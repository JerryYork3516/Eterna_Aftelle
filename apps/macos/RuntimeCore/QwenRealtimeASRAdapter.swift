import Foundation

nonisolated struct QwenRealtimeASRConfiguration: Sendable, Equatable {
    let endpoint: URL
    let modelID: String
    let keyRef: String
    let vadThreshold: Double
    let silenceDurationMilliseconds: Int

    init(
        endpoint: URL,
        modelID: String,
        keyRef: String,
        vadThreshold: Double = 0,
        silenceDurationMilliseconds: Int = 400
    ) {
        self.endpoint = endpoint
        self.modelID = modelID
        self.keyRef = keyRef
        self.vadThreshold = vadThreshold
        self.silenceDurationMilliseconds = silenceDurationMilliseconds
    }

    func validate() throws {
        guard modelID == "qwen3-asr-flash-realtime",
              !keyRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (-1.0 ... 1.0).contains(vadThreshold),
              (200 ... 6_000).contains(silenceDurationMilliseconds) else {
            throw SpeechRouteError.invalidConfiguration
        }
    }
}

nonisolated private enum QwenRealtimeASRWireEvent: Equatable {
    case sessionCreated
    case sessionUpdated
    case speechStarted
    case speechStopped
    case partial(String)
    case final(String)
    case failed(String?)
    case sessionFinished
    case providerError(SpeechRouteError, String?)
    case other
}

nonisolated private struct QwenRealtimeASRCodec: Sendable {
    let configuration: QwenRealtimeASRConfiguration

    func sessionUpdate(locale: String?) throws -> String {
        var session: [String: Any] = [
            "input_audio_format": "pcm",
            "modalities": ["text"],
            "sample_rate": 16_000,
            "turn_detection": [
                "silence_duration_ms":
                    configuration.silenceDurationMilliseconds,
                "threshold": configuration.vadThreshold,
                "type": "server_vad"
            ]
        ]
        if let language = Self.languageCode(for: locale) {
            session["input_audio_transcription"] = ["language": language]
        }
        return try encode([
            "event_id": "session-\(UUID().uuidString)",
            "session": session,
            "type": "session.update"
        ])
    }

    func audioAppend(_ bytes: Data) throws -> String {
        guard !bytes.isEmpty else {
            throw SpeechRouteError.invalidConfiguration
        }
        return try encode([
            "audio": bytes.base64EncodedString(),
            "event_id": "audio-\(UUID().uuidString)",
            "type": "input_audio_buffer.append"
        ])
    }

    func sessionFinish() throws -> String {
        try encode([
            "event_id": "finish-\(UUID().uuidString)",
            "type": "session.finish"
        ])
    }

    func decode(_ text: String) throws -> QwenRealtimeASRWireEvent {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let type = object["type"] as? String else {
            throw SpeechRouteError.invalidEvent
        }
        switch type {
        case "session.created":
            return .sessionCreated
        case "session.updated":
            return .sessionUpdated
        case "input_audio_buffer.speech_started":
            return .speechStarted
        case "input_audio_buffer.speech_stopped":
            return .speechStopped
        case "conversation.item.input_audio_transcription.text":
            guard let confirmed = object["text"] as? String,
                  let stash = object["stash"] as? String else {
                throw SpeechRouteError.invalidEvent
            }
            return .partial(confirmed + stash)
        case "conversation.item.input_audio_transcription.completed":
            guard let transcript = object["transcript"] as? String else {
                throw SpeechRouteError.invalidEvent
            }
            return .final(transcript)
        case "conversation.item.input_audio_transcription.failed":
            let error = object["error"] as? [String: Any]
            return .failed(Self.sanitizedErrorCode(error?["code"]))
        case "session.finished":
            return .sessionFinished
        case "error":
            let error = object["error"] as? [String: Any]
            let kind = error?["type"] as? String
            return .providerError(
                kind == "invalid_request_error"
                    ? .invalidConfiguration
                    : .transportFailure,
                Self.sanitizedErrorCode(error?["code"])
            )
        default:
            return .other
        }
    }

    private func encode(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8) else {
            throw SpeechRouteError.invalidEvent
        }
        return text
    }

    private static func sanitizedErrorCode(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        let filtered = value.unicodeScalars.filter { allowed.contains($0) }
        guard !filtered.isEmpty else { return nil }
        return String(String.UnicodeScalarView(filtered).prefix(64))
    }

    private static func languageCode(for locale: String?) -> String? {
        guard let locale else { return nil }
        let normalized = locale.lowercased().replacingOccurrences(
            of: "_",
            with: "-"
        )
        let code = normalized.split(separator: "-").first.map(String.init)
        let supported = Set([
            "ar", "cs", "da", "de", "en", "es", "fi", "fil", "fr",
            "hi", "id", "is", "it", "ja", "ko", "ms", "no", "pl",
            "pt", "ru", "sv", "th", "tr", "uk", "vi", "yue", "zh"
        ])
        return code.flatMap { supported.contains($0) ? $0 : nil }
    }
}

