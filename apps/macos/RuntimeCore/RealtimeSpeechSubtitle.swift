import Foundation

nonisolated enum RealtimeSpeechSubtitleDirection: String, Sendable, Equatable {
    case user
    case resident
}

nonisolated enum RealtimeSpeechSubtitleContentState: String, Sendable, Equatable {
    case partial
    case final
}

nonisolated enum RealtimeSpeechSubtitleEventKind: String, Sendable, Equatable {
    case userPartialTranscript = "user_partial_transcript"
    case userFinalTranscript = "user_final_transcript"
    case residentPartialTranscript = "resident_partial_transcript"
    case residentFinalTranscript = "resident_final_transcript"
    case interrupted
    case cancelled
    case failed
    case completed
    case closed
}

nonisolated enum RealtimeSpeechSubtitleClosureReason: String, Sendable, Equatable {
    case none
    case interrupted
    case stopped
    case cancelled
    case failed
    case completed
    case closed
    case superseded
}

nonisolated enum RealtimeSpeechSubtitleDisposition: String, Sendable, Equatable {
    case accepted
    case rejectedStale = "rejected_stale"
    case rejectedLate = "rejected_late"
    case rejectedRevision = "rejected_revision"
    case rejectedFinalLocked = "rejected_final_locked"
    case rejectedDuplicate = "rejected_duplicate"
    case rejectedOutOfOrder = "rejected_out_of_order"
}

nonisolated struct RealtimeSpeechSubtitleIdentity: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let turnNumber: UInt64
    let turnGeneration: UInt64
    let direction: RealtimeSpeechSubtitleDirection
    let contentState: RealtimeSpeechSubtitleContentState
}

nonisolated struct RealtimeSpeechSubtitleEvent: Sendable, Equatable {
    let identity: RealtimeSpeechSubtitleIdentity
    let revision: UInt64
    let kind: RealtimeSpeechSubtitleEventKind
    let text: String?
}

nonisolated struct RealtimeSpeechCompletedSubtitle: Sendable, Equatable {
    let interactionShortID: String
    let turnNumber: UInt64
    let turnGeneration: UInt64
    let userFinal: String?
    let residentFinal: String?
}

nonisolated struct RealtimeSpeechSubtitleSnapshot: Sendable, Equatable {
    let interactionShortID: String?
    let turnNumber: UInt64
    let turnGeneration: UInt64
    let userPartial: String?
    let userFinal: String?
    let userPartialRevision: UInt64?
    let userFinalRevision: UInt64?
    let residentPartial: String?
    let residentFinal: String?
    let residentPartialRevision: UInt64?
    let residentFinalRevision: UInt64?
    let userFinalLocked: Bool
    let residentFinalLocked: Bool
    let rejectedEventCount: UInt64
    let lastClosureReason: RealtimeSpeechSubtitleClosureReason
    let lastCompleted: RealtimeSpeechCompletedSubtitle?

    static let initial = RealtimeSpeechSubtitleSnapshot(
        interactionShortID: nil,
        turnNumber: 0,
        turnGeneration: 0,
        userPartial: nil,
        userFinal: nil,
        userPartialRevision: nil,
        userFinalRevision: nil,
        residentPartial: nil,
        residentFinal: nil,
        residentPartialRevision: nil,
        residentFinalRevision: nil,
        userFinalLocked: false,
        residentFinalLocked: false,
        rejectedEventCount: 0,
        lastClosureReason: .none,
        lastCompleted: nil
    )

    var displayText: String? {
        residentPartial
            ?? residentFinal
            ?? userPartial
            ?? userFinal
            ?? lastCompleted?.residentFinal
            ?? lastCompleted?.userFinal
    }
}

nonisolated struct RealtimeSpeechSubtitleUpdateResult: Sendable, Equatable {
    let disposition: RealtimeSpeechSubtitleDisposition
    let event: RealtimeSpeechSubtitleEvent?
    let snapshot: RealtimeSpeechSubtitleSnapshot
}

