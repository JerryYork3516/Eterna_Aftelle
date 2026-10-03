@preconcurrency import AVFoundation
import Foundation
#if DEBUG
import OSLog

nonisolated struct Test3NearEndInjection {
    let samples: [Float]
    let startAtNanoseconds: UInt64
    private(set) var startedAtNanoseconds: UInt64?
    private(set) var injectedSampleCount = 0

    mutating func mix(into capture: inout [Float], hostTimeNanoseconds: UInt64) {
        guard injectedSampleCount < samples.count, !capture.isEmpty else { return }
        let offset: Int
        if startedAtNanoseconds == nil, hostTimeNanoseconds < startAtNanoseconds {
            let remaining = Double(startAtNanoseconds - hostTimeNanoseconds)
                * 48_000 / 1_000_000_000
            guard remaining < Double(capture.count) else { return }
            offset = Int(remaining.rounded(.up))
        } else {
            offset = 0
        }
        guard offset < capture.count else { return }
        if startedAtNanoseconds == nil {
            startedAtNanoseconds = hostTimeNanoseconds
                + UInt64(Double(offset) * 1_000_000_000 / 48_000)
        }
        let count = min(capture.count - offset, samples.count - injectedSampleCount)
        for index in 0..<count {
            capture[offset + index] = min(1, max(-1,
                capture[offset + index] + samples[injectedSampleCount + index]))
        }
        injectedSampleCount += count
    }
}
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
    func causalInterruptionObservation() async
        -> MacSpeechCausalInterruptionObservation?
    func residentAcousticSnapshot() async
        -> MacSpeechResidentAcousticSnapshot?
}

nonisolated extension MacSpeechAudioFrameSourcing {
    func discardPendingAudioForGenerationTransition() async {}
    func interruptionAcousticSnapshot() async
        -> MacSpeechInterruptionAcousticSnapshot? { nil }
    func causalInterruptionObservation() async
        -> MacSpeechCausalInterruptionObservation? { nil }
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
    func causalInterruptionObservation()
        -> MacSpeechCausalInterruptionObservation?
    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot?
    func resetAcousticEchoDiagnostics()
}

