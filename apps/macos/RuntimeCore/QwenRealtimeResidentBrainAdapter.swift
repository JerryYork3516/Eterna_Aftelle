import Foundation

nonisolated struct QwenRealtimeResidentBrainConfiguration:
    Sendable,
    Equatable {
    static let supportedModelID = "qwen3.5-omni-plus-realtime"

    let endpoint: URL
    let modelID: String
    let keyRef: String
    let defaultProviderVoiceID: String
    let acknowledgementTimeout: Duration

    init(
        endpoint: URL,
        modelID: String = Self.supportedModelID,
        keyRef: String,
        defaultProviderVoiceID: String,
        acknowledgementTimeout: Duration = .seconds(5)
    ) {
        self.endpoint = endpoint
        self.modelID = modelID
        self.keyRef = keyRef
        self.defaultProviderVoiceID = defaultProviderVoiceID
        self.acknowledgementTimeout = acknowledgementTimeout
    }
}

nonisolated private struct QwenResolvedRealtimeVoice:
    Sendable,
    Equatable {
    let voiceID: String
}

nonisolated private struct QwenRealtimeTurnDetectionEcho: Sendable {
    let type: String?
    let threshold: Double?
    let silenceDurationMilliseconds: Int?
    let createResponse: Bool?
    let interruptResponse: Bool?

    var diagnosticDisposition: String {
        let thresholdValue = threshold.map { String($0) } ?? "unknown"
        let silenceValue = silenceDurationMilliseconds.map { String($0) }
            ?? "unknown"
        let createValue = createResponse.map { String($0) } ?? "unknown"
        let interruptValue = interruptResponse.map { String($0) } ?? "unknown"
        return "type=\(type ?? "unknown");threshold=\(thresholdValue)"
            + ";silence_ms=\(silenceValue);create_response=\(createValue)"
            + ";interrupt_response=\(interruptValue)"
    }
}

nonisolated private enum QwenRealtimeTurnDetectionPolicy {
    static let type = "semantic_vad"
    static let threshold = 0.2
    static let silenceDurationMilliseconds = 800
}

nonisolated private enum QwenRealtimeBrainWireEvent: Sendable {
    case sessionCreated
    case sessionUpdated(turnDetection: QwenRealtimeTurnDetectionEcho?)
    case inputAudioCleared
    case inputSpeechStarted(itemID: String, audioStartMilliseconds: Int?)
    case inputSpeechStopped(itemID: String, audioEndMilliseconds: Int?)
    case unidentifiedSpeechStopped(audioEndMilliseconds: Int?)
    case inputTranscriptDelta(itemID: String, preview: String)
    case inputTranscriptCompleted(itemID: String, transcript: String)
    case inputTranscriptFailed(itemID: String)
    case responseCreated(responseID: String)
    case responseTextDelta(responseID: String, delta: String)
    case responseTextDone(responseID: String, text: String)
    case responseAudioTranscriptDelta(responseID: String, delta: String)
    case responseAudioTranscriptDone(responseID: String, transcript: String)
    case responseAudioDelta(responseID: String, bytes: Data)
    case responseAudioDone(responseID: String)
    case toolArgumentsDone(
        responseID: String,
        callID: String,
        name: String,
        arguments: Data
    )
    case responseDone(
        responseID: String,
        status: String,
        canonicalText: String?
    )
    case providerError
    case other
}

#if DEBUG
nonisolated private struct QwenRealtimeReceiveFailure: Error {
    let branch: String
}
#endif

nonisolated private func invalidQwenReceiveEvent(
    _ branch: StaticString
) -> any Error {
    #if DEBUG
    return QwenRealtimeReceiveFailure(branch: branch.description)
    #else
    return RealtimeResidentBrainError.invalidEvent
    #endif
}

nonisolated private struct QwenRealtimeResidentBrainCodec: Sendable {
    func initialSessionUpdate(
        instructions: String,
        tools: [RealtimeBrainToolAdvertisement],
        voice: QwenResolvedRealtimeVoice
    ) throws -> String {
        let toolObjects: [[String: Any]] = try tools.map { tool in
            guard let object = try? JSONSerialization.jsonObject(
                with: tool.parametersJSON
            ), let parameters = object as? [String: Any] else {
                throw RealtimeResidentBrainError.invalidEvent
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
            "event_id": eventID(),
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "voice": voice.voiceID,
                "input_audio_format": "pcm",
                "output_audio_format": "pcm",
                "instructions": instructions,
                "input_audio_transcription": [
                    "model": "qwen3-asr-flash-realtime"
                ],
                "turn_detection": [
                    "type": QwenRealtimeTurnDetectionPolicy.type,
                    "threshold": QwenRealtimeTurnDetectionPolicy.threshold,
                    "silence_duration_ms": QwenRealtimeTurnDetectionPolicy
                        .silenceDurationMilliseconds,
                    "create_response": false,
                    "interrupt_response": false
                ],
                "enable_search": false,
                "tools": toolObjects
            ]
        ])
    }

    func contextUpdate(instructions: String) throws -> String {
        try encode([
            "event_id": eventID(),
            "type": "session.update",
            "session": ["instructions": instructions]
        ])
    }

    func audioAppend(_ bytes: Data) throws -> String {
        try encode([
            "event_id": eventID(),
            "type": "input_audio_buffer.append",
            "audio": bytes.base64EncodedString()
        ])
    }

    func responseCancel() throws -> String {
        try encode([
            "event_id": eventID(),
            "type": "response.cancel"
        ])
    }

    func inputAudioClear() throws -> String {
        try encode([
            "event_id": eventID(),
            "type": "input_audio_buffer.clear"
        ])
    }

    func toolOutput(
        callID: String,
        output: String,
        isError: Bool
    ) throws -> String {
        let payload: String
        if isError {
            payload = try encode([
                "error": output
            ])
        } else {
            payload = output
        }
        return try encode([
            "event_id": eventID(),
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callID,
                "output": payload
            ]
        ])
    }

    func responseCreate() throws -> String {
        try encode([
            "event_id": eventID(),
            "type": "response.create"
        ])
    }

    func decode(_ frame: RealtimeWebSocketFrame) throws
        -> QwenRealtimeBrainWireEvent {
        let data: Data = switch frame {
        case .text(let text): Data(text.utf8)
        case .binary(let bytes): bytes
        }
        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw invalidQwenReceiveEvent("json_object")
        }
        guard let object = rawObject as? [String: Any],
              let type = object["type"] as? String else {
            throw invalidQwenReceiveEvent("object_or_type")
        }

        switch type {
        case "session.created":
            return .sessionCreated
        case "session.updated":
            return .sessionUpdated(
                turnDetection: turnDetectionEcho(in: object)
            )
        case "input_audio_buffer.cleared":
            return .inputAudioCleared
        case "input_audio_buffer.speech_started":
            return .inputSpeechStarted(
                itemID: try itemID(in: object),
                audioStartMilliseconds: audioMilliseconds("audio_start_ms", in: object)
            )
        case "input_audio_buffer.speech_stopped":
            // Preserve the interval for bounded association; an empty ID alone is not a turn.
            if object["item_id"] as? String == "" {
                return .unidentifiedSpeechStopped(
                    audioEndMilliseconds: audioMilliseconds("audio_end_ms", in: object)
                )
            }
            return .inputSpeechStopped(
                itemID: try itemID(in: object),
                audioEndMilliseconds: audioMilliseconds("audio_end_ms", in: object)
            )
        case "conversation.item.input_audio_transcription.delta":
            guard let text = object["text"] as? String,
                  let stash = object["stash"] as? String else {
                throw invalidQwenReceiveEvent("transcript_text_or_stash")
            }
            return .inputTranscriptDelta(
                itemID: try itemID(in: object),
                preview: text + stash
            )
        case "conversation.item.input_audio_transcription.completed":
            guard let transcript = object["transcript"] as? String else {
                throw invalidQwenReceiveEvent("transcript")
            }
            return .inputTranscriptCompleted(
                itemID: try itemID(in: object),
                transcript: transcript
            )
        case "conversation.item.input_audio_transcription.failed":
            return .inputTranscriptFailed(itemID: try itemID(in: object))
        case "response.created":
            return .responseCreated(
                responseID: try responseID(in: object)
            )
        case "response.text.delta":
            return .responseTextDelta(
                responseID: try responseID(in: object),
                delta: try string("delta", in: object)
            )
        case "response.text.done":
            return .responseTextDone(
                responseID: try responseID(in: object),
                text: try string("text", in: object)
            )
        case "response.audio_transcript.delta":
            return .responseAudioTranscriptDelta(
                responseID: try responseID(in: object),
                delta: try string("delta", in: object)
            )
        case "response.audio_transcript.done":
            return .responseAudioTranscriptDone(
                responseID: try responseID(in: object),
                transcript: try string("transcript", in: object)
            )
        case "response.audio.delta":
            guard let encoded = object["delta"] as? String,
                  let bytes = Data(base64Encoded: encoded) else {
                throw invalidQwenReceiveEvent("audio_base64")
            }
            return .responseAudioDelta(
                responseID: try responseID(in: object),
                bytes: bytes
            )
        case "response.audio.done":
            return .responseAudioDone(
                responseID: try responseID(in: object)
            )
        case "response.function_call_arguments.done":
            let arguments = try string("arguments", in: object)
            let argumentsObject: Any
            do {
                argumentsObject = try JSONSerialization.jsonObject(
                    with: Data(arguments.utf8)
                )
            } catch {
                throw invalidQwenReceiveEvent("tool_arguments_json")
            }
            guard JSONSerialization.isValidJSONObject(argumentsObject) else {
                throw invalidQwenReceiveEvent("tool_arguments_object")
            }
            return .toolArgumentsDone(
                responseID: try responseID(in: object),
                callID: try string("call_id", in: object),
                name: try string("name", in: object),
                arguments: Data(arguments.utf8)
            )
        case "response.done":
            guard let response = object["response"] as? [String: Any],
                  let responseID = response["id"] as? String,
                  let status = response["status"] as? String,
                  !responseID.isEmpty,
                  !status.isEmpty else {
                throw invalidQwenReceiveEvent("response_done_identity_or_status")
            }
            return .responseDone(
                responseID: responseID,
                status: status,
                canonicalText: canonicalText(in: response)
            )
        case "error":
            return .providerError
        default:
            return .other
        }
    }

    private func encode(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw RealtimeResidentBrainError.invalidEvent
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeResidentBrainError.invalidEvent
        }
        return text
    }

    private func eventID() -> String {
        "event_\(UUID().uuidString.lowercased())"
    }

    private func audioMilliseconds(
        _ key: String,
        in object: [String: Any]
    ) -> Int? {
        guard let number = object[key] as? NSNumber,
              String(cString: number.objCType) != "c",
              let value = Int(number.stringValue), value >= 0 else { return nil }
        return value
    }

    private func itemID(in object: [String: Any]) throws -> String {
        guard let value = object["item_id"] as? String,
              !value.isEmpty else {
            throw invalidQwenReceiveEvent("item_id")
        }
        return value
    }

    private func responseID(in object: [String: Any]) throws -> String {
        if let value = object["response_id"] as? String, !value.isEmpty {
            return value
        }
        if let response = object["response"] as? [String: Any],
           let value = response["id"] as? String,
           !value.isEmpty {
            return value
        }
        throw invalidQwenReceiveEvent("response_id")
    }

    private func turnDetectionEcho(
        in object: [String: Any]
    ) -> QwenRealtimeTurnDetectionEcho? {
        guard let session = object["session"] as? [String: Any],
              let value = session["turn_detection"] as? [String: Any] else {
            return nil
        }
        return QwenRealtimeTurnDetectionEcho(
            type: value["type"] as? String,
            threshold: value["threshold"] as? Double,
            silenceDurationMilliseconds:
                value["silence_duration_ms"] as? Int,
            createResponse: value["create_response"] as? Bool,
            interruptResponse: value["interrupt_response"] as? Bool
        )
    }

    private func string(
        _ key: String,
        in object: [String: Any]
    ) throws -> String {
        guard let value = object[key] as? String else {
            throw invalidQwenReceiveEvent("required_string")
        }
        return value
    }

    private func canonicalText(in response: [String: Any]) -> String? {
        guard let output = response["output"] as? [Any] else { return nil }
        var candidates: [String] = []
        for value in output {
            guard let item = value as? [String: Any],
                  item["type"] as? String != "function_call",
                  let content = item["content"] as? [Any] else { continue }
            for partValue in content {
                guard let part = partValue as? [String: Any] else { continue }
                if let transcript = part["transcript"] as? String {
                    candidates.append(transcript)
                } else if let text = part["text"] as? String {
                    candidates.append(text)
                }
            }
        }
        let joined = candidates.joined().trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return joined.isEmpty ? nil : joined
    }
}

