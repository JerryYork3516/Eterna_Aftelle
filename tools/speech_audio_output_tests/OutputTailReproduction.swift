import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

@main
@MainActor
private enum OutputTailReproduction {
    private struct Failure: Error { let reason: String }

    private final nonisolated class Input: @unchecked Sendable {
        var offset = 0
    }

    static func main() {
        do { try run() } catch {
            print("output_tail_red=FAIL \(error)")
            exit(1)
        }
    }

    private static func require(_ value: Bool, _ reason: String) throws {
        if !value {
            throw Failure(reason: reason)
        }
    }

    private static func sourceBytes() -> Data {
        let samples: [Int16] = (0 ..< 24000).map { index in
            index < 2400 ? 0 : Int16(10000 * sin(Double(index) * 2 * .pi * 373 / 24000))
        }
        var bytes = Data()
        for sample in samples {
            bytes.append(UInt8(truncatingIfNeeded: sample))
            bytes.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        return bytes
    }

    private static func run() throws {
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3)!
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   interleaved: false, channelLayout: layout)
        let bytes = sourceBytes()
        let converter = try MacSpeechPCMOutputConverter(localFormat: format)
        var actual = [[Float]](repeating: [], count: 3)
        var chunkFrames: [Int] = []
        for offset in stride(from: 0, to: bytes.count, by: 4800) {
            let chunk = bytes.subdata(in: offset ..< min(offset + 4800, bytes.count))
            let buffer = try converter.convert(pcm16Bytes: chunk)
            chunkFrames.append(Int(buffer.frameLength))
            for channel in 0 ..< 3 {
                actual[channel] += Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel],
                                                             count: Int(buffer.frameLength)))
            }
        }
        let unfinished = try reference(bytes, format: format, finish: false)
        let finished = try reference(bytes, format: format, finish: true)
        try require(actual == unfinished, "chunked production converter differs from the continuous reference")
        try require(actual.allSatisfy { $0 == actual[0] }, "synthetic three-channel duplication changed")
        print("source_frames=24000 scheduled_frames=\(actual[0].count)"
            + " EOF_frames=\(finished[0].count) chunks=\(chunkFrames)")
        var missingNonzero = 0
        for channel in 0 ..< 3 {
            try require(finished[channel].count >= actual[channel].count, "EOF reference shortened the stream")
            try require(Array(finished[channel].prefix(actual[channel].count)) == actual[channel],
                        "EOF changed a sample already emitted")
            let tail = finished[channel].dropFirst(actual[channel].count)
            let nonzero = tail.filter { $0 != 0 }.count
            missingNonzero += nonzero
            print("channel=\(channel) missing_frames=\(tail.count) missing_nonzero=\(nonzero)"
                + " peak=\(tail.map { abs($0) }.max() ?? 0)")
        }
        let silence = Data(repeating: 0, count: bytes.count)
        let silentConverter = try MacSpeechPCMOutputConverter(localFormat: format)
        let silent = try silentConverter.convert(pcm16Bytes: silence)
        let silentEOF = try reference(silence, format: format, finish: true)
        try require((0 ..< 3).allSatisfy { channel in
            (0 ..< Int(silent.frameLength)).allSatisfy { silent.floatChannelData![channel][$0] == 0 }
                && silentEOF[channel].allSatisfy { $0 == 0 }
        }, "silence negative control invented signal")
        print("silence_negative_control=PASS device_access=ZERO")
        try require(missingNonzero == 0, "finite playback ends with nonzero converter samples never scheduled")
        print("output_tail_red=PASS")
    }

    private static func reference(_ source: Data, format: AVAudioFormat, finish: Bool) throws -> [[Float]] {
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000,
                                        channels: 1, interleaved: true)!
        let converter = AVAudioConverter(from: inputFormat, to: format)!
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 20000)!
        let input = Input()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { requested, state in
            guard input.offset < source.count else {
                state.pointee = finish ? .endOfStream : .noDataNow
                return nil
            }
            let end = min(source.count, input.offset + Int(requested) * 2)
            let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: UInt32((end - input.offset) / 2))!
            buffer.frameLength = buffer.frameCapacity
            source.copyBytes(to: UnsafeMutableRawBufferPointer(start: buffer.int16ChannelData![0],
                                                               count: end - input.offset),
                             from: input.offset ..< end)
            input.offset = end
            state.pointee = .haveData
            return buffer
        }
        try require(error == nil && status != .error && input.offset == source.count
            && output.frameLength < output.frameCapacity, "independent reference did not consume the complete source")
        print("reference finish=\(finish) status=\(status.rawValue) frames=\(output.frameLength)"
            + " prime_leading=\(converter.primeInfo.leadingFrames)"
            + " prime_trailing=\(converter.primeInfo.trailingFrames)")
        if finish {
            let terminal = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
            var terminalError: NSError?
            let terminalStatus = converter.convert(to: terminal, error: &terminalError) { _, state in
                state.pointee = .endOfStream
                return nil
            }
            try require(terminalError == nil && terminalStatus == .endOfStream && terminal.frameLength == 0,
                        "EOF reference has not reached the actual terminal status")
            print("reference_terminal=EndOfStream frames=0")
        }
        return (0 ..< 3).map {
            Array(UnsafeBufferPointer(start: output.floatChannelData![$0], count: Int(output.frameLength)))
        }
    }
}