nonisolated extension MacSpeechAudioCapturing {
    func discardPendingAudioForGenerationTransition() {}
    func routeWillRebuild() {}
    func routeDidRebuild() {}
    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot? { nil }
    func causalInterruptionObservation()
        -> MacSpeechCausalInterruptionObservation? { nil }
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

    struct Output {
        var samples: [Float]
        let hostTimeNanoseconds: UInt64?
        let timestampFailureReason: String?
        let timestampErrorNanoseconds: Double?
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
            if inputState.supplied {
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
            }
            guard conversionError == nil,
                  status != .error,
                  outputBuffer.frameLength > 0,
                  let samples = outputBuffer.floatChannelData?[0] else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            let count = Int(outputBuffer.frameLength)
            let timing = outputHostTime(sampleCount: count)
            outputSampleCount += UInt64(count)
            inputTimes.removeAll { $0.end <= Double(outputSampleCount) }
            return Output(samples: Array(UnsafeBufferPointer(
                start: samples,
                count: count
            )), hostTimeNanoseconds: timing.0,
                timestampFailureReason: timing.1,
                timestampErrorNanoseconds: timing.2)
        }
    }

    private func outputHostTime(sampleCount: Int)
        -> (UInt64?, String?, Double?) {
        let start = Double(outputSampleCount)
        let end = start + Double(sampleCount)
        let intervals = inputTimes.filter { $0.end > start && $0.start < end }
        guard let last = intervals.last,
              last.end + 0.000_001 >= end else {
            return (nil, "output_cursor_ahead_of_input", nil)
        }
        guard let first = intervals.first,
              first.start <= start else {
            return (nil, "output_cursor_uncovered", nil)
        }
        guard let firstTime = first.hostTimeNanoseconds else {
            return (nil, "first_input_time_missing", nil)
        }
        let nanosecondsPerSample = 1_000_000_000 / outputFormat.sampleRate
        let timestamp = Double(firstTime) + (start - first.start) * nanosecondsPerSample
        // Host timestamps use whole nanoseconds, including a one-sample clock offset.
        let timestampTolerance = (1_000_000_000 / inputSampleRate).rounded(.up)
        // Buffered output may span input callbacks. A gap or unknown time cannot become a continuous clock.
        for interval in intervals {
            guard let time = interval.hostTimeNanoseconds else {
                return (nil, "input_time_missing", nil)
            }
            let expected = timestamp + (interval.start - start) * nanosecondsPerSample
            let error = Double(time) - expected
            guard abs(error) <= timestampTolerance else {
                return (nil, "input_time_discontinuity", error)
            }
        }
        return (UInt64(timestamp.rounded()), nil, nil)
    }

    private func anchoredInputHostTime(
        sampleTime: Int64?,
        hostTimeNanoseconds: UInt64?,
        inputFrameCount: Int
    ) -> UInt64? {
        guard let sampleTime else {
            if sampleTimeAnchor != nil || hostTimeNanoseconds == nil {
                sampleTimeContinuityValid = false
            }
            if let previousInputHostTime,
               let hostTimeNanoseconds {
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
            guard self.inputFrameCount == 0,
                  let hostTimeNanoseconds else {
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
        let elapsed = Double(sampleTime - sampleTimeAnchor)
            * 1_000_000_000 / inputSampleRate
        return UInt64((Double(hostTimeAnchor) + elapsed).rounded())
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

nonisolated final class SystemMacSpeechVoiceProcessingEngine:
    @unchecked Sendable
{
    #if DEBUG
    struct Test3AppleVADReadTrace: Codable, Sendable {
        struct Read: Codable, Sendable {
            let sequence: UInt64
            let captureHostTimeNanoseconds: UInt64?
            let sampledAtNanoseconds: UInt64
            let sampleCount: Int
            let detectorEventSequence: UInt64?
            let detectorEventNanoseconds: UInt64?
            let detectorReadNanoseconds: UInt64?
            let detectorReadStatus: OSStatus?
            let detectorVoiceDetected: Bool?
            let effectiveVoiceDetected: Bool?
        }

        let schemaVersion: Int
        let reads: [Read]
        let detector: MacSpeechTest3VADTrace?
        let truncated: Bool
    }

    struct Test3CaptureCallbackTrace: Codable, Sendable {
        struct Callback: Codable, Sendable {
            let contentHostTimeNanoseconds: UInt64?
            let nativeSampleTime: Int64?
            let enteredAtNanoseconds: UInt64
            let previousEntryIntervalNanoseconds: UInt64?
            let inputFrameLength: Int
            let inputSampleRate: Double
            let convertedSampleCount: Int
            let convertedHostTimeNanoseconds: UInt64?
            let lockWaitNanoseconds: UInt64
            let conversionNanoseconds: UInt64?
            let hostNanoseconds: UInt64?
            let postHostNanoseconds: UInt64?
            let totalNanoseconds: UInt64
        }

        let schemaVersion: Int
        let callbacks: [Callback]
        let truncated: Bool
    }

    struct Test3RenderCallbackTrace: Codable, Sendable {
        struct Callback: Codable, Sendable {
            let enteredAtNanoseconds: UInt64
            let inputHostTimeNanoseconds: UInt64?
            let nativeSampleTime: Int64?
            let inputFrameLength: Int
            let inputSampleRate: Double
            let convertedHostTimeNanoseconds: UInt64?
            let convertedSampleCount: Int
            let convertedRMS: Double?
            let timestampFailureReason: String?
            let timestampErrorNanoseconds: Double?
            let status: String
        }

        let schemaVersion: Int
        let callbacks: [Callback]
        let truncated: Bool
    }

    struct Test3AppleInputTrace: Codable, Sendable {
        struct VoiceProcessingState: Codable, Sendable {
            let inputEnabled: Bool
            let outputEnabled: Bool
            let inputBypassed: Bool
            let inputAGCEnabled: Bool
        }

        struct Callback: Codable, Sendable {
            let contentHostTimeNanoseconds: UInt64?
            let nativeSampleTime: Int64?
            let inputFrameLength: Int
            let inputSampleRate: Double
            let inputChannelCount: UInt32
            let inputCommonFormat: String
            let inputIsInterleaved: Bool
            let sampleOffset: Int
            let copiedSampleCount: Int
            let copyNanoseconds: UInt64
        }

        let schemaVersion: Int
        let callbacks: [Callback]
        let sampleCount: Int
        let capturedChannelCount: Int
        let channelSampleCounts: [Int]
        let allChannelsComplete: Bool
        let truncated: Bool
        let unsupportedFormat: Bool
        let atConfiguration: VoiceProcessingState?
        let atCaptureStart: VoiceProcessingState?
    }
    #endif

    private let lock = NSLock()
    private let captureProcessingLock = NSLock()
    private let renderConverterLock = NSLock()
    private let audioProcessingMode: MacSpeechAudioProcessingMode
    private let acousticEchoHost: MacSpeechAcousticEchoHost
    private let voiceActivityDetector: any MacSpeechVoiceActivityDetecting
    private let stopPlayerNode:
        @Sendable (AVAudioPlayerNode?) -> Void
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var captureAECConverter: MacSpeechFloatMono48kConverter?
    private var captureOutputConverter: MacSpeechAudioConverter?
    private var renderAECConverter: MacSpeechFloatMono48kConverter?
    private var isConfigured = false
    private var isCaptureActive = false
    private var isOutputPrepared = false
    private var isOutputPlaying = false
    private var isRenderReferenceTapInstalled = false
    private var outputFormat: AVAudioFormat?
    private var routeRebuildWasConfigured = false
    private var outputPresentationLatencySeconds = 0.0
    private var capturePresentationLatencySeconds = 0.0
    private var captureGenerationFence =
        MacSpeechCaptureGenerationFence()
    #if DEBUG
    private var test3NearEndInjection: Test3NearEndInjection?
    private var test3TimingTraceEnabled = false
    private var test3VADReadSequence: UInt64 = 0
    private var test3VADReads: [Test3AppleVADReadTrace.Read] = []
    private var test3VADReadsTruncated = false
    private var test3SealedVADTrace: MacSpeechTest3VADTrace?
    private static let test3VADReadCapacity = 2_000
    private var test3CaptureCallbacks: [Test3CaptureCallbackTrace.Callback] = []
    private var test3CaptureCallbacksTruncated = false
    private var test3PreviousCaptureCallbackEntry: UInt64?
    private static let test3CaptureCallbackCapacity = 2_500
    private let test3RenderTraceLock = NSLock()
    private var test3RenderTraceEnabled = false
    private var test3RenderCallbacks: [Test3RenderCallbackTrace.Callback] = []
    private var test3RenderCallbacksTruncated = false
    private static let test3RenderCallbackCapacity = 2_500
    private var test3AppleInputCallbacks: [Test3AppleInputTrace.Callback] = []
    private var test3AppleInputSamples: [Float] = []
    private var test3AppleInputAdditionalChannels: [[Float]] = []
    private var test3AppleInputChannelCount = 0
    private var test3AppleInputTruncated = false
    private var test3AppleInputUnsupportedFormat = false
    private var test3VoiceProcessingAtConfiguration:
        Test3AppleInputTrace.VoiceProcessingState?
    private var test3VoiceProcessingAtCaptureStart:
        Test3AppleInputTrace.VoiceProcessingState?
    private static let test3AppleInputSampleCapacity = 960_000
    private static let audioUnitDiagnosticLogger = Logger(
        subsystem: "com.eterna.aftelle",
        category: "AudioUnitAttribution"
    )
    #endif

    init(
        audioProcessingMode: MacSpeechAudioProcessingMode = .webRTCAEC3,
        acousticEchoHost: MacSpeechAcousticEchoHost? = nil,
        voiceActivityDetector: any MacSpeechVoiceActivityDetecting =
            SystemMacSpeechVoiceActivityDetector(),
        stopPlayerNode: @escaping @Sendable (
            AVAudioPlayerNode?
        ) -> Void = { $0?.stop() }
    ) {
        self.audioProcessingMode = audioProcessingMode
        self.voiceActivityDetector = voiceActivityDetector
        self.stopPlayerNode = stopPlayerNode
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
                    nativeSampleTime: when.isSampleTimeValid
                        ? when.sampleTime : nil,
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
            #if DEBUG
            if audioProcessingMode == .appleVoiceProcessing {
                test3VoiceProcessingAtCaptureStart =
                    test3VoiceProcessingState(engine)
            }
            #endif
            refreshAcousticEchoPresentationLatencyLocked()
            isCaptureActive = true
            return describe(inputFormat)
        }
    }

    func stopCapture() {
        let runningEngine = lock.withLock { () -> AVAudioEngine? in
            guard isCaptureActive, let activeEngine = engine else { return nil }
            isCaptureActive = false
            return activeEngine
        }
        guard let runningEngine else { return }
        runningEngine.inputNode.removeTap(onBus: 0)
        lock.withLock {
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
            acousticEchoHost.playbackStarted()
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
                throw error
            }
        }
    }

    func pauseOutput() throws {
        try lock.withLock {
            guard isOutputPrepared, isOutputPlaying, let playerNode else {
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            playerNode.pause()
        }
    }

    func resumeOutput() throws {
        try lock.withLock {
            guard isOutputPrepared, isOutputPlaying, let playerNode else {
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            playerNode.play()
        }
    }

    func finishOutputPlayback() {
        lock.withLock {
            isOutputPlaying = false
            acousticEchoHost.playbackCompleted()
        }
    }

    func clearScheduledOutput() {
        let playerNode = lock.withLock { self.playerNode }
        stopPlayerNodeOutsideStateLock(playerNode, reason: "clear")
        lock.withLock {
            isOutputPlaying = false
            acousticEchoHost.playbackStopped()
        }
    }

    func stopOutput() {
        let playerNode = lock.withLock { self.playerNode }
        stopPlayerNodeOutsideStateLock(playerNode, reason: "stop")
        lock.withLock {
            isOutputPlaying = false
            acousticEchoHost.playbackStopped()
            if !isCaptureActive {
                engine?.stop()
            }
        }
    }

    func closeOutput() {
        let playerNode = lock.withLock { self.playerNode }
        stopPlayerNodeOutsideStateLock(playerNode, reason: "close")
        lock.withLock {
            isOutputPlaying = false
            acousticEchoHost.playbackStopped()
            isOutputPrepared = false
            tearDownIfIdle()
        }
    }

    private func stopPlayerNodeOutsideStateLock(
        _ playerNode: AVAudioPlayerNode?,
        reason: String
    ) {
        #if DEBUG
        let startedAt = DispatchTime.now().uptimeNanoseconds
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_output_node_stop phase=will_stop reason=\(reason, privacy: .public) sample=\(startedAt)"
        )
        #endif
        stopPlayerNode(playerNode)
        let renderConverter = renderConverterLock.withLock { renderAECConverter }
        renderConverter?.resetForGenerationTransition()
        #if DEBUG
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_output_node_stop phase=did_stop reason=\(reason, privacy: .public) sample=\(DispatchTime.now().uptimeNanoseconds)"
        )
        #endif
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
                  engine.outputNode.isVoiceProcessingEnabled else {
                throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
            }
            #if DEBUG
            test3VoiceProcessingAtConfiguration =
                test3VoiceProcessingState(engine)
            test3VoiceProcessingAtCaptureStart = nil
            #endif
        } else if inputNode.isVoiceProcessingEnabled
                    || engine.outputNode.isVoiceProcessingEnabled {
            throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
        }
        try rebuildAudioFormatsLocked(engine: engine, localFormat: localFormat)
        installRenderReferenceTapLocked(playerNode: playerNode)
        _ = acousticEchoHost.configure()
        guard audioProcessingMode != .appleVoiceProcessing
                || voiceActivityDetector.start() else {
            removeRenderReferenceTapLocked(playerNode: playerNode)
            throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
        }
        self.engine = engine
        self.playerNode = playerNode
        outputFormat = localFormat
        isConfigured = true
    }

    private func tearDownIfIdle() {
        guard !isCaptureActive, !isOutputPrepared else { return }
        voiceActivityDetector.stop()
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

    func routeWillRebuild() {
        lock.withLock {
            guard isConfigured else { return }
            routeRebuildWasConfigured = true
            logAudioUnitLifecycle("route_will_rebuild")
            if let playerNode {
                removeRenderReferenceTapLocked(playerNode: playerNode)
            }
            voiceActivityDetector.stop()
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
                            playerNode: playerNode
                        )
                    }
                }
                guard audioProcessingMode != .appleVoiceProcessing
                        || voiceActivityDetector.start() else {
                    throw MacSpeechAudioCaptureError
                        .voiceProcessingUnavailable
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

    func causalInterruptionObservation()
        -> MacSpeechCausalInterruptionObservation {
        acousticEchoHost.causalInterruptionObservation()
    }

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot {
        acousticEchoHost.acousticObservationSnapshot()
    }

    func resetAcousticEchoDiagnostics() {
        acousticEchoHost.resetDiagnostics()
    }

    #if DEBUG
    func setTest3NearEndInjection(samples: [Float], startAtNanoseconds: UInt64) {
        captureProcessingLock.withLock {
            test3NearEndInjection = Test3NearEndInjection(
                samples: samples, startAtNanoseconds: startAtNanoseconds
            )
        }
    }

    func clearTest3NearEndInjection() {
        captureProcessingLock.withLock { test3NearEndInjection = nil }
    }

    func test3NearEndInjectionSnapshot()
        -> (startedAtNanoseconds: UInt64?, injectedSampleCount: Int) {
        captureProcessingLock.withLock {
            (test3NearEndInjection?.startedAtNanoseconds,
             test3NearEndInjection?.injectedSampleCount ?? 0)
        }
    }

    func systemVoiceActivityForTesting() -> Bool {
        acousticEchoHost.systemVoiceActivityForTesting()
    }

    func armTest3TimingTrace() -> Bool {
        captureProcessingLock.withLock {
            let channelCount = lock.withLock {
                Int(engine?.inputNode.outputFormat(forBus: 0).channelCount ?? 0)
            }
            guard (1...8).contains(channelCount) else { return false }
            guard acousticEchoHost.armTest3TimingTrace() else {
                return false
            }
            test3TimingTraceEnabled = true
            test3VADReadSequence = 0
            test3VADReads = []
            test3VADReads.reserveCapacity(Self.test3VADReadCapacity)
            test3VADReadsTruncated = false
            test3SealedVADTrace = nil
            test3CaptureCallbacks = []
            test3CaptureCallbacks.reserveCapacity(
                Self.test3CaptureCallbackCapacity
            )
            test3CaptureCallbacksTruncated = false
            test3PreviousCaptureCallbackEntry = nil
            test3AppleInputCallbacks = []
            test3AppleInputCallbacks.reserveCapacity(
                Self.test3CaptureCallbackCapacity
            )
            test3AppleInputSamples = []
            test3AppleInputSamples.reserveCapacity(
                Self.test3AppleInputSampleCapacity
            )
            test3AppleInputChannelCount = channelCount
            test3AppleInputAdditionalChannels = []
            test3AppleInputAdditionalChannels.reserveCapacity(channelCount - 1)
            for _ in 1..<channelCount {
                var samples: [Float] = []
                samples.reserveCapacity(Self.test3AppleInputSampleCapacity)
                test3AppleInputAdditionalChannels.append(samples)
            }
            test3AppleInputTruncated = false
            test3AppleInputUnsupportedFormat = false
            test3RenderTraceLock.withLock {
                test3RenderTraceEnabled = true
                test3RenderCallbacks = []
                test3RenderCallbacks.reserveCapacity(
                    Self.test3RenderCallbackCapacity
                )
                test3RenderCallbacksTruncated = false
            }
            return true
        }
    }

    func test3TimingTraceSnapshot() -> MacSpeechTest3TimingTrace {
        acousticEchoHost.test3TimingTraceSnapshot()
    }

    func test3RenderTimingBounds() -> (firstContent: UInt64?, latest: UInt64?) {
        acousticEchoHost.test3RenderTimingBounds()
    }

    func sealTest3TimingTrace() {
        captureProcessingLock.withLock {
            test3TimingTraceEnabled = false
            test3RenderTraceLock.withLock {
                test3RenderTraceEnabled = false
            }
            test3SealedVADTrace = (voiceActivityDetector
                as? SystemMacSpeechVoiceActivityDetector)?
                .test3TraceSnapshot()
            acousticEchoHost.sealTest3TimingTrace()
        }
    }

    func test3AppleDecisionSnapshot() -> (
        trace: MacSpeechTest3AppleDecisionTrace,
        processedSamples: [Float]
    ) {
        acousticEchoHost.test3AppleDecisionSnapshot()
    }

    func test3AppleVADReadSnapshot() -> Test3AppleVADReadTrace {
        captureProcessingLock.withLock {
            Test3AppleVADReadTrace(
                schemaVersion: 1,
                reads: test3VADReads,
                detector: test3SealedVADTrace ?? (voiceActivityDetector
                    as? SystemMacSpeechVoiceActivityDetector)?
                    .test3TraceSnapshot(),
                truncated: test3VADReadsTruncated
            )
        }
    }

    func test3CaptureCallbackSnapshot() -> Test3CaptureCallbackTrace {
        captureProcessingLock.withLock {
            Test3CaptureCallbackTrace(
                schemaVersion: 1,
                callbacks: test3CaptureCallbacks,
                truncated: test3CaptureCallbacksTruncated
            )
        }
    }

    func test3AppleInputSnapshot() -> (
        trace: Test3AppleInputTrace,
        samples: [Float],
        additionalChannels: [[Float]]
    ) {
        captureProcessingLock.withLock {
            let counts = [test3AppleInputSamples.count]
                + test3AppleInputAdditionalChannels.map(\.count)
            let complete = !test3AppleInputTruncated
                && !test3AppleInputUnsupportedFormat
                && counts.count == test3AppleInputChannelCount
                && counts.allSatisfy { $0 == test3AppleInputSamples.count }
                && test3AppleInputCallbacks.allSatisfy {
                    $0.copiedSampleCount == $0.inputFrameLength
                }
            return (Test3AppleInputTrace(
                schemaVersion: 3,
                callbacks: test3AppleInputCallbacks,
                sampleCount: test3AppleInputSamples.count,
                capturedChannelCount: test3AppleInputChannelCount,
                channelSampleCounts: counts,
                allChannelsComplete: complete,
                truncated: test3AppleInputTruncated,
                unsupportedFormat: test3AppleInputUnsupportedFormat,
                atConfiguration: test3VoiceProcessingAtConfiguration,
                atCaptureStart: test3VoiceProcessingAtCaptureStart
            ), test3AppleInputSamples, test3AppleInputAdditionalChannels)
        }
    }

    func test3RenderCallbackSnapshot() -> Test3RenderCallbackTrace {
        test3RenderTraceLock.withLock {
            Test3RenderCallbackTrace(
                schemaVersion: 2,
                callbacks: test3RenderCallbacks,
                truncated: test3RenderCallbacksTruncated
            )
        }
    }

    func armAcousticReplayCapture(
        attemptID: UUID,
        targetCaptureFrameCount: Int = 1_000
    ) -> Bool {
        acousticEchoHost.armAcousticReplayCapture(
            attemptID: attemptID,
            targetCaptureFrameCount: targetCaptureFrameCount
        )
    }

    func sealAcousticReplayCapture(
        reason: MacSpeechAcousticReplaySealReason = .manual,
        matchingAttemptID attemptID: UUID? = nil
    ) {
        acousticEchoHost.sealAcousticReplayCapture(
            reason: reason,
            matchingAttemptID: attemptID
        )
    }

    func acousticReplayCaptureSnapshot()
        -> MacSpeechAcousticReplayCaptureSnapshot? {
        acousticEchoHost.acousticReplayCaptureSnapshot()
    }

    func clearAcousticReplayCapture(matchingAttemptID attemptID: UUID? = nil) {
        acousticEchoHost.clearAcousticReplayCapture(
            matchingAttemptID: attemptID
        )
    }
    #endif

    private func processCapture(
        _ buffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?,
        nativeSampleTime: Int64?,
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) {
        #if DEBUG
        let enteredAt = DispatchTime.now().uptimeNanoseconds
        #endif
        captureProcessingLock.withLock {
            #if DEBUG
            let acquiredAt = DispatchTime.now().uptimeNanoseconds
            #endif
            guard captureGenerationFence.accepts(
                hostTimeNanoseconds: hostTimeNanoseconds
            ) else { return }
            let stages = processCaptureLocked(
                buffer,
                hostTimeNanoseconds: hostTimeNanoseconds,
                nativeSampleTime: nativeSampleTime,
                generation: generation,
                frameBuffer: frameBuffer
            )
            #if DEBUG
            if test3TimingTraceEnabled {
                let completedAt = DispatchTime.now().uptimeNanoseconds
                if test3CaptureCallbacks.count
                    < Self.test3CaptureCallbackCapacity {
                    test3CaptureCallbacks.append(.init(
                        contentHostTimeNanoseconds: hostTimeNanoseconds,
                        nativeSampleTime: nativeSampleTime,
                        enteredAtNanoseconds: enteredAt,
                        previousEntryIntervalNanoseconds:
                            test3PreviousCaptureCallbackEntry.map {
                                enteredAt &- $0
                            },
                        inputFrameLength: Int(buffer.frameLength),
                        inputSampleRate: buffer.format.sampleRate,
                        convertedSampleCount: stages?.convertedSampleCount ?? 0,
                        convertedHostTimeNanoseconds:
                            stages?.convertedHostTimeNanoseconds,
                        lockWaitNanoseconds: acquiredAt &- enteredAt,
                        conversionNanoseconds: stages.map {
                            $0.convertedAt &- acquiredAt
                        },
                        hostNanoseconds: stages.map {
                            $0.hostCompletedAt &- $0.convertedAt
                        },
                        postHostNanoseconds: stages.map {
                            completedAt &- $0.hostCompletedAt
                        },
                        totalNanoseconds: completedAt &- enteredAt
                    ))
                } else {
                    test3CaptureCallbacksTruncated = true
                }
                test3PreviousCaptureCallbackEntry = enteredAt
            }
            #endif
        }
    }

    private func processCaptureLocked(
        _ buffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?,
        nativeSampleTime: Int64?,
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) -> (
        convertedAt: UInt64,
        hostCompletedAt: UInt64,
        convertedSampleCount: Int,
        convertedHostTimeNanoseconds: UInt64?
    )? {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let converters = lock.withLock {
            (captureAECConverter, captureOutputConverter)
        }
        #if DEBUG
        recordTest3AppleInput(
            buffer,
            hostTimeNanoseconds: hostTimeNanoseconds,
            nativeSampleTime: nativeSampleTime
        )
        #endif
        guard let inputConverter = converters.0,
              let outputConverter = converters.1,
              var converted = try? inputConverter.convert(
                  buffer, hostTimeNanoseconds: hostTimeNanoseconds,
                  sampleTime: nativeSampleTime
              ) else {
            return nil
        }
        #if DEBUG
        let injectedSampleCountBefore =
            test3NearEndInjection?.injectedSampleCount ?? 0
        test3NearEndInjection?.mix(
            into: &converted.samples,
            hostTimeNanoseconds: converted.hostTimeNanoseconds ?? startedAt
        )
        let injectedNearEndInThisCapture =
            (test3NearEndInjection?.injectedSampleCount ?? 0)
                > injectedSampleCountBefore
        #endif
        #if DEBUG
        let convertedAt = test3TimingTraceEnabled
            ? DispatchTime.now().uptimeNanoseconds : 0
        #else
        let convertedAt: UInt64 = 0
        #endif
        var systemVoiceActivityForFrame: ((UInt64?) -> (Bool?, UInt64?))?
        if audioProcessingMode == .appleVoiceProcessing {
            systemVoiceActivityForFrame = { [self] frameHostTimeNanoseconds in
                #if DEBUG
                let detectorRead = test3TimingTraceEnabled
                    ? (voiceActivityDetector
                        as? SystemMacSpeechVoiceActivityDetector)?
                        .test3CaptureRead(at: frameHostTimeNanoseconds)
                    : nil
                let detectorState: Bool?
                if let detectorRead {
                    detectorState = detectorRead.detected
                } else {
                    detectorState = voiceActivityDetector.voiceActivityState(
                        at: frameHostTimeNanoseconds
                    )
                }
                let voiceActivityDetected: Bool? =
                    injectedNearEndInThisCapture ? true : detectorState
                let readSequence: UInt64?
                if test3TimingTraceEnabled {
                    test3VADReadSequence &+= 1
                    readSequence = test3VADReadSequence
                    if test3VADReads.count < Self.test3VADReadCapacity {
                        test3VADReads.append(.init(
                            sequence: test3VADReadSequence,
                            captureHostTimeNanoseconds:
                                frameHostTimeNanoseconds,
                            sampledAtNanoseconds:
                                DispatchTime.now().uptimeNanoseconds,
                            sampleCount:
                                MacSpeechAcousticEchoHost.frameSampleCount,
                            detectorEventSequence:
                                detectorRead?.eventSequence,
                            detectorEventNanoseconds:
                                detectorRead?.lastEventNanoseconds,
                            detectorReadNanoseconds:
                                detectorRead?.lastReadNanoseconds,
                            detectorReadStatus:
                                detectorRead?.lastReadStatus,
                            detectorVoiceDetected: detectorState,
                            effectiveVoiceDetected: voiceActivityDetected
                        ))
                    } else {
                        test3VADReadsTruncated = true
                    }
                } else {
                    readSequence = nil
                }
                #else
                let voiceActivityDetected = voiceActivityDetector
                    .voiceActivityState(at: frameHostTimeNanoseconds)
                let readSequence: UInt64? = nil
                #endif
                return (voiceActivityDetected, readSequence)
            }
        }
        let captureSpans = acousticEchoHost.processCaptureSpans(
            converted.samples,
            hostTimeNanoseconds: converted.hostTimeNanoseconds,
            systemVoiceActivityForFrame: systemVoiceActivityForFrame
        )
        #if DEBUG
        let hostCompletedAt = test3TimingTraceEnabled
            ? DispatchTime.now().uptimeNanoseconds : 0
        #else
        let hostCompletedAt: UInt64 = 0
        #endif
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
        return (
            convertedAt,
            hostCompletedAt,
            converted.samples.count,
            converted.hostTimeNanoseconds
        )
    }

    #if DEBUG
    private func recordTest3AppleInput(
        _ buffer: AVAudioPCMBuffer,
        hostTimeNanoseconds: UInt64?,
        nativeSampleTime: Int64?
    ) {
        guard test3TimingTraceEnabled,
              audioProcessingMode == .appleVoiceProcessing else { return }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let count = Int(buffer.frameLength)
        let sampleOffset = test3AppleInputSamples.count
        let channels = buffer.floatChannelData
        let formatSupported = buffer.format.commonFormat == .pcmFormatFloat32
            && !buffer.format.isInterleaved && channels != nil
            && Int(buffer.format.channelCount) == test3AppleInputChannelCount
        var copied = 0
        if formatSupported,
           let channels,
           sampleOffset + count <= Self.test3AppleInputSampleCapacity,
           !test3AppleInputTruncated,
           !test3AppleInputUnsupportedFormat,
           test3AppleInputAdditionalChannels.allSatisfy({
               $0.count == sampleOffset
                   && $0.count + count <= Self.test3AppleInputSampleCapacity
           }) {
            test3AppleInputSamples.append(contentsOf: UnsafeBufferPointer(
                start: channels[0], count: count
            ))
            for index in test3AppleInputAdditionalChannels.indices {
                test3AppleInputAdditionalChannels[index].append(
                    contentsOf: UnsafeBufferPointer(
                        start: channels[index + 1], count: count
                    )
                )
            }
            copied = count
        } else if !formatSupported {
            test3AppleInputUnsupportedFormat = true
        } else {
            test3AppleInputTruncated = true
        }
        guard test3AppleInputCallbacks.count
            < Self.test3CaptureCallbackCapacity else {
            test3AppleInputTruncated = true
            return
        }
        test3AppleInputCallbacks.append(.init(
            contentHostTimeNanoseconds: hostTimeNanoseconds,
            nativeSampleTime: nativeSampleTime,
            inputFrameLength: count,
            inputSampleRate: buffer.format.sampleRate,
            inputChannelCount: buffer.format.channelCount,
            inputCommonFormat: String(describing: buffer.format.commonFormat),
            inputIsInterleaved: buffer.format.isInterleaved,
            sampleOffset: sampleOffset,
            copiedSampleCount: copied,
            copyNanoseconds: DispatchTime.now().uptimeNanoseconds &- startedAt
        ))
    }
    #endif

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
        playerNode: AVAudioPlayerNode
    ) {
        guard !isRenderReferenceTapInstalled else { return }
        playerNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            format: nil
        ) { [weak self] buffer, when in
            self?.processRenderedOutput(
                buffer,
                hostTimeNanoseconds: Self.hostTimeNanoseconds(when),
                nativeSampleTime: when.isSampleTimeValid
                    ? when.sampleTime : nil
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
        hostTimeNanoseconds: UInt64?,
        nativeSampleTime: Int64?
    ) {
        #if DEBUG
        let enteredAtNanoseconds = DispatchTime.now().uptimeNanoseconds
        #endif
        let converter = renderConverterLock.withLock { renderAECConverter }
        guard let converter else {
            #if DEBUG
            recordTest3RenderCallback(
                buffer, enteredAtNanoseconds: enteredAtNanoseconds,
                hostTimeNanoseconds: hostTimeNanoseconds,
                nativeSampleTime: nativeSampleTime,
                converted: nil, status: "converter_unavailable"
            )
            #endif
            acousticEchoHost.renderConversionFailed()
            return
        }
        do {
            let converted = try converter.convert(
                buffer, hostTimeNanoseconds: hostTimeNanoseconds,
                sampleTime: nativeSampleTime
            )
            #if DEBUG
            recordTest3RenderCallback(
                buffer, enteredAtNanoseconds: enteredAtNanoseconds,
                hostTimeNanoseconds: hostTimeNanoseconds,
                nativeSampleTime: nativeSampleTime,
                converted: converted,
                status: converted.hostTimeNanoseconds == nil
                    ? "converted_timestamp_missing" : "ok"
            )
            #endif
            acousticEchoHost.processRender(
                converted.samples,
                hostTimeNanoseconds: converted.hostTimeNanoseconds
            )
        } catch {
            #if DEBUG
            recordTest3RenderCallback(
                buffer, enteredAtNanoseconds: enteredAtNanoseconds,
                hostTimeNanoseconds: hostTimeNanoseconds,
                nativeSampleTime: nativeSampleTime,
                converted: nil, status: "conversion_failed"
            )
            #endif
            acousticEchoHost.renderConversionFailed()
        }
    }

    #if DEBUG
    private func recordTest3RenderCallback(
        _ buffer: AVAudioPCMBuffer,
        enteredAtNanoseconds: UInt64,
        hostTimeNanoseconds: UInt64?,
        nativeSampleTime: Int64?,
        converted: MacSpeechFloatMono48kConverter.Output?,
        status: String
    ) {
        test3RenderTraceLock.withLock {
            guard test3RenderTraceEnabled else { return }
            guard test3RenderCallbacks.count
                < Self.test3RenderCallbackCapacity else {
                test3RenderCallbacksTruncated = true
                return
            }
            test3RenderCallbacks.append(.init(
                enteredAtNanoseconds: enteredAtNanoseconds,
                inputHostTimeNanoseconds: hostTimeNanoseconds,
                nativeSampleTime: nativeSampleTime,
                inputFrameLength: Int(buffer.frameLength),
                inputSampleRate: buffer.format.sampleRate,
                convertedHostTimeNanoseconds:
                    converted?.hostTimeNanoseconds,
                convertedSampleCount: converted?.samples.count ?? 0,
                convertedRMS: converted.map { output in
                    guard !output.samples.isEmpty else { return 0 }
                    let sum = output.samples.reduce(0.0) {
                        $0 + Double($1) * Double($1)
                    }
                    return sqrt(sum / Double(output.samples.count))
                },
                timestampFailureReason:
                    converted?.timestampFailureReason,
                timestampErrorNanoseconds:
                    converted?.timestampErrorNanoseconds,
                status: status
            ))
        }
    }
    #endif

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

    #if DEBUG
    private func test3VoiceProcessingState(
        _ engine: AVAudioEngine
    ) -> Test3AppleInputTrace.VoiceProcessingState {
        Test3AppleInputTrace.VoiceProcessingState(
            inputEnabled: engine.inputNode.isVoiceProcessingEnabled,
            outputEnabled: engine.outputNode.isVoiceProcessingEnabled,
            inputBypassed: engine.inputNode.isVoiceProcessingBypassed,
            inputAGCEnabled: engine.inputNode.isVoiceProcessingAGCEnabled
        )
    }
    #endif

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

    func causalInterruptionObservation()
        -> MacSpeechCausalInterruptionObservation? {
        audioEngine.causalInterruptionObservation()
    }

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot? {
        audioEngine.acousticObservationSnapshot()
    }

    func resetAcousticEchoDiagnostics() {
        audioEngine.resetAcousticEchoDiagnostics()
    }
}
