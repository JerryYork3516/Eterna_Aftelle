import Foundation

nonisolated private struct QwenPendingToolCall: Sendable, Equatable {
    let name: String
    var arguments: String
}

nonisolated enum QwenRealtimeConnectionState: Sendable, Equatable {
    case connecting
    case connected
    case configured
    case streaming
    case cancelling
    case closing
    case closed
    case failed
}

actor QwenRealtimeAdapter:
    NativeSpeechProvider,
    RealtimeSpeechContextProviding {
    private static let suppressedResponseCapacity = 256
    private static let completedToolCallCapacity = 256

    private let credentialReader: ProviderCredentialReading
    private let transport: RealtimeWebSocketTransport
    private let configuration: QwenRealtimeConfiguration
    private let codec: QwenRealtimeCodec
    private let reconnectDelay: Duration
    private let diagnosticBuffer: NativeSpeechDiagnosticBuffer?

    private var activeInteraction: NativeSpeechInteraction?
    private var preparedContextProjection: RealtimeSpeechContextProjection?
    private var activeContextVersion: String?
    private var pendingEvents: [NativeSpeechEvent] = []
    private var inputAudioBuffer = Data()
    private var nextOutputAudioSequenceNumber: UInt64 = 0

    private var userSpeechIsActive = false
    private var activeUserItemCorrelationHash: String?
    private var lastUserTranscriptPreview = ""
    private var userTranscriptFinalized = false

    private var isProviderResponseActive = false
    private var activeResponseCorrelationHash: String?
    private var suppressedResponseCorrelationHashes: Set<String> = []
    private var suppressedResponseCorrelationOrder: [String] = []
    private var residentTranscriptAccumulator = ""
    private var activeResidentItemCorrelationHash: String?
    private var pendingResidentPartial: String?
    private var deferredResidentFinal: String?

    private var isCancelling = false
    private var didEmitCancellationAcknowledgement = false
    private var pendingCancellationReason: NativeSpeechCancellationReason?
    private var pendingCancellationResponseCorrelationHash: String?

    private var pendingToolCalls: [String: QwenPendingToolCall] = [:]
    private var completedToolCallIDs: Set<String> = []
    private var completedToolCallOrder: [String] = []
    private var didRequestToolContinuation = false

    private(set) var connectionState = QwenRealtimeConnectionState.closed
    private(set) var ignoredEventCount: UInt64 = 0

    init(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        configuration: QwenRealtimeConfiguration = .init(),
        reconnectDelay: Duration = .milliseconds(100),
        diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.configuration = configuration
        codec = QwenRealtimeCodec(configuration: configuration)
        self.reconnectDelay = reconnectDelay
        self.diagnosticBuffer = diagnosticBuffer
    }

    func prepareContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws {
        guard activeInteraction == nil else {
            throw NativeSpeechError.invalidConfiguration
        }
        preparedContextProjection = projection
    }

    func updateContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws {
        guard let interaction = activeInteraction,
              projection.isBound(to: interaction) else {
            throw NativeSpeechError.interactionMismatch
        }
        guard activeContextVersion != projection.compilationVersion else {
            return
        }
        try await transport.send(.text(try codec.contextUpdate(
            instructions: projection.instructions
        )))
        activeContextVersion = projection.compilationVersion
    }

    func start(request: NativeSpeechStartRequest) async throws {
        guard activeInteraction == nil,
              let projection = preparedContextProjection else {
            throw NativeSpeechError.invalidConfiguration
        }
        preparedContextProjection = nil
        try request.profile.validate()
        try configuration.validate(profile: request.profile)
        guard request.interaction.providerProfileID
                == request.profile.profileID,
              projection.isBound(to: request.interaction) else {
            throw NativeSpeechError.interactionMismatch
        }

        let credential: QwenRealtimeCredential
        do {
            guard let stored = try credentialReader.readCredential(
                for: request.profile.keyRef
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty else {
                throw NativeSpeechError.missingCredential
            }
            credential = try QwenRealtimeCredential(storedValue: stored)
        } catch let error as NativeSpeechError {
            throw error
        } catch {
            throw NativeSpeechError.missingCredential
        }

        for attempt in 0 ... 1 {
            do {
                try await connectAndConfigure(
                    request: request,
                    projection: projection,
                    endpoint: try credential.endpoint(for: request.profile),
                    bearerToken: credential.apiKey
                )
                return
            } catch let error as NativeSpeechError {
                resetConnection()
                await transport.close(reason: .cancelled)
                guard attempt == 0,
                      Self.isRetryableBeforeStreaming(error) else {
                    connectionState = .failed
                    throw error
                }
                do {
                    try await Task.sleep(for: reconnectDelay)
                } catch {
                    connectionState = .failed
                    throw NativeSpeechError.cancelled
                }
            } catch {
                resetConnection()
                await transport.close(reason: .cancelled)
                connectionState = .failed
                throw NativeSpeechError.transportFailure
            }
        }
    }

    func send(audio: NativeSpeechAudioPayload) async throws {
        try requireActive(audio.interactionID)
        guard audio.format == .pcm16 else {
            throw NativeSpeechError.invalidConfiguration
        }
        inputAudioBuffer.append(audio.bytes)
        while inputAudioBuffer.count >= configuration.inputPacketByteCount {
            let packet = Data(
                inputAudioBuffer.prefix(configuration.inputPacketByteCount)
            )
            inputAudioBuffer.removeFirst(configuration.inputPacketByteCount)
            try await transport.send(.text(try codec.audioAppend(packet)))
        }
        connectionState = .streaming
    }

    func receive(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEvent {
        try requireActive(interactionID)
        if !pendingEvents.isEmpty {
            return pendingEvents.removeFirst()
        }
        while true {
            let envelope = try await receiveEnvelope(
                interactionID: interactionID
            )
            if isSuppressedResponseEvent(envelope) {
                ignore(envelope, disposition: "suppressed_response")
                continue
            }
            if Self.requiresActiveResponse(envelope.wireKind),
               !responseEventMatchesActive(envelope) {
                ignore(envelope, disposition: "response_mismatch")
                continue
            }
            if isCancelling,
               Self.requiresActiveResponse(envelope.wireKind),
               envelope.wireKind != .responseDone {
                ignore(envelope, disposition: "cancelling_response")
                continue
            }

            switch envelope.wireKind {
            case .sessionCreated, .sessionUpdated:
                if let event = envelope.event { return event }
            case .inputSpeechStarted:
                userSpeechIsActive = true
                activeUserItemCorrelationHash =
                    envelope.itemCorrelationHash
                lastUserTranscriptPreview = ""
                userTranscriptFinalized = false
                resetResidentProjection()
                if let event = envelope.event { return event }
            case .inputSpeechEnded:
                userSpeechIsActive = false
                if let event = envelope.event { return event }
            case .userTranscriptPreview:
                guard userTranscriptMatchesActiveItem(envelope),
                      !userTranscriptFinalized,
                      case .partialTranscript(let preview) =
                        envelope.event?.kind,
                      preview != lastUserTranscriptPreview else {
                    ignore(envelope, disposition: "duplicate_or_stale_user_preview")
                    continue
                }
                lastUserTranscriptPreview = preview
                return NativeSpeechEvent(
                    interactionID: interactionID,
                    kind: .partialTranscript(preview)
                )
            case .userTranscriptDone:
                guard userTranscriptMatchesActiveItem(envelope),
                      !userTranscriptFinalized,
                      case .finalTranscript(let transcript) =
                        envelope.event?.kind else {
                    ignore(envelope, disposition: "duplicate_or_stale_user_final")
                    continue
                }
                userTranscriptFinalized = true
                lastUserTranscriptPreview = transcript
                return NativeSpeechEvent(
                    interactionID: interactionID,
                    kind: .finalTranscript(transcript)
                )
            case .responseCreated:
                if userSpeechIsActive {
                    if let responseHash =
                        envelope.responseCorrelationHash {
                        suppressResponse(responseHash)
                    }
                    ignore(envelope, disposition: "user_speaking")
                    continue
                }
                if isCancelling {
                    acknowledgeCancellation(
                        interactionID: interactionID,
                        replacementEvent: envelope.event
                    )
                    isProviderResponseActive = true
                    activeResponseCorrelationHash =
                        envelope.responseCorrelationHash
                    didEmitCancellationAcknowledgement = false
                    didRequestToolContinuation = false
                    pendingToolCalls.removeAll(keepingCapacity: true)
                    return pendingEvents.removeFirst()
                }
                if let previous = activeResponseCorrelationHash,
                   previous != envelope.responseCorrelationHash {
                    suppressResponse(previous)
                }
                isProviderResponseActive = true
                activeResponseCorrelationHash =
                    envelope.responseCorrelationHash
                didEmitCancellationAcknowledgement = false
                didRequestToolContinuation = false
                pendingToolCalls.removeAll(keepingCapacity: true)
                resetResidentProjection()
                if let event = envelope.event { return event }
            case .residentTranscriptDelta:
                guard residentTranscriptMatchesActiveItem(envelope),
                      case .outputText(let delta, false) =
                        envelope.event?.kind,
                      !delta.isEmpty else {
                    ignore(envelope, disposition: "stale_resident_delta")
                    continue
                }
                residentTranscriptAccumulator.append(delta)
                pendingResidentPartial = residentTranscriptAccumulator
            case .residentTranscriptDone:
                guard residentTranscriptMatchesActiveItem(envelope),
                      case .outputText(let transcript, true) =
                        envelope.event?.kind else {
                    ignore(envelope, disposition: "stale_resident_final")
                    continue
                }
                residentTranscriptAccumulator = transcript
                deferredResidentFinal = transcript
            case .outputAudioDelta:
                guard let event = envelope.event else {
                    throw NativeSpeechError.invalidEvent
                }
                nextOutputAudioSequenceNumber &+= 1
                isProviderResponseActive = true
                connectionState = .streaming
                if let partial = pendingResidentPartial {
                    pendingResidentPartial = nil
                    pendingEvents.append(NativeSpeechEvent(
                        interactionID: interactionID,
                        kind: .outputText(text: partial, isFinal: false)
                    ))
                }
                return event
            case .outputAudioDone:
                pendingResidentPartial = nil
                if let final = takeDeferredResidentFinal(
                    interactionID: interactionID
                ) {
                    return final
                }
            case .toolCallCreated, .toolArgumentsDelta,
                 .toolArgumentsDone:
                if let toolEvent = try standardizedToolEvent(
                    envelope,
                    interactionID: interactionID
                ) {
                    return toolEvent
                }
            case .responseDone:
                if isCancelling,
                   cancellationMatches(envelope) {
                    acknowledgeCancellation(interactionID: interactionID)
                    return pendingEvents.removeFirst()
                }
                let terminal = envelope.event ?? NativeSpeechEvent(
                    interactionID: interactionID,
                    kind: .turnFailed(.invalidEvent)
                )
                finishResponse(envelope)
                if case .responseCompleted = terminal.kind,
                   let final = takeDeferredResidentFinal(
                       interactionID: interactionID
                   ) {
                    pendingEvents.append(terminal)
                    return final
                }
                resetResidentProjection()
                return terminal
            case .providerError:
                guard case .failed(let error) = envelope.event?.kind else {
                    throw NativeSpeechError.invalidEvent
                }
                if error == .unauthorized || !isProviderResponseActive {
                    return NativeSpeechEvent(
                        interactionID: interactionID,
                        kind: .failed(error)
                    )
                }
                if let active = activeResponseCorrelationHash {
                    suppressResponse(active)
                }
                isProviderResponseActive = false
                activeResponseCorrelationHash = nil
                resetResidentProjection()
                connectionState = .configured
                return NativeSpeechEvent(
                    interactionID: interactionID,
                    kind: .turnFailed(error)
                )
            case .other:
                ignore(envelope, disposition: "unknown")
            }
        }
    }

    func cancel(
        interactionID: NativeSpeechInteractionID,
        reason: NativeSpeechCancellationReason
    ) async throws {
        try requireActive(interactionID)
        guard isProviderResponseActive else {
            resetResidentProjection()
            if !isCancelling, !didEmitCancellationAcknowledgement {
                didEmitCancellationAcknowledgement = true
                pendingEvents.append(NativeSpeechEvent(
                    interactionID: interactionID,
                    kind: .cancelled(reason: reason.rawValue)
                ))
            }
            return
        }
        guard !isCancelling else { return }
        isCancelling = true
        pendingCancellationReason = reason
        pendingCancellationResponseCorrelationHash =
            activeResponseCorrelationHash
        pendingEvents.removeAll {
            if case .outputText = $0.kind { return true }
            return false
        }
        resetResidentProjection()
        connectionState = .cancelling
        do {
            try await transport.send(.text(try codec.responseCancel(
                eventID: "cancel-\(UUID().uuidString)"
            )))
        } catch {
            isCancelling = false
            pendingCancellationReason = nil
            pendingCancellationResponseCorrelationHash = nil
            connectionState = .configured
            throw error
        }
    }

    func submitToolOutput(
        _ output: NativeSpeechToolOutput,
        interactionID: NativeSpeechInteractionID
    ) async throws {
        try requireActive(interactionID)
        try await transport.send(.text(try codec.toolOutput(output)))
    }

    func requestToolContinuation(
        interactionID: NativeSpeechInteractionID
    ) async throws {
        try requireActive(interactionID)
        guard !didRequestToolContinuation else { return }
        guard !isProviderResponseActive, !isCancelling else {
            throw NativeSpeechError.invalidEvent
        }
        try await transport.send(.text(try codec.responseCreate()))
        didRequestToolContinuation = true
    }

    func close(interactionID: NativeSpeechInteractionID) async throws {
        guard activeInteraction?.id == interactionID else {
            if activeInteraction == nil { return }
            throw NativeSpeechError.interactionMismatch
        }
        connectionState = .closing
        let finishError: (any Error)?
        do {
            try await transport.send(.text(try codec.sessionFinish()))
            finishError = nil
        } catch {
            finishError = error
        }
        resetConnection()
        await transport.close(reason: .normal)
        connectionState = .closed
        if let finishError { throw finishError }
    }

    private func connectAndConfigure(
        request: NativeSpeechStartRequest,
        projection: RealtimeSpeechContextProjection,
        endpoint: URL,
        bearerToken: String
    ) async throws {
        connectionState = .connecting
        try await transport.connect(
            endpoint: endpoint,
            bearerToken: bearerToken
        )
        activeInteraction = request.interaction
        activeContextVersion = projection.compilationVersion
        resetInteractionState()

        let created = try await receiveEnvelope(
            interactionID: request.interaction.id
        )
        guard created.wireKind == .sessionCreated,
              let createdEvent = created.event else {
            throw NativeSpeechError.invalidEvent
        }
        connectionState = .connected
        try await transport.send(.text(try codec.sessionUpdate(
            profile: request.profile,
            instructions: projection.instructions,
            tools: request.tools
        )))
        let updated = try await receiveEnvelope(
            interactionID: request.interaction.id
        )
        guard updated.wireKind == .sessionUpdated,
              let updatedEvent = updated.event else {
            throw NativeSpeechError.invalidEvent
        }
        connectionState = .configured
        pendingEvents = [createdEvent, updatedEvent]
    }

    private func receiveEnvelope(
        interactionID: NativeSpeechInteractionID
    ) async throws -> QwenRealtimeDecodedEnvelope {
        let frame: RealtimeWebSocketFrame
        do {
            frame = try await transport.receive()
        } catch is CancellationError {
            throw NativeSpeechError.cancelled
        } catch let error as NativeSpeechError {
            throw error
        } catch {
            throw NativeSpeechError.transportFailure
        }
        return try codec.decodeEnvelope(
            frame,
            interactionID: interactionID,
            outputAudioSequenceNumber: nextOutputAudioSequenceNumber
        )
    }

    private func requireActive(
        _ interactionID: NativeSpeechInteractionID
    ) throws {
        guard activeInteraction?.id == interactionID else {
            throw NativeSpeechError.interactionMismatch
        }
    }

    private func userTranscriptMatchesActiveItem(
        _ envelope: QwenRealtimeDecodedEnvelope
    ) -> Bool {
        guard let incoming = envelope.itemCorrelationHash else { return true }
        guard let active = activeUserItemCorrelationHash else {
            activeUserItemCorrelationHash = incoming
            return true
        }
        return incoming == active
    }

    private func residentTranscriptMatchesActiveItem(
        _ envelope: QwenRealtimeDecodedEnvelope
    ) -> Bool {
        guard let incoming = envelope.itemCorrelationHash else { return true }
        guard let active = activeResidentItemCorrelationHash else {
            activeResidentItemCorrelationHash = incoming
            return true
        }
        return incoming == active
    }

    private func responseEventMatchesActive(
        _ envelope: QwenRealtimeDecodedEnvelope
    ) -> Bool {
        switch (
            envelope.responseCorrelationHash,
            activeResponseCorrelationHash
        ) {
        case (let incoming?, let active?):
            return incoming == active
        case (let incoming?, nil):
            activeResponseCorrelationHash = incoming
            isProviderResponseActive = true
            return true
        case (nil, _?):
            return true
        case (nil, nil):
            return isProviderResponseActive
        }
    }

    private func isSuppressedResponseEvent(
        _ envelope: QwenRealtimeDecodedEnvelope
    ) -> Bool {
        guard let hash = envelope.responseCorrelationHash else { return false }
        return suppressedResponseCorrelationHashes.contains(hash)
    }

    private func suppressResponse(_ hash: String) {
        guard suppressedResponseCorrelationHashes.insert(hash).inserted else {
            return
        }
        suppressedResponseCorrelationOrder.append(hash)
        if suppressedResponseCorrelationOrder.count
            > Self.suppressedResponseCapacity {
            suppressedResponseCorrelationHashes.remove(
                suppressedResponseCorrelationOrder.removeFirst()
            )
        }
    }

    private func cancellationMatches(
        _ envelope: QwenRealtimeDecodedEnvelope
    ) -> Bool {
        guard let pending =
            pendingCancellationResponseCorrelationHash else {
            return true
        }
        return envelope.responseCorrelationHash == nil
            || envelope.responseCorrelationHash == pending
    }

    private func acknowledgeCancellation(
        interactionID: NativeSpeechInteractionID,
        replacementEvent: NativeSpeechEvent? = nil
    ) {
        if let pending = pendingCancellationResponseCorrelationHash {
            suppressResponse(pending)
        }
        let reason = pendingCancellationReason?.rawValue ?? "cancelled"
        isCancelling = false
        didEmitCancellationAcknowledgement = true
        pendingCancellationReason = nil
        pendingCancellationResponseCorrelationHash = nil
        isProviderResponseActive = false
        activeResponseCorrelationHash = nil
        resetResidentProjection()
        connectionState = .configured
        pendingEvents.append(NativeSpeechEvent(
            interactionID: interactionID,
            kind: .cancelled(reason: reason)
        ))
        if let replacementEvent {
            pendingEvents.append(replacementEvent)
        }
    }

    private func finishResponse(_ envelope: QwenRealtimeDecodedEnvelope) {
        if let responseHash = envelope.responseCorrelationHash
            ?? activeResponseCorrelationHash {
            suppressResponse(responseHash)
        }
        isProviderResponseActive = false
        activeResponseCorrelationHash = nil
        pendingToolCalls.removeAll(keepingCapacity: true)
        connectionState = .configured
    }

    private func takeDeferredResidentFinal(
        interactionID: NativeSpeechInteractionID
    ) -> NativeSpeechEvent? {
        guard let text = deferredResidentFinal else { return nil }
        deferredResidentFinal = nil
        pendingResidentPartial = nil
        return NativeSpeechEvent(
            interactionID: interactionID,
            kind: .outputText(text: text, isFinal: true)
        )
    }

    private func standardizedToolEvent(
        _ envelope: QwenRealtimeDecodedEnvelope,
        interactionID: NativeSpeechInteractionID
    ) throws -> NativeSpeechEvent? {
        guard let wireEvent = envelope.toolWireEvent else { return nil }
        switch wireEvent {
        case .created(let callID, let name, let arguments):
            guard !completedToolCallIDs.contains(callID) else { return nil }
            pendingToolCalls[callID] = QwenPendingToolCall(
                name: name,
                arguments: arguments ?? ""
            )
        case .argumentsDelta(let callID, let name, let delta):
            guard !completedToolCallIDs.contains(callID) else { return nil }
            if var pending = pendingToolCalls[callID] {
                guard name == nil || name == pending.name else {
                    throw NativeSpeechError.invalidEvent
                }
                pending.arguments.append(delta)
                pendingToolCalls[callID] = pending
            } else if let name {
                pendingToolCalls[callID] = QwenPendingToolCall(
                    name: name,
                    arguments: delta
                )
            } else {
                throw NativeSpeechError.invalidEvent
            }
        case .argumentsDone(let callID, let name, let arguments):
            guard !completedToolCallIDs.contains(callID) else { return nil }
            if let pending = pendingToolCalls[callID],
               pending.name != name {
                throw NativeSpeechError.invalidEvent
            }
            let completeArguments = arguments.isEmpty
                ? (pendingToolCalls[callID]?.arguments ?? "")
                : arguments
            pendingToolCalls[callID] = nil
            completedToolCallIDs.insert(callID)
            completedToolCallOrder.append(callID)
            while completedToolCallOrder.count
                    > Self.completedToolCallCapacity {
                completedToolCallIDs.remove(
                    completedToolCallOrder.removeFirst()
                )
            }
            return NativeSpeechEvent(
                interactionID: interactionID,
                kind: .toolRequestCandidate(NativeSpeechToolRequest(
                    callID: callID,
                    toolName: name,
                    arguments: Data(completeArguments.utf8),
                    correlationHash: envelope.callCorrelationHash
                ))
            )
        }
        return nil
    }

    private func ignore(
        _ envelope: QwenRealtimeDecodedEnvelope,
        disposition: String
    ) {
        ignoredEventCount &+= 1
        diagnosticBuffer?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter,
            category: "qwen_wire_event_ignored",
            interactionShortID: activeInteraction.map {
                String($0.id.rawValue.uuidString.prefix(8))
            },
            disposition: disposition,
            responseCorrelationHash: envelope.responseCorrelationHash,
            itemCorrelationHash: envelope.itemCorrelationHash
                ?? envelope.callCorrelationHash
        ))
    }

    private func resetResidentProjection() {
        residentTranscriptAccumulator = ""
        activeResidentItemCorrelationHash = nil
        pendingResidentPartial = nil
        deferredResidentFinal = nil
    }

    private func resetInteractionState() {
        pendingEvents.removeAll()
        inputAudioBuffer.removeAll(keepingCapacity: true)
        nextOutputAudioSequenceNumber = 0
        userSpeechIsActive = false
        activeUserItemCorrelationHash = nil
        lastUserTranscriptPreview = ""
        userTranscriptFinalized = false
        isProviderResponseActive = false
        activeResponseCorrelationHash = nil
        suppressedResponseCorrelationHashes.removeAll(keepingCapacity: true)
        suppressedResponseCorrelationOrder.removeAll(keepingCapacity: true)
        isCancelling = false
        didEmitCancellationAcknowledgement = false
        pendingCancellationReason = nil
        pendingCancellationResponseCorrelationHash = nil
        pendingToolCalls.removeAll(keepingCapacity: true)
        completedToolCallIDs.removeAll(keepingCapacity: true)
        completedToolCallOrder.removeAll(keepingCapacity: true)
        didRequestToolContinuation = false
        resetResidentProjection()
    }

    private func resetConnection() {
        activeInteraction = nil
        activeContextVersion = nil
        resetInteractionState()
    }

    private static func requiresActiveResponse(
        _ wireKind: QwenRealtimeWireEventKind
    ) -> Bool {
        switch wireKind {
        case .residentTranscriptDelta, .residentTranscriptDone,
             .outputAudioDelta, .outputAudioDone, .toolCallCreated,
             .toolArgumentsDelta, .toolArgumentsDone, .responseDone:
            return true
        default:
            return false
        }
    }

    private static func isRetryableBeforeStreaming(
        _ error: NativeSpeechError
    ) -> Bool {
        switch error {
        case .transportFailure, .timedOut, .unavailable:
            return true
        default:
            return false
        }
    }
}
