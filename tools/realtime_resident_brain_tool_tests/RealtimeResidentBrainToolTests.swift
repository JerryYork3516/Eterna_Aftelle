import Foundation

private struct R5CredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        nil
    }
}

private actor R5RealtimeProvider: RealtimeResidentBrainProvider {
    private var events: [RealtimeResidentBrainEvent] = []
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var toolResults: [RealtimeBrainToolResultCommand] = []
    private var interruptCommands: [RealtimeBrainInterruptCommand] = []
    private var closeCommands: [RealtimeBrainCloseSessionCommand] = []
    private var resultWaiters:
        [Int: [CheckedContinuation<Void, Never>]] = [:]

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        openCommands.append(command)
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {}

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {}

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {
        toolResults.append(command)
        resumeResultWaiters()
    }

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {}

    func interrupt(
        _ command: RealtimeBrainInterruptCommand
    ) async throws {
        interruptCommands.append(command)
    }

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

    func waitUntilToolResultCount(_ count: Int) async {
        guard toolResults.count < count else { return }
        await withCheckedContinuation { continuation in
            if toolResults.count >= count {
                continuation.resume()
            } else {
                resultWaiters[count, default: []].append(continuation)
            }
        }
    }

    func recordedOpenCommands() -> [RealtimeBrainOpenSessionCommand] {
        openCommands
    }

    func recordedToolResults() -> [RealtimeBrainToolResultCommand] {
        toolResults
    }

    func interruptCount() -> Int {
        interruptCommands.count
    }

    private func resumeResultWaiters() {
        let ready = resultWaiters.keys.filter { $0 <= toolResults.count }
        for count in ready {
            resultWaiters.removeValue(forKey: count)?.forEach {
                $0.resume()
            }
        }
    }
}

private enum R5ToolBehavior: Sendable {
    case success(String)
    case failure
    case held(String)
}

private enum R5ToolFailure: Error {
    case failed
}

private actor R5ToolExecutor: RuntimeToolExecuting {
    private var behaviors: [String: R5ToolBehavior] = [:]
    private var requests: [RuntimeToolExecutionRequest] = []
    private var heldExecutions:
        [String: CheckedContinuation<String, Never>] = [:]
    private var requestWaiters:
        [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var completedCount = 0
    private var completionWaiters:
        [Int: [CheckedContinuation<Void, Never>]] = [:]

    func execute(
        _ request: RuntimeToolExecutionRequest
    ) async throws -> String {
        let behavior = behaviors[request.identity.callID]
            ?? .success(#"{"ok":true}"#)
        switch behavior {
        case .success(let output):
            publish(request)
            markCompleted()
            return output
        case .failure:
            publish(request)
            markCompleted()
            throw R5ToolFailure.failed
        case .held:
            let output = await withCheckedContinuation { continuation in
                heldExecutions[request.identity.callID] = continuation
                publish(request)
            }
            markCompleted()
            return output
        }
    }

    func setBehavior(_ behavior: R5ToolBehavior, callID: String) {
        behaviors[callID] = behavior
    }

    func resume(callID: String) {
        guard case .held(let output) = behaviors[callID] else {
            fatalError("Tool execution is not configured as held")
        }
        guard let continuation = heldExecutions.removeValue(
            forKey: callID
        ) else {
            fatalError("held Tool execution resumed before it was ready")
        }
        continuation.resume(returning: output)
    }

    func waitUntilRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            if requests.count >= count {
                continuation.resume()
            } else {
                requestWaiters[count, default: []].append(continuation)
            }
        }
    }

    func waitUntilCompletedCount(_ count: Int) async {
        guard completedCount < count else { return }
        await withCheckedContinuation { continuation in
            if completedCount >= count {
                continuation.resume()
            } else {
                completionWaiters[count, default: []].append(continuation)
            }
        }
    }

    func requestCount() -> Int {
        requests.count
    }

    func recordedRequests() -> [RuntimeToolExecutionRequest] {
        requests
    }

    private func publish(_ request: RuntimeToolExecutionRequest) {
        requests.append(request)
        resumeRequestWaiters()
    }

    private func markCompleted() {
        completedCount += 1
        let ready = completionWaiters.keys.filter { $0 <= completedCount }
        for count in ready {
            completionWaiters.removeValue(forKey: count)?.forEach {
                $0.resume()
            }
        }
    }

    private func resumeRequestWaiters() {
        let ready = requestWaiters.keys.filter { $0 <= requests.count }
        for count in ready {
            requestWaiters.removeValue(forKey: count)?.forEach {
                $0.resume()
            }
        }
    }
}

