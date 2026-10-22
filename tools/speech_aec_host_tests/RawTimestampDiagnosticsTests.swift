@preconcurrency import AVFoundation
import Foundation

@main
@MainActor
enum RawTimestampDiagnosticsTests {
    private static var cases = 0
    private static var checks = 0

    static func main() throws {
        normalClock()
        try hostFaultWindow()
        earlySealAndContentFault()
        try flagsAndRateScalar()
        identityAndGeneration()
        try converterParity(sampleGap: false)
        try converterParity(sampleGap: true)
        concurrentSnapshots()
        print("m09_timestamp_cases=\(cases); checks=\(checks); device_access=ZERO")
        print("m09_window_bytes=\(MemoryLayout<MacSpeechRawTimestampDiagnostic>.stride); capacity=5")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { print("m09_FAIL: \(message)"); exit(1) }
    }

    nonisolated static func stats(generation: UInt64 = 7) -> MacSpeechNativeVoiceDebugStats {
        var stats = MacSpeechNativeVoiceDebugStats(runID: UUID(), generation: generation)
        let native = MacSpeechNativeInputFormat(sampleRate: 16000, channelCount: 3)
        stats.bind(configurationID: 3, voiceProcessing: MacSpeechVoiceProcessingSnapshot(
            mode: .appleVoiceProcessing, configurationID: 3,
            inputEnabled: true, outputEnabled: true, bypassed: false, inputMuted: false,
            automaticGainControlEnabled: true, inputFormat: native, outputFormat: native,
            validatedAtNanoseconds: 10_000_000_000
        ))
        return stats
    }

