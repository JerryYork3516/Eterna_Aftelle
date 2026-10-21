@preconcurrency import AVFoundation
import Foundation

#if DEBUG
    @MainActor
    enum CaptureContentClockReproduction {
        private static var cases = 0
        private static var checks = 0
        private static let anchor: UInt64 = 10_000_000_000

        static func run() throws {
            for offset: UInt64 in [2_182_375, 2_165_292, 3_239_541] {
                try historicalHostOffset(offset)
            }
            try omittedSourceCallback()
            timestampRepresentations()
            print("m08_reproduction_cases=\(cases); checks=\(checks)")
            print("m08_host_offset_reproduction=3/3; production_fix=NOT_PROVEN")
        }

        private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }

        private static func historicalHostOffset(_ offset: UInt64) throws {
            cases += 1
            let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3)!
            let native = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                       interleaved: false, channelLayout: layout)
            let actual = try MacSpeechFloatMono48kConverter(inputFormat: native)
            let reference = try MacSpeechFloatMono48kConverter(inputFormat: native)
            let values = (0 ..< 1600).map { Float(sin(Double($0) * 0.017) * 0.3) }
            let chunk = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: 1600)!
            chunk.frameLength = 1600
            for channel in 0 ..< 3 {
                chunk.floatChannelData![channel].update(from: values, count: values.count)
            }
            for index in 0 ..< 12 {
                let nominal = anchor + UInt64(index) * 100_000_000
                // Only the observed magnitude is reused; this is not a recorded callback replay.
                let host = nominal + (index == 7 ? offset : 0)
                let sample = Int64(624 + index * 1600)
                let output = try actual.convert(chunk, hostTimeNanoseconds: host, sampleTime: sample)
                let expected = try reference.convert(chunk, hostTimeNanoseconds: nominal, sampleTime: sample)
                expect(!output.samples.isEmpty && output.samples == expected.samples,
                       "known synthetic content stays unchanged despite the host metadata fault")
                expect((output.hostTimeNanoseconds != nil) == (index < 7),
                       "host-only fault rejects content time and remains latched after host intervals recover")
            }
            actual.resetForGenerationTransition()
            reference.resetForGenerationTransition()
            let restarted = try actual.convert(chunk, hostTimeNanoseconds: anchor, sampleTime: 0)
            let fresh = try reference.convert(chunk, hostTimeNanoseconds: anchor, sampleTime: 0)
            expect(restarted.hostTimeNanoseconds == anchor && restarted.samples == fresh.samples,
                   "only the existing generation reset restores the clock without changing samples")
        }

        private static func timestampRepresentations() {
            cases += 1
            let tickNanoseconds = AVAudioTime.seconds(forHostTime: 1) * 1_000_000_000
            for nanoseconds: UInt64 in [10_000_000_000, 1_000_000_000_000_000] {
                let ticks = AVAudioTime.hostTime(forSeconds: Double(nanoseconds) / 1_000_000_000)
                let roundTrip = (AVAudioTime.seconds(forHostTime: ticks) * 1_000_000_000).rounded()
                expect(abs(roundTrip - Double(nanoseconds)) <= ceil(tickNanoseconds) + 1,
                       "host ticks to nanoseconds round within a tick, not milliseconds")
            }
            var timestamp = AudioTimeStamp()
            timestamp.mHostTime = AVAudioTime.hostTime(forSeconds: 10)
            timestamp.mSampleTime = 624
            timestamp.mRateScalar = 1.02182375
            timestamp.mFlags = [.sampleTimeValid, .hostTimeValid, .rateScalarValid]
            let time = AVAudioTime(audioTimeStamp: &timestamp, sampleRate: 16000)
            expect(time.isHostTimeValid && time.isSampleTimeValid && time.sampleRate == 16000,
                   "timestamp validity and sample-rate fields have distinct meanings")
            expect(time.audioTimeStamp.mFlags.contains(.rateScalarValid)
                && time.audioTimeStamp.mRateScalar == timestamp.mRateScalar,
                "SDK can carry a valid rate scalar; historical runs did not record it")
        }

        private static func omittedSourceCallback() throws {
            cases += 1
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                       channels: 1, interleaved: false)!
            let converter = try MacSpeechFloatMono48kConverter(inputFormat: format)
            let source = (0 ..< 8000).map { Float($0) / 10000 }
            let sourceCallbacks = [0, 1, 3, 4]
            expect(sourceCallbacks.count * 1600 == source.count - 1600,
                   "fixture really omits 1600 unique source samples, not only a timestamp")
            for (delivered, sourceCallback) in sourceCallbacks.enumerated() {
                let start = sourceCallback * 1600
                let values = Array(source[start ..< (start + 1600)])
                let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
                chunk.frameLength = 1600
                chunk.floatChannelData![0].update(from: values, count: values.count)
                let converted = try converter.convert(
                    chunk, hostTimeNanoseconds: anchor + UInt64(sourceCallback) * 100_000_000,
                    sampleTime: Int64(start)
                )
                expect((converted.hostTimeNanoseconds != nil) == (delivered < 2),
                       "an omitted source callback cannot acquire a fabricated continuous content time")
            }
        }
    }
#endif
