import Foundation

extension TransportTests {
    static func playbackLifecycle() throws {
        let rate = 48000.0
        let initial = identity()
        let worker = try AppleNativeVoiceTransportWorker(identity: initial, nativeRate: rate)
        let captureRing = nvt_ring_create(2048, initial.capture.token)!
        let playbackRing = nvt_ring_create(64, initial.playback.token)!
        defer {
            nvt_ring_destroy(captureRing)
            nvt_ring_destroy(playbackRing)
        }
        let sizes = [137, 521, 1031, 300, 700, 1201, 607, 941, 1333, 630, 877, 1550]
        let input = wave(sizes.reduce(0, +), rate: rate)
        var packets: [NativeVoiceCapturePacket] = []
        var offset = 0
        for (index, count) in sizes.enumerated() {
            let stamp = NVTStamp(
                sample_time: Int64(offset),
                host_time_ns: hostTime(at: Double(offset), rate: rate),
                flags: 3
            )
            let chunk = Array(input[offset ..< offset + count])
            expect(
                nvt_ring_write(captureRing, chunk, count, stamp, initial.capture.token) == NVT_WRITE_OK,
                "the original capture token remains writable"
            )
            if index == 4 {
                try completedPlayback(worker, ring: playbackRing)
            } else if index == 7 {
                try cancelledPlayback(worker, ring: playbackRing)
            }
            for _ in 0 ..< (count + 112) / 113 {
                packets += try worker.drainCapture(captureRing, maxFrames: 113)
            }
            offset += count
        }
        packets += try worker.finishCapture(identity: initial.capture)
        try assertContinuousPCM(packets, input: input, worker: worker, capture: initial.capture)
        let stats = nvt_ring_stats(captureRing)
        expect(
            stats.active_token == initial.capture.token && stats.acknowledged_token == initial.capture.token,
            "playback lifecycle keeps the capture ring identity"
        )
        for packet in packets where packet.sampleCount >= 480 {
            let expected = hostTime(at: Double(packet.sampleCount) * rate / 24000, rate: rate)
            expect(
                packet.timingStatus == .valid && packet.hostTimeNanoseconds == expected,
                "playback EOS and cancel preserve established capture clock"
            )
        }
        print("native_voice_playback_lifecycle=PASS")
    }

    static func directionalFences() throws {
        let initial = identity()
        let worker = try AppleNativeVoiceTransportWorker(identity: initial, nativeRate: 24000)
        let sharedChanges: [NativeVoiceIdentity.Authority] = [
            .init(runtimeGeneration: 2, routeEpoch: 1, configurationID: 1),
            .init(runtimeGeneration: 1, routeEpoch: 2, configurationID: 1),
            .init(runtimeGeneration: 1, routeEpoch: 1, configurationID: 2)
        ]
        for shared in sharedChanges {
            for (captureToken, playbackToken) in [(UInt64(1), UInt64(2)), (2, 1)] {
                let next = NativeVoiceIdentity(
                    authority: shared, captureGeneration: 1, captureToken: captureToken,
                    playbackEpoch: 1, playbackToken: playbackToken
                )
                try expectStale { try worker.reset(identity: next, nativeRate: 24000) }
                expect(
                    worker.identity.capture == initial.capture && worker.identity.playback == initial.playback,
                    "authority changes require both fences before mutating either direction"
                )
            }
        }
        _ = try worker.capture(
            [Float](repeating: 0.7, count: 479),
            sampleTime: 0,
            hostTime: anchor,
            identity: initial.capture
        )
        let signal = NativeVoicePCM16.encode([Float](repeating: 0.25, count: 599))
        var playback = try worker.playback(signal, identity: initial.playback)
        let next = NativeVoiceIdentity(
            authority: initial.capture.authority, captureGeneration: 2, captureToken: 2,
            playbackEpoch: initial.playback.epoch, playbackToken: initial.playback.token
        )
        try worker.reset(identity: next, nativeRate: 24000)
        try expectStale { _ = try worker.finishCapture(identity: initial.capture) }
        expect(worker.discardedCaptureTailSamples == 479, "capture generation invalidates the old partial packet")
        playback += try worker.finishPlayback(identity: initial.playback)
        expect(
            playback.count == 599 && playback.allSatisfy { $0 == 0.25 },
            "capture-only invalidation preserves playback SRC"
        )
    }

