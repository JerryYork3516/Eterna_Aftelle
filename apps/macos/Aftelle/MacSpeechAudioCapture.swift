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
    let contentTimestampNanoseconds: UInt64?

    init(
        bytes: Data,
        activity: Float,
        activityEvidenceKind: MacSpeechAudioActivityEvidenceKind,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot?,
        contentTimestampNanoseconds: UInt64? = nil
    ) {
        self.bytes = bytes
        self.activity = activity
        self.activityEvidenceKind = activityEvidenceKind
        self.acousticSnapshot = acousticSnapshot
        self.contentTimestampNanoseconds = contentTimestampNanoseconds
    }
}

nonisolated struct MacSpeechPCM16Packetizer: Sendable {
    private struct EvidenceSpan: Sendable {
        var sampleCount: Int
        let kind: MacSpeechAudioActivityEvidenceKind
        let acousticSnapshot: MacSpeechAcousticObservationSnapshot?
    }

    private var pendingSamples: [Float] = []
    private var evidenceSpans: [EvidenceSpan] = []
    private var pendingTimestamp: UInt64?

    mutating func append(
        samples: [Float],
        activityEvidenceKind: MacSpeechAudioActivityEvidenceKind = .none,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot? = nil,
        contentTimestampNanoseconds: UInt64? = nil
    ) -> [MacSpeechPCM16Packet] {
        guard !samples.isEmpty else { return [] }
        if pendingSamples.isEmpty { pendingTimestamp = contentTimestampNanoseconds }
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
                acousticSnapshot: evidence.acousticSnapshot,
                contentTimestampNanoseconds: pendingTimestamp
            ))
            pendingTimestamp = pendingTimestamp.map { $0 &+ 20_000_000 }
        }
        return packets
    }

    mutating func reset() {
        pendingSamples.removeAll(keepingCapacity: true)
        evidenceSpans.removeAll(keepingCapacity: true)
        pendingTimestamp = nil
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
    case processingModeBusy = "audio_processing_mode_busy"
}

nonisolated protocol MacSpeechAudioCapturing: AnyObject, Sendable {
    func selectProcessingMode(_ mode: MacSpeechAudioProcessingMode) throws
    func voiceProcessingSnapshot() -> MacSpeechVoiceProcessingSnapshot?
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
    func selectProcessingMode(_ mode: MacSpeechAudioProcessingMode) throws {
        guard mode == .webRTCAEC3 else {
            throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
        }
    }
    func voiceProcessingSnapshot() -> MacSpeechVoiceProcessingSnapshot? { nil }
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
    private var inputSampleCount: UInt64 = 0
    private var outputSampleCount: UInt64 = 0
    private var contentAnchor: UInt64?
    private var contentTimeValid = true

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
        acousticSnapshot: MacSpeechAcousticObservationSnapshot? = nil,
        contentTimestampNanoseconds: UInt64? = nil,
        requireContentTime: Bool = false
    ) throws -> [MacSpeechPCM16Packet] {
        try lock.withLock {
            if requireContentTime {
                guard contentTimeValid, let timestamp = contentTimestampNanoseconds,
                      timestamp > 0 else {
                    contentTimeValid = false
                    packetizer.reset()
                    return []
                }
                if contentAnchor == nil { contentAnchor = timestamp }
                let expected = Double(contentAnchor!)
                    + Double(inputSampleCount) * 1_000_000_000 / inputSampleRate
                guard abs(Double(timestamp) - expected) <= (1_000_000_000 / inputSampleRate).rounded(.up) else {
                    contentTimeValid = false
                    packetizer.reset()
                    return []
                }
            }
            let ratio = MacSpeechAudioInputFormat.sampleRate / inputSampleRate
            let estimatedFrames = ceil(Double(inputBuffer.frameLength) * ratio) + 8
            guard inputBuffer.frameLength > 0, estimatedFrames <= 8_192 else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            let capacity = AVAudioFrameCount(max(1, estimatedFrames))
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
                  let samples = outputBuffer.floatChannelData?[0]
            else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }

            guard inputState.supplied else {
                contentTimeValid = false
                packetizer.reset()
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            inputSampleCount += UInt64(inputBuffer.frameLength)
            let count = Int(outputBuffer.frameLength)
            guard Double(outputSampleCount) + Double(count)
                    <= Double(inputSampleCount) * ratio + 0.000_001 else {
                contentTimeValid = false
                packetizer.reset()
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            var timestamp: UInt64?
            if let contentAnchor {
                let value = Double(contentAnchor) + Double(outputSampleCount)
                    * 1_000_000_000 / outputFormat.sampleRate
                guard value.isFinite, value > 0, value < Double(UInt64.max) else {
                    contentTimeValid = false
                    packetizer.reset()
                    return []
                }
                timestamp = UInt64(value.rounded())
            }
            outputSampleCount += UInt64(count)
            let values = Array(UnsafeBufferPointer(start: samples, count: count))
            return packetizer.append(
                samples: values,
                activityEvidenceKind: activityEvidenceKind,
                acousticSnapshot: acousticSnapshot,
                contentTimestampNanoseconds: timestamp
            )
        }
    }

    func convert(
        captureSpans: [MacSpeechAcousticCaptureSpan],
        requiresContinuousContentTime: Bool = false
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
                acousticSnapshot: span.observation,
                contentTimestampNanoseconds: requiresContinuousContentTime
                    ? span.observation.captureHostTimeNanoseconds : nil,
                requireContentTime: requiresContinuousContentTime
            ))
        }
        return packets
    }

    func resetForGenerationTransition() {
        lock.withLock {
            converter.reset()
            packetizer.reset()
            inputSampleCount = 0
            outputSampleCount = 0
            contentAnchor = nil
            contentTimeValid = true
        }
    }
}

