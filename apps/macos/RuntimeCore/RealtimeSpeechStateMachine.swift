import Foundation

nonisolated enum RealtimeSpeechState: String, Sendable, Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

nonisolated enum RealtimeSpeechTransitionReason: String, Sendable, Equatable {
    case interactionStarted = "interaction_started"
    case speechStarted = "speech_started"
    case speechStopped = "speech_stopped"
    case finalTranscript = "final_transcript"
    case providerThinking = "provider_thinking"
    case firstOutputAudio = "first_output_audio"
    case responseCompleted = "response_completed"
    case userStopped = "user_stopped"
    case interrupted
    case superseded
    case providerCancelled = "provider_cancelled"
    case providerFailed = "provider_failed"
    case providerClosed = "provider_closed"
    case speechStopTimedOut = "speech_stop_timed_out"
    case thinkingTimedOut = "thinking_timed_out"
    case speakingTimedOut = "speaking_timed_out"
}

nonisolated enum RealtimeSpeechTurnDetectionSource: String, Sendable, Equatable {
    case none
    case serverVAD = "server_vad"
    case finalTranscript = "final_transcript"
    case providerThinking = "provider_thinking"
}

nonisolated enum RealtimeSpeechTransitionDisposition: String, Sendable, Equatable {
    case applied
    case ignoredDuplicate = "ignored_duplicate"
    case rejectedStale = "rejected_stale"
    case rejectedOutOfOrder = "rejected_out_of_order"
}

nonisolated enum RealtimeSpeechGuardKind: String, Sendable, Equatable {
    case speechStop = "speech_stop"
    case thinkingOutput = "thinking_output"
    case speakingCompletion = "speaking_completion"
}

nonisolated struct RealtimeSpeechStateIdentity: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let residentID: String
    let sessionID: String

    init(interaction: NativeSpeechInteraction) {
        interactionID = interaction.id
        residentID = interaction.residentID
        sessionID = interaction.sessionID
    }
}

nonisolated struct RealtimeSpeechTimeoutConfiguration: Sendable, Equatable {
    let speechStopNanoseconds: UInt64
    let thinkingOutputNanoseconds: UInt64
    let speakingCompletionNanoseconds: UInt64

    static let standard = RealtimeSpeechTimeoutConfiguration(
        speechStopNanoseconds: 30_000_000_000,
        thinkingOutputNanoseconds: 30_000_000_000,
        speakingCompletionNanoseconds: 60_000_000_000
    )
}

nonisolated struct RealtimeSpeechTransitionRecord: Sendable, Equatable {
    let state: RealtimeSpeechState
    let turnNumber: UInt64
    let reason: RealtimeSpeechTransitionReason
}

nonisolated struct RealtimeSpeechStateSnapshot: Sendable, Equatable {
    let state: RealtimeSpeechState
    let currentTurnNumber: UInt64
    let completedTurnCount: UInt64
    let lastTransitionReason: RealtimeSpeechTransitionReason?
    let lastTurnDetectionSource: RealtimeSpeechTurnDetectionSource
    let guardTimeoutTriggered: Bool
    let lastStandardError: String?
    let recentTransitions: [RealtimeSpeechTransitionRecord]

    static let initial = RealtimeSpeechStateSnapshot(
        state: .idle,
        currentTurnNumber: 0,
        completedTurnCount: 0,
        lastTransitionReason: nil,
        lastTurnDetectionSource: .none,
        guardTimeoutTriggered: false,
        lastStandardError: nil,
        recentTransitions: []
    )
}

nonisolated struct RealtimeSpeechTransitionResult: Sendable, Equatable {
    let disposition: RealtimeSpeechTransitionDisposition
    let previousState: RealtimeSpeechState
    let snapshot: RealtimeSpeechStateSnapshot
}

nonisolated struct RealtimeSpeechGuardRequest: Sendable, Equatable {
    let identity: RealtimeSpeechStateIdentity
    let kind: RealtimeSpeechGuardKind
    let generation: UInt64
    let remainingNanoseconds: UInt64
}

