import Foundation

nonisolated struct MacSpeechRealtimeBrainInputBinding: Sendable, Equatable {
    let session: RealtimeBrainSessionIdentity
    let captureGeneration: UInt64
}

nonisolated struct MacSpeechRealtimeBrainInputActivity:
    Sendable,
    Equatable {
    let localActivity: RealtimeBrainLocalAudioActivity
}

nonisolated struct MacSpeechRealtimeBrainAcousticObservation:
    Sendable,
    Equatable {
    let observation: RealtimeAcousticObservation
    let facts: RealtimeInterruptionAcousticFacts

    var session: RealtimeBrainSessionIdentity {
        observation.identity.session
    }

    var captureGeneration: UInt64 {
        observation.identity.captureGeneration
    }

    var playbackSequence: UInt64 {
        observation.metrics.residentPlaybackSequence
    }

    var sourceGateEpoch: UInt64 {
        observation.metrics.sourceGateEpoch
    }

    var sequence: UInt64 { observation.identity.sequence }

    var timestampNanoseconds: UInt64 {
        observation.identity.timestampNanoseconds
    }

    func matchesCurrentPlayback(
        _ snapshot: MacSpeechResidentAcousticSnapshot
    ) -> Bool {
        snapshot.captureGeneration == captureGeneration
            && snapshot.playbackSequence == playbackSequence
            && snapshot.residentPlaybackActive
            && snapshot.sourceGateEpoch == sourceGateEpoch
            && snapshot.routeStable
            && snapshot.inputDeviceAvailable
            && snapshot.outputDeviceAvailable
    }
}

nonisolated struct MacSpeechRealtimeBrainAcousticDiagnostic: Sendable {
    let category: String
    let disposition: String
    let turnGeneration: UInt64
    let observationSequence: UInt64
    let sourceGateEpoch: UInt64
    let timestampNanoseconds: UInt64
    let packetTrace: MacSpeechRealtimeBrainAcousticPacketTrace?

    init(
        category: String,
        disposition: String,
        turnGeneration: UInt64,
        observationSequence: UInt64,
        sourceGateEpoch: UInt64,
        timestampNanoseconds: UInt64,
        packetTrace: MacSpeechRealtimeBrainAcousticPacketTrace? = nil
    ) {
        self.category = category
        self.disposition = disposition
        self.turnGeneration = turnGeneration
        self.observationSequence = observationSequence
        self.sourceGateEpoch = sourceGateEpoch
        self.timestampNanoseconds = timestampNanoseconds
        self.packetTrace = packetTrace
    }
}

nonisolated struct MacSpeechRealtimeBrainAcousticPacketTrace:
    Sendable,
    Equatable {
    let packetSequence: UInt64
    let captureFrameIndex: UInt64?
    let observationSequence: UInt64?
    let observationTimestampNanoseconds: UInt64?
    let playbackSequence: UInt64
    let sourceGateEpoch: UInt64
    let sourceAssessment: String?
    let classification: String?
    let captureTimestampNanoseconds: UInt64?
    let lastAudibleRenderTimestampNanoseconds: UInt64?
    let gateLastSequence: UInt64?
    let gateLastTimestampNanoseconds: UInt64?
    let gateLastPlaybackSequence: UInt64?
    let gateLastAudibleRenderTimestampNanoseconds: UInt64?
}

nonisolated enum MacSpeechRealtimeBrainInputBridgeState: String, Sendable, Equatable {
    case idle
    case running
    case stopped
    case failed
}

nonisolated struct MacSpeechRealtimeBrainInputBridgeSnapshot: Sendable, Equatable {
    let state: MacSpeechRealtimeBrainInputBridgeState
    let sessionShortID: String?
    let forwardedFrameCount: UInt64
    let residentAcousticObservationCount: UInt64
    let rejectedResidentAcousticObservationCount: UInt64
    let droppedResidentAcousticObservationCount: UInt64
    let acousticEvidenceCount: UInt64
    let acousticEligibilityCandidateCount: UInt64
    let acousticEligibilityRearmedCount: UInt64
    let acousticEvidenceStaleFenceCount: UInt64
    let acousticEligibilityDispositionCounts: [String: UInt64]
    let acousticEvidenceForwardDispositionCounts: [String: UInt64]
    let runtimeRejectedFrameCount: UInt64
    let sendOperationCount: UInt64
    let noneActivityFrameCount: UInt64
    let listeningNearEndFrameCount: UInt64
    let sourceGatedNearEndFrameCount: UInt64
    let listeningConfirmationAttemptCount: UInt64
    let listeningConfirmationAcceptedCount: UInt64
    let listeningConfirmationRejectedCount: UInt64
    let listeningFreshnessRejectedCount: UInt64
    let averageSendDurationMilliseconds: UInt64
    let maximumSendDurationMilliseconds: UInt64
    let lastAcousticEligibilityDisposition: String?
    let lastAcousticEvidenceForwardDisposition: String?
    let lastError: String?
    let hasActivePump: Bool
    let hasPendingResidentAcousticObservation: Bool

    static let initial = MacSpeechRealtimeBrainInputBridgeSnapshot(
        state: .idle,
        sessionShortID: nil,
        forwardedFrameCount: 0,
        residentAcousticObservationCount: 0,
        rejectedResidentAcousticObservationCount: 0,
        droppedResidentAcousticObservationCount: 0,
        acousticEvidenceCount: 0,
        acousticEligibilityCandidateCount: 0,
        acousticEligibilityRearmedCount: 0,
        acousticEvidenceStaleFenceCount: 0,
        acousticEligibilityDispositionCounts: [:],
        acousticEvidenceForwardDispositionCounts: [:],
        runtimeRejectedFrameCount: 0,
        sendOperationCount: 0,
        noneActivityFrameCount: 0,
        listeningNearEndFrameCount: 0,
        sourceGatedNearEndFrameCount: 0,
        listeningConfirmationAttemptCount: 0,
        listeningConfirmationAcceptedCount: 0,
        listeningConfirmationRejectedCount: 0,
        listeningFreshnessRejectedCount: 0,
        averageSendDurationMilliseconds: 0,
        maximumSendDurationMilliseconds: 0,
        lastAcousticEligibilityDisposition: nil,
        lastAcousticEvidenceForwardDisposition: nil,
        lastError: nil,
        hasActivePump: false,
        hasPendingResidentAcousticObservation: false
    )
}

nonisolated struct MacSpeechRealtimeBrainInputStopOutcome: Sendable {
    let snapshot: MacSpeechRealtimeBrainInputBridgeSnapshot
    let closeResult: Result<Void, RealtimeResidentBrainError>?
}

private struct MacSpeechCausalProvisionalEpisode: Sendable {
    let id: UUID
    let binding: MacSpeechRealtimeBrainInputBinding
    let playbackSequence: UInt64
    let deadlineNanoseconds: UInt64
    let preYieldRenderFrame: MacSpeechCausalFrameObservation
}

