import Foundation

#if DEBUG
private struct R7CredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? { nil }
}

private final class FakeMacSpeechAudioFrameSource: MacSpeechAudioFrameSourcing, @unchecked Sendable {
    private let lock = NSLock()
    private var activeGeneration: UInt64?
    private var frames: [MacSpeechAudioFrame] = []
    private var nextSequence: UInt64 = 0
    private var residentSnapshot: MacSpeechResidentAcousticSnapshot?
    private var generationBoundaryDiscardCount = 0

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
            let drained = Array(frames.prefix(count))
            frames.removeFirst(count)
            return drained
        }
    }

    func discardPendingAudioForGenerationTransition() async {
        lock.withLock { generationBoundaryDiscardCount += 1 }
    }

    func discardedGenerationBoundaryCount() -> Int {
        lock.withLock { generationBoundaryDiscardCount }
    }

    func residentAcousticSnapshot() async
        -> MacSpeechResidentAcousticSnapshot? {
        lock.withLock { residentSnapshot }
    }

    func setActiveGeneration(_ generation: UInt64) {
        lock.withLock { activeGeneration = generation }
    }

    func setResidentSnapshot(
        _ snapshot: MacSpeechResidentAcousticSnapshot?
    ) {
        lock.withLock { residentSnapshot = snapshot }
    }

    func appendFrame(
        pcm16Bytes: Data,
        activity: Float = 0,
        generation: UInt64
    ) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            nextSequence &+= 1
            frames.append(MacSpeechAudioFrame(
                captureGeneration: generation,
                sequenceNumber: nextSequence,
                monotonicTimestampNanoseconds: UInt64(nextSequence) * 20_000_000,
                pcm16Bytes: pcm16Bytes,
                activity: activity
            ))
        }
    }

    func appendStaleFrame(
        pcm16Bytes: Data,
        generation: UInt64,
        sequenceNumber: UInt64
    ) {
        lock.withLock {
            frames.append(MacSpeechAudioFrame(
                captureGeneration: generation,
                sequenceNumber: sequenceNumber,
                monotonicTimestampNanoseconds: UInt64(sequenceNumber) * 20_000_000,
                pcm16Bytes: pcm16Bytes,
                activity: 0
            ))
        }
    }

    func appendFrame(
        pcm16Bytes: Data,
        generation: UInt64,
        sequenceNumber: UInt64
    ) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            nextSequence = max(nextSequence, sequenceNumber)
            frames.append(MacSpeechAudioFrame(
                captureGeneration: generation,
                sequenceNumber: sequenceNumber,
                monotonicTimestampNanoseconds:
                    sequenceNumber * 20_000_000,
                pcm16Bytes: pcm16Bytes,
                activity: 0
            ))
        }
    }

    func appendListeningNearEndFrame(
        pcm16Bytes: Data,
        generation: UInt64,
        timestampNanoseconds: UInt64
    ) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            nextSequence &+= 1
            frames.append(MacSpeechAudioFrame(
                captureGeneration: generation,
                sequenceNumber: nextSequence,
                monotonicTimestampNanoseconds: timestampNanoseconds,
                pcm16Bytes: pcm16Bytes,
                activity: 0.18,
                activityEvidenceKind: .listeningNearEnd,
                residentPlaybackSequence: 0,
                residentPlaybackActive: false
            ))
        }
    }

    func appendRouteStableNoneFrame(
        pcm16Bytes: Data,
        generation: UInt64,
        timestampNanoseconds: UInt64
    ) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            nextSequence &+= 1
            frames.append(MacSpeechAudioFrame(
                captureGeneration: generation,
                sequenceNumber: nextSequence,
                monotonicTimestampNanoseconds: timestampNanoseconds,
                pcm16Bytes: pcm16Bytes,
                activity: 0.004,
                activityEvidenceKind: .none,
                residentPlaybackSequence: 0,
                residentPlaybackActive: false
            ))
        }
    }

    func appendSourceGatedFrame(
        pcm16Bytes: Data,
        generation: UInt64,
        acousticSnapshot: MacSpeechAcousticObservationSnapshot
    ) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            nextSequence &+= 1
            frames.append(MacSpeechAudioFrame(
                captureGeneration: generation,
                sequenceNumber: nextSequence,
                monotonicTimestampNanoseconds:
                    acousticSnapshot.captureHostTimeNanoseconds
                        ?? UInt64(nextSequence) * 20_000_000,
                pcm16Bytes: pcm16Bytes,
                activity: 0.18,
                activityEvidenceKind: .sourceGatedNearEnd,
                residentPlaybackSequence:
                    acousticSnapshot.playbackSequence,
                residentPlaybackActive:
                    acousticSnapshot.isPlaybackActive,
                lastAudibleResidentRenderTimestampNanoseconds:
                    acousticSnapshot
                        .lastAudibleRenderHostTimeNanoseconds,
                sourceGateEpoch: acousticSnapshot.sourceGateEpoch,
                acousticSnapshot: acousticSnapshot
            ))
        }
    }
}

private actor FakeRealtimeResidentBrainProvider: RealtimeResidentBrainProvider {
    private var audioFrames: [RealtimeBrainAudioFrame] = []
    private var events: [RealtimeResidentBrainEvent] = []
    private var receiveContinuation:
        CheckedContinuation<RealtimeResidentBrainEvent, Error>?
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var contextUpdates: [RealtimeBrainRuntimeContextUpdate] = []
    private var responseCommands: [RealtimeBrainCreateResponseCommand] = []
    private var cancelCommands: [RealtimeBrainCancelGenerationCommand] = []
    private var closeCommands: [RealtimeBrainCloseSessionCommand] = []
    private var nextAudioError: RealtimeResidentBrainError?
    private var nextCloseError: RealtimeResidentBrainError?

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        openCommands.append(command)
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {
        contextUpdates.append(update)
    }

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {
        audioFrames.append(frame)
        if let error = nextAudioError {
            nextAudioError = nil
            throw error
        }
    }

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {}

    func createResponse(
        _ command: RealtimeBrainCreateResponseCommand
    ) async throws {
        responseCommands.append(command)
    }

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {
        cancelCommands.append(command)
        let event = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: command.identity,
                turnID: nil,
                responseID: nil,
                contextRevision: contextUpdates.last?.contextRevision ?? 1
            ),
            sequence: 1,
            kind: .cancelled(command.reason)
        )
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: event)
        } else {
            events.append(event)
        }
    }

    func interrupt(_ command: RealtimeBrainInterruptCommand) async throws {}

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        if !events.isEmpty {
            return events.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            precondition(receiveContinuation == nil)
            receiveContinuation = continuation
        }
    }

    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws {
        closeCommands.append(command)
        if let error = nextCloseError {
            nextCloseError = nil
            throw error
        }
        let continuation = receiveContinuation
        receiveContinuation = nil
        continuation?.resume(throwing: RealtimeResidentBrainError.cancelled)
    }

    func enqueue(_ event: RealtimeResidentBrainEvent) {
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: event)
        } else {
            events.append(event)
        }
    }

    func failNextAudio(_ error: RealtimeResidentBrainError) {
        nextAudioError = error
    }

    func failNextClose(_ error: RealtimeResidentBrainError) {
        nextCloseError = error
    }

    func audioCount() -> Int { audioFrames.count }

    func firstAudioFrame() -> RealtimeBrainAudioFrame? { audioFrames.first }

    func recordedAudioFrames() -> [RealtimeBrainAudioFrame] { audioFrames }

    func openCount() -> Int { openCommands.count }

    func closeCount() -> Int { closeCommands.count }

    func responseCreateCount() -> Int { responseCommands.count }

    func cancelCount() -> Int { cancelCommands.count }

    func lastCancelCommand() -> RealtimeBrainCancelGenerationCommand? {
        cancelCommands.last
    }

    func latestContextRevision() -> UInt64 {
        contextUpdates.last?.contextRevision ?? 0
    }
}

private actor R7EventSink {
    private var events: [RealtimeResidentBrainEvent] = []
    private var dispositions: [RealtimeBrainEventDisposition] = []

    func observe(_ disposition: RealtimeBrainEventDisposition) {
        dispositions.append(disposition)
    }

    func consume(_ event: RealtimeResidentBrainEvent) {
        events.append(event)
    }

    func audioCount() -> Int {
        events.reduce(into: 0) { count, event in
            if case .residentAudioDelta = event.kind { count += 1 }
        }
    }

    func speakingStoppedCount() -> Int {
        events.reduce(into: 0) { count, event in
            if case .residentSpeakingStopped = event.kind { count += 1 }
        }
    }

    func semanticFinalCount() -> Int {
        events.reduce(into: 0) { count, event in
            if case .residentSemanticFinal = event.kind { count += 1 }
        }
    }

    func counts() -> (audio: Int, speakingStopped: Int, semanticFinal: Int) {
        (audioCount(), speakingStoppedCount(), semanticFinalCount())
    }

    func recordedDispositions() -> [RealtimeBrainEventDisposition] {
        dispositions
    }

    func recordedEvents() -> [RealtimeResidentBrainEvent] {
        events
    }
}

private actor R7HeldAudioSend {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation:
        CheckedContinuation<Result<Void, RealtimeResidentBrainError>, Never>?

    func send(
        _ frame: RealtimeBrainAudioFrame
    ) async -> Result<Void, RealtimeResidentBrainError> {
        _ = frame
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            if started {
                continuation.resume()
            } else {
                startWaiters.append(continuation)
            }
        }
    }

    func resume(
        _ result: Result<Void, RealtimeResidentBrainError>
    ) {
        guard let continuation else {
            fatalError("FAILED: held send was not ready")
        }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}

private actor R7LocalActivityConfirmationRecorder {
    private var confirmationCount = 0

    func confirm() -> Result<Void, RealtimeResidentBrainError> {
        confirmationCount += 1
        return .success(())
    }

    func count() -> Int { confirmationCount }
}

private nonisolated final class R7RuntimeBox: @unchecked Sendable {
    let runtime: RuntimeCore

    init(_ runtime: RuntimeCore) {
        self.runtime = runtime
    }
}

private nonisolated final class R7AppendResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Void, RealtimeResidentBrainError>?

    func store(_ result: Result<Void, RealtimeResidentBrainError>) {
        lock.withLock { value = result }
    }

    func result() -> Result<Void, RealtimeResidentBrainError>? {
        lock.withLock { value }
    }

    func waitForSignal(
        _ semaphore: DispatchSemaphore,
        timeout: DispatchTime
    ) -> Bool {
        semaphore.wait(timeout: timeout) == .success
    }
}

private actor R7CloseSequence {
    private var results: [Result<Void, RealtimeResidentBrainError>]
    private var callCount = 0

    init(_ results: [Result<Void, RealtimeResidentBrainError>]) {
        self.results = results
    }

    func close(
        _ binding: MacSpeechRealtimeBrainInputBinding
    ) -> Result<Void, RealtimeResidentBrainError> {
        _ = binding
        callCount += 1
        if results.isEmpty { return .success(()) }
        return results.removeFirst()
    }

    func count() -> Int { callCount }
}

private actor R7DispositionSource {
    private var dispositions: [RealtimeBrainEventDisposition]

    init(_ dispositions: [RealtimeBrainEventDisposition]) {
        self.dispositions = dispositions
    }

    func next() -> Result<
        RealtimeBrainEventDisposition,
        RealtimeResidentBrainError
    > {
        guard !dispositions.isEmpty else {
            return .success(.rejectedClosed)
        }
        return .success(dispositions.removeFirst())
    }
}

private actor R81AcousticObservationSink {
    private var observations: [MacSpeechRealtimeBrainAcousticObservation] = []

    func consume(_ observation: MacSpeechRealtimeBrainAcousticObservation) {
        observations.append(observation)
    }

    func values() -> [MacSpeechRealtimeBrainAcousticObservation] {
        observations
    }
}

private actor R82AcousticDiagnosticSink {
    private var observations: [RealtimeAcousticObservation] = []

    func observe(
        _ observation: RealtimeAcousticObservation
    ) -> RealtimeAcousticObservationDisposition {
        observations.append(observation)
        return .observed
    }

    func values() -> [RealtimeAcousticObservation] { observations }
}

