import Foundation
import OSLog

nonisolated enum MacSpeechAudioProcessingMode: String, Sendable, Equatable {
    case webRTCAEC3
    case appleVoiceProcessing
    case halfDuplexFallback
}

nonisolated enum MacSpeechAECFallbackReason: String, Sendable, Equatable {
    case initializationFailed = "initialization_failed"
    case renderProcessingFailed = "render_processing_failed"
    case captureProcessingFailed = "capture_processing_failed"
    case delayInvalid = "delay_invalid"
    case statsUnavailable = "stats_unavailable"
    case fifoOverflow = "fifo_overflow"
    case residualEcho = "residual_echo"
    case sourceAlignmentUnavailable = "source_alignment_unavailable"
    case sourceClassificationUncertain = "source_classification_uncertain"
    case routeRebuild = "route_rebuild"
    case requested = "requested"
}

nonisolated enum MacSpeechAcousticInputClassification: String, Sendable, Equatable {
    case echoOnly = "echo_only"
    case nearEndSpeech = "near_end_speech"
    case doubleTalk = "double_talk"
    case uncertain
}

nonisolated enum MacSpeechSourceGateCloseReason: String, Sendable, Equatable {
    case nonUserHangover = "non_user_hangover"
    case sourceEvidenceReset = "source_evidence_reset"
    case residualEchoProtection = "residual_echo_protection"
    case playbackLifecycle = "playback_lifecycle"
    case routeRebuild = "route_rebuild"
    case hostFallback = "host_fallback"
}

nonisolated struct MacSpeechAECBackendStats: Sendable, Equatable {
    let enabled: Bool
    let active: Bool
    let estimatedDelayMilliseconds: Int
    let erlDecibels: Double
    let erleDecibels: Double
}

nonisolated struct MacSpeechAECCaptureResult: Sendable, Equatable {
    let processedSamples: [Float]
    let linearOutputSamples: [Float]
}

nonisolated struct MacSpeechSourceGateEpochDiagnostic: Sendable, Equatable {
    let playbackSequence: UInt64
    let epochSequence: UInt64
    let openedAtCaptureFrame: UInt64
    let closedAtCaptureFrame: UInt64?
    let totalFrameCount: UInt64
    let forwardedFrameCount: UInt64
    let suppressedFrameCount: UInt64
    let echoOnlyFrameCount: UInt64
    let nearEndSpeechFrameCount: UInt64
    let doubleTalkFrameCount: UInt64
    let uncertainFrameCount: UInt64
    let rawEchoGainBaselineAtOpen: Double
    let rawEchoGainBaselineAtClose: Double
    let residualEchoGainBaselineAtOpen: Double
    let residualEchoGainBaselineAtClose: Double
    let linearAECOutputGainBaselineAtOpen: Double
    let linearAECOutputGainBaselineAtClose: Double
    let aecBufferDelayMillisecondsAtOpen: Int
    let aecBufferDelayMillisecondsAtClose: Int
    let sourceAlignmentDelayMillisecondsAtOpen: Int?
    let sourceAlignmentDelayMillisecondsAtClose: Int?
    let estimatedDelayMillisecondsAtOpen: Int
    let estimatedDelayMillisecondsAtClose: Int
    let closeReason: MacSpeechSourceGateCloseReason?
}

nonisolated enum MacSpeechAECBackendError: Error, Sendable, Equatable {
    case createFailed
    case configureFailed
    case renderFailed
    case captureFailed
    case delayFailed
    case resetFailed
    case statsFailed
}

nonisolated protocol MacSpeechAECBackend: AnyObject, Sendable {
    func configure() throws
    func processRender(_ samples: [Float]) throws
    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult
    func setDelay(milliseconds: Int) throws
    func reset() throws
    func stats() throws -> MacSpeechAECBackendStats
}

nonisolated struct MacSpeechAcousticEchoSnapshot: Sendable, Equatable {
    let mode: MacSpeechAudioProcessingMode
    let enabled: Bool
    let active: Bool
    let sampleRate: Int
    let renderFrameCount: UInt64
    let captureFrameCount: UInt64
    let delayMilliseconds: Int
    let aecBufferDelayMilliseconds: Int
    let estimatedDelayMilliseconds: Int
    let erlDecibels: Double
    let erleDecibels: Double
    let renderFIFOSampleCount: Int
    let captureFIFOSampleCount: Int
    let renderCaptureSkewFrames: Int64
    let driftTrend: String
    let presentationDelayMilliseconds: Int
    let alignedDelayMilliseconds: Int?
    let sourceAlignmentDelayMilliseconds: Int?
    let renderTimingFrameCount: Int
    let rawCaptureRMS: Double
    let processedCaptureRMS: Double
    let renderCaptureCorrelation: Double
    let residualRenderCorrelation: Double
    let linearAECOutputRMS: Double
    let linearRenderCorrelation: Double
    let processedLinearCorrelation: Double
    let inputClassification: MacSpeechAcousticInputClassification
    let sourceGateOpen: Bool
    let sourceGatePreRollFrameCount: Int
    let echoOnlyFrameCount: UInt64
    let nearEndSpeechFrameCount: UInt64
    let doubleTalkFrameCount: UInt64
    let uncertainFrameCount: UInt64
    let sourceForwardedFrameCount: UInt64
    let sourceSuppressedFrameCount: UInt64
    let sourceTimingCandidateFrameCount: UInt64
    let sourceTimingUnavailableFrameCount: UInt64
    let sourceGateOpenCount: UInt64
    let sourceGateCloseCount: UInt64
    let maximumSourceGateOpenFrameCount: UInt64
    let maximumContinuousSourceForwardedFrameCount: UInt64
    let rawEchoGainBaseline: Double
    let residualEchoGainBaseline: Double
    let linearAECOutputGainBaseline: Double
    let residualEchoBaselineFrameCount: UInt64
    let residualEchoBaselineFrozen: Bool
    let residualEchoBaselineUpdateCount: UInt64
    let residualEchoBaselineFreezeCount: UInt64
    let adaptiveEvidenceCandidateFrameCount: UInt64
    let adaptiveDoubleTalkFrameCount: UInt64
    let maximumAdaptiveRawExcessRMS: Double
    let maximumAdaptiveResidualExcessRMS: Double
    let maximumAdaptiveLinearExcessRMS: Double
    let renderCaptureIsolationEstablished: Bool
    let renderCaptureIsolationQuietFrameCount: Int
    let renderCaptureIsolationEstablishmentCount: UInt64
    let renderCaptureIsolationRevocationCount: UInt64
    let sourceAlignmentLocked: Bool
    let sourceAlignmentAcquisitionFrameCount: Int
    let sourceAlignmentMissCount: UInt64
    let sourceAlignmentReacquisitionCount: UInt64
    let lastSourceGateCloseReason: MacSpeechSourceGateCloseReason?
    let sourceGateEpochs: [MacSpeechSourceGateEpochDiagnostic]
    let fallbackCount: UInt64
    let lastFallbackReason: MacSpeechAECFallbackReason?
    let routeResetCount: UInt64
    let fallbackReason: MacSpeechAECFallbackReason?
    let isPlaybackActive: Bool
}

nonisolated struct MacSpeechAcousticObservationSnapshot:
    Sendable,
    Equatable {
    let captureFrameIndex: UInt64
    let captureHostTimeNanoseconds: UInt64?
    let playbackSequence: UInt64
    let isPlaybackActive: Bool
    let lastAudibleRenderHostTimeNanoseconds: UInt64?
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

    func withSourceGate(open: Bool, epoch: UInt64) -> Self {
        Self(
            captureFrameIndex: captureFrameIndex,
            captureHostTimeNanoseconds: captureHostTimeNanoseconds,
            playbackSequence: playbackSequence,
            isPlaybackActive: isPlaybackActive,
            lastAudibleRenderHostTimeNanoseconds:
                lastAudibleRenderHostTimeNanoseconds,
            renderReferenceAvailable: renderReferenceAvailable,
            renderReferenceRMS: renderReferenceRMS,
            renderHostTimeNanoseconds: renderHostTimeNanoseconds,
            rawCaptureRMS: rawCaptureRMS,
            processedCaptureRMS: processedCaptureRMS,
            linearAECOutputRMS: linearAECOutputRMS,
            renderCaptureCorrelation: renderCaptureCorrelation,
            residualRenderCorrelation: residualRenderCorrelation,
            linearRenderCorrelation: linearRenderCorrelation,
            inputClassification: inputClassification,
            sourceGateOpen: open,
            sourceGateEpoch: epoch,
            aecEnabled: aecEnabled,
            aecActive: aecActive,
            renderCaptureIsolationEstablished:
                renderCaptureIsolationEstablished,
            sourceAlignmentLocked: sourceAlignmentLocked,
            sourceAlignmentDelayMilliseconds:
                sourceAlignmentDelayMilliseconds,
            estimatedDelayMilliseconds: estimatedDelayMilliseconds,
            erlDecibels: erlDecibels,
            erleDecibels: erleDecibels,
            renderCaptureSkewFrames: renderCaptureSkewFrames,
            driftTrend: driftTrend
        )
    }
}

nonisolated struct MacSpeechAcousticCaptureSpan: Sendable, Equatable {
    let samples: [Float]
    let observation: MacSpeechAcousticObservationSnapshot
}

#if DEBUG
extension MacSpeechAcousticInputClassification: Codable {}

nonisolated enum MacSpeechAcousticReplayAudioCallKind:
    String,
    Codable,
    Sendable {
    case render
    case capture
}

nonisolated enum MacSpeechAcousticReplayControlKind:
    String,
    Codable,
    Sendable {
    case playbackStarted = "playback_started"
    case playbackCompleted = "playback_completed"
    case playbackStopped = "playback_stopped"
    case discardPendingCapture = "discard_pending_capture"
    case delayUpdated = "delay_updated"
    case captureProcessingDuration = "capture_processing_duration"
}

nonisolated enum MacSpeechAcousticReplaySealReason:
    String,
    Codable,
    Sendable {
    case targetReached = "target_reached"
    case manual
    case timeout
    case routeRebuild = "route_rebuild"
    case hostFallback = "host_fallback"
}

nonisolated struct MacSpeechAcousticReplayBackendStatsSnapshot:
    Codable,
    Sendable,
    Equatable {
    let enabled: Bool
    let active: Bool
    let estimatedDelayMilliseconds: Int
    let erlDecibels: Double
    let erleDecibels: Double

    init(_ stats: MacSpeechAECBackendStats) {
        enabled = stats.enabled
        active = stats.active
        estimatedDelayMilliseconds = stats.estimatedDelayMilliseconds
        erlDecibels = stats.erlDecibels
        erleDecibels = stats.erleDecibels
    }

    var backendStats: MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(
            enabled: enabled,
            active: active,
            estimatedDelayMilliseconds: estimatedDelayMilliseconds,
            erlDecibels: erlDecibels,
            erleDecibels: erleDecibels
        )
    }
}

nonisolated struct MacSpeechAcousticReplayInitialStateSnapshot:
    Codable,
    Sendable,
    Equatable {
    let mode: String
    let renderFIFOSamples: [Float]
    let captureFIFOSamples: [Float]
    let fifoSampleCapacity: Int
    let renderRemainderHostTimeNanoseconds: UInt64?
    let captureRemainderHostTimeNanoseconds: UInt64?
    let renderFrameCount: UInt64
    let captureFrameCount: UInt64
    let delayMilliseconds: Int
    let presentationDelayMilliseconds: Int
    let captureProcessingNanoseconds: UInt64
    let backendStats: MacSpeechAcousticReplayBackendStatsSnapshot
    let timingHistoryFrameCount: Int
    let timingLockCandidateMilliseconds: Double?
    let timingLockCandidateFrameCount: Int
    let timingLockedDelayMilliseconds: Double?
    let timingLockConsecutiveMissFrameCount: Int
    let alignedDelayMilliseconds: Double?
    let rawEchoGainBaseline: Double
    let residualEchoGainBaseline: Double
    let linearAECOutputGainBaseline: Double
    let residualEchoBaselineFrameCount: UInt64
    let residualEchoBaselineFrozen: Bool
    let sourceGateOpen: Bool
    let sourceGatePreRollFrameCount: Int
    let sourceGateConfirmationFrameCount: Int
    let sourceGateNonUserHangoverFrameCount: Int
    let sourceGateCandidateNearEndFrameCount: UInt64
    let sourceGateCandidateDoubleTalkFrameCount: UInt64
    let consecutiveSourceAlignmentUnavailableFrameCount: Int
    let consecutiveSourceUncertainFrameCount: Int
    let pendingSourceGateReset: Bool
    let renderCaptureIsolationEstablished: Bool
    let renderCaptureIsolationQuietFrameCount: Int
    let hasReliableEchoCancellation: Bool
    let poorResidualEchoFrameCount: UInt64
    let playbackSequence: UInt64
    let sourceGateEpochSequence: UInt64
    let playbackActive: Bool
    let routeRebuilding: Bool
    let fallbackReason: String?

    var exactReplayEligible: Bool {
        mode == MacSpeechAudioProcessingMode.webRTCAEC3.rawValue
            && timingHistoryFrameCount == 0
            && timingLockCandidateMilliseconds == nil
            && timingLockCandidateFrameCount == 0
            && timingLockedDelayMilliseconds == nil
            && timingLockConsecutiveMissFrameCount == 0
            && !sourceGateOpen
            && sourceGatePreRollFrameCount == 0
            && sourceGateConfirmationFrameCount == 0
            && sourceGateNonUserHangoverFrameCount == 0
            && sourceGateCandidateNearEndFrameCount == 0
            && sourceGateCandidateDoubleTalkFrameCount == 0
            && !pendingSourceGateReset
            && !playbackActive
            && !routeRebuilding
            && fallbackReason == nil
    }
}

nonisolated struct MacSpeechAcousticReplayAudioCallSnapshot:
    Codable,
    Sendable,
    Equatable {
    let ordinal: UInt64
    let kind: MacSpeechAcousticReplayAudioCallKind
    let sampleOffset: Int
    let sampleCount: Int
    let hostTimeNanoseconds: UInt64?
    let firstFrameIndex: Int
    let frameCount: Int
    let backendStatsBefore: MacSpeechAcousticReplayBackendStatsSnapshot
    let backendStatsAfter: MacSpeechAcousticReplayBackendStatsSnapshot
}

nonisolated struct MacSpeechAcousticReplayControlEventSnapshot:
    Codable,
    Sendable,
    Equatable {
    let ordinal: UInt64
    let kind: MacSpeechAcousticReplayControlKind
    let outputPresentationLatencySeconds: Double?
    let capturePresentationLatencySeconds: Double?
    let captureProcessingDurationNanoseconds: UInt64?
}

nonisolated struct MacSpeechAcousticReplayRenderFrameSnapshot:
    Codable,
    Sendable,
    Equatable {
    let callOrdinal: UInt64
    let frameInCall: Int
    let renderFrameIndex: UInt64
    let hostTimeNanoseconds: UInt64?
    let aecBufferDelayMilliseconds: Int
    let backendStats: MacSpeechAcousticReplayBackendStatsSnapshot
}

nonisolated struct MacSpeechAcousticReplayEmittedSpanSnapshot:
    Codable,
    Sendable,
    Equatable {
    let captureFrameIndex: UInt64
    let sourceGateOpen: Bool
    let sourceGateEpoch: UInt64
    let silenced: Bool
}

nonisolated struct MacSpeechAcousticReplayFrameSnapshot:
    Codable,
    Sendable,
    Equatable {
    let callOrdinal: UInt64
    let frameInCall: Int
    let captureFrameIndex: UInt64
    let aecCleanSampleOffset: Int
    let aecLinearSampleOffset: Int
    let timestampNanoseconds: UInt64
    let captureHostTimeNanoseconds: UInt64?
    let timingMatchAvailable: Bool
    let matchedRenderCallOrdinal: UInt64?
    let matchedRenderHostTimeNanoseconds: UInt64?
    let timingDelayMilliseconds: Double?
    let timingCorrelation: Double?
    let renderReferenceRMS: Double?
    let aecBufferDelayMilliseconds: Int
    let sourceAlignmentLocked: Bool
    let sourceAlignmentDelayMilliseconds: Int?
    let estimatedDelayMilliseconds: Int
    let backendStats: MacSpeechAcousticReplayBackendStatsSnapshot
    let inputClassification: MacSpeechAcousticInputClassification
    let sourceGateOpen: Bool
    let sourceGateEpoch: UInt64
    let playbackSequence: UInt64
    let isPlaybackActive: Bool
    let rawCaptureRMS: Double
    let processedCaptureRMS: Double
    let linearAECOutputRMS: Double
    let linearRenderCorrelation: Double
    let processedLinearCorrelation: Double
    let residualRenderCorrelation: Double
    let timingLockCandidateMilliseconds: Double?
    let timingLockCandidateFrameCount: Int
    let timingLockedDelayMilliseconds: Double?
    let timingLockConsecutiveMissFrameCount: Int
    let rawEchoGainBaseline: Double
    let residualEchoGainBaseline: Double
    let linearAECOutputGainBaseline: Double
    let residualEchoBaselineFrameCount: UInt64
    let residualEchoBaselineFrozen: Bool
    let sourceGatePreRollFrameCount: Int
    let sourceGateConfirmationFrameCount: Int
    let sourceGateNonUserHangoverFrameCount: Int
    let pendingSourceGateReset: Bool
    let renderCaptureIsolationEstablished: Bool
    let renderCaptureIsolationQuietFrameCount: Int
    let emittedSpans: [MacSpeechAcousticReplayEmittedSpanSnapshot]
}