nonisolated final class RealtimeSpeechStateMachine: @unchecked Sendable {
    private let lock = NSLock()
    private var timeoutConfiguration: RealtimeSpeechTimeoutConfiguration
    private var identity: RealtimeSpeechStateIdentity?
    private var lastIdentity: RealtimeSpeechStateIdentity?
    private var currentSnapshot = RealtimeSpeechStateSnapshot.initial
    private var transitionHistory: [RealtimeSpeechTransitionRecord] = []
    private var speechIsActive = false
    private var guardKind: RealtimeSpeechGuardKind?
    private var guardDeadlineNanoseconds: UInt64?
    private var guardGeneration: UInt64 = 0

    init(
        timeoutConfiguration: RealtimeSpeechTimeoutConfiguration = .standard
    ) {
        self.timeoutConfiguration = timeoutConfiguration
    }

    @discardableResult
    func start(
        interaction: NativeSpeechInteraction
    ) -> RealtimeSpeechTransitionResult {
        lock.withLock {
            let previous = currentSnapshot.state
            let startedIdentity = RealtimeSpeechStateIdentity(
                interaction: interaction
            )
            identity = startedIdentity
            lastIdentity = startedIdentity
            speechIsActive = false
            clearGuardLocked()
            transitionHistory.removeAll(keepingCapacity: true)
            currentSnapshot = RealtimeSpeechStateSnapshot(
                state: .listening,
                currentTurnNumber: 1,
                completedTurnCount: 0,
                lastTransitionReason: .interactionStarted,
                lastTurnDetectionSource: .none,
                guardTimeoutTriggered: false,
                lastStandardError: nil,
                recentTransitions: []
            )
            recordTransitionLocked()
            return RealtimeSpeechTransitionResult(
                disposition: .applied,
                previousState: previous,
                snapshot: snapshotWithHistoryLocked()
            )
        }
    }

    func transition(
        event: NativeSpeechEvent,
        interaction: NativeSpeechInteraction,
        nowNanoseconds: UInt64
    ) -> RealtimeSpeechTransitionResult {
        lock.withLock {
            let previous = currentSnapshot.state
            let eventIdentity = RealtimeSpeechStateIdentity(
                interaction: interaction
            )
            guard identity == eventIdentity,
                  event.interactionID == eventIdentity.interactionID else {
                return resultLocked(.rejectedStale, previous: previous)
            }

            switch event.kind {
            case .connected, .sessionUpdated, .partialTranscript,
                 .outputText, .toolRequestCandidate:
                return resultLocked(.ignoredDuplicate, previous: previous)
            case .inputSpeechStarted:
                guard currentSnapshot.state == .listening else {
                    return rejectOutOfOrderLocked(previous: previous)
                }
                guard !speechIsActive else {
                    return resultLocked(.ignoredDuplicate, previous: previous)
                }
                speechIsActive = true
                setGuardLocked(
                    .speechStop,
                    timeoutNanoseconds:
                        timeoutConfiguration.speechStopNanoseconds,
                    nowNanoseconds: nowNanoseconds
                )
                applyLocked(
                    state: .listening,
                    reason: .speechStarted,
                    turnDetectionSource: currentSnapshot
                        .lastTurnDetectionSource
                )
                return resultLocked(.applied, previous: previous)
            case .inputSpeechEnded:
                if currentSnapshot.state == .thinking,
                   !speechIsActive {
                    guard currentSnapshot.lastTurnDetectionSource
                            != .serverVAD else {
                        return resultLocked(
                            .ignoredDuplicate,
                            previous: previous
                        )
                    }
                    enterThinkingLocked(
                        reason: .speechStopped,
                        source: .serverVAD,
                        nowNanoseconds: nowNanoseconds
                    )
                    return resultLocked(.applied, previous: previous)
                }
                guard currentSnapshot.state == .listening,
                      speechIsActive else {
                    return rejectOutOfOrderLocked(previous: previous)
                }
                enterThinkingLocked(
                    reason: .speechStopped,
                    source: .serverVAD,
                    nowNanoseconds: nowNanoseconds
                )
                return resultLocked(.applied, previous: previous)
            case .finalTranscript:
                if currentSnapshot.state == .thinking {
                    guard currentSnapshot.lastTurnDetectionSource
                            == .providerThinking else {
                        return resultLocked(
                            .ignoredDuplicate,
                            previous: previous
                        )
                    }
                    enterThinkingLocked(
                        reason: .finalTranscript,
                        source: .finalTranscript,
                        nowNanoseconds: nowNanoseconds
                    )
                    return resultLocked(.applied, previous: previous)
                }
                guard currentSnapshot.state == .listening else {
                    return rejectOutOfOrderLocked(previous: previous)
                }
                enterThinkingLocked(
                    reason: .finalTranscript,
                    source: .finalTranscript,
                    nowNanoseconds: nowNanoseconds
                )
                return resultLocked(.applied, previous: previous)
            case .thinking:
                if currentSnapshot.state == .thinking {
                    return resultLocked(.ignoredDuplicate, previous: previous)
                }
                guard currentSnapshot.state == .listening else {
                    return rejectOutOfOrderLocked(previous: previous)
                }
                enterThinkingLocked(
                    reason: .providerThinking,
                    source: .providerThinking,
                    nowNanoseconds: nowNanoseconds
                )
                return resultLocked(.applied, previous: previous)
            case .outputAudio:
                if currentSnapshot.state == .speaking {
                    return resultLocked(.ignoredDuplicate, previous: previous)
                }
                guard currentSnapshot.state == .thinking else {
                    return rejectOutOfOrderLocked(previous: previous)
                }
                speechIsActive = false
                setGuardLocked(
                    .speakingCompletion,
                    timeoutNanoseconds:
                        timeoutConfiguration.speakingCompletionNanoseconds,
                    nowNanoseconds: nowNanoseconds
                )
                applyLocked(
                    state: .speaking,
                    reason: .firstOutputAudio,
                    turnDetectionSource: currentSnapshot
                        .lastTurnDetectionSource
                )
                return resultLocked(.applied, previous: previous)
            case .responseCompleted:
                if currentSnapshot.state == .listening,
                   currentSnapshot.lastTransitionReason == .responseCompleted {
                    return resultLocked(.ignoredDuplicate, previous: previous)
                }
                guard currentSnapshot.state == .speaking
                        || currentSnapshot.state == .thinking else {
                    return rejectOutOfOrderLocked(previous: previous)
                }
                speechIsActive = false
                clearGuardLocked()
                currentSnapshot = RealtimeSpeechStateSnapshot(
                    state: .listening,
                    currentTurnNumber:
                        currentSnapshot.currentTurnNumber &+ 1,
                    completedTurnCount:
                        currentSnapshot.completedTurnCount &+ 1,
                    lastTransitionReason: .responseCompleted,
                    lastTurnDetectionSource:
                        currentSnapshot.lastTurnDetectionSource,
                    guardTimeoutTriggered: false,
                    lastStandardError: nil,
                    recentTransitions: []
                )
                recordTransitionLocked()
                return resultLocked(.applied, previous: previous)
            case .cancelled:
                return finishLocked(
                    reason: .providerCancelled,
                    error: nil,
                    previous: previous
                )
            case .closed:
                return finishLocked(
                    reason: .providerClosed,
                    error: nil,
                    previous: previous
                )
            case .failed(let error):
                return finishLocked(
                    reason: .providerFailed,
                    error: Self.standardErrorName(error),
                    previous: previous
                )
            }
        }
    }

    @discardableResult
    func stop(
        interactionID: NativeSpeechInteractionID? = nil,
        reason: NativeSpeechCancellationReason
    ) -> RealtimeSpeechTransitionResult {
        lock.withLock {
            let previous = currentSnapshot.state
            if let interactionID,
               (identity ?? lastIdentity)?.interactionID != interactionID {
                return resultLocked(.rejectedStale, previous: previous)
            }
            if identity == nil,
               currentSnapshot.state == .idle {
                guard reason == .stopped,
                      currentSnapshot.lastTransitionReason != .userStopped else {
                    return resultLocked(
                        .ignoredDuplicate,
                        previous: previous
                    )
                }
                currentSnapshot = RealtimeSpeechStateSnapshot(
                    state: .idle,
                    currentTurnNumber: currentSnapshot.currentTurnNumber,
                    completedTurnCount: currentSnapshot.completedTurnCount,
                    lastTransitionReason: .userStopped,
                    lastTurnDetectionSource:
                        currentSnapshot.lastTurnDetectionSource,
                    guardTimeoutTriggered:
                        currentSnapshot.guardTimeoutTriggered,
                    lastStandardError: currentSnapshot.lastStandardError,
                    recentTransitions: []
                )
                return resultLocked(.applied, previous: previous)
            }
            identity = nil
            speechIsActive = false
            clearGuardLocked()
            currentSnapshot = RealtimeSpeechStateSnapshot(
                state: .idle,
                currentTurnNumber: currentSnapshot.currentTurnNumber,
                completedTurnCount: currentSnapshot.completedTurnCount,
                lastTransitionReason: Self.transitionReason(reason),
                lastTurnDetectionSource:
                    currentSnapshot.lastTurnDetectionSource,
                guardTimeoutTriggered:
                    currentSnapshot.guardTimeoutTriggered,
                lastStandardError: currentSnapshot.lastStandardError,
                recentTransitions: []
            )
            if previous != .idle {
                recordTransitionLocked()
            }
            return resultLocked(.applied, previous: previous)
        }
    }

    func reset() {
        lock.withLock {
            identity = nil
            lastIdentity = nil
            speechIsActive = false
            clearGuardLocked()
            currentSnapshot = .initial
            transitionHistory.removeAll(keepingCapacity: true)
        }
    }

    func snapshot() -> RealtimeSpeechStateSnapshot {
        lock.withLock { snapshotWithHistoryLocked() }
    }

    func tracks(_ interaction: NativeSpeechInteraction) -> Bool {
        lock.withLock {
            identity == RealtimeSpeechStateIdentity(interaction: interaction)
        }
    }

    func guardRequest(
        interaction: NativeSpeechInteraction,
        nowNanoseconds: UInt64
    ) -> RealtimeSpeechGuardRequest? {
        lock.withLock {
            let requestedIdentity = RealtimeSpeechStateIdentity(
                interaction: interaction
            )
            guard identity == requestedIdentity,
                  let guardKind,
                  let guardDeadlineNanoseconds else {
                return nil
            }
            return RealtimeSpeechGuardRequest(
                identity: requestedIdentity,
                kind: guardKind,
                generation: guardGeneration,
                remainingNanoseconds:
                    guardDeadlineNanoseconds > nowNanoseconds
                        ? guardDeadlineNanoseconds - nowNanoseconds
                        : 0
            )
        }
    }

    func applyTimeout(
        _ request: RealtimeSpeechGuardRequest
    ) -> RealtimeSpeechTransitionResult {
        lock.withLock {
            let previous = currentSnapshot.state
            guard identity == request.identity,
                  guardKind == request.kind,
                  guardGeneration == request.generation else {
                return resultLocked(.rejectedStale, previous: previous)
            }
            let reason: RealtimeSpeechTransitionReason
            let error: String
            switch request.kind {
            case .speechStop:
                reason = .speechStopTimedOut
                error = "speech_stop_timed_out"
            case .thinkingOutput:
                reason = .thinkingTimedOut
                error = "thinking_output_timed_out"
            case .speakingCompletion:
                reason = .speakingTimedOut
                error = "speaking_completion_timed_out"
            }
            identity = nil
            speechIsActive = false
            clearGuardLocked()
            currentSnapshot = RealtimeSpeechStateSnapshot(
                state: .idle,
                currentTurnNumber: currentSnapshot.currentTurnNumber,
                completedTurnCount: currentSnapshot.completedTurnCount,
                lastTransitionReason: reason,
                lastTurnDetectionSource:
                    currentSnapshot.lastTurnDetectionSource,
                guardTimeoutTriggered: true,
                lastStandardError: error,
                recentTransitions: []
            )
            if previous != .idle {
                recordTransitionLocked()
            }
            return resultLocked(.applied, previous: previous)
        }
    }

    func useTimeoutConfigurationForTesting(
        _ configuration: RealtimeSpeechTimeoutConfiguration
    ) {
        lock.withLock {
            guard identity == nil else { return }
            timeoutConfiguration = configuration
        }
    }

    private func enterThinkingLocked(
        reason: RealtimeSpeechTransitionReason,
        source: RealtimeSpeechTurnDetectionSource,
        nowNanoseconds: UInt64
    ) {
        speechIsActive = false
        setGuardLocked(
            .thinkingOutput,
            timeoutNanoseconds:
                timeoutConfiguration.thinkingOutputNanoseconds,
            nowNanoseconds: nowNanoseconds
        )
        applyLocked(
            state: .thinking,
            reason: reason,
            turnDetectionSource: source
        )
    }

    private func applyLocked(
        state: RealtimeSpeechState,
        reason: RealtimeSpeechTransitionReason,
        turnDetectionSource: RealtimeSpeechTurnDetectionSource
    ) {
        let previous = currentSnapshot.state
        currentSnapshot = RealtimeSpeechStateSnapshot(
            state: state,
            currentTurnNumber: currentSnapshot.currentTurnNumber,
            completedTurnCount: currentSnapshot.completedTurnCount,
            lastTransitionReason: reason,
            lastTurnDetectionSource: turnDetectionSource,
            guardTimeoutTriggered: false,
            lastStandardError: nil,
            recentTransitions: []
        )
        if previous != state {
            recordTransitionLocked()
        }
    }

    private func finishLocked(
        reason: RealtimeSpeechTransitionReason,
        error: String?,
        previous: RealtimeSpeechState
    ) -> RealtimeSpeechTransitionResult {
        identity = nil
        speechIsActive = false
        clearGuardLocked()
        currentSnapshot = RealtimeSpeechStateSnapshot(
            state: .idle,
            currentTurnNumber: currentSnapshot.currentTurnNumber,
            completedTurnCount: currentSnapshot.completedTurnCount,
            lastTransitionReason: reason,
            lastTurnDetectionSource:
                currentSnapshot.lastTurnDetectionSource,
            guardTimeoutTriggered: false,
            lastStandardError: error,
            recentTransitions: []
        )
        if previous != .idle {
            recordTransitionLocked()
        }
        return resultLocked(.applied, previous: previous)
    }

    private func rejectOutOfOrderLocked(
        previous: RealtimeSpeechState
    ) -> RealtimeSpeechTransitionResult {
        currentSnapshot = RealtimeSpeechStateSnapshot(
            state: currentSnapshot.state,
            currentTurnNumber: currentSnapshot.currentTurnNumber,
            completedTurnCount: currentSnapshot.completedTurnCount,
            lastTransitionReason: currentSnapshot.lastTransitionReason,
            lastTurnDetectionSource:
                currentSnapshot.lastTurnDetectionSource,
            guardTimeoutTriggered: currentSnapshot.guardTimeoutTriggered,
            lastStandardError: "invalid_state_transition",
            recentTransitions: []
        )
        return resultLocked(.rejectedOutOfOrder, previous: previous)
    }

    private func resultLocked(
        _ disposition: RealtimeSpeechTransitionDisposition,
        previous: RealtimeSpeechState
    ) -> RealtimeSpeechTransitionResult {
        RealtimeSpeechTransitionResult(
            disposition: disposition,
            previousState: previous,
            snapshot: snapshotWithHistoryLocked()
        )
    }

    private func recordTransitionLocked() {
        guard let reason = currentSnapshot.lastTransitionReason else { return }
        transitionHistory.append(
            RealtimeSpeechTransitionRecord(
                state: currentSnapshot.state,
                turnNumber: currentSnapshot.currentTurnNumber,
                reason: reason
            )
        )
        if transitionHistory.count > 16 {
            transitionHistory.removeFirst(transitionHistory.count - 16)
        }
    }

    private func snapshotWithHistoryLocked() -> RealtimeSpeechStateSnapshot {
        RealtimeSpeechStateSnapshot(
            state: currentSnapshot.state,
            currentTurnNumber: currentSnapshot.currentTurnNumber,
            completedTurnCount: currentSnapshot.completedTurnCount,
            lastTransitionReason: currentSnapshot.lastTransitionReason,
            lastTurnDetectionSource: currentSnapshot.lastTurnDetectionSource,
            guardTimeoutTriggered: currentSnapshot.guardTimeoutTriggered,
            lastStandardError: currentSnapshot.lastStandardError,
            recentTransitions: transitionHistory
        )
    }

    private func setGuardLocked(
        _ kind: RealtimeSpeechGuardKind,
        timeoutNanoseconds: UInt64,
        nowNanoseconds: UInt64
    ) {
        guardGeneration &+= 1
        guardKind = kind
        guardDeadlineNanoseconds = nowNanoseconds &+ timeoutNanoseconds
    }

    private func clearGuardLocked() {
        guardGeneration &+= 1
        guardKind = nil
        guardDeadlineNanoseconds = nil
    }

    private static func transitionReason(
        _ reason: NativeSpeechCancellationReason
    ) -> RealtimeSpeechTransitionReason {
        switch reason {
        case .stopped: .userStopped
        case .interrupted: .interrupted
        case .superseded: .superseded
        }
    }

    private static func standardErrorName(
        _ error: NativeSpeechError
    ) -> String {
        switch error {
        case .invalidConfiguration: "invalid_configuration"
        case .missingCredential: "missing_credential"
        case .unauthorized: "unauthorized"
        case .rateLimited: "rate_limited"
        case .unavailable: "unavailable"
        case .timedOut: "timed_out"
        case .cancelled: "cancelled"
        case .transportFailure: "transport_failure"
        case .invalidEvent: "invalid_event"
        case .interactionMismatch: "interaction_mismatch"
        }
    }
}

nonisolated final class RealtimeSpeechGuardScheduler: @unchecked Sendable {
    typealias TimeoutHandler = @Sendable (
        RealtimeSpeechGuardRequest
    ) async -> Void

    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func schedule(
        _ request: RealtimeSpeechGuardRequest?,
        timeout: @escaping TimeoutHandler
    ) {
        let previousTask = lock.withLock { () -> Task<Void, Never>? in
            let previousTask = task
            task = request.map { request in
                Task {
                    do {
                        try await Task.sleep(
                            nanoseconds: request.remainingNanoseconds
                        )
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await timeout(request)
                }
            }
            return previousTask
        }
        previousTask?.cancel()
    }

    func cancel() {
        let previousTask = lock.withLock { () -> Task<Void, Never>? in
            defer { task = nil }
            return task
        }
        previousTask?.cancel()
    }
}
