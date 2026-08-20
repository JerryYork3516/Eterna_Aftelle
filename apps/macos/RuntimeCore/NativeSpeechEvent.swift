import Foundation

nonisolated enum RuntimeToolPermission: String, Sendable, Equatable {
    case permissionFree = "permission_free"
    case requiresPermission = "requires_permission"
}

nonisolated struct NativeSpeechToolTurnIdentity: Hashable, Sendable {
    let interactionID: NativeSpeechInteractionID
    let turnNumber: UInt64
    let turnGeneration: UInt64
}

nonisolated enum RuntimeToolRouteIdentity: Hashable, Sendable {
    case nativeSpeech(NativeSpeechToolTurnIdentity)
    case realtimeResidentBrain(RealtimeBrainEventIdentity)
}

nonisolated struct RuntimeToolCallIdentity: Hashable, Sendable {
    let route: RuntimeToolRouteIdentity
    let callID: String

    init(turn: NativeSpeechToolTurnIdentity, callID: String) {
        route = .nativeSpeech(turn)
        self.callID = callID
    }

    init(
        realtime identity: RealtimeBrainEventIdentity,
        callID: RealtimeBrainToolCallID
    ) {
        route = .realtimeResidentBrain(identity)
        self.callID = callID.rawValue
    }

    var nativeSpeechTurn: NativeSpeechToolTurnIdentity? {
        guard case .nativeSpeech(let turn) = route else { return nil }
        return turn
    }

    var realtimeIdentity: RealtimeBrainEventIdentity? {
        guard case .realtimeResidentBrain(let identity) = route else {
            return nil
        }
        return identity
    }

    var turn: NativeSpeechToolTurnIdentity? { nativeSpeechTurn }
}

nonisolated enum RuntimeToolPermissionRequestState:
    String,
    Sendable,
    Equatable {
    case pending
    case approved
    case denied
    case cancelled
    case unavailable
    case stale
}

nonisolated enum RuntimeToolPermissionDecision:
    String,
    Sendable,
    Equatable {
    case approved
    case denied
    case cancelled
    case unavailable
    case stale
}

nonisolated struct RuntimeToolPermissionRequest: Sendable, Equatable {
    let identity: RuntimeToolCallIdentity
    let toolName: String
    let permission: RuntimeToolPermission
    let displaySummary: String
    let state: RuntimeToolPermissionRequestState
    let correlationHash: String?
}

nonisolated protocol RuntimeToolPermissionResolving: Sendable {
    func resolve(
        _ request: RuntimeToolPermissionRequest
    ) async -> RuntimeToolPermissionDecision
}

nonisolated struct UnavailableRuntimeToolPermissionResolver:
    RuntimeToolPermissionResolving {
    func resolve(
        _ request: RuntimeToolPermissionRequest
    ) async -> RuntimeToolPermissionDecision {
        .unavailable
    }
}

nonisolated struct RuntimeToolDefinition: Sendable, Equatable {
    let name: String
    let description: String
    let parametersJSON: Data
    let permission: RuntimeToolPermission
    let executionTimeout: Duration

    init(
        name: String,
        description: String,
        parametersJSON: Data,
        permission: RuntimeToolPermission,
        executionTimeout: Duration = .seconds(30)
    ) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
        self.permission = permission
        self.executionTimeout = executionTimeout
    }
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

nonisolated struct RuntimeToolExecutionRequest: Sendable, Equatable {
    let identity: RuntimeToolCallIdentity
    let toolName: String
    let arguments: Data
    let correlationHash: String?

    init(
        identity: RuntimeToolCallIdentity,
        toolName: String,
        arguments: Data,
        correlationHash: String?
    ) {
        self.identity = identity
        self.toolName = toolName
        self.arguments = arguments
        self.correlationHash = correlationHash
    }

    init(
        interactionID: NativeSpeechInteractionID,
        turnNumber: UInt64,
        turnGeneration: UInt64,
        callID: String,
        toolName: String,
        arguments: Data,
        correlationHash: String?
    ) {
        self.init(
            identity: RuntimeToolCallIdentity(
                turn: NativeSpeechToolTurnIdentity(
                    interactionID: interactionID,
                    turnNumber: turnNumber,
                    turnGeneration: turnGeneration
                ),
                callID: callID
            ),
            toolName: toolName,
            arguments: arguments,
            correlationHash: correlationHash
        )
    }

    var interactionID: NativeSpeechInteractionID? {
        identity.nativeSpeechTurn?.interactionID
    }

    var turnNumber: UInt64? { identity.nativeSpeechTurn?.turnNumber }
    var turnGeneration: UInt64? {
        identity.nativeSpeechTurn?.turnGeneration
    }
    var callID: String { identity.callID }
}

nonisolated struct NativeSpeechToolOutput: Sendable, Equatable {
    let callID: String
    let output: String
}

nonisolated protocol RuntimeToolExecuting: Sendable {
    func execute(
        _ request: RuntimeToolExecutionRequest
    ) async throws -> String
}

nonisolated struct UnavailableRuntimeToolExecutor: RuntimeToolExecuting {
    func execute(
        _ request: RuntimeToolExecutionRequest
    ) async throws -> String {
        throw RuntimeToolExecutionError.unavailable
    }
}

nonisolated enum RuntimeToolExecutionError: Error, Sendable, Equatable {
    case unavailable
}

typealias NativeSpeechToolPermission = RuntimeToolPermission
typealias NativeSpeechToolCallIdentity = RuntimeToolCallIdentity
typealias NativeSpeechToolPermissionRequestState =
    RuntimeToolPermissionRequestState
typealias NativeSpeechToolPermissionDecision = RuntimeToolPermissionDecision
typealias NativeSpeechToolPermissionRequest = RuntimeToolPermissionRequest
typealias NativeSpeechToolPermissionResolving = RuntimeToolPermissionResolving
typealias UnavailableNativeSpeechToolPermissionResolver =
    UnavailableRuntimeToolPermissionResolver
typealias NativeSpeechToolDefinition = RuntimeToolDefinition
typealias NativeSpeechToolExecutionRequest = RuntimeToolExecutionRequest
typealias NativeSpeechToolExecuting = RuntimeToolExecuting
typealias UnavailableNativeSpeechToolExecutor = UnavailableRuntimeToolExecutor

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
