import Foundation

nonisolated struct MacSpeechRealtimeBrainInputBinding: Sendable, Equatable {
    let session: RealtimeBrainSessionIdentity
    let captureGeneration: UInt64
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
    let runtimeRejectedFrameCount: UInt64
    let sendOperationCount: UInt64
    let averageSendDurationMilliseconds: UInt64
    let maximumSendDurationMilliseconds: UInt64
    let lastError: String?
    let hasActivePump: Bool

    static let initial = MacSpeechRealtimeBrainInputBridgeSnapshot(
        state: .idle,
        sessionShortID: nil,
        forwardedFrameCount: 0,
        runtimeRejectedFrameCount: 0,
        sendOperationCount: 0,
        averageSendDurationMilliseconds: 0,
        maximumSendDurationMilliseconds: 0,
        lastError: nil,
        hasActivePump: false
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

    private let source: any MacSpeechAudioFrameSourcing
    private let sendFrame: SendFrame
    private let stopInput: StopInput
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
    private var runtimeRejectedFrameCount: UInt64 = 0
    private var sendOperationCount: UInt64 = 0
    private var totalSendDurationMilliseconds: UInt64 = 0
    private var maximumSendDurationMilliseconds: UInt64 = 0
    private var nextSubmittedSequence: UInt64 = 1
    private var lastError: String?

    init(
        source: any MacSpeechAudioFrameSourcing,
        sendFrame: @escaping SendFrame,
        stopInput: @escaping StopInput
    ) {
        self.source = source
        self.sendFrame = sendFrame
        self.stopInput = stopInput
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
        runtimeRejectedFrameCount = 0
        sendOperationCount = 0
        totalSendDurationMilliseconds = 0
        maximumSendDurationMilliseconds = 0
        nextSubmittedSequence = 1
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
            runtimeRejectedFrameCount: runtimeRejectedFrameCount,
            sendOperationCount: sendOperationCount,
            averageSendDurationMilliseconds: sendOperationCount == 0
                ? 0 : totalSendDurationMilliseconds / sendOperationCount,
            maximumSendDurationMilliseconds:
                maximumSendDurationMilliseconds,
            lastError: lastError,
            hasActivePump: activeBinding != nil
                && activePumpID != nil
                && pumpTask != nil
        )
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
