import Foundation

nonisolated enum StepFunRealtimeWireEventKind: Sendable, Equatable {
    case responseCreated
    case responseCompleted
    case cancellationAcknowledgement
    case userTranscriptDelta
    case userTranscriptDone
    case residentAudioTranscriptDelta
    case residentAudioTranscriptDone
    case residentTextDelta
    case residentTextDone
    case other
}

nonisolated struct StepFunRealtimeDecodedEnvelope: Sendable, Equatable {
    let wireKind: StepFunRealtimeWireEventKind
    let event: NativeSpeechEvent?
    let causedByEventID: String?

    init(
        wireKind: StepFunRealtimeWireEventKind,
        event: NativeSpeechEvent?,
        causedByEventID: String? = nil
    ) {
        self.wireKind = wireKind
        self.event = event
        self.causedByEventID = causedByEventID
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

        let kind: NativeSpeechEventKind?
        let wireKind: StepFunRealtimeWireEventKind
        switch type {
        case "session.created":
            kind = .connected
            wireKind = .other
        case "session.updated":
            kind = .sessionUpdated
            wireKind = .other
        case "input_audio_buffer.speech_started":
            kind = .inputSpeechStarted
            wireKind = .other
        case "input_audio_buffer.speech_stopped":
            kind = .inputSpeechEnded
            wireKind = .other
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
            wireKind = .other
        case "response.audio.done":
            return StepFunRealtimeDecodedEnvelope(
                wireKind: .other,
                event: nil
            )
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
            kind = try responseDoneKind(object)
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
            wireKind = .other
        default:
            return StepFunRealtimeDecodedEnvelope(
                wireKind: .other,
                event: nil
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
            causedByEventID: errorEventID(from: object)
        )
    }

    private func responseDoneKind(
        _ object: [String: Any]
    ) throws -> NativeSpeechEventKind {
        guard let response = object["response"] as? [String: Any],
              let status = response["status"] as? String else {
            throw NativeSpeechError.invalidEvent
        }
        switch status {
        case "completed":
            return .responseCompleted
        case "cancelled":
            return .cancelled(reason: "cancelled")
        case "failed":
            return .failed(.unavailable)
        case "incomplete":
            return .failed(.transportFailure)
        default:
            throw NativeSpeechError.invalidEvent
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
}
