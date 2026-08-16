import Foundation

nonisolated struct QwenRealtimeTTSConfiguration: Sendable, Equatable {
    let endpoint: URL
    let modelID: String
    let keyRef: String
    let voiceBindings: [String: String]

    func validate() throws {
        guard modelID == "qwen3-tts-instruct-flash-realtime",
              !keyRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !voiceBindings.isEmpty,
              voiceBindings.allSatisfy({
                  !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw SpeechRouteError.invalidConfiguration
        }
    }
}

nonisolated private enum QwenRealtimeTTSWireEvent: Equatable {
    case sessionCreated
    case sessionUpdated
    case responseCreated
    case audio(Data)
    case audioDone
    case sessionFinished
    case providerError(SpeechRouteError)
    case other
}

nonisolated private struct QwenRealtimeTTSCodec: Sendable {
    let configuration: QwenRealtimeTTSConfiguration

    func sessionUpdate(for request: TTSSynthesisRequest) throws -> String {
        guard let voice = configuration.voiceBindings[
            request.voiceProfile.profileID
        ], (0.5 ... 2.0).contains(request.pace) else {
            throw SpeechRouteError.invalidConfiguration
        }
        var session: [String: Any] = [
            "language_type": Self.languageType(
                for: request.voiceProfile.locale
            ),
            "mode": "commit",
            "response_format": "pcm",
            "sample_rate": 24_000,
            "speech_rate": request.pace,
            "voice": voice
        ]
        if let instructions = Self.instructions(
            emotion: request.emotion,
            style: request.style
        ) {
            session["instructions"] = instructions
            session["optimize_instructions"] = false
        }
        return try encode([
            "event_id": "session-\(UUID().uuidString)",
            "session": session,
            "type": "session.update"
        ])
    }

    func textAppend(_ canonicalResponseText: String) throws -> String {
        guard !canonicalResponseText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw SpeechRouteError.invalidConfiguration
        }
        return try encode([
            "event_id": "text-\(UUID().uuidString)",
            "text": canonicalResponseText,
            "type": "input_text_buffer.append"
        ])
    }

    func textCommit() throws -> String {
        try encode([
            "event_id": "commit-\(UUID().uuidString)",
            "type": "input_text_buffer.commit"
        ])
    }

    func sessionFinish() throws -> String {
        try encode([
            "event_id": "finish-\(UUID().uuidString)",
            "type": "session.finish"
        ])
    }

    func decode(_ text: String) throws -> QwenRealtimeTTSWireEvent {
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
        case "response.created":
            return .responseCreated
        case "response.audio.delta":
            guard let encoded = object["delta"] as? String,
                  let audio = Data(base64Encoded: encoded),
                  !audio.isEmpty,
                  audio.count.isMultiple(of: 2) else {
                throw SpeechRouteError.invalidEvent
            }
            return .audio(audio)
        case "response.audio.done":
            return .audioDone
        case "session.finished":
            return .sessionFinished
        case "error":
            let error = object["error"] as? [String: Any]
            let code = error?["code"] as? String
            return .providerError(
                code?.hasPrefix("invalid_") == true
                    ? .invalidConfiguration
                    : .transportFailure
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

    private static func languageType(for locale: String?) -> String {
        guard let locale else { return "Auto" }
        let code = locale.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init)
        return [
            "de": "German",
            "en": "English",
            "es": "Spanish",
            "fr": "French",
            "it": "Italian",
            "ja": "Japanese",
            "ko": "Korean",
            "pt": "Portuguese",
            "ru": "Russian",
            "zh": "Chinese"
        ][code ?? ""] ?? "Auto"
    }

    private static func instructions(
        emotion: String?,
        style: String?
    ) -> String? {
        var controls: [String] = []
        if let emotion = normalizedControl(emotion) {
            controls.append("Emotion: \(emotion).")
        }
        if let style = normalizedControl(style) {
            controls.append("Style: \(style).")
        }
        return controls.isEmpty ? nil : controls.joined(separator: " ")
    }

    private static func normalizedControl(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

actor QwenRealtimeTTSAdapter: TTSProvider {
    private let credentialReader: ProviderCredentialReading
    private let transport: RealtimeWebSocketTransport
    private let configuration: QwenRealtimeTTSConfiguration
    private let codec: QwenRealtimeTTSCodec

    private var activeGeneration: UInt64?
    private var terminatedGeneration: UInt64?
    private var cancelledGeneration: UInt64?
    private var sessionFinishSent = false
    private var audioSequence: UInt64 = 0

    init(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        configuration: QwenRealtimeTTSConfiguration
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.configuration = configuration
        codec = QwenRealtimeTTSCodec(configuration: configuration)
    }

    func start(request: TTSSynthesisRequest) async throws {
        guard activeGeneration == nil else {
            throw SpeechRouteError.invalidConfiguration
        }
        try configuration.validate()
        let sessionUpdate = try codec.sessionUpdate(for: request)
        let textAppend = try codec.textAppend(request.canonicalResponseText)
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
            try await transport.send(.text(sessionUpdate))
            guard try await receiveWireEvent() == .sessionUpdated else {
                throw SpeechRouteError.invalidEvent
            }
            try await transport.send(.text(textAppend))
            try await transport.send(.text(try codec.textCommit()))
        } catch {
            await transport.close(reason: .cancelled)
            throw Self.map(error)
        }

        activeGeneration = request.generation
        terminatedGeneration = nil
        cancelledGeneration = nil
        sessionFinishSent = false
        audioSequence = 0
    }

    func receive(generation: UInt64) async throws -> TTSEvent {
        if cancelledGeneration == generation {
            cancelledGeneration = nil
            return TTSEvent(generation: generation, kind: .cancelled)
        }
        guard generation == activeGeneration else {
            return TTSEvent(
                generation: generation,
                kind: .error(.staleGeneration)
            )
        }

        while true {
            let wire: QwenRealtimeTTSWireEvent
            do {
                wire = try await receiveWireEvent()
            } catch {
                return TTSEvent(
                    generation: generation,
                    kind: .error(Self.map(error))
                )
            }
            guard activeGeneration == generation else {
                return TTSEvent(
                    generation: generation,
                    kind: .error(.staleGeneration)
                )
            }
            switch wire {
            case .responseCreated:
                return TTSEvent(generation: generation, kind: .started)
            case .audio(let bytes):
                audioSequence &+= 1
                return TTSEvent(
                    generation: generation,
                    kind: .audio(TTSAudioChunk(
                        generation: generation,
                        sequenceNumber: audioSequence,
                        bytes: bytes,
                        format: .pcm16,
                        sampleRate: 24_000,
                        channelCount: 1
                    ))
                )
            case .audioDone:
                return TTSEvent(generation: generation, kind: .done)
            case .providerError(let error):
                return TTSEvent(
                    generation: generation,
                    kind: .error(error)
                )
            case .sessionFinished:
                return TTSEvent(
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
        activeGeneration = nil
        terminatedGeneration = generation
        cancelledGeneration = generation
        await transport.close(reason: .cancelled)
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
        -> QwenRealtimeTTSWireEvent {
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
