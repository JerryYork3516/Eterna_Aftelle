import Foundation

private struct R3CredentialReader: ProviderCredentialReading {
    let value: String?

    func readCredential(for keyRef: String) throws -> String? {
        keyRef == "keychain://test/qwen" ? value : nil
    }
}

private actor R3ASRProvider: ASRProvider {
    private var activeGeneration: UInt64?
    private var starts = 0

    func start(request: ASRStartRequest) async throws {
        activeGeneration = request.generation
        starts += 1
    }

    func send(_ input: ASRAudioInput) async throws {
        guard activeGeneration == input.generation else {
            throw SpeechRouteError.staleGeneration
        }
    }

    func receive(generation: UInt64) async throws -> ASREvent {
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        return ASREvent(
            generation: generation,
            kind: .partialTranscript("fixture")
        )
    }

    func cancel(generation: UInt64) async throws {
        if activeGeneration == generation { activeGeneration = nil }
    }

    func close(generation: UInt64) async throws {
        if activeGeneration == generation { activeGeneration = nil }
    }

    func startCount() -> Int { starts }
}

@main
private struct QwenRealtimeResidentBrainAdapterTests {
    private static var checks = 0
    private static var cases = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        try await testHandshakeAndBootstrap()
        try await testContextScopeReplacement()
        try await testAudioAndEventMapping()
        try await testGenerationGlobalOutputAudioClock()
        try await testInterruptionAndGeneration()
        try await testToolFixture()
        try await testFailureAndCloseLifecycle()
        try await testGenericErrorDuringTransition()
        try await testRuntimeCancelInputFence(fixture: fixture)
        try await testRuntimeGenerationFence(fixture: fixture)
        try await testRuntimeOperationFence(fixture: fixture)
        try await testRuntimeAdmission(fixture: fixture)
        print("qwen_realtime_resident_brain_cases=\(cases)")
        print("qwen_realtime_resident_brain_checks=\(checks)")
        print("qwen_realtime_resident_brain_network_dependency=ZERO")
    }

    private static func testHandshakeAndBootstrap() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 1)
        try await stack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(identity: identity)
        )
        try await stack.adapter.updateRuntimeContext(
            RealtimeBrainRuntimeContextUpdate(
                identity: identity,
                kind: .bootstrap,
                contextRevision: 1,
                sections: [
                    RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "stable resident fixture"
                    ),
                    RealtimeBrainContextSection(
                        scope: .dynamicSession,
                        content: "dynamic session fixture"
                    )
                ]
            )
        )
        let ready = try await stack.adapter.receiveEvent(session: identity)
        expect(ready.kind == .sessionReady, "bootstrap emits sessionReady")
        expect(ready.sequence == 1, "sessionReady starts generation sequence")
        expect(
            ready.identity.session == identity
                && ready.identity.contextRevision == 1,
            "sessionReady carries Runtime identity and revision"
        )

        let endpoints = await stack.transport.connectedEndpoints
        expect(endpoints.count == 1, "one WebSocket connection opens")
        expect(
            endpoints[0].host
                == "fixture-workspace.cn-beijing.maas.aliyuncs.com",
            "workspace ID is placed only in the approved host"
        )
        expect(
            URLComponents(
                url: endpoints[0],
                resolvingAgainstBaseURL: false
            )?.queryItems?.first(where: { $0.name == "model" })?.value
                == QwenRealtimeResidentBrainConfiguration.supportedModelID,
            "baseline Qwen model stays in the endpoint query"
        )
        let bearerTokens = await stack.transport.bearerTokens
        expect(
            bearerTokens == ["fixture-secret"],
            "existing credential reader supplies the Bearer token"
        )

        let objects = try await sentObjects(stack.transport)
        let updates = objects.filter { $0["type"] as? String == "session.update" }
        expect(updates.count == 2, "handshake and bootstrap are acknowledged")
        let initialSession = updates[0]["session"] as? [String: Any]
        expect(
            initialSession?["modalities"] as? [String] == ["text", "audio"],
            "Qwen session requests text and audio"
        )
        expect(initialSession?["voice"] as? String == "Tina", "R3 uses temporary adapter-private voice")
        expect(
            initialSession?["input_audio_format"] as? String == "pcm"
                && initialSession?["output_audio_format"] as? String == "pcm",
            "Qwen wire uses pcm rather than public codec types"
        )
        let turnDetection = initialSession?["turn_detection"]
            as? [String: Any]
        expect(
            turnDetection?["type"] as? String == "semantic_vad",
            "Qwen3.5 semantic VAD is configured"
        )
        expect(
            turnDetection?["create_response"] as? Bool == true
                && turnDetection?["interrupt_response"] as? Bool == false,
            "Qwen may create responses but Runtime retains interruption authority"
        )
        expect(
            (initialSession?["input_audio_transcription"]
                as? [String: Any])?["model"] as? String
                == "qwen3-asr-flash-realtime",
            "input transcript fixture uses the fixed official model"
        )
        expect(
            initialSession?["tools"] == nil,
            "R3 does not pre-register a Tool registry before R5"
        )
        let bootstrapInstructions = (updates[1]["session"]
            as? [String: Any])?["instructions"] as? String
        expect(
            bootstrapInstructions?.contains("[stableResident]") == true
                && bootstrapInstructions?.contains("[dynamicSession]") == true,
            "provider-neutral context scopes flatten only at the adapter edge"
        )
        let sentTexts = await stack.transport.sentTexts()
        expect(
            sentTexts.allSatisfy {
                !$0.contains("fixture-secret")
                    && !$0.contains("fixture-workspace")
            },
            "credential and workspace never enter wire JSON"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        let closeCount = await stack.transport.closeCount()
        expect(closeCount == 1, "close is idempotent")
    }

    private static func testContextScopeReplacement() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 2)
        try await stack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(identity: identity)
        )
        try await stack.adapter.updateRuntimeContext(
            RealtimeBrainRuntimeContextUpdate(
                identity: identity,
                kind: .bootstrap,
                contextRevision: 1,
                sections: [
                    RealtimeBrainContextSection(
                        scope: .relationshipDelta,
                        content: "relationship v1"
                    ),
                    RealtimeBrainContextSection(
                        scope: .toolResultContext,
                        content: "tool context v1"
                    ),
                    RealtimeBrainContextSection(
                        scope: .memoryDelta,
                        content: "memory v1"
                    ),
                    RealtimeBrainContextSection(
                        scope: .dynamicSession,
                        content: "dynamic v1"
                    ),
                    RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "stable v1"
                    )
                ]
            )
        )
        _ = try await stack.adapter.receiveEvent(session: identity)

        try await stack.adapter.updateRuntimeContext(
            RealtimeBrainRuntimeContextUpdate(
                identity: identity,
                kind: .delta,
                contextRevision: 2,
                sections: [
                    RealtimeBrainContextSection(
                        scope: .relationshipDelta,
                        content: "relationship v2"
                    ),
                    RealtimeBrainContextSection(
                        scope: .memoryDelta,
                        content: ""
                    ),
                    RealtimeBrainContextSection(
                        scope: .dynamicSession,
                        content: "dynamic v2"
                    )
                ]
            )
        )

        let objects = try await sentObjects(stack.transport)
        let updates = objects.filter {
            $0["type"] as? String == "session.update"
        }
        guard let instructions = (updates.last?["session"]
            as? [String: Any])?["instructions"] as? String else {
            fatalError("delta context instructions expected")
        }
        expect(
            instructions == """
            [stableResident]
            stable v1

            [dynamicSession]
            dynamic v2

            [relationshipDelta]
            relationship v2

            [toolResultContext]
            tool context v1
            """,
            "delta replaces supplied scopes, retains omitted scopes, clears empty scopes, and renders deterministically"
        )
        expect(
            !instructions.contains("memory v1")
                && !instructions.contains("dynamic v1"),
            "replaced and cleared context never leaks into the full Qwen instructions"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testAudioAndEventMapping() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 7)
        try await openAndBootstrap(stack, identity: identity)

        let mono24k = pcm16([1_000, 2_000, 3_000, 4_000, 5_000, 6_000])
        try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 1,
            timestampNanoseconds: 100,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: mono24k
        ))
        let objects = try await sentObjects(stack.transport)
        guard let append = objects.last(where: {
            $0["type"] as? String == "input_audio_buffer.append"
        }), let encoded = append["audio"] as? String,
        let converted = Data(base64Encoded: encoded) else {
            fatalError("audio append fixture missing")
        }
        expect(
            pcm16Samples(converted) == [1_000, 2_500, 4_000, 5_500],
            "24 kHz mono is deterministically converted to 16 kHz mono"
        )

        let frame48k = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 2,
            timestampNanoseconds: 200,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 48_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: pcm16(Array(repeating: [300, 600, 900], count: 160)
                .flatMap { $0 })
        )
        try await stack.adapter.appendAudio(frame48k)
        try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 3,
            timestampNanoseconds: 300,
            format: frame48k.format,
            provenance: frame48k.provenance,
            bytes: pcm16(Array(repeating: [-300, 0, 300], count: 160)
                .flatMap { $0 })
        ))
        let converted48k = try await sentObjects(stack.transport)
            .filter { $0["type"] as? String == "input_audio_buffer.append" }
            .suffix(2)
            .compactMap { object -> Data? in
                guard let encoded = object["audio"] as? String else {
                    return nil
                }
                return Data(base64Encoded: encoded)
            }
        expect(
            converted48k.count == 2
                && converted48k.allSatisfy { $0.count == 320 },
            "two 48 kHz 10 ms mono packets each become 160 samples"
        )
        expect(
            pcm16Samples(converted48k[0]).allSatisfy { $0 == 600 }
                && pcm16Samples(converted48k[1]).allSatisfy { $0 == 0 },
            "48 to 16 kHz conversion is deterministic across packet boundaries"
        )

        await expectRealtimeError(.invalidAudioFrame) {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: 4,
                timestampNanoseconds: 400,
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 48_000,
                    channelCount: 2
                ),
                provenance: .acousticEchoProcessed,
                bytes: pcm16([0, 0, 0, 0, 0, 0])
            ))
        }
        await expectRealtimeError(.invalidAudioFrame) {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: 4,
                timestampNanoseconds: 400,
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 44_100,
                    channelCount: 1
                ),
                provenance: .acousticEchoProcessed,
                bytes: pcm16([0, 0, 0])
            ))
        }

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-1"}"#
        )
        let speechStarted = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(speechStarted.kind == .userSpeechStarted, "speech_started maps to user speech lifecycle")
        let turnID = speechStarted.identity.turnID
        expect(turnID != nil, "user speech owns a Runtime turn ID")

        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"user-1","text":"你","stash":"好"}"#
        )
        let partialOne = try await stack.adapter.receiveEvent(session: identity)
        expect(partialOne.kind == .userTranscriptPartial("你好"), "ASR text plus stash is a preview snapshot")
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"user-1","text":"你好","stash":"呀"}"#
        )
        let partialTwo = try await stack.adapter.receiveEvent(session: identity)
        expect(partialTwo.kind == .userTranscriptPartial("你好呀"), "ASR preview replaces rather than appends snapshots")
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"user-1","transcript":"你好呀"}"#
        )
        let userFinal = try await stack.adapter.receiveEvent(session: identity)
        expect(userFinal.kind == .userTranscriptFinal("你好呀"), "completed transcript is final")
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"user-1"}"#
        )
        let speechStopped = try await stack.adapter.receiveEvent(session: identity)
        expect(speechStopped.kind == .userSpeechStopped, "speech_stopped maps to user lifecycle")
        expect(speechStopped.identity.turnID == turnID, "user item keeps a stable Runtime turn ID")

        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"response-1","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.audio_transcript.delta","response_id":"response-1","delta":"你"}"#
        )
        let textDelta = try await stack.adapter.receiveEvent(session: identity)
        expect(textDelta.kind == .residentTextDelta("你"), "resident transcript delta maps to text delta")
        let responseID = textDelta.identity.responseID
        expect(responseID != nil && textDelta.identity.turnID == turnID, "resident output binds the active turn and response")
        await stack.transport.enqueueText(
            #"{"type":"response.audio_transcript.done","response_id":"response-1","transcript":"你好呀"}"#
        )
        let textFinal = try await stack.adapter.receiveEvent(session: identity)
        expect(textFinal.kind == .residentTextFinal("你好呀"), "transcript done maps to ephemeral text final")

        let outputPCM = Data([1, 0, 2, 0])
        await stack.transport.enqueueText(
            #"{"type":"response.audio.delta","response_id":"response-1","delta":"\#(outputPCM.base64EncodedString())"}"#
        )
        let speakingStarted = try await stack.adapter.receiveEvent(session: identity)
        expect(speakingStarted.kind == .residentSpeakingStarted, "first audio delta starts speaking lifecycle")
        let audioEvent = try await stack.adapter.receiveEvent(session: identity)
        guard case .residentAudioDelta(let audio) = audioEvent.kind else {
            fatalError("resident audio delta expected")
        }
        expect(
            audio.format.sampleRate == 24_000
                && audio.format.channelCount == 1
                && audio.format.encoding == .pcm16LittleEndian,
            "Qwen output maps to the frozen PCM contract"
        )
        expect(
            audio.sequence == 1
                && audio.timestampNanoseconds == 0
                && audio.provenance == .providerGenerated
                && audio.bytes == outputPCM,
            "audio delta carries adapter sequence, timestamp and provenance"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.audio.done","response_id":"response-1"}"#
        )
        let speakingStopped = try await stack.adapter.receiveEvent(session: identity)
        expect(speakingStopped.kind == .residentSpeakingStopped, "audio.done stops speaking only")

        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"response-1","status":"completed","output":[{"type":"message","content":[{"type":"audio","transcript":"你好呀"}]}]}}"#
        )
        let semantic = try await stack.adapter.receiveEvent(session: identity)
        expect(
            semantic.kind == .residentSemanticFinal(
                RealtimeBrainSemanticOutput(canonicalText: "你好呀")
            ),
            "only completed response.done emits canonical semantic final"
        )
        expect(semantic.identity.responseID == responseID, "semantic final keeps the response identity")
        expect(
            [speechStarted, partialOne, partialTwo, userFinal, speechStopped,
             textDelta, textFinal, speakingStarted, audioEvent,
             speakingStopped, semantic]
                .map(\.sequence) == Array(2 ... 12),
            "adapter event sequence is strictly monotonic after sessionReady"
        )

        await expectRealtimeError(.invalidAudioFrame) {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: 2,
                timestampNanoseconds: 200,
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 16_000,
                    channelCount: 1
                ),
                provenance: .providerGenerated,
                bytes: Data([0, 0])
            ))
        }
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testGenerationGlobalOutputAudioClock() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 17)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"audio-turn-1"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"audio-response-1","status":"in_progress"}}"#
        )
        let firstBytes = Data([1, 0, 2, 0])
        await stack.transport.enqueueText(
            #"{"type":"response.audio.delta","response_id":"audio-response-1","delta":"\#(firstBytes.base64EncodedString())"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        let firstAudioEvent = try await stack.adapter.receiveEvent(
            session: identity
        )
        guard case .residentAudioDelta(let firstAudio) = firstAudioEvent.kind
        else {
            fatalError("first response audio expected")
        }
        await stack.transport.enqueueText(
            #"{"type":"response.audio.done","response_id":"audio-response-1"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"audio-response-1","status":"completed","output":[{"type":"message","content":[{"type":"audio","transcript":"first"}]}]}}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        _ = try await stack.adapter.receiveEvent(session: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"audio-turn-2"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"audio-response-2","status":"in_progress"}}"#
        )
        let secondBytes = Data([3, 0])
        await stack.transport.enqueueText(
            #"{"type":"response.audio.delta","response_id":"audio-response-2","delta":"\#(secondBytes.base64EncodedString())"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        let secondAudioEvent = try await stack.adapter.receiveEvent(
            session: identity
        )
        guard case .residentAudioDelta(let secondAudio) = secondAudioEvent.kind
        else {
            fatalError("second response audio expected")
        }

        expect(
            firstAudio.sequence == 1
                && firstAudio.timestampNanoseconds == 0,
            "first response starts the generation output audio clock"
        )
        expect(
            secondAudio.sequence == 2
                && secondAudio.timestampNanoseconds == 83_333,
            "second response continues the same generation output audio clock"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testInterruptionAndGeneration() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 3)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-a"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"response-interrupt","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-b"}"#
        )
        let proposal = try await stack.adapter.receiveEvent(session: identity)
        guard case .interruptionProposed(let evidence) = proposal.kind else {
            fatalError("interruption proposal expected")
        }
        expect(evidence.reason == "qwen_input_speech_started", "speech evidence is a proposal, not Runtime authority")
        expect(evidence.identity == proposal.identity, "proposal identity is exact")
        let nextSpeech = try await stack.adapter.receiveEvent(session: identity)
        expect(nextSpeech.kind == .userSpeechStarted, "new speech lifecycle is preserved beside proposal")
        let typesBeforeInterrupt = try await sentTypes(stack.transport)
        expect(
            typesBeforeInterrupt.filter { $0 == "response.cancel" }.isEmpty,
            "Provider evidence does not autonomously send response.cancel"
        )

        let nextIdentity = sessionIdentity(
            generation: 4,
            leaseID: identity.brainLeaseID,
            routeEpoch: identity.routeEpoch
        )
        let oldReceive = Task {
            try await stack.adapter.receiveEvent(session: identity)
        }
        await waitUntilPendingReceive(stack.adapter, session: identity)
        try await stack.adapter.interrupt(RealtimeBrainInterruptCommand(
            identity: identity,
            nextGeneration: nextIdentity.generation,
            reason: .runtimeDecision
        ))
        let staleWake = try await oldReceive.value
        expect(
            staleWake.identity.session == identity,
            "an old receive is woken with old identity at the generation fence"
        )
        let cancelled = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(cancelled.kind == .cancelled(.interrupted), "Runtime interrupt produces a new-generation cancellation event")
        expect(
            cancelled.identity.session == nextIdentity
                && cancelled.sequence == 1,
            "Runtime generation transition resets only provider event sequence"
        )
        let sent = try await sentObjects(stack.transport)
        guard let cancel = sent.last(where: {
            $0["type"] as? String == "response.cancel"
        }) else { fatalError("response.cancel missing") }
        expect(cancel["response_id"] == nil, "current Qwen response.cancel has no response ID")
        expect(
            sent.contains { $0["type"] as? String == "input_audio_buffer.clear" },
            "Runtime interrupt clears uncommitted provider input"
        )

        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"user-a","transcript":"late old transcript"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.failed","item_id":"user-a","error":{"code":"late_old_asr"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"response-interrupt","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.audio.delta","response_id":"response-interrupt","delta":"AA=="}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-current"}"#
        )
        let currentSpeech = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            currentSpeech.kind == .userSpeechStarted
                && currentSpeech.sequence == 2,
            "late old item and response callbacks do not create a sequence gap"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"response-current","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.text.done","response_id":"response-current","text":"current generation"}"#
        )
        let currentText = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            currentText.kind == .residentTextFinal("current generation")
                && currentText.identity.session == nextIdentity,
            "new wire IDs remain usable after old callbacks are tombstoned"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: nextIdentity)
        )
    }

    private static func testToolFixture() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 11)
        try await openAndBootstrap(stack, identity: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"tool-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"tool-response","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"tool-response","item_id":"tool-item","call_id":"call-weather","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}"#
        )
        let toolEvent = try await stack.adapter.receiveEvent(session: identity)
        guard case .toolCall(let candidate) = toolEvent.kind else {
            fatalError("tool candidate expected")
        }
        expect(candidate.callID.rawValue == "call-weather", "provider call ID remains adapter-correlated")
        expect(candidate.toolName == "weather_lookup", "tool candidate preserves tool name")
        expect(
            String(data: candidate.arguments, encoding: .utf8)
                == #"{"city":"Hangzhou"}"#,
            "arguments.done is the complete JSON fixture"
        )
        expect(candidate.identity == toolEvent.identity, "tool candidate carries exact Runtime identity")

        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"tool-response","status":"completed","output":[{"type":"function_call","call_id":"call-weather","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}]}}"#
        )
        await stack.transport.holdResponseCreationAcknowledgements()
        let toolResultCommand = RealtimeBrainToolResultCommand(
                identity: toolEvent.identity,
                sequence: 1,
                callID: candidate.callID,
                output: #"{"temperature":25}"#,
                isError: false
        )
        let toolResultTask = Task {
            try await stack.adapter.submitToolResult(toolResultCommand)
        }
        await stack.transport.waitUntilSent(type: "response.create")
        await expectRealtimeError(.operationInFlight) {
            try await stack.adapter.cancelGeneration(
                RealtimeBrainCancelGenerationCommand(
                    identity: identity,
                    nextGeneration: identity.generation + 1,
                    reason: .runtimeDecision
                )
            )
        }
        await expectRealtimeError(.operationInFlight) {
            try await stack.adapter.interrupt(RealtimeBrainInterruptCommand(
                identity: identity,
                nextGeneration: identity.generation + 1,
                reason: .runtimeDecision
            ))
        }
        await stack.transport.releaseResponseCreationAcknowledgements()
        try await toolResultTask.value
        expect(
            true,
            "generation transition cannot discard an in-flight Tool continuation"
        )
        let sent = try await sentObjects(stack.transport)
        guard let itemCreate = sent.last(where: {
            $0["type"] as? String == "conversation.item.create"
        }), let item = itemCreate["item"] as? [String: Any] else {
            fatalError("function_call_output missing")
        }
        expect(item["type"] as? String == "function_call_output", "Runtime result maps to Qwen function output")
        expect(item["call_id"] as? String == "call-weather", "tool result stays correlated")
        expect(item["output"] as? String == #"{"temperature":25}"#, "tool output is forwarded verbatim")
        expect(
            sent.contains { $0["type"] as? String == "response.create" },
            "tool result explicitly requests provider continuation"
        )

        await stack.transport.enqueueText(
            #"{"type":"response.text.done","response_id":"response-tool-1","text":"杭州现在 25 度。"}"#
        )
        let finalText = try await stack.adapter.receiveEvent(session: identity)
        expect(finalText.kind == .residentTextFinal("杭州现在 25 度。"), "tool continuation remains normal resident output")
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"response-tool-1","status":"completed","output":[{"type":"message","content":[{"type":"text","text":"杭州现在 25 度。"}]}]}}"#
        )
        let semantic = try await stack.adapter.receiveEvent(session: identity)
        expect(
            semantic.kind == .residentSemanticFinal(
                RealtimeBrainSemanticOutput(
                    canonicalText: "杭州现在 25 度。"
                )
            ),
            "tool execution remains outside Provider while continuation can finish semantically"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testFailureAndCloseLifecycle() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 21)
        try await openAndBootstrap(stack, identity: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"failure-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"response-incomplete","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.audio.done","response_id":"response-incomplete"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"response-incomplete","status":"incomplete","output":[]}}"#
        )
        let cancelled = try await stack.adapter.receiveEvent(session: identity)
        expect(cancelled.kind == .cancelled(.interrupted), "incomplete response is terminal but never semantic final")

        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"response-error","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"response-error","status":"failed","output":[]}}"#
        )
        let error = try await stack.adapter.receiveEvent(session: identity)
        expect(error.kind == .error(.providerFailure), "failed response.done maps to recoverable response error")

        let terminalErrorReceive = Task {
            do {
                _ = try await stack.adapter.receiveEvent(session: identity)
                return false
            } catch RealtimeResidentBrainError.providerFailure {
                return true
            } catch {
                return false
            }
        }
        await stack.transport.enqueueText(
            #"{"type":"error","error":{"code":"provider_failure"}}"#
        )
        let terminalErrorWasReported = await terminalErrorReceive.value
        expect(
            terminalErrorWasReported,
            "uncorrelated Qwen error is a terminal session failure"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )

        let closeWakeIdentity = sessionIdentity(generation: 1)
        try await stack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(identity: closeWakeIdentity)
        )
        try await stack.adapter.updateRuntimeContext(
            RealtimeBrainRuntimeContextUpdate(
                identity: closeWakeIdentity,
                kind: .bootstrap,
                contextRevision: 1,
                sections: [RealtimeBrainContextSection(
                    scope: .stableResident,
                    content: "close wake"
                )]
            )
        )
        _ = try await stack.adapter.receiveEvent(session: closeWakeIdentity)
        let heldReceive = Task {
            do {
                _ = try await stack.adapter.receiveEvent(
                    session: closeWakeIdentity
                )
                return false
            } catch RealtimeResidentBrainError.cancelled {
                return true
            } catch {
                return false
            }
        }
        await waitUntilPendingReceive(
            stack.adapter,
            session: closeWakeIdentity
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: closeWakeIdentity)
        )
        let receiveWasCancelled = await heldReceive.value
        let closeCount = await stack.transport.closeCount()
        expect(receiveWasCancelled, "close wakes a passive receive without waiting on it")
        expect(closeCount == 2, "terminal recovery and explicit close terminate both sockets")

        let reopened = sessionIdentity(generation: 1)
        try await stack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(identity: reopened)
        )
        try await stack.adapter.updateRuntimeContext(
            RealtimeBrainRuntimeContextUpdate(
                identity: reopened,
                kind: .bootstrap,
                contextRevision: 1,
                sections: [RealtimeBrainContextSection(
                    scope: .stableResident,
                    content: "reopened"
                )]
            )
        )
        let ready = try await stack.adapter.receiveEvent(session: reopened)
        expect(ready.kind == .sessionReady && ready.sequence == 1, "reopen starts a clean provider session")
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"asr-failure"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: reopened)
        let transcriptFailure = Task {
            do {
                _ = try await stack.adapter.receiveEvent(session: reopened)
                return false
            } catch RealtimeResidentBrainError.providerFailure {
                return true
            } catch {
                return false
            }
        }
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.failed","item_id":"asr-failure","error":{"code":"asr_failed"}}"#
        )
        let transcriptFailureWasTerminal = await transcriptFailure.value
        expect(
            transcriptFailureWasTerminal,
            "unscoped ASR failure is terminal instead of misbound to an assistant response"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: reopened)
        )
    }

    private static func testGenericErrorDuringTransition() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 31)
        try await openAndBootstrap(stack, identity: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"cancel-error-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"cancel-error-response","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.text.delta","response_id":"cancel-error-response","delta":"x"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.failNextResponseCancelWithGenericError()
        await expectRealtimeError(.providerFailure) {
            try await stack.adapter.interrupt(RealtimeBrainInterruptCommand(
                identity: identity,
                nextGeneration: identity.generation + 1,
                reason: .runtimeDecision
            ))
        }
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        let transitionCloseCount = await stack.transport.closeCount()
        expect(
            transitionCloseCount == 1,
            "generic cancel error fails immediately and remains definitively closeable"
        )
    }

    private static func testRuntimeOperationFence(fixture: Data) async throws {
        cases += 1
        let stack = try makeStack()
        let reader = try credentialReader()
        let router = ProviderRouter(
            credentialReader: reader,
            realtimeResidentBrainProvider: stack.adapter
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "operation fixture resident loads")
        let identity = try realtimeIdentity(
            await runtime.openRealtimeResidentBrainSession()
        )
        expectRealtimeSuccess(
            await runtime.updateRealtimeResidentBrainContext(
                RealtimeBrainRuntimeContextUpdate(
                    identity: identity,
                    kind: .bootstrap,
                    contextRevision: 1,
                    sections: [RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "operation fence"
                    )]
                )
            ),
            "Runtime operation fixture bootstraps"
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"runtime-tool-user"}"#
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"runtime-tool-response","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"runtime-tool-response","item_id":"runtime-tool-item","call_id":"runtime-tool-call","name":"fixture_tool","arguments":"{}"}"#
        )
        let toolDisposition = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        guard case .accepted(let toolEvent) = toolDisposition,
              case .toolCall(let candidate) = toolEvent.kind else {
            fatalError("Runtime tool candidate expected")
        }
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"runtime-tool-response","status":"completed","output":[{"type":"function_call","call_id":"runtime-tool-call","name":"fixture_tool","arguments":"{}"}]}}"#
        )
        await stack.transport.holdResponseCreationAcknowledgements()
        let command = RealtimeBrainToolResultCommand(
            identity: toolEvent.identity,
            sequence: 1,
            callID: candidate.callID,
            output: "fixture result",
            isError: false
        )
        let toolTask = Task {
            await runtime.submitRealtimeResidentBrainToolResult(command)
        }
        await stack.transport.waitUntilSent(type: "response.create")
        let cancelTask = Task {
            await runtime.cancelRealtimeResidentBrainGeneration(
                identity: identity,
                reason: .runtimeDecision
            )
        }
        for _ in 0 ..< 10_000 {
            if runtime.activeBrainLeaseForTesting()?.state == .settling {
                break
            }
            await Task.yield()
        }
        expect(
            runtime.activeBrainLeaseForTesting()?.state == .settling,
            "Runtime settlement is in flight before the Tool ACK is released"
        )
        await stack.transport.releaseResponseCreationAcknowledgements()
        expectRealtimeFailure(
            await toolTask.value,
            equals: .cancelled,
            "Runtime invalidates the old Tool result without losing its continuation"
        )
        expectRealtimeFailure(
            await cancelTask.value,
            equals: .operationInFlight,
            "generation transition fails closed while a Provider mutation is in flight"
        )
        let closeCount = await stack.transport.closeCount()
        expect(
            closeCount == 1 && runtime.activeBrainLeaseForTesting() == nil,
            "Runtime closes definitively before releasing the in-flight Brain lease"
        )
        let reopened = try realtimeIdentity(
            await runtime.openRealtimeResidentBrainSession()
        )
        expectRealtimeSuccess(
            await runtime.closeRealtimeResidentBrainSession(identity: reopened),
            "a new Brain can open only after definitive recovery"
        )
    }

    private static func testRuntimeGenerationFence(fixture: Data) async throws {
        cases += 1
        let stack = try makeStack()
        let router = ProviderRouter(
            credentialReader: try credentialReader(),
            realtimeResidentBrainProvider: stack.adapter
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "generation fixture resident loads")
        let identity = try realtimeIdentity(
            await runtime.openRealtimeResidentBrainSession()
        )
        expectRealtimeSuccess(
            await runtime.updateRealtimeResidentBrainContext(
                RealtimeBrainRuntimeContextUpdate(
                    identity: identity,
                    kind: .bootstrap,
                    contextRevision: 1,
                    sections: [RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "generation fence"
                    )]
                )
            ),
            "Runtime generation fixture bootstraps"
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"runtime-old-user"}"#
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"runtime-old-response","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.text.delta","response_id":"runtime-old-response","delta":"old"}"#
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        let oldReceive = Task {
            try await runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            )
        }
        await waitUntilPendingReceive(stack.adapter, session: identity)
        let nextIdentity = try realtimeIdentity(
            await runtime.interruptRealtimeResidentBrain(
                identity: identity,
                reason: .runtimeDecision
            )
        )
        let staleDisposition = try await oldReceive.value
        expect(
            staleDisposition == .rejectedStale,
            "Runtime rejects the explicitly woken old-generation receive"
        )
        expectAccepted(
            try await runtime.receiveRealtimeResidentBrainEvent(
                session: nextIdentity
            ),
            kind: .cancelled(.interrupted),
            "new generation retains its cancellation event"
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"runtime-old-user","transcript":"late"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.failed","item_id":"runtime-old-user","error":{"code":"late_old_asr"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"runtime-old-response","status":"in_progress"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.audio.delta","response_id":"runtime-old-response","delta":"AAA="}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"runtime-new-user"}"#
        )
        let currentDisposition = try await runtime
            .receiveRealtimeResidentBrainEvent(session: nextIdentity)
        guard case .accepted(let currentEvent) = currentDisposition else {
            fatalError("current generation speech expected")
        }
        expect(
            currentEvent.kind == .userSpeechStarted
                && currentEvent.sequence == 2
                && currentEvent.identity.session == nextIdentity,
            "late wire callbacks cannot be relabeled into the new generation"
        )
        expectRealtimeSuccess(
            await runtime.closeRealtimeResidentBrainSession(
                identity: nextIdentity
            ),
            "Runtime generation fixture closes"
        )
    }

    private static func testRuntimeCancelInputFence(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try makeStack()
        let router = ProviderRouter(
            credentialReader: try credentialReader(),
            realtimeResidentBrainProvider: stack.adapter
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "cancel fixture resident loads")
        let identity = try realtimeIdentity(
            await runtime.openRealtimeResidentBrainSession()
        )
        expectRealtimeSuccess(
            await runtime.updateRealtimeResidentBrainContext(
                RealtimeBrainRuntimeContextUpdate(
                    identity: identity,
                    kind: .bootstrap,
                    contextRevision: 1,
                    sections: [RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "cancel input fence"
                    )]
                )
            ),
            "cancel fixture bootstraps"
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        expectRealtimeSuccess(
            await runtime.appendRealtimeResidentBrainAudio(
                RealtimeBrainAudioFrame(
                    identity: identity,
                    sequence: 1,
                    timestampNanoseconds: 1,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: 16_000,
                        channelCount: 1
                    ),
                    provenance: .acousticEchoProcessed,
                    bytes: pcm16([100, -100])
                )
            ),
            "uncommitted old-generation audio reaches the Provider"
        )

        await stack.transport.holdInputClearAcknowledgements()
        let cancelTask = Task {
            await runtime.cancelRealtimeResidentBrainGeneration(
                identity: identity,
                reason: .runtimeDecision
            )
        }
        await stack.transport.waitUntilSent(type: "input_audio_buffer.clear")
        expect(
            runtime.activeBrainLeaseForTesting()?.generation
                == .realtimeResidentBrain(identity.generation),
            "Runtime generation does not advance before Provider input clear ACK"
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"unseen-old-user"}"#
        )
        await stack.transport.releaseInputClearAcknowledgements()
        let nextIdentity = try realtimeIdentity(await cancelTask.value)
        expect(
            nextIdentity.generation == identity.generation + 1,
            "cancel advances generation only after the input fence"
        )
        expectAccepted(
            try await runtime.receiveRealtimeResidentBrainEvent(
                session: nextIdentity
            ),
            kind: .cancelled(.runtimeDecision),
            "new generation receives the Runtime cancellation event"
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"current-user"}"#
        )
        let current = try await runtime.receiveRealtimeResidentBrainEvent(
            session: nextIdentity
        )
        guard case .accepted(let currentEvent) = current else {
            fatalError("current speech expected after cancel input fence")
        }
        expect(
            currentEvent.kind == .userSpeechStarted
                && currentEvent.sequence == 2,
            "unseen old input cannot cross the acknowledged generation fence"
        )
        expectRealtimeSuccess(
            await runtime.closeRealtimeResidentBrainSession(
                identity: nextIdentity
            ),
            "cancel input fence fixture closes"
        )
    }

    private static func testRuntimeAdmission(fixture: Data) async throws {
        cases += 1
        let stack = try makeStack()
        let asr = R3ASRProvider()
        let reader = try credentialReader()
        let router = ProviderRouter(
            credentialReader: reader,
            asrProvider: asr,
            realtimeResidentBrainProvider: stack.adapter
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "fixture resident loads")
        let identity = try realtimeIdentity(
            await runtime.openRealtimeResidentBrainSession()
        )
        let firstConnectCount = await stack.transport.connectCount()
        expect(firstConnectCount == 1, "Runtime admission precedes real adapter open")
        expectRealtimeSuccess(
            await runtime.updateRealtimeResidentBrainContext(
                RealtimeBrainRuntimeContextUpdate(
                    identity: identity,
                    kind: .bootstrap,
                    contextRevision: 1,
                    sections: [RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "runtime fixture"
                    )]
                )
            ),
            "Runtime forwards bootstrap to Qwen adapter"
        )
        expectAccepted(
            try await runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            kind: .sessionReady,
            "Runtime accepts adapter sessionReady"
        )
        expectRealtimeFailure(
            await runtime.openRealtimeResidentBrainSession(),
            equals: .unavailable,
            "second Realtime Brain is rejected"
        )
        let secondConnectCount = await stack.transport.connectCount()
        expect(secondConnectCount == 1, "second Brain rejects before transport connect")
        expectSpeechFailure(
            await runtime.startSpeechRouteASR(),
            equals: .unavailable,
            "Cascaded Brain cannot start beside Realtime Brain"
        )
        let blockedASRStartCount = await asr.startCount()
        expect(blockedASRStartCount == 0, "Cascaded Provider is not called while Realtime owns lease")
        expectRealtimeSuccess(
            await runtime.closeRealtimeResidentBrainSession(
                identity: identity
            ),
            "Runtime definitive close releases Realtime lease"
        )
        let cascadedGeneration = try speechGeneration(
            await runtime.startSpeechRouteASR()
        )
        let releasedASRStartCount = await asr.startCount()
        expect(releasedASRStartCount == 1, "Cascaded Brain starts only after Realtime close")
        _ = await runtime.cancelSpeechRoute(
            generation: cascadedGeneration
        )
    }

    private static func makeStack() throws -> (
        adapter: QwenRealtimeResidentBrainAdapter,
        transport: R3FakeRealtimeWebSocketTransport
    ) {
        let transport = R3FakeRealtimeWebSocketTransport()
        return (
            QwenRealtimeResidentBrainAdapter(
                credentialReader: try credentialReader(),
                transport: transport,
                configuration: QwenRealtimeResidentBrainConfiguration(
                    endpoint: URL(
                        string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-plus-realtime"
                    )!,
                    keyRef: "keychain://test/qwen",
                    acknowledgementTimeout: .seconds(1)
                )
            ),
            transport
        )
    }

    private static func credentialReader() throws -> R3CredentialReader {
        R3CredentialReader(value: try QwenRealtimeCredential(
            workspaceID: "fixture-workspace",
            secret: "fixture-secret"
        ).storedValue())
    }

    private static func openAndBootstrap(
        _ stack: (
            adapter: QwenRealtimeResidentBrainAdapter,
            transport: R3FakeRealtimeWebSocketTransport
        ),
        identity: RealtimeBrainSessionIdentity
    ) async throws {
        try await stack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(identity: identity)
        )
        try await stack.adapter.updateRuntimeContext(
            RealtimeBrainRuntimeContextUpdate(
                identity: identity,
                kind: .bootstrap,
                contextRevision: 1,
                sections: [RealtimeBrainContextSection(
                    scope: .stableResident,
                    content: "fixture context"
                )]
            )
        )
        let ready = try await stack.adapter.receiveEvent(session: identity)
        expect(ready.kind == .sessionReady, "fixture session becomes ready")
    }

    private static func sessionIdentity(
        generation: UInt64,
        leaseID: UUID = UUID(),
        routeEpoch: UInt64 = 1
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: "resident-r3",
            runtimeSessionID: "session-r3",
            brainLeaseID: leaseID,
            routeEpoch: routeEpoch,
            generation: generation
        )
    }

    private static func sentObjects(
        _ transport: R3FakeRealtimeWebSocketTransport
    ) async throws -> [[String: Any]] {
        try await transport.sentTexts().map { text in
            guard let object = try JSONSerialization.jsonObject(
                with: Data(text.utf8)
            ) as? [String: Any] else {
                throw RealtimeResidentBrainError.invalidEvent
            }
            return object
        }
    }

    private static func waitUntilPendingReceive(
        _ adapter: QwenRealtimeResidentBrainAdapter,
        session: RealtimeBrainSessionIdentity
    ) async {
        for _ in 0 ..< 10_000 {
            if await adapter.hasPendingEventWaiterForTesting(
                session: session
            ) {
                return
            }
            await Task.yield()
        }
        fatalError("event receive did not enter the Adapter waiter")
    }

    private static func sentTypes(
        _ transport: R3FakeRealtimeWebSocketTransport
    ) async throws -> [String] {
        try await sentObjects(transport).compactMap { $0["type"] as? String }
    }

    private static func pcm16(_ samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let bits = UInt16(bitPattern: sample)
            data.append(UInt8(truncatingIfNeeded: bits))
            data.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return data
    }

    private static func pcm16Samples(_ data: Data) -> [Int16] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 2).map { offset in
            Int16(bitPattern: UInt16(bytes[offset])
                | UInt16(bytes[offset + 1]) << 8)
        }
    }

    private static func realtimeIdentity(
        _ result: Result<
            RealtimeBrainSessionIdentity,
            RealtimeResidentBrainError
        >
    ) throws -> RealtimeBrainSessionIdentity {
        switch result {
        case .success(let identity): return identity
        case .failure(let error): throw error
        }
    }

    private static func speechGeneration(
        _ result: Result<UInt64, SpeechRouteError>
    ) throws -> UInt64 {
        switch result {
        case .success(let generation): return generation
        case .failure(let error): throw error
        }
    }

    private static func expectAccepted(
        _ disposition: RealtimeBrainEventDisposition,
        kind: RealtimeResidentBrainEventKind,
        _ message: String
    ) {
        if case .accepted(let event) = disposition,
           event.kind == kind {
            expect(true, message)
        } else {
            expect(false, message)
        }
    }

    private static func expectRealtimeSuccess(
        _ result: Result<Void, RealtimeResidentBrainError>,
        _ message: String
    ) {
        if case .success = result {
            expect(true, message)
        } else {
            expect(false, message)
        }
    }

    private static func expectRealtimeFailure<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        equals expected: RealtimeResidentBrainError,
        _ message: String
    ) {
        if case .failure(let error) = result, error == expected {
            expect(true, message)
        } else {
            expect(false, message)
        }
    }

    private static func expectSpeechFailure(
        _ result: Result<UInt64, SpeechRouteError>,
        equals expected: SpeechRouteError,
        _ message: String
    ) {
        if case .failure(let error) = result, error == expected {
            expect(true, message)
        } else {
            expect(false, message)
        }
    }

    private static func expectRealtimeError(
        _ expected: RealtimeResidentBrainError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            expect(false, "expected \(expected)")
        } catch let error as RealtimeResidentBrainError {
            expect(error == expected, "expected \(expected)")
        } catch {
            expect(false, "unexpected error \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("check failed: \(message)") }
    }
}
