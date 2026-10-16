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
              <= (1_000_000_000 / inputSampleRate).rounded(.up)
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
        if let previousInputHostTime {
            let expected = Double(previousInputHostTime)
                + Double(previousInputFrameCount)
                * 1_000_000_000 / inputSampleRate
            let tolerance = (1_000_000_000 / inputSampleRate).rounded(.up)
            if abs(Double(hostTimeNanoseconds) - expected) > tolerance {
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

        fileprivate mutating func record(_ sample: Double, fullScale: Bool) -> Bool {
            sampleCount &+= 1
            guard sample.isFinite else {
                nonFiniteCount &+= 1
                peakMagnitude = nil
                return false
            }
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

    nonisolated struct MacSpeechNativeVoiceDebugSnapshot: Sendable, Equatable {
        let runID: UUID
        let captureGeneration: UInt64
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

        init(runID: UUID, generation: UInt64) {
            self.runID = runID
            captureGeneration = generation
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
                  voiceProcessing.hasValidAppleProcessing,
                  !voiceProcessing.inputMuted
            else {
                reject("voice_processing")
                return
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
                runID: runID, captureGeneration: captureGeneration, configurationID: configurationID,
                isSealed: isSealed, sealReason: sealReason,
                coverageValid: configurationID != nil && nativeBufferCount > 0 && packetCount > 0 && issues.isEmpty,
                issues: issues, voiceProcessing: voiceProcessing, nativeFormat: nativeFormat,
                channels: Array(channelStats.prefix(observedChannels)),
                nativeBufferCount: nativeBufferCount, nativeFrameCount: nativeFrameCount,
                packetCount: packetCount, packetByteCount: packetByteCount,
                firstNativeHostTime: firstNativeHostTime, lastNativeHostTime: lastNativeHostTime,
                firstNativeSampleTime: firstNativeSampleTime, lastNativeSampleTime: lastNativeSampleTime,
                firstPacketTime: firstPacketTime, lastPacketTime: lastPacketTime, rejections: rejections
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

        private static func sample(
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
        private var configurationDebug: [String: Any] = [:]

        func voiceProcessingConfigurationDebug() -> [String: Any] {
            lock.withLock { configurationDebug }
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
                if !prepared.engine.isRunning {
                    prepared.engine.prepare()
                    try prepared.engine.start()
                }
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
                if !prepared.1.isPlaying {
                    prepared.1.play()
                }
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
        inputNode.isVoiceProcessingAGCEnabled = true
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
            guard snapshot.hasValidAppleProcessing,
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
        guard lock.withLock({ !isCaptureActive && !isOutputPrepared }) else { return }
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
            let wasConfigured = lock.withLock { () -> Bool in
                isRouteRebuilding = true
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
        let hostTime = Self.hostTimeNanoseconds(time)
        let nativeSampleTime = time.isSampleTimeValid ? time.sampleTime : nil
        captureProcessingLock.withLock {
            guard captureGenerationFence.accepts(hostTimeNanoseconds: hostTime) else {
                #if DEBUG
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

#if DEBUG
    extension SystemMacSpeechVoiceProcessingEngine {
        func armNativeVoiceDebug(runID: UUID, generation: UInt64) -> Bool {
            lifecycleLock.withLock {
                captureProcessingLock.withLock {
                    let idle = lock.withLock {
                        audioProcessingMode == .appleVoiceProcessing && !isCaptureActive
                            && !isOutputPlaying && !isRouteRebuilding
                    }
                    guard idle, nativeVoiceDebug == nil else { return false }
                    nativeVoiceDebug = MacSpeechNativeVoiceDebugStats(runID: runID, generation: generation)
                    return true
                }
            }
        }

        func nativeVoiceDebugSnapshot(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
            captureProcessingLock.withLock {
                guard nativeVoiceDebug?.runID == runID else { return nil }
                return nativeVoiceDebug?.snapshot
            }
        }

        func sealNativeVoiceDebug(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
            captureProcessingLock.withLock {
                guard nativeVoiceDebug?.runID == runID else { return nil }
                nativeVoiceDebug?.seal()
                return nativeVoiceDebug?.snapshot
            }
        }

        func clearNativeVoiceDebug(runID: UUID) {
            captureProcessingLock.withLock {
                guard nativeVoiceDebug?.runID == runID,
                      nativeVoiceDebug?.isSealed == true || lock.withLock({ !isCaptureActive }) else { return }
                nativeVoiceDebug = nil
            }
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
