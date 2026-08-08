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
        let target = lock.withLock { (started, frameBuffer, generation) }
        guard target.0,
              let frameBuffer = target.1,
              let generation = target.2 else {
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

private nonisolated final class ControlledWriteSink: @unchecked Sendable {
    typealias Completion = @Sendable (NativeSpeechError?) -> Void

    private let lock = NSLock()
    private var pendingCompletions: [Completion] = []
    private var submittedFrames: [RealtimeWebSocketFrame] = []
    private var virtualLatencies: [Int] = []

    func submit(
        _ frame: RealtimeWebSocketFrame,
        completion: @escaping Completion
    ) {
        lock.withLock {
            let latencyPattern = [43, 43, 43, 43, 43, 43, 43, 43, 46, 80]
            virtualLatencies.append(
                latencyPattern[submittedFrames.count % latencyPattern.count]
            )
            submittedFrames.append(frame)
            pendingCompletions.append(completion)
        }
    }

    @discardableResult
    func completeNext(error: NativeSpeechError? = nil) -> Bool {
        let completion = lock.withLock { () -> Completion? in
            guard !pendingCompletions.isEmpty else { return nil }
            return pendingCompletions.removeFirst()
        }
        guard let completion else { return false }
        completion(error)
        return true
    }

    func completeAllLate() {
        while completeNext() {}
    }

    var pendingCount: Int {
        lock.withLock { pendingCompletions.count }
    }

    var frames: [RealtimeWebSocketFrame] {
        lock.withLock { submittedFrames }
    }

    var averageVirtualLatencyMilliseconds: Int {
        lock.withLock {
            guard !virtualLatencies.isEmpty else { return 0 }
            return virtualLatencies.reduce(0, +) / virtualLatencies.count
        }
    }

    var maximumVirtualLatencyMilliseconds: Int {
        lock.withLock { virtualLatencies.max() ?? 0 }
    }
}

private nonisolated final class InputSendProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false
    private var forwardedCount = 0

    func markStarted() {
        lock.withLock { didStart = true }
    }

    func markForwarded() {
        lock.withLock { forwardedCount += 1 }
    }

    var snapshot: (didStart: Bool, forwardedCount: Int) {
        lock.withLock { (didStart, forwardedCount) }
    }
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
        try await testInputSendContinuesWhileMainActorIsBusy()
        try await testRuntimeGenerationSessionAndSequenceGates()
        try await testSendFailureStopsSinglePump()
        try await testBoundedWriteWindowSustainsVirtualFiveMinutes()
        try await testWriteWindowFailureAndCloseAreBounded()
        try await testControlAndAudioFramesShareFIFO()
        print("native_speech_input_bridge_checks=\(checks)")
    }

    private static func testBoundedWriteWindowSustainsVirtualFiveMinutes()
        async throws
    {
        let frameCount = 15_000
        let sink = ControlledWriteSink()
        let window = BoundedRealtimeWebSocketWriteWindow(capacity: 8)
        await window.reset()

        let producer = Task {
            for index in 0 ..< frameCount {
                let marker = UInt8(index % 251)
                try await window.enqueue(
                    .binary(Data(repeating: marker, count: 960))
                ) { frame, completion in
                    sink.submit(frame, completion: completion)
                }
            }
        }

        await waitUntil { sink.pendingCount == 8 }
        for _ in 0 ..< frameCount {
            while !sink.completeNext() {
                await Task.yield()
            }
        }
        try await producer.value
        await waitUntil {
            await window.snapshot().completedWriteCount == UInt64(frameCount)
        }

        let frames = sink.frames
        let snapshot = await window.snapshot()
        expect(frames.count == frameCount, "five virtual minutes submit every frame")
        expect(
            frames.allSatisfy {
                guard case .binary(let bytes) = $0 else { return false }
                return bytes.count == 960
            },
            "every virtual microphone frame remains 20 ms / 960 bytes"
        )
        expect(
            frames.enumerated().allSatisfy { index, frame in
                guard case .binary(let bytes) = frame else { return false }
                return bytes.first == UInt8(index % 251)
            },
            "bounded writes preserve capture order"
        )
        expect(
            snapshot.submittedWriteCount == UInt64(frameCount),
            "all 15,000 frames enter the write window"
        )
        expect(
            snapshot.completedWriteCount == UInt64(frameCount),
            "all 15,000 virtual writes complete"
        )
        expect(snapshot.pendingWriteCount == 0, "write window drains completely")
        expect(
            snapshot.maximumPendingWriteCount == 8,
            "write window never exceeds eight pending operations"
        )
        expect(
            sink.averageVirtualLatencyMilliseconds == 47,
            "virtual completion latency averages 47 ms"
        )
        expect(
            sink.maximumVirtualLatencyMilliseconds == 80,
            "virtual completion latency peaks at 80 ms"
        )
    }

    private static func testWriteWindowFailureAndCloseAreBounded()
        async throws
    {
        let failureSink = ControlledWriteSink()
        let failureWindow = BoundedRealtimeWebSocketWriteWindow(capacity: 2)
        await failureWindow.reset()
        for marker in UInt8(1) ... UInt8(2) {
            try await failureWindow.enqueue(
                .binary(Data(repeating: marker, count: 960))
            ) { frame, completion in
                failureSink.submit(frame, completion: completion)
            }
        }
        let blockedByFailure = Task { () -> NativeSpeechError? in
            do {
                try await failureWindow.enqueue(
                    .binary(Data(repeating: 3, count: 960))
                ) { frame, completion in
                    failureSink.submit(frame, completion: completion)
                }
                return nil
            } catch let error as NativeSpeechError {
                return error
            } catch {
                return .transportFailure
            }
        }
        await Task.yield()
        expect(
            failureSink.completeNext(error: .transportFailure),
            "asynchronous write failure completes an in-flight write"
        )
        expect(
            await blockedByFailure.value == .transportFailure,
            "latched write failure releases a saturated sender"
        )
        failureSink.completeAllLate()
        await Task.yield()
        let failed = await failureWindow.snapshot()
        expect(failed.pendingWriteCount == 0, "write failure releases pending operations")
        expect(
            failed.latchedError == .transportFailure,
            "write failure remains observable"
        )
        expect(
            await failureWindow.beginCloseAndDrain(
                timeoutNanoseconds: 50_000_000
            ) == .transportFailure,
            "close drain surfaces a previously latched write failure"
        )

        let closeSink = ControlledWriteSink()
        let closeWindow = BoundedRealtimeWebSocketWriteWindow(capacity: 2)
        await closeWindow.reset()
        for marker in UInt8(1) ... UInt8(2) {
            try await closeWindow.enqueue(
                .binary(Data(repeating: marker, count: 960))
            ) { frame, completion in
                closeSink.submit(frame, completion: completion)
            }
        }
        let blockedByClose = Task { () -> NativeSpeechError? in
            do {
                try await closeWindow.enqueue(
                    .binary(Data(repeating: 3, count: 960))
                ) { frame, completion in
                    closeSink.submit(frame, completion: completion)
                }
                return nil
            } catch let error as NativeSpeechError {
                return error
            } catch {
                return .transportFailure
            }
        }
        await Task.yield()
        await closeWindow.close()
        expect(
            await blockedByClose.value == .cancelled,
            "Stop releases a saturated sender as cancelled"
        )
        closeSink.completeAllLate()
        await Task.yield()
        let closed = await closeWindow.snapshot()
        expect(closed.pendingWriteCount == 0, "Stop clears pending writes")
        expect(closed.latchedError == .cancelled, "Stop invalidates late completions")

        let drainSink = ControlledWriteSink()
        let drainWindow = BoundedRealtimeWebSocketWriteWindow(capacity: 2)
        await drainWindow.reset()
        let drainFrames: [RealtimeWebSocketFrame] = [
            .text(#"{"type":"input_audio_buffer.append","audio":"AA=="}"#),
            .text(#"{"type":"response.cancel"}"#)
        ]
        for frame in drainFrames {
            try await drainWindow.enqueue(frame) { frame, completion in
                drainSink.submit(frame, completion: completion)
            }
        }
        let drain = Task {
            await drainWindow.beginCloseAndDrain(
                timeoutNanoseconds: 500_000_000
            )
        }
        await Task.yield()
        expect(
            drainSink.completeNext(),
            "close drain waits for the earlier audio write"
        )
        await Task.yield()
        expect(
            await drainWindow.snapshot().pendingWriteCount == 1,
            "response.cancel remains pending behind the earlier write"
        )
        expect(
            drainSink.completeNext(),
            "response.cancel completes before close proceeds"
        )
        expect(
            await drain.value == nil,
            "close barrier drains all submitted FIFO writes"
        )
        expect(
            drainSink.frames == drainFrames,
            "close barrier preserves audio then cancel submission order"
        )
        await drainWindow.close()

        let timeoutSink = ControlledWriteSink()
        let timeoutWindow = BoundedRealtimeWebSocketWriteWindow(capacity: 1)
        await timeoutWindow.reset()
        try await timeoutWindow.enqueue(
            .text(#"{"type":"response.cancel"}"#)
        ) { frame, completion in
            timeoutSink.submit(frame, completion: completion)
        }
        expect(
            await timeoutWindow.beginCloseAndDrain(
                timeoutNanoseconds: 5_000_000
            ) == .timedOut,
            "close drain times out instead of waiting forever"
        )
        await timeoutWindow.close()
        timeoutSink.completeAllLate()
        await Task.yield()
        let timedOut = await timeoutWindow.snapshot()
        expect(
            timedOut.pendingWriteCount == 0
                && timedOut.latchedError == .cancelled,
            "close invalidates late completion after a drain timeout"
        )
    }

    private static func testControlAndAudioFramesShareFIFO() async throws {
        let sink = ControlledWriteSink()
        let window = BoundedRealtimeWebSocketWriteWindow(capacity: 8)
        await window.reset()
        let frames: [RealtimeWebSocketFrame] = [
            .text(#"{"type":"session.update"}"#),
            .text(#"{"type":"input_audio_buffer.append","audio":"AA=="}"#),
            .text(#"{"type":"response.cancel"}"#),
            .binary(Data(repeating: 7, count: 960))
        ]
        for frame in frames {
            try await window.enqueue(frame) { frame, completion in
                sink.submit(frame, completion: completion)
            }
        }
        expect(sink.frames == frames, "control and audio writes share one FIFO")
        sink.completeAllLate()
        await waitUntil {
            await window.snapshot().completedWriteCount == UInt64(frames.count)
        }
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
        for marker in UInt8(201) ... UInt8(205) {
            expect(
                stack.capture.emit(marker),
                "standalone capture can produce before bridge startup"
            )
        }

        await stack.controller.startNativeSpeechInputBridge()
        let started = await stack.host.currentSnapshot()
        expect(started.isCapturing, "capture starts after Provider handshake")
        expect(
            started.generatedFrameCount == 0
                && started.droppedFrameCount == 0
                && started.queuedFrameCount == 0,
            "bridge generation excludes standalone pre-handshake frames"
        )
        for marker in UInt8(1) ... UInt8(25) {
            expect(stack.capture.emit(marker), "Fake Audio Source emits PCM16 frame")
        }
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechInputBridgeSnapshot
                .adapterReceivedFrameCount == 25
        }
        let running = stack.controller.speechInputBridgeSnapshot
        expect(running.state == .running, "input bridge is running")
        expect(running.hasActivePump, "one active input pump is visible")
        expect(running.forwardedFrameCount == 25, "twenty-five bounded frames are forwarded")
        expect(running.runtimeRejectedFrameCount == 0, "current frames pass Runtime gate")
        expect(running.sendOperationCount == 25, "twenty-five sends are measured")
        expect(
            running.maximumSendDurationMilliseconds
                >= running.averageSendDurationMilliseconds,
            "send timing exposes bounded aggregate metrics"
        )
        expect(running.interactionShortID?.count == 8, "interaction ID is redacted")

        let appendObjects = try await audioAppendObjects(transport)
        expect(appendObjects.count == 25, "Fake Transport receives bounded audio appends")
        let markers = appendObjects.compactMap { object -> UInt8? in
            guard let encoded = object["audio"] as? String,
                  let data = Data(base64Encoded: encoded) else { return nil }
            return data.first
        }
        expect(markers == Array(UInt8(1) ... UInt8(25)), "audio order preserves post-handshake frames")

        await stack.controller.startNativeSpeechInputBridge()
        await stack.controller.refreshMicrophoneAuthorization()
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "duplicate start keeps the existing pump"
        )
        expect(
            try await audioAppendObjects(transport).count == 25,
            "duplicate start creates no second sender"
        )

        await stack.controller.stopSpeechAudioCapture()
        expect(!stack.controller.speechAudioHostSnapshot.isCapturing, "Host stop ends capture")
        expect(!stack.controller.speechInputBridgeSnapshot.hasActivePump, "Host stop ends input pump")
        expect(!stack.capture.emit(13), "stopped generation rejects late Host frame")
        let stopCount = stack.capture.stopCount
        await stack.controller.stopSpeechAudioCapture()
        expect(
            stack.capture.stopCount == stopCount,
            "repeated stop is idempotent"
        )
        expect(
            try await audioAppendObjects(transport).count == 25,
            "stop sends no late audio append"
        )
        let eventTypes = try await sentEventTypes(transport)
        expect(eventTypes.contains("input_audio_buffer.append"), "Adapter emits audio append events")
        expect(!eventTypes.contains("input_audio_buffer.commit"), "bridge sends no audio commit")
        expect(!eventTypes.contains("response.create"), "bridge sends no response.create")
    }

    private static func testInputSendContinuesWhileMainActorIsBusy() async throws {
        let transport = handshakeTransport()
        let stack = makeRuntimeStack(transport: transport)
        _ = stack.orchestration.loadResident(fixtureData: fixtureData)
        let binding = try success(
            await stack.orchestration.startNativeSpeechInput(
                profile: profile(),
                captureGeneration: 42
            )
        )
        let sendFrame: MacSpeechNativeInputBridge.SendFrame = {
            [orchestration = stack.orchestration] payload, context in
            await orchestration.sendNativeSpeechInput(
                payload,
                context: context
            )
        }
        let frames = (UInt64(1) ... UInt64(25)).map { sequence in
            (
                payload(
                    binding: binding,
                    sequence: sequence,
                    marker: UInt8(sequence)
                ),
                context(binding: binding, generation: 42)
            )
        }
        let progress = InputSendProgress()
        let producer = Task.detached {
            progress.markStarted()
            for frame in frames {
                let result = await sendFrame(frame.0, frame.1)
                if result == .success(.forwarded) {
                    progress.markForwarded()
                }
            }
        }

        while !progress.snapshot.didStart {
            _ = DispatchTime.now().uptimeNanoseconds
        }
        let blockedUntil = DispatchTime.now().uptimeNanoseconds
            + 250_000_000
        while DispatchTime.now().uptimeNanoseconds < blockedUntil {
            _ = progress.snapshot.didStart
        }

        expect(
            progress.snapshot.forwardedCount == 25,
            "twenty-millisecond input hot path does not wait for MainActor"
        )
        await producer.value
        _ = try success(
            await stack.orchestration.stopNativeSpeechInput(
                binding: binding,
                reason: .stopped
            )
        )
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
        await stack.controller.startNativeSpeechInputBridge()
        expect(stack.capture.emit(42), "failure source emits one frame")
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
