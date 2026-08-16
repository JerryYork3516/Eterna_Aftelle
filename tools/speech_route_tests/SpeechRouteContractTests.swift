import Foundation

private struct TestCredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "test-credential"
    }
}

private final class TestTextTransport: ProviderHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
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
    private(set) var requests: [TTSSynthesisRequest] = []
    private(set) var cancelledGenerations: [UInt64] = []
    private(set) var closedGenerations: [UInt64] = []

    func start(request: TTSSynthesisRequest) async throws {
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
        guard !events.isEmpty else {
            throw SpeechRouteError.invalidEvent
        }
        return events.removeFirst()
    }

    func cancel(generation: UInt64) async throws {
        cancelledGenerations.append(generation)
        events.append(TTSEvent(generation: generation, kind: .cancelled))
    }

    func close(generation: UInt64) async throws {
        closedGenerations.append(generation)
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
        let router = ProviderRouter(
            credentialReader: TestCredentialReader(),
            transport: TestTextTransport(),
            asrProvider: asr,
            ttsProvider: tts
        )
        let sessionStore = SessionStore()
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
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
        let final = try await runtime.receiveSpeechRouteASREvent(
            generation: generation
        )
        expect(
            final.kind == .finalTranscript("hello resident"),
            "ASR exposes final transcript"
        )

        let turn = try turnSuccess(await runtime.submitSpeechRouteASRFinal(
            final,
            voiceProfile: SpeechVoiceProfile(
                profileID: "resident-default",
                locale: "en-US"
            ),
            emotion: "calm",
            pace: 0.95,
            style: "conversational"
        ))
        expect(
            turn.reply.replyText == "canonical response",
            "existing RuntimeCore LLM produces canonical response"
        )
        expect(
            turn.ttsRequest.canonicalResponseText == turn.reply.replyText,
            "TTS receives canonical response unchanged"
        )
        let ttsRequests = await tts.requests
        expect(
            ttsRequests == [turn.ttsRequest],
            "TTS receives provider-neutral voice controls"
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

        let dialogue = try sessionStore.loadMostRecentDialogueEntries()
        expect(
            dialogue.suffix(2).map(\.text)
                == ["hello resident", "canonical response"],
            "speech final reuses RuntimeCore dialogue persistence"
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
        _ = try success(await runtime.cancelSpeechRoute(
            generation: nextGeneration
        ))
        let cancelledASRGenerations = await asr.cancelledGenerations
        expect(
            cancelledASRGenerations == [nextGeneration],
            "RuntimeCore owns ASR cancellation"
        )
        let cancelledTTSGenerations = await tts.cancelledGenerations
        expect(
            cancelledTTSGenerations == [nextGeneration],
            "RuntimeCore owns TTS cancellation"
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
            closedASRGenerations == [closeGeneration],
            "RuntimeCore closes ASR"
        )
        let closedTTSGenerations = await tts.closedGenerations
        expect(
            closedTTSGenerations == [closeGeneration],
            "RuntimeCore closes TTS"
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

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
