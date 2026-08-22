import Foundation

nonisolated enum MacSpeechRealtimeBrainOutputBridgeState:
    String,
    Sendable,
    Equatable {
    case idle
    case running
    case stopped
    case failed
}

nonisolated struct MacSpeechRealtimeBrainOutputBridgeSnapshot:
    Sendable,
    Equatable {
    let state: MacSpeechRealtimeBrainOutputBridgeState
    let sessionShortID: String?
    let acceptedEventCount: UInt64
    let rejectedEventCount: UInt64
    let audioChunkCount: UInt64
    let completedResponseCount: UInt64
    let lastError: String?
    let hasActiveReceiveLoop: Bool

    static let initial = MacSpeechRealtimeBrainOutputBridgeSnapshot(
        state: .idle,
        sessionShortID: nil,
        acceptedEventCount: 0,
        rejectedEventCount: 0,
        audioChunkCount: 0,
        completedResponseCount: 0,
        lastError: nil,
        hasActiveReceiveLoop: false
    )
}

actor MacSpeechRealtimeBrainOutputBridge {
    typealias ReceiveEvent = @Sendable (
        RealtimeBrainSessionIdentity
    ) async -> Result<RealtimeBrainEventDisposition, RealtimeResidentBrainError>
    typealias ConsumeEvent = @MainActor @Sendable (
        RealtimeResidentBrainEvent
    ) async -> Void
    typealias SessionEnded = @MainActor @Sendable (
        RealtimeBrainSessionIdentity,
        RealtimeResidentBrainError?
    ) async -> Void

    private let receiveEvent: ReceiveEvent
    private let consumeEvent: ConsumeEvent
    private let sessionEnded: SessionEnded
    private var receiveTask: Task<Void, Never>?
    private var retiredReceiveTask: Task<Void, Never>?
    private var activeLoopID: UUID?
    private var activeSession: RealtimeBrainSessionIdentity?
    private var suspendedSession: RealtimeBrainSessionIdentity?
    private var finishedAudioResponseID: RealtimeBrainResponseID?
    private var state = MacSpeechRealtimeBrainOutputBridgeState.idle
    private var acceptedEventCount: UInt64 = 0
    private var rejectedEventCount: UInt64 = 0
    private var audioChunkCount: UInt64 = 0
    private var completedResponseCount: UInt64 = 0
    private var lastError: String?

    init(
        receiveEvent: @escaping ReceiveEvent,
        consumeEvent: @escaping ConsumeEvent,
        sessionEnded: @escaping SessionEnded = { _, _ in }
    ) {
        self.receiveEvent = receiveEvent
        self.consumeEvent = consumeEvent
        self.sessionEnded = sessionEnded
    }

    func start(
        session: RealtimeBrainSessionIdentity
    ) -> MacSpeechRealtimeBrainOutputBridgeSnapshot {
        guard activeSession == nil, suspendedSession == nil else {
            return makeSnapshot()
        }
        activeSession = session
        state = .running
        acceptedEventCount = 0
        rejectedEventCount = 0
        audioChunkCount = 0
        completedResponseCount = 0
        finishedAudioResponseID = nil
        lastError = nil
        installReceiveLoop(session: session)
        return makeSnapshot()
    }

    func suspendForGenerationTransition(
        session: RealtimeBrainSessionIdentity
    ) -> MacSpeechRealtimeBrainOutputBridgeSnapshot {
        guard activeSession == session, suspendedSession == nil else {
            return makeSnapshot()
        }
        let task = receiveTask
        task?.cancel()
        retiredReceiveTask = task
        receiveTask = nil
        activeLoopID = nil
        activeSession = nil
        suspendedSession = session
        finishedAudioResponseID = nil
        state = .stopped
        return makeSnapshot()
    }

    func resumeAfterGenerationTransition(
        session: RealtimeBrainSessionIdentity
    ) -> MacSpeechRealtimeBrainOutputBridgeSnapshot {
        guard let previous = suspendedSession, activeSession == nil else {
            return makeSnapshot()
        }
        guard Self.isNextGeneration(session, after: previous) else {
            state = .failed
            lastError = "invalid_identity"
            return makeSnapshot()
        }
        suspendedSession = nil
        activeSession = session
        finishedAudioResponseID = nil
        state = .running
        lastError = nil
        installReceiveLoop(session: session)
        return makeSnapshot()
    }

    func stop(
        expectedSession: RealtimeBrainSessionIdentity? = nil
    ) -> MacSpeechRealtimeBrainOutputBridgeSnapshot {
        let session = activeSession ?? suspendedSession
        guard expectedSession == nil || expectedSession == session else {
            return makeSnapshot()
        }
        let task = receiveTask ?? retiredReceiveTask
        activeSession = nil
        suspendedSession = nil
        receiveTask = nil
        activeLoopID = nil
        finishedAudioResponseID = nil
        task?.cancel()
        retiredReceiveTask = task
        if state != .failed { state = .stopped }
        return makeSnapshot()
    }

    func currentSnapshot() -> MacSpeechRealtimeBrainOutputBridgeSnapshot {
        makeSnapshot()
    }

    private func installReceiveLoop(
        session: RealtimeBrainSessionIdentity
    ) {
        let predecessor = retiredReceiveTask
        retiredReceiveTask = nil
        let loopID = UUID()
        activeLoopID = loopID
        receiveTask = Task { [weak self] in
            await predecessor?.value
            guard !Task.isCancelled else { return }
            await self?.run(session: session, loopID: loopID)
        }
    }

    private func run(
        session: RealtimeBrainSessionIdentity,
        loopID: UUID
    ) async {
        while !Task.isCancelled {
            let result = await receiveEvent(session)
            guard activeSession == session,
                  activeLoopID == loopID else { return }
            switch result {
            case .failure(let error):
                await finish(
                    session: session,
                    loopID: loopID,
                    error: error
                )
                return
            case .success(.accepted(let event)):
                guard event.identity.session == session else {
                    rejectedEventCount &+= 1
                    await finish(
                        session: session,
                        loopID: loopID,
                        error: .invalidIdentity
                    )
                    return
                }
                switch event.kind {
                case .residentAudioDelta:
                    guard let responseID = event.identity.responseID else {
                        rejectedEventCount &+= 1
                        await finish(
                            session: session,
                            loopID: loopID,
                            error: .invalidIdentity
                        )
                        return
                    }
                    if let finishedResponseID = finishedAudioResponseID {
                        if responseID == finishedResponseID {
                            rejectedEventCount &+= 1
                            continue
                        }
                        finishedAudioResponseID = nil
                    }
                    audioChunkCount &+= 1
                case .residentSpeakingStopped:
                    guard let responseID = event.identity.responseID else {
                        rejectedEventCount &+= 1
                        await finish(
                            session: session,
                            loopID: loopID,
                            error: .invalidIdentity
                        )
                        return
                    }
                    completedResponseCount &+= 1
                    finishedAudioResponseID = responseID
                default:
                    break
                }
                acceptedEventCount &+= 1
                await consumeEvent(event)
                guard activeSession == session,
                      activeLoopID == loopID else { return }
                switch event.kind {
                case .sessionClosed:
                    await finish(
                        session: session,
                        loopID: loopID,
                        error: nil
                    )
                    return
                case .residentSemanticFinal:
                    continue
                case .cancelled:
                    finishedAudioResponseID = nil
                    await finish(
                        session: session,
                        loopID: loopID,
                        error: .cancelled
                    )
                    return
                default:
                    continue
                }
            case .success(.rejectedClosed):
                rejectedEventCount &+= 1
                await finish(
                    session: session,
                    loopID: loopID,
                    error: nil
                )
                return
            case .success(.rejectedStale):
                rejectedEventCount &+= 1
                try? await Task.sleep(for: .milliseconds(5))
                continue
            case .success(.rejectedBufferOverflow),
                 .success(.rejectedReceiveInFlight):
                rejectedEventCount &+= 1
                await finish(
                    session: session,
                    loopID: loopID,
                    error: .invalidEvent
                )
                return
            case .success(.rejectedDuplicate),
                 .success(.rejectedOutOfOrder),
                 .success(.deferredOutOfOrder),
                 .success(.rejectedInvalidIdentity),
                 .success(.rejectedInvalidEvent),
                 .success(.rejectedContextTransition):
                rejectedEventCount &+= 1
                continue
            }
        }
    }

    private func finish(
        session: RealtimeBrainSessionIdentity,
        loopID: UUID,
        error: RealtimeResidentBrainError?
    ) async {
        guard activeSession == session,
              activeLoopID == loopID else { return }
        activeSession = nil
        activeLoopID = nil
        receiveTask = nil
        state = error == nil ? .stopped : .failed
        finishedAudioResponseID = nil
        lastError = error.map(Self.standardErrorName)
        await sessionEnded(session, error)
    }

    private func makeSnapshot() -> MacSpeechRealtimeBrainOutputBridgeSnapshot {
        MacSpeechRealtimeBrainOutputBridgeSnapshot(
            state: state,
            sessionShortID: (activeSession ?? suspendedSession).map {
                String($0.brainLeaseID.uuidString.prefix(8))
            },
            acceptedEventCount: acceptedEventCount,
            rejectedEventCount: rejectedEventCount,
            audioChunkCount: audioChunkCount,
            completedResponseCount: completedResponseCount,
            lastError: lastError,
            hasActiveReceiveLoop: activeSession != nil
                && activeLoopID != nil
                && receiveTask != nil
        )
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

    private static func standardErrorName(
        _ error: RealtimeResidentBrainError
    ) -> String {
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
}
