import Foundation

nonisolated enum StepFunRealtimeWireEventKind: String, Sendable, Equatable {
    case sessionCreated = "session_created"
    case sessionUpdated = "session_updated"
    case inputSpeechStarted = "input_speech_started"
    case inputSpeechEnded = "input_speech_ended"
    case responseCreated
    case responseCompleted
    case cancellationAcknowledgement
    case userTranscriptDelta
    case userTranscriptDone
    case residentAudioTranscriptDelta
    case residentAudioTranscriptDone
    case residentTextDelta
    case residentTextDone
    case outputAudioDelta = "output_audio_delta"
    case outputAudioDone = "output_audio_done"
    case conversationItemCreated = "conversation_item_created"
    case providerError = "provider_error"
    case other
}

nonisolated enum StepFunRealtimeResponseStatus: String, Sendable, Equatable {
    case completed
    case cancelled
    case failed
    case incomplete
}

nonisolated enum StepFunRealtimeResponseStatusDetailReason:
    String,
    Sendable,
    Equatable {
    case turnDetected = "turn_detected"
}

nonisolated struct StepFunRealtimeDecodedEnvelope: Sendable, Equatable {
    let wireKind: StepFunRealtimeWireEventKind
    let event: NativeSpeechEvent?
    let causedByEventID: String?
    let wireEventCorrelationHash: String?
    let responseCorrelationHash: String?
    let itemCorrelationHash: String?
    let responseStatus: StepFunRealtimeResponseStatus?
    let responseStatusDetailReason:
        StepFunRealtimeResponseStatusDetailReason?

    init(
        wireKind: StepFunRealtimeWireEventKind,
        event: NativeSpeechEvent?,
        causedByEventID: String? = nil,
        wireEventCorrelationHash: String? = nil,
        responseCorrelationHash: String? = nil,
        itemCorrelationHash: String? = nil,
        responseStatus: StepFunRealtimeResponseStatus? = nil,
        responseStatusDetailReason:
            StepFunRealtimeResponseStatusDetailReason? = nil
    ) {
        self.wireKind = wireKind
        self.event = event
        self.causedByEventID = causedByEventID
        self.wireEventCorrelationHash = wireEventCorrelationHash
        self.responseCorrelationHash = responseCorrelationHash
        self.itemCorrelationHash = itemCorrelationHash
        self.responseStatus = responseStatus
        self.responseStatusDetailReason = responseStatusDetailReason
    }
}

