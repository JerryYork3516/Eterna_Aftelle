import Foundation

private actor FakeNativeSpeechProvider: NativeSpeechProvider {
    enum Operation: Sendable, Equatable {
        case start(NativeSpeechInteractionID)
        case send(NativeSpeechInteractionID)
        case receive(NativeSpeechInteractionID)
        case cancel(NativeSpeechInteractionID)
        case close(NativeSpeechInteractionID)
    }

    enum OperationKind: Sendable {
        case start
        case send
        case receive
        case cancel
        case close
    }

    private var events: [NativeSpeechEvent] = []
    private var receiveContinuation:
        CheckedContinuation<NativeSpeechEvent, any Error>?
    private var receiveStarted = false
    private var receiveStartedContinuation: CheckedContinuation<Void, Never>?
    private(set) var operations: [Operation] = []

    func start(request: NativeSpeechStartRequest) async throws {
        operations.append(.start(request.interaction.id))
    }

    func send(audio: NativeSpeechAudioPayload) async throws {
        operations.append(.send(audio.interactionID))
    }

    func receive(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEvent {
        operations.append(.receive(interactionID))
        if !events.isEmpty {
            return events.removeFirst()
        }
        receiveStarted = true
        receiveStartedContinuation?.resume()
        receiveStartedContinuation = nil
        return try await withCheckedThrowingContinuation { continuation in
            receiveContinuation = continuation
        }
    }

    func cancel(
        interactionID: NativeSpeechInteractionID,
        reason: NativeSpeechCancellationReason
    ) async throws {
        operations.append(.cancel(interactionID))
    }

    func close(interactionID: NativeSpeechInteractionID) async throws {
        operations.append(.close(interactionID))
    }

    func enqueue(_ event: NativeSpeechEvent) {
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            receiveStarted = false
            continuation.resume(returning: event)
        } else {
            events.append(event)
        }
    }

    func waitUntilReceiveStarts() async {
        guard !receiveStarted else { return }
        await withCheckedContinuation { continuation in
            receiveStartedContinuation = continuation
        }
    }

    func operationCount(_ kind: OperationKind) -> Int {
        operations.filter { operation in
            switch (kind, operation) {
            case (.start, .start),
                 (.send, .send),
                 (.receive, .receive),
                 (.cancel, .cancel),
                 (.close, .close):
                return true
            default:
                return false
            }
        }.count
    }
}

