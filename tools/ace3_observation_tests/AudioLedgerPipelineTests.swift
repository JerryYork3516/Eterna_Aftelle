import AVFoundation
import Foundation

private struct LedgerPipelineResult: Equatable {
    var packets: [MacSpeechPCM16Packet] = []
    var frames: [MacSpeechAudioFrame] = []
    var observations: [MacSpeechAcousticObservationSnapshot] = []
    var operations: [String] = []
    var counts: [UInt64] = []
}

private final class SecondCaptureFails: MacSpeechAECBackend, @unchecked Sendable {
    let base = TestAEC()
    var count = 0
    var linearOutputDelaySamples: Int {
        0
    }

    var processedOutputDelaySamples: Int {
        0
    }

    func configure() throws {
        try base.configure()
    }

    func processRender(_ samples: [Float]) throws {
        try base.processRender(samples)
    }

    func processCapture(_ samples: [Float]) throws -> MacSpeechAECCaptureResult {
        count += 1
        if count == 2 {
            throw MacSpeechAECBackendError.captureFailed
        }
        return try base.processCapture(samples)
    }

    func setDelay(milliseconds: Int) throws {
        try base.setDelay(milliseconds: milliseconds)
    }

    func reset() throws {
        try base.reset()
    }

    func stats() throws -> MacSpeechAECBackendStats {
        try base.stats()
    }
}

extension AudioObservationTests {
    static func testLedgerBuffer(_ artifacts: inout [String: String]) throws {
        let off = ledgerBufferFixture()
        let url = destination()
        expect(recorder.arm(at: url), "queue arm")
        let observed = ledgerBufferFixture()
        expect(recorder.seal().invalidReasons == 0, "queue recorder intact")
        expect(off == observed, "queue contents and monotonic order off/on")
        let records = try events(url)
        expect(
            records.contains { $0.kind == 19 && $0.status == 8 && $0.inputStart == 1 },
            "drop-oldest identity"
        )
        expect(records.contains { $0.kind == 19 && $0.status == 7 }, "rejected generation explicit")
        expect(
            records.contains { $0.kind == 19 && $0.status == 10 && $0.generation == 1 },
            "generation clear explicit"
        )
        expect(records.contains { $0.kind == 19 && $0.status == 9 && $0.generation == 2 }, "drain explicit")
        artifacts["buffer"] = url.lastPathComponent
    }

    private static func ledgerBufferFixture() -> [MacSpeechAudioFrame] {
        let queue = MacSpeechAudioFrameBuffer(capacity: 2)
        let bytes = MacSpeechPCM16Encoder.encode(samples: [Float](repeating: 0.1, count: 480))
        queue.begin(generation: 1)
        for index in 0 ..< 3 {
            _ = queue.append(pcm16Bytes: bytes, activity: 0.1, generation: 1, timestamp: UInt64(index + 1))
        }
        _ = queue.append(pcm16Bytes: bytes, activity: 0.1, generation: 0, timestamp: 4)
        queue.begin(generation: 2)
        _ = queue.append(pcm16Bytes: bytes, activity: 0.1, generation: 2, timestamp: 5)
        let result = queue.drain(maxCount: 1)
        queue.end(generation: 2)
        return result
    }

    static func testLedgerPipeline(_ artifacts: inout [String: String]) throws {
        let off = try ledgerPipelineFixture()
        let url = destination()
        expect(recorder.arm(at: url), "pipeline arm")
        let observed = try ledgerPipelineFixture()
        expect(recorder.seal().invalidReasons == 0, "pipeline recorder intact")
        expect(off == observed, "PCM classifications Gate epochs packets queue and AEC/delay order off/on")
        expect(!observed.packets.isEmpty && !observed.frames.isEmpty, "fixture exercises packet delivery")
        let records = try events(url)
        expect(records.contains { $0.kind == 12 && $0.flags & 8 == 0 }, "actual Host returned spans observed")
        expect(records.contains { $0.kind == 19 && $0.status == 8 }, "pipeline queue overflow exercised")
        artifacts["pipeline"] = url.lastPathComponent
        try testLedgerHostFailure(&artifacts)
    }

