import Darwin
import Foundation

/// Serial non-realtime control and conversion. Callers supply authority and drive bounded service.
actor AppleNativeVoiceTransport {
    enum State: String, Equatable, Sendable { case idle, running, rebuildRequired, closed }
    enum PlaybackState: Equatable, Sendable { case idle, playing, ending, cancelled }

    struct Limits: Sendable {
        var ringFrames = 16384
        var callbackFrames: UInt32 = 8192
        var captureChannel: UInt32 = 0
    }

    struct Progress: Sendable {
        let playback: PlaybackState
        let token: UInt64
        let consumerAcknowledged: Bool
        let renderClearAcknowledged: Bool
        let renderHandoff: Bool
        let droppedRenderFacts: UInt64
        let idleFrames: UInt64
        let cancelledFrames: UInt64
        let underrunFrames: UInt64
        let captureDroppedFrames: UInt64
        let captureOverflowEvents: UInt64
        let rejectedOutputFrames: UInt64
    }

    struct ServiceBatch: Sendable {
        let packets: [NativeVoiceCapturePacket]
        let render: [NativeVoiceRenderFact]
        let progress: Progress
    }

    private let makeEngine: @Sendable () -> any NativeVoiceGraphBackend
    private let authorized: @Sendable () -> Bool
    private let limits: Limits
    private var lastIdentity: NativeVoiceIdentity?
    private var live: NativeVoiceSessionGraph?
    private var retiredReadback: NativeVoiceTransportReadback?
    private(set) var state: State = .idle

    init(
        makeEngine: @escaping @Sendable () -> any NativeVoiceGraphBackend,
        authorized: @escaping @Sendable () -> Bool,
        limits: Limits = Limits()
    ) {
        self.makeEngine = makeEngine
        self.authorized = authorized
        self.limits = limits
    }

    func start(identity: NativeVoiceIdentity) throws {
        guard state == .idle else { throw NativeVoiceSessionError.state }
        try open(identity)
    }

    func rebuild(identity next: NativeVoiceIdentity) throws {
        guard state == .rebuildRequired, let prior = lastIdentity else { throw NativeVoiceSessionError.state }
        guard next.capture.authority.configurationID != prior.capture.authority.configurationID,
              next.capture.token > prior.capture.token,
              next.playback.token > prior.playback.token else { throw NativeVoiceTransportError.staleIdentity }
        try open(next)
    }

    func close() {
        tearDown(.closed)
    }

    func permissionRevoked() {
        tearDown(.closed)
    }

    func invalidateConfiguration(_ current: NativeVoiceIdentity.Capture) throws {
        let graph = try running()
        guard current == graph.worker.identity.capture else { throw NativeVoiceTransportError.staleIdentity }
        tearDown(.rebuildRequired)
    }

    func beginPlayback(_ next: NativeVoiceIdentity.Playback) throws {
        let graph = try running()
        let current = graph.worker.identity.playback
        let completed = graph.playback == .ending && nvt_rt_stats(graph.context).rendered_end_token == current.token
        guard graph.playback == .idle || graph.playback == .cancelled || completed else {
            throw NativeVoiceSessionError.state
        }
        guard next.token > current.token || (graph.playback == .idle && next == current) else {
            throw NativeVoiceTransportError.staleIdentity
        }
        try transitionPlayback(graph, to: next, cancelling: false)
    }

    func cancelPlayback(
        _ current: NativeVoiceIdentity.Playback, replacingWith next: NativeVoiceIdentity.Playback
    ) throws {
        let graph = try running()
        guard graph.worker.identity.playback == current, next.token > current.token, next.epoch > current.epoch
        else { throw NativeVoiceTransportError.staleIdentity }
        try transitionPlayback(graph, to: next, cancelling: true)
    }

    /// Runtime has completed N+1 after Source acknowledged the old playback clear.
    func advanceGeneration(from current: NativeVoiceIdentity, to next: NativeVoiceIdentity) throws {
        let graph = try running()
        let authority = current.capture.authority
        let successor = next.capture.authority
        guard graph.worker.identity.capture == current.capture,
              graph.worker.identity.playback == current.playback,
              graph.playback == .cancelled,
              nvt_rt_stats(graph.context).rendered_clear_token == current.playback.token,
              successor.configurationID == authority.configurationID, successor.routeEpoch == authority.routeEpoch,
              authority.runtimeGeneration < UInt64.max, successor.runtimeGeneration == authority.runtimeGeneration + 1,
              next.capture.generation == current.capture.generation,
              next.capture.token > current.capture.token, next.playback.token > current.playback.token,
              next.playback.epoch == current.playback.epoch else { throw NativeVoiceTransportError.staleIdentity }
        do {
            let boundary = DispatchTime.now().uptimeNanoseconds
            guard nvt_rt_set_capture(graph.context, next.capture.token, boundary),
                  nvt_rt_set_playback(graph.context, next.playback.token, true)
            else { throw NativeVoiceTransportError.staleIdentity }
            try graph.worker.reset(
                identity: next, nativeRate: graph.binding.plan.capture.sampleRate,
                playbackRate: graph.binding.plan.render.sampleRate
            )
            lastIdentity = next
        } catch {
            tearDown(.rebuildRequired)
            throw error
        }
    }

    /// False leaves this chunk unaccepted so the same bytes can be retried on the serial worker.
    func enqueuePlayback(_ pcm: Data, identity: NativeVoiceIdentity.Playback) throws -> Bool {
        let graph = try running()
        try graph.requirePlayback(identity)
        guard graph.playback == .playing else { throw NativeVoiceSessionError.state }
        guard pcm.count <= 48000 else { throw NativeVoiceTransportError.invalidPCM }
        try graph.pump()
        guard graph.pending == nil else { return false }
        let samples = try graph.worker.playback(pcm, identity: identity)
        _ = try running()
        if !samples.isEmpty {
            graph.pending = .init(samples: samples, end: false, identity: identity)
            try graph.pump()
        }
        return true
    }

    /// False means queued data is still pending and EOS can be retried. A true result accepts EOS.
    func finishPlayback(identity: NativeVoiceIdentity.Playback) throws -> Bool {
        let graph = try running()
        try graph.requirePlayback(identity)
        guard graph.playback == .playing || graph.playback == .ending else { throw NativeVoiceSessionError.state }
        try graph.pump()
        if graph.playback == .ending {
            return true
        }
        guard graph.pending == nil else { return false }
        let tail = try graph.worker.finishPlayback(identity: identity)
        _ = try running()
        graph.pending = .init(samples: tail, end: true, identity: identity)
        graph.playback = .ending
        try graph.pump()
        return true
    }

    func service(maxCaptureFrames: Int) throws -> [NativeVoiceCapturePacket] {
        let graph = try running()
        try graph.pump()
        let packets = try graph.worker.drainCapture(
            nvt_rt_capture_ring(graph.context), maxFrames: maxCaptureFrames, requiresConfiguration: true
        )
        _ = try running()
        return packets
    }

    func bridgeService(maxCaptureFrames: Int) throws -> ServiceBatch {
        try ServiceBatch(
            packets: service(maxCaptureFrames: maxCaptureFrames), render: takeRenderFacts(), progress: progress()
        )
    }

    func configuredGraph() throws -> NativeVoiceGraphSnapshot {
        try running().binding
    }

    func readback() -> NativeVoiceTransportReadback? {
        live?.readback(state: state.rawValue) ?? retiredReadback
    }

    /// Handoff reports an EOS observed by the source callback. Physical playback completion is unknown.
    func progress() throws -> Progress {
        let graph = try running()
        let stats = nvt_rt_stats(graph.context)
        let capture = nvt_rt_capture_stats(graph.context)
        return Progress(
            playback: graph.playback, token: stats.active_token,
            consumerAcknowledged: stats.acknowledged_token == stats.active_token,
            renderClearAcknowledged: stats.rendered_clear_token == stats.active_token,
            renderHandoff: stats.rendered_end_token == stats.active_token,
            droppedRenderFacts: stats.dropped_render_facts,
            idleFrames: stats.idle_frames, cancelledFrames: stats.cancelled_frames,
            underrunFrames: stats.underrun_frames, captureDroppedFrames: stats.rejected_input_frames,
            captureOverflowEvents: capture.overflow_events, rejectedOutputFrames: stats.rejected_output_frames
        )
    }

    func takeRenderFacts() throws -> [NativeVoiceRenderFact] {
        let graph = try running()
        let playback = graph.worker.identity.playback
        var record = NVTRenderFact()
        var facts: [NativeVoiceRenderFact] = []
        // One bounded pass even if Source keeps publishing while this worker drains.
        for _ in 0 ..< Int(NVT_RENDER_FACT_CAPACITY) {
            guard nvt_rt_take_render_fact(graph.context, &record) else { break }
            guard record.playback_token == playback.token,
                  record.configuration_id == playback.authority.configurationID else { continue }
            facts.append(NativeVoiceRenderFact(record, playback: playback))
        }
        return facts
    }
}