private actor R5PermissionResolver: RuntimeToolPermissionResolving {
    private var requests: [RuntimeToolPermissionRequest] = []
    private var continuations: [
        RuntimeToolCallIdentity:
            CheckedContinuation<RuntimeToolPermissionDecision, Never>
    ] = [:]
    private var requestWaiters:
        [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var completedCount = 0
    private var completionWaiters:
        [Int: [CheckedContinuation<Void, Never>]] = [:]

    func resolve(
        _ request: RuntimeToolPermissionRequest
    ) async -> RuntimeToolPermissionDecision {
        let decision = await withCheckedContinuation { continuation in
            continuations[request.identity] = continuation
            requests.append(request)
            resumeRequestWaiters()
        }
        completedCount += 1
        resumeCompletionWaiters()
        return decision
    }

    func decide(
        _ decision: RuntimeToolPermissionDecision,
        requestAt index: Int
    ) {
        let identity = requests[index].identity
        guard let continuation = continuations.removeValue(
            forKey: identity
        ) else {
            fatalError("permission decision requested before resolver was ready")
        }
        continuation.resume(returning: decision)
    }

    func waitUntilRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            if requests.count >= count {
                continuation.resume()
            } else {
                requestWaiters[count, default: []].append(continuation)
            }
        }
    }

    func waitUntilCompletedCount(_ count: Int) async {
        guard completedCount < count else { return }
        await withCheckedContinuation { continuation in
            if completedCount >= count {
                continuation.resume()
            } else {
                completionWaiters[count, default: []].append(continuation)
            }
        }
    }

    func request(at index: Int) -> RuntimeToolPermissionRequest {
        requests[index]
    }

    func requestCount() -> Int {
        requests.count
    }

    private func resumeRequestWaiters() {
        let ready = requestWaiters.keys.filter { $0 <= requests.count }
        for count in ready {
            requestWaiters.removeValue(forKey: count)?.forEach {
                $0.resume()
            }
        }
    }

    private func resumeCompletionWaiters() {
        let ready = completionWaiters.keys.filter { $0 <= completedCount }
        for count in ready {
            completionWaiters.removeValue(forKey: count)?.forEach {
                $0.resume()
            }
        }
    }
}

private struct R5Stack {
    let runtime: RuntimeCore
    let provider: R5RealtimeProvider
    let executor: R5ToolExecutor
    let identity: RealtimeBrainSessionIdentity
}

@main
@MainActor
private struct RealtimeResidentBrainToolTests {
    private static var checks = 0
    private static var cases = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        try await testValidCandidateUsesRuntimeKernel(fixture: fixture)
        try await testValidationRejectsBeforeExecution(fixture: fixture)
        try await testPermissionIsRuntimeOwned(fixture: fixture)
        try await testFailureTimeoutAndDuplicateSettleOnce(fixture: fixture)
        try await testConcurrentCallsCorrelateOutOfOrder(fixture: fixture)
        try await testWrongAndDuplicateResultsNeverReachProvider(
            fixture: fixture
        )
        try await testInterruptInvalidatesPendingWork(fixture: fixture)