nonisolated struct StepFunRealtimeCodec: Sendable {
    func sessionUpdate(
        profile: NativeSpeechProviderProfile,
        instructions: String
    ) throws -> String {
        try encode([
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "voice": profile.voiceID,
                "instructions": instructions,
                "input_audio_format": profile.inputAudioFormat.rawValue,
                "output_audio_format": profile.outputAudioFormat.rawValue,
                "turn_detection": [
                    "type": profile.turnDetection.type.rawValue,
                    "prefix_padding_ms": profile.turnDetection.prefixPaddingMilliseconds
                ]
            ]
        ])
    }

    func contextUpdate(instructions: String) throws -> String {
        try encode([
            "type": "session.update",
            "session": ["instructions": instructions]
        ])
    }

    func audioAppend(_ payload: NativeSpeechAudioPayload) throws -> String {
        try encode([
            "type": "input_audio_buffer.append",
            "audio": payload.bytes.base64EncodedString()
        ])
    }

    func responseCancel(eventID: String) throws -> String {
        try encode([
            "event_id": eventID,
            "type": "response.cancel"
        ])
    }

    func decode(
        _ frame: RealtimeWebSocketFrame,
        interactionID: NativeSpeechInteractionID,
        outputAudioSequenceNumber: UInt64? = nil
    ) throws -> NativeSpeechEvent? {
        try decodeEnvelope(
            frame,
            interactionID: interactionID,
            outputAudioSequenceNumber: outputAudioSequenceNumber
        ).event
    }

    func decodeEnvelope(
        _ frame: RealtimeWebSocketFrame,
        interactionID: NativeSpeechInteractionID,
        outputAudioSequenceNumber: UInt64? = nil
    ) throws -> StepFunRealtimeDecodedEnvelope {
        let data: Data
        switch frame {
        case .text(let text):
            guard let textData = text.data(using: .utf8) else {
                throw NativeSpeechError.invalidEvent
            }
            data = textData
        case .binary(let bytes):
            data = bytes
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            throw NativeSpeechError.invalidEvent
        }
        let responseCorrelationHash = Self.correlationHash(
            Self.correlationID(
                in: object,
                directKey: "response_id",
                objectKey: "response"
            )
        )
        let itemCorrelationHash = Self.correlationHash(
            Self.correlationID(
                in: object,
                directKey: "item_id",
                objectKey: "item"
            )
        )
        let wireEventCorrelationHash = Self.correlationHash(
            object["event_id"] as? String
        )

        let kind: NativeSpeechEventKind?
        let wireKind: StepFunRealtimeWireEventKind
        var responseStatus: StepFunRealtimeResponseStatus?
        var responseStatusDetailReason:
            StepFunRealtimeResponseStatusDetailReason?
        switch type {
        case "session.created":
            kind = .connected
            wireKind = .sessionCreated
        case "session.updated":
            kind = .sessionUpdated
            wireKind = .sessionUpdated
        case "input_audio_buffer.speech_started":
            kind = .inputSpeechStarted
            wireKind = .inputSpeechStarted
        case "input_audio_buffer.speech_stopped":
            kind = .inputSpeechEnded
            wireKind = .inputSpeechEnded
        case "conversation.item.input_audio_transcription.delta":
            kind = stringEvent(object, key: "delta", make: NativeSpeechEventKind.partialTranscript)
            wireKind = .userTranscriptDelta
        case "conversation.item.input_audio_transcription.completed":
            kind = stringEvent(object, key: "transcript", make: NativeSpeechEventKind.finalTranscript)
            wireKind = .userTranscriptDone
        case "response.created":
            kind = .thinking
            wireKind = .responseCreated
        case "response.thinking.delta", "response.thinking.done":
            kind = .thinking
            wireKind = .other
        case "response.audio_transcript.delta":
            kind = stringEvent(object, key: "delta") {
                .outputText(text: $0, isFinal: false)
            }
            wireKind = .residentAudioTranscriptDelta
        case "response.audio_transcript.done":
            kind = stringEvent(object, key: "transcript") {
                .outputText(text: $0, isFinal: true)
            }
            wireKind = .residentAudioTranscriptDone
        case "response.audio.delta":
            guard let encoded = object["delta"] as? String,
                  let audio = Data(base64Encoded: encoded) else {
                throw NativeSpeechError.invalidEvent
            }
            guard let sequence = outputAudioSequenceNumber
                    ?? (object["sequence"] as? NSNumber)?.uint64Value else {
                throw NativeSpeechError.invalidEvent
            }
            kind = .outputAudio(
                NativeSpeechAudioPayload(
                    interactionID: interactionID,
                    sequenceNumber: sequence,
                    bytes: audio,
                    format: .pcm16
                )
            )
            wireKind = .outputAudioDelta
        case "response.audio.done":
            return StepFunRealtimeDecodedEnvelope(
                wireKind: .outputAudioDone,
                event: nil,
                wireEventCorrelationHash: wireEventCorrelationHash,
                responseCorrelationHash: responseCorrelationHash,
                itemCorrelationHash: itemCorrelationHash
            )
        case "conversation.item.created":
            guard let transcript = userTranscriptFromConversationItem(
                object
            ) else {
                return StepFunRealtimeDecodedEnvelope(
                    wireKind: .conversationItemCreated,
                    event: nil,
                    wireEventCorrelationHash: wireEventCorrelationHash,
                    responseCorrelationHash: responseCorrelationHash,
                    itemCorrelationHash: itemCorrelationHash
                )
            }
            kind = .finalTranscript(transcript)
            wireKind = .conversationItemCreated
        case "response.text.delta":
            kind = stringEvent(object, key: "delta") {
                .outputText(text: $0, isFinal: false)
            }
            wireKind = .residentTextDelta
        case "response.text.done":
            kind = stringEvent(object, key: "text") {
                .outputText(text: $0, isFinal: true)
            }
            wireKind = .residentTextDone
        case "response.function_call_arguments.done":
            guard let requestID = object["call_id"] as? String,
                  let toolName = object["name"] as? String,
                  let arguments = object["arguments"] as? String else {
                throw NativeSpeechError.invalidEvent
            }
            kind = .toolRequestCandidate(
                NativeSpeechToolRequest(
                    requestID: requestID,
                    toolName: toolName,
                    arguments: Data(arguments.utf8)
                )
            )
            wireKind = .other
        case "response.done":
            let decodedStatus = try responseDoneStatus(object)
            responseStatus = decodedStatus
            let decodedDetailReason = responseDoneStatusDetailReason(object)
            responseStatusDetailReason = decodedDetailReason
            kind = responseDoneKind(
                decodedStatus,
                detailReason: decodedDetailReason
            )
            if case .cancelled = kind {
                wireKind = .cancellationAcknowledgement
            } else {
                wireKind = .responseCompleted
            }
        case "response.cancelled":
            kind = .cancelled(reason: nil)
            wireKind = .cancellationAcknowledgement
        case "error":
            kind = .failed(error(from: object))
            wireKind = .providerError
        default:
            return StepFunRealtimeDecodedEnvelope(
                wireKind: .other,
                event: nil,
                wireEventCorrelationHash: wireEventCorrelationHash,
                responseCorrelationHash: responseCorrelationHash,
                itemCorrelationHash: itemCorrelationHash
            )
        }

        guard let kind else {
            throw NativeSpeechError.invalidEvent
        }
        return StepFunRealtimeDecodedEnvelope(
            wireKind: wireKind,
            event: NativeSpeechEvent(
                interactionID: interactionID,
                kind: kind
            ),
            causedByEventID: errorEventID(from: object),
            wireEventCorrelationHash: wireEventCorrelationHash,
            responseCorrelationHash: responseCorrelationHash,
            itemCorrelationHash: itemCorrelationHash,
            responseStatus: responseStatus,
            responseStatusDetailReason: responseStatusDetailReason
        )
    }

    private func responseDoneStatus(
        _ object: [String: Any]
    ) throws -> StepFunRealtimeResponseStatus {
        guard let response = object["response"] as? [String: Any],
              let rawStatus = response["status"] as? String,
              let status = StepFunRealtimeResponseStatus(
                rawValue: rawStatus
              ) else {
            throw NativeSpeechError.invalidEvent
        }
        return status
    }

    private func responseDoneKind(
        _ status: StepFunRealtimeResponseStatus,
        detailReason: StepFunRealtimeResponseStatusDetailReason?
    ) -> NativeSpeechEventKind {
        switch status {
        case .completed:
            return .responseCompleted
        case .cancelled:
            return .cancelled(reason: "cancelled")
        case .failed:
            return .turnFailed(.unavailable)
        case .incomplete:
            if detailReason == .turnDetected {
                return .turnFailed(.cancelled)
            }
            return .turnFailed(.unavailable)
        }
    }

    private func responseDoneStatusDetailReason(
        _ object: [String: Any]
    ) -> StepFunRealtimeResponseStatusDetailReason? {
        guard let response = object["response"] as? [String: Any],
              let statusDetails = response["status_details"]
                as? [String: Any],
              let rawReason = statusDetails["reason"] as? String else {
            return nil
        }
        return StepFunRealtimeResponseStatusDetailReason(
            rawValue: rawReason
        )
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

    private func stringEvent(
        _ object: [String: Any],
        key: String,
        make: (String) -> NativeSpeechEventKind
    ) -> NativeSpeechEventKind? {
        guard let value = object[key] as? String else { return nil }
        return make(value)
    }

    private func error(from object: [String: Any]) -> NativeSpeechError {
        let error = object["error"] as? [String: Any]
        switch error?["code"] as? String {
        case "invalid_api_key", "unauthorized":
            return .unauthorized
        case "rate_limit_exceeded":
            return .rateLimited
        case "server_error", "service_unavailable":
            return .unavailable
        default:
            return .invalidEvent
        }
    }

    private func errorEventID(from object: [String: Any]) -> String? {
        guard object["type"] as? String == "error" else { return nil }
        let error = object["error"] as? [String: Any]
        return error?["event_id"] as? String
    }

    private func userTranscriptFromConversationItem(
        _ object: [String: Any]
    ) -> String? {
        guard let item = object["item"] as? [String: Any],
              item["type"] as? String == "message",
              item["role"] as? String == "user",
              (item["status"] as? String).map({ $0 == "completed" })
                ?? true,
              let contents = item["content"] as? [[String: Any]] else {
            return nil
        }
        for content in contents {
            for key in ["transcript", "text"] {
                guard let value = content[key] as? String else { continue }
                let normalized = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !normalized.isEmpty { return normalized }
            }
        }
        return nil
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
