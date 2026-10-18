@preconcurrency import AVFoundation
import Foundation

@MainActor
enum NativeInputChannelMappingTests {
    private struct Result {
        var mono48: [Float] = []
        var packets: [MacSpeechPCM16Packet] = []
    }

    private static var cases = 0
    private static var checks = 0
    private static let rate = 16000.0
    private static let frames = 32137
    private static let anchor: UInt64 = 10_000_000_000

    static func run() throws {
        for channel in 0 ..< 3 {
            cases += 1
            var input = Array(repeating: [Float](repeating: 0, count: frames), count: 3)
            input[channel] = tone(frequency: 300 + Double(channel) * 400, amplitude: 0.2)
            let result = try verify(input)
            expect(channel == 0 ? rms(result.mono48) > 0.1 : result.mono48.allSatisfy { $0 == 0 },
                   "only selected channel zero reaches the mono converter")
        }
        for amplitude: Float in [0.0005, 0.01, 0.2, 0.8] {
            cases += 1
            let selected = tone(frequency: 300, amplitude: amplitude)
            let channelOne = tone(frequency: 700, amplitude: 0.35)
            let channelTwo = tone(frequency: 1100, amplitude: 0.15)
            let result = try verify([selected, channelOne, channelTwo])
            let measured = rms(Array(result.mono48[24000 ..< 72000]))
            expect(abs(measured - Double(amplitude) / sqrt(2)) < Double(amplitude) * 0.015,
                   "steady selected-channel amplitude is preserved without a software gain or Gate")
        }
        try silenceAndStep()
        try interleaved()
        try fullScale()
        try invalidBuffer()
        print("input_channel_mapping_cases=\(cases)")
        print("input_channel_mapping_checks=\(checks)")
        print("input_channel_mapping=SYNTHETIC_DISCRETE_3CH_SELECTS_CH0")
        print("input_channel_mapping_device_access=ZERO")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    private static func tone(frequency: Double, amplitude: Float) -> [Float] {
        (0 ..< frames).map { Float(sin(Double($0) * 2 * .pi * frequency / rate)) * amplitude }
    }

    private static func format(channels: Int, interleaved: Bool) throws -> AVAudioFormat {
        guard let layout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
        ) else { throw MacSpeechAudioCaptureError.invalidInputFormat }
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                             interleaved: interleaved, channelLayout: layout)
    }

    private static func buffer(
        _ channels: [[Float]], range: Range<Int>, format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(range.count)),
              let pointers = buffer.floatChannelData
        else { throw MacSpeechAudioCaptureError.conversionFailed }
        buffer.frameLength = buffer.frameCapacity
        for (channel, values) in channels.enumerated() {
            for (frame, index) in range.enumerated() {
                if format.isInterleaved {
                    pointers[0][frame * channels.count + channel] = values[index]
                } else {
                    pointers[channel][frame] = values[index]
                }
            }
        }
        return buffer
    }

    private static func convert(_ channels: [[Float]], interleaved: Bool = false) throws -> Result {
        let format = try format(channels: channels.count, interleaved: interleaved)
        let input = try MacSpeechFloatMono48kConverter(inputFormat: format)
        let mono = try MacSpeechFloatMono48kConverter.makeBuffer(samples: [0]).format
        let output = try MacSpeechAudioConverter(inputFormat: mono)
        let host = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)
        expect(host.configure() == .appleVoiceProcessing, "the synthetic path uses Apple pass-through")
        var result = Result()
        for offset in stride(from: 0, to: frames, by: 1600) {
            let range = offset ..< min(offset + 1600, frames)
            let converted = try input.convert(
                buffer(channels, range: range, format: format),
                hostTimeNanoseconds: anchor + UInt64(offset) * 1_000_000_000 / 16000,
                sampleTime: Int64(offset)
            )
            expect(converted.hostTimeNanoseconds != nil, "continuous native buffers retain content time")
            let spans = host.processCaptureSpans(converted.samples,
                                                 hostTimeNanoseconds: converted.hostTimeNanoseconds)
            expect(spans.flatMap(\.samples) == converted.samples, "Apple AcousticHost preserves sample content")
            result.mono48.append(contentsOf: converted.samples)
            try result.packets.append(contentsOf: output.convert(captureSpans: spans,
                                                                 requiresContinuousContentTime: true))
        }
        return result
    }

    private static func verify(_ channels: [[Float]], interleaved: Bool = false) throws -> Result {
        let actual = try convert(channels, interleaved: interleaved)
        let reference = try convert([channels[0]])
        expect(actual.mono48 == reference.mono48, "three-channel output matches independent mono channel-zero input")
        expect(actual.packets.map(\.bytes) == reference.packets.map(\.bytes),
               "chunk order and PCM bytes match mono input")
        expect(!actual.packets.isEmpty, "the test enters both production converters and produces packets")
        for (index, packet) in actual.packets.enumerated() {
            expect(packet.bytes.count == 960, "24kHz mono PCM16LE packet contains 480 samples")
            expect(packet.contentTimestampNanoseconds == anchor + UInt64(index) * 20_000_000,
                   "packet timestamps follow the original content timeline")
        }
        return actual
    }

    private static func silenceAndStep() throws {
        cases += 1
        let signal = tone(frequency: 300, amplitude: 1).enumerated().map { index, value -> Float in
            switch index {
            case 6400 ..< 16000: value * 0.05
            case 16000 ..< 25600: value * 0.5
            default: 0
            }
        }
        let result = try verify([signal, tone(frequency: 700, amplitude: 0.6), signal])
        expect(result.mono48[4800 ..< 14400].allSatisfy { $0 == 0 }, "unselected sound cannot fill selected silence")
        let low = rms(Array(result.mono48[24000 ..< 43200]))
        let high = rms(Array(result.mono48[52800 ..< 72000]))
        expect(abs(high / low - 10) < 0.1, "a known tenfold amplitude step remains tenfold")
        expect(result.mono48[86400 ..< 91200].allSatisfy { $0 == 0 }, "selected trailing silence stays silence")
    }

    private static func interleaved() throws {
        cases += 1
        _ = try verify([tone(frequency: 300, amplitude: 0.2),
                        tone(frequency: 700, amplitude: 0.3), tone(frequency: 1100, amplitude: 0.4)],
                       interleaved: true)
    }

    private static func fullScale() throws {
        for value: Float in [-1.25, 1.25] {
            cases += 1
            let result = try verify(Array(repeating: [Float](repeating: value, count: frames), count: 3))
            expect(abs(result.mono48[24000]) > 1.2, "float conversion does not normalize an overscale input")
            let encoded = MacSpeechPCM16Encoder.encode(samples: [value])
            expect(result.packets[30].bytes == Data((0 ..< 480).flatMap { _ in encoded }),
                   "the existing PCM16 boundary clamps overscale values to its finite range")
        }
    }

    private static func invalidBuffer() throws {
        cases += 1
        let format = try format(channels: 3, interleaved: false)
        guard let empty = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)
        else { throw MacSpeechAudioCaptureError.conversionFailed }
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: format)
        do {
            _ = try converter.convert(empty, hostTimeNanoseconds: anchor, sampleTime: 0)
            expect(false, "a zero-frame buffer must fail")
        } catch {
            expect(error as? MacSpeechAudioCaptureError == .conversionFailed, "invalid input fails explicitly")
        }
    }

    private static func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    }
}
