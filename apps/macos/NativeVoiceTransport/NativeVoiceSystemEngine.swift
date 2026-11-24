@preconcurrency import AVFoundation
import Foundation

extension AppleNativeVoiceTransport {
    static func macOS(limits: Limits = Limits()) -> AppleNativeVoiceTransport {
        AppleNativeVoiceTransport(
            makeEngine: { NativeVoiceSystemEngine() },
            makeMonitor: { SystemMacSpeechDeviceMonitor() },
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

    func negotiate() throws -> NativeVoiceGraphPlan {
        guard !engine.isRunning else { throw NativeVoiceSessionError.state }
        engine.isAutoShutdownEnabled = false
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        input.isVoiceProcessingBypassed = false
        input.isVoiceProcessingAGCEnabled = true
        input.isVoiceProcessingInputMuted = false
        _ = engine.mainMixerNode
        try requireVoiceProcessing()
        return plan()
    }

    func install(
        _ plan: NativeVoiceGraphPlan,
        lease: NativeVoiceCallbackLease,
        configurationChanged: @escaping @Sendable () -> Void
    ) throws {
        let capture = engine.inputNode.outputFormat(forBus: 0)
        let render = engine.outputNode.inputFormat(forBus: 0)
        guard source == nil, sink == nil, !engine.isRunning,
              Self.describe(capture) == plan.capture, Self.describe(render) == plan.render,
              let mono = AVAudioFormat(standardFormatWithSampleRate: plan.source.sampleRate, channels: 1)
        else { throw NativeVoiceSessionError.format }

        let sink = lease.factory.makeSink()
        let source = lease.factory.makeSource(with: mono)
        self.sink = sink
        self.source = source
        guard nvt_connect_voice_graph(engine, sink, source, capture, mono, render)
        else { throw NativeVoiceSessionError.format }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in configurationChanged() }
    }

    func start() throws {
        guard source != nil, sink != nil, !engine.isRunning else { throw NativeVoiceSessionError.state }
        try requireVoiceProcessing()
        engine.prepare()
        try engine.start()
    }

    func snapshot() throws -> NativeVoiceGraphSnapshot {
        guard engine.isRunning, let sink, let source else { throw NativeVoiceSessionError.state }
        try requireVoiceProcessing()
        let graph = plan()
        guard Self.describe(sink.inputFormat(forBus: 0)) == graph.capture,
              Self.describe(source.outputFormat(forBus: 0)) == graph.source,
              Self.describe(engine.mainMixerNode.outputFormat(forBus: 0)) == graph.render
        else { throw NativeVoiceSessionError.format }
        let input = try NativeVoiceHALRoute.currentDevice(engine.inputNode.audioUnit)
        let output = try NativeVoiceHALRoute.currentDevice(engine.outputNode.audioUnit)
        return try NativeVoiceGraphSnapshot(
            plan: graph, inputDevice: input, outputDevice: output,
            bindings: NativeVoiceHALRoute.bindings(input: input, output: output)
        )
    }

    func watchDevices(_ snapshot: NativeVoiceGraphSnapshot, changed: @escaping @Sendable () -> Void) throws {
        try devices.start(snapshot.bindings, changed: changed)
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
    }

    private func requireVoiceProcessing() throws {
        let input = engine.inputNode
        guard input.isVoiceProcessingEnabled, engine.outputNode.isVoiceProcessingEnabled,
              input.isVoiceProcessingAGCEnabled, !input.isVoiceProcessingBypassed, !input.isVoiceProcessingInputMuted
        else { throw NativeVoiceSessionError.voiceProcessing }
    }

    private func plan() -> NativeVoiceGraphPlan {
        NativeVoiceGraphPlan(
            capture: Self.describe(engine.inputNode.outputFormat(forBus: 0)),
            render: Self.describe(engine.outputNode.inputFormat(forBus: 0))
        )
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
