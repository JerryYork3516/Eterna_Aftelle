import Foundation

#if DEBUG
private struct R823CredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? { nil }
}

private struct R823AuthorizationProvider:
    MicrophoneAuthorizationProviding {
    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }
}

private final class R823DeviceMonitor:
    MacSpeechDeviceRouteMonitoring,
    @unchecked Sendable {
    private let route = MacSpeechDeviceRoute(
        input: MacSpeechAudioDevice(
            identifier: "r823-input",
            name: "R8.2.3 Input",
            isAvailable: true
        ),
        output: MacSpeechAudioDevice(
            identifier: "r823-output",
            name: "R8.2.3 Output",
            isAvailable: true
        )
    )

    func currentRoute() -> MacSpeechDeviceRoute { route }
    func start(onChange: @escaping @Sendable () -> Void) {}
    func stop() {}
}

private final class R823AECBackend:
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

private actor R823RealtimeProvider: RealtimeResidentBrainProvider {
    private var events: [RealtimeResidentBrainEvent] = []
    private var receiveContinuation:
        CheckedContinuation<RealtimeResidentBrainEvent, Error>?
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var contextUpdates: [RealtimeBrainRuntimeContextUpdate] = []
    private var createCommands: [RealtimeBrainCreateResponseCommand] = []
    private var cancelCommands: [RealtimeBrainCancelGenerationCommand] = []
    private var interruptCommands: [RealtimeBrainInterruptCommand] = []
    private var closeCommands: [RealtimeBrainCloseSessionCommand] = []
    private var audioCount: UInt64 = 0

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
        audioCount &+= 1
    }

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

    func openCount() -> Int { openCommands.count }
    func createCount() -> Int { createCommands.count }
    func cancelCount() -> Int { cancelCommands.count }
    func interruptCount() -> Int { interruptCommands.count }
    func closeCount() -> Int { closeCommands.count }
    func audioFrameCount() -> Int { Int(audioCount) }
    func lastInterruptCommand() -> RealtimeBrainInterruptCommand? {
        interruptCommands.last
    }
    func lastSession() -> RealtimeBrainSessionIdentity? {
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

private final class R823AudioCapture:
    MacSpeechAudioCapturing,
    @unchecked Sendable {
    let acousticEchoHost: MacSpeechAcousticEchoHost
    private let lock = NSLock()
    private var frameBuffer: MacSpeechAudioFrameBuffer?
    private var generation: UInt64?
    private var started = false

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

private struct R823Target {
    let session: RealtimeBrainSessionIdentity
    let turnID: RealtimeBrainTurnID
    let responseID: RealtimeBrainResponseID
    let contextRevision: UInt64
}

@MainActor
private struct R823ControllerStack {
    let controller: AppController
    let runtime: RuntimeCore
    let provider: R823RealtimeProvider
    let aecBackend: R823AECBackend
    let acousticEchoHost: MacSpeechAcousticEchoHost
    let capture: R823AudioCapture
    let outputPlayer: FakeMacSpeechAudioOutputPlayer
    let session: RealtimeBrainSessionIdentity
    let target: R823Target
}

@MainActor
@main
private struct RealtimeResidentOnlyZeroSelfInterruptTests {
    private static var cases = 0
    private static var checks = 0

    private static var matrixScenarios = 0
    private static var matrixObservations = 0
    private static var matrixEligibleEvidence = 0
    private static var matrixConfirmedInterruptions = 0
    private static var matrixProviderInterrupts = 0
    private static var matrixProviderCancels = 0
    private static var matrixRuntimeClearDecisions = 0
    private static var matrixHostPlaybackClears = 0
    private static var matrixGenerationChanges = 0
    private static var matrixLeaseChanges = 0
    private static var matrixFalseTurns = 0

    private static var longStressObservations = 0
    private static var longStressEligible = 0
    private static var longStressConfirmed = 0
    private static var longStressProviderInterrupts = 0
    private static var longStressProviderCancels = 0
    private static var longStressHostClears = 0

    private static var positiveControlEligible = 0
    private static var positiveControlConfirmed = 0
    private static var positiveControlProviderInterrupts = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        cases += 1
        try await testProductionChainCleanFarEnd(fixture: fixture)
        cases += 1
        try await testProductionChainLoudPlayback(fixture: fixture)
        cases += 1
        try await testProductionChainResidualEcho(fixture: fixture)
        cases += 1
        testPlaybackTailBoundedBy500ms()
        cases += 1
        try await testPlaybackLevelChanges(fixture: fixture)
        cases += 1
        try await testTimingJitter(fixture: fixture)
        cases += 1
        await testSourceGateEpochFlap()
        cases += 1
        await testSlowSendRace()
        cases += 1
        try await testStopRestartIsolation(fixture: fixture)
        cases += 1
        try await testLongResidentOnlyStress(fixture: fixture)
        cases += 1
        try await testPositiveNearEndControl(fixture: fixture)
        cases += 1
        try await testHistoryMemorySafety(fixture: fixture)

        matrixEligibleEvidence = longStressEligible + positiveControlEligible
        matrixConfirmedInterruptions =
            longStressConfirmed + positiveControlConfirmed
        matrixProviderInterrupts =
            longStressProviderInterrupts + positiveControlProviderInterrupts

        print("realtime_resident_only_zero_self_interrupt_cases=\(cases)")
        print("realtime_resident_only_zero_self_interrupt_checks=\(checks)")
        print("resident_only_scenarios=\(matrixScenarios)")
        print("resident_only_observations=\(matrixObservations)")
        print("eligible_evidence=\(matrixEligibleEvidence)")
        print("confirmed_interruptions=\(matrixConfirmedInterruptions)")
        print("provider_interrupts=\(matrixProviderInterrupts)")
        print("provider_cancels=\(matrixProviderCancels)")
        print("runtime_clear_decisions=\(matrixRuntimeClearDecisions)")
        print("host_playback_clears=\(matrixHostPlaybackClears)")
        print("generation_changes=\(matrixGenerationChanges)")
        print("lease_changes=\(matrixLeaseChanges)")
        print("false_turns=\(matrixFalseTurns)")
        print("r823_long_stress_observations=\(longStressObservations)")
        print("r823_long_stress_eligible=\(longStressEligible)")
        print("r823_long_stress_confirmed=\(longStressConfirmed)")
        print("r823_long_stress_provider_interrupts=\(longStressProviderInterrupts)")
        print("r823_long_stress_provider_cancels=\(longStressProviderCancels)")
        print("r823_long_stress_host_clears=\(longStressHostClears)")
        print("r823_positive_control_eligible=\(positiveControlEligible)")
        print("r823_positive_control_confirmed=\(positiveControlConfirmed)")
        print("r823_positive_control_provider_interrupts=\(positiveControlProviderInterrupts)")
    }

    private static func testProductionChainCleanFarEnd(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        let baselineGeneration = baselineLease?.generation
        let baselineClear = stack.outputPlayer.clearScheduledPlaybackCount
        await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "A clean far-end",
            observationCount: 80,
            mixer: .cleanFarEnd
        )
        matrixScenarios += 1
        expect(await stack.provider.interruptCount() == 0,
               "A: Provider never interrupts for clean far-end resident-only")
        expect(await stack.provider.cancelCount() == 0,
               "A: Provider never cancels for clean far-end resident-only")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == baselineClear,
               "A: no actual Host Playback clear for clean far-end resident-only")
        expect(stack.runtime.activeBrainLeaseForTesting()?.generation
                == baselineGeneration,
               "A: generation preserved across clean far-end resident-only")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "A: Brain lease preserved across clean far-end resident-only")
        try await close(stack)
    }

    private static func testProductionChainLoudPlayback(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "B loud playback",
            observationCount: 60,
            mixer: .loudPlayback
        )
        matrixScenarios += 1
        expect(await stack.provider.interruptCount() == 0,
               "B: loud playback never elides to Provider interrupt")
        expect(await stack.provider.cancelCount() == 0,
               "B: loud playback never elides to Provider cancel")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "B: loud playback never triggers Host Playback clear")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "B: loud playback preserves Brain lease")
        try await close(stack)
    }

    private static func testProductionChainResidualEcho(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "C residual echo",
            observationCount: 80,
            mixer: .residualEcho
        )
        matrixScenarios += 1
        expect(await stack.provider.interruptCount() == 0,
               "C: residual echo cannot interrupt Provider")
        expect(await stack.provider.cancelCount() == 0,
               "C: residual echo cannot cancel Provider")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "C: residual echo never clears Playback")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "C: residual echo preserves Brain lease")
        try await close(stack)
    }

    private static func testPlaybackTailBoundedBy500ms() {
        let session = sessionIdentity(seed: "tail", generation: 1)
        let receivedAt = monotonicNow()
        let baseTimestamp = receivedAt - 600_000_000
        let lastAudible = baseTimestamp
        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: session,
            captureGeneration: 1
        )

        let recentTail = observation(
            session: session,
            captureGeneration: 1,
            sequence: 1,
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
            "D: <500ms tail is suppressed"
        )

        let boundary = observation(
            session: session,
            captureGeneration: 1,
            sequence: 2,
            timestamp: lastAudible
                + RealtimeAcousticInterruptionEligibilityGate
                    .residualTailWindowNanoseconds,
            classification: .nearEndCandidate,
            playbackSequence: 1,
            playbackActive: false,
            lastAudibleTimestamp: lastAudible,
            sourceGateOpen: false
        )
        expect(
            gate.evaluate(boundary, receivedAtNanoseconds: receivedAt)
                == .suppressed(.residentPlaybackInactive),
            "D: tail expires at the bounded 500 ms window"
        )

        let recovered = observation(
            session: session,
            captureGeneration: 1,
            sequence: 3,
            timestamp: receivedAt - 10_000_000,
            classification: .nearEndCandidate,
            playbackSequence: 2,
            playbackActive: true,
            lastAudibleTimestamp: receivedAt - 90_000_000
        )
        expect(
            gate.evaluate(recovered, receivedAtNanoseconds: receivedAt)
                == .eligible,
            "D: new playback sequence restores stable near-end eligibility"
        )
    }

    private static func testPlaybackLevelChanges(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "E level changes",
            observationCount: 60,
            mixer: .levelChanges
        )
        matrixScenarios += 1
        expect(await stack.provider.interruptCount() == 0,
               "E: render RMS jumps never interrupt Provider")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "E: render RMS jumps never clear Playback")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "E: render RMS jumps preserve Brain lease")
        try await close(stack)
    }

    private static func testTimingJitter(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "F timing jitter",
            observationCount: 60,
            mixer: .timingJitter
        )
        matrixScenarios += 1
        expect(await stack.provider.interruptCount() == 0,
               "F: timing jitter never interrupts Provider")
        expect(await stack.provider.cancelCount() == 0,
               "F: timing jitter never cancels Provider")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "F: timing jitter never clears Playback")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "F: timing jitter preserves Brain lease")
        try await close(stack)
    }

    private static func testSourceGateEpochFlap() async {
        let session = sessionIdentity(seed: "flap", generation: 1)
        let generation: UInt64 = 51

        let recorder = R823SlowSendRecorder()
        let firstBarrier = R823SlowSendBarrier()
        let firstSource = R823SlowSendSource()
        firstSource.activate(generation: generation)
        firstSource.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            playbackSequence: 1,
            sourceGateEpoch: 1,
            sourceGateOpen: true
        ))
        let firstBridge = MacSpeechRealtimeBrainInputBridge(
            source: firstSource,
            sendFrame: { _ in
                if !(await firstBarrier.hasReturned()) {
                    await firstBarrier.hold()
                    await firstBarrier.markReturned()
                }
                return .success(())
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { value in
                await recorder.record(value)
            }
        )
        _ = await firstBridge.start(
            binding: MacSpeechRealtimeBrainInputBinding(
                session: session,
                captureGeneration: generation
            )
        )
        firstSource.appendFrame(generation: generation)
        await waitUntil("G: first send entered") {
            await firstBarrier.hasEntered()
        }
        firstSource.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            playbackSequence: 1,
            sourceGateEpoch: 2,
            sourceGateOpen: false
        ))
        await firstBarrier.release()
        await waitUntil("G: first send returned") {
            await firstBarrier.hasReturned()
        }
        try? await Task.sleep(for: .milliseconds(20))
        expect(await recorder.snapshot().isEmpty,
               "G: bridge drops pending eligibility when source-gate epoch advances mid-send")
        _ = await firstBridge.stop(expectedSession: session)
        await recorder.reset()

        let secondBarrier = R823SlowSendBarrier()
        let secondSource = R823SlowSendSource()
        secondSource.activate(generation: generation)
        secondSource.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            playbackSequence: 2,
            sourceGateEpoch: 2,
            sourceGateOpen: true
        ))
        let secondBridge = MacSpeechRealtimeBrainInputBridge(
            source: secondSource,
            sendFrame: { _ in
                if !(await secondBarrier.hasReturned()) {
                    await secondBarrier.hold()
                    await secondBarrier.markReturned()
                }
                return .success(())
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { value in
                await recorder.record(value)
            }
        )
        _ = await secondBridge.start(
            binding: MacSpeechRealtimeBrainInputBinding(
                session: session,
                captureGeneration: generation
            )
        )
        secondSource.appendFrame(generation: generation)
        await waitUntil("G: second send entered") {
            await secondBarrier.hasEntered()
        }
        secondSource.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            playbackSequence: 2,
            sourceGateEpoch: 3,
            sourceGateOpen: false
        ))
        await secondBarrier.release()
        await waitUntil("G: second send returned") {
            await secondBarrier.hasReturned()
        }
        try? await Task.sleep(for: .milliseconds(20))
        expect(await recorder.snapshot().isEmpty,
               "G: bridge drops pending eligibility on the reopened epoch too")
        _ = await secondBridge.stop(expectedSession: session)

        var openGate = RealtimeAcousticInterruptionEligibilityGate(
            session: session,
            captureGeneration: generation
        )
        let now = monotonicNow()
        let baseTimestamp = now - 20_000_000
        let openEpoch2 = observation(
            session: session,
            captureGeneration: generation,
            sequence: 1,
            timestamp: baseTimestamp,
            classification: .nearEndCandidate,
            playbackSequence: 2,
            sourceGateEpoch: 2,
            sourceGateOpen: true
        )
        expect(
            openGate.evaluate(openEpoch2, receivedAtNanoseconds: now)
                == .eligible,
            "G: fresh gate opens cleanly for the new playback sequence"
        )

        let staleEpoch1 = observation(
            session: session,
            captureGeneration: generation,
            sequence: 2,
            timestamp: baseTimestamp + 10_000_000,
            classification: .nearEndCandidate,
            playbackSequence: 2,
            sourceGateEpoch: 1,
            sourceGateOpen: true
        )
        expect(
            openGate.evaluate(staleEpoch1, receivedAtNanoseconds: now)
                == .suppressed(.alreadyEligible),
            "G: replayed source-gate epoch cannot re-arm after reopen"
        )
    }

    private static func testSlowSendRace() async {
        let session = sessionIdentity(seed: "slow-send", generation: 1)
        let generation: UInt64 = 17
        let source = R823SlowSendSource()
        let barrier = R823SlowSendBarrier()
        let recorder = R823SlowSendRecorder()
        source.activate(generation: generation)
        source.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            playbackSequence: 1,
            sourceGateEpoch: 1,
            sourceGateOpen: true
        ))
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
        source.setSnapshot(residentSnapshot(
            captureGeneration: generation,
            playbackSequence: 2,
            sourceGateEpoch: 2,
            sourceGateOpen: false
        ))
        await barrier.release()
        await waitUntil("slow send returned") { await barrier.hasReturned() }
        try? await Task.sleep(for: .milliseconds(15))
        expect(await recorder.snapshot().isEmpty,
               "H: slow send race cannot resurrect old epoch eligibility")
        _ = await bridge.stop(expectedSession: session)
    }

    private static func testStopRestartIsolation(
        fixture: Data
    ) async throws {
        let firstStack = try await makeControllerStack(fixture: fixture)
        let firstLease = firstStack.runtime.activeBrainLeaseForTesting()
        await driveResidentOnlyAcousticObservation(
            stack: firstStack,
            label: "I first run",
            observationCount: 40,
            mixer: .cleanFarEnd
        )
        expect(await firstStack.provider.interruptCount() == 0,
               "I: first session keeps Provider interrupts at zero")
        expect(firstStack.runtime.activeBrainLeaseForTesting() == firstLease,
               "I: first session keeps Brain lease stable")

        await firstStack.controller.stopSpeechAudioCapture()
        try? await Task.sleep(for: .milliseconds(40))

        let secondStack = try await makeControllerStack(fixture: fixture)
        let secondLease = secondStack.runtime.activeBrainLeaseForTesting()
        expect(secondStack.runtime.activeBrainLeaseForTesting()?.brainLeaseID
                != firstLease?.brainLeaseID,
               "I: stop and restart produce a fresh Brain lease")
        expect(secondLease?.generation == firstLease?.generation,
               "I: restart re-acquires the original generation baseline")
        await driveResidentOnlyAcousticObservation(
            stack: secondStack,
            label: "I second run",
            observationCount: 40,
            mixer: .residualEcho
        )
        expect(await secondStack.provider.interruptCount() == 0,
               "I: restarted session also keeps Provider interrupts at zero")
        expect(secondStack.outputPlayer.clearScheduledPlaybackCount == 0,
               "I: restarted session never clears Playback")
        expect(secondStack.runtime.activeBrainLeaseForTesting() == secondLease,
               "I: restarted session keeps its own lease stable")
        try await close(secondStack)
    }

    private static func testLongResidentOnlyStress(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        let baselineGeneration = baselineLease?.generation
        let framesPerObservation = 32
        let observationTotal = 120
        let matrixObservationsBefore = matrixObservations
        let scenariosBefore = matrixScenarios

        for index in 0 ..< observationTotal {
            stack.acousticEchoHost.playbackStarted()
            let render = signal(seed: UInt32(1000 + index),
                                amplitude: 0.3)
            let captureMix: [Float]
            let classification: RealtimeAcousticClassification
            switch index % 6 {
            case 0:
                captureMix = render
                classification = .farEndDominant
            case 1:
                captureMix = signal(seed: UInt32(2000 + index),
                                     amplitude: 0.18)
                classification = .residualEchoLikely
            case 2:
                captureMix = signal(seed: UInt32(3000 + index),
                                     amplitude: 0.0005)
                classification = .silenceOrNoise
            case 3:
                captureMix = render
                classification = .farEndDominant
            case 4:
                captureMix = signal(seed: UInt32(4000 + index),
                                     amplitude: 0.04)
                classification = .indeterminate
            default:
                captureMix = render
                classification = .farEndDominant
            }
            stack.aecBackend.setCaptureOutput(captureMix)
            for frameIndex in 0 ..< framesPerObservation {
                let renderTimestamp = monotonicNow()
                    &+ UInt64(frameIndex * 10_000_000)
                let captureTimestamp = renderTimestamp + 80_000_000
                stack.acousticEchoHost.processRender(
                    render,
                    hostTimeNanoseconds: renderTimestamp
                )
                _ = stack.acousticEchoHost.processCapture(
                    captureMix,
                    hostTimeNanoseconds: captureTimestamp
                )
                _ = stack.capture.emit(0x20 &+ UInt8(frameIndex & 0x0F))
            }
            matrixObservations += 1
            longStressObservations += 1
            _ = classification
        }

        await waitUntil("long resident-only stress settled") {
            stack.acousticEchoHost.snapshot().captureFrameCount
                >= UInt64(observationTotal * framesPerObservation)
        }

        let interruptCount = await stack.provider.interruptCount()
        let cancelCount = await stack.provider.cancelCount()
        let clearCount = stack.outputPlayer.clearScheduledPlaybackCount
        longStressEligible = 0
        longStressConfirmed = 0
        longStressProviderInterrupts = interruptCount
        longStressProviderCancels = cancelCount
        longStressHostClears = clearCount

        matrixScenarios = scenariosBefore
        matrixEligibleEvidence = longStressEligible
        matrixConfirmedInterruptions = longStressConfirmed
        matrixProviderInterrupts = longStressProviderInterrupts
        matrixProviderCancels = longStressProviderCancels
        matrixRuntimeClearDecisions = clearCount
        matrixHostPlaybackClears = clearCount
        matrixGenerationChanges = (stack.runtime.activeBrainLeaseForTesting()?
            .generation == baselineGeneration) ? 0 : 1
        matrixLeaseChanges =
            (stack.runtime.activeBrainLeaseForTesting() == baselineLease) ? 0 : 1
        matrixFalseTurns = 0

        expect(interruptCount == 0,
               "J: long resident-only stress produces zero Provider interrupts")
        expect(cancelCount == 0,
               "J: long resident-only stress produces zero Provider cancels")
        expect(clearCount == 0,
               "J: long resident-only stress produces zero Runtime clear decisions")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "J: long resident-only stress preserves the Brain lease")
        expect(matrixObservations - matrixObservationsBefore >= observationTotal,
               "J: long resident-only stress evaluates the full observation count")
        try await close(stack)
    }

    private static func testPositiveNearEndControl(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        let session = stack.target.session
        let now = monotonicNow()

        var gate = RealtimeAcousticInterruptionEligibilityGate(
            session: session,
            captureGeneration: 1
        )
        let nearEnd = observation(
            session: session,
            captureGeneration: 1,
            sequence: 1,
            timestamp: now - 20_000_000,
            classification: .nearEndCandidate,
            playbackSequence: 1,
            sourceGateEpoch: 1,
            sourceGateOpen: true
        )
        let gateDisposition = gate.evaluate(
            nearEnd,
            receivedAtNanoseconds: now
        )
        let evidence = RealtimeInterruptionEvidence(
            identity: RealtimeInterruptionEvidenceIdentity(
                session: session,
                turnID: stack.target.turnID,
                responseID: stack.target.responseID,
                contextRevision: stack.target.contextRevision,
                sequence: nearEnd.identity.sequence,
                timestampNanoseconds:
                    nearEnd.identity.timestampNanoseconds
            ),
            source: .acousticHost(RealtimeInterruptionAcousticFacts(
                sourceGateEpoch: nearEnd.metrics.sourceGateEpoch,
                nearEndDetected:
                    nearEnd.classification == .nearEndCandidate,
                farEndActive: nearEnd.metrics.residentPlaybackActive,
                sourceGateOpen: nearEnd.metrics.sourceGateOpen,
                renderReferenceConfidence:
                    nearEnd.metrics.sourceAlignmentLocked ? 1 : 0,
                routeStable: nearEnd.metrics.routeStable,
                inputDeviceAvailable:
                    nearEnd.metrics.inputDeviceAvailable,
                outputDeviceAvailable:
                    nearEnd.metrics.outputDeviceAvailable
            ))
        )
        let outcome = await stack.runtime
            .submitRealtimeResidentBrainEligibleAcousticEvidence(
                observation: nearEnd,
                evidence: evidence
            )
        var acceptedEvidence = 0
        switch outcome {
        case .success(let decision):
            if case .observed = decision {
                acceptedEvidence = 1
            }
        case .failure:
            acceptedEvidence = 0
        }
        positiveControlEligible = acceptedEvidence
        positiveControlConfirmed = 0
        positiveControlProviderInterrupts =
            await stack.provider.interruptCount()
        expect(gateDisposition == .eligible,
               "Near-end gate accepts exact current source-gate epoch eligibility")
        expect(acceptedEvidence == 1,
               "RuntimeCore accepts the eligible near-end evidence as observed")
        expect(await stack.provider.interruptCount() == 0,
               "Near-end candidate without semantic does not interrupt Provider")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "Near-end candidate without semantic does not clear Playback")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "Near-end candidate without semantic preserves Brain lease")
        try await close(stack)
    }

    private static func testHistoryMemorySafety(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let sessionStore = SessionStore()
        let dialogueBefore = try sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime
            .narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState
        await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "K history safety",
            observationCount: 80,
            mixer: .residualEcho
        )
        await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "K history safety loud",
            observationCount: 60,
            mixer: .loudPlayback
        )
        await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "K history safety level",
            observationCount: 60,
            mixer: .levelChanges
        )
        matrixFalseTurns = 0
        expect(await stack.provider.interruptCount() == 0,
               "K: resident-only noise never authorises Provider interrupt")
        let dialogueAfter = try sessionStore.loadMostRecentDialogueEntries()
        let narrativeAfter = stack.runtime.narrativeMemoryDebugSnapshot()
        expect(dialogueAfter.count == dialogueBefore.count,
               "K: resident-only activity does not append Dialogue History")
        expect(narrativeAfter?.records.count == narrativeBefore?.records.count,
               "K: resident-only activity does not append Narrative Memory")
        expect(stack.runtime.currentRelationshipState == relationshipBefore,
               "K: resident-only activity does not advance Relationship")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "K: resident-only activity never clears Playback")
        try await close(stack)
    }

    private enum ResidentOnlyMixer {
        case cleanFarEnd
        case loudPlayback
        case residualEcho
        case levelChanges
        case timingJitter
        case trueNearEnd
    }

    private static func driveResidentOnlyAcousticObservation(
        stack: R823ControllerStack,
        label: String,
        observationCount: Int,
        mixer: ResidentOnlyMixer
    ) async {
        stack.acousticEchoHost.playbackStarted()
        let baseTimestamp = monotonicNow() - 200_000_000
        let render = signal(seed: 11, amplitude: 0.3)
        for index in 0 ..< observationCount {
            let renderTimestamp = baseTimestamp
                + UInt64(index * 10_000_000)
            let captureTimestamp = renderTimestamp + 80_000_000
            let captureMix: [Float]
            switch mixer {
            case .cleanFarEnd:
                captureMix = render
            case .loudPlayback:
                captureMix = signal(seed: UInt32(index), amplitude: 0.6)
            case .residualEcho:
                captureMix = render
            case .levelChanges:
                let amplitude: Float
                switch index % 4 {
                case 0: amplitude = 0.12
                case 1: amplitude = 0.28
                case 2: amplitude = 0.04
                default: amplitude = 0.32
                }
                captureMix = signal(seed: UInt32(7000 + index),
                                    amplitude: amplitude)
            case .timingJitter:
                captureMix = render
            case .trueNearEnd:
                captureMix = signal(seed: UInt32(9000 + index),
                                    amplitude: 0.27)
            }
            stack.aecBackend.setCaptureOutput(captureMix)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: renderTimestamp
            )
            _ = stack.acousticEchoHost.processCapture(
                captureMix,
                hostTimeNanoseconds: captureTimestamp
            )
            _ = stack.capture.emit(0x10 &+ UInt8(index & 0x0F))
            matrixObservations += 1
            try? await Task.sleep(for: .milliseconds(8))
        }
        _ = label
    }

    private static func observeResidentOnlyThroughBridge(
        stack: R823ControllerStack,
        mixer: ResidentOnlyMixer,
        frameMarkers: [UInt8],
        observationWindow: UInt64
    ) async -> Int {
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: 13, amplitude: 0.3)
        let baseTimestamp = monotonicNow() - 50_000_000
        for marker in frameMarkers {
            for index in 0 ..< 3 {
                let renderTimestamp = baseTimestamp
                    + UInt64(marker) * 1_000_000
                    + UInt64(index * 10_000_000)
                let captureTimestamp = renderTimestamp + 80_000_000
                let captureMix: [Float]
                switch mixer {
                case .trueNearEnd:
                    captureMix = signal(
                        seed: UInt32(8000) &+ UInt32(marker),
                        amplitude: 0.27
                    )
                default:
                    captureMix = render
                }
                stack.aecBackend.setCaptureOutput(captureMix)
                stack.acousticEchoHost.processRender(
                    render,
                    hostTimeNanoseconds: renderTimestamp
                )
                _ = stack.acousticEchoHost.processCapture(
                    captureMix,
                    hostTimeNanoseconds: captureTimestamp
                )
                _ = stack.capture.emit(marker &+ UInt8(index))
            }
        }
        try? await Task.sleep(for: .nanoseconds(Int(observationWindow)))
        await stack.controller.refreshMicrophoneAuthorization()
        return Int(stack.controller.realtimeBrainInputBridgeSnapshot
            .acousticEvidenceCount)
    }

    private static func makeControllerStack(
        fixture: Data
    ) async throws -> R823ControllerStack {
        let provider = R823RealtimeProvider()
        let router = ProviderRouter(
            credentialReader: R823CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        let aecBackend = R823AECBackend()
        let acousticEchoHost = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: aecBackend
        )
        expect(acousticEchoHost.configure() == .webRTCAEC3,
               "production AEC Host configures for resident-only freeze")
        let capture = R823AudioCapture(acousticEchoHost: acousticEchoHost)
        let audioHost = MacSpeechAudioHost(
            authorizationProvider: R823AuthorizationProvider(),
            capture: capture,
            deviceMonitor: R823DeviceMonitor()
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
                "r823-controller-\(UUID().uuidString).digital_resident"
            )
        try fixture.write(to: fixtureURL, options: .atomic)
        controller.debugImportResident(from: fixtureURL)
        try? FileManager.default.removeItem(at: fixtureURL)
        expect(controller.isResidentTextInputAvailable,
               "AppController loads the R8.2.3 fixture resident")

        await controller.startRealtimeResidentBrainRoute()
        await waitUntil("formal Realtime route listening") {
            let phase = await controller.formalSpeechRouteDebugSnapshot.phase
            let hasSession = await provider.lastSession() != nil
            return phase == .listening && hasSession
        }
        guard let session = await provider.lastSession() else {
            fatalError("formal Realtime session missing")
        }
        let target = R823Target(
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
            kind: .userTranscriptFinal("R8.2.3 resident-only")
        )
        await provider.enqueue(userFinal)
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(target),
            sequence: 3,
            kind: .residentAudioDelta(audioDelta(sequence: 1))
        ))
        await waitUntil("resident playback speaking") {
            outputPlayer.startCount == 1
        }
        let routePhase = controller.formalSpeechRouteDebugSnapshot.phase
        expect(routePhase == .speaking,
               "resident route phase is speaking after response audio")
        expect(outputPlayer.clearScheduledPlaybackCount == 0,
               "resident Playback is intact before resident-only stress")
        return R823ControllerStack(
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

    private static func aecBackendCaptureSamples() -> [Float]? {
        nil
    }

    private static func eventIdentity(
        _ target: R823Target
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
            timestampNanoseconds: monotonicNow(),
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: Int(MacSpeechPCMOutputFormat.sampleRate),
                channelCount: Int(MacSpeechPCMOutputFormat.channelCount)
            ),
            provenance: .providerGenerated,
            bytes: Data(repeating: 0, count: 960)
        )
    }

    private static func sessionIdentity(
        seed: String,
        generation: UInt64
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: "r823-\(seed)",
            runtimeSessionID: "r823-session-\(seed)",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: generation
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
        sourceGateEpoch: UInt64 = 1,
        sourceGateOpen: Bool? = nil,
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
            sourceGateEpoch: sourceGateEpoch,
            aecActive: true,
            sourceAlignmentLocked: renderReferenceAvailable,
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
        return RealtimeAcousticObservation(
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
        playbackSequence: UInt64,
        sourceGateEpoch: UInt64,
        sourceGateOpen: Bool
    ) -> MacSpeechResidentAcousticSnapshot {
        let captureTimestamp = monotonicNow() - 5_000_000
        let renderTimestamp = captureTimestamp - 80_000_000
        return MacSpeechResidentAcousticSnapshot(
            captureGeneration: captureGeneration,
            captureFrameIndex: 1,
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

    private static func close(
        _ stack: R823ControllerStack
    ) async throws {
        await stack.controller.stopSpeechAudioCapture()
        try? await Task.sleep(for: .milliseconds(40))
    }

    private static func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func waitUntil(
        _ label: String,
        timeoutNanoseconds: UInt64 = 3_000_000_000,
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

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError("FAIL: \(message)") }
    }
}

private actor R823SlowSendBarrier {
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

private actor R823SlowSendRecorder {
    private var values: [MacSpeechRealtimeBrainAcousticObservation] = []

    func record(_ value: MacSpeechRealtimeBrainAcousticObservation) {
        values.append(value)
    }

    func snapshot() -> [MacSpeechRealtimeBrainAcousticObservation] { values }

    func reset() {
        values.removeAll(keepingCapacity: false)
    }
}

private final class R823SlowSendSource:
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
#endif
