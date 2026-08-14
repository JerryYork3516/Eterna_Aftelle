import Foundation

nonisolated struct QwenRealtimeCredential: Sendable, Equatable {
    let workspaceID: String
    let apiKey: String

    init(workspaceID: String, secret: String) throws {
        let workspaceID = workspaceID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let apiKey = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidWorkspaceID(workspaceID), !apiKey.isEmpty else {
            throw NativeSpeechError.invalidConfiguration
        }
        self.workspaceID = workspaceID
        self.apiKey = apiKey
    }

    init(storedValue: String) throws {
        guard let data = storedValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: String],
              let workspaceID = object["workspace_id"],
              let apiKey = object["api_key"] else {
            throw NativeSpeechError.invalidConfiguration
        }
        try self.init(workspaceID: workspaceID, secret: apiKey)
    }

    func storedValue() throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "api_key": apiKey,
                "workspace_id": workspaceID
            ],
            options: [.sortedKeys]
        )
        guard let value = String(data: data, encoding: .utf8) else {
            throw NativeSpeechError.invalidConfiguration
        }
        return value
    }

    func endpoint(for profile: NativeSpeechProviderProfile) throws -> URL {
        guard var components = URLComponents(
            url: profile.endpoint,
            resolvingAgainstBaseURL: false
        ),
        let configuredHost = components.host?.lowercased() else {
            throw NativeSpeechError.invalidConfiguration
        }
        let suffixes = [
            ".cn-beijing.maas.aliyuncs.com",
            ".ap-southeast-1.maas.aliyuncs.com"
        ]
        guard let suffix = suffixes.first(where: {
            configuredHost.hasSuffix($0)
        }) else {
            throw NativeSpeechError.invalidConfiguration
        }
        components.host = workspaceID + suffix
        guard let endpoint = components.url else {
            throw NativeSpeechError.invalidConfiguration
        }
        return endpoint
    }

    private static func isValidWorkspaceID(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= 63,
              value.first != "-",
              value.last != "-" else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 48 ... 57, 65 ... 90, 97 ... 122:
                true
            default:
                false
            }
        }
    }
}

nonisolated struct QwenRealtimeConfiguration: Sendable, Equatable {
    let inputSampleRate: Int
    let outputSampleRate: Int
    let inputPacketMilliseconds: Int
    let vadThreshold: Double
    let silenceDurationMilliseconds: Int

    init(
        inputSampleRate: Int = 24_000,
        outputSampleRate: Int = 24_000,
        inputPacketMilliseconds: Int = 100,
        vadThreshold: Double = 0.5,
        silenceDurationMilliseconds: Int = 800
    ) {
        self.inputSampleRate = inputSampleRate
        self.outputSampleRate = outputSampleRate
        self.inputPacketMilliseconds = inputPacketMilliseconds
        self.vadThreshold = vadThreshold
        self.silenceDurationMilliseconds = silenceDurationMilliseconds
    }

    var inputPacketByteCount: Int {
        inputSampleRate * MemoryLayout<Int16>.size
            * inputPacketMilliseconds / 1_000
    }

    func validate(profile: NativeSpeechProviderProfile) throws {
        guard inputSampleRate == 24_000,
              outputSampleRate == 24_000,
              inputPacketMilliseconds >= 20,
              inputPacketMilliseconds.isMultiple(of: 20),
              (-1.0 ... 1.0).contains(vadThreshold),
              (200 ... 6_000).contains(silenceDurationMilliseconds),
              profile.transport == "websocket",
              profile.inputAudioFormat == .pcm16,
              profile.outputAudioFormat == .pcm16,
              profile.turnDetection.type == .semanticVAD,
              Self.isSupportedEndpoint(
                  profile.endpoint,
                  modelID: profile.modelID
              ) else {
            throw NativeSpeechError.invalidConfiguration
        }
    }

    private static func isSupportedEndpoint(
        _ endpoint: URL,
        modelID: String
    ) -> Bool {
        guard endpoint.scheme?.lowercased() == "wss",
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.path == "/api-ws/v1/realtime",
              let host = endpoint.host?.lowercased(),
              let components = URLComponents(
                  url: endpoint,
                  resolvingAgainstBaseURL: false
              ),
              components.queryItems?.first(where: {
                  $0.name == "model"
              })?.value == modelID else {
            return false
        }
        let regionSuffixes = [
            ".cn-beijing.maas.aliyuncs.com",
            ".ap-southeast-1.maas.aliyuncs.com"
        ]
        return regionSuffixes.contains { suffix in
            host.hasSuffix(suffix) && host.count > suffix.count
        }
    }
}

nonisolated enum QwenRealtimeWireEventKind: Sendable, Equatable {
    case sessionCreated
    case sessionUpdated
    case inputSpeechStarted
    case inputSpeechEnded
    case userTranscriptPreview
    case userTranscriptDone
    case responseCreated
    case residentTranscriptDelta
    case residentTranscriptDone
    case outputAudioDelta
    case outputAudioDone
    case toolCallCreated
    case toolArgumentsDelta
    case toolArgumentsDone
    case responseDone
    case providerError
    case other
}

