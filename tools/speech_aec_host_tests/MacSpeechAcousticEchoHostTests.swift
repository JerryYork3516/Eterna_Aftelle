@preconcurrency import AVFoundation
import Foundation

private final class FakeAECBackend: MacSpeechAECBackend, @unchecked Sendable {
    private let lock = NSLock()
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

    func processCapture(_ samples: [Float]) throws -> [Float] {
        if let captureError { throw captureError }
        guard samples.count == MacSpeechAcousticEchoHost.frameSampleCount else {
            throw MacSpeechAECBackendError.captureFailed
        }
        return lock.withLock {
            operations.append("capture")
            return captureOutput ?? samples.map { $0 * 0.5 }
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

    var recordedOperations: [String] { lock.withLock { operations } }
    var recordedDelays: [Int] { lock.withLock { delays } }
    var resetCount: Int { lock.withLock { resets } }
}

@MainActor
@main
private struct MacSpeechAcousticEchoHostTests {
    private static var checks = 0

    static func main() {
        testConfigureAndSerializedFraming()
        testArbitraryRenderCallbackFraming()
        testArbitraryCaptureCallbackFraming()
        testFIFORemainderIsBounded()
        testRenderAlignedDelay()
        testHostTimeAlignedDelayAndDiagnostics()
        testSourceGateEpochDiagnosticsAreBounded()
        testTimingHistoryIsBoundedAndReset()
        testEchoOnlySourceGate()
        testNearEndSourceGateAndPreRoll()
        testAbortedSourceGatePreRollPreservesCadence()
        testDoubleTalkSourceGate()
        testRouteIndependentBargeInHysteresis()
        testAdaptiveExternalOutputDoubleTalk()
        testAdaptiveGateRejectsResidualEchoVariation()
        testMixedResidentRenderIsOneFarEndReference()
        testLongLoudEchoStaysSuppressed()
        testUncertainSourceGateIsBoundedAndRecoverable()
        testAmbiguousSourceStaysGatedAndRecovers()
        testRenderConversionFailureFallback()
        testRouteRebuildRecovery()
        testFallbackAndPlaybackRecovery()
        testPoorERLEPreservesEchoGateAndBargeIn()
        testPlaybackStopClearsSourceGateState()
        testStopAlwaysRecoversCapture()
        testAppleModeDoesNotUseWebRTC()
        testNativeTenMillisecondTapFraming()
        testSixteenToFortyEightCaptureFraming()
        testTwentyFourToFortyEightResamplingRoundTrip()
        print("speech_aec_host_checks=\(checks)")
    }

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
        let second = host.processCapture(
            [Float](repeating: 0.5, count: 479)
        )
        expect(second.count == 480,
               "remainder completes the next frame")
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
        let frame = (0 ..< 480).map {
            sin(Float($0) * 0.07) * 0.25
        }
        host.processRender(
            frame,
            hostTimeNanoseconds: 1_000_000_000
        )
        _ = host.processCapture(
            frame,
            hostTimeNanoseconds: 1_080_000_000
        )

        let snapshot = host.snapshot()
        expect(snapshot.presentationDelayMilliseconds == 30,
               "presentation delay remains available as a baseline")
        expect(snapshot.alignedDelayMilliseconds == 80,
               "matched host times establish the acoustic delay")
        expect(snapshot.sourceAlignmentDelayMilliseconds == 80,
               "source alignment has an explicit diagnostic field")
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
                       == 86,
               "source gate epoch keeps delay semantics separate")
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
        expect(snapshot.inputClassification == .echoOnly,
               "resident-only echo is classified from PCM correlation")
        expect(!snapshot.sourceGateOpen,
               "resident-only echo keeps the source gate closed")
        expect(snapshot.sourceGatePreRollFrameCount == 0,
               "resident-only echo is not retained as user pre-roll")
        expect(snapshot.echoOnlyFrameCount == 1
                   && snapshot.sourceSuppressedFrameCount == 1,
               "resident-only diagnostics count the suppressed frame")
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
        expect(isSilence(host.processCapture(
            render,
            hostTimeNanoseconds: 2_120_000_000
        )), "one resident echo frame stays suppressed")
        snapshot = host.snapshot()
        expect(snapshot.inputClassification == .echoOnly
                   && snapshot.sourceGateOpen
                   && snapshot.sourceGateCloseCount == 0,
               "one echo frame cannot fragment confirmed user speech")
        for index in 1 ..< 20 {
            expect(isSilence(host.processCapture(
                render,
                hostTimeNanoseconds:
                    2_120_000_000 + UInt64(index * 10_000_000)
            )), "resident echo remains zeroed during gate hangover")
        }
        snapshot = host.snapshot()
        expect(!snapshot.sourceGateOpen
                   && snapshot.lastSourceGateCloseReason
                       == .nonUserHangover,
               "200 ms without user evidence closes the source gate")
        expect(snapshot.nearEndSpeechFrameCount == 4
                   && snapshot.sourceForwardedFrameCount == 4,
               "near-end diagnostics count released and live frames")
        expect(snapshot.sourceGateOpenCount == 1
                   && snapshot.sourceGateCloseCount == 1,
               "source gate transitions are counted")
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
        for index in 0 ..< 15 {
            expect(isSilence(host.processCapture(
                render,
                hostTimeNanoseconds:
                    3_170_000_000 + UInt64(index * 10_000_000)
            )), "resident echo after barge-in remains zeroed")
        }
        snapshot = host.snapshot()
        expect(!snapshot.sourceGateOpen
                   && snapshot.sourceGateCloseCount == 1
                   && snapshot.lastSourceGateCloseReason
                       == .nonUserHangover,
               "bounded non-user hangover closes the post-barge gate")
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
            expect(isSilence(host.processCapture(
                render,
                hostTimeNanoseconds: renderTime + 80_000_000
            )), "interleaved resident echo is zeroed")
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
        for _ in 0 ..< 20 {
            host.processRender(render, hostTimeNanoseconds: renderTime)
            expect(isSilence(host.processCapture(
                render,
                hostTimeNanoseconds: renderTime + 80_000_000
            )), "resident-only tail never forwards nonzero PCM")
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
        expect(snapshot.residualEchoBaselineFrameCount == 10,
               "resident-only frames establish the route baseline")
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

        backend.setCaptureOutput(residualEcho)
        for _ in 0 ..< 20 {
            host.processRender(render, hostTimeNanoseconds: renderTime)
            expect(isSilence(host.processCapture(
                render.map { $0 * 0.9 },
                hostTimeNanoseconds: renderTime + 146_000_000
            )), "resident-only tail remains zeroed after barge-in")
            renderTime += 10_000_000
        }
        snapshot = host.snapshot()
        expect(!snapshot.sourceGateOpen
                   && snapshot.lastSourceGateCloseReason
                       == .nonUserHangover,
               "resident-only tail closes the adaptive user epoch")
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
        expect(snapshot.adaptiveEvidenceCandidateFrameCount > 0
                   && snapshot.maximumAdaptiveRawExcessRMS < 0.001
                   && snapshot.maximumAdaptiveResidualExcessRMS > 0.012,
               "diagnostics expose which adaptive evidence was absent")
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
        expect(snapshot.inputClassification == .echoOnly
                   && snapshot.echoOnlyFrameCount == 1,
               "mixed resident playback cannot be mistaken for near-end speech")
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
        expect(snapshot.echoOnlyFrameCount == 300
                   && snapshot.sourceSuppressedFrameCount == 300,
               "long loud playback is fully counted as resident echo")
        expect(snapshot.sourceTimingCandidateFrameCount == 300
                   && snapshot.sourceTimingUnavailableFrameCount == 0,
               "long loud playback retains timing evidence")
        expect(snapshot.sourceGateOpenCount == 0,
               "resident-only playback never opens the source gate")
        expect(snapshot.maximumContinuousSourceForwardedFrameCount == 0,
               "resident-only playback never emits nonzero source PCM")
        expect(snapshot.residualEchoBaselineFrameCount == 300
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
        expect(snapshot.residualEchoBaselineFrameCount == 300,
               "diagnostic reset preserves the live echo baseline")
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
                   && snapshot.sourceTimingCandidateFrameCount == 20,
               "diagnostics distinguish timing from attribution")
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
            expect(isSilence(host.processCapture(
                render,
                hostTimeNanoseconds: echoOnlyTime + 80_000_000
            )), "poor-ERLE resident echo remains zeroed after barge-in")
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
        expect(backend.recordedOperations.isEmpty,
               "Apple and WebRTC AEC are mutually exclusive")
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

    private static func testSignal(seed: UInt32, amplitude: Float) -> [Float] {
        var state = seed
        return (0 ..< 480).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit = Float(state >> 8) / Float(0x00FF_FFFF)
            return (unit * 2 - 1) * amplitude
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
