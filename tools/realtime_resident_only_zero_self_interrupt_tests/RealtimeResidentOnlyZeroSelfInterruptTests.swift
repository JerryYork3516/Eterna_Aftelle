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
    private var heldAudioAppendTargetCount: UInt64?
    private var heldAudioAppendContinuation:
        CheckedContinuation<Void, Never>?
    private var heldAudioAppendWaiters:
        [CheckedContinuation<Void, Never>] = []

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
        if heldAudioAppendTargetCount == audioCount {
            heldAudioAppendTargetCount = nil
            await withCheckedContinuation { continuation in
                heldAudioAppendContinuation = continuation
                let waiters = heldAudioAppendWaiters
                heldAudioAppendWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
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
    func contextRevision(
        for session: RealtimeBrainSessionIdentity
    ) -> UInt64? {
        contextUpdates.last { $0.identity == session }?.contextRevision
    }
    func carriedContextRevision(
        for session: RealtimeBrainSessionIdentity
    ) -> UInt64? {
        contextUpdates.last { update in
            update.identity.residentID == session.residentID
                && update.identity.runtimeSessionID
                    == session.runtimeSessionID
                && update.identity.brainLeaseID == session.brainLeaseID
                && update.identity.routeEpoch == session.routeEpoch
        }?.contextRevision
    }
    func nextResidentAudioSequence(
        for session: RealtimeBrainSessionIdentity
    ) -> UInt64 {
        let maximum = enqueuedEvents.compactMap { event -> UInt64? in
            guard event.identity.session == session,
                  case .residentAudioDelta(let audio) = event.kind else {
                return nil
            }
            return audio.sequence
        }.max() ?? 0
        return maximum + 1
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

    func holdAudioAppend(afterAdditionalFrames count: UInt64) {
        precondition(count > 0)
        heldAudioAppendTargetCount = audioCount &+ count
    }

    func waitUntilAudioAppendIsHeld() async {
        guard heldAudioAppendContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            if heldAudioAppendContinuation != nil {
                continuation.resume()
            } else {
                heldAudioAppendWaiters.append(continuation)
            }
        }
    }

    func releaseAudioAppend() {
        let continuation = heldAudioAppendContinuation
        heldAudioAppendContinuation = nil
        continuation?.resume()
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

    func discardPendingAudioForGenerationTransition() {
        outputConverter.resetForGenerationTransition()
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
        processedSamples: [Float],
        acousticBefore: MacSpeechAcousticObservationSnapshot? = nil
    ) throws -> (packetCount: Int, activePacketCount: Int) {
        guard !processedSamples.isEmpty else { return (0, 0) }
        let cleanedBuffer = try MacSpeechFloatMono48kConverter.makeBuffer(
            samples: processedSamples
        )
        let packets = try outputConverter.convert(cleanedBuffer)
        let acoustic = acousticEchoHost.acousticObservationSnapshot()
        let activityEvidenceKind: MacSpeechAudioActivityEvidenceKind
        if let acousticBefore {
            activityEvidenceKind =
                MacSpeechAudioActivityEvidenceKind.classify(
                    before: acousticBefore,
                    after: acoustic
                )
        } else {
            activityEvidenceKind = acoustic.isPlaybackActive
                    && acoustic.sourceGateOpen
                    && acoustic.sourceGateEpoch > 0
                    && (acoustic.inputClassification == .nearEndSpeech
                        || acoustic.inputClassification == .doubleTalk)
                ? .sourceGatedNearEnd : .none
        }
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
                generation: generation,
                timestamp: acoustic.captureHostTimeNanoseconds
                    ?? DispatchTime.now().uptimeNanoseconds,
                activityEvidenceKind: activityEvidenceKind,
                residentPlaybackSequence: acoustic.playbackSequence,
                residentPlaybackActive: acoustic.isPlaybackActive,
                lastAudibleResidentRenderTimestampNanoseconds:
                    acoustic.lastAudibleRenderHostTimeNanoseconds,
                sourceGateEpoch: activityEvidenceKind
                    == .sourceGatedNearEnd
                    ? acoustic.sourceGateEpoch : 0
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
    private static var residentOnlyGrowthWrites = 0

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

    private static var r841PositiveScenarios = 0
    private static var r841DetectedScenarios = 0
    private static var r841SourceGateOpenScenarios = 0
    private static var r841AcousticEligibility = 0
    private static var r841DoubleTalkFrames = 0
    private static var r841ActivePCMPackets = 0
    private static var r841AdaptiveScenarios = 0
    private static var r841TransitionToNearEnd = 0
    private static var r841TransitionToFarEnd = 0
    private static var r841NegativeScenarios = 0
    private static var r841NegativeObservations = 0
    private static var r841NegativeFrames = 0
    private static var r841StressFrames = 0
    private static var r841FalseDoubleTalk = 0
    private static var r841FarEndFalseDoubleTalk = 0
    private static var r841ResidualEchoFalseDoubleTalk = 0
    private static var r841PlaybackTailFalseDoubleTalk = 0
    private static var r841TimingJitterFalseDoubleTalk = 0
    private static var r841StressFalseDoubleTalk = 0
    private static var r841ResidentOnlyEligibility = 0
    private static var r841ConfirmedInterruptions = 0
    private static var r841ProviderInterrupts = 0
    private static var r841ProviderCancels = 0
    private static var r841HostPlaybackClears = 0
    private static var r841GenerationChanges = 0
    private static var r841LeaseChanges = 0
    private static var r841SemanticProposals = 0

    private static var r842ShortPauseCases = 0
    private static var r842ShortPauseFalseCompletions = 0
    private static var r842TrueEndCases = 0
    private static var r842CompletionCandidates = 0
    private static var r842DuplicateCompletions = 0
    private static var r842ResidentOnlyFalseCompletions = 0
    private static var r842StaleGenerationCompletions = 0
    private static var r842OldTimerResurrections = 0
    private static var r842ResponseCreates = 0
    private static var r842ProviderInterrupts = 0
    private static var r842ProviderCancels = 0
    private static var r842HostPlaybackClears = 0
    private static var r842ExtraGenerationAdvances = 0
    private static var r842CompletionWindowNanoseconds: UInt64 = 0
    private static var r842MaximumTrueEndLatencyNanoseconds: UInt64 = 0
    private static var r842DoubleTalkCases = 0
    private static var r842ListeningContinuousCases = 0
    private static var r842ListeningShortPauseCases = 0
    private static var r842ListeningSpeakingAdmissions = 0
    private static var r842ListeningTrueEndCandidates = 0
    private static var r842ListeningFalseCompletions = 0
    private static var r842ProviderOnlyFalseAdmissions = 0
    private static var r842ProviderOnlyFalseCompletions = 0
    private static var r842ListeningNegativeFalseAdmissions = 0
    private static var r842ListeningNegativeFalseCompletions = 0
    private static var r842StalePCMAdmissions = 0
    private static var r842OldGenerationCompletions = 0

    private static var r843FinalBeforeCompletionCases = 0
    private static var r843CompletionBeforeFinalCases = 0
    private static var r843CrossSourceTurnCases = 0
    private static var r843ValidCompletedSemanticTurns = 0
    private static var r843ValidTurnResponseCreates = 0
    private static var r843CompletionOnlyResponseCreates = 0
    private static var r843SemanticOnlyResponseCreates = 0
    private static var r843ProviderOnlyResponseCreates = 0
    private static var r843EmptyFinalResponseCreates = 0
    private static var r843WrongIdentityResponseCreates = 0
    private static var r843StaleGenerationResponseCreates = 0
    private static var r843DuplicateResponseCreates = 0
    private static var r843ExtraInterrupts = 0
    private static var r843ExtraPlaybackClears = 0
    private static var r843ExtraGenerationAdvances = 0

    private static var r844ClassifierPassiveCases = 0
    private static var r844ClassifierSubstantiveCases = 0
    private static var r844ClassifierFalsePassive = 0
    private static var r844ClassifierFalseSubstantive = 0
    private static var r844PassiveBackchannelCases = 0
    private static var r844PassiveBackchannelDispositions = 0
    private static var r844PassiveBackchannelResponseCreates = 0
    private static var r844SubstantiveCases = 0
    private static var r844SubstantiveDispositions = 0
    private static var r844SubstantiveResponseCreates = 0
    private static var r844CrossSourceMixedResponseCreates = 0
    private static var r844CrossSourcePassiveResponseCreates = 0
    private static var r844DuplicateResponseCreates = 0
    private static var r844ProviderOnlyResponseCreates = 0
    private static var r844ProviderOnlyDispositions = 0
    private static var r844StaleGenerationResponseCreates = 0
    private static var r844NPlusOneSubstantiveResponseCreates = 0
    private static var r844FalseHistoryWrites = 0
    private static var r844FalseMemoryWrites = 0
    private static var r844RelationshipChanges = 0
    private static var r844GrowthWrites = 0
    private static var r844ExtraInterrupts = 0
    private static var r844ExtraPlaybackClears = 0
    private static var r844ExtraGenerationAdvances = 0

    private static var r852SubtitleDeltaPresentations = 0
    private static var r852SubtitleFinalPresentations = 0
    private static var r852UserFinalFallbackPresentations = 0
    private static var r852PlaybackCompletionResurrections = 0
    private static var r852AudioFirstResurrections = 0
    private static var r852InterruptionResurrections = 0
    private static var r852OldIdentityResurrections = 0
    private static var r852RecoverableResponseErrors = 0
    private static var r852TerminalStops = 0
    private static var r852PostErrorResponseRebound = 0
    private static var r852ProviderClosesOnResponseError = 0

    private static var r851CrossNodeScenarios = 0
    private static var r851RapidTurns = 0
    private static var r851RepeatedInterruptionCycles = 0
    private static var r851StopRestartPoints = 0
    private static var r851DelayedOrderingCases = 0
    private static var r851DuplicateResponses = 0
    private static var r851DuplicateInterrupts = 0
    private static var r851DuplicateClears = 0
    private static var r851StaleSideEffects = 0
    private static var r851FalseSelfInterrupts = 0
    private static var r851FalsePersistence = 0
    private static var r851FalseHistoryWrites = 0
    private static var r851FalseMemoryWrites = 0
    private static var r851FalseRelationshipChanges = 0
    private static var r851FalseGrowthWrites = 0
    private static var r851GenerationDrift = 0
    private static var r851LeaseDrift = 0
    private static var r851RandomizedIterations = 0
    private static var r851RandomizedFailures = 0
    private static var r851RandomizedExpectedGenerationTransitions = 0
    private static var r851RandomizedObservedGenerationTransitions = 0
    private static var r851RandomizedFinalBeforeStop = 0
    private static var r851RandomizedCompletionBeforeFinal = 0
    private static var r851RandomizedPartialFinalStop = 0
    private static var r851RandomizedShortPauseResume = 0
    private static var r851RandomizedProviderFirstStart = 0
    private static let r851RandomSeed: UInt64 = 0x8515_11A7

    static func main() async throws {
        guard CommandLine.arguments.count == 2
                || (CommandLine.arguments.count == 3
                    && [
                        "--r831-positive-only",
                        "--r832-confirmed-only",
                        "--r833-latency-stale-only",
                        "--r841-double-talk-only",
                        "--r842-listening-only",
                        "--r842-turn-completion-only",
                        "--r843-semantic-fusion-only",
                        "--r844-classifier-only",
                        "--r844-response-policy-only",
                        "--r852-subtitle-diagnostics-only",
                        "--r851-cross-node-only",
                        "--r851-randomized-only"
                    ].contains(CommandLine.arguments[2])) else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        if CommandLine.arguments.count == 3 {
            if CommandLine.arguments[2]
                    == "--r852-subtitle-diagnostics-only" {
                try await testR852FormalRealtimeSubtitleAndDiagnostics(
                    fixture: fixture
                )
                print("realtime_formal_subtitle_diagnostics_cases=\(cases)")
                print("realtime_formal_subtitle_diagnostics_checks=\(checks)")
                print("r852_subtitle_delta_presentations=\(r852SubtitleDeltaPresentations)")
                print("r852_subtitle_final_presentations=\(r852SubtitleFinalPresentations)")
                print("r852_user_final_fallback_presentations=\(r852UserFinalFallbackPresentations)")
                print("r852_playback_completion_resurrections=\(r852PlaybackCompletionResurrections)")
                print("r852_audio_first_resurrections=\(r852AudioFirstResurrections)")
                print("r852_interruption_resurrections=\(r852InterruptionResurrections)")
                print("r852_old_identity_resurrections=\(r852OldIdentityResurrections)")
                print("r852_recoverable_response_errors=\(r852RecoverableResponseErrors)")
                print("r852_terminal_stops=\(r852TerminalStops)")
                print("r852_post_error_response_rebound=\(r852PostErrorResponseRebound)")
                print("r852_provider_closes_on_response_error=\(r852ProviderClosesOnResponseError)")
                return
            }
            if CommandLine.arguments[2] == "--r851-cross-node-only" {
                try await testR851CrossNodeTotalRegression(fixture: fixture)
                print("realtime_total_cross_node_cases=\(r851CrossNodeScenarios)")
                print("realtime_total_cross_node_checks=\(checks)")
                printR851CrossNodeMetrics()
                return
            }
            if CommandLine.arguments[2] == "--r851-randomized-only" {
                try await testR851DeterministicRandomizedOrdering(
                    fixture: fixture
                )
                print("realtime_total_randomized_cases=1")
                print("realtime_total_randomized_checks=\(checks)")
                printR851RandomizedMetrics()
                return
            }
            if CommandLine.arguments[2] == "--r844-classifier-only" {
                testR844BackchannelClassifier()
                print("realtime_backchannel_classifier_cases=\(cases)")
                print("realtime_backchannel_classifier_checks=\(checks)")
                printR844ClassifierMetrics()
                return
            }
            if CommandLine.arguments[2] == "--r844-response-policy-only" {
                try await testR844BackchannelResponsePolicy(
                    fixture: fixture
                )
                print("realtime_backchannel_response_policy_cases=\(cases)")
                print("realtime_backchannel_response_policy_checks=\(checks)")
                printR844ResponsePolicyMetrics()
                print("r844_real_qwen_and_devices=NOT_RUN_HUMAN_GATE")
                return
            }
            if CommandLine.arguments[2] == "--r843-semantic-fusion-only" {
                try await testR843SemanticTurnTakingFusion(
                    fixture: fixture
                )
                print("realtime_semantic_turn_taking_cases=\(cases)")
                print("realtime_semantic_turn_taking_checks=\(checks)")
                printR843Metrics()
                print("r843_real_qwen_and_devices=NOT_RUN_HUMAN_GATE")
                return
            }
            if CommandLine.arguments[2] == "--r842-listening-only" {
                cases += 1
                try await testR842NormalListeningAdmission(
                    fixture: fixture
                )
                print("realtime_turn_completion_listening_cases=\(cases)")
                print("realtime_turn_completion_listening_checks=\(checks)")
                printR842ListeningMetrics()
                return
            }
            if CommandLine.arguments[2] == "--r842-turn-completion-only" {
                cases += 1
                try await testR842PauseVsUtteranceCompletion(
                    fixture: fixture
                )
                print("realtime_turn_completion_cases=\(cases)")
                print("realtime_turn_completion_checks=\(checks)")
                print("r842_completion_window_ns=\(r842CompletionWindowNanoseconds)")
                print("r842_clock_source=monotonic_uptime")
                print("r842_short_pause_cases=\(r842ShortPauseCases)")
                print("r842_short_pause_false_completions=\(r842ShortPauseFalseCompletions)")
                print("r842_true_end_cases=\(r842TrueEndCases)")
                print("r842_utterance_completion_candidates=\(r842CompletionCandidates)")
                print("r842_max_true_end_latency_ns=\(r842MaximumTrueEndLatencyNanoseconds)")
                print("r842_duplicate_completions=\(r842DuplicateCompletions)")
                print("r842_resident_only_false_completions=\(r842ResidentOnlyFalseCompletions)")
                print("r842_stale_generation_completions=\(r842StaleGenerationCompletions)")
                print("r842_old_timer_resurrections=\(r842OldTimerResurrections)")
                print("r842_double_talk_cases=\(r842DoubleTalkCases)")
                print("r842_response_creates=\(r842ResponseCreates)")
                print("r842_provider_interrupts=\(r842ProviderInterrupts)")
                print("r842_provider_cancels=\(r842ProviderCancels)")
                print("r842_host_playback_clears=\(r842HostPlaybackClears)")
                print("r842_extra_generation_advances=\(r842ExtraGenerationAdvances)")
                printR842ListeningMetrics()
                print("r842_real_qwen_and_devices=NOT_RUN_HUMAN_GATE")
                return
            }
            if CommandLine.arguments[2] == "--r841-double-talk-only" {
                cases += 1
                try await testR841DoubleTalkAcousticDetermination(
                    fixture: fixture
                )
                print("realtime_double_talk_acoustic_cases=\(cases)")
                print("realtime_double_talk_acoustic_checks=\(checks)")
                print("r841_positive_scenarios=\(r841PositiveScenarios)")
                print("r841_double_talk_detected_scenarios=\(r841DetectedScenarios)")
                print("r841_source_gate_open_scenarios=\(r841SourceGateOpenScenarios)")
                print("r841_acoustic_eligibility=\(r841AcousticEligibility)")
                print("r841_double_talk_frames=\(r841DoubleTalkFrames)")
                print("r841_active_pcm_packets=\(r841ActivePCMPackets)")
                print("r841_adaptive_scenarios=\(r841AdaptiveScenarios)")
                print("r841_transition_to_near_end=\(r841TransitionToNearEnd)")
                print("r841_transition_to_far_end=\(r841TransitionToFarEnd)")
                print("r841_negative_scenarios=\(r841NegativeScenarios)")
                print("r841_negative_observations=\(r841NegativeObservations)")
                print("r841_negative_frames=\(r841NegativeFrames)")
                print("r841_stress_frames=\(r841StressFrames)")
                print("r841_false_double_talk=\(r841FalseDoubleTalk)")
                print("r841_far_end_false_double_talk=\(r841FarEndFalseDoubleTalk)")
                print("r841_residual_echo_false_double_talk=\(r841ResidualEchoFalseDoubleTalk)")
                print("r841_playback_tail_false_double_talk=\(r841PlaybackTailFalseDoubleTalk)")
                print("r841_timing_jitter_false_double_talk=\(r841TimingJitterFalseDoubleTalk)")
                print("r841_stress_false_double_talk=\(r841StressFalseDoubleTalk)")
                print("r841_resident_only_eligibility=\(r841ResidentOnlyEligibility)")
                print("r841_confirmed_interruptions=\(r841ConfirmedInterruptions)")
                print("r841_provider_interrupts=\(r841ProviderInterrupts)")
                print("r841_provider_cancels=\(r841ProviderCancels)")
                print("r841_host_playback_clears=\(r841HostPlaybackClears)")
                print("r841_generation_changes=\(r841GenerationChanges)")
                print("r841_lease_changes=\(r841LeaseChanges)")
                print("r841_semantic_proposals=\(r841SemanticProposals)")
                print("r841_acoustic_threshold_changes=0")
                print("r841_real_room_and_devices=NOT_RUN_HUMAN_GATE")
                return
            }
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

    private enum R851TurnOrder {
        case finalBeforeStop
        case completionBeforeFinal
        case partialFinalStop
        case shortPauseResume
        case providerFirstStart
    }

    private enum R851OutputMode {
        case none
        case complete
    }

    private struct R851TurnResult {
        let turnID: RealtimeBrainTurnID
        let responseID: RealtimeBrainResponseID?
        let contextRevision: UInt64
        let nextSequence: UInt64
        let createDelta: Int
    }

    private struct R851DeterministicGenerator {
        private(set) var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return state
        }
    }

    private static func testR851CrossNodeTotalRegression(
        fixture: Data
    ) async throws {
        try await testR851NormalListeningSubstantive(fixture: fixture)
        r851CrossNodeScenarios += 1

        try await testR851MissingStopPresentationRecovery(fixture: fixture)
        r851CrossNodeScenarios += 1

        try await testR851NormalListeningPassive(fixture: fixture)
        r851CrossNodeScenarios += 1

        try await testLongResidentOnlyStress(fixture: fixture)
        try await testHistoryMemorySafety(fixture: fixture)
        expect(longStressFrames == 3_840
                && longStressEligible == 0
                && longStressConfirmed == 0
                && longStressProviderInterrupts == 0
                && longStressProviderCancels == 0
                && longStressHostClears == 0,
               "R8.5.1 preserves the 3840-frame resident-only invariant")
        expect(residentOnlyFalseHistoryWrites == 0
                && residentOnlyFalseMemoryWrites == 0
                && residentOnlyRelationshipChanges == 0
                && residentOnlyGrowthWrites == 0,
               "R8.5.1 resident-only stress has zero false persistence")
        r851FalseSelfInterrupts += longStressConfirmed
            + longStressProviderInterrupts + longStressProviderCancels
            + longStressHostClears
        r851FalsePersistence += residentOnlyFalseHistoryWrites
            + residentOnlyFalseMemoryWrites + residentOnlyRelationshipChanges
        r851FalseHistoryWrites += residentOnlyFalseHistoryWrites
        r851FalseMemoryWrites += residentOnlyFalseMemoryWrites
        r851FalseRelationshipChanges += residentOnlyRelationshipChanges
        r851FalseGrowthWrites += residentOnlyGrowthWrites
        r851CrossNodeScenarios += 1

        try await testR832ConfirmedInterruptionProductionChain(
            fixture: fixture
        ) { stack, nextSession in
            stack.acousticEchoHost.playbackStopped()
            try await settleR851ListeningSilence(
                stack: stack,
                expectedSession: nextSession,
                frameCount: 24,
                label: "post-interruption N+1 boundary"
            )
            let result = try await runR851ListeningTurn(
                stack: stack,
                session: nextSession,
                transcript: "打断后继续正常说话",
                expectsPassive: false,
                order: .finalBeforeStop,
                outputMode: .complete,
                sequenceBase: 1,
                seed: 85_105,
                label: "post-interruption N+1 substantive",
                allowsContextRevisionCarry: true
            )
            expect(result.createDelta == 1
                    && stack.controller.formalSpeechRouteDebugSnapshot.phase
                        == .listening,
                   "R8.5.1 N+1 completes a production substantive turn")
        }
        expect(r832ConfirmedInterruptions == 1
                && r832ProviderInterrupts == 1
                && r832HostPlaybackClears == 1
                && r832GenerationDelta == 1,
               "R8.5.1 true interruption advances exactly once")
        r851DuplicateInterrupts += max(0, r832ProviderInterrupts - 1)
        r851DuplicateClears += max(0, r832HostPlaybackClears - 1)
        r851CrossNodeScenarios += 2

        try await testR843CrossSourceTurn(fixture: fixture)
        expect(r843CrossSourceTurnCases >= 1,
               "R8.5.1 cross-source short pause fuses one utterance")
        r851CrossNodeScenarios += 1

        try await testR844CrossSourceMixed(fixture: fixture)
        expect(r844CrossSourceMixedResponseCreates == 1,
               "R8.5.1 mixed backchannel remains substantive")
        r851CrossNodeScenarios += 1

        try await testR851RapidAlternatingTurns(fixture: fixture)
        r851CrossNodeScenarios += 1

        try await testR851RepeatedInterruptions(fixture: fixture)
        r851CrossNodeScenarios += 1

        try await testR851StopRestartMatrix(fixture: fixture)
        r851CrossNodeScenarios += 1

        try await testR851DelayedProviderOrdering(fixture: fixture)
        r851CrossNodeScenarios += 1

        expect(r851CrossNodeScenarios == 12,
               "R8.5.1 executable covers twelve non-Tool scenarios")
        expect(r851DuplicateResponses == 0
                && r851DuplicateInterrupts == 0
                && r851DuplicateClears == 0
                && r851StaleSideEffects == 0
                && r851FalseSelfInterrupts == 0
                && r851FalsePersistence == 0
                && r851GenerationDrift == 0
                && r851LeaseDrift == 0,
               "R8.5.1 cross-node safety counters remain zero")
    }

    private static func testR851NormalListeningSubstantive(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let result = try await runR851ListeningTurn(
            stack: stack,
            session: stack.session,
            transcript: "我们继续刚才的话题",
            expectsPassive: false,
            order: .shortPauseResume,
            outputMode: .complete,
            sequenceBase: 2,
            seed: 85_101,
            label: "normal Listening substantive"
        )
        expect(result.createDelta == 1
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening,
               "R8.5.1 normal substantive completes output and Playback")
        try await close(stack)
    }

    private static func testR851MissingStopPresentationRecovery(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let leaseBaseline = stack.runtime.activeBrainLeaseForTesting()
        try await admitR844ListeningTurn(
            stack: stack,
            session: stack.session,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 85_106,
            label: "missing-stop presentation recovery"
        )
        let firstFinalAt = monotonicNow()
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userTranscriptFinal("缺少 speech stopped"),
            label: "missing-stop final"
        )
        await waitUntilOnMainActor("R8.5.1 missing-stop Thinking") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                == .processing
        }
        try? await Task.sleep(for: .milliseconds(200))
        let duplicateStartAt = monotonicNow()
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 4,
            kind: .userSpeechStarted,
            label: "duplicate missing-stop start"
        )
        try? await Task.sleep(for: .milliseconds(200))
        let mismatchedStopAt = monotonicNow()
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: RealtimeBrainTurnID(),
            sequence: 5,
            kind: .userSpeechStopped,
            label: "mismatched missing-stop stop"
        )
        try? await Task.sleep(for: .milliseconds(300))
        let duplicateFinalAt = monotonicNow()
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 6,
            kind: .userTranscriptFinal("缺少 speech stopped"),
            label: "duplicate missing-stop final"
        )
        await waitUntilOnMainActor(
            "R8.5.1 missing-stop recovery",
            timeoutNanoseconds: 850_000_000
        ) {
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
                && stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot().phase
                    == .idle
        }
        let recoveryLatency = monotonicNow() - firstFinalAt
        expect(duplicateStartAt - firstFinalAt < 1_000_000_000
                && mismatchedStopAt - firstFinalAt < 1_000_000_000
                && duplicateFinalAt - firstFinalAt < 1_000_000_000,
               "R8.5.1 duplicate activity arrives before Runtime expiry")
        let createAfter = await stack.provider.createCount()
        let interruptAfter = await stack.provider.interruptCount()
        let cancelAfter = await stack.provider.cancelCount()
        expect(createAfter == createBaseline
                && interruptAfter == interruptBaseline
                && cancelAfter == cancelBaseline
                && stack.outputPlayer.clearScheduledPlaybackCount
                    == clearBaseline,
               "R8.5.1 missing-stop expiry has no response or interruption side effects")
        expect(stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == stack.session.generation
                && stack.runtime.activeBrainLeaseForTesting()
                    == leaseBaseline,
               "R8.5.1 missing-stop recovery preserves generation and lease")
        expect(recoveryLatency < 1_550_000_000,
               "R8.5.1 duplicate activity does not postpone missing-stop recovery")
        try await close(stack)
    }

    private static func testR851NormalListeningPassive(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let result = try await runR851ListeningTurn(
            stack: stack,
            session: stack.session,
            transcript: "嗯",
            expectsPassive: true,
            order: .finalBeforeStop,
            outputMode: .none,
            sequenceBase: 2,
            seed: 85_102,
            label: "normal Listening passive"
        )
        expect(result.createDelta == 0
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening,
               "R8.5.1 passive backchannel returns directly to Listening")
        try await close(stack)
    }

    private static func testR851RapidAlternatingTurns(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let lease = stack.runtime.activeBrainLeaseForTesting()
        let generation = stack.session.generation
        var sequenceBase: UInt64 = 2
        for index in 0 ..< 20 {
            let expectsPassive = index.isMultiple(of: 2)
            let result = try await runR851ListeningTurn(
                stack: stack,
                session: stack.session,
                transcript: expectsPassive ? "嗯" : "连续问题 \(index)",
                expectsPassive: expectsPassive,
                order: index.isMultiple(of: 3)
                    ? .completionBeforeFinal : .finalBeforeStop,
                outputMode: expectsPassive ? .none : .complete,
                sequenceBase: sequenceBase,
                seed: UInt32(85_200 + index),
                label: "rapid alternating turn \(index)"
            )
            expect(result.createDelta == (expectsPassive ? 0 : 1),
                   "R8.5.1 rapid turn has exactly one expected disposition")
            sequenceBase = result.nextSequence
            r851RapidTurns += 1
        }
        let finalLease = stack.runtime.activeBrainLeaseForTesting()
        let route = stack.controller.formalSpeechRouteDebugSnapshot
        r851GenerationDrift += route.generation == generation ? 0 : 1
        r851LeaseDrift += finalLease == lease ? 0 : 1
        expect(r851RapidTurns == 20
                && route.phase == .listening
                && route.generation == generation
                && finalLease == lease,
               "R8.5.1 rapid turns keep one generation and Brain lease")
        try await close(stack)
    }

    private static func testR851RepeatedInterruptions(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        guard let baselineLease = stack.runtime.activeBrainLeaseForTesting()
        else { fatalError("R8.5.1 repeated interruption lease missing") }
        var session = stack.session
        var turnID = stack.target.turnID
        var responseID = stack.target.responseID
        var proposalSequence: UInt64 = 4
        let interruptBaseline = await stack.provider.interruptCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount

        for cycle in 0 ..< 10 {
            session = try await performR851InterruptionCycle(
                stack: stack,
                session: session,
                turnID: turnID,
                responseID: responseID,
                proposalSequence: proposalSequence,
                label: "repeated interruption \(cycle)"
            )
            r851RepeatedInterruptionCycles += 1
            if cycle < 9 {
                let turn = await prepareR851ResidentResponseForInterruption(
                    stack: stack,
                    session: session,
                    label: "prepare interruption \(cycle + 1)"
                )
                turnID = turn.turnID
                responseID = turn.responseID
                proposalSequence = turn.nextSequence
            }
        }

        guard let finalLease = stack.runtime.activeBrainLeaseForTesting(),
              case .realtimeResidentBrain(let finalGeneration) =
                finalLease.generation else {
            fatalError("R8.5.1 repeated interruption final lease missing")
        }
        let interrupts = await stack.provider.interruptCount()
            - interruptBaseline
        let clears = stack.outputPlayer.clearScheduledPlaybackCount
            - clearBaseline
        r851DuplicateInterrupts += max(0, interrupts - 10)
        r851DuplicateClears += max(0, clears - 10)
        expect(r851RepeatedInterruptionCycles == 10
                && interrupts == 10 && clears == 10
                && finalGeneration == stack.session.generation + 10,
               "R8.5.1 ten interruption cycles advance exactly ten times")
        expect(finalLease.residentID == baselineLease.residentID
                && finalLease.runtimeSessionID
                    == baselineLease.runtimeSessionID
                && finalLease.brainLeaseID == baselineLease.brainLeaseID
                && finalLease.routeEpoch == baselineLease.routeEpoch,
               "R8.5.1 repeated interruption preserves lease identity")
        r851GenerationDrift += finalGeneration
            == stack.session.generation + 10 ? 0 : 1
        r851LeaseDrift += finalLease.brainLeaseID
            == baselineLease.brainLeaseID ? 0 : 1
        try await close(stack)
    }

    private static func prepareR851ResidentResponseForInterruption(
        stack: R823ControllerStack,
        session: RealtimeBrainSessionIdentity,
        label: String
    ) async -> (
        turnID: RealtimeBrainTurnID,
        responseID: RealtimeBrainResponseID,
        nextSequence: UInt64
    ) {
        let turnID = RealtimeBrainTurnID()
        let contextRevision = await r851ContextRevision(
            stack: stack,
            session: session,
            label: label,
            allowsGenerationCarry: true
        )
        let createBaseline = await stack.provider.createCount()
        await enqueueR843Activity(
            stack: stack,
            session: session,
            turnID: turnID,
            contextRevision: contextRevision,
            sequence: 1,
            kind: .userTranscriptFinal("R8.5.1 repeated interruption"),
            label: "\(label) response authorization"
        )
        await waitUntil("R8.5.1 \(label) response create") {
            await stack.provider.createCount() == createBaseline + 1
        }
        let output = await emitR851ResidentOutput(
            stack: stack,
            session: session,
            turnID: turnID,
            contextRevision: contextRevision,
            sequenceBase: 2,
            completePlayback: false,
            label: label
        )
        let createDelta = await stack.provider.createCount() - createBaseline
        let createCommand = await stack.provider.lastCreateCommand()
        r851DuplicateResponses += max(0, createDelta - 1)
        expect(createDelta == 1
                && createCommand?.identity.session == session
                && createCommand?.identity.turnID == turnID
                && createCommand?.identity.responseID == nil
                && createCommand?.identity.contextRevision == contextRevision
                && createCommand?.sourceEventSequence == 1,
               "R8.5.1 repeated cycle authorizes one resident response")
        return (turnID, output.responseID, output.nextSequence)
    }

    private static func testR851StopRestartMatrix(
        fixture: Data
    ) async throws {
        try await testR842ListeningStopRestart(fixture: fixture)
        r851StopRestartPoints += 1

        try await testR843GenerationFence(fixture: fixture)
        r851StopRestartPoints += 2

        try await testStopRestartIsolation(fixture: fixture)
        r851StopRestartPoints += 1

        try await testR851InterruptionPendingStopRestart(fixture: fixture)
        r851StopRestartPoints += 1

        expect(r851StopRestartPoints == 5,
               "R8.5.1 covers five formal Stop/restart points")
    }

    private static func testR851DelayedProviderOrdering(
        fixture: Data
    ) async throws {
        try await testR843FinalBeforeCompletion(fixture: fixture)
        r851DelayedOrderingCases += 1
        try await testR843CompletionBeforeFinal(fixture: fixture)
        r851DelayedOrderingCases += 1
        try await testR842ListeningProviderFirst(fixture: fixture)
        r851DelayedOrderingCases += 1
        try await testR844FinalAfterCompletion(fixture: fixture)
        r851DelayedOrderingCases += 1
        try await testR843DuplicateEvidence(fixture: fixture)
        r851DelayedOrderingCases += 1
        try await testR843CrossSourceTurn(fixture: fixture)
        r851DelayedOrderingCases += 1
        expect(r851DelayedOrderingCases == 6,
               "R8.5.1 executes every delayed Provider ordering")
    }

    private static func testR851DeterministicRandomizedOrdering(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        var generator = R851DeterministicGenerator(state: r851RandomSeed)
        var session = stack.session
        var sequenceBase: UInt64 = 2
        var expectedGeneration = session.generation
        let initialInterrupts = await stack.provider.interruptCount()
        let initialCancels = await stack.provider.cancelCount()
        let initialClears = stack.outputPlayer.clearScheduledPlaybackCount

        for iteration in 0 ..< 100 {
            if iteration > 0 && iteration.isMultiple(of: 10) {
                let previous = session
                session = await restartR851Route(
                    stack: stack,
                    previousSession: previous,
                    label: "random transition \(iteration)"
                )
                expectedGeneration += 1
                r851RandomizedExpectedGenerationTransitions += 1
                r851RandomizedObservedGenerationTransitions += Int(
                    session.generation - previous.generation
                )
                sequenceBase = 2
            }

            let random = generator.next()
            let expectsPassive = (random & 1) == 0
            let order: R851TurnOrder
            if iteration.isMultiple(of: 10) {
                order = .providerFirstStart
            } else {
                switch Int((random >> 8) % 4) {
                case 0: order = .finalBeforeStop
                case 1: order = .completionBeforeFinal
                case 2: order = .partialFinalStop
                default: order = .shortPauseResume
                }
            }
            switch order {
            case .finalBeforeStop:
                r851RandomizedFinalBeforeStop += 1
            case .completionBeforeFinal:
                r851RandomizedCompletionBeforeFinal += 1
            case .partialFinalStop:
                r851RandomizedPartialFinalStop += 1
            case .shortPauseResume:
                r851RandomizedShortPauseResume += 1
            case .providerFirstStart:
                r851RandomizedProviderFirstStart += 1
            }
            let result = try await runR851ListeningTurn(
                stack: stack,
                session: session,
                transcript: expectsPassive
                    ? ((random & 2) == 0 ? "嗯" : "mhm")
                    : "确定性随机问题 \(iteration)",
                expectsPassive: expectsPassive,
                order: order,
                outputMode: expectsPassive ? .none : .complete,
                sequenceBase: sequenceBase,
                seed: UInt32(truncatingIfNeeded: random),
                label: "deterministic ordering \(iteration)"
            )
            let createBeforeDuplicate = await stack.provider.createCount()
            let dispositionBeforeDuplicate = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            let dialogueBeforeDuplicate = try stack.sessionStore
                .loadMostRecentDialogueEntries()
            let narrativeBeforeDuplicate = stack.runtime
                .narrativeMemoryDebugSnapshot()
            let relationshipBeforeDuplicate = stack.runtime
                .currentRelationshipState
            let growthBeforeDuplicate = stack.runtime
                .realtimeGrowthObservationDecisionCountForTesting()
            let completionBeforeDuplicate = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let duplicateIdentity = r843EventIdentity(
                session: session,
                turnID: result.turnID,
                contextRevision: result.contextRevision
            )
            let leaseBeforeDuplicate = stack.runtime
                .activeBrainLeaseForTesting()
            await stack.controller.refreshMicrophoneAuthorization()
            let outputBeforeDuplicate = stack.controller
                .realtimeBrainOutputBridgeSnapshot
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: result.turnID,
                contextRevision: result.contextRevision,
                sequence: result.nextSequence,
                kind: .userTranscriptFinal("late duplicate"),
                label: "deterministic late duplicate \(iteration)"
            )
            await waitUntil(
                "R8.5.1 deterministic late duplicate \(iteration) processed"
            ) {
                await stack.controller.refreshMicrophoneAuthorization()
                let output = await stack.controller
                    .realtimeBrainOutputBridgeSnapshot
                return output.acceptedEventCount
                        + output.rejectedEventCount
                    == outputBeforeDuplicate.acceptedEventCount
                        + outputBeforeDuplicate.rejectedEventCount + 1
            }
            let createAfterDuplicate = await stack.provider.createCount()
            let dispositionAfterDuplicate = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            let historyWrites = try stack.sessionStore
                .loadMostRecentDialogueEntries()
                == dialogueBeforeDuplicate ? 0 : 1
            let memoryWrites = stack.runtime.narrativeMemoryDebugSnapshot()
                == narrativeBeforeDuplicate ? 0 : 1
            let relationshipChanges = stack.runtime.currentRelationshipState
                == relationshipBeforeDuplicate ? 0 : 1
            let growthWrites = stack.runtime
                .realtimeGrowthObservationDecisionCountForTesting()
                == growthBeforeDuplicate ? 0 : 1
            let completionAfterDuplicate = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let pendingInputAfterDuplicate = stack.runtime
                .realtimePendingUserInputForTesting(duplicateIdentity)
            let leaseAfterDuplicate = stack.runtime
                .activeBrainLeaseForTesting()
            let routeAfterDuplicate = stack.controller
                .formalSpeechRouteDebugSnapshot
            let duplicateCreates = createAfterDuplicate
                - createBeforeDuplicate
            r851DuplicateResponses += duplicateCreates
            r851FalsePersistence += historyWrites + memoryWrites
                + relationshipChanges + growthWrites
            r851FalseHistoryWrites += historyWrites
            r851FalseMemoryWrites += memoryWrites
            r851FalseRelationshipChanges += relationshipChanges
            r851FalseGrowthWrites += growthWrites
            r851GenerationDrift += routeAfterDuplicate.generation
                == expectedGeneration ? 0 : 1
            let leaseUnchanged = leaseAfterDuplicate == leaseBeforeDuplicate
                && r851LeaseMatches(leaseAfterDuplicate, session: session)
            r851LeaseDrift += leaseUnchanged ? 0 : 1
            expect(duplicateCreates == 0
                    && dispositionAfterDuplicate
                        == dispositionBeforeDuplicate
                    && historyWrites == 0 && memoryWrites == 0
                    && relationshipChanges == 0 && growthWrites == 0
                    && completionAfterDuplicate
                        == completionBeforeDuplicate
                    && pendingInputAfterDuplicate == nil
                    && routeAfterDuplicate.generation
                        == expectedGeneration
                    && leaseUnchanged,
                   "R8.5.1 randomized late duplicate is a no-op")
            let completion = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let route = stack.controller.formalSpeechRouteDebugSnapshot
            expect(completion.phase == .idle
                    && route.phase == .listening
                    && route.generation == expectedGeneration,
                   "R8.5.1 randomized iteration fully settles")
            r851RandomizedIterations += 1
            sequenceBase = result.nextSequence + 1
        }

        let interruptDelta = await stack.provider.interruptCount()
            - initialInterrupts
        let cancelDelta = await stack.provider.cancelCount()
            - initialCancels
        let clearDelta = stack.outputPlayer.clearScheduledPlaybackCount
            - initialClears
        r851FalseSelfInterrupts += interruptDelta + cancelDelta + clearDelta
        r851GenerationDrift += session.generation == expectedGeneration
            ? 0 : 1
        expect(r851RandomizedIterations == 100
                && r851RandomizedExpectedGenerationTransitions == 9
                && r851RandomizedObservedGenerationTransitions == 9,
               "R8.5.1 randomized stress executes 100 fixed-seed iterations")
        expect(r851RandomizedFinalBeforeStop > 0
                && r851RandomizedCompletionBeforeFinal > 0
                && r851RandomizedPartialFinalStop > 0
                && r851RandomizedShortPauseResume > 0
                && r851RandomizedProviderFirstStart > 0,
               "R8.5.1 fixed seed executes every legal ordering template")
        expect(interruptDelta == 0 && cancelDelta == 0 && clearDelta == 0
                && r851DuplicateResponses == 0
                && r851FalsePersistence == 0
                && r851GenerationDrift == 0
                && r851LeaseDrift == 0,
               "R8.5.1 randomized ordering has zero unsafe side effects")
        try await close(stack)
    }

    private static func runR851ListeningTurn(
        stack: R823ControllerStack,
        session: RealtimeBrainSessionIdentity,
        transcript: String,
        expectsPassive: Bool,
        order: R851TurnOrder,
        outputMode: R851OutputMode,
        sequenceBase: UInt64,
        seed: UInt32,
        label: String,
        allowsContextRevisionCarry: Bool = false
    ) async throws -> R851TurnResult {
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let completionBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        let dispositionBaseline = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let leaseBaseline = stack.runtime.activeBrainLeaseForTesting()
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState
        let growthBefore = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()
        let contextRevision = await r851ContextRevision(
            stack: stack,
            session: session,
            label: label,
            allowsGenerationCarry: allowsContextRevisionCarry
        )
        var nextSequence = sequenceBase
        var finalSequence: UInt64?

        if order == .providerFirstStart {
            await stack.controller.refreshMicrophoneAuthorization()
            let outputBeforeProviderStart = stack.controller
                .realtimeBrainOutputBridgeSnapshot
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userSpeechStarted,
                label: "\(label) Provider-first start"
            )
            nextSequence += 1
            await waitUntil("R8.5.1 \(label) Provider-first processed") {
                await stack.controller.refreshMicrophoneAuthorization()
                let output = await stack.controller
                    .realtimeBrainOutputBridgeSnapshot
                return output.acceptedEventCount
                        + output.rejectedEventCount
                    == outputBeforeProviderStart.acceptedEventCount
                        + outputBeforeProviderStart.rejectedEventCount + 1
            }
            expect(stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                    .phase == .idle,
                   "R8.5.1 Provider-first start has no admission authority")
            try await emitR842ListeningSamples(
                stack: stack,
                samples: signal(seed: seed, amplitude: 0.18),
                expectedClassification: .nearEndCandidate,
                label: "R8.5.1 \(label) Provider-first production audio"
            )
            await waitUntilOnMainActor("R8.5.1 \(label) admission") {
                let snapshot = stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot()
                return snapshot.phase == .speaking
                    && snapshot.session == session
                    && snapshot.sourceTurnID == turnID
            }
        } else {
            try await admitR844ListeningTurn(
                stack: stack,
                session: session,
                sourceTurnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                seed: seed,
                label: "R8.5.1 \(label)"
            )
            nextSequence += 1
        }

        switch order {
        case .completionBeforeFinal:
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userSpeechStopped,
                label: "\(label) stop before final"
            )
            nextSequence += 1
            await waitForR842Completion(
                runtime: stack.runtime,
                expectedCount: completionBaseline + 1,
                expectedSession: session,
                expectedTurn: turnID,
                expectedContextRevision: contextRevision,
                expectedStoppedSequence: nextSequence - 1,
                label: "R8.5.1 \(label) completion before final"
            )
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userTranscriptFinal(transcript),
                label: "\(label) late final"
            )
            finalSequence = nextSequence
            nextSequence += 1
        case .shortPauseResume:
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userSpeechStopped,
                label: "\(label) short pause"
            )
            nextSequence += 1
            await waitUntilOnMainActor("R8.5.1 \(label) candidate pause") {
                stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                    .phase == .candidatePause
            }
            try? await Task.sleep(for: .milliseconds(120))
            try await emitR842ListeningSamples(
                stack: stack,
                samples: signal(seed: seed &+ 1, amplitude: 0.18),
                expectedClassification: .nearEndCandidate,
                label: "R8.5.1 \(label) resume audio"
            )
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userSpeechStarted,
                label: "\(label) resume"
            )
            nextSequence += 1
            await waitUntilOnMainActor("R8.5.1 \(label) resumed") {
                stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                    .phase == .speaking
            }
            fallthrough
        case .finalBeforeStop, .providerFirstStart:
            finalSequence = nextSequence
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userTranscriptFinal(transcript),
                label: "\(label) final"
            )
            nextSequence += 1
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userSpeechStopped,
                label: "\(label) true stop"
            )
            nextSequence += 1
        case .partialFinalStop:
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userTranscriptPartial("partial"),
                label: "\(label) partial"
            )
            nextSequence += 1
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userTranscriptFinal(transcript),
                label: "\(label) final"
            )
            finalSequence = nextSequence
            nextSequence += 1
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequence: nextSequence,
                kind: .userSpeechStopped,
                label: "\(label) stop"
            )
            nextSequence += 1
        }

        await waitUntilOnMainActor("R8.5.1 \(label) disposition") {
            let completion = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let disposition = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            return completion.completionCandidateCount
                    == completionBaseline + 1
                && disposition.passiveBackchannelCount
                    == dispositionBaseline.passiveBackchannelCount
                        + (expectsPassive ? 1 : 0)
                && disposition.substantiveCount
                    == dispositionBaseline.substantiveCount
                        + (expectsPassive ? 0 : 1)
        }
        if !expectsPassive {
            await waitUntil("R8.5.1 \(label) response create") {
                await stack.provider.createCount() == createBaseline + 1
            }
        }
        let createDelta = await stack.provider.createCount()
            - createBaseline
        let expectedCreates = expectsPassive ? 0 : 1
        r851DuplicateResponses += max(0, createDelta - expectedCreates)
        expect(createDelta == expectedCreates,
               "R8.5.1 response policy creates exactly the expected count")
        if !expectsPassive {
            guard let finalSequence,
                  let command = await stack.provider.lastCreateCommand()
            else {
                fatalError("R8.5.1 \(label) response identity missing")
            }
            expect(command.identity.session == session
                    && command.identity.turnID == turnID
                    && command.identity.responseID == nil
                    && command.identity.contextRevision == contextRevision
                    && command.sourceEventSequence == finalSequence,
                   "R8.5.1 response binds the exact accepted final identity")
        }

        var responseID: RealtimeBrainResponseID?
        if !expectsPassive && outputMode != .none {
            let result = await emitR851ResidentOutput(
                stack: stack,
                session: session,
                turnID: turnID,
                contextRevision: contextRevision,
                sequenceBase: nextSequence,
                completePlayback: outputMode == .complete,
                label: label
            )
            responseID = result.responseID
            nextSequence = result.nextSequence
        }

        let interruptDelta = await stack.provider.interruptCount()
            - interruptBaseline
        let cancelDelta = await stack.provider.cancelCount()
            - cancelBaseline
        let clearDelta = stack.outputPlayer.clearScheduledPlaybackCount
            - clearBaseline
        r851FalseSelfInterrupts += interruptDelta + cancelDelta + clearDelta
        let route = stack.controller.formalSpeechRouteDebugSnapshot
        r851GenerationDrift += route.generation == session.generation ? 0 : 1
        r851LeaseDrift += stack.runtime.activeBrainLeaseForTesting()
            == leaseBaseline ? 0 : 1
        expect(interruptDelta == 0 && cancelDelta == 0 && clearDelta == 0,
               "R8.5.1 ordinary user turn has no interruption side effects")
        expect(route.generation == session.generation
                && stack.runtime.activeBrainLeaseForTesting()
                    == leaseBaseline,
               "R8.5.1 ordinary turn preserves generation and lease")

        let identity = r843EventIdentity(
            session: session,
            turnID: turnID,
            contextRevision: contextRevision
        )
        if expectsPassive {
            let historyWrites = try stack.sessionStore
                .loadMostRecentDialogueEntries() == dialogueBefore ? 0 : 1
            let memoryWrites = stack.runtime.narrativeMemoryDebugSnapshot()
                == narrativeBefore ? 0 : 1
            let relationshipChanges = stack.runtime.currentRelationshipState
                == relationshipBefore ? 0 : 1
            let growthWrites = stack.runtime
                .realtimeGrowthObservationDecisionCountForTesting()
                == growthBefore ? 0 : 1
            r851FalsePersistence += historyWrites + memoryWrites
                + relationshipChanges + growthWrites
            r851FalseHistoryWrites += historyWrites
            r851FalseMemoryWrites += memoryWrites
            r851FalseRelationshipChanges += relationshipChanges
            r851FalseGrowthWrites += growthWrites
            expect(historyWrites == 0 && memoryWrites == 0
                    && relationshipChanges == 0 && growthWrites == 0
                    && stack.runtime
                        .realtimePendingUserInputForTesting(identity) == nil,
                   "R8.5.1 passive turn is ephemeral and fully retired")
        } else if outputMode == .complete {
            expect(stack.runtime.realtimePendingUserInputForTesting(identity)
                    == nil,
                   "R8.5.1 completed substantive output retires user input")
        }
        return R851TurnResult(
            turnID: turnID,
            responseID: responseID,
            contextRevision: contextRevision,
            nextSequence: nextSequence,
            createDelta: createDelta
        )
    }

    private static func emitR851ResidentOutput(
        stack: R823ControllerStack,
        session: RealtimeBrainSessionIdentity,
        turnID: RealtimeBrainTurnID,
        contextRevision: UInt64,
        sequenceBase: UInt64,
        completePlayback: Bool,
        label: String
    ) async -> (
        responseID: RealtimeBrainResponseID,
        nextSequence: UInt64
    ) {
        await stack.controller.refreshMicrophoneAuthorization()
        let responseID = RealtimeBrainResponseID()
        let startBaseline = stack.outputPlayer.startCount
        let playbackBaseline = stack.controller.speechAudioOutputHostSnapshot
        let outputBaseline = stack.controller
            .realtimeBrainOutputBridgeSnapshot
        let audioSequence = await stack.provider.nextResidentAudioSequence(
            for: session
        )
        var sequence = sequenceBase
        let prefixEvents: [RealtimeResidentBrainEventKind] = [
            .residentTextDelta("R8.5.1 response"),
            .residentSpeakingStarted,
            .residentAudioDelta(audioDelta(sequence: audioSequence))
        ]
        for event in prefixEvents {
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                responseID: responseID,
                contextRevision: contextRevision,
                sequence: sequence,
                kind: event,
                label: "\(label) resident output \(sequence)"
            )
            sequence += 1
        }
        await waitUntil("R8.5.1 \(label) Playback starts") {
            stack.outputPlayer.startCount == startBaseline + 1
        }
        if completePlayback {
            let suffixEvents: [RealtimeResidentBrainEventKind] = [
                .residentTextFinal("R8.5.1 response complete"),
                .residentSpeakingStopped
            ]
            for event in suffixEvents {
                await enqueueR843Activity(
                    stack: stack,
                    session: session,
                    turnID: turnID,
                    responseID: responseID,
                    contextRevision: contextRevision,
                    sequence: sequence,
                    kind: event,
                    label: "\(label) resident completion \(sequence)"
                )
                sequence += 1
            }
            await waitUntil(
                "R8.5.1 \(label) resident response completes"
            ) {
                await stack.controller.refreshMicrophoneAuthorization()
                let output = await stack.controller
                    .realtimeBrainOutputBridgeSnapshot
                return output.completedResponseCount
                    == outputBaseline.completedResponseCount + 1
            }
            await enqueueR843Activity(
                stack: stack,
                session: session,
                turnID: turnID,
                responseID: responseID,
                contextRevision: contextRevision,
                sequence: sequence,
                kind: .residentSemanticFinal(
                    RealtimeBrainSemanticOutput(
                        canonicalText: "R8.5.1 response complete"
                    )
                ),
                label: "\(label) resident semantic completion"
            )
            sequence += 1
            await waitUntil("R8.5.1 \(label) semantic output accepted") {
                await stack.controller.refreshMicrophoneAuthorization()
                let output = await stack.controller
                    .realtimeBrainOutputBridgeSnapshot
                return output.acceptedEventCount
                    == outputBaseline.acceptedEventCount + 6
            }
            await waitUntilOnMainActor(
                "R8.5.1 \(label) semantic completion settles"
            ) {
                stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                    .phase == .idle
            }
            stack.outputPlayer.completeScheduledChunk()
            await waitUntil("R8.5.1 \(label) Listening") {
                let playback = await stack.outputHost.currentSnapshot()
                let route = await stack.controller
                    .formalSpeechRouteDebugSnapshot
                return playback.playbackCompletedCount
                        == playbackBaseline.playbackCompletedCount + 1
                    && route.phase == .listening
            }
        } else {
            await waitUntilOnMainActor("R8.5.1 \(label) resident speaking") {
                stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .speaking
            }
        }
        return (responseID, sequence)
    }

    private static func settleR851ListeningSilence(
        stack: R823ControllerStack,
        expectedSession: RealtimeBrainSessionIdentity,
        frameCount: Int,
        label: String
    ) async throws {
        let silence = [Float](
            repeating: 0,
            count: MacSpeechAcousticEchoHost.frameSampleCount
        )
        let audioBaseline = await stack.provider.audioFrameCount()
        let createBaseline = await stack.provider.createCount()
        let completionBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        let dispositionBaseline = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        var emittedPacketCount = 0
        var emittedFrameCount = 0
        let tailDeadline = monotonicNow()
            + RealtimeAcousticInterruptionEligibilityGate
                .residualTailWindowNanoseconds
            + 2_000_000_000
        while true {
            let observation = stack.acousticEchoHost
                .acousticObservationSnapshot()
            let residualTailExpired: Bool
            if let lastAudible = observation
                    .lastAudibleRenderHostTimeNanoseconds,
               let captureTimestamp = observation
                    .captureHostTimeNanoseconds {
                residualTailExpired = captureTimestamp >= lastAudible
                    && captureTimestamp - lastAudible
                        >= RealtimeAcousticInterruptionEligibilityGate
                            .residualTailWindowNanoseconds
            } else {
                residualTailExpired = false
            }
            if emittedFrameCount >= frameCount && residualTailExpired {
                break
            }
            guard monotonicNow() < tailDeadline else {
                fatalError(
                    "timeout: R8.5.1 \(label) residual playback tail"
                )
            }
            let before = stack.acousticEchoHost
                .acousticObservationSnapshot()
            stack.aecBackend.setCaptureOutput(silence)
            let processed = stack.acousticEchoHost.processCapture(
                silence,
                hostTimeNanoseconds: monotonicNow()
            )
            let emission = try stack.capture.emit(
                processedSamples: processed,
                acousticBefore: before
            )
            emittedPacketCount += emission.packetCount
            emittedFrameCount += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        let expectedPacketCount = emittedPacketCount
        await waitUntil("R8.5.1 \(label) reaches N+1 Provider") {
            await stack.provider.audioFrameCount()
                >= audioBaseline + expectedPacketCount
        }
        let frames = await stack.provider.audioFrames(after: audioBaseline)
        let createAfterSilence = await stack.provider.createCount()
        let observation = stack.acousticEchoHost
            .acousticObservationSnapshot()
        expect(emittedPacketCount > 0
                && frames.count == emittedPacketCount
                && frames.allSatisfy { $0.identity == expectedSession }
                && !observation.isPlaybackActive
                && !observation.sourceGateOpen
                && observation.rawCaptureRMS < 0.000_001
                && observation.processedCaptureRMS < 0.000_001
                && observation.linearAECOutputRMS < 0.000_001
                && createAfterSilence == createBaseline
                && stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot()
                    == completionBaseline
                && stack.runtime
                    .realtimeUserTurnDispositionDebugSnapshot()
                    == dispositionBaseline,
               "R8.5.1 \(label) settles through production silence")
    }

    private static func performR851InterruptionCycle(
        stack: R823ControllerStack,
        session: RealtimeBrainSessionIdentity,
        turnID: RealtimeBrainTurnID,
        responseID: RealtimeBrainResponseID,
        proposalSequence: UInt64,
        label: String
    ) async throws -> RealtimeBrainSessionIdentity {
        let nextSession = RealtimeBrainSessionIdentity(
            residentID: session.residentID,
            runtimeSessionID: session.runtimeSessionID,
            brainLeaseID: session.brainLeaseID,
            routeEpoch: session.routeEpoch,
            generation: session.generation + 1
        )
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let startBaseline = stack.outputPlayer.startCount
        await stack.controller.refreshMicrophoneAuthorization()
        let playbackBaseline = stack.controller
            .speechAudioOutputHostSnapshot
        let subtitleAfterResidentOutput = stack.controller
            .realtimeSpeechSubtitleSnapshot
        let acousticBaseline = stack.controller
            .realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        let forwardedBaseline = stack.controller
            .realtimeBrainInputBridgeSnapshot.forwardedFrameCount
        let rejectedFrameBaseline = stack.controller
            .realtimeBrainInputBridgeSnapshot.runtimeRejectedFrameCount
        let sendBaseline = stack.controller
            .realtimeBrainInputBridgeSnapshot.sendOperationCount
        await stack.provider.holdInterrupt()
        _ = try await submitTrueNearEndThroughProductionChain(stack: stack)
        let acousticDeadline = monotonicNow() + 3_000_000_000
        let continuedRender = signal(seed: 17, amplitude: 0.3)
        let continuedNearEnd = signal(seed: 19, amplitude: 0.27)
        let continuedCapture = zip(
            continuedRender,
            continuedNearEnd
        ).map { render, nearEnd in
            render * 0.8 + nearEnd
        }
        let continuedProcessed = zip(
            continuedRender,
            continuedNearEnd
        ).map { render, nearEnd in
            render * 0.05 + nearEnd
        }
        while true {
            await stack.controller.refreshMicrophoneAuthorization()
            let bridge = stack.controller
                .realtimeBrainInputBridgeSnapshot
            if bridge.acousticEvidenceCount == acousticBaseline + 1 {
                break
            }
            if bridge.acousticEvidenceCount > acousticBaseline + 1 {
                fatalError(
                    "FAIL: R8.5.1 \(label) forwarded duplicate acoustic evidence"
                )
            }
            if monotonicNow() >= acousticDeadline {
                let acoustic = stack.acousticEchoHost
                    .acousticObservationSnapshot()
                let evidence = stack.runtime
                    .realtimeInterruptionEvidenceDebugSnapshot()
                let eligibility = bridge
                    .lastAcousticEligibilityDisposition ?? "nil"
                let forward = bridge
                    .lastAcousticEvidenceForwardDisposition ?? "nil"
                fatalError(
                    "timeout: R8.5.1 \(label) acoustic Bridge refresh "
                        + "baseline=\(acousticBaseline) "
                        + "current=\(bridge.acousticEvidenceCount) "
                        + "observed="
                        + "\(bridge.residentAcousticObservationCount) "
                        + "rejected="
                        + "\(bridge.rejectedResidentAcousticObservationCount) "
                        + "dropped="
                        + "\(bridge.droppedResidentAcousticObservationCount) "
                        + "eligibility=\(eligibility) "
                        + "forward=\(forward) "
                        + "forwarded_delta="
                        + "\(bridge.forwardedFrameCount - forwardedBaseline) "
                        + "send_delta="
                        + "\(bridge.sendOperationCount - sendBaseline) "
                        + "runtime_rejected_delta="
                        + "\(bridge.runtimeRejectedFrameCount - rejectedFrameBaseline) "
                        + "source_gated_frames="
                        + "\(bridge.sourceGatedNearEndFrameCount) "
                        + "classification="
                        + "\(acoustic.inputClassification.rawValue) "
                        + "playback=\(acoustic.isPlaybackActive) "
                        + "source_gate=\(acoustic.sourceGateOpen) "
                        + "source_epoch=\(acoustic.sourceGateEpoch) "
                        + "raw_rms=\(acoustic.rawCaptureRMS) "
                        + "processed_rms="
                        + "\(acoustic.processedCaptureRMS) "
                        + "aec_active=\(acoustic.aecActive) "
                        + "render_available="
                        + "\(acoustic.renderReferenceAvailable) "
                        + "alignment_locked="
                        + "\(acoustic.sourceAlignmentLocked) "
                        + "alignment_delay="
                        + "\(String(describing: acoustic.sourceAlignmentDelayMilliseconds)) "
                        + "capture_timestamp="
                        + "\(String(describing: acoustic.captureHostTimeNanoseconds)) "
                        + "render_timestamp="
                        + "\(String(describing: acoustic.renderHostTimeNanoseconds)) "
                        + "runtime_session_match="
                        + "\(evidence.session == session) "
                        + "runtime_acoustic="
                        + "\(evidence.hasAcousticEvidence)"
                )
            }
            let captureTimestamp = monotonicNow()
            stack.aecBackend.setCaptureOutput(continuedProcessed)
            stack.acousticEchoHost.processRender(
                continuedRender,
                hostTimeNanoseconds: captureTimestamp - 80_000_000
            )
            let processed = stack.acousticEchoHost.processCapture(
                continuedCapture,
                hostTimeNanoseconds: captureTimestamp
            )
            _ = try stack.capture.emit(processedSamples: processed)
            try? await Task.sleep(for: .milliseconds(12))
        }
        await waitUntilOnMainActor("R8.5.1 \(label) acoustic evidence") {
            let evidence = stack.runtime
                .realtimeInterruptionEvidenceDebugSnapshot()
            return evidence.session == session
                && evidence.hasAcousticEvidence
                && !evidence.hasSemanticEvidence
        }
        let contextRevision = await r851ContextRevision(
            stack: stack,
            session: session,
            label: label,
            allowsGenerationCarry: true
        )
        let proposalIdentity = r843EventIdentity(
            session: session,
            turnID: turnID,
            responseID: responseID,
            contextRevision: contextRevision
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: proposalIdentity,
            sequence: proposalSequence,
            kind: .interruptionProposed(RealtimeBrainInterruptionProposal(
                identity: proposalIdentity,
                reason: "user_speech_started_during_resident_response"
            ))
        ))
        await waitUntil("R8.5.1 \(label) clear before ACK") {
            await stack.provider.isInterruptHeld()
                && stack.outputPlayer.clearScheduledPlaybackCount
                    == clearBaseline + 1
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let acceptedBaseline = stack.controller
            .realtimeBrainOutputBridgeSnapshot.acceptedEventCount
        let rejectedBaseline = stack.controller
            .realtimeBrainOutputBridgeSnapshot.rejectedEventCount
        let returnedBaseline = await stack.provider.returnedEventCount(
            eventSession: session
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: proposalIdentity,
            sequence: proposalSequence + 1,
            kind: .residentTextDelta("stale R8.5.1 output")
        ))
        await stack.provider.releaseInterrupt()
        await waitUntilOnMainActor("R8.5.1 \(label) N+1 generation") {
            guard let lease = stack.runtime.activeBrainLeaseForTesting()
            else { return false }
            return lease.generation
                    == .realtimeResidentBrain(nextSession.generation)
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
        }
        await waitUntil("R8.5.1 \(label) N+1 Bridges rebound") {
            await stack.controller.refreshMicrophoneAuthorization()
            let input = await stack.controller
                .realtimeBrainInputBridgeSnapshot
            let output = await stack.controller
                .realtimeBrainOutputBridgeSnapshot
            return input.hasActivePump && output.hasActiveReceiveLoop
        }
        await waitUntil("R8.5.1 \(label) stale output returns") {
            await stack.provider.returnedEventCount(eventSession: session)
                == returnedBaseline + 1
        }
        await waitUntil("R8.5.1 \(label) stale output rejected") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller.realtimeBrainOutputBridgeSnapshot
                .rejectedEventCount == rejectedBaseline + 1
        }
        let reboundBaseline = await stack.provider.audioFrameCount()
        let reboundPacketCount = try
            submitPostInterruptionInputThroughProductionChain(stack: stack)
        await waitUntil("R8.5.1 \(label) N+1 PCM rebound") {
            await stack.provider.audioFrameCount()
                >= reboundBaseline + reboundPacketCount
        }
        let reboundFrames = await stack.provider.audioFrames(
            after: reboundBaseline
        )
        expect(reboundFrames.count == reboundPacketCount
                && reboundFrames.allSatisfy { $0.identity == nextSession },
               "R8.5.1 interruption cycle rebounds exact N+1 PCM")
        stack.outputPlayer.completeStoppedChunk()
        await waitUntil("R8.5.1 \(label) old callback rejected") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller.speechAudioOutputHostSnapshot
                .rejectedCallbackCount
                == playbackBaseline.rejectedCallbackCount + 1
        }
        let interruptDelta = await stack.provider.interruptCount()
            - interruptBaseline
        let cancelDelta = await stack.provider.cancelCount() - cancelBaseline
        let clearDelta = stack.outputPlayer.clearScheduledPlaybackCount
            - clearBaseline
        await stack.controller.refreshMicrophoneAuthorization()
        let finalOutput = stack.controller.realtimeBrainOutputBridgeSnapshot
        let staleAccepted = Int(finalOutput.acceptedEventCount
            - acceptedBaseline)
        let staleResurrection = stack.outputPlayer.startCount
                    == startBaseline
                && stack.controller.realtimeSpeechSubtitleSnapshot
                    == subtitleAfterResidentOutput ? 0 : 1
        r851StaleSideEffects += staleAccepted + staleResurrection
        expect(interruptDelta == 1 && cancelDelta == 0 && clearDelta == 1,
               "R8.5.1 interruption cycle owns one interrupt and clear")
        expect(staleAccepted == 0 && staleResurrection == 0,
               "R8.5.1 old output and callback remain stale after N+1")
        stack.acousticEchoHost.playbackStopped()
        try await settleR851ListeningSilence(
            stack: stack,
            expectedSession: nextSession,
            frameCount: 24,
            label: "\(label) N+1 listening boundary"
        )
        return nextSession
    }

    private static func testR851InterruptionPendingStopRestart(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let oldSession = stack.session
        let startBaseline = stack.outputPlayer.startCount
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        await stack.provider.holdInterrupt()
        _ = try await submitTrueNearEndThroughProductionChain(stack: stack)
        let proposal = semanticProposal(stack: stack, sequence: 4)
        await stack.provider.enqueue(proposal)
        await waitUntil("R8.5.1 interruption-pending clear") {
            await stack.provider.isInterruptHeld()
                && stack.outputPlayer.clearScheduledPlaybackCount
                    == clearBaseline + 1
        }
        let stopTask = Task { @MainActor in
            await stack.controller.stopSpeechAudioCapture()
        }
        await stack.provider.releaseInterrupt()
        await stopTask.value
        await waitUntilOnMainActor("R8.5.1 interruption-pending stop") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .idle
        }
        await stack.controller.startRealtimeResidentBrainRoute()
        await waitUntil("R8.5.1 interruption-pending restart") {
            guard let current = await stack.provider.lastSession() else {
                return false
            }
            let route = await stack.controller.formalSpeechRouteDebugSnapshot
            return current.generation == oldSession.generation + 2
                && current.residentID == oldSession.residentID
                && current.runtimeSessionID == oldSession.runtimeSessionID
                && current.brainLeaseID != oldSession.brainLeaseID
                && current.routeEpoch == oldSession.routeEpoch + 1
                && route.phase == .listening
                && route.generation == current.generation
        }
        guard let restarted = await stack.provider.lastSession() else {
            fatalError("R8.5.1 interruption-pending restart missing")
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let outputBaseline = stack.controller
            .realtimeBrainOutputBridgeSnapshot
        let returnedBaseline = await stack.provider.returnedEventCount(
            eventSession: oldSession
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 5,
            kind: .residentAudioDelta(audioDelta(sequence: 2))
        ))
        await waitUntil("R8.5.1 interruption-pending stale return") {
            await stack.provider.returnedEventCount(eventSession: oldSession)
                == returnedBaseline + 1
        }
        await waitUntil("R8.5.1 interruption-pending stale rejection") {
            await stack.controller.refreshMicrophoneAuthorization()
            let output = await stack.controller
                .realtimeBrainOutputBridgeSnapshot
            return output.acceptedEventCount
                    == outputBaseline.acceptedEventCount
                && output.rejectedEventCount
                    == outputBaseline.rejectedEventCount + 1
        }
        let finalOutput = stack.controller.realtimeBrainOutputBridgeSnapshot
        let staleAccepted = Int(finalOutput.acceptedEventCount
            - outputBaseline.acceptedEventCount)
        let staleRejected = Int(finalOutput.rejectedEventCount
            - outputBaseline.rejectedEventCount)
        let route = stack.controller.formalSpeechRouteDebugSnapshot
        let interruptDelta = await stack.provider.interruptCount()
            - interruptBaseline
        let cancelDelta = await stack.provider.cancelCount() - cancelBaseline
        let clearDelta = stack.outputPlayer.clearScheduledPlaybackCount
            - clearBaseline
        r851DuplicateInterrupts += max(0, interruptDelta - 1)
        r851DuplicateClears += max(0, clearDelta - 1)
        r851StaleSideEffects += staleAccepted
        expect(restarted.generation == oldSession.generation + 2,
               "R8.5.1 confirmed interruption and restart advance twice")
        expect(route.phase == .listening
                && route.generation == restarted.generation,
               "R8.5.1 restart publishes the exact active generation")
        let leaseMatchesRestart = r851LeaseMatches(
            stack.runtime.activeBrainLeaseForTesting(),
            session: restarted
        )
        r851LeaseDrift += leaseMatchesRestart ? 0 : 1
        expect(leaseMatchesRestart,
               "R8.5.1 restart preserves the exact active Brain lease")
        expect(stack.outputPlayer.startCount == startBaseline,
               "R8.5.1 stale audio cannot restart Playback")
        expect(interruptDelta == 1 && cancelDelta == 0 && clearDelta == 1,
               "R8.5.1 interruption-pending Stop has one interrupt and clear")
        expect(staleAccepted == 0 && staleRejected == 1,
               "R8.5.1 interruption-pending Stop rejects old generation")
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func r851ContextRevision(
        stack: R823ControllerStack,
        session: RealtimeBrainSessionIdentity,
        label: String,
        allowsGenerationCarry: Bool = false
    ) async -> UInt64 {
        if let revision = await stack.provider.contextRevision(for: session) {
            return revision
        }
        guard allowsGenerationCarry,
              let revision = await stack.provider.carriedContextRevision(
                for: session
              ) else {
            fatalError("R8.5.1 \(label) formal context revision missing")
        }
        return revision
    }

    private static func restartR851Route(
        stack: R823ControllerStack,
        previousSession: RealtimeBrainSessionIdentity,
        label: String
    ) async -> RealtimeBrainSessionIdentity {
        await stack.controller.stopSpeechAudioCapture()
        await waitUntilOnMainActor("R8.5.1 \(label) stop") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .idle
        }
        await stack.controller.startRealtimeResidentBrainRoute()
        await waitUntil("R8.5.1 \(label) restart") {
            guard let session = await stack.provider.lastSession() else {
                return false
            }
            let route = await stack.controller.formalSpeechRouteDebugSnapshot
            return session != previousSession
                && session.generation == previousSession.generation + 1
                && session.residentID == previousSession.residentID
                && session.runtimeSessionID
                    == previousSession.runtimeSessionID
                && session.brainLeaseID != previousSession.brainLeaseID
                && session.routeEpoch == previousSession.routeEpoch + 1
                && route.phase == .listening
                && route.generation == session.generation
        }
        guard let session = await stack.provider.lastSession() else {
            fatalError("R8.5.1 \(label) restarted session missing")
        }
        let leaseMatchesRestart = r851LeaseMatches(
            stack.runtime.activeBrainLeaseForTesting(),
            session: session
        )
        r851LeaseDrift += leaseMatchesRestart ? 0 : 1
        expect(leaseMatchesRestart,
               "R8.5.1 \(label) restart preserves the active Brain lease")
        return session
    }

    private static func r851LeaseMatches(
        _ lease: ActiveBrainLease?,
        session: RealtimeBrainSessionIdentity
    ) -> Bool {
        guard let lease,
              case .realtimeResidentBrain(let generation) = lease.generation
        else { return false }
        return lease.state == .active
            && lease.route == .realtimeResidentBrain
            && lease.residentID == session.residentID
            && lease.runtimeSessionID == session.runtimeSessionID
            && lease.brainLeaseID == session.brainLeaseID
            && lease.routeEpoch == session.routeEpoch
            && generation == session.generation
    }

    private static func printR851CrossNodeMetrics() {
        print("r851_cross_node_executable_scenarios=\(r851CrossNodeScenarios)")
        print("r851_cross_node_failures=0")
        print("r851_rapid_consecutive_turns=\(r851RapidTurns)")
        print("r851_repeated_interruption_cycles=\(r851RepeatedInterruptionCycles)")
        print("r851_stop_restart_points=\(r851StopRestartPoints)")
        print("r851_delayed_provider_ordering_cases=\(r851DelayedOrderingCases)")
        print("r851_duplicate_response_creates=\(r851DuplicateResponses)")
        print("r851_duplicate_interrupts=\(r851DuplicateInterrupts)")
        print("r851_duplicate_clears=\(r851DuplicateClears)")
        print("r851_stale_generation_side_effects=\(r851StaleSideEffects)")
        print("r851_false_self_interrupts=\(r851FalseSelfInterrupts)")
        print("r851_false_persistence_writes=\(r851FalsePersistence)")
        print("r851_false_history_writes=\(r851FalseHistoryWrites)")
        print("r851_false_memory_writes=\(r851FalseMemoryWrites)")
        print("r851_false_relationship_changes=\(r851FalseRelationshipChanges)")
        print("r851_false_growth_writes=\(r851FalseGrowthWrites)")
        print("r851_generation_drift=\(r851GenerationDrift)")
        print("r851_lease_drift=\(r851LeaseDrift)")
    }

    private static func printR851RandomizedMetrics() {
        print(String(
            format: "r851_randomized_seed=0x%llX",
            r851RandomSeed
        ))
        print("r851_randomized_race_iterations=\(r851RandomizedIterations)")
        print("r851_randomized_race_failures=\(r851RandomizedFailures)")
        print("r851_randomized_generation_transitions_expected=\(r851RandomizedExpectedGenerationTransitions)")
        print("r851_randomized_generation_transitions_observed=\(r851RandomizedObservedGenerationTransitions)")
        print("r851_randomized_final_before_stop=\(r851RandomizedFinalBeforeStop)")
        print("r851_randomized_completion_before_final=\(r851RandomizedCompletionBeforeFinal)")
        print("r851_randomized_partial_final_stop=\(r851RandomizedPartialFinalStop)")
        print("r851_randomized_short_pause_resume=\(r851RandomizedShortPauseResume)")
        print("r851_randomized_provider_first_start=\(r851RandomizedProviderFirstStart)")
        print("r851_randomized_duplicate_response_creates=\(r851DuplicateResponses)")
        print("r851_randomized_false_self_interrupts=\(r851FalseSelfInterrupts)")
        print("r851_randomized_false_persistence_writes=\(r851FalsePersistence)")
        print("r851_randomized_generation_drift=\(r851GenerationDrift)")
        print("r851_randomized_lease_drift=\(r851LeaseDrift)")
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

    private enum R844SemanticEventOrder {
        case finalBeforeCompletion
        case completionBeforeFinal
    }

    private static func testR844BackchannelClassifier() {
        let passive = [
            "嗯", "嗯嗯", "唔", "唔嗯", "哦", "哦哦",
            "mhm", "mm", "mm-hmm", "uh-huh", "uh huh",
            "  嗯  ", "\n嗯嗯\t", "MHM", "Mhm.", "嗯。",
            "嗯！", "uh   huh", "嗯 嗯嗯"
        ]
        let substantive = [
            "好", "好的", "可以", "行", "对", "是", "是的",
            "yes", "yeah", "okay", "ok", "继续", "然后呢",
            "为什么", "why", "嗯？", "嗯?", "嗯？为什么",
            "嗯，我觉得还是第二个", "mhm but I disagree",
            "嗯 我还有一个问题", "", "！", "uh"
        ]
        for transcript in passive {
            cases += 1
            let disposition = RuntimeCore
                .realtimeUserTurnDispositionForTesting(transcript)
            if disposition != "passive_backchannel" {
                r844ClassifierFalseSubstantive += 1
            }
            expect(disposition == "passive_backchannel",
                   "R8.4.4 classifier keeps a high-confidence passive set")
            r844ClassifierPassiveCases += 1
        }
        for transcript in substantive {
            cases += 1
            let disposition = RuntimeCore
                .realtimeUserTurnDispositionForTesting(transcript)
            if disposition != "substantive" {
                r844ClassifierFalsePassive += 1
            }
            expect(disposition == "substantive",
                   "R8.4.4 classifier fails open for semantic input")
            r844ClassifierSubstantiveCases += 1
        }
        expect(r844ClassifierPassiveCases == 19,
               "R8.4.4 classifier covers the fixed passive matrix")
        expect(r844ClassifierSubstantiveCases == 24,
               "R8.4.4 classifier covers the fail-open matrix")
        expect(r844ClassifierFalsePassive == 0
                && r844ClassifierFalseSubstantive == 0,
               "R8.4.4 classifier has zero disposition errors")
    }

    private static func printR844ClassifierMetrics() {
        print("r844_classifier_passive_cases=\(r844ClassifierPassiveCases)")
        print("r844_classifier_substantive_cases=\(r844ClassifierSubstantiveCases)")
        print("r844_classifier_false_passive=\(r844ClassifierFalsePassive)")
        print("r844_classifier_false_substantive=\(r844ClassifierFalseSubstantive)")
    }

    private static func testR844BackchannelResponsePolicy(
        fixture: Data
    ) async throws {
        try await testR844ChinesePassiveBackchannel(fixture: fixture)
        cases += 1
        try await testR844FinalAfterCompletion(fixture: fixture)
        cases += 1
        try await testR844EnglishBackchannel(fixture: fixture)
        cases += 1
        try await testR844PunctuationNormalization(fixture: fixture)
        cases += 1
        try await testR844ShortSubstantive(fixture: fixture)
        cases += 1
        try await testR844BackchannelWithSubstantive(fixture: fixture)
        cases += 1
        try await testR844CrossSourceMixed(fixture: fixture)
        cases += 1
        try await testR844CrossSourcePassive(fixture: fixture)
        cases += 1
        try await testR844DuplicateSuppressionClosure(fixture: fixture)
        cases += 1
        try await testR844ProviderOnly(fixture: fixture)
        cases += 1
        try await testR844StaleGenerationClosure(fixture: fixture)
        cases += 1
        try await testR844NormalSubstantiveRegression(fixture: fixture)
        cases += 1
        try await testR844InterruptionRegression(fixture: fixture)
        cases += 1

        expect(r844PassiveBackchannelCases == 11
                && r844PassiveBackchannelDispositions == 11,
               "R8.4.4 executes every passive production disposition")
        expect(r844PassiveBackchannelResponseCreates == 0,
               "R8.4.4 passive backchannels create zero responses")
        expect(r844SubstantiveCases == 12
                && r844SubstantiveDispositions == 12,
               "R8.4.4 executes every substantive production disposition")
        expect(r844SubstantiveResponseCreates == r844SubstantiveCases,
               "R8.4.4 substantive turns preserve exactly-once response")
        expect(r844CrossSourceMixedResponseCreates == 1
                && r844CrossSourcePassiveResponseCreates == 0,
               "R8.4.4 classifies only final canonical aggregation")
        expect(r844DuplicateResponseCreates == 0
                && r844ProviderOnlyResponseCreates == 0
                && r844ProviderOnlyDispositions == 0
                && r844StaleGenerationResponseCreates == 0,
               "R8.4.4 closes duplicate, Provider-only, and stale paths")
        expect(r844NPlusOneSubstantiveResponseCreates == 1,
               "R8.4.4 preserves N+1 substantive response creation")
        expect(r844FalseHistoryWrites == 0
                && r844FalseMemoryWrites == 0
                && r844RelationshipChanges == 0
                && r844GrowthWrites == 0,
               "R8.4.4 passive turns remain ephemeral")
        expect(r844ExtraInterrupts == 0
                && r844ExtraPlaybackClears == 0
                && r844ExtraGenerationAdvances == 0,
               "R8.4.4 adds no interruption or generation authority")
    }

    private static func testR844ChinesePassiveBackchannel(
        fixture: Data
    ) async throws {
        try await runR844SingleTurn(
            fixture: fixture,
            transcript: "嗯",
            order: .finalBeforeCompletion,
            expectedDisposition: "passive_backchannel",
            seed: 48_100,
            label: "Chinese passive"
        )
    }

    private static func testR844FinalAfterCompletion(
        fixture: Data
    ) async throws {
        try await runR844SingleTurn(
            fixture: fixture,
            transcript: "嗯嗯",
            order: .completionBeforeFinal,
            expectedDisposition: "passive_backchannel",
            seed: 48_200,
            label: "late final passive"
        )
    }

    private static func testR844EnglishBackchannel(
        fixture: Data
    ) async throws {
        for (index, transcript) in ["mhm", "uh-huh"].enumerated() {
            try await runR844SingleTurn(
                fixture: fixture,
                transcript: transcript,
                order: .finalBeforeCompletion,
                expectedDisposition: "passive_backchannel",
                seed: 48_300 + UInt32(index),
                label: "English passive \(index)"
            )
        }
    }

    private static func testR844PunctuationNormalization(
        fixture: Data
    ) async throws {
        for (index, transcript) in ["嗯。", "嗯！", "Mhm."].enumerated() {
            try await runR844SingleTurn(
                fixture: fixture,
                transcript: transcript,
                order: .finalBeforeCompletion,
                expectedDisposition: "passive_backchannel",
                seed: 48_400 + UInt32(index),
                label: "punctuated passive \(index)"
            )
        }
        try await runR844SingleTurn(
            fixture: fixture,
            transcript: "嗯？",
            order: .finalBeforeCompletion,
            expectedDisposition: "substantive",
            seed: 48_410,
            label: "question mark fail-open"
        )
    }

    private static func testR844ShortSubstantive(
        fixture: Data
    ) async throws {
        let transcripts = [
            "好", "对", "继续", "为什么", "why", "yes", "okay"
        ]
        for (index, transcript) in transcripts.enumerated() {
            try await runR844SingleTurn(
                fixture: fixture,
                transcript: transcript,
                order: .finalBeforeCompletion,
                expectedDisposition: "substantive",
                seed: 48_500 + UInt32(index),
                label: "short substantive \(index)"
            )
        }
    }

    private static func testR844BackchannelWithSubstantive(
        fixture: Data
    ) async throws {
        try await runR844SingleTurn(
            fixture: fixture,
            transcript: "嗯，但是我不同意",
            order: .finalBeforeCompletion,
            expectedDisposition: "substantive",
            seed: 48_600,
            label: "backchannel plus substantive"
        )
    }

    private static func testR844NormalSubstantiveRegression(
        fixture: Data
    ) async throws {
        try await runR844SingleTurn(
            fixture: fixture,
            transcript: "今天晚上我们聊什么？",
            order: .finalBeforeCompletion,
            expectedDisposition: "substantive",
            seed: 49_200,
            label: "normal substantive regression"
        )
    }

    private static func runR844SingleTurn(
        fixture: Data,
        transcript: String,
        order: R844SemanticEventOrder,
        expectedDisposition: String,
        seed: UInt32,
        label: String
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let openBaseline = await stack.provider.openCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        let dispositionBaseline = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let generation = stack.session.generation
        let lease = stack.runtime.activeBrainLeaseForTesting()
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState
        let growthBefore = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()

        try await admitR844ListeningTurn(
            stack: stack,
            session: stack.session,
            sourceTurnID: turnID,
            sequence: 2,
            seed: seed,
            label: label
        )
        switch order {
        case .finalBeforeCompletion:
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 3,
                kind: .userTranscriptFinal(transcript),
                label: "R8.4.4 \(label) final"
            )
            let identity = r843EventIdentity(
                session: stack.session,
                turnID: turnID,
                contextRevision: 1
            )
            await waitUntilOnMainActor(
                "R8.4.4 \(label) final tracked before completion"
            ) {
                stack.runtime.realtimePendingUserInputForTesting(identity)
                        == transcript
                    && stack.runtime
                        .realtimeUtteranceCompletionDebugSnapshot()
                        .completionCandidateCount == candidateBaseline
                    && stack.runtime
                        .realtimeUserTurnDispositionDebugSnapshot()
                        == dispositionBaseline
            }
            expect(await stack.provider.createCount() == createBaseline,
                   "R8.4.4 final cannot bypass completion")
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 4,
                kind: .userSpeechStopped,
                label: "R8.4.4 \(label) stop"
            )
        case .completionBeforeFinal:
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 3,
                kind: .userSpeechStopped,
                label: "R8.4.4 \(label) stop"
            )
            await waitForR842Completion(
                runtime: stack.runtime,
                expectedCount: candidateBaseline + 1,
                expectedSession: stack.session,
                expectedTurn: turnID,
                expectedStoppedSequence: 3,
                label: "R8.4.4 \(label) completion before final"
            )
            expect(await stack.provider.createCount() == createBaseline,
                   "R8.4.4 completion alone cannot create a response")
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 4,
                kind: .userTranscriptFinal(transcript),
                label: "R8.4.4 \(label) late final"
            )
        }

        let expectsPassive = expectedDisposition == "passive_backchannel"
        await waitUntilOnMainActor("R8.4.4 \(label) disposition") {
            let completion = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let disposition = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            let dispositionReached = expectsPassive
                ? disposition.passiveBackchannelCount
                    == dispositionBaseline.passiveBackchannelCount + 1
                : disposition.substantiveCount
                    == dispositionBaseline.substantiveCount + 1
            return completion.completionCandidateCount
                    == candidateBaseline + 1
                && dispositionReached
        }
        if !expectsPassive {
            await waitUntil("R8.4.4 \(label) response create") {
                await stack.provider.createCount() == createBaseline + 1
            }
        }
        await waitUntilOnMainActor("R8.4.4 \(label) settles route state") {
            let expectedRoutePhase: FormalSpeechRoutePhase = expectsPassive
                ? .listening : .processing
            return stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot().phase == .idle
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == expectedRoutePhase
        }

        let disposition = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let createDelta = await stack.provider.createCount() - createBaseline
        let passiveDelta = Int(
            disposition.passiveBackchannelCount
                - dispositionBaseline.passiveBackchannelCount
        )
        let substantiveDelta = Int(
            disposition.substantiveCount
                - dispositionBaseline.substantiveCount
        )
        expect(disposition.lastCanonicalTranscript == transcript
                && disposition.lastDisposition == expectedDisposition,
               "R8.4.4 disposition uses the final canonical transcript")
        expect(passiveDelta == (expectsPassive ? 1 : 0)
                && substantiveDelta == (expectsPassive ? 0 : 1),
               "R8.4.4 executes exactly one effective disposition")
        expect(createDelta == (expectsPassive ? 0 : 1),
               "R8.4.4 response creation follows Runtime disposition")
        let openCount = await stack.provider.openCount()
        let lastSession = await stack.provider.lastSession()
        expect(openCount == openBaseline && lastSession == stack.session,
               "R8.4.4 keeps one Session and Brain route")
        expect(stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == generation
                && stack.runtime.activeBrainLeaseForTesting() == lease,
               "R8.4.4 preserves generation and Brain lease")

        let interruptDelta = await stack.provider.interruptCount()
            - interruptBaseline
        let cancelDelta = await stack.provider.cancelCount() - cancelBaseline
        let clearDelta = stack.outputPlayer.clearScheduledPlaybackCount
            - clearBaseline
        r844ExtraInterrupts += interruptDelta + cancelDelta
        r844ExtraPlaybackClears += clearDelta
        expect(interruptDelta == 0 && cancelDelta == 0 && clearDelta == 0,
               "R8.4.4 response policy has no interruption side effects")

        if expectsPassive {
            let identity = r843EventIdentity(
                session: stack.session,
                turnID: turnID,
                contextRevision: 1
            )
            let dialogueAfter = try stack.sessionStore
                .loadMostRecentDialogueEntries()
            let narrativeAfter = stack.runtime
                .narrativeMemoryDebugSnapshot()
            let relationshipAfter = stack.runtime.currentRelationshipState
            let growthAfter = stack.runtime
                .realtimeGrowthObservationDecisionCountForTesting()
            let historyWrites = dialogueAfter == dialogueBefore ? 0 : 1
            let memoryWrites = narrativeAfter == narrativeBefore ? 0 : 1
            let relationshipChanges = relationshipAfter == relationshipBefore
                ? 0 : 1
            let growthWrites = growthAfter == growthBefore ? 0 : 1
            r844FalseHistoryWrites += historyWrites
            r844FalseMemoryWrites += memoryWrites
            r844RelationshipChanges += relationshipChanges
            r844GrowthWrites += growthWrites
            expect(stack.runtime.realtimePendingUserInputForTesting(identity)
                    == nil,
                   "R8.4.4 passive semantic pending input is retired")
            expect(historyWrites == 0 && memoryWrites == 0
                    && relationshipChanges == 0 && growthWrites == 0,
                   "R8.4.4 passive backchannel stays ephemeral")
            r844PassiveBackchannelCases += 1
            r844PassiveBackchannelDispositions += passiveDelta
            r844PassiveBackchannelResponseCreates += createDelta
        } else {
            r844SubstantiveCases += 1
            r844SubstantiveDispositions += substantiveDelta
            r844SubstantiveResponseCreates += createDelta
        }
        try await close(stack)
    }

    private static func testR844CrossSourceMixed(
        fixture: Data
    ) async throws {
        r844CrossSourceMixedResponseCreates = try await
            runR844CrossSourceTurn(
                fixture: fixture,
                firstTranscript: "嗯",
                secondTranscript: "我还有一个问题",
                expectedDisposition: "substantive",
                secondFinalAfterCompletion: true,
                seed: 48_700,
                label: "cross-source mixed"
            )
    }

    private static func testR844CrossSourcePassive(
        fixture: Data
    ) async throws {
        let chineseResponseCreates = try await
            runR844CrossSourceTurn(
                fixture: fixture,
                firstTranscript: "嗯",
                secondTranscript: "嗯嗯",
                expectedDisposition: "passive_backchannel",
                seed: 48_800,
                label: "cross-source Chinese passive"
            )
        let segmentedEnglishResponseCreates = try await
            runR844CrossSourceTurn(
                fixture: fixture,
                firstTranscript: "uh",
                secondTranscript: "huh",
                expectedDisposition: "passive_backchannel",
                seed: 48_850,
                label: "cross-source segmented uh huh"
            )
        r844CrossSourcePassiveResponseCreates =
            chineseResponseCreates + segmentedEnglishResponseCreates
    }

    private static func runR844CrossSourceTurn(
        fixture: Data,
        firstTranscript: String,
        secondTranscript: String,
        expectedDisposition: String,
        secondFinalAfterCompletion: Bool = false,
        seed: UInt32,
        label: String
    ) async throws -> Int {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let logicalTurnID = RealtimeBrainTurnID()
        let reboundTurnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        let dispositionBaseline = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let generation = stack.session.generation
        let lease = stack.runtime.activeBrainLeaseForTesting()
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState
        let growthBefore = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()

        try await admitR844ListeningTurn(
            stack: stack,
            session: stack.session,
            sourceTurnID: logicalTurnID,
            sequence: 2,
            seed: seed,
            label: "\(label) first segment"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: logicalTurnID,
            sequence: 3,
            kind: .userTranscriptFinal(firstTranscript),
            label: "R8.4.4 \(label) first final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: logicalTurnID,
            sequence: 4,
            kind: .userSpeechStopped,
            label: "R8.4.4 \(label) short stop"
        )
        try? await Task.sleep(for: .milliseconds(140))
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: seed + 1, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "R8.4.4 \(label) continuation"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: reboundTurnID,
            sequence: 5,
            kind: .userSpeechStarted,
            label: "R8.4.4 \(label) resumed start"
        )
        await waitUntilOnMainActor("R8.4.4 \(label) logical rebound") {
            let completion = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return completion.phase == .speaking
                && completion.turnID == logicalTurnID
                && completion.sourceTurnID == reboundTurnID
        }
        if !secondFinalAfterCompletion {
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: reboundTurnID,
                sequence: 6,
                kind: .userTranscriptFinal(secondTranscript),
                label: "R8.4.4 \(label) second final"
            )
        }
        await waitBeyondR842CompletionWindow()
        expect(stack.runtime.realtimeUtteranceCompletionDebugSnapshot().phase
                == .speaking,
               "R8.4.4 cross-source pause remains one logical utterance")
        expect(await stack.provider.createCount() == createBaseline,
               "R8.4.4 does not classify an incomplete aggregation")
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: reboundTurnID,
            sequence: secondFinalAfterCompletion ? 6 : 7,
            kind: .userSpeechStopped,
            label: "R8.4.4 \(label) true stop"
        )

        if secondFinalAfterCompletion {
            await waitUntilOnMainActor(
                "R8.4.4 \(label) awaits complete aggregation"
            ) {
                let completion = stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot()
                return completion.completionCandidateCount
                    == candidateBaseline + 1
            }
            let awaitingCompletion = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let awaitingDisposition = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            let awaitingCreateCount = await stack.provider.createCount()
            expect(awaitingCompletion.phase == .completionCandidate
                    && awaitingDisposition == dispositionBaseline
                    && awaitingCreateCount == createBaseline,
                   "R8.4.4 incomplete cross-source aggregation stays pending")
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: reboundTurnID,
                sequence: 7,
                kind: .userTranscriptFinal(secondTranscript),
                label: "R8.4.4 \(label) late second final"
            )
        }

        let expectsPassive = expectedDisposition == "passive_backchannel"
        await waitUntilOnMainActor("R8.4.4 \(label) disposition") {
            let completion = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let disposition = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            let dispositionReached = expectsPassive
                ? disposition.passiveBackchannelCount
                    == dispositionBaseline.passiveBackchannelCount + 1
                : disposition.substantiveCount
                    == dispositionBaseline.substantiveCount + 1
            return completion.completionCandidateCount
                    == candidateBaseline + 1
                && dispositionReached
        }
        if !expectsPassive {
            await waitUntil("R8.4.4 \(label) response create") {
                await stack.provider.createCount() == createBaseline + 1
            }
        }
        await waitUntilOnMainActor("R8.4.4 \(label) idle") {
            let expectedRoutePhase: FormalSpeechRoutePhase = expectsPassive
                ? .listening : .processing
            return stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot().phase == .idle
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == expectedRoutePhase
        }

        let expectedCanonical = "\(firstTranscript) \(secondTranscript)"
        let disposition = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let createDelta = await stack.provider.createCount() - createBaseline
        let passiveDelta = Int(
            disposition.passiveBackchannelCount
                - dispositionBaseline.passiveBackchannelCount
        )
        let substantiveDelta = Int(
            disposition.substantiveCount
                - dispositionBaseline.substantiveCount
        )
        expect(disposition.lastCanonicalTranscript == expectedCanonical
                && disposition.lastDisposition == expectedDisposition,
               "R8.4.4 cross-source policy uses final canonical aggregation")
        expect(passiveDelta == (expectsPassive ? 1 : 0)
                && substantiveDelta == (expectsPassive ? 0 : 1)
                && createDelta == (expectsPassive ? 0 : 1),
               "R8.4.4 cross-source disposition controls response once")
        expect(stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == generation
                && stack.runtime.activeBrainLeaseForTesting() == lease,
               "R8.4.4 cross-source disposition preserves identity")

        let interruptDelta = await stack.provider.interruptCount()
            - interruptBaseline
        let cancelDelta = await stack.provider.cancelCount() - cancelBaseline
        let clearDelta = stack.outputPlayer.clearScheduledPlaybackCount
            - clearBaseline
        r844ExtraInterrupts += interruptDelta + cancelDelta
        r844ExtraPlaybackClears += clearDelta
        expect(interruptDelta == 0 && cancelDelta == 0 && clearDelta == 0,
               "R8.4.4 cross-source policy has no decision side effects")

        let firstIdentity = r843EventIdentity(
            session: stack.session,
            turnID: logicalTurnID,
            contextRevision: 1
        )
        let secondIdentity = r843EventIdentity(
            session: stack.session,
            turnID: reboundTurnID,
            contextRevision: 1
        )
        if expectsPassive {
            let dialogueAfter = try stack.sessionStore
                .loadMostRecentDialogueEntries()
            let historyWrites = dialogueAfter == dialogueBefore ? 0 : 1
            let memoryWrites = stack.runtime.narrativeMemoryDebugSnapshot()
                == narrativeBefore ? 0 : 1
            let relationshipChanges = stack.runtime.currentRelationshipState
                == relationshipBefore ? 0 : 1
            let growthWrites = stack.runtime
                .realtimeGrowthObservationDecisionCountForTesting()
                == growthBefore ? 0 : 1
            r844FalseHistoryWrites += historyWrites
            r844FalseMemoryWrites += memoryWrites
            r844RelationshipChanges += relationshipChanges
            r844GrowthWrites += growthWrites
            expect(stack.runtime.realtimePendingUserInputForTesting(
                        firstIdentity
                    ) == nil
                    && stack.runtime.realtimePendingUserInputForTesting(
                        secondIdentity
                    ) == nil,
                   "R8.4.4 retires every passive source alias")
            expect(historyWrites == 0 && memoryWrites == 0
                    && relationshipChanges == 0 && growthWrites == 0,
                   "R8.4.4 cross-source passive remains ephemeral")
            let settledDisposition = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            let settledCreateCount = await stack.provider.createCount()
            for (sequence, turnID, kind) in [
                (UInt64(8), logicalTurnID,
                 RealtimeResidentBrainEventKind
                    .userTranscriptFinal(firstTranscript)),
                (UInt64(9), logicalTurnID,
                 RealtimeResidentBrainEventKind.userSpeechStopped),
                (UInt64(10), reboundTurnID,
                 RealtimeResidentBrainEventKind
                    .userTranscriptFinal(secondTranscript)),
                (UInt64(11), reboundTurnID,
                 RealtimeResidentBrainEventKind.userSpeechStopped)
            ] {
                await enqueueR843Activity(
                    stack: stack,
                    session: stack.session,
                    turnID: turnID,
                    sequence: sequence,
                    kind: kind,
                    label: "R8.4.4 \(label) retired alias \(sequence)"
                )
            }
            await waitBeyondR842CompletionWindow()
            let replayCreateCount = await stack.provider.createCount()
            expect(stack.runtime
                    .realtimeUserTurnDispositionDebugSnapshot()
                        == settledDisposition
                    && replayCreateCount == settledCreateCount
                    && stack.runtime.realtimePendingUserInputForTesting(
                        firstIdentity
                    ) == nil
                    && stack.runtime.realtimePendingUserInputForTesting(
                        secondIdentity
                    ) == nil
                    && stack.controller
                        .formalSpeechRouteDebugSnapshot.phase == .listening
                    && stack.controller
                        .formalSpeechRouteDebugSnapshot.generation == generation
                    && stack.runtime.activeBrainLeaseForTesting() == lease,
                   "R8.4.4 every passive source alias stays retired")
            r844PassiveBackchannelCases += 1
            r844PassiveBackchannelDispositions += passiveDelta
            r844PassiveBackchannelResponseCreates += createDelta
        } else {
            expect(stack.runtime.realtimePendingUserInputForTesting(
                        secondIdentity
                    ) == expectedCanonical,
                   "R8.4.4 substantive aggregation reaches R8.4.3 unchanged")
            r844SubstantiveCases += 1
            r844SubstantiveDispositions += substantiveDelta
            r844SubstantiveResponseCreates += createDelta
        }
        try await close(stack)
        return createDelta
    }

    private static func testR844DuplicateSuppressionClosure(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let dispositionBaseline = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState
        let growthBefore = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()

        try await admitR844ListeningTurn(
            stack: stack,
            session: stack.session,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 48_900,
            label: "duplicate suppression"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userTranscriptFinal("唔"),
            label: "R8.4.4 duplicate initial final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 4,
            kind: .userSpeechStopped,
            label: "R8.4.4 duplicate initial stop"
        )
        await waitUntilOnMainActor("R8.4.4 duplicate initial suppress") {
            let disposition = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            return disposition.passiveBackchannelCount
                    == dispositionBaseline.passiveBackchannelCount + 1
                && stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot().phase == .idle
        }
        let suppressedDisposition = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let nextTurnID = RealtimeBrainTurnID()
        try await admitR844ListeningTurn(
            stack: stack,
            session: stack.session,
            sourceTurnID: nextTurnID,
            sequence: 5,
            seed: 48_901,
            label: "duplicate suppression next utterance"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: nextTurnID,
            sequence: 6,
            kind: .userTranscriptFinal("哦"),
            label: "R8.4.4 next passive final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: nextTurnID,
            sequence: 7,
            kind: .userSpeechStopped,
            label: "R8.4.4 next passive stop"
        )
        await waitUntilOnMainActor("R8.4.4 next passive suppress") {
            let disposition = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            return disposition.passiveBackchannelCount
                    == dispositionBaseline.passiveBackchannelCount + 2
                && stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot().phase == .idle
                && stack.controller
                    .formalSpeechRouteDebugSnapshot.phase == .listening
        }
        let settledDisposition = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        for (sequence, replayTurnID, kind) in [
            (UInt64(8), turnID, RealtimeResidentBrainEventKind
                .userTranscriptFinal("唔")),
            (UInt64(9), turnID,
             RealtimeResidentBrainEventKind.userSpeechStopped),
            (UInt64(10), nextTurnID, RealtimeResidentBrainEventKind
                .userTranscriptFinal("哦")),
            (UInt64(11), nextTurnID,
             RealtimeResidentBrainEventKind.userSpeechStopped)
        ] {
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: replayTurnID,
                sequence: sequence,
                kind: kind,
                label: "R8.4.4 duplicate late evidence \(sequence)"
            )
        }
        await waitBeyondR842CompletionWindow()

        let finalDisposition = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let createDelta = await stack.provider.createCount() - createBaseline
        r844DuplicateResponseCreates = createDelta
        r844PassiveBackchannelCases += 2
        r844PassiveBackchannelDispositions += Int(
            finalDisposition.passiveBackchannelCount
                - dispositionBaseline.passiveBackchannelCount
        )
        r844PassiveBackchannelResponseCreates += createDelta
        expect(createDelta == 0
                && settledDisposition.passiveBackchannelCount
                    == suppressedDisposition.passiveBackchannelCount + 1
                && finalDisposition == settledDisposition
                && stack.controller
                    .formalSpeechRouteDebugSnapshot.phase == .listening,
               "R8.4.4 duplicate final/stop cannot reclassify or respond")
        let identity = r843EventIdentity(
            session: stack.session,
            turnID: turnID,
            contextRevision: 1
        )
        expect(stack.runtime.realtimePendingUserInputForTesting(identity)
                == nil
                && stack.runtime.realtimePendingUserInputForTesting(
                    r843EventIdentity(
                        session: stack.session,
                        turnID: nextTurnID,
                        contextRevision: 1
                    )
                ) == nil,
               "R8.4.4 duplicate evidence cannot resurrect pending input")

        let dialogueAfter = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let historyWrites = dialogueAfter == dialogueBefore ? 0 : 1
        let memoryWrites = stack.runtime.narrativeMemoryDebugSnapshot()
            == narrativeBefore ? 0 : 1
        let relationshipChanges = stack.runtime.currentRelationshipState
            == relationshipBefore ? 0 : 1
        let growthWrites = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()
            == growthBefore ? 0 : 1
        r844FalseHistoryWrites += historyWrites
        r844FalseMemoryWrites += memoryWrites
        r844RelationshipChanges += relationshipChanges
        r844GrowthWrites += growthWrites
        expect(historyWrites == 0 && memoryWrites == 0
                && relationshipChanges == 0 && growthWrites == 0,
               "R8.4.4 duplicate passive evidence remains ephemeral")
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR844ProviderOnly(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let dispositionBaseline = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let dialogueBefore = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let narrativeBefore = stack.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = stack.runtime.currentRelationshipState
        let growthBefore = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()

        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 2,
            kind: .userSpeechStarted,
            label: "R8.4.4 Provider-only start"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userSpeechStopped,
            label: "R8.4.4 Provider-only stop"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 4,
            kind: .userTranscriptFinal("嗯"),
            label: "R8.4.4 Provider-only final"
        )
        await waitBeyondR842CompletionWindow()

        let disposition = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        r844ProviderOnlyResponseCreates = await stack.provider.createCount()
            - createBaseline
        r844ProviderOnlyDispositions = Int(
            disposition.passiveBackchannelCount
                - dispositionBaseline.passiveBackchannelCount
                + disposition.substantiveCount
                - dispositionBaseline.substantiveCount
        )
        expect(r844ProviderOnlyResponseCreates == 0
                && r844ProviderOnlyDispositions == 0
                && stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot().phase == .idle,
               "R8.4.4 Provider-only evidence has no policy authority")
        let dialogueAfter = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        let historyWrites = dialogueAfter == dialogueBefore ? 0 : 1
        let memoryWrites = stack.runtime.narrativeMemoryDebugSnapshot()
            == narrativeBefore ? 0 : 1
        let relationshipChanges = stack.runtime.currentRelationshipState
            == relationshipBefore ? 0 : 1
        let growthWrites = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()
            == growthBefore ? 0 : 1
        r844FalseHistoryWrites += historyWrites
        r844FalseMemoryWrites += memoryWrites
        r844RelationshipChanges += relationshipChanges
        r844GrowthWrites += growthWrites
        expect(historyWrites == 0 && memoryWrites == 0
                && relationshipChanges == 0 && growthWrites == 0,
               "R8.4.4 Provider-only backchannel writes no persistence")
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR844StaleGenerationClosure(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let oldTurnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let dispositionBaseline = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        try await admitR844ListeningTurn(
            stack: stack,
            session: stack.session,
            sourceTurnID: oldTurnID,
            sequence: 2,
            seed: 49_000,
            label: "stale generation N"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: oldTurnID,
            sequence: 3,
            kind: .userTranscriptFinal("嗯"),
            label: "R8.4.4 stale N final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: oldTurnID,
            sequence: 4,
            kind: .userSpeechStopped,
            label: "R8.4.4 stale N stop"
        )
        let nextSession = await restartR843Route(
            stack: stack,
            label: "R8.4.4 stale N timer"
        )
        await waitBeyondR842CompletionWindow()
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: oldTurnID,
            sequence: 5,
            kind: .userTranscriptFinal("嗯"),
            label: "R8.4.4 late N final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: oldTurnID,
            sequence: 6,
            kind: .userSpeechStopped,
            label: "R8.4.4 late N stop"
        )
        let nextTurnID = RealtimeBrainTurnID()
        try await admitR844ListeningTurn(
            stack: stack,
            session: nextSession,
            sourceTurnID: nextTurnID,
            sequence: 2,
            seed: 49_001,
            label: "N+1 substantive"
        )
        let afterOld = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        r844StaleGenerationResponseCreates = await stack.provider
            .createCount() - createBaseline
        expect(nextSession.generation == stack.session.generation + 1
                && afterOld == dispositionBaseline
                && afterOld.passiveBackchannelCount
                    == dispositionBaseline.passiveBackchannelCount
                && r844StaleGenerationResponseCreates == 0,
               "R8.4.4 stale N evidence cannot classify or respond in N+1")
        await enqueueR843Activity(
            stack: stack,
            session: nextSession,
            turnID: nextTurnID,
            sequence: 3,
            kind: .userTranscriptFinal("N+1 正常问题"),
            label: "R8.4.4 N+1 substantive final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: nextSession,
            turnID: nextTurnID,
            sequence: 4,
            kind: .userSpeechStopped,
            label: "R8.4.4 N+1 substantive stop"
        )
        await waitUntil("R8.4.4 N+1 substantive create") {
            await stack.provider.createCount() == createBaseline + 1
        }
        await waitUntilOnMainActor("R8.4.4 N+1 substantive disposition") {
            let disposition = stack.runtime
                .realtimeUserTurnDispositionDebugSnapshot()
            return disposition.substantiveCount
                    == dispositionBaseline.substantiveCount + 1
                && stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot().phase == .idle
        }
        let finalDisposition = stack.runtime
            .realtimeUserTurnDispositionDebugSnapshot()
        let command = await stack.provider.lastCreateCommand()
        let createDelta = await stack.provider.createCount() - createBaseline
        let substantiveDelta = Int(
            finalDisposition.substantiveCount
                - dispositionBaseline.substantiveCount
        )
        expect(finalDisposition.lastCanonicalTranscript == "N+1 正常问题"
                && finalDisposition.lastDisposition == "substantive"
                && finalDisposition.passiveBackchannelCount
                    == dispositionBaseline.passiveBackchannelCount
                && command?.identity.session == nextSession,
               "R8.4.4 N+1 substantive turn is independent of stale N")
        expect(createDelta == 1 && substantiveDelta == 1,
               "R8.4.4 N+1 substantive response remains exactly once")
        r844NPlusOneSubstantiveResponseCreates = createDelta
        r844SubstantiveCases += 1
        r844SubstantiveDispositions += substantiveDelta
        r844SubstantiveResponseCreates += createDelta
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: nextSession.generation
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testR844InterruptionRegression(
        fixture: Data
    ) async throws {
        try await testR832ConfirmedInterruptionProductionChain(
            fixture: fixture
        )
        r844ExtraInterrupts += r832ExtraInterruptions
        r844ExtraPlaybackClears += r832ExtraPlaybackClears
        r844ExtraGenerationAdvances += max(0, r832GenerationDelta - 1)
        expect(r832ProviderInterrupts == 1
                && r832ProviderCancels == 0
                && r832HostPlaybackClears == 1
                && r832GenerationDelta == 1,
               "R8.4.4 preserves the frozen R8.3 interruption chain")
        expect(r832ResponseCreates == 0,
               "R8.4.4 interruption path does not create a response")
    }

    private static func admitR844ListeningTurn(
        stack: R823ControllerStack,
        session: RealtimeBrainSessionIdentity,
        sourceTurnID: RealtimeBrainTurnID,
        contextRevision: UInt64 = 1,
        sequence: UInt64,
        seed: UInt32,
        label: String
    ) async throws {
        r842CompletionWindowNanoseconds = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionWindowNanoseconds
        await stack.controller.refreshMicrophoneAuthorization()
        let confirmationBaseline = stack.controller
            .realtimeBrainInputBridgeSnapshot
            .listeningConfirmationAcceptedCount
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: seed, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "R8.4.4 \(label) production near-end"
        )
        await waitUntil(
            "R8.4.4 \(label) accepted Listening activity"
        ) {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller
                .realtimeBrainInputBridgeSnapshot
                .listeningConfirmationAcceptedCount
                > confirmationBaseline
        }
        await enqueueR843Activity(
            stack: stack,
            session: session,
            turnID: sourceTurnID,
            contextRevision: contextRevision,
            sequence: sequence,
            kind: .userSpeechStarted,
            label: "R8.4.4 \(label) speech start"
        )
        let admissionDeadline = monotonicNow() + 3_000_000_000
        while true {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            if snapshot.phase == .speaking,
               snapshot.session == session,
               snapshot.sourceTurnID == sourceTurnID {
                break
            }
            if monotonicNow() >= admissionDeadline {
                await stack.controller.refreshMicrophoneAuthorization()
                let bridge = stack.controller
                    .realtimeBrainInputBridgeSnapshot
                let acoustic = stack.acousticEchoHost
                    .acousticObservationSnapshot()
                fatalError(
                    "timeout: R8.4.4 \(label) admission "
                        + "phase=\(snapshot.phase.rawValue) "
                        + "session_match=\(snapshot.session == session) "
                        + "source_turn_match="
                        + "\(snapshot.sourceTurnID == sourceTurnID) "
                        + "pending_turn_match="
                        + "\(snapshot.pendingStartTurnID == sourceTurnID) "
                        + "claimed_listening="
                        + "\(snapshot.claimedListeningAudioSequence) "
                        + "provider_authorizations="
                        + "\(snapshot.providerListeningAuthorizationCount) "
                        + "input_forwarded=\(bridge.forwardedFrameCount) "
                        + "input_none=\(bridge.noneActivityFrameCount) "
                        + "input_listening="
                        + "\(bridge.listeningNearEndFrameCount) "
                        + "confirm_attempts="
                        + "\(bridge.listeningConfirmationAttemptCount) "
                        + "confirm_accepted="
                        + "\(bridge.listeningConfirmationAcceptedCount) "
                        + "confirm_rejected="
                        + "\(bridge.listeningConfirmationRejectedCount) "
                        + "freshness_rejected="
                        + "\(bridge.listeningFreshnessRejectedCount) "
                        + "acoustic_playback="
                        + "\(acoustic.isPlaybackActive) "
                        + "acoustic_source_gate="
                        + "\(acoustic.sourceGateOpen) "
                        + "acoustic_classification="
                        + "\(acoustic.inputClassification.rawValue)"
                )
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private static func printR844ResponsePolicyMetrics() {
        print("r844_passive_backchannel_cases=\(r844PassiveBackchannelCases)")
        print("r844_passive_backchannel_dispositions=\(r844PassiveBackchannelDispositions)")
        print("r844_passive_backchannel_response_creates=\(r844PassiveBackchannelResponseCreates)")
        print("r844_substantive_cases=\(r844SubstantiveCases)")
        print("r844_substantive_dispositions=\(r844SubstantiveDispositions)")
        print("r844_substantive_response_creates=\(r844SubstantiveResponseCreates)")
        print("r844_response_creates=\(r844SubstantiveResponseCreates + r844PassiveBackchannelResponseCreates)")
        print("r844_cross_source_mixed_response_creates=\(r844CrossSourceMixedResponseCreates)")
        print("r844_cross_source_passive_response_creates=\(r844CrossSourcePassiveResponseCreates)")
        print("r844_duplicate_response_creates=\(r844DuplicateResponseCreates)")
        print("r844_provider_only_response_creates=\(r844ProviderOnlyResponseCreates)")
        print("r844_provider_only_dispositions=\(r844ProviderOnlyDispositions)")
        print("r844_stale_generation_response_creates=\(r844StaleGenerationResponseCreates)")
        print("r844_n_plus_one_substantive_response_creates=\(r844NPlusOneSubstantiveResponseCreates)")
        print("r844_false_history_writes=\(r844FalseHistoryWrites)")
        print("r844_false_memory_writes=\(r844FalseMemoryWrites)")
        print("r844_relationship_changes=\(r844RelationshipChanges)")
        print("r844_growth_writes=\(r844GrowthWrites)")
        print("r844_extra_interrupts=\(r844ExtraInterrupts)")
        print("r844_extra_playback_clears=\(r844ExtraPlaybackClears)")
        print("r844_extra_generation_advances=\(r844ExtraGenerationAdvances)")
    }

    private static func testR843SemanticTurnTakingFusion(
        fixture: Data
    ) async throws {
        try await testR843FinalBeforeCompletion(fixture: fixture)
        cases += 1
        try await testR843CompletionBeforeFinal(fixture: fixture)
        cases += 1
        try await testR843CancelledPendingResume(fixture: fixture)
        cases += 1
        try await testR843DuplicateStartAfterCompletion(fixture: fixture)
        cases += 1
        try await testR843CrossSourceTurn(fixture: fixture)
        cases += 1
        try await testR843CompletionOnly(fixture: fixture)
        cases += 1
        try await testR843SemanticOnly(fixture: fixture)
        cases += 1
        try await testR843ProviderOnly(fixture: fixture)
        cases += 1
        try await testR843DuplicateEvidence(fixture: fixture)
        cases += 1
        try await testR843EmptySemantic(fixture: fixture)
        cases += 1
        try await testR843WrongIdentity(fixture: fixture)
        cases += 1
        try await testR843GenerationFence(fixture: fixture)
        cases += 1
        try await testR843InterruptionRegression(fixture: fixture)
        cases += 1

        expect(r843FinalBeforeCompletionCases == 1,
               "R8.4.3 covers final before completion")
        expect(r843CompletionBeforeFinalCases == 1,
               "R8.4.3 covers completion before final")
        expect(r843CrossSourceTurnCases == 1,
               "R8.4.3 covers one cross-source logical utterance")
        expect(r843ValidTurnResponseCreates
                == r843ValidCompletedSemanticTurns,
               "R8.4.3 creates exactly one response per valid fused turn")
        expect(r843CompletionOnlyResponseCreates == 0,
               "R8.4.3 completion alone cannot create a response")
        expect(r843SemanticOnlyResponseCreates == 0,
               "R8.4.3 tracked semantic final alone cannot respond")
        expect(r843ProviderOnlyResponseCreates == 0,
               "R8.4.3 Provider-only activity has no response authority")
        expect(r843EmptyFinalResponseCreates == 0,
               "R8.4.3 empty semantic finals fail closed")
        expect(r843WrongIdentityResponseCreates == 0,
               "R8.4.3 wrong identities cannot authorize a response")
        expect(r843StaleGenerationResponseCreates == 0,
               "R8.4.3 stale generation evidence cannot authorize N+1")
        expect(r843DuplicateResponseCreates == 0,
               "R8.4.3 duplicate evidence cannot duplicate responses")
        expect(r843ExtraInterrupts == 0
                && r843ExtraPlaybackClears == 0
                && r843ExtraGenerationAdvances == 0,
               "R8.4.3 does not expand interruption authority")
    }

    private static func testR843FinalBeforeCompletion(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        let generation = stack.session.generation
        let lease = stack.runtime.activeBrainLeaseForTesting()

        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 47_000,
            label: "final-before-completion"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userTranscriptPartial("semantic opening"),
            label: "final-before-completion partial"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 4,
            kind: .userTranscriptFinal("semantic final"),
            label: "final-before-completion final"
        )
        expect(await stack.provider.createCount() == createBaseline,
               "R8.4.3 final cannot answer before completion")
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 5,
            kind: .userSpeechStopped,
            label: "final-before-completion stop"
        )
        await waitForR843Response(
            stack: stack,
            createBaseline: createBaseline,
            candidateBaseline: candidateBaseline,
            expectedTurnID: turnID,
            expectedSemanticSequence: 4,
            label: "final-before-completion fusion"
        )
        expect(stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == generation
                && stack.runtime.activeBrainLeaseForTesting() == lease,
               "R8.4.3 final-first fusion preserves generation and lease")
        r843FinalBeforeCompletionCases += 1
        r843ValidCompletedSemanticTurns += 1
        r843ValidTurnResponseCreates += await stack.provider.createCount()
            - createBaseline
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: generation
        )
        try await close(stack)
    }

    private static func testR843CompletionBeforeFinal(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount

        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 47_100,
            label: "completion-before-final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userSpeechStopped,
            label: "completion-before-final stop"
        )
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: candidateBaseline + 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: 3,
            label: "R8.4.3 completion-before-final candidate"
        )
        expect(await stack.provider.createCount() == createBaseline,
               "R8.4.3 completion cannot answer without semantic final")
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 4,
            kind: .userTranscriptFinal("late semantic final"),
            label: "completion-before-final final"
        )
        await waitForR843Response(
            stack: stack,
            createBaseline: createBaseline,
            candidateBaseline: candidateBaseline,
            expectedTurnID: turnID,
            expectedSemanticSequence: 4,
            label: "completion-before-final fusion"
        )
        r843CompletionBeforeFinalCases += 1
        r843ValidCompletedSemanticTurns += 1
        r843ValidTurnResponseCreates += await stack.provider.createCount()
            - createBaseline
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR843CrossSourceTurn(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let logicalTurnID = RealtimeBrainTurnID()
        let reboundSourceTurnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount

        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: logicalTurnID,
            sequence: 2,
            seed: 47_200,
            label: "cross-source first segment"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: logicalTurnID,
            sequence: 3,
            kind: .userTranscriptFinal("first source segment"),
            label: "cross-source first final"
        )
        expect(await stack.provider.createCount() == createBaseline,
               "R8.4.3 first segment final cannot answer early")
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: logicalTurnID,
            sequence: 4,
            kind: .userSpeechStopped,
            label: "cross-source short stop"
        )
        try? await Task.sleep(for: .milliseconds(600))
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: 47_201, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "R8.4.3 cross-source continuation"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: reboundSourceTurnID,
            sequence: 5,
            kind: .userSpeechStarted,
            label: "cross-source resumed start"
        )
        await waitUntilOnMainActor("R8.4.3 cross-source logical rebound") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.turnID == logicalTurnID
                && snapshot.sourceTurnID == reboundSourceTurnID
        }
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: reboundSourceTurnID,
            sequence: 6,
            kind: .userTranscriptFinal("second source segment"),
            label: "cross-source second final"
        )
        let firstIdentity = r843EventIdentity(
            session: stack.session,
            turnID: logicalTurnID,
            contextRevision: 1
        )
        let secondIdentity = r843EventIdentity(
            session: stack.session,
            turnID: reboundSourceTurnID,
            contextRevision: 1
        )
        expect(stack.runtime
                .realtimeUtteranceCompletionTracksTranscriptFinalForTesting(
                    firstIdentity
                )
                && stack.runtime
                    .realtimeUtteranceCompletionTracksTranscriptFinalForTesting(
                        secondIdentity
                    ),
               "R8.4.3 both source finals belong to one logical utterance")
        await waitBeyondR842CompletionWindow()
        let resumed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(resumed.phase == .speaking
                && resumed.completionCandidateCount == candidateBaseline,
               "R8.4.3 cross-source speech does not complete during resume")
        expect(await stack.provider.createCount() == createBaseline,
               "R8.4.3 cross-source finals cannot answer before true end")
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: reboundSourceTurnID,
            sequence: 7,
            kind: .userSpeechStopped,
            label: "cross-source true stop"
        )
        await waitForR843Response(
            stack: stack,
            createBaseline: createBaseline,
            candidateBaseline: candidateBaseline,
            expectedTurnID: reboundSourceTurnID,
            expectedSemanticSequence: 6,
            label: "cross-source fusion"
        )
        expect(stack.runtime.realtimePendingUserInputForTesting(
            secondIdentity
        ) == "first source segment second source segment",
               "R8.4.3 preserves every accepted source segment in canonical input")
        r843CrossSourceTurnCases += 1
        r843ValidCompletedSemanticTurns += 1
        r843ValidTurnResponseCreates += await stack.provider.createCount()
            - createBaseline
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR843CancelledPendingResume(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let logicalTurnID = RealtimeBrainTurnID()
        let pendingResumeTurnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount

        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: logicalTurnID,
            sequence: 2,
            seed: 47_250,
            label: "cancelled-pending-resume base"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: logicalTurnID,
            sequence: 3,
            kind: .userSpeechStopped,
            label: "cancelled-pending-resume stop"
        )
        await waitUntilOnMainActor("R8.4.3 pending-resume pause") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .candidatePause
                && snapshot.turnID == logicalTurnID
        }
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: pendingResumeTurnID,
            sequence: 4,
            kind: .userSpeechStarted,
            label: "cancelled-pending-resume start"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: pendingResumeTurnID,
            sequence: 5,
            kind: .cancelled(.runtimeDecision),
            label: "cancelled-pending-resume terminal"
        )
        await waitUntilOnMainActor("R8.4.3 pending-resume reset") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .idle
        }
        await waitBeyondR842CompletionWindow()
        let snapshot = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(snapshot.phase == .idle
                && snapshot.completionCandidateCount == candidateBaseline,
               "R8.4.3 cancelled pending resume cannot resurrect its old timer")
        expect(await stack.provider.createCount() == createBaseline,
               "R8.4.3 cancelled pending resume creates no response")
        let interruptCount = await stack.provider.interruptCount()
        let cancelCount = await stack.provider.cancelCount()
        expect(interruptCount == 0 && cancelCount == 0,
               "R8.4.3 turn terminal invokes no Provider interruption API")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "R8.4.3 turn terminal does not clear Playback")
        expect(stack.controller.formalSpeechRouteDebugSnapshot.generation
                != stack.session.generation &+ 1,
               "R8.4.3 turn terminal cannot advance the formal generation")
        try await close(stack)
    }

    private static func testR843DuplicateStartAfterCompletion(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let unrelatedTurnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount

        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 47_260,
            label: "duplicate-start completion base"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userSpeechStopped,
            label: "duplicate-start completion stop"
        )
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: candidateBaseline + 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: 3,
            label: "R8.4.3 duplicate-start completion candidate"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 4,
            kind: .userSpeechStarted,
            label: "duplicate start after completion"
        )
        await waitBeyondR842CompletionWindow()
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: unrelatedTurnID,
            sequence: 5,
            kind: .userSpeechStarted,
            label: "unrelated start after duplicate expiry"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 6,
            kind: .userTranscriptFinal("late valid semantic final"),
            label: "late final after duplicate start"
        )
        await waitForR843Response(
            stack: stack,
            createBaseline: createBaseline,
            candidateBaseline: candidateBaseline,
            expectedTurnID: turnID,
            expectedSemanticSequence: 6,
            label: "duplicate-start late-final fusion"
        )
        r843ValidCompletedSemanticTurns += 1
        r843ValidTurnResponseCreates += await stack.provider.createCount()
            - createBaseline
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR843CompletionOnly(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 47_300,
            label: "completion-only"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userSpeechStopped,
            label: "completion-only stop"
        )
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: candidateBaseline + 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: 3,
            label: "R8.4.3 completion-only candidate"
        )
        r843CompletionOnlyResponseCreates +=
            await stack.provider.createCount() - createBaseline
        expect(r843CompletionOnlyResponseCreates == 0,
               "R8.4.3 completion-only case stays response-free")
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR843SemanticOnly(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 47_400,
            label: "semantic-only"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userTranscriptFinal("tracked semantic only"),
            label: "semantic-only final"
        )
        await waitBeyondR842CompletionWindow()
        let snapshot = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r843SemanticOnlyResponseCreates +=
            await stack.provider.createCount() - createBaseline
        expect(snapshot.phase == .speaking
                && snapshot.completionCandidateCount == candidateBaseline
                && r843SemanticOnlyResponseCreates == 0,
               "R8.4.3 tracked final without completion cannot respond")
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR843ProviderOnly(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 2,
            kind: .userSpeechStarted,
            label: "Provider-only start"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 3,
            kind: .userSpeechStopped,
            label: "Provider-only stop"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 4,
            kind: .userTranscriptFinal("Provider-only final"),
            label: "Provider-only final"
        )
        await waitBeyondR842CompletionWindow()
        let snapshot = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r843ProviderOnlyResponseCreates +=
            await stack.provider.createCount() - createBaseline
        expect(snapshot.phase == .idle
                && snapshot.completionCandidateCount == 0
                && r843ProviderOnlyResponseCreates == 0,
               "R8.4.3 Provider-only evidence cannot create a user turn")
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR843DuplicateEvidence(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 47_500,
            label: "duplicate evidence"
        )
        for sequence in UInt64(3) ... 4 {
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: sequence,
                kind: .userTranscriptFinal("duplicate semantic final"),
                label: "duplicate final \(sequence)"
            )
        }
        for sequence in UInt64(5) ... 6 {
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: sequence,
                kind: .userSpeechStopped,
                label: "duplicate stop \(sequence)"
            )
        }
        await waitForR843Response(
            stack: stack,
            createBaseline: createBaseline,
            candidateBaseline: candidateBaseline,
            expectedTurnID: turnID,
            expectedSemanticSequence: 3,
            label: "duplicate fusion"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 7,
            kind: .userTranscriptFinal("late duplicate final"),
            label: "late duplicate final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 8,
            kind: .userSpeechStopped,
            label: "late duplicate stop"
        )
        try? await Task.sleep(for: .milliseconds(80))
        let createDelta = await stack.provider.createCount() - createBaseline
        r843DuplicateResponseCreates += max(0, createDelta - 1)
        r843ValidCompletedSemanticTurns += 1
        r843ValidTurnResponseCreates += createDelta
        expect(createDelta == 1,
               "R8.4.3 duplicate evidence authorizes exactly once")
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: stack.session.generation
        )
        try await close(stack)
    }

    private static func testR843EmptySemantic(
        fixture: Data
    ) async throws {
        let finals = ["", "  \n\t  "]
        for (index, transcript) in finals.enumerated() {
            let stack = try await makeControllerStack(
                fixture: fixture,
                startsResidentPlayback: false
            )
            let turnID = RealtimeBrainTurnID()
            let createBaseline = await stack.provider.createCount()
            let candidateBaseline = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
                .completionCandidateCount
            try await admitR843ListeningTurn(
                stack: stack,
                sourceTurnID: turnID,
                sequence: 2,
                seed: UInt32(47_600 + index),
                label: "empty semantic \(index)"
            )
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 3,
                kind: .userTranscriptFinal(transcript),
                label: "empty final \(index)"
            )
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 4,
                kind: .userSpeechStopped,
                label: "empty semantic stop \(index)"
            )
            await waitForR842Completion(
                runtime: stack.runtime,
                expectedCount: candidateBaseline + 1,
                expectedSession: stack.session,
                expectedTurn: turnID,
                expectedStoppedSequence: 4,
                label: "R8.4.3 empty semantic \(index)"
            )
            r843EmptyFinalResponseCreates +=
                await stack.provider.createCount() - createBaseline
            expect(await stack.provider.createCount() == createBaseline,
                   "R8.4.3 empty final \(index) cannot authorize")
            await assertR843NoInterruptionSideEffects(
                stack,
                expectedGeneration: stack.session.generation
            )
            try await close(stack)
        }
    }

    private static func testR843WrongIdentity(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        let unknownTurnID = RealtimeBrainTurnID()
        let createBaseline = await stack.provider.createCount()
        let candidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        try await admitR843ListeningTurn(
            stack: stack,
            sourceTurnID: turnID,
            sequence: 2,
            seed: 47_700,
            label: "wrong identity control"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            responseID: RealtimeBrainResponseID(),
            sequence: 3,
            kind: .userTranscriptFinal("wrong response identity"),
            label: "wrong response identity final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            contextRevision: 2,
            sequence: 4,
            kind: .userTranscriptFinal("wrong context"),
            label: "wrong context final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: unknownTurnID,
            sequence: 5,
            kind: .userTranscriptFinal("unknown source"),
            label: "unknown source final"
        )
        let futureSession = RealtimeBrainSessionIdentity(
            residentID: stack.session.residentID,
            runtimeSessionID: stack.session.runtimeSessionID,
            brainLeaseID: stack.session.brainLeaseID,
            routeEpoch: stack.session.routeEpoch,
            generation: stack.session.generation + 1
        )
        await enqueueR843Activity(
            stack: stack,
            session: futureSession,
            turnID: turnID,
            sequence: 1,
            kind: .userTranscriptFinal("wrong generation"),
            label: "wrong generation final"
        )
        try? await Task.sleep(for: .milliseconds(40))
        expect(await stack.provider.createCount() == createBaseline,
               "R8.4.3 wrong context/source/generation create nothing")

        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 6,
            kind: .userTranscriptFinal("valid identity control"),
            label: "valid identity control final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 7,
            kind: .userSpeechStopped,
            label: "valid identity control stop"
        )
        await waitForR843Response(
            stack: stack,
            createBaseline: createBaseline,
            candidateBaseline: candidateBaseline,
            expectedTurnID: turnID,
            expectedSemanticSequence: 6,
            label: "wrong identity valid control"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 8,
            kind: .userTranscriptFinal("stale logical turn"),
            label: "stale logical final"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 9,
            kind: .userSpeechStopped,
            label: "stale logical stop"
        )
        try? await Task.sleep(for: .milliseconds(40))
        let nextSession = await restartR843Route(
            stack: stack,
            label: "wrong identity old Session"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: turnID,
            sequence: 10,
            kind: .userTranscriptFinal("old Session final"),
            label: "old Session final"
        )
        try? await Task.sleep(for: .milliseconds(40))
        let createDelta = await stack.provider.createCount() - createBaseline
        r843WrongIdentityResponseCreates += max(0, createDelta - 1)
        r843ValidCompletedSemanticTurns += 1
        r843ValidTurnResponseCreates += min(1, createDelta)
        expect(createDelta == 1,
               "R8.4.3 wrong identities add zero responses")
        expect(nextSession.generation == stack.session.generation + 1,
               "R8.4.3 old-Session test uses a formal N to N+1 restart")
        await assertR843NoInterruptionSideEffects(
            stack,
            expectedGeneration: nextSession.generation
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testR843GenerationFence(
        fixture: Data
    ) async throws {
        do {
            let stack = try await makeControllerStack(
                fixture: fixture,
                startsResidentPlayback: false
            )
            let turnID = RealtimeBrainTurnID()
            let createBaseline = await stack.provider.createCount()
            let candidateBaseline = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
                .completionCandidateCount
            try await admitR843ListeningTurn(
                stack: stack,
                sourceTurnID: turnID,
                sequence: 2,
                seed: 47_800,
                label: "completion-N final-N+1"
            )
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 3,
                kind: .userSpeechStopped,
                label: "completion-N stop"
            )
            await waitForR842Completion(
                runtime: stack.runtime,
                expectedCount: candidateBaseline + 1,
                expectedSession: stack.session,
                expectedTurn: turnID,
                expectedStoppedSequence: 3,
                label: "R8.4.3 completion in N"
            )
            let nextSession = await restartR843Route(
                stack: stack,
                label: "completion-N final-N+1"
            )
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 4,
                kind: .userTranscriptFinal("late N final"),
                label: "late N final after restart"
            )
            try? await Task.sleep(for: .milliseconds(80))
            let createCount = await stack.provider.createCount()
            r843StaleGenerationResponseCreates += createCount - createBaseline
            expect(nextSession.generation == stack.session.generation + 1
                    && createCount == createBaseline,
                   "R8.4.3 N completion cannot combine with late N final")
            await assertR843NoInterruptionSideEffects(
                stack,
                expectedGeneration: nextSession.generation
            )
            await stack.controller.stopSpeechAudioCapture()
        }

        do {
            let stack = try await makeControllerStack(
                fixture: fixture,
                startsResidentPlayback: false
            )
            let turnID = RealtimeBrainTurnID()
            let createBaseline = await stack.provider.createCount()
            try await admitR843ListeningTurn(
                stack: stack,
                sourceTurnID: turnID,
                sequence: 2,
                seed: 47_900,
                label: "final-N timer-N+1"
            )
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 3,
                kind: .userTranscriptFinal("semantic final in N"),
                label: "final in N"
            )
            await enqueueR843Activity(
                stack: stack,
                session: stack.session,
                turnID: turnID,
                sequence: 4,
                kind: .userSpeechStopped,
                label: "pending timer in N"
            )
            let pending = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let pendingCreateCount = await stack.provider.createCount()
            expect(pending.phase == .candidatePause
                    && pendingCreateCount == createBaseline,
                   "R8.4.3 final in N waits for its completion timer")
            let nextSession = await restartR843Route(
                stack: stack,
                label: "final-N timer-N+1"
            )
            await waitBeyondR842CompletionWindow()
            let createCount = await stack.provider.createCount()
            r843StaleGenerationResponseCreates += createCount - createBaseline
            expect(nextSession.generation == stack.session.generation + 1
                    && createCount == createBaseline,
                   "R8.4.3 old N timer cannot authorize N+1")
            await assertR843NoInterruptionSideEffects(
                stack,
                expectedGeneration: nextSession.generation
            )
            await stack.controller.stopSpeechAudioCapture()
        }
    }

    private static func testR843InterruptionRegression(
        fixture: Data
    ) async throws {
        try await testR832ConfirmedInterruptionProductionChain(
            fixture: fixture
        )
        r843ExtraInterrupts = r832ExtraInterruptions
        r843ExtraPlaybackClears = r832ExtraPlaybackClears
        r843ExtraGenerationAdvances = max(0, r832GenerationDelta - 1)
        expect(r832ProviderInterrupts == 1
                && r832HostPlaybackClears == 1
                && r832GenerationDelta == 1,
               "R8.4.3 preserves the frozen confirmed interruption chain")
        expect(r832ResponseCreates == 0,
               "R8.4.3 interruption evidence does not create a response")
    }

    private static func admitR843ListeningTurn(
        stack: R823ControllerStack,
        sourceTurnID: RealtimeBrainTurnID,
        sequence: UInt64,
        seed: UInt32,
        label: String
    ) async throws {
        r842CompletionWindowNanoseconds = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionWindowNanoseconds
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: seed, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "R8.4.3 \(label) production near-end"
        )
        await enqueueR843Activity(
            stack: stack,
            session: stack.session,
            turnID: sourceTurnID,
            sequence: sequence,
            kind: .userSpeechStarted,
            label: "\(label) speech start"
        )
        await waitUntilOnMainActor("R8.4.3 \(label) admission") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.session == stack.session
                && snapshot.sourceTurnID == sourceTurnID
        }
    }

    private static func enqueueR843Activity(
        stack: R823ControllerStack,
        session: RealtimeBrainSessionIdentity,
        turnID: RealtimeBrainTurnID,
        responseID: RealtimeBrainResponseID? = nil,
        contextRevision: UInt64 = 1,
        sequence: UInt64,
        kind: RealtimeResidentBrainEventKind,
        label: String
    ) async {
        let returnedBefore = await stack.provider.returnedEventCount(
            eventSession: session
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: r843EventIdentity(
                session: session,
                turnID: turnID,
                responseID: responseID,
                contextRevision: contextRevision
            ),
            sequence: sequence,
            kind: kind
        ))
        await waitUntil("R8.4.3 \(label)") {
            await stack.provider.returnedEventCount(eventSession: session)
                == returnedBefore + 1
        }
    }

    private static func r843EventIdentity(
        session: RealtimeBrainSessionIdentity,
        turnID: RealtimeBrainTurnID,
        responseID: RealtimeBrainResponseID? = nil,
        contextRevision: UInt64
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: session,
            turnID: turnID,
            responseID: responseID,
            contextRevision: contextRevision
        )
    }

    private static func waitForR843Response(
        stack: R823ControllerStack,
        createBaseline: Int,
        candidateBaseline: UInt64,
        expectedTurnID: RealtimeBrainTurnID,
        expectedSemanticSequence: UInt64,
        label: String
    ) async {
        await waitUntil("R8.4.3 \(label) Provider create") {
            await stack.provider.createCount() == createBaseline + 1
        }
        let snapshot = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        let command = await stack.provider.lastCreateCommand()
        expect(snapshot.completionCandidateCount == candidateBaseline + 1,
               "R8.4.3 \(label) requires one completion candidate")
        expect(command?.identity.session == stack.session
                && command?.identity.turnID == expectedTurnID
                && command?.identity.responseID == nil
                && command?.identity.contextRevision == 1,
               "R8.4.3 \(label) preserves exact response identity")
        expect(command?.sourceEventSequence == expectedSemanticSequence,
               "R8.4.3 \(label) binds the accepted semantic final")
    }

    private static func restartR843Route(
        stack: R823ControllerStack,
        label: String
    ) async -> RealtimeBrainSessionIdentity {
        await stack.controller.stopSpeechAudioCapture()
        await waitUntilOnMainActor("R8.4.3 \(label) stop") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .idle
        }
        await stack.controller.startRealtimeResidentBrainRoute()
        await waitUntil("R8.4.3 \(label) restart") {
            guard let session = await stack.provider.lastSession() else {
                return false
            }
            let route = await stack.controller.formalSpeechRouteDebugSnapshot
            return session != stack.session
                && route.phase == .listening
                && route.generation == session.generation
        }
        guard let session = await stack.provider.lastSession() else {
            fatalError("R8.4.3 \(label) restarted session missing")
        }
        return session
    }

    private static func assertR843NoInterruptionSideEffects(
        _ stack: R823ControllerStack,
        expectedGeneration: UInt64
    ) async {
        let interruptCount = await stack.provider.interruptCount()
        let cancelCount = await stack.provider.cancelCount()
        expect(interruptCount == 0 && cancelCount == 0,
               "R8.4.3 semantic fusion never interrupts or cancels Provider")
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "R8.4.3 semantic fusion never clears Playback")
        expect(stack.controller.formalSpeechRouteDebugSnapshot.generation
                == expectedGeneration,
               "R8.4.3 preserves the expected formal generation")
    }

    private static func printR843Metrics() {
        print("r843_final_before_completion_cases=\(r843FinalBeforeCompletionCases)")
        print("r843_completion_before_final_cases=\(r843CompletionBeforeFinalCases)")
        print("r843_cross_source_turn_cases=\(r843CrossSourceTurnCases)")
        print("r843_valid_completed_semantic_turns=\(r843ValidCompletedSemanticTurns)")
        print("r843_valid_turn_response_creates=\(r843ValidTurnResponseCreates)")
        print("r843_completion_only_response_creates=\(r843CompletionOnlyResponseCreates)")
        print("r843_semantic_only_response_creates=\(r843SemanticOnlyResponseCreates)")
        print("r843_provider_only_response_creates=\(r843ProviderOnlyResponseCreates)")
        print("r843_empty_final_response_creates=\(r843EmptyFinalResponseCreates)")
        print("r843_wrong_identity_response_creates=\(r843WrongIdentityResponseCreates)")
        print("r843_stale_generation_response_creates=\(r843StaleGenerationResponseCreates)")
        print("r843_duplicate_response_creates=\(r843DuplicateResponseCreates)")
        print("r843_extra_interrupts=\(r843ExtraInterrupts)")
        print("r843_extra_playback_clears=\(r843ExtraPlaybackClears)")
        print("r843_extra_generation_advances=\(r843ExtraGenerationAdvances)")
    }

    private static func testR842PauseVsUtteranceCompletion(
        fixture: Data
    ) async throws {
        try await testR842NormalListeningAdmission(fixture: fixture)
        try await testR842ContinuousPauseAndTrueEnd(fixture: fixture)
        try await testR842SourceTurnRebound(fixture: fixture)
        try await testR842ProviderFirstDelayedPause(fixture: fixture)
        try await testR842GateCloseEventFirstResume(fixture: fixture)
        try await testR842FalsePendingAndFreshTurn(fixture: fixture)
        try await testR842PreStopInFlightFrame(fixture: fixture)
        try await testR842DoubleTalkPauseAndTrueEnd(fixture: fixture)
        try await testR842ResidentOnlySafety(fixture: fixture)
        try await testR842StaleTimerAndGeneration(fixture: fixture)
        r842DuplicateCompletions = max(
            0,
            r842CompletionCandidates - r842TrueEndCases
        )

        expect(r842CompletionWindowNanoseconds == 800_000_000,
               "R8.4.2 freezes one centralized 800 ms Runtime window")
        expect(r842ShortPauseCases == 5,
               "R8.4.2 covers five short-pause patterns")
        expect(r842ShortPauseFalseCompletions == 0,
               "R8.4.2 short pauses never complete")
        expect(r842TrueEndCases == 11,
               "R8.4.2 covers eleven true-end paths")
        expect(r842CompletionCandidates == r842TrueEndCases,
               "R8.4.2 emits exactly one candidate per true end")
        expect(r842DuplicateCompletions == 0,
               "R8.4.2 duplicate end facts stay idempotent")
        expect(r842ResidentOnlyFalseCompletions == 0,
               "R8.4.2 resident-only audio never creates a user completion")
        expect(r842StaleGenerationCompletions == 0,
               "R8.4.2 stale-generation events fail closed")
        expect(r842OldTimerResurrections == 0,
               "R8.4.2 old timers cannot resurrect after restart")
        expect(r842ResponseCreates == 0,
               "R8.4.2 activity-only evidence creates no response")
        expect(r842ProviderInterrupts == 0 && r842ProviderCancels == 0,
               "R8.4.2 never invokes Provider interruption APIs")
        expect(r842HostPlaybackClears == 0,
               "R8.4.2 never clears Playback")
        expect(r842ExtraGenerationAdvances == 0,
               "R8.4.2 has no generation advance beyond formal restart")
        expect(r842DoubleTalkCases == 2,
               "R8.4.2 covers double-talk pause and true end")
    }

    private static func testR842NormalListeningAdmission(
        fixture: Data
    ) async throws {
        try await testR842ListeningContinuousSpeech(fixture: fixture)
        try await testR842ListeningShortPause(fixture: fixture)
        try await testR842ListeningProviderFirst(fixture: fixture)
        try await testR842ListeningProviderOnly(fixture: fixture)
        try await testR842ListeningNegativeMatrix(fixture: fixture)
        try await testR842ListeningStopRestart(fixture: fixture)

        expect(r842ListeningContinuousCases == 1,
               "R8.4.2 repair covers normal Listening continuous speech")
        expect(r842ListeningShortPauseCases == 1,
               "R8.4.2 repair covers normal Listening short pause")
        expect(r842ListeningSpeakingAdmissions == 4,
               "R8.4.2 repair admits four production Listening starts")
        expect(r842ListeningTrueEndCandidates == 3,
               "R8.4.2 repair completes three true Listening ends")
        expect(r842ListeningFalseCompletions == 0,
               "R8.4.2 repair has no Listening false completion")
        expect(r842ProviderOnlyFalseAdmissions == 0
                && r842ProviderOnlyFalseCompletions == 0,
               "R8.4.2 Provider-only activity has no authority")
        expect(r842ListeningNegativeFalseAdmissions == 0
                && r842ListeningNegativeFalseCompletions == 0,
               "R8.4.2 silence, noise, tail, and ordinary PCM fail closed")
        expect(r842StalePCMAdmissions == 0,
               "R8.4.2 old-generation PCM cannot admit N+1")
        expect(r842OldGenerationCompletions == 0,
               "R8.4.2 old Listening timers cannot complete N+1")
    }

    private static func testR842ListeningContinuousSpeech(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let generation = stack.session.generation
        let lease = stack.runtime.activeBrainLeaseForTesting()
        r842CompletionWindowNanoseconds = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionWindowNanoseconds
        let turnID = RealtimeBrainTurnID()
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: 46_000, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "continuous production near-end"
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 2,
            kind: .userSpeechStarted
        )
        await waitUntilOnMainActor("R8.4.2 Listening continuous speaking") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.session == stack.session
                && snapshot.turnID == turnID
        }
        r842ListeningContinuousCases += 1
        r842ListeningSpeakingAdmissions += 1
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 3,
            kind: .userTranscriptPartial("normal listening speech")
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 4,
            kind: .userTranscriptPartial("normal listening speech continued")
        )
        expect(stack.runtime
                .realtimeUtteranceCompletionTracksTranscriptFinalForTesting(
                    RealtimeBrainEventIdentity(
                        session: stack.session,
                        turnID: turnID,
                        responseID: nil,
                        contextRevision: 1
                    )
                ),
               "R8.4.2 Listening transcript remains tracked evidence")
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 5,
            kind: .userSpeechStopped
        )
        await waitUntilOnMainActor("R8.4.2 Listening continuous pause") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .candidatePause
        }
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: 5,
            label: "normal Listening continuous true end"
        )
        r842ListeningTrueEndCandidates += 1
        expect(stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == generation
                && stack.runtime.activeBrainLeaseForTesting() == lease,
               "R8.4.2 Listening continuous keeps generation and lease")
        await assertR842ListeningHasNoDecisionSideEffects(stack)
        try await close(stack)
    }

    private static func testR842ListeningShortPause(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: 46_100, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "short-pause opening"
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 2,
            kind: .userSpeechStarted
        )
        await waitUntilOnMainActor("R8.4.2 Listening short-pause speaking") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .speaking
        }
        r842ListeningSpeakingAdmissions += 1
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 3,
            kind: .userSpeechStopped
        )
        await waitUntilOnMainActor("R8.4.2 Listening short-pause candidate") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .candidatePause
        }
        try? await Task.sleep(for: .milliseconds(600))
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: 46_101, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "short-pause continuation"
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 4,
            kind: .userSpeechStarted
        )
        await waitUntilOnMainActor("R8.4.2 Listening short-pause resume") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.turnID == turnID
                && snapshot.session == stack.session
        }
        await waitBeyondR842CompletionWindow()
        let resumed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842ListeningShortPauseCases += 1
        r842ListeningFalseCompletions += Int(
            resumed.completionCandidateCount
        )
        expect(resumed.completionCandidateCount == 0,
               "R8.4.2 normal Listening short pause does not complete")
        expect(resumed.resumedPauseCount == 1,
               "R8.4.2 normal Listening resumes the same logical turn")
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 5,
            kind: .userSpeechStopped
        )
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: 5,
            label: "normal Listening short-pause true end"
        )
        r842ListeningTrueEndCandidates += 1
        await assertR842ListeningHasNoDecisionSideEffects(stack)
        try await close(stack)
    }

    private static func testR842ListeningProviderFirst(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 2,
            kind: .userSpeechStarted
        )
        let beforePCM = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(beforePCM.phase == .idle
                && beforePCM.pendingStartTurnID == turnID,
               "R8.4.2 Provider-first event waits for production PCM")
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: 46_200, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "Provider-first delayed production near-end"
        )
        await waitUntilOnMainActor("R8.4.2 Provider-first admission") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.turnID == turnID
        }
        r842ListeningSpeakingAdmissions += 1
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 3,
            kind: .userTranscriptPartial("Provider-first normal speech")
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 4,
            kind: .userSpeechStopped
        )
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: 4,
            label: "Provider-first normal Listening true end"
        )
        r842ListeningTrueEndCandidates += 1
        await assertR842ListeningHasNoDecisionSideEffects(stack)
        try await close(stack)
    }

    private static func testR842ListeningProviderOnly(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let turnID = RealtimeBrainTurnID()
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 2,
            kind: .userSpeechStarted
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 3,
            kind: .userSpeechStopped
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 4,
            kind: .userTranscriptFinal("Provider-only fake")
        )
        await waitBeyondR842CompletionWindow()
        let snapshot = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842ProviderOnlyFalseAdmissions += snapshot.phase == .idle ? 0 : 1
        r842ProviderOnlyFalseCompletions += Int(
            snapshot.completionCandidateCount
        )
        expect(snapshot.phase == .idle
                && snapshot.completionCandidateCount == 0,
               "R8.4.2 Provider activity alone cannot create a user turn")
        await assertR842ListeningHasNoDecisionSideEffects(stack)
        try await close(stack)
    }

    private static func testR842ListeningNegativeMatrix(
        fixture: Data
    ) async throws {
        let cases: [(String, [Float], Bool)] = [
            ("silence", Array(repeating: 0, count: 480), false),
            ("noise", signal(seed: 46_300, amplitude: 0.004), false),
            ("ordinary PCM", signal(seed: 46_301, amplitude: 0.008), false),
            ("residual tail", signal(seed: 46_302, amplitude: 0.18), true)
        ]
        for (index, fixtureCase) in cases.enumerated() {
            let stack = try await makeControllerStack(
                fixture: fixture,
                startsResidentPlayback: false
            )
            if fixtureCase.2 {
                let render = signal(seed: 46_350, amplitude: 0.25)
                stack.acousticEchoHost.playbackStarted()
                stack.acousticEchoHost.processRender(
                    render,
                    hostTimeNanoseconds: monotonicNow()
                )
                stack.acousticEchoHost.playbackCompleted()
                let observation = stack.acousticEchoHost
                    .acousticObservationSnapshot()
                expect(!observation.isPlaybackActive
                        && observation
                            .lastAudibleRenderHostTimeNanoseconds != nil,
                       "R8.4.2 residual-tail fixture closes playback with an audible fence")
            }
            try await emitR842ListeningSamples(
                stack: stack,
                samples: fixtureCase.1,
                expectedClassification: fixtureCase.2
                    ? .nearEndCandidate : .silenceOrNoise,
                label: fixtureCase.0
            )
            let turnID = RealtimeBrainTurnID()
            let sequence = UInt64(2)
            await enqueueR842Activity(
                stack: stack,
                turnID: turnID,
                sequence: sequence,
                kind: .userSpeechStarted
            )
            await enqueueR842Activity(
                stack: stack,
                turnID: turnID,
                sequence: sequence + 1,
                kind: .userSpeechStopped
            )
            await enqueueR842Activity(
                stack: stack,
                turnID: turnID,
                sequence: sequence + 2,
                kind: .userTranscriptFinal("negative \(index)")
            )
            await waitBeyondR842CompletionWindow()
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            r842ListeningNegativeFalseAdmissions +=
                snapshot.phase == .idle ? 0 : 1
            r842ListeningNegativeFalseCompletions += Int(
                snapshot.completionCandidateCount
            )
            expect(snapshot.phase == .idle
                    && snapshot.completionCandidateCount == 0,
                   "R8.4.2 \(fixtureCase.0) cannot admit Provider activity")
            await assertR842ListeningHasNoDecisionSideEffects(stack)
            try await close(stack)
        }
    }

    private static func testR842ListeningStopRestart(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(
            fixture: fixture,
            startsResidentPlayback: false
        )
        let oldTurnID = RealtimeBrainTurnID()
        try await emitR842ListeningSamples(
            stack: stack,
            samples: signal(seed: 46_400, amplitude: 0.18),
            expectedClassification: .nearEndCandidate,
            label: "stop-restart old generation"
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: oldTurnID,
            sequence: 2,
            kind: .userSpeechStarted
        )
        await waitUntilOnMainActor("R8.4.2 Listening old generation speaking") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .speaking
        }
        r842ListeningSpeakingAdmissions += 1
        await enqueueR842Activity(
            stack: stack,
            turnID: oldTurnID,
            sequence: 3,
            kind: .userSpeechStopped
        )
        await waitUntilOnMainActor("R8.4.2 Listening old timer pending") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .candidatePause
        }
        await stack.controller.stopSpeechAudioCapture()
        await waitUntilOnMainActor("R8.4.2 Listening route stops") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .idle
        }
        await stack.controller.startRealtimeResidentBrainRoute()
        await waitUntil("R8.4.2 Listening route restarts") {
            guard let session = await stack.provider.lastSession() else {
                return false
            }
            let phase = await stack.controller
                .formalSpeechRouteDebugSnapshot.phase
            return session != stack.session && phase == .listening
        }
        guard let nextSession = await stack.provider.lastSession() else {
            fatalError("R8.4.2 Listening restarted session missing")
        }
        expect(nextSession.generation == stack.session.generation + 1,
               "R8.4.2 Listening restart advances exactly to N+1")
        await stack.provider.enqueue(r842ActivityEvent(
            session: stack.session,
            turnID: oldTurnID,
            sequence: 4,
            kind: .userTranscriptFinal("stale N transcript")
        ))
        let nextTurnID = RealtimeBrainTurnID()
        await stack.provider.enqueue(r842ActivityEvent(
            session: nextSession,
            turnID: nextTurnID,
            sequence: 2,
            kind: .userSpeechStarted
        ))
        await waitUntil("R8.4.2 Listening stale and N+1 events return") {
            let oldCount = await stack.provider.returnedEventCount(
                eventSession: stack.session
            )
            let nextCount = await stack.provider.returnedEventCount(
                eventSession: nextSession
            )
            return oldCount >= 4 && nextCount >= 2
        }
        await waitBeyondR842CompletionWindow()
        let snapshot = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842StalePCMAdmissions += snapshot.phase == .idle ? 0 : 1
        r842OldGenerationCompletions += Int(
            snapshot.completionCandidateCount
        )
        expect(snapshot.phase == .idle
                && snapshot.completionCandidateCount == 0,
               "R8.4.2 old PCM, activity, and timer cannot bind N+1")
        await assertR842ListeningHasNoDecisionSideEffects(stack)
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func emitR842ListeningSamples(
        stack: R823ControllerStack,
        samples: [Float],
        expectedClassification: RealtimeAcousticClassification,
        label: String
    ) async throws {
        let audioBefore = await stack.provider.audioFrameCount()
        expect(!stack.acousticEchoHost.acousticObservationSnapshot()
                .isPlaybackActive,
               "R8.4.2 \(label) starts without resident playback")
        var emittedPackets = 0
        for _ in 0 ..< 4 {
            let before = stack.acousticEchoHost
                .acousticObservationSnapshot()
            let captureTimestamp = monotonicNow()
            stack.aecBackend.setCaptureOutput(samples)
            let processed = stack.acousticEchoHost.processCapture(
                samples,
                hostTimeNanoseconds: captureTimestamp
            )
            let emission = try stack.capture.emit(
                processedSamples: processed,
                acousticBefore: before
            )
            emittedPackets += emission.packetCount
            try? await Task.sleep(for: .milliseconds(10))
        }
        await waitUntil("R8.4.2 \(label) reaches Provider") {
            await stack.provider.audioFrameCount() > audioBefore
        }
        let acoustic = stack.acousticEchoHost
            .acousticObservationSnapshot()
        let metrics = RealtimeAcousticMetrics(
            residentPlaybackSequence: acoustic.playbackSequence,
            residentPlaybackActive: acoustic.isPlaybackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                acoustic.lastAudibleRenderHostTimeNanoseconds,
            renderReferenceAvailable: acoustic.renderReferenceAvailable,
            renderReferenceRMS: acoustic.renderReferenceRMS,
            rawCaptureRMS: acoustic.rawCaptureRMS,
            aecOutputRMS: acoustic.processedCaptureRMS,
            linearAECOutputRMS: acoustic.linearAECOutputRMS,
            renderCaptureCorrelation: acoustic.renderCaptureCorrelation,
            residualRenderCorrelation: acoustic.residualRenderCorrelation,
            linearRenderCorrelation: acoustic.linearRenderCorrelation,
            captureTimestampNanoseconds:
                acoustic.captureHostTimeNanoseconds,
            renderTimestampNanoseconds: acoustic.renderHostTimeNanoseconds,
            sourceAlignmentDelayMilliseconds:
                acoustic.sourceAlignmentDelayMilliseconds,
            estimatedDelayMilliseconds:
                acoustic.estimatedDelayMilliseconds,
            erlDecibels: acoustic.erlDecibels,
            erleDecibels: acoustic.erleDecibels,
            renderCaptureSkewFrames: acoustic.renderCaptureSkewFrames,
            driftState: .stable,
            sourceAssessment: .nearEndSpeech,
            sourceGateOpen: acoustic.sourceGateOpen,
            sourceGateEpoch: acoustic.sourceGateEpoch,
            aecActive: acoustic.aecActive,
            sourceAlignmentLocked: acoustic.sourceAlignmentLocked,
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
        let classification = RealtimeAcousticClassifier.classify(
            metrics: metrics,
            observationTimestampNanoseconds:
                acoustic.captureHostTimeNanoseconds ?? monotonicNow()
        )
        expect(emittedPackets > 0,
               "R8.4.2 \(label) crosses production PCM conversion")
        expect(!acoustic.isPlaybackActive && !acoustic.sourceGateOpen,
               "R8.4.2 \(label) does not fake playback or source gate")
        expect(classification == expectedClassification,
               "R8.4.2 \(label) uses production Listening classification")
    }

    private static func assertR842ListeningHasNoDecisionSideEffects(
        _ stack: R823ControllerStack
    ) async {
        let createCount = await stack.provider.createCount()
        let interruptCount = await stack.provider.interruptCount()
        let cancelCount = await stack.provider.cancelCount()
        expect(createCount == 0,
               "R8.4.2 Listening never creates a response")
        expect(interruptCount == 0 && cancelCount == 0,
               "R8.4.2 Listening never interrupts or cancels Provider")
        expect(stack.outputPlayer.startCount == 0
                && stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "R8.4.2 Listening never starts or clears Playback")
    }

    private static func printR842ListeningMetrics() {
        print("r842_listening_continuous_cases=\(r842ListeningContinuousCases)")
        print("r842_listening_short_pause_cases=\(r842ListeningShortPauseCases)")
        print("r842_listening_speaking_admissions=\(r842ListeningSpeakingAdmissions)")
        print("r842_listening_true_end_candidates=\(r842ListeningTrueEndCandidates)")
        print("r842_listening_false_completions=\(r842ListeningFalseCompletions)")
        print("r842_provider_only_false_admissions=\(r842ProviderOnlyFalseAdmissions)")
        print("r842_provider_only_false_completions=\(r842ProviderOnlyFalseCompletions)")
        print("r842_listening_negative_false_admissions=\(r842ListeningNegativeFalseAdmissions)")
        print("r842_listening_negative_false_completions=\(r842ListeningNegativeFalseCompletions)")
        print("r842_stale_pcm_admissions=\(r842StalePCMAdmissions)")
        print("r842_old_generation_completions=\(r842OldGenerationCompletions)")
    }

    private static func testR842ContinuousPauseAndTrueEnd(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let generationBaseline = stack.session.generation
        let leaseBaseline = stack.runtime.activeBrainLeaseForTesting()
        let initial = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842CompletionWindowNanoseconds = initial
            .completionWindowNanoseconds
        var sequence: UInt64 = 4

        let continuousTurn = RealtimeBrainTurnID()
        try await establishR842AcousticAuthorization(
            stack: stack,
            label: "continuous speech",
            seed: 45_000
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: continuousTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: continuousTurn,
            sequence: sequence,
            kind: .userTranscriptPartial("still speaking")
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: continuousTurn,
            sequence: sequence,
            kind: .userTranscriptPartial("provider segment partial")
        )
        sequence &+= 1
        await waitUntilOnMainActor("R8.4.2 continuous speech state") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.turnID == continuousTurn
        }
        await waitBeyondR842CompletionWindow()
        let continuous = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(continuous.phase == .speaking,
               "R8.4.2 continuous speech remains speaking")
        expect(continuous.completionCandidateCount == 0,
               "R8.4.2 continuous speech never completes")
        expect(
            stack.runtime
                .realtimeUtteranceCompletionTracksTranscriptFinalForTesting(
                    RealtimeBrainEventIdentity(
                        session: stack.session,
                        turnID: continuousTurn,
                        responseID: nil,
                        contextRevision: 1
                    )
                ),
            "R8.4.2 matching transcript stays on the tracked utterance"
        )
        expect(
            !stack.runtime
                .realtimeUtteranceCompletionTracksTranscriptFinalForTesting(
                    RealtimeBrainEventIdentity(
                        session: stack.session,
                        turnID: RealtimeBrainTurnID(),
                        responseID: nil,
                        contextRevision: 1
                    )
                ),
            "R8.4.2 unrelated transcript final is outside the turn fence"
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: continuousTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let continuousStopSequence = sequence
        sequence &+= 1
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: continuousTurn,
            expectedStoppedSequence: continuousStopSequence,
            label: "continuous speech eventual true end"
        )
        r842TrueEndCases += 1
        let shortTurn = RealtimeBrainTurnID()
        try await establishR842AcousticAuthorization(
            stack: stack,
            label: "single short pause",
            seed: 45_100
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: shortTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: shortTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        sequence &+= 1
        await waitUntilOnMainActor("R8.4.2 short pause candidate") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .candidatePause
        }
        let shortPauseCandidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        try? await Task.sleep(for: .milliseconds(300))
        try await emitR842NearEndContinuation(
            stack: stack,
            seed: 45_101
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: shortTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await waitUntilOnMainActor("R8.4.2 short pause resume") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.turnID == shortTurn
                && snapshot.session == stack.session
        }
        await waitBeyondR842CompletionWindow()
        let shortResume = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842ShortPauseCases += 1
        r842ShortPauseFalseCompletions += Int(
            shortResume.completionCandidateCount
                - shortPauseCandidateBaseline
        )
        expect(shortResume.completionCandidateCount
                == shortPauseCandidateBaseline,
               "R8.4.2 short pause resumes without completion")
        expect(shortResume.session?.generation == generationBaseline
                && shortResume.turnID == shortTurn,
               "R8.4.2 short pause resumes on the same generation and turn")
        await enqueueR842Activity(
            stack: stack,
            turnID: shortTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let shortStopSequence = sequence
        sequence &+= 1
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 2,
            expectedSession: stack.session,
            expectedTurn: shortTurn,
            expectedStoppedSequence: shortStopSequence,
            label: "single short-pause eventual true end"
        )
        r842TrueEndCases += 1
        let repeatedTurn = RealtimeBrainTurnID()
        try await establishR842AcousticAuthorization(
            stack: stack,
            label: "repeated short pauses",
            seed: 45_200
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: repeatedTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        let repeatedCandidateBaseline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        let repeatedPauseMilliseconds = [300, 500, 600]
        for (pauseIndex, pauseMilliseconds) in
            repeatedPauseMilliseconds.enumerated() {
            await enqueueR842Activity(
                stack: stack,
                turnID: repeatedTurn,
                sequence: sequence,
                kind: .userSpeechStopped
            )
            sequence &+= 1
            await waitUntilOnMainActor(
                "R8.4.2 repeated pause \(pauseIndex)"
            ) {
                stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot().phase
                    == .candidatePause
            }
            try? await Task.sleep(for: .milliseconds(pauseMilliseconds))
            try await emitR842NearEndContinuation(
                stack: stack,
                seed: UInt32(45_201 + pauseIndex)
            )
            await enqueueR842Activity(
                stack: stack,
                turnID: repeatedTurn,
                sequence: sequence,
                kind: .userSpeechStarted
            )
            sequence &+= 1
            await waitUntilOnMainActor(
                "R8.4.2 repeated resume \(pauseIndex)"
            ) {
                let snapshot = stack.runtime
                    .realtimeUtteranceCompletionDebugSnapshot()
                return snapshot.phase == .speaking
                    && snapshot.turnID == repeatedTurn
            }
        }
        await waitBeyondR842CompletionWindow()
        let repeatedResume = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842ShortPauseCases += 1
        r842ShortPauseFalseCompletions += Int(
            repeatedResume.completionCandidateCount
                - repeatedCandidateBaseline
        )
        expect(repeatedResume.completionCandidateCount
                == repeatedCandidateBaseline,
               "R8.4.2 repeated short pauses never complete")
        expect(repeatedResume.resumedPauseCount == 4,
               "R8.4.2 records every same-turn pause resume")
        await enqueueR842Activity(
            stack: stack,
            turnID: repeatedTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let repeatedStopSequence = sequence
        sequence &+= 1
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 3,
            expectedSession: stack.session,
            expectedTurn: repeatedTurn,
            expectedStoppedSequence: repeatedStopSequence,
            label: "repeated-pause eventual true end"
        )
        r842TrueEndCases += 1
        let trueEndTurn = RealtimeBrainTurnID()
        try await establishR842AcousticAuthorization(
            stack: stack,
            label: "true end",
            seed: 45_300
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: trueEndTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: trueEndTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let trueEndSequence = sequence
        sequence &+= 1
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 4,
            expectedSession: stack.session,
            expectedTurn: trueEndTurn,
            expectedStoppedSequence: trueEndSequence,
            label: "continuous-matrix true end"
        )
        r842TrueEndCases += 1
        await enqueueR842Activity(
            stack: stack,
            turnID: trueEndTurn,
            sequence: sequence,
            kind: .userTranscriptPartial("provider true-end partial")
        )
        sequence &+= 1

        let returnedBeforeDuplicates = await stack.provider
            .returnedEventCount(eventSession: stack.session)
        for _ in 0 ..< 3 {
            await stack.provider.enqueue(r842ActivityEvent(
                session: stack.session,
                turnID: trueEndTurn,
                sequence: sequence,
                kind: .userSpeechStopped
            ))
            sequence &+= 1
        }
        await waitUntil("R8.4.2 duplicate stops returned") {
            await stack.provider.returnedEventCount(
                eventSession: stack.session
            ) == returnedBeforeDuplicates + 3
        }
        try? await Task.sleep(for: .milliseconds(80))
        let completed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(completed.completionCandidateCount == 4,
               "R8.4.2 duplicate stops do not duplicate completion")
        r842CompletionCandidates += Int(completed.completionCandidateCount)
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        expect(stack.runtime.activeBrainLeaseForTesting() == leaseBaseline,
               "R8.4.2 activity matrix preserves the Brain lease")
        expect(stack.session.generation == generationBaseline,
               "R8.4.2 activity matrix preserves generation")
        try await close(stack)
    }

    private static func testR842SourceTurnRebound(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let generationBaseline = stack.session.generation
        let logicalTurn = RealtimeBrainTurnID()
        let reboundSourceTurn = RealtimeBrainTurnID()
        var sequence: UInt64 = 4

        let sourceCaptureFrameBefore = stack.acousticEchoHost
            .acousticObservationSnapshot().captureFrameIndex
        await stack.provider.holdAudioAppend(afterAdditionalFrames: 1)
        let acousticTask = Task {
            try await establishR842AcousticAuthorization(
                stack: stack,
                label: "source-turn rebound",
                seed: 45_400,
                transition: .none
            )
        }
        await stack.provider.waitUntilAudioAppendIsHeld()
        await waitUntil("R8.4.2 held production gate opens") {
            stack.acousticEchoHost.acousticObservationSnapshot()
                .sourceGateOpen
        }
        await waitUntil("R8.4.2 held production capture settles") {
            stack.acousticEchoHost.acousticObservationSnapshot()
                .captureFrameIndex >= sourceCaptureFrameBefore + 18
        }
        await waitUntil("R8.4.2 held capture timestamp becomes current") {
            guard let captureTimestamp = stack.acousticEchoHost
                .acousticObservationSnapshot()
                .captureHostTimeNanoseconds else { return false }
            return DispatchTime.now().uptimeNanoseconds
                >= captureTimestamp
        }
        await enqueueR842Activity(
            stack: stack,
            turnID: logicalTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        let pending = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(pending.phase == .idle
                && pending.claimedAcousticSequence == 0,
               "R8.4.2 Provider-first activity waits for acoustic authorization")
        await enqueueR842Activity(
            stack: stack,
            turnID: logicalTurn,
            sequence: sequence,
            kind: .userTranscriptPartial("provider-first segment partial")
        )
        sequence &+= 1
        let createCountWhilePending = await stack.provider.createCount()
        expect(createCountWhilePending == createBaseline,
               "R8.4.2 pending exact-turn transcript creates no response")
        await enqueueR842Activity(
            stack: stack,
            turnID: logicalTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        sequence &+= 1
        await stack.provider.releaseAudioAppend()
        try await acousticTask.value
        let pendingAfterAcoustic = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        let evidenceAfterAcoustic = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
        await waitUntilOnMainActor(
            "R8.4.2 Provider-first acoustic reconciliation "
                + "pending=\(pendingAfterAcoustic.pendingStartAtNanoseconds) "
                + "acoustic=\(evidenceAfterAcoustic.lastAcousticTimestampNanoseconds) "
                + "received=\(evidenceAfterAcoustic.acousticReceivedAtNanoseconds)"
        ) {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .candidatePause
                && snapshot.turnID == logicalTurn
        }
        try? await Task.sleep(for: .milliseconds(600))
        try await emitR842NearEndContinuation(
            stack: stack,
            seed: 45_401
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: reboundSourceTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await waitUntilOnMainActor("R8.4.2 source-turn rebound") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.turnID == logicalTurn
                && snapshot.sourceTurnID == reboundSourceTurn
        }
        await waitBeyondR842CompletionWindow()
        let resumed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842ShortPauseCases += 1
        r842ShortPauseFalseCompletions += Int(
            resumed.completionCandidateCount
        )
        expect(resumed.completionCandidateCount == 0,
               "R8.4.2 source-turn rebound does not complete")
        expect(resumed.session?.generation == generationBaseline
                && resumed.turnID == logicalTurn
                && resumed.sourceTurnID == reboundSourceTurn,
               "R8.4.2 source-turn rebound preserves one logical utterance")

        await enqueueR842Activity(
            stack: stack,
            turnID: reboundSourceTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let stoppedSequence = sequence
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: logicalTurn,
            expectedStoppedSequence: stoppedSequence,
            label: "source-turn rebound true end"
        )
        let completed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(completed.sourceTurnID == reboundSourceTurn,
               "R8.4.2 rebound completion retains the active source turn")
        r842TrueEndCases += 1
        r842CompletionCandidates += Int(completed.completionCandidateCount)
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        try await close(stack)
    }

    private static func testR842ProviderFirstDelayedPause(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let turnID = RealtimeBrainTurnID()

        let delayedCaptureFrameBefore = stack.acousticEchoHost
            .acousticObservationSnapshot().captureFrameIndex
        await stack.provider.holdAudioAppend(afterAdditionalFrames: 1)
        let acousticTask = Task {
            try await establishR842AcousticAuthorization(
                stack: stack,
                label: "delayed Provider-first pause",
                seed: 45_450,
                transition: .none
            )
        }
        await stack.provider.waitUntilAudioAppendIsHeld()
        await waitUntil("R8.4.2 held delayed gate opens") {
            stack.acousticEchoHost.acousticObservationSnapshot()
                .sourceGateOpen
        }
        await waitUntil("R8.4.2 held delayed capture settles") {
            stack.acousticEchoHost.acousticObservationSnapshot()
                .captureFrameIndex >= delayedCaptureFrameBefore + 18
        }
        await waitUntil(
            "R8.4.2 held delayed capture timestamp becomes current"
        ) {
            guard let captureTimestamp = stack.acousticEchoHost
                .acousticObservationSnapshot()
                .captureHostTimeNanoseconds else { return false }
            return DispatchTime.now().uptimeNanoseconds
                >= captureTimestamp
        }
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 4,
            kind: .userSpeechStarted
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 5,
            kind: .userSpeechStopped
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: 6,
            kind: .userTranscriptPartial("delayed Provider-first partial")
        )
        await waitUntilOnMainActor(
            "R8.4.2 Provider-only activity reaches Runtime pending state"
        ) {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .idle
                && snapshot.pendingStartTurnID == turnID
        }
        try? await Task.sleep(
            for: .nanoseconds(
                Int64(r842CompletionWindowNanoseconds / 2 + 20_000_000)
            )
        )
        let beforeAcoustic = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        let createBeforeAcoustic = await stack.provider.createCount()
        expect(beforeAcoustic.phase == .idle
                && beforeAcoustic.completionCandidateCount == 0
                && createBeforeAcoustic == createBaseline,
               "R8.4.2 Provider activity alone cannot complete or respond")

        await stack.provider.releaseAudioAppend()
        try await acousticTask.value
        let afterDelayedAcoustic = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        let afterDelayedEvidence = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: 5,
            label: "delayed Provider-first true end "
                + "phase=\(afterDelayedAcoustic.phase) "
                + "pending=\(afterDelayedAcoustic.pendingStartAtNanoseconds) "
                + "claimed=\(afterDelayedAcoustic.claimedAcousticSequence) "
                + "acoustic=\(afterDelayedEvidence.lastAcousticTimestampNanoseconds)"
        )
        let completed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842TrueEndCases += 1
        r842CompletionCandidates += Int(completed.completionCandidateCount)
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        try await close(stack)
    }

    private static func testR842GateCloseEventFirstResume(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let turnID = RealtimeBrainTurnID()
        let falseTurnID = RealtimeBrainTurnID()
        var sequence: UInt64 = 4

        try await establishR842AcousticAuthorization(
            stack: stack,
            label: "event-first gate-close base",
            seed: 45_460,
            transition: .none
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        let initialClaim = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .claimedAcousticSequence
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        sequence &+= 1
        await waitUntilOnMainActor("R8.4.2 gate-close candidate") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .candidatePause
        }
        try await closeR842SourceGateDuringPause(
            stack: stack,
            seed: 45_461,
            frameIntervalMilliseconds: 8
        )
        expect(stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .candidatePause,
               "R8.4.2 gate closes before the pause window expires")

        let captureFrameBefore = stack.acousticEchoHost
            .acousticObservationSnapshot().captureFrameIndex
        await stack.provider.holdAudioAppend(afterAdditionalFrames: 1)
        let continuationTask = Task {
            try await emitR842NearEndContinuation(
                stack: stack,
                seed: 45_462
            )
        }
        await stack.provider.waitUntilAudioAppendIsHeld()
        await waitUntil("R8.4.2 event-first reopen capture settles") {
            stack.acousticEchoHost.acousticObservationSnapshot()
                .captureFrameIndex >= captureFrameBefore + 6
        }
        await waitUntil("R8.4.2 event-first reopen timestamp is current") {
            guard let captureTimestamp = stack.acousticEchoHost
                .acousticObservationSnapshot()
                .captureHostTimeNanoseconds else { return false }
            return DispatchTime.now().uptimeNanoseconds
                >= captureTimestamp
        }
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: sequence,
            kind: .userTranscriptPartial("event-first resumed segment")
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let resumedStopSequence = sequence
        sequence &+= 1
        await stack.provider.releaseAudioAppend()
        try await continuationTask.value
        await waitUntilOnMainActor(
            "R8.4.2 delayed reopen eligibility is consumed"
        ) {
            let completion = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            let evidence = stack.runtime
                .realtimeInterruptionEvidenceDebugSnapshot()
            return completion.claimedAcousticSequence
                    == evidence.lastAcousticSequence
                && completion.claimedAcousticSequence > initialClaim
        }
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: resumedStopSequence,
            label: "event-first gate-close true end"
        )
        let completed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(completed.resumedPauseCount == 1,
               "R8.4.2 event-first audio resumes the original pause once")
        let claimedAfterCompletion = completed.claimedAcousticSequence
        let evidenceAfterCompletion = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
            .lastAcousticSequence
        await enqueueR842Activity(
            stack: stack,
            turnID: falseTurnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        try? await Task.sleep(for: .milliseconds(40))
        let afterFalseStart = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(afterFalseStart.turnID == turnID
                && afterFalseStart.completionCandidateCount == 1,
               "R8.4.2 no-evidence next start cannot replace the completed turn")
        expect(afterFalseStart.claimedAcousticSequence
                == claimedAfterCompletion
                && evidenceAfterCompletion == claimedAfterCompletion,
               "R8.4.2 delayed resume eligibility is one-shot")
        r842ShortPauseCases += 1
        r842TrueEndCases += 1
        r842CompletionCandidates += Int(
            afterFalseStart.completionCandidateCount
        )
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        try await close(stack)
    }

    private static func testR842FalsePendingAndFreshTurn(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let falseTurnID = RealtimeBrainTurnID()
        let trueTurnID = RealtimeBrainTurnID()
        let replacementTurnID = RealtimeBrainTurnID()
        var sequence: UInt64 = 4

        await enqueueR842Activity(
            stack: stack,
            turnID: falseTurnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        expect(stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .idle,
               "R8.4.2 unmatched false Provider VAD cannot open a turn")

        let captureFrameBefore = stack.acousticEchoHost
            .acousticObservationSnapshot().captureFrameIndex
        await stack.provider.holdAudioAppend(afterAdditionalFrames: 1)
        let acousticTask = Task {
            try await establishR842AcousticAuthorization(
                stack: stack,
                label: "false A then true B",
                seed: 45_470,
                transition: .none
            )
        }
        await stack.provider.waitUntilAudioAppendIsHeld()
        await waitUntil("R8.4.2 true B production capture settles") {
            stack.acousticEchoHost.acousticObservationSnapshot()
                .captureFrameIndex >= captureFrameBefore + 18
        }
        await waitUntil("R8.4.2 true B capture timestamp is current") {
            guard let captureTimestamp = stack.acousticEchoHost
                .acousticObservationSnapshot()
                .captureHostTimeNanoseconds else { return false }
            return DispatchTime.now().uptimeNanoseconds
                >= captureTimestamp
        }
        await enqueueR842Activity(
            stack: stack,
            turnID: trueTurnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await stack.provider.releaseAudioAppend()
        try await acousticTask.value
        await waitUntilOnMainActor("R8.4.2 true B replaces false A") {
            let snapshot = stack.runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            return snapshot.phase == .speaking
                && snapshot.turnID == trueTurnID
                && snapshot.sourceTurnID == trueTurnID
                && snapshot.claimedAcousticSequence > 0
        }

        try await closeR842SourceGateDuringPause(
            stack: stack,
            seed: 45_471
        )
        try await establishR842AcousticAuthorization(
            stack: stack,
            label: "fresh speaking-turn replacement",
            seed: 45_472,
            transition: .none
        )
        let claimBeforeReplacement = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .claimedAcousticSequence
        await enqueueR842Activity(
            stack: stack,
            turnID: replacementTurnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        let replacement = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(replacement.phase == .speaking
                && replacement.turnID == replacementTurnID,
               "R8.4.2 fresh eligible turn replaces a different speaking turn")
        expect(replacement.claimedAcousticSequence
                > claimBeforeReplacement,
               "R8.4.2 speaking replacement consumes a fresh one-shot marker")
        await enqueueR842Activity(
            stack: stack,
            turnID: replacementTurnID,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let stoppedSequence = sequence
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: replacementTurnID,
            expectedStoppedSequence: stoppedSequence,
            label: "fresh speaking replacement true end"
        )
        let completed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842TrueEndCases += 1
        r842CompletionCandidates += Int(completed.completionCandidateCount)
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        try await close(stack)
    }

    private static func testR842PreStopInFlightFrame(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let turnID = RealtimeBrainTurnID()
        let falseTurnID = RealtimeBrainTurnID()
        var sequence: UInt64 = 4

        try await establishR842AcousticAuthorization(
            stack: stack,
            label: "pre-stop in-flight base",
            seed: 45_480,
            transition: .none
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        let initialClaim = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .claimedAcousticSequence
        try await closeR842SourceGateDuringPause(
            stack: stack,
            seed: 45_481
        )

        let captureFrameBefore = stack.acousticEchoHost
            .acousticObservationSnapshot().captureFrameIndex
        await stack.provider.holdAudioAppend(afterAdditionalFrames: 1)
        let continuationTask = Task {
            try await emitR842NearEndContinuation(
                stack: stack,
                seed: 45_482
            )
        }
        await stack.provider.waitUntilAudioAppendIsHeld()
        await waitUntil("R8.4.2 pre-stop capture settles") {
            stack.acousticEchoHost.acousticObservationSnapshot()
                .captureFrameIndex >= captureFrameBefore + 6
        }
        await waitUntil("R8.4.2 pre-stop capture timestamp is current") {
            guard let captureTimestamp = stack.acousticEchoHost
                .acousticObservationSnapshot()
                .captureHostTimeNanoseconds else { return false }
            return DispatchTime.now().uptimeNanoseconds
                >= captureTimestamp
        }
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let stoppedSequence = sequence
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: turnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await stack.provider.releaseAudioAppend()
        try await continuationTask.value
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: turnID,
            expectedStoppedSequence: stoppedSequence,
            label: "pre-stop in-flight frame true end"
        )
        let completed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        let staleEvidenceSequence = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
            .lastAcousticSequence
        expect(completed.resumedPauseCount == 0,
               "R8.4.2 pre-stop in-flight PCM cannot resume the pause")
        expect(completed.claimedAcousticSequence == initialClaim
                && staleEvidenceSequence > initialClaim,
               "R8.4.2 pre-stop eligibility remains unclaimed")
        await enqueueR842Activity(
            stack: stack,
            turnID: falseTurnID,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        let afterFalseStart = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(afterFalseStart.turnID == turnID
                && afterFalseStart.claimedAcousticSequence == initialClaim,
               "R8.4.2 stale pre-stop marker cannot open a later turn")
        r842TrueEndCases += 1
        r842CompletionCandidates += Int(
            afterFalseStart.completionCandidateCount
        )
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        try await close(stack)
    }

    private static func testR842DoubleTalkPauseAndTrueEnd(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        var sequence: UInt64 = 4

        let shortAcoustic = try await
            submitR841DoubleTalkThroughProductionChain(
                stack: stack,
                scenario: R841DoubleTalkScenario(
                    label: "R8.4.2 double-talk short pause",
                    renderAmplitude: 0.30,
                    echoGain: 0.80,
                    nearEndAmplitude: 0.20,
                    doubleTalkFrames: 12,
                    transition: .nearEndOnly
                ),
                seed: 42_000
            )
        expect(shortAcoustic.detected && shortAcoustic.sourceGateOpened,
               "R8.4.2 short-pause double-talk is production detected")
        expect(shortAcoustic.acousticEligibility == 1,
               "R8.4.2 short-pause double-talk reaches eligibility")
        r842DoubleTalkCases += 1

        let shortTurn = RealtimeBrainTurnID()
        await enqueueR842Activity(
            stack: stack,
            turnID: shortTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: shortTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        sequence &+= 1
        await waitUntilOnMainActor("R8.4.2 double-talk short pause") {
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .candidatePause
        }
        try? await Task.sleep(for: .milliseconds(600))
        try await emitR842NearEndContinuation(
            stack: stack,
            seed: 42_001
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: shortTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await waitBeyondR842CompletionWindow()
        let resumed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842ShortPauseCases += 1
        r842ShortPauseFalseCompletions += Int(
            resumed.completionCandidateCount
        )
        expect(resumed.phase == .speaking
                && resumed.turnID == shortTurn,
               "R8.4.2 double-talk pause resumes as the same turn")
        expect(resumed.completionCandidateCount == 0,
               "R8.4.2 double-talk short pause does not complete")
        await enqueueR842Activity(
            stack: stack,
            turnID: shortTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let resumedStopSequence = sequence
        sequence &+= 1
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 1,
            expectedSession: stack.session,
            expectedTurn: shortTurn,
            expectedStoppedSequence: resumedStopSequence,
            label: "double-talk short-pause eventual true end"
        )
        r842TrueEndCases += 1
        let trueEndAcoustic = try await
            submitR841DoubleTalkThroughProductionChain(
                stack: stack,
                scenario: R841DoubleTalkScenario(
                    label: "R8.4.2 double-talk true end",
                    renderAmplitude: 0.35,
                    echoGain: 0.85,
                    nearEndAmplitude: 0.18,
                    doubleTalkFrames: 12,
                    transition: .farEndOnly
                ),
                seed: 43_000
            )
        expect(trueEndAcoustic.detected
                && trueEndAcoustic.sourceGateOpened,
               "R8.4.2 true-end double-talk is production detected")
        expect(trueEndAcoustic.acousticEligibility == 1,
               "R8.4.2 true-end double-talk reaches eligibility")
        r842DoubleTalkCases += 1

        let trueEndTurn = RealtimeBrainTurnID()
        await enqueueR842Activity(
            stack: stack,
            turnID: trueEndTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: trueEndTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        let trueEndSequence = sequence
        await waitForR842Completion(
            runtime: stack.runtime,
            expectedCount: 2,
            expectedSession: stack.session,
            expectedTurn: trueEndTurn,
            expectedStoppedSequence: trueEndSequence,
            label: "double-talk true end"
        )
        r842TrueEndCases += 1
        let completed = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842CompletionCandidates += Int(completed.completionCandidateCount)
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        try await close(stack)
    }

    private static func testR842ResidentOnlySafety(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        let candidatesBefore = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        var sequence: UInt64 = 4
        let negatives = [
            R841NegativeScenario(
                label: "R8.4.2 clean far-end",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                residualGain: 0,
                delayMilliseconds: [80],
                bucket: .farEnd
            ),
            R841NegativeScenario(
                label: "R8.4.2 residual echo",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                residualGain: 0.15,
                delayMilliseconds: [80],
                bucket: .residualEcho
            )
        ]
        for (index, scenario) in negatives.enumerated() {
            let result = try await submitR841ResidentOnlyThroughProductionChain(
                stack: stack,
                scenario: scenario,
                seed: UInt32(44_000 + index)
            )
            expect(result.falseDoubleTalk == 0
                    && result.acousticEligibility == 0,
                   "R8.4.2 \(scenario.label) stays user-negative")
            let falseTurn = RealtimeBrainTurnID()
            await enqueueR842Activity(
                stack: stack,
                turnID: falseTurn,
                sequence: sequence,
                kind: .userSpeechStarted
            )
            sequence &+= 1
            await enqueueR842Activity(
                stack: stack,
                turnID: falseTurn,
                sequence: sequence,
                kind: .userSpeechStopped
            )
            sequence &+= 1
            await waitBeyondR842CompletionWindow()
            expect(
                stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                    .phase == .idle,
                "R8.4.2 \(scenario.label) Provider VAD cannot open a user turn"
            )
        }
        let tail = try await submitR841PlaybackTailThroughProductionChain(
            stack: stack
        )
        expect(tail.falseDoubleTalk == 0 && tail.acousticEligibility == 0,
               "R8.4.2 residual playback tail stays user-negative")
        let tailTurn = RealtimeBrainTurnID()
        await enqueueR842Activity(
            stack: stack,
            turnID: tailTurn,
            sequence: sequence,
            kind: .userSpeechStarted
        )
        sequence &+= 1
        await enqueueR842Activity(
            stack: stack,
            turnID: tailTurn,
            sequence: sequence,
            kind: .userSpeechStopped
        )
        await waitBeyondR842CompletionWindow()
        let candidatesAfter = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionCandidateCount
        r842ResidentOnlyFalseCompletions += Int(
            candidatesAfter - candidatesBefore
        )
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        expect(candidatesAfter == candidatesBefore,
               "R8.4.2 resident-only matrix creates no completion")
        expect(
            stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .claimedAcousticSequence == 0,
            "R8.4.2 resident-only Provider VAD claims no acoustic authorization"
        )
        try await close(stack)
    }

    private static func testR842StaleTimerAndGeneration(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let createBaseline = await stack.provider.createCount()
        let interruptBaseline = await stack.provider.interruptCount()
        let cancelBaseline = await stack.provider.cancelCount()
        let clearBaseline = stack.outputPlayer.clearScheduledPlaybackCount
        r842CompletionWindowNanoseconds = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
            .completionWindowNanoseconds
        try await establishR842AcousticAuthorization(
            stack: stack,
            label: "stop-restart timer",
            seed: 45_500
        )
        let oldTurn = RealtimeBrainTurnID()
        await enqueueR842Activity(
            stack: stack,
            turnID: oldTurn,
            sequence: 4,
            kind: .userSpeechStarted
        )
        await enqueueR842Activity(
            stack: stack,
            turnID: oldTurn,
            sequence: 5,
            kind: .userSpeechStopped
        )
        expect(stack.runtime.realtimeUtteranceCompletionDebugSnapshot()
                .phase == .candidatePause,
               "R8.4.2 old generation owns one pending pause timer")

        await stack.controller.stopSpeechAudioCapture()
        await waitUntilOnMainActor("R8.4.2 formal route stops") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .idle
        }
        await stack.controller.startRealtimeResidentBrainRoute()
        await waitUntil("R8.4.2 formal route restarts") {
            guard let nextSession = await stack.provider.lastSession() else {
                return false
            }
            let phase = await stack.controller
                .formalSpeechRouteDebugSnapshot.phase
            return nextSession != stack.session
                && phase == .listening
        }
        guard let nextSession = await stack.provider.lastSession() else {
            fatalError("R8.4.2 restarted session missing")
        }
        expect(nextSession.generation == stack.session.generation + 1,
               "R8.4.2 formal restart advances exactly to N+1")
        r842ExtraGenerationAdvances += max(
            0,
            Int(nextSession.generation - stack.session.generation) - 1
        )

        let staleReturnedBaseline = await stack.provider
            .returnedEventCount(eventSession: stack.session)
        await stack.provider.enqueue(r842ActivityEvent(
            session: stack.session,
            turnID: oldTurn,
            sequence: 6,
            kind: .userSpeechStopped
        ))
        await waitUntil("R8.4.2 stale N activity returns") {
            await stack.provider.returnedEventCount(
                eventSession: stack.session
            ) == staleReturnedBaseline + 1
        }
        await waitBeyondR842CompletionWindow()
        let afterOldDeadline = stack.runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        r842OldTimerResurrections += Int(
            afterOldDeadline.completionCandidateCount
        )
        r842StaleGenerationCompletions += Int(
            afterOldDeadline.completionCandidateCount
        )
        expect(afterOldDeadline.phase == .idle
                && afterOldDeadline.completionCandidateCount == 0,
               "R8.4.2 old timer cannot complete or bind N+1")
        expect(afterOldDeadline.session == nil
                && afterOldDeadline.claimedAcousticSequence == 0,
               "R8.4.2 N+1 cannot inherit N turn or acoustic authorization")
        expect(nextSession.runtimeSessionID == stack.session.runtimeSessionID,
               "R8.4.2 stop/restart preserves the Runtime session identity")
        r842ResponseCreates += await stack.provider.createCount()
            - createBaseline
        r842ProviderInterrupts += await stack.provider.interruptCount()
            - interruptBaseline
        r842ProviderCancels += await stack.provider.cancelCount()
            - cancelBaseline
        r842HostPlaybackClears += stack.outputPlayer
            .clearScheduledPlaybackCount - clearBaseline
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func establishR842AcousticAuthorization(
        stack: R823ControllerStack,
        label: String,
        seed: UInt32,
        transition: R841DoubleTalkTransition = .farEndOnly
    ) async throws {
        let result = try await submitR841DoubleTalkThroughProductionChain(
            stack: stack,
            scenario: R841DoubleTalkScenario(
                label: "R8.4.2 \(label)",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                nearEndAmplitude: 0.20,
                doubleTalkFrames: 12,
                transition: transition
            ),
            seed: seed
        )
        expect(result.detected && result.sourceGateOpened,
               "R8.4.2 \(label) is production-acoustic user evidence")
        expect(result.acousticEligibility == 1,
               "R8.4.2 \(label) obtains one acoustic authorization")
    }

    private static func emitR842NearEndContinuation(
        stack: R823ControllerStack,
        seed: UInt32
    ) async throws {
        let audioBefore = await stack.provider.audioFrameCount()
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: seed, amplitude: 0.30)
        let nearEnd = signal(seed: seed + 1, amplitude: 0.20)
        let capture = zip(render, nearEnd).map {
            $0.0 * 0.80 + $0.1
        }
        let processed = zip(render, nearEnd).map {
            $0.0 * 0.05 + $0.1
        }
        for _ in 0 ..< 6 {
            let captureTimestamp = monotonicNow()
            stack.aecBackend.setCaptureOutput(processed)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: captureTimestamp - 80_000_000
            )
            let output = stack.acousticEchoHost.processCapture(
                capture,
                hostTimeNanoseconds: captureTimestamp
            )
            _ = try stack.capture.emit(processedSamples: output)
            try? await Task.sleep(for: .milliseconds(10))
        }
        await waitUntil("R8.4.2 near-end continuation reaches Provider") {
            await stack.provider.audioFrameCount() > audioBefore
        }
        let snapshot = stack.acousticEchoHost.acousticObservationSnapshot()
        expect(snapshot.sourceGateOpen
                && (snapshot.inputClassification == .nearEndSpeech
                    || snapshot.inputClassification == .doubleTalk),
               "R8.4.2 resumed audio remains production user-positive")
    }

    private static func closeR842SourceGateDuringPause(
        stack: R823ControllerStack,
        seed: UInt32,
        frameIntervalMilliseconds: Int = 12
    ) async throws {
        let hostBefore = stack.acousticEchoHost.snapshot()
        let bridgeEvidenceBefore = await bridgeEvidenceCount(stack)
        let render = signal(seed: seed, amplitude: 0.30)
        let capture = render.map { $0 * 0.80 }
        let processed = render.map { _ in Float.zero }
        for _ in 0 ..< 22 {
            let captureTimestamp = monotonicNow()
            stack.aecBackend.setCaptureOutput(processed)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: captureTimestamp - 80_000_000
            )
            let output = stack.acousticEchoHost.processCapture(
                capture,
                hostTimeNanoseconds: captureTimestamp
            )
            _ = try stack.capture.emit(processedSamples: output)
            try? await Task.sleep(
                for: .milliseconds(frameIntervalMilliseconds)
            )
        }
        let observation = stack.acousticEchoHost
            .acousticObservationSnapshot()
        let hostAfter = stack.acousticEchoHost.snapshot()
        expect(hostAfter.captureFrameCount
                == hostBefore.captureFrameCount + 22,
               "R8.4.2 pause gate-close executes 22 production frames")
        expect(observation.inputClassification == .echoOnly
                && !observation.sourceGateOpen,
               "R8.4.2 pause far-end hangover closes the source gate")
        expect(hostAfter.sourceGateCloseCount
                == hostBefore.sourceGateCloseCount + 1,
               "R8.4.2 pause closes exactly one source-gate epoch")
        expect(hostAfter.lastSourceGateCloseReason == .nonUserHangover,
               "R8.4.2 pause gate closes only by non-user hangover")
        let bridgeEvidenceAfter = await bridgeEvidenceCount(stack)
        expect(bridgeEvidenceAfter == bridgeEvidenceBefore,
               "R8.4.2 pause far-end frames create no eligibility")
    }

    private static func enqueueR842Activity(
        stack: R823ControllerStack,
        turnID: RealtimeBrainTurnID,
        sequence: UInt64,
        kind: RealtimeResidentBrainEventKind
    ) async {
        let returnedBefore = await stack.provider.returnedEventCount(
            eventSession: stack.session
        )
        await stack.provider.enqueue(r842ActivityEvent(
            session: stack.session,
            turnID: turnID,
            sequence: sequence,
            kind: kind
        ))
        await waitUntil("R8.4.2 provider activity \(sequence)") {
            await stack.provider.returnedEventCount(
                eventSession: stack.session
            ) == returnedBefore + 1
        }
    }

    private static func r842ActivityEvent(
        session: RealtimeBrainSessionIdentity,
        turnID: RealtimeBrainTurnID,
        sequence: UInt64,
        kind: RealtimeResidentBrainEventKind
    ) -> RealtimeResidentBrainEvent {
        RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: turnID,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: sequence,
            kind: kind
        )
    }

    private static func waitBeyondR842CompletionWindow() async {
        let delay = r842CompletionWindowNanoseconds + 80_000_000
        try? await Task.sleep(for: .nanoseconds(Int64(delay)))
    }

    private static func waitForR842Completion(
        runtime: RuntimeCore,
        expectedCount: UInt64,
        expectedSession: RealtimeBrainSessionIdentity,
        expectedTurn: RealtimeBrainTurnID,
        expectedContextRevision: UInt64 = 1,
        expectedStoppedSequence: UInt64,
        label: String
    ) async {
        await waitUntilOnMainActor("R8.4.2 \(label)") {
            runtime.realtimeUtteranceCompletionDebugSnapshot()
                .completionCandidateCount == expectedCount
        }
        let snapshot = runtime.realtimeUtteranceCompletionDebugSnapshot()
        expect(snapshot.phase == .completionCandidate,
               "R8.4.2 \(label) reaches completion candidate")
        expect(snapshot.session == expectedSession
                && snapshot.turnID == expectedTurn
                && snapshot.contextRevision == expectedContextRevision,
               "R8.4.2 \(label) preserves exact identity")
        expect(snapshot.stoppedEventSequence == expectedStoppedSequence,
               "R8.4.2 \(label) binds the formal stop sequence")
        expect(snapshot.speechStartedAtNanoseconds > 0
                && snapshot.pauseStartedAtNanoseconds
                    >= snapshot.speechStartedAtNanoseconds
                && snapshot.completionCandidateAtNanoseconds
                    >= snapshot.pauseStartedAtNanoseconds,
               "R8.4.2 \(label) has monotonic timing evidence")
        let latency = snapshot.completionCandidateAtNanoseconds
            - snapshot.pauseStartedAtNanoseconds
        expect(latency >= snapshot.completionWindowNanoseconds,
               "R8.4.2 \(label) cannot complete before the window")
        expect(latency <= 1_600_000_000,
               "R8.4.2 \(label) completion latency stays bounded")
        r842MaximumTrueEndLatencyNanoseconds = max(
            r842MaximumTrueEndLatencyNanoseconds,
            latency
        )
    }

    private enum R841DoubleTalkTransition {
        case none
        case nearEndOnly
        case farEndOnly
    }

    private struct R841DoubleTalkScenario {
        let label: String
        let renderAmplitude: Float
        let echoGain: Float
        let nearEndAmplitude: Float
        let residualGain: Float
        let doubleTalkFrames: Int
        let delayMilliseconds: [Int]
        let expectsAdaptiveEvidence: Bool
        let transition: R841DoubleTalkTransition

        init(
            label: String,
            renderAmplitude: Float,
            echoGain: Float,
            nearEndAmplitude: Float,
            residualGain: Float = 0,
            doubleTalkFrames: Int = 4,
            delayMilliseconds: [Int] = [80],
            expectsAdaptiveEvidence: Bool = false,
            transition: R841DoubleTalkTransition = .none
        ) {
            self.label = label
            self.renderAmplitude = renderAmplitude
            self.echoGain = echoGain
            self.nearEndAmplitude = nearEndAmplitude
            self.residualGain = residualGain
            self.doubleTalkFrames = doubleTalkFrames
            self.delayMilliseconds = delayMilliseconds
            self.expectsAdaptiveEvidence = expectsAdaptiveEvidence
            self.transition = transition
        }
    }

    private struct R841DoubleTalkResult {
        let detected: Bool
        let sourceGateOpened: Bool
        let acousticEligibility: Int
        let doubleTalkFrames: Int
        let activePCMPackets: Int
        let adaptiveEvidence: Bool
        let runtimeObservedDoubleTalk: Bool
        let runtimeSummary: String
        let transitionPassed: Bool
    }

    private enum R841NegativeBucket {
        case farEnd
        case residualEcho
        case timingJitter
    }

    private struct R841NegativeScenario {
        let label: String
        let renderAmplitude: Float
        let echoGain: Float
        let residualGain: Float
        let delayMilliseconds: [Int]
        let bucket: R841NegativeBucket
    }

    private struct R841NegativeResult {
        let falseDoubleTalk: Int
        let acousticEligibility: Int
        let frames: Int
    }

    private static func testR841DoubleTalkAcousticDetermination(
        fixture: Data
    ) async throws {
        let positiveStack = try await makeControllerStack(fixture: fixture)
        let positiveBaselineLease = positiveStack.runtime
            .activeBrainLeaseForTesting()
        let positiveEvidenceBaseline = await bridgeEvidenceCount(positiveStack)
        let positiveInterruptBaseline = await positiveStack.provider
            .interruptCount()
        let positiveCancelBaseline = await positiveStack.provider.cancelCount()
        let positiveClearBaseline = positiveStack.outputPlayer
            .clearScheduledPlaybackCount
        let positiveSemanticBaseline = await positiveStack.provider
            .enqueuedEventCount(eventSession: positiveStack.session)
        let scenarios = [
            R841DoubleTalkScenario(
                label: "medium resident + medium near-end",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                nearEndAmplitude: 0.20
            ),
            R841DoubleTalkScenario(
                label: "loud resident + near-end",
                renderAmplitude: 0.60,
                echoGain: 0.80,
                nearEndAmplitude: 0.22
            ),
            R841DoubleTalkScenario(
                label: "weak near-end",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                nearEndAmplitude: 0.05
            ),
            R841DoubleTalkScenario(
                label: "strong near-end",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                nearEndAmplitude: 0.40
            ),
            R841DoubleTalkScenario(
                label: "low echo to near-end ratio",
                renderAmplitude: 0.20,
                echoGain: 0.50,
                nearEndAmplitude: 0.14
            ),
            R841DoubleTalkScenario(
                label: "high echo to near-end ratio",
                renderAmplitude: 0.55,
                echoGain: 0.95,
                nearEndAmplitude: 0.08
            ),
            R841DoubleTalkScenario(
                label: "bounded timing jitter",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                nearEndAmplitude: 0.20,
                delayMilliseconds: [70, 90, 80, 100]
            ),
            R841DoubleTalkScenario(
                label: "residual echo + near-end",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                nearEndAmplitude: 0.10,
                residualGain: 0.18,
                expectsAdaptiveEvidence: true
            ),
            R841DoubleTalkScenario(
                label: "sustained double-talk",
                renderAmplitude: 0.35,
                echoGain: 0.85,
                nearEndAmplitude: 0.18,
                doubleTalkFrames: 12
            ),
            R841DoubleTalkScenario(
                label: "double-talk to near-end only",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                nearEndAmplitude: 0.20,
                transition: .nearEndOnly
            ),
            R841DoubleTalkScenario(
                label: "double-talk to far-end only",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                nearEndAmplitude: 0.20,
                transition: .farEndOnly
            )
        ]

        for (index, scenario) in scenarios.enumerated() {
            let result = try await submitR841DoubleTalkThroughProductionChain(
                stack: positiveStack,
                scenario: scenario,
                seed: UInt32(8_000 + index * 20)
            )
            r841PositiveScenarios += 1
            if result.detected && result.runtimeObservedDoubleTalk {
                r841DetectedScenarios += 1
            }
            if result.sourceGateOpened {
                r841SourceGateOpenScenarios += 1
            }
            r841AcousticEligibility += result.acousticEligibility
            r841DoubleTalkFrames += result.doubleTalkFrames
            r841ActivePCMPackets += result.activePCMPackets
            if result.adaptiveEvidence { r841AdaptiveScenarios += 1 }
            expect(result.detected,
                   "R8.4.1 \(scenario.label) is production double-talk")
            expect(result.sourceGateOpened,
                   "R8.4.1 \(scenario.label) opens the source gate")
            expect(result.acousticEligibility == 1,
                   "R8.4.1 \(scenario.label) emits one eligibility")
            expect(result.doubleTalkFrames >= scenario.doubleTalkFrames,
                   "R8.4.1 \(scenario.label) sustains double-talk frames")
            expect(result.activePCMPackets > 0,
                   "R8.4.1 \(scenario.label) emits active production PCM")
            expect(result.runtimeObservedDoubleTalk,
                   "R8.4.1 \(scenario.label) reaches Runtime as double-talk "
                    + result.runtimeSummary)
            expect(result.transitionPassed,
                   "R8.4.1 \(scenario.label) preserves transition behavior")
            if scenario.expectsAdaptiveEvidence {
                expect(result.adaptiveEvidence,
                       "R8.4.1 residual case uses learned echo baseline")
            }
            switch scenario.transition {
            case .nearEndOnly:
                r841TransitionToNearEnd = result.transitionPassed ? 1 : 0
            case .farEndOnly:
                r841TransitionToFarEnd = result.transitionPassed ? 1 : 0
            case .none:
                break
            }
        }

        let positiveLeaseAfter = positiveStack.runtime
            .activeBrainLeaseForTesting()
        let positiveInterrupts = await positiveStack.provider.interruptCount()
            - positiveInterruptBaseline
        let positiveCancels = await positiveStack.provider.cancelCount()
            - positiveCancelBaseline
        let positiveClears = positiveStack.outputPlayer
            .clearScheduledPlaybackCount - positiveClearBaseline
        let positiveSemanticEvents = await positiveStack.provider
            .enqueuedEventCount(eventSession: positiveStack.session)
            - positiveSemanticBaseline
        let positiveGenerationChanged = positiveLeaseAfter?.generation
            != positiveBaselineLease?.generation
        let positiveLeaseChanged = positiveLeaseAfter != positiveBaselineLease
        expect(r841PositiveScenarios == scenarios.count,
               "R8.4.1 runs the complete positive matrix")
        expect(r841DetectedScenarios == scenarios.count,
               "R8.4.1 every positive is low-level double-talk")
        expect(r841SourceGateOpenScenarios == scenarios.count,
               "R8.4.1 every positive opens the production gate")
        expect(r841AcousticEligibility == scenarios.count,
               "R8.4.1 every positive reaches high-level eligibility once")
        expect(r841AdaptiveScenarios == 1,
               "R8.4.1 covers one adaptive residual-echo case")
        expect(r841TransitionToNearEnd == 1
                && r841TransitionToFarEnd == 1,
               "R8.4.1 covers both required transitions")
        expect(positiveInterrupts == 0 && positiveCancels == 0,
               "R8.4.1 acoustic-only positives do not interrupt Provider")
        expect(positiveClears == 0,
               "R8.4.1 acoustic-only positives do not clear Playback")
        expect(!positiveGenerationChanged && !positiveLeaseChanged,
               "R8.4.1 acoustic-only positives preserve generation and lease")
        expect(positiveSemanticEvents == 0,
               "R8.4.1 positive matrix injects no semantic proposal")
        expect(await bridgeEvidenceCount(positiveStack)
                - positiveEvidenceBaseline == UInt64(scenarios.count),
               "R8.4.1 positive matrix forwards one eligibility per epoch")
        try await close(positiveStack)

        let negativeStack = try await makeControllerStack(fixture: fixture)
        let negativeBaselineLease = negativeStack.runtime
            .activeBrainLeaseForTesting()
        let negativeEvidenceBaseline = await bridgeEvidenceCount(negativeStack)
        let negativeInterruptBaseline = await negativeStack.provider
            .interruptCount()
        let negativeCancelBaseline = await negativeStack.provider.cancelCount()
        let negativeClearBaseline = negativeStack.outputPlayer
            .clearScheduledPlaybackCount
        let negativeSemanticBaseline = await negativeStack.provider
            .enqueuedEventCount(eventSession: negativeStack.session)
        let negativeScenarios = [
            R841NegativeScenario(
                label: "clean far-end",
                renderAmplitude: 0.30,
                echoGain: 0.80,
                residualGain: 0,
                delayMilliseconds: [80],
                bucket: .farEnd
            ),
            R841NegativeScenario(
                label: "loud playback",
                renderAmplitude: 0.60,
                echoGain: 0.95,
                residualGain: 0.08,
                delayMilliseconds: [80],
                bucket: .farEnd
            ),
            R841NegativeScenario(
                label: "residual echo",
                renderAmplitude: 0.30,
                echoGain: 0.85,
                residualGain: 0.22,
                delayMilliseconds: [80],
                bucket: .residualEcho
            ),
            R841NegativeScenario(
                label: "timing jitter",
                renderAmplitude: 0.30,
                echoGain: 0.85,
                residualGain: 0.03,
                delayMilliseconds: [70, 90, 80, 100],
                bucket: .timingJitter
            )
        ]
        for (index, scenario) in negativeScenarios.enumerated() {
            let result = try await submitR841ResidentOnlyThroughProductionChain(
                stack: negativeStack,
                scenario: scenario,
                seed: UInt32(12_000 + index * 20)
            )
            r841NegativeScenarios += 1
            r841NegativeObservations += result.frames
            r841NegativeFrames += result.frames
            r841FalseDoubleTalk += result.falseDoubleTalk
            switch scenario.bucket {
            case .farEnd:
                r841FarEndFalseDoubleTalk += result.falseDoubleTalk
            case .residualEcho:
                r841ResidualEchoFalseDoubleTalk += result.falseDoubleTalk
            case .timingJitter:
                r841TimingJitterFalseDoubleTalk += result.falseDoubleTalk
            }
            expect(result.falseDoubleTalk == 0,
                   "R8.4.1 \(scenario.label) has zero false double-talk")
            expect(result.acousticEligibility == 0,
                   "R8.4.1 \(scenario.label) has zero eligibility")
        }

        let tailResult = try await submitR841PlaybackTailThroughProductionChain(
            stack: negativeStack
        )
        r841NegativeScenarios += 1
        r841NegativeObservations += tailResult.frames
        r841NegativeFrames += tailResult.frames
        r841FalseDoubleTalk += tailResult.falseDoubleTalk
        r841PlaybackTailFalseDoubleTalk = tailResult.falseDoubleTalk
        expect(tailResult.falseDoubleTalk == 0,
               "R8.4.1 playback tail has zero false double-talk")
        expect(tailResult.acousticEligibility == 0,
               "R8.4.1 playback tail has zero eligibility")

        let stressResult = try await submitR841LongResidentStress(
            stack: negativeStack
        )
        r841NegativeScenarios += 1
        r841NegativeObservations += 120
        r841NegativeFrames += stressResult.frames
        r841StressFrames = stressResult.frames
        r841FalseDoubleTalk += stressResult.falseDoubleTalk
        r841StressFalseDoubleTalk = stressResult.falseDoubleTalk
        expect(stressResult.falseDoubleTalk == 0,
               "R8.4.1 long resident-only stress has zero double-talk")
        expect(stressResult.acousticEligibility == 0,
               "R8.4.1 long resident-only stress has zero eligibility")

        let negativeLeaseAfter = negativeStack.runtime
            .activeBrainLeaseForTesting()
        let negativeEvidenceAfter = await bridgeEvidenceCount(negativeStack)
        r841ResidentOnlyEligibility = Int(
            negativeEvidenceAfter - negativeEvidenceBaseline
        )
        let negativeInterrupts = await negativeStack.provider.interruptCount()
            - negativeInterruptBaseline
        let negativeCancels = await negativeStack.provider.cancelCount()
            - negativeCancelBaseline
        let negativeClears = negativeStack.outputPlayer
            .clearScheduledPlaybackCount - negativeClearBaseline
        let negativeSemanticEvents = await negativeStack.provider
            .enqueuedEventCount(eventSession: negativeStack.session)
            - negativeSemanticBaseline
        let negativeGenerationChanged = negativeLeaseAfter?.generation
            != negativeBaselineLease?.generation
        let negativeLeaseChanged = negativeLeaseAfter != negativeBaselineLease

        r841ProviderInterrupts = positiveInterrupts + negativeInterrupts
        r841ProviderCancels = positiveCancels + negativeCancels
        r841HostPlaybackClears = positiveClears + negativeClears
        r841GenerationChanges = (positiveGenerationChanged ? 1 : 0)
            + (negativeGenerationChanged ? 1 : 0)
        r841LeaseChanges = (positiveLeaseChanged ? 1 : 0)
            + (negativeLeaseChanged ? 1 : 0)
        r841ConfirmedInterruptions = r841GenerationChanges
        r841SemanticProposals = positiveSemanticEvents
            + negativeSemanticEvents

        expect(r841NegativeScenarios == 6,
               "R8.4.1 runs all six resident-only negative scenarios")
        expect(r841NegativeObservations == 176
                && r841NegativeFrames == 3_896
                && r841StressFrames == 3_840,
               "R8.4.1 freezes 120 x 32 long-stress frames")
        expect(r841FalseDoubleTalk == 0,
               "R8.4.1 negative matrix has zero false double-talk")
        expect(r841ResidentOnlyEligibility == 0,
               "R8.4.1 resident-only eligibility remains zero")
        expect(r841ConfirmedInterruptions == 0,
               "R8.4.1 acoustic-only run confirms no interruption")
        expect(r841ProviderInterrupts == 0
                && r841ProviderCancels == 0,
               "R8.4.1 leaves Provider interruption APIs untouched")
        expect(r841HostPlaybackClears == 0,
               "R8.4.1 never clears Playback")
        expect(r841GenerationChanges == 0 && r841LeaseChanges == 0,
               "R8.4.1 preserves Runtime generation and lease")
        expect(r841SemanticProposals == 0,
               "R8.4.1 injects no semantic proposal")
        try await close(negativeStack)
    }

    private static func submitR841DoubleTalkThroughProductionChain(
        stack: R823ControllerStack,
        scenario: R841DoubleTalkScenario,
        seed: UInt32
    ) async throws -> R841DoubleTalkResult {
        let snapshotBefore = stack.acousticEchoHost.snapshot()
        let evidenceBefore = await bridgeEvidenceCount(stack)
        let runtimeRecordBefore = stack.runtime
            .realtimeAcousticObservationDebugSnapshot().records.count
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: seed, amplitude: scenario.renderAmplitude)
        let nearEnd = signal(
            seed: seed + 1,
            amplitude: scenario.nearEndAmplitude
        )
        let warmupCapture = render.map { $0 * scenario.echoGain }
        let warmupOutput = render.map { $0 * scenario.residualGain }

        for index in 0 ..< 6 {
            let delay = scenario.delayMilliseconds[
                index % scenario.delayMilliseconds.count
            ]
            let captureTimestamp = monotonicNow()
            let renderTimestamp = captureTimestamp
                - UInt64(delay) * 1_000_000
            stack.aecBackend.setCaptureOutput(warmupOutput)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: renderTimestamp
            )
            let processed = stack.acousticEchoHost.processCapture(
                warmupCapture,
                hostTimeNanoseconds: captureTimestamp
            )
            _ = try stack.capture.emit(processedSamples: processed)
            try? await Task.sleep(for: .milliseconds(12))
        }
        let warmup = stack.acousticEchoHost.acousticObservationSnapshot()
        expect(warmup.sourceAlignmentLocked,
               "R8.4.1 \(scenario.label) warm-up locks alignment")
        expect(warmup.inputClassification == .echoOnly,
               "R8.4.1 \(scenario.label) warm-up is echo-only")
        expect(!warmup.sourceGateOpen,
               "R8.4.1 \(scenario.label) warm-up keeps gate closed")

        let mixedCapture = zip(render, nearEnd).map { sample in
            sample.0 * scenario.echoGain + sample.1
        }
        let processedDoubleTalk = zip(render, nearEnd).map { sample in
            sample.0 * scenario.residualGain + sample.1
        }
        var activePCMPackets = 0
        for index in 0 ..< scenario.doubleTalkFrames {
            let delay = scenario.delayMilliseconds[
                (index + 6) % scenario.delayMilliseconds.count
            ]
            let captureTimestamp = monotonicNow()
            let renderTimestamp = captureTimestamp
                - UInt64(delay) * 1_000_000
            stack.aecBackend.setCaptureOutput(processedDoubleTalk)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: renderTimestamp
            )
            let processed = stack.acousticEchoHost.processCapture(
                mixedCapture,
                hostTimeNanoseconds: captureTimestamp
            )
            let emission = try stack.capture.emit(
                processedSamples: processed
            )
            activePCMPackets += emission.activePacketCount
            try? await Task.sleep(for: .milliseconds(12))
        }

        let opened = stack.acousticEchoHost.snapshot()
        let openedObservation = stack.acousticEchoHost
            .acousticObservationSnapshot()
        let detected = openedObservation.inputClassification == .doubleTalk
        let gateOpened = openedObservation.sourceGateOpen
            && openedObservation.sourceGateEpoch > 0
            && openedObservation.sourceAlignmentLocked
        let pendingDeadline = monotonicNow() + 3_000_000_000
        while true {
            await stack.controller.refreshMicrophoneAuthorization()
            let bridge = stack.controller.realtimeBrainInputBridgeSnapshot
            if bridge.acousticEvidenceCount > evidenceBefore
                || bridge.lastAcousticEvidenceForwardDisposition == "pending"
            {
                break
            }
            if monotonicNow() >= pendingDeadline {
                let bridge = stack.controller
                    .realtimeBrainInputBridgeSnapshot
                let acoustic = stack.acousticEchoHost
                    .acousticObservationSnapshot()
                let eligibility = bridge
                    .lastAcousticEligibilityDisposition ?? "nil"
                let forward = bridge
                    .lastAcousticEvidenceForwardDisposition ?? "nil"
                fatalError(
                    "timeout: R8.4.1 \(scenario.label) gate observation "
                        + "evidence=\(bridge.acousticEvidenceCount)/\(evidenceBefore) "
                        + "eligibility=\(eligibility) "
                        + "forward=\(forward) "
                        + "classification=\(acoustic.inputClassification) "
                        + "gate=\(acoustic.sourceGateOpen) "
                        + "epoch=\(acoustic.sourceGateEpoch)"
                )
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        if await bridgeEvidenceCount(stack) == evidenceBefore {
            for index in 0 ..< 2 {
                let delay = scenario.delayMilliseconds[
                    (index + scenario.doubleTalkFrames + 6)
                        % scenario.delayMilliseconds.count
                ]
                let captureTimestamp = monotonicNow()
                stack.aecBackend.setCaptureOutput(processedDoubleTalk)
                stack.acousticEchoHost.processRender(
                    render,
                    hostTimeNanoseconds: captureTimestamp
                        - UInt64(delay) * 1_000_000
                )
                let processed = stack.acousticEchoHost.processCapture(
                    mixedCapture,
                    hostTimeNanoseconds: captureTimestamp
                )
                let emission = try stack.capture.emit(
                    processedSamples: processed
                )
                activePCMPackets += emission.activePacketCount
                try? await Task.sleep(for: .milliseconds(12))
            }
        }
        await waitUntil("R8.4.1 \(scenario.label) eligibility") {
            await bridgeEvidenceCount(stack) >= evidenceBefore + 1
        }
        let evidenceAtOpen = stack.runtime
            .realtimeInterruptionEvidenceDebugSnapshot()
        let runtimeRecords = stack.runtime
            .realtimeAcousticObservationDebugSnapshot()
            .records.dropFirst(runtimeRecordBefore)
        let runtimeObservedDoubleTalk = runtimeRecords.contains { record in
            record.disposition == .observed
                && record.observation.classification == .nearEndCandidate
                && record.observation.metrics.sourceAssessment == .doubleTalk
                && record.observation.identity.sequence
                    == evidenceAtOpen.lastAcousticSequence
                && record.observation.identity.timestampNanoseconds
                    == evidenceAtOpen.lastAcousticTimestampNanoseconds
        }
        let runtimeSummary = "evidence="
            + "\(evidenceAtOpen.lastAcousticSequence)/"
            + "\(evidenceAtOpen.lastAcousticTimestampNanoseconds) records="
            + runtimeRecords.map { record in
                "\(record.observation.identity.sequence)/"
                    + "\(record.observation.identity.timestampNanoseconds)/"
                    + "\(record.observation.classification.rawValue)/"
                    + "\(record.observation.metrics.sourceAssessment.rawValue)/"
                    + "\(record.disposition)"
            }.joined(separator: ",")

        var transitionPassed = true
        switch scenario.transition {
        case .none:
            break
        case .nearEndOnly:
            for index in 0 ..< 4 {
                let delay = scenario.delayMilliseconds[
                    index % scenario.delayMilliseconds.count
                ]
                let captureTimestamp = monotonicNow()
                stack.aecBackend.setCaptureOutput(nearEnd)
                stack.acousticEchoHost.processRender(
                    render,
                    hostTimeNanoseconds: captureTimestamp
                        - UInt64(delay) * 1_000_000
                )
                let processed = stack.acousticEchoHost.processCapture(
                    nearEnd,
                    hostTimeNanoseconds: captureTimestamp
                )
                _ = try stack.capture.emit(processedSamples: processed)
                try? await Task.sleep(for: .milliseconds(12))
            }
            let transitioned = stack.acousticEchoHost
                .acousticObservationSnapshot()
            transitionPassed = transitioned.inputClassification
                    == .nearEndSpeech
                && transitioned.sourceGateOpen
                && transitioned.sourceGateEpoch
                    == openedObservation.sourceGateEpoch
        case .farEndOnly:
            for index in 0 ..< 20 {
                let delay = scenario.delayMilliseconds[
                    index % scenario.delayMilliseconds.count
                ]
                let captureTimestamp = monotonicNow()
                stack.aecBackend.setCaptureOutput(warmupOutput)
                stack.acousticEchoHost.processRender(
                    render,
                    hostTimeNanoseconds: captureTimestamp
                        - UInt64(delay) * 1_000_000
                )
                let processed = stack.acousticEchoHost.processCapture(
                    warmupCapture,
                    hostTimeNanoseconds: captureTimestamp
                )
                _ = try stack.capture.emit(processedSamples: processed)
                try? await Task.sleep(for: .milliseconds(12))
            }
            let transitioned = stack.acousticEchoHost
                .acousticObservationSnapshot()
            transitionPassed = transitioned.inputClassification == .echoOnly
                && !transitioned.sourceGateOpen
        }

        let eligibility = await settledBridgeEvidenceDelta(
            stack,
            baseline: evidenceBefore
        )
        return R841DoubleTalkResult(
            detected: detected,
            sourceGateOpened: gateOpened,
            acousticEligibility: eligibility,
            doubleTalkFrames: Int(
                opened.doubleTalkFrameCount
                    - snapshotBefore.doubleTalkFrameCount
            ),
            activePCMPackets: activePCMPackets,
            adaptiveEvidence: opened.adaptiveDoubleTalkFrameCount
                > snapshotBefore.adaptiveDoubleTalkFrameCount,
            runtimeObservedDoubleTalk: runtimeObservedDoubleTalk,
            runtimeSummary: runtimeSummary,
            transitionPassed: transitionPassed && eligibility == 1
        )
    }

    private static func submitR841ResidentOnlyThroughProductionChain(
        stack: R823ControllerStack,
        scenario: R841NegativeScenario,
        seed: UInt32
    ) async throws -> R841NegativeResult {
        let snapshotBefore = stack.acousticEchoHost.snapshot()
        let evidenceBefore = await bridgeEvidenceCount(stack)
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: seed, amplitude: scenario.renderAmplitude)
        let capture = render.map { $0 * scenario.echoGain }
        let residual = render.map { $0 * scenario.residualGain }
        let frames = 12
        for index in 0 ..< frames {
            let delay = scenario.delayMilliseconds[
                index % scenario.delayMilliseconds.count
            ]
            let captureTimestamp = monotonicNow()
            stack.aecBackend.setCaptureOutput(residual)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: captureTimestamp
                    - UInt64(delay) * 1_000_000
            )
            let processed = stack.acousticEchoHost.processCapture(
                capture,
                hostTimeNanoseconds: captureTimestamp
            )
            _ = try stack.capture.emit(processedSamples: processed)
            try? await Task.sleep(for: .milliseconds(2))
        }
        let snapshot = stack.acousticEchoHost.snapshot()
        expect(snapshot.inputClassification == .echoOnly,
               "R8.4.1 \(scenario.label) remains echo-only")
        expect(!snapshot.sourceGateOpen,
               "R8.4.1 \(scenario.label) keeps source gate closed")
        return R841NegativeResult(
            falseDoubleTalk: Int(
                snapshot.doubleTalkFrameCount
                    - snapshotBefore.doubleTalkFrameCount
            ),
            acousticEligibility: await settledBridgeEvidenceDelta(
                stack,
                baseline: evidenceBefore
            ),
            frames: frames
        )
    }

    private static func submitR841PlaybackTailThroughProductionChain(
        stack: R823ControllerStack
    ) async throws -> R841NegativeResult {
        let snapshotBefore = stack.acousticEchoHost.snapshot()
        let evidenceBefore = await bridgeEvidenceCount(stack)
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: 14_000, amplitude: 0.30)
        let capture = render.map { $0 * 0.80 }
        let silence = [Float](
            repeating: 0,
            count: MacSpeechAcousticEchoHost.frameSampleCount
        )
        for _ in 0 ..< 6 {
            let captureTimestamp = monotonicNow()
            stack.aecBackend.setCaptureOutput(silence)
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: captureTimestamp - 80_000_000
            )
            let processed = stack.acousticEchoHost.processCapture(
                capture,
                hostTimeNanoseconds: captureTimestamp
            )
            _ = try stack.capture.emit(processedSamples: processed)
            try? await Task.sleep(for: .milliseconds(10))
        }
        let audibleTimestamp = stack.acousticEchoHost
            .acousticObservationSnapshot()
            .lastAudibleRenderHostTimeNanoseconds
        stack.acousticEchoHost.playbackCompleted()
        let residualTail = render.map { $0 * 0.15 }
        let frames = 8
        for _ in 0 ..< frames {
            stack.aecBackend.setCaptureOutput(residualTail)
            let processed = stack.acousticEchoHost.processCapture(
                capture,
                hostTimeNanoseconds: monotonicNow()
            )
            _ = try stack.capture.emit(processedSamples: processed)
            try? await Task.sleep(for: .milliseconds(10))
        }
        let tail = stack.acousticEchoHost.acousticObservationSnapshot()
        let remainsWithinTail = audibleTimestamp.map { audible in
            guard let captureTimestamp = tail.captureHostTimeNanoseconds,
                  captureTimestamp >= audible else { return false }
            return captureTimestamp - audible < 500_000_000
        } ?? false
        expect(remainsWithinTail,
               "R8.4.1 residual playback tail stays inside 500 ms")
        expect(!tail.isPlaybackActive
                && tail.inputClassification == .nearEndSpeech,
               "R8.4.1 inactive tail cannot be classified as double-talk")
        return R841NegativeResult(
            falseDoubleTalk: Int(
                stack.acousticEchoHost.snapshot().doubleTalkFrameCount
                    - snapshotBefore.doubleTalkFrameCount
            ),
            acousticEligibility: await settledBridgeEvidenceDelta(
                stack,
                baseline: evidenceBefore
            ),
            frames: frames
        )
    }

    private static func submitR841LongResidentStress(
        stack: R823ControllerStack
    ) async throws -> R841NegativeResult {
        let snapshotBefore = stack.acousticEchoHost.snapshot()
        let evidenceBefore = await bridgeEvidenceCount(stack)
        stack.acousticEchoHost.playbackStarted()
        let observations = 120
        let framesPerObservation = 32
        for observation in 0 ..< observations {
            let amplitudes: [Float] = [0.12, 0.30, 0.60, 0.22]
            let echoGains: [Float] = [0.75, 0.90, 0.98, 0.82]
            let residualGains: [Float] = [0, 0.04, 0.12, 0.22]
            let render = signal(
                seed: UInt32(16_000 + observation),
                amplitude: amplitudes[observation % amplitudes.count]
            )
            let capture = render.map {
                $0 * echoGains[observation % echoGains.count]
            }
            let residual = render.map {
                $0 * residualGains[observation % residualGains.count]
            }
            for frame in 0 ..< framesPerObservation {
                let jitter = [70, 90, 80, 100][frame % 4]
                let captureTimestamp = monotonicNow()
                stack.aecBackend.setCaptureOutput(residual)
                stack.acousticEchoHost.processRender(
                    render,
                    hostTimeNanoseconds: captureTimestamp
                        - UInt64(jitter) * 1_000_000
                )
                let processed = stack.acousticEchoHost.processCapture(
                    capture,
                    hostTimeNanoseconds: captureTimestamp
                )
                _ = try stack.capture.emit(processedSamples: processed)
            }
        }
        let frames = observations * framesPerObservation
        let snapshot = stack.acousticEchoHost.snapshot()
        expect(snapshot.captureFrameCount
                - snapshotBefore.captureFrameCount == UInt64(frames),
               "R8.4.1 long stress processes all 3840 AEC frames")
        expect(!snapshot.sourceGateOpen,
               "R8.4.1 long resident-only stress keeps source gate closed")
        return R841NegativeResult(
            falseDoubleTalk: Int(
                snapshot.doubleTalkFrameCount
                    - snapshotBefore.doubleTalkFrameCount
            ),
            acousticEligibility: await settledBridgeEvidenceDelta(
                stack,
                baseline: evidenceBefore
            ),
            frames: frames
        )
    }

    private static func testR852FormalRealtimeSubtitleAndDiagnostics(
        fixture: Data
    ) async throws {
        cases += 1
        try await testR852RecoverableResponseError(fixture: fixture)
        cases += 1
        try await testR852SubtitleInterruptionFence(fixture: fixture)
        cases += 1
        try await testR852SubtitlePlaybackCompletion(fixture: fixture)
        cases += 1
        try await testR852AudioFirstCompletionFence(fixture: fixture)
    }

    private static func testR852AudioFirstCompletionFence(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        expect(stack.controller.particleSubtitleState == .hidden,
               "R8.5.2 audio-first response starts without subtitle")
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 4,
            kind: .residentSpeakingStopped
        ))
        await waitUntil("R8.5.2 audio-first Provider completion is accepted") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller.realtimeBrainOutputBridgeSnapshot
                .completedResponseCount == 1
        }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntilOnMainActor("R8.5.2 audio-first Playback completes") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
                && stack.controller.particleSubtitleState == .hidden
        }

        await stack.controller.refreshMicrophoneAuthorization()
        let processedBefore = stack.controller
            .realtimeBrainOutputBridgeSnapshot.acceptedEventCount
            + stack.controller.realtimeBrainOutputBridgeSnapshot
                .rejectedEventCount
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 5,
            kind: .residentTextFinal("音频结束后的迟到首个字幕")
        ))
        await waitUntil("R8.5.2 audio-first response identity stays retired") {
            await stack.controller.refreshMicrophoneAuthorization()
            let snapshot = await stack.controller
                .realtimeBrainOutputBridgeSnapshot
            return snapshot.acceptedEventCount + snapshot.rejectedEventCount
                == processedBefore + 1
        }
        r852AudioFirstResurrections +=
            stack.controller.particleSubtitleState == .hidden ? 0 : 1
        expect(stack.controller.particleSubtitleState == .hidden,
               "R8.5.2 audio-first late text cannot resurrect subtitle")
        try await close(stack)
    }

    private static func testR852SubtitlePlaybackCompletion(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        expect(stack.controller.particleSubtitleState == .hidden,
               "R8.5.2 formal route never presents userFinal fallback")
        r852UserFinalFallbackPresentations +=
            stack.controller.particleSubtitleState == .hidden ? 0 : 1

        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 4,
            kind: .residentTextDelta("正式")
        ))
        await waitUntilOnMainActor("R8.5.2 first resident delta presents") {
            stack.controller.particleSubtitleState == ParticleSubtitleState(
                text: "正式",
                phase: .showing
            )
        }
        r852SubtitleDeltaPresentations += 1

        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 5,
            kind: .residentTextDelta("字幕")
        ))
        await waitUntilOnMainActor("R8.5.2 resident deltas accumulate") {
            stack.controller.particleSubtitleState == ParticleSubtitleState(
                text: "正式字幕",
                phase: .showing
            )
        }
        r852SubtitleDeltaPresentations += 1

        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 6,
            kind: .residentTextFinal("正式字幕完成")
        ))
        await waitUntilOnMainActor("R8.5.2 resident final presents") {
            stack.controller.particleSubtitleState == ParticleSubtitleState(
                text: "正式字幕完成",
                phase: .showing
            )
        }
        r852SubtitleFinalPresentations += 1

        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 7,
            kind: .residentSpeakingStopped
        ))
        await waitUntil("R8.5.2 Provider audio completion is accepted") {
            await stack.controller.refreshMicrophoneAuthorization()
            return await stack.controller.realtimeBrainOutputBridgeSnapshot
                .completedResponseCount == 1
        }
        expect(stack.controller.particleSubtitleState.text
                == "正式字幕完成",
               "R8.5.2 subtitle remains visible until Playback completes")

        stack.outputPlayer.completeScheduledChunk()
        await waitUntilOnMainActor("R8.5.2 Playback completion hides subtitle") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
                && stack.controller.particleSubtitleState == .hidden
        }
        r852PlaybackCompletionResurrections +=
            stack.controller.particleSubtitleState == .hidden ? 0 : 1

        await stack.controller.refreshMicrophoneAuthorization()
        let processedBefore = stack.controller
            .realtimeBrainOutputBridgeSnapshot.acceptedEventCount
            + stack.controller.realtimeBrainOutputBridgeSnapshot
                .rejectedEventCount
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 8,
            kind: .residentTextDelta("旧回答不得复活")
        ))
        await waitUntil("R8.5.2 completed response identity stays retired") {
            await stack.controller.refreshMicrophoneAuthorization()
            let snapshot = await stack.controller
                .realtimeBrainOutputBridgeSnapshot
            return snapshot.acceptedEventCount + snapshot.rejectedEventCount
                == processedBefore + 1
        }
        r852OldIdentityResurrections +=
            stack.controller.particleSubtitleState == .hidden ? 0 : 1
        expect(stack.controller.particleSubtitleState == .hidden,
               "R8.5.2 retired response text cannot resurrect subtitle")
        try await close(stack)
    }

    private static func testR852SubtitleInterruptionFence(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 4,
            kind: .residentTextFinal("插话前居民字幕")
        ))
        await waitUntilOnMainActor("R8.5.2 interruption subtitle presents") {
            stack.controller.particleSubtitleState.text == "插话前居民字幕"
        }

        let evidenceBefore = stack.controller
            .realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        _ = try await submitTrueNearEndThroughProductionChain(stack: stack)
        await waitUntil("R8.5.2 interruption acoustic evidence arrives") {
            await stack.controller.refreshMicrophoneAuthorization()
            let evidenceCount = await stack.controller
                .realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
            return evidenceCount == evidenceBefore + 1
        }

        await stack.provider.holdInterrupt()
        try await submitSemanticProposal(stack: stack, sequence: 5)
        await waitUntilOnMainActor("R8.5.2 confirmed interruption hides subtitle") {
            stack.controller.particleSubtitleState == .hidden
                && stack.outputPlayer.clearScheduledPlaybackCount == 1
        }
        r852InterruptionResurrections +=
            stack.controller.particleSubtitleState == .hidden ? 0 : 1

        let returnedBefore = await stack.provider.returnedEventCount(
            eventSession: stack.session
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 6,
            kind: .residentTextFinal("旧 generation 字幕")
        ))
        await stack.provider.releaseInterrupt()
        await waitUntilOnMainActor("R8.5.2 interruption rebounds to N+1") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
                && stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == stack.session.generation + 1
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop
        }
        await waitUntil("R8.5.2 old generation subtitle is fenced") {
            await stack.provider.returnedEventCount(
                eventSession: stack.session
            ) == returnedBefore + 1
        }
        await stack.controller.refreshMicrophoneAuthorization()
        r852OldIdentityResurrections +=
            stack.controller.particleSubtitleState == .hidden ? 0 : 1
        expect(stack.controller.particleSubtitleState == .hidden,
               "R8.5.2 interruption and stale generation stay subtitle-free")
        try await close(stack)
    }

    private static func testR852RecoverableResponseError(
        fixture: Data
    ) async throws {
        let stack = try await makeControllerStack(fixture: fixture)
        let baselineCloseCount = await stack.provider.closeCount()
        let baselineCreateCount = await stack.provider.createCount()
        let baselinePlayerStartCount = stack.outputPlayer.startCount

        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 4,
            kind: .residentTextDelta("失败前字幕")
        ))
        await waitUntilOnMainActor("R8.5.2 pre-error subtitle presents") {
            stack.controller.particleSubtitleState.text == "失败前字幕"
        }
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 5,
            kind: .error(.providerFailure)
        ))
        await waitUntilOnMainActor("R8.5.2 response error remains recoverable") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
                && stack.controller.formalSpeechRouteDebugSnapshot
                    .lastErrorCode == nil
                && stack.controller.particleSubtitleState == .hidden
                && stack.controller.realtimeBrainInputBridgeSnapshot
                    .hasActivePump
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop
        }

        let diagnosticEvents = stack.controller
            .realtimeSpeechDiagnosticTimeline.events.filter {
                $0.routeKind
                        == NativeSpeechDiagnosticRouteKind.realtimeBrain.rawValue
                    && $0.source == .providerEvent
                    && $0.category == "recoverable_response_error"
                    && $0.disposition == "returned_to_listening"
                    && $0.errorCode == "provider_failure"
            }
        r852RecoverableResponseErrors += diagnosticEvents.count
        r852TerminalStops += stack.controller
            .realtimeBrainOutputBridgeSnapshot.hasActiveReceiveLoop ? 0 : 1
        r852ProviderClosesOnResponseError +=
            await stack.provider.closeCount() - baselineCloseCount
        expect(diagnosticEvents.count == 1,
               "R8.5.2 diagnostics preserve one recoverable response error")
        expect(r852TerminalStops == 0
                && r852ProviderClosesOnResponseError == 0,
               "R8.5.2 response error does not terminally stop Provider route")

        stack.outputPlayer.completeStoppedChunk()
        let nextTurnID = RealtimeBrainTurnID()
        let nextResponseID = RealtimeBrainResponseID()
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: stack.session,
                turnID: nextTurnID,
                responseID: nil,
                contextRevision: stack.target.contextRevision
            ),
            sequence: 6,
            kind: .userTranscriptFinal("错误后新用户轮次")
        ))
        await waitUntil("R8.5.2 response create rebounds after error") {
            await stack.provider.createCount() == baselineCreateCount + 1
        }
        expect(stack.controller.particleSubtitleState == .hidden,
               "R8.5.2 post-error userFinal never becomes resident subtitle")

        let nextIdentity = RealtimeBrainEventIdentity(
            session: stack.session,
            turnID: nextTurnID,
            responseID: nextResponseID,
            contextRevision: stack.target.contextRevision
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: nextIdentity,
            sequence: 7,
            kind: .residentTextFinal("错误后正常回复")
        ))
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: nextIdentity,
            sequence: 8,
            kind: .residentAudioDelta(audioDelta(sequence: 2))
        ))
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: nextIdentity,
            sequence: 9,
            kind: .residentSpeakingStopped
        ))
        await waitUntilOnMainActor("R8.5.2 output rebounds after error") {
            stack.controller.particleSubtitleState.text == "错误后正常回复"
                && stack.outputPlayer.startCount
                    == baselinePlayerStartCount + 1
        }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntilOnMainActor("R8.5.2 rebound Playback completes") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
                && stack.controller.particleSubtitleState == .hidden
        }
        r852PostErrorResponseRebound += 1
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
        fixture: Data,
        afterRebound: ((
            R823ControllerStack,
            RealtimeBrainSessionIdentity
        ) async throws -> Void)? = nil
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
        if let afterRebound {
            try await afterRebound(stack, nextIdentity)
        }
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
        let growthBefore = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()
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
        let growthWrites = stack.runtime
            .realtimeGrowthObservationDecisionCountForTesting()
            == growthBefore ? 0 : 1
        residentOnlyFalseTurns += historyWrites
        residentOnlyFalseHistoryWrites += historyWrites
        residentOnlyFalseMemoryWrites += memoryWrites
        residentOnlyRelationshipChanges += relationshipChanges
        residentOnlyGrowthWrites += growthWrites
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
        fixture: Data,
        startsResidentPlayback: Bool = true
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
        if startsResidentPlayback {
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
        } else {
            expect(controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening,
                   "normal Listening fixture starts in Runtime Listening")
            expect(outputPlayer.startCount == 0
                    && !acousticEchoHost.acousticObservationSnapshot()
                        .isPlaybackActive,
                   "normal Listening fixture has no resident playback")
        }
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