@main
@MainActor
private struct NativeSpeechRuntimeIntegrationTests {
    private static var checks = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        let fixtureData = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let provider = FakeNativeSpeechProvider()
        let sessionStore = SessionStore()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: sessionStore
        )

        do {
            _ = try await runtime.startNativeSpeechInteraction()
            fatalError("FAILED: start without resident must fail")
        } catch NativeSpeechError.unavailable {
            checks += 1
        }
        let unloadedStartCount = await provider.operationCount(.start)
        expect(
            unloadedStartCount == 0,
            "unloaded runtime performs no Provider start"
        )

        let load = runtime.loadDR(from: fixtureData)
        expect(load.isLoaded, "fixed resident loads")
        let dialogueBefore =
            (try? sessionStore.loadMostRecentDialogueEntries()) ?? []

        let first = try await runtime.startNativeSpeechInteraction()
        expect(first.lifecycleState == .active, "start activates interaction")
        expect(first.residentID == load.residentID, "interaction owns loaded resident")
        expect(first.sessionID == load.sessionID?.rawValue, "interaction owns current session")

        do {
            _ = try await runtime.startNativeSpeechInteraction()
            fatalError("FAILED: second active interaction must fail")
        } catch NativeSpeechError.invalidConfiguration {
            checks += 1
        }

        try await runtime.sendNativeSpeechAudio(
            NativeSpeechAudioPayload(
                interactionID: first.id,
                sequenceNumber: 1,
                bytes: Data([0x00, 0x01]),
                format: .pcm16
            )
        )
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: first.id,
                kind: .partialTranscript("partial")
            )
        )
        let accepted = try await runtime.receiveNativeSpeechEvent(
            interactionID: first.id
        )
        expect(
            accepted == .accepted(
                NativeSpeechEvent(
                    interactionID: first.id,
                    kind: .partialTranscript("partial")
                )
            ),
            "current event is accepted"
        )

        let blockedReceive = Task { @MainActor in
            try await runtime.receiveNativeSpeechEvent(
                interactionID: first.id
            )
        }
        await provider.waitUntilReceiveStarts()
        try await runtime.cancelActiveNativeSpeechInteraction(
            reason: .interrupted
        )
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: first.id,
                kind: .finalTranscript("late")
            )
        )
        let lateDisposition = try await blockedReceive.value
        expect(
            lateDisposition == .rejectedStale,
            "event arriving after cancel is rejected"
        )

        let cancelCountAfterFirst = await provider.operationCount(.cancel)
        let closeCountAfterFirst = await provider.operationCount(.close)
        try await runtime.cancelActiveNativeSpeechInteraction(
            reason: .interrupted
        )
        let cancelCountAfterDuplicate = await provider.operationCount(.cancel)
        let closeCountAfterDuplicate = await provider.operationCount(.close)
        expect(
            cancelCountAfterDuplicate == cancelCountAfterFirst,
            "duplicate cancel has no Provider side effect"
        )
        expect(
            closeCountAfterDuplicate == closeCountAfterFirst,
            "cancel closes Provider exactly once"
        )

        let second = try await runtime.startNativeSpeechInteraction()
        expect(second.id != first.id, "new interaction gets a new identity")
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: first.id,
                kind: .finalTranscript("old")
            )
        )
        let oldEventDisposition = try await runtime.receiveNativeSpeechEvent(
            interactionID: second.id
        )
        expect(
            oldEventDisposition == .rejectedStale,
            "old interaction event cannot enter new interaction"
        )
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: second.id,
                kind: .finalTranscript("current")
            )
        )
        let currentEvent = try await runtime.receiveNativeSpeechEvent(
            interactionID: second.id
        )
        expect(
            currentEvent == .accepted(
                NativeSpeechEvent(
                    interactionID: second.id,
                    kind: .finalTranscript("current")
                )
            ),
            "new interaction event is accepted"
        )

        let closeCountBeforeTerminal = await provider.operationCount(.close)
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: second.id,
                kind: .closed
            )
        )
        let terminalEvent = try await runtime.receiveNativeSpeechEvent(
            interactionID: second.id
        )
        expect(
            terminalEvent == .accepted(
                NativeSpeechEvent(
                    interactionID: second.id,
                    kind: .closed
                )
            ),
            "terminal event is accepted once"
        )
        let closeCountAfterTerminal = await provider.operationCount(.close)
        expect(
            closeCountAfterTerminal - closeCountBeforeTerminal == 1,
            "terminal event closes Provider once"
        )

        let sessionBound = try await runtime.startNativeSpeechInteraction()
        let reload = runtime.loadDR(from: fixtureData)
        expect(reload.sessionID != load.sessionID, "reload creates a new session")
        expect(
            runtime.nativeSpeechDisposition(
                for: NativeSpeechEvent(
                    interactionID: sessionBound.id,
                    kind: .partialTranscript("stale session")
                ),
                expectedInteractionID: sessionBound.id
            ) == .rejectedStale,
            "old session event is rejected"
        )

        _ = try await runtime.startNativeSpeechInteraction()
        let closeCountBeforeThird = await provider.operationCount(.close)
        try await runtime.closeActiveNativeSpeechInteraction()
        try await runtime.closeActiveNativeSpeechInteraction()
        let closeCountAfterThird = await provider.operationCount(.close)
        expect(
            closeCountAfterThird - closeCountBeforeThird == 1,
            "explicit close is idempotent"
        )

        let dialogueAfter =
            (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
        expect(
            dialogueAfter == dialogueBefore,
            "native speech events do not write dialogue session data"
        )

        let operations = await provider.operations
        expect(
            operations.contains(.send(first.id)),
            "audio reaches Provider through Runtime chain"
        )
        expect(
            operations.contains(.cancel(first.id)),
            "cancel reaches Provider through Runtime chain"
        )
        print("native_speech_runtime_integration_checks=\(checks)")
    }

    private static func configuredRuntime(
        provider: NativeSpeechProvider,
        sessionStore: SessionStore
    ) -> RuntimeCore {
        let router = ProviderRouter(
            credentialReader: UnavailableProviderCredentialReader(),
            nativeSpeechProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: sessionStore
        )
        let profile = NativeSpeechProviderProfile(
            profileID: "stage7_5_stepfun_realtime_primary",
            providerID: "StepFun",
            capability: "native_speech",
            adapterID: "stepfun_realtime",
            modelID: "stepaudio-2.5-realtime",
            voiceID: "linjiajiejie",
            endpoint: URL(
                string: "wss://api.stepfun.com/v1/realtime?model=stepaudio-2.5-realtime"
            )!,
            transport: "websocket",
            inputAudioFormat: .pcm16,
            outputAudioFormat: .pcm16,
            turnDetection: NativeSpeechTurnDetection(
                type: .serverVAD,
                prefixPaddingMilliseconds: 500
            ),
            languageMetadata: "zh-CN",
            keyRef: "keychain://com.eterna.aftelle.provider.stepfun/stepfun_realtime_api_key"
        )
        expect(
            runtime.configureNativeSpeechProvider(profile: profile) == nil,
            "native speech profile configures"
        )
        return runtime
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
