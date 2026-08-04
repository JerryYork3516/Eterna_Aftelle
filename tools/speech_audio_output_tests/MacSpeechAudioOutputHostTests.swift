@preconcurrency import AVFoundation
import Foundation

@MainActor
@main
private struct MacSpeechAudioOutputHostTests {
    private static var checks = 0

    static func main() async {
        testFrozenProviderFormat()
        testPCMConversionToLocalFormat()
        testBoundedQueueOrderingAndValidation()
        await testPrepareAndDiagnostics()
        await testOrderedPlaybackAndCompletion()
        await testTemporaryQueueGapKeepsOnePlaybackCycle()
        await testShortResponseFlushesPrebuffer()
        await testUnderrunDoesNotStartPlayer()
        await testQueueFullStopsAndClears()
        await testConversionFailureStopsAndClears()
        await testConsumerTimeoutStopsAndClears()
        await testStopAndCloseAreIdempotent()
        await testGenerationRejectsLateInputAndCompletion()
        await testCloseCanReprepare()
        await testDefaultOutputChangeFailsAndCanRecover()
        await testUnavailableOutputFailsBeforePrepare()
        print("speech_audio_output_checks=\(checks)")
    }

    private static func testFrozenProviderFormat() {
        expect(MacSpeechPCMOutputFormat.sampleRate == 24_000, "24 kHz")
        expect(MacSpeechPCMOutputFormat.channelCount == 1, "mono")
        expect(MacSpeechPCMOutputFormat.bytesPerSample == 2, "PCM16")
        expect(
            MacSpeechPCMOutputFormat.description.contains("PCM16 LE"),
            "little-endian declaration"
        )
    }

