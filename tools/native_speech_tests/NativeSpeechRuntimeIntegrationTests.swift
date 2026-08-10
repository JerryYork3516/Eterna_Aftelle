import Foundation

private actor FakeNativeSpeechProvider:
    NativeSpeechProvider,
    RealtimeSpeechContextProviding {
    enum Operation: Sendable, Equatable {
        case start(NativeSpeechInteractionID)
        case updateContext(NativeSpeechInteractionID, String)
        case send(NativeSpeechInteractionID)
        case receive(NativeSpeechInteractionID)
        case cancel(NativeSpeechInteractionID)
        case close(NativeSpeechInteractionID)
    }

    enum OperationKind: Sendable {
        case start
        case updateContext
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
    private(set) var startedProjections: [RealtimeSpeechContextProjection] = []
    private(set) var updatedProjections: [RealtimeSpeechContextProjection] = []
    private var preparedProjection: RealtimeSpeechContextProjection?
    private let emitsHandshakeOnStart: Bool

    init(emitsHandshakeOnStart: Bool = false) {
        self.emitsHandshakeOnStart = emitsHandshakeOnStart
    }

    func start(request: NativeSpeechStartRequest) async throws {
        operations.append(.start(request.interaction.id))
        guard let preparedProjection,
              preparedProjection.isBound(to: request.interaction) else {
            throw NativeSpeechError.interactionMismatch
        }
        self.preparedProjection = nil
        startedProjections.append(preparedProjection)
        if emitsHandshakeOnStart {
            events.append(
                NativeSpeechEvent(
                    interactionID: request.interaction.id,
                    kind: .connected
                )
            )
            events.append(
                NativeSpeechEvent(
                    interactionID: request.interaction.id,
                    kind: .sessionUpdated
                )
            )
        }
    }

    func prepareContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws {
        preparedProjection = projection
    }

    func updateContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws {
        operations.append(
            .updateContext(
                projection.interactionID,
                projection.compilationVersion
            )
        )
        updatedProjections.append(projection)
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
                 (.updateContext, .updateContext),
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
        guard let dynamicInput = runtime
            .compileResidentDialogueContext(currentUserInput: "")?
            .identity.domainFocus.first else {
            fatalError("FAILED: fixed resident needs a domain focus")
        }
        let probeInteraction = NativeSpeechInteraction(
            residentID: load.residentID,
            sessionID: load.sessionID!.rawValue,
            providerProfileID: nativeSpeechProfile().profileID
        )
        let dynamicContext = runtime.compileResidentDialogueContext(
            currentUserInput: dynamicInput
        )!
        let dynamicProbe = try RealtimeSpeechContextCompiler().compile(
            context: dynamicContext,
            interaction: probeInteraction,
            refreshReason: .finalTranscript
        )
        print(
            "native_speech_context_probe="
                + "untrimmed:\(dynamicProbe.budget.untrimmedUTF8Bytes),"
                + "final:\(dynamicProbe.budget.finalUTF8Bytes),"
                + "removed:\(dynamicProbe.budget.removedSectionIDs.count)"
        )
        let dialogueBefore =
            (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
        let staleMemoryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staleMemoryDirectory) }
        let staleMemoryStore = NarrativeMemoryStore(
            baseURL: staleMemoryDirectory
        )
        try staleMemoryStore.save(RuntimeNarrativeMemoryStoreSnapshot(
            residentID: load.residentID,
            records: [RuntimeNarrativeMemoryRecord(
                memoryID: "stale-final-memory",
                residentID: load.residentID,
                type: .confirmedPlan,
                summary: "迟到 final 不得清除的既有记忆",
                sourceSessionID: load.sessionID!.rawValue,
                sourceTurnIDs: ["stale-seed-turn"],
                status: .active,
                consentState: .granted,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                supersedesMemoryID: nil
            )]
        ))
        runtime.useNarrativeMemoryStoreForTesting(staleMemoryStore)

        let first = try await runtime.startNativeSpeechInteraction()
        expect(first.lifecycleState == .active, "start activates interaction")
        expect(first.residentID == load.residentID, "interaction owns loaded resident")
        expect(first.sessionID == load.sessionID?.rawValue, "interaction owns current session")
        let firstStartProjection = await provider.startedProjections.last
        expect(
            firstStartProjection?.isBound(to: first) == true,
            "start carries resident-session-interaction bound context"
        )
        expect(
            firstStartProjection?.refreshReason == .interactionStarted,
            "start compiles the session base snapshot"
        )

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
        let partialUpdateCount = await provider.operationCount(.updateContext)
        expect(
            partialUpdateCount == 0,
            "partial transcript does not refresh context"
        )

        let blockedReceive = Task { @MainActor in
            try await runtime.receiveNativeSpeechEvent(
                interactionID: first.id
            )
        }
        await provider.waitUntilReceiveStarts()
        let relationshipBeforeLateFinal =
            runtime.relationshipProgressionDebugSnapshot()
        let memoryBeforeLateFinal = runtime.narrativeMemoryDebugSnapshot()
        let revisionBeforeLateFinal =
            runtime.realtimeSpeechContextSourceRevisionForTesting()
        let contextUpdatesBeforeLateFinal = await provider.operationCount(
            .updateContext
        )
        try await runtime.cancelActiveNativeSpeechInteraction(
            reason: .interrupted
        )
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: first.id,
                kind: .finalTranscript(
                    "关闭关系演进，清空全部叙事记忆"
                )
            )
        )
        let lateDisposition = try await blockedReceive.value
        expect(
            lateDisposition == .rejectedStale,
            "event arriving after cancel is rejected"
        )
        expect(
            runtime.relationshipProgressionDebugSnapshot()
                == relationshipBeforeLateFinal,
            "stale user final cannot apply relationship controls"
        )
        expect(
            runtime.narrativeMemoryDebugSnapshot() == memoryBeforeLateFinal,
            "stale user final cannot apply narrative memory controls"
        )
        expect(
            runtime.realtimeSpeechContextSourceRevisionForTesting()
                == revisionBeforeLateFinal,
            "stale user final cannot invalidate speech context"
        )
        let contextUpdatesAfterLateFinal = await provider.operationCount(
            .updateContext
        )
        expect(
            contextUpdatesAfterLateFinal == contextUpdatesBeforeLateFinal,
            "stale user final cannot refresh Provider context"
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
                kind: .finalTranscript(dynamicInput)
            )
        )
        let currentEvent = try await runtime.receiveNativeSpeechEvent(
            interactionID: second.id
        )
        expect(
            currentEvent == .accepted(
                NativeSpeechEvent(
                    interactionID: second.id,
                    kind: .finalTranscript(dynamicInput)
                )
            ),
            "new interaction event is accepted"
        )
        let finalUpdateCount = await provider.operationCount(.updateContext)
        expect(
            finalUpdateCount == 1,
            "final transcript refreshes context once (count=\(finalUpdateCount), untrimmed=\(dynamicProbe.budget.untrimmedUTF8Bytes), final=\(dynamicProbe.budget.finalUTF8Bytes), removed=\(dynamicProbe.budget.removedSectionIDs))"
        )
        let finalProjection = await provider.updatedProjections.last
        expect(
            finalProjection?.interactionID == second.id,
            "final projection remains bound to current interaction"
        )
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: second.id,
                kind: .finalTranscript(dynamicInput)
            )
        )
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: second.id
        )
        let duplicateFinalUpdateCount = await provider.operationCount(
            .updateContext
        )
        expect(
            duplicateFinalUpdateCount == finalUpdateCount,
            "same final trigger and source revision are not recompiled or resent"
        )
        let memoryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: memoryDirectory) }
        let memoryStore = NarrativeMemoryStore(baseURL: memoryDirectory)
        let relevantMemorySummary = "\(dynamicInput) 的已确认计划"
        try memoryStore.save(RuntimeNarrativeMemoryStoreSnapshot(
            residentID: second.residentID,
            records: [RuntimeNarrativeMemoryRecord(
                memoryID: "private-memory-id",
                residentID: second.residentID,
                type: .confirmedPlan,
                summary: relevantMemorySummary,
                sourceSessionID: "private-session-id",
                sourceTurnIDs: ["private-turn-id"],
                status: .active,
                consentState: .granted,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                supersedesMemoryID: nil
            )]
        ))
        runtime.useNarrativeMemoryStoreForTesting(memoryStore)
        await provider.enqueue(NativeSpeechEvent(
            interactionID: second.id,
            kind: .finalTranscript(dynamicInput)
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: second.id
        )
        let memoryRefreshCount = await provider.operationCount(
            .updateContext
        )
        expect(
            memoryRefreshCount == duplicateFinalUpdateCount + 1,
            "effective memory change invalidates the cached projection"
        )
        let memoryProjection = await provider.updatedProjections.last
        expect(
            memoryProjection?.instructions.contains(relevantMemorySummary)
                == true,
            "memory refresh sends only the relevant compiled summary"
        )
        expect(
            memoryProjection?.instructions.contains("private-memory-id")
                == false,
            "memory refresh omits Store identifiers"
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

        let reloadedInteraction = try await runtime.startNativeSpeechInteraction()
        let reloadedProjection = await provider.startedProjections.last
        expect(
            reloadedProjection?.isBound(to: reloadedInteraction) == true,
            "new Runtime session rebuilds a bound snapshot"
        )
        expect(
            reloadedProjection?.sessionID != firstStartProjection?.sessionID,
            "old session projection is not reused"
        )
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
            "incomplete native speech events do not write dialogue session data"
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
        try await testRuntimeMultiTurnState(fixtureData: fixtureData)
        try await testRuntimeSubtitleGate(fixtureData: fixtureData)
        try await testRuntimeUserFinalControlOrdering(
            fixtureData: fixtureData
        )
        try await testRuntimeInterrupts(fixtureData: fixtureData)
        try await testRuntimePlaybackFailure(fixtureData: fixtureData)
        try await testRuntimeRejectionDiagnostics(
            fixtureData: fixtureData
        )
        try await testRuntimeTimeouts(fixtureData: fixtureData)
        try await testConnectivityEntry(fixtureData: fixtureData)
        print("native_speech_runtime_integration_checks=\(checks)")
    }

    private static func testRuntimeSubtitleGate(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let sessionStore = SessionStore()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: sessionStore
        )
        let load = runtime.loadDR(from: fixtureData)
        expect(load.isLoaded, "subtitle resident loads")
        _ = try runtime.clearDialogueTestData()
        let memoryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: memoryDirectory) }
        let memoryStore = NarrativeMemoryStore(baseURL: memoryDirectory)
        try memoryStore.save(RuntimeNarrativeMemoryStoreSnapshot(
            residentID: load.residentID,
            records: [RuntimeNarrativeMemoryRecord(
                memoryID: "partial-safety-memory",
                residentID: load.residentID,
                type: .confirmedPlan,
                summary: "已经确认的安全边界",
                sourceSessionID: load.sessionID!.rawValue,
                sourceTurnIDs: ["seed-turn"],
                status: .active,
                consentState: .granted,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                supersedesMemoryID: nil
            )]
        ))
        runtime.useNarrativeMemoryStoreForTesting(memoryStore)
        let memoryBefore = runtime.narrativeMemoryDebugSnapshot()
        let dialogueBefore =
            (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 1
        )
        var subtitle = runtime.realtimeSpeechSubtitleSnapshot()
        expect(
            subtitle.turnNumber == 1 && subtitle.turnGeneration == 1,
            "Runtime starts a bound subtitle generation"
        )

        try await acceptStateEvent(
            .partialTranscript("清空全部叙事记忆"),
            expectedState: .listening,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        try await acceptStateEvent(
            .partialTranscript("你好"),
            expectedState: .listening,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        subtitle = runtime.realtimeSpeechSubtitleSnapshot()
        expect(subtitle.userPartial == "你好", "Runtime replaces user partial")
        expect(subtitle.userPartialRevision == 2, "Runtime advances user revision")
        let dialogueAfterPartial =
            (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
        expect(
            dialogueAfterPartial == dialogueBefore,
            "partial transcript never enters Session"
        )
        expect(
            runtime.narrativeMemoryDebugSnapshot() == memoryBefore,
            "user partial cannot mutate narrative memory"
        )

        try await acceptStateEvent(
            .finalTranscript("你好"),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        subtitle = runtime.realtimeSpeechSubtitleSnapshot()
        expect(subtitle.userFinal == "你好", "Runtime accepts gated user final")
        expect(subtitle.userFinalLocked, "Runtime locks user final")

        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .partialTranscript("迟到用户 partial")
        ))
        let lateUserPartial = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            lateUserPartial == .rejectedOutOfOrder,
            "Runtime rejects user partial after final"
        )
        expect(
            runtime.realtimeSpeechSubtitleSnapshot().userFinal == "你好",
            "rejected partial cannot alter final subtitle"
        )

        try await acceptStateEvent(
            .outputText(text: "答", isFinal: false),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        expect(
            runtime.realtimeSpeechSubtitleSnapshot().residentPartial == "答",
            "Runtime accepts resident partial independently"
        )
        expect(
            runtime.narrativeMemoryDebugSnapshot() == memoryBefore,
            "resident partial cannot mutate narrative memory"
        )
        try await acceptStateEvent(
            .outputText(text: "答案", isFinal: true),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        subtitle = runtime.realtimeSpeechSubtitleSnapshot()
        expect(subtitle.residentPartial == nil, "resident final clears partial")
        expect(subtitle.residentFinal == "答案", "Runtime locks resident final")
        expect(
            runtime.realtimeSpeechStateSnapshot().state == .thinking,
            "text output cannot enter speaking"
        )

        try await acceptStateEvent(
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 1,
                bytes: Data([0, 1]),
                format: .pcm16
            )),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        expect(
            runtime.realtimeSpeechStateSnapshot().state == .thinking,
            "received outputAudio cannot enter speaking"
        )
        await acceptPlaybackEvent(
            .started,
            generation: 1,
            binding: binding,
            runtime: runtime
        )
        expect(
            runtime.realtimeSpeechStateSnapshot().state == .speaking,
            "local playback start is the speaking trigger"
        )

        try await acceptStateEvent(
            .inputSpeechStarted,
            expectedState: .listening,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        subtitle = runtime.realtimeSpeechSubtitleSnapshot()
        expect(
            subtitle.turnNumber == 2 && subtitle.turnGeneration == 2,
            "Interrupt advances subtitle turn generation"
        )
        expect(
            subtitle.residentPartial == nil && subtitle.residentFinal == nil,
            "Interrupt clears resident subtitle display"
        )
        expect(
            subtitle.interactionShortID != nil,
            "Interrupt preserves subtitle interaction"
        )
        expect(
            (try? sessionStore.loadMostRecentDialogueEntries()) == dialogueBefore,
            "Interrupt does not commit an incomplete resident turn"
        )

        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputText(text: "旧轮迟到", isFinal: true)
        ))
        let lateResident = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(lateResident == .rejectedLate, "old turn resident subtitle is rejected")
        expect(
            (try? sessionStore.loadMostRecentDialogueEntries()) == dialogueBefore,
            "stale generation cannot write unfinished resident content"
        )

        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
        subtitle = runtime.realtimeSpeechSubtitleSnapshot()
        expect(subtitle.interactionShortID == nil, "Stop invalidates subtitle interaction")
        expect(subtitle.displayText == nil, "Stop clears active subtitle display")
        expect(subtitle.lastClosureReason == .stopped, "Stop records subtitle closure")
        expect(
            (try? sessionStore.loadMostRecentDialogueEntries()) == dialogueBefore,
            "Stop does not commit an incomplete resident turn"
        )
        expect(
            runtime.narrativeMemoryDebugSnapshot() == memoryBefore,
            "Interrupt and Stop preserve narrative memory"
        )
    }

    private static func testRuntimeUserFinalControlOrdering(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let sessionStore = SessionStore()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: sessionStore
        )
        let load = runtime.loadDR(from: fixtureData)
        expect(load.isLoaded, "memory-control resident loads")
        _ = try runtime.clearDialogueTestData()

        let memoryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: memoryDirectory) }
        let memoryStore = NarrativeMemoryStore(baseURL: memoryDirectory)
        let controlText = "关闭关系演进，清空全部叙事记忆"
        let memorySummary = "清空全部叙事记忆前，已经确认的安全边界"
        try memoryStore.save(RuntimeNarrativeMemoryStoreSnapshot(
            residentID: load.residentID,
            records: [RuntimeNarrativeMemoryRecord(
                memoryID: "voice-control-memory",
                residentID: load.residentID,
                type: .confirmedPlan,
                summary: memorySummary,
                sourceSessionID: load.sessionID!.rawValue,
                sourceTurnIDs: ["seed-control-turn"],
                status: .active,
                consentState: .granted,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                supersedesMemoryID: nil
            )]
        ))
        runtime.useNarrativeMemoryStoreForTesting(memoryStore)
        let relationshipBefore =
            runtime.relationshipProgressionDebugSnapshot()
        expect(
            relationshipBefore.isAvailable && relationshipBefore.enabled,
            "memory-control fixture exposes enabled relationship progression"
        )
        let projectionBeforeControl = try RealtimeSpeechContextCompiler()
            .compile(
                context: runtime.compileResidentDialogueContext(
                    currentUserInput: controlText
                )!,
                interaction: NativeSpeechInteraction(
                    residentID: load.residentID,
                    sessionID: load.sessionID!.rawValue,
                    providerProfileID: nativeSpeechProfile().profileID
                ),
                refreshReason: .finalTranscript
            )
        expect(
            projectionBeforeControl.instructions.contains(memorySummary),
            "control input would retrieve the existing memory before deletion"
        )

        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 1
        )
        let revisionBeforePartial =
            runtime.realtimeSpeechContextSourceRevisionForTesting()
        try await acceptStateEvent(
            .partialTranscript(controlText),
            expectedState: .listening,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        expect(
            runtime.narrativeMemoryDebugSnapshot()?.records.first?.status
                == .active,
            "user partial cannot apply narrative memory controls"
        )
        expect(
            runtime.relationshipProgressionDebugSnapshot()
                == relationshipBefore,
            "user partial cannot apply relationship controls"
        )
        expect(
            runtime.realtimeSpeechContextSourceRevisionForTesting()
                == revisionBeforePartial,
            "user partial cannot invalidate speech context"
        )
        let partialContextUpdateCount = await provider.operationCount(
            .updateContext
        )
        expect(
            partialContextUpdateCount == 0,
            "user partial cannot update Provider context"
        )

        try await acceptStateEvent(
            .finalTranscript(controlText),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        expect(
            runtime.narrativeMemoryDebugSnapshot()?.records.first?.status
                == .deleted,
            "accepted user final applies narrative memory control"
        )
        let relationshipAfterFinal =
            runtime.relationshipProgressionDebugSnapshot()
        expect(
            !relationshipAfterFinal.enabled,
            "accepted user final applies relationship control"
        )
        let revisionAfterFinal =
            runtime.realtimeSpeechContextSourceRevisionForTesting()
        expect(
            revisionAfterFinal == revisionBeforePartial + 2,
            "only the two effective final controls advance source revision"
        )
        let finalContextUpdateCount = await provider.operationCount(
            .updateContext
        )
        expect(
            finalContextUpdateCount == 1,
            "accepted user final refreshes Provider context once"
        )
        let projectionAfterFinal = await provider.updatedProjections.last
        expect(
            projectionAfterFinal?.instructions.contains(memorySummary)
                == false,
            "memory control is applied before Provider context refresh"
        )

        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript(controlText)
        ))
        let duplicateFinal = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            duplicateFinal == .rejectedOutOfOrder,
            "duplicate user final is rejected after the final lock"
        )
        expect(
            runtime.realtimeSpeechContextSourceRevisionForTesting()
                == revisionAfterFinal,
            "duplicate user final cannot repeat controls or source revision"
        )
        let duplicateContextUpdateCount = await provider.operationCount(
            .updateContext
        )
        expect(
            duplicateContextUpdateCount == 1,
            "duplicate user final cannot resend Provider context"
        )

        try await acceptStateEvent(
            .outputText(text: "居民未完成", isFinal: false),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        expect(
            (try? sessionStore.loadMostRecentDialogueEntries())?.isEmpty
                == true,
            "resident partial cannot enter Session"
        )
        try await acceptStateEvent(
            .outputText(text: "居民完成回复", isFinal: true),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        try await acceptStateEvent(
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 1,
                bytes: Data([0, 1]),
                format: .pcm16
            )),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        await acceptPlaybackEvent(
            .started,
            generation: 1,
            binding: binding,
            runtime: runtime
        )
        try await acceptStateEvent(
            .responseCompleted,
            expectedState: .speaking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        expect(
            (try? sessionStore.loadMostRecentDialogueEntries())?.isEmpty
                == true,
            "response completion waits for playback before Session commit"
        )
        await acceptPlaybackEvent(
            .completed,
            generation: 1,
            binding: binding,
            runtime: runtime
        )
        let committed =
            (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
        expect(
            committed.map(\.text) == [controlText, "居民完成回复"],
            "completed voice turn persists only the locked finals"
        )
        expect(
            runtime.realtimeSpeechContextSourceRevisionForTesting()
                == revisionAfterFinal + 1,
            "completed turn invalidates Session context without repeating controls"
        )
        expect(
            runtime.relationshipProgressionDebugSnapshot().revision
                == relationshipAfterFinal.revision,
            "completed turn does not apply relationship control twice"
        )

        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeMultiTurnState(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let sessionStore = SessionStore()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: sessionStore
        )
        expect(runtime.loadDR(from: fixtureData).isLoaded, "multi-turn resident loads")
        _ = try runtime.clearDialogueTestData()
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 1
        )
        expect(
            runtime.realtimeSpeechStateSnapshot().state == .listening,
            "Runtime starts multi-turn input in listening"
        )

        let userFinals = ["第一轮用户 final", "第二轮用户 final"]
        let residentFinals = ["第一轮居民 final", "第二轮居民 final"]
        for turn in 1...2 {
            let userFinal = userFinals[turn - 1]
            let residentFinal = residentFinals[turn - 1]
            try await acceptStateEvent(
                .inputSpeechStarted,
                expectedState: .listening,
                binding: binding,
                runtime: runtime,
                provider: provider
            )
            try await acceptStateEvent(
                .inputSpeechEnded,
                expectedState: .thinking,
                binding: binding,
                runtime: runtime,
                provider: provider
            )
            try await acceptStateEvent(
                .finalTranscript(userFinal),
                expectedState: .thinking,
                binding: binding,
                runtime: runtime,
                provider: provider
            )
            if turn == 2 {
                let secondTurnProjection = await provider.updatedProjections.last
                expect(
                    secondTurnProjection?.instructions.contains(userFinals[0])
                        == true,
                    "second voice turn reads the first user final from Session"
                )
                expect(
                    secondTurnProjection?.instructions.contains(residentFinals[0])
                        == true,
                    "second voice turn reads the first resident final from Session"
                )
            }
            try await acceptStateEvent(
                .outputText(text: "居民 partial \(turn)", isFinal: false),
                expectedState: .thinking,
                binding: binding,
                runtime: runtime,
                provider: provider
            )
            let entriesBeforeResidentFinal =
                (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
            expect(
                entriesBeforeResidentFinal.count == (turn - 1) * 2,
                "resident partial does not enter the formal dialogue chain"
            )
            try await acceptStateEvent(
                .outputText(text: residentFinal, isFinal: true),
                expectedState: .thinking,
                binding: binding,
                runtime: runtime,
                provider: provider
            )
            try await acceptStateEvent(
                .outputAudio(
                    NativeSpeechAudioPayload(
                        interactionID: binding.interactionID,
                        sequenceNumber: UInt64(turn),
                        bytes: Data([0, 1]),
                        format: .pcm16
                    )
                ),
                expectedState: .thinking,
                binding: binding,
                runtime: runtime,
                provider: provider
            )
            await acceptPlaybackEvent(
                .started,
                generation: UInt64(turn),
                binding: binding,
                runtime: runtime
            )
            try await acceptStateEvent(
                .responseCompleted,
                expectedState: .speaking,
                binding: binding,
                runtime: runtime,
                provider: provider
            )
            let entriesBeforePlaybackCompletion =
                (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
            expect(
                entriesBeforePlaybackCompletion.count == (turn - 1) * 2,
                "response completion waits for the completed playback turn"
            )
            await acceptPlaybackEvent(
                .completed,
                generation: UInt64(turn),
                binding: binding,
                runtime: runtime
            )
            expect(
                runtime.realtimeSpeechStateSnapshot().completedTurnCount
                    == UInt64(turn),
                "Runtime completes turn \(turn) without closing interaction"
            )
            expect(
                runtime.realtimeSpeechStateSnapshot().state == .listening,
                "Runtime returns to listening after turn \(turn)"
            )
            let committed =
                (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
            expect(
                committed.count == turn * 2,
                "completed voice turn is committed exactly once"
            )
            expect(
                committed.suffix(2).map(\.text) == [userFinal, residentFinal],
                "formal voice exchange uses only user and resident finals"
            )
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .responseCompleted
            ))
            let duplicateCompletion = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            expect(
                duplicateCompletion == .rejectedOutOfOrder,
                "duplicate response completion is rejected"
            )
            expect(
                (try? sessionStore.loadMostRecentDialogueEntries())?.count
                    == turn * 2,
                "duplicate completion cannot submit memory twice"
            )
        }

        let startCountBeforeStop = await provider.operationCount(.start)
        let closeCountBeforeStop = await provider.operationCount(.close)
        expect(
            startCountBeforeStop == 1,
            "multi-turn interaction starts Provider once"
        )
        expect(
            closeCountBeforeStop == 0,
            "responseCompleted does not close Provider"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
        expect(
            runtime.realtimeSpeechStateSnapshot().state == .idle,
            "explicit Stop returns Runtime to idle"
        )
        let cancelCount = await provider.operationCount(.cancel)
        let closeCount = await provider.operationCount(.close)
        expect(cancelCount == 1, "multi-turn Stop cancels Provider once")
        expect(closeCount == 1, "multi-turn Stop closes Provider once")
    }

    private static func testRuntimeRejectionDiagnostics(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        let diagnostics = NativeSpeechDiagnosticBuffer()
        runtime.attachNativeSpeechDiagnosticBuffer(diagnostics)
        expect(
            runtime.loadDR(from: fixtureData).isLoaded,
            "diagnostic resident loads"
        )
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 1
        )
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .inputSpeechEnded
            )
        )
        let disposition = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            disposition == .rejectedOutOfOrder,
            "out-of-order event is rejected"
        )
        let rejected = diagnostics.drain().events.last
        expect(
            rejected?.source == .runtime
                && rejected?.category == "input_speech_ended"
                && rejected?.stateBefore == "listening"
                && rejected?.disposition == "rejected_out_of_order"
                && rejected?.errorCode == "invalid_state_transition",
            "Runtime rejection diagnostic preserves safe cause"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeInterrupts(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixtureData).isLoaded, "interrupt resident loads")
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 1
        )
        let startCount = await provider.operationCount(.start)

        try await acceptStateEvent(
            .finalTranscript("turn one"),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        try await acceptStateEvent(
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 1,
                bytes: Data([0, 1]),
                format: .pcm16
            )),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        await acceptPlaybackEvent(
            .started,
            generation: 1,
            binding: binding,
            runtime: runtime
        )
        try await acceptStateEvent(
            .inputSpeechStarted,
            expectedState: .listening,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        let firstInterruptCommitted = try await commitPendingInterrupt(
            runtime: runtime,
            binding: binding
        )
        expect(
            firstInterruptCommitted,
            "first pending Interrupt commits once"
        )
        let duplicateCommit = try await commitPendingInterrupt(
            runtime: runtime,
            binding: binding
        )
        expect(!duplicateCommit, "pending Interrupt is consumed once")
        var cancelCount = await provider.operationCount(.cancel)
        expect(cancelCount == 1, "first Interrupt sends one Provider cancel")
        expect(
            runtime.realtimeSpeechStateSnapshot().currentTurnNumber == 2,
            "first Interrupt advances Runtime turn generation"
        )
        expect(
            runtime.realtimeSpeechStateSnapshot().interactionTerminalOutcome
                == nil,
            "Interrupt preserves the Runtime interaction"
        )

        try await acceptStateEvent(
            .inputSpeechStarted,
            expectedState: .listening,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        let duplicateCancelCount = await provider.operationCount(.cancel)
        expect(
            duplicateCancelCount == cancelCount,
            "duplicate speech_started sends no second cancel"
        )

        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 2,
                bytes: Data([2, 3]),
                format: .pcm16
            ))
        ))
        let lateAudio = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            lateAudio == .rejectedLate,
            "Runtime rejects old turn outputAudio"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .cancelled(reason: "interrupted")
        ))
        let lateCancellation = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            lateCancellation == .rejectedLate,
            "Runtime rejects old turn cancelled acknowledgement"
        )

        try await acceptStateEvent(
            .inputSpeechEnded,
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        try await acceptStateEvent(
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 3,
                bytes: Data([4, 5]),
                format: .pcm16
            )),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        await acceptPlaybackEvent(
            .started,
            generation: 2,
            binding: binding,
            runtime: runtime
        )
        try await acceptStateEvent(
            .inputSpeechStarted,
            expectedState: .listening,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        let secondInterruptCommitted = try await commitPendingInterrupt(
            runtime: runtime,
            binding: binding
        )
        expect(
            secondInterruptCommitted,
            "second pending Interrupt commits once"
        )
        cancelCount = await provider.operationCount(.cancel)
        expect(cancelCount == 2, "second Interrupt sends one additional cancel")
        let startCountAfterInterrupts = await provider.operationCount(.start)
        expect(
            startCountAfterInterrupts == startCount,
            "consecutive Interrupts do not create a new interaction"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        let lateCompletion = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            lateCompletion == .rejectedLate,
            "old responseCompleted cannot complete the new turn"
        )

        try await acceptStateEvent(
            .inputSpeechEnded,
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        try await acceptStateEvent(
            .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 4,
                bytes: Data([6, 7]),
                format: .pcm16
            )),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        await acceptPlaybackEvent(
            .started,
            generation: 3,
            binding: binding,
            runtime: runtime
        )
        try await acceptStateEvent(
            .responseCompleted,
            expectedState: .speaking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        await acceptPlaybackEvent(
            .completed,
            generation: 3,
            binding: binding,
            runtime: runtime
        )
        let completedSnapshot = runtime.realtimeSpeechStateSnapshot()
        expect(
            completedSnapshot.lastCanonicalOutcome == .completed,
            "new turn completes with one canonical outcome"
        )
        expect(
            completedSnapshot.interruptedTurnCount == 2,
            "Runtime counts both interrupted turns"
        )
        expect(
            completedSnapshot.rejectedLateEventCount == 3,
            "Runtime counts rejected old-turn events"
        )

        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
        let stoppedSnapshot = runtime.realtimeSpeechStateSnapshot()
        expect(stoppedSnapshot.state == .idle, "Stop after Interrupt returns idle")
        expect(
            stoppedSnapshot.interactionTerminalOutcome == .stopped,
            "Stop commits the only interaction terminal outcome"
        )
        let cancelCountAfterStop = await provider.operationCount(.cancel)
        let closeCountAfterStop = await provider.operationCount(.close)
        expect(
            cancelCountAfterStop == cancelCount + 1,
            "Stop sends one final Provider cancel"
        )
        expect(
            closeCountAfterStop == 1,
            "Stop closes Provider once"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
        let cancelCountAfterDuplicateStop = await provider.operationCount(
            .cancel
        )
        let closeCountAfterDuplicateStop = await provider.operationCount(
            .close
        )
        expect(
            cancelCountAfterDuplicateStop == cancelCount + 1,
            "duplicate Stop is idempotent"
        )
        expect(
            closeCountAfterDuplicateStop == 1,
            "duplicate Stop cannot close Provider twice"
        )
    }

    private static func acceptStateEvent(
        _ kind: NativeSpeechEventKind,
        expectedState: RealtimeSpeechState,
        binding: NativeSpeechInputBinding,
        runtime: RuntimeCore,
        provider: FakeNativeSpeechProvider
    ) async throws {
        await provider.enqueue(
            NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: kind
            )
        )
        let disposition = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        guard case .accepted = disposition else {
            fatalError("FAILED: Runtime state event was rejected")
        }
        checks += 1
        expect(
            runtime.realtimeSpeechStateSnapshot().state == expectedState,
            "Runtime owns \(expectedState.rawValue) transition"
        )
    }

    private static func commitPendingInterrupt(
        runtime: RuntimeCore,
        binding: NativeSpeechInputBinding
    ) async throws -> Bool {
        let state = runtime.realtimeSpeechStateSnapshot()
        let subtitle = runtime.realtimeSpeechSubtitleSnapshot()
        return try await runtime.commitNativeSpeechInterrupt(
            interactionID: binding.interactionID,
            turnNumber: state.currentTurnNumber,
            turnGeneration: subtitle.turnGeneration
        )
    }

    private static func testRuntimePlaybackFailure(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixtureData).isLoaded, "playback failure resident loads")
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 1
        )
        try await acceptStateEvent(
            .thinking,
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        try await acceptStateEvent(
            .outputAudio(
                NativeSpeechAudioPayload(
                    interactionID: binding.interactionID,
                    sequenceNumber: 1,
                    bytes: Data([0, 1]),
                    format: .pcm16
                )
            ),
            expectedState: .thinking,
            binding: binding,
            runtime: runtime,
            provider: provider
        )
        await acceptPlaybackEvent(
            .started,
            generation: 1,
            binding: binding,
            runtime: runtime
        )
        let disposition = await runtime.handleNativeSpeechPlaybackEvent(
            RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 1,
                kind: .failed(.unavailable)
            )
        )
        expect(disposition == .applied, "Runtime accepts playback failure")
        let snapshot = runtime.realtimeSpeechStateSnapshot()
        expect(snapshot.state == .idle, "playback failure returns Runtime idle")
        expect(snapshot.lastStandardError == "unavailable", "playback failure keeps standard error")
        let cancelCount = await provider.operationCount(.cancel)
        let closeCount = await provider.operationCount(.close)
        expect(cancelCount == 1, "playback failure cancels Provider once")
        expect(closeCount == 1, "playback failure closes Provider once")
    }

    private static func acceptPlaybackEvent(
        _ kind: RealtimeSpeechPlaybackEventKind,
        generation: UInt64,
        binding: NativeSpeechInputBinding,
        runtime: RuntimeCore
    ) async {
        let snapshot = runtime.realtimeSpeechStateSnapshot()
        let disposition = await runtime.handleNativeSpeechPlaybackEvent(
            RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: snapshot.currentTurnNumber,
                playbackGeneration: generation,
                kind: kind
            )
        )
        expect(disposition == .applied, "Runtime accepts local playback lifecycle")
    }

    private static func testRuntimeTimeouts(
        fixtureData: Data
    ) async throws {
        try await testRuntimeTimeout(
            fixtureData: fixtureData,
            events: [.inputSpeechStarted],
            expectedReason: .speechStopTimedOut,
            expectedError: "speech_stop_timed_out"
        )
        try await testRuntimeTimeout(
            fixtureData: fixtureData,
            events: [.finalTranscript("timeout")],
            expectedReason: .thinkingTimedOut,
            expectedError: "thinking_output_timed_out"
        )
        try await testRuntimeTimeout(
            fixtureData: fixtureData,
            events: [
                .finalTranscript("timeout"),
                .outputAudio(
                    NativeSpeechAudioPayload(
                        interactionID: NativeSpeechInteractionID(),
                        sequenceNumber: 1,
                        bytes: Data([0, 1]),
                        format: .pcm16
                    )
                )
            ],
            expectedReason: .speakingTimedOut,
            expectedError: "speaking_completion_timed_out"
        )
    }

    private static func testRuntimeTimeout(
        fixtureData: Data,
        events: [NativeSpeechEventKind],
        expectedReason: RealtimeSpeechTransitionReason,
        expectedError: String
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        runtime.useRealtimeSpeechTimeoutConfigurationForTesting(
            RealtimeSpeechTimeoutConfiguration(
                speechStopNanoseconds: 5_000_000,
                thinkingOutputNanoseconds: 5_000_000,
                speakingCompletionNanoseconds: 5_000_000
            )
        )
        expect(runtime.loadDR(from: fixtureData).isLoaded, "timeout resident loads")
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 1
        )
        expect(
            runtime.realtimeSpeechStateSnapshot().state == .listening,
            "Runtime input start owns listening state"
        )

        for kind in events {
            let resolvedKind: NativeSpeechEventKind
            if case .outputAudio(let payload) = kind {
                resolvedKind = .outputAudio(
                    NativeSpeechAudioPayload(
                        interactionID: binding.interactionID,
                        sequenceNumber: payload.sequenceNumber,
                        bytes: payload.bytes,
                        format: payload.format
                    )
                )
            } else {
                resolvedKind = kind
            }
            await provider.enqueue(
                NativeSpeechEvent(
                    interactionID: binding.interactionID,
                    kind: resolvedKind
                )
            )
            let disposition = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            guard case .accepted = disposition else {
                fatalError("FAILED: timeout setup event was rejected")
            }
            checks += 1
        }
        if expectedReason == .speakingTimedOut {
            await acceptPlaybackEvent(
                .started,
                generation: 1,
                binding: binding,
                runtime: runtime
            )
        }

        try await Task.sleep(for: .milliseconds(30))
        let snapshot = runtime.realtimeSpeechStateSnapshot()
        expect(snapshot.state == .idle, "Runtime guard timeout returns idle")
        expect(snapshot.guardTimeoutTriggered, "Runtime records guard timeout")
        expect(snapshot.lastTransitionReason == expectedReason, "Runtime retains timeout reason")
        expect(snapshot.lastStandardError == expectedError, "Runtime retains standard timeout error")
        let cancelCount = await provider.operationCount(.cancel)
        let closeCount = await provider.operationCount(.close)
        expect(
            cancelCount == 1,
            "Runtime timeout actively cancels Provider once"
        )
        expect(
            closeCount == 1,
            "Runtime timeout closes Provider once"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
        let stoppedSnapshot = runtime.realtimeSpeechStateSnapshot()
        expect(
            stoppedSnapshot.lastTransitionReason == .userStopped,
            "explicit Runtime Stop wins a timeout race"
        )
        expect(
            stoppedSnapshot.guardTimeoutTriggered,
            "Runtime Stop preserves timeout diagnosis"
        )
        let cancelCountAfterStop = await provider.operationCount(.cancel)
        let closeCountAfterStop = await provider.operationCount(.close)
        expect(
            cancelCountAfterStop == cancelCount,
            "post-timeout Stop does not cancel Provider twice"
        )
        expect(
            closeCountAfterStop == closeCount,
            "post-timeout Stop does not close Provider twice"
        )
    }

    private static func testConnectivityEntry(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider(emitsHandshakeOnStart: true)
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixtureData).isLoaded, "connectivity resident loads")
        let result = await runtime.testNativeSpeechConnectivity(
            profile: nativeSpeechProfile()
        )
        switch result {
        case .success:
            checks += 1
        case .failure(let error):
            fatalError("FAILED: fake connectivity failed: \(error)")
        }
        let startCount = await provider.operationCount(.start)
        let receiveCount = await provider.operationCount(.receive)
        let closeCount = await provider.operationCount(.close)
        let sendCount = await provider.operationCount(.send)
        expect(
            startCount == 1,
            "connectivity starts one Provider interaction"
        )
        expect(
            receiveCount == 2,
            "connectivity consumes created and updated"
        )
        expect(
            closeCount == 1,
            "connectivity closes Provider"
        )
        expect(
            sendCount == 0,
            "connectivity sends no audio payload"
        )
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
        let profile = nativeSpeechProfile()
        expect(
            runtime.configureNativeSpeechProvider(profile: profile) == nil,
            "native speech profile configures"
        )
        return runtime
    }

    private static func nativeSpeechProfile() -> NativeSpeechProviderProfile {
        NativeSpeechProviderProfile(
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
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
