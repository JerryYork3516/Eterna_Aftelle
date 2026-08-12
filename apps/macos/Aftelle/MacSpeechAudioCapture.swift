@preconcurrency import AVFoundation
import Foundation

nonisolated enum MacSpeechAudioInputFormat {
    static let sampleRate: Double = 24_000
    static let channelCount: AVAudioChannelCount = 1
    static let packetDurationMilliseconds = 20
    static let packetSampleCount = 480
    static let packetByteCount = 960
    static let frameCapacity = 25
    static let tapBufferSize: AVAudioFrameCount = 1_024
    static let description = "24000 Hz / mono / signed PCM16 LE / interleaved"
}

nonisolated protocol MacSpeechAudioFrameSourcing: Sendable {
    func activeCaptureGeneration() async -> UInt64?
    func isCaptureGenerationActive(_ generation: UInt64) async -> Bool
    func drainFrames(maxCount: Int) async -> [MacSpeechAudioFrame]
}

nonisolated struct MacSpeechAudioFrame: Sendable, Equatable {
    let captureGeneration: UInt64
    let sequenceNumber: UInt64
    let monotonicTimestampNanoseconds: UInt64
    let pcm16Bytes: Data
    let activity: Float
}

nonisolated struct MacSpeechAudioFrameBufferStats: Sendable, Equatable {
    let generatedCount: UInt64
    let droppedCount: UInt64
    let rejectedStaleCount: UInt64
    let queuedCount: Int
    let latestActivity: Float
}

nonisolated final class MacSpeechAudioFrameBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var activeGeneration: UInt64?
    private var frames: [MacSpeechAudioFrame] = []
    private var nextSequence: UInt64 = 0
    private var lastTimestamp: UInt64 = 0
    private var generatedCount: UInt64 = 0
    private var droppedCount: UInt64 = 0
    private var rejectedStaleCount: UInt64 = 0
    private var latestActivity: Float = 0

    init(capacity: Int = MacSpeechAudioInputFormat.frameCapacity) {
        precondition(capacity > 0)
        self.capacity = capacity
        frames.reserveCapacity(capacity)
    }

    func begin(generation: UInt64) {
        lock.withLock {
            activeGeneration = generation
            frames.removeAll(keepingCapacity: true)
            nextSequence = 0
            lastTimestamp = 0
            generatedCount = 0
            droppedCount = 0
            rejectedStaleCount = 0
            latestActivity = 0
        }
    }

    func end(generation: UInt64) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            activeGeneration = nil
            frames.removeAll(keepingCapacity: true)
        }
    }

    @discardableResult
    func append(
        pcm16Bytes: Data,
        activity: Float,
        generation: UInt64,
        timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Bool {
        lock.withLock {
            guard activeGeneration == generation, !pcm16Bytes.isEmpty else {
                rejectedStaleCount &+= 1
                return false
            }
            if frames.count == capacity {
                frames.removeFirst()
                droppedCount &+= 1
            }
            nextSequence &+= 1
            let monotonicTimestamp = timestamp > lastTimestamp
                ? timestamp
                : lastTimestamp &+ 1
            lastTimestamp = monotonicTimestamp
            latestActivity = activity.isFinite
                ? min(max(activity, 0), 1)
                : 0
            frames.append(
                MacSpeechAudioFrame(
                    captureGeneration: generation,
                    sequenceNumber: nextSequence,
                    monotonicTimestampNanoseconds: monotonicTimestamp,
                    pcm16Bytes: pcm16Bytes,
                    activity: latestActivity
                )
            )
            generatedCount &+= 1
            return true
        }
    }

    func drain(maxCount: Int) -> [MacSpeechAudioFrame] {
        lock.withLock {
            guard maxCount > 0, !frames.isEmpty else { return [] }
            let count = min(maxCount, frames.count)
            let drained = Array(frames.prefix(count))
            frames.removeFirst(count)
            return drained
        }
    }

    func stats() -> MacSpeechAudioFrameBufferStats {
        lock.withLock {
            MacSpeechAudioFrameBufferStats(
                generatedCount: generatedCount,
                droppedCount: droppedCount,
                rejectedStaleCount: rejectedStaleCount,
                queuedCount: frames.count,
                latestActivity: latestActivity
            )
        }
    }
}

nonisolated enum MacSpeechPCM16Encoder {
    static func encode(samples: [Float]) -> Data {
        var bytes = [UInt8](repeating: 0, count: samples.count * 2)
        for (index, sample) in samples.enumerated() {
            let value = pcm16Value(for: sample)
            let bits = UInt16(bitPattern: value)
            bytes[index * 2] = UInt8(truncatingIfNeeded: bits)
            bytes[index * 2 + 1] = UInt8(truncatingIfNeeded: bits >> 8)
        }
        return Data(bytes)
    }

    private static func pcm16Value(for sample: Float) -> Int16 {
        guard sample.isFinite else { return 0 }
        let clamped = min(max(sample, -1), 1)
        let scaled = clamped < 0
            ? clamped * 32_768
            : clamped * 32_767
        return Int16(scaled.rounded(.toNearestOrAwayFromZero))
    }
}

