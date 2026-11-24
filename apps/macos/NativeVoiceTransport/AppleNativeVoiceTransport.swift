import Darwin
import Foundation

/// Serial non-realtime control and conversion. Callers supply authority and drive bounded service.
actor AppleNativeVoiceTransport {
    enum State: Equatable, Sendable { case idle, running, rebuildRequired, closed }
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
        let renderHandoff: Bool
        let idleFrames: UInt64
        let cancelledFrames: UInt64
        let underrunFrames: UInt64
        let captureDroppedFrames: UInt64
        let captureOverflowEvents: UInt64
        let rejectedOutputFrames: UInt64
    }

    private let makeEngine: @Sendable () -> any NativeVoiceGraphBackend
    private let makeMonitor: @Sendable () -> any MacSpeechDeviceRouteMonitoring
    private let authorized: @Sendable () -> Bool
    private let limits: Limits
    private var lastIdentity: NativeVoiceIdentity?
    private var live: NativeVoiceSessionGraph?
    private(set) var state: State = .idle

    init(
        makeEngine: @escaping @Sendable () -> any NativeVoiceGraphBackend,
        makeMonitor: @escaping @Sendable () -> any MacSpeechDeviceRouteMonitoring,
        authorized: @escaping @Sendable () -> Bool,
        limits: Limits = Limits()
    ) {
        self.makeEngine = makeEngine
        self.makeMonitor = makeMonitor
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

    /// Handoff reports an EOS observed by the source callback. Physical playback completion is unknown.
    func progress() throws -> Progress {
        let graph = try running()
        let stats = nvt_rt_stats(graph.context)
        let capture = nvt_rt_capture_stats(graph.context)
        return Progress(
            playback: graph.playback, token: stats.active_token,
            consumerAcknowledged: stats.acknowledged_token == stats.active_token,
            renderHandoff: stats.rendered_end_token == stats.active_token,
            idleFrames: stats.idle_frames, cancelledFrames: stats.cancelled_frames,
            underrunFrames: stats.underrun_frames, captureDroppedFrames: stats.rejected_input_frames,
            captureOverflowEvents: capture.overflow_events, rejectedOutputFrames: stats.rejected_output_frames
        )
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
        let monitor = makeMonitor()
        var lease: NativeVoiceCallbackLease?
        do {
            let defaults = monitor.currentRoute()
            guard defaults.input.isAvailable, defaults.output.isAvailable else { throw NativeVoiceSessionError.route }
            let plan = try engine.negotiate()
            let callbacks = try makeLease(plan, identity: identity)
            lease = callbacks
            let worker = try AppleNativeVoiceTransportWorker(
                identity: identity, nativeRate: plan.capture.sampleRate, playbackRate: plan.render.sampleRate
            )
            try installAndStart(engine, lease: callbacks, plan: plan, captureToken: identity.capture.token)
            let binding = try engine.snapshot()
            guard binding.plan == plan else { throw NativeVoiceSessionError.format }
            try watchRoute(engine, monitor: monitor, binding: binding, token: identity.capture.token)
            guard authorized() else { throw NativeVoiceSessionError.permission }
            guard sameDefaults(defaults, monitor.currentRoute()), try engine.snapshot() == binding,
                  nvt_rt_activate(callbacks.context) else { throw NativeVoiceSessionError.route }
            live = NativeVoiceSessionGraph(
                engine: engine, monitor: monitor, lease: callbacks, worker: worker, binding: binding, defaults: defaults
            )
            state = .running
        } catch {
            lease?.close()
            monitor.stop()
            engine.stop()
            state = authorized() ? .rebuildRequired : .closed
            throw error
        }
    }

    func installAndStart(
        _ engine: any NativeVoiceGraphBackend, lease: NativeVoiceCallbackLease,
        plan: NativeVoiceGraphPlan, captureToken: UInt64
    ) throws {
        try engine.install(plan, lease: lease) { [weak self] in
            lease.close()
            Task { await self?.deviceEvent(captureToken, graphInvalidated: true) }
        }
        guard authorized() else { throw NativeVoiceSessionError.permission }
        try engine.start()
    }

    func watchRoute(
        _ engine: any NativeVoiceGraphBackend, monitor: any MacSpeechDeviceRouteMonitoring,
        binding: NativeVoiceGraphSnapshot, token: UInt64
    ) throws {
        let changed: @Sendable () -> Void = { [weak self] in
            Task { await self?.deviceEvent(token, graphInvalidated: false) }
        }
        try engine.watchDevices(binding, changed: changed)
        monitor.start(onChange: changed)
    }

    func deviceEvent(_ token: UInt64, graphInvalidated: Bool) {
        guard let live, live.worker.identity.capture.token == token else { return }
        guard authorized() else { tearDown(.closed); return }
        guard !graphInvalidated, nvt_rt_active(live.context),
              sameDefaults(live.defaults, live.monitor.currentRoute()),
              (try? live.engine.snapshot()) == live.binding else { tearDown(.rebuildRequired); return }
    }

    func sameDefaults(_ left: MacSpeechDeviceRoute, _ right: MacSpeechDeviceRoute) -> Bool {
        right.input.isAvailable && right.output.isAvailable
            && left.input.identifier == right.input.identifier && left.output.identifier == right.output.identifier
    }

    func running() throws -> NativeVoiceSessionGraph {
        guard let live else { throw NativeVoiceSessionError.state }
        guard authorized() else { tearDown(.closed); throw NativeVoiceSessionError.permission }
        guard nvt_rt_active(live.context) else { tearDown(.rebuildRequired); throw NativeVoiceSessionError.route }
        return live
    }

    func tearDown(_ next: State) {
        live?.close()
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
