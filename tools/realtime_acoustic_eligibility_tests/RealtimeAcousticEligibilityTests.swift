import Foundation

#if DEBUG
private struct R822CredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? { nil }
}

private final class R822AECBackend:
    MacSpeechAECBackend,
    @unchecked Sendable {
    private let lock = NSLock()
    private var captureOutput: [Float]?

    func configure() throws {}
    func processRender(_ samples: [Float]) throws {}

    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult {
        let processed = lock.withLock { captureOutput ?? samples }
        var linear: [Float] = []
        linear.reserveCapacity(processed.count / 3)
        for index in stride(from: 0, to: processed.count, by: 3) {
            linear.append(
                (processed[index] + processed[index + 1]
                    + processed[index + 2]) / 3
            )
        }
        return MacSpeechAECCaptureResult(
            processedSamples: processed,
            linearOutputSamples: linear
        )
    }

    func setDelay(milliseconds: Int) throws {}
    func reset() throws {}

    func stats() throws -> MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(
            enabled: true,
            active: true,
            estimatedDelayMilliseconds: 80,
            erlDecibels: 12,
            erleDecibels: 18
        )
    }

    func setCaptureOutput(_ samples: [Float]) {
        lock.withLock { captureOutput = samples }
    }
}

private actor R822RealtimeProvider: RealtimeResidentBrainProvider {
    private var events: [RealtimeResidentBrainEvent] = []
    private var receiveContinuation:
        CheckedContinuation<RealtimeResidentBrainEvent, Error>?
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var createCommands: [RealtimeBrainCreateResponseCommand] = []
    private var cancelCommands: [RealtimeBrainCancelGenerationCommand] = []
    private var interruptCommands: [RealtimeBrainInterruptCommand] = []
    private var closeCommands: [RealtimeBrainCloseSessionCommand] = []

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        openCommands.append(command)
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {
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

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {}
    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {}

    func createResponse(
        _ command: RealtimeBrainCreateResponseCommand
    ) async throws {
        createCommands.append(command)
    }

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {
        cancelCommands.append(command)
    }

    func interrupt(
        _ command: RealtimeBrainInterruptCommand
    ) async throws {
        interruptCommands.append(command)
    }

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
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

    func createCount() -> Int { createCommands.count }
    func interruptCount() -> Int { interruptCommands.count }
    func cancelCount() -> Int { cancelCommands.count }

    private func deliver(_ event: RealtimeResidentBrainEvent) {
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: event)
        } else {
            events.append(event)
        }
    }
}

private final class R822AudioSource:
    MacSpeechAudioFrameSourcing,
    @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64?
    private var frames: [MacSpeechAudioFrame] = []
    private var snapshot: MacSpeechResidentAcousticSnapshot?
    private var frameSequence: UInt64 = 0

    func activeCaptureGeneration() async -> UInt64? {
        lock.withLock { generation }
    }

    func isCaptureGenerationActive(_ value: UInt64) async -> Bool {
        lock.withLock { generation == value }
    }

    func drainFrames(maxCount: Int) async -> [MacSpeechAudioFrame] {
        lock.withLock {
            guard maxCount > 0, !frames.isEmpty else { return [] }
            let count = min(maxCount, frames.count)
            let result = Array(frames.prefix(count))
            frames.removeFirst(count)
            return result
        }
    }

    func residentAcousticSnapshot() async
        -> MacSpeechResidentAcousticSnapshot? {
        lock.withLock { snapshot }
    }

    func activate(generation: UInt64) {
        lock.withLock { self.generation = generation }
    }

    func setSnapshot(_ value: MacSpeechResidentAcousticSnapshot?) {
        lock.withLock { snapshot = value }
    }

    func appendFrame(generation: UInt64) {
        lock.withLock {
            guard self.generation == generation else { return }
            frameSequence &+= 1
            frames.append(MacSpeechAudioFrame(
                captureGeneration: generation,
                sequenceNumber: frameSequence,
                monotonicTimestampNanoseconds:
                    DispatchTime.now().uptimeNanoseconds,
                pcm16Bytes: Data(repeating: 0, count: 960),
                activity: 0
            ))
        }
    }
}