nonisolated struct MacSpeechPCM16Packet: Sendable, Equatable {
    let bytes: Data
    let activity: Float
}

nonisolated struct MacSpeechPCM16Packetizer: Sendable {
    private var pendingSamples: [Float] = []

    mutating func append(samples: [Float]) -> [MacSpeechPCM16Packet] {
        pendingSamples.append(contentsOf: samples)
        var packets: [MacSpeechPCM16Packet] = []
        while pendingSamples.count >= MacSpeechAudioInputFormat.packetSampleCount {
            let packetSamples = Array(
                pendingSamples.prefix(
                    MacSpeechAudioInputFormat.packetSampleCount
                )
            )
            pendingSamples.removeFirst(
                MacSpeechAudioInputFormat.packetSampleCount
            )
            packets.append(MacSpeechPCM16Packet(
                bytes: MacSpeechPCM16Encoder.encode(samples: packetSamples),
                activity: Self.activity(samples: packetSamples)
            ))
        }
        return packets
    }

    private static func activity(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let finiteSquares = samples.reduce(Float.zero) { partial, value in
            guard value.isFinite else { return partial }
            let clamped = min(max(value, -1), 1)
            return partial + clamped * clamped
        }
        return min(sqrt(finiteSquares / Float(samples.count)), 1)
    }
}

nonisolated struct MacSpeechNativeInputFormat: Sendable, Equatable {
    let sampleRate: Double
    let channelCount: UInt32
}

nonisolated enum MacSpeechAudioCaptureError: String, Error, Sendable {
    case invalidInputFormat = "invalid_input_format"
    case converterUnavailable = "audio_converter_unavailable"
    case conversionFailed = "audio_conversion_failed"
    case voiceProcessingUnavailable = "voice_processing_unavailable"
    case engineStartFailed = "audio_engine_start_failed"
}

nonisolated protocol MacSpeechAudioCapturing: AnyObject, Sendable {
    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat
    func stop()
}

nonisolated final class MacSpeechAudioConverter: @unchecked Sendable {
    private final class InputState: @unchecked Sendable {
        var supplied = false
    }

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let inputSampleRate: Double
    private var packetizer = MacSpeechPCM16Packetizer()

    init(inputFormat: AVAudioFormat) throws {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MacSpeechAudioCaptureError.invalidInputFormat
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: MacSpeechAudioInputFormat.sampleRate,
            channels: MacSpeechAudioInputFormat.channelCount,
            interleaved: false
        ), let converter = AVAudioConverter(
            from: inputFormat,
            to: outputFormat
        ) else {
            throw MacSpeechAudioCaptureError.converterUnavailable
        }
        converter.channelMap = [0]
        self.converter = converter
        self.outputFormat = outputFormat
        inputSampleRate = inputFormat.sampleRate
    }

    func convert(
        _ inputBuffer: AVAudioPCMBuffer
    ) throws -> [MacSpeechPCM16Packet] {
        try lock.withLock {
            let ratio = MacSpeechAudioInputFormat.sampleRate / inputSampleRate
            let estimatedFrames = ceil(Double(inputBuffer.frameLength) * ratio) + 8
            let capacity = AVAudioFrameCount(max(1, min(estimatedFrames, 8_192)))
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }

            let inputState = InputState()
            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { _, inputStatus in
                guard !inputState.supplied else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputState.supplied = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            guard conversionError == nil,
                  status != .error,
                  outputBuffer.frameLength > 0,
                  let samples = outputBuffer.floatChannelData?[0]
            else {
                throw MacSpeechAudioCaptureError.conversionFailed
            }

            let count = Int(outputBuffer.frameLength)
            let values = Array(UnsafeBufferPointer(start: samples, count: count))
            return packetizer.append(samples: values)
        }
    }
}

