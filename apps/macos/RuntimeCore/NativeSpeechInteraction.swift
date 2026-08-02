import Foundation

nonisolated struct NativeSpeechInteractionID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated enum NativeSpeechLifecycleState: Sendable, Equatable {
    case starting
    case active
    case cancelling
    case closed
}

nonisolated struct NativeSpeechInteraction: Sendable, Equatable {
    let id: NativeSpeechInteractionID
    let residentID: String
    let sessionID: String
    let providerProfileID: String
    let lifecycleState: NativeSpeechLifecycleState

    init(
        id: NativeSpeechInteractionID = NativeSpeechInteractionID(),
        residentID: String,
        sessionID: String,
        providerProfileID: String,
        lifecycleState: NativeSpeechLifecycleState = .starting
    ) {
        self.id = id
        self.residentID = residentID
        self.sessionID = sessionID
        self.providerProfileID = providerProfileID
        self.lifecycleState = lifecycleState
    }
}
