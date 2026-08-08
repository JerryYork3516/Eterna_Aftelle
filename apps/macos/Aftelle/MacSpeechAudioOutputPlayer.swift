@preconcurrency import AVFoundation
import Foundation

private final class MacSpeechConverterInputState: @unchecked Sendable {
    private let lock = NSLock()
    private var supplied = false

    func takeInput() -> Bool {
        lock.withLock {
            guard !supplied else { return false }
            supplied = true
            return true
        }
    }
}

nonisolated struct MacSpeechLocalPlaybackFormat: Sendable, Equatable {
    let sampleRate: Double
    let channelCount: UInt32
    let sampleFormat: String
    let isInterleaved: Bool

    var description: String {
        let layout = channelCount == 1 ? "mono" : "\(channelCount) channels"
        let interleaving = isInterleaved ? "interleaved" : "non-interleaved"
        return String(
            format: "%.0f Hz / %@ / %@ / %@",
            sampleRate,
            layout,
            sampleFormat,
            interleaving
        )
    }
}

nonisolated final class MacSpeechPCMOutputConverter: @unchecked Sendable {
    private let lock = NSLock()
    private let providerFormat: AVAudioFormat
    private let localFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init(localFormat: AVAudioFormat) throws {
        guard let providerFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: MacSpeechPCMOutputFormat.sampleRate,
            channels: MacSpeechPCMOutputFormat.channelCount,
            interleaved: true
        ),
        let converter = AVAudioConverter(
            from: providerFormat,
            to: localFormat
        ) else {
            throw MacSpeechAudioOutputHostError.conversionFailed
        }
        self.providerFormat = providerFormat
        self.localFormat = localFormat
        self.converter = converter
    }

    func convert(pcm16Bytes: Data) throws -> AVAudioPCMBuffer {
        try lock.withLock {
            try convertedBuffer(pcm16Bytes: pcm16Bytes)
        }
    }

    private func convertedBuffer(
        pcm16Bytes: Data
    ) throws -> AVAudioPCMBuffer {
        guard !pcm16Bytes.isEmpty,
              pcm16Bytes.count.isMultiple(of: MacSpeechPCMOutputFormat.bytesPerSample)
        else {
            throw MacSpeechAudioOutputHostError.invalidPCMByteCount
        }
        let sourceFrames = AVAudioFrameCount(
            pcm16Bytes.count / MacSpeechPCMOutputFormat.bytesPerSample
        )
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: providerFormat,
            frameCapacity: sourceFrames
        ) else {
            throw MacSpeechAudioOutputHostError.conversionFailed
        }
        sourceBuffer.frameLength = sourceFrames
        let audioBuffer = sourceBuffer.mutableAudioBufferList.pointee.mBuffers
        guard let destination = audioBuffer.mData,
              Int(audioBuffer.mDataByteSize) >= pcm16Bytes.count
        else {
            throw MacSpeechAudioOutputHostError.conversionFailed
        }
        pcm16Bytes.copyBytes(
            to: destination.assumingMemoryBound(to: UInt8.self),
            count: pcm16Bytes.count
        )

        let ratio = localFormat.sampleRate / providerFormat.sampleRate
        let targetCapacity = AVAudioFrameCount(
            ceil(Double(sourceFrames) * ratio) + 64
        )
        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: localFormat,
            frameCapacity: targetCapacity
        ) else {
            throw MacSpeechAudioOutputHostError.conversionFailed
        }

        let inputState = MacSpeechConverterInputState()
        var conversionError: NSError?
        let status = converter.convert(
            to: targetBuffer,
            error: &conversionError
        ) { _, inputStatus in
            guard inputState.takeInput() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return sourceBuffer
        }
        guard conversionError == nil,
              status != .error,
              targetBuffer.frameLength > 0
        else {
            throw MacSpeechAudioOutputHostError.conversionFailed
        }
        return targetBuffer
    }
}

