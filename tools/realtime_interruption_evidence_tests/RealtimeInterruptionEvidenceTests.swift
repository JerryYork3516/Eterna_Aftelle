import Foundation

private struct R81CredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? { nil }
}

private struct R81AuthorizationProvider: MicrophoneAuthorizationProviding {
    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }
}

private final class R81DeviceMonitor:
    MacSpeechDeviceRouteMonitoring,
    @unchecked Sendable {
    private let route = MacSpeechDeviceRoute(
        input: MacSpeechAudioDevice(
            identifier: "r81-input",
            name: "R8.1 Input",
            isAvailable: true
        ),
        output: MacSpeechAudioDevice(
            identifier: "r81-output",
            name: "R8.1 Output",
            isAvailable: true
        )
    )

    func currentRoute() -> MacSpeechDeviceRoute { route }
    func start(onChange: @escaping @Sendable () -> Void) {}
    func stop() {}
}

private final class R81AECBackend: MacSpeechAECBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var captureOutput: [Float]?

    func configure() throws {}
    func processRender(_ samples: [Float]) throws {}

    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult {
        let processed = lock.withLock { captureOutput ?? samples }
        return MacSpeechAECCaptureResult(
            processedSamples: processed,
            linearOutputSamples: stride(
                from: 0,
                to: processed.count,
                by: 3
            ).map { index in
                (processed[index] + processed[index + 1]
                    + processed[index + 2]) / 3
            }
        )
    }

    func setDelay(milliseconds: Int) throws {}
    func reset() throws {}

    func stats() throws -> MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(
            enabled: true,
            active: true,
            estimatedDelayMilliseconds: 0,
            erlDecibels: 12,
            erleDecibels: 24
        )
    }

    func setCaptureOutput(_ samples: [Float]) {
        lock.withLock { captureOutput = samples }
    }
}

private final class R81AudioCapture:
    MacSpeechAudioCapturing,
    @unchecked Sendable {
    private let lock = NSLock()
    private var frameBuffer: MacSpeechAudioFrameBuffer?
    private var generation: UInt64?
    private var started = false
    let acousticEchoHost: MacSpeechAcousticEchoHost

    init(acousticEchoHost: MacSpeechAcousticEchoHost) {
        self.acousticEchoHost = acousticEchoHost
    }

    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        lock.withLock {
            started = true
            self.generation = generation
            self.frameBuffer = frameBuffer
        }
        return MacSpeechNativeInputFormat(
            sampleRate: 48_000,
            channelCount: 1
        )
    }

    func stop() {
        lock.withLock { started = false }
    }

    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot? {
        acousticEchoHost.snapshot()
    }

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot? {
        acousticEchoHost.acousticObservationSnapshot()
    }

    func resetAcousticEchoDiagnostics() {
        acousticEchoHost.resetDiagnostics()
    }

    var isStarted: Bool { lock.withLock { started } }

    @discardableResult
    func emit(_ marker: UInt8) -> Bool {
        let target = lock.withLock { (started, frameBuffer, generation) }
        guard target.0,
              let frameBuffer = target.1,
              let generation = target.2 else { return false }
        return frameBuffer.append(
            pcm16Bytes: Data(repeating: marker, count: 960),
            activity: 0.25,
            generation: generation
        )
    }
}

private actor R81RealtimeProvider: RealtimeResidentBrainProvider {
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var contextUpdates: [RealtimeBrainRuntimeContextUpdate] = []
    private var audioFrames: [RealtimeBrainAudioFrame] = []
    private var responseCreateCommands:
        [RealtimeBrainCreateResponseCommand] = []
    private var interruptCommands: [RealtimeBrainInterruptCommand] = []
    private var closeCommands: [RealtimeBrainCloseSessionCommand] = []
    private var events: [RealtimeResidentBrainEvent] = []
    private var receiveCallCount = 0
    private var receiveContinuation:
        CheckedContinuation<RealtimeResidentBrainEvent, Error>?
    private var holdsInterrupt = false
    private var wakesReceiveOnInterrupt = false
    private var interruptContinuation: CheckedContinuation<Void, Never>?
    private var nextInterruptError: RealtimeResidentBrainError?
    private var holdsAudio = false
    private var audioContinuation: CheckedContinuation<Void, Never>?

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        openCommands.append(command)
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {
        contextUpdates.append(update)
        if update.kind == .bootstrap {
            deliver(RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(
                    session: update.identity,
                    turnID: nil,
                    responseID: nil,
                    contextRevision: update.contextRevision
                ),
                sequence: 1,
                kind: .sessionReady
            ))
        }
    }

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {
        audioFrames.append(frame)
        if holdsAudio {
            await withCheckedContinuation { continuation in
                audioContinuation = continuation
            }
        }
    }

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {}

    func createResponse(
        _ command: RealtimeBrainCreateResponseCommand
    ) async throws {
        responseCreateCommands.append(command)
    }

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {}

    func interrupt(_ command: RealtimeBrainInterruptCommand) async throws {
        interruptCommands.append(command)
        if let error = nextInterruptError {
            nextInterruptError = nil
            throw error
        }
        if holdsInterrupt {
            await withCheckedContinuation { continuation in
                interruptContinuation = continuation
            }
        }
        if wakesReceiveOnInterrupt, let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(
                    session: command.identity,
                    turnID: nil,
                    responseID: nil,
                    contextRevision: contextUpdates.last?.contextRevision ?? 1
                ),
                sequence: 1,
                kind: .cancelled(.interrupted)
            ))
        }
    }

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        receiveCallCount += 1
        if !events.isEmpty { return events.removeFirst() }
        return try await withCheckedThrowingContinuation { continuation in
            precondition(receiveContinuation == nil)
            receiveContinuation = continuation
        }
    }

    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws {
        closeCommands.append(command)
        let continuation = receiveContinuation
        receiveContinuation = nil
        continuation?.resume(throwing: RealtimeResidentBrainError.cancelled)
    }

    func enqueue(_ event: RealtimeResidentBrainEvent) {
        deliver(event)
    }

    func holdInterrupt() {
        holdsInterrupt = true
    }

    func enableInterruptReceiveWake() {
        wakesReceiveOnInterrupt = true
    }

    func failNextInterrupt(_ error: RealtimeResidentBrainError) {
        nextInterruptError = error
    }

    func holdAudio() {
        holdsAudio = true
    }

    func releaseAudio() {
        holdsAudio = false
        let continuation = audioContinuation
        audioContinuation = nil
        continuation?.resume()
    }

    func isAudioHeld() -> Bool {
        audioContinuation != nil
    }

    func releaseInterrupt() {
        holdsInterrupt = false
        let continuation = interruptContinuation
        interruptContinuation = nil
        continuation?.resume()
    }

    func isInterruptHeld() -> Bool {
        interruptContinuation != nil
    }

    func hasPendingReceive() -> Bool {
        receiveContinuation != nil
    }

    func openCount() -> Int { openCommands.count }
    func audioCount() -> Int { audioFrames.count }
    func interruptCount() -> Int { interruptCommands.count }
    func closeCount() -> Int { closeCommands.count }
    func responseCreateCount() -> Int { responseCreateCommands.count }

    func recordedResponseCreateCommands()
        -> [RealtimeBrainCreateResponseCommand] {
        responseCreateCommands
    }
    func receiveCount() -> Int { receiveCallCount }

    func lastAudioFrame() -> RealtimeBrainAudioFrame? {
        audioFrames.last
    }

    func lastCloseCommand() -> RealtimeBrainCloseSessionCommand? {
        closeCommands.last
    }

    func closeGenerations() -> [UInt64] {
        closeCommands.map(\.identity.generation)
    }

    func lastInterruptCommand() -> RealtimeBrainInterruptCommand? {
        interruptCommands.last
    }

    func latestSession() -> RealtimeBrainSessionIdentity? {
        openCommands.last?.identity
    }

    private func deliver(_ event: RealtimeResidentBrainEvent) {
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: event)
        } else {
            events.append(event)
        }
    }
}