private extension AppleNativeVoiceTransport {
    func open(_ identity: NativeVoiceIdentity) throws {
        guard authorized() else { tearDown(.closed); throw NativeVoiceSessionError.permission }
        guard identity.capture.token > 0, identity.capture.token < UInt64.max, identity.playback.token > 0 else {
            throw NativeVoiceTransportError.staleIdentity
        }
        lastIdentity = identity
        let engine = makeEngine()
        var lease: NativeVoiceCallbackLease?
        do {
            let plan = try engine.negotiate()
            let callbacks = try makeLease(plan, identity: identity)
            lease = callbacks
            let worker = try AppleNativeVoiceTransportWorker(
                identity: identity, nativeRate: plan.capture.sampleRate, playbackRate: plan.render.sampleRate
            )
            try installAndStart(engine, lease: callbacks, plan: plan)
            let binding = try engine.snapshot()
            guard binding.plan == plan else { throw NativeVoiceSessionError.format }
            try watchRoute(engine, binding: binding, lease: callbacks)
            guard authorized() else { throw NativeVoiceSessionError.permission }
            guard try engine.snapshot() == binding,
                  nvt_rt_activate(callbacks.context) else { throw NativeVoiceSessionError.route }
            live = NativeVoiceSessionGraph(engine: engine, lease: callbacks, worker: worker, binding: binding)
            state = .running
        } catch {
            lease?.close()
            engine.stop()
            state = authorized() ? .rebuildRequired : .closed
            throw error
        }
    }

