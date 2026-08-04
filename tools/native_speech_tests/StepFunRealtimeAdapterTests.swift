import Foundation

nonisolated protocol ProviderCredentialReading: Sendable {
    func readCredential(for keyRef: String) throws -> String?
}

nonisolated private struct StaticCredentialReader: ProviderCredentialReading {
    let credential: String?

    func readCredential(for keyRef: String) throws -> String? {
        credential
    }
}

@main
@MainActor
private struct StepFunRealtimeAdapterTests {
    private static var checks = 0

    static func main() async throws {
        try await testHandshakeAudioCancelAndClose()
        try await testCancelRearmsSameConnection()
        try await testMissingCredentialDoesNotConnect()
        try testCodecMappings()
        try await testContinuousOutputAndResponseBoundary()
        try await testSinglePreconfigurationRetry()
        try await testStreamingFailureDoesNotReconnect()
        print("stepfun_realtime_adapter_checks=\(checks)")
    }

    private static func testHandshakeAudioCancelAndClose() async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(credential: "test-token"),
            transport: transport
        )
        let request = makeRequest()
        let startProjection = try await start(
            adapter,
            request: request
        )

        let calls = await transport.calls
        expect(calls.count == 4, "handshake has four ordered calls")
        expect(calls[0] == .connect(request.profile.endpoint), "connect is first")
        expect(calls[1] == .receive, "session.created receive is second")
        guard case .send(.text(let update)) = calls[2] else {
            fatalError("FAILED: session.update is third")
        }
        let updateObject = try json(update)
        expect(updateObject["type"] as? String == "session.update", "session.update type")
        let session = updateObject["session"] as? [String: Any]
        expect(session?["modalities"] as? [String] == ["text", "audio"], "modalities fixed")
        expect(session?["voice"] as? String == "linjiajiejie", "voice fixed")
        expect(session?["input_audio_format"] as? String == "pcm16", "input format fixed")
        expect(session?["output_audio_format"] as? String == "pcm16", "output format fixed")
        let vad = session?["turn_detection"] as? [String: Any]
        expect(vad?["type"] as? String == "server_vad", "server VAD fixed")
        expect(vad?["prefix_padding_ms"] as? Int == 500, "VAD prefix fixed")
        expect(
            session?["instructions"] as? String
                == startProjection.instructions,
            "compiled instructions are sent"
        )
        expect(session?["tools"] == nil, "tools are not sent")
        expect(calls[3] == .receive, "session.updated receive is fourth")
        let capturedBearerToken = await transport.capturedBearerToken
        expect(capturedBearerToken == "test-token", "credential stays in transport memory")

        let connectedEvent = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            connectedEvent.kind == .connected,
            "created maps to connected"
        )
        let updatedEvent = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            updatedEvent.kind == .sessionUpdated,
            "updated maps to standard event"
        )

        let refreshed = contextProjection(
            interaction: request.interaction,
            instructions: "refreshed instructions",
            version: "context-v2",
            reason: .finalTranscript
        )
        try await adapter.updateContext(refreshed)
        try await adapter.updateContext(refreshed)
        let refreshCalls = await transport.calls.filter { call in
            guard case .send(.text(let text)) = call,
                  let object = try? json(text),
                  object["type"] as? String == "session.update",
                  let session = object["session"] as? [String: Any] else {
                return false
            }
            return session["instructions"] as? String
                == refreshed.instructions
        }
        expect(
            refreshCalls.count == 1,
            "duplicate context version is not resent"
        )
        let staleInteraction = NativeSpeechInteraction(
            residentID: request.interaction.residentID,
            sessionID: request.interaction.sessionID,
            providerProfileID: request.profile.profileID
        )
        do {
            try await adapter.updateContext(contextProjection(
                interaction: staleInteraction,
                instructions: "stale instructions",
                version: "stale-v1",
                reason: .finalTranscript
            ))
            fatalError("FAILED: stale context must be rejected")
        } catch NativeSpeechError.interactionMismatch {
            checks += 1
        }

        let audio = NativeSpeechAudioPayload(
            interactionID: request.interaction.id,
            sequenceNumber: 7,
            bytes: Data([0x10, 0x20]),
            format: .pcm16
        )
        try await adapter.send(audio: audio)
        let audioCalls = await transport.calls
        guard case .send(.text(let append)) = audioCalls.last else {
            fatalError("FAILED: audio append sent")
        }
        let appendObject = try json(append)
        expect(appendObject["type"] as? String == "input_audio_buffer.append", "audio append type")
        expect(appendObject["audio"] as? String == audio.bytes.base64EncodedString(), "audio base64")

        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .stopped
        )
        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .stopped
        )
        let cancelCalls = await transport.calls
        let cancelCount = try cancelCalls.filter { call in
            guard case .send(.text(let text)) = call else { return false }
            return try json(text)["type"] as? String == "response.cancel"
        }.count
        expect(cancelCount == 1, "cancel is idempotent")

        try await adapter.close(interactionID: request.interaction.id)
        try await adapter.close(interactionID: request.interaction.id)
        let closeCount = await transport.calls.filter {
            $0 == .close(.normal)
        }.count
        expect(closeCount == 1, "close is idempotent")
    }

    private static func testMissingCredentialDoesNotConnect() async throws {
        let transport = FakeRealtimeWebSocketTransport()
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(credential: nil),
            transport: transport
        )
        do {
            _ = try await start(adapter, request: makeRequest())
            fatalError("FAILED: missing credential must fail")
        } catch NativeSpeechError.missingCredential {
            checks += 1
        }
        let calls = await transport.calls
        expect(calls.isEmpty, "missing credential avoids connect")
    }

    private static func testCancelRearmsSameConnection() async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(credential: "test-token"),
            transport: transport
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(
            interactionID: request.interaction.id
        )
        _ = try await adapter.receive(
            interactionID: request.interaction.id
        )

        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )
        await transport.enqueue(
            .text(#"{"type":"response.cancelled"}"#)
        )
        let acknowledgement = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            acknowledgement.kind == .cancelled(reason: "interrupted"),
            "cancel acknowledgement remains a standard event"
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"cancelled"}}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.created"}"#)
        )
        let nextResponse = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            nextResponse.kind == .thinking,
            "duplicate cancel acknowledgement is absorbed"
        )
        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )

        let calls = await transport.calls
        let cancelCount = try calls.filter { call in
            guard case .send(.text(let text)) = call else { return false }
            return try json(text)["type"] as? String == "response.cancel"
        }.count
        expect(cancelCount == 2, "cancel acknowledgement rearms next turn")
        let ignoredEventCount = await adapter.ignoredEventCount
        expect(
            ignoredEventCount == 1,
            "duplicate cancel acknowledgement is counted once"
        )
        expect(
            calls.filter {
                if case .connect = $0 { return true }
                return false
            }.count == 1,
            "turn interrupts preserve one WebSocket"
        )
        expect(
            calls.filter { $0 == .close(.normal) }.isEmpty,
            "turn interrupt does not close transport"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testCodecMappings() throws {
        let codec = StepFunRealtimeCodec()
        let interactionID = NativeSpeechInteractionID()
        let cases: [(String, NativeSpeechEventKind)] = [
            (#"{"type":"input_audio_buffer.speech_started"}"#, .inputSpeechStarted),
            (#"{"type":"input_audio_buffer.speech_stopped"}"#, .inputSpeechEnded),
            (#"{"type":"conversation.item.input_audio_transcription.delta","delta":"你"}"#, .partialTranscript("你")),
            (#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"你好"}"#, .finalTranscript("你好")),
            (#"{"type":"response.created"}"#, .thinking),
            (#"{"type":"response.thinking.delta","delta":"private reasoning"}"#, .thinking),
            (#"{"type":"response.thinking.done","thinking":"private reasoning"}"#, .thinking),
            (#"{"type":"response.audio_transcript.delta","delta":"好"}"#, .outputText(text: "好", isFinal: false)),
            (#"{"type":"response.audio_transcript.done","transcript":"好的"}"#, .outputText(text: "好的", isFinal: true)),
            (#"{"type":"response.text.delta","delta":"好"}"#, .outputText(text: "好", isFinal: false)),
            (#"{"type":"response.text.done","text":"好的"}"#, .outputText(text: "好的", isFinal: true)),
            (#"{"type":"response.cancelled"}"#, .cancelled(reason: nil)),
            (#"{"type":"error","error":{"code":"rate_limit_exceeded"}}"#, .failed(.rateLimited))
        ]
        for (frame, expected) in cases {
            let event = try codec.decode(.text(frame), interactionID: interactionID)
            expect(event?.kind == expected, "server event maps to standard event")
        }
        let audio = try codec.decode(
            .text(#"{"type":"response.audio.delta","delta":"ECA=","sequence":9}"#),
            interactionID: interactionID
        )
        expect(
            audio?.kind == .outputAudio(
                NativeSpeechAudioPayload(
                    interactionID: interactionID,
                    sequenceNumber: 9,
                    bytes: Data([0x10, 0x20]),
                    format: .pcm16
                )
            ),
            "audio event decodes"
        )
        let unknown = try codec.decode(
            .text(#"{"type":"future.event"}"#),
            interactionID: interactionID
        )
        expect(unknown == nil, "unknown event is ignored")
        let audioDone = try codec.decode(
            .text(#"{"type":"response.audio.done"}"#),
            interactionID: interactionID
        )
        expect(audioDone == nil, "audio.done is not a terminal event")
        let tool = try codec.decode(
            .text(#"{"type":"response.function_call_arguments.done","call_id":"call-1","name":"weather","arguments":"{\"city\":\"北京\"}"}"#),
            interactionID: interactionID
        )
        expect(
            tool?.kind == .toolRequestCandidate(
                NativeSpeechToolRequest(
                    requestID: "call-1",
                    toolName: "weather",
                    arguments: Data(#"{"city":"北京"}"#.utf8)
                )
            ),
            "tool request is forwarded without execution"
        )
        let doneCases: [(String, NativeSpeechEventKind)] = [
            ("completed", .responseCompleted),
            ("cancelled", .cancelled(reason: "cancelled")),
            ("failed", .failed(.unavailable)),
            ("incomplete", .failed(.transportFailure))
        ]
        for (status, expected) in doneCases {
            let event = try codec.decode(
                .text(#"{"type":"response.done","response":{"status":"\#(status)"}}"#),
                interactionID: interactionID
            )
            expect(event?.kind == expected, "response.done maps canonical status")
        }
    }

    private static func testContinuousOutputAndResponseBoundary() async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.audio.delta","delta":"AQI="}"#),
            .text(#"{"type":"response.audio.delta","delta":"AwQ="}"#),
            .text(#"{"type":"response.audio.done"}"#),
            .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(credential: "test-token"),
            transport: transport
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let first = try await adapter.receive(
            interactionID: request.interaction.id
        )
        let second = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            first.kind == .outputAudio(
                NativeSpeechAudioPayload(
                    interactionID: request.interaction.id,
                    sequenceNumber: 0,
                    bytes: Data([1, 2]),
                    format: .pcm16
                )
            ),
            "first output chunk receives local sequence zero"
        )
        expect(
            second.kind == .outputAudio(
                NativeSpeechAudioPayload(
                    interactionID: request.interaction.id,
                    sequenceNumber: 1,
                    bytes: Data([3, 4]),
                    format: .pcm16
                )
            ),
            "second output chunk preserves bytes and order"
        )
        let firstBoundary = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            firstBoundary.kind == .responseCompleted,
            "response.done completes one response"
        )
        try await adapter.send(
            audio: NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 2,
                bytes: Data([5, 6]),
                format: .pcm16
            )
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio.delta","delta":"Bwg="}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.done","response":{"status":"completed"}}"#)
        )
        let third = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            third.kind == .outputAudio(
                NativeSpeechAudioPayload(
                    interactionID: request.interaction.id,
                    sequenceNumber: 2,
                    bytes: Data([7, 8]),
                    format: .pcm16
                )
            ),
            "second response reuses the interaction"
        )
        let secondBoundary = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            secondBoundary.kind == .responseCompleted,
            "second response completes without closing"
        )
        let callsBeforeClose = await transport.calls
        expect(
            callsBeforeClose.filter {
                if case .connect = $0 { return true }
                return false
            }.count == 1,
            "two responses reuse one connection"
        )
        expect(
            !callsBeforeClose.contains(.close(.normal)),
            "response completion keeps transport open"
        )
        try await adapter.close(interactionID: request.interaction.id)
        let callsAfterClose = await transport.calls
        expect(
            callsAfterClose.filter { $0 == .close(.normal) }.count == 1,
            "explicit close releases transport once"
        )
        let ignoredEventCount = await adapter.ignoredEventCount
        expect(
            ignoredEventCount == 1,
            "audio.done is consumed without ending the response"
        )
    }

    private static func testSinglePreconfigurationRetry() async throws {
        let transport = FakeRealtimeWebSocketTransport(
            frames: [
                .text(#"{"type":"session.created"}"#),
                .text(#"{"type":"session.updated"}"#)
            ],
            connectResults: [
                .failure(.transportFailure),
                .success(())
            ]
        )
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(credential: "test-token"),
            transport: transport,
            reconnectDelay: .zero
        )
        _ = try await start(adapter, request: makeRequest())
        let connectCount = await transport.calls.filter {
            if case .connect = $0 { return true }
            return false
        }.count
        expect(connectCount == 2, "preconfiguration failure retries once")
        let connectionState = await adapter.connectionState
        expect(
            connectionState == .configured,
            "retry reaches configured state"
        )
    }

    private static func testStreamingFailureDoesNotReconnect() async throws {
        let transport = FakeRealtimeWebSocketTransport(
            frames: [
                .text(#"{"type":"session.created"}"#),
                .text(#"{"type":"session.updated"}"#)
            ],
            receiveResults: [.failure(.transportFailure)]
        )
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(credential: "test-token"),
            transport: transport,
            reconnectDelay: .zero
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        try await adapter.send(
            audio: NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 1,
                bytes: Data([0, 0]),
                format: .pcm16
            )
        )
        do {
            _ = try await adapter.receive(
                interactionID: request.interaction.id
            )
            fatalError("FAILED: streaming receive failure must surface")
        } catch NativeSpeechError.transportFailure {
            checks += 1
        }
        let connectCount = await transport.calls.filter {
            if case .connect = $0 { return true }
            return false
        }.count
        expect(connectCount == 1, "streaming failure never reconnects")
    }

    private static func makeRequest() -> NativeSpeechStartRequest {
        let profile = NativeSpeechProviderProfile(
            profileID: "stage7_5_stepfun_realtime_primary",
            providerID: "StepFun",
            capability: "native_speech",
            adapterID: "stepfun_realtime",
            modelID: "stepaudio-2.5-realtime",
            voiceID: "linjiajiejie",
            endpoint: URL(string: "wss://api.stepfun.com/v1/realtime?model=stepaudio-2.5-realtime")!,
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
        let interaction = makeInteraction(profile: profile)
        return NativeSpeechStartRequest(
            interaction: interaction,
            profile: profile
        )
    }

    @discardableResult
    private static func start(
        _ adapter: StepFunRealtimeAdapter,
        request: NativeSpeechStartRequest
    ) async throws -> RealtimeSpeechContextProjection {
        let projection = contextProjection(
            interaction: request.interaction,
            instructions: "compiled resident instructions",
            version: "context-v1",
            reason: .interactionStarted
        )
        try await adapter.prepareContext(projection)
        try await adapter.start(request: request)
        return projection
    }

    private static func contextProjection(
        interaction: NativeSpeechInteraction,
        instructions: String,
        version: String,
        reason: RealtimeSpeechContextRefreshReason
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
            refreshReason: reason,
            compilationVersion: version
        )
    }

    private static func makeInteraction(
        profile: NativeSpeechProviderProfile
    ) -> NativeSpeechInteraction {
        NativeSpeechInteraction(
            residentID: "resident",
            sessionID: "session",
            providerProfileID: profile.profileID
        )
    }

    private static func json(_ text: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
