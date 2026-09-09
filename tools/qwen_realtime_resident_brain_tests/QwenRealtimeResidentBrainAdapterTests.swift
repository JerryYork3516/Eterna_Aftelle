import Foundation

nonisolated private final class R3ModelSelection: @unchecked Sendable {
    private let lock = NSLock()
    private var modelID = QwenRealtimeResidentBrainConfiguration.supportedModelID
    private var reads = 0

    func select(_ modelID: String) { lock.withLock { self.modelID = modelID } }
    var readCount: Int { lock.withLock { reads } }
    func configuration() -> QwenRealtimeResidentBrainConfiguration {
        lock.withLock {
            reads += 1
            return QwenRealtimeResidentBrainConfiguration(
                endpoint: URL(string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=\(modelID)")!,
                modelID: modelID,
                keyRef: "keychain://test/qwen",
                defaultProviderVoiceID: "R6FixtureVoice",
                acknowledgementTimeout: .seconds(1)
            )
        }
    }
}

private actor R3ResponseCatchBarrier {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private enum R3PendingAnswerCase: String, CaseIterable {
    case doneBeforeTimeout, doneBeforeCatch, lateDone, stop, expiry, speechPause, supersede, supersedeDuringWait, generation, context
    case identityCollision, identityCollisionAfterSubmission, inputRecovery, inputRecoveryFinal, inputRecoverySecondCollision
    case inputRecoveryChangedFinal, inputRecoveryStop, inputRecoveryOverflow, inputRecoveryTimeout
    case inputRecoveryStopDuringReconnect, inputRecoveryConcurrentReceive
    case inputRecoveryBeforeConfirmation, inputRecoveryDuringCancellation, inputRecoveryDuringAudioAppend
    case inputRecoveryStopDuringCancellation, inputRecoveryCancellationDeadline
    case expiryAfterSubmission, expiryDuringWrite, expiryBeforeSubmission
    case cancelledOperationDrain, cancelledStopDrain, cancelledContextDrain, cancelledContextGenerationDrain
}

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

private actor R3RealtimeEventRecorder {
    private var events: [RealtimeResidentBrainEvent] = []

    func append(_ event: RealtimeResidentBrainEvent) {
        events.append(event)
    }

    func snapshot() -> [RealtimeResidentBrainEvent] {
        events
    }
}

@MainActor
private final class R3OutputBridgeInterruptionCoordinator {
    let runtime: RuntimeCore
    let recorder: R3RealtimeEventRecorder
    var bridge: MacSpeechRealtimeBrainOutputBridge?
    private(set) var decision: RealtimeConfirmedInterruption?
    private(set) var nextIdentity: RealtimeBrainSessionIdentity?

    init(runtime: RuntimeCore, recorder: R3RealtimeEventRecorder) {
        self.runtime = runtime
        self.recorder = recorder
    }

    func consume(_ event: RealtimeResidentBrainEvent) async {
        await recorder.append(event)
        guard case .userSpeechStarted = event.kind,
              decision == nil,
              case .success(.confirmed(let confirmed)) = await runtime
                .claimRealtimeResidentBrainInterruptionDecision(for: event),
              let bridge else {
            if case .userTranscriptPartial = event.kind {
                try? await Task.sleep(for: .milliseconds(90))
            }
            return
        }
        decision = confirmed
        _ = await bridge.suspendForGenerationTransition(
            session: confirmed.interruptedIdentity
        )
        guard case .success(let rebound) = await runtime
            .completeRealtimeResidentBrainInterruption(confirmed) else {
            return
        }
        nextIdentity = rebound
        try? await Task.sleep(for: .milliseconds(500))
        _ = await bridge.resumeAfterGenerationTransition(session: rebound)
    }
}

@main
private struct QwenRealtimeResidentBrainAdapterTests {
    private static var checks = 0
    private static var cases = 0 {
        didSet {
            FileHandle.standardError.write(Data("qwen_case_started=\(cases)\n".utf8))
        }
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        try await testAssistantOutputIdentityOwnership()
        try await testPostStopCommittedItem()
        try await testPostStopCommittedItemFences()
        try await testUnidentifiedStopRecoversBoundTurn()
        try await testUnidentifiedStopRejectsUnboundEvidence()
        if let name = ProcessInfo.processInfo.environment["AFTELLE_PENDING_REVIEW_CASE"],
           let scenario = R3PendingAnswerCase(rawValue: name) {
            try await testRuntimeConfirmedInterruptionUserTurnHandoff(
                fixture: fixture, drainTimeout: true, pendingCase: scenario
            )
            print("pending_review_case=\(name) PASS checks=\(checks)")
            return
        }
        if ProcessInfo.processInfo.environment["AFTELLE_UNSENT_RACE_ONLY"] == "1" {
            try await testInterruptionAndGeneration(missingCancellationCompletion: true, drainTimeout: true, doneBeforeCatch: true)
            print("unsent_timeout_done_catch=PASS checks=\(checks)")
            return
        }
        if ProcessInfo.processInfo.environment["AFTELLE_PENDING_ANSWER_ONLY"] == "1" {
            try await testPendingAnswerMatrix(fixture: fixture)
            print("pending_answer_matrix=PASS cases=\(cases) checks=\(checks)")
            return
        }
        try await testInterruptionAndGeneration(missingCancellationCompletion: true, drainTimeout: true)
        try await testInterruptionAndGeneration(missingCancellationCompletion: true)
        try await testInterruptionAndGeneration(missingCancellationCompletion: true, unsolicitedDuringDrain: true)
        if ProcessInfo.processInfo.environment["AFTELLE_CANCEL_HANDOFF_ONLY"] == "1" {
            try await testRuntimeConfirmedInterruptionUserTurnHandoff(fixture: fixture, drainTimeout: true)
            try await testSubmittedResponseTimeoutIsTerminal()
            print("cancel_handoff_checks=\(checks) PASS")
            return
        }
        try await testPendingAnswerMatrix(fixture: fixture)
        try await testModelSelectionBetweenSessions()
        try await testHandshakeAndBootstrap()
        try await testProviderListeningInputAudioDiagnostics()
        try await testUnsafeTurnDetectionAcknowledgementFailsClosed()
        try await testInvalidToolAdvertisementsFailClosed()
        try await testContextScopeReplacement()
        try await testAudioAndEventMapping()
        try await testMissingTranscriptFinalRecovery()
        try await testTranscriptFinalFallbackDebounce()
        try await testTranscriptFinalFallbackLifecycleCancellation()
        try await testLateFinalKeepsExactProviderItemBinding()
        try await testBoundedUserItemReassociation()
        try await testBoundedUserItemReassociation(withProvisionalPreview: false)
        try await testResidentTextWireSourceCanonicalization()
        try await testGenerationGlobalOutputAudioClock()
        try await testInterruptionAndGeneration()
        try await testInterruptionAndGeneration(reassociateItem: true)
        try await testInterruptionAndGeneration(reassociateItem: true, withProvisionalPreview: false)
        try await testActiveResponseReceiveDiagnostics()
        try await testEmptySpeechStopIsNotCompletion()
        try await testPendingUserActivityRebindsAcrossContextRefresh()
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
        try await testRuntimeConfirmedInterruptionUserTurnHandoff(
            fixture: fixture
        )
        try await testRuntimeConfirmedInterruptionUserTurnHandoff(
            fixture: fixture, unidentifiedStop: true
        )
        try await testRuntimeConfirmedInterruptionUserTurnHandoff(
            fixture: fixture, unidentifiedStop: true, postStopCommittedItem: true
        )
        try await testRuntimeProviderTerminalPlaybackTailInterruptionHandoff(
            fixture: fixture
        )
        try await testRuntimeAcousticActivityAdmissionFence(fixture: fixture)
        try await testRuntimeAdmission(fixture: fixture)
        print("qwen_realtime_resident_brain_cases=\(cases)")
        print("qwen_realtime_resident_brain_checks=\(checks)")
        print("qwen_realtime_resident_brain_network_dependency=ZERO")
    }

    private static func testAssistantOutputIdentityOwnership() async throws {
        for defect in ["finalized_user", "wrong_role", "changed_item", "missing_identity"] {
            cases += 1
            let diagnostics = NativeSpeechDiagnosticBuffer()
            let stack = try makeStack(diagnosticBuffer: diagnostics)
            let identity = sessionIdentity(generation: 4)
            try await openAndBootstrap(stack, identity: identity)
            await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"user-B"}"#)
            let started = try await stack.adapter.receiveEvent(session: identity)
            await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"user-B","transcript":"user question B"}"#)
            let final = try await stack.adapter.receiveEvent(session: identity)
            expect(final.kind == .userTranscriptFinal("user question B")
                && final.identity.turnID == started.identity.turnID, "B has finalized user ownership")
            try await authorizeResponse(stack, from: final, responseID: "response-A")
            await stack.transport.enqueueText(#"{"type":"response.output_item.added","response_id":"response-A","output_index":0,"item":{"id":"assistant-A","type":"message","role":"assistant"}}"#)
            let itemID = defect == "finalized_user" ? "user-B" : defect == "changed_item" ? "assistant-C" : "assistant-A"
            let role = defect == "wrong_role" ? "user" : "assistant"
            let fields = defect == "missing_identity" ? "" : #""id":"\#(itemID)","role":"\#(role)","#
            await stack.transport.enqueueText(#"{"type":"response.done","response":{"id":"response-A","status":"completed","output":[{\#(fields)"type":"message","content":[{"type":"text","text":"must not become canonical"}]}]}}"#)
            await expectRealtimeError(.invalidEvent) {
                _ = try await stack.adapter.receiveEvent(session: identity)
            }
            expect(diagnostics.drain().events.contains {
                $0.category == "qwen_receive_failure"
                    && ($0.disposition ?? "").contains("branch=assistant_output_identity")
            }, "invalid output identity fails at the production ownership boundary")
            let sent = try await sentTypes(stack.transport)
            expect(sent.filter { $0 == "response.create" }.count == 1
                && !sent.contains("response.cancel"), "identity validation does not own interruption or authorize a second response")
            try? await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
        }
        print("assistant_output_identity_defects=4 PASS")
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 4)
        try await openAndBootstrap(stack, identity: identity)
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"user-B"}"#)
        let user = try await stack.adapter.receiveEvent(session: identity)
        try await authorizeResponse(stack, from: user, responseID: "response-A")
        await stack.transport.enqueueText(#"{"type":"response.output_item.added","response_id":"response-A","output_index":0,"item":{"id":"assistant-A","type":"message","role":"assistant"}}"#)
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"assistant-A"}"#)
        await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"assistant-A","transcript":"resident words relabeled as user"}"#)
        await stack.transport.enqueueText(#"{"type":"response.done","response":{"id":"response-A","status":"completed","output":[{"id":"assistant-A","type":"message","role":"assistant","content":[{"type":"text","text":"valid assistant answer"}]}]}}"#)
        let final = try await stack.adapter.receiveEvent(session: identity)
        expect(final.kind == .residentTextFinal("valid assistant answer"),
            "assistant item cannot acquire a user turn, proposal or transcript ownership")
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"assistant-A"}"#)
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"user-C"}"#)
        let next = try await stack.adapter.receiveEvent(session: identity)
        expect(next.kind == .userSpeechStarted && next.identity.turnID != user.identity.turnID,
            "retired assistant item cannot become a later user turn")
        try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
    }

    private static func testModelSelectionBetweenSessions() async throws {
        cases += 1
        let selection = R3ModelSelection()
        let transport = R3FakeRealtimeWebSocketTransport()
        let adapter = QwenRealtimeResidentBrainAdapter(
            credentialReader: try credentialReader(),
            transport: transport,
            configuration: selection.configuration(),
            configurationProvider: { selection.configuration() }
        )
        let models = [
            QwenRealtimeResidentBrainConfiguration.supportedModelID,
            QwenRealtimeResidentBrainConfiguration.flashModelID,
            QwenRealtimeResidentBrainConfiguration.supportedModelID
        ]
        for (index, model) in models.enumerated() {
            selection.select(model)
            let identity = sessionIdentity(generation: UInt64(index + 1))
            try await adapter.openSession(RealtimeBrainOpenSessionCommand(identity: identity))
            try await adapter.updateRuntimeContext(RealtimeBrainRuntimeContextUpdate(
                identity: identity, kind: .bootstrap, contextRevision: 1,
                sections: [RealtimeBrainContextSection(scope: .stableResident, content: "model fixture")]
            ))
            let ready = try await adapter.receiveEvent(session: identity)
            expect(ready.kind == .sessionReady, "selected model completes bootstrap")
            let endpoints = await transport.connectedEndpoints
            let queryModel = URLComponents(url: endpoints[index], resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "model" })?.value
            expect(queryModel == model, "next session uses selected model in actual transport URL")
            expect(endpoints.count == index + 1, "switching opens only one connection per session")
            let reads = selection.readCount
            selection.select("unsupported-model-fixture")
            await expectRealtimeError(.unavailable) {
                try await adapter.openSession(RealtimeBrainOpenSessionCommand(identity: identity))
            }
            expect(selection.readCount == reads, "active session never reloads changed configuration")
            try await adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
        }
        let count = await transport.connectedEndpoints.count
        await expectRealtimeError(.unavailable) {
            try await adapter.openSession(RealtimeBrainOpenSessionCommand(identity: sessionIdentity(generation: 4)))
        }
        let rejectedCount = await transport.connectedEndpoints.count
        expect(count == rejectedCount, "unsupported model fails before any connection")
        let objects = try await sentObjects(transport)
        expect(!objects.contains { $0["type"] as? String == "response.create" },
               "model selection cannot create a response")
        let closeCount = await transport.closeCount()
        expect(closeCount == 3, "all model sessions settle before reuse")
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
            turnDetection?["threshold"] as? Double == 0.2
                && turnDetection?["silence_duration_ms"] as? Int == 800,
            "Qwen semantic VAD keeps the pause window while admitting quieter speech"
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

    private static func testProviderListeningInputAudioDiagnostics()
        async throws {
        cases += 1
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let stack = try makeStack(diagnosticBuffer: diagnostics)
        let identity = sessionIdentity(generation: 23)
        try await openAndBootstrap(stack, identity: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"listening-diagnostic-turn"}"#
        )
        let speechStarted = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: speechStarted,
            responseID: "listening-diagnostic-response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"listening-diagnostic-response","status":"completed","output":[{"id":"fixture-output-449-0","role":"assistant","type":"message","content":[{"type":"text","text":"done"}]}]}}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        _ = diagnostics.drain()
        let frameBytes = pcm16(
            Array(repeating: [700, 700, 700], count: 160).flatMap { $0 }
        )
        diagnostics.appendRealtimeAudioCapsuleBatch(
            Data(repeating: 1, count: 3_200),
            identity: identity,
            audioSequence: 1
        )
        expect(
            diagnostics.realtimeAudioCapsuleSnapshot() == nil,
            "Qwen input PCM is not retained before explicit arming"
        )
        let capsuleAttemptID = UUID()
        let routeAttemptID = UUID()
        expect(diagnostics.armRealtimeAudioCapsule(
            attemptID: capsuleAttemptID,
            routeAttemptID: routeAttemptID,
            session: identity
        ), "an empty Qwen input PCM capsule arms once")
        expect(!diagnostics.armRealtimeAudioCapsule(
            attemptID: UUID(),
            routeAttemptID: UUID(),
            session: identity
        ), "an unexported Qwen input PCM capsule cannot be overwritten")
        diagnostics.appendRealtimeAudioCapsuleBatch(
            Data(repeating: 2, count: 3_200),
            identity: sessionIdentity(generation: identity.generation),
            audioSequence: 2
        )
        for index in 0 ..< 2 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 1),
                timestampNanoseconds: UInt64((index + 1) * 20_000_000),
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 24_000,
                    channelCount: 1
                ),
                provenance: .microphoneCapture,
                bytes: frameBytes
            ))
        }
        for index in 2 ..< 5 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 1),
                timestampNanoseconds: UInt64((index + 1) * 20_000_000),
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 24_000,
                    channelCount: 1
                ),
                provenance: .acousticEchoProcessed,
                bytes: frameBytes
            ))
        }
        expect(
            diagnostics.realtimeAudioCapsuleSnapshot()?.bytes.isEmpty == true,
            "capsule rejects another lease and a mixed-provenance batch"
        )
        for index in 5 ..< 10 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 1),
                timestampNanoseconds: UInt64((index + 1) * 20_000_000),
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 24_000,
                    channelCount: 1
                ),
                provenance: .acousticEchoProcessed,
                bytes: frameBytes
            ))
        }
        let events = diagnostics.drain().events
        guard let listeningBatch = events.last(where: {
            $0.category == "qwen_listening_input_audio_batch"
        }) else {
            fatalError("Provider-listening audio diagnostic missing")
        }
        expect(
            listeningBatch.byteCount == 3_200
                && listeningBatch.disposition == "transport_enqueued"
                && listeningBatch.turnGeneration == identity.generation
                && (listeningBatch.pcmPeak ?? 0) > 0
                && (listeningBatch.pcmRMS ?? 0) > 0,
            "Provider-listening diagnostics prove audible PCM enters transport"
        )
        expect(
            !events.contains {
                $0.category == "qwen_active_response_input_audio_batch"
            },
            "Provider-listening PCM is not mislabeled as active-response audio"
        )
        guard let capsule = diagnostics.realtimeAudioCapsuleSnapshot() else {
            fatalError("armed Qwen input PCM capsule missing")
        }
        expect(
            capsule.attemptID == capsuleAttemptID
                && capsule.routeAttemptID == routeAttemptID
                && capsule.brainLeaseID == identity.brainLeaseID
                && capsule.routeEpoch == identity.routeEpoch
                && capsule.firstGeneration == identity.generation
                && capsule.lastGeneration == identity.generation
                && capsule.firstBatchTerminalAudioSequence == 10
                && capsule.lastBatchTerminalAudioSequence == 10
                && capsule.bytes.count == 3_200
                && capsule.durationMilliseconds == 100
                && !capsule.isSealed,
            "capsule contains only the exact batch successfully sent to Qwen"
        )
        let sentAudioAppends = try await sentObjects(stack.transport).filter {
            $0["type"] as? String == "input_audio_buffer.append"
        }
        let lastTransportedBatch: Data?
        if let encodedBatch = sentAudioAppends.last?["audio"] as? String {
            lastTransportedBatch = Data(base64Encoded: encodedBatch)
        } else {
            lastTransportedBatch = nil
        }
        expect(
            sentAudioAppends.count == 2
                && lastTransportedBatch == capsule.bytes,
            "capsule bytes exactly match the successful Qwen audio batch"
        )
        diagnostics.clearRealtimeAudioCapsule(
            matchingAttemptID: capsuleAttemptID
        )
        let cappedAttemptID = UUID()
        expect(diagnostics.armRealtimeAudioCapsule(
            attemptID: cappedAttemptID,
            routeAttemptID: UUID(),
            session: identity
        ), "a cleared Qwen input PCM capsule can be armed again")
        diagnostics.appendRealtimeAudioCapsuleBatch(
            Data(repeating: 9, count: 3_200),
            identity: sessionIdentity(
                generation: identity.generation,
                leaseID: identity.brainLeaseID,
                routeEpoch: identity.routeEpoch + 1
            ),
            audioSequence: 1
        )
        expect(
            diagnostics.realtimeAudioCapsuleSnapshot()?.bytes.isEmpty == true,
            "capsule rejects another route epoch on the same brain lease"
        )
        let reboundIdentity = sessionIdentity(
            generation: identity.generation + 1,
            leaseID: identity.brainLeaseID,
            routeEpoch: identity.routeEpoch
        )
        for sequence in 1 ... 101 {
            diagnostics.appendRealtimeAudioCapsuleBatch(
                Data(repeating: UInt8(sequence), count: 3_200),
                identity: sequence == 1 ? identity : reboundIdentity,
                audioSequence: UInt64(sequence)
            )
        }
        guard let cappedCapsule = diagnostics
            .realtimeAudioCapsuleSnapshot() else {
            fatalError("bounded Qwen input PCM capsule missing")
        }
        expect(
            cappedCapsule.bytes.count == 320_000
                && cappedCapsule.durationMilliseconds == 10_000
                && cappedCapsule.firstGeneration == identity.generation
                && cappedCapsule.lastGeneration
                    == reboundIdentity.generation
                && cappedCapsule.lastBatchTerminalAudioSequence == 100
                && cappedCapsule.isSealed,
            "capsule spans N to N+1 and seals at exactly ten seconds"
        )
        diagnostics.clearRealtimeAudioCapsule(
            matchingAttemptID: cappedAttemptID
        )
        expect(
            diagnostics.realtimeAudioCapsuleSnapshot() == nil,
            "capsule export cleanup is attempt-bound and exactly once"
        )
        let failedAttemptID = UUID()
        expect(diagnostics.armRealtimeAudioCapsule(
            attemptID: failedAttemptID,
            routeAttemptID: routeAttemptID,
            session: identity
        ), "send-failure PCM capsule fixture arms")
        for index in 10 ..< 14 {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: UInt64(index + 1),
                timestampNanoseconds: UInt64((index + 1) * 20_000_000),
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 24_000,
                    channelCount: 1
                ),
                provenance: .acousticEchoProcessed,
                bytes: frameBytes
            ))
        }
        await stack.transport.failNextAudioAppend()
        await expectRealtimeError(.transportFailure) {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity,
                sequence: 15,
                timestampNanoseconds: 300_000_000,
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 24_000,
                    channelCount: 1
                ),
                provenance: .acousticEchoProcessed,
                bytes: frameBytes
            ))
        }
        expect(
            diagnostics.realtimeAudioCapsuleSnapshot()?.bytes.isEmpty == true,
            "a failed Qwen transport send cannot enter the PCM capsule"
        )
        diagnostics.clearRealtimeAudioCapsule(
            matchingAttemptID: failedAttemptID
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
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
            #"{"type":"response.done","response":{"id":"response-1","status":"completed","output":[{"id":"fixture-output-1055-0","role":"assistant","type":"message","content":[{"type":"audio","transcript":"你好呀"}]}]}}"#
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

    private static func testMissingTranscriptFinalRecovery() async throws {
        cases += 1
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let stack = try makeStack(diagnosticBuffer: diagnostics)
        let identity = sessionIdentity(generation: 18)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"missing-final-user"}"#
        )
        let started = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"missing-final-user","text":"停，等一下","stash":""}"#
        )
        let partial = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"missing-final-user"}"#
        )
        let stopped = try await stack.adapter.receiveEvent(session: identity)
        let recovered = try await stack.adapter.receiveEvent(session: identity)
        expect(
            started.kind == .userSpeechStarted
                && partial.kind == .userTranscriptPartial("停，等一下")
                && stopped.kind == .userSpeechStopped
                && recovered.kind == .userTranscriptFinal("停，等一下"),
            "speech stopped recovers one missing final from the latest partial"
        )
        let recoveryDiagnostics = diagnostics.drain().events
        expect(
            recoveryDiagnostics.contains {
                $0.category
                    == "qwen_transcript_final_recovered_from_partial"
            },
            "missing-final recovery is visible without logging transcript text"
        )

        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.failed","item_id":"missing-final-user","error":{"code":"late_asr_failure"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"missing-final-user","transcript":"停，等一下，我还有话"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"after-late-final"}"#
        )
        let afterLateFinal = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            afterLateFinal.kind == .userSpeechStarted,
            "late Provider final cannot duplicate the recovered final"
        )

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"after-late-final"}"#
        )
        let noPartialStop = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            noPartialStop.kind == .userSpeechStopped,
            "speech without a partial still keeps its lifecycle"
        )
        try? await Task.sleep(for: .milliseconds(650))
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"after-empty-fallback"}"#
        )
        let afterEmptyFallback = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            afterEmptyFallback.kind == .userSpeechStarted,
            "missing-final recovery never fabricates an empty transcript"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testTranscriptFinalFallbackDebounce() async throws {
        cases += 1
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let stack = try makeStack(diagnosticBuffer: diagnostics)
        let identity = sessionIdentity(generation: 19)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"progressive-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"progressive-user","text":"找点乐子","stash":""}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"progressive-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        try? await Task.sleep(for: .milliseconds(300))
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"progressive-user","text":"找点乐子是什么","stash":""}"#
        )
        let progressivePartial = try await stack.adapter.receiveEvent(
            session: identity
        )
        let progressiveFinalTask = Task {
            try await stack.adapter.receiveEvent(session: identity)
        }
        await waitUntilPendingReceive(stack.adapter, session: identity)
        try? await Task.sleep(for: .milliseconds(250))
        let fallbackStillPending = await stack.adapter
            .hasPendingEventWaiterForTesting(session: identity)
        expect(
            fallbackStillPending,
            "a later partial restarts the stopped-turn fallback window"
        )
        let progressiveFinal = try await progressiveFinalTask.value
        expect(
            progressivePartial.kind
                == .userTranscriptPartial("找点乐子是什么")
                && progressiveFinal.kind
                    == .userTranscriptFinal("找点乐子是什么"),
            "fallback commits the latest stable partial instead of an earlier preview"
        )

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"late-partial-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"late-partial-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        try? await Task.sleep(for: .milliseconds(650))
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"late-partial-user","text":"稍晚到达的内容","stash":""}"#
        )
        let latePartial = try await stack.adapter.receiveEvent(
            session: identity
        )
        let latePartialFinal = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            latePartial.kind == .userTranscriptPartial("稍晚到达的内容")
                && latePartialFinal.kind
                    == .userTranscriptFinal("稍晚到达的内容"),
            "a first partial arriving after the original deadline gets its own fallback window"
        )

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"provider-final-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"provider-final-user","text":"未完成","stash":""}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"provider-final-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        try? await Task.sleep(for: .milliseconds(100))
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"provider-final-user","transcript":"Provider 完整文本"}"#
        )
        let providerFinal = try await stack.adapter.receiveEvent(
            session: identity
        )
        try? await Task.sleep(for: .milliseconds(550))
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"after-provider-final"}"#
        )
        let afterProviderFinal = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            providerFinal.kind == .userTranscriptFinal("Provider 完整文本")
                && afterProviderFinal.kind == .userSpeechStarted,
            "a timely Provider final cancels fallback without a duplicate"
        )
        let recoveryCount = diagnostics.drain().events.filter {
            $0.category == "qwen_transcript_final_recovered_from_partial"
        }.count
        expect(
            recoveryCount == 2,
            "only the two genuinely missing finals use fallback recovery"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testTranscriptFinalFallbackLifecycleCancellation()
        async throws {
        cases += 1
        let stack = try makeStack()
        let initial = sessionIdentity(generation: 20)
        try await openAndBootstrap(stack, identity: initial)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"close-old-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: initial)
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"close-old-user","text":"旧会话","stash":""}"#
        )
        _ = try await stack.adapter.receiveEvent(session: initial)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"close-old-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: initial)
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: initial)
        )

        let reopened = sessionIdentity(generation: 1)
        try await openAndBootstrap(stack, identity: reopened)
        try? await Task.sleep(for: .milliseconds(650))
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"reopened-user"}"#
        )
        let reopenedSpeech = try await stack.adapter.receiveEvent(
            session: reopened
        )
        expect(
            reopenedSpeech.kind == .userSpeechStarted,
            "close and reopen cannot resurrect an old fallback final"
        )

        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"reopened-user","text":"旧 generation","stash":""}"#
        )
        _ = try await stack.adapter.receiveEvent(session: reopened)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"reopened-user"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: reopened)
        let next = sessionIdentity(
            generation: 2,
            leaseID: reopened.brainLeaseID,
            routeEpoch: reopened.routeEpoch
        )
        try await stack.adapter.cancelGeneration(
            RealtimeBrainCancelGenerationCommand(
                identity: reopened,
                nextGeneration: next.generation,
                reason: .runtimeDecision
            )
        )
        let cancelled = try await stack.adapter.receiveEvent(session: next)
        try? await Task.sleep(for: .milliseconds(650))
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"next-generation-user"}"#
        )
        let nextSpeech = try await stack.adapter.receiveEvent(session: next)
        expect(
            cancelled.kind == .cancelled(.runtimeDecision)
                && nextSpeech.kind == .userSpeechStarted,
            "generation reset cancels the old fallback without touching N+1"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: next)
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
            #"{"type":"response.done","response":{"id":"audio-response-1","status":"completed","output":[{"id":"fixture-output-1395-0","role":"assistant","type":"message","content":[{"type":"audio","transcript":"first"}]}]}}"#
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

    private static func testLateFinalKeepsExactProviderItemBinding()
        async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 33)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"late-final-a"}"#
        )
        let startA = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"late-final-a"}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"late-final-b"}"#
        )
        let startB = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"late-final-a","transcript":"第一句"}"#
        )
        let finalA = try await stack.adapter.receiveEvent(session: identity)

        expect(
            startA.identity.turnID != startB.identity.turnID
                && finalA.kind == .userTranscriptFinal("第一句")
                && finalA.identity.turnID == startA.identity.turnID,
            "a late final remains bound to its exact Provider item"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testBoundedUserItemReassociation(withProvisionalPreview: Bool = true) async throws {
        let scenarios: [(String, String, String, [String], Bool)] = [
            ("bounded", ",\"audio_start_ms\":1000", ",\"audio_end_ms\":1800", ["new"], true),
            ("missing-start", "", ",\"audio_end_ms\":1800", ["new"], false),
            ("missing-end", ",\"audio_start_ms\":1000", "", ["new"], false),
            ("old-end", ",\"audio_start_ms\":2000", ",\"audio_end_ms\":1800", ["new"], false),
            ("boolean-end", ",\"audio_start_ms\":0", ",\"audio_end_ms\":true", ["new"], false),
            ("fractional-end", ",\"audio_start_ms\":1000", ",\"audio_end_ms\":1800.5", ["new"], false),
            ("ambiguous", ",\"audio_start_ms\":1000", ",\"audio_end_ms\":1800", ["new", "other"], false),
            ("unseen-final", ",\"audio_start_ms\":1000", ",\"audio_end_ms\":1800", [], false),
            ("no-start-event", ",\"audio_start_ms\":1000", ",\"audio_end_ms\":1800", ["new"], false),
            ("no-stop-event", ",\"audio_start_ms\":1000", ",\"audio_end_ms\":1800", ["new"], false),
            ("completed-item", ",\"audio_start_ms\":1000", ",\"audio_end_ms\":1800", ["new"], false),
            ("retired-generation-item", ",\"audio_start_ms\":1000", ",\"audio_end_ms\":1800", ["new"], false)
        ]
        for (name, startTime, stopTime, candidates, accepts) in scenarios {
            cases += 1
            let stack = try makeStack()
            var identity = sessionIdentity(generation: 90)
            try await openAndBootstrap(stack, identity: identity)
            if name == "completed-item" || name == "retired-generation-item" {
                await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"new"}"#)
                _ = try await stack.adapter.receiveEvent(session: identity)
                if name == "completed-item" {
                    await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"new"}"#)
                    _ = try await stack.adapter.receiveEvent(session: identity)
                    await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"new","transcript":"already completed"}"#)
                    _ = try await stack.adapter.receiveEvent(session: identity)
                } else {
                    await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"carried-user"}"#)
                    _ = try await stack.adapter.receiveEvent(session: identity)
                    let next = sessionIdentity(generation: 91, leaseID: identity.brainLeaseID, routeEpoch: identity.routeEpoch)
                    try await stack.adapter.interrupt(RealtimeBrainInterruptCommand(
                        identity: identity, nextGeneration: next.generation, reason: .runtimeDecision
                    ))
                    identity = next
                    _ = try await stack.adapter.receiveEvent(session: identity)
                    let connections = await stack.transport.connectCount()
                    expect(connections == 1, "retired item test stays on the original socket")
                }
            }
            var start: RealtimeResidentBrainEvent?
            if name != "no-start-event" {
                await stack.transport.enqueueText(
                    "{\"type\":\"input_audio_buffer.speech_started\",\"item_id\":\"original\"\(startTime)}"
                )
                start = try await stack.adapter.receiveEvent(session: identity)
                if withProvisionalPreview {
                    await stack.transport.enqueueText(
                        #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"original","text":"","stash":"先停一下"}"#
                    )
                    _ = try await stack.adapter.receiveEvent(session: identity)
                }
            }
            for candidate in candidates {
                await stack.transport.enqueueText(
                    "{\"type\":\"conversation.item.input_audio_transcription.delta\",\"item_id\":\"\(candidate)\",\"text\":\"\",\"stash\":\"先停一下我想问第二点\"}"
                )
            }
            if name != "no-stop-event" {
                await stack.transport.enqueueText(
                    "{\"type\":\"input_audio_buffer.speech_stopped\",\"item_id\":\"new\"\(stopTime)}"
                )
            }
            for item in ["new", "new", "original"] {
                await stack.transport.enqueueText(
                    "{\"type\":\"conversation.item.input_audio_transcription.completed\",\"item_id\":\"\(item)\",\"transcript\":\"\(item) final\"}"
                )
            }
            await stack.transport.enqueueText(
                #"{"type":"input_audio_buffer.speech_started","item_id":"sentinel"}"#
            )
            var finals: [RealtimeResidentBrainEvent] = []
            while true {
                let event = try await stack.adapter.receiveEvent(session: identity)
                if case .userSpeechStarted = event.kind { break }
                if case .userTranscriptFinal = event.kind { finals.append(event) }
            }
            let label = "\(name), provisional-preview=\(withProvisionalPreview)"
            expect(finals.count == (start == nil ? 0 : 1), "\(label): no extra or unbound final")
            let expected: RealtimeResidentBrainEventKind? = start == nil ? nil
                : .userTranscriptFinal(accepts ? "new final" : "original final")
            expect(finals.first?.kind == expected, "\(label): only bounded ID reassociation is accepted")
            expect(finals.first?.identity == start?.identity, "\(label): same Runtime turn and generation")
            try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
        }
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

    private static func testInterruptionAndGeneration(reassociateItem: Bool = false, withProvisionalPreview: Bool = true, missingCancellationCompletion: Bool = false, unsolicitedDuringDrain: Bool = false, drainTimeout: Bool = false, doneBeforeCatch: Bool = false) async throws {
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
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-b","audio_start_ms":1000}"#
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
        await stack.transport.holdResponseCancellationAcknowledgements()
        let interruptTask = Task {
            try await stack.adapter.interrupt(RealtimeBrainInterruptCommand(
                identity: identity,
                nextGeneration: nextIdentity.generation,
                reason: .runtimeDecision
            ))
        }
        try await waitUntilSentTypeCount(
            stack.transport,
            type: "response.cancel",
            minimum: 1
        )
        if missingCancellationCompletion {
            // Qwen-Omni need not send response.done as a cancel acknowledgement.
            // Input must rebound before any remote completion arrives.
            try await interruptTask.value
            print("cancel_handoff_without_response_done=PASS")
        }
        // An unidentifiable stop must not end the preserved utterance during cancel ACK.
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"","audio_end_ms":10220}"#
        )
        if withProvisionalPreview {
            await stack.transport.enqueueText(
                #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"user-b","text":"停一下","stash":""}"#
            )
        }
        let endingItemID = reassociateItem ? "user-b-committed" : "user-b"
        if reassociateItem {
            await stack.transport.enqueueText(
                #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"user-b-committed","text":"停一下","stash":""}"#
            )
        }
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"\#(endingItemID)","audio_end_ms":1800}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"\#(endingItemID)","transcript":"停一下"}"#
        )
        if !missingCancellationCompletion {
            await stack.transport.releaseResponseCancellationAcknowledgements()
        }
        try await interruptTask.value
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
            !sent.contains { $0["type"] as? String == "input_audio_buffer.clear" },
            "Runtime interrupt preserves the admitted user utterance"
        )

        var reboundEvents: [RealtimeResidentBrainEvent] = []
        while reboundEvents.count < 4 {
            let event = try await stack.adapter.receiveEvent(session: nextIdentity)
            reboundEvents.append(event)
            if case .userTranscriptFinal = event.kind { break }
        }
        guard let reboundSpeech = reboundEvents.first,
              let reboundFinal = reboundEvents.last else {
            fatalError("rebound input events missing")
        }
        // Reassociation after rebound may have only a final, not a bound partial.
        let expectedInputKinds: [RealtimeResidentBrainEventKind] =
            reboundEvents.count == 3 && reassociateItem && !withProvisionalPreview
            ? [.userSpeechStarted, .userSpeechStopped, .userTranscriptFinal("停一下")]
            : [.userSpeechStarted, .userTranscriptPartial("停一下"),
               .userSpeechStopped, .userTranscriptFinal("停一下")]
        expect(
            reboundEvents.map(\.kind) == expectedInputKinds,
            "the exact interrupting user item resumes in Provider order"
        )
        expect(
            reboundEvents.allSatisfy {
                $0.identity.session == nextIdentity
                    && $0.identity.turnID == reboundSpeech.identity.turnID
            },
            "the interrupting user item is rebound only to N+1"
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
        let carriedSamples = pcm16Samples(newAudio)
        expect(
            carriedSamples.prefix(1_280).allSatisfy { $0 == 300 }
                && carriedSamples.suffix(320).allSatisfy { $0 == 900 },
            "the bounded pending PCM stays continuous across interruption"
        )

        let catchBarrier = R3ResponseCatchBarrier()
        if doneBeforeCatch {
            await stack.adapter.setResponseCatchBarrierForTesting { await catchBarrier.suspend() }
        }
        let reboundCommand = RealtimeBrainCreateResponseCommand(
            identity: reboundFinal.identity, sourceEventSequence: reboundFinal.sequence
        )
        await stack.transport.useNextResponseID("response-barge-in")
        let reboundResponse = Task {
            do {
                try await stack.adapter.createResponse(reboundCommand)
            } catch let failure as RealtimeBrainResponseAttemptFailure
                where !drainTimeout && failure.submission == .notSubmitted
                    && reboundCommand.attempt.snapshot().providerReady {
                // Adapter fixture explicitly grants a new attempt; production uses Runtime's gate.
                try await stack.adapter.createResponse(RealtimeBrainCreateResponseCommand(
                    identity: reboundFinal.identity, sourceEventSequence: reboundFinal.sequence
                ))
            }
        }
        if missingCancellationCompletion {
            for _ in 0 ..< 10_000 {
                if await stack.adapter.isWaitingForResponseDoneForTesting(
                    "response-interrupt", session: nextIdentity
                ) { break }
                await Task.yield()
            }
            let waiting = await stack.adapter.isWaitingForResponseDoneForTesting(
                "response-interrupt", session: nextIdentity
            )
            expect(waiting, "only new response creation waits for retired wire completion")
            let beforeDrain = try await sentTypes(stack.transport)
            expect(beforeDrain.filter { $0 == "response.create" }.count == 1,
                   "no new response.create while the old wire response is still draining")
            if unsolicitedDuringDrain {
                await stack.transport.enqueueText(
                    #"{"type":"response.created","response":{"id":"unrequested-during-drain","status":"in_progress"}}"#
                )
                await expectRealtimeError(.invalidEvent) {
                    try await reboundResponse.value
                }
                try await stack.adapter.closeSession(
                    RealtimeBrainCloseSessionCommand(identity: nextIdentity)
                )
                return
            }
            for _ in 0 ..< 20 {
                await stack.transport.enqueueText(
                    #"{"type":"response.audio.delta","response_id":"response-interrupt","delta":"AAA="}"#
                )
                await stack.transport.enqueueText(
                    #"{"type":"response.audio_transcript.delta","response_id":"response-interrupt","delta":"stale"}"#
                )
            }
            if drainTimeout {
                if doneBeforeCatch {
                    await catchBarrier.waitForEntry()
                    await stack.transport.releaseResponseCancellationAcknowledgements()
                    for _ in 0 ..< 10_000 {
                        if !(await stack.adapter.hasRetiringResponseForTesting()) { break }
                        await Task.yield()
                    }
                    let stillRetiring = await stack.adapter.hasRetiringResponseForTesting()
                    expect(!stillRetiring, "old done is consumed after timeout but before catch")
                    await stack.adapter.setResponseCatchBarrierForTesting(nil)
                    await catchBarrier.release()
                    FileHandle.standardError.write(Data("counterexample_order=timer_fired,old_done_consumed,catch_released\n".utf8))
                }
                do {
                    try await reboundResponse.value
                    fatalError("the original waiting attempt must return its not-submitted receipt")
                } catch let failure as RealtimeBrainResponseAttemptFailure {
                    expect(failure.attemptID == reboundCommand.attempt.id
                        && failure.submission == .notSubmitted
                        && failure.reason == .retiredResponseWait && failure.error == .timedOut,
                        "timeout belongs to the original unsubmitted attempt even when old done beats catch")
                }
                let terminalFailure = await stack.adapter.terminalErrorForTesting(session: nextIdentity)
                expect(terminalFailure == nil, "late old done cannot turn an unsubmitted timeout into terminal failure")
                let afterTimeout = try await sentTypes(stack.transport)
                expect(afterTimeout.filter { $0 == "response.create" }.count == 1,
                       "timed-out drain never submits or retries response.create")
                for index in 0 ..< 5 {
                    try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                        identity: nextIdentity, sequence: UInt64(index + 6),
                        timestampNanoseconds: UInt64(index + 20) * 100,
                        format: newAudioFrame.format, provenance: newAudioFrame.provenance,
                        bytes: newAudioFrame.bytes
                    ))
                }
                let afterInput = try await sentTypes(stack.transport)
                expect(afterInput.filter { $0 == "input_audio_buffer.append" }.count == 3,
                       "input keeps flowing in the same generation while retired response remains unresolved")
                await stack.transport.releaseResponseCancellationAcknowledgements()
                await stack.transport.enqueueText(
                    #"{"type":"response.audio.delta","response_id":"response-interrupt","delta":"AAA="}"#
                )
                await stack.transport.enqueueText(
                    #"{"type":"input_audio_buffer.speech_started","item_id":"after-timeout-user"}"#
                )
                let fresh = try await stack.adapter.receiveEvent(session: nextIdentity)
                expect(fresh.kind == .userSpeechStarted && fresh.sequence == reboundFinal.sequence + 1,
                       "late old completion and audio cannot revive or duplicate a failed attempt")
                let beforeFreshCreate = try await sentTypes(stack.transport)
                expect(beforeFreshCreate.filter { $0 == "response.create" }.count == 1,
                       "old drain completion does not automatically retry the expired user turn")
                try await authorizeResponse(stack, from: fresh, responseID: "after-timeout-response")
                await stack.transport.enqueueText(
                    #"{"type":"response.done","response":{"id":"after-timeout-response","status":"completed","output":[{"id":"fixture-output-2039-0","role":"assistant","type":"message","content":[{"type":"text","text":"fresh reply"}]}]}}"#
                )
                let freshText = try await stack.adapter.receiveEvent(session: nextIdentity)
                let freshFinal = try await stack.adapter.receiveEvent(session: nextIdentity)
                expect(freshText.kind == .residentTextFinal("fresh reply")
                    && freshFinal.kind == .residentSemanticFinal(RealtimeBrainSemanticOutput(canonicalText: "fresh reply")),
                    "fresh authorized turn works after late remote drain on the original connection")
                let connections = await stack.transport.connectCount()
                expect(connections == connectionCountAfterInterrupt, "recoverable timeout cannot replace the connection")
                try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: nextIdentity))
                try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: nextIdentity))
                return
            }
            await stack.transport.releaseResponseCancellationAcknowledgements()
        }
        try await reboundResponse.value
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"response-barge-in","status":"completed","output":[{"id":"fixture-output-2056-0","role":"assistant","type":"message","content":[{"type":"text","text":"我在听"}]}]}}"#
        )
        let reboundResidentText = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        let reboundResidentSemantic = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            reboundResidentText.kind == .residentTextFinal("我在听")
                && reboundResidentSemantic.kind == .residentSemanticFinal(
                    RealtimeBrainSemanticOutput(canonicalText: "我在听")
                ),
            "the rebound user turn remains response-authorizable"
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
            #"{"type":"response.done","response":{"id":"response-interrupt","status":"completed","output":[{"id":"fixture-output-2085-0","role":"assistant","type":"message","content":[{"type":"text","text":"late old final"}]}]}}"#
        )
        for _ in 0 ..< 3 {
            await stack.transport.enqueueText(
                #"{"type":"input_audio_buffer.speech_stopped","item_id":"","audio_end_ms":10220}"#
            )
        }
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"user-current"}"#
        )
        let currentSpeech = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            currentSpeech.kind == .userSpeechStarted
                && currentSpeech.sequence == UInt64(reboundEvents.count + 3),
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

    private static func testPendingUserActivityRebindsAcrossContextRefresh()
        async throws {
        cases += 1
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let stack = try makeStack(diagnosticBuffer: diagnostics)
        let identity = sessionIdentity(generation: 23)
        try await openAndBootstrap(stack, identity: identity)

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"context-source-user"}"#
        )
        let sourceSpeech = try await stack.adapter.receiveEvent(
            session: identity
        )
        try await authorizeResponse(
            stack,
            from: sourceSpeech,
            responseID: "context-source-response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"context-source-response","status":"completed","output":[{"id":"fixture-output-2153-0","role":"assistant","type":"message","content":[{"type":"text","text":"context refresh"}]}]}}"#
        )
        let ingressLowerBound = DispatchTime.now().uptimeNanoseconds
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"pending-barge-in-user"}"#
        )

        let residentText = try await stack.adapter.receiveEvent(
            session: identity
        )
        let residentFinal = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            residentText.identity.contextRevision == 1
                && residentFinal.identity.contextRevision == 1,
            "terminal response events retain their accepted context revision"
        )
        await waitUntilPendingEventCount(
            stack.adapter, session: identity, minimum: 1,
            label: "pending speech-start before context refresh"
        )
        let ingressUpperBound = DispatchTime.now().uptimeNanoseconds

        try await stack.adapter.updateRuntimeContext(
            RealtimeBrainRuntimeContextUpdate(
                identity: identity,
                kind: .delta,
                contextRevision: 2,
                sections: [RealtimeBrainContextSection(
                    scope: .dynamicSession,
                    content: "refreshed context"
                )]
            )
        )
        let pendingSpeech = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            pendingSpeech.kind == .userSpeechStarted
                && pendingSpeech.sequence == 5
                && pendingSpeech.identity.contextRevision == 2,
            "pending speech-start joins the context accepted before delivery"
        )
        expect(
            pendingSpeech.ingressTimestampNanoseconds.map {
                $0 >= ingressLowerBound && $0 <= ingressUpperBound
            } == true,
            "context rebinding preserves local ingress time, not delivery time"
        )

        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"pending-barge-in-user","text":"停一下","stash":""}"#
        )
        let pendingTranscript = try await stack.adapter.receiveEvent(
            session: identity
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"pending-barge-in-user"}"#
        )
        let pendingStop = try await stack.adapter.receiveEvent(
            session: identity
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"pending-barge-in-user","transcript":"停一下"}"#
        )
        let pendingFinal = try await stack.adapter.receiveEvent(
            session: identity
        )
        expect(
            pendingTranscript.identity.turnID == pendingSpeech.identity.turnID
                && pendingStop.identity.turnID == pendingSpeech.identity.turnID
                && pendingFinal.identity.turnID == pendingSpeech.identity.turnID
                && pendingTranscript.identity.contextRevision == 2
                && pendingStop.identity.contextRevision == 2
                && pendingFinal.identity.contextRevision == 2,
            "the exact pending user turn stays on the refreshed context"
        )
        try await authorizeResponse(
            stack,
            from: pendingFinal,
            responseID: "pending-barge-in-response"
        )
        let responseCreateCount = try await sentTypes(stack.transport)
            .filter { $0 == "response.create" }
            .count
        expect(
            responseCreateCount == 2,
            "the rebound turn remains authorized for its next response"
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"pending-barge-in-response","status":"completed","output":[{"id":"fixture-output-2244-0","role":"assistant","type":"message","content":[{"type":"text","text":"继续"}]}]}}"#
        )
        _ = try await stack.adapter.receiveEvent(session: identity)
        _ = try await stack.adapter.receiveEvent(session: identity)
        expect(
            diagnostics.drain().events.contains {
                $0.category == "qwen_pending_user_activity_context_rebound"
                    && $0.stateBefore == "1"
                    && $0.stateAfter == "2"
            },
            "diagnostics expose the pending user-turn context repair"
        )

        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
    }

    private static func testPostStopCommittedItem() async throws {
        cases += 1
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let stack = try makeStack(diagnosticBuffer: diagnostics)
        let identity = sessionIdentity(generation: 43)
        try await openAndBootstrap(stack, identity: identity)
        // Live round 2: provisional partial -> empty timed stop -> new item partial/final.
        // Ordered receive calls preserve causality without racing a wall-clock sleep.
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"provisional","audio_start_ms":19640}"#)
        let started = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"provisional","text":"","stash":"请解释下雨，每一点都举。"}"#)
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"","audio_end_ms":26480}"#)
        let stopped = try await stack.adapter.receiveEvent(session: identity)
        expect(stopped.kind == .userSpeechStopped && stopped.identity == started.identity, "post-stop alias keeps the original speech boundary")
        await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"committed","text":"","stash":"请解释下雨，每一点都举一个例子。"}"#)
        await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"committed","transcript":"请解释下雨，每一点都举一个例子。"}"#)
        let final = try await stack.adapter.receiveEvent(session: identity)
        if case .userTranscriptFinal(let text) = final.kind {
            FileHandle.standardError.write(Data("post_stop_alias adapter_final=\(text)\n".utf8))
        }
        expect(final.kind == .userTranscriptFinal("请解释下雨，每一点都举一个例子。") && final.identity == started.identity,
               "committed final after empty stop replaces provisional text on the same turn")
        let events = diagnostics.drain().events
        expect(!events.contains { $0.category == "qwen_transcript_final_fallback_fired" }, "provider final cancels provisional fallback")
        let creates = try await sentTypes(stack.transport).filter { $0 == "response.create" }
        expect(creates.isEmpty,
               "Adapter does not create an answer when rebinding input")
        try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
    }

    private static func testPostStopCommittedItemFences() async throws {
        for name in ["identified-stop", "final-only", "different-final", "two-candidates", "expired",
                     "resumed", "context", "generation", "restart"] {
            cases += 1
            let diagnostics = NativeSpeechDiagnosticBuffer()
            let stack = try makeStack(diagnosticBuffer: diagnostics)
            var identity = sessionIdentity(generation: 44)
            try await openAndBootstrap(stack, identity: identity)
            await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"provisional","audio_start_ms":19640}"#)
            _ = try await stack.adapter.receiveEvent(session: identity)
            await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"provisional","text":"","stash":"原来的问题"}"#)
            _ = try await stack.adapter.receiveEvent(session: identity)
            let stopID = name == "identified-stop" ? "provisional" : ""
            await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"\#(stopID)","audio_end_ms":26480}"#)
            _ = try await stack.adapter.receiveEvent(session: identity)
            if name == "expired" {
                let fallback = try await stack.adapter.receiveEvent(session: identity)
                expect(fallback.kind == .userTranscriptFinal("原来的问题"), "expiry settles the old item before late input")
            } else if name == "resumed" {
                await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"resumed","audio_start_ms":27000}"#)
                _ = try await stack.adapter.receiveEvent(session: identity)
            } else if name == "context" {
                try await stack.adapter.updateRuntimeContext(RealtimeBrainRuntimeContextUpdate(
                    identity: identity, kind: .delta, contextRevision: 2,
                    sections: [RealtimeBrainContextSection(scope: .stableResident, content: "new context")]))
            } else if name == "generation" {
                let next = sessionIdentity(generation: 45, leaseID: identity.brainLeaseID, routeEpoch: identity.routeEpoch)
                try await stack.adapter.cancelGeneration(RealtimeBrainCancelGenerationCommand(
                    identity: identity, nextGeneration: next.generation, reason: .runtimeDecision))
                identity = next
                _ = try await stack.adapter.receiveEvent(session: identity)
            } else if name == "restart" {
                try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
                identity = sessionIdentity(generation: 45)
                try await openAndBootstrap(stack, identity: identity)
            }
            if name != "final-only" {
                await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"committed","text":"","stash":"不应接纳的问题"}"#)
            }
            if name == "two-candidates" {
                await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"another","text":"","stash":"另一个问题"}"#)
            }
            let final = name == "different-final" ? "另一个不同的问题" : "不应接纳的问题"
            await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"committed","transcript":"\#(final)"}"#)
            // FIFO marker proves the preceding unknown final was handled, without sleeping.
            await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"marker","audio_start_ms":28000}"#)
            let marker = try await stack.adapter.receiveEvent(session: identity)
            expect(marker.kind == .userSpeechStarted, "\(name): unknown final cannot claim or resurrect a turn")
            expect(!diagnostics.drain().events.contains { $0.disposition == "post_empty_stop_unique_preview_final" },
                   "\(name): post-stop alias fence stays closed")
            try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
        }
    }

    private static func testUnidentifiedStopRecoversBoundTurn() async throws {
        cases += 1
        let stack = try makeStack()
        let identity = sessionIdentity(generation: 41)
        try await openAndBootstrap(stack, identity: identity)
        // The failing live round's audio interval; no text or raw Provider IDs are retained.
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"live-round-ten","audio_start_ms":125760}"#)
        let started = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"live-round-ten","text":"","stash":"请解释第二点"}"#)
        _ = try await stack.adapter.receiveEvent(session: identity)
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"","audio_end_ms":132020}"#)
        // This ordered marker also makes the pre-fix failure immediate, without a sleep.
        await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"live-round-ten","text":"","stash":"请解释第二点的意思"}"#)
        let stopped = try await stack.adapter.receiveEvent(session: identity)
        expect(stopped.kind == .userSpeechStopped && stopped.identity == started.identity,
               "unique timed empty stop binds the existing turn before the partial marker")
        _ = try await stack.adapter.receiveEvent(session: identity)
        let final = try await stack.adapter.receiveEvent(session: identity)
        expect(final.kind == .userTranscriptFinal("请解释第二点的意思") && final.identity == started.identity,
               "existing debounce recovers the latest partial on the exact turn")
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"","audio_end_ms":132020}"#)
        await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"live-round-ten","transcript":"late duplicate"}"#)
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"next","audio_start_ms":133000}"#)
        let next = try await stack.adapter.receiveEvent(session: identity)
        expect(next.kind == .userSpeechStarted && next.identity.turnID != started.identity.turnID,
               "duplicate stop and late final do not resurrect the completed turn")
        let creates = try await sentTypes(stack.transport).filter { $0 == "response.create" }.count
        expect(creates == 0, "empty stop recovery does not grant Adapter response authority")
        try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
    }

    private static func testUnidentifiedStopRejectsUnboundEvidence() async throws {
        for name in ["no-partial", "no-start-time", "no-end-time", "old-end", "equal-end",
                     "boolean-end", "fractional-end", "two-starts", "unbound-partial"] {
            cases += 1
            let diagnostics = NativeSpeechDiagnosticBuffer()
            let stack = try makeStack(diagnosticBuffer: diagnostics)
            let identity = sessionIdentity(generation: 42)
            try await openAndBootstrap(stack, identity: identity)
            if name == "two-starts" {
                await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"other","audio_start_ms":500}"#)
                _ = try await stack.adapter.receiveEvent(session: identity)
            }
            let startTime = name == "no-start-time" ? "" : ",\"audio_start_ms\":1000"
            await stack.transport.enqueueText("{\"type\":\"input_audio_buffer.speech_started\",\"item_id\":\"current\"\(startTime)}")
            let start = try await stack.adapter.receiveEvent(session: identity)
            if name != "no-partial" {
                await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"current","text":"","stash":"原问题"}"#)
                _ = try await stack.adapter.receiveEvent(session: identity)
            }
            if name == "unbound-partial" {
                await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"unknown","text":"","stash":"另一个候选"}"#)
            }
            let endTime: String = switch name {
            case "no-end-time": ""
            case "old-end": ",\"audio_end_ms\":900"
            case "equal-end": ",\"audio_end_ms\":1000"
            case "boolean-end": ",\"audio_end_ms\":true"
            case "fractional-end": ",\"audio_end_ms\":1800.5"
            default: ",\"audio_end_ms\":1800"
            }
            await stack.transport.enqueueText("{\"type\":\"input_audio_buffer.speech_stopped\",\"item_id\":\"\"\(endTime)}")
            await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"current","text":"","stash":"继续讲话标记"}"#)
            let marker = try await stack.adapter.receiveEvent(session: identity)
            expect(marker.kind == .userTranscriptPartial("继续讲话标记") && marker.identity == start.identity,
                   "\(name): unbound stop never completes or rebinds a turn")
            let events = diagnostics.drain().events
            expect(events.contains { $0.category == "qwen_speech_stopped_rejected" }
                && !events.contains { $0.category == "qwen_transcript_final_fallback_scheduled" },
                "\(name): rejected stop cannot arm final recovery")
            try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
        }
    }

    private static func testEmptySpeechStopIsNotCompletion() async throws {
        for activeItems in 0 ... 2 {
            cases += 1
            let diagnostics = NativeSpeechDiagnosticBuffer()
            let stack = try makeStack(diagnosticBuffer: diagnostics)
            let identity = sessionIdentity(generation: 41)
            try await openAndBootstrap(stack, identity: identity)
            var lastSpeech: RealtimeResidentBrainEvent?
            for index in 0 ..< activeItems {
                await stack.transport.enqueueText(
                    #"{"type":"input_audio_buffer.speech_started","item_id":"empty-stop-\#(index)","audio_start_ms":1000}"#
                )
                lastSpeech = try await stack.adapter.receiveEvent(session: identity)
            }
            let sentBefore = try await sentTypes(stack.transport)
            for _ in 0 ..< 20 {
                await stack.transport.enqueueText(
                    #"{"type":"input_audio_buffer.speech_stopped","item_id":"","audio_end_ms":10220}"#
                )
            }
            // A valid marker proves all preceding rejected packets were processed.
            let itemID = activeItems == 0 ? "empty-stop-marker" : "empty-stop-\(activeItems - 1)"
            let marker: RealtimeResidentBrainEvent
            if activeItems == 0 {
                await stack.transport.enqueueText(
                    #"{"type":"input_audio_buffer.speech_started","item_id":"\#(itemID)"}"#
                )
                marker = try await stack.adapter.receiveEvent(session: identity)
                expect(marker.kind == .userSpeechStarted, "empty stops do not create user turns")
            } else {
                await stack.transport.enqueueText(
                    #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"\#(itemID)","text":"继续说完整句话","stash":""}"#
                )
                marker = try await stack.adapter.receiveEvent(session: identity)
                expect(marker.kind == .userTranscriptPartial("继续说完整句话"), "valid partial survives empty stops")
                expect(marker.identity.turnID == lastSpeech?.identity.turnID, "no invented turn binding")
            }
            let observed = diagnostics.drain().events
            expect(observed.filter { $0.category == "qwen_speech_stopped_rejected" }.count == 20,
                   "each empty stop is rejected observably, not swallowed")
            expect(!observed.contains { $0.category == "qwen_receive_failure" }, "empty stop is not terminal")
            let waiting = Task { try await stack.adapter.receiveEvent(session: identity) }
            await waitUntilPendingReceive(stack.adapter, session: identity)
            // Cross the existing 500 ms transcript fallback window to detect accidental timers.
            try await Task.sleep(for: .milliseconds(600))
            let stillWaiting = await stack.adapter.hasPendingEventWaiterForTesting(session: identity)
            expect(stillWaiting, "empty stops cannot schedule stop/final fallback, even with ambiguous input")
            let sentAfter = try await sentTypes(stack.transport)
            expect(sentAfter == sentBefore, "empty stops cannot create responses or send cancel/clear")
            await stack.transport.enqueueText(
                #"{"type":"input_audio_buffer.speech_stopped","item_id":"\#(itemID)","audio_end_ms":11000}"#
            )
            let stop = try await waiting.value
            expect(stop.kind == .userSpeechStopped && stop.identity == marker.identity,
                   "only a valid identified stop ends the exact current utterance")
            await stack.transport.enqueueText(
                #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"\#(itemID)","transcript":"继续说完整句话"}"#
            )
            let final = try await stack.adapter.receiveEvent(session: identity)
            expect(final.kind == .userTranscriptFinal("继续说完整句话") && final.identity == marker.identity,
                   "later valid final is neither lost nor rebound to another generation")
            let terminal = await stack.adapter.terminalErrorForTesting(session: identity)
            expect(terminal == nil, "valid recovery keeps session healthy")
            try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
        }
    }

    private static func testActiveResponseReceiveDiagnostics() async throws {
        let failures: [(frame: String?, phase: String, branch: String, wire: String)] = [
            (#"{"type":"input_audio_buffer.speech_stopped","audio_end_ms":10220}"#,
             "decode", "item_id", "input_audio_buffer.speech_stopped"),
            (#"{"type":"input_audio_buffer.speech_stopped","item_id":null,"audio_end_ms":10220}"#,
             "decode", "item_id", "input_audio_buffer.speech_stopped"),
            (#"{"type":"input_audio_buffer.speech_stopped","item_id":17,"audio_end_ms":10220}"#,
             "decode", "item_id", "input_audio_buffer.speech_stopped"),
            (#"{"type":"input_audio_buffer.speech_started","item_id":""}"#,
             "decode", "item_id", "input_audio_buffer.speech_started"),
            (#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"","transcript":"fixture"}"#,
             "decode", "item_id", "conversation.item.input_audio_transcription.completed"),
            ("{private-wire-marker", "decode", "json_object", "unknown"),
            (#"{"type":17,"text":"private-wire-marker"}"#,
             "decode", "object_or_type", "unknown"),
            (#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"private-item","text":"private-wire-marker"}"#,
             "decode", "transcript_text_or_stash", "conversation.item.input_audio_transcription.delta"),
            (#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"private-item","text":"private-wire-marker","stash":null}"#,
             "decode", "transcript_text_or_stash", "conversation.item.input_audio_transcription.delta"),
            (#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"private-item","transcript":null}"#,
             "decode", "transcript", "conversation.item.input_audio_transcription.completed"),
            (#"{"type":"response.audio.delta","response_id":"private-response","delta":"!!!private-wire-marker"}"#,
             "decode", "audio_base64", "response.audio.delta"),
            (#"{"type":"response.created","response":{"id":""}}"#,
             "decode", "response_id", "response.created"),
            (#"{"type":"response.created","response":{"id":"private-overlap"}}"#,
             "state", "response_authorization", "response.created"),
            (#"{"type":"session.created","session":{"id":"private-session"}}"#,
             "state", "unexpected_session_created", "session.created"),
            (#"{"type":"session.updated","session":{"turn_detection":{"create_response":true}}}"#,
             "state", "turn_detection_authority", "session.updated"),
            (nil, "transport_receive", "upstream_error", "none")
        ]
        // The valid control follows the same prefix as every injected failure.
        // This is a branch test, not a replay of the missing real wire packet.
        for index in 0 ... failures.count {
            cases += 1
            let diagnostics = NativeSpeechDiagnosticBuffer()
            let stack = try makeStack(diagnosticBuffer: diagnostics)
            let identity = sessionIdentity(generation: 4)
            try await openAndBootstrap(stack, identity: identity)
            await stack.transport.enqueueText(
                #"{"type":"input_audio_buffer.speech_started","item_id":"initial-user"}"#
            )
            let firstSpeech = try await stack.adapter.receiveEvent(session: identity)
            try await authorizeResponse(stack, from: firstSpeech, responseID: "private-response")
            await stack.transport.enqueueText(
                #"{"type":"input_audio_buffer.speech_started","item_id":"private-item"}"#
            )
            let proposal = try await stack.adapter.receiveEvent(session: identity)
            guard case .interruptionProposed = proposal.kind else {
                fatalError("active generation must emit interruption evidence")
            }
            let speech = try await stack.adapter.receiveEvent(session: identity)
            expect(speech.kind == .userSpeechStarted, "speech follows proposal")
            for partialIndex in 1 ... 8 {
                await stack.transport.enqueueText(
                    #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"private-item","text":"private-wire-marker-\#(partialIndex)","stash":""}"#
                )
                let partial = try await stack.adapter.receiveEvent(session: identity)
                expect(partial.kind == .userTranscriptPartial("private-wire-marker-\(partialIndex)"),
                       "each active-response partial survives without a Runtime decision")
                expect(partial.identity.turnID == speech.identity.turnID,
                       "active-response partial keeps the exact user turn")
            }
            let prefixDiagnostics = diagnostics.drain().events
            expect(prefixDiagnostics.contains {
                $0.category == "qwen_speech_started_received" && $0.disposition == "active_response"
            }, "failure prefix really has Provider generation in progress")
            expect(!prefixDiagnostics.contains { $0.category == "qwen_receive_failure" },
                   "valid active-response prefix has no receiver error")

            if index == failures.count {
                await stack.transport.enqueueText(
                    #"{"type":"input_audio_buffer.speech_stopped","item_id":"private-item"}"#
                )
                let stopped = try await stack.adapter.receiveEvent(session: identity)
                expect(stopped.kind == .userSpeechStopped, "valid overlap can end")
                await stack.transport.enqueueText(
                    #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"private-item","transcript":"停等一下"}"#
                )
                let final = try await stack.adapter.receiveEvent(session: identity)
                expect(final.kind == .userTranscriptFinal("停等一下"), "valid stop words remain transcript evidence")
                await stack.transport.enqueueText(
                    #"{"type":"response.audio.delta","response_id":"private-response","delta":"AAA="}"#
                )
                let speaking = try await stack.adapter.receiveEvent(session: identity)
                expect(speaking.kind == .residentSpeakingStarted, "valid audio starts resident speaking")
                let audio = try await stack.adapter.receiveEvent(session: identity)
                guard case .residentAudioDelta = audio.kind else {
                    fatalError("without a Runtime decision the resident audio stays active")
                }
                let terminal = await stack.adapter.terminalErrorForTesting(session: identity)
                expect(terminal == nil, "valid generating overlap does not fail the session")
                expect(!diagnostics.drain().events.contains { $0.category == "qwen_receive_failure" },
                       "normal receipt never produces failure diagnostics")
            } else {
                let failure = failures[index]
                let receive = Task {
                    try await stack.adapter.receiveEvent(session: identity)
                }
                await waitUntilPendingReceive(stack.adapter, session: identity)
                if let frame = failure.frame {
                    // Exercise binary JSON as well as the usual text WebSocket frame.
                    await stack.transport.enqueue(index == 3 ? .binary(Data(frame.utf8)) : .text(frame))
                } else {
                    await stack.transport.failNextReceive(.invalidEvent)
                }
                await expectRealtimeError(.invalidEvent) { _ = try await receive.value }
                await waitUntilTerminalError(stack.adapter, session: identity, expected: .invalidEvent)
                let events = diagnostics.drain().events.filter { $0.category == "qwen_receive_failure" }
                expect(events.count == 1, "one failure produces exactly one diagnostic")
                guard let diagnostic = events.first else { fatalError("missing receive failure diagnostic") }
                let detail = diagnostic.disposition ?? ""
                expect(detail.contains("phase=\(failure.phase);wire=\(failure.wire);branch=\(failure.branch)"),
                       "the actual decode/state/transport branch is distinguishable")
                expect(detail.contains("active_response=true") && detail.contains("user_input=true"),
                       "failure records the overlap state before teardown")
                expect(diagnostic.stateBefore == "active" && diagnostic.stateAfter == "failed"
                    && diagnostic.turnGeneration == 4 && diagnostic.routeKind == .realtimeBrain,
                       "failure retains formal route and generation attribution")
                expect(diagnostic.errorCode == "invalid_event" && (diagnostic.wireSequence ?? 0) > 0,
                       "public error remains unchanged and wire receipt is correlated")
                expect(diagnostic.byteCount == failure.frame.map { $0.utf8.count },
                       "failure byte count is accurate without storing the packet")
                expect(!detail.contains("private-") && !detail.contains("停等一下"),
                       "diagnostic excludes transcript, identifiers and raw payload")
            }
            let sent = try await sentTypes(stack.transport)
            expect(sent.filter { $0 == "response.create" }.count == 1,
                   "receiver diagnostics never authorize another response")
            expect(!sent.contains("response.cancel") && !sent.contains("input_audio_buffer.clear"),
                   "receiver diagnostics never decide cancellation or input clearing")
            try? await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
        }
        print("qwen_receive_failure_matrix_cases=\(failures.count)")
        print("qwen_active_response_receive_control=PASS")
        print("qwen_real_invalid_event_packet_replay=NOT_AVAILABLE")
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
            #"{"type":"response.function_call_arguments.done","response_id":"tool-response","output_index":0,"item_id":"tool-item","call_id":"call-weather","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}"#
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
            #"{"type":"response.done","response":{"id":"tool-response","status":"completed","output":[{"id":"tool-item","type":"function_call","call_id":"call-weather","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}]}}"#
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
            #"{"type":"response.function_call_arguments.done","response_id":"tool-collision-response","output_index":0,"item_id":"tool-collision-item","call_id":"call-weather","name":"weather_lookup","arguments":"{\"city\":\"Suzhou\"}"}"#
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
            #"{"type":"response.done","response":{"id":"tool-collision-response","status":"completed","output":[{"id":"tool-collision-item","type":"function_call","call_id":"call-weather","name":"weather_lookup","arguments":"{\"city\":\"Suzhou\"}"}]}}"#
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
            #"{"type":"response.done","response":{"id":"response-tool-1","status":"completed","output":[{"id":"fixture-output-3039-0","role":"assistant","type":"message","content":[{"type":"text","text":"杭州现在 25 度。"}]}]}}"#
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
            #"{"type":"response.function_call_arguments.done","response_id":"fast-tool-response","output_index":0,"item_id":"fast-tool-item","call_id":"fast-tool-call","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}"#
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
            #"{"type":"response.done","response":{"id":"fast-tool-response","status":"completed","output":[{"id":"fast-tool-item","type":"function_call","call_id":"fast-tool-call","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}]}}"#
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
            #"{"type":"response.done","response":{"id":"fast-tool-continuation","status":"completed","output":[{"id":"fixture-output-3136-0","role":"assistant","type":"message","content":[{"type":"text","text":"杭州现在 25 度。"}]}]}}"#
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
            #"{"type":"response.function_call_arguments.done","response_id":"multi-tool-response","output_index":0,"item_id":"multi-tool-item-1","call_id":"multi-tool-call-1","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.function_call_arguments.done","response_id":"multi-tool-response","output_index":1,"item_id":"multi-tool-item-2","call_id":"multi-tool-call-2","name":"weather_lookup","arguments":"{\"city\":\"Shanghai\"}"}"#
        )
        let firstEvent = try await stack.adapter.receiveEvent(session: identity)
        let secondEvent = try await stack.adapter.receiveEvent(session: identity)
        guard case .toolCall(let firstCandidate) = firstEvent.kind,
              case .toolCall(let secondCandidate) = secondEvent.kind else {
            fatalError("two tool candidates expected")
        }
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"multi-tool-response","status":"completed","output":[{"id":"multi-tool-item-1","type":"function_call","call_id":"multi-tool-call-1","name":"weather_lookup","arguments":"{\"city\":\"Hangzhou\"}"},{"id":"multi-tool-item-2","type":"function_call","call_id":"multi-tool-call-2","name":"weather_lookup","arguments":"{\"city\":\"Shanghai\"}"}]}}"#
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
            #"{"type":"response.done","response":{"id":"multi-tool-continuation","status":"completed","output":[{"id":"fixture-output-3237-0","role":"assistant","type":"message","content":[{"type":"text","text":"两座城市都已查询。"}]}]}}"#
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
            #"{"type":"response.function_call_arguments.done","response_id":"failed-tool-response","output_index":0,"item_id":"failed-tool-item","call_id":"failed-tool-call","name":"weather_lookup","arguments":"{}"}"#
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
            #"{"type":"response.function_call_arguments.done","response_id":"late-failed-tool-response","output_index":0,"item_id":"late-failed-tool-item","call_id":"late-failed-tool-call","name":"weather_lookup","arguments":"{}"}"#
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
        var closingIdentity = identity
        do {
            try await stack.adapter.interrupt(RealtimeBrainInterruptCommand(
                identity: identity,
                nextGeneration: identity.generation + 1,
                reason: .runtimeDecision
            ))
            closingIdentity = sessionIdentity(
                generation: identity.generation + 1,
                leaseID: identity.brainLeaseID,
                routeEpoch: identity.routeEpoch
            )
            await expectRealtimeError(.providerFailure) {
                while true { _ = try await stack.adapter.receiveEvent(session: closingIdentity) }
            }
        } catch {
            expect(error as? RealtimeResidentBrainError == .providerFailure,
                   "cancel failure is terminal whether before or after local rebound")
        }
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: closingIdentity)
        )
        let transitionCloseCount = await stack.transport.closeCount()
        expect(
            transitionCloseCount == 1,
            "generic cancel error fails immediately and remains definitively closeable"
        )

        let transcriptFailureStack = try makeStack()
        let transcriptFailureIdentity = sessionIdentity(generation: 32)
        try await openAndBootstrap(
            transcriptFailureStack,
            identity: transcriptFailureIdentity
        )
        await transcriptFailureStack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"transition-asr-failure"}"#
        )
        let transcriptFailureSpeech = try await transcriptFailureStack
            .adapter.receiveEvent(session: transcriptFailureIdentity)
        try await authorizeResponse(
            transcriptFailureStack,
            from: transcriptFailureSpeech,
            responseID: "transition-asr-failure-response"
        )
        await transcriptFailureStack.transport
            .holdResponseCancellationAcknowledgements()
        let transcriptFailureInterrupt = Task {
            try await transcriptFailureStack.adapter.interrupt(
                RealtimeBrainInterruptCommand(
                    identity: transcriptFailureIdentity,
                    nextGeneration: transcriptFailureIdentity.generation + 1,
                    reason: .runtimeDecision
                )
            )
        }
        await transcriptFailureStack.transport.waitUntilSent(
            type: "response.cancel"
        )
        await transcriptFailureStack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.failed","item_id":"transition-asr-failure","error":{"code":"asr_failed"}}"#
        )
        var transcriptClosingIdentity = transcriptFailureIdentity
        do {
            try await transcriptFailureInterrupt.value
            transcriptClosingIdentity = sessionIdentity(
                generation: transcriptFailureIdentity.generation + 1,
                leaseID: transcriptFailureIdentity.brainLeaseID,
                routeEpoch: transcriptFailureIdentity.routeEpoch
            )
            await expectRealtimeError(.providerFailure) {
                while true {
                    _ = try await transcriptFailureStack.adapter.receiveEvent(
                        session: transcriptClosingIdentity
                    )
                }
            }
        } catch {
            expect(error as? RealtimeResidentBrainError == .providerFailure,
                   "ASR failure remains terminal across local rebound")
        }
        try await transcriptFailureStack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(
                identity: transcriptClosingIdentity
            )
        )
        let transcriptFailureCloseCount = await transcriptFailureStack
            .transport.closeCount()
        expect(
            transcriptFailureCloseCount == 1,
            "exact ASR failure during transition remains fail closed"
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
        let reboundDisposition = try await runtime
            .receiveRealtimeResidentBrainEvent(session: nextIdentity)
        guard case .accepted(let reboundEvent) = reboundDisposition else {
            fatalError("interrupting user turn must rebound into N+1")
        }
        expect(
            reboundEvent.kind == .userSpeechStarted
                && reboundEvent.sequence == 1
                && reboundEvent.identity.session == nextIdentity
                && reboundEvent.identity.turnID
                    == acceptedSpeechStarted.identity.turnID,
            "Runtime rebuilds the exact interrupting user turn in N+1"
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"runtime-old-user"}"#
        )
        let reboundStop = try await runtime
            .receiveRealtimeResidentBrainEvent(session: nextIdentity)
        guard case .accepted(let reboundStopEvent) = reboundStop else {
            fatalError("rebound speech stop expected")
        }
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"runtime-old-user","transcript":"停一下"}"#
        )
        let reboundFinal = try await runtime
            .receiveRealtimeResidentBrainEvent(session: nextIdentity)
        expect(
            reboundStopEvent.kind == .userSpeechStopped
                && reboundStopEvent.sequence == 2
                && reboundStopEvent.identity.turnID
                    == reboundEvent.identity.turnID,
            "Runtime accepts the rebound speech stop only in N+1"
        )
        expect(
            reboundFinal == .rejectedStale
                && runtime.realtimePendingUserInputForTesting(
                    reboundEvent.identity
                ) == "停一下",
            "Runtime receives the rebound transcript but keeps acoustic admission fail closed"
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"runtime-unrelated-old-user","transcript":"late"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.failed","item_id":"runtime-unrelated-old-user","error":{"code":"late_old_asr"}}"#
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
                && currentEvent.sequence == 4
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

    private static func testPendingAnswerMatrix(fixture: Data) async throws {
        let startingCases = cases
        let startingChecks = checks
        cases += 1
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .seconds(15))
        let expired = RealtimeBrainResponseAttempt()
        expired.setSubmissionDeadline(deadline)
        expired.setSubmissionDeadline(deadline.advanced(by: .seconds(15)))
        expect(!expired.beginSubmissionForTesting(at: deadline), "deadline is inclusive and cannot roll forward")
        expect(expired.invalidate() == .notSubmitted, "deadline before beginSubmission proves no write")
        expect(!expired.beginSubmissionForTesting(at: start), "revocation cannot be reversed by a late callback")
        let sent = RealtimeBrainResponseAttempt()
        sent.setSubmissionDeadline(deadline)
        expect(sent.beginSubmissionForTesting(at: start.advanced(by: .milliseconds(14_900))), "submission at 14.9 seconds is admitted")
        expect(sent.invalidate() == .uncertain, "beginSubmission before expiry atomically reports uncertainty")
        expect(!sent.beginSubmissionForTesting(at: start), "uncertain write never obtains another submission")
        sent.submitted()
        expect(sent.invalidate() == .submitted, "completed write remains submitted after revocation")
        for scenario in R3PendingAnswerCase.allCases {
            try await testRuntimeConfirmedInterruptionUserTurnHandoff(
                fixture: fixture, drainTimeout: true, pendingCase: scenario
            )
        }
        try await testInterruptionAndGeneration(missingCancellationCompletion: true, drainTimeout: true, doneBeforeCatch: true)
        try await testSubmittedResponseTimeoutIsTerminal()
        print("pending_answer_default_matrix=PASS cases=\(cases - startingCases) checks=\(checks - startingChecks)")
    }

    private static func testRuntimeConfirmedInterruptionUserTurnHandoff(
        fixture: Data,
        drainTimeout: Bool = false,
        pendingCase: R3PendingAnswerCase = .lateDone,
        unidentifiedStop: Bool = false,
        postStopCommittedItem: Bool = false
    ) async throws {
        cases += 1
        print("handoff_case=\(pendingCase.rawValue) unidentified_stop=\(unidentifiedStop) committed_item=\(postStopCommittedItem)")
        let diagnostics = NativeSpeechDiagnosticBuffer()
        let stack = try makeStack(diagnosticBuffer: diagnostics)
        let catchBarrier = R3ResponseCatchBarrier()
        let recoversInput = pendingCase.rawValue.hasPrefix("inputRecovery")
        if drainTimeout && pendingCase != .doneBeforeTimeout && pendingCase != .supersedeDuringWait && !recoversInput {
            await stack.adapter.setResponseCatchBarrierForTesting { await catchBarrier.suspend() }
        }
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
               "confirmed-handoff fixture resident loads")
        runtime.attachNativeSpeechDiagnosticBuffer(diagnostics)
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
                        content: "confirmed interruption user-turn handoff"
                    )]
                )
            ),
            "confirmed-handoff fixture bootstraps"
        )
        expectAccepted(
            try await runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            kind: .sessionReady,
            "confirmed-handoff session becomes ready"
        )

        let listeningActivity = RealtimeBrainLocalAudioActivity(
            kind: .listeningNearEnd,
            residentPlaybackSequence: 0,
            residentPlaybackActive: false,
            lastAudibleResidentRenderTimestampNanoseconds: nil,
            sourceGateEpoch: 0,
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
        let frameBytes = pcm16(Array(repeating: 400, count: 320))
        var timestamp = DispatchTime.now().uptimeNanoseconds
        expectRealtimeSuccess(
            await runtime.appendRealtimeResidentBrainAudio(
                RealtimeBrainAudioFrame(
                    identity: identity,
                    sequence: 1,
                    timestampNanoseconds: timestamp,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: 16_000,
                        channelCount: 1
                    ),
                    provenance: .acousticEchoProcessed,
                    bytes: frameBytes
                ),
                activity: listeningActivity
            ),
            "initial listening audio establishes the turn boundary"
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"initial-user"}"#
        )
        expectAccepted(
            try await runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            kind: .userSpeechStarted,
            "initial listening turn starts"
        )
        for sequence in 2 ... 5 {
            try? await Task.sleep(for: .milliseconds(20))
            timestamp = DispatchTime.now().uptimeNanoseconds
            expectRealtimeSuccess(
                await runtime.appendRealtimeResidentBrainAudio(
                    RealtimeBrainAudioFrame(
                        identity: identity,
                        sequence: UInt64(sequence),
                        timestampNanoseconds: timestamp,
                        format: RealtimeBrainAudioFormat(
                            encoding: .pcm16LittleEndian,
                            sampleRate: 16_000,
                            channelCount: 1
                        ),
                        provenance: .acousticEchoProcessed,
                        bytes: frameBytes
                    ),
                    activity: listeningActivity
                ),
                "initial listening audio remains continuous"
            )
        }
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"initial-user"}"#
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        _ = try await receiveRuntimeTranscript(
            stack,
            runtime: runtime,
            identity: identity,
            itemID: "initial-user",
            transcript: "请先回答"
        )
        await stack.transport.waitUntilSent(type: "response.create")
        await stack.transport.enqueueText(
            #"{"type":"response.output_item.added","response_id":"response-tool-1","output_index":0,"item":{"id":"assistant-old","type":"message","role":"assistant"}}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.audio.delta","response_id":"response-tool-1","delta":"AAA="}"#
        )
        let residentSpeaking = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        let residentAudio = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        guard case .accepted(let residentSpeakingEvent) = residentSpeaking,
              residentSpeakingEvent.kind == .residentSpeakingStarted,
              case .accepted(let residentAudioEvent) = residentAudio,
              case .residentAudioDelta = residentAudioEvent.kind else {
            fatalError("confirmed-handoff resident response must be active")
        }
        _ = diagnostics.drain()

        let evidenceTimestamp = DispatchTime.now().uptimeNanoseconds
        let acousticEvidence = RealtimeInterruptionEvidence(
            identity: RealtimeInterruptionEvidenceIdentity(
                session: identity,
                turnID: residentAudioEvent.identity.turnID,
                responseID: residentAudioEvent.identity.responseID,
                contextRevision: residentAudioEvent.identity.contextRevision,
                sequence: 1,
                timestampNanoseconds: evidenceTimestamp
            ),
            source: .acousticHost(RealtimeInterruptionAcousticFacts(
                sourceGateEpoch: 1,
                nearEndDetected: true,
                farEndActive: true,
                sourceGateOpen: true,
                renderReferenceConfidence: 1,
                routeStable: true,
                inputDeviceAvailable: true,
                outputDeviceAvailable: true
            ))
        )
        guard case .success(.observed) = await runtime
            .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acousticEvidence
            ) else {
            fatalError("confirmed-handoff acoustic evidence must be observed")
        }

        await stack.transport.holdResponseCancellationAcknowledgements()
        let cancelWriteBarrier = R3ResponseCatchBarrier()
        if pendingCase == .inputRecoveryDuringCancellation || pendingCase == .inputRecoveryStopDuringCancellation
            || pendingCase == .inputRecoveryCancellationDeadline {
            await stack.transport.setResponseCancelWriteBarrier { await cancelWriteBarrier.suspend() }
        }
        if recoversInput {
            try await stack.adapter.appendAudio(RealtimeBrainAudioFrame(
                identity: identity, sequence: 6, timestampNanoseconds: timestamp + 1,
                format: RealtimeBrainAudioFormat(encoding: .pcm16LittleEndian, sampleRate: 16_000, channelCount: 1),
                provenance: .acousticEchoProcessed, bytes: pcm16(Array(repeating: 700, count: 1_600))))
        }
        let audioWriteBarrier = R3ResponseCatchBarrier()
        var heldAppend: Task<Result<Void, RealtimeResidentBrainError>, Never>?
        let heldAudio = pcm16(Array(repeating: 900, count: 1_600))
        if pendingCase == .inputRecoveryDuringAudioAppend {
            await stack.transport.setAudioAppendWriteBarrier { await audioWriteBarrier.suspend() }
            heldAppend = Task {
                await runtime.appendRealtimeResidentBrainAudio(RealtimeBrainAudioFrame(
                    identity: identity, sequence: 6, timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                    format: RealtimeBrainAudioFormat(encoding: .pcm16LittleEndian, sampleRate: 16_000, channelCount: 1),
                    provenance: .acousticEchoProcessed, bytes: heldAudio), activity: listeningActivity)
            }
            await audioWriteBarrier.waitForEntry()
        }
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"interrupting-user","audio_start_ms":\#(recoversInput ? 100 : 125760)}"#
        )
        if pendingCase == .inputRecoveryBeforeConfirmation || pendingCase == .inputRecoveryDuringAudioAppend
            || pendingCase == .inputRecoveryCancellationDeadline {
            await stack.transport.enqueueText(#"{"type":"response.audio_transcript.delta","response_id":"response-tool-1","item_id":"interrupting-user","output_index":0,"delta":"old resident words"}"#)
            await waitForCondition("collision precedes Runtime confirmation") {
                await stack.adapter.terminalErrorForTesting(session: identity) == .invalidEvent
            }
        }
        if pendingCase == .inputRecoveryDuringAudioAppend {
            do {
                try await stack.adapter.interrupt(RealtimeBrainInterruptCommand(
                    identity: identity, nextGeneration: identity.generation + 1, reason: .runtimeDecision))
                fatalError("an in-flight append must defer generation transition")
            } catch {
                expect(error as? RealtimeResidentBrainError == .operationInFlight,
                       "in-flight append defers the interrupt without dismantling quarantine")
            }
            let retainedError = await stack.adapter.terminalErrorForTesting(session: identity)
            expect(retainedError == .invalidEvent, "deferred transition retains the quarantined generation")
        }
        let proposalDisposition = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        guard case .accepted(let proposalEvent) = proposalDisposition,
              case .interruptionProposed = proposalEvent.kind,
              case .success(.confirmed(let decision)) = await runtime
                .claimRealtimeResidentBrainInterruptionDecision(
                    for: proposalEvent
                ) else {
            fatalError("confirmed-handoff interruption must be Runtime-confirmed")
        }
        if pendingCase == .inputRecoveryDuringAudioAppend {
            await waitForCondition("Runtime drains the old append before cancelling") {
                runtime.realtimeProviderOperationsForTesting().waiters > 0
            }
            let operations = runtime.realtimeProviderOperationsForTesting()
            expect(operations.operations >= 2, "Runtime retains append and generation transition ownership")
            let beforeRelease = try await sentTypes(stack.transport)
            expect(!beforeRelease.contains("response.cancel"), "cancel cannot overtake an in-flight append")
            await audioWriteBarrier.release()
            let appendResult = await heldAppend?.value
            guard case .failure(.cancelled)? = appendResult else {
                fatalError("invalidated append must finish without settling the new turn")
            }
            await stack.transport.setAudioAppendWriteBarrier(nil)
        }
        if pendingCase == .inputRecoveryCancellationDeadline {
            await cancelWriteBarrier.waitForEntry()
            try await Task.sleep(for: .seconds(16))
            let closes = await stack.transport.closeCount()
            expect(closes == 1, "the original recovery deadline closes a stalled cancel write")
            await cancelWriteBarrier.release()
            let result = await runtime.completeRealtimeResidentBrainInterruption(decision)
            guard case .failure = result else { fatalError("expired cancellation cannot recover") }
            expect(runtime.activeBrainLeaseForTesting() == nil, "deadline releases the session without submitting a new answer")
            return
        }
        if pendingCase == .inputRecoveryDuringCancellation || pendingCase == .inputRecoveryStopDuringCancellation {
            await cancelWriteBarrier.waitForEntry()
            await stack.transport.enqueueText(#"{"type":"response.audio_transcript.delta","response_id":"response-tool-1","item_id":"interrupting-user","output_index":0,"delta":"old resident words"}"#)
            await waitForCondition("collision arrives during response.cancel send") {
                await stack.adapter.terminalErrorForTesting(session: identity) == .invalidEvent
            }
            if pendingCase == .inputRecoveryStopDuringCancellation {
                await stack.transport.holdNextCloseCompletion()
                let closed = Task { try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity)) }
                await waitForCondition("Stop fences the quarantined cancellation") {
                    await stack.adapter.isClosingForTesting(session: identity)
                }
                await cancelWriteBarrier.release()
                let result = await runtime.completeRealtimeResidentBrainInterruption(decision)
                guard case .failure = result else { fatalError("Stop must prevent cancellation from reviving the session") }
                await stack.transport.releaseHeldCloseCompletion()
                try await closed.value
                expect(runtime.activeBrainLeaseForTesting() == nil, "Stop wins over the suspended cancellation")
                let sent = try await sentTypes(stack.transport)
                expect(sent.filter { $0 == "response.create" }.count == 1, "Stop cannot submit a recovered response")
                return
            }
            await cancelWriteBarrier.release()
        }
        try await waitUntilSentTypeCount(
            stack.transport,
            type: "response.cancel",
            minimum: 1
        )
        if !drainTimeout && !unidentifiedStop {
            await stack.transport.releaseResponseCancellationAcknowledgements()
        }
        let nextIdentity = try realtimeIdentity(
            await runtime.completeRealtimeResidentBrainInterruption(decision)
        )

        let reboundStart = try await runtime
            .receiveRealtimeResidentBrainEvent(session: nextIdentity)
        guard case .accepted(let reboundStartEvent) = reboundStart else {
            fatalError("confirmed interrupting turn must start in N+1")
        }
        expect(
            reboundStartEvent.kind == .userSpeechStarted
                && reboundStartEvent.sequence == 1,
            "Runtime consumes the confirmed-interruption handoff once"
        )
        if recoversInput {
            if pendingCase == .inputRecoveryFinal || pendingCase == .inputRecoveryChangedFinal {
                await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"interrupting-user"}"#)
                _ = try await runtime.receiveRealtimeResidentBrainEvent(session: nextIdentity)
                _ = try await receiveRuntimeTranscript(stack, runtime: runtime, identity: nextIdentity,
                                                      itemID: "interrupting-user", transcript: "原始完整问题")
            }
            await stack.transport.enqueueText(#"{"type":"response.audio_transcript.delta","response_id":"response-tool-1","item_id":"interrupting-user","output_index":0,"delta":"old resident words"}"#)
            for _ in 0..<100 {
                if await stack.adapter.terminalErrorForTesting(session: nextIdentity) != nil { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            let quarantinedError = await stack.adapter.terminalErrorForTesting(session: nextIdentity)
            expect(quarantinedError == .invalidEvent,
                   "collision quarantines old wire before a partial or final exists")
            await stack.adapter.expireInputRecoveryForTesting(matching: residentAudioEvent.identity)
            if pendingCase == .inputRecoveryStop {
                _ = await runtime.closeRealtimeResidentBrainSession(identity: nextIdentity)
                expect(runtime.activeBrainLeaseForTesting() == nil, "Stop discards retained input and recovery permission")
                let connections = await stack.transport.connectedEndpoints.count
                expect(connections == 1, "Stop cannot reconnect a quarantined session")
                return
            }
            if pendingCase == .inputRecoveryTimeout {
                await stack.adapter.expireInputRecoveryForTesting()
                do { _ = try await runtime.receiveRealtimeResidentBrainEvent(session: nextIdentity); fatalError("expired recovery must fail") }
                catch { expect(runtime.activeBrainLeaseForTesting() == nil, "deadline fails closed without reconnecting") }
                return
            }
            if pendingCase == .inputRecoveryOverflow {
                let result = await runtime.appendRealtimeResidentBrainAudio(RealtimeBrainAudioFrame(
                    identity: nextIdentity, sequence: 1, timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                    format: RealtimeBrainAudioFormat(encoding: .pcm16LittleEndian, sampleRate: 16_000, channelCount: 1),
                    provenance: .acousticEchoProcessed, bytes: Data(repeating: 0, count: 480_002)), activity: listeningActivity)
                guard case .failure = result else { fatalError("oversized recovery input must fail") }
                expect(runtime.activeBrainLeaseForTesting() == nil, "overflow closes instead of replaying a truncated utterance")
                return
            }
            expectRealtimeSuccess(await runtime.appendRealtimeResidentBrainAudio(RealtimeBrainAudioFrame(
                identity: nextIdentity, sequence: 1, timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                format: RealtimeBrainAudioFormat(encoding: .pcm16LittleEndian, sampleRate: 16_000, channelCount: 1),
                provenance: .acousticEchoProcessed, bytes: frameBytes), activity: listeningActivity),
                "quarantine retains continuing input without failing Host capture")
            let holdsReconnect = pendingCase == .inputRecoveryStopDuringReconnect || pendingCase == .inputRecoveryConcurrentReceive
            if holdsReconnect { await stack.transport.holdNextCloseCompletion() }
            let recovered = Task { try await runtime.receiveRealtimeResidentBrainEvent(session: nextIdentity) }
            if holdsReconnect {
                await waitForCondition("old connection closes before reconnect") { await stack.transport.closeCount() == 1 }
                if pendingCase == .inputRecoveryStopDuringReconnect {
                    let stopped = Task { await runtime.closeRealtimeResidentBrainSession(identity: nextIdentity) }
                    await Task.yield()
                    await stack.transport.releaseHeldCloseCompletion()
                    _ = await stopped.value
                    do { _ = try await recovered.value } catch { /* Stop owns the terminal outcome. */ }
                    expect(runtime.activeBrainLeaseForTesting() == nil, "Stop during reconnect cannot revive the lease")
                    let sent = try await sentTypes(stack.transport)
                    expect(sent.filter { $0 == "response.create" }.count == 1, "Stop during reconnect cannot submit an answer")
                    return
                }
                let duplicateReceive = try await runtime.receiveRealtimeResidentBrainEvent(session: nextIdentity)
                expect(duplicateReceive == .rejectedReceiveInFlight, "one Runtime receive reservation coalesces recovery")
                await stack.transport.releaseHeldCloseCompletion()
            }
            try await waitUntilSentTypeCount(stack.transport, type: "input_audio_buffer.append",
                                            minimum: pendingCase == .inputRecoveryDuringAudioAppend ? 6 : 4)
            let objects = try await sentObjects(stack.transport)
            let audio = objects.filter { $0["type"] as? String == "input_audio_buffer.append" }
                .compactMap { ($0["audio"] as? String).flatMap { Data(base64Encoded: $0) } }
            let heldPrefix = pendingCase == .inputRecoveryDuringAudioAppend ? heldAudio : Data()
            expect(audio.suffix(heldPrefix.isEmpty ? 2 : 3).reduce(Data(), +) == pcm16(Array(repeating: 700, count: 1_600)) + heldPrefix + frameBytes,
                   "replay is exactly the new utterance prefix plus quarantine continuation")
            await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"recovered-user","audio_start_ms":0}"#)
            if pendingCase == .inputRecoverySecondCollision {
                await stack.transport.enqueueText(#"{"type":"response.output_item.done","response_id":"response-tool-1","output_index":0,"item":{"id":"recovered-user","type":"message","role":"assistant"}}"#)
                do { _ = try await recovered.value; fatalError("second collision must fail closed") }
                catch { expect(runtime.activeBrainLeaseForTesting() == nil, "second collision safely releases lease") }
                let connections = await stack.transport.connectedEndpoints.count
                let sent = try await sentTypes(stack.transport)
                expect(connections == 2 && sent.filter { $0 == "response.create" }.count == 1,
                       "second collision cannot retry or produce another response")
                return
            }
            await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"recovered-user"}"#)
            if pendingCase == .inputRecoveryFinal || pendingCase == .inputRecoveryChangedFinal {
                let recoveredText = pendingCase == .inputRecoveryFinal ? "原始完整问题" : "重放后的不同转写不得覆盖"
                await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"recovered-user","transcript":"\#(recoveredText)"}"#)
                if pendingCase == .inputRecoveryChangedFinal {
                    do { _ = try await recovered.value; fatalError("changed canonical final must fail closed") }
                    catch { expect(runtime.activeBrainLeaseForTesting() == nil, "changed replay final cannot reach subsequent model context") }
                    let sent = try await sentTypes(stack.transport)
                    expect(sent.filter { $0 == "response.create" }.count == 1, "mismatched final cannot release response authorization")
                    return
                }
                try await waitUntilSentTypeCount(stack.transport, type: "response.create", minimum: 2)
                expect(runtime.realtimePendingUserInputForTesting(reboundStartEvent.identity) == "原始完整问题",
                       "replayed final cannot replace the finalized canonical user text")
                await stack.transport.enqueueText(#"{"type":"response.done","response":{"id":"response-tool-2","status":"completed","output":[{"id":"answer-new","type":"message","role":"assistant","content":[{"type":"text","text":"恢复后的回答。"}]}]}}"#)
                expectAccepted(try await recovered.value, kind: .residentTextFinal("恢复后的回答。"),
                               "existing pending answer resumes after recovered input acknowledgement")
                _ = try await runtime.receiveRealtimeResidentBrainEvent(session: nextIdentity)
                try await verifyRecoveredPersistence(stack, runtime: runtime, identity: nextIdentity,
                                                     question: "原始完整问题", answer: "恢复后的回答。")
                _ = await runtime.closeRealtimeResidentBrainSession(identity: nextIdentity)
                return
            }
            expectAccepted(try await recovered.value, kind: .userSpeechStopped,
                           "replayed speech start reuses the existing turn without a second start")
            let final = try await receiveRuntimeTranscript(stack, runtime: runtime, identity: nextIdentity,
                                                          itemID: "recovered-user", transcript: "解释地球和火星的区别")
            guard case .accepted(let event) = final else { fatalError("recovered final must be accepted") }
            expect(event.identity.turnID == reboundStartEvent.identity.turnID && event.identity.responseID == nil,
                   "new wire alias retains original canonical user ownership")
            try await waitUntilSentTypeCount(stack.transport, type: "response.create", minimum: 2)
            expect(runtime.realtimePendingUserInputForTesting(event.identity) == "解释地球和火星的区别",
                   "only actual recovered final becomes canonical")
            let connectionCount = await stack.transport.connectedEndpoints.count
            expect(connectionCount == 2, "Runtime authorizes exactly one reconnection")
            expect(runtime.activeBrainLeaseForTesting()?.generation == .realtimeResidentBrain(nextIdentity.generation),
                   "recovery does not advance the Runtime generation")
            await stack.transport.enqueueText(#"{"type":"response.done","response":{"id":"response-tool-2","status":"completed","output":[{"id":"answer-new","type":"message","role":"assistant","content":[{"type":"text","text":"地球有海洋，火星较寒冷。"}]}]}}"#)
            _ = try await runtime.receiveRealtimeResidentBrainEvent(session: nextIdentity)
            _ = try await runtime.receiveRealtimeResidentBrainEvent(session: nextIdentity)
            try await verifyRecoveredPersistence(stack, runtime: runtime, identity: nextIdentity,
                                                 question: "解释地球和火星的区别", answer: "地球有海洋，火星较寒冷。")
            let sent = try await sentTypes(stack.transport)
            expect(sent.filter { $0 == "response.create" }.count == 2 && sent.filter { $0 == "response.cancel" }.count == 1,
                   "one initial response and one recovered answer, one original interruption")
            _ = await runtime.closeRealtimeResidentBrainSession(identity: nextIdentity)
            return
        }
        for preview in ["找", "找点", "找点乐子", "找点乐子是什么"] {
            await stack.transport.enqueueText(
                #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"interrupting-user","text":"\#(preview)","stash":""}"#
            )
        }
        if unidentifiedStop {
            // Match the live failure: old done follows the new partials, then an empty-ID stop.
            await stack.transport.releaseResponseCancellationAcknowledgements()
        }
        await stack.transport.enqueueText(unidentifiedStop
            ? #"{"type":"input_audio_buffer.speech_stopped","item_id":"","audio_end_ms":132020}"#
            : #"{"type":"input_audio_buffer.speech_stopped","item_id":"interrupting-user"}"#)
        await waitUntilPendingEventCount(
            stack.adapter,
            session: nextIdentity,
            minimum: 5,
            label: "pre-final interrupting turn burst"
        )
        let finalItemID = postStopCommittedItem ? "committed-after-stop" : "interrupting-user"
        for preview in ["找点乐子是", "找点乐子是什么", "找点乐子是什么呢"] {
            await stack.transport.enqueueText(
                #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"\#(finalItemID)","text":"\#(preview)","stash":""}"#
            )
        }
        let expectedFinal = unidentifiedStop ? "找点乐子是什么呢" : "找点乐子是什么"
        if !unidentifiedStop || postStopCommittedItem {
            await stack.transport.enqueueText(
                #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"\#(finalItemID)","transcript":"\#(expectedFinal)"}"#
            )
        }
        let postStopCount = postStopCommittedItem ? 1 : 4
        await waitUntilPendingEventCount(
            stack.adapter,
            session: nextIdentity,
            minimum: 5 + postStopCount,
            label: "complete interrupting turn before slow consumption"
        )
        var preFinalEvents: [RealtimeResidentBrainEvent] = []
        for _ in 0 ..< 5 {
            let disposition = try await runtime
                .receiveRealtimeResidentBrainEvent(session: nextIdentity)
            guard case .accepted(let event) = disposition else {
                fatalError("confirmed handoff burst must remain ordered")
            }
            preFinalEvents.append(event)
            if !postStopCommittedItem { try? await Task.sleep(for: .milliseconds(90)) }
        }
        expect(
            preFinalEvents.dropLast().allSatisfy {
                if case .userTranscriptPartial = $0.kind { return true }
                return false
            } && preFinalEvents.last?.kind == .userSpeechStopped,
            "queued N+1 partials and stop remain ordered under slow consumption"
        )
        await waitUntilPendingEventCount(
            stack.adapter,
            session: nextIdentity,
            minimum: postStopCount,
            label: "post-stop interrupting turn burst"
        )
        var postStopEvents: [RealtimeBrainEventDisposition] = []
        for _ in 0 ..< postStopCount {
            if !postStopCommittedItem { try? await Task.sleep(for: .milliseconds(110)) }
            postStopEvents.append(
                try await runtime.receiveRealtimeResidentBrainEvent(
                    session: nextIdentity
                )
            )
        }
        guard case .accepted(let reboundFinalEvent) = postStopEvents.last else {
            fatalError("Provider final must survive the slow N+1 burst")
        }
        expect(
            reboundFinalEvent.kind
                    == .userTranscriptFinal(expectedFinal)
                && reboundFinalEvent.identity.session == nextIdentity
                && reboundFinalEvent.identity.turnID
                    == reboundStartEvent.identity.turnID
                && runtime.realtimePendingUserInputForTesting(
                    reboundStartEvent.identity
                ) == expectedFinal,
            "Provider final remains bound to the interrupting N+1 turn"
        )
        let providerFinalEvents = diagnostics.drain().events
        expect(
            providerFinalEvents.filter {
                $0.category == "qwen_transcript_final_received"
            }.count == (unidentifiedStop && !postStopCommittedItem ? 0 : 1)
                && providerFinalEvents.filter {
                    $0.category
                        == "qwen_transcript_final_fallback_fired"
                        || $0.category
                            == "qwen_transcript_final_recovered_from_partial"
                }.count == (unidentifiedStop && !postStopCommittedItem ? 2 : 0),
            "Provider final wins when present; otherwise existing fallback recovers exactly once"
        )
        if drainTimeout {
            try await verifyPendingAnswerCase(
                pendingCase, runtime: runtime, stack: stack, diagnostics: diagnostics,
                identity: nextIdentity, original: reboundFinalEvent, barrier: catchBarrier,
                activity: listeningActivity, bytes: frameBytes
            )
            return
        }
        try await waitUntilSentTypeCount(
            stack.transport,
            type: "response.create",
            minimum: 2
        )
        let responseCreateCountAfterHandoff = try await sentTypes(
            stack.transport
        ).filter { $0 == "response.create" }.count
        expect(
            responseCreateCountAfterHandoff == 2,
            "the completed interrupting turn creates exactly one N+1 response"
        )
        if postStopCommittedItem {
            let canonical = runtime.realtimeUserTurnDispositionDebugSnapshot().lastCanonicalTranscript
            expect(canonical == expectedFinal, "committed item final equals Runtime canonical, without partial truncation")
            let creates = try await sentObjects(stack.transport).filter { $0["type"] as? String == "response.create" }
            expect(creates.count == 2 && creates.last?.keys.sorted() == ["event_id", "type"],
                   "wire sends one authorization, not a synthetic re-upload of transcript")
            print("post_stop_handoff provider_final=\(expectedFinal) adapter_final=\(expectedFinal) runtime_canonical=\(canonical ?? "nil") response_create=authorization_only")
            await stack.transport.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"committed-after-stop","transcript":"重复"}"#)
        }

        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"interrupting-user"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"interrupting-user","text":"迟到的重复内容","stash":""}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"interrupting-user","transcript":"迟到的完整内容"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.failed","item_id":"interrupting-user","error":{"code":"late_asr_failure"}}"#
        )
        try? await Task.sleep(for: .milliseconds(650))
        let responseCreateCountAfterDuplicates = try await sentTypes(
            stack.transport
        ).filter { $0 == "response.create" }.count
        expect(
            responseCreateCountAfterDuplicates == 2,
            "late duplicate events cannot create an extra response"
        )
        expect(
            diagnostics.drain().events.filter {
                $0.category
                    == "qwen_transcript_final_recovered_from_partial"
            }.isEmpty,
            "late duplicate events cannot fire a second fallback final"
        )
        let pendingEventCountAfterDuplicates = await stack.adapter
            .pendingEventCountForTesting(session: nextIdentity)
        expect(
            pendingEventCountAfterDuplicates == 0,
            "late duplicate events leave no stale user event queued"
        )
        expectRealtimeSuccess(
            await runtime.closeRealtimeResidentBrainSession(
                identity: nextIdentity
            ),
            "confirmed-handoff fixture closes"
        )
    }

    private static func verifyRecoveredPersistence(
        _ stack: (adapter: QwenRealtimeResidentBrainAdapter, transport: R3FakeRealtimeWebSocketTransport),
        runtime: RuntimeCore, identity: RealtimeBrainSessionIdentity, question: String, answer: String
    ) async throws {
        let history = try SessionStore().loadMostRecentDialogueEntries(limit: 10_000)
        expect(history.map(\.role) == ["user", "resident"] && history.map(\.text) == [question, answer],
               "recovery persists exactly one original user turn and one valid resident answer")
        let memory = runtime.narrativeMemoryDebugSnapshot()
        await stack.transport.enqueueText(#"{"type":"response.done","response":{"id":"response-tool-2","status":"completed","output":[{"id":"answer-new","type":"message","role":"assistant","content":[{"type":"text","text":"duplicate must not persist"}]}]}}"#)
        await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"after-recovery-marker"}"#)
        expectAccepted(try await runtime.receiveRealtimeResidentBrainEvent(session: identity), kind: .userSpeechStarted,
                       "duplicate completion cannot emit a second canonical response")
        let after = try SessionStore().loadMostRecentDialogueEntries(limit: 10_000)
        expect(after == history && runtime.narrativeMemoryDebugSnapshot() == memory,
               "duplicate recovered completion cannot write Session or Memory again")
    }

    private static func waitForCondition(
        _ label: String, _ predicate: @MainActor () async -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { fatalError("condition timed out: \(label)") }
            await Task.yield()
        }
    }

    private static func verifyPendingAnswerCase(
        _ scenario: R3PendingAnswerCase, runtime: RuntimeCore,
        stack: (adapter: QwenRealtimeResidentBrainAdapter, transport: R3FakeRealtimeWebSocketTransport),
        diagnostics: NativeSpeechDiagnosticBuffer, identity: RealtimeBrainSessionIdentity,
        original: RealtimeResidentBrainEvent, barrier: R3ResponseCatchBarrier,
        activity: RealtimeBrainLocalAudioActivity, bytes: Data
    ) async throws {
        FileHandle.standardError.write(Data("pending_answer_case=\(scenario.rawValue)\n".utf8))
        let lease = runtime.activeBrainLeaseForTesting()
        let historyBefore = try SessionStore().loadMostRecentDialogueEntries(limit: 10_000)
        await waitForCondition("formal semantic completion admits pending answer") {
            runtime.realtimePendingAnswerForTesting() != nil
        }
        guard let initial = runtime.realtimePendingAnswerForTesting() else {
            fatalError("Runtime must retain exactly one pending question before ACK timeout")
        }
        expect(initial.turnID == original.identity.turnID && initial.state.submission == .notSubmitted,
               "pending question carries the original logical authorization and submission receipt")
        await waitForCondition("old response ACK wait registered") {
            !(await stack.adapter.responseDoneWaiterIDsForTesting("response-tool-1")).isEmpty
        }
        let oldWaiters = await stack.adapter.responseDoneWaiterIDsForTesting("response-tool-1")
        if [.expiryAfterSubmission, .expiryDuringWrite, .expiryBeforeSubmission,
            .cancelledOperationDrain, .cancelledStopDrain, .cancelledContextDrain,
            .cancelledContextGenerationDrain].contains(scenario) {
            await barrier.waitForEntry()
            let sendsBeforeExpiry = scenario == .expiryAfterSubmission || scenario == .expiryDuringWrite
            var timeoutPresentations = 0
            runtime.setRealtimePendingAnswerPresentationHandler { _, error in
                if error == .timedOut { timeoutPresentations += 1 }
            }
            if sendsBeforeExpiry {
                await stack.adapter.setResponseCatchBarrierForTesting(nil)
                await stack.transport.holdResponseCreationAcknowledgements()
                let writeBarrier = R3ResponseCatchBarrier()
                if scenario == .expiryDuringWrite {
                    await stack.transport.setResponseCreateWriteBarrier { await writeBarrier.suspend() }
                }
                await barrier.release()
                await stack.transport.releaseResponseCancellationAcknowledgements()
                await waitForCondition("response.create written, ACK held") {
                    runtime.realtimePendingAnswerForTesting()?.state.submission == (scenario == .expiryDuringWrite ? .uncertain : .submitted)
                }
                if scenario == .expiryDuringWrite { await writeBarrier.waitForEntry() }
                let exitBarrier = R3ResponseCatchBarrier()
                await stack.adapter.setResponseCatchBarrierForTesting { await exitBarrier.suspend() }
                runtime.expireRealtimePendingAnswerForTesting(id: initial.id, now: initial.deadline)
                expect(timeoutPresentations == 0, "submitted or uncertain expiry cannot present ordinary Listening")
                let disposition = try await runtime.receiveRealtimeResidentBrainEvent(session: identity)
                if case .accepted = disposition { expect(false, "expired submitted attempt must fence output immediately") }
                else { expect(true, "expired submitted attempt fences output before Adapter exits") }
                if scenario == .expiryDuringWrite {
                    await stack.transport.setResponseCreateWriteBarrier(nil)
                    await writeBarrier.release()
                }
                await exitBarrier.waitForEntry()
                expect(runtime.realtimeProviderOperationsForTesting().operations == 1, "expiry keeps operation until call exits")
                await stack.adapter.setResponseCatchBarrierForTesting(nil)
                await exitBarrier.release()
                await runtime.waitForRealtimePendingAnswerDrainForTesting()
                let isolated = runtime.activeBrainLeaseForTesting() == nil
                FileHandle.standardError.write(Data("P1_A_expired_submitted_session_isolated=\(isolated)\n".utf8))
                expect(isolated, "submitted expiry must settle the failed Runtime session even after pending is removed")
                let closeCount = await stack.transport.closeCount()
                expect(closeCount == 1, "Runtime failure settlement closes exactly once")
            } else if scenario == .expiryBeforeSubmission {
                runtime.expireRealtimePendingAnswerForTesting(id: initial.id, now: initial.deadline)
                expect(timeoutPresentations == 1, "definitely unsubmitted expiry reports failure once")
                await stack.transport.releaseResponseCancellationAcknowledgements()
                await stack.adapter.setResponseCatchBarrierForTesting(nil)
                await barrier.release()
                await runtime.waitForRealtimePendingAnswerDrainForTesting()
                expect(runtime.activeBrainLeaseForTesting() == lease, "unsubmitted expiry keeps the current session")
                expectRealtimeSuccess(await runtime.closeRealtimeResidentBrainSession(identity: identity), "unsubmitted expiry closes normally")
            } else {
                var completed = false
                let transition = Task { @MainActor in
                    let result: Result<RealtimeBrainSessionIdentity, RealtimeResidentBrainError>
                    if scenario == .cancelledStopDrain {
                        result = await runtime.closeRealtimeResidentBrainSession(identity: identity).map { identity }
                    } else if scenario == .cancelledContextDrain || scenario == .cancelledContextGenerationDrain {
                        result = await runtime.updateRealtimeResidentBrainContext(RealtimeBrainRuntimeContextUpdate(
                            identity: identity, kind: .delta, contextRevision: 2,
                            sections: [RealtimeBrainContextSection(scope: .dynamicSession, content: "replacement")]
                        )).map { identity }
                    } else {
                        runtime.expireRealtimePendingAnswerForTesting(id: initial.id, now: initial.deadline)
                        result = await runtime.cancelRealtimeResidentBrainGenerationForTesting(identity: identity, reason: .runtimeDecision)
                    }
                    completed = true
                    return result
                }
                let contextDrain = scenario == .cancelledContextDrain || scenario == .cancelledContextGenerationDrain
                await waitForCondition("generation either drains or incorrectly escapes") {
                    completed || (contextDrain ? runtime.realtimePendingAnswerForTesting() == nil
                        : runtime.realtimeProviderOperationsForTesting().waiters > 0)
                }
                let waited = !completed
                let retained = runtime.realtimeProviderOperationsForTesting().operations >= 1
                var concurrentGeneration: Task<Result<RealtimeBrainSessionIdentity, RealtimeResidentBrainError>, Never>?
                if scenario == .cancelledContextGenerationDrain {
                    concurrentGeneration = Task { @MainActor in
                        await runtime.cancelRealtimeResidentBrainGenerationForTesting(identity: identity, reason: .runtimeDecision)
                    }
                    await waitForCondition("generation waits for old call without a context-operation cycle") {
                        runtime.realtimeProviderOperationsForTesting().waiters > 0
                    }
                    expect(runtime.realtimeProviderOperationsForTesting().operations == 2, "only old call and generation operation are reserved")
                }
                await stack.adapter.setResponseCatchBarrierForTesting(nil)
                await barrier.release()
                let result = await transition.value
                FileHandle.standardError.write(Data("P1_B_operation_retained=\(retained) generation_waited=\(waited) result=\(result)\n".utf8))
                expect(retained && waited, "Task.cancel must not release the Provider operation before Adapter exits")
                let next: RealtimeBrainSessionIdentity
                if let concurrentGeneration {
                    expect(result == .failure(.invalidContextRevision), "context callback cannot update a transitioning generation")
                    next = try realtimeIdentity(await concurrentGeneration.value)
                } else {
                    next = try realtimeIdentity(result)
                }
                expectRealtimeSuccess(await runtime.closeRealtimeResidentBrainSession(identity: next), "drained generation closes")
            }
            let types = try await sentTypes(stack.transport)
            expect(types.filter { $0 == "response.create" }.count == (sendsBeforeExpiry ? 2 : 1), "no retry or expired submission")
            expect(types.filter { $0 == "response.cancel" }.count == 1, "no extra interrupt")
            expect(runtime.realtimeProviderOperationsForTesting().operations == 0, "no leaked Provider operations")
            let history = try SessionStore().loadMostRecentDialogueEntries(limit: 10_000)
            expect(history == historyBefore, "expired question never persists")
            print("pending_answer_\(scenario.rawValue)=PASS duplicate_answer=0 stale_output=0")
            return
        }
        let (expired, expiryNotice) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        runtime.setRealtimePendingAnswerPresentationHandler { _, error in
            if error == .timedOut { expiryNotice.yield(); expiryNotice.finish() }
        }
        if scenario != .doneBeforeTimeout && scenario != .supersedeDuringWait {
            await barrier.waitForEntry()
            if scenario == .doneBeforeCatch {
                await stack.transport.releaseResponseCancellationAcknowledgements()
                await waitForCondition("old done before request catch") {
                    !(await stack.adapter.hasRetiringResponseForTesting())
                }
            }
            await stack.adapter.setResponseCatchBarrierForTesting(nil)
            await barrier.release()
            await waitForCondition("original request catch finished") {
                !(await stack.adapter.hasResponseRequestForTesting())
            }
        }
        expect(runtime.realtimePendingUserInputForTesting(original.identity) == "找点乐子是什么",
               "the ACK wait never consumes the unanswered question")
        expect(runtime.activeBrainLeaseForTesting() == lease, "ACK lateness does not replace lease or generation")
        let beforeReady = try await sentTypes(stack.transport)
        if scenario != .doneBeforeCatch {
            expect(beforeReady.filter { $0 == "response.create" }.count == 1,
                   "not-submitted question is not sent while the old response is unresolved")
        }

        if scenario == .identityCollision || scenario == .identityCollisionAfterSubmission {
            let submitted = scenario == .identityCollisionAfterSubmission
            if submitted {
                await stack.transport.releaseResponseCancellationAcknowledgements()
                try await waitUntilSentTypeCount(stack.transport, type: "response.create", minimum: 2)
                await waitForCondition("new question submitted before late collision") {
                    runtime.realtimePendingAnswerForTesting() == nil
                }
            }
            let memoryBefore = runtime.narrativeMemoryDebugSnapshot()
            expect(runtime.realtimeUserTurnDispositionDebugSnapshot().lastCanonicalTranscript == "找点乐子是什么",
                   "finalized user B is canonical before the late collision")
            let collision = submitted
                ? #"{"type":"response.audio_transcript.delta","response_id":"response-tool-1","output_index":0,"item_id":"interrupting-user","delta":"old assistant words"}"#
                : #"{"type":"response.output_item.done","response_id":"response-tool-1","output_index":0,"item":{"id":"interrupting-user","type":"message","role":"assistant"}}"#
            await stack.transport.enqueueText(collision)
            await waitForCondition("cross-role collision makes the wire session terminal") {
                await stack.adapter.terminalErrorForTesting(session: identity) == .invalidEvent
                    || runtime.activeBrainLeaseForTesting() == nil
            }
            await stack.transport.releaseResponseCancellationAcknowledgements()
            await stack.transport.enqueueText(#"{"type":"response.done","response":{"id":"response-tool-2","status":"completed","output":[{"id":"new-assistant-output","type":"message","role":"assistant","content":[{"type":"text","text":"you said the old assistant words"}]}]}}"#)
            do {
                let disposition = try await runtime.receiveRealtimeResidentBrainEvent(session: identity)
                expect(disposition == .rejectedClosed, "a failed wire cannot deliver a new resident completion")
            } catch {
                expect(error as? RealtimeResidentBrainError == .invalidEvent,
                       "Runtime receives the terminal identity error")
            }
            await waitForCondition("Runtime closes the failed provider session") {
                runtime.activeBrainLeaseForTesting() == nil
            }
            expect(runtime.realtimePendingAnswerForTesting() == nil,
                   "failed session cannot retain an automatic response retry")
            expect(runtime.realtimeUserTurnDispositionDebugSnapshot().lastCanonicalTranscript == "找点乐子是什么",
                   "session failure does not overwrite or reclassify canonical user B")
            expect(runtime.narrativeMemoryDebugSnapshot() == memoryBefore,
                   "new response from the corrupt session cannot write Memory")
            let history = try SessionStore().loadMostRecentDialogueEntries(limit: 10_000)
            expect(history == historyBefore, "neither old nor new corrupt-session output persists")
            let types = try await sentTypes(stack.transport)
            expect(types.filter { $0 == "response.create" }.count == (submitted ? 2 : 1)
                && types.filter { $0 == "response.cancel" }.count == 1,
                "failure creates no extra response or interruption")
            expect(diagnostics.drain().events.contains {
                $0.category == "qwen_receive_failure"
                    && ($0.disposition ?? "").contains("branch=assistant_output_identity")
            }, "late user collision is a terminal protocol failure, not only stale diagnostics")
            print("corrupt_wire_session=PASS case=\(scenario.rawValue) canonical_user=preserved persistence_delta=0 extra_response=0")
            return
        }

        func append(_ sequence: UInt64) async {
            expectRealtimeSuccess(await runtime.appendRealtimeResidentBrainAudio(RealtimeBrainAudioFrame(
                identity: identity, sequence: sequence, timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                format: RealtimeBrainAudioFormat(encoding: .pcm16LittleEndian, sampleRate: 16_000, channelCount: 1),
                provenance: .acousticEchoProcessed, bytes: bytes
            ), activity: activity), "formal input continues while waiting")
        }

        if scenario != .context { await append(1) }
        var expectedIdentity = original.identity
        var expectedQuestion = "找点乐子是什么"
        let supersedes = scenario == .supersede || scenario == .supersedeDuringWait
        if scenario == .speechPause || supersedes {
            await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"new-pending-question"}"#)
            guard case .accepted(let started) = try await runtime.receiveRealtimeResidentBrainEvent(session: identity) else {
                fatalError("new speech must be received while the original answer is waiting")
            }
            expect(started.kind == .userSpeechStarted, "new speech pauses old submission")
            expect(runtime.realtimePendingAnswerForTesting()?.state.permitted == false,
                   "new speech revokes submission permission before a late done can arrive")
            if supersedes {
                for sequence in 2 ... 5 {
                    try await Task.sleep(for: .milliseconds(20))
                    await append(UInt64(sequence))
                }
                await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"new-pending-question"}"#)
                _ = try await runtime.receiveRealtimeResidentBrainEvent(session: identity)
                _ = try await receiveRuntimeTranscript(stack, runtime: runtime, identity: identity,
                    itemID: "new-pending-question", transcript: "改问今天该做什么")
                await waitForCondition("new substantive question supersedes original") {
                    runtime.realtimePendingAnswerForTesting()?.turnID == started.identity.turnID
                }
                expectedIdentity = started.identity
                expectedQuestion = "改问今天该做什么"
                expect(runtime.realtimePendingUserInputForTesting(original.identity) == nil,
                       "superseded input is explicitly retired, not persisted or silently dropped as overlap")
                runtime.expireRealtimePendingAnswerForTesting(id: initial.id, now: initial.deadline)
                expect(runtime.realtimePendingAnswerForTesting()?.turnID == started.identity.turnID,
                       "old expiry callback cannot expire the new question")
                if scenario == .supersedeDuringWait {
                    guard let oldWaiter = oldWaiters.first else { fatalError("original ACK waiter must exist") }
                    await waitForCondition("new attempt owns a different ACK waiter") {
                        let ids = await stack.adapter.responseDoneWaiterIDsForTesting("response-tool-1")
                        return !ids.isEmpty && !ids.contains(oldWaiter)
                    }
                    let newWaiters = await stack.adapter.responseDoneWaiterIDsForTesting("response-tool-1")
                    await stack.adapter.fireResponseDoneTimeoutForTesting("response-tool-1", waiterID: oldWaiter)
                    let remaining = await stack.adapter.responseDoneWaiterIDsForTesting("response-tool-1")
                    expect(remaining == newWaiters, "old timer cannot remove or resume a new attempt's waiter")
                }
            }
        }

        if scenario == .stop {
            expectRealtimeSuccess(await runtime.closeRealtimeResidentBrainSession(identity: identity), "Stop cancels pending without old done")
            let next = try realtimeIdentity(await runtime.openRealtimeResidentBrainSession())
            expectRealtimeSuccess(await runtime.updateRealtimeResidentBrainContext(RealtimeBrainRuntimeContextUpdate(
                identity: next, kind: .bootstrap, contextRevision: 1,
                sections: [RealtimeBrainContextSection(scope: .stableResident, content: "restart")]
            )), "Restart is independent of old pending")
            expectAccepted(try await runtime.receiveRealtimeResidentBrainEvent(session: next), kind: .sessionReady, "restart ready")
            await stack.transport.releaseResponseCancellationAcknowledgements()
            runtime.expireRealtimePendingAnswerForTesting(id: initial.id, now: initial.deadline)
            expect(runtime.realtimePendingAnswerForTesting() == nil, "Stop/restart cannot resurrect pending")
            expectRealtimeSuccess(await runtime.closeRealtimeResidentBrainSession(identity: next), "restart closes")
        } else if scenario == .expiry || scenario == .speechPause {
            if scenario == .speechPause {
                await stack.transport.releaseResponseCancellationAcknowledgements()
                await waitForCondition("readiness does not override speech pause") {
                    runtime.realtimePendingAnswerForTesting()?.state.providerReady == true
                }
                expect(runtime.realtimePendingAnswerForTesting()?.id == initial.id, "same question remains paused")
            }
            expect(runtime.realtimePendingAnswerForTesting()?.deadline == initial.deadline, "total deadline never rolls forward")
            if scenario == .expiry {
                // Exercise the actual production 15-second deadline, not a shortened test timeout.
                for await _ in expired { break }
                expect(ContinuousClock.now >= initial.deadline
                    && ContinuousClock.now < initial.deadline.advanced(by: .seconds(2)),
                       "never-arriving done exits at the real fixed total deadline")
            } else {
                runtime.expireRealtimePendingAnswerForTesting(id: initial.id, now: initial.deadline)
            }
            expect(runtime.realtimePendingAnswerForTesting() == nil
                && runtime.realtimePendingUserInputForTesting(original.identity) == nil,
                   "fixed total deadline explicitly fails the question without persisting it")
            await stack.transport.releaseResponseCancellationAcknowledgements()
            expectRealtimeSuccess(await runtime.closeRealtimeResidentBrainSession(identity: identity), "expired pending remains stoppable")
        } else if scenario == .context {
            expectRealtimeSuccess(await runtime.updateRealtimeResidentBrainContext(RealtimeBrainRuntimeContextUpdate(
                identity: identity, kind: .delta, contextRevision: 2,
                sections: [RealtimeBrainContextSection(scope: .dynamicSession, content: "updated context")]
            )), "context replacement invalidates unsubmitted question")
            await stack.transport.releaseResponseCancellationAcknowledgements()
            runtime.expireRealtimePendingAnswerForTesting(id: initial.id, now: initial.deadline)
            expect(runtime.realtimePendingAnswerForTesting() == nil, "old context never resubmits")
            expectRealtimeSuccess(await runtime.closeRealtimeResidentBrainSession(identity: identity), "context test closes")
        } else if scenario == .generation {
            let next = try realtimeIdentity(await runtime.cancelRealtimeResidentBrainGenerationForTesting(identity: identity, reason: .runtimeDecision))
            runtime.expireRealtimePendingAnswerForTesting(id: initial.id, now: initial.deadline)
            expect(runtime.realtimePendingAnswerForTesting() == nil, "new generation rejects old timer")
            expectRealtimeSuccess(await runtime.closeRealtimeResidentBrainSession(identity: next), "generation test closes")
        } else {
            await stack.transport.releaseResponseCancellationAcknowledgements()
            try await waitUntilSentTypeCount(stack.transport, type: "response.create", minimum: 2)
            await waitForCondition("pending question successfully submitted once") { runtime.realtimePendingAnswerForTesting() == nil }
            let memoryBefore = runtime.narrativeMemoryDebugSnapshot()
            for _ in 0 ..< 20 {
                await stack.transport.enqueueText(#"{"type":"response.output_item.done","response_id":"response-tool-1","output_index":0,"item":{"id":"assistant-old","type":"message","role":"assistant"}}"#)
                await stack.transport.enqueueText(#"{"type":"response.audio.delta","response_id":"response-tool-1","delta":"AAA="}"#)
                await stack.transport.enqueueText(#"{"type":"response.audio_transcript.delta","response_id":"response-tool-1","delta":"stale"}"#)
                await stack.transport.enqueueText(#"{"type":"response.done","response":{"id":"response-tool-1","status":"completed","output":[{"id":"assistant-old","type":"message","role":"assistant","content":[{"type":"text","text":"old assistant pollution"}]}]}}"#)
            }
            await stack.transport.enqueueText(#"{"type":"response.audio_transcript.delta","response_id":"response-tool-2","delta":"new reply"}"#)
            guard case .accepted(let text) = try await runtime.receiveRealtimeResidentBrainEvent(session: identity) else {
                fatalError("only new response text should be accepted")
            }
            expect(text.kind == .residentTextDelta("new reply") && text.identity.turnID == expectedIdentity.turnID,
                   "late old audio/text/done cannot resurrect or cross-bind the response")
            expect(runtime.realtimePendingUserInputForTesting(expectedIdentity) == expectedQuestion,
                   "exact canonical question survives until a real accepted answer")
            expect(runtime.narrativeMemoryDebugSnapshot() == memoryBefore,
                "late retired output cannot write Memory")
            let historyAfterLateOutput = try SessionStore().loadMostRecentDialogueEntries(limit: 10_000)
            expect(historyAfterLateOutput == historyBefore,
                "late retired output cannot persist or reclassify a finalized user")
            let completed = #"{"type":"response.done","response":{"id":"response-tool-2","status":"completed","output":[{"id":"fixture-output-4655-0","role":"assistant","type":"message","content":[{"type":"text","text":"new reply"}]}]}}"#
            await stack.transport.enqueueText(completed)
            guard case .accepted(let finalText) = try await runtime.receiveRealtimeResidentBrainEvent(session: identity),
                  case .accepted(let semantic) = try await runtime.receiveRealtimeResidentBrainEvent(session: identity) else {
                fatalError("new answer must complete through the formal canonical path")
            }
            expect(finalText.kind == .residentTextFinal("new reply")
                && semantic.kind == .residentSemanticFinal(RealtimeBrainSemanticOutput(canonicalText: "new reply")),
                   "exact new answer completes once")
            await stack.transport.enqueueText(completed)
            await stack.transport.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"after-duplicate-marker"}"#)
            expectAccepted(try await runtime.receiveRealtimeResidentBrainEvent(session: identity),
                kind: .userSpeechStarted, "duplicate completion emits no semantic event before the next input marker")
            let history = try SessionStore().loadMostRecentDialogueEntries(limit: 10_000)
            expect(history.suffix(2).map(\.text) == [expectedQuestion, "new reply"],
                   "only the correct question and actual answer reach canonical history")
            expect(history.map(\.role) == ["user", "resident"],
                "finalized B retains user role and only the new response has resident role")
            expect(history.count == 2, "this new Runtime session stores exactly one history exchange, never a stale write")
            expect(runtime.activeBrainLeaseForTesting() == lease, "re-authorization uses the same lease and generation")
            print("late_retired_output=PASS case=\(scenario.rawValue) generation_delta=0 extra_response=0 history_rows=2")
            expectRealtimeSuccess(await runtime.closeRealtimeResidentBrainSession(identity: identity), "retained question test closes")
        }
        let types = try await sentTypes(stack.transport)
        let shouldAnswer = [.doneBeforeTimeout, .doneBeforeCatch, .lateDone, .supersede, .supersedeDuringWait].contains(scenario)
        if !shouldAnswer {
            let history = try SessionStore().loadMostRecentDialogueEntries(limit: 10_000)
            expect(history == historyBefore, "failed, paused or invalidated questions cannot produce a history write")
        }
        expect(types.filter { $0 == "response.create" }.count == (shouldAnswer ? 2 : 1),
               "exactly one valid submission, zero duplicate or revived old answers")
        let finalDiagnostics = diagnostics.drain().events
        if shouldAnswer {
            expect(finalDiagnostics.contains { $0.category == "qwen_assistant_output_rejected" },
                "late output identity is explicitly rejected before ownership mutation")
        }
        let dispositions = finalDiagnostics.filter { $0.category == "runtime_pending_answer" }.map(\.disposition)
        if supersedes { expect(dispositions.filter { $0 == "superseded" }.count == 1, "superseded is explicit exactly once") }
        if scenario == .expiry || scenario == .speechPause { expect(dispositions.filter { $0 == "expired" }.count == 1, "expiry is explicit exactly once") }
        print("pending_answer_\(scenario.rawValue)=PASS duplicate_answer=0 stale_output=0")
    }

    private static func
        testRuntimeProviderTerminalPlaybackTailInterruptionHandoff(
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
               "near-tail fixture resident loads")
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
                        content: "provider-terminal playback tail"
                    )]
                )
            ),
            "near-tail fixture bootstraps"
        )
        expectAccepted(
            try await runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            kind: .sessionReady,
            "near-tail session becomes ready"
        )
        let listeningActivity = RealtimeBrainLocalAudioActivity(
            kind: .listeningNearEnd,
            residentPlaybackSequence: 0,
            residentPlaybackActive: false,
            lastAudibleResidentRenderTimestampNanoseconds: nil,
            sourceGateEpoch: 0,
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
        let frameBytes = pcm16(Array(repeating: 400, count: 320))
        var timestamp = DispatchTime.now().uptimeNanoseconds
        expectRealtimeSuccess(
            await runtime.appendRealtimeResidentBrainAudio(
                RealtimeBrainAudioFrame(
                    identity: identity,
                    sequence: 1,
                    timestampNanoseconds: timestamp,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: 16_000,
                        channelCount: 1
                    ),
                    provenance: .acousticEchoProcessed,
                    bytes: frameBytes
                ),
                activity: listeningActivity
            ),
            "near-tail initial audio establishes the turn boundary"
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"near-tail-initial-user"}"#
        )
        expectAccepted(
            try await runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            kind: .userSpeechStarted,
            "near-tail initial listening turn starts"
        )
        for sequence in 2 ... 5 {
            try? await Task.sleep(for: .milliseconds(20))
            timestamp = DispatchTime.now().uptimeNanoseconds
            expectRealtimeSuccess(
                await runtime.appendRealtimeResidentBrainAudio(
                    RealtimeBrainAudioFrame(
                        identity: identity,
                        sequence: UInt64(sequence),
                        timestampNanoseconds: timestamp,
                        format: RealtimeBrainAudioFormat(
                            encoding: .pcm16LittleEndian,
                            sampleRate: 16_000,
                            channelCount: 1
                        ),
                        provenance: .acousticEchoProcessed,
                        bytes: frameBytes
                    ),
                    activity: listeningActivity
                ),
                "near-tail listening audio remains continuous"
            )
        }
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"near-tail-initial-user"}"#
        )
        _ = try await runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        await stack.transport.useNextResponseID("near-tail-old-response")
        _ = try await receiveRuntimeTranscript(
            stack,
            runtime: runtime,
            identity: identity,
            itemID: "near-tail-initial-user",
            transcript: "请先回答"
        )
        await stack.transport.waitUntilSent(type: "response.create")
        await stack.transport.enqueueText(
            #"{"type":"response.audio.delta","response_id":"near-tail-old-response","delta":"AAA="}"#
        )
        let residentSpeaking = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        let residentAudio = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        guard case .accepted(let residentSpeakingEvent) = residentSpeaking,
              residentSpeakingEvent.kind == .residentSpeakingStarted,
              case .accepted(let residentAudioEvent) = residentAudio,
              case .residentAudioDelta = residentAudioEvent.kind else {
            fatalError("near-tail resident response must be audible")
        }
        expectRealtimeSuccess(
            runtime.registerRealtimeResidentBrainPlaybackTarget(
                residentAudioEvent.identity
            ),
            "near-tail physical playback target registers"
        )

        await stack.transport.enqueueText(
            #"{"type":"response.audio.done","response_id":"near-tail-old-response"}"#
        )
        await stack.transport.enqueueText(
            #"{"type":"response.done","response":{"id":"near-tail-old-response","status":"completed","output":[{"id":"fixture-output-4828-0","role":"assistant","type":"message","content":[{"type":"text","text":"旧回答"}]}]}}"#
        )
        let residentStopped = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        let residentText = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        let residentSemantic = try await runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        expectAccepted(
            residentStopped,
            kind: .residentSpeakingStopped,
            "near-tail Provider speech ends"
        )
        expectAccepted(
            residentText,
            kind: .residentTextFinal("旧回答"),
            "near-tail Provider text ends"
        )
        expectAccepted(
            residentSemantic,
            kind: .residentSemanticFinal(
                RealtimeBrainSemanticOutput(canonicalText: "旧回答")
            ),
            "near-tail Provider response ends"
        )
        let activeWireResponse = await stack.adapter
            .activeWireResponseIDForTesting(session: identity)
        expect(
            activeWireResponse == nil,
            "near-tail Provider response is terminal"
        )
        expect(
            runtime.realtimeInterruptionEvidenceDebugSnapshot()
                .playbackTarget == residentAudioEvent.identity,
            "near-tail old PCM remains the physical playback target"
        )

        let evidenceTimestamp = DispatchTime.now().uptimeNanoseconds
        let acousticEvidence = RealtimeInterruptionEvidence(
            identity: RealtimeInterruptionEvidenceIdentity(
                session: identity,
                turnID: residentAudioEvent.identity.turnID,
                responseID: residentAudioEvent.identity.responseID,
                contextRevision: residentAudioEvent.identity.contextRevision,
                sequence: 1,
                timestampNanoseconds: evidenceTimestamp
            ),
            source: .acousticHost(RealtimeInterruptionAcousticFacts(
                sourceGateEpoch: 1,
                nearEndDetected: true,
                farEndActive: true,
                sourceGateOpen: true,
                renderReferenceConfidence: 1,
                routeStable: true,
                inputDeviceAvailable: true,
                outputDeviceAvailable: true
            ))
        )
        guard case .success(.observed) = await runtime
            .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acousticEvidence
            ) else {
            fatalError("near-tail acoustic evidence must be observed")
        }

        let recorder = R3RealtimeEventRecorder()
        let coordinator = R3OutputBridgeInterruptionCoordinator(
            runtime: runtime,
            recorder: recorder
        )
        let outputBridge = MacSpeechRealtimeBrainOutputBridge(
            receiveEvent: { session in
                do {
                    return .success(
                        try await runtime.receiveRealtimeResidentBrainEvent(
                            session: session
                        )
                    )
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.transportFailure)
                }
            },
            consumeEvent: { event in
                await coordinator.consume(event)
            }
        )
        coordinator.bridge = outputBridge
        _ = await outputBridge.start(session: identity)
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_started","item_id":"near-tail-user"}"#
        )
        await waitUntilInterruptionTransition(coordinator)
        guard let tailStartEvent = await recorder.snapshot().first,
              tailStartEvent.kind == .userSpeechStarted,
              let decision = coordinator.decision,
              let nextIdentity = coordinator.nextIdentity else {
            fatalError("near-tail user speech must confirm interruption")
        }
        expect(
            decision.interruptedIdentity == identity
                && decision.turnID == residentAudioEvent.identity.turnID
                && decision.responseID
                    == residentAudioEvent.identity.responseID,
            "near-tail decision targets only the audible old response"
        )
        expect(
            nextIdentity.generation == identity.generation + 1,
            "near-tail interruption advances exactly one generation"
        )
        expect(
            runtime.realtimeInterruptionEvidenceDebugSnapshot()
                .playbackTarget == nil,
            "near-tail transition retires the old playback target"
        )
        let sentAfterTransition = try await sentTypes(stack.transport)
        expect(
            sentAfterTransition.filter { $0 == "response.cancel" }.isEmpty,
            "near-tail terminal response does not send Provider cancel"
        )
        expect(
            sentAfterTransition.filter {
                $0 == "input_audio_buffer.clear"
            }.isEmpty,
            "near-tail transition preserves the interrupting utterance"
        )

        for preview in ["找", "找点", "找点乐子", "找点乐子是什么"] {
            await stack.transport.enqueueText(
                #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"near-tail-user","text":"\#(preview)","stash":""}"#
            )
        }
        await waitUntilRecordedEventCount(recorder, minimum: 6)
        let transitionEvents = await recorder.snapshot()
        guard transitionEvents.count >= 2 else {
            fatalError("near-tail user turn must rebound into N+1")
        }
        let reboundStartEvent = transitionEvents[1]
        expect(
            reboundStartEvent.kind == .userSpeechStarted
                && reboundStartEvent.sequence == 1
                && reboundStartEvent.identity.session == nextIdentity
                && reboundStartEvent.identity.turnID
                    == tailStartEvent.identity.turnID,
            "near-tail handoff admits the exact user turn once"
        )
        await stack.transport.enqueueText(
            #"{"type":"input_audio_buffer.speech_stopped","item_id":"near-tail-user"}"#
        )
        await waitUntilRecordedEventCount(recorder, minimum: 7)
        let preFinalEvents = Array(
            await recorder.snapshot().dropFirst(2).prefix(5)
        )
        expect(
            preFinalEvents.dropLast().allSatisfy {
                if case .userTranscriptPartial = $0.kind { return true }
                return false
            } && preFinalEvents.last?.kind == .userSpeechStopped,
            "near-tail queued partials and stop remain ordered"
        )
        for preview in ["找点乐子是", "找点乐子是什么", "找点乐子是什么呢"] {
            await stack.transport.enqueueText(
                #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"near-tail-user","text":"\#(preview)","stash":""}"#
            )
        }
        await stack.transport.enqueueText(
            #"{"type":"conversation.item.input_audio_transcription.completed","item_id":"near-tail-user","transcript":"找点乐子是什么"}"#
        )
        await waitUntilRecordedEventCount(recorder, minimum: 11)
        guard let reboundFinalEvent = await recorder.snapshot().last else {
            fatalError("near-tail Provider final must survive the N+1 burst")
        }
        expect(
            reboundFinalEvent.kind
                    == .userTranscriptFinal("找点乐子是什么")
                && reboundFinalEvent.identity.turnID
                    == reboundStartEvent.identity.turnID,
            "near-tail Provider final stays on the rebound turn"
        )
        expect(
            runtime.realtimePendingUserInputForTesting(
                reboundStartEvent.identity
            ) == "找点乐子是什么",
            "near-tail transcript survives generation transition"
        )
        await stack.transport.waitUntilSent(type: "response.create", count: 2)
        let finalSent = try await sentTypes(stack.transport)
        expect(
            finalSent.filter { $0 == "response.create" }.count == 2,
            "near-tail rebound creates exactly one new response"
        )
        _ = await outputBridge.stop(expectedSession: nextIdentity)
        expectRealtimeSuccess(
            await runtime.closeRealtimeResidentBrainSession(
                identity: nextIdentity
            ),
            "near-tail fixture closes"
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

    private static func testSubmittedResponseTimeoutIsTerminal() async throws {
        for uncertain in [false, true] {
            cases += 1
            let diagnostics = NativeSpeechDiagnosticBuffer()
            let stack = try makeStack(diagnosticBuffer: diagnostics)
            let identity = sessionIdentity(generation: 41)
            try await openAndBootstrap(stack, identity: identity)
            await stack.transport.enqueueText(
                #"{"type":"input_audio_buffer.speech_started","item_id":"submitted-timeout-user"}"#
            )
            let speech = try await stack.adapter.receiveEvent(session: identity)
            if uncertain { await stack.transport.failNextResponseCreationWrite() }
            else { await stack.transport.holdResponseCreationAcknowledgements() }
            let command = RealtimeBrainCreateResponseCommand(identity: speech.identity, sourceEventSequence: speech.sequence)
            do {
                try await stack.adapter.createResponse(command)
                fatalError("submission fault expected")
            } catch let failure as RealtimeBrainResponseAttemptFailure {
                expect(failure.attemptID == command.attempt.id
                    && failure.submission == (uncertain ? .uncertain : .submitted)
                    && failure.error == (uncertain ? .transportFailure : .timedOut),
                       "submitted and uncertain outcomes carry typed non-retryable receipts")
            }
            let sent = try await sentTypes(stack.transport)
            expect(sent.filter { $0 == "response.create" }.count == 1,
                   "submitted or uncertain request is never retried")
            expect(diagnostics.drain().events.allSatisfy { $0.category != "qwen_response_not_submitted" },
                   "unknown outcome cannot be mislabeled as unsent")
            try await stack.adapter.closeSession(RealtimeBrainCloseSessionCommand(identity: identity))
        }
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

        let missingStack = try makeStack()
        await missingStack.transport.useMissingTurnDetectionAcknowledgement()
        await expectRealtimeError(.invalidEvent) {
            try await missingStack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(
                    identity: sessionIdentity(generation: 2)
                )
            )
        }
        let missingCloseCount = await missingStack.transport.closeCount()
        expect(
            missingCloseCount == 1,
            "missing Provider VAD policy acknowledgement fails closed"
        )

        let missingThresholdStack = try makeStack()
        await missingThresholdStack.transport
            .useMissingThresholdTurnDetectionAcknowledgement()
        await expectRealtimeError(.invalidEvent) {
            try await missingThresholdStack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(
                    identity: sessionIdentity(generation: 3)
                )
            )
        }
        let missingThresholdCloseCount = await missingThresholdStack
            .transport.closeCount()
        expect(
            missingThresholdCloseCount == 1,
            "incomplete Provider VAD policy acknowledgement fails closed"
        )

        let wrongThresholdStack = try makeStack()
        await wrongThresholdStack.transport
            .useWrongThresholdTurnDetectionAcknowledgement()
        await expectRealtimeError(.invalidEvent) {
            try await wrongThresholdStack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(
                    identity: sessionIdentity(generation: 4)
                )
            )
        }
        let wrongThresholdCloseCount = await wrongThresholdStack.transport
            .closeCount()
        expect(
            wrongThresholdCloseCount == 1,
            "Provider VAD threshold mismatch fails closed"
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
            #"{"type":"response.done","response":{"id":"\#(responseID)","status":"completed","output":[{"id":"fixture-output-5421-0","role":"assistant","type":"message","content":[\#(responseDoneContent)]}]}}"#
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

    private static func waitUntilPendingEventCount(
        _ adapter: QwenRealtimeResidentBrainAdapter,
        session: RealtimeBrainSessionIdentity,
        minimum: Int,
        label: String
    ) async {
        for _ in 0 ..< 5_000 {
            if await adapter.pendingEventCountForTesting(session: session)
                >= minimum {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Adapter did not enqueue \(label)")
    }

    private static func waitUntilRecordedEventCount(
        _ recorder: R3RealtimeEventRecorder,
        minimum: Int
    ) async {
        for _ in 0 ..< 2_000 {
            if await recorder.snapshot().count >= minimum {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Output Bridge did not consume the expected event burst")
    }

    @MainActor
    private static func waitUntilInterruptionTransition(
        _ coordinator: R3OutputBridgeInterruptionCoordinator
    ) async {
        for _ in 0 ..< 2_000 {
            if coordinator.nextIdentity != nil {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Output Bridge did not enter the generation transition")
    }

    private static func waitUntilSentTypeCount(
        _ transport: R3FakeRealtimeWebSocketTransport,
        type: String,
        minimum: Int
    ) async throws {
        for _ in 0 ..< 1_500 {
            if try await sentTypes(transport).filter({ $0 == type }).count
                >= minimum {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("transport did not send \(minimum) bounded \(type) frames")
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
        } catch let failure as RealtimeBrainResponseAttemptFailure {
            expect(failure.error == expected, "expected typed attempt error \(expected)")
        } catch {
            expect(false, "unexpected error \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("check failed: \(message)") }
    }
}
