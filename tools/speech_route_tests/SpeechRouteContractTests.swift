import Foundation

private struct TestCredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "test-credential"
    }
}

private final class TestTextTransport: ProviderHTTPTransport {
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { capturedRequests.append(request) }
        let reply = #"{"reply_text":"canonical response","expression_state":"neutral","expression_intensity":0}"#
        let body: [String: Any] = [
            "choices": [["message": ["content": reply]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func requests() -> [URLRequest] {
        lock.withLock { capturedRequests }
    }
}

private actor TestASRProvider: ASRProvider {
    private var events: [ASREvent] = []
    private(set) var inputs: [ASRAudioInput] = []
    private(set) var cancelledGenerations: [UInt64] = []
    private(set) var closedGenerations: [UInt64] = []

    func start(request: ASRStartRequest) async throws {
        events = [
            ASREvent(
                generation: request.generation,
                kind: .speechActivity(.started)
            ),
            ASREvent(
                generation: request.generation,
                kind: .partialTranscript("hello")
            ),
            ASREvent(
                generation: request.generation,
                kind: .finalTranscript("hello resident")
            )
        ]
    }

    func send(_ input: ASRAudioInput) async throws {
        inputs.append(input)
    }

    func receive(generation: UInt64) async throws -> ASREvent {
        guard !events.isEmpty else {
            throw SpeechRouteError.invalidEvent
        }
        return events.removeFirst()
    }

    func cancel(generation: UInt64) async throws {
        cancelledGenerations.append(generation)
        events.append(ASREvent(generation: generation, kind: .cancelled))
    }

    func close(generation: UInt64) async throws {
        closedGenerations.append(generation)
    }
}

private actor TestTTSProvider: TTSProvider {
    private var events: [TTSEvent] = []
    private var activeGeneration: UInt64?
    private(set) var requests: [TTSSynthesisRequest] = []
    private(set) var cancelledGenerations: [UInt64] = []
    private(set) var closedGenerations: [UInt64] = []

    func start(request: TTSSynthesisRequest) async throws {
        guard activeGeneration == nil else {
            throw SpeechRouteError.invalidConfiguration
        }
        activeGeneration = request.generation
        requests.append(request)
        events = [
            TTSEvent(generation: request.generation, kind: .started),
            TTSEvent(
                generation: request.generation,
                kind: .audio(TTSAudioChunk(
                    generation: request.generation,
                    sequenceNumber: 1,
                    bytes: Data([0x01, 0x02]),
                    format: .pcm16,
                    sampleRate: 24_000,
                    channelCount: 1
                ))
            ),
            TTSEvent(generation: request.generation, kind: .done)
        ]
    }

    func receive(generation: UInt64) async throws -> TTSEvent {
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        guard !events.isEmpty else {
            throw SpeechRouteError.invalidEvent
        }
        return events.removeFirst()
    }

    func cancel(generation: UInt64) async throws {
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        cancelledGenerations.append(generation)
        activeGeneration = nil
        events.append(TTSEvent(generation: generation, kind: .cancelled))
    }

    func close(generation: UInt64) async throws {
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        closedGenerations.append(generation)
        activeGeneration = nil
    }
}

@main
@MainActor
private struct SpeechRouteContractTests {
    private static var checks = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let asr = TestASRProvider()
        let tts = TestTTSProvider()
        let textTransport = TestTextTransport()
        let router = ProviderRouter(
            credentialReader: TestCredentialReader(),
            transport: textTransport,
            asrProvider: asr,
            ttsProvider: tts
        )
        let sessionStore = SessionStore()
        let executionEngine = ExecutionEngine(providerRouter: router)
        let runtime = RuntimeCore(
            executionEngine: executionEngine,
            providerRouter: router,
            sessionStore: sessionStore
        )

        expect(runtime.loadDR(from: fixture).isLoaded, "resident loads")
        expect(
            runtime.configureTextProvider(profile: ProviderProfile(
                profileID: "text-profile",
                providerID: "text-provider",
                adapterType: "openai_compatible",
                modelID: "existing-model",
                baseURL: "https://example.invalid/v1",
                keyRef: "keychain://test/text",
                enabled: true,
                timeout: 5,
                stream: false,
                thinkingMode: "disabled"
            )) == nil,
            "existing text ProviderRouter configures"
        )

        let generation = try success(
            await runtime.startSpeechRouteASR(locale: "en-US")
        )
        let input = ASRAudioInput(
            generation: generation,
            sequenceNumber: 1,
            bytes: Data([0x01, 0x02]),
            format: .pcm16,
            sampleRate: 16_000,
            channelCount: 1,
            source: .aec3Processed
        )
        try await runtime.sendSpeechRouteASRAudio(input)
        let asrInputs = await asr.inputs
        expect(asrInputs == [input], "AEC-processed PCM reaches ASR")

        let activity = try await runtime.receiveSpeechRouteASREvent(
            generation: generation
        )
        expect(
            activity.kind == .speechActivity(.started),
            "ASR exposes speech activity"
        )
        let partial = try await runtime.receiveSpeechRouteASREvent(
            generation: generation
        )
        expect(
            partial.kind == .partialTranscript("hello"),
            "ASR exposes partial transcript"
        )
        expectTurnFailure(
            await runtime.submitSpeechRouteASRFinal(partial),
            equals: .invalidASREvent,
            "partial cannot create a formal turn"
        )
        let unreceivedFinal = ASREvent(
            generation: generation,
            kind: .finalTranscript("hello resident")
        )
        expectTurnFailure(
            await runtime.submitSpeechRouteASRFinal(unreceivedFinal),
            equals: .invalidASREvent,
            "an unreceived final cannot create a formal turn"
        )
        expect(
            textTransport.requests().isEmpty,
            "rejected ASR events never reach the text provider"
        )
        let final = try await runtime.receiveSpeechRouteASREvent(
            generation: generation
        )
        expect(
            final.kind == .finalTranscript("hello resident"),
            "ASR exposes final transcript"
        )
        _ = try success(await runtime.finishSpeechRouteASR(
            generation: generation
        ))

        let interactionID = UUID()
        let turn = try turnSuccess(await runtime.submitSpeechRouteASRFinal(
            final,
            interactionID: interactionID
        ))
        expect(
            turn.canonicalResponseText == "canonical response",
            "existing RuntimeCore LLM produces canonical response"
        )
        expect(
            turn.canonicalResponseText == turn.reply.replyText,
            "canonical response is the sole resident text output"
        )
        expect(
            textTransport.requests().count == 1,
            "one locked final creates one existing text-provider request"
        )
        var orchestration = runtime.runtimeOrchestrationSnapshot().first {
            $0.id == interactionID
        }
        let completedSteps = orchestration?.steps.filter {
            $0.status == .completed
        }.map(\.kind) ?? []
        expect(
            orchestration?.result == .success
                && orchestration?.sessionWriteStatus == .skipped,
            "speech final uses the formal RuntimeCore orchestration"
        )
        expect(
            completedSteps.contains(.contextCompiled)
                && completedSteps.contains(.memoryChecked)
                && completedSteps.contains(.providerRouted)
                && completedSteps.contains(.requestCompleted),
            "formal turn compiles context, checks memory and routes"
        )
        expect(
            orchestration?.steps.first(where: {
                $0.kind == .sessionPersisted
            })?.status == .pending,
            "speech persistence waits for playback completion"
        )
        let ttsRequestsAfterFormalTurn = await tts.requests
        expect(ttsRequestsAfterFormalTurn.isEmpty, "A3 does not start TTS")

        let dialogueBeforePlayback = try sessionStore
            .loadMostRecentDialogueEntries()
        expect(
            dialogueBeforePlayback.isEmpty,
            "canonical response does not persist before playback"
        )

        let ttsRequest = TTSSynthesisRequest(
            generation: generation,
            canonicalResponseText: turn.canonicalResponseText,
            voiceProfile: SpeechVoiceProfile(
                profileID: "resident-default",
                locale: "en-US"
            ),
            emotion: "calm",
            pace: 0.95,
            style: "conversational"
        )
        expectFailure(
            await runtime.startSpeechRouteTTS(request: TTSSynthesisRequest(
                generation: generation,
                canonicalResponseText: "rewritten response",
                voiceProfile: ttsRequest.voiceProfile,
                emotion: ttsRequest.emotion,
                pace: ttsRequest.pace,
                style: ttsRequest.style
            )),
            equals: .invalidEvent,
            "TTS cannot replace RuntimeCore canonical response text"
        )
        _ = try success(await runtime.startSpeechRouteTTS(
            request: ttsRequest
        ))
        let ttsRequests = await tts.requests
        expect(
            ttsRequests == [ttsRequest],
            "RuntimeCore starts TTS with canonical response text"
        )
        let started = try await runtime.receiveSpeechRouteTTSEvent(
            generation: generation
        )
        expect(started.kind == .started, "TTS exposes started")
        let audio = try await runtime.receiveSpeechRouteTTSEvent(
            generation: generation
        )
        guard case .audio(let chunk) = audio.kind else {
            fatalError("FAILED: TTS exposes streaming PCM")
        }
        expect(chunk.bytes == Data([0x01, 0x02]), "TTS streams PCM")
        let done = try await runtime.receiveSpeechRouteTTSEvent(
            generation: generation
        )
        expect(done.kind == .done, "TTS exposes done")
        _ = try success(await runtime.finishSpeechRouteTTS(
            generation: generation
        ))

        let committed = try success(runtime.commitSpeechRoutePlayback(
            generation: generation
        ))
        expect(
            committed.canonicalResponseText == turn.canonicalResponseText,
            "playback commits the same canonical response"
        )
        let dialogue = try sessionStore.loadMostRecentDialogueEntries()
        expect(
            dialogue.suffix(2).map(\.text)
                == ["hello resident", "canonical response"],
            "completed playback reuses RuntimeCore dialogue persistence"
        )
        expectFailure(
            runtime.commitSpeechRoutePlayback(generation: generation),
            equals: .staleGeneration,
            "playback completion is idempotent"
        )
        orchestration = runtime.runtimeOrchestrationSnapshot().first {
            $0.id == interactionID
        }
        expect(
            orchestration?.sessionWriteStatus == .saved
                && orchestration?.steps.first(where: {
                    $0.kind == .sessionPersisted
                })?.status == .completed,
            "playback completion closes formal persistence"
        )
        expectTurnFailure(
            await runtime.submitSpeechRouteASRFinal(final),
            equals: .finalAlreadySubmitted,
            "the same final cannot create a duplicate turn"
        )
        expect(
            textTransport.requests().count == 1,
            "duplicate final never repeats the provider request"
        )
        expectTurnFailure(
            await runtime.submitSpeechRouteASRFinal(ASREvent(
                generation: generation,
                kind: .finalTranscript("   ")
            )),
            equals: .emptyTranscript,
            "empty final cannot create a formal turn"
        )

        let cancelledPendingGeneration = try success(
            await runtime.startSpeechRouteASR(locale: "en-US")
        )
        _ = try await runtime.receiveSpeechRouteASREvent(
            generation: cancelledPendingGeneration
        )
        _ = try await runtime.receiveSpeechRouteASREvent(
            generation: cancelledPendingGeneration
        )
        let cancelledPendingFinal = try await runtime
            .receiveSpeechRouteASREvent(
                generation: cancelledPendingGeneration
            )
        _ = try success(await runtime.finishSpeechRouteASR(
            generation: cancelledPendingGeneration
        ))
        _ = try turnSuccess(await runtime.submitSpeechRouteASRFinal(
            cancelledPendingFinal
        ))
        _ = try success(await runtime.cancelSpeechRoute(
            generation: cancelledPendingGeneration
        ))
        let dialogueAfterPendingCancel = try sessionStore
            .loadMostRecentDialogueEntries()
        expect(
            dialogueAfterPendingCancel == dialogue,
            "cancelled canonical response is not persisted before playback"
        )

        let nextGeneration = try success(
            await runtime.startSpeechRouteASR(locale: "en-US")
        )
        let stale = try await runtime.receiveSpeechRouteASREvent(
            generation: generation
        )
        expect(
            stale.kind == .staleGeneration,
            "RuntimeCore rejects stale ASR generation"
        )
        expectTurnFailure(
            await runtime.submitSpeechRouteASRFinal(final),
            equals: .staleGeneration,
            "stale final cannot create a formal turn"
        )
        expectTurnFailure(
            await runtime.submitSpeechRouteASRFinal(ASREvent(
                generation: nextGeneration,
                kind: .cancelled
            )),
            equals: .invalidASREvent,
            "cancelled ASR event cannot create a formal turn"
        )
        _ = try success(await runtime.cancelSpeechRoute(
            generation: nextGeneration
        ))
        expectTurnFailure(
            await runtime.submitSpeechRouteASRFinal(ASREvent(
                generation: nextGeneration,
                kind: .finalTranscript("cancelled final")
            )),
            equals: .staleGeneration,
            "cancelled generation cannot submit a late final"
        )
        let dialogueAfterRejectedEvents = try sessionStore
            .loadMostRecentDialogueEntries()
        expect(
            dialogueAfterRejectedEvents == dialogue,
            "rejected events do not write dialogue history"
        )
        let cancelledASRGenerations = await asr.cancelledGenerations
        expect(
            cancelledASRGenerations == [nextGeneration],
            "RuntimeCore owns ASR cancellation"
        )
        let cancelledTTSGenerations = await tts.cancelledGenerations
        expect(
            cancelledTTSGenerations.isEmpty,
            "RuntimeCore does not cancel an unstarted TTS provider"
        )

        expect(
            ASREvent(
                generation: nextGeneration,
                kind: .error(.timedOut)
            ).kind == .error(.timedOut),
            "ASR exposes provider-neutral error"
        )
        expect(
            TTSEvent(
                generation: nextGeneration,
                kind: .error(.transportFailure)
            ).kind == .error(.transportFailure),
            "TTS exposes provider-neutral error"
        )
        expect(
            ASREvent(
                generation: nextGeneration,
                kind: .cancelled
            ).kind == .cancelled,
            "ASR exposes cancelled"
        )
        expect(
            TTSEvent(
                generation: nextGeneration,
                kind: .cancelled
            ).kind == .cancelled,
            "TTS exposes cancelled"
        )

        let closeGeneration = try success(
            await runtime.startSpeechRouteASR(locale: "en-US")
        )
        _ = try success(await runtime.closeSpeechRoute(
            generation: closeGeneration
        ))
        let closedASRGenerations = await asr.closedGenerations
        expect(
            closedASRGenerations == [
                generation,
                cancelledPendingGeneration,
                closeGeneration
            ],
            "RuntimeCore closes ASR"
        )
        let closedTTSGenerations = await tts.closedGenerations
        expect(
            closedTTSGenerations == [generation],
            "RuntimeCore closes only the active TTS provider"
        )

        print("speech_route_contract_checks=\(checks)")
    }

    private static func success<T>(
        _ result: Result<T, SpeechRouteError>
    ) throws -> T {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    private static func turnSuccess(
        _ result: Result<SpeechRouteTurnResult, SpeechRouteTurnError>
    ) throws -> SpeechRouteTurnResult {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    private static func expectFailure<T>(
        _ result: Result<T, SpeechRouteError>,
        equals expected: SpeechRouteError,
        _ message: String
    ) {
        guard case .failure(let error) = result,
              error == expected else {
            fatalError("FAILED: \(message)")
        }
        checks += 1
    }

    private static func expectTurnFailure(
        _ result: Result<SpeechRouteTurnResult, SpeechRouteTurnError>,
        equals expected: SpeechRouteTurnError,
        _ message: String
    ) {
        guard case .failure(let error) = result,
              error == expected else {
            fatalError("FAILED: \(message)")
        }
        checks += 1
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
