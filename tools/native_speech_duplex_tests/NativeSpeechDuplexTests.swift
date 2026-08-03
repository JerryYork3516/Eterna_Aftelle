@preconcurrency import AVFoundation
import Foundation

private struct DuplexCredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "fake-token"
    }
}

private struct DuplexAuthorizationProvider:
    MicrophoneAuthorizationProviding
{
    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }
}

private final class DuplexAudioCapture:
    MacSpeechAudioCapturing, @unchecked Sendable
{
    private let lock = NSLock()
    private var frameBuffer: MacSpeechAudioFrameBuffer?
    private var generation: UInt64?
    private var started = false

    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        lock.withLock {
            started = true
            self.generation = generation
            self.frameBuffer = frameBuffer
            return MacSpeechNativeInputFormat(
                sampleRate: 48_000,
                channelCount: 2
            )
        }
    }

    func stop() {
        lock.withLock { started = false }
    }

    @discardableResult
    func emit(_ marker: UInt8) -> Bool {
        let target = lock.withLock { (started, frameBuffer, generation) }
        guard target.0,
              let frameBuffer = target.1,
              let generation = target.2 else {
            return false
        }
        return frameBuffer.append(
            pcm16Bytes: Data([marker, 0]),
            activity: 0.25,
            generation: generation
        )
    }
}

