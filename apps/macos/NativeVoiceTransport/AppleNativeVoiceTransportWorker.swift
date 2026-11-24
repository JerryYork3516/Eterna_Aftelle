import Foundation

/// Mirrors external authority. Each token fences only its own ring and SRC.
nonisolated struct NativeVoiceIdentity: Sendable {
    struct Authority: Equatable, Sendable {
        let runtimeGeneration: UInt64
        let routeEpoch: UInt64
        let configurationID: UInt64
    }

    struct Capture: Equatable, Sendable {
        let authority: Authority
        let generation: UInt64
        let token: UInt64
    }

    struct Playback: Equatable, Sendable {
        let authority: Authority
        let epoch: UInt64
        let token: UInt64
    }

    let capture: Capture
    let playback: Playback

    init(
        authority: Authority,
        captureGeneration: UInt64,
        captureToken: UInt64,
        playbackEpoch: UInt64,
        playbackToken: UInt64
    ) {
        capture = Capture(authority: authority, generation: captureGeneration, token: captureToken)
        playback = Playback(authority: authority, epoch: playbackEpoch, token: playbackToken)
    }
}

nonisolated struct NativeVoiceCapturePacket: Sendable {
    let bytes: Data
    let identity: NativeVoiceIdentity.Capture
    let segment: UInt64
    let sampleCount: UInt64
    let hostTimeNanoseconds: UInt64?
    let timingStatus: NativeVoiceTimingStatus

    /// Necessary timing evidence only; this never grants acoustic/interrupt authority.
    func hasFreshTiming(now: UInt64) -> Bool {
        timingStatus == .valid && NativeVoiceClock.isFresh(hostTime: hostTimeNanoseconds, now: now)
    }
}