    private static func ledgerPipelineFixture() throws -> LedgerPipelineResult {
        let backend = TestAEC()
        #if AFTELLE_WEBRTC_AEC3
            backend.real = MacSpeechWebRTCAECProcessor()
        #endif
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
        _ = host.configure()
        let converter = try MacSpeechAudioConverter(inputFormat: buffer(rate: 48000, count: 480).format)
        let queue = MacSpeechAudioFrameBuffer(capacity: 2)
        var result = LedgerPipelineResult()
        var generation: UInt64 = 7
        queue.begin(generation: generation)
        for index in 0 ..< 8 {
            if index == 4 {
                generation = 8
                host.discardPendingCaptureForGenerationTransition()
                converter.resetForGenerationTransition()
                queue.begin(generation: generation)
            }
            let signal = [Float](repeating: Float(index + 1) / 100, count: 1920)
            let time = UInt64(1_000_000_000 + index * 40_000_000)
            host.processRender(signal, hostTimeNanoseconds: time)
            let spans = host.processCaptureSpans(signal, hostTimeNanoseconds: time)
            result.observations.append(contentsOf: spans.map(\.observation))
            let packets = try ledgerDeliver(spans, converter: converter, queue: queue, generation: generation)
            result.packets.append(contentsOf: packets)
            if index.isMultiple(of: 2) {
                result.frames.append(contentsOf: queue.drain(maxCount: 1))
            }
        }
        result.frames.append(contentsOf: queue.drain(maxCount: 99))
        let stats = queue.stats()
        result.counts = [stats.generatedCount, stats.droppedCount, stats.rejectedStaleCount]
        result.operations = backend.operations
        return result
    }

    private static func ledgerDeliver(
        _ spans: [MacSpeechAcousticCaptureSpan],
        converter: MacSpeechAudioConverter,
        queue: MacSpeechAudioFrameBuffer,
        generation: UInt64
    ) throws
        -> [MacSpeechPCM16Packet] {
        // Same deterministic methods; this synthetic envelope is not a native callback.
        var event = recorder.begin(.deliveryBatch, stream: 1)
        event?.generation = generation
        event?.status = 3
        defer { recorder.finish(event) }
        let packets = try converter.convert(captureSpans: spans)
        event?.status = 0
        event?.outputEnd = UInt64(packets.count)
        for packet in packets {
            _ = queue.append(pcm16Bytes: packet.bytes, activity: packet.activity,
                             generation: generation,
                             timestamp: packet.acousticSnapshot?.captureHostTimeNanoseconds ?? 1,
                             activityEvidenceKind: packet.activityEvidenceKind,
                             acousticSnapshot: packet.acousticSnapshot)
        }
        return packets
    }

    private static func testLedgerHostFailure(_ artifacts: inout [String: String]) throws {
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: SecondCaptureFails())
        _ = host.configure()
        host.playbackStarted()
        let url = destination()
        expect(recorder.arm(at: url), "Host failure arm")
        let output = host.processCaptureSpans([Float](repeating: 0.1, count: 960),
                                              hostTimeNanoseconds: 1_000_000_000)
        expect(output.isEmpty, "whole-batch fallback discards first frame result")
        expect(recorder.seal().invalidReasons == 0, "Host exception trace sealed")
        let records = try events(url)
        expect(records.contains { $0.kind == 9 }, "first frame reached Gate")
        expect(
            records.contains { $0.kind == 12 && $0.flags & 8 != 0 && $0.frameCount == 0 },
            "final empty return explicit"
        )
        expect(
            !records.contains { $0.kind == 12 && $0.flags & 8 == 0 },
            "provisional output not mislabeled final"
        )
        expect(records.contains { $0.kind == 23 && $0.status == 3 }, "fallback reason explicit")
        artifacts["host_failure"] = url.lastPathComponent
    }
}
