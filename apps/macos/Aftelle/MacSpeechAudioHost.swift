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
    case capturing
    case deviceUnavailable
    case denied
    case restricted
    case failed
}

nonisolated struct MacSpeechAudioHostSnapshot: Sendable, Equatable {
    let authorization: MicrophoneAuthorizationState
    let state: MacSpeechAudioHostState
    let isCapturing: Bool
    let inputDevice: MacSpeechAudioDevice
    let outputDevice: MacSpeechAudioDevice
    let actualSampleRate: Double
    let actualChannelCount: UInt32
    let normalizedOutputFormat: String
    let generatedFrameCount: UInt64
    let droppedFrameCount: UInt64
    let rejectedStaleFrameCount: UInt64
    let queuedFrameCount: Int
    let latestActivity: Float
    let lastError: String?

    static let initial = MacSpeechAudioHostSnapshot(
        authorization: .notDetermined,
        state: .idle,
        isCapturing: false,
        inputDevice: .unavailable,
        outputDevice: .unavailable,
        actualSampleRate: 0,
        actualChannelCount: 0,
        normalizedOutputFormat: MacSpeechAudioInputFormat.description,
        generatedFrameCount: 0,
        droppedFrameCount: 0,
        rejectedStaleFrameCount: 0,
        queuedFrameCount: 0,
        latestActivity: 0,
        lastError: nil
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

actor MacSpeechAudioHost: MacSpeechAudioFrameSourcing {
    private let authorizationProvider: any MicrophoneAuthorizationProviding
    private let capture: any MacSpeechAudioCapturing
    private let deviceMonitor: any MacSpeechDeviceRouteMonitoring
    private let frameBuffer: MacSpeechAudioFrameBuffer
    private var permissionRequestInFlight = false
    private var authorization = MicrophoneAuthorizationState.notDetermined
    private var state = MacSpeechAudioHostState.idle
    private var route = MacSpeechDeviceRoute.unavailable
    private var isCapturing = false
    private var isMonitoringRoute = false
    private var generation: UInt64 = 0
    private var preparedGeneration: UInt64?
    private var actualInputFormat = MacSpeechNativeInputFormat(
        sampleRate: 0,
        channelCount: 0
    )
    private var lastError: String?

    init(
        authorizationProvider: any MicrophoneAuthorizationProviding =
            SystemMicrophoneAuthorizationProvider(),
        capture: any MacSpeechAudioCapturing =
            SystemMacSpeechAudioCapture(),
        deviceMonitor: any MacSpeechDeviceRouteMonitoring =
            SystemMacSpeechDeviceMonitor(),
        frameCapacity: Int = MacSpeechAudioInputFormat.frameCapacity
    ) {
        self.authorizationProvider = authorizationProvider
        self.capture = capture
        self.deviceMonitor = deviceMonitor
        frameBuffer = MacSpeechAudioFrameBuffer(capacity: frameCapacity)
    }

    func currentSnapshot() -> MacSpeechAudioHostSnapshot {
        makeSnapshot()
    }

    func interruptionAcousticSnapshot() async
        -> MacSpeechInterruptionAcousticSnapshot? {
        guard let acoustic = capture.acousticEchoSnapshot() else {
            return nil
        }
        return MacSpeechInterruptionAcousticSnapshot(
            sourceGateSequence: acoustic.sourceGateOpenCount,
            nearEndDetected: acoustic.inputClassification == .nearEndSpeech
                || acoustic.inputClassification == .doubleTalk,
            farEndActive: acoustic.isPlaybackActive,
            sourceGateOpen: acoustic.sourceGateOpen,
            renderReferenceConfidence:
                acoustic.sourceAlignmentLocked ? 1 : 0,
            routeStable: state == .capturing && lastError == nil,
            inputDeviceAvailable: route.input.isAvailable,
            outputDeviceAvailable: route.output.isAvailable
        )
    }

    nonisolated func currentAcousticEchoSnapshot()
        -> MacSpeechAcousticEchoSnapshot? {
        capture.acousticEchoSnapshot()
    }

    nonisolated func resetAcousticEchoDiagnostics() {
        capture.resetAcousticEchoDiagnostics()
    }

    func refreshAuthorization() async -> MacSpeechAudioHostSnapshot {
        do {
            update(
                authorization: try await authorizationProvider
                    .currentAuthorization()
            )
            refreshDeviceRoute()
            ensureRouteMonitoring()
            return makeSnapshot()
        } catch {
            return fail()
        }
    }

    func requestMicrophoneAuthorization() async -> MacSpeechAudioHostSnapshot {
        guard !permissionRequestInFlight else { return makeSnapshot() }
        permissionRequestInFlight = true
        defer { permissionRequestInFlight = false }

        do {
            let current = try await authorizationProvider.currentAuthorization()
            guard current == .notDetermined else {
                update(authorization: current)
                refreshDeviceRoute()
                ensureRouteMonitoring()
                return makeSnapshot()
            }
            update(
                authorization: try await authorizationProvider
                    .requestAuthorization()
            )
            refreshDeviceRoute()
            ensureRouteMonitoring()
            return makeSnapshot()
        } catch {
            return fail()
        }
    }

    func startCapture() async -> MacSpeechAudioHostSnapshot {
        guard !isCapturing else { return makeSnapshot() }
        guard let captureGeneration = await prepareCaptureGeneration() else {
            return makeSnapshot()
        }
        return startPreparedCapture(generation: captureGeneration)
    }

    func prepareCaptureGeneration() async -> UInt64? {
        if isCapturing || preparedGeneration != nil {
            stopCapture(lastError: nil)
        }
        do {
            update(
                authorization: try await authorizationProvider
                    .currentAuthorization()
            )
        } catch {
            _ = fail()
            return nil
        }
        refreshDeviceRoute()
        ensureRouteMonitoring()
        guard authorization == .authorized else {
            lastError = "microphone_not_authorized"
            return nil
        }
        guard route.input.isAvailable else {
            state = .deviceUnavailable
            lastError = "input_device_unavailable"
            return nil
        }

        generation &+= 1
        let captureGeneration = generation
        preparedGeneration = captureGeneration
        frameBuffer.begin(generation: captureGeneration)
        state = hostState(for: authorization)
        lastError = nil
        return captureGeneration
    }

    func startPreparedCapture(
        generation captureGeneration: UInt64
    ) -> MacSpeechAudioHostSnapshot {
        guard !isCapturing,
              preparedGeneration == captureGeneration,
              generation == captureGeneration else {
            lastError = "capture_generation_unavailable"
            return makeSnapshot()
        }
        guard authorization == .authorized else {
            frameBuffer.end(generation: captureGeneration)
            preparedGeneration = nil
            lastError = "microphone_not_authorized"
            state = hostState(for: authorization)
            return makeSnapshot()
        }
        guard route.input.isAvailable else {
            frameBuffer.end(generation: captureGeneration)
            preparedGeneration = nil
            state = .deviceUnavailable
            lastError = "input_device_unavailable"
            return makeSnapshot()
        }
        do {
            actualInputFormat = try capture.start(
                generation: captureGeneration,
                frameBuffer: frameBuffer
            )
            preparedGeneration = nil
            isCapturing = true
            state = .capturing
            lastError = nil
        } catch let error as MacSpeechAudioCaptureError {
            frameBuffer.end(generation: captureGeneration)
            preparedGeneration = nil
            capture.stop()
            state = .failed
            lastError = error.rawValue
        } catch {
            frameBuffer.end(generation: captureGeneration)
            preparedGeneration = nil
            capture.stop()
            state = .failed
            lastError = "audio_engine_start_failed"
        }
        return makeSnapshot()
    }

    func cancelPreparedCapture(
        generation captureGeneration: UInt64
    ) -> MacSpeechAudioHostSnapshot {
        guard preparedGeneration == captureGeneration else {
            return makeSnapshot()
        }
        frameBuffer.end(generation: captureGeneration)
        preparedGeneration = nil
        state = hostState(for: authorization)
        lastError = nil
        return makeSnapshot()
    }

    func stopCapture() -> MacSpeechAudioHostSnapshot {
        stopCapture(lastError: nil)
        return makeSnapshot()
    }

    func refreshDeviceRoute() {
        let previousRoute = route
        route = deviceMonitor.currentRoute()
        let inputChanged = previousRoute.input.identifier != route.input.identifier
        let outputChanged = previousRoute.output.identifier
            != route.output.identifier
        if inputChanged || outputChanged {
            capture.routeWillRebuild()
        }
        if isCapturing,
           inputChanged || outputChanged || !route.input.isAvailable {
            stopCapture(
                lastError: route.input.isAvailable
                    ? "audio_route_changed"
                    : "input_device_unavailable"
            )
        } else if !isCapturing {
            state = hostState(for: authorization)
        }
        if inputChanged || outputChanged {
            capture.routeDidRebuild()
        }
    }

    func drainFrames(maxCount: Int) -> [MacSpeechAudioFrame] {
        frameBuffer.drain(maxCount: maxCount)
    }

    func activeCaptureGeneration() -> UInt64? {
        isCapturing ? generation : nil
    }

    func isCaptureGenerationActive(_ generation: UInt64) -> Bool {
        isCapturing && self.generation == generation
    }

    func shutdown() {
        stopCapture(lastError: nil)
        deviceMonitor.stop()
        isMonitoringRoute = false
    }

    private func update(
        authorization: MicrophoneAuthorizationState
    ) {
        if isCapturing, authorization != .authorized {
            stopCapture(lastError: "microphone_authorization_lost")
        }
        self.authorization = authorization
        state = isCapturing && authorization == .authorized
            ? .capturing
            : hostState(for: authorization)
        if authorization != .failed {
            lastError = nil
        }
    }

    private func fail() -> MacSpeechAudioHostSnapshot {
        if isCapturing {
            stopCapture(lastError: "microphone_authorization_failed")
        }
        authorization = .failed
        state = .failed
        lastError = "microphone_authorization_failed"
        return makeSnapshot()
    }

    private func hostState(
        for authorization: MicrophoneAuthorizationState
    ) -> MacSpeechAudioHostState {
        switch authorization {
        case .notDetermined:
            return .permissionRequired
        case .authorized:
            return route.input.isAvailable ? .ready : .deviceUnavailable
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .failed:
            return .failed
        }
    }

    private func stopCapture(lastError: String?) {
        if isCapturing {
            capture.stop()
            frameBuffer.end(generation: generation)
            isCapturing = false
        }
        if let preparedGeneration {
            frameBuffer.end(generation: preparedGeneration)
            self.preparedGeneration = nil
        }
        self.lastError = lastError
        state = hostState(for: authorization)
    }

    private func ensureRouteMonitoring() {
        guard !isMonitoringRoute else { return }
        deviceMonitor.start { [weak self] in
            Task {
                await self?.refreshDeviceRoute()
            }
        }
        isMonitoringRoute = true
    }

    private func makeSnapshot() -> MacSpeechAudioHostSnapshot {
        let stats = frameBuffer.stats()
        return MacSpeechAudioHostSnapshot(
            authorization: authorization,
            state: state,
            isCapturing: isCapturing,
            inputDevice: route.input,
            outputDevice: route.output,
            actualSampleRate: actualInputFormat.sampleRate,
            actualChannelCount: actualInputFormat.channelCount,
            normalizedOutputFormat: MacSpeechAudioInputFormat.description,
            generatedFrameCount: stats.generatedCount,
            droppedFrameCount: stats.droppedCount,
            rejectedStaleFrameCount: stats.rejectedStaleCount,
            queuedFrameCount: stats.queuedCount,
            latestActivity: stats.latestActivity,
            lastError: lastError
        )
    }
}