nonisolated private enum QwenRealtimePCM16Converter {
    static func mono16k(_ frame: RealtimeBrainAudioFrame) throws -> Data {
        guard frame.format.encoding == .pcm16LittleEndian,
              frame.format.channelCount == 1,
              !frame.bytes.isEmpty,
              frame.bytes.count.isMultiple(of: 2) else {
            throw RealtimeResidentBrainError.invalidAudioFrame
        }
        switch frame.format.sampleRate {
        case 16_000:
            return frame.bytes
        case 24_000:
            return try convert24kTo16k(frame.bytes)
        case 48_000:
            return try convert48kTo16k(frame.bytes)
        default:
            throw RealtimeResidentBrainError.invalidAudioFrame
        }
    }

    private static func convert24kTo16k(_ data: Data) throws -> Data {
        let input = [UInt8](data)
        guard input.count.isMultiple(of: 6) else {
            throw RealtimeResidentBrainError.invalidAudioFrame
        }
        var output = Data(capacity: input.count * 2 / 3)
        for offset in stride(from: 0, to: input.count, by: 6) {
            append(sample(input, at: offset), to: &output)
            append(Int16(
                (Int32(sample(input, at: offset + 2))
                    + Int32(sample(input, at: offset + 4))) / 2
            ), to: &output)
        }
        return output
    }

    private static func convert48kTo16k(_ data: Data) throws -> Data {
        let input = [UInt8](data)
        guard input.count.isMultiple(of: 6) else {
            throw RealtimeResidentBrainError.invalidAudioFrame
        }
        var output = Data(capacity: input.count / 3)
        for offset in stride(from: 0, to: input.count, by: 6) {
            append(Int16(
                (Int32(sample(input, at: offset))
                    + Int32(sample(input, at: offset + 2))
                    + Int32(sample(input, at: offset + 4))) / 3
            ), to: &output)
        }
        return output
    }

    private static func sample(_ bytes: [UInt8], at offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(bytes[offset])
            | UInt16(bytes[offset + 1]) << 8)
    }

    private static func append(_ sample: Int16, to data: inout Data) {
        let bits = UInt16(bitPattern: sample)
        data.append(UInt8(truncatingIfNeeded: bits))
        data.append(UInt8(truncatingIfNeeded: bits >> 8))
    }
}

nonisolated private struct QwenRealtimeInputAudioBatcher {
    static let batchByteCount = 3_200

    private struct PendingSegment {
        var byteCount: Int
        let isAcousticEchoProcessed: Bool
    }

    struct Batch {
        let bytes: Data
        let isAcousticEchoProcessed: Bool
    }

    private var pendingBytes = Data()
    private var pendingSegments: [PendingSegment] = []

    mutating func append(
        _ bytes: Data,
        isAcousticEchoProcessed: Bool
    ) -> [Batch] {
        guard !bytes.isEmpty else { return [] }
        pendingBytes.append(bytes)
        if pendingSegments.last?.isAcousticEchoProcessed
            == isAcousticEchoProcessed {
            pendingSegments[pendingSegments.count - 1].byteCount += bytes.count
        } else {
            pendingSegments.append(PendingSegment(
                byteCount: bytes.count,
                isAcousticEchoProcessed: isAcousticEchoProcessed
            ))
        }
        var batches: [Batch] = []
        while pendingBytes.count >= Self.batchByteCount {
            var remainingByteCount = Self.batchByteCount
            var batchIsAcousticEchoProcessed = true
            while remainingByteCount > 0 {
                let consumedByteCount = min(
                    remainingByteCount,
                    pendingSegments[0].byteCount
                )
                batchIsAcousticEchoProcessed =
                    batchIsAcousticEchoProcessed
                    && pendingSegments[0].isAcousticEchoProcessed
                pendingSegments[0].byteCount -= consumedByteCount
                remainingByteCount -= consumedByteCount
                if pendingSegments[0].byteCount == 0 {
                    pendingSegments.removeFirst()
                }
            }
            batches.append(Batch(
                bytes: Data(pendingBytes.prefix(Self.batchByteCount)),
                isAcousticEchoProcessed: batchIsAcousticEchoProcessed
            ))
            pendingBytes.removeFirst(Self.batchByteCount)
        }
        return batches
    }

    mutating func reset() {
        pendingBytes.removeAll(keepingCapacity: true)
        pendingSegments.removeAll(keepingCapacity: true)
    }
}

