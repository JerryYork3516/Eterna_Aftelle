import Foundation

nonisolated private final class QwenTTSTestCredentialReader:
    ProviderCredentialReading,
    @unchecked Sendable {
    let storedCredential: String?
    private let lock = NSLock()
    private var requestedReferences: [String] = []

    init(storedCredential: String?) {
        self.storedCredential = storedCredential
    }

    func readCredential(for keyRef: String) throws -> String? {
        lock.withLock { requestedReferences.append(keyRef) }
        return storedCredential
    }

    func references() -> [String] {
        lock.withLock { requestedReferences }
    }
}

@main
@MainActor
private struct QwenRealtimeTTSAdapterTests {
    private static var checks = 0

    static func main() async throws {
        try await testHandshakeControlsTextAndAudioMapping()
        try await testProviderErrorMapping()
        try await testStaleGenerationAndCancelIdempotency()
        try await testCloseIdempotency()
        print("qwen_realtime_tts_checks=\(checks)")
    }

    private static func testHandshakeControlsTextAndAudioMapping()
        async throws {
        let pcm = Data([0x01, 0x02, 0x03, 0x04])
        let transport = QwenASRFakeRealtimeWebSocketTransport(frames:
            handshake() + [
                text(#"{"type":"input_text_buffer.committed"}"#),
                text(#"{"type":"response.created"}"#),
                text("{\"type\":\"response.audio.delta\",\"delta\":\"\(pcm.base64EncodedString())\"}"),
                text(#"{"type":"response.audio.done"}"#),
                text(#"{"type":"session.finished"}"#)
            ]
        )
        let credentialReader = QwenTTSTestCredentialReader(
            storedCredential: try credential()
        )
        let adapter = makeAdapter(
            credentialReader: credentialReader,
            transport: transport
        )
        let canonical = "  Canonical resident response.  "
        try await adapter.start(request: request(
            generation: 41,
            canonical: canonical,
            locale: "zh-CN",
            emotion: "joyful",
            pace: 1.25,
            style: "intimate"
        ))

        let calls = await transport.calls
        expect(
            calls.contains(.connect(URL(
                string: "wss://workspace-123.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3-tts-instruct-flash-realtime"
            )!)),
            "workspace credential resolves the official TTS endpoint"
        )
        let bearerToken = await transport.bearerToken
        expect(
            bearerToken == "test-token",
            "credential is passed only as the transport bearer token"
        )
        expect(
            credentialReader.references() == ["keychain://test/qwen"],
            "adapter reads the configured credential reference"
        )

        let update = try sentJSON(calls, type: "session.update")
        let session = update["session"] as? [String: Any]
        expect(
            session?["voice"] as? String == "Cherry",
            "provider-neutral VoiceProfile maps through provider binding"
        )
        expect(
            session?["mode"] as? String == "commit"
                && session?["response_format"] as? String == "pcm"
                && session?["sample_rate"] as? Int == 24_000,
            "session requests commit-mode 24 kHz PCM"
        )
        expect(
            session?["language_type"] as? String == "Chinese",
            "provider-neutral locale maps to language_type"
        )
        expect(
            session?["speech_rate"] as? Double == 1.25,
            "provider-neutral pace maps to speech_rate"
        )
        expect(
            session?["instructions"] as? String
                == "Emotion: joyful. Style: intimate."
                && session?["optimize_instructions"] as? Bool == false,
            "emotion and style map only to provider speech instructions"
        )

        let append = try sentJSON(calls, type: "input_text_buffer.append")
        expect(
            append["text"] as? String == canonical,
            "canonical response text is sent byte-for-byte unchanged"
        )
        expect(
            sentTypeCount(calls, type: "input_text_buffer.commit") == 1,
            "canonical text is committed exactly once"
        )

        let started = try await adapter.receive(generation: 41)
        expect(started.kind == .started, "response.created maps to started")
        let audio = try await adapter.receive(generation: 41)
        expect(
            audio.kind == .audio(TTSAudioChunk(
                generation: 41,
                sequenceNumber: 1,
                bytes: pcm,
                format: .pcm16,
                sampleRate: 24_000,
                channelCount: 1
            )),
            "base64 audio maps to provider-neutral 24 kHz mono PCM16"
        )
        let done = try await adapter.receive(generation: 41)
        expect(done.kind == .done, "response.audio.done maps to done")
        try await adapter.close(generation: 41)
        let callsAfterClose = await transport.calls
        expect(
            callsAfterClose.contains(.close(.normal)),
            "normal close waits for session.finished"
        )
    }

    private static func testProviderErrorMapping() async throws {
        let transport = QwenASRFakeRealtimeWebSocketTransport(frames:
            handshake() + [
                text(#"{"type":"error","error":{"code":"invalid_value","message":"bad session"}}"#)
            ]
        )
        let adapter = makeAdapter(
            credentialReader: QwenTTSTestCredentialReader(
                storedCredential: try credential()
            ),
            transport: transport
        )
        try await adapter.start(request: request(generation: 2))
        let event = try await adapter.receive(generation: 2)
        expect(
            event.kind == .error(.invalidConfiguration),
            "official error event maps without leaking provider details"
        )
    }

    private static func testStaleGenerationAndCancelIdempotency()
        async throws {
        let transport = QwenASRFakeRealtimeWebSocketTransport(
            frames: handshake()
        )
        let adapter = makeAdapter(
            credentialReader: QwenTTSTestCredentialReader(
                storedCredential: try credential()
            ),
            transport: transport
        )
        try await adapter.start(request: request(generation: 7))
        let receiveCount = await transport.calls.filter {
            $0 == .receive
        }.count
        let stale = try await adapter.receive(generation: 6)
        expect(
            stale.kind == .error(.staleGeneration),
            "stale generation maps to a non-audio error"
        )
        let callsAfterStale = await transport.calls
        expect(
            callsAfterStale.filter { $0 == .receive }.count
                == receiveCount,
            "stale generation never consumes provider audio"
        )

        try await adapter.cancel(generation: 7)
        try await adapter.cancel(generation: 7)
        let cancelled = try await adapter.receive(generation: 7)
        expect(
            cancelled.kind == .cancelled,
            "cancel exposes one provider-neutral cancelled event"
        )
        let calls = await transport.calls
        expect(
            sentTypeCount(calls, type: "session.finish") == 0,
            "cancel does not request remaining audio"
        )
        expect(
            calls.filter { $0 == .close(.cancelled) }.count == 1,
            "cancel immediately closes the transport once"
        )
    }

    private static func testCloseIdempotency() async throws {
        let transport = QwenASRFakeRealtimeWebSocketTransport(
            frames: handshake() + [text(#"{"type":"session.finished"}"#)]
        )
        let adapter = makeAdapter(
            credentialReader: QwenTTSTestCredentialReader(
                storedCredential: try credential()
            ),
            transport: transport
        )
        try await adapter.start(request: request(generation: 9))
        try await adapter.close(generation: 9)
        try await adapter.close(generation: 9)
        let calls = await transport.calls
        expect(
            sentTypeCount(calls, type: "session.finish") == 1,
            "close sends session.finish once"
        )
        expect(
            calls.filter { $0 == .close(.normal) }.count == 1,
            "close is transport-idempotent"
        )
    }

    private static func makeAdapter(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport
    ) -> QwenRealtimeTTSAdapter {
        QwenRealtimeTTSAdapter(
            credentialReader: credentialReader,
            transport: transport,
            configuration: QwenRealtimeTTSConfiguration(
                endpoint: URL(
                    string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3-tts-instruct-flash-realtime"
                )!,
                modelID: "qwen3-tts-instruct-flash-realtime",
                keyRef: "keychain://test/qwen",
                voiceBindings: ["resident-default": "Cherry"]
            )
        )
    }

    private static func request(
        generation: UInt64,
        canonical: String = "Canonical response",
        locale: String? = "en-US",
        emotion: String? = nil,
        pace: Double = 1,
        style: String? = nil
    ) -> TTSSynthesisRequest {
        TTSSynthesisRequest(
            generation: generation,
            canonicalResponseText: canonical,
            voiceProfile: SpeechVoiceProfile(
                profileID: "resident-default",
                locale: locale
            ),
            emotion: emotion,
            pace: pace,
            style: style
        )
    }

    private static func credential() throws -> String {
        try QwenRealtimeCredential(
            workspaceID: "workspace-123",
            secret: "test-token"
        ).storedValue()
    }

    private static func handshake() -> [RealtimeWebSocketFrame] {
        [
            text(#"{"type":"session.created"}"#),
            text(#"{"type":"session.updated"}"#)
        ]
    }

    private static func text(_ value: String) -> RealtimeWebSocketFrame {
        .text(value)
    }

    private static func sentJSON(
        _ calls: [QwenASRFakeRealtimeWebSocketTransport.Call],
        type: String
    ) throws -> [String: Any] {
        for call in calls {
            guard case .send(.text(let text)) = call,
                  let object = try? json(text),
                  object["type"] as? String == type else {
                continue
            }
            return object
        }
        throw SpeechRouteError.invalidEvent
    }

    private static func sentTypeCount(
        _ calls: [QwenASRFakeRealtimeWebSocketTransport.Call],
        type: String
    ) -> Int {
        calls.reduce(into: 0) { count, call in
            guard case .send(.text(let text)) = call,
                  let object = try? json(text),
                  object["type"] as? String == type else {
                return
            }
            count += 1
        }
    }

    private static func json(_ text: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(
            with: Data(text.utf8)
        ) as? [String: Any] else {
            throw SpeechRouteError.invalidEvent
        }
        return object
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
