import AVFoundation
import Foundation
import Synchronization

@main
enum AudioObservationTests {
    static let recorder = MacSpeechAudioObservation.shared
    static let checks = Atomic<Int>(0)
    static let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks.wrappingAdd(1, ordering: .relaxed)
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func destination() -> URL {
        directory.appendingPathComponent(UUID().uuidString + ".bin")
    }

    static func events(_ url: URL) throws -> [MacSpeechAudioObservationEvent] {
        let data = try Data(contentsOf: url)
        let size = MemoryLayout<MacSpeechAudioObservationEvent>.stride
        expect(data.count % size == 0, "complete fixed-width records")
        return data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: size).map {
                bytes.loadUnaligned(fromByteOffset: $0, as: MacSpeechAudioObservationEvent.self)
            }
        }
    }

    static func checkFrameBoundaries(
        calls: [MacSpeechAudioObservationEvent], frames: [MacSpeechAudioObservationEvent]
    ) {
        for call in calls {
            let children = frames.filter { $0.parent == call.id }
            expect(
                children.count == Int(call.frameCount / 480),
                "one callback batch contains multiple processing frames"
            )
            expect(
                call.entered <= call.began && call.began <= call.completed,
                "queue submit begin return"
            )
            for frame in children {
                expect(
                    call.began <= frame.began && frame.began <= frame.completed
                        && frame.completed <= call.completed,
                    "actual AEC interval nested in Host call"
                )
                expect(frame.inputEnd - frame.inputStart == 480, "480-sample frame source interval")
            }
        }
    }

    static func testEquivalenceAndFraming() throws {
        expect(recorder.begin(.hostCall) == nil, "default off")
        let off = hostFixture()
        let url = destination()
        expect(recorder.arm(at: url), "arm")
        let observed = hostFixture()
        let summary = recorder.seal()
        expect(off.pcm == observed.pcm, "bit-exact PCM off/on")
        expect(off.observations == observed.observations, "classification Gate epochs source identity off/on")
        expect(off.operations == observed.operations, "AEC/control call order including delay values off/on")
        expect(
            summary.invalidReasons == 0 && summary.pending == 0 && summary.lost == 0,
            "valid complete fixture"
        )
        let records = try events(url)
        let calls = records.filter { $0.kind == 3 }
        let frames = records.filter { $0.kind == 4 }
        expect(
            calls.contains { $0.frameCount == 480 } && calls.contains { $0.frameCount == 4800 },
            "10ms and 100ms batches"
        )
        checkFrameBoundaries(calls: calls, frames: frames)
        expect(records.first?.kind == 100 && records.last?.kind == 101, "arm seal records")
        expect(
            records.contains { $0.kind == 5 }, "lifecycle reset observed without behavior change"
        )
        for call in calls {
            let resets = records.filter {
                $0.kind == 5 && $0.stream == call.stream && $0.object == call.object
                    && $0.id < call.id
            }
            if let reset = resets.last {
                expect(
                    call.epoch == reset.detail, "epoch consistent across arm and lifecycle reset"
                )
            }
        }
    }
}

extension AudioObservationTests {
    static func testNativeConvertersAndEarlyExit() throws {
        let backend = TestAEC()
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
        _ = host.configure()
        let engine = SystemMacSpeechVoiceProcessingEngine(
            acousticEchoHost: host,
            voiceActivityDetector: NoDeviceVAD()
        )
        let frames = MacSpeechAudioFrameBuffer()
        frames.begin(generation: 7)
        let url = destination()
        expect(recorder.arm(at: url), "native test arm")
        for rate in [44100.0, 48000.0] {
            let input = buffer(rate: rate, count: Int(rate / 10))
            try engine.prepareObservationTestConverters(input.format)
            for sequence in 0 ..< 3 {
                let time = AVAudioTime(
                    hostTime: AVAudioTime.hostTime(forSeconds: 1 + Double(sequence) / 10),
                    sampleTime: Int64(sequence * Int(rate / 10)), atRate: rate
                )
                engine.observationTestCallback(
                    input, when: time, stream: 2, generation: 7, frameBuffer: frames
                )
                engine.observationTestCallback(
                    input, when: time, stream: 1, generation: 7, frameBuffer: frames
                )
            }
            engine.observationTestCallback(
                input, when: AVAudioTime(sampleTime: 20000, atRate: rate),
                stream: 1, generation: 7, frameBuffer: frames
            )
            engine.observationTestCallback(
                input, when: AVAudioTime(hostTime: 123),
                stream: 2, generation: 7, frameBuffer: frames
            )
        }
        let emptyInput = buffer(rate: 48000, count: 480)
        emptyInput.frameLength = 0
        engine.observationTestCallback(
            emptyInput, when: AVAudioTime(hostTime: 123),
            stream: 2, generation: 7, frameBuffer: frames
        )
        engine.discardPendingAudioForGenerationTransition()
        let input = buffer(rate: 48000, count: 480)
        engine.observationTestCallback(
            input, when: AVAudioTime(hostTime: 1),
            stream: 1, generation: 8, frameBuffer: frames
        )
        let summary = recorder.seal()
        expect(summary.invalidReasons == 0, "native scalar trace complete")
        try checkNativeConverterRecords(events(url))
    }

