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
    private var activeInteraction: NativeSpeechInteraction?
    private var activeContextVersion: String?
    private var preparedContextProjection:
        RealtimeSpeechContextProjection?
    private var pendingEvents: [NativeSpeechEvent] = []
    private var isCancelling = false
    private var didEmitCancellationAcknowledgement = false
    private var userTranscriptAccumulator = ""
    private var residentTranscriptAccumulator = ""
    private var userTranscriptFinalized = false
    private var residentTranscriptFinalized = false
    private var nextOutputAudioSequenceNumber: UInt64 = 0
    private let reconnectDelay: Duration
    private(set) var connectionState = StepFunRealtimeConnectionState.closed
    private(set) var ignoredEventCount: UInt64 = 0

    init(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        codec: StepFunRealtimeCodec = StepFunRealtimeCodec(),
        reconnectDelay: Duration = .milliseconds(100)
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.codec = codec
        self.reconnectDelay = reconnectDelay
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
        guard !isCancelling else { return }
        isCancelling = true
        residentTranscriptAccumulator = ""
        residentTranscriptFinalized = false
        connectionState = .cancelling
        try await transport.send(.text(try codec.responseCancel()))
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
        nextOutputAudioSequenceNumber = 0
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
        nextOutputAudioSequenceNumber = 0
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
            let envelope = try codec.decodeEnvelope(
                frame,
                interactionID: interactionID,
                outputAudioSequenceNumber: nextOutputAudioSequenceNumber
            )
            if envelope.wireKind == .responseCreated {
                isCancelling = false
                didEmitCancellationAcknowledgement = false
                residentTranscriptAccumulator = ""
                residentTranscriptFinalized = false
            }
            if isCancelling,
               (envelope.wireKind == .cancellationAcknowledgement
                    || envelope.wireKind == .responseCompleted) {
                guard !didEmitCancellationAcknowledgement else {
                    ignoredEventCount &+= 1
                    continue
                }
                didEmitCancellationAcknowledgement = true
                residentTranscriptAccumulator = ""
                residentTranscriptFinalized = false
                connectionState = .configured
                return NativeSpeechEvent(
                    interactionID: interactionID,
                    kind: .cancelled(reason: "interrupted")
                )
            }
            if let event = normalizedEvent(
                from: envelope,
                interactionID: interactionID
            ) {
                switch event.kind {
                case .outputAudio:
                    nextOutputAudioSequenceNumber &+= 1
                    connectionState = .streaming
                case .cancelled, .responseCompleted, .failed:
                    connectionState = .configured
                default:
                    break
                }
                return event
            }
            ignoredEventCount &+= 1
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
        case .residentTranscriptDelta:
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
        case .residentTranscriptDone:
            guard !residentTranscriptFinalized,
                  case .outputText(let text, true) = event.kind else {
                return nil
            }
            residentTranscriptFinalized = true
            residentTranscriptAccumulator = text
            return event
        case .responseCreated, .responseCompleted,
             .cancellationAcknowledgement:
            return event
        case .other:
            if case .inputSpeechStarted = event.kind {
                userTranscriptAccumulator = ""
                userTranscriptFinalized = false
            }
            return event
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
}