nonisolated enum QwenRealtimeToolWireEvent: Sendable, Equatable {
    case created(callID: String, name: String, arguments: String?)
    case argumentsDelta(callID: String, name: String?, delta: String)
    case argumentsDone(callID: String, name: String, arguments: String)
}

nonisolated enum QwenRealtimeResponseStatus: String, Sendable, Equatable {
    case completed
    case failed
    case incomplete
    case cancelled
}

nonisolated struct QwenRealtimeDecodedEnvelope: Sendable, Equatable {
    let wireKind: QwenRealtimeWireEventKind
    let event: NativeSpeechEvent?
    let responseCorrelationHash: String?
    let itemCorrelationHash: String?
    let callCorrelationHash: String?
    let toolWireEvent: QwenRealtimeToolWireEvent?
    let responseStatus: QwenRealtimeResponseStatus?
}

nonisolated struct QwenRealtimeCodec: Sendable {
    let configuration: QwenRealtimeConfiguration

    init(configuration: QwenRealtimeConfiguration = .init()) {
        self.configuration = configuration
    }

    func sessionUpdate(
        profile: NativeSpeechProviderProfile,
        instructions: String,
        tools: [NativeSpeechToolDefinition]
    ) throws -> String {
        let toolObjects: [[String: Any]] = try tools.map { tool in
            guard let parameters = try JSONSerialization.jsonObject(
                with: tool.parametersJSON
            ) as? [String: Any] else {
                throw NativeSpeechError.invalidConfiguration
            }
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": parameters
                ]
            ]
        }
        return try encode([
            "type": "session.update",
            "session": [
                "model": profile.modelID,
                "modalities": ["text", "audio"],
                "voice": profile.voiceID,
                "instructions": instructions,
                "audio": [
                    "input": [
                        "format": [
                            "type": "pcm",
                            "sample_rate": configuration.inputSampleRate
                        ]
                    ],
                    "output": [
                        "format": [
                            "type": "pcm",
                            "sample_rate": configuration.outputSampleRate
                        ]
                    ]
                ],
                "input_audio_transcription": [
                    "model": "qwen3-asr-flash-realtime"
                ],
                "turn_detection": [
                    "type": profile.turnDetection.type.rawValue,
                    "threshold": configuration.vadThreshold,
                    "prefix_padding_ms":
                        profile.turnDetection.prefixPaddingMilliseconds,
                    "silence_duration_ms":
                        configuration.silenceDurationMilliseconds
                ],
                "enable_search": false,
                "tools": toolObjects
            ]
        ])
    }

    func contextUpdate(instructions: String) throws -> String {
        try encode([
            "type": "session.update",
            "session": ["instructions": instructions]
        ])
    }

    func audioAppend(_ bytes: Data) throws -> String {
        try encode([
            "type": "input_audio_buffer.append",
            "audio": bytes.base64EncodedString()
        ])
    }

    func responseCancel(eventID: String) throws -> String {
        try encode([
            "event_id": eventID,
            "type": "response.cancel"
        ])
    }

    func toolOutput(_ output: NativeSpeechToolOutput) throws -> String {
        try encode([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": output.callID,
                "output": output.output
            ]
        ])
    }

    func responseCreate() throws -> String {
        try encode(["type": "response.create"])
    }

    func sessionFinish() throws -> String {
        try encode(["type": "session.finish"])
    }

    func decodeEnvelope(
        _ frame: RealtimeWebSocketFrame,
        interactionID: NativeSpeechInteractionID,
        outputAudioSequenceNumber: UInt64
    ) throws -> QwenRealtimeDecodedEnvelope {
        let data: Data
        switch frame {
        case .text(let text):
            data = Data(text.utf8)
        case .binary(let bytes):
            data = bytes
        }
        guard let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let type = object["type"] as? String else {
            throw NativeSpeechError.invalidEvent
        }
        let responseHash = Self.correlationHash(
            Self.correlationID(
                in: object,
                directKey: "response_id",
                objectKey: "response"
            )
        )
        let itemHash = Self.correlationHash(
            Self.correlationID(
                in: object,
                directKey: "item_id",
                objectKey: "item"
            )
        )
        let callID = object["call_id"] as? String
            ?? ((object["item"] as? [String: Any])?["call_id"]
                as? String)
        let callHash = Self.correlationHash(callID)

        func envelope(
            _ wireKind: QwenRealtimeWireEventKind,
            _ kind: NativeSpeechEventKind? = nil,
            tool: QwenRealtimeToolWireEvent? = nil,
            status: QwenRealtimeResponseStatus? = nil
        ) -> QwenRealtimeDecodedEnvelope {
            QwenRealtimeDecodedEnvelope(
                wireKind: wireKind,
                event: kind.map {
                    NativeSpeechEvent(
                        interactionID: interactionID,
                        kind: $0
                    )
                },
                responseCorrelationHash: responseHash,
                itemCorrelationHash: itemHash,
                callCorrelationHash: callHash,
                toolWireEvent: tool,
                responseStatus: status
            )
        }

        switch type {
        case "session.created":
            return envelope(.sessionCreated, .connected)
        case "session.updated":
            return envelope(.sessionUpdated, .sessionUpdated)
        case "input_audio_buffer.speech_started":
            return envelope(.inputSpeechStarted, .inputSpeechStarted)
        case "input_audio_buffer.speech_stopped":
            return envelope(.inputSpeechEnded, .inputSpeechEnded)
        case "conversation.item.input_audio_transcription.delta":
            guard let text = object["text"] as? String,
                  let stash = object["stash"] as? String else {
                throw NativeSpeechError.invalidEvent
            }
            return envelope(
                .userTranscriptPreview,
                .partialTranscript(text + stash)
            )
        case "conversation.item.input_audio_transcription.completed":
            guard let transcript = object["transcript"] as? String else {
                throw NativeSpeechError.invalidEvent
            }
            return envelope(.userTranscriptDone, .finalTranscript(transcript))
        case "response.created":
            return envelope(.responseCreated, .thinking)
        case "response.audio_transcript.delta":
            guard let delta = object["delta"] as? String else {
                throw NativeSpeechError.invalidEvent
            }
            return envelope(
                .residentTranscriptDelta,
                .outputText(text: delta, isFinal: false)
            )
        case "response.audio_transcript.done":
            guard let transcript = object["transcript"] as? String else {
                throw NativeSpeechError.invalidEvent
            }
            return envelope(
                .residentTranscriptDone,
                .outputText(text: transcript, isFinal: true)
            )
        case "response.audio.delta":
            guard let encoded = object["delta"] as? String,
                  let bytes = Data(base64Encoded: encoded) else {
                throw NativeSpeechError.invalidEvent
            }
            return envelope(
                .outputAudioDelta,
                .outputAudio(NativeSpeechAudioPayload(
                    interactionID: interactionID,
                    sequenceNumber: outputAudioSequenceNumber,
                    bytes: bytes,
                    format: .pcm16
                ))
            )
        case "response.audio.done":
            return envelope(.outputAudioDone)
        case "conversation.item.created":
            guard let item = object["item"] as? [String: Any],
                  item["type"] as? String == "function_call" else {
                return envelope(.other)
            }
            guard let createdCallID = item["call_id"] as? String,
                  let name = item["name"] as? String else {
                throw NativeSpeechError.invalidEvent
            }
            return envelope(
                .toolCallCreated,
                tool: .created(
                    callID: createdCallID,
                    name: name,
                    arguments: item["arguments"] as? String
                )
            )
        case "response.function_call_arguments.delta":
            guard let deltaCallID = object["call_id"] as? String,
                  let delta = object["arguments"] as? String else {
                throw NativeSpeechError.invalidEvent
            }
            return envelope(
                .toolArgumentsDelta,
                tool: .argumentsDelta(
                    callID: deltaCallID,
                    name: object["name"] as? String,
                    delta: delta
                )
            )
        case "response.function_call_arguments.done":
            guard let doneCallID = object["call_id"] as? String,
                  let name = object["name"] as? String,
                  let arguments = object["arguments"] as? String else {
                throw NativeSpeechError.invalidEvent
            }
            return envelope(
                .toolArgumentsDone,
                tool: .argumentsDone(
                    callID: doneCallID,
                    name: name,
                    arguments: arguments
                )
            )
        case "response.done":
            guard let response = object["response"] as? [String: Any],
                  let rawStatus = response["status"] as? String,
                  let status = QwenRealtimeResponseStatus(
                      rawValue: rawStatus
                  ) else {
                throw NativeSpeechError.invalidEvent
            }
            let kind: NativeSpeechEventKind = switch status {
            case .completed: .responseCompleted
            case .cancelled: .cancelled(reason: "cancelled")
            case .failed, .incomplete: .turnFailed(.unavailable)
            }
            return envelope(.responseDone, kind, status: status)
        case "error":
            return envelope(.providerError, .failed(error(from: object)))
        default:
            return envelope(.other)
        }
    }

    private func encode(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NativeSpeechError.invalidConfiguration
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw NativeSpeechError.invalidEvent
        }
        return text
    }

    private func error(from object: [String: Any]) -> NativeSpeechError {
        let error = object["error"] as? [String: Any]
        switch (error?["code"] as? String)?.lowercased() {
        case "invalid_api_key", "unauthorized":
            return .unauthorized
        case "rate_limit_exceeded", "throttling":
            return .rateLimited
        case "server_error", "service_unavailable":
            return .unavailable
        default:
            return .invalidEvent
        }
    }

    private static func correlationID(
        in object: [String: Any],
        directKey: String,
        objectKey: String
    ) -> String? {
        if let direct = object[directKey] as? String {
            return direct
        }
        return (object[objectKey] as? [String: Any])?["id"] as? String
    }

    private static func correlationHash(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
