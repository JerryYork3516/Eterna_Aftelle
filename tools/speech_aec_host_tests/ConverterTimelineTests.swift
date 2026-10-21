@preconcurrency import AVFoundation
import Foundation

private final class ReferenceInput: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

@main
@MainActor
private struct ConverterTimelineTests {
    private static var cases = 0
    private static var checks = 0
    private static let anchor: UInt64 = 10_000_000_000

    static func main() throws {
        #if DEBUG
            if try diagnosticMode() {
                return
            }
        #endif
        let scenarios = ["missing-start", "missing-middle", "forward", "backward",
                         "sample-gap", "host-jump-with-sample-time", "jitter", "reset"]
        for rate in [16000.0, 48000.0, 44100.0] {
            try streaming(rate: rate)
            for scenario in scenarios {
                try clockBoundary(rate: rate, scenario: scenario)
            }
            try delivery(rate: rate)
            for drift in [0.0, -62667.0, 62667.0] {
                try longClock(rate: rate, driftAtBoundary: drift)
            }
            let faults = ["sample-gap", "sample-backward", "host-jump", "host-backward",
                          "missing-host", "missing-sample", "one-sample-excess"]
            for fault in faults {
                try driftThenFault(rate: rate, fault: fault)
            }
        }
        try packetTimeAndReset()
        try gatedSpanCompatibility()
        try processingState()
        try capacity()
        try invalidTimestamp()
        try NativeInputChannelMappingTests.run()
        print("speech_converter_timeline_cases=\(cases)")
        print("speech_converter_timeline_checks=\(checks)")
        print("speech_converter_device_access=ZERO")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            fatalError(message)
        }
    }

    private static func streaming(rate: Double) throws {
        cases += 1
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
        let sizes = [Int(rate / 100), Int(rate / 50), 128, 1, 7, 2, 511, 1,
                     Int(rate / 100), 256, Int(rate / 20)]
        let input = waveform(sizes.reduce(0, +))
        var inputOffset = 0
        var samples: [Float] = []
        for size in sizes {
            let out = try converter.convert(
                buffer(Array(input[inputOffset ..< (inputOffset + size)]), rate: rate),
                hostTimeNanoseconds: time(inputOffset, rate: rate),
                sampleTime: Int64(inputOffset)
            )
            if !out.samples.isEmpty {
                expect(out.hostTimeNanoseconds.map {
                    abs(Double($0) - Double(time(samples.count, rate: 48000))) <= 1
                } == true,
                "buffered output follows source cursor, not latest callback")
            }
            samples += out.samples
            inputOffset += size
        }
        let expected = try reference(input, from: rate, to: 48000)
        expect(!samples.isEmpty && samples.count <= expected.count, "output is covered by source")
        expect(samples == Array(expected.prefix(samples.count)),
               "streaming waveform has no duplicated or reordered source")
        converter.resetForGenerationTransition()
        let reset = try converter.convert(buffer(waveform(Int(rate / 100)), rate: rate),
                                          hostTimeNanoseconds: anchor + 1_000_000_000, sampleTime: 0)
        expect(reset.hostTimeNanoseconds == anchor + 1_000_000_000, "reset starts a new content cursor")
    }

    private static func clockBoundary(rate: Double, scenario: String) throws {
        cases += 1
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
        let size = Int(rate / 100)
        if scenario == "reset" {
            _ = try converter.convert(buffer(waveform(size), rate: rate), hostTimeNanoseconds: nil)
            converter.resetForGenerationTransition()
        }
        for index in 0 ..< 4 {
            let timestamp = clockTimestamp(rate: rate, size: size, index: index, scenario: scenario)
            let sampleTime: Int64?
            switch scenario {
            case "sample-gap": sampleTime = Int64(index * size + (index > 0 ? 1 : 0))
            case "host-jump-with-sample-time": sampleTime = Int64(index * size)
            default: sampleTime = nil
            }
            let out = try converter.convert(buffer(waveform(size), rate: rate),
                                            hostTimeNanoseconds: timestamp, sampleTime: sampleTime)
            let valid = scenario == "jitter" || scenario == "reset"
                || (index == 0 && scenario != "missing-start")
            expect((out.hostTimeNanoseconds != nil) == valid, "invalid content clock remains rejected until reset")
        }
    }

    private static func clockTimestamp(rate: Double, size: Int, index: Int, scenario: String) -> UInt64? {
        let timestamp = time(index * size, rate: rate)
        guard index > 0 else { return scenario == "missing-start" ? nil : timestamp }
        switch scenario {
        case "missing-middle": return index == 1 ? nil : timestamp
        case "forward", "host-jump-with-sample-time": return timestamp + 50_000_000
        case "backward": return timestamp - 5_000_000
        case "jitter": return timestamp + 100
        default: return timestamp
        }
    }

    private static func delivery(rate: Double) throws {
        cases += 1
        let input = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
        let output = try MacSpeechAudioConverter(inputFormat: format(48000))
        let host = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)
        expect(host.configure() == .appleVoiceProcessing, "Apple profile configured without WebRTC")
        let frames = MacSpeechAudioFrameBuffer()
        frames.begin(generation: 1)
        let size = Int(rate / 100)
        let source = waveform(size * 20)
        var nativePackets: [MacSpeechPCM16Packet] = []
        for index in 0 ..< 20 {
            let out = try input.convert(
                buffer(Array(source[index * size ..< (index + 1) * size]), rate: rate),
                hostTimeNanoseconds: time(index * size, rate: rate), sampleTime: Int64(index * size)
            )
            guard let timestamp = out.hostTimeNanoseconds else { continue }
            let spans = host.processCaptureSpans(out.samples, hostTimeNanoseconds: timestamp)
            let packets = try output.convert(captureSpans: spans, requiresContinuousContentTime: true)
            nativePackets += packets
            for packet in packets {
                expect(packet.bytes.count == 960, "formal packet is 480 mono PCM16 LE samples")
                expect(packet.activityEvidenceKind == .none, "mechanical PCM grants no Apple activity authority")
                expect(packet.contentTimestampNanoseconds != nil, "packet retains content time")
                frames.append(pcm16Bytes: packet.bytes, activity: packet.activity, generation: 1,
                              timestamp: packet.contentTimestampNanoseconds!)
            }
        }
        let delivered = frames.drain(maxCount: 25)
        expect(!delivered.isEmpty && delivered.count == nativePackets.count, "packets delivered once")
        for (index, frame) in delivered.enumerated() {
            expect(frame.sequenceNumber == UInt64(index + 1), "packet sequence is ordered")
            expect(frame.monotonicTimestampNanoseconds == anchor + UInt64(index) * 20_000_000,
                   "packet start is first sample, not final observation")
        }
        let firstStage = try reference(source, from: rate, to: 48000)
        let expected = try reference(firstStage, from: 48000, to: 24000)
        let bytes = delivered.reduce(into: Data()) { $0.append($1.pcm16Bytes) }
        expect(bytes == MacSpeechPCM16Encoder.encode(samples: Array(expected.prefix(bytes.count / 2))),
               "both conversions preserve the reference waveform prefix")
        frames.end(generation: 1)
        frames.begin(generation: 2)
        expect(!frames.append(pcm16Bytes: Data(repeating: 1, count: 960), activity: 1, generation: 1),
               "old generation cannot enter new buffer")
        expect(frames.drain(maxCount: 25).isEmpty, "reset does not replay old packets")
    }

    private static func packetTimeAndReset() throws {
        cases += 1
        let converter = try MacSpeechAudioConverter(inputFormat: format(48000))
        let chunk = buffer(waveform(960), rate: 48000)
        let unknown = try converter.convert(chunk, requireContentTime: true)
        expect(unknown.isEmpty, "missing time cannot produce valid silence or packets")
        let stillUnknown = try converter.convert(
            chunk, contentTimestampNanoseconds: anchor, requireContentTime: true
        )
        expect(stillUnknown.isEmpty, "bad timeline does not recover by relabelling later PCM")
        converter.resetForGenerationTransition()
        let first = try converter.convert(chunk, contentTimestampNanoseconds: anchor, requireContentTime: true)
        let next = try converter.convert(
            chunk, contentTimestampNanoseconds: anchor + 20_000_000, requireContentTime: true
        )
        let packets = first + next
        expect(!packets.isEmpty && packets[0].contentTimestampNanoseconds == anchor,
               "24k reset anchors first packet")
        let gap = try converter.convert(
            chunk, contentTimestampNanoseconds: anchor + 80_000_000, requireContentTime: true
        )
        expect(gap.isEmpty, "24k discontinuity drops pending packet instead of mixing time ranges")
    }

    private static func gatedSpanCompatibility() throws {
        cases += 1
        let legacy = try MacSpeechAudioConverter(inputFormat: format(48000))
        let strict = try MacSpeechAudioConverter(inputFormat: format(48000))
        let observations = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)
        _ = observations.configure()
        var legacyPackets = 0
        for index in 0 ..< 4 {
            let timestamp = anchor + UInt64(index) * 100_000_000
            let spans = observations.processCaptureSpans(waveform(1920), hostTimeNanoseconds: timestamp)
            let retained = try legacy.convert(captureSpans: spans)
            legacyPackets += retained.count
            if index > 0 {
                expect(!retained.isEmpty, "legacy Gate gaps do not poison subsequent source delivery")
            }
            let rejected = try strict.convert(captureSpans: spans, requiresContinuousContentTime: true)
            if index > 0 {
                expect(rejected.isEmpty, "Apple continuous stream rejects the same gap")
            }
        }
        expect(legacyPackets > 0, "Cascaded retains original segmented conversion")
    }

    private static func processingState() throws {
        cases += 1
        let native = MacSpeechNativeInputFormat(sampleRate: 48000, channelCount: 1)
        for bad in 0 ..< 5 {
            let value = MacSpeechVoiceProcessingSnapshot(
                mode: .appleVoiceProcessing, configurationID: 1,
                inputEnabled: bad != 0, outputEnabled: bad != 1,
                bypassed: bad == 2, inputMuted: false, automaticGainControlEnabled: bad != 3,
                inputFormat: native, outputFormat: native, validatedAtNanoseconds: 1
            )
            expect(value.hasValidAppleProcessing == (bad == 4),
                   "both VP flags, bypass and actual AGC are required")
        }
        let engine = SystemMacSpeechVoiceProcessingEngine()
        try engine.selectProcessingMode(.appleVoiceProcessing)
        expect(
            engine.voiceProcessingSnapshot() == nil,
            "selection alone does not configure hardware or claim VP enabled"
        )
        try engine.selectProcessingMode(.webRTCAEC3)
        expect(engine.voiceProcessingSnapshot() == nil, "idle route switch creates no parallel audio engine")
    }

    private static func invalidTimestamp() throws {
        cases += 1
        let input = try MacSpeechFloatMono48kConverter(inputFormat: format(48000))
        let data = buffer(waveform(960), rate: 48000)
        let invalid = try input.convert(data, hostTimeNanoseconds: .max, sampleTime: 0)
        expect(invalid.hostTimeNanoseconds == nil, "unrepresentable host time cannot trap or become valid")
        let output = try MacSpeechAudioConverter(inputFormat: format(48000))
        let packets = try output.convert(data, contentTimestampNanoseconds: .max, requireContentTime: true)
        expect(packets.isEmpty, "invalid packet timestamp fails closed without integer overflow")
    }

    private static func capacity() throws {
        cases += 1
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: format(48000))
        do {
            _ = try converter.convert(buffer(waveform(16385), rate: 48000), hostTimeNanoseconds: anchor)
            expect(false, "oversize input is rejected, never silently truncated")
        } catch MacSpeechAudioCaptureError.conversionFailed {
            expect(true, "bounded converter rejects oversize")
        }
        let frames = MacSpeechAudioFrameBuffer()
        frames.begin(generation: 1)
        for index in 0 ..< 30 {
            frames.append(pcm16Bytes: Data(repeating: UInt8(index), count: 960),
                          activity: 0, generation: 1, timestamp: anchor + UInt64(index) * 20_000_000)
        }
        expect(frames.stats().queuedCount == 25, "formal queue remains bounded")
        expect(frames.stats().droppedCount == 5, "overflow is reported, never hidden")
    }
}

