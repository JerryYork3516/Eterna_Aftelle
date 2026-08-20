import Foundation

nonisolated private struct R6CredentialReader: ProviderCredentialReading {
    let storedValue: String?

    func readCredential(for keyRef: String) throws -> String? {
        keyRef == "keychain://test/r6-qwen" ? storedValue : nil
    }
}

private actor R6FakeRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    private var connectedEndpoints: [URL] = []
    private var sentFrames: [RealtimeWebSocketFrame] = []
    private var queuedFrames: [RealtimeWebSocketFrame] = []
    private var receiveWaiter:
        CheckedContinuation<RealtimeWebSocketFrame, any Error>?
    private var isConnected = false

    func connect(endpoint: URL, bearerToken: String) async throws {
        guard !isConnected else {
            throw RealtimeResidentBrainError.operationInFlight
        }
        isConnected = true
        connectedEndpoints.append(endpoint)
        enqueue(.text(
            #"{"type":"session.created","session":{"id":"r6-session"}}"#
        ))
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        guard isConnected else {
            throw RealtimeResidentBrainError.transportFailure
        }
        sentFrames.append(frame)
        guard case .text(let text) = frame,
              let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let type = object["type"] as? String else {
            return
        }
        switch type {
        case "session.update":
            enqueue(.text(
                #"{"type":"session.updated","session":{"id":"r6-session"}}"#
            ))
        case "input_audio_buffer.clear":
            enqueue(.text(#"{"type":"input_audio_buffer.cleared"}"#))
        default:
            break
        }
    }

    func receive() async throws -> RealtimeWebSocketFrame {
        guard isConnected else {
            throw RealtimeResidentBrainError.transportFailure
        }
        if !queuedFrames.isEmpty {
            return queuedFrames.removeFirst()
        }
        guard receiveWaiter == nil else {
            throw RealtimeResidentBrainError.operationInFlight
        }
        return try await withCheckedThrowingContinuation { continuation in
            receiveWaiter = continuation
        }
    }

    func close(reason: RealtimeWebSocketCloseReason) async {
        isConnected = false
        queuedFrames.removeAll(keepingCapacity: true)
        if let receiveWaiter {
            self.receiveWaiter = nil
            receiveWaiter.resume(
                throwing: RealtimeResidentBrainError.cancelled
            )
        }
    }

    func sentTexts() -> [String] {
        sentFrames.compactMap { frame in
            guard case .text(let text) = frame else { return nil }
            return text
        }
    }

    func connectCount() -> Int {
        connectedEndpoints.count
    }

    private func enqueue(_ frame: RealtimeWebSocketFrame) {
        if let receiveWaiter {
            self.receiveWaiter = nil
            receiveWaiter.resume(returning: frame)
        } else {
            queuedFrames.append(frame)
        }
    }
}

private actor R6RuntimeProvider: RealtimeResidentBrainProvider {
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var contextUpdates: [RealtimeBrainRuntimeContextUpdate] = []
    private var events: [RealtimeResidentBrainEvent] = []
    private var closeCommands: [RealtimeBrainCloseSessionCommand] = []

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        openCommands.append(command)
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {
        contextUpdates.append(update)
    }

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {}

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {}

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {}

    func interrupt(
        _ command: RealtimeBrainInterruptCommand
    ) async throws {}

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        guard !events.isEmpty else {
            throw RealtimeResidentBrainError.unavailable
        }
        return events.removeFirst()
    }

    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws {
        closeCommands.append(command)
    }

    func enqueue(_ event: RealtimeResidentBrainEvent) {
        events.append(event)
    }

    func recordedOpenCommands() -> [RealtimeBrainOpenSessionCommand] {
        openCommands
    }

    func openCount() -> Int {
        openCommands.count
    }

    func contextCount() -> Int {
        contextUpdates.count
    }

    func closeCount() -> Int {
        closeCommands.count
    }
}

