import Darwin
import Foundation

@main private struct SilentDoubleTalkTests {
    private enum Failure: Error { case invalidInput(String) }

    private static func samples(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count == 2000 * 480 * 4 else {
            throw Failure.invalidInput(url.lastPathComponent)
        }
        return data.withUnsafeBytes { bytes in
            (0..<data.count / 4).map {
                Float(bitPattern: UInt32(littleEndian:
                    bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
            }
        }
    }

    private static func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    }

    private static func run(_ scenario: String, directory: URL) throws -> [String: Any] {
        let render = try samples(directory.appendingPathComponent(scenario + ".render48"))
        let raw = try samples(directory.appendingPathComponent(scenario + ".raw48"))
        let near = try samples(directory.appendingPathComponent(scenario + ".near48"))
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: MacSpeechWebRTCAECProcessor())
        guard host.configure() == .webRTCAEC3 else { throw Failure.invalidInput("AEC configure failed") }
        host.updateDelay(outputPresentationLatencySeconds: 0.003, capturePresentationLatencySeconds: 0)
        host.playbackStarted()
        var gates = Set<Int>(), forwarded = Set<Int>(), simultaneous = Set<Int>()
        var knownNear = Set<Int>(), knownFar = Set<Int>()
        var forwardedSamples = [Bool](repeating: false, count: raw.count)
        var firstEmission: Int?, userEvidence = 0, duplicateForwardedFrames = 0
        var powers = [String: Double](), delays = Set<Int>()
        for frame in 0..<2000 {
            let range = frame * 480..<(frame + 1) * 480
            let farFrame = Array(render[range]), rawFrame = Array(raw[range])
            let nearRMS = rms(Array(near[range])), farRMS = rms(farFrame)
            // Truth comes from generated inputs, never the Host classification.
            if nearRMS >= 0.006 { knownNear.insert(frame) }
            if farRMS >= 0.005 { knownFar.insert(frame) }
            if nearRMS >= 0.006 && farRMS >= 0.005 { simultaneous.insert(frame) }
            let time = UInt64(1_000_000_000) + UInt64(frame) * 10_000_000
            // The physical 120 ms echo path is already encoded in raw samples.
            host.processRender(farFrame, hostTimeNanoseconds: time)
            let spans = host.processCaptureSpans(rawFrame, hostTimeNanoseconds: time)
            let state = host.snapshot()
            if state.sourceGateOpen { gates.insert(frame) }
            if state.inputClassification == .nearEndSpeech || state.inputClassification == .doubleTalk {
                userEvidence += 1
            }
            for span in spans where span.observation.sourceGateOpen && span.samples.contains(where: { $0 != 0 }) {
                if !forwarded.insert(Int(span.observation.captureFrameIndex) - 1).inserted {
                    duplicateForwardedFrames += 1
                }
                let offset = (Int(span.observation.captureFrameIndex) - 1) * 480
                for sample in offset..<min(offset + span.samples.count, forwardedSamples.count) {
                    forwardedSamples[sample] = true
                }
                if firstEmission == nil { firstEmission = frame }
            }
            if frame >= 1200 {
                for (track, value) in ["raw": state.rawCaptureRMS, "render": farRMS,
                    "near": nearRMS, "clean": state.processedCaptureRMS, "linear": state.linearAECOutputRMS] {
                    powers[track, default: 0] += value * value
                }
                delays.insert(state.estimatedDelayMilliseconds)
            }
        }
        let state = host.snapshot(), positive = scenario.hasPrefix("double-talk")
        let ending = scenario.hasPrefix("double-talk-ending")
        let isolated = scenario.hasSuffix("-isolated")
        // Existing AEC3 output alignment: 144 low-band samples = 432 samples at 48 kHz.
        let outputDelay = 432
        let missingNearFrames = knownNear.sorted().filter { frame in
            let start = frame * 480 + outputDelay
            guard start + 480 <= forwardedSamples.count else { return false }
            return !forwardedSamples[start..<start + 480].allSatisfy { $0 }
        }
        // This is the existing 20-frame weak-evidence budget, not a semantic VAD timeout.
        let nearEndSample = (near.lastIndex(where: { $0 != 0 }) ?? -1) + 1
        let closureDeadline = Int(ceil(Double(nearEndSample + outputDelay) / 480)) + 20
        var failures = [String]()
        func expect(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        expect(state.mode == .webRTCAEC3 && state.active && state.fallbackCount == 0, "AEC must stay active without fallback")
        expect(state.captureFrameCount == 2000 && state.renderFrameCount == 2000, "all 2000 frames must be processed")
        if isolated { expect(raw == near, "isolated fixture has no remote echo in microphone input") }
        expect(knownFar.filter { $0 >= 1200 }.count == 800, "far-end must remain audible throughout evaluation")
        if positive {
            expect(gates.allSatisfy { $0 >= 1200 } && forwarded.allSatisfy { $0 >= 1200 }, "echo warmup must not open or forward")
            if ending {
                expect(!knownNear.isEmpty && simultaneous == knownNear, "known near-end must overlap audible far-end")
                expect(missingNearFrames.isEmpty, "every known active near-end frame must survive source gating, including onset and tail")
                expect(duplicateForwardedFrames == 0, "near-end source frames must not be emitted twice")
                expect(near[(1780 * 480)...].allSatisfy { $0 == 0 }, "all ten near-end syllable periods finish by 17.8 seconds")
                expect(knownFar.filter { $0 >= 1780 }.count == 220, "resident remains audible after near-end stops")
                expect(gates.allSatisfy { $0 < closureDeadline } && forwarded.allSatisfy { $0 < closureDeadline },
                       "gate closes within the existing weak-evidence budget and does not reopen for echo")
            } else {
                expect(knownNear.count >= 500 && simultaneous == knownNear, "known near-end must overlap audible far-end")
                expect(forwarded.intersection(simultaneous).count >= 500, "simultaneous known near-end must be forwarded")
            }
        } else {
            expect(near.allSatisfy { $0 == 0 }, "negative must contain no near-end samples")
            expect(gates.isEmpty && forwarded.isEmpty && userEvidence == 0, "pure echo must not open, forward, or become user evidence")
        }
        return ["scenario": scenario, "pass": failures.isEmpty, "failures": failures,
            "frame_count": 2000, "gate_frames": gates.count, "forwarded_frames": forwarded.count,
            "both_active_frames": simultaneous.count, "both_gate_frames": gates.intersection(simultaneous).count,
            "both_forwarded_frames": forwarded.intersection(simultaneous).count,
            "missing_active_near_frames_after_aec_alignment": missingNearFrames,
            "duplicate_forwarded_frames": duplicateForwardedFrames,
            "ending_case": ending, "closure_deadline_frame": ending ? closureDeadline as Any : NSNull(),
            "isolated_input_fixture": isolated,
            "last_near_source_sample_exclusive": nearEndSample,
            "gate_frames_after_closure_deadline": ending ? gates.filter { $0 >= closureDeadline }.count as Any : NSNull(),
            "limits": "Sample coverage tests gate retention, not word intelligibility or physical-device acceptance",
            "first_gate_frame": gates.min() as Any? ?? NSNull(),
            "first_forwarded_source_frame": forwarded.min() as Any? ?? NSNull(),
            "first_emission_frame": firstEmission as Any? ?? NSNull(),
            "first_known_near_frame": knownNear.min() as Any? ?? NSNull(),
            "evaluation_rms": powers.mapValues { sqrt($0 / 800) },
            "estimated_delay_ms": delays.sorted(), "fallback_count": state.fallbackCount]
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.invalidInput("expected output directory") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var results = [[String: Any]]()
        for scenario in ["echo-only-normal", "echo-only-loud", "double-talk-normal", "double-talk-loud",
                         "double-talk-ending-normal", "double-talk-ending-loud", "double-talk-ending-isolated"] {
            do { results.append(try run(scenario, directory: directory)) }
            catch { results.append(["scenario": scenario, "pass": false, "error": String(describing: error)]) }
        }
        let passed = results.allSatisfy { $0["pass"] as? Bool == true }
        let report: [String: Any] = ["schema_version": 1, "pass": passed,
            "evidence": "synthetic_inputs_actual_WebRTC_and_production_Host", "physical_device_test": false,
            "activity_rms": ["known_near": 0.006, "known_far": 0.005], "cases": results]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("result.json"))
        print(String(decoding: data, as: UTF8.self))
        if !passed { exit(1) }
    }
}