    func installAndStart(
        _ engine: any NativeVoiceGraphBackend, lease: NativeVoiceCallbackLease,
        plan: NativeVoiceGraphPlan
    ) throws {
        try engine.install(plan, lease: lease) { [weak self] in
            lease.close()
            Task { await self?.deviceEvent(lease, graphInvalidated: true) }
        }
        guard authorized() else { throw NativeVoiceSessionError.permission }
        try engine.start()
    }

    func watchRoute(
        _ engine: any NativeVoiceGraphBackend, binding: NativeVoiceGraphSnapshot, lease: NativeVoiceCallbackLease
    ) throws {
        try engine.watchDevices(binding) { [weak self] in
            Task { await self?.deviceEvent(lease, graphInvalidated: false) }
        }
    }

    func deviceEvent(_ lease: NativeVoiceCallbackLease, graphInvalidated: Bool) {
        guard let live, live.lease === lease else { return }
        guard authorized() else { tearDown(.closed); return }
        guard !graphInvalidated, nvt_rt_active(live.context),
              (try? live.engine.snapshot()) == live.binding else { tearDown(.rebuildRequired); return }
    }

    func running() throws -> NativeVoiceSessionGraph {
        guard let live else { throw NativeVoiceSessionError.state }
        guard authorized() else { tearDown(.closed); throw NativeVoiceSessionError.permission }
        guard nvt_rt_active(live.context) else { tearDown(.rebuildRequired); throw NativeVoiceSessionError.route }
        return live
    }

    func tearDown(_ next: State) {
        if let live {
            live.close()
            retiredReadback = live.readback(state: next.rawValue)
        }
        live = nil
        state = next
    }

    func transitionPlayback(
        _ graph: NativeVoiceSessionGraph, to next: NativeVoiceIdentity.Playback, cancelling: Bool
    ) throws {
        let capture = graph.worker.identity.capture
        guard next.authority == capture.authority, next.epoch >= graph.worker.identity.playback.epoch,
              nvt_rt_set_playback(graph.context, next.token, cancelling) else {
            throw NativeVoiceTransportError.staleIdentity
        }
        let identity = NativeVoiceIdentity(
            authority: next.authority, captureGeneration: capture.generation, captureToken: capture.token,
            playbackEpoch: next.epoch, playbackToken: next.token
        )
        lastIdentity = identity
        do {
            if next != graph.worker.identity.playback {
                try graph.worker.reset(
                    identity: identity, nativeRate: graph.binding.plan.capture.sampleRate,
                    playbackRate: graph.binding.plan.render.sampleRate
                )
            }
            graph.pending = nil
            graph.playback = cancelling ? .cancelled : .playing
        } catch {
            tearDown(.rebuildRequired)
            throw error
        }
    }

    func makeLease(
        _ plan: NativeVoiceGraphPlan,
        identity: NativeVoiceIdentity
    ) throws -> NativeVoiceCallbackLease {
        guard plan.capture.supported, plan.render.supported else { throw NativeVoiceSessionError.format }
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS else { throw NativeVoiceSessionError.format }
        let config = NVTRTConfig(
            capture_channels: plan.capture.channels, capture_channel: limits.captureChannel,
            max_callback_frames: limits.callbackFrames, capture_interleaved: plan.capture.interleaved,
            timebase_numerator: timebase.numer, timebase_denominator: timebase.denom,
            capture_capacity: limits.ringFrames, playback_capacity: limits.ringFrames,
            configuration_id: identity.capture.authority.configurationID,
            capture_token: identity.capture.token, playback_token: identity.playback.token
        )
        guard let lease = NativeVoiceCallbackLease(config: config) else { throw NativeVoiceTransportError.allocation }
        return lease
    }
}
