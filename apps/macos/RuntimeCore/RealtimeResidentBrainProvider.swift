import Foundation

nonisolated enum RealtimeResidentBrainError: Error, Sendable, Equatable {
    case unavailable
    case invalidIdentity
    case invalidContextRevision
    case invalidAudioFrame
    case operationInFlight
    case invalidEvent
    case timedOut
    case cancelled
    case transportFailure
    case providerFailure
}

nonisolated struct RealtimeBrainSessionIdentity: Hashable, Sendable {
    let residentID: String
    let runtimeSessionID: String
    let brainLeaseID: UUID
    let routeEpoch: UInt64
    let generation: UInt64
}

nonisolated struct RealtimeBrainTurnID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct RealtimeBrainResponseID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct RealtimeBrainToolCallID: Hashable, Sendable {
    let rawValue: String
}

nonisolated struct RealtimeBrainToolAdvertisement: Sendable, Equatable {
    let name: String
    let description: String
    let parametersJSON: Data
}

nonisolated struct RealtimeBrainOpenSessionCommand: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
    let tools: [RealtimeBrainToolAdvertisement]

    init(
        identity: RealtimeBrainSessionIdentity,
        tools: [RealtimeBrainToolAdvertisement] = []
    ) {
        self.identity = identity
        self.tools = tools
    }
}

nonisolated enum RealtimeBrainContextUpdateKind:
    String,
    Sendable,
    Equatable {
    case bootstrap
    case delta
}

nonisolated enum RealtimeBrainContextScope:
    String,
    Hashable,
    Sendable {
    case stableResident
    case dynamicSession
    case memoryDelta
    case relationshipDelta
    case toolResultContext
}

nonisolated struct RealtimeBrainContextSection: Sendable, Equatable {
    let scope: RealtimeBrainContextScope
    let content: String
}

nonisolated struct RealtimeBrainRuntimeContextUpdate:
    Sendable,
    Equatable {
    let identity: RealtimeBrainSessionIdentity
    let kind: RealtimeBrainContextUpdateKind
    let contextRevision: UInt64
    let sections: [RealtimeBrainContextSection]
}

nonisolated enum RealtimeBrainPCMEncoding: String, Sendable, Equatable {
    case pcm16LittleEndian
}

nonisolated struct RealtimeBrainAudioFormat: Sendable, Equatable {
    let encoding: RealtimeBrainPCMEncoding
    let sampleRate: Int
    let channelCount: Int
}

nonisolated enum RealtimeBrainAudioProvenance:
    String,
    Sendable,
    Equatable {
    case microphoneCapture
    case acousticEchoProcessed
    case voiceProcessed
    case providerGenerated
}

nonisolated struct RealtimeBrainAudioFrame: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
    let sequence: UInt64
    let timestampNanoseconds: UInt64
    let format: RealtimeBrainAudioFormat
    let provenance: RealtimeBrainAudioProvenance
    let bytes: Data
}

nonisolated struct RealtimeBrainAudioDelta: Sendable, Equatable {
    let sequence: UInt64
    let timestampNanoseconds: UInt64
    let format: RealtimeBrainAudioFormat
    let provenance: RealtimeBrainAudioProvenance
    let bytes: Data
}

nonisolated struct RealtimeBrainEventIdentity: Hashable, Sendable {
    let session: RealtimeBrainSessionIdentity
    let turnID: RealtimeBrainTurnID?
    let responseID: RealtimeBrainResponseID?
    let contextRevision: UInt64
}

nonisolated struct RealtimeBrainNarrativeMemoryCandidate:
    Sendable,
    Equatable {
    let identity: RealtimeBrainEventIdentity
    let candidateID: String
    let memoryType: String
    let summary: String
    let sourceTurnIDs: [String]
    let consentSignal: String
    let sensitivityFlags: [String]
    let evidenceSource: String
    let inputClassification: String
    let confidence: Double
}

nonisolated struct RealtimeBrainRelationshipEvidenceCandidate:
    Sendable,
    Equatable {
    let identity: RealtimeBrainEventIdentity
    let evidenceType: String
    let evidenceDetected: Bool
    let evidenceSource: String
    let requiresUserConfirmation: Bool
    let confidence: Double
}

nonisolated struct RealtimeBrainGrowthObservationCandidate:
    Sendable,
    Equatable {
    let identity: RealtimeBrainEventIdentity
    let observation: String
    let confidence: Double
}

