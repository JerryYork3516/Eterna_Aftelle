@preconcurrency import AVFoundation
import Foundation
#if DEBUG
    import CoreAudio
#endif
#if DEBUG
import OSLog
    import Synchronization
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
        if pendingSamples.isEmpty {
            pendingTimestamp = contentTimestampNanoseconds
        }
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
    #if DEBUG
        func armNativeVoiceDebug(runID: UUID, generation: UInt64) -> Bool
        func armNativeVoiceDebug(runID: UUID, generation: UInt64, profile: MacSpeechAppleVPDebugProfile) -> Bool
        func configureNativeAcousticWindows(runID: UUID, generation: UInt64, plan: MacSpeechAcousticWindowPlan) -> Bool
        func nativeVoiceDebugSnapshot(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot?
        func sealNativeVoiceDebug(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot?
        func clearNativeVoiceDebug(runID: UUID)
    #endif
}

nonisolated extension MacSpeechAudioCapturing {
    func selectProcessingMode(_ mode: MacSpeechAudioProcessingMode) throws {
        guard mode == .webRTCAEC3 else {
            throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
        }
    }

    func voiceProcessingSnapshot() -> MacSpeechVoiceProcessingSnapshot? {
        nil
    }

    func discardPendingAudioForGenerationTransition() {}
    func routeWillRebuild() {}
    func routeDidRebuild() {}
    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot? { nil }
    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot? { nil }
    func resetAcousticEchoDiagnostics() {}
    #if DEBUG
        func armNativeVoiceDebug(runID _: UUID, generation _: UInt64) -> Bool {
            false
        }

        func armNativeVoiceDebug(runID: UUID, generation: UInt64, profile: MacSpeechAppleVPDebugProfile) -> Bool {
            guard profile == .agcOn else { return false }
            return armNativeVoiceDebug(runID: runID, generation: generation)
        }

        func configureNativeAcousticWindows(
            runID _: UUID, generation _: UInt64, plan _: MacSpeechAcousticWindowPlan
        ) -> Bool {
            false
        }

        func nativeVoiceDebugSnapshot(runID _: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
            nil
        }

        func sealNativeVoiceDebug(runID _: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
            nil
        }

        func clearNativeVoiceDebug(runID _: UUID) {}
    #endif
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
            if requireContentTime, !validateContentTimeLocked(contentTimestampNanoseconds) {
                return []
            }
            let ratio = MacSpeechAudioInputFormat.sampleRate / inputSampleRate
            let estimatedFrames = ceil(Double(inputBuffer.frameLength) * ratio) + 8
            guard inputBuffer.frameLength > 0, estimatedFrames <= 8192 else {
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
            return try makePacketsLocked(
                samples: samples,
                outputBuffer: outputBuffer,
                ratio: ratio,
                activityEvidenceKind: activityEvidenceKind,
                acousticSnapshot: acousticSnapshot
            )
        }
    }

    private func validateContentTimeLocked(_ timestamp: UInt64?) -> Bool {
        guard contentTimeValid, let timestamp, timestamp > 0 else {
            contentTimeValid = false
            packetizer.reset()
            return false
        }
        if contentAnchor == nil {
            contentAnchor = timestamp
        }
        let expected = Double(contentAnchor!)
            + Double(inputSampleCount) * 1_000_000_000 / inputSampleRate
        guard abs(Double(timestamp) - expected) <= (1_000_000_000 / inputSampleRate).rounded(.up) else {
            contentTimeValid = false
            packetizer.reset()
            return false
        }
        return true
    }

    private func makePacketsLocked(
        samples: UnsafeMutablePointer<Float>,
        outputBuffer: AVAudioPCMBuffer,
        ratio: Double,
        activityEvidenceKind: MacSpeechAudioActivityEvidenceKind,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot?
    ) throws -> [MacSpeechPCM16Packet] {
        try withExtendedLifetime(outputBuffer) {
            let count = Int(outputBuffer.frameLength)
            guard Double(outputSampleCount) + Double(count)
                <= Double(inputSampleCount) * ratio + 0.000_001
            else {
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
            let outputBuffer = try makeOutputBufferLocked(
                frameLength: inputBuffer.frameLength, ratio: ratio
            )
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
            recordInputTimeLocked(
                frameLength: inputBuffer.frameLength,
                ratio: ratio,
                sampleTime: sampleTime,
                hostTimeNanoseconds: hostTimeNanoseconds
            )
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

    private func outputHostTime(sampleCount: Int) -> UInt64? {
        guard sampleCount > 0 else { return nil }
        let start = Double(outputSampleCount)
        let end = start + Double(sampleCount)
        let intervals = inputTimes.filter { $0.end > start && $0.start < end }
        guard let last = intervals.last,
              last.end + 0.000_001 >= end
        else {
            return nil
        }
        guard let first = intervals.first,
              first.start <= start
        else {
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
            return unanchoredInputHostTimeLocked(
                hostTimeNanoseconds: hostTimeNanoseconds,
                inputFrameCount: inputFrameCount
            )
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
        if overflow {
            sampleTimeContinuityValid = false
        }
        nextInputSampleTime = overflow ? nil : next
        guard sampleTimeContinuityValid,
              continuousInputHostTimeLocked(
                  hostTimeNanoseconds: hostTimeNanoseconds, inputFrameCount: inputFrameCount
              ) != nil,
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
              timestamp < Double(UInt64.max)
        else {
            sampleTimeContinuityValid = false
            return nil
        }
        return UInt64(timestamp.rounded())
    }

    private func unanchoredInputHostTimeLocked(
        hostTimeNanoseconds: UInt64,
        inputFrameCount: Int
    ) -> UInt64? {
        if sampleTimeAnchor != nil {
            sampleTimeContinuityValid = false
        }
        return continuousInputHostTimeLocked(
            hostTimeNanoseconds: hostTimeNanoseconds, inputFrameCount: inputFrameCount
        )
    }

    private func continuousInputHostTimeLocked(
        hostTimeNanoseconds: UInt64,
        inputFrameCount: Int
    ) -> UInt64? {
        // Compare adjacent hardware times; sampleTime remains the anchored content clock.
        if let previousInputHostTime {
            let expected = Double(previousInputHostTime)
                + Double(previousInputFrameCount)
                * 1_000_000_000 / inputSampleRate
            let tolerance = (1_000_000_000 / inputSampleRate).rounded(.up)
            let difference = abs(Double(hostTimeNanoseconds) - expected)
            if hostTimeNanoseconds <= previousInputHostTime || difference > tolerance {
                sampleTimeContinuityValid = false
            }
        }
        previousInputHostTime = hostTimeNanoseconds
        previousInputFrameCount = inputFrameCount
        return sampleTimeContinuityValid ? hostTimeNanoseconds : nil
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

private extension MacSpeechFloatMono48kConverter {
    func makeOutputBufferLocked(
        frameLength: AVAudioFrameCount,
        ratio: Double
    ) throws -> AVAudioPCMBuffer {
        let estimatedFrames = ceil(Double(frameLength) * ratio)
        guard frameLength > 0,
              estimatedFrames <= 16384,
              inputTimes.count < 64
        else {
            throw MacSpeechAudioCaptureError.conversionFailed
        }
        let capacity = AVAudioFrameCount(max(1, estimatedFrames))
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            throw MacSpeechAudioCaptureError.conversionFailed
        }
        return outputBuffer
    }

    func recordInputTimeLocked(
        frameLength: AVAudioFrameCount,
        ratio: Double,
        sampleTime: Int64?,
        hostTimeNanoseconds: UInt64?
    ) {
        let start = Double(inputFrameCount) * ratio
        let inputTime = anchoredInputHostTime(
            sampleTime: sampleTime,
            hostTimeNanoseconds: hostTimeNanoseconds,
            inputFrameCount: Int(frameLength)
        )
        inputFrameCount += UInt64(frameLength)
        inputTimes.append(InputTime(
            start: start, end: Double(inputFrameCount) * ratio,
            hostTimeNanoseconds: inputTime
        ))
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

#if DEBUG
    nonisolated enum MacSpeechAppleVPDebugProfile: String, CaseIterable, Sendable {
        case agcOn = "APPLE_VP_AGC_ON"
        case agcOff = "APPLE_VP_AGC_OFF"

        var automaticGainControlEnabled: Bool {
            self == .agcOn
        }

        func accepts(_ snapshot: MacSpeechVoiceProcessingSnapshot) -> Bool {
            snapshot.mode == .appleVoiceProcessing && snapshot.inputEnabled && snapshot.outputEnabled
                && !snapshot.bypassed && !snapshot.inputMuted
                && snapshot.automaticGainControlEnabled == automaticGainControlEnabled
        }
    }

    nonisolated enum MacSpeechWarmupProfile: String, CaseIterable, Sendable {
        case zero = "WARMUP_0S"
        case four = "WARMUP_4S"

        var nanoseconds: UInt64 {
            self == .four ? 4_000_000_000 : 0
        }
    }

    nonisolated struct MacSpeechAcousticWindowPlan: Sendable, Equatable {
        static let names = ["warmup", "human_only", "double_talk", "human_tail", "quiet"]
        let captureStartedAt: UInt64
        let scoreStartedAt: UInt64
        let scoreEndedAt: UInt64

        init?(captureStartedAt: UInt64, profile: MacSpeechWarmupProfile) {
            let score = captureStartedAt.addingReportingOverflow(profile.nanoseconds)
            let end = score.partialValue.addingReportingOverflow(15_000_000_000)
            guard captureStartedAt > 0, !score.overflow, !end.overflow else { return nil }
            self.captureStartedAt = captureStartedAt
            scoreStartedAt = score.partialValue
            scoreEndedAt = end.partialValue
        }

        func bounds(_ index: Int) -> (UInt64, UInt64) {
            switch index {
            case 0: (captureStartedAt, scoreStartedAt)
            case 1: (scoreStartedAt, scoreStartedAt + 3_000_000_000)
            case 2: (scoreStartedAt + 3_000_000_000, scoreStartedAt + 9_000_000_000)
            case 3: (scoreStartedAt + 9_000_000_000, scoreStartedAt + 11_000_000_000)
            default: (scoreStartedAt + 11_000_000_000, scoreEndedAt)
            }
        }

        func window(start: UInt64, end: UInt64) -> Int? {
            guard start < end else { return nil }
            for index in 0 ..< Self.names.count {
                let (lower, upper) = bounds(index)
                if start >= lower, end <= upper {
                    return index
                }
            }
            return nil
        }
    }

    nonisolated struct MacSpeechAcousticWindowStats: Sendable, Equatable {
        let plan: MacSpeechAcousticWindowPlan
        private var levels = Array(repeating: MacSpeechNativeVoiceDebugChannel(), count: 40)
        private var equalSamples = Array(repeating: UInt64(0), count: 40)
        private var comparedSamples = Array(repeating: UInt64(0), count: 40)
        private var firstContent = [UInt64?](repeating: nil, count: 5)
        private var lastContentEnd = [UInt64?](repeating: nil, count: 5)
        private var channels = 0
        private var rate = 0.0
        private(set) var excludedFrames: UInt64 = 0
        private(set) var invalidBuffers: UInt64 = 0
        let framesBeforeConfiguration: UInt64

        init(plan: MacSpeechAcousticWindowPlan, framesBeforeConfiguration: UInt64 = 0) {
            self.plan = plan
            self.framesBeforeConfiguration = framesBeforeConfiguration
        }

        mutating func recordNative(_ buffer: AVAudioPCMBuffer, hostTime: UInt64?) {
            guard let hostTime, hostTime > 0, buffer.format.sampleRate.isFinite,
                  buffer.format.sampleRate > 0, buffer.format.channelCount <= 8
            else {
                invalidBuffers &+= 1
                return
            }
            channels = Int(buffer.format.channelCount)
            rate = buffer.format.sampleRate
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for frame in 0 ..< Int(buffer.frameLength) {
                guard let window = frameWindow(frame, hostTime: hostTime) else { continue }
                let first = nativeSample(buffers, format: buffer.format, frame: frame, channel: 0)
                for channel in 0 ..< channels {
                    let value = channel == 0 ? first
                        : nativeSample(buffers, format: buffer.format, frame: frame, channel: channel)
                    record(value, reference: first.0, channel: channel, window: window)
                }
            }
        }

        mutating func recordPCM(_ bytes: Data, hostTime: UInt64) {
            guard bytes.count == 960, hostTime > 0 else {
                invalidBuffers &+= 1
                return
            }
            channels = 1
            rate = 24000
            bytes.withUnsafeBytes { data in
                for frame in 0 ..< 480 {
                    guard let window = frameWindow(frame, hostTime: hostTime) else { continue }
                    let value = Int16(littleEndian: data.loadUnaligned(fromByteOffset: frame * 2, as: Int16.self))
                    let sample = Double(value) / 32768
                    record((sample, value == .min || value == .max), reference: sample, channel: 0, window: window)
                }
            }
        }

        private mutating func frameWindow(_ frame: Int, hostTime: UInt64) -> Int? {
            let start = hostTime.addingReportingOverflow(UInt64((Double(frame) * 1e9 / rate).rounded(.down)))
            let end = hostTime.addingReportingOverflow(UInt64((Double(frame + 1) * 1e9 / rate).rounded(.up)))
            guard !start.overflow, !end.overflow,
                  let index = plan.window(start: start.partialValue, end: end.partialValue)
            else {
                excludedFrames &+= 1
                return nil
            }
            firstContent[index] = firstContent[index] ?? start.partialValue
            lastContentEnd[index] = end.partialValue
            return index
        }

        private func nativeSample(
            _ buffers: UnsafeMutableAudioBufferListPointer, format: AVAudioFormat, frame: Int, channel: Int
        ) -> (Double, Bool) {
            let item = buffers[format.isInterleaved ? 0 : channel]
            guard let data = item.mData else { return (.nan, false) }
            let index = format.isInterleaved ? frame * channels + channel : frame
            return MacSpeechNativeVoiceDebugStats.sample(data, index: index, format: format.commonFormat)
        }

        private mutating func record(_ sample: (Double, Bool), reference: Double, channel: Int, window: Int) {
            let index = window * 8 + channel
            _ = levels[index].record(sample.0, fullScale: sample.1)
            if reference.isFinite, sample.0.isFinite {
                comparedSamples[index] &+= 1
                equalSamples[index] &+= sample.0 == reference ? 1 : 0
            }
        }

        func manifest() -> [String: Any] {
            var windows = [[String: Any]]()
            for index in 0 ..< 5 {
                let (start, end) = plan.bounds(index)
                let rows = (0 ..< channels).map { channel -> [String: Any] in
                    let slot = index * 8 + channel
                    var row = Self.levelManifest(levels[slot])
                    row["compared_to_ch0_finite_samples"] = comparedSamples[slot]
                    row["numerically_equal_to_ch0_samples"] = equalSamples[slot]
                    return row
                }
                windows.append(["name": MacSpeechAcousticWindowPlan.names[index], "start_ns": start,
                                "end_ns": end, "first_content_ns": firstContent[index] ?? NSNull() as Any,
                                "last_content_end_ns": lastContentEnd[index] ?? NSNull() as Any, "channels": rows])
            }
            return ["windows": windows, "sample_rate": rate, "excluded_boundary_or_outside_frames": excludedFrames,
                    "native_frames_before_window_configuration": framesBeforeConfiguration,
                    "invalid_buffers": invalidBuffers, "source": "processed_samples_not_raw_microphone",
                    "equality": "numeric_finite_samples_only_not_physical_channel_identity"]
        }

        static func levelManifest(_ level: MacSpeechNativeVoiceDebugChannel) -> [String: Any] {
            ["samples": level.sampleCount, "rms": level.rms ?? NSNull() as Any,
             "peak": level.peakMagnitude ?? NSNull() as Any, "full_scale": level.fullScaleCount,
             "non_finite": level.nonFiniteCount, "exact_zero_samples": level.zeroCount,
             "maximum_adjacent_sample_step": level.maximumAdjacentStep]
        }
    }

    nonisolated struct MacSpeechNativeVoiceDebugFormat: Sendable, Equatable {
        let sampleRate: Double
        let channelCount: UInt32
        let sampleFormat: String
        let isInterleaved: Bool

        init(_ format: AVAudioFormat) {
            sampleRate = format.sampleRate
            channelCount = format.channelCount
            sampleFormat = Self.name(format.commonFormat)
            isInterleaved = format.isInterleaved
        }

        private static func name(_ format: AVAudioCommonFormat) -> String {
            switch format {
            case .pcmFormatFloat32: "float32"
            case .pcmFormatFloat64: "float64"
            case .pcmFormatInt16: "int16"
            case .pcmFormatInt32: "int32"
            default: "other"
            }
        }
    }

    nonisolated struct MacSpeechNativeVoiceDebugChannel: Sendable, Equatable {
        private(set) var sampleCount: UInt64 = 0
        private(set) var peakMagnitude: Double?
        private(set) var fullScaleCount: UInt64 = 0
        private(set) var overScaleCount: UInt64 = 0
        private(set) var nonFiniteCount: UInt64 = 0
        private(set) var sumSquares = 0.0
        private(set) var zeroCount: UInt64 = 0
        private(set) var maximumAdjacentStep = 0.0
        private var previousFiniteSample: Double?

        var rms: Double? {
            sampleCount > 0 && nonFiniteCount == 0 ? sqrt(sumSquares / Double(sampleCount)) : nil
        }

        fileprivate mutating func record(_ sample: Double, fullScale: Bool) -> Bool {
            sampleCount &+= 1
            guard sample.isFinite else {
                nonFiniteCount &+= 1
                peakMagnitude = nil
                return false
            }
            sumSquares += sample * sample
            zeroCount &+= sample == 0 ? 1 : 0
            if let previousFiniteSample {
                maximumAdjacentStep = max(maximumAdjacentStep, abs(sample - previousFiniteSample))
            }
            previousFiniteSample = sample
            if nonFiniteCount == 0 {
                peakMagnitude = max(peakMagnitude ?? 0, abs(sample))
            }
            if fullScale {
                fullScaleCount &+= 1
            }
            if abs(sample) > 1 {
                overScaleCount &+= 1
            }
            return true
        }
    }

    nonisolated struct MacSpeechRawTimestampSample: Sendable, Equatable {
        let timestamp: AudioTimeStamp
        let timestampSampleRate: Double
        let hostNanoseconds: UInt64?
        let samplePosition: Int64?
        let bufferFormat: AudioStreamBasicDescription
        let frames: UInt32
        let arrivalNanoseconds: UInt64

        static func == (lhs: Self, rhs: Self) -> Bool {
            let left = lhs.timestamp, right = rhs.timestamp
            let leftSMPTE = left.mSMPTETime, rightSMPTE = right.mSMPTETime
            let leftFormat = lhs.bufferFormat, rightFormat = rhs.bufferFormat
            return left.mSampleTime.bitPattern == right.mSampleTime.bitPattern
                && left.mHostTime == right.mHostTime && left.mRateScalar.bitPattern == right.mRateScalar.bitPattern
                && left.mWordClockTime == right.mWordClockTime && left.mFlags == right.mFlags
                && left.mReserved == right.mReserved && leftSMPTE.mSubframes == rightSMPTE.mSubframes
                && leftSMPTE.mSubframeDivisor == rightSMPTE.mSubframeDivisor && leftSMPTE.mCounter == rightSMPTE
                .mCounter
                && leftSMPTE.mType == rightSMPTE.mType && leftSMPTE.mFlags == rightSMPTE.mFlags && leftSMPTE
                .mHours == rightSMPTE.mHours
                && leftSMPTE.mMinutes == rightSMPTE.mMinutes && leftSMPTE.mSeconds == rightSMPTE.mSeconds && leftSMPTE
                .mFrames == rightSMPTE.mFrames
                && lhs.timestampSampleRate.bitPattern == rhs.timestampSampleRate.bitPattern
                && lhs.hostNanoseconds == rhs.hostNanoseconds && lhs.samplePosition == rhs.samplePosition
                && leftFormat.mSampleRate.bitPattern == rightFormat.mSampleRate.bitPattern && leftFormat
                .mFormatID == rightFormat.mFormatID
                && leftFormat.mFormatFlags == rightFormat.mFormatFlags && leftFormat.mBytesPerPacket == rightFormat
                .mBytesPerPacket
                && leftFormat.mFramesPerPacket == rightFormat.mFramesPerPacket && leftFormat
                .mBytesPerFrame == rightFormat.mBytesPerFrame
                && leftFormat.mChannelsPerFrame == rightFormat.mChannelsPerFrame && leftFormat
                .mBitsPerChannel == rightFormat.mBitsPerChannel
                && leftFormat.mReserved == rightFormat.mReserved && lhs.frames == rhs.frames
                && lhs.arrivalNanoseconds == rhs.arrivalNanoseconds
        }
    }

    nonisolated struct MacSpeechRawTimestampDiagnostic: Sendable, Equatable {
        enum Fault: String, Sendable {
            case nativeClock = "native_clock"
            case contentTime = "content_time"
            case missingHostTime = "missing_host_time"
        }

        private(set) var previous2: MacSpeechRawTimestampSample?
        private(set) var previous1: MacSpeechRawTimestampSample?
        private(set) var current: MacSpeechRawTimestampSample?
        private(set) var following1: MacSpeechRawTimestampSample?
        private(set) var following2: MacSpeechRawTimestampSample?
        private(set) var fault: Fault?

        var isComplete: Bool {
            following2 != nil
        }

        mutating func record(_ sample: MacSpeechRawTimestampSample) {
            if fault == nil {
                previous2 = previous1
                previous1 = current
                current = sample
            } else if following1 == nil {
                following1 = sample
            } else if following2 == nil {
                following2 = sample
            }
        }

        mutating func markFirstAnomaly(_ reason: Fault) {
            guard fault == nil, current != nil else { return }
            fault = reason
        }
    }

    private extension MacSpeechRawTimestampSample {
        func manifest(previous: Self?) -> [String: Any] {
            let stamp = timestamp, smpte = stamp.mSMPTETime, format = bufferFormat
            let scalarValid = stamp.mFlags.contains(.rateScalarValid) && stamp.mRateScalar.isFinite
                && stamp.mRateScalar > 0
            var result: [String: Any] = [
                "raw_audio_timestamp": [
                    "sample_time": Self.finite(stamp.mSampleTime), "sample_time_bits": String(
                        stamp.mSampleTime.bitPattern,
                        radix: 16
                    ),
                    "host_ticks": stamp.mHostTime, "rate_scalar": Self.finite(stamp.mRateScalar),
                    "rate_scalar_bits": String(stamp.mRateScalar.bitPattern, radix: 16),
                    "word_clock_time": stamp.mWordClockTime, "flags": stamp.mFlags.rawValue,
                    "reserved": stamp.mReserved,
                    "smpte": ["subframes": smpte.mSubframes, "subframe_divisor": smpte.mSubframeDivisor,
                              "counter": smpte.mCounter, "type": smpte.mType.rawValue, "flags": smpte.mFlags.rawValue,
                              "hours": smpte.mHours, "minutes": smpte.mMinutes, "seconds": smpte.mSeconds,
                              "frames": smpte.mFrames]
                ],
                "host_time_valid": stamp.mFlags.contains(.hostTimeValid),
                "sample_time_valid": stamp.mFlags.contains(.sampleTimeValid),
                "rate_scalar_valid": scalarValid,
                "valid_rate_scalar": scalarValid ? stamp.mRateScalar : NSNull() as Any,
                "timestamp_sample_rate": Self.finite(timestampSampleRate),
                "converted_host_ns": hostNanoseconds ?? NSNull() as Any,
                "converted_sample_position": samplePosition ?? NSNull() as Any,
                "buffer_frames": frames, "buffer_asbd": [
                    "sample_rate": Self.finite(format.mSampleRate), "format_id": format.mFormatID,
                    "format_flags": format.mFormatFlags, "bytes_per_packet": format.mBytesPerPacket,
                    "frames_per_packet": format.mFramesPerPacket, "bytes_per_frame": format.mBytesPerFrame,
                    "channels": format.mChannelsPerFrame, "bits_per_channel": format.mBitsPerChannel,
                    "reserved": format.mReserved
                ],
                "callback_arrival_ns": arrivalNanoseconds
            ]
            if let previous {
                result["host_delta_ns"] = Self.delta(hostNanoseconds, previous.hostNanoseconds)
                result["sample_delta_frames"] = samplePosition.flatMap { current in
                    previous.samplePosition.map { Double(current) - Double($0) }
                } ?? NSNull() as Any
                result["expected_sample_delta_frames"] = previous.frames
                let rate = previous.bufferFormat.mSampleRate
                result["expected_host_delta_ns"] = rate.isFinite && rate > 0
                    ? Double(previous.frames) * 1e9 / rate : NSNull() as Any
                result["arrival_delta_ns"] = Self.delta(arrivalNanoseconds, previous.arrivalNanoseconds)
            }
            return result
        }

        static func finite(_ value: Double) -> Any {
            value.isFinite ? value : NSNull()
        }

        static func delta(_ current: UInt64?, _ previous: UInt64?) -> Any {
            guard let current, let previous else { return NSNull() }
            return current >= previous ? Double(current - previous) : -Double(previous - current)
        }
    }

    extension MacSpeechRawTimestampDiagnostic {
        /// Called only by the existing control-path JSON export, never by an audio callback.
        func manifest(runID: UUID, generation: UInt64, configurationID: UInt64?, sealed: Bool) -> [String: Any] {
            let slots = [previous2, previous1, current, following1, following2]
            let rows = slots.enumerated().compactMap { index, sample -> [String: Any]? in
                guard let sample else { return nil }
                var row = sample.manifest(previous: index > 0 ? slots[index - 1] : nil)
                row["relative_callback"] = index - 2
                return row
            }
            return ["run_id": runID.uuidString, "generation": generation,
                    "configuration_id": configurationID ?? NSNull() as Any,
                    "first_fault": fault?.rawValue ?? NSNull() as Any,
                    "maximum_callbacks": 5, "callbacks": rows, "sealed": sealed,
                    "following_status": isComplete ? "complete" :
                        (sealed ? "unavailable_after_seal" : "awaiting_callbacks"),
                    "host_clock": "mach_absolute_time converted by existing AVAudioTime helper",
                    "arrival_clock": "DispatchTime.uptimeNanoseconds auxiliary only"]
        }
    }

    nonisolated struct MacSpeechNativeVoiceDebugSnapshot: Sendable, Equatable {
        let runID: UUID
        let captureGeneration: UInt64
        let profile: MacSpeechAppleVPDebugProfile
        let configurationID: UInt64?
        let isSealed: Bool
        let sealReason: String?
        let coverageValid: Bool
        let issues: [String]
        let voiceProcessing: MacSpeechVoiceProcessingSnapshot?
        let nativeFormat: MacSpeechNativeVoiceDebugFormat?
        let channels: [MacSpeechNativeVoiceDebugChannel]
        let nativeBufferCount: UInt64
        let nativeFrameCount: UInt64
        let packetCount: UInt64
        let packetByteCount: UInt64
        let firstNativeHostTime: UInt64?
        let lastNativeHostTime: UInt64?
        let firstNativeSampleTime: Int64?
        let lastNativeSampleTime: Int64?
        let firstPacketTime: UInt64?
        let lastPacketTime: UInt64?
        let rejections: [String: UInt64]
        let acousticWindows: MacSpeechAcousticWindowStats?
        let rawTimestampDiagnostic: MacSpeechRawTimestampDiagnostic?
    }

    private nonisolated enum MacSpeechNativeVoiceDebugReason: String, CaseIterable {
        case staleContext = "stale_context"
        case captureFence = "capture_fence"
        case inputConversion = "input_conversion"
        case contentTime = "content_time"
        case outputConversion = "output_conversion"
        case packetTime = "packet_time"
        case bufferRejected = "buffer_rejected"
        case packetLength = "packet_length"
        case nativeCapacity = "native_capacity"
        case nativeFormat = "native_format"
        case nativeClock = "native_clock"
        case nonFinite = "non_finite"
        case configurationChanged = "configuration_changed"
        case captureStopped = "capture_stopped"
        case routeChanged = "route_changed"
        case voiceProcessing = "voice_processing"
        case packetClock = "packet_clock"
        case other
    }

    nonisolated struct MacSpeechNativeVoiceDebugStats: Sendable {
        static let maxChannels = 8
        static let maxNativeFrames = 16384
        private static let reasons = MacSpeechNativeVoiceDebugReason.allCases.map(\.rawValue)

        let runID: UUID
        let captureGeneration: UInt64
        let timing: MacSpeechNativeVoiceTiming?
        let profile: MacSpeechAppleVPDebugProfile
        private(set) var isSealed = false
        private var sealReason: String?
        private var configurationID: UInt64?
        private var voiceProcessing: MacSpeechVoiceProcessingSnapshot?
        private var nativeFormat: MacSpeechNativeVoiceDebugFormat?
        private var channelStats = Array(
            repeating: MacSpeechNativeVoiceDebugChannel(), count: Self.maxChannels
        )
        private var observedChannels = 0
        private var rejectionCounts = Array(repeating: UInt64(0), count: Self.reasons.count)
        private var nativeBufferCount: UInt64 = 0
        private var nativeFrameCount: UInt64 = 0
        private var packetCount: UInt64 = 0
        private var packetByteCount: UInt64 = 0
        private var firstNativeHostTime: UInt64?
        private var lastNativeHostTime: UInt64?
        private var firstNativeSampleTime: Int64?
        private var lastNativeSampleTime: Int64?
        private var previousNativeFrames = 0
        private var firstPacketTime: UInt64?
        private var lastPacketTime: UInt64?
        private var acousticWindows: MacSpeechAcousticWindowStats?
        private var rawTimestampDiagnostic = MacSpeechRawTimestampDiagnostic()

        init(
            runID: UUID, generation: UInt64, timing: MacSpeechNativeVoiceTiming? = nil,
            profile: MacSpeechAppleVPDebugProfile = .agcOn
        ) {
            self.runID = runID
            captureGeneration = generation
            self.timing = timing
            self.profile = profile
        }

        mutating func bind(
            configurationID: UInt64,
            voiceProcessing: MacSpeechVoiceProcessingSnapshot?
        ) {
            guard !isSealed else { return }
            guard configurationID > 0, captureGeneration > 0 else {
                reject("stale_context")
                return
            }
            if let current = self.configurationID {
                if current != configurationID {
                    seal(reason: "configuration_changed")
                }
                return
            }
            self.configurationID = configurationID
            self.voiceProcessing = voiceProcessing
            guard let voiceProcessing,
                  voiceProcessing.configurationID == configurationID,
                  voiceProcessing.validatedAtNanoseconds > 0,
                  profile.accepts(voiceProcessing),
                  !voiceProcessing.inputMuted
            else {
                reject("voice_processing")
                return
            }
        }

        mutating func configureWindows(_ plan: MacSpeechAcousticWindowPlan) -> Bool {
            let warmup = plan.scoreStartedAt - plan.captureStartedAt
            guard !isSealed, acousticWindows == nil, let voiceProcessing,
                  configurationID == voiceProcessing.configurationID,
                  rejectionCounts.allSatisfy({ $0 == 0 }), profile.accepts(voiceProcessing),
                  profile == .agcOn || warmup == MacSpeechWarmupProfile.four.nanoseconds
            else { return false }
            acousticWindows = MacSpeechAcousticWindowStats(plan: plan, framesBeforeConfiguration: nativeFrameCount)
            return true
        }

        mutating func recordRawTimestamp(
            _ buffer: AVAudioPCMBuffer, time: AVAudioTime,
            content: (host: UInt64?, sample: Int64?), arrival: UInt64,
            identity: (configurationID: UInt64, generation: UInt64)
        ) {
            guard !isSealed, configurationID == identity.configurationID, captureGeneration == identity.generation,
                  !rawTimestampDiagnostic.isComplete else { return }
            rawTimestampDiagnostic.record(MacSpeechRawTimestampSample(
                timestamp: time.audioTimeStamp, timestampSampleRate: time.sampleRate,
                hostNanoseconds: content.host, samplePosition: content.sample,
                bufferFormat: buffer.format.streamDescription.pointee, frames: buffer.frameLength,
                arrivalNanoseconds: arrival
            ))
            if content.host == nil {
                rawTimestampDiagnostic.markFirstAnomaly(.missingHostTime)
            }
        }

        mutating func recordNative(
            _ buffer: AVAudioPCMBuffer,
            hostTimeNanoseconds: UInt64?,
            sampleTime: Int64?,
            configurationID: UInt64,
            generation: UInt64
        ) {
            guard accepts(configurationID: configurationID, generation: generation) else { return }
            nativeBufferCount &+= 1
            nativeFrameCount &+= UInt64(buffer.frameLength)
            let format = MacSpeechNativeVoiceDebugFormat(buffer.format)
            guard nativeFormat == nil || nativeFormat == format else {
                reject("native_format")
                return
            }
            nativeFormat = format
            guard buffer.frameLength > 0, Int(buffer.frameLength) <= Self.maxNativeFrames,
                  format.channelCount > 0, Int(format.channelCount) <= Self.maxChannels
            else {
                reject("native_capacity")
                return
            }
            recordClock(hostTime: hostTimeNanoseconds, sampleTime: sampleTime, frames: Int(buffer.frameLength))
            guard let sampleBytes = Self.sampleBytes(buffer.format.commonFormat),
                  validLayout(buffer, sampleBytes: sampleBytes)
            else {
                reject("native_format")
                return
            }
            observedChannels = Int(format.channelCount)
            recordSamples(buffer)
            acousticWindows?.recordNative(buffer, hostTime: hostTimeNanoseconds)
        }

        mutating func recordPacket(
            timestamp: UInt64,
            byteCount: Int,
            accepted: Bool,
            configurationID: UInt64,
            generation: UInt64
        ) {
            guard accepts(configurationID: configurationID, generation: generation) else { return }
            guard timestamp > 0, byteCount >= 0 else {
                reject("packet_time")
                return
            }
            if let previous = lastPacketTime {
                let expected = previous.addingReportingOverflow(20_000_000)
                if expected.overflow || expected.partialValue != timestamp {
                    reject("packet_clock")
                }
            }
            firstPacketTime = firstPacketTime ?? timestamp
            lastPacketTime = timestamp
            packetCount &+= 1
            packetByteCount &+= UInt64(byteCount)
            if byteCount != MacSpeechAudioInputFormat.packetByteCount {
                reject("packet_length")
            }
            if !accepted {
                reject("buffer_rejected")
            }
        }

        mutating func reject(_ reason: String) {
            guard !isSealed else { return }
            let index = Self.reasons.firstIndex(of: reason) ?? Self.reasons.count - 1
            rejectionCounts[index] &+= 1
            if reason == "native_clock" {
                rawTimestampDiagnostic.markFirstAnomaly(.nativeClock)
            }
            if reason == "content_time" {
                rawTimestampDiagnostic.markFirstAnomaly(.contentTime)
            }
        }

        mutating func seal(reason: String? = nil) {
            guard !isSealed else { return }
            if let reason {
                let index = Self.reasons.firstIndex(of: reason) ?? Self.reasons.count - 1
                sealReason = Self.reasons[index]
                reject(reason)
            }
            isSealed = true
        }

        var snapshot: MacSpeechNativeVoiceDebugSnapshot {
            let rejections = Dictionary(uniqueKeysWithValues: zip(Self.reasons, rejectionCounts))
            let issues = Self.reasons.filter { rejections[$0, default: 0] > 0 }
            return MacSpeechNativeVoiceDebugSnapshot(
                runID: runID, captureGeneration: captureGeneration, profile: profile, configurationID: configurationID,
                isSealed: isSealed, sealReason: sealReason,
                coverageValid: configurationID != nil && nativeBufferCount > 0 && packetCount > 0 && issues.isEmpty,
                issues: issues, voiceProcessing: voiceProcessing, nativeFormat: nativeFormat,
                channels: Array(channelStats.prefix(observedChannels)),
                nativeBufferCount: nativeBufferCount, nativeFrameCount: nativeFrameCount,
                packetCount: packetCount, packetByteCount: packetByteCount,
                firstNativeHostTime: firstNativeHostTime, lastNativeHostTime: lastNativeHostTime,
                firstNativeSampleTime: firstNativeSampleTime, lastNativeSampleTime: lastNativeSampleTime,
                firstPacketTime: firstPacketTime, lastPacketTime: lastPacketTime, rejections: rejections,
                acousticWindows: acousticWindows,
                rawTimestampDiagnostic: rawTimestampDiagnostic.fault == nil ? nil : rawTimestampDiagnostic
            )
        }

        private mutating func accepts(configurationID: UInt64, generation: UInt64) -> Bool {
            guard !isSealed else { return false }
            guard self.configurationID == configurationID, captureGeneration == generation else {
                reject("stale_context")
                return false
            }
            return true
        }

        private mutating func recordClock(hostTime: UInt64?, sampleTime: Int64?, frames: Int) {
            defer {
                lastNativeHostTime = hostTime
                lastNativeSampleTime = sampleTime
                previousNativeFrames = frames
            }
            guard let hostTime, hostTime > 0, let sampleTime,
                  let nativeFormat, nativeFormat.sampleRate.isFinite, nativeFormat.sampleRate > 0
            else {
                reject("native_clock")
                return
            }
            firstNativeHostTime = firstNativeHostTime ?? hostTime
            firstNativeSampleTime = firstNativeSampleTime ?? sampleTime
            if let previousHost = lastNativeHostTime, let previousSample = lastNativeSampleTime {
                let duration = 1_000_000_000 / nativeFormat.sampleRate
                let expectedHost = Double(previousHost) + Double(previousNativeFrames) * duration
                let expectedSample = previousSample.addingReportingOverflow(Int64(previousNativeFrames))
                let discontinuous = abs(Double(hostTime) - expectedHost) > duration.rounded(.up)
                    || expectedSample.overflow || expectedSample.partialValue != sampleTime
                if discontinuous {
                    reject("native_clock")
                }
            }
        }

        private static func sampleBytes(_ format: AVAudioCommonFormat) -> Int? {
            switch format {
            case .pcmFormatFloat32, .pcmFormatInt32: 4
            case .pcmFormatInt16: 2
            default: nil
            }
        }
    }

    private extension MacSpeechNativeVoiceDebugStats {
        private func validLayout(_ buffer: AVAudioPCMBuffer, sampleBytes: Int) -> Bool {
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let channels = Int(buffer.format.channelCount)
            guard buffers.count > 0, buffers.count <= Self.maxChannels else { return false }
            if buffer.format.isInterleaved {
                guard buffers.count == 1 else { return false }
            } else if buffers.count != channels {
                return false
            }
            var totalChannels = 0
            for item in buffers {
                let itemChannels = Int(item.mNumberChannels)
                let requiredBytes = Int(buffer.frameLength) * itemChannels * sampleBytes
                guard itemChannels > 0, itemChannels <= channels,
                      buffer.format.isInterleaved || itemChannels == 1,
                      item.mData != nil, Int(item.mDataByteSize) >= requiredBytes else { return false }
                totalChannels += itemChannels
            }
            return totalChannels == channels
        }

        private mutating func recordSamples(_ buffer: AVAudioPCMBuffer) {
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            var channelOffset = 0
            var finite = true
            for item in buffers {
                guard let data = item.mData else { return }
                let channelCount = Int(item.mNumberChannels)
                for frame in 0 ..< Int(buffer.frameLength) {
                    for channel in 0 ..< channelCount {
                        let sample = Self.sample(
                            data, index: frame * channelCount + channel, format: buffer.format.commonFormat
                        )
                        if !channelStats[channelOffset + channel].record(sample.0, fullScale: sample.1) {
                            finite = false
                        }
                    }
                }
                channelOffset += channelCount
            }
            if !finite {
                reject("non_finite")
            }
        }

        static func sample(
            _ data: UnsafeMutableRawPointer,
            index: Int,
            format: AVAudioCommonFormat
        ) -> (Double, Bool) {
            switch format {
            case .pcmFormatFloat32:
                let value = Double(data.assumingMemoryBound(to: Float.self)[index])
                return (value, abs(value) >= 1)
            case .pcmFormatInt16:
                let value = data.assumingMemoryBound(to: Int16.self)[index]
                return (Double(value) / 32768, value == .min || value == .max)
            case .pcmFormatInt32:
                let value = data.assumingMemoryBound(to: Int32.self)[index]
                return (Double(value) / 2_147_483_648, value == .min || value == .max)
            default:
                return (.nan, false)
            }
        }
    }

#endif

#if DEBUG
    nonisolated enum MacSpeechRuntimeReadback {
        static let sharedIODeviceSetBinding = "PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED"

        enum Phase: String, Encodable, Sendable { case engineStarted, residentPlaybackStarted }

        struct Identity {
            let runID: UUID
            let generation: UInt64
            let configurationID: UInt64
        }

        struct Stream: Encodable, Sendable, Equatable {
            let owner: UInt32
            let direction: UInt32
            let start: UInt32
            let channels: UInt32
            let rate: Double
        }

        struct Device: Encodable, Sendable, Equatable {
            let id: UInt32
            let transport: UInt32
            let aggregate: Bool
            let alive: Bool
            let inputChannels: UInt32
            let outputChannels: UInt32
            let inputStreams: [Stream]
            let outputStreams: [Stream]
        }

        struct Aggregate: Encodable, Sendable, Equatable {
            let device: Device
            let members: [Device]
            let activeMembers: [UInt32]
            let tapCount: Int?
            let activeTapCount: Int?

            func qualifies(input: Device, output: Device) -> Bool {
                guard device.aggregate, !input.aggregate, !output.aggregate, input.id != output.id,
                      device.alive, members.count == 2, activeMembers.count == 2,
                      Set(activeMembers) == Set([input.id, output.id]), tapCount == 0, activeTapCount == 0,
                      let microphone = members.first(where: { $0 == input }),
                      let speaker = members.first(where: { $0 == output }),
                      microphone.alive, speaker.alive,
                      microphone.inputChannels > 0, microphone.outputChannels == 0,
                      speaker.inputChannels == 0, speaker.outputChannels > 0,
                      device.inputChannels == microphone.inputChannels,
                      device.outputChannels == speaker.outputChannels
                else { return false }
                return directionMatches(input: true) && directionMatches(input: false)
            }

            private func directionMatches(input: Bool) -> Bool {
                let direction: UInt32 = input ? 1 : 0
                var expected: [UInt32] = []
                for member in members {
                    let streams = input ? member.inputStreams : member.outputStreams
                    guard Self.valid(streams, direction: direction, owner: member.id),
                          streams.reduce(0, { $0 + $1.channels })
                          == (input ? member.inputChannels : member.outputChannels) else { return false }
                    expected.append(contentsOf: streams.map(\.channels))
                }
                let streams = input ? device.inputStreams : device.outputStreams
                return Self.valid(streams, direction: direction, owner: device.id)
                    && streams.map(\.channels) == expected
            }

            static func valid(_ streams: [Stream], direction: UInt32, owner: UInt32) -> Bool {
                guard streams.count <= 16 else { return false }
                var next: UInt32 = 1
                for stream in streams {
                    guard stream.owner == owner, stream.direction == direction, stream.start == next,
                          stream.channels > 0, stream.channels <= 64, next <= 65 - stream.channels,
                          stream.rate.isFinite, stream.rate > 0 else { return false }
                    next += stream.channels
                }
                return true
            }
        }

        struct Route: Encodable, Sendable, Equatable {
            let defaultInput: Device
            let defaultOutput: Device
            let actualInput: Device
            let actualOutput: Device
            let aggregates: [Aggregate]

            var binding: String {
                guard defaultInput.id > 0, defaultOutput.id > 0, actualInput.id > 0, actualOutput.id > 0,
                      defaultInput.alive, defaultOutput.alive, actualInput.alive, actualOutput.alive
                else { return "UNKNOWN_UNAVAILABLE_DEVICE" }
                if actualInput == defaultInput, actualOutput == defaultOutput {
                    return "NODE_IDS_MATCH_DEFAULTS"
                }
                let input = actualInput == defaultInput || aggregates.contains {
                    $0.device == actualInput && $0.qualifies(input: defaultInput, output: defaultOutput)
                }
                let output = actualOutput == defaultOutput || aggregates.contains {
                    $0.device == actualOutput && $0.qualifies(input: defaultInput, output: defaultOutput)
                }
                return input && output ? "AGGREGATE_IO_DIRECTION_QUALIFIED" : "UNKNOWN_UNVERIFIED_BINDING"
            }
        }

        struct Payload: Encodable, Sendable, Equatable {
            let readStartedAtNs: UInt64
            let readFinishedAtNs: UInt64
            let voiceProcessing: [String: Bool]
            let formats: [String: MacSpeechPlaybackFormatWitness]
            let playerMixerBus: Int?
            let mixerOutputConnected: Bool
            var route: Route?
            var issues: [String]
            var bindingStatus: String = "UNKNOWN"
            var processBinding = ProcessBinding()
        }

        enum QueryFailure: Error { case property(UInt32, Int32), invalidProperty(UInt32), unavailable(UInt32) }

        struct ProcessQuery: Encodable, Sendable, Equatable {
            let operation: String
            let scope: UInt32?
            let status: String
            let osStatus: Int32?
            var failedSelector: UInt32?
        }

        struct ProcessDirection: Encodable, Sendable, Equatable {
            let scope: UInt32
            var deviceIDs: [UInt32] = []
            var devices: [Device] = []
            var aggregates: [Aggregate] = []
            var status = "UNKNOWN"
            var bindingStatus = "UNKNOWN"
        }

        struct ProcessBinding: Encodable, Sendable, Equatable {
            var requestedPID: Int32?
            var processObjectID: UInt32?
            var observedPID: Int32?
            var observedPIDAfter: Int32?
            var readStartedAtNs: UInt64?
            var readFinishedAtNs: UInt64?
            var input: ProcessDirection?
            var output: ProcessDirection?
            var queries: [ProcessQuery] = []
            var status = "UNAVAILABLE"
            let meaning = "Process direction metadata; not AU endpoints, physical-source proof"
                + " or Apple internal AEC reference"
        }

        struct ConfigurationEvent: Encodable, Sendable, Equatable {
            let atNs: UInt64
            let runID: UUID
            let generation: UInt64
            let configurationID: UInt64
            let lifecyclePhase: String
        }

        struct ConfigurationEvents: Encodable, Sendable, Equatable {
            var status = "UNAVAILABLE"
            var count: UInt64 = 0
            var first: ConfigurationEvent?
            var skippedNotifications: UInt64 = 0
            var observationClosed = false
        }

        struct ProcessReader {
            let translate: (Int32) throws -> UInt32
            let pid: (UInt32) throws -> Int32
            let devices: (UInt32, UInt32) throws -> [UInt32]
            let device: (UInt32) throws -> MacSpeechRuntimeReadback.Device
            let aggregate: (MacSpeechRuntimeReadback.Device) throws -> MacSpeechRuntimeReadback.Aggregate
        }

        struct Snapshot: Encodable, Sendable, Equatable {
            let schemaVersion = 1
            let phase: Phase
            let runID: UUID
            let captureGeneration: UInt64
            let configurationID: UInt64
            let payload: Payload
        }

        static func record(
            _ phase: Phase, identity: Identity,
            active: Bool, snapshots: inout [Snapshot], read: () -> Payload
        ) -> Bool {
            guard active, identity.generation > 0, identity.configurationID > 0, snapshots.count < 2,
                  !snapshots.contains(where: { $0.phase == phase }) else { return false }
            if let first = snapshots.first {
                guard phase == .residentPlaybackStarted, first.runID == identity.runID,
                      first.captureGeneration == identity.generation, first.configurationID == identity.configurationID
                else { return false }
            } else if phase != .engineStarted {
                return false
            }
            snapshots.append(Snapshot(phase: phase, runID: identity.runID, captureGeneration: identity.generation,
                                      configurationID: identity.configurationID, payload: read()))
            return true
        }
    }

    extension MacSpeechRuntimeReadback {
        static func readProcess(
            pid: Int32, route: MacSpeechRuntimeReadback.Route?, using reader: ProcessReader,
            now: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
        ) -> MacSpeechRuntimeReadback.ProcessBinding {
            var result = MacSpeechRuntimeReadback.ProcessBinding(
                requestedPID: pid,
                readStartedAtNs: now(),
                status: "UNKNOWN"
            )
            do {
                guard pid > 0 else { throw QueryFailure.invalidProperty(kAudioProcessPropertyPID) }
                let id = try processQuery("translatePID", queries: &result.queries) { try reader.translate(pid) }
                result.processObjectID = id
                guard id != kAudioObjectUnknown else {
                    throw QueryFailure.invalidProperty(kAudioHardwarePropertyTranslatePIDToProcessObject)
                }
                let observed = try processQuery("processPID", queries: &result.queries) { try reader.pid(id) }
                result.observedPID = observed
                guard observed == pid else { throw QueryFailure.invalidProperty(kAudioProcessPropertyPID) }
                result.input = processDirection(id, scope: kAudioObjectPropertyScopeInput, route: route,
                                                reader: reader, queries: &result.queries)
                result.output = processDirection(id, scope: kAudioObjectPropertyScopeOutput, route: route,
                                                 reader: reader, queries: &result.queries)
                let after = try processQuery("processPIDAfter", queries: &result.queries) { try reader.pid(id) }
                result.observedPIDAfter = after
                guard after == pid else { throw QueryFailure.invalidProperty(kAudioProcessPropertyPID) }
                if result.input?.status == "CONFIRMED", result.output?.status == "CONFIRMED" {
                    result.status = "CONFIRMED"
                    if let route, qualifiesSharedIODeviceSet(result, route: route) {
                        result.input?.bindingStatus = sharedIODeviceSetBinding
                    }
                }
            } catch {
                result.input?.status = "UNKNOWN"
                result.input?.bindingStatus = "UNKNOWN"
                result.output?.status = "UNKNOWN"
                result.output?.bindingStatus = "UNKNOWN"
                result.queries.append(processFailure("processValidation", scope: nil, error: error))
            }
            result.readFinishedAtNs = now()
            return result
        }

        static func qualifiesSharedIODeviceSet(_ process: ProcessBinding, route: Route) -> Bool {
            let microphone = route.defaultInput
            let speaker = route.defaultOutput
            guard process.status == "CONFIRMED", let input = process.input, let output = process.output,
                  input.status == "CONFIRMED", output.status == "CONFIRMED",
                  input.scope == kAudioObjectPropertyScopeInput, output.scope == kAudioObjectPropertyScopeOutput,
                  microphone.id > 0, speaker.id > 0, microphone.id != speaker.id,
                  microphone.alive, speaker.alive, !microphone.aggregate, !speaker.aggregate,
                  microphone.transport == kAudioDeviceTransportTypeUSB,
                  speaker.transport == kAudioDeviceTransportTypeBuiltIn,
                  microphone.inputChannels > 0, microphone.outputChannels == 0, microphone.outputStreams.isEmpty,
                  speaker.inputChannels > 0, speaker.outputChannels > 0,
                  route.actualInput == speaker, route.actualOutput == speaker, route.aggregates.isEmpty,
                  input.deviceIDs.count == 2, Set(input.deviceIDs) == Set([microphone.id, speaker.id]),
                  input.devices.count == 2, input.devices.contains(microphone), input.devices.contains(speaker),
                  output.deviceIDs == [speaker.id], output.devices == [speaker],
                  input.aggregates.isEmpty, output.aggregates.isEmpty
            else { return false }
            // This qualifies process membership metadata, never the physical source or internal AEC reference.
            return true
        }

        private static func processDirection(
            _ id: UInt32, scope: UInt32, route: MacSpeechRuntimeReadback.Route?, reader: ProcessReader,
            queries: inout [ProcessQuery]
        ) -> ProcessDirection {
            var result = ProcessDirection(scope: scope)
            do {
                result.deviceIDs = try processQuery("processDevices", scope: scope, queries: &queries) {
                    try reader.devices(id, scope)
                }
                guard !result.deviceIDs.isEmpty, result.deviceIDs.count <= 16,
                      Set(result.deviceIDs).count == result.deviceIDs.count
                else {
                    throw QueryFailure.invalidProperty(kAudioProcessPropertyDevices)
                }
                try processQuery("deviceMetadata", scope: scope, queries: &queries) {
                    for deviceID in result.deviceIDs {
                        let value = try reader.device(deviceID)
                        let input = scope == kAudioObjectPropertyScopeInput
                        let streams = input ? value.inputStreams : value.outputStreams
                        let channels = input ? value.inputChannels : value.outputChannels
                        guard value.id == deviceID, value.id != kAudioObjectUnknown, value.alive, channels > 0,
                              MacSpeechRuntimeReadback.Aggregate.valid(
                                  streams,
                                  direction: input ? 1 : 0,
                                  owner: deviceID
                              ),
                              streams.reduce(0, { $0 + $1.channels }) == channels
                        else {
                            throw QueryFailure.invalidProperty(kAudioDevicePropertyStreams)
                        }
                        result.devices.append(value)
                        if value.aggregate {
                            try result.aggregates.append(reader.aggregate(value))
                        }
                    }
                }
                result.status = "CONFIRMED"
                if let route, result.devices.count == 1, let value = result.devices.first {
                    let expected = scope == kAudioObjectPropertyScopeInput ? route.defaultInput : route.defaultOutput
                    if value == expected {
                        result.bindingStatus = "PROCESS_DEVICE_METADATA_MATCHES_DEFAULT"
                    } else if result.aggregates.contains(where: {
                        $0.device == value && $0.qualifies(input: route.defaultInput, output: route.defaultOutput)
                    }) {
                        result.bindingStatus = "PROCESS_AGGREGATE_DIRECTION_QUALIFIED"
                    }
                }
            } catch {
                result.status = "UNKNOWN"
                result.bindingStatus = "UNKNOWN"
                queries.append(processFailure("directionValidation", scope: scope, error: error))
            }
            return result
        }

        private static func processQuery<T>(
            _ operation: String, scope: UInt32? = nil,
            queries: inout [ProcessQuery], read: () throws -> T
        ) throws -> T {
            do {
                let value = try read()
                queries.append(.init(operation: operation, scope: scope, status: "CONFIRMED", osStatus: noErr))
                return value
            } catch {
                queries.append(processFailure(operation, scope: scope, error: error))
                throw error
            }
        }

        private static func processFailure(
            _ operation: String, scope: UInt32?, error: Error
        ) -> ProcessQuery {
            var result = ProcessQuery(
                operation: operation, scope: scope, status: "UNKNOWN", osStatus: nil
            )
            switch error {
            case let QueryFailure.property(selector, status): result = .init(
                    operation: operation, scope: scope, status: "UNKNOWN", osStatus: status, failedSelector: selector
                )
            case let QueryFailure.invalidProperty(selector): result.failedSelector = selector
            case let QueryFailure.unavailable(selector): result = .init(
                    operation: operation, scope: scope, status: "UNAVAILABLE", osStatus: nil, failedSelector: selector
                )
            default: result = .init(operation: operation, scope: scope, status: "UNKNOWN",
                                    osStatus: Int32(clamping: (error as NSError).code))
            }
            return result
        }
    }

    nonisolated enum MacSpeechTimingEvent: String, CaseIterable, Codable, Sendable {
        case engineStartBefore, engineStartReturned, playerPlayBefore, playerPlayReturned
        case playbackPrepared, playbackStarted, playbackCompleted, captureStopped
        case configurationChanged, routeChanged
    }

    nonisolated struct MacSpeechTimingEventWitness: Codable, Sendable, Equatable {
        let event: MacSpeechTimingEvent
        var firstCallTimeNs: UInt64?
        var lastCallTimeNs: UInt64?
        var count: UInt64 = 0
    }

    nonisolated struct MacSpeechTimingStream: Codable, Sendable, Equatable {
        var firstCallbackArrivalNs: UInt64?
        var lastCallbackArrivalNs: UInt64?
        var callbacks: UInt64 = 0
        var firstArrivalNs: UInt64?
        var lastArrivalNs: UInt64?
        var firstContentHostNs: UInt64?
        var lastContentHostNs: UInt64?
        var lastContentEndNs: UInt64?
        var firstSampleTime: Int64?
        var lastSampleTime: Int64?
        var previousFrames: UInt64 = 0
        var buffers: UInt64 = 0
        var frames: UInt64 = 0
        var missingTime: UInt64 = 0
        var duplicate: UInt64 = 0
        var backwards: UInt64 = 0
        var sampleDiscontinuities: UInt64 = 0
        var hostDiscontinuities: UInt64 = 0
        var maximumStartIntervalNs: UInt64 = 0
        var maximumEndGapNs: UInt64 = 0
        var firstNonzeroContentNs: UInt64?
        var lastNonzeroContentNs: UInt64?
        var firstNonzeroSampleTime: Int64?
        var lastNonzeroSampleTime: Int64?
        var nonzeroFrames: UInt64 = 0

        mutating func recordNonzero(
            content: (host: UInt64?, sample: Int64?), range: ClosedRange<Int>, rate: Double
        ) {
            var firstHost: UInt64?
            var lastHost: UInt64?
            var firstSample: Int64?
            var lastSample: Int64?
            if let host = content.host, host > 0 {
                let firstOffset = UInt64((Double(range.lowerBound) * 1_000_000_000 / rate).rounded())
                let lastOffset = UInt64((Double(range.upperBound) * 1_000_000_000 / rate).rounded())
                let begin = host.addingReportingOverflow(firstOffset)
                let end = host.addingReportingOverflow(lastOffset)
                if !begin.overflow && !end.overflow {
                    firstHost = begin.partialValue
                    lastHost = end.partialValue
                }
            }
            if let sample = content.sample {
                let begin = sample.addingReportingOverflow(Int64(range.lowerBound))
                let end = sample.addingReportingOverflow(Int64(range.upperBound))
                if !begin.overflow && !end.overflow {
                    firstSample = begin.partialValue
                    lastSample = end.partialValue
                }
            }
            if nonzeroFrames == 0 {
                firstNonzeroContentNs = firstHost
                firstNonzeroSampleTime = firstSample
            }
            lastNonzeroContentNs = lastHost
            lastNonzeroSampleTime = lastSample
        }

        mutating func arrived(at time: UInt64) {
            firstCallbackArrivalNs = firstCallbackArrivalNs ?? time
            lastCallbackArrivalNs = time
            callbacks &+= 1
        }

        mutating func record(host: UInt64?, sample: Int64?, arrival: UInt64, count: UInt64, rate: Double) {
            buffers &+= 1
            frames &+= count
            guard let host, host > 0, let sample, rate.isFinite, rate > 0 else {
                missingTime &+= 1
                lastContentHostNs = nil
                lastSampleTime = nil
                lastContentEndNs = nil
                return
            }
            firstArrivalNs = firstArrivalNs ?? arrival
            lastArrivalNs = arrival
            if let previousHost = lastContentHostNs, let previousSample = lastSampleTime {
                if host == previousHost && sample == previousSample {
                    duplicate &+= 1
                }
                if host < previousHost || sample < previousSample {
                    backwards &+= 1
                }
                let expected = previousSample.addingReportingOverflow(Int64(previousFrames))
                if expected.overflow || expected.partialValue != sample {
                    sampleDiscontinuities &+= 1
                }
                let interval = host >= previousHost ? host - previousHost : 0
                maximumStartIntervalNs = max(maximumStartIntervalNs, interval)
                if let end = lastContentEndNs {
                    if host > end {
                        maximumEndGapNs = max(maximumEndGapNs, host - end)
                    }
                    if abs(Double(host) - Double(end)) > ceil(1_000_000_000 / rate) {
                        hostDiscontinuities &+= 1
                    }
                }
            }
            firstContentHostNs = firstContentHostNs ?? host
            firstSampleTime = firstSampleTime ?? sample
            lastContentHostNs = host
            lastSampleTime = sample
            previousFrames = count
            let end = host.addingReportingOverflow(UInt64((Double(count) * 1_000_000_000 / rate).rounded()))
            lastContentEndNs = end.overflow ? nil : end.partialValue
        }
    }

    nonisolated struct MacSpeechPlaybackFormatWitness: Codable, Sendable, Equatable {
        let sampleRate: Double
        let channelCount: UInt32
        let commonFormat: UInt
        let commonFormatName: String
        let interleaved: Bool
        let asbd: [String: Double]
        let layoutTag: UInt32?
        let layoutBitmap: UInt32?
        let layoutDescriptionCount: UInt32?
        let channelDescriptions: [[String: Double]]
        let descriptionsTruncated: Bool

        init(_ format: AVAudioFormat) {
            sampleRate = format.sampleRate
            channelCount = format.channelCount
            commonFormat = format.commonFormat.rawValue
            commonFormatName = String(describing: format.commonFormat)
            interleaved = format.isInterleaved
            let native = format.streamDescription.pointee
            asbd = ["mSampleRate": native.mSampleRate, "mFormatID": Double(native.mFormatID),
                    "mFormatFlags": Double(native.mFormatFlags), "mBytesPerPacket": Double(native.mBytesPerPacket),
                    "mFramesPerPacket": Double(native.mFramesPerPacket),
                    "mBytesPerFrame": Double(native.mBytesPerFrame),
                    "mChannelsPerFrame": Double(native.mChannelsPerFrame),
                    "mBitsPerChannel": Double(native.mBitsPerChannel),
                    "mReserved": Double(native.mReserved)]
            let layout = format.channelLayout?.layout
            layoutTag = layout?.pointee.mChannelLayoutTag
            layoutBitmap = layout?.pointee.mChannelBitmap.rawValue
            layoutDescriptionCount = layout?.pointee.mNumberChannelDescriptions
            descriptionsTruncated = (layoutDescriptionCount ?? 0) > 8
            channelDescriptions = Self.descriptions(layout)
        }

        private static func descriptions(_ layout: UnsafePointer<AudioChannelLayout>?) -> [[String: Double]] {
            guard let layout,
                  let offset = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) else { return [] }
            let pointer = UnsafeRawPointer(layout).advanced(by: offset)
                .assumingMemoryBound(to: AudioChannelDescription.self)
            return (0 ..< min(8, Int(layout.pointee.mNumberChannelDescriptions))).map { index in
                let value = pointer[index]
                return ["label": Double(value.mChannelLabel), "flags": Double(value.mChannelFlags.rawValue),
                        "x": Double(value.mCoordinates.0), "y": Double(value.mCoordinates.1),
                        "z": Double(value.mCoordinates.2)]
            }
        }
    }

    nonisolated struct MacSpeechTimingSnapshot: Encodable, Sendable, Equatable {
        let runID: UUID
        let captureGeneration: UInt64
        var configurationID: UInt64?
        var playbackGeneration: UInt64?
        var events = MacSpeechTimingEvent.allCases.map { MacSpeechTimingEventWitness(event: $0) }
        var input = MacSpeechTimingStream()
        var playerRender = MacSpeechTimingStream()
        var playbackFormat: MacSpeechPlaybackFormatWitness?
        var runtimeReadbacks: [MacSpeechRuntimeReadback.Snapshot] = []
        var engineConfigurationEvents = MacSpeechRuntimeReadback.ConfigurationEvents()
        var staleCallbacks: UInt64 = 0
        var identityChanges: UInt64 = 0
        var invalidBuffers: UInt64 = 0
        var skippedUpdates: UInt64 = 0
        var callbacksClosed = false
        var scheduledFrames: UInt64 = 0
        var scheduledNonzeroFrames: UInt64 = 0
        let tapLocation = "PlayerNode before Mixer; not speaker or Apple internal AEC reference"
        let missingValueMeaning = "Omitted optional fields are UNKNOWN; call/arrival/content clocks are distinct"
        let inputWitnessMeaning = "Metadata-valid tap callback; not proof of downstream PCM acceptance"
        let nonzeroCoverage = "UNKNOWN: scheduled-to-player content alignment is not established"
    }

    /// Updates never wait; only non-realtime control snapshots use bounded acquisition.
    final nonisolated class MacSpeechNativeVoiceTiming: @unchecked Sendable {
        let runID: UUID
        let captureGeneration: UInt64
        private let busy = Atomic<Bool>(false)
        private let skipped = Atomic<UInt64>(0)
        private var state: MacSpeechTimingSnapshot
        private let lifecyclePhase = Atomic<UInt8>(0)
        private let configurationObservationActive = Atomic<Bool>(false)
        private let configurationObservationClosed = Atomic<Bool>(false)
        private let skippedConfigurationNotifications = Atomic<UInt64>(0)
        private var configurationObserver: NSObjectProtocol?
        private var configurationCenter: NotificationCenter?

        init(runID: UUID, generation: UInt64) {
            self.runID = runID
            captureGeneration = generation
            state = MacSpeechTimingSnapshot(runID: runID, captureGeneration: generation)
        }

        private func update(_ body: (inout MacSpeechTimingSnapshot) -> Void) {
            guard busy.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged
            else {
                skipped.wrappingAdd(1, ordering: .relaxed)
                return
            }
            defer { busy.store(false, ordering: .releasing) }
            body(&state)
        }

        func withUpdateForTesting(_ body: () -> Void) {
            update { _ in body() }
        }

        func snapshot(
            clock: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
            wait: () -> Void = { Thread.sleep(forTimeInterval: 0.00025) }
        ) -> MacSpeechTimingSnapshot? {
            guard acquireSnapshotAccess(clock: clock, wait: wait) else { return nil }
            defer { busy.store(false, ordering: .releasing) }
            var result = state
            result.skippedUpdates = skipped.load(ordering: .relaxed)
            result.engineConfigurationEvents.skippedNotifications = skippedConfigurationNotifications
                .load(ordering: .relaxed)
            result.engineConfigurationEvents.observationClosed = !configurationObservationActive
                .load(ordering: .acquiring)
            if result.engineConfigurationEvents.skippedNotifications > 0 {
                result.engineConfigurationEvents.status = "UNKNOWN"
            }
            return result
        }

        private func acquireSnapshotAccess(clock: () -> UInt64, wait: () -> Void) -> Bool {
            let started = clock()
            for attempt in 0 ..< 20 {
                let now = clock()
                guard now >= started, now - started < 5_000_000 else { return false }
                if busy.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged {
                    return true
                }
                if attempt < 19 {
                    wait()
                }
            }
            return false
        }

        /// Registration/removal use the existing lifecycle control path, never the notification queue.
        func observeEngineConfiguration(
            _ object: AnyObject, configurationID: UInt64, center: NotificationCenter = .default
        ) -> Bool {
            guard configurationObserver == nil, !configurationObservationClosed.load(ordering: .acquiring),
                  busy.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged
            else { return false }
            let valid = !state.callbacksClosed && state.configurationID == configurationID
                && configurationID > 0 && captureGeneration > 0
            if valid {
                state.engineConfigurationEvents.status = "CONFIRMED"
            }
            busy.store(false, ordering: .releasing)
            guard valid else { return false }
            configurationObservationActive.store(true, ordering: .releasing)
            configurationCenter = center
            configurationObserver = center.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: object, queue: nil
            ) { [weak self] _ in self?.recordEngineConfiguration(configurationID: configurationID) }
            return true
        }

        func stopObservingEngineConfiguration() {
            configurationObservationActive.store(false, ordering: .releasing)
            configurationObservationClosed.store(true, ordering: .releasing)
            if let configurationObserver {
                configurationCenter?.removeObserver(configurationObserver)
            }
            configurationObserver = nil
            configurationCenter = nil
        }

        deinit { stopObservingEngineConfiguration() }

        func recordEngineConfiguration(
            configurationID: UInt64, at time: UInt64 = DispatchTime.now().uptimeNanoseconds
        ) {
            guard configurationObservationActive.load(ordering: .acquiring) else { return }
            guard busy.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged
            else {
                skippedConfigurationNotifications.wrappingAdd(1, ordering: .relaxed)
                return
            }
            defer { busy.store(false, ordering: .releasing) }
            guard configurationObservationActive.load(ordering: .acquiring), !state.callbacksClosed,
                  state.configurationID == configurationID else { return }
            if state.engineConfigurationEvents.count < .max {
                state.engineConfigurationEvents.count += 1
            }
            if state.engineConfigurationEvents.first == nil {
                state.engineConfigurationEvents.first = .init(
                    atNs: time, runID: runID, generation: captureGeneration,
                    configurationID: configurationID,
                    lifecyclePhase: Self.lifecyclePhaseName(lifecyclePhase.load(ordering: .acquiring))
                )
            }
        }

        func bind(configurationID: UInt64, playbackGeneration: UInt64? = nil) {
            update { value in
                guard configurationID > 0, playbackGeneration != 0 else {
                    value.callbacksClosed = true
                    value.identityChanges &+= 1
                    return
                }
                if let current = value.configurationID, current != configurationID {
                    value.callbacksClosed = true
                    value.identityChanges &+= 1
                } else {
                    value.configurationID = configurationID
                }
                if let playbackGeneration {
                    if let current = value.playbackGeneration, current != playbackGeneration {
                        value.callbacksClosed = true
                        value.identityChanges &+= 1
                    } else {
                        value.playbackGeneration = playbackGeneration
                    }
                }
            }
        }

        func event(_ event: MacSpeechTimingEvent, at time: UInt64 = DispatchTime.now().uptimeNanoseconds) {
            switch event {
            case .engineStartBefore: lifecyclePhase.store(1, ordering: .releasing)
            case .engineStartReturned: lifecyclePhase.store(2, ordering: .releasing)
            case .playerPlayBefore: lifecyclePhase.store(3, ordering: .releasing)
            case .playerPlayReturned: lifecyclePhase.store(4, ordering: .releasing)
            default: break
            }
            update { value in
                guard let index = MacSpeechTimingEvent.allCases.firstIndex(of: event) else { return }
                value.events[index].firstCallTimeNs = value.events[index].firstCallTimeNs ?? time
                value.events[index].lastCallTimeNs = time
                value.events[index].count &+= 1
                if event == .captureStopped || event == .routeChanged {
                    value.callbacksClosed = true
                }
            }
        }

        private static func lifecyclePhaseName(_ value: UInt8) -> String {
            switch value {
            case 1: "engineStarting"
            case 2: "captureRunning"
            case 3: "residentPlaybackStarting"
            case 4: "residentPlaybackRunning"
            default: "capturePrepared"
            }
        }

        func format(_ format: AVAudioFormat) {
            let witness = MacSpeechPlaybackFormatWitness(format)
            update { $0.playbackFormat = witness }
        }

        func input(
            content: (host: UInt64?, sample: Int64?), arrival: UInt64, frames: UInt64, rate: Double,
            identity: (configurationID: UInt64, generation: UInt64)
        ) {
            update { value in
                guard !value.callbacksClosed, value.configurationID == identity.configurationID,
                      value.captureGeneration == identity.generation else { value.staleCallbacks &+= 1; return }
                value.input.arrived(at: arrival)
                guard frames > 0, frames <= 16384, rate.isFinite, rate >= 1, rate <= 768_000 else {
                    value.invalidBuffers &+= 1
                    return
                }
                value.input.record(
                    host: content.host,
                    sample: content.sample,
                    arrival: arrival,
                    count: frames,
                    rate: rate
                )
            }
        }

        func render(
            _ buffer: AVAudioPCMBuffer, content: (host: UInt64?, sample: Int64?), arrival: UInt64,
            identity: (configurationID: UInt64, generation: UInt64)
        ) {
            update { value in
                guard !value.callbacksClosed, value.configurationID == identity.configurationID,
                      value.captureGeneration == identity.generation else { value.staleCallbacks &+= 1; return }
                value.playerRender.arrived(at: arrival)
                guard let bounds = Self.nonzeroBounds(buffer) else { value.invalidBuffers &+= 1; return }
                value.playerRender.record(host: content.host, sample: content.sample, arrival: arrival,
                                          count: UInt64(buffer.frameLength), rate: buffer.format.sampleRate)
                if let range = bounds.range {
                    value.playerRender.recordNonzero(content: content, range: range, rate: buffer.format.sampleRate)
                }
                value.playerRender.nonzeroFrames &+= bounds.count
            }
        }

        func scheduled(_ buffer: AVAudioPCMBuffer) {
            update { value in
                guard let bounds = Self.nonzeroBounds(buffer) else { value.invalidBuffers &+= 1; return }
                value.scheduledFrames &+= UInt64(buffer.frameLength)
                value.scheduledNonzeroFrames &+= bounds.count
            }
        }
    }

    private extension MacSpeechNativeVoiceTiming {
        static func nonzeroBounds(_ buffer: AVAudioPCMBuffer) -> (range: ClosedRange<Int>?, count: UInt64)? {
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            guard frames > 0, frames <= 16384, channels > 0, channels <= 8,
                  buffer.format.sampleRate.isFinite, buffer.format.sampleRate >= 1,
                  buffer.format.sampleRate <= 768_000 else { return nil }
            let bytes: Int
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32, .pcmFormatInt32: bytes = 4
            case .pcmFormatInt16: bytes = 2
            default: return nil
            }
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            guard buffers.count == (buffer.format.isInterleaved ? 1 : channels) else { return nil }
            var first: Int?
            var last: Int?
            var count: UInt64 = 0
            for item in buffers {
                let itemChannels = Int(item.mNumberChannels)
                guard itemChannels == (buffer.format.isInterleaved ? channels : 1), item.mData != nil,
                      Int(item.mDataByteSize) >= frames * itemChannels * bytes else { return nil }
            }
            for frame in 0 ..< frames {
                guard let nonzero = nonzeroFrame(frame, buffers: buffers, format: buffer.format.commonFormat)
                else { return nil }
                if nonzero {
                    first = first ?? frame; last = frame; count &+= 1
                }
            }
            return (first.flatMap { start in last.map { start ... $0 } }, count)
        }

        static func nonzeroFrame(
            _ frame: Int, buffers: UnsafeMutableAudioBufferListPointer, format: AVAudioCommonFormat
        ) -> Bool? {
            var nonzero = false
            for item in buffers {
                guard let data = item.mData else { return nil }
                let channels = Int(item.mNumberChannels)
                for channel in 0 ..< channels {
                    let value = MacSpeechNativeVoiceDebugStats.sample(
                        data,
                        index: frame * channels + channel,
                        format: format
                    ).0
                    guard value.isFinite else { return nil }
                    nonzero = nonzero || value != 0
                }
            }
            return nonzero
        }
    }
#endif

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
    #if DEBUG
        private var nativeVoiceDebug: MacSpeechNativeVoiceDebugStats?
        private var nativeVoiceTimingDebug: MacSpeechNativeVoiceTiming?
        private var runtimeReadbacks: [MacSpeechRuntimeReadback.Snapshot] = []
        private var configurationDebug: [String: Any] = [:]
        private struct AGCOffDebugContext {
            let runID: UUID
            let generation: UInt64
            let configurationID: UInt64
        }

        private var agcOffDebugContext: AGCOffDebugContext?

        func voiceProcessingConfigurationDebug() -> [String: Any] {
            lock.withLock {
                var snapshot = configurationDebug
                snapshot["agc_off_registration_present"] = agcOffDebugContext != nil
                return snapshot
            }
        }
    #endif
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
                      !isRouteRebuilding
                else {
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

    private struct PreparedCapture {
        let engine: AVAudioEngine
        let format: AVAudioFormat
        let configurationID: UInt64
    }

    private func prepareCaptureLocked(generation: UInt64) throws -> PreparedCapture {
        guard !isRouteRebuilding else {
            throw MacSpeechAudioCaptureError.processingModeBusy
        }
        #if DEBUG
            if let context = agcOffDebugContext, context.generation != generation {
                agcOffDebugContext = nil
                processingSnapshot = nil
                throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
            }
        #endif
        try configureIfNeeded()
        guard let engine, captureAECConverter != nil,
              captureOutputConverter != nil
        else {
            throw MacSpeechAudioCaptureError.converterUnavailable
        }
        if isCaptureActive {
            guard captureGeneration == generation else {
                throw MacSpeechAudioCaptureError.processingModeBusy
            }
        }
        return PreparedCapture(
            engine: engine,
            format: engine.inputNode.outputFormat(forBus: 0),
            configurationID: configurationID
        )
    }

    func startCapture(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        try lifecycleLock.withLock {
            let prepared = try lock.withLock { try prepareCaptureLocked(generation: generation) }
            if lock.withLock({ isCaptureActive }) {
                return describe(prepared.format)
            }
            do {
                try validateVoiceProcessing(engine: prepared.engine, requireUnmuted: true)
                captureProcessingLock.withLock {
                    captureGenerationFence = MacSpeechCaptureGenerationFence()
                    lock.withLock {
                        captureAECConverter?.resetForGenerationTransition()
                        captureOutputConverter?.resetForGenerationTransition()
                        captureGeneration = generation
                        isCaptureActive = true
                    }
                    #if DEBUG
                        bindNativeVoiceDebugLocked(configurationID: prepared.configurationID, generation: generation)
                    #endif
                }
                #if DEBUG
                    _ = nativeVoiceTimingDebug?.observeEngineConfiguration(
                        prepared.engine, configurationID: prepared.configurationID
                    )
                #endif
                let inputNode = prepared.engine.inputNode
                let captureConfigurationID = prepared.configurationID
                inputNode.installTap(
                    onBus: 0,
                    bufferSize: MacSpeechAudioInputFormat.tapBufferSize(for: prepared.format.sampleRate),
                    format: prepared.format
                ) { [weak self] buffer, when in
                    self?.processCapture(
                        buffer,
                        at: when,
                        configurationID: captureConfigurationID,
                        generation: generation,
                        frameBuffer: frameBuffer
                    )
                }
                lock.withLock { isCaptureTapInstalled = true }
                try startEngineIfNeeded(prepared.engine)
                lock.withLock { refreshAcousticEchoPresentationLatencyLocked() }
                return describe(prepared.format)
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
        #if DEBUG
            nativeVoiceTimingDebug?.stopObservingEngineConfiguration()
        #endif
        let input = lock.withLock { () -> AVAudioInputNode? in
            isCaptureActive = false
            captureGeneration = nil
            #if DEBUG
                if agcOffDebugContext != nil {
                    agcOffDebugContext = nil
                    processingSnapshot = nil
                }
            #endif
            guard isCaptureTapInstalled else { return nil }
            isCaptureTapInstalled = false
            return engine?.inputNode
        }
        // removeTap can wait for a callback which needs the state lock.
        input?.removeTap(onBus: 0)
        #if DEBUG
            nativeVoiceTimingDebug?.event(.captureStopped)
        #endif
        captureProcessingLock.withLock {
            #if DEBUG
                nativeVoiceDebug?.seal(reason: "capture_stopped")
            #endif
            let converters = lock.withLock { (captureAECConverter, captureOutputConverter) }
            converters.0?.resetForGenerationTransition()
            converters.1?.resetForGenerationTransition()
        }
        tearDownIfIdle()
    }

    func discardPendingAudioForGenerationTransition() {
        captureProcessingLock.withLock {
            #if DEBUG
                nativeVoiceDebug?.seal(reason: "configuration_changed")
                lock.withLock {
                    if agcOffDebugContext != nil {
                        agcOffDebugContext = nil
                        processingSnapshot = nil
                    }
                }
            #endif
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
                #if DEBUG
                    nativeVoiceTimingDebug?.format(outputFormat)
                    nativeVoiceTimingDebug?.event(.playbackPrepared)
                #endif
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
                      buffer.format == outputFormat
                else {
                    throw MacSpeechAudioCaptureError.engineStartFailed
                }
                return playerNode
            }
            #if DEBUG
                nativeVoiceTimingDebug?.scheduled(buffer)
            #endif
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
                try startEngineIfNeeded(prepared.0)
                if !prepared.1.isPlaying {
                    #if DEBUG
                        nativeVoiceTimingDebug?.event(.playerPlayBefore)
                    #endif
                    prepared.1.play()
                    #if DEBUG
                        nativeVoiceTimingDebug?.event(.playerPlayReturned)
                        recordRuntimeReadback(.residentPlaybackStarted, engine: prepared.0)
                    #endif
                }
                #if DEBUG
                    nativeVoiceTimingDebug?.event(.playbackStarted)
                #endif
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
            #if DEBUG
                nativeVoiceTimingDebug?.event(.playbackCompleted)
            #endif
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

    private func startEngineIfNeeded(_ engine: AVAudioEngine) throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        #if DEBUG
            nativeVoiceTimingDebug?.event(.engineStartBefore)
        #endif
        try engine.start()
        #if DEBUG
            nativeVoiceTimingDebug?.event(.engineStartReturned)
            recordRuntimeReadback(.engineStarted, engine: engine)
        #endif
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        do {
            let inputNode = engine.inputNode
            guard !engine.isRunning else { throw MacSpeechAudioCaptureError.processingModeBusy }
            try configureVoiceProcessingIO(engine: engine)
            let localFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let outputInputFormat = engine.outputNode.inputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  localFormat.sampleRate > 0, localFormat.channelCount > 0
            else {
                throw MacSpeechAudioCaptureError.invalidInputFormat
            }
            if audioProcessingMode == .appleVoiceProcessing {
                guard inputFormat.sampleRate == outputInputFormat.sampleRate,
                      inputFormat.channelCount == outputInputFormat.channelCount
                else {
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
            #if DEBUG
                configurationDebug["error_domain"] = (error as NSError).domain
                configurationDebug["error_code"] = (error as NSError).code
            #endif
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

    private func configureVoiceProcessingIO(engine: AVAudioEngine) throws {
        guard audioProcessingMode == .appleVoiceProcessing else { return }
        #if DEBUG
            configurationDebug = ["stage": "enable_voice_processing"]
        #endif
        let inputNode = engine.inputNode
        try inputNode.setVoiceProcessingEnabled(true)
        inputNode.isVoiceProcessingBypassed = false
        inputNode.isVoiceProcessingInputMuted = false
        #if DEBUG
            inputNode.isVoiceProcessingAGCEnabled = agcOffDebugContext == nil
            configurationDebug["requested_agc_enabled"] = agcOffDebugContext == nil
        #else
            inputNode.isVoiceProcessingAGCEnabled = true
        #endif
        let format = inputNode.outputFormat(forBus: 0)
        #if DEBUG
            configurationDebug["input_rate"] = format.sampleRate
            configurationDebug["input_channels"] = format.channelCount
            configurationDebug["output_channels_before"] = engine.outputNode.inputFormat(forBus: 0).channelCount
            configurationDebug["stage"] = "negotiate_io_format"
        #endif
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
            throw MacSpeechAudioCaptureError.invalidInputFormat
        }
        // Voice-processing I/O formats must match; negotiate while the engine is stopped.
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        #if DEBUG
            configurationDebug["output_rate"] = engine.outputNode.inputFormat(forBus: 0).sampleRate
            configurationDebug["output_channels"] = engine.outputNode.inputFormat(forBus: 0).channelCount
            configurationDebug["stage"] = "validate_io_format"
        #endif
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
        if let previous = processingSnapshot, previous.configurationID == configurationID {
            if previous.inputFormat != snapshot.inputFormat || previous.outputFormat != snapshot.outputFormat {
                processingSnapshot = nil
                throw MacSpeechAudioCaptureError.invalidInputFormat
            }
        }
        if audioProcessingMode == .appleVoiceProcessing {
            let validProcessing: Bool
            #if DEBUG
                if let context = agcOffDebugContext {
                    validProcessing = context.configurationID == snapshot.configurationID
                        && (captureGeneration == nil || captureGeneration == context.generation)
                        && MacSpeechAppleVPDebugProfile.agcOff.accepts(snapshot)
                } else {
                    validProcessing = snapshot.hasValidAppleProcessing
                }
            #else
                validProcessing = snapshot.hasValidAppleProcessing
            #endif
            guard validProcessing,
                  !requireUnmuted || !snapshot.inputMuted
            else {
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
        #if DEBUG
            configurationDebug["stage"] = "validated"
        #endif
    }

    private func tearDownIfIdle(outputAlreadyStopped: Bool = false) {
        let idle = lock.withLock {
            guard !isCaptureActive, !isOutputPrepared else { return false }
            #if DEBUG
                agcOffDebugContext = nil
            #endif
            return true
        }
        guard idle else { return }
        tearDownGraph(outputAlreadyStopped: outputAlreadyStopped)
    }

    private struct DetachedGraph {
        let engine: AVAudioEngine?
        let playerNode: AVAudioPlayerNode?
        let captureTapInstalled: Bool
        let renderTapInstalled: Bool
    }

    private func tearDownGraph(outputAlreadyStopped: Bool = false) {
        let graph = lock.withLock {
            let result = DetachedGraph(
                engine: engine,
                playerNode: playerNode,
                captureTapInstalled: isCaptureTapInstalled,
                renderTapInstalled: isRenderReferenceTapInstalled
            )
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
        if graph.captureTapInstalled {
            graph.engine?.inputNode.removeTap(onBus: 0)
        }
        if graph.renderTapInstalled {
            graph.playerNode?.removeTap(onBus: 0)
        }
        captureProcessingLock.withLock {
            #if DEBUG
                nativeVoiceTimingDebug?.stopObservingEngineConfiguration()
                nativeVoiceTimingDebug?.bind(configurationID: configurationID)
                nativeVoiceTimingDebug?.event(.configurationChanged)
                nativeVoiceDebug?.seal(reason: "configuration_changed")
            #endif
        }
        renderProcessingLock.withLock {}
        graph.engine?.stop()
        if !outputAlreadyStopped, let node = graph.playerNode {
            stopPlayerNodeOutsideStateLock(node)
        }
        if let engine = graph.engine, let node = graph.playerNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            engine.reset()
        }
    }

    func routeWillRebuild() {
        lifecycleLock.withLock {
            #if DEBUG
                nativeVoiceTimingDebug?.event(.routeChanged)
            #endif
            let wasConfigured = lock.withLock { () -> Bool in
                isRouteRebuilding = true
                #if DEBUG
                    if agcOffDebugContext != nil {
                        agcOffDebugContext = nil
                        processingSnapshot = nil
                    }
                #endif
                routeRebuildWasConfigured = isConfigured
                return isConfigured
            }
            #if DEBUG
                captureProcessingLock.withLock { nativeVoiceDebug?.seal(reason: "route_changed") }
            #endif
            acousticEchoHost.routeWillRebuild()
            if wasConfigured {
                tearDownGraph()
            }
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

    private struct CaptureProcessingContext {
        let inputConverter: MacSpeechFloatMono48kConverter
        let outputConverter: MacSpeechAudioConverter
        let host: MacSpeechAcousticEchoHost
        let appleProcessing: Bool
    }

    private func processCapture(
        _ buffer: AVAudioPCMBuffer,
        at time: AVAudioTime,
        configurationID: UInt64,
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) {
        #if DEBUG
            let callbackArrivalNs = DispatchTime.now().uptimeNanoseconds
        #endif
        let hostTime = Self.hostTimeNanoseconds(time)
        let nativeSampleTime = time.isSampleTimeValid ? time.sampleTime : nil
        captureProcessingLock.withLock {
            guard captureGenerationFence.accepts(hostTimeNanoseconds: hostTime) else {
                #if DEBUG
                    if hostTime == nil {
                        nativeVoiceDebug?.recordRawTimestamp(
                            buffer, time: time, content: (hostTime, nativeSampleTime),
                            arrival: callbackArrivalNs, identity: (configurationID, generation)
                        )
                    }
                    nativeVoiceDebug?.reject("capture_fence")
                #endif
                return
            }
            guard let context = captureContext(configurationID: configurationID, generation: generation) else {
                #if DEBUG
                    nativeVoiceDebug?.reject("stale_context")
                #endif
                return
            }
            #if DEBUG
                recordNativeTimingInput(buffer, time: time, content: (hostTime, nativeSampleTime),
                                        arrival: callbackArrivalNs, identity: (configurationID, generation))
            #endif
            guard let input = convertCaptureInput(
                buffer, context: context, nativeTime: (hostTime, nativeSampleTime),
                configurationID: configurationID, generation: generation
            ) else { return }
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let spans = context.host.processCaptureSpans(input.samples, hostTimeNanoseconds: input.contentTime)
            if let packets = try? context.outputConverter.convert(
                captureSpans: spans, requiresContinuousContentTime: context.appleProcessing
            ) {
                appendCapturePackets(
                    packets, appleProcessing: context.appleProcessing,
                    configurationID: configurationID, generation: generation, frameBuffer: frameBuffer
                )
            } else {
                #if DEBUG
                    nativeVoiceDebug?.reject("output_conversion")
                #endif
            }
            context.host.recordCaptureProcessingDuration(nanoseconds: DispatchTime.now().uptimeNanoseconds &- startedAt)
            lock.withLock { updateAcousticEchoDelayLocked() }
        }
    }

    private func captureContext(configurationID: UInt64, generation: UInt64) -> CaptureProcessingContext? {
        lock.withLock {
            guard isCaptureActive, self.configurationID == configurationID,
                  captureGeneration == generation,
                  let input = captureAECConverter, let output = captureOutputConverter else { return nil }
            return CaptureProcessingContext(
                inputConverter: input, outputConverter: output, host: acousticEchoHost,
                appleProcessing: audioProcessingMode == .appleVoiceProcessing
            )
        }
    }

    private func convertCaptureInput(
        _ buffer: AVAudioPCMBuffer,
        context: CaptureProcessingContext,
        nativeTime: (host: UInt64?, sample: Int64?),
        configurationID: UInt64,
        generation: UInt64
    ) -> (samples: [Float], contentTime: UInt64)? {
        #if DEBUG
            nativeVoiceDebug?.recordNative(
                buffer, hostTimeNanoseconds: nativeTime.host, sampleTime: nativeTime.sample,
                configurationID: configurationID, generation: generation
            )
        #endif
        guard let converted = try? context.inputConverter.convert(
            buffer, hostTimeNanoseconds: nativeTime.host, sampleTime: nativeTime.sample
        ) else {
            #if DEBUG
                nativeVoiceDebug?.reject("input_conversion")
            #endif
            return nil
        }
        guard let contentTime = converted.hostTimeNanoseconds else {
            #if DEBUG
                nativeVoiceDebug?.reject("content_time")
            #endif
            return nil
        }
        guard captureGenerationFence.accepts(hostTimeNanoseconds: contentTime),
              lock.withLock({ isCaptureActive && self.configurationID == configurationID
                      && captureGeneration == generation })
        else {
            #if DEBUG
                nativeVoiceDebug?.reject("capture_fence")
            #endif
            return nil
        }
        return (converted.samples, contentTime)
    }

    private func appendCapturePackets(
        _ packets: [MacSpeechPCM16Packet],
        appleProcessing: Bool,
        configurationID: UInt64,
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) {
        for packet in packets {
            guard let observation = packet.acousticSnapshot,
                  let timestamp = packet.contentTimestampNanoseconds
                  ?? (appleProcessing ? nil : observation.captureHostTimeNanoseconds)
            else {
                #if DEBUG
                    nativeVoiceDebug?.reject("packet_time")
                #endif
                continue
            }
            let accepted = frameBuffer.append(
                pcm16Bytes: packet.bytes, activity: packet.activity, generation: generation,
                timestamp: timestamp, activityEvidenceKind: packet.activityEvidenceKind,
                residentPlaybackSequence: observation.playbackSequence,
                residentPlaybackActive: observation.isPlaybackActive,
                lastAudibleResidentRenderTimestampNanoseconds: observation.lastAudibleRenderHostTimeNanoseconds,
                sourceGateEpoch: packet.activityEvidenceKind == .sourceGatedNearEnd ? observation.sourceGateEpoch : 0,
                acousticSnapshot: observation
            )
            #if DEBUG
                nativeVoiceDebug?.recordPacket(
                    timestamp: timestamp, byteCount: packet.bytes.count, accepted: accepted,
                    configurationID: configurationID, generation: generation
                )
            #else
                _ = accepted
            #endif
        }
    }

    private func rebuildAudioFormatsLocked(
        engine: AVAudioEngine,
        localFormat: AVAudioFormat
    ) throws {
        #if DEBUG
            configurationDebug["stage"] = "create_converters"
        #endif
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
        #if DEBUG
            nativeVoiceTimingDebug?.bind(configurationID: configurationID)
            nativeVoiceTimingDebug?.event(.configurationChanged)
            let timing = nativeVoiceTimingDebug
        #endif
        playerNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(MacSpeechAcousticEchoHost.frameSampleCount),
            format: nil
        ) { [weak self] buffer, when in
            #if DEBUG
                let arrivalNs = DispatchTime.now().uptimeNanoseconds
            #endif
            let contentHostTime = Self.hostTimeNanoseconds(when)
            #if DEBUG
                if let timing {
                    timing.render(buffer, content: (contentHostTime, when.isSampleTimeValid ? when.sampleTime : nil),
                                  arrival: arrivalNs, identity: (configurationID, timing.captureGeneration))
                }
            #endif
            self?.processRenderedOutput(
                buffer,
                hostTimeNanoseconds: contentHostTime,
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

#if DEBUG
    extension SystemMacSpeechVoiceProcessingEngine {
        private func recordNativeTimingInput(
            _ buffer: AVAudioPCMBuffer, time: AVAudioTime, content: (host: UInt64?, sample: Int64?), arrival: UInt64,
            identity: (configurationID: UInt64, generation: UInt64)
        ) {
            nativeVoiceDebug?.recordRawTimestamp(buffer, time: time, content: content, arrival: arrival,
                                                 identity: identity)
            nativeVoiceDebug?.timing?.input(content: content, arrival: arrival,
                                            frames: UInt64(buffer.frameLength), rate: buffer.format.sampleRate,
                                            identity: identity)
        }

        func armNativeVoiceDebug(runID: UUID, generation: UInt64) -> Bool {
            armNativeVoiceDebug(runID: runID, generation: generation, profile: .agcOn)
        }

        func armNativeVoiceDebug(runID: UUID, generation: UInt64, profile: MacSpeechAppleVPDebugProfile) -> Bool {
            lifecycleLock.withLock {
                captureProcessingLock.withLock {
                    let idle = lock.withLock {
                        audioProcessingMode == .appleVoiceProcessing && !isCaptureActive
                            && !isOutputPlaying && !isRouteRebuilding
                            && (profile == .agcOn || (!isConfigured && !isOutputPrepared))
                    }
                    guard idle, generation > 0, nativeVoiceDebug == nil else { return false }
                    lock.withLock {
                        agcOffDebugContext = profile == .agcOff
                            ? AGCOffDebugContext(runID: runID, generation: generation,
                                                 configurationID: configurationID &+ 1) : nil
                    }
                    runtimeReadbacks.removeAll(keepingCapacity: true)
                    let timing = MacSpeechNativeVoiceTiming(runID: runID, generation: generation)
                    nativeVoiceTimingDebug = timing
                    nativeVoiceDebug = MacSpeechNativeVoiceDebugStats(
                        runID: runID, generation: generation, timing: timing, profile: profile
                    )
                    return true
                }
            }
        }

        func configureNativeAcousticWindows(
            runID: UUID, generation: UInt64, plan: MacSpeechAcousticWindowPlan
        ) -> Bool {
            captureProcessingLock.withLock {
                guard nativeVoiceDebug?.runID == runID,
                      nativeVoiceDebug?.captureGeneration == generation else { return false }
                return nativeVoiceDebug?.configureWindows(plan) == true
            }
        }

        func nativeVoiceDebugSnapshot(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
            captureProcessingLock.withLock {
                guard nativeVoiceDebug?.runID == runID else { return nil }
                return nativeVoiceDebug?.snapshot
            }
        }

        func sealNativeVoiceDebug(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
            lifecycleLock.withLock {
                captureProcessingLock.withLock {
                    guard nativeVoiceDebug?.runID == runID else { return nil }
                    nativeVoiceTimingDebug?.stopObservingEngineConfiguration()
                    nativeVoiceDebug?.seal()
                    return nativeVoiceDebug?.snapshot
                }
            }
        }

        func clearNativeVoiceDebug(runID: UUID) {
            lifecycleLock.withLock {
                captureProcessingLock.withLock {
                    guard nativeVoiceDebug?.runID == runID,
                          nativeVoiceDebug?.isSealed == true || lock.withLock({ !isCaptureActive }) else { return }
                    nativeVoiceTimingDebug?.stopObservingEngineConfiguration()
                    nativeVoiceDebug = nil
                    nativeVoiceTimingDebug = nil
                    runtimeReadbacks.removeAll(keepingCapacity: true)
                    lock.withLock {
                        if agcOffDebugContext?.runID == runID {
                            agcOffDebugContext = nil
                            processingSnapshot = nil
                        }
                    }
                }
            }
        }

        func bindNativeVoiceTimingPlayback(runID: UUID, generation: UInt64) {
            lifecycleLock.withLock {
                guard let timing = nativeVoiceTimingDebug, timing.runID == runID else { return }
                timing.bind(configurationID: configurationID, playbackGeneration: generation)
            }
        }

        func nativeVoiceTimingSnapshot(runID: UUID) -> MacSpeechTimingSnapshot? {
            let (timing, readbacks) = lifecycleLock.withLock { (nativeVoiceTimingDebug, runtimeReadbacks) }
            guard timing?.runID == runID, var result = timing?.snapshot() else { return nil }
            result.runtimeReadbacks = readbacks
            return result
        }

        private func recordRuntimeReadback(_ phase: MacSpeechRuntimeReadback.Phase, engine: AVAudioEngine) {
            guard let timing = nativeVoiceTimingDebug else { return }
            let context = lock.withLock { (captureGeneration, configurationID, isCaptureActive,
                                           isRouteRebuilding, audioProcessingMode, playerNode) }
            guard context.0 == timing.captureGeneration, let player = context.5 else { return }
            _ = MacSpeechRuntimeReadback.record(
                phase, identity: .init(
                    runID: timing.runID,
                    generation: timing.captureGeneration,
                    configurationID: context.1
                ),
                active: context.2 && !context.3 && context.4 == .appleVoiceProcessing,
                snapshots: &runtimeReadbacks
            ) {
                Self.readRuntimePayload(engine: engine, player: player)
            }
        }

        private static func readRuntimePayload(
            engine: AVAudioEngine, player: AVAudioPlayerNode
        ) -> MacSpeechRuntimeReadback.Payload {
            let started = DispatchTime.now().uptimeNanoseconds
            let input = engine.inputNode
            let output = engine.outputNode
            let inputID = input.auAudioUnit.deviceID
            let outputID = output.auAudioUnit.deviceID
            var issues: [String] = []
            let mixer = engine.mainMixerNode
            let bus = engine.outputConnectionPoints(for: player, outputBus: 0)
                .first(where: { $0.node === mixer })?.bus
            let connected = engine.outputConnectionPoints(for: mixer, outputBus: 0)
                .contains(where: { $0.node === output })
            let (formats, formatIssues) = readRuntimeFormats(engine: engine, player: player, bus: bus)
            issues.append(contentsOf: formatIssues)
            if bus == nil || !connected {
                issues.append("graph_connection_unverified")
            }
            let voice = ["engineRunning": engine.isRunning, "inputEnabled": input.isVoiceProcessingEnabled,
                         "outputEnabled": output.isVoiceProcessingEnabled,
                         "agcEnabled": input.isVoiceProcessingAGCEnabled,
                         "bypass": input.isVoiceProcessingBypassed,
                         "inputMuted": input.isVoiceProcessingInputMuted]
            var route: MacSpeechRuntimeReadback.Route?
            do {
                route = try MacSpeechRuntimeDeviceReadback.read(input: inputID, output: outputID)
            } catch { issues.append("route_read_failed:" + String(describing: error)) }
            if input.auAudioUnit.deviceID != inputID || output.auAudioUnit.deviceID != outputID {
                route = nil
                issues.append("io_nodes_changed_during_read")
            }
            let process = MacSpeechRuntimeDeviceReadback.readCurrentProcess(route: route)
            return MacSpeechRuntimeReadback.Payload(
                readStartedAtNs: started, readFinishedAtNs: DispatchTime.now().uptimeNanoseconds,
                voiceProcessing: voice,
                formats: formats, playerMixerBus: bus, mixerOutputConnected: connected,
                route: route, issues: issues, bindingStatus: route?.binding ?? "UNKNOWN_READ_FAILED",
                processBinding: process
            )
        }

        private static func readRuntimeFormats(
            engine: AVAudioEngine, player: AVAudioPlayerNode, bus: AVAudioNodeBus?
        ) -> ([String: MacSpeechPlaybackFormatWitness], [String]) {
            let input = engine.inputNode
            let output = engine.outputNode
            let mixer = engine.mainMixerNode
            var formats = [String: MacSpeechPlaybackFormatWitness]()
            var issues: [String] = []
            var sources = ["inputOutput": input.outputFormat(forBus: 0),
                           "playerOutput": player.outputFormat(forBus: 0),
                           "mixerOutput": mixer.outputFormat(forBus: 0),
                           "outputInput": output.inputFormat(forBus: 0),
                           "hardwareOutput": output.outputFormat(forBus: 0)]
            if let bus {
                sources["mixerPlayerInput"] = mixer.inputFormat(forBus: bus)
            }
            for (name, format) in sources {
                let value = MacSpeechPlaybackFormatWitness(format)
                let valid = value.sampleRate.isFinite && value.sampleRate > 0 && value.channelCount > 0
                    && value.asbd.values.allSatisfy(\.isFinite)
                    && value.channelDescriptions.allSatisfy { $0.values.allSatisfy(\.isFinite) }
                if valid {
                    formats[name] = value
                } else {
                    issues.append("invalid_format:" + name)
                }
            }
            return (formats, issues)
        }

        private func bindNativeVoiceDebugLocked(configurationID: UInt64, generation: UInt64) {
            guard nativeVoiceDebug != nil else { return }
            guard nativeVoiceDebug?.captureGeneration == generation else {
                nativeVoiceDebug?.seal(reason: "stale_context")
                return
            }
            nativeVoiceDebug?.bind(
                configurationID: configurationID,
                voiceProcessing: lock.withLock { processingSnapshot }
            )
        }
    }
#endif

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

    #if DEBUG
        func armNativeVoiceDebug(runID: UUID, generation: UInt64) -> Bool {
            audioEngine.armNativeVoiceDebug(runID: runID, generation: generation)
        }

        func armNativeVoiceDebug(runID: UUID, generation: UInt64, profile: MacSpeechAppleVPDebugProfile) -> Bool {
            audioEngine.armNativeVoiceDebug(runID: runID, generation: generation, profile: profile)
        }

        func configureNativeAcousticWindows(
            runID: UUID, generation: UInt64, plan: MacSpeechAcousticWindowPlan
        ) -> Bool {
            audioEngine.configureNativeAcousticWindows(runID: runID, generation: generation, plan: plan)
        }

        func nativeVoiceDebugSnapshot(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
            audioEngine.nativeVoiceDebugSnapshot(runID: runID)
        }

        func sealNativeVoiceDebug(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
            audioEngine.sealNativeVoiceDebug(runID: runID)
        }

        func clearNativeVoiceDebug(runID: UUID) {
            audioEngine.clearNativeVoiceDebug(runID: runID)
        }
    #endif

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
