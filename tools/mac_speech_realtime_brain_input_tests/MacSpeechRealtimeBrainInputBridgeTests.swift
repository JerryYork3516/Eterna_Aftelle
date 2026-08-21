import Foundation

#if DEBUG
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
}

private actor FakeRealtimeResidentBrainProvider: RealtimeResidentBrainProvider {
    private var audioFrames: [RealtimeBrainAudioFrame] = []
    private var nextAudioError: RealtimeResidentBrainError?

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {}

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {}

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
    ) async throws {}

    func interrupt(_ command: RealtimeBrainInterruptCommand) async throws {}

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        throw RealtimeResidentBrainError.unavailable
    }

    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws {}

    func failNextAudio(_ error: RealtimeResidentBrainError) {
        nextAudioError = error
    }

    func audioCount() -> Int { audioFrames.count }

    func firstAudioFrame() -> RealtimeBrainAudioFrame? { audioFrames.first }
}

@main
private struct MacSpeechRealtimeBrainInputBridgeTests {
    private static var checks = 0
    private static var cases = 0

    static func main() async {
        await testBridgeForwardsFrames()
        await testBridgeStopsOnError()
        await testBridgeRejectsStaleFrames()
        await testBridgeSnapshot()
        await testAudioFrameConversion()

        print("mac_speech_realtime_brain_input_bridge_cases=5")
        print("mac_speech_realtime_brain_input_bridge_checks=20")
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
            stopInput: { _ in }
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
            stopInput: { _ in }
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
            stopInput: { _ in }
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
            stopInput: { _ in }
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

    private static func waitUntil(
        attempts: Int = 100,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<attempts {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        fatalError("FAILED: asynchronous condition timed out")
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