    private static func testPCMConversionToLocalFormat() {
        guard let localFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ) else {
            fatalError("FAILED: construct local output format")
        }
        do {
            let converter = try MacSpeechPCMOutputConverter(
                localFormat: localFormat
            )
            let sampleCount = 240
            let pcm = Data(repeating: 0, count: sampleCount * 2)
            let output = try converter.convert(pcm16Bytes: pcm)
            expect(output.format.sampleRate == 48_000, "converted sample rate")
            expect(output.format.channelCount == 2, "converted channels")
            expect(output.format.commonFormat == .pcmFormatFloat32, "converted sample format")
            expect(!output.format.isInterleaved, "converted interleaving")
            expect(
                output.frameLength >= 430 && output.frameLength <= 480,
                "converted frame count \(output.frameLength)"
            )
            let nextOutput = try converter.convert(pcm16Bytes: pcm)
            expect(nextOutput.frameLength > 0, "streaming converter remains active")
        } catch {
            fatalError("FAILED: PCM output conversion \(error)")
        }
    }

    private static func testBoundedQueueOrderingAndValidation() {
        var buffer = MacSpeechPCMPlaybackBuffer(capacity: 2, generation: 4)
        try? buffer.enqueue(chunk(generation: 4, sequence: 1, byte: 1))
        try? buffer.enqueue(chunk(generation: 4, sequence: 2, byte: 2))
        expectThrows(.queueFull) {
            try buffer.enqueue(chunk(generation: 4, sequence: 3, byte: 3))
        }
        expect(buffer.count == 2, "queue stays bounded")
        expect(buffer.dequeue()?.sequence == 1, "first-in first-out 1")
        expect(buffer.dequeue()?.sequence == 2, "first-in first-out 2")
        expect(buffer.dequeue() == nil, "queue drains")

        expectThrows(.invalidPCMByteCount) {
            try buffer.enqueue(
                MacSpeechPCMPlaybackChunk(
                    generation: 4,
                    sequence: 3,
                    pcm16Bytes: Data([1])
                )
            )
        }
        expectThrows(.staleGeneration) {
            try buffer.enqueue(chunk(generation: 3, sequence: 3, byte: 3))
        }
        expectThrows(.outOfOrderSequence) {
            try buffer.enqueue(chunk(generation: 4, sequence: 2, byte: 2))
        }
    }

    private static func testPrepareAndDiagnostics() async {
        let (host, player) = makeHost()
        let prepared = await host.prepare()
        expect(prepared.state == .prepared, "prepared state")
        expect(prepared.generation == 1, "generation begins")
        expect(prepared.outputDevice.name == "Test Output", "default output")
        expect(prepared.providerFormat.contains("24000 Hz"), "provider format")
        expect(prepared.localFormat.contains("48000 Hz"), "local format")
        expect(player.prepareCount == 1, "player prepared once")
        let repeated = await host.prepare()
        expect(repeated.generation == prepared.generation, "prepare idempotent")
        expect(player.prepareCount == 1, "no duplicate prepare")
        expect(repeated.recentEvents.map(\.kind) == [.prepared], "prepared event")
    }

    private static func testOrderedPlaybackAndCompletion() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        let queued = await host.enqueue(
            pcm16Bytes: Data([2, 0]), sequence: 2, generation: generation
        )
        expect(queued.queueDepth == 2, "two queued chunks")
        let started = await host.start()
        expect(started.state == .playing, "playing with queued successor")
        expect(player.startCount == 1, "player started")
        expect(player.scheduledCount == 1, "first chunk scheduled")
        _ = await host.finishProviderResponse()
        player.completeScheduledChunk()
        await waitUntil { player.scheduledCount == 2 }
        expect(player.payloads == [Data([1, 0]), Data([2, 0])], "ordered scheduling")
        player.completeScheduledChunk()
        await waitUntil { await host.currentSnapshot().state == .completed }
        let completed = await host.currentSnapshot()
        expect(completed.playedChunkCount == 2, "played chunk count")
        expect(completed.playedByteCount == 4, "played byte count")
        expect(completed.queueDepth == 0, "queue exhausted")
        expect(completed.playbackStartedCount == 1, "playback start counted")
        expect(completed.playbackCompletedCount == 1, "playback completion counted")
        expect(
            completed.recentEvents.map(\.kind).contains(.playbackCompleted),
            "local completion event"
        )
    }

    private static func testTemporaryQueueGapKeepsOnePlaybackCycle() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        _ = await host.enqueue(
            pcm16Bytes: Data([2, 0]), sequence: 2, generation: generation
        )
        _ = await host.start()
        player.completeScheduledChunk()
        await waitUntil { player.scheduledCount == 2 }
        player.completeScheduledChunk()
        await waitUntil {
            let snapshot = await host.currentSnapshot()
            return snapshot.queueDepth == 0 && snapshot.state == .playing
        }
        let gap = await host.currentSnapshot()
        expect(gap.playbackCompletedCount == 0,
               "temporary queue gap is not response completion")
        _ = await host.enqueue(
            pcm16Bytes: Data([3, 0]), sequence: 3, generation: generation
        )
        await waitUntil { player.scheduledCount == 3 }
        expect(player.startCount == 1,
               "new audio continues the same player cycle")
        _ = await host.finishProviderResponse()
        player.completeScheduledChunk()
        await waitUntil { await host.currentSnapshot().state == .completed }
        let completed = await host.currentSnapshot()
        expect(completed.playbackStartedCount == 1,
               "response emits one playbackStarted")
        expect(completed.playbackCompletedCount == 1,
               "response emits one playbackCompleted")
    }

    private static func testShortResponseFlushesPrebuffer() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        let waiting = await host.start()
        expect(waiting.state == .prepared,
               "single chunk waits for startup prebuffer")
        expect(player.startCount == 0,
               "single chunk does not start before Provider completion")
        let flushed = await host.finishProviderResponse()
        expect(flushed.state == .draining,
               "Provider completion flushes short response")
        expect(player.startCount == 1,
               "short response starts one playback cycle")
        player.completeScheduledChunk()
        await waitUntil { await host.currentSnapshot().state == .completed }
        let completed = await host.currentSnapshot()
        expect(completed.playbackCompletedCount == 1,
               "short response completes once")
    }

    private static func testUnderrunDoesNotStartPlayer() async {
        let (host, player) = makeHost()
        _ = await host.prepare()
        let snapshot = await host.start()
        expect(snapshot.state == .prepared, "underrun keeps prepared")
        expect(snapshot.underrunCount == 1, "underrun count")
        expect(player.startCount == 0, "empty queue does not start")
        expect(snapshot.recentEvents.last?.kind == .bufferUnderrun, "underrun event")
    }

    private static func testQueueFullStopsAndClears() async {
        let configuration = MacSpeechPCMPlaybackConfiguration(
            capacity: 2,
            lowWatermark: 0,
            consumerTimeoutNanoseconds: 1_000_000_000
        )
        let (host, player) = makeHost(configuration: configuration)
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        _ = await host.enqueue(
            pcm16Bytes: Data([2, 0]), sequence: 2, generation: generation
        )
        let failed = await host.enqueue(
            pcm16Bytes: Data([3, 0]), sequence: 3, generation: generation
        )
        expect(failed.state == .failed, "queue full fails host")
        expect(failed.lastError == "playback_queue_full", "queue full error")
        expect(failed.queueDepth == 0, "queue full clears queue")
        expect(player.stopCount == 1, "queue full stops player")
    }

    private static func testConsumerTimeoutStopsAndClears() async {
        let configuration = MacSpeechPCMPlaybackConfiguration(
            capacity: 2,
            lowWatermark: 0,
            consumerTimeoutNanoseconds: 20_000_000
        )
        let (host, player) = makeHost(configuration: configuration)
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        _ = await host.finishProviderResponse()
        await waitUntil { await host.currentSnapshot().state == .failed }
        let failed = await host.currentSnapshot()
        expect(failed.lastError == "consumer_timed_out", "timeout error")
        expect(failed.queueDepth == 0, "timeout clears queue")
        expect(player.stopCount == 1, "timeout stops player")
    }

    private static func testConversionFailureStopsAndClears() async {
        let (host, player) = makeHost()
        player.scheduleError = .conversionFailed
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        let failed = await host.finishProviderResponse()
        expect(failed.state == .failed, "conversion failure stops host")
        expect(failed.lastError == "conversion_failed", "conversion error standardized")
        expect(failed.queueDepth == 0, "conversion failure clears queue")
        expect(player.startCount == 0, "conversion failure never starts player")
        expect(player.stopCount == 1, "conversion failure stops player")
        expect(failed.recentEvents.last?.kind == .failed, "conversion failure emits event")
    }

    private static func testStopAndCloseAreIdempotent() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        _ = await host.finishProviderResponse()
        let stopped = await host.stop()
        let stoppedAgain = await host.stop()
        expect(stopped.state == .stopped, "stopped state")
        expect(stoppedAgain.generation == stopped.generation, "stop idempotent")
        expect(player.stopCount == 1, "single stop side effect")
        let closed = await host.close()
        let closedAgain = await host.close()
        expect(closed.state == .closed, "closed state")
        expect(closedAgain.generation == closed.generation, "close idempotent")
        expect(player.closeCount == 1, "single close side effect")
    }

    private static func testGenerationRejectsLateInputAndCompletion() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        _ = await host.finishProviderResponse()
        let stopped = await host.stop()
        player.completeScheduledChunk()
        try? await Task.sleep(nanoseconds: 5_000_000)
        let afterLateCompletion = await host.currentSnapshot()
        expect(afterLateCompletion.playedChunkCount == 0, "late completion rejected")
        expect(afterLateCompletion.rejectedCallbackCount == 1, "late callback counted")
        let stale = await host.enqueue(
            pcm16Bytes: Data([2, 0]), sequence: 2, generation: generation
        )
        expect(stale.lastError == "stale_generation", "stale generation rejected")
        expect(stale.generation == stopped.generation, "new generation preserved")
    }

    private static func testCloseCanReprepare() async {
        let (host, player) = makeHost()
        let firstGeneration = await host.prepare().generation
        _ = await host.close()
        let reopened = await host.prepare()
        expect(reopened.state == .prepared, "closed host can reprepare")
        expect(reopened.generation > firstGeneration, "reprepare advances generation")
        expect(player.prepareCount == 2, "player prepares again after close")
    }

    private static func testDefaultOutputChangeFailsAndCanRecover() async {
        let player = FakeMacSpeechAudioOutputPlayer()
        let monitor = FakeMacSpeechOutputDeviceMonitor()
        let host = MacSpeechAudioOutputHost(
            player: player,
            deviceMonitor: monitor
        )
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        _ = await host.finishProviderResponse()
        monitor.changeOutput(
            identifier: "output-next",
            name: "Next Output",
            available: true
        )
        await waitUntil { await host.currentSnapshot().state == .failed }
        let failed = await host.currentSnapshot()
        expect(failed.lastError == "output_device_changed", "device change error")
        expect(failed.queueDepth == 0, "device change clears playback")
        expect(player.stopCount == 1, "device change stops player")
        expect(player.closeCount == 1, "device change closes player")
        let recovered = await host.prepare()
        expect(recovered.state == .prepared, "later playback can reprepare")
        expect(recovered.outputDevice.name == "Next Output", "new default output used")
    }

    private static func testUnavailableOutputFailsBeforePrepare() async {
        let player = FakeMacSpeechAudioOutputPlayer()
        let host = MacSpeechAudioOutputHost(
            player: player,
            deviceMonitor: FakeMacSpeechOutputDeviceMonitor(
                outputAvailable: false
            )
        )
        let snapshot = await host.prepare()
        expect(snapshot.state == .failed, "unavailable output fails")
        expect(snapshot.lastError == "output_unavailable", "output error")
        expect(player.prepareCount == 0, "player not prepared without device")
    }

    private static func makeHost(
        configuration: MacSpeechPCMPlaybackConfiguration = .standard
    ) -> (MacSpeechAudioOutputHost, FakeMacSpeechAudioOutputPlayer) {
        let player = FakeMacSpeechAudioOutputPlayer()
        return (
            MacSpeechAudioOutputHost(
                player: player,
                deviceMonitor: FakeMacSpeechOutputDeviceMonitor(),
                configuration: configuration
            ),
            player
        )
    }

    private static func chunk(
        generation: UInt64,
        sequence: UInt64,
        byte: UInt8
    ) -> MacSpeechPCMPlaybackChunk {
        MacSpeechPCMPlaybackChunk(
            generation: generation,
            sequence: sequence,
            pcm16Bytes: Data([byte, 0])
        )
    }

    private static func expectThrows(
        _ expected: MacSpeechAudioOutputHostError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            fatalError("FAILED: expected \(expected.rawValue)")
        } catch let error as MacSpeechAudioOutputHostError {
            expect(error == expected, "throws \(expected.rawValue)")
        } catch {
            fatalError("FAILED: unexpected error \(error)")
        }
    }

    private static func waitUntil(
        attempts: Int = 100,
        condition: @escaping () async -> Bool
    ) async {
        for _ in 0..<attempts {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        fatalError("FAILED: asynchronous condition timed out")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        guard condition else { fatalError("FAILED: \(label)") }
        checks += 1
    }
}
