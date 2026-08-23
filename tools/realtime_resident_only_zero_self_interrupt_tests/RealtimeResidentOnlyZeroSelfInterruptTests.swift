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
    private var audioFrames: [RealtimeBrainAudioFrame] = []
    private var receiveSessions: [RealtimeBrainSessionIdentity] = []
    private var enqueuedEvents: [RealtimeResidentBrainEvent] = []
    private var returnedEvents: [RealtimeResidentBrainEvent] = []
    private var holdsInterrupt = false
    private var interruptContinuation: CheckedContinuation<Void, Never>?

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
        audioFrames.append(frame)
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
        if holdsInterrupt {
            await withCheckedContinuation { continuation in
                interruptContinuation = continuation
            }
        }
    }

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        receiveSessions.append(session)
        let event: RealtimeResidentBrainEvent
        if !events.isEmpty {
            event = events.removeFirst()
        } else {
            event = try await withCheckedThrowingContinuation { continuation in
                precondition(receiveContinuation == nil)
                receiveContinuation = continuation
            }
        }
        returnedEvents.append(event)
        return event
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
        enqueuedEvents.append(event)
        deliver(event)
    }

    func openCount() -> Int { openCommands.count }
    func createCount() -> Int { createCommands.count }
    func cancelCount() -> Int { cancelCommands.count }
    func interruptCount() -> Int { interruptCommands.count }
    func closeCount() -> Int { closeCommands.count }
    func audioFrameCount() -> Int { Int(audioCount) }
    func audioFrames(after index: Int) -> [RealtimeBrainAudioFrame] {
        Array(audioFrames.dropFirst(index))
    }
    func receiveCount(session: RealtimeBrainSessionIdentity) -> Int {
        receiveSessions.filter { $0 == session }.count
    }
    func lastInterruptCommand() -> RealtimeBrainInterruptCommand? {
        interruptCommands.last
    }
    func lastCreateCommand() -> RealtimeBrainCreateResponseCommand? {
        createCommands.last
    }
    func returnedEventCount(
        eventSession: RealtimeBrainSessionIdentity
    ) -> Int {
        returnedEvents.filter { $0.identity.session == eventSession }.count
    }
    func enqueuedEventCount(
        eventSession: RealtimeBrainSessionIdentity
    ) -> Int {
        enqueuedEvents.filter { $0.identity.session == eventSession }.count
    }
    func lastSession() -> RealtimeBrainSessionIdentity? {
        openCommands.last?.identity
    }

    func holdInterrupt() {
        holdsInterrupt = true
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
    let outputHost: MacSpeechAudioOutputHost
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

    private static var r832ProductionAcousticEligibility = 0
    private static var r832RuntimeNearEndObservations = 0
    private static var r832RuntimeAcousticEvidence = 0
    private static var r832FormalSemanticEvidence = 0
    private static var r832ConfirmedInterruptions = 0
    private static var r832ProviderInterrupts = 0
    private static var r832ProviderCancels = 0
    private static var r832HostPlaybackClears = 0
    private static var r832PlaybackGenerationDelta = 0
    private static var r832GenerationDelta = 0
    private static var r832GenerationBefore: UInt64 = 0
    private static var r832GenerationAfter: UInt64 = 0
    private static var r832ResidentIDChanges = 0
    private static var r832RuntimeSessionIDChanges = 0
    private static var r832BrainLeaseIDChanges = 0
    private static var r832RouteEpochChanges = 0
    private static var r832ProviderReopens = 0
    private static var r832ProviderCloses = 0
    private static var r832ResponseCreates = 0
    private static var r832InputBridgeRebound = 0
    private static var r832OutputBridgeRebound = 0
    private static var r832RouteListening = 0
    private static var r832CapturePersistent = 0
    private static var r832InjectedOldOutputEventsRejected = 0
    private static var r832OldPlaybackCallbacksRejected = 0
    private static var r832ExtraInterruptions = 0
    private static var r832ExtraPlaybackClears = 0
    private static var r832FalseUserTurns = 0
    private static var r832FalseHistoryWrites = 0
    private static var r832FalseMemoryWrites = 0
    private static var r832RelationshipChanges = 0

    private static var r833FirstToEligibilityNanoseconds: UInt64 = 0
    private static var r833ConfirmedToClearNanoseconds: UInt64 = 0
    private static var r833FirstToClearNanoseconds: UInt64 = 0
    private static var r833PreclearOldPCM = 0
    private static var r833PreclearQueuedPCM = 0
    private static var r833PreclearScheduledPCM = 0
    private static var r833StaleEventsInjected = 0
    private static var r833StaleEventsReturned = 0
    private static var r833OldOutputAcceptedAfterFence = 0
    private static var r833OldGenerationAudioPlayed = 0
    private static var r833OldPlaybackRestarts = 0
    private static var r833OldTextResurrections = 0
    private static var r833OldCallbacksRejected = 0
    private static var r833ExtraInterruptions = 0
    private static var r833ExtraPlaybackClears = 0
    private static var r833ExtraGenerationChanges = 0
    private static var r833NPlusOneInputRebound = 0
    private static var r833NPlusOneOutputRebound = 0
    private static var r833NPlusOnePlayback = 0
    private static var r833NPlusOneListening = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2
                || (CommandLine.arguments.count == 3
                    && [
                        "--r831-positive-only",
                        "--r832-confirmed-only",
                        "--r833-latency-stale-only"
                    ].contains(CommandLine.arguments[2])) else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        if CommandLine.arguments.count == 3 {
            if CommandLine.arguments[2] == "--r833-latency-stale-only" {
                cases += 1
                try await testR833BargeInLatencyAndStaleClosure(
                    fixture: fixture
                )
                print("realtime_barge_in_latency_stale_cases=\(cases)")
                print("realtime_barge_in_latency_stale_checks=\(checks)")
                print("r833_first_valid_near_end_to_acoustic_eligibility_ns=\(r833FirstToEligibilityNanoseconds)")
                print("r833_confirmed_to_playback_clear_ns=\(r833ConfirmedToClearNanoseconds)")
                print("r833_first_valid_near_end_to_playback_clear_ns=\(r833FirstToClearNanoseconds)")
                print("r833_preclear_old_pcm=\(r833PreclearOldPCM)")
                print("r833_preclear_queued_pcm=\(r833PreclearQueuedPCM)")
                print("r833_preclear_scheduled_pcm=\(r833PreclearScheduledPCM)")
                print("r833_stale_events_injected=\(r833StaleEventsInjected)")
                print("r833_stale_events_returned=\(r833StaleEventsReturned)")
                print("r833_old_generation_output_accepted_after_fence=\(r833OldOutputAcceptedAfterFence)")
                print("r833_old_generation_audio_played=\(r833OldGenerationAudioPlayed)")
                print("r833_old_playback_restarts=\(r833OldPlaybackRestarts)")
                print("r833_old_text_or_subtitle_resurrections=\(r833OldTextResurrections)")
                print("r833_old_playback_callbacks_rejected=\(r833OldCallbacksRejected)")
                print("r833_extra_interruptions=\(r833ExtraInterruptions)")
                print("r833_extra_playback_clears=\(r833ExtraPlaybackClears)")
                print("r833_extra_generation_changes=\(r833ExtraGenerationChanges)")
                print("r833_n_plus_one_input_rebound=\(r833NPlusOneInputRebound)")
                print("r833_n_plus_one_output_rebound=\(r833NPlusOneOutputRebound)")
                print("r833_n_plus_one_playback=\(r833NPlusOnePlayback)")
                print("r833_n_plus_one_listening=\(r833NPlusOneListening)")
                print("r833_real_qwen_semantic_latency=NOT_RUN_HUMAN_GATE")
                print("r833_real_device_latency=NOT_RUN_HUMAN_GATE")
                return
            }
            if CommandLine.arguments[2] == "--r832-confirmed-only" {
                cases += 1
                try await testR832ConfirmedInterruptionProductionChain(
                    fixture: fixture
                )
                print("realtime_confirmed_interruption_cases=\(cases)")
                print("realtime_confirmed_interruption_checks=\(checks)")
                print("r832_production_acoustic_eligibility=\(r832ProductionAcousticEligibility)")
                print("r832_runtime_near_end_observations=\(r832RuntimeNearEndObservations)")
                print("r832_runtime_acoustic_evidence=\(r832RuntimeAcousticEvidence)")
                print("r832_formal_semantic_evidence=\(r832FormalSemanticEvidence)")
                print("r832_confirmed_interruptions=\(r832ConfirmedInterruptions)")
                print("r832_provider_interrupts=\(r832ProviderInterrupts)")
                print("r832_provider_cancels=\(r832ProviderCancels)")
                print("r832_host_playback_clears=\(r832HostPlaybackClears)")
                print("r832_playback_generation_delta=\(r832PlaybackGenerationDelta)")
                print("r832_runtime_generation_delta=\(r832GenerationDelta)")
                print("r832_generation_before=\(r832GenerationBefore)")
                print("r832_generation_after=\(r832GenerationAfter)")
                print("r832_resident_id_changes=\(r832ResidentIDChanges)")
                print("r832_runtime_session_id_changes=\(r832RuntimeSessionIDChanges)")
                print("r832_brain_lease_id_changes=\(r832BrainLeaseIDChanges)")
                print("r832_route_epoch_changes=\(r832RouteEpochChanges)")
                print("r832_provider_reopens=\(r832ProviderReopens)")
                print("r832_provider_closes=\(r832ProviderCloses)")
                print("r832_response_creates=\(r832ResponseCreates)")
                print("r832_input_bridge_rebound=\(r832InputBridgeRebound)")
                print("r832_output_bridge_rebound=\(r832OutputBridgeRebound)")
                print("r832_route_listening=\(r832RouteListening)")
                print("r832_capture_persistent=\(r832CapturePersistent)")
                print("r832_injected_old_output_events_rejected=\(r832InjectedOldOutputEventsRejected)")
                print("r832_old_playback_callbacks_rejected=\(r832OldPlaybackCallbacksRejected)")
                print("r832_extra_interruptions=\(r832ExtraInterruptions)")
                print("r832_extra_playback_clears=\(r832ExtraPlaybackClears)")
                print("r832_false_user_turns=\(r832FalseUserTurns)")
                print("r832_false_history_writes=\(r832FalseHistoryWrites)")
                print("r832_false_memory_writes=\(r832FalseMemoryWrites)")
                print("r832_relationship_changes=\(r832RelationshipChanges)")
                return
            }
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

    private static func testR833BargeInLatencyAndStaleClosure(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        await stack.controller.refreshMicrophoneAuthorization()
        guard let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        else {
            fatalError("R8.3.3 active Brain lease missing")
        }
        let baselineIdentity = stack.session
        let nextIdentity = RealtimeBrainSessionIdentity(
            residentID: baselineIdentity.residentID,
            runtimeSessionID: baselineIdentity.runtimeSessionID,
            brainLeaseID: baselineIdentity.brainLeaseID,
            routeEpoch: baselineIdentity.routeEpoch,
            generation: baselineIdentity.generation + 1
        )
        let initialPlayback = stack.controller.speechAudioOutputHostSnapshot
        let baselineCreateCount = await stack.provider.createCount()
        let baselineInterruptCount = await stack.provider.interruptCount()
        let baselineCancelCount = await stack.provider.cancelCount()
        let baselineOpenCount = await stack.provider.openCount()
        let baselineCloseCount = await stack.provider.closeCount()
        let baselineClearCount =
            stack.outputPlayer.clearScheduledPlaybackCount
        let baselinePlayerStartCount = stack.outputPlayer.startCount
        let baselineSubtitle = stack.controller
            .realtimeSpeechSubtitleSnapshot
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState

        for offset in 0 ..< 3 {
            await stack.provider.enqueue(RealtimeResidentBrainEvent(
                identity: eventIdentity(stack.target),
                sequence: UInt64(4 + offset),
                kind: .residentAudioDelta(audioDelta(
                    sequence: UInt64(2 + offset)
                ))
            ))
        }
        await waitUntil("R8.3.3 old PCM is queued and scheduled") {
            await stack.controller.refreshMicrophoneAuthorization()
            let playback = await stack.controller
                .speechAudioOutputHostSnapshot
            return playback.enqueuedChunkCount
                    == initialPlayback.enqueuedChunkCount + 3
                && playback.scheduledChunkCount == 2
                && playback.queueDepth == 2
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let preclearOutput = stack.controller
            .realtimeBrainOutputBridgeSnapshot
        let preclearPlayback = stack.controller
            .speechAudioOutputHostSnapshot
        let preclearTiming = await stack.outputHost.timingDebugSnapshot()
        expect(preclearPlayback.enqueuedChunkCount
                == initialPlayback.enqueuedChunkCount + 3,
               "R8.3.3 preloads four generation N PCM chunks")
        expect(preclearPlayback.scheduledChunkCount == 2,
               "R8.3.3 has two scheduled generation N PCM chunks")
        expect(preclearPlayback.queueDepth == 2,
               "R8.3.3 has two queued generation N PCM chunks")
        expect(stack.outputPlayer.startCount == baselinePlayerStartCount,
               "R8.3.3 preloading does not restart active Playback")

        let runtimeRecordCountBefore = stack.runtime
            .realtimeAcousticObservationDebugSnapshot().records.count
        await stack.provider.holdInterrupt()
        let emittedPacketCount = try await
            submitTrueNearEndThroughProductionChain(stack: stack)
        await waitUntilOnMainActor("R8.3.3 acoustic eligibility is atomic") {
            let evidence = stack.runtime
                .realtimeInterruptionEvidenceDebugSnapshot()
            return evidence.session == baselineIdentity
                && evidence.hasAcousticEvidence
                && !evidence.hasSemanticEvidence
        }
        let evidenceAtEligibility = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
        let nearEndRecords = stack.runtime
            .realtimeAcousticObservationDebugSnapshot()
            .records.dropFirst(runtimeRecordCountBefore)
            .filter { record in
                record.disposition == .observed
                    && record.observation.classification
                        == .nearEndCandidate
            }
        guard let firstValidNearEndAt = nearEndRecords.map({
            $0.observation.identity.timestampNanoseconds
        }).min(), nearEndRecords.contains(where: {
            $0.observation.identity.sequence
                    == evidenceAtEligibility.lastAcousticSequence
                && $0.observation.identity.timestampNanoseconds
                    == evidenceAtEligibility
                        .lastAcousticTimestampNanoseconds
        }), evidenceAtEligibility.acousticReceivedAtNanoseconds > 0 else {
            fatalError("R8.3.3 monotonic acoustic evidence missing")
        }
        let acousticEligibilityAt = evidenceAtEligibility
            .acousticReceivedAtNanoseconds
        await stack.provider.enqueue(
            semanticProposal(stack: stack, sequence: 7)
        )
        await waitUntil("R8.3.3 clear completes before held Provider ACK") {
            let timing = await stack.outputHost.timingDebugSnapshot()
            return await stack.provider.isInterruptHeld()
                && timing.clearCompletionCount
                    == preclearTiming.clearCompletionCount + 1
        }
        guard let confirmedTiming = stack.runtime
            .realtimeInterruptionTimingForTesting() else {
            fatalError("R8.3.3 confirmed timestamp missing")
        }
        let clearTiming = await stack.outputHost.timingDebugSnapshot()
        let confirmedAt = confirmedTiming.confirmedAtNanoseconds
        let clearAt = clearTiming.lastClearCompletedAtNanoseconds
        guard firstValidNearEndAt <= acousticEligibilityAt,
              acousticEligibilityAt <= confirmedAt,
              confirmedAt <= clearAt else {
            fatalError("R8.3.3 monotonic event order violated")
        }
        let firstToEligibility = acousticEligibilityAt
            - firstValidNearEndAt
        let confirmedToClear = clearAt - confirmedAt
        let firstToClear = clearAt - firstValidNearEndAt
        r833FirstToEligibilityNanoseconds = firstToEligibility
        r833ConfirmedToClearNanoseconds = confirmedToClear
        r833FirstToClearNanoseconds = firstToClear
        expect(emittedPacketCount > 0,
               "R8.3.3 true near-end traverses production PCM conversion")
        expect(confirmedTiming.interruptedIdentity == baselineIdentity,
               "R8.3.3 timing is bound to confirmed generation N")
        expect(firstValidNearEndAt <= acousticEligibilityAt
                && acousticEligibilityAt <= confirmedAt
                && confirmedAt <= clearAt,
               "R8.3.3 timing follows near-end, eligibility, confirmed, clear")
        expect(confirmedToClear <= 50_000_000,
               "R8.3.3 confirmed to Playback clear is at most 50 ms")
        expect(firstToClear <= 200_000_000,
               "R8.3.3 first valid near-end to clear is at most 200 ms")

        await stack.controller.refreshMicrophoneAuthorization()
        let heldInput = stack.controller.realtimeBrainInputBridgeSnapshot
        let heldOutput = stack.controller.realtimeBrainOutputBridgeSnapshot
        let heldPlayback = stack.controller.speechAudioOutputHostSnapshot
        r833PreclearOldPCM = preclearPlayback.enqueuedChunkCount
            - initialPlayback.enqueuedChunkCount + 1
        r833PreclearQueuedPCM = preclearPlayback.queueDepth
        r833PreclearScheduledPCM = preclearPlayback.scheduledChunkCount
        expect(!heldInput.hasActivePump && !heldOutput.hasActiveReceiveLoop,
               "R8.3.3 both Bridges are fenced while ACK is held")
        expect(heldPlayback.state == .prepared,
               "R8.3.3 clear completes before Provider ACK")
        expect(heldPlayback.queueDepth == 0
                && heldPlayback.scheduledChunkCount == 0,
               "R8.3.3 clear removes queued and scheduled old PCM")
        expect(heldPlayback.generation == preclearPlayback.generation + 1,
               "R8.3.3 clear advances Playback generation exactly once")
        expect(heldPlayback.playedChunkCount
                == preclearPlayback.playedChunkCount,
               "R8.3.3 no old PCM plays after clear")
        expect(stack.outputPlayer.startCount == baselinePlayerStartCount,
               "R8.3.3 clear does not restart old Playback")
        expect(await stack.provider.interruptCount()
                == baselineInterruptCount + 1,
               "R8.3.3 sends one Runtime-authorized Provider interrupt")
        expect(await stack.provider.cancelCount() == baselineCancelCount,
               "R8.3.3 never calls the separate cancel API")
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "R8.3.3 held ACK preserves generation N lease")

        let oldReturnedBaseline = await stack.provider.returnedEventCount(
            eventSession: baselineIdentity
        )
        let oldEnqueuedBaseline = await stack.provider.enqueuedEventCount(
            eventSession: baselineIdentity
        )
        let preAckOldEvents = oldGenerationOutputEvents(
            stack: stack,
            cycles: 1,
            sequenceBase: 20
        )
        for event in preAckOldEvents {
            await stack.provider.enqueue(event)
        }
        let preAckEnqueuedCount = await stack.provider.enqueuedEventCount(
            eventSession: baselineIdentity
        )
        let providerACKIsHeld = await stack.provider.isInterruptHeld()
        expect(preAckEnqueuedCount
                == oldEnqueuedBaseline + preAckOldEvents.count
                && providerACKIsHeld,
               "R8.3.3 old events reach Provider queue before ACK")
        stack.outputPlayer.completeStoppedChunk()
        stack.outputPlayer.completeStoppedChunk()
        await waitUntil("R8.3.3 old Playback callbacks are fenced") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller.speechAudioOutputHostSnapshot
                .rejectedCallbackCount
                == preclearPlayback.rejectedCallbackCount + 2
        }
        await stack.provider.releaseInterrupt()

        await waitUntilOnMainActor("R8.3.3 generation and Bridges rebound") {
            let lease = stack.runtime.activeBrainLeaseForTesting()
            let route = stack.controller.formalSpeechRouteDebugSnapshot
            return lease?.generation
                    == .realtimeResidentBrain(nextIdentity.generation)
                && route.phase == .listening
                && route.generation == nextIdentity.generation
                && stack.controller.realtimeBrainInputBridgeSnapshot
                    .hasActivePump
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop
        }
        await waitUntil("R8.3.3 all pre-ACK stale events return") {
            await stack.provider.returnedEventCount(
                eventSession: baselineIdentity
            ) == oldReturnedBaseline + preAckOldEvents.count
        }

        let reboundAudioBaseline = await stack.provider.audioFrameCount()
        let reboundPacketCount = try
            submitPostInterruptionInputThroughProductionChain(stack: stack)
        await waitUntil("R8.3.3 Input Bridge forwards generation N+1") {
            await stack.provider.audioFrameCount()
                >= reboundAudioBaseline + reboundPacketCount
        }
        let reboundFrames = await stack.provider.audioFrames(
            after: reboundAudioBaseline
        )
        expect(reboundFrames.count == reboundPacketCount,
               "R8.3.3 N+1 Input forwards every production PCM packet")
        expect(reboundFrames.allSatisfy { $0.identity == nextIdentity },
               "R8.3.3 N+1 Input carries the exact new generation")
        expect(reboundFrames.first?.sequence == 1
                && reboundFrames.enumerated().allSatisfy { index, frame in
                    frame.sequence == UInt64(index + 1)
                }, "R8.3.3 N+1 Input sequence restarts at one")
        expect(reboundFrames.allSatisfy {
            $0.provenance == .acousticEchoProcessed
        }, "R8.3.3 N+1 Input preserves production AEC provenance")

        var staleEventsInjected = preAckOldEvents.count
        let postAckOldEvents = oldGenerationOutputEvents(
            stack: stack,
            cycles: 2,
            sequenceBase: 40
        )
        for event in postAckOldEvents {
            await stack.provider.enqueue(event)
        }
        staleEventsInjected += postAckOldEvents.count
        let expectedPostAckOldReturned = oldReturnedBaseline
            + staleEventsInjected
        await waitUntil("R8.3.3 post-ACK stale events are drained") {
            await stack.provider.returnedEventCount(
                eventSession: baselineIdentity
            ) == expectedPostAckOldReturned
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let beforeNewOutput = stack.controller
            .realtimeBrainOutputBridgeSnapshot
        let beforeNewPlayback = stack.controller
            .speechAudioOutputHostSnapshot
        expect(beforeNewOutput.acceptedEventCount
                == preclearOutput.acceptedEventCount + 1,
               "R8.3.3 old events never reach the Host consumer")
        expect(stack.outputPlayer.startCount == baselinePlayerStartCount,
               "R8.3.3 stale burst cannot restart old Playback")
        expect(stack.controller.realtimeSpeechSubtitleSnapshot
                == baselineSubtitle,
               "R8.3.3 old text cannot resurrect subtitles")
        expect(stack.controller.formalSpeechRouteDebugSnapshot.phase
                == .listening,
               "R8.3.3 old speaking and terminal events cannot revive N")
        r833OldGenerationAudioPlayed = beforeNewPlayback.playedChunkCount
            - preclearPlayback.playedChunkCount
        r833OldPlaybackRestarts = stack.outputPlayer.startCount
            - baselinePlayerStartCount
        r833OldTextResurrections = stack.controller
            .realtimeSpeechSubtitleSnapshot == baselineSubtitle ? 0 : 1

        let nextTurnID = RealtimeBrainTurnID()
        let nextResponseID = RealtimeBrainResponseID()
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: nextIdentity,
                turnID: nextTurnID,
                responseID: nil,
                contextRevision: stack.target.contextRevision
            ),
            sequence: 1,
            kind: .userTranscriptFinal("R8.3.3 N+1 input rebound")
        ))
        await waitUntil("R8.3.3 N+1 response is authorized") {
            await stack.provider.createCount() == baselineCreateCount + 1
        }
        let createCommand = await stack.provider.lastCreateCommand()
        expect(createCommand?.identity.session == nextIdentity
                && createCommand?.identity.turnID == nextTurnID
                && createCommand?.identity.responseID == nil,
               "R8.3.3 N+1 response uses the formal Runtime authorization")

        let nextOutputIdentity = RealtimeBrainEventIdentity(
            session: nextIdentity,
            turnID: nextTurnID,
            responseID: nextResponseID,
            contextRevision: stack.target.contextRevision
        )
        let nextOutputEvents = [
            RealtimeResidentBrainEvent(
                identity: nextOutputIdentity,
                sequence: 2,
                kind: .residentTextDelta("N+1")
            ),
            RealtimeResidentBrainEvent(
                identity: nextOutputIdentity,
                sequence: 3,
                kind: .residentSpeakingStarted
            ),
            RealtimeResidentBrainEvent(
                identity: nextOutputIdentity,
                sequence: 4,
                kind: .residentAudioDelta(audioDelta(sequence: 1))
            ),
            RealtimeResidentBrainEvent(
                identity: nextOutputIdentity,
                sequence: 5,
                kind: .residentTextFinal("N+1 survives stale output")
            ),
            RealtimeResidentBrainEvent(
                identity: nextOutputIdentity,
                sequence: 6,
                kind: .residentSpeakingStopped
            )
        ]
        for (index, event) in nextOutputEvents.enumerated() {
            let interleavedOld = oldGenerationOutputEvents(
                stack: stack,
                cycles: 1,
                sequenceBase: UInt64(80 + index * 20)
            )
            for staleEvent in interleavedOld {
                await stack.provider.enqueue(staleEvent)
            }
            staleEventsInjected += interleavedOld.count
            await stack.provider.enqueue(event)
        }
        let finalInterleavedOld = oldGenerationOutputEvents(
            stack: stack,
            cycles: 1,
            sequenceBase: 200
        )
        for event in finalInterleavedOld {
            await stack.provider.enqueue(event)
        }
        staleEventsInjected += finalInterleavedOld.count
        let expectedInterleavedOldReturned = oldReturnedBaseline
            + staleEventsInjected
        await waitUntil("R8.3.3 interleaved N and N+1 output drains") {
            await stack.controller.refreshMicrophoneAuthorization()
            let output = await stack.controller
                .realtimeBrainOutputBridgeSnapshot
            let returnedOldEvents = await stack.provider
                .returnedEventCount(eventSession: baselineIdentity)
            return output.acceptedEventCount
                    == preclearOutput.acceptedEventCount + 7
                && output.completedResponseCount
                    == preclearOutput.completedResponseCount + 1
                && returnedOldEvents == expectedInterleavedOldReturned
        }
        expect(stack.outputPlayer.startCount
                == baselinePlayerStartCount + 1,
               "R8.3.3 N+1 PCM starts Playback exactly once")
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil("R8.3.3 N+1 Playback completes") {
            let playback = await stack.outputHost.currentSnapshot()
            let route = await stack.controller
                .formalSpeechRouteDebugSnapshot
            return playback.playbackCompletedCount
                    == preclearPlayback.playbackCompletedCount + 1
                && route.phase == .listening
        }

        let postPlaybackOldEvents = oldGenerationOutputEvents(
            stack: stack,
            cycles: 2,
            sequenceBase: 240
        )
        for event in postPlaybackOldEvents {
            await stack.provider.enqueue(event)
        }
        staleEventsInjected += postPlaybackOldEvents.count
        let expectedFinalOldReturned = oldReturnedBaseline
            + staleEventsInjected
        await waitUntil("R8.3.3 post-N+1 stale replay drains") {
            await stack.provider.returnedEventCount(
                eventSession: baselineIdentity
            ) == expectedFinalOldReturned
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let finalInput = stack.controller.realtimeBrainInputBridgeSnapshot
        let finalOutput = stack.controller.realtimeBrainOutputBridgeSnapshot
        let finalPlayback = await stack.outputHost.currentSnapshot()
        guard let finalLease = stack.runtime.activeBrainLeaseForTesting(),
              case .realtimeResidentBrain(let finalGeneration) =
                finalLease.generation else {
            fatalError("R8.3.3 N+1 lease missing")
        }
        let providerInterrupts = await stack.provider.interruptCount()
            - baselineInterruptCount
        let providerCancels = await stack.provider.cancelCount()
            - baselineCancelCount
        let hostClears = stack.outputPlayer.clearScheduledPlaybackCount
            - baselineClearCount
        let generationDelta = Int(
            finalGeneration - baselineIdentity.generation
        )
        let expectedAcceptedEvents = 1 + 1 + nextOutputEvents.count
        let actualAcceptedEvents = Int(
            finalOutput.acceptedEventCount
                - preclearOutput.acceptedEventCount
        )
        let oldOutputAccepted = max(
            0,
            actualAcceptedEvents - expectedAcceptedEvents
        )
        let staleEventsReturned = await stack.provider.returnedEventCount(
            eventSession: baselineIdentity
        ) - oldReturnedBaseline
        let dialogueAfter = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeAfter = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipAfter = stack.runtime.currentRelationshipState

        r833StaleEventsInjected = staleEventsInjected
        r833StaleEventsReturned = staleEventsReturned
        r833OldOutputAcceptedAfterFence = oldOutputAccepted
        r833OldCallbacksRejected = finalPlayback.rejectedCallbackCount
            - preclearPlayback.rejectedCallbackCount
        r833ExtraInterruptions = max(0, providerInterrupts - 1)
        r833ExtraPlaybackClears = max(0, hostClears - 1)
        r833ExtraGenerationChanges = max(0, generationDelta - 1)
        r833NPlusOneInputRebound = finalInput.hasActivePump
                && reboundFrames.count == reboundPacketCount
                && reboundFrames.allSatisfy { $0.identity == nextIdentity }
            ? 1 : 0
        r833NPlusOneOutputRebound = finalOutput.hasActiveReceiveLoop
                && actualAcceptedEvents == expectedAcceptedEvents
            ? 1 : 0
        r833NPlusOnePlayback = stack.outputPlayer.startCount
                    == baselinePlayerStartCount + 1
                && finalPlayback.enqueuedChunkCount
                    == preclearPlayback.enqueuedChunkCount + 1
                && finalPlayback.playedChunkCount
                    == preclearPlayback.playedChunkCount + 1
                && finalPlayback.playbackCompletedCount
                    == preclearPlayback.playbackCompletedCount + 1
            ? 1 : 0
        r833NPlusOneListening =
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                == .listening ? 1 : 0

        expect(staleEventsInjected == 110,
               "R8.3.3 exercises a 110-event stale generation burst")
        expect(staleEventsReturned == staleEventsInjected,
               "R8.3.3 every injected old event reaches the generation fence")
        expect(oldOutputAccepted == 0,
               "R8.3.3 accepts zero generation N output after the fence")
        expect(r833OldGenerationAudioPlayed == 0,
               "R8.3.3 plays zero old-generation audio after clear")
        expect(r833OldPlaybackRestarts == 0,
               "R8.3.3 performs zero old-generation Playback restarts")
        expect(r833OldTextResurrections == 0,
               "R8.3.3 performs zero old text or subtitle resurrection")
        expect(r833OldCallbacksRejected == 2,
               "R8.3.3 rejects both scheduled generation N callbacks")
        expect(providerInterrupts == 1 && providerCancels == 0,
               "R8.3.3 has one interrupt and zero separate cancels")
        expect(hostClears == 1,
               "R8.3.3 Host clear remains exactly once")
        expect(generationDelta == 1
                && finalPlayback.generation
                    == preclearPlayback.generation + 1,
               "R8.3.3 Runtime and Playback generations advance once")
        expect(r833ExtraInterruptions == 0
                && r833ExtraPlaybackClears == 0
                && r833ExtraGenerationChanges == 0,
               "R8.3.3 duplicate old events have zero extra side effects")
        expect(r833NPlusOneInputRebound == 1,
               "R8.3.3 N+1 production Input remains functional")
        expect(r833NPlusOneOutputRebound == 1,
               "R8.3.3 N+1 formal Output remains functional")
        expect(r833NPlusOnePlayback == 1,
               "R8.3.3 N+1 PCM plays and completes normally")
        expect(r833NPlusOneListening == 1,
               "R8.3.3 N+1 returns to Listening")
        expect(finalLease.residentID == baselineLease.residentID
                && finalLease.runtimeSessionID
                    == baselineLease.runtimeSessionID
                && finalLease.brainLeaseID == baselineLease.brainLeaseID
                && finalLease.routeEpoch == baselineLease.routeEpoch,
               "R8.3.3 preserves resident, session, lease, and epoch")
        let finalOpenCount = await stack.provider.openCount()
        let finalCloseCount = await stack.provider.closeCount()
        expect(finalOpenCount == baselineOpenCount
                && finalCloseCount == baselineCloseCount,
               "R8.3.3 reuses the existing Provider session")
        expect(dialogueAfter == dialogueBefore
                && narrativeAfter == narrativeBefore
                && relationshipAfter == relationshipBefore,
               "R8.3.3 stale output writes no History, Memory, or Relationship")
        expect(stack.controller.realtimeSpeechSubtitleSnapshot
                == baselineSubtitle,
               "R8.3.3 N output never resurrects subtitle state")
        try await close(stack)
    }

    private static func testR832ConfirmedInterruptionProductionChain(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        await stack.controller.refreshMicrophoneAuthorization()
        guard let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        else {
            fatalError("R8.3.2 active Brain lease missing")
        }
        let baselineIdentity = stack.session
        let nextIdentity = RealtimeBrainSessionIdentity(
            residentID: baselineIdentity.residentID,
            runtimeSessionID: baselineIdentity.runtimeSessionID,
            brainLeaseID: baselineIdentity.brainLeaseID,
            routeEpoch: baselineIdentity.routeEpoch,
            generation: baselineIdentity.generation + 1
        )
        let baselineInput = stack.controller.realtimeBrainInputBridgeSnapshot
        let baselineOutput = stack.controller.realtimeBrainOutputBridgeSnapshot
        let baselinePlayback = stack.controller.speechAudioOutputHostSnapshot
        let baselineOpenCount = await stack.provider.openCount()
        let baselineCloseCount = await stack.provider.closeCount()
        let baselineCreateCount = await stack.provider.createCount()
        let baselineInterruptCount = await stack.provider.interruptCount()
        let baselineCancelCount = await stack.provider.cancelCount()
        let baselineClearCount =
            stack.outputPlayer.clearScheduledPlaybackCount
        let baselinePlayerStartCount = stack.outputPlayer.startCount
        let runtimeRecordCountBefore = stack.runtime
            .realtimeAcousticObservationDebugSnapshot().records.count
        let runtimeEvidenceBefore = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState

        let emittedPacketCount = try await
            submitTrueNearEndThroughProductionChain(stack: stack)
        await waitUntil("R8.3.2 production near-end reaches Bridge") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller.realtimeBrainInputBridgeSnapshot
                .forwardedFrameCount
                >= baselineInput.forwardedFrameCount + emittedPacketCount
        }
        await waitUntilOnMainActor("R8.3.2 acoustic evidence is atomic") {
            let evidence = stack.runtime
                .realtimeInterruptionEvidenceDebugSnapshot()
            return evidence.session == baselineIdentity
                && evidence.hasAcousticEvidence
                && !evidence.hasSemanticEvidence
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let acousticInput = stack.controller.realtimeBrainInputBridgeSnapshot
        let acousticEligibility = Int(
            acousticInput.acousticEvidenceCount
                &- baselineInput.acousticEvidenceCount
        )
        let acceptedNearEndRecords = stack.runtime
            .realtimeAcousticObservationDebugSnapshot()
            .records.dropFirst(runtimeRecordCountBefore)
            .filter { record in
                record.observation.classification == .nearEndCandidate
                    && record.disposition == .observed
            }
        let runtimeEvidenceAfterAcoustic = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
        let runtimeNearEndObservations = acceptedNearEndRecords.filter {
            record in
            record.observation.identity.sequence
                == runtimeEvidenceAfterAcoustic.lastAcousticSequence
                && record.observation.identity.timestampNanoseconds
                    == runtimeEvidenceAfterAcoustic
                        .lastAcousticTimestampNanoseconds
        }.count
        let runtimeAcousticEvidence =
            !runtimeEvidenceBefore.hasAcousticEvidence
            && runtimeEvidenceAfterAcoustic.hasAcousticEvidence
            && !runtimeEvidenceAfterAcoustic.hasSemanticEvidence
            && runtimeEvidenceAfterAcoustic.session == baselineIdentity
        expect(acousticEligibility == 1,
               "R8.3.2 true near-end creates one production eligibility")
        expect(runtimeNearEndObservations == 1,
               "R8.3.2 Runtime observes one exact production near-end")
        expect(runtimeAcousticEvidence,
               "R8.3.2 Runtime records one exact acoustic evidence")
        expect(await stack.provider.interruptCount() == baselineInterruptCount,
               "R8.3.2 acoustic-only phase has no Provider interrupt")
        expect(await stack.provider.cancelCount() == baselineCancelCount,
               "R8.3.2 acoustic-only phase has no Provider cancel")
        expect(
            stack.outputPlayer.clearScheduledPlaybackCount
                == baselineClearCount,
            "R8.3.2 acoustic-only phase has no Playback clear"
        )
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "R8.3.2 acoustic-only phase preserves generation and lease")

        await stack.provider.holdInterrupt()
        try await submitSemanticProposal(stack: stack, sequence: 4)
        await waitUntil("R8.3.2 clear precedes held Provider settlement") {
            await stack.provider.isInterruptHeld()
                && stack.outputPlayer.clearScheduledPlaybackCount
                    == baselineClearCount + 1
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let heldInput = stack.controller.realtimeBrainInputBridgeSnapshot
        let heldOutput = stack.controller.realtimeBrainOutputBridgeSnapshot
        let heldPlayback = stack.controller.speechAudioOutputHostSnapshot
        let semanticEvidence = Int(
            heldOutput.acceptedEventCount
                &- baselineOutput.acceptedEventCount
        )
        expect(semanticEvidence == 1,
               "R8.3.2 formal Provider proposal is accepted exactly once")
        expect(!heldInput.hasActivePump,
               "R8.3.2 Input Bridge is fenced during confirmation")
        expect(!heldOutput.hasActiveReceiveLoop,
               "R8.3.2 Output Bridge is fenced during confirmation")
        expect(heldPlayback.state == .prepared,
               "R8.3.2 confirmed command clears old Playback")
        expect(heldPlayback.queueDepth == 0
                && heldPlayback.scheduledChunkCount == 0,
               "R8.3.2 clear removes queued and scheduled old audio")
        expect(heldPlayback.generation == baselinePlayback.generation + 1,
               "R8.3.2 clear advances Playback generation once")
        expect(
            stack.controller.formalSpeechRouteDebugSnapshot.generation
                == baselineIdentity.generation,
            "R8.3.2 Host does not publish N+1 before Provider ACK"
        )
        expect(stack.runtime.activeBrainLeaseForTesting() == baselineLease,
               "R8.3.2 Runtime does not settle N+1 before Provider ACK")
        expect(stack.capture.isStarted,
               "R8.3.2 confirmation keeps persistent Capture alive")
        expect(await stack.provider.interruptCount()
                == baselineInterruptCount + 1,
               "R8.3.2 sends one canonical Provider interrupt")
        expect(await stack.provider.cancelCount() == baselineCancelCount,
               "R8.3.2 does not call the separate cancelGeneration API")

        let injectedOldOutputEvents = [
            semanticProposal(stack: stack, sequence: 4),
            RealtimeResidentBrainEvent(
                identity: eventIdentity(stack.target),
                sequence: 5,
                kind: .residentAudioDelta(audioDelta(sequence: 2))
            )
        ]
        for event in injectedOldOutputEvents {
            await stack.provider.enqueue(event)
        }
        await stack.provider.releaseInterrupt()

        await waitUntilOnMainActor("R8.3.2 generation and Bridge rebound") {
            let lease = stack.runtime.activeBrainLeaseForTesting()
            let route = stack.controller.formalSpeechRouteDebugSnapshot
            return lease?.generation
                    == .realtimeResidentBrain(nextIdentity.generation)
                && route.phase == .listening
                && route.generation == nextIdentity.generation
                && stack.controller.realtimeBrainInputBridgeSnapshot
                    .hasActivePump
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop
        }
        await waitUntil("R8.3.2 Output Bridge receives on N+1") {
            await stack.provider.receiveCount(session: nextIdentity) > 0
        }
        await waitUntil("R8.3.2 old generation events are rejected") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller.realtimeBrainOutputBridgeSnapshot
                .rejectedEventCount >= heldOutput.rejectedEventCount + 2
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let settledOutput = stack.controller.realtimeBrainOutputBridgeSnapshot
        let oldGenerationEventsRejected = Int(
            settledOutput.rejectedEventCount
                &- heldOutput.rejectedEventCount
        )

        let reboundAudioBaseline = await stack.provider.audioFrameCount()
        let reboundPacketCount = try
            submitPostInterruptionInputThroughProductionChain(stack: stack)
        await waitUntil("R8.3.2 Input Bridge forwards on N+1") {
            await stack.provider.audioFrameCount()
                >= reboundAudioBaseline + reboundPacketCount
        }
        let reboundFrames = await stack.provider.audioFrames(
            after: reboundAudioBaseline
        )
        expect(reboundFrames.count == reboundPacketCount,
               "R8.3.2 rebound forwards only the new production PCM")
        expect(reboundFrames.allSatisfy { $0.identity == nextIdentity },
               "R8.3.2 rebound PCM carries exact generation N+1")
        expect(reboundFrames.first?.sequence == 1
                && reboundFrames.enumerated().allSatisfy { index, frame in
                    frame.sequence == UInt64(index + 1)
                },
               "R8.3.2 rebound resets submitted PCM sequence at one")
        expect(reboundFrames.allSatisfy {
            $0.provenance == .acousticEchoProcessed
        }, "R8.3.2 rebound PCM preserves production AEC provenance")

        stack.outputPlayer.completeStoppedChunk()
        await waitUntil("R8.3.2 old Playback callback is fenced") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller.speechAudioOutputHostSnapshot
                .rejectedCallbackCount
                == baselinePlayback.rejectedCallbackCount + 1
        }

        await stack.controller.refreshMicrophoneAuthorization()
        let finalInput = stack.controller.realtimeBrainInputBridgeSnapshot
        let finalOutput = stack.controller.realtimeBrainOutputBridgeSnapshot
        let finalPlayback = stack.controller.speechAudioOutputHostSnapshot
        guard let finalLease = stack.runtime.activeBrainLeaseForTesting()
        else {
            fatalError("R8.3.2 settled Brain lease missing")
        }
        let interruptCommand = await stack.provider.lastInterruptCommand()
        let providerInterrupts = await stack.provider.interruptCount()
            - baselineInterruptCount
        let providerCancels = await stack.provider.cancelCount()
            - baselineCancelCount
        let hostClears = stack.outputPlayer.clearScheduledPlaybackCount
            - baselineClearCount
        let providerReopens = await stack.provider.openCount()
            - baselineOpenCount
        let providerCloses = await stack.provider.closeCount()
            - baselineCloseCount
        let responseCreates = await stack.provider.createCount()
            - baselineCreateCount
        guard case .realtimeResidentBrain(let settledGeneration) =
                finalLease.generation else {
            fatalError("R8.3.2 settled route is not Realtime Resident Brain")
        }
        let generationDelta = Int(
            settledGeneration - baselineIdentity.generation
        )
        let playbackGenerationDelta = Int(
            finalPlayback.generation - baselinePlayback.generation
        )
        let dialogueAfter = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeAfter = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipAfter = stack.runtime.currentRelationshipState
        let historyWrites = dialogueAfter == dialogueBefore ? 0 : 1
        let memoryWrites = narrativeAfter == narrativeBefore ? 0 : 1
        let relationshipChanges = relationshipAfter == relationshipBefore
            ? 0 : 1
        let nextReceiveCount = await stack.provider.receiveCount(
            session: nextIdentity
        )

        r832ProductionAcousticEligibility = acousticEligibility
        r832RuntimeNearEndObservations = runtimeNearEndObservations
        r832RuntimeAcousticEvidence = runtimeAcousticEvidence ? 1 : 0
        r832FormalSemanticEvidence = semanticEvidence
        r832ConfirmedInterruptions = providerInterrupts == 1
                && hostClears == 1 && generationDelta == 1 ? 1 : 0
        r832ProviderInterrupts = providerInterrupts
        r832ProviderCancels = providerCancels
        r832HostPlaybackClears = hostClears
        r832PlaybackGenerationDelta = playbackGenerationDelta
        r832GenerationDelta = generationDelta
        r832GenerationBefore = baselineIdentity.generation
        r832GenerationAfter = settledGeneration
        r832ResidentIDChanges = finalLease.residentID
            == baselineLease.residentID ? 0 : 1
        r832RuntimeSessionIDChanges = finalLease.runtimeSessionID
            == baselineLease.runtimeSessionID ? 0 : 1
        r832BrainLeaseIDChanges = finalLease.brainLeaseID
            == baselineLease.brainLeaseID ? 0 : 1
        r832RouteEpochChanges = finalLease.routeEpoch
            == baselineLease.routeEpoch ? 0 : 1
        r832ProviderReopens = providerReopens
        r832ProviderCloses = providerCloses
        r832ResponseCreates = responseCreates
        r832InputBridgeRebound = finalInput.hasActivePump
                && finalInput.lastError == nil
                && reboundFrames.count == reboundPacketCount
                && reboundFrames.allSatisfy { $0.identity == nextIdentity }
                && reboundFrames.first?.sequence == 1
            ? 1 : 0
        r832OutputBridgeRebound = finalOutput.hasActiveReceiveLoop
                && nextReceiveCount > 0
            ? 1 : 0
        r832RouteListening =
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                == .listening ? 1 : 0
        r832CapturePersistent = stack.capture.isStarted ? 1 : 0
        r832InjectedOldOutputEventsRejected = oldGenerationEventsRejected
        r832OldPlaybackCallbacksRejected = finalPlayback
            .rejectedCallbackCount - baselinePlayback.rejectedCallbackCount
        r832ExtraInterruptions = max(0, providerInterrupts - 1)
        r832ExtraPlaybackClears = max(0, hostClears - 1)
        r832FalseUserTurns = responseCreates
        r832FalseHistoryWrites = historyWrites
        r832FalseMemoryWrites = memoryWrites
        r832RelationshipChanges = relationshipChanges

        expect(interruptCommand?.identity == baselineIdentity,
               "R8.3.2 Provider interrupt targets generation N")
        expect(interruptCommand?.nextGeneration == nextIdentity.generation,
               "R8.3.2 Provider interrupt carries generation N+1")
        expect(interruptCommand?.reason == .runtimeDecision,
               "R8.3.2 Provider interrupt remains Runtime-authorized")
        expect(providerInterrupts == 1,
               "R8.3.2 canonical Provider interrupt is exactly once")
        expect(providerCancels == 0,
               "R8.3.2 separate Provider cancelGeneration remains zero")
        expect(hostClears == 1,
               "R8.3.2 Host Playback clear is exactly once")
        expect(generationDelta == 1,
               "R8.3.2 Runtime generation advances exactly N to N+1")
        expect(playbackGenerationDelta == 1,
               "R8.3.2 Playback generation advances exactly once")
        expect(finalLease.residentID == baselineLease.residentID
                && finalLease.runtimeSessionID
                    == baselineLease.runtimeSessionID
                && finalLease.brainLeaseID == baselineLease.brainLeaseID
                && finalLease.routeEpoch == baselineLease.routeEpoch,
               "R8.3.2 preserves resident, session, lease, and epoch")
        expect(providerReopens == 0 && providerCloses == 0,
               "R8.3.2 reuses the existing Provider session")
        expect(responseCreates == 0,
               "R8.3.2 proposal does not create a new response")
        expect(r832InputBridgeRebound == 1,
               "R8.3.2 Input Bridge is rebound before N+1 Listening")
        expect(r832OutputBridgeRebound == 1,
               "R8.3.2 Output Bridge receives on generation N+1")
        expect(r832RouteListening == 1 && r832CapturePersistent == 1,
               "R8.3.2 settles to Listening with persistent Capture")
        expect(oldGenerationEventsRejected == injectedOldOutputEvents.count,
               "R8.3.2 duplicate proposal and late audio stay stale")
        expect(r832OldPlaybackCallbacksRejected == 1,
               "R8.3.2 old Playback completion stays stale")
        expect(finalOutput.acceptedEventCount
                == baselineOutput.acceptedEventCount + 1,
               "R8.3.2 stale old events never reach the Host consumer")
        expect(stack.outputPlayer.startCount == baselinePlayerStartCount
                && finalPlayback.enqueuedChunkCount
                    == baselinePlayback.enqueuedChunkCount,
               "R8.3.2 stale old audio never restarts Playback")
        expect(r832ExtraInterruptions == 0
                && r832ExtraPlaybackClears == 0,
               "R8.3.2 duplicate and late events have zero side effects")
        expect(historyWrites == 0 && memoryWrites == 0
                && relationshipChanges == 0,
               "R8.3.2 writes no History, Memory, or Relationship state")
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
        await stack.provider.enqueue(
            semanticProposal(stack: stack, sequence: sequence)
        )
        try? await Task.sleep(for: .milliseconds(80))
    }

    private static func semanticProposal(
        stack: R823ControllerStack,
        sequence: UInt64
    ) -> RealtimeResidentBrainEvent {
        let identity = RealtimeBrainEventIdentity(
            session: stack.target.session,
            turnID: stack.target.turnID,
            responseID: stack.target.responseID,
            contextRevision: stack.target.contextRevision
        )
        return RealtimeResidentBrainEvent(
            identity: identity,
            sequence: sequence,
            kind: .interruptionProposed(RealtimeBrainInterruptionProposal(
                identity: identity,
                reason: "user_speech_started_during_resident_response"
            ))
        )
    }

    private static func oldGenerationOutputEvents(
        stack: R823ControllerStack,
        cycles: Int,
        sequenceBase: UInt64
    ) -> [RealtimeResidentBrainEvent] {
        let identity = eventIdentity(stack.target)
        var events: [RealtimeResidentBrainEvent] = []
        events.reserveCapacity(cycles * 10)
        for cycle in 0 ..< cycles {
            let sequence = sequenceBase + UInt64(cycle * 10)
            events.append(semanticProposal(stack: stack, sequence: 7))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 1,
                kind: .residentAudioDelta(audioDelta(
                    sequence: UInt64(100 + cycle)
                ))
            ))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 2,
                kind: .residentTextDelta("stale resident text delta")
            ))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 3,
                kind: .residentTextFinal("stale resident text final")
            ))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 4,
                kind: .residentSpeakingStarted
            ))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 5,
                kind: .residentSpeakingStopped
            ))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 6,
                kind: .residentSemanticFinal(
                    RealtimeBrainSemanticOutput(
                        canonicalText: "stale resident completion"
                    )
                )
            ))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 7,
                kind: .error(.providerFailure)
            ))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 8,
                kind: .cancelled(.interrupted)
            ))
            events.append(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: sequence + 9,
                kind: .sessionClosed
            ))
        }
        return events
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

    private static func submitPostInterruptionInputThroughProductionChain(
        stack: R823ControllerStack
    ) throws -> Int {
        // The real audio device closes AEC playback on clear; the fake player
        // has no capture-device lifecycle hook, so mirror that device effect.
        stack.acousticEchoHost.playbackStopped()
        let nearEnd = signal(seed: 23, amplitude: 0.18)
        stack.aecBackend.setCaptureOutput(nearEnd)
        var processedFrameCount = 0
        var packetCount = 0
        var activePacketCount = 0
        for _ in 0 ..< 4 {
            let processed = stack.acousticEchoHost.processCapture(
                nearEnd,
                hostTimeNanoseconds: monotonicNow()
            )
            if processed.count
                    == MacSpeechAcousticEchoHost.frameSampleCount {
                processedFrameCount += 1
            }
            let emission = try stack.capture.emit(
                processedSamples: processed
            )
            packetCount += emission.packetCount
            activePacketCount += emission.activePacketCount
        }
        expect(processedFrameCount == 4,
               "R8.3.2 rebound input passes through production AEC Host")
        expect(packetCount > 0,
               "R8.3.2 rebound input reaches production PCM conversion")
        expect(activePacketCount > 0,
               "R8.3.2 rebound production PCM remains active")
        return packetCount
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
            outputHost: outputHost,
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
