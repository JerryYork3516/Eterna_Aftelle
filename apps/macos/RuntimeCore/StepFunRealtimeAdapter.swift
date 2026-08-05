import Foundation

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
    private var isProviderResponseActive = false
    private var pendingCancellationEventID: String?
    private var userTranscriptAccumulator = ""
    private var residentTranscriptAccumulator = ""
    private var userTranscriptFinalized = false
    private var residentTranscriptFinalized = false
    private var nextOutputAudioSequenceNumber: UInt64 = 0
    private var wireReceiveOrdinal: UInt64 = 0
    private var lastOutputAudioArrivalNanoseconds: UInt64?
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
            residentTranscriptAccumulator = ""
            residentTranscriptFinalized = false
            return
        }
        guard !isCancelling else { return }
        let eventID = "cancel-\(UUID().uuidString)"
        isCancelling = true
        pendingCancellationEventID = eventID
        residentTranscriptAccumulator = ""
        residentTranscriptFinalized = false
        connectionState = .cancelling
        do {
            try await transport.send(
                .text(try codec.responseCancel(eventID: eventID))
            )
        } catch {
            isCancelling = false
            pendingCancellationEventID = nil
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
        isProviderResponseActive = false
        pendingCancellationEventID = nil
        nextOutputAudioSequenceNumber = 0
        wireReceiveOrdinal = 0
        lastOutputAudioArrivalNanoseconds = nil
        userTranscriptAccumulator = ""
        residentTranscriptAccumulator = ""
        userTranscriptFinalized = false
        residentTranscriptFinalized = false

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
                instructions: contextProjection.instructions
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
        isProviderResponseActive = false
        pendingCancellationEventID = nil
        nextOutputAudioSequenceNumber = 0
        wireReceiveOrdinal = 0
        lastOutputAudioArrivalNanoseconds = nil
        userTranscriptAccumulator = ""
        residentTranscriptAccumulator = ""
        userTranscriptFinalized = false
        residentTranscriptFinalized = false
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
                wireSequence: wireReceiveOrdinal,
                responseCorrelationHash:
                    envelope.responseCorrelationHash,
                itemCorrelationHash: envelope.itemCorrelationHash,
                audioSequence: wireMetadata.audioSequence,
                byteCount: wireMetadata.byteCount,
                arrivalIntervalMilliseconds: audioInterval,
                errorCode: wireMetadata.errorCode,
                nowNanoseconds: receivedAt
            )
            if envelope.wireKind == .responseCreated {
                isCancelling = false
                didEmitCancellationAcknowledgement = false
                isProviderResponseActive = true
                pendingCancellationEventID = nil
                residentTranscriptAccumulator = ""
                residentTranscriptFinalized = false
            }
            if isCancelling,
               case .failed(.invalidEvent) = envelope.event?.kind,
               envelope.causedByEventID == pendingCancellationEventID {
                didEmitCancellationAcknowledgement = true
                isProviderResponseActive = false
                pendingCancellationEventID = nil
                residentTranscriptAccumulator = ""
                residentTranscriptFinalized = false
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
                isProviderResponseActive = false
                pendingCancellationEventID = nil
                residentTranscriptAccumulator = ""
                residentTranscriptFinalized = false
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
            if let event = normalizedEvent(
                from: envelope,
                interactionID: interactionID
            ) {
                switch event.kind {
                case .thinking, .outputText:
                    isProviderResponseActive = true
                case .outputAudio:
                    isProviderResponseActive = true
                    nextOutputAudioSequenceNumber &+= 1
                    connectionState = .streaming
                case .cancelled, .responseCompleted, .failed:
                    isProviderResponseActive = false
                    connectionState = .configured
                default:
                    break
                }
                return emitStandardEvent(
                    event,
                    envelope: envelope,
                    receivedAtNanoseconds: receivedAt
                )
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
            guard !userTranscriptFinalized,
                  case .partialTranscript(let fragment) = event.kind,
                  let cumulative = Self.accumulate(
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
            guard !userTranscriptFinalized,
                  case .finalTranscript(let text) = event.kind else {
                return nil
            }
            userTranscriptFinalized = true
            userTranscriptAccumulator = text
            return event
        case .residentAudioTranscriptDelta:
            guard !residentTranscriptFinalized,
                  case .outputText(let fragment, false) = event.kind,
                  let cumulative = Self.accumulate(
                    fragment,
                    into: &residentTranscriptAccumulator
                  ) else {
                return nil
            }
            return NativeSpeechEvent(
                interactionID: interactionID,
                kind: .outputText(text: cumulative, isFinal: false)
            )
        case .residentAudioTranscriptDone:
            guard !residentTranscriptFinalized,
                  case .outputText(let text, true) = event.kind else {
                return nil
            }
            residentTranscriptFinalized = true
            residentTranscriptAccumulator = text
            return event
        case .residentTextDelta, .residentTextDone:
            return nil
        case .responseCreated, .responseCompleted,
             .cancellationAcknowledgement:
            return event
        case .sessionCreated, .sessionUpdated, .inputSpeechStarted,
             .inputSpeechEnded, .outputAudioDelta, .providerError,
             .other:
            if case .inputSpeechStarted = event.kind {
                userTranscriptAccumulator = ""
                userTranscriptFinalized = false
            }
            return event
        case .outputAudioDone, .conversationItemCreated:
            return nil
        }
    }

    private static func accumulate(
        _ fragment: String,
        into accumulator: inout String
    ) -> String? {
        guard !fragment.isEmpty else { return nil }
        if fragment == accumulator || accumulator.hasSuffix(fragment) {
            return nil
        }
        if fragment.hasPrefix(accumulator) {
            accumulator = fragment
            return accumulator
        }
        let maximumOverlap = min(accumulator.count, fragment.count)
        var overlap = maximumOverlap
        while overlap > 0 {
            let suffix = accumulator.suffix(overlap)
            let prefix = fragment.prefix(overlap)
            if suffix == prefix { break }
            overlap -= 1
        }
        accumulator.append(contentsOf: fragment.dropFirst(overlap))
        return accumulator
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
            itemCorrelationHash: envelope.itemCorrelationHash,
            audioSequence: metadata.audioSequence,
            byteCount: metadata.byteCount,
            wireToStandardDurationMilliseconds:
                (DispatchTime.now().uptimeNanoseconds
                    &- receivedAtNanoseconds) / 1_000_000,
            errorCode: metadata.errorCode
        )
        return event
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
        case .partialTranscript: ("user_partial", nil, nil, nil)
        case .finalTranscript: ("user_final", nil, nil, nil)
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
}
