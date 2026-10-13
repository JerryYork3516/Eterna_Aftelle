import AVFoundation
import Foundation

final class TestAEC: MacSpeechAECBackend, @unchecked Sendable {
    var operations: [String] = []
    var failCapture = false
    var real: (any MacSpeechAECBackend)?
    var linearOutputDelaySamples: Int {
        real?.linearOutputDelaySamples ?? 0
    }

    var processedOutputDelaySamples: Int {
        real?.processedOutputDelaySamples ?? 0
    }

    func configure() throws {
        operations.append("configure")
        try real?.configure()
    }

    func processRender(_ samples: [Float]) throws {
        operations.append("render")
        try real?.processRender(samples)
    }

    func processCapture(_ samples: [Float]) throws -> MacSpeechAECCaptureResult {
        operations.append("capture")
        if failCapture {
            throw MacSpeechAECBackendError.captureFailed
        }
        if let real {
            return try real.processCapture(samples)
        }
        return .init(
            processedSamples: samples.map { $0 * 0.5 },
            linearOutputSamples: stride(from: 0, to: samples.count, by: 3).map { samples[$0] * 0.5 }
        )
    }

    func setDelay(milliseconds: Int) throws {
        operations.append("delay:\(milliseconds)")
        try real?.setDelay(milliseconds: milliseconds)
    }

    func reset() throws {
        operations.append("reset")
        try real?.reset()
    }

    func stats() throws -> MacSpeechAECBackendStats {
        if let real {
            return try real.stats()
        }
        return .init(
            enabled: true, active: true, estimatedDelayMilliseconds: 0,
            erlDecibels: 12, erleDecibels: 24
        )
    }
}

final class NoDeviceVAD: MacSpeechVoiceActivityDetecting, @unchecked Sendable {
    func start() -> Bool {
        fatalError("device access prohibited")
    }

    func stop() {}
    func voiceActivityState(at _: UInt64?) -> Bool? {
        fatalError("device access prohibited")
    }
}

struct HostFixtureResult {
    let pcm: Data
    let observations: [MacSpeechAcousticObservationSnapshot]
    let operations: [String]
}

extension AudioObservationTests {
    static func buffer(rate: Double, count: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate,
            channels: 1, interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for index in 0 ..< count {
            buffer.floatChannelData![0][index] = Float(sin(Double(index) * 0.07) * 0.2)
        }
        return buffer
    }

    static func hostFixture(real: Bool = false) -> HostFixtureResult {
        let backend = TestAEC()
        #if AFTELLE_WEBRTC_AEC3
            if real {
                backend.real = MacSpeechWebRTCAECProcessor()
            }
        #endif
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
        _ = host.configure()
        host.playbackStarted()
        var pcm = Data()
        var observations: [MacSpeechAcousticObservationSnapshot] = []
        for batch in 0 ..< 12 {
            let count = batch.isMultiple(of: 2) ? 480 : 4800
            let signal = (0 ..< count).map { Float(sin(Double($0 + batch * 17) * 0.09) * 0.1) }
            let time = UInt64(1_000_000_000 + batch * 100_000_000)
            host.processRender(signal, hostTimeNanoseconds: time)
            let spans = host.processCaptureSpans(signal, hostTimeNanoseconds: time + 80_000_000)
            for span in spans {
                pcm.append(MacSpeechPCM16Encoder.encode(samples: span.samples))
                observations.append(span.observation)
            }
        }
        host.discardPendingCaptureForGenerationTransition()
        host.routeWillRebuild()
        _ = host.routeDidRebuild()
        host.playbackStopped()
        return HostFixtureResult(pcm: pcm, observations: observations, operations: backend.operations)
    }

    static func converterFixture(rate: Double) throws -> [MacSpeechFloatMono48kConverter.Output] {
        let initial = buffer(rate: rate, count: Int(rate / 100))
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: initial.format)
        var results: [MacSpeechFloatMono48kConverter.Output] = []
        var cursor: Int64 = 0
        for divisor in [100, 10, 100, 10] {
            let input = buffer(rate: rate, count: Int(rate / Double(divisor)))
            let time = AVAudioTime(
                hostTime: AVAudioTime.hostTime(forSeconds: 1 + Double(cursor) / rate),
                sampleTime: cursor, atRate: rate
            )
            let callback = recorder.beginNativeCallback(input, when: time, stream: 1, generation: 9)
            try results.append(converter.convert(
                input, hostTimeNanoseconds: 1_000_000_000 + UInt64(Double(cursor) / rate * 1e9),
                sampleTime: cursor
            ))
            recorder.finish(callback)
            cursor += Int64(input.frameLength)
        }
        return results
    }

    static func checkNativeConverterRecords(_ records: [MacSpeechAudioObservationEvent]) {
        let native = records.filter { $0.kind == 1 }
        expect(
            native.contains { Double(bitPattern: $0.sampleRate) == 44100 }, "44.1k content clock"
        )
        expect(native.contains { Double(bitPattern: $0.sampleRate) == 48000 }, "48k content clock")
        expect(
            native.contains { $0.flags & 1 == 0 && $0.status == 1 },
            "missing native host time preserved"
        )
        expect(
            native.contains { $0.flags & 2 == 0 && $0.status == 2 }, "missing sampleTime preserved"
        )
        expect(
            records.contains { $0.kind == 6 && $0.status == 4 && $0.generation == 8 },
            "fence rejection retains generation"
        )
        let conversions = records.filter { $0.kind == 2 }
        expect(
            conversions.contains { $0.status == 3 },
            "converter failure recorded without changing fallback"
        )
        expect(
            conversions.contains { $0.status == 1 && $0.reserved != 0 },
            "missing converted time retains its reason"
        )
        expect(
            conversions.allSatisfy {
                $0.inputEnd >= $0.inputStart && $0.outputEnd >= $0.outputStart
            }, "converter cursors"
        )
        expect(
            conversions.contains {
                $0.inputEnd - $0.inputStart == 4410 && $0.outputEnd - $0.outputStart == 4800
            }, "actual 4410 to 4800 conversion"
        )
        for call in records.filter({ $0.kind == 3 }) {
            let ancestors = native.filter {
                $0.thread == call.thread && $0.entered <= call.entered
                    && call.completed <= $0.completed
            }
            expect(
                ancestors.count == 1, "exact native callback ancestry by same-thread call nesting"
            )
        }
    }
}