nonisolated enum QwenASRPCM16Downsampler {
    static func convertMonoTo16k(
        _ bytes: Data,
        sampleRate: Int
    ) throws -> Data {
        switch sampleRate {
        case 48_000:
            return try convert48kMonoTo16k(bytes)
        case 24_000:
            return try convert24kMonoTo16k(bytes)
        default:
            throw SpeechRouteError.invalidConfiguration
        }
    }

    static func convert48kMonoTo16k(_ bytes: Data) throws -> Data {
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 6) else {
            throw SpeechRouteError.invalidConfiguration
        }
        let input = [UInt8](bytes)
        var output = [UInt8]()
        output.reserveCapacity(bytes.count / 3)
        for offset in stride(from: 0, to: input.count, by: 6) {
            let first = sample(input, at: offset)
            let second = sample(input, at: offset + 2)
            let third = sample(input, at: offset + 4)
            let average = Int16(
                (Int32(first) + Int32(second) + Int32(third)) / 3
            )
            let bits = UInt16(bitPattern: average)
            output.append(UInt8(truncatingIfNeeded: bits))
            output.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return Data(output)
    }

    static func convert24kMonoTo16k(_ bytes: Data) throws -> Data {
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 6) else {
            throw SpeechRouteError.invalidConfiguration
        }
        let input = [UInt8](bytes)
        var output = [UInt8]()
        output.reserveCapacity(bytes.count * 2 / 3)
        for offset in stride(from: 0, to: input.count, by: 6) {
            append(sample(input, at: offset), to: &output)
            let interpolated = Int16(
                (Int32(sample(input, at: offset + 2))
                    + Int32(sample(input, at: offset + 4))) / 2
            )
            append(interpolated, to: &output)
        }
        return Data(output)
    }

    private static func append(_ sample: Int16, to bytes: inout [UInt8]) {
        let bits = UInt16(bitPattern: sample)
        bytes.append(UInt8(truncatingIfNeeded: bits))
        bytes.append(UInt8(truncatingIfNeeded: bits >> 8))
    }

    private static func sample(_ bytes: [UInt8], at offset: Int) -> Int16 {
        let bits = UInt16(bytes[offset])
            | UInt16(bytes[offset + 1]) << 8
        return Int16(bitPattern: bits)
    }
}