actor MacSpeechRealtimeBrainInputBridge {
    typealias SendFrame = @Sendable (
        RealtimeBrainAudioFrame
    ) async -> Result<Void, RealtimeResidentBrainError>

    typealias SendFrameWithActivity = @Sendable (
        RealtimeBrainAudioFrame,
        MacSpeechRealtimeBrainInputActivity
    ) async -> Result<Void, RealtimeResidentBrainError>

    typealias ConfirmAcceptedLocalActivity = @Sendable (
        RealtimeBrainAudioFrame,
        MacSpeechRealtimeBrainInputActivity
    ) async -> Result<Void, RealtimeResidentBrainError>

    typealias StopInput = @MainActor @Sendable (
        MacSpeechRealtimeBrainInputBinding
    ) async -> Result<Void, RealtimeResidentBrainError>

    typealias ConsumeAcousticObservation = @MainActor @Sendable (
        MacSpeechRealtimeBrainAcousticObservation
    ) async -> Void

    typealias ObserveResidentAcoustics = @MainActor @Sendable (
        RealtimeAcousticObservation
    ) async -> RealtimeAcousticObservationDisposition

    typealias RecordAcousticDiagnostic = @MainActor @Sendable (
        MacSpeechRealtimeBrainAcousticDiagnostic
    ) -> Void

    typealias BeginCausalProvisional = @MainActor @Sendable (
        UUID,
        MacSpeechRealtimeBrainInputBinding,
        UInt64
    ) async -> Bool

    typealias RecoverCausalProvisional = @MainActor @Sendable (
        UUID,
        MacSpeechRealtimeBrainInputBinding
    ) async -> Void

    typealias DiscardCausalEvidence = @MainActor @Sendable (
        MacSpeechRealtimeBrainInputBinding
    ) async -> Void

    typealias MonotonicNow = @Sendable () -> UInt64

    private let source: any MacSpeechAudioFrameSourcing
    private let sendFrame: SendFrameWithActivity
    private let confirmAcceptedLocalActivity:
        ConfirmAcceptedLocalActivity?
    private let stopInput: StopInput
    private let observeResidentAcoustics: ObserveResidentAcoustics?
    private let consumeAcousticObservation: ConsumeAcousticObservation?
    private let recordAcousticDiagnostic: RecordAcousticDiagnostic?
    private let beginCausalProvisional: BeginCausalProvisional?
    private let recoverCausalProvisional: RecoverCausalProvisional?
    private let discardCausalEvidence: DiscardCausalEvidence?
    private let monotonicNow: MonotonicNow
    private var pumpTask: Task<Void, Never>?
    private var activePumpID: UUID?
    private var activeBinding: MacSpeechRealtimeBrainInputBinding?
    private var suspendedBinding: MacSpeechRealtimeBrainInputBinding?
    private var suspendedPumpID: UUID?
    private var retainedCapture: [MacSpeechAudioFrame] = []
    private var lastSubmittedCaptureSequence: UInt64 = 0
    private var lastSubmittedCaptureTimestamp: UInt64 = 0
    private var retainedCaptureExpectedSession: RealtimeBrainSessionIdentity?
    private var retainedCaptureAmbiguous = false
    private var enforceCaptureContinuity = false
    private var generationTransitionID: UUID?
    private var pendingCloseBinding: MacSpeechRealtimeBrainInputBinding?
    private var closeTask:
        Task<Result<Void, RealtimeResidentBrainError>, Never>?
    private var closeAttemptID: UUID?
    private var state = MacSpeechRealtimeBrainInputBridgeState.idle
    private var forwardedFrameCount: UInt64 = 0
    private var residentAcousticObservationCount: UInt64 = 0
    private var rejectedResidentAcousticObservationCount: UInt64 = 0
    private var droppedResidentAcousticObservationCount: UInt64 = 0
    private var acousticEvidenceCount: UInt64 = 0
    private var acousticEligibilityCandidateCount: UInt64 = 0
    private var acousticEligibilityRearmedCount: UInt64 = 0
    private var acousticEvidenceStaleFenceCount: UInt64 = 0
    private var acousticEligibilityDispositionCounts: [String: UInt64] = [:]
    private var acousticEvidenceForwardDispositionCounts: [String: UInt64] = [:]
    private var runtimeRejectedFrameCount: UInt64 = 0
    private var sendOperationCount: UInt64 = 0
    private var noneActivityFrameCount: UInt64 = 0
    private var listeningNearEndFrameCount: UInt64 = 0
    private var sourceGatedNearEndFrameCount: UInt64 = 0
    private var listeningConfirmationAttemptCount: UInt64 = 0
    private var listeningConfirmationAcceptedCount: UInt64 = 0
    private var listeningConfirmationRejectedCount: UInt64 = 0
    private var listeningFreshnessRejectedCount: UInt64 = 0
    private var totalSendDurationMilliseconds: UInt64 = 0
    private var maximumSendDurationMilliseconds: UInt64 = 0
    private var nextSubmittedSequence: UInt64 = 1
    private var nextResidentAcousticObservationSequence: UInt64 = 1
    private var nextResidentAcousticSnapshotPollNanoseconds: UInt64 = 0
    private var lastResidentCaptureFrameIndex: UInt64 = 0
    private var lastObserverOnlyResidentCaptureFrameIndex: UInt64 = 0
    private var lastResidentObservationFrameIndex: UInt64 = 0
    private var residentAcousticObservationTask: Task<Void, Never>?
    private var residentAcousticObservationTaskID: UUID?
    private var acousticEligibilityGate:
        RealtimeAcousticInterruptionEligibilityGate?
    private var pendingEligibleAcousticObservation:
        RealtimeAcousticObservation?
    private var pendingEligibilitySourceGateEpoch: UInt64?
    private var pendingEligibilityGateBeforeIssue:
        RealtimeAcousticInterruptionEligibilityGate?
    private var acousticEligibilityForwarded = false
    private var lastAcousticEligibilityDisposition: String?
    private var lastAcousticEvidenceForwardDisposition: String?
    private var lastError: String?
    private var causalEpisode: MacSpeechCausalProvisionalEpisode?
    private var causalCandidateConsumedPlaybackSequence: UInt64?
    private static let causalActivityRMS = 0.012
    private static let causalFarEndPowerRatioMaximum = 0.25
    private static let causalEvidenceDeadlineNanoseconds: UInt64 =
        1_000_000_000

    init(
        source: any MacSpeechAudioFrameSourcing,
        sendFrame: @escaping SendFrame,
        stopInput: @escaping StopInput,
        observeResidentAcoustics: ObserveResidentAcoustics? = nil,
        consumeAcousticObservation: ConsumeAcousticObservation? = nil,
        recordAcousticDiagnostic: RecordAcousticDiagnostic? = nil,
        beginCausalProvisional: BeginCausalProvisional? = nil,
        recoverCausalProvisional: RecoverCausalProvisional? = nil,
        discardCausalEvidence: DiscardCausalEvidence? = nil,
        monotonicNow: @escaping MonotonicNow = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.source = source
        self.sendFrame = { frame, _ in
            await sendFrame(frame)
        }
        confirmAcceptedLocalActivity = nil
        self.stopInput = stopInput
        self.observeResidentAcoustics = observeResidentAcoustics
        self.consumeAcousticObservation = consumeAcousticObservation
        self.recordAcousticDiagnostic = recordAcousticDiagnostic
        self.beginCausalProvisional = beginCausalProvisional
        self.recoverCausalProvisional = recoverCausalProvisional
        self.discardCausalEvidence = discardCausalEvidence
        self.monotonicNow = monotonicNow
    }

    init(
        source: any MacSpeechAudioFrameSourcing,
        sendFrameWithActivity: @escaping SendFrameWithActivity,
        confirmAcceptedLocalActivity:
            ConfirmAcceptedLocalActivity? = nil,
        stopInput: @escaping StopInput,
        observeResidentAcoustics: ObserveResidentAcoustics? = nil,
        consumeAcousticObservation: ConsumeAcousticObservation? = nil,
        recordAcousticDiagnostic: RecordAcousticDiagnostic? = nil,
        beginCausalProvisional: BeginCausalProvisional? = nil,
        recoverCausalProvisional: RecoverCausalProvisional? = nil,
        discardCausalEvidence: DiscardCausalEvidence? = nil,
        monotonicNow: @escaping MonotonicNow = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.source = source
        self.sendFrame = sendFrameWithActivity
        self.confirmAcceptedLocalActivity = confirmAcceptedLocalActivity
        self.stopInput = stopInput
        self.observeResidentAcoustics = observeResidentAcoustics
        self.consumeAcousticObservation = consumeAcousticObservation
        self.recordAcousticDiagnostic = recordAcousticDiagnostic
        self.beginCausalProvisional = beginCausalProvisional
        self.recoverCausalProvisional = recoverCausalProvisional
        self.discardCausalEvidence = discardCausalEvidence
        self.monotonicNow = monotonicNow
    }

    func start(
        binding: MacSpeechRealtimeBrainInputBinding
    ) -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        guard activeBinding == nil,
              suspendedBinding == nil,
              pendingCloseBinding == nil else {
            return makeSnapshot()
        }
        activeBinding = binding
        state = .running
        forwardedFrameCount = 0
        residentAcousticObservationCount = 0
        rejectedResidentAcousticObservationCount = 0
        droppedResidentAcousticObservationCount = 0
        acousticEvidenceCount = 0
        acousticEligibilityCandidateCount = 0
        acousticEligibilityRearmedCount = 0
        acousticEvidenceStaleFenceCount = 0
        acousticEligibilityDispositionCounts.removeAll(keepingCapacity: true)
        acousticEvidenceForwardDispositionCounts.removeAll(keepingCapacity: true)
        lastAcousticEligibilityDisposition = nil
        lastAcousticEvidenceForwardDisposition = nil
        runtimeRejectedFrameCount = 0
        sendOperationCount = 0
        noneActivityFrameCount = 0
        listeningNearEndFrameCount = 0
        sourceGatedNearEndFrameCount = 0
        listeningConfirmationAttemptCount = 0
        listeningConfirmationAcceptedCount = 0
        listeningConfirmationRejectedCount = 0
        listeningFreshnessRejectedCount = 0
        totalSendDurationMilliseconds = 0
        maximumSendDurationMilliseconds = 0
        nextSubmittedSequence = 1
        suspendedPumpID = nil
        retainedCapture.removeAll(keepingCapacity: true)
        lastSubmittedCaptureSequence = 0
        lastSubmittedCaptureTimestamp = 0
        retainedCaptureExpectedSession = nil
        retainedCaptureAmbiguous = false
        enforceCaptureContinuity = false
        causalEpisode = nil
        causalCandidateConsumedPlaybackSequence = nil
        resetResidentAcousticObservationState(binding: binding)
        lastError = nil
        let pumpID = UUID()
        activePumpID = pumpID
        pumpTask = Task { [weak self] in
            await self?.run(binding: binding, pumpID: pumpID)
        }
        return makeSnapshot()
    }

    func suspendForGenerationTransition(
        session: RealtimeBrainSessionIdentity,
        preserving decision: RealtimeConfirmedInterruption? = nil
    ) async -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        if let decision,
           decision.interruptedIdentity != session {
            return makeSnapshot()
        }
        guard let binding = activeBinding,
              binding.session == session,
              suspendedBinding == nil else { return makeSnapshot() }
        let retiringPump = pumpTask
        suspendedPumpID = activePumpID
        retainedCaptureExpectedSession = decision?.nextIdentity
        retainedCaptureAmbiguous = false
        pumpTask?.cancel()
        pumpTask = nil
        activePumpID = nil
        activeBinding = nil
        suspendedBinding = binding
        generationTransitionID = UUID()
        causalEpisode = nil
        resetResidentAcousticObservationState()
        state = .stopped
        await retiringPump?.value
        return makeSnapshot()
    }

    func resumeAfterGenerationTransition(
        session: RealtimeBrainSessionIdentity
    ) async -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        guard let previous = suspendedBinding,
              let transitionID = generationTransitionID,
              activeBinding == nil,
              Self.isNextGeneration(session, after: previous.session) else {
            state = .failed
            lastError = "invalid_identity"
            return makeSnapshot()
        }
        let keepsCapture = retainedCaptureExpectedSession == session
        if keepsCapture {
            let captureActive = await source.isCaptureGenerationActive(
                previous.captureGeneration
            )
            let observedRoute = await source.residentAcousticSnapshot()
            guard suspendedBinding == previous,
                  generationTransitionID == transitionID else {
                return makeSnapshot()
            }
            guard !retainedCaptureAmbiguous,
                  captureActive,
                  let observedRoute,
                  observedRoute.captureGeneration
                    == previous.captureGeneration,
                  observedRoute.routeStable,
                  observedRoute.inputDeviceAvailable,
                  observedRoute.outputDeviceAvailable else {
                state = .failed
                generationTransitionID = nil
                retainedCapture.removeAll()
                lastError = "capture_handoff_invalid"
                return makeSnapshot()
            }
            let pendingFrames = await source.drainFrames(
                maxCount: MacSpeechAudioInputFormat.frameCapacity
            )
            guard suspendedBinding == previous,
                  generationTransitionID == transitionID else {
                return makeSnapshot()
            }
            retainedCapture.append(contentsOf: pendingFrames)
            var sequence = lastSubmittedCaptureSequence
            var timestamp = lastSubmittedCaptureTimestamp
            guard retainedCapture.count
                    <= MacSpeechAudioInputFormat.frameCapacity,
                  retainedCapture.allSatisfy({ frame in
                      defer {
                          sequence = frame.sequenceNumber
                          timestamp = frame.monotonicTimestampNanoseconds
                      }
                      return frame.captureGeneration
                            == previous.captureGeneration
                          && frame.sequenceNumber == sequence &+ 1
                          && frame.monotonicTimestampNanoseconds >= timestamp
                  }) else {
                state = .failed
                generationTransitionID = nil
                retainedCapture.removeAll()
                lastError = "capture_handoff_gap"
                return makeSnapshot()
            }
        } else {
            retainedCapture.removeAll()
            await source.discardPendingAudioForGenerationTransition()
            _ = await source.drainFrames(
                maxCount: MacSpeechAudioInputFormat.frameCapacity
            )
        }
        guard suspendedBinding == previous,
              generationTransitionID == transitionID else {
            return makeSnapshot()
        }
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: previous.captureGeneration
        )
        suspendedBinding = nil
        suspendedPumpID = nil
        generationTransitionID = nil
        activeBinding = binding
        nextSubmittedSequence = 1
        retainedCaptureExpectedSession = nil
        causalEpisode = nil
        causalCandidateConsumedPlaybackSequence = nil
        enforceCaptureContinuity = keepsCapture
        resetResidentAcousticObservationState(binding: binding)
        state = .running
        lastError = nil
        let pumpID = UUID()
        activePumpID = pumpID
        pumpTask = Task { [weak self] in
            await self?.run(binding: binding, pumpID: pumpID)
        }
        return makeSnapshot()
    }

    func stop(
        expectedSession: RealtimeBrainSessionIdentity? = nil
    ) async -> MacSpeechRealtimeBrainInputStopOutcome {
        guard let binding = activeBinding
                ?? suspendedBinding
                ?? pendingCloseBinding,
              expectedSession == nil || expectedSession == binding.session else {
            if activeBinding == nil,
               suspendedBinding == nil,
               pendingCloseBinding == nil,
               state != .failed {
                state = .stopped
            }
            return MacSpeechRealtimeBrainInputStopOutcome(
                snapshot: makeSnapshot(),
                closeResult: nil
            )
        }
        let task = pumpTask
        pumpTask = nil
        activePumpID = nil
        task?.cancel()
        activeBinding = nil
        suspendedBinding = nil
        suspendedPumpID = nil
        generationTransitionID = nil
        retainedCapture.removeAll()
        retainedCaptureExpectedSession = nil
        retainedCaptureAmbiguous = false
        enforceCaptureContinuity = false
        state = .stopped
        causalEpisode = nil
        causalCandidateConsumedPlaybackSequence = nil
        resetResidentAcousticObservationState()
        let closeResult = await close(binding: binding)
        switch closeResult {
        case .success:
            lastError = nil
        case .failure(let error):
            state = .failed
            lastError = Self.standardErrorName(error)
        }
        return MacSpeechRealtimeBrainInputStopOutcome(
            snapshot: makeSnapshot(),
            closeResult: closeResult
        )
    }

    func stopForwarding(
        expectedSession: RealtimeBrainSessionIdentity? = nil
    ) -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        let binding = activeBinding ?? suspendedBinding ?? pendingCloseBinding
        guard expectedSession == nil || expectedSession == binding?.session else {
            return makeSnapshot()
        }
        pumpTask?.cancel()
        pumpTask = nil
        activePumpID = nil
        activeBinding = nil
        suspendedBinding = nil
        suspendedPumpID = nil
        generationTransitionID = nil
        retainedCapture.removeAll()
        retainedCaptureExpectedSession = nil
        retainedCaptureAmbiguous = false
        enforceCaptureContinuity = false
        causalEpisode = nil
        causalCandidateConsumedPlaybackSequence = nil
        resetResidentAcousticObservationState()
        if state != .failed { state = .stopped }
        return makeSnapshot()
    }

    private func ownsCaptureCompletion(
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID
    ) -> Bool {
        (activeBinding == binding && activePumpID == pumpID)
            || (suspendedBinding == binding
                && suspendedPumpID == pumpID
                && generationTransitionID != nil)
    }

    func currentSnapshot() -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        makeSnapshot()
    }

    func fail(
        _ error: Error
    ) -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        guard activeBinding == nil,
              suspendedBinding == nil,
              pendingCloseBinding == nil else {
            return makeSnapshot()
        }
        state = .failed
        lastError = Self.standardErrorName(error)
        return makeSnapshot()
    }

    func settleExternalCloseSuccess(
        session: RealtimeBrainSessionIdentity?
    )
        -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        guard activeBinding == nil,
              suspendedBinding == nil else {
            return makeSnapshot()
        }
        if let pendingCloseBinding {
            guard let session,
                  pendingCloseBinding.session == session else {
                return makeSnapshot()
            }
            self.pendingCloseBinding = nil
            closeTask = nil
            closeAttemptID = nil
        }
        state = .stopped
        lastError = nil
        return makeSnapshot()
    }

    private func run(
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID
    ) async {
        while !Task.isCancelled {
            guard await source.isCaptureGenerationActive(
                binding.captureGeneration
            ) else {
                await finish(
                    binding: binding,
                    pumpID: pumpID,
                    state: .stopped,
                    error: nil
                )
                return
            }

            if retainedCapture.isEmpty {
                let drained = await source.drainFrames(
                    maxCount: MacSpeechAudioInputFormat.frameCapacity
                )
                guard ownsCaptureCompletion(
                    binding: binding,
                    pumpID: pumpID
                ) else { return }
                retainedCapture.append(contentsOf: drained)
            }
            if retainedCapture.isEmpty {
                await advanceCausalProvisionalIfNeeded(
                    binding: binding,
                    pumpID: pumpID
                )
                await observeResidentAcousticsIfNeeded(
                    fallbackTimestampNanoseconds:
                        DispatchTime.now().uptimeNanoseconds,
                    capturedAcousticSnapshot: nil,
                    observerOnly: true,
                    binding: binding,
                    pumpID: pumpID
                )
                try? await Task.sleep(for: .milliseconds(5))
                continue
            }

            while let frame = retainedCapture.first {
                guard !Task.isCancelled,
                      activeBinding == binding,
                      activePumpID == pumpID else { return }
                guard frame.captureGeneration == binding.captureGeneration else {
                    retainedCapture.removeFirst()
                    runtimeRejectedFrameCount &+= 1
                    continue
                }
                if enforceCaptureContinuity,
                   frame.sequenceNumber != lastSubmittedCaptureSequence &+ 1
                    || frame.monotonicTimestampNanoseconds
                        < lastSubmittedCaptureTimestamp {
                    await finish(
                        binding: binding,
                        pumpID: pumpID,
                        state: .failed,
                        error: RealtimeResidentBrainError.invalidAudioFrame
                    )
                    return
                }

                await advanceCausalProvisionalIfNeeded(
                    binding: binding,
                    pumpID: pumpID
                )
                if causalEpisode == nil,
                   frame.residentPlaybackActive,
                   frame.activity >= Float(Self.causalActivityRMS) {
                    _ = await beginCausalProvisionalIfSupported(
                        binding: binding,
                        requiresNearEndSupport: true
                    )
                }

                let realtimeFrame = RealtimeBrainAudioFrame(
                    identity: binding.session,
                    sequence: nextSubmittedSequence,
                    timestampNanoseconds: frame.monotonicTimestampNanoseconds,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: Int(MacSpeechAudioInputFormat.sampleRate),
                        channelCount: Int(MacSpeechAudioInputFormat.channelCount)
                    ),
                    provenance: .acousticEchoProcessed,
                    bytes: frame.pcm16Bytes
                )
                let inputActivity = await makeInputActivity(
                    for: frame,
                    binding: binding
                )
                switch inputActivity.localActivity.kind {
                case .none:
                    noneActivityFrameCount &+= 1
                case .listeningNearEnd:
                    listeningNearEndFrameCount &+= 1
                case .sourceGatedNearEnd:
                    sourceGatedNearEndFrameCount &+= 1
                }
                let sourceGatedPacketTrace =
                    inputActivity.localActivity.kind == .sourceGatedNearEnd
                        && recordAcousticDiagnostic != nil
                    ? MacSpeechRealtimeBrainAcousticPacketTrace(
                        packetSequence: frame.sequenceNumber,
                        captureFrameIndex:
                            frame.acousticSnapshot?.captureFrameIndex,
                        observationSequence: nil,
                        observationTimestampNanoseconds:
                            frame.acousticSnapshot?
                                .captureHostTimeNanoseconds
                                ?? frame.monotonicTimestampNanoseconds,
                        playbackSequence:
                            frame.residentPlaybackSequence,
                        sourceGateEpoch: frame.sourceGateEpoch,
                        sourceAssessment:
                            frame.acousticSnapshot?
                                .inputClassification.rawValue,
                        classification: nil,
                        captureTimestampNanoseconds:
                            frame.acousticSnapshot?
                                .captureHostTimeNanoseconds,
                        lastAudibleRenderTimestampNanoseconds:
                            frame.acousticSnapshot?
                                .lastAudibleRenderHostTimeNanoseconds,
                        gateLastSequence: nil,
                        gateLastTimestampNanoseconds: nil,
                        gateLastPlaybackSequence: nil,
                        gateLastAudibleRenderTimestampNanoseconds: nil
                    ) : nil
                await observeResidentAcousticsIfNeeded(
                    fallbackTimestampNanoseconds:
                        realtimeFrame.timestampNanoseconds,
                    capturedAcousticSnapshot: frame.acousticSnapshot,
                    observerOnly: false,
                    sourceGatedPacketTrace: sourceGatedPacketTrace,
                    binding: binding,
                    pumpID: pumpID
                )
                guard !Task.isCancelled,
                      activeBinding == binding,
                      activePumpID == pumpID else { return }
                retainedCapture.removeFirst()
                let sendStartedAt = DispatchTime.now().uptimeNanoseconds
                let result = await sendFrame(
                    realtimeFrame,
                    inputActivity
                )
                let sendDuration = (
                    DispatchTime.now().uptimeNanoseconds &- sendStartedAt
                ) / 1_000_000
                guard ownsCaptureCompletion(
                    binding: binding,
                    pumpID: pumpID
                ) else { return }
                if case .success = result {
                    lastSubmittedCaptureSequence = frame.sequenceNumber
                    lastSubmittedCaptureTimestamp =
                        frame.monotonicTimestampNanoseconds
                } else if suspendedBinding == binding,
                          retainedCaptureExpectedSession != nil {
                    retainedCaptureAmbiguous = true
                }
                guard activeBinding == binding,
                      activePumpID == pumpID else { return }
                sendOperationCount &+= 1
                totalSendDurationMilliseconds &+= sendDuration
                maximumSendDurationMilliseconds = max(
                    maximumSendDurationMilliseconds,
                    sendDuration
                )
                switch result {
                case .success:
                    await confirmListeningActivityIfCurrent(
                        realtimeFrame: realtimeFrame,
                        captureFrame: frame,
                        activity: inputActivity,
                        binding: binding,
                        pumpID: pumpID
                    )
                    guard activeBinding == binding,
                          activePumpID == pumpID else { return }
                    forwardedFrameCount &+= 1
                    nextSubmittedSequence &+= 1
                    await forwardEligibleAcousticEvidence(
                        binding: binding,
                        pumpID: pumpID
                    )
                case .failure(.invalidIdentity), .failure(.cancelled):
                    pendingEligibleAcousticObservation = nil
                    pendingEligibilitySourceGateEpoch = nil
                    pendingEligibilityGateBeforeIssue = nil
                    acousticEligibilityForwarded = false
                    acousticEligibilityGate =
                        RealtimeAcousticInterruptionEligibilityGate(
                            session: binding.session,
                            captureGeneration: binding.captureGeneration
                        )
                    runtimeRejectedFrameCount &+= 1
                case .failure(let error):
                    await finish(
                        binding: binding,
                        pumpID: pumpID,
                        state: MacSpeechRealtimeBrainInputBridgeState.failed,
                        error: error
                    )
                    return
                }
            }
        }
    }

    func beginProviderCausalCandidate(
        session: RealtimeBrainSessionIdentity
    ) async -> Bool {
        guard let binding = activeBinding,
              binding.session == session else { return false }
        return await beginCausalProvisionalIfSupported(
            binding: binding,
            requiresNearEndSupport: false
        )
    }

    private func beginCausalProvisionalIfSupported(
        binding: MacSpeechRealtimeBrainInputBinding,
        requiresNearEndSupport: Bool
    ) async -> Bool {
        guard causalEpisode == nil,
              activeBinding == binding,
              let beginCausalProvisional,
              let observation = await source.causalInterruptionObservation(),
              causalEpisode == nil,
              activeBinding == binding else { return false }
        guard observation.isPlaybackActive,
              observation.playbackSequence > 0,
              observation.playbackSequence
                != causalCandidateConsumedPlaybackSequence,
              let render = observation.latestRenderFrame,
              render.rms >= Self.causalActivityRMS,
              render.hostTimeNanoseconds != nil else { return false }
        let nearEndSupported = Self.hasCausalNearEndSupport(
            observation.recentCaptureFrames,
            throughNanoseconds: nil
        )
        guard !requiresNearEndSupport || nearEndSupported else {
            return false
        }
        let now = monotonicNow()
        let id = UUID()
        let episode = MacSpeechCausalProvisionalEpisode(
            id: id,
            binding: binding,
            playbackSequence: observation.playbackSequence,
            deadlineNanoseconds:
                now &+ Self.causalEvidenceDeadlineNanoseconds,
            preYieldRenderFrame: render
        )
        causalCandidateConsumedPlaybackSequence = observation.playbackSequence
        guard await beginCausalProvisional(
            id,
            binding,
            observation.playbackSequence
        ), activeBinding == binding,
           causalEpisode == nil else {
            if activeBinding == binding,
               causalEpisode == nil,
               causalCandidateConsumedPlaybackSequence
                == observation.playbackSequence {
                causalCandidateConsumedPlaybackSequence = nil
            }
            return false
        }
        causalEpisode = episode
        return true
    }

    private func advanceCausalProvisionalIfNeeded(
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID
    ) async {
        guard let episode = causalEpisode,
              episode.binding == binding,
              activeBinding == binding,
              activePumpID == pumpID else { return }
        let now = monotonicNow()
        guard let observation = await source.causalInterruptionObservation(),
              activeBinding == binding,
              activePumpID == pumpID,
              causalEpisode?.id == episode.id,
              observation.isPlaybackActive,
              observation.playbackSequence == episode.playbackSequence,
              let latestRender = observation.latestRenderFrame else {
            await recoverCausalEpisode(episode, binding: binding)
            return
        }

        if Self.actualFarEndDrop(
            from: episode.preYieldRenderFrame,
            to: latestRender
        ) != nil {
            // Gate 1 support preserves a candidate; it does not identify a
            // user source and therefore cannot become formal evidence.
            await recoverCausalEpisode(episode, binding: binding)
            return
        }

        if now >= episode.deadlineNanoseconds {
            await recoverCausalEpisode(episode, binding: binding)
        }
    }

    private func recoverCausalEpisode(
        _ episode: MacSpeechCausalProvisionalEpisode,
        binding: MacSpeechRealtimeBrainInputBinding
    ) async {
        guard causalEpisode?.id == episode.id else { return }
        causalEpisode = nil
        await recoverCausalProvisional?(episode.id, binding)
        await discardCausalEvidence?(binding)
        guard activeBinding == binding,
              causalEpisode == nil else { return }
        causalCandidateConsumedPlaybackSequence = episode.playbackSequence
    }

    private static func actualFarEndDrop(
        from before: MacSpeechCausalFrameObservation,
        to after: MacSpeechCausalFrameObservation
    ) -> MacSpeechCausalFrameObservation? {
        guard after.index > before.index,
              after.hostTimeNanoseconds != nil,
              before.rms >= causalActivityRMS else { return nil }
        let beforePower = before.rms * before.rms
        let afterPower = after.rms * after.rms
        guard beforePower > 0,
              afterPower / beforePower
                <= causalFarEndPowerRatioMaximum else { return nil }
        return after
    }

    private static func hasCausalNearEndSupport(
        _ frames: [MacSpeechCausalFrameObservation],
        throughNanoseconds: UInt64?
    ) -> Bool {
        let eligible = frames.filter { frame in
            guard let throughNanoseconds else { return true }
            return frame.hostTimeNanoseconds.map {
                $0 <= throughNanoseconds
            } ?? false
        }
        guard eligible.count >= 5 else { return false }
        for start in 0...(eligible.count - 5) {
            let group = Array(eligible[start..<(start + 5)])
            let contiguous = zip(group, group.dropFirst()).allSatisfy {
                previous, next in
                guard next.index == previous.index &+ 1,
                      let previousTime = previous.hostTimeNanoseconds,
                      let nextTime = next.hostTimeNanoseconds,
                      nextTime >= previousTime else { return false }
                let delta = nextTime - previousTime
                return delta >= 9_999_999 && delta <= 10_000_001
            }
            if contiguous,
               group.filter({ $0.rms >= causalActivityRMS }).count >= 3 {
                return true
            }
        }
        return false
    }

    private func makeInputActivity(
        for frame: MacSpeechAudioFrame,
        binding: MacSpeechRealtimeBrainInputBinding
    ) async -> MacSpeechRealtimeBrainInputActivity {
        guard let liveSnapshot = await source.residentAcousticSnapshot(),
              liveSnapshot.captureGeneration == binding.captureGeneration,
              liveSnapshot.playbackSequence
                == frame.residentPlaybackSequence,
              liveSnapshot.residentPlaybackActive
                == frame.residentPlaybackActive,
              liveSnapshot.routeStable,
              liveSnapshot.inputDeviceAvailable,
              liveSnapshot.outputDeviceAvailable else {
            return MacSpeechRealtimeBrainInputActivity(
                localActivity: .none
            )
        }
        let snapshot = residentAcousticSnapshot(
            captured: frame.acousticSnapshot,
            live: liveSnapshot
        )

        let kind: RealtimeBrainLocalAudioActivityKind
        switch frame.activityEvidenceKind {
        case .none:
            kind = .none
        case .listeningNearEnd:
            kind = snapshot.residentPlaybackActive
                ? .none : .listeningNearEnd
        case .sourceGatedNearEnd:
            kind = snapshot.residentPlaybackActive
                    && snapshot.sourceGateOpen
                    && frame.sourceGateEpoch > 0
                    && snapshot.sourceGateEpoch == frame.sourceGateEpoch
                ? .sourceGatedNearEnd : .none
        }
        return MacSpeechRealtimeBrainInputActivity(
            localActivity: RealtimeBrainLocalAudioActivity(
                kind: kind,
                residentPlaybackSequence:
                    frame.residentPlaybackSequence,
                residentPlaybackActive:
                    frame.residentPlaybackActive,
                lastAudibleResidentRenderTimestampNanoseconds:
                    frame
                        .lastAudibleResidentRenderTimestampNanoseconds,
                sourceGateEpoch: kind == .sourceGatedNearEnd
                    ? frame.sourceGateEpoch : 0,
                routeStable: snapshot.routeStable,
                inputDeviceAvailable: snapshot.inputDeviceAvailable,
                outputDeviceAvailable: snapshot.outputDeviceAvailable
            )
        )
    }

    private func confirmListeningActivityIfCurrent(
        realtimeFrame: RealtimeBrainAudioFrame,
        captureFrame: MacSpeechAudioFrame,
        activity: MacSpeechRealtimeBrainInputActivity,
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID
    ) async {
        guard activity.localActivity.kind == .listeningNearEnd,
              let confirmAcceptedLocalActivity,
              activeBinding == binding,
              activePumpID == pumpID else { return }
        let currentActivity = await makeInputActivity(
            for: captureFrame,
            binding: binding
        )
        guard currentActivity == activity,
              activeBinding == binding,
              activePumpID == pumpID else {
            listeningFreshnessRejectedCount &+= 1
            return
        }
        listeningConfirmationAttemptCount &+= 1
        let result = await confirmAcceptedLocalActivity(
            realtimeFrame,
            activity
        )
        switch result {
        case .success:
            listeningConfirmationAcceptedCount &+= 1
        case .failure:
            listeningConfirmationRejectedCount &+= 1
        }
    }

    private func observeResidentAcousticsIfNeeded(
        fallbackTimestampNanoseconds: UInt64,
        capturedAcousticSnapshot:
            MacSpeechAcousticObservationSnapshot?,
        observerOnly: Bool,
        sourceGatedPacketTrace:
            MacSpeechRealtimeBrainAcousticPacketTrace? = nil,
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID
    ) async {
        if observerOnly {
            guard fallbackTimestampNanoseconds
                    >= nextResidentAcousticSnapshotPollNanoseconds else {
                return
            }
            nextResidentAcousticSnapshotPollNanoseconds =
                fallbackTimestampNanoseconds &+ 10_000_000
        }
        guard let liveSnapshot = await source.residentAcousticSnapshot() else {
            #if DEBUG
            recordSourceGatedPacketTrace(
                sourceGatedPacketTrace,
                disposition: "guard_live_snapshot_unavailable",
                binding: binding
            )
            #endif
            return
        }
        guard liveSnapshot.captureGeneration == binding.captureGeneration else {
            #if DEBUG
            recordSourceGatedPacketTrace(
                sourceGatedPacketTrace,
                disposition: "guard_capture_generation_mismatch",
                binding: binding
            )
            #endif
            return
        }
        guard activeBinding == binding,
              activePumpID == pumpID else {
            #if DEBUG
            recordSourceGatedPacketTrace(
                sourceGatedPacketTrace,
                disposition: "guard_binding_or_pump_changed",
                binding: binding
            )
            #endif
            return
        }
        if observerOnly {
            guard !liveSnapshot.sourceGateOpen else { return }
        } else {
            guard let capturedAcousticSnapshot else {
                #if DEBUG
                recordSourceGatedPacketTrace(
                    sourceGatedPacketTrace,
                    disposition: "guard_captured_snapshot_unavailable",
                    binding: binding
                )
                #endif
                return
            }
            guard capturedAcousticSnapshot.playbackSequence
                    == liveSnapshot.playbackSequence else {
                #if DEBUG
                recordSourceGatedPacketTrace(
                    sourceGatedPacketTrace,
                    disposition: "guard_playback_sequence_mismatch",
                    binding: binding
                )
                #endif
                return
            }
            guard capturedAcousticSnapshot.isPlaybackActive
                    == liveSnapshot.residentPlaybackActive else {
                #if DEBUG
                recordSourceGatedPacketTrace(
                    sourceGatedPacketTrace,
                    disposition: "guard_playback_activity_mismatch",
                    binding: binding
                )
                #endif
                return
            }
        }
        let snapshot = residentAcousticSnapshot(
            captured: capturedAcousticSnapshot,
            live: liveSnapshot
        )
        if observerOnly {
            guard snapshot.captureFrameIndex
                    > lastObserverOnlyResidentCaptureFrameIndex,
                  activeBinding == binding,
                  activePumpID == pumpID else { return }
            lastObserverOnlyResidentCaptureFrameIndex =
                snapshot.captureFrameIndex
        } else {
            guard snapshot.captureFrameIndex
                    > lastResidentCaptureFrameIndex else {
                #if DEBUG
                recordSourceGatedPacketTrace(
                    sourceGatedPacketTrace,
                    disposition: "guard_capture_frame_not_newer",
                    binding: binding,
                    snapshot: snapshot
                )
                #endif
                return
            }
            guard activeBinding == binding,
                  activePumpID == pumpID else {
                #if DEBUG
                recordSourceGatedPacketTrace(
                    sourceGatedPacketTrace,
                    disposition: "guard_binding_or_pump_changed",
                    binding: binding,
                    snapshot: snapshot
                )
                #endif
                return
            }
            lastResidentCaptureFrameIndex = snapshot.captureFrameIndex
        }

        let timestamp = snapshot.captureHostTimeNanoseconds
            ?? fallbackTimestampNanoseconds
        let metrics = RealtimeAcousticMetrics(
            residentPlaybackSequence: snapshot.playbackSequence,
            residentPlaybackActive: snapshot.residentPlaybackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                snapshot.lastAudibleResidentRenderTimestampNanoseconds,
            renderReferenceAvailable: snapshot.renderReferenceAvailable,
            renderReferenceRMS: snapshot.renderReferenceRMS,
            rawCaptureRMS: snapshot.rawCaptureRMS,
            aecOutputRMS: snapshot.processedCaptureRMS,
            linearAECOutputRMS: snapshot.linearAECOutputRMS,
            renderCaptureCorrelation:
                snapshot.renderCaptureCorrelation,
            residualRenderCorrelation:
                snapshot.residualRenderCorrelation,
            linearRenderCorrelation: snapshot.linearRenderCorrelation,
            captureTimestampNanoseconds:
                snapshot.captureHostTimeNanoseconds,
            renderTimestampNanoseconds:
                snapshot.renderHostTimeNanoseconds,
            sourceAlignmentDelayMilliseconds:
                snapshot.sourceAlignmentDelayMilliseconds,
            estimatedDelayMilliseconds: snapshot.aecEnabled
                ? snapshot.estimatedDelayMilliseconds : nil,
            erlDecibels: snapshot.aecEnabled
                ? snapshot.erlDecibels : nil,
            erleDecibels: snapshot.aecEnabled
                ? snapshot.erleDecibels : nil,
            renderCaptureSkewFrames:
                snapshot.renderCaptureSkewFrames,
            driftState: Self.driftState(snapshot.driftTrend),
            sourceAssessment: Self.sourceAssessment(
                snapshot.inputClassification
            ),
            sourceGateOpen: snapshot.sourceGateOpen,
            sourceGateEpoch: snapshot.sourceGateEpoch,
            aecActive: snapshot.aecActive,
            renderCaptureIsolationEstablished:
                snapshot.renderCaptureIsolationEstablished,
            sourceAlignmentLocked: snapshot.sourceAlignmentLocked,
            routeStable: snapshot.routeStable,
            inputDeviceAvailable: snapshot.inputDeviceAvailable,
            outputDeviceAvailable: snapshot.outputDeviceAvailable
        )
        let classification = RealtimeAcousticClassifier.classify(
            metrics: metrics,
            observationTimestampNanoseconds: timestamp
        )
        let observation = RealtimeAcousticObservation(
            identity: RealtimeAcousticObservationIdentity(
                session: binding.session,
                captureGeneration: binding.captureGeneration,
                sequence: nextResidentAcousticObservationSequence,
                timestampNanoseconds: timestamp
            ),
            metrics: metrics,
            classification: classification
        )
        nextResidentAcousticObservationSequence &+= 1
        var isEligibleCandidate = false
        if !observerOnly, var gate = acousticEligibilityGate {
            let gateBeforeEvaluation = gate
            #if DEBUG
            let gateDiagnosticState = gate.diagnosticState
            #endif
            let disposition = gate.evaluate(observation)
            acousticEligibilityGate = gate
            #if DEBUG
            let dispositionName: String
            switch disposition {
            case .eligible:
                dispositionName = "eligible"
            case .suppressed(let reason):
                dispositionName = reason.rawValue
            }
            acousticEligibilityDispositionCounts[dispositionName, default: 0]
                &+= 1
            lastAcousticEligibilityDisposition = dispositionName
            recordSourceGatedPacketTrace(
                sourceGatedPacketTrace,
                disposition: dispositionName,
                binding: binding,
                snapshot: snapshot,
                observation: observation,
                gateState: gateDiagnosticState
            )
            #endif
            switch disposition {
            case .eligible:
                pendingEligibleAcousticObservation = observation
                pendingEligibilitySourceGateEpoch =
                    observation.metrics.sourceGateEpoch
                pendingEligibilityGateBeforeIssue = gateBeforeEvaluation
                acousticEligibilityForwarded = false
                acousticEligibilityCandidateCount &+= 1
                #if DEBUG
                lastAcousticEvidenceForwardDisposition = "pending"
                #endif
                isEligibleCandidate = true
                recordAcousticDiagnosticIfNeeded(
                    MacSpeechRealtimeBrainAcousticDiagnostic(
                        category: "acoustic_eligibility_candidate",
                        disposition: "pending",
                        turnGeneration: binding.session.generation,
                        observationSequence: observation.identity.sequence,
                        sourceGateEpoch:
                            observation.metrics.sourceGateEpoch,
                        timestampNanoseconds:
                            observation.identity.timestampNanoseconds
                    )
                )
            case .suppressed(.alreadyEligible):
                break
            case .suppressed:
                pendingEligibleAcousticObservation = nil
                pendingEligibilitySourceGateEpoch = nil
                pendingEligibilityGateBeforeIssue = nil
            }
        } else if !observerOnly {
            #if DEBUG
            recordSourceGatedPacketTrace(
                sourceGatedPacketTrace,
                disposition: "guard_eligibility_gate_unavailable",
                binding: binding,
                snapshot: snapshot,
                observation: observation
            )
            #endif
        }

        guard !isEligibleCandidate,
              pendingEligibleAcousticObservation == nil,
              let observeResidentAcoustics else { return }
        let cadenceReached = lastResidentObservationFrameIndex == 0
            || snapshot.captureFrameIndex
                >= lastResidentObservationFrameIndex &+ 10
        guard cadenceReached else { return }
        guard residentAcousticObservationTask == nil else {
            lastResidentObservationFrameIndex = snapshot.captureFrameIndex
            droppedResidentAcousticObservationCount &+= 1
            return
        }

        lastResidentObservationFrameIndex = snapshot.captureFrameIndex
        let deliveryID = UUID()
        residentAcousticObservationTaskID = deliveryID
        residentAcousticObservationTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let disposition = await observeResidentAcoustics(observation)
            await self?.finishResidentAcousticObservation(
                disposition,
                deliveryID: deliveryID,
                binding: binding,
                pumpID: pumpID
            )
        }
    }

    private func residentAcousticSnapshot(
        captured: MacSpeechAcousticObservationSnapshot?,
        live: MacSpeechResidentAcousticSnapshot
    ) -> MacSpeechResidentAcousticSnapshot {
        guard let captured else { return live }
        return MacSpeechResidentAcousticSnapshot(
            captureGeneration: live.captureGeneration,
            captureFrameIndex: captured.captureFrameIndex,
            captureHostTimeNanoseconds:
                captured.captureHostTimeNanoseconds,
            playbackSequence: captured.playbackSequence,
            residentPlaybackActive: captured.isPlaybackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                captured.lastAudibleRenderHostTimeNanoseconds,
            renderReferenceAvailable:
                captured.renderReferenceAvailable,
            renderReferenceRMS: captured.renderReferenceRMS,
            renderHostTimeNanoseconds:
                captured.renderHostTimeNanoseconds,
            rawCaptureRMS: captured.rawCaptureRMS,
            processedCaptureRMS: captured.processedCaptureRMS,
            linearAECOutputRMS: captured.linearAECOutputRMS,
            renderCaptureCorrelation:
                captured.renderCaptureCorrelation,
            residualRenderCorrelation:
                captured.residualRenderCorrelation,
            linearRenderCorrelation:
                captured.linearRenderCorrelation,
            inputClassification: captured.inputClassification,
            sourceGateOpen: captured.sourceGateOpen,
            sourceGateEpoch: captured.sourceGateEpoch,
            aecEnabled: captured.aecEnabled,
            aecActive: captured.aecActive,
            renderCaptureIsolationEstablished:
                captured.renderCaptureIsolationEstablished,
            sourceAlignmentLocked: captured.sourceAlignmentLocked,
            sourceAlignmentDelayMilliseconds:
                captured.sourceAlignmentDelayMilliseconds,
            estimatedDelayMilliseconds:
                captured.estimatedDelayMilliseconds,
            erlDecibels: captured.erlDecibels,
            erleDecibels: captured.erleDecibels,
            renderCaptureSkewFrames:
                captured.renderCaptureSkewFrames,
            driftTrend: captured.driftTrend,
            routeStable: live.routeStable,
            inputDeviceAvailable: live.inputDeviceAvailable,
            outputDeviceAvailable: live.outputDeviceAvailable
        )
    }

    private func finishResidentAcousticObservation(
        _ disposition: RealtimeAcousticObservationDisposition,
        deliveryID: UUID,
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID
    ) {
        guard residentAcousticObservationTaskID == deliveryID else { return }
        residentAcousticObservationTask = nil
        residentAcousticObservationTaskID = nil
        guard activeBinding == binding,
              activePumpID == pumpID else { return }
        switch disposition {
        case .observed:
            residentAcousticObservationCount &+= 1
        case .ignored:
            rejectedResidentAcousticObservationCount &+= 1
        }
    }

    private func forwardEligibleAcousticEvidence(
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID
    ) async {
        guard let consumeAcousticObservation,
              !acousticEligibilityForwarded,
              let observation = pendingEligibleAcousticObservation,
              let eligibilityEpoch = pendingEligibilitySourceGateEpoch,
              observation.identity.session == binding.session,
              observation.identity.captureGeneration
                == binding.captureGeneration,
              activeBinding == binding,
              activePumpID == pumpID else { return }
        let currentSnapshot = await source.residentAcousticSnapshot()
        guard activeBinding == binding,
              activePumpID == pumpID,
              pendingEligibleAcousticObservation?.identity
                == observation.identity,
              pendingEligibilitySourceGateEpoch == eligibilityEpoch else {
            return
        }
        let staleReason = Self.acousticEvidenceStaleReason(
            snapshot: currentSnapshot,
            binding: binding,
            observation: observation,
            eligibilityEpoch: eligibilityEpoch,
            receivedAtNanoseconds: monotonicNow()
        )
        if let staleReason {
            if let pendingEligibilityGateBeforeIssue {
                acousticEligibilityGate = pendingEligibilityGateBeforeIssue
                acousticEligibilityRearmedCount &+= 1
            }
            acousticEvidenceStaleFenceCount &+= 1
            #if DEBUG
            acousticEvidenceForwardDispositionCounts[staleReason, default: 0]
                &+= 1
            lastAcousticEvidenceForwardDisposition = staleReason
            #endif
            pendingEligibleAcousticObservation = nil
            pendingEligibilitySourceGateEpoch = nil
            pendingEligibilityGateBeforeIssue = nil
            acousticEligibilityForwarded = false
            recordAcousticDiagnosticIfNeeded(
                MacSpeechRealtimeBrainAcousticDiagnostic(
                    category: "acoustic_evidence_forward",
                    disposition: staleReason,
                    turnGeneration: binding.session.generation,
                    observationSequence: observation.identity.sequence,
                    sourceGateEpoch: eligibilityEpoch,
                    timestampNanoseconds:
                        observation.identity.timestampNanoseconds
                )
            )
            return
        }
        pendingEligibleAcousticObservation = nil
        pendingEligibilitySourceGateEpoch = nil
        pendingEligibilityGateBeforeIssue = nil
        acousticEligibilityForwarded = true
        #if DEBUG
        lastAcousticEvidenceForwardDisposition = "forwarded"
        acousticEvidenceForwardDispositionCounts["forwarded", default: 0]
            &+= 1
        #endif
        acousticEvidenceCount &+= 1
        recordAcousticDiagnosticIfNeeded(
            MacSpeechRealtimeBrainAcousticDiagnostic(
                category: "acoustic_evidence_forward",
                disposition: "forwarded",
                turnGeneration: binding.session.generation,
                observationSequence: observation.identity.sequence,
                sourceGateEpoch: eligibilityEpoch,
                timestampNanoseconds:
                    observation.identity.timestampNanoseconds
            )
        )
        let metrics = observation.metrics
        let sourceGateSeparatesNearEnd = metrics.sourceGateOpen
            && metrics.sourceGateEpoch > 0
            && metrics.sourceAssessment == .doubleTalk
        await consumeAcousticObservation(
            MacSpeechRealtimeBrainAcousticObservation(
                observation: observation,
                facts: RealtimeInterruptionAcousticFacts(
                    sourceGateEpoch: metrics.sourceGateEpoch,
                    nearEndDetected:
                        observation.classification == .nearEndCandidate,
                    sourceAttributionConfirmed: false,
                    farEndActive: metrics.residentPlaybackActive,
                    sourceGateOpen: metrics.sourceGateOpen,
                    renderReferenceConfidence:
                        (metrics.sourceAlignmentLocked
                            || metrics.renderCaptureIsolationEstablished
                            || sourceGateSeparatesNearEnd)
                            ? 1 : 0,
                    routeStable: metrics.routeStable,
                    inputDeviceAvailable: metrics.inputDeviceAvailable,
                    outputDeviceAvailable: metrics.outputDeviceAvailable
                )
            )
        )
    }

    private static func acousticEvidenceStaleReason(
        snapshot: MacSpeechResidentAcousticSnapshot?,
        binding: MacSpeechRealtimeBrainInputBinding,
        observation: RealtimeAcousticObservation,
        eligibilityEpoch: UInt64,
        receivedAtNanoseconds: UInt64
    ) -> String? {
        guard let snapshot else { return "stale_snapshot_unavailable" }
        guard snapshot.captureGeneration == binding.captureGeneration else {
            return "stale_capture_generation"
        }
        guard snapshot.playbackSequence
                == observation.metrics.residentPlaybackSequence else {
            return "stale_playback_sequence"
        }
        guard snapshot.residentPlaybackActive else {
            return "stale_playback_inactive"
        }
        guard snapshot.sourceGateEpoch == eligibilityEpoch else {
            return "stale_source_gate_epoch"
        }
        guard snapshot.routeStable else { return "stale_route_unstable" }
        guard snapshot.inputDeviceAvailable else {
            return "stale_input_device_unavailable"
        }
        guard snapshot.outputDeviceAvailable else {
            return "stale_output_device_unavailable"
        }
        let timestamp = observation.identity.timestampNanoseconds
        guard timestamp <= receivedAtNanoseconds,
              receivedAtNanoseconds - timestamp
                <= RealtimeAcousticInterruptionEligibilityGate
                    .observationFreshnessNanoseconds else {
            return "stale_observation_expired"
        }
        return nil
    }

    private func recordAcousticDiagnosticIfNeeded(
        _ diagnostic: MacSpeechRealtimeBrainAcousticDiagnostic
    ) {
        guard let recorder = recordAcousticDiagnostic else { return }
        Task { @MainActor in
            recorder(diagnostic)
        }
    }

    #if DEBUG
    private func recordSourceGatedPacketTrace(
        _ packetTrace: MacSpeechRealtimeBrainAcousticPacketTrace?,
        disposition: String,
        binding: MacSpeechRealtimeBrainInputBinding,
        snapshot: MacSpeechResidentAcousticSnapshot? = nil,
        observation: RealtimeAcousticObservation? = nil,
        gateState: RealtimeAcousticEligibilityGateDiagnosticState? = nil
    ) {
        guard let packetTrace else { return }
        let trace = MacSpeechRealtimeBrainAcousticPacketTrace(
            packetSequence: packetTrace.packetSequence,
            captureFrameIndex: snapshot?.captureFrameIndex
                ?? packetTrace.captureFrameIndex,
            observationSequence: observation?.identity.sequence,
            observationTimestampNanoseconds:
                observation?.identity.timestampNanoseconds
                    ?? packetTrace.observationTimestampNanoseconds,
            playbackSequence: observation?.metrics.residentPlaybackSequence
                ?? snapshot?.playbackSequence
                ?? packetTrace.playbackSequence,
            sourceGateEpoch: observation?.metrics.sourceGateEpoch
                ?? snapshot?.sourceGateEpoch
                ?? packetTrace.sourceGateEpoch,
            sourceAssessment: observation?.metrics.sourceAssessment.rawValue
                ?? snapshot?.inputClassification.rawValue
                ?? packetTrace.sourceAssessment,
            classification: observation?.classification.rawValue,
            captureTimestampNanoseconds:
                observation?.metrics.captureTimestampNanoseconds
                    ?? snapshot?.captureHostTimeNanoseconds
                    ?? packetTrace.captureTimestampNanoseconds,
            lastAudibleRenderTimestampNanoseconds:
                observation?.metrics
                    .lastAudibleResidentRenderTimestampNanoseconds
                    ?? snapshot?
                        .lastAudibleResidentRenderTimestampNanoseconds
                    ?? packetTrace.lastAudibleRenderTimestampNanoseconds,
            gateLastSequence: gateState?.lastSequence,
            gateLastTimestampNanoseconds:
                gateState?.lastTimestampNanoseconds,
            gateLastPlaybackSequence: gateState?.lastPlaybackSequence,
            gateLastAudibleRenderTimestampNanoseconds:
                gateState?.lastAudibleRenderTimestampNanoseconds
        )
        recordAcousticDiagnosticIfNeeded(
            MacSpeechRealtimeBrainAcousticDiagnostic(
                category: "source_gated_near_end_packet",
                disposition: disposition,
                turnGeneration: binding.session.generation,
                observationSequence: trace.observationSequence ?? 0,
                sourceGateEpoch: trace.sourceGateEpoch,
                timestampNanoseconds:
                    trace.observationTimestampNanoseconds
                        ?? DispatchTime.now().uptimeNanoseconds,
                packetTrace: trace
            )
        )
    }
    #endif

    private func finish(
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID,
        state: MacSpeechRealtimeBrainInputBridgeState,
        error: Error?
    ) async {
        guard activeBinding == binding,
              activePumpID == pumpID else { return }
        let endingCausalEpisode = causalEpisode
        causalEpisode = nil
        if let endingCausalEpisode {
            await recoverCausalProvisional?(
                endingCausalEpisode.id,
                binding
            )
            await discardCausalEvidence?(binding)
        }
        activeBinding = nil
        pumpTask = nil
        activePumpID = nil
        suspendedPumpID = nil
        retainedCapture.removeAll()
        retainedCaptureExpectedSession = nil
        retainedCaptureAmbiguous = false
        enforceCaptureContinuity = false
        self.state = state
        resetResidentAcousticObservationState()
        lastError = error.map(Self.standardErrorName)
        let closeResult = await close(binding: binding)
        if case .failure(let closeError) = closeResult {
            self.state = .failed
            lastError = Self.standardErrorName(closeError)
        }
    }

    private func makeSnapshot() -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        MacSpeechRealtimeBrainInputBridgeSnapshot(
            state: state,
            sessionShortID: (
                activeBinding ?? suspendedBinding ?? pendingCloseBinding
            ).map {
                String($0.session.brainLeaseID.uuidString.prefix(8))
            },
            forwardedFrameCount: forwardedFrameCount,
            residentAcousticObservationCount:
                residentAcousticObservationCount,
            rejectedResidentAcousticObservationCount:
                rejectedResidentAcousticObservationCount,
            droppedResidentAcousticObservationCount:
                droppedResidentAcousticObservationCount,
            acousticEvidenceCount: acousticEvidenceCount,
            acousticEligibilityCandidateCount:
                acousticEligibilityCandidateCount,
            acousticEligibilityRearmedCount:
                acousticEligibilityRearmedCount,
            acousticEvidenceStaleFenceCount:
                acousticEvidenceStaleFenceCount,
            acousticEligibilityDispositionCounts:
                acousticEligibilityDispositionCounts,
            acousticEvidenceForwardDispositionCounts:
                acousticEvidenceForwardDispositionCounts,
            runtimeRejectedFrameCount: runtimeRejectedFrameCount,
            sendOperationCount: sendOperationCount,
            noneActivityFrameCount: noneActivityFrameCount,
            listeningNearEndFrameCount: listeningNearEndFrameCount,
            sourceGatedNearEndFrameCount: sourceGatedNearEndFrameCount,
            listeningConfirmationAttemptCount:
                listeningConfirmationAttemptCount,
            listeningConfirmationAcceptedCount:
                listeningConfirmationAcceptedCount,
            listeningConfirmationRejectedCount:
                listeningConfirmationRejectedCount,
            listeningFreshnessRejectedCount:
                listeningFreshnessRejectedCount,
            averageSendDurationMilliseconds: sendOperationCount == 0
                ? 0 : totalSendDurationMilliseconds / sendOperationCount,
            maximumSendDurationMilliseconds:
                maximumSendDurationMilliseconds,
            lastAcousticEligibilityDisposition:
                lastAcousticEligibilityDisposition,
            lastAcousticEvidenceForwardDisposition:
                lastAcousticEvidenceForwardDisposition,
            lastError: lastError,
            hasActivePump: activeBinding != nil
                && activePumpID != nil
                && pumpTask != nil,
            hasPendingResidentAcousticObservation:
                residentAcousticObservationTask != nil
        )
    }

    private func resetResidentAcousticObservationState(
        binding: MacSpeechRealtimeBrainInputBinding? = nil
    ) {
        residentAcousticObservationTask?.cancel()
        residentAcousticObservationTask = nil
        residentAcousticObservationTaskID = nil
        acousticEligibilityGate = binding.map {
            RealtimeAcousticInterruptionEligibilityGate(
                session: $0.session,
                captureGeneration: $0.captureGeneration
            )
        }
        pendingEligibleAcousticObservation = nil
        pendingEligibilitySourceGateEpoch = nil
        pendingEligibilityGateBeforeIssue = nil
        acousticEligibilityForwarded = false
        nextResidentAcousticObservationSequence = 1
        nextResidentAcousticSnapshotPollNanoseconds = 0
        lastResidentCaptureFrameIndex = 0
        lastObserverOnlyResidentCaptureFrameIndex = 0
        lastResidentObservationFrameIndex = 0
    }

    private static func sourceAssessment(
        _ classification: MacSpeechAcousticInputClassification
    ) -> RealtimeAcousticSourceAssessment {
        switch classification {
        case .echoOnly: .echoOnly
        case .nearEndSpeech: .nearEndSpeech
        case .doubleTalk: .doubleTalk
        case .uncertain: .uncertain
        }
    }

    private static func driftState(
        _ value: String
    ) -> RealtimeAcousticDriftState {
        switch value {
        case "stable": .stable
        case "render_ahead": .renderAhead
        case "capture_ahead": .captureAhead
        default: .unknown
        }
    }

    private func close(
        binding: MacSpeechRealtimeBrainInputBinding
    ) async -> Result<Void, RealtimeResidentBrainError> {
        let task: Task<Result<Void, RealtimeResidentBrainError>, Never>
        let attemptID: UUID
        if pendingCloseBinding == binding,
           let existingTask = closeTask,
           let existingAttemptID = closeAttemptID {
            task = existingTask
            attemptID = existingAttemptID
        } else {
            pendingCloseBinding = binding
            let newAttemptID = UUID()
            let stopInput = self.stopInput
            let newTask = Task {
                await stopInput(binding)
            }
            closeTask = newTask
            closeAttemptID = newAttemptID
            task = newTask
            attemptID = newAttemptID
        }
        let result = await task.value
        guard closeAttemptID == attemptID else { return result }
        closeTask = nil
        closeAttemptID = nil
        if case .success = result {
            pendingCloseBinding = nil
        }
        return result
    }

    private static func isNextGeneration(
        _ candidate: RealtimeBrainSessionIdentity,
        after previous: RealtimeBrainSessionIdentity
    ) -> Bool {
        candidate.residentID == previous.residentID
            && candidate.runtimeSessionID == previous.runtimeSessionID
            && candidate.brainLeaseID == previous.brainLeaseID
            && candidate.routeEpoch == previous.routeEpoch
            && candidate.generation == previous.generation &+ 1
    }

    private static func standardErrorName(_ error: Error) -> String {
        if let error = error as? RealtimeResidentBrainError {
            switch error {
            case .unavailable: return "unavailable"
            case .voiceBindingUnavailable: return "voice_binding_unavailable"
            case .invalidIdentity: return "invalid_identity"
            case .invalidContextRevision: return "invalid_context_revision"
            case .invalidAudioFrame: return "invalid_audio_frame"
            case .operationInFlight: return "operation_in_flight"
            case .invalidEvent: return "invalid_event"
            case .timedOut: return "timed_out"
            case .cancelled: return "cancelled"
            case .transportFailure: return "transport_failure"
            case .providerFailure: return "provider_failure"
            }
        }
        return "unknown"
    }
}
