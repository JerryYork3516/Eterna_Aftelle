import Foundation

@main
struct TransportTests {
    private nonisolated(unsafe) static var checks = 0
    static let anchor: UInt64 = 10_000_000_000

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    static func identity(_ token: UInt64 = 1, configuration: UInt64 = 1) -> NativeVoiceIdentity {
        NativeVoiceIdentity(
            authority: .init(runtimeGeneration: token, routeEpoch: token, configurationID: configuration),
            captureGeneration: token,
            captureToken: token,
            playbackEpoch: token,
            playbackToken: token
        )
    }

    static func main() throws {
        for rate in [16000.0, 24000, 44100, 48000, 96000, 22050] {
            try streaming(from: rate, to: 24000)
            try streaming(from: 24000, to: rate)
            try packetization(rate: rate)
            clock(rate: rate)
        }
        try clippingAndErrors()
        try identityReset()
        try captureGap()
        try bufferedWorker()
        try playbackLifecycle()
        try directionalFences()
        for rate in [16000.0, 24000, 44100, 48000] {
            try timestampChangesPreservePCM(rate: rate)
        }
        print("native_voice_transport_checks=\(checks)")
        print("native_voice_rate_pairs=12\nnative_voice_device_access=ZERO")
    }

    static func wave(_ count: Int, rate: Double) -> [Float] {
        (0 ..< count).map { Float(0.35 * sin(2 * Double.pi * 431 * Double($0) / rate)) }
    }

    private static func streaming(from inputRate: Double, to outputRate: Double) throws {
        let source = wave(Int(inputRate * 0.43) + 17, rate: inputRate)
        let whole = try NativeVoiceStreamingSRC(inputRate: inputRate, outputRate: outputRate)
        var expected = try whole.append(source)
        expected += try whole.finish()
        let converter = try NativeVoiceStreamingSRC(inputRate: inputRate, outputRate: outputRate)
        var actual: [Float] = []
        let sizes = [1, 7, 128, 511, 3, 1024, 441, 79]
        var offset = 0
        var chunk = 0
        while offset < source.count {
            let count = min(sizes[chunk % sizes.count], source.count - offset)
            actual += try converter.append(Array(source[offset ..< offset + count]))
            offset += count
            chunk += 1
            expect(
                converter.outputFrames <= Int(Double(offset) * outputRate / inputRate),
                "no output beyond available content"
            )
        }
        actual += try converter.finish()
        expect(
            actual.count == Int((Double(source.count) * outputRate / inputRate).rounded(.down)),
            "rational frame conservation"
        )
        expect(actual.count == expected.count, "chunk-independent length")
        let error = zip(actual, expected).map { abs($0 - $1) }.max() ?? 0
        expect(error < 0.00001, "streaming equals single continuous conversion")
        expect(actual.allSatisfy { $0.isFinite && abs($0) < 0.45 }, "amplitude finite and bounded")
        expect(actual.suffix(100).contains { abs($0) > 0.01 }, "tail contains signal")
        let repeated = try converter.finish()
        expect(repeated.isEmpty, "EOS does not duplicate tail")
        do {
            _ = try converter.append([1]); preconditionFailure("append after EOS")
        } catch NativeVoiceTransportError.exhausted {}
    }

    private static func packetization(rate: Double) throws {
        let worker = try AppleNativeVoiceTransportWorker(identity: identity(), nativeRate: rate)
        let size = Int(rate / 50)
        var packets: [NativeVoiceCapturePacket] = []
        for index in 0 ..< 15 {
            packets += try worker.capture(
                wave(size, rate: rate),
                sampleTime: Int64(index * size),
                hostTime: anchor + UInt64(Double(index * size) * 1e9 / rate),
                identity: identity().capture
            )
        }
        packets += try worker.finishCapture(identity: identity().capture)
        let outputFrames = Int(Double(size * 15) * 24000 / rate)
        expect(packets.count == outputFrames / 480, "timing acquisition preserves every complete packet")
        expect(worker.discardedCaptureTailSamples == outputFrames % 480, "only the incomplete EOS tail is discarded")
        expect(packets.allSatisfy { $0.bytes.count == 960 }, "480 mono PCM16LE samples")
        let valid = packets.filter { $0.timingStatus == .valid }
        expect(!valid.isEmpty, "observed clock acquires mapping")
        for packet in valid {
            expect(packet.hasFreshTiming(now: packet.hostTimeNanoseconds! + 500_000_000), "500ms inclusive")
            expect(!packet.hasFreshTiming(now: packet.hostTimeNanoseconds! + 500_000_001), "stale rejects")
            expect(!packet.hasFreshTiming(now: packet.hostTimeNanoseconds! - 1), "future rejects")
        }
        for (first, second) in zip(valid, valid.dropFirst()) where first.segment == second.segment {
            expect(second.sampleCount - first.sampleCount == 480, "sample cursor advances by packet content")
            expect(
                abs(Int64(second.hostTimeNanoseconds!) - Int64(first.hostTimeNanoseconds!) - 20_000_000) <= 1,
                "host mapped from packet start"
            )
        }
    }
}