private actor R85AcousticPacketDiagnosticSink {
    private var diagnostics: [MacSpeechRealtimeBrainAcousticDiagnostic] = []

    func record(_ diagnostic: MacSpeechRealtimeBrainAcousticDiagnostic) {
        diagnostics.append(diagnostic)
    }

    func packetTraces() -> [MacSpeechRealtimeBrainAcousticDiagnostic] {
        diagnostics.filter {
            $0.category == "source_gated_near_end_packet"
        }
    }
}

@MainActor
private final class R7OutputBridgeHolder {
    var bridge: MacSpeechRealtimeBrainOutputBridge?
}

@main
private struct MacSpeechRealtimeBrainInputBridgeTests {
    private static var checks = 0
    private static var cases = 0

    static func main() async {
        guard let fixturePath = ProcessInfo.processInfo.environment[
            "AFTELLE_R7_FIXTURE"
        ], let fixture = FileManager.default.contents(atPath: fixturePath) else {
            fatalError("FAILED: missing fixed R7 resident fixture")
        }
        await testBridgeForwardsFrames()
        await testBridgeStopsOnError()
        await testBridgeRejectsStaleFrames()
        await testBridgeForwardsAcousticEvidenceEdges()
        await testBridgeForwardsEvidenceWithNonFiniteAECMetrics()
        testPacketizerPreservesTenMillisecondSourceGateEvidence()
        await testBridgeUsesFrameBoundAcousticEvidence()
        await testBridgeRecordsSourceGatedPacketTerminalDiagnostics()
        await testBridgeForwardsSameEpochEvidenceAfterGateClose()
        await testBridgeRearmsEligibilityAfterEpochRolloverFence()
        await testBridgeRejectsRouteAndDeviceChangesAfterSend()
        await testBridgeRejectsExpiredEvidenceAfterSend()
        testControllerSourceGateEpochFence()
        await testBridgeSnapshot()
        await testAudioFrameConversion()
        await testStopFailsClosedAndRetries()
        await testOutputRejectsLateAudioAfterAudioDone()
        await testOutputStopFromConsumerDoesNotDeadlock()
        await testFormalRuntimeRouteRemainsActiveForTwoTurns(
            fixture: fixture
        )
        await testFormalNoneActivityAppendDoesNotAwaitMainActor(
            fixture: fixture
        )
        await testListeningActivityRevalidatesAfterProviderAppend()
        await testFormalNormalListeningSpeechAdmission(fixture: fixture)
        await testAdmittedSpeechFinalWithoutStopFailsClosed(
            fixture: fixture
        )
        await testFormalProviderSpeechRequiresBoundedLocalPCM(
            fixture: fixture
        )
        await testProviderSpeechIntervalFailsClosedForPlaybackAndTail(
            fixture: fixture
        )
        await testGenerationTransitionRebindsHost(
            fixture: fixture
        )
        await testRuntimeCloseFailureRetries(fixture: fixture)

        print("mac_speech_realtime_brain_input_bridge_cases=\(cases)")
        print("mac_speech_realtime_brain_input_bridge_checks=\(checks)")
    }

    private static func testBridgeForwardsFrames() async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 100

