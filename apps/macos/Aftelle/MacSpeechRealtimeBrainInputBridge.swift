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
            && snapshot.sourceGateOpen
            && snapshot.sourceGateEpoch == sourceGateEpoch
    }
}

nonisolated struct MacSpeechRealtimeBrainAcousticDiagnostic: Sendable {
    let category: String
    let disposition: String
    let turnGeneration: UInt64
    let observationSequence: UInt64
    let sourceGateEpoch: UInt64
    let timestampNanoseconds: UInt64
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

    private let source: any MacSpeechAudioFrameSourcing
    private let sendFrame: SendFrameWithActivity
    private let confirmAcceptedLocalActivity:
        ConfirmAcceptedLocalActivity?
    private let stopInput: StopInput
    private let observeResidentAcoustics: ObserveResidentAcoustics?
    private let consumeAcousticObservation: ConsumeAcousticObservation?
    private let recordAcousticDiagnostic: RecordAcousticDiagnostic?
    private var pumpTask: Task<Void, Never>?
    private var activePumpID: UUID?
    private var activeBinding: MacSpeechRealtimeBrainInputBinding?
    private var suspendedBinding: MacSpeechRealtimeBrainInputBinding?
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

    init(
        source: any MacSpeechAudioFrameSourcing,
        sendFrame: @escaping SendFrame,
        stopInput: @escaping StopInput,
        observeResidentAcoustics: ObserveResidentAcoustics? = nil,
        consumeAcousticObservation: ConsumeAcousticObservation? = nil,
        recordAcousticDiagnostic: RecordAcousticDiagnostic? = nil
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
    }

    init(
        source: any MacSpeechAudioFrameSourcing,
        sendFrameWithActivity: @escaping SendFrameWithActivity,
        confirmAcceptedLocalActivity:
            ConfirmAcceptedLocalActivity? = nil,
        stopInput: @escaping StopInput,
        observeResidentAcoustics: ObserveResidentAcoustics? = nil,
        consumeAcousticObservation: ConsumeAcousticObservation? = nil,
        recordAcousticDiagnostic: RecordAcousticDiagnostic? = nil
    ) {
        self.source = source
        self.sendFrame = sendFrameWithActivity
        self.confirmAcceptedLocalActivity = confirmAcceptedLocalActivity
        self.stopInput = stopInput
        self.observeResidentAcoustics = observeResidentAcoustics
        self.consumeAcousticObservation = consumeAcousticObservation
        self.recordAcousticDiagnostic = recordAcousticDiagnostic
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
        session: RealtimeBrainSessionIdentity
    ) -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        guard let binding = activeBinding,
              binding.session == session,
              suspendedBinding == nil else { return makeSnapshot() }
        pumpTask?.cancel()
        pumpTask = nil
        activePumpID = nil
        activeBinding = nil
        suspendedBinding = binding
        generationTransitionID = UUID()
        resetResidentAcousticObservationState()
        state = .stopped
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
        await source.discardPendingAudioForGenerationTransition()
        _ = await source.drainFrames(
            maxCount: MacSpeechAudioInputFormat.frameCapacity
        )
        guard suspendedBinding == previous,
              generationTransitionID == transitionID else {
            return makeSnapshot()
        }
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: previous.captureGeneration
        )
        suspendedBinding = nil
        generationTransitionID = nil
        activeBinding = binding
        nextSubmittedSequence = 1
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
        generationTransitionID = nil
        state = .stopped
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
        generationTransitionID = nil
        resetResidentAcousticObservationState()
        if state != .failed { state = .stopped }
        return makeSnapshot()
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

            let frames = await source.drainFrames(
                maxCount: MacSpeechAudioInputFormat.frameCapacity
            )
            if frames.isEmpty {
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

            for frame in frames {
                guard !Task.isCancelled,
                      activeBinding == binding,
                      activePumpID == pumpID else { return }
                guard frame.captureGeneration == binding.captureGeneration else {
                    runtimeRejectedFrameCount &+= 1
                    continue
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
                await observeResidentAcousticsIfNeeded(
                    fallbackTimestampNanoseconds:
                        realtimeFrame.timestampNanoseconds,
                    capturedAcousticSnapshot: frame.acousticSnapshot,
                    observerOnly: false,
                    binding: binding,
                    pumpID: pumpID
                )
                guard !Task.isCancelled,
                      activeBinding == binding,
                      activePumpID == pumpID else { return }
                let sendStartedAt = DispatchTime.now().uptimeNanoseconds
                let result = await sendFrame(
                    realtimeFrame,
                    inputActivity
                )
                let sendDuration = (
                    DispatchTime.now().uptimeNanoseconds &- sendStartedAt
                ) / 1_000_000
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
        guard let liveSnapshot = await source.residentAcousticSnapshot(),
              liveSnapshot.captureGeneration == binding.captureGeneration,
              activeBinding == binding,
              activePumpID == pumpID else { return }
        if observerOnly {
            guard !liveSnapshot.sourceGateOpen else { return }
        } else {
            guard let capturedAcousticSnapshot,
                  capturedAcousticSnapshot.playbackSequence
                    == liveSnapshot.playbackSequence,
                  capturedAcousticSnapshot.isPlaybackActive
                    == liveSnapshot.residentPlaybackActive else { return }
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
            guard snapshot.captureFrameIndex > lastResidentCaptureFrameIndex,
                  activeBinding == binding,
                  activePumpID == pumpID else { return }
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
            eligibilityEpoch: eligibilityEpoch
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
        eligibilityEpoch: UInt64
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
        guard snapshot.sourceGateOpen else { return "stale_source_gate_closed" }
        guard snapshot.sourceGateEpoch == eligibilityEpoch else {
            return "stale_source_gate_epoch"
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

    private func finish(
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID,
        state: MacSpeechRealtimeBrainInputBridgeState,
        error: Error?
    ) async {
        guard activeBinding == binding,
              activePumpID == pumpID else { return }
        activeBinding = nil
        pumpTask = nil
        activePumpID = nil
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
