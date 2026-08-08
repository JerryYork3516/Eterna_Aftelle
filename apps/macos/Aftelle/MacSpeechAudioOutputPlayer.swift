@preconcurrency import AVFoundation
import Foundation

private nonisolated final class MacSpeechConverterInputState: @unchecked Sendable {
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

    func reset() {
        lock.withLock {
            converter.reset()
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
    private static let audiblePeak = 0.01
    private static let audibleRMS = 0.002

    struct ProcessingResult: Sendable, Equatable {
        let bytes: Data
        let isAudible: Bool
        let didStartAttenuation: Bool
        let inputPeak: Double
        let outputPeak: Double
        let minimumGain: Double

        init(
            bytes: Data,
            isAudible: Bool,
            didStartAttenuation: Bool = false,
            inputPeak: Double = 0,
            outputPeak: Double = 0,
            minimumGain: Double = 1
        ) {
            self.bytes = bytes
            self.isAudible = isAudible
            self.didStartAttenuation = didStartAttenuation
            self.inputPeak = inputPeak
            self.outputPeak = outputPeak
            self.minimumGain = minimumGain
        }
    }

    static func processing(
        to data: Data,
        applyFadeIn: Bool
    ) -> ProcessingResult {
        guard !data.isEmpty,
              data.count.isMultiple(of: MacSpeechPCMOutputFormat.bytesPerSample)
        else {
            return ProcessingResult(
                bytes: data,
                isAudible: false
            )
        }
        let source = [UInt8](data)
        var peak = 0
        var squaredSum = 0.0
        var firstAudibleSampleIndex: Int?
        let sampleCount = source.count / MacSpeechPCMOutputFormat.bytesPerSample
        for sampleIndex in 0 ..< sampleCount {
            let byteIndex = sampleIndex * MacSpeechPCMOutputFormat.bytesPerSample
            let sample = decodedSample(source, at: byteIndex)
            peak = max(peak, abs(Int(sample)))
            squaredSum += Double(sample) * Double(sample)
            if firstAudibleSampleIndex == nil,
               abs(Int(sample)) >= Int(audibleRMS * 32_768) {
                firstAudibleSampleIndex = sampleIndex
            }
        }
        let normalizedPeak = Double(peak) / 32_768.0
        let normalizedRMS = sqrt(squaredSum / Double(sampleCount)) / 32_768.0
        let isAudible = normalizedPeak >= audiblePeak
            || normalizedRMS >= audibleRMS
        let processed = applyFadeIn && isAudible
            ? applyingResumeFadeIn(
                to: data,
                startingAtSample: firstAudibleSampleIndex ?? 0
            )
            : data
        return ProcessingResult(
            bytes: processed,
            isAudible: isAudible
        )
    }

    static func applyingResumeFadeIn(
        to data: Data,
        startingAtSample startIndex: Int = 0
    ) -> Data {
        let totalSampleCount = data.count
            / MacSpeechPCMOutputFormat.bytesPerSample
        guard startIndex >= 0, startIndex < totalSampleCount else {
            return data
        }
        let sampleCount = min(
            resumeFadeInSampleCount,
            totalSampleCount - startIndex
        )
        guard sampleCount > 0 else { return data }
        var bytes = [UInt8](data)
        for fadeIndex in 0 ..< sampleCount {
            let sampleIndex = startIndex + fadeIndex
            let byteIndex = sampleIndex * 2
            let raw = UInt16(bytes[byteIndex])
                | (UInt16(bytes[byteIndex + 1]) << 8)
            let sample = Int16(bitPattern: raw)
            let scaled = Int16(
                Double(sample) * Double(fadeIndex + 1)
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

nonisolated struct MacSpeechContinuousOutputProtector: Sendable {
    static let thresholdDecibels = -12.0
    static let ratio = 3.0
    static let kneeWidthDecibels = 6.0
    static let ceilingDecibels = -3.0
    static let holdSampleCount = 960
    static let releaseSampleCount = 7_200

    private static let ceilingLinear = pow(
        10.0,
        ceilingDecibels / 20.0
    )
    private static let releaseFactor = exp(
        -1.0 / Double(releaseSampleCount)
    )

    private(set) var currentGain = 1.0
    private(set) var holdSamplesRemaining = 0

    struct ProcessingResult: Sendable, Equatable {
        let bytes: Data
        let didStartAttenuation: Bool
        let inputPeak: Double
        let outputPeak: Double
        let minimumGain: Double
    }

    mutating func process(_ data: Data) -> ProcessingResult {
        guard !data.isEmpty,
              data.count.isMultiple(
                of: MacSpeechPCMOutputFormat.bytesPerSample
              ) else {
            return ProcessingResult(
                bytes: data,
                didStartAttenuation: false,
                inputPeak: 0,
                outputPeak: 0,
                minimumGain: currentGain
            )
        }
        let source = [UInt8](data)
        var output = source
        var didStartAttenuation = false
        var inputPeak = 0.0
        var outputPeak = 0.0
        var minimumGain = currentGain

        for byteIndex in stride(from: 0, to: source.count, by: 2) {
            let raw = UInt16(source[byteIndex])
                | (UInt16(source[byteIndex + 1]) << 8)
            let sample = Int16(bitPattern: raw)
            let magnitude = Double(abs(Int32(sample))) / 32_768.0
            inputPeak = max(inputPeak, magnitude)
            let targetGain = Self.targetGain(for: magnitude)
            if targetGain < currentGain {
                currentGain = targetGain
                holdSamplesRemaining = Self.holdSampleCount
                didStartAttenuation = true
            } else if holdSamplesRemaining > 0 {
                holdSamplesRemaining -= 1
            } else {
                let releasedGain = 1.0
                    - (1.0 - currentGain) * Self.releaseFactor
                currentGain = min(targetGain, releasedGain)
            }
            minimumGain = min(minimumGain, currentGain)
            let scaled = Int16(
                (Double(sample) * currentGain).rounded(.towardZero)
            )
            let scaledMagnitude = Double(abs(Int32(scaled))) / 32_768.0
            outputPeak = max(outputPeak, scaledMagnitude)
            let scaledRaw = UInt16(bitPattern: scaled)
            output[byteIndex] = UInt8(truncatingIfNeeded: scaledRaw)
            output[byteIndex + 1] = UInt8(
                truncatingIfNeeded: scaledRaw >> 8
            )
        }
        return ProcessingResult(
            bytes: Data(output),
            didStartAttenuation: didStartAttenuation,
            inputPeak: inputPeak,
            outputPeak: outputPeak,
            minimumGain: minimumGain
        )
    }

    mutating func reset() {
        currentGain = 1
        holdSamplesRemaining = 0
    }

    private static func targetGain(for magnitude: Double) -> Double {
        guard magnitude > 0 else { return 1 }
        let level = 20.0 * log10(magnitude)
        let kneeLower = thresholdDecibels - kneeWidthDecibels / 2.0
        let kneeUpper = thresholdDecibels + kneeWidthDecibels / 2.0
        let compressionGainDecibels: Double
        if level <= kneeLower {
            compressionGainDecibels = 0
        } else if level >= kneeUpper {
            compressionGainDecibels = (1.0 / ratio - 1.0)
                * (level - thresholdDecibels)
        } else {
            let offset = level - thresholdDecibels
                + kneeWidthDecibels / 2.0
            compressionGainDecibels = (1.0 / ratio - 1.0)
                * offset * offset / (2.0 * kneeWidthDecibels)
        }
        let compressionGain = pow(
            10.0,
            compressionGainDecibels / 20.0
        )
        let ceilingGain = min(1.0, ceilingLinear / magnitude)
        return min(1.0, compressionGain, ceilingGain)
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
    ) throws -> MacSpeechPCMOutputEnvelope.ProcessingResult
    func resetForPlaybackGeneration()
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
    private var outputProtector = MacSpeechContinuousOutputProtector()

    func prepare() throws -> MacSpeechLocalPlaybackFormat {
        try lock.withLock {
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
    ) throws -> MacSpeechPCMOutputEnvelope.ProcessingResult {
        let prepared = try lock.withLock {
            guard let playerNode,
                  let converter
            else {
                throw MacSpeechAudioOutputHostError.invalidState
            }
            let processing = MacSpeechPCMOutputEnvelope.processing(
                to: pcm16Bytes,
                applyFadeIn: applyFadeIn
            )
            let protected = outputProtector.process(processing.bytes)
            let buffer = try converter.convert(
                pcm16Bytes: protected.bytes
            )
            let result = MacSpeechPCMOutputEnvelope.ProcessingResult(
                bytes: protected.bytes,
                isAudible: processing.isAudible,
                didStartAttenuation: protected.didStartAttenuation,
                inputPeak: protected.inputPeak,
                outputPeak: protected.outputPeak,
                minimumGain: protected.minimumGain
            )
            return (playerNode, buffer, result)
        }
        prepared.0.scheduleBuffer(
            prepared.1,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            completion(.success(pcm16Bytes.count))
        }
        return prepared.2
    }

    func resetForPlaybackGeneration() {
        lock.withLock {
            converter?.reset()
            outputProtector.reset()
        }
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
        }
    }

    func stop() {
        lock.withLock {
            playerNode?.stop()
            engine?.stop()
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
            outputProtector.reset()
            localFormat = nil
            playerNode = nil
            engine = nil
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
