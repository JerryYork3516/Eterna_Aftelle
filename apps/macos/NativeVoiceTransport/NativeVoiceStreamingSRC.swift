@preconcurrency import AVFoundation
import Foundation

nonisolated enum NativeVoiceTransportError: Error {
    case unsupportedFormat, allocation, conversion, exhausted, invalidPCM, staleIdentity
}

/// Serial non-realtime worker only. Exactly one system SRC, never a hardware callback.
final nonisolated class NativeVoiceStreamingSRC {
    let inputRate: Double
    let outputRate: Double
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private var pending: [Float] = []
    private(set) var inputFrames = 0
    private(set) var outputFrames = 0
    private(set) var discardedFilterTailFrames = 0
    private(set) var finished = false
    private var failed = false
    #if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
        var sameFramePrimeInfo: AVAudioConverterPrimeInfo? {
            inputRate == outputRate ? nil : converter.primeInfo
        }
    #endif

    var fractionalOutputFrames: Double {
        Double(inputFrames) * outputRate / inputRate - Double(expectedFrames)
    }

    init(inputRate: Double, outputRate: Double) throws {
        guard inputRate.isFinite, outputRate.isFinite, inputRate > 0, outputRate > 0,
              let input = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: inputRate,
                  channels: 1,
                  interleaved: false
              ),
              let output = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: outputRate,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: input, to: output)
        else {
            throw NativeVoiceTransportError.unsupportedFormat
        }
        self.inputRate = inputRate
        self.outputRate = outputRate
        inputFormat = input
        outputFormat = output
        self.converter = converter
        converter.primeMethod = .normal
    }

    func append(_ samples: [Float]) throws -> [Float] {
        guard !finished, !failed else { throw NativeVoiceTransportError.exhausted }
        guard samples.allSatisfy(\.isFinite), samples.count <= 1_048_576,
              inputFrames <= Int.max - samples.count else { throw NativeVoiceTransportError.invalidPCM }
        if samples.isEmpty {
            return []
        }
        let projectedOutput = Double(inputFrames + samples.count) * outputRate / inputRate
        guard projectedOutput.isFinite, projectedOutput < Double(Int.max / 2) else {
            throw NativeVoiceTransportError.invalidPCM
        }
        inputFrames += samples.count
        try convert(samples, end: false)
        return releasePending()
    }

    func finish() throws -> [Float] {
        if finished {
            return []
        }
        try convert([], end: true)
        guard outputFrames + pending.count >= expectedFrames else { throw NativeVoiceTransportError.conversion }
        let result = releasePending()
        discardedFilterTailFrames = pending.count
        pending.removeAll(keepingCapacity: true)
        finished = true
        return result
    }

    var unreleasedContentFrames: Int {
        expectedFrames - outputFrames
    }

    private var expectedFrames: Int {
        Int((Double(inputFrames) * outputRate / inputRate).rounded(.down))
    }

    private func releasePending() -> [Float] {
        let count = min(pending.count, expectedFrames - outputFrames)
        let result = Array(pending.prefix(count))
        pending.removeFirst(count)
        outputFrames += count
        return result
    }

    private func inputBuffer(_ samples: [Float], offset: inout Int, requested: Int) -> AVAudioPCMBuffer? {
        let count = min(requested, samples.count - offset)
        guard count > 0,
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(count)),
              let target = input.floatChannelData?[0] else { return nil }
        input.frameLength = AVAudioFrameCount(count)
        samples.withUnsafeBufferPointer { source in
            target.update(from: source.baseAddress! + offset, count: count)
        }
        offset += count
        return input
    }

    private func appendOutput(_ output: AVAudioPCMBuffer) throws {
        guard let data = output.floatChannelData?[0] else { throw NativeVoiceTransportError.allocation }
        let converted = UnsafeBufferPointer(start: data, count: Int(output.frameLength))
        guard converted.allSatisfy(\.isFinite) else { throw NativeVoiceTransportError.invalidPCM }
        pending.append(contentsOf: converted)
    }

    private func convert(_ samples: [Float], end: Bool) throws {
        guard !failed else { throw NativeVoiceTransportError.exhausted }
        failed = true
        var offset = 0
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
                throw NativeVoiceTransportError.allocation
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { requested, inputStatus in
                guard offset < samples.count else {
                    inputStatus.pointee = end ? .endOfStream : .noDataNow
                    return nil
                }
                guard let input = self.inputBuffer(samples, offset: &offset, requested: Int(requested)) else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputStatus.pointee = .haveData
                return input
            }
            if let error {
                throw error
            }
            guard status != .error else { throw NativeVoiceTransportError.conversion }
            try appendOutput(output)
            if status == .endOfStream || status == .inputRanDry {
                guard offset == samples.count else { throw NativeVoiceTransportError.conversion }
                failed = false
                return
            }
            guard output.frameLength > 0 else { throw NativeVoiceTransportError.conversion }
        }
    }
}

nonisolated enum NativeVoicePCM16 {
    static func encode(_ samples: [Float]) -> Data {
        var bytes = Data(capacity: samples.count * 2)
        for sample in samples {
            let clipped = min(32767, max(-32768, (Double(sample) * 32768).rounded()))
            let value = UInt16(bitPattern: Int16(clipped))
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        return bytes
    }

    static func decode(_ bytes: Data) throws -> [Float] {
        guard bytes.count.isMultiple(of: 2) else { throw NativeVoiceTransportError.invalidPCM }
        let data = Array(bytes)
        return stride(from: 0, to: data.count, by: 2).map {
            Float(Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8)) / 32768
        }
    }
}