actor QwenRealtimeResidentBrainAdapter:
    RealtimeResidentBrainProvider {
    private static let maximumPendingEventCount = 256
    private static let transcriptFinalFallbackDelay: Duration =
        .milliseconds(500)

    private enum Lifecycle {
        case closed
        case opening
        case awaitingBootstrap
        case active
        case transitioning
        case closing
        case failed
    }

    private enum Acknowledgement: Hashable, Sendable {
        case sessionUpdated(UInt64)
        case responseDone(String)
        case inputAudioCleared(UInt64)
        case responseCreated(UInt64)
    }

    private enum ResidentTextWireSource {
        case text
        case audioTranscript
    }

    private struct ActiveResponse {
        let wireID: String
        let runtimeID: RealtimeBrainResponseID
        let turnID: RealtimeBrainTurnID
        let sessionIdentity: RealtimeBrainSessionIdentity
        let contextRevision: UInt64
        var text = ""
        var finalText: String?
        var residentTextWireSource: ResidentTextWireSource?
        var didEmitTextFinal = false
        var isSpeaking = false
        var hasToolCall = false
    }

    private struct TurnBinding: Equatable {
        let runtimeID: RealtimeBrainTurnID
        let sessionIdentity: RealtimeBrainSessionIdentity
        let contextRevision: UInt64
    }

    private struct ActiveUserInputTurn {
        var wireItemID: String
        var turn: TurnBinding
        var latestTranscriptPartial: String?
        var audioStartMilliseconds: Int?
        var unboundTranscript: (itemID: String, preview: String)?
        var hasAmbiguousItem = false
        var didReassociateItem = false
        var speechStopped = false
        var transcriptFinal: String?
    }

    private struct TranscriptFinalFallback {
        let token: UUID
        let task: Task<Void, Never>
    }

    private enum ResponseAuthorizationKind: Equatable {
        case runtime(sourceEventSequence: UInt64)
        case toolContinuation(callID: RealtimeBrainToolCallID)
    }

    private struct PendingResponseAuthorization: Equatable {
        let acknowledgement: Acknowledgement
        let turn: TurnBinding
        let kind: ResponseAuthorizationKind
        var attempt: RealtimeBrainResponseAttempt?
        var wasSubmitted = false
    }

    private struct EventWaiter {
        let session: RealtimeBrainSessionIdentity
        let continuation:
            CheckedContinuation<RealtimeResidentBrainEvent, any Error>
    }

    private struct AcknowledgementWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let credentialReader: ProviderCredentialReading
    private let transport: RealtimeWebSocketTransport
    private let configuration: QwenRealtimeResidentBrainConfiguration
    private let diagnosticBuffer: NativeSpeechDiagnosticBuffer?
    private let codec = QwenRealtimeResidentBrainCodec()

    private var lifecycle = Lifecycle.closed
    private var identity: RealtimeBrainSessionIdentity?
    private var closedSessionIdentity: RealtimeBrainSessionIdentity?
    private var contextRevision: UInt64 = 0
    private var connectionToken: UUID?
    private var receiverTask: Task<Void, Never>?
    private var terminalTransportCloseTask: Task<Void, Never>?
    private var terminalError: RealtimeResidentBrainError?
    #if DEBUG
    private var receivedWireSequence: UInt64 = 0
    var responseCatchBarrierForTesting: (@Sendable () async -> Void)?

    func hasRetiringResponseForTesting() -> Bool {
        retiringWireResponseID != nil
    }

    func hasResponseRequestForTesting() -> Bool { pendingResponseAuthorization != nil }

    func responseDoneWaiterIDsForTesting(_ responseID: String) -> [UUID] {
        acknowledgementWaiters[.responseDone(responseID)]?.map(\.id) ?? []
    }

    func fireResponseDoneTimeoutForTesting(_ responseID: String, waiterID: UUID) {
        timeout(.responseDone(responseID), waiterID: waiterID, connectionToken: connectionToken)
    }

    func setResponseCatchBarrierForTesting(_ barrier: (@Sendable () async -> Void)?) {
        responseCatchBarrierForTesting = barrier
    }
    #endif

    private var acknowledgementSerial: UInt64 = 0
    private var expectedSessionUpdate: Acknowledgement?
    private var expectedInputClear: Acknowledgement?
    private var pendingResponseAuthorization: PendingResponseAuthorization?
    private var acknowledgementWaiters:
        [Acknowledgement: [AcknowledgementWaiter]] = [:]
    private var deliveredAcknowledgements: Set<Acknowledgement> = []

    private var pendingEvents: [RealtimeResidentBrainEvent] = []
    private var eventWaiter: EventWaiter?
    private var nextEventSequence: UInt64 = 0
    private var outputAudioSequence: UInt64 = 0
    private var outputAudioSampleFrames: UInt64 = 0
    private var inputAudioBatcher = QwenRealtimeInputAudioBatcher()
    private var preservingUserInputDuringTransition = false
    private var contextSectionsByScope: [String: String] = [:]
    private var runtimeTools: [RealtimeBrainToolAdvertisement] = []
    private var runtimeVoiceBinding: RuntimeVoiceBinding?
    private var resolvedVoice: QwenResolvedRealtimeVoice?

    private var turnsByWireItemID:
        [String: TurnBinding] = [:]
    private var latestTurnBinding: TurnBinding?
    private var lastUserTranscriptPreviewByItemID: [String: String] = [:]
    private var activeUserInputTurn: ActiveUserInputTurn?
    private var transcriptFinalFallbackTasks:
        [String: TranscriptFinalFallback] = [:]
    private var activeResponse: ActiveResponse?
    private var completedUserInputItemIDs: Set<String> = []
    private var completedUserInputItemOrder: [String] = []
    private var stoppedUserInputItemIDs: Set<String> = []
    private var stoppedUserInputItemOrder: [String] = []
    private var retiredItemIDs: Set<String> = []
    private var retiredItemOrder: [String] = []
    private var retiredResponseIDs: Set<String> = []
    private var retiredResponseOrder: [String] = []
    private var pendingToolCalls:
        [RealtimeBrainToolCallID: RealtimeBrainEventIdentity] = [:]
    private var locallyCancellingResponseID: String?
    private var retiringWireResponseID: String?
    private var retiringResponseAttempt: RealtimeBrainResponseAttempt?
    private var activeMutationOperations: Set<UUID> = []

    init(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        configuration: QwenRealtimeResidentBrainConfiguration,
        diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.configuration = configuration
        self.diagnosticBuffer = diagnosticBuffer
    }

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        guard lifecycle == .closed,
              identity == nil,
              terminalTransportCloseTask == nil,
              configuration.modelID
                == QwenRealtimeResidentBrainConfiguration.supportedModelID,
              !configuration.keyRef.isEmpty else {
            throw RealtimeResidentBrainError.unavailable
        }
        let resolvedVoice = try resolveVoiceBinding(
            command.voiceBinding,
            expectedIdentity: command.identity
        )
        lifecycle = .opening
        identity = command.identity
        closedSessionIdentity = nil
        contextRevision = 0
        terminalError = nil
        resetSessionState()
        runtimeTools = command.tools
        runtimeVoiceBinding = command.voiceBinding
        self.resolvedVoice = resolvedVoice

        do {
            let credential = try readCredential()
            let endpoint = try credential.endpoint(
                configuredEndpoint: configuration.endpoint,
                modelID: configuration.modelID
            )
            try await transport.connect(
                endpoint: endpoint,
                bearerToken: credential.apiKey
            )
            guard case .sessionCreated = try await receiveHandshakeEvent()
            else {
                throw RealtimeResidentBrainError.invalidEvent
            }
            try await send(codec.initialSessionUpdate(
                instructions: "Runtime context bootstrap pending.",
                tools: runtimeTools,
                voice: resolvedVoice
            ))
            recordTurnDetectionRequest()
            let sessionUpdate = try await receiveHandshakeEvent()
            guard case .sessionUpdated(let turnDetection) = sessionUpdate else {
                throw RealtimeResidentBrainError.invalidEvent
            }
            try validateTurnDetectionAcknowledgement(
                turnDetection,
                requiresCompletePolicy: true
            )
            recordTurnDetectionAcknowledgement(turnDetection)
            let token = UUID()
            connectionToken = token
            lifecycle = .awaitingBootstrap
            startReceiver(connectionToken: token)
        } catch {
            await failOpen(command.identity)
            throw Self.map(error)
        }
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {
        try requireIdentity(update.identity)
        switch update.kind {
        case .bootstrap:
            guard lifecycle == .awaitingBootstrap,
                  contextRevision == 0,
                  update.contextRevision > 0 else {
                throw RealtimeResidentBrainError.invalidContextRevision
            }
        case .delta:
            guard lifecycle == .active,
                  update.contextRevision > contextRevision else {
                throw RealtimeResidentBrainError.invalidContextRevision
            }
        }
        let operationID = beginMutationOperation()
        defer { finishMutationOperation(operationID) }
        let acknowledgement = nextSessionUpdateAcknowledgement()
        expectedSessionUpdate = acknowledgement
        let nextContextSections = Self.applying(
            update,
            to: contextSectionsByScope
        )
        do {
            try await send(codec.contextUpdate(
                instructions: Self.instructions(from: nextContextSections)
            ))
            try await waitForAcknowledgement(acknowledgement)
            expectedSessionUpdate = nil
            contextSectionsByScope = nextContextSections
            if update.kind == .delta {
                rebindPendingUserActivity(
                    from: contextRevision,
                    to: update.contextRevision
                )
            }
            contextRevision = update.contextRevision
            if update.kind == .bootstrap {
                lifecycle = .active
                enqueue(kind: .sessionReady)
            }
        } catch {
            expectedSessionUpdate = nil
            lifecycle = .failed
            throw Self.map(error)
        }
    }

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {
        try requireActive(frame.identity)
        guard frame.provenance != .providerGenerated else {
            throw RealtimeResidentBrainError.invalidAudioFrame
        }
        let operationID = beginMutationOperation()
        defer { finishMutationOperation(operationID) }
        do {
            let batches = inputAudioBatcher.append(
                try QwenRealtimePCM16Converter.mono16k(frame),
                isAcousticEchoProcessed:
                    frame.provenance == .acousticEchoProcessed
            )
            for batch in batches {
                let hadActiveResponse = activeResponse != nil
                try await send(codec.audioAppend(batch.bytes))
                #if DEBUG
                if batch.isAcousticEchoProcessed {
                    diagnosticBuffer?.appendRealtimeAudioCapsuleBatch(
                        batch.bytes,
                        identity: frame.identity,
                        audioSequence: frame.sequence
                    )
                }
                #endif
                if let diagnosticBuffer {
                    let metrics = Self.pcmMetrics(batch.bytes)
                    diagnosticBuffer.append(
                        NativeSpeechInternalDiagnosticEvent(
                            source: .adapter,
                            category: hadActiveResponse
                                ? "qwen_active_response_input_audio_batch"
                                : "qwen_listening_input_audio_batch",
                            routeKind: .realtimeBrain,
                            turnGeneration: frame.identity.generation,
                            disposition: "transport_enqueued",
                            audioSequence: frame.sequence,
                            byteCount: batch.bytes.count,
                            pcmPeak: metrics.peak,
                            pcmRMS: metrics.rms
                        )
                    )
                }
            }
        } catch {
            throw Self.map(error)
        }
    }

    func createResponse(
        _ command: RealtimeBrainCreateResponseCommand
    ) async throws {
        try requireActive(command.identity.session)
        guard command.identity.responseID == nil,
              command.sourceEventSequence > 0,
              let turn = exactTurnBinding(for: command.identity) else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        let operationID = beginMutationOperation()
        defer { finishMutationOperation(operationID) }
        do {
            try await requestResponse(
                for: turn,
                kind: .runtime(
                    sourceEventSequence: command.sourceEventSequence
                ),
                attempt: command.attempt
            )
        } catch let failure as RealtimeBrainResponseAttemptFailure {
            if failure.submission != .notSubmitted, command.attempt.snapshot().valid,
               identity == command.identity.session {
                lifecycle = .failed
            }
            throw failure
        } catch {
            if identity == command.identity.session { lifecycle = .failed }
            throw Self.map(error)
        }
    }

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {
        try requireActive(command.identity.session)
        guard command.identity.contextRevision == contextRevision,
              pendingToolCalls[command.callID] == command.identity,
              let turn = exactTurnBinding(for: command.identity) else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        let operationID = beginMutationOperation()
        defer { finishMutationOperation(operationID) }
        do {
            if let response = activeResponse,
               makeEventIdentity(for: response) == command.identity {
                try await waitForAcknowledgement(
                    .responseDone(response.wireID)
                )
            }
            try await send(codec.toolOutput(
                callID: command.callID.rawValue,
                output: command.output,
                isError: command.isError
            ))
            pendingToolCalls.removeValue(forKey: command.callID)
            if !pendingToolCalls.values.contains(command.identity) {
                try await requestResponse(
                    for: turn,
                    kind: .toolContinuation(callID: command.callID)
                )
            }
        } catch {
            pendingResponseAuthorization = nil
            lifecycle = .failed
            throw Self.map(error)
        }
    }

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {
        try requireActive(command.identity)
        let next = Self.nextIdentity(
            from: command.identity,
            generation: command.nextGeneration
        )
        try await transitionGeneration(
            to: next,
            reason: command.reason,
            clearInput: true,
            reconnect: true,
            preserveInterruptingUserInput: false
        )
    }

    func interrupt(_ command: RealtimeBrainInterruptCommand) async throws {
        try requireActive(command.identity)
        let next = Self.nextIdentity(
            from: command.identity,
            generation: command.nextGeneration
        )
        try await transitionGeneration(
            to: next,
            reason: .interrupted,
            clearInput: true,
            reconnect: false,
            preserveInterruptingUserInput: true
        )
    }

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        try requireActive(session)
        if !pendingEvents.isEmpty {
            let event = pendingEvents.removeFirst()
            recordTranscriptFinalQueueDiagnostic(
                event,
                category: "qwen_transcript_final_delivered",
                disposition: "dequeued",
                queueDepth: pendingEvents.count
            )
            return event
        }
        if let terminalError { throw terminalError }
        guard eventWaiter == nil else {
            throw RealtimeResidentBrainError.operationInFlight
        }
        return try await withCheckedThrowingContinuation { continuation in
            eventWaiter = EventWaiter(
                session: session,
                continuation: continuation
            )
        }
    }

    #if DEBUG
    func hasPendingEventWaiterForTesting(
        session: RealtimeBrainSessionIdentity
    ) -> Bool {
        eventWaiter?.session == session
    }

    func activeWireResponseIDForTesting(
        session: RealtimeBrainSessionIdentity
    ) -> String? {
        guard identity == session else { return nil }
        return activeResponse?.wireID
    }

    func isWaitingForResponseDoneForTesting(
        _ responseID: String,
        session: RealtimeBrainSessionIdentity
    ) -> Bool {
        guard identity == session else { return false }
        return acknowledgementWaiters[.responseDone(responseID)] != nil
    }

    func terminalErrorForTesting(
        session: RealtimeBrainSessionIdentity
    ) -> RealtimeResidentBrainError? {
        guard identity == session else { return nil }
        return terminalError
    }

    func isClosingForTesting(
        session: RealtimeBrainSessionIdentity
    ) -> Bool {
        identity == session && lifecycle == .closing
    }

    func pendingEventCountForTesting(
        session: RealtimeBrainSessionIdentity
    ) -> Int {
        identity == session ? pendingEvents.count : 0
    }

    func contextRevisionForTesting(
        session: RealtimeBrainSessionIdentity
    ) -> UInt64? {
        identity == session ? contextRevision : nil
    }
    #endif

    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws {
        if lifecycle == .closed {
            guard closedSessionIdentity.map({
                Self.sameSession($0, command.identity)
            }) ?? true else {
                throw RealtimeResidentBrainError.invalidIdentity
            }
            return
        }
        guard let current = identity,
              Self.sameSession(current, command.identity) else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        lifecycle = .closing
        connectionToken = nil
        let oldReceiver = receiverTask
        receiverTask = nil
        oldReceiver?.cancel()
        if let terminalTransportCloseTask {
            await terminalTransportCloseTask.value
        } else {
            await transport.close(reason: .normal)
            _ = await oldReceiver?.value
        }
        terminalTransportCloseTask = nil
        failWaiters(with: .cancelled)
        closedSessionIdentity = command.identity
        identity = nil
        contextRevision = 0
        lifecycle = .closed
        resetSessionState()
    }

    private func transitionGeneration(
        to next: RealtimeBrainSessionIdentity,
        reason: RealtimeBrainCancellationReason,
        clearInput: Bool,
        reconnect: Bool,
        preserveInterruptingUserInput: Bool
    ) async throws {
        guard let current = identity,
              next.generation > current.generation,
              let nextVoiceBinding = runtimeVoiceBinding?.rebound(
                to: next
              ) else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        guard activeMutationOperations.isEmpty else {
            throw RealtimeResidentBrainError.operationInFlight
        }
        let interruptingTurnID = preserveInterruptingUserInput
            ? activeUserInputTurn?.turn.runtimeID : nil
        preservingUserInputDuringTransition = interruptingTurnID != nil
        defer { preservingUserInputDuringTransition = false }
        lifecycle = .transitioning
        do {
            if let responseID = activeResponse?.wireID {
                locallyCancellingResponseID = responseID
                if !reconnect { retiringWireResponseID = responseID }
                try await send(codec.responseCancel())
                if reconnect {
                    try await waitForAcknowledgement(.responseDone(responseID))
                } else {
                    // Omni does not guarantee a response.done acknowledgement for cancel.
                    // Fence old output locally so the interrupting input can keep flowing.
                    if let terminalError { throw terminalError }
                    try requireOwnedGenerationTransition(current)
                    finishActiveResponse(responseID)
                }
                locallyCancellingResponseID = nil
            }
            if clearInput && interruptingTurnID == nil {
                acknowledgementSerial &+= 1
                let acknowledgement = Acknowledgement.inputAudioCleared(
                    acknowledgementSerial
                )
                expectedInputClear = acknowledgement
                try await send(codec.inputAudioClear())
                try await waitForAcknowledgement(acknowledgement)
                expectedInputClear = nil
            }
            let carriedUserInput = activeUserInputTurn.flatMap { state in
                state.turn.runtimeID == interruptingTurnID ? state : nil
            }
            let carriedInputAudioBatcher: QwenRealtimeInputAudioBatcher?
            if carriedUserInput == nil {
                carriedInputAudioBatcher = nil
            } else {
                carriedInputAudioBatcher = inputAudioBatcher
                inputAudioBatcher = QwenRealtimeInputAudioBatcher()
            }
            retireCurrentGenerationWireState(
                preservingItemID: carriedUserInput?.wireItemID
            )
            let nextConnectionToken: UUID?
            if reconnect {
                nextConnectionToken = try await reconnectForGeneration(
                    expectedIdentity: current
                )
            } else {
                nextConnectionToken = nil
            }
            resumeStaleEventWaiter(
                expected: current,
                reason: reason
            )
            identity = next
            runtimeVoiceBinding = nextVoiceBinding
            resetGenerationStatePreservingTombstones()
            if let carriedUserInput, let carriedInputAudioBatcher {
                restoreInterruptingUserInput(
                    carriedUserInput,
                    inputAudioBatcher: carriedInputAudioBatcher,
                    session: next
                )
            }
            if let nextConnectionToken {
                resetWireTombstones()
                connectionToken = nextConnectionToken
            }
            lifecycle = .active
            if let nextConnectionToken {
                startReceiver(connectionToken: nextConnectionToken)
                enqueue(kind: .cancelled(reason))
            }
        } catch {
            expectedInputClear = nil
            locallyCancellingResponseID = nil
            let mapped = Self.map(error)
            if lifecycle == .transitioning, identity == current {
                lifecycle = .failed
                terminalError = mapped
                failWaiters(with: mapped)
            }
            throw mapped
        }
    }

    private func reconnectForGeneration(
        expectedIdentity: RealtimeBrainSessionIdentity
    ) async throws -> UUID {
        connectionToken = nil
        let oldReceiver = receiverTask
        receiverTask = nil
        oldReceiver?.cancel()
        await transport.close(reason: .cancelled)
        _ = await oldReceiver?.value
        try requireOwnedGenerationTransition(expectedIdentity)

        let credential = try readCredential()
        let endpoint = try credential.endpoint(
            configuredEndpoint: configuration.endpoint,
            modelID: configuration.modelID
        )
        var didConnect = false
        do {
            try await transport.connect(
                endpoint: endpoint,
                bearerToken: credential.apiKey
            )
            didConnect = true
            try requireOwnedGenerationTransition(expectedIdentity)
            guard case .sessionCreated = try await receiveHandshakeEvent()
            else {
                throw RealtimeResidentBrainError.invalidEvent
            }
            try requireOwnedGenerationTransition(expectedIdentity)
            guard let resolvedVoice else {
                throw RealtimeResidentBrainError.voiceBindingUnavailable
            }
            try await send(codec.initialSessionUpdate(
                instructions: Self.instructions(from: contextSectionsByScope),
                tools: runtimeTools,
                voice: resolvedVoice
            ))
            recordTurnDetectionRequest()
            let sessionUpdate = try await receiveHandshakeEvent()
            guard case .sessionUpdated(let turnDetection) = sessionUpdate else {
                throw RealtimeResidentBrainError.invalidEvent
            }
            try validateTurnDetectionAcknowledgement(
                turnDetection,
                requiresCompletePolicy: true
            )
            recordTurnDetectionAcknowledgement(turnDetection)
            try requireOwnedGenerationTransition(expectedIdentity)
            return UUID()
        } catch {
            if didConnect,
               lifecycle == .transitioning,
               identity == expectedIdentity {
                await transport.close(reason: .cancelled)
            }
            throw error
        }
    }

    private func requireOwnedGenerationTransition(
        _ expectedIdentity: RealtimeBrainSessionIdentity
    ) throws {
        guard lifecycle == .transitioning,
              identity == expectedIdentity else {
            throw RealtimeResidentBrainError.cancelled
        }
    }

    private func startReceiver(connectionToken token: UUID) {
        let transport = self.transport
        receiverTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let frame = try await transport.receive()
                    guard let self else { return }
                    await self.handle(frame, connectionToken: token)
                } catch {
                    guard let self else { return }
                    await self.handleReceiverFailure(
                        error,
                        connectionToken: token
                    )
                    return
                }
            }
        }
    }

    private func handle(
        _ frame: RealtimeWebSocketFrame,
        connectionToken token: UUID
    ) {
        guard connectionToken == token else { return }
        #if DEBUG
        receivedWireSequence &+= 1
        #endif
        var phase = "decode"
        do {
            let event = try codec.decode(frame)
            phase = "state"
            try handle(event)
        } catch {
            handleReceiverFailure(
                error, connectionToken: token, phase: phase, frame: frame
            )
        }
    }

    private func handle(_ event: QwenRealtimeBrainWireEvent) throws {
        switch event {
        case .sessionCreated:
            throw invalidQwenReceiveEvent("unexpected_session_created")
        case .sessionUpdated(let turnDetection):
            try validateTurnDetectionAcknowledgement(turnDetection)
            recordTurnDetectionAcknowledgement(turnDetection)
            if let acknowledgement = expectedSessionUpdate {
                deliver(acknowledgement)
            }
        case .inputAudioCleared:
            if let acknowledgement = expectedInputClear {
                deliver(acknowledgement)
            }
        case .inputSpeechStarted(let itemID, let audioStartMilliseconds):
            diagnosticBuffer?.append(
                NativeSpeechInternalDiagnosticEvent(
                    source: .adapter,
                    category: "qwen_speech_started_received",
                    routeKind: .realtimeBrain,
                    turnGeneration: identity?.generation,
                    disposition: activeResponse == nil
                        ? "listening" : "active_response",
                    itemCorrelationHash: Self.correlationHash(itemID)
                )
            )
            guard lifecycle == .active,
                  !completedUserInputItemIDs.contains(itemID) else { return }
            guard let turn = turnBinding(for: itemID, createsIfNeeded: true)
            else { return }
            activeUserInputTurn = ActiveUserInputTurn(
                wireItemID: itemID,
                turn: turn,
                latestTranscriptPartial: nil,
                audioStartMilliseconds: audioStartMilliseconds
            )
            if let response = activeResponse {
                let eventIdentity = makeEventIdentity(for: response)
                enqueue(kind: .interruptionProposed(
                    RealtimeBrainInterruptionProposal(
                        identity: eventIdentity,
                        reason: "user_speech_started_during_resident_response"
                    )
                ), identity: eventIdentity)
            }
            enqueue(
                kind: .userSpeechStarted,
                identity: makeEventIdentity(for: turn)
            )
        case .unidentifiedSpeechStopped(let audioEndMilliseconds):
            if let itemID = uniquelyStoppedUserItem(audioEndMilliseconds: audioEndMilliseconds) {
                recordUserInputWireDiagnostic(
                    category: "qwen_speech_stopped_associated", itemID: itemID
                )
                try handle(.inputSpeechStopped(itemID: itemID, audioEndMilliseconds: audioEndMilliseconds))
                return
            }
            diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
                source: .adapter,
                category: "qwen_speech_stopped_rejected",
                routeKind: .realtimeBrain,
                turnGeneration: identity?.generation,
                disposition: "empty_item_id"
            ))
        case .inputSpeechStopped(let itemID, let audioEndMilliseconds):
            recordUserInputWireDiagnostic(
                category: "qwen_speech_stopped_received",
                itemID: itemID
            )
            guard !stoppedUserInputItemIDs.contains(itemID) else { return }
            reassociateUserInputAtSpeechStop(
                itemID: itemID,
                audioEndMilliseconds: audioEndMilliseconds
            )
            if lifecycle == .transitioning,
               recordActiveUserSpeechStopped(itemID: itemID) {
                markUserInputStopped(itemID)
                return
            }
            guard lifecycle == .active,
                  let turn = turnBinding(
                    for: itemID,
                    createsIfNeeded: false
                  ) else { return }
            if activeUserInputTurn?.wireItemID == itemID,
               !recordActiveUserSpeechStopped(itemID: itemID) {
                return
            }
            markUserInputStopped(itemID)
            enqueue(
                kind: .userSpeechStopped,
                identity: makeEventIdentity(for: turn)
            )
            scheduleTranscriptFinalFallback(itemID: itemID)
        case .inputTranscriptDelta(let itemID, let preview):
            recordUserInputWireDiagnostic(
                category: "qwen_transcript_partial_received",
                itemID: itemID
            )
            guard !completedUserInputItemIDs.contains(itemID) else { return }
            let trimmedPreview = preview.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            recordUnboundUserTranscript(preview, itemID: itemID)
            if lifecycle == .transitioning,
               !trimmedPreview.isEmpty,
               lastUserTranscriptPreviewByItemID[itemID] != preview,
               recordActiveUserTranscriptPartial(
                   preview,
                   itemID: itemID
               ) {
                lastUserTranscriptPreviewByItemID[itemID] = preview
                return
            }
            guard lifecycle == .active,
                  let turn = turnBinding(
                    for: itemID,
                    createsIfNeeded: false
                  ),
                  !trimmedPreview.isEmpty,
                  lastUserTranscriptPreviewByItemID[itemID] != preview else {
                return
            }
            lastUserTranscriptPreviewByItemID[itemID] = preview
            if activeUserInputTurn?.wireItemID == itemID {
                _ = recordActiveUserTranscriptPartial(
                    preview,
                    itemID: itemID
                )
            }
            enqueue(
                kind: .userTranscriptPartial(preview),
                identity: makeEventIdentity(for: turn)
            )
            if stoppedUserInputItemIDs.contains(itemID) {
                scheduleTranscriptFinalFallback(itemID: itemID)
            }
        case .inputTranscriptCompleted(let itemID, let transcript):
            recordUserInputWireDiagnostic(
                category: "qwen_transcript_final_received",
                itemID: itemID
            )
            guard !completedUserInputItemIDs.contains(itemID) else { return }
            let trimmedTranscript = transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if lifecycle == .transitioning,
               !trimmedTranscript.isEmpty,
               recordActiveUserTranscriptFinal(
                   transcript,
                   itemID: itemID
               ) {
                cancelTranscriptFinalFallback(
                    itemID: itemID,
                    reason: "provider_final_during_transition"
                )
                lastUserTranscriptPreviewByItemID[itemID] = transcript
                markUserInputCompleted(itemID)
                return
            }
            guard lifecycle == .active,
                  let turn = turnBinding(
                    for: itemID,
                    createsIfNeeded: false
                  ),
                  !trimmedTranscript.isEmpty else { return }
            cancelTranscriptFinalFallback(
                itemID: itemID,
                reason: "provider_final"
            )
            lastUserTranscriptPreviewByItemID[itemID] = transcript
            if activeUserInputTurn?.wireItemID == itemID {
                _ = recordActiveUserTranscriptFinal(
                    transcript,
                    itemID: itemID
                )
            }
            markUserInputCompleted(itemID)
            enqueue(
                kind: .userTranscriptFinal(transcript),
                identity: makeEventIdentity(for: turn)
            )
        case .inputTranscriptFailed(let itemID):
            recordUserInputWireDiagnostic(
                category: "qwen_transcription_failed_received",
                itemID: itemID
            )
            guard !completedUserInputItemIDs.contains(itemID) else { return }
            cancelTranscriptFinalFallback(
                itemID: itemID,
                reason: "provider_transcription_failed"
            )
            if lifecycle == .transitioning {
                guard let state = activeUserInputTurn,
                      state.wireItemID == itemID,
                      state.transcriptFinal == nil else { return }
                throw RealtimeResidentBrainError.providerFailure
            }
            guard lifecycle == .active,
                  turnBinding(
                    for: itemID,
                    createsIfNeeded: false
                  ) != nil else { return }
            throw RealtimeResidentBrainError.providerFailure
        case .responseCreated(let responseID):
            guard lifecycle == .active else { return }
            if retiredResponseIDs.contains(responseID)
                || activeResponse?.wireID == responseID {
                return
            }
            guard activeResponse == nil,
                  let authorization = pendingResponseAuthorization,
                  authorization.wasSubmitted,
                  authorization.turn.sessionIdentity == identity,
                  authorization.turn.contextRevision == contextRevision else {
                throw invalidQwenReceiveEvent("response_authorization")
            }
            let turn = authorization.turn
            authorization.attempt?.submitted()
            activeResponse = ActiveResponse(
                wireID: responseID,
                runtimeID: RealtimeBrainResponseID(),
                turnID: turn.runtimeID,
                sessionIdentity: turn.sessionIdentity,
                contextRevision: turn.contextRevision
            )
            deliver(authorization.acknowledgement)
        case .responseTextDelta(let responseID, let delta):
            acceptResidentText(
                responseID: responseID,
                source: .text,
                text: delta,
                isFinal: false
            )
        case .responseAudioTranscriptDelta(let responseID, let delta):
            acceptResidentText(
                responseID: responseID,
                source: .audioTranscript,
                text: delta,
                isFinal: false
            )
        case .responseTextDone(let responseID, let text):
            acceptResidentText(
                responseID: responseID,
                source: .text,
                text: text,
                isFinal: true
            )
        case .responseAudioTranscriptDone(let responseID, let text):
            acceptResidentText(
                responseID: responseID,
                source: .audioTranscript,
                text: text,
                isFinal: true
            )
        case .responseAudioDelta(let responseID, let bytes):
            guard lifecycle == .active,
                  !bytes.isEmpty,
                  bytes.count.isMultiple(of: 2),
                  updateActiveResponse(responseID, { _ in }),
                  var response = activeResponse else { return }
            if !response.isSpeaking {
                response.isSpeaking = true
                enqueue(
                    kind: .residentSpeakingStarted,
                    identity: makeEventIdentity(for: response)
                )
            }
            outputAudioSequence &+= 1
            let timestamp = outputAudioSampleFrames
                * 1_000_000_000 / 24_000
            outputAudioSampleFrames &+= UInt64(bytes.count / 2)
            activeResponse = response
            enqueue(
                kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                    sequence: outputAudioSequence,
                    timestampNanoseconds: timestamp,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: 24_000,
                        channelCount: 1
                    ),
                    provenance: .providerGenerated,
                    bytes: bytes
                )),
                identity: makeEventIdentity(for: response)
            )
        case .responseAudioDone(let responseID):
            guard lifecycle == .active,
                  updateActiveResponse(responseID, { _ in }),
                  var response = activeResponse,
                  response.isSpeaking else { return }
            response.isSpeaking = false
            activeResponse = response
            enqueue(
                kind: .residentSpeakingStopped,
                identity: makeEventIdentity(for: response)
            )
        case .toolArgumentsDone(
            let responseID,
            let callID,
            let name,
            let arguments
        ):
            guard lifecycle == .active,
                  updateActiveResponse(responseID, { $0.hasToolCall = true }),
                  let response = activeResponse else { return }
            let eventIdentity = makeEventIdentity(for: response)
            let runtimeCallID = RealtimeBrainToolCallID(rawValue: callID)
            if pendingToolCalls[runtimeCallID] == nil {
                pendingToolCalls[runtimeCallID] = eventIdentity
            }
            enqueue(
                kind: .toolCall(RealtimeBrainToolCallCandidate(
                    identity: eventIdentity,
                    callID: runtimeCallID,
                    toolName: name,
                    arguments: arguments
                )),
                identity: eventIdentity
            )
        case .responseDone(
            let responseID,
            let status,
            let canonicalText
        ):
            if retiringWireResponseID == responseID {
                retiringWireResponseID = nil
                retiringResponseAttempt?.providerBecameReady()
                retiringResponseAttempt = nil
                finishActiveResponse(responseID)
                deliverIfWaiting(.responseDone(responseID))
                return
            }
            if locallyCancellingResponseID == responseID {
                finishActiveResponse(responseID)
                deliver(.responseDone(responseID))
                return
            }
            guard lifecycle == .active,
                  var response = activeResponse,
                  response.wireID == responseID else {
                if retiredResponseIDs.contains(responseID) { return }
                return
            }
            if response.isSpeaking {
                response.isSpeaking = false
                activeResponse = response
                enqueue(
                    kind: .residentSpeakingStopped,
                    identity: makeEventIdentity(for: response)
                )
            }
            let final = canonicalText ?? response.finalText ?? response.text
            if status == "completed" {
                if !response.didEmitTextFinal,
                   !final.trimmingCharacters(
                    in: .whitespacesAndNewlines
                   ).isEmpty {
                    response.didEmitTextFinal = true
                    enqueue(
                        kind: .residentTextFinal(final),
                        identity: makeEventIdentity(for: response)
                    )
                }
                if !response.hasToolCall,
                   !final.trimmingCharacters(
                    in: .whitespacesAndNewlines
                   ).isEmpty {
                    enqueue(
                        kind: .residentSemanticFinal(
                            RealtimeBrainSemanticOutput(
                                canonicalText: final
                            )
                        ),
                        identity: makeEventIdentity(for: response)
                    )
                } else if !response.hasToolCall {
                    enqueue(
                        kind: .error(.providerFailure),
                        identity: makeEventIdentity(for: response)
                    )
                }
            } else if status == "incomplete" {
                enqueue(
                    kind: .error(.providerFailure),
                    identity: makeEventIdentity(for: response)
                )
            } else {
                enqueue(
                    kind: .error(.providerFailure),
                    identity: makeEventIdentity(for: response)
                )
            }
            if status != "completed" {
                let failedIdentity = makeEventIdentity(for: response)
                pendingToolCalls = pendingToolCalls.filter {
                    $0.value != failedIdentity
                }
            }
            activeResponse = response
            finishActiveResponse(responseID)
            if status == "completed" {
                deliverIfWaiting(.responseDone(responseID))
            } else {
                failIfWaiting(
                    .responseDone(responseID),
                    with: .providerFailure
                )
            }
        case .providerError:
            throw RealtimeResidentBrainError.providerFailure
        case .other:
            break
        }
    }

    private func handleReceiverFailure(
        _ error: any Error,
        connectionToken token: UUID,
        phase: String = "transport_receive",
        frame: RealtimeWebSocketFrame? = nil
    ) {
        guard connectionToken == token else { return }
        if lifecycle == .closing || lifecycle == .closed {
            failWaiters(with: .cancelled)
            return
        }
        let mapped = Self.map(error)
        #if DEBUG
        if terminalError == nil {
            recordReceiveFailure(error, mapped: mapped, phase: phase, frame: frame)
        }
        #endif
        lifecycle = .failed
        terminalError = mapped
        failWaiters(with: mapped)
    }

    #if DEBUG
    private func recordReceiveFailure(
        _ error: any Error,
        mapped: RealtimeResidentBrainError,
        phase: String,
        frame: RealtimeWebSocketFrame?
    ) {
        guard let diagnosticBuffer else { return }
        let data: Data? = switch frame {
        case .text(let text): Data(text.utf8)
        case .binary(let bytes): bytes
        case nil: nil
        }
        let object = data.flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        // Only protocol constants may enter diagnostics, never arbitrary wire text.
        let wireType: String
        switch object?["type"] as? String {
        case let value? where [
            "session.created", "session.updated", "input_audio_buffer.cleared",
            "input_audio_buffer.speech_started", "input_audio_buffer.speech_stopped",
            "conversation.item.input_audio_transcription.delta",
            "conversation.item.input_audio_transcription.completed",
            "conversation.item.input_audio_transcription.failed",
            "response.created", "response.text.delta", "response.text.done",
            "response.audio_transcript.delta", "response.audio_transcript.done",
            "response.audio.delta", "response.audio.done",
            "response.function_call_arguments.done", "response.done", "error"
        ].contains(value): wireType = value
        default: wireType = frame == nil ? "none" : "unknown"
        }
        let branch = (error as? QwenRealtimeReceiveFailure)?.branch ?? "upstream_error"
        diagnosticBuffer.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: "qwen_receive_failure",
            routeKind: .realtimeBrain,
            turnGeneration: identity?.generation,
            stateBefore: String(describing: lifecycle),
            stateAfter: "failed",
            disposition: "phase=\(phase);wire=\(wireType);branch=\(branch)"
                + ";active_response=\(activeResponse != nil)"
                + ";authorization=\(pendingResponseAuthorization != nil)"
                + ";authorization_session_matches=\(pendingResponseAuthorization?.turn.sessionIdentity == identity)"
                + ";authorization_context_matches=\(pendingResponseAuthorization?.turn.contextRevision == contextRevision)"
                + ";user_input=\(activeUserInputTurn != nil)"
                + ";text_string=\(object?["text"] is String)"
                + ";stash_string=\(object?["stash"] is String)",
            wireSequence: receivedWireSequence,
            queueDepth: pendingEvents.count,
            byteCount: data?.count,
            errorCode: mapped == .invalidEvent ? "invalid_event" : String(describing: mapped)
        ))
    }
    #endif

    private func receiveHandshakeEvent() async throws
        -> QwenRealtimeBrainWireEvent {
        let transport = self.transport
        let timeout = configuration.acknowledgementTimeout
        let frame = try await withThrowingTaskGroup(
            of: RealtimeWebSocketFrame.self
        ) { group in
            group.addTask { try await transport.receive() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw RealtimeResidentBrainError.timedOut
            }
            guard let first = try await group.next() else {
                throw RealtimeResidentBrainError.transportFailure
            }
            group.cancelAll()
            return first
        }
        let event = try codec.decode(frame)
        if case .providerError = event {
            throw RealtimeResidentBrainError.providerFailure
        }
        return event
    }

    private func send(_ text: String) async throws {
        if let terminalError { throw terminalError }
        do {
            try await transport.send(.text(text))
        } catch {
            throw Self.map(error)
        }
    }

    private func waitForAcknowledgement(
        _ acknowledgement: Acknowledgement
    ) async throws {
        if deliveredAcknowledgements.remove(acknowledgement) != nil {
            return
        }
        let token = connectionToken
        let timeout = configuration.acknowledgementTimeout
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                acknowledgementWaiters[acknowledgement, default: []]
                    .append(AcknowledgementWaiter(id: waiterID, continuation: continuation))
                Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.timeout(
                        acknowledgement,
                        waiterID: waiterID,
                        connectionToken: token
                    )
                }
            }
        } onCancel: {
            Task { await self.cancelAcknowledgement(acknowledgement, waiterID: waiterID) }
        }
    }

    private func timeout(
        _ acknowledgement: Acknowledgement,
        waiterID: UUID,
        connectionToken token: UUID?
    ) {
        guard connectionToken == token else { return }
        finishAcknowledgement(acknowledgement, waiterID: waiterID, error: .timedOut)
    }

    private func cancelAcknowledgement(_ acknowledgement: Acknowledgement, waiterID: UUID) {
        finishAcknowledgement(acknowledgement, waiterID: waiterID, error: .cancelled)
    }

    private func finishAcknowledgement(
        _ acknowledgement: Acknowledgement, waiterID: UUID,
        error: RealtimeResidentBrainError
    ) {
        guard var waiters = acknowledgementWaiters[acknowledgement],
              let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        acknowledgementWaiters[acknowledgement] = waiters.isEmpty ? nil : waiters
        waiter.continuation.resume(throwing: error)
    }

    private func deliver(_ acknowledgement: Acknowledgement) {
        if let waiters = acknowledgementWaiters.removeValue(
            forKey: acknowledgement
        ) {
            waiters.forEach { $0.continuation.resume() }
        } else {
            deliveredAcknowledgements.insert(acknowledgement)
        }
    }

    private func deliverIfWaiting(_ acknowledgement: Acknowledgement) {
        guard let waiters = acknowledgementWaiters.removeValue(
            forKey: acknowledgement
        ) else { return }
        waiters.forEach { $0.continuation.resume() }
    }

    private func failIfWaiting(
        _ acknowledgement: Acknowledgement,
        with error: RealtimeResidentBrainError
    ) {
        guard let waiters = acknowledgementWaiters.removeValue(
            forKey: acknowledgement
        ) else { return }
        waiters.forEach { $0.continuation.resume(throwing: error) }
    }

    private func nextSessionUpdateAcknowledgement() -> Acknowledgement {
        acknowledgementSerial &+= 1
        return .sessionUpdated(acknowledgementSerial)
    }

    @discardableResult
    private func enqueue(
        kind: RealtimeResidentBrainEventKind,
        turnID: RealtimeBrainTurnID? = nil,
        responseID: RealtimeBrainResponseID? = nil
    ) -> Bool {
        enqueue(
            kind: kind,
            identity: makeEventIdentity(
                turnID: turnID,
                responseID: responseID
            )
        )
    }

    @discardableResult
    private func enqueue(
        kind: RealtimeResidentBrainEventKind,
        identity eventIdentity: RealtimeBrainEventIdentity
    ) -> Bool {
        let matchingWaiter = eventWaiter?.session == eventIdentity.session
        guard eventIdentity.session == identity || matchingWaiter else {
            recordTranscriptFinalQueueRejectionIfNeeded(
                kind,
                identity: eventIdentity,
                disposition: "identity_mismatch"
            )
            return false
        }
        nextEventSequence &+= 1
        let event = RealtimeResidentBrainEvent(
            identity: eventIdentity,
            sequence: nextEventSequence,
            kind: kind,
            ingressTimestampNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        if let waiter = eventWaiter, matchingWaiter {
            eventWaiter = nil
            recordTranscriptFinalQueueDiagnostic(
                event,
                category: "qwen_transcript_final_enqueued",
                disposition: "direct_waiter",
                queueDepth: pendingEvents.count
            )
            recordTranscriptFinalQueueDiagnostic(
                event,
                category: "qwen_transcript_final_delivered",
                disposition: "direct_waiter",
                queueDepth: pendingEvents.count
            )
            waiter.continuation.resume(returning: event)
        } else if eventIdentity.session == identity {
            guard pendingEvents.count < Self.maximumPendingEventCount else {
                recordTranscriptFinalQueueDiagnostic(
                    event,
                    category: "qwen_transcript_final_enqueue_rejected",
                    disposition: "buffer_overflow",
                    queueDepth: pendingEvents.count
                )
                failPendingEventBuffer()
                return false
            }
            pendingEvents.append(event)
            recordTranscriptFinalQueueDiagnostic(
                event,
                category: "qwen_transcript_final_enqueued",
                disposition: "pending_queue",
                queueDepth: pendingEvents.count
            )
        }
        return true
    }

    private func recordTranscriptFinalQueueRejectionIfNeeded(
        _ kind: RealtimeResidentBrainEventKind,
        identity eventIdentity: RealtimeBrainEventIdentity,
        disposition: String
    ) {
        guard case .userTranscriptFinal = kind else { return }
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: "qwen_transcript_final_enqueue_rejected",
            routeKind: .realtimeBrain,
            turnGeneration: eventIdentity.session.generation,
            disposition: disposition,
            itemCorrelationHash:
                wireItemCorrelationHash(for: eventIdentity),
            queueDepth: pendingEvents.count
        ))
    }

    private func recordTranscriptFinalQueueDiagnostic(
        _ event: RealtimeResidentBrainEvent,
        category: String,
        disposition: String,
        queueDepth: Int
    ) {
        guard case .userTranscriptFinal = event.kind else { return }
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: category,
            routeKind: .realtimeBrain,
            turnGeneration: event.identity.session.generation,
            disposition: disposition,
            wireSequence: event.sequence,
            itemCorrelationHash:
                wireItemCorrelationHash(for: event.identity),
            queueDepth: queueDepth
        ))
    }

    private func wireItemCorrelationHash(
        for eventIdentity: RealtimeBrainEventIdentity
    ) -> String? {
        guard let turnID = eventIdentity.turnID else { return nil }
        let itemID = turnsByWireItemID.first { entry in
            entry.value.runtimeID == turnID
                && entry.value.sessionIdentity == eventIdentity.session
        }?.key
        return itemID.map(Self.correlationHash)
    }

    private func failPendingEventBuffer() {
        pendingEvents.removeAll(keepingCapacity: true)
        terminalError = .providerFailure
        lifecycle = .failed
        connectionToken = nil
        let oldReceiver = receiverTask
        receiverTask = nil
        oldReceiver?.cancel()
        let transport = transport
        terminalTransportCloseTask = Task {
            await transport.close(reason: .cancelled)
            _ = await oldReceiver?.value
        }
        failWaiters(with: .providerFailure)
    }

    private func makeEventIdentity(
        turnID: RealtimeBrainTurnID?,
        responseID: RealtimeBrainResponseID?
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: identity!,
            turnID: turnID,
            responseID: responseID,
            contextRevision: contextRevision
        )
    }

    private func makeEventIdentity(
        for turn: TurnBinding
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: turn.sessionIdentity,
            turnID: turn.runtimeID,
            responseID: nil,
            contextRevision: turn.contextRevision
        )
    }

    private func makeEventIdentity(
        for response: ActiveResponse
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: response.sessionIdentity,
            turnID: response.turnID,
            responseID: response.runtimeID,
            contextRevision: response.contextRevision
        )
    }

    private func rebindPendingUserActivity(
        from previousContextRevision: UInt64,
        to nextContextRevision: UInt64
    ) {
        guard let identity,
              nextContextRevision > previousContextRevision else { return }
        let pendingTurnIDs = Set<RealtimeBrainTurnID>(
            pendingEvents.compactMap { event in
                guard event.identity.session == identity,
                      event.identity.contextRevision
                        == previousContextRevision,
                      event.identity.responseID == nil,
                      let turnID = event.identity.turnID,
                      case .userSpeechStarted = event.kind else { return nil }
                return turnID
            }
        )
        guard !pendingTurnIDs.isEmpty else { return }

        var reboundEventCount = 0
        pendingEvents = pendingEvents.map { event in
            guard event.identity.session == identity,
                  event.identity.contextRevision
                    == previousContextRevision,
                  event.identity.responseID == nil,
                  let turnID = event.identity.turnID,
                  pendingTurnIDs.contains(turnID),
                  Self.isUserActivity(event.kind) else { return event }
            reboundEventCount += 1
            return RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(
                    session: identity,
                    turnID: turnID,
                    responseID: nil,
                    contextRevision: nextContextRevision
                ),
                sequence: event.sequence,
                kind: event.kind,
                ingressTimestampNanoseconds: event.ingressTimestampNanoseconds
            )
        }
        let reboundWireItemIDs = turnsByWireItemID.compactMap {
            wireItemID, turn in
            turn.sessionIdentity == identity
                && turn.contextRevision == previousContextRevision
                && pendingTurnIDs.contains(turn.runtimeID)
                ? wireItemID : nil
        }
        for wireItemID in reboundWireItemIDs {
            guard let turn = turnsByWireItemID[wireItemID] else { continue }
            turnsByWireItemID[wireItemID] = TurnBinding(
                runtimeID: turn.runtimeID,
                sessionIdentity: turn.sessionIdentity,
                contextRevision: nextContextRevision
            )
        }
        if let turn = latestTurnBinding,
           turn.sessionIdentity == identity,
           turn.contextRevision == previousContextRevision,
           pendingTurnIDs.contains(turn.runtimeID) {
            latestTurnBinding = TurnBinding(
                runtimeID: turn.runtimeID,
                sessionIdentity: turn.sessionIdentity,
                contextRevision: nextContextRevision
            )
        }
        if var active = activeUserInputTurn,
           active.turn.sessionIdentity == identity,
           active.turn.contextRevision == previousContextRevision,
           pendingTurnIDs.contains(active.turn.runtimeID) {
            active.turn = TurnBinding(
                runtimeID: active.turn.runtimeID,
                sessionIdentity: identity,
                contextRevision: nextContextRevision
            )
            activeUserInputTurn = active
        }
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: "qwen_pending_user_activity_context_rebound",
            routeKind: .realtimeBrain,
            turnGeneration: identity.generation,
            stateBefore: String(previousContextRevision),
            stateAfter: String(nextContextRevision),
            disposition: "events=\(reboundEventCount)",
            itemCorrelationHash: pendingTurnIDs.count == 1
                ? pendingTurnIDs.first.map {
                    String($0.rawValue.uuidString.prefix(8))
                } : nil
        ))
    }

    private static func isUserActivity(
        _ kind: RealtimeResidentBrainEventKind
    ) -> Bool {
        switch kind {
        case .userSpeechStarted, .userSpeechStopped,
             .userTranscriptPartial, .userTranscriptFinal:
            true
        default:
            false
        }
    }

    private func requestResponse(
        for turn: TurnBinding,
        kind: ResponseAuthorizationKind,
        attempt: RealtimeBrainResponseAttempt? = nil
    ) async throws {
        guard lifecycle == .active,
              turn.sessionIdentity == identity,
              turn.contextRevision == contextRevision,
              activeResponse == nil,
              pendingResponseAuthorization == nil else {
            throw RealtimeResidentBrainError.invalidEvent
        }
        acknowledgementSerial &+= 1
        var authorization = PendingResponseAuthorization(
            acknowledgement: .responseCreated(acknowledgementSerial),
            turn: turn,
            kind: kind,
            attempt: attempt
        )
        pendingResponseAuthorization = authorization
        var failureReason = RealtimeBrainResponseAttemptFailure.Reason.responseWriteOrAcknowledgement
        do {
            // Keep capturing the rebound utterance while the retired wire response drains.
            // A local output fence is not evidence that the Provider is ready for a new response.
            if let responseID = retiringWireResponseID {
                failureReason = .retiredResponseWait
                retiringResponseAttempt = attempt
                attempt?.waitForProvider()
                try await waitForAcknowledgement(.responseDone(responseID))
                try requireActive(turn.sessionIdentity)
                guard pendingResponseAuthorization == authorization else {
                    throw RealtimeResidentBrainError.cancelled
                }
                if attempt != nil {
                    // Readiness is evidence only. Runtime must revalidate the original authorization.
                    throw RealtimeResidentBrainError.operationInFlight
                }
            }
            if let attempt {
                failureReason = .submissionPermission
                guard attempt.beginSubmission() else {
                    throw RealtimeResidentBrainError.cancelled
                }
            }
            failureReason = .responseWriteOrAcknowledgement
            authorization.wasSubmitted = true
            pendingResponseAuthorization = authorization
            try await send(codec.responseCreate())
            attempt?.submitted()
            try await waitForAcknowledgement(
                authorization.acknowledgement
            )
            guard pendingResponseAuthorization == authorization else {
                throw RealtimeResidentBrainError.cancelled
            }
            pendingResponseAuthorization = nil
        } catch {
            #if DEBUG
            await responseCatchBarrierForTesting?()
            #endif
            if pendingResponseAuthorization == authorization {
                pendingResponseAuthorization = nil
            }
            if let attempt {
                throw RealtimeBrainResponseAttemptFailure(
                    attemptID: attempt.id,
                    submission: attempt.snapshot().submission,
                    reason: failureReason,
                    error: Self.map(error)
                )
            }
            throw error
        }
    }

    private func exactTurnBinding(
        for eventIdentity: RealtimeBrainEventIdentity
    ) -> TurnBinding? {
        guard let turnID = eventIdentity.turnID else { return nil }
        return turnsByWireItemID.values.first { turn in
            turn.runtimeID == turnID
                && turn.sessionIdentity == eventIdentity.session
                && turn.contextRevision == eventIdentity.contextRevision
        }
    }

    private func turnBinding(
        for wireItemID: String,
        createsIfNeeded: Bool
    ) -> TurnBinding? {
        guard !retiredItemIDs.contains(wireItemID) else { return nil }
        if let existing = turnsByWireItemID[wireItemID] {
            latestTurnBinding = existing
            return existing
        }
        guard createsIfNeeded, let identity else { return nil }
        let value = TurnBinding(
            runtimeID: RealtimeBrainTurnID(),
            sessionIdentity: identity,
            contextRevision: contextRevision
        )
        turnsByWireItemID[wireItemID] = value
        latestTurnBinding = value
        return value
    }

    @discardableResult
    private func updateActiveResponse(
        _ wireID: String,
        _ update: (inout ActiveResponse) -> Void
    ) -> Bool {
        guard var response = activeResponse,
              response.wireID == wireID,
              response.sessionIdentity == identity,
              response.contextRevision == contextRevision,
              !retiredResponseIDs.contains(wireID) else { return false }
        update(&response)
        activeResponse = response
        return true
    }

    private func acceptResidentText(
        responseID: String,
        source: ResidentTextWireSource,
        text: String,
        isFinal: Bool
    ) {
        let hasVisibleText = !text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        guard var response = activeResponse,
              lifecycle == .active,
              !text.isEmpty,
              (!isFinal || hasVisibleText),
              (response.residentTextWireSource != nil || hasVisibleText),
              response.wireID == responseID,
              response.sessionIdentity == identity,
              response.contextRevision == contextRevision,
              !retiredResponseIDs.contains(responseID),
              response.residentTextWireSource == nil
                || response.residentTextWireSource == source else {
            return
        }
        response.residentTextWireSource = source
        if isFinal {
            response.text = text
            response.finalText = text
            guard !response.didEmitTextFinal else {
                activeResponse = response
                return
            }
            response.didEmitTextFinal = true
            activeResponse = response
            enqueue(
                kind: .residentTextFinal(text),
                identity: makeEventIdentity(for: response)
            )
        } else {
            response.text.append(text)
            activeResponse = response
            enqueue(
                kind: .residentTextDelta(text),
                identity: makeEventIdentity(for: response)
            )
        }
    }

    private func finishActiveResponse(_ responseID: String) {
        guard activeResponse?.wireID == responseID else { return }
        retire(responseID: responseID)
        activeResponse = nil
    }

    private func retire(responseID: String) {
        guard retiredResponseIDs.insert(responseID).inserted else { return }
        retiredResponseOrder.append(responseID)
        if retiredResponseOrder.count > 128 {
            retiredResponseIDs.remove(retiredResponseOrder.removeFirst())
        }
    }

    private func retire(itemID: String) {
        guard retiredItemIDs.insert(itemID).inserted else { return }
        retiredItemOrder.append(itemID)
        if retiredItemOrder.count > 256 {
            retiredItemIDs.remove(retiredItemOrder.removeFirst())
        }
    }

    private func retireCurrentGenerationWireState(
        preservingItemID: String? = nil
    ) {
        turnsByWireItemID.keys
            .filter { $0 != preservingItemID }
            .forEach { retire(itemID: $0) }
        if let responseID = activeResponse?.wireID {
            retire(responseID: responseID)
        }
    }

    private func restoreInterruptingUserInput(
        _ state: ActiveUserInputTurn,
        inputAudioBatcher: QwenRealtimeInputAudioBatcher,
        session: RealtimeBrainSessionIdentity
    ) {
        let turn = TurnBinding(
            runtimeID: state.turn.runtimeID,
            sessionIdentity: session,
            contextRevision: state.turn.contextRevision
        )
        var restored = state
        restored.turn = turn
        self.inputAudioBatcher = inputAudioBatcher
        turnsByWireItemID[state.wireItemID] = turn
        latestTurnBinding = turn
        activeUserInputTurn = restored
        if let preview = state.transcriptFinal
            ?? state.latestTranscriptPartial {
            lastUserTranscriptPreviewByItemID[state.wireItemID] = preview
        }
        let eventIdentity = makeEventIdentity(for: turn)
        enqueue(kind: .userSpeechStarted, identity: eventIdentity)
        if let preview = state.latestTranscriptPartial {
            enqueue(
                kind: .userTranscriptPartial(preview),
                identity: eventIdentity
            )
        }
        if state.speechStopped {
            enqueue(kind: .userSpeechStopped, identity: eventIdentity)
        }
        if let transcript = state.transcriptFinal {
            enqueue(
                kind: .userTranscriptFinal(transcript),
                identity: eventIdentity
            )
        }
        let eventCount = 1
            + (state.latestTranscriptPartial == nil ? 0 : 1)
            + (state.speechStopped ? 1 : 0)
            + (state.transcriptFinal == nil ? 0 : 1)
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: "qwen_interrupting_user_turn_rebound",
            routeKind: .realtimeBrain,
            turnGeneration: session.generation,
            disposition: "events=\(eventCount)",
            itemCorrelationHash: String(
                turn.runtimeID.rawValue.uuidString.prefix(8)
            )
        ))
        if state.speechStopped && state.transcriptFinal == nil {
            scheduleTranscriptFinalFallback(itemID: state.wireItemID)
        }
    }

    private var canAssociateUserInput: Bool {
        lifecycle == .active
            || (lifecycle == .transitioning && preservingUserInputDuringTransition)
    }

    private func recordUnboundUserTranscript(_ preview: String, itemID: String) {
        guard canAssociateUserInput,
              turnsByWireItemID[itemID] == nil,
              !retiredItemIDs.contains(itemID),
              !completedUserInputItemIDs.contains(itemID),
              !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var state = activeUserInputTurn,
              state.turn.sessionIdentity == identity,
              state.turn.contextRevision == contextRevision,
              state.audioStartMilliseconds != nil,
              !state.speechStopped, state.transcriptFinal == nil,
              !state.didReassociateItem else { return }
        // Qwen can replace the provisional item before its first preview.
        // Only the matching VAD stop below may bind this candidate to the turn.
        if let candidate = state.unboundTranscript, candidate.itemID != itemID {
            state.hasAmbiguousItem = true
        } else {
            state.unboundTranscript = (itemID, preview)
        }
        activeUserInputTurn = state
    }

    private func uniquelyStoppedUserItem(audioEndMilliseconds: Int?) -> String? {
        guard lifecycle == .active,
              let state = activeUserInputTurn,
              state.turn.sessionIdentity == identity,
              state.turn.contextRevision == contextRevision,
              !state.speechStopped, state.transcriptFinal == nil,
              !state.hasAmbiguousItem, state.unboundTranscript == nil,
              !state.didReassociateItem,
              let partial = state.latestTranscriptPartial,
              !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let start = state.audioStartMilliseconds,
              let end = audioEndMilliseconds, end > start else { return nil }
        // Never pick the latest turn when another unfinished item could own this stop.
        let candidates = turnsByWireItemID.filter { itemID, turn in
            turn.sessionIdentity == identity && turn.contextRevision == contextRevision
                && !retiredItemIDs.contains(itemID)
                && !completedUserInputItemIDs.contains(itemID)
                && !stoppedUserInputItemIDs.contains(itemID)
        }
        guard candidates.count == 1, candidates[state.wireItemID] == state.turn else { return nil }
        return state.wireItemID
    }

    private func reassociateUserInputAtSpeechStop(
        itemID: String,
        audioEndMilliseconds: Int?
    ) {
        guard canAssociateUserInput, turnsByWireItemID[itemID] == nil,
              !retiredItemIDs.contains(itemID),
              !completedUserInputItemIDs.contains(itemID),
              var state = activeUserInputTurn,
              state.turn.sessionIdentity == identity,
              state.turn.contextRevision == contextRevision,
              !state.speechStopped, state.transcriptFinal == nil,
              !state.hasAmbiguousItem, !state.didReassociateItem,
              let candidate = state.unboundTranscript, candidate.itemID == itemID,
              let start = state.audioStartMilliseconds, let end = audioEndMilliseconds,
              end > start else { return }
        // Final/partial alone cannot create a turn. Only this bounded VAD stop may
        // replace one provisional item ID; the Runtime turn identity stays intact.
        let previousItemID = state.wireItemID
        retire(itemID: previousItemID)
        turnsByWireItemID.removeValue(forKey: previousItemID)
        lastUserTranscriptPreviewByItemID.removeValue(forKey: previousItemID)
        cancelTranscriptFinalFallback(
            itemID: previousItemID,
            reason: "input_item_reassociated"
        )
        state.wireItemID = itemID
        state.latestTranscriptPartial = candidate.preview
        state.unboundTranscript = nil
        state.didReassociateItem = true
        turnsByWireItemID[itemID] = state.turn
        latestTurnBinding = state.turn
        lastUserTranscriptPreviewByItemID[itemID] = candidate.preview
        activeUserInputTurn = state
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: "qwen_input_item_reassociated",
            routeKind: .realtimeBrain,
            turnGeneration: identity?.generation,
            disposition: "single_candidate_valid_audio_interval",
            itemCorrelationHash: Self.correlationHash(itemID)
        ))
    }

    private func recordActiveUserTranscriptPartial(
        _ preview: String,
        itemID: String
    ) -> Bool {
        guard var state = activeUserInputTurn,
              state.wireItemID == itemID,
              state.transcriptFinal == nil,
              state.latestTranscriptPartial != preview else { return false }
        state.latestTranscriptPartial = preview
        activeUserInputTurn = state
        return true
    }

    private func recordActiveUserSpeechStopped(itemID: String) -> Bool {
        guard var state = activeUserInputTurn,
              state.wireItemID == itemID,
              !state.speechStopped else { return false }
        state.speechStopped = true
        activeUserInputTurn = state
        return true
    }

    private func recordActiveUserTranscriptFinal(
        _ transcript: String,
        itemID: String
    ) -> Bool {
        guard var state = activeUserInputTurn,
              state.wireItemID == itemID,
              state.transcriptFinal == nil else { return false }
        state.transcriptFinal = transcript
        activeUserInputTurn = state
        return true
    }

    private func scheduleTranscriptFinalFallback(itemID: String) {
        cancelTranscriptFinalFallback(
            itemID: itemID,
            reason: "rescheduled"
        )
        let token = UUID()
        let task = Task { [weak self] in
            try? await Task.sleep(
                for: Self.transcriptFinalFallbackDelay
            )
            guard !Task.isCancelled else { return }
            await self?.recoverTranscriptFinalFromPartial(
                itemID: itemID,
                token: token
            )
        }
        transcriptFinalFallbackTasks[itemID] = TranscriptFinalFallback(
            token: token,
            task: task
        )
        recordTranscriptFinalFallbackDiagnostic(
            category: "qwen_transcript_final_fallback_scheduled",
            itemID: itemID,
            disposition: "delay_ms=500"
        )
    }

    private func cancelTranscriptFinalFallback(
        itemID: String,
        reason: String
    ) {
        guard let fallback = transcriptFinalFallbackTasks.removeValue(
            forKey: itemID
        ) else { return }
        fallback.task.cancel()
        recordTranscriptFinalFallbackDiagnostic(
            category: "qwen_transcript_final_fallback_cancelled",
            itemID: itemID,
            disposition: reason
        )
    }

    private func cancelTranscriptFinalFallbacks(reason: String) {
        let itemIDs = Array(transcriptFinalFallbackTasks.keys)
        for itemID in itemIDs {
            cancelTranscriptFinalFallback(
                itemID: itemID,
                reason: reason
            )
        }
    }

    private func recoverTranscriptFinalFromPartial(
        itemID: String,
        token: UUID
    ) {
        guard transcriptFinalFallbackTasks[itemID]?.token == token else {
            recordTranscriptFinalFallbackDiagnostic(
                category: "qwen_transcript_final_fallback_suppressed",
                itemID: itemID,
                disposition: "token_replaced"
            )
            return
        }
        if lifecycle == .transitioning {
            transcriptFinalFallbackTasks.removeValue(forKey: itemID)
            recordTranscriptFinalFallbackDiagnostic(
                category: "qwen_transcript_final_fallback_suppressed",
                itemID: itemID,
                disposition: "transition_deferred_to_rebound"
            )
            return
        }
        transcriptFinalFallbackTasks.removeValue(forKey: itemID)
        guard lifecycle == .active else {
            recordTranscriptFinalFallbackDiagnostic(
                category: "qwen_transcript_final_fallback_suppressed",
                itemID: itemID,
                disposition: "route_not_active"
            )
            return
        }
        guard !completedUserInputItemIDs.contains(itemID) else {
            recordTranscriptFinalFallbackDiagnostic(
                category: "qwen_transcript_final_fallback_suppressed",
                itemID: itemID,
                disposition: "already_completed"
            )
            return
        }
        guard stoppedUserInputItemIDs.contains(itemID) else {
            recordTranscriptFinalFallbackDiagnostic(
                category: "qwen_transcript_final_fallback_suppressed",
                itemID: itemID,
                disposition: "speech_not_stopped"
            )
            return
        }
        guard let turn = turnBinding(
            for: itemID,
            createsIfNeeded: false
        ) else {
            recordTranscriptFinalFallbackDiagnostic(
                category: "qwen_transcript_final_fallback_suppressed",
                itemID: itemID,
                disposition: "turn_binding_missing"
            )
            return
        }
        guard turn.sessionIdentity == identity,
              turn.contextRevision == contextRevision else {
            recordTranscriptFinalFallbackDiagnostic(
                category: "qwen_transcript_final_fallback_suppressed",
                itemID: itemID,
                disposition: "turn_binding_stale"
            )
            return
        }
        let preview = lastUserTranscriptPreviewByItemID[itemID]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preview, !preview.isEmpty else {
            recordTranscriptFinalFallbackDiagnostic(
                category: "qwen_transcript_final_fallback_suppressed",
                itemID: itemID,
                disposition: "partial_missing"
            )
            return
        }
        if activeUserInputTurn?.wireItemID == itemID {
            _ = recordActiveUserTranscriptFinal(preview, itemID: itemID)
        }
        markUserInputCompleted(itemID)
        recordTranscriptFinalFallbackDiagnostic(
            category: "qwen_transcript_final_fallback_fired",
            itemID: itemID,
            disposition: "latest_partial_promoted"
        )
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: "qwen_transcript_final_recovered_from_partial",
            routeKind: .realtimeBrain,
            turnGeneration: turn.sessionIdentity.generation,
            disposition: "speech_stopped_partial_fallback",
            itemCorrelationHash: Self.correlationHash(itemID)
        ))
        enqueue(
            kind: .userTranscriptFinal(preview),
            identity: makeEventIdentity(for: turn)
        )
    }

    private func recordTranscriptFinalFallbackDiagnostic(
        category: String,
        itemID: String,
        disposition: String
    ) {
        let turn = turnsByWireItemID[itemID]
            ?? activeUserInputTurn.flatMap {
                $0.wireItemID == itemID ? $0.turn : nil
            }
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: category,
            routeKind: .realtimeBrain,
            turnGeneration: turn?.sessionIdentity.generation
                ?? identity?.generation,
            disposition: disposition,
            itemCorrelationHash: Self.correlationHash(itemID)
        ))
    }

    private func recordUserInputWireDiagnostic(
        category: String,
        itemID: String
    ) {
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: category,
            routeKind: .realtimeBrain,
            turnGeneration: identity?.generation,
            disposition: String(describing: lifecycle),
            itemCorrelationHash: Self.correlationHash(itemID)
        ))
    }

    private func markUserInputCompleted(_ itemID: String) {
        guard completedUserInputItemIDs.insert(itemID).inserted else {
            return
        }
        completedUserInputItemOrder.append(itemID)
        if completedUserInputItemOrder.count > 256 {
            completedUserInputItemIDs.remove(
                completedUserInputItemOrder.removeFirst()
            )
        }
    }

    private func markUserInputStopped(_ itemID: String) {
        guard stoppedUserInputItemIDs.insert(itemID).inserted else {
            return
        }
        stoppedUserInputItemOrder.append(itemID)
        if stoppedUserInputItemOrder.count > 256 {
            let evictedItemID = stoppedUserInputItemOrder.removeFirst()
            stoppedUserInputItemIDs.remove(evictedItemID)
            cancelTranscriptFinalFallback(
                itemID: evictedItemID,
                reason: "stopped_tombstone_evicted"
            )
        }
    }

    private func resumeStaleEventWaiter(
        expected session: RealtimeBrainSessionIdentity,
        reason: RealtimeBrainCancellationReason
    ) {
        guard let waiter = eventWaiter,
              waiter.session == session else { return }
        eventWaiter = nil
        waiter.continuation.resume(returning: RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: nil,
                responseID: nil,
                contextRevision: contextRevision
            ),
            sequence: nextEventSequence &+ 1,
            kind: .cancelled(reason)
        ))
    }

    private func beginMutationOperation() -> UUID {
        let operationID = UUID()
        activeMutationOperations.insert(operationID)
        return operationID
    }

    private func finishMutationOperation(_ operationID: UUID) {
        activeMutationOperations.remove(operationID)
    }

    private func requireIdentity(
        _ expected: RealtimeBrainSessionIdentity
    ) throws {
        guard identity == expected,
              lifecycle != .closed,
              lifecycle != .closing else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        if let terminalError { throw terminalError }
        guard lifecycle != .failed else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
    }

    private func requireActive(
        _ expected: RealtimeBrainSessionIdentity
    ) throws {
        try requireIdentity(expected)
        guard lifecycle == .active else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
    }

    private func readCredential() throws -> QwenRealtimeCredential {
        do {
            guard let stored = try credentialReader.readCredential(
                for: configuration.keyRef
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty else {
                throw RealtimeResidentBrainError.unavailable
            }
            return try QwenRealtimeCredential(storedValue: stored)
        } catch let error as RealtimeResidentBrainError {
            throw error
        } catch {
            throw RealtimeResidentBrainError.unavailable
        }
    }

    private func failOpen(
        _ commandIdentity: RealtimeBrainSessionIdentity
    ) async {
        connectionToken = nil
        receiverTask?.cancel()
        receiverTask = nil
        await transport.close(reason: .cancelled)
        failWaiters(with: .cancelled)
        closedSessionIdentity = commandIdentity
        identity = nil
        lifecycle = .closed
        resetSessionState()
    }

    private func failWaiters(with error: RealtimeResidentBrainError) {
        failAcknowledgementWaiters(with: error)
        if let waiter = eventWaiter {
            eventWaiter = nil
            waiter.continuation.resume(throwing: error)
        }
    }

    private func failAcknowledgementWaiters(
        with error: RealtimeResidentBrainError
    ) {
        let continuations = acknowledgementWaiters.values.flatMap { $0 }
        acknowledgementWaiters.removeAll(keepingCapacity: true)
        deliveredAcknowledgements.removeAll(keepingCapacity: true)
        continuations.forEach { $0.continuation.resume(throwing: error) }
    }

    private func resetGenerationStatePreservingTombstones() {
        cancelTranscriptFinalFallbacks(
            reason: "generation_or_session_reset"
        )
        pendingEvents.removeAll(keepingCapacity: true)
        nextEventSequence = 0
        outputAudioSequence = 0
        outputAudioSampleFrames = 0
        inputAudioBatcher.reset()
        turnsByWireItemID.removeAll(keepingCapacity: true)
        latestTurnBinding = nil
        lastUserTranscriptPreviewByItemID.removeAll(keepingCapacity: true)
        activeUserInputTurn = nil
        activeResponse = nil
        pendingToolCalls.removeAll(keepingCapacity: true)
        locallyCancellingResponseID = nil
        expectedSessionUpdate = nil
        expectedInputClear = nil
        pendingResponseAuthorization = nil
        deliveredAcknowledgements.removeAll(keepingCapacity: true)
    }

    private func resetSessionState() {
        resetGenerationStatePreservingTombstones()
        resetWireTombstones()
        contextSectionsByScope.removeAll(keepingCapacity: true)
        runtimeTools.removeAll(keepingCapacity: true)
        runtimeVoiceBinding = nil
        resolvedVoice = nil
    }

    private func resetWireTombstones() {
        retiringWireResponseID = nil
        retiringResponseAttempt?.invalidate()
        retiringResponseAttempt = nil
        completedUserInputItemIDs.removeAll(keepingCapacity: true)
        completedUserInputItemOrder.removeAll(keepingCapacity: true)
        stoppedUserInputItemIDs.removeAll(keepingCapacity: true)
        stoppedUserInputItemOrder.removeAll(keepingCapacity: true)
        retiredItemIDs.removeAll(keepingCapacity: true)
        retiredItemOrder.removeAll(keepingCapacity: true)
        retiredResponseIDs.removeAll(keepingCapacity: true)
        retiredResponseOrder.removeAll(keepingCapacity: true)
    }

    private func recordTurnDetectionAcknowledgement(
        _ value: QwenRealtimeTurnDetectionEcho?
    ) {
        diagnosticBuffer?.append(
            NativeSpeechInternalDiagnosticEvent(
                source: .adapter,
                category: "qwen_turn_detection_acknowledged",
                routeKind: .realtimeBrain,
                turnGeneration: identity?.generation,
                disposition: value?.diagnosticDisposition ?? "not_echoed"
            )
        )
    }

    private func validateTurnDetectionAcknowledgement(
        _ value: QwenRealtimeTurnDetectionEcho?,
        requiresCompletePolicy: Bool = false
    ) throws {
        guard let value else {
            if requiresCompletePolicy {
                throw invalidQwenReceiveEvent("turn_detection_missing")
            }
            return
        }
        if requiresCompletePolicy {
            guard value.type != nil,
                  value.threshold != nil,
                  value.silenceDurationMilliseconds != nil,
                  value.createResponse != nil,
                  value.interruptResponse != nil else {
                throw invalidQwenReceiveEvent("turn_detection_incomplete")
            }
        }
        if let type = value.type,
           type != QwenRealtimeTurnDetectionPolicy.type {
            throw invalidQwenReceiveEvent("turn_detection_type")
        }
        if let threshold = value.threshold,
           threshold != QwenRealtimeTurnDetectionPolicy.threshold {
            throw invalidQwenReceiveEvent("turn_detection_threshold")
        }
        if let silenceDurationMilliseconds =
            value.silenceDurationMilliseconds,
           silenceDurationMilliseconds
            != QwenRealtimeTurnDetectionPolicy
                .silenceDurationMilliseconds {
            throw invalidQwenReceiveEvent("turn_detection_silence")
        }
        guard value.createResponse != true,
              value.interruptResponse != true else {
            throw invalidQwenReceiveEvent("turn_detection_authority")
        }
    }

    private func recordTurnDetectionRequest() {
        diagnosticBuffer?.append(
            NativeSpeechInternalDiagnosticEvent(
                source: .adapter,
                category: "qwen_turn_detection_requested",
                routeKind: .realtimeBrain,
                turnGeneration: identity?.generation,
                disposition: "type=\(QwenRealtimeTurnDetectionPolicy.type)"
                    + ";threshold=\(QwenRealtimeTurnDetectionPolicy.threshold)"
                    + ";silence_ms=\(QwenRealtimeTurnDetectionPolicy.silenceDurationMilliseconds)"
                    + ";create_response=false"
                    + ";interrupt_response=false"
            )
        )
    }

    private static func pcmMetrics(_ data: Data) -> (
        peak: Double,
        rms: Double
    ) {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else {
            return (0, 0)
        }
        var peak = 0.0
        var squaredSum = 0.0
        var sampleCount = 0
        for offset in stride(from: 0, to: bytes.count, by: 2) {
            let sample = Int16(bitPattern: UInt16(bytes[offset])
                | UInt16(bytes[offset + 1]) << 8)
            let normalized = Double(sample) / 32_768
            peak = max(peak, abs(normalized))
            squaredSum += normalized * normalized
            sampleCount += 1
        }
        return (peak, sqrt(squaredSum / Double(sampleCount)))
    }

    private static func correlationHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static let contextScopeOrder: [RealtimeBrainContextScope] = [
        .stableResident,
        .dynamicSession,
        .memoryDelta,
        .relationshipDelta,
        .toolResultContext
    ]

    private static func applying(
        _ update: RealtimeBrainRuntimeContextUpdate,
        to current: [String: String]
    ) -> [String: String] {
        var result = update.kind == .bootstrap ? [:] : current
        for section in update.sections {
            if section.content.isEmpty {
                result.removeValue(forKey: section.scope.rawValue)
            } else {
                result[section.scope.rawValue] = section.content
            }
        }
        return result
    }

    private static func instructions(
        from sectionsByScope: [String: String]
    ) -> String {
        contextScopeOrder.compactMap { scope in
            guard let content = sectionsByScope[scope.rawValue] else {
                return nil
            }
            return "[\(scope.rawValue)]\n\(content)"
        }.joined(separator: "\n\n")
    }

    private static func nextIdentity(
        from current: RealtimeBrainSessionIdentity,
        generation: UInt64
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: current.residentID,
            runtimeSessionID: current.runtimeSessionID,
            brainLeaseID: current.brainLeaseID,
            routeEpoch: current.routeEpoch,
            generation: generation
        )
    }

    private static func sameSession(
        _ lhs: RealtimeBrainSessionIdentity,
        _ rhs: RealtimeBrainSessionIdentity
    ) -> Bool {
        lhs.residentID == rhs.residentID
            && lhs.runtimeSessionID == rhs.runtimeSessionID
            && lhs.brainLeaseID == rhs.brainLeaseID
            && lhs.routeEpoch == rhs.routeEpoch
    }

    private func resolveVoiceBinding(
        _ binding: RuntimeVoiceBinding,
        expectedIdentity: RealtimeBrainSessionIdentity
    ) throws -> QwenResolvedRealtimeVoice {
        guard binding.identity == expectedIdentity else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        guard binding.providerIdentity == .activeRealtimeProvider else {
            throw RealtimeResidentBrainError.voiceBindingUnavailable
        }
        let defaultVoiceID = configuration.defaultProviderVoiceID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !defaultVoiceID.isEmpty else {
            throw RealtimeResidentBrainError.voiceBindingUnavailable
        }
        switch binding.mode {
        case .providerDefault:
            guard binding.voiceProfileID == nil,
                  binding.providerPrivateVoiceReference == nil else {
                throw RealtimeResidentBrainError.voiceBindingUnavailable
            }
        case .providerBuiltIn, .providerCustom, .providerCloned:
            guard binding.fallback == .providerDefault else {
                throw RealtimeResidentBrainError.voiceBindingUnavailable
            }
        }
        return QwenResolvedRealtimeVoice(voiceID: defaultVoiceID)
    }

    private static func map(
        _ error: any Error
    ) -> RealtimeResidentBrainError {
        #if DEBUG
        if error is QwenRealtimeReceiveFailure { return .invalidEvent }
        #endif
        if let error = error as? RealtimeResidentBrainError {
            return error
        }
        if error is CancellationError { return .cancelled }
        if let error = error as? NativeSpeechError {
            return switch error {
            case .timedOut: .timedOut
            case .cancelled: .cancelled
            case .invalidEvent: .invalidEvent
            case .invalidConfiguration, .missingCredential,
                 .unauthorized, .rateLimited, .unavailable:
                .unavailable
            case .transportFailure, .interactionMismatch:
                .transportFailure
            }
        }
        return .transportFailure
    }
}
