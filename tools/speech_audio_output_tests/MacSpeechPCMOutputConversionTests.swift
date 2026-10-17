import AudioToolbox
@preconcurrency import AVFoundation
import CryptoKit
import Foundation

@MainActor
enum MacSpeechPCMOutputConversionTests {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private struct Stream {
        var channels = [[Float]](repeating: [], count: 3)
        var processed = Data()
        var chunkFrames: [Int] = []
        var fadeSamples: [Int] = []
    }

    private final nonisolated class ReferenceInput: @unchecked Sendable {
        var offset = 0
        var failed = false

        func nextBuffer(frames: AVAudioPacketCount, source: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
            let end = min(source.count, offset + Int(frames) * 2)
            guard end > offset,
                  let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount((end - offset) / 2)),
                  let channels = input.int16ChannelData
            else {
                failed = true
                return nil
            }
            input.frameLength = input.frameCapacity
            source.copyBytes(to: UnsafeMutableRawBufferPointer(start: channels[0], count: end - offset),
                             from: offset ..< end)
            offset = end
            return input
        }
    }

    private static var checks = 0

    static func runIfRequested() -> Int {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else { return 0 }
        do {
            try require(arguments.count == 3 && arguments[1] == "--r3-m01-wav", "explicit WAV argument")
            try run(url: URL(fileURLWithPath: arguments[2]))
            return checks
        } catch {
            print("r3_m01_output_conversion=FAIL error=\(error)")
            Foundation.exit(1)
        }
    }

    private static func run(url: URL) throws {
        let source = try readSource(url: url)
        let target = try syntheticFormat()
        let stream = try convertChunks(source, target: target)
        let expectedFade = independentFade(source)
        try require(stream.processed == expectedFade, "fade bytes match independent 120-sample ramp")
        try require(stream.fadeSamples.reduce(0, +) == 120, "five milliseconds of fade, never restarted")
        let reference = try convertReference(expectedFade, target: target, finish: false)
        let finished = try convertReference(expectedFade, target: target, finish: true)
        print("r3_m01_stream_frames=\(stream.chunkFrames) fade_samples=\(stream.fadeSamples)")
        try compare(stream.channels, with: reference, label: "unflushed whole-input reference")
        try require(stream.chunkFrames.count == 48 && source.count % 4800 == 2464,
                    "47 full chunks and final 2464-byte chunk")
        try inspectTail(source: source, stream: stream.channels, finished: finished)
        print("r3_m01_output_conversion=PASS_SYNTHETIC_3CH_ONLY cases=6 checks=\(checks)")
    }

    private static func syntheticFormat() throws -> AVAudioFormat {
        let tag = kAudioChannelLayoutTag_DiscreteInOrder | 3
        guard let layout = AVAudioChannelLayout(layoutTag: tag) else {
            throw Failure(description: "SYNTHETIC_3CH DiscreteInOrder layout construction failed, tag=\(tag)")
        }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   interleaved: false, channelLayout: layout)
        try require(format.sampleRate == 16000 && format.channelCount == 3
            && format.commonFormat == .pcmFormatFloat32 && !format.isInterleaved
            && format.channelLayout?.layoutTag == tag, "SYNTHETIC_3CH format readback")
        let asbd = format.streamDescription.pointee
        print("r3_m01_format=SYNTHETIC_3CH ACTUAL_PLAYBACK_LAYOUT_UNKNOWN rate=\(format.sampleRate)"
            + " channels=\(format.channelCount) common_format=Float32 interleaved=\(format.isInterleaved)"
            + " layout_tag=\(tag) format_id=\(asbd.mFormatID) flags=\(asbd.mFormatFlags)"
            + " bytes_per_packet=\(asbd.mBytesPerPacket) frames_per_packet=\(asbd.mFramesPerPacket)"
            + " bytes_per_frame=\(asbd.mBytesPerFrame) bits_per_channel=\(asbd.mBitsPerChannel)")
        return format
    }

    private static func readSource(url: URL) throws -> Data {
        let bytes = try Data(contentsOf: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try require(digest == "774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea",
                    "registered nonprivate WAV SHA-256")
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        try require(file.processingFormat.sampleRate == 24000 && file.processingFormat.channelCount == 1,
                    "24 kHz mono source")
        try require(file.length == 114_032, "complete fixed source frame count")
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 114_032),
              let channels = buffer.int16ChannelData
        else {
            throw Failure(description: "fixed WAV PCM16 read buffer allocation failed")
        }
        var pcm = Data()
        var reads = 0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            try require(buffer.frameLength > 0, "WAV read makes progress before EOF")
            pcm.append(Data(bytes: channels[0], count: Int(buffer.frameLength) * 2))
            reads += 1
        }
        try require(pcm == bytes.suffix(228_064), "complete WAV read preserves original PCM bytes")
        print("r3_m01_wav_reads=\(reads) input_samples=\(pcm.count / 2)")
        return pcm
    }

    private static func convertChunks(_ source: Data, target: AVAudioFormat) throws -> Stream {
        let converter = try MacSpeechPCMOutputConverter(localFormat: target)
        var pending: MacSpeechPCMOutputFadeIn? = .initial
        var stream = Stream()
        for offset in stride(from: 0, to: source.count, by: 4800) {
            let chunk = source.subdata(in: offset ..< min(offset + 4800, source.count))
            let processing = MacSpeechPCMOutputEnvelope.processing(to: chunk, fadeIn: pending)
            if let fade = pending, processing.appliedFadeInSampleCount > 0 {
                pending = fade.advancing(by: processing.appliedFadeInSampleCount)
            }
            if offset == 0 {
                FileHandle.standardOutput.write(Data("r3_m01_production_convert=ENTERED chunk=0\n".utf8))
            }
            let output = try converter.convert(pcm16Bytes: processing.bytes)
            try require(output.format == target, "native output format at chunk \(offset / 4800)")
            guard let channels = output.floatChannelData else {
                throw Failure(description: "production output has no Float32 channel data at byte offset \(offset)")
            }
            stream.processed.append(processing.bytes)
            stream.fadeSamples.append(processing.appliedFadeInSampleCount)
            stream.chunkFrames.append(Int(output.frameLength))
            for channel in 0 ..< 3 {
                let samples = Array(UnsafeBufferPointer(start: channels[channel],
                                                        count: Int(output.frameLength)))
                try require(samples.allSatisfy(\.isFinite), "finite native channel \(channel)")
                stream.channels[channel].append(contentsOf: samples)
            }
        }
        return stream
    }

    private static func independentFade(_ source: Data) -> Data {
        var samples = decoded(source)
        var applied = 0
        for offset in stride(from: 0, to: samples.count, by: 2400) {
            let end = min(offset + 2400, samples.count)
            let original = Array(samples[offset ..< end])
            let peak = original.map { abs(Int($0)) }.max() ?? 0
            let energy = original.reduce(0.0) { $0 + Double($1) * Double($1) }
            let audible = Double(peak) / 32768 >= 0.01
                || sqrt(energy / Double(original.count)) / 32768 >= 0.002
            guard applied < 120, audible,
                  let first = original.firstIndex(where: { abs(Int($0)) >= 65 }) else { continue }
            for index in first ..< original.count where applied < 120 {
                applied += 1
                samples[offset + index] = Int16(Double(original[index]) * Double(applied) / 120)
            }
        }
        return encoded(samples)
    }

    private static func convertReference(
        _ source: Data, target: AVAudioFormat, finish: Bool
    ) throws -> [[Float]] {
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000,
                                              channels: 1, interleaved: true),
            let converter = AVAudioConverter(from: inputFormat, to: target)
        else {
            throw Failure(description: "independent reference PCM16 format or SYNTHETIC_3CH converter unavailable")
        }
        let capacity = AVAudioFrameCount(ceil(Double(source.count / 2) * 2 / 3))
            + converter.primeInfo.leadingFrames + converter.primeInfo.trailingFrames + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity),
              let channels = output.floatChannelData
        else {
            throw Failure(description: "independent reference Float32 output buffer allocation failed")
        }
        let state = ReferenceInput()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { requested, inputStatus in
            if state.offset == source.count {
                inputStatus.pointee = finish ? .endOfStream : .noDataNow
                return nil
            }
            guard let input = state.nextBuffer(frames: requested, source: source, format: inputFormat) else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }
        print("r3_m01_reference finish=\(finish) status=\(status.rawValue) frames=\(output.frameLength)"
            + " supplied_frames=\(state.offset / 2) leading=\(converter.primeInfo.leadingFrames)"
            + " trailing=\(converter.primeInfo.trailingFrames)")
        if let error {
            throw Failure(description: "independent reference failed domain=\(error.domain) code=\(error.code)")
        }
        try require(error == nil && status != .error && output.frameLength < capacity,
                    "independent reference completes without capacity truncation")
        try require(!state.failed && state.offset == source.count, "independent reference consumes every source sample")
        return (0 ..< 3).map { channel in
            Array(UnsafeBufferPointer(start: channels[channel], count: Int(output.frameLength)))
        }
    }

    private static func compare(_ actual: [[Float]], with expected: [[Float]], label: String) throws {
        for channel in 0 ..< 3 {
            let comparedCount = min(actual[channel].count, expected[channel].count)
            let first = (0 ..< comparedCount).first { actual[channel][$0] != expected[channel][$0] }
            let peak = actual[channel].map { abs($0) }.max() ?? 0
            let nonzero = actual[channel].filter { $0 != 0 }.count
            let onset = actual[channel].firstIndex(where: { $0 != 0 })
            print("r3_m01_channel=\(channel) frames=\(actual[channel].count) peak=\(peak) nonzero=\(nonzero)"
                + " first_nonzero=\(onset.map(String.init) ?? "NONE")"
                + " first_difference=\(first?.description ?? "NONE")")
            try require(first == nil && actual[channel].count == expected[channel].count,
                        "\(label) channel \(channel) first difference \(first?.description ?? "length")")
        }
    }

    private static func inspectTail(source: Data, stream: [[Float]], finished: [[Float]]) throws {
        let nominal = Double(source.count / 2) * 2 / 3
        print("r3_m01_nominal_output_frames=\(nominal) actual=\(stream[0].count) EOF=\(finished[0].count)")
        for channel in 0 ..< 3 {
            try require(finished[channel].count >= stream[channel].count, "EOF covers native channel \(channel)")
            let prefix = Array(finished[channel].prefix(stream[channel].count))
            try require(prefix == stream[channel], "EOF preserves all already produced samples in channel \(channel)")
            let tail = finished[channel].dropFirst(stream[channel].count)
            let nonzero = tail.filter { $0 != 0 }.count
            print("r3_m01_tail_channel=\(channel) unflushed_frames=\(tail.count) nonzero=\(nonzero)"
                + " peak=\(tail.map { abs($0) }.max() ?? 0)")
            try require(nonzero == 0, "unrendered nonzero tail in channel \(channel)")
        }
    }

    private static func decoded(_ data: Data) -> [Int16] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 2).map {
            Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)
        }
    }

    private static func encoded(_ samples: [Int16]) -> Data {
        var bytes = Data(capacity: samples.count * 2)
        for sample in samples {
            bytes.append(UInt8(truncatingIfNeeded: sample))
            bytes.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        return bytes
    }

    private static func require(_ condition: Bool, _ label: String) throws {
        guard condition else { throw Failure(description: label) }
        checks += 1
    }
}