private extension TransportTests {
    static func clock(rate: Double) {
        let size = Int(rate / 100)
        func time(_ index: Int) -> UInt64 {
            anchor + UInt64((Double(index * size) * 1e9 / rate).rounded())
        }
        var clock = NativeVoiceClock(sampleRate: rate)
        for index in 0 ..< 3 {
            let observation = clock.observe(sampleTime: Int64(index * size), frames: size, hostTime: time(index))
            expect(!observation.discontinuity, "normal sample continuity")
        }
        expect(clock.status == .valid, "three real anchors qualify")
        let jump: UInt64 = 80_000_000
        let fault = clock.observe(sampleTime: Int64(3 * size), frames: size, hostTime: time(3) + jump)
        expect(fault.status == .invalid && !fault.discontinuity, "host anomaly does not invent sample loss")
        expect(clock.qualifiedHost(sampleTime: 0) == nil, "invalid mapping has no qualification")
        _ = clock.observe(sampleTime: Int64(4 * size), frames: size, hostTime: time(4) + jump)
        expect(clock.status == .unknown, "one follow-up cannot recover")
        _ = clock.observe(sampleTime: Int64(5 * size), frames: size, hostTime: time(5) + jump)
        expect(clock.status == .valid, "same generation recovers from actual stable timestamps")
        expect(
            abs(Int64(clock.qualifiedHost(sampleTime: Int64(5 * size))!) - Int64(time(5) + jump)) <= 1,
            "new mapping uses actual host anchor with integer-nanosecond rounding"
        )
        let gap = clock.observe(
            sampleTime: Int64(7 * size),
            frames: size,
            hostTime: time(7) + jump,
            droppedFrames: UInt64(size)
        )
        expect(gap.discontinuity && gap.status == .unknown, "real loss breaks sample timeline")
        let missing = clock.observe(sampleTime: Int64(8 * size), frames: size, hostTime: nil)
        expect(missing.status == .unknown, "missing host cannot qualify")
        let backwards = clock.observe(sampleTime: 1, frames: size, hostTime: time(9))
        expect(backwards.discontinuity, "sample rollback breaks content")
        _ = clock.observe(sampleTime: nil, frames: size, hostTime: time(10))
        expect(clock.status == .unknown, "missing sample clock cannot qualify")
        _ = clock.observe(sampleTime: Int64.max, frames: size, hostTime: time(11))
        expect(clock.status == .unknown, "overflow cannot qualify")
        clockWithoutIndependentAnchors(rate: rate)
    }

    static func clockWithoutIndependentAnchors(rate: Double) {
        let size = Int(rate / 100)
        func time(_ index: Int) -> UInt64 {
            anchor + UInt64((Double(index * size) * 1e9 / rate).rounded())
        }
        var split = NativeVoiceClock(sampleRate: rate)
        for index in 0 ..< 5 {
            _ = split.observe(
                sampleTime: Int64(index * size),
                frames: size,
                hostTime: time(index),
                independentHostObservation: index == 0
            )
        }
        expect(split.status == .unknown, "slicing one callback does not fabricate independent host observations")
        var rollback = NativeVoiceClock(sampleRate: rate)
        _ = rollback.observe(sampleTime: 0, frames: size, hostTime: anchor)
        let bad = rollback.observe(sampleTime: Int64(size), frames: size, hostTime: anchor - 1)
        expect(bad.status == .invalid, "backward host invalid")
    }

    private static func clippingAndErrors() throws {
        let bytes = NativeVoicePCM16.encode([-2, -1, -0.5, 0, 0.5, 1, 2])
        expect(Array(bytes) == [0, 128, 0, 128, 0, 192, 0, 0, 0, 64, 255, 127, 255, 127], "saturating little endian")
        let decoded = try NativeVoicePCM16.decode(bytes)
        expect(decoded[0] == -1 && decoded[6] == Float(32767) / 32768, "PCM endpoints")
        do {
            _ = try NativeVoicePCM16.decode(Data([1])); preconditionFailure("odd PCM bytes")
        } catch NativeVoiceTransportError.invalidPCM {}
        for rate in [0.0, -1, .nan, .infinity] {
            do { _ = try NativeVoiceStreamingSRC(inputRate: rate, outputRate: 24000); preconditionFailure("bad format")
            } catch NativeVoiceTransportError.unsupportedFormat {}
        }
        let converter = try NativeVoiceStreamingSRC(inputRate: 44100, outputRate: 24000)
        do {
            _ = try converter.append([.nan]); preconditionFailure("nonfinite PCM")
        } catch NativeVoiceTransportError.invalidPCM {}
        let short = try converter.append([0.5]) + converter.finish()
        expect(short.isEmpty, "fractional tail is reported, never padded")
    }

