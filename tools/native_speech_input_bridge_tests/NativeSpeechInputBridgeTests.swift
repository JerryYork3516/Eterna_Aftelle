@preconcurrency import AVFoundation
import Foundation

private struct BridgeTestCredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "fake-token"
    }
}

private struct AuthorizedMicrophoneProvider:
    MicrophoneAuthorizationProviding
{
    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }
}

private final class FakeBridgeAudioCapture:
    MacSpeechAudioCapturing, @unchecked Sendable
{
    private let lock = NSLock()
    private var frameBuffer: MacSpeechAudioFrameBuffer?
    private var generation: UInt64?
    private var started = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        lock.withLock {
            guard !started else {
                return MacSpeechNativeInputFormat(
                    sampleRate: 48_000,
                    channelCount: 2
                )
            }
            started = true
            startCount += 1
            self.generation = generation
            self.frameBuffer = frameBuffer
            return MacSpeechNativeInputFormat(
                sampleRate: 48_000,
                channelCount: 2
            )
        }
    }

    func stop() {
        lock.withLock {
            guard started else { return }
            started = false
            stopCount += 1
        }
    }

    @discardableResult
    func emit(_ marker: UInt8) -> Bool {
        let target = lock.withLock { (frameBuffer, generation) }
        guard let frameBuffer = target.0, let generation = target.1 else {
            return false
        }
        return frameBuffer.append(
            pcm16Bytes: Data([marker, 0]),
            activity: Float(marker) / 255,
            generation: generation
        )
    }
}

private final class FakeBridgeDeviceMonitor:
    MacSpeechDeviceRouteMonitoring, @unchecked Sendable
{
    private let route = MacSpeechDeviceRoute(
        input: MacSpeechAudioDevice(
            identifier: "fake-input",
            name: "Fake Input",
            isAvailable: true
        ),
        output: MacSpeechAudioDevice(
            identifier: "fake-output",
            name: "Fake Output",
            isAvailable: true
        )
    )

    func currentRoute() -> MacSpeechDeviceRoute { route }
    func start(onChange: @escaping @Sendable () -> Void) {}
    func stop() {}
}

