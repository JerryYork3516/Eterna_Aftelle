@preconcurrency import AVFoundation
import Foundation

private struct DuplexCredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        if keyRef.contains("provider.qwen") {
            return try QwenRealtimeCredential(
                workspaceID: "workspace-test",
                secret: "fake-token"
            ).storedValue()
        }
        return "fake-token"
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
    private let acousticEchoHost = MacSpeechAcousticEchoHost(
        mode: .appleVoiceProcessing
    )

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

    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot? {
        acousticEchoHost.snapshot()
    }

    func resetAcousticEchoDiagnostics() {
        acousticEchoHost.resetDiagnostics()
    }

    var isStarted: Bool { lock.withLock { started } }

    @discardableResult
    func emit(_ marker: UInt8) -> Bool {
        emit(bytes: Data(repeating: marker, count: 960))
    }

    @discardableResult
    func emitPacket(_ marker: UInt8) -> Bool {
        emit(bytes: Data(repeating: marker, count: 960))
    }

    private func emit(bytes: Data) -> Bool {
        let target = lock.withLock { (started, frameBuffer, generation) }
        guard target.0,
              let frameBuffer = target.1,
              let generation = target.2 else {
            return false
        }
        return frameBuffer.append(
            pcm16Bytes: bytes,
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

private actor DirectOutputEventSource {
    private var events: [NativeSpeechEventDisposition] = []
    private var pendingReceive: CheckedContinuation<
        Result<NativeSpeechEventDisposition, NativeSpeechError>, Never
    >?

    func enqueue(_ event: NativeSpeechEventDisposition) {
        if let pendingReceive {
            self.pendingReceive = nil
            pendingReceive.resume(returning: .success(event))
        } else {
            events.append(event)
        }
    }

    func receive() async -> Result<
        NativeSpeechEventDisposition, NativeSpeechError
    > {
        if !events.isEmpty {
            return .success(events.removeFirst())
        }
        return await withCheckedContinuation { continuation in
            pendingReceive = continuation
        }
    }
}

private actor BlockingOutputConsumer {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var shouldBlockMedia = true
    private(set) var mediaStarted = false
    private(set) var mediaConsumedCount = 0
    private(set) var outputTextConsumedCount = 0
    private(set) var cancelledMediaCompletion = false
    private(set) var controlConsumed = false

    func consume(_ event: NativeSpeechEvent) async {
        switch event.kind {
        case .outputAudio:
            mediaStarted = true
            if shouldBlockMedia {
                shouldBlockMedia = false
                await withCheckedContinuation { continuation in
                    releaseContinuation = continuation
                }
                cancelledMediaCompletion = Task.isCancelled
            }
            mediaConsumedCount += 1
        case .inputSpeechStarted:
            controlConsumed = true
        case .outputText:
            outputTextConsumedCount += 1
        default:
            break
        }
    }

    func releaseMedia() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor BlockingSubtitleNotification {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var started = false

    func notify() async {
        started = true
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor SlowOrderedOutputConsumer {
    private(set) var mediaCompleted = false
    private(set) var responseCompleted = false
    private(set) var responseFollowedMedia = false

    func consume(_ event: NativeSpeechEvent) async {
        switch event.kind {
        case .outputAudio:
            try? await Task.sleep(for: .milliseconds(300))
            mediaCompleted = true
        case .responseCompleted:
            responseCompleted = true
            responseFollowedMedia = mediaCompleted
        default:
            break
        }
    }
}

private actor InterruptPreclearProbe {
    private(set) var preclearCount = 0
    private(set) var controlObservedPreclear = false

    func preclear() {
        preclearCount += 1
    }

    func consume(_ event: NativeSpeechEvent) {
        guard case .inputSpeechStarted = event.kind else { return }
        controlObservedPreclear = preclearCount == 1
    }
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
        testRealSequenceSubtitleSynchronizer()
        try await testQwenHostChainThroughController()
        try await testHandshakeDoesNotRunCaptureProducer()
        try await testFullDuplexThroughController()
        try await testPlaybackStallThroughController()
        try await testInterruptThroughController()
        try await testInterruptAfterProviderCompletionThroughController()
        try await testOutputDeviceChangeThroughController()
        try await testStopClearsActivePlaybackThroughController()
        try await testConversionFailureThroughController()
        await testDebugSinkClearsInterruptedOutput()
        await testMediaCapacityBackpressurePreservesInteraction()
        await testControlBypassesBlockedMedia()
        await testSubtitleMailboxBypassesBlockedMedia()
        await testSpeechStartPreclearsBeforeConsumer()
        try await testSlowConsumerPreservesInteraction()
        try await testRecoverableTurnFailurePreservesBridge()
        try await testThinkingInterruptPreservesInteraction()
        try await testReceiveFailureAndDuplicateStart()
        try await testStaleCancelledAndClosedOutput()
        try await testCumulativeSubtitleThroughController()
        try await testStopDoesNotExposeUnplayedFinalThroughController()
        try await testLateUserFinalThroughController()
        try await testTextSubtitleSurvivesRealtimeRefresh()
        try await testRedactedDiagnosticsAndExport()
        print("native_speech_duplex_checks=\(checks)")
    }

    private static func testQwenHostChainThroughController() async throws {
        let transport = handshakeTransport()
        let stack = makeQwenControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "Qwen Host fixture loads"
        )
        expect(
            stack.controller.nativeSpeechProviderDebugState.profile
                == qwenProfile(),
            "AppController selects the Beijing Qwen Flash profile"
        )
        let flashProfile = stack.controller.nativeSpeechProviderDebugState
            .profile
        stack.controller.selectNativeSpeechModel(
            Stage75QwenRealtimeModel.plus.rawValue
        )
        let plusProfile = stack.controller.nativeSpeechProviderDebugState
            .profile
        expect(
            plusProfile.modelID == Stage75QwenRealtimeModel.plus.rawValue
                && plusProfile.endpoint.query
                    == "model=\(Stage75QwenRealtimeModel.plus.rawValue)",
            "Qwen A/B selector changes the model and endpoint together"
        )
        expect(
            plusProfile.profileID == flashProfile.profileID
                && plusProfile.providerID == flashProfile.providerID
                && plusProfile.adapterID == flashProfile.adapterID
                && plusProfile.voiceID == flashProfile.voiceID
                && plusProfile.inputAudioFormat
                    == flashProfile.inputAudioFormat
                && plusProfile.outputAudioFormat
                    == flashProfile.outputAudioFormat
                && plusProfile.turnDetection == flashProfile.turnDetection
                && plusProfile.languageMetadata
                    == flashProfile.languageMetadata
                && plusProfile.keyRef == flashProfile.keyRef,
            "Qwen A/B selector holds every non-model contract fixed"
        )
        stack.controller.selectNativeSpeechModel(
            Stage75QwenRealtimeModel.flash.rawValue
        )
        expect(
            stack.controller.nativeSpeechProviderDebugState.profile
                == flashProfile,
            "Qwen A/B selector restores the Flash baseline"
        )

        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        stack.controller.selectNativeSpeechModel(
            Stage75QwenRealtimeModel.plus.rawValue
        )
        expect(
            stack.controller.nativeSpeechProviderDebugState.profile
                == flashProfile,
            "Qwen A/B selector cannot change an active realtime session"
        )
        for marker in UInt8(1) ... UInt8(5) {
            expect(
                stack.capture.emitPacket(marker),
                "Qwen Host emits a 20 ms PCM16 packet"
            )
        }
        await waitUntil {
            try await audioAppendObjects(transport).count == 1
        }
        let append = try await audioAppendObjects(transport)
        let encoded = append.first?["audio"] as? String
        let decodedPacket = encoded.flatMap { Data(base64Encoded: $0) }
        expect(
            decodedPacket?.count == 4_800,
            "Qwen Adapter aggregates five Host packets to 100 ms"
        )

        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_started","item_id":"qwen-user-1"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"qwen-user-1","text":"你","stash":"好"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"qwen-user-1","transcript":"你好"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"qwen-user-1"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"qwen-response-1"}}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio_transcript.delta","response_id":"qwen-response-1","item_id":"qwen-resident-1","delta":"你好，"}"#
        ))
        await transport.enqueue(subtitleAudioFrame(
            responseID: "qwen-response-1",
            itemID: "qwen-resident-1",
            seed: 21
        ))
        await transport.enqueue(subtitleAudioFrame(
            responseID: "qwen-response-1",
            itemID: "qwen-resident-1",
            seed: 22
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio_transcript.done","response_id":"qwen-response-1","item_id":"qwen-resident-1","transcript":"你好，我在。"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.done","response_id":"qwen-response-1","item_id":"qwen-resident-1"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"qwen-response-1","status":"completed"}}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                    .completedResponseCount == 1
                && stack.controller.realtimeSpeechSubtitleSnapshot.userFinal
                    == "你好"
                && stack.controller.realtimeSpeechSubtitleSnapshot
                    .residentFinal == "你好，我在。"
        }
        expect(
            stack.controller.realtimeSpeechStateSnapshot
                .lastTurnDetectionSource == .serverVAD,
            "Qwen semantic VAD events remain Runtime-owned turn detection"
        )
        await waitUntil { stack.outputPlayer.scheduledCount == 2 }
        stack.outputPlayer.completeScheduledChunk()
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                    == .listening
                && stack.controller.particleSubtitleState.text
                    == "你好，我在。"
        }
        expect(
            stack.controller.sessionState.dialogueEntries.map(\.text)
                == ["你好", "你好，我在。"],
            "Qwen played turn enters the shared dialogue history"
        )

        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_started","item_id":"qwen-user-2"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"qwen-user-2"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"qwen-response-2"}}"#
        ))
        await transport.enqueue(subtitleAudioFrame(
            responseID: "qwen-response-2",
            itemID: "qwen-resident-2",
            seed: 23
        ))
        await transport.enqueue(subtitleAudioFrame(
            responseID: "qwen-response-2",
            itemID: "qwen-resident-2",
            seed: 24
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .speaking
        }
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_started","item_id":"qwen-user-3"}"#
        ))
        await waitUntil {
            let eventTypes = try await sentEventTypes(transport)
            return eventTypes.filter { $0 == "response.cancel" }.count == 1
                && stack.controller.nativeSpeechPlaybackDebugSnapshot
                    .interruptClearCount == 1
        }
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"qwen-response-2","status":"incomplete"}}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"qwen-response-2","item_id":"qwen-resident-2","delta":"AQI="}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"qwen-user-3"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"qwen-response-3"}}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"qwen-response-3","status":"completed"}}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                    .completedResponseCount == 2
                && stack.controller.realtimeSpeechStateSnapshot.state
                    == .listening
        }
        expect(
            await stack.adapter.ignoredEventCount >= 1,
            "Qwen Adapter filters output arriving after Interrupt"
        )
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump
                && stack.controller.speechOutputBridgeSnapshot
                    .hasActiveReceiveLoop,
            "Qwen Interrupt preserves the active capture and receive chain"
        )
        expect(
            stack.controller.sessionState.dialogueEntries.map(\.text)
                == ["你好", "你好，我在。"],
            "interrupted and stale Qwen turns do not enter history"
        )

        await stack.controller.stopSpeechAudioCapture()
        let eventTypes = try await sentEventTypes(transport)
        expect(
            eventTypes.filter { $0 == "response.cancel" }.count == 1,
            "Stop after response.done sends no stale Qwen cancel"
        )
        expect(
            eventTypes.filter { $0 == "session.finish" }.count == 1,
            "Stop closes the Qwen session explicitly"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.count == 1,
            "Stop closes the Qwen WebSocket once"
        )
    }

    private static func testRealSequenceSubtitleSynchronizer() {
        var synchronizer = RealtimeSpeechPlaybackSubtitleSynchronizer()
        let interactionID = NativeSpeechInteractionID(rawValue: UUID(
            uuidString: "00000000-0000-0000-0000-000000000091"
        )!)
        let identity = RealtimeSpeechPlaybackSubtitleIdentity(
            interactionID: interactionID,
            turnNumber: 1,
            turnGeneration: 1,
            playbackGeneration: 10
        )
        synchronizer.prepare(identity: identity)
        synchronizer.advance(playedSequence: 10, identity: identity)
        expect(
            synchronizer.applyPartial(
                text: "我",
                requiredAudioSequence: 10,
                identity: identity
            ),
            "partial releases only after its real audio sequence"
        )
        expect(
            !synchronizer.applyPartial(
                text: "我是",
                requiredAudioSequence: 20,
                identity: identity
            ),
            "future audio cannot release a resident partial"
        )
        synchronizer.advance(playedSequence: 19, identity: identity)
        expect(synchronizer.displayText == "我",
               "an unplayed sequence cannot advance subtitles")
        synchronizer.advance(playedSequence: 20, identity: identity)
        expect(
            synchronizer.applyPartial(
                text: "我是",
                requiredAudioSequence: 20,
                identity: identity
            ),
            "matching playback waterline advances the partial"
        )
        expect(synchronizer.displayText == "我是",
               "matching played sequence advances the partial")
        expect(
            synchronizer.enqueueFinal(
                text: "我是林轩",
                identity: identity
            ),
            "current playback identity accepts its final"
        )
        synchronizer.completePlayback(identity: identity)
        expect(synchronizer.displayText == "我是林轩",
               "final locks only after playback completion")

        synchronizer.reset()
        let nextIdentity = RealtimeSpeechPlaybackSubtitleIdentity(
            interactionID: interactionID,
            turnNumber: 2,
            turnGeneration: 2,
            playbackGeneration: 11
        )
        synchronizer.prepare(identity: nextIdentity)
        synchronizer.advance(
            playedSequence: 30,
            identity: nextIdentity
        )
        expect(
            synchronizer.applyPartial(
                text: "已播放水位",
                requiredAudioSequence: 30,
                identity: nextIdentity
            ),
            "partial can bind after its chunkPlayed callback"
        )
        expect(
            synchronizer.displayText == "已播放水位",
            "late-bound partial releases immediately at played waterline"
        )
        expect(
            !synchronizer.applyPartial(
                text: "旧轮次",
                requiredAudioSequence: 30,
                identity: identity
            ),
            "old turn and playback generation cannot restore a subtitle"
        )

        synchronizer.reset()
        expect(
            synchronizer.displayText == nil
                && !synchronizer.hasPendingText,
            "Interrupt reset clears displayed and pending resident subtitles"
        )
        synchronizer.noteUnplayedResponse()
        expect(
            synchronizer.displayText == nil,
            "unplayed response cannot bypass playback completion"
        )
        synchronizer.resetForTerminal(
            canonicalCompleted: RealtimeSpeechCompletedSubtitle(
                interactionShortID: "00000000",
                turnNumber: 1,
                turnGeneration: 1,
                userFinal: nil,
                residentFinal: "我是林轩"
            )
        )
        expect(
            synchronizer.displayText == "我是林轩",
            "terminal cleanup retains a played canonical subtitle"
        )
        synchronizer.resetForTerminal(
            canonicalCompleted: RealtimeSpeechCompletedSubtitle(
                interactionShortID: "00000000",
                turnNumber: 2,
                turnGeneration: 2,
                userFinal: nil,
                residentFinal: "我是林轩"
            )
        )
        expect(
            synchronizer.displayText == nil,
            "same text from another Runtime turn cannot pass terminal identity"
        )
    }

    private static func testRecoverableTurnFailurePreservesBridge()
        async throws
    {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData)
                .isLoaded,
            "recoverable turn failure fixture loads"
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
            .text(#"{"type":"response.created","response":{"id":"failed-turn"}}"#)
        )
        await transport.enqueue(.text(
            #"{"event_id":"failed-partial","type":"response.audio_transcript.delta","response_id":"failed-turn","item_id":"failed-item","delta":"旧字幕"}"#
        ))
        await transport.enqueue(.text(
            #"{"event_id":"failed-final","type":"response.audio_transcript.done","response_id":"failed-turn","item_id":"failed-item","transcript":"旧字幕终稿"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"failed-turn","item_id":"failed-item","delta":"AQI="}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechAudioOutputHostSnapshot
                .enqueuedChunkCount == 1
        }
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"id":"failed-turn","status":"failed"}}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            let state = stack.controller.realtimeSpeechStateSnapshot
            return state.state == .listening
                && state.currentTurnNumber == 2
                && stack.controller.speechAudioOutputHostSnapshot
                    .queueDepth == 0
                && stack.controller.nativeSpeechPlaybackDebugSnapshot
                    .turnNumber == nil
        }
        let afterFailure = stack.controller.speechOutputBridgeSnapshot
        expect(afterFailure.state == .configured, "turn failure keeps output bridge configured")
        expect(afterFailure.hasActiveReceiveLoop, "turn failure keeps receive loop active")
        expect(afterFailure.terminalStatus == nil, "turn failure is not bridge terminal")
        expect(afterFailure.lastError == "unavailable", "bridge exposes recoverable turn error")
        expect(
            stack.controller.realtimeSpeechStateSnapshot
                .interactionTerminalOutcome == nil,
            "turn failure keeps Runtime interaction nonterminal"
        )
        expect(
            stack.controller.speechAudioHostSnapshot.isCapturing,
            "turn failure keeps microphone capture active"
        )
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "turn failure keeps the input pump active"
        )
        expect(
            stack.controller.nativeSpeechPlaybackDebugSnapshot
                .turnNumber == nil,
            "turn failure clears the old playback binding"
        )
        expect(
            stack.controller.particleSubtitleState.text != "旧字幕"
                && stack.controller.particleSubtitleState.text
                    != "旧字幕终稿",
            "turn failure clears pending and final old-turn subtitles"
        )

        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.created","response":{"id":"recovered-turn"}}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"id":"recovered-turn","status":"completed"}}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            let state = stack.controller.realtimeSpeechStateSnapshot
            return state.state == .listening
                && state.currentTurnNumber == 3
                && state.completedTurnCount == 1
        }
        expect(
            stack.controller.speechOutputBridgeSnapshot
                .completedResponseCount == 1,
            "same receive loop completes the next turn"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.isEmpty,
            "recoverable turn failure does not close WebSocket"
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testThinkingInterruptPreservesInteraction()
        async throws
    {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData)
                .isLoaded,
            "thinking Interrupt fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_started","item_id":"first-user"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"first-user"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"old-response"}}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .thinking
        }

        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_started","item_id":"second-user"}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            let types = try await sentEventTypes(transport)
            return stack.controller.realtimeSpeechStateSnapshot.state
                    == .listening
                && stack.controller.realtimeSpeechStateSnapshot
                    .interruptedTurnCount == 1
                && types.filter { $0 == "response.cancel" }.count == 1
        }
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"old-response","status":"incomplete"}}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"second-user"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"new-response"}}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"new-response","status":"completed"}}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                    .completedResponseCount == 1
                && stack.controller.realtimeSpeechStateSnapshot.state
                    == .listening
        }
        expect(
            stack.controller.realtimeSpeechStateSnapshot
                .interactionTerminalOutcome == nil,
            "thinking Interrupt keeps the interaction nonterminal"
        )
        expect(
            stack.controller.realtimeSpeechStateSnapshot
                .currentTurnNumber == 3,
            "same WebSocket completes the turn after thinking Interrupt"
        )
        expect(
            stack.controller.realtimeSpeechDiagnosticTimeline.events
                .filter { $0.category == "standard_turn_failed" }
                .isEmpty,
            "late incomplete response cannot override Interrupt"
        )
        let connectCount = await transport.calls.filter {
            if case .connect = $0 { return true }
            return false
        }.count
        expect(connectCount == 1, "thinking Interrupt reuses one WebSocket")
        await stack.controller.stopSpeechAudioCapture()
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
        expect(object["schema_version"] as? Int == 4,
               "diagnostic export freezes schema version 4")
        expect(object["events"] is [[String: Any]],
               "diagnostic export contains structured events")
        let acousticEcho = object["acoustic_echo"] as? [String: Any]
        expect(acousticEcho?["available"] as? Bool == true,
               "diagnostic export includes Host AEC diagnostics")
        expect(acousticEcho?["mode"] as? String == "appleVoiceProcessing",
               "diagnostic export maps the Host audio mode")
        for metric in [
            "input_classification",
            "source_forwarded_frame_count",
            "source_suppressed_frame_count",
            "source_timing_candidate_frame_count",
            "source_timing_unavailable_frame_count",
            "fallback_count",
            "last_fallback_reason"
        ] {
            expect(
                acousticEcho?[metric] != nil
                    || metric == "last_fallback_reason",
                "diagnostic export includes acoustic (metric)"
            )
        }
        for metric in [
            "input_send_operation_count",
            "input_average_send_duration_milliseconds",
            "input_maximum_send_duration_milliseconds",
            "capture_generated_frame_count",
            "capture_dropped_frame_count",
            "capture_queued_frame_count",
            "output_runtime_rejected_event_count"
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
        let visibleTextBeforeUserPartials =
            stack.controller.particleSubtitleState.text
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"subtitle-user","text":"你","stash":"好"}"#)
        )
        await waitUntil {
            stack.orchestration.realtimeSpeechSubtitleSnapshot().userPartial
                == "你好"
        }
        expect(
            stack.controller.particleSubtitleState.text
                == visibleTextBeforeUserPartials,
            "user partials never change the visible subtitle"
        )
        await transport.enqueue(
            .text(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"你好"}"#)
        )
        await waitUntil {
            stack.controller.realtimeSpeechSubtitleSnapshot.userFinal
                == "你好"
        }
        await waitUntil {
            stack.controller.particleSubtitleState.text == "你好"
        }
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.created","response":{"id":"response-one"}}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-one","delta":"我是林轩，"}"#)
        )
        for seed in UInt8(1) ... UInt8(5) {
            await transport.enqueue(subtitleAudioFrame(
                responseID: "response-one",
                itemID: "item-one",
                seed: seed
            ))
        }
        await waitUntil {
            stack.controller.realtimeSpeechSubtitleSnapshot.residentPartial
                == "我是林轩，"
        }
        expect(
            stack.controller.particleSubtitleState.text != "我是林轩，",
            "resident phrase waits for matching local playback"
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio_transcript.done","response_id":"response-one","item_id":"item-one","transcript":"我是林轩。"}"#)
        )
        expect(
            stack.controller.particleSubtitleState.text != "我是林轩。",
            "resident final remains deferred before response boundary"
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"id":"response-one","status":"completed"}}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                    .completedResponseCount == 1
                && stack.controller.realtimeSpeechSubtitleSnapshot
                    .residentFinal == "我是林轩。"
        }
        expect(
            stack.controller.sessionState.dialogueEntries.isEmpty,
            "response completion alone does not write voice history"
        )
        await waitUntil { stack.outputPlayer.scheduledCount == 4 }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil { stack.outputPlayer.scheduledCount == 5 }
        stack.outputPlayer.completeScheduledChunk()
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil {
            stack.controller.particleSubtitleState.text == "我是林轩，"
        }
        expect(
            stack.controller.particleSubtitleState.text == "我是林轩，",
            "matching local playback releases the resident phrase"
        )
        stack.outputPlayer.completeScheduledChunk()
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil {
            stack.controller.particleSubtitleState.text == "我是林轩。"
        }
        expect(
            stack.controller.particleSubtitleState.text == "我是林轩。",
            "playback completion releases the final voice subtitle"
        )
        await waitUntil {
            stack.controller.sessionState.dialogueEntries.count == 2
        }
        let completedEntries = stack.controller.sessionState.dialogueEntries
        expect(
            completedEntries.map(\.role) == ["user", "resident"]
                && completedEntries.map(\.text)
                    == ["你好", "我是林轩。"],
            "played voice turn reuses the existing dialogue history"
        )
        let completedAuditEntries =
            stack.controller.dialogueAuditState.entries
        expect(
            completedAuditEntries.map(\.role) == [.user, .resident]
                && completedAuditEntries.map(\.text)
                    == ["你好", "我是林轩。"],
            "played voice turn appears in the existing history UI"
        )
        stack.outputPlayer.completeScheduledChunk()
        expect(
            stack.controller.sessionState.dialogueEntries == completedEntries,
            "duplicate playback completion cannot duplicate voice history"
        )
        expect(
            stack.controller.dialogueAuditState.entries
                == completedAuditEntries,
            "duplicate playback completion cannot duplicate history UI"
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testStopDoesNotExposeUnplayedFinalThroughController()
        async throws
    {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData)
                .isLoaded,
            "unplayed terminal subtitle fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_started","item_id":"stop-user"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"stop-user","transcript":"停止前的问题"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"stop-user"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"stop-response"}}"#
        ))
        await transport.enqueue(.text(
            #"{"event_id":"stop-partial","type":"response.audio_transcript.delta","response_id":"stop-response","item_id":"stop-item","delta":"未播放"}"#
        ))
        await transport.enqueue(.text(
            #"{"event_id":"stop-final","type":"response.audio_transcript.done","response_id":"stop-response","item_id":"stop-item","transcript":"未播放终稿"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"stop-response","item_id":"stop-item","delta":"AQI="}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"stop-response","item_id":"stop-item","delta":"AwQ="}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.done","response_id":"stop-response","item_id":"stop-item"}"#
        ))
        await waitUntil {
            stack.controller.realtimeSpeechSubtitleSnapshot.residentFinal
                == "未播放终稿"
        }
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"stop-response","status":"completed"}}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                .completedResponseCount == 1
        }
        expect(
            stack.controller.realtimeSpeechSubtitleSnapshot.userFinal
                == "停止前的问题"
                && stack.controller.realtimeSpeechSubtitleSnapshot
                    .residentFinal == "未播放终稿"
                && stack.controller.realtimeSpeechSubtitleSnapshot
                    .userFinalLocked
                && stack.controller.realtimeSpeechSubtitleSnapshot
                    .residentFinalLocked,
            "response completion has both locked voice finals"
        )
        expect(
            stack.controller.sessionState.dialogueEntries.isEmpty,
            "completed response stays out of history before playback"
        )
        await waitUntil {
            stack.outputPlayer.scheduledCount > 0
        }
        expect(
            stack.controller.particleSubtitleState.text != "未播放终稿",
            "resident final waits for real playback completion"
        )
        await stack.controller.stopSpeechAudioCapture()
        expect(
            stack.controller.particleSubtitleState.text != "未播放终稿",
            "Stop cannot expose a Runtime-completed but unplayed final"
        )
        expect(
            stack.controller.sessionState.dialogueEntries.isEmpty,
            "Stop cannot write an unplayed voice response to history"
        )
    }

    private static func testLateUserFinalThroughController() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "late user final fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_started","item_id":"late-user"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"late-user"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"late-response"}}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"late-response","delta":"AQI="}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"late-response","delta":"AwQ="}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .speaking
        }
        let rejectedBefore = stack.controller
            .realtimeSpeechSubtitleSnapshot.rejectedEventCount
        await transport.enqueue(.text(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"late-user","transcript":"播放开始后到达的完整输入"}"#
        ))
        await waitUntil {
            stack.controller.realtimeSpeechSubtitleSnapshot.userFinal
                == "播放开始后到达的完整输入"
        }
        expect(
            stack.controller.realtimeSpeechStateSnapshot.state == .speaking,
            "late user final keeps the controller in speaking"
        )
        expect(
            stack.controller.realtimeSpeechSubtitleSnapshot
                .rejectedEventCount == rejectedBefore,
            "late current-turn final is not rejected by Runtime"
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testHandshakeDoesNotRunCaptureProducer() async throws {
        let transport = FakeRealtimeWebSocketTransport(waitsWhenEmpty: true)
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "startup fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        expect(stack.capture.isStarted, "standalone capture starts normally")

        let startTask = Task { @MainActor in
            await stack.controller.startNativeSpeechInputBridge()
        }
        await waitUntil {
            await transport.calls.contains(.receive)
                && !stack.capture.isStarted
        }
        for marker in UInt8(1) ... UInt8(60) {
            expect(
                !stack.capture.emit(marker),
                "handshake does not run the capture producer"
            )
        }

        await transport.enqueue(.text(#"{"type":"session.created"}"#))
        await transport.enqueue(.text(#"{"type":"session.updated"}"#))
        await startTask.value
        expect(stack.capture.isStarted, "capture starts after handshake")
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "input pump starts beside the capture producer"
        )
        expect(stack.capture.emit(61), "post-handshake frame is accepted")
        await waitUntil {
            try await audioAppendObjects(transport).count == 1
        }
        await stack.controller.refreshMicrophoneAuthorization()
        expect(
            stack.controller.speechAudioHostSnapshot.droppedFrameCount == 0,
            "interaction generation starts without buffered frame loss"
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
        await stack.controller.startNativeSpeechInputBridge()
        let initialInteractionShortID = stack.controller
            .realtimeSpeechStateSnapshot.interactionShortID
        expect(
            initialInteractionShortID != nil,
            "ten-turn interaction has an identity"
        )
        for marker in UInt8(1) ... UInt8(3) {
            expect(stack.capture.emit(marker), "Fake source emits input frame")
        }
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
            .text(#"{"type":"response.created"}"#)
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
            .text(#"{"type":"response.created"}"#)
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

        for turn in 3 ... 10 {
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
                .text(#"{"type":"response.created"}"#)
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
        expect(inputObjects.count == 14, "ten turns keep sending input")
        let inputMarkers = inputObjects.compactMap { object -> UInt8? in
            guard let encoded = object["audio"] as? String,
                  let data = Data(base64Encoded: encoded) else { return nil }
            return data.first
        }
        expect(
            inputMarkers == Array(UInt8(1) ... UInt8(14)),
            "ten-turn input preserves order"
        )

        let output = stack.controller.speechOutputBridgeSnapshot
        expect(output.state == .configured, "tenth response keeps bridge configured")
        expect(output.completedResponseCount == 10, "ten response boundaries arrive")
        expect(output.outputAudioChunkCount == 11, "ten responses reach AppController")
        expect(output.outputAudioByteCount == 22, "ten-response byte count reaches AppController")
        expect(output.firstChunkLatencyMilliseconds != nil, "first chunk latency is recorded")
        expect(output.hasActiveReceiveLoop, "tenth response keeps receive loop active")
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "tenth response keeps input pump active"
        )
        expect(
            stack.controller.realtimeSpeechStateSnapshot.interactionShortID
                == initialInteractionShortID,
            "ten turns preserve one interaction"
        )
        expect(
            await transport.maximumConcurrentReceiveCount == 1,
            "all responses share one receive loop"
        )
        expect(
            await stack.adapter.ignoredEventCount == 1,
            "unknown events are ignored while audio.done closes subtitles"
        )
        let eventTypes = try await sentEventTypes(transport)
        expect(!eventTypes.contains("input_audio_buffer.commit"), "no input commit is sent")
        expect(!eventTypes.contains("response.create"), "no response.create is sent")
        let connectCount = await transport.calls.filter {
            if case .connect = $0 { return true }
            return false
        }.count
        expect(connectCount == 1, "ten responses reuse one WebSocket")
        expect(
            stack.controller.speechAudioOutputHostSnapshot
                .playbackStartedCount == 10,
            "ten responses emit one playbackStarted each"
        )
        expect(
            stack.controller.speechAudioOutputHostSnapshot
                .playbackCompletedCount == 10,
            "ten responses emit one playbackCompleted each"
        )
        let closeCountBeforeStop = await transport.calls.filter {
            $0 == .close(.normal)
        }.count
        expect(closeCountBeforeStop == 0, "ten responses keep transport open")

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

    private static func testPlaybackStallThroughController() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "playback stall fixture loads"
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
            .text(#"{"type":"response.created"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#)
        )
        await waitUntil {
            stack.controller.realtimeSpeechStateSnapshot.state == .speaking
        }
        stack.outputPlayer.completeScheduledChunk()
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil {
            stack.controller.speechAudioOutputHostSnapshot.state == .stalled
                && stack.controller.realtimeSpeechStateSnapshot.state
                    == .thinking
        }
        expect(
            stack.controller.residentVisualIntent == .thinking,
            "playback starvation maps ParticleCore to thinking"
        )
        expect(
            stack.controller.residentSpeechSignal.phase == .ended,
            "playback starvation ends the speech signal"
        )

        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"BQY="}"#)
        )
        expect(
            stack.outputPlayer.scheduledCount == 2,
            "one resumed chunk waits for prebuffer"
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"Bwg="}"#)
        )
        await waitUntil {
            stack.controller.speechAudioOutputHostSnapshot.state == .playing
                && stack.controller.realtimeSpeechStateSnapshot.state
                    == .speaking
        }
        expect(
            stack.controller.residentVisualIntent == .speaking,
            "resumed PCM restores ParticleCore speaking"
        )
        expect(
            stack.controller.speechAudioOutputHostSnapshot
                .playbackStartedCount == 1,
            "stall resume does not create a second formal playback start"
        )

        stack.outputPlayer.completeScheduledChunk()
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil {
            stack.controller.speechAudioOutputHostSnapshot.state == .stalled
        }
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await waitUntil {
            let eventTypes = try await sentEventTypes(transport)
            return stack.controller.realtimeSpeechStateSnapshot.state
                    == .listening
                && eventTypes.filter { $0 == "response.cancel" }.count == 1
        }
        expect(
            stack.controller.nativeSpeechPlaybackDebugSnapshot
                .interruptClearCount == 1,
            "stalled output remains immediately interruptible"
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testTextSubtitleSurvivesRealtimeRefresh() async throws {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "text subtitle fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()

        await transport.enqueue(.text(
            #"{"type":"input_audio_buffer.speech_started","item_id":"old-user"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"old-user","transcript":"上一句语音字幕"}"#
        ))
        await waitUntil {
            stack.controller.particleSubtitleState.text
                == "上一句语音字幕"
        }

        let response = stack.controller.step(inputText: "文字字幕测试")
        let text = response.outputText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        expect(!text.isEmpty, "text dialogue produces a subtitle")
        expect(stack.controller.particleSubtitleState.text == text,
               "text dialogue owns its active subtitle")

        try await Task.sleep(nanoseconds: 2_500_000_000)
        await stack.controller.refreshMicrophoneAuthorization()
        expect(stack.controller.particleSubtitleState.text == text,
               "stale realtime refresh cannot restore an old subtitle")

        let refreshCount = stack.controller
            .realtimeSpeechDiagnosticViewState.eventCount
        await transport.enqueue(.text(#"{"type":"session.updated"}"#))
        await waitUntil {
            stack.controller.realtimeSpeechDiagnosticViewState.eventCount
                > refreshCount
        }
        expect(stack.controller.particleSubtitleState.text == text,
               "repeated Provider refresh keeps the current text subtitle")

        await stack.controller.stopSpeechAudioCapture()
        await transport.enqueue(.text(#"{"type":"session.created"}"#))
        await transport.enqueue(.text(#"{"type":"session.updated"}"#))
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(.text(
            #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"新语音字幕"}"#
        ))
        await waitUntil {
            stack.controller.particleSubtitleState.text == "新语音字幕"
        }
        expect(stack.controller.particleSubtitleState.text == "新语音字幕",
               "new voice input takes subtitle ownership")
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testSlowConsumerPreservesInteraction() async throws {
        let transport = handshakeTransport()
        let stack = makeRuntimeStack(transport: transport)
        let consumer = SlowOrderedOutputConsumer()
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
            await consumer.consume(event)
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
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
        )
        await waitUntil {
            await consumer.responseCompleted
        }
        let active = await bridge.currentSnapshot()
        expect(active.lastError == nil, "slow sink is not a transport error")
        expect(active.hasActiveReceiveLoop, "slow sink preserves receive loop")
        expect(active.completedResponseCount == 1,
               "slow sink still completes the current turn")
        expect(
            await consumer.responseFollowedMedia,
            "response completion follows queued audio consumption"
        )
        expect(
            MacSpeechNativeOutputBridge.mediaEventCapacity == 64,
            "media lane has a fixed bounded capacity"
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

    private static func testControlBypassesBlockedMedia() async {
        let source = DirectOutputEventSource()
        let consumer = BlockingOutputConsumer()
        let interactionID = NativeSpeechInteractionID()
        let binding = NativeSpeechInputBinding(
            interactionID: interactionID,
            residentID: "resident",
            sessionID: "session",
            captureGeneration: 1
        )
        let bridge = MacSpeechNativeOutputBridge(
            receiveEvent: { _ in await source.receive() },
            consumeEvent: { event in await consumer.consume(event) },
            endInputPump: {},
            stopInput: { _, _ in .success(()) },
            closeInput: { _ in .success(()) }
        )
        _ = await bridge.start(binding: binding)
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: interactionID,
                sequenceNumber: 1,
                bytes: Data([1, 0]),
                format: .pcm16
            ))
        )))
        await waitUntil { await consumer.mediaStarted }
        for sequence in UInt64(2) ... UInt64(65) {
            await source.enqueue(.accepted(NativeSpeechEvent(
                interactionID: interactionID,
                kind: .outputAudio(NativeSpeechAudioPayload(
                    interactionID: interactionID,
                    sequenceNumber: sequence,
                    bytes: Data([UInt8(sequence), 0]),
                    format: .pcm16
                ))
            )))
        }
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .inputSpeechStarted
        )))
        await waitUntil { await consumer.controlConsumed }
        expect(
            await consumer.controlConsumed,
            "speech_started bypasses a full blocked media lane"
        )
        expect(
            await bridge.currentSnapshot().lastError == nil,
            "bounded media pressure does not fail the interaction"
        )
        await consumer.releaseMedia()
        await waitUntil { await consumer.cancelledMediaCompletion }
        expect(
            await consumer.cancelledMediaCompletion,
            "invalidated media delivery observes task cancellation"
        )
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .closed
        )))
        await waitUntil {
            !(await bridge.currentSnapshot().hasActiveReceiveLoop)
        }
    }

    private static func testSubtitleMailboxBypassesBlockedMedia() async {
        let source = DirectOutputEventSource()
        let consumer = BlockingOutputConsumer()
        let subtitleNotification = BlockingSubtitleNotification()
        let interactionID = NativeSpeechInteractionID()
        let binding = NativeSpeechInputBinding(
            interactionID: interactionID,
            residentID: "resident",
            sessionID: "session",
            captureGeneration: 1
        )
        let bridge = MacSpeechNativeOutputBridge(
            receiveEvent: { _ in await source.receive() },
            consumeEvent: { event in await consumer.consume(event) },
            residentSubtitleCheckpointReady: {
                await subtitleNotification.notify()
            },
            endInputPump: {},
            stopInput: { _, _ in .success(()) },
            closeInput: { _ in .success(()) }
        )
        _ = await bridge.start(binding: binding)
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: interactionID,
                sequenceNumber: 1,
                bytes: Data([1, 0]),
                format: .pcm16
            ))
        )))
        await waitUntil { await consumer.mediaStarted }
        for index in 0 ..< 500 {
            await source.enqueue(.accepted(NativeSpeechEvent(
                interactionID: interactionID,
                kind: .outputText(
                    text: "字幕\(index)",
                    isFinal: false
                )
            )))
        }
        await waitUntil { await subtitleNotification.started }
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: interactionID,
                sequenceNumber: 2,
                bytes: Data([2, 0]),
                format: .pcm16
            ))
        )))
        await waitUntil {
            await bridge.currentSnapshot().outputAudioChunkCount == 2
        }
        expect(
            await bridge.currentSnapshot().hasActiveReceiveLoop,
            "subtitle flood cannot fill or stop the ordered media lane"
        )
        expect(
            await consumer.outputTextConsumedCount == 0,
            "resident partials never enter the ordered MainActor consumer"
        )
        let checkpoint = await bridge.takeResidentSubtitleCheckpoint(
            interactionID: interactionID,
            throughAudioSequence: 1
        )
        expect(
            checkpoint?.text == "字幕499"
                && checkpoint?.requiredAudioSequence == 1,
            "subtitle mailbox coalesces backlog at the played waterline"
        )
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .inputSpeechStarted
        )))
        await waitUntil { await consumer.controlConsumed }
        expect(
            await subtitleNotification.started,
            "blocked subtitle notification cannot block speech_started"
        )
        expect(
            await bridge.takeResidentSubtitleCheckpoint(
                interactionID: interactionID,
                throughAudioSequence: 2
            ) == nil,
            "speech_started atomically clears old subtitle checkpoints"
        )
        await subtitleNotification.release()
        await consumer.releaseMedia()
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .closed
        )))
        await waitUntil {
            !(await bridge.currentSnapshot().hasActiveReceiveLoop)
        }
    }

    private static func testMediaCapacityBackpressurePreservesInteraction() async {
        let source = DirectOutputEventSource()
        let consumer = BlockingOutputConsumer()
        let interactionID = NativeSpeechInteractionID()
        let binding = NativeSpeechInputBinding(
            interactionID: interactionID,
            residentID: "resident",
            sessionID: "session",
            captureGeneration: 1
        )
        let bridge = MacSpeechNativeOutputBridge(
            receiveEvent: { _ in await source.receive() },
            consumeEvent: { event in await consumer.consume(event) },
            endInputPump: {},
            stopInput: { _, _ in .success(()) },
            closeInput: { _ in .success(()) }
        )
        _ = await bridge.start(binding: binding)
        for sequence in UInt64(1) ... UInt64(66) {
            await source.enqueue(.accepted(NativeSpeechEvent(
                interactionID: interactionID,
                kind: .outputAudio(NativeSpeechAudioPayload(
                    interactionID: interactionID,
                    sequenceNumber: sequence,
                    bytes: Data([UInt8(sequence), 0]),
                    format: .pcm16
                ))
            )))
        }
        await waitUntil { await consumer.mediaStarted }
        try? await Task.sleep(for: .milliseconds(50))
        let pressured = await bridge.currentSnapshot()
        expect(
            pressured.lastError == nil && pressured.hasActiveReceiveLoop,
            "full media lane applies backpressure without stopping STS"
        )
        await consumer.releaseMedia()
        await waitUntil { await consumer.mediaConsumedCount == 66 }
        expect(
            await consumer.mediaConsumedCount == 66,
            "bounded media backpressure resumes without dropping events"
        )
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .closed
        )))
        await waitUntil {
            !(await bridge.currentSnapshot().hasActiveReceiveLoop)
        }
    }

    private static func testSpeechStartPreclearsBeforeConsumer() async {
        let source = DirectOutputEventSource()
        let probe = InterruptPreclearProbe()
        let interactionID = NativeSpeechInteractionID()
        let binding = NativeSpeechInputBinding(
            interactionID: interactionID,
            residentID: "resident",
            sessionID: "session",
            captureGeneration: 1
        )
        let bridge = MacSpeechNativeOutputBridge(
            receiveEvent: { _ in await source.receive() },
            consumeEvent: { event in await probe.consume(event) },
            clearOutputForSpeechStart: { await probe.preclear() },
            endInputPump: {},
            stopInput: { _, _ in .success(()) },
            closeInput: { _ in .success(()) }
        )
        _ = await bridge.start(binding: binding)
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .inputSpeechStarted
        )))
        await waitUntil { await probe.controlObservedPreclear }
        expect(await probe.preclearCount == 1,
               "speech_started preclears local output once")
        expect(await probe.controlObservedPreclear,
               "local preclear precedes MainActor event consumption")
        expect(
            await bridge.currentSnapshot()
                .lastSpeechStartPreclearDurationMilliseconds != nil,
            "speech start exposes truthful Host preclear duration"
        )
        await source.enqueue(.accepted(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .closed
        )))
        await waitUntil {
            !(await bridge.currentSnapshot().hasActiveReceiveLoop)
        }
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
        await stack.controller.startNativeSpeechInputBridge()
        expect(stack.capture.emit(1), "interrupt test emits initial input")
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
            .text(#"{"type":"response.created","response":{"id":"interrupt-response"}}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","response_id":"interrupt-response","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","response_id":"interrupt-response","delta":"AwQ="}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .speaking
        }

        for _ in 0 ..< 12 {
            await transport.enqueue(
                .text(#"{"type":"response.audio.delta","response_id":"interrupt-response","delta":"BQY="}"#)
            )
        }
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechAudioOutputHostSnapshot
                .pressureWaitCount > 0
        }

        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await waitUntil {
            stack.outputPlayer.clearScheduledPlaybackCount == 1
        }
        expect(
            stack.outputPlayer.stopCount == 0,
            "Interrupt clears PlayerNode before stopping the audio engine"
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
        let acceptedOutputCount = stack.controller
            .speechOutputBridgeSnapshot.outputAudioChunkCount
        let ignoredEventCount = await stack.adapter.ignoredEventCount

        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","response_id":"interrupt-response","delta":"AwQ="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"id":"interrupt-response","status":"incomplete"}}"#)
        )
        await waitUntil {
            await stack.adapter.ignoredEventCount >= ignoredEventCount + 1
        }
        expect(
            stack.controller.speechOutputBridgeSnapshot.outputAudioChunkCount
                == acceptedOutputCount,
            "Qwen filters late interrupted outputAudio before Runtime"
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
            .text(#"{"type":"response.created","response":{"id":"next-response"}}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"cancelled"}}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","response_id":"next-response","delta":"Bwg="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"id":"next-response","status":"completed"}}"#)
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
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.isEmpty,
            "late response cancellation does not close the persistent session"
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

    private static func testInterruptAfterProviderCompletionThroughController()
        async throws
    {
        let transport = handshakeTransport()
        let stack = makeControllerStack(transport: transport)
        expect(
            stack.orchestration.loadResident(fixtureData: fixtureData).isLoaded,
            "completed-response Interrupt fixture loads"
        )
        await stack.controller.startSpeechAudioCapture()
        await stack.controller.startNativeSpeechInputBridge()
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_started"}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"old"}}"#
        ))
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","response_id":"old","delta":"AQI="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","response_id":"old","delta":"AwQ="}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                == .speaking
        }
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"old","status":"completed"}}"#
        ))
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.speechOutputBridgeSnapshot
                    .completedResponseCount == 1
                && stack.controller.realtimeSpeechStateSnapshot.state
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
        let sentAfterLocalInterrupt = try await sentEventTypes(transport)
        expect(
            sentAfterLocalInterrupt.filter { $0 == "response.cancel" }
                .isEmpty,
            "completed Provider response needs no wire cancel"
        )

        await transport.enqueue(
            .text(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        )
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"new"}}"#
        ))
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","response_id":"new","delta":"BQY="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","response_id":"new","delta":"Bwg="}"#)
        )
        await waitUntil {
            await stack.controller.refreshMicrophoneAuthorization()
            return stack.controller.realtimeSpeechStateSnapshot.state
                    == .speaking
                && stack.controller.speechOutputBridgeSnapshot
                    .outputAudioChunkCount == 4
        }
        expect(
            stack.controller.speechOutputBridgeSnapshot.hasActiveReceiveLoop,
            "cancel no-op keeps receive loop available for the next response"
        )
        expect(
            stack.controller.speechInputBridgeSnapshot.hasActivePump,
            "cancel no-op keeps input pump active"
        )
        expect(
            await transport.calls.filter { $0 == .close(.normal) }.isEmpty,
            "cancel no-op preserves the WebSocket"
        )
        await stack.controller.stopSpeechAudioCapture()
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
            .text(#"{"type":"response.created"}"#)
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
            .text(#"{"type":"response.created"}"#)
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
            .text(#"{"type":"response.created"}"#)
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
        try await stack.adapter.send(audio: NativeSpeechAudioPayload(
            interactionID: binding.interactionID,
            sequenceNumber: 1,
            bytes: Data(repeating: 1, count: 960),
            format: .pcm16
        ))
        await transport.enqueueFailure(.transportFailure)
        await waitUntil {
            await bridge.currentSnapshot().state == .failed
        }
        expect(
            await bridge.currentSnapshot().lastError == "transport_failure",
            "receive failure reaches standard error"
        )
        expect(
            await transport.calls.filter {
                if case .connect = $0 { return true }
                return false
            }.count == 1,
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
        await waitUntil {
            await staleTransport.calls.filter {
                $0 == .close(.normal)
            }.count == 1
        }
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
        adapter: QwenRealtimeAdapter,
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
            deviceMonitor: outputMonitor,
            configuration: MacSpeechPCMPlaybackConfiguration(
                capacity: 8,
                lowWatermark: 1,
                consumerTimeoutNanoseconds: 2_000_000_000,
                startupBufferCount: 2,
                startupBufferDurationNanoseconds: 0,
                scheduleAheadCount: 4
            )
        )
        return (
            AppController(
                orchestrationKernel: runtimeStack.orchestration,
                speechAudioHost: host,
                speechAudioOutputHost: outputHost,
                nativeSpeechProfile: profile()
            ),
            runtimeStack.orchestration,
            capture,
            runtimeStack.adapter,
            outputPlayer,
            outputMonitor
        )
    }

    private static func makeQwenControllerStack(
        transport: FakeRealtimeWebSocketTransport
    ) -> (
        controller: AppController,
        orchestration: OrchestrationKernel,
        capture: DuplexAudioCapture,
        adapter: QwenRealtimeAdapter,
        outputPlayer: FakeMacSpeechAudioOutputPlayer
    ) {
        let adapter = QwenRealtimeAdapter(
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
        let orchestration = OrchestrationKernel(runtimeCore: runtime)
        let capture = DuplexAudioCapture()
        let host = MacSpeechAudioHost(
            authorizationProvider: DuplexAuthorizationProvider(),
            capture: capture,
            deviceMonitor: DuplexDeviceMonitor()
        )
        let outputPlayer = FakeMacSpeechAudioOutputPlayer()
        let outputHost = MacSpeechAudioOutputHost(
            player: outputPlayer,
            deviceMonitor: FakeMacSpeechOutputDeviceMonitor(),
            configuration: MacSpeechPCMPlaybackConfiguration(
                capacity: 8,
                lowWatermark: 1,
                consumerTimeoutNanoseconds: 2_000_000_000,
                startupBufferCount: 2,
                startupBufferDurationNanoseconds: 0,
                scheduleAheadCount: 4
            )
        )
        return (
            AppController(
                orchestrationKernel: orchestration,
                speechAudioHost: host,
                speechAudioOutputHost: outputHost,
                nativeSpeechProfile: qwenProfile()
            ),
            orchestration,
            capture,
            adapter,
            outputPlayer
        )
    }

    private static func makeRuntimeStack(
        transport: FakeRealtimeWebSocketTransport
    ) -> (
        orchestration: OrchestrationKernel,
        adapter: QwenRealtimeAdapter
    ) {
        let adapter = QwenRealtimeAdapter(
            credentialReader: DuplexCredentialReader(),
            transport: transport,
            configuration: QwenRealtimeConfiguration(
                inputPacketMilliseconds: 20
            ),
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

    private static func subtitleAudioFrame(
        responseID: String,
        itemID: String,
        seed: UInt8,
        byteCount: Int = 14_400
    ) -> RealtimeWebSocketFrame {
        let encoded = Data(
            repeating: seed,
            count: byteCount
        ).base64EncodedString()
        return .text(
            #"{"type":"response.audio.delta","response_id":"\#(responseID)","item_id":"\#(itemID)","delta":"\#(encoded)"}"#
        )
    }

    private static func profile() -> NativeSpeechProviderProfile {
        qwenProfile()
    }

    private static func qwenProfile() -> NativeSpeechProviderProfile {
        NativeSpeechProviderProfile(
            profileID: "stage7_5_qwen_realtime_development_beijing",
            providerID: "Qwen",
            capability: "native_speech",
            adapterID: "qwen_realtime",
            modelID: "qwen3.5-omni-flash-realtime",
            voiceID: "Maia",
            endpoint: URL(
                string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-flash-realtime"
            )!,
            transport: "websocket",
            inputAudioFormat: .pcm16,
            outputAudioFormat: .pcm16,
            turnDetection: NativeSpeechTurnDetection(
                type: .semanticVAD,
                prefixPaddingMilliseconds: 500
            ),
            languageMetadata: "zh-CN",
            keyRef: "keychain://com.eterna.aftelle.provider.qwen/qwen_realtime_credential"
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
