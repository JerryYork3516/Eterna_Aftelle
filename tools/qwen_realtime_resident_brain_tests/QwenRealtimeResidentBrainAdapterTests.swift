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
        try await testUnsafeTurnDetectionAcknowledgementFailsClosed()
        try await testInvalidToolAdvertisementsFailClosed()
        try await testContextScopeReplacement()
        try await testAudioAndEventMapping()
        try await testResidentTextWireSourceCanonicalization()
        try await testGenerationGlobalOutputAudioClock()
        try await testInterruptionAndGeneration()
        try await testUnauthorizedResponseFailsClosed()
        try await testOverlappingResponseFailsClosed()
        try await testGenerationReconnectRejectsUnseenOldResponse()
        try await testCloseWinsGenerationReconnect()
        try await testFastToolResultWaitsForResponseDone()
        try await testMultipleToolResultsCreateOneContinuation()
        try await testFailedToolResponseCannotContinue()
        try await testToolFixture()
        try await testFailureAndCloseLifecycle()
        try await testPendingEventBufferFailsClosed()
        try await testGenericErrorDuringTransition()
        try await testRuntimeCancelInputFence(fixture: fixture)
        try await testRuntimeGenerationFence(fixture: fixture)
        try await testRuntimeAcousticActivityAdmissionFence(fixture: fixture)
        try await testRuntimeAdmission(fixture: fixture)
        print("qwen_realtime_resident_brain_cases=\(cases)")
        print("qwen_realtime_resident_brain_checks=\(checks)")
        print("qwen_realtime_resident_brain_network_dependency=ZERO")
    }

    private static func testHandshakeAndBootstrap() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 1)
        let tools = runtimeToolAdvertisements()
        try await stack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(
                identity: identity,
                tools: tools
            )
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
        expect(
            initialSession?["voice"] as? String == "R6FixtureVoice",
            "Qwen resolves the neutral binding to its private default voice"
        )
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
            turnDetection?["create_response"] as? Bool == false
                && turnDetection?["interrupt_response"] as? Bool == false,
            "Qwen VAD cannot create or interrupt responses without Runtime authority"
        )
        expect(
            (initialSession?["input_audio_transcription"]
                as? [String: Any])?["model"] as? String
                == "qwen3-asr-flash-realtime",
            "input transcript fixture uses the fixed official model"
        )
        guard let wireTools = initialSession?["tools"]
                as? [[String: Any]],
              let wireTool = wireTools.first,
              let function = wireTool["function"] as? [String: Any],
              let parameters = function["parameters"] as? [String: Any],
              let properties = parameters["properties"] as? [String: Any],
              let city = properties["city"] as? [String: Any] else {
            fatalError("Runtime Tool definitions must map to Qwen wire tools")
        }
        expect(
            wireTools.count == 1,
            "Qwen advertises the Runtime Tool snapshot"
        )
        expect(
            Set(wireTool.keys) == Set(["type", "function"])
                && wireTool["type"] as? String == "function",
            "Qwen wire keeps Provider function framing private"
        )
        expect(
            Set(function.keys) == Set(["name", "description", "parameters"])
                && function["name"] as? String == "weather_lookup"
                && function["description"] as? String
                    == "Look up weather by city.",
            "Qwen wire exposes only the Runtime Tool advertisement fields"
        )
        expect(
            parameters["type"] as? String == "object"
                && parameters["required"] as? [String] == ["city"]
                && parameters["additionalProperties"] as? Bool == false
                && city["type"] as? String == "string",
            "Runtime parameters JSON maps to an object rather than encoded data"
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
                    && !$0.contains("requires_permission")
                    && !$0.contains("executionTimeout")
            },
            "credentials and Runtime execution policy never enter wire JSON"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        let closeCount = await stack.transport.closeCount()
        expect(closeCount == 1, "close is idempotent")

        let reopenedIdentity = sessionIdentity(generation: 2)
        try await openAndBootstrap(stack, identity: reopenedIdentity)
        let advertisedSessions = try await sentObjects(stack.transport)
            .compactMap { $0["session"] as? [String: Any] }
            .filter { $0["tools"] != nil }
        expect(
            (advertisedSessions.last?["tools"] as? [[String: Any]])?.isEmpty
                == true,
            "reopened session replaces the prior Tool advertisement snapshot"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: reopenedIdentity)
        )
    }

    private static func testInvalidToolAdvertisementsFailClosed()
        async throws {
        cases += 1
        let invalidSchemas: [(Data, String)] = [
            (Data("{".utf8), "malformed"),
            (Data("[]".utf8), "non-object")
        ]
        for (offset, fixture) in invalidSchemas.enumerated() {
            let stack = try makeStack()
            let identity = sessionIdentity(
                generation: UInt64(30 + offset)
            )
            await expectRealtimeError(.invalidEvent) {
                try await stack.adapter.openSession(
                    RealtimeBrainOpenSessionCommand(
                        identity: identity,
                        tools: [RealtimeBrainToolAdvertisement(
                            name: "invalid_tool",
                            description: "Invalid \(fixture.1) schema.",
                            parametersJSON: fixture.0
                        )]
                    )
                )
            }
            let closeCount = await stack.transport.closeCount()
            expect(
                closeCount == 1,
                "\(fixture.1) Tool schema closes the failed open"
            )
            let types = try await sentTypes(stack.transport)
            expect(
                types.allSatisfy { $0 != "session.update" },
                "\(fixture.1) Tool schema never reaches Qwen wire"
            )
        }
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

        let frame24k = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 1,
            timestampNanoseconds: 100,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: pcm16(
                Array(
                    repeating: [1_000, 2_000, 3_000, 4_000, 5_000, 6_000],
                    count: 80
                ).flatMap { $0 }
            )
        )
        for index in 0 ..< 4 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 1),
                timestampNanoseconds: UInt64((index + 1) * 100),
                format: frame24k.format,
                provenance: frame24k.provenance,
                bytes: frame24k.bytes
            ))
        }
        let objectsBeforeBatch = try await sentObjects(stack.transport)
        expect(
            objectsBeforeBatch.allSatisfy {
                $0["type"] as? String != "input_audio_buffer.append"
            },
            "Qwen input waits for one 100 ms PCM batch"
        )
        try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 5,
            timestampNanoseconds: 500,
            format: frame24k.format,
            provenance: frame24k.provenance,
            bytes: frame24k.bytes
        ))
        let objects = try await sentObjects(stack.transport)
        guard let append = objects.last(where: {
            $0["type"] as? String == "input_audio_buffer.append"
        }), let encoded = append["audio"] as? String,
        let converted = Data(base64Encoded: encoded) else {
            fatalError("audio append fixture missing")
        }
        let converted24kSamples = pcm16Samples(converted)
        expect(
            converted.count == 3_200
                && converted24kSamples.count == 1_600
                && Array(converted24kSamples.prefix(4))
                    == [1_000, 2_500, 4_000, 5_500],
            "five 20 ms frames become one deterministic 100 ms 16 kHz batch"
        )

        let positive48k = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 6,
            timestampNanoseconds: 600,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 48_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: pcm16(Array(repeating: [300, 600, 900], count: 160)
                .flatMap { $0 })
        )
        let quiet48k = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 11,
            timestampNanoseconds: 1_100,
            format: positive48k.format,
            provenance: positive48k.provenance,
            bytes: pcm16(Array(repeating: [-300, 0, 300], count: 160)
                .flatMap { $0 })
        )
        for index in 0 ..< 5 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 6),
                timestampNanoseconds: UInt64((index + 6) * 100),
                format: positive48k.format,
                provenance: positive48k.provenance,
                bytes: positive48k.bytes
            ))
        }
        for index in 0 ..< 5 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 11),
                timestampNanoseconds: UInt64((index + 11) * 100),
                format: quiet48k.format,
                provenance: quiet48k.provenance,
                bytes: quiet48k.bytes
            ))
        }
        let allAppends = try await sentObjects(stack.transport)
            .filter { $0["type"] as? String == "input_audio_buffer.append" }
        expect(
            allAppends.count == 2,
            "ten 48 kHz 10 ms frames produce one additional Qwen batch"
        )
        guard let encoded48k = allAppends.last?["audio"] as? String,
              let converted48k = Data(base64Encoded: encoded48k) else {
            fatalError("48 kHz audio batch fixture missing")
        }
        let converted48kSamples = pcm16Samples(converted48k)
        expect(
            converted48k.count == 3_200
                && converted48kSamples.prefix(800)
                    .allSatisfy { $0 == 600 }
                && converted48kSamples.suffix(800)
                    .allSatisfy { $0 == 0 },
            "48 to 16 kHz conversion is deterministic across packet boundaries"
        )

        await expectRealtimeError(.invalidAudioFrame) {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: 16,
                timestampNanoseconds: 1_600,
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
                sequence: 16,
                timestampNanoseconds: 1_600,
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
        let responseCreatesBeforeAuthorization = try await sentTypes(
            stack.transport
        ).filter { $0 == "response.create" }
        expect(
            responseCreatesBeforeAuthorization.isEmpty,
            "speech lifecycle and transcript events cannot create a response"
        )

        try await authorizeResponse(
            stack,
            from: userFinal,
            responseID: "response-1"
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
        let firstSpeech = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: firstSpeech,
            responseID: "audio-response-1"
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
        let secondSpeech = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: secondSpeech,
            responseID: "audio-response-2"
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

    private static func testResidentTextWireSourceCanonicalization() async throws {
        cases += 5
        let expected: [RealtimeResidentBrainEventKind] = [
            .residentTextDelta("你好"),
            .residentTextFinal("你好"),
            .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "你好"
            ))
        ]

        let textOnly = try await residentTextEvents(
            generation: 18,
            responseID: "text-only-response",
            wireEvents: [
                #"{"type":"response.text.delta","response_id":"text-only-response","delta":"你好"}"#,
                #"{"type":"response.text.done","response_id":"text-only-response","text":"你好"}"#
            ],
            responseDoneContent: #"{"type":"text","text":"你好"}"#
        )
        expect(textOnly == expected, "text-only output emits one resident text stream")

        let audioTranscriptOnly = try await residentTextEvents(
            generation: 19,
            responseID: "audio-transcript-only-response",
            wireEvents: [
                #"{"type":"response.audio_transcript.delta","response_id":"audio-transcript-only-response","delta":"你好"}"#,
                #"{"type":"response.audio_transcript.done","response_id":"audio-transcript-only-response","transcript":"你好"}"#
            ],
            responseDoneContent: #"{"type":"audio","transcript":"你好"}"#
        )
        expect(
            audioTranscriptOnly == expected,
            "audio-transcript-only output emits one resident text stream"
        )

        let mirroredStreams = try await residentTextEvents(
            generation: 20,
            responseID: "mirrored-response",
            wireEvents: [
                #"{"type":"response.text.delta","response_id":"mirrored-response","delta":"你好"}"#,
                #"{"type":"response.audio_transcript.delta","response_id":"mirrored-response","delta":"你好"}"#,
                #"{"type":"response.text.done","response_id":"mirrored-response","text":"你好"}"#,
                #"{"type":"response.audio_transcript.done","response_id":"mirrored-response","transcript":"你好"}"#
            ],
            responseDoneContent: #"{"type":"audio","transcript":"你好"}"#
        )
        expect(
            mirroredStreams == expected,
            "mirrored text and audio transcript output emits one resident text stream"
        )

        let audioFirstMirroredStreams = try await residentTextEvents(
            generation: 21,
            responseID: "audio-first-mirrored-response",
            wireEvents: [
                #"{"type":"response.audio_transcript.delta","response_id":"audio-first-mirrored-response","delta":"你好"}"#,
                #"{"type":"response.text.delta","response_id":"audio-first-mirrored-response","delta":"你好"}"#,
                #"{"type":"response.audio_transcript.done","response_id":"audio-first-mirrored-response","transcript":"你好"}"#,
                #"{"type":"response.text.done","response_id":"audio-first-mirrored-response","text":"你好"}"#
            ],
            responseDoneContent: #"{"type":"audio","transcript":"你好"}"#
        )
        expect(
            audioFirstMirroredStreams == expected,
            "audio-first mirrored streams still emit one resident text stream"
        )

        let whitespaceBeforeAudio = try await residentTextEvents(
            generation: 22,
            responseID: "whitespace-before-audio-response",
            wireEvents: [
                #"{"type":"response.text.delta","response_id":"whitespace-before-audio-response","delta":"   "}"#,
                #"{"type":"response.audio_transcript.delta","response_id":"whitespace-before-audio-response","delta":"你好"}"#,
                #"{"type":"response.text.done","response_id":"whitespace-before-audio-response","text":"你好"}"#,
                #"{"type":"response.audio_transcript.done","response_id":"whitespace-before-audio-response","transcript":"你好"}"#
            ],
            responseDoneContent: #"{"type":"audio","transcript":"你好"}"#
        )
        expect(
            whitespaceBeforeAudio == expected,
            "whitespace-only first delta cannot lock out a valid text source"
        )
    }

    private static func testInterruptionAndGeneration() async throws {
        cases += 1
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let stack = try makeStack(diagnosticBuffer: diagnostics)
        let identity = sessionIdentity(generation: 3)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-a"}"#
        )
        let initialSpeech = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: initialSpeech,
            responseID: "response-interrupt"
        )
        let overlapAudioFrame = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 1,
            timestampNanoseconds: 100,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: pcm16(Array(repeating: [600, 600, 600], count: 160)
                .flatMap { $0 })
        )
        for index in 0 ..< 5 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 1),
                timestampNanoseconds: UInt64((index + 1) * 100),
                format: overlapAudioFrame.format,
                provenance: overlapAudioFrame.provenance,
                bytes: overlapAudioFrame.bytes
            ))
        }
        let overlapAppends = try await sentObjects(stack.transport)
            .filter { $0["type"] as? String == "input_audio_buffer.append" }
        guard overlapAppends.count == 1,
              let overlapEncoded = overlapAppends[0]["audio"] as? String,
              let overlapBytes = Data(base64Encoded: overlapEncoded) else {
            fatalError("active-response audio batch missing")
        }
        expect(
            overlapBytes.count == 3_200,
            "five overlap frames form exactly one 100 ms Provider batch"
        )
        let batchDiagnostics = diagnostics.drain().events
        expect(
            batchDiagnostics.contains {
                $0.category == "qwen_turn_detection_requested"
                    && $0.disposition?.contains("type=semantic_vad") == true
                    && $0.disposition?.contains("interrupt_response=false")
                        == true
            },
            "diagnostics expose the requested provider-neutral VAD policy"
        )
        expect(
            batchDiagnostics.contains {
                $0.category == "qwen_turn_detection_acknowledged"
                    && $0.disposition?.contains("type=semantic_vad") == true
                    && $0.disposition?.contains("silence_ms=800") == true
            },
            "diagnostics expose the Provider-acknowledged VAD policy"
        )
        guard let batchDiagnostic = batchDiagnostics.last(where: {
            $0.category == "qwen_active_response_input_audio_batch"
        }) else {
            fatalError("active-response audio diagnostic missing")
        }
        expect(
            batchDiagnostic.byteCount == 3_200
                && batchDiagnostic.disposition == "transport_enqueued"
                && batchDiagnostic.turnGeneration == identity.generation
                && (batchDiagnostic.pcmPeak ?? 0) > 0
                && (batchDiagnostic.pcmRMS ?? 0) > 0,
            "active-response diagnostic proves audible PCM enters transport"
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-b"}"#
        )
        let proposal = try await stack.adapter.receiveEvent(session: identity)
        guard case .interruptionProposed(let evidence) = proposal.kind else {
            fatalError("interruption proposal expected")
        }
        expect(
            evidence.reason
                == "user_speech_started_during_resident_response",
            "speech evidence is provider-neutral and not Runtime authority"
        )
        expect(evidence.identity == proposal.identity, "proposal identity is exact")
        let nextSpeech = try await stack.adapter.receiveEvent(session: identity)
        expect(nextSpeech.kind == .userSpeechStarted, "new speech lifecycle is preserved beside proposal")
        let speechDiagnostics = diagnostics.drain().events
        expect(
            speechDiagnostics.contains {
                $0.category == "qwen_speech_started_received"
                    && $0.disposition == "active_response"
                    && $0.turnGeneration == identity.generation
            },
            "Provider speech-start is attributed to the active response"
        )
        let typesBeforeInterrupt = try await sentTypes(stack.transport)
        expect(
            typesBeforeInterrupt.filter { $0 == "response.cancel" }.isEmpty,
            "Provider evidence does not autonomously send response.cancel"
        )
        expect(
            typesBeforeInterrupt.filter { $0 == "response.create" }.count == 1,
            "interruption proposal cannot create an overlapping response"
        )

        let oldAudioFrame = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 6,
            timestampNanoseconds: 600,
            format: overlapAudioFrame.format,
            provenance: .acousticEchoProcessed,
            bytes: pcm16(Array(repeating: [300, 300, 300], count: 160)
                .flatMap { $0 })
        )
        for index in 0 ..< 4 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 6),
                timestampNanoseconds: UInt64((index + 6) * 100),
                format: oldAudioFrame.format,
                provenance: oldAudioFrame.provenance,
                bytes: oldAudioFrame.bytes
            ))
        }
        let typesWithPartialOldAudio = try await sentTypes(stack.transport)
        expect(
            typesWithPartialOldAudio.filter {
                $0 == "input_audio_buffer.append"
            }.count == 1,
            "partial old-generation audio remains local until a full batch"
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
        let connectionCountBeforeInterrupt = await stack.transport.connectCount()
        let closeCountBeforeInterrupt = await stack.transport.closeCount()
        try await stack.adapter.interrupt(RealtimeBrainInterruptCommand(
            identity: identity,
            nextGeneration: nextIdentity.generation,
            reason: .runtimeDecision
        ))
        let staleWake = try await oldReceive.value
        expect(
            staleWake.identity.session == identity
                && staleWake.kind == .cancelled(.interrupted),
            "an old receive is woken only on the retired generation fence"
        )
        let connectionCountAfterInterrupt = await stack.transport.connectCount()
        let closeCountAfterInterrupt = await stack.transport.closeCount()
        expect(
            connectionCountAfterInterrupt == connectionCountBeforeInterrupt
                && closeCountAfterInterrupt == closeCountBeforeInterrupt,
            "Runtime-confirmed interruption preserves the Provider WebSocket"
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

        let newAudioFrame = RealtimeBrainAudioFrame(
            identity: nextIdentity,
            sequence: 1,
            timestampNanoseconds: 1_000,
            format: oldAudioFrame.format,
            provenance: oldAudioFrame.provenance,
            bytes: pcm16(Array(repeating: [900, 900, 900], count: 160)
                .flatMap { $0 })
        )
        for index in 0 ..< 5 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: nextIdentity,
                sequence: UInt64(index + 1),
                timestampNanoseconds: UInt64((index + 10) * 100),
                format: newAudioFrame.format,
                provenance: newAudioFrame.provenance,
                bytes: newAudioFrame.bytes
            ))
        }
        let postInterruptAppends = try await sentObjects(stack.transport)
            .filter { $0["type"] as? String == "input_audio_buffer.append" }
        guard postInterruptAppends.count == 2,
              let encodedNewAudio = postInterruptAppends[1]["audio"]
                as? String,
              let newAudio = Data(base64Encoded: encodedNewAudio) else {
            fatalError("new-generation audio batch missing")
        }
        expect(
            pcm16Samples(newAudio).allSatisfy { $0 == 900 },
            "generation transition discards every pending old PCM byte"
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
            #"{"type":"response.done","response":{"id":"response-interrupt","status":"completed","output":[{"type":"message","content":[{"type":"text","text":"late old final"}]}]}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-current"}"#
        )
        let currentSpeech = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            currentSpeech.kind == .userSpeechStarted
                && currentSpeech.sequence == 1,
            "late old item and response callbacks do not create a sequence gap"
        )
        try await authorizeResponse(
            stack,
            from: currentSpeech,
            responseID: "response-current"
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
        let connectionCountAfterLateCallbacks = await stack.transport
            .connectCount()
        let closeCountAfterLateCallbacks = await stack.transport.closeCount()
        expect(
            connectionCountAfterLateCallbacks == connectionCountAfterInterrupt
                && closeCountAfterLateCallbacks == closeCountAfterInterrupt,
            "late same-socket callbacks cannot reconnect or close the session"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: nextIdentity)
        )
    }

    private static func testUnauthorizedResponseFailsClosed() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 4)
        try await openAndBootstrap(stack, identity: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"unauthorized-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        let sentBefore = try await sentTypes(stack.transport)
        expect(
            sentBefore.filter { $0 == "response.create" }.isEmpty,
            "Provider speech evidence alone has no response authorization"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"unauthorized-response","status":"in_progress"}}"#
        )
        await waitUntilTerminalError(
            stack.adapter,
            session: identity,
            expected: .invalidEvent
        )
        let activeResponse = await stack.adapter
            .activeWireResponseIDForTesting(session: identity)
        expect(
            activeResponse == nil,
            "unexpected response.created cannot acquire a Runtime response identity"
        )
        try? await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testOverlappingResponseFailsClosed() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 5)
        try await openAndBootstrap(stack, identity: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"overlap-user"}"#
        )
        let speech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: speech,
            responseID: "response-owned"
        )
        for _ in 0 ..< 10_000 {
            if await stack.adapter.activeWireResponseIDForTesting(
                session: identity
            ) == "response-owned" { break }
            await Task.yield()
        }
        await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"response-overlap","status":"in_progress"}}"#
        )
        await waitUntilTerminalError(
            stack.adapter,
            session: identity,
            expected: .invalidEvent
        )
        let activeResponseID = await stack.adapter
            .activeWireResponseIDForTesting(session: identity)
        expect(
            activeResponseID == "response-owned",
            "Provider overlap cannot replace the Runtime-owned active response"
        )
        let overlapSentTypes = try await sentTypes(stack.transport)
        expect(
            overlapSentTypes.filter {
                $0 == "response.cancel"
            }.isEmpty,
            "overlapping response evidence cannot cancel the active response"
        )
        await expectRealtimeError(.invalidEvent) {
            _ = try await stack.adapter.receiveEvent(session: identity)
        }
        try? await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testGenerationReconnectRejectsUnseenOldResponse()
        async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 8)
        let tools = runtimeToolAdvertisements()
        try await openAndBootstrap(
            stack,
            identity: identity,
            tools: tools
        )

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"reused-user"}"#
        )
        let oldSpeech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: oldSpeech,
            responseID: "reused-response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.text.delta","response_id":"reused-response","delta":"old"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)

        let nextIdentity = sessionIdentity(
            generation: 9,
            leaseID: identity.brainLeaseID,
            routeEpoch: identity.routeEpoch
        )
        try await stack.adapter.cancelGeneration(
            RealtimeBrainCancelGenerationCommand(
                identity: identity,
                nextGeneration: nextIdentity.generation,
                reason: .runtimeDecision
            )
        )
        let cancelled = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            cancelled.kind == .cancelled(.runtimeDecision),
            "generation reconnect retains the Runtime cancellation event"
        )
        let connectionCount = await stack.transport.connectCount()
        expect(
            connectionCount == 2,
            "generation transition opens a fresh physical WebSocket"
        )

        let updates = try await sentObjects(stack.transport).filter {
            $0["type"] as? String == "session.update"
        }
        guard let initialSession = updates.first?["session"]
                as? [String: Any],
              let replayedSession = updates.last?["session"]
                as? [String: Any],
              let initialTools = initialSession["tools"]
                as? [[String: Any]],
              let replayedTools = replayedSession["tools"]
                as? [[String: Any]] else {
            fatalError("generation reconnect must retain Runtime Tools")
        }
        let initialToolsJSON = try JSONSerialization.data(
            withJSONObject: initialTools,
            options: [.sortedKeys]
        )
        let replayedToolsJSON = try JSONSerialization.data(
            withJSONObject: replayedTools,
            options: [.sortedKeys]
        )
        expect(
            initialTools.count == tools.count
                && replayedToolsJSON == initialToolsJSON,
            "fresh WebSocket replays the identical Runtime Tool snapshot"
        )
        expect(
            initialSession["voice"] as? String == "R6FixtureVoice"
                && replayedSession["voice"] as? String
                    == initialSession["voice"] as? String,
            "fresh WebSocket replays the same private Provider default voice"
        )
        let replayedInstructions = replayedSession["instructions"] as? String
        expect(
            replayedInstructions?.contains("[stableResident]\nfixture context")
                == true,
            "fresh WebSocket replays only the acknowledged Runtime context"
        )

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"reused-user"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"reused-user","transcript":"reused transcript"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"fallback-user"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"fallback-user","transcript":"fallback transcript"}"#
        )
        let currentSpeech = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            currentSpeech.kind == .userSpeechStarted,
            "new generation establishes its own turn before response mapping"
        )
        let reusedTranscript = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            reusedTranscript.kind
                == .userTranscriptFinal("reused transcript"),
            "fresh Qwen session may reuse an old item ID"
        )
        _ = try await stack.adapter.receiveEvent(session: nextIdentity)
        _ = try await stack.adapter.receiveEvent(session: nextIdentity)

        let oldFrameEnteredCurrentConnection = await stack.transport.enqueueText(
            #"{"type":"response.created","response":{"id":"unseen-old-response","status":"in_progress"}}"#,
            connectionNumber: 1
        )
        expect(
            !oldFrameEnteredCurrentConnection,
            "closed-generation response.created cannot enter the new socket"
        )
        let activeResponseID = await stack.adapter
            .activeWireResponseIDForTesting(session: nextIdentity)
        expect(
            activeResponseID == nil,
            "unseen old response is never relabeled with the new generation"
        )

        try await authorizeResponse(
            stack,
            from: reusedTranscript,
            responseID: "reused-response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.text.done","response_id":"reused-response","text":"reused response"}"#
        )
        let currentText = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            currentText.kind == .residentTextFinal("reused response")
                && currentText.identity.session == nextIdentity,
            "fresh Qwen session may reuse an old response ID"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: nextIdentity)
        )
    }

    private static func testCloseWinsGenerationReconnect() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 10)
        try await openAndBootstrap(stack, identity: identity)
        await stack.transport.holdSessionUpdateAcknowledgements()

        let transition = Task { () -> RealtimeResidentBrainError? in
            do {
                try await stack.adapter.cancelGeneration(
                    RealtimeBrainCancelGenerationCommand(
                        identity: identity,
                        nextGeneration: identity.generation + 1,
                        reason: .runtimeDecision
                    )
                )
                return nil
            } catch let error as RealtimeResidentBrainError {
                return error
            } catch {
                return .transportFailure
            }
        }
        await stack.transport.waitUntilSent(type: "session.update", count: 3)
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        let transitionError = await transition.value
        expect(
            transitionError == .cancelled,
            "definitive close wins a reconnect handshake race"
        )
        await stack.transport.releaseSessionUpdateAcknowledgements()

        let reopenedIdentity = sessionIdentity(generation: 1)
        try await openAndBootstrap(stack, identity: reopenedIdentity)
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: reopenedIdentity)
        )
    }

    private static func testToolFixture() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 11)
        try await openAndBootstrap(
            stack,
            identity: identity,
            tools: runtimeToolAdvertisements()
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"tool-user"}"#
        )
        let toolSpeech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: toolSpeech,
            responseID: "tool-response"
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
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"tool-collision-user"}"#
        )
        let collisionSpeech = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: collisionSpeech,
            responseID: "tool-collision-response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"tool-collision-response","item_id":"tool-collision-item","call_id":"call-weather","name":"weather_lookup","arguments":"{\"city\":\"Suzhou\"}"}"#
        )
        let collisionEvent = try await stack.adapter.receiveEvent(
            session: identity
        )
        guard case .toolCall(let collisionCandidate) = collisionEvent.kind else {
            fatalError("duplicate callID candidate expected")
        }
        expect(
            collisionCandidate.callID == candidate.callID
                && collisionCandidate.identity != candidate.identity,
            "duplicate callID remains a distinct Runtime candidate"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"tool-collision-response","status":"completed","output":[{"type":"function_call","call_id":"call-weather","name":"weather_lookup","arguments":"{\"city\":\"Suzhou\"}"}]}}"#
        )
        await stack.transport.holdResponseCreationAcknowledgements()
        await stack.transport.useNextResponseID("response-tool-1")
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
        await expectRealtimeError(.invalidIdentity) {
            try await stack.adapter.submitToolResult(
                RealtimeBrainToolResultCommand(
                    identity: collisionEvent.identity,
                    sequence: 2,
                    callID: collisionCandidate.callID,
                    output: #"{"temperature":26}"#,
                    isError: false
                )
            )
        }
        expect(
            true,
            "original Tool correlation survives a duplicate callID candidate"
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

    private static func testFastToolResultWaitsForResponseDone() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 12)
        try await openAndBootstrap(
            stack,
            identity: identity,
            tools: runtimeToolAdvertisements()
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"fast-tool-user"}"#
        )
        let speech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: speech,
            responseID: "fast-tool-response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"fast-tool-response","item_id":"fast-tool-item","call_id":"fast-tool-call","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}"#
        )
        let toolEvent = try await stack.adapter.receiveEvent(session: identity)
        guard case .toolCall(let candidate) = toolEvent.kind else {
            fatalError("fast tool candidate expected")
        }

        await stack.transport.holdResponseCreationAcknowledgements()
        await stack.transport.useNextResponseID("fast-tool-continuation")
        let before = try await sentTypes(stack.transport)
        let resultTask = Task {
            try await stack.adapter.submitToolResult(
                RealtimeBrainToolResultCommand(
                    identity: toolEvent.identity,
                    sequence: 1,
                    callID: candidate.callID,
                    output: #"{"temperature":25}"#,
                    isError: false
                )
            )
        }
        await waitUntilResponseDoneWaiter(
            stack.adapter,
            responseID: "fast-tool-response",
            session: identity
        )
        let whileOldResponseActive = try await sentTypes(stack.transport)
        expect(
            whileOldResponseActive.filter { $0 == "conversation.item.create" }
                .count
                == before.filter { $0 == "conversation.item.create" }.count
                && whileOldResponseActive.filter { $0 == "response.create" }
                    .count
                    == before.filter { $0 == "response.create" }.count,
            "tool continuation waits for the old response.done barrier"
        )

        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"fast-tool-response","status":"completed","output":[{"type":"function_call","call_id":"fast-tool-call","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}]}}"#
        )
        await stack.transport.waitUntilSent(type: "conversation.item.create")
        await stack.transport.waitUntilSent(type: "response.create", count: 2)
        let afterBarrier = try await sentTypes(stack.transport)
        expect(
            afterBarrier.filter { $0 == "conversation.item.create" }.count
                == before.filter { $0 == "conversation.item.create" }.count + 1
                && afterBarrier.filter { $0 == "response.create" }.count
                    == before.filter { $0 == "response.create" }.count + 1,
            "one tool output and one continuation are sent after response.done"
        )
        await stack.transport.releaseResponseCreationAcknowledgements()
        try await resultTask.value

        await stack.transport.enqueueText(
            #"{"type":"response.text.done","response_id":"fast-tool-continuation","text":"杭州现在 25 度。"}"#
        )
        let finalText = try await stack.adapter.receiveEvent(session: identity)
        expect(
            finalText.kind == .residentTextFinal("杭州现在 25 度。"),
            "fast tool continuation remains bound to the original Runtime turn"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"fast-tool-continuation","status":"completed","output":[{"type":"message","content":[{"type":"text","text":"杭州现在 25 度。"}]}]}}"#
        )
        let semantic = try await stack.adapter.receiveEvent(session: identity)
        expect(
            semantic.kind == .residentSemanticFinal(
                RealtimeBrainSemanticOutput(canonicalText: "杭州现在 25 度。")
            ),
            "fast tool continuation can finish semantically"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testMultipleToolResultsCreateOneContinuation()
        async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 13)
        try await openAndBootstrap(
            stack,
            identity: identity,
            tools: runtimeToolAdvertisements()
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"multi-tool-user"}"#
        )
        let speech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: speech,
            responseID: "multi-tool-response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"multi-tool-response","item_id":"multi-tool-item-1","call_id":"multi-tool-call-1","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"multi-tool-response","item_id":"multi-tool-item-2","call_id":"multi-tool-call-2","name":"weather_lookup","arguments":"{\"city\":\"Shanghai\"}"}"#
        )
        let firstEvent = try await stack.adapter.receiveEvent(session: identity)
        let secondEvent = try await stack.adapter.receiveEvent(session: identity)
        guard case .toolCall(let firstCandidate) = firstEvent.kind,
              case .toolCall(let secondCandidate) = secondEvent.kind else {
            fatalError("two tool candidates expected")
        }
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"multi-tool-response","status":"completed","output":[{"type":"function_call","call_id":"multi-tool-call-1","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"},{"type":"function_call","call_id":"multi-tool-call-2","name":"weather_lookup","arguments":"{\"city\":\"Shanghai\"}"}]}}"#
        )

        let before = try await sentTypes(stack.transport)
        try await stack.adapter.submitToolResult(
            RealtimeBrainToolResultCommand(
                identity: firstEvent.identity,
                sequence: 1,
                callID: firstCandidate.callID,
                output: #"{"temperature":25}"#,
                isError: false
            )
        )
        let afterFirst = try await sentTypes(stack.transport)
        expect(
            afterFirst.filter { $0 == "conversation.item.create" }.count
                == before.filter { $0 == "conversation.item.create" }.count + 1
                && afterFirst.filter { $0 == "response.create" }.count
                    == before.filter { $0 == "response.create" }.count,
            "a non-final tool result submits output without opening a continuation"
        )

        await stack.transport.holdResponseCreationAcknowledgements()
        await stack.transport.useNextResponseID("multi-tool-continuation")
        let secondResult = Task {
            try await stack.adapter.submitToolResult(
                RealtimeBrainToolResultCommand(
                    identity: secondEvent.identity,
                    sequence: 2,
                    callID: secondCandidate.callID,
                    output: #"{"temperature":26}"#,
                    isError: false
                )
            )
        }
        await stack.transport.waitUntilSent(
            type: "response.create",
            count: before.filter { $0 == "response.create" }.count + 1
        )
        let afterLast = try await sentTypes(stack.transport)
        expect(
            afterLast.filter { $0 == "conversation.item.create" }.count
                == before.filter { $0 == "conversation.item.create" }.count + 2
                && afterLast.filter { $0 == "response.create" }.count
                    == before.filter { $0 == "response.create" }.count + 1,
            "the final tool result opens exactly one continuation"
        )
        await stack.transport.releaseResponseCreationAcknowledgements()
        try await secondResult.value

        await stack.transport.enqueueText(
            #"{"type":"response.text.done","response_id":"multi-tool-continuation","text":"两座城市都已查询。"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"multi-tool-continuation","status":"completed","output":[{"type":"message","content":[{"type":"text","text":"两座城市都已查询。"}]}]}}"#
        )
        let semantic = try await stack.adapter.receiveEvent(session: identity)
        expect(
            semantic.kind == .residentSemanticFinal(
                RealtimeBrainSemanticOutput(canonicalText: "两座城市都已查询。")
            ),
            "one multi-tool continuation reaches a semantic final"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testFailedToolResponseCannotContinue() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 14)
        try await openAndBootstrap(
            stack,
            identity: identity,
            tools: runtimeToolAdvertisements()
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"failed-tool-user"}"#
        )
        let speech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: speech,
            responseID: "failed-tool-response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"failed-tool-response","item_id":"failed-tool-item","call_id":"failed-tool-call","name":"weather_lookup","arguments":"{}"}"#
        )
        let toolEvent = try await stack.adapter.receiveEvent(session: identity)
        guard case .toolCall(let candidate) = toolEvent.kind else {
            fatalError("failed tool candidate expected")
        }
        let before = try await sentTypes(stack.transport)
        let resultTask = Task { () -> RealtimeResidentBrainError? in
            do {
                try await stack.adapter.submitToolResult(
                    RealtimeBrainToolResultCommand(
                        identity: toolEvent.identity,
                        sequence: 1,
                        callID: candidate.callID,
                        output: "{}",
                        isError: false
                    )
                )
                return nil
            } catch let error as RealtimeResidentBrainError {
                return error
            } catch {
                return .transportFailure
            }
        }
        await waitUntilResponseDoneWaiter(
            stack.adapter,
            responseID: "failed-tool-response",
            session: identity
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"failed-tool-response","status":"failed","output":[]}}"#
        )
        let resultError = await resultTask.value
        expect(
            resultError == .providerFailure,
            "failed tool response rejects its pending continuation"
        )
        let after = try await sentTypes(stack.transport)
        expect(
            after.filter { $0 == "conversation.item.create" }.count
                == before.filter { $0 == "conversation.item.create" }.count
                && after.filter { $0 == "response.create" }.count
                    == before.filter { $0 == "response.create" }.count,
            "failed tool response cannot emit tool output or response.create"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )

        let lateStack = try makeStack()
        let lateIdentity = sessionIdentity(generation: 15)
        try await openAndBootstrap(
            lateStack,
            identity: lateIdentity,
            tools: runtimeToolAdvertisements()
        )
        await lateStack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"late-failed-tool-user"}"#
        )
        let lateSpeech = try await lateStack.adapter.receiveEvent(
            session: lateIdentity
        )
        try await authorizeResponse(
            lateStack,
            from: lateSpeech,
            responseID: "late-failed-tool-response"
        )
        await lateStack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"late-failed-tool-response","item_id":"late-failed-tool-item","call_id":"late-failed-tool-call","name":"weather_lookup","arguments":"{}"}"#
        )
        let lateToolEvent = try await lateStack.adapter.receiveEvent(
            session: lateIdentity
        )
        guard case .toolCall(let lateCandidate) = lateToolEvent.kind else {
            fatalError("late failed tool candidate expected")
        }
        await lateStack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"late-failed-tool-response","status":"failed","output":[]}}"#
        )
        let lateFailure = try await lateStack.adapter.receiveEvent(
            session: lateIdentity
        )
        expect(
            lateFailure.kind == .error(.providerFailure),
            "failed response terminalizes tool correlation before a late result"
        )
        let lateBefore = try await sentTypes(lateStack.transport)
        await expectRealtimeError(.invalidIdentity) {
            try await lateStack.adapter.submitToolResult(
                RealtimeBrainToolResultCommand(
                    identity: lateToolEvent.identity,
                    sequence: 1,
                    callID: lateCandidate.callID,
                    output: "{}",
                    isError: false
                )
            )
        }
        let lateAfter = try await sentTypes(lateStack.transport)
        expect(
            lateAfter.filter { $0 == "conversation.item.create" }.count
                == lateBefore.filter { $0 == "conversation.item.create" }.count
                && lateAfter.filter { $0 == "response.create" }.count
                    == lateBefore.filter { $0 == "response.create" }.count,
            "late tool result cannot revive a failed response"
        )
        try await lateStack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: lateIdentity)
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
        let firstSpeech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: firstSpeech,
            responseID: "response-incomplete"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.audio.done","response_id":"response-incomplete"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"response-incomplete","status":"incomplete","output":[]}}"#
        )
        let incomplete = try await stack.adapter.receiveEvent(session: identity)
        expect(
            incomplete.kind == .error(.providerFailure),
            "incomplete response is a neutral Provider failure, not an interruption decision"
        )

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"empty-completed-user"}"#
        )
        let emptySpeech = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: emptySpeech,
            responseID: "response-empty-completed"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"response-empty-completed","status":"completed","output":[]}}"#
        )
        let emptyCompleted = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            emptyCompleted.kind == .error(.providerFailure),
            "completed response without semantic output is terminal, not an orphaned active response"
        )

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"failure-user-2"}"#
        )
        let secondSpeech = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: secondSpeech,
            responseID: "response-error"
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

    private static func testPendingEventBufferFailsClosed() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 27)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"buffer-user"}"#
        )
        let speech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: speech,
            responseID: "buffer-response"
        )
        await stack.transport.holdNextCloseCompletion()
        for _ in 0 ... 256 {
            await stack.transport.enqueueText(
                #"{"type":"response.audio.delta","response_id":"buffer-response","delta":"AAA="}"#
            )
        }
        await waitUntilTerminalError(
            stack.adapter,
            session: identity,
            expected: .providerFailure
        )
        await waitUntilTransportCloseCount(stack.transport, expected: 1)

        let closeTask = Task {
            try await stack.adapter.closeSession(
                RealtimeBrainCloseSessionCommand(identity: identity)
            )
        }
        await waitUntilClosing(stack.adapter, session: identity)
        let closeCountWhileJoining = await stack.transport.closeCount()
        expect(
            closeCountWhileJoining == 1,
            "formal close joins the overflow transport close"
        )
        await stack.transport.releaseHeldCloseCompletion()
        try await closeTask.value
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        let closeCountAfterFormalClose = await stack.transport.closeCount()
        expect(
            closeCountAfterFormalClose == 1,
            "formal close remains idempotent after overflow emergency close"
        )

        let reopenedIdentity = sessionIdentity(generation: 1)
        try await openAndBootstrap(stack, identity: reopenedIdentity)
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: reopenedIdentity)
        )
        let recoveredCloseCount = await stack.transport.closeCount()
        expect(
            recoveredCloseCount == 2,
            "overflow close completes before a recovered session can reopen"
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
        let speech = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(
            stack,
            from: speech,
            responseID: "cancel-error-response"
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

    private static func testRuntimeAcousticActivityAdmissionFence(
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
        expect(runtime.loadDR(from: fixture).isLoaded,
               "turn-completion fixture resident loads")
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
                        content: "acoustic activity admission fence"
                    )]
                )
            ),
            "Runtime acoustic-activity fixture bootstraps"
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"runtime-completion-user"}"#
        )
        let speechStart = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        guard case .accepted(let pendingStart) = speechStart,
              pendingStart.kind == .userSpeechStarted else {
            fatalError("Runtime pending speech-start expected")
        }
        let uncorrelatedActivity = runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(
            uncorrelatedActivity.phase == .idle
                && uncorrelatedActivity.claimedAcousticSequence == 0,
            "Provider VAD without Runtime acoustic eligibility fails closed"
        )
        expect(
            runtime
                .realtimeUtteranceCompletionTracksTranscriptFinalForTesting(
                    pendingStart.identity
                ),
            "pending exact turn is fenced before acoustic authorization"
        )
        let userFinal = try await receiveRuntimeTranscript(
            stack,
            runtime: runtime,
            identity: identity,
            itemID: "runtime-completion-user",
            transcript: "wait for utterance completion"
        )
        if case .accepted = userFinal {
            expect(
                true,
                "final allows a bounded Provider final-before-stop ordering"
            )
        } else {
            expect(
                false,
                "final allows a bounded Provider final-before-stop ordering"
            )
        }
        try? await Task.sleep(for: .milliseconds(1_120))
        let retiredActivity = runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(
            retiredActivity.phase == .idle
                && retiredActivity.pendingStartTurnID == nil,
            "missing Provider speech stop cannot leave Runtime pending"
        )
        let sentAfterFinal = try await sentTypes(stack.transport)
        expect(
            sentAfterFinal.filter { $0 == "response.create" }.isEmpty,
            "pending exact-turn transcript final cannot create a response"
        )
        expectRealtimeSuccess(
            await runtime.closeRealtimeResidentBrainSession(
                identity: identity
            ),
            "pending-activity session remains definitively closeable"
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
        let speechStarted = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        guard case .accepted(let acceptedSpeechStarted) = speechStarted,
              acceptedSpeechStarted.kind == .userSpeechStarted else {
            fatalError("Runtime-tracked generation speech start expected")
        }
        try await authorizeResponse(
            stack,
            from: acceptedSpeechStarted,
            responseID: "runtime-old-response"
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
            await runtime.interruptRealtimeResidentBrainForTesting(
                identity: identity,
                reason: .runtimeDecision
            )
        )
        let staleDisposition = try await oldReceive.value
        expect(
            staleDisposition == .rejectedStale,
            "Runtime rejects the explicitly woken old-generation receive"
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
                && currentEvent.sequence == 1
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
        await stack.transport.holdSessionUpdateAcknowledgements()
        let cancelTask = Task {
            await runtime.cancelRealtimeResidentBrainGenerationForTesting(
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
        await stack.transport.waitUntilSent(type: "session.update", count: 3)
        let reconnectCount = await stack.transport.connectCount()
        expect(
            reconnectCount == 2,
            "generation fence opens a replacement Provider session"
        )
        expect(
            runtime.activeBrainLeaseForTesting()?.generation
                == .realtimeResidentBrain(identity.generation),
            "Runtime generation does not advance before reconnect context ACK"
        )
        await stack.transport.releaseSessionUpdateAcknowledgements()
        let nextIdentity = try realtimeIdentity(await cancelTask.value)
        expect(
            nextIdentity.generation == identity.generation + 1,
            "cancel advances generation only after clear and reconnect ACKs"
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

    private static func makeStack(
        diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil
    ) throws -> (
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
                    defaultProviderVoiceID: "R6FixtureVoice",
                    acknowledgementTimeout: .seconds(1)
                ),
                diagnosticBuffer: diagnosticBuffer
            ),
            transport
        )
    }

    private static func testUnsafeTurnDetectionAcknowledgementFailsClosed()
        async throws {
        cases += 1
        let stack = try makeStack()
        await stack.transport.useUnsafeTurnDetectionAcknowledgement()
        await expectRealtimeError(.invalidEvent) {
            try await stack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(
                    identity: sessionIdentity(generation: 1)
                )
            )
        }
        let closeCount = await stack.transport.closeCount()
        expect(
            closeCount == 1,
            "unsafe Provider VAD authority acknowledgement closes the session"
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
        identity: RealtimeBrainSessionIdentity,
        tools: [RealtimeBrainToolAdvertisement] = []
    ) async throws {
        try await stack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(
                identity: identity,
                tools: tools
            )
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

    private static func authorizeResponse(
        _ stack: (
            adapter: QwenRealtimeResidentBrainAdapter,
            transport: R3FakeRealtimeWebSocketTransport
        ),
        from event: RealtimeResidentBrainEvent,
        responseID: String
    ) async throws {
        await stack.transport.useNextResponseID(responseID)
        try await stack.adapter.createResponse(
            RealtimeBrainCreateResponseCommand(
                identity: event.identity,
                sourceEventSequence: event.sequence
            )
        )
    }

    private static func residentTextEvents(
        generation: UInt64,
        responseID: String,
        wireEvents: [String],
        responseDoneContent: String
    ) async throws -> [RealtimeResidentBrainEventKind] {
        let stack = try makeStack()
        let identity = sessionIdentity(generation: generation)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"subtitle-turn-\#(generation)"}"#
        )
        let speechStarted = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: speechStarted,
            responseID: responseID
        )
        for event in wireEvents {
            await stack.transport.enqueueText(event)
        }
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"\#(responseID)","status":"completed","output":[{"type":"message","content":[\#(responseDoneContent)]}]}}"#
        )

        var events: [RealtimeResidentBrainEventKind] = []
        for _ in 0 ..< 3 {
            events.append(try await stack.adapter.receiveEvent(
                session: identity
            ).kind)
        }
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        return events
    }

    private static func receiveRuntimeTranscript(
        _ stack: (
            adapter: QwenRealtimeResidentBrainAdapter,
            transport: R3FakeRealtimeWebSocketTransport
        ),
        runtime: RuntimeCore,
        identity: RealtimeBrainSessionIdentity,
        itemID: String,
        transcript: String
    ) async throws -> RealtimeBrainEventDisposition {
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"\#(itemID)","transcript":"\#(transcript)"}"#
        )
        return try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
    }

    private static func runtimeToolAdvertisements()
        -> [RealtimeBrainToolAdvertisement] {
        [RealtimeBrainToolAdvertisement(
            name: "weather_lookup",
            description: "Look up weather by city.",
            parametersJSON: Data(
                """
                {
                  "type": "object",
                  "properties": {"city": {"type": "string"}},
                  "required": ["city"],
                  "additionalProperties": false
                }
                """.utf8
            )
        )]
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

    private static func waitUntilResponseDoneWaiter(
        _ adapter: QwenRealtimeResidentBrainAdapter,
        responseID: String,
        session: RealtimeBrainSessionIdentity
    ) async {
        for _ in 0 ..< 10_000 {
            if await adapter.isWaitingForResponseDoneForTesting(
                responseID,
                session: session
            ) {
                return
            }
            await Task.yield()
        }
        fatalError("tool result did not wait for response.done")
    }

    private static func waitUntilTerminalError(
        _ adapter: QwenRealtimeResidentBrainAdapter,
        session: RealtimeBrainSessionIdentity,
        expected: RealtimeResidentBrainError
    ) async {
        for _ in 0 ..< 10_000 {
            if await adapter.terminalErrorForTesting(session: session)
                == expected {
                return
            }
            await Task.yield()
        }
        fatalError("Adapter did not enter the expected terminal failure")
    }

    private static func waitUntilTransportCloseCount(
        _ transport: R3FakeRealtimeWebSocketTransport,
        expected: Int
    ) async {
        for _ in 0 ..< 10_000 {
            if await transport.closeCount() >= expected { return }
            await Task.yield()
        }
        fatalError("transport did not enter the expected close")
    }

    private static func waitUntilClosing(
        _ adapter: QwenRealtimeResidentBrainAdapter,
        session: RealtimeBrainSessionIdentity
    ) async {
        for _ in 0 ..< 10_000 {
            if await adapter.isClosingForTesting(session: session) { return }
            await Task.yield()
        }
        fatalError("Adapter did not join the terminal transport close")
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