@MainActor
@main
private struct NativeSpeechInputBridgeTests {
    private static var checks = 0
    private static var fixtureData = Data()

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        fixtureData = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        try await testControllerEndToEndAndBoundedOrdering()
        try await testRuntimeGenerationSessionAndSequenceGates()
        try await testSendFailureStopsSinglePump()
        print("native_speech_input_bridge_checks=\(checks)")
    }

    private static func testControllerEndToEndAndBoundedOrdering() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "fixed resident loads through Orchestration"
        )

        await stack.controller.startSpeechAudioCapture()
        expect(
            stack.controller.speechAudioHostSnapshot.isCapturing,
            "AppController starts Fake Audio Host capture"
        )
        for marker in UInt8(1) ... UInt8(12) {
            expect(stack.capture.emit(marker), "Fake Audio Source emits PCM16 frame")
        }
        let bounded = await stack.host.currentSnapshot()
        expect(bounded.queuedFrameCount == 8, "Host queue remains at capacity eight")
        expect(bounded.droppedFrameCount == 4, "Host deterministically drops four oldest frames")

        await stack.controller.startNativeSpeechInputBridge()
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechInputBridgeSnapshot
                .adapterReceivedFrameCount == 8
        }
        let running = stack.controller.speechInputBridgeSnapshot
        expect(running.state == .running, "input bridge is running")
        expect(running.hasActivePump, "one active input pump is visible")
        expect(running.forwardedFrameCount == 8, "eight bounded frames are forwarded")
        expect(running.runtimeRejectedFrameCount == 0, "current frames pass Runtime gate")
        expect(running.interactionShortID?.count == 8, "interaction ID is redacted")

        let appendObjects = try await audioAppendObjects(transport)
        expect(appendObjects.count == 8, "Fake Transport receives eight audio appends")
        let markers = appendObjects.compactMap { object -> UInt8? in
            guard let encoded = object["audio"] as? String,
                  let data = Data(base64Encoded: encoded) else { return nil }
            return data.first
        }
        expect(markers == Array(UInt8(5) ... UInt8(12)), "audio order preserves newest bounded frames")

        await stack.controller.startNativeSpeechInputBridge()
        await stack.controller.refreshMicrophoneAuthorization()
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "duplicate start keeps the existing pump"
        )
        expect(
            try await audioAppendObjects(transport).count == 8,
            "duplicate start creates no second sender"
        )

        await stack.controller.stopSpeechAudioCapture()
        expect(!stack.controller.speechAudioHostSnapshot.isCapturing, "Host stop ends capture")
        expect(!stack.controller.speechInputBridgeSnapshot.hasActivePump, "Host stop ends input pump")
        expect(!stack.capture.emit(13), "stopped generation rejects late Host frame")
        await stack.controller.stopSpeechAudioCapture()
        expect(stack.capture.stopCount == 1, "repeated stop is idempotent")
        expect(
            try await audioAppendObjects(transport).count == 8,
            "stop sends no late audio append"
        )
        let eventTypes = try await sentEventTypes(transport)
        expect(eventTypes.contains("input_audio_buffer.append"), "Adapter emits audio append events")
        expect(!eventTypes.contains("input_audio_buffer.commit"), "bridge sends no audio commit")
        expect(!eventTypes.contains("response.create"), "bridge sends no response.create")
    }

    private static func testRuntimeGenerationSessionAndSequenceGates() async throws {
        let transport = handshakeTransport()
        let runtimeStack = makeRuntimeStack(transport: transport)
        expect(
            runtimeStack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "gate test resident loads"
        )
        let binding = try success(
            await runtimeStack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 41
            )
        )

        let wrongGeneration = try success(
            await runtimeStack.orchestration.sendNativeSpeechInput(
                payload(binding: binding, sequence: 1, marker: 1),
                context: context(binding: binding, generation: 40)
            )
        )
        expect(wrongGeneration == .rejectedStale, "old capture generation is rejected")

        let first = try success(
            await runtimeStack.orchestration.sendNativeSpeechInput(
                payload(binding: binding, sequence: 2, marker: 2),
                context: context(binding: binding, generation: 41)
            )
        )
        expect(first == .forwarded, "valid bound frame is forwarded")
        let duplicate = try success(
            await runtimeStack.orchestration.sendNativeSpeechInput(
                payload(binding: binding, sequence: 2, marker: 2),
                context: context(binding: binding, generation: 41)
            )
        )
        expect(duplicate == .rejectedStale, "duplicate sequence is rejected")
        let regression = try success(
            await runtimeStack.orchestration.sendNativeSpeechInput(
                payload(binding: binding, sequence: 1, marker: 1),
                context: context(binding: binding, generation: 41)
            )
        )
        expect(regression == .rejectedStale, "sequence regression is rejected")

        _ = runtimeStack.orchestration.loadResident(fixtureData: fixtureData)
        let oldSession = try success(
            await runtimeStack.orchestration.sendNativeSpeechInput(
                payload(binding: binding, sequence: 3, marker: 3),
                context: context(binding: binding, generation: 41)
            )
        )
        expect(oldSession == .rejectedStale, "old Runtime session is rejected")
        expect(
            try await audioAppendObjects(transport).count == 1,
            "only the valid sequence reaches Adapter"
        )

        let cancelTransport = handshakeTransport()
        let cancelStack = makeRuntimeStack(transport: cancelTransport)
        _ = cancelStack.orchestration.loadResident(fixtureData: fixtureData)
        let cancelledBinding = try success(
            await cancelStack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 77
            )
        )
        _ = try success(
            await cancelStack.orchestration.stopNativeSpeechInput(
                binding: cancelledBinding,
                reason: .stopped
            )
        )
        _ = try success(
            await cancelStack.orchestration.stopNativeSpeechInput(
                binding: cancelledBinding,
                reason: .stopped
            )
        )
        let cancelledLate = try success(
            await cancelStack.orchestration.sendNativeSpeechInput(
                payload(binding: cancelledBinding, sequence: 1, marker: 9),
                context: context(binding: cancelledBinding, generation: 77)
            )
        )
        expect(cancelledLate == .rejectedStale, "cancelled interaction rejects late frame")
        expect(
            try await audioAppendObjects(cancelTransport).isEmpty,
            "cancelled interaction sends no append"
        )
        let closeCount = await cancelTransport.calls.filter {
            $0 == .close(.normal)
        }.count
        expect(closeCount == 1, "repeated stop closes Adapter once")

        let closeTransport = handshakeTransport()
        let closeStack = makeRuntimeStack(transport: closeTransport)
        _ = closeStack.orchestration.loadResident(fixtureData: fixtureData)
        let closedBinding = try success(
            await closeStack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 88
            )
        )
        _ = try success(
            await closeStack.orchestration.closeNativeSpeechInput(
                binding: closedBinding
            )
        )
        let closedLate = try success(
            await closeStack.orchestration.sendNativeSpeechInput(
                payload(binding: closedBinding, sequence: 1, marker: 10),
                context: context(binding: closedBinding, generation: 88)
            )
        )
        expect(closedLate == .rejectedStale, "closed interaction rejects late frame")
        expect(
            try await audioAppendObjects(closeTransport).isEmpty,
            "closed Adapter receives no late append"
        )
        let closedCallCount = await closeTransport.calls.filter {
            $0 == .close(.normal)
        }.count
        expect(closedCallCount == 1, "Runtime close closes Adapter once")
    }

    private static func testSendFailureStopsSinglePump() async throws {
        let transport = handshakeTransport(audioAppendError: .transportFailure)
        let stack = makeControllerStack(transport: transport)
        _ = stack.orchestration.loadResident(fixtureData: fixtureData)
        await stack.controller.startSpeechAudioCapture()
        expect(stack.capture.emit(42), "failure source emits one frame")
        await stack.controller.startNativeSpeechInputBridge()
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechInputBridgeSnapshot.state == .failed
        }
        let failed = stack.controller.speechInputBridgeSnapshot
        expect(failed.state == .failed, "sendAudio failure marks pump failed")
        expect(!failed.hasActivePump, "sendAudio failure releases pump")
        expect(failed.lastError == "transport_failure", "Provider error is standardized")
        let attemptedCount = try await audioAppendObjects(transport).count
        expect(attemptedCount == 1, "failed Adapter receives one append attempt")
        expect(stack.capture.emit(43), "Audio Host can still produce after pump failure")
        try? await Task.sleep(for: .milliseconds(30))
        expect(
            try await audioAppendObjects(transport).count == attemptedCount,
            "failed pump performs no retry or later append"
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func makeControllerStack(
        transport: FakeRealtimeWebSocketTransport
    ) -> (
        controller: AppController,
        orchestration: OrchestrationKernel,
        host: MacSpeechAudioHost,
        capture: FakeBridgeAudioCapture
    ) {
        let runtimeStack = makeRuntimeStack(transport: transport)
        let capture = FakeBridgeAudioCapture()
        let host = MacSpeechAudioHost(
            authorizationProvider: AuthorizedMicrophoneProvider(),
            capture: capture,
            deviceMonitor: FakeBridgeDeviceMonitor()
        )
        return (
            AppController(
                orchestrationKernel: runtimeStack.orchestration,
                speechAudioHost: host
            ),
            runtimeStack.orchestration,
            host,
            capture
        )
    }

    private static func makeRuntimeStack(
        transport: FakeRealtimeWebSocketTransport
    ) -> (runtime: RuntimeCore, orchestration: OrchestrationKernel) {
        let adapter = StepFunRealtimeAdapter(
            credentialReader: BridgeTestCredentialReader(),
            transport: transport
        )
        let router = ProviderRouter(
            credentialReader: UnavailableProviderCredentialReader(),
            nativeSpeechProvider: adapter
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        return (runtime, OrchestrationKernel(runtimeCore: runtime))
    }

    private static func handshakeTransport(
        audioAppendError: NativeSpeechError? = nil
    ) -> FakeRealtimeWebSocketTransport {
        FakeRealtimeWebSocketTransport(
            frames: [
                .text(#"{"type":"session.created"}"#),
                .text(#"{"type":"session.updated"}"#)
            ],
            audioAppendError: audioAppendError,
            waitsWhenEmpty: true
        )
    }

    private static func profile() -> NativeSpeechProviderProfile {
        NativeSpeechProviderProfile(
            profileID: "stage7_5_stepfun_realtime_primary",
            providerID: "StepFun",
            capability: "native_speech",
            adapterID: "stepfun_realtime",
            modelID: "stepaudio-2.5-realtime",
            voiceID: "linjiajiejie",
            endpoint: URL(
                string: "wss://api.stepfun.com/v1/realtime?model=stepaudio-2.5-realtime"
            )!,
            transport: "websocket",
            inputAudioFormat: .pcm16,
            outputAudioFormat: .pcm16,
            turnDetection: NativeSpeechTurnDetection(
                type: .serverVAD,
                prefixPaddingMilliseconds: 500
            ),
            languageMetadata: "zh-CN",
            keyRef: "keychain://com.eterna.aftelle.provider.stepfun/stepfun_realtime_api_key"
        )
    }

    private static func payload(
        binding: NativeSpeechInputBinding,
        sequence: UInt64,
        marker: UInt8
    ) -> NativeSpeechAudioPayload {
        NativeSpeechAudioPayload(
            interactionID: binding.interactionID,
            sequenceNumber: sequence,
            bytes: Data([marker, 0]),
            format: .pcm16
        )
    }

    private static func context(
        binding: NativeSpeechInputBinding,
        generation: UInt64
    ) -> NativeSpeechInputFrameContext {
        NativeSpeechInputFrameContext(
            binding: binding,
            captureGeneration: generation,
            monotonicTimestampNanoseconds: 1
        )
    }

    private static func audioAppendObjects(
        _ transport: FakeRealtimeWebSocketTransport
    ) async throws -> [[String: Any]] {
        try await transport.calls.compactMap { call in
            guard case .send(.text(let text)) = call else { return nil }
            let object = try JSONSerialization.jsonObject(
                with: Data(text.utf8)
            ) as! [String: Any]
            return object["type"] as? String == "input_audio_buffer.append"
                ? object
                : nil
        }
    }

    private static func sentEventTypes(
        _ transport: FakeRealtimeWebSocketTransport
    ) async throws -> [String] {
        try await transport.calls.compactMap { call in
            guard case .send(.text(let text)) = call else { return nil }
            let object = try JSONSerialization.jsonObject(
                with: Data(text.utf8)
            ) as! [String: Any]
            return object["type"] as? String
        }
    }

    private static func success<Value>(
        _ result: Result<Value, NativeSpeechError>
    ) throws -> Value {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    private static func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0 ..< 200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        fatalError("FAILED: timed out waiting for input bridge")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