    nonisolated static func buffer() -> AVAudioPCMBuffer {
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3)!
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   interleaved: false, channelLayout: layout)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
        buffer.frameLength = 320
        for channel in 0 ..< 3 {
            for frame in 0 ..< 320 {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 0.07) * 0.25)
            }
        }
        return buffer
    }

    nonisolated static func time(
        index: Int, offset: UInt64 = 0, sampleGap: Int64 = 0,
        flags: AudioTimeStampFlags = [.hostTimeValid, .sampleTimeValid, .rateScalarValid], scalar: Double = 1
    ) -> AVAudioTime {
        var stamp = AudioTimeStamp()
        stamp.mHostTime = AVAudioTime
            .hostTime(forSeconds: Double(10_000_000_000 + UInt64(index) * 20_000_000 + offset) / 1e9)
        stamp.mSampleTime = Double(index * 320) + Double(sampleGap)
        stamp.mRateScalar = scalar
        stamp.mWordClockTime = 1234
        stamp.mSMPTETime.mCounter = 56
        stamp.mSMPTETime.mHours = 1
        stamp.mFlags = flags
        return AVAudioTime(audioTimeStamp: &stamp, sampleRate: 16000)
    }

    nonisolated static func observe(
        _ stats: inout MacSpeechNativeVoiceDebugStats, buffer: AVAudioPCMBuffer, time: AVAudioTime,
        enabled: Bool = true, generation: UInt64 = 7, configuration: UInt64 = 3
    ) {
        let host = time
            .isHostTimeValid ? UInt64((AVAudioTime.seconds(forHostTime: time.hostTime) * 1e9).rounded()) : nil
        let sample = time.isSampleTimeValid ? time.sampleTime : nil
        if enabled {
            stats.recordRawTimestamp(buffer, time: time, content: (host, sample),
                                     arrival: 12_000_000_000 + UInt64(max(0, time.sampleTime)) * 62500,
                                     identity: (configuration, generation))
        }
        stats.recordNative(buffer, hostTimeNanoseconds: host, sampleTime: sample,
                           configurationID: configuration, generation: generation)
    }

    private static func normalClock() {
        cases += 1
        var stats = stats()
        let buffer = buffer()
        for index in 0 ..< 2000 {
            observe(&stats, buffer: buffer, time: time(index: index))
        }
        expect(stats.snapshot.rawTimestampDiagnostic == nil, "continuous clocks export no anomaly")
        expect(stats.snapshot.rejections.values.allSatisfy { $0 == 0 }, "diagnostics add no clock rejection")
        expect(stats.snapshot.nativeBufferCount == 2000, "fixed storage does not cap normal processing")
        expect(MemoryLayout<MacSpeechRawTimestampDiagnostic>.stride < 2048, "five witnesses use bounded value storage")
    }

    private static func hostFaultWindow() throws {
        cases += 1
        var stats = stats()
        let buffer = buffer()
        for index in 0 ..< 5 {
            observe(&stats, buffer: buffer, time: time(index: index, offset: index == 4 ? 2_182_375 : 0))
        }
        let frozen = stats.snapshot.rawTimestampDiagnostic!
        expect(frozen.fault == .nativeClock, "actual native_clock rejection marks the fault")
        expect(stats.snapshot.rejections["native_clock"] == 1, "original rejection count stays exact")
        expect(frozen.previous2?.samplePosition == 640 && frozen.previous1?.samplePosition == 960,
               "exactly the preceding two callbacks remain")
        expect(frozen.current?.samplePosition == 1280 && frozen.following1 == nil, "anomaly callback is current")
        for index in 5 ..< 20 {
            observe(&stats, buffer: buffer, time: time(index: index))
        }
        let window = stats.snapshot.rawTimestampDiagnostic!
        expect(window.following1?.samplePosition == 1600 && window.following2?.samplePosition == 1920,
               "only the first two following callbacks remain")
        expect(window.current == frozen.current && frozen.following1 == nil, "snapshot value copies remain stable")
        expect(
            window.current?.timestamp.mFlags == [.hostTimeValid, .sampleTimeValid, .rateScalarValid],
            "raw flags preserved"
        )
        expect(window.current?.timestamp.mWordClockTime == 1234
            && window.current?.timestamp.mSMPTETime.mCounter == 56, "whole timestamp includes word/SMPTE fields")
        expect(window.current?.timestampSampleRate == 16000 && window.current?.bufferFormat.mChannelsPerFrame == 3,
               "timestamp rate and actual buffer ASBD remain distinct")
        let snapshot = stats.snapshot
        let json = window.manifest(runID: snapshot.runID, generation: snapshot.captureGeneration,
                                   configurationID: snapshot.configurationID, sealed: snapshot.isSealed)
        let rows = json["callbacks"] as? [[String: Any]] ?? []
        expect(
            rows.count == 5 && rows.compactMap { $0["relative_callback"] as? Int } == [-2, -1, 0, 1, 2],
            "fixed offsets exported"
        )
        expect(
            abs((rows[2]["host_delta_ns"] as? Double ?? .infinity) - 22_182_375) < 2,
            "actual adjacent host delta exported"
        )
        expect(rows[2]["expected_host_delta_ns"] as? Double == 20_000_000
            && rows[2]["sample_delta_frames"] as? Double == 320, "expected and sample deltas are separate")
        expect(json["run_id"] as? String == snapshot.runID.uuidString && json["generation"] as? UInt64 == 7,
               "export identity comes from the same immutable snapshot")
        expect(JSONSerialization.isValidJSONObject(json), "all metadata is JSON safe")
        _ = try JSONSerialization.data(withJSONObject: json)
    }

    private static func earlySealAndContentFault() {
        cases += 1
        var stats = stats()
        let buffer = buffer()
        observe(&stats, buffer: buffer, time: time(index: 0))
        stats.reject("content_time")
        let original = stats.snapshot.rawTimestampDiagnostic!
        expect(original.fault == .contentTime && original.previous1 == nil, "early anomaly needs no fabricated history")
        stats.seal(reason: "capture_stopped")
        observe(&stats, buffer: buffer, time: time(index: 1))
        expect(stats.snapshot.rawTimestampDiagnostic == original, "seal prevents further metadata writes")
        let json = original.manifest(runID: stats.runID, generation: 7, configurationID: 3, sealed: true)
        expect(json["following_status"] as? String == "unavailable_after_seal", "missing following data is explicit")
        expect((json["callbacks"] as? [[String: Any]] ?? []).count == 1, "shutdown does not synthesize callbacks")
    }

    private static func flagsAndRateScalar() throws {
        cases += 1
        let buffer = buffer()
        for flags: AudioTimeStampFlags in [[.sampleTimeValid], [.hostTimeValid], []] {
            var stats = stats()
            observe(&stats, buffer: buffer, time: time(index: 0, flags: flags))
            let witness = stats.snapshot.rawTimestampDiagnostic!
            expect(witness.current?.timestamp.mFlags == flags, "missing raw validity flags remain missing")
            expect(
                witness.fault == (flags.contains(.hostTimeValid) ? .nativeClock : .missingHostTime),
                "missing clocks remain rejected"
            )
        }
        for scalar in [Double.nan, .infinity, 0, -1, 1.02182375] {
            for validFlag in [false, true] {
                var stats = stats()
                let flags: AudioTimeStampFlags = validFlag ? [.hostTimeValid, .sampleTimeValid, .rateScalarValid]
                    : [.hostTimeValid, .sampleTimeValid]
                observe(&stats, buffer: buffer, time: time(index: 0, flags: flags, scalar: scalar))
                expect(
                    stats.snapshot.rawTimestampDiagnostic == nil,
                    "scalar does not create observedOutput new clock rule"
                )
                stats.reject("content_time")
                let witness = stats.snapshot.rawTimestampDiagnostic!
                expect(
                    witness.current?.timestamp.mRateScalar.bitPattern == scalar.bitPattern,
                    "invalid scalar bits retained losslessly"
                )
                let json = witness.manifest(runID: stats.runID, generation: 7, configurationID: 3, sealed: false)
                let row = (json["callbacks"] as? [[String: Any]] ?? [])[0]
                expect(
                    row["rate_scalar_valid"] as? Bool == (validFlag && scalar.isFinite && scalar > 0),
                    "only flagged finite positive scalar is valid"
                )
                expect(JSONSerialization.isValidJSONObject(json), "invalid raw floats cannot break evidence export")
                _ = try JSONSerialization.data(withJSONObject: json)
            }
        }
    }

    private static func identityAndGeneration() {
        cases += 1
        var stats = stats()
        let buffer = buffer()
        observe(&stats, buffer: buffer, time: time(index: 0))
        let before = stats.snapshot
        let stamp = time(index: 99)
        for (configuration, generation): (UInt64, UInt64) in [(3, 6), (4, 7)] {
            stats.recordRawTimestamp(buffer, time: stamp, content: (nil, 99),
                                     arrival: 1, identity: (configuration, generation))
        }
        expect(stats.snapshot == before, "stale metadata changes neither window nor original rejection counts")
        observe(&stats, buffer: buffer, time: time(index: 1, sampleGap: 1))
        expect(stats.snapshot.rawTimestampDiagnostic?.current?.samplePosition == 321, "sample discontinuity captured")
        expect(stats.snapshot.rejections["native_clock"] == 1, "real sample discontinuity still rejected")
        var rebuilt = Self.stats(generation: 8)
        observe(&rebuilt, buffer: buffer, time: time(index: 0), generation: 8)
        expect(
            rebuilt.runID != stats.runID && rebuilt.snapshot.rawTimestampDiagnostic == nil,
            "new run/generation clears prior anomaly"
        )
        expect(
            rebuilt.snapshot.rejections.values.allSatisfy { $0 == 0 },
            "generation restart retains no prior rejection"
        )
    }
}