nonisolated struct RealtimeBrainSemanticOutput: Sendable, Equatable {
    let canonicalText: String
    let narrativeMemoryCandidates:
        [RealtimeBrainNarrativeMemoryCandidate]
    let relationshipEvidenceCandidates:
        [RealtimeBrainRelationshipEvidenceCandidate]
    let growthObservationCandidates:
        [RealtimeBrainGrowthObservationCandidate]

    init(
        canonicalText: String,
        narrativeMemoryCandidates:
            [RealtimeBrainNarrativeMemoryCandidate] = [],
        relationshipEvidenceCandidates:
            [RealtimeBrainRelationshipEvidenceCandidate] = [],
        growthObservationCandidates:
            [RealtimeBrainGrowthObservationCandidate] = []
    ) {
        self.canonicalText = canonicalText
        self.narrativeMemoryCandidates = narrativeMemoryCandidates
        self.relationshipEvidenceCandidates =
            relationshipEvidenceCandidates
        self.growthObservationCandidates = growthObservationCandidates
    }
}

nonisolated struct RealtimeBrainToolCallCandidate: Sendable, Equatable {
    let identity: RealtimeBrainEventIdentity
    let callID: RealtimeBrainToolCallID
    let toolName: String
    let arguments: Data
}

nonisolated struct RealtimeBrainInterruptionProposal:
    Sendable,
    Equatable {
    let identity: RealtimeBrainEventIdentity
    let reason: String
}

nonisolated struct RealtimeBrainToolResultCommand: Sendable, Equatable {
    let identity: RealtimeBrainEventIdentity
    let sequence: UInt64
    let callID: RealtimeBrainToolCallID
    let output: String
    let isError: Bool
}

nonisolated enum RealtimeBrainCancellationReason:
    String,
    Sendable,
    Equatable {
    case stopped
    case interrupted
    case superseded
    case sessionReplaced
    case runtimeDecision
}

nonisolated struct RealtimeBrainCancelGenerationCommand:
    Sendable,
    Equatable {
    let identity: RealtimeBrainSessionIdentity
    let nextGeneration: UInt64
    let reason: RealtimeBrainCancellationReason
}

nonisolated enum RealtimeBrainInterruptReason:
    String,
    Sendable,
    Equatable {
    case runtimeDecision
    case sessionClosing
    case sessionReplaced
}

nonisolated struct RealtimeBrainInterruptCommand: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
    let nextGeneration: UInt64
    let reason: RealtimeBrainInterruptReason
}

nonisolated struct RealtimeBrainCloseSessionCommand: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
}

nonisolated enum RealtimeResidentBrainEventKind: Sendable, Equatable {
    case sessionReady
    case sessionClosed
    // Recoverable response error. Terminal session failure is thrown by receiveEvent.
    case error(RealtimeResidentBrainError)
    case userSpeechStarted
    case userSpeechStopped
    case userTranscriptPartial(String)
    case userTranscriptFinal(String)
    case residentTextDelta(String)
    case residentTextFinal(String)
    case residentAudioDelta(RealtimeBrainAudioDelta)
    case residentSpeakingStarted
    case residentSpeakingStopped
    case residentSemanticFinal(RealtimeBrainSemanticOutput)
    case toolCall(RealtimeBrainToolCallCandidate)
    case interruptionProposed(RealtimeBrainInterruptionProposal)
    case cancelled(RealtimeBrainCancellationReason)
}

nonisolated struct RealtimeResidentBrainEvent: Sendable, Equatable {
    let identity: RealtimeBrainEventIdentity
    let sequence: UInt64
    let kind: RealtimeResidentBrainEventKind
}

nonisolated protocol RealtimeResidentBrainProvider: Sendable {
    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws
    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws
    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws
    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws
    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws
    func interrupt(_ command: RealtimeBrainInterruptCommand) async throws
    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent
    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws
}

nonisolated enum RealtimeBrainEventDisposition: Sendable, Equatable {
    case accepted(RealtimeResidentBrainEvent)
    case rejectedStale
    case rejectedDuplicate
    case rejectedOutOfOrder
    case rejectedBufferOverflow
    case deferredOutOfOrder
    case rejectedClosed
    case rejectedInvalidIdentity
    case rejectedInvalidEvent
    case rejectedContextTransition
    case rejectedReceiveInFlight
}

nonisolated enum RuntimeRealtimeBrainSessionLifecycle:
    Sendable,
    Equatable {
    case opening
    case awaitingBootstrap
    case active
    case transitioningGeneration
    case closing
    case closed
}

nonisolated enum RuntimeRealtimeBrainProviderCloseOutcome:
    Sendable,
    Equatable {
    case closed
    case failed(RealtimeResidentBrainError)
}

nonisolated enum RuntimeRealtimeBrainProviderCloseClaim:
    Sendable,
    Equatable {
    case perform(UUID, [RealtimeBrainSessionIdentity])
    case wait(UUID)
    case closed
    case invalid
}

nonisolated enum RuntimeRealtimeBrainAudioInputStart:
    Sendable,
    Equatable {
    case accepted(UUID)
    case busy
    case invalid
}

nonisolated enum RuntimeRealtimeBrainReceiveStart:
    Sendable,
    Equatable {
    case provider(UUID)
    case buffered(RealtimeResidentBrainEvent)
    case rejected(RealtimeBrainEventDisposition)
}