private actor R81StartBarrier {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waiterCount() -> Int { waiters.count }

    func release() {
        isOpen = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: true)
        pending.forEach { $0.resume() }
    }
}

private struct R81Target {
    let session: RealtimeBrainSessionIdentity
    let turnID: RealtimeBrainTurnID
    let responseID: RealtimeBrainResponseID
    let contextRevision: UInt64
}

private struct R81Stack {
    let runtime: RuntimeCore
    let provider: R81RealtimeProvider
    let sessionStore: SessionStore
    let target: R81Target
}

@MainActor
private struct R81ControllerStack {
    let controller: AppController
    let runtime: RuntimeCore
    let provider: R81RealtimeProvider
    let aecBackend: R81AECBackend
    let acousticEchoHost: MacSpeechAcousticEchoHost
    let capture: R81AudioCapture
    let outputPlayer: FakeMacSpeechAudioOutputPlayer
    let session: RealtimeBrainSessionIdentity
    let target: R81Target
}

@MainActor
@main
private struct RealtimeInterruptionEvidenceTests {
    private static var cases = 0
    private static var checks = 0
    private static var acousticOnlyPlaybackClearCount = -1

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        let primary = try await makeStack(fixture: fixture)
        cases += 1
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(primary.target, sequence: 0)
                ),
            equals: .ignored(.invalidEvidence),
            "zero source sequence is invalid"
        )
        for wrongSession in wrongSessions(for: primary.target.session) {
            expectDecision(
                await primary.runtime
                    .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                        acoustic(
                            R81Target(
                                session: wrongSession,
                                turnID: primary.target.turnID,
                                responseID: primary.target.responseID,
                                contextRevision: primary.target.contextRevision
                            ),
                            sequence: 1
                        )
                    ),
                equals: .ignored(.staleIdentity),
                "wrong session, lease, epoch, or generation is stale"
            )
        }
        let now = monotonicNow()
        let expiredTimestamp = now > 3_000_000_000
            ? now - 3_000_000_000 : 1
        expectDecision(
            await primary.runtime.submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acoustic(
                    primary.target,
                    sequence: 1,
                    timestamp: expiredTimestamp
                )
            ),
            equals: .ignored(.invalidEvidence),
            "expired acoustic evidence is rejected by the fixed freshness fence"
        )
        expectDecision(
            await primary.runtime.submitRealtimeResidentBrainAcousticEvidenceForTesting(
                semantic(primary.target, sequence: 4)
            ),
            equals: .ignored(.invalidEvidence),
            "Host cannot forge Realtime Brain semantic evidence"
        )
        expectDecision(
            await primary.runtime.submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acoustic(primary.target, sequence: 1, confidence: 0)
            ),
            equals: .ignored(.invalidEvidence),
            "zero render-reference confidence cannot confirm interruption"
        )
        let invalidInterruptCount = await primary.provider.interruptCount()
        expect(invalidInterruptCount == 0,
               "invalid identity evidence has no Provider side effect")

        cases += 1
        let primaryAcoustic = acoustic(primary.target, sequence: 2)
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    primaryAcoustic
                ),
            equals: .observed,
            "acoustic evidence alone is observed"
        )
        let acousticOnlyInterruptCount = await primary.provider.interruptCount()
        expect(acousticOnlyInterruptCount == 0,
               "acoustic evidence alone cannot interrupt")
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    primaryAcoustic
                ),
            equals: .ignored(.duplicateEvidence),
            "duplicate acoustic evidence is ignored"
        )
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(primary.target, sequence: 1)
                ),
            equals: .ignored(.staleEvidence),
            "out-of-order acoustic evidence is stale"
        )

        cases += 1
        let wrongTarget = R81Target(
            session: primary.target.session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: primary.target.contextRevision
        )
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(wrongTarget, sequence: 3)
                ),
            equals: .ignored(.staleEvidence),
            "unowned turn and response cannot enter evidence fusion"
        )
        let wrongContext = R81Target(
            session: primary.target.session,
            turnID: primary.target.turnID,
            responseID: primary.target.responseID,
            contextRevision: primary.target.contextRevision + 1
        )
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(wrongContext, sequence: 3)
                ),
            equals: .ignored(.staleEvidence),
            "wrong context revision cannot enter evidence fusion"
        )

        let wrongSemantic = try await makeStack(fixture: fixture)
        cases += 1
        let wrongSemanticTarget = R81Target(
            session: wrongSemantic.target.session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: wrongSemantic.target.contextRevision
        )
        let wrongSemanticEvent = proposalEvent(
            wrongSemanticTarget,
            sequence: 4
        )
        let wrongSemanticResult = try await receiveProposal(
            wrongSemantic,
            event: wrongSemanticEvent
        )
        expect(
            wrongSemanticResult.disposition == .rejectedInvalidEvent,
            "Provider cannot make an invented turn and response active"
        )
        expectDecision(
            wrongSemanticResult.decision,
            equals: .ignored(.staleEvidence),
            "semantic evidence for an unowned turn and response cannot fuse"
        )

        let semanticOnly = try await makeStack(fixture: fixture)
        cases += 1
        let semanticOnlyEvent = proposalEvent(
            semanticOnly.target,
            sequence: 4
        )
        let semanticOnlyDisposition = try await receiveProposal(
            semanticOnly,
            event: semanticOnlyEvent
        )
        expect(
            semanticOnlyDisposition.disposition
                == .accepted(semanticOnlyEvent),
            "Runtime accepts an identity-bound semantic proposal"
        )
        expectDecision(
            semanticOnlyDisposition.decision,
            equals: .observed,
            "semantic evidence alone is observed"
        )
        let semanticOnlyInterruptCount = await semanticOnly.provider
            .interruptCount()
        expect(semanticOnlyInterruptCount == 0,
               "semantic evidence alone cannot interrupt")
        let semanticOnlyLease = semanticOnly.runtime.activeBrainLeaseForTesting()
        expect(
            semanticOnlyLease?.brainLeaseID
                == semanticOnly.target.session.brainLeaseID,
            "semantic evidence alone preserves the active Brain lease"
        )
        await semanticOnly.provider.enqueue(semanticOnlyEvent)
        let duplicateSemantic = try await semanticOnly.runtime
            .receiveRealtimeResidentBrainEvent(
                session: semanticOnly.target.session
            )
        expect(duplicateSemantic == .rejectedDuplicate,
               "duplicate semantic evidence is rejected at the event fence")
        let staleSemanticEvent = proposalEvent(
            semanticOnly.target,
            sequence: 3
        )
        await semanticOnly.provider.enqueue(staleSemanticEvent)
        let staleSemantic = try await semanticOnly.runtime
            .receiveRealtimeResidentBrainEvent(
                session: semanticOnly.target.session
            )
        expect(staleSemantic == .rejectedDuplicate,
               "stale semantic sequence is rejected at the event fence")

        let responseAuthority = try await makeStack(fixture: fixture)
        cases += 1
        let repeatedFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: responseAuthority.target.session,
                turnID: responseAuthority.target.turnID,
                responseID: nil,
                contextRevision: responseAuthority.target.contextRevision
            ),
            sequence: 4,
            kind: .userTranscriptFinal("repeat the same final")
        )
        await responseAuthority.provider.enqueue(repeatedFinal)
        let repeatedFinalDisposition = try await responseAuthority.runtime
            .receiveRealtimeResidentBrainEvent(
                session: responseAuthority.target.session
            )
        expect(
            repeatedFinalDisposition == .accepted(repeatedFinal),
            "a repeated final on the authorized turn remains one-shot"
        )
        let overlapTurn = RealtimeBrainTurnID()
        let overlapFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: responseAuthority.target.session,
                turnID: overlapTurn,
                responseID: nil,
                contextRevision: responseAuthority.target.contextRevision
            ),
            sequence: 5,
            kind: .userTranscriptFinal("overlap is not queued")
        )
        await responseAuthority.provider.enqueue(overlapFinal)
        let overlapDisposition = try await responseAuthority.runtime
            .receiveRealtimeResidentBrainEvent(
                session: responseAuthority.target.session
            )
        expect(
            overlapDisposition == .accepted(overlapFinal),
            "overlapping final is consumed without Provider auto-response"
        )
        let oneShotCommands = await responseAuthority.provider
            .recordedResponseCreateCommands()
        expect(
            oneShotCommands.count == 1,
            "repeated and overlapping finals cannot duplicate response.create"
        )
        let terminal = RealtimeResidentBrainEvent(
            identity: eventIdentity(responseAuthority.target),
            sequence: 6,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "The authorized response is complete."
            ))
        )
        await responseAuthority.provider.enqueue(terminal)
        let terminalDisposition = try await responseAuthority.runtime
            .receiveRealtimeResidentBrainEvent(
                session: responseAuthority.target.session
            )
        expect(
            terminalDisposition == .accepted(terminal),
            "the authorized response reaches its terminal boundary"
        )
        expectRealtimeSuccess(
            await responseAuthority.runtime
                .updateRealtimeResidentBrainContext(
                    RealtimeBrainRuntimeContextUpdate(
                        identity: responseAuthority.target.session,
                        kind: .delta,
                        contextRevision: 3,
                        sections: [RealtimeBrainContextSection(
                            scope: .dynamicSession,
                            content: "overlap drop leaves no orphan turn"
                        )]
                    )
                ),
            "overlap drop leaves no pending turn or transcript"
        )
        expectRealtimeSuccess(
            await responseAuthority.runtime.closeRealtimeResidentBrainSession(
                identity: responseAuthority.target.session
            ),
            "response-authority fixture closes"
        )

        cases += 1
        let primaryProposal = proposalEvent(primary.target, sequence: 4)
        let primaryProposalResult = try await receiveProposal(
            primary,
            event: primaryProposal
        )
        let primaryDecision = confirmedDecision(
            primaryProposalResult.decision,
            message: "matching acoustic and semantic evidence confirms"
        )
        let nextSession = expectRealtimeIdentity(
            await primary.runtime.completeRealtimeResidentBrainInterruption(
                primaryDecision
            ),
            "confirmed interruption settles the Provider transition"
        )
        expect(nextSession.generation == primary.target.session.generation + 1,
               "Runtime confirmation advances generation exactly once")
        expect(
            nextSession.brainLeaseID == primary.target.session.brainLeaseID
                && nextSession.routeEpoch == primary.target.session.routeEpoch
                && nextSession.runtimeSessionID
                    == primary.target.session.runtimeSessionID,
            "confirmed interruption preserves session, lease, and epoch"
        )
        let primaryInterruptCount = await primary.provider.interruptCount()
        expect(primaryInterruptCount == 1,
               "Runtime sends exactly one Provider interrupt")
        let primaryOpenCount = await primary.provider.openCount()
        let primaryCloseCount = await primary.provider.closeCount()
        expect(primaryOpenCount == 1 && primaryCloseCount == 0,
               "confirmed interruption does not reopen or close Provider")
        let primaryInterruptCommand = await primary.provider
            .lastInterruptCommand()
        expect(primaryInterruptCommand?.nextGeneration == nextSession.generation,
               "Provider command carries the Runtime-issued generation")

        cases += 1
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    primaryAcoustic
                ),
            equals: .ignored(.staleIdentity),
            "old-generation duplicate evidence is stale after confirmation"
        )
        let duplicateInterruptCount = await primary.provider.interruptCount()
        expect(duplicateInterruptCount == 1,
               "duplicate evidence cannot interrupt twice")

        let reverse = try await makeStack(fixture: fixture)
        cases += 1
        let reverseProposal = proposalEvent(reverse.target, sequence: 4)
        let reverseProposalResult = try await receiveProposal(
            reverse,
            event: reverseProposal
        )
        expectDecision(
            reverseProposalResult.decision,
            equals: .observed,
            "semantic-first fusion waits for acoustic evidence"
        )
        let reverseDecision = await reverse.runtime
            .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acoustic(reverse.target, sequence: 2)
            )
        let reverseConfirmation = confirmedDecision(
            reverseDecision,
            message: "fusion is deterministic in either arrival order"
        )
        let reverseNextSession = expectRealtimeIdentity(
            await reverse.runtime.completeRealtimeResidentBrainInterruption(
                reverseConfirmation
            ),
            "reverse-order interruption settles"
        )
        let reverseInterruptCount = await reverse.provider.interruptCount()
        expect(reverseInterruptCount == 1,
               "reverse-order fusion interrupts once")

        let mutationRace = try await makeStack(fixture: fixture)
        cases += 1
        await mutationRace.provider.holdAudio()
        let pendingInput = Task { @MainActor in
            await mutationRace.runtime.appendRealtimeResidentBrainAudio(
                inputFrame(session: mutationRace.target.session)
            )
        }
        await waitUntil("old-generation audio mutation is in flight") {
            await mutationRace.provider.isAudioHeld()
        }
        let mutationProposal = proposalEvent(
            mutationRace.target,
            sequence: 4
        )
        let mutationProposalResult = try await receiveProposal(
            mutationRace,
            event: mutationProposal
        )
        expectDecision(
            mutationProposalResult.decision,
            equals: .observed,
            "in-flight mutation fixture records semantic evidence"
        )
        let mutationDecision = confirmedDecision(
            await mutationRace.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(mutationRace.target, sequence: 2)
                ),
            message: "in-flight audio cannot block Runtime confirmation"
        )
        let mutationInterruptCountBeforeDrain = await mutationRace.provider
            .interruptCount()
        expect(
            mutationInterruptCountBeforeDrain == 0,
            "Provider interrupt waits for the retired audio mutation"
        )
        await mutationRace.provider.releaseAudio()
        expectFailure(
            await pendingInput.value,
            equals: .cancelled,
            "retired in-flight audio resolves as cancelled"
        )
        let mutationNextSession = expectRealtimeIdentity(
            await mutationRace.runtime
                .completeRealtimeResidentBrainInterruption(mutationDecision),
            "Provider interrupt runs after the retired mutation drains"
        )
        let mutationInterruptCountAfterDrain = await mutationRace.provider
            .interruptCount()
        expect(
            mutationInterruptCountAfterDrain == 1
                && mutationNextSession.generation
                    == mutationRace.target.session.generation + 1,
            "mutation race produces one interrupt and one generation advance"
        )

        let race = try await makeStack(fixture: fixture)
        let dialogueBefore = try race.sessionStore.loadMostRecentDialogueEntries()
        let narrativeBefore = race.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = race.runtime.currentRelationshipState
        let raceProposal = proposalEvent(race.target, sequence: 4)
        let raceProposalResult = try await receiveProposal(
            race,
            event: raceProposal
        )
        expectDecision(
            raceProposalResult.decision,
            equals: .observed,
            "race fixture records authentic semantic evidence"
        )
        await race.provider.holdInterrupt()
        let duplicateBarrier = R81StartBarrier()
        let duplicateAcoustic = acoustic(race.target, sequence: 2)
        let firstSubmission = Task { @MainActor in
            await duplicateBarrier.wait()
            return await race.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    duplicateAcoustic
                )
        }
        let secondSubmission = Task { @MainActor in
            await duplicateBarrier.wait()
            return await race.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    duplicateAcoustic
                )
        }
        await waitUntil("concurrent duplicate evidence is ready") {
            await duplicateBarrier.waiterCount() == 2
        }
        await duplicateBarrier.release()
        let concurrentResults = [
            await firstSubmission.value,
            await secondSubmission.value
        ]
        let confirmations: [RealtimeConfirmedInterruption] =
            concurrentResults.compactMap { result in
                guard case .success(.confirmed(let decision)) = result else {
                    return nil
                }
                return decision
            }
        let ignoredDuplicates = concurrentResults.filter { result in
            guard case .success(.ignored(let reason)) = result else {
                return false
            }
            return reason == .staleIdentity || reason == .duplicateEvidence
        }
        expect(
            confirmations.count == 1 && ignoredDuplicates.count == 1,
            "concurrent duplicate evidence yields one Runtime confirmation"
        )
        guard let raceConfirmation = confirmations.first else {
            fatalError("concurrent Runtime confirmation missing")
        }
        await waitUntil("held Provider interrupt") {
            await race.provider.isInterruptHeld()
        }
        expect(raceConfirmation.hostCommand == .clearPlayback,
               "Runtime publishes the Host command while Provider is held")

        cases += 1
        await race.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(race.target),
            sequence: 5,
            kind: .residentAudioDelta(audioDelta(sequence: 2))
        ))
        let pendingDisposition = try await race.runtime
            .receiveRealtimeResidentBrainEvent(
                session: race.target.session
            )
        expect(pendingDisposition == .rejectedStale,
               "old output audio is rejected while Provider interrupt is held")
        let oldInput = await race.runtime.appendRealtimeResidentBrainAudio(
            inputFrame(session: race.target.session)
        )
        expectFailure(oldInput, equals: .invalidIdentity,
                      "old input audio is rejected after Runtime confirmation")
        let rejectedAudioCount = await race.provider.audioCount()
        expect(rejectedAudioCount == 0,
               "rejected old input never reaches Provider")

        cases += 1
        expectDecision(
            await race.runtime.submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acoustic(race.target, sequence: 2)
            ),
            equals: .ignored(.staleIdentity),
            "duplicate evidence during confirmation cannot start a second transition"
        )
        expectDecision(
            await race.runtime.claimRealtimeResidentBrainInterruptionDecision(
                for: raceProposal
            ),
            equals: .ignored(.staleEvidence),
            "a semantic proposal decision can be claimed only once"
        )
        let heldInterruptCount = await race.provider.interruptCount()
        expect(heldInterruptCount == 1,
               "in-flight duplicate evidence sends one Provider interrupt")

        await race.provider.releaseInterrupt()
        let raceNextSession = expectRealtimeIdentity(
            await race.runtime.completeRealtimeResidentBrainInterruption(
                raceConfirmation
            ),
            "held Provider acknowledgement completes confirmation"
        )
        expect(
            raceNextSession.generation
                == race.target.session.generation + 1,
            "concurrent duplicate evidence advances generation exactly once"
        )
        let lateAudio = try await race.runtime
            .receiveRealtimeResidentBrainEvent(session: raceNextSession)
        expect(lateAudio == .rejectedStale,
               "queued old Provider audio stays stale after settlement")

        cases += 1
        let lateIdentity = eventIdentity(race.target)
        await race.provider.enqueue(RealtimeResidentBrainEvent(
            identity: lateIdentity,
            sequence: 6,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "late old response",
                narrativeMemoryCandidates: [
                    RealtimeBrainNarrativeMemoryCandidate(
                        identity: lateIdentity,
                        candidateID: "late-r81-memory",
                        memoryType: "confirmed_plan",
                        summary: "This stale candidate must never be committed.",
                        sourceTurnIDs: [
                            race.target.turnID.rawValue.uuidString.lowercased()
                        ],
                        consentSignal: "explicit_remember_request",
                        sensitivityFlags: [],
                        evidenceSource: "explicit_user_statement",
                        inputClassification: "explicit_memory_worthy",
                        confidence: 0.95
                    )
                ],
                relationshipEvidenceCandidates: [
                    RealtimeBrainRelationshipEvidenceCandidate(
                        identity: lateIdentity,
                        evidenceType: "explicit_familiarity_or_trust",
                        evidenceDetected: true,
                        evidenceSource: "explicit_user_expression",
                        requiresUserConfirmation: false,
                        confidence: 0.95
                    )
                ]
            ))
        ))
        let lateSemantic = try await race.runtime
            .receiveRealtimeResidentBrainEvent(session: raceNextSession)
        expect(lateSemantic == .rejectedStale,
               "late old semantic final is rejected as stale")
        let dialogueAfter = try race.sessionStore.loadMostRecentDialogueEntries()
        expect(dialogueAfter == dialogueBefore,
               "late semantic final writes no dialogue history")
        expect(race.runtime.narrativeMemoryDebugSnapshot() == narrativeBefore,
               "late semantic final writes no Narrative Memory")
        expect(race.runtime.currentRelationshipState == relationshipBefore,
               "late semantic final writes no Relationship state")
        let raceInterruptCount = await race.provider.interruptCount()
        expect(raceInterruptCount == 1,
               "late callbacks cannot trigger another Provider interrupt")

        let memoryControl = try await makeStack(fixture: fixture)
        cases += 1
        let memoryControlIdentity = eventIdentity(memoryControl.target)
        await memoryControl.provider.enqueue(RealtimeResidentBrainEvent(
            identity: memoryControlIdentity,
            sequence: 4,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "Remember the current-generation plan.",
                narrativeMemoryCandidates: [
                    RealtimeBrainNarrativeMemoryCandidate(
                        identity: memoryControlIdentity,
                        candidateID: "r81-current-memory-control",
                        memoryType: "confirmed_plan",
                        summary: "Current-generation memory control.",
                        sourceTurnIDs: [
                            memoryControl.target.turnID.rawValue.uuidString
                                .lowercased()
                        ],
                        consentSignal: "explicit_remember_request",
                        sensitivityFlags: [],
                        evidenceSource: "explicit_user_statement",
                        inputClassification: "explicit_memory_worthy",
                        confidence: 0.95
                    )
                ]
            ))
        ))
        guard case .accepted = try await memoryControl.runtime
                .receiveRealtimeResidentBrainEvent(
                    session: memoryControl.target.session
                ) else {
            fatalError("current-generation memory control was not accepted")
        }
        expect(
            memoryControl.runtime.narrativeMemoryDebugSnapshot()?.records
                .contains { record in
                    record.summary == "Current-generation memory control."
                } == true,
            "current-generation candidate proves the durable Memory observer"
        )
        expectRealtimeSuccess(
            await memoryControl.runtime.closeRealtimeResidentBrainSession(
                identity: memoryControl.target.session
            ),
            "memory control session closes"
        )

        try await testControllerSemanticFirstInterruption(fixture: fixture)
        try await testControllerPlaybackCompletionAndStopRace(fixture: fixture)
        try await testControllerInterruptFailureCanRestart(fixture: fixture)

        cases += 1
        expectRealtimeSuccess(
            await primary.runtime.closeRealtimeResidentBrainSession(
                identity: nextSession
            ),
            "primary session closes"
        )
        expectRealtimeSuccess(
            await semanticOnly.runtime.closeRealtimeResidentBrainSession(
                identity: semanticOnly.target.session
            ),
            "semantic-only session closes"
        )
        expectRealtimeSuccess(
            await wrongSemantic.runtime.closeRealtimeResidentBrainSession(
                identity: wrongSemantic.target.session
            ),
            "wrong-semantic session closes"
        )
        let reverseNext = reverse.runtime.activeBrainLeaseForTesting()
        expect(reverseNext?.brainLeaseID == reverse.target.session.brainLeaseID,
               "reverse fusion keeps the original Brain lease")
        expectRealtimeSuccess(
            await reverse.runtime.closeRealtimeResidentBrainSession(
                identity: reverseNextSession
            ),
            "reverse-order session closes"
        )
        expectRealtimeSuccess(
            await mutationRace.runtime.closeRealtimeResidentBrainSession(
                identity: mutationNextSession
            ),
            "mutation-race session closes"
        )
        expectRealtimeSuccess(
            await race.runtime.closeRealtimeResidentBrainSession(
                identity: raceNextSession
            ),
            "race session closes"
        )

        print("realtime_interruption_evidence_cases=\(cases)")
        print("realtime_interruption_evidence_checks=\(checks)")
        print("r81_acoustic_only_playback_clears=\(acousticOnlyPlaybackClearCount)")
    }

    private static func testControllerSemanticFirstInterruption(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeControllerStack(fixture: fixture)
        let receiveCountBeforeProposal = await stack.provider.receiveCount()
        await stack.provider.enqueue(proposalEvent(stack.target, sequence: 4))
        await waitUntil("semantic proposal consumed") {
            await stack.provider.receiveCount() > receiveCountBeforeProposal
        }
        let semanticOnlyInterruptCount = await stack.provider.interruptCount()
        let semanticOnlyOpenCount = await stack.provider.openCount()
        let semanticOnlyCloseCount = await stack.provider.closeCount()
        let semanticOnlyResponseCreateCount = await stack.provider
            .responseCreateCount()
        expect(
            semanticOnlyInterruptCount == 0
                && semanticOnlyResponseCreateCount == 1
                && stack.outputPlayer.clearScheduledPlaybackCount == 0
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .speaking,
            "Brain semantic evidence alone cannot create, clear, or interrupt"
        )
        expect(
            semanticOnlyOpenCount == 1
                && semanticOnlyCloseCount == 0
                && stack.capture.isStarted,
            "semantic evidence alone preserves Provider session and Capture"
        )

        await stack.provider.holdInterrupt()
        await emitNearEndEvidence(stack, marker: 0x31, expectedAudioCount: 3)
        await waitUntil("Host clear before held Provider settlement") {
            await stack.provider.isInterruptHeld()
                && stack.outputPlayer.clearScheduledPlaybackCount == 1
        }
        expect(
            stack.outputPlayer.clearScheduledPlaybackCount == 1,
            "Runtime-issued command pre-clears Playback before Provider ACK"
        )
        await stack.provider.releaseInterrupt()
        await waitUntil("semantic-first interruption rebound") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .listening
                && stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == stack.session.generation + 1
                && stack.controller.realtimeBrainInputBridgeSnapshot
                    .hasActivePump
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop
        }
        guard let interruptCommand = await stack.provider
                .lastInterruptCommand() else {
            fatalError("confirmed Host interruption command missing")
        }
        let nextSession = nextSession(
            after: stack.session,
            generation: interruptCommand.nextGeneration
        )
        stack.outputPlayer.completeStoppedChunk()
        expect(stack.capture.emit(0x41),
               "persistent Capture submits the next-generation frame")
        await waitUntil("next-generation input reaches Provider") {
            await stack.provider.audioCount() == 4
        }
        let nextInput = await stack.provider.lastAudioFrame()
        expect(
            nextInput?.identity == nextSession && nextInput?.sequence == 1,
            "next interaction reuses Capture with sequence reset to one"
        )

        let nextTarget = R81Target(
            session: nextSession,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: nextSession,
                turnID: nextTarget.turnID,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .userTranscriptFinal("next turn")
        ))
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(nextTarget),
            sequence: 2,
            kind: .residentAudioDelta(audioDelta(sequence: 1))
        ))
        await waitUntil("next-generation response speaking") {
            stack.outputPlayer.startCount == 2
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .speaking
        }
        let responseCreateCount = await stack.provider.responseCreateCount()
        expect(
            responseCreateCount == 2,
            "two accepted user finals receive exactly two Runtime create commands"
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(nextTarget),
            sequence: 3,
            kind: .residentSpeakingStopped
        ))
        await waitUntil("next response marked draining") {
            stack.controller.speechAudioOutputHostSnapshot.state == .draining
        }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil("next response returns listening") {
            stack.outputPlayer.finishPlaybackCount == 1
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
                && stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == nextSession.generation
        }
        let openCount = await stack.provider.openCount()
        let closeCount = await stack.provider.closeCount()
        expect(openCount == 1 && closeCount == 0 && stack.capture.isStarted,
               "two turns keep one Provider session and persistent Capture")
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testControllerPlaybackCompletionAndStopRace(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeControllerStack(fixture: fixture)
        await emitNearEndEvidence(stack, marker: 0x51, expectedAudioCount: 3)
        let acousticOnlyInterruptCount = await stack.provider.interruptCount()
        expect(
            acousticOnlyInterruptCount == 0
                && stack.outputPlayer.clearScheduledPlaybackCount == 0
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .speaking,
            "Host acoustic evidence alone cannot clear Playback or interrupt"
        )
        acousticOnlyPlaybackClearCount =
            stack.outputPlayer.clearScheduledPlaybackCount

        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 4,
            kind: .residentSpeakingStopped
        ))
        await waitUntil("old response marked draining") {
            stack.controller.speechAudioOutputHostSnapshot.state == .draining
        }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil("old Playback naturally completed") {
            stack.outputPlayer.finishPlaybackCount == 1
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
        }
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "natural completion does not impersonate interruption clear")

        await stack.provider.holdInterrupt()
        await stack.provider.enqueue(proposalEvent(stack.target, sequence: 5))
        await waitUntil("completed Playback still receives confirmed command") {
            await stack.provider.isInterruptHeld()
                && stack.outputPlayer.clearScheduledPlaybackCount == 1
        }
        expect(
            stack.controller.formalSpeechRouteDebugSnapshot.generation
                == stack.session.generation,
            "Host does not bind the next generation before Provider settlement"
        )
        let stopTask = Task { @MainActor in
            await stack.controller.stopSpeechAudioCapture()
        }
        await waitUntil("Stop halts Capture while Provider is held") {
            !stack.capture.isStarted
        }
        await stack.provider.releaseInterrupt()
        await stopTask.value
        let closeCommand = await stack.provider.lastCloseCommand()
        expect(
            closeCommand?.identity.generation == stack.session.generation + 1,
            "Stop closes the Runtime-confirmed next identity, not the stale one"
        )
        let openCount = await stack.provider.openCount()
        let closeCount = await stack.provider.closeCount()
        expect(
            openCount == 1 && closeCount == 1 && !stack.capture.isStarted,
            "Stop during confirmation leaves no Provider lease or Capture leak"
        )
        expect(
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .idle,
            "Stop during confirmation settles the formal Realtime route"
        )
    }

    private static func testControllerInterruptFailureCanRestart(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeControllerStack(fixture: fixture)
        await stack.provider.failNextInterrupt(.transportFailure)
        await emitNearEndEvidence(stack, marker: 0x61, expectedAudioCount: 3)
        await stack.provider.enqueue(proposalEvent(stack.target, sequence: 4))
        await waitUntil("failed Provider interruption settles Host route") {
            let closeCount = await stack.provider.closeCount()
            return closeCount == 2
                && !stack.capture.isStarted
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .failed
        }
        expect(
            stack.outputPlayer.clearScheduledPlaybackCount == 1,
            "confirmed Host command clears Playback before Provider failure settles"
        )
        let interruptCount = await stack.provider.interruptCount()
        let closeCount = await stack.provider.closeCount()
        let closeGenerations = await stack.provider.closeGenerations()
        expect(
            interruptCount == 1
                && closeCount == 2
                && closeGenerations.sorted() == [
                    stack.session.generation,
                    stack.session.generation + 1
                ]
                && stack.runtime.activeBrainLeaseForTesting() == nil,
            "failed transition closes old and pending identities once each"
        )

        await stack.controller.startRealtimeResidentBrainRoute()
        await waitUntil("formal Realtime route restarts after Provider failure") {
            await stack.provider.openCount() == 2
                && stack.capture.isStarted
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
        }
        expect(
            stack.controller.realtimeBrainInputBridgeSnapshot.hasActivePump
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop,
            "failed transition leaves no closed binding that blocks restart"
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func makeControllerStack(
        fixture: Data
    ) async throws -> R81ControllerStack {
        let provider = R81RealtimeProvider()
        await provider.enableInterruptReceiveWake()
        let router = ProviderRouter(
            credentialReader: R81CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        let aecBackend = R81AECBackend()
        let acousticEchoHost = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: aecBackend
        )
        expect(acousticEchoHost.configure() == .webRTCAEC3,
               "formal Realtime Host uses the configured AEC evidence source")
        let capture = R81AudioCapture(acousticEchoHost: acousticEchoHost)
        let audioHost = MacSpeechAudioHost(
            authorizationProvider: R81AuthorizationProvider(),
            capture: capture,
            deviceMonitor: R81DeviceMonitor()
        )
        let outputPlayer = FakeMacSpeechAudioOutputPlayer()
        let outputHost = MacSpeechAudioOutputHost(
            player: outputPlayer,
            deviceMonitor: FakeMacSpeechOutputDeviceMonitor(),
            configuration: MacSpeechPCMPlaybackConfiguration(
                capacity: 4,
                lowWatermark: 1,
                consumerTimeoutNanoseconds: 2_000_000_000,
                startupBufferCount: 1,
                startupBufferDurationNanoseconds: 0,
                scheduleAheadCount: 2
            )
        )
        let controller = AppController(
            orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
            speechAudioHost: audioHost,
            speechAudioOutputHost: outputHost
        )
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "r81-controller-\(UUID().uuidString).digital_resident"
            )
        try fixture.write(to: fixtureURL, options: .atomic)
        controller.debugImportResident(from: fixtureURL)
        try? FileManager.default.removeItem(at: fixtureURL)
        expect(controller.isResidentTextInputAvailable,
               "AppController loads the R8.1 fixture resident")

        await controller.startRealtimeResidentBrainRoute()
        await waitUntil("formal Realtime route listening") {
            let hasSession = await provider.latestSession() != nil
            return controller.formalSpeechRouteDebugSnapshot.phase == .listening
                && hasSession
        }
        guard let session = await provider.latestSession() else {
            fatalError("formal Realtime session missing")
        }
        let target = R81Target(
            session: session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let userFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: target.turnID,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 2,
            kind: .userTranscriptFinal("interrupt now")
        )
        await provider.enqueue(userFinal)
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(target),
            sequence: 3,
            kind: .residentAudioDelta(audioDelta(sequence: 1))
        ))
        await waitUntil("resident playback speaking") {
            outputPlayer.startCount == 1
                && controller.formalSpeechRouteDebugSnapshot.phase == .speaking
        }
        let responseCreateCount = await provider.responseCreateCount()
        expect(
            responseCreateCount == 1,
            "the accepted user final receives one Runtime response-create command"
        )
        expect(outputPlayer.clearScheduledPlaybackCount == 0,
               "resident Playback is intact before evidence fusion")
        return R81ControllerStack(
            controller: controller,
            runtime: runtime,
            provider: provider,
            aecBackend: aecBackend,
            acousticEchoHost: acousticEchoHost,
            capture: capture,
            outputPlayer: outputPlayer,
            session: session,
            target: target
        )
    }

    private static func emitNearEndEvidence(
        _ stack: R81ControllerStack,
        marker: UInt8,
        expectedAudioCount: Int
    ) async {
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: 2, amplitude: 0.3)
        let nearEnd = signal(seed: 3, amplitude: 0.25)
        let baseTimestamp = monotonicNow() - 120_000_000
        stack.aecBackend.setCaptureOutput(nearEnd)
        for index in 0 ..< 3 {
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds:
                    baseTimestamp + UInt64(index * 10_000_000)
            )
            _ = stack.acousticEchoHost.processCapture(
                render,
                hostTimeNanoseconds:
                    baseTimestamp + 80_000_000
                        + UInt64(index * 10_000_000)
            )
            try? await Task.sleep(for: .milliseconds(12))
            expect(
                stack.capture.emit(marker &+ UInt8(index)),
                "identity-bound near-end frame enters the Realtime pump"
            )
            await waitUntil("acoustic frame reaches Provider") {
                await stack.provider.audioCount()
                    == expectedAudioCount - 2 + index
            }
        }
        let acoustic = stack.acousticEchoHost.snapshot()
        expect(
            acoustic.sourceAlignmentLocked && acoustic.sourceGateOpen,
            "valid aligned near-end evidence opens the existing source gate"
        )
        for _ in 0 ..< 400 {
            await stack.controller.refreshMicrophoneAuthorization()
            if stack.controller.realtimeBrainInputBridgeSnapshot
                .acousticEvidenceCount == 1 {
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let bridgeSnapshot = stack.controller
            .realtimeBrainInputBridgeSnapshot
        expect(
            bridgeSnapshot.acousticEvidenceCount == 1,
            "Host forwards one source-gate acoustic evidence edge; sends=\(bridgeSnapshot.sendOperationCount), forwarded=\(bridgeSnapshot.forwardedFrameCount)"
        )
    }

    private static func nextSession(
        after session: RealtimeBrainSessionIdentity,
        generation: UInt64
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: session.residentID,
            runtimeSessionID: session.runtimeSessionID,
            brainLeaseID: session.brainLeaseID,
            routeEpoch: session.routeEpoch,
            generation: generation
        )
    }

    private static func signal(
        seed: UInt32,
        amplitude: Float
    ) -> [Float] {
        var state = seed
        return (0 ..< MacSpeechAcousticEchoHost.frameSampleCount).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit = Float(state >> 8) / Float(0x00FF_FFFF)
            return (unit * 2 - 1) * amplitude
        }
    }

    private static func makeStack(fixture: Data) async throws -> R81Stack {
        let provider = R81RealtimeProvider()
        let router = ProviderRouter(
            credentialReader: R81CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let sessionStore = SessionStore()
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: sessionStore
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "interruption evidence fixture resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("Realtime session did not start")
        }
        guard case .accepted(let ready) = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session),
              ready.kind == .sessionReady else {
            fatalError("Realtime session did not become ready")
        }
        let target = R81Target(
            session: session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let userFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: target.turnID,
                responseID: nil,
                contextRevision: target.contextRevision
            ),
            sequence: 2,
            kind: .userTranscriptFinal("interrupt the resident")
        )
        await provider.enqueue(userFinal)
        guard case .accepted = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session) else {
            fatalError("user turn did not activate")
        }
        let responseCreateCommands = await provider
            .recordedResponseCreateCommands()
        expect(
            responseCreateCommands == [RealtimeBrainCreateResponseCommand(
                identity: userFinal.identity,
                sourceEventSequence: userFinal.sequence
            )],
            "Runtime response authorization binds the exact final identity and sequence"
        )
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(target),
            sequence: 3,
            kind: .residentAudioDelta(audioDelta(sequence: 1))
        ))
        guard case .accepted = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session) else {
            fatalError("resident response did not activate")
        }
        return R81Stack(
            runtime: runtime,
            provider: provider,
            sessionStore: sessionStore,
            target: target
        )
    }

    private static func acoustic(
        _ target: R81Target,
        sequence: UInt64,
        timestamp: UInt64? = nil,
        confidence: Double = 1
    ) -> RealtimeInterruptionEvidence {
        RealtimeInterruptionEvidence(
            identity: RealtimeInterruptionEvidenceIdentity(
                session: target.session,
                turnID: target.turnID,
                responseID: target.responseID,
                contextRevision: target.contextRevision,
                sequence: sequence,
                timestampNanoseconds: timestamp ?? monotonicNow()
            ),
            source: .acousticHost(RealtimeInterruptionAcousticFacts(
                sourceGateEpoch: 1,
                nearEndDetected: true,
                farEndActive: true,
                sourceGateOpen: true,
                renderReferenceConfidence: confidence,
                routeStable: true,
                inputDeviceAvailable: true,
                outputDeviceAvailable: true
            ))
        )
    }

    private static func semantic(
        _ target: R81Target,
        sequence: UInt64,
        timestamp: UInt64? = nil
    ) -> RealtimeInterruptionEvidence {
        RealtimeInterruptionEvidence(
            identity: RealtimeInterruptionEvidenceIdentity(
                session: target.session,
                turnID: target.turnID,
                responseID: target.responseID,
                contextRevision: target.contextRevision,
                sequence: sequence,
                timestampNanoseconds: timestamp ?? monotonicNow()
            ),
            source: .realtimeBrain(RealtimeInterruptionSemanticFacts(
                reason: "user_speech_started_during_resident_response"
            ))
        )
    }

    private static func proposalEvent(
        _ target: R81Target,
        sequence: UInt64
    ) -> RealtimeResidentBrainEvent {
        let identity = eventIdentity(target)
        return RealtimeResidentBrainEvent(
            identity: identity,
            sequence: sequence,
            kind: .interruptionProposed(RealtimeBrainInterruptionProposal(
                identity: identity,
                reason: "user_speech_started_during_resident_response"
            ))
        )
    }

    private static func receiveProposal(
        _ stack: R81Stack,
        event: RealtimeResidentBrainEvent
    ) async throws -> (
        disposition: RealtimeBrainEventDisposition,
        decision: Result<
            RealtimeInterruptionDecision,
            RealtimeResidentBrainError
        >
    ) {
        await stack.provider.enqueue(event)
        let disposition = try await stack.runtime
            .receiveRealtimeResidentBrainEvent(session: stack.target.session)
        let decision = await stack.runtime
            .claimRealtimeResidentBrainInterruptionDecision(for: event)
        return (disposition, decision)
    }

    private static func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func wrongSessions(
        for session: RealtimeBrainSessionIdentity
    ) -> [RealtimeBrainSessionIdentity] {
        [
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID + "-wrong",
                brainLeaseID: session.brainLeaseID,
                routeEpoch: session.routeEpoch,
                generation: session.generation
            ),
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID,
                brainLeaseID: UUID(),
                routeEpoch: session.routeEpoch,
                generation: session.generation
            ),
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID,
                brainLeaseID: session.brainLeaseID,
                routeEpoch: session.routeEpoch + 1,
                generation: session.generation
            ),
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID,
                brainLeaseID: session.brainLeaseID,
                routeEpoch: session.routeEpoch,
                generation: session.generation + 1
            )
        ]
    }

    private static func eventIdentity(
        _ target: R81Target
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: target.session,
            turnID: target.turnID,
            responseID: target.responseID,
            contextRevision: target.contextRevision
        )
    }

    private static func audioDelta(
        sequence: UInt64
    ) -> RealtimeBrainAudioDelta {
        RealtimeBrainAudioDelta(
            sequence: sequence,
            timestampNanoseconds: sequence * 20_000_000,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .providerGenerated,
            bytes: Data(repeating: 1, count: 960)
        )
    }

    private static func inputFrame(
        session: RealtimeBrainSessionIdentity
    ) -> RealtimeBrainAudioFrame {
        RealtimeBrainAudioFrame(
            identity: session,
            sequence: 1,
            timestampNanoseconds: 1,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: Data(repeating: 1, count: 960)
        )
    }

    private static func confirmedDecision(
        _ result: Result<
            RealtimeInterruptionDecision,
            RealtimeResidentBrainError
        >,
        message: String
    ) -> RealtimeConfirmedInterruption {
        guard case .success(.confirmed(let decision)) = result else {
            expect(false, message)
            fatalError(message)
        }
        expect(decision.hostCommand == .clearPlayback, message)
        return decision
    }

    private static func expectRealtimeIdentity(
        _ result: Result<
            RealtimeBrainSessionIdentity,
            RealtimeResidentBrainError
        >,
        _ message: String
    ) -> RealtimeBrainSessionIdentity {
        guard case .success(let identity) = result else {
            expect(false, message)
            fatalError(message)
        }
        expect(true, message)
        return identity
    }

    private static func expectDecision(
        _ result: Result<
            RealtimeInterruptionDecision,
            RealtimeResidentBrainError
        >,
        equals expected: RealtimeInterruptionDecision,
        _ message: String
    ) {
        switch result {
        case .success(let decision):
            expect(decision == expected, message)
        case .failure:
            expect(false, message)
        }
    }

    private static func expectFailure<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        equals expected: RealtimeResidentBrainError,
        _ message: String
    ) {
        switch result {
        case .failure(let error): expect(error == expected, message)
        case .success: expect(false, message)
        }
    }

    private static func expectRealtimeSuccess<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        _ message: String
    ) {
        switch result {
        case .success: expect(true, message)
        case .failure: expect(false, message)
        }
    }

    private static func waitUntil(
        _ label: String,
        condition: @escaping () async -> Bool
    ) async {
        for _ in 0 ..< 400 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        fatalError("timed out: \(label)")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        checks += 1
        if !condition() { fatalError("FAILED: \(message)") }
    }

}
