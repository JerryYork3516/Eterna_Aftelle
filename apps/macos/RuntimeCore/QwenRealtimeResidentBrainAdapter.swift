import Foundation

nonisolated struct QwenRealtimeResidentBrainConfiguration:
    Sendable,
    Equatable {
    static let supportedModelID = "qwen3.5-omni-plus-realtime"

    let endpoint: URL
    let modelID: String
    let keyRef: String
    let temporaryProviderVoiceID: String
    let acknowledgementTimeout: Duration

    init(
        endpoint: URL,
        modelID: String = Self.supportedModelID,
        keyRef: String,
        temporaryProviderVoiceID: String = "Tina",
        acknowledgementTimeout: Duration = .seconds(5)
    ) {
        self.endpoint = endpoint
        self.modelID = modelID
        self.keyRef = keyRef
        self.temporaryProviderVoiceID = temporaryProviderVoiceID
        self.acknowledgementTimeout = acknowledgementTimeout
    }
}

nonisolated private enum QwenRealtimeBrainWireEvent: Sendable {
    case sessionCreated
    case sessionUpdated
    case inputAudioCleared
    case inputSpeechStarted(itemID: String)
    case inputSpeechStopped(itemID: String)
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

nonisolated private struct QwenRealtimeResidentBrainCodec: Sendable {
    let configuration: QwenRealtimeResidentBrainConfiguration

    func initialSessionUpdate(instructions: String) throws -> String {
        try encode([
            "event_id": eventID(),
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "voice": configuration.temporaryProviderVoiceID,
                "input_audio_format": "pcm",
                "output_audio_format": "pcm",
                "instructions": instructions,
                "input_audio_transcription": [
                    "model": "qwen3-asr-flash-realtime"
                ],
                "turn_detection": [
                    "type": "semantic_vad",
                    "threshold": 0.5,
                    "silence_duration_ms": 800,
                    "create_response": true,
                    "interrupt_response": false
                ],
                "enable_search": false
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
            throw RealtimeResidentBrainError.invalidEvent
        }
        guard let object = rawObject as? [String: Any],
              let type = object["type"] as? String else {
            throw RealtimeResidentBrainError.invalidEvent
        }

        switch type {
        case "session.created":
            return .sessionCreated
        case "session.updated":
            return .sessionUpdated
        case "input_audio_buffer.cleared":
            return .inputAudioCleared
        case "input_audio_buffer.speech_started":
            return .inputSpeechStarted(itemID: try itemID(in: object))
        case "input_audio_buffer.speech_stopped":
            return .inputSpeechStopped(itemID: try itemID(in: object))
        case "conversation.item.input_audio_transcription.delta":
            guard let text = object["text"] as? String,
                  let stash = object["stash"] as? String else {
                throw RealtimeResidentBrainError.invalidEvent
            }
            return .inputTranscriptDelta(
                itemID: try itemID(in: object),
                preview: text + stash
            )
        case "conversation.item.input_audio_transcription.completed":
            guard let transcript = object["transcript"] as? String else {
                throw RealtimeResidentBrainError.invalidEvent
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
                throw RealtimeResidentBrainError.invalidEvent
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
                throw RealtimeResidentBrainError.invalidEvent
            }
            guard JSONSerialization.isValidJSONObject(argumentsObject) else {
                throw RealtimeResidentBrainError.invalidEvent
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
                throw RealtimeResidentBrainError.invalidEvent
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

    private func itemID(in object: [String: Any]) throws -> String {
        guard let value = object["item_id"] as? String,
              !value.isEmpty else {
            throw RealtimeResidentBrainError.invalidEvent
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
        throw RealtimeResidentBrainError.invalidEvent
    }

    private func string(
        _ key: String,
        in object: [String: Any]
    ) throws -> String {
        guard let value = object[key] as? String else {
            throw RealtimeResidentBrainError.invalidEvent
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

actor QwenRealtimeResidentBrainAdapter:
    RealtimeResidentBrainProvider {
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

    private struct ActiveResponse {
        let wireID: String
        let runtimeID: RealtimeBrainResponseID
        let turnID: RealtimeBrainTurnID
        let sessionIdentity: RealtimeBrainSessionIdentity
        let contextRevision: UInt64
        var text = ""
        var finalText: String?
        var didEmitTextFinal = false
        var isSpeaking = false
        var audioSequence: UInt64 = 0
        var audioSampleFrames: UInt64 = 0
        var hasToolCall = false
    }

    private struct TurnBinding {
        let runtimeID: RealtimeBrainTurnID
        let sessionIdentity: RealtimeBrainSessionIdentity
        let contextRevision: UInt64
    }

    private struct EventWaiter {
        let session: RealtimeBrainSessionIdentity
        let continuation:
            CheckedContinuation<RealtimeResidentBrainEvent, any Error>
    }

    private let credentialReader: ProviderCredentialReading
    private let transport: RealtimeWebSocketTransport
    private let configuration: QwenRealtimeResidentBrainConfiguration
    private let codec: QwenRealtimeResidentBrainCodec

    private var lifecycle = Lifecycle.closed
    private var identity: RealtimeBrainSessionIdentity?
    private var closedSessionIdentity: RealtimeBrainSessionIdentity?
    private var contextRevision: UInt64 = 0
    private var connectionToken: UUID?
    private var receiverTask: Task<Void, Never>?
    private var terminalError: RealtimeResidentBrainError?

    private var acknowledgementSerial: UInt64 = 0
    private var expectedSessionUpdate: Acknowledgement?
    private var expectedInputClear: Acknowledgement?
    private var expectedResponseCreation: Acknowledgement?
    private var acknowledgementWaiters:
        [Acknowledgement: CheckedContinuation<Void, any Error>] = [:]
    private var deliveredAcknowledgements: Set<Acknowledgement> = []

    private var pendingEvents: [RealtimeResidentBrainEvent] = []
    private var eventWaiter: EventWaiter?
    private var nextEventSequence: UInt64 = 0

    private var turnsByWireItemID:
        [String: TurnBinding] = [:]
    private var latestTurnBinding: TurnBinding?
    private var lastUserTranscriptPreviewByItemID: [String: String] = [:]
    private var activeResponse: ActiveResponse?
    private var retiredItemIDs: Set<String> = []
    private var retiredItemOrder: [String] = []
    private var retiredResponseIDs: Set<String> = []
    private var retiredResponseOrder: [String] = []
    private var pendingToolCalls:
        [RealtimeBrainToolCallID: RealtimeBrainEventIdentity] = [:]
    private var locallyCancellingResponseID: String?
    private var activeMutationOperations: Set<UUID> = []

    init(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        configuration: QwenRealtimeResidentBrainConfiguration
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.configuration = configuration
        codec = QwenRealtimeResidentBrainCodec(configuration: configuration)
    }

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        guard lifecycle == .closed,
              identity == nil,
              configuration.modelID
                == QwenRealtimeResidentBrainConfiguration.supportedModelID,
              !configuration.keyRef.isEmpty,
              !configuration.temporaryProviderVoiceID.isEmpty else {
            throw RealtimeResidentBrainError.unavailable
        }
        lifecycle = .opening
        identity = command.identity
        closedSessionIdentity = nil
        contextRevision = 0
        terminalError = nil
        resetSessionState()

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
                instructions: "Runtime context bootstrap pending."
            ))
            guard case .sessionUpdated = try await receiveHandshakeEvent()
            else {
                throw RealtimeResidentBrainError.invalidEvent
            }
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
        do {
            try await send(codec.contextUpdate(
                instructions: Self.instructions(from: update.sections)
            ))
            try await waitForAcknowledgement(acknowledgement)
            expectedSessionUpdate = nil
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
            try await send(codec.audioAppend(
                try QwenRealtimePCM16Converter.mono16k(frame)
            ))
        } catch {
            throw Self.map(error)
        }
    }

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {
        try requireActive(command.identity.session)
        guard command.identity.contextRevision == contextRevision,
              pendingToolCalls[command.callID] == command.identity else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        let operationID = beginMutationOperation()
        defer { finishMutationOperation(operationID) }
        do {
            try await send(codec.toolOutput(
                callID: command.callID.rawValue,
                output: command.output,
                isError: command.isError
            ))
            acknowledgementSerial &+= 1
            let responseAcknowledgement = Acknowledgement.responseCreated(
                acknowledgementSerial
            )
            expectedResponseCreation = responseAcknowledgement
            try await send(codec.responseCreate())
            try await waitForAcknowledgement(responseAcknowledgement)
            expectedResponseCreation = nil
            pendingToolCalls.removeValue(forKey: command.callID)
        } catch {
            expectedResponseCreation = nil
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
            clearInput: true
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
            clearInput: true
        )
    }

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        try requireActive(session)
        if !pendingEvents.isEmpty {
            return pendingEvents.removeFirst()
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
        receiverTask?.cancel()
        receiverTask = nil
        await transport.close(reason: .normal)
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
        clearInput: Bool
    ) async throws {
        guard let current = identity,
              next.generation > current.generation else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        guard activeMutationOperations.isEmpty else {
            throw RealtimeResidentBrainError.operationInFlight
        }
        lifecycle = .transitioning
        do {
            if let responseID = activeResponse?.wireID {
                locallyCancellingResponseID = responseID
                try await send(codec.responseCancel())
                try await waitForAcknowledgement(.responseDone(responseID))
                locallyCancellingResponseID = nil
            }
            if clearInput {
                acknowledgementSerial &+= 1
                let acknowledgement = Acknowledgement.inputAudioCleared(
                    acknowledgementSerial
                )
                expectedInputClear = acknowledgement
                try await send(codec.inputAudioClear())
                try await waitForAcknowledgement(acknowledgement)
                expectedInputClear = nil
            }
            retireCurrentGenerationWireState()
            resumeStaleEventWaiter(
                expected: current,
                reason: reason
            )
            identity = next
            lifecycle = .active
            resetGenerationStatePreservingTombstones()
            enqueue(kind: .cancelled(reason))
        } catch {
            expectedInputClear = nil
            locallyCancellingResponseID = nil
            lifecycle = .failed
            throw Self.map(error)
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
        do {
            try handle(codec.decode(frame))
        } catch {
            handleReceiverFailure(error, connectionToken: token)
        }
    }

    private func handle(_ event: QwenRealtimeBrainWireEvent) throws {
        switch event {
        case .sessionCreated:
            throw RealtimeResidentBrainError.invalidEvent
        case .sessionUpdated:
            if let acknowledgement = expectedSessionUpdate {
                deliver(acknowledgement)
            }
        case .inputAudioCleared:
            if let acknowledgement = expectedInputClear {
                deliver(acknowledgement)
            }
        case .inputSpeechStarted(let itemID):
            guard lifecycle == .active else { return }
            guard let turn = turnBinding(for: itemID, createsIfNeeded: true)
            else { return }
            if let response = activeResponse {
                let eventIdentity = makeEventIdentity(for: response)
                enqueue(kind: .interruptionProposed(
                    RealtimeBrainInterruptionProposal(
                        identity: eventIdentity,
                        reason: "qwen_input_speech_started"
                    )
                ), identity: eventIdentity)
            }
            enqueue(
                kind: .userSpeechStarted,
                identity: makeEventIdentity(for: turn)
            )
        case .inputSpeechStopped(let itemID):
            guard lifecycle == .active,
                  let turn = turnBinding(
                    for: itemID,
                    createsIfNeeded: false
                  ) else { return }
            enqueue(
                kind: .userSpeechStopped,
                identity: makeEventIdentity(for: turn)
            )
        case .inputTranscriptDelta(let itemID, let preview):
            guard lifecycle == .active,
                  let turn = turnBinding(
                    for: itemID,
                    createsIfNeeded: false
                  ),
                  !preview.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty,
                  lastUserTranscriptPreviewByItemID[itemID] != preview else {
                return
            }
            lastUserTranscriptPreviewByItemID[itemID] = preview
            enqueue(
                kind: .userTranscriptPartial(preview),
                identity: makeEventIdentity(for: turn)
            )
        case .inputTranscriptCompleted(let itemID, let transcript):
            guard lifecycle == .active,
                  let turn = turnBinding(
                    for: itemID,
                    createsIfNeeded: false
                  ),
                  !transcript.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else { return }
            lastUserTranscriptPreviewByItemID[itemID] = transcript
            enqueue(
                kind: .userTranscriptFinal(transcript),
                identity: makeEventIdentity(for: turn)
            )
        case .inputTranscriptFailed(let itemID):
            guard lifecycle == .active,
                  turnBinding(
                    for: itemID,
                    createsIfNeeded: false
                  ) != nil else { return }
            throw RealtimeResidentBrainError.providerFailure
        case .responseCreated(let responseID):
            guard lifecycle == .active,
                  !retiredResponseIDs.contains(responseID),
                  activeResponse?.wireID != responseID,
                  let turn = latestTurnBinding,
                  turn.sessionIdentity == identity,
                  turn.contextRevision == contextRevision else { return }
            if let activeResponse, activeResponse.wireID != responseID {
                retire(responseID: activeResponse.wireID)
            }
            activeResponse = ActiveResponse(
                wireID: responseID,
                runtimeID: RealtimeBrainResponseID(),
                turnID: turn.runtimeID,
                sessionIdentity: turn.sessionIdentity,
                contextRevision: turn.contextRevision
            )
            if let acknowledgement = expectedResponseCreation {
                deliver(acknowledgement)
            }
        case .responseTextDelta(let responseID, let delta),
             .responseAudioTranscriptDelta(let responseID, let delta):
            guard lifecycle == .active,
                  !delta.isEmpty,
                  updateActiveResponse(responseID, { $0.text.append(delta) })
            else { return }
            guard let response = activeResponse else { return }
            enqueue(
                kind: .residentTextDelta(delta),
                identity: makeEventIdentity(for: response)
            )
        case .responseTextDone(let responseID, let text),
             .responseAudioTranscriptDone(let responseID, let text):
            guard lifecycle == .active,
                  !text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty,
                  updateActiveResponse(responseID, {
                    $0.text = text
                    $0.finalText = text
                  }),
                  var response = activeResponse else { return }
            if !response.didEmitTextFinal {
                response.didEmitTextFinal = true
                activeResponse = response
                enqueue(
                    kind: .residentTextFinal(text),
                    identity: makeEventIdentity(for: response)
                )
            }
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
            response.audioSequence &+= 1
            let timestamp = response.audioSampleFrames
                * 1_000_000_000 / 24_000
            response.audioSampleFrames &+= UInt64(bytes.count / 2)
            activeResponse = response
            enqueue(
                kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                    sequence: response.audioSequence,
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
            pendingToolCalls[runtimeCallID] = eventIdentity
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
                }
            } else if status == "incomplete" {
                enqueue(
                    kind: .cancelled(.interrupted),
                    identity: makeEventIdentity(for: response)
                )
            } else {
                enqueue(
                    kind: .error(.providerFailure),
                    identity: makeEventIdentity(for: response)
                )
            }
            activeResponse = response
            finishActiveResponse(responseID)
        case .providerError:
            throw RealtimeResidentBrainError.providerFailure
        case .other:
            break
        }
    }

    private func handleReceiverFailure(
        _ error: any Error,
        connectionToken token: UUID
    ) {
        guard connectionToken == token else { return }
        if lifecycle == .closing || lifecycle == .closed {
            failWaiters(with: .cancelled)
            return
        }
        let mapped = Self.map(error)
        lifecycle = .failed
        terminalError = mapped
        failWaiters(with: mapped)
    }

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
        try await withCheckedThrowingContinuation { continuation in
            acknowledgementWaiters[acknowledgement] = continuation
            Task { [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                guard let self else { return }
                await self.timeout(
                    acknowledgement,
                    connectionToken: token
                )
            }
        }
    }

    private func timeout(
        _ acknowledgement: Acknowledgement,
        connectionToken token: UUID?
    ) {
        guard connectionToken == token,
              let waiter = acknowledgementWaiters.removeValue(
                forKey: acknowledgement
              ) else { return }
        waiter.resume(throwing: RealtimeResidentBrainError.timedOut)
    }

    private func deliver(_ acknowledgement: Acknowledgement) {
        if let waiter = acknowledgementWaiters.removeValue(
            forKey: acknowledgement
        ) {
            waiter.resume()
        } else {
            deliveredAcknowledgements.insert(acknowledgement)
        }
    }

    private func nextSessionUpdateAcknowledgement() -> Acknowledgement {
        acknowledgementSerial &+= 1
        return .sessionUpdated(acknowledgementSerial)
    }

    private func enqueue(
        kind: RealtimeResidentBrainEventKind,
        turnID: RealtimeBrainTurnID? = nil,
        responseID: RealtimeBrainResponseID? = nil
    ) {
        enqueue(
            kind: kind,
            identity: makeEventIdentity(
                turnID: turnID,
                responseID: responseID
            )
        )
    }

    private func enqueue(
        kind: RealtimeResidentBrainEventKind,
        identity eventIdentity: RealtimeBrainEventIdentity
    ) {
        let matchingWaiter = eventWaiter?.session == eventIdentity.session
        guard eventIdentity.session == identity || matchingWaiter else { return }
        nextEventSequence &+= 1
        let event = RealtimeResidentBrainEvent(
            identity: eventIdentity,
            sequence: nextEventSequence,
            kind: kind
        )
        if let waiter = eventWaiter, matchingWaiter {
            eventWaiter = nil
            waiter.continuation.resume(returning: event)
        } else if eventIdentity.session == identity {
            pendingEvents.append(event)
        }
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

    private func retireCurrentGenerationWireState() {
        turnsByWireItemID.keys.forEach { retire(itemID: $0) }
        if let responseID = activeResponse?.wireID {
            retire(responseID: responseID)
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
              lifecycle != .closing,
              lifecycle != .failed else {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        if let terminalError { throw terminalError }
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
        let continuations = acknowledgementWaiters.values
        acknowledgementWaiters.removeAll(keepingCapacity: true)
        deliveredAcknowledgements.removeAll(keepingCapacity: true)
        continuations.forEach { $0.resume(throwing: error) }
    }

    private func resetGenerationStatePreservingTombstones() {
        pendingEvents.removeAll(keepingCapacity: true)
        nextEventSequence = 0
        turnsByWireItemID.removeAll(keepingCapacity: true)
        latestTurnBinding = nil
        lastUserTranscriptPreviewByItemID.removeAll(keepingCapacity: true)
        activeResponse = nil
        pendingToolCalls.removeAll(keepingCapacity: true)
        locallyCancellingResponseID = nil
        expectedSessionUpdate = nil
        expectedInputClear = nil
        expectedResponseCreation = nil
        deliveredAcknowledgements.removeAll(keepingCapacity: true)
    }

    private func resetSessionState() {
        resetGenerationStatePreservingTombstones()
        retiredItemIDs.removeAll(keepingCapacity: true)
        retiredItemOrder.removeAll(keepingCapacity: true)
        retiredResponseIDs.removeAll(keepingCapacity: true)
        retiredResponseOrder.removeAll(keepingCapacity: true)
    }

    private static func instructions(
        from sections: [RealtimeBrainContextSection]
    ) -> String {
        sections.map { section in
            "[\(section.scope.rawValue)]\n\(section.content)"
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

    private static func map(
        _ error: any Error
    ) -> RealtimeResidentBrainError {
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
