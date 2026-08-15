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
        lock.withLock { operations.append("capture") }
        return samples.map { $0 * 0.5 }
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
        MacSpeechAECBackendStats(
            enabled: true,
            active: true,
            estimatedDelayMilliseconds: lock.withLock {
                delays.last ?? 0
            },
            erlDecibels: 12,
            erleDecibels: 24
        )
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
        testBoundedFIFOFailure()
        testMeasuredDelay()
        testRouteReset()
        testFallbackAndPlaybackRecovery()
        testStopAlwaysRecoversCapture()
        testAppleModeDoesNotUseWebRTC()
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

    private static func testBoundedFIFOFailure() {
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: FakeAECBackend(),
            fifoFrameCapacity: 1
        )
        _ = host.configure()
        host.processRender([Float](repeating: 0, count: 481))
        let snapshot = host.snapshot()
        expect(snapshot.mode == .halfDuplexFallback,
               "FIFO overflow enters fallback")
        expect(snapshot.fallbackReason == .fifoOverflow,
               "FIFO overflow is diagnostic")
        expect(snapshot.renderFIFOSampleCount == 0,
               "overflow clears render FIFO")
    }

    private static func testMeasuredDelay() {
        let backend = FakeAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        _ = host.configure()
        host.recordCaptureProcessingDuration(nanoseconds: 2_000_000)
        host.updateDelay(
            outputPresentationLatencySeconds: 0.020,
            capturePresentationLatencySeconds: 0.010,
            queuedOutputFrameCount: 480,
            outputSampleRate: 48_000
        )
        expect(backend.recordedDelays.last == 42,
               "delay sums presentation queue and processing measurements")
        expect(host.snapshot().delayMilliseconds == 42,
               "measured delay is exposed")
    }

    private static func testRouteReset() {
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: FakeAECBackend()
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
        expect(host.configure() == .webRTCAEC3,
               "format rebuild reconfigures AEC")
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

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