actor QwenRealtimeASRAdapter: ASRProvider {
    private let credentialReader: ProviderCredentialReading
    private let transport: RealtimeWebSocketTransport
    private let configuration: QwenRealtimeASRConfiguration
    private let codec: QwenRealtimeASRCodec
    private let diagnosticBuffer: NativeSpeechDiagnosticBuffer?

    private var activeGeneration: UInt64?
    private var terminatedGeneration: UInt64?
    private var cancelledGeneration: UInt64?
    private var sessionFinishSent = false

    init(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        configuration: QwenRealtimeASRConfiguration,
        diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.configuration = configuration
        self.diagnosticBuffer = diagnosticBuffer
        codec = QwenRealtimeASRCodec(configuration: configuration)
    }

    func start(request: ASRStartRequest) async throws {
        guard activeGeneration == nil else {
            throw SpeechRouteError.invalidConfiguration
        }
        try configuration.validate()
        let credential = try readCredential()
        let endpoint: URL
        do {
            endpoint = try credential.endpoint(
                configuredEndpoint: configuration.endpoint,
                modelID: configuration.modelID
            )
        } catch {
            throw SpeechRouteError.invalidConfiguration
        }

        do {
            try await transport.connect(
                endpoint: endpoint,
                bearerToken: credential.apiKey
            )
            guard try await receiveWireEvent() == .sessionCreated else {
                throw SpeechRouteError.invalidEvent
            }
            try await transport.send(.text(try codec.sessionUpdate(
                locale: request.locale
            )))
            guard try await receiveWireEvent() == .sessionUpdated else {
                throw SpeechRouteError.invalidEvent
            }
        } catch {
            record(
                category: "asr_start_failed",
                generation: request.generation,
                errorCode: Self.errorCode(error)
            )
            await transport.close(reason: .cancelled)
            throw Self.map(error)
        }

        activeGeneration = request.generation
        terminatedGeneration = nil
        cancelledGeneration = nil
        sessionFinishSent = false
    }

    func send(_ input: ASRAudioInput) async throws {
        guard input.generation == activeGeneration else {
            throw SpeechRouteError.staleGeneration
        }
        guard input.source == .aec3Processed,
              input.format == .pcm16,
              input.sampleRate == 48_000 || input.sampleRate == 24_000,
              input.channelCount == 1 else {
            throw SpeechRouteError.invalidConfiguration
        }
        let converted = try QwenASRPCM16Downsampler
            .convertMonoTo16k(
                input.bytes,
                sampleRate: input.sampleRate
            )
        do {
            try await transport.send(.text(try codec.audioAppend(converted)))
        } catch {
            record(
                category: "asr_send_failed",
                generation: input.generation,
                errorCode: Self.errorCode(error)
            )
            throw Self.map(error)
        }
    }

    func receive(generation: UInt64) async throws -> ASREvent {
        if cancelledGeneration == generation {
            cancelledGeneration = nil
            return ASREvent(generation: generation, kind: .cancelled)
        }
        guard generation == activeGeneration else {
            return ASREvent(generation: generation, kind: .staleGeneration)
        }

        while true {
            let wire: QwenRealtimeASRWireEvent
            do {
                wire = try await receiveWireEvent()
            } catch {
                record(
                    category: "asr_receive_failed",
                    generation: generation,
                    errorCode: Self.errorCode(error)
                )
                return ASREvent(
                    generation: generation,
                    kind: .error(Self.map(error))
                )
            }
            guard activeGeneration == generation else {
                return ASREvent(
                    generation: generation,
                    kind: .staleGeneration
                )
            }
            switch wire {
            case .speechStarted:
                return ASREvent(
                    generation: generation,
                    kind: .speechActivity(.started)
                )
            case .speechStopped:
                return ASREvent(
                    generation: generation,
                    kind: .speechActivity(.ended)
                )
            case .partial(let text):
                return ASREvent(
                    generation: generation,
                    kind: .partialTranscript(text)
                )
            case .final(let transcript):
                return ASREvent(
                    generation: generation,
                    kind: .finalTranscript(transcript)
                )
            case .failed(let errorCode):
                record(
                    category: "asr_recognition_failed",
                    generation: generation,
                    errorCode: errorCode ?? "recognition_failed"
                )
                return ASREvent(
                    generation: generation,
                    kind: .error(.transportFailure)
                )
            case .providerError(let error, let providerCode):
                record(
                    category: "asr_provider_error",
                    generation: generation,
                    errorCode: providerCode ?? Self.errorCode(error)
                )
                return ASREvent(
                    generation: generation,
                    kind: .error(error)
                )
            case .sessionFinished:
                return ASREvent(
                    generation: generation,
                    kind: .error(.invalidEvent)
                )
            case .sessionCreated, .sessionUpdated, .other:
                continue
            }
        }
    }

    func cancel(generation: UInt64) async throws {
        if terminatedGeneration == generation { return }
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        let finishError = await sendSessionFinishIfNeeded()
        activeGeneration = nil
        terminatedGeneration = generation
        cancelledGeneration = generation
        await transport.close(reason: .cancelled)
        if let finishError { throw finishError }
    }

    func close(generation: UInt64) async throws {
        if terminatedGeneration == generation { return }
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        if let finishError = await sendSessionFinishIfNeeded() {
            activeGeneration = nil
            terminatedGeneration = generation
            await transport.close(reason: .cancelled)
            throw finishError
        }

        do {
            while try await receiveWireEvent() != .sessionFinished {}
        } catch {
            activeGeneration = nil
            terminatedGeneration = generation
            await transport.close(reason: .cancelled)
            throw Self.map(error)
        }
        activeGeneration = nil
        terminatedGeneration = generation
        cancelledGeneration = nil
        await transport.close(reason: .normal)
    }

    private func readCredential() throws -> QwenRealtimeCredential {
        do {
            guard let stored = try credentialReader.readCredential(
                for: configuration.keyRef
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty else {
                throw SpeechRouteError.unavailable
            }
            return try QwenRealtimeCredential(storedValue: stored)
        } catch let error as SpeechRouteError {
            throw error
        } catch {
            throw SpeechRouteError.unavailable
        }
    }

    private func receiveWireEvent() async throws
        -> QwenRealtimeASRWireEvent {
        do {
            switch try await transport.receive() {
            case .text(let text):
                return try codec.decode(text)
            case .binary:
                throw SpeechRouteError.invalidEvent
            }
        } catch {
            throw Self.map(error)
        }
    }

    private func record(
        category: String,
        generation: UInt64,
        errorCode: String
    ) {
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: category,
            turnGeneration: generation,
            errorCode: errorCode
        ))
    }

    private static func errorCode(_ error: Error) -> String {
        guard let error = error as? SpeechRouteError else {
            return "unknown"
        }
        return errorCode(error)
    }

    private static func errorCode(_ error: SpeechRouteError) -> String {
        switch error {
        case .invalidConfiguration: "invalid_configuration"
        case .unavailable: "unavailable"
        case .timedOut: "timed_out"
        case .cancelled: "cancelled"
        case .transportFailure: "transport_failure"
        case .invalidEvent: "invalid_event"
        case .staleGeneration: "stale_generation"
        }
    }

    private func sendSessionFinishIfNeeded() async -> SpeechRouteError? {
        guard !sessionFinishSent else { return nil }
        sessionFinishSent = true
        do {
            try await transport.send(.text(try codec.sessionFinish()))
            return nil
        } catch {
            return Self.map(error)
        }
    }

    private nonisolated static func map(_ error: Error) -> SpeechRouteError {
        if let error = error as? SpeechRouteError { return error }
        guard let error = error as? NativeSpeechError else {
            return .transportFailure
        }
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration
        case .missingCredential, .unauthorized, .rateLimited, .unavailable:
            return .unavailable
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        case .transportFailure:
            return .transportFailure
        case .invalidEvent, .interactionMismatch:
            return .invalidEvent
        }
    }
}