    static func timestampChangesPreservePCM(rate: Double) throws {
        let capture = identity().capture
        let worker = try AppleNativeVoiceTransportWorker(identity: identity(), nativeRate: rate)
        let sizes = [137, 501, 1111, 2491, 2255, 1127, 389, 743, 1279, 2200, 1087, 1211, 800, 1370, 1223, 463, 1831]
        let input = wave(sizes.reduce(0, +), rate: rate)
        let jump: UInt64 = 80_000_000
        var callbacks: [Int] = []
        var packets: [NativeVoiceCapturePacket] = []
        var offset = 0
        for (index, count) in sizes.enumerated() {
            callbacks.append(offset)
            let host = hostTime(at: Double(offset), rate: rate) + (index >= 5 ? jump : 0)
            packets += try worker.capture(
                Array(input[offset ..< offset + count]),
                sampleTime: 1_234_000 + Int64(offset),
                hostTime: index == 10 ? nil : host,
                identity: capture
            )
            offset += count
        }
        packets += try worker.finishCapture(identity: capture)
        try assertContinuousPCM(packets, input: input, worker: worker, capture: capture)
        assertTiming(
            packets,
            rate: rate,
            intervals: [
                (callbacks[2] ..< callbacks[5], 0),
                (callbacks[7] ..< callbacks[10], jump),
                (callbacks[13] ..< input.count, jump)
            ]
        )
        print("native_voice_timestamp_continuity_\(Int(rate))=PASS")
    }
}

private extension TransportTests {
    static func completedPlayback(_ worker: AppleNativeVoiceTransportWorker, ring: OpaquePointer) throws {
        let first = worker.identity.playback
        try finishTurn(worker, level: 0.25)
        try advancePlayback(worker, ring: ring, epoch: first.epoch, token: first.token + 1)
        try expectStale { _ = try worker.playback(Data([0, 0]), identity: first) }
        try finishTurn(worker, level: -0.25)
    }

    static func cancelledPlayback(_ worker: AppleNativeVoiceTransportWorker, ring: OpaquePointer) throws {
        let active = worker.identity.playback
        try advancePlayback(worker, ring: ring, epoch: active.epoch, token: active.token + 1)
        let cancelled = worker.identity.playback
        let signal = NativeVoicePCM16.encode([Float](repeating: 0.75, count: 1024))
        let queued = try Array(worker.playback(signal, identity: cancelled).prefix(32))
        expect(queued.count == 32, "cancellation test has real buffered PCM")
        expect(
            nvt_ring_write(ring, queued, queued.count, NVTStamp(), cancelled.token) == NVT_WRITE_OK,
            "the cancelled epoch had queued audio"
        )
        try advancePlayback(worker, ring: ring, epoch: cancelled.epoch + 1, token: cancelled.token + 1)
        try expectStale { _ = try worker.finishPlayback(identity: cancelled) }
        expect(
            nvt_ring_write(ring, queued, queued.count, NVTStamp(), cancelled.token) == NVT_WRITE_STALE,
            "delayed old playback cannot refill the cleared ring"
        )
        var output = [Float](repeating: 1, count: 32)
        let cleared = nvt_ring_read(ring, &output, nil, output.count, true, false)
        expect(cleared.copied == 0 && output.allSatisfy { $0 == 0 }, "cancel clears only playback PCM")
        try finishTurn(worker, level: 0)
    }

    static func advancePlayback(
        _ worker: AppleNativeVoiceTransportWorker, ring: OpaquePointer, epoch: UInt64, token: UInt64
    ) throws {
        let capture = worker.identity.capture
        let next = NativeVoiceIdentity(
            authority: capture.authority, captureGeneration: capture.generation, captureToken: capture.token,
            playbackEpoch: epoch, playbackToken: token
        )
        expect(nvt_ring_invalidate(ring, token), "playback control publishes the new token")
        try worker.reset(identity: next, nativeRate: worker.nativeRate)
        expect(nvt_ring_consumer_sync(ring) == token, "playback consumer acknowledges its own clear")
    }

