import Foundation

/// A mirror of the existing owners' IDs. transportToken only fences this buffer.
nonisolated struct NativeVoiceIdentity: Equatable {
    let runtimeGeneration: UInt64
    let routeEpoch: UInt64
    let playbackEpoch: UInt64
    let captureGeneration: UInt64
    let configurationID: UInt64
    let transportToken: UInt64
}

nonisolated struct NativeVoiceCapturePacket {
    let bytes: Data
    let identity: NativeVoiceIdentity
    let segment: UInt64
    let sampleCount: UInt64
    let hostTimeNanoseconds: UInt64?
    let timingStatus: NativeVoiceTimingStatus

    /// Necessary timing evidence only; this never grants acoustic/interrupt authority.
    func hasFreshTiming(now: UInt64) -> Bool {
        timingStatus == .valid && NativeVoiceClock.isFresh(hostTime: hostTimeNanoseconds, now: now)
    }
}

/// P1 has no engine, nodes, tasks or production caller. Invoke on one serial worker.
final nonisolated class AppleNativeVoiceTransportWorker {
    private(set) var identity: NativeVoiceIdentity
    private(set) var nativeRate: Double
    private var captureSRC: NativeVoiceStreamingSRC
    private var playbackSRC: NativeVoiceStreamingSRC
    private var clock: NativeVoiceClock
    private var pending: [Float] = []
    private var sourceStart: Int64?
    private var packetSampleCount: UInt64 = 0
    private var segment: UInt64 = 0
    private var timingStatus: NativeVoiceTimingStatus = .unknown
    private(set) var discardedCaptureTailSamples = 0

    init(identity: NativeVoiceIdentity, nativeRate: Double) throws {
        guard identity.transportToken > 0 else { throw NativeVoiceTransportError.staleIdentity }
        self.identity = identity
        self.nativeRate = nativeRate
        captureSRC = try NativeVoiceStreamingSRC(inputRate: nativeRate, outputRate: 24000)
        playbackSRC = try NativeVoiceStreamingSRC(inputRate: 24000, outputRate: nativeRate)
        clock = NativeVoiceClock(sampleRate: nativeRate)
    }

    func reset(identity next: NativeVoiceIdentity, nativeRate: Double) throws {
        guard next.transportToken > identity.transportToken,
              next.configurationID != identity.configurationID || nativeRate == self.nativeRate
        else {
            throw NativeVoiceTransportError.staleIdentity
        }
        let capture = try NativeVoiceStreamingSRC(inputRate: nativeRate, outputRate: 24000)
        let playback = try NativeVoiceStreamingSRC(inputRate: 24000, outputRate: nativeRate)
        discardPending()
        identity = next
        self.nativeRate = nativeRate
        captureSRC = capture
        playbackSRC = playback
        clock = NativeVoiceClock(sampleRate: nativeRate)
        sourceStart = nil
        timingStatus = .unknown
    }

    func capture(
        _ samples: [Float],
        sampleTime: Int64?,
        hostTime: UInt64?,
        identity: NativeVoiceIdentity,
        droppedFrames: UInt64 = 0,
        independentHostObservation: Bool = true
    ) throws -> [NativeVoiceCapturePacket] {
        try require(identity)
        guard !samples.isEmpty else { return [] }
        let observation = clock.observe(
            sampleTime: sampleTime,
            frames: samples.count,
            hostTime: hostTime,
            droppedFrames: droppedFrames,
            independentHostObservation: independentHostObservation
        )
        if observation.discontinuity || observation.status != timingStatus {
            discardPending()
            captureSRC = try NativeVoiceStreamingSRC(inputRate: nativeRate, outputRate: 24000)
            sourceStart = nil
        }
        timingStatus = observation.status
        if sourceStart == nil {
            sourceStart = sampleTime
        }
        pending += try captureSRC.append(samples)
        return packets()
    }

    func finishCapture(identity: NativeVoiceIdentity) throws -> [NativeVoiceCapturePacket] {
        try require(identity)
        pending += try captureSRC.finish()
        let result = packets()
        // Never pad a partial 20ms packet, including after a real capture gap.
        discardedCaptureTailSamples += pending.count
        pending.removeAll(keepingCapacity: true)
        return result
    }

    func playback(_ pcm16LE: Data, identity: NativeVoiceIdentity) throws -> [Float] {
        try require(identity)
        return try playbackSRC.append(NativeVoicePCM16.decode(pcm16LE))
    }

    func finishPlayback(identity: NativeVoiceIdentity) throws -> [Float] {
        try require(identity)
        return try playbackSRC.finish()
    }

    /// Consumer endpoint only. Original callback stamps survive arbitrary read sizes.
    func drainCapture(_ ring: OpaquePointer, maxFrames: Int) throws -> [NativeVoiceCapturePacket] {
        guard maxFrames > 0, maxFrames <= 1_048_576 else { throw NativeVoiceTransportError.invalidPCM }
        guard nvt_ring_active_token(ring) == identity.transportToken
        else { throw NativeVoiceTransportError.staleIdentity }
        var samples = [Float](repeating: 0, count: maxFrames)
        var frames = [NVTFrame](repeating: NVTFrame(), count: maxFrames)
        let result = nvt_ring_read(ring, &samples, &frames, maxFrames, false, false)
        guard !result.invalidated,
              result.token == identity.transportToken else { throw NativeVoiceTransportError.staleIdentity }
        var packets: [NativeVoiceCapturePacket] = []
        var start = 0
        while start < result.copied {
            let frame = frames[start]
            var end = start + 1
            while end < result.copied, frames[end].origin.sample_time == frame.origin.sample_time,
                  frames[end].origin.host_time_ns == frame.origin.host_time_ns,
                  frames[end].origin.flags == frame.origin.flags,
                  frames[end].offset == frame.offset + UInt32(end - start) {
                end += 1
            }
            let sampleTime = frame.origin.flags & UInt32(NVT_SAMPLE_TIME_VALID) != 0
                ? frame.origin.sample_time + Int64(frame.offset) : nil
            let offsetNS = UInt64((Double(frame.offset) * 1_000_000_000 / nativeRate).rounded())
            let time = frame.origin.host_time_ns.addingReportingOverflow(offsetNS)
            let hostTime = frame.origin.flags & UInt32(NVT_HOST_TIME_VALID) != 0 && !time.overflow ? time
                .partialValue : nil
            packets += try capture(
                Array(samples[start ..< end]),
                sampleTime: sampleTime,
                hostTime: hostTime,
                identity: identity,
                independentHostObservation: frame.offset == 0
            )
            start = end
        }
        guard nvt_ring_active_token(ring) == identity.transportToken
        else { throw NativeVoiceTransportError.staleIdentity }
        return packets
    }

    private func packets() -> [NativeVoiceCapturePacket] {
        var result: [NativeVoiceCapturePacket] = []
        while pending.count >= 480 {
            let host = sourceStart.flatMap {
                clock.qualifiedHost(sampleTime: $0, offsetFrames: Double(packetSampleCount) * nativeRate / 24000)
            }
            result.append(NativeVoiceCapturePacket(
                bytes: NativeVoicePCM16.encode(Array(pending.prefix(480))),
                identity: identity,
                segment: segment,
                sampleCount: packetSampleCount,
                hostTimeNanoseconds: host,
                timingStatus: timingStatus
            ))
            pending.removeFirst(480)
            packetSampleCount += 480
        }
        return result
    }

    private func require(_ candidate: NativeVoiceIdentity) throws {
        guard candidate == identity else { throw NativeVoiceTransportError.staleIdentity }
    }

    private func discardPending() {
        discardedCaptureTailSamples += pending.count + captureSRC.unreleasedContentFrames
        pending.removeAll(keepingCapacity: true)
        packetSampleCount = 0
        segment += 1
    }
}
