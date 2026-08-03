import Foundation

actor StepFunRealtimeAdapter: NativeSpeechProvider {
    private let credentialReader: ProviderCredentialReading
    private let transport: RealtimeWebSocketTransport
    private let codec: StepFunRealtimeCodec
    private var activeInteractionID: NativeSpeechInteractionID?
    private var pendingEvents: [NativeSpeechEvent] = []
    private var isCancelling = false

    init(
        credentialReader: ProviderCredentialReading,
        transport: RealtimeWebSocketTransport,
        codec: StepFunRealtimeCodec = StepFunRealtimeCodec()
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.codec = codec
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

        try await transport.connect(
            endpoint: request.profile.endpoint,
            bearerToken: credential
        )
        activeInteractionID = request.interaction.id
        isCancelling = false

        do {
            let created = try await nextRecognizedEvent(
                interactionID: request.interaction.id
            )
            guard created.kind == .connected else {
                throw NativeSpeechError.invalidEvent
            }
            try await transport.send(
                .text(try codec.sessionUpdate(profile: request.profile))
            )
            let updated = try await nextRecognizedEvent(
                interactionID: request.interaction.id
            )
            guard updated.kind == .sessionUpdated else {
                throw NativeSpeechError.invalidEvent
            }
            pendingEvents = [created, updated]
        } catch {
            activeInteractionID = nil
            await transport.close(reason: .cancelled)
            throw error
        }
    }

    func send(audio: NativeSpeechAudioPayload) async throws {
        try requireActive(audio.interactionID)
        try await transport.send(.text(try codec.audioAppend(audio)))
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
        try await transport.send(.text(try codec.responseCancel()))
    }

    func close(interactionID: NativeSpeechInteractionID) async throws {
        guard activeInteractionID == interactionID else {
            if activeInteractionID == nil { return }
            throw NativeSpeechError.interactionMismatch
        }
        activeInteractionID = nil
        pendingEvents.removeAll()
        isCancelling = false
        await transport.close(reason: .normal)
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
                interactionID: interactionID
            ) {
                return event
            }
        }
    }
}