nonisolated final class SystemMacSpeechVoiceProcessingEngine:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isConfigured = false
    private var isCaptureActive = false
    private var isOutputPrepared = false
    private var isOutputPlaying = false
    private var isInputMutedForOutput = false
    private var outputFormat: AVAudioFormat?

    func startCapture(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        try lock.withLock {
            try configureIfNeeded()
            guard let engine else {
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0,
                  inputFormat.channelCount > 0 else {
                throw MacSpeechAudioCaptureError.invalidInputFormat
            }
            if isCaptureActive {
                return describe(inputFormat)
            }

            let converter = try MacSpeechAudioConverter(
                inputFormat: inputFormat
            )
            inputNode.installTap(
                onBus: 0,
                bufferSize: MacSpeechAudioInputFormat.tapBufferSize,
                format: inputFormat
            ) { buffer, _ in
                guard let packets = try? converter.convert(buffer) else {
                    return
                }
                for packet in packets {
                    frameBuffer.append(
                        pcm16Bytes: packet.bytes,
                        activity: packet.activity,
                        generation: generation
                    )
                }
            }
            do {
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
            } catch {
                inputNode.removeTap(onBus: 0)
                tearDownIfIdle()
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            if !isOutputPlaying {
                inputNode.isVoiceProcessingInputMuted = false
                isInputMutedForOutput = false
            }
            isCaptureActive = true
            return describe(inputFormat)
        }
    }

    func stopCapture() {
        lock.withLock {
            guard isCaptureActive, let engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            isCaptureActive = false
            tearDownIfIdle()
        }
    }

    func prepareOutput() throws -> AVAudioFormat {
        try lock.withLock {
            try configureIfNeeded()
            guard let outputFormat else {
                throw MacSpeechAudioCaptureError.invalidInputFormat
            }
            isOutputPrepared = true
            return outputFormat
        }
    }

    func scheduleOutput(
        _ buffer: AVAudioPCMBuffer,
        completion: @escaping @Sendable () -> Void
    ) throws {
        try lock.withLock {
            guard isOutputPrepared, let playerNode else {
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            playerNode.scheduleBuffer(
                buffer,
                completionCallbackType: .dataPlayedBack
            ) { _ in
                completion()
            }
        }
    }

    func startOutput() throws {
        try lock.withLock {
            guard isOutputPrepared,
                  let engine,
                  let playerNode else {
                throw MacSpeechAudioCaptureError.engineStartFailed
            }
            let inputNode = engine.inputNode
            inputNode.isVoiceProcessingInputMuted = true
            isInputMutedForOutput = true
            isOutputPlaying = true
            do {
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
                if !playerNode.isPlaying {
                    playerNode.play()
                }
            } catch {
                isOutputPlaying = false
                unmuteInput()
                throw error
            }
        }
    }

    func finishOutputPlayback() {
        lock.withLock {
            isOutputPlaying = false
            unmuteInput()
        }
    }

    func clearScheduledOutput() {
        lock.withLock {
            playerNode?.stop()
            isOutputPlaying = false
            unmuteInput()
        }
    }

    func stopOutput() {
        lock.withLock {
            playerNode?.stop()
            isOutputPlaying = false
            unmuteInput()
            if !isCaptureActive {
                engine?.stop()
            }
        }
    }

    func closeOutput() {
        lock.withLock {
            playerNode?.stop()
            isOutputPlaying = false
            unmuteInput()
            isOutputPrepared = false
            tearDownIfIdle()
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        let localFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        guard localFormat.sampleRate > 0,
              localFormat.channelCount > 0 else {
            throw MacSpeechAudioCaptureError.invalidInputFormat
        }
        engine.connect(
            playerNode,
            to: engine.mainMixerNode,
            format: localFormat
        )
        let inputNode = engine.inputNode
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
        }
        guard inputNode.isVoiceProcessingEnabled,
              engine.outputNode.isVoiceProcessingEnabled else {
            throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
        }
        guard inputNode.setMutedSpeechActivityEventListener({
            [weak self] event in
            self?.handleMutedSpeechActivity(event)
        }) else {
            throw MacSpeechAudioCaptureError.voiceProcessingUnavailable
        }
        self.engine = engine
        self.playerNode = playerNode
        outputFormat = localFormat
        isConfigured = true
    }

    private func tearDownIfIdle() {
        guard !isCaptureActive, !isOutputPrepared else { return }
        unmuteInput()
        engine?.stop()
        if isConfigured,
           let engine,
           let playerNode {
            engine.disconnectNodeOutput(playerNode)
            engine.detach(playerNode)
            engine.reset()
        }
        playerNode = nil
        engine = nil
        outputFormat = nil
        isConfigured = false
    }

    private func handleMutedSpeechActivity(
        _ event: AVAudioVoiceProcessingSpeechActivityEvent
    ) {
        guard event == .started else { return }
        lock.withLock {
            guard isOutputPlaying, isInputMutedForOutput else { return }
            unmuteInput()
        }
    }

    private func unmuteInput() {
        guard isInputMutedForOutput else { return }
        engine?.inputNode.isVoiceProcessingInputMuted = false
        isInputMutedForOutput = false
    }

    private func describe(
        _ format: AVAudioFormat
    ) -> MacSpeechNativeInputFormat {
        MacSpeechNativeInputFormat(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount
        )
    }
}

nonisolated final class SystemMacSpeechAudioCapture:
    MacSpeechAudioCapturing, @unchecked Sendable
{
    private let audioEngine: SystemMacSpeechVoiceProcessingEngine

    init(
        audioEngine: SystemMacSpeechVoiceProcessingEngine =
            SystemMacSpeechVoiceProcessingEngine()
    ) {
        self.audioEngine = audioEngine
    }

    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        try audioEngine.startCapture(
            generation: generation,
            frameBuffer: frameBuffer
        )
    }

    func stop() {
        audioEngine.stopCapture()
    }
}
