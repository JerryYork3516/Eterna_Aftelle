@preconcurrency import AVFoundation
import Foundation
#if DEBUG
import OSLog
#endif

nonisolated enum MacSpeechAudioInputFormat {
    static let sampleRate: Double = 24_000
    static let channelCount: AVAudioChannelCount = 1
    static let packetDurationMilliseconds = 20
    static let packetSampleCount = 480
    static let packetByteCount = 960
    static let frameCapacity = 25
    static let description = "24000 Hz / mono / signed PCM16 LE / interleaved"

    static func tapBufferSize(for sampleRate: Double) -> AVAudioFrameCount {
        AVAudioFrameCount(max(1, Int((sampleRate / 100).rounded())))
    }
}

nonisolated enum MacSpeechAudioActivityEvidenceKind:
    String,
    Sendable,
    Equatable {
    case none
    case listeningNearEnd = "listening_near_end"
    case sourceGatedNearEnd = "source_gated_near_end"

    static func classify(
        before: MacSpeechAcousticObservationSnapshot,
        after: MacSpeechAcousticObservationSnapshot
    ) -> Self {
        guard after.captureFrameIndex > before.captureFrameIndex,
              after.playbackSequence == before.playbackSequence,
              after.isPlaybackActive == before.isPlaybackActive,
              after.aecEnabled,
              after.aecActive else { return .none }
        return classify(observation: after)
    }

    static func classify(
        observation: MacSpeechAcousticObservationSnapshot
    ) -> Self {
        guard observation.captureFrameIndex > 0,
              observation.aecEnabled,
              observation.aecActive else { return .none }
        if observation.isPlaybackActive {
            return observation.sourceGateOpen
                    && observation.sourceGateEpoch > 0
                    && (observation.inputClassification == .nearEndSpeech
                        || observation.inputClassification == .doubleTalk)
                ? .sourceGatedNearEnd : .none
        }
        let outputRMS = max(
            observation.processedCaptureRMS,
            observation.linearAECOutputRMS
        )
        return observation.inputClassification == .nearEndSpeech
                && max(observation.rawCaptureRMS, outputRMS)
                    >= MacSpeechAcousticEchoHost.minimumNearEndRMS
            ? .listeningNearEnd : .none
    }
}

nonisolated struct MacSpeechCaptureGenerationFence: Sendable {
    private(set) var minimumHostTimeNanoseconds: UInt64 = 0

    mutating func advance(to timestampNanoseconds: UInt64) {
        minimumHostTimeNanoseconds = max(
            minimumHostTimeNanoseconds,
            timestampNanoseconds
        )
    }

    func accepts(hostTimeNanoseconds: UInt64?) -> Bool {
        guard minimumHostTimeNanoseconds > 0 else { return true }
        guard let hostTimeNanoseconds else { return false }
        return hostTimeNanoseconds >= minimumHostTimeNanoseconds
    }
}

nonisolated protocol MacSpeechAudioFrameSourcing: Sendable {
    func activeCaptureGeneration() async -> UInt64?
    func isCaptureGenerationActive(_ generation: UInt64) async -> Bool
    func drainFrames(maxCount: Int) async -> [MacSpeechAudioFrame]
    func discardPendingAudioForGenerationTransition() async
    func interruptionAcousticSnapshot() async
        -> MacSpeechInterruptionAcousticSnapshot?
    func residentAcousticSnapshot() async
        -> MacSpeechResidentAcousticSnapshot?
}

nonisolated extension MacSpeechAudioFrameSourcing {
    func discardPendingAudioForGenerationTransition() async {}
    func interruptionAcousticSnapshot() async
        -> MacSpeechInterruptionAcousticSnapshot? { nil }
    func residentAcousticSnapshot() async
        -> MacSpeechResidentAcousticSnapshot? { nil }
}

nonisolated struct MacSpeechInterruptionAcousticSnapshot:
    Sendable,
    Equatable {
    let sourceGateSequence: UInt64
    let nearEndDetected: Bool
    let farEndActive: Bool
    let sourceGateOpen: Bool
    let renderReferenceConfidence: Double
    let routeStable: Bool
    let inputDeviceAvailable: Bool
    let outputDeviceAvailable: Bool
}

nonisolated struct MacSpeechResidentAcousticSnapshot:
    Sendable,
    Equatable {
    let captureGeneration: UInt64
    let captureFrameIndex: UInt64
    let captureHostTimeNanoseconds: UInt64?
    let playbackSequence: UInt64
    let residentPlaybackActive: Bool
    let lastAudibleResidentRenderTimestampNanoseconds: UInt64?
    let renderReferenceAvailable: Bool
    let renderReferenceRMS: Double?
    let renderHostTimeNanoseconds: UInt64?
    let rawCaptureRMS: Double
    let processedCaptureRMS: Double
    let linearAECOutputRMS: Double
    let renderCaptureCorrelation: Double
    let residualRenderCorrelation: Double
    let linearRenderCorrelation: Double
    let inputClassification: MacSpeechAcousticInputClassification
    let sourceGateOpen: Bool
    let sourceGateEpoch: UInt64
    let aecEnabled: Bool
    let aecActive: Bool
    let renderCaptureIsolationEstablished: Bool
    let sourceAlignmentLocked: Bool
    let sourceAlignmentDelayMilliseconds: Int?
    let estimatedDelayMilliseconds: Int
    let erlDecibels: Double
    let erleDecibels: Double
    let renderCaptureSkewFrames: Int64
    let driftTrend: String
    let routeStable: Bool
    let inputDeviceAvailable: Bool
    let outputDeviceAvailable: Bool
}

