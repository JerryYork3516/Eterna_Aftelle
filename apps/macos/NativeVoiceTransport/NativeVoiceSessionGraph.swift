import AudioToolbox
import Foundation

nonisolated struct NativeVoiceRenderFact: Encodable, Sendable {
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

    var isDigitalHandoff: Bool { flags & UInt32(NVT_RENDER_END) != 0 }

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

nonisolated struct NativeVoiceTransportReadback: Encodable, Sendable {
    struct Route: Encodable, Sendable {
        let active: Bool
        let defaults: NativeVoiceGraphSnapshot.Defaults
        let inputUnitDevice: UInt32
        let outputUnitDevice: UInt32
        let validatedDeviceCount: Int
        let inputActiveMembers: [UInt32]?
        let outputActiveMembers: [UInt32]?
    }

    let state: String
    let identity: NativeVoiceIdentity
    let formats: [String: NativeVoiceIOFormat]
    let voiceProcessing: NativeVoiceProcessingReadback?
    let route: Route
    let captureMinimumHostNanoseconds: UInt64?
    let captureTimingStatus: String
    let captureCounters: [String: UInt64]
    let sourceCounters: [String: UInt64]
    let lastConsumedSink: NativeVoiceSinkFact?
    #if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
        var sameFrameDiagnostics: NativeVoiceSameFrameDiagnostics.Report? = nil
    #endif
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

    func readback(state: String) -> NativeVoiceTransportReadback {
        let stats = nvt_rt_stats(context)
        let capture = nvt_rt_capture_stats(context)
        let readback = NativeVoiceTransportReadback(
            state: state,
            identity: worker.identity,
            formats: ["sink": binding.plan.capture, "source": binding.plan.source, "output": binding.plan.render],
            voiceProcessing: binding.voiceProcessing,
            route: .init(
                active: nvt_rt_active(context), defaults: binding.defaults,
                inputUnitDevice: binding.inputUnitDevice, outputUnitDevice: binding.outputUnitDevice,
                validatedDeviceCount: binding.bindings.count,
                inputActiveMembers: members(for: binding.inputUnitDevice),
                outputActiveMembers: members(for: binding.outputUnitDevice)
            ),
            captureMinimumHostNanoseconds: stats.capture_minimum_host_ns == 0 ? nil : stats.capture_minimum_host_ns,
            captureTimingStatus: worker.captureTimingStatus.rawValue,
            captureCounters: [
                "sinkCallbacks": stats.capture_callbacks,
                "acceptedNativeFrames": stats.accepted_input_frames,
                "rejectedNativeFrames": stats.rejected_input_frames,
                "staleNativeFrames": stats.capture_stale_frames,
                "missingFenceEvidenceNativeFrames": stats.capture_fence_missing_frames,
                "beforeFenceNativeFrames": stats.capture_fence_old_frames,
                "ringOverflowEvents": capture.overflow_events,
                "ringDroppedNativeFrames": capture.dropped_frames,
                "ringWaterNativeFrames": capture.water_frames,
                "ringHighWaterNativeFrames": capture.high_water_frames,
                "ringClearDiscardedNativeFrames": capture.clear_discarded_frames,
                "workerDiscontinuities": worker.captureDiscontinuities,
                "workerProducedPackets": worker.producedCapturePackets,
                "pendingWorkerTailSamples24k": UInt64(worker.pendingCaptureTailSamples),
                "discardedWorkerTailSamples24k": UInt64(worker.discardedCaptureTailSamples)
            ],
            sourceCounters: [
                "digitalHandoffToken": stats.rendered_end_token, "renderClearToken": stats.rendered_clear_token,
                "idleFrames": stats.idle_frames, "cancelledFrames": stats.cancelled_frames,
                "underrunFrames": stats.underrun_frames, "rejectedFrames": stats.rejected_output_frames,
                "droppedRenderFacts": stats.dropped_render_facts
            ],
            lastConsumedSink: worker.lastSinkFact
        )
        #if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
            var diagnosticReadback = readback
            if !readback.route.active {
                diagnosticReadback.sameFrameDiagnostics = worker.sameFrame?.report(
                    terminal: state, pendingTail: worker.pendingCaptureTailSamples,
                    discardedTail: worker.discardedCaptureTailSamples
                )
            }
            return diagnosticReadback
        #else
            return readback
        #endif
    }

    private func members(for id: UInt32) -> [UInt32]? {
        binding.bindings.first { $0.id == id }?.activeMembers.map { Array($0.prefix(8)) }
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
