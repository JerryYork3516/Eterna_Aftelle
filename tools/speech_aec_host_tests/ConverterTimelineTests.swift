import AVFoundation
import Darwin
import Foundation

private final class TimelineBackend: MacSpeechAECBackend, @unchecked Sendable {
    func configure() throws {}
    func reset() throws {}
    func setDelay(milliseconds: Int) throws {}
    func processRender(_ samples: [Float]) throws {}
    func processCapture(_ samples: [Float]) throws -> MacSpeechAECCaptureResult {
        MacSpeechAECCaptureResult(processedSamples: samples,
            linearOutputSamples: stride(from: 0, to: samples.count, by: 3).map { samples[$0] })
    }
    func stats() throws -> MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(enabled: true, active: true,
            estimatedDelayMilliseconds: 0, erlDecibels: 0, erleDecibels: 0)
    }
}

private final class ReferenceInput: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { pending = buffer }
    func take() -> AVAudioPCMBuffer? {
        lock.withLock {
            defer { pending = nil }
            return pending
        }
    }
}

@main private struct ConverterTimelineTests {
    private static func format(_ rate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
            channels: 1, interleaved: false)!
    }

    private static func buffer(_ samples: [Float], rate: Double) -> AVAudioPCMBuffer {
        let result = AVAudioPCMBuffer(pcmFormat: format(rate), frameCapacity: AVAudioFrameCount(samples.count))!
        result.frameLength = AVAudioFrameCount(samples.count)
        result.floatChannelData![0].update(from: samples, count: samples.count)
        return result
    }

    private static func reference(_ input: [Float], rate: Double) throws -> [Float] {
        let converter = AVAudioConverter(from: format(rate), to: format(48_000))!
        converter.channelMap = [0]
        let source = ReferenceInput(buffer(input, rate: rate))
        let capacity = max(16_384, Int(ceil(Double(input.count) * 48_000 / rate)) + 1_024)
        let output = AVAudioPCMBuffer(pcmFormat: format(48_000), frameCapacity: AVAudioFrameCount(capacity))!
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard let next = source.take() else { state.pointee = .endOfStream; return nil }
            state.pointee = .haveData
            return next
        }
        guard status != .error, error == nil else { throw MacSpeechAudioCaptureError.conversionFailed }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    private static func run(rate: Double, render: Bool, reset: Bool, batches: Int) throws -> [String: Any] {
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: TimelineBackend())
        guard host.configure() == .webRTCAEC3 else { throw MacSpeechAECBackendError.configureFailed }
        let engine = SystemMacSpeechVoiceProcessingEngine(acousticEchoHost: host)
        let queue = MacSpeechAudioFrameBuffer(capacity: 200)
        queue.begin(generation: 1)
        engine.captureAECConverter = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
        engine.captureOutputConverter = try MacSpeechAudioConverter(inputFormat: format(48_000))
        engine.renderAECConverter = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
        var failures = [String](), epochs = [[String: Any]]()
        let base = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        for epoch in 0..<(reset ? 2 : 1) {
            if epoch > 0 {
                // Capture uses the real generation transition; render format rebuild uses a fresh converter.
                if render {
                    engine.renderAECConverter = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
                    _ = host.configure()
                } else { engine.discardPendingAudioForGenerationTransition() }
            }
            queue.begin(generation: UInt64(epoch + 1))
            host.clearAcousticReplayCapture()
            guard host.armAcousticReplayCapture(attemptID: UUID(), targetCaptureFrameCount: 100) else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            let anchor = base + UInt64(epoch) * 1_000_000_000
            let inputCount = Int(rate / 10)
            // A deterministic ramp identifies source positions independently of callback sizes.
            let input = (0..<(inputCount * batches)).map { Float($0 + epoch * 100_000) / 1_000_000 }
            for batch in 0..<batches {
                let frame = buffer(Array(input[batch * inputCount..<(batch + 1) * inputCount]), rate: rate)
                let timestamp = anchor + UInt64(batch) * 100_000_000
                if render { engine.processRenderedOutput(frame, hostTimeNanoseconds: timestamp) }
                else {
                    engine.processCapture(frame, hostTimeNanoseconds: timestamp,
                        generation: UInt64(epoch + 1), frameBuffer: queue)
                }
            }
            host.sealAcousticReplayCapture(reason: .manual)
            guard let saved = host.acousticReplayCaptureSnapshot() else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }
            let calls = saved.audioCalls.filter { render ? $0.kind == .render : $0.kind == .capture }
            let frames = render ? saved.renderFrames.map(\.hostTimeNanoseconds)
                : saved.captureFrames.map(\.captureHostTimeNanoseconds)
            var errors = [[String: Any]]()
            for call in calls {
                let expected = anchor + UInt64((Double(call.sampleOffset) * 1_000_000_000 / 48_000).rounded())
                if abs(Double(call.hostTimeNanoseconds ?? 0) - Double(expected)) > 1 {
                    errors.append(["sample_offset": call.sampleOffset, "expected_ns": expected,
                                   "actual_ns": call.hostTimeNanoseconds as Any? ?? NSNull()])
                }
            }
            let frameErrors = frames.enumerated().filter {
                abs(Double($0.element ?? 0) - Double(anchor + UInt64($0.offset) * 10_000_000)) > 1
            }.count
            let samples = render ? saved.chronologicalRenderSamples : saved.rawMicrophoneSamples
            // A one-shot conversion supplies an independent waveform reference for resampling.
            let expectedSamples = rate == 48_000 ? input : try reference(input, rate: rate)
            let prefixMatches = samples.count <= expectedSamples.count
                && samples == Array(expectedSamples.prefix(samples.count))
            if calls.count != batches || frames.isEmpty || !prefixMatches || !errors.isEmpty || frameErrors > 0 {
                failures.append("epoch \(epoch): converted samples and 10 ms frames must retain source time")
            }
            epochs.append(["epoch": epoch, "call_count": calls.count, "output_samples": samples.count,
                           "source_prefix_matches": prefixMatches,
                           "call_time_errors": errors, "frame_time_error_count": frameErrors])
        }
        return ["rate": rate, "stream": render ? "render" : "capture", "reset": reset, "batches": batches,
                "pass": failures.isEmpty, "failures": failures, "epochs": epochs]
    }

    private static func clockBoundary(rate: Double, scenario: String) throws -> [String: Any] {
        let base: UInt64 = 10_000_000_000
        var times: [UInt64?] = (0..<4).map { base + UInt64($0) * 100_000_000 }
        var known = [true, true, true, true]
        switch scenario {
        case "missing-start": times[0] = nil; known = [false, false, true, true]
        case "missing-middle": times[1] = nil; known = [true, false, false, true]
        case "forward-gap", "backward-jump":
            for index in 1..<4 {
                times[index] = scenario == "forward-gap"
                    ? times[index]! + 50_000_000 : times[index]! - 50_000_000
            }
            known = [true, false, true, true]
        case "sub-sample-jitter":
            for index in 1..<4 { times[index]! += 100 }
        default: break
        }
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
        if scenario == "reset-unknown" {
            _ = try converter.convert(buffer(Array(repeating: 0.5, count: Int(rate / 10)), rate: rate),
                                      hostTimeNanoseconds: nil)
            converter.resetForGenerationTransition()
        }
        let inputCount = Int(rate / 10)
        let input = (0..<(inputCount * 4)).map { Float($0) / 1_000_000 }
        var samples = [Float](), failures = [String](), outputs = [[String: Any]]()
        for index in 0..<4 {
            let offset = samples.count
            let converted = try converter.convert(
                buffer(Array(input[index * inputCount..<(index + 1) * inputCount]), rate: rate),
                hostTimeNanoseconds: times[index])
            if (converted.hostTimeNanoseconds != nil) != known[index] {
                failures.append("callback \(index): unexpected clock validity")
            }
            if known[index] {
                // Source position, independently identified by the waveform, selects the input clock.
                let sourceBatch = offset / 4_800
                if let time = times[sourceBatch], let actual = converted.hostTimeNanoseconds {
                    let expected = time + UInt64((Double(offset % 4_800) * 1_000_000_000 / 48_000).rounded())
                    if abs(Double(actual) - Double(expected)) > 1 {
                        failures.append("callback \(index): wrong source clock after boundary")
                    }
                } else { failures.append("callback \(index): missing expected source clock") }
            }
            outputs.append(["source_offset": offset, "output_count": converted.samples.count,
                            "timestamp_known": converted.hostTimeNanoseconds != nil])
            samples.append(contentsOf: converted.samples)
        }
        let expectedSamples = rate == 48_000 ? input : try reference(input, rate: rate)
        let matches = !samples.isEmpty && samples.count <= expectedSamples.count
            && samples == Array(expectedSamples.prefix(samples.count))
        if !matches { failures.append("clock boundary changed audio samples") }
        return ["scenario": scenario, "rate": rate, "pass": failures.isEmpty,
                "failures": failures, "source_prefix_matches": matches, "outputs": outputs]
    }

    static func main() throws {
        var results = [[String: Any]]()
        for rate in [48_000.0, 44_100.0] {
            for render in [false, true] {
                for (batches, reset) in [(1, false), (3, false), (3, true)] {
                    do { results.append(try run(rate: rate, render: render, reset: reset, batches: batches)) }
                    catch { results.append(["rate": rate, "render": render, "reset": reset,
                                            "pass": false, "error": String(describing: error)]) }
                }
            }
        }
        for rate in [48_000.0, 44_100.0] {
            for scenario in ["missing-start", "missing-middle", "forward-gap", "backward-jump",
                             "sub-sample-jitter", "reset-unknown"] {
                do { results.append(try clockBoundary(rate: rate, scenario: scenario)) }
                catch { results.append(["rate": rate, "scenario": scenario,
                                        "pass": false, "error": String(describing: error)]) }
            }
        }
        let passed = results.allSatisfy { $0["pass"] as? Bool == true }
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "pass": passed, "cases": results, "device_access": false], options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if !passed { exit(1) }
    }
}
