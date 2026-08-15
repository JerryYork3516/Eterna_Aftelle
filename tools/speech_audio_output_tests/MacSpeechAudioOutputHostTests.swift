@preconcurrency import AVFoundation
import Foundation

@MainActor
@main
private struct MacSpeechAudioOutputHostTests {
    private static var checks = 0

    static func main() async {
        testFrozenProviderFormat()
        testPCMConversionToLocalFormat()
        testPCMConversionResetMatchesFreshStream()
        testResumeFadeInEnvelope()
        testStalledResumeFadeSpansChunks()
        testStalledResumeFadeTracksLateAudibleOnsetAcrossSplits()
        testPlaybackFadeTracksAudibleOnset()
        testPlaybackProcessingPreservesPCMWithoutFade()
        testPlaybackProcessingAvoidsCrossChunkGainPumping()
        testBoundedQueueOrderingAndValidation()
        await testPrepareAndDiagnostics()
        await testPlaybackProcessingDoesNotEmitLimiterEvent()
        await testPlaybackStartWaitsForAudibleChunk()
        await testDurationBasedStartupWatermark()
        await testOrderedPlaybackAndCompletion()
        await testTemporaryQueueGapReportsStallAndResume()
        await testShortResponseFlushesPrebuffer()
        await testUnderrunDoesNotStartPlayer()
        await testQueuePressureWaitsWithoutStopping()
        await testConversionFailureStopsAndClears()
        await testConsumerTimeoutStopsAndClears()
        testConsumerWatchdogIncludesScheduledPCMDuration()
        await testStopAndCloseAreIdempotent()
        await testSpeechStartClearKeepsEngineAvailable()
        await testGenerationRejectsLateInputAndCompletion()
        await testStaleResponseCompletionCannotFinishNewGeneration()
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
        expect(
            MacSpeechPCMPlaybackConfiguration.standard
                .startupBufferDurationNanoseconds == 500_000_000,
            "standard startup buffer is 500 milliseconds"
        )
    }

    private static func testResumeFadeInEnvelope() {
        let sample = Int16(16_384)
        let raw = UInt16(bitPattern: sample)
        var bytes: [UInt8] = []
        for _ in 0 ..< 240 {
            bytes.append(UInt8(truncatingIfNeeded: raw))
            bytes.append(UInt8(truncatingIfNeeded: raw >> 8))
        }
        let faded = [UInt8](
            MacSpeechPCMOutputEnvelope.applyingResumeFadeIn(to: Data(bytes))
        )
        func decodedSample(_ index: Int) -> Int16 {
            let byteIndex = index * 2
            return Int16(bitPattern:
                UInt16(faded[byteIndex])
                    | (UInt16(faded[byteIndex + 1]) << 8)
            )
        }
        expect(abs(Int(decodedSample(0))) < 200,
               "resume fade begins near silence")
        expect(decodedSample(119) == sample,
               "resume fade reaches original level")
        expect(decodedSample(120) == sample,
               "resume fade preserves later samples")
    }

    private static func testPlaybackFadeTracksAudibleOnset() {
        let silence = [Int16](repeating: 0, count: 240)
        let speech = [Int16](repeating: 3_000, count: 240)
        let processed = MacSpeechPCMOutputEnvelope.processing(
            to: pcm16Data(samples: silence + speech),
            applyFadeIn: true
        )
        expect(pcmSample(processed.bytes, at: 239) == 0,
               "leading silence stays unchanged")
        expect(pcmSample(processed.bytes, at: 240) < 200,
               "fade begins at the first audible sample")
        expect(pcmSample(processed.bytes, at: 359) == 3_000,
               "audible fade reaches the source level")
        expect(pcmSample(processed.bytes, at: 360) == 3_000,
               "samples after audible fade stay bit-exact")
    }

