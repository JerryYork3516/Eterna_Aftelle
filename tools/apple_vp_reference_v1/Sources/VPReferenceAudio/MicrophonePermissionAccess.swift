import AVFoundation
import VPReferenceCore

public struct MicrophonePermissionAccess: MicrophonePermissionAccessing {
    public init() {}

    public static func currentStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unavailable
        }
    }

    public func authorizationStatus() async -> MicrophonePermissionStatus {
        Self.currentStatus()
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