private final class DuplexDeviceMonitor:
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
private struct NativeSpeechDuplexTests {
    private static var checks = 0
    private static var fixtureData = Data()

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        fixtureData = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        try await testFullDuplexThroughController()
        try await testOutputBackpressureStopsInteraction()
        try await testReceiveFailureAndDuplicateStart()
        try await testStaleCancelledAndClosedOutput()
        print("native_speech_duplex_checks=\(checks)")
    }

    private static func testFullDuplexThroughController() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "fixed resident loads"
        )
        await stack.controller.startSpeechAudioCapture()
        for marker in UInt8(1) ... UInt8(3) {
            expect(stack.capture.emit(marker), "Fake source emits input frame")
        }
        await stack.controller.startNativeSpeechInputBridge()
        await waitUntil {
            try await audioAppendObjects(transport).count == 3
        }

        await transport.enqueue(.text(#"{"type":"future.event"}"#))
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQF"}"#)
        )
        await transport.enqueue(.text(#"{"type":"response.audio.done"}"#))
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot.terminalStatus
                == "completed"
        }

        let inputObjects = try await audioAppendObjects(transport)
        expect(inputObjects.count == 3, "three ordered input appends arrive")
        let inputMarkers = inputObjects.compactMap { object -> UInt8? in
            guard let encoded = object["audio"] as? String,
                  let data = Data(base64Encoded: encoded) else { return nil }
            return data.first
        }
        expect(inputMarkers == [1, 2, 3], "input bytes preserve order")

        let output = stack.controller.speechOutputBridgeSnapshot
        expect(output.state == .closed, "canonical completion closes receive loop")
        expect(output.outputAudioChunkCount == 2, "two output chunks reach AppController")
        expect(output.outputAudioByteCount == 5, "output byte count reaches AppController")
        expect(output.firstChunkLatencyMilliseconds != nil, "first chunk latency is recorded")
        expect(!output.hasActiveReceiveLoop, "terminal event releases receive loop")
        expect(
            !stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "terminal event stops input pump"
        )
        expect(
            await transport.maximumConcurrentReceiveCount == 1,
            "one receive loop is active"
        )
        expect(
            await stack.adapter.ignoredEventCount == 2,
            "unknown and audio.done events are safely ignored"
        )
        let eventTypes = try await sentEventTypes(transport)
        expect(!eventTypes.contains("input_audio_buffer.commit"), "no input commit is sent")
        expect(!eventTypes.contains("response.create"), "no response.create is sent")
        let closeCount = await transport.calls.filter {
            $0 == .close(.normal)
        }.count
        expect(closeCount == 1, "canonical terminal closes transport once")
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testOutputBackpressureStopsInteraction() async throws {
        let transport = handshakeTransport()
        let stack = makeRuntimeStack(transport: transport)
        _ = stack.orchestration.loadResident(fixtureData: fixtureData)
        let binding = try success(
            await stack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 10
            )
        )
        let bridge = outputBridge(
            orchestration: stack.orchestration,
            consumeTimeout: .milliseconds(5)
        ) { event in
            if case .outputAudio = event.kind {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        _ = await bridge.start(binding: binding)
        await waitUntil {
            await transport.calls.contains(.receive)
        }
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        await waitUntil {
            await bridge.currentSnapshot().state == .failed
        }
        let failed = await bridge.currentSnapshot()
        expect(failed.lastError == "transport_failure", "slow sink returns standard error")
        expect(!failed.hasActiveReceiveLoop, "slow sink stops receive loop")
        expect(
            MacSpeechNativeOutputBridge.outputEventCapacity == 1,
            "output flow is one bounded in-flight event"
        )
        let types = try await sentEventTypes(transport)
        expect(types.filter { $0 == "response.cancel" }.count == 1, "overflow cancels Provider once")
        let closeCount = await transport.calls.filter {
            $0 == .close(.normal)
        }.count
        expect(closeCount == 1, "overflow closes Provider once")
        let receiveCount = await transport.calls.filter { $0 == .receive }.count
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#)
        )
        try? await Task.sleep(for: .milliseconds(20))
        expect(
            await transport.calls.filter { $0 == .receive }.count == receiveCount,
            "overflow does not continue receiving"
        )
    }

    private static func testReceiveFailureAndDuplicateStart() async throws {
        let transport = handshakeTransport()
        let stack = makeRuntimeStack(transport: transport)
        _ = stack.orchestration.loadResident(fixtureData: fixtureData)
        let binding = try success(
            await stack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 20
            )
        )
        let bridge = outputBridge(orchestration: stack.orchestration)
        _ = await bridge.start(binding: binding)
        _ = await bridge.start(binding: binding)
        await waitUntil {
            await transport.calls.contains(.receive)
        }
        expect(
            await transport.maximumConcurrentReceiveCount == 1,
            "duplicate start creates no second receive loop"
        )
        await transport.enqueueFailure(.transportFailure)
        await waitUntil {
            await bridge.currentSnapshot().state == .failed
        }
        expect(
            await bridge.currentSnapshot().lastError == "transport_failure",
            "receive failure reaches standard error"
        )
        expect(
            await transport.calls.filter { $0 == .connect(profile().endpoint) }.count == 1,
            "streaming receive failure never reconnects"
        )
    }

    private static func testStaleCancelledAndClosedOutput() async throws {
        let staleTransport = handshakeTransport()
        let staleStack = makeRuntimeStack(transport: staleTransport)
        _ = staleStack.orchestration.loadResident(fixtureData: fixtureData)
        let staleBinding = try success(
            await staleStack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 30
            )
        )
        _ = staleStack.orchestration.loadResident(fixtureData: fixtureData)
        let staleBridge = outputBridge(orchestration: staleStack.orchestration)
        _ = await staleBridge.start(binding: staleBinding)
        await waitUntil {
            await staleBridge.currentSnapshot().terminalStatus
                == "rejected_stale"
        }
        expect(
            await staleBridge.currentSnapshot().runtimeRejectedEventCount == 1,
            "old session output is rejected"
        )
        let staleCloseCount = await staleTransport.calls.filter {
            $0 == .close(.normal)
        }.count
        expect(staleCloseCount == 1, "old session connection is closed")

        let cancelledTransport = handshakeTransport()
        let cancelledStack = makeRuntimeStack(transport: cancelledTransport)
        _ = cancelledStack.orchestration.loadResident(fixtureData: fixtureData)
        let cancelledBinding = try success(
            await cancelledStack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 40
            )
        )
        _ = try success(
            await cancelledStack.orchestration.stopNativeSpeechInput(
                binding: cancelledBinding,
                reason: .stopped
            )
        )
        let cancelled = await cancelledStack.orchestration
            .receiveNativeSpeechEvent(
                interactionID: cancelledBinding.interactionID
            )
        expect(
            try success(cancelled) == .rejectedStale,
            "cancelled interaction rejects output"
        )

        let closedTransport = handshakeTransport()
        let closedStack = makeRuntimeStack(transport: closedTransport)
        _ = closedStack.orchestration.loadResident(fixtureData: fixtureData)
        let closedBinding = try success(
            await closedStack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 50
            )
        )
        _ = try success(
            await closedStack.orchestration.closeNativeSpeechInput(
                binding: closedBinding
            )
        )
        let closed = await closedStack.orchestration.receiveNativeSpeechEvent(
            interactionID: closedBinding.interactionID
        )
        expect(
            try success(closed) == .rejectedStale,
            "closed interaction rejects output"
        )
    }

    private static func outputBridge(
        orchestration: OrchestrationKernel,
        consumeTimeout: Duration = .milliseconds(250),
        consume: @escaping @Sendable (NativeSpeechEvent) async -> Void = { _ in }
    ) -> MacSpeechNativeOutputBridge {
        MacSpeechNativeOutputBridge(
            receiveEvent: { interactionID in
                await orchestration.receiveNativeSpeechEvent(
                    interactionID: interactionID
                )
            },
            consumeEvent: consume,
            endInputPump: {},
            stopInput: { binding, reason in
                await orchestration.stopNativeSpeechInput(
                    binding: binding,
                    reason: reason
                )
            },
            closeInput: { binding in
                await orchestration.closeNativeSpeechInput(
                    binding: binding
                )
            },
            consumeTimeout: consumeTimeout
        )
    }

    private static func makeControllerStack(
        transport: FakeRealtimeWebSocketTransport
    ) -> (
        controller: AppController,
        orchestration: OrchestrationKernel,
        capture: DuplexAudioCapture,
        adapter: StepFunRealtimeAdapter
    ) {
        let runtimeStack = makeRuntimeStack(transport: transport)
        let capture = DuplexAudioCapture()
        let host = MacSpeechAudioHost(
            authorizationProvider: DuplexAuthorizationProvider(),
            capture: capture,
            deviceMonitor: DuplexDeviceMonitor()
        )
        return (
            AppController(
                orchestrationKernel: runtimeStack.orchestration,
                speechAudioHost: host
            ),
            runtimeStack.orchestration,
            capture,
            runtimeStack.adapter
        )
    }

    private static func makeRuntimeStack(
        transport: FakeRealtimeWebSocketTransport
    ) -> (
        orchestration: OrchestrationKernel,
        adapter: StepFunRealtimeAdapter
    ) {
        let adapter = StepFunRealtimeAdapter(
            credentialReader: DuplexCredentialReader(),
            transport: transport,
            reconnectDelay: .zero
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
        return (OrchestrationKernel(runtimeCore: runtime), adapter)
    }

    private static func handshakeTransport() -> FakeRealtimeWebSocketTransport {
        FakeRealtimeWebSocketTransport(
            frames: [
                .text(#"{"type":"session.created"}"#),
                .text(#"{"type":"session.updated"}"#)
            ],
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

    private static func audioAppendObjects(
        _ transport: FakeRealtimeWebSocketTransport
    ) async throws -> [[String: Any]] {
        let calls = await transport.calls
        return try calls.compactMap { call in
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
        let calls = await transport.calls
        return try calls.compactMap { call in
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
        _ condition: @escaping @MainActor () async throws -> Bool
    ) async {
        for _ in 0 ..< 400 {
            if (try? await condition()) == true { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        fatalError("FAILED: timed out waiting for duplex state")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