nonisolated struct RuntimeRealtimeBrainSemanticFinalKey:
    Hashable,
    Sendable {
    let turnID: RealtimeBrainTurnID
    let responseID: RealtimeBrainResponseID
}

nonisolated final class RuntimeRealtimeBrainProviderOperationGate:
    @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: Set<UUID> = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func begin(_ token: UUID) {
        lock.withLock {
            _ = tokens.insert(token)
        }
    }

    func finish(_ token: UUID) {
        let continuations: [CheckedContinuation<Void, Never>] =
            lock.withLock {
                guard tokens.remove(token) != nil,
                      tokens.isEmpty else { return [] }
                let continuations = waiters
                waiters.removeAll(keepingCapacity: true)
                return continuations
            }
        continuations.forEach { $0.resume() }
    }

    func waitForAll() async {
        await withCheckedContinuation { continuation in
            let resumesImmediately = lock.withLock {
                guard !tokens.isEmpty else { return true }
                waiters.append(continuation)
                return false
            }
            if resumesImmediately {
                continuation.resume()
            }
        }
    }
}

nonisolated final class RuntimeRealtimeBrainSessionGate:
    @unchecked Sendable {
    private static let deferredEventCapacity = 16

    private let lock = NSLock()
    private let providerOperations =
        RuntimeRealtimeBrainProviderOperationGate()
    private var identity: RealtimeBrainSessionIdentity?
    private var lifecycle = RuntimeRealtimeBrainSessionLifecycle.closed
    private var contextRevision: UInt64 = 0
    private var lastAcceptedEventSequence: UInt64 = 0
    private var deferredEvents: [UInt64: RealtimeResidentBrainEvent] = [:]
    private var receiveToken: UUID?
    private var contextUpdateToken: UUID?
    private var pendingContextUpdate: RealtimeBrainRuntimeContextUpdate?
    private var audioInputToken: UUID?
    private var pendingAudioInput: RealtimeBrainAudioFrame?
    private var lastAudioInputSequence: UInt64 = 0
    private var lastAudioInputTimestamp: UInt64 = 0
    private var audioInputSinceStableBoundary = false
    private var lastAudioOutputSequence: UInt64 = 0
    private var lastAudioOutputTimestamp: UInt64 = 0
    private var semanticFinals:
        Set<RuntimeRealtimeBrainSemanticFinalKey> = []
    private var activeTurnIDs: Set<RealtimeBrainTurnID> = []
    private var activeResponseIDs:
        Set<RuntimeRealtimeBrainSemanticFinalKey> = []
    private var terminalTurnIDs: Set<RealtimeBrainTurnID> = []
    private var terminalResponseIDs:
        Set<RuntimeRealtimeBrainSemanticFinalKey> = []
    private var toolResultToken: UUID?
    private var pendingToolResult: RealtimeBrainToolResultCommand?
    private var lastToolResultSequence: UInt64 = 0
    private var toolCandidates:
        [RealtimeBrainToolCallID: RealtimeBrainEventIdentity] = [:]
    private var completedToolCalls: Set<RealtimeBrainToolCallID> = []
    private var generationTransitionToken: UUID?
    private var pendingGenerationIdentity: RealtimeBrainSessionIdentity?
    private var closeIdentityCandidates: [RealtimeBrainSessionIdentity] = []
    private var closeAttemptID: UUID?
    private var closeWaiters:
        [UUID: [CheckedContinuation<
            RuntimeRealtimeBrainProviderCloseOutcome,
            Never
        >]] = [:]
    private var closeWaiterClaimCounts: [UUID: Int] = [:]
    private var completedCloseOutcomes:
        [UUID: RuntimeRealtimeBrainProviderCloseOutcome] = [:]
    private var closedIdentity: RealtimeBrainSessionIdentity?

    func reserve(_ identity: RealtimeBrainSessionIdentity) -> Bool {
        lock.withLock {
            guard self.identity == nil else { return false }
            self.identity = identity
            lifecycle = .opening
            resetSessionStateLocked()
            closedIdentity = nil
            return true
        }
    }

    func activate(_ identity: RealtimeBrainSessionIdentity) -> Bool {
        lock.withLock {
            guard self.identity == identity,
                  lifecycle == .opening else { return false }
            lifecycle = .awaitingBootstrap
            return true
        }
    }

    func isActive(_ identity: RealtimeBrainSessionIdentity) -> Bool {
        lock.withLock {
            isReadyLocked(identity)
        }
    }

    func isCurrent(_ identity: RealtimeBrainEventIdentity) -> Bool {
        lock.withLock {
            isReadyLocked(identity.session)
                && contextRevision == identity.contextRevision
        }
    }

    func beginContextUpdate(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) -> UUID? {
        lock.withLock {
            guard identity == update.identity,
                  contextUpdateToken == nil,
                  receiveToken == nil,
                  audioInputToken == nil,
                  !audioInputSinceStableBoundary,
                  toolResultToken == nil,
                  toolCandidates.isEmpty,
                  activeTurnIDs.isEmpty,
                  activeResponseIDs.isEmpty,
                  deferredEvents.isEmpty,
                  generationTransitionToken == nil,
                  Self.hasUniqueContextScopes(update.sections),
                  update.contextRevision > contextRevision else {
                return nil
            }
            let isValid: Bool
            switch update.kind {
            case .bootstrap:
                isValid = lifecycle == .awaitingBootstrap
                    && contextRevision == 0
            case .delta:
                isValid = lifecycle == .active
                    && contextRevision > 0
            }
            guard isValid else { return nil }
            let token = UUID()
            contextUpdateToken = token
            pendingContextUpdate = update
            providerOperations.begin(token)
            return token
        }
    }

    func finishContextUpdate(
        token: UUID,
        update: RealtimeBrainRuntimeContextUpdate,
        succeeded: Bool
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard contextUpdateToken == token,
                  pendingContextUpdate == update else {
                return false
            }
            contextUpdateToken = nil
            pendingContextUpdate = nil
            guard succeeded,
                  identity == update.identity,
                  update.contextRevision > contextRevision else {
                return false
            }
            switch update.kind {
            case .bootstrap:
                guard lifecycle == .awaitingBootstrap,
                      contextRevision == 0 else { return false }
                lifecycle = .active
            case .delta:
                guard lifecycle == .active,
                      contextRevision > 0 else { return false }
            }
            contextRevision = update.contextRevision
            return true
        }
    }

    func beginAudioInput(
        _ frame: RealtimeBrainAudioFrame
    ) -> RuntimeRealtimeBrainAudioInputStart {
        lock.withLock {
            guard isReadyLocked(frame.identity) else { return .invalid }
            guard audioInputToken == nil else { return .busy }
            guard frame.sequence == lastAudioInputSequence &+ 1,
                  lastAudioInputSequence == 0
                    || frame.timestampNanoseconds
                        >= lastAudioInputTimestamp,
                  Self.isValidPCM(frame.format, bytes: frame.bytes),
                  Self.isInputProvenance(frame.provenance) else {
                return .invalid
            }
            let token = UUID()
            audioInputToken = token
            pendingAudioInput = frame
            providerOperations.begin(token)
            return .accepted(token)
        }
    }

    func finishAudioInput(
        token: UUID,
        frame: RealtimeBrainAudioFrame,
        succeeded: Bool
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard audioInputToken == token,
                  pendingAudioInput == frame else { return false }
            audioInputToken = nil
            pendingAudioInput = nil
            guard succeeded,
                  isReadyLocked(frame.identity) else { return false }
            lastAudioInputSequence = frame.sequence
            lastAudioInputTimestamp = frame.timestampNanoseconds
            audioInputSinceStableBoundary = true
            return true
        }
    }

    func beginToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) -> UUID? {
        lock.withLock {
            guard isReadyLocked(command.identity.session),
                  contextRevision == command.identity.contextRevision,
                  toolResultToken == nil,
                  command.sequence == lastToolResultSequence &+ 1,
                  toolCandidates[command.callID] == command.identity,
                  !completedToolCalls.contains(command.callID) else {
                return nil
            }
            let token = UUID()
            toolResultToken = token
            pendingToolResult = command
            providerOperations.begin(token)
            return token
        }
    }

    func finishToolResult(
        token: UUID,
        command: RealtimeBrainToolResultCommand,
        succeeded: Bool
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard toolResultToken == token,
                  pendingToolResult == command else { return false }
            toolResultToken = nil
            pendingToolResult = nil
            guard succeeded,
                  isReadyLocked(command.identity.session),
                  contextRevision == command.identity.contextRevision else {
                return false
            }
            lastToolResultSequence = command.sequence
            toolCandidates.removeValue(forKey: command.callID)
            completedToolCalls.insert(command.callID)
            if let key = Self.semanticFinalKey(for: command.identity) {
                activeResponseIDs.remove(key)
            }
            return true
        }
    }

    func beginGenerationTransition(
        from current: RealtimeBrainSessionIdentity,
        to next: RealtimeBrainSessionIdentity
    ) -> UUID? {
        lock.withLock {
            guard isReadyLocked(current),
                  generationTransitionToken == nil,
                  current.brainLeaseID == next.brainLeaseID,
                  current.routeEpoch == next.routeEpoch,
                  next.generation > current.generation else {
                return nil
            }
            let token = UUID()
            generationTransitionToken = token
            pendingGenerationIdentity = next
            lifecycle = .transitioningGeneration
            providerOperations.begin(token)
            invalidateInFlightOperationsLocked()
            deferredEvents.removeAll(keepingCapacity: true)
            return token
        }
    }

    func commitGenerationTransition(
        token: UUID,
        from current: RealtimeBrainSessionIdentity,
        to next: RealtimeBrainSessionIdentity
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard generationTransitionToken == token,
                  identity == current,
                  pendingGenerationIdentity == next,
                  lifecycle == .transitioningGeneration else {
                return false
            }
            identity = next
            lifecycle = .active
            generationTransitionToken = nil
            pendingGenerationIdentity = nil
            resetGenerationStateLocked()
            return true
        }
    }

    func cancelGenerationTransition(token: UUID) {
        defer { providerOperations.finish(token) }
        lock.withLock {
            if generationTransitionToken == token {
                generationTransitionToken = nil
            }
        }
    }

    func beginReceiving(
        _ identity: RealtimeBrainSessionIdentity
    ) -> RuntimeRealtimeBrainReceiveStart {
        lock.withLock {
            if let rejection = receptionRejectionLocked(for: identity) {
                return .rejected(rejection)
            }
            let nextSequence = lastAcceptedEventSequence &+ 1
            if let event = deferredEvents.removeValue(
                forKey: nextSequence
            ) {
                guard event.identity.session == identity,
                      event.identity.contextRevision == contextRevision,
                      Self.hasRequiredIdentity(event) else {
                    consumeRejectedSequenceLocked(event)
                    return .rejected(.rejectedInvalidIdentity)
                }
                guard Self.hasStructurallyValidPayload(event),
                      hasStatefullyValidPayloadLocked(event) else {
                    consumeRejectedSequenceLocked(event)
                    return .rejected(.rejectedInvalidEvent)
                }
                commitEventLocked(event)
                return .buffered(event)
            }
            guard receiveToken == nil else {
                return .rejected(.rejectedReceiveInFlight)
            }
            let token = UUID()
            receiveToken = token
            return .provider(token)
        }
    }

    func cancelReceiving(token: UUID) {
        lock.withLock {
            if receiveToken == token {
                receiveToken = nil
            }
        }
    }

    func accept(
        _ event: RealtimeResidentBrainEvent,
        expected identity: RealtimeBrainSessionIdentity,
        token: UUID
    ) -> RealtimeBrainEventDisposition {
        return lock.withLock {
            guard receiveToken == token else {
                return receptionRejectionLocked(for: identity)
                    ?? .rejectedStale
            }
            receiveToken = nil
            guard self.identity == identity,
                  lifecycle == .active,
                  event.identity.session == identity else {
                return closedIdentity == identity
                    ? .rejectedClosed : .rejectedStale
            }
            if event.sequence <= lastAcceptedEventSequence
                || deferredEvents[event.sequence] != nil {
                return .rejectedDuplicate
            }
            let expectedSequence = lastAcceptedEventSequence &+ 1
            if event.sequence != expectedSequence {
                guard deferredEvents.count
                        < Self.deferredEventCapacity else {
                    return .rejectedBufferOverflow
                }
                deferredEvents[event.sequence] = event
                return .deferredOutOfOrder
            }
            guard event.identity.contextRevision == contextRevision,
                  Self.hasRequiredIdentity(event) else {
                consumeRejectedSequenceLocked(event)
                return .rejectedInvalidIdentity
            }
            guard Self.hasStructurallyValidPayload(event) else {
                consumeRejectedSequenceLocked(event)
                return .rejectedInvalidEvent
            }
            guard hasStatefullyValidPayloadLocked(event) else {
                consumeRejectedSequenceLocked(event)
                return .rejectedInvalidEvent
            }
            commitEventLocked(event)
            return .accepted(event)
        }
    }

    func claimClose(
        _ identity: RealtimeBrainSessionIdentity
    ) -> RuntimeRealtimeBrainProviderCloseClaim {
        lock.withLock {
            if closedIdentity == identity {
                return .closed
            }
            guard self.identity == identity else { return .invalid }
            if let closeAttemptID {
                closeWaiterClaimCounts[closeAttemptID, default: 0] += 1
                return .wait(closeAttemptID)
            }
            let attemptID = UUID()
            if closeIdentityCandidates.isEmpty {
                closeIdentityCandidates = [identity]
                if let pendingGenerationIdentity,
                   pendingGenerationIdentity != identity {
                    closeIdentityCandidates.append(
                        pendingGenerationIdentity
                    )
                }
            }
            closeAttemptID = attemptID
            lifecycle = .closing
            generationTransitionToken = nil
            pendingGenerationIdentity = nil
            invalidateInFlightOperationsLocked()
            deferredEvents.removeAll(keepingCapacity: true)
            return .perform(attemptID, closeIdentityCandidates)
        }
    }

    func waitForClose(
        attemptID: UUID
    ) async -> RuntimeRealtimeBrainProviderCloseOutcome {
        await withCheckedContinuation { continuation in
            let immediate: RuntimeRealtimeBrainProviderCloseOutcome? =
                lock.withLock {
                    if let outcome = completedCloseOutcomes[attemptID] {
                        consumeCloseWaiterClaimLocked(attemptID)
                        return outcome
                    }
                    guard closeAttemptID == attemptID else {
                        consumeCloseWaiterClaimLocked(attemptID)
                        return .failed(.invalidIdentity)
                    }
                    closeWaiters[attemptID, default: []].append(
                        continuation
                    )
                    return nil
                }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }

    func finishClose(
        identity: RealtimeBrainSessionIdentity,
        attemptID: UUID,
        outcome: RuntimeRealtimeBrainProviderCloseOutcome
    ) {
        let waiters: [CheckedContinuation<
            RuntimeRealtimeBrainProviderCloseOutcome,
            Never
        >] = lock.withLock {
            guard closeAttemptID == attemptID,
                  self.identity == identity else { return [] }
            let waiters = closeWaiters.removeValue(
                forKey: attemptID
            ) ?? []
            closeAttemptID = nil
            let remainingClaims = max(
                0,
                (closeWaiterClaimCounts[attemptID] ?? 0)
                    - waiters.count
            )
            if remainingClaims > 0 {
                closeWaiterClaimCounts[attemptID] = remainingClaims
                completedCloseOutcomes[attemptID] = outcome
            } else {
                closeWaiterClaimCounts.removeValue(forKey: attemptID)
                completedCloseOutcomes.removeValue(forKey: attemptID)
            }
            if outcome == .closed {
                markClosedLocked(identity)
            } else {
                lifecycle = .closing
            }
            return waiters
        }
        waiters.forEach { $0.resume(returning: outcome) }
    }

    func isClosed(_ identity: RealtimeBrainSessionIdentity) -> Bool {
        lock.withLock { closedIdentity == identity }
    }

    func waitForProviderOperationsToFinish() async {
        await providerOperations.waitForAll()
    }

    private func receptionRejectionLocked(
        for identity: RealtimeBrainSessionIdentity
    ) -> RealtimeBrainEventDisposition? {
        if closedIdentity == identity {
            return .rejectedClosed
        }
        guard self.identity == identity else { return .rejectedStale }
        if lifecycle == .awaitingBootstrap
            || contextUpdateToken != nil {
            return .rejectedContextTransition
        }
        guard lifecycle == .active else { return .rejectedStale }
        return nil
    }

    private func consumeCloseWaiterClaimLocked(_ attemptID: UUID) {
        let remainingClaims = max(
            0,
            (closeWaiterClaimCounts[attemptID] ?? 0) - 1
        )
        if remainingClaims == 0 {
            closeWaiterClaimCounts.removeValue(forKey: attemptID)
            completedCloseOutcomes.removeValue(forKey: attemptID)
        } else {
            closeWaiterClaimCounts[attemptID] = remainingClaims
        }
    }

    private func isReadyLocked(
        _ identity: RealtimeBrainSessionIdentity
    ) -> Bool {
        self.identity == identity
            && lifecycle == .active
            && contextUpdateToken == nil
            && generationTransitionToken == nil
            && closeAttemptID == nil
    }

    private func commitEventLocked(_ event: RealtimeResidentBrainEvent) {
        lastAcceptedEventSequence = event.sequence
        updateOpenTurnLedgerLocked(event)
        switch event.kind {
        case .residentAudioDelta(let audio):
            lastAudioOutputSequence = audio.sequence
            lastAudioOutputTimestamp = audio.timestampNanoseconds
        case .residentSemanticFinal:
            if let key = Self.semanticFinalKey(for: event.identity) {
                _ = semanticFinals.insert(key)
            }
        case .toolCall(let candidate):
            toolCandidates[candidate.callID] = candidate.identity
        default:
            break
        }
    }

    private func consumeRejectedSequenceLocked(
        _ event: RealtimeResidentBrainEvent
    ) {
        guard event.sequence == lastAcceptedEventSequence &+ 1 else {
            return
        }
        lastAcceptedEventSequence = event.sequence
        if case .residentAudioDelta(let audio) = event.kind,
           audio.sequence == lastAudioOutputSequence &+ 1 {
            lastAudioOutputSequence = audio.sequence
            if Self.hasStructurallyValidPayload(event),
               audio.timestampNanoseconds >= lastAudioOutputTimestamp {
                lastAudioOutputTimestamp = audio.timestampNanoseconds
            }
        }
    }

    private func updateOpenTurnLedgerLocked(
        _ event: RealtimeResidentBrainEvent
    ) {
        switch event.kind {
        case .sessionReady:
            break
        case .sessionClosed:
            audioInputSinceStableBoundary = false
            terminalTurnIDs.formUnion(activeTurnIDs)
            terminalResponseIDs.formUnion(activeResponseIDs)
            activeTurnIDs.removeAll(keepingCapacity: true)
            activeResponseIDs.removeAll(keepingCapacity: true)
        case .error, .residentSemanticFinal:
            audioInputSinceStableBoundary = false
            markTurnTerminalLocked(event.identity)
        case .cancelled:
            audioInputSinceStableBoundary = false
            if event.identity.turnID != nil {
                markTurnTerminalLocked(event.identity)
            } else {
                terminalTurnIDs.formUnion(activeTurnIDs)
                terminalResponseIDs.formUnion(activeResponseIDs)
                activeTurnIDs.removeAll(keepingCapacity: true)
                activeResponseIDs.removeAll(keepingCapacity: true)
            }
        case .userSpeechStarted, .userSpeechStopped,
             .userTranscriptPartial, .userTranscriptFinal:
            if let turnID = event.identity.turnID {
                activeTurnIDs.insert(turnID)
            }
        case .residentTextDelta, .residentTextFinal,
             .residentAudioDelta, .residentSpeakingStarted,
             .residentSpeakingStopped, .toolCall,
             .interruptionProposed:
            if let turnID = event.identity.turnID {
                activeTurnIDs.insert(turnID)
            }
            if let responseID = Self.semanticFinalKey(
                for: event.identity
            ) {
                activeResponseIDs.insert(responseID)
            }
        }
    }

    private func markTurnTerminalLocked(
        _ identity: RealtimeBrainEventIdentity
    ) {
        if let turnID = identity.turnID {
            terminalTurnIDs.insert(turnID)
        }
        if let responseID = Self.semanticFinalKey(for: identity) {
            terminalResponseIDs.insert(responseID)
        }
        closeTurnLocked(identity.turnID)
    }

    private func closeTurnLocked(_ turnID: RealtimeBrainTurnID?) {
        guard let turnID else { return }
        activeTurnIDs.remove(turnID)
        activeResponseIDs = Set(
            activeResponseIDs.filter { $0.turnID != turnID }
        )
    }

    private func hasStatefullyValidPayloadLocked(
        _ event: RealtimeResidentBrainEvent
    ) -> Bool {
        if let turnID = event.identity.turnID,
           terminalTurnIDs.contains(turnID) {
            return false
        }
        if let responseID = Self.semanticFinalKey(for: event.identity),
           terminalResponseIDs.contains(responseID) {
            return false
        }
        switch event.kind {
        case .residentAudioDelta(let audio):
            return audio.sequence == lastAudioOutputSequence &+ 1
                && (lastAudioOutputSequence == 0
                    || audio.timestampNanoseconds
                        >= lastAudioOutputTimestamp)
        case .residentSemanticFinal:
            guard let key = Self.semanticFinalKey(
                for: event.identity
            ) else { return false }
            return !semanticFinals.contains(key)
        case .toolCall(let candidate):
            return toolCandidates[candidate.callID] == nil
                && !completedToolCalls.contains(candidate.callID)
        default:
            return true
        }
    }

    private static func hasStructurallyValidPayload(
        _ event: RealtimeResidentBrainEvent
    ) -> Bool {
        switch event.kind {
        case .sessionReady, .sessionClosed, .error, .cancelled,
             .userSpeechStarted, .userSpeechStopped,
             .residentSpeakingStarted, .residentSpeakingStopped:
            return true
        case .userTranscriptPartial(let text),
             .userTranscriptFinal(let text),
             .residentTextDelta(let text),
             .residentTextFinal(let text):
            return !text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        case .residentAudioDelta(let audio):
            return audio.provenance == .providerGenerated
                && Self.isValidPCM(audio.format, bytes: audio.bytes)
        case .residentSemanticFinal(let output):
            return Self.hasValidSemanticOutput(
                output,
                identity: event.identity
            )
        case .toolCall(let candidate):
            return candidate.identity == event.identity
                && !candidate.callID.rawValue.isEmpty
                && !candidate.toolName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        case .interruptionProposed(let proposal):
            return proposal.identity == event.identity
                && !proposal.reason.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        }
    }

    private static func isValidPCM(
        _ format: RealtimeBrainAudioFormat,
        bytes: Data
    ) -> Bool {
        guard format.sampleRate > 0,
              format.channelCount > 0,
              format.channelCount <= 64,
              !bytes.isEmpty else { return false }
        let bytesPerFrame = 2 * format.channelCount
        return bytes.count.isMultiple(of: bytesPerFrame)
    }

    private static func hasUniqueContextScopes(
        _ sections: [RealtimeBrainContextSection]
    ) -> Bool {
        Set(sections.map(\.scope)).count == sections.count
    }

    private static func hasValidSemanticOutput(
        _ output: RealtimeBrainSemanticOutput,
        identity: RealtimeBrainEventIdentity
    ) -> Bool {
        guard !output.canonicalText.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              Set(output.narrativeMemoryCandidates.map(\.candidateID))
                .count == output.narrativeMemoryCandidates.count else {
            return false
        }
        let memoriesAreValid = output.narrativeMemoryCandidates.allSatisfy {
            candidate in
            candidate.identity == identity
                && hasText(candidate.candidateID)
                && hasText(candidate.memoryType)
                && hasText(candidate.summary)
                && !candidate.sourceTurnIDs.isEmpty
                && candidate.sourceTurnIDs.allSatisfy(hasText)
                && hasText(candidate.consentSignal)
                && candidate.sensitivityFlags.allSatisfy(hasText)
                && hasText(candidate.evidenceSource)
                && hasText(candidate.inputClassification)
                && hasValidConfidence(candidate.confidence)
        }
        let relationshipsAreValid =
            output.relationshipEvidenceCandidates.allSatisfy { candidate in
                candidate.identity == identity
                    && hasText(candidate.evidenceType)
                    && hasText(candidate.evidenceSource)
                    && hasValidConfidence(candidate.confidence)
            }
        let growthObservationsAreValid =
            output.growthObservationCandidates.allSatisfy { candidate in
                candidate.identity == identity
                    && hasText(candidate.observation)
                    && hasValidConfidence(candidate.confidence)
            }
        return memoriesAreValid
            && relationshipsAreValid
            && growthObservationsAreValid
    }

    private static func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func hasValidConfidence(_ confidence: Double) -> Bool {
        confidence.isFinite && (0...1).contains(confidence)
    }

    private static func semanticFinalKey(
        for identity: RealtimeBrainEventIdentity
    ) -> RuntimeRealtimeBrainSemanticFinalKey? {
        guard let turnID = identity.turnID,
              let responseID = identity.responseID else { return nil }
        return RuntimeRealtimeBrainSemanticFinalKey(
            turnID: turnID,
            responseID: responseID
        )
    }

    private static func isInputProvenance(
        _ provenance: RealtimeBrainAudioProvenance
    ) -> Bool {
        switch provenance {
        case .microphoneCapture, .acousticEchoProcessed,
             .voiceProcessed:
            return true
        case .providerGenerated:
            return false
        }
    }

    private func invalidateInFlightOperationsLocked() {
        receiveToken = nil
        contextUpdateToken = nil
        pendingContextUpdate = nil
        audioInputToken = nil
        pendingAudioInput = nil
        toolResultToken = nil
        pendingToolResult = nil
    }

    private func resetGenerationStateLocked() {
        lastAcceptedEventSequence = 0
        deferredEvents.removeAll(keepingCapacity: true)
        receiveToken = nil
        lastAudioInputSequence = 0
        lastAudioInputTimestamp = 0
        audioInputSinceStableBoundary = false
        audioInputToken = nil
        pendingAudioInput = nil
        lastAudioOutputSequence = 0
        lastAudioOutputTimestamp = 0
        semanticFinals.removeAll(keepingCapacity: true)
        activeTurnIDs.removeAll(keepingCapacity: true)
        activeResponseIDs.removeAll(keepingCapacity: true)
        terminalTurnIDs.removeAll(keepingCapacity: true)
        terminalResponseIDs.removeAll(keepingCapacity: true)
        toolResultToken = nil
        pendingToolResult = nil
        lastToolResultSequence = 0
        toolCandidates.removeAll(keepingCapacity: true)
        completedToolCalls.removeAll(keepingCapacity: true)
    }

    private func resetSessionStateLocked() {
        contextRevision = 0
        contextUpdateToken = nil
        pendingContextUpdate = nil
        generationTransitionToken = nil
        pendingGenerationIdentity = nil
        closeAttemptID = nil
        closeIdentityCandidates.removeAll(keepingCapacity: true)
        closeWaiters.removeAll(keepingCapacity: true)
        resetGenerationStateLocked()
    }

    private func markClosedLocked(
        _ identity: RealtimeBrainSessionIdentity
    ) {
        self.identity = nil
        lifecycle = .closed
        resetSessionStateLocked()
        closedIdentity = identity
    }

    private static func hasRequiredIdentity(
        _ event: RealtimeResidentBrainEvent
    ) -> Bool {
        let hasTurn = event.identity.turnID != nil
        let hasResponse = event.identity.responseID != nil
        switch event.kind {
        case .sessionReady, .sessionClosed, .cancelled:
            return true
        case .error:
            return hasTurn && hasResponse
        case .userSpeechStarted, .userSpeechStopped,
             .userTranscriptPartial, .userTranscriptFinal:
            return hasTurn
        case .residentTextDelta, .residentTextFinal,
             .residentAudioDelta, .residentSpeakingStarted,
             .residentSpeakingStopped, .residentSemanticFinal:
            return hasTurn && hasResponse
        case .toolCall(let candidate):
            return hasTurn && hasResponse
                && candidate.identity == event.identity
        case .interruptionProposed(let proposal):
            return hasTurn && hasResponse
                && proposal.identity == event.identity
        }
    }
}
