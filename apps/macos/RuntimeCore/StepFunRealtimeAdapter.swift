import Foundation

nonisolated private struct StepFunResidentPartialCheckpoint:
    Sendable,
    Equatable {
    let text: String
    let responseCorrelationHash: String?
    let itemCorrelationHash: String?
    let requiredCumulativeAudioByteCount: Int
}

nonisolated private struct StepFunDeferredResidentFinal:
    Sendable,
    Equatable {
    let text: String
    let responseCorrelationHash: String?
    let itemCorrelationHash: String?
}

nonisolated private struct StepFunPendingToolCall: Sendable, Equatable {
    let name: String
    var arguments: String
}

nonisolated enum StepFunRealtimeConnectionState: String, Sendable, Equatable {
    case connecting
    case connected
    case configured
    case streaming
    case cancelling
    case closing
    case closed
    case failed
}

actor StepFunRealtimeAdapter:
    NativeSpeechProvider,
    RealtimeSpeechContextProviding {
    private static let transcriptEventIdentityCapacity = 2_048
    private static let residentPartialCheckpointCapacity = 128
    private static let residentSubtitleMinimumPhraseByteCount = 48_000
    private static let residentSubtitleAudioBytesPerVisibleCharacter = 12_000
    private static let residentSubtitleMaximumPhraseCharacterCount = 12
    private static let residentSubtitleMinimumBoundaryCharacterCount = 3
    private static let residentSubtitlePhraseBoundaries = Set<Character>(
        "，。！？；：、,.!?;:\n\r…”’」』】）》）]}"
    )
    private static let suppressedResponseCapacity = 256
    private static let completedToolCallCapacity = 256
    private let credentialReader: ProviderCredentialReading
    private let transport: RealtimeWebSocketTransport
    private let codec: StepFunRealtimeCodec
    private let diagnosticBuffer: NativeSpeechDiagnosticBuffer?
    private var activeInteraction: NativeSpeechInteraction?
    private var activeContextVersion: String?
    private var preparedContextProjection:
        RealtimeSpeechContextProjection?
    private var pendingEvents: [NativeSpeechEvent] = []
    private var isCancelling = false
    private var didEmitCancellationAcknowledgement = false
    private var didEmitTurnFailureOutcome = false
    private var isProviderResponseActive = false
    private var activeResponseCorrelationHash: String?
    private var pendingCancellationResponseCorrelationHash: String?
    private var pendingCancellationEventID: String?
    private var userTranscriptAccumulator = ""
    private var activeUserItemCorrelationHash: String?
    private var residentTranscriptAccumulator = ""
    private var activeResidentItemCorrelationHash: String?
    private var suppressedResidentItemCorrelationHashes: Set<String> = []
    private var userTranscriptFinalized = false
    private var residentTranscriptFinalized = false
    private var pendingResidentPartialCheckpoints:
        [StepFunResidentPartialCheckpoint] = []
    private var residentAudioByteCount = 0
    private var residentCheckpointedVisibleCharacterCount = 0
    private var residentLastCheckpointAudioByteCount = 0
    private var deferredResidentFinal: StepFunDeferredResidentFinal?
    private var residentAudioFinished = false
    private var seenUserTranscriptEventHashes: Set<String> = []
    private var seenResidentTranscriptEventHashes: Set<String> = []
    private var userSpeechIsActive = false
    private var suppressedResponseCorrelationHashes: Set<String> = []
    private var suppressedResponseCorrelationOrder: [String] = []
    private var nextOutputAudioSequenceNumber: UInt64 = 0
    private var wireReceiveOrdinal: UInt64 = 0
    private var lastOutputAudioArrivalNanoseconds: UInt64?
    private var pendingToolCalls: [String: StepFunPendingToolCall] = [:]
    private var completedToolCallIDs: Set<String> = []
    private var completedToolCallOrder: [String] = []
    private var didRequestToolContinuation = false
    private let reconnectDelay: Duration
    private(set) var connectionState = StepFunRealtimeConnectionState.closed
    private(set) var ignoredEventCount: UInt64 = 0

    init(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        codec: StepFunRealtimeCodec = StepFunRealtimeCodec(),
        reconnectDelay: Duration = .milliseconds(100),
        diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.codec = codec
        self.reconnectDelay = reconnectDelay
        self.diagnosticBuffer = diagnosticBuffer
    }

    func start(request: NativeSpeechStartRequest) async throws {
        guard activeInteraction == nil else {
            throw NativeSpeechError.invalidConfiguration
        }
        guard let contextProjection = preparedContextProjection else {
            throw NativeSpeechError.invalidConfiguration
        }
        preparedContextProjection = nil
        try request.profile.validate()
        guard request.interaction.providerProfileID == request.profile.profileID,
              contextProjection.isBound(to: request.interaction) else {
            throw NativeSpeechError.interactionMismatch
        }
        let credential: String
        do {
            guard let stored = try credentialReader.readCredential(
                for: request.profile.keyRef
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty else {
                throw NativeSpeechError.missingCredential
            }
            credential = stored
        } catch let error as NativeSpeechError {
            throw error
        } catch {
            throw NativeSpeechError.missingCredential
        }

        for attempt in 0 ... 1 {
            do {
                try await connectAndConfigure(
                    request: request,
                    contextProjection: contextProjection,
                    credential: credential
                )
                return
            } catch let error as NativeSpeechError {
                resetConnection()
                await transport.close(reason: .cancelled)
                guard attempt == 0, Self.isRetryableBeforeStreaming(error) else {
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
        try await transport.send(
            .text(try codec.contextUpdate(
                instructions: projection.instructions
            ))
        )
        activeContextVersion = projection.compilationVersion
    }

    func send(audio: NativeSpeechAudioPayload) async throws {
        try requireActive(audio.interactionID)
        try await transport.send(.text(try codec.audioAppend(audio)))
        connectionState = .streaming
    }

    func submitToolOutput(
        _ output: NativeSpeechToolOutput,
        interactionID: NativeSpeechInteractionID
    ) async throws {
        try requireActive(interactionID)
        try await transport.send(.text(try codec.toolOutput(output)))
        recordDiagnostic(
            source: .adapter,
            category: "tool_output_submitted",
            interactionID: interactionID,
            disposition: "submitted",
            itemCorrelationHash: Self.correlationHash(output.callID),
            byteCount: output.output.utf8.count
        )
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
        recordDiagnostic(
            source: .adapter,
            category: "tool_continuation_requested",
            interactionID: interactionID,
            disposition: "response_create"
        )
    }

    func receive(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEvent {
        try requireActive(interactionID)
        if !pendingEvents.isEmpty {
            return pendingEvents.removeFirst()
        }
        return try await nextRecognizedEvent(interactionID: interactionID)
    }

    func cancel(
        interactionID: NativeSpeechInteractionID,
        reason: NativeSpeechCancellationReason
    ) async throws {
        try requireActive(interactionID)
        guard isProviderResponseActive else {
            resetResidentResponseState()
            if reason == .interrupted,
               !didEmitCancellationAcknowledgement {
                didEmitCancellationAcknowledgement = true
                pendingEvents.append(NativeSpeechEvent(
                    interactionID: interactionID,
                    kind: .cancelled(reason: reason.rawValue)
                ))
                recordDiagnostic(
                    source: .adapter,
                    category: "response_cancel_not_required",
                    interactionID: interactionID,
                    disposition: "provider_response_inactive"
                )
            }
            return
        }
        guard !isCancelling else { return }
        let eventID = "cancel-\(UUID().uuidString)"
        isCancelling = true
        didEmitCancellationAcknowledgement = false
        pendingCancellationEventID = eventID
        pendingCancellationResponseCorrelationHash =
            activeResponseCorrelationHash
        resetResidentResponseState()
        pendingEvents.removeAll {
            if case .outputText = $0.kind { return true }
            return false
        }
        connectionState = .cancelling
        do {
            try await transport.send(
                .text(try codec.responseCancel(eventID: eventID))
            )
        } catch {
            isCancelling = false
            pendingCancellationEventID = nil
            pendingCancellationResponseCorrelationHash = nil
            connectionState = .configured
            throw error
        }
    }

    func close(interactionID: NativeSpeechInteractionID) async throws {
        guard activeInteraction?.id == interactionID else {
            if activeInteraction == nil { return }
            throw NativeSpeechError.interactionMismatch
        }
        connectionState = .closing
        resetConnection()
        await transport.close(reason: .normal)
        connectionState = .closed
    }

    private func connectAndConfigure(
        request: NativeSpeechStartRequest,
        contextProjection: RealtimeSpeechContextProjection,
        credential: String
    ) async throws {
        connectionState = .connecting
        try await transport.connect(
            endpoint: request.profile.endpoint,
            bearerToken: credential
        )
        activeInteraction = request.interaction
        activeContextVersion = contextProjection.compilationVersion
        isCancelling = false
        didEmitCancellationAcknowledgement = false
        didEmitTurnFailureOutcome = false
        isProviderResponseActive = false
        activeResponseCorrelationHash = nil
        pendingCancellationResponseCorrelationHash = nil
        pendingCancellationEventID = nil
        nextOutputAudioSequenceNumber = 0
        wireReceiveOrdinal = 0
        lastOutputAudioArrivalNanoseconds = nil
        pendingToolCalls.removeAll(keepingCapacity: true)
        completedToolCallIDs.removeAll(keepingCapacity: true)
        completedToolCallOrder.removeAll(keepingCapacity: true)
        didRequestToolContinuation = false
        userTranscriptAccumulator = ""
        activeUserItemCorrelationHash = nil
        userTranscriptFinalized = false
        seenUserTranscriptEventHashes.removeAll(keepingCapacity: true)
        userSpeechIsActive = false
        suppressedResponseCorrelationHashes.removeAll(keepingCapacity: true)
        suppressedResponseCorrelationOrder.removeAll(keepingCapacity: true)
        resetResidentResponseState()

        let created = try await nextRecognizedEvent(
            interactionID: request.interaction.id
        )
        guard created.kind == .connected else {
            throw NativeSpeechError.invalidEvent
        }
        connectionState = .connected
        try await transport.send(
            .text(try codec.sessionUpdate(
                profile: request.profile,
                instructions: contextProjection.instructions,
                tools: request.tools
            ))
        )
        let updated = try await nextRecognizedEvent(
            interactionID: request.interaction.id
        )
        guard updated.kind == .sessionUpdated else {
            throw NativeSpeechError.invalidEvent
        }
        connectionState = .configured
        pendingEvents = [created, updated]
    }

    private func resetConnection() {
        activeInteraction = nil
        activeContextVersion = nil
        pendingEvents.removeAll()
        isCancelling = false
        didEmitCancellationAcknowledgement = false
        didEmitTurnFailureOutcome = false
        isProviderResponseActive = false
        activeResponseCorrelationHash = nil
        pendingCancellationResponseCorrelationHash = nil
        pendingCancellationEventID = nil
        nextOutputAudioSequenceNumber = 0
        wireReceiveOrdinal = 0
        lastOutputAudioArrivalNanoseconds = nil
        pendingToolCalls.removeAll(keepingCapacity: true)
        completedToolCallIDs.removeAll(keepingCapacity: true)
        completedToolCallOrder.removeAll(keepingCapacity: true)
        didRequestToolContinuation = false
        userTranscriptAccumulator = ""
        activeUserItemCorrelationHash = nil
        userTranscriptFinalized = false
        seenUserTranscriptEventHashes.removeAll(keepingCapacity: true)
        userSpeechIsActive = false
        suppressedResponseCorrelationHashes.removeAll(keepingCapacity: true)
        suppressedResponseCorrelationOrder.removeAll(keepingCapacity: true)
        resetResidentResponseState()
    }

    private func resetResidentResponseState() {
        residentTranscriptAccumulator = ""
        activeResidentItemCorrelationHash = nil
        suppressedResidentItemCorrelationHashes.removeAll(
            keepingCapacity: true
        )
        residentTranscriptFinalized = false
        pendingResidentPartialCheckpoints.removeAll(keepingCapacity: true)
        residentAudioByteCount = 0
        residentCheckpointedVisibleCharacterCount = 0
        residentLastCheckpointAudioByteCount = 0
        deferredResidentFinal = nil
        residentAudioFinished = false
        seenResidentTranscriptEventHashes.removeAll(keepingCapacity: true)
    }

    private func requireActive(_ interactionID: NativeSpeechInteractionID) throws {
        guard activeInteraction?.id == interactionID else {
            throw NativeSpeechError.interactionMismatch
        }
    }

    private func nextRecognizedEvent(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEvent {
        while true {
            let receivedAt: UInt64
            let frame: RealtimeWebSocketFrame
            do {
                frame = try await transport.receive()
                receivedAt = DispatchTime.now().uptimeNanoseconds
            } catch is CancellationError {
                throw NativeSpeechError.cancelled
            } catch let error as NativeSpeechError {
                recordDiagnostic(
                    source: .adapter,
                    category: "receive_failed",
                    interactionID: interactionID,
                    errorCode: Self.standardErrorName(error)
                )
                throw error
            } catch {
                recordDiagnostic(
                    source: .adapter,
                    category: "receive_failed",
                    interactionID: interactionID,
                    errorCode: "transport_failure"
                )
                throw NativeSpeechError.transportFailure
            }
            let envelope = try codec.decodeEnvelope(
                frame,
                interactionID: interactionID,
                outputAudioSequenceNumber: nextOutputAudioSequenceNumber
            )
            wireReceiveOrdinal &+= 1
            let audioInterval: UInt64?
            if envelope.wireKind == .outputAudioDelta {
                audioInterval = lastOutputAudioArrivalNanoseconds.map {
                    (receivedAt &- $0) / 1_000_000
                }
                lastOutputAudioArrivalNanoseconds = receivedAt
            } else {
                audioInterval = nil
            }
            let wireMetadata = Self.eventMetadata(envelope.event?.kind)
            recordDiagnostic(
                source: .wire,
                category: envelope.wireKind.rawValue,
                interactionID: interactionID,
                disposition: Self.responseDisposition(envelope),
                wireSequence: wireReceiveOrdinal,
                responseCorrelationHash:
                    envelope.responseCorrelationHash,
                itemCorrelationHash: envelope.itemCorrelationHash
                    ?? envelope.callCorrelationHash,
                audioSequence: wireMetadata.audioSequence,
                byteCount: wireMetadata.byteCount,
                arrivalIntervalMilliseconds: audioInterval,
                errorCode: wireMetadata.errorCode,
                nowNanoseconds: receivedAt
            )
            if envelope.wireKind == .responseCreated,
               userSpeechIsActive {
                if let responseHash = envelope.responseCorrelationHash {
                    suppressResponse(responseHash)
                }
                ignoredEventCount &+= 1
                recordDiagnostic(
                    source: .adapter,
                    category: "response_created_ignored_during_user_speech",
                    interactionID: interactionID,
                    disposition: "stale_response_start",
                    wireSequence: wireReceiveOrdinal,
                    responseCorrelationHash:
                        envelope.responseCorrelationHash
                )
                continue
            }
            if isSuppressedResponseEvent(envelope) {
                ignoredEventCount &+= 1
                recordDiagnostic(
                    source: .adapter,
                    category: "stale_response_event_ignored",
                    interactionID: interactionID,
                    disposition: envelope.wireKind.rawValue,
                    wireSequence: wireReceiveOrdinal,
                    responseCorrelationHash:
                        envelope.responseCorrelationHash,
                    itemCorrelationHash: envelope.itemCorrelationHash
                )
                continue
            }
            if envelope.wireKind == .responseCreated {
                let bridgesPendingCancellation = isCancelling
                    && !didEmitCancellationAcknowledgement
                if let previousResponse = activeResponseCorrelationHash,
                   previousResponse != envelope.responseCorrelationHash {
                    suppressResponse(previousResponse)
                }
                if bridgesPendingCancellation,
                   let cancellingResponse =
                    pendingCancellationResponseCorrelationHash {
                    suppressResponse(cancellingResponse)
                }
                isCancelling = false
                didEmitCancellationAcknowledgement = false
                didEmitTurnFailureOutcome = false
                isProviderResponseActive = true
                activeResponseCorrelationHash =
                    envelope.responseCorrelationHash
                pendingCancellationEventID = nil
                pendingCancellationResponseCorrelationHash = nil
                pendingToolCalls.removeAll(keepingCapacity: true)
                didRequestToolContinuation = false
                resetResidentResponseState()
                if bridgesPendingCancellation {
                    if let responseCreated = normalizedEvent(
                        from: envelope,
                        interactionID: interactionID
                    ) {
                        pendingEvents.append(emitStandardEvent(
                            responseCreated,
                            envelope: envelope,
                            receivedAtNanoseconds: receivedAt
                        ))
                    }
                    recordDiagnostic(
                        source: .adapter,
                        category: "response_cancel_superseded",
                        interactionID: interactionID,
                        disposition: "next_response_created",
                        wireSequence: wireReceiveOrdinal,
                        responseCorrelationHash:
                            envelope.responseCorrelationHash
                    )
                    return emitStandardEvent(
                        NativeSpeechEvent(
                            interactionID: interactionID,
                            kind: .cancelled(reason: "interrupted")
                        ),
                        envelope: envelope,
                        receivedAtNanoseconds: receivedAt
                    )
                }
            }
            if isCancelling,
               case .failed(let cancellationError) = envelope.event?.kind,
               cancellationError != .unauthorized,
               envelope.causedByEventID == pendingCancellationEventID {
                didEmitCancellationAcknowledgement = true
                if let cancellingResponse =
                    pendingCancellationResponseCorrelationHash {
                    suppressResponse(cancellingResponse)
                }
                isProviderResponseActive = false
                activeResponseCorrelationHash = nil
                pendingCancellationEventID = nil
                pendingCancellationResponseCorrelationHash = nil
                resetResidentResponseState()
                connectionState = .configured
                return emitStandardEvent(
                    NativeSpeechEvent(
                        interactionID: interactionID,
                        kind: .cancelled(reason: "interrupted")
                    ),
                    envelope: envelope,
                    receivedAtNanoseconds: receivedAt
                )
            }
            if isCancelling,
               (envelope.wireKind == .cancellationAcknowledgement
                    || envelope.wireKind == .responseCompleted) {
                guard !didEmitCancellationAcknowledgement else {
                    ignoredEventCount &+= 1
                    continue
                }
                didEmitCancellationAcknowledgement = true
                if let cancellingResponse =
                    pendingCancellationResponseCorrelationHash {
                    suppressResponse(cancellingResponse)
                }
                isProviderResponseActive = false
                activeResponseCorrelationHash = nil
                pendingCancellationEventID = nil
                pendingCancellationResponseCorrelationHash = nil
                resetResidentResponseState()
                connectionState = .configured
                return emitStandardEvent(
                    NativeSpeechEvent(
                        interactionID: interactionID,
                        kind: .cancelled(reason: "interrupted")
                    ),
                    envelope: envelope,
                    receivedAtNanoseconds: receivedAt
                )
            }
            if envelope.wireKind == .cancellationAcknowledgement {
                ignoredEventCount &+= 1
                recordDiagnostic(
                    source: .adapter,
                    category: "late_cancellation_ack_ignored",
                    interactionID: interactionID,
                    disposition: "no_pending_cancel",
                    wireSequence: wireReceiveOrdinal,
                    responseCorrelationHash:
                        envelope.responseCorrelationHash
                )
                continue
            }
            if Self.requiresActiveResponseCorrelation(
                envelope.wireKind
            ), !responseEventMatchesActive(envelope) {
                ignoredEventCount &+= 1
                recordDiagnostic(
                    source: .adapter,
                    category: "stale_response_event_ignored",
                    interactionID: interactionID,
                    disposition: envelope.wireKind.rawValue,
                    wireSequence: wireReceiveOrdinal,
                    responseCorrelationHash:
                        envelope.responseCorrelationHash,
                    errorCode: Self.eventMetadata(
                        envelope.event?.kind
                    ).errorCode
                )
                continue
            }
            if isDuplicateTranscriptEvent(envelope) {
                ignoredEventCount &+= 1
                recordDiagnostic(
                    source: .adapter,
                    category: "duplicate_transcript_event_ignored",
                    interactionID: interactionID,
                    disposition: envelope.wireKind.rawValue,
                    wireSequence: wireReceiveOrdinal,
                    responseCorrelationHash:
                        envelope.responseCorrelationHash,
                    itemCorrelationHash: envelope.itemCorrelationHash
                )
                continue
            }
            if envelope.wireKind == .providerError,
               case .failed(let error) = envelope.event?.kind {
                if error == .unauthorized {
                    return emitStandardEvent(
                        NativeSpeechEvent(
                            interactionID: interactionID,
                            kind: .failed(error)
                        ),
                        envelope: envelope,
                        receivedAtNanoseconds: receivedAt
                    )
                }
                guard isProviderResponseActive else {
                    ignoredEventCount &+= 1
                    recordDiagnostic(
                        source: .adapter,
                        category: "recoverable_provider_error_ignored",
                        interactionID: interactionID,
                        disposition: "no_active_response",
                        wireSequence: wireReceiveOrdinal,
                        responseCorrelationHash:
                            envelope.responseCorrelationHash,
                        itemCorrelationHash:
                            envelope.itemCorrelationHash,
                        errorCode: Self.standardErrorName(error)
                    )
                    continue
                }
                if let eventResponse = envelope.responseCorrelationHash,
                   let activeResponse = activeResponseCorrelationHash,
                   eventResponse != activeResponse {
                    ignoredEventCount &+= 1
                    recordDiagnostic(
                        source: .adapter,
                        category: "recoverable_provider_error_ignored",
                        interactionID: interactionID,
                        disposition: "stale_response",
                        wireSequence: wireReceiveOrdinal,
                        responseCorrelationHash: eventResponse,
                        errorCode: Self.standardErrorName(error)
                    )
                    continue
                }
                guard !didEmitTurnFailureOutcome else {
                    ignoredEventCount &+= 1
                    continue
                }
                didEmitTurnFailureOutcome = true
                suppressCurrentResponse(envelope)
                isProviderResponseActive = false
                activeResponseCorrelationHash = nil
                resetResidentResponseState()
                connectionState = .configured
                return emitStandardEvent(
                    NativeSpeechEvent(
                        interactionID: interactionID,
                        kind: .turnFailed(error)
                    ),
                    envelope: envelope,
                    receivedAtNanoseconds: receivedAt
                )
            }
            if case .turnFailed(let error) = envelope.event?.kind {
                guard !didEmitTurnFailureOutcome else {
                    ignoredEventCount &+= 1
                    continue
                }
                didEmitTurnFailureOutcome = true
                suppressCurrentResponse(envelope)
                isProviderResponseActive = false
                activeResponseCorrelationHash = nil
                resetResidentResponseState()
                connectionState = .configured
                return emitStandardEvent(
                    NativeSpeechEvent(
                        interactionID: interactionID,
                        kind: .turnFailed(error)
                    ),
                    envelope: envelope,
                    receivedAtNanoseconds: receivedAt
                )
            }
            if didEmitTurnFailureOutcome,
               Self.isResponseScoped(envelope.wireKind) {
                ignoredEventCount &+= 1
                continue
            }
            if let toolEvent = try standardizedToolEvent(
                from: envelope,
                interactionID: interactionID
            ) {
                return emitStandardEvent(
                    toolEvent,
                    envelope: envelope,
                    receivedAtNanoseconds: receivedAt
                )
            }
            if envelope.toolWireEvent != nil {
                continue
            }
            if envelope.wireKind == .outputAudioDone {
                residentAudioFinished = true
                if let final = takeDeferredResidentFinal(
                    matching: envelope,
                    interactionID: interactionID,
                    boundary: "output_audio_done"
                ) {
                    return emitStandardEvent(
                        final,
                        envelope: envelope,
                        receivedAtNanoseconds: receivedAt
                    )
                }
                discardResidentPartialCheckpoints(
                    interactionID: interactionID,
                    boundary: "output_audio_done"
                )
                continue
            }
            if let event = normalizedEvent(
                from: envelope,
                interactionID: interactionID
            ) {
                if case .responseCompleted = event.kind,
                   let final = takeDeferredResidentFinal(
                    matching: envelope,
                    interactionID: interactionID,
                    boundary: "response_completed"
                   ) {
                    suppressCurrentResponse(envelope)
                    isProviderResponseActive = false
                    activeResponseCorrelationHash = nil
                    connectionState = .configured
                    pendingEvents.append(emitStandardEvent(
                        event,
                        envelope: envelope,
                        receivedAtNanoseconds: receivedAt
                    ))
                    return emitStandardEvent(
                        final,
                        envelope: envelope,
                        receivedAtNanoseconds: receivedAt
                    )
                }
                switch event.kind {
                case .thinking, .outputText:
                    isProviderResponseActive = true
                case .outputAudio:
                    isProviderResponseActive = true
                    if activeResponseCorrelationHash == nil {
                        activeResponseCorrelationHash =
                            envelope.responseCorrelationHash
                    }
                    nextOutputAudioSequenceNumber &+= 1
                    connectionState = .streaming
                case .responseCompleted:
                    suppressCurrentResponse(envelope)
                    isProviderResponseActive = false
                    activeResponseCorrelationHash = nil
                    discardResidentPartialCheckpoints(
                        interactionID: interactionID,
                        boundary: "response_completed"
                    )
                    connectionState = .configured
                case .cancelled, .turnFailed, .failed:
                    isProviderResponseActive = false
                    activeResponseCorrelationHash = nil
                    resetResidentResponseState()
                    connectionState = .configured
                default:
                    break
                }
                let standardEvent = emitStandardEvent(
                    event,
                    envelope: envelope,
                    receivedAtNanoseconds: receivedAt
                )
                if case .outputAudio(let payload) = event.kind {
                    let (byteCount, overflow) =
                        residentAudioByteCount
                            .addingReportingOverflow(payload.bytes.count)
                    residentAudioByteCount = overflow
                        ? Int.max
                        : byteCount
                }
                if case .outputAudio = event.kind,
                   let partial = takeResidentPartialCheckpoint(
                        matching: envelope,
                        interactionID: interactionID
                   ) {
                    pendingEvents.append(emitStandardEvent(
                        partial,
                        envelope: envelope,
                        receivedAtNanoseconds: receivedAt
                    ))
                }
                return standardEvent
            }
            if envelope.wireKind == .residentAudioTranscriptDelta
                || envelope.wireKind == .residentAudioTranscriptDone {
                recordDiagnostic(
                    source: .adapter,
                    category: envelope.wireKind
                        == .residentAudioTranscriptDelta
                        ? "resident_partial_buffered"
                        : "resident_final_deferred",
                    interactionID: interactionID,
                    disposition: envelope.wireKind
                        == .residentAudioTranscriptDelta
                        ? "awaiting_correlated_audio"
                        : "awaiting_audio_boundary",
                    wireSequence: wireReceiveOrdinal,
                    responseCorrelationHash:
                        envelope.responseCorrelationHash,
                    itemCorrelationHash: envelope.itemCorrelationHash
                )
                continue
            }
            ignoredEventCount &+= 1
            recordDiagnostic(
                source: .adapter,
                category: "wire_event_ignored",
                interactionID: interactionID,
                disposition: envelope.wireKind.rawValue,
                wireSequence: wireReceiveOrdinal,
                responseCorrelationHash:
                    envelope.responseCorrelationHash,
                itemCorrelationHash: envelope.itemCorrelationHash,
                wireToStandardDurationMilliseconds:
                    (DispatchTime.now().uptimeNanoseconds &- receivedAt)
                        / 1_000_000
            )
        }
    }

    private func normalizedEvent(
        from envelope: StepFunRealtimeDecodedEnvelope,
        interactionID: NativeSpeechInteractionID
    ) -> NativeSpeechEvent? {
        guard let event = envelope.event else { return nil }
        switch envelope.wireKind {
        case .userTranscriptDelta:
            guard userTranscriptMatchesActiveItem(envelope),
                  !userTranscriptFinalized,
                  case .partialTranscript(let fragment) = event.kind,
                  let cumulative = Self.appendTranscriptFragment(
                    fragment,
                    into: &userTranscriptAccumulator
                  ) else {
                return nil
            }
            return NativeSpeechEvent(
                interactionID: interactionID,
                kind: .partialTranscript(cumulative)
            )
        case .userTranscriptDone:
            guard userTranscriptMatchesActiveItem(envelope),
                  !userTranscriptFinalized,
                  case .finalTranscript(let text) = event.kind else {
                return nil
            }
            userTranscriptFinalized = true
            userTranscriptAccumulator = text
            return event
        case .residentAudioTranscriptDelta:
            guard residentTranscriptMatchesActiveItem(envelope),
                  !residentTranscriptFinalized,
                  !residentAudioFinished,
                  case .outputText(let fragment, false) = event.kind,
                  let cumulative = Self.appendTranscriptFragment(
                    fragment,
                    into: &residentTranscriptAccumulator
                  ) else {
                return nil
            }
            appendResidentPartialCheckpoints(
                text: cumulative,
                envelope: envelope
            )
            return nil
        case .residentAudioTranscriptDone:
            guard residentTranscriptMatchesActiveItem(envelope),
                  !residentTranscriptFinalized,
                  case .outputText(let text, true) = event.kind else {
                return nil
            }
            residentTranscriptFinalized = true
            residentTranscriptAccumulator = text
            deferredResidentFinal = StepFunDeferredResidentFinal(
                text: text,
                responseCorrelationHash:
                    envelope.responseCorrelationHash,
                itemCorrelationHash: envelope.itemCorrelationHash
            )
            return nil
        case .residentTextDelta, .residentTextDone:
            return nil
        case .toolCallCreated, .toolArgumentsDelta,
             .toolArgumentsDone:
            return nil
        case .responseCreated, .responseCompleted,
             .cancellationAcknowledgement:
            return event
        case .sessionCreated, .sessionUpdated, .inputSpeechStarted,
             .inputSpeechEnded, .outputAudioDelta, .providerError,
             .other:
            if case .inputSpeechStarted = event.kind {
                userSpeechIsActive = true
                activeUserItemCorrelationHash =
                    envelope.itemCorrelationHash
                userTranscriptAccumulator = ""
                userTranscriptFinalized = false
                seenUserTranscriptEventHashes.removeAll(
                    keepingCapacity: true
                )
                resetResidentResponseState()
            } else if case .inputSpeechEnded = event.kind {
                userSpeechIsActive = false
            }
            return event
        case .conversationItemCreated:
            guard userTranscriptMatchesActiveItem(envelope),
                  !userTranscriptFinalized,
                  case .finalTranscript(let text) = event.kind else {
                return nil
            }
            if userTranscriptAccumulator.isEmpty {
                recordDiagnostic(
                    source: .adapter,
                    category: "provider_user_partial_unavailable",
                    interactionID: interactionID,
                    disposition: "conversation_item_final_only",
                    wireSequence: wireReceiveOrdinal,
                    itemCorrelationHash: envelope.itemCorrelationHash
                )
            }
            userTranscriptFinalized = true
            userTranscriptAccumulator = text
            return event
        case .outputAudioDone:
            return nil
        }
    }

    private func userTranscriptMatchesActiveItem(
        _ envelope: StepFunRealtimeDecodedEnvelope
    ) -> Bool {
        guard let incoming = envelope.itemCorrelationHash else {
            return true
        }
        guard let active = activeUserItemCorrelationHash else {
            activeUserItemCorrelationHash = incoming
            return true
        }
        guard incoming == active else {
            ignoredEventCount &+= 1
            recordDiagnostic(
                source: .adapter,
                category: "stale_user_transcript_ignored",
                interactionID: activeInteraction?.id,
                disposition: "item_mismatch",
                wireSequence: wireReceiveOrdinal,
                itemCorrelationHash: incoming
            )
            return false
        }
        return true
    }

    private func residentTranscriptMatchesActiveItem(
        _ envelope: StepFunRealtimeDecodedEnvelope
    ) -> Bool {
        guard let incoming = envelope.itemCorrelationHash else {
            return true
        }
        if suppressedResidentItemCorrelationHashes.contains(incoming) {
            ignoredEventCount &+= 1
            recordDiagnostic(
                source: .adapter,
                category: "stale_resident_transcript_ignored",
                interactionID: activeInteraction?.id,
                disposition: "item_mismatch",
                wireSequence: wireReceiveOrdinal,
                responseCorrelationHash:
                    envelope.responseCorrelationHash,
                itemCorrelationHash: incoming
            )
            return false
        }
        guard let active = activeResidentItemCorrelationHash else {
            activeResidentItemCorrelationHash = incoming
            return true
        }
        guard incoming != active else { return true }
        suppressedResidentItemCorrelationHashes.insert(active)
        resetResidentTranscriptProjectionForItemChange()
        activeResidentItemCorrelationHash = incoming
        return true
    }

    private func resetResidentTranscriptProjectionForItemChange() {
        residentTranscriptAccumulator = ""
        residentTranscriptFinalized = false
        pendingResidentPartialCheckpoints.removeAll(keepingCapacity: true)
        residentAudioByteCount = 0
        residentCheckpointedVisibleCharacterCount = 0
        residentLastCheckpointAudioByteCount = 0
        deferredResidentFinal = nil
        residentAudioFinished = false
    }

    private func takeResidentPartialCheckpoint(
        matching envelope: StepFunRealtimeDecodedEnvelope,
        interactionID: NativeSpeechInteractionID
    ) -> NativeSpeechEvent? {
        guard let checkpoint = pendingResidentPartialCheckpoints.first else {
            return nil
        }
        guard residentAudioByteCount
                >= checkpoint.requiredCumulativeAudioByteCount else {
            return nil
        }
        let responseMatches = Self.correlationMatches(
            checkpoint.responseCorrelationHash,
            envelope.responseCorrelationHash
        )
        let itemMatches = Self.correlationMatches(
            checkpoint.itemCorrelationHash,
            envelope.itemCorrelationHash
        )
        let activeResponseMatches = Self.correlationMatches(
            checkpoint.responseCorrelationHash,
            activeResponseCorrelationHash
        )
        let hasMismatch = responseMatches == false
            || itemMatches == false
            || activeResponseMatches == false
        let hasMatch = responseMatches == true
            || itemMatches == true
            || activeResponseMatches == true
            || (checkpoint.responseCorrelationHash == nil
                && checkpoint.itemCorrelationHash == nil
                && envelope.responseCorrelationHash == nil
                && envelope.itemCorrelationHash == nil
                && isProviderResponseActive)
        guard hasMatch, !hasMismatch else {
            recordDiagnostic(
                source: .adapter,
                category: hasMismatch
                    ? "provider_subtitle_correlation_mismatch"
                    : "provider_subtitle_correlation_unavailable",
                interactionID: interactionID,
                disposition: "partial_not_released",
                wireSequence: wireReceiveOrdinal,
                responseCorrelationHash:
                    envelope.responseCorrelationHash,
                itemCorrelationHash: envelope.itemCorrelationHash
            )
            if hasMismatch {
                pendingResidentPartialCheckpoints.removeAll(
                    keepingCapacity: true
                )
                residentAudioByteCount = 0
                residentCheckpointedVisibleCharacterCount = 0
                residentLastCheckpointAudioByteCount = 0
            }
            return nil
        }
        pendingResidentPartialCheckpoints.removeFirst()
        return NativeSpeechEvent(
            interactionID: interactionID,
            kind: .outputText(
                text: checkpoint.text,
                isFinal: false
            )
        )
    }

    private func takeDeferredResidentFinal(
        matching envelope: StepFunRealtimeDecodedEnvelope,
        interactionID: NativeSpeechInteractionID,
        boundary: String
    ) -> NativeSpeechEvent? {
        guard let final = deferredResidentFinal else { return nil }
        let responseMatches = Self.correlationMatches(
            final.responseCorrelationHash,
            envelope.responseCorrelationHash
        )
        let itemMatches = Self.correlationMatches(
            final.itemCorrelationHash,
            envelope.itemCorrelationHash
        )
        let activeResponseMatches = Self.correlationMatches(
            final.responseCorrelationHash,
            activeResponseCorrelationHash
        )
        let hasMismatch = responseMatches == false
            || itemMatches == false
            || activeResponseMatches == false
        let hasMatch = responseMatches == true
            || itemMatches == true
            || activeResponseMatches == true
            || (final.responseCorrelationHash == nil
                && final.itemCorrelationHash == nil
                && envelope.responseCorrelationHash == nil
                && envelope.itemCorrelationHash == nil
                && isProviderResponseActive)
        guard hasMatch, !hasMismatch else {
            recordDiagnostic(
                source: .adapter,
                category: "provider_subtitle_correlation_mismatch",
                interactionID: interactionID,
                disposition: "final_not_released_\(boundary)",
                wireSequence: wireReceiveOrdinal,
                responseCorrelationHash:
                    envelope.responseCorrelationHash,
                itemCorrelationHash: envelope.itemCorrelationHash
            )
            resetResidentResponseState()
            return nil
        }
        deferredResidentFinal = nil
        discardResidentPartialCheckpoints(
            interactionID: interactionID,
            boundary: boundary
        )
        return NativeSpeechEvent(
            interactionID: interactionID,
            kind: .outputText(text: final.text, isFinal: true)
        )
    }

    private func discardResidentPartialCheckpoints(
        interactionID: NativeSpeechInteractionID,
        boundary: String
    ) {
        let remaining = pendingResidentPartialCheckpoints.count
        residentAudioByteCount = 0
        residentCheckpointedVisibleCharacterCount = 0
        residentLastCheckpointAudioByteCount = 0
        guard remaining > 0 else { return }
        pendingResidentPartialCheckpoints.removeAll(keepingCapacity: true)
        recordDiagnostic(
            source: .adapter,
            category: "resident_partial_checkpoints_discarded",
            interactionID: interactionID,
            disposition: "\(boundary):\(remaining)"
        )
    }

    private func isDuplicateTranscriptEvent(
        _ envelope: StepFunRealtimeDecodedEnvelope
    ) -> Bool {
        guard let eventHash = envelope.wireEventCorrelationHash else {
            return false
        }
        switch envelope.wireKind {
        case .userTranscriptDelta, .userTranscriptDone:
            if seenUserTranscriptEventHashes.count
                >= Self.transcriptEventIdentityCapacity {
                seenUserTranscriptEventHashes.removeAll(
                    keepingCapacity: true
                )
            }
            return !seenUserTranscriptEventHashes
                .insert(eventHash).inserted
        case .residentAudioTranscriptDelta,
             .residentAudioTranscriptDone:
            if seenResidentTranscriptEventHashes.count
                >= Self.transcriptEventIdentityCapacity {
                seenResidentTranscriptEventHashes.removeAll(
                    keepingCapacity: true
                )
            }
            return !seenResidentTranscriptEventHashes
                .insert(eventHash).inserted
        default:
            return false
        }
    }

    private func appendResidentPartialCheckpoints(
        text: String,
        envelope: StepFunRealtimeDecodedEnvelope
    ) {
        var visibleCharacterCount = 0
        for index in text.indices {
            let character = text[index]
            let isBoundary = Self.residentSubtitlePhraseBoundaries
                .contains(character)
            if !character.isWhitespace, !isBoundary {
                visibleCharacterCount += 1
            }
            let addedCharacterCount = visibleCharacterCount
                - residentCheckpointedVisibleCharacterCount
            guard addedCharacterCount
                    >= Self.residentSubtitleMaximumPhraseCharacterCount
                    || (isBoundary
                        && addedCharacterCount
                            >= Self.residentSubtitleMinimumBoundaryCharacterCount)
            else {
                continue
            }
            appendResidentPartialCheckpoint(
                text: String(text[...index]),
                visibleCharacterCount: visibleCharacterCount,
                envelope: envelope
            )
        }
    }

    private func appendResidentPartialCheckpoint(
        text: String,
        visibleCharacterCount: Int,
        envelope: StepFunRealtimeDecodedEnvelope
    ) {
        let characterWatermark = visibleCharacterCount
            .multipliedReportingOverflow(
                by: Self.residentSubtitleAudioBytesPerVisibleCharacter
            )
        let minimumPhraseWatermark = residentLastCheckpointAudioByteCount
            .addingReportingOverflow(
                Self.residentSubtitleMinimumPhraseByteCount
            )
        let requiredAudioByteCount = max(
            characterWatermark.overflow
                ? Int.max : characterWatermark.partialValue,
            minimumPhraseWatermark.overflow
                ? Int.max : minimumPhraseWatermark.partialValue
        )
        let checkpoint = StepFunResidentPartialCheckpoint(
            text: text,
            responseCorrelationHash: envelope.responseCorrelationHash,
            itemCorrelationHash: envelope.itemCorrelationHash,
            requiredCumulativeAudioByteCount: requiredAudioByteCount
        )
        if pendingResidentPartialCheckpoints.last == checkpoint {
            return
        }
        if pendingResidentPartialCheckpoints.count
            >= Self.residentPartialCheckpointCapacity {
            let previousCount = pendingResidentPartialCheckpoints.count
            let previous = pendingResidentPartialCheckpoints
            let preservedPrefixCount =
                Self.residentPartialCheckpointCapacity / 2
            var compacted = Array(
                previous.prefix(preservedPrefixCount)
            )
            compacted.append(contentsOf: stride(
                from: preservedPrefixCount + 1,
                to: previousCount,
                by: 2
            ).map { previous[$0] })
            if compacted.last != previous.last,
               let latest = previous.last {
                compacted.append(latest)
            }
            pendingResidentPartialCheckpoints = compacted
            let compactedCount = previousCount
                - pendingResidentPartialCheckpoints.count
            recordDiagnostic(
                source: .adapter,
                category: "resident_partial_checkpoints_compacted",
                interactionID: activeInteraction?.id,
                disposition: "capacity:\(compactedCount)",
                wireSequence: wireReceiveOrdinal,
                responseCorrelationHash:
                    envelope.responseCorrelationHash,
                itemCorrelationHash: envelope.itemCorrelationHash
            )
        }
        pendingResidentPartialCheckpoints.append(checkpoint)
        residentCheckpointedVisibleCharacterCount = visibleCharacterCount
        residentLastCheckpointAudioByteCount = requiredAudioByteCount
    }

    private static func visibleSubtitleCharacterCount(
        in text: String
    ) -> Int {
        text.reduce(into: 0) { count, character in
            if !character.isWhitespace,
               !residentSubtitlePhraseBoundaries.contains(character) {
                count += 1
            }
        }
    }

    private func isSuppressedResponseEvent(
        _ envelope: StepFunRealtimeDecodedEnvelope
    ) -> Bool {
        guard (envelope.wireKind == .responseCreated
                || Self.isResponseScoped(envelope.wireKind)),
              let responseHash = envelope.responseCorrelationHash else {
            return false
        }
        return suppressedResponseCorrelationHashes.contains(responseHash)
    }

    private func suppressResponse(_ responseHash: String) {
        guard suppressedResponseCorrelationHashes.insert(responseHash)
            .inserted else {
            return
        }
        suppressedResponseCorrelationOrder.append(responseHash)
        if suppressedResponseCorrelationOrder.count
            > Self.suppressedResponseCapacity {
            let evicted = suppressedResponseCorrelationOrder.removeFirst()
            suppressedResponseCorrelationHashes.remove(evicted)
        }
    }

    private func suppressCurrentResponse(
        _ envelope: StepFunRealtimeDecodedEnvelope
    ) {
        guard let responseHash = envelope.responseCorrelationHash
                ?? activeResponseCorrelationHash else {
            return
        }
        suppressResponse(responseHash)
    }

    private func responseEventMatchesActive(
        _ envelope: StepFunRealtimeDecodedEnvelope
    ) -> Bool {
        switch (
            envelope.responseCorrelationHash,
            activeResponseCorrelationHash
        ) {
        case let (incoming?, active?):
            return incoming == active
        case (nil, nil):
            if !isProviderResponseActive {
                isProviderResponseActive = true
            }
            return true
        case let (incoming?, nil):
            activeResponseCorrelationHash = incoming
            isProviderResponseActive = true
            return true
        case (nil, _?):
            return false
        }
    }

    private static func correlationMatches(
        _ first: String?,
        _ second: String?
    ) -> Bool? {
        guard let first, let second else { return nil }
        return first == second
    }

    private static func appendTranscriptFragment(
        _ fragment: String,
        into accumulator: inout String
    ) -> String? {
        guard !fragment.isEmpty else { return nil }
        accumulator.append(fragment)
        return accumulator
    }

    private static func responseDisposition(
        _ envelope: StepFunRealtimeDecodedEnvelope
    ) -> String? {
        guard let status = envelope.responseStatus else { return nil }
        guard let detailReason = envelope.responseStatusDetailReason else {
            return status.rawValue
        }
        return "\(status.rawValue):\(detailReason.rawValue)"
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

    private static func isResponseScoped(
        _ wireKind: StepFunRealtimeWireEventKind
    ) -> Bool {
        switch wireKind {
        case .responseCreated, .sessionCreated, .sessionUpdated,
             .inputSpeechStarted, .inputSpeechEnded,
             .conversationItemCreated:
            return false
        case .userTranscriptDelta, .userTranscriptDone,
             .residentAudioTranscriptDelta, .residentAudioTranscriptDone,
             .residentTextDelta, .residentTextDone, .outputAudioDelta,
             .outputAudioDone, .responseCompleted,
             .toolCallCreated, .toolArgumentsDelta,
             .toolArgumentsDone,
             .cancellationAcknowledgement, .providerError, .other:
            return true
        }
    }

    private static func requiresActiveResponseCorrelation(
        _ wireKind: StepFunRealtimeWireEventKind
    ) -> Bool {
        switch wireKind {
        case .residentAudioTranscriptDelta,
             .residentAudioTranscriptDone,
             .residentTextDelta,
             .residentTextDone,
             .outputAudioDelta,
             .outputAudioDone,
             .responseCompleted:
            return true
        default:
            return false
        }
    }

    private func emitStandardEvent(
        _ event: NativeSpeechEvent,
        envelope: StepFunRealtimeDecodedEnvelope,
        receivedAtNanoseconds: UInt64
    ) -> NativeSpeechEvent {
        let metadata = Self.eventMetadata(event.kind)
        recordDiagnostic(
            source: .adapter,
            category: "standard_\(metadata.category)",
            interactionID: event.interactionID,
            disposition: "emitted",
            wireSequence: wireReceiveOrdinal,
            responseCorrelationHash: envelope.responseCorrelationHash,
            itemCorrelationHash: envelope.itemCorrelationHash
                ?? envelope.callCorrelationHash,
            audioSequence: metadata.audioSequence,
            byteCount: metadata.byteCount,
            wireToStandardDurationMilliseconds:
                (DispatchTime.now().uptimeNanoseconds
                    &- receivedAtNanoseconds) / 1_000_000,
            errorCode: metadata.errorCode
        )
        return event
    }

    private func standardizedToolEvent(
        from envelope: StepFunRealtimeDecodedEnvelope,
        interactionID: NativeSpeechInteractionID
    ) throws -> NativeSpeechEvent? {
        guard let toolWireEvent = envelope.toolWireEvent else { return nil }
        switch toolWireEvent {
        case .created(let callID, let name, let arguments):
            guard !completedToolCallIDs.contains(callID) else { return nil }
            pendingToolCalls[callID] = StepFunPendingToolCall(
                name: name,
                arguments: arguments ?? ""
            )
            return nil
        case .argumentsDelta(let callID, let name, let delta):
            guard !completedToolCallIDs.contains(callID) else { return nil }
            if var pending = pendingToolCalls[callID] {
                guard name == nil || name == pending.name else {
                    throw NativeSpeechError.invalidEvent
                }
                pending.arguments.append(delta)
                pendingToolCalls[callID] = pending
            } else if let name {
                pendingToolCalls[callID] = StepFunPendingToolCall(
                    name: name,
                    arguments: delta
                )
            } else {
                throw NativeSpeechError.invalidEvent
            }
            return nil
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
                kind: .toolRequestCandidate(
                    NativeSpeechToolRequest(
                        callID: callID,
                        toolName: name,
                        arguments: Data(completeArguments.utf8),
                        correlationHash: envelope.callCorrelationHash
                    )
                )
            )
        }
    }

    private func recordDiagnostic(
        source: NativeSpeechInternalDiagnosticSource,
        category: String,
        interactionID: NativeSpeechInteractionID? = nil,
        disposition: String? = nil,
        wireSequence: UInt64? = nil,
        responseCorrelationHash: String? = nil,
        itemCorrelationHash: String? = nil,
        audioSequence: UInt64? = nil,
        byteCount: Int? = nil,
        arrivalIntervalMilliseconds: UInt64? = nil,
        wireToStandardDurationMilliseconds: UInt64? = nil,
        errorCode: String? = nil,
        nowNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        diagnosticBuffer?.append(
            NativeSpeechInternalDiagnosticEvent(
                source: source,
                category: category,
                interactionShortID: interactionID.map {
                    String($0.rawValue.uuidString.prefix(8))
                },
                disposition: disposition,
                wireSequence: wireSequence,
                responseCorrelationHash: responseCorrelationHash,
                itemCorrelationHash: itemCorrelationHash,
                audioSequence: audioSequence,
                byteCount: byteCount,
                arrivalIntervalMilliseconds:
                    arrivalIntervalMilliseconds,
                wireToStandardDurationMilliseconds:
                    wireToStandardDurationMilliseconds,
                errorCode: errorCode,
                monotonicTimestampNanoseconds: nowNanoseconds
            )
        )
    }

    private static func eventMetadata(
        _ kind: NativeSpeechEventKind?
    ) -> (
        category: String,
        audioSequence: UInt64?,
        byteCount: Int?,
        errorCode: String?
    ) {
        guard let kind else { return ("none", nil, nil, nil) }
        return switch kind {
        case .connected: ("connected", nil, nil, nil)
        case .sessionUpdated: ("session_updated", nil, nil, nil)
        case .inputSpeechStarted: ("input_speech_started", nil, nil, nil)
        case .inputSpeechEnded: ("input_speech_ended", nil, nil, nil)
        case .partialTranscript(let text):
            ("user_partial", nil, text.utf8.count, nil)
        case .finalTranscript(let text):
            ("user_final", nil, text.utf8.count, nil)
        case .thinking: ("thinking", nil, nil, nil)
        case .outputText(_, let isFinal):
            (isFinal ? "resident_final" : "resident_partial",
             nil, nil, nil)
        case .outputAudio(let payload):
            ("output_audio", payload.sequenceNumber,
             payload.bytes.count, nil)
        case .toolRequestCandidate:
            ("tool_request_candidate", nil, nil, nil)
        case .responseCompleted:
            ("response_completed", nil, nil, nil)
        case .turnFailed(let error):
            ("turn_failed", nil, nil, standardErrorName(error))
        case .cancelled:
            ("cancelled", nil, nil, nil)
        case .closed:
            ("closed", nil, nil, nil)
        case .failed(let error):
            ("failed", nil, nil, standardErrorName(error))
        }
    }

    private static func standardErrorName(
        _ error: NativeSpeechError
    ) -> String {
        switch error {
        case .invalidConfiguration: "invalid_configuration"
        case .missingCredential: "missing_credential"
        case .unauthorized: "unauthorized"
        case .rateLimited: "rate_limited"
        case .unavailable: "unavailable"
        case .timedOut: "timed_out"
        case .cancelled: "cancelled"
        case .transportFailure: "transport_failure"
        case .invalidEvent: "invalid_event"
        case .interactionMismatch: "interaction_mismatch"
        }
    }

    private static func correlationHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