#if DEBUG
    private extension ConverterTimelineTests {
        static func diagnosticMode() throws -> Bool {
            let arguments = CommandLine.arguments.dropFirst()
            if arguments.elementsEqual(["--d1-stats-only"]) {
                NativeVoiceDebugStatsTests.run()
                return true
            }
            guard arguments.elementsEqual(["--m08-clock-only"]) else { return false }
            try streaming(rate: 16000)
            try CaptureContentClockReproduction.run()
            for fault in ["sample-gap", "sample-backward", "missing-host", "missing-sample"] {
                try driftThenFault(rate: 16000, fault: fault)
            }
            try packetTimeAndReset()
            try delivery(rate: 16000)
            try capacity()
            try invalidTimestamp()
            NativeVoiceDebugStatsTests.run()
            print("m08_existing_clock_cases=\(cases); checks=\(checks)")
            print("m08_device_access=ZERO")
            return true
        }
    }
#endif

private extension ConverterTimelineTests {
    static func longClock(rate: Double, driftAtBoundary: Double) throws {
        cases += 1
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
        let size = Int(rate / 10)
        let chunk = buffer(waveform(size), rate: rate)
        var outputSamples = 0
        for index in 0 ..< 300 {
            let elapsed = Double(index) / 10
            let drift = driftAtBoundary * elapsed / 14.8
            let timestamp = UInt64((Double(time(index * size, rate: rate)) + drift).rounded())
            let converted = try converter.convert(
                chunk, hostTimeNanoseconds: timestamp, sampleTime: Int64(index * size)
            )
            let expected = time(outputSamples, rate: 48000)
            expect(converted.hostTimeNanoseconds.map { abs(Double($0) - Double(expected)) <= 1 } == true,
                   "continuous source cursor survives thirty seconds of bounded hardware clock drift")
            outputSamples += converted.samples.count
        }
        expect(outputSamples > 29 * 48000, "long conversion retains the source through the drift boundary")
    }

