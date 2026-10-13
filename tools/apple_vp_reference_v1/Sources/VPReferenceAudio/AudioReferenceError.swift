import Foundation

public enum AudioReferenceError: Error, CustomStringConvertible {
    case permissionRequired
    case unavailableDevice
    case unsupportedRoute
    case routeChanged
    case unsupportedMaterial
    case materialTooLarge
    case recorderUnavailable
    case evidenceWriteFailed
    case inconsistentRuntimeState
    case sessionAlreadyUsed

    public var description: String {
        switch self {
        case .permissionRequired: return "BLOCKED: manual microphone permission is required"
        case .unavailableDevice: return "BLOCKED: required device state is UNAVAILABLE"
        case .unsupportedRoute: return "BLOCKED: default input must be USB and output must be built-in"
        case .routeChanged: return "INVALID: audio route changed during the run"
        case .unsupportedMaterial: return "BLOCKED: material must be a supported linear PCM file"
        case .materialTooLarge: return "BLOCKED: material exceeds the independent 8 MiB asset budget"
        case .recorderUnavailable: return "BLOCKED: private recorder could not be created"
        case .evidenceWriteFailed: return "INVALID: evidence manifest could not be written"
        case .inconsistentRuntimeState: return "INVALID: running state differs from configured state"
        case .sessionAlreadyUsed: return "BLOCKED: use a new process for each mode"
        }
    }
}
