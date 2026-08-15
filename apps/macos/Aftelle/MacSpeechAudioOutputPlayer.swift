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

nonisolated struct MacSpeechPCMOutputFadeIn: Sendable, Equatable {
    let totalSampleCount: Int
    let appliedSampleCount: Int

    static let initial = MacSpeechPCMOutputFadeIn(
        totalSampleCount: MacSpeechPCMOutputEnvelope.resumeFadeInSampleCount,
        appliedSampleCount: 0
    )
    static let stalledResume = MacSpeechPCMOutputFadeIn(
        totalSampleCount:
            MacSpeechPCMOutputEnvelope.stalledResumeFadeInSampleCount,
        appliedSampleCount: 0
    )

    func advancing(by sampleCount: Int) -> MacSpeechPCMOutputFadeIn? {
        let next = min(
            totalSampleCount,
            appliedSampleCount + max(0, sampleCount)
        )
        guard next < totalSampleCount else { return nil }
        return MacSpeechPCMOutputFadeIn(
            totalSampleCount: totalSampleCount,
            appliedSampleCount: next
        )
    }
}

nonisolated enum MacSpeechPCMOutputEnvelope {
    static let resumeFadeInSampleCount = 120
    static let stalledResumeFadeInSampleCount = 480
    private static let audiblePeak = 0.01
    private static let audibleRMS = 0.002

    struct ProcessingResult: Sendable, Equatable {
        let bytes: Data
        let isAudible: Bool
        let appliedFadeInSampleCount: Int
    }

    static func processing(
        to data: Data,
        applyFadeIn: Bool
    ) -> ProcessingResult {
        processing(
            to: data,
            fadeIn: applyFadeIn ? .initial : nil
        )
    }

    static func processing(
        to data: Data,
        fadeIn: MacSpeechPCMOutputFadeIn?
    ) -> ProcessingResult {
        guard !data.isEmpty,
              data.count.isMultiple(of: MacSpeechPCMOutputFormat.bytesPerSample)
        else {
            return ProcessingResult(
                bytes: data,
                isAudible: false,
                appliedFadeInSampleCount: 0
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
        let faded: (bytes: Data, appliedSampleCount: Int)
        if let fadeIn, isAudible {
            faded = applyingFadeIn(
                to: data,
                startingAtSample: firstAudibleSampleIndex ?? 0,
                fadeIn: fadeIn
            )
        } else {
            faded = (data, 0)
        }
        return ProcessingResult(
            bytes: faded.bytes,
            isAudible: isAudible,
            appliedFadeInSampleCount: faded.appliedSampleCount
        )
    }

    static func applyingResumeFadeIn(
        to data: Data,
        startingAtSample startIndex: Int = 0
    ) -> Data {
        applyingFadeIn(
            to: data,
            startingAtSample: startIndex,
            fadeIn: .initial
        ).bytes
    }

    private static func applyingFadeIn(
        to data: Data,
        startingAtSample startIndex: Int,
        fadeIn: MacSpeechPCMOutputFadeIn
    ) -> (bytes: Data, appliedSampleCount: Int) {
        let totalSampleCount = data.count
            / MacSpeechPCMOutputFormat.bytesPerSample
        let remainingFadeSampleCount = max(
            0,
            fadeIn.totalSampleCount - fadeIn.appliedSampleCount
        )
        guard startIndex >= 0,
              startIndex < totalSampleCount,
              remainingFadeSampleCount > 0 else {
            return (data, 0)
        }
        let sampleCount = min(
            remainingFadeSampleCount,
            totalSampleCount - startIndex
        )
        guard sampleCount > 0 else { return (data, 0) }
        var bytes = [UInt8](data)
        for fadeIndex in 0 ..< sampleCount {
            let sampleIndex = startIndex + fadeIndex
            let byteIndex = sampleIndex * 2
            let raw = UInt16(bytes[byteIndex])
                | (UInt16(bytes[byteIndex + 1]) << 8)
            let sample = Int16(bitPattern: raw)
            let scaled = Int16(
                Double(sample)
                    * Double(fadeIn.appliedSampleCount + fadeIndex + 1)
                    / Double(fadeIn.totalSampleCount)
            )
            let scaledRaw = UInt16(bitPattern: scaled)
            bytes[byteIndex] = UInt8(truncatingIfNeeded: scaledRaw)
            bytes[byteIndex + 1] = UInt8(truncatingIfNeeded: scaledRaw >> 8)
        }
        return (Data(bytes), sampleCount)
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
        fadeIn: MacSpeechPCMOutputFadeIn?,
        completion: @escaping @Sendable (
            Result<Int, MacSpeechAudioOutputHostError>
        ) -> Void
    ) throws -> MacSpeechPCMOutputEnvelope.ProcessingResult
    func resetForPlaybackGeneration()
    func start() throws
    func finishPlayback()
    func clearScheduledPlayback()
    func resetForRouteChange()
    func stop()
    func close()
}

nonisolated extension MacSpeechAudioOutputPlaying {
    func resetForRouteChange() {}
}

nonisolated final class SystemMacSpeechAudioOutputPlayer:
    MacSpeechAudioOutputPlaying, @unchecked Sendable
{
    private let lock = NSLock()
    private let audioEngine: SystemMacSpeechVoiceProcessingEngine
    private var converter: MacSpeechPCMOutputConverter?
    private var localFormat: AVAudioFormat?

    init(
        audioEngine: SystemMacSpeechVoiceProcessingEngine =
            SystemMacSpeechVoiceProcessingEngine()
    ) {
        self.audioEngine = audioEngine
    }

    func prepare() throws -> MacSpeechLocalPlaybackFormat {
        try lock.withLock {
            if let localFormat {
                return describe(localFormat)
            }

            let localFormat: AVAudioFormat
            do {
                localFormat = try audioEngine.prepareOutput()
            } catch {
                throw MacSpeechAudioOutputHostError.outputUnavailable
            }
            guard localFormat.sampleRate > 0,
                  localFormat.channelCount > 0,
                  let converter = try? MacSpeechPCMOutputConverter(
                    localFormat: localFormat
                  )
            else {
                audioEngine.closeOutput()
                throw MacSpeechAudioOutputHostError.outputUnavailable
            }

            self.converter = converter
            self.localFormat = localFormat
            return describe(localFormat)
        }
    }

    func schedule(
        pcm16Bytes: Data,
        fadeIn: MacSpeechPCMOutputFadeIn?,
        completion: @escaping @Sendable (
            Result<Int, MacSpeechAudioOutputHostError>
        ) -> Void
    ) throws -> MacSpeechPCMOutputEnvelope.ProcessingResult {
        let prepared = try lock.withLock {
            guard let converter else {
                throw MacSpeechAudioOutputHostError.invalidState
            }
            let processing = MacSpeechPCMOutputEnvelope.processing(
                to: pcm16Bytes,
                fadeIn: fadeIn
            )
            let buffer = try converter.convert(
                pcm16Bytes: processing.bytes
            )
            return (buffer, processing)
        }
        do {
            try audioEngine.scheduleOutput(prepared.0) {
                completion(.success(pcm16Bytes.count))
            }
        } catch {
            throw MacSpeechAudioOutputHostError.invalidState
        }
        return prepared.1
    }

    func resetForPlaybackGeneration() {
        lock.withLock {
            converter?.reset()
        }
    }

    func start() throws {
        let isPrepared = lock.withLock { localFormat != nil }
        guard isPrepared else {
            throw MacSpeechAudioOutputHostError.invalidState
        }
        do {
            try audioEngine.startOutput()
        } catch {
            throw MacSpeechAudioOutputHostError.playbackFailed
        }
    }

    func finishPlayback() {
        audioEngine.finishOutputPlayback()
    }

    func clearScheduledPlayback() {
        audioEngine.clearScheduledOutput()
    }

    func resetForRouteChange() {
        audioEngine.resetForRouteChange()
    }

    func stop() {
        audioEngine.stopOutput()
    }

    func close() {
        lock.withLock {
            audioEngine.closeOutput()
            converter = nil
            localFormat = nil
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
