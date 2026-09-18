@preconcurrency import AVFoundation
import Foundation

private final class FakeAECBackend: MacSpeechAECBackend, @unchecked Sendable {
    private let lock = NSLock()
    let linearOutputDelaySamples: Int
    let processedOutputDelaySamples: Int
    var configureError: MacSpeechAECBackendError?
    var renderError: MacSpeechAECBackendError?
    var captureError: MacSpeechAECBackendError?
    private var operations: [String] = []
    private var delays: [Int] = []
    private var resets = 0
    private var active = true
    private var erlDecibels = 12.0
    private var erleDecibels = 24.0
    private var captureOutput: [Float]?
    private var captureOutputQueue: [[Float]] = []
    private var linearOutput: [Float]?

    init(linearOutputDelaySamples: Int = 0, processedOutputDelaySamples: Int = 0) {
        self.linearOutputDelaySamples = linearOutputDelaySamples
        self.processedOutputDelaySamples = processedOutputDelaySamples
    }

    func configure() throws {
        if let configureError { throw configureError }
        lock.withLock { operations.append("configure") }
    }

    func processRender(_ samples: [Float]) throws {
        if let renderError { throw renderError }
        guard samples.count == MacSpeechAcousticEchoHost.frameSampleCount else {
            throw MacSpeechAECBackendError.renderFailed
        }
        lock.withLock { operations.append("render") }
    }

    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult {
        if let captureError { throw captureError }
        guard samples.count == MacSpeechAcousticEchoHost.frameSampleCount else {
            throw MacSpeechAECBackendError.captureFailed
        }
        return lock.withLock {
            operations.append("capture")
            let processed = captureOutputQueue.isEmpty
                ? captureOutput ?? samples.map { $0 * 0.5 }
                : captureOutputQueue.removeFirst()
            return MacSpeechAECCaptureResult(
                processedSamples: processed,
                linearOutputSamples:
                    linearOutput ?? downsampleToSixteenKilohertz(processed)
            )
        }
    }

    func setDelay(milliseconds: Int) throws {
        lock.withLock {
            delays.append(milliseconds)
            operations.append("delay")
        }
    }

    func reset() throws {
        lock.withLock {
            resets += 1
            operations.append("reset")
        }
    }

    func stats() throws -> MacSpeechAECBackendStats {
        lock.withLock {
            MacSpeechAECBackendStats(
                enabled: true,
                active: active,
                estimatedDelayMilliseconds: delays.last ?? 0,
                erlDecibels: erlDecibels,
                erleDecibels: erleDecibels
            )
        }
    }

    func setMetrics(active: Bool = true, erl: Double = 12, erle: Double) {
        lock.withLock {
            self.active = active
            erlDecibels = erl
            erleDecibels = erle
        }
    }

    func setCaptureOutput(_ samples: [Float]?) {
        lock.withLock { captureOutput = samples }
    }

    func setCaptureOutputQueue(_ frames: [[Float]]) {
        lock.withLock { captureOutputQueue = frames }
    }

    func setLinearOutput(_ samples: [Float]?) {
        lock.withLock { linearOutput = samples }
    }

    private func downsampleToSixteenKilohertz(_ samples: [Float]) -> [Float] {
        stride(from: 0, to: samples.count, by: 3).map { index in
            let end = min(index + 3, samples.count)
            return samples[index ..< end].reduce(0, +)
                / Float(end - index)
        }
    }

    var recordedOperations: [String] { lock.withLock { operations } }
    var recordedDelays: [Int] { lock.withLock { delays } }
    var resetCount: Int { lock.withLock { resets } }
}

@MainActor
@main
private struct MacSpeechAcousticEchoHostTests {
    private static var checks = 0

    static func main() {
        if CommandLine.arguments.contains("--converter-timing-only") {
            testConverterTimestampQuantization()
            print("converter_timing_checks=\(checks)")
            return
        }
        if CommandLine.arguments.contains("--apple-framing-only") {
            testAppleModeDoesNotUseWebRTC()
            testAppleCaptureFraming()
            testAppleConvertedCaptureFraming()
            testNativeTenMillisecondTapFraming()
            testSixteenToFortyEightCaptureFraming()
            testTwentyFourToFortyEightResamplingRoundTrip()
            testConverterTimestampQuantization()
            print("apple_framing_checks=\(checks)")
            return
        }
        if CommandLine.arguments.contains("--subframe-reference-only") {
            exit(testSubframeEchoReference() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--competing-reference-only") {
            exit(testCompetingEchoReference() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--weak-budget-only") {
            exit(testAlternatingWeakEvidenceCloseBudget() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--timing-controls-only") {
            exit(runTimingControls() ? 0 : 1)
        }
        testConfigureAndSerializedFraming()
        testArbitraryRenderCallbackFraming()
        testArbitraryCaptureCallbackFraming()
        testMultiFrameCaptureCallbackPreservesGateEvidence()
        testFIFORemainderIsBounded()
        testRenderAlignedDelay()
        testHostTimeAlignedDelayAndDiagnostics()
        #if DEBUG
        testAcousticReplayCapture()
        testLocalNearEndInjectionTiming()
        #endif
        testFutureRenderTimestampIsCaptureCausal()
        testTimingLockDoesNotJumpOnRepeatedRender()
        testUnsupportedExpectedTimingDiscoversActualPath()
        testTimingLockReacquiresShiftedPath()
        testSourceGateEpochDiagnosticsAreBounded()
        testTimingHistoryIsBoundedAndReset()
        testEchoOnlySourceGate()
        testNearEndSourceGateAndPreRoll()
        testAbortedSourceGatePreRollPreservesCadence()
        testSuppressedOnsetPreRollBoundaries()
        testDoubleTalkSourceGate()
        testDelayedAECOutputEvidence()
        testMissingAECReferenceCannotRenewHangover()
        testRouteIndependentBargeInHysteresis()
        testAdaptiveExternalOutputDoubleTalk()
        testBaselineFreezesBeforeQuieterUserSpeech()
        testAbortedCandidateDoesNotFreezeUntrainedBaseline()
        testAdaptiveGateRejectsResidualEchoVariation()
        testMixedResidentRenderIsOneFarEndReference()
        testLongLoudEchoStaysSuppressed()
        testRenderCaptureIsolationOpensOnlyForNearEnd()
        testUncertainSourceGateIsBoundedAndRecoverable()
        testAmbiguousSourceStaysGatedAndRecovers()
        testRenderConversionFailureFallback()
        testRouteRebuildRecovery()
        testFallbackAndPlaybackRecovery()
        testPoorERLEPreservesEchoGateAndBargeIn()
        testPlaybackStopClearsSourceGateState()
        testStopAlwaysRecoversCapture()
        testAppleModeDoesNotUseWebRTC()
        testAppleCaptureFraming()
        testAppleConvertedCaptureFraming()
        testConverterTimestampQuantization()
        testNativeTenMillisecondTapFraming()
        testSixteenToFortyEightCaptureFraming()
        testTwentyFourToFortyEightResamplingRoundTrip()
        print("speech_aec_host_checks=\(checks)")
        let timingPassed = runTimingControls()
        let subframePassed = testSubframeEchoReference()
        let referencePassed = testCompetingEchoReference()
        let budgetPassed = testAlternatingWeakEvidenceCloseBudget()
        if !timingPassed || !subframePassed || !referencePassed || !budgetPassed { exit(1) }
    }

    #if DEBUG
    private static func testLocalNearEndInjectionTiming() {
        let start: UInt64 = 1_000_000_000
        let source = (0..<720).map { Float($0) / 2_000 }
        var injection = Test3NearEndInjection(
            samples: source, startAtNanoseconds: start + 5_000_000
        )
        var early = [Float](repeating: 0.1, count: 480)
        injection.mix(into: &early, hostTimeNanoseconds: start - 10_000_000)
        expect(early.allSatisfy { $0 == 0.1 }, "near fixture does not precede its start")
        expect(injection.injectedSampleCount == 0, "early callback consumes no fixture")
        var first = [Float](repeating: 0, count: 480)
        injection.mix(into: &first, hostTimeNanoseconds: start)
        expect(first.prefix(240).allSatisfy { $0 == 0 }, "start offset preserves real mic prefix")
        expect(Array(first.suffix(240)) == Array(source.prefix(240)), "fixture begins at sample offset")
        expect(injection.startedAtNanoseconds == start + 5_000_000, "actual injection time recorded")
        var second = [Float](repeating: 0, count: 480)
        injection.mix(into: &second, hostTimeNanoseconds: start + 10_500_000)
        expect(second == Array(source.suffix(480)), "callback jitter does not skip or repeat fixture samples")
        expect(injection.injectedSampleCount == 720, "fixture consumption is bounded")
        var after = [Float](repeating: 0.2, count: 480)
        injection.mix(into: &after, hostTimeNanoseconds: start + 20_000_000)
        expect(after.allSatisfy { $0 == 0.2 }, "completed injection leaves microphone unchanged")
        var clipping = Test3NearEndInjection(samples: [0.8, -0.8], startAtNanoseconds: start)
        var loud: [Float] = [0.8, -0.8]
        clipping.mix(into: &loud, hostTimeNanoseconds: start)
        expect(loud == [1, -1], "software mix stays within PCM range")
    }
    #endif

    private static func testConfigureAndSerializedFraming() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        expect(host.configure() == .webRTCAEC3, "AEC configures")
        host.processRender([Float](repeating: 0.25, count: 240))
        host.processRender([Float](repeating: 0.25, count: 240))
        let output = host.processCapture(
            [Float](repeating: 0.5, count: 480)
        )
        expect(output == [Float](repeating: 0.25, count: 480),
               "capture uses processed output")
        expect(
            backend.recordedOperations.prefix(3) == [
                "configure", "render", "capture"
            ],
            "render precedes capture on serialized processing path"
        )
        let snapshot = host.snapshot()
        expect(snapshot.renderFrameCount == 1, "render 10 ms framing")
        expect(snapshot.captureFrameCount == 1, "capture 10 ms framing")
        expect(snapshot.renderFIFOSampleCount == 0, "render FIFO drained")
        expect(snapshot.captureFIFOSampleCount == 0, "capture FIFO drained")
        expect(snapshot.erlDecibels == 12, "ERL exposed")
        expect(snapshot.erleDecibels == 24, "ERLE exposed")
    }

    private static func testArbitraryRenderCallbackFraming() {
        for durationMilliseconds in [120, 250, 500] {
            let host = MacSpeechAcousticEchoHost(
                mode: .webRTCAEC3,
                backend: FakeAECBackend(),
                fifoFrameCapacity: 1
            )
            _ = host.configure()
            let sampleCount = durationMilliseconds * 48
            host.processRender([Float](repeating: 0, count: sampleCount))
            let snapshot = host.snapshot()
            expect(snapshot.mode == .webRTCAEC3,
                   "\(durationMilliseconds) ms render callback stays in AEC")
            expect(snapshot.renderFrameCount == UInt64(sampleCount / 480),
                   "\(durationMilliseconds) ms render callback is fully framed")
            expect(snapshot.renderFIFOSampleCount == sampleCount % 480,
                   "render keeps only the incomplete frame")
        }
    }

    private static func testArbitraryCaptureCallbackFraming() {
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: FakeAECBackend(),
            fifoFrameCapacity: 1
        )
        _ = host.configure()
        let samples = [Float](repeating: 0.5, count: 24_000)
        let output = host.processCapture(samples)
        let snapshot = host.snapshot()
        expect(output.count == samples.count,
               "500 ms capture callback preserves all complete output")
        expect(snapshot.captureFrameCount == 50,
               "500 ms capture callback is split into 10 ms frames")
        expect(snapshot.captureFIFOSampleCount == 0,
               "large capture callback leaves no complete frame queued")
    }

    private static func testMultiFrameCaptureCallbackPreservesGateEvidence() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 500, amplitude: 0.3)
        let nearEnd = testSignal(seed: 501, amplitude: 0.25)
        let echo = render.map { $0 * 0.5 }
        let baseTimestamp: UInt64 = 500_000_000_000
        host.processRender(
            Array(repeating: render, count: 4).flatMap { $0 },
            hostTimeNanoseconds: baseTimestamp
        )
        backend.setCaptureOutputQueue([nearEnd, nearEnd, nearEnd, echo])
        let spans = host.processCaptureSpans(
            nearEnd + nearEnd + nearEnd + render
                + [Float](repeating: 0, count: 137),
            hostTimeNanoseconds: baseTimestamp + 80_000_000
        )
        let snapshot = host.snapshot()
        expect(snapshot.captureFrameCount == 4
                   && snapshot.captureFIFOSampleCount == 137,
               "irregular callback keeps only its incomplete remainder")
        expect(snapshot.inputClassification == .uncertain
                   && snapshot.sourceGateOpen,
               "one historical echo frame stays uncertain during hangover")
        expect(spans.count == 4,
               "confirmed pre-roll and trailing echo retain four 10 ms spans")
        expect(spans.map(\.observation.captureFrameIndex) == [1, 2, 3, 4],
               "capture spans retain their original frame identities")
        expect(spans.compactMap(\.observation.captureHostTimeNanoseconds)
                   == [
                       baseTimestamp + 80_000_000,
                       baseTimestamp + 90_000_000,
                       baseTimestamp + 100_000_000,
                       baseTimestamp + 110_000_000
                   ],
               "capture spans retain their original monotonic timestamps")
        let positiveSpans = spans.filter {
            MacSpeechAudioActivityEvidenceKind.classify(
                observation: $0.observation
            ) == .sourceGatedNearEnd
        }
        expect(positiveSpans.count == 3
                   && positiveSpans.allSatisfy {
                       $0.observation.sourceGateOpen
                           && $0.observation.sourceGateEpoch == 1
                   },
               "confirmed pre-roll binds exact positive frames to one epoch")
        let trailingObservation = spans.last?.observation
        expect(trailingObservation?.inputClassification == .uncertain
                   && trailingObservation.map {
                       MacSpeechAudioActivityEvidenceKind.classify(
                           observation: $0
                       )
                   } == MacSpeechAudioActivityEvidenceKind.none,
               "untrusted open-gate hangover never becomes user evidence")
        let packets = convertedPackets(captureSpans: spans)
        let positivePackets = packets.filter {
            $0.activityEvidenceKind == .sourceGatedNearEnd
        }
        expect(!positivePackets.isEmpty
                   && positivePackets.allSatisfy {
                       guard let packetObservation = $0.acousticSnapshot else {
                           return false
                       }
                       return packetObservation.inputClassification
                               == .nearEndSpeech
                           && positiveSpans.contains {
                               $0.observation == packetObservation
                           }
                   },
               "production conversion binds packets to an original positive span")