private struct R6QwenStack {
    let adapter: QwenRealtimeResidentBrainAdapter
    let transport: R6FakeRealtimeWebSocketTransport
}

private struct R6RuntimeStack {
    let runtime: RuntimeCore
    let provider: R6RuntimeProvider
    let sessionStore: SessionStore
}

@main
@MainActor
private struct RealtimeVoiceBindingTests {
    private static let providerDefaultVoice = "R6PrivateDefaultVoice"
    private static var cases = 0
    private static var checks = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        testDefaultBindingAndDeterminism()
        try await testRuntimeOpenUsesCurrentLease(fixture: fixture)
        try await testIdentityAndProviderFences()
        try await testUnsupportedBindingFallback()
        try await testQwenPrivateDefaultAndGenerationFence()
        try await testSemanticIntegrityAndSingleBrain(fixture: fixture)

        print("realtime_voice_binding_cases=\(cases)")
        print("realtime_voice_binding_checks=\(checks)")
        print("realtime_voice_binding_network_dependency=ZERO")
    }

    private static func testDefaultBindingAndDeterminism() {
        cases += 1
        let identity = sessionIdentity(generation: 1)
        let first = RuntimeVoiceBinding.providerDefault(identity: identity)
        let second = RuntimeVoiceBinding.providerDefault(identity: identity)

        expect(first == second, "default binding is deterministic")
        expect(first.identity == identity, "binding keeps full session identity")
        expect(
            first.providerIdentity == .activeRealtimeProvider,
            "binding identifies only the selected neutral Realtime Provider"
        )
        expect(first.mode == .providerDefault, "default mode is explicit")
        expect(first.voiceProfileID == nil, "default has no Studio profile")
        expect(
            first.providerPrivateVoiceReference == nil,
            "default public binding has no Provider voice reference"
        )
        expect(
            first.fallback == .providerDefault,
            "default fallback is explicit"
        )

        let command = RealtimeBrainOpenSessionCommand(identity: identity)
        expect(
            command.voiceBinding == first,
            "every open command carries the deterministic default binding"
        )
        assertGenerationRebind()
    }

    private static func testRuntimeOpenUsesCurrentLease(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = runtimeStack(fixture: fixture)
        let identity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )
        let commands = await stack.provider.recordedOpenCommands()
        guard let command = commands.first else {
            fatalError("Runtime did not forward an open command")
        }

        expect(commands.count == 1, "Runtime opens exactly one Realtime Brain")
        expect(command.identity == identity, "Provider receives Runtime identity")
        expect(
            command.voiceBinding
                == RuntimeVoiceBinding.providerDefault(identity: identity),
            "Runtime creates the default binding after lease admission"
        )
        guard let lease = stack.runtime.activeBrainLeaseForTesting() else {
            fatalError("Runtime lease missing after open")
        }
        expect(
            lease.route == .realtimeResidentBrain,
            "Voice Binding does not create a second Brain route"
        )
        expect(
            lease.brainLeaseID == identity.brainLeaseID
                && lease.routeEpoch == identity.routeEpoch
                && lease.generation
                    == .realtimeResidentBrain(identity.generation),
            "binding identity reuses the current lease fence"
        )
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: identity
            ),
            "Runtime closes the bound session"
        )
        let closeCount = await stack.provider.closeCount()
        expect(closeCount == 1, "Provider closes once")
    }

    private static func testIdentityAndProviderFences() async throws {
        cases += 1
        let identity = sessionIdentity(generation: 7)
        let mismatches = [
            copyIdentity(identity, residentID: "other-resident"),
            copyIdentity(identity, runtimeSessionID: "other-session"),
            copyIdentity(identity, brainLeaseID: UUID()),
            copyIdentity(identity, routeEpoch: identity.routeEpoch + 1),
            copyIdentity(identity, generation: identity.generation - 1)
        ]

        for mismatch in mismatches {
            let stack = try makeQwenStack()
            let binding = RuntimeVoiceBinding.providerDefault(
                identity: mismatch
            )
            await expectError(.invalidIdentity) {
                try await stack.adapter.openSession(
                    RealtimeBrainOpenSessionCommand(
                        identity: identity,
                        voiceBinding: binding
                    )
                )
            }
            let connectCount = await stack.transport.connectCount()
            expect(
                connectCount == 0,
                "identity mismatch rejects before Provider connection"
            )
        }

        let providerMismatch = RuntimeVoiceBinding(
            identity: identity,
            providerIdentity: RuntimeVoiceProviderIdentity(
                rawValue: "different-realtime-provider"
            ),
            mode: .providerDefault,
            voiceProfileID: nil,
            providerPrivateVoiceReference: nil,
            fallback: .providerDefault
        )
        let providerStack = try makeQwenStack()
        await expectError(.voiceBindingUnavailable) {
            try await providerStack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(
                    identity: identity,
                    voiceBinding: providerMismatch
                )
            )
        }
        let providerMismatchConnectCount = await providerStack.transport
            .connectCount()
        expect(
            providerMismatchConnectCount == 0,
            "Provider identity mismatch fails before connection"
        )
    }

    private static func testUnsupportedBindingFallback() async throws {
        cases += 1
        let identity = sessionIdentity(generation: 11)
        let unsupportedModes: [RuntimeVoiceBindingMode] = [
            .providerBuiltIn,
            .providerCustom,
            .providerCloned
        ]

        for (offset, mode) in unsupportedModes.enumerated() {
            let stack = try makeQwenStack()
            let binding = RuntimeVoiceBinding(
                identity: identity,
                providerIdentity: .activeRealtimeProvider,
                mode: mode,
                voiceProfileID: "future-studio-profile-\(offset)",
                providerPrivateVoiceReference:
                    mode == .providerBuiltIn ? "unavailable-private-ref" : nil,
                fallback: .providerDefault
            )
            try await stack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(
                    identity: identity,
                    voiceBinding: binding
                )
            )
            let resolvedVoice = try await firstWireVoice(stack.transport)
            expect(
                resolvedVoice == providerDefaultVoice,
                "unsupported binding safely resolves to Provider default"
            )
            try await stack.adapter.closeSession(
                RealtimeBrainCloseSessionCommand(identity: identity)
            )
        }

        let failClosedStack = try makeQwenStack()
        let failClosed = RuntimeVoiceBinding(
            identity: identity,
            providerIdentity: .activeRealtimeProvider,
            mode: .providerCustom,
            voiceProfileID: "future-studio-profile",
            providerPrivateVoiceReference: nil,
            fallback: .failClosed
        )
        await expectError(.voiceBindingUnavailable) {
            try await failClosedStack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(
                    identity: identity,
                    voiceBinding: failClosed
                )
            )
        }
        let failClosedConnectCount = await failClosedStack.transport
            .connectCount()
        expect(
            failClosedConnectCount == 0,
            "failClosed binding performs no Provider connection"
        )
        try await failClosedStack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(identity: identity)
        )
        let recoveredFailClosedVoice = try await firstWireVoice(
            failClosedStack.transport
        )
        expect(
            recoveredFailClosedVoice == providerDefaultVoice,
            "failClosed attempt leaves Adapter available for valid default"
        )
        try await failClosedStack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )

        let pollutedDefaultStack = try makeQwenStack()
        let pollutedDefault = RuntimeVoiceBinding(
            identity: identity,
            providerIdentity: .activeRealtimeProvider,
            mode: .providerDefault,
            voiceProfileID: "not-allowed-for-default",
            providerPrivateVoiceReference: nil,
            fallback: .providerDefault
        )
        await expectError(.voiceBindingUnavailable) {
            try await pollutedDefaultStack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(
                    identity: identity,
                    voiceBinding: pollutedDefault
                )
            )
        }
        let pollutedDefaultConnectCount = await pollutedDefaultStack.transport
            .connectCount()
        expect(
            pollutedDefaultConnectCount == 0,
            "default binding rejects a fabricated resident voice profile"
        )
        try await pollutedDefaultStack.adapter.openSession(
            RealtimeBrainOpenSessionCommand(identity: identity)
        )
        let recoveredInvalidVoice = try await firstWireVoice(
            pollutedDefaultStack.transport
        )
        expect(
            recoveredInvalidVoice == providerDefaultVoice,
            "invalid binding leaves Adapter available for valid default"
        )
        try await pollutedDefaultStack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: identity)
        )
        try await assertInvalidProviderDefaultFailsClosed()
    }

    private static func testQwenPrivateDefaultAndGenerationFence()
        async throws {
        cases += 1
        let stack = try makeQwenStack()
        let identity = sessionIdentity(generation: 20)
        let command = RealtimeBrainOpenSessionCommand(identity: identity)

        expect(
            command.voiceBinding.providerPrivateVoiceReference == nil,
            "Qwen private default is absent from the open contract"
        )
        try await stack.adapter.openSession(command)
        let initialVoice = try await firstWireVoice(stack.transport)
        expect(
            initialVoice == providerDefaultVoice,
            "Qwen resolves its private default only at the Adapter edge"
        )
        try await stack.adapter.updateRuntimeContext(
            RealtimeBrainRuntimeContextUpdate(
                identity: identity,
                kind: .bootstrap,
                contextRevision: 1,
                sections: [RealtimeBrainContextSection(
                    scope: .stableResident,
                    content: "R6 generation fixture"
                )]
            )
        )
        let ready = try await stack.adapter.receiveEvent(session: identity)
        expect(ready.kind == .sessionReady, "Qwen binding session activates")

        let nextGeneration = identity.generation + 1
        try await stack.adapter.cancelGeneration(
            RealtimeBrainCancelGenerationCommand(
                identity: identity,
                nextGeneration: nextGeneration,
                reason: .superseded
            )
        )
        let nextIdentity = copyIdentity(
            identity,
            generation: nextGeneration
        )
        let voiceUpdates = try await wireVoices(stack.transport)
        expect(
            voiceUpdates == [providerDefaultVoice, providerDefaultVoice],
            "generation reconnect deterministically reuses the resolved default"
        )
        await expectError(.invalidIdentity) {
            _ = try await stack.adapter.receiveEvent(session: identity)
        }
        let cancellation = try await stack.adapter.receiveEvent(
            session: nextIdentity
        )
        expect(
            cancellation.identity.session == nextIdentity
                && cancellation.kind == .cancelled(.superseded),
            "only the rebound generation can receive current output"
        )
        try await stack.adapter.closeSession(
            RealtimeBrainCloseSessionCommand(identity: nextIdentity)
        )
    }

    private static func assertInvalidProviderDefaultFailsClosed()
        async throws {
        let stack = try makeQwenStack(defaultVoiceID: "  \n  ")
        let identity = sessionIdentity(generation: 31)
        await expectError(.voiceBindingUnavailable) {
            try await stack.adapter.openSession(
                RealtimeBrainOpenSessionCommand(identity: identity)
            )
        }
        let connectCount = await stack.transport.connectCount()
        expect(
            connectCount == 0,
            "invalid Provider default fails before any connection"
        )
    }

    private static func assertGenerationRebind() {
        let identity = sessionIdentity(generation: 40)
        let binding = RuntimeVoiceBinding(
            identity: identity,
            providerIdentity: .activeRealtimeProvider,
            mode: .providerCustom,
            voiceProfileID: "future-profile",
            providerPrivateVoiceReference: "provider-private-reference",
            fallback: .providerDefault
        )
        let next = copyIdentity(identity, generation: 41)
        guard let rebound = binding.rebound(to: next) else {
            fatalError("valid generation did not rebind")
        }
        expect(rebound.identity == next, "rebind advances only the identity")
        expect(rebound.mode == binding.mode, "rebind preserves binding mode")
        expect(
            rebound.voiceProfileID == binding.voiceProfileID,
            "rebind preserves future Studio profile identity"
        )
        expect(
            rebound.providerPrivateVoiceReference
                == binding.providerPrivateVoiceReference,
            "rebind preserves private resolution state"
        )
        expect(
            binding.rebound(to: identity) == nil,
            "same generation cannot rebind"
        )
        expect(
            binding.rebound(to: copyIdentity(
                identity,
                routeEpoch: identity.routeEpoch + 1,
                generation: 41
            )) == nil,
            "stale routeEpoch cannot rebind"
        )
        expect(
            binding.rebound(to: copyIdentity(
                identity,
                brainLeaseID: UUID(),
                generation: 41
            )) == nil,
            "old lease cannot rebind"
        )
    }

    private static func testSemanticIntegrityAndSingleBrain(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = runtimeStack(fixture: fixture)
        let identity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )
        expectRealtimeSuccess(
            await stack.runtime.updateRealtimeResidentBrainContext(
                RealtimeBrainRuntimeContextUpdate(
                    identity: identity,
                    kind: .bootstrap,
                    contextRevision: 1,
                    sections: [RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "R6 stable resident context"
                    )]
                )
            ),
            "semantic fixture bootstraps"
        )
        let contextCount = await stack.provider.contextCount()
        expect(
            contextCount == 1,
            "Voice Binding creates no second Runtime context"
        )

        let readyIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: nil,
            responseID: nil,
            contextRevision: 1
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: readyIdentity,
            sequence: 1,
            kind: .sessionReady
        ))
        _ = try await stack.runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )

        let turnID = RealtimeBrainTurnID()
        let responseID = RealtimeBrainResponseID()
        let userIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: nil,
            contextRevision: 1
        )
        let responseIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: responseID,
            contextRevision: 1
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 2,
            kind: .userTranscriptFinal("Hello resident")
        ))
        _ = try await stack.runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        let canonical = "Canonical meaning remains byte-for-byte unchanged."
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: responseIdentity,
            sequence: 3,
            kind: .residentTextFinal(canonical)
        ))
        _ = try await stack.runtime.receiveRealtimeResidentBrainEvent(
            session: identity
        )
        let semanticEvent = RealtimeResidentBrainEvent(
            identity: responseIdentity,
            sequence: 4,
            kind: .residentSemanticFinal(
                RealtimeBrainSemanticOutput(canonicalText: canonical)
            )
        )
        await stack.provider.enqueue(semanticEvent)
        let disposition = try await stack.runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        guard case .accepted(let accepted) = disposition,
              case .residentSemanticFinal(let semantic) = accepted.kind else {
            fatalError("semantic final was not accepted")
        }
        expect(
            semantic.canonicalText == canonical,
            "Voice Binding never rewrites residentSemanticFinal"
        )

        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: responseIdentity,
            sequence: 5,
            kind: .residentSemanticFinal(
                RealtimeBrainSemanticOutput(canonicalText: canonical)
            )
        ))
        let duplicateDisposition = try await stack.runtime
            .receiveRealtimeResidentBrainEvent(session: identity)
        expect(
            duplicateDisposition == .rejectedInvalidEvent,
            "one response accepts one canonical semantic final"
        )
        let dialogueEntries = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let residentEntries = dialogueEntries.filter { entry in
            entry.role == "resident"
        }
        expect(
            residentEntries.count == 1,
            "CanonicalResidentTurn persists exactly one resident entry"
        )
        expect(
            residentEntries.first?.text == canonical,
            "History preserves resident semantic content byte-for-byte"
        )
        let openCount = await stack.provider.openCount()
        expect(
            openCount == 1,
            "semantic delivery still uses exactly one Brain"
        )
        expect(
            stack.runtime.activeBrainLeaseForTesting()?.route
                == .realtimeResidentBrain,
            "Voice Binding owns no second Runtime lease"
        )
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: identity
            ),
            "semantic fixture closes"
        )
    }

    private static func runtimeStack(fixture: Data) -> R6RuntimeStack {
        let provider = R6RuntimeProvider()
        let sessionStore = SessionStore()
        let router = ProviderRouter(
            credentialReader: R6CredentialReader(storedValue: nil),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: sessionStore
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "resident fixture loads")
        return R6RuntimeStack(
            runtime: runtime,
            provider: provider,
            sessionStore: sessionStore
        )
    }

    private static func makeQwenStack(
        defaultVoiceID: String = providerDefaultVoice
    ) throws -> R6QwenStack {
        let storedValue = try QwenRealtimeCredential(
            workspaceID: "fixture-workspace",
            secret: "fixture-secret"
        ).storedValue()
        let transport = R6FakeRealtimeWebSocketTransport()
        let adapter = QwenRealtimeResidentBrainAdapter(
            credentialReader: R6CredentialReader(storedValue: storedValue),
            transport: transport,
            configuration: QwenRealtimeResidentBrainConfiguration(
                endpoint: URL(
                    string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-plus-realtime"
                )!,
                keyRef: "keychain://test/r6-qwen",
                defaultProviderVoiceID: defaultVoiceID,
                acknowledgementTimeout: .seconds(1)
            )
        )
        return R6QwenStack(adapter: adapter, transport: transport)
    }

    private static func firstWireVoice(
        _ transport: R6FakeRealtimeWebSocketTransport
    ) async throws -> String? {
        try await wireVoices(transport).first
    }

    private static func wireVoices(
        _ transport: R6FakeRealtimeWebSocketTransport
    ) async throws -> [String] {
        try await transport.sentTexts().compactMap { text in
            guard let data = text.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  object["type"] as? String == "session.update",
                  let session = object["session"] as? [String: Any] else {
                return nil
            }
            return session["voice"] as? String
        }
    }

    private static func sessionIdentity(
        generation: UInt64
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: "resident-r6",
            runtimeSessionID: "runtime-session-r6",
            brainLeaseID: UUID(
                uuidString: "66000000-0000-0000-0000-000000000006"
            )!,
            routeEpoch: 6,
            generation: generation
        )
    }

    private static func copyIdentity(
        _ identity: RealtimeBrainSessionIdentity,
        residentID: String? = nil,
        runtimeSessionID: String? = nil,
        brainLeaseID: UUID? = nil,
        routeEpoch: UInt64? = nil,
        generation: UInt64? = nil
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: residentID ?? identity.residentID,
            runtimeSessionID: runtimeSessionID ?? identity.runtimeSessionID,
            brainLeaseID: brainLeaseID ?? identity.brainLeaseID,
            routeEpoch: routeEpoch ?? identity.routeEpoch,
            generation: generation ?? identity.generation
        )
    }

    private static func realtimeIdentity(
        _ result: Result<
            RealtimeBrainSessionIdentity,
            RealtimeResidentBrainError
        >
    ) throws -> RealtimeBrainSessionIdentity {
        switch result {
        case .success(let identity):
            return identity
        case .failure(let error):
            throw error
        }
    }

    private static func expectRealtimeSuccess(
        _ result: Result<Void, RealtimeResidentBrainError>,
        _ message: String
    ) {
        switch result {
        case .success:
            expect(true, message)
        case .failure(let error):
            fatalError("FAILED: \(message): \(error)")
        }
    }

    private static func expectError(
        _ expected: RealtimeResidentBrainError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            fatalError("FAILED: expected \(expected)")
        } catch let error as RealtimeResidentBrainError {
            expect(error == expected, "expected \(expected), got \(error)")
        } catch {
            fatalError("FAILED: unexpected error \(error)")
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