    private static func testStalledResumeFadeSpansChunks() {
        let chunk = pcm16Data(
            samples: [Int16](repeating: 10_000, count: 240)
        )
        let first = MacSpeechPCMOutputEnvelope.processing(
            to: chunk,
            fadeIn: .stalledResume
        )
        let continuation = MacSpeechPCMOutputFadeIn.stalledResume
            .advancing(by: first.appliedFadeInSampleCount)
        let second = MacSpeechPCMOutputEnvelope.processing(
            to: chunk,
            fadeIn: continuation
        )
        let whole = MacSpeechPCMOutputEnvelope.processing(
            to: chunk + chunk,
            fadeIn: .stalledResume
        )

        expect(first.appliedFadeInSampleCount == 240,
               "stall fade consumes the first chunk")
        expect(second.appliedFadeInSampleCount == 240,
               "stall fade continues across the next chunk")
        expect(first.bytes + second.bytes == whole.bytes,
               "stall fade is invariant to PCM chunk boundaries")
        expect(pcmSample(first.bytes, at: 239) == 5_000,
               "stall fade remains below unity at the chunk boundary")
        expect(pcmSample(second.bytes, at: 0) > 5_000,
               "stall fade continues instead of restarting")
        expect(pcmSample(second.bytes, at: 239) == 10_000,
               "stall fade reaches the original PCM after 20 milliseconds")
    }

    private static func testPlaybackProcessingPreservesPCMWithoutFade() {
        let fixtures: [[Int16]] = [
            [Int16](repeating: 0, count: 240),
            [Int16](repeating: 3_000, count: 240),
            [Int16](repeating: 30_000, count: 240),
            [Int16.max, Int16.min, 24_000, -24_000]
        ]
        for samples in fixtures {
            let source = pcm16Data(samples: samples)
            let processed = MacSpeechPCMOutputEnvelope.processing(
                to: source,
                applyFadeIn: false
            )
            expect(processed.bytes == source,
                   "PCM stays bit-exact without fade")
        }
    }

    private static func testStalledResumeFadeTracksLateAudibleOnsetAcrossSplits() {
        let silence = [Int16](repeating: 0, count: 230)
        let speech = [Int16](repeating: 10_000, count: 480)
        let trailing = [Int16](repeating: 10_000, count: 37)
        let samples = silence + speech + trailing
        let chunks = [
            Array(samples[0 ..< 240]),
            Array(samples[240 ..< 377]),
            Array(samples[377 ..< samples.count])
        ].map { pcm16Data(samples: $0) }
        var fadeIn: MacSpeechPCMOutputFadeIn? = .stalledResume
        var splitOutput = Data()
        var appliedCounts: [Int] = []
        for chunk in chunks {
            let processed = MacSpeechPCMOutputEnvelope.processing(
                to: chunk,
                fadeIn: fadeIn
            )
            splitOutput.append(processed.bytes)
            appliedCounts.append(processed.appliedFadeInSampleCount)
            fadeIn = fadeIn?.advancing(
                by: processed.appliedFadeInSampleCount
            )
        }
        let whole = MacSpeechPCMOutputEnvelope.processing(
            to: pcm16Data(samples: samples),
            fadeIn: .stalledResume
        )

        expect(appliedCounts == [10, 137, 333],
               "late audible onset consumes only audible fade samples")
        expect(splitOutput == whole.bytes,
               "uneven PCM splits preserve one continuous resume ramp")
        expect(pcmSample(splitOutput, at: 229) == 0,
               "leading silence remains bit-exact before recovery speech")
        expect(pcmSample(splitOutput, at: 230) < 100,
               "resume ramp begins at the late audible onset")
        expect(pcmSample(splitOutput, at: 709) == 10_000,
               "resume ramp reaches unity after 480 audible samples")
        expect(pcmSample(splitOutput, at: 710) == 10_000,
               "post-ramp PCM remains bit-exact")
    }

    private static func testPlaybackProcessingAvoidsCrossChunkGainPumping() {
        let chunks = [
            pcm16Data(samples: [Int16](repeating: 3_000, count: 240)),
            pcm16Data(samples: [Int16](repeating: 30_000, count: 240)),
            pcm16Data(samples: [Int16](repeating: 3_000, count: 240))
        ]
        let processed = chunks.map {
            MacSpeechPCMOutputEnvelope.processing(
                to: $0,
                applyFadeIn: false
            ).bytes
        }
        expect(processed == chunks,
               "quiet loud quiet chunks do not pump gain")
    }