nonisolated enum MacSpeechPCMOutputEnvelope {
    static let resumeFadeInSampleCount = 120
    static let gainTransitionSampleCount = 120
    static let maximumPlaybackPeak = 0.65
    static let maximumPlaybackRMS = 0.11
    private static let audiblePeak = 0.01
    private static let audibleRMS = 0.002

    struct SafetyResult: Sendable, Equatable {
        let bytes: Data
        let appliedGain: Double
        let endingGain: Double
        let isAudible: Bool

        var didLimit: Bool { appliedGain < 1 }
    }

    static func applyingPlaybackSafety(
        to data: Data,
        startingGain: Double? = nil
    ) -> SafetyResult {
        guard !data.isEmpty,
              data.count.isMultiple(of: MacSpeechPCMOutputFormat.bytesPerSample)
        else {
            let gain = startingGain ?? 1
            return SafetyResult(
                bytes: data,
                appliedGain: 1,
                endingGain: gain,
                isAudible: false
            )
        }
        let source = [UInt8](data)
        var peak = 0
        var squaredSum = 0.0
        let sampleCount = source.count / MacSpeechPCMOutputFormat.bytesPerSample
        for byteIndex in stride(from: 0, to: source.count, by: 2) {
            let sample = decodedSample(source, at: byteIndex)
            peak = max(peak, abs(Int(sample)))
            squaredSum += Double(sample) * Double(sample)
        }
        let normalizedPeak = Double(peak) / 32_768.0
        let normalizedRMS = sqrt(squaredSum / Double(sampleCount)) / 32_768.0
        let peakGain = normalizedPeak > maximumPlaybackPeak
            ? maximumPlaybackPeak / normalizedPeak : 1
        let rmsGain = normalizedRMS > maximumPlaybackRMS
            ? maximumPlaybackRMS / normalizedRMS : 1
        let appliedGain = min(peakGain, rmsGain)
        let isAudible = normalizedPeak >= audiblePeak
            || normalizedRMS >= audibleRMS
        let initialGain = max(0, min(1, startingGain ?? appliedGain))
        let transitionSampleCount = min(
            gainTransitionSampleCount,
            sampleCount
        )
        let maximumSample = Double(Int16.max) * maximumPlaybackPeak

        var output = source
        var endingGain = initialGain
        for sampleIndex in 0 ..< sampleCount {
            let byteIndex = sampleIndex * 2
            let sample = decodedSample(source, at: byteIndex)
            let progress = transitionSampleCount > 0
                ? min(
                    1,
                    Double(sampleIndex + 1)
                        / Double(transitionSampleCount)
                )
                : 1
            let gain = initialGain + (appliedGain - initialGain) * progress
            endingGain = gain
            let scaled = Int16(
                max(-maximumSample, min(
                    maximumSample,
                    (Double(sample) * gain).rounded()
                ))
            )
            let raw = UInt16(bitPattern: scaled)
            output[byteIndex] = UInt8(truncatingIfNeeded: raw)
            output[byteIndex + 1] = UInt8(truncatingIfNeeded: raw >> 8)
        }
        return SafetyResult(
            bytes: Data(output),
            appliedGain: appliedGain,
            endingGain: endingGain,
            isAudible: isAudible
        )
    }

    static func applyingResumeFadeIn(to data: Data) -> Data {
        let sampleCount = min(
            resumeFadeInSampleCount,
            data.count / MacSpeechPCMOutputFormat.bytesPerSample
        )
        guard sampleCount > 0 else { return data }
        var bytes = [UInt8](data)
        for sampleIndex in 0 ..< sampleCount {
            let byteIndex = sampleIndex * 2
            let raw = UInt16(bytes[byteIndex])
                | (UInt16(bytes[byteIndex + 1]) << 8)
            let sample = Int16(bitPattern: raw)
            let scaled = Int16(
                Double(sample) * Double(sampleIndex + 1)
                    / Double(sampleCount)
            )
            let scaledRaw = UInt16(bitPattern: scaled)
            bytes[byteIndex] = UInt8(truncatingIfNeeded: scaledRaw)
            bytes[byteIndex + 1] = UInt8(truncatingIfNeeded: scaledRaw >> 8)
        }
        return Data(bytes)
    }

    private static func decodedSample(
        _ bytes: [UInt8],
        at byteIndex: Int
    ) -> Int16 {
        Int16(bitPattern:
            UInt16(bytes[byteIndex])
                | (UInt16(bytes[byteIndex + 1]) << 8)
        )
    }
}