/// Conversion and packetization on the serial non-realtime worker.
final nonisolated class AppleNativeVoiceTransportWorker {
    private(set) var identity: NativeVoiceIdentity
    private(set) var nativeRate: Double
    private(set) var playbackRate: Double
    private var captureSRC: NativeVoiceStreamingSRC
    private var playbackSRC: NativeVoiceStreamingSRC
    private var clock: NativeVoiceClock
    private var pending: [Float] = []
    private var timingAnchor: (inputFrame: Int, sampleTime: Int64)?
    private var packetSampleCount: UInt64 = 0
    private var segment: UInt64 = 0
    private(set) var discardedCaptureTailSamples = 0

    init(identity: NativeVoiceIdentity, nativeRate: Double, playbackRate: Double? = nil) throws {
        guard identity.capture.token > 0, identity.playback.token > 0 else {
            throw NativeVoiceTransportError.staleIdentity
        }
        self.identity = identity
        self.nativeRate = nativeRate
        self.playbackRate = playbackRate ?? nativeRate
        captureSRC = try NativeVoiceStreamingSRC(inputRate: nativeRate, outputRate: 24000)
        playbackSRC = try NativeVoiceStreamingSRC(inputRate: 24000, outputRate: self.playbackRate)
        clock = NativeVoiceClock(sampleRate: nativeRate)
    }

    /// The control owner advances only the affected ring tokens. A new utterance can advance
    /// the playback token even when its enclosing playback epoch has not changed.
    func reset(identity next: NativeVoiceIdentity, nativeRate: Double, playbackRate: Double? = nil) throws {
        let outputRate = playbackRate ?? nativeRate
        let captureChanged = next.capture != identity.capture
        let playbackChanged = next.playback != identity.playback
        let configurationChanged = next.capture.authority.configurationID != identity.capture.authority.configurationID
        guard captureChanged || playbackChanged,
              !captureChanged || next.capture.token > identity.capture.token,
              !playbackChanged || next.playback.token > identity.playback.token,
              configurationChanged || (nativeRate == self.nativeRate && outputRate == self.playbackRate)
        else {
            throw NativeVoiceTransportError.staleIdentity
        }
        let capture = captureChanged ? try NativeVoiceStreamingSRC(inputRate: nativeRate, outputRate: 24000) : nil
        let playback = playbackChanged ? try NativeVoiceStreamingSRC(inputRate: 24000, outputRate: outputRate) : nil
        if let capture {
            discardPending()
            captureSRC = capture
            clock = NativeVoiceClock(sampleRate: nativeRate)
        }
        if let playback {
            playbackSRC = playback
        }
        identity = next
        self.nativeRate = nativeRate
        self.playbackRate = outputRate
    }

    func capture(
        _ samples: [Float],
        sampleTime: Int64?,
        hostTime: UInt64?,
        identity: NativeVoiceIdentity.Capture,
        droppedFrames: UInt64 = 0,
        independentHostObservation: Bool = true
    ) throws -> [NativeVoiceCapturePacket] {
        guard identity == self.identity.capture else { throw NativeVoiceTransportError.staleIdentity }
        guard !samples.isEmpty else { return [] }
        var observedClock = clock
        let observation = observedClock.observe(
            sampleTime: sampleTime,
            frames: samples.count,
            hostTime: hostTime,
            droppedFrames: droppedFrames,
            independentHostObservation: independentHostObservation
        )
        let converter = observation.discontinuity
            ? try NativeVoiceStreamingSRC(inputRate: nativeRate, outputRate: 24000) : captureSRC
        let inputStart = converter.inputFrames
        let output = try converter.append(samples)
        if observation.discontinuity {
            discardPending()
            captureSRC = converter
        }
        clock = observedClock
        if observation.status != .valid {
            timingAnchor = nil
        } else if timingAnchor == nil, let sampleTime {
            timingAnchor = (inputStart, sampleTime)
        }
        pending += output
        return packets()
    }

    func finishCapture(identity: NativeVoiceIdentity.Capture) throws -> [NativeVoiceCapturePacket] {
        guard identity == self.identity.capture else { throw NativeVoiceTransportError.staleIdentity }
        pending += try captureSRC.finish()
        let result = packets()
        // Never pad a partial 20ms packet, including after a real capture gap.
        discardedCaptureTailSamples += pending.count
        pending.removeAll(keepingCapacity: true)
        return result
    }

    func playback(_ pcm16LE: Data, identity: NativeVoiceIdentity.Playback) throws -> [Float] {
        guard identity == self.identity.playback else { throw NativeVoiceTransportError.staleIdentity }
        return try playbackSRC.append(NativeVoicePCM16.decode(pcm16LE))
    }

    func finishPlayback(identity: NativeVoiceIdentity.Playback) throws -> [Float] {
        guard identity == self.identity.playback else { throw NativeVoiceTransportError.staleIdentity }
        return try playbackSRC.finish()
    }

    /// Consumer endpoint only. Original callback stamps survive arbitrary read sizes.
    func drainCapture(
        _ ring: OpaquePointer, maxFrames: Int, requiresConfiguration: Bool = false
    ) throws -> [NativeVoiceCapturePacket] {
        guard maxFrames > 0, maxFrames <= 1_048_576 else { throw NativeVoiceTransportError.invalidPCM }
        let captureIdentity = identity.capture
        guard nvt_ring_active_token(ring) == captureIdentity.token
        else { throw NativeVoiceTransportError.staleIdentity }
        var samples = [Float](repeating: 0, count: maxFrames)
        var frames = [NVTFrame](repeating: NVTFrame(), count: maxFrames)
        let result = nvt_ring_read(ring, &samples, &frames, maxFrames, false, false)
        guard !result.invalidated,
              result.token == captureIdentity.token else { throw NativeVoiceTransportError.staleIdentity }
        var packets: [NativeVoiceCapturePacket] = []
        var start = 0
        while start < result.copied {
            let frame = frames[start]
            guard !requiresConfiguration || frame.ingress.configuration_id == captureIdentity.authority.configurationID
            else { throw NativeVoiceTransportError.staleIdentity }
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
                identity: captureIdentity,
                droppedFrames: frame.offset == 0 ? frame.ingress.dropped_before : 0,
                independentHostObservation: frame.offset == 0
            )
            start = end
        }
        guard nvt_ring_active_token(ring) == captureIdentity.token
        else { throw NativeVoiceTransportError.staleIdentity }
        return packets
    }

    private func packets() -> [NativeVoiceCapturePacket] {
        var result: [NativeVoiceCapturePacket] = []
        while pending.count >= 480 {
            let host = packetHostTime()
            let status: NativeVoiceTimingStatus = host != nil ? .valid :
                (clock.status == .invalid ? .invalid : .unknown)
            result.append(NativeVoiceCapturePacket(
                bytes: NativeVoicePCM16.encode(Array(pending.prefix(480))),
                identity: identity.capture,
                segment: segment,
                sampleCount: packetSampleCount,
                hostTimeNanoseconds: host,
                timingStatus: status
            ))
            pending.removeFirst(480)
            packetSampleCount += 480
        }
        return result
    }

    private func packetHostTime() -> UInt64? {
        guard let timingAnchor else { return nil }
        // SRC may return pre-anchor content after qualification. Check the packet's source position.
        let offset = Double(packetSampleCount) * nativeRate / captureSRC.outputRate - Double(timingAnchor.inputFrame)
        guard offset >= 0 else { return nil }
        return clock.qualifiedHost(sampleTime: timingAnchor.sampleTime, offsetFrames: offset)
    }

    private func discardPending() {
        discardedCaptureTailSamples += pending.count + captureSRC.unreleasedContentFrames
        pending.removeAll(keepingCapacity: true)
        packetSampleCount = 0
        timingAnchor = nil
        segment += 1
    }
}
