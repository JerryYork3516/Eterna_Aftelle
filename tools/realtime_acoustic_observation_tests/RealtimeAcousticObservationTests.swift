import Foundation

#if DEBUG
private struct R821CredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? { nil }
}

private struct R821AuthorizationProvider:
    MicrophoneAuthorizationProviding {
    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }
}

private final class R821DeviceMonitor:
    MacSpeechDeviceRouteMonitoring,
    @unchecked Sendable {
    private let route = MacSpeechDeviceRoute(
        input: MacSpeechAudioDevice(
            identifier: "r821-input",
            name: "R8.2.1 Input",
            isAvailable: true
        ),
        output: MacSpeechAudioDevice(
            identifier: "r821-output",
            name: "R8.2.1 Output",
            isAvailable: true
        )
    )

    func currentRoute() -> MacSpeechDeviceRoute { route }
    func start(onChange: @escaping @Sendable () -> Void) {}
    func stop() {}
}

private final class R821AECBackend:
    MacSpeechAECBackend,
    @unchecked Sendable {
    func configure() throws {}
    func processRender(_ samples: [Float]) throws {}

    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult {
        let processed = samples.map { $0 * 0.05 }
        var linear: [Float] = []
        linear.reserveCapacity(processed.count / 3)
        for index in stride(from: 0, to: processed.count, by: 3) {
            let sum = processed[index]
                + processed[index + 1]
                + processed[index + 2]
            linear.append(sum / 3)
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
}

private final class R821AudioCapture:
    MacSpeechAudioCapturing,
    @unchecked Sendable {
    let acousticHost: MacSpeechAcousticEchoHost

    init(acousticHost: MacSpeechAcousticEchoHost) {
        self.acousticHost = acousticHost
    }

    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        MacSpeechNativeInputFormat(sampleRate: 48_000, channelCount: 1)
    }

    func stop() {}

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot? {
        acousticHost.acousticObservationSnapshot()
    }
}

private actor R821RealtimeProvider: RealtimeResidentBrainProvider {
    private var events: [RealtimeResidentBrainEvent] = []
    private var receiveContinuation:
        CheckedContinuation<RealtimeResidentBrainEvent, Error>?
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var contextUpdates: [RealtimeBrainRuntimeContextUpdate] = []
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

    func openCount() -> Int { openCommands.count }
    func createCount() -> Int { createCommands.count }
    func cancelCount() -> Int { cancelCommands.count }
    func interruptCount() -> Int { interruptCommands.count }
    func closeCount() -> Int { closeCommands.count }

    private func deliver(_ event: RealtimeResidentBrainEvent) {
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: event)
        } else {
            events.append(event)
        }
    }
}

private final class R821AudioSource:
    MacSpeechAudioFrameSourcing,
    @unchecked Sendable {
    private let lock = NSLock()
    private var activeGeneration: UInt64?
    private var frames: [MacSpeechAudioFrame] = []
    private var snapshot: MacSpeechResidentAcousticSnapshot?
    private var frameSequence: UInt64 = 0
    private var lastFrameTimestamp: UInt64 = 0

    func activeCaptureGeneration() async -> UInt64? {
        lock.withLock { activeGeneration }
    }

    func isCaptureGenerationActive(_ generation: UInt64) async -> Bool {
        lock.withLock { activeGeneration == generation }
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
        lock.withLock { activeGeneration = generation }
    }

    func stop() {
        lock.withLock {
            activeGeneration = nil
            frames.removeAll(keepingCapacity: true)
        }
    }

    func setSnapshot(_ snapshot: MacSpeechResidentAcousticSnapshot?) {
        lock.withLock { self.snapshot = snapshot }
    }

    func appendFrame(generation: UInt64) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            frameSequence &+= 1
            let now = DispatchTime.now().uptimeNanoseconds
            let timestamp = max(now, lastFrameTimestamp &+ 20_000_000)
            lastFrameTimestamp = timestamp
            frames.append(MacSpeechAudioFrame(
                captureGeneration: generation,
                sequenceNumber: frameSequence,
                monotonicTimestampNanoseconds: timestamp,
                pcm16Bytes: Data(repeating: 0, count: 960),
                activity: 0
            ))
        }
    }
}

private actor R821SendRecorder {
    private var frames: [RealtimeBrainAudioFrame] = []

    func record(_ frame: RealtimeBrainAudioFrame) {
        frames.append(frame)
    }

    func count() -> Int { frames.count }
}

private actor R821ObservationRecorder {
    private var observations: [RealtimeAcousticObservation] = []
    private var completedObservationCount = 0
    private var isHeld = false
    private var holdContinuation: CheckedContinuation<Void, Never>?

    func setHeld(_ held: Bool) {
        isHeld = held
    }

    func observe(
        _ observation: RealtimeAcousticObservation
    ) async -> RealtimeAcousticObservationDisposition {
        observations.append(observation)
        if isHeld {
            await withCheckedContinuation { continuation in
                precondition(holdContinuation == nil)
                holdContinuation = continuation
            }
        }
        completedObservationCount += 1
        return .observed
    }

    func release() {
        isHeld = false
        let continuation = holdContinuation
        holdContinuation = nil
        continuation?.resume()
    }

    func values() -> [RealtimeAcousticObservation] { observations }
    func completionCount() -> Int { completedObservationCount }
}

