public enum MicrophonePermissionStatus: String, Codable, Sendable {
    case authorized = "AUTHORIZED"
    case notDetermined = "NOT_DETERMINED"
    case denied = "DENIED"
    case restricted = "RESTRICTED"
    case unavailable = "UNAVAILABLE"
}

public enum MicrophonePermissionFailure: String, Error, Sendable {
    case requestRequired = "MICROPHONE_REQUEST_REQUIRED"
    case denied = "MICROPHONE_DENIED"
    case restricted = "MICROPHONE_RESTRICTED"
    case statusUnavailable = "MICROPHONE_STATUS_UNAVAILABLE"
    case requestAlreadyAttempted = "MICROPHONE_REQUEST_ALREADY_ATTEMPTED"
    case requestDenied = "MICROPHONE_REQUEST_DENIED"
    case requestResultUnconfirmed = "MICROPHONE_REQUEST_RESULT_UNCONFIRMED"
}

public protocol MicrophonePermissionAccessing: Sendable {
    func authorizationStatus() async -> MicrophonePermissionStatus
    func requestAccess() async -> Bool
}

public actor MicrophonePermissionPlan {
    private var requestAttempted = false

    public init() {}

    /// Recording checks permission without presenting a system prompt.
    public static func requireAuthorized(status: MicrophonePermissionStatus) throws {
        switch status {
        case .authorized: return
        case .notDetermined: throw MicrophonePermissionFailure.requestRequired
        case .denied: throw MicrophonePermissionFailure.denied
        case .restricted: throw MicrophonePermissionFailure.restricted
        case .unavailable: throw MicrophonePermissionFailure.statusUnavailable
        }
    }

    /// Call only from the explicit permission command; never from recording or verification.
    public func requestExplicitly(
        using access: any MicrophonePermissionAccessing
    ) async throws -> MicrophonePermissionStatus {
        let status = await access.authorizationStatus()
        if status == .authorized { return status }
        guard status == .notDetermined else {
            try Self.requireAuthorized(status: status)
            return status
        }
        guard !requestAttempted else { throw MicrophonePermissionFailure.requestAlreadyAttempted }
        requestAttempted = true
        let granted = await access.requestAccess()
        let observed = await access.authorizationStatus()
        guard granted else {
            if observed == .denied { throw MicrophonePermissionFailure.denied }
            if observed == .restricted { throw MicrophonePermissionFailure.restricted }
            if observed == .unavailable { throw MicrophonePermissionFailure.statusUnavailable }
            throw MicrophonePermissionFailure.requestDenied
        }
        guard observed != .notDetermined else { throw MicrophonePermissionFailure.requestResultUnconfirmed }
        try Self.requireAuthorized(status: observed)
        return observed
    }
}