nonisolated protocol MacSpeechAudioOutputPlaying: AnyObject, Sendable {
    func prepare() throws -> MacSpeechLocalPlaybackFormat
    func schedule(
        pcm16Bytes: Data,
        applyFadeIn: Bool,
        completion: @escaping @Sendable (
            Result<Int, MacSpeechAudioOutputHostError>
        ) -> Void
    ) throws -> MacSpeechPCMOutputEnvelope.SafetyResult
    func start() throws
    func clearScheduledPlayback()
    func stop()
    func close()
}

nonisolated final class SystemMacSpeechAudioOutputPlayer:
    MacSpeechAudioOutputPlaying, @unchecked Sendable
{
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var converter: MacSpeechPCMOutputConverter?
    private var localFormat: AVAudioFormat?
    private var playbackSafetyGain = 1.0

    func prepare() throws -> MacSpeechLocalPlaybackFormat {
        try lock.withLock {
            playbackSafetyGain = 1
            if let localFormat {
                return describe(localFormat)
            }

            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            let localFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            guard localFormat.sampleRate > 0,
                  localFormat.channelCount > 0,
                  let converter = try? MacSpeechPCMOutputConverter(
                    localFormat: localFormat
                  )
            else {
                throw MacSpeechAudioOutputHostError.outputUnavailable
            }
            engine.connect(
                playerNode,
                to: engine.mainMixerNode,
                format: localFormat
            )
            engine.prepare()

            self.engine = engine
            self.playerNode = playerNode
            self.converter = converter
            self.localFormat = localFormat
            return describe(localFormat)
        }
    }

    func schedule(
        pcm16Bytes: Data,
        applyFadeIn: Bool,
        completion: @escaping @Sendable (
            Result<Int, MacSpeechAudioOutputHostError>
        ) -> Void
    ) throws -> MacSpeechPCMOutputEnvelope.SafetyResult {
        let prepared = try lock.withLock {
            guard let playerNode,
                  let converter
            else {
                throw MacSpeechAudioOutputHostError.invalidState
            }
            let safety = MacSpeechPCMOutputEnvelope.applyingPlaybackSafety(
                to: pcm16Bytes,
                startingGain: playbackSafetyGain
            )
            playbackSafetyGain = safety.endingGain
            let playbackBytes = applyFadeIn
                ? MacSpeechPCMOutputEnvelope.applyingResumeFadeIn(
                    to: safety.bytes
                )
                : safety.bytes
            let buffer = try converter.convert(pcm16Bytes: playbackBytes)
            return (playerNode, buffer, safety)
        }
        prepared.0.scheduleBuffer(
            prepared.1,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            completion(.success(pcm16Bytes.count))
        }
        return prepared.2
    }

    func start() throws {
        try lock.withLock {
            guard let engine, let playerNode else {
                throw MacSpeechAudioOutputHostError.invalidState
            }
            if !engine.isRunning {
                try engine.start()
            }
            if !playerNode.isPlaying {
                playerNode.play()
            }
        }
    }

    func clearScheduledPlayback() {
        lock.withLock {
            playerNode?.stop()
            playbackSafetyGain = 1
        }
    }

    func stop() {
        lock.withLock {
            playerNode?.stop()
            engine?.stop()
            playbackSafetyGain = 1
        }
    }

    func close() {
        lock.withLock {
            playerNode?.stop()
            engine?.stop()
            if let engine, let playerNode {
                engine.disconnectNodeOutput(playerNode)
                engine.detach(playerNode)
            }
            converter = nil
            localFormat = nil
            playerNode = nil
            engine = nil
            playbackSafetyGain = 1
        }
    }

    private func describe(
        _ format: AVAudioFormat
    ) -> MacSpeechLocalPlaybackFormat {
        MacSpeechLocalPlaybackFormat(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            sampleFormat: sampleFormatDescription(format.commonFormat),
            isInterleaved: format.isInterleaved
        )
    }

    private func sampleFormatDescription(
        _ format: AVAudioCommonFormat
    ) -> String {
        switch format {
        case .pcmFormatFloat32:
            return "Float32"
        case .pcmFormatFloat64:
            return "Float64"
        case .pcmFormatInt16:
            return "signed PCM16"
        case .pcmFormatInt32:
            return "signed PCM32"
        case .otherFormat:
            return "other"
        @unknown default:
            return "unknown"
        }
    }
}