    static func driftThenFault(rate: Double, fault: String) throws {
        cases += 1
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: format(rate))
        let size = Int(rate / 10)
        let chunk = buffer(waveform(size), rate: rate)
        for index in 0 ..< 180 {
            let nominal = time(index * size, rate: rate)
            var timestamp: UInt64? = nominal - UInt64((Double(index) * 62667 / 148).rounded())
            var sample: Int64? = Int64(index * size)
            if index >= 170 {
                switch fault {
                case "sample-gap": sample! += 1
                case "sample-backward": sample! -= Int64(size * 2)
                case "host-jump": timestamp! += 50_000_000
                case "host-backward": timestamp! -= 200_000_000
                case "missing-host": timestamp = nil
                case "missing-sample": sample = nil
                default: timestamp! += UInt64(ceil(1_000_000_000 / rate)) + 1000
                }
            }
            let converted = try converter.convert(chunk, hostTimeNanoseconds: timestamp, sampleTime: sample)
            expect((converted.hostTimeNanoseconds != nil) == (index < 170),
                   "real discontinuity after valid drift latches invalid until generation reset")
        }
        converter.resetForGenerationTransition()
        let restarted = try converter.convert(chunk, hostTimeNanoseconds: anchor, sampleTime: 0)
        expect(restarted.hostTimeNanoseconds == anchor, "generation reset clears the prior invalid clock")
    }

    static func format(_ rate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                      channels: 1, interleaved: false)!
    }

    static func buffer(_ samples: [Float], rate: Double) -> AVAudioPCMBuffer {
        let result = AVAudioPCMBuffer(pcmFormat: format(rate),
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        result.frameLength = AVAudioFrameCount(samples.count)
        result.floatChannelData![0].update(from: samples, count: samples.count)
        return result
    }

    static func time(_ sample: Int, rate: Double) -> UInt64 {
        anchor + UInt64((Double(sample) * 1_000_000_000 / rate).rounded())
    }

    static func waveform(_ count: Int) -> [Float] {
        (0 ..< count).map { Float(sin(Double($0) * 0.017) * 0.3) }
    }

    static func reference(_ samples: [Float], from inputRate: Double, to outputRate: Double) throws -> [Float] {
        let converter = AVAudioConverter(from: format(inputRate), to: format(outputRate))!
        converter.channelMap = [0]
        let input = ReferenceInput(buffer(samples, rate: inputRate))
        let capacity = AVAudioFrameCount(ceil(Double(samples.count) * outputRate / inputRate) + 1024)
        let output = AVAudioPCMBuffer(pcmFormat: format(outputRate), frameCapacity: capacity)!
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard let source = input.buffer else {
                state.pointee = .endOfStream
                return nil
            }
            input.buffer = nil
            state.pointee = .haveData
            return source
        }
        expect(error == nil && status != .error, "one-shot reference converts")
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0],
                                         count: Int(output.frameLength)))
    }
}