    static func finishTurn(_ worker: AppleNativeVoiceTransportWorker, level: Float) throws {
        let playback = worker.identity.playback
        let pcm = NativeVoicePCM16.encode([Float](repeating: level, count: 1024))
        var output = try worker.playback(pcm, identity: playback)
        output += try worker.finishPlayback(identity: playback)
        let repeated = try worker.finishPlayback(identity: playback)
        expect(output.count == 2048 && repeated.isEmpty, "each playback turn drains its own SRC exactly once")
        expect(
            output.dropFirst(128).dropLast(128).allSatisfy { abs($0 - level) < 0.001 },
            "a fresh turn has no prior SRC tail"
        )
        do {
            _ = try worker.playback(pcm, identity: playback)
            preconditionFailure("audio after EOS must require the next playback token")
        } catch NativeVoiceTransportError.exhausted {}
    }

    static func expectStale(_ operation: () throws -> Void) throws {
        do {
            try operation()
            preconditionFailure("an old or incomplete identity was accepted")
        } catch NativeVoiceTransportError.staleIdentity {}
    }

    static func assertContinuousPCM(
        _ packets: [NativeVoiceCapturePacket],
        input: [Float],
        worker: AppleNativeVoiceTransportWorker,
        capture: NativeVoiceIdentity.Capture
    ) throws {
        let reference = try NativeVoiceStreamingSRC(inputRate: worker.nativeRate, outputRate: 24000)
        var output = try reference.append(input)
        output += try reference.finish()
        let fullSamples = output.count / 480 * 480
        let expected = NativeVoicePCM16.encode(Array(output.prefix(fullSamples)))
        let actual = packets.reduce(into: Data()) { $0.append($1.bytes) }
        expect(actual == expected, "capture PCM equals a continuous whole-input conversion")
        expect(worker.discardedCaptureTailSamples == output.count % 480, "only the incomplete EOS tail is discarded")
        for (index, packet) in packets.enumerated() {
            expect(packet.bytes.count == 960 && packet.sampleCount == UInt64(index * 480), "packet cursor has no gap")
            expect(packet.segment == 0 && packet.identity == capture, "one capture identity and continuous segment")
        }
    }

    static func assertTiming(
        _ packets: [NativeVoiceCapturePacket], rate: Double, intervals: [(Range<Int>, UInt64)]
    ) {
        var confirmed = [Int](repeating: 0, count: intervals.count)
        var mixedPackets = 0
        let boundaries = intervals.flatMap { [$0.0.lowerBound, $0.0.upperBound] }
        for packet in packets {
            let start = Double(packet.sampleCount) * rate / 24000
            let end = Double(packet.sampleCount + 480) * rate / 24000
            if boundaries.contains(where: { start < Double($0) && Double($0) < end }) {
                mixedPackets += 1
                expect(packet.timingStatus != .valid, "packets across timing boundaries cannot qualify")
            }
            if packet.timingStatus == .valid {
                guard let index = intervals.firstIndex(where: {
                    Double($0.0.lowerBound) <= start && end <= Double($0.0.upperBound)
                }) else { preconditionFailure("qualification leaked outside an observed mapping") }
                let expected = hostTime(at: start, rate: rate) + intervals[index].1
                expect(abs(Int64(packet.hostTimeNanoseconds!) - Int64(expected)) <= 1, "real re-anchor is used")
                confirmed[index] += 1
            } else {
                expect(
                    packet.hostTimeNanoseconds == nil && !packet.hasFreshTiming(now: anchor),
                    "unqualified PCM offers no timing or freshness"
                )
            }
        }
        expect(mixedPackets >= 4 && confirmed.allSatisfy { $0 > 0 }, "acquisition, jump and both recoveries exercised")
        expect(packets.contains { $0.timingStatus == .invalid }, "the jump supplies explicit invalid timing")
    }

    static func hostTime(at nativeFrame: Double, rate: Double) -> UInt64 {
        anchor + UInt64((nativeFrame * 1_000_000_000 / rate).rounded())
    }
}