    private static func pcm16Data(samples: [Int16]) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            let raw = UInt16(bitPattern: sample)
            bytes.append(UInt8(truncatingIfNeeded: raw))
            bytes.append(UInt8(truncatingIfNeeded: raw >> 8))
        }
        return Data(bytes)
    }

    private static func pcmSample(_ data: Data, at index: Int) -> Int16 {
        let bytes = [UInt8](data)
        let byteIndex = index * 2
        return Int16(bitPattern:
            UInt16(bytes[byteIndex])
                | (UInt16(bytes[byteIndex + 1]) << 8)
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

    private static func testPCMConversionResetMatchesFreshStream() {
        guard let localFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ) else {
            fatalError("FAILED: construct converter reset format")
        }
        let polluted = pcm16Data(
            samples: [Int16](repeating: 12_000, count: 480)
        )
        let probe = pcm16Data(
            samples: (0 ..< 480).map { index in
                index.isMultiple(of: 2) ? Int16(4_000) : Int16(-4_000)
            }
        )
        do {
            let resetConverter = try MacSpeechPCMOutputConverter(
                localFormat: localFormat
            )
            _ = try resetConverter.convert(pcm16Bytes: polluted)
            resetConverter.reset()
            let resetOutput = try resetConverter.convert(pcm16Bytes: probe)
            let freshOutput = try MacSpeechPCMOutputConverter(
                localFormat: localFormat
            ).convert(pcm16Bytes: probe)
            expect(resetOutput.frameLength == freshOutput.frameLength,
                   "converter reset restores fresh frame count")
            let resetSamples = floatSamples(resetOutput)
            let freshSamples = floatSamples(freshOutput)
            expect(resetSamples.count == freshSamples.count,
                   "converter reset restores fresh sample count")
            let maximumDelta = zip(resetSamples, freshSamples).reduce(0.0) {
                max($0, abs(Double($1.0 - $1.1)))
            }
            expect(maximumDelta < 0.000_001,
                   "converter reset removes prior stream history")
        } catch {
            fatalError("FAILED: PCM converter reset \(error)")
        }
    }

    private static func floatSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(
            start: channels[0],
            count: Int(buffer.frameLength)
        ))
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
        expect(player.resetForPlaybackGenerationCount == 1,
               "prepare resets converter for the first generation")
        let repeated = await host.prepare()
        expect(repeated.generation == prepared.generation, "prepare idempotent")
        expect(player.prepareCount == 1, "no duplicate prepare")
        expect(player.resetForPlaybackGenerationCount == 1,
               "idempotent prepare does not reset the active stream")
        expect(repeated.recentEvents.map(\.kind) == [.prepared], "prepared event")
    }

    private static func testPlaybackProcessingDoesNotEmitLimiterEvent() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        let source = pcm16Data(
            samples: [Int16](repeating: 30_000, count: 240)
        )
        _ = await host.enqueue(
            pcm16Bytes: source,
            sequence: 42,
            generation: generation
        )
        let snapshot = await host.finishProviderResponse(
            generation: generation
        )
        expect(!snapshot.recentEvents.map(\.kind).contains(.outputSafetyLimited),
               "playback does not emit dynamic limiter events")
        expect(pcmSample(player.processed[0], at: 119) == 30_000,
               "fade reaches the original near-full-scale PCM")
        expect(pcmSample(player.processed[0], at: 120) == 30_000,
               "playback preserves PCM after the first fade")
    }

    private static func testPlaybackStartWaitsForAudibleChunk() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        let silent = pcm16Data(samples: [Int16](repeating: 0, count: 240))
        let audible = pcm16Data(
            samples: [Int16](repeating: 3_000, count: 240)
        )
        _ = await host.enqueue(
            pcm16Bytes: silent, sequence: 1, generation: generation
        )
        _ = await host.enqueue(
            pcm16Bytes: audible, sequence: 2, generation: generation
        )
        _ = await host.start()
        expect(player.fadeIns == [true, true],
               "fade-in remains armed through leading silence")
        _ = await host.enqueue(
            pcm16Bytes: audible, sequence: 3, generation: generation
        )
        expect(player.fadeIns == [true, true, false],
               "only the first audible playback chunk consumes fade-in")
        expect(player.processed[0] == silent,
               "leading silence remains bit-exact")
        expect(pcmSample(player.processed[1], at: 0) < 200,
               "first audible chunk begins with a fade")
        expect(pcmSample(player.processed[1], at: 119) == 3_000,
               "first audible chunk returns to source PCM")
        expect(player.processed[2] == audible,
               "later audible chunks remain bit-exact")
        _ = await host.stop()
    }

    private static func testDurationBasedStartupWatermark() async {
        let (host, player) = makeHost(configuration: .standard)
        let generation = await host.prepare().generation
        for sequence in UInt64(1) ... UInt64(2) {
            _ = await host.enqueue(
                pcm16Bytes: Data(repeating: 0, count: 8_192),
                sequence: sequence,
                generation: generation
            )
        }
        let waiting = await host.start()
        expect(waiting.state == .prepared,
               "341 milliseconds does not satisfy startup watermark")
        expect(waiting.bufferedDurationMilliseconds == 341,
               "buffer reports PCM duration")
        _ = await host.enqueue(
            pcm16Bytes: Data(repeating: 0, count: 8_192),
            sequence: 3,
            generation: generation
        )
        let started = await host.start()
        expect(started.state == .playing,
               "512 milliseconds starts playback")
        expect(player.scheduledCount == 3,
               "duration watermark preserves ordered scheduling")
        _ = await host.finishProviderResponse(generation: generation)
        for _ in 0 ..< 3 { player.completeScheduledChunk() }
        await waitUntil { await host.currentSnapshot().state == .completed }
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
        expect(player.scheduledCount == 2, "successor is scheduled ahead")
        _ = await host.finishProviderResponse(generation: generation)
        player.completeScheduledChunk()
        await waitUntil {
            await host.currentSnapshot().playedChunkCount == 1
        }
        expect(player.payloads == [Data([1, 0]), Data([2, 0])], "ordered scheduling")
        player.completeScheduledChunk()
        await waitUntil { await host.currentSnapshot().state == .completed }
        let completed = await host.currentSnapshot()
        expect(completed.playedChunkCount == 2, "played chunk count")
        expect(completed.playedByteCount == 4, "played byte count")
        expect(completed.queueDepth == 0, "queue exhausted")
        expect(completed.playbackStartedCount == 1, "playback start counted")
        expect(completed.playbackCompletedCount == 1, "playback completion counted")
        expect(player.finishPlaybackCount == 1,
               "formal playback completion releases the input echo gate once")
        expect(
            completed.recentEvents.filter { $0.kind == .chunkPlayed }
                .compactMap(\.sequence) == [1, 2],
            "played chunk events expose ordered subtitle watermarks"
        )
        expect(
            completed.recentEvents.map(\.kind).contains(.playbackCompleted),
            "local completion event"
        )
    }

    private static func testTemporaryQueueGapReportsStallAndResume() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        let audible = pcm16Data(
            samples: [Int16](repeating: 3_000, count: 240)
        )
        _ = await host.enqueue(
            pcm16Bytes: audible, sequence: 1, generation: generation
        )
        _ = await host.enqueue(
            pcm16Bytes: audible, sequence: 2, generation: generation
        )
        _ = await host.start()
        player.completeScheduledChunk()
        await waitUntil {
            await host.currentSnapshot().playedChunkCount == 1
        }
        player.completeScheduledChunk()
        await waitUntil {
            let snapshot = await host.currentSnapshot()
            return snapshot.queueDepth == 0 && snapshot.state == .stalled
        }
        let gap = await host.currentSnapshot()
        expect(gap.playbackCompletedCount == 0,
               "temporary queue gap is not response completion")
        expect(player.finishPlaybackCount == 0,
               "temporary queue gap keeps the input echo gate active")
        expect(gap.recentEvents.map(\.kind).contains(.playbackStalled),
               "temporary queue gap reports stalled")
        _ = await host.enqueue(
            pcm16Bytes: audible, sequence: 3, generation: generation
        )
        expect(player.scheduledCount == 2,
               "stalled playback waits for the frozen prebuffer")
        _ = await host.enqueue(
            pcm16Bytes: audible, sequence: 4, generation: generation
        )
        await waitUntil { player.scheduledCount == 4 }
        let resumed = await host.currentSnapshot()
        expect(resumed.state == .playing, "stalled playback resumes")
        expect(resumed.recentEvents.map(\.kind).contains(.playbackResumed),
               "resumed playback is observable")
        expect(player.startCount == 1,
               "new audio continues the same player cycle")
        expect(player.resetForPlaybackGenerationCount == 1,
               "stall and resume retain converter stream state")
        expect(player.fadeIns == [true, false, true, true],
               "stall recovery fade remains armed across PCM chunks")
        expect(
            player.fadeInStates.compactMap { $0?.appliedSampleCount }
                == [0, 0, 240],
            "stall recovery fade advances without restarting"
        )
        expect(pcmSample(player.processed[2], at: 239) == 1_500,
               "first resumed chunk stays inside the 20 millisecond ramp")
        expect(pcmSample(player.processed[3], at: 239) == 3_000,
               "second resumed chunk returns to source PCM")
        _ = await host.finishProviderResponse(generation: generation)
        player.completeScheduledChunk()
        player.completeScheduledChunk()
        await waitUntil { await host.currentSnapshot().state == .completed }
        let completed = await host.currentSnapshot()
        expect(completed.playbackStartedCount == 1,
               "response emits one playbackStarted")
        expect(completed.playbackCompletedCount == 1,
               "response emits one playbackCompleted")
    }

    private static func testConsumerWatchdogIncludesScheduledPCMDuration() {
        let safetyMargin: UInt64 = 25_000_000
        expect(
            MacSpeechAudioOutputHost.consumerWatchdogNanoseconds(
                inFlightByteCount: 48_000,
                safetyMarginNanoseconds: safetyMargin
            ) == 1_025_000_000,
            "watchdog includes scheduled PCM duration and safety margin"
        )
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
        let flushed = await host.finishProviderResponse(
            generation: generation
        )
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

    private static func testQueuePressureWaitsWithoutStopping() async {
        let configuration = MacSpeechPCMPlaybackConfiguration(
            capacity: 2,
            lowWatermark: 0,
            consumerTimeoutNanoseconds: 1_000_000_000,
            scheduleAheadCount: 1
        )
        let (host, player) = makeHost(configuration: configuration)
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        _ = await host.enqueue(
            pcm16Bytes: Data([2, 0]), sequence: 2, generation: generation
        )
        _ = await host.start()
        _ = await host.enqueue(
            pcm16Bytes: Data([3, 0]), sequence: 3, generation: generation
        )
        let waitingEnqueue = Task {
            await host.enqueue(
                pcm16Bytes: Data([4, 0]),
                sequence: 4,
                generation: generation
            )
        }
        await waitUntil {
            await host.currentSnapshot().pressureWaitCount == 1
        }
        let pressured = await host.currentSnapshot()
        expect(pressured.state == .playing,
               "queue pressure keeps playback active")
        expect(pressured.lastError == nil,
               "queue pressure is not a fatal error")
        expect(player.stopCount == 0,
               "queue pressure does not stop player")

        player.completeScheduledChunk()
        let resumed = await waitingEnqueue.value
        expect(resumed.enqueuedChunkCount == 4,
               "producer resumes after scheduled capacity frees")
        _ = await host.finishProviderResponse(generation: generation)
        for expectedPlayedCount in 2 ... 4 {
            player.completeScheduledChunk()
            await waitUntil {
                await host.currentSnapshot().playedChunkCount
                    == expectedPlayedCount
            }
        }
        let completed = await host.currentSnapshot()
        expect(completed.state == .completed,
               "pressured response completes normally")
        expect(player.payloads == [
            Data([1, 0]), Data([2, 0]), Data([3, 0]), Data([4, 0])
        ], "pressure preserves PCM ordering")
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
        _ = await host.finishProviderResponse(generation: generation)
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
        let failed = await host.finishProviderResponse(
            generation: generation
        )
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
        _ = await host.finishProviderResponse(generation: generation)
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

    private static func testSpeechStartClearKeepsEngineAvailable() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        let audible = pcm16Data(
            samples: [Int16](repeating: 3_000, count: 240)
        )
        _ = await host.enqueue(
            pcm16Bytes: audible, sequence: 1, generation: generation
        )
        _ = await host.finishProviderResponse(generation: generation)
        let cleared = await host.clearForAcceptedSpeechStart()
        expect(cleared.state == .prepared,
               "speech start returns output Host to prepared")
        expect(cleared.generation > generation,
               "speech start invalidates the old playback generation")
        expect(player.clearScheduledPlaybackCount == 1,
               "speech start clears scheduled PlayerNode audio once")
        expect(player.resetForPlaybackGenerationCount == 2,
               "speech start resets converter for the new generation")
        expect(player.stopCount == 0,
               "speech start keeps the audio engine available")
        let repeated = await host.clearForAcceptedSpeechStart()
        expect(repeated.generation == cleared.generation,
               "duplicate speech start does not clear an empty Host")
        expect(player.clearScheduledPlaybackCount == 1,
               "duplicate speech start has no Player side effect")
        expect(player.resetForPlaybackGenerationCount == 2,
               "duplicate speech start does not reset converter again")
        _ = await host.enqueue(
            pcm16Bytes: audible,
            sequence: 2,
            generation: cleared.generation
        )
        _ = await host.enqueue(
            pcm16Bytes: audible,
            sequence: 3,
            generation: cleared.generation
        )
        _ = await host.start()
        expect(pcmSample(player.processed[1], at: 0) < 200,
               "new generation rearms the first audible fade")
        expect(pcmSample(player.processed[1], at: 119) == 3_000,
               "new generation fade returns to source PCM")
        expect(player.processed[2] == audible,
               "new generation second chunk remains bit-exact")
        _ = await host.stop()
    }

    private static func testGenerationRejectsLateInputAndCompletion() async {
        let (host, player) = makeHost()
        let generation = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]), sequence: 1, generation: generation
        )
        _ = await host.finishProviderResponse(generation: generation)
        let stopped = await host.stop()
        player.completeStoppedChunk()
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

    private static func testStaleResponseCompletionCannotFinishNewGeneration()
        async {
        let (host, player) = makeHost()
        let staleGeneration = await host.prepare().generation
        _ = await host.enqueue(
            pcm16Bytes: Data([1, 0]),
            sequence: 1,
            generation: staleGeneration
        )
        let cleared = await host.clear()
        let currentGeneration = cleared.generation
        _ = await host.enqueue(
            pcm16Bytes: Data([2, 0]),
            sequence: 2,
            generation: currentGeneration
        )
        let rejected = await host.finishProviderResponse(
            generation: staleGeneration
        )
        expect(
            rejected.state == .prepared && player.startCount == 0,
            "stale response completion cannot finish a new generation"
        )
        let accepted = await host.finishProviderResponse(
            generation: currentGeneration
        )
        expect(
            accepted.state == .draining && player.startCount == 1,
            "current response completion still flushes playback"
        )
        player.completeScheduledChunk()
        await waitUntil { await host.currentSnapshot().state == .completed }
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
        _ = await host.finishProviderResponse(generation: generation)
        monitor.changeOutput(
            identifier: "output-next",
            name: "Next Output",
            available: true
        )
        await waitUntil { await host.currentSnapshot().state == .failed }
        let failed = await host.currentSnapshot()
        expect(failed.lastError == "output_device_changed", "device change error")
        expect(failed.queueDepth == 0, "device change clears playback")
        expect(player.routeResetCount == 1, "device change invalidates AEC reference")
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
        configuration: MacSpeechPCMPlaybackConfiguration =
            MacSpeechPCMPlaybackConfiguration(
                capacity: 8,
                lowWatermark: 1,
                consumerTimeoutNanoseconds: 2_000_000_000,
                startupBufferCount: 2,
                startupBufferDurationNanoseconds: 0,
                scheduleAheadCount: 4
            )
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
