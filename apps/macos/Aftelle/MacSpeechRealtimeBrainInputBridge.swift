import Foundation

nonisolated struct MacSpeechRealtimeBrainInputBinding: Sendable, Equatable {
    let session: RealtimeBrainSessionIdentity
    let captureGeneration: UInt64
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
    }
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
    let runtimeRejectedFrameCount: UInt64
    let sendOperationCount: UInt64
    let averageSendDurationMilliseconds: UInt64
    let maximumSendDurationMilliseconds: UInt64
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
        runtimeRejectedFrameCount: 0,
        sendOperationCount: 0,
        averageSendDurationMilliseconds: 0,
        maximumSendDurationMilliseconds: 0,
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

    typealias StopInput = @MainActor @Sendable (
        MacSpeechRealtimeBrainInputBinding
    ) async -> Result<Void, RealtimeResidentBrainError>

    typealias ConsumeAcousticObservation = @MainActor @Sendable (
        MacSpeechRealtimeBrainAcousticObservation
    ) async -> Void

    typealias ObserveResidentAcoustics = @MainActor @Sendable (
        RealtimeAcousticObservation
    ) async -> RealtimeAcousticObservationDisposition

    private let source: any MacSpeechAudioFrameSourcing
    private let sendFrame: SendFrame
    private let stopInput: StopInput
    private let observeResidentAcoustics: ObserveResidentAcoustics?
    private let consumeAcousticObservation: ConsumeAcousticObservation?
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
    private var runtimeRejectedFrameCount: UInt64 = 0
    private var sendOperationCount: UInt64 = 0
    private var totalSendDurationMilliseconds: UInt64 = 0
    private var maximumSendDurationMilliseconds: UInt64 = 0
    private var nextSubmittedSequence: UInt64 = 1
    private var nextResidentAcousticObservationSequence: UInt64 = 1
    private var nextResidentAcousticSnapshotPollNanoseconds: UInt64 = 0
    private var lastResidentCaptureFrameIndex: UInt64 = 0
    private var lastResidentObservationFrameIndex: UInt64 = 0
    private var residentAcousticObservationTask: Task<Void, Never>?
    private var residentAcousticObservationTaskID: UUID?
    private var acousticEligibilityGate:
        RealtimeAcousticInterruptionEligibilityGate?
    private var pendingEligibleAcousticObservation:
        RealtimeAcousticObservation?
    private var acousticEligibilityForwarded = false
    private var lastError: String?

    init(
        source: any MacSpeechAudioFrameSourcing,
        sendFrame: @escaping SendFrame,
        stopInput: @escaping StopInput,
        observeResidentAcoustics: ObserveResidentAcoustics? = nil,
        consumeAcousticObservation: ConsumeAcousticObservation? = nil
    ) {
        self.source = source
        self.sendFrame = sendFrame
        self.stopInput = stopInput
        self.observeResidentAcoustics = observeResidentAcoustics
        self.consumeAcousticObservation = consumeAcousticObservation
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
        runtimeRejectedFrameCount = 0
        sendOperationCount = 0
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
                await observeResidentAcousticsIfNeeded(
                    fallbackTimestampNanoseconds:
                        realtimeFrame.timestampNanoseconds,
                    binding: binding,
                    pumpID: pumpID
                )
                guard !Task.isCancelled,
                      activeBinding == binding,
                      activePumpID == pumpID else { return }
                let sendStartedAt = DispatchTime.now().uptimeNanoseconds
                let result = await sendFrame(realtimeFrame)
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
                    forwardedFrameCount &+= 1
                    nextSubmittedSequence &+= 1
                    await forwardEligibleAcousticEvidence(
                        binding: binding,
                        pumpID: pumpID
                    )
                case .failure(.invalidIdentity), .failure(.cancelled):
                    pendingEligibleAcousticObservation = nil
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

    private func observeResidentAcousticsIfNeeded(
        fallbackTimestampNanoseconds: UInt64,
        binding: MacSpeechRealtimeBrainInputBinding,
        pumpID: UUID
    ) async {
        let pollTimestamp = fallbackTimestampNanoseconds
        guard pollTimestamp >= nextResidentAcousticSnapshotPollNanoseconds else {
            return
        }
        nextResidentAcousticSnapshotPollNanoseconds = pollTimestamp &+ 10_000_000
        guard let snapshot = await source.residentAcousticSnapshot(),
              snapshot.captureGeneration == binding.captureGeneration,
              snapshot.captureFrameIndex > lastResidentCaptureFrameIndex,
              activeBinding == binding,
              activePumpID == pumpID else { return }
        lastResidentCaptureFrameIndex = snapshot.captureFrameIndex

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
            aecActive: snapshot.aecActive,
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
        if var gate = acousticEligibilityGate {
            let disposition = gate.evaluate(observation)
            acousticEligibilityGate = gate
            switch disposition {
            case .eligible:
                pendingEligibleAcousticObservation = observation
                acousticEligibilityForwarded = false
                isEligibleCandidate = true
            case .suppressed(.alreadyEligible):
                break
            case .suppressed:
                pendingEligibleAcousticObservation = nil
            }
        }

        guard !isEligibleCandidate,
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
              observation.identity.session == binding.session,
              observation.identity.captureGeneration
                == binding.captureGeneration,
              activeBinding == binding,
              activePumpID == pumpID else { return }
        pendingEligibleAcousticObservation = nil
        acousticEligibilityForwarded = true
        let metrics = observation.metrics
        acousticEvidenceCount &+= 1
        await consumeAcousticObservation(
            MacSpeechRealtimeBrainAcousticObservation(
                observation: observation,
                facts: RealtimeInterruptionAcousticFacts(
                    nearEndDetected:
                        observation.classification == .nearEndCandidate,
                    farEndActive: metrics.residentPlaybackActive,
                    sourceGateOpen: metrics.sourceGateOpen,
                    renderReferenceConfidence:
                        metrics.sourceAlignmentLocked ? 1 : 0,
                    routeStable: metrics.routeStable,
                    inputDeviceAvailable: metrics.inputDeviceAvailable,
                    outputDeviceAvailable: metrics.outputDeviceAvailable
                )
            )
        )
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
            runtimeRejectedFrameCount: runtimeRejectedFrameCount,
            sendOperationCount: sendOperationCount,
            averageSendDurationMilliseconds: sendOperationCount == 0
                ? 0 : totalSendDurationMilliseconds / sendOperationCount,
            maximumSendDurationMilliseconds:
                maximumSendDurationMilliseconds,
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
        acousticEligibilityForwarded = false
        nextResidentAcousticObservationSequence = 1
        nextResidentAcousticSnapshotPollNanoseconds = 0
        lastResidentCaptureFrameIndex = 0
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