        source.setActiveGeneration(captureGeneration)
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )

        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) }
        )

        let snapshot = await bridge.start(binding: binding)
        expect(snapshot.state == .running, "bridge starts in running state")
        expect(snapshot.hasActivePump, "bridge has active pump")

        let pcmBytes = Data([UInt8](repeating: 0, count: 960))
        source.appendFrame(pcm16Bytes: pcmBytes, generation: captureGeneration)

        await waitUntil { await provider.audioCount() == 1 }

        let updatedSnapshot = await bridge.currentSnapshot()
        expect(updatedSnapshot.forwardedFrameCount == 1, "bridge forwards one frame")
        expect(await provider.audioCount() == 1, "provider receives one frame")

        if let receivedFrame = await provider.firstAudioFrame() {
            expect(receivedFrame.identity == session, "frame has correct session identity")
            expect(receivedFrame.sequence == 1, "frame has correct sequence")
            expect(receivedFrame.provenance == .acousticEchoProcessed, "frame has correct provenance")
            expect(receivedFrame.format.encoding == .pcm16LittleEndian, "frame has correct encoding")
            expect(receivedFrame.format.sampleRate == 24_000, "frame has correct sample rate")
            expect(receivedFrame.format.channelCount == 1, "frame has correct channel count")
            expect(receivedFrame.bytes == pcmBytes, "frame has correct bytes")
        } else {
            fatalError("FAILED: expected first audio frame")
        }

        _ = await bridge.stop()
        let finalSnapshot = await bridge.currentSnapshot()
        expect(finalSnapshot.state == .stopped, "bridge stops cleanly")
        expect(!finalSnapshot.hasActivePump, "bridge has no active pump after stop")
    }

    private static func testBridgeStopsOnError() async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 200

        source.setActiveGeneration(captureGeneration)
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )

        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) }
        )

        _ = await bridge.start(binding: binding)
        await provider.failNextAudio(.invalidAudioFrame)
        source.appendFrame(pcm16Bytes: Data(repeating: 0, count: 960), generation: captureGeneration)

        await waitUntil { await bridge.currentSnapshot().state == .failed }

        let snapshot = await bridge.currentSnapshot()
        expect(snapshot.state == .failed, "bridge fails on audio error")
        expect(snapshot.lastError == "invalid_audio_frame", "bridge records error")
    }

    private static func testBridgeRejectsStaleFrames() async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 300

        source.setActiveGeneration(captureGeneration)
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )

        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) }
        )

        _ = await bridge.start(binding: binding)
        source.appendStaleFrame(
            pcm16Bytes: Data(repeating: 0, count: 960),
            generation: captureGeneration + 1,
            sequenceNumber: 1
        )

        try? await Task.sleep(for: .milliseconds(50))

        let snapshot = await bridge.currentSnapshot()
        expect(snapshot.runtimeRejectedFrameCount == 1, "bridge rejects stale frame")
        expect(await provider.audioCount() == 0, "provider receives no stale frames")

        _ = await bridge.stop()
    }

    private static func testBridgeForwardsAcousticEvidenceEdges() async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let sink = R81AcousticObservationSink()
        let diagnostics = R82AcousticDiagnosticSink()
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 350
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 1,
            nearEnd: true
        ))
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) },
            observeResidentAcoustics: { observation in
                await diagnostics.observe(observation)
            },
            consumeAcousticObservation: { observation in
                await sink.consume(observation)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            acousticSnapshot: acousticSnapshot(
                frameIndex: 1,
                classification: .nearEndSpeech,
                sourceGateOpen: true
            )
        )
        await waitUntil(label: "first acoustic evidence") {
            await sink.values().count == 1
        }
        let first = await sink.values()[0]
        expect(first.session == session,
               "acoustic evidence carries the exact Runtime session identity")
        expect(first.sequence == 1 && first.timestampNanoseconds > 0,
               "acoustic evidence carries submitted sequence and monotonic time")
        expect(first.facts.nearEndDetected && first.facts.farEndActive,
               "acoustic evidence preserves near-end and render facts")

        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 11,
            nearEnd: false
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 2, count: 960),
            generation: captureGeneration,
            acousticSnapshot: acousticSnapshot(
                frameIndex: 11,
                classification: .echoOnly,
                sourceGateOpen: false
            )
        )
        await waitUntil(label: "suppressed acoustic frame") {
            await provider.audioCount() == 2
        }
        await waitUntil(label: "suppressed acoustic diagnostics") {
            await diagnostics.values().count == 1
        }
        await waitUntil(label: "suppressed diagnostics settled") {
            !(await bridge.currentSnapshot()
                .hasPendingResidentAcousticObservation)
        }
        expect(await diagnostics.values()[0].classification == .farEndDominant,
               "suppressed frame uses the production far-end classifier")
        expect(await sink.values().count == 1,
               "one source-gate edge emits only one acoustic fact")
        let snapshot = await bridge.currentSnapshot()
        expect(
            snapshot.acousticEvidenceCount == 1,
            "bridge reports one eligible edge and suppresses far-end"
        )
        _ = await bridge.stop()
    }

    private static func testBridgeForwardsSameEpochEvidenceAfterGateClose()
        async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let sink = R81AcousticObservationSink()
        let session = RealtimeBrainSessionIdentity(
            residentID: "same-epoch-close-resident",
            runtimeSessionID: "same-epoch-close-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 351
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 1,
            classification: .nearEndSpeech,
            sourceGateOpen: true,
            sourceGateEpoch: 1
        ))
        let closedSnapshot = residentSnapshot(
            generation: captureGeneration,
            frameIndex: 2,
            classification: .echoOnly,
            sourceGateOpen: false,
            sourceGateEpoch: 1
        )
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrameWithActivity: { frame, _ in
                do {
                    try await provider.appendAudio(frame)
                    if frame.sequence == 1 {
                        source.setResidentSnapshot(closedSnapshot)
                    }
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { observation in
                await sink.consume(observation)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            acousticSnapshot: acousticSnapshot(
                frameIndex: 1,
                classification: .nearEndSpeech,
                sourceGateOpen: true,
                sourceGateEpoch: 1
            )
        )
        await waitUntil(label: "same-epoch closed-gate evidence") {
            await sink.values().count == 1
        }
        let snapshot = await bridge.currentSnapshot()
        expect(snapshot.acousticEligibilityCandidateCount == 1,
               "same-epoch close preserves the packet-bound candidate")
        expect(snapshot.acousticEvidenceCount == 1,
               "same-epoch close forwards exactly one acoustic fact")
        expect(snapshot.acousticEvidenceStaleFenceCount == 0,
               "same-epoch close is not a stale-fence transition")
        expect(snapshot.acousticEligibilityRearmedCount == 0,
               "delivered same-epoch evidence is never rearmed")
        _ = await bridge.stop()
    }

    private static func testBridgeRearmsEligibilityAfterEpochRolloverFence()
        async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let sink = R81AcousticObservationSink()
        let session = RealtimeBrainSessionIdentity(
            residentID: "rearm-resident",
            runtimeSessionID: "rearm-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 352
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 1,
            classification: .nearEndSpeech,
            sourceGateOpen: true,
            sourceGateEpoch: 1
        ))
        let rolledSnapshot = residentSnapshot(
            generation: captureGeneration,
            frameIndex: 2,
            classification: .nearEndSpeech,
            sourceGateOpen: true,
            sourceGateEpoch: 2
        )
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrameWithActivity: { frame, _ in
                do {
                    try await provider.appendAudio(frame)
                    if frame.sequence == 1 {
                        source.setResidentSnapshot(rolledSnapshot)
                    }
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { observation in
                await sink.consume(observation)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            acousticSnapshot: acousticSnapshot(
                frameIndex: 1,
                classification: .nearEndSpeech,
                sourceGateOpen: true,
                sourceGateEpoch: 1
            )
        )
        await waitUntil(label: "stale acoustic evidence rearm") {
            let snapshot = await bridge.currentSnapshot()
            return snapshot.acousticEligibilityRearmedCount == 1
                && snapshot.acousticEvidenceStaleFenceCount == 1
        }
        expect(
            await sink.values().isEmpty,
            "a new source-gate epoch cannot accept old packet evidence"
        )

        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 3,
            classification: .nearEndSpeech,
            sourceGateOpen: true,
            sourceGateEpoch: 2
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 2, count: 960),
            generation: captureGeneration,
            acousticSnapshot: acousticSnapshot(
                frameIndex: 3,
                classification: .nearEndSpeech,
                sourceGateOpen: true,
                sourceGateEpoch: 2
            )
        )
        await waitUntil(label: "rearmed acoustic evidence") {
            await sink.values().count == 1
        }
        let snapshot = await bridge.currentSnapshot()
        expect(snapshot.acousticEligibilityCandidateCount == 2,
               "fresh source-gate epoch can issue a second eligibility candidate")
        expect(snapshot.acousticEligibilityRearmedCount == 1,
               "only the undelivered stale candidate rearms eligibility")
        expect(snapshot.acousticEvidenceCount == 1,
               "only the fresh candidate reaches Runtime acoustic evidence")
        expect(
            snapshot.acousticEvidenceForwardDispositionCounts["forwarded"]
                == 1,
            "forward diagnostics preserve the successful fresh candidate"
        )
        _ = await bridge.stop()
    }

    private static func testBridgeRejectsExpiredEvidenceAfterSend()
        async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let sink = R81AcousticObservationSink()
        let session = RealtimeBrainSessionIdentity(
            residentID: "expired-evidence-resident",
            runtimeSessionID: "expired-evidence-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 354
        let capturedSnapshot = acousticSnapshot(
            frameIndex: 1,
            classification: .nearEndSpeech,
            sourceGateOpen: true,
            sourceGateEpoch: 1
        )
        let captureTimestamp = capturedSnapshot.captureHostTimeNanoseconds!
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 1,
            classification: .nearEndSpeech,
            sourceGateOpen: true,
            sourceGateEpoch: 1
        ))
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrameWithActivity: { frame, _ in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { observation in
                await sink.consume(observation)
            },
            monotonicNow: {
                captureTimestamp
                    + RealtimeAcousticInterruptionEligibilityGate
                        .observationFreshnessNanoseconds
                    + 1
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            acousticSnapshot: capturedSnapshot
        )
        await waitUntil(label: "expired acoustic evidence fence") {
            let snapshot = await bridge.currentSnapshot()
            return snapshot.acousticEligibilityRearmedCount == 1
                && snapshot.acousticEvidenceStaleFenceCount == 1
        }
        let snapshot = await bridge.currentSnapshot()
        expect(await sink.values().isEmpty,
               "expired packet evidence never reaches Runtime")
        expect(
            snapshot.acousticEvidenceForwardDispositionCounts[
                "stale_observation_expired"
            ] == 1,
            "the 500 ms freshness fence records its exact reason"
        )
        expect(snapshot.acousticEvidenceCount == 0,
               "expired evidence cannot increment the delivered count")
        _ = await bridge.stop()
    }

    private static func testBridgeRejectsRouteAndDeviceChangesAfterSend()
        async {
        cases += 1
        let scenarios: [(
            label: String,
            disposition: String,
            routeStable: Bool,
            inputDeviceAvailable: Bool,
            outputDeviceAvailable: Bool
        )] = [
            ("route", "stale_route_unstable", false, true, true),
            ("input", "stale_input_device_unavailable", true, false, true),
            ("output", "stale_output_device_unavailable", true, true, false)
        ]
        for (offset, scenario) in scenarios.enumerated() {
            let source = FakeMacSpeechAudioFrameSource()
            let provider = FakeRealtimeResidentBrainProvider()
            let sink = R81AcousticObservationSink()
            let session = RealtimeBrainSessionIdentity(
                residentID: "\(scenario.label)-fence-resident",
                runtimeSessionID: "\(scenario.label)-fence-session",
                brainLeaseID: UUID(),
                routeEpoch: 1,
                generation: 1
            )
            let captureGeneration = UInt64(355 + offset)
            source.setActiveGeneration(captureGeneration)
            source.setResidentSnapshot(residentSnapshot(
                generation: captureGeneration,
                frameIndex: 1,
                classification: .nearEndSpeech,
                sourceGateOpen: true,
                sourceGateEpoch: 1
            ))
            let invalidSnapshot = residentSnapshot(
                generation: captureGeneration,
                frameIndex: 2,
                classification: .nearEndSpeech,
                sourceGateOpen: true,
                sourceGateEpoch: 1,
                routeStable: scenario.routeStable,
                inputDeviceAvailable: scenario.inputDeviceAvailable,
                outputDeviceAvailable: scenario.outputDeviceAvailable
            )
            let bridge = MacSpeechRealtimeBrainInputBridge(
                source: source,
                sendFrameWithActivity: { frame, _ in
                    do {
                        try await provider.appendAudio(frame)
                        source.setResidentSnapshot(invalidSnapshot)
                        return .success(())
                    } catch let error as RealtimeResidentBrainError {
                        return .failure(error)
                    } catch {
                        return .failure(.providerFailure)
                    }
                },
                stopInput: { _ in .success(()) },
                consumeAcousticObservation: { observation in
                    await sink.consume(observation)
                }
            )
            _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
                session: session,
                captureGeneration: captureGeneration
            ))
            source.appendSourceGatedFrame(
                pcm16Bytes: Data(repeating: 1, count: 960),
                generation: captureGeneration,
                acousticSnapshot: acousticSnapshot(
                    frameIndex: 1,
                    classification: .nearEndSpeech,
                    sourceGateOpen: true,
                    sourceGateEpoch: 1
                )
            )
            await waitUntil(label: "\(scenario.label) live fence") {
                await bridge.currentSnapshot()
                    .acousticEvidenceStaleFenceCount == 1
            }
            let snapshot = await bridge.currentSnapshot()
            expect(await sink.values().isEmpty,
                   "\(scenario.label) transition rejects pending evidence")
            expect(
                snapshot.acousticEvidenceForwardDispositionCounts[
                    scenario.disposition
                ] == 1,
                "\(scenario.label) transition records its exact fence"
            )
            _ = await bridge.stop()
        }
    }

    private static func testBridgeForwardsEvidenceWithNonFiniteAECMetrics()
        async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let sink = R81AcousticObservationSink()
        let session = RealtimeBrainSessionIdentity(
            residentID: "non-finite-aec-resident",
            runtimeSessionID: "non-finite-aec-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 353
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 1,
            classification: .nearEndSpeech,
            sourceGateOpen: true,
            sourceGateEpoch: 1,
            erleDecibels: .nan
        ))
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrameWithActivity: { frame, _ in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { observation in
                await sink.consume(observation)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            acousticSnapshot: acousticSnapshot(
                frameIndex: 1,
                classification: .nearEndSpeech,
                sourceGateOpen: true,
                sourceGateEpoch: 1,
                erleDecibels: .nan
            )
        )
        await waitUntil(label: "non-finite AEC acoustic evidence") {
            await sink.values().count == 1
        }
        let snapshot = await bridge.currentSnapshot()
        expect(snapshot.acousticEvidenceCount == 1,
               "non-finite optional AEC metrics do not strand eligible evidence")
        _ = await bridge.stop()
    }

    private static func testPacketizerPreservesTenMillisecondSourceGateEvidence() {
        cases += 1
        var packetizer = MacSpeechPCM16Packetizer()
        let nearEnd = acousticSnapshot(
            frameIndex: 1,
            classification: .nearEndSpeech,
            sourceGateOpen: true
        )
        let uncertain = acousticSnapshot(
            frameIndex: 2,
            classification: .uncertain,
            sourceGateOpen: true
        )

        let firstHalf = packetizer.append(
            samples: [Float](repeating: 0.2, count: 240),
            activityEvidenceKind: .sourceGatedNearEnd,
            acousticSnapshot: nearEnd
        )
        expect(firstHalf.isEmpty,
               "first 10 ms waits for a complete Provider PCM packet")
        let packets = packetizer.append(
            samples: [Float](repeating: 0.002, count: 240),
            activityEvidenceKind: .none,
            acousticSnapshot: uncertain
        )
        expect(packets.count == 1,
               "two 10 ms capture windows form one 20 ms Provider packet")
        expect(packets[0].activityEvidenceKind == .sourceGatedNearEnd,
               "20 ms packet retains near-end evidence from its first half")
        expect(packets[0].acousticSnapshot?.captureFrameIndex == 1,
               "packet binds the exact positive AEC snapshot")

        packetizer.reset()
        let echoOnly = acousticSnapshot(
            frameIndex: 3,
            classification: .echoOnly,
            sourceGateOpen: false
        )
        let residentOnlyPackets = packetizer.append(
            samples: [Float](repeating: 0.002, count: 480),
            activityEvidenceKind: .none,
            acousticSnapshot: echoOnly
        )
        expect(residentOnlyPackets.count == 1
                   && residentOnlyPackets[0].activityEvidenceKind == .none,
               "resident-only packet does not gain near-end evidence")
    }

    private static func testBridgeUsesFrameBoundAcousticEvidence() async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let sink = R81AcousticObservationSink()
        let session = RealtimeBrainSessionIdentity(
            residentID: "frame-bound-resident",
            runtimeSessionID: "frame-bound-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 351
        let capturedNearEnd = acousticSnapshot(
            frameIndex: 1,
            classification: .nearEndSpeech,
            sourceGateOpen: true
        )
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 2,
            classification: .uncertain,
            sourceGateOpen: true
        ))
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrameWithActivity: { frame, _ in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) },
            consumeAcousticObservation: { observation in
                await sink.consume(observation)
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            acousticSnapshot: capturedNearEnd
        )

        await waitUntil(label: "frame-bound acoustic evidence") {
            await sink.values().count == 1
        }
        let snapshot = await bridge.currentSnapshot()
        expect(snapshot.sourceGatedNearEndFrameCount == 1,
               "Bridge accepts the packet-bound source-gate activity")
        expect(snapshot.acousticEvidenceCount == 1,
               "Bridge evaluates the bound positive snapshot instead of a later uncertain sample")
        _ = await bridge.stop()
    }

    private static func testBridgeRecordsSourceGatedPacketTerminalDiagnostics()
        async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let diagnostics = R85AcousticPacketDiagnosticSink()
        let session = RealtimeBrainSessionIdentity(
            residentID: "packet-trace-resident",
            runtimeSessionID: "packet-trace-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 354
        let positiveSnapshot = acousticSnapshot(
            frameIndex: 1,
            classification: .doubleTalk,
            sourceGateOpen: true,
            sourceGateEpoch: 7
        )
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(residentSnapshot(
            generation: captureGeneration,
            frameIndex: 1,
            classification: .doubleTalk,
            sourceGateOpen: true,
            sourceGateEpoch: 7
        ))
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            acousticSnapshot: positiveSnapshot
        )
        source.appendSourceGatedFrame(
            pcm16Bytes: Data(repeating: 2, count: 960),
            generation: captureGeneration,
            acousticSnapshot: positiveSnapshot
        )

        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) },
            recordAcousticDiagnostic: { diagnostic in
                Task { await diagnostics.record(diagnostic) }
            }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))

        await waitUntil(label: "source-gated packet terminal diagnostics") {
            await diagnostics.packetTraces().count == 2
        }
        let traces = await diagnostics.packetTraces().sorted {
            ($0.packetTrace?.packetSequence ?? 0)
                < ($1.packetTrace?.packetSequence ?? 0)
        }
        let evaluated = traces[0]
        expect(evaluated.disposition == "eligible",
               "positive packet records the eligibility result")
        expect(evaluated.packetTrace?.packetSequence == 1
                   && evaluated.packetTrace?.captureFrameIndex == 1,
               "positive packet correlates packet and capture sequences")
        expect(evaluated.packetTrace?.observationSequence == 1
                   && evaluated.packetTrace?
                        .observationTimestampNanoseconds != nil,
               "evaluated packet records observation identity")
        expect(evaluated.packetTrace?.playbackSequence == 1
                   && evaluated.packetTrace?.sourceGateEpoch == 7,
               "evaluated packet records playback and source-gate identity")
        expect(evaluated.packetTrace?.sourceAssessment == "double_talk"
                   && evaluated.packetTrace?.classification
                        == "near_end_candidate",
               "evaluated packet records source and high-level classifications")
        expect(
            evaluated.packetTrace?.captureTimestampNanoseconds
                == evaluated.packetTrace?.observationTimestampNanoseconds,
            "evaluated packet records the exact capture timestamp"
        )
        expect(
            (evaluated.packetTrace?.lastAudibleRenderTimestampNanoseconds ?? 1)
                <= (evaluated.packetTrace?.captureTimestampNanoseconds ?? 0),
            "evaluated packet exposes causal last-audible evidence"
        )
        expect(evaluated.packetTrace?.gateLastSequence == 0
                   && evaluated.packetTrace?.gateLastTimestampNanoseconds == 0
                   && evaluated.packetTrace?.gateLastPlaybackSequence == 0
                   && evaluated.packetTrace?
                        .gateLastAudibleRenderTimestampNanoseconds == 0,
               "evaluated packet records the authoritative gate pre-state")

        let guarded = traces[1]
        expect(guarded.disposition == "guard_capture_frame_not_newer",
               "early-return packet records its exact terminal guard")
        expect(guarded.packetTrace?.packetSequence == 2
                   && guarded.packetTrace?.captureFrameIndex == 1,
               "early-return packet remains correlated to its packet evidence")
        expect(guarded.packetTrace?.observationSequence == nil
                   && guarded.packetTrace?.classification == nil,
               "early-return trace does not invent an observation result")
        _ = await bridge.stop()
    }

    private static func residentSnapshot(
        generation: UInt64,
        frameIndex: UInt64,
        nearEnd: Bool
    ) -> MacSpeechResidentAcousticSnapshot {
        let captureTimestamp = DispatchTime.now().uptimeNanoseconds
        let renderTimestamp = captureTimestamp - 80_000_000
        return MacSpeechResidentAcousticSnapshot(
            captureGeneration: generation,
            captureFrameIndex: frameIndex,
            captureHostTimeNanoseconds: captureTimestamp,
            playbackSequence: 1,
            residentPlaybackActive: true,
            lastAudibleResidentRenderTimestampNanoseconds: renderTimestamp,
            renderReferenceAvailable: true,
            renderReferenceRMS: 0.2,
            renderHostTimeNanoseconds: renderTimestamp,
            rawCaptureRMS: 0.2,
            processedCaptureRMS: nearEnd ? 0.2 : 0.002,
            linearAECOutputRMS: nearEnd ? 0.2 : 0.002,
            renderCaptureCorrelation: nearEnd ? 0.1 : 0.8,
            residualRenderCorrelation: 0.1,
            linearRenderCorrelation: 0.1,
            inputClassification: nearEnd ? .nearEndSpeech : .echoOnly,
            sourceGateOpen: nearEnd,
            sourceGateEpoch: nearEnd ? 1 : 0,
            aecEnabled: true,
            aecActive: true,
            renderCaptureIsolationEstablished: false,
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

    private static func residentSnapshot(
        generation: UInt64,
        frameIndex: UInt64,
        classification: MacSpeechAcousticInputClassification,
        sourceGateOpen: Bool,
        sourceGateEpoch: UInt64? = nil,
        erleDecibels: Double = 10,
        routeStable: Bool = true,
        inputDeviceAvailable: Bool = true,
        outputDeviceAvailable: Bool = true
    ) -> MacSpeechResidentAcousticSnapshot {
        let acoustic = acousticSnapshot(
            frameIndex: frameIndex,
            classification: classification,
            sourceGateOpen: sourceGateOpen,
            sourceGateEpoch: sourceGateEpoch,
            erleDecibels: erleDecibels
        )
        return MacSpeechResidentAcousticSnapshot(
            captureGeneration: generation,
            captureFrameIndex: acoustic.captureFrameIndex,
            captureHostTimeNanoseconds:
                acoustic.captureHostTimeNanoseconds,
            playbackSequence: acoustic.playbackSequence,
            residentPlaybackActive: acoustic.isPlaybackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                acoustic.lastAudibleRenderHostTimeNanoseconds,
            renderReferenceAvailable:
                acoustic.renderReferenceAvailable,
            renderReferenceRMS: acoustic.renderReferenceRMS,
            renderHostTimeNanoseconds:
                acoustic.renderHostTimeNanoseconds,
            rawCaptureRMS: acoustic.rawCaptureRMS,
            processedCaptureRMS: acoustic.processedCaptureRMS,
            linearAECOutputRMS: acoustic.linearAECOutputRMS,
            renderCaptureCorrelation:
                acoustic.renderCaptureCorrelation,
            residualRenderCorrelation:
                acoustic.residualRenderCorrelation,
            linearRenderCorrelation:
                acoustic.linearRenderCorrelation,
            inputClassification: acoustic.inputClassification,
            sourceGateOpen: acoustic.sourceGateOpen,
            sourceGateEpoch: acoustic.sourceGateEpoch,
            aecEnabled: acoustic.aecEnabled,
            aecActive: acoustic.aecActive,
            renderCaptureIsolationEstablished:
                acoustic.renderCaptureIsolationEstablished,
            sourceAlignmentLocked: acoustic.sourceAlignmentLocked,
            sourceAlignmentDelayMilliseconds:
                acoustic.sourceAlignmentDelayMilliseconds,
            estimatedDelayMilliseconds:
                acoustic.estimatedDelayMilliseconds,
            erlDecibels: acoustic.erlDecibels,
            erleDecibels: acoustic.erleDecibels,
            renderCaptureSkewFrames:
                acoustic.renderCaptureSkewFrames,
            driftTrend: acoustic.driftTrend,
            routeStable: routeStable,
            inputDeviceAvailable: inputDeviceAvailable,
            outputDeviceAvailable: outputDeviceAvailable
        )
    }

    private static func acousticSnapshot(
        frameIndex: UInt64,
        classification: MacSpeechAcousticInputClassification,
        sourceGateOpen: Bool,
        sourceGateEpoch: UInt64? = nil,
        erleDecibels: Double = 10
    ) -> MacSpeechAcousticObservationSnapshot {
        let captureTimestamp = DispatchTime.now().uptimeNanoseconds
        let renderTimestamp = captureTimestamp - 80_000_000
        let isNearEnd = classification == .nearEndSpeech
            || classification == .doubleTalk
        return MacSpeechAcousticObservationSnapshot(
            captureFrameIndex: frameIndex,
            captureHostTimeNanoseconds: captureTimestamp,
            playbackSequence: 1,
            isPlaybackActive: true,
            lastAudibleRenderHostTimeNanoseconds: renderTimestamp,
            renderReferenceAvailable: true,
            renderReferenceRMS: 0.2,
            renderHostTimeNanoseconds: renderTimestamp,
            rawCaptureRMS: 0.2,
            processedCaptureRMS: isNearEnd ? 0.2 : 0.002,
            linearAECOutputRMS: isNearEnd ? 0.2 : 0.002,
            renderCaptureCorrelation: isNearEnd ? 0.1 : 0.8,
            residualRenderCorrelation: 0.1,
            linearRenderCorrelation: 0.1,
            inputClassification: classification,
            sourceGateOpen: sourceGateOpen,
            sourceGateEpoch: sourceGateEpoch ?? (sourceGateOpen ? 1 : 0),
            aecEnabled: true,
            aecActive: true,
            renderCaptureIsolationEstablished: false,
            sourceAlignmentLocked: true,
            sourceAlignmentDelayMilliseconds: 80,
            estimatedDelayMilliseconds: 80,
            erlDecibels: 12,
            erleDecibels: erleDecibels,
            renderCaptureSkewFrames: 0,
            driftTrend: "stable"
        )
    }

    private static func testControllerSourceGateEpochFence() {
        cases += 1
        let session = RealtimeBrainSessionIdentity(
            residentID: "controller-fence",
            runtimeSessionID: "controller-fence-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let observation = MacSpeechRealtimeBrainAcousticObservation(
            observation: RealtimeAcousticObservation(
                identity: RealtimeAcousticObservationIdentity(
                    session: session,
                    captureGeneration: 700,
                    sequence: 1,
                    timestampNanoseconds:
                        DispatchTime.now().uptimeNanoseconds
                ),
                metrics: controllerFenceMetrics(sourceGateEpoch: 9),
                classification: .nearEndCandidate
            ),
            facts: RealtimeInterruptionAcousticFacts(
                sourceGateEpoch: 9,
                nearEndDetected: true,
                farEndActive: true,
                sourceGateOpen: true,
                renderReferenceConfidence: 1,
                routeStable: true,
                inputDeviceAvailable: true,
                outputDeviceAvailable: true
            )
        )
        expect(
            observation.matchesCurrentPlayback(controllerFenceSnapshot(
                sourceGateOpen: false,
                sourceGateEpoch: 9
            )),
            "Case A Controller accepts captured evidence after same-epoch close"
        )
        expect(
            !observation.matchesCurrentPlayback(controllerFenceSnapshot(
                sourceGateOpen: true,
                sourceGateEpoch: 10
            )),
            "Case B Controller rejects old evidence after gate reopens"
        )
        expect(
            observation.matchesCurrentPlayback(controllerFenceSnapshot(
                sourceGateOpen: true,
                sourceGateEpoch: 9
            )),
            "Case C Controller accepts evidence in the same open epoch"
        )
        expect(
            !observation.matchesCurrentPlayback(controllerFenceSnapshot(
                sourceGateOpen: true,
                sourceGateEpoch: 9,
                routeStable: false
            )),
            "Case D Controller rejects evidence after route instability"
        )
        expect(
            !observation.matchesCurrentPlayback(controllerFenceSnapshot(
                sourceGateOpen: true,
                sourceGateEpoch: 9,
                inputDeviceAvailable: false
            )),
            "Case E Controller rejects evidence after input loss"
        )
        expect(
            !observation.matchesCurrentPlayback(controllerFenceSnapshot(
                sourceGateOpen: true,
                sourceGateEpoch: 9,
                outputDeviceAvailable: false
            )),
            "Case F Controller rejects evidence after output loss"
        )
    }

    private static func controllerFenceMetrics(
        sourceGateEpoch: UInt64
    ) -> RealtimeAcousticMetrics {
        let captureTimestamp = DispatchTime.now().uptimeNanoseconds
        return RealtimeAcousticMetrics(
            residentPlaybackSequence: 3,
            residentPlaybackActive: true,
            lastAudibleResidentRenderTimestampNanoseconds:
                captureTimestamp - 80_000_000,
            renderReferenceAvailable: true,
            renderReferenceRMS: 0.2,
            rawCaptureRMS: 0.2,
            aecOutputRMS: 0.2,
            linearAECOutputRMS: 0.2,
            renderCaptureCorrelation: 0.1,
            residualRenderCorrelation: 0.1,
            linearRenderCorrelation: 0.1,
            captureTimestampNanoseconds: captureTimestamp,
            renderTimestampNanoseconds: captureTimestamp - 80_000_000,
            sourceAlignmentDelayMilliseconds: 80,
            estimatedDelayMilliseconds: 80,
            erlDecibels: 12,
            erleDecibels: 10,
            renderCaptureSkewFrames: 0,
            driftState: .stable,
            sourceAssessment: .nearEndSpeech,
            sourceGateOpen: true,
            sourceGateEpoch: sourceGateEpoch,
            aecActive: true,
            renderCaptureIsolationEstablished: false,
            sourceAlignmentLocked: true,
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
    }

    private static func controllerFenceSnapshot(
        sourceGateOpen: Bool,
        sourceGateEpoch: UInt64,
        routeStable: Bool = true,
        inputDeviceAvailable: Bool = true,
        outputDeviceAvailable: Bool = true
    ) -> MacSpeechResidentAcousticSnapshot {
        let captureTimestamp = DispatchTime.now().uptimeNanoseconds
        return MacSpeechResidentAcousticSnapshot(
            captureGeneration: 700,
            captureFrameIndex: 2,
            captureHostTimeNanoseconds: captureTimestamp,
            playbackSequence: 3,
            residentPlaybackActive: true,
            lastAudibleResidentRenderTimestampNanoseconds:
                captureTimestamp - 80_000_000,
            renderReferenceAvailable: true,
            renderReferenceRMS: 0.2,
            renderHostTimeNanoseconds: captureTimestamp - 80_000_000,
            rawCaptureRMS: 0.2,
            processedCaptureRMS: 0.2,
            linearAECOutputRMS: 0.2,
            renderCaptureCorrelation: 0.1,
            residualRenderCorrelation: 0.1,
            linearRenderCorrelation: 0.1,
            inputClassification: .nearEndSpeech,
            sourceGateOpen: sourceGateOpen,
            sourceGateEpoch: sourceGateEpoch,
            aecEnabled: true,
            aecActive: true,
            renderCaptureIsolationEstablished: false,
            sourceAlignmentLocked: true,
            sourceAlignmentDelayMilliseconds: 80,
            estimatedDelayMilliseconds: 80,
            erlDecibels: 12,
            erleDecibels: 10,
            renderCaptureSkewFrames: 0,
            driftTrend: "stable",
            routeStable: routeStable,
            inputDeviceAvailable: inputDeviceAvailable,
            outputDeviceAvailable: outputDeviceAvailable
        )
    }

    private static func testBridgeSnapshot() async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let provider = FakeRealtimeResidentBrainProvider()
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 400

        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                do {
                    try await provider.appendAudio(frame)
                    return .success(())
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.providerFailure)
                }
            },
            stopInput: { _ in .success(()) }
        )

        let initialSnapshot = await bridge.currentSnapshot()
        expect(initialSnapshot.state == .idle, "initial state is idle")
        expect(!initialSnapshot.hasActivePump, "initial has no active pump")
        expect(initialSnapshot.forwardedFrameCount == 0, "initial has no forwarded frames")

        source.setActiveGeneration(captureGeneration)
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )

        _ = await bridge.start(binding: binding)
        let runningSnapshot = await bridge.currentSnapshot()
        expect(runningSnapshot.sessionShortID == String(session.brainLeaseID.uuidString.prefix(8)), "snapshot has session ID")
    }

    private static func testAudioFrameConversion() async {
        cases += 1
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )

        let macFrame = MacSpeechAudioFrame(
            captureGeneration: 100,
            sequenceNumber: 42,
            monotonicTimestampNanoseconds: 1_000_000_000,
            pcm16Bytes: Data([UInt8](repeating: 128, count: 960)),
            activity: 0.5
        )

        let realtimeFrame = RealtimeBrainAudioFrame(
            identity: session,
            sequence: macFrame.sequenceNumber,
            timestampNanoseconds: macFrame.monotonicTimestampNanoseconds,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: Int(MacSpeechAudioInputFormat.sampleRate),
                channelCount: Int(MacSpeechAudioInputFormat.channelCount)
            ),
            provenance: .acousticEchoProcessed,
            bytes: macFrame.pcm16Bytes
        )

        expect(realtimeFrame.identity == session, "converted frame has correct identity")
        expect(realtimeFrame.sequence == 42, "converted frame has correct sequence")
        expect(realtimeFrame.timestampNanoseconds == 1_000_000_000, "converted frame has correct timestamp")
        expect(realtimeFrame.provenance == .acousticEchoProcessed, "converted frame has correct provenance")
        expect(realtimeFrame.format.sampleRate == 24_000, "converted frame has correct sample rate")
        expect(realtimeFrame.format.channelCount == 1, "converted frame has correct channel count")
        expect(realtimeFrame.bytes.count == 960, "converted frame has correct byte count")
    }

    private static func testStopFailsClosedAndRetries() async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let heldSend = R7HeldAudioSend()
        let closeSequence = R7CloseSequence([
            .failure(.transportFailure),
            .success(())
        ])
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 500
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )
        source.setActiveGeneration(captureGeneration)
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in await heldSend.send(frame) },
            stopInput: { binding in
                await closeSequence.close(binding)
            }
        )
        _ = await bridge.start(binding: binding)
        source.appendFrame(
            pcm16Bytes: Data(repeating: 0, count: 960),
            generation: captureGeneration
        )
        await heldSend.waitUntilStarted()

        let failedStop = await bridge.stop(expectedSession: session)
        expect(
            failedStop.snapshot.state == .failed,
            "close failure is visible on the input bridge"
        )
        expect(
            failedStop.snapshot.lastError == "transport_failure",
            "close failure keeps a bounded error code"
        )
        expect(
            !failedStop.snapshot.hasActivePump,
            "stop fences the input pump before a held send returns"
        )
        if case .failure(.transportFailure)? = failedStop.closeResult {
            expect(true, "stop returns the Runtime close failure")
        } else {
            expect(false, "stop returns the Runtime close failure")
        }
        let blockedRestart = await bridge.start(binding: binding)
        expect(
            !blockedRestart.hasActivePump,
            "a pending close blocks session restart"
        )
        expect(await closeSequence.count() == 1, "first stop closes once")

        await heldSend.resume(.success(()))
        for _ in 0..<5 { await Task.yield() }
        expect(
            await bridge.currentSnapshot().forwardedFrameCount == 0,
            "late held-send completion cannot revive stopped metrics"
        )

        let retry = await bridge.stop(expectedSession: session)
        if case .success? = retry.closeResult {
            expect(true, "the same session identity retries close")
        } else {
            expect(false, "the same session identity retries close")
        }
        expect(await closeSequence.count() == 2, "close retry is not lost")
        let restarted = await bridge.start(binding: binding)
        expect(
            restarted.hasActivePump,
            "successful close clears the pending-close fence"
        )
        _ = await bridge.stop(expectedSession: session)

        let automaticSource = FakeMacSpeechAudioFrameSource()
        let automaticClose = R7CloseSequence([
            .failure(.transportFailure),
            .success(())
        ])
        automaticSource.setActiveGeneration(captureGeneration)
        let automaticBridge = MacSpeechRealtimeBrainInputBridge(
            source: automaticSource,
            sendFrame: { _ in .failure(.transportFailure) },
            stopInput: { binding in await automaticClose.close(binding) }
        )
        _ = await automaticBridge.start(binding: binding)
        automaticSource.appendFrame(
            pcm16Bytes: Data(repeating: 0, count: 960),
            generation: captureGeneration
        )
        await waitUntil(label: "automatic close failure") {
            await automaticBridge.currentSnapshot().state == .failed
        }
        expect(
            await automaticClose.count() == 1,
            "send failure attempts Runtime close once"
        )
        let wrongSession = RealtimeBrainSessionIdentity(
            residentID: session.residentID,
            runtimeSessionID: session.runtimeSessionID,
            brainLeaseID: session.brainLeaseID,
            routeEpoch: session.routeEpoch,
            generation: session.generation + 1
        )
        let mismatchedSettlement = await automaticBridge
            .settleExternalCloseSuccess(session: wrongSession)
        expect(
            mismatchedSettlement.state == .failed,
            "external settlement cannot clear another generation"
        )
        let externalSettlement = await automaticBridge
            .settleExternalCloseSuccess(session: session)
        expect(
            externalSettlement.state == .stopped,
            "matching external Runtime close clears the pending fence"
        )
        let restartAfterExternalClose = await automaticBridge.start(
            binding: binding
        )
        expect(
            restartAfterExternalClose.hasActivePump,
            "external close settlement permits a new Host pump"
        )
        _ = await automaticBridge.stop(expectedSession: session)
    }

    private static func testOutputRejectsLateAudioAfterAudioDone() async {
        cases += 1
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let firstTurn = RealtimeBrainTurnID()
        let firstResponse = RealtimeBrainResponseID()
        let secondTurn = RealtimeBrainTurnID()
        let secondResponse = RealtimeBrainResponseID()
        let format = RealtimeBrainAudioFormat(
            encoding: .pcm16LittleEndian,
            sampleRate: 24_000,
            channelCount: 1
        )
        func identity(
            turn: RealtimeBrainTurnID,
            response: RealtimeBrainResponseID
        ) -> RealtimeBrainEventIdentity {
            RealtimeBrainEventIdentity(
                session: session,
                turnID: turn,
                responseID: response,
                contextRevision: 1
            )
        }
        func audio(
            eventSequence: UInt64,
            audioSequence: UInt64,
            turn: RealtimeBrainTurnID,
            response: RealtimeBrainResponseID
        ) -> RealtimeResidentBrainEvent {
            RealtimeResidentBrainEvent(
                identity: identity(turn: turn, response: response),
                sequence: eventSequence,
                kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                    sequence: audioSequence,
                    timestampNanoseconds: audioSequence * 20_000_000,
                    format: format,
                    provenance: .providerGenerated,
                    bytes: Data(repeating: 1, count: 960)
                ))
            )
        }
        let events = [
            audio(
                eventSequence: 1,
                audioSequence: 1,
                turn: firstTurn,
                response: firstResponse
            ),
            RealtimeResidentBrainEvent(
                identity: identity(
                    turn: firstTurn,
                    response: firstResponse
                ),
                sequence: 2,
                kind: .residentSpeakingStopped
            ),
            audio(
                eventSequence: 3,
                audioSequence: 99,
                turn: firstTurn,
                response: firstResponse
            ),
            audio(
                eventSequence: 4,
                audioSequence: 2,
                turn: secondTurn,
                response: secondResponse
            ),
            RealtimeResidentBrainEvent(
                identity: identity(
                    turn: secondTurn,
                    response: secondResponse
                ),
                sequence: 5,
                kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                    canonicalText: "second"
                ))
            )
        ]
        let source = R7DispositionSource(events.map {
            RealtimeBrainEventDisposition.accepted($0)
        })
        let sink = R7EventSink()
        let bridge = MacSpeechRealtimeBrainOutputBridge(
            receiveEvent: { _ in await source.next() },
            consumeEvent: { event in await sink.consume(event) }
        )
        _ = await bridge.start(session: session)
        await waitUntil(label: "audio-done output settlement") {
            await bridge.currentSnapshot().state == .stopped
        }
        let consumed = await sink.recordedEvents()
        let consumedAudioSequences = consumed.compactMap { event -> UInt64? in
            if case .residentAudioDelta(let audio) = event.kind {
                return audio.sequence
            }
            return nil
        }
        expect(
            consumedAudioSequences == [1, 2],
            "audio done rejects late PCM but allows a response without a prior semantic final"
        )
        expect(
            !consumed.contains {
                if case .residentAudioDelta(let audio) = $0.kind {
                    return audio.sequence == 99
                }
                return false
            },
            "late same-response PCM never reaches the Host consumer"
        )
        expect(
            consumed.contains {
                if case .residentSpeakingStopped = $0.kind { return true }
                return false
            },
            "provider audio done remains distinct and observable"
        )
        expect(
            consumed.contains {
                if case .residentSemanticFinal = $0.kind { return true }
                return false
            },
            "semantic final remains distinct from audio completion"
        )
        let snapshot = await bridge.currentSnapshot()
        expect(snapshot.audioChunkCount == 2, "only playable chunks are counted")
        expect(
            snapshot.completedResponseCount == 1,
            "audio stream completion is counted independently"
        )
        expect(
            snapshot.rejectedEventCount == 2,
            "late audio and terminal close are deterministically rejected"
        )
    }

    private static func testOutputStopFromConsumerDoesNotDeadlock() async {
        cases += 1
        let session = RealtimeBrainSessionIdentity(
            residentID: "test-resident",
            runtimeSessionID: "test-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let event = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: nil,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .sessionReady
        )
        let source = R7DispositionSource([.accepted(event)])
        let sink = R7EventSink()
        let holder = R7OutputBridgeHolder()
        let bridge = MacSpeechRealtimeBrainOutputBridge(
            receiveEvent: { _ in await source.next() },
            consumeEvent: { event in
                await sink.consume(event)
                guard let bridge = holder.bridge else {
                    fatalError("FAILED: output bridge holder is empty")
                }
                _ = await bridge.stop(expectedSession: session)
            }
        )
        holder.bridge = bridge
        _ = await bridge.start(session: session)
        await waitUntil(label: "consumer-triggered output stop") {
            let hasActiveReceiveLoop = await bridge.currentSnapshot()
                .hasActiveReceiveLoop
            let eventCount = await sink.recordedEvents().count
            return !hasActiveReceiveLoop && eventCount == 1
        }
        let snapshot = await bridge.currentSnapshot()
        expect(snapshot.state == .stopped, "consumer-triggered stop settles")
        expect(
            !snapshot.hasActiveReceiveLoop,
            "output stop never waits on its own receive task"
        )
        expect(
            (await sink.recordedEvents()) == [event],
            "the claimed event is consumed exactly once before stop"
        )
    }

    private static func testFormalRuntimeRouteRemainsActiveForTwoTurns(
        fixture: Data
    ) async {
        cases += 1
        let provider = FakeRealtimeResidentBrainProvider()
        let router = ProviderRouter(
            credentialReader: R7CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "fixed resident loads")
        let startResult = await runtime.startRealtimeResidentBrainSession()
        guard case .success(let session) = startResult else {
            fatalError("FAILED: formal Realtime session did not start")
        }
        expect(await provider.openCount() == 1, "provider session opens once")
        expect(
            runtime.activeBrainLeaseForTesting()?.route
                == .realtimeResidentBrain,
            "Realtime route owns the single active Brain lease"
        )

        let captureGeneration: UInt64 = 700
        let source = FakeMacSpeechAudioFrameSource()
        source.setActiveGeneration(captureGeneration)
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )
        let input = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                await runtime.appendRealtimeResidentBrainAudio(frame)
            },
            stopInput: { binding in
                await runtime.closeRealtimeResidentBrainSession(
                    identity: binding.session
                )
            }
        )
        let sink = R7EventSink()
        let output = MacSpeechRealtimeBrainOutputBridge(
            receiveEvent: { session in
                do {
                    let disposition = try await runtime
                        .receiveRealtimeResidentBrainEvent(
                            session: session
                        )
                    await sink.observe(disposition)
                    return .success(disposition)
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.transportFailure)
                }
            },
            consumeEvent: { event in
                await sink.consume(event)
            }
        )

        _ = await input.start(binding: binding)
        _ = await output.start(session: session)
        let inputPCM = Data(repeating: 0, count: 960)
        source.appendFrame(
            pcm16Bytes: inputPCM,
            generation: captureGeneration,
            sequenceNumber: 10
        )
        source.appendFrame(
            pcm16Bytes: inputPCM,
            generation: captureGeneration,
            sequenceNumber: 12
        )
        await waitUntil(label: "formal input frames") {
            await provider.audioCount() == 2
        }
        let submitted = await provider.recordedAudioFrames()
        expect(
            submitted.map(\.sequence) == [1, 2],
            "capture gaps are projected to a contiguous submitted sequence"
        )
        expect(
            submitted.allSatisfy {
                $0.identity == session
                    && $0.provenance == .acousticEchoProcessed
            },
            "every input frame keeps the active lease identity and AEC provenance"
        )

        await enqueueTurn(
            provider: provider,
            session: session,
            turnIndex: 1,
            firstEventSequence: 1,
            audioSequence: 1,
            contextRevision: 1,
            includesSessionReady: true
        )
        await waitUntil(label: "first formal turn") {
            let counts = await sink.counts()
            return counts.audio == 1
                && counts.speakingStopped == 1
                && counts.semanticFinal == 1
        }
        let afterFirstTurn = await output.currentSnapshot()
        expect(
            afterFirstTurn.hasActiveReceiveLoop,
            "response completion returns to the same active receive loop"
        )
        expect(await provider.closeCount() == 0, "turn one does not close provider")
        expect(
            runtime.activeBrainLeaseForTesting()?.brainLeaseID
                == session.brainLeaseID,
            "turn one does not release or reacquire the Brain lease"
        )

        source.appendFrame(
            pcm16Bytes: inputPCM,
            generation: captureGeneration,
            sequenceNumber: 20
        )
        await waitUntil(label: "second-turn input frame") {
            await input.currentSnapshot().forwardedFrameCount == 3
        }
        let secondTurnContextRevision = await provider
            .latestContextRevision()
        expect(
            secondTurnContextRevision > 1,
            "Runtime refreshes context without replacing the Speech Session"
        )
        await enqueueTurn(
            provider: provider,
            session: session,
            turnIndex: 2,
            firstEventSequence: 6,
            audioSequence: 2,
            contextRevision: secondTurnContextRevision,
            includesSessionReady: false
        )
        await waitUntil(label: "second formal turn") {
            let counts = await sink.counts()
            return counts.audio == 2
                && counts.speakingStopped == 2
                && counts.semanticFinal == 2
        }
        let afterSecondTurn = await output.currentSnapshot()
        let activeCapture = await source.isCaptureGenerationActive(
            captureGeneration
        )
        expect(afterSecondTurn.hasActiveReceiveLoop, "turn two remains listening")
        expect(activeCapture, "capture remains active across both turns")
        expect(await provider.openCount() == 1, "two turns reuse one Provider session")
        expect(await provider.closeCount() == 0, "two turns do not settle the session")
        let dispositions = await sink.recordedDispositions()
        expect(
            dispositions.allSatisfy {
                if case .accepted = $0 { return true }
                return false
            },
            "both turns cross the Runtime identity fence without rejection"
        )

        _ = await input.stop()
        _ = await output.stop()
        await waitUntil(label: "formal session close") {
            await provider.closeCount() == 1
        }
        expect(runtime.activeBrainLeaseForTesting() == nil, "user stop releases the lease")
        let stoppedInput = await input.currentSnapshot()
        let stoppedOutput = await output.currentSnapshot()
        expect(
            !stoppedInput.hasActivePump
                && !stoppedOutput.hasActiveReceiveLoop,
            "user stop releases both Host pumps"
        )
    }

    private static func testListeningActivityRevalidatesAfterProviderAppend()
        async {
        cases += 1
        let source = FakeMacSpeechAudioFrameSource()
        let heldSend = R7HeldAudioSend()
        let confirmations = R7LocalActivityConfirmationRecorder()
        let session = RealtimeBrainSessionIdentity(
            residentID: "listening-fence-resident",
            runtimeSessionID: "listening-fence-session",
            brainLeaseID: UUID(),
            routeEpoch: 1,
            generation: 1
        )
        let captureGeneration: UInt64 = 725
        let captureTimestamp = DispatchTime.now().uptimeNanoseconds
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(listeningSnapshot(
            generation: captureGeneration,
            timestampNanoseconds: captureTimestamp
        ))
        let bridge = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrameWithActivity: { frame, _ in
                await heldSend.send(frame)
            },
            confirmAcceptedLocalActivity: { _, _ in
                await confirmations.confirm()
            },
            stopInput: { _ in .success(()) }
        )
        _ = await bridge.start(binding: MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        ))
        source.appendListeningNearEndFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            timestampNanoseconds: captureTimestamp
        )
        await heldSend.waitUntilStarted()
        source.setResidentSnapshot(nil)
        await heldSend.resume(.success(()))
        await waitUntil(label: "Listening post-append lifecycle fence") {
            await bridge.currentSnapshot().forwardedFrameCount == 1
        }
        expect(await confirmations.count() == 0,
               "Listening activity is not committed after Host lifecycle loss")
        _ = await bridge.stop()
    }

    private static func testFormalNoneActivityAppendDoesNotAwaitMainActor(
        fixture: Data
    ) async {
        cases += 1
        let provider = FakeRealtimeResidentBrainProvider()
        let router = ProviderRouter(
            credentialReader: R7CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "none-activity fast-path resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("FAILED: none-activity fast-path session did not start")
        }
        let frame = RealtimeBrainAudioFrame(
            identity: session,
            sequence: 1,
            timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: Data(repeating: 0, count: 960)
        )
        let runtimeBox = R7RuntimeBox(runtime)
        let resultBox = R7AppendResultBox()
        let mainActorOccupied = DispatchSemaphore(value: 0)
        let releaseMainActor = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0)
        let outcome = await Task.detached {
            let mainActorBlocker = Task { @MainActor in
                mainActorOccupied.signal()
                _ = resultBox.waitForSignal(
                    releaseMainActor,
                    timeout: .now() + 2
                )
            }
            let occupied = resultBox.waitForSignal(
                mainActorOccupied,
                timeout: .now() + 1
            )
            let appendTask = Task.detached {
                let result = await runtimeBox.runtime
                    .appendRealtimeResidentBrainAudio(
                        frame,
                        activity: .none
                    )
                resultBox.store(result)
                completed.signal()
            }
            let finished = resultBox.waitForSignal(
                completed,
                timeout: .now() + 1
            )
            releaseMainActor.signal()
            await mainActorBlocker.value
            await appendTask.value
            return (occupied, finished)
        }.value
        expect(outcome.0, "none-activity test occupies MainActor")
        expect(outcome.1,
               "none-activity PCM append does not wait on MainActor")
        if case .success? = resultBox.result() {
            expect(true, "none-activity fast-path append succeeds")
        } else {
            expect(false, "none-activity fast-path append succeeds")
        }
        expect(await provider.audioCount() == 1,
               "none-activity fast-path reaches Provider exactly once")
        let completion = runtime.realtimeUtteranceCompletionDebugSnapshot()
        expect(completion.phase == .idle
                && completion.pendingStartTurnID == nil
                && completion.completionCandidateCount == 0,
               "none-activity fast-path does not mutate turn completion")
        _ = await runtime.closeRealtimeResidentBrainSession(
            identity: session
        )
    }

    private static func listeningSnapshot(
        generation: UInt64,
        timestampNanoseconds: UInt64
    ) -> MacSpeechResidentAcousticSnapshot {
        MacSpeechResidentAcousticSnapshot(
            captureGeneration: generation,
            captureFrameIndex: 1,
            captureHostTimeNanoseconds: timestampNanoseconds,
            playbackSequence: 0,
            residentPlaybackActive: false,
            lastAudibleResidentRenderTimestampNanoseconds: nil,
            renderReferenceAvailable: false,
            renderReferenceRMS: nil,
            renderHostTimeNanoseconds: nil,
            rawCaptureRMS: 0.18,
            processedCaptureRMS: 0.18,
            linearAECOutputRMS: 0.18,
            renderCaptureCorrelation: 0,
            residualRenderCorrelation: 0,
            linearRenderCorrelation: 0,
            inputClassification: .nearEndSpeech,
            sourceGateOpen: false,
            sourceGateEpoch: 0,
            aecEnabled: true,
            aecActive: true,
            renderCaptureIsolationEstablished: false,
            sourceAlignmentLocked: false,
            sourceAlignmentDelayMilliseconds: nil,
            estimatedDelayMilliseconds: 80,
            erlDecibels: 0,
            erleDecibels: 0,
            renderCaptureSkewFrames: 0,
            driftTrend: "stable",
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
    }

    private static func testFormalNormalListeningSpeechAdmission(
        fixture: Data
    ) async {
        cases += 1
        let provider = FakeRealtimeResidentBrainProvider()
        let router = ProviderRouter(
            credentialReader: R7CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "normal Listening regression resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("FAILED: normal Listening session did not start")
        }
        let captureGeneration: UInt64 = 750
        let captureTimestamp = DispatchTime.now().uptimeNanoseconds
        let source = FakeMacSpeechAudioFrameSource()
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(listeningSnapshot(
            generation: captureGeneration,
            timestampNanoseconds: captureTimestamp
        ))
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )
        let input = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrameWithActivity: { frame, activity in
                await runtime.appendRealtimeResidentBrainAudio(
                    frame,
                    activity: activity.localActivity
                )
            },
            confirmAcceptedLocalActivity: { frame, activity in
                await runtime
                    .confirmRealtimeResidentBrainAcceptedLocalAudioActivity(
                        frame: frame,
                        activity: activity.localActivity
                    )
            },
            stopInput: { binding in
                await runtime.closeRealtimeResidentBrainSession(
                    identity: binding.session
                )
            }
        )
        let sink = R7EventSink()
        let output = MacSpeechRealtimeBrainOutputBridge(
            receiveEvent: { session in
                do {
                    let disposition = try await runtime
                        .receiveRealtimeResidentBrainEvent(session: session)
                    await sink.observe(disposition)
                    return .success(disposition)
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.transportFailure)
                }
            },
            consumeEvent: { event in await sink.consume(event) }
        )
        _ = await input.start(binding: binding)
        _ = await output.start(session: session)
        source.appendListeningNearEndFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration,
            timestampNanoseconds: captureTimestamp
        )
        await waitUntil(label: "normal Listening accepted PCM") {
            await provider.audioCount() == 1
        }
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: nil,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .sessionReady
        ))
        let turnID = RealtimeBrainTurnID()
        let identity = RealtimeBrainEventIdentity(
            session: session,
            turnID: turnID,
            responseID: nil,
            contextRevision: 1
        )
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: identity,
            sequence: 2,
            kind: .userSpeechStarted
        ))
        await waitUntil(label: "normal Listening speaking admission") {
            await MainActor.run {
                let snapshot = runtime
                    .realtimeUtteranceCompletionDebugSnapshot()
                return snapshot.phase == .speaking
                    && snapshot.turnID == turnID
            }
        }
        expect(runtime.realtimeUtteranceCompletionDebugSnapshot().phase
                == .speaking,
               "R7 formal route admits normal Listening speech activity")
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: identity,
            sequence: 3,
            kind: .userSpeechStopped
        ))
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: identity,
            sequence: 4,
            kind: .userTranscriptPartial("normal Listening turn")
        ))
        await waitUntil(label: "normal Listening completion candidate") {
            await MainActor.run {
                runtime.realtimeUtteranceCompletionDebugSnapshot()
                    .completionCandidateCount == 1
            }
        }
        let completion = runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(completion.phase == .completionCandidate
                && completion.session == session
                && completion.turnID == turnID,
               "R7 formal Listening start-stop-partial reaches one candidate")
        expect(runtime
                .realtimeUtteranceCompletionTracksTranscriptFinalForTesting(
                    identity
                ),
               "R7 normal Listening turn identity stays tracked")
        _ = await input.stop()
        _ = await output.stop()
        await waitUntil(label: "normal Listening session close") {
            await provider.closeCount() == 1
        }
    }

    private static func testAdmittedSpeechFinalWithoutStopFailsClosed(
        fixture: Data
    ) async {
        cases += 1
        let provider = FakeRealtimeResidentBrainProvider()
        let router = ProviderRouter(
            credentialReader: R7CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "missing-stop admitted resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("FAILED: missing-stop admitted session did not start")
        }
        let timestamp = DispatchTime.now().uptimeNanoseconds
        let frame = RealtimeBrainAudioFrame(
            identity: session,
            sequence: 1,
            timestampNanoseconds: timestamp,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: Data(repeating: 1, count: 960)
        )
        let listening = RealtimeBrainLocalAudioActivity(
            kind: .listeningNearEnd,
            residentPlaybackSequence: 0,
            residentPlaybackActive: false,
            lastAudibleResidentRenderTimestampNanoseconds: nil,
            sourceGateEpoch: 0,
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
        let appendResult = await runtime.appendRealtimeResidentBrainAudio(
                frame,
                activity: listening
            )
        if case .success = appendResult {
            expect(true, "missing-stop admitted PCM append")
        } else {
            expect(false, "missing-stop admitted PCM append")
        }
        let confirmation = await runtime
            .confirmRealtimeResidentBrainAcceptedLocalAudioActivity(
                frame: frame,
                activity: listening
            )
        if case .success = confirmation {
            expect(true, "missing-stop listening confirmation")
        } else {
            expect(false, "missing-stop listening confirmation")
        }
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: nil,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .sessionReady
        ))
        _ = try? await runtime.receiveRealtimeResidentBrainEvent(
            session: session
        )
        let turnID = RealtimeBrainTurnID()
        let identity = RealtimeBrainEventIdentity(
            session: session,
            turnID: turnID,
            responseID: nil,
            contextRevision: 1
        )
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: identity,
            sequence: 2,
            kind: .userSpeechStarted
        ))
        _ = try? await runtime.receiveRealtimeResidentBrainEvent(
            session: session
        )
        expect(runtime.realtimeUtteranceCompletionDebugSnapshot().phase
                == .speaking,
               "missing-stop fixture reaches speaking")
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: identity,
            sequence: 3,
            kind: .userTranscriptFinal("缺少 speech stopped")
        ))
        let finalDisposition = try? await runtime
            .receiveRealtimeResidentBrainEvent(session: session)
        if case .some(.accepted) = finalDisposition {
            expect(true,
                   "admitted final allows bounded final-before-stop ordering")
        } else {
            expect(false,
                   "admitted final allows bounded final-before-stop ordering")
        }
        try? await Task.sleep(for: .milliseconds(1_120))
        let completion = runtime
            .realtimeUtteranceCompletionDebugSnapshot()
        expect(completion.phase == .idle
                && completion.pendingStartTurnID == nil,
               "admitted final without stop expires without a completion")
        expect(await provider.responseCreateCount() == 0,
               "admitted final without stop cannot create response")
        _ = await runtime.closeRealtimeResidentBrainSession(
            identity: session
        )
    }

    private static func testFormalProviderSpeechRequiresBoundedLocalPCM(
        fixture: Data
    ) async {
        cases += 1
        let provider = FakeRealtimeResidentBrainProvider()
        let router = ProviderRouter(
            credentialReader: R7CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "provider speech admission resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("FAILED: provider speech admission session did not start")
        }
        let captureGeneration: UInt64 = 775
        let source = FakeMacSpeechAudioFrameSource()
        source.setActiveGeneration(captureGeneration)
        source.setResidentSnapshot(listeningSnapshot(
            generation: captureGeneration,
            timestampNanoseconds: DispatchTime.now().uptimeNanoseconds
        ))
        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )
        let input = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrameWithActivity: { frame, activity in
                await runtime.appendRealtimeResidentBrainAudio(
                    frame,
                    activity: activity.localActivity
                )
            },
            confirmAcceptedLocalActivity: { frame, activity in
                await runtime
                    .confirmRealtimeResidentBrainAcceptedLocalAudioActivity(
                        frame: frame,
                        activity: activity.localActivity
                    )
            },
            stopInput: { binding in
                await runtime.closeRealtimeResidentBrainSession(
                    identity: binding.session
                )
            }
        )
        let output = MacSpeechRealtimeBrainOutputBridge(
            receiveEvent: { session in
                do {
                    return .success(
                        try await runtime.receiveRealtimeResidentBrainEvent(
                            session: session
                        )
                    )
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.transportFailure)
                }
            },
            consumeEvent: { _ in }
        )
        _ = await input.start(binding: binding)
        _ = await output.start(session: session)

        let pcm = Data(repeating: 1, count: 960)
        let captureBase = DispatchTime.now().uptimeNanoseconds
            - 100_000_000
        source.appendRouteStableNoneFrame(
            pcm16Bytes: pcm,
            generation: captureGeneration,
            timestampNanoseconds: captureBase
        )
        await waitUntil(label: "provider speech baseline PCM") {
            await provider.audioCount() == 1
        }
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: nil,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .sessionReady
        ))
        let firstTurnID = RealtimeBrainTurnID()
        let firstIdentity = RealtimeBrainEventIdentity(
            session: session,
            turnID: firstTurnID,
            responseID: nil,
            contextRevision: 1
        )
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: firstIdentity,
            sequence: 2,
            kind: .userSpeechStarted
        ))
        await waitUntil(label: "provider speech waits for local PCM") {
            await MainActor.run {
                let snapshot = runtime
                    .realtimeUtteranceCompletionDebugSnapshot()
                return snapshot.phase == .idle
                    && snapshot.pendingStartTurnID == firstTurnID
            }
        }
        for frameOffset in UInt64(1) ... 3 {
            source.appendRouteStableNoneFrame(
                pcm16Bytes: pcm,
                generation: captureGeneration,
                timestampNanoseconds:
                    captureBase + frameOffset * 20_000_000
            )
        }
        await waitUntil(label: "provider speech bounded local PCM") {
            await provider.audioCount() == 4
        }
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: firstIdentity,
            sequence: 3,
            kind: .userSpeechStopped
        ))
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: firstIdentity,
            sequence: 4,
            kind: .userTranscriptFinal("真实有线麦克风第一段")
        ))
        expect(await provider.responseCreateCount() == 0,
               "provider speech final does not bypass the completion window")
        await waitUntil(label: "provider speech first pause candidate") {
            await MainActor.run {
                runtime.realtimeUtteranceCompletionDebugSnapshot().phase
                    == .candidatePause
            }
        }

        let secondTurnID = RealtimeBrainTurnID()
        let secondIdentity = RealtimeBrainEventIdentity(
            session: session,
            turnID: secondTurnID,
            responseID: nil,
            contextRevision: 1
        )
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: secondIdentity,
            sequence: 5,
            kind: .userSpeechStarted
        ))
        for frameOffset in UInt64(4) ... 6 {
            source.appendRouteStableNoneFrame(
                pcm16Bytes: pcm,
                generation: captureGeneration,
                timestampNanoseconds:
                    captureBase + frameOffset * 20_000_000
            )
        }
        await waitUntil(label: "provider speech resumed local PCM") {
            await provider.audioCount() == 7
        }
        try? await Task.sleep(for: .milliseconds(450))
        expect(await provider.responseCreateCount() == 0,
               "Provider-backed short pause does not respond early")
        expect(runtime.realtimeUtteranceCompletionDebugSnapshot().phase
                == .speaking,
               "Provider-backed short pause resumes the same utterance")

        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: secondIdentity,
            sequence: 6,
            kind: .userSpeechStopped
        ))
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: secondIdentity,
            sequence: 7,
            kind: .userTranscriptFinal("真实有线麦克风第二段")
        ))
        await waitUntil(label: "provider speech second pause candidate") {
            await MainActor.run {
                runtime.realtimeUtteranceCompletionDebugSnapshot().phase
                    == .candidatePause
            }
        }
        for frameOffset in UInt64(7) ... 12 {
            source.appendRouteStableNoneFrame(
                pcm16Bytes: pcm,
                generation: captureGeneration,
                timestampNanoseconds:
                    captureBase + frameOffset * 20_000_000
            )
        }
        await waitUntil(label: "provider speech near-window pause PCM") {
            await provider.audioCount() == 13
        }
        try? await Task.sleep(for: .milliseconds(320))

        let thirdTurnID = RealtimeBrainTurnID()
        let thirdIdentity = RealtimeBrainEventIdentity(
            session: session,
            turnID: thirdTurnID,
            responseID: nil,
            contextRevision: 1
        )
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: thirdIdentity,
            sequence: 8,
            kind: .userSpeechStarted
        ))
        await waitUntil(label: "provider speech near-window resume") {
            await MainActor.run {
                runtime.realtimeUtteranceCompletionDebugSnapshot().phase
                    == .speaking
            }
        }
        try? await Task.sleep(for: .milliseconds(120))
        expect(await provider.responseCreateCount() == 0,
               "near-window Provider resume cancels the old completion")
        for frameOffset in UInt64(13) ... 15 {
            source.appendRouteStableNoneFrame(
                pcm16Bytes: pcm,
                generation: captureGeneration,
                timestampNanoseconds:
                    captureBase + frameOffset * 20_000_000
            )
        }
        await waitUntil(label: "provider speech third segment PCM") {
            await provider.audioCount() == 16
        }
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: thirdIdentity,
            sequence: 9,
            kind: .userSpeechStopped
        ))
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: thirdIdentity,
            sequence: 10,
            kind: .userTranscriptFinal("真实有线麦克风第三段")
        ))
        await waitUntil(
            label: "provider speech exactly-one response",
            attempts: 150
        ) {
            await provider.responseCreateCount() == 1
        }
        expect(await provider.responseCreateCount() == 1,
               "Provider VAD plus advancing local PCM authorizes one response")
        expect(runtime.realtimeUtteranceCompletionDebugSnapshot().phase
                == .idle,
               "completed provider speech turn returns Runtime to idle")

        _ = await input.stop()
        _ = await output.stop()
        await waitUntil(label: "provider speech admission session close") {
            await provider.closeCount() == 1
        }
    }

    private static func testProviderSpeechIntervalFailsClosedForPlaybackAndTail(
        fixture: Data
    ) async {
        let negativeCases: [(
            label: String,
            startPlaybackActive: Bool,
            startTailAgeNanoseconds: UInt64?,
            startPlaybackSequence: UInt64,
            endPlaybackActive: Bool,
            endTailAgeNanoseconds: UInt64?,
            endPlaybackSequence: UInt64,
            emitsSpeechStopped: Bool
        )] = [
            ("resident playback", true, nil, 1, true, nil, 1, true),
            ("500 ms residual tail", false, 100_000_000, 1,
             false, 100_000_000, 1, true),
            ("playback start then post-tail stop", true, nil, 1,
             false, 600_000_000, 2, true),
            ("missing Provider speech stop", false, nil, 0,
             false, nil, 0, false)
        ]
        for fixtureCase in negativeCases {
            let label = fixtureCase.label
            cases += 1
            let provider = FakeRealtimeResidentBrainProvider()
            let router = ProviderRouter(
                credentialReader: R7CredentialReader(),
                realtimeResidentBrainProvider: provider
            )
            let runtime = RuntimeCore(
                executionEngine: ExecutionEngine(providerRouter: router),
                providerRouter: router,
                sessionStore: SessionStore()
            )
            expect(runtime.loadDR(from: fixture).isLoaded,
                   "\(label) negative resident loads")
            guard case .success(let session) =
                    await runtime.startRealtimeResidentBrainSession() else {
                fatalError("FAILED: \(label) negative session did not start")
            }
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(
                    session: session,
                    turnID: nil,
                    responseID: nil,
                    contextRevision: 1
                ),
                sequence: 1,
                kind: .sessionReady
            ))
            _ = try? await runtime.receiveRealtimeResidentBrainEvent(
                session: session
            )

            let captureBase = DispatchTime.now().uptimeNanoseconds
                - 200_000_000
            func appendFrame(
                sequence: UInt64,
                timestamp: UInt64,
                playbackActive: Bool,
                tailAgeNanoseconds: UInt64?,
                playbackSequence: UInt64
            ) async {
                let lastAudible = tailAgeNanoseconds.map {
                    timestamp - $0
                }
                let result = await runtime.appendRealtimeResidentBrainAudio(
                    RealtimeBrainAudioFrame(
                        identity: session,
                        sequence: sequence,
                        timestampNanoseconds: timestamp,
                        format: RealtimeBrainAudioFormat(
                            encoding: .pcm16LittleEndian,
                            sampleRate: 24_000,
                            channelCount: 1
                        ),
                        provenance: .acousticEchoProcessed,
                        bytes: Data(repeating: 1, count: 960)
                    ),
                    activity: RealtimeBrainLocalAudioActivity(
                        kind: .none,
                        residentPlaybackSequence: playbackSequence,
                        residentPlaybackActive: playbackActive,
                        lastAudibleResidentRenderTimestampNanoseconds:
                            lastAudible,
                        sourceGateEpoch: 0,
                        routeStable: true,
                        inputDeviceAvailable: true,
                        outputDeviceAvailable: true
                    )
                )
                if case .success = result {
                    expect(true, "\(label) local PCM reaches Runtime")
                } else {
                    expect(false, "\(label) local PCM reaches Runtime")
                }
            }

            await appendFrame(
                sequence: 1,
                timestamp: captureBase,
                playbackActive: fixtureCase.startPlaybackActive,
                tailAgeNanoseconds:
                    fixtureCase.startTailAgeNanoseconds,
                playbackSequence: fixtureCase.startPlaybackSequence
            )
            let turnID = RealtimeBrainTurnID()
            let identity = RealtimeBrainEventIdentity(
                session: session,
                turnID: turnID,
                responseID: nil,
                contextRevision: 1
            )
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: 2,
                kind: .userSpeechStarted
            ))
            _ = try? await runtime.receiveRealtimeResidentBrainEvent(
                session: session
            )
            for sequence in 2 ... 4 {
                await appendFrame(
                    sequence: UInt64(sequence),
                    timestamp: captureBase
                        + UInt64(sequence - 1) * 20_000_000,
                    playbackActive: fixtureCase.endPlaybackActive,
                    tailAgeNanoseconds:
                        fixtureCase.endTailAgeNanoseconds,
                    playbackSequence: fixtureCase.endPlaybackSequence
                )
            }
            if fixtureCase.emitsSpeechStopped {
                await provider.enqueue(RealtimeResidentBrainEvent(
                    identity: identity,
                    sequence: 3,
                    kind: .userSpeechStopped
                ))
                _ = try? await runtime.receiveRealtimeResidentBrainEvent(
                    session: session
                )
            }
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: fixtureCase.emitsSpeechStopped ? 4 : 3,
                kind: .userTranscriptFinal("negative \(label)")
            ))
            let finalDisposition = try? await runtime
                .receiveRealtimeResidentBrainEvent(session: session)
            if fixtureCase.emitsSpeechStopped {
                expect(finalDisposition == .rejectedStale,
                       "\(label) final fails closed without admission")
            } else {
                if case .some(.accepted) = finalDisposition {
                    expect(true,
                           "\(label) permits only the bounded missing-stop window")
                } else {
                    expect(false,
                           "\(label) permits only the bounded missing-stop window")
                }
                try? await Task.sleep(for: .milliseconds(1_120))
            }
            expect(await provider.responseCreateCount() == 0,
                   "\(label) cannot authorize response.create")
            let completion = runtime
                .realtimeUtteranceCompletionDebugSnapshot()
            expect(completion.phase == .idle
                    && completion.pendingStartTurnID == nil,
                   "\(label) cannot leave Runtime stuck Thinking")
            _ = await runtime.closeRealtimeResidentBrainSession(
                identity: session
            )
        }
    }

    private static func testGenerationTransitionRebindsHost(
        fixture: Data
    ) async {
        cases += 1
        let provider = FakeRealtimeResidentBrainProvider()
        let router = ProviderRouter(
            credentialReader: R7CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "transition resident loads")
        guard case .success(let firstSession) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("FAILED: transition Realtime session did not start")
        }
        let captureGeneration: UInt64 = 800
        let source = FakeMacSpeechAudioFrameSource()
        source.setActiveGeneration(captureGeneration)
        let input = MacSpeechRealtimeBrainInputBridge(
            source: source,
            sendFrame: { frame in
                await runtime.appendRealtimeResidentBrainAudio(frame)
            },
            stopInput: { binding in
                await runtime.closeRealtimeResidentBrainSession(
                    identity: binding.session
                )
            }
        )
        let sink = R7EventSink()
        let output = MacSpeechRealtimeBrainOutputBridge(
            receiveEvent: { session in
                do {
                    return .success(
                        try await runtime.receiveRealtimeResidentBrainEvent(
                            session: session
                        )
                    )
                } catch let error as RealtimeResidentBrainError {
                    return .failure(error)
                } catch {
                    return .failure(.transportFailure)
                }
            },
            consumeEvent: { event in await sink.consume(event) }
        )
        let firstBinding = MacSpeechRealtimeBrainInputBinding(
            session: firstSession,
            captureGeneration: captureGeneration
        )
        _ = await input.start(binding: firstBinding)
        _ = await output.start(session: firstSession)
        source.appendFrame(
            pcm16Bytes: Data(repeating: 1, count: 960),
            generation: captureGeneration
        )
        await waitUntil(label: "pre-transition input") {
            await provider.audioCount() == 1
        }

        let suspendedInput = await input.suspendForGenerationTransition(
            session: firstSession
        )
        let suspendedOutput = await output.suspendForGenerationTransition(
            session: firstSession
        )
        expect(!suspendedInput.hasActivePump, "generation transition fences old input")
        expect(
            !suspendedOutput.hasActiveReceiveLoop,
            "generation transition fences old output"
        )
        source.appendFrame(
            pcm16Bytes: Data(repeating: 9, count: 960),
            generation: captureGeneration,
            sequenceNumber: 50
        )
        guard case .success(let nextSession) =
                await runtime.cancelRealtimeResidentBrainGenerationForTesting(
                    identity: firstSession,
                    reason: .runtimeDecision
                ) else {
            fatalError("FAILED: Runtime generation transition failed")
        }
        expect(
            nextSession.brainLeaseID == firstSession.brainLeaseID
                && nextSession.routeEpoch == firstSession.routeEpoch
                && nextSession.residentID == firstSession.residentID
                && nextSession.runtimeSessionID
                    == firstSession.runtimeSessionID,
            "generation transition preserves the single Brain lease identity"
        )
        expect(
            nextSession.generation == firstSession.generation + 1,
            "Runtime alone advances the generation"
        )
        expect(await provider.openCount() == 1, "transition does not reopen Provider")
        expect(await provider.closeCount() == 0, "transition does not close Provider")
        expect(await provider.cancelCount() == 1, "Provider receives one cancel command")
        expect(
            await provider.lastCancelCommand()?.nextGeneration
                == nextSession.generation,
            "Provider receives the Runtime-issued next generation"
        )

        let reboundOutput = await output.resumeAfterGenerationTransition(
            session: nextSession
        )
        let reboundInput = await input.resumeAfterGenerationTransition(
            session: nextSession
        )
        expect(reboundOutput.hasActiveReceiveLoop, "new output generation resumes")
        expect(reboundInput.hasActivePump, "new input generation resumes")
        expect(source.discardedGenerationBoundaryCount() == 1,
               "generation transition discards pending pre-fence audio")

        let oldTurn = RealtimeBrainTurnID()
        let oldResponse = RealtimeBrainResponseID()
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: firstSession,
                turnID: oldTurn,
                responseID: oldResponse,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                sequence: 1,
                timestampNanoseconds: 0,
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 24_000,
                    channelCount: 1
                ),
                provenance: .providerGenerated,
                bytes: Data(repeating: 7, count: 960)
            ))
        ))
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: nextSession,
                turnID: nil,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .sessionReady
        ))
        await waitUntil(label: "post-transition session ready") {
            await sink.recordedEvents().contains {
                $0.identity.session == nextSession
                    && $0.kind == .sessionReady
            }
        }
        expect(
            !(await sink.recordedEvents()).contains {
                $0.identity.session == firstSession
            },
            "old generation output never reaches the Host consumer"
        )

        source.appendFrame(
            pcm16Bytes: Data(repeating: 2, count: 960),
            generation: captureGeneration,
            sequenceNumber: 51
        )
        await waitUntil(label: "post-transition input") {
            await provider.audioCount() == 2
        }
        let frames = await provider.recordedAudioFrames()
        expect(
            frames.map(\.identity) == [firstSession, nextSession],
            "submitted PCM switches exactly to the new Runtime identity"
        )
        expect(
            frames.map(\.sequence) == [1, 1],
            "submitted sequence restarts at one for the new generation"
        )
        expect(
            frames.last?.bytes == Data(repeating: 2, count: 960),
            "pre-transition buffered PCM is drained before rebind"
        )
        expect(
            runtime.activeBrainLeaseForTesting()?.brainLeaseID
                == firstSession.brainLeaseID,
            "the original Brain lease remains active after rebind"
        )

        let stopOutcome = await input.stop(expectedSession: nextSession)
        _ = await output.stop(expectedSession: nextSession)
        if case .success? = stopOutcome.closeResult {
            expect(true, "rebound session closes successfully")
        } else {
            expect(false, "rebound session closes successfully")
        }
        expect(await provider.closeCount() == 1, "user stop closes Provider once")
        expect(runtime.activeBrainLeaseForTesting() == nil, "user stop releases the lease")
    }

    private static func testRuntimeCloseFailureRetries(
        fixture: Data
    ) async {
        cases += 1
        let provider = FakeRealtimeResidentBrainProvider()
        let router = ProviderRouter(
            credentialReader: R7CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "close-retry resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("FAILED: close-retry session did not start")
        }
        await provider.failNextClose(.transportFailure)
        let firstClose = await runtime.closeRealtimeResidentBrainSession(
            identity: session
        )
        if case .failure(.transportFailure) = firstClose {
            expect(true, "first Runtime close reports Provider failure")
        } else {
            expect(false, "first Runtime close reports Provider failure")
        }
        expect(await provider.closeCount() == 1, "failed close reaches Provider once")
        expect(
            runtime.activeBrainLeaseForTesting()?.brainLeaseID
                == session.brainLeaseID,
            "failed close retains the settling Brain lease for retry"
        )
        let retry = await runtime.closeRealtimeResidentBrainSession(
            identity: session
        )
        if case .success = retry {
            expect(true, "same identity retries Runtime close")
        } else {
            expect(false, "same identity retries Runtime close")
        }
        expect(await provider.closeCount() == 2, "retry reaches Provider once more")
        expect(runtime.activeBrainLeaseForTesting() == nil, "retry releases the lease")
        let idempotent = await runtime.closeRealtimeResidentBrainSession(
            identity: session
        )
        if case .success = idempotent {
            expect(true, "closed session remains idempotent")
        } else {
            expect(false, "closed session remains idempotent")
        }
        expect(
            await provider.closeCount() == 2,
            "idempotent close does not reach Provider again"
        )
    }

    private static func enqueueTurn(
        provider: FakeRealtimeResidentBrainProvider,
        session: RealtimeBrainSessionIdentity,
        turnIndex: UInt64,
        firstEventSequence: UInt64,
        audioSequence: UInt64,
        contextRevision: UInt64,
        includesSessionReady: Bool
    ) async {
        var sequence = firstEventSequence
        if includesSessionReady {
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(
                    session: session,
                    turnID: nil,
                    responseID: nil,
                    contextRevision: contextRevision
                ),
                sequence: sequence,
                kind: .sessionReady
            ))
            sequence &+= 1
        }
        let turnID = RealtimeBrainTurnID()
        let responseID = RealtimeBrainResponseID()
        let userIdentity = RealtimeBrainEventIdentity(
            session: session,
            turnID: turnID,
            responseID: nil,
            contextRevision: contextRevision
        )
        let residentIdentity = RealtimeBrainEventIdentity(
            session: session,
            turnID: turnID,
            responseID: responseID,
            contextRevision: contextRevision
        )
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: userIdentity,
            sequence: sequence,
            kind: .userTranscriptFinal("turn \(turnIndex)")
        ))
        sequence &+= 1
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: sequence,
            kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                sequence: audioSequence,
                timestampNanoseconds: (audioSequence &- 1) * 20_000_000,
                format: RealtimeBrainAudioFormat(
                    encoding: .pcm16LittleEndian,
                    sampleRate: 24_000,
                    channelCount: 1
                ),
                provenance: .providerGenerated,
                bytes: Data(repeating: UInt8(turnIndex), count: 960)
            ))
        ))
        sequence &+= 1
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: sequence,
            kind: .residentSpeakingStopped
        ))
        sequence &+= 1
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: residentIdentity,
            sequence: sequence,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "resident turn \(turnIndex)"
            ))
        ))
    }

    private static func waitUntil(
        label: String = "asynchronous condition",
        attempts: Int = 100,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<attempts {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        fatalError("FAILED: \(label) timed out")
    }

    private static func expect(
        _ condition: Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        checks += 1
        if !condition {
            fatalError("FAILED: \(message) at \(file):\(line)")
        }
    }
}
#endif
