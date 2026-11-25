@preconcurrency import AVFoundation
import Foundation

extension AppleNativeVoiceTransport {
    static func macOS(limits: Limits = Limits()) -> AppleNativeVoiceTransport {
        AppleNativeVoiceTransport(
            makeEngine: { NativeVoiceSystemEngine() },
            authorized: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
            limits: limits
        )
    }
}

/// Owns one stopped/configured Engine per graph. Only explicitly authorized session control starts it.
final nonisolated class NativeVoiceSystemEngine: NativeVoiceGraphBackend {
    private let engine = AVAudioEngine()
    private let devices = NativeVoiceHALRoute()
    private var source: AVAudioSourceNode?
    private var sink: AVAudioSinkNode?
    private var configurationObserver: NSObjectProtocol?
    private var preparedDefaults: NativeVoiceGraphSnapshot.Defaults?
    private var negotiatedInput: AVAudioFormat?

    func negotiate() throws -> NativeVoiceGraphPlan {
        guard !engine.isRunning else { throw NativeVoiceSessionError.state }
        preparedDefaults = try NativeVoiceHALRoute.defaultDevices()
        engine.isAutoShutdownEnabled = false
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        input.isVoiceProcessingBypassed = false
        input.isVoiceProcessingAGCEnabled = true
        input.isVoiceProcessingInputMuted = false
        try requireVoiceProcessing()
        let negotiated = try Self.negotiateVP(
            readInput: { input.outputFormat(forBus: 0) },
            readOutput: { self.engine.outputNode.inputFormat(forBus: 0) },
            connectMixer: { nvt_negotiate_voice_output(self.engine, $0) }
        )
        negotiatedInput = negotiated.input
        return negotiated.plan
    }

    func install(
        _ plan: NativeVoiceGraphPlan,
        lease: NativeVoiceCallbackLease,
        configurationChanged: @escaping @Sendable () -> Void
    ) throws {
        let capture = engine.inputNode.outputFormat(forBus: 0)
        let render = engine.outputNode.inputFormat(forBus: 0)
        guard source == nil, sink == nil, !engine.isRunning, let negotiatedInput, capture.isEqual(negotiatedInput),
              try Self.matchedPlan(capture, render) == plan,
              let mono = AVAudioFormat(standardFormatWithSampleRate: plan.source.sampleRate, channels: 1)
        else { throw NativeVoiceSessionError.format }

        let sink = lease.factory.makeSink()
        let source = lease.factory.makeSource(with: mono)
        self.sink = sink
        self.source = source
        guard nvt_connect_voice_graph(engine, sink, source, capture, mono)
        else { throw NativeVoiceSessionError.format }
        _ = try connectedPlan()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in configurationChanged() }
    }

    func start() throws {
        guard source != nil, sink != nil, !engine.isRunning else { throw NativeVoiceSessionError.state }
        try requireVoiceProcessing()
        _ = try connectedPlan()
        guard try NativeVoiceHALRoute.defaultDevices() == preparedDefaults else { throw NativeVoiceSessionError.route }
        engine.prepare()
        try engine.start()
    }

    func snapshot() throws -> NativeVoiceGraphSnapshot {
        guard engine.isRunning else { throw NativeVoiceSessionError.state }
        let voiceProcessing = try requireVoiceProcessing()
        let graph = try connectedPlan()
        let defaults = try NativeVoiceHALRoute.defaultDevices()
        guard defaults == preparedDefaults else { throw NativeVoiceSessionError.route }
        let input = try NativeVoiceHALRoute.currentDevice(engine.inputNode.audioUnit)
        let output = try NativeVoiceHALRoute.currentDevice(engine.outputNode.audioUnit)
        let bindings = try NativeVoiceHALRoute.bindings(roots: [defaults.input, defaults.output, input, output])
        return try NativeVoiceGraphSnapshot(
            plan: graph, defaults: defaults, inputUnitDevice: input, outputUnitDevice: output,
            bindings: bindings, streams: NativeVoiceHALRoute.streamBindings(bindings), voiceProcessing: voiceProcessing
        )
    }

    func watchDevices(_ snapshot: NativeVoiceGraphSnapshot, changed: @escaping @Sendable () -> Void) throws {
        try devices.start(snapshot, changed: changed)
    }

    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        devices.stop()
        engine.stop()
        if let sink, engine.attachedNodes.contains(sink) {
            engine.detach(sink)
        }
        if let source, engine.attachedNodes.contains(source) {
            engine.detach(source)
        }
        sink = nil
        source = nil
        preparedDefaults = nil
        negotiatedInput = nil
    }

    @discardableResult
    private func requireVoiceProcessing() throws -> NativeVoiceProcessingReadback {
        let input = engine.inputNode
        let processing = NativeVoiceProcessingReadback(
            inputEnabled: input.isVoiceProcessingEnabled, outputEnabled: engine.outputNode.isVoiceProcessingEnabled,
            agcEnabled: input.isVoiceProcessingAGCEnabled, bypassed: input.isVoiceProcessingBypassed,
            inputMuted: input.isVoiceProcessingInputMuted
        )
        guard processing.inputEnabled, processing.outputEnabled,
              processing.agcEnabled, !processing.bypassed, !processing.inputMuted
        else { throw NativeVoiceSessionError.voiceProcessing }
        return processing
    }

    private func connectedPlan() throws -> NativeVoiceGraphPlan {
        guard let sink, let source, let negotiatedInput else { throw NativeVoiceSessionError.state }
        let capture = engine.inputNode.outputFormat(forBus: 0)
        let render = engine.outputNode.inputFormat(forBus: 0)
        let graph = try Self.matchedPlan(capture, render)
        guard capture.isEqual(negotiatedInput), capture.isEqual(sink.inputFormat(forBus: 0)),
              render.isEqual(engine.mainMixerNode.outputFormat(forBus: 0)),
              Self.describe(source.outputFormat(forBus: 0)) == graph.source
        else { throw NativeVoiceSessionError.format }
        return graph
    }

    /// Shared with the offline regression. Only the caller's stopped graph may apply the connection.
    static func negotiateVP(
        readInput: () -> AVAudioFormat,
        readOutput: () -> AVAudioFormat,
        connectMixer: (AVAudioFormat) -> Bool
    ) throws -> (plan: NativeVoiceGraphPlan, input: AVAudioFormat) {
        let proposed = readInput()
        guard describe(proposed).supported, connectMixer(proposed) else { throw NativeVoiceSessionError.format }
        let input = readInput()
        let output = readOutput()
        guard proposed.isEqual(input) else { throw NativeVoiceSessionError.format }
        return try (matchedPlan(input, output), input)
    }

    private static func matchedPlan(_ capture: AVAudioFormat, _ render: AVAudioFormat) throws -> NativeVoiceGraphPlan {
        let input = describe(capture)
        let output = describe(render)
        guard input.supported, input == output, capture.isEqual(render) else { throw NativeVoiceSessionError.format }
        return NativeVoiceGraphPlan(capture: input, render: output)
    }

    private static func describe(_ format: AVAudioFormat) -> NativeVoiceIOFormat {
        let asbd = format.streamDescription.pointee
        let stride = format.isInterleaved ? UInt64(format.channelCount) : 1
        let float32 = format.commonFormat == .pcmFormatFloat32
            && asbd.mFormatID == kAudioFormatLinearPCM && asbd.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
            && asbd.mBitsPerChannel == 32 && asbd.mFramesPerPacket == 1
            && asbd.mBytesPerFrame == stride * UInt64(MemoryLayout<Float>.size)
        return NativeVoiceIOFormat(
            sampleRate: format.sampleRate, channels: format.channelCount, interleaved: format.isInterleaved,
            float32: float32
        )
    }
}
