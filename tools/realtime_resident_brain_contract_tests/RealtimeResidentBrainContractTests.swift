import Foundation

private struct R2CredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "test-credential"
    }
}

private final class R2TextTransport: ProviderHTTPTransport {
    private let lock = NSLock()
    private var requestTotal = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { requestTotal += 1 }
        let reply = #"{"reply_text":"text route","expression_state":"neutral","expression_intensity":0}"#
        let body: [String: Any] = [
            "choices": [["message": ["content": reply]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func requestCount() -> Int {
        lock.withLock { requestTotal }
    }
}

private actor R2ASRProvider: ASRProvider {
    private var activeGeneration: UInt64?
    private(set) var startedGenerations: [UInt64] = []

    func start(request: ASRStartRequest) async throws {
        activeGeneration = request.generation
        startedGenerations.append(request.generation)
    }

    func send(_ input: ASRAudioInput) async throws {
        guard activeGeneration == input.generation else {
            throw SpeechRouteError.staleGeneration
        }
    }

    func receive(generation: UInt64) async throws -> ASREvent {
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        return ASREvent(
            generation: generation,
            kind: .partialTranscript("fake")
        )
    }

    func cancel(generation: UInt64) async throws {
        if activeGeneration == generation {
            activeGeneration = nil
        }
    }

    func close(generation: UInt64) async throws {
        if activeGeneration == generation {
            activeGeneration = nil
        }
    }

    func startCount() -> Int {
        startedGenerations.count
    }
}

private actor FakeRealtimeResidentBrainProvider:
    RealtimeResidentBrainProvider {
    private(set) var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private(set) var contextUpdates: [RealtimeBrainRuntimeContextUpdate] = []
    private(set) var audioFrames: [RealtimeBrainAudioFrame] = []
    private(set) var toolResults: [RealtimeBrainToolResultCommand] = []
    private(set) var responseCreateCommands:
        [RealtimeBrainCreateResponseCommand] = []
    private(set) var cancelCommands: [RealtimeBrainCancelGenerationCommand] = []
    private(set) var interruptCommands: [RealtimeBrainInterruptCommand] = []
    private(set) var closeCommands: [RealtimeBrainCloseSessionCommand] = []
    private var events: [RealtimeResidentBrainEvent] = []
    private var nextOpenError: RealtimeResidentBrainError?
    private var nextContextError: RealtimeResidentBrainError?
    private var nextAudioError: RealtimeResidentBrainError?
    private var nextToolResultError: RealtimeResidentBrainError?
    private var nextCancelError: RealtimeResidentBrainError?
    private var nextInterruptError: RealtimeResidentBrainError?
    private var nextCloseError: RealtimeResidentBrainError?
    private var closeErrorsByGeneration:
        [UInt64: RealtimeResidentBrainError] = [:]
    private var nextReceiveError: RealtimeResidentBrainError?
    private var requiredCloseGeneration: UInt64?
    private var shouldHoldNextOpen = false
    private var heldOpen: CheckedContinuation<Void, Never>?
    private var heldOpenWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldHoldNextContextUpdate = false
    private var heldContextUpdate: CheckedContinuation<Void, Never>?
    private var heldContextUpdateWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var shouldHoldNextCancel = false
    private var heldCancel: CheckedContinuation<Void, Never>?
    private var heldCancelWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldHoldNextAudio = false
    private var heldAudio: CheckedContinuation<Void, Never>?
    private var heldAudioWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldHoldNextResponseCreate = false
    private var heldResponseCreate: CheckedContinuation<Void, Never>?
    private var heldResponseCreateWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var shouldHoldNextReceive = false
    private var heldReceive: CheckedContinuation<Void, Never>?
    private var heldReceiveWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldHoldNextClose = false
    private var heldClose: CheckedContinuation<Void, Never>?
    private var heldCloseWaiters: [CheckedContinuation<Void, Never>] = []
    private var receiveTotal = 0

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        openCommands.append(command)
        if shouldHoldNextOpen {
            shouldHoldNextOpen = false
            await withCheckedContinuation { continuation in
                heldOpen = continuation
                let waiters = heldOpenWaiters
                heldOpenWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
        if let error = nextOpenError {
            nextOpenError = nil
            throw error
        }
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {
        contextUpdates.append(update)
        if shouldHoldNextContextUpdate {
            shouldHoldNextContextUpdate = false
            await withCheckedContinuation { continuation in
                heldContextUpdate = continuation
                let waiters = heldContextUpdateWaiters
                heldContextUpdateWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
        if let error = nextContextError {
            nextContextError = nil
            throw error
        }
    }

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {
        audioFrames.append(frame)
        if shouldHoldNextAudio {
            shouldHoldNextAudio = false
            await withCheckedContinuation { continuation in
                heldAudio = continuation
                let waiters = heldAudioWaiters
                heldAudioWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
        if let error = nextAudioError {
            nextAudioError = nil
            throw error
        }
    }

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {
        toolResults.append(command)
        if let error = nextToolResultError {
            nextToolResultError = nil
            throw error
        }
    }

    func createResponse(
        _ command: RealtimeBrainCreateResponseCommand
    ) async throws {
        responseCreateCommands.append(command)
        if shouldHoldNextResponseCreate {
            shouldHoldNextResponseCreate = false
            await withCheckedContinuation { continuation in
                heldResponseCreate = continuation
                let waiters = heldResponseCreateWaiters
                heldResponseCreateWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
    }

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {
        cancelCommands.append(command)
        if shouldHoldNextCancel {
            shouldHoldNextCancel = false
            await withCheckedContinuation { continuation in
                heldCancel = continuation
                let waiters = heldCancelWaiters
                heldCancelWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
        if let error = nextCancelError {
            nextCancelError = nil
            throw error
        }
    }

    func interrupt(
        _ command: RealtimeBrainInterruptCommand
    ) async throws {
        interruptCommands.append(command)
        if let error = nextInterruptError {
            nextInterruptError = nil
            throw error
        }
    }

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        receiveTotal += 1
        if shouldHoldNextReceive {
            shouldHoldNextReceive = false
            await withCheckedContinuation { continuation in
                heldReceive = continuation
                let waiters = heldReceiveWaiters
                heldReceiveWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
        if let error = nextReceiveError {
            nextReceiveError = nil
            throw error
        }
        guard !events.isEmpty else {
            throw RealtimeResidentBrainError.unavailable
        }
        return events.removeFirst()
    }

    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws {
        closeCommands.append(command)
        if shouldHoldNextClose {
            shouldHoldNextClose = false
            await withCheckedContinuation { continuation in
                heldClose = continuation
                let waiters = heldCloseWaiters
                heldCloseWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
        if let requiredCloseGeneration,
           command.identity.generation != requiredCloseGeneration {
            throw RealtimeResidentBrainError.invalidIdentity
        }
        requiredCloseGeneration = nil
        if let error = closeErrorsByGeneration.removeValue(
            forKey: command.identity.generation
        ) {
            throw error
        }
        if let error = nextCloseError {
            nextCloseError = nil
            throw error
        }
    }

    func enqueue(_ event: RealtimeResidentBrainEvent) {
        events.append(event)
    }

    func failNextOpen(_ error: RealtimeResidentBrainError) {
        nextOpenError = error
    }

    func failNextContext(_ error: RealtimeResidentBrainError) {
        nextContextError = error
    }

    func failNextCancel(_ error: RealtimeResidentBrainError) {
        nextCancelError = error
    }

    func failNextAudio(_ error: RealtimeResidentBrainError) {
        nextAudioError = error
    }

    func failNextToolResult(_ error: RealtimeResidentBrainError) {
        nextToolResultError = error
    }

    func failNextInterrupt(_ error: RealtimeResidentBrainError) {
        nextInterruptError = error
    }

    func failNextClose(_ error: RealtimeResidentBrainError) {
        nextCloseError = error
    }

    func failNextClose(
        generation: UInt64,
        error: RealtimeResidentBrainError
    ) {
        closeErrorsByGeneration[generation] = error
    }

    func failNextReceive(_ error: RealtimeResidentBrainError) {
        nextReceiveError = error
    }

    func holdNextOpen() {
        shouldHoldNextOpen = true
    }

    func waitForHeldOpen() async {
        if heldOpen != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldOpenWaiters.append(continuation)
        }
    }

    func resumeHeldOpen() {
        let continuation = heldOpen
        heldOpen = nil
        continuation?.resume()
    }

    func holdNextContextUpdate() {
        shouldHoldNextContextUpdate = true
    }

    func waitForHeldContextUpdate() async {
        if heldContextUpdate != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldContextUpdateWaiters.append(continuation)
        }
    }

    func resumeHeldContextUpdate() {
        let continuation = heldContextUpdate
        heldContextUpdate = nil
        continuation?.resume()
    }

    func holdNextCancel() {
        shouldHoldNextCancel = true
    }

    func waitForHeldCancel() async {
        if heldCancel != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldCancelWaiters.append(continuation)
        }
    }

    func resumeHeldCancel() {
        let continuation = heldCancel
        heldCancel = nil
        continuation?.resume()
    }

    func holdNextAudio() {
        shouldHoldNextAudio = true
    }

    func waitForHeldAudio() async {
        if heldAudio != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldAudioWaiters.append(continuation)
        }
    }

    func resumeHeldAudio() {
        let continuation = heldAudio
        heldAudio = nil
        continuation?.resume()
    }

    func holdNextResponseCreate() {
        shouldHoldNextResponseCreate = true
    }

    func waitForHeldResponseCreate() async {
        if heldResponseCreate != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldResponseCreateWaiters.append(continuation)
        }
    }

    func resumeHeldResponseCreate() {
        let continuation = heldResponseCreate
        heldResponseCreate = nil
        continuation?.resume()
    }

    func requireClose(generation: UInt64) {
        requiredCloseGeneration = generation
    }

    func holdNextReceive() {
        shouldHoldNextReceive = true
    }

    func waitForHeldReceive() async {
        if heldReceive != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldReceiveWaiters.append(continuation)
        }
    }

    func resumeHeldReceive() {
        let continuation = heldReceive
        heldReceive = nil
        continuation?.resume()
    }

    func holdNextClose() {
        shouldHoldNextClose = true
    }

    func waitForHeldClose() async {
        if heldClose != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldCloseWaiters.append(continuation)
        }
    }

    func resumeHeldClose() {
        let continuation = heldClose
        heldClose = nil
        continuation?.resume()
    }

    func openCount() -> Int { openCommands.count }
    func contextCount() -> Int { contextUpdates.count }
    func audioCount() -> Int { audioFrames.count }
    func toolResultCount() -> Int { toolResults.count }
    func cancelCount() -> Int { cancelCommands.count }
    func interruptCount() -> Int { interruptCommands.count }
    func closeCount() -> Int { closeCommands.count }
    func receiveCount() -> Int { receiveTotal }

    func lastCancelCommand() -> RealtimeBrainCancelGenerationCommand? {
        cancelCommands.last
    }

    func lastInterruptCommand() -> RealtimeBrainInterruptCommand? {
        interruptCommands.last
    }

    func closeGenerations() -> [UInt64] {
        closeCommands.map(\.identity.generation)
    }
}

private struct R2RuntimeStack {
    let runtime: RuntimeCore
    let provider: FakeRealtimeResidentBrainProvider
    let asrProvider: R2ASRProvider
    let textTransport: R2TextTransport
}

private actor R2SuspendingRuntimeToolExecutor: RuntimeToolExecuting {
    func execute(
        _ request: RuntimeToolExecutionRequest
    ) async throws -> String {
        try await Task.sleep(for: .seconds(300))
        return "{}"
    }
}

@main
@MainActor
private struct RealtimeResidentBrainContractTests {
    private static var checks = 0
    private static var cases = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        try await testSessionAndSingleBrain(fixture: fixture)
        try await testCommandsAndEvents(fixture: fixture)
        try await testIdentityOrderingAndLateCallbacks(fixture: fixture)
        try await testDeferredCapacityFailsClosed(fixture: fixture)
        try await testConcurrentTransitions(fixture: fixture)
        try await testContextAudioAdmission(fixture: fixture)
        try await testProviderFailureAndRecovery(fixture: fixture)
        try await testRuntimeEagerResponseAuthorization(fixture: fixture)
        testEagerResponseAuthorization()
        testTurnBoundarySequenceAndSemanticCandidates()
        testCrossSourceResponseExecutionFence()
        await testCloseWaiterRetention()

        print("realtime_resident_brain_contract_cases=\(cases)")
        print("realtime_resident_brain_contract_checks=\(checks)")
    }

    private static func testCloseWaiterRetention() async {
        cases += 1
        let gate = RuntimeRealtimeBrainSessionGate()
        let firstIdentity = RealtimeBrainSessionIdentity(
            residentID: "resident",
            runtimeSessionID: "session-one",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        expect(gate.reserve(firstIdentity), "waiter gate reserves first session")
        guard case .perform(let firstAttempt, _) = gate.claimClose(
            firstIdentity
        ), case .wait(let firstWait) = gate.claimClose(firstIdentity) else {
            fatalError("FAILED: close waiter claims first attempt")
        }
        gate.finishClose(
            identity: firstIdentity,
            attemptID: firstAttempt,
            outcome: .closed
        )
        let secondIdentity = RealtimeBrainSessionIdentity(
            residentID: "resident",
            runtimeSessionID: "session-two",
            brainLeaseID: UUID(),
            routeEpoch: 2,
            generation: 2
        )
        expect(
            gate.reserve(secondIdentity),
            "new session may reserve before late waiter consumes outcome"
        )
        expect(
            await gate.waitForClose(attemptID: firstWait) == .closed,
            "late waiter retains closed outcome across reopen"
        )

        guard case .perform(let failedAttempt, _) = gate.claimClose(
            secondIdentity
        ), case .wait(let failedWait) = gate.claimClose(secondIdentity) else {
            fatalError("FAILED: close waiter claims failed attempt")
        }
        gate.finishClose(
            identity: secondIdentity,
            attemptID: failedAttempt,
            outcome: .failed(.transportFailure)
        )
        guard case .perform(let retryAttempt, _) = gate.claimClose(
            secondIdentity
        ) else {
            fatalError("FAILED: failed close creates retry attempt")
        }
        expect(
            await gate.waitForClose(attemptID: failedWait)
                == .failed(.transportFailure),
            "late waiter retains failure after retry begins"
        )
        gate.finishClose(
            identity: secondIdentity,
            attemptID: retryAttempt,
            outcome: .closed
        )
    }

    private static func testCrossSourceResponseExecutionFence() {
        cases += 1

        func activatedGate(
            _ runtimeSessionID: String
        ) -> (
            gate: RuntimeRealtimeBrainSessionGate,
            identity: RealtimeBrainSessionIdentity
        ) {
            let gate = RuntimeRealtimeBrainSessionGate()
            let identity = RealtimeBrainSessionIdentity(
                residentID: "resident",
                runtimeSessionID: runtimeSessionID,
                brainLeaseID: UUID(),
                routeEpoch: 1,
                generation: 1
            )
            expect(gate.reserve(identity),
                   "cross-source gate reserves \(runtimeSessionID)")
            expect(gate.activate(identity),
                   "cross-source gate activates \(runtimeSessionID)")
            let bootstrap = RealtimeBrainRuntimeContextUpdate(
                identity: identity,
                kind: .bootstrap,
                contextRevision: 1,
                sections: [RealtimeBrainContextSection(
                    scope: .stableResident,
                    content: "stable"
                )]
            )
            guard let token = gate.beginContextUpdate(bootstrap) else {
                fatalError("FAILED: cross-source gate begins bootstrap")
            }
            expect(gate.finishContextUpdate(
                token: token,
                update: bootstrap,
                succeeded: true
            ), "cross-source gate commits bootstrap")
            return (gate, identity)
        }

        let terminalFixture = activatedGate("cross-source-terminal")
        let terminalFirstTurn = RealtimeBrainTurnID()
        let terminalResponseTurn = RealtimeBrainTurnID()
        let terminalFirstIdentity = RealtimeBrainEventIdentity(
            session: terminalFixture.identity,
            turnID: terminalFirstTurn,
            responseID: nil,
            contextRevision: 1
        )
        let terminalResponseIdentity = RealtimeBrainEventIdentity(
            session: terminalFixture.identity,
            turnID: terminalResponseTurn,
            responseID: nil,
            contextRevision: 1
        )
        let terminalFirstFinal = RealtimeResidentBrainEvent(
            identity: terminalFirstIdentity,
            sequence: 1,
            kind: .userTranscriptFinal("first segment")
        )
        let terminalResponseFinal = RealtimeResidentBrainEvent(
            identity: terminalResponseIdentity,
            sequence: 2,
            kind: .userTranscriptFinal("second segment")
        )
        expectAccepted(
            acceptDirect(
                terminalFirstFinal,
                gate: terminalFixture.gate,
                session: terminalFixture.identity
            ),
            equals: terminalFirstFinal,
            "cross-source terminal fixture accepts first final"
        )
        expectAccepted(
            acceptDirect(
                terminalResponseFinal,
                gate: terminalFixture.gate,
                session: terminalFixture.identity
            ),
            equals: terminalResponseFinal,
            "cross-source terminal fixture accepts response final"
        )
        let terminalCommand = RealtimeBrainCreateResponseCommand(
            identity: terminalResponseIdentity,
            sourceEventSequence: terminalResponseFinal.sequence
        )
        let terminalSourceTurns: Set<RealtimeBrainTurnID> = [
            terminalFirstTurn,
            terminalResponseTurn
        ]
        guard case .accepted(let terminalToken) = terminalFixture.gate
                .beginResponseCreate(
                    terminalCommand,
                    sourceTurnIDs: terminalSourceTurns
                ) else {
            fatalError("FAILED: cross-source terminal authorization begins")
        }
        let terminalEvent = RealtimeResidentBrainEvent(
            identity: terminalFirstIdentity,
            sequence: 3,
            kind: .cancelled(.runtimeDecision)
        )
        expectAccepted(
            acceptDirect(
                terminalEvent,
                gate: terminalFixture.gate,
                session: terminalFixture.identity
            ),
            equals: terminalEvent,
            "cross-source terminal fixture accepts alias failure"
        )
        expect(!terminalFixture.gate.claimResponseCreateExecution(
            token: terminalToken,
            command: terminalCommand,
            sourceTurnIDs: terminalSourceTurns
        ), "alias terminal atomically blocks Provider dispatch")
        expect(terminalFixture.gate.retireUserActivityTurns(
            terminalSourceTurns,
            session: terminalFixture.identity,
            contextRevision: 1,
            afterCommittedTerminalEvent: true
        ), "Runtime retirement closes the whole failed logical turn")
        expect(!terminalFixture.gate.finishResponseCreate(
            token: terminalToken,
            command: terminalCommand,
            succeeded: false
        ), "failed cross-source authorization has no response progress")
        let terminalBoundary = RealtimeBrainRuntimeContextUpdate(
            identity: terminalFixture.identity,
            kind: .delta,
            contextRevision: 2,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "terminal boundary"
            )]
        )
        expect(terminalFixture.gate.beginContextUpdate(terminalBoundary) != nil,
               "failed logical aliases do not leak an active turn")

        let successFixture = activatedGate("cross-source-success")
        let successFirstTurn = RealtimeBrainTurnID()
        let successResponseTurn = RealtimeBrainTurnID()
        let successFirstIdentity = RealtimeBrainEventIdentity(
            session: successFixture.identity,
            turnID: successFirstTurn,
            responseID: nil,
            contextRevision: 1
        )
        let successResponseIdentity = RealtimeBrainEventIdentity(
            session: successFixture.identity,
            turnID: successResponseTurn,
            responseID: nil,
            contextRevision: 1
        )
        let successFirstFinal = RealtimeResidentBrainEvent(
            identity: successFirstIdentity,
            sequence: 1,
            kind: .userTranscriptFinal("first segment")
        )
        let successResponseFinal = RealtimeResidentBrainEvent(
            identity: successResponseIdentity,
            sequence: 2,
            kind: .userTranscriptFinal("second segment")
        )
        expectAccepted(
            acceptDirect(
                successFirstFinal,
                gate: successFixture.gate,
                session: successFixture.identity
            ),
            equals: successFirstFinal,
            "cross-source success fixture accepts first final"
        )
        expectAccepted(
            acceptDirect(
                successResponseFinal,
                gate: successFixture.gate,
                session: successFixture.identity
            ),
            equals: successResponseFinal,
            "cross-source success fixture accepts response final"
        )
        let successCommand = RealtimeBrainCreateResponseCommand(
            identity: successResponseIdentity,
            sourceEventSequence: successResponseFinal.sequence
        )
        let successSourceTurns: Set<RealtimeBrainTurnID> = [
            successFirstTurn,
            successResponseTurn
        ]
        guard case .accepted(let successToken) = successFixture.gate
                .beginResponseCreate(
                    successCommand,
                    sourceTurnIDs: successSourceTurns
                ) else {
            fatalError("FAILED: cross-source success authorization begins")
        }
        expect(!successFixture.gate.retireUserActivityTurns(
            [successResponseTurn],
            session: successFixture.identity,
            contextRevision: 1
        ), "generic semantic cleanup cannot retire an awaiting response")
        expect(successFixture.gate.claimResponseCreateExecution(
            token: successToken,
            command: successCommand,
            sourceTurnIDs: successSourceTurns
        ), "all live source turns atomically claim response execution")
        let continuationCommand = RealtimeBrainCreateResponseCommand(
            identity: successCommand.identity, sourceEventSequence: successCommand.sourceEventSequence
        )
        for submission in [RealtimeBrainResponseAttempt.Submission.submitted, .uncertain] {
            expect(successFixture.gate.continueResponseCreate(
                token: successToken, previous: successCommand, next: continuationCommand,
                failure: RealtimeBrainResponseAttemptFailure(attemptID: successCommand.attempt.id,
                    submission: submission, reason: .responseWriteOrAcknowledgement, error: .timedOut)
            ) == nil, "submitted and uncertain attempts cannot obtain another Runtime authorization")
        }
        let notSubmitted = RealtimeBrainResponseAttemptFailure(
            attemptID: successCommand.attempt.id, submission: .notSubmitted,
            reason: .retiredResponseWait, error: .timedOut
        )
        successCommand.attempt.setPermitted(false)
        expect(successFixture.gate.continueResponseCreate(
            token: successToken, previous: successCommand, next: continuationCommand, failure: notSubmitted
        ) == nil, "speech pause prevents Runtime re-authorization")
        successCommand.attempt.setPermitted(true)
        guard let continuedToken = successFixture.gate.continueResponseCreate(
            token: successToken, previous: successCommand, next: continuationCommand, failure: notSubmitted
        ) else { fatalError("valid not-submitted continuation must be authorized") }
        expect(continuedToken != successToken, "each attempt receives a different operation token")
        expect(successFixture.gate.beginResponseCreate(continuationCommand) == .alreadyAuthorized(successResponseTurn),
               "continuation never clears consumed logical-turn authorization")
        expect(!successFixture.gate.finishResponseCreate(token: successToken, command: successCommand, succeeded: false),
               "late old attempt completion cannot clear the current attempt")
        let lateAlias = RealtimeResidentBrainEvent(
            identity: successFirstIdentity,
            sequence: 3,
            kind: .userTranscriptPartial("late alias")
        )
        expect(acceptDirect(
            lateAlias,
            gate: successFixture.gate,
            session: successFixture.identity
        ) == .rejectedInvalidEvent,
        "successful execution closes non-response aliases")
        expect(successFixture.gate.finishResponseCreate(
            token: continuedToken,
            command: continuationCommand,
            succeeded: true
        ), "cross-source response authorization commits")
        let residentIdentity = RealtimeBrainEventIdentity(
            session: successFixture.identity,
            turnID: successResponseTurn,
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let residentText = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 4,
            kind: .residentTextDelta("in progress")
        )
        expectAccepted(
            acceptDirect(
                residentText,
                gate: successFixture.gate,
                session: successFixture.identity
            ),
            equals: residentText,
            "response output opens the active resident response"
        )
        expect(!successFixture.gate.retireUserActivityTurns(
            [successResponseTurn],
            session: successFixture.identity,
            contextRevision: 1
        ), "generic semantic cleanup cannot retire an active response")
        let residentFinal = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 5,
            kind: .residentSemanticFinal(
                RealtimeBrainSemanticOutput(canonicalText: "complete")
            )
        )
        expectAccepted(
            acceptDirect(
                residentFinal,
                gate: successFixture.gate,
                session: successFixture.identity
            ),
            equals: residentFinal,
            "response completion closes the response source turn"
        )
        let successBoundary = RealtimeBrainRuntimeContextUpdate(
            identity: successFixture.identity,
            kind: .delta,
            contextRevision: 2,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "success boundary"
            )]
        )
        expect(successFixture.gate.beginContextUpdate(successBoundary) != nil,
               "successful logical aliases do not leak an active turn")
    }

    private static func testDeferredCapacityFailsClosed(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = configuredStack(fixture: fixture)
        let identity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(stack, identity: identity)
        let eventIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: RealtimeBrainTurnID(),
            responseID: nil,
            contextRevision: 1
        )
        for sequence in UInt64(2)...UInt64(17) {
            await stack.provider.enqueue(RealtimeResidentBrainEvent(
                identity: eventIdentity,
                sequence: sequence,
                kind: .userTranscriptPartial("future \(sequence)")
            ))
            expect(
                try await stack.runtime
                    .receiveRealtimeResidentBrainEvent(session: identity)
                    == .deferredOutOfOrder,
                "bounded future event \(sequence) is deferred"
            )
        }
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity,
            sequence: 18,
            kind: .userTranscriptPartial("overflow")
        ))
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedBufferOverflow,
            "deferred capacity overflow is explicit"
        )
        expect(await stack.provider.closeCount() == 1,
               "buffer overflow definitively closes the Provider")
        expect(stack.runtime.activeBrainLeaseForTesting() == nil,
               "buffer overflow releases admission only after close")
    }