        print("realtime_resident_brain_tool_cases=\(cases)")
        print("realtime_resident_brain_tool_checks=\(checks)")
    }

    private static func testValidCandidateUsesRuntimeKernel(
        fixture: Data
    ) async throws {
        cases += 1
        let resolver = R5PermissionResolver()
        let stack = try await configuredStack(
            fixture: fixture,
            permissionResolver: resolver
        )
        let callID = "call-valid"
        await stack.executor.setBehavior(
            .success(#"{"value":"shared-kernel"}"#),
            callID: callID
        )
        let identity = eventIdentity(session: stack.identity)
        let event = toolEvent(
            identity: identity,
            sequence: 1,
            callID: callID,
            toolName: "lookup_test_value",
            arguments: #"{"key":"alpha"}"#
        )
        expectAccepted(
            try await receive(event, stack: stack),
            equals: event,
            "valid Realtime candidate is accepted"
        )
        await stack.executor.waitUntilRequestCount(1)
        await stack.provider.waitUntilToolResultCount(1)

        let opens = await stack.provider.recordedOpenCommands()
        expect(
            opens.count == 1
                && opens[0].tools.map(\.name) == toolDefinitions().map(\.name),
            "Runtime advertises its single Tool registry to Realtime"
        )
        let permissionRequestCount = await resolver.requestCount()
        expect(
            permissionRequestCount == 0,
            "permission-free Tool does not enter permission resolution"
        )
        let request = (await stack.executor.recordedRequests())[0]
        expect(
            request.identity.realtimeIdentity == identity
                && request.identity.callID == callID
                && request.toolName == "lookup_test_value"
                && request.arguments == Data(#"{"key":"alpha"}"#.utf8),
            "shared executor receives the full Realtime identity and arguments"
        )
        let result = (await stack.provider.recordedToolResults())[0]
        expect(
            result.identity == identity
                && result.callID.rawValue == callID
                && result.sequence == 1
                && result.output.contains("shared-kernel")
                && !result.isError,
            "Runtime correlates the successful result to the candidate"
        )
        let audit = stack.runtime.runtimeToolAuditRecordsForTesting()
        expect(
            audit.contains {
                $0.route == "realtime_resident_brain"
                    && $0.category == "tool_result_submitted"
                    && $0.toolName == "lookup_test_value"
                    && $0.generation == stack.identity.generation
            },
            "Runtime owns a route-neutral Realtime Tool audit"
        )
        try await close(stack.runtime, identity: stack.identity)
    }

    private static func testValidationRejectsBeforeExecution(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await configuredStack(
            fixture: fixture,
            permissionResolver: nil
        )
        let invalidCalls: [(String, String, String, String)] = [
            ("call-unknown", "missing_tool", #"{}"#, "unknown_tool"),
            ("call-malformed", "lookup_test_value", "not-json",
             "invalid_arguments"),
            ("call-schema", "lookup_test_value", #"{}"#,
             "invalid_arguments"),
            ("call-no-permission", "permission_test_action", #"{}"#,
             "permission_unavailable")
        ]
        for (offset, item) in invalidCalls.enumerated() {
            let event = toolEvent(
                identity: eventIdentity(session: stack.identity),
                sequence: UInt64(offset + 1),
                callID: item.0,
                toolName: item.1,
                arguments: item.2
            )
            expectAccepted(
                try await receive(event, stack: stack),
                equals: event,
                "invalid Tool request reaches Runtime validation"
            )
            await stack.provider.waitUntilToolResultCount(offset + 1)
        }
        let invalidExecutionCount = await stack.executor.requestCount()
        expect(
            invalidExecutionCount == 0,
            "unknown, malformed, schema-invalid, and unauthorized calls do not execute"
        )
        let invalidResults = await stack.provider.recordedToolResults()
        expect(
            zip(invalidResults, invalidCalls).allSatisfy {
                $0.0.isError && $0.0.output.contains($0.1.3)
            },
            "every validation failure returns one bounded Runtime error"
        )
        try await close(stack.runtime, identity: stack.identity)

        let staleResolver = R5PermissionResolver()
        let stale = try await configuredStack(
            fixture: fixture,
            permissionResolver: staleResolver
        )
        let staleSessions = [
            copySession(stale.identity, brainLeaseID: UUID()),
            copySession(
                stale.identity,
                routeEpoch: stale.identity.routeEpoch &+ 1
            ),
            copySession(
                stale.identity,
                generation: stale.identity.generation &+ 1
            )
        ]
        for (offset, session) in staleSessions.enumerated() {
            let event = toolEvent(
                identity: eventIdentity(session: session),
                sequence: 1,
                callID: "call-stale-\(offset)",
                toolName: "lookup_test_value",
                arguments: #"{"key":"stale"}"#
            )
            let disposition = try await receive(event, stack: stale)
            expect(
                disposition == .rejectedStale,
                "stale lease, epoch, or generation is rejected"
            )
        }
        let staleExecutionCount = await stale.executor.requestCount()
        let stalePermissionCount = await staleResolver.requestCount()
        let staleResults = await stale.provider.recordedToolResults()
        expect(
            staleExecutionCount == 0
                && stalePermissionCount == 0
                && staleResults.isEmpty,
            "stale candidates have no permission, execution, or result side effect"
        )
        try await close(stale.runtime, identity: stale.identity)

        let structural = try await configuredStack(
            fixture: fixture,
            permissionResolver: R5PermissionResolver()
        )
        let validIdentity = eventIdentity(session: structural.identity)
        let emptyCall = toolEvent(
            identity: validIdentity,
            sequence: 1,
            callID: "",
            toolName: "lookup_test_value",
            arguments: #"{"key":"x"}"#
        )
        let emptyCallDisposition = try await receive(
            emptyCall,
            stack: structural
        )
        expect(
            emptyCallDisposition == .rejectedInvalidEvent,
            "empty callID is structurally invalid"
        )
        let missingTurn = RealtimeBrainEventIdentity(
            session: structural.identity,
            turnID: nil,
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let missingTurnEvent = toolEvent(
            identity: missingTurn,
            sequence: 2,
            callID: "call-no-turn",
            toolName: "lookup_test_value",
            arguments: #"{"key":"x"}"#
        )
        let missingTurnDisposition = try await receive(
            missingTurnEvent,
            stack: structural
        )
        expect(
            missingTurnDisposition == .rejectedInvalidIdentity,
            "Tool candidate requires a turn identity"
        )
        let missingResponse = RealtimeBrainEventIdentity(
            session: structural.identity,
            turnID: RealtimeBrainTurnID(),
            responseID: nil,
            contextRevision: 1
        )
        let missingResponseEvent = toolEvent(
            identity: missingResponse,
            sequence: 3,
            callID: "call-no-response",
            toolName: "lookup_test_value",
            arguments: #"{"key":"x"}"#
        )
        let missingResponseDisposition = try await receive(
            missingResponseEvent,
            stack: structural
        )
        expect(
            missingResponseDisposition == .rejectedInvalidIdentity,
            "Tool candidate requires a response identity"
        )
        let structuralExecutionCount = await structural.executor.requestCount()
        let structuralResults = await structural.provider
            .recordedToolResults()
        expect(
            structuralExecutionCount == 0 && structuralResults.isEmpty,
            "structurally invalid candidates never reach the Tool kernel"
        )
        try await close(structural.runtime, identity: structural.identity)
    }

    private static func testPermissionIsRuntimeOwned(
        fixture: Data
    ) async throws {
        cases += 1
        let approvedResolver = R5PermissionResolver()
        let approved = try await configuredStack(
            fixture: fixture,
            permissionResolver: approvedResolver
        )
        let approvedIdentity = eventIdentity(session: approved.identity)
        let approvedEvent = toolEvent(
            identity: approvedIdentity,
            sequence: 1,
            callID: "call-permission-approved",
            toolName: "permission_test_action",
            arguments: #"{}"#
        )
        expectAccepted(
            try await receive(approvedEvent, stack: approved),
            equals: approvedEvent,
            "permission-gated candidate is accepted for Runtime review"
        )
        await approvedResolver.waitUntilRequestCount(1)
        let permission = await approvedResolver.request(at: 0)
        let counts = approved.runtime.runtimeToolLifecycleCountsForTesting()
        let pendingExecutionCount = await approved.executor.requestCount()
        let pendingResults = await approved.provider.recordedToolResults()
        expect(
            permission.identity.realtimeIdentity == approvedIdentity
                && permission.identity.callID == "call-permission-approved"
                && permission.permission == .requiresPermission
                && permission.state == .pending
                && !permission.displaySummary.contains("{}"),
            "Runtime creates a safe, fully correlated confirmation request"
        )
        expect(
            counts.pendingPermissions == 1
                && pendingExecutionCount == 0
                && pendingResults.isEmpty,
            "confirmation remains pending without execution or result"
        )
        await approvedResolver.decide(.approved, requestAt: 0)
        await approvedResolver.waitUntilCompletedCount(1)
        await approved.provider.waitUntilToolResultCount(1)
        let approvedExecutionCount = await approved.executor.requestCount()
        let approvedResults = await approved.provider.recordedToolResults()
        expect(
            approvedExecutionCount == 1 && !approvedResults[0].isError,
            "Runtime-approved permission executes exactly once"
        )
        try await close(approved.runtime, identity: approved.identity)

        let deniedResolver = R5PermissionResolver()
        let denied = try await configuredStack(
            fixture: fixture,
            permissionResolver: deniedResolver
        )
        let deniedEvent = toolEvent(
            identity: eventIdentity(session: denied.identity),
            sequence: 1,
            callID: "call-permission-denied",
            toolName: "permission_test_action",
            arguments: #"{}"#
        )
        expectAccepted(
            try await receive(deniedEvent, stack: denied),
            equals: deniedEvent,
            "denied permission fixture accepts the candidate"
        )
        await deniedResolver.waitUntilRequestCount(1)
        await deniedResolver.decide(.denied, requestAt: 0)
        await deniedResolver.waitUntilCompletedCount(1)
        await denied.provider.waitUntilToolResultCount(1)
        let deniedResult = (await denied.provider.recordedToolResults())[0]
        let deniedExecutionCount = await denied.executor.requestCount()
        expect(
            deniedExecutionCount == 0
                && deniedResult.isError
                && deniedResult.output.contains("permission_denied"),
            "Runtime denial returns one error without execution"
        )
        try await close(denied.runtime, identity: denied.identity)
    }

    private static func testFailureTimeoutAndDuplicateSettleOnce(
        fixture: Data
    ) async throws {
        cases += 1
        let failed = try await configuredStack(
            fixture: fixture,
            permissionResolver: R5PermissionResolver()
        )
        await failed.executor.setBehavior(.failure, callID: "call-failed")
        let failedEvent = toolEvent(
            identity: eventIdentity(session: failed.identity),
            sequence: 1,
            callID: "call-failed",
            toolName: "lookup_test_value",
            arguments: #"{"key":"failure"}"#
        )
        expectAccepted(
            try await receive(failedEvent, stack: failed),
            equals: failedEvent,
            "failing executor fixture accepts the candidate"
        )
        await failed.provider.waitUntilToolResultCount(1)
        let failedResult = (await failed.provider.recordedToolResults())[0]
        expect(
            failedResult.isError
                && failedResult.output.contains("execution_failed"),
            "executor failure settles as one bounded error result"
        )
        try await close(failed.runtime, identity: failed.identity)

        let timedOut = try await configuredStack(
            fixture: fixture,
            permissionResolver: R5PermissionResolver()
        )
        await timedOut.executor.setBehavior(
            .held(#"{"late":true}"#),
            callID: "call-timeout"
        )
        let timeoutEvent = toolEvent(
            identity: eventIdentity(session: timedOut.identity),
            sequence: 1,
            callID: "call-timeout",
            toolName: "timeout_test_value",
            arguments: #"{"key":"timeout"}"#
        )
        expectAccepted(
            try await receive(timeoutEvent, stack: timedOut),
            equals: timeoutEvent,
            "timeout fixture accepts the candidate"
        )
        await timedOut.executor.waitUntilRequestCount(1)
        await timedOut.provider.waitUntilToolResultCount(1)
        let timeoutResult = (await timedOut.provider.recordedToolResults())[0]
        expect(
            timeoutResult.isError
                && timeoutResult.output.contains("execution_timeout"),
            "Runtime Tool timeout settles independently of the executor"
        )
        await timedOut.executor.resume(callID: "call-timeout")
        await timedOut.executor.waitUntilCompletedCount(1)
        await Task.yield()
        let timeoutResultCount = await timedOut.provider
            .recordedToolResults().count
        expect(
            timeoutResultCount == 1,
            "late completion after timeout cannot submit a second result"
        )
        expect(
            timedOut.runtime.runtimeToolAuditRecordsForTesting().contains {
                $0.category == "tool_execution_timeout"
                    && $0.route == "realtime_resident_brain"
            },
            "Runtime audits the Tool-specific timeout"
        )
        try await close(timedOut.runtime, identity: timedOut.identity)

        let duplicate = try await configuredStack(
            fixture: fixture,
            permissionResolver: R5PermissionResolver()
        )
        await duplicate.executor.setBehavior(
            .held(#"{"once":true}"#),
            callID: "call-duplicate"
        )
        let duplicateIdentity = eventIdentity(session: duplicate.identity)
        let first = toolEvent(
            identity: duplicateIdentity,
            sequence: 1,
            callID: "call-duplicate",
            toolName: "lookup_test_value",
            arguments: #"{"key":"once"}"#
        )
        expectAccepted(
            try await receive(first, stack: duplicate),
            equals: first,
            "first duplicate fixture candidate is accepted"
        )
        await duplicate.executor.waitUntilRequestCount(1)
        let replay = toolEvent(
            identity: duplicateIdentity,
            sequence: 2,
            callID: "call-duplicate",
            toolName: "lookup_test_value",
            arguments: #"{"key":"once"}"#
        )
        let replayDisposition = try await receive(replay, stack: duplicate)
        expect(
            replayDisposition == .rejectedInvalidEvent,
            "duplicate callID is rejected by the Runtime ledger"
        )
        let duplicateExecutionCount = await duplicate.executor.requestCount()
        expect(
            duplicateExecutionCount == 1,
            "duplicate candidate schedules one execution"
        )
        await duplicate.executor.resume(callID: "call-duplicate")
        await duplicate.provider.waitUntilToolResultCount(1)
        let duplicateResultCount = await duplicate.provider
            .recordedToolResults().count
        expect(
            duplicateResultCount == 1,
            "duplicate candidate produces one result"
        )
        try await close(duplicate.runtime, identity: duplicate.identity)
    }

    private static func testConcurrentCallsCorrelateOutOfOrder(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await configuredStack(
            fixture: fixture,
            permissionResolver: R5PermissionResolver()
        )
        await stack.executor.setBehavior(
            .held(#"{"order":"A"}"#),
            callID: "call-A"
        )
        await stack.executor.setBehavior(
            .held(#"{"order":"B"}"#),
            callID: "call-B"
        )
        let identity = eventIdentity(session: stack.identity)
        let first = toolEvent(
            identity: identity,
            sequence: 1,
            callID: "call-A",
            toolName: "lookup_test_value",
            arguments: #"{"key":"A"}"#
        )
        let second = toolEvent(
            identity: identity,
            sequence: 2,
            callID: "call-B",
            toolName: "lookup_test_value",
            arguments: #"{"key":"B"}"#
        )
        expectAccepted(
            try await receive(first, stack: stack),
            equals: first,
            "first concurrent candidate is accepted"
        )
        expectAccepted(
            try await receive(second, stack: stack),
            equals: second,
            "second concurrent candidate is accepted"
        )
        await stack.executor.waitUntilRequestCount(2)
        await stack.executor.resume(callID: "call-B")
        await stack.provider.waitUntilToolResultCount(1)
        await stack.executor.resume(callID: "call-A")
        await stack.provider.waitUntilToolResultCount(2)
        let results = await stack.provider.recordedToolResults()
        expect(
            results.map(\.callID.rawValue) == ["call-B", "call-A"]
                && results.map(\.sequence) == [1, 2]
                && results[0].output.contains("B")
                && results[1].output.contains("A")
                && results.allSatisfy { $0.identity == identity },
            "out-of-order completion preserves call correlation and Runtime sequencing"
        )
        try await close(stack.runtime, identity: stack.identity)
    }

    private static func testWrongAndDuplicateResultsNeverReachProvider(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await configuredStack(
            fixture: fixture,
            permissionResolver: R5PermissionResolver()
        )
        await stack.executor.setBehavior(
            .held(#"{"correct":true}"#),
            callID: "call-correlation"
        )
        let identity = eventIdentity(session: stack.identity)
        let event = toolEvent(
            identity: identity,
            sequence: 1,
            callID: "call-correlation",
            toolName: "lookup_test_value",
            arguments: #"{"key":"correlation"}"#
        )
        expectAccepted(
            try await receive(event, stack: stack),
            equals: event,
            "correlation fixture candidate is accepted"
        )
        await stack.executor.waitUntilRequestCount(1)
        let wrongCall = RealtimeBrainToolResultCommand(
            identity: identity,
            sequence: 1,
            callID: RealtimeBrainToolCallID(rawValue: "wrong-call"),
            output: "wrong",
            isError: false
        )
        expectRealtimeFailure(
            await stack.runtime.submitRealtimeResidentBrainToolResult(
                wrongCall
            ),
            "unknown callID is rejected"
        )
        let wrongResponseIdentity = RealtimeBrainEventIdentity(
            session: stack.identity,
            turnID: identity.turnID,
            responseID: RealtimeBrainResponseID(),
            contextRevision: identity.contextRevision
        )
        expectRealtimeFailure(
            await stack.runtime.submitRealtimeResidentBrainToolResult(
                RealtimeBrainToolResultCommand(
                    identity: wrongResponseIdentity,
                    sequence: 1,
                    callID: RealtimeBrainToolCallID(
                        rawValue: "call-correlation"
                    ),
                    output: "wrong",
                    isError: false
                )
            ),
            "wrong responseID is rejected"
        )
        let wrongGenerationIdentity = RealtimeBrainEventIdentity(
            session: copySession(
                stack.identity,
                generation: stack.identity.generation &+ 1
            ),
            turnID: identity.turnID,
            responseID: identity.responseID,
            contextRevision: identity.contextRevision
        )
        expectRealtimeFailure(
            await stack.runtime.submitRealtimeResidentBrainToolResult(
                RealtimeBrainToolResultCommand(
                    identity: wrongGenerationIdentity,
                    sequence: 1,
                    callID: RealtimeBrainToolCallID(
                        rawValue: "call-correlation"
                    ),
                    output: "wrong",
                    isError: false
                )
            ),
            "wrong generation result is rejected"
        )
        let rejectedResults = await stack.provider.recordedToolResults()
        expect(
            rejectedResults.isEmpty,
            "mis-correlated results never reach Provider"
        )
        await stack.executor.resume(callID: "call-correlation")
        await stack.provider.waitUntilToolResultCount(1)
        let correct = (await stack.provider.recordedToolResults())[0]
        expectRealtimeFailure(
            await stack.runtime.submitRealtimeResidentBrainToolResult(
                correct
            ),
            "duplicate settled result is rejected"
        )
        let settledResultCount = await stack.provider
            .recordedToolResults().count
        expect(
            settledResultCount == 1,
            "duplicate result is not submitted twice"
        )
        try await close(stack.runtime, identity: stack.identity)
    }

    private static func testInterruptInvalidatesPendingWork(
        fixture: Data
    ) async throws {
        cases += 1
        let permissionResolver = R5PermissionResolver()
        let pendingPermission = try await configuredStack(
            fixture: fixture,
            permissionResolver: permissionResolver
        )
        let permissionEvent = toolEvent(
            identity: eventIdentity(session: pendingPermission.identity),
            sequence: 1,
            callID: "call-interrupt-permission",
            toolName: "permission_test_action",
            arguments: #"{}"#
        )
        expectAccepted(
            try await receive(permissionEvent, stack: pendingPermission),
            equals: permissionEvent,
            "pending permission fixture accepts the candidate"
        )
        await permissionResolver.waitUntilRequestCount(1)
        let nextPermissionIdentity = realtimeValue(
            await pendingPermission.runtime.interruptRealtimeResidentBrain(
                identity: pendingPermission.identity,
                reason: .runtimeDecision
            ),
            "interrupt advances the permission fixture"
        )
        await permissionResolver.decide(.approved, requestAt: 0)
        await permissionResolver.waitUntilCompletedCount(1)
        await Task.yield()
        let permissionCounts = pendingPermission.runtime
            .runtimeToolLifecycleCountsForTesting()
        let interruptedPermissionExecutionCount = await pendingPermission
            .executor.requestCount()
        let interruptedPermissionResults = await pendingPermission.provider
            .recordedToolResults()
        expect(
            permissionCounts.executions == 0
                && permissionCounts.permissions == 0
                && permissionCounts.pendingPermissions == 0
                && permissionCounts.handledCalls == 0
                && interruptedPermissionExecutionCount == 0
                && interruptedPermissionResults.isEmpty,
            "late approval cannot revive an interrupted generation"
        )
        let permissionInterruptCount = await pendingPermission.provider
            .interruptCount()
        expect(
            permissionInterruptCount == 1,
            "Runtime sends one Provider interruption"
        )
        try await close(
            pendingPermission.runtime,
            identity: nextPermissionIdentity
        )

        let pendingExecution = try await configuredStack(
            fixture: fixture,
            permissionResolver: R5PermissionResolver()
        )
        await pendingExecution.executor.setBehavior(
            .held(#"{"late":true}"#),
            callID: "call-interrupt-execution"
        )
        let oldIdentity = eventIdentity(session: pendingExecution.identity)
        let executionEvent = toolEvent(
            identity: oldIdentity,
            sequence: 1,
            callID: "call-interrupt-execution",
            toolName: "lookup_test_value",
            arguments: #"{"key":"late"}"#
        )
        expectAccepted(
            try await receive(executionEvent, stack: pendingExecution),
            equals: executionEvent,
            "pending execution fixture accepts the candidate"
        )
        await pendingExecution.executor.waitUntilRequestCount(1)
        let nextExecutionIdentity = realtimeValue(
            await pendingExecution.runtime.interruptRealtimeResidentBrain(
                identity: pendingExecution.identity,
                reason: .runtimeDecision
            ),
            "interrupt advances the execution fixture"
        )
        await pendingExecution.executor.resume(
            callID: "call-interrupt-execution"
        )
        await pendingExecution.executor.waitUntilCompletedCount(1)
        await Task.yield()
        let interruptedExecutionResults = await pendingExecution.provider
            .recordedToolResults()
        expect(
            interruptedExecutionResults.isEmpty,
            "late executor completion cannot submit an old result"
        )
        expectRealtimeFailure(
            await pendingExecution.runtime
                .submitRealtimeResidentBrainToolResult(
                    RealtimeBrainToolResultCommand(
                        identity: oldIdentity,
                        sequence: 1,
                        callID: RealtimeBrainToolCallID(
                            rawValue: "call-interrupt-execution"
                        ),
                        output: "late",
                        isError: false
                    )
                ),
            "old generation result remains stale after interruption"
        )
        expect(
            nextExecutionIdentity.generation
                == pendingExecution.identity.generation &+ 1,
            "Runtime remains the generation authority"
        )
        try await close(
            pendingExecution.runtime,
            identity: nextExecutionIdentity
        )
    }

    private static func configuredStack(
        fixture: Data,
        permissionResolver: R5PermissionResolver?
    ) async throws -> R5Stack {
        let provider = R5RealtimeProvider()
        let executor = R5ToolExecutor()
        let router = ProviderRouter(
            credentialReader: R5CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(
            runtime.configureRuntimeTools(
                definitions: toolDefinitions(),
                executor: executor,
                permissionResolver: permissionResolver
                    ?? UnavailableRuntimeToolPermissionResolver()
            ),
            "single Runtime Tool kernel configures"
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "fixed resident loads")
        let identity = realtimeValue(
            await runtime.openRealtimeResidentBrainSession(),
            "Realtime Brain session opens"
        )
        expectRealtimeSuccess(
            await runtime.updateRealtimeResidentBrainContext(
                RealtimeBrainRuntimeContextUpdate(
                    identity: identity,
                    kind: .bootstrap,
                    contextRevision: 1,
                    sections: [RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "R5 zero-network bootstrap"
                    )]
                )
            ),
            "Realtime Brain context bootstraps"
        )
        return R5Stack(
            runtime: runtime,
            provider: provider,
            executor: executor,
            identity: identity
        )
    }

    private static func toolDefinitions() -> [RuntimeToolDefinition] {
        let keyedObject = Data(
            #"{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}"#.utf8
        )
        return [
            RuntimeToolDefinition(
                name: "lookup_test_value",
                description: "Read a deterministic local test value.",
                parametersJSON: keyedObject,
                permission: .permissionFree,
                executionTimeout: .seconds(5)
            ),
            RuntimeToolDefinition(
                name: "permission_test_action",
                description: "Confirm a deterministic local test action.",
                parametersJSON: Data(#"{"type":"object"}"#.utf8),
                permission: .requiresPermission,
                executionTimeout: .seconds(5)
            ),
            RuntimeToolDefinition(
                name: "timeout_test_value",
                description: "Exercise the Runtime Tool deadline.",
                parametersJSON: keyedObject,
                permission: .permissionFree,
                executionTimeout: .milliseconds(25)
            )
        ]
    }

    private static func eventIdentity(
        session: RealtimeBrainSessionIdentity
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
    }

    private static func toolEvent(
        identity: RealtimeBrainEventIdentity,
        sequence: UInt64,
        callID: String,
        toolName: String,
        arguments: String
    ) -> RealtimeResidentBrainEvent {
        let candidate = RealtimeBrainToolCallCandidate(
            identity: identity,
            callID: RealtimeBrainToolCallID(rawValue: callID),
            toolName: toolName,
            arguments: Data(arguments.utf8)
        )
        return RealtimeResidentBrainEvent(
            identity: identity,
            sequence: sequence,
            kind: .toolCall(candidate)
        )
    }

    private static func receive(
        _ event: RealtimeResidentBrainEvent,
        stack: R5Stack
    ) async throws -> RealtimeBrainEventDisposition {
        await stack.provider.enqueue(event)
        return try await stack.runtime.receiveRealtimeResidentBrainEvent(
            session: stack.identity
        )
    }

    private static func copySession(
        _ identity: RealtimeBrainSessionIdentity,
        brainLeaseID: UUID? = nil,
        routeEpoch: UInt64? = nil,
        generation: UInt64? = nil
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: identity.residentID,
            runtimeSessionID: identity.runtimeSessionID,
            brainLeaseID: brainLeaseID ?? identity.brainLeaseID,
            routeEpoch: routeEpoch ?? identity.routeEpoch,
            generation: generation ?? identity.generation
        )
    }

    private static func close(
        _ runtime: RuntimeCore,
        identity: RealtimeBrainSessionIdentity
    ) async throws {
        expectRealtimeSuccess(
            await runtime.closeRealtimeResidentBrainSession(
                identity: identity
            ),
            "Realtime Brain session closes"
        )
    }

    private static func realtimeValue<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        _ message: String
    ) -> T {
        switch result {
        case .success(let value):
            expect(true, message)
            return value
        case .failure(let error):
            fatalError("FAILED: \(message): \(error)")
        }
    }

    private static func expectAccepted(
        _ disposition: RealtimeBrainEventDisposition,
        equals expected: RealtimeResidentBrainEvent,
        _ message: String
    ) {
        guard disposition == .accepted(expected) else {
            fatalError("FAILED: \(message): \(disposition)")
        }
        checks += 1
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

    private static func expectRealtimeFailure<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        _ message: String
    ) {
        switch result {
        case .success:
            fatalError("FAILED: \(message): expected failure")
        case .failure:
            expect(true, message)
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
