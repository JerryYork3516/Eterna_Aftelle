import Foundation

nonisolated enum NativeSpeechCancellationReason: String, Sendable, Equatable {
    case stopped
    case interrupted
    case superseded
}

nonisolated enum NativeSpeechError: Error, Sendable, Equatable {
    case invalidConfiguration
    case missingCredential
    case unauthorized
    case rateLimited
    case unavailable
    case timedOut
    case cancelled
    case transportFailure
    case invalidEvent
    case interactionMismatch
}

nonisolated struct NativeSpeechStartRequest: Sendable, Equatable {
    let interaction: NativeSpeechInteraction
    let profile: NativeSpeechProviderProfile
    let tools: [NativeSpeechToolDefinition]

    init(
        interaction: NativeSpeechInteraction,
        profile: NativeSpeechProviderProfile,
        tools: [NativeSpeechToolDefinition] = []
    ) {
        self.interaction = interaction
        self.profile = profile
        self.tools = tools
    }
}

nonisolated protocol NativeSpeechProvider: Sendable {
    func start(request: NativeSpeechStartRequest) async throws
    func send(audio: NativeSpeechAudioPayload) async throws
    func receive(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEvent
    func cancel(
        interactionID: NativeSpeechInteractionID,
        reason: NativeSpeechCancellationReason
    ) async throws
    func close(interactionID: NativeSpeechInteractionID) async throws
    func submitToolOutput(
        _ output: NativeSpeechToolOutput,
        interactionID: NativeSpeechInteractionID
    ) async throws
    func requestToolContinuation(
        interactionID: NativeSpeechInteractionID
    ) async throws
}

nonisolated extension NativeSpeechProvider {
    func submitToolOutput(
        _ output: NativeSpeechToolOutput,
        interactionID: NativeSpeechInteractionID
    ) async throws {
        throw NativeSpeechError.unavailable
    }

    func requestToolContinuation(
        interactionID: NativeSpeechInteractionID
    ) async throws {
        throw NativeSpeechError.unavailable
    }
}
