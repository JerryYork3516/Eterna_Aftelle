import Foundation

nonisolated protocol ProviderCredentialReading: Sendable {
    func readCredential(for keyRef: String) throws -> String?
}

nonisolated private struct QwenTestCredentialReader:
    ProviderCredentialReading {
    let credential: String?

    func readCredential(for keyRef: String) throws -> String? {
        credential
    }
}

@main
@MainActor
private struct QwenRealtimeAdapterTests {
    private static var checks = 0

    static func main() async throws {
        try await testHandshakeConfigurationAndContextUpdate()
        try await testTwentyMillisecondAudioAggregation()
        try await testVADTranscriptsAudioAndResponseBoundary()
        try await testCancelRejectsLateResponseEvents()
        try await testToolMappingAndContinuation()
        try await testErrorsAndConfigurationRejection()
        try await testSingaporePlusConfigurationAndClose()
        print("qwen_realtime_adapter_checks=\(checks)")
    }

    private static func testHandshakeConfigurationAndContextUpdate()
        async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ])
        let adapter = QwenRealtimeAdapter(
            credentialReader: QwenTestCredentialReader(
                credential: try storedCredential()
            ),
            transport: transport
        )
        let baseRequest = makeRequest()
        let tool = NativeSpeechToolDefinition(
            name: "weather",
            description: "Read deterministic weather.",
            parametersJSON: Data(
                #"{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}"#.utf8
            ),
            permission: .permissionFree
        )
        let request = NativeSpeechStartRequest(
            interaction: baseRequest.interaction,
            profile: baseRequest.profile,
            tools: [tool]
        )
        let initial = contextProjection(
            interaction: request.interaction,
            instructions: "thirteen-layer projection",
            version: "context-v1"
        )
        try await adapter.prepareContext(initial)
        try await adapter.start(request: request)
        let connected = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            connected.kind == .connected,
            "session.created maps to connected"
        )
        let configured = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            configured.kind == .sessionUpdated,
            "session.updated completes initialization"
        )
        let capturedBearerToken = await transport.capturedBearerToken
        expect(
            capturedBearerToken == "test-token",
            "Bearer credential is passed only to the transport"
        )
        let calls = await transport.calls
        expect(
            calls.contains(.connect(URL(
                string: "wss://workspace-123.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-flash-realtime"
            )!)),
            "Keychain workspace resolves the Beijing endpoint in Adapter"
        )

        var sentTexts = await textFrames(transport)
        let update = try json(sentTexts[0])
        let session = update["session"] as? [String: Any]
        let audio = session?["audio"] as? [String: Any]
        let input = audio?["input"] as? [String: Any]
        let inputFormat = input?["format"] as? [String: Any]
        let output = audio?["output"] as? [String: Any]
        let outputFormat = output?["format"] as? [String: Any]
        let vad = session?["turn_detection"] as? [String: Any]
        let tools = session?["tools"] as? [[String: Any]]
        let function = tools?.first?["function"] as? [String: Any]
        expect(
            session?["model"] as? String == request.profile.modelID
                && session?["voice"] as? String
                    == request.profile.voiceID,
            "model and voice remain profile configuration"
        )
        expect(
            session?["instructions"] as? String
                == "thirteen-layer projection",
            "compiled context maps only to session.instructions"
        )
        expect(
            inputFormat?["type"] as? String == "pcm"
                && inputFormat?["sample_rate"] as? Int == 24_000
                && outputFormat?["type"] as? String == "pcm"
                && outputFormat?["sample_rate"] as? Int == 24_000,
            "input and output preserve the 24 kHz mono PCM contract"
        )
        expect(
            vad?["type"] as? String == "semantic_vad"
                && vad?["threshold"] as? Double == 0.5
                && vad?["silence_duration_ms"] as? Int == 800,
            "Qwen semantic VAD is configured explicitly"
        )
        expect(
            session?["enable_search"] as? Bool == false,
            "WebSearch stays disabled while RuntimeCore tools are enabled"
        )
        expect(
            function?["name"] as? String == "weather",
            "RuntimeCore tool schema is mapped without execution"
        )

        let refreshed = contextProjection(
            interaction: request.interaction,
            instructions: "updated projection",
            version: "context-v2"
        )
        try await adapter.updateContext(refreshed)
        try await adapter.updateContext(refreshed)
        sentTexts = await textFrames(transport)
        let contextUpdates = try sentTexts.compactMap { text -> String? in
            let object = try json(text)
            guard let updateSession = object["session"]
                    as? [String: Any],
                  updateSession.count == 1 else {
                return nil
            }
            return updateSession["instructions"] as? String
        }
        expect(
            contextUpdates == ["updated projection"],
            "context refresh is version-idempotent"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testTwentyMillisecondAudioAggregation()
        async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: handshake())
        let adapter = QwenRealtimeAdapter(
            credentialReader: QwenTestCredentialReader(
                credential: try storedCredential()
            ),
            transport: transport
        )
        let request = makeRequest()
        try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)

        for sequence in 0 ..< UInt64(4) {
            try await adapter.send(audio: inputFrame(
                request: request,
                sequence: sequence,
                value: UInt8(sequence)
            ))
        }
        let earlyAppends = await audioAppendFrames(transport)
        expect(
            earlyAppends.isEmpty,
            "four 20 ms frames remain inside the adapter"
        )
        try await adapter.send(audio: inputFrame(
            request: request,
            sequence: 4,
            value: 4
        ))
        let appends = await audioAppendFrames(transport)
        expect(appends.count == 1, "five 20 ms frames form one 100 ms packet")
        let object = try json(appends[0])
        let encoded = object["audio"] as? String
        let decodedPacket = encoded.flatMap { Data(base64Encoded: $0) }
        expect(
            decodedPacket?.count == 4_800,
            "aggregated packet contains exactly 100 ms of PCM16"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testVADTranscriptsAudioAndResponseBoundary()
        async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: handshake() + [
            .text(#"{"type":"input_audio_buffer.speech_started","item_id":"user-1"}"#),
            .text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"user-1","text":"今天","stash":"好吗"}"#),
            .text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"user-1","transcript":"今天好吗"}"#),
            .text(#"{"type":"input_audio_buffer.speech_stopped","item_id":"user-1"}"#),
            .text(#"{"type":"response.created","response":{"id":"response-1"}}"#),
            .text(#"{"type":"response.audio_transcript.delta","response_id":"response-1","item_id":"resident-1","delta":"当然"}"#),
            .text(#"{"type":"response.audio.delta","response_id":"response-1","item_id":"resident-1","delta":"AQI="}"#),
            .text(#"{"type":"response.audio_transcript.done","response_id":"response-1","item_id":"resident-1","transcript":"当然很好。"}"#),
            .text(#"{"type":"response.audio.done","response_id":"response-1","item_id":"resident-1"}"#),
            .text(#"{"type":"response.done","response":{"id":"response-1","status":"completed"}}"#)
        ])
        let adapter = makeAdapter(transport: transport)
        let request = makeRequest()
        try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let expected: [NativeSpeechEventKind] = [
            .inputSpeechStarted,
            .partialTranscript("今天好吗"),
            .finalTranscript("今天好吗"),
            .inputSpeechEnded,
            .thinking,
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 0,
                bytes: Data([1, 2]),
                format: .pcm16
            )),
            .outputText(text: "当然", isFinal: false),
            .outputText(text: "当然很好。", isFinal: true),
            .responseCompleted
        ]
        for kind in expected {
            let event = try await adapter.receive(
                interactionID: request.interaction.id
            )
            expect(event.kind == kind, "VAD/transcript/audio event order is stable")
        }
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testCancelRejectsLateResponseEvents()
        async throws {
        let transport = FakeRealtimeWebSocketTransport(
            frames: handshake() + [
                .text(#"{"type":"response.created","response":{"id":"old-response"}}"#)
            ],
            waitsWhenEmpty: true
        )
        let adapter = makeAdapter(transport: transport)
        let request = makeRequest()
        try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let thinking = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            thinking.kind == .thinking,
            "response becomes active before cancellation"
        )
        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"old-response","item_id":"old-item","delta":"AQI="}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio_transcript.done","response_id":"old-response","item_id":"old-item","transcript":"stale"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"old-response","status":"incomplete"}}"#
        ))
        let cancelled = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            cancelled.kind == .cancelled(reason: "interrupted"),
            "response.done acknowledges the pending Runtime cancellation"
        )
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"old-response","item_id":"old-item","delta":"AwQ="}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"new-response"}}"#
        ))
        let next = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(next.kind == .thinking, "a new response survives old late audio")
        let ignoredEventCount = await adapter.ignoredEventCount
        expect(
            ignoredEventCount == 3,
            "cancelled audio, subtitle, and post-cancel audio are rejected"
        )
        let sentTexts = await textFrames(transport)
        expect(
            sentTexts.filter { $0.contains("response.cancel") }.count == 1,
            "active response cancellation is sent exactly once"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testToolMappingAndContinuation() async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: handshake() + [
            .text(#"{"type":"response.created","response":{"id":"tool-response"}}"#),
            .text(#"{"type":"conversation.item.created","response_id":"tool-response","item":{"id":"tool-item","type":"function_call","call_id":"call-1","name":"weather","arguments":""}}"#),
            .text(#"{"type":"response.function_call_arguments.delta","response_id":"tool-response","call_id":"call-1","name":"weather","arguments":"{\"city\":"}"#),
            .text(#"{"type":"response.function_call_arguments.done","response_id":"tool-response","call_id":"call-1","name":"weather","arguments":"{\"city\":\"北京\"}"}"#),
            .text(#"{"type":"response.done","response":{"id":"tool-response","status":"completed"}}"#)
        ])
        let adapter = makeAdapter(transport: transport)
        let request = makeRequest()
        try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let candidate = try await adapter.receive(
            interactionID: request.interaction.id
        )
        guard case .toolRequestCandidate(let tool) = candidate.kind else {
            fatalError("FAILED: tool arguments emit a candidate")
        }
        expect(
            tool.callID == "call-1"
                && tool.toolName == "weather"
                && tool.arguments == Data(#"{"city":"北京"}"#.utf8),
            "Qwen tool event maps to the Runtime-owned request"
        )
        let completed = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            completed.kind == .responseCompleted,
            "tool response reaches its response.done boundary"
        )
        try await adapter.submitToolOutput(
            NativeSpeechToolOutput(
                callID: "call-1",
                output: #"{"temperature":20}"#
            ),
            interactionID: request.interaction.id
        )
        try await adapter.requestToolContinuation(
            interactionID: request.interaction.id
        )
        try await adapter.requestToolContinuation(
            interactionID: request.interaction.id
        )
        let sentTexts = await textFrames(transport)
        expect(
            sentTexts.filter { $0.contains("function_call_output") }.count == 1,
            "tool output is mapped once without executing in the adapter"
        )
        expect(
            sentTexts.filter { $0.contains("response.create") }.count == 1,
            "tool continuation is idempotent"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testErrorsAndConfigurationRejection()
        async throws {
        let errorTransport = FakeRealtimeWebSocketTransport(
            frames: handshake() + [
                .text(#"{"type":"error","error":{"code":"invalid_api_key"}}"#)
            ]
        )
        let adapter = makeAdapter(transport: errorTransport)
        let request = makeRequest()
        try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let failed = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            failed.kind == .failed(.unauthorized),
            "provider error maps to the standard unauthorized error"
        )
        try await adapter.close(interactionID: request.interaction.id)

        let turnErrorTransport = FakeRealtimeWebSocketTransport(
            frames: handshake() + [
                .text(#"{"type":"response.created","response":{"id":"response-error"}}"#),
                .text(#"{"type":"error","response_id":"response-error","error":{"code":"rate_limit_exceeded"}}"#)
            ]
        )
        let turnErrorAdapter = makeAdapter(transport: turnErrorTransport)
        let turnErrorRequest = makeRequest()
        try await start(turnErrorAdapter, request: turnErrorRequest)
        _ = try await turnErrorAdapter.receive(
            interactionID: turnErrorRequest.interaction.id
        )
        _ = try await turnErrorAdapter.receive(
            interactionID: turnErrorRequest.interaction.id
        )
        _ = try await turnErrorAdapter.receive(
            interactionID: turnErrorRequest.interaction.id
        )
        let turnFailed = try await turnErrorAdapter.receive(
            interactionID: turnErrorRequest.interaction.id
        )
        expect(
            turnFailed.kind == .turnFailed(.rateLimited),
            "response-scoped errors fail only the active turn"
        )
        try await turnErrorAdapter.close(
            interactionID: turnErrorRequest.interaction.id
        )

        let missingCredential = QwenRealtimeAdapter(
            credentialReader: QwenTestCredentialReader(credential: nil),
            transport: FakeRealtimeWebSocketTransport()
        )
        let missingRequest = makeRequest()
        try await missingCredential.prepareContext(contextProjection(
            interaction: missingRequest.interaction,
            instructions: "context",
            version: "v1"
        ))
        do {
            try await missingCredential.start(request: missingRequest)
            fatalError("FAILED: missing credential must fail")
        } catch NativeSpeechError.missingCredential {
            checks += 1
        }

        do {
            _ = try QwenRealtimeCredential(
                workspaceID: "非法空间",
                secret: "test-token"
            )
            fatalError("FAILED: non-ASCII workspace must fail")
        } catch NativeSpeechError.invalidConfiguration {
            checks += 1
        }

        let invalidRequest = makeRequest(
            endpoint: "wss://example.invalid/api-ws/v1/realtime?model=qwen"
        )
        let invalidAdapter = makeAdapter(
            transport: FakeRealtimeWebSocketTransport()
        )
        try await invalidAdapter.prepareContext(contextProjection(
            interaction: invalidRequest.interaction,
            instructions: "context",
            version: "v1"
        ))
        do {
            try await invalidAdapter.start(request: invalidRequest)
            fatalError("FAILED: unsupported endpoint must fail")
        } catch NativeSpeechError.invalidConfiguration {
            checks += 1
        }
    }

    private static func testSingaporePlusConfigurationAndClose()
        async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: handshake())
        let adapter = makeAdapter(transport: transport)
        let request = makeRequest(
            modelID: "qwen3.5-omni-plus-realtime",
            endpoint: "wss://workspace.ap-southeast-1.maas.aliyuncs.com/"
                + "api-ws/v1/realtime?model=qwen3.5-omni-plus-realtime"
        )
        try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        try await adapter.close(interactionID: request.interaction.id)
        let calls = await transport.calls
        let sentTexts = await textFrames(transport)
        expect(
            sentTexts.contains { $0.contains("session.finish") },
            "close sends Qwen session.finish"
        )
        expect(
            calls.filter { $0 == .close(.normal) }.count == 1,
            "close releases the WebSocket normally"
        )
        expect(
            calls.contains(.connect(URL(
                string: "wss://workspace-123.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-plus-realtime"
            )!)),
            "the same adapter accepts the Singapore Plus profile"
        )
    }

    private static func makeAdapter(
        transport: FakeRealtimeWebSocketTransport
    ) -> QwenRealtimeAdapter {
        QwenRealtimeAdapter(
            credentialReader: QwenTestCredentialReader(
                credential: try! storedCredential()
            ),
            transport: transport,
            reconnectDelay: .zero
        )
    }

    @discardableResult
    private static func start(
        _ adapter: QwenRealtimeAdapter,
        request: NativeSpeechStartRequest
    ) async throws -> RealtimeSpeechContextProjection {
        let projection = contextProjection(
            interaction: request.interaction,
            instructions: "compiled resident instructions",
            version: "context-v1"
        )
        try await adapter.prepareContext(projection)
        try await adapter.start(request: request)
        return projection
    }

    private static func makeRequest(
        modelID: String = "qwen3.5-omni-flash-realtime",
        endpoint: String = "wss://workspace.cn-beijing.maas.aliyuncs.com/"
            + "api-ws/v1/realtime?model=qwen3.5-omni-flash-realtime"
    ) -> NativeSpeechStartRequest {
        let profile = NativeSpeechProviderProfile(
            profileID: "stage7_5_qwen_realtime_primary",
            providerID: "Qwen",
            capability: "native_speech",
            adapterID: "qwen_realtime",
            modelID: modelID,
            voiceID: "test-voice",
            endpoint: URL(string: endpoint)!,
            transport: "websocket",
            inputAudioFormat: .pcm16,
            outputAudioFormat: .pcm16,
            turnDetection: NativeSpeechTurnDetection(
                type: .semanticVAD,
                prefixPaddingMilliseconds: 500
            ),
            languageMetadata: "zh-CN",
            keyRef: "keychain://com.eterna.aftelle.provider.qwen/realtime_api_key"
        )
        return NativeSpeechStartRequest(
            interaction: NativeSpeechInteraction(
                residentID: "resident",
                sessionID: "session",
                providerProfileID: profile.profileID
            ),
            profile: profile
        )
    }

    private static func contextProjection(
        interaction: NativeSpeechInteraction,
        instructions: String,
        version: String
    ) -> RealtimeSpeechContextProjection {
        RealtimeSpeechContextProjection(
            residentID: interaction.residentID,
            sessionID: interaction.sessionID,
            interactionID: interaction.id,
            sections: [],
            instructions: instructions,
            budget: RealtimeSpeechContextBudget(
                maximumUTF8Bytes: 24_576,
                untrimmedUTF8Bytes: instructions.utf8.count,
                finalUTF8Bytes: instructions.utf8.count,
                removedSectionIDs: []
            ),
            refreshReason: .interactionStarted,
            compilationVersion: version
        )
    }

    private static func storedCredential(
        workspaceID: String = "workspace-123"
    ) throws -> String {
        try QwenRealtimeCredential(
            workspaceID: workspaceID,
            secret: "test-token"
        ).storedValue()
    }

    private static func inputFrame(
        request: NativeSpeechStartRequest,
        sequence: UInt64,
        value: UInt8
    ) -> NativeSpeechAudioPayload {
        NativeSpeechAudioPayload(
            interactionID: request.interaction.id,
            sequenceNumber: sequence,
            bytes: Data(repeating: value, count: 960),
            format: .pcm16
        )
    }

    private static func handshake() -> [RealtimeWebSocketFrame] {
        [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ]
    }

    private static func textFrames(
        _ transport: FakeRealtimeWebSocketTransport
    ) async -> [String] {
        await transport.calls.compactMap { call in
            guard case .send(.text(let text)) = call else { return nil }
            return text
        }
    }

    private static func audioAppendFrames(
        _ transport: FakeRealtimeWebSocketTransport
    ) async -> [String] {
        await textFrames(transport).filter {
            $0.contains("input_audio_buffer.append")
        }
    }

    private static func json(_ text: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
            as! [String: Any]
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
