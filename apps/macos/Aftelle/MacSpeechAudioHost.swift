@preconcurrency import AVFoundation
import Foundation

nonisolated enum MicrophoneAuthorizationState: String, Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case failed
}

nonisolated enum MacSpeechAudioHostState: String, Sendable, Equatable {
    case idle
    case permissionRequired
    case ready
    case denied
    case restricted
    case failed
}

nonisolated struct MacSpeechAudioHostSnapshot: Sendable, Equatable {
    let authorization: MicrophoneAuthorizationState
    let state: MacSpeechAudioHostState

    static let initial = MacSpeechAudioHostSnapshot(
        authorization: .notDetermined,
        state: .idle
    )
}

nonisolated protocol MicrophoneAuthorizationProviding: Sendable {
    func currentAuthorization() async throws -> MicrophoneAuthorizationState
    func requestAuthorization() async throws -> MicrophoneAuthorizationState
}

nonisolated struct SystemMicrophoneAuthorizationProvider:
    MicrophoneAuthorizationProviding
{
    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        authorizationState(
            for: AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        let current = authorizationState(
            for: AVCaptureDevice.authorizationStatus(for: .audio)
        )
        if current == .notDetermined {
            return granted ? .authorized : .denied
        }
        return current
    }

    private func authorizationState(
        for status: AVAuthorizationStatus
    ) -> MicrophoneAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .failed
        }
    }
}

actor MacSpeechAudioHost {
    private let authorizationProvider: any MicrophoneAuthorizationProviding
    private var permissionRequestInFlight = false
    private var snapshot = MacSpeechAudioHostSnapshot.initial

    init(
        authorizationProvider: any MicrophoneAuthorizationProviding =
            SystemMicrophoneAuthorizationProvider()
    ) {
        self.authorizationProvider = authorizationProvider
    }

    func currentSnapshot() -> MacSpeechAudioHostSnapshot {
        snapshot
    }

    func refreshAuthorization() async -> MacSpeechAudioHostSnapshot {
        do {
            return update(
                authorization: try await authorizationProvider
                    .currentAuthorization()
            )
        } catch {
            return fail()
        }
    }

    func requestMicrophoneAuthorization() async -> MacSpeechAudioHostSnapshot {
        guard !permissionRequestInFlight else { return snapshot }
        permissionRequestInFlight = true
        defer { permissionRequestInFlight = false }

        do {
            let current = try await authorizationProvider.currentAuthorization()
            guard current == .notDetermined else {
                return update(authorization: current)
            }
            return update(
                authorization: try await authorizationProvider
                    .requestAuthorization()
            )
        } catch {
            return fail()
        }
    }

    private func update(
        authorization: MicrophoneAuthorizationState
    ) -> MacSpeechAudioHostSnapshot {
        snapshot = MacSpeechAudioHostSnapshot(
            authorization: authorization,
            state: hostState(for: authorization)
        )
        return snapshot
    }

    private func fail() -> MacSpeechAudioHostSnapshot {
        snapshot = MacSpeechAudioHostSnapshot(
            authorization: .failed,
            state: .failed
        )
        return snapshot
    }

    private func hostState(
        for authorization: MicrophoneAuthorizationState
    ) -> MacSpeechAudioHostState {
        switch authorization {
        case .notDetermined:
            return .permissionRequired
        case .authorized:
            return .ready
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .failed:
            return .failed
        }
    }
}
