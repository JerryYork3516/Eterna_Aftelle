import AVFoundation
import Foundation

extension AudioObservationTests {
    static func runLedgerTests() throws {
        var artifacts: [String: String] = [:]
        try testLedgerGate(&artifacts)
        try testLedgerPackets(&artifacts)
        try testLedgerConversionFailure(&artifacts)
        try testLedgerBuffer(&artifacts)
        try testLedgerPipeline(&artifacts)
        try testLedgerMixedPacket(&artifacts)
        try testLedgerIntegrity(&artifacts)
        let manifest = try JSONSerialization.data(withJSONObject: artifacts, options: [.sortedKeys])
        try manifest.write(to: directory.appendingPathComponent("ledger-artifacts.json"))
        print("step2b_checks=\(checks.load(ordering: .relaxed)) synthetic_memory_only=true")
    }

    static func testLedgerGate(_ artifacts: inout [String: String]) throws {
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: TestAEC())
        _ = host.configure()
        let url = destination()
        expect(recorder.arm(at: url), "O3 arm")
        let zeros = [Float](repeating: 0, count: 480)
        let actualPass = host.processCaptureSpans(zeros, hostTimeNanoseconds: 1_000_000_000)
        host.playbackStarted()
        let actualZero = host.processCaptureSpans(zeros, hostTimeNanoseconds: 2_000_000_000)
        expect(
            actualPass.first?.samples == actualZero.first?.samples,
            "actual Gate PASS versus ZERO on zero PCM"
        )
        host.playbackStopped()
        let passed = host.observationTestGate(action: 1, frame: 1001, samples: zeros)
        let zeroed = host.observationTestGate(action: 4, frame: 1002, samples: zeros)
        expect(passed[0].samples == zeroed[0].samples, "zero PCM alone cannot identify Gate ZERO")
        expect(host.observationTestGate(action: 2, frame: 1003, samples: zeros).isEmpty, "RETAIN no delivery")
        let released = host.observationTestGate(action: 3, frame: 0, samples: [])
        expect(released.first?.observation.captureFrameIndex == 1003, "release preserves origin frame")
        expect(released.first?.observation.sourceGateEpoch == 1, "release records current epoch")
        _ = host.observationTestGate(action: 2, frame: 1004, samples: zeros)
        _ = host.observationTestGate(action: 5, frame: 0, samples: [])
        for frame in 1010 ..< 1030 {
            _ = host.observationTestGate(action: 6, frame: UInt64(frame), samples: zeros)
        }
        _ = host.observationTestGate(action: 2, frame: 1040, samples: zeros)
        expect(recorder.seal().invalidReasons == 0, "O3 recorder intact")
        let records = try events(url)
        checkGateActions(records)
        artifacts["gate"] = url.lastPathComponent
        let crossRunURL = destination()
        expect(recorder.arm(at: crossRunURL), "cross-run release arm")
        let prior = host.observationTestGate(action: 3, frame: 0, samples: [])
        expect(
            prior.first?.observation.captureFrameIndex == 1040,
            "pre-arm origin retained without relabeling"
        )
        expect(recorder.seal().invalidReasons == 0, "recorder complete does not prove source ancestry")
        artifacts["cross_run"] = crossRunURL.lastPathComponent
    }

    static func checkGateActions(_ records: [MacSpeechAudioObservationEvent]) {
        let actions = records.filter { $0.kind == 10 }
        expect(actions.contains { $0.reserved == 1001 && $0.status == 1 }, "zero-valued PASS is PASS")
        expect(actions.contains { $0.reserved == 1002 && $0.status == 4 }, "active ZERO is explicit")
        expect(actions.filter { $0.reserved == 1003 }.map(\.status) == [2, 3], "RETAIN then RELEASE")
        expect(actions.filter { $0.reserved == 1004 }.map(\.status) == [2, 5], "RETAIN then reset removal")
        expect(actions.filter { $0.reserved == 1040 }.map(\.status) == [2], "RETAIN stays pending at seal")
        expect(
            actions.contains { $0.reserved >= 1010 && $0.reserved < 1030 && $0.status == 1 },
            "hangover PASS"
        )
        expect(
            actions.contains { $0.reserved >= 1010 && $0.reserved < 1030 && $0.status == 4 },
            "hangover ZERO"
        )
        expect(records.contains { $0.kind == 11 && $0.epoch == 1 }, "current epoch recorded separately")
        expect(
            records.filter { $0.kind == 9 && $0.reserved >= 1000 }.allSatisfy { $0.flags & 1024 != 0 },
            "synthetic Gate inputs labeled"
        )
    }

    static func testLedgerPackets(_ artifacts: inout [String: String]) throws {
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: TestAEC())
        _ = host.configure()
        let input = [Float](repeating: 0.1, count: 480)
        let near = host.observationTestGate(action: 1, frame: 2001, samples: input)[0].observation
        let echo = host.observationTestGate(action: 4, frame: 2002, samples: input)[0].observation
        let url = destination()
        expect(recorder.arm(at: url), "packet arm")
        var packetizer = MacSpeechPCM16Packetizer()
        expect(packetizer.append(samples: [Float](repeating: 0.1, count: 240),
                                 activityEvidenceKind: .sourceGatedNearEnd, acousticSnapshot: near).isEmpty,
               "10ms retained")
        let packets = packetizer.append(samples: [Float](repeating: 0, count: 240),
                                        activityEvidenceKind: .none, acousticSnapshot: echo)
        expect(packets.count == 1 && packets[0].bytes.count == 960, "two 10ms inputs form 20ms packet")
        expect(packets[0].acousticSnapshot == near, "representative does not identify all fragments")
        _ = packetizer.append(samples: [Float](repeating: 0.1, count: 17))
        packetizer.reset()
        _ = packetizer.append(samples: [Float](repeating: 0, count: 23))
        let encoded = MacSpeechPCM16Encoder.encode(samples: [.nan, .infinity, .leastNormalMagnitude, 0])
        expect(encoded == Data(repeating: 0, count: 8), "nonfinite and natural quantization unchanged")
        expect(recorder.seal().invalidReasons == 0, "packet recorder intact")
        let records = try events(url)
        expect(
            records.filter { $0.kind == 15 && $0.frameCount == 240 }.count == 2,
            "both fragment sources recorded"
        )
        expect(
            records.contains { $0.kind == 17 && $0.detail == 2 && $0.reserved == 1 },
            "nonfinite versus quantization counters"
        )
        expect(
            records.contains { $0.kind == 18 && $0.remainderBefore == 17 },
            "reset accounts for pending tail"
        )
        artifacts["packets"] = url.lastPathComponent
    }

    static func testLedgerConversionFailure(_ artifacts: inout [String: String]) throws {
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: TestAEC())
        _ = host.configure()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                                   channels: 1, interleaved: false)!
        let converter = try MacSpeechAudioConverter(inputFormat: format)
        let url = destination()
        expect(recorder.arm(at: url), "conversion arm")
        let spans = host.processCaptureSpans([Float](repeating: 0.1, count: 4800),
                                             hostTimeNanoseconds: 1_000_000_000)
        converter.observationTestFailureAfterConversions = 4
        do {
            _ = try converter.convert(captureSpans: spans)
            expect(false, "injected post-convert failure throws")
        } catch {
            expect(true, "conversion throw observed")
        }
        converter.observationTestFailureAfterConversions = nil
        converter.resetForGenerationTransition()
        _ = try converter.convert(captureSpans: Array(spans.prefix(3)))
        expect(recorder.seal().invalidReasons == 0, "failure affects ledger not recorder")
        let records = try events(url)
        expect(records.contains { $0.kind == 14 && $0.status == 3 }, "failed batch terminal")
        expect(
            records.contains { $0.kind == 13 && $0.status == 3 && $0.flags & 512 != 0 },
            "partial converter output observed"
        )
        expect(records.contains { $0.kind == 16 }, "local packet can exist before batch failure")
        expect(records.filter { $0.kind == 13 }.allSatisfy { $0.flags & 64 != 0 }, "FIR support not invented")
        artifacts["conversion"] = url.lastPathComponent
        let resumedURL = destination()
        expect(recorder.arm(at: resumedURL), "stateful converter second run arm")
        _ = try converter.convert(buffer(rate: 48000, count: 480))
        expect(recorder.seal().invalidReasons == 0, "second run sealed")
        let resumed = try events(resumedURL)
        expect(resumed.contains { $0.kind == 13 && $0.flags & 128 != 0 }, "prior run FIR history unknown")
        artifacts["converter_resumed"] = resumedURL.lastPathComponent
    }

    static func testLedgerIntegrity(_ artifacts: inout [String: String]) throws {
        expect(MemoryLayout<MacSpeechAudioObservationEvent>.stride == 224, "schema stride unchanged")
        expect(MacSpeechAudioObservation.capacity == 16384, "slot count unchanged")
        expect(recorder.allocatedBytes == 4_128_768, "capacity certificate unchanged")
        expect(MacSpeechAudioObservation.maximumWindowNanoseconds == 60_000_000_000, "window unchanged")
        let url = destination()
        recorder.stallWorker.store(true, ordering: .relaxed)
        expect(recorder.arm(at: url), "O3 event overflow arm")
        for _ in 0 ... MacSpeechAudioObservation.capacity {
            recorder.finish(recorder.begin(.gateDecision))
        }
        expect(recorder.activeRun == 0, "overflow stops O3 acceptance")
        recorder.stallWorker.store(false, ordering: .relaxed)
        let full = recorder.seal()
        expect(full.invalidReasons & 1 != 0 && full.lost == 1, "O3 overflow INVALID and lost")
        expect(full.admitted == full.written + full.lost + full.pending, "O3 reservation conservation")
        artifacts["overflow"] = url.lastPathComponent
        let pendingURL = destination()
        expect(recorder.arm(at: pendingURL), "O4 pending arm")
        let event = recorder.begin(.convert24)
        let summary = recorder.seal()
        expect(summary.pending == 1 && summary.invalidReasons & 8 != 0, "O4 in-flight pending INVALID")
        recorder.finish(event)
        artifacts["pending"] = pendingURL.lastPathComponent
    }

    static func testLedgerMixedPacket(_ artifacts: inout [String: String]) throws {
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: TestAEC())
        _ = host.configure()
        let converter = try MacSpeechAudioConverter(inputFormat: buffer(rate: 48000, count: 480).format)
        let url = destination()
        expect(recorder.arm(at: url), "mixed actual Gate pipeline arm")
        var packets: [MacSpeechPCM16Packet] = []
        for index in 0 ..< 3 {
            if index == 1 { host.playbackStarted() }
            let samples = [Float](repeating: index == 0 ? 0.1 : 0, count: 480)
            let spans = host.processCaptureSpans(samples,
                hostTimeNanoseconds: UInt64(1_000_000_000 + index * 10_000_000))
            packets.append(contentsOf: try converter.convert(captureSpans: spans))
        }
        expect(packets.count == 1, "one mixed packet after actual AV conversion")
        expect(recorder.seal().invalidReasons == 0, "mixed ledger complete")
        let records = try events(url)
        expect(records.contains { $0.kind == 10 && $0.status == 1 }, "actual PASS source")
        expect(records.contains { $0.kind == 10 && $0.status == 4 }, "actual ZERO source")
        artifacts["mixed"] = url.lastPathComponent
    }
}
