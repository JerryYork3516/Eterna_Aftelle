import Foundation

nonisolated enum NativeSpeechToolPermission: String, Sendable, Equatable {
    case permissionFree = "permission_free"
    case requiresPermission = "requires_permission"
}

nonisolated struct NativeSpeechToolDefinition: Sendable, Equatable {
    let name: String
    let description: String
    let parametersJSON: Data
    let permission: NativeSpeechToolPermission
}

nonisolated struct NativeSpeechToolRequest: Sendable, Equatable {
    let callID: String
    let toolName: String
    let arguments: Data
    let correlationHash: String?

    var requestID: String { callID }

    init(
        callID: String,
        toolName: String,
        arguments: Data,
        correlationHash: String? = nil
    ) {
        self.callID = callID
        self.toolName = toolName
        self.arguments = arguments
        self.correlationHash = correlationHash
    }

    init(
        requestID: String,
        toolName: String,
        arguments: Data,
        correlationHash: String? = nil
    ) {
        self.init(
            callID: requestID,
            toolName: toolName,
            arguments: arguments,
            correlationHash: correlationHash
        )
    }
}

nonisolated struct NativeSpeechToolExecutionRequest: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let turnNumber: UInt64
    let turnGeneration: UInt64
    let callID: String
    let toolName: String
    let arguments: Data
    let correlationHash: String?
}

nonisolated struct NativeSpeechToolOutput: Sendable, Equatable {
    let callID: String
    let output: String
}

nonisolated protocol NativeSpeechToolExecuting: Sendable {
    func execute(
        _ request: NativeSpeechToolExecutionRequest
    ) async throws -> String
}

nonisolated struct UnavailableNativeSpeechToolExecutor:
    NativeSpeechToolExecuting {
    func execute(
        _ request: NativeSpeechToolExecutionRequest
    ) async throws -> String {
        throw NativeSpeechError.unavailable
    }
}

nonisolated enum NativeSpeechEventKind: Sendable, Equatable {
    case connected
    case sessionUpdated
    case inputSpeechStarted
    case inputSpeechEnded
    case partialTranscript(String)
    case finalTranscript(String)
    case thinking
    case outputText(text: String, isFinal: Bool)
    case outputAudio(NativeSpeechAudioPayload)
    case toolRequestCandidate(NativeSpeechToolRequest)
    case responseCompleted
    case turnFailed(NativeSpeechError)
    case cancelled(reason: String?)
    case closed
    case failed(NativeSpeechError)
}

nonisolated struct NativeSpeechEvent: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let kind: NativeSpeechEventKind
}