private extension RawTimestampDiagnosticsTests {
    static func converterParity(sampleGap: Bool) throws {
        cases += 1
        let buffer = buffer()
        let observed = try MacSpeechFloatMono48kConverter(inputFormat: buffer.format)
        let unobserved = try MacSpeechFloatMono48kConverter(inputFormat: buffer.format)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let observedPCM = try MacSpeechAudioConverter(inputFormat: outputFormat)
        let unobservedPCM = try MacSpeechAudioConverter(inputFormat: outputFormat)
        var enabledStats = stats(), disabledStats = stats()
        for index in 0 ..< 12 {
            let stamp = time(index: index, offset: !sampleGap && index == 5 ? 2_182_375 : 0,
                             sampleGap: sampleGap && index >= 5 ? 320 : 0)
            observe(&enabledStats, buffer: buffer, time: stamp)
            observe(&disabledStats, buffer: buffer, time: stamp, enabled: false)
            let host = UInt64((AVAudioTime.seconds(forHostTime: stamp.hostTime) * 1e9).rounded())
            let observedOutput = try observed.convert(buffer, hostTimeNanoseconds: host, sampleTime: stamp.sampleTime)
            let unobservedOutput = try unobserved.convert(
                buffer,
                hostTimeNanoseconds: host,
                sampleTime: stamp.sampleTime
            )
            expect(
                observedOutput.samples == unobservedOutput.samples && observedOutput
                    .hostTimeNanoseconds == unobservedOutput.hostTimeNanoseconds,
                "observation never changes Float32 values/order or rejection"
            )
            expect(
                (observedOutput.hostTimeNanoseconds != nil) == (index < 5),
                "both faults retain existing fail-closed latch"
            )
            if let timestamp = observedOutput.hostTimeNanoseconds {
                try assertPCMParity(observedOutput.samples, unobservedOutput.samples,
                                    timestamp: timestamp, converters: (observedPCM, unobservedPCM))
            }
        }
        expect(
            enabledStats.snapshot.rejections == disabledStats.snapshot.rejections,
            "all Native rejection counts match with diagnostics disabled"
        )
        expect(
            enabledStats.snapshot.channels == disabledStats.snapshot.channels && enabledStats.snapshot
                .nativeFrameCount == disabledStats.snapshot.nativeFrameCount,
            "Native sample statistics match with diagnostics disabled"
        )
        expect(
            enabledStats.snapshot.rawTimestampDiagnostic != nil && disabledStats.snapshot.rawTimestampDiagnostic == nil,
            "only diagnostic evidence differs"
        )
        try assertResetParity(observed, unobserved, buffer: buffer)
    }

