import AudioToolbox
import Foundation

nonisolated struct NativeVoiceRenderFact: Sendable {
    let playback: NativeVoiceIdentity.Playback
    let timeFlags: UInt32
    let sampleTime: Double?
    let hostTime: UInt64?
    let hostTimeNanoseconds: UInt64?
    let frameCount: UInt32
    let submittedFrames: UInt32
    let nonzeroFrames: UInt32
    let nonzeroSpan: Range<UInt32>?
    let acknowledgedToken: UInt64
    let flags: UInt32

    init(_ fact: NVTRenderFact, playback: NativeVoiceIdentity.Playback) {
        self.playback = playback
        timeFlags = fact.time_flags
        let time = AudioTimeStampFlags(rawValue: timeFlags)
        sampleTime = time.contains(.sampleTimeValid) && fact.sample_time.isFinite ? fact.sample_time : nil
        hostTime = time.contains(.hostTimeValid) && fact.host_time != 0 ? fact.host_time : nil
        hostTimeNanoseconds = fact.host_time_ns != 0 ? fact.host_time_ns : nil
        frameCount = fact.frame_count
        submittedFrames = fact.submitted_frames
        nonzeroFrames = fact.nonzero_frames
        nonzeroSpan = nonzeroFrames > 0 ? fact.first_nonzero ..< fact.nonzero_end : nil
        acknowledgedToken = fact.acknowledged_token
        flags = fact.flags
    }
}

/// Owned exclusively by the transport actor. Retired callbacks keep their original C allocation.
final nonisolated class NativeVoiceSessionGraph {
    struct Pending {
        let samples: [Float]
        let end: Bool
        let identity: NativeVoiceIdentity.Playback
        var offset = 0
    }

    let engine: any NativeVoiceGraphBackend
    let lease: NativeVoiceCallbackLease
    let worker: AppleNativeVoiceTransportWorker
    let binding: NativeVoiceGraphSnapshot
    var pending: Pending?
    var playback: AppleNativeVoiceTransport.PlaybackState = .idle
    private var closed = false

    init(
        engine: any NativeVoiceGraphBackend,
        lease: NativeVoiceCallbackLease,
        worker: AppleNativeVoiceTransportWorker,
        binding: NativeVoiceGraphSnapshot
    ) {
        self.engine = engine
        self.lease = lease
        self.worker = worker
        self.binding = binding
    }

    deinit { close() }

    var context: OpaquePointer {
        lease.context
    }

    func close() {
        guard !closed else { return }
        closed = true
        lease.close()
        engine.stop()
        pending = nil
    }

    func requirePlayback(_ identity: NativeVoiceIdentity.Playback) throws {
        guard worker.identity.playback == identity else { throw NativeVoiceTransportError.staleIdentity }
    }

    func pump() throws {
        guard var block = pending else { return }
        try requirePlayback(block.identity)
        let token = block.identity.token
        let remaining = block.samples.count - block.offset
        let frames = min(remaining, nvt_rt_playback_space(context, token))
        guard frames > 0 || (remaining == 0 && block.end) else { return }
        let result = block.samples.withUnsafeBufferPointer { samples in
            nvt_rt_enqueue(
                context,
                samples.baseAddress?.advanced(by: block.offset),
                frames,
                token,
                block.end && remaining == frames
            )
        }
        switch result {
        case NVT_WRITE_OK:
            block.offset += frames
            pending = block.offset == block.samples.count ? nil : block
        case NVT_WRITE_FULL, NVT_WRITE_AWAITING_CLEAR:
            break
        default:
            throw NativeVoiceTransportError.staleIdentity
        }
    }
}
