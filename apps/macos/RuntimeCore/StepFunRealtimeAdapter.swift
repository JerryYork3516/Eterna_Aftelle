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

actor StepFunRealtimeAdapter: NativeSpeechProvider {
    private let credentialReader: ProviderCredentialReading
    private let transport: RealtimeWebSocketTransport
    private let codec: StepFunRealtimeCodec
    private var activeInteractionID: NativeSpeechInteractionID?
    private var pendingEvents: [NativeSpeechEvent] = []
    private var isCancelling = false
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
        guard activeInteractionID == nil else {
            throw NativeSpeechError.invalidConfiguration
        }
        try request.profile.validate()
        guard request.interaction.providerProfileID == request.profile.profileID else {
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
        connectionState = .cancelling
        try await transport.send(.text(try codec.responseCancel()))
    }

    func close(interactionID: NativeSpeechInteractionID) async throws {
        guard activeInteractionID == interactionID else {
            if activeInteractionID == nil { return }
            throw NativeSpeechError.interactionMismatch
        }
        connectionState = .closing
        resetConnection()
        await transport.close(reason: .normal)
        connectionState = .closed
    }

    private func connectAndConfigure(
        request: NativeSpeechStartRequest,
        credential: String
    ) async throws {
        connectionState = .connecting
        try await transport.connect(
            endpoint: request.profile.endpoint,
            bearerToken: credential
        )
        activeInteractionID = request.interaction.id
        isCancelling = false
        nextOutputAudioSequenceNumber = 0

        let created = try await nextRecognizedEvent(
            interactionID: request.interaction.id
        )
        guard created.kind == .connected else {
            throw NativeSpeechError.invalidEvent
        }
        connectionState = .connected
        try await transport.send(
            .text(try codec.sessionUpdate(profile: request.profile))
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
        activeInteractionID = nil
        pendingEvents.removeAll()
        isCancelling = false
        nextOutputAudioSequenceNumber = 0
    }

    private func requireActive(_ interactionID: NativeSpeechInteractionID) throws {
        guard activeInteractionID == interactionID else {
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
            if let event = try codec.decode(
                frame,
                interactionID: interactionID,
                outputAudioSequenceNumber: nextOutputAudioSequenceNumber
            ) {
                if case .outputAudio = event.kind {
                    nextOutputAudioSequenceNumber &+= 1
                    connectionState = .streaming
                }
                return event
            }
            ignoredEventCount &+= 1
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