nonisolated struct MacSpeechAcousticReplayCaptureSnapshot:
    Sendable,
    Equatable {
    let attemptID: UUID
    let armedAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let targetPostPlaybackCaptureFrameCount: Int
    let postPlaybackCaptureFrameCount: Int
    let initialState: MacSpeechAcousticReplayInitialStateSnapshot
    let finalState: MacSpeechAcousticReplayInitialStateSnapshot
    let rawMicrophoneSamples: [Float]
    let chronologicalRenderSamples: [Float]
    let aecCleanSamples: [Float]
    let aecLinearSamples: [Float]
    let audioCalls: [MacSpeechAcousticReplayAudioCallSnapshot]
    let controlEvents: [MacSpeechAcousticReplayControlEventSnapshot]
    let renderFrames: [MacSpeechAcousticReplayRenderFrameSnapshot]
    let captureFrames: [MacSpeechAcousticReplayFrameSnapshot]
    let isSealed: Bool
    let sealReason: MacSpeechAcousticReplaySealReason?

    var durationMilliseconds: Int {
        captureFrames.count
            * MacSpeechAcousticEchoHost.frameDurationMilliseconds
    }

    var isExactReplayReady: Bool {
        guard isSealed,
              sealReason == .targetReached,
              startedAt != nil,
              endedAt != nil,
              initialState.exactReplayEligible,
              postPlaybackCaptureFrameCount
                >= targetPostPlaybackCaptureFrameCount,
              !rawMicrophoneSamples.isEmpty,
              !chronologicalRenderSamples.isEmpty,
              !captureFrames.isEmpty,
              !renderFrames.isEmpty,
              aecCleanSamples.count
                == captureFrames.count
                    * MacSpeechAcousticEchoHost.frameSampleCount,
              aecLinearSamples.count
                == captureFrames.count
                    * MacSpeechAcousticEchoHost.linearOutputFrameSampleCount,
              controlEvents.contains(where: {
                  $0.kind == .playbackStarted
              }),
              hasCompleteChronology,
              hasCompleteAudioCalls,
              hasCompleteCaptureTimeline,
              hasCompleteRenderTimeline else { return false }
        return true
    }

    private var hasCompleteChronology: Bool {
        let ordinals = (
            audioCalls.map(\.ordinal) + controlEvents.map(\.ordinal)
        ).sorted()
        guard ordinals.count == Set(ordinals).count else { return false }
        return ordinals.enumerated().allSatisfy { index, ordinal in
            ordinal == UInt64(index + 1)
        }
    }

    private var hasCompleteAudioCalls: Bool {
        var rawOffset = 0
        var renderOffset = 0
        var captureFrameOffset = 0
        var renderFrameOffset = 0
        for call in audioCalls.sorted(by: { $0.ordinal < $1.ordinal }) {
            guard call.sampleCount > 0,
                  call.frameCount >= 0,
                  call.hostTimeNanoseconds != nil else { return false }
            switch call.kind {
            case .capture:
                guard call.sampleOffset == rawOffset,
                      call.firstFrameIndex == captureFrameOffset,
                      call.firstFrameIndex + call.frameCount
                        <= captureFrames.count else {
                    return false
                }
                let frames = captureFrames[
                    call.firstFrameIndex
                        ..< call.firstFrameIndex + call.frameCount
                ]
                guard frames.enumerated().allSatisfy({ index, frame in
                    frame.callOrdinal == call.ordinal
                        && frame.frameInCall == index
                }) else { return false }
                rawOffset += call.sampleCount
                captureFrameOffset += call.frameCount
            case .render:
                guard call.sampleOffset == renderOffset,
                      call.firstFrameIndex == renderFrameOffset,
                      call.firstFrameIndex + call.frameCount
                        <= renderFrames.count else {
                    return false
                }
                let frames = renderFrames[
                    call.firstFrameIndex
                        ..< call.firstFrameIndex + call.frameCount
                ]
                guard frames.enumerated().allSatisfy({ index, frame in
                    frame.callOrdinal == call.ordinal
                        && frame.frameInCall == index
                }) else { return false }
                renderOffset += call.sampleCount
                renderFrameOffset += call.frameCount
            }
        }
        return rawOffset == rawMicrophoneSamples.count
            && renderOffset == chronologicalRenderSamples.count
            && captureFrameOffset == captureFrames.count
            && renderFrameOffset == renderFrames.count
    }

    private var hasCompleteCaptureTimeline: Bool {
        let frameSamples = MacSpeechAcousticEchoHost.frameSampleCount
        let linearSamples =
            MacSpeechAcousticEchoHost.linearOutputFrameSampleCount
        var renderCallOrdinalByHostTime: [UInt64: UInt64] = [:]
        for frame in renderFrames {
            guard let hostTime = frame.hostTimeNanoseconds,
                  renderCallOrdinalByHostTime.updateValue(
                      frame.callOrdinal,
                      forKey: hostTime
                  ) == nil else { return false }
        }
        for (index, frame) in captureFrames.enumerated() {
            guard frame.frameInCall >= 0,
                  frame.aecCleanSampleOffset == index * frameSamples,
                  frame.aecLinearSampleOffset == index * linearSamples,
                  let hostTime = frame.captureHostTimeNanoseconds,
                  frame.timestampNanoseconds == hostTime,
                  index == 0
                    || hostTime
                        > captureFrames[index - 1]
                            .captureHostTimeNanoseconds!
            else { return false }
            if frame.timingMatchAvailable {
                guard let matchedHostTime =
                        frame.matchedRenderHostTimeNanoseconds,
                      let matchedCall = frame.matchedRenderCallOrdinal,
                      renderCallOrdinalByHostTime[matchedHostTime]
                        == matchedCall else { return false }
            } else if frame.matchedRenderHostTimeNanoseconds != nil
                        || frame.matchedRenderCallOrdinal != nil {
                return false
            }
        }
        return true
    }

    private var hasCompleteRenderTimeline: Bool {
        for (index, frame) in renderFrames.enumerated() {
            guard frame.frameInCall >= 0,
                  let hostTime = frame.hostTimeNanoseconds,
                  index == 0
                    || hostTime
                        > renderFrames[index - 1]
                            .hostTimeNanoseconds!
            else { return false }
        }
        return true
    }
}

nonisolated struct MacSpeechAcousticReplayAudioFile:
    Codable,
    Sendable,
    Equatable {
    let fileName: String
    let sha256: String
    let stage: String
    let encoding: String
    let sampleRate: Int
    let channelCount: Int
    let frameSampleCount: Int
    let byteCount: Int
}

nonisolated struct MacSpeechAcousticReplayManifest:
    Codable,
    Sendable,
    Equatable {
    let schemaVersion: Int
    let producerBinaryName: String
    let producerBinarySHA256: String
    let attemptID: String
    let armedAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let targetPostPlaybackCaptureFrameCount: Int
    let postPlaybackCaptureFrameCount: Int
    let capturedFrameCount: Int
    let renderedFrameCount: Int
    let durationMilliseconds: Int
    let missingTimingMatchFrameCount: Int
    let isSealed: Bool
    let sealReason: MacSpeechAcousticReplaySealReason?
    let exactReplayReady: Bool
    let renderReferenceSemantics: String
    let rawMicrophone: MacSpeechAcousticReplayAudioFile
    let chronologicalRender: MacSpeechAcousticReplayAudioFile
    let aecClean: MacSpeechAcousticReplayAudioFile
    let aecLinear: MacSpeechAcousticReplayAudioFile
    let initialState: MacSpeechAcousticReplayInitialStateSnapshot
    let finalState: MacSpeechAcousticReplayInitialStateSnapshot
    let audioCalls: [MacSpeechAcousticReplayAudioCallSnapshot]
    let controlEvents: [MacSpeechAcousticReplayControlEventSnapshot]
    let renderFrames: [MacSpeechAcousticReplayRenderFrameSnapshot]
    let captureFrames: [MacSpeechAcousticReplayFrameSnapshot]

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }
}

nonisolated enum MacSpeechAcousticReplayCodec {
    static func float32LittleEndianData(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<UInt32>.size)
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }
}
#endif