nonisolated struct MacSpeechAudioFrame: Sendable, Equatable {
    let captureGeneration: UInt64
    let sequenceNumber: UInt64
    let monotonicTimestampNanoseconds: UInt64
    let pcm16Bytes: Data
    let activity: Float
    let activityEvidenceKind: MacSpeechAudioActivityEvidenceKind
    let residentPlaybackSequence: UInt64
    let residentPlaybackActive: Bool
    let lastAudibleResidentRenderTimestampNanoseconds: UInt64?
    let sourceGateEpoch: UInt64
    let acousticSnapshot: MacSpeechAcousticObservationSnapshot?

    init(
        captureGeneration: UInt64,
        sequenceNumber: UInt64,
        monotonicTimestampNanoseconds: UInt64,
        pcm16Bytes: Data,
        activity: Float,
        activityEvidenceKind: MacSpeechAudioActivityEvidenceKind = .none,
        residentPlaybackSequence: UInt64 = 0,
        residentPlaybackActive: Bool = false,
        lastAudibleResidentRenderTimestampNanoseconds: UInt64? = nil,
        sourceGateEpoch: UInt64 = 0,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot? = nil
    ) {
        self.captureGeneration = captureGeneration
        self.sequenceNumber = sequenceNumber
        self.monotonicTimestampNanoseconds =
            monotonicTimestampNanoseconds
        self.pcm16Bytes = pcm16Bytes
        self.activity = activity
        self.activityEvidenceKind = activityEvidenceKind
        self.residentPlaybackSequence = residentPlaybackSequence
        self.residentPlaybackActive = residentPlaybackActive
        self.lastAudibleResidentRenderTimestampNanoseconds =
            lastAudibleResidentRenderTimestampNanoseconds
        self.sourceGateEpoch = sourceGateEpoch
        self.acousticSnapshot = acousticSnapshot
    }
}

nonisolated struct MacSpeechAudioFrameBufferStats: Sendable, Equatable {
    let generatedCount: UInt64
    let droppedCount: UInt64
    let rejectedStaleCount: UInt64
    let queuedCount: Int
    let latestActivity: Float
}

nonisolated final class MacSpeechAudioFrameBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var activeGeneration: UInt64?
    private var frames: [MacSpeechAudioFrame] = []
    private var nextSequence: UInt64 = 0
    private var lastTimestamp: UInt64 = 0
    private var generatedCount: UInt64 = 0
    private var droppedCount: UInt64 = 0
    private var rejectedStaleCount: UInt64 = 0
    private var latestActivity: Float = 0

    init(capacity: Int = MacSpeechAudioInputFormat.frameCapacity) {
        precondition(capacity > 0)
        self.capacity = capacity
        frames.reserveCapacity(capacity)
    }

    func begin(generation: UInt64) {
        lock.withLock {
            activeGeneration = generation
            frames.removeAll(keepingCapacity: true)
            nextSequence = 0
            lastTimestamp = 0
            generatedCount = 0
            droppedCount = 0
            rejectedStaleCount = 0
            latestActivity = 0
        }
    }

    func end(generation: UInt64) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            activeGeneration = nil
            frames.removeAll(keepingCapacity: true)
        }
    }

    @discardableResult
    func append(
        pcm16Bytes: Data,
        activity: Float,
        generation: UInt64,
        timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds,
        activityEvidenceKind: MacSpeechAudioActivityEvidenceKind = .none,
        residentPlaybackSequence: UInt64 = 0,
        residentPlaybackActive: Bool = false,
        lastAudibleResidentRenderTimestampNanoseconds: UInt64? = nil,
        sourceGateEpoch: UInt64 = 0,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot? = nil
    ) -> Bool {
        lock.withLock {
            guard activeGeneration == generation, !pcm16Bytes.isEmpty else {
                rejectedStaleCount &+= 1
                return false
            }
            if frames.count == capacity {
                frames.removeFirst()
                droppedCount &+= 1
            }
            nextSequence &+= 1
            let monotonicTimestamp = timestamp > lastTimestamp
                ? timestamp
                : lastTimestamp &+ 1
            lastTimestamp = monotonicTimestamp
            latestActivity = activity.isFinite
                ? min(max(activity, 0), 1)
                : 0
            frames.append(
                MacSpeechAudioFrame(
                    captureGeneration: generation,
                    sequenceNumber: nextSequence,
                    monotonicTimestampNanoseconds: monotonicTimestamp,
                    pcm16Bytes: pcm16Bytes,
                    activity: latestActivity,
                    activityEvidenceKind: activityEvidenceKind,
                    residentPlaybackSequence: residentPlaybackSequence,
                    residentPlaybackActive: residentPlaybackActive,
                    lastAudibleResidentRenderTimestampNanoseconds:
                        lastAudibleResidentRenderTimestampNanoseconds,
                    sourceGateEpoch: sourceGateEpoch,
                    acousticSnapshot: acousticSnapshot
                )
            )
            generatedCount &+= 1
            return true
        }
    }

    func drain(maxCount: Int) -> [MacSpeechAudioFrame] {
        lock.withLock {
            guard maxCount > 0, !frames.isEmpty else { return [] }
            let count = min(maxCount, frames.count)
            let drained = Array(frames.prefix(count))
            frames.removeFirst(count)
            return drained
        }
    }

    func stats() -> MacSpeechAudioFrameBufferStats {
        lock.withLock {
            MacSpeechAudioFrameBufferStats(
                generatedCount: generatedCount,
                droppedCount: droppedCount,
                rejectedStaleCount: rejectedStaleCount,
                queuedCount: frames.count,
                latestActivity: latestActivity
            )
        }
    }
}