    private static func identityReset() throws {
        let worker = try AppleNativeVoiceTransportWorker(identity: identity(), nativeRate: 48000)
        _ = try worker.capture(
            [Float](repeating: 0.8, count: 500),
            sampleTime: 0,
            hostTime: anchor,
            identity: identity().capture
        )
        _ = try worker.playback(
            NativeVoicePCM16.encode([Float](repeating: 0.9, count: 300)),
            identity: identity().playback
        )
        try worker.reset(identity: identity(2), nativeRate: 48000)
        do {
            _ = try worker.playback(Data([0, 0]), identity: identity().playback); preconditionFailure("old generation")
        } catch NativeVoiceTransportError.staleIdentity {}
        let mismatched = NativeVoiceIdentity.Capture(
            authority: .init(runtimeGeneration: 2, routeEpoch: 999, configurationID: 1),
            generation: 2,
            token: 2
        )
        do {
            _ = try worker
                .capture(
                    [0],
                    sampleTime: 0,
                    hostTime: anchor,
                    identity: mismatched
                ); preconditionFailure("old route/config")
        } catch NativeVoiceTransportError.staleIdentity {}
        var silence = try worker.playback(Data(repeating: 0, count: 9600), identity: identity(2).playback)
        silence += try worker.finishPlayback(identity: identity(2).playback)
        expect(silence.allSatisfy { $0 == 0 }, "old SRC filter tail does not revive after reset")
        do {
            try worker.reset(identity: identity(3), nativeRate: 44100); preconditionFailure("rate identity")
        } catch NativeVoiceTransportError.staleIdentity {}
        try worker.reset(identity: identity(3, configuration: 2), nativeRate: 44100)
    }

    static func captureGap() throws {
        let gapWorker = try AppleNativeVoiceTransportWorker(identity: identity(), nativeRate: 24000)
        _ = try gapWorker.capture(
            [Float](repeating: 0.4, count: 479),
            sampleTime: 0,
            hostTime: nil,
            identity: identity().capture
        )
        let packets = try gapWorker.capture(
            [Float](repeating: -0.4, count: 480),
            sampleTime: 960,
            hostTime: nil,
            identity: identity().capture,
            droppedFrames: 481
        )
        let tail = try gapWorker.finishCapture(identity: identity().capture)
        expect((packets + tail).count == 1, "loss cannot join partial packets or create zero packets")
        let decoded = try NativeVoicePCM16.decode((packets + tail)[0].bytes)
        expect(decoded.allSatisfy { abs($0 + 0.4) < 0.001 }, "pre-gap samples not replayed")
        expect(gapWorker.discardedCaptureTailSamples > 0, "incomplete tail accounted")
    }

    private static func bufferedWorker() throws {
        let ring = nvt_ring_create(2048, 1)!
        defer { nvt_ring_destroy(ring) }
        let worker = try AppleNativeVoiceTransportWorker(identity: identity(), nativeRate: 24000)
        var packets: [NativeVoiceCapturePacket] = []
        for index in 0 ..< 10 {
            let samples = wave(480, rate: 24000)
            let stamp = NVTStamp(
                sample_time: Int64(index * 480),
                host_time_ns: anchor + UInt64(index) * 20_000_000,
                flags: 3
            )
            expect(nvt_ring_write(ring, samples, 480, stamp, 1) == NVT_WRITE_OK, "callback ingress")
            for _ in 0 ..< 5 {
                packets += try worker.drainCapture(ring, maxFrames: 113)
            }
        }
        packets += try worker.finishCapture(identity: identity().capture)
        expect(packets.contains { $0.timingStatus == .valid }, "ring metadata maps through worker")
        expect(nvt_ring_invalidate(ring, 2), "control invalidation")
        do {
            _ = try worker.drainCapture(ring, maxFrames: 100); preconditionFailure("old worker cannot drain")
        } catch NativeVoiceTransportError.staleIdentity {}
        try worker.reset(identity: identity(2), nativeRate: 24000)
        let drained = try worker.drainCapture(ring, maxFrames: 100)
        expect(drained.isEmpty, "consumer acknowledges clear")
        expect(nvt_ring_stats(ring).acknowledged_token == 2, "ack is distinct from physical playback")
    }
}