nonisolated final class MacSpeechAcousticEchoHost: @unchecked Sendable {
    static let sampleRate = 48_000
    static let frameSampleCount = 480
    static let linearOutputSampleRate = 16_000
    static let linearOutputFrameSampleCount = 160
    static let frameDurationMilliseconds = 10
    static let maximumDelayMilliseconds = 500
    static let standardFIFOFrameCapacity = 12
    private static let timingHistoryFrameCapacity =
        maximumDelayMilliseconds / frameDurationMilliseconds
    private static let minimumTimingCorrelation = 0.35
    private static let minimumTimingRMS = 0.005
    static let minimumNearEndRMS = 0.012
    private static let maximumNearEndCorrelation = 0.25
    private static let maximumDoubleTalkResidualCorrelation = 0.25
    private static let maximumAdaptiveDoubleTalkResidualCorrelation = 0.65
    private static let maximumLinearNearEndCorrelation = 0.35
    private static let minimumProcessedLinearNearEndCorrelation = 0.65
    private static let minimumResidentOnlyRawCorrelation = 0.7
    private static let minimumResidentOnlyResidualCorrelation = 0.55
    private static let minimumResidualEchoBaselineFrameCount: UInt64 = 5
    private static let residualEchoBaselineSmoothingFactor = 0.1
    private static let maximumBaselineGainIncreaseRatio = 1.25
    private static let timingLockAcquisitionFrameCount = 3
    private static let timingLockCandidateToleranceMilliseconds = 20.0
    private static let timingAssociationProgressToleranceMilliseconds = 5.0
    private static let timingLockMissFrameCount = 5
    private static let requiredSourceGateConfirmationFrames = 3
    private static let maximumSourceGateNonUserHangoverFrames = 20
    private static let sourceGatePreRollFrameCapacity = 15
    private static let sourceGateEpochDiagnosticCapacity = 16
    private static let sourceGateResetFrameCount = 20
    private static let renderCaptureIsolationWarmupFrameCount =
        timingHistoryFrameCapacity
    private static let reliableERLEDecibels = 3.0
    private static let failedERLEDecibels = 1.0
    private static let residualEchoGateResetFrameCount: UInt64 = 5

    private let queue = DispatchQueue(
        label: "com.eterna.aftelle.speech-aec-processing"
    )
    private let backend: (any MacSpeechAECBackend)?
    private let fifoSampleCapacity: Int
    private let logger = Logger(
        subsystem: "com.eterna.aftelle",
        category: "speech-aec"
    )
    private let requestedMode: MacSpeechAudioProcessingMode
    private var mode: MacSpeechAudioProcessingMode
    private var renderFIFO: [Float] = []
    private var captureFIFO: [Float] = []
    private var renderRemainderHostTimeNanoseconds: UInt64?
    private var captureRemainderHostTimeNanoseconds: UInt64?
    private var renderTimingHistory: [TimedRenderFrame] = []
    private var renderFrameCount: UInt64 = 0
    private var captureFrameCount: UInt64 = 0
    private var lastLoggedCaptureFrameCount: UInt64 = 0
    private var delayMilliseconds = 0
    private var presentationDelayMilliseconds = 0
    private var alignedDelayMilliseconds: Double?
    private var captureProcessingMilliseconds = 0.0
    private var latestCaptureHostTimeNanoseconds: UInt64?
    private var latestRenderHostTimeNanoseconds: UInt64?
    private var latestRenderReferenceRMS = 0.0
    private var matchedRenderHostTimeNanoseconds: UInt64?
    private var matchedRenderReferenceRMS = 0.0
    private var rawCaptureRMS = 0.0
    private var processedCaptureRMS = 0.0
    private var renderCaptureCorrelation = 0.0
    private var residualRenderCorrelation = 0.0
    private var linearAECOutputRMS = 0.0
    private var linearRenderCorrelation = 0.0
    private var processedLinearCorrelation = 0.0
    private var inputClassification: MacSpeechAcousticInputClassification =
        .uncertain
    private var sourceGateOpen = false
    private var sourceGatePreRoll: [MacSpeechAcousticCaptureSpan] = []
    private var sourceGateCandidateNearEndFrameCount: UInt64 = 0
    private var sourceGateCandidateDoubleTalkFrameCount: UInt64 = 0
    private var sourceGateConfirmationFrameCount = 0
    private var sourceGateNonUserHangoverFrameCount = 0
    private var consecutiveSourceAlignmentUnavailableFrameCount = 0
    private var consecutiveSourceUncertainFrameCount = 0
    private var pendingSourceGateReset = false
    private var echoOnlyFrameCount: UInt64 = 0
    private var nearEndSpeechFrameCount: UInt64 = 0
    private var doubleTalkFrameCount: UInt64 = 0
    private var uncertainFrameCount: UInt64 = 0
    private var sourceForwardedFrameCount: UInt64 = 0
    private var sourceSuppressedFrameCount: UInt64 = 0
    private var sourceTimingCandidateFrameCount: UInt64 = 0
    private var sourceTimingUnavailableFrameCount: UInt64 = 0
    private var sourceGateOpenCount: UInt64 = 0
    private var sourceGateCloseCount: UInt64 = 0
    private var currentSourceGateOpenFrameCount: UInt64 = 0
    private var maximumSourceGateOpenFrameCount: UInt64 = 0
    private var currentContinuousSourceForwardedFrameCount: UInt64 = 0
    private var maximumContinuousSourceForwardedFrameCount: UInt64 = 0
    private var rawEchoGainBaseline = 0.0
    private var residualEchoGainBaseline = 0.0
    private var linearAECOutputGainBaseline = 0.0
    private var residualEchoBaselineFrameCount: UInt64 = 0
    private var residualEchoBaselineFrozen = false
    private var residualEchoBaselineUpdateCount: UInt64 = 0
    private var residualEchoBaselineFreezeCount: UInt64 = 0
    private var adaptiveEvidenceCandidateFrameCount: UInt64 = 0
    private var adaptiveDoubleTalkFrameCount: UInt64 = 0
    private var adaptiveNearEndContinuationCandidate = false
    private var maximumAdaptiveRawExcessRMS = 0.0
    private var maximumAdaptiveResidualExcessRMS = 0.0
    private var maximumAdaptiveLinearExcessRMS = 0.0
    private var renderCaptureIsolationEstablished = false
    private var renderCaptureIsolationQuietFrameCount = 0
    private var renderCaptureIsolationEstablishmentCount: UInt64 = 0
    private var renderCaptureIsolationRevocationCount: UInt64 = 0
    private var timingLockCandidateMilliseconds: Double?
    private var timingLockCandidateFrameCount = 0
    private var timingLockedDelayMilliseconds: Double?
    private var timingLockConsecutiveMissFrameCount = 0
    private var timingAssociationCaptureHostTimeNanoseconds: UInt64?
    private var timingAssociationRenderHostTimeNanoseconds: UInt64?
    private var timingAssociationFollowsExpectedTimeline = false
    private var sourceAlignmentMissCount: UInt64 = 0
    private var sourceAlignmentReacquisitionCount: UInt64 = 0
    private var lastSourceGateCloseReason: MacSpeechSourceGateCloseReason?
    private var playbackSequence: UInt64 = 0
    private var sourceGateEpochSequence: UInt64 = 0
    private var sourceGateEpochs: [MacSpeechSourceGateEpochDiagnostic] = []
    private var activeSourceGateEpoch: SourceGateEpochAccumulator?
    private var fallbackCount: UInt64 = 0
    private var lastFallbackReason: MacSpeechAECFallbackReason?
    private var lastDriftSkew: Int64 = 0
    private var driftTrend = "stable"
    private var routeResetCount: UInt64 = 0
    private var fallbackReason: MacSpeechAECFallbackReason?
    private var isPlaybackActive = false
    private var lastAudibleRenderHostTimeNanoseconds: UInt64?
    private var isRouteRebuilding = false
    private var hasReliableEchoCancellation = false
    private var poorResidualEchoFrameCount: UInt64 = 0
    private var backendStats = MacSpeechAECBackendStats(
        enabled: false,
        active: false,
        estimatedDelayMilliseconds: 0,
        erlDecibels: 0,
        erleDecibels: 0
    )
    #if DEBUG
    private struct AcousticReplayAudioCallContext {
        let ordinal: UInt64
        let kind: MacSpeechAcousticReplayAudioCallKind
        let sampleOffset: Int
        let sampleCount: Int
        let hostTimeNanoseconds: UInt64?
        let firstFrameIndex: Int
        let backendStatsBefore: MacSpeechAcousticReplayBackendStatsSnapshot
    }

    private final class AcousticReplayCapture {
        let attemptID: UUID
        let armedAt = Date()
        let targetPostPlaybackCaptureFrameCount: Int
        let initialState: MacSpeechAcousticReplayInitialStateSnapshot
        var finalState: MacSpeechAcousticReplayInitialStateSnapshot?
        var startedAt: Date?
        var endedAt: Date?
        var nextOrdinal: UInt64 = 1
        var sawPlaybackStart = false
        var postPlaybackCaptureFrameCount = 0
        var rawMicrophoneSamples: [Float] = []
        var chronologicalRenderSamples: [Float] = []
        var aecCleanSamples: [Float] = []
        var aecLinearSamples: [Float] = []
        var audioCalls: [MacSpeechAcousticReplayAudioCallSnapshot] = []
        var controlEvents: [MacSpeechAcousticReplayControlEventSnapshot] = []
        var renderFrames: [MacSpeechAcousticReplayRenderFrameSnapshot] = []
        var captureFrames: [MacSpeechAcousticReplayFrameSnapshot] = []
        var renderCallOrdinalByHostTime: [UInt64: UInt64] = [:]
        var isSealed = false
        var sealReason: MacSpeechAcousticReplaySealReason?

        init(
            attemptID: UUID,
            targetPostPlaybackCaptureFrameCount: Int,
            initialState: MacSpeechAcousticReplayInitialStateSnapshot
        ) {
            self.attemptID = attemptID
            self.targetPostPlaybackCaptureFrameCount =
                targetPostPlaybackCaptureFrameCount
            self.initialState = initialState
            let sampleCapacity = targetPostPlaybackCaptureFrameCount
                * MacSpeechAcousticEchoHost.frameSampleCount
            rawMicrophoneSamples.reserveCapacity(sampleCapacity)
            chronologicalRenderSamples.reserveCapacity(sampleCapacity)
            aecCleanSamples.reserveCapacity(sampleCapacity)
            aecLinearSamples.reserveCapacity(
                targetPostPlaybackCaptureFrameCount
                    * MacSpeechAcousticEchoHost.linearOutputFrameSampleCount
            )
            audioCalls.reserveCapacity(targetPostPlaybackCaptureFrameCount)
            controlEvents.reserveCapacity(32)
            renderFrames.reserveCapacity(targetPostPlaybackCaptureFrameCount)
            captureFrames.reserveCapacity(targetPostPlaybackCaptureFrameCount)
        }

        func takeOrdinal() -> UInt64 {
            defer { nextOrdinal &+= 1 }
            return nextOrdinal
        }
    }

    private static let acousticReplayCaptureFrameCapacity = 1_000
    private var acousticReplayCapture: AcousticReplayCapture?
    #endif

    init(
        mode: MacSpeechAudioProcessingMode,
        backend: (any MacSpeechAECBackend)? = nil,
        fifoFrameCapacity: Int = standardFIFOFrameCapacity
    ) {
        precondition(fifoFrameCapacity > 0)
        requestedMode = mode
        self.mode = mode
        self.backend = backend
        fifoSampleCapacity = fifoFrameCapacity * Self.frameSampleCount
        renderFIFO.reserveCapacity(fifoSampleCapacity)
        captureFIFO.reserveCapacity(fifoSampleCapacity)
        renderTimingHistory.reserveCapacity(Self.timingHistoryFrameCapacity)
        sourceGatePreRoll.reserveCapacity(
            Self.sourceGatePreRollFrameCapacity
        )
        sourceGateEpochs.reserveCapacity(
            Self.sourceGateEpochDiagnosticCapacity
        )
    }

    @discardableResult
    func configure() -> MacSpeechAudioProcessingMode {
        queue.sync {
            clearFIFOs()
            renderFrameCount = 0
            captureFrameCount = 0
            lastLoggedCaptureFrameCount = 0
            resetTimingState()
            resetDiagnosticCounters()
            isRouteRebuilding = false
            lastAudibleRenderHostTimeNanoseconds = nil
            lastDriftSkew = 0
            driftTrend = "stable"
            fallbackReason = nil
            hasReliableEchoCancellation = false
            poorResidualEchoFrameCount = 0
            switch requestedMode {
            case .webRTCAEC3:
                guard let backend else {
                    enterFallback(.initializationFailed)
                    return mode
                }
                do {
                    try backend.configure()
                    mode = .webRTCAEC3
                    backendStats = try backend.stats()
                    logConfiguration()
                } catch {
                    enterFallback(.initializationFailed)
                }
            case .appleVoiceProcessing:
                mode = .appleVoiceProcessing
                backendStats = disabledStats()
                logConfiguration()
            case .halfDuplexFallback:
                enterFallback(.requested)
            }
            return mode
        }
    }

    func processRender(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64? = nil
    ) {
        guard !samples.isEmpty else { return }
        queue.sync {
            guard mode == .webRTCAEC3, let backend else { return }
            #if DEBUG
            let replayCall = beginAcousticReplayAudioCall(
                kind: .render,
                samples: samples,
                hostTimeNanoseconds: hostTimeNanoseconds
            )
            #endif
            do {
                try processFrames(
                    samples,
                    hostTimeNanoseconds: hostTimeNanoseconds,
                    remainder: &renderFIFO,
                    remainderHostTimeNanoseconds:
                        &renderRemainderHostTimeNanoseconds
                ) { frame, frameHostTimeNanoseconds in
                    try backend.processRender(frame)
                    renderFrameCount &+= 1
                    #if DEBUG
                    recordAcousticReplayRenderFrame(
                        call: replayCall,
                        hostTimeNanoseconds: frameHostTimeNanoseconds
                    )
                    #endif
                    if isPlaybackActive,
                       let frameHostTimeNanoseconds {
                        appendRenderTimingFrame(
                            frame,
                            hostTimeNanoseconds: frameHostTimeNanoseconds
                        )
                    }
                }
            } catch FrameProcessingError.fifoOverflow {
                enterFallback(.fifoOverflow)
                return
            } catch {
                enterFallback(.renderProcessingFailed)
                return
            }
            refreshBackendStats()
            updateDrift()
            #if DEBUG
            finishAcousticReplayAudioCall(replayCall)
            #endif
        }
    }

    func renderConversionFailed() {
        queue.sync { enterFallback(.renderProcessingFailed) }
    }

    func processCapture(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64? = nil
    ) -> [Float] {
        processCaptureSpans(
            samples,
            hostTimeNanoseconds: hostTimeNanoseconds
        ).flatMap { $0.samples }
    }

    func processCaptureSpans(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64? = nil
    ) -> [MacSpeechAcousticCaptureSpan] {
        guard !samples.isEmpty else { return [] }
        return queue.sync {
            if mode == .halfDuplexFallback {
                captureFIFO.removeAll(keepingCapacity: true)
                recordUnavailableCaptureObservation(
                    samples,
                    hostTimeNanoseconds: hostTimeNanoseconds
                )
                return isPlaybackActive || isRouteRebuilding
                    ? [] : [captureSpan(samples: samples)]
            }
            guard mode == .webRTCAEC3, let backend else {
                recordUnavailableCaptureObservation(
                    samples,
                    hostTimeNanoseconds: hostTimeNanoseconds
                )
                return [captureSpan(samples: samples)]
            }
            #if DEBUG
            let replayCall = beginAcousticReplayAudioCall(
                kind: .capture,
                samples: samples,
                hostTimeNanoseconds: hostTimeNanoseconds
            )
            #endif
            var output: [MacSpeechAcousticCaptureSpan] = []
            let captureFrameCountBeforeProcessing = captureFrameCount
            do {
                try processFrames(
                    samples,
                    hostTimeNanoseconds: hostTimeNanoseconds,
                    remainder: &captureFIFO,
                    remainderHostTimeNanoseconds:
                        &captureRemainderHostTimeNanoseconds
                ) { frame, frameHostTimeNanoseconds in
                    let timingMatch = timingMatch(
                        for: frame,
                        captureHostTimeNanoseconds: frameHostTimeNanoseconds
                    )
                    let captureResult = try backend.processCapture(frame)
                    guard captureResult.processedSamples.count
                            == Self.frameSampleCount,
                          captureResult.linearOutputSamples.count
                            == Self.linearOutputFrameSampleCount else {
                        throw MacSpeechAECBackendError.captureFailed
                    }
                    let processedFrame = captureResult.processedSamples
                    updateSignalDiagnostics(
                        rawCapture: frame,
                        processedCapture: processedFrame,
                        linearAECOutput: captureResult.linearOutputSamples,
                        captureHostTimeNanoseconds:
                            frameHostTimeNanoseconds,
                        timingMatch: timingMatch
                    )
                    let reportedTimingMatch: TimingMatch?
                    if let timingMatch,
                       timingMatch.associationOrigin == .historicalDiscovery,
                       !timingMatchSupportsEchoAssociation(timingMatch) {
                        reportedTimingMatch = nil
                    } else {
                        reportedTimingMatch = timingMatch
                    }
                    updateTimingLock(with: timingMatch)
                    updateRenderCaptureIsolationEvidence(
                        timingMatch: timingMatch
                    )
                    let gatedSpans = gatedCaptureSpans(
                        processedFrame,
                        classificationTimingMatch: timingMatch,
                        reportedTimingMatch: reportedTimingMatch,
                        captureFrameIndex: captureFrameCount &+ 1
                    )
                    output.append(contentsOf: gatedSpans)
                    #if DEBUG
                    recordAcousticReplayCaptureFrame(
                        call: replayCall,
                        rawCapture: frame,
                        processedCapture: processedFrame,
                        linearAECOutput: captureResult.linearOutputSamples,
                        timingMatch: reportedTimingMatch,
                        observation: makeAcousticObservationSnapshot(
                            captureFrameIndex: captureFrameCount &+ 1
                        ),
                        emittedSpans: gatedSpans
                    )
                    #endif
                    captureFrameCount &+= 1
                }
            } catch FrameProcessingError.fifoOverflow {
                enterFallback(.fifoOverflow)
                return isPlaybackActive || isRouteRebuilding
                    ? [] : [captureSpan(samples: samples)]
            } catch {
                enterFallback(.captureProcessingFailed)
                return isPlaybackActive || isRouteRebuilding
                    ? [] : [captureSpan(samples: samples)]
            }
            refreshBackendStats()
            applyResidualEchoGateProtection(
                processedFrameCount:
                    captureFrameCount - captureFrameCountBeforeProcessing
            )
            updateDrift()
            #if DEBUG
            finishAcousticReplayAudioCall(replayCall)
            #endif
            return mode == .halfDuplexFallback
                    && (isPlaybackActive || isRouteRebuilding)
                ? [] : output
        }
    }

    private func captureSpan(
        samples: [Float],
        captureFrameIndex: UInt64? = nil
    ) -> MacSpeechAcousticCaptureSpan {
        MacSpeechAcousticCaptureSpan(
            samples: samples,
            observation: makeAcousticObservationSnapshot(
                captureFrameIndex: captureFrameIndex
            )
        )
    }

    private func recordUnavailableCaptureObservation(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64?
    ) {
        let frameCount = max(
            1,
            (samples.count + Self.frameSampleCount - 1)
                / Self.frameSampleCount
        )
        latestCaptureHostTimeNanoseconds = hostTimeNanoseconds.map {
            $0 &+ UInt64(frameCount - 1) * 10_000_000
        }
        rawCaptureRMS = signalRMS(samples)
        processedCaptureRMS = isPlaybackActive ? 0 : rawCaptureRMS
        linearAECOutputRMS = 0
        renderCaptureCorrelation = 0
        residualRenderCorrelation = 0
        linearRenderCorrelation = 0
        inputClassification = .uncertain
        captureFrameCount &+= UInt64(frameCount)
        updateDrift()
    }

    func updateDelay(
        outputPresentationLatencySeconds: Double,
        capturePresentationLatencySeconds: Double
    ) {
        queue.sync {
            guard outputPresentationLatencySeconds.isFinite,
                  capturePresentationLatencySeconds.isFinite else {
                enterFallback(.delayInvalid)
                return
            }
            #if DEBUG
            recordAcousticReplayControl(
                kind: .delayUpdated,
                outputPresentationLatencySeconds:
                    outputPresentationLatencySeconds,
                capturePresentationLatencySeconds:
                    capturePresentationLatencySeconds
            )
            #endif
            let totalSeconds = max(0, outputPresentationLatencySeconds)
                + max(0, capturePresentationLatencySeconds)
            presentationDelayMilliseconds = Int(
                (totalSeconds * 1_000).rounded()
            )
            let measuredMilliseconds = Int((
                Double(presentationDelayMilliseconds)
                    + max(0, captureProcessingMilliseconds)
            ).rounded())
            guard measuredMilliseconds <= Self.maximumDelayMilliseconds else {
                enterFallback(.delayInvalid)
                return
            }
            applyDelay(measuredMilliseconds)
        }
    }

    func recordCaptureProcessingDuration(nanoseconds: UInt64) {
        queue.sync {
            #if DEBUG
            recordAcousticReplayControl(
                kind: .captureProcessingDuration,
                captureProcessingDurationNanoseconds: nanoseconds
            )
            #endif
            captureProcessingMilliseconds = Double(nanoseconds) / 1_000_000
        }
    }

    func playbackStarted() {
        queue.sync {
            #if DEBUG
            recordAcousticReplayControl(kind: .playbackStarted)
            acousticReplayCapture?.sawPlaybackStart = true
            #endif
            playbackSequence &+= 1
            isPlaybackActive = true
            lastAudibleRenderHostTimeNanoseconds = nil
            clearTimingHistory()
            alignedDelayMilliseconds = nil
            resetSignalDiagnostics()
            resetResidualEchoBaseline()
            resetSourceGate(closeReason: .playbackLifecycle)
            poorResidualEchoFrameCount = 0
        }
    }

    func playbackCompleted() {
        queue.sync {
            #if DEBUG
            recordAcousticReplayControl(kind: .playbackCompleted)
            #endif
            isPlaybackActive = false
            captureFIFO.removeAll(keepingCapacity: true)
            captureRemainderHostTimeNanoseconds = nil
            clearTimingHistory()
            resetSourceGate(closeReason: .playbackLifecycle)
            poorResidualEchoFrameCount = 0
            guard mode == .halfDuplexFallback,
                  fallbackReason != .routeRebuild,
                  requestedMode == .webRTCAEC3,
                  let backend else { return }
            do {
                try backend.reset()
                try backend.setDelay(milliseconds: delayMilliseconds)
                mode = .webRTCAEC3
                fallbackReason = nil
                hasReliableEchoCancellation = false
                backendStats = try backend.stats()
                logConfiguration()
            } catch {
                enterFallback(.initializationFailed)
            }
        }
    }

    func playbackStopped() {
        queue.sync {
            #if DEBUG
            recordAcousticReplayControl(kind: .playbackStopped)
            #endif
            isPlaybackActive = false
            captureFIFO.removeAll(keepingCapacity: true)
            captureRemainderHostTimeNanoseconds = nil
            clearTimingHistory()
            resetSourceGate(closeReason: .playbackLifecycle)
            poorResidualEchoFrameCount = 0
        }
    }

    func discardPendingCaptureForGenerationTransition() {
        queue.sync {
            #if DEBUG
            recordAcousticReplayControl(kind: .discardPendingCapture)
            #endif
            captureFIFO.removeAll(keepingCapacity: true)
            captureRemainderHostTimeNanoseconds = nil
        }
    }

    func routeWillRebuild() {
        queue.sync {
            #if DEBUG
            sealAcousticReplayCaptureLocked(reason: .routeRebuild)
            #endif
            routeResetCount &+= 1
            lastAudibleRenderHostTimeNanoseconds = nil
            isRouteRebuilding = true
            hasReliableEchoCancellation = false
            poorResidualEchoFrameCount = 0
            clearFIFOs()
            resetTimingState(closeReason: .routeRebuild)
            if requestedMode == .webRTCAEC3 {
                enterFallback(.routeRebuild)
            }
            logger.notice(
                "AEC route reset count=\(self.routeResetCount, privacy: .public) mode=\(self.mode.rawValue, privacy: .public)"
            )
        }
    }

    @discardableResult
    func routeDidRebuild() -> MacSpeechAudioProcessingMode {
        queue.sync {
            clearFIFOs()
            isRouteRebuilding = false
            guard requestedMode == .webRTCAEC3, let backend else {
                mode = requestedMode
                return mode
            }
            do {
                try backend.reset()
                try backend.configure()
                try backend.setDelay(milliseconds: delayMilliseconds)
                mode = .webRTCAEC3
                fallbackReason = nil
                hasReliableEchoCancellation = false
                backendStats = try backend.stats()
                logConfiguration()
            } catch {
                enterFallback(.initializationFailed)
            }
            return mode
        }
    }

    func snapshot() -> MacSpeechAcousticEchoSnapshot {
        queue.sync { makeSnapshot() }
    }

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot {
        queue.sync { makeAcousticObservationSnapshot() }
    }

    #if DEBUG
    func armAcousticReplayCapture(
        attemptID: UUID,
        targetCaptureFrameCount: Int = acousticReplayCaptureFrameCapacity
    ) -> Bool {
        queue.sync {
            guard mode == .webRTCAEC3,
                  backend != nil,
                  acousticReplayCapture == nil,
                  !isPlaybackActive,
                  targetCaptureFrameCount > 0 else { return false }
            let initialState = makeAcousticReplayInitialState()
            guard initialState.exactReplayEligible else { return false }
            acousticReplayCapture = AcousticReplayCapture(
                attemptID: attemptID,
                targetPostPlaybackCaptureFrameCount: targetCaptureFrameCount,
                initialState: initialState
            )
            return true
        }
    }

    func sealAcousticReplayCapture(
        reason: MacSpeechAcousticReplaySealReason = .manual,
        matchingAttemptID attemptID: UUID? = nil
    ) {
        queue.sync {
            guard attemptID == nil
                    || acousticReplayCapture?.attemptID == attemptID else {
                return
            }
            sealAcousticReplayCaptureLocked(reason: reason)
        }
    }

    func acousticReplayCaptureSnapshot()
        -> MacSpeechAcousticReplayCaptureSnapshot? {
        queue.sync {
            guard let capture = acousticReplayCapture else { return nil }
            return MacSpeechAcousticReplayCaptureSnapshot(
                attemptID: capture.attemptID,
                armedAt: capture.armedAt,
                startedAt: capture.startedAt,
                endedAt: capture.endedAt,
                targetPostPlaybackCaptureFrameCount:
                    capture.targetPostPlaybackCaptureFrameCount,
                postPlaybackCaptureFrameCount:
                    capture.postPlaybackCaptureFrameCount,
                initialState: capture.initialState,
                finalState: capture.finalState
                    ?? makeAcousticReplayInitialState(),
                rawMicrophoneSamples: capture.rawMicrophoneSamples,
                chronologicalRenderSamples:
                    capture.chronologicalRenderSamples,
                aecCleanSamples: capture.aecCleanSamples,
                aecLinearSamples: capture.aecLinearSamples,
                audioCalls: capture.audioCalls,
                controlEvents: capture.controlEvents,
                renderFrames: capture.renderFrames,
                captureFrames: capture.captureFrames,
                isSealed: capture.isSealed,
                sealReason: capture.sealReason
            )
        }
    }

    func restoreAcousticReplayInitialState(
        _ state: MacSpeechAcousticReplayInitialStateSnapshot
    ) -> Bool {
        queue.sync {
            guard state.exactReplayEligible,
                  mode.rawValue == state.mode,
                  fifoSampleCapacity == state.fifoSampleCapacity,
                  !isPlaybackActive else { return false }
            renderFIFO = state.renderFIFOSamples
            captureFIFO = state.captureFIFOSamples
            renderRemainderHostTimeNanoseconds =
                state.renderRemainderHostTimeNanoseconds
            captureRemainderHostTimeNanoseconds =
                state.captureRemainderHostTimeNanoseconds
            renderFrameCount = state.renderFrameCount
            captureFrameCount = state.captureFrameCount
            delayMilliseconds = state.delayMilliseconds
            presentationDelayMilliseconds =
                state.presentationDelayMilliseconds
            captureProcessingMilliseconds =
                Double(state.captureProcessingNanoseconds) / 1_000_000
            backendStats = state.backendStats.backendStats
            timingLockCandidateMilliseconds =
                state.timingLockCandidateMilliseconds
            timingLockCandidateFrameCount =
                state.timingLockCandidateFrameCount
            timingLockedDelayMilliseconds =
                state.timingLockedDelayMilliseconds
            timingLockConsecutiveMissFrameCount =
                state.timingLockConsecutiveMissFrameCount
            alignedDelayMilliseconds = state.alignedDelayMilliseconds
            rawEchoGainBaseline = state.rawEchoGainBaseline
            residualEchoGainBaseline = state.residualEchoGainBaseline
            linearAECOutputGainBaseline = state.linearAECOutputGainBaseline
            residualEchoBaselineFrameCount =
                state.residualEchoBaselineFrameCount
            residualEchoBaselineFrozen = state.residualEchoBaselineFrozen
            sourceGateConfirmationFrameCount =
                state.sourceGateConfirmationFrameCount
            sourceGateNonUserHangoverFrameCount =
                state.sourceGateNonUserHangoverFrameCount
            sourceGateCandidateNearEndFrameCount =
                state.sourceGateCandidateNearEndFrameCount
            sourceGateCandidateDoubleTalkFrameCount =
                state.sourceGateCandidateDoubleTalkFrameCount
            consecutiveSourceAlignmentUnavailableFrameCount =
                state.consecutiveSourceAlignmentUnavailableFrameCount
            consecutiveSourceUncertainFrameCount =
                state.consecutiveSourceUncertainFrameCount
            pendingSourceGateReset = state.pendingSourceGateReset
            renderCaptureIsolationEstablished =
                state.renderCaptureIsolationEstablished
            renderCaptureIsolationQuietFrameCount =
                state.renderCaptureIsolationQuietFrameCount
            hasReliableEchoCancellation =
                state.hasReliableEchoCancellation
            poorResidualEchoFrameCount = state.poorResidualEchoFrameCount
            playbackSequence = state.playbackSequence
            sourceGateEpochSequence = state.sourceGateEpochSequence
            lastDriftSkew = Int64(renderFrameCount) - Int64(captureFrameCount)
            driftTrend = "stable"
            return true
        }
    }

    func clearAcousticReplayCapture(matchingAttemptID attemptID: UUID? = nil) {
        queue.sync {
            guard attemptID == nil
                    || acousticReplayCapture?.attemptID == attemptID else {
                return
            }
            acousticReplayCapture = nil
        }
    }
    #endif

    func resetDiagnostics() {
        queue.sync {
            let gateWasOpen = sourceGateOpen
            resetDiagnosticCounters()
            if gateWasOpen {
                beginSourceGateEpoch()
            }
        }
    }

    private enum FrameProcessingError: Error {
        case fifoOverflow
    }

    private struct TimedRenderFrame {
        let hostTimeNanoseconds: UInt64
        let samples: [Float]
        let rms: Double
    }

    private struct TimingMatch {
        enum AssociationOrigin {
            case expected
            case trackedCandidate
            case locked
            case historicalDiscovery
        }

        let renderSamples: [Float]
        let captureHostTimeNanoseconds: UInt64
        let renderHostTimeNanoseconds: UInt64
        let renderRMS: Double
        let delayMilliseconds: Double
        let correlation: Double
        let associationOrigin: AssociationOrigin
    }

    private struct SourceGateEpochAccumulator {
        let playbackSequence: UInt64
        let epochSequence: UInt64
        let openedAtCaptureFrame: UInt64
        let forwardedFrameCountAtOpen: UInt64
        let suppressedFrameCountAtOpen: UInt64
        let echoOnlyFrameCountAtOpen: UInt64
        let nearEndSpeechFrameCountAtOpen: UInt64
        let doubleTalkFrameCountAtOpen: UInt64
        let uncertainFrameCountAtOpen: UInt64
        let rawEchoGainBaselineAtOpen: Double
        let residualEchoGainBaselineAtOpen: Double
        let linearAECOutputGainBaselineAtOpen: Double
        let aecBufferDelayMillisecondsAtOpen: Int
        let sourceAlignmentDelayMillisecondsAtOpen: Int?
        let estimatedDelayMillisecondsAtOpen: Int
    }

    private func processFrames(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64?,
        remainder: inout [Float],
        remainderHostTimeNanoseconds: inout UInt64?,
        process: ([Float], UInt64?) throws -> Void
    ) throws {
        guard remainder.count < Self.frameSampleCount,
              remainder.count <= fifoSampleCapacity else {
            throw FrameProcessingError.fifoOverflow
        }

        var offset = 0
        if !remainder.isEmpty {
            let needed = Self.frameSampleCount - remainder.count
            let consumed = min(needed, samples.count)
            remainder.append(contentsOf: samples.prefix(consumed))
            offset += consumed
            if remainder.count == Self.frameSampleCount {
                try process(remainder, remainderHostTimeNanoseconds)
                remainder.removeAll(keepingCapacity: true)
                remainderHostTimeNanoseconds = nil
            }
        }

        while samples.count - offset >= Self.frameSampleCount {
            let end = offset + Self.frameSampleCount
            try process(
                Array(samples[offset ..< end]),
                advancedHostTime(
                    hostTimeNanoseconds,
                    sampleOffset: offset
                )
            )
            offset = end
        }

        if offset < samples.count {
            if remainder.isEmpty {
                remainderHostTimeNanoseconds = advancedHostTime(
                    hostTimeNanoseconds,
                    sampleOffset: offset
                )
            }
            remainder.append(contentsOf: samples[offset...])
        }
        guard remainder.count < Self.frameSampleCount,
              remainder.count <= fifoSampleCapacity else {
            remainder.removeAll(keepingCapacity: true)
            remainderHostTimeNanoseconds = nil
            throw FrameProcessingError.fifoOverflow
        }
    }

    private func advancedHostTime(
        _ hostTimeNanoseconds: UInt64?,
        sampleOffset: Int
    ) -> UInt64? {
        guard let hostTimeNanoseconds else { return nil }
        let offsetNanoseconds = UInt64((
            Double(sampleOffset) * 1_000_000_000
                / Double(Self.sampleRate)
        ).rounded())
        return hostTimeNanoseconds &+ offsetNanoseconds
    }

    private func appendRenderTimingFrame(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64
    ) {
        if renderTimingHistory.count == Self.timingHistoryFrameCapacity {
            renderTimingHistory.removeFirst()
        }
        let frame = TimedRenderFrame(
            hostTimeNanoseconds: hostTimeNanoseconds,
            samples: samples,
            rms: signalRMS(samples)
        )
        renderTimingHistory.append(frame)
        latestRenderHostTimeNanoseconds = frame.hostTimeNanoseconds
        latestRenderReferenceRMS = frame.rms
        if frame.rms >= Self.minimumTimingRMS {
            lastAudibleRenderHostTimeNanoseconds = max(
                lastAudibleRenderHostTimeNanoseconds ?? 0,
                frame.hostTimeNanoseconds
            )
        }
    }

    private func timingMatch(
        for captureSamples: [Float],
        captureHostTimeNanoseconds: UInt64?
    ) -> TimingMatch? {
        guard isPlaybackActive,
              let captureHostTimeNanoseconds,
              signalRMS(captureSamples) >= Self.minimumTimingRMS else {
            return nil
        }
        let hasAssociationAuthority =
            timingLockedDelayMilliseconds != nil
            || timingLockCandidateFrameCount > 0
        let hasChronologicalAssociation =
            timingAssociationCaptureHostTimeNanoseconds != nil
            && timingAssociationRenderHostTimeNanoseconds != nil
        let shouldDiscoverHistoricalAssociation =
            timingLockedDelayMilliseconds == nil
            && timingLockCandidateFrameCount == 0
            && timingLockConsecutiveMissFrameCount
                >= Self.timingLockMissFrameCount
            && !renderCaptureIsolationEstablished
        let followsExistingAssociation: Bool
        let targetRenderHostTimeNanoseconds: UInt64
        if (hasAssociationAuthority
                || timingAssociationFollowsExpectedTimeline),
           hasChronologicalAssociation,
           let previousCapture =
                timingAssociationCaptureHostTimeNanoseconds,
           let previousRender =
                timingAssociationRenderHostTimeNanoseconds,
           captureHostTimeNanoseconds > previousCapture {
            followsExistingAssociation = true
            targetRenderHostTimeNanoseconds = previousRender &+
                (captureHostTimeNanoseconds - previousCapture)
        } else {
            followsExistingAssociation = false
            let preferredDelayMilliseconds =
                timingLockedDelayMilliseconds
                ?? timingLockCandidateMilliseconds
                ?? Double(delayMilliseconds)
            let preferredDelayNanoseconds = UInt64(max(
                0,
                (preferredDelayMilliseconds * 1_000_000).rounded()
            ))
            targetRenderHostTimeNanoseconds =
                captureHostTimeNanoseconds >= preferredDelayNanoseconds
                ? captureHostTimeNanoseconds - preferredDelayNanoseconds
                : 0
        }
        var bestMatch: TimingMatch?
        var bestDistanceNanoseconds: UInt64?
        var fallbackMatch: TimingMatch?
        for renderFrame in renderTimingHistory {
            guard captureHostTimeNanoseconds >= renderFrame.hostTimeNanoseconds
            else { continue }
            let delayMilliseconds = Double(
                captureHostTimeNanoseconds - renderFrame.hostTimeNanoseconds
            ) / 1_000_000
            guard delayMilliseconds <= Double(Self.maximumDelayMilliseconds),
                  renderFrame.rms >= Self.minimumTimingRMS else {
                continue
            }
            if followsExistingAssociation {
                guard timingAssociationIsContinuous(
                    captureHostTimeNanoseconds: captureHostTimeNanoseconds,
                    renderHostTimeNanoseconds: renderFrame.hostTimeNanoseconds
                ) else { continue }
            }
            let correlation = normalizedCorrelation(
                captureSamples,
                renderFrame.samples
            )
            if !followsExistingAssociation,
               fallbackMatch == nil
                    || correlation >= (fallbackMatch?.correlation ?? 0) {
                fallbackMatch = TimingMatch(
                    renderSamples: renderFrame.samples,
                    captureHostTimeNanoseconds:
                        captureHostTimeNanoseconds,
                    renderHostTimeNanoseconds:
                        renderFrame.hostTimeNanoseconds,
                    renderRMS: renderFrame.rms,
                    delayMilliseconds: delayMilliseconds,
                    correlation: correlation,
                    associationOrigin: .historicalDiscovery
                )
            }
            let distanceNanoseconds = renderFrame.hostTimeNanoseconds
                    >= targetRenderHostTimeNanoseconds
                ? renderFrame.hostTimeNanoseconds
                    - targetRenderHostTimeNanoseconds
                : targetRenderHostTimeNanoseconds
                    - renderFrame.hostTimeNanoseconds
            let maximumDistanceMilliseconds =
                followsExistingAssociation
                ? Self.timingAssociationProgressToleranceMilliseconds
                : Self.timingLockCandidateToleranceMilliseconds
            guard Double(distanceNanoseconds) / 1_000_000
                    <= maximumDistanceMilliseconds else {
                continue
            }
            if bestDistanceNanoseconds == nil
                || distanceNanoseconds < (bestDistanceNanoseconds ?? .max)
                || (distanceNanoseconds == bestDistanceNanoseconds
                    && correlation >= (bestMatch?.correlation ?? 0)) {
                bestDistanceNanoseconds = distanceNanoseconds
                bestMatch = TimingMatch(
                    renderSamples: renderFrame.samples,
                    captureHostTimeNanoseconds:
                        captureHostTimeNanoseconds,
                    renderHostTimeNanoseconds:
                        renderFrame.hostTimeNanoseconds,
                    renderRMS: renderFrame.rms,
                    delayMilliseconds: delayMilliseconds,
                    correlation: correlation,
                    associationOrigin:
                        timingLockedDelayMilliseconds != nil
                        ? .locked
                        : followsExistingAssociation
                            ? .trackedCandidate
                            : .expected
                )
            }
        }
        if (bestMatch == nil || shouldDiscoverHistoricalAssociation),
           !followsExistingAssociation,
           !renderCaptureIsolationEstablished {
            bestMatch = fallbackMatch
        }
        return bestMatch
    }

    private func timingAssociationIsContinuous(
        captureHostTimeNanoseconds: UInt64,
        renderHostTimeNanoseconds: UInt64
    ) -> Bool {
        guard let previousCapture =
                timingAssociationCaptureHostTimeNanoseconds,
              let previousRender =
                timingAssociationRenderHostTimeNanoseconds else {
            return true
        }
        guard captureHostTimeNanoseconds > previousCapture,
              renderHostTimeNanoseconds > previousRender else {
            return false
        }
        let captureAdvanceMilliseconds = Double(
            captureHostTimeNanoseconds - previousCapture
        ) / 1_000_000
        let renderAdvanceMilliseconds = Double(
            renderHostTimeNanoseconds - previousRender
        ) / 1_000_000
        return abs(captureAdvanceMilliseconds - renderAdvanceMilliseconds)
            <= Self.timingAssociationProgressToleranceMilliseconds
    }

    private func updateTimingLock(with timingMatch: TimingMatch?) {
        guard let timingMatch,
              timingMatchSupportsEchoAssociation(timingMatch) else {
            if timingLockedDelayMilliseconds != nil {
                sourceAlignmentMissCount &+= 1
                timingLockConsecutiveMissFrameCount += 1
                if timingLockConsecutiveMissFrameCount
                    >= Self.timingLockMissFrameCount {
                    timingLockedDelayMilliseconds = nil
                    timingLockCandidateMilliseconds = nil
                    timingLockCandidateFrameCount = 0
                    timingLockConsecutiveMissFrameCount = 0
                    clearTimingAssociation()
                    alignedDelayMilliseconds = nil
                    sourceAlignmentReacquisitionCount &+= 1
                }
            } else {
                timingLockCandidateMilliseconds = nil
                timingLockCandidateFrameCount = 0
                let rejectedChronologicalAssociation =
                    timingMatch?.associationOrigin == .expected
                    || timingMatch?.associationOrigin == .trackedCandidate
                    || timingAssociationFollowsExpectedTimeline
                if rejectedChronologicalAssociation {
                    timingLockConsecutiveMissFrameCount = min(
                        timingLockConsecutiveMissFrameCount + 1,
                        Self.timingLockMissFrameCount
                    )
                    if timingLockConsecutiveMissFrameCount
                        >= Self.timingLockMissFrameCount {
                        clearTimingAssociation()
                    }
                } else {
                    timingLockConsecutiveMissFrameCount = 0
                }
            }
            return
        }

        timingLockConsecutiveMissFrameCount = 0
        timingAssociationCaptureHostTimeNanoseconds =
            timingMatch.captureHostTimeNanoseconds
        timingAssociationRenderHostTimeNanoseconds =
            timingMatch.renderHostTimeNanoseconds
        timingAssociationFollowsExpectedTimeline =
            timingMatch.associationOrigin != .historicalDiscovery
        if let lockedDelay = timingLockedDelayMilliseconds {
            let updatedDelay = lockedDelay * 0.9
                + timingMatch.delayMilliseconds * 0.1
            timingLockedDelayMilliseconds = updatedDelay
            updateAlignedDelay(updatedDelay)
            return
        }

        if let candidate = timingLockCandidateMilliseconds,
           abs(timingMatch.delayMilliseconds - candidate)
            <= Self.timingLockCandidateToleranceMilliseconds {
            timingLockCandidateFrameCount += 1
            let count = Double(timingLockCandidateFrameCount)
            timingLockCandidateMilliseconds = candidate
                + (timingMatch.delayMilliseconds - candidate) / count
        } else {
            timingLockCandidateMilliseconds = timingMatch.delayMilliseconds
            timingLockCandidateFrameCount = 1
        }

        guard timingLockCandidateFrameCount
                >= Self.timingLockAcquisitionFrameCount,
              let candidate = timingLockCandidateMilliseconds else {
            return
        }
        timingLockedDelayMilliseconds = candidate
        updateAlignedDelay(candidate)
    }

    private func timingMatchSupportsEchoAssociation(
        _ timingMatch: TimingMatch
    ) -> Bool {
        guard timingMatch.correlation
                >= Self.minimumTimingCorrelation else {
            return false
        }
        let bothOutputsQuiet =
            processedCaptureRMS < Self.minimumNearEndRMS
            && linearAECOutputRMS < Self.minimumNearEndRMS
        let bothOutputsTrackRender =
            residualRenderCorrelation
                >= Self.minimumResidentOnlyResidualCorrelation
            && linearRenderCorrelation
                >= Self.minimumResidentOnlyResidualCorrelation
        return bothOutputsQuiet || bothOutputsTrackRender
    }

    private func gatedCaptureSpans(
        _ processedFrame: [Float],
        classificationTimingMatch: TimingMatch?,
        reportedTimingMatch: TimingMatch?,
        captureFrameIndex: UInt64
    ) -> [MacSpeechAcousticCaptureSpan] {
        guard isPlaybackActive else {
            inputClassification = .nearEndSpeech
            resetSourceGate(
                keepingClassification: true,
                closeReason: .playbackLifecycle
            )
            return [captureSpan(
                samples: processedFrame,
                captureFrameIndex: captureFrameIndex
            )]
        }

        inputClassification = classifyCapture(
            processedFrame,
            timingMatch: classificationTimingMatch
        )
        if classificationTimingMatch != nil,
           reportedTimingMatch == nil {
            clearTimingMatchIdentity()
        }
        recordSourceClassification(timingMatch: reportedTimingMatch)
        if sourceGateOpen {
            recordSourceGateOpenFrame()
        }
        if pendingSourceGateReset {
            return suppressCaptureFrameAndCloseGate(
                reason: .sourceEvidenceReset,
                captureFrameIndex: captureFrameIndex
            )
        }
        if sourceGateOpen {
            return captureWhileGateIsOpen(
                processedFrame,
                captureFrameIndex: captureFrameIndex
            )
        }

        switch inputClassification {
        case .echoOnly:
            return suppressClosedGateFrame(
                captureFrameIndex: captureFrameIndex
            )
        case .uncertain:
            return suppressClosedGateFrame(
                captureFrameIndex: captureFrameIndex
            )
        case .nearEndSpeech, .doubleTalk:
            appendSourceGatePreRoll(captureSpan(
                samples: processedFrame,
                captureFrameIndex: captureFrameIndex
            ))
            if inputClassification == .nearEndSpeech {
                sourceGateCandidateNearEndFrameCount &+= 1
            } else {
                sourceGateCandidateDoubleTalkFrameCount &+= 1
            }
            sourceGateConfirmationFrameCount += 1
            guard sourceGateConfirmationFrameCount
                    >= Self.requiredSourceGateConfirmationFrames else {
                return []
            }
            sourceGateOpen = true
            sourceGateOpenCount &+= 1
            sourceGateConfirmationFrameCount = 0
            sourceGateNonUserHangoverFrameCount = 0
            currentSourceGateOpenFrameCount = UInt64(
                sourceGatePreRoll.count
            )
            maximumSourceGateOpenFrameCount = max(
                maximumSourceGateOpenFrameCount,
                currentSourceGateOpenFrameCount
            )
            beginSourceGateEpoch()
            return drainSourceGatePreRoll()
        }
    }

    private func classifyCapture(
        _ processedFrame: [Float],
        timingMatch: TimingMatch?
    ) -> MacSpeechAcousticInputClassification {
        adaptiveNearEndContinuationCandidate = false
        let cleanRMS = signalRMS(processedFrame)
        guard let timingMatch else {
            if hasUnalignedIsolatedNearEndEvidence(cleanRMS: cleanRMS) {
                freezeResidualEchoBaseline()
                return .nearEndSpeech
            }
            return .uncertain
        }
        let residualCorrelation = normalizedCorrelation(
            processedFrame,
            timingMatch.renderSamples
        )
        let residentOnlyEvidence = hasHighConfidenceResidentOnlyEvidence(
            cleanRMS: cleanRMS,
            residualCorrelation: residualCorrelation,
            timingMatch: timingMatch
        )
        if residentOnlyEvidence {
            revokeRenderCaptureIsolationEvidence()
        }
        let classification: MacSpeechAcousticInputClassification
        if residentOnlyEvidence {
            classification = .echoOnly
        } else if hasImmediateDoubleTalkEvidence(
            cleanRMS: cleanRMS,
            residualCorrelation: residualCorrelation,
            timingMatch: timingMatch
        ) {
            classification = .doubleTalk
            freezeResidualEchoBaseline()
        } else if hasAdaptiveDoubleTalkEvidence(
            cleanRMS: cleanRMS,
            residualCorrelation: residualCorrelation,
            timingMatch: timingMatch
        ) {
            classification = .doubleTalk
            adaptiveDoubleTalkFrameCount &+= 1
            freezeResidualEchoBaseline()
        } else if hasIsolatedNearEndEvidence(
            cleanRMS: cleanRMS,
            residualCorrelation: residualCorrelation,
            timingMatch: timingMatch
        ) {
            classification = .nearEndSpeech
            freezeResidualEchoBaseline()
        } else if hasUnalignedIsolatedNearEndEvidence(
            cleanRMS: cleanRMS
        ) {
            classification = .nearEndSpeech
            freezeResidualEchoBaseline()
        } else if (timingMatch.associationOrigin == .historicalDiscovery
                    || timingLockedDelayMilliseconds != nil),
                  timingMatch.correlation
                    <= Self.maximumNearEndCorrelation,
                  residualCorrelation <= Self.maximumNearEndCorrelation,
                  linearRenderCorrelation
                    <= Self.maximumLinearNearEndCorrelation,
                  processedLinearCorrelation
                    >= Self.minimumProcessedLinearNearEndCorrelation,
                  max(cleanRMS, linearAECOutputRMS)
                    >= Self.minimumNearEndRMS {
            classification = .nearEndSpeech
            freezeResidualEchoBaseline()
        } else if timingLockedDelayMilliseconds != nil,
                  timingMatchSupportsEchoAssociation(timingMatch) {
            classification = .echoOnly
        } else {
            classification = .uncertain
        }
        updateResidualEchoBaseline(
            hasHighConfidenceResidentOnlyEvidence: residentOnlyEvidence,
            cleanRMS: cleanRMS,
            timingMatch: timingMatch
        )
        return classification
    }

    private func hasUnalignedIsolatedNearEndEvidence(
        cleanRMS: Double
    ) -> Bool {
        timingLockedDelayMilliseconds == nil
            && timingLockCandidateFrameCount == 0
            && renderCaptureIsolationEstablished
            && rawCaptureRMS >= Self.minimumNearEndRMS
            && cleanRMS >= Self.minimumNearEndRMS
            && linearAECOutputRMS >= Self.minimumNearEndRMS
    }

    private func updateRenderCaptureIsolationEvidence(
        timingMatch: TimingMatch?
    ) {
        guard !renderCaptureIsolationEstablished else { return }
        guard isPlaybackActive,
              mode == .webRTCAEC3,
              backendStats.active,
              timingLockedDelayMilliseconds == nil,
              !renderTimingHistory.isEmpty,
              latestRenderReferenceRMS >= Self.minimumTimingRMS,
              rawCaptureRMS < Self.minimumNearEndRMS,
              processedCaptureRMS < Self.minimumNearEndRMS,
              linearAECOutputRMS < Self.minimumNearEndRMS else {
            renderCaptureIsolationQuietFrameCount = 0
            return
        }
        renderCaptureIsolationQuietFrameCount += 1
        guard renderCaptureIsolationQuietFrameCount
                >= Self.renderCaptureIsolationWarmupFrameCount,
              renderTimingHistory.count
                == Self.timingHistoryFrameCapacity else {
            return
        }
        renderCaptureIsolationEstablished = true
        renderCaptureIsolationEstablishmentCount &+= 1
    }

    private func hasIsolatedNearEndEvidence(
        cleanRMS: Double,
        residualCorrelation: Double,
        timingMatch: TimingMatch
    ) -> Bool {
        renderCaptureIsolationEstablished
            && timingMatch.renderRMS >= Self.minimumTimingRMS
            && rawCaptureRMS >= Self.minimumNearEndRMS
            && cleanRMS >= Self.minimumNearEndRMS
            && timingMatch.correlation < Self.minimumTimingCorrelation
            && residualCorrelation < Self.minimumTimingCorrelation
            && linearRenderCorrelation
                < Self.minimumTimingCorrelation
            && processedLinearCorrelation
                >= Self.minimumProcessedLinearNearEndCorrelation
    }

    private func revokeRenderCaptureIsolationEvidence() {
        guard renderCaptureIsolationEstablished else { return }
        renderCaptureIsolationEstablished = false
        renderCaptureIsolationQuietFrameCount = 0
        renderCaptureIsolationRevocationCount &+= 1
    }

    private func hasHighConfidenceResidentOnlyEvidence(
        cleanRMS: Double,
        residualCorrelation: Double,
        timingMatch: TimingMatch
    ) -> Bool {
        guard timingMatch.correlation
                >= Self.minimumResidentOnlyRawCorrelation else {
            return false
        }
        let bothOutputsQuiet = cleanRMS < Self.minimumNearEndRMS
            && linearAECOutputRMS < Self.minimumNearEndRMS
        let bothOutputsTrackRender = residualCorrelation
                >= Self.minimumResidentOnlyResidualCorrelation
            && linearRenderCorrelation
                >= Self.minimumResidentOnlyResidualCorrelation
        let associationCanClassifyEcho =
            timingMatch.associationOrigin == .expected
            || timingMatch.associationOrigin == .locked
            || timingLockedDelayMilliseconds != nil
        return (associationCanClassifyEcho && bothOutputsTrackRender)
            || (timingLockedDelayMilliseconds != nil && bothOutputsQuiet)
    }

    private func hasImmediateDoubleTalkEvidence(
        cleanRMS: Double,
        residualCorrelation: Double,
        timingMatch: TimingMatch
    ) -> Bool {
        timingMatch.correlation >= Self.minimumTimingCorrelation
            && cleanRMS >= Self.minimumNearEndRMS
            && linearAECOutputRMS >= Self.minimumNearEndRMS
            && residualCorrelation
                <= Self.maximumDoubleTalkResidualCorrelation
            && linearRenderCorrelation
                <= Self.maximumLinearNearEndCorrelation
            && processedLinearCorrelation
                >= Self.minimumProcessedLinearNearEndCorrelation
    }

    private func hasAdaptiveDoubleTalkEvidence(
        cleanRMS: Double,
        residualCorrelation: Double,
        timingMatch: TimingMatch
    ) -> Bool {
        guard residualEchoBaselineFrameCount
                >= Self.minimumResidualEchoBaselineFrameCount,
              residualCorrelation
                <= Self.maximumAdaptiveDoubleTalkResidualCorrelation,
              linearRenderCorrelation
                <= Self.maximumAdaptiveDoubleTalkResidualCorrelation else {
            return false
        }
        let renderRMS = signalRMS(timingMatch.renderSamples)
        guard renderRMS >= Self.minimumTimingRMS else { return false }
        let expectedRawEchoRMS = rawEchoGainBaseline * renderRMS
        let expectedEchoRMS = residualEchoGainBaseline * renderRMS
        let expectedLinearRMS = linearAECOutputGainBaseline * renderRMS
        let rawExcessPower = rawCaptureRMS * rawCaptureRMS
            - expectedRawEchoRMS * expectedRawEchoRMS
        let excessPower = cleanRMS * cleanRMS
            - expectedEchoRMS * expectedEchoRMS
        let linearExcessPower = linearAECOutputRMS * linearAECOutputRMS
            - expectedLinearRMS * expectedLinearRMS
        let rawExcessRMS = sqrt(max(0, rawExcessPower))
        let residualExcessRMS = sqrt(max(0, excessPower))
        let linearExcessRMS = sqrt(max(0, linearExcessPower))
        maximumAdaptiveRawExcessRMS = max(
            maximumAdaptiveRawExcessRMS,
            rawExcessRMS
        )
        maximumAdaptiveResidualExcessRMS = max(
            maximumAdaptiveResidualExcessRMS,
            residualExcessRMS
        )
        maximumAdaptiveLinearExcessRMS = max(
            maximumAdaptiveLinearExcessRMS,
            linearExcessRMS
        )
        let minimumNearEndPower = Self.minimumNearEndRMS
            * Self.minimumNearEndRMS
        let hasCandidate = rawExcessPower >= minimumNearEndPower
            && max(excessPower, linearExcessPower) >= minimumNearEndPower
        adaptiveNearEndContinuationCandidate = hasCandidate
        adaptiveEvidenceCandidateFrameCount &+= 1
        if hasCandidate {
            freezeResidualEchoBaseline()
        }
        return rawExcessPower >= minimumNearEndPower
            && excessPower >= minimumNearEndPower
            && linearExcessPower >= minimumNearEndPower
            && processedLinearCorrelation
                >= Self.minimumProcessedLinearNearEndCorrelation
    }

    private func updateResidualEchoBaseline(
        hasHighConfidenceResidentOnlyEvidence: Bool,
        cleanRMS: Double,
        timingMatch: TimingMatch
    ) {
        guard hasHighConfidenceResidentOnlyEvidence,
              !residualEchoBaselineFrozen,
              !sourceGateOpen,
              sourceGateConfirmationFrameCount == 0 else {
            return
        }
        let renderRMS = signalRMS(timingMatch.renderSamples)
        guard renderRMS >= Self.minimumTimingRMS else { return }
        let observedGain = cleanRMS / renderRMS
        let observedRawGain = rawCaptureRMS / renderRMS
        let observedLinearGain = linearAECOutputRMS / renderRMS
        guard observedGain.isFinite,
              observedRawGain.isFinite,
              observedLinearGain.isFinite else { return }
        if residualEchoBaselineFrameCount == 0 {
            rawEchoGainBaseline = observedRawGain
            residualEchoGainBaseline = observedGain
            linearAECOutputGainBaseline = observedLinearGain
        } else {
            rawEchoGainBaseline = smoothedBaselineGain(
                rawEchoGainBaseline,
                observed: observedRawGain
            )
            residualEchoGainBaseline = smoothedBaselineGain(
                residualEchoGainBaseline,
                observed: observedGain
            )
            linearAECOutputGainBaseline = smoothedBaselineGain(
                linearAECOutputGainBaseline,
                observed: observedLinearGain
            )
        }
        residualEchoBaselineFrameCount &+= 1
        residualEchoBaselineUpdateCount &+= 1
    }

    private func smoothedBaselineGain(
        _ current: Double,
        observed: Double
    ) -> Double {
        let boundedObservation = min(
            observed,
            current * Self.maximumBaselineGainIncreaseRatio
        )
        return current + (boundedObservation - current)
            * Self.residualEchoBaselineSmoothingFactor
    }

    private func freezeResidualEchoBaseline() {
        guard !residualEchoBaselineFrozen else { return }
        residualEchoBaselineFrozen = true
        residualEchoBaselineFreezeCount &+= 1
    }

    private func recordSourceGateOpenFrame() {
        currentSourceGateOpenFrameCount &+= 1
        maximumSourceGateOpenFrameCount = max(
            maximumSourceGateOpenFrameCount,
            currentSourceGateOpenFrameCount
        )
    }

    private func captureWhileGateIsOpen(
        _ processedFrame: [Float],
        captureFrameIndex: UInt64
    ) -> [MacSpeechAcousticCaptureSpan] {
        switch inputClassification {
        case .nearEndSpeech, .doubleTalk:
            sourceGateNonUserHangoverFrameCount = 0
            recordForwardedSourceFrames(1)
            return [captureSpan(
                samples: processedFrame,
                captureFrameIndex: captureFrameIndex
            )]
        case .uncertain, .echoOnly:
            if adaptiveNearEndContinuationCandidate {
                sourceGateNonUserHangoverFrameCount = 0
                recordForwardedSourceFrames(1)
                return [captureSpan(
                    samples: processedFrame,
                    captureFrameIndex: captureFrameIndex
                )]
            }
            sourceGateNonUserHangoverFrameCount += 1
            if sourceGateNonUserHangoverFrameCount
                >= Self.maximumSourceGateNonUserHangoverFrames {
                return suppressCaptureFrameAndCloseGate(
                    reason: .nonUserHangover,
                    captureFrameIndex: captureFrameIndex
                )
            }
            recordForwardedSourceFrames(1)
            return [captureSpan(
                samples: processedFrame,
                captureFrameIndex: captureFrameIndex
            )]
        }
    }

    private func recordSourceClassification(timingMatch: TimingMatch?) {
        switch inputClassification {
        case .echoOnly:
            echoOnlyFrameCount &+= 1
        case .nearEndSpeech:
            nearEndSpeechFrameCount &+= 1
        case .doubleTalk:
            doubleTalkFrameCount &+= 1
        case .uncertain:
            uncertainFrameCount &+= 1
        }

        if timingMatch == nil,
           rawCaptureRMS >= Self.minimumNearEndRMS,
           inputClassification != .nearEndSpeech,
           inputClassification != .doubleTalk {
            sourceTimingUnavailableFrameCount &+= 1
            consecutiveSourceAlignmentUnavailableFrameCount += 1
            consecutiveSourceUncertainFrameCount = 0
            if consecutiveSourceAlignmentUnavailableFrameCount
                >= Self.sourceGateResetFrameCount {
                pendingSourceGateReset = true
            }
            return
        }

        consecutiveSourceAlignmentUnavailableFrameCount = 0
        if timingMatch != nil {
            sourceTimingCandidateFrameCount &+= 1
        }
        if inputClassification == .uncertain,
           rawCaptureRMS >= Self.minimumNearEndRMS {
            consecutiveSourceUncertainFrameCount += 1
            if consecutiveSourceUncertainFrameCount
                >= Self.sourceGateResetFrameCount {
                pendingSourceGateReset = true
            }
        } else {
            consecutiveSourceUncertainFrameCount = 0
        }
    }

    private func appendSourceGatePreRoll(
        _ span: MacSpeechAcousticCaptureSpan
    ) {
        if sourceGatePreRoll.count
            == Self.sourceGatePreRollFrameCapacity {
            sourceGatePreRoll.removeFirst()
            recordSuppressedSourceFrames(1)
        }
        sourceGatePreRoll.append(span)
    }

    private func suppressClosedGateFrame(
        captureFrameIndex: UInt64
    ) -> [MacSpeechAcousticCaptureSpan] {
        let current = captureSpan(
            samples: [Float](
                repeating: 0,
                count: Self.frameSampleCount
            ),
            captureFrameIndex: captureFrameIndex
        )
        let output = sourceGatePreRoll.map(silencedCaptureSpan) + [current]
        let suppressedFrameCount = sourceGatePreRoll.count + 1
        sourceGatePreRoll.removeAll(keepingCapacity: true)
        sourceGateConfirmationFrameCount = 0
        sourceGateCandidateNearEndFrameCount = 0
        sourceGateCandidateDoubleTalkFrameCount = 0
        recordSuppressedSourceFrames(suppressedFrameCount)
        return output
    }

    private func suppressCaptureFrameAndCloseGate(
        reason: MacSpeechSourceGateCloseReason,
        captureFrameIndex: UInt64
    ) -> [MacSpeechAcousticCaptureSpan] {
        let pending = sourceGatePreRoll.map(silencedCaptureSpan)
        recordSuppressedSourceFrames(1)
        resetSourceGate(
            keepingClassification: true,
            closeReason: reason
        )
        return pending + [captureSpan(
            samples: [Float](
                repeating: 0,
                count: Self.frameSampleCount
            ),
            captureFrameIndex: captureFrameIndex
        )]
    }

    private func silencedCaptureSpan(
        _ span: MacSpeechAcousticCaptureSpan
    ) -> MacSpeechAcousticCaptureSpan {
        MacSpeechAcousticCaptureSpan(
            samples: [Float](
                repeating: 0,
                count: span.samples.count
            ),
            observation: span.observation
        )
    }

    private func recordForwardedSourceFrames(_ frameCount: Int) {
        let count = UInt64(frameCount)
        sourceForwardedFrameCount &+= count
        currentContinuousSourceForwardedFrameCount &+= count
        maximumContinuousSourceForwardedFrameCount = max(
            maximumContinuousSourceForwardedFrameCount,
            currentContinuousSourceForwardedFrameCount
        )
    }

    private func recordSuppressedSourceFrames(_ frameCount: Int) {
        sourceSuppressedFrameCount &+= UInt64(frameCount)
        currentContinuousSourceForwardedFrameCount = 0
    }

    private func drainSourceGatePreRoll()
        -> [MacSpeechAcousticCaptureSpan] {
        let output = sourceGatePreRoll.map { span in
            MacSpeechAcousticCaptureSpan(
                samples: span.samples,
                observation: span.observation.withSourceGate(
                    open: true,
                    epoch: sourceGateEpochSequence
                )
            )
        }
        recordForwardedSourceFrames(sourceGatePreRoll.count)
        sourceGatePreRoll.removeAll(keepingCapacity: true)
        sourceGateCandidateNearEndFrameCount = 0
        sourceGateCandidateDoubleTalkFrameCount = 0
        return output
    }

    private func beginSourceGateEpoch() {
        sourceGateEpochSequence &+= 1
        let preRollFrameCount = UInt64(sourceGatePreRoll.count)
        let currentCaptureFrame = captureFrameCount &+ 1
        activeSourceGateEpoch = SourceGateEpochAccumulator(
            playbackSequence: playbackSequence,
            epochSequence: sourceGateEpochSequence,
            openedAtCaptureFrame:
                currentCaptureFrame &+ 1 &- preRollFrameCount,
            forwardedFrameCountAtOpen: sourceForwardedFrameCount,
            suppressedFrameCountAtOpen: sourceSuppressedFrameCount,
            echoOnlyFrameCountAtOpen: echoOnlyFrameCount,
            nearEndSpeechFrameCountAtOpen:
                nearEndSpeechFrameCount
                    &- sourceGateCandidateNearEndFrameCount,
            doubleTalkFrameCountAtOpen:
                doubleTalkFrameCount
                    &- sourceGateCandidateDoubleTalkFrameCount,
            uncertainFrameCountAtOpen: uncertainFrameCount,
            rawEchoGainBaselineAtOpen: rawEchoGainBaseline,
            residualEchoGainBaselineAtOpen: residualEchoGainBaseline,
            linearAECOutputGainBaselineAtOpen:
                linearAECOutputGainBaseline,
            aecBufferDelayMillisecondsAtOpen: delayMilliseconds,
            sourceAlignmentDelayMillisecondsAtOpen:
                roundedSourceAlignmentDelay,
            estimatedDelayMillisecondsAtOpen:
                backendStats.estimatedDelayMilliseconds
        )
    }

    private func closeSourceGateEpoch(
        reason: MacSpeechSourceGateCloseReason?
    ) {
        guard let accumulator = activeSourceGateEpoch else { return }
        let closesDuringCurrentCapture = reason == .nonUserHangover
            || reason == .sourceEvidenceReset
        appendSourceGateEpochDiagnostic(
            makeSourceGateEpochDiagnostic(
                accumulator,
                closedAtCaptureFrame: captureFrameCount
                    &+ (closesDuringCurrentCapture ? 1 : 0),
                closeReason: reason
            )
        )
        activeSourceGateEpoch = nil
    }

    private func appendSourceGateEpochDiagnostic(
        _ diagnostic: MacSpeechSourceGateEpochDiagnostic
    ) {
        if sourceGateEpochs.count
            == Self.sourceGateEpochDiagnosticCapacity {
            sourceGateEpochs.removeFirst()
        }
        sourceGateEpochs.append(diagnostic)
    }

    private func makeSourceGateEpochDiagnostic(
        _ accumulator: SourceGateEpochAccumulator,
        closedAtCaptureFrame: UInt64?,
        closeReason: MacSpeechSourceGateCloseReason?
    ) -> MacSpeechSourceGateEpochDiagnostic {
        MacSpeechSourceGateEpochDiagnostic(
            playbackSequence: accumulator.playbackSequence,
            epochSequence: accumulator.epochSequence,
            openedAtCaptureFrame: accumulator.openedAtCaptureFrame,
            closedAtCaptureFrame: closedAtCaptureFrame,
            totalFrameCount: currentSourceGateOpenFrameCount,
            forwardedFrameCount:
                sourceForwardedFrameCount
                    &- accumulator.forwardedFrameCountAtOpen,
            suppressedFrameCount:
                sourceSuppressedFrameCount
                    &- accumulator.suppressedFrameCountAtOpen,
            echoOnlyFrameCount:
                echoOnlyFrameCount &- accumulator.echoOnlyFrameCountAtOpen,
            nearEndSpeechFrameCount:
                nearEndSpeechFrameCount
                    &- accumulator.nearEndSpeechFrameCountAtOpen,
            doubleTalkFrameCount:
                doubleTalkFrameCount
                    &- accumulator.doubleTalkFrameCountAtOpen,
            uncertainFrameCount:
                uncertainFrameCount
                    &- accumulator.uncertainFrameCountAtOpen,
            rawEchoGainBaselineAtOpen:
                accumulator.rawEchoGainBaselineAtOpen,
            rawEchoGainBaselineAtClose: rawEchoGainBaseline,
            residualEchoGainBaselineAtOpen:
                accumulator.residualEchoGainBaselineAtOpen,
            residualEchoGainBaselineAtClose: residualEchoGainBaseline,
            linearAECOutputGainBaselineAtOpen:
                accumulator.linearAECOutputGainBaselineAtOpen,
            linearAECOutputGainBaselineAtClose:
                linearAECOutputGainBaseline,
            aecBufferDelayMillisecondsAtOpen:
                accumulator.aecBufferDelayMillisecondsAtOpen,
            aecBufferDelayMillisecondsAtClose: delayMilliseconds,
            sourceAlignmentDelayMillisecondsAtOpen:
                accumulator.sourceAlignmentDelayMillisecondsAtOpen,
            sourceAlignmentDelayMillisecondsAtClose:
                roundedSourceAlignmentDelay,
            estimatedDelayMillisecondsAtOpen:
                accumulator.estimatedDelayMillisecondsAtOpen,
            estimatedDelayMillisecondsAtClose:
                backendStats.estimatedDelayMilliseconds,
            closeReason: closeReason
        )
    }

    private var roundedSourceAlignmentDelay: Int? {
        alignedDelayMilliseconds.map { Int($0.rounded()) }
    }

    private func sourceGateEpochDiagnostics()
        -> [MacSpeechSourceGateEpochDiagnostic] {
        var diagnostics = sourceGateEpochs
        if let activeSourceGateEpoch {
            diagnostics.append(makeSourceGateEpochDiagnostic(
                activeSourceGateEpoch,
                closedAtCaptureFrame: nil,
                closeReason: nil
            ))
        }
        if diagnostics.count > Self.sourceGateEpochDiagnosticCapacity {
            diagnostics.removeFirst(
                diagnostics.count - Self.sourceGateEpochDiagnosticCapacity
            )
        }
        return diagnostics
    }

    private func updateAlignedDelay(_ contentDelayMilliseconds: Double) {
        guard contentDelayMilliseconds.isFinite,
              contentDelayMilliseconds >= 0,
              contentDelayMilliseconds
                <= Double(Self.maximumDelayMilliseconds) else {
            return
        }
        let smoothedDelay = alignedDelayMilliseconds.map {
            $0 * 0.8 + contentDelayMilliseconds * 0.2
        } ?? contentDelayMilliseconds
        alignedDelayMilliseconds = smoothedDelay
    }

    private func applyDelay(_ milliseconds: Int) {
        guard milliseconds >= 0,
              milliseconds <= Self.maximumDelayMilliseconds else {
            enterFallback(.delayInvalid)
            return
        }
        guard delayMilliseconds != milliseconds else { return }
        delayMilliseconds = milliseconds
        guard mode == .webRTCAEC3, let backend else { return }
        do {
            try backend.setDelay(milliseconds: milliseconds)
        } catch {
            enterFallback(.delayInvalid)
        }
    }

    private func updateSignalDiagnostics(
        rawCapture: [Float],
        processedCapture: [Float],
        linearAECOutput: [Float],
        captureHostTimeNanoseconds: UInt64?,
        timingMatch: TimingMatch?
    ) {
        latestCaptureHostTimeNanoseconds = captureHostTimeNanoseconds
        rawCaptureRMS = signalRMS(rawCapture)
        processedCaptureRMS = signalRMS(processedCapture)
        linearAECOutputRMS = signalRMS(linearAECOutput)
        processedLinearCorrelation = normalizedCorrelation(
            downsampleToSixteenKilohertz(processedCapture),
            linearAECOutput
        )
        if let timingMatch {
            matchedRenderHostTimeNanoseconds =
                timingMatch.renderHostTimeNanoseconds
            matchedRenderReferenceRMS = timingMatch.renderRMS
            renderCaptureCorrelation = timingMatch.correlation
            residualRenderCorrelation = normalizedCorrelation(
                processedCapture,
                timingMatch.renderSamples
            )
            linearRenderCorrelation = normalizedCorrelation(
                linearAECOutput,
                downsampleToSixteenKilohertz(timingMatch.renderSamples)
            )
        } else {
            matchedRenderHostTimeNanoseconds = nil
            matchedRenderReferenceRMS = 0
            renderCaptureCorrelation = 0
            residualRenderCorrelation = 0
            linearRenderCorrelation = 0
        }
    }

    private func downsampleToSixteenKilohertz(_ samples: [Float]) -> [Float] {
        guard samples.count == Self.frameSampleCount else { return [] }
        return stride(from: 0, to: samples.count, by: 3).map { index in
            (samples[index] + samples[index + 1] + samples[index + 2]) / 3
        }
    }

    private func signalRMS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { partial, sample in
            let value = Double(sample.isFinite ? sample : 0)
            return partial + value * value
        }
        return sqrt(sum / Double(samples.count))
    }

    #if DEBUG
    private func makeAcousticReplayInitialState()
        -> MacSpeechAcousticReplayInitialStateSnapshot {
        MacSpeechAcousticReplayInitialStateSnapshot(
            mode: mode.rawValue,
            renderFIFOSamples: renderFIFO,
            captureFIFOSamples: captureFIFO,
            fifoSampleCapacity: fifoSampleCapacity,
            renderRemainderHostTimeNanoseconds:
                renderRemainderHostTimeNanoseconds,
            captureRemainderHostTimeNanoseconds:
                captureRemainderHostTimeNanoseconds,
            renderFrameCount: renderFrameCount,
            captureFrameCount: captureFrameCount,
            delayMilliseconds: delayMilliseconds,
            presentationDelayMilliseconds: presentationDelayMilliseconds,
            captureProcessingNanoseconds: UInt64(max(
                0,
                (captureProcessingMilliseconds * 1_000_000).rounded()
            )),
            backendStats: MacSpeechAcousticReplayBackendStatsSnapshot(
                backendStats
            ),
            timingHistoryFrameCount: renderTimingHistory.count,
            timingLockCandidateMilliseconds:
                timingLockCandidateMilliseconds,
            timingLockCandidateFrameCount: timingLockCandidateFrameCount,
            timingLockedDelayMilliseconds: timingLockedDelayMilliseconds,
            timingLockConsecutiveMissFrameCount:
                timingLockConsecutiveMissFrameCount,
            alignedDelayMilliseconds: alignedDelayMilliseconds,
            rawEchoGainBaseline: rawEchoGainBaseline,
            residualEchoGainBaseline: residualEchoGainBaseline,
            linearAECOutputGainBaseline: linearAECOutputGainBaseline,
            residualEchoBaselineFrameCount: residualEchoBaselineFrameCount,
            residualEchoBaselineFrozen: residualEchoBaselineFrozen,
            sourceGateOpen: sourceGateOpen,
            sourceGatePreRollFrameCount: sourceGatePreRoll.count,
            sourceGateConfirmationFrameCount:
                sourceGateConfirmationFrameCount,
            sourceGateNonUserHangoverFrameCount:
                sourceGateNonUserHangoverFrameCount,
            sourceGateCandidateNearEndFrameCount:
                sourceGateCandidateNearEndFrameCount,
            sourceGateCandidateDoubleTalkFrameCount:
                sourceGateCandidateDoubleTalkFrameCount,
            consecutiveSourceAlignmentUnavailableFrameCount:
                consecutiveSourceAlignmentUnavailableFrameCount,
            consecutiveSourceUncertainFrameCount:
                consecutiveSourceUncertainFrameCount,
            pendingSourceGateReset: pendingSourceGateReset,
            renderCaptureIsolationEstablished:
                renderCaptureIsolationEstablished,
            renderCaptureIsolationQuietFrameCount:
                renderCaptureIsolationQuietFrameCount,
            hasReliableEchoCancellation: hasReliableEchoCancellation,
            poorResidualEchoFrameCount: poorResidualEchoFrameCount,
            playbackSequence: playbackSequence,
            sourceGateEpochSequence: sourceGateEpochSequence,
            playbackActive: isPlaybackActive,
            routeRebuilding: isRouteRebuilding,
            fallbackReason: fallbackReason?.rawValue
        )
    }

    private func beginAcousticReplayAudioCall(
        kind: MacSpeechAcousticReplayAudioCallKind,
        samples: [Float],
        hostTimeNanoseconds: UInt64?
    ) -> AcousticReplayAudioCallContext? {
        guard let capture = acousticReplayCapture,
              !capture.isSealed else { return nil }
        if capture.startedAt == nil {
            capture.startedAt = Date()
        }
        let sampleOffset: Int
        let firstFrameIndex: Int
        switch kind {
        case .render:
            sampleOffset = capture.chronologicalRenderSamples.count
            firstFrameIndex = capture.renderFrames.count
            capture.chronologicalRenderSamples.append(contentsOf: samples)
        case .capture:
            sampleOffset = capture.rawMicrophoneSamples.count
            firstFrameIndex = capture.captureFrames.count
            capture.rawMicrophoneSamples.append(contentsOf: samples)
        }
        return AcousticReplayAudioCallContext(
            ordinal: capture.takeOrdinal(),
            kind: kind,
            sampleOffset: sampleOffset,
            sampleCount: samples.count,
            hostTimeNanoseconds: hostTimeNanoseconds,
            firstFrameIndex: firstFrameIndex,
            backendStatsBefore:
                MacSpeechAcousticReplayBackendStatsSnapshot(backendStats)
        )
    }

    private func finishAcousticReplayAudioCall(
        _ context: AcousticReplayAudioCallContext?
    ) {
        guard let context,
              let capture = acousticReplayCapture,
              !capture.isSealed else { return }
        let frameCount: Int
        switch context.kind {
        case .render:
            frameCount = capture.renderFrames.count - context.firstFrameIndex
        case .capture:
            frameCount = capture.captureFrames.count - context.firstFrameIndex
        }
        capture.audioCalls.append(MacSpeechAcousticReplayAudioCallSnapshot(
            ordinal: context.ordinal,
            kind: context.kind,
            sampleOffset: context.sampleOffset,
            sampleCount: context.sampleCount,
            hostTimeNanoseconds: context.hostTimeNanoseconds,
            firstFrameIndex: context.firstFrameIndex,
            frameCount: frameCount,
            backendStatsBefore: context.backendStatsBefore,
            backendStatsAfter:
                MacSpeechAcousticReplayBackendStatsSnapshot(backendStats)
        ))
        if context.kind == .capture,
           capture.sawPlaybackStart,
           capture.postPlaybackCaptureFrameCount
            >= capture.targetPostPlaybackCaptureFrameCount {
            sealAcousticReplayCaptureLocked(reason: .targetReached)
        }
    }

    private func recordAcousticReplayRenderFrame(
        call: AcousticReplayAudioCallContext?,
        hostTimeNanoseconds: UInt64?
    ) {
        guard let call,
              let capture = acousticReplayCapture,
              !capture.isSealed else { return }
        let frame = MacSpeechAcousticReplayRenderFrameSnapshot(
            callOrdinal: call.ordinal,
            frameInCall: capture.renderFrames.count - call.firstFrameIndex,
            renderFrameIndex: renderFrameCount,
            hostTimeNanoseconds: hostTimeNanoseconds,
            aecBufferDelayMilliseconds: delayMilliseconds,
            backendStats: MacSpeechAcousticReplayBackendStatsSnapshot(
                backendStats
            )
        )
        capture.renderFrames.append(frame)
        if let hostTimeNanoseconds {
            capture.renderCallOrdinalByHostTime[hostTimeNanoseconds] =
                call.ordinal
        }
    }

    private func recordAcousticReplayCaptureFrame(
        call: AcousticReplayAudioCallContext?,
        rawCapture: [Float],
        processedCapture: [Float],
        linearAECOutput: [Float],
        timingMatch: TimingMatch?,
        observation: MacSpeechAcousticObservationSnapshot,
        emittedSpans: [MacSpeechAcousticCaptureSpan]
    ) {
        guard let call,
              let capture = acousticReplayCapture,
              !capture.isSealed,
              rawCapture.count == Self.frameSampleCount,
              processedCapture.count == Self.frameSampleCount,
              linearAECOutput.count
                == Self.linearOutputFrameSampleCount else { return }
        let cleanOffset = capture.aecCleanSamples.count
        let linearOffset = capture.aecLinearSamples.count
        capture.aecCleanSamples.append(contentsOf: processedCapture)
        capture.aecLinearSamples.append(contentsOf: linearAECOutput)
        capture.captureFrames.append(MacSpeechAcousticReplayFrameSnapshot(
            callOrdinal: call.ordinal,
            frameInCall: capture.captureFrames.count - call.firstFrameIndex,
            captureFrameIndex: observation.captureFrameIndex,
            aecCleanSampleOffset: cleanOffset,
            aecLinearSampleOffset: linearOffset,
            timestampNanoseconds:
                observation.captureHostTimeNanoseconds
                    ?? DispatchTime.now().uptimeNanoseconds,
            captureHostTimeNanoseconds:
                observation.captureHostTimeNanoseconds,
            timingMatchAvailable: timingMatch != nil,
            matchedRenderCallOrdinal: timingMatch.flatMap {
                capture.renderCallOrdinalByHostTime[
                    $0.renderHostTimeNanoseconds
                ]
            },
            matchedRenderHostTimeNanoseconds:
                timingMatch?.renderHostTimeNanoseconds,
            timingDelayMilliseconds: timingMatch?.delayMilliseconds,
            timingCorrelation: timingMatch?.correlation,
            renderReferenceRMS: timingMatch?.renderRMS,
            aecBufferDelayMilliseconds: delayMilliseconds,
            sourceAlignmentLocked: observation.sourceAlignmentLocked,
            sourceAlignmentDelayMilliseconds:
                observation.sourceAlignmentDelayMilliseconds,
            estimatedDelayMilliseconds:
                observation.estimatedDelayMilliseconds,
            backendStats: MacSpeechAcousticReplayBackendStatsSnapshot(
                backendStats
            ),
            inputClassification: observation.inputClassification,
            sourceGateOpen: observation.sourceGateOpen,
            sourceGateEpoch: observation.sourceGateEpoch,
            playbackSequence: observation.playbackSequence,
            isPlaybackActive: observation.isPlaybackActive,
            rawCaptureRMS: observation.rawCaptureRMS,
            processedCaptureRMS: observation.processedCaptureRMS,
            linearAECOutputRMS: observation.linearAECOutputRMS,
            linearRenderCorrelation: observation.linearRenderCorrelation,
            processedLinearCorrelation: processedLinearCorrelation,
            residualRenderCorrelation:
                observation.residualRenderCorrelation,
            timingLockCandidateMilliseconds:
                timingLockCandidateMilliseconds,
            timingLockCandidateFrameCount: timingLockCandidateFrameCount,
            timingLockedDelayMilliseconds: timingLockedDelayMilliseconds,
            timingLockConsecutiveMissFrameCount:
                timingLockConsecutiveMissFrameCount,
            rawEchoGainBaseline: rawEchoGainBaseline,
            residualEchoGainBaseline: residualEchoGainBaseline,
            linearAECOutputGainBaseline: linearAECOutputGainBaseline,
            residualEchoBaselineFrameCount: residualEchoBaselineFrameCount,
            residualEchoBaselineFrozen: residualEchoBaselineFrozen,
            sourceGatePreRollFrameCount: sourceGatePreRoll.count,
            sourceGateConfirmationFrameCount:
                sourceGateConfirmationFrameCount,
            sourceGateNonUserHangoverFrameCount:
                sourceGateNonUserHangoverFrameCount,
            pendingSourceGateReset: pendingSourceGateReset,
            renderCaptureIsolationEstablished:
                renderCaptureIsolationEstablished,
            renderCaptureIsolationQuietFrameCount:
                renderCaptureIsolationQuietFrameCount,
            emittedSpans: emittedSpans.map {
                MacSpeechAcousticReplayEmittedSpanSnapshot(
                    captureFrameIndex: $0.observation.captureFrameIndex,
                    sourceGateOpen: $0.observation.sourceGateOpen,
                    sourceGateEpoch: $0.observation.sourceGateEpoch,
                    silenced: $0.samples.allSatisfy { $0 == 0 }
                )
            }
        ))
        if capture.sawPlaybackStart {
            capture.postPlaybackCaptureFrameCount += 1
        }
    }

    private func recordAcousticReplayControl(
        kind: MacSpeechAcousticReplayControlKind,
        outputPresentationLatencySeconds: Double? = nil,
        capturePresentationLatencySeconds: Double? = nil,
        captureProcessingDurationNanoseconds: UInt64? = nil
    ) {
        guard let capture = acousticReplayCapture,
              !capture.isSealed else { return }
        if capture.startedAt == nil {
            capture.startedAt = Date()
        }
        capture.controlEvents.append(
            MacSpeechAcousticReplayControlEventSnapshot(
                ordinal: capture.takeOrdinal(),
                kind: kind,
                outputPresentationLatencySeconds:
                    outputPresentationLatencySeconds,
                capturePresentationLatencySeconds:
                    capturePresentationLatencySeconds,
                captureProcessingDurationNanoseconds:
                    captureProcessingDurationNanoseconds
            )
        )
    }

    private func sealAcousticReplayCaptureLocked(
        reason: MacSpeechAcousticReplaySealReason
    ) {
        guard let capture = acousticReplayCapture,
              !capture.isSealed else { return }
        capture.finalState = makeAcousticReplayInitialState()
        capture.isSealed = true
        capture.sealReason = reason
        capture.endedAt = Date()
    }
    #endif

    private func normalizedCorrelation(
        _ first: [Float],
        _ second: [Float]
    ) -> Double {
        guard first.count == second.count, !first.isEmpty else { return 0 }
        let firstMean = first.reduce(0.0) { $0 + Double($1) }
            / Double(first.count)
        let secondMean = second.reduce(0.0) { $0 + Double($1) }
            / Double(second.count)
        var covariance = 0.0
        var firstEnergy = 0.0
        var secondEnergy = 0.0
        for index in first.indices {
            let firstValue = Double(first[index]) - firstMean
            let secondValue = Double(second[index]) - secondMean
            covariance += firstValue * secondValue
            firstEnergy += firstValue * firstValue
            secondEnergy += secondValue * secondValue
        }
        guard firstEnergy > 0, secondEnergy > 0 else { return 0 }
        return min(abs(covariance / sqrt(firstEnergy * secondEnergy)), 1)
    }

    private func updateDrift() {
        let skew = Int64(renderFrameCount) - Int64(captureFrameCount)
        if skew > lastDriftSkew {
            driftTrend = "render_ahead"
        } else if skew < lastDriftSkew {
            driftTrend = "capture_ahead"
        } else {
            driftTrend = "stable"
        }
        lastDriftSkew = skew
        let shouldLogInitialState = lastLoggedCaptureFrameCount == 0
            && captureFrameCount >= 10
        let shouldLogPeriodicState = lastLoggedCaptureFrameCount > 0
            && captureFrameCount >= lastLoggedCaptureFrameCount + 100
        if shouldLogInitialState || shouldLogPeriodicState {
            lastLoggedCaptureFrameCount = captureFrameCount
            logger.info(
                "AEC mode=\(self.mode.rawValue, privacy: .public) enabled=\(self.backendStats.enabled, privacy: .public) active=\(self.backendStats.active, privacy: .public) frames=\(self.renderFrameCount, privacy: .public)/\(self.captureFrameCount, privacy: .public) delay_ms=\(self.delayMilliseconds, privacy: .public) presentation_ms=\(self.presentationDelayMilliseconds, privacy: .public) aligned_ms=\(self.alignedDelayMilliseconds ?? -1, privacy: .public) estimated_ms=\(self.backendStats.estimatedDelayMilliseconds, privacy: .public) erl=\(self.backendStats.erlDecibels, privacy: .public) erle=\(self.backendStats.erleDecibels, privacy: .public) raw_rms=\(self.rawCaptureRMS, privacy: .public) clean_rms=\(self.processedCaptureRMS, privacy: .public) correlation=\(self.renderCaptureCorrelation, privacy: .public) residual_correlation=\(self.residualRenderCorrelation, privacy: .public) echo_gain=\(self.rawEchoGainBaseline, privacy: .public)/\(self.residualEchoGainBaseline, privacy: .public)/\(self.residualEchoBaselineFrameCount, privacy: .public) adaptive=\(self.adaptiveEvidenceCandidateFrameCount, privacy: .public)/\(self.adaptiveDoubleTalkFrameCount, privacy: .public)/\(self.maximumAdaptiveRawExcessRMS, privacy: .public)/\(self.maximumAdaptiveResidualExcessRMS, privacy: .public) isolation=\(self.renderCaptureIsolationEstablished, privacy: .public)/\(self.renderCaptureIsolationQuietFrameCount, privacy: .public)/\(self.renderCaptureIsolationEstablishmentCount, privacy: .public)/\(self.renderCaptureIsolationRevocationCount, privacy: .public) source=\(self.inputClassification.rawValue, privacy: .public) source_gate=\(self.sourceGateOpen, privacy: .public) source_gate_max=\(self.maximumSourceGateOpenFrameCount, privacy: .public) source_forwarded=\(self.sourceForwardedFrameCount, privacy: .public) source_suppressed=\(self.sourceSuppressedFrameCount, privacy: .public) source_max_run=\(self.maximumContinuousSourceForwardedFrameCount, privacy: .public) source_close=\(self.lastSourceGateCloseReason?.rawValue ?? "-", privacy: .public) source_timing=\(self.sourceTimingCandidateFrameCount, privacy: .public)/\(self.sourceTimingUnavailableFrameCount, privacy: .public) preroll_frames=\(self.sourceGatePreRoll.count, privacy: .public) timing_frames=\(self.renderTimingHistory.count, privacy: .public) fifo=\(self.renderFIFO.count, privacy: .public)/\(self.captureFIFO.count, privacy: .public) drift=\(self.driftTrend, privacy: .public)"
            )
        }
    }

    private func refreshBackendStats() {
        guard let backend else { return }
        do {
            backendStats = try backend.stats()
        } catch {
            enterFallback(.statsUnavailable)
        }
    }

    private func applyResidualEchoGateProtection(
        processedFrameCount: UInt64
    ) {
        guard processedFrameCount > 0,
              isPlaybackActive,
              mode == .webRTCAEC3,
              backendStats.active,
              backendStats.erleDecibels.isFinite else {
            poorResidualEchoFrameCount = 0
            return
        }
        if backendStats.erleDecibels >= Self.reliableERLEDecibels {
            hasReliableEchoCancellation = true
            poorResidualEchoFrameCount = 0
            return
        }
        guard hasReliableEchoCancellation,
              backendStats.erleDecibels < Self.failedERLEDecibels else {
            poorResidualEchoFrameCount = 0
            return
        }
        guard inputClassification == .echoOnly
                || inputClassification == .uncertain else {
            poorResidualEchoFrameCount = 0
            return
        }
        poorResidualEchoFrameCount &+= processedFrameCount
        if poorResidualEchoFrameCount
            >= Self.residualEchoGateResetFrameCount {
            resetSourceGate(
                keepingClassification: true,
                closeReason: .residualEchoProtection
            )
            poorResidualEchoFrameCount = 0
        }
    }

    private func enterFallback(_ reason: MacSpeechAECFallbackReason) {
        #if DEBUG
        sealAcousticReplayCaptureLocked(reason: .hostFallback)
        #endif
        if mode != .halfDuplexFallback || fallbackReason != reason {
            fallbackCount &+= 1
        }
        lastFallbackReason = reason
        mode = .halfDuplexFallback
        fallbackReason = reason
        backendStats = disabledStats()
        poorResidualEchoFrameCount = 0
        clearFIFOs()
        resetSourceGate(closeReason: .hostFallback)
        logger.error(
            "AEC fallback reason=\(reason.rawValue, privacy: .public) delay_ms=\(self.delayMilliseconds, privacy: .public)"
        )
    }

    private func clearFIFOs() {
        renderFIFO.removeAll(keepingCapacity: true)
        captureFIFO.removeAll(keepingCapacity: true)
        renderRemainderHostTimeNanoseconds = nil
        captureRemainderHostTimeNanoseconds = nil
    }

    private func clearTimingHistory() {
        renderTimingHistory.removeAll(keepingCapacity: true)
        latestRenderHostTimeNanoseconds = nil
        latestRenderReferenceRMS = 0
        matchedRenderHostTimeNanoseconds = nil
        matchedRenderReferenceRMS = 0
        timingLockCandidateMilliseconds = nil
        timingLockCandidateFrameCount = 0
        timingLockedDelayMilliseconds = nil
        timingLockConsecutiveMissFrameCount = 0
        clearTimingAssociation()
        renderCaptureIsolationEstablished = false
        renderCaptureIsolationQuietFrameCount = 0
    }

    private func clearTimingAssociation() {
        timingAssociationCaptureHostTimeNanoseconds = nil
        timingAssociationRenderHostTimeNanoseconds = nil
        timingAssociationFollowsExpectedTimeline = false
    }

    private func resetSignalDiagnostics() {
        latestCaptureHostTimeNanoseconds = nil
        matchedRenderHostTimeNanoseconds = nil
        matchedRenderReferenceRMS = 0
        rawCaptureRMS = 0
        processedCaptureRMS = 0
        renderCaptureCorrelation = 0
        residualRenderCorrelation = 0
        linearAECOutputRMS = 0
        linearRenderCorrelation = 0
        processedLinearCorrelation = 0
    }

    private func clearTimingMatchIdentity() {
        matchedRenderHostTimeNanoseconds = nil
        matchedRenderReferenceRMS = 0
    }

    private func resetSourceGate(
        keepingClassification: Bool = false,
        closeReason: MacSpeechSourceGateCloseReason? = nil
    ) {
        recordSuppressedSourceFrames(sourceGatePreRoll.count)
        if sourceGateOpen {
            sourceGateCloseCount &+= 1
            lastSourceGateCloseReason = closeReason
            closeSourceGateEpoch(reason: closeReason)
        }
        sourceGateOpen = false
        currentSourceGateOpenFrameCount = 0
        sourceGatePreRoll.removeAll(keepingCapacity: true)
        sourceGateCandidateNearEndFrameCount = 0
        sourceGateCandidateDoubleTalkFrameCount = 0
        sourceGateConfirmationFrameCount = 0
        sourceGateNonUserHangoverFrameCount = 0
        consecutiveSourceAlignmentUnavailableFrameCount = 0
        consecutiveSourceUncertainFrameCount = 0
        pendingSourceGateReset = false
        if !keepingClassification {
            inputClassification = .uncertain
        }
    }

    private func resetDiagnosticCounters() {
        echoOnlyFrameCount = 0
        nearEndSpeechFrameCount = 0
        doubleTalkFrameCount = 0
        uncertainFrameCount = 0
        sourceForwardedFrameCount = 0
        sourceSuppressedFrameCount = 0
        sourceTimingCandidateFrameCount = 0
        sourceTimingUnavailableFrameCount = 0
        sourceGateOpenCount = 0
        sourceGateCloseCount = 0
        sourceGateCandidateNearEndFrameCount = 0
        sourceGateCandidateDoubleTalkFrameCount = 0
        currentSourceGateOpenFrameCount = 0
        maximumSourceGateOpenFrameCount = 0
        currentContinuousSourceForwardedFrameCount = 0
        maximumContinuousSourceForwardedFrameCount = 0
        adaptiveEvidenceCandidateFrameCount = 0
        adaptiveDoubleTalkFrameCount = 0
        maximumAdaptiveRawExcessRMS = 0
        maximumAdaptiveResidualExcessRMS = 0
        maximumAdaptiveLinearExcessRMS = 0
        renderCaptureIsolationEstablishmentCount = 0
        renderCaptureIsolationRevocationCount = 0
        residualEchoBaselineUpdateCount = 0
        residualEchoBaselineFreezeCount = 0
        lastSourceGateCloseReason = nil
        sourceGateEpochSequence = 0
        sourceGateEpochs.removeAll(keepingCapacity: true)
        activeSourceGateEpoch = nil
        fallbackCount = 0
        lastFallbackReason = nil
        consecutiveSourceAlignmentUnavailableFrameCount = 0
        consecutiveSourceUncertainFrameCount = 0
        pendingSourceGateReset = false
        sourceAlignmentMissCount = 0
        sourceAlignmentReacquisitionCount = 0
    }

    private func resetTimingState(
        closeReason: MacSpeechSourceGateCloseReason? = nil
    ) {
        clearTimingHistory()
        delayMilliseconds = 0
        presentationDelayMilliseconds = 0
        alignedDelayMilliseconds = nil
        resetSignalDiagnostics()
        resetResidualEchoBaseline()
        resetSourceGate(closeReason: closeReason)
    }

    private func resetResidualEchoBaseline() {
        rawEchoGainBaseline = 0
        residualEchoGainBaseline = 0
        linearAECOutputGainBaseline = 0
        residualEchoBaselineFrameCount = 0
        residualEchoBaselineFrozen = false
    }

    private func disabledStats() -> MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(
            enabled: false,
            active: false,
            estimatedDelayMilliseconds: 0,
            erlDecibels: 0,
            erleDecibels: 0
        )
    }

    private func makeSnapshot() -> MacSpeechAcousticEchoSnapshot {
        MacSpeechAcousticEchoSnapshot(
            mode: mode,
            enabled: backendStats.enabled,
            active: backendStats.active,
            sampleRate: Self.sampleRate,
            renderFrameCount: renderFrameCount,
            captureFrameCount: captureFrameCount,
            delayMilliseconds: delayMilliseconds,
            aecBufferDelayMilliseconds: delayMilliseconds,
            estimatedDelayMilliseconds:
                backendStats.estimatedDelayMilliseconds,
            erlDecibels: backendStats.erlDecibels,
            erleDecibels: backendStats.erleDecibels,
            renderFIFOSampleCount: renderFIFO.count,
            captureFIFOSampleCount: captureFIFO.count,
            renderCaptureSkewFrames:
                Int64(renderFrameCount) - Int64(captureFrameCount),
            driftTrend: driftTrend,
            presentationDelayMilliseconds: presentationDelayMilliseconds,
            alignedDelayMilliseconds: roundedSourceAlignmentDelay,
            sourceAlignmentDelayMilliseconds:
                roundedSourceAlignmentDelay,
            renderTimingFrameCount: renderTimingHistory.count,
            rawCaptureRMS: rawCaptureRMS,
            processedCaptureRMS: processedCaptureRMS,
            renderCaptureCorrelation: renderCaptureCorrelation,
            residualRenderCorrelation: residualRenderCorrelation,
            linearAECOutputRMS: linearAECOutputRMS,
            linearRenderCorrelation: linearRenderCorrelation,
            processedLinearCorrelation: processedLinearCorrelation,
            inputClassification: inputClassification,
            sourceGateOpen: sourceGateOpen,
            sourceGatePreRollFrameCount: sourceGatePreRoll.count,
            echoOnlyFrameCount: echoOnlyFrameCount,
            nearEndSpeechFrameCount: nearEndSpeechFrameCount,
            doubleTalkFrameCount: doubleTalkFrameCount,
            uncertainFrameCount: uncertainFrameCount,
            sourceForwardedFrameCount: sourceForwardedFrameCount,
            sourceSuppressedFrameCount: sourceSuppressedFrameCount,
            sourceTimingCandidateFrameCount: sourceTimingCandidateFrameCount,
            sourceTimingUnavailableFrameCount:
                sourceTimingUnavailableFrameCount,
            sourceGateOpenCount: sourceGateOpenCount,
            sourceGateCloseCount: sourceGateCloseCount,
            maximumSourceGateOpenFrameCount:
                maximumSourceGateOpenFrameCount,
            maximumContinuousSourceForwardedFrameCount:
                maximumContinuousSourceForwardedFrameCount,
            rawEchoGainBaseline: rawEchoGainBaseline,
            residualEchoGainBaseline: residualEchoGainBaseline,
            linearAECOutputGainBaseline: linearAECOutputGainBaseline,
            residualEchoBaselineFrameCount:
                residualEchoBaselineFrameCount,
            residualEchoBaselineFrozen: residualEchoBaselineFrozen,
            residualEchoBaselineUpdateCount:
                residualEchoBaselineUpdateCount,
            residualEchoBaselineFreezeCount:
                residualEchoBaselineFreezeCount,
            adaptiveEvidenceCandidateFrameCount:
                adaptiveEvidenceCandidateFrameCount,
            adaptiveDoubleTalkFrameCount: adaptiveDoubleTalkFrameCount,
            maximumAdaptiveRawExcessRMS:
                maximumAdaptiveRawExcessRMS,
            maximumAdaptiveResidualExcessRMS:
                maximumAdaptiveResidualExcessRMS,
            maximumAdaptiveLinearExcessRMS:
                maximumAdaptiveLinearExcessRMS,
            renderCaptureIsolationEstablished:
                renderCaptureIsolationEstablished,
            renderCaptureIsolationQuietFrameCount:
                renderCaptureIsolationQuietFrameCount,
            renderCaptureIsolationEstablishmentCount:
                renderCaptureIsolationEstablishmentCount,
            renderCaptureIsolationRevocationCount:
                renderCaptureIsolationRevocationCount,
            sourceAlignmentLocked:
                timingLockedDelayMilliseconds != nil,
            sourceAlignmentAcquisitionFrameCount:
                timingLockCandidateFrameCount,
            sourceAlignmentMissCount: sourceAlignmentMissCount,
            sourceAlignmentReacquisitionCount:
                sourceAlignmentReacquisitionCount,
            lastSourceGateCloseReason: lastSourceGateCloseReason,
            sourceGateEpochs: sourceGateEpochDiagnostics(),
            fallbackCount: fallbackCount,
            lastFallbackReason: lastFallbackReason,
            routeResetCount: routeResetCount,
            fallbackReason: fallbackReason,
            isPlaybackActive: isPlaybackActive
        )
    }

    private func makeAcousticObservationSnapshot(
        captureFrameIndex: UInt64? = nil
    )
        -> MacSpeechAcousticObservationSnapshot {
        let observationFrameIndex = captureFrameIndex
            ?? self.captureFrameCount
        let causalLastAudibleRenderHostTimeNanoseconds: UInt64?
        if let lastAudibleRenderHostTimeNanoseconds,
           let latestCaptureHostTimeNanoseconds {
            causalLastAudibleRenderHostTimeNanoseconds = min(
                lastAudibleRenderHostTimeNanoseconds,
                latestCaptureHostTimeNanoseconds
            )
        } else {
            causalLastAudibleRenderHostTimeNanoseconds =
                lastAudibleRenderHostTimeNanoseconds
        }
        return MacSpeechAcousticObservationSnapshot(
            captureFrameIndex: observationFrameIndex,
            captureHostTimeNanoseconds:
                latestCaptureHostTimeNanoseconds,
            playbackSequence: playbackSequence,
            isPlaybackActive: isPlaybackActive,
            lastAudibleRenderHostTimeNanoseconds:
                causalLastAudibleRenderHostTimeNanoseconds,
            renderReferenceAvailable:
                latestRenderHostTimeNanoseconds != nil,
            renderReferenceRMS: matchedRenderHostTimeNanoseconds == nil
                ? latestRenderReferenceRMS : matchedRenderReferenceRMS,
            renderHostTimeNanoseconds:
                matchedRenderHostTimeNanoseconds,
            rawCaptureRMS: rawCaptureRMS,
            processedCaptureRMS: processedCaptureRMS,
            linearAECOutputRMS: linearAECOutputRMS,
            renderCaptureCorrelation: renderCaptureCorrelation,
            residualRenderCorrelation: residualRenderCorrelation,
            linearRenderCorrelation: linearRenderCorrelation,
            inputClassification: inputClassification,
            sourceGateOpen: sourceGateOpen,
            sourceGateEpoch: sourceGateEpochSequence,
            aecEnabled: backendStats.enabled,
            aecActive: backendStats.active,
            renderCaptureIsolationEstablished:
                renderCaptureIsolationEstablished,
            sourceAlignmentLocked:
                timingLockedDelayMilliseconds != nil,
            sourceAlignmentDelayMilliseconds:
                roundedSourceAlignmentDelay,
            estimatedDelayMilliseconds:
                backendStats.estimatedDelayMilliseconds,
            erlDecibels: backendStats.erlDecibels,
            erleDecibels: backendStats.erleDecibels,
            renderCaptureSkewFrames:
                Int64(renderFrameCount) - Int64(observationFrameIndex),
            driftTrend: driftTrend
        )
    }

    private func logConfiguration() {
        logger.notice(
            "AEC configured mode=\(self.mode.rawValue, privacy: .public) enabled=\(self.backendStats.enabled, privacy: .public) sample_rate=\(Self.sampleRate, privacy: .public) frame_samples=\(Self.frameSampleCount, privacy: .public)"
        )
    }
}