nonisolated enum MacSpeechPCM16Encoder {
    static func encode(samples: [Float]) -> Data {
        var bytes = [UInt8](repeating: 0, count: samples.count * 2)
        for (index, sample) in samples.enumerated() {
            let value = pcm16Value(for: sample)
            let bits = UInt16(bitPattern: value)
            bytes[index * 2] = UInt8(truncatingIfNeeded: bits)
            bytes[index * 2 + 1] = UInt8(truncatingIfNeeded: bits >> 8)
        }
        return Data(bytes)
    }

    private static func pcm16Value(for sample: Float) -> Int16 {
        guard sample.isFinite else { return 0 }
        let clamped = min(max(sample, -1), 1)
        let scaled = clamped < 0
            ? clamped * 32_768
            : clamped * 32_767
        return Int16(scaled.rounded(.toNearestOrAwayFromZero))
    }
}

nonisolated struct MacSpeechPCM16Packet: Sendable, Equatable {
    let bytes: Data
    let activity: Float
    let activityEvidenceKind: MacSpeechAudioActivityEvidenceKind
    let acousticSnapshot: MacSpeechAcousticObservationSnapshot?
}

nonisolated struct MacSpeechPCM16Packetizer: Sendable {
    private struct EvidenceSpan: Sendable {
        var sampleCount: Int
        let kind: MacSpeechAudioActivityEvidenceKind
        let acousticSnapshot: MacSpeechAcousticObservationSnapshot?
    }

    private var pendingSamples: [Float] = []
    private var evidenceSpans: [EvidenceSpan] = []

    mutating func append(
        samples: [Float],
        activityEvidenceKind: MacSpeechAudioActivityEvidenceKind = .none,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot? = nil
    ) -> [MacSpeechPCM16Packet] {
        pendingSamples.append(contentsOf: samples)
        evidenceSpans.append(EvidenceSpan(
            sampleCount: samples.count,
            kind: activityEvidenceKind,
            acousticSnapshot: acousticSnapshot
        ))
        var packets: [MacSpeechPCM16Packet] = []
        while pendingSamples.count >= MacSpeechAudioInputFormat.packetSampleCount {
            let packetSamples = Array(
                pendingSamples.prefix(
                    MacSpeechAudioInputFormat.packetSampleCount
                )
            )
            pendingSamples.removeFirst(
                MacSpeechAudioInputFormat.packetSampleCount
            )
            let evidence = takeEvidence(
                sampleCount: MacSpeechAudioInputFormat.packetSampleCount
            )
            packets.append(MacSpeechPCM16Packet(
                bytes: MacSpeechPCM16Encoder.encode(samples: packetSamples),
                activity: Self.activity(samples: packetSamples),
                activityEvidenceKind: evidence.kind,
                acousticSnapshot: evidence.acousticSnapshot
            ))
        }
        return packets
    }

    mutating func reset() {
        pendingSamples.removeAll(keepingCapacity: true)
        evidenceSpans.removeAll(keepingCapacity: true)
    }

    private mutating func takeEvidence(
        sampleCount: Int
    ) -> (
        kind: MacSpeechAudioActivityEvidenceKind,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot?
    ) {
        var remaining = sampleCount
        var selectedKind = MacSpeechAudioActivityEvidenceKind.none
        var selectedSnapshot: MacSpeechAcousticObservationSnapshot?
        while remaining > 0, !evidenceSpans.isEmpty {
            let consumed = min(remaining, evidenceSpans[0].sampleCount)
            let span = evidenceSpans[0]
            switch span.kind {
            case .sourceGatedNearEnd:
                selectedKind = .sourceGatedNearEnd
                selectedSnapshot = span.acousticSnapshot
            case .listeningNearEnd:
                if selectedKind != .sourceGatedNearEnd {
                    selectedKind = .listeningNearEnd
                    selectedSnapshot = span.acousticSnapshot
                }
            case .none:
                if selectedKind == .none {
                    selectedSnapshot = span.acousticSnapshot
                }
            }
            remaining -= consumed
            if consumed == evidenceSpans[0].sampleCount {
                evidenceSpans.removeFirst()
            } else {
                evidenceSpans[0].sampleCount -= consumed
            }
        }
        return (selectedKind, selectedSnapshot)
    }

    private static func activity(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let finiteSquares = samples.reduce(Float.zero) { partial, value in
            guard value.isFinite else { return partial }
            let clamped = min(max(value, -1), 1)
            return partial + clamped * clamped
        }
        return min(sqrt(finiteSquares / Float(samples.count)), 1)
    }
}