nonisolated final class MacSpeechFloatMono48kConverter: @unchecked Sendable {
    private final class InputState: @unchecked Sendable {
        var supplied = false
    }

    struct Output {
        let samples: [Float]
        let hostTimeNanoseconds: UInt64?
    }

    private struct InputTime {
        let start: Double
        let end: Double
        let hostTimeNanoseconds: UInt64?
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
    private var inputFrameCount: UInt64 = 0
    private var outputSampleCount: UInt64 = 0
    private var inputTimes: [InputTime] = []
    private var sampleTimeAnchor: Int64?
    private var hostTimeAnchor: UInt64?
    private var nextInputSampleTime: Int64?
    private var sampleTimeContinuityValid = true
    private var previousInputHostTime: UInt64?
    private var previousInputFrameCount = 0

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
        try convert(inputBuffer, hostTimeNanoseconds: nil).samples
    }

    func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?,
        sampleTime: Int64? = nil
    ) throws -> Output {
        try lock.withLock {
            let ratio = outputFormat.sampleRate / inputSampleRate
            let estimatedFrames = ceil(Double(inputBuffer.frameLength) * ratio)
            guard inputBuffer.frameLength > 0,
                  estimatedFrames <= 16_384,
                  inputTimes.count < 64 else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            let capacity = AVAudioFrameCount(max(1, estimatedFrames))
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
            guard inputState.supplied else {
                sampleTimeContinuityValid = false
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            let start = Double(inputFrameCount) * ratio
            let inputTime = anchoredInputHostTime(
                sampleTime: sampleTime,
                hostTimeNanoseconds: hostTimeNanoseconds,
                inputFrameCount: Int(inputBuffer.frameLength)
            )
            inputFrameCount += UInt64(inputBuffer.frameLength)
            inputTimes.append(InputTime(
                start: start, end: Double(inputFrameCount) * ratio,
                hostTimeNanoseconds: inputTime
            ))
            guard conversionError == nil,
                  status != .error,
                  let samples = outputBuffer.floatChannelData?[0] else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            let count = Int(outputBuffer.frameLength)
            let timestamp = outputHostTime(sampleCount: count)
            outputSampleCount += UInt64(count)
            inputTimes.removeAll { $0.end <= Double(outputSampleCount) }
            return Output(samples: Array(UnsafeBufferPointer(
                start: samples,
                count: count
            )), hostTimeNanoseconds: timestamp)
        }
    }

    private func outputHostTime(sampleCount: Int)
        -> UInt64? {
        guard sampleCount > 0 else { return nil }
        let start = Double(outputSampleCount)
        let end = start + Double(sampleCount)
        let intervals = inputTimes.filter { $0.end > start && $0.start < end }
        guard let last = intervals.last,
              last.end + 0.000_001 >= end else {
            return nil
        }
        guard let first = intervals.first,
              first.start <= start else {
            return nil
        }
        guard let firstTime = first.hostTimeNanoseconds else {
            return nil
        }
        let nanosecondsPerSample = 1_000_000_000 / outputFormat.sampleRate
        let timestamp = Double(firstTime) + (start - first.start) * nanosecondsPerSample
        // Host timestamps use whole nanoseconds, including a one-sample clock offset.
        let timestampTolerance = (1_000_000_000 / inputSampleRate).rounded(.up)
        // Buffered output may span input callbacks. A gap or unknown time cannot become a continuous clock.
        for interval in intervals {
            guard let time = interval.hostTimeNanoseconds else {
                return nil
            }
            let expected = timestamp + (interval.start - start) * nanosecondsPerSample
            let error = Double(time) - expected
            guard abs(error) <= timestampTolerance else {
                return nil
            }
        }
        guard timestamp.isFinite, timestamp > 0,
              timestamp < Double(UInt64.max) else { return nil }
        return UInt64(timestamp.rounded())
    }

    private func anchoredInputHostTime(
        sampleTime: Int64?,
        hostTimeNanoseconds: UInt64?,
        inputFrameCount: Int
    ) -> UInt64? {
        guard let hostTimeNanoseconds, hostTimeNanoseconds > 0 else {
            sampleTimeContinuityValid = false
            return nil
        }
        guard let sampleTime else {
            if sampleTimeAnchor != nil {
                sampleTimeContinuityValid = false
            }
            if let previousInputHostTime {
                let expected = Double(previousInputHostTime)
                    + Double(previousInputFrameCount)
                        * 1_000_000_000 / inputSampleRate
                let tolerance = (1_000_000_000 / inputSampleRate)
                    .rounded(.up)
                if abs(Double(hostTimeNanoseconds) - expected)
                    > tolerance {
                    sampleTimeContinuityValid = false
                }
            }
            previousInputHostTime = hostTimeNanoseconds
            previousInputFrameCount = inputFrameCount
            return sampleTimeContinuityValid ? hostTimeNanoseconds : nil
        }
        if sampleTimeAnchor == nil {
            guard self.inputFrameCount == 0 else {
                sampleTimeContinuityValid = false
                return nil
            }
            sampleTimeAnchor = sampleTime
            hostTimeAnchor = hostTimeNanoseconds
        } else if nextInputSampleTime != sampleTime {
            sampleTimeContinuityValid = false
        }
        let (next, overflow) = sampleTime.addingReportingOverflow(
            Int64(inputFrameCount)
        )
        if overflow { sampleTimeContinuityValid = false }
        nextInputSampleTime = overflow ? nil : next
        guard sampleTimeContinuityValid,
              let sampleTimeAnchor,
              let hostTimeAnchor else { return nil }
        let (offset, subtractionOverflow) = sampleTime.subtractingReportingOverflow(sampleTimeAnchor)
        guard !subtractionOverflow, offset >= 0 else {
            sampleTimeContinuityValid = false
            return nil
        }
        let elapsed = Double(offset) * 1_000_000_000 / inputSampleRate
        let timestamp = Double(hostTimeAnchor) + elapsed
        guard timestamp.isFinite, timestamp > 0,
              timestamp < Double(UInt64.max),
              abs(Double(hostTimeNanoseconds) - timestamp)
                <= (1_000_000_000 / inputSampleRate).rounded(.up) else {
            sampleTimeContinuityValid = false
            return nil
        }
        return UInt64(timestamp.rounded())
    }

    func resetForGenerationTransition() {
        lock.withLock {
            converter.reset()
            inputFrameCount = 0
            outputSampleCount = 0
            inputTimes.removeAll(keepingCapacity: true)
            sampleTimeAnchor = nil
            hostTimeAnchor = nil
            nextInputSampleTime = nil
            sampleTimeContinuityValid = true
            previousInputHostTime = nil
            previousInputFrameCount = 0
        }
    }
}

