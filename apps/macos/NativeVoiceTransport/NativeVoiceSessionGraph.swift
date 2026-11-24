import Foundation

/// Owned exclusively by the transport actor. Retired callbacks keep their original C allocation.
final nonisolated class NativeVoiceSessionGraph {
    struct Pending {
        let samples: [Float]
        let end: Bool
        let identity: NativeVoiceIdentity.Playback
        var offset = 0
    }

    let engine: any NativeVoiceGraphBackend
    let monitor: any MacSpeechDeviceRouteMonitoring
    let lease: NativeVoiceCallbackLease
    let worker: AppleNativeVoiceTransportWorker
    let binding: NativeVoiceGraphSnapshot
    let defaults: MacSpeechDeviceRoute
    var pending: Pending?
    var playback: AppleNativeVoiceTransport.PlaybackState = .idle
    private var closed = false

    init(
        engine: any NativeVoiceGraphBackend,
        monitor: any MacSpeechDeviceRouteMonitoring,
        lease: NativeVoiceCallbackLease,
        worker: AppleNativeVoiceTransportWorker,
        binding: NativeVoiceGraphSnapshot,
        defaults: MacSpeechDeviceRoute
    ) {
        self.engine = engine
        self.monitor = monitor
        self.lease = lease
        self.worker = worker
        self.binding = binding
        self.defaults = defaults
    }

    deinit { close() }

    var context: OpaquePointer {
        lease.context
    }

    func close() {
        guard !closed else { return }
        closed = true
        lease.close()
        monitor.stop()
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
