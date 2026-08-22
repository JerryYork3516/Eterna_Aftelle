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

    func setActiveGeneration(_ generation: UInt64) {
        lock.withLock { activeGeneration = generation }
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
}

private actor FakeRealtimeResidentBrainProvider: RealtimeResidentBrainProvider {
    private var audioFrames: [RealtimeBrainAudioFrame] = []
    private var events: [RealtimeResidentBrainEvent] = []
    private var receiveContinuation:
        CheckedContinuation<RealtimeResidentBrainEvent, Error>?
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var contextUpdates: [RealtimeBrainRuntimeContextUpdate] = []
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
        await testBridgeSnapshot()
        await testAudioFrameConversion()
        await testStopFailsClosedAndRetries()
        await testOutputRejectsLateAudioAfterAudioDone()
        await testOutputStopFromConsumerDoesNotDeadlock()
        await testFormalRuntimeRouteRemainsActiveForTwoTurns(
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
            firstEventSequence: 8,
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
                await runtime.cancelRealtimeResidentBrainGeneration(
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
        for kind in [
            RealtimeResidentBrainEventKind.userSpeechStarted,
            .userSpeechStopped,
            .userTranscriptFinal("turn \(turnIndex)")
        ] {
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: userIdentity,
                sequence: sequence,
                kind: kind
            ))
            sequence &+= 1
        }
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
