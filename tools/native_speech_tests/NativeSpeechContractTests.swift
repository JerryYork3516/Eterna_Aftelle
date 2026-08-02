import Foundation

private actor ContractProvider: NativeSpeechProvider {
    private var events: [NativeSpeechEvent] = []

    func start(request: NativeSpeechStartRequest) async throws {
        events.append(
            NativeSpeechEvent(
                interactionID: request.interaction.id,
                kind: .connected
            )
        )
    }

    func send(audio: NativeSpeechAudioPayload) async throws {
        events.append(
            NativeSpeechEvent(
                interactionID: audio.interactionID,
                kind: .outputAudio(audio)
            )
        )
    }

    func receive(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEvent {
        guard !events.isEmpty else {
            throw NativeSpeechError.invalidEvent
        }
        let event = events.removeFirst()
        guard event.interactionID == interactionID else {
            throw NativeSpeechError.interactionMismatch
        }
        return event
    }

    func cancel(
        interactionID: NativeSpeechInteractionID,
        reason: NativeSpeechCancellationReason
    ) async throws {
        events.append(
            NativeSpeechEvent(
                interactionID: interactionID,
                kind: .cancelled(reason: reason.rawValue)
            )
        )
    }

    func close(interactionID: NativeSpeechInteractionID) async throws {
        events.append(
            NativeSpeechEvent(
                interactionID: interactionID,
                kind: .closed
            )
        )
    }
}

@main
@MainActor
private struct NativeSpeechContractTests {
    private static var checks = 0

    static func main() async throws {
        let profile = try validProfile()
        let interactionID = NativeSpeechInteractionID(
            rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let interaction = NativeSpeechInteraction(
            id: interactionID,
            residentID: "resident",
            sessionID: "session",
            providerProfileID: profile.profileID
        )
        let payload = NativeSpeechAudioPayload(
            interactionID: interactionID,
            sequenceNumber: 42,
            bytes: Data([0x01, 0x02]),
            format: .pcm16
        )

        expect(interaction.lifecycleState == .starting, "interaction starts in starting state")
        expect(payload.sequenceNumber == 42, "audio sequence remains unchanged")
        expect(payload.bytes == Data([0x01, 0x02]), "audio bytes remain unchanged")

        let event = NativeSpeechEvent(
            interactionID: interactionID,
            kind: .partialTranscript("hello")
        )
        expect(event.interactionID == interactionID, "event carries interaction identity")

        let provider = ContractProvider()
        try await provider.start(
            request: NativeSpeechStartRequest(
                interaction: interaction,
                profile: profile
            )
        )
        let connectedEvent = try await provider.receive(
            interactionID: interactionID
        )
        expect(
            connectedEvent.kind == .connected,
            "contract can be implemented by an actor"
        )
        try await provider.send(audio: payload)
        let audioEvent = try await provider.receive(
            interactionID: interactionID
        )
        expect(
            audioEvent.kind == .outputAudio(payload),
            "provider accepts platform-neutral audio payload"
        )
        try await provider.cancel(
            interactionID: interactionID,
            reason: .interrupted
        )
        let cancelledEvent = try await provider.receive(
            interactionID: interactionID
        )
        expect(
            cancelledEvent.kind == .cancelled(reason: "interrupted"),
            "provider exposes explicit cancellation"
        )
        try await provider.close(interactionID: interactionID)
        let closedEvent = try await provider.receive(
            interactionID: interactionID
        )
        expect(
            closedEvent.kind == .closed,
            "provider exposes explicit close"
        )

        try expectInvalid(profileWith: ["profileID": ""])
        try expectInvalid(profileWith: ["endpoint": "https://example.invalid"])
        try expectInvalid(profileWith: ["keyRef": "plain-secret"])

        print("native_speech_contract_checks=\(checks)")
    }

    private static func validProfile(
        overrides: [String: String] = [:]
    ) throws -> NativeSpeechProviderProfile {
        let endpoint = URL(
            string: overrides["endpoint"] ?? "wss://example.invalid/realtime"
        )!
        let profile = NativeSpeechProviderProfile(
            profileID: overrides["profileID"] ?? "profile",
            providerID: "provider",
            capability: "native_speech",
            adapterID: "adapter",
            modelID: "model",
            voiceID: "voice",
            endpoint: endpoint,
            transport: "websocket",
            inputAudioFormat: .pcm16,
            outputAudioFormat: .pcm16,
            turnDetection: NativeSpeechTurnDetection(
                type: .serverVAD,
                prefixPaddingMilliseconds: 500
            ),
            languageMetadata: "zh-CN",
            keyRef: overrides["keyRef"] ?? "keychain://service/account"
        )
        try profile.validate()
        return profile
    }

    private static func expectInvalid(profileWith overrides: [String: String]) throws {
        do {
            _ = try validProfile(overrides: overrides)
            fatalError("Expected invalid profile: \(overrides.keys.sorted())")
        } catch NativeSpeechError.invalidConfiguration {
            checks += 1
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError("FAILED: \(message)")
        }
        checks += 1
    }
}