    static func testConverterEquivalence() throws {
        for rate in [44100.0, 48000.0] {
            let baseline = try converterFixture(rate: rate)
            expect(recorder.arm(at: destination()), "converter equivalence arm")
            let observed = try converterFixture(rate: rate)
            expect(recorder.seal().invalidReasons == 0, "converter trace complete")
            for (before, after) in zip(baseline, observed) {
                expect(before.samples == after.samples, "converter PCM off/on")
                expect(before.hostTimeNanoseconds == after.hostTimeNanoseconds,
                       "converter content time off/on")
                expect(before.timestampFailureReason == after.timestampFailureReason,
                       "converter timestamp validity off/on")
            }
        }
    }

    static func testUnavailableConverter() throws {
        let input = buffer(rate: 48000, count: 480)
        let frames = MacSpeechAudioFrameBuffer()
        frames.begin(generation: 1)
        let unavailableHost = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: TestAEC())
        let unavailable = SystemMacSpeechVoiceProcessingEngine(
            acousticEchoHost: unavailableHost,
            voiceActivityDetector: NoDeviceVAD()
        )
        let unavailableURL = destination()
        expect(recorder.arm(at: unavailableURL), "early exit arm")
        unavailable.observationTestCallback(
            input, when: AVAudioTime(hostTime: 123), stream: 1,
            generation: 1, frameBuffer: frames
        )
        _ = recorder.seal()
        let unavailableRecords = try events(unavailableURL)
        expect(
            unavailableRecords.contains { $0.kind == 6 && $0.status == 5 },
            "converter unavailable terminal"
        )
    }

    static func testRemainderAndFailure() throws {
        let backend = TestAEC()
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
        _ = host.configure()
        let url = destination()
        expect(recorder.arm(at: url), "failure fixture arm")
        host.processRender([])
        _ = host.processCaptureSpans([])
        _ = host.processCaptureSpans(
            [Float](repeating: 0.1, count: 240), hostTimeNanoseconds: 1_000_000_000
        )
        _ = host.processCaptureSpans(
            [Float](repeating: 0.1, count: 240), hostTimeNanoseconds: 2_000_000_000
        )
        host.playbackCompleted()
        backend.failCapture = true
        _ = host.processCaptureSpans(
            [Float](repeating: 0.1, count: 960), hostTimeNanoseconds: 3_000_000_000
        )
        _ = recorder.seal()
        let records = try events(url)
        expect(
            records.contains { $0.kind == 3 && $0.remainderAfter == 240 }, "pending 240-sample tail"
        )
        expect(records.filter { $0.kind == 3 && $0.frameCount == 0 && $0.status == 9 }.count == 2,
               "empty input has no invented queue or AEC completion")
        expect(records.contains { $0.kind == 3 && $0.status == 7 }, "discontinuity terminal")
        expect(records.contains { $0.kind == 4 && $0.status == 6 }, "AEC exception completion")
        expect(
            records.contains {
                $0.kind == 3 && $0.frameCount == 960 && $0.outputEnd == 0 && $0.status == 6
            }, "failed and unprocessed input range"
        )
    }

    static func testConcurrentAndReuse() throws {
        let url = destination()
        expect(recorder.arm(at: url), "concurrent arm")
        for round in 0 ..< 4 {
            DispatchQueue.concurrentPerform(iterations: 8) { lane in
                for index in 0 ..< 1000 {
                    let sequence = round * 1000 + index
                    var event = recorder.begin(.rejected, stream: UInt64(lane + 1))
                    event?.inputStart = UInt64(sequence)
                    event?.outputStart = UInt64(sequence) ^ 0xA55A
                    recorder.finish(event)
                }
            }
            // Control-thread barrier between bounded bursts, not producer backpressure.
            let deadline = recorder.now() + 2_000_000_000
            while recorder.summary().written < UInt64((round + 1) * 8000), recorder.now() < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
            expect(
                recorder.summary().written == UInt64((round + 1) * 8000),
                "worker drains bounded concurrent burst"
            )
        }
        let summary = recorder.seal()
        expect(
            summary.invalidReasons == 0 && summary.written == 32000,
            "MPSC and ring reuse without losses"
        )
        let records = try events(url).filter { $0.kind == 7 }
        expect(Set(records.map(\.id)).count == 32000, "unique producer tickets")
        expect(
            records.allSatisfy { $0.outputStart == $0.inputStart ^ 0xA55A },
            "no torn scalar payload"
        )
        for lane in 1 ... 8 {
            expect(
                Set(records.filter { $0.stream == UInt64(lane) }.map(\.inputStart)).count == 4000,
                "per-producer complete coverage"
            )
        }
    }

    static func testCreationAndWriteFailures() {
        recorder.failWrites.store(true, ordering: .relaxed)
        expect(recorder.arm(at: destination()), "write failure arm")
        let failed = recorder.seal()
        expect(failed.invalidReasons & 4 != 0, "write failure invalid")
        recorder.failWrites.store(false, ordering: .relaxed)

        let failedRun = recorder.summary().run
        let invalidPath = directory.appendingPathComponent("absent-" + UUID().uuidString)
            .appendingPathComponent("trace.bin")
        expect(!recorder.arm(at: invalidPath), "open failure does not arm")
        expect(
            recorder.summary().run > failedRun && recorder.summary().invalidReasons & 4 != 0,
            "open failure has a separate diagnostic run identity"
        )

        recorder.failWorkerSetup.store(true, ordering: .relaxed)
        expect(!recorder.arm(at: destination()), "worker creation failure does not arm")
        expect(recorder.summary().invalidReasons & 16 != 0, "worker creation failure INVALID")
        recorder.failWorkerSetup.store(false, ordering: .relaxed)
    }

    static func testInvalidAndSealing() throws {
        recorder.stallWorker.store(true, ordering: .relaxed)
        let fullURL = destination()
        expect(recorder.arm(at: fullURL), "overflow arm")
        for _ in 0 ... MacSpeechAudioObservation.capacity {
            recorder.finish(recorder.begin(.rejected))
        }
        expect(recorder.activeRun == 0, "overflow stops new reservations")
        recorder.stallWorker.store(false, ordering: .relaxed)
        let full = recorder.seal()
        expect(
            full.invalidReasons & 1 != 0 && full.lost == 1 && full.pending == 0,
            "overflow lost terminal accounted"
        )
        expect(full.admitted == full.written + full.lost + full.pending, "reservation conservation")

        let pendingURL = destination()
        expect(recorder.arm(at: pendingURL), "pending arm")
        let pending = recorder.begin(.nativeCallback)
        let sealed = recorder.seal()
        expect(
            sealed.pending == 1 && sealed.invalidReasons & 8 != 0,
            "seal outstanding callback without waiting for realtime thread"
        )
        expect(!recorder.arm(at: destination()), "no reuse while producer owns slot")
        recorder.finish(pending)

        testCreationAndWriteFailures()

        let emptyURL = destination()
        expect(recorder.arm(at: emptyURL), "no-playback arm")
        let empty = recorder.seal()
        expect(
            empty.admitted == 0 && empty.pending == 0 && empty.invalidReasons == 0,
            "no-playback early seal complete"
        )
        let emptyRecords = try events(emptyURL)
        expect(emptyRecords.count == 2, "empty run arm/seal")
        expect(recorder.begin(.converter) == nil, "closed recorder cannot publish")
        expect(
            !recorder.arm(at: destination(), windowNanoseconds: 60_000_000_001), "60-second ceiling"
        )
        expect(recorder.arm(at: destination(), windowNanoseconds: 1_000_000), "short deadline arm")
        Thread.sleep(forTimeInterval: 0.02)
        expect(recorder.seal().invalidReasons & 2 != 0, "deadline stops no-playback run")
    }

    static func main() throws {
        if CommandLine.arguments.contains("--abrupt-exit") {
            let url = directory.appendingPathComponent(UUID().uuidString + ".aborted")
            expect(recorder.arm(at: url), "abrupt-exit arm")
            recorder.finish(recorder.begin(.nativeCallback))
            Thread.sleep(forTimeInterval: 0.02)
            _exit(0) // Missing seal must never be accepted as a complete run.
        }
        #if AFTELLE_WEBRTC_AEC3
            let off = hostFixture(real: true)
            expect(recorder.arm(at: destination()), "production AEC arm")
            let observed = hostFixture(real: true)
            expect(recorder.seal().invalidReasons == 0, "production AEC trace complete")
            expect(off.pcm == observed.pcm, "production AEC bitwise PCM off/on")
            expect(off.observations == observed.observations, "production AEC classification/Gate/epoch off/on")
            expect(off.operations == observed.operations, "production AEC call order and delay values off/on")
            print(
                "production_aec_equivalence=PASS pcm_bytes=\(observed.pcm.count) "
                    + "observations=\(observed.observations.count)"
            )
        #endif
        if CommandLine.arguments.contains("--recorder-only") {
            try testConcurrentAndReuse()
            try testInvalidAndSealing()
            print("recorder_checks=\(checks.load(ordering: .relaxed))")
            return
        }
        try testEquivalenceAndFraming()
        try testNativeConvertersAndEarlyExit()
        try testConverterEquivalence()
        try testUnavailableConverter()
        try testRemainderAndFailure()
        try testConcurrentAndReuse()
        try testInvalidAndSealing()
        expect(recorder.allocatedBytes <= 8 * 1024 * 1024, "resident allocation certificate")
        print(
            "step2a_checks=\(checks.load(ordering: .relaxed)) "
                + "allocation_certificate_bytes=\(recorder.allocatedBytes) "
                + "slots=\(MacSpeechAudioObservation.capacity)"
        )
        print("device_callbacks_p99=NOT_MEASURED microphones_speakers=NOT_STARTED")
    }
}