nonisolated struct MacSpeechNativeInputFormat: Sendable, Equatable {
    let sampleRate: Double
    let channelCount: UInt32
}

nonisolated enum MacSpeechAudioCaptureError: String, Error, Sendable {
    case invalidInputFormat = "invalid_input_format"
    case converterUnavailable = "audio_converter_unavailable"
    case conversionFailed = "audio_conversion_failed"
    case voiceProcessingUnavailable = "voice_processing_unavailable"
    case engineStartFailed = "audio_engine_start_failed"
}

nonisolated protocol MacSpeechAudioCapturing: AnyObject, Sendable {
    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat
    func stop()
    func discardPendingAudioForGenerationTransition()
    func routeWillRebuild()
    func routeDidRebuild()
    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot?
    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot?
    func resetAcousticEchoDiagnostics()
}

nonisolated extension MacSpeechAudioCapturing {
    func discardPendingAudioForGenerationTransition() {}
    func routeWillRebuild() {}
    func routeDidRebuild() {}
    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot? { nil }
    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot? { nil }
    func resetAcousticEchoDiagnostics() {}
}

nonisolated final class MacSpeechAudioConverter: @unchecked Sendable {
    private final class InputState: @unchecked Sendable {
        var supplied = false
    }

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let inputSampleRate: Double
    private var packetizer = MacSpeechPCM16Packetizer()

    init(inputFormat: AVAudioFormat) throws {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MacSpeechAudioCaptureError.invalidInputFormat
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: MacSpeechAudioInputFormat.sampleRate,
            channels: MacSpeechAudioInputFormat.channelCount,
            interleaved: false
        ), let converter = AVAudioConverter(
            from: inputFormat,
            to: outputFormat
        ) else {
            throw MacSpeechAudioCaptureError.converterUnavailable
        }
        converter.channelMap = [0]
        self.converter = converter
        self.outputFormat = outputFormat
        inputSampleRate = inputFormat.sampleRate
    }

    func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        activityEvidenceKind: MacSpeechAudioActivityEvidenceKind = .none,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot? = nil
    ) throws -> [MacSpeechPCM16Packet] {
        try lock.withLock {
            let ratio = MacSpeechAudioInputFormat.sampleRate / inputSampleRate
            let estimatedFrames = ceil(Double(inputBuffer.frameLength) * ratio) + 8
            let capacity = AVAudioFrameCount(max(1, min(estimatedFrames, 8_192)))
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }

            let inputState = InputState()
            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { _, inputStatus in
                guard !inputState.supplied else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputState.supplied = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            guard conversionError == nil,
                  status != .error,
                  outputBuffer.frameLength > 0,
                  let samples = outputBuffer.floatChannelData?[0]
            else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }

            let count = Int(outputBuffer.frameLength)
            let values = Array(UnsafeBufferPointer(start: samples, count: count))
            return packetizer.append(
                samples: values,
                activityEvidenceKind: activityEvidenceKind,
                acousticSnapshot: acousticSnapshot
            )
        }
    }

    func convert(
        captureSpans: [MacSpeechAcousticCaptureSpan]
    ) throws -> [MacSpeechPCM16Packet] {
        var packets: [MacSpeechPCM16Packet] = []
        for span in captureSpans where !span.samples.isEmpty {
            let buffer = try MacSpeechFloatMono48kConverter.makeBuffer(
                samples: span.samples
            )
            packets.append(contentsOf: try convert(
                buffer,
                activityEvidenceKind:
                    MacSpeechAudioActivityEvidenceKind.classify(
                        observation: span.observation
                    ),
                acousticSnapshot: span.observation
            ))
        }
        return packets
    }

    func resetForGenerationTransition() {
        lock.withLock {
            converter.reset()
            packetizer.reset()
        }
    }
}