        let abortedBackend = FakeAECBackend()
        let abortedHost = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: abortedBackend
        )
        _ = abortedHost.configure()
        abortedHost.playbackStarted()
        abortedHost.processRender(
            Array(repeating: render, count: 4).flatMap { $0 },
            hostTimeNanoseconds: baseTimestamp + 1_000_000_000
        )
        abortedBackend.setCaptureOutputQueue([nearEnd, nearEnd, echo, echo])
        let abortedSpans = abortedHost.processCaptureSpans(
            nearEnd + nearEnd + render + render,
            hostTimeNanoseconds: baseTimestamp + 1_080_000_000
        )
        let abortedSnapshot = abortedHost.snapshot()
        expect(abortedSnapshot.sourceGateOpenCount == 0
                   && abortedSnapshot.sourceForwardedFrameCount == 0,
               "two candidate frames cannot open the source gate")
        expect(abortedSpans.allSatisfy { isSilence($0.samples) }
                   && convertedPackets(captureSpans: abortedSpans)
                       .allSatisfy {
                           $0.activityEvidenceKind == .none
                       },
               "aborted pre-roll remains silence with no user evidence")

        let echoBackend = FakeAECBackend()
        let echoHost = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: echoBackend
        )
        _ = echoHost.configure()
        echoHost.playbackStarted()
        echoHost.processRender(
            Array(repeating: render, count: 4).flatMap { $0 },
            hostTimeNanoseconds: baseTimestamp + 2_000_000_000
        )
        echoBackend.setCaptureOutputQueue([echo, echo, echo, echo])
        let echoSpans = echoHost.processCaptureSpans(
            Array(repeating: render, count: 4).flatMap { $0 },
            hostTimeNanoseconds: baseTimestamp + 2_080_000_000
        )
        let echoSnapshot = echoHost.snapshot()
        expect(echoSnapshot.sourceGateOpenCount == 0
                   && echoSnapshot.sourceForwardedFrameCount == 0,
               "resident-only multi-frame callback keeps the gate closed")
        expect(convertedPackets(captureSpans: echoSpans).allSatisfy {
            $0.activityEvidenceKind == .none
        }, "resident-only packets cannot gain source-gated evidence")
    }

    private static func testFIFORemainderIsBounded() {
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: FakeAECBackend(),
            fifoFrameCapacity: 1
        )
        _ = host.configure()
        host.processRender([Float](repeating: 0, count: 24_001))
        expect(host.snapshot().renderFIFOSampleCount == 1,
               "render keeps only one incomplete-frame sample")
        host.processRender([Float](repeating: 0, count: 479))
        expect(host.snapshot().renderFIFOSampleCount == 0,
               "render remainder completes without backlog")
        let first = host.processCapture(
            [Float](repeating: 0.5, count: 24_001)
        )
        expect(first.count == 24_000,
               "complete capture frames are emitted immediately")
        expect(host.snapshot().captureFIFOSampleCount == 1,
               "only one capture remainder sample is retained")
        host.discardPendingCaptureForGenerationTransition()
        expect(host.snapshot().captureFIFOSampleCount == 0,
               "generation fence clears the old capture remainder")
        let second = host.processCapture(
            [Float](repeating: 0.5, count: 479)
        )
        expect(second.isEmpty,
               "post-fence samples cannot complete an old capture frame")
        let third = host.processCapture(
            [Float](repeating: 0.5, count: 1)
        )
        expect(third.count == 480,
               "post-fence remainder completes only with current samples")
        let snapshot = host.snapshot()
        expect(snapshot.captureFIFOSampleCount < 480,
               "capture remainder stays below one frame")
        expect(snapshot.mode == .webRTCAEC3,
               "legal large callbacks never report FIFO overflow")
    }

    private static func testRenderAlignedDelay() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.recordCaptureProcessingDuration(nanoseconds: 2_000_000)
        host.updateDelay(
            outputPresentationLatencySeconds: 0.020,
            capturePresentationLatencySeconds: 0.010
        )
        expect(backend.recordedDelays.last == 32,
               "render-aligned delay excludes future scheduled audio")
        expect(host.snapshot().delayMilliseconds == 32,
               "measured delay is exposed")
    }

    private static func testHostTimeAlignedDelayAndDiagnostics() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.updateDelay(
            outputPresentationLatencySeconds: 0.020,
            capturePresentationLatencySeconds: 0.010
        )
        host.playbackStarted()
        for index in 0 ..< 3 {
            let frame = testSignal(
                seed: UInt32(700 + index),
                amplitude: 0.25
            )
            host.processRender(
                frame,
                hostTimeNanoseconds:
                    1_000_000_000 + UInt64(index * 10_000_000)
            )
            _ = host.processCapture(
                frame,
                hostTimeNanoseconds:
                    1_080_000_000 + UInt64(index * 10_000_000)
            )
        }

        let snapshot = host.snapshot()
        expect(snapshot.presentationDelayMilliseconds == 30,
               "presentation delay remains available as a baseline")
        expect(snapshot.alignedDelayMilliseconds == 80,
               "matched host times establish the acoustic delay")
        expect(snapshot.sourceAlignmentDelayMilliseconds == 80,
               "source alignment has an explicit diagnostic field")
        expect(snapshot.sourceAlignmentLocked,
               "three consistent matches lock source alignment")
        expect(snapshot.aecBufferDelayMilliseconds == 30,
               "AEC buffer delay remains presentation-derived")
        expect(backend.recordedDelays.last == 30,
               "source alignment is not forced into the AEC backend")
        expect(snapshot.renderCaptureCorrelation > 0.99,
               "render/capture correlation is diagnosed")
        expect(snapshot.rawCaptureRMS > snapshot.processedCaptureRMS,
               "raw and processed capture energy are diagnosed")
        expect(snapshot.residualRenderCorrelation > 0.99,
               "residual render correlation is diagnosed")

        host.updateDelay(
            outputPresentationLatencySeconds: 0.001,
            capturePresentationLatencySeconds: 0.001
        )
        expect(host.snapshot().delayMilliseconds == 2,
               "presentation updates control only AEC buffer delay")
        expect(host.snapshot().sourceAlignmentDelayMilliseconds == 80,
               "presentation updates preserve source alignment")
    }

    #if DEBUG
    private static func testAcousticReplayCapture() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.updateDelay(
            outputPresentationLatencySeconds: 0.020,
            capturePresentationLatencySeconds: 0.010
        )
        let attemptID = UUID()
        expect(host.armAcousticReplayCapture(
            attemptID: attemptID,
            targetCaptureFrameCount: 3
        ), "DEBUG acoustic replay capture arms")
        host.playbackStarted()

        var rawSamples: [Float] = []
        for index in 0 ..< 3 {
            let frame = testSignal(
                seed: UInt32(1_700 + index),
                amplitude: 0.25
            )
            rawSamples.append(contentsOf: frame)
            host.processRender(
                frame,
                hostTimeNanoseconds:
                    2_000_000_000 + UInt64(index * 10_000_000)
            )
            _ = host.processCapture(
                frame,
                hostTimeNanoseconds:
                    2_080_000_000 + UInt64(index * 10_000_000)
            )
        }

        guard let capture = host.acousticReplayCaptureSnapshot() else {
            fatalError("FAILED: DEBUG acoustic replay snapshot exists")
        }
        expect(capture.attemptID == attemptID,
               "replay snapshot preserves attempt identity")
        expect(capture.captureFrames.count == 3 && capture.isSealed,
               "three 10 ms frames seal the bounded replay capture")
        expect(capture.isExactReplayReady,
               "clean pre-playback capture is exact-replay ready")
        expect(capture.durationMilliseconds == 30,
               "replay duration derives from exact 10 ms frames")
        expect(capture.rawMicrophoneSamples == rawSamples,
               "replay preserves exact pre-AEC microphone samples")
        expect(capture.chronologicalRenderSamples == rawSamples,
               "replay preserves chronological render callback input")
        expect(
            capture.aecCleanSamples == rawSamples.map { $0 * 0.5 },
            "replay preserves exact pre-gate AEC clean samples"
        )
        expect(capture.aecLinearSamples.count
                == 3 * MacSpeechAcousticEchoHost.linearOutputFrameSampleCount,
               "replay preserves exact AEC linear output")
        expect(capture.renderFrames.count == 3,
               "replay records each chronological render frame")
        expect(capture.audioCalls.count == 6,
               "replay records render and capture callback boundaries")
        expect(capture.controlEvents.map(\.kind) == [.playbackStarted],
               "replay records playback lifecycle in the event timeline")
        expect(capture.captureFrames.allSatisfy {
            $0.timingMatchAvailable
        },
               "every replay frame records timing-match availability")
        expect(capture.captureFrames.allSatisfy {
            abs(($0.timingDelayMilliseconds ?? 0) - 80) < 0.001
                && ($0.timingCorrelation ?? 0) > 0.99
        }, "replay records matched delay and correlation per frame")
        expect(capture.captureFrames.last?.sourceAlignmentLocked == true,
               "replay records per-frame alignment lock")
        expect(capture.captureFrames.map(\.inputClassification) == [
            .uncertain, .uncertain, .echoOnly
        ] && capture.captureFrames.allSatisfy { !$0.sourceGateOpen },
               "replay records three-frame trusted echo acquisition")
        expect(!host.armAcousticReplayCapture(
            attemptID: UUID(),
            targetCaptureFrameCount: 1
        ), "unexported replay capture cannot be overwritten")
        host.clearAcousticReplayCapture(matchingAttemptID: attemptID)
        expect(host.acousticReplayCaptureSnapshot() == nil,
               "matching replay capture clears exactly once")

        do {
            let encoded = try JSONEncoder().encode(capture.initialState)
            let decoded = try JSONDecoder().decode(
                MacSpeechAcousticReplayInitialStateSnapshot.self, from: encoded
            )
            expect(decoded.linearOutputDelaySamples == nil
                       && decoded.processedOutputDelaySamples == nil,
                   "legacy replay metadata keeps zero-delay behavior")
            let delayedHost = MacSpeechAcousticEchoHost(
                mode: .webRTCAEC3,
                backend: FakeAECBackend(
                    linearOutputDelaySamples: 72, processedOutputDelaySamples: 144
                )
            )
            _ = delayedHost.configure()
            expect(!delayedHost.restoreAcousticReplayInitialState(decoded),
                   "replay rejects a backend with different output timing")
            _ = delayedHost.armAcousticReplayCapture(
                attemptID: UUID(), targetCaptureFrameCount: 1
            )
            guard let state = delayedHost.acousticReplayCaptureSnapshot()?.initialState
            else { fatalError("FAILED: delayed replay initial state exists") }
            let roundTrip = try JSONDecoder().decode(
                MacSpeechAcousticReplayInitialStateSnapshot.self,
                from: JSONEncoder().encode(state)
            )
            expect(roundTrip.linearOutputDelaySamples == 72
                       && roundTrip.processedOutputDelaySamples == 144,
                   "replay records both AEC output delays")
        } catch {
            fatalError("FAILED: AEC output timing metadata round trip: \(error)")
        }
    }
    #endif

    private static func testFutureRenderTimestampIsCaptureCausal() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        host.processRender(
            [Float](repeating: 0.25, count: 480),
            hostTimeNanoseconds: 2_000_000_000
        )

        var projected: [UInt64] = []
        for captureTimestamp in [
            UInt64(1_000_000_000),
            UInt64(1_500_000_000),
            UInt64(2_500_000_000)
        ] {
            _ = host.processCapture(
                [Float](repeating: 0, count: 480),
                hostTimeNanoseconds: captureTimestamp
            )
            let snapshot = host.acousticObservationSnapshot()
            guard let audible = snapshot.lastAudibleRenderHostTimeNanoseconds,
                  let capture = snapshot.captureHostTimeNanoseconds else {
                fatalError("FAILED: causal render fixture timestamps missing")
            }
            projected.append(audible)
            expect(audible <= capture,
                   "audible render projection never leads capture time")
        }
        expect(projected == [
            1_000_000_000,
            1_500_000_000,
            2_000_000_000
        ], "future render watermark is clamped monotonically at capture time")
    }

    private static func testTimingHistoryIsBoundedAndReset() {
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: FakeAECBackend()
        )
        _ = host.configure()
        host.playbackStarted()
        let frame = (0 ..< 480).map {
            sin(Float($0) * 0.04) * 0.2
        }
        for index in 0 ..< 80 {
            host.processRender(
                frame,
                hostTimeNanoseconds:
                    1_000_000_000 + UInt64(index * 10_000_000)
            )
        }
        expect(host.snapshot().renderTimingFrameCount == 50,
               "timing history is bounded to the 500 ms delay window")
        host.playbackCompleted()
        expect(host.snapshot().renderTimingFrameCount == 0,
               "playback completion clears old render timing")
    }

    private static func testTimingLockDoesNotJumpOnRepeatedRender() {
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: FakeAECBackend()
        )
        _ = host.configure()
        host.playbackStarted()
        let repeated = testSignal(seed: 2_500, amplitude: 0.3)
        let start: UInt64 = 30_000_000_000
        for index in 0 ..< 20 {
            let renderTime = start + UInt64(index * 10_000_000)
            host.processRender(repeated, hostTimeNanoseconds: renderTime)
            _ = host.processCapture(
                repeated,
                hostTimeNanoseconds: renderTime + 80_000_000
            )
        }

        let snapshot = host.snapshot()
        expect(snapshot.sourceAlignmentLocked
                   && snapshot.sourceAlignmentDelayMilliseconds == 80,
               "repeated resident speech cannot move a locked alignment")
        expect(snapshot.sourceAlignmentMissCount == 0
                   && snapshot.sourceAlignmentReacquisitionCount == 0,
               "stable repeated speech does not trigger reacquisition")
    }

    private static func testUnsupportedExpectedTimingDiscoversActualPath() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.updateDelay(
            outputPresentationLatencySeconds: 0.08,
            capturePresentationLatencySeconds: 0
        )
        host.playbackStarted()
        let start: UInt64 = 35_000_000_000
        let renderFrames = (0 ..< 30).map { index in
            testSignal(seed: UInt32(2_550 + index), amplitude: 0.3)
        }
        for (index, frame) in renderFrames.enumerated() {
            host.processRender(
                frame,
                hostTimeNanoseconds:
                    start + UInt64(index) * 10_000_000
            )
        }

        for index in 0 ..< 10 {
            _ = host.processCapture(
                renderFrames[16 + index],
                hostTimeNanoseconds:
                    start + UInt64(30 + index) * 10_000_000
            )
        }

        let snapshot = host.snapshot()
        expect(snapshot.sourceAlignmentLocked
                   && snapshot.sourceAlignmentDelayMilliseconds == 140,
               "unsupported expected delay discovers the actual echo path")
        expect(!snapshot.sourceGateOpen
                   && snapshot.sourceForwardedFrameCount == 0,
               "timing reacquisition keeps resident-only PCM suppressed")
    }

    private static func testTimingLockReacquiresShiftedPath() {
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: FakeAECBackend()
        )
        _ = host.configure()
        host.playbackStarted()
        let start: UInt64 = 40_000_000_000
        for index in 0 ..< 3 {
            let frame = testSignal(
                seed: UInt32(2_600 + index),
                amplitude: 0.3
            )
            let renderTime = start + UInt64(index * 10_000_000)
            host.processRender(frame, hostTimeNanoseconds: renderTime)
            _ = host.processCapture(
                frame,
                hostTimeNanoseconds: renderTime + 80_000_000
            )
        }
        expect(host.snapshot().sourceAlignmentDelayMilliseconds == 80,
               "initial path establishes the first timing lock")

        for index in 3 ..< 11 {
            let frame = testSignal(
                seed: UInt32(2_600 + index),
                amplitude: 0.3
            )
            let renderTime = start + UInt64(index * 10_000_000)
            host.processRender(frame, hostTimeNanoseconds: renderTime)
            _ = host.processCapture(
                frame,
                hostTimeNanoseconds: renderTime + 140_000_000
            )
        }

        let snapshot = host.snapshot()
        expect(snapshot.sourceAlignmentLocked
                   && snapshot.sourceAlignmentDelayMilliseconds == 140,
               "bounded misses reacquire a genuinely shifted path")
        expect(snapshot.sourceAlignmentMissCount == 5
                   && snapshot.sourceAlignmentReacquisitionCount == 1,
               "timing lock exposes misses and one reacquisition")
    }

    private static func testSourceGateEpochDiagnosticsAreBounded() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        var hostTime: UInt64 = 20_000_000_000
        for playback in 0 ..< 18 {
            host.playbackStarted()
            let render = testSignal(
                seed: UInt32(1_000 + playback),
                amplitude: 0.3
            )
            let user = testSignal(
                seed: UInt32(2_000 + playback),
                amplitude: 0.2
            )
            let mixedCapture = zip(render, user).map { sample in
                sample.0 * 0.8 + sample.1
            }
            backend.setCaptureOutput(user)
            host.processRender(render, hostTimeNanoseconds: hostTime)
            for frame in 0 ..< 3 {
                _ = host.processCapture(
                    mixedCapture,
                    hostTimeNanoseconds:
                        hostTime + 80_000_000
                            + UInt64(frame * 10_000_000)
                )
            }
            host.playbackCompleted()
            hostTime += 1_000_000_000
        }

        let epochs = host.snapshot().sourceGateEpochs
        expect(epochs.count == 16,
               "source gate epoch diagnostics use a bounded ring")
        expect(epochs.first?.playbackSequence == 3
                   && epochs.last?.playbackSequence == 18,
               "source gate epoch ring retains the newest playbacks")
        expect(epochs.last?.forwardedFrameCount == 3
                   && epochs.last?.totalFrameCount == 3,
               "source gate epoch records released pre-roll")
        expect(epochs.last?.closeReason == .playbackLifecycle
                   && epochs.last?.closedAtCaptureFrame != nil,
               "source gate epoch records deterministic closure")
        expect(epochs.last?.aecBufferDelayMillisecondsAtOpen == 0
                   && epochs.last?.sourceAlignmentDelayMillisecondsAtOpen
                       == nil,
               "near-end output cannot manufacture an alignment lock")
    }

    private static func testEchoOnlySourceGate() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 1, amplitude: 0.3)
        host.processRender(render, hostTimeNanoseconds: 1_000_000_000)

        let output = host.processCapture(
            render,
            hostTimeNanoseconds: 1_080_000_000
        )
        let snapshot = host.snapshot()
        expect(isSilence(output),
               "aligned resident-only echo becomes one silence frame")
        expect(snapshot.inputClassification == .uncertain,
               "one historical echo peak has no classification authority")
        expect(!snapshot.sourceGateOpen,
               "resident-only echo keeps the source gate closed")
        expect(snapshot.sourceGatePreRollFrameCount == 0,
               "resident-only echo is not retained as user pre-roll")
        expect(snapshot.uncertainFrameCount == 1
                   && snapshot.sourceSuppressedFrameCount == 1,
               "untrusted resident evidence remains suppressed")
        expect(snapshot.sourceTimingCandidateFrameCount == 1,
               "resident-only diagnostics count aligned timing")
        expect(snapshot.mode == .webRTCAEC3,
               "source gating does not replace a healthy AEC backend")
    }

    private static func testNearEndSourceGateAndPreRoll() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 2, amplitude: 0.3)
        let user = testSignal(seed: 3, amplitude: 0.25)
        host.processRender(render, hostTimeNanoseconds: 2_000_000_000)
        backend.setCaptureOutput(user)

        for index in 0 ..< 2 {
            let output = host.processCapture(
                user,
                hostTimeNanoseconds:
                    2_080_000_000 + UInt64(index * 10_000_000)
            )
            expect(output.isEmpty,
                   "near-end speech waits for bounded confirmation")
        }
        let confirmed = host.processCapture(
            user,
            hostTimeNanoseconds: 2_100_000_000
        )
        var snapshot = host.snapshot()
        expect(confirmed.count == 3 * 480,
               "confirmed near-end speech releases its pre-roll")
        expect(snapshot.inputClassification == .nearEndSpeech,
               "independent near-end PCM is classified as user speech")
        expect(snapshot.sourceGateOpen,
               "confirmed near-end speech opens the source gate")
        expect(snapshot.sourceGatePreRollFrameCount == 0,
               "released near-end pre-roll is drained")
        expect(host.processCapture(
            user,
            hostTimeNanoseconds: 2_110_000_000
        ).count == 480, "open source gate forwards near-end speech")

        backend.setCaptureOutput(nil)
        expect(!isSilence(host.processCapture(
            render,
            hostTimeNanoseconds: 2_120_000_000
        )), "confirmed speech epoch stays continuous through one echo frame")
        snapshot = host.snapshot()
        expect(snapshot.inputClassification == .uncertain
                   && snapshot.sourceGateOpen
                   && snapshot.sourceGateCloseCount == 0,
               "one untrusted echo frame cannot fragment confirmed speech")
        for index in 1 ..< 19 {
            expect(!isSilence(host.processCapture(
                render,
                hostTimeNanoseconds:
                    2_120_000_000 + UInt64(index * 10_000_000)
            )), "bounded hangover does not fragment the speech epoch")
        }
        expect(isSilence(host.processCapture(
            render,
            hostTimeNanoseconds: 2_310_000_000
        )), "sustained resident-only evidence closes the speech epoch")
        snapshot = host.snapshot()
        expect(!snapshot.sourceGateOpen,
               "200 ms without user evidence closes the source gate")
        expect(snapshot.lastSourceGateCloseReason == .nonUserHangover,
               "bounded non-user closure reports its reason independently")
        expect(snapshot.nearEndSpeechFrameCount == 4
                   && snapshot.sourceForwardedFrameCount == 23,
               "epoch diagnostics count pre-roll and continuous hangover")
        expect(snapshot.sourceGateOpenCount == 1
                   && snapshot.sourceGateCloseCount == 1,
               "source gate transitions are counted")
        expect(snapshot.sourceGateEpochs.last?.totalFrameCount == 24
                   && snapshot.sourceGateEpochs.last?.forwardedFrameCount
                       == 23
                   && snapshot.sourceGateEpochs.last?.suppressedFrameCount
                       == 1,
               "gate epoch records one continuous forwarded speech run")
    }

    private static func testDoubleTalkSourceGate() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 4, amplitude: 0.35)
        let user = testSignal(seed: 5, amplitude: 0.2)
        let mixedCapture = zip(render, user).map { sample in
            sample.0 * 0.8 + sample.1
        }
        host.processRender(render, hostTimeNanoseconds: 3_000_000_000)
        backend.setCaptureOutput(user)

        var output: [Float] = []
        for index in 0 ..< 3 {
            output = host.processCapture(
                mixedCapture,
                hostTimeNanoseconds:
                    3_090_000_000 + UInt64(index * 10_000_000)
            )
        }
        var snapshot = host.snapshot()
        expect(output.count == 3 * 480,
               "confirmed double-talk releases near-end pre-roll")
        expect(snapshot.inputClassification == .doubleTalk,
               "echo plus preserved near-end PCM is double-talk")
        expect(snapshot.sourceGateOpen,
               "double-talk remains eligible for normal barge-in")
        expect(snapshot.doubleTalkFrameCount == 3
                   && snapshot.sourceForwardedFrameCount == 3,
               "double-talk diagnostics count forwarded pre-roll")

        backend.setCaptureOutput(user)
        for _ in 0 ..< 5 {
            let continued = host.processCapture(user)
            expect(continued.count == 480 && !isSilence(continued),
                   "energetic uncertainty continues a confirmed user epoch")
        }
        snapshot = host.snapshot()
        expect(snapshot.sourceGateOpen
                   && snapshot.sourceForwardedFrameCount == 8
                   && snapshot.maximumContinuousSourceForwardedFrameCount
                       == 8,
               "confirmed user audio remains continuous across uncertainty")

        backend.setCaptureOutput(nil)
        for index in 0 ..< 14 {
            expect(!isSilence(host.processCapture(
                render,
                hostTimeNanoseconds:
                    3_170_000_000 + UInt64(index * 10_000_000)
            )), "confirmed barge-in stays continuous during hangover")
        }
        expect(isSilence(host.processCapture(
            render,
            hostTimeNanoseconds: 3_310_000_000
        )), "bounded hangover closes after sustained resident evidence")
        snapshot = host.snapshot()
        expect(!snapshot.sourceGateOpen
                   && snapshot.sourceGateCloseCount == 1
                   && snapshot.lastSourceGateCloseReason
                       == .nonUserHangover,
               "bounded non-user hangover closes the post-barge gate")
    }

    private static func testDelayedAECOutputEvidence() {
        func delayed(_ samples: [Float], by count: Int) -> [Float] {
            (0 ..< samples.count).map {
                samples[($0 + samples.count - count) % samples.count]
            }
        }
        for nearEndPresent in [false, true] {
            for echoGain: Float in [1, 2] {
                let backend = FakeAECBackend(
                    linearOutputDelaySamples: 72, processedOutputDelaySamples: 144
                )
                let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
                _ = host.configure()
                host.playbackStarted()
                let renderLow = Array(testSignal(seed: 981, amplitude: 0.4 * echoGain).prefix(160))
                let userLow = Array(testSignal(seed: 752, amplitude: 0.25).prefix(160))
                let render = renderLow.flatMap { [$0, $0, $0] }
                let linear = nearEndPresent ? userLow : renderLow.map { $0 * 0.8 }
                let clean = nearEndPresent ? userLow : renderLow.map { $0 * 0.2 }
                let processed = delayed(clean, by: 144).flatMap { [$0, $0, $0] }
                backend.setLinearOutput(delayed(linear, by: 72))
                backend.setCaptureOutput(processed)
                let raw = zip(renderLow, userLow).flatMap { echo, user -> [Float] in
                    let sample = echo * 0.8 + (nearEndPresent ? user : 0)
                    return [sample, sample, sample]
                }
                var output: [Float] = []
                for index in 0 ..< 10 {
                    let time = UInt64(1_000_000_000 + index * 10_000_000)
                    host.processRender(render, hostTimeNanoseconds: time)
                    output = host.processCapture(raw, hostTimeNanoseconds: time + 80_000_000)
                    if index == 0 {
                        expect(!host.snapshot().sourceGateOpen,
                               "missing past render cannot establish near-end evidence")
                    }
                    if !nearEndPresent {
                        expect(!host.snapshot().sourceGateOpen && isSilence(output),
                               "energetic delayed residual echo never opens the source gate")
                    }
                }
                let state = host.snapshot()
                expect(state.processedLinearCorrelation > 0.99,
                       "linear and processed evidence compares the same source samples")
                if nearEndPresent {
                    expect(state.sourceGateOpen && state.inputClassification == .doubleTalk,
                           "independent near-end speech survives delayed AEC evidence")
                    expect(output == processed,
                           "timing compensation changes evidence without shifting output PCM")
                } else {
                    expect(state.residualRenderCorrelation > 0.99
                               && state.linearRenderCorrelation > 0.99,
                           "both delayed echo outputs retain their render association")
                    expect(state.sourceForwardedFrameCount == 0,
                           "delayed residual echo cannot become a user epoch")
                }
            }
        }
    }

    private static func testMissingAECReferenceCannotRenewHangover() {
        let backend = FakeAECBackend(
            linearOutputDelaySamples: 72, processedOutputDelaySamples: 144
        )
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
        _ = host.configure()
        host.playbackStarted()
        let renderLow = Array(testSignal(seed: 981, amplitude: 0.4).prefix(160))
        let userLow = Array(testSignal(seed: 752, amplitude: 0.25).prefix(160))
        let render = renderLow.flatMap { [$0, $0, $0] }
        var time: UInt64 = 2_000_000_000
        for index in 0 ..< 53 {
            let speech = index >= 10
            let quiet = index >= 13 && index % 2 == 0
            let source = quiet ? [Float](repeating: 0, count: 160)
                : speech ? userLow : renderLow.map { $0 * 0.1 }
            let linear = (0 ..< 160).map { source[($0 + 160 - 72) % 160] }
            let clean = (0 ..< 160).flatMap { offset -> [Float] in
                let sample = source[(offset + 160 - 144) % 160]
                return [sample, sample, sample]
            }
            backend.setLinearOutput(linear)
            backend.setCaptureOutput(clean)
            let raw = zip(renderLow, userLow).flatMap { echo, user -> [Float] in
                let sample = quiet ? 0 : echo * 0.9 + (speech ? user : 0)
                return [sample, sample, sample]
            }
            // A discontinuous render timeline has no usable delayed reference.
            time += index < 13 ? 10_000_000 : 20_000_000
            host.processRender(render, hostTimeNanoseconds: time)
            _ = host.processCapture(raw, hostTimeNanoseconds: time + 80_000_000)
            if index == 12 {
                expect(host.snapshot().sourceGateOpen
                           && host.snapshot().residualEchoBaselineFrozen,
                       "fixture opens a valid user epoch with a mature baseline")
            }
        }
        expect(!host.snapshot().sourceGateOpen,
               "missing references mixed with silence cannot renew user hangover")
        expect(host.snapshot().maximumSourceGateOpenFrameCount <= 23,
               "reference loss retains the existing bounded hangover")
    }

    private static func testAbortedSourceGatePreRollPreservesCadence() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 17, amplitude: 0.35)
        let user = testSignal(seed: 18, amplitude: 0.22)
        let renderTime: UInt64 = 2_500_000_000
        host.processRender(render, hostTimeNanoseconds: renderTime)
        backend.setCaptureOutput(user)
        for index in 0 ..< 2 {
            expect(host.processCapture(
                user,
                hostTimeNanoseconds:
                    renderTime + 80_000_000
                        + UInt64(index * 10_000_000)
            ).isEmpty, "candidate frames wait for source confirmation")
        }

        backend.setCaptureOutput(nil)
        let aborted = host.processCapture(
            render,
            hostTimeNanoseconds: renderTime + 100_000_000
        )
        let snapshot = host.snapshot()
        expect(isSilence(aborted, frameCount: 3),
               "aborted pre-roll is replaced by equal-duration silence")
        expect(snapshot.sourceForwardedFrameCount == 0
                   && snapshot.sourceSuppressedFrameCount == 3
                   && snapshot.sourceGatePreRollFrameCount == 0,
               "aborted source evidence never leaks resident audio")
    }

    private static func testRouteIndependentBargeInHysteresis() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 15, amplitude: 0.55)
        let user = testSignal(seed: 16, amplitude: 0.22)
        let mixedCapture = zip(render, user).map { sample in
            sample.0 * 0.85 + sample.1
        }
        var renderTime: UInt64 = 8_000_000_000
        backend.setCaptureOutput(user)
        var opened: [Float] = []
        for _ in 0 ..< 3 {
            host.processRender(render, hostTimeNanoseconds: renderTime)
            opened = host.processCapture(
                mixedCapture,
                hostTimeNanoseconds: renderTime + 80_000_000
            )
            renderTime += 10_000_000
        }
        expect(opened.count == 3 * 480,
               "external-like double-talk opens the source gate")

        for _ in 0 ..< 4 {
            backend.setCaptureOutput(user)
            for _ in 0 ..< 4 {
                let continued = host.processCapture(user)
                expect(continued.count == 480 && !isSilence(continued),
                       "energetic uncertain user audio stays continuous")
            }

            backend.setCaptureOutput(nil)
            host.processRender(render, hostTimeNanoseconds: renderTime)
            expect(!isSilence(host.processCapture(
                render,
                hostTimeNanoseconds: renderTime + 80_000_000
            )), "interleaved evidence does not fragment barge-in")
            renderTime += 10_000_000

            backend.setCaptureOutput(user)
            host.processRender(render, hostTimeNanoseconds: renderTime)
            let reaffirmed = host.processCapture(
                mixedCapture,
                hostTimeNanoseconds: renderTime + 80_000_000
            )
            expect(reaffirmed.count == 480 && !isSilence(reaffirmed),
                   "fresh double-talk evidence refreshes the user epoch")
            renderTime += 10_000_000
        }

        var snapshot = host.snapshot()
        expect(snapshot.sourceGateOpen,
               "classification churn does not fragment barge-in")
        expect(snapshot.maximumContinuousSourceForwardedFrameCount >= 7,
               "diagnostics retain the longest useful user run")

        backend.setCaptureOutput(nil)
        for index in 0 ..< 20 {
            host.processRender(render, hostTimeNanoseconds: renderTime)
            let tail = host.processCapture(
                render,
                hostTimeNanoseconds: renderTime + 80_000_000
            )
            expect(index == 19 ? isSilence(tail) : !isSilence(tail),
                   "resident-only tail closes after bounded hangover")
            renderTime += 10_000_000
        }
        snapshot = host.snapshot()
        expect(!snapshot.sourceGateOpen
                   && snapshot.lastSourceGateCloseReason
                       == .nonUserHangover,
               "resident-only tail deterministically closes the gate")
    }

    private static func testAdaptiveExternalOutputDoubleTalk() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let baseRender = testSignal(seed: 19, amplitude: 0.55)
        let user = testSignal(seed: 20, amplitude: 0.11)
        let playbackScales: [Float] = [
            0.6, 0.8, 1.0, 1.2, 0.7,
            1.1, 0.9, 1.3, 0.75, 1.0
        ]
        var renderTime: UInt64 = 9_000_000_000

        for (index, scale) in playbackScales.enumerated() {
            let render = testSignal(
                seed: UInt32(100 + index),
                amplitude: 0.55
            ).map { $0 * scale }
            backend.setCaptureOutput(render.map { $0 * 0.12 })
            host.processRender(render, hostTimeNanoseconds: renderTime)
            expect(isSilence(host.processCapture(
                render.map { $0 * 0.9 },
                hostTimeNanoseconds: renderTime + 146_000_000
            )), "adaptive baseline keeps resident-only PCM zeroed")
            renderTime += 10_000_000
        }

        var snapshot = host.snapshot()
        expect(snapshot.residualEchoBaselineFrameCount == 8,
               "trusted resident frames establish the route baseline")
        expect(abs(snapshot.rawEchoGainBaseline - 0.9) < 0.001,
               "raw echo coupling is normalized against render level")
        expect(abs(snapshot.residualEchoGainBaseline - 0.12) < 0.001,
               "normalized residual gain ignores playback level")
        expect(snapshot.adaptiveDoubleTalkFrameCount == 0
                   && snapshot.sourceGateOpenCount == 0,
               "baseline learning cannot open the user gate")

        let render = baseRender
        let residualEcho = render.map { $0 * 0.12 }
        let rawDoubleTalk = zip(render, user).map { sample in
            sample.0 * 0.9 + sample.1
        }
        let processedDoubleTalk = zip(residualEcho, user).map { sample in
            sample.0 + sample.1
        }
        backend.setCaptureOutput(processedDoubleTalk)
        var opened: [Float] = []
        for _ in 0 ..< 3 {
            host.processRender(render, hostTimeNanoseconds: renderTime)
            opened = host.processCapture(
                rawDoubleTalk,
                hostTimeNanoseconds: renderTime + 146_000_000
            )
            renderTime += 10_000_000
        }
        snapshot = host.snapshot()
        expect(opened.count == 3 * 480
                   && snapshot.inputClassification == .doubleTalk,
               "adaptive residual energy opens external-output barge-in")
        expect(snapshot.residualRenderCorrelation > 0.25,
               "fixture exercises the former fixed-correlation rejection")

        for _ in 0 ..< 30 {
            host.processRender(render, hostTimeNanoseconds: renderTime)
            let continued = host.processCapture(
                rawDoubleTalk,
                hostTimeNanoseconds: renderTime + 146_000_000
            )
            expect(continued.count == 480 && !isSilence(continued),
                   "adaptive double-talk remains continuous for VAD")
            renderTime += 10_000_000
        }
        snapshot = host.snapshot()
        expect(snapshot.adaptiveEvidenceCandidateFrameCount == 33
                   && snapshot.adaptiveDoubleTalkFrameCount == 33,
               "adaptive double-talk decisions remain diagnosable")
        expect(snapshot.maximumAdaptiveRawExcessRMS > 0.012
                   && snapshot.maximumAdaptiveResidualExcessRMS > 0.012,
               "both raw and cleaned near-end excess are measured")
        expect(snapshot.maximumSourceGateOpenFrameCount == 33
                   && snapshot.maximumContinuousSourceForwardedFrameCount
                       == 33,
               "external-output user audio reaches a 330 ms run")

        backend.setLinearOutput([Float](repeating: 0, count: 160))
        for index in 0 ..< 30 {
            host.processRender(render, hostTimeNanoseconds: renderTime)
            let continued = host.processCapture(
                rawDoubleTalk,
                hostTimeNanoseconds: renderTime + 146_000_000
            )
            expect(index < 19
                    ? continued.count == 480 && !isSilence(continued)
                    : isSilence(continued),
                   "weak-only continuation closes after the bounded window")
            renderTime += 10_000_000
        }
        snapshot = host.snapshot()
        expect(snapshot.inputClassification == .uncertain
                   && !snapshot.sourceGateOpen
                   && snapshot.lastSourceGateCloseReason
                       == .sourceEvidenceReset,
               "uncertain continuation cannot keep the gate open forever")
        expect(snapshot.adaptiveEvidenceCandidateFrameCount == 63
                   && snapshot.adaptiveDoubleTalkFrameCount == 33,
               "continuation reuses adaptive evidence without false double-talk")
        expect(snapshot.maximumSourceGateOpenFrameCount == 53
                   && snapshot.maximumContinuousSourceForwardedFrameCount
                       == 52,
               "weak-only forwarding is bounded to the existing reset window")

        backend.setCaptureOutput(residualEcho)
        backend.setLinearOutput(linearOutput(residualEcho))
        for _ in 0 ..< 20 {
            host.processRender(render, hostTimeNanoseconds: renderTime)
            let tail = host.processCapture(
                render.map { $0 * 0.9 },
                hostTimeNanoseconds: renderTime + 146_000_000
            )
            expect(isSilence(tail),
                   "resident-only tail stays suppressed after bounded closure")
            renderTime += 10_000_000
        }
        snapshot = host.snapshot()
        expect(!snapshot.sourceGateOpen
                   && snapshot.lastSourceGateCloseReason
                       == .sourceEvidenceReset,
               "resident-only tail cannot reopen the closed user epoch")
    }

    private static func testBaselineFreezesBeforeQuieterUserSpeech() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        var renderTime: UInt64 = 50_000_000_000

        for index in 0 ..< 7 {
            let render = testSignal(
                seed: UInt32(3_000 + index),
                amplitude: 0.55
            )
            let residualEcho = render.map { $0 * 0.1 }
            backend.setCaptureOutput(residualEcho)
            backend.setLinearOutput(linearOutput(residualEcho))
            host.processRender(render, hostTimeNanoseconds: renderTime)
            expect(isSilence(host.processCapture(
                render.map { $0 * 0.9 },
                hostTimeNanoseconds: renderTime + 120_000_000
            )), "high-confidence resident frames train the echo baseline")
            renderTime += 10_000_000
        }

        let trained = host.snapshot()
        expect(trained.residualEchoBaselineFrameCount == 5
                   && !trained.residualEchoBaselineFrozen,
               "five trusted resident frames establish an unfrozen baseline")
        let rawBaseline = trained.rawEchoGainBaseline
        let residualBaseline = trained.residualEchoGainBaseline
        let linearBaseline = trained.linearAECOutputGainBaseline

        var opened: [Float] = []
        for index in 0 ..< 3 {
            let render = testSignal(
                seed: UInt32(3_100 + index),
                amplitude: 0.55
            )
            let user = testSignal(
                seed: UInt32(3_200 + index),
                amplitude: 0.09
            )
            let rawDoubleTalk = zip(render, user).map { sample in
                sample.0 * 0.9 + sample.1
            }
            let cleanedDoubleTalk = zip(render, user).map { sample in
                sample.0 * 0.1 + sample.1
            }
            backend.setCaptureOutput(cleanedDoubleTalk)
            backend.setLinearOutput(linearOutput(cleanedDoubleTalk))
            host.processRender(render, hostTimeNanoseconds: renderTime)
            opened = host.processCapture(
                rawDoubleTalk,
                hostTimeNanoseconds: renderTime + 120_000_000
            )
            renderTime += 10_000_000
        }

        let snapshot = host.snapshot()
        expect(opened.count == 3 * 480 && snapshot.sourceGateOpen,
               "a user quieter than raw echo still opens barge-in")
        expect(snapshot.residualEchoBaselineFrozen
                   && snapshot.residualEchoBaselineFreezeCount == 1,
               "first near-end excess freezes the playback baseline")
        expect(snapshot.residualEchoBaselineFrameCount == 5
                   && snapshot.rawEchoGainBaseline == rawBaseline
                   && snapshot.residualEchoGainBaseline == residualBaseline
                   && snapshot.linearAECOutputGainBaseline == linearBaseline,
               "double-talk cannot poison any learned echo gain")
    }

    private static func testAbortedCandidateDoesNotFreezeUntrainedBaseline() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
        _ = host.configure()
        host.playbackStarted()
        var renderTime: UInt64 = 60_000_000_000
        func capture(index: Int, nearEnd: Bool) {
            let render = testSignal(seed: UInt32(4_000 + index), amplitude: 0.55)
            let user = testSignal(seed: UInt32(5_000 + index), amplitude: 0.2)
            let clean = nearEnd ? user : render.map { $0 * 0.1 }
            backend.setCaptureOutput(clean)
            backend.setLinearOutput(linearOutput(clean))
            host.processRender(render, hostTimeNanoseconds: renderTime)
            _ = host.processCapture(zip(render, user).map {
                $0.0 * 0.9 + (nearEnd ? $0.1 : 0)
            }, hostTimeNanoseconds: renderTime + 120_000_000)
            renderTime += 10_000_000
        }
        for index in 0 ..< 4 { capture(index: index, nearEnd: false) }
        expect(host.snapshot().residualEchoBaselineFrameCount == 2,
               "fixture has an incomplete two-frame echo baseline")
        capture(index: 4, nearEnd: true)
        expect(host.snapshot().sourceGatePreRollFrameCount == 1
                   && !host.snapshot().sourceGateOpen,
               "single near-end candidate has no user epoch ownership")
        capture(index: 5, nearEnd: false)
        expect(host.snapshot().sourceGatePreRollFrameCount == 0
                   && host.snapshot().sourceForwardedFrameCount == 0,
               "aborted near-end candidate is silenced")
        for index in 6 ..< 9 { capture(index: index, nearEnd: false) }
        expect(host.snapshot().residualEchoBaselineFrameCount == 5
                   && !host.snapshot().residualEchoBaselineFrozen,
               "trusted echo can finish training after an aborted candidate")
        for index in 9 ..< 12 { capture(index: index, nearEnd: true) }
        expect(host.snapshot().sourceGateOpen
                   && host.snapshot().residualEchoBaselineFrozen
                   && host.snapshot().residualEchoBaselineFrameCount == 5,
               "confirmed speech preserves the completed echo baseline")
    }

    private static func testAdaptiveGateRejectsResidualEchoVariation() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        var renderTime: UInt64 = 10_000_000_000

        for index in 0 ..< 10 {
            let render = testSignal(
                seed: UInt32(200 + index),
                amplitude: 0.55
            )
            let artifact = testSignal(
                seed: UInt32(300 + index),
                amplitude: 0.55
            )
            let processedEcho = zip(render, artifact).map { sample in
                sample.0 * 0.04 + sample.1 * 0.10
            }
            backend.setCaptureOutput(processedEcho)
            backend.setLinearOutput(linearOutput(
                render.map { $0 * 0.04 }
            ))
            host.processRender(render, hostTimeNanoseconds: renderTime)
            expect(isSilence(host.processCapture(
                render.map { $0 * 0.9 },
                hostTimeNanoseconds: renderTime + 146_000_000
            )), "decorrelated residual echo establishes a safe baseline")
            renderTime += 10_000_000
        }

        for index in 0 ..< 10 {
            let render = testSignal(
                seed: UInt32(400 + index),
                amplitude: 0.55
            )
            let artifact = testSignal(
                seed: UInt32(500 + index),
                amplitude: 0.55
            )
            let processedEcho = zip(render, artifact).map { sample in
                sample.0 * 0.04 + sample.1 * 0.11
            }
            backend.setCaptureOutput(processedEcho)
            backend.setLinearOutput(linearOutput(
                render.map { $0 * 0.04 }
            ))
            host.processRender(render, hostTimeNanoseconds: renderTime)
            expect(isSilence(host.processCapture(
                render.map { $0 * 0.9 },
                hostTimeNanoseconds: renderTime + 146_000_000
            )), "residual-only variation cannot become double-talk")
            renderTime += 10_000_000
        }

        let snapshot = host.snapshot()
        expect(snapshot.residualRenderCorrelation > 0.25
                   && snapshot.residualRenderCorrelation < 0.65,
               "fixture reaches the adaptive residual-correlation band")
        expect(snapshot.adaptiveDoubleTalkFrameCount == 0
                   && snapshot.sourceGateOpenCount == 0
                   && snapshot.sourceForwardedFrameCount == 0,
               "raw echo evidence blocks residual-only false barge-in")
        expect(snapshot.linearRenderCorrelation > 0.9
                   && snapshot.processedLinearCorrelation < 0.65
                   && snapshot.adaptiveEvidenceCandidateFrameCount == 0,
               "linear AEC evidence rejects nonlinear residual variation")
    }

    private static func testMixedResidentRenderIsOneFarEndReference() {
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: FakeAECBackend()
        )
        _ = host.configure()
        host.playbackStarted()
        let firstResident = testSignal(seed: 11, amplitude: 0.25)
        let secondResident = testSignal(seed: 12, amplitude: 0.25)
        let finalMix = zip(firstResident, secondResident).map { sample in
            (sample.0 + sample.1) * 0.5
        }
        host.processRender(
            finalMix,
            hostTimeNanoseconds: 4_500_000_000
        )

        expect(isSilence(host.processCapture(
            finalMix,
            hostTimeNanoseconds: 4_580_000_000
        )), "final resident mix remains one zeroed far-end reference")
        let snapshot = host.snapshot()
        expect(snapshot.inputClassification == .uncertain
                   && snapshot.uncertainFrameCount == 1,
               "one mixed resident frame stays suppressed without authority")
    }

    private static func testLongLoudEchoStaysSuppressed() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let loudRender = testSignal(seed: 8, amplitude: 0.9)
        for index in 0 ..< 300 {
            let renderTime = 5_000_000_000
                + UInt64(index * 10_000_000)
            host.processRender(
                loudRender,
                hostTimeNanoseconds: renderTime
            )
            expect(isSilence(host.processCapture(
                loudRender,
                hostTimeNanoseconds: renderTime + 80_000_000
            )), "sustained loud resident echo stays zeroed")
        }

        var snapshot = host.snapshot()
        expect(snapshot.mode == .webRTCAEC3
                   && snapshot.fallbackCount == 0,
               "aligned loud echo does not destabilize AEC")
        expect(snapshot.echoOnlyFrameCount == 298
                   && snapshot.uncertainFrameCount == 2
                   && snapshot.sourceSuppressedFrameCount == 300,
               "long loud playback stays fully suppressed during lock-in")
        expect(snapshot.sourceTimingCandidateFrameCount == 300
                   && snapshot.sourceTimingUnavailableFrameCount == 0,
               "long loud playback retains timing evidence")
        expect(snapshot.sourceGateOpenCount == 0,
               "resident-only playback never opens the source gate")
        expect(snapshot.maximumContinuousSourceForwardedFrameCount == 0,
               "resident-only playback never emits nonzero source PCM")
        expect(snapshot.residualEchoBaselineFrameCount == 298
                   && abs(snapshot.residualEchoGainBaseline - 0.5) < 0.001,
               "resident-only playback learns a stable residual gain")
        expect(snapshot.adaptiveDoubleTalkFrameCount == 0
                   && snapshot.maximumSourceGateOpenFrameCount == 0,
               "loud resident-only PCM cannot satisfy adaptive evidence")

        host.resetDiagnostics()
        snapshot = host.snapshot()
        expect(snapshot.echoOnlyFrameCount == 0
                   && snapshot.sourceSuppressedFrameCount == 0,
               "diagnostic reset clears aggregate counters")
        expect(snapshot.mode == .webRTCAEC3
                   && snapshot.isPlaybackActive,
               "diagnostic reset does not alter audio processing")
        expect(snapshot.residualEchoBaselineFrameCount == 298,
               "diagnostic reset preserves the live echo baseline")
    }

    private static func testSuppressedOnsetPreRollBoundaries() {
        for scenario in ["confirm", "expire-confirm", "abort", "weak-timeout", "stop", "generation", "route"] {
            let backend = FakeAECBackend()
            let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
            _ = host.configure()
            host.playbackStarted()
            let silence = [Float](repeating: 0, count: 480)
            let user = testSignal(seed: 7_100, amplitude: 0.25)
            let suppressed = user.map { $0 * 0.02 }
            var frame = 0
            func drive(_ kind: String) -> [MacSpeechAcousticCaptureSpan] {
                let time = UInt64(80_000_000_000) + UInt64(frame) * 10_000_000
                let far = testSignal(seed: UInt32(7_200 + frame), amplitude: 0.3)
                backend.setCaptureOutput(kind == "quiet" ? silence : kind == "strong" ? user : suppressed)
                backend.setLinearOutput(kind == "quiet" ? [Float](repeating: 0, count: 160) : linearOutput(user))
                host.processRender(far, hostTimeNanoseconds: time)
                frame += 1
                return host.processCaptureSpans(kind == "quiet" ? silence : user,
                                               hostTimeNanoseconds: time + 80_000_000)
            }
            for _ in 0..<50 { _ = drive("quiet") }
            expect(host.snapshot().renderCaptureIsolationEstablished, "onset fixture establishes acoustic isolation")
            var emitted = [MacSpeechAcousticCaptureSpan]()
            let weakCount = scenario == "expire-confirm" ? 18 : scenario == "weak-timeout" ? 30 : 8
            for _ in 0..<weakCount {
                emitted += drive("weak")
                let state = host.snapshot()
                expect(!state.sourceGateOpen && state.inputClassification == .uncertain,
                       "linear onset alone never opens or classifies a user turn")
                expect(state.sourceGatePreRollFrameCount <= 15, "pending onset stays within 150 ms")
            }
            expect(emitted.allSatisfy { isSilence($0.samples) }, "unconfirmed onset emits no microphone audio")
            if scenario == "confirm" || scenario == "expire-confirm" {
                for index in 0..<3 {
                    emitted += drive("strong")
                    expect(host.snapshot().sourceGateOpen == (index == 2),
                           "retained onset still requires three consecutive strong frames")
                }
                expect(emitted.count == weakCount + 3, "overflow silence and confirmed pre-roll preserve every source position")
                expect(emitted.map { $0.observation.captureFrameIndex } == Array(UInt64(51)...UInt64(frame)),
                       "retained frames keep source order without duplication")
                let released = emitted.filter { !isSilence($0.samples) }
                expect(released.count == min(weakCount + 3, 15), "only the bounded pending window is released")
                expect(released.dropLast(3).allSatisfy {
                    $0.samples == suppressed && $0.observation.inputClassification == .uncertain
                        && MacSpeechAudioActivityEvidenceKind.classify(observation: $0.observation) == .none
                }, "confirmed onset retains PCM and uncertain role evidence without reclassification")
                expect(host.snapshot().sourceGateOpenCount == 1, "one confirmation opens only one epoch")
                let epoch = host.acousticObservationSnapshot().sourceGateEpoch
                host.discardPendingCaptureForGenerationTransition()
                expect(host.snapshot().sourceGateOpen && host.acousticObservationSnapshot().sourceGateEpoch == epoch,
                       "generation fence preserves already-confirmed active near-end ownership")
                expect(drive("strong").count == 1, "generation fence does not cut continuing confirmed speech")
            } else if scenario == "abort" {
                for kind in ["strong", "strong", "weak", "strong", "strong", "quiet"] { emitted += drive(kind) }
                expect(!host.snapshot().sourceGateOpen && host.snapshot().sourceGateOpenCount == 0,
                       "weak interruption resets consecutive confirmation")
                expect(emitted.count == weakCount + 6 && emitted.allSatisfy { isSilence($0.samples) },
                       "aborted onset and partial confirmations become equal-duration silence")
            } else if scenario == "weak-timeout" {
                emitted += drive("quiet")
                expect(emitted.count == weakCount + 1 && emitted.allSatisfy { isSilence($0.samples) },
                       "weak-only pending audio expires without loss of cadence or user audio")
                expect(host.snapshot().sourceGateOpenCount == 0, "weak-only timeout creates no user epoch")
            } else {
                expect(host.snapshot().sourceGatePreRollFrameCount == 8, "lifecycle fixture has pending onset")
                if scenario == "stop" { host.playbackStopped() }
                else if scenario == "generation" { host.discardPendingCaptureForGenerationTransition() }
                else { host.routeWillRebuild() }
                expect(host.snapshot().sourceGatePreRollFrameCount == 0, "lifecycle boundary discards pending onset")
                expect(host.snapshot().sourceForwardedFrameCount == 0, "lifecycle reset does not release stale onset")
                if scenario == "generation" {
                    var fresh = [MacSpeechAcousticCaptureSpan]()
                    for _ in 0..<3 { fresh += drive("strong") }
                    expect(fresh.count == 3 && fresh.allSatisfy { $0.observation.captureFrameIndex > 58 },
                           "only fresh post-fence source frames reach the new confirmation")
                }
            }
        }
    }

    private static func testUncertainSourceGateIsBoundedAndRecoverable() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 6, amplitude: 0.3)
        let capture = testSignal(seed: 7, amplitude: 0.2)
        host.processRender(render, hostTimeNanoseconds: 4_000_000_000)
        backend.setCaptureOutput(capture)

        for _ in 0 ..< 15 {
            expect(isSilence(host.processCapture(capture)),
                   "unconfirmed capture preserves cadence with silence")
        }
        var snapshot = host.snapshot()
        expect(snapshot.inputClassification == .uncertain,
               "missing alignment evidence remains uncertain")
        expect(snapshot.sourceGatePreRollFrameCount == 0,
               "uncertain audio is not retained as user pre-roll")
        expect(!snapshot.sourceGateOpen,
               "uncertain capture never opens the source gate")
        expect(snapshot.mode == .webRTCAEC3,
               "150 ms uncertainty remains inside the pre-roll window")

        for _ in 0 ..< 5 {
            expect(isSilence(host.processCapture(capture)),
                   "sustained missing alignment remains zeroed")
        }
        snapshot = host.snapshot()
        expect(snapshot.mode == .webRTCAEC3
                   && snapshot.fallbackReason == nil,
               "alignment loss keeps AEC available for later barge-in")
        expect(snapshot.sourceTimingUnavailableFrameCount == 20,
               "alignment loss remains diagnosable")
        expect(snapshot.sourceSuppressedFrameCount == 20
                   && snapshot.sourceGatePreRollFrameCount == 0,
               "source protection accounts for each uncertain frame")

        let recoveryRenderTime: UInt64 = 4_300_000_000
        host.processRender(
            render,
            hostTimeNanoseconds: recoveryRenderTime
        )
        backend.setCaptureOutput(capture)
        var recovered: [Float] = []
        for index in 0 ..< 3 {
            recovered = host.processCapture(
                capture,
                hostTimeNanoseconds:
                    recoveryRenderTime + 80_000_000
                        + UInt64(index * 10_000_000)
            )
        }
        snapshot = host.snapshot()
        expect(recovered.count == 3 * 480
                   && snapshot.sourceGateOpen,
               "aligned near-end speech recovers without playback ending")

        host.playbackCompleted()
        snapshot = host.snapshot()
        expect(snapshot.sourceGatePreRollFrameCount == 0,
               "playback completion discards uncertain pre-roll")
        expect(host.processCapture(capture).count == 480,
               "capture resumes normally outside resident playback")
        expect(snapshot.fallbackCount == 0,
               "recoverable alignment loss is not a hard fallback")
    }

    private static func testRenderCaptureIsolationOpensOnlyForNearEnd() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let baseTime: UInt64 = 60_000_000_000
        let silence = [Float](repeating: 0, count: 480)
        var latestRender = [Float]()

        backend.setCaptureOutput(silence)
        backend.setLinearOutput([Float](repeating: 0, count: 160))
        for index in 0 ..< 50 {
            latestRender = testSignal(
                seed: UInt32(6_000 + index),
                amplitude: 0.3
            )
            let renderTime = baseTime + UInt64(index) * 10_000_000
            host.processRender(
                latestRender,
                hostTimeNanoseconds: renderTime
            )
            expect(isSilence(host.processCapture(
                silence,
                hostTimeNanoseconds: renderTime + 80_000_000
            )), "isolated render warm-up remains source-gated")
        }

        var snapshot = host.snapshot()
        expect(snapshot.renderCaptureIsolationEstablished,
               "500 ms quiet capture establishes render isolation")
        expect(snapshot.renderCaptureIsolationQuietFrameCount == 50
                   && snapshot.renderCaptureIsolationEstablishmentCount == 1,
               "render isolation warm-up is explicit and bounded")
        expect(!snapshot.sourceGateOpen,
               "render isolation evidence alone cannot open source gate")

        let independent = testSignal(seed: 6_100, amplitude: 0.25)
        let user = zip(latestRender, independent).map { sample in
            sample.0 * 0.3 + sample.1
        }
        backend.setCaptureOutput(user)
        backend.setLinearOutput([Float](repeating: 0, count: 160))
        for index in 0 ..< 3 {
            expect(isSilence(host.processCapture(
                user,
                hostTimeNanoseconds:
                    baseTime + 580_000_000
                        + UInt64(index) * 10_000_000
            )), "gray-zone residual without linear evidence stays gated")
        }
        expect(!host.snapshot().sourceGateOpen,
               "render isolation cannot replace secondary near-end evidence")

        backend.setLinearOutput(linearOutput(user))
        var opened: [Float] = []
        for index in 0 ..< 3 {
            opened = host.processCapture(
                user,
                hostTimeNanoseconds:
                    baseTime + 610_000_000
                        + UInt64(index) * 10_000_000
            )
        }
        snapshot = host.snapshot()
        expect(snapshot.renderCaptureCorrelation == 0
                   && !snapshot.sourceAlignmentLocked,
               "established isolation rejects unrelated historical matches")
        expect(snapshot.inputClassification == .nearEndSpeech,
               "isolated gray-zone speech is classified as near-end")
        expect(snapshot.sourceGateOpen && opened.count == 3 * 480,
               "isolated near-end speech still uses three-frame gate")

        host.playbackStopped()
        host.playbackStarted()
        backend.setCaptureOutput(silence)
        backend.setLinearOutput([Float](repeating: 0, count: 160))
        for index in 0 ..< 50 {
            latestRender = testSignal(
                seed: UInt32(6_200 + index),
                amplitude: 0.3
            )
            let renderTime = baseTime + 1_000_000_000
                + UInt64(index) * 10_000_000
            host.processRender(
                latestRender,
                hostTimeNanoseconds: renderTime
            )
            _ = host.processCapture(
                silence,
                hostTimeNanoseconds: renderTime + 80_000_000
            )
        }
        expect(host.snapshot().renderCaptureIsolationEstablished,
               "second playback independently re-establishes isolation")

        backend.setCaptureOutput(silence)
        backend.setLinearOutput([Float](repeating: 0, count: 160))
        host.processRender(
            latestRender,
            hostTimeNanoseconds: baseTime + 1_500_000_000
        )
        let echo = host.processCapture(
            latestRender,
            hostTimeNanoseconds: baseTime + 1_580_000_000
        )
        snapshot = host.snapshot()
        expect(isSilence(echo)
                   && snapshot.inputClassification == .uncertain
                   && !snapshot.sourceGateOpen,
               "one historical echo peak has no classification authority")
        expect(snapshot.renderCaptureIsolationEstablished,
               "one untrusted peak cannot revoke established isolation")
        for index in 1 ..< 3 {
            let renderTime = baseTime + 1_500_000_000
                + UInt64(index) * 10_000_000
            host.processRender(
                latestRender,
                hostTimeNanoseconds: renderTime
            )
            expect(isSilence(host.processCapture(
                latestRender,
                hostTimeNanoseconds: renderTime + 80_000_000
            )), "post-isolation resident energy remains source-gated")
        }
        snapshot = host.snapshot()
        expect(snapshot.inputClassification == .uncertain
                   && !snapshot.sourceGateOpen
                   && snapshot.renderCaptureIsolationEstablished
                   && snapshot.renderCaptureIsolationRevocationCount == 0,
               "historical peaks cannot revoke established isolation")
    }

    private static func testAmbiguousSourceStaysGatedAndRecovers() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 9, amplitude: 0.3)
        let independent = testSignal(seed: 10, amplitude: 0.3)
        let ambiguous = zip(render, independent).map { sample in
            sample.0 * 0.32 + sample.1 * 0.95
        }
        host.processRender(render, hostTimeNanoseconds: 6_000_000_000)
        backend.setCaptureOutput(ambiguous)

        for index in 0 ..< 20 {
            expect(isSilence(host.processCapture(
                ambiguous,
                hostTimeNanoseconds:
                    6_080_000_000 + UInt64(index * 10_000_000)
            )), "ambiguous energetic capture stays zeroed")
        }
        var snapshot = host.snapshot()
        expect(snapshot.mode == .webRTCAEC3
                   && snapshot.fallbackReason == nil,
               "ambiguous source stays gated without disabling AEC")
        expect(snapshot.uncertainFrameCount == 20
                   && snapshot.sourceTimingCandidateFrameCount == 0
                   && snapshot.sourceTimingUnavailableFrameCount == 20,
               "untrusted historical peaks are not timing associations")
        expect(snapshot.sourceGatePreRollFrameCount == 0,
               "bounded ambiguous pre-roll is discarded")

        backend.setCaptureOutput(independent)
        var recovered: [Float] = []
        for index in 0 ..< 3 {
            recovered = host.processCapture(
                independent,
                hostTimeNanoseconds:
                    6_280_000_000 + UInt64(index * 10_000_000)
            )
        }
        snapshot = host.snapshot()
        expect(recovered.count == 3 * 480
                   && snapshot.inputClassification == .nearEndSpeech,
               "confident near-end speech recovers from ambiguity")
        expect(snapshot.fallbackCount == 0,
               "source ambiguity never locks the remainder of playback")
    }

    private static func testRenderConversionFailureFallback() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        host.renderConversionFailed()
        let failed = host.snapshot()
        expect(failed.mode == .halfDuplexFallback,
               "render conversion failure enters fallback")
        expect(failed.fallbackReason == .renderProcessingFailed,
               "render conversion failure is diagnosed")
        expect(host.processCapture([Float](repeating: 1, count: 480)).isEmpty,
               "failed render reference gates playback echo")
        host.playbackCompleted()
        expect(host.snapshot().mode == .webRTCAEC3,
               "playback completion recovers render failure")
    }

    private static func testRouteRebuildRecovery() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.processRender([Float](repeating: 0, count: 100))
        host.routeWillRebuild()
        let rebuilding = host.snapshot()
        expect(rebuilding.mode == .halfDuplexFallback,
               "route reset enters safe fallback")
        expect(rebuilding.fallbackReason == .routeRebuild,
               "route reset reason exposed")
        expect(rebuilding.renderFIFOSampleCount == 0,
               "route reset clears reference")
        expect(rebuilding.routeResetCount == 1,
               "route reset counted")
        expect(host.processCapture([Float](repeating: 1, count: 480)).isEmpty,
               "route rebuild suppresses capture until reconfigured")
        expect(host.routeDidRebuild() == .webRTCAEC3,
               "completed format rebuild deterministically restores AEC")
        expect(backend.resetCount == 1,
               "route rebuild resets the existing AEC backend")
        expect(host.processCapture([Float](repeating: 1, count: 480)).count == 480,
               "capture resumes after route rebuild completes")
    }

    private static func testFallbackAndPlaybackRecovery() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        backend.captureError = .captureFailed
        let suppressed = host.processCapture(
            [Float](repeating: 0.5, count: 480)
        )
        expect(suppressed.isEmpty,
               "AEC failure suppresses capture during resident playback")
        expect(host.snapshot().mode == .halfDuplexFallback,
               "AEC failure enters fallback")
        backend.captureError = nil
        host.playbackCompleted()
        expect(backend.resetCount == 1,
               "real playback completion attempts AEC recovery")
        expect(host.snapshot().mode == .webRTCAEC3,
               "playback completion recovers AEC")
    }

    private static func testPoorERLEPreservesEchoGateAndBargeIn() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        expect(host.configure() == .webRTCAEC3,
               "residual echo fixture configures AEC")
        host.playbackStarted()
        let render = testSignal(seed: 13, amplitude: 0.35)
        let user = testSignal(seed: 14, amplitude: 0.2)
        backend.setMetrics(erle: 6)
        host.processRender(render, hostTimeNanoseconds: 7_000_000_000)
        expect(isSilence(host.processCapture(
            render,
            hostTimeNanoseconds: 7_080_000_000
        )), "healthy resident echo remains zeroed")
        expect(host.snapshot().mode == .webRTCAEC3,
               "healthy ERLE keeps the AEC backend active")

        backend.setMetrics(erle: 0.2)
        for index in 0 ..< 300 {
            let renderTime = 7_010_000_000
                + UInt64(index * 10_000_000)
            host.processRender(render, hostTimeNanoseconds: renderTime)
            expect(isSilence(host.processCapture(
                render,
                hostTimeNanoseconds: renderTime + 80_000_000
            )), "poor-ERLE resident echo remains zeroed")
        }
        var snapshot = host.snapshot()
        expect(snapshot.mode == .webRTCAEC3
                   && snapshot.fallbackCount == 0
                   && snapshot.sourceForwardedFrameCount == 0,
               "poor ERLE cannot forward echo or lock full duplex")

        backend.setCaptureOutput(user)
        let mixedCapture = zip(render, user).map { sample in
            sample.0 * 0.8 + sample.1
        }
        var interrupted: [Float] = []
        for index in 0 ..< 3 {
            let renderTime = 10_100_000_000
                + UInt64(index * 10_000_000)
            host.processRender(render, hostTimeNanoseconds: renderTime)
            interrupted = host.processCapture(
                mixedCapture,
                hostTimeNanoseconds: renderTime + 80_000_000
            )
        }
        snapshot = host.snapshot()
        expect(interrupted.count == 3 * 480
                   && snapshot.inputClassification == .doubleTalk,
               "late double-talk opens barge-in despite poor ERLE")
        expect(snapshot.sourceGateOpen,
               "confirmed user speech keeps the source gate open")

        backend.setCaptureOutput(nil)
        var echoOnlyTime: UInt64 = 10_200_000_000
        for _ in 0 ..< 5 {
            host.processRender(render, hostTimeNanoseconds: echoOnlyTime)
            expect(!isSilence(host.processCapture(
                render,
                hostTimeNanoseconds: echoOnlyTime + 80_000_000
            )), "poor-ERLE protection keeps the user epoch contiguous")
            echoOnlyTime += 10_000_000
        }
        snapshot = host.snapshot()
        expect(!snapshot.sourceGateOpen
                   && snapshot.sourceGateCloseCount == 1
                   && snapshot.lastSourceGateCloseReason
                       == .residualEchoProtection,
               "residual protection closes a persistently failed echo path")
    }

    private static func testStopAlwaysRecoversCapture() {
        let backend = FakeAECBackend()
        backend.configureError = .configureFailed
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        expect(host.configure() == .halfDuplexFallback,
               "initialization failure falls back")
        host.playbackStarted()
        expect(host.processCapture([Float](repeating: 1, count: 480)).isEmpty,
               "fallback gates playback echo")
        host.playbackStopped()
        expect(host.processCapture([Float](repeating: 1, count: 480)).count == 480,
               "Stop restores capture without a timer")
    }

    private static func testPlaybackStopClearsSourceGateState() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.playbackStarted()
        let render = testSignal(seed: 13, amplitude: 0.3)
        let user = testSignal(seed: 14, amplitude: 0.25)
        host.processRender(render, hostTimeNanoseconds: 7_000_000_000)
        backend.setCaptureOutput(user)
        for index in 0 ..< 2 {
            _ = host.processCapture(
                user,
                hostTimeNanoseconds:
                    7_080_000_000 + UInt64(index * 10_000_000)
            )
        }
        expect(host.snapshot().sourceGatePreRollFrameCount == 2,
               "unconfirmed user speech is buffered before Stop")

        host.playbackStopped()
        let stopped = host.snapshot()
        expect(!stopped.sourceGateOpen
                   && stopped.sourceGatePreRollFrameCount == 0,
               "Stop clears gate state and stale pre-roll")
        expect(stopped.sourceSuppressedFrameCount == 2,
               "Stop diagnoses discarded unconfirmed frames")
        expect(host.processCapture(user).count == 480,
               "Stop immediately restores ordinary capture")
    }

    private static func testAppleModeDoesNotUseWebRTC() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .appleVoiceProcessing,
            backend: backend
        )
        expect(host.configure() == .appleVoiceProcessing,
               "Apple voice processing is selectable")
        let configured = host.snapshot()
        expect(configured.enabled && configured.active,
               "Apple voice processing reports active system AEC")
        host.playbackStarted()
        let render = testSignal(seed: 91, amplitude: 0.3)
        let capture = [Float](
            repeating: 0.1,
            count: MacSpeechAcousticEchoHost.frameSampleCount
        )
        host.processRender(
            render,
            hostTimeNanoseconds: 8_000_000_000
        )
        host.updateSystemVoiceActivity(false)
        _ = host.processCaptureSpans(
            capture,
            hostTimeNanoseconds: 8_080_000_000
        )
        let echoOnly = host.snapshot()
        expect(echoOnly.inputClassification == .echoOnly
                   && !echoOnly.sourceGateOpen,
               "Apple VAD keeps playback-only capture source-gated")
        host.updateSystemVoiceActivity(true)
        for index in 0..<3 {
            _ = host.processCaptureSpans(
                render,
                hostTimeNanoseconds:
                    8_090_000_000 + UInt64(index * 10_000_000)
            )
        }
        expect(!host.snapshot().sourceGateOpen,
               "Apple VAD rejects capture that still matches playback")
        for (index, signal) in [capture, render, render, capture, render]
            .enumerated() {
            _ = host.processCaptureSpans(
                signal,
                hostTimeNanoseconds:
                    8_120_000_000 + UInt64(index * 10_000_000)
            )
        }
        expect(!host.snapshot().sourceGateOpen,
               "Apple VAD rejects isolated low-correlation pulses")
        host.playbackStopped()
        host.playbackStarted()
        host.processRender(
            render,
            hostTimeNanoseconds: 9_000_000_000
        )
        host.updateSystemVoiceActivity(false)
        _ = host.processCaptureSpans(
            capture,
            hostTimeNanoseconds: 9_080_000_000
        )
        host.updateSystemVoiceActivity(true)
        var doubleTalkSpans: [MacSpeechAcousticCaptureSpan] = []
        for index in 0..<3 {
            doubleTalkSpans = host.processCaptureSpans(
                capture,
                hostTimeNanoseconds:
                    9_090_000_000 + UInt64(index * 10_000_000)
            )
        }
        let doubleTalk = host.snapshot()
        let doubleTalkObservation = host.acousticObservationSnapshot()
        expect(doubleTalk.inputClassification == .doubleTalk
                   && doubleTalk.sourceGateOpen
                   && doubleTalkObservation.sourceGateEpoch > 0,
               "Apple VAD opens one source-gate epoch for double-talk")
        expect(!doubleTalkSpans.isEmpty
                   && doubleTalk.processedCaptureRMS > 0,
               "Apple-processed double-talk capture remains available")
        host.updateSystemVoiceActivity(false)
        _ = host.processCaptureSpans(
            capture,
            hostTimeNanoseconds: 9_120_000_000
        )
        let closed = host.snapshot()
        expect(!closed.sourceGateOpen
                   && closed.lastSourceGateCloseReason
                        == .sourceEvidenceReset,
               "Apple VAD closes the source gate when voice ends")
        expect(backend.recordedOperations.isEmpty,
               "Apple and WebRTC AEC are mutually exclusive")
    }

    private static func testAppleCaptureFraming() {
        let render = testSignal(seed: 91, amplitude: 0.3)
        let start: UInt64 = 8_080_000_000
        for chunkSize in [480, 4800, 4816, 4096, 137] {
            for scenario in ["double_talk", "echo_only", "isolated"] {
                let host = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)
                _ = host.configure()
                if scenario != "isolated" {
                    host.playbackStarted()
                    host.processRender(
                        Array(repeating: render, count: 20).flatMap { $0 },
                        hostTimeNanoseconds: 7_880_000_000
                    )
                }
                host.updateSystemVoiceActivity(true)
                let samples = (0..<10_080).map { index in
                    scenario == "echo_only" ? render[index % 480]
                        : 0.1 + Float(index % 127) * 0.0001
                }
                var spans: [MacSpeechAcousticCaptureSpan] = []
                var offset = 0
                while offset < 9_737 {
                    let end = min(offset + chunkSize, 9_737)
                    spans += host.processCaptureSpans(
                        Array(samples[offset..<end]),
                        hostTimeNanoseconds: start + UInt64((
                            Double(offset) * 1_000_000_000 / 48_000
                        ).rounded())
                    )
                    offset = end
                }
                let label = "Apple \(scenario) chunk=\(chunkSize)"
                expect(spans.count == 20 && spans.allSatisfy {
                    $0.samples.count == 480
                }, "\(label) emits complete 10 ms frames")
                expect(host.snapshot().captureFIFOSampleCount == 137,
                       "\(label) retains partial capture")
                spans += host.processCaptureSpans(
                    Array(samples[9_737...]),
                    hostTimeNanoseconds: start + 202_854_167
                )
                expect(spans.flatMap(\.samples) == samples,
                       "\(label) preserves every sample in order")
                expect(host.snapshot().captureFIFOSampleCount == 0,
                       "\(label) completes the retained frame")
                expect(spans.map(\.observation.captureFrameIndex)
                    == Array(UInt64(1)...21), "\(label) counts audio frames")
                expect(spans.enumerated().allSatisfy { index, span in
                    guard let timestamp = span.observation
                        .captureHostTimeNanoseconds else { return false }
                    let expected = start + UInt64(index) * 10_000_000
                    return abs(Int64(timestamp) - Int64(expected)) <= 1
                }, "\(label) preserves frame timestamps across callbacks")
                if scenario == "double_talk" {
                    expect(spans.firstIndex(where: {
                        $0.observation.sourceGateOpen
                    }) == 2, "\(label) confirms after 30 ms of audio")
                    expect(spans.dropFirst(2).allSatisfy {
                        $0.observation.sourceGateOpen
                    }, "\(label) keeps qualified speech open")
                } else if scenario == "echo_only" {
                    expect(spans.allSatisfy { !$0.observation.sourceGateOpen },
                           "\(label) rejects echo even with VAD true")
                } else {
                    expect(spans.allSatisfy {
                        MacSpeechAudioActivityEvidenceKind.classify(
                            observation: $0.observation
                        ) == .listeningNearEnd
                    }, "\(label) retains isolated near-end evidence")
                }
                host.updateSystemVoiceActivity(false)
                _ = host.processCaptureSpans(
                    render, hostTimeNanoseconds: start + 210_000_000
                )
                expect(!host.snapshot().sourceGateOpen,
                       "\(label) closes when near-end evidence ends")
                _ = host.processCaptureSpans(
                    [Float](repeating: 0.3, count: 137),
                    hostTimeNanoseconds: start + 220_000_000
                )
                host.discardPendingCaptureForGenerationTransition()
                expect(host.snapshot().captureFIFOSampleCount == 0,
                       "\(label) discards prior generation remainder")
            }
        }
    }

    private static func testAppleConvertedCaptureFraming() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let converter = try! MacSpeechFloatMono48kConverter(inputFormat: format)
        let host = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)
        _ = host.configure()
        host.playbackStarted()
        host.processRender(
            testSignal(seed: 91, amplitude: 0.3),
            hostTimeNanoseconds: 8_000_000_000
        )
        host.updateSystemVoiceActivity(true)
        var convertedSamples: [Float] = []
        var spans: [MacSpeechAcousticCaptureSpan] = []
        for index in 0..<5 {
            let buffer = try! MacSpeechFloatMono48kConverter.makeBuffer(
                samples: [Float](repeating: 0.1, count: 4800)
            )
            let converted = try! converter.convert(
                buffer,
                hostTimeNanoseconds: 8_080_000_000 + UInt64(index) * 100_000_000
            )
            convertedSamples += converted.samples
            spans += host.processCaptureSpans(
                converted.samples,
                hostTimeNanoseconds: converted.hostTimeNanoseconds
            )
        }
        expect(spans.firstIndex(where: { $0.observation.sourceGateOpen }) == 2,
               "Apple real converter output qualifies at audio frame three")
        expect(spans.flatMap(\.samples)
            == Array(convertedSamples.prefix(spans.count * 480)),
               "Apple converter output is preserved through Host framing")
        expect(host.snapshot().captureFIFOSampleCount == convertedSamples.count % 480,
               "Apple converter remainder is retained")
    }

    private static func testConverterTimestampQuantization() {
        let start: UInt64 = 1_119_613_984_460_750
        for rate in [16_000.0, 24_000.0, 44_100.0, 48_000.0] {
            let format = AVAudioFormat(
                standardFormatWithSampleRate: rate, channels: 1
            )!
            let count = AVAudioFrameCount(rate / 10)
            let input = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: count
            )!
            input.frameLength = count
            for index in 0..<Int(count) {
                input.floatChannelData![0][index] = sin(Float(index) * 0.04) * 0.2
            }
            let tolerance = Int64((1_000_000_000 / rate).rounded(.up))
            do {
                let reference = try MacSpeechFloatMono48kConverter(inputFormat: format)
                _ = try reference.convert(input, hostTimeNanoseconds: start)
                let unchangedPCM = try reference.convert(
                    input, hostTimeNanoseconds: start + 100_000_000
                ).samples
                for displacement in [Int64(0), tolerance, -tolerance,
                                     tolerance + 1, -tolerance - 1,
                                     tolerance * 2, -tolerance * 2] {
                    let converter = try MacSpeechFloatMono48kConverter(inputFormat: format)
                    _ = try converter.convert(input, hostTimeNanoseconds: start)
                    let timestamp = UInt64(Int64(start) + 100_000_000 + displacement)
                    let output = try converter.convert(input, hostTimeNanoseconds: timestamp)
                    expect((output.hostTimeNanoseconds != nil) == (abs(displacement) <= tolerance),
                           "\(Int(rate)) Hz timestamp displacement \(displacement) respects a quantized sample")
                    expect(output.samples == unchangedPCM,
                           "timestamp quantization does not change converted PCM")
                }
                let converter = try MacSpeechFloatMono48kConverter(inputFormat: format)
                _ = try converter.convert(input, hostTimeNanoseconds: start)
                let unknown = try converter.convert(input, hostTimeNanoseconds: nil)
                expect(unknown.hostTimeNanoseconds == nil,
                       "unknown callback time cannot acquire a timestamp")
                converter.resetForGenerationTransition()
                let restarted = try converter.convert(input, hostTimeNanoseconds: start + 1_000_000_000)
                expect(restarted.hostTimeNanoseconds == start + 1_000_000_000,
                       "generation transition clears prior timing uncertainty")
            } catch {
                fatalError("FAILED: converter timestamp quantization: \(error)")
            }
        }
    }

    private static func testNativeTenMillisecondTapFraming() {
        expect(
            MacSpeechAudioInputFormat.tapBufferSize(for: 16_000) == 160,
            "16 kHz input requests a 10 ms tap"
        )
        expect(
            MacSpeechAudioInputFormat.tapBufferSize(for: 44_100) == 441,
            "44.1 kHz input requests a 10 ms tap"
        )
        expect(
            MacSpeechAudioInputFormat.tapBufferSize(for: 48_000) == 480,
            "48 kHz input requests a 10 ms tap"
        )
    }

    private static func testSixteenToFortyEightCaptureFraming() {
        guard let format16 = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let input = AVAudioPCMBuffer(
            pcmFormat: format16,
            frameCapacity: 160
        ), let channel = input.floatChannelData?[0] else {
            fatalError("FAILED: 16 kHz fixture")
        }
        input.frameLength = 160
        for index in 0 ..< 160 {
            channel[index] = sin(Float(index) * 0.04) * 0.25
        }

        do {
            let converter = try MacSpeechFloatMono48kConverter(
                inputFormat: format16
            )
            let backend = FakeAECBackend()
            let host = MacSpeechAcousticEchoHost(
                mode: .webRTCAEC3,
                backend: backend
            )
            expect(host.configure() == .webRTCAEC3,
                   "16 kHz capture fixture configures AEC")

            for _ in 0 ..< 4 {
                let before = host.snapshot().captureFrameCount
                let samples = try converter.convert(input)
                _ = host.processCapture(samples)
                let processed = host.snapshot().captureFrameCount - before
                expect(processed <= 1,
                       "each 10 ms USB callback emits at most one AEC frame")
            }
            expect(host.snapshot().captureFrameCount >= 3,
                   "16 kHz input sustains 10 ms AEC capture cadence")
        } catch {
            fatalError("FAILED: 16/48 kHz capture framing: \(error)")
        }
    }

    private static func testTwentyFourToFortyEightResamplingRoundTrip() {
        guard let format24 = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        ), let input = AVAudioPCMBuffer(
            pcmFormat: format24,
            frameCapacity: 480
        ), let channel = input.floatChannelData?[0] else {
            fatalError("FAILED: 24 kHz fixture")
        }
        input.frameLength = 480
        for index in 0 ..< 480 {
            channel[index] = sin(Float(index) * 0.03) * 0.25
        }
        do {
            let upsampler = try MacSpeechFloatMono48kConverter(
                inputFormat: format24
            )
            let first48 = try upsampler.convert(input)
            let second48 = try upsampler.convert(input)
            expect(first48.count >= 900 && first48.count <= 970,
                   "24 kHz converter emits a bounded primed 48 kHz block")
            expect(second48.count >= 950 && second48.count <= 970,
                   "24 kHz converter reaches steady 48 kHz framing")
            let buffer48 = try MacSpeechFloatMono48kConverter.makeBuffer(
                samples: first48 + second48
            )
            let packetizer = try MacSpeechAudioConverter(
                inputFormat: buffer48.format
            )
            let packets = try packetizer.convert(buffer48)
            expect(!packets.isEmpty, "48 kHz returns 20 ms packets")
            expect(packets.allSatisfy { $0.bytes.count == 960 },
                   "Qwen wire packets remain 24 kHz PCM16 20 ms")
        } catch {
            fatalError("FAILED: 24/48 kHz conversion: \(error)")
        }
    }

    private static func testSubframeEchoReference() -> Bool {
        var passed = true
        let render = (0 ..< 33).map { testSignal(seed: UInt32(81_000 + $0), amplitude: 0.3) }
        for offset in [0, 1, 72, 144, 216, 240, 432, 479] {
            for userPresent in [false, true] {
                let backend = FakeAECBackend()
                let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
                _ = host.configure()
                host.playbackStarted()
                var failures: [String] = [], forwarded: [UInt64] = []
                for tick in 0 ..< 33 {
                    let active = tick >= 30
                    let echo = active ? Array((render[tick - 20] + render[tick - 19])[offset ..< offset + 480]) : render[tick]
                    let near = testSignal(seed: UInt32(82_000 + tick), amplitude: 0.3)
                    let residual = userPresent ? near : echo
                    let raw = active ? zip(render[tick], residual).map { $0 * 0.6 + $1 * 0.8 } : render[tick].map { $0 * 0.9 }
                    let clean = active ? residual : render[tick].map { $0 * 0.02 }
                    backend.setCaptureOutput(clean)
                    backend.setLinearOutput(linearOutput(clean))
                    let time = UInt64(100_000_000_000) + UInt64(tick) * 10_000_000
                    host.processRender(render[tick], hostTimeNanoseconds: time)
                    let spans = host.processCaptureSpans(raw, hostTimeNanoseconds: time + 80_000_000)
                    let state = host.snapshot()
                    if tick == 29 && (state.residualEchoBaselineFrameCount < 5 || state.sourceGateOpen) {
                        failures.append("trusted_echo_warmup")
                    }
                    guard active else { continue }
                    if !userPresent && (state.sourceGateOpen || state.inputClassification == .doubleTalk
                        || state.inputClassification == .nearEndSpeech) { failures.append("echo_gained_near_identity_\(tick)") }
                    for span in spans where span.samples.contains(where: { $0 != 0 }) {
                        forwarded.append(span.observation.captureFrameIndex)
                        let originalTick = Int(span.observation.captureFrameIndex) - 1
                        if userPresent && span.samples != testSignal(seed: UInt32(82_000 + originalTick), amplitude: 0.3) {
                            failures.append("near_audio_altered")
                        }
                    }
                }
                if forwarded != (userPresent ? [31, 32, 33] : []) { failures.append("source_frame_coverage") }
                if host.snapshot().sourceGateOpenCount != (userPresent ? 1 : 0) { failures.append("gate_ownership") }
                let result: [String: Any] = ["case": "subframe-reference", "offset_samples": offset,
                    "user_present": userPresent, "backend": "FakeAECBackend", "pass": failures.isEmpty,
                    "failures": failures, "nonzero_source_ids": forwarded]
                let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                passed = passed && failures.isEmpty
            }
        }
        return passed
    }

    private static func testCompetingEchoReference() -> Bool {
        var allPassed = true
        for userPresent in [false, true] {
            let backend = FakeAECBackend()
            let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
            _ = host.configure()
            host.playbackStarted()
            let oldRender = testSignal(seed: 70_001, amplitude: 0.3)
            let user = testSignal(seed: 70_002, amplitude: 0.3)
            let residual = userPresent ? user : oldRender
            var failures: [String] = []
            var forwarded: [UInt64] = []
            for tick in 0 ..< 33 {
                let far = tick == 0 ? oldRender : testSignal(seed: UInt32(71_000 + tick), amplitude: 0.3)
                let active = tick >= 30
                // The negative contains only two render paths; the positive replaces
                // the delayed echo with independent near-end audio of the same level.
                let raw = active ? zip(far, residual).map { $0 * 0.6 + $1 * 0.8 } : far.map { $0 * 0.9 }
                let clean = active ? residual : far.map { $0 * 0.02 }
                backend.setCaptureOutput(clean)
                backend.setLinearOutput(linearOutput(clean))
                let time = UInt64(90_000_000_000) + UInt64(tick) * 10_000_000
                host.processRender(far, hostTimeNanoseconds: time)
                let spans = host.processCaptureSpans(raw, hostTimeNanoseconds: time + 80_000_000)
                let state = host.snapshot()
                if tick == 29 && (state.residualEchoBaselineFrameCount < 5 || state.sourceGateOpen) {
                    failures.append("trusted_echo_warmup")
                }
                guard active else { continue }
                if state.renderCaptureCorrelation <= 0.25 { failures.append("fixture_must_exercise_skipped_scan") }
                if !userPresent && (state.sourceGateOpen || state.inputClassification == .doubleTalk
                    || state.inputClassification == .nearEndSpeech) { failures.append("echo_gained_near_identity_\(tick)") }
                for span in spans where span.samples.contains(where: { $0 != 0 }) {
                    forwarded.append(span.observation.captureFrameIndex)
                    if userPresent && span.samples != user { failures.append("near_audio_altered") }
                }
            }
            if userPresent {
                if forwarded != [31, 32, 33] { failures.append("near_onset_missing_or_duplicated") }
                if host.snapshot().sourceGateOpenCount != 1 { failures.append("one_near_open") }
            } else if !forwarded.isEmpty { failures.append("echo_forwarded") }
            let result: [String: Any] = ["case": userPresent ? "competing-reference-near" : "competing-reference-echo",
                "backend": "FakeAECBackend", "pass": failures.isEmpty, "failures": failures,
                "nonzero_source_ids": forwarded]
            let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            allPassed = allPassed && failures.isEmpty
        }
        return allPassed
    }

    private static func testAlternatingWeakEvidenceCloseBudget() -> Bool {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
        _ = host.configure()
        host.playbackStarted()
        let tailReference = testSignal(seed: 42_001, amplitude: 0.3)
        let user = testSignal(seed: 42_002, amplitude: 0.25)
        var rows: [[String: Any]] = []
        var failures: [String] = []
        var firstClose: Int?
        for tick in 0 ..< 83 {
            let far = tick == 0 ? tailReference : testSignal(seed: UInt32(43_000 + tick), amplitude: 0.3)
            let time = UInt64(60_000_000_000) + UInt64(tick) * 10_000_000
            let isUser = (30 ..< 33).contains(tick)
            let weakIndex = tick - 33
            let residual = weakIndex >= 0 && weakIndex.isMultiple(of: 2) ? tailReference : far
            let raw = isUser ? zip(far, user).map { $0 * 0.9 + $1 }
                : far.map { $0 * (weakIndex >= 0 ? 1.2 : 0.9) }
            let clean = isUser ? user : residual.map { $0 * (weakIndex >= 0 ? 0.01 : 0.12) }
            let linear = weakIndex >= 0 ? linearOutput(residual.map { $0 * 0.5 }) : linearOutput(clean)
            backend.setCaptureOutput(clean)
            backend.setLinearOutput(linear)
            host.processRender(far, hostTimeNanoseconds: time)
            let emitted = host.processCaptureSpans(raw, hostTimeNanoseconds: time + 80_000_000)
            let state = host.snapshot()
            if tick == 32 && !state.sourceGateOpen { failures.append("fixture_user_must_open_gate") }
            guard weakIndex >= 0 else { continue }
            let expected: MacSpeechAcousticInputClassification = weakIndex.isMultiple(of: 2) ? .uncertain : .echoOnly
            if state.inputClassification != expected { failures.append("fixture_classification_\(weakIndex)") }
            if !state.sourceGateOpen && firstClose == nil { firstClose = weakIndex }
            if weakIndex >= 19 && emitted.contains(where: { $0.samples.contains { $0 != 0 } }) {
                failures.append("nonzero_after_20_non_user_frames_\(weakIndex)")
            }
            rows.append(["non_user_index": weakIndex, "classification": state.inputClassification.rawValue,
                         "gate_open": state.sourceGateOpen, "gate_opens": state.sourceGateOpenCount,
                         "adaptive_evaluations": state.adaptiveEvidenceCandidateFrameCount])
        }
        let state = host.snapshot()
        if firstClose.map({ $0 <= 19 }) != true { failures.append("close_within_20_non_user_frames") }
        if state.sourceGateOpenCount != 1 { failures.append("weak_evidence_must_not_reopen_gate") }
        let result: [String: Any] = ["case": "alternating-weak-close-budget", "backend": "FakeAECBackend",
                                     "pass": failures.isEmpty, "first_close_non_user_index": firstClose ?? -1,
                                     "failures": failures, "frames": rows]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        return failures.isEmpty
    }

    // Signal truth and callback clocks vary independently. Fake AEC isolates
    // Host association/gating; these controls do not validate WebRTC acoustics.
    private static func runTimingControls() -> Bool {
        let cases: [(String, Float, Bool, String)] = [
            ("isolated-double-talk", 0, true, "continuous"),
            ("speaker-normal-double-talk", 0.3, true, "continuous"),
            ("speaker-loud-double-talk", 0.6, true, "continuous"),
            ("speaker-normal-echo", 0.3, false, "continuous"),
            ("speaker-loud-echo", 0.6, false, "continuous"),
            ("physical-delay-shift", 0.3, false, "path-shift"),
            ("render-time-missing", 0.3, false, "render-missing"),
            ("varying-echo-reference-present", 0.3, false, "varying-echo"),
            ("varying-echo-reference-gap", 0.3, false, "varying-echo-gap"),
            ("capture-time-missing", 0.3, false, "missing"),
            ("capture-time-duplicate", 0.3, false, "duplicate"),
            ("capture-time-backward", 0.3, false, "backward"),
            ("capture-time-jump", 0.3, false, "jump")
        ]
        var failedCases = 0
        for (name, amplitude, hasNear, variation) in cases {
            let backend = FakeAECBackend()
            let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
            _ = host.configure()
            host.updateDelay(outputPresentationLatencySeconds: 0.08,
                             capturePresentationLatencySeconds: 0)
            host.playbackStarted()
            let start: UInt64 = 50_000_000_000
            let step: UInt64 = 10_000_000
            let nearTicks = amplitude == 0 ? 80 ..< 110 : 50 ..< 80
            let render = (0 ..< 166).map {
                let gain: Float = variation.hasPrefix("varying-echo")
                    ? ($0 % 80 < 52 ? 0.5 : 2) : 1
                return testSignal(seed: UInt32(6_000 + $0), amplitude: max(amplitude, 0.3) * gain)
            }
            var rows: [[String: Any]] = []
            var forwarded: [UInt64: [[Float]]] = [:]
            var expectedNear: [UInt64: [Float]] = [:]
            var missingReferences = 0
            var wrongReferences = 0
            var nonCausalReferences = 0
            var invalidClockLocks = 0
            var firstUnlock: Int?
            var firstClose: Int?
            var gateEverOpened = false
            var previousCaptureTime: UInt64?
            var failures: [String] = []
            func require(_ condition: Bool, _ label: String) {
                if !condition { failures.append(label) }
            }
            for tick in 0 ..< render.count {
                let physicalTime = start + UInt64(tick) * step
                let missingRenderTime = variation == "render-missing" && (52 ..< 60).contains(tick)
                    || variation == "varying-echo-gap" && (52 ..< 76).contains(tick)
                let renderTime = missingRenderTime ? nil : Optional(physicalTime)
                host.processRender(render[tick], hostTimeNanoseconds: renderTime)
                guard tick >= 16 else { continue }
                if tick == (hasNear ? nearTicks.lowerBound : 60) {
                    let state = host.snapshot()
                    require(amplitude == 0 ? state.renderCaptureIsolationEstablished
                                : state.sourceAlignmentLocked
                                    && state.sourceAlignmentDelayMilliseconds == 80,
                            "fixture_must_establish_initial_path_before_perturbation")
                }
                let delayFrames = variation == "path-shift" && tick >= 60 ? 14 : 8
                let truthReference = start + UInt64(tick - delayFrames) * step
                let echo = amplitude == 0
                    ? [Float](repeating: 0, count: 480) : render[tick - delayFrames]
                let near = hasNear && nearTicks.contains(tick)
                    ? testSignal(seed: UInt32(9_000 + tick), amplitude: 0.25)
                    : [Float](repeating: 0, count: 480)
                let raw = zip(echo, near).map { $0 * 0.9 + $1 }
                let clean = zip(echo, near).map { $0 * 0.12 + $1 }
                backend.setCaptureOutput(clean)
                backend.setLinearOutput(linearOutput(clean))
                var captureTime: UInt64? = physicalTime
                if variation == "missing" && (60 ..< 68).contains(tick) {
                    captureTime = nil
                } else if tick == 60 {
                    if variation == "duplicate" { captureTime = physicalTime - step }
                    if variation == "backward" { captureTime = physicalTime - 2 * step }
                    if variation == "jump" { captureTime = physicalTime + 6 * step }
                }
                let spans = host.processCaptureSpans(raw, hostTimeNanoseconds: captureTime)
                let observation = host.acousticObservationSnapshot()
                let snapshot = host.snapshot()
                let frameID = UInt64(tick - 15)
                if hasNear && nearTicks.contains(tick) { expectedNear[frameID] = clean }
                for span in spans where span.samples.contains(where: { $0 != 0 }) {
                    forwarded[span.observation.captureFrameIndex, default: []].append(span.samples)
                }
                let reference = observation.renderHostTimeNanoseconds
                if let reference, let captureTime, reference > captureTime {
                    nonCausalReferences += 1
                }
                if hasNear && amplitude > 0 && nearTicks.contains(tick) {
                    if reference == nil { missingReferences += 1 }
                    else if reference != truthReference { wrongReferences += 1 }
                    if !snapshot.sourceAlignmentLocked && firstUnlock == nil { firstUnlock = tick }
                }
                if let captureTime, let previousCaptureTime,
                   captureTime <= previousCaptureTime,
                   snapshot.sourceAlignmentLocked, reference != nil {
                    invalidClockLocks += 1
                }
                previousCaptureTime = captureTime
                gateEverOpened = gateEverOpened || snapshot.sourceGateOpen
                if hasNear && tick >= nearTicks.upperBound && gateEverOpened,
                   !snapshot.sourceGateOpen && firstClose == nil { firstClose = tick }
                rows.append([
                    "tick": tick, "physical_capture_ns": physicalTime,
                    "capture_ns": captureTime.map { Int64($0) } ?? -1,
                    "truth_render_ns": truthReference,
                    "reported_render_ns": reference.map { Int64($0) } ?? -1,
                    "near_present": hasNear && nearTicks.contains(tick),
                    "locked": snapshot.sourceAlignmentLocked,
                    "delay_ms": snapshot.sourceAlignmentDelayMilliseconds ?? -1,
                    "misses": snapshot.sourceAlignmentMissCount,
                    "reacquisitions": snapshot.sourceAlignmentReacquisitionCount,
                    "classification": observation.inputClassification.rawValue,
                    "gate_open": snapshot.sourceGateOpen,
                    "close_reason": snapshot.lastSourceGateCloseReason?.rawValue ?? "none",
                    "emitted_frame_ids": spans.map { $0.observation.captureFrameIndex },
                    "nonzero_frame_ids": spans.filter { $0.samples.contains { $0 != 0 } }
                        .map { $0.observation.captureFrameIndex }
                ])
            }
            let snapshot = host.snapshot()
            let missingNear = expectedNear.keys.filter { forwarded[$0] == nil }.sorted()
            let duplicateNear = expectedNear.keys.filter { (forwarded[$0]?.count ?? 0) > 1 }.sorted()
            let alteredNear = expectedNear.keys.filter {
                guard let emitted = forwarded[$0]?.first else { return false }
                return emitted != expectedNear[$0]
            }.sorted()
            require(nonCausalReferences == 0, "reported_reference_must_be_capture_causal")
            if hasNear {
                require(missingNear.isEmpty, "every_near_frame_must_be_forwarded")
                require(duplicateNear.isEmpty, "near_frames_must_not_repeat")
                require(alteredNear.isEmpty, "gate_must_preserve_aec_output_samples")
                require(forwarded.keys.allSatisfy { $0 >= UInt64(nearTicks.lowerBound - 15) },
                        "echo_warmup_must_be_silent")
                require(snapshot.sourceGateOpenCount == 1, "one_near_segment_one_gate_epoch")
                require(firstClose.map { $0 <= nearTicks.upperBound + 19 } == true,
                        "close_within_20_non_user_frames")
                require(!snapshot.sourceGateOpen, "gate_must_finish_closed")
                require(forwarded.keys.allSatisfy { $0 < UInt64(nearTicks.upperBound + 19 - 15) },
                        "no_nonzero_output_after_close_budget")
                if amplitude > 0 {
                    require(missingReferences == 0 && wrongReferences == 0,
                            "fixed_path_double_talk_must_keep_correct_reference")
                }
            } else {
                require(snapshot.sourceGateOpenCount == 0, "echo_must_not_open_gate")
                require(forwarded.isEmpty, "echo_must_not_forward_nonzero_pcm")
                require(snapshot.nearEndSpeechFrameCount == 0 && snapshot.doubleTalkFrameCount == 0,
                        "echo_must_not_become_user_evidence")
                require(invalidClockLocks == 0, "nonmonotonic_capture_must_not_claim_locked_reference")
                require(snapshot.sourceAlignmentLocked, "fresh_echo_must_reacquire_by_fixture_end")
                let expectedDelay = variation == "path-shift" ? 140 : 80
                require(snapshot.sourceAlignmentDelayMilliseconds == expectedDelay,
                        "reacquired_delay_must_match_physical_truth")
            }
            if !failures.isEmpty { failedCases += 1 }
            let result: [String: Any] = [
                "case": name, "status": failures.isEmpty ? "PASS" : "FAIL",
                "backend": "FakeAECBackend", "failures": failures,
                "missing_near_ids": missingNear, "duplicate_near_ids": duplicateNear,
                "altered_near_ids": alteredNear,
                "missing_near_references": missingReferences,
                "wrong_near_references": wrongReferences,
                "first_near_unlock_tick": firstUnlock ?? -1,
                "first_close_tick": firstClose ?? -1,
                "final_close_reason": snapshot.lastSourceGateCloseReason?.rawValue ?? "none",
                "invalid_clock_locked_references": invalidClockLocks,
                "gate_opens": snapshot.sourceGateOpenCount,
                "nonzero_frames": forwarded.values.reduce(0) { $0 + $1.count },
                "frames": rows
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } catch { fatalError("FAILED: timing control evidence serialization: \(error)") }
        }
        print("timing_controls=\(cases.count) failed=\(failedCases)")
        return failedCases == 0
    }

    private static func convertedPackets(
        captureSpans: [MacSpeechAcousticCaptureSpan]
    ) -> [MacSpeechPCM16Packet] {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ), let converter = try? MacSpeechAudioConverter(inputFormat: format),
        let packets = try? converter.convert(captureSpans: captureSpans) else {
            fatalError("FAILED: production capture span conversion unavailable")
        }
        return packets
    }

    private static func testSignal(seed: UInt32, amplitude: Float) -> [Float] {
        var state = seed
        return (0 ..< 480).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit = Float(state >> 8) / Float(0x00FF_FFFF)
            return (unit * 2 - 1) * amplitude
        }
    }

    private static func linearOutput(_ samples: [Float]) -> [Float] {
        stride(from: 0, to: samples.count, by: 3).map { index in
            (samples[index] + samples[index + 1] + samples[index + 2]) / 3
        }
    }

    private static func isSilence(
        _ samples: [Float],
        frameCount: Int = 1
    ) -> Bool {
        samples.count
            == frameCount * MacSpeechAcousticEchoHost.frameSampleCount
            && samples.allSatisfy { $0 == 0 }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
