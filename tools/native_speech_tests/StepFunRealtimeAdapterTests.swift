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
        try await testCancelAfterCompletedResponseIsSafe()
        try await testNextResponseWinsCancellationRace()
        try await testCompletedResponseRejectsLateEvents()
        try await testCompletedResponseTombstonesStayBounded()
        try await testResumedSpeechSuppressesLateResponse()
        try await testCumulativeTranscriptNormalization()
        try await testResidentPhraseBoundariesTrackAudioWaterline()
        try await testLargeUnpunctuatedDeltaCreatesPhraseCheckpoints()
        try await testResidentSubtitleCadenceTracksAudioDuration()
        try await testResidentCheckpointBurstIsBounded()
        try await testResidentFinalFallsBackAtResponseBoundary()
        try await testLateUserFinalCorrelation()
        try await testSubtitleCorrelationGate()
        try await testResidentItemSwitchResetsSubtitleState()
        try await testCancelDropsQueuedSubtitle()
        try await testConversationItemUserFinal()
        try await testRecoverableTurnFailureKeepsConnection()
        try await testMissingCredentialDoesNotConnect()
        try testCodecMappings()
        testDiagnosticBufferRingOrdering()
        try await testRedactedWireDiagnostics()
        try await testContinuousOutputAndResponseBoundary()
        try await testSinglePreconfigurationRetry()
        try await testStreamingFailureDoesNotReconnect()
        print("stepfun_realtime_adapter_checks=\(checks)")
    }

    private static func testDiagnosticBufferRingOrdering() {
        let diagnostics = NativeSpeechDiagnosticBuffer(capacity: 3)
        for category in ["one", "two", "three", "four", "five"] {
            diagnostics.append(
                NativeSpeechInternalDiagnosticEvent(
                    source: .runtime,
                    category: category
                )
            )
        }
        let drained = diagnostics.drain()
        expect(
            drained.events.map(\.category) == ["three", "four", "five"],
            "diagnostic ring retains the newest events in order"
        )
        expect(
            drained.droppedEventCount == 2,
            "diagnostic ring reports overwritten events"
        )
        let empty = diagnostics.drain()
        expect(
            empty.events.isEmpty && empty.droppedEventCount == 0,
            "draining the diagnostic ring resets its counters"
        )
    }

    private static func testRecoverableTurnFailureKeepsConnection()
        async throws
    {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.created","response":{"id":"response-one"}}"#),
            .text(#"{"type":"response.audio_transcript.delta","response_id":"response-one","item_id":"failed-item","delta":"旧"}"#),
            .text(#"{"type":"response.audio_transcript.done","response_id":"response-one","item_id":"failed-item","transcript":"旧字幕"}"#),
            .text(#"{"type":"response.done","response":{"id":"response-one","status":"failed"}}"#),
            .text(#"{"type":"error","response_id":"response-one","error":{"code":"server_error"}}"#),
            .text(#"{"type":"response.created","response":{"id":"response-two"}}"#),
            .text(#"{"type":"response.done","response":{"id":"response-two","status":"completed"}}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(credential: "test-token"),
            transport: transport
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let firstResponse = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(firstResponse.kind == .thinking, "first response starts")
        let turnFailure = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            turnFailure.kind == .turnFailed(.unavailable),
            "failed response becomes one recoverable turn failure"
        )
        let stateAfterFailure = await adapter.connectionState
        expect(
            stateAfterFailure == .configured,
            "turn failure keeps the configured WebSocket"
        )
        let secondResponse = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            secondResponse.kind == .thinking,
            "turn failure drops deferred subtitle before the next response"
        )
        let secondCompletion = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            secondCompletion.kind == .responseCompleted,
            "same connection completes the next response"
        )
        let connectCount = await transport.calls.filter {
            if case .connect = $0 { return true }
            return false
        }.count
        expect(connectCount == 1, "recoverable turn failure does not reconnect")
        try await adapter.close(interactionID: request.interaction.id)
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

        await transport.enqueue(
            .text(#"{"type":"response.created"}"#)
        )
        let responseCreated = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(responseCreated.kind == .thinking, "response is active before cancel")
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

        await transport.enqueue(
            .text(#"{"type":"response.created"}"#)
        )
        let firstResponse = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(firstResponse.kind == .thinking, "first response is active")
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

    private static func testCancelAfterCompletedResponseIsSafe() async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.created"}"#),
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
        let created = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(created.kind == .thinking, "response.created marks response active")
        let completed = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            completed.kind == .responseCompleted,
            "response.done marks provider response inactive"
        )

        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )
        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )
        let callsAfterCompletedCancel = await transport.calls
        let completedCancelCount = try callsAfterCompletedCancel.filter { call in
            guard case .send(.text(let text)) = call else { return false }
            return try json(text)["type"] as? String == "response.cancel"
        }.count
        expect(
            completedCancelCount == 0,
            "cancel after response completion is a safe wire no-op"
        )
        let inactiveAcknowledgement = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            inactiveAcknowledgement.kind
                == .cancelled(reason: "interrupted"),
            "inactive response still acknowledges Runtime Interrupt"
        )

        await transport.enqueue(.text(#"{"type":"response.created"}"#))
        let nextResponse = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            nextResponse.kind == .thinking,
            "cancel no-op does not suppress the next response"
        )
        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )
        let activeCancelCalls = await transport.calls.compactMap { call -> String? in
            guard case .send(.text(let text)) = call,
                  let object = try? json(text),
                  object["type"] as? String == "response.cancel" else {
                return nil
            }
            return object["event_id"] as? String
        }
        expect(activeCancelCalls.count == 1, "active response sends one cancel")
        guard let cancellationEventID = activeCancelCalls.first else {
            fatalError("FAILED: response.cancel must carry event_id")
        }
        expect(
            cancellationEventID.hasPrefix("cancel-"),
            "cancel event ID is namespaced"
        )

        await transport.enqueue(.text(
            #"{"type":"error","error":{"code":"invalid_value","event_id":"\#(cancellationEventID)"}}"#
        ))
        let correlatedError = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            correlatedError.kind == .cancelled(reason: "interrupted"),
            "error correlated to response.cancel is absorbed as acknowledgement"
        )
        let state = await adapter.connectionState
        expect(state == .configured, "correlated cancel error keeps session alive")
        let callsBeforeClose = await transport.calls
        expect(
            callsBeforeClose.filter { $0 == .close(.normal) }.isEmpty,
            "correlated cancel error does not close transport"
        )

        await transport.enqueue(.text(#"{"type":"response.created"}"#))
        _ = try await adapter.receive(interactionID: request.interaction.id)
        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )
        let allCancellationEventIDs = await transport.calls.compactMap {
            call -> String? in
            guard case .send(.text(let text)) = call,
                  let object = try? json(text),
                  object["type"] as? String == "response.cancel" else {
                return nil
            }
            return object["event_id"] as? String
        }
        guard let secondCancellationEventID = allCancellationEventIDs.last else {
            fatalError("FAILED: second response.cancel must carry event_id")
        }
        await transport.enqueue(.text(
            #"{"type":"error","error":{"code":"rate_limit_exceeded","event_id":"\#(secondCancellationEventID)"}}"#
        ))
        let correlatedRateLimit = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            correlatedRateLimit.kind == .cancelled(reason: "interrupted"),
            "cancel-correlated Provider error is one cancellation acknowledgement"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testNextResponseWinsCancellationRace() async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"old"}}"#
        ))
        _ = try await adapter.receive(interactionID: request.interaction.id)
        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )

        await transport.enqueue(.text(
            #"{"type":"response.created","response":{"id":"new"}}"#
        ))
        let cancellationBoundary = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            cancellationBoundary.kind == .cancelled(reason: "interrupted"),
            "next response closes the pending cancellation boundary first"
        )
        let nextResponse = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            nextResponse.kind == .thinking,
            "next response remains available after cancellation boundary"
        )

        await transport.enqueue(.text(#"{"type":"response.cancelled"}"#))
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"old","status":"cancelled"}}"#
        ))
        await transport.enqueue(.text(
            #"{"event_id":"old-text","type":"response.audio_transcript.delta","response_id":"old","item_id":"old-item","delta":"旧"}"#
        ))
        await transport.enqueue(.text(
            #"{"event_id":"old-final","type":"response.audio_transcript.done","response_id":"old","item_id":"old-item","transcript":"旧字幕"}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.audio.delta","response_id":"old","delta":"CQo="}"#
        ))
        await transport.enqueue(.text(
            #"{"type":"response.done","response":{"id":"old","status":"incomplete"}}"#
        ))
        await transport.enqueue(.text(
            #"{"event_id":"new-text","type":"response.audio_transcript.delta","response_id":"new","item_id":"new-item","delta":"新的回答已经开始。"}"#
        ))
        await transport.enqueue(.text(
            #"{"event_id":"new-final","type":"response.audio_transcript.done","response_id":"new","item_id":"new-item","transcript":"新的回答已经开始。"}"#
        ))
        await transport.enqueue(subtitleAudioFrame(
            responseID: "new",
            itemID: "new-item",
            seed: 1,
            byteCount: 96_000
        ))
        let output = try await adapter.receive(
            interactionID: request.interaction.id
        )
        guard case .outputAudio = output.kind else {
            fatalError("FAILED: late cancellation ACK must not hide new audio")
        }
        let partial = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            partial.kind == .outputText(
                text: "新的回答已经开始。",
                isFinal: false
            ),
            "old transcript checkpoints cannot block the new response"
        )
        let state = await adapter.connectionState
        expect(
            state == .streaming,
            "old audio and terminal events cannot terminate the new response"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testCumulativeTranscriptNormalization() async throws {
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"input_audio_buffer.speech_started","item_id":"user-one"}"#),
            .text(#"{"event_id":"user-1","type":"conversation.item.input_audio_transcription.delta","item_id":"user-one","delta":"哈"}"#),
            .text(#"{"event_id":"user-2","type":"conversation.item.input_audio_transcription.delta","item_id":"user-one","delta":"哈"}"#),
            .text(#"{"event_id":"user-2","type":"conversation.item.input_audio_transcription.delta","item_id":"user-one","delta":"哈"}"#),
            .text(#"{"event_id":"user-3","type":"conversation.item.input_audio_transcription.delta","item_id":"user-one","delta":"海洋"}"#),
            .text(#"{"event_id":"user-4","type":"conversation.item.input_audio_transcription.completed","item_id":"user-one","transcript":"哈哈海洋"}"#),
            .text(#"{"type":"input_audio_buffer.speech_stopped","item_id":"user-one"}"#),
            .text(#"{"type":"response.created","response":{"id":"response-one"}}"#),
            .text(#"{"event_id":"resident-1","type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-one","delta":"上"}"#),
            .text(#"{"event_id":"resident-2","type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-one","delta":"海"}"#),
            .text(#"{"event_id":"resident-2","type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-one","delta":"海"}"#),
            .text(#"{"event_id":"resident-3","type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-one","delta":"海"}"#),
            .text(#"{"event_id":"resident-4","type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-one","delta":"洋，"}"#),
            .text(#"{"event_id":"resident-5","type":"response.audio_transcript.done","response_id":"response-one","item_id":"item-one","transcript":"上海海洋"}"#),
            subtitleAudioFrame(
                responseID: "response-one",
                itemID: "item-one",
                seed: 1
            ),
            subtitleAudioFrame(
                responseID: "response-one",
                itemID: "item-one",
                seed: 2
            ),
            subtitleAudioFrame(
                responseID: "response-one",
                itemID: "item-one",
                seed: 3
            ),
            subtitleAudioFrame(
                responseID: "response-one",
                itemID: "item-one",
                seed: 4
            ),
            .text(#"{"type":"response.audio.done","response_id":"response-one","item_id":"item-one"}"#),
            .text(#"{"type":"response.done","response":{"id":"response-one","status":"completed"}}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(
            interactionID: request.interaction.id
        )
        _ = try await adapter.receive(
            interactionID: request.interaction.id
        )

        let expected: [NativeSpeechEventKind] = [
            .inputSpeechStarted,
            .partialTranscript("哈"),
            .partialTranscript("哈哈"),
            .partialTranscript("哈哈海洋"),
            .finalTranscript("哈哈海洋"),
            .inputSpeechEnded,
            .thinking,
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 0,
                bytes: subtitleAudioBytes(seed: 1),
                format: .pcm16
            )),
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 1,
                bytes: subtitleAudioBytes(seed: 2),
                format: .pcm16
            )),
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 2,
                bytes: subtitleAudioBytes(seed: 3),
                format: .pcm16
            )),
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 3,
                bytes: subtitleAudioBytes(seed: 4),
                format: .pcm16
            )),
            .outputText(text: "上海海洋，", isFinal: false),
            .outputText(text: "上海海洋", isFinal: true),
            .responseCompleted
        ]
        for expectedKind in expected {
            let event = try await adapter.receive(
                interactionID: request.interaction.id
            )
            expect(
                event.kind == expectedKind,
                "Provider fragments preserve repeats and bind to audio"
            )
        }
        expect(
            diagnostics.drain().events.filter {
                $0.category == "duplicate_transcript_event_ignored"
            }.count == 2,
            "wire event identity removes duplicates without content guessing"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testCompletedResponseRejectsLateEvents()
        async throws
    {
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.created","response":{"id":"completed-response"}}"#),
            .text(#"{"type":"response.done","response":{"id":"completed-response","status":"completed"}}"#),
            .text(#"{"type":"response.created","response":{"id":"completed-response"}}"#),
            .text(#"{"event_id":"late-text","type":"response.audio_transcript.delta","response_id":"completed-response","item_id":"old-item","delta":"旧"}"#),
            .text(#"{"type":"response.audio.delta","response_id":"completed-response","item_id":"old-item","delta":"CQo="}"#),
            .text(#"{"type":"response.done","response":{"id":"completed-response","status":"incomplete"}}"#),
            .text(#"{"type":"response.created","response":{"id":"next-response"}}"#),
            .text(#"{"type":"response.audio.delta","response_id":"next-response","item_id":"next-item","delta":"AQI="}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let firstStart = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            firstStart.kind == .thinking,
            "completed-response fixture starts"
        )
        let firstCompletion = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            firstCompletion.kind == .responseCompleted,
            "completed response reaches one terminal boundary"
        )
        let nextStart = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            nextStart.kind == .thinking,
            "late completed-response events cannot hide the next response"
        )
        let nextAudio = try await adapter.receive(
            interactionID: request.interaction.id
        )
        guard case .outputAudio(let payload) = nextAudio.kind else {
            fatalError("FAILED: next response audio survives old events")
        }
        expect(
            payload.bytes == Data([1, 2]),
            "old completed-response audio cannot enter the new turn"
        )
        expect(
            diagnostics.drain().events.filter {
                $0.category == "stale_response_event_ignored"
            }.count >= 4,
            "completed response tombstone also rejects duplicate response.created"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testCompletedResponseTombstonesStayBounded()
        async throws
    {
        var frames: [RealtimeWebSocketFrame] = [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ]
        for index in 0 ..< 257 {
            frames.append(.text(
                #"{"type":"response.created","response":{"id":"bounded-\#(index)"}}"#
            ))
            frames.append(.text(
                #"{"type":"response.done","response":{"id":"bounded-\#(index)","status":"completed"}}"#
            ))
        }
        frames.append(.text(
            #"{"type":"response.created","response":{"id":"bounded-255"}}"#
        ))
        frames.append(.text(
            #"{"type":"response.audio.delta","response_id":"bounded-255","delta":"CQo="}"#
        ))
        frames.append(.text(
            #"{"type":"response.created","response":{"id":"bounded-valid"}}"#
        ))
        frames.append(.text(
            #"{"type":"response.audio.delta","response_id":"bounded-valid","delta":"AQI="}"#
        ))

        let transport = FakeRealtimeWebSocketTransport(frames: frames)
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        for index in 0 ..< 257 {
            let started = try await adapter.receive(
                interactionID: request.interaction.id
            )
            expect(
                started.kind == .thinking,
                "bounded tombstone response \(index) starts"
            )
            let completed = try await adapter.receive(
                interactionID: request.interaction.id
            )
            expect(
                completed.kind == .responseCompleted,
                "bounded tombstone response \(index) completes"
            )
        }
        let validStart = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            validStart.kind == .thinking,
            "bounded tombstones evict only the oldest response"
        )
        let validAudio = try await adapter.receive(
            interactionID: request.interaction.id
        )
        guard case .outputAudio(let payload) = validAudio.kind else {
            fatalError("FAILED: valid response follows bounded tombstones")
        }
        expect(
            payload.bytes == Data([1, 2]),
            "recent completed response cannot revive after tombstone rollover"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testResumedSpeechSuppressesLateResponse()
        async throws
    {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"input_audio_buffer.speech_started","item_id":"resumed-user"}"#),
            .text(#"{"type":"response.created","response":{"id":"stale-response"}}"#),
            .text(#"{"type":"response.audio.delta","response_id":"stale-response","delta":"CQo="}"#),
            .text(#"{"type":"response.done","response":{"id":"stale-response","status":"completed"}}"#),
            .text(#"{"type":"input_audio_buffer.speech_stopped","item_id":"resumed-user"}"#),
            .text(#"{"type":"response.created","response":{"id":"stale-response"}}"#),
            .text(#"{"type":"response.audio.delta","response_id":"stale-response","delta":"Cww="}"#),
            .text(#"{"type":"response.created","response":{"id":"valid-response"}}"#),
            .text(#"{"type":"response.audio.delta","response_id":"valid-response","delta":"AQI="}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let speechStarted = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            speechStarted.kind == .inputSpeechStarted,
            "resumed user speech remains active"
        )
        let speechEnded = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            speechEnded.kind == .inputSpeechEnded,
            "late response is suppressed until resumed speech ends"
        )
        let validStart = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            validStart.kind == .thinking,
            "same WebSocket accepts the legitimate next response"
        )
        let audio = try await adapter.receive(
            interactionID: request.interaction.id
        )
        guard case .outputAudio(let payload) = audio.kind else {
            fatalError("FAILED: valid response emits audio")
        }
        expect(
            payload.bytes == Data([1, 2]),
            "suppressed stale response cannot leak its audio"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testResidentCheckpointBurstIsBounded()
        async throws
    {
        let diagnostics = NativeSpeechDiagnosticBuffer(capacity: 4_096)
        var frames: [RealtimeWebSocketFrame] = [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.created","response":{"id":"burst-response"}}"#)
        ]
        for index in 0 ..< 1_560 {
            frames.append(.text(
                #"{"event_id":"burst-\#(index)","type":"response.audio_transcript.delta","response_id":"burst-response","item_id":"burst-item","delta":"哈"}"#
            ))
        }
        let finalText = String(repeating: "哈", count: 1_560)
        frames.append(.text(
            #"{"event_id":"burst-final","type":"response.audio_transcript.done","response_id":"burst-response","item_id":"burst-item","transcript":"\#(finalText)"}"#
        ))
        for index in 1 ... 30 {
            frames.append(subtitleAudioFrame(
                responseID: "burst-response",
                itemID: "burst-item",
                seed: UInt8(index)
            ))
        }
        frames.append(.text(
            #"{"type":"response.audio.done","response_id":"burst-response","item_id":"burst-item"}"#
        ))
        frames.append(.text(
            #"{"type":"response.done","response":{"id":"burst-response","status":"completed"}}"#
        ))

        let transport = FakeRealtimeWebSocketTransport(frames: frames)
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let responseStart = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            responseStart.kind == .thinking,
            "burst response starts"
        )

        var progressivePartials: [String] = []
        var audioSeen = 0
        var finalTextSeen: String?
        responseLoop: while true {
            let event = try await adapter.receive(
                interactionID: request.interaction.id
            )
            switch event.kind {
            case .outputAudio:
                audioSeen += 1
            case .outputText(let text, false):
                progressivePartials.append(text)
            case .outputText(let text, true):
                finalTextSeen = text
            case .responseCompleted:
                break responseLoop
            default:
                break
            }
        }
        expect(audioSeen == 30, "burst fixture preserves every audio block")
        expect(
            progressivePartials.map(\.count)
                == progressivePartials.map(\.count).sorted()
                && Set(progressivePartials.map(\.count)).count == 3,
            "bounded checkpoints advance monotonically across audio"
        )
        expect(
            progressivePartials.map(\.count) == [12, 24, 36],
            "checkpoint compaction preserves phrase-level progress"
        )
        expect(
            progressivePartials.allSatisfy { $0.count < finalText.count },
            "early audio never releases the complete final transcript"
        )
        expect(
            finalTextSeen == finalText,
            "burst final is emitted once at the audio boundary"
        )
        expect(
            diagnostics.drain().events.contains {
                $0.category == "resident_partial_checkpoints_compacted"
            },
            "early delta bursts stay bounded through deterministic compaction"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testResidentPhraseBoundariesTrackAudioWaterline()
        async throws
    {
        let responseID = "phrase-response"
        let itemID = "phrase-item"
        var frames: [RealtimeWebSocketFrame] = [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(
                #"{"type":"response.created","response":{"id":"phrase-response"}}"#
            ),
            .text(
                #"{"event_id":"phrase-1","type":"response.audio_transcript.delta","response_id":"phrase-response","item_id":"phrase-item","delta":"今天想吃顿好的，然后去逛逛。"}"#
            ),
            .text(
                #"{"event_id":"phrase-final","type":"response.audio_transcript.done","response_id":"phrase-response","item_id":"phrase-item","transcript":"今天想吃顿好的，然后去逛逛。"}"#
            )
        ]
        for seed in UInt8(1) ... UInt8(11) {
            frames.append(subtitleAudioFrame(
                responseID: responseID,
                itemID: itemID,
                seed: seed
            ))
        }
        frames.append(.text(
            #"{"type":"response.audio.done","response_id":"phrase-response","item_id":"phrase-item"}"#
        ))
        frames.append(.text(
            #"{"type":"response.done","response":{"id":"phrase-response","status":"completed"}}"#
        ))

        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: FakeRealtimeWebSocketTransport(frames: frames)
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)

        var audioSeen = 0
        var partials: [(audioCount: Int, text: String)] = []
        var final: String?
        responseLoop: while true {
            let event = try await adapter.receive(
                interactionID: request.interaction.id
            )
            switch event.kind {
            case .outputAudio:
                audioSeen += 1
            case .outputText(let text, false):
                partials.append((audioSeen, text))
            case .outputText(let text, true):
                final = text
            case .responseCompleted:
                break responseLoop
            default:
                break
            }
        }
        expect(
            partials.map { $0.text } == [
                "今天想吃顿好的，",
                "今天想吃顿好的，然后去逛逛。"
            ],
            "resident subtitles advance by Provider phrase boundaries"
        )
        expect(
            partials.map { $0.audioCount } == [6, 10],
            "phrases wait for their conservative PCM waterline"
        )
        expect(
            final == "今天想吃顿好的，然后去逛逛。",
            "phrase pacing preserves the Provider final"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testResidentSubtitleCadenceTracksAudioDuration()
        async throws
    {
        let scenarios = [
            (deltaCount: 29, audioCount: 42),
            (deltaCount: 50, audioCount: 91),
            (deltaCount: 43, audioCount: 79)
        ]
        for (scenarioIndex, scenario) in scenarios.enumerated() {
            let responseID = "cadence-response-\(scenarioIndex)"
            let itemID = "cadence-item-\(scenarioIndex)"
            var frames: [RealtimeWebSocketFrame] = [
                .text(#"{"type":"session.created"}"#),
                .text(#"{"type":"session.updated"}"#),
                .text(
                    #"{"type":"response.created","response":{"id":"\#(responseID)"}}"#
                )
            ]
            for index in 0 ..< scenario.deltaCount {
                frames.append(.text(
                    #"{"event_id":"cadence-\#(scenarioIndex)-\#(index)","type":"response.audio_transcript.delta","response_id":"\#(responseID)","item_id":"\#(itemID)","delta":"字"}"#
                ))
            }
            let finalText = String(
                repeating: "字",
                count: scenario.deltaCount
            )
            frames.append(.text(
                #"{"event_id":"cadence-final-\#(scenarioIndex)","type":"response.audio_transcript.done","response_id":"\#(responseID)","item_id":"\#(itemID)","transcript":"\#(finalText)"}"#
            ))
            for index in 0 ..< scenario.audioCount {
                frames.append(subtitleAudioFrame(
                    responseID: responseID,
                    itemID: itemID,
                    seed: UInt8(index % 251),
                    byteCount: 8_192
                ))
            }
            frames.append(.text(
                #"{"type":"response.audio.done","response_id":"\#(responseID)","item_id":"\#(itemID)"}"#
            ))
            frames.append(.text(
                #"{"type":"response.done","response":{"id":"\#(responseID)","status":"completed"}}"#
            ))

            let adapter = StepFunRealtimeAdapter(
                credentialReader: StaticCredentialReader(
                    credential: "test-token"
                ),
                transport: FakeRealtimeWebSocketTransport(frames: frames)
            )
            let request = makeRequest()
            _ = try await start(adapter, request: request)
            _ = try await adapter.receive(
                interactionID: request.interaction.id
            )
            _ = try await adapter.receive(
                interactionID: request.interaction.id
            )
            _ = try await adapter.receive(
                interactionID: request.interaction.id
            )

            var audioSeen = 0
            var partials: [(audioCount: Int, text: String)] = []
            var final: String?
            responseLoop: while true {
                let event = try await adapter.receive(
                    interactionID: request.interaction.id
                )
                switch event.kind {
                case .outputAudio:
                    audioSeen += 1
                case .outputText(let text, false):
                    partials.append((audioSeen, text))
                case .outputText(let text, true):
                    final = text
                case .responseCompleted:
                    break responseLoop
                default:
                    break
                }
            }
            expect(
                audioSeen == scenario.audioCount,
                "subtitle cadence preserves every Provider audio block"
            )
            let expectedCharacterCounts = stride(
                from: 12,
                through: scenario.deltaCount,
                by: 12
            ).filter {
                $0 * 12_000 <= scenario.audioCount * 8_192
            }
            let expectedAudioCounts = expectedCharacterCounts.map {
                ($0 * 12_000 + 8_191) / 8_192
            }
            expect(
                partials.map { $0.text.count } == expectedCharacterCounts,
                "character deltas collapse into bounded phrase checkpoints"
            )
            expect(
                partials.map { $0.audioCount } == expectedAudioCounts,
                "each phrase waits for its conservative PCM waterline"
            )
            expect(
                partials.allSatisfy { $0.text.count >= 12 },
                "single-character deltas never become visible checkpoints"
            )
            expect(
                final == finalText,
                "playback cadence never changes the Provider final"
            )
            try await adapter.close(
                interactionID: request.interaction.id
            )
        }
    }

    private static func testLargeUnpunctuatedDeltaCreatesPhraseCheckpoints()
        async throws
    {
        let text = String(repeating: "字", count: 30)
        let responseID = "large-delta-response"
        let itemID = "large-delta-item"
        var frames: [RealtimeWebSocketFrame] = [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(
                #"{"type":"response.created","response":{"id":"large-delta-response"}}"#
            ),
            .text(
                "{\"event_id\":\"large-delta\",\"type\":\"response.audio_transcript.delta\",\"response_id\":\"large-delta-response\",\"item_id\":\"large-delta-item\",\"delta\":\"\(text)\"}"
            ),
            .text(
                "{\"event_id\":\"large-delta-final\",\"type\":\"response.audio_transcript.done\",\"response_id\":\"large-delta-response\",\"item_id\":\"large-delta-item\",\"transcript\":\"\(text)\"}"
            )
        ]
        for seed in UInt8(1) ... UInt8(3) {
            frames.append(subtitleAudioFrame(
                responseID: responseID,
                itemID: itemID,
                seed: seed,
                byteCount: 96_000
            ))
        }
        frames.append(.text(
            #"{"type":"response.audio.done","response_id":"large-delta-response","item_id":"large-delta-item"}"#
        ))
        frames.append(.text(
            #"{"type":"response.done","response":{"id":"large-delta-response","status":"completed"}}"#
        ))

        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: FakeRealtimeWebSocketTransport(frames: frames)
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)

        var audioSeen = 0
        var partials: [(Int, String)] = []
        responseLoop: while true {
            let event = try await adapter.receive(
                interactionID: request.interaction.id
            )
            switch event.kind {
            case .outputAudio:
                audioSeen += 1
            case .outputText(let partial, false):
                partials.append((audioSeen, partial))
            case .responseCompleted:
                break responseLoop
            default:
                break
            }
        }
        expect(
            partials.map { $0.1.count } == [12, 24],
            "one large Provider delta still advances by phrase checkpoints"
        )
        expect(
            partials.map { $0.0 } == [2, 3],
            "large-delta checkpoints wait for conservative PCM watermarks"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testResidentFinalFallsBackAtResponseBoundary()
        async throws
    {
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.created","response":{"id":"fallback-response"}}"#),
            .text(#"{"type":"response.audio_transcript.delta","response_id":"fallback-response","item_id":"fallback-item","delta":"一二三四五六七八九十十一十二"}"#),
            .text(#"{"type":"response.audio_transcript.done","response_id":"fallback-response","item_id":"fallback-item","transcript":"一二三四五六七八九十十一十二"}"#),
            subtitleAudioFrame(
                responseID: "fallback-response",
                itemID: "fallback-item",
                seed: 1
            ),
            .text(#"{"type":"response.done","response":{"id":"fallback-response","status":"completed"}}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let expected: [NativeSpeechEventKind] = [
            .thinking,
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 0,
                bytes: subtitleAudioBytes(seed: 1),
                format: .pcm16
            )),
            .outputText(text: "一二三四五六七八九十十一十二", isFinal: true),
            .responseCompleted
        ]
        for expectedKind in expected {
            let event = try await adapter.receive(
                interactionID: request.interaction.id
            )
            expect(
                event.kind == expectedKind,
                "response boundary emits deferred final before completion"
            )
        }
        expect(
            diagnostics.drain().events.contains {
                $0.category == "resident_partial_checkpoints_discarded"
                    && $0.disposition == "response_completed:1"
            },
            "response boundary discards unreleased Provider checkpoints"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testConversationItemUserFinal() async throws {
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"conversation.item.created","item":{"id":"user-item","type":"message","role":"user","status":"completed","content":[{"type":"input_audio","transcript":"你好"}]}}"#),
            .text(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"你好"}"#),
            .text(#"{"type":"response.created"}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let userFinal = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            userFinal.kind == .finalTranscript("你好"),
            "conversation.item.created provides the user final"
        )
        let next = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            next.kind == .thinking,
            "dedicated duplicate final is absorbed"
        )
        expect(
            diagnostics.drain().events.contains {
                $0.category == "provider_user_partial_unavailable"
            },
            "missing Provider user partial is diagnosed without fabrication"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testLateUserFinalCorrelation() async throws {
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"input_audio_buffer.speech_started","item_id":"user-one"}"#),
            .text(#"{"type":"input_audio_buffer.speech_stopped","item_id":"user-one"}"#),
            .text(#"{"type":"response.created","response":{"id":"response-one"}}"#),
            .text(#"{"type":"response.audio.delta","response_id":"response-one","delta":"AQI="}"#),
            .text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"user-one","transcript":"第一轮完整输入"}"#),
            .text(#"{"type":"input_audio_buffer.speech_started","item_id":"user-two"}"#),
            .text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"user-one","transcript":"第一轮迟到重复"}"#),
            .text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"user-two","transcript":"第二轮完整输入"}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)

        let expected: [NativeSpeechEventKind] = [
            .inputSpeechStarted,
            .inputSpeechEnded,
            .thinking,
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 0,
                bytes: Data([1, 2]),
                format: .pcm16
            )),
            .finalTranscript("第一轮完整输入"),
            .inputSpeechStarted,
            .finalTranscript("第二轮完整输入")
        ]
        for expectedKind in expected {
            let event = try await adapter.receive(
                interactionID: request.interaction.id
            )
            expect(
                event.kind == expectedKind,
                "late user final keeps current item correlation"
            )
        }
        let events = diagnostics.drain().events
        expect(
            events.contains {
                $0.category == "stale_user_transcript_ignored"
                    && $0.disposition == "item_mismatch"
            },
            "old item final is absorbed before the current user final"
        )
        expect(
            events.contains {
                $0.category == "standard_user_final"
                    && $0.byteCount != nil
            },
            "user final diagnostics retain only a redacted byte count"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testSubtitleCorrelationGate() async throws {
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.created","response":{"id":"response-one"}}"#),
            .text(#"{"type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-one","delta":"旧的回答不应出现。"}"#),
            subtitleAudioFrame(
                responseID: "response-other",
                itemID: "item-other",
                seed: 1
            ),
            .text(#"{"type":"response.created","response":{"id":"response-two"}}"#),
            .text(#"{"type":"response.audio_transcript.delta","response_id":"response-two","item_id":"item-two","delta":"新的回答已经开始。"}"#),
            subtitleAudioFrame(
                responseID: "response-two",
                itemID: "item-two",
                seed: 2,
                byteCount: 96_000
            )
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)

        let expected: [NativeSpeechEventKind] = [
            .thinking,
            .thinking,
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: request.interaction.id,
                sequenceNumber: 0,
                bytes: subtitleAudioBytes(seed: 2, byteCount: 96_000),
                format: .pcm16
            )),
            .outputText(text: "新的回答已经开始。", isFinal: false)
        ]
        for expectedKind in expected {
            let event = try await adapter.receive(
                interactionID: request.interaction.id
            )
            expect(
                event.kind == expectedKind,
                "only a correlated response/item releases its latest partial"
            )
        }
        expect(
            diagnostics.drain().events.contains {
                $0.category == "stale_response_event_ignored"
                    && $0.disposition == "output_audio_delta"
            },
            "mismatched response audio is rejected before subtitle binding"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testCancelDropsQueuedSubtitle() async throws {
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.created","response":{"id":"response-one"}}"#),
            .text(#"{"type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-one","delta":"旧字幕仍在等待，"}"#),
            subtitleAudioFrame(
                responseID: "response-one",
                itemID: "item-one",
                seed: 1
            )
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let audio = try await adapter.receive(
            interactionID: request.interaction.id
        )
        if case .outputAudio = audio.kind {
            expect(true, "correlated audio is emitted before its partial")
        } else {
            expect(false, "correlated audio is emitted before its partial")
        }
        try await adapter.cancel(
            interactionID: request.interaction.id,
            reason: .interrupted
        )
        await transport.enqueue(
            .text(#"{"type":"response.cancelled"}"#)
        )
        let cancelled = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            cancelled.kind == .cancelled(reason: "interrupted"),
            "Interrupt drops a queued old-turn partial before acknowledgement"
        )
        await transport.enqueue(
            .text(#"{"type":"response.created","response":{"id":"response-two"}}"#)
        )
        await transport.enqueue(
            .text(#"{"type":"response.audio_transcript.delta","response_id":"response-two","item_id":"item-two","delta":"新字幕已经开始，"}"#)
        )
        await transport.enqueue(subtitleAudioFrame(
            responseID: "response-two",
            itemID: "item-two",
            seed: 2,
            byteCount: 96_000
        ))
        let nextStart = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(nextStart.kind == .thinking, "next response starts after cancel")
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let nextPartial = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            nextPartial.kind == .outputText(
                text: "新字幕已经开始，",
                isFinal: false
            ),
            "cancelled response cannot leak its queued subtitle"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testResidentItemSwitchResetsSubtitleState()
        async throws
    {
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.created","response":{"id":"response-one"}}"#),
            .text(#"{"event_id":"item-a-1","type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-a","delta":"旧的回答，"}"#),
            .text(#"{"event_id":"item-b-1","type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-b","delta":"新的回答，"}"#),
            .text(#"{"event_id":"item-a-late","type":"response.audio_transcript.delta","response_id":"response-one","item_id":"item-a","delta":"旧内容又来了。"}"#),
            subtitleAudioFrame(
                responseID: "response-one",
                itemID: "item-b",
                seed: 1,
                byteCount: 96_000
            )
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        _ = try await adapter.receive(interactionID: request.interaction.id)
        let start = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(start.kind == .thinking, "resident item fixture starts")
        let audio = try await adapter.receive(
            interactionID: request.interaction.id
        )
        guard case .outputAudio = audio.kind else {
            fatalError("FAILED: current resident item emits audio")
        }
        let partial = try await adapter.receive(
            interactionID: request.interaction.id
        )
        expect(
            partial.kind == .outputText(
                text: "新的回答，",
                isFinal: false
            ),
            "resident item switch cannot mix the previous item transcript"
        )
        expect(
            diagnostics.drain().events.contains {
                $0.category == "stale_resident_transcript_ignored"
                    && $0.disposition == "item_mismatch"
            },
            "late transcript from the previous resident item is rejected"
        )
        try await adapter.close(interactionID: request.interaction.id)
    }

    private static func testCodecMappings() throws {
        let codec = StepFunRealtimeCodec()
        let interactionID = NativeSpeechInteractionID()
        let cancelObject = try json(
            codec.responseCancel(eventID: "cancel-test")
        )
        expect(cancelObject["type"] as? String == "response.cancel", "cancel type")
        expect(cancelObject["event_id"] as? String == "cancel-test", "cancel event ID")
        let cases: [(String, NativeSpeechEventKind)] = [
            (#"{"type":"input_audio_buffer.speech_started"}"#, .inputSpeechStarted),
            (#"{"type":"input_audio_buffer.speech_stopped"}"#, .inputSpeechEnded),
            (#"{"type":"conversation.item.input_audio_transcription.delta","delta":"你"}"#, .partialTranscript("你")),
            (#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"你好"}"#, .finalTranscript("你好")),
            (#"{"type":"conversation.item.created","item":{"id":"user-item","type":"message","role":"user","status":"completed","content":[{"type":"input_audio","transcript":"你好"}]}}"#, .finalTranscript("你好")),
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
        let assistantItem = try codec.decode(
            .text(#"{"type":"conversation.item.created","item":{"type":"message","role":"assistant","content":[{"transcript":"private"}]}}"#),
            interactionID: interactionID
        )
        expect(assistantItem == nil, "assistant conversation items are ignored")
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
            ("failed", .turnFailed(.unavailable)),
            ("incomplete", .turnFailed(.unavailable))
        ]
        for (status, expected) in doneCases {
            let event = try codec.decode(
                .text(#"{"type":"response.done","response":{"status":"\#(status)"}}"#),
                interactionID: interactionID
            )
            expect(event?.kind == expected, "response.done maps canonical status")
        }
        let incomplete = try codec.decodeEnvelope(
            .text(#"{"type":"response.done","response":{"id":"response-one","status":"incomplete","status_details":{"reason":"turn_detected"}}}"#),
            interactionID: interactionID
        )
        expect(
            incomplete.responseStatus == .incomplete
                && incomplete.responseStatusDetailReason == .turnDetected
                && incomplete.event?.kind == .turnFailed(.cancelled),
            "turn-detected incomplete remains a recoverable overlap outcome"
        )
        let correlatedError = try codec.decodeEnvelope(
            .text(#"{"type":"error","event_id":"server-error","error":{"code":"invalid_value","event_id":"cancel-test"}}"#),
            interactionID: interactionID
        )
        expect(
            correlatedError.causedByEventID == "cancel-test",
            "error retains only the originating client event ID"
        )
        let audioTranscript = try codec.decodeEnvelope(
            .text(#"{"type":"response.audio_transcript.delta","delta":"语音"}"#),
            interactionID: interactionID
        )
        let textTranscript = try codec.decodeEnvelope(
            .text(#"{"type":"response.text.delta","delta":"文本"}"#),
            interactionID: interactionID
        )
        expect(
            audioTranscript.wireKind == .residentAudioTranscriptDelta,
            "audio transcript keeps a distinct wire kind"
        )
        expect(
            textTranscript.wireKind == .residentTextDelta,
            "text modality cannot masquerade as voice subtitle"
        )
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
            ignoredEventCount == 0,
            "audio.done closes only the subtitle projection boundary"
        )
    }

    private static func testRedactedWireDiagnostics() async throws {
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let transport = FakeRealtimeWebSocketTransport(frames: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"response.audio.delta","response_id":"response-secret-id","item_id":"item-secret-id","delta":"AQI="}"#)
        ])
        let adapter = StepFunRealtimeAdapter(
            credentialReader: StaticCredentialReader(
                credential: "test-token"
            ),
            transport: transport,
            diagnosticBuffer: diagnostics
        )
        let request = makeRequest()
        _ = try await start(adapter, request: request)
        _ = try await adapter.receive(
            interactionID: request.interaction.id
        )
        _ = try await adapter.receive(
            interactionID: request.interaction.id
        )
        _ = try await adapter.receive(
            interactionID: request.interaction.id
        )

        let events = diagnostics.drain().events
        let wireEvents = events.filter { $0.source == .wire }
        expect(
            wireEvents.map(\.wireSequence) == [1, 2, 3],
            "wire diagnostics preserve receive order"
        )
        expect(
            wireEvents.map(\.category) == [
                "session_created",
                "session_updated",
                "output_audio_delta"
            ],
            "wire diagnostics expose only whitelisted categories"
        )
        let audio = wireEvents.last
        expect(
            audio?.responseCorrelationHash != nil
                && audio?.responseCorrelationHash != "response-secret-id",
            "wire diagnostics hash response identity"
        )
        expect(
            audio?.itemCorrelationHash != nil
                && audio?.itemCorrelationHash != "item-secret-id",
            "wire diagnostics hash item identity"
        )
        expect(
            audio?.audioSequence == 0 && audio?.byteCount == 2,
            "wire diagnostics retain safe audio metadata"
        )
        expect(
            events.contains {
                $0.source == .adapter
                    && $0.category == "standard_output_audio"
                    && $0.wireSequence == 3
            },
            "standard event can be correlated to wire arrival"
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

    private static func subtitleAudioBytes(
        seed: UInt8,
        byteCount: Int = 14_400
    ) -> Data {
        Data(repeating: seed, count: byteCount)
    }

    private static func subtitleAudioFrame(
        responseID: String,
        itemID: String,
        seed: UInt8,
        byteCount: Int = 14_400
    ) -> RealtimeWebSocketFrame {
        let encoded = subtitleAudioBytes(
            seed: seed,
            byteCount: byteCount
        ).base64EncodedString()
        return .text(
            #"{"type":"response.audio.delta","response_id":"\#(responseID)","item_id":"\#(itemID)","delta":"\#(encoded)"}"#
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