nonisolated final class MacSpeechFloatMono48kConverter: @unchecked Sendable {
    private final class InputState: @unchecked Sendable {
        var supplied = false
    }

    static func makeBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        guard !samples.isEmpty,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(MacSpeechAcousticEchoHost.sampleRate),
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let destination = buffer.floatChannelData?[0] else {
            throw MacSpeechAudioCaptureError.conversionFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        destination.update(from: samples, count: samples.count)
        return buffer
    }

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let inputSampleRate: Double

    init(inputFormat: AVAudioFormat) throws {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(MacSpeechAcousticEchoHost.sampleRate),
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(
                from: inputFormat,
                to: outputFormat
              ) else {
            throw MacSpeechAudioCaptureError.converterUnavailable
        }
        converter.channelMap = [0]
        self.converter = converter
        self.outputFormat = outputFormat
        inputSampleRate = inputFormat.sampleRate
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> [Float] {
        try lock.withLock {
            let ratio = outputFormat.sampleRate / inputSampleRate
            let estimatedFrames = ceil(Double(inputBuffer.frameLength) * ratio)
                + 16
            let capacity = AVAudioFrameCount(
                max(1, min(estimatedFrames, 16_384))
            )
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            let inputState = InputState()
            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { _, inputStatus in
                guard !inputState.supplied else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputState.supplied = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            guard conversionError == nil,
                  status != .error,
                  outputBuffer.frameLength > 0,
                  let samples = outputBuffer.floatChannelData?[0] else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            return Array(UnsafeBufferPointer(
                start: samples,
                count: Int(outputBuffer.frameLength)
            ))
        }
    }

    func resetForGenerationTransition() {
        lock.withLock { converter.reset() }
    }
}

nonisolated final class SystemMacSpeechVoiceProcessingEngine:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let captureProcessingLock = NSLock()
    private let renderConverterLock = NSLock()
    private let audioProcessingMode: MacSpeechAudioProcessingMode
    private let acousticEchoHost: MacSpeechAcousticEchoHost
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var captureAECConverter: MacSpeechFloatMono48kConverter?
    private var captureOutputConverter: MacSpeechAudioConverter?
    private var renderAECConverter: MacSpeechFloatMono48kConverter?
    private var isConfigured = false
    private var isCaptureActive = false
    private var isOutputPrepared = false
    private var isOutputPlaying = false
    private var isInputMutedForOutput = false
    private var isRenderReferenceTapInstalled = false
    private var outputFormat: AVAudioFormat?
    private var routeRebuildWasConfigured = false
    private var outputPresentationLatencySeconds = 0.0
    private var capturePresentationLatencySeconds = 0.0
    private var captureGenerationFence =
        MacSpeechCaptureGenerationFence()
    #if DEBUG
    private static let audioUnitDiagnosticLogger = Logger(
        subsystem: "com.eterna.aftelle",
        category: "AudioUnitAttribution"
    )
    #endif

    init(
        audioProcessingMode: MacSpeechAudioProcessingMode = .webRTCAEC3,
        acousticEchoHost: MacSpeechAcousticEchoHost? = nil
    ) {
        self.audioProcessingMode = audioProcessingMode
        if let acousticEchoHost {
            self.acousticEchoHost = acousticEchoHost
        } else {
            #if AFTELLE_WEBRTC_AEC3
            self.acousticEchoHost = MacSpeechAcousticEchoHost(
                mode: audioProcessingMode,
                backend: audioProcessingMode == .webRTCAEC3
                    ? MacSpeechWebRTCAECProcessor() : nil
            )
            #else
            self.acousticEchoHost = MacSpeechAcousticEchoHost(
                mode: audioProcessingMode
            )
            #endif
        }
    }

    func startCapture(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        try lock.withLock {
            try configureIfNeeded()
            guard let engine else {
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0,
                  inputFormat.channelCount > 0 else {
                throw MacSpeechAudioCaptureError.invalidInputFormat
            }
            if isCaptureActive {
                return describe(inputFormat)
            }

            guard captureAECConverter != nil,
                  captureOutputConverter != nil else {
                throw MacSpeechAudioCaptureError.converterUnavailable
            }
            inputNode.installTap(
                onBus: 0,
                bufferSize: MacSpeechAudioInputFormat.tapBufferSize(
                    for: inputFormat.sampleRate
                ),
                format: inputFormat
            ) { [weak self] buffer, when in
                self?.processCapture(
                    buffer,
                    hostTimeNanoseconds: Self.hostTimeNanoseconds(when),
                    generation: generation,
                    frameBuffer: frameBuffer
                )
            }
            logAudioUnitLifecycle("capture_tap_installed")
            do {
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
            } catch {
                inputNode.removeTap(onBus: 0)
                tearDownIfIdle()
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            refreshAcousticEchoPresentationLatencyLocked()
            if !isOutputPlaying,
               audioProcessingMode == .appleVoiceProcessing {
                inputNode.isVoiceProcessingInputMuted = false
                isInputMutedForOutput = false
            }
            isCaptureActive = true
            return describe(inputFormat)
        }
    }

    func stopCapture() {
        lock.withLock {
            guard isCaptureActive, let engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            isCaptureActive = false
            logAudioUnitLifecycle("capture_tap_removed")
            tearDownIfIdle()
        }
    }

    func discardPendingAudioForGenerationTransition() {
        captureProcessingLock.withLock {
            captureGenerationFence.advance(
                to: DispatchTime.now().uptimeNanoseconds
            )
            let converters = lock.withLock {
                (captureAECConverter, captureOutputConverter)
            }
            converters.0?.resetForGenerationTransition()
            converters.1?.resetForGenerationTransition()
            acousticEchoHost.discardPendingCaptureForGenerationTransition()
        }
    }

    func prepareOutput() throws -> AVAudioFormat {
        try lock.withLock {
            try configureIfNeeded()
            guard let outputFormat else {
                throw MacSpeechAudioCaptureError.invalidInputFormat
            }
            isOutputPrepared = true
            return outputFormat
        }
    }

    func scheduleOutput(
        _ buffer: AVAudioPCMBuffer,
        completion: @escaping @Sendable () -> Void
    ) throws {
        try lock.withLock {
            guard isOutputPrepared,
                  let playerNode else {
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            playerNode.scheduleBuffer(
                buffer,
                completionCallbackType: .dataPlayedBack
            ) { _ in completion() }
        }
    }

    func startOutput() throws {
        try lock.withLock {
            guard isOutputPrepared,
                  let engine,
                  let playerNode else {
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            let inputNode = engine.inputNode
            acousticEchoHost.playbackStarted()
            if audioProcessingMode == .appleVoiceProcessing {
                inputNode.isVoiceProcessingInputMuted = true
                isInputMutedForOutput = true
            }
            isOutputPlaying = true
            do {
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
                if !playerNode.isPlaying {
                    playerNode.play()
                }
                refreshAcousticEchoPresentationLatencyLocked()
            } catch {
                isOutputPlaying = false
                acousticEchoHost.playbackStopped()
                unmuteInput()
                throw error
            }
        }
    }

    func finishOutputPlayback() {
        lock.withLock {
            isOutputPlaying = false
            acousticEchoHost.playbackCompleted()
            unmuteInput()
        }
    }

    func clearScheduledOutput() {
        lock.withLock {
            playerNode?.stop()
            isOutputPlaying = false
            acousticEchoHost.playbackStopped()
            unmuteInput()
        }
    }

    func stopOutput() {
        lock.withLock {
            playerNode?.stop()
            isOutputPlaying = false
            acousticEchoHost.playbackStopped()
            unmuteInput()
            if !isCaptureActive {
                engine?.stop()
            }
        }
    }

    func closeOutput() {
        lock.withLock {
            playerNode?.stop()
            isOutputPlaying = false
            acousticEchoHost.playbackStopped()
            unmuteInput()
            isOutputPrepared = false
            tearDownIfIdle()
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        let localFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        guard localFormat.sampleRate > 0,
              localFormat.channelCount > 0 else {
            throw MacSpeechAudioCaptureError.invalidInputFormat
        }
        engine.connect(
            playerNode,
            to: engine.mainMixerNode,
            format: localFormat
        )
        let inputNode = engine.inputNode
        if audioProcessingMode == .appleVoiceProcessing {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
            } catch {
                throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
            }
            guard inputNode.isVoiceProcessingEnabled,
                  engine.outputNode.isVoiceProcessingEnabled,
                  inputNode.setMutedSpeechActivityEventListener({
                    [weak self] event in
                    self?.handleMutedSpeechActivity(event)
                  }) else {
                throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
            }
        } else if inputNode.isVoiceProcessingEnabled
                    || engine.outputNode.isVoiceProcessingEnabled {
            throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
        }
        try rebuildAudioFormatsLocked(engine: engine, localFormat: localFormat)
        installRenderReferenceTapLocked(
            playerNode: playerNode,
            format: localFormat
        )
        _ = acousticEchoHost.configure()
        self.engine = engine
        self.playerNode = playerNode
        outputFormat = localFormat
        isConfigured = true
    }

    private func tearDownIfIdle() {
        guard !isCaptureActive, !isOutputPrepared else { return }
        unmuteInput()
        engine?.stop()
        if isConfigured,
           let engine,
           let playerNode {
            removeRenderReferenceTapLocked(playerNode: playerNode)
            engine.disconnectNodeOutput(playerNode)
            engine.detach(playerNode)
            engine.reset()
        }
        playerNode = nil
        engine = nil
        outputFormat = nil
        captureAECConverter = nil
        captureOutputConverter = nil
        renderConverterLock.withLock { renderAECConverter = nil }
        resetAcousticEchoPresentationLatencyLocked()
        isConfigured = false
    }

    private func handleMutedSpeechActivity(
        _ event: AVAudioVoiceProcessingSpeechActivityEvent
    ) {
        guard event == .started else { return }
        lock.withLock {
            guard isOutputPlaying, isInputMutedForOutput else { return }
            unmuteInput()
        }
    }

    func routeWillRebuild() {
        lock.withLock {
            guard isConfigured else { return }
            routeRebuildWasConfigured = true
            logAudioUnitLifecycle("route_will_rebuild")
            if let playerNode {
                removeRenderReferenceTapLocked(playerNode: playerNode)
            }
            acousticEchoHost.routeWillRebuild()
            resetAcousticEchoPresentationLatencyLocked()
            captureAECConverter = nil
            captureOutputConverter = nil
            renderConverterLock.withLock { renderAECConverter = nil }
        }
    }

    func routeDidRebuild() {
        lock.withLock {
            guard routeRebuildWasConfigured else { return }
            defer { routeRebuildWasConfigured = false }
            do {
                if !isConfigured {
                    try configureIfNeeded()
                } else if let engine {
                    let localFormat = engine.mainMixerNode.outputFormat(forBus: 0)
                    try rebuildAudioFormatsLocked(
                        engine: engine,
                        localFormat: localFormat
                    )
                    if let playerNode {
                        installRenderReferenceTapLocked(
                            playerNode: playerNode,
                            format: localFormat
                        )
                    }
                }
                _ = acousticEchoHost.routeDidRebuild()
                if let engine, engine.isRunning {
                    refreshAcousticEchoPresentationLatencyLocked()
                }
                logAudioUnitLifecycle("route_did_rebuild")
            } catch {
                captureAECConverter = nil
                captureOutputConverter = nil
                renderConverterLock.withLock { renderAECConverter = nil }
                logAudioUnitLifecycle("route_rebuild_failed")
            }
        }
    }

    func resetForRouteChange() {
        routeWillRebuild()
        routeDidRebuild()
    }

    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot {
        acousticEchoHost.snapshot()
    }

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot {
        acousticEchoHost.acousticObservationSnapshot()
    }

    func resetAcousticEchoDiagnostics() {
        acousticEchoHost.resetDiagnostics()
    }

    private func processCapture(
        _ buffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?,
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) {
        captureProcessingLock.withLock {
            guard captureGenerationFence.accepts(
                hostTimeNanoseconds: hostTimeNanoseconds
            ) else { return }
            processCaptureLocked(
                buffer,
                hostTimeNanoseconds: hostTimeNanoseconds,
                generation: generation,
                frameBuffer: frameBuffer
            )
        }
    }

    private func processCaptureLocked(
        _ buffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?,
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let converters = lock.withLock {
            (captureAECConverter, captureOutputConverter)
        }
        guard let inputConverter = converters.0,
              let outputConverter = converters.1,
              let inputSamples = try? inputConverter.convert(buffer) else {
            return
        }
        let captureSpans = acousticEchoHost.processCaptureSpans(
            inputSamples,
            hostTimeNanoseconds: hostTimeNanoseconds
        )
        let acoustic = acousticEchoHost.acousticObservationSnapshot()
        if !captureSpans.isEmpty,
           let packets = try? outputConverter.convert(
               captureSpans: captureSpans
           ) {
            for packet in packets {
                let packetAcoustic = packet.acousticSnapshot
                    ?? acoustic
                frameBuffer.append(
                    pcm16Bytes: packet.bytes,
                    activity: packet.activity,
                    generation: generation,
                    timestamp: packetAcoustic.captureHostTimeNanoseconds
                        ?? DispatchTime.now().uptimeNanoseconds,
                    activityEvidenceKind: packet.activityEvidenceKind,
                    residentPlaybackSequence:
                        packetAcoustic.playbackSequence,
                    residentPlaybackActive:
                        packetAcoustic.isPlaybackActive,
                    lastAudibleResidentRenderTimestampNanoseconds:
                        packetAcoustic
                            .lastAudibleRenderHostTimeNanoseconds,
                    sourceGateEpoch: packet.activityEvidenceKind
                        == .sourceGatedNearEnd
                        ? packetAcoustic.sourceGateEpoch : 0,
                    acousticSnapshot: packetAcoustic
                )
            }
        }
        acousticEchoHost.recordCaptureProcessingDuration(
            nanoseconds: DispatchTime.now().uptimeNanoseconds &- startedAt
        )
        lock.withLock { updateAcousticEchoDelayLocked() }
    }

    private func rebuildAudioFormatsLocked(
        engine: AVAudioEngine,
        localFormat: AVAudioFormat
    ) throws {
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              localFormat.sampleRate > 0,
              localFormat.channelCount > 0,
              let aecFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(MacSpeechAcousticEchoHost.sampleRate),
                channels: 1,
                interleaved: false
              ) else {
            throw MacSpeechAudioCaptureError.invalidInputFormat
        }
        captureAECConverter = try MacSpeechFloatMono48kConverter(
            inputFormat: inputFormat
        )
        captureOutputConverter = try MacSpeechAudioConverter(
            inputFormat: aecFormat
        )
        let renderConverter = try MacSpeechFloatMono48kConverter(
            inputFormat: localFormat
        )
        renderConverterLock.withLock {
            renderAECConverter = renderConverter
        }
        outputFormat = localFormat
    }

    private func installRenderReferenceTapLocked(
        playerNode: AVAudioPlayerNode,
        format: AVAudioFormat
    ) {
        guard !isRenderReferenceTapInstalled else { return }
        playerNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            format: format
        ) { [weak self] buffer, when in
            self?.processRenderedOutput(
                buffer,
                hostTimeNanoseconds: Self.hostTimeNanoseconds(when)
            )
        }
        isRenderReferenceTapInstalled = true
        logAudioUnitLifecycle("render_tap_installed")
    }

    private func removeRenderReferenceTapLocked(
        playerNode: AVAudioPlayerNode
    ) {
        guard isRenderReferenceTapInstalled else { return }
        playerNode.removeTap(onBus: 0)
        isRenderReferenceTapInstalled = false
        logAudioUnitLifecycle("render_tap_removed")
    }

    private func processRenderedOutput(
        _ buffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?
    ) {
        let converter = renderConverterLock.withLock { renderAECConverter }
        guard let converter else {
            acousticEchoHost.renderConversionFailed()
            return
        }
        do {
            acousticEchoHost.processRender(
                try converter.convert(buffer),
                hostTimeNanoseconds: hostTimeNanoseconds
            )
        } catch {
            acousticEchoHost.renderConversionFailed()
        }
    }

    private func updateAcousticEchoDelayLocked() {
        acousticEchoHost.updateDelay(
            outputPresentationLatencySeconds:
                outputPresentationLatencySeconds,
            capturePresentationLatencySeconds:
                capturePresentationLatencySeconds
        )
    }

    private func refreshAcousticEchoPresentationLatencyLocked() {
        guard let engine, engine.isRunning else { return }
        #if DEBUG
        let diagnosticTimestamp = DispatchTime.now().uptimeNanoseconds
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_latency_read phase=output_will_read sample=\(diagnosticTimestamp)"
        )
        #endif
        let outputPresentationLatency = engine.outputNode.presentationLatency
        #if DEBUG
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_latency_read phase=output_did_read sample=\(diagnosticTimestamp) value_ms=\(outputPresentationLatency * 1_000, format: .fixed(precision: 3))"
        )
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_latency_read phase=input_will_read sample=\(diagnosticTimestamp)"
        )
        #endif
        let capturePresentationLatency = engine.inputNode.presentationLatency
        outputPresentationLatencySeconds = outputPresentationLatency
        capturePresentationLatencySeconds = capturePresentationLatency
        #if DEBUG
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_latency_read phase=input_did_read sample=\(diagnosticTimestamp) value_ms=\(capturePresentationLatency * 1_000, format: .fixed(precision: 3))"
        )
        #endif
        acousticEchoHost.updateDelay(
            outputPresentationLatencySeconds:
                outputPresentationLatencySeconds,
            capturePresentationLatencySeconds:
                capturePresentationLatencySeconds
        )
    }

    private func resetAcousticEchoPresentationLatencyLocked() {
        outputPresentationLatencySeconds = 0
        capturePresentationLatencySeconds = 0
    }

    private func logAudioUnitLifecycle(_ phase: String) {
        #if DEBUG
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_lifecycle phase=\(phase, privacy: .public) configured=\(self.isConfigured) capture_active=\(self.isCaptureActive) output_prepared=\(self.isOutputPrepared) output_playing=\(self.isOutputPlaying) render_tap=\(self.isRenderReferenceTapInstalled)"
        )
        #endif
    }

    private static func hostTimeNanoseconds(_ time: AVAudioTime) -> UInt64? {
        guard time.isHostTimeValid else { return nil }
        let seconds = AVAudioTime.seconds(forHostTime: time.hostTime)
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return UInt64((seconds * 1_000_000_000).rounded())
    }

    private func unmuteInput() {
        guard isInputMutedForOutput else { return }
        engine?.inputNode.isVoiceProcessingInputMuted = false
        isInputMutedForOutput = false
    }

    private func describe(
        _ format: AVAudioFormat
    ) -> MacSpeechNativeInputFormat {
        MacSpeechNativeInputFormat(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount
        )
    }
}

nonisolated final class SystemMacSpeechAudioCapture:
    MacSpeechAudioCapturing, @unchecked Sendable
{
    private let audioEngine: SystemMacSpeechVoiceProcessingEngine

    init(
        audioEngine: SystemMacSpeechVoiceProcessingEngine =
            SystemMacSpeechVoiceProcessingEngine()
    ) {
        self.audioEngine = audioEngine
    }

    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        try audioEngine.startCapture(
            generation: generation,
            frameBuffer: frameBuffer
        )
    }

    func stop() {
        audioEngine.stopCapture()
    }

    func discardPendingAudioForGenerationTransition() {
        audioEngine.discardPendingAudioForGenerationTransition()
    }

    func routeWillRebuild() {
        audioEngine.routeWillRebuild()
    }

    func routeDidRebuild() {
        audioEngine.routeDidRebuild()
    }

    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot? {
        audioEngine.acousticEchoSnapshot()
    }

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot? {
        audioEngine.acousticObservationSnapshot()
    }

    func resetAcousticEchoDiagnostics() {
        audioEngine.resetAcousticEchoDiagnostics()
    }
}