private struct R821Stack {
    let runtime: RuntimeCore
    let provider: R821RealtimeProvider
    let session: RealtimeBrainSessionIdentity
}

@MainActor
@main
private struct RealtimeAcousticObservationTests {
    private static var cases = 0
    private static var checks = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        testFarEndDominantClassification()
        testResidualEchoClassification()
        testSilenceClassification()
        testNearEndCandidateClassification()
        testIsolatedNearEndCandidateClassification()
        testIndeterminateClassification()
        await testActualHostAcousticFacts()
        testFallbackHostAcousticFacts()
        try await testRuntimeObservationTrace(fixture: fixture)
        try await testIdentityFences(fixture: fixture)
        try await testActualOldIdentityReplay(fixture: fixture)
        try await testSemanticIsolation(fixture: fixture)
        try await testResidentOnlyStressAndBound(fixture: fixture)
        try await testStopCleanup(fixture: fixture)
        await testBridgeDeliveryDoesNotBlockAudio()
        await testFallbackObservationWithoutAudioFrame()

        print("realtime_acoustic_observation_cases=\(cases)")
        print("realtime_acoustic_observation_checks=\(checks)")
    }

    private static func testFarEndDominantClassification() {
        cases += 1
        let timestamp = monotonicNow()
        let normal = metrics(
            timestamp: timestamp,
            renderRMS: 0.20,
            rawRMS: 0.16,
            outputRMS: 0.003,
            rawCorrelation: 0.82,
            erle: 12,
            source: .echoOnly
        )
        expect(classify(normal, timestamp: timestamp) == .farEndDominant,
               "clean AEC playback is far-end dominant")

        let quietLevel = metrics(
            timestamp: timestamp,
            renderRMS: 0.04,
            rawRMS: 0.035,
            outputRMS: 0.002,
            rawCorrelation: 0.76,
            erle: 8,
            source: .echoOnly
        )
        let loudLevel = metrics(
            timestamp: timestamp,
            renderRMS: 0.36,
            rawRMS: 0.31,
            outputRMS: 0.004,
            rawCorrelation: 0.88,
            erle: 15,
            source: .echoOnly
        )
        expect(classify(quietLevel, timestamp: timestamp) == .farEndDominant,
               "lower far-end level stays far-end dominant")
        expect(classify(loudLevel, timestamp: timestamp) == .farEndDominant,
               "higher far-end level stays far-end dominant")

        let mildDelayChange = metrics(
            timestamp: timestamp,
            renderRMS: 0.20,
            rawRMS: 0.16,
            outputRMS: 0.003,
            rawCorrelation: 0.82,
            erle: 12,
            source: .echoOnly,
            measuredDelayMilliseconds: 86,
            alignedDelayMilliseconds: 80
        )
        expect(
            classify(mildDelayChange, timestamp: timestamp)
                == .farEndDominant,
            "small delay variation remains inside the aligned window"
        )
    }

    private static func testResidualEchoClassification() {
        cases += 1
        let timestamp = monotonicNow()
        let value = metrics(
            timestamp: timestamp,
            renderRMS: 0.22,
            rawRMS: 0.18,
            outputRMS: 0.038,
            rawCorrelation: 0.81,
            residualCorrelation: 0.78,
            erle: 1,
            source: .echoOnly
        )
        expect(classify(value, timestamp: timestamp) == .residualEchoLikely,
               "correlated post-AEC energy is residual echo likely")
        expect(value.residentPlaybackActive && value.aecActive,
               "residual fixture has resident playback and active AEC")
    }

    private static func testSilenceClassification() {
        cases += 1
        let timestamp = monotonicNow()
        let value = metrics(
            timestamp: timestamp,
            playbackActive: false,
            renderRMS: 0,
            rawRMS: 0.002,
            outputRMS: 0.001,
            rawCorrelation: 0,
            erle: 0,
            source: .uncertain
        )
        expect(classify(value, timestamp: timestamp) == .silenceOrNoise,
               "inactive playback and low background is silence or noise")
    }

    private static func testNearEndCandidateClassification() {
        cases += 1
        let timestamp = monotonicNow()
        let value = metrics(
            timestamp: timestamp,
            renderRMS: 0.18,
            rawRMS: 0.27,
            outputRMS: 0.21,
            rawCorrelation: 0.12,
            erle: 0,
            source: .nearEndSpeech
        )
        expect(classify(value, timestamp: timestamp) == .nearEndCandidate,
               "unexplained near-end energy is only a candidate")
    }

    private static func testIsolatedNearEndCandidateClassification() {
        cases += 1
        let timestamp = monotonicNow()
        let value = metrics(
            timestamp: timestamp,
            renderRMS: 0.18,
            rawRMS: 0.27,
            outputRMS: 0.21,
            rawCorrelation: 0.33,
            erle: 0,
            source: .nearEndSpeech,
            renderCaptureIsolationEstablished: true,
            sourceAlignmentLocked: false
        )
        expect(classify(value, timestamp: timestamp) == .nearEndCandidate,
               "explicit render isolation replaces unavailable timing lock")

        let unproven = metrics(
            timestamp: timestamp,
            renderRMS: 0.18,
            rawRMS: 0.27,
            outputRMS: 0.21,
            rawCorrelation: 0.33,
            erle: 0,
            source: .nearEndSpeech,
            sourceAlignmentLocked: false
        )
        expect(classify(unproven, timestamp: timestamp) == .indeterminate,
               "missing alignment and isolation still fail closed")
    }

    private static func testIndeterminateClassification() {
        cases += 1
        let timestamp = monotonicNow()
        let misaligned = metrics(
            timestamp: timestamp,
            renderRMS: 0.20,
            rawRMS: 0.17,
            outputRMS: 0.004,
            rawCorrelation: 0.83,
            erle: 10,
            source: .echoOnly,
            measuredDelayMilliseconds: 650,
            alignedDelayMilliseconds: 650
        )
        expect(classify(misaligned, timestamp: timestamp) == .indeterminate,
               "render and capture outside the timing window is indeterminate")

        let missingReference = metrics(
            timestamp: timestamp,
            renderRMS: nil,
            rawRMS: 0.12,
            outputRMS: 0.03,
            rawCorrelation: 0,
            erle: 0,
            source: .uncertain,
            renderReferenceAvailable: false,
            renderTimestampAvailable: false
        )
        expect(
            classify(missingReference, timestamp: timestamp) == .indeterminate,
            "missing render diagnostics is explicitly indeterminate"
        )

        let fallback = metrics(
            timestamp: timestamp,
            renderRMS: 0.2,
            rawRMS: 0.12,
            outputRMS: 0,
            rawCorrelation: 0,
            erle: 0,
            source: .uncertain,
            aecActive: false
        )
        expect(classify(fallback, timestamp: timestamp) == .indeterminate,
               "AEC fallback during playback is indeterminate")

        let unstableRoute = metrics(
            timestamp: timestamp,
            renderRMS: 0.2,
            rawRMS: 0.16,
            outputRMS: 0.003,
            rawCorrelation: 0.82,
            erle: 12,
            source: .echoOnly,
            routeStable: false
        )
        expect(
            classify(unstableRoute, timestamp: timestamp) == .indeterminate,
            "route rebuild facts fail closed as indeterminate"
        )

        let unavailableOutput = metrics(
            timestamp: timestamp,
            renderRMS: 0.2,
            rawRMS: 0.16,
            outputRMS: 0.003,
            rawCorrelation: 0.82,
            erle: 12,
            source: .echoOnly,
            outputDeviceAvailable: false
        )
        expect(
            classify(unavailableOutput, timestamp: timestamp)
                == .indeterminate,
            "unavailable output route fails closed as indeterminate"
        )
    }

    private static func testActualHostAcousticFacts() async {
        cases += 1
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: R821AECBackend()
        )
        expect(host.configure() == .webRTCAEC3,
               "actual Host fact fixture configures the production AEC path")
        host.playbackStarted()
        let render = signal(seed: 7, amplitude: 0.25)
        let base: UInt64 = 2_000_000_000
        for index in 0 ..< 3 {
            let offset = UInt64(index) * 10_000_000
            host.processRender(
                render,
                hostTimeNanoseconds: base + offset
            )
            _ = host.processCapture(
                render,
                hostTimeNanoseconds: base + 80_000_000 + offset
            )
        }
        let snapshot = host.acousticObservationSnapshot()
        expect(snapshot.captureFrameIndex == 3,
               "observation snapshot follows production 10 ms capture frames")
        expect(snapshot.captureHostTimeNanoseconds
                == base + 100_000_000,
               "snapshot retains the actual capture host timestamp")
        expect(snapshot.renderReferenceAvailable,
               "snapshot sees the actual player render reference")
        expect(snapshot.renderHostTimeNanoseconds == base + 20_000_000,
               "snapshot retains the matched render host timestamp")
        expect((snapshot.renderReferenceRMS ?? 0) > 0.1,
               "snapshot reuses actual render RMS")
        expect(snapshot.sourceAlignmentLocked
                && snapshot.sourceAlignmentDelayMilliseconds == 80,
               "snapshot retains the production timing alignment")

        let audioHost = MacSpeechAudioHost(
            authorizationProvider: R821AuthorizationProvider(),
            capture: R821AudioCapture(acousticHost: host),
            deviceMonitor: R821DeviceMonitor()
        )
        guard let captureGeneration = await audioHost
                .prepareCaptureGeneration() else {
            fatalError("Audio Host capture generation was not prepared")
        }
        let started = await audioHost.startPreparedCapture(
            generation: captureGeneration
        )
        expect(started.state == .capturing,
               "Audio Host starts the identity-bound capture generation")
        guard let residentSnapshot = await audioHost
                .residentAcousticSnapshot() else {
            fatalError("Audio Host resident acoustic snapshot missing")
        }
        expect(residentSnapshot.captureGeneration == captureGeneration,
               "Audio Host binds facts to the exact capture generation")
        expect(residentSnapshot.captureFrameIndex == snapshot.captureFrameIndex,
               "Audio Host preserves the AEC capture frame index")
        expect(residentSnapshot.captureHostTimeNanoseconds
                == snapshot.captureHostTimeNanoseconds,
               "Audio Host preserves the actual capture timestamp")
        expect(residentSnapshot.renderHostTimeNanoseconds
                == snapshot.renderHostTimeNanoseconds,
               "Audio Host preserves the actual render timestamp")
        expect(residentSnapshot.routeStable
                && residentSnapshot.inputDeviceAvailable
                && residentSnapshot.outputDeviceAvailable,
               "Audio Host attaches live route and device facts")
        _ = await audioHost.stopCapture()
    }

    private static func testFallbackHostAcousticFacts() {
        cases += 1
        let host = MacSpeechAcousticEchoHost(mode: .halfDuplexFallback)
        expect(host.configure() == .halfDuplexFallback,
               "fallback Host fixture stays in half-duplex mode")
        host.playbackStarted()
        let timestamp = monotonicNow()
        let output = host.processCapture(
            signal(seed: 11, amplitude: 0.1),
            hostTimeNanoseconds: timestamp
        )
        let snapshot = host.acousticObservationSnapshot()
        expect(output.isEmpty,
               "fallback playback still suppresses outgoing capture PCM")
        expect(snapshot.captureFrameIndex == 1,
               "fallback still advances the lightweight observation frame")
        expect(snapshot.captureHostTimeNanoseconds == timestamp,
               "fallback retains the actual capture timestamp")
        expect(snapshot.rawCaptureRMS > 0,
               "fallback retains the low-cost raw capture energy")
        expect(snapshot.inputClassification == .uncertain,
               "fallback facts remain explicitly uncertain")
        expect(!snapshot.aecActive,
               "fallback does not invent an active AEC diagnostic")
    }

    private static func testRuntimeObservationTrace(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeStack(fixture: fixture)
        let classes: [RealtimeAcousticClassification] = [
            .farEndDominant,
            .residualEchoLikely,
            .silenceOrNoise,
            .nearEndCandidate,
            .indeterminate
        ]
        for (index, classification) in classes.enumerated() {
            let sequence = UInt64(index + 1)
            let timestamp = monotonicNow()
            let observation = observation(
                session: stack.session,
                sequence: sequence,
                timestamp: timestamp,
                classification: classification
            )
            expect(
                stack.runtime.observeRealtimeResidentBrainAcoustics(
                    observation
                ) == .observed,
                "each production classification is observed"
            )
        }
        let snapshot = stack.runtime
            .realtimeAcousticObservationDebugSnapshot()
        expect(snapshot.capacity == 32,
               "Runtime observation trace has fixed capacity 32")
        expect(snapshot.records.map(\.observation.classification) == classes,
               "trace preserves all five classifications in order")
        expect(snapshot.activeSession == stack.session,
               "trace ledger retains the exact active identity")
        expect(snapshot.lastSequence == 5,
               "trace ledger retains the latest independent sequence")
        _ = await stack.runtime.closeRealtimeResidentBrainSession(
            identity: stack.session
        )
    }

    private static func testIdentityFences(fixture: Data) async throws {
        cases += 1
        let stack = try await makeStack(fixture: fixture)
        for wrongSession in wrongSessions(for: stack.session) {
            let timestamp = monotonicNow()
            expect(
                stack.runtime.observeRealtimeResidentBrainAcoustics(
                    observation(
                        session: wrongSession,
                        sequence: 1,
                        timestamp: timestamp,
                        classification: .farEndDominant
                    )
                ) == .ignored(.staleIdentity),
                "wrong session, lease, epoch, or generation is stale"
            )
        }

        let timestamp = monotonicNow()
        let valid = observation(
            session: stack.session,
            sequence: 1,
            timestamp: timestamp,
            classification: .farEndDominant
        )
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(valid)
                == .observed,
            "valid observation establishes the independent ledger"
        )
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(valid)
                == .ignored(.duplicateObservation),
            "duplicate observation is rejected"
        )
        let outOfOrder = observation(
            session: stack.session,
            sequence: 0,
            timestamp: timestamp,
            classification: .farEndDominant
        )
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(outOfOrder)
                == .ignored(.invalidObservation),
            "zero sequence is invalid"
        )
        let expiredTimestamp = timestamp > 1_000_000_000
            ? timestamp - 1_000_000_000 : 1
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(
                observation(
                    session: stack.session,
                    sequence: 2,
                    timestamp: expiredTimestamp,
                    classification: .farEndDominant
                )
            ) == .ignored(.invalidObservation),
            "expired acoustic sample is rejected"
        )
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(
                observation(
                    session: stack.session,
                    sequence: 2,
                    timestamp: monotonicNow() + 1_000_000_000,
                    classification: .farEndDominant
                )
            ) == .ignored(.invalidObservation),
            "future acoustic sample is rejected"
        )
        _ = await stack.runtime.closeRealtimeResidentBrainSession(
            identity: stack.session
        )
    }

    private static func testActualOldIdentityReplay(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeStack(fixture: fixture)
        let oldGeneration = stack.session
        guard case .success(let nextGeneration) =
                await stack.runtime
                    .cancelRealtimeResidentBrainGenerationForTesting(
                        identity: oldGeneration,
                        reason: .runtimeDecision
                    ) else {
            fatalError("generation transition failed")
        }
        expect(nextGeneration.generation == oldGeneration.generation + 1,
               "generation transition produces a real next identity")
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(
                observation(
                    session: oldGeneration,
                    sequence: 1,
                    timestamp: monotonicNow(),
                    classification: .farEndDominant
                )
            ) == .ignored(.staleIdentity),
            "the actual old generation is rejected"
        )
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(
                observation(
                    session: nextGeneration,
                    sequence: 1,
                    timestamp: monotonicNow(),
                    classification: .farEndDominant
                )
            ) == .observed,
            "the committed next generation is accepted"
        )

        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: nextGeneration
            ),
            "next generation closes"
        )
        guard case .success(let reopened) =
                await stack.runtime.startRealtimeResidentBrainSession() else {
            fatalError("Realtime session did not reopen")
        }
        guard case .accepted(let ready) = try await stack.runtime
                .receiveRealtimeResidentBrainEvent(session: reopened),
              ready.kind == .sessionReady else {
            fatalError("reopened session did not become ready")
        }
        expect(reopened.brainLeaseID != nextGeneration.brainLeaseID,
               "reopen creates a real new lease")
        expect(reopened.routeEpoch > nextGeneration.routeEpoch,
               "reopen creates a real new route epoch")
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(
                observation(
                    session: nextGeneration,
                    sequence: 2,
                    timestamp: monotonicNow(),
                    classification: .farEndDominant
                )
            ) == .ignored(.staleIdentity),
            "the actual old lease and route are rejected after reopen"
        )
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(
                observation(
                    session: reopened,
                    sequence: 1,
                    timestamp: monotonicNow(),
                    classification: .farEndDominant
                )
            ) == .observed,
            "the reopened identity accepts a fresh observation"
        )
        _ = await stack.runtime.closeRealtimeResidentBrainSession(
            identity: reopened
        )
    }

    private static func testSemanticIsolation(fixture: Data) async throws {
        cases += 1
        let stack = try await makeStack(fixture: fixture)
        let target = try await activateResidentResponse(stack)
        let proposal = RealtimeResidentBrainEvent(
            identity: target,
            sequence: 4,
            kind: .interruptionProposed(RealtimeBrainInterruptionProposal(
                identity: target,
                reason: "user_speech_started_during_resident_response"
            ))
        )
        await stack.provider.enqueue(proposal)
        guard case .accepted = try await stack.runtime
                .receiveRealtimeResidentBrainEvent(session: stack.session) else {
            fatalError("semantic proposal was not accepted")
        }
        let decision = await stack.runtime
            .claimRealtimeResidentBrainInterruptionDecision(for: proposal)
        if case .success(.observed) = decision {
            expect(true, "semantic-only proposal remains observed")
        } else {
            expect(false, "semantic-only proposal remains observed")
        }

        for (index, classification) in [
            RealtimeAcousticClassification.silenceOrNoise,
            .farEndDominant,
            .residualEchoLikely,
            .nearEndCandidate,
            .indeterminate
        ].enumerated() {
            expect(
                stack.runtime.observeRealtimeResidentBrainAcoustics(
                    observation(
                        session: stack.session,
                        sequence: UInt64(index + 1),
                        timestamp: monotonicNow(),
                        classification: classification
                    )
                ) == .observed,
                "classification remains observer-only beside semantic evidence"
            )
        }
        let interruptCount = await stack.provider.interruptCount()
        let cancelCount = await stack.provider.cancelCount()
        expect(interruptCount == 0,
               "classification never invokes Provider interrupt")
        expect(cancelCount == 0,
               "classification never invokes Provider cancel")
        expect(stack.runtime.activeBrainLeaseForTesting()?.generation
                == .realtimeResidentBrain(stack.session.generation),
               "classification never advances generation")
        _ = await stack.runtime.closeRealtimeResidentBrainSession(
            identity: stack.session
        )
    }

    private static func testResidentOnlyStressAndBound(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeStack(fixture: fixture)
        let originalLease = stack.runtime.activeBrainLeaseForTesting()
        for index in 1 ... 320 {
            let classification: RealtimeAcousticClassification =
                index.isMultiple(of: 2)
                ? .farEndDominant : .residualEchoLikely
            expect(
                stack.runtime.observeRealtimeResidentBrainAcoustics(
                    observation(
                        session: stack.session,
                        sequence: UInt64(index),
                        timestamp: monotonicNow(),
                        classification: classification
                    )
                ) == .observed,
                "resident-only stress observation is accepted"
            )
        }
        let snapshot = stack.runtime
            .realtimeAcousticObservationDebugSnapshot()
        expect(snapshot.records.count == 32,
               "rolling observation trace never exceeds capacity")
        expect(snapshot.droppedRecordCount == 288,
               "overflow drops the oldest bounded trace records")
        expect(
            snapshot.records.map(\.observation.identity.sequence)
                == Array(289 ... 320).map(UInt64.init),
            "rolling trace retains only the newest observation sequences"
        )
        let interruptCount = await stack.provider.interruptCount()
        let cancelCount = await stack.provider.cancelCount()
        expect(interruptCount == 0,
               "resident-only stress produces zero Provider interrupts")
        expect(cancelCount == 0,
               "resident-only stress produces zero Provider cancels")
        expect(stack.runtime.activeBrainLeaseForTesting() == originalLease,
               "resident-only stress preserves the ActiveBrainLease")
        expect(stack.runtime.activeBrainLeaseForTesting()?.generation
                == .realtimeResidentBrain(stack.session.generation),
               "resident-only stress preserves generation")
        _ = await stack.runtime.closeRealtimeResidentBrainSession(
            identity: stack.session
        )
    }

    private static func testStopCleanup(fixture: Data) async throws {
        cases += 1
        let stack = try await makeStack(fixture: fixture)
        for sequence in 1 ... 3 {
            expect(
                stack.runtime.observeRealtimeResidentBrainAcoustics(
                    observation(
                        session: stack.session,
                        sequence: UInt64(sequence),
                        timestamp: monotonicNow(),
                        classification: .farEndDominant
                    )
                ) == .observed,
                "pre-Stop observation is accepted"
            )
        }
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: stack.session
            ),
            "Stop closes the active Realtime session"
        )
        let cleared = stack.runtime
            .realtimeAcousticObservationDebugSnapshot()
        expect(cleared.records.isEmpty && cleared.droppedRecordCount == 0,
               "Stop clears the bounded observation trace")
        expect(cleared.activeSession == nil && cleared.lastSequence == 0,
               "Stop clears the observation ledger")
        expect(
            stack.runtime.observeRealtimeResidentBrainAcoustics(
                observation(
                    session: stack.session,
                    sequence: 4,
                    timestamp: monotonicNow(),
                    classification: .farEndDominant
                )
            ) == .ignored(.staleIdentity),
            "late post-Stop observation is rejected"
        )
        let afterLate = stack.runtime
            .realtimeAcousticObservationDebugSnapshot()
        expect(afterLate.records.isEmpty,
               "late post-Stop callback cannot refill the trace")
    }

    private static func testBridgeDeliveryDoesNotBlockAudio() async {
        cases += 1
        let source = R821AudioSource()
        let sender = R821SendRecorder()
        let recorder = R821ObservationRecorder()
        let session = testSession()
        let captureGeneration: UInt64 = 41
        source.activate(generation: captureGeneration)
        await recorder.setHeld(true)
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                await sender.record(frame)
                return .success(())
            },
            stopInput: { _ in .success(()) },
            observeResidentAcoustics: { observation in
                await recorder.observe(observation)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        source.setSnapshot(residentSnapshot(
            captureGeneration: captureGeneration,
            frameIndex: 1,
            classification: .silenceOrNoise
        ))
        source.appendFrame(generation: captureGeneration)
        await waitUntil("first observation enters slow observer") {
            await recorder.values().count == 1
        }
        await waitUntil("first audio frame sends") {
            await sender.count() == 1
        }
        let held = await bridge.currentSnapshot()
        expect(held.hasPendingResidentAcousticObservation,
               "slow observer is represented by one pending delivery")
        let sentWhileHeld = await sender.count()
        expect(sentWhileHeld == 1,
               "slow observer does not block Provider audio send")

        source.setSnapshot(residentSnapshot(
            captureGeneration: captureGeneration,
            frameIndex: 2,
            classification: .nearEndCandidate
        ))
        source.appendFrame(generation: captureGeneration)
        await waitUntil("second audio frame sends") {
            await sender.count() == 2
        }
        let beforeCadence = await bridge.currentSnapshot()
        let observedBeforeCadence = await recorder.values().count
        expect(observedBeforeCadence == 1,
               "classification change does not bypass the 10-frame cadence")
        expect(beforeCadence.droppedResidentAcousticObservationCount == 0,
               "sub-cadence classification change schedules no delivery")

        source.setSnapshot(residentSnapshot(
            captureGeneration: captureGeneration,
            frameIndex: 10,
            classification: .nearEndCandidate
        ))
        source.appendFrame(generation: captureGeneration)
        await waitUntil("third audio frame sends") {
            await sender.count() == 3
        }
        let observedAtFrameTen = await recorder.values().count
        let droppedAtFrameTen = await bridge.currentSnapshot()
            .droppedResidentAcousticObservationCount
        expect(observedAtFrameTen == 1,
               "frame ten remains below the first plus ten cadence boundary")
        expect(droppedAtFrameTen == 0,
               "frame ten does not schedule or drop an early observation")

        source.setSnapshot(residentSnapshot(
            captureGeneration: captureGeneration,
            frameIndex: 11,
            classification: .nearEndCandidate
        ))
        source.appendFrame(generation: captureGeneration)
        await waitUntil("fourth audio frame sends") {
            await sender.count() == 4
        }
        await waitUntil("bounded pending observation drop") {
            await bridge.currentSnapshot()
                .droppedResidentAcousticObservationCount == 1
        }
        let observedWhileHeld = await recorder.values().count
        expect(observedWhileHeld == 1,
               "single-flight delivery does not queue a second observer task")
        await recorder.release()
        await waitUntil("pending observation completion") {
            !(await bridge.currentSnapshot()
                .hasPendingResidentAcousticObservation)
        }
        let completed = await bridge.currentSnapshot()
        expect(completed.residentAcousticObservationCount == 1,
               "completed observation is counted once")
        expect(completed.droppedResidentAcousticObservationCount == 1,
               "overflow drops one scheduled observation")

        await recorder.setHeld(true)
        source.setSnapshot(residentSnapshot(
            captureGeneration: captureGeneration,
            frameIndex: 21,
            classification: .farEndDominant,
            playbackActive: true
        ))
        source.appendFrame(generation: captureGeneration)
        await waitUntil("second slow observation enters") {
            await recorder.values().count == 2
        }
        await waitUntil("fifth audio frame sends") {
            await sender.count() == 5
        }
        let pendingAtStop = await bridge.currentSnapshot()
            .hasPendingResidentAcousticObservation
        expect(pendingAtStop,
               "a second slow observation is pending at Stop")
        _ = await bridge.stop()
        let stopped = await bridge.currentSnapshot()
        expect(!stopped.hasPendingResidentAcousticObservation,
               "Stop cancels pending observation delivery")
        await recorder.release()
        await waitUntil("late stopped observation settles") {
            await recorder.completionCount() == 2
        }
        let afterLateCompletion = await bridge.currentSnapshot()
        expect(afterLateCompletion.residentAcousticObservationCount == 1,
               "late stopped observation cannot increment accepted count")
        expect(
            afterLateCompletion.rejectedResidentAcousticObservationCount == 0,
            "late stopped observation cannot increment rejected count"
        )
        source.stop()
    }

    private static func testFallbackObservationWithoutAudioFrame() async {
        cases += 1
        let source = R821AudioSource()
        let sender = R821SendRecorder()
        let recorder = R821ObservationRecorder()
        let session = testSession()
        let captureGeneration: UInt64 = 51
        source.activate(generation: captureGeneration)
        source.setSnapshot(residentSnapshot(
            captureGeneration: captureGeneration,
            frameIndex: 10,
            classification: .indeterminate,
            playbackActive: true,
            aecActive: false,
            renderReferenceAvailable: false
        ))
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                await sender.record(frame)
                return .success(())
            },
            stopInput: { _ in .success(()) },
            observeResidentAcoustics: { observation in
                await recorder.observe(observation)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        await waitUntil("fallback observation arrives without audio") {
            await recorder.values().count == 1
        }
        let values = await recorder.values()
        expect(values.first?.classification == .indeterminate,
               "fallback emits explicit indeterminate observation")
        let sentCount = await sender.count()
        expect(sentCount == 0,
               "fallback observation does not require a PCM send frame")
        _ = await bridge.stop()
        source.stop()
    }

    private static func makeStack(fixture: Data) async throws -> R821Stack {
        let provider = R821RealtimeProvider()
        let router = ProviderRouter(
            credentialReader: R821CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "R8.2.1 fixture resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("Realtime session did not start")
        }
        guard case .accepted(let ready) = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session),
              ready.kind == .sessionReady else {
            fatalError("Realtime session did not become ready")
        }
        return R821Stack(
            runtime: runtime,
            provider: provider,
            session: session
        )
    }

    private static func activateResidentResponse(
        _ stack: R821Stack
    ) async throws -> RealtimeBrainEventIdentity {
        let turnID = RealtimeBrainTurnID()
        let responseID = RealtimeBrainResponseID()
        let userFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: stack.session,
                turnID: turnID,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 2,
            kind: .userTranscriptFinal("resident-only isolation")
        )
        await stack.provider.enqueue(userFinal)
        guard case .accepted = try await stack.runtime
                .receiveRealtimeResidentBrainEvent(session: stack.session) else {
            fatalError("user final was not accepted")
        }
        let createCount = await stack.provider.createCount()
        expect(createCount == 1,
               "Runtime authorizes exactly one resident response")
        let responseIdentity = RealtimeBrainEventIdentity(
            session: stack.session,
            turnID: turnID,
            responseID: responseID,
            contextRevision: 1
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: responseIdentity,
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
        guard case .accepted = try await stack.runtime
                .receiveRealtimeResidentBrainEvent(session: stack.session) else {
            fatalError("resident response was not accepted")
        }
        return responseIdentity
    }

    private static func observation(
        session: RealtimeBrainSessionIdentity,
        sequence: UInt64,
        timestamp: UInt64,
        classification: RealtimeAcousticClassification
    ) -> RealtimeAcousticObservation {
        let value: RealtimeAcousticMetrics
        switch classification {
        case .silenceOrNoise:
            value = metrics(
                timestamp: timestamp,
                playbackActive: false,
                renderRMS: 0,
                rawRMS: 0.002,
                outputRMS: 0.001,
                rawCorrelation: 0,
                erle: 0,
                source: .uncertain
            )
        case .farEndDominant:
            value = metrics(
                timestamp: timestamp,
                renderRMS: 0.2,
                rawRMS: 0.16,
                outputRMS: 0.003,
                rawCorrelation: 0.82,
                erle: 12,
                source: .echoOnly
            )
        case .residualEchoLikely:
            value = metrics(
                timestamp: timestamp,
                renderRMS: 0.2,
                rawRMS: 0.16,
                outputRMS: 0.035,
                rawCorrelation: 0.82,
                residualCorrelation: 0.8,
                erle: 1,
                source: .echoOnly
            )
        case .nearEndCandidate:
            value = metrics(
                timestamp: timestamp,
                renderRMS: 0.2,
                rawRMS: 0.25,
                outputRMS: 0.2,
                rawCorrelation: 0.1,
                erle: 0,
                source: .nearEndSpeech
            )
        case .indeterminate:
            value = metrics(
                timestamp: timestamp,
                renderRMS: nil,
                rawRMS: 0.1,
                outputRMS: 0.02,
                rawCorrelation: 0,
                erle: 0,
                source: .uncertain,
                renderReferenceAvailable: false,
                renderTimestampAvailable: false
            )
        }
        return RealtimeAcousticObservation(
            identity: RealtimeAcousticObservationIdentity(
                session: session,
                captureGeneration: 1,
                sequence: sequence,
                timestampNanoseconds: timestamp
            ),
            metrics: value,
            classification: classification
        )
    }

    private static func metrics(
        timestamp: UInt64,
        playbackActive: Bool = true,
        renderRMS: Double?,
        rawRMS: Double,
        outputRMS: Double,
        rawCorrelation: Double,
        residualCorrelation: Double = 0.1,
        erle: Double,
        source: RealtimeAcousticSourceAssessment,
        measuredDelayMilliseconds: Int = 80,
        alignedDelayMilliseconds: Int = 80,
        renderReferenceAvailable: Bool = true,
        renderTimestampAvailable: Bool = true,
        aecActive: Bool = true,
        routeStable: Bool = true,
        outputDeviceAvailable: Bool = true,
        renderCaptureIsolationEstablished: Bool = false,
        sourceAlignmentLocked: Bool? = nil
    ) -> RealtimeAcousticMetrics {
        let measured = max(0, measuredDelayMilliseconds)
        let renderTimestamp = timestamp > UInt64(measured) * 1_000_000
            ? timestamp - UInt64(measured) * 1_000_000 : 1
        return RealtimeAcousticMetrics(
            residentPlaybackSequence: playbackActive ? 1 : 0,
            residentPlaybackActive: playbackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                playbackActive ? renderTimestamp : nil,
            renderReferenceAvailable: renderReferenceAvailable,
            renderReferenceRMS: renderRMS,
            rawCaptureRMS: rawRMS,
            aecOutputRMS: outputRMS,
            linearAECOutputRMS: outputRMS,
            renderCaptureCorrelation: rawCorrelation,
            residualRenderCorrelation: residualCorrelation,
            linearRenderCorrelation: residualCorrelation,
            captureTimestampNanoseconds: timestamp,
            renderTimestampNanoseconds: renderTimestampAvailable
                ? renderTimestamp : nil,
            sourceAlignmentDelayMilliseconds: alignedDelayMilliseconds,
            estimatedDelayMilliseconds: alignedDelayMilliseconds,
            erlDecibels: 12,
            erleDecibels: erle,
            renderCaptureSkewFrames: 0,
            driftState: .stable,
            sourceAssessment: source,
            sourceGateOpen: source == .nearEndSpeech
                || source == .doubleTalk,
            sourceGateEpoch: 1,
            aecActive: aecActive,
            renderCaptureIsolationEstablished:
                renderCaptureIsolationEstablished,
            sourceAlignmentLocked:
                sourceAlignmentLocked ?? renderTimestampAvailable,
            routeStable: routeStable,
            inputDeviceAvailable: true,
            outputDeviceAvailable: outputDeviceAvailable
        )
    }

    private static func classify(
        _ metrics: RealtimeAcousticMetrics,
        timestamp: UInt64
    ) -> RealtimeAcousticClassification {
        RealtimeAcousticClassifier.classify(
            metrics: metrics,
            observationTimestampNanoseconds: timestamp
        )
    }

    private static func residentSnapshot(
        captureGeneration: UInt64,
        frameIndex: UInt64,
        classification: RealtimeAcousticClassification,
        playbackActive: Bool = false,
        aecActive: Bool = true,
        renderReferenceAvailable: Bool = true
    ) -> MacSpeechResidentAcousticSnapshot {
        let timestamp = monotonicNow()
        let source: MacSpeechAcousticInputClassification
        switch classification {
        case .farEndDominant, .residualEchoLikely: source = .echoOnly
        case .nearEndCandidate: source = .nearEndSpeech
        case .silenceOrNoise, .indeterminate: source = .uncertain
        }
        let renderTimestamp = renderReferenceAvailable && timestamp > 80_000_000
            ? timestamp - 80_000_000 : nil
        return MacSpeechResidentAcousticSnapshot(
            captureGeneration: captureGeneration,
            captureFrameIndex: frameIndex,
            captureHostTimeNanoseconds: timestamp,
            playbackSequence: playbackActive ? 1 : 0,
            residentPlaybackActive: playbackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                playbackActive ? renderTimestamp : nil,
            renderReferenceAvailable: renderReferenceAvailable,
            renderReferenceRMS: renderReferenceAvailable ? 0.2 : nil,
            renderHostTimeNanoseconds: renderTimestamp,
            rawCaptureRMS: classification == .silenceOrNoise ? 0.002 : 0.2,
            processedCaptureRMS: classification == .nearEndCandidate
                ? 0.2 : 0.002,
            linearAECOutputRMS: classification == .nearEndCandidate
                ? 0.2 : 0.002,
            renderCaptureCorrelation:
                classification == .farEndDominant ? 0.8 : 0.1,
            residualRenderCorrelation:
                classification == .residualEchoLikely ? 0.8 : 0.1,
            linearRenderCorrelation:
                classification == .residualEchoLikely ? 0.8 : 0.1,
            inputClassification: source,
            sourceGateOpen: classification == .nearEndCandidate,
            sourceGateEpoch: classification == .nearEndCandidate ? 1 : 0,
            aecEnabled: aecActive,
            aecActive: aecActive,
            renderCaptureIsolationEstablished: false,
            sourceAlignmentLocked: renderTimestamp != nil,
            sourceAlignmentDelayMilliseconds:
                renderTimestamp == nil ? nil : 80,
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

    private static func testSession() -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: "r821-resident",
            runtimeSessionID: "r821-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
    }

    private static func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
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

    private static func waitUntil(
        _ label: String,
        condition: @escaping () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        fatalError("timed out: \(label)")
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

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        checks += 1
        if !condition() { fatalError("FAILED: \(message)") }
    }
}
#endif