    private static func testTurnBoundarySequenceAndSemanticCandidates() {
        cases += 1
        let gate = RuntimeRealtimeBrainSessionGate()
        let identity = RealtimeBrainSessionIdentity(
            residentID: "resident",
            runtimeSessionID: "turn-boundary",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        expect(gate.reserve(identity), "turn gate reserves the session")
        expect(gate.activate(identity), "turn gate awaits bootstrap")
        let bootstrap = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .bootstrap,
            contextRevision: 1,
            sections: [RealtimeBrainContextSection(
                scope: .stableResident,
                content: "stable"
            )]
        )
        guard let bootstrapToken = gate.beginContextUpdate(bootstrap) else {
            fatalError("FAILED: turn gate begins bootstrap")
        }
        expect(
            gate.finishContextUpdate(
                token: bootstrapToken,
                update: bootstrap,
                succeeded: true
            ),
            "turn gate commits bootstrap"
        )
        let duplicateScopeUpdate = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .delta,
            contextRevision: 2,
            sections: [
                RealtimeBrainContextSection(
                    scope: .dynamicSession,
                    content: "first"
                ),
                RealtimeBrainContextSection(
                    scope: .dynamicSession,
                    content: "second"
                )
            ]
        )
        expect(
            gate.beginContextUpdate(duplicateScopeUpdate) == nil,
            "one context update cannot replace the same scope twice"
        )