private actor R822SendBarrier {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false
    private var returned = false

    func hold() async {
        entered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func hasEntered() -> Bool { entered }

    func hasReturned() -> Bool { returned }

    func markReturned() {
        returned = true
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

private actor R822CarrierRecorder {
    private var values: [MacSpeechRealtimeBrainAcousticObservation] = []

    func record(_ value: MacSpeechRealtimeBrainAcousticObservation) {
        values.append(value)
    }

    func snapshot() -> [MacSpeechRealtimeBrainAcousticObservation] { values }
}

private struct R822Target {
    let session: RealtimeBrainSessionIdentity
    let turnID: RealtimeBrainTurnID
    let responseID: RealtimeBrainResponseID
    let contextRevision: UInt64
}

private struct R822RuntimeStack {
    let runtime: RuntimeCore
    let provider: R822RealtimeProvider
    let target: R822Target
}

@MainActor
@main
private struct RealtimeAcousticEligibilityTests {
    private static var cases = 0
    private static var checks = 0
    private static var stressObservationCount = 0
    private static var stressEligibleCount = 0
    private static var stressConfirmedCount = 0
    private static var stressProviderInterruptCount = 0
    private static var stressProviderCancelCount = 0
    private static var stressRuntimeClearDecisionCount = 0
    private static var stressGenerationChangeCount = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        testClassificationAndEpochGate()
        testProductionSourceGateStability()
        try await testResidentOnlyStress(fixture: fixture)
        try await testNearEndWithoutSemantic(fixture: fixture)
        try await testNearEndWithSemantic(fixture: fixture)
        testPlaybackTailAndRecovery()
        try await testFreshnessAndIdentity(fixture: fixture)
        await testSourceGateEpochSendRaces()
        await testSlowSendRolloverAndStop()

        print("realtime_acoustic_eligibility_cases=\(cases)")
        print("realtime_acoustic_eligibility_checks=\(checks)")
        print("r822_resident_stress_observations=\(stressObservationCount)")
        print("r822_resident_stress_eligible_acoustic_evidence=\(stressEligibleCount)")
        print("r822_resident_stress_confirmed_interruptions=\(stressConfirmedCount)")
        print("r822_resident_stress_provider_interrupts=\(stressProviderInterruptCount)")
        print("r822_resident_stress_provider_cancels=\(stressProviderCancelCount)")
        print("r822_resident_stress_runtime_clear_playback_decisions=\(stressRuntimeClearDecisionCount)")
        print("r822_resident_stress_generation_changes=\(stressGenerationChangeCount)")
    }

    private static func testClassificationAndEpochGate() {
        cases += 1
        let session = sessionIdentity(seed: "classification", generation: 1)
        let receivedAt = monotonicNow()
        let timestamp = receivedAt - 100_000_000
        let suppressedFixtures: [
            (RealtimeAcousticClassification,
             RealtimeAcousticEligibilitySuppressionReason)
        ] = [
            (.silenceOrNoise, .silenceOrNoise),
            (.farEndDominant, .farEndDominant),
            (.residualEchoLikely, .residualEchoLikely),
            (.indeterminate, .indeterminate)
        ]
        for (classification, reason) in suppressedFixtures {
            var gate = RealtimeAcousticInterruptionEligibilityGate(
                session: session,
                captureGeneration: 1
            )
            let value = observation(
                session: session,
                captureGeneration: 1,
                sequence: 1,
                timestamp: timestamp,
                classification: classification
            )
            expect(
                gate.evaluate(value, receivedAtNanoseconds: receivedAt)
                    == .suppressed(reason),
                "\(classification.rawValue) is not interruption eligible"
            )
        }

        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: session,
            captureGeneration: 1
        )
        let singleFrame = observation(
            session: session,
            captureGeneration: 1,
            sequence: 1,
            timestamp: timestamp,
            classification: .nearEndCandidate,
            sourceGateOpen: false
        )
        expect(
            gate.evaluate(singleFrame, receivedAtNanoseconds: receivedAt)
                == .suppressed(.unstableNearEnd),
            "one near-end frame cannot open eligibility before source stability"
        )
        let stableNearEnd = observation(
            session: session,
            captureGeneration: 1,
            sequence: 2,
            timestamp: timestamp + 10_000_000,
            classification: .nearEndCandidate
        )
        expect(
            gate.evaluate(stableNearEnd, receivedAtNanoseconds: receivedAt)
                == .eligible,
            "source-gate-confirmed near-end is eligible"
        )
        let echoDuringOpenEpoch = observation(
            session: session,
            captureGeneration: 1,
            sequence: 3,
            timestamp: timestamp + 20_000_000,
            classification: .indeterminate,
            sourceGateOpen: true
        )
        expect(
            gate.evaluate(
                echoDuringOpenEpoch,
                receivedAtNanoseconds: receivedAt
            ) == .suppressed(.indeterminate),
            "indeterminate stays fail-closed during source-gate hangover"
        )
        let repeatedNearEnd = observation(
            session: session,
            captureGeneration: 1,
            sequence: 4,
            timestamp: timestamp + 30_000_000,
            classification: .nearEndCandidate
        )
        expect(
            gate.evaluate(repeatedNearEnd, receivedAtNanoseconds: receivedAt)
                == .suppressed(.alreadyEligible),
            "one source-gate epoch issues at most one eligible candidate"
        )
        let closedGate = observation(
            session: session,
            captureGeneration: 1,
            sequence: 5,
            timestamp: timestamp + 40_000_000,
            classification: .farEndDominant,
            sourceGateOpen: false
        )
        _ = gate.evaluate(closedGate, receivedAtNanoseconds: receivedAt)
        let nextNearEndEpoch = observation(
            session: session,
            captureGeneration: 1,
            sequence: 6,
            timestamp: timestamp + 50_000_000,
            classification: .nearEndCandidate
        )
        expect(
            gate.evaluate(nextNearEndEpoch, receivedAtNanoseconds: receivedAt)
                == .eligible,
            "a closed source gate permits a later stable near-end epoch"
        )
    }

    private static func testProductionSourceGateStability() {
        cases += 1
        let backend = R822AECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        expect(host.configure() == .webRTCAEC3,
               "production AEC Host configures for gate stability")
        host.playbackStarted()
        let render = signal(seed: 11, amplitude: 0.3)
        let nearEnd = signal(seed: 12, amplitude: 0.25)
        backend.setCaptureOutput(nearEnd)
        let session = sessionIdentity(seed: "source-gate", generation: 1)
        let receivedAt = monotonicNow()
        let baseTimestamp = receivedAt - 200_000_000
        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: session,
            captureGeneration: 1
        )
        for index in 0 ..< 3 {
            let renderTimestamp = baseTimestamp
                + UInt64(index * 10_000_000)
            let captureTimestamp = renderTimestamp + 80_000_000
            host.processRender(
                render,
                hostTimeNanoseconds: renderTimestamp
            )
            _ = host.processCapture(
                render,
                hostTimeNanoseconds: captureTimestamp
            )
            let snapshot = host.acousticObservationSnapshot()
            let value = observation(
                session: session,
                captureGeneration: 1,
                sequence: UInt64(index + 1),
                timestamp: captureTimestamp,
                acousticSnapshot: snapshot
            )
            let disposition = gate.evaluate(
                value,
                receivedAtNanoseconds: receivedAt
            )
            if index < 2 {
                expect(
                    !snapshot.sourceGateOpen && disposition != .eligible,
                    "production source gate rejects near-end before 30 ms stability"
                )
            } else {
                expect(snapshot.sourceGateOpen && disposition == .eligible,
                       "production 3x10 ms source gate unlocks one candidate")
            }
        }
    }

    private static func testResidentOnlyStress(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeRuntimeStack(
            fixture: fixture,
            seed: "resident-stress"
        )
        try await submitSemanticProposal(stack, sequence: 4)
        let originalLease = stack.runtime.activeBrainLeaseForTesting()
        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: stack.target.session,
            captureGeneration: 1
        )
        let receivedAt = monotonicNow()
        let baseTimestamp = receivedAt - 400_000_000
        var eligibleCount = 0
        var confirmedCount = 0
        var clearCommandCount = 0

        for index in 0 ..< 320 {
            let classification: RealtimeAcousticClassification
            switch index % 5 {
            case 0: classification = .farEndDominant
            case 1: classification = .residualEchoLikely
            case 2: classification = .silenceOrNoise
            case 3: classification = .indeterminate
            default: classification = .farEndDominant
            }
            let timestamp = baseTimestamp + UInt64(index) * 1_000_000
            let value = observation(
                session: stack.target.session,
                captureGeneration: 1,
                sequence: UInt64(index + 1),
                timestamp: timestamp,
                classification: classification,
                routeStable: index % 5 != 3,
                measuredDelayMilliseconds: index % 5 == 4 ? 120 : 80,
                alignedDelayMilliseconds: 80
            )
            stressObservationCount += 1
            let disposition = gate.evaluate(
                value,
                receivedAtNanoseconds: receivedAt
            )
            if disposition == .eligible {
                eligibleCount += 1
                let result = await stack.runtime
                    .submitRealtimeResidentBrainEligibleAcousticEvidence(
                        observation: value,
                        evidence: acousticEvidence(
                            observation: value,
                            target: stack.target
                        )
                    )
                if case .success(.confirmed(let decision)) = result {
                    confirmedCount += 1
                    if decision.hostCommand == .clearPlayback {
                        clearCommandCount += 1
                    }
                }
            }
        }

        stressEligibleCount = eligibleCount
        stressConfirmedCount = confirmedCount
        stressProviderInterruptCount = await stack.provider.interruptCount()
        stressProviderCancelCount = await stack.provider.cancelCount()
        stressRuntimeClearDecisionCount = clearCommandCount
        stressGenerationChangeCount = stack.runtime
            .activeBrainLeaseForTesting()?.generation
            == originalLease?.generation ? 0 : 1

        expect(stressObservationCount == 320,
               "resident-only stress evaluates 320 observations")
        expect(stressEligibleCount == 0,
               "resident-only stress produces zero eligible evidence")
        expect(stressConfirmedCount == 0,
               "resident-only stress produces zero confirmed interruption")
        expect(stressProviderInterruptCount == 0,
               "resident-only stress never interrupts Provider")
        expect(stressProviderCancelCount == 0,
               "resident-only stress never cancels Provider")
        expect(stressRuntimeClearDecisionCount == 0,
               "resident-only stress produces no Runtime clear-Playback decision")
        expect(stressGenerationChangeCount == 0,
               "resident-only stress preserves Runtime generation")
        expect(stack.runtime.activeBrainLeaseForTesting() == originalLease,
               "resident-only stress preserves the exact Brain lease")
        try await close(stack.runtime, identity: stack.target.session)
    }

    private static func testNearEndWithoutSemantic(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeRuntimeStack(
            fixture: fixture,
            seed: "near-without-semantic"
        )
        let originalLease = stack.runtime.activeBrainLeaseForTesting()
        let now = monotonicNow()
        let value = observation(
            session: stack.target.session,
            captureGeneration: 1,
            sequence: 1,
            timestamp: now - 10_000_000,
            classification: .nearEndCandidate
        )
        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: stack.target.session,
            captureGeneration: 1
        )
        expect(
            gate.evaluate(value, receivedAtNanoseconds: now) == .eligible,
            "stable near-end remains eligible while resident playback is active"
        )
        let decision = await stack.runtime
            .submitRealtimeResidentBrainEligibleAcousticEvidence(
                observation: value,
                evidence: acousticEvidence(
                    observation: value,
                    target: stack.target
                )
            )
        expectDecision(decision, equals: .observed,
                       "near-end evidence alone stays observer-only")
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(value)
                == .ignored(.duplicateObservation),
            "eligible atomic ingest owns the exact observation ledger entry"
        )
        expect(await stack.provider.interruptCount() == 0,
               "near-end without semantic does not interrupt Provider")
        expect(await stack.provider.cancelCount() == 0,
               "near-end without semantic does not cancel Provider")
        expect(stack.runtime.activeBrainLeaseForTesting() == originalLease,
               "near-end without semantic preserves generation and lease")
        try await close(stack.runtime, identity: stack.target.session)
    }

    private static func testNearEndWithSemantic(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeRuntimeStack(
            fixture: fixture,
            seed: "near-with-semantic"
        )
        try await submitSemanticProposal(stack, sequence: 4)
        let originalLease = stack.runtime.activeBrainLeaseForTesting()
        let now = monotonicNow()
        let value = observation(
            session: stack.target.session,
            captureGeneration: 1,
            sequence: 1,
            timestamp: now - 10_000_000,
            classification: .nearEndCandidate
        )
        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: stack.target.session,
            captureGeneration: 1
        )
        expect(gate.evaluate(value, receivedAtNanoseconds: now) == .eligible,
               "semantic fusion receives only eligible near-end evidence")
        let result = await stack.runtime
            .submitRealtimeResidentBrainEligibleAcousticEvidence(
                observation: value,
                evidence: acousticEvidence(
                    observation: value,
                    target: stack.target
                )
            )
        guard case .success(.confirmed(let decision)) = result else {
            fatalError("eligible near-end plus semantic did not confirm")
        }
        expect(decision.hostCommand == .clearPlayback,
               "only Runtime confirmation issues the Playback clear command")
        guard case .success(let nextIdentity) = await stack.runtime
                .completeRealtimeResidentBrainInterruption(decision) else {
            fatalError("confirmed interruption did not settle")
        }
        expect(nextIdentity.generation == stack.target.session.generation + 1,
               "Runtime alone advances exactly one generation")
        expect(await stack.provider.interruptCount() == 1,
               "Runtime confirmation issues exactly one Provider interrupt")
        expect(await stack.provider.cancelCount() == 0,
               "eligible interruption does not use Provider cancellation")
        let nextLease = stack.runtime.activeBrainLeaseForTesting()
        expect(nextLease?.brainLeaseID == originalLease?.brainLeaseID,
               "confirmed interruption preserves the Brain lease")
        expect(
            nextLease?.generation
                == .realtimeResidentBrain(nextIdentity.generation),
               "confirmed interruption binds the exact next generation")
        let oldGenerationObservation = observation(
            session: stack.target.session,
            captureGeneration: 1,
            sequence: 2,
            timestamp: monotonicNow() - 5_000_000,
            classification: .nearEndCandidate
        )
        expectDecision(
            await stack.runtime
                .submitRealtimeResidentBrainEligibleAcousticEvidence(
                    observation: oldGenerationObservation,
                    evidence: acousticEvidence(
                        observation: oldGenerationObservation,
                        target: stack.target
                    )
                ),
            equals: .ignored(.staleIdentity),
            "Runtime rejects fresh eligible evidence from the invalidated generation"
        )
        let replayInterruptCount = await stack.provider.interruptCount()
        let replayCancelCount = await stack.provider.cancelCount()
        expect(
            replayInterruptCount == 1
                && replayCancelCount == 0
                && stack.runtime.activeBrainLeaseForTesting() == nextLease,
            "old-generation replay cannot mutate Provider or the rebound lease"
        )
        try await close(stack.runtime, identity: nextIdentity)
    }

    private static func testPlaybackTailAndRecovery() {
        cases += 1
        let session = sessionIdentity(seed: "tail", generation: 1)
        let receivedAt = monotonicNow()
        let baseTimestamp = receivedAt - 450_000_000
        let lastAudible = baseTimestamp - 80_000_000
        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: session,
            captureGeneration: 7
        )
        let activeFarEnd = observation(
            session: session,
            captureGeneration: 7,
            sequence: 1,
            timestamp: baseTimestamp,
            classification: .farEndDominant,
            playbackSequence: 1,
            lastAudibleTimestamp: lastAudible
        )
        expect(
            gate.evaluate(activeFarEnd, receivedAtNanoseconds: receivedAt)
                == .suppressed(.farEndDominant),
            "active resident far-end is suppressed"
        )
        let recentTail = observation(
            session: session,
            captureGeneration: 7,
            sequence: 2,
            timestamp: lastAudible + 200_000_000,
            classification: .nearEndCandidate,
            playbackSequence: 1,
            playbackActive: false,
            lastAudibleTimestamp: lastAudible,
            sourceGateOpen: false
        )
        expect(
            gate.evaluate(recentTail, receivedAtNanoseconds: receivedAt)
                == .suppressed(.playbackTail),
            "recent last-audible render keeps residual playback tail closed"
        )
        let missingTailClock = observation(
            session: session,
            captureGeneration: 7,
            sequence: 3,
            timestamp: lastAudible + 300_000_000,
            classification: .nearEndCandidate,
            playbackSequence: 1,
            playbackActive: false,
            lastAudibleTimestamp: lastAudible,
            sourceGateOpen: false,
            captureTimestampAvailable: false
        )
        expect(
            gate.evaluate(
                missingTailClock,
                receivedAtNanoseconds: receivedAt
            ) == .suppressed(.indeterminate),
            "missing capture clock fails closed during playback tail"
        )
        let expiredTailTimestamp = lastAudible
            + RealtimeAcousticInterruptionEligibilityGate
                .residualTailWindowNanoseconds
        let expiredTail = observation(
            session: session,
            captureGeneration: 7,
            sequence: 4,
            timestamp: expiredTailTimestamp,
            classification: .nearEndCandidate,
            playbackSequence: 1,
            playbackActive: false,
            lastAudibleTimestamp: lastAudible,
            sourceGateOpen: false
        )
        expect(
            gate.evaluate(expiredTail, receivedAtNanoseconds: receivedAt)
                == .suppressed(.residentPlaybackInactive),
            "tail expires exactly at the bounded 500 ms window"
        )
        let nextPlayback = observation(
            session: session,
            captureGeneration: 7,
            sequence: 5,
            timestamp: receivedAt - 10_000_000,
            classification: .nearEndCandidate,
            playbackSequence: 2,
            playbackActive: true,
            lastAudibleTimestamp: receivedAt - 90_000_000
        )
        expect(
            gate.evaluate(nextPlayback, receivedAtNanoseconds: receivedAt)
                == .eligible,
            "a new playback epoch restores stable near-end eligibility"
        )
    }

    private static func testFreshnessAndIdentity(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeRuntimeStack(
            fixture: fixture,
            seed: "freshness"
        )
        try await submitSemanticProposal(stack, sequence: 4)
        let now = monotonicNow()
        let stale = observation(
            session: stack.target.session,
            captureGeneration: 1,
            sequence: 1,
            timestamp: now - 600_000_000,
            classification: .nearEndCandidate
        )
        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: stack.target.session,
            captureGeneration: 1
        )
        expect(
            gate.evaluate(stale, receivedAtNanoseconds: now)
                == .suppressed(.invalidObservation),
            "600 ms old near-end cannot obtain gate eligibility"
        )
        expectDecision(
            await stack.runtime
                .submitRealtimeResidentBrainEligibleAcousticEvidence(
                    observation: stale,
                    evidence: acousticEvidence(
                        observation: stale,
                        target: stack.target
                    )
                ),
            equals: .ignored(.invalidEvidence),
            "Runtime atomic ingest also rejects 600 ms old evidence"
        )
        expect(await stack.provider.interruptCount() == 0,
               "stale evidence cannot interrupt Provider")

        for wrongSession in wrongSessions(for: stack.target.session) {
            var wrongGate = RealtimeAcousticInterruptionEligibilityGate(
                session: stack.target.session,
                captureGeneration: 1
            )
            let wrong = observation(
                session: wrongSession,
                captureGeneration: 1,
                sequence: 1,
                timestamp: now - 10_000_000,
                classification: .nearEndCandidate
            )
            expect(
                wrongGate.evaluate(wrong, receivedAtNanoseconds: now)
                    == .suppressed(.staleIdentity),
                "old session, lease, epoch, or generation gate state is stale"
            )
        }
        var captureGate = RealtimeAcousticInterruptionEligibilityGate(
            session: stack.target.session,
            captureGeneration: 1
        )
        let wrongCapture = observation(
            session: stack.target.session,
            captureGeneration: 2,
            sequence: 1,
            timestamp: now - 10_000_000,
            classification: .nearEndCandidate
        )
        expect(
            captureGate.evaluate(wrongCapture, receivedAtNanoseconds: now)
                == .suppressed(.staleIdentity),
            "old capture generation cannot reuse current gate state"
        )

        let observed = observation(
            session: stack.target.session,
            captureGeneration: 1,
            sequence: 2,
            timestamp: now - 5_000_000,
            classification: .farEndDominant
        )
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(observed)
                == .observed,
            "Runtime ledger binds the current capture generation"
        )
        let replayedCapture = observation(
            session: stack.target.session,
            captureGeneration: 2,
            sequence: 3,
            timestamp: now - 4_000_000,
            classification: .farEndDominant
        )
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(
                replayedCapture
            ) == .ignored(.staleIdentity),
            "Runtime rejects capture-generation replay within one session"
        )
        try await close(stack.runtime, identity: stack.target.session)

        let reboundSession = sessionIdentity(seed: "rebound", generation: 2)
        var reboundGate = RealtimeAcousticInterruptionEligibilityGate(
            session: reboundSession,
            captureGeneration: 9
        )
        let rebound = observation(
            session: reboundSession,
            captureGeneration: 9,
            sequence: 1,
            timestamp: now - 1_000_000,
            classification: .nearEndCandidate
        )
        expect(
            reboundGate.evaluate(rebound, receivedAtNanoseconds: now)
                == .eligible,
            "Stop or route rebind creates fresh gate state without stale latch"
        )
    }

    private static func testSourceGateEpochSendRaces() async {
        cases += 1
        await runSourceGateEpochRace(
            label: "Case A close",
            currentSnapshot: residentSnapshot(
                captureGeneration: 31,
                frameIndex: 2,
                playbackSequence: 1,
                sourceGateEpoch: 1,
                sourceGateOpen: false
            ),
            expectedEvidenceCount: 0
        )
        await runSourceGateEpochRace(
            label: "Case B reopen",
            currentSnapshot: residentSnapshot(
                captureGeneration: 31,
                frameIndex: 2,
                playbackSequence: 1,
                sourceGateEpoch: 2,
                sourceGateOpen: true
            ),
            expectedEvidenceCount: 0
        )
        await runSourceGateEpochRace(
            label: "Case C same epoch",
            currentSnapshot: residentSnapshot(
                captureGeneration: 31,
                frameIndex: 2,
                playbackSequence: 1,
                sourceGateEpoch: 1,
                sourceGateOpen: true
            ),
            expectedEvidenceCount: 1
        )
        await runRejectedSendEpochCase(error: .invalidIdentity)
        await runRejectedSendEpochCase(error: .cancelled)
    }

    private static func runSourceGateEpochRace(
        label: String,
        currentSnapshot: MacSpeechResidentAcousticSnapshot,
        expectedEvidenceCount: Int
    ) async {
        let generation: UInt64 = 31
        let session = sessionIdentity(seed: label, generation: 1)
        let source = R822AudioSource()
        let barrier = R822SendBarrier()
        let recorder = R822CarrierRecorder()
        source.activate(generation: generation)
        source.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            frameIndex: 1,
            playbackSequence: 1,
            sourceGateEpoch: 1,
            sourceGateOpen: true
        ))
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { _ in
                await barrier.hold()
                await barrier.markReturned()
                return .success(())
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { value in
                await recorder.record(value)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: generation
        ))
        source.appendFrame(generation: generation)
        await waitUntil("\(label) send entered") { await barrier.hasEntered() }
        source.setSnapshot(currentSnapshot)
        await barrier.release()
        await waitUntil("\(label) send returned") { await barrier.hasReturned() }
        try? await Task.sleep(for: .milliseconds(20))
        expect(
            await recorder.snapshot().count == expectedEvidenceCount,
            "\(label) fences the exact source-gate epoch"
        )
        _ = await bridge.stop(expectedSession: session)
    }

    private static func runRejectedSendEpochCase(
        error: RealtimeResidentBrainError
    ) async {
        let generation: UInt64 = error == .invalidIdentity ? 41 : 42
        let session = sessionIdentity(
            seed: "rejected-\(generation)",
            generation: 1
        )
        let source = R822AudioSource()
        let recorder = R822CarrierRecorder()
        source.activate(generation: generation)
        source.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            frameIndex: 1,
            playbackSequence: 1,
            sourceGateEpoch: 1,
            sourceGateOpen: true
        ))
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { _ in .failure(error) },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { value in
                await recorder.record(value)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: generation
        ))
        source.appendFrame(generation: generation)
        await waitUntil("rejected send settled") {
            await bridge.currentSnapshot().sendOperationCount == 1
        }
        source.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            frameIndex: 2,
            playbackSequence: 1,
            sourceGateEpoch: 2,
            sourceGateOpen: true
        ))
        try? await Task.sleep(for: .milliseconds(20))
        expect(await recorder.snapshot().isEmpty,
               "\(error) cannot rearm old epoch eligibility")
        expect(await bridge.currentSnapshot().acousticEvidenceCount == 0,
               "\(error) cannot account old epoch evidence")
        _ = await bridge.stop(expectedSession: session)
    }

    private static func testSlowSendRolloverAndStop() async {
        cases += 1
        let session = sessionIdentity(seed: "slow-send", generation: 1)
        let generation: UInt64 = 17
        let source = R822AudioSource()
        let barrier = R822SendBarrier()
        let recorder = R822CarrierRecorder()
        source.activate(generation: generation)
        let firstSnapshot = residentSnapshot(
            captureGeneration: generation,
            frameIndex: 1,
            playbackSequence: 1,
            nearEnd: true
        )
        source.setSnapshot(firstSnapshot)
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { _ in
                if !(await barrier.hasReturned()) {
                    await barrier.hold()
                    await barrier.markReturned()
                }
                return .success(())
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { value in
                await recorder.record(value)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: generation
        ))
        source.appendFrame(generation: generation)
        await waitUntil("slow send entered") { await barrier.hasEntered() }
        let nextSnapshot = residentSnapshot(
            captureGeneration: generation,
            frameIndex: 2,
            playbackSequence: 2,
            nearEnd: true
        )
        source.setSnapshot(nextSnapshot)
        await barrier.release()
        await waitUntil("slow send returned") {
            await barrier.hasReturned()
        }
        try? await Task.sleep(for: .milliseconds(20))
        expect(await recorder.snapshot().isEmpty,
               "old playback eligibility is discarded after send")
        let suspended = await bridge.suspendForGenerationTransition(
            session: session
        )
        expect(suspended.state == .stopped,
               "generation transition suspends the old input binding")
        let nextSession = nextGenerationSession(after: session)
        let resumed = await bridge.resumeAfterGenerationTransition(
            session: nextSession
        )
        expect(
            resumed.state == .running && resumed.hasActivePump,
            "generation transition resumes the Bridge on the next identity"
        )
        try? await Task.sleep(for: .milliseconds(15))
        source.appendFrame(generation: generation)
        await waitUntil("rebound carrier delivered") {
            await recorder.snapshot().count == 1
        }
        let reboundCarriers = await recorder.snapshot()
        expect(
            reboundCarriers.last?.session == nextSession
                && reboundCarriers.last?.captureGeneration == generation
                && reboundCarriers.last?.sequence == 1,
            "rebound eligibility starts fresh on the exact next identity"
        )
        _ = await bridge.stop(expectedSession: nextSession)

        let stopSource = R822AudioSource()
        let stopBarrier = R822SendBarrier()
        let stopRecorder = R822CarrierRecorder()
        stopSource.activate(generation: generation)
        stopSource.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            frameIndex: 1,
            playbackSequence: 1,
            nearEnd: true
        ))
        let stopBridge = MacSpeechRealtimeBrainInputBridge(
            source: stopSource,
            sendFrame: { _ in
                if !(await stopBarrier.hasReturned()) {
                    await stopBarrier.hold()
                    await stopBarrier.markReturned()
                }
                return .success(())
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { value in
                await stopRecorder.record(value)
            }
        )
        _ = await stopBridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: generation
        ))
        stopSource.appendFrame(generation: generation)
        await waitUntil("Stop fixture send entered") {
            await stopBarrier.hasEntered()
        }
        _ = await stopBridge.stop(expectedSession: session)
        await stopBarrier.release()
        await waitUntil("late send settled") {
            await stopBarrier.hasReturned()
        }
        _ = await stopBridge.currentSnapshot()
        expect(await stopRecorder.snapshot().isEmpty,
               "Stop clears pending eligibility before late send completion")
        expect(await stopBridge.currentSnapshot().acousticEvidenceCount == 0,
               "Stop prevents late acoustic evidence accounting")
    }

    private static func makeRuntimeStack(
        fixture: Data,
        seed: String
    ) async throws -> R822RuntimeStack {
        let provider = R822RealtimeProvider()
        let router = ProviderRouter(
            credentialReader: R822CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "\(seed) fixture resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("\(seed) Realtime session did not start")
        }
        guard case .accepted(let ready) = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session),
              ready.kind == .sessionReady else {
            fatalError("\(seed) Realtime session did not become ready")
        }
        let target = R822Target(
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
            kind: .userTranscriptFinal("R8.2.2 \(seed)")
        )
        await provider.enqueue(userFinal)
        guard case .accepted = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session) else {
            fatalError("\(seed) user turn did not activate")
        }
        expect(await provider.createCount() == 1,
               "\(seed) Runtime authorizes one response")
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(target),
            sequence: 3,
            kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                sequence: 1,
                timestampNanoseconds: monotonicNow(),
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 24_000,
                    channelCount: 1
                ),
                provenance: .providerGenerated,
                bytes: Data(repeating: 0, count: 960)
            ))
        ))
        guard case .accepted = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session) else {
            fatalError("\(seed) resident response did not activate")
        }
        return R822RuntimeStack(
            runtime: runtime,
            provider: provider,
            target: target
        )
    }

    private static func submitSemanticProposal(
        _ stack: R822RuntimeStack,
        sequence: UInt64
    ) async throws {
        let identity = eventIdentity(stack.target)
        let proposal = RealtimeResidentBrainEvent(
            identity: identity,
            sequence: sequence,
            kind: .interruptionProposed(RealtimeBrainInterruptionProposal(
                identity: identity,
                reason: "user_speech_started_during_resident_response"
            ))
        )
        await stack.provider.enqueue(proposal)
        guard case .accepted = try await stack.runtime
                .receiveRealtimeResidentBrainEvent(
                    session: stack.target.session
                ) else {
            fatalError("semantic proposal was not accepted")
        }
        expectDecision(
            await stack.runtime
                .claimRealtimeResidentBrainInterruptionDecision(for: proposal),
            equals: .observed,
            "semantic proposal alone remains observed"
        )
    }

    private static func acousticEvidence(
        observation: RealtimeAcousticObservation,
        target: R822Target
    ) -> RealtimeInterruptionEvidence {
        let metrics = observation.metrics
        return RealtimeInterruptionEvidence(
            identity: RealtimeInterruptionEvidenceIdentity(
                session: target.session,
                turnID: target.turnID,
                responseID: target.responseID,
                contextRevision: target.contextRevision,
                sequence: observation.identity.sequence,
                timestampNanoseconds:
                    observation.identity.timestampNanoseconds
            ),
            source: .acousticHost(RealtimeInterruptionAcousticFacts(
                sourceGateEpoch: metrics.sourceGateEpoch,
                nearEndDetected:
                    observation.classification == .nearEndCandidate,
                farEndActive: metrics.residentPlaybackActive,
                sourceGateOpen: metrics.sourceGateOpen,
                renderReferenceConfidence:
                    metrics.sourceAlignmentLocked ? 1 : 0,
                routeStable: metrics.routeStable,
                inputDeviceAvailable: metrics.inputDeviceAvailable,
                outputDeviceAvailable: metrics.outputDeviceAvailable
            ))
        )
    }

    private static func observation(
        session: RealtimeBrainSessionIdentity,
        captureGeneration: UInt64,
        sequence: UInt64,
        timestamp: UInt64,
        classification fixture: RealtimeAcousticClassification,
        playbackSequence: UInt64 = 1,
        playbackActive: Bool = true,
        lastAudibleTimestamp: UInt64? = nil,
        sourceGateOpen: Bool? = nil,
        routeStable: Bool = true,
        measuredDelayMilliseconds: Int = 80,
        alignedDelayMilliseconds: Int = 80,
        captureTimestampAvailable: Bool = true
    ) -> RealtimeAcousticObservation {
        let renderTimestamp = timestamp
            - UInt64(max(0, measuredDelayMilliseconds)) * 1_000_000
        let source: RealtimeAcousticSourceAssessment
        let renderReferenceAvailable: Bool
        let renderRMS: Double?
        let rawRMS: Double
        let outputRMS: Double
        let rawCorrelation: Double
        let residualCorrelation: Double
        let erle: Double
        switch fixture {
        case .silenceOrNoise:
            source = .uncertain
            renderReferenceAvailable = true
            renderRMS = 0
            rawRMS = 0.002
            outputRMS = 0.001
            rawCorrelation = 0
            residualCorrelation = 0
            erle = 0
        case .farEndDominant:
            source = .echoOnly
            renderReferenceAvailable = true
            renderRMS = 0.2
            rawRMS = 0.16
            outputRMS = 0.003
            rawCorrelation = 0.82
            residualCorrelation = 0.1
            erle = 12
        case .residualEchoLikely:
            source = .echoOnly
            renderReferenceAvailable = true
            renderRMS = 0.2
            rawRMS = 0.16
            outputRMS = 0.035
            rawCorrelation = 0.82
            residualCorrelation = 0.8
            erle = 1
        case .nearEndCandidate:
            source = .nearEndSpeech
            renderReferenceAvailable = true
            renderRMS = 0.2
            rawRMS = 0.25
            outputRMS = 0.2
            rawCorrelation = 0.1
            residualCorrelation = 0.1
            erle = 0
        case .indeterminate:
            source = .uncertain
            renderReferenceAvailable = false
            renderRMS = nil
            rawRMS = 0.1
            outputRMS = 0.02
            rawCorrelation = 0
            residualCorrelation = 0
            erle = 0
        }
        let metrics = RealtimeAcousticMetrics(
            residentPlaybackSequence: playbackSequence,
            residentPlaybackActive: playbackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                lastAudibleTimestamp
                    ?? (playbackActive ? renderTimestamp : nil),
            renderReferenceAvailable: renderReferenceAvailable,
            renderReferenceRMS: renderRMS,
            rawCaptureRMS: rawRMS,
            aecOutputRMS: outputRMS,
            linearAECOutputRMS: outputRMS,
            renderCaptureCorrelation: rawCorrelation,
            residualRenderCorrelation: residualCorrelation,
            linearRenderCorrelation: residualCorrelation,
            captureTimestampNanoseconds:
                captureTimestampAvailable ? timestamp : nil,
            renderTimestampNanoseconds:
                renderReferenceAvailable ? renderTimestamp : nil,
            sourceAlignmentDelayMilliseconds:
                renderReferenceAvailable ? alignedDelayMilliseconds : nil,
            estimatedDelayMilliseconds: alignedDelayMilliseconds,
            erlDecibels: 12,
            erleDecibels: erle,
            renderCaptureSkewFrames: 0,
            driftState: .stable,
            sourceAssessment: source,
            sourceGateOpen: sourceGateOpen
                ?? (fixture == .nearEndCandidate),
            sourceGateEpoch: 1,
            aecActive: true,
            sourceAlignmentLocked: renderReferenceAvailable,
            routeStable: routeStable,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
        return makeObservation(
            session: session,
            captureGeneration: captureGeneration,
            sequence: sequence,
            timestamp: timestamp,
            metrics: metrics
        )
    }

    private static func observation(
        session: RealtimeBrainSessionIdentity,
        captureGeneration: UInt64,
        sequence: UInt64,
        timestamp: UInt64,
        acousticSnapshot snapshot: MacSpeechAcousticObservationSnapshot
    ) -> RealtimeAcousticObservation {
        let source: RealtimeAcousticSourceAssessment = switch snapshot
            .inputClassification {
        case .echoOnly: .echoOnly
        case .nearEndSpeech: .nearEndSpeech
        case .doubleTalk: .doubleTalk
        case .uncertain: .uncertain
        }
        let metrics = RealtimeAcousticMetrics(
            residentPlaybackSequence: snapshot.playbackSequence,
            residentPlaybackActive: snapshot.isPlaybackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                snapshot.lastAudibleRenderHostTimeNanoseconds,
            renderReferenceAvailable: snapshot.renderReferenceAvailable,
            renderReferenceRMS: snapshot.renderReferenceRMS,
            rawCaptureRMS: snapshot.rawCaptureRMS,
            aecOutputRMS: snapshot.processedCaptureRMS,
            linearAECOutputRMS: snapshot.linearAECOutputRMS,
            renderCaptureCorrelation: snapshot.renderCaptureCorrelation,
            residualRenderCorrelation: snapshot.residualRenderCorrelation,
            linearRenderCorrelation: snapshot.linearRenderCorrelation,
            captureTimestampNanoseconds:
                snapshot.captureHostTimeNanoseconds,
            renderTimestampNanoseconds: snapshot.renderHostTimeNanoseconds,
            sourceAlignmentDelayMilliseconds:
                snapshot.sourceAlignmentDelayMilliseconds,
            estimatedDelayMilliseconds: snapshot.estimatedDelayMilliseconds,
            erlDecibels: snapshot.erlDecibels,
            erleDecibels: snapshot.erleDecibels,
            renderCaptureSkewFrames: snapshot.renderCaptureSkewFrames,
            driftState: snapshot.driftTrend == "stable" ? .stable : .unknown,
            sourceAssessment: source,
            sourceGateOpen: snapshot.sourceGateOpen,
            sourceGateEpoch: snapshot.sourceGateEpoch,
            aecActive: snapshot.aecActive,
            sourceAlignmentLocked: snapshot.sourceAlignmentLocked,
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
        return makeObservation(
            session: session,
            captureGeneration: captureGeneration,
            sequence: sequence,
            timestamp: timestamp,
            metrics: metrics
        )
    }

    private static func makeObservation(
        session: RealtimeBrainSessionIdentity,
        captureGeneration: UInt64,
        sequence: UInt64,
        timestamp: UInt64,
        metrics: RealtimeAcousticMetrics
    ) -> RealtimeAcousticObservation {
        RealtimeAcousticObservation(
            identity: RealtimeAcousticObservationIdentity(
                session: session,
                captureGeneration: captureGeneration,
                sequence: sequence,
                timestampNanoseconds: timestamp
            ),
            metrics: metrics,
            classification: RealtimeAcousticClassifier.classify(
                metrics: metrics,
                observationTimestampNanoseconds: timestamp
            )
        )
    }

    private static func residentSnapshot(
        captureGeneration: UInt64,
        frameIndex: UInt64,
        playbackSequence: UInt64,
        nearEnd: Bool
    ) -> MacSpeechResidentAcousticSnapshot {
        residentSnapshot(
            captureGeneration: captureGeneration,
            frameIndex: frameIndex,
            playbackSequence: playbackSequence,
            sourceGateEpoch: nearEnd ? 1 : 0,
            sourceGateOpen: nearEnd
        )
    }

    private static func residentSnapshot(
        captureGeneration: UInt64,
        frameIndex: UInt64,
        playbackSequence: UInt64,
        sourceGateEpoch: UInt64,
        sourceGateOpen: Bool
    ) -> MacSpeechResidentAcousticSnapshot {
        let captureTimestamp = monotonicNow() - 5_000_000
        let renderTimestamp = captureTimestamp - 80_000_000
        return MacSpeechResidentAcousticSnapshot(
            captureGeneration: captureGeneration,
            captureFrameIndex: frameIndex,
            captureHostTimeNanoseconds: captureTimestamp,
            playbackSequence: playbackSequence,
            residentPlaybackActive: true,
            lastAudibleResidentRenderTimestampNanoseconds: renderTimestamp,
            renderReferenceAvailable: true,
            renderReferenceRMS: 0.2,
            renderHostTimeNanoseconds: renderTimestamp,
            rawCaptureRMS: 0.2,
            processedCaptureRMS: sourceGateOpen ? 0.2 : 0.002,
            linearAECOutputRMS: sourceGateOpen ? 0.2 : 0.002,
            renderCaptureCorrelation: sourceGateOpen ? 0.1 : 0.8,
            residualRenderCorrelation: 0.1,
            linearRenderCorrelation: 0.1,
            inputClassification: sourceGateOpen ? .nearEndSpeech : .echoOnly,
            sourceGateOpen: sourceGateOpen,
            sourceGateEpoch: sourceGateEpoch,
            aecEnabled: true,
            aecActive: true,
            sourceAlignmentLocked: true,
            sourceAlignmentDelayMilliseconds: 80,
            estimatedDelayMilliseconds: 80,
            erlDecibels: 12,
            erleDecibels: 10,
            renderCaptureSkewFrames: 0,
            driftTrend: "stable",
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
    }

    private static func eventIdentity(
        _ target: R822Target
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: target.session,
            turnID: target.turnID,
            responseID: target.responseID,
            contextRevision: target.contextRevision
        )
    }

    private static func sessionIdentity(
        seed: String,
        generation: UInt64
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: "r822-\(seed)",
            runtimeSessionID: "r822-session-\(seed)",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: generation
        )
    }

    private static func nextGenerationSession(
        after session: RealtimeBrainSessionIdentity
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: session.residentID,
            runtimeSessionID: session.runtimeSessionID,
            brainLeaseID: session.brainLeaseID,
            routeEpoch: session.routeEpoch,
            generation: session.generation + 1
        )
    }

    private static func wrongSessions(
        for session: RealtimeBrainSessionIdentity
    ) -> [RealtimeBrainSessionIdentity] {
        [
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID + "-old",
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

    private static func close(
        _ runtime: RuntimeCore,
        identity: RealtimeBrainSessionIdentity
    ) async throws {
        guard case .success = await runtime
                .closeRealtimeResidentBrainSession(identity: identity) else {
            fatalError("Realtime session did not close")
        }
    }

    private static func expectDecision(
        _ result: Result<
            RealtimeInterruptionDecision,
            RealtimeResidentBrainError
        >,
        equals expected: RealtimeInterruptionDecision,
        _ message: String
    ) {
        guard case .success(let value) = result else {
            expect(false, message)
            return
        }
        expect(value == expected, message)
    }

    private static func waitUntil(
        _ label: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        let deadline = monotonicNow() + timeoutNanoseconds
        while !(await condition()) {
            if monotonicNow() >= deadline {
                fatalError("timeout: \(label)")
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
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

    private static func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError("FAIL: \(message)") }
    }
}
#endif
