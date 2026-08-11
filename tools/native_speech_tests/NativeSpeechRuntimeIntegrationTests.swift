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
        case toolOutput(NativeSpeechInteractionID, String)
        case toolContinuation(NativeSpeechInteractionID)
    }

    enum OperationKind: Sendable {
        case start
        case updateContext
        case send
        case receive
        case cancel
        case close
        case toolOutput
        case toolContinuation
    }

    private var events: [NativeSpeechEvent] = []
    private var receiveContinuation:
        CheckedContinuation<NativeSpeechEvent, any Error>?
    private var receiveStarted = false
    private var receiveStartedContinuation: CheckedContinuation<Void, Never>?
    private(set) var operations: [Operation] = []
    private(set) var startedProjections: [RealtimeSpeechContextProjection] = []
    private(set) var updatedProjections: [RealtimeSpeechContextProjection] = []
    private(set) var startedToolDefinitions: [[NativeSpeechToolDefinition]] = []
    private(set) var submittedToolOutputs: [NativeSpeechToolOutput] = []
    private var toolContinuationWaiters:
        [Int: [CheckedContinuation<Void, Never>]] = [:]
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
        startedToolDefinitions.append(request.tools)
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

    func submitToolOutput(
        _ output: NativeSpeechToolOutput,
        interactionID: NativeSpeechInteractionID
    ) async throws {
        operations.append(.toolOutput(interactionID, output.callID))
        submittedToolOutputs.append(output)
    }

    func requestToolContinuation(
        interactionID: NativeSpeechInteractionID
    ) async throws {
        operations.append(.toolContinuation(interactionID))
        let count = operationCount(.toolContinuation)
        toolContinuationWaiters.removeValue(forKey: count)?.forEach {
            $0.resume()
        }
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
                 (.close, .close),
                 (.toolOutput, .toolOutput),
                 (.toolContinuation, .toolContinuation):
                return true
            default:
                return false
            }
        }.count
    }

    func waitUntilToolContinuationCount(_ count: Int) async {
        guard operationCount(.toolContinuation) < count else { return }
        await withCheckedContinuation { continuation in
            toolContinuationWaiters[count, default: []].append(continuation)
        }
    }
}