        let turnID = RealtimeBrainTurnID()
        let responseID = RealtimeBrainResponseID()
        let userIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: nil,
            contextRevision: 1
        )
        let residentIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: responseID,
            contextRevision: 1
        )
        let userFinal = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 1,
            kind: .userTranscriptFinal("remember this")
        )
        expectAccepted(
            acceptDirect(userFinal, gate: gate, session: identity),
            equals: userFinal,
            "user final opens a realtime turn"
        )
        expect(
            gate.beginResponseCreate(RealtimeBrainCreateResponseCommand(
                identity: userIdentity,
                sourceEventSequence: 2
            )) == .invalid,
            "response creation requires the exact accepted final sequence"
        )
        let responseCreate = RealtimeBrainCreateResponseCommand(
            identity: userIdentity,
            sourceEventSequence: userFinal.sequence
        )
        guard case .accepted(let responseCreateToken) =
                gate.beginResponseCreate(responseCreate) else {
            fatalError("FAILED: exact user final authorizes response creation")
        }
        expect(
            gate.finishResponseCreate(
                token: responseCreateToken,
                command: responseCreate,
                succeeded: true
            ),
            "response authorization commits before resident output"
        )
        expect(
            gate.beginResponseCreate(responseCreate)
                == .alreadyAuthorized(turnID),
            "one accepted final cannot authorize response creation twice"
        )
        let boundaryDelta = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .delta,
            contextRevision: 2,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "next boundary"
            )]
        )
        expect(
            gate.beginContextUpdate(boundaryDelta) == nil,
            "context cannot advance while a turn is open"
        )

        let memoryCandidate = RealtimeBrainNarrativeMemoryCandidate(
            identity: residentIdentity,
            candidateID: "memory-1",
            memoryType: "preference",
            summary: "The user asked the resident to remember this.",
            sourceTurnIDs: [turnID.rawValue.uuidString],
            consentSignal: "explicit",
            sensitivityFlags: [],
            evidenceSource: "user_transcript",
            inputClassification: "explicit_memory_request",
            confidence: 0.95
        )
        let relationshipCandidate =
            RealtimeBrainRelationshipEvidenceCandidate(
                identity: residentIdentity,
                evidenceType: "trust_signal",
                evidenceDetected: true,
                evidenceSource: "user_transcript",
                requiresUserConfirmation: false,
                confidence: 0.8
            )
        let growthCandidate = RealtimeBrainGrowthObservationCandidate(
            identity: residentIdentity,
            observation: "The resident explained the answer more clearly.",
            confidence: 0.7
        )
        let validSemantic = RealtimeBrainSemanticOutput(
            canonicalText: "I will remember that.",
            narrativeMemoryCandidates: [memoryCandidate],
            relationshipEvidenceCandidates: [relationshipCandidate],
            growthObservationCandidates: [growthCandidate]
        )
        let wrongCandidateIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let invalidIdentitySemantic = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 2,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "invalid nested identity",
                narrativeMemoryCandidates: [
                    RealtimeBrainNarrativeMemoryCandidate(
                        identity: wrongCandidateIdentity,
                        candidateID: "memory-wrong-response",
                        memoryType: "preference",
                        summary: "Wrong response binding.",
                        sourceTurnIDs: [turnID.rawValue.uuidString],
                        consentSignal: "explicit",
                        sensitivityFlags: [],
                        evidenceSource: "user_transcript",
                        inputClassification: "explicit_memory_request",
                        confidence: 0.9
                    )
                ]
            ))
        )
        expect(
            acceptDirect(
                invalidIdentitySemantic,
                gate: gate,
                session: identity
            ) == .rejectedInvalidEvent,
            "semantic candidates must bind the outer response identity"
        )
        let correctedSameSequence = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 2,
            kind: .residentSemanticFinal(validSemantic)
        )
        expect(
            acceptDirect(
                correctedSameSequence,
                gate: gate,
                session: identity
            ) == .rejectedDuplicate,
            "an invalid current event still consumes its outer sequence"
        )
        let nextSequence = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 3,
            kind: .residentTextFinal("I will remember that.")
        )
        expectAccepted(
            acceptDirect(nextSequence, gate: gate, session: identity),
            equals: nextSequence,
            "the next outer sequence continues after an invalid event"
        )
        let invalidMemoryConfidence = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 4,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "invalid memory confidence",
                narrativeMemoryCandidates: [
                    RealtimeBrainNarrativeMemoryCandidate(
                        identity: residentIdentity,
                        candidateID: "memory-nan",
                        memoryType: "preference",
                        summary: "Invalid confidence.",
                        sourceTurnIDs: [turnID.rawValue.uuidString],
                        consentSignal: "explicit",
                        sensitivityFlags: [],
                        evidenceSource: "user_transcript",
                        inputClassification: "explicit_memory_request",
                        confidence: .nan
                    )
                ]
            ))
        )
        expect(
            acceptDirect(
                invalidMemoryConfidence,
                gate: gate,
                session: identity
            ) == .rejectedInvalidEvent,
            "memory candidate confidence must be finite"
        )
        let invalidRelationshipConfidence = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 5,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "invalid relationship confidence",
                relationshipEvidenceCandidates: [
                    RealtimeBrainRelationshipEvidenceCandidate(
                        identity: residentIdentity,
                        evidenceType: "trust_signal",
                        evidenceDetected: true,
                        evidenceSource: "user_transcript",
                        requiresUserConfirmation: false,
                        confidence: 1.1
                    )
                ]
            ))
        )
        expect(
            acceptDirect(
                invalidRelationshipConfidence,
                gate: gate,
                session: identity
            ) == .rejectedInvalidEvent,
            "relationship candidate confidence stays within zero and one"
        )
        let invalidGrowthConfidence = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 6,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "invalid growth confidence",
                growthObservationCandidates: [
                    RealtimeBrainGrowthObservationCandidate(
                        identity: residentIdentity,
                        observation: "Invalid confidence.",
                        confidence: -0.1
                    )
                ]
            ))
        )
        expect(
            acceptDirect(
                invalidGrowthConfidence,
                gate: gate,
                session: identity
            ) == .rejectedInvalidEvent,
            "growth observation confidence stays within zero and one"
        )
        let semanticFinal = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 7,
            kind: .residentSemanticFinal(validSemantic)
        )
        expectAccepted(
            acceptDirect(semanticFinal, gate: gate, session: identity),
            equals: semanticFinal,
            "valid semantic candidates remain metadata on semantic final"
        )
        guard let boundaryToken = gate.beginContextUpdate(boundaryDelta) else {
            fatalError("FAILED: semantic final closes the context boundary")
        }
        expect(
            gate.finishContextUpdate(
                token: boundaryToken,
                update: boundaryDelta,
                succeeded: true
            ),
            "semantic final permits the next context revision"
        )

        let errorTurnID = RealtimeBrainTurnID()
        let errorResponseID = RealtimeBrainResponseID()
        let errorUserIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: errorTurnID,
            responseID: nil,
            contextRevision: 2
        )
        let errorResponseIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: errorTurnID,
            responseID: errorResponseID,
            contextRevision: 2
        )
        let speechStarted = RealtimeResidentBrainEvent(
            identity: errorUserIdentity,
            sequence: 8,
            kind: .userSpeechStarted
        )
        expectAccepted(
            acceptDirect(speechStarted, gate: gate, session: identity),
            equals: speechStarted,
            "speech start opens a turn"
        )
        let errorUserFinal = RealtimeResidentBrainEvent(
            identity: errorUserIdentity,
            sequence: 9,
            kind: .userTranscriptFinal("authorize error response")
        )
        expectAccepted(
            acceptDirect(errorUserFinal, gate: gate, session: identity),
            equals: errorUserFinal,
            "user final authorizes the error response"
        )
        let errorResponseCreate = RealtimeBrainCreateResponseCommand(
            identity: errorUserIdentity,
            sourceEventSequence: errorUserFinal.sequence
        )
        guard case .accepted(let errorResponseCreateToken) =
                gate.beginResponseCreate(errorResponseCreate) else {
            fatalError("FAILED: error response creation begins")
        }
        expect(
            gate.finishResponseCreate(
                token: errorResponseCreateToken,
                command: errorResponseCreate,
                succeeded: true
            ),
            "error response authorization commits"
        )
        let responseDelta = RealtimeResidentBrainEvent(
            identity: errorResponseIdentity,
            sequence: 10,
            kind: .residentTextDelta("partial")
        )
        expectAccepted(
            acceptDirect(responseDelta, gate: gate, session: identity),
            equals: responseDelta,
            "resident output opens a response"
        )
        let responseError = RealtimeResidentBrainEvent(
            identity: errorResponseIdentity,
            sequence: 11,
            kind: .error(.providerFailure)
        )
        expectAccepted(
            acceptDirect(responseError, gate: gate, session: identity),
            equals: responseError,
            "response error terminates the open turn and response"
        )
        let afterErrorDelta = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .delta,
            contextRevision: 3,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "after error"
            )]
        )
        guard let afterErrorToken = gate.beginContextUpdate(
            afterErrorDelta
        ) else {
            fatalError("FAILED: response error closes context boundary")
        }
        expect(
            gate.finishContextUpdate(
                token: afterErrorToken,
                update: afterErrorDelta,
                succeeded: true
            ),
            "response error permits the next context revision"
        )

        let cancelledTurnID = RealtimeBrainTurnID()
        let cancelledUserIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: cancelledTurnID,
            responseID: nil,
            contextRevision: 3
        )
        let partial = RealtimeResidentBrainEvent(
            identity: cancelledUserIdentity,
            sequence: 12,
            kind: .userTranscriptPartial("cancel")
        )
        expectAccepted(
            acceptDirect(partial, gate: gate, session: identity),
            equals: partial,
            "partial transcript opens a turn"
        )
        let cancelled = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: identity,
                turnID: nil,
                responseID: nil,
                contextRevision: 3
            ),
            sequence: 13,
            kind: .cancelled(.runtimeDecision)
        )
        expectAccepted(
            acceptDirect(cancelled, gate: gate, session: identity),
            equals: cancelled,
            "session-scoped cancellation terminates open work"
        )
        let afterCancelDelta = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .delta,
            contextRevision: 4,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "after cancel"
            )]
        )
        guard let afterCancelToken = gate.beginContextUpdate(
            afterCancelDelta
        ) else {
            fatalError("FAILED: cancellation closes context boundary")
        }
        expect(
            gate.finishContextUpdate(
                token: afterCancelToken,
                update: afterCancelDelta,
                succeeded: true
            ),
            "cancellation permits the next context revision"
        )

        let resetTurn = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: identity,
                turnID: RealtimeBrainTurnID(),
                responseID: nil,
                contextRevision: 4
            ),
            sequence: 14,
            kind: .userSpeechStarted
        )
        expectAccepted(
            acceptDirect(resetTurn, gate: gate, session: identity),
            equals: resetTurn,
            "generation reset fixture opens a turn"
        )
        let nextIdentity = RealtimeBrainSessionIdentity(
            residentID: identity.residentID,
            runtimeSessionID: identity.runtimeSessionID,
            brainLeaseID: identity.brainLeaseID,
            routeEpoch: identity.routeEpoch,
            generation: identity.generation + 1
        )
        guard let generationToken = gate.beginGenerationTransition(
            from: identity,
            to: nextIdentity
        ) else {
            fatalError("FAILED: generation transition begins")
        }
        expect(
            gate.commitGenerationTransition(
                token: generationToken,
                from: identity,
                to: nextIdentity
            ),
            "generation transition resets open turn and response ledgers"
        )
        let afterResetDelta = RealtimeBrainRuntimeContextUpdate(
            identity: nextIdentity,
            kind: .delta,
            contextRevision: 5,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "after generation reset"
            )]
        )
        guard let afterResetToken = gate.beginContextUpdate(
            afterResetDelta
        ) else {
            fatalError("FAILED: generation reset opens context boundary")
        }
        expect(
            gate.finishContextUpdate(
                token: afterResetToken,
                update: afterResetDelta,
                succeeded: true
            ),
            "generation reset permits a context delta"
        )
    }

    private static func testEagerResponseAuthorization() {
        cases += 1
        let gate = RuntimeRealtimeBrainSessionGate()
        let identity = RealtimeBrainSessionIdentity(
            residentID: "resident",
            runtimeSessionID: "eager-response-authorization",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        expect(gate.reserve(identity), "eager gate reserves the session")
        expect(gate.activate(identity), "eager gate awaits bootstrap")
        let bootstrap = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .bootstrap,
            contextRevision: 1,
            sections: [RealtimeBrainContextSection(
                scope: .stableResident,
                content: "stable"
            )]
        )
        guard let bootstrapToken = gate.beginContextUpdate(bootstrap) else {
            fatalError("FAILED: eager gate begins bootstrap")
        }
        expect(
            gate.finishContextUpdate(
                token: bootstrapToken,
                update: bootstrap,
                succeeded: true
            ),
            "eager gate commits bootstrap"
        )

        let turnID = RealtimeBrainTurnID()
        let userIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: nil,
            contextRevision: 1
        )
        let userFinal = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 1,
            kind: .userTranscriptFinal("run the tool")
        )
        expectAccepted(
            acceptDirect(userFinal, gate: gate, session: identity),
            equals: userFinal,
            "eager fixture accepts the exact user final"
        )
        let responseCreate = RealtimeBrainCreateResponseCommand(
            identity: userIdentity,
            sourceEventSequence: userFinal.sequence
        )
        guard case .accepted(let responseCreateToken) =
                gate.beginResponseCreate(responseCreate) else {
            fatalError("FAILED: eager response authorization begins")
        }
        let oldResponseID = RealtimeBrainResponseID()
        let oldResponseIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: oldResponseID,
            contextRevision: 1
        )
        let firstResidentEvent = RealtimeResidentBrainEvent(
            identity: oldResponseIdentity,
            sequence: 2,
            kind: .interruptionProposed(
                RealtimeBrainInterruptionProposal(
                    identity: oldResponseIdentity,
                    reason: "first response-bound semantic evidence"
                )
            )
        )
        expectAccepted(
            acceptDirect(firstResidentEvent, gate: gate, session: identity),
            equals: firstResidentEvent,
            "first interruption proposal may claim eager authorization before Provider return"
        )
        expect(
            gate.finishResponseCreate(
                token: responseCreateToken,
                command: responseCreate,
                succeeded: true
            ),
            "response authorization finishes after the first event claim"
        )

        let callID = RealtimeBrainToolCallID(rawValue: "eager-tool")
        let toolEvent = RealtimeResidentBrainEvent(
            identity: oldResponseIdentity,
            sequence: 3,
            kind: .toolCall(RealtimeBrainToolCallCandidate(
                identity: oldResponseIdentity,
                callID: callID,
                toolName: "fixture_tool",
                arguments: Data("{}".utf8)
            ))
        )
        expectAccepted(
            acceptDirect(toolEvent, gate: gate, session: identity),
            equals: toolEvent,
            "eager fixture accepts the tool candidate"
        )
        let toolResult = RealtimeBrainToolResultCommand(
            identity: oldResponseIdentity,
            sequence: 1,
            callID: callID,
            output: "{}",
            isError: false
        )
        guard let toolToken = gate.beginToolResult(toolResult) else {
            fatalError("FAILED: eager tool continuation begins")
        }
        let oldTail = RealtimeResidentBrainEvent(
            identity: oldResponseIdentity,
            sequence: 4,
            kind: .residentTextDelta("old tail")
        )
        expectAccepted(
            acceptDirect(oldTail, gate: gate, session: identity),
            equals: oldTail,
            "old response tail cannot consume tool continuation authorization"
        )
        let continuationIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let continuationEvent = RealtimeResidentBrainEvent(
            identity: continuationIdentity,
            sequence: 5,
            kind: .residentTextDelta("tool continuation")
        )
        expectAccepted(
            acceptDirect(continuationEvent, gate: gate, session: identity),
            equals: continuationEvent,
            "new response may claim tool authorization before Provider return"
        )
        expect(
            gate.finishToolResult(
                token: toolToken,
                command: toolResult,
                succeeded: true
            ),
            "tool authorization finishes after the new response claim"
        )

        let lateCallID = RealtimeBrainToolCallID(rawValue: "late-tool")
        let lateToolEvent = RealtimeResidentBrainEvent(
            identity: continuationIdentity,
            sequence: 6,
            kind: .toolCall(RealtimeBrainToolCallCandidate(
                identity: continuationIdentity,
                callID: lateCallID,
                toolName: "fixture_tool",
                arguments: Data("{}".utf8)
            ))
        )
        expectAccepted(
            acceptDirect(lateToolEvent, gate: gate, session: identity),
            equals: lateToolEvent,
            "terminal cleanup fixture records a pending tool candidate"
        )
        let terminalError = RealtimeResidentBrainEvent(
            identity: continuationIdentity,
            sequence: 7,
            kind: .error(.providerFailure)
        )
        expectAccepted(
            acceptDirect(terminalError, gate: gate, session: identity),
            equals: terminalError,
            "response error terminalizes the tool turn"
        )
        expect(
            gate.beginToolResult(RealtimeBrainToolResultCommand(
                identity: continuationIdentity,
                sequence: 2,
                callID: lateCallID,
                output: "{}",
                isError: false
            )) == nil,
            "late tool result cannot revive a terminal turn"
        )
    }

    private static func testRuntimeEagerResponseAuthorization(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = configuredStack(fixture: fixture)
        let identity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(stack, identity: identity)
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
        let userFinal = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 1,
            kind: .userTranscriptFinal("authorize while Provider is held")
        )
        await stack.provider.holdNextResponseCreate()
        await stack.provider.enqueue(userFinal)
        let userFinalTask = Task { @MainActor in
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            )
        }
        await stack.provider.waitForHeldResponseCreate()

        let firstProposal = RealtimeResidentBrainEvent(
            identity: responseIdentity,
            sequence: 2,
            kind: .interruptionProposed(
                RealtimeBrainInterruptionProposal(
                    identity: responseIdentity,
                    reason: "proposal before createResponse returns"
                )
            )
        )
        await stack.provider.enqueue(firstProposal)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: firstProposal,
            "Runtime accepts a response-bound proposal while createResponse is held"
        )
        await stack.provider.resumeHeldResponseCreate()
        expectAccepted(
            try await userFinalTask.value,
            equals: userFinal,
            "user final finishes after its eager authorization was claimed"
        )
        let responseCreateCommands = await stack.provider
            .responseCreateCommands
        expect(
            responseCreateCommands.count == 1
                && responseCreateCommands.first?.identity == userIdentity
                && responseCreateCommands.first?.sourceEventSequence == userFinal.sequence,
            "Runtime sends one exact createResponse command across the race"
        )
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: identity
            ),
            "eager Runtime fixture closes cleanly"
        )
    }

    private static func testSessionAndSingleBrain(
        fixture: Data
    ) async throws {
        cases += 1
        let unloadedProvider = FakeRealtimeResidentBrainProvider()
        let unloadedRuntime = runtime(provider: unloadedProvider)
        expectRealtimeFailure(
            await unloadedRuntime.openRealtimeResidentBrainSession(),
            equals: .unavailable,
            "a resident session is required before open"
        )
        expect(
            await unloadedProvider.openCount() == 0,
            "invalid admission never reaches the Provider"
        )

        let stack = configuredStack(fixture: fixture)
        let identity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )
        expect(
            await stack.provider.openCount() == 1,
            "valid R1 lease opens exactly one Realtime Provider"
        )
        expect(
            stack.runtime.activeBrainLeaseForTesting()?.route
                == .realtimeResidentBrain,
            "RuntimeCore records the Realtime route in the R1 lease"
        )
        expectRealtimeFailure(
            await stack.runtime.openRealtimeResidentBrainSession(),
            equals: .unavailable,
            "a second Realtime Brain cannot open"
        )
        expect(
            await stack.provider.openCount() == 1,
            "second admission is rejected before Provider open"
        )
        expectSpeechFailure(
            await stack.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "Realtime active rejects Cascaded Brain"
        )
        expect(
            await stack.asrProvider.startCount() == 0,
            "rejected Cascaded route never reaches ASR"
        )
        expectProviderFailure(
            await stack.runtime.requestResidentReply(inputText: "parallel"),
            equals: .cancelled,
            "Realtime active rejects text Brain"
        )
        expect(
            stack.textTransport.requestCount() == 0,
            "rejected text route never reaches transport"
        )

        await stack.provider.holdNextClose()
        let closing = Task {
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: identity
            )
        }
        await stack.provider.waitForHeldClose()
        let joinedClose = Task {
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: identity
            )
        }
        expect(
            stack.runtime.activeBrainLeaseForTesting()?.state == .settling,
            "close keeps the lease settling until Provider close finishes"
        )
        expectSpeechFailure(
            await stack.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "a settling Realtime route still blocks another Brain"
        )
        await stack.provider.resumeHeldClose()
        expectRealtimeSuccess(
            await closing.value,
            "definitive Provider close succeeds"
        )
        expectRealtimeSuccess(
            await joinedClose.value,
            "concurrent close joins the definitive Provider close"
        )
        expect(
            stack.runtime.activeBrainLeaseForTesting() == nil,
            "Runtime releases the lease only after definitive close"
        )
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: identity
            ),
            "close is idempotent"
        )
        expect(
            await stack.provider.closeCount() == 1,
            "idempotent close does not call Provider twice"
        )

        let cascadedGeneration = try speechIdentity(
            await stack.runtime.startSpeechRouteASR(locale: "en-US")
        )
        expect(
            await stack.asrProvider.startCount() == 1,
            "a new Brain may start only after Realtime release"
        )
        expectRealtimeFailure(
            await stack.runtime.openRealtimeResidentBrainSession(),
            equals: .unavailable,
            "Cascaded active rejects Realtime Brain"
        )
        expect(
            await stack.provider.openCount() == 1,
            "reverse admission rejects before Realtime Provider open"
        )
        _ = await stack.runtime.cancelSpeechRoute(
            generation: cascadedGeneration
        )
    }

    private static func testCommandsAndEvents(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = configuredStack(fixture: fixture)
        expect(
            stack.runtime.configureRuntimeTools(
                definitions: [RuntimeToolDefinition(
                    name: "weather.lookup",
                    description: "R2 contract fixture.",
                    parametersJSON: Data(
                        #"{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}"#.utf8
                    ),
                    permission: .permissionFree
                )],
                executor: R2SuspendingRuntimeToolExecutor()
            ),
            "R2 fixture advertises its candidate through the shared Runtime Tool kernel"
        )
        let identity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )

        let readyIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: nil,
            responseID: nil,
            contextRevision: 1
        )
        let ready = RealtimeResidentBrainEvent(
            identity: readyIdentity,
            sequence: 1,
            kind: .sessionReady
        )
        await stack.provider.enqueue(ready)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedContextTransition,
            "events wait for Runtime context bootstrap"
        )
        expect(
            await stack.provider.receiveCount() == 0,
            "bootstrap barrier rejects before Provider receive"
        )
        let inputFrame = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 1,
            timestampNanoseconds: 10,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 44_100,
                channelCount: 2
            ),
            provenance: .voiceProcessed,
            bytes: Data([0, 1, 2, 3])
        )
        expectRealtimeFailure(
            await stack.runtime.appendRealtimeResidentBrainAudio(inputFrame),
            equals: .invalidIdentity,
            "audio waits for Runtime context bootstrap"
        )

        let deltaBeforeBootstrap = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .delta,
            contextRevision: 1,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "delta-before-bootstrap"
            )]
        )
        expectRealtimeFailure(
            await stack.runtime.updateRealtimeResidentBrainContext(
                deltaBeforeBootstrap
            ),
            equals: .invalidContextRevision,
            "context delta requires bootstrap"
        )
        expect(
            await stack.provider.contextCount() == 0,
            "invalid context order does not reach Provider"
        )

        let bootstrap = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .bootstrap,
            contextRevision: 1,
            sections: [
                RealtimeBrainContextSection(
                    scope: .stableResident,
                    content: "stable resident context"
                ),
                RealtimeBrainContextSection(
                    scope: .dynamicSession,
                    content: "dynamic session context"
                )
            ]
        )
        expectRealtimeSuccess(
            await stack.runtime.updateRealtimeResidentBrainContext(bootstrap),
            "context bootstrap is forwarded"
        )
        expect(
            await stack.provider.contextCount() == 1,
            "Provider receives one bootstrap"
        )
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: ready,
            "sessionReady is accepted after bootstrap"
        )
        expectRealtimeFailure(
            await stack.runtime.updateRealtimeResidentBrainContext(bootstrap),
            equals: .invalidContextRevision,
            "duplicate context revision is rejected"
        )

        expectRealtimeSuccess(
            await stack.runtime.appendRealtimeResidentBrainAudio(inputFrame),
            "provider-neutral PCM input is forwarded"
        )
        expect(
            await stack.provider.audioCount() == 1,
            "Fake Provider receives audio without a network dependency"
        )
        let contextDuringUnsettledAudio =
            RealtimeBrainRuntimeContextUpdate(
                identity: identity,
                kind: .delta,
                contextRevision: 2,
                sections: [RealtimeBrainContextSection(
                    scope: .dynamicSession,
                    content: "must wait for the audio turn boundary"
                )]
            )
        expectRealtimeFailure(
            await stack.runtime.updateRealtimeResidentBrainContext(
                contextDuringUnsettledAudio
            ),
            equals: .invalidContextRevision,
            "context delta cannot cross submitted audio before a terminal event"
        )
        let misalignedInput = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 2,
            timestampNanoseconds: 20,
            format: inputFrame.format,
            provenance: .voiceProcessed,
            bytes: Data([4, 5])
        )
        expectRealtimeFailure(
            await stack.runtime.appendRealtimeResidentBrainAudio(
                misalignedInput
            ),
            equals: .invalidAudioFrame,
            "PCM16 input must align to channel frames"
        )
        let generatedInput = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 2,
            timestampNanoseconds: 20,
            format: inputFrame.format,
            provenance: .providerGenerated,
            bytes: Data([4, 5, 6, 7])
        )
        expectRealtimeFailure(
            await stack.runtime.appendRealtimeResidentBrainAudio(
                generatedInput
            ),
            equals: .invalidAudioFrame,
            "provider output provenance cannot be resubmitted as user input"
        )

        let turnID = RealtimeBrainTurnID()
        let activityTurnID = RealtimeBrainTurnID()
        let responseID = RealtimeBrainResponseID()
        let eventIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: responseID,
            contextRevision: 1
        )
        let userIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: activityTurnID,
            responseID: nil,
            contextRevision: 1
        )
        let responseAuthorizationIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: nil,
            contextRevision: 1
        )
        let callID = RealtimeBrainToolCallID(rawValue: "call-weather")
        let audioDelta = RealtimeBrainAudioDelta(
            sequence: 3,
            timestampNanoseconds: 50,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 32_000,
                channelCount: 1
            ),
            provenance: .providerGenerated,
            bytes: Data([6, 7])
        )
        let toolCandidate = RealtimeBrainToolCallCandidate(
            identity: eventIdentity,
            callID: callID,
            toolName: "weather.lookup",
            arguments: Data(#"{"city":"Shanghai"}"#.utf8)
        )
        let interruption = RealtimeBrainInterruptionProposal(
            identity: eventIdentity,
            reason: "near-end semantic evidence"
        )
        let errorIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let cancelledEventIdentity = userIdentity
        let semantic = RealtimeBrainSemanticOutput(
            canonicalText: "The final resident meaning."
        )
        let eventKinds: [(RealtimeBrainEventIdentity, RealtimeResidentBrainEventKind)] = [
            (responseAuthorizationIdentity, .userTranscriptFinal("hello")),
            (userIdentity, .userSpeechStarted),
            (userIdentity, .userSpeechStopped),
            (userIdentity, .userTranscriptPartial("hel")),
            (eventIdentity, .residentTextDelta("The final")),
            (eventIdentity, .residentTextFinal("The final resident meaning.")),
            (eventIdentity, .residentAudioDelta(audioDelta)),
            (eventIdentity, .residentSpeakingStarted),
            (eventIdentity, .residentSpeakingStopped),
            (eventIdentity, .toolCall(toolCandidate)),
            (eventIdentity, .interruptionProposed(interruption))
        ]
        var nextEventSequence: UInt64 = 2
        for (offset, item) in eventKinds.enumerated() {
            if offset == 6 {
                let wrongProvenance = RealtimeResidentBrainEvent(
                    identity: eventIdentity,
                    sequence: nextEventSequence,
                    kind: .residentAudioDelta(
                        RealtimeBrainAudioDelta(
                            sequence: 1,
                            timestampNanoseconds: 30,
                            format: audioDelta.format,
                            provenance: .voiceProcessed,
                            bytes: audioDelta.bytes
                        )
                    )
                )
                await stack.provider.enqueue(wrongProvenance)
                expect(
                    try await stack.runtime
                        .receiveRealtimeResidentBrainEvent(
                            session: identity
                        ) == .rejectedInvalidEvent,
                    "resident audio requires provider-generated provenance"
                )
                nextEventSequence += 1
                let misalignedOutput = RealtimeResidentBrainEvent(
                    identity: eventIdentity,
                    sequence: nextEventSequence,
                    kind: .residentAudioDelta(
                        RealtimeBrainAudioDelta(
                            sequence: 2,
                            timestampNanoseconds: 40,
                            format: audioDelta.format,
                            provenance: .providerGenerated,
                            bytes: Data([6])
                        )
                    )
                )
                await stack.provider.enqueue(misalignedOutput)
                expect(
                    try await stack.runtime
                        .receiveRealtimeResidentBrainEvent(
                            session: identity
                        ) == .rejectedInvalidEvent,
                    "resident PCM16 output must align to channel frames"
                )
                nextEventSequence += 1
            }
            let event = RealtimeResidentBrainEvent(
                identity: item.0,
                sequence: nextEventSequence,
                kind: item.1
            )
            await stack.provider.enqueue(event)
            expectAccepted(
                try await stack.runtime.receiveRealtimeResidentBrainEvent(
                    session: identity
                ),
                equals: event,
                "typed Realtime event \(nextEventSequence) is accepted"
            )
            nextEventSequence += 1
        }
        expect(
            stack.runtime.activeBrainLeaseForTesting()?.generation
                == .realtimeResidentBrain(identity.generation),
            "an interruption proposal cannot advance Runtime generation"
        )

        let contextWhileToolPending = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .delta,
            contextRevision: 2,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "must wait for Tool result"
            )]
        )
        expectRealtimeFailure(
            await stack.runtime.updateRealtimeResidentBrainContext(
                contextWhileToolPending
            ),
            equals: .invalidContextRevision,
            "context revision cannot strand a pending Tool candidate"
        )

        let toolResult = RealtimeBrainToolResultCommand(
            identity: eventIdentity,
            sequence: 1,
            callID: callID,
            output: #"{"temperature_c":31}"#,
            isError: false
        )
        expectRealtimeSuccess(
            await stack.runtime.submitRealtimeResidentBrainToolResult(
                toolResult
            ),
            "Runtime may return an already-executed Fake tool result"
        )
        expect(
            await stack.provider.toolResultCount() == 1,
            "Provider only receives a Tool result, never execution authority"
        )
        expectRealtimeFailure(
            await stack.runtime.submitRealtimeResidentBrainToolResult(
                toolResult
            ),
            equals: .invalidIdentity,
            "duplicate Tool result is rejected"
        )
        let unknownToolResult = RealtimeBrainToolResultCommand(
            identity: eventIdentity,
            sequence: 2,
            callID: RealtimeBrainToolCallID(rawValue: "unknown-call"),
            output: "ignored",
            isError: false
        )
        expectRealtimeFailure(
            await stack.runtime.submitRealtimeResidentBrainToolResult(
                unknownToolResult
            ),
            equals: .invalidIdentity,
            "Tool result must correlate to an accepted candidate"
        )
        expect(
            await stack.provider.toolResultCount() == 1,
            "invalid Tool results never reach Provider"
        )

        let continuationIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let emptySemantic = RealtimeResidentBrainEvent(
            identity: continuationIdentity,
            sequence: nextEventSequence,
            kind: .residentSemanticFinal(
                RealtimeBrainSemanticOutput(canonicalText: "   ")
            )
        )
        await stack.provider.enqueue(emptySemantic)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidEvent,
            "canonical semantic final cannot be empty"
        )
        nextEventSequence += 1
        let missingResponse = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: nextEventSequence,
            kind: .residentSemanticFinal(semantic)
        )
        await stack.provider.enqueue(missingResponse)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidIdentity,
            "semantic final requires turn and response identity"
        )
        nextEventSequence += 1
        let continuationSemantic = RealtimeResidentBrainEvent(
            identity: continuationIdentity,
            sequence: nextEventSequence,
            kind: .residentSemanticFinal(semantic)
        )
        await stack.provider.enqueue(continuationSemantic)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: continuationSemantic,
            "Tool continuation semantic final is accepted"
        )
        nextEventSequence += 1
        let duplicateSemantic = RealtimeResidentBrainEvent(
            identity: continuationIdentity,
            sequence: nextEventSequence,
            kind: .residentSemanticFinal(semantic)
        )
        await stack.provider.enqueue(duplicateSemantic)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidEvent,
            "one response accepts one canonical semantic final"
        )
        nextEventSequence += 1
        let lateText = RealtimeResidentBrainEvent(
            identity: continuationIdentity,
            sequence: nextEventSequence,
            kind: .residentTextDelta("late after semantic final")
        )
        await stack.provider.enqueue(lateText)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidEvent,
            "a terminal response rejects late resident callbacks"
        )
        nextEventSequence += 1
        let lateCancellation = RealtimeResidentBrainEvent(
            identity: continuationIdentity,
            sequence: nextEventSequence,
            kind: .cancelled(.runtimeDecision)
        )
        await stack.provider.enqueue(lateCancellation)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidEvent,
            "a terminal response rejects a late cancellation"
        )
        nextEventSequence += 1

        let unscopedError = RealtimeResidentBrainEvent(
            identity: readyIdentity,
            sequence: nextEventSequence,
            kind: .error(.providerFailure)
        )
        await stack.provider.enqueue(unscopedError)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidIdentity,
            "recoverable error requires turn and response identity"
        )
        nextEventSequence += 1
        let cancelledEvent = RealtimeResidentBrainEvent(
            identity: cancelledEventIdentity,
            sequence: nextEventSequence,
            kind: .cancelled(.runtimeDecision)
        )
        await stack.provider.enqueue(cancelledEvent)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: cancelledEvent,
            "typed cancellation is accepted"
        )
        nextEventSequence += 1
        let errorTurnIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: errorIdentity.turnID,
            responseID: nil,
            contextRevision: 1
        )
        let errorTurn = RealtimeResidentBrainEvent(
            identity: errorTurnIdentity,
            sequence: nextEventSequence,
            kind: .userTranscriptFinal("authorized error turn")
        )
        await stack.provider.enqueue(errorTurn)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: errorTurn,
            "response-scoped error turn is Runtime-authorized"
        )
        nextEventSequence += 1
        let errorEvent = RealtimeResidentBrainEvent(
            identity: errorIdentity,
            sequence: nextEventSequence,
            kind: .error(.providerFailure)
        )
        await stack.provider.enqueue(errorEvent)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: errorEvent,
            "typed response-scoped error is accepted"
        )
        nextEventSequence += 1

        expectRealtimeSuccess(
            await stack.runtime.updateRealtimeResidentBrainContext(
                contextWhileToolPending
            ),
            "context revision may advance after Tool result settlement"
        )
        let repeatedSemanticAcrossRevision = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: identity,
                turnID: turnID,
                responseID: responseID,
                contextRevision: 2
            ),
            sequence: nextEventSequence,
            kind: .residentSemanticFinal(semantic)
        )
        await stack.provider.enqueue(repeatedSemanticAcrossRevision)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidEvent,
            "semantic final remains unique across context revisions"
        )

        let cancelledIdentity = try realtimeIdentity(
            await stack.runtime.cancelRealtimeResidentBrainGenerationForTesting(
                identity: identity,
                reason: .runtimeDecision
            )
        )
        expect(
            cancelledIdentity.brainLeaseID == identity.brainLeaseID
                && cancelledIdentity.routeEpoch == identity.routeEpoch
                && cancelledIdentity.generation == identity.generation + 1,
            "cancel advances the existing R1 lease generation"
        )
        expect(
            await stack.provider.lastCancelCommand()?.nextGeneration
                == cancelledIdentity.generation,
            "Provider receives the Runtime-issued next generation"
        )
        expectRealtimeFailure(
            await stack.runtime.appendRealtimeResidentBrainAudio(inputFrame),
            equals: .invalidIdentity,
            "the pre-cancel generation is stale"
        )

        let interruptedIdentity = try realtimeIdentity(
            await stack.runtime.interruptRealtimeResidentBrainForTesting(
                identity: cancelledIdentity,
                reason: .runtimeDecision
            )
        )
        expect(
            interruptedIdentity.generation
                == cancelledIdentity.generation + 1,
            "RuntimeCore remains final interruption generation authority"
        )
        expect(
            await stack.provider.lastInterruptCommand()?.nextGeneration
                == interruptedIdentity.generation,
            "Provider receives but does not invent interruption generation"
        )
        let sessionClosed = RealtimeResidentBrainEvent(
            identity: readyIdentityFor(
                interruptedIdentity,
                revision: 2
            ),
            sequence: 1,
            kind: .sessionClosed
        )
        await stack.provider.enqueue(sessionClosed)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: interruptedIdentity
            ),
            equals: sessionClosed,
            "Provider sessionClosed is a terminal acknowledgement"
        )
        expect(
            stack.runtime.activeBrainLeaseForTesting() == nil,
            "sessionClosed releases the R1 Brain lease"
        )
        expectRealtimeFailure(
            await stack.runtime.cancelRealtimeResidentBrainGenerationForTesting(
                identity: interruptedIdentity,
                reason: .runtimeDecision
            ),
            equals: .invalidIdentity,
            "terminal session rejects later commands"
        )
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: interruptedIdentity
            ),
            "close remains idempotent after Provider terminal event"
        )
        expect(
            await stack.provider.closeCount() == 0,
            "terminal acknowledgement does not close Provider twice"
        )
    }

    private static func testIdentityOrderingAndLateCallbacks(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = configuredStack(fixture: fixture)
        let identity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(stack, identity: identity)

        let turnID = RealtimeBrainTurnID()
        let userIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: nil,
            contextRevision: 1
        )
        let first = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 1,
            kind: .userTranscriptPartial("one")
        )
        await stack.provider.enqueue(first)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: first,
            "current identity accepts the first event"
        )
        await stack.provider.enqueue(first)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedDuplicate,
            "duplicate event is deterministic"
        )
        let third = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 3,
            kind: .userTranscriptFinal("three")
        )
        await stack.provider.enqueue(third)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .deferredOutOfOrder,
            "future event is deterministically deferred"
        )
        let second = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 2,
            kind: .userTranscriptFinal("two")
        )
        await stack.provider.enqueue(second)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: second,
            "the missing next sequence remains acceptable"
        )
        let receiveCountAfterSecond = await stack.provider.receiveCount()
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: third,
            "deferred event resumes when its sequence becomes current"
        )
        expect(
            await stack.provider.receiveCount() == receiveCountAfterSecond,
            "deferred event is replayed without a second Provider pull"
        )

        let responseID = RealtimeBrainResponseID()
        let residentIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: responseID,
            contextRevision: 1
        )
        let audioFormat = RealtimeBrainAudioFormat(
            encoding: .pcm16LittleEndian,
            sampleRate: 24_000,
            channelCount: 1
        )
        let deferredAudio = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 5,
            kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                sequence: 1,
                timestampNanoseconds: 100,
                format: audioFormat,
                provenance: .providerGenerated,
                bytes: Data([0, 1])
            ))
        )
        await stack.provider.enqueue(deferredAudio)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .deferredOutOfOrder,
            "stateful future audio may wait for missing outer sequence"
        )
        let currentAudio = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 4,
            kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                sequence: 1,
                timestampNanoseconds: 200,
                format: audioFormat,
                provenance: .providerGenerated,
                bytes: Data([2, 3])
            ))
        )
        await stack.provider.enqueue(currentAudio)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: currentAudio,
            "current audio establishes the output ledger"
        )
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidEvent,
            "deferred audio is revalidated against the current ledger"
        )

        let duplicateCallID = RealtimeBrainToolCallID(
            rawValue: "deferred-duplicate"
        )
        let deferredTool = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 8,
            kind: .toolCall(RealtimeBrainToolCallCandidate(
                identity: residentIdentity,
                callID: duplicateCallID,
                toolName: "test.tool",
                arguments: Data()
            ))
        )
        await stack.provider.enqueue(deferredTool)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .deferredOutOfOrder,
            "stateful future Tool candidate may wait for its sequence"
        )
        let currentTool = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 6,
            kind: .toolCall(RealtimeBrainToolCallCandidate(
                identity: residentIdentity,
                callID: duplicateCallID,
                toolName: "test.tool",
                arguments: Data()
            ))
        )
        await stack.provider.enqueue(currentTool)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: currentTool,
            "current Tool candidate establishes the call ledger"
        )
        for _ in 0..<10_000 {
            if await stack.provider.toolResultCount() == 1 { break }
            await Task.yield()
        }
        expect(
            await stack.provider.toolResultCount() == 1,
            "Tool result authorizes one continuation response"
        )
        let filler = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 7,
            kind: .userTranscriptFinal("seven")
        )
        await stack.provider.enqueue(filler)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: filler,
            "missing sequence advances to deferred Tool replay"
        )
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidEvent,
            "deferred Tool candidate is revalidated for duplicate callID"
        )

        let malformedFutureAudio = RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: 10,
            kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                sequence: 2,
                timestampNanoseconds: 50,
                format: audioFormat,
                provenance: .voiceProcessed,
                bytes: Data([4, 5])
            ))
        )
        await stack.provider.enqueue(malformedFutureAudio)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .deferredOutOfOrder,
            "a future ordinal is deferred before payload validation"
        )
        let sequenceNine = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 9,
            kind: .userTranscriptFinal("nine")
        )
        await stack.provider.enqueue(sequenceNine)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: sequenceNine,
            "the missing ordinal remains acceptable"
        )
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedInvalidEvent,
            "the malformed future payload is rejected when current"
        )
        let continuationResidentIdentity = RealtimeBrainEventIdentity(
            session: identity,
            turnID: turnID,
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let validAfterMalformedAudio = RealtimeResidentBrainEvent(
            identity: continuationResidentIdentity,
            sequence: 11,
            kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                sequence: 3,
                timestampNanoseconds: 250,
                format: audioFormat,
                provenance: .providerGenerated,
                bytes: Data([6, 7])
            ))
        )
        await stack.provider.enqueue(validAfterMalformedAudio)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ),
            equals: validAfterMalformedAudio,
            "outer and audio ordering recover after malformed payload"
        )

        let receiveCount = await stack.provider.receiveCount()
        let wrongIdentities = [
            copyIdentity(identity, brainLeaseID: UUID()),
            copyIdentity(identity, routeEpoch: identity.routeEpoch &- 1),
            copyIdentity(identity, generation: identity.generation &- 1),
            copyIdentity(identity, runtimeSessionID: "wrong-session")
        ]
        for wrongIdentity in wrongIdentities {
            expect(
                try await stack.runtime.receiveRealtimeResidentBrainEvent(
                    session: wrongIdentity
                ) == .rejectedStale,
                "wrong lease, epoch, generation, or session is stale"
            )
        }
        expect(
            await stack.provider.receiveCount() == receiveCount,
            "stale identity is rejected before Provider receive"
        )

        for wrongIdentity in wrongIdentities {
            let staleCallback = RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(
                    session: wrongIdentity,
                    turnID: turnID,
                    responseID: nil,
                    contextRevision: 1
                ),
                sequence: 9,
                kind: .userTranscriptFinal("stale callback")
            )
            await stack.provider.enqueue(staleCallback)
            expect(
                try await stack.runtime.receiveRealtimeResidentBrainEvent(
                    session: identity
                ) == .rejectedStale,
                "Fake callback with stale lease identity is rejected"
            )
        }

        let late = RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: 9,
            kind: .userTranscriptFinal("late")
        )
        await stack.provider.enqueue(late)
        await stack.provider.holdNextReceive()
        let pendingReceive = Task {
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            )
        }
        await stack.provider.waitForHeldReceive()
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedReceiveInFlight,
            "only one Provider receive may be in flight"
        )
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: identity
            ),
            "close does not wait on a passive Provider receive"
        )
        expect(
            await stack.provider.closeCount() == 1,
            "Provider close may terminate the passive receive"
        )
        await stack.provider.resumeHeldReceive()
        expect(
            try await pendingReceive.value == .rejectedClosed,
            "late passive callback is fenced after close"
        )
        let closedReceiveCount = await stack.provider.receiveCount()
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedClosed,
            "closed session rejects future events"
        )
        expect(
            await stack.provider.receiveCount() == closedReceiveCount,
            "closed event is rejected before Provider receive"
        )

        let replacementIdentity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )
        expect(
            replacementIdentity.brainLeaseID != identity.brainLeaseID
                && replacementIdentity.routeEpoch > identity.routeEpoch,
            "reopen creates a new R1 lease and route epoch"
        )
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedStale,
            "old lease callback is stale after reopen"
        )
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: replacementIdentity
            ),
            "replacement session closes"
        )
    }

    private static func testConcurrentTransitions(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = configuredStack(fixture: fixture)
        let identity = try realtimeIdentity(
            await stack.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(stack, identity: identity)

        let delta = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .delta,
            contextRevision: 2,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "revision two"
            )]
        )
        await stack.provider.holdNextContextUpdate()
        let pendingContext = Task {
            await stack.runtime.updateRealtimeResidentBrainContext(delta)
        }
        await stack.provider.waitForHeldContextUpdate()
        let competingDelta = RealtimeBrainRuntimeContextUpdate(
            identity: identity,
            kind: .delta,
            contextRevision: 3,
            sections: [RealtimeBrainContextSection(
                scope: .dynamicSession,
                content: "competing revision"
            )]
        )
        expectRealtimeFailure(
            await stack.runtime.updateRealtimeResidentBrainContext(
                competingDelta
            ),
            equals: .invalidContextRevision,
            "context updates are single-flight"
        )
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedContextTransition,
            "events cannot cross an uncommitted context revision"
        )
        expect(
            await stack.provider.receiveCount() == 0,
            "context transition rejects before Provider receive"
        )
        await stack.provider.resumeHeldContextUpdate()
        expectRealtimeSuccess(
            await pendingContext.value,
            "the claimed context revision commits atomically"
        )
        expect(
            await stack.provider.contextCount() == 2,
            "competing context update never reaches Provider"
        )

        let audioFormat = RealtimeBrainAudioFormat(
            encoding: .pcm16LittleEndian,
            sampleRate: 48_000,
            channelCount: 1
        )
        let firstAudio = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 1,
            timestampNanoseconds: 100,
            format: audioFormat,
            provenance: .acousticEchoProcessed,
            bytes: Data([0, 1])
        )
        let secondAudio = RealtimeBrainAudioFrame(
            identity: identity,
            sequence: 2,
            timestampNanoseconds: 200,
            format: audioFormat,
            provenance: .acousticEchoProcessed,
            bytes: Data([2, 3])
        )
        await stack.provider.holdNextAudio()
        let pendingAudio = Task {
            await stack.runtime.appendRealtimeResidentBrainAudio(firstAudio)
        }
        await stack.provider.waitForHeldAudio()
        expectRealtimeFailure(
            await stack.runtime.appendRealtimeResidentBrainAudio(secondAudio),
            equals: .operationInFlight,
            "valid concurrent audio is reported as busy, not malformed"
        )
        await stack.provider.resumeHeldAudio()
        expectRealtimeSuccess(
            await pendingAudio.value,
            "claimed audio frame completes"
        )
        expectRealtimeSuccess(
            await stack.runtime.appendRealtimeResidentBrainAudio(secondAudio),
            "busy audio frame can retry with the same sequence"
        )

        await stack.provider.holdNextCancel()
        let pendingCancel = Task {
            await stack.runtime.cancelRealtimeResidentBrainGenerationForTesting(
                identity: identity,
                reason: .runtimeDecision
            )
        }
        await stack.provider.waitForHeldCancel()
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: identity
            ) == .rejectedStale,
            "generation transition invalidates old events before Provider await"
        )
        expectRealtimeFailure(
            await stack.runtime.interruptRealtimeResidentBrainForTesting(
                identity: identity,
                reason: .runtimeDecision
            ),
            equals: .invalidIdentity,
            "a second generation transition cannot reach Provider"
        )
        expect(
            await stack.provider.interruptCount() == 0,
            "competing transition has no Provider side effect"
        )
        await stack.provider.resumeHeldCancel()
        let nextIdentity = try realtimeIdentity(await pendingCancel.value)
        expect(
            nextIdentity.generation == identity.generation + 1,
            "claimed transition advances exactly one Runtime generation"
        )
        expect(
            await stack.provider.cancelCount() == 1,
            "only the claimed cancellation reaches Provider"
        )

        let turnID = RealtimeBrainTurnID()
        let staleEvent = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: identity,
                turnID: turnID,
                responseID: nil,
                contextRevision: 2
            ),
            sequence: 1,
            kind: .userTranscriptFinal("old generation")
        )
        await stack.provider.enqueue(staleEvent)
        expect(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: nextIdentity
            ) == .rejectedStale,
            "late callback from the previous generation is stale"
        )
        let currentEvent = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: nextIdentity,
                turnID: turnID,
                responseID: nil,
                contextRevision: 2
            ),
            sequence: 1,
            kind: .userTranscriptFinal("current generation")
        )
        await stack.provider.enqueue(currentEvent)
        expectAccepted(
            try await stack.runtime.receiveRealtimeResidentBrainEvent(
                session: nextIdentity
            ),
            equals: currentEvent,
            "current generation resumes with the committed context revision"
        )
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: nextIdentity
            ),
            "concurrency fixture closes"
        )

        let closeRace = configuredStack(fixture: fixture)
        let closeRaceIdentity = try realtimeIdentity(
            await closeRace.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(closeRace, identity: closeRaceIdentity)
        await closeRace.provider.holdNextCancel()
        let inFlightCancel = Task {
            await closeRace.runtime
                .cancelRealtimeResidentBrainGenerationForTesting(
                identity: closeRaceIdentity,
                reason: .runtimeDecision
            )
        }
        await closeRace.provider.waitForHeldCancel()
        let closeDuringCancel = Task {
            await closeRace.runtime.closeRealtimeResidentBrainSession(
                identity: closeRaceIdentity
            )
        }
        for _ in 0..<10 {
            await Task.yield()
        }
        expect(
            await closeRace.provider.closeCount() == 0,
            "close waits for an in-flight generation command"
        )
        await closeRace.provider.resumeHeldCancel()
        expectRealtimeFailure(
            await inFlightCancel.value,
            equals: .cancelled,
            "concurrent close prevents generation commit"
        )
        expectRealtimeSuccess(
            await closeDuringCancel.value,
            "close settles after the in-flight command returns"
        )
        expect(
            await closeRace.provider.closeGenerations() == [
                closeRaceIdentity.generation,
                closeRaceIdentity.generation + 1
            ],
            "close verifies every generation that could have become active"
        )
        expect(
            closeRace.runtime.activeBrainLeaseForTesting() == nil,
            "all-candidate close releases admission"
        )
    }

    private static func testContextAudioAdmission(fixture: Data) async throws {
        for scenario in ["ack", "cancel", "timeout", "failure", "close"] {
            cases += 1
            let stack = configuredStack(fixture: fixture)
            let identity = try realtimeIdentity(
                await stack.runtime.openRealtimeResidentBrainSession()
            )
            try await bootstrap(stack, identity: identity)
            let lease = stack.runtime.activeBrainLeaseForTesting()
            let diagnostics = NativeSpeechDiagnosticBuffer()
            stack.runtime.attachNativeSpeechDiagnosticBuffer(diagnostics)
            let delta = RealtimeBrainRuntimeContextUpdate(
                identity: identity, kind: .delta, contextRevision: 2,
                sections: [RealtimeBrainContextSection(scope: .dynamicSession, content: "next context")]
            )
            let frame = RealtimeBrainAudioFrame(
                identity: identity, sequence: 1,
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                format: RealtimeBrainAudioFormat(encoding: .pcm16LittleEndian, sampleRate: 16_000, channelCount: 1),
                provenance: .acousticEchoProcessed,
                bytes: Data(repeating: 1, count: 640)
            )
            let activity = RealtimeBrainLocalAudioActivity(
                kind: .listeningNearEnd, residentPlaybackSequence: 0,
                residentPlaybackActive: false,
                lastAudibleResidentRenderTimestampNanoseconds: nil,
                sourceGateEpoch: 0, routeStable: true,
                inputDeviceAvailable: true, outputDeviceAvailable: true
            )
            await stack.provider.holdNextContextUpdate()
            let update = Task { await stack.runtime.updateRealtimeResidentBrainContext(delta) }
            await stack.provider.waitForHeldContextUpdate()
            let started = ContinuousClock.now
            let append = Task { await stack.runtime.appendRealtimeResidentBrainAudio(frame, activity: activity) }
            let waitDeadline = ContinuousClock.now.advanced(by: .seconds(1))
            var sawWait = false
            while ContinuousClock.now < waitDeadline, !sawWait {
                sawWait = diagnostics.drain().events.contains {
                    $0.category == "runtime_audio_context_admission" && $0.disposition == "waiting"
                }
                if !sawWait { await Task.yield() }
            }
            expect(sawWait, "\(scenario): append reaches context wait before ACK")
            expect(await stack.provider.audioCount() == 0,
                   "\(scenario): no audio crosses uncommitted context")
            var closing: Task<Result<Void, RealtimeResidentBrainError>, Never>?
            switch scenario {
            case "cancel":
                append.cancel()
                expectRealtimeFailure(await append.value, equals: .cancelled,
                                      "cancelled waiter returns promptly")
                expect(started.duration(to: .now) < .milliseconds(500),
                       "cancellation does not wait for ACK or timeout")
            case "timeout":
                expectRealtimeFailure(await append.value, equals: .operationInFlight,
                                      "unacknowledged context is bounded busy, not invalid identity")
                let elapsed = started.duration(to: .now)
                expect(elapsed >= .milliseconds(500) && elapsed < .seconds(1),
                       "context wait is bounded to 500ms")
            case "failure":
                await stack.provider.failNextContext(.transportFailure)
            case "close":
                closing = Task { await stack.runtime.closeRealtimeResidentBrainSession(identity: identity) }
                expectRealtimeFailure(await append.value, equals: .invalidIdentity,
                                      "Stop rejects retained audio without waiting for ACK")
            default: break
            }
            await stack.provider.resumeHeldContextUpdate()
            if scenario == "failure" || scenario == "close" {
                expectRealtimeFailure(await update.value,
                                      equals: scenario == "failure" ? .transportFailure : .cancelled,
                                      "failed or closed context cannot commit")
                expectRealtimeFailure(await append.value, equals: .invalidIdentity,
                                      "terminated lease rejects waiting audio")
                if let closing { expectRealtimeSuccess(await closing.value, "Stop completes after ACK") }
                expect(await stack.provider.audioCount() == 0,
                       "terminal context never forwards retained PCM")
                let next = try realtimeIdentity(await stack.runtime.openRealtimeResidentBrainSession())
                try await bootstrap(stack, identity: next)
                expectRealtimeFailure(await stack.runtime.appendRealtimeResidentBrainAudio(frame),
                                      equals: .invalidIdentity, "restart rejects old retained frame")
                expectRealtimeSuccess(await stack.runtime.closeRealtimeResidentBrainSession(identity: next),
                                      "replacement session closes")
            } else {
                expectRealtimeSuccess(await update.value, "context ACK commits")
                if scenario == "ack" {
                    expectRealtimeSuccess(await append.value, "same PCM survives context ACK")
                } else {
                    expect(await stack.provider.audioCount() == 0,
                           "cancel/timeout never sends PCM late")
                    expectRealtimeSuccess(await stack.runtime.appendRealtimeResidentBrainAudio(frame, activity: activity),
                                          "caller may retry unconsumed sequence after ACK")
                }
                expect(await stack.provider.audioFrames == [frame],
                       "retained bytes, identity, sequence and timestamp are unchanged, sent exactly once")
                expectRealtimeSuccess(await stack.runtime.confirmRealtimeResidentBrainAcceptedLocalAudioActivity(frame: frame, activity: activity),
                                      "retained listening activity can be confirmed in committed context")
                expectRealtimeFailure(await stack.runtime.appendRealtimeResidentBrainAudio(frame),
                                      equals: .invalidAudioFrame, "duplicate sequence remains rejected")
                let nextFrame = RealtimeBrainAudioFrame(
                    identity: identity, sequence: 2,
                    timestampNanoseconds: frame.timestampNanoseconds + 20_000_000,
                    format: frame.format, provenance: frame.provenance, bytes: frame.bytes
                )
                let cancelledAppend = Task {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return await stack.runtime.appendRealtimeResidentBrainAudio(nextFrame)
                }
                expectRealtimeFailure(await cancelledAppend.value, equals: .cancelled,
                                      "cancel between reservation and send cannot reach Provider")
                expect(await stack.provider.audioFrames == [frame],
                       "cancelled reservation sends no second PCM")
                expectRealtimeSuccess(await stack.runtime.appendRealtimeResidentBrainAudio(nextFrame),
                                      "cancelled reservation releases token and preserves next sequence")
                expect(stack.runtime.activeBrainLeaseForTesting() == lease,
                       "context wait does not advance generation or replace lease")
                expectRealtimeSuccess(await stack.runtime.closeRealtimeResidentBrainSession(identity: identity),
                                      "context admission fixture closes")
            }
            let interrupts = await stack.provider.interruptCount()
            let cancellations = await stack.provider.cancelCount()
            expect(interrupts == 0 && cancellations == 0,
                   "context admission never invents interruption or cancellation")
            print("context_audio_admission=PASS scenario=\(scenario)")
        }
    }

    private static func testProviderFailureAndRecovery(
        fixture: Data
    ) async throws {
        cases += 1
        let startFailure = configuredStack(fixture: fixture)
        await startFailure.provider.failNextOpen(.transportFailure)
        expectRealtimeFailure(
            await startFailure.runtime.openRealtimeResidentBrainSession(),
            equals: .transportFailure,
            "Provider open error is reported"
        )
        expect(
            await startFailure.provider.closeCount() == 1,
            "failed open receives definitive close cleanup"
        )
        expect(
            startFailure.runtime.activeBrainLeaseForTesting() == nil,
            "successful failed-open cleanup releases admission"
        )
        let recovered = try realtimeIdentity(
            await startFailure.runtime.openRealtimeResidentBrainSession()
        )
        expectRealtimeSuccess(
            await startFailure.runtime.closeRealtimeResidentBrainSession(
                identity: recovered
            ),
            "a clean failed-open path can recover"
        )

        let inFlightOpen = configuredStack(fixture: fixture)
        await inFlightOpen.provider.holdNextOpen()
        let oldOpen = Task {
            await inFlightOpen.runtime
                .openRealtimeResidentBrainSession()
        }
        await inFlightOpen.provider.waitForHeldOpen()
        expect(
            inFlightOpen.runtime.loadDR(from: fixture).isLoaded,
            "session replacement may begin while Provider open is suspended"
        )
        let replacementOpen = Task {
            await inFlightOpen.runtime
                .openRealtimeResidentBrainSession()
        }
        expect(
            await inFlightOpen.provider.openCount() == 1,
            "replacement open waits for old Provider-start settlement"
        )
        await inFlightOpen.provider.resumeHeldOpen()
        expectRealtimeFailure(
            await oldOpen.value,
            equals: .cancelled,
            "old in-flight open becomes stale after session replacement"
        )
        let replacementOpenIdentity = try realtimeIdentity(
            await replacementOpen.value
        )
        let settledOpenCloseCount = await inFlightOpen.provider.closeCount()
        let settledOpenCount = await inFlightOpen.provider.openCount()
        expect(
            settledOpenCloseCount == 1 && settledOpenCount == 2,
            "old Provider closes before replacement Provider opens"
        )
        expectRealtimeSuccess(
            await inFlightOpen.runtime.closeRealtimeResidentBrainSession(
                identity: replacementOpenIdentity
            ),
            "replacement after suspended open closes"
        )

        let contextFailure = configuredStack(fixture: fixture)
        let contextIdentity = try realtimeIdentity(
            await contextFailure.runtime.openRealtimeResidentBrainSession()
        )
        await contextFailure.provider.failNextContext(.providerFailure)
        expectRealtimeFailure(
            await contextFailure.runtime
                .updateRealtimeResidentBrainContext(
                    RealtimeBrainRuntimeContextUpdate(
                        identity: contextIdentity,
                        kind: .bootstrap,
                        contextRevision: 1,
                        sections: [RealtimeBrainContextSection(
                            scope: .stableResident,
                            content: "ambiguous bootstrap"
                        )]
                    )
                ),
            equals: .providerFailure,
            "ambiguous context failure is reported"
        )
        expect(
            await contextFailure.provider.closeCount() == 1
                && contextFailure.runtime.activeBrainLeaseForTesting() == nil,
            "ambiguous context failure definitively closes before release"
        )

        let audioFailure = configuredStack(fixture: fixture)
        let audioFailureIdentity = try realtimeIdentity(
            await audioFailure.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(audioFailure, identity: audioFailureIdentity)
        await audioFailure.provider.failNextAudio(.providerFailure)
        expectRealtimeFailure(
            await audioFailure.runtime.appendRealtimeResidentBrainAudio(
                RealtimeBrainAudioFrame(
                    identity: audioFailureIdentity,
                    sequence: 1,
                    timestampNanoseconds: 1,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: 16_000,
                        channelCount: 1
                    ),
                    provenance: .microphoneCapture,
                    bytes: Data([0, 1])
                )
            ),
            equals: .providerFailure,
            "ambiguous audio failure is reported"
        )
        expect(
            await audioFailure.provider.closeCount() == 1
                && audioFailure.runtime.activeBrainLeaseForTesting() == nil,
            "ambiguous audio failure closes instead of retrying a frame"
        )

        let toolFailure = configuredStack(fixture: fixture)
        expect(
            toolFailure.runtime.configureRuntimeTools(
                definitions: [RuntimeToolDefinition(
                    name: "test.tool",
                    description: "R2 Tool-result failure fixture.",
                    parametersJSON: Data(#"{"type":"object"}"#.utf8),
                    permission: .permissionFree
                )],
                executor: R2SuspendingRuntimeToolExecutor()
            ),
            "Tool-result failure fixture uses the shared Runtime Tool kernel"
        )
        let toolFailureIdentity = try realtimeIdentity(
            await toolFailure.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(toolFailure, identity: toolFailureIdentity)
        let toolEventIdentity = RealtimeBrainEventIdentity(
            session: toolFailureIdentity,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let toolFailureCallID = RealtimeBrainToolCallID(
            rawValue: "ambiguous-tool"
        )
        let toolFailureTurn = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: toolFailureIdentity,
                turnID: toolEventIdentity.turnID,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .userTranscriptFinal("authorized Tool failure turn")
        )
        await toolFailure.provider.enqueue(toolFailureTurn)
        expectAccepted(
            try await toolFailure.runtime.receiveRealtimeResidentBrainEvent(
                session: toolFailureIdentity
            ),
            equals: toolFailureTurn,
            "Tool failure response is Runtime-authorized"
        )
        let toolFailureEvent = RealtimeResidentBrainEvent(
            identity: toolEventIdentity,
            sequence: 2,
            kind: .toolCall(RealtimeBrainToolCallCandidate(
                identity: toolEventIdentity,
                callID: toolFailureCallID,
                toolName: "test.tool",
                arguments: Data("{}".utf8)
            ))
        )
        await toolFailure.provider.enqueue(toolFailureEvent)
        expectAccepted(
            try await toolFailure.runtime
                .receiveRealtimeResidentBrainEvent(
                    session: toolFailureIdentity
                ),
            equals: toolFailureEvent,
            "Tool failure fixture accepts a candidate"
        )
        await toolFailure.provider.failNextToolResult(.providerFailure)
        expectRealtimeFailure(
            await toolFailure.runtime
                .submitRealtimeResidentBrainToolResult(
                    RealtimeBrainToolResultCommand(
                        identity: toolEventIdentity,
                        sequence: 1,
                        callID: toolFailureCallID,
                        output: "ambiguous",
                        isError: false
                    )
                ),
            equals: .providerFailure,
            "ambiguous Tool result failure is reported"
        )
        expect(
            await toolFailure.provider.closeCount() == 1
                && toolFailure.runtime.activeBrainLeaseForTesting() == nil,
            "ambiguous Tool result closes instead of duplicate retry"
        )

        let receiveFailure = configuredStack(fixture: fixture)
        let receiveIdentity = try realtimeIdentity(
            await receiveFailure.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(receiveFailure, identity: receiveIdentity)
        await receiveFailure.provider.failNextReceive(.providerFailure)
        do {
            _ = try await receiveFailure.runtime
                .receiveRealtimeResidentBrainEvent(
                    session: receiveIdentity
                )
            fatalError("FAILED: terminal receive error must surface")
        } catch let error as RealtimeResidentBrainError {
            expect(
                error == .providerFailure,
                "terminal Provider receive error is mapped"
            )
        }
        expect(
            await receiveFailure.provider.closeCount() == 1
                && receiveFailure.runtime.activeBrainLeaseForTesting() == nil,
            "terminal receive error definitively closes the session"
        )

        let ambiguousCancel = configuredStack(fixture: fixture)
        let cancelIdentity = try realtimeIdentity(
            await ambiguousCancel.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(ambiguousCancel, identity: cancelIdentity)
        await ambiguousCancel.provider.failNextCancel(.transportFailure)
        await ambiguousCancel.provider.requireClose(
            generation: cancelIdentity.generation + 1
        )
        expectRealtimeFailure(
            await ambiguousCancel.runtime
                .cancelRealtimeResidentBrainGenerationForTesting(
                    identity: cancelIdentity,
                    reason: .runtimeDecision
                ),
            equals: .transportFailure,
            "ambiguous generation transition reports its command error"
        )
        expect(
            await ambiguousCancel.provider.closeGenerations()
                == [
                    cancelIdentity.generation,
                    cancelIdentity.generation + 1
                ],
            "definitive close covers old and proposed generations"
        )
        expect(
            ambiguousCancel.runtime.activeBrainLeaseForTesting() == nil,
            "successful next-generation close releases admission"
        )

        let ambiguousInterrupt = configuredStack(fixture: fixture)
        let interruptIdentity = try realtimeIdentity(
            await ambiguousInterrupt.runtime
                .openRealtimeResidentBrainSession()
        )
        try await bootstrap(ambiguousInterrupt, identity: interruptIdentity)
        await ambiguousInterrupt.provider.failNextInterrupt(
            .transportFailure
        )
        await ambiguousInterrupt.provider.requireClose(
            generation: interruptIdentity.generation + 1
        )
        expectRealtimeFailure(
            await ambiguousInterrupt.runtime
                .interruptRealtimeResidentBrainForTesting(
                identity: interruptIdentity,
                reason: .runtimeDecision
            ),
            equals: .transportFailure,
            "ambiguous interruption uses fail-closed settlement"
        )
        expect(
            await ambiguousInterrupt.provider.closeGenerations() == [
                interruptIdentity.generation,
                interruptIdentity.generation + 1
            ],
            "interruption settlement covers old and proposed generations"
        )
        expect(
            ambiguousInterrupt.runtime.activeBrainLeaseForTesting() == nil,
            "definitive interruption cleanup releases admission"
        )

        let allCandidates = configuredStack(fixture: fixture)
        let allCandidatesIdentity = try realtimeIdentity(
            await allCandidates.runtime.openRealtimeResidentBrainSession()
        )
        try await bootstrap(allCandidates, identity: allCandidatesIdentity)
        await allCandidates.provider.failNextCancel(.transportFailure)
        await allCandidates.provider.failNextClose(
            generation: allCandidatesIdentity.generation + 1,
            error: .transportFailure
        )
        expectRealtimeFailure(
            await allCandidates.runtime
                .cancelRealtimeResidentBrainGenerationForTesting(
                    identity: allCandidatesIdentity,
                    reason: .runtimeDecision
                ),
            equals: .transportFailure,
            "generation command ambiguity remains visible"
        )
        expect(
            allCandidates.runtime.activeBrainLeaseForTesting()?.state
                == .settling,
            "one ambiguous close candidate keeps admission fail-closed"
        )
        expect(
            await allCandidates.provider.closeGenerations() == [
                allCandidatesIdentity.generation,
                allCandidatesIdentity.generation + 1
            ],
            "old close success cannot skip a possible next generation"
        )
        expectRealtimeSuccess(
            await allCandidates.runtime.closeRealtimeResidentBrainSession(
                identity: allCandidatesIdentity
            ),
            "retry confirms every retained close candidate"
        )
        expect(
            await allCandidates.provider.closeGenerations() == [
                allCandidatesIdentity.generation,
                allCandidatesIdentity.generation + 1,
                allCandidatesIdentity.generation,
                allCandidatesIdentity.generation + 1
            ],
            "close retry preserves the full candidate set"
        )

        let closeFailure = configuredStack(fixture: fixture)
        let active = try realtimeIdentity(
            await closeFailure.runtime.openRealtimeResidentBrainSession()
        )
        await closeFailure.provider.failNextClose(.transportFailure)
        expectRealtimeFailure(
            await closeFailure.runtime.closeRealtimeResidentBrainSession(
                identity: active
            ),
            equals: .transportFailure,
            "Provider close failure is reported"
        )
        expect(
            closeFailure.runtime.activeBrainLeaseForTesting()?.state
                == .settling,
            "close failure keeps admission fail-closed"
        )
        expectSpeechFailure(
            await closeFailure.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "no second Brain starts after close failure"
        )
        expectRealtimeSuccess(
            await closeFailure.runtime.closeRealtimeResidentBrainSession(
                identity: active
            ),
            "retry may finish definitive close"
        )

        let replacement = configuredStack(fixture: fixture)
        await replacement.provider.failNextOpen(.transportFailure)
        await replacement.provider.failNextClose(.transportFailure)
        expectRealtimeFailure(
            await replacement.runtime.openRealtimeResidentBrainSession(),
            equals: .transportFailure,
            "partial open with failed cleanup reports original error"
        )
        expect(
            replacement.runtime.activeBrainLeaseForTesting() != nil,
            "partial open cleanup failure retains the R1 lease"
        )
        expectRealtimeFailure(
            await replacement.runtime.openRealtimeResidentBrainSession(),
            equals: .unavailable,
            "retained lease rejects another Realtime Brain"
        )
        expect(
            replacement.runtime.loadDR(from: fixture).isLoaded,
            "session replacement loads while cleanup is scheduled"
        )
        let afterReplacement = try realtimeIdentity(
            await replacement.runtime.openRealtimeResidentBrainSession()
        )
        expect(
            await replacement.provider.closeCount() == 2,
            "session replacement settles the old partial Provider session"
        )
        expectRealtimeSuccess(
            await replacement.runtime.closeRealtimeResidentBrainSession(
                identity: afterReplacement
            ),
            "new session opens only after old Provider settlement"
        )
    }

    private static func configuredStack(fixture: Data) -> R2RuntimeStack {
        let provider = FakeRealtimeResidentBrainProvider()
        let asrProvider = R2ASRProvider()
        let textTransport = R2TextTransport()
        let router = ProviderRouter(
            credentialReader: R2CredentialReader(),
            transport: textTransport,
            asrProvider: asrProvider,
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "resident loads")
        expect(
            runtime.configureTextProvider(profile: ProviderProfile(
                profileID: "text-profile",
                providerID: "text-provider",
                adapterType: "openai_compatible",
                modelID: "existing-model",
                baseURL: "https://example.invalid/v1",
                keyRef: "keychain://test/text",
                enabled: true,
                timeout: 5,
                stream: false,
                thinkingMode: "disabled"
            )) == nil,
            "text Provider configures"
        )
        return R2RuntimeStack(
            runtime: runtime,
            provider: provider,
            asrProvider: asrProvider,
            textTransport: textTransport
        )
    }

    private static func runtime(
        provider: FakeRealtimeResidentBrainProvider
    ) -> RuntimeCore {
        let router = ProviderRouter(
            credentialReader: R2CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        return RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
    }

    private static func bootstrap(
        _ stack: R2RuntimeStack,
        identity: RealtimeBrainSessionIdentity
    ) async throws {
        expectRealtimeSuccess(
            await stack.runtime.updateRealtimeResidentBrainContext(
                RealtimeBrainRuntimeContextUpdate(
                    identity: identity,
                    kind: .bootstrap,
                    contextRevision: 1,
                    sections: [RealtimeBrainContextSection(
                        scope: .stableResident,
                        content: "stable"
                    )]
                )
            ),
            "identity test bootstraps context"
        )
    }

    private static func readyIdentityFor(
        _ session: RealtimeBrainSessionIdentity,
        revision: UInt64
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: session,
            turnID: nil,
            responseID: nil,
            contextRevision: revision
        )
    }

    private static func copyIdentity(
        _ identity: RealtimeBrainSessionIdentity,
        runtimeSessionID: String? = nil,
        brainLeaseID: UUID? = nil,
        routeEpoch: UInt64? = nil,
        generation: UInt64? = nil
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: identity.residentID,
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

    private static func speechIdentity(
        _ result: Result<UInt64, SpeechRouteError>
    ) throws -> UInt64 {
        switch result {
        case .success(let generation):
            return generation
        case .failure(let error):
            throw error
        }
    }

    private static func expectAccepted(
        _ disposition: RealtimeBrainEventDisposition,
        equals expected: RealtimeResidentBrainEvent,
        _ message: String
    ) {
        switch disposition {
        case .accepted(let event):
            expect(event == expected, message)
        default:
            fatalError("FAILED: \(message): \(disposition)")
        }
    }

    private static func acceptDirect(
        _ event: RealtimeResidentBrainEvent,
        gate: RuntimeRealtimeBrainSessionGate,
        session: RealtimeBrainSessionIdentity
    ) -> RealtimeBrainEventDisposition {
        guard case .provider(let token) = gate.beginReceiving(session) else {
            fatalError("FAILED: direct gate receive begins")
        }
        return gate.accept(event, expected: session, token: token)
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
        equals expected: RealtimeResidentBrainError,
        _ message: String
    ) {
        switch result {
        case .success:
            fatalError("FAILED: \(message): expected \(expected)")
        case .failure(let error):
            expect(error == expected, message)
        }
    }

    private static func expectSpeechFailure<T>(
        _ result: Result<T, SpeechRouteError>,
        equals expected: SpeechRouteError,
        _ message: String
    ) {
        switch result {
        case .success:
            fatalError("FAILED: \(message): expected \(expected)")
        case .failure(let error):
            expect(error == expected, message)
        }
    }

    private static func expectProviderFailure<T>(
        _ result: Result<T, ProviderRequestError>,
        equals expected: ProviderRequestError,
        _ message: String
    ) {
        switch result {
        case .success:
            fatalError("FAILED: \(message): expected \(expected)")
        case .failure(let error):
            expect(error == expected, message)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
