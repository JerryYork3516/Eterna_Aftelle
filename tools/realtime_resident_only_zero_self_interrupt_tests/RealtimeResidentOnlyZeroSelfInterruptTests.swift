import AVFoundation
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
    private let outputConverter: MacSpeechAudioConverter
    private var frameBuffer: MacSpeechAudioFrameBuffer?
    private var generation: UInt64?
    private var started = false

    init(acousticEchoHost: MacSpeechAcousticEchoHost) throws {
        guard let aecFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(MacSpeechAcousticEchoHost.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw MacSpeechAudioCaptureError.invalidInputFormat
        }
        self.acousticEchoHost = acousticEchoHost
        outputConverter = try MacSpeechAudioConverter(inputFormat: aecFormat)
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

    func emit(
        processedSamples: [Float]
    ) throws -> (packetCount: Int, activePacketCount: Int) {
        guard !processedSamples.isEmpty else { return (0, 0) }
        let cleanedBuffer = try MacSpeechFloatMono48kConverter.makeBuffer(
            samples: processedSamples
        )
        let packets = try outputConverter.convert(cleanedBuffer)
        let target = lock.withLock { (started, frameBuffer, generation) }
        guard target.0,
              let frameBuffer = target.1,
              let generation = target.2 else { return (0, 0) }
        var packetCount = 0
        var activePacketCount = 0
        for packet in packets {
            if frameBuffer.append(
                pcm16Bytes: packet.bytes,
                activity: packet.activity,
                generation: generation
            ) {
                packetCount += 1
                if packet.activity > 0.001 {
                    activePacketCount += 1
                }
            }
        }
        return (packetCount, activePacketCount)
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
    let sessionStore: SessionStore
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
    private static var matrixAudioFrames = 0
    private static var matrixEligibleEvidence = 0
    private static var matrixConfirmedInterruptions = 0
    private static var matrixProviderInterrupts = 0
    private static var matrixProviderCancels = 0
    private static var matrixRuntimeClearDecisions = 0
    private static var matrixHostPlaybackClears = 0
    private static var matrixGenerationChanges = 0
    private static var matrixLeaseChanges = 0
    private static var matrixFalseTurns = 0

    private static var residentOnlyEligibleEvidence = 0
    private static var residentOnlyConfirmedInterruptions = 0
    private static var residentOnlyProviderInterrupts = 0
    private static var residentOnlyProviderCancels = 0
    private static var residentOnlyRuntimeClearDecisions = 0
    private static var residentOnlyHostPlaybackClears = 0
    private static var residentOnlyGenerationChanges = 0
    private static var residentOnlyLeaseChanges = 0
    private static var residentOnlyFalseTurns = 0
    private static var residentOnlyFalseHistoryWrites = 0
    private static var residentOnlyFalseMemoryWrites = 0
    private static var residentOnlyRelationshipChanges = 0

    private static var longStressObservations = 0
    private static var longStressFrames = 0
    private static var longStressEligible = 0
    private static var longStressConfirmed = 0
    private static var longStressProviderInterrupts = 0
    private static var longStressProviderCancels = 0
    private static var longStressHostClears = 0

    private static var positiveControlEligible = 0
    private static var positiveControlRuntimeObserved = 0
    private static var positiveControlRuntimeAcousticEvidence = 0
    private static var positiveControlConfirmed = 0
    private static var positiveControlProviderInterrupts = 0
    private static var positiveControlProviderCancels = 0
    private static var positiveControlHostClears = 0
    private static var positiveControlGenerationChanges = 0
    private static var positiveControlLeaseChanges = 0
    private static var positiveControlHistoryWrites = 0
    private static var positiveControlMemoryWrites = 0
    private static var positiveControlRelationshipChanges = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2
                || (CommandLine.arguments.count == 3
                    && CommandLine.arguments[2]
                        == "--r831-positive-only") else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        if CommandLine.arguments.count == 3 {
            cases += 1
            try await testPositiveNearEndControl(fixture: fixture)
            print("realtime_true_near_end_opening_cases=\(cases)")
            print("realtime_true_near_end_opening_checks=\(checks)")
            print("r831_positive_control_acoustic_eligibility=\(positiveControlEligible)")
            print("r831_runtime_near_end_observations=\(positiveControlRuntimeObserved)")
            print("r831_runtime_acoustic_evidence=\(positiveControlRuntimeAcousticEvidence)")
            print("r831_confirmed_interruptions=\(positiveControlConfirmed)")
            print("r831_provider_interrupts=\(positiveControlProviderInterrupts)")
            print("r831_provider_cancels=\(positiveControlProviderCancels)")
            print("r831_host_playback_clears=\(positiveControlHostClears)")
            print("r831_generation_changes=\(positiveControlGenerationChanges)")
            print("r831_lease_changes=\(positiveControlLeaseChanges)")
            print("r831_false_history_writes=\(positiveControlHistoryWrites)")
            print("r831_false_memory_writes=\(positiveControlMemoryWrites)")
            print("r831_relationship_changes=\(positiveControlRelationshipChanges)")
            return
        }

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

        matrixEligibleEvidence = residentOnlyEligibleEvidence
        matrixConfirmedInterruptions = residentOnlyConfirmedInterruptions
        matrixProviderInterrupts = residentOnlyProviderInterrupts

        print("realtime_resident_only_zero_self_interrupt_cases=\(cases)")
        print("realtime_resident_only_zero_self_interrupt_checks=\(checks)")
        print("resident_only_scenarios=\(matrixScenarios)")
        print("resident_only_observations=\(matrixObservations)")
        print("resident_only_audio_frames=\(matrixAudioFrames)")
        print("resident_only_eligible_evidence=\(residentOnlyEligibleEvidence)")
        print("resident_only_confirmed_interruptions=\(residentOnlyConfirmedInterruptions)")
        print("resident_only_provider_interrupts=\(residentOnlyProviderInterrupts)")
        print("resident_only_provider_cancels=\(residentOnlyProviderCancels)")
        print("resident_only_runtime_clear_decisions=\(residentOnlyRuntimeClearDecisions)")
        print("resident_only_host_playback_clears=\(residentOnlyHostPlaybackClears)")
        print("resident_only_generation_changes=\(residentOnlyGenerationChanges)")
        print("resident_only_lease_changes=\(residentOnlyLeaseChanges)")
        print("resident_only_false_turns=\(residentOnlyFalseTurns)")
        print("resident_only_false_history_writes=\(residentOnlyFalseHistoryWrites)")
        print("resident_only_false_memory_writes=\(residentOnlyFalseMemoryWrites)")
        print("resident_only_relationship_changes=\(residentOnlyRelationshipChanges)")
        print("r823_long_stress_observations=\(longStressObservations)")
        print("r823_long_stress_frames=\(longStressFrames)")
        print("r823_long_stress_eligible=\(longStressEligible)")
        print("r823_long_stress_confirmed=\(longStressConfirmed)")
        print("r823_long_stress_provider_interrupts=\(longStressProviderInterrupts)")
        print("r823_long_stress_provider_cancels=\(longStressProviderCancels)")
        print("r823_long_stress_host_clears=\(longStressHostClears)")
        print("positive_control_eligible_evidence=\(positiveControlEligible)")
        print("positive_control_runtime_observed=\(positiveControlRuntimeObserved)")
        print("positive_control_runtime_acoustic_evidence=\(positiveControlRuntimeAcousticEvidence)")
        print("positive_control_confirmed_interruptions=\(positiveControlConfirmed)")
        print("positive_control_provider_interrupts=\(positiveControlProviderInterrupts)")
        print("positive_control_provider_cancels=\(positiveControlProviderCancels)")
        print("positive_control_host_playback_clears=\(positiveControlHostClears)")
        print("positive_control_generation_changes=\(positiveControlGenerationChanges)")
        print("positive_control_lease_changes=\(positiveControlLeaseChanges)")
        print("positive_control_false_history_writes=\(positiveControlHistoryWrites)")
        print("positive_control_false_memory_writes=\(positiveControlMemoryWrites)")
        print("positive_control_relationship_changes=\(positiveControlRelationshipChanges)")
    }

    private static func testProductionChainCleanFarEnd(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        let baselineGeneration = baselineLease?.generation
        let baselineClear = stack.outputPlayer.clearScheduledPlaybackCount
        let baselineEvidence = await bridgeEvidenceCount(stack)
        try await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "A clean far-end",
            observationCount: 80,
            mixer: .cleanFarEnd
        )
        let evidenceDelta = await settledBridgeEvidenceDelta(
            stack,
            baseline: baselineEvidence
        )
        residentOnlyEligibleEvidence += evidenceDelta
        matrixScenarios += 1
        expect(evidenceDelta == 0,
               "A: clean far-end produces zero acoustic eligibility")
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
        let baselineEvidence = await bridgeEvidenceCount(stack)
        try await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "B loud playback",
            observationCount: 60,
            mixer: .loudPlayback
        )
        let evidenceDelta = await settledBridgeEvidenceDelta(
            stack,
            baseline: baselineEvidence
        )
        residentOnlyEligibleEvidence += evidenceDelta
        matrixScenarios += 1
        expect(evidenceDelta == 0,
               "B: loud playback produces zero acoustic eligibility")
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
        let baselineEvidence = await bridgeEvidenceCount(stack)
        try await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "C residual echo",
            observationCount: 80,
            mixer: .residualEcho
        )
        let evidenceDelta = await settledBridgeEvidenceDelta(
            stack,
            baseline: baselineEvidence
        )
        residentOnlyEligibleEvidence += evidenceDelta
        matrixScenarios += 1
        expect(evidenceDelta == 0,
               "C: residual echo produces zero acoustic eligibility")
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
        let baselineEvidence = await bridgeEvidenceCount(stack)
        try await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "E level changes",
            observationCount: 60,
            mixer: .levelChanges
        )
        let evidenceDelta = await settledBridgeEvidenceDelta(
            stack,
            baseline: baselineEvidence
        )
        residentOnlyEligibleEvidence += evidenceDelta
        matrixScenarios += 1
        expect(evidenceDelta == 0,
               "E: playback level changes produce zero acoustic eligibility")
        expect(await stack.provider.interruptCount() == 0,
               "E: render RMS jumps never interrupt Provider")
        expect(await stack.provider.cancelCount() == 0,
               "E: render RMS jumps never cancel Provider")
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
        let baselineEvidence = await bridgeEvidenceCount(stack)
        try await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "F timing jitter",
            observationCount: 60,
            mixer: .timingJitter
        )
        let evidenceDelta = await settledBridgeEvidenceDelta(
            stack,
            baseline: baselineEvidence
        )
        residentOnlyEligibleEvidence += evidenceDelta
        matrixScenarios += 1
        expect(evidenceDelta == 0,
               "F: timing jitter produces zero acoustic eligibility")
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
        let firstEvidenceBaseline = await bridgeEvidenceCount(firstStack)
        try await driveResidentOnlyAcousticObservation(
            stack: firstStack,
            label: "I first run",
            observationCount: 40,
            mixer: .cleanFarEnd
        )
        let firstEvidenceDelta = await settledBridgeEvidenceDelta(
            firstStack,
            baseline: firstEvidenceBaseline
        )
        residentOnlyEligibleEvidence += firstEvidenceDelta
        expect(firstEvidenceDelta == 0,
               "I: first session produces zero acoustic eligibility")
        expect(await firstStack.provider.interruptCount() == 0,
               "I: first session keeps Provider interrupts at zero")
        expect(await firstStack.provider.cancelCount() == 0,
               "I: first session keeps Provider cancels at zero")
        expect(firstStack.outputPlayer.clearScheduledPlaybackCount == 0,
               "I: first session never clears Playback")
        expect(firstStack.runtime.activeBrainLeaseForTesting() == firstLease,
               "I: first session keeps Brain lease stable")

        await firstStack.controller.stopSpeechAudioCapture()
        try? await Task.sleep(for: .milliseconds(40))

        let secondStack = try await makeControllerStack(fixture: fixture)
        let secondLease = secondStack.runtime.activeBrainLeaseForTesting()
        let secondEvidenceBaseline = await bridgeEvidenceCount(secondStack)
        expect(secondStack.runtime.activeBrainLeaseForTesting()?.brainLeaseID
                != firstLease?.brainLeaseID,
               "I: stop and restart produce a fresh Brain lease")
        expect(secondLease?.generation == firstLease?.generation,
               "I: restart re-acquires the original generation baseline")
        try await driveResidentOnlyAcousticObservation(
            stack: secondStack,
            label: "I second run",
            observationCount: 40,
            mixer: .residualEcho
        )
        let secondEvidenceDelta = await settledBridgeEvidenceDelta(
            secondStack,
            baseline: secondEvidenceBaseline
        )
        residentOnlyEligibleEvidence += secondEvidenceDelta
        expect(secondEvidenceDelta == 0,
               "I: restarted session produces zero acoustic eligibility")
        expect(await secondStack.provider.interruptCount() == 0,
               "I: restarted session also keeps Provider interrupts at zero")
        expect(await secondStack.provider.cancelCount() == 0,
               "I: restarted session keeps Provider cancels at zero")
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
        let baselineEvidenceCount = stack.controller
            .realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        try await submitSemanticProposal(stack: stack, sequence: 100)
        let framesPerObservation = 32
        let observationTotal = 120
        let matrixObservationsBefore = matrixObservations
        let matrixAudioFramesBefore = matrixAudioFrames
        let scenariosBefore = matrixScenarios
        let residentOnlyEligibleBefore = residentOnlyEligibleEvidence
        let residentOnlyConfirmedBefore = residentOnlyConfirmedInterruptions
        let providerInterruptsBefore = await stack.provider.interruptCount()
        let providerCancelsBefore = await stack.provider.cancelCount()
        let clearCountBefore = stack.outputPlayer.clearScheduledPlaybackCount

        for index in 0 ..< observationTotal {
            stack.acousticEchoHost.playbackStarted()
            let render = signal(seed: UInt32(1000 + index),
                                amplitude: 0.3)
            let captureMix: [Float]
            switch index % 6 {
            case 0:
                captureMix = render
            case 1:
                let noise = signal(seed: UInt32(2000 + index),
                                   amplitude: 0.05)
                captureMix = render.enumerated().map { idx, value in
                    value + (idx < noise.count ? noise[idx] : 0)
                }
            case 2:
                let noise = signal(seed: UInt32(3000 + index),
                                   amplitude: 0.001)
                captureMix = render.enumerated().map { idx, value in
                    value + (idx < noise.count ? noise[idx] : 0)
                }
            case 3:
                captureMix = render
            case 4:
                let noise = signal(seed: UInt32(4000 + index),
                                   amplitude: 0.01)
                captureMix = render.enumerated().map { idx, value in
                    value + (idx < noise.count ? noise[idx] : 0)
                }
            default:
                captureMix = render
            }
            stack.aecBackend.setCaptureOutput(captureMix)
            for _ in 0 ..< framesPerObservation {
                let captureTimestamp = monotonicNow()
                let renderTimestamp = captureTimestamp - 80_000_000
                stack.acousticEchoHost.processRender(
                    render,
                    hostTimeNanoseconds: renderTimestamp
                )
                let processed = stack.acousticEchoHost.processCapture(
                    captureMix,
                    hostTimeNanoseconds: captureTimestamp
                )
                _ = try stack.capture.emit(processedSamples: processed)
            }
            matrixObservations += 1
            matrixAudioFrames += framesPerObservation
            longStressObservations += 1
            longStressFrames += framesPerObservation
            if index % 8 == 7 {
                while stack.outputPlayer.pendingCount > 0 {
                    stack.outputPlayer.completeScheduledChunk()
                }
            }
        }

        while stack.outputPlayer.pendingCount > 0 {
            stack.outputPlayer.completeScheduledChunk()
        }

        await waitUntil("long resident-only stress settled") {
            stack.acousticEchoHost.snapshot().captureFrameCount
                >= UInt64(observationTotal * framesPerObservation)
        }
        try? await Task.sleep(for: .milliseconds(80))

        await stack.controller.refreshMicrophoneAuthorization()
        let afterEvidenceCount = stack.controller
            .realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        let bridgeEligibleDelta = Int(
            afterEvidenceCount &- baselineEvidenceCount
        )
        let afterLease = stack.runtime.activeBrainLeaseForTesting()
        let interruptCount =
            await stack.provider.interruptCount() &- providerInterruptsBefore
        let cancelCount =
            await stack.provider.cancelCount() &- providerCancelsBefore
        let clearCount = stack.outputPlayer.clearScheduledPlaybackCount
            &- clearCountBefore
        let generationChanged = afterLease?.generation != baselineGeneration
        let leaseChanged = afterLease != baselineLease

        longStressEligible = bridgeEligibleDelta
        longStressConfirmed = generationChanged ? 1 : 0
        longStressProviderInterrupts = interruptCount
        longStressProviderCancels = cancelCount
        longStressHostClears = clearCount

        residentOnlyEligibleEvidence += bridgeEligibleDelta
        if generationChanged { residentOnlyGenerationChanges += 1 }
        if leaseChanged { residentOnlyLeaseChanges += 1 }
        residentOnlyConfirmedInterruptions += generationChanged ? 1 : 0
        residentOnlyProviderInterrupts += interruptCount
        residentOnlyProviderCancels += cancelCount
        residentOnlyRuntimeClearDecisions += clearCount
        residentOnlyHostPlaybackClears += clearCount

        matrixScenarios += 1
        matrixEligibleEvidence = residentOnlyEligibleEvidence
        matrixConfirmedInterruptions = residentOnlyConfirmedInterruptions
        matrixProviderInterrupts = residentOnlyProviderInterrupts
        matrixProviderCancels = residentOnlyProviderCancels
        matrixRuntimeClearDecisions = residentOnlyRuntimeClearDecisions
        matrixHostPlaybackClears = residentOnlyHostPlaybackClears
        matrixGenerationChanges = residentOnlyGenerationChanges
        matrixLeaseChanges = residentOnlyLeaseChanges
        matrixFalseTurns = residentOnlyFalseTurns
        _ = matrixAudioFramesBefore
        _ = matrixObservationsBefore
        _ = scenariosBefore
        _ = residentOnlyEligibleBefore
        _ = residentOnlyConfirmedBefore

        expect(bridgeEligibleDelta == 0,
               "J: long resident-only stress with valid semantic evidence produces zero bridge eligibility delta")
        expect(generationChanged == false,
               "J: long resident-only stress preserves Runtime generation")
        expect(leaseChanged == false,
               "J: long resident-only stress preserves the exact Brain lease")
        expect(interruptCount == 0,
               "J: long resident-only stress produces zero Provider interrupts")
        expect(cancelCount == 0,
               "J: long resident-only stress produces zero Provider cancels")
        expect(clearCount == 0,
               "J: long resident-only stress produces zero Runtime clear decisions")
        expect(matrixObservations - matrixObservationsBefore >= observationTotal,
               "J: long resident-only stress evaluates the full observation count")
        try await close(stack)
    }

    private static func testPositiveNearEndControl(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        let baselineGeneration = baselineLease?.generation
        let baselineEvidenceCount = stack.controller
            .realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        let baselineForwardedFrameCount = stack.controller
            .realtimeBrainInputBridgeSnapshot.forwardedFrameCount
        let runtimeRecordCountBefore = stack.runtime
            .realtimeAcousticObservationDebugSnapshot().records.count
        let runtimeEvidenceBefore = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState
        let providerInterruptsBefore = await stack.provider.interruptCount()
        let providerCancelsBefore = await stack.provider.cancelCount()
        let clearCountBefore = stack.outputPlayer.clearScheduledPlaybackCount

        let emittedPacketCount = try await
            submitTrueNearEndThroughProductionChain(stack: stack)
        await waitUntil("Bridge sends production-chain capture frames") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller
                .realtimeBrainInputBridgeSnapshot.forwardedFrameCount
                >= baselineForwardedFrameCount + emittedPacketCount
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let bridgeAfterCapture = stack.controller
            .realtimeBrainInputBridgeSnapshot
        expect(
            bridgeAfterCapture.acousticEvidenceCount > baselineEvidenceCount,
            "Positive: Bridge forwards eligible near-end after "
                + "\(bridgeAfterCapture.forwardedFrameCount) PCM frames; "
                + "observed=\(bridgeAfterCapture.residentAcousticObservationCount) "
                + "rejected=\(bridgeAfterCapture.rejectedResidentAcousticObservationCount) "
                + "dropped=\(bridgeAfterCapture.droppedResidentAcousticObservationCount)"
        )
        await waitUntilOnMainActor("Runtime observes production-chain near-end") {
            stack.runtime.realtimeAcousticObservationDebugSnapshot()
                .records.dropFirst(runtimeRecordCountBefore)
                .contains { record in
                    record.observation.classification == .nearEndCandidate
                        && record.disposition == .observed
                }
        }
        try? await Task.sleep(for: .milliseconds(40))

        await stack.controller.refreshMicrophoneAuthorization()
        let afterEvidenceCount = stack.controller
            .realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        let bridgeEligibleDelta = Int(
            afterEvidenceCount &- baselineEvidenceCount
        )
        let afterLease = stack.runtime.activeBrainLeaseForTesting()
        let interruptCount =
            await stack.provider.interruptCount() &- providerInterruptsBefore
        let cancelCount =
            await stack.provider.cancelCount() &- providerCancelsBefore
        let clearCount = stack.outputPlayer.clearScheduledPlaybackCount
            &- clearCountBefore
        let generationChanged = afterLease?.generation != baselineGeneration
        let leaseChanged = afterLease != baselineLease
        let acceptedNearEndRecords = stack.runtime
            .realtimeAcousticObservationDebugSnapshot()
            .records.dropFirst(runtimeRecordCountBefore)
            .filter { record in
                record.observation.classification == .nearEndCandidate
                    && record.disposition == .observed
            }
        let runtimeEvidenceAfter = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
        let runtimeObserved = acceptedNearEndRecords.filter { record in
            record.observation.identity.sequence
                == runtimeEvidenceAfter.lastAcousticSequence
                && record.observation.identity.timestampNanoseconds
                    == runtimeEvidenceAfter.lastAcousticTimestampNanoseconds
        }.count
        let runtimeAcousticEvidenceAccepted =
            !runtimeEvidenceBefore.hasAcousticEvidence
            && runtimeEvidenceAfter.hasAcousticEvidence
            && !runtimeEvidenceAfter.hasSemanticEvidence
            && runtimeEvidenceAfter.session == stack.session
            && acceptedNearEndRecords.contains { record in
                record.observation.identity.sequence
                    == runtimeEvidenceAfter.lastAcousticSequence
                    && record.observation.identity.timestampNanoseconds
                        == runtimeEvidenceAfter
                            .lastAcousticTimestampNanoseconds
            }
        let dialogueAfter = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeAfter = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipAfter = stack.runtime.currentRelationshipState
        let historyWrites = dialogueAfter == dialogueBefore ? 0 : 1
        let memoryWrites = narrativeAfter == narrativeBefore ? 0 : 1
        let relationshipChanges = relationshipAfter == relationshipBefore
            ? 0 : 1

        positiveControlEligible = bridgeEligibleDelta
        positiveControlRuntimeObserved = runtimeObserved
        positiveControlRuntimeAcousticEvidence =
            runtimeAcousticEvidenceAccepted ? 1 : 0
        positiveControlConfirmed = generationChanged ? 1 : 0
        positiveControlProviderInterrupts = interruptCount
        positiveControlProviderCancels = cancelCount
        positiveControlHostClears = clearCount
        positiveControlGenerationChanges = generationChanged ? 1 : 0
        positiveControlLeaseChanges = leaseChanged ? 1 : 0
        positiveControlHistoryWrites = historyWrites
        positiveControlMemoryWrites = memoryWrites
        positiveControlRelationshipChanges = relationshipChanges

        expect(bridgeEligibleDelta == 1,
               "Positive: production chain near-end produces acoustic eligibility")
        expect(runtimeObserved == 1,
               "Positive: Runtime observes the eligible near-end candidate")
        expect(runtimeAcousticEvidenceAccepted,
               "Positive: Runtime atomically records acoustic-only evidence")
        expect(generationChanged == false,
               "Positive: production chain near-end preserves Runtime generation")
        expect(leaseChanged == false,
               "Positive: production chain near-end preserves the Brain lease")
        expect(interruptCount == 0,
               "Positive: production chain near-end never interrupts Provider")
        expect(cancelCount == 0,
               "Positive: production chain near-end never cancels Provider")
        expect(clearCount == 0,
               "Positive: production chain near-end never authorises Playback clear")
        expect(historyWrites == 0,
               "Positive: acoustic-only near-end writes no Dialogue History")
        expect(memoryWrites == 0,
               "Positive: acoustic-only near-end writes no Narrative Memory")
        expect(relationshipChanges == 0,
               "Positive: acoustic-only near-end preserves Relationship")
        try await close(stack)
    }

    private static func submitSemanticProposal(
        stack: R823ControllerStack,
        sequence: UInt64
    ) async throws {
        let identity = RealtimeBrainEventIdentity(
            session: stack.target.session,
            turnID: stack.target.turnID,
            responseID: stack.target.responseID,
            contextRevision: stack.target.contextRevision
        )
        let proposal = RealtimeResidentBrainEvent(
            identity: identity,
            sequence: sequence,
            kind: .interruptionProposed(RealtimeBrainInterruptionProposal(
                identity: identity,
                reason: "user_speech_started_during_resident_response"
            ))
        )
        await stack.provider.enqueue(proposal)
        try? await Task.sleep(for: .milliseconds(80))
    }

    private static func testHistoryMemorySafety(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        let baselineEvidence = await bridgeEvidenceCount(stack)
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime
            .narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState
        try await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "K history safety",
            observationCount: 80,
            mixer: .residualEcho
        )
        try await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "K history safety loud",
            observationCount: 60,
            mixer: .loudPlayback
        )
        try await driveResidentOnlyAcousticObservation(
            stack: stack,
            label: "K history safety level",
            observationCount: 60,
            mixer: .levelChanges
        )
        let evidenceDelta = await settledBridgeEvidenceDelta(
            stack,
            baseline: baselineEvidence
        )
        residentOnlyEligibleEvidence += evidenceDelta
        expect(evidenceDelta == 0,
               "K: history safety stress produces zero acoustic eligibility")
        expect(await stack.provider.interruptCount() == 0,
               "K: resident-only noise never authorises Provider interrupt")
        expect(await stack.provider.cancelCount() == 0,
               "K: resident-only noise never authorises Provider cancel")
        let dialogueAfter = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeAfter = stack.runtime.narrativeMemoryDebugSnapshot()
        let historyWrites = dialogueAfter == dialogueBefore ? 0 : 1
        let memoryWrites = narrativeAfter == narrativeBefore ? 0 : 1
        let relationshipChanges = stack.runtime.currentRelationshipState
            == relationshipBefore ? 0 : 1
        residentOnlyFalseTurns += historyWrites
        residentOnlyFalseHistoryWrites += historyWrites
        residentOnlyFalseMemoryWrites += memoryWrites
        residentOnlyRelationshipChanges += relationshipChanges
        matrixFalseTurns = residentOnlyFalseTurns
        expect(historyWrites == 0,
               "K: resident-only activity does not append Dialogue History")
        expect(memoryWrites == 0,
               "K: resident-only activity does not append Narrative Memory")
        expect(relationshipChanges == 0,
               "K: resident-only activity does not advance Relationship")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "K: resident-only activity never clears Playback")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "K: resident-only activity preserves the Brain lease")
        try await close(stack)
    }

    private static func submitTrueNearEndThroughProductionChain(
        stack: R823ControllerStack
    ) async throws -> UInt64 {
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: 17, amplitude: 0.3)
        let nearEnd = signal(seed: 19, amplitude: 0.27)
        let cleanedFarEnd = [Float](
            repeating: 0,
            count: MacSpeechAcousticEchoHost.frameSampleCount
        )
        var emittedPacketCount = 0
        var activePacketCount = 0
        for _ in 0 ..< 3 {
            let captureTimestamp = monotonicNow()
            let renderTimestamp = captureTimestamp - 80_000_000
            stack.aecBackend.setCaptureOutput(cleanedFarEnd)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: renderTimestamp
            )
            let processed = stack.acousticEchoHost.processCapture(
                render,
                hostTimeNanoseconds: captureTimestamp
            )
            expect(
                processed.count == MacSpeechAcousticEchoHost.frameSampleCount
                    && processed.allSatisfy { abs($0) < 0.000_001 },
                "Positive: far-end warm-up remains source-gated as silence"
            )
            let emission = try stack.capture.emit(
                processedSamples: processed
            )
            emittedPacketCount += emission.packetCount
            activePacketCount += emission.activePacketCount
            try? await Task.sleep(for: .milliseconds(12))
        }
        let warmup = stack.acousticEchoHost.acousticObservationSnapshot()
        expect(warmup.sourceAlignmentLocked,
               "Positive: far-end warm-up locks source alignment")
        expect(warmup.sourceAlignmentDelayMilliseconds == 80,
               "Positive: far-end warm-up locks the 80 ms delay")
        expect(warmup.inputClassification == .echoOnly,
               "Positive: far-end warm-up remains echo-only")
        expect(!warmup.sourceGateOpen,
               "Positive: far-end warm-up leaves source gate closed")

        for _ in 0 ..< 4 {
            let captureTimestamp = monotonicNow()
            let renderTimestamp = captureTimestamp - 80_000_000
            stack.aecBackend.setCaptureOutput(nearEnd)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: renderTimestamp
            )
            let processed = stack.acousticEchoHost.processCapture(
                nearEnd,
                hostTimeNanoseconds: captureTimestamp
            )
            let emission = try stack.capture.emit(
                processedSamples: processed
            )
            emittedPacketCount += emission.packetCount
            activePacketCount += emission.activePacketCount
            try? await Task.sleep(for: .milliseconds(12))
        }
        let nearEndSnapshot = stack.acousticEchoHost
            .acousticObservationSnapshot()
        expect(nearEndSnapshot.inputClassification == .nearEndSpeech,
               "Positive: AEC Host classifies true near-end speech")
        expect(nearEndSnapshot.sourceGateOpen,
               "Positive: true near-end opens the production source gate")
        expect(nearEndSnapshot.sourceGateEpoch > 0,
               "Positive: true near-end creates a source-gate epoch")
        expect(nearEndSnapshot.sourceAlignmentLocked,
               "Positive: alignment remains locked through source-gate open")
        expect(emittedPacketCount > 0,
               "Positive: production output converter emits PCM packets")
        expect(activePacketCount > 0,
               "Positive: emitted PCM contains opened near-end samples")
        return UInt64(emittedPacketCount)
    }

    private enum ResidentOnlyMixer {
        case cleanFarEnd
        case loudPlayback
        case residualEcho
        case levelChanges
        case timingJitter
    }

    private static func driveResidentOnlyAcousticObservation(
        stack: R823ControllerStack,
        label: String,
        observationCount: Int,
        mixer: ResidentOnlyMixer
    ) async throws {
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: 11, amplitude: 0.3)
        for index in 0 ..< observationCount {
            let captureTimestamp = monotonicNow()
            let renderDelayNanoseconds: UInt64
            if case .timingJitter = mixer {
                let jitterMilliseconds = [70, 90, 80, 100][index % 4]
                renderDelayNanoseconds = UInt64(jitterMilliseconds)
                    * 1_000_000
            } else {
                renderDelayNanoseconds = 80_000_000
            }
            let renderTimestamp = captureTimestamp
                - renderDelayNanoseconds
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
            }
            stack.aecBackend.setCaptureOutput(captureMix)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: renderTimestamp
            )
            let processed = stack.acousticEchoHost.processCapture(
                captureMix,
                hostTimeNanoseconds: captureTimestamp
            )
            _ = try stack.capture.emit(processedSamples: processed)
            matrixObservations += 1
            try? await Task.sleep(for: .milliseconds(8))
        }
        _ = label
    }

    private static func makeControllerStack(
        fixture: Data
    ) async throws -> R823ControllerStack {
        let provider = R823RealtimeProvider()
        let router = ProviderRouter(
            credentialReader: R823CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let sessionStore = SessionStore()
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: sessionStore
        )
        let aecBackend = R823AECBackend()
        let acousticEchoHost = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: aecBackend
        )
        expect(acousticEchoHost.configure() == .webRTCAEC3,
               "production AEC Host configures for resident-only freeze")
        let capture = try R823AudioCapture(
            acousticEchoHost: acousticEchoHost
        )
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
                consumerTimeoutNanoseconds: 30_000_000_000,
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
            sessionStore: sessionStore,
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

    private static func bridgeEvidenceCount(
        _ stack: R823ControllerStack
    ) async -> UInt64 {
        await stack.controller.refreshMicrophoneAuthorization()
        return stack.controller.realtimeBrainInputBridgeSnapshot
            .acousticEvidenceCount
    }

    private static func settledBridgeEvidenceDelta(
        _ stack: R823ControllerStack,
        baseline: UInt64
    ) async -> Int {
        try? await Task.sleep(for: .milliseconds(40))
        let current = await bridgeEvidenceCount(stack)
        return Int(current &- baseline)
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

    private static func waitUntilOnMainActor(
        _ label: String,
        timeoutNanoseconds: UInt64 = 3_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = monotonicNow() + timeoutNanoseconds
        while !condition() {
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