nonisolated final class RealtimeSpeechSubtitleStateMachine:
    @unchecked Sendable {
    private struct DirectionState {
        var partial: String?
        var final: String?
        var partialRevision: UInt64?
        var finalRevision: UInt64?
        var latestRevision: UInt64 = 0
        var finalLocked = false
    }

    private let lock = NSLock()
    private var interactionID: NativeSpeechInteractionID?
    private var turnNumber: UInt64 = 0
    private var turnGeneration: UInt64 = 0
    private var user = DirectionState()
    private var resident = DirectionState()
    private var carriedUserFinal: String?
    private var rejectedEventCount: UInt64 = 0
    private var lastClosureReason = RealtimeSpeechSubtitleClosureReason.none
    private var lastCompleted: RealtimeSpeechCompletedSubtitle?

    func start(
        interactionID: NativeSpeechInteractionID,
        turnNumber: UInt64
    ) {
        lock.withLock {
            self.interactionID = interactionID
            self.turnNumber = turnNumber
            turnGeneration = 1
            user = DirectionState()
            resident = DirectionState()
            carriedUserFinal = nil
            rejectedEventCount = 0
            lastClosureReason = .none
            lastCompleted = nil
        }
    }

    func applyProviderTranscript(
        interactionID: NativeSpeechInteractionID,
        turnNumber: UInt64,
        direction: RealtimeSpeechSubtitleDirection,
        contentState: RealtimeSpeechSubtitleContentState,
        text: String
    ) -> RealtimeSpeechSubtitleUpdateResult {
        lock.withLock {
            guard self.interactionID == interactionID else {
                return rejectLocked(.rejectedStale)
            }
            guard self.turnNumber == turnNumber else {
                return rejectLocked(.rejectedLate)
            }
            let normalized = text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalized.isEmpty else {
                return rejectLocked(.rejectedOutOfOrder)
            }
            let state = directionStateLocked(direction)
            if state.finalLocked {
                return rejectLocked(.rejectedFinalLocked)
            }
            let currentText = contentState == .partial
                ? state.partial : state.final
            if currentText == normalized {
                return rejectLocked(.rejectedDuplicate)
            }
            let event = RealtimeSpeechSubtitleEvent(
                identity: RealtimeSpeechSubtitleIdentity(
                    interactionID: interactionID,
                    turnNumber: turnNumber,
                    turnGeneration: turnGeneration,
                    direction: direction,
                    contentState: contentState
                ),
                revision: state.latestRevision &+ 1,
                kind: Self.eventKind(
                    direction: direction,
                    contentState: contentState
                ),
                text: normalized
            )
            return applyLocked(event)
        }
    }

    func apply(
        _ event: RealtimeSpeechSubtitleEvent
    ) -> RealtimeSpeechSubtitleUpdateResult {
        lock.withLock { applyLocked(event) }
    }

    func interrupt(
        interactionID: NativeSpeechInteractionID,
        interruptedTurnNumber: UInt64,
        nextTurnNumber: UInt64
    ) -> RealtimeSpeechSubtitleDisposition {
        lock.withLock {
            guard self.interactionID == interactionID else {
                return rejectDispositionLocked(.rejectedStale)
            }
            guard turnNumber == interruptedTurnNumber,
                  nextTurnNumber > interruptedTurnNumber else {
                return rejectDispositionLocked(.rejectedLate)
            }
            carriedUserFinal = user.final
            user = DirectionState()
            resident = DirectionState()
            turnNumber = nextTurnNumber
            turnGeneration &+= 1
            lastClosureReason = .interrupted
            return .accepted
        }
    }

    func completeTurn(
        interactionID: NativeSpeechInteractionID,
        completedTurnNumber: UInt64,
        nextTurnNumber: UInt64
    ) -> RealtimeSpeechSubtitleDisposition {
        lock.withLock {
            guard self.interactionID == interactionID else {
                return rejectDispositionLocked(.rejectedStale)
            }
            guard turnNumber == completedTurnNumber,
                  nextTurnNumber > completedTurnNumber else {
                return rejectDispositionLocked(.rejectedLate)
            }
            let userFinal = user.final ?? carriedUserFinal
            if userFinal != nil || resident.final != nil {
                lastCompleted = RealtimeSpeechCompletedSubtitle(
                    interactionShortID: Self.shortID(interactionID),
                    turnNumber: completedTurnNumber,
                    turnGeneration: turnGeneration,
                    userFinal: userFinal,
                    residentFinal: resident.final
                )
            }
            user = DirectionState()
            resident = DirectionState()
            carriedUserFinal = nil
            turnNumber = nextTurnNumber
            turnGeneration &+= 1
            lastClosureReason = .completed
            return .accepted
        }
    }

    func terminate(
        interactionID: NativeSpeechInteractionID,
        reason: RealtimeSpeechSubtitleClosureReason
    ) -> RealtimeSpeechSubtitleDisposition {
        lock.withLock {
            guard self.interactionID == interactionID else {
                return rejectDispositionLocked(.rejectedStale)
            }
            self.interactionID = nil
            user = DirectionState()
            resident = DirectionState()
            carriedUserFinal = nil
            lastClosureReason = reason
            return .accepted
        }
    }

    func recordRejectedEvent(
        _ disposition: RealtimeSpeechSubtitleDisposition
    ) {
        guard disposition != .accepted else { return }
        lock.withLock { rejectedEventCount &+= 1 }
    }

    func reset() {
        lock.withLock {
            interactionID = nil
            turnNumber = 0
            turnGeneration = 0
            user = DirectionState()
            resident = DirectionState()
            carriedUserFinal = nil
            rejectedEventCount = 0
            lastClosureReason = .none
            lastCompleted = nil
        }
    }

    func snapshot() -> RealtimeSpeechSubtitleSnapshot {
        lock.withLock { snapshotLocked() }
    }

    func tracks(_ interactionID: NativeSpeechInteractionID) -> Bool {
        lock.withLock { self.interactionID == interactionID }
    }

    private func applyLocked(
        _ event: RealtimeSpeechSubtitleEvent
    ) -> RealtimeSpeechSubtitleUpdateResult {
        guard interactionID == event.identity.interactionID else {
            return rejectLocked(.rejectedStale)
        }
        guard turnNumber == event.identity.turnNumber,
              turnGeneration == event.identity.turnGeneration else {
            return rejectLocked(.rejectedLate)
        }
        guard Self.eventMatchesIdentity(event) else {
            return rejectLocked(.rejectedOutOfOrder)
        }
        guard let text = event.text?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !text.isEmpty else {
            return rejectLocked(.rejectedOutOfOrder)
        }
        var state = directionStateLocked(event.identity.direction)
        guard event.revision > state.latestRevision else {
            return rejectLocked(
                event.revision == state.latestRevision
                    ? .rejectedDuplicate : .rejectedRevision
            )
        }
        guard !state.finalLocked else {
            return rejectLocked(.rejectedFinalLocked)
        }

        state.latestRevision = event.revision
        switch event.identity.contentState {
        case .partial:
            state.partial = text
            state.partialRevision = event.revision
        case .final:
            state.partial = nil
            state.partialRevision = nil
            state.final = text
            state.finalRevision = event.revision
            state.finalLocked = true
        }
        setDirectionStateLocked(state, direction: event.identity.direction)
        if event.identity.direction == .user {
            carriedUserFinal = nil
        }
        return RealtimeSpeechSubtitleUpdateResult(
            disposition: .accepted,
            event: event,
            snapshot: snapshotLocked()
        )
    }

    private func rejectLocked(
        _ disposition: RealtimeSpeechSubtitleDisposition
    ) -> RealtimeSpeechSubtitleUpdateResult {
        rejectedEventCount &+= 1
        return RealtimeSpeechSubtitleUpdateResult(
            disposition: disposition,
            event: nil,
            snapshot: snapshotLocked()
        )
    }

    private func rejectDispositionLocked(
        _ disposition: RealtimeSpeechSubtitleDisposition
    ) -> RealtimeSpeechSubtitleDisposition {
        rejectedEventCount &+= 1
        return disposition
    }

    private func directionStateLocked(
        _ direction: RealtimeSpeechSubtitleDirection
    ) -> DirectionState {
        switch direction {
        case .user: user
        case .resident: resident
        }
    }

    private func setDirectionStateLocked(
        _ state: DirectionState,
        direction: RealtimeSpeechSubtitleDirection
    ) {
        switch direction {
        case .user: user = state
        case .resident: resident = state
        }
    }

    private func snapshotLocked() -> RealtimeSpeechSubtitleSnapshot {
        RealtimeSpeechSubtitleSnapshot(
            interactionShortID: interactionID.map(Self.shortID),
            turnNumber: turnNumber,
            turnGeneration: turnGeneration,
            userPartial: user.partial,
            userFinal: user.final ?? carriedUserFinal,
            userPartialRevision: user.partialRevision,
            userFinalRevision: user.finalRevision,
            residentPartial: resident.partial,
            residentFinal: resident.final,
            residentPartialRevision: resident.partialRevision,
            residentFinalRevision: resident.finalRevision,
            userFinalLocked: user.finalLocked,
            residentFinalLocked: resident.finalLocked,
            rejectedEventCount: rejectedEventCount,
            lastClosureReason: lastClosureReason,
            lastCompleted: lastCompleted
        )
    }

    private static func eventKind(
        direction: RealtimeSpeechSubtitleDirection,
        contentState: RealtimeSpeechSubtitleContentState
    ) -> RealtimeSpeechSubtitleEventKind {
        switch (direction, contentState) {
        case (.user, .partial): .userPartialTranscript
        case (.user, .final): .userFinalTranscript
        case (.resident, .partial): .residentPartialTranscript
        case (.resident, .final): .residentFinalTranscript
        }
    }

    private static func eventMatchesIdentity(
        _ event: RealtimeSpeechSubtitleEvent
    ) -> Bool {
        event.kind == eventKind(
            direction: event.identity.direction,
            contentState: event.identity.contentState
        )
    }

    private static func shortID(
        _ interactionID: NativeSpeechInteractionID
    ) -> String {
        String(interactionID.rawValue.uuidString.prefix(8))
    }
}
