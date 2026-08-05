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
    private static var waitIndex = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        fixtureData = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        try await testFullDuplexThroughController()
        try await testInterruptThroughController()
        try await testOutputDeviceChangeThroughController()
        try await testStopClearsActivePlaybackThroughController()
        try await testConversionFailureThroughController()
        await testDebugSinkClearsInterruptedOutput()
        try await testSlowConsumerPreservesInteraction()
        try await testReceiveFailureAndDuplicateStart()
        try await testStaleCancelledAndClosedOutput()
        try await testCumulativeSubtitleThroughController()
        try await testRedactedDiagnosticsAndExport()
        print("native_speech_duplex_checks=\(checks)")
    }

    private static func testRedactedDiagnosticsAndExport() async throws {
        var timeline = RealtimeSpeechDiagnosticTimeline()
        for index in 0 ... RealtimeSpeechDiagnosticTimeline.capacity {
            timeline.append(
                source: .providerEvent,
                category: "output_audio",
                audioSequence: UInt64(index),
                byteCount: 320
            )
        }
        expect(
            timeline.eventCount
                == RealtimeSpeechDiagnosticTimeline.capacity,
            "diagnostic timeline is bounded"
        )
        expect(
            timeline.events.first?.audioSequence == 1
                && timeline.events.last?.audioSequence
                    == UInt64(RealtimeSpeechDiagnosticTimeline.capacity),
            "diagnostic ring preserves retained event order"
        )
        expect(
            timeline.visibleEvents.count
                == RealtimeSpeechDiagnosticTimeline.visibleCapacity,
            "debug panel timeline is limited to recent events"
        )
        expect(
            timeline.droppedEventCount == 1,
            "diagnostic timeline reports dropped events"
        )
        timeline.clear()
        expect(
            timeline.eventCount == 0 && timeline.droppedEventCount == 0,
            "diagnostic timeline clears events and dropped count"
        )

        let stack = makeControllerStack(transport: handshakeTransport())
        await stack.controller.startSpeechAudioCapture()
        let data = try stack.controller.realtimeSpeechDiagnosticExportData(
            exportedAt: Date(timeIntervalSince1970: 0)
        )
        let object = try JSONSerialization.jsonObject(with: data)
            as! [String: Any]
        expect(object["schema_version"] as? Int == 2,
               "diagnostic export freezes schema version 2")
        expect(object["events"] is [[String: Any]],
               "diagnostic export contains structured events")
        for metric in [
            "input_send_operation_count",
            "input_average_send_duration_milliseconds",
            "input_maximum_send_duration_milliseconds",
            "capture_generated_frame_count",
            "capture_dropped_frame_count",
            "capture_queued_frame_count"
        ] {
            expect(
                object[metric] != nil,
                "diagnostic export includes \(metric)"
            )
        }
        let exported = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in [
            "fake-token",
            "authorization",
            "instructions",
            "base64",
            "transcript",
            "resident_identity",
            "session_memory"
        ] {
            expect(
                !exported.contains(forbidden),
                "diagnostic export omits \(forbidden)"
            )
        }
        stack.controller.clearRealtimeSpeechDiagnostics()
        expect(
            stack.controller.realtimeSpeechDiagnosticTimeline.events.isEmpty,
            "controller clears diagnostic timeline"
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testCumulativeSubtitleThroughController() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "subtitle fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"你"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"好"}"#)
        )
        await waitUntil {
            stack.controller.realtimeSpeechSubtitleSnapshot.userPartial
                == "你好"
        }
        await transport.enqueue(
            .text(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"你好"}"#)
        )
        await waitUntil {
            stack.controller.realtimeSpeechSubtitleSnapshot.userFinal
                == "你好"
        }
        await transport.enqueue(.text(#"{"type":"response.created"}"#))
        await transport.enqueue(
            .text(#"{"type":"response.audio_transcript.delta","delta":"我"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio_transcript.delta","delta":"是"}"#)
        )
        await waitUntil {
            stack.controller.realtimeSpeechSubtitleSnapshot.residentPartial
                == "我是"
        }
        await transport.enqueue(
            .text(#"{"type":"response.audio_transcript.done","transcript":"我是林轩"}"#)
        )
        await waitUntil {
            stack.controller.realtimeSpeechSubtitleSnapshot.residentFinal
                == "我是林轩"
        }
        expect(
            stack.controller.particleSubtitleState.text == "我是林轩",
            "final subtitle bypasses partial throttle"
        )
        await stack.controller.stopSpeechAudioCapture()
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
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#)
        )
        await transport.enqueue(.text(#"{"type":"response.audio.done"}"#))
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                .completedResponseCount == 1
        }
        expect(
            stack.controller.realtimeSpeechStateSnapshot.state == .speaking,
            "Provider completion waits for local playback"
        )
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil { stack.outputPlayer.scheduledCount == 2 }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .listening
        }

        let firstOutput = stack.controller.speechOutputBridgeSnapshot
        expect(
            firstOutput.state == .configured,
            "first response returns to configured state"
        )
        expect(
            firstOutput.hasActiveReceiveLoop,
            "first response keeps receive loop active"
        )
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "first response keeps input pump active"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.isEmpty,
            "first response keeps transport open"
        )

        for marker in UInt8(4) ... UInt8(6) {
            expect(stack.capture.emit(marker), "second turn emits input frame")
        }
        await waitUntil {
            try await audioAppendObjects(transport).count == 6
        }
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"Bgc="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                .completedResponseCount == 2
        }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .listening
        }

        for turn in 3 ... 5 {
            expect(
                stack.capture.emit(UInt8(turn + 4)),
                "turn \(turn) emits input frame"
            )
            await waitUntil {
                try await audioAppendObjects(transport).count == turn + 4
            }
            await transport.enqueue(
                .text(#"{"type":"input_audio_buffer.speech_started"}"#)
            )
            await transport.enqueue(
                .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
            )
            await transport.enqueue(
                .text(#"{"type":"response.audio.delta","delta":"CAk="}"#)
            )
            await transport.enqueue(
                .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
            )
            await waitUntil {
                await stack.controller.refreshMicrophoneAuthorization()
                return stack.controller.speechOutputBridgeSnapshot
                    .completedResponseCount == UInt64(turn)
            }
            stack.outputPlayer.completeScheduledChunk()
            await waitUntil {
                await stack.controller.refreshMicrophoneAuthorization()
                return stack.controller.realtimeSpeechStateSnapshot.state
                    == .listening
            }
        }

        let inputObjects = try await audioAppendObjects(transport)
        expect(inputObjects.count == 9, "five turns keep sending input")
        let inputMarkers = inputObjects.compactMap { object -> UInt8? in
            guard let encoded = object["audio"] as? String,
                  let data = Data(base64Encoded: encoded) else { return nil }
            return data.first
        }
        expect(
            inputMarkers == [1, 2, 3, 4, 5, 6, 7, 8, 9],
            "five-turn input preserves order"
        )

        let output = stack.controller.speechOutputBridgeSnapshot
        expect(output.state == .configured, "fifth response keeps bridge configured")
        expect(output.completedResponseCount == 5, "five response boundaries arrive")
        expect(output.outputAudioChunkCount == 6, "five responses reach AppController")
        expect(output.outputAudioByteCount == 12, "five-response byte count reaches AppController")
        expect(output.firstChunkLatencyMilliseconds != nil, "first chunk latency is recorded")
        expect(output.hasActiveReceiveLoop, "fifth response keeps receive loop active")
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "fifth response keeps input pump active"
        )
        expect(
            await transport.maximumConcurrentReceiveCount == 1,
            "all responses share one receive loop"
        )
        expect(
            await stack.adapter.ignoredEventCount == 2,
            "unknown and audio.done events are safely ignored"
        )
        let eventTypes = try await sentEventTypes(transport)
        expect(!eventTypes.contains("input_audio_buffer.commit"), "no input commit is sent")
        expect(!eventTypes.contains("response.create"), "no response.create is sent")
        let connectCount = await transport.calls.filter {
            if case .connect = $0 { return true }
            return false
        }.count
        expect(connectCount == 1, "five responses reuse one WebSocket")
        expect(
            stack.controller.speechAudioOutputHostSnapshot
                .playbackStartedCount == 5,
            "five responses emit one playbackStarted each"
        )
        expect(
            stack.controller.speechAudioOutputHostSnapshot
                .playbackCompletedCount == 5,
            "five responses emit one playbackCompleted each"
        )

        await stack.controller.stopSpeechAudioCapture()
        let stoppedOutput = stack.controller.speechOutputBridgeSnapshot
        expect(stoppedOutput.state == .closed, "Stop closes output bridge")
        expect(!stoppedOutput.hasActiveReceiveLoop, "Stop releases receive loop")
        expect(
            !stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "Stop releases input pump"
        )
        expect(
            !stack.controller.speechAudioHostSnapshot.isCapturing,
            "Stop releases microphone capture"
        )
        let closeCount = await transport.calls.filter {
            $0 == .close(.normal)
        }.count
        expect(closeCount == 1, "Stop closes transport once")
    }

    private static func testSlowConsumerPreservesInteraction() async throws {
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
            orchestration: stack.orchestration
        ) { event in
            if case .outputAudio = event.kind {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        _ = await bridge.start(binding: binding)
        await waitUntil {
            await transport.calls.contains(.receive)
        }
        await transport.enqueue(
            .text(#"{"type":"response.created"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        try? await Task.sleep(for: .milliseconds(350))
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
        )
        await waitUntil {
            await bridge.currentSnapshot().completedResponseCount == 1
        }
        let active = await bridge.currentSnapshot()
        expect(active.lastError == nil, "slow sink is not a transport error")
        expect(active.hasActiveReceiveLoop, "slow sink preserves receive loop")
        expect(active.completedResponseCount == 1,
               "slow sink still completes the current turn")
        expect(
            MacSpeechNativeOutputBridge.outputEventCapacity == 1,
            "output flow is one bounded in-flight event"
        )
        let types = try await sentEventTypes(transport)
        expect(types.filter { $0 == "response.cancel" }.isEmpty,
               "slow sink does not cancel Provider")
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.isEmpty,
            "slow sink does not close Provider"
        )
        _ = await bridge.stop()
    }

    private static func testInterruptThroughController() async throws {
        let transport = handshakeTransport(
            responseCancelDelay: .milliseconds(300)
        )
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "interrupt fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        expect(stack.capture.emit(1), "interrupt test emits initial input")
        await stack.controller.startNativeSpeechInputBridge()
        await waitUntil {
            try await audioAppendObjects(transport).count == 1
        }

        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .speaking
        }

        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.nativeSpeechPlaybackDebugSnapshot
                .interruptClearCount == 1
        }
        let clearEvent = stack.controller
            .realtimeSpeechDiagnosticTimeline.events.last {
                $0.category == "interrupt_local_clear"
            }
        expect(
            clearEvent?.durationMilliseconds.map { $0 <= 100 } == true,
            "accepted speech_started clears local playback within 100ms"
        )
        let diagnosticCategories = stack.controller
            .realtimeSpeechDiagnosticTimeline.events.map(\.category)
        let clearIndex = diagnosticCategories.firstIndex(
            of: "interrupt_local_clear"
        )
        let cancelIndex = diagnosticCategories.firstIndex(
            of: "provider_cancel_committed"
        )
        expect(
            clearIndex != nil
                && (cancelIndex == nil || clearIndex! < cancelIndex!),
            "local clear is recorded before delayed Provider cancel"
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            let types = try await sentEventTypes(transport)
            return stack.controller.realtimeSpeechStateSnapshot.state
                    == .listening
                && stack.controller.nativeSpeechPlaybackDebugSnapshot
                    .interruptClearCount == 1
                && types.filter { $0 == "response.cancel" }.count == 1
        }
        expect(
            stack.controller.speechAudioHostSnapshot.isCapturing,
            "Interrupt preserves microphone capture"
        )
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "Interrupt preserves input pump"
        )
        expect(
            stack.controller.speechOutputBridgeSnapshot.hasActiveReceiveLoop,
            "Interrupt preserves receive loop"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.isEmpty,
            "Interrupt preserves WebSocket"
        )
        expect(
            stack.controller.realtimeSpeechStateSnapshot
                .interruptedTurnCount == 1,
            "Runtime owns interrupted turn count"
        )
        expect(
            stack.controller.nativeSpeechPlaybackDebugSnapshot
                .interruptClearCount == 1,
            "Interrupt clears local playback once"
        )
        stack.outputPlayer.completeStoppedChunk()
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechAudioOutputHostSnapshot
                .rejectedCallbackCount == 1
        }

        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.cancelled"}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                .runtimeRejectedEventCount == 2
        }
        expect(
            stack.controller.speechOutputBridgeSnapshot.outputAudioChunkCount
                == 2,
            "late interrupted outputAudio never reaches Debug output sink"
        )
        expect(
            stack.controller.speechOutputBridgeSnapshot.hasActiveReceiveLoop,
            "late-event rejection keeps receive loop alive"
        )

        expect(stack.capture.emit(2), "next turn input continues immediately")
        await waitUntil {
            try await audioAppendObjects(transport).count == 2
        }
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.created"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"BQY="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                    .completedResponseCount == 1
        }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .listening
        }
        expect(
            stack.controller.realtimeSpeechStateSnapshot.currentTurnNumber
                == 3,
            "next turn completes without rebuilding interaction"
        )
        let connectCount = await transport.calls.filter {
            if case .connect = $0 { return true }
            return false
        }.count
        expect(connectCount == 1, "Interrupt flow reuses one WebSocket")

        await stack.controller.stopSpeechAudioCapture()
        await stack.controller.stopSpeechAudioCapture()
        expect(
            !stack.controller.speechAudioHostSnapshot.isCapturing,
            "duplicate Stop releases microphone"
        )
        expect(
            !stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "duplicate Stop releases input pump"
        )
        expect(
            !stack.controller.speechOutputBridgeSnapshot.hasActiveReceiveLoop,
            "duplicate Stop releases receive loop"
        )
        expect(
            stack.controller.speechAudioOutputHostSnapshot.state == .closed,
            "Stop closes local playback"
        )
        let eventTypes = try await sentEventTypes(transport)
        expect(
            eventTypes.filter { $0 == "response.cancel" }.count == 1,
            "Stop after response completion does not send a stale Provider cancel"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.count == 1,
            "duplicate Stop closes WebSocket once"
        )
        expect(
            stack.controller.realtimeSpeechStateSnapshot.state == .idle,
            "Stop canonical state is idle"
        )
        expect(
            stack.controller.realtimeSpeechStateSnapshot
                .interactionTerminalOutcome == .stopped,
            "Stop owns one interaction terminal outcome"
        )
    }

    private static func testDebugSinkClearsInterruptedOutput() async {
        let sink = MacSpeechNativeDebugOutputSink()
        let interactionID = NativeSpeechInteractionID()
        await sink.consume(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .outputText(text: "debug", isFinal: false)
        ))
        expect(
            await sink.currentTurnOutputEventCount == 1,
            "Debug sink tracks current output turn"
        )
        await sink.consume(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .inputSpeechStarted
        ))
        expect(
            await sink.currentTurnOutputEventCount == 0,
            "speech_started clears Debug output sink"
        )
    }

    private static func testOutputDeviceChangeThroughController() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "device-change fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .speaking
        }
        stack.outputMonitor.changeOutput(
            identifier: "replacement-output",
            name: "Replacement Output",
            available: true
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state == .idle
                && stack.controller.realtimeSpeechStateSnapshot
                    .lastStandardError == "unavailable"
        }
        await waitUntil {
            let eventTypes = try await sentEventTypes(transport)
            let closeCount = await transport.calls.filter {
                $0 == .close(.normal)
            }.count
            return eventTypes.filter { $0 == "response.cancel" }.count == 1
                && closeCount == 1
        }
        let eventTypes = try await sentEventTypes(transport)
        expect(
            eventTypes.filter { $0 == "response.cancel" }.count == 1,
            "output device change cancels Provider once"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.count == 1,
            "output device change closes Provider once"
        )
    }

    private static func testStopClearsActivePlaybackThroughController() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "active Stop fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .speaking
        }
        await stack.controller.stopSpeechAudioCapture()
        await stack.controller.stopSpeechAudioCapture()
        expect(
            stack.controller.nativeSpeechPlaybackDebugSnapshot.stopClearCount
                == 1,
            "duplicate Stop clears active playback once"
        )
        expect(
            stack.controller.speechAudioOutputHostSnapshot.state == .closed,
            "Stop closes active output host"
        )
        expect(
            stack.controller.realtimeSpeechStateSnapshot.state == .idle,
            "Stop returns active playback to idle"
        )
        stack.outputPlayer.completeStoppedChunk()
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechAudioOutputHostSnapshot
                .rejectedCallbackCount == 1
        }
        expect(
            stack.controller.speechAudioOutputHostSnapshot.playedChunkCount
                == 0,
            "Stop rejects late playback completion"
        )
        let eventTypes = try await sentEventTypes(transport)
        expect(
            eventTypes.filter { $0 == "response.cancel" }.count == 1,
            "duplicate Stop cancels Provider once"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.count == 1,
            "duplicate Stop closes Provider once"
        )
    }

    private static func testConversionFailureThroughController() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        stack.outputPlayer.scheduleError = .conversionFailed
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "conversion failure fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state == .idle
                && stack.controller.realtimeSpeechStateSnapshot
                    .lastStandardError == "transport_failure"
        }
        expect(
            stack.controller.speechAudioOutputHostSnapshot.lastError
                == "conversion_failed",
            "conversion failure retains Host diagnosis"
        )
        let eventTypes = try await sentEventTypes(transport)
        expect(
            eventTypes.filter { $0 == "response.cancel" }.count == 1,
            "conversion failure cancels Provider once"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.count == 1,
            "conversion failure closes Provider once"
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
            }
        )
    }

    private static func makeControllerStack(
        transport: FakeRealtimeWebSocketTransport
    ) -> (
        controller: AppController,
        orchestration: OrchestrationKernel,
        capture: DuplexAudioCapture,
        adapter: StepFunRealtimeAdapter,
        outputPlayer: FakeMacSpeechAudioOutputPlayer,
        outputMonitor: FakeMacSpeechOutputDeviceMonitor
    ) {
        let runtimeStack = makeRuntimeStack(transport: transport)
        let capture = DuplexAudioCapture()
        let host = MacSpeechAudioHost(
            authorizationProvider: DuplexAuthorizationProvider(),
            capture: capture,
            deviceMonitor: DuplexDeviceMonitor()
        )
        let outputPlayer = FakeMacSpeechAudioOutputPlayer()
        let outputMonitor = FakeMacSpeechOutputDeviceMonitor()
        let outputHost = MacSpeechAudioOutputHost(
            player: outputPlayer,
            deviceMonitor: outputMonitor
        )
        return (
            AppController(
                orchestrationKernel: runtimeStack.orchestration,
                speechAudioHost: host,
                speechAudioOutputHost: outputHost
            ),
            runtimeStack.orchestration,
            capture,
            runtimeStack.adapter,
            outputPlayer,
            outputMonitor
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

    private static func handshakeTransport(
        responseCancelDelay: Duration = .zero
    ) -> FakeRealtimeWebSocketTransport {
        FakeRealtimeWebSocketTransport(
            frames: [
                .text(#"{"type":"session.created"}"#),
                .text(#"{"type":"session.updated"}"#)
            ],
            responseCancelDelay: responseCancelDelay,
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
        line: UInt = #line,
        _ condition: @escaping @MainActor () async throws -> Bool
    ) async {
        waitIndex += 1
        let currentWait = waitIndex
        for _ in 0 ..< 400 {
            if (try? await condition()) == true { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        fatalError(
            "FAILED: timed out waiting for duplex state #\(currentWait) at line \(line)"
        )
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