    static func assertResetParity(
        _ observed: MacSpeechFloatMono48kConverter, _ unobserved: MacSpeechFloatMono48kConverter,
        buffer: AVAudioPCMBuffer
    ) throws {
        observed.resetForGenerationTransition()
        unobserved.resetForGenerationTransition()
        let observedOutput = try observed.convert(buffer, hostTimeNanoseconds: 10_000_000_000, sampleTime: 0)
        let unobservedOutput = try unobserved.convert(buffer, hostTimeNanoseconds: 10_000_000_000, sampleTime: 0)
        expect(
            observedOutput.hostTimeNanoseconds == 10_000_000_000 && observedOutput.samples == unobservedOutput.samples,
            "existing generation reset recovers both paths"
        )
    }

    static func assertPCMParity(
        _ observed: [Float], _ unobserved: [Float], timestamp: UInt64,
        converters: (MacSpeechAudioConverter, MacSpeechAudioConverter)
    ) throws {
        let observedPackets = try converters.0.convert(
            MacSpeechFloatMono48kConverter.makeBuffer(samples: observed),
            contentTimestampNanoseconds: timestamp, requireContentTime: true
        )
        let unobservedPackets = try converters.1.convert(
            MacSpeechFloatMono48kConverter.makeBuffer(samples: unobserved),
            contentTimestampNanoseconds: timestamp, requireContentTime: true
        )
        expect(observedPackets.map(\.bytes) == unobservedPackets.map(\.bytes),
               "retained PCM bytes are identical with observation enabled/disabled")
    }

    static func concurrentSnapshots() {
        cases += 1
        let locked = LockedTimestampStats()
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            if index == 0 {
                locked.writeCallbacks()
            } else {
                locked.readSnapshot()
            }
        }
        expect(locked.valid, "existing owner-lock model keeps concurrent snapshot copies consistent")
        expect(locked.snapshot.rawTimestampDiagnostic?.isComplete == true, "writer completes the bounded window")
    }
}

private final class LockedTimestampStats: @unchecked Sendable {
    private let lock = NSLock()
    private var stats = RawTimestampDiagnosticsTests.stats()
    private var readsValid = true

    func writeCallbacks() {
        let buffer = RawTimestampDiagnosticsTests.buffer()
        for index in 0 ..< 200 {
            lock.withLock {
                RawTimestampDiagnosticsTests.observe(&stats, buffer: buffer,
                                                     time: RawTimestampDiagnosticsTests.time(
                                                         index: index,
                                                         offset: index == 4 ? 2_182_375 : 0
                                                     ))
            }
        }
    }

    func readSnapshot() {
        lock.withLock {
            let snapshot = stats.snapshot
            readsValid = readsValid && snapshot.captureGeneration == 7 && snapshot.configurationID == 3
            if let window = snapshot.rawTimestampDiagnostic {
                readsValid = readsValid && window.current?.samplePosition == 1280
            }
        }
    }

    var valid: Bool {
        lock.withLock { readsValid }
    }

    var snapshot: MacSpeechNativeVoiceDebugSnapshot {
        lock.withLock { stats.snapshot }
    }
}
