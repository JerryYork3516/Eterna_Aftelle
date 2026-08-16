import Foundation

nonisolated private final class QwenASRTestCredentialReader:
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
private struct QwenRealtimeASRAdapterTests {
    private static var checks = 0

    static func main() async throws {
        try await testHandshakeAudioAndEventMapping()
        try await testFailedAndErrorMapping()
        try await testStaleGenerationAndCancelIdempotency()
        try await testCloseIdempotency()
        try testDownsamplerValidation()
        print("qwen_realtime_asr_checks=\(checks)")
    }

    private static func testHandshakeAudioAndEventMapping() async throws {
        let transport = QwenASRFakeRealtimeWebSocketTransport(frames: [
            text(#"{"type":"session.created"}"#),
            text(#"{"type":"session.updated"}"#),
            text(#"{"type":"input_audio_buffer.speech_started"}"#),
            text(#"{"type":"conversation.item.input_audio_transcription.text","text":"今天","stash":"天气"}"#),
            text(#"{"type":"input_audio_buffer.speech_stopped"}"#),
            text(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"今天天气很好"}"#),
            text(#"{"type":"session.finished"}"#)
        ])
        let credentialReader = QwenASRTestCredentialReader(
            storedCredential: try credential()
        )
        let adapter = makeAdapter(
            credentialReader: credentialReader,
            transport: transport
        )
        try await adapter.start(request: ASRStartRequest(
            generation: 41,
            locale: "zh-CN"
        ))

        let callsAfterStart = await transport.calls
        expect(
            callsAfterStart.contains(.connect(URL(
                string: "wss://workspace-123.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3-asr-flash-realtime"
            )!)),
            "workspace credential resolves the official endpoint"
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

        let sessionUpdate = try sentJSON(
            callsAfterStart,
            type: "session.update"
        )
        let session = sessionUpdate["session"] as? [String: Any]
        let transcription = session?["input_audio_transcription"]
            as? [String: Any]
        let vad = session?["turn_detection"] as? [String: Any]
        expect(
            session?["input_audio_format"] as? String == "pcm"
                && session?["sample_rate"] as? Int == 16_000,
            "Qwen session uses 16 kHz PCM"
        )
        expect(
            transcription?["language"] as? String == "zh",
            "provider-neutral locale maps to the official language code"
        )
        expect(
            vad?["type"] as? String == "server_vad"
                && vad?["threshold"] as? Double == 0
                && vad?["silence_duration_ms"] as? Int == 400,
            "server VAD is configured only as ASR activity input"
        )

        let samples = (0 ..< 160).flatMap { index -> [Int16] in
            let base = Int16(index * 3)
            return [base, base + 3, base + 6]
        }
        try await adapter.send(ASRAudioInput(
            generation: 41,
            sequenceNumber: 1,
            bytes: pcm16(samples),
            format: .pcm16,
            sampleRate: 48_000,
            channelCount: 1,
            source: .aec3Processed
        ))
        let audioAppend = try sentJSON(
            await transport.calls,
            type: "input_audio_buffer.append"
        )
        let encodedAudio = try requiredString(audioAppend, key: "audio")
        let converted = try requiredData(encodedAudio)
        expect(converted.count == 320, "10 ms at 48 kHz becomes 10 ms at 16 kHz")
        expect(
            pcm16Samples(converted) == (0 ..< 160).map {
                Int16($0 * 3 + 3)
            },
            "3:1 PCM conversion is deterministic"
        )

        let started = try await adapter.receive(generation: 41)
        expect(
            started.kind == .speechActivity(.started),
            "speech_started maps to ASR activity started"
        )
        let partial = try await adapter.receive(generation: 41)
        expect(
            partial.kind == .partialTranscript("今天天气"),
            "partial transcript concatenates text and stash"
        )
        let stopped = try await adapter.receive(generation: 41)
        expect(
            stopped.kind == .speechActivity(.ended),
            "speech_stopped maps to ASR activity ended"
        )
        let final = try await adapter.receive(generation: 41)
        expect(
            final.kind == .finalTranscript("今天天气很好"),
            "completed.transcript is the sole final result"
        )
        try await adapter.close(generation: 41)
        let callsAfterClose = await transport.calls
        expect(
            callsAfterClose.contains(.close(.normal)),
            "close waits for session.finished and closes normally"
        )
    }

    private static func testFailedAndErrorMapping() async throws {
        let diagnosticBuffer = NativeSpeechDiagnosticBuffer()
        let failedTransport = QwenASRFakeRealtimeWebSocketTransport(frames:
            handshake() + [text(#"{"type":"conversation.item.input_audio_transcription.failed","error":{"code":"asr_failed"}}"#)]
        )
        let failedAdapter = makeAdapter(
            credentialReader: QwenASRTestCredentialReader(
                storedCredential: try credential()
            ),
            transport: failedTransport,
            diagnosticBuffer: diagnosticBuffer
        )
        try await failedAdapter.start(request: ASRStartRequest(
            generation: 1,
            locale: nil
        ))
        let failed = try await failedAdapter.receive(generation: 1)
        expect(
            failed.kind == .error(.transportFailure),
            "transcription.failed maps to provider-neutral error"
        )
        expect(
            diagnosticBuffer.drain().events.contains {
                $0.category == "asr_recognition_failed"
                    && $0.errorCode == "asr_failed"
            },
            "transcription failure exports only the sanitized provider code"
        )

        let errorTransport = QwenASRFakeRealtimeWebSocketTransport(frames:
            handshake() + [text(#"{"type":"error","error":{"type":"invalid_request_error"}}"#)]
        )
        let errorAdapter = makeAdapter(
            credentialReader: QwenASRTestCredentialReader(
                storedCredential: try credential()
            ),
            transport: errorTransport
        )
        try await errorAdapter.start(request: ASRStartRequest(
            generation: 2,
            locale: nil
        ))
        let providerError = try await errorAdapter.receive(generation: 2)
        expect(
            providerError.kind == .error(.invalidConfiguration),
            "server error maps without leaking provider details"
        )
    }

    private static func testStaleGenerationAndCancelIdempotency()
        async throws {
        let transport = QwenASRFakeRealtimeWebSocketTransport(
            frames: handshake()
        )
        let adapter = makeAdapter(
            credentialReader: QwenASRTestCredentialReader(
                storedCredential: try credential()
            ),
            transport: transport
        )
        try await adapter.start(request: ASRStartRequest(
            generation: 7,
            locale: "en-US"
        ))
        let receiveCount = await transport.calls.filter {
            $0 == .receive
        }.count
        let stale = try await adapter.receive(generation: 6)
        expect(
            stale.kind == .staleGeneration,
            "stale generation becomes a provider-neutral stale event"
        )
        let callsAfterStale = await transport.calls
        expect(
            callsAfterStale.filter { $0 == .receive }.count == receiveCount,
            "stale generation never consumes a provider event"
        )
        do {
            try await adapter.send(ASRAudioInput(
                generation: 6,
                sequenceNumber: 1,
                bytes: Data(repeating: 0, count: 960),
                format: .pcm16,
                sampleRate: 48_000,
                channelCount: 1,
                source: .aec3Processed
            ))
            fatalError("FAILED: stale audio must be rejected")
        } catch let error as SpeechRouteError {
            expect(error == .staleGeneration, "stale audio is rejected")
        }

        try await adapter.cancel(generation: 7)
        try await adapter.cancel(generation: 7)
        let cancelled = try await adapter.receive(generation: 7)
        expect(
            cancelled.kind == .cancelled,
            "cancel exposes one provider-neutral cancelled event"
        )
        let calls = await transport.calls
        expect(
            sentTypeCount(calls, type: "session.finish") == 1,
            "cancel is wire-idempotent"
        )
        expect(
            calls.filter { $0 == .close(.cancelled) }.count == 1,
            "cancel closes transport once"
        )
    }

    private static func testCloseIdempotency() async throws {
        let transport = QwenASRFakeRealtimeWebSocketTransport(
            frames: handshake() + [text(#"{"type":"session.finished"}"#)]
        )
        let adapter = makeAdapter(
            credentialReader: QwenASRTestCredentialReader(
                storedCredential: try credential()
            ),
            transport: transport
        )
        try await adapter.start(request: ASRStartRequest(
            generation: 9,
            locale: nil
        ))
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

    private static func testDownsamplerValidation() throws {
        let converted24k = try QwenASRPCM16Downsampler
            .convert24kMonoTo16k(pcm16([0, 10, 20, 30, 40, 50]))
        expect(
            pcm16Samples(converted24k) == [0, 15, 30, 45],
            "24 kHz post-AEC PCM converts deterministically to 16 kHz"
        )
        do {
            _ = try QwenASRPCM16Downsampler.convert48kMonoTo16k(
                Data(repeating: 0, count: 4)
            )
            fatalError("FAILED: incomplete 3:1 frame must be rejected")
        } catch let error as SpeechRouteError {
            expect(
                error == .invalidConfiguration,
                "downsampler rejects incomplete sample groups"
            )
        }
    }

    private static func makeAdapter(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil
    ) -> QwenRealtimeASRAdapter {
        QwenRealtimeASRAdapter(
            credentialReader: credentialReader,
            transport: transport,
            configuration: QwenRealtimeASRConfiguration(
                endpoint: URL(
                    string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3-asr-flash-realtime"
                )!,
                modelID: "qwen3-asr-flash-realtime",
                keyRef: "keychain://test/qwen"
            ),
            diagnosticBuffer: diagnosticBuffer
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
        let data = Data(text.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw SpeechRouteError.invalidEvent
        }
        return object
    }

    private static func requiredString(
        _ object: [String: Any],
        key: String
    ) throws -> String {
        guard let value = object[key] as? String else {
            throw SpeechRouteError.invalidEvent
        }
        return value
    }

    private static func requiredData(_ base64: String) throws -> Data {
        guard let data = Data(base64Encoded: base64) else {
            throw SpeechRouteError.invalidEvent
        }
        return data
    }

    private static func pcm16(_ samples: [Int16]) -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            let bits = UInt16(bitPattern: sample)
            bytes.append(UInt8(truncatingIfNeeded: bits))
            bytes.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return Data(bytes)
    }

    private static func pcm16Samples(_ data: Data) -> [Int16] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 2).map { offset in
            Int16(bitPattern: UInt16(bytes[offset])
                | UInt16(bytes[offset + 1]) << 8)
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