nonisolated struct MacSpeechVoiceProcessingSnapshot: Sendable, Equatable {
    let mode: MacSpeechAudioProcessingMode
    let configurationID: UInt64
    let inputEnabled: Bool
    let outputEnabled: Bool
    let bypassed: Bool
    let inputMuted: Bool
    let automaticGainControlEnabled: Bool
    let inputFormat: MacSpeechNativeInputFormat
    let outputFormat: MacSpeechNativeInputFormat
    let validatedAtNanoseconds: UInt64

    var hasValidAppleProcessing: Bool {
        mode == .appleVoiceProcessing && inputEnabled && outputEnabled
            && !bypassed && automaticGainControlEnabled
    }
}

nonisolated final class SystemMacSpeechVoiceProcessingEngine:
    @unchecked Sendable
{
    // Control operations serialize here; audio callbacks never acquire this lock.
    private let lifecycleLock = NSLock()
    private let lock = NSLock()
    private let captureProcessingLock = NSLock()
    private let renderProcessingLock = NSLock()
    private let renderConverterLock = NSLock()
    private var audioProcessingMode: MacSpeechAudioProcessingMode
    private var acousticEchoHost: MacSpeechAcousticEchoHost
    private let stopPlayerNode: @Sendable (AVAudioPlayerNode?) -> Void
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var captureAECConverter: MacSpeechFloatMono48kConverter?
    private var captureOutputConverter: MacSpeechAudioConverter?
    private var renderAECConverter: MacSpeechFloatMono48kConverter?
    private var isConfigured = false
    private var isCaptureActive = false
    private var isCaptureTapInstalled = false
    private var captureGeneration: UInt64?
    private var isOutputPrepared = false
    private var isOutputPlaying = false
    private var isRenderReferenceTapInstalled = false
    private var outputFormat: AVAudioFormat?
    private var routeRebuildWasConfigured = false
    private var isRouteRebuilding = false
    private var configurationID: UInt64 = 0
    private var processingSnapshot: MacSpeechVoiceProcessingSnapshot?
    private var outputPresentationLatencySeconds = 0.0
    private var capturePresentationLatencySeconds = 0.0
    private var captureGenerationFence = MacSpeechCaptureGenerationFence()
    #if DEBUG
    private static let audioUnitDiagnosticLogger = Logger(
        subsystem: "com.eterna.aftelle", category: "AudioUnitAttribution"
    )
    #endif

    init(
        audioProcessingMode: MacSpeechAudioProcessingMode = .webRTCAEC3,
        acousticEchoHost: MacSpeechAcousticEchoHost? = nil,
        stopPlayerNode: @escaping @Sendable (AVAudioPlayerNode?) -> Void = {
            $0?.stop()
        }
    ) {
        self.audioProcessingMode = audioProcessingMode
        self.stopPlayerNode = stopPlayerNode
        self.acousticEchoHost = acousticEchoHost
            ?? Self.makeAcousticEchoHost(mode: audioProcessingMode)
    }

    private static func makeAcousticEchoHost(
        mode: MacSpeechAudioProcessingMode
    ) -> MacSpeechAcousticEchoHost {
        #if AFTELLE_WEBRTC_AEC3
        MacSpeechAcousticEchoHost(
            mode: mode,
            backend: mode == .webRTCAEC3 ? MacSpeechWebRTCAECProcessor() : nil
        )
        #else
        MacSpeechAcousticEchoHost(mode: mode)
        #endif
    }

    func selectProcessingMode(_ mode: MacSpeechAudioProcessingMode) throws {
        try lifecycleLock.withLock {
            try lock.withLock {
                guard !isCaptureActive, !isOutputPrepared, !isOutputPlaying,
                      !isRouteRebuilding else {
                    throw MacSpeechAudioCaptureError.processingModeBusy
                }
                guard mode != .halfDuplexFallback else {
                    throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
                }
            }
            tearDownIfIdle()
            lock.withLock {
                guard audioProcessingMode != mode else { return }
                audioProcessingMode = mode
                acousticEchoHost = Self.makeAcousticEchoHost(mode: mode)
            }
        }
    }

    func voiceProcessingSnapshot() -> MacSpeechVoiceProcessingSnapshot? {
        lock.withLock { processingSnapshot }
    }

    func startCapture(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        try lifecycleLock.withLock {
            let prepared = try lock.withLock { () throws -> (AVAudioEngine, AVAudioFormat, UInt64) in
                guard !isRouteRebuilding else {
                    throw MacSpeechAudioCaptureError.processingModeBusy
                }
                try configureIfNeeded()
                guard let engine, captureAECConverter != nil,
                      captureOutputConverter != nil else {
                    throw MacSpeechAudioCaptureError.converterUnavailable
                }
                if isCaptureActive {
                    guard captureGeneration == generation else {
                        throw MacSpeechAudioCaptureError.processingModeBusy
                    }
                }
                return (engine, engine.inputNode.outputFormat(forBus: 0), configurationID)
            }
            if lock.withLock({ isCaptureActive }) { return describe(prepared.1) }
            do {
                try validateVoiceProcessing(engine: prepared.0, requireUnmuted: true)
                captureProcessingLock.withLock {
                    captureGenerationFence = MacSpeechCaptureGenerationFence()
                    lock.withLock {
                        captureAECConverter?.resetForGenerationTransition()
                        captureOutputConverter?.resetForGenerationTransition()
                        captureGeneration = generation
                        isCaptureActive = true
                    }
                }
                let inputNode = prepared.0.inputNode
                let captureConfigurationID = prepared.2
                inputNode.installTap(
                    onBus: 0,
                    bufferSize: MacSpeechAudioInputFormat.tapBufferSize(for: prepared.1.sampleRate),
                    format: prepared.1
                ) { [weak self] buffer, when in
                    self?.processCapture(
                        buffer,
                        hostTimeNanoseconds: Self.hostTimeNanoseconds(when),
                        nativeSampleTime: when.isSampleTimeValid ? when.sampleTime : nil,
                        configurationID: captureConfigurationID,
                        generation: generation,
                        frameBuffer: frameBuffer
                    )
                }
                lock.withLock { isCaptureTapInstalled = true }
                if !prepared.0.isRunning {
                    prepared.0.prepare()
                    try prepared.0.start()
                }
                lock.withLock { refreshAcousticEchoPresentationLatencyLocked() }
                return describe(prepared.1)
            } catch {
                stopCaptureLocked()
                throw error
            }
        }
    }

    func stopCapture() {
        lifecycleLock.withLock { stopCaptureLocked() }
    }

    private func stopCaptureLocked() {
        let input = lock.withLock { () -> AVAudioInputNode? in
            isCaptureActive = false
            captureGeneration = nil
            guard isCaptureTapInstalled else { return nil }
            isCaptureTapInstalled = false
            return engine?.inputNode
        }
        // removeTap can wait for a callback which needs the state lock.
        input?.removeTap(onBus: 0)
        captureProcessingLock.withLock {
            let converters = lock.withLock { (captureAECConverter, captureOutputConverter) }
            converters.0?.resetForGenerationTransition()
            converters.1?.resetForGenerationTransition()
        }
        tearDownIfIdle()
    }

    func discardPendingAudioForGenerationTransition() {
        captureProcessingLock.withLock {
            captureGenerationFence.advance(to: DispatchTime.now().uptimeNanoseconds)
            let context = lock.withLock { (captureAECConverter, captureOutputConverter, acousticEchoHost) }
            context.0?.resetForGenerationTransition()
            context.1?.resetForGenerationTransition()
            context.2.discardPendingCaptureForGenerationTransition()
        }
    }

    func prepareOutput() throws -> AVAudioFormat {
        try lifecycleLock.withLock {
            try lock.withLock {
                guard !isRouteRebuilding else { throw MacSpeechAudioCaptureError.processingModeBusy }
                try configureIfNeeded()
                guard let outputFormat else { throw MacSpeechAudioCaptureError.invalidInputFormat }
                isOutputPrepared = true
                return outputFormat
            }
        }
    }

    func scheduleOutput(
        _ buffer: AVAudioPCMBuffer,
        completion: @escaping @Sendable () -> Void
    ) throws {
        try lifecycleLock.withLock {
            let node = try lock.withLock { () throws -> AVAudioPlayerNode in
                guard isOutputPrepared, !isRouteRebuilding,
                      let playerNode, let outputFormat,
                      buffer.format == outputFormat else {
                    throw MacSpeechAudioCaptureError.engineStartFailed
                }
                return playerNode
            }
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in completion() }
        }
    }

    func startOutput() throws {
        try lifecycleLock.withLock {
            let prepared = try lock.withLock { () throws -> (AVAudioEngine, AVAudioPlayerNode) in
                guard isOutputPrepared, !isRouteRebuilding, let engine, let playerNode else {
                    throw MacSpeechAudioCaptureError.engineStartFailed
                }
                return (engine, playerNode)
            }
            do {
                try validateVoiceProcessing(engine: prepared.0, requireUnmuted: false)
                acousticEchoHost.playbackStarted()
                lock.withLock { isOutputPlaying = true }
                if !prepared.0.isRunning {
                    prepared.0.prepare()
                    try prepared.0.start()
                }
                if !prepared.1.isPlaying { prepared.1.play() }
                lock.withLock { refreshAcousticEchoPresentationLatencyLocked() }
            } catch {
                lock.withLock { isOutputPlaying = false }
                acousticEchoHost.playbackStopped()
                throw error
            }
        }
    }

    func finishOutputPlayback() {
        lifecycleLock.withLock {
            lock.withLock { isOutputPlaying = false }
            acousticEchoHost.playbackCompleted()
        }
    }

    func clearScheduledOutput() {
        lifecycleLock.withLock {
            let node = lock.withLock { () -> AVAudioPlayerNode? in
                isOutputPlaying = false
                return playerNode
            }
            stopPlayerNodeOutsideStateLock(node)
            acousticEchoHost.playbackStopped()
        }
    }

    func stopOutput() {
        lifecycleLock.withLock {
            let graph = lock.withLock { () -> (AVAudioPlayerNode?, AVAudioEngine?) in
                isOutputPlaying = false
                return (playerNode, isCaptureActive ? nil : engine)
            }
            stopPlayerNodeOutsideStateLock(graph.0)
            acousticEchoHost.playbackStopped()
            graph.1?.stop()
        }
    }

    func closeOutput() {
        lifecycleLock.withLock {
            let node = lock.withLock { () -> AVAudioPlayerNode? in
                isOutputPlaying = false
                isOutputPrepared = false
                return playerNode
            }
            stopPlayerNodeOutsideStateLock(node)
            acousticEchoHost.playbackStopped()
            tearDownIfIdle(outputAlreadyStopped: true)
        }
    }

    private func stopPlayerNodeOutsideStateLock(_ node: AVAudioPlayerNode?) {
        stopPlayerNode(node)
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        do {
            let inputNode = engine.inputNode
            guard !engine.isRunning else { throw MacSpeechAudioCaptureError.processingModeBusy }
            if audioProcessingMode == .appleVoiceProcessing {
                try inputNode.setVoiceProcessingEnabled(true)
                inputNode.isVoiceProcessingBypassed = false
                inputNode.isVoiceProcessingInputMuted = false
                inputNode.isVoiceProcessingAGCEnabled = true
            }
            let localFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let outputInputFormat = engine.outputNode.inputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  localFormat.sampleRate > 0, localFormat.channelCount > 0 else {
                throw MacSpeechAudioCaptureError.invalidInputFormat
            }
            if audioProcessingMode == .appleVoiceProcessing {
                guard inputFormat.sampleRate == outputInputFormat.sampleRate,
                      inputFormat.channelCount == outputInputFormat.channelCount else {
                    throw MacSpeechAudioCaptureError.invalidInputFormat
                }
            }
            engine.connect(playerNode, to: engine.mainMixerNode, format: localFormat)
            try rebuildAudioFormatsLocked(engine: engine, localFormat: localFormat)
            configurationID &+= 1
            self.engine = engine
            self.playerNode = playerNode
            try updateVoiceProcessingSnapshot(engine: engine, requireUnmuted: true)
            installRenderReferenceTapLocked(playerNode: playerNode, configurationID: configurationID)
            _ = acousticEchoHost.configure()
            isConfigured = true
        } catch {
            captureAECConverter = nil
            captureOutputConverter = nil
            renderConverterLock.withLock { renderAECConverter = nil }
            processingSnapshot = nil
            outputFormat = nil
            self.engine = nil
            self.playerNode = nil
            engine.stop()
            engine.disconnectNodeOutput(playerNode)
            engine.detach(playerNode)
            throw error
        }
    }

    private func validateVoiceProcessing(engine: AVAudioEngine, requireUnmuted: Bool) throws {
        try lock.withLock { try updateVoiceProcessingSnapshot(engine: engine, requireUnmuted: requireUnmuted) }
    }

    private func updateVoiceProcessingSnapshot(engine: AVAudioEngine, requireUnmuted: Bool) throws {
        let inputNode = engine.inputNode
        let snapshot = MacSpeechVoiceProcessingSnapshot(
            mode: audioProcessingMode,
            configurationID: configurationID,
            inputEnabled: inputNode.isVoiceProcessingEnabled,
            outputEnabled: engine.outputNode.isVoiceProcessingEnabled,
            bypassed: inputNode.isVoiceProcessingBypassed,
            inputMuted: inputNode.isVoiceProcessingInputMuted,
            automaticGainControlEnabled: inputNode.isVoiceProcessingAGCEnabled,
            inputFormat: describe(inputNode.outputFormat(forBus: 0)),
            outputFormat: describe(engine.outputNode.inputFormat(forBus: 0)),
            validatedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        if let previous = processingSnapshot,
           previous.configurationID == configurationID,
           (previous.inputFormat != snapshot.inputFormat || previous.outputFormat != snapshot.outputFormat) {
            processingSnapshot = nil
            throw MacSpeechAudioCaptureError.invalidInputFormat
        }
        if audioProcessingMode == .appleVoiceProcessing {
            guard snapshot.hasValidAppleProcessing,
                  !requireUnmuted || !snapshot.inputMuted else {
                processingSnapshot = nil
                throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
            }
        } else {
            guard !snapshot.inputEnabled, !snapshot.outputEnabled else {
                processingSnapshot = nil
                throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
            }
        }
        processingSnapshot = snapshot
    }

    private func tearDownIfIdle(outputAlreadyStopped: Bool = false) {
        guard lock.withLock({ !isCaptureActive && !isOutputPrepared }) else { return }
        tearDownGraph(outputAlreadyStopped: outputAlreadyStopped)
    }

    private func tearDownGraph(outputAlreadyStopped: Bool = false) {
        let graph = lock.withLock { () -> (AVAudioEngine?, AVAudioPlayerNode?, Bool, Bool) in
            let result = (engine, playerNode, isCaptureTapInstalled, isRenderReferenceTapInstalled)
            configurationID &+= 1
            isCaptureActive = false
            captureGeneration = nil
            isCaptureTapInstalled = false
            isOutputPrepared = false
            isOutputPlaying = false
            isRenderReferenceTapInstalled = false
            isConfigured = false
            processingSnapshot = nil
            engine = nil
            playerNode = nil
            outputFormat = nil
            captureAECConverter = nil
            captureOutputConverter = nil
            renderConverterLock.withLock { renderAECConverter = nil }
            resetAcousticEchoPresentationLatencyLocked()
            return result
        }
        if graph.2 { graph.0?.inputNode.removeTap(onBus: 0) }
        if graph.3 { graph.1?.removeTap(onBus: 0) }
        captureProcessingLock.withLock {}
        renderProcessingLock.withLock {}
        graph.0?.stop()
        if !outputAlreadyStopped, let node = graph.1 {
            stopPlayerNodeOutsideStateLock(node)
        }
        if let engine = graph.0, let node = graph.1 {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            engine.reset()
        }
    }

    func routeWillRebuild() {
        lifecycleLock.withLock {
            let wasConfigured = lock.withLock { () -> Bool in
                isRouteRebuilding = true
                routeRebuildWasConfigured = isConfigured
                return isConfigured
            }
            acousticEchoHost.routeWillRebuild()
            if wasConfigured { tearDownGraph() }
        }
    }

    func routeDidRebuild() {
        lifecycleLock.withLock {
            let rebuild = lock.withLock { () -> Bool in
                isRouteRebuilding = false
                defer { routeRebuildWasConfigured = false }
                return routeRebuildWasConfigured
            }
            guard rebuild else { return }
            do {
                try lock.withLock { try configureIfNeeded() }
            } catch {
                tearDownGraph()
            }
        }
    }

    func resetForRouteChange() {
        routeWillRebuild()
        routeDidRebuild()
    }

    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot {
        lock.withLock { acousticEchoHost }.snapshot()
    }

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot {
        lock.withLock { acousticEchoHost }.acousticObservationSnapshot()
    }

    func resetAcousticEchoDiagnostics() {
        lock.withLock { acousticEchoHost }.resetDiagnostics()
    }

    #if DEBUG
    func armAcousticReplayCapture(
        attemptID: UUID,
        targetCaptureFrameCount: Int = 1_000
    ) -> Bool {
        lock.withLock { acousticEchoHost }.armAcousticReplayCapture(
            attemptID: attemptID,
            targetCaptureFrameCount: targetCaptureFrameCount
        )
    }

    func sealAcousticReplayCapture(
        reason: MacSpeechAcousticReplaySealReason = .manual,
        matchingAttemptID attemptID: UUID? = nil
    ) {
        lock.withLock { acousticEchoHost }.sealAcousticReplayCapture(
            reason: reason,
            matchingAttemptID: attemptID
        )
    }

    func acousticReplayCaptureSnapshot()
        -> MacSpeechAcousticReplayCaptureSnapshot? {
        lock.withLock { acousticEchoHost }.acousticReplayCaptureSnapshot()
    }

    func clearAcousticReplayCapture(matchingAttemptID attemptID: UUID? = nil) {
        lock.withLock { acousticEchoHost }.clearAcousticReplayCapture(
            matchingAttemptID: attemptID
        )
    }
    #endif

    private func processCapture(
        _ buffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?,
        nativeSampleTime: Int64?,
        configurationID: UInt64,
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) {
        captureProcessingLock.withLock {
            guard captureGenerationFence.accepts(hostTimeNanoseconds: hostTimeNanoseconds) else { return }
            let context = lock.withLock { () -> (MacSpeechFloatMono48kConverter, MacSpeechAudioConverter, MacSpeechAcousticEchoHost, Bool)? in
                guard isCaptureActive, self.configurationID == configurationID,
                      captureGeneration == generation,
                      let input = captureAECConverter, let output = captureOutputConverter else { return nil }
                return (input, output, acousticEchoHost, audioProcessingMode == .appleVoiceProcessing)
            }
            guard let (inputConverter, outputConverter, host, appleProcessing) = context,
                  let converted = try? inputConverter.convert(
                    buffer, hostTimeNanoseconds: hostTimeNanoseconds, sampleTime: nativeSampleTime
                  ), let contentTime = converted.hostTimeNanoseconds,
                  captureGenerationFence.accepts(hostTimeNanoseconds: contentTime),
                  lock.withLock({ isCaptureActive && self.configurationID == configurationID
                      && captureGeneration == generation }) else { return }
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let captureSpans = host.processCaptureSpans(converted.samples, hostTimeNanoseconds: contentTime)
            if let packets = try? outputConverter.convert(
                captureSpans: captureSpans, requiresContinuousContentTime: appleProcessing
            ) {
                for packet in packets {
                    guard let observation = packet.acousticSnapshot,
                          let timestamp = packet.contentTimestampNanoseconds
                            ?? (appleProcessing ? nil : observation.captureHostTimeNanoseconds) else { continue }
                    frameBuffer.append(
                        pcm16Bytes: packet.bytes,
                        activity: packet.activity,
                        generation: generation,
                        timestamp: timestamp,
                        activityEvidenceKind: packet.activityEvidenceKind,
                        residentPlaybackSequence: observation.playbackSequence,
                        residentPlaybackActive: observation.isPlaybackActive,
                        lastAudibleResidentRenderTimestampNanoseconds: observation.lastAudibleRenderHostTimeNanoseconds,
                        sourceGateEpoch: packet.activityEvidenceKind == .sourceGatedNearEnd ? observation.sourceGateEpoch : 0,
                        acousticSnapshot: observation
                    )
                }
            }
            host.recordCaptureProcessingDuration(nanoseconds: DispatchTime.now().uptimeNanoseconds &- startedAt)
            lock.withLock { updateAcousticEchoDelayLocked() }
        }
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
        configurationID: UInt64
    ) {
        guard !isRenderReferenceTapInstalled else { return }
        playerNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(MacSpeechAcousticEchoHost.frameSampleCount),
            format: nil
        ) { [weak self] buffer, when in
            self?.processRenderedOutput(
                buffer,
                hostTimeNanoseconds: Self.hostTimeNanoseconds(when),
                nativeSampleTime: when.isSampleTimeValid ? when.sampleTime : nil,
                configurationID: configurationID
            )
        }
        isRenderReferenceTapInstalled = true
    }

    private func processRenderedOutput(
        _ buffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?,
        nativeSampleTime: Int64?,
        configurationID: UInt64
    ) {
        renderProcessingLock.withLock {
            let context = lock.withLock { () -> (MacSpeechFloatMono48kConverter, MacSpeechAcousticEchoHost)? in
                guard self.configurationID == configurationID, isConfigured,
                      let converter = renderConverterLock.withLock({ renderAECConverter }) else { return nil }
                return (converter, acousticEchoHost)
            }
            guard let (converter, host) = context else { return }
            do {
                let converted = try converter.convert(
                    buffer, hostTimeNanoseconds: hostTimeNanoseconds, sampleTime: nativeSampleTime
                )
                guard let contentTime = converted.hostTimeNanoseconds,
                      lock.withLock({ self.configurationID == configurationID && isConfigured }) else { return }
                host.processRender(converted.samples, hostTimeNanoseconds: contentTime)
            } catch {
                host.renderConversionFailed()
            }
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

    private static func hostTimeNanoseconds(_ time: AVAudioTime) -> UInt64? {
        guard time.isHostTimeValid else { return nil }
        let seconds = AVAudioTime.seconds(forHostTime: time.hostTime)
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return UInt64((seconds * 1_000_000_000).rounded())
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

    func selectProcessingMode(_ mode: MacSpeechAudioProcessingMode) throws {
        try audioEngine.selectProcessingMode(mode)
    }

    func voiceProcessingSnapshot() -> MacSpeechVoiceProcessingSnapshot? {
        audioEngine.voiceProcessingSnapshot()
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