private actor FakeNativeSpeechToolExecutor: NativeSpeechToolExecuting {
    private let output: String
    private let suspends: Bool
    private(set) var requests: [NativeSpeechToolExecutionRequest] = []
    private var completedRequestCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var completedContinuations:
        [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(output: String, suspends: Bool = false) {
        self.output = output
        self.suspends = suspends
    }

    func execute(
        _ request: NativeSpeechToolExecutionRequest
    ) async throws -> String {
        requests.append(request)
        startedContinuation?.resume()
        startedContinuation = nil
        if suspends {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        completedRequestCount += 1
        completedContinuations.removeValue(
            forKey: completedRequestCount
        )?.forEach { $0.resume() }
        return output
    }

    func waitUntilStarted() async {
        guard requests.isEmpty else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    func waitUntilCompleted() async {
        await waitUntilCompleted(count: 1)
    }

    func waitUntilCompleted(count: Int) async {
        guard completedRequestCount < count else { return }
        await withCheckedContinuation { continuation in
            completedContinuations[count, default: []].append(continuation)
        }
    }

    func requestCount() -> Int {
        requests.count
    }
}

private actor FakeNativeSpeechToolPermissionResolver:
    NativeSpeechToolPermissionResolving {
    private let automaticDecision: NativeSpeechToolPermissionDecision?
    private(set) var requests: [NativeSpeechToolPermissionRequest] = []
    private var continuations: [
        NativeSpeechToolCallIdentity:
            CheckedContinuation<NativeSpeechToolPermissionDecision, Never>
    ] = [:]
    private var requestWaiters:
        [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var completedCount = 0
    private var completionWaiters:
        [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(
        automaticDecision: NativeSpeechToolPermissionDecision? = nil
    ) {
        self.automaticDecision = automaticDecision
    }

    func resolve(
        _ request: NativeSpeechToolPermissionRequest
    ) async -> NativeSpeechToolPermissionDecision {
        requests.append(request)
        requestWaiters.removeValue(forKey: requests.count)?.forEach {
            $0.resume()
        }
        let decision: NativeSpeechToolPermissionDecision
        if let automaticDecision {
            decision = automaticDecision
        } else {
            decision = await withCheckedContinuation { continuation in
                continuations[request.identity] = continuation
            }
        }
        completedCount += 1
        completionWaiters.removeValue(forKey: completedCount)?.forEach {
            $0.resume()
        }
        return decision
    }

    func decide(
        _ decision: NativeSpeechToolPermissionDecision,
        requestAt index: Int
    ) {
        let identity = requests[index].identity
        continuations.removeValue(forKey: identity)?.resume(
            returning: decision
        )
    }

    func waitUntilRequested(count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[count, default: []].append(continuation)
        }
    }

    func waitUntilCompleted(count: Int) async {
        guard completedCount < count else { return }
        await withCheckedContinuation { continuation in
            completionWaiters[count, default: []].append(continuation)
        }
    }

    func request(at index: Int) -> NativeSpeechToolPermissionRequest {
        requests[index]
    }

    func requestCount() -> Int {
        requests.count
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
        let productionTools = await provider.startedToolDefinitions.last
        expect(
            productionTools?.isEmpty == true,
            "production Runtime advertises no external tools by default"
        )
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
        try await testRuntimeToolRouting(fixtureData: fixtureData)
        try await testRuntimeToolPermissionApproveAndPlayback(
            fixtureData: fixtureData
        )
        try await testRuntimeToolPermissionRejections(
            fixtureData: fixtureData
        )
        try await testRuntimeToolPermissionInterrupt(
            fixtureData: fixtureData
        )
        try await testRuntimeToolPermissionAcrossTurns(
            fixtureData: fixtureData
        )
        try await testRuntimeMultipleToolPermissions(
            fixtureData: fixtureData
        )
        try await testRuntimeToolCallHistoryBounded(fixtureData: fixtureData)
        try await testRuntimePendingToolCallRetention(fixtureData: fixtureData)
        try await testRuntimeToolPlaybackGate(fixtureData: fixtureData)
        try await testRuntimeStaleToolResult(fixtureData: fixtureData)
        try await testRuntimePlaybackFailure(fixtureData: fixtureData)
        try await testRuntimeRejectionDiagnostics(
            fixtureData: fixtureData
        )
        try await testRuntimeTimeouts(fixtureData: fixtureData)
        try await testConnectivityEntry(fixtureData: fixtureData)
        print("native_speech_runtime_integration_checks=\(checks)")
    }

    private static func testRuntimeToolRouting(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let sessionStore = SessionStore()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: sessionStore
        )
        expect(runtime.loadDR(from: fixtureData).isLoaded, "tool resident loads")
        _ = try runtime.clearDialogueTestData()
        let executor = FakeNativeSpeechToolExecutor(
            output: #"{"value":"PRIVATE_TOOL_RESULT_DO_NOT_STORE"}"#
        )
        let permissionResolver = FakeNativeSpeechToolPermissionResolver(
            automaticDecision: .approved
        )
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        runtime.configureNativeSpeechToolPermissionResolver(
            permissionResolver
        )
        let diagnostics = NativeSpeechDiagnosticBuffer()
        runtime.attachNativeSpeechDiagnosticBuffer(diagnostics)
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 501
        )
        let advertised = await provider.startedToolDefinitions.last ?? []
        expect(
            advertised.map(\.name) == [
                "lookup_test_value",
                "permission_test_action"
            ],
            "all Runtime-available Tool definitions reach Provider"
        )

        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("请使用测试工具")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputText(text: "让我先查一下", isFinal: true)
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 0,
                bytes: Data([0, 1]),
                format: .pcm16
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let interimPlaybackStarted = await runtime
            .handleNativeSpeechPlaybackEvent(RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 61,
                kind: .started
            ))
        expect(
            interimPlaybackStarted == .applied,
            "speech-before-tool playback starts"
        )
        let request = NativeSpeechToolRequest(
            callID: "call-normal",
            toolName: "lookup_test_value",
            arguments: Data(#"{"key":"alpha"}"#.utf8),
            correlationHash: "safe-call-hash"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .toolRequestCandidate(request)
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .toolRequestCandidate(request)
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await executor.waitUntilCompleted()
        let executedAfterDuplicate = await executor.requestCount()
        expect(
            executedAfterDuplicate == 1,
            "duplicate call ID executes exactly once"
        )
        let permissionRequestCount = await permissionResolver.requestCount()
        expect(
            permissionRequestCount == 0,
            "permission-free Tool bypasses the permission resolver"
        )
        expect(
            runtime.handledNativeSpeechToolCallCountForTesting() == 1,
            "active speech-before-tool turn retains duplicate protection"
        )
        let outputCountBeforeBoundary = await provider.operationCount(
            .toolOutput
        )
        expect(
            outputCountBeforeBoundary == 0,
            "tool output waits for the Provider response boundary"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let outputBeforeInterimDrain = await provider.operationCount(.toolOutput)
        expect(
            outputBeforeInterimDrain == 0,
            "interim speech keeps continuation behind playback drain"
        )
        let interimPlaybackCompleted = await runtime
            .handleNativeSpeechPlaybackEvent(RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 61,
                kind: .completed
            ))
        expect(
            interimPlaybackCompleted == .applied,
            "interim playback drain releases tool continuation"
        )
        let normalOutputCount = await provider.operationCount(.toolOutput)
        let normalContinuationCount = await provider.operationCount(
            .toolContinuation
        )
        expect(
            normalOutputCount == 1,
            "completed tool output returns through Runtime and Provider"
        )
        expect(
            normalContinuationCount == 1,
            "Runtime requests one continuation response"
        )
        expect(
            runtime.handledNativeSpeechToolCallCountForTesting() == 1,
            "interim Tool segment does not trigger history cleanup"
        )
        expect(
            runtime.realtimeSpeechStateSnapshot().lastTransitionReason
                == .toolContinuationRequested,
            "tool continuation remains inside the current formal turn"
        )

        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .thinking
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputText(text: "这是正常回答", isFinal: true)
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 1,
                bytes: Data([2, 3]),
                format: .pcm16
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let continuationPlaybackStarted = await runtime
            .handleNativeSpeechPlaybackEvent(RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 62,
                kind: .started
            ))
        expect(
            continuationPlaybackStarted == .applied,
            "continuation playback starts in the same formal turn"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            (try? sessionStore.loadMostRecentDialogueEntries())?.isEmpty
                == true,
            "continuation response waits for its playback drain"
        )
        let continuationPlaybackCompleted = await runtime
            .handleNativeSpeechPlaybackEvent(RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 62,
                kind: .completed
            ))
        expect(
            continuationPlaybackCompleted == .applied,
            "continuation playback completes the formal turn"
        )
        expect(
            runtime.handledNativeSpeechToolCallCountForTesting() == 0,
            "speech-before-tool history prunes after formal playback completion"
        )
        let dialogue = try sessionStore.loadMostRecentDialogueEntries()
        expect(
            dialogue.contains { $0.text == "请使用测试工具" }
                && dialogue.contains { $0.text == "这是正常回答" },
            "completed speech turn still uses the existing dialogue chain"
        )
        expect(
            dialogue.map(\.text) == ["请使用测试工具", "这是正常回答"],
            "speech-before-tool remains interim and continuation commits once"
        )
        expect(
            !dialogue.contains {
                $0.text.contains("PRIVATE_TOOL_RESULT_DO_NOT_STORE")
                    || $0.text.contains("call-normal")
            },
            "tool payload and result stay out of Session and Memory data"
        )

        let outputsBeforeRejected = await provider.submittedToolOutputs.count
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("继续测试拒绝路径")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let rejectedRequests = [
            NativeSpeechToolRequest(
                callID: "call-malformed",
                toolName: "lookup_test_value",
                arguments: Data("not-json".utf8)
            ),
            NativeSpeechToolRequest(
                callID: "call-schema-invalid",
                toolName: "lookup_test_value",
                arguments: Data(#"{}"#.utf8)
            ),
            NativeSpeechToolRequest(
                callID: "call-unknown",
                toolName: "unknown_tool",
                arguments: Data(#"{}"#.utf8)
            )
        ]
        for rejected in rejectedRequests {
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .toolRequestCandidate(rejected)
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
        }
        let executedAfterRejected = await executor.requestCount()
        expect(
            executedAfterRejected == 1,
            "malformed and unknown calls never execute"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let rejectedOutputs = Array(
            (await provider.submittedToolOutputs).dropFirst(
                outputsBeforeRejected
            )
        )
        expect(
            rejectedOutputs.count == 3,
            "each rejected call returns one bounded error result"
        )
        let diagnosticEvents = diagnostics.drain().events
        expect(
            diagnosticEvents.contains {
                $0.category
                    == "tool_request_executed:lookup_test_value"
                    && $0.itemCorrelationHash == "safe-call-hash"
                    && $0.turnNumber != nil
                    && $0.turnGeneration != nil
            },
            "Runtime tool diagnostics include name, safe call hash, and turn identity"
        )
        let lifecycleCategories = Set(diagnosticEvents.map(\.category))
        expect(
            lifecycleCategories.contains(
                "tool_execution_scheduled:lookup_test_value"
            )
                && lifecycleCategories.contains(
                    "tool_execution_completed:lookup_test_value"
                )
                && lifecycleCategories.contains(
                    "tool_response_segment_boundary"
                )
                && lifecycleCategories.contains("tool_continuation_started")
                && lifecycleCategories.contains("tool_formal_turn_completed"),
            "Runtime emits redacted Tool lifecycle diagnostics"
        )
        expect(
            !diagnosticEvents.contains {
                $0.category.contains("alpha")
                    || $0.disposition?.contains("PRIVATE_TOOL") == true
            },
            "Runtime diagnostics contain no tool arguments or result payload"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeToolPermissionApproveAndPlayback(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let sessionStore = SessionStore()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: sessionStore
        )
        expect(
            runtime.loadDR(from: fixtureData).isLoaded,
            "permission approve resident loads"
        )
        _ = try runtime.clearDialogueTestData()
        let memoryBefore = runtime.narrativeMemoryDebugSnapshot()
        let executor = FakeNativeSpeechToolExecutor(
            output: #"{"approved":true}"#
        )
        let resolver = FakeNativeSpeechToolPermissionResolver()
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        runtime.configureNativeSpeechToolPermissionResolver(resolver)
        let diagnostics = NativeSpeechDiagnosticBuffer()
        runtime.attachNativeSpeechDiagnosticBuffer(diagnostics)
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 506
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("请执行受控测试操作")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputText(text: "这个操作需要授权", isFinal: true)
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 0,
                bytes: Data([0, 1]),
                format: .pcm16
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let playbackStarted = await runtime.handleNativeSpeechPlaybackEvent(
            RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 81,
                kind: .started
            )
        )
        expect(playbackStarted == .applied, "permission interim playback starts")
        let toolRequest = NativeSpeechToolRequest(
            callID: "call-permission-approve",
            toolName: "permission_test_action",
            arguments: Data(#"{}"#.utf8),
            correlationHash: "safe-permission-hash"
        )
        for _ in 0..<2 {
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .toolRequestCandidate(toolRequest)
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
        }
        await resolver.waitUntilRequested(count: 1)
        let permissionRequest = await resolver.request(at: 0)
        expect(
            permissionRequest.identity.turn.interactionID
                == binding.interactionID
                && permissionRequest.identity.turn.turnNumber == 1
                && permissionRequest.identity.callID
                    == "call-permission-approve"
                && permissionRequest.toolName == "permission_test_action",
            "permission request preserves the full Tool call identity"
        )
        expect(
            permissionRequest.permission == .requiresPermission
                && permissionRequest.state == .pending
                && !permissionRequest.displaySummary.contains("{}"),
            "permission request exposes only safe Runtime metadata"
        )
        let resolverCount = await resolver.requestCount()
        let executorBeforeApproval = await executor.requestCount()
        expect(
            resolverCount == 1 && executorBeforeApproval == 0,
            "duplicate candidate creates one prompt and no execution"
        )
        expect(
            runtime.pendingNativeSpeechToolPermissionCountForTesting() == 1,
            "Runtime owns one pending permission request"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 1,
                bytes: Data([2, 3]),
                format: .pcm16
            ))
        ))
        let audioWhilePending = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        guard case .accepted = audioWhilePending else {
            fatalError("FAILED: permission wait blocked realtime audio")
        }
        checks += 1
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        let boundaryWhilePending = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        guard case .accepted = boundaryWhilePending else {
            fatalError("FAILED: permission wait blocked response boundary")
        }
        checks += 1
        await resolver.decide(.approved, requestAt: 0)
        await resolver.waitUntilCompleted(count: 1)
        await runtime.waitForNativeSpeechToolPermissionTasksForTesting()
        await executor.waitUntilCompleted()
        let outputBeforePlayback = await provider.operationCount(.toolOutput)
        let continuationBeforePlayback = await provider.operationCount(
            .toolContinuation
        )
        expect(
            outputBeforePlayback == 0 && continuationBeforePlayback == 0,
            "approval cannot bypass the active playback gate"
        )
        let playbackCompleted = await runtime.handleNativeSpeechPlaybackEvent(
            RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 81,
                kind: .completed
            )
        )
        expect(
            playbackCompleted == .applied,
            "permission interim playback drains"
        )
        await provider.waitUntilToolContinuationCount(1)
        let executedAfterApproval = await executor.requestCount()
        let outputAfterPlayback = await provider.operationCount(.toolOutput)
        let continuationAfterPlayback = await provider.operationCount(
            .toolContinuation
        )
        expect(
            executedAfterApproval == 1
                && outputAfterPlayback == 1
                && continuationAfterPlayback == 1,
            "approved permission executes and continues exactly once"
        )
        await runtime.applyNativeSpeechToolPermissionDecisionForTesting(
            .approved,
            request: permissionRequest
        )
        let executedAfterDuplicateDecision = await executor.requestCount()
        let outputAfterDuplicateDecision = await provider.operationCount(
            .toolOutput
        )
        expect(
            executedAfterDuplicateDecision == 1
                && outputAfterDuplicateDecision == 1,
            "duplicate approval is ignored by Runtime"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .thinking
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputText(text: "操作已获授权并完成", isFinal: true)
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let dialogue = try sessionStore.loadMostRecentDialogueEntries()
        expect(
            dialogue.map(\.text) == [
                "请执行受控测试操作",
                "操作已获授权并完成"
            ],
            "permission state stays outside the formal Session exchange"
        )
        expect(
            !dialogue.contains {
                $0.text.contains("call-permission-approve")
                    || $0.text.contains("safe-permission-hash")
                    || $0.text.contains("approved")
            },
            "permission identity and decision never enter Session dialogue"
        )
        expect(
            runtime.narrativeMemoryDebugSnapshot() == memoryBefore,
            "permission request and decision never enter narrative memory"
        )
        let permissionDiagnostics = diagnostics.drain().events
        let diagnosticCategories = Set(permissionDiagnostics.map(\.category))
        expect(
            diagnosticCategories.contains(
                "tool_permission_requested:permission_test_action"
            )
                && diagnosticCategories.contains(
                    "tool_permission_approved:permission_test_action"
                )
                && diagnosticCategories.contains(
                    "tool_permission_duplicate:permission_test_action"
                ),
            "permission lifecycle emits redacted Runtime diagnostics"
        )
        expect(
            !permissionDiagnostics.contains {
                $0.category.contains("call-permission-approve")
                    || $0.disposition?.contains("{}") == true
            },
            "permission diagnostics contain no call ID or arguments"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeToolPermissionRejections(
        fixtureData: Data
    ) async throws {
        try await assertRuntimeToolPermissionRejection(
            fixtureData: fixtureData,
            decision: .denied,
            expectedCode: "permission_denied",
            expectedDiagnostic: "tool_permission_denied"
        )
        try await assertRuntimeToolPermissionRejection(
            fixtureData: fixtureData,
            decision: nil,
            expectedCode: "permission_unavailable",
            expectedDiagnostic: "tool_permission_unavailable"
        )
    }

    private static func assertRuntimeToolPermissionRejection(
        fixtureData: Data,
        decision: NativeSpeechToolPermissionDecision?,
        expectedCode: String,
        expectedDiagnostic: String
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(
            runtime.loadDR(from: fixtureData).isLoaded,
            "permission rejection resident loads"
        )
        let executor = FakeNativeSpeechToolExecutor(output: #"{"bad":true}"#)
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        let resolver: FakeNativeSpeechToolPermissionResolver?
        if let decision {
            let configured = FakeNativeSpeechToolPermissionResolver(
                automaticDecision: decision
            )
            runtime.configureNativeSpeechToolPermissionResolver(configured)
            resolver = configured
        } else {
            resolver = nil
        }
        let diagnostics = NativeSpeechDiagnosticBuffer()
        runtime.attachNativeSpeechDiagnosticBuffer(diagnostics)
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: decision == nil ? 508 : 507
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("测试一次性工具授权拒绝")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .toolRequestCandidate(NativeSpeechToolRequest(
                callID: "call-\(expectedCode)",
                toolName: "permission_test_action",
                arguments: Data(#"{}"#.utf8)
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        if let resolver {
            await resolver.waitUntilRequested(count: 1)
            await resolver.waitUntilCompleted(count: 1)
        }
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.waitUntilToolContinuationCount(1)
        let executedCount = await executor.requestCount()
        let outputCount = await provider.operationCount(.toolOutput)
        let continuationCount = await provider.operationCount(
            .toolContinuation
        )
        expect(
            executedCount == 0,
            "denied or unavailable permission never executes Tool"
        )
        expect(
            outputCount == 1 && continuationCount == 1,
            "permission rejection returns and continues exactly once "
                + "(output=\(outputCount), continuation=\(continuationCount))"
        )
        expect(
            runtime.nativeSpeechToolPermissionTaskCountForTesting() == 0,
            "completed permission task state is released"
        )
        let outputs = await provider.submittedToolOutputs
        expect(
            outputs.count == 1
                && outputs[0].output.contains(expectedCode),
            "permission rejection returns a bounded Runtime error"
        )
        let diagnosticCategories = diagnostics.drain().events.map(\.category)
        expect(
            diagnosticCategories.contains {
                $0 == "\(expectedDiagnostic):permission_test_action"
            },
            "permission rejection emits its safe diagnostic"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeToolPermissionInterrupt(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(
            runtime.loadDR(from: fixtureData).isLoaded,
            "permission interrupt resident loads"
        )
        let executor = FakeNativeSpeechToolExecutor(output: #"{"late":true}"#)
        let resolver = FakeNativeSpeechToolPermissionResolver()
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        runtime.configureNativeSpeechToolPermissionResolver(resolver)
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 509
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("这个授权会被中断")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .toolRequestCandidate(NativeSpeechToolRequest(
                callID: "call-permission-stale",
                toolName: "permission_test_action",
                arguments: Data(#"{}"#.utf8)
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await resolver.waitUntilRequested(count: 1)
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 0,
                bytes: Data([0, 1]),
                format: .pcm16
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let generationBeforeInterrupt = runtime
            .realtimeSpeechSubtitleSnapshot().turnGeneration
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .inputSpeechStarted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            runtime.realtimeSpeechSubtitleSnapshot().turnGeneration
                > generationBeforeInterrupt,
            "permission Interrupt advances generation"
        )
        expect(
            runtime.pendingNativeSpeechToolPermissionCountForTesting() == 0,
            "Interrupt marks the pending permission stale"
        )
        _ = try await commitPendingInterrupt(runtime: runtime, binding: binding)
        await resolver.decide(.approved, requestAt: 0)
        await resolver.waitUntilCompleted(count: 1)
        await runtime.waitForNativeSpeechToolPermissionTasksForTesting()
        let executedCount = await executor.requestCount()
        let outputCount = await provider.operationCount(.toolOutput)
        let continuationCount = await provider.operationCount(
            .toolContinuation
        )
        expect(
            executedCount == 0,
            "late approval cannot execute a stale generation"
        )
        expect(
            outputCount == 0 && continuationCount == 0,
            "late approval cannot restore output or continuation"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeToolPermissionAcrossTurns(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(
            runtime.loadDR(from: fixtureData).isLoaded,
            "permission multi-turn resident loads"
        )
        let executor = FakeNativeSpeechToolExecutor(output: #"{"ok":true}"#)
        let resolver = FakeNativeSpeechToolPermissionResolver(
            automaticDecision: .approved
        )
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        runtime.configureNativeSpeechToolPermissionResolver(resolver)
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 510
        )
        for turn in 1...2 {
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .finalTranscript("一次性授权轮次 \(turn)")
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .toolRequestCandidate(NativeSpeechToolRequest(
                    callID: "call-permission-repeat",
                    toolName: "permission_test_action",
                    arguments: Data(#"{}"#.utf8)
                ))
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            await resolver.waitUntilRequested(count: turn)
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .responseCompleted
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            await executor.waitUntilCompleted(count: turn)
            await provider.waitUntilToolContinuationCount(turn)
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .thinking
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .outputText(
                    text: "一次性授权回答 \(turn)",
                    isFinal: true
                )
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .responseCompleted
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
        }
        let permissionCount = await resolver.requestCount()
        let executionCount = await executor.requestCount()
        expect(
            permissionCount == 2 && executionCount == 2,
            "same Tool and callID require fresh approval in each formal turn"
        )
        let requests = await resolver.requests
        expect(
            requests[0].identity.turn != requests[1].identity.turn,
            "permission identity changes with formal turn and generation"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeMultipleToolPermissions(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(
            runtime.loadDR(from: fixtureData).isLoaded,
            "multiple Tool permission resident loads"
        )
        let executor = FakeNativeSpeechToolExecutor(output: #"{"ok":true}"#)
        let resolver = FakeNativeSpeechToolPermissionResolver()
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        runtime.configureNativeSpeechToolPermissionResolver(resolver)
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 511
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("同一轮执行两个工具")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let requests = [
            NativeSpeechToolRequest(
                callID: "call-free-multiple",
                toolName: "lookup_test_value",
                arguments: Data(#"{"key":"free"}"#.utf8)
            ),
            NativeSpeechToolRequest(
                callID: "call-permission-multiple",
                toolName: "permission_test_action",
                arguments: Data(#"{}"#.utf8)
            )
        ]
        for request in requests {
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .toolRequestCandidate(request)
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
        }
        await executor.waitUntilCompleted(count: 1)
        await resolver.waitUntilRequested(count: 1)
        let executionBeforeApproval = await executor.requestCount()
        expect(
            executionBeforeApproval == 1,
            "permission-free Tool runs while the other permission is pending"
        )
        expect(
            runtime.pendingNativeSpeechToolPermissionCountForTesting() == 1,
            "multiple-call turn retains one bounded permission request"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let continuationBeforeApproval = await provider.operationCount(
            .toolContinuation
        )
        expect(
            continuationBeforeApproval == 0,
            "response continuation waits for every Tool call"
        )
        await resolver.decide(.approved, requestAt: 0)
        await resolver.waitUntilCompleted(count: 1)
        await runtime.waitForNativeSpeechToolPermissionTasksForTesting()
        await executor.waitUntilCompleted(count: 2)
        await provider.waitUntilToolContinuationCount(1)
        let executionAfterApproval = await executor.requestCount()
        let outputCount = await provider.operationCount(.toolOutput)
        let continuationCount = await provider.operationCount(
            .toolContinuation
        )
        expect(
            executionAfterApproval == 2 && outputCount == 2,
            "independent Tool calls each execute and produce one output"
        )
        expect(
            continuationCount == 1,
            "multiple Tool outputs create one continuation"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeToolCallHistoryBounded(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let sessionStore = SessionStore()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: sessionStore
        )
        expect(
            runtime.loadDR(from: fixtureData).isLoaded,
            "bounded tool resident loads"
        )
        _ = try runtime.clearDialogueTestData()
        let executor = FakeNativeSpeechToolExecutor(output: #"{"ok":true}"#)
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 504
        )
        let turnCount = 24
        for turn in 1...turnCount {
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .finalTranscript("长期工具轮次 \(turn)")
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            let request = NativeSpeechToolRequest(
                callID: "call-repeat",
                toolName: "lookup_test_value",
                arguments: Data(#"{"key":"bounded"}"#.utf8)
            )
            for _ in 0..<2 {
                await provider.enqueue(NativeSpeechEvent(
                    interactionID: binding.interactionID,
                    kind: .toolRequestCandidate(request)
                ))
                _ = try await runtime.receiveNativeSpeechEvent(
                    interactionID: binding.interactionID
                )
            }
            await executor.waitUntilCompleted(count: turn)
            expect(
                runtime.handledNativeSpeechToolCallCountForTesting() == 1,
                "active turn retains one deduplicated Tool identity"
            )
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .responseCompleted
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            await provider.waitUntilToolContinuationCount(turn)
            expect(
                runtime.handledNativeSpeechToolCallCountForTesting() == 1,
                "Tool segment boundary does not prune the formal turn"
            )
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .thinking
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .outputText(
                    text: "长期工具回答 \(turn)",
                    isFinal: true
                )
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            await provider.enqueue(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .responseCompleted
            ))
            _ = try await runtime.receiveNativeSpeechEvent(
                interactionID: binding.interactionID
            )
            expect(
                runtime.handledNativeSpeechToolCallCountForTesting() == 0,
                "formal completion prunes completed Tool identities"
            )
        }
        let executedCount = await executor.requestCount()
        let outputCount = await provider.operationCount(.toolOutput)
        let continuationCount = await provider.operationCount(
            .toolContinuation
        )
        expect(
            executedCount == turnCount,
            "same callID executes once per formal turn"
        )
        expect(
            outputCount == turnCount,
            "each long-interaction Tool turn submits one output"
        )
        expect(
            continuationCount == turnCount,
            "each long-interaction Tool turn continues once"
        )
        expect(
            runtime.realtimeSpeechStateSnapshot().completedTurnCount
                == UInt64(turnCount),
            "long Tool interaction completes every formal turn"
        )
        let dialogue = try sessionStore.loadMostRecentDialogueEntries()
        expect(
            dialogue.count == RuntimeCore.recentDialogueMessageLimit,
            "long Tool interaction preserves the bounded Session window"
        )
        expect(
            dialogue.suffix(2).map(\.text) == [
                "长期工具轮次 \(turnCount)",
                "长期工具回答 \(turnCount)"
            ],
            "long Tool interaction retains the final formal exchange"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimePendingToolCallRetention(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let sessionStore = SessionStore()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: sessionStore
        )
        expect(
            runtime.loadDR(from: fixtureData).isLoaded,
            "pending tool resident loads"
        )
        let executor = FakeNativeSpeechToolExecutor(
            output: #"{"ok":true}"#,
            suspends: true
        )
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 505
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("等待工具完成")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .toolRequestCandidate(NativeSpeechToolRequest(
                callID: "call-pending",
                toolName: "lookup_test_value",
                arguments: Data(#"{"key":"pending"}"#.utf8)
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await executor.waitUntilStarted()
        expect(
            runtime.handledNativeSpeechToolCallCountForTesting() == 1,
            "pending current task retains its Tool identity"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            runtime.handledNativeSpeechToolCallCountForTesting() == 1,
            "response segment boundary cannot prune a pending Tool identity"
        )
        await executor.resume()
        await executor.waitUntilCompleted()
        await provider.waitUntilToolContinuationCount(1)
        expect(
            runtime.handledNativeSpeechToolCallCountForTesting() == 1,
            "continuation keeps Tool identity until formal completion"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .thinking
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputText(text: "工具已完成", isFinal: true)
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            runtime.handledNativeSpeechToolCallCountForTesting() == 0,
            "pending Tool identity is pruned only after formal completion"
        )
        let executedCount = await executor.requestCount()
        expect(
            executedCount == 1,
            "retained pending Tool executes exactly once"
        )
        expect(
            (try? sessionStore.loadMostRecentDialogueEntries())?.count == 2,
            "pending Tool turn commits one formal Session exchange"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeToolPlaybackGate(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixtureData).isLoaded, "tool playback resident loads")
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: FakeNativeSpeechToolExecutor(output: #"{"ok":true}"#)
        )
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 502
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("带音频的工具轮次")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 0,
                bytes: Data([0, 1]),
                format: .pcm16
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let playbackStarted = await runtime.handleNativeSpeechPlaybackEvent(
            RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 77,
                kind: .started
            )
        )
        expect(
            playbackStarted == .applied,
            "tool turn playback starts"
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .toolRequestCandidate(NativeSpeechToolRequest(
                callID: "call-playback",
                toolName: "lookup_test_value",
                arguments: Data(#"{"key":"beta"}"#.utf8)
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        let outputBeforeDrain = await provider.operationCount(.toolOutput)
        let continuationBeforeDrain = await provider.operationCount(
            .toolContinuation
        )
        expect(
            outputBeforeDrain == 0 && continuationBeforeDrain == 0,
            "response boundary cannot overlap active playback"
        )
        let playbackCompleted = await runtime.handleNativeSpeechPlaybackEvent(
            RealtimeSpeechPlaybackEvent(
                interactionID: binding.interactionID,
                turnNumber: 1,
                playbackGeneration: 77,
                kind: .completed
            )
        )
        expect(
            playbackCompleted == .applied,
            "actual playback completion drains the gate"
        )
        let outputAfterDrain = await provider.operationCount(.toolOutput)
        let continuationAfterDrain = await provider.operationCount(
            .toolContinuation
        )
        expect(
            outputAfterDrain == 1 && continuationAfterDrain == 1,
            "tool output and response.create continue only after playback drain"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func testRuntimeStaleToolResult(
        fixtureData: Data
    ) async throws {
        let provider = FakeNativeSpeechProvider()
        let runtime = configuredRuntime(
            provider: provider,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixtureData).isLoaded, "stale tool resident loads")
        let executor = FakeNativeSpeechToolExecutor(
            output: #"{"late":true}"#,
            suspends: true
        )
        runtime.configureNativeSpeechToolsForTesting(
            definitions: nativeSpeechToolDefinitions(),
            executor: executor
        )
        let binding = try await runtime.startNativeSpeechInput(
            captureGeneration: 503
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .finalTranscript("会被中断的工具轮次")
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .toolRequestCandidate(NativeSpeechToolRequest(
                callID: "call-stale",
                toolName: "lookup_test_value",
                arguments: Data(#"{"key":"late"}"#.utf8)
            ))
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        await executor.waitUntilStarted()
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .outputAudio(NativeSpeechAudioPayload(
                interactionID: binding.interactionID,
                sequenceNumber: 0,
                bytes: Data([0, 1]),
                format: .pcm16
            ))
        ))
        let audioWhileSuspended = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        guard case .accepted = audioWhileSuspended else {
            fatalError("FAILED: suspended executor blocked output audio")
        }
        checks += 1
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .responseCompleted
        ))
        let whileSuspended = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            whileSuspended == .accepted(NativeSpeechEvent(
                interactionID: binding.interactionID,
                kind: .responseCompleted
            )),
            "suspended tool execution does not block response boundary receive"
        )
        let generationBeforeInterrupt = runtime
            .realtimeSpeechSubtitleSnapshot().turnGeneration
        await provider.enqueue(NativeSpeechEvent(
            interactionID: binding.interactionID,
            kind: .inputSpeechStarted
        ))
        _ = try await runtime.receiveNativeSpeechEvent(
            interactionID: binding.interactionID
        )
        expect(
            runtime.realtimeSpeechSubtitleSnapshot().turnGeneration
                > generationBeforeInterrupt,
            "Interrupt advances generation while executor remains suspended"
        )
        expect(
            runtime.handledNativeSpeechToolCallCountForTesting() == 0,
            "Interrupt prunes the stale Tool identity"
        )
        _ = try await commitPendingInterrupt(runtime: runtime, binding: binding)
        await executor.resume()
        await executor.waitUntilCompleted()
        let staleOutputCount = await provider.operationCount(.toolOutput)
        let staleContinuationCount = await provider.operationCount(
            .toolContinuation
        )
        expect(
            staleOutputCount == 0,
            "stale generation result is discarded after interrupt"
        )
        expect(
            staleContinuationCount == 0,
            "stale generation cannot create a new response"
        )
        try await runtime.stopNativeSpeechInput(
            binding: binding,
            reason: .stopped
        )
    }

    private static func nativeSpeechToolDefinitions()
        -> [NativeSpeechToolDefinition] {
        let parameters = Data(
            #"{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}"#.utf8
        )
        return [
            NativeSpeechToolDefinition(
                name: "lookup_test_value",
                description: "Returns a deterministic test value.",
                parametersJSON: parameters,
                permission: .permissionFree
            ),
            NativeSpeechToolDefinition(
                name: "permission_test_action",
                description: "Must never execute without permission.",
                parametersJSON: Data(#"{"type":"object"}"#.utf8),
                permission: .requiresPermission
            )
        ]
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
            expect(
                runtime.handledNativeSpeechToolCallCountForTesting() == 0,
                "ordinary no-Tool turn retains no Tool history"
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
