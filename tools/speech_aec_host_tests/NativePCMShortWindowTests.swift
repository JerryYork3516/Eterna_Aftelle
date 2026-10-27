import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

@main
@MainActor
private enum NativePCMShortWindowTests {
    private static let anchor: UInt64 = 10_000_000_000
    private static let identity = MacSpeechRuntimeReadback.Identity(runID: UUID(), generation: 7, configurationID: 3)
    private static var checks = 0

    static func main() throws {
        try testSRCAndBytes()
        testDips()
        try testActualSRCDips()
        testUnknowns()
        try testIdentityAndSeal()
        testCapacityAndCounts()
        testMicrophoneModes()
        testIncrementalCallbackCost()
        print("m19_short_window_checks=\(checks)")
        print("m19_short_window_device_and_system_queries=ZERO")
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }

    private static func pcm(_ value: Float) -> Data {
        MacSpeechPCM16Encoder.encode(samples: Array(repeating: value, count: 480))
    }

    private static func fixture(
        _ values: [Float], native: Bool, srcAligned: Bool = true,
        identity: MacSpeechRuntimeReadback.Identity = identity
    ) -> MacSpeechShortWindowSnapshot {
        var stats = MacSpeechShortWindowStats(source: native ? .native : .pcm)
        for (index, value) in values.enumerated() {
            let start = anchor + UInt64(index) * 20_000_000
            if native {
                stats.record(count: 320, rate: 16000, start: start, srcAligned: srcAligned) { _ in
                    (Double(value), abs(value) >= 1)
                }
            } else {
                stats.recordPCM(pcm(value), start: start)
            }
        }
        return stats.snapshot(identity: identity)
    }

    private static func rows(
        _ native: MacSpeechShortWindowSnapshot, _ pcm: MacSpeechShortWindowSnapshot, trusted: Bool = true
    ) -> [[String: Any]] {
        MacSpeechShortWindowSnapshot.pairedManifest(
            native: native, pcm: pcm, identity: identity, clockTrusted: trusted, savedPCM: true
        )["windows"] as? [[String: Any]] ?? []
    }

    private static func allUnknown(_ rows: [[String: Any]]) -> Bool {
        !rows.isEmpty && rows.allSatisfy { ($0["status"] as? String)?.hasPrefix("UNKNOWN_") == true }
    }

    private static func testDips() {
        for duration in [100, 140, 160] {
            let range = 10 ..< (10 + duration / 20)
            let values = (0 ..< 40).map { range.contains($0) ? Float(0.025) : 0.25 }
            let native = fixture(values, native: true)
            let converted = fixture(values, native: false)
            let paired = rows(native, converted)
            expect(paired.count == 40 && paired.allSatisfy { $0["status"] as? String == "MATCHED_CONTENT_COVERAGE" },
                   "complete 16k/24k intervals pair without comparing their sample indices")
            for stream in [native, converted] {
                let low = stream.windows.filter { ($0.level.rms ?? 1) < 0.125 }
                expect(low.first?.start == anchor + 200_000_000, "known dip starts at the exact content interval")
                expect(low.last?.end == anchor + 200_000_000 + UInt64(duration) * 1_000_000,
                       "100/140/160ms dip ends at the exact interval")
                expect(low.count == duration / 20, "no interpolation or fabricated windows")
            }
            expect(native.windows[0].level.sampleCount == 320 && converted.windows[0].level.sampleCount == 480,
                   "native and final sample counts retain their distinct rates")
        }
    }

    private static func testUnknowns() {
        let values = Array(repeating: Float(0.25), count: 10)
        let native = fixture(values, native: true)
        let converted = fixture(values, native: false)
        expect(allUnknown(rows(native, converted, trusted: false)), "untrusted content clock cannot pair")
        expect(allUnknown(rows(fixture(values, native: true, srcAligned: false), converted)),
               "unverified SRC latency cannot pair")
        let remaining = native.windows.enumerated().filter { $0.offset != 4 }.map(\.element)
        let missing = MacSpeechShortWindowSnapshot(identity: identity, source: .native, sampleRate: 16000,
                                                   srcAligned: true, fault: nil, windows: remaining)
        expect((rows(missing, converted)[4]["status"] as? String)?.hasPrefix("UNKNOWN_") == true,
               "a missing native interval cannot borrow a neighboring window")
        let duplicate = MacSpeechShortWindowSnapshot(
            identity: identity, source: .native, sampleRate: 16000,
            srcAligned: true, fault: nil, windows: native.windows + [native.windows[0]]
        )
        expect(allUnknown(rows(duplicate, converted)), "duplicate or unordered evidence is rejected")
        testInvalidClock(converted)
        let foreign = MacSpeechRuntimeReadback.Identity(runID: UUID(), generation: 7, configurationID: 3)
        expect(allUnknown(rows(fixture(values, native: true, identity: foreign), converted)), "foreign run rejected")
        let changed = MacSpeechRuntimeReadback.Identity(runID: identity.runID, generation: 8, configurationID: 4)
        expect(allUnknown(rows(fixture(values, native: true, identity: changed), converted)),
               "generation/configuration cannot mix")
    }

    private static func testInvalidClock(_ pcm: MacSpeechShortWindowSnapshot) {
        for time in [anchor, anchor + 20_000_001, anchor + 40_000_000] {
            var stats = MacSpeechShortWindowStats(source: .native)
            stats.record(count: 320, rate: 16000, start: anchor, srcAligned: true) { _ in (0.25, false) }
            stats.record(count: 320, rate: 16000, start: time, srcAligned: true) { _ in (0.25, false) }
            expect(allUnknown(rows(stats.snapshot(identity: identity), pcm)),
                   "duplicate, one-nanosecond error and missing interval latch UNKNOWN")
        }
        var partial = MacSpeechShortWindowStats(source: .native)
        partial.record(count: 319, rate: 16000, start: anchor, srcAligned: true) { _ in (0.25, false) }
        expect(allUnknown(rows(partial.snapshot(identity: identity), pcm)), "incomplete coverage never pads a sample")
    }

    private static func buffer(_ offset: Int, dipDuration: Int? = nil) -> AVAudioPCMBuffer {
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3)!
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   interleaved: false, channelLayout: layout)
        let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
        result.frameLength = 1600
        for frame in 0 ..< 1600 {
            let time = Double(offset + frame) / 16000
            let low = dipDuration.map { time >= 1 && time < 1 + Double($0) / 1000 } ?? false
            let amplitude = low ? 0.02 : 0.2
            result.floatChannelData![0][frame] = Float(amplitude * sin(Double(offset + frame) * 2 * .pi * 300 / 16000))
            result.floatChannelData![1][frame] = 0
            result.floatChannelData![2][frame] = 0
        }
        return result
    }

    private static func nativeStats() -> MacSpeechNativeVoiceDebugStats {
        var stats = MacSpeechNativeVoiceDebugStats(runID: identity.runID, generation: identity.generation)
        let format = MacSpeechNativeInputFormat(sampleRate: 16000, channelCount: 3)
        stats.bind(configurationID: identity.configurationID, voiceProcessing: .init(
            mode: .appleVoiceProcessing, configurationID: identity.configurationID,
            inputEnabled: true, outputEnabled: true, bypassed: false, inputMuted: false,
            automaticGainControlEnabled: true, inputFormat: format, outputFormat: format, validatedAtNanoseconds: anchor
        ))
        return stats
    }

    private struct PipelineResult {
        let bytes: Data
        let native: MacSpeechNativeVoiceDebugSnapshot
        let pcm: MacSpeechShortWindowSnapshot
    }

    private static func pipeline(_ enabled: Bool, dipDuration: Int? = nil) throws -> PipelineResult {
        let input = try MacSpeechFloatMono48kConverter(inputFormat: buffer(0).format)
        let mono = try MacSpeechFloatMono48kConverter.makeBuffer(samples: [0]).format
        let output = try MacSpeechAudioConverter(inputFormat: mono)
        let host = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)
        expect(host.configure() == .appleVoiceProcessing, "synthetic post-VP pass-through")
        var stats = nativeStats()
        var final = MacSpeechShortWindowStats(source: .pcm)
        var bytes = Data()
        for index in 0 ..< 30 {
            let buffer = buffer(index * 1600, dipDuration: dipDuration)
            let time = anchor + UInt64(index) * 100_000_000
            stats.recordNative(buffer, hostTimeNanoseconds: time, sampleTime: Int64(index * 1600),
                               configurationID: 3, generation: 7)
            let native = try input.convert(buffer, hostTimeNanoseconds: time, sampleTime: Int64(index * 1600))
            if enabled {
                stats.recordShortNative(buffer, contentTime: native.acceptedInputContentTime,
                                        srcAligned: input.debugSRCMappingKnown && output.debugSRCMappingKnown,
                                        configurationID: 3, generation: 7)
            }
            let spans = host.processCaptureSpans(native.samples, hostTimeNanoseconds: native.hostTimeNanoseconds)
            for packet in try output.convert(captureSpans: spans, requiresContinuousContentTime: true) {
                bytes.append(packet.bytes)
                stats.recordPacket(timestamp: packet.contentTimestampNanoseconds!, byteCount: packet.bytes.count,
                                   accepted: true, configurationID: 3, generation: 7)
                if enabled {
                    final.recordPCM(packet.bytes, start: packet.contentTimestampNanoseconds!)
                }
            }
        }
        expect(stats.snapshot.shortWindows == nil, "active control snapshots do not copy short-window arrays")
        stats.seal()
        return .init(bytes: bytes, native: stats.snapshot, pcm: final.snapshot(identity: identity))
    }

    private static func testSRCAndBytes() throws {
        let baseline = try pipeline(false)
        let instrumented = try pipeline(true)
        expect(baseline.bytes == instrumented.bytes, "DEBUG on/off emits exactly identical PCM bytes")
        let native = instrumented.native
        let paired = rows(native.shortWindows!, instrumented.pcm, trusted: native.coverageValid)
        expect(!paired.isEmpty && paired.allSatisfy { $0["status"] as? String == "MATCHED_CONTENT_COVERAGE" },
               "real normal-priming SRC pairs accepted source intervals")
        for row in paired.dropFirst(3).dropLast(3) {
            expect(abs(row["rms_ratio_db"] as? Double ?? 100) < 0.1,
                   "steady 300Hz SRC stays within the declared 0.1dB synthetic tolerance")
            expect(row["gain_defect"] == nil, "measurement never invents a gain-defect decision")
        }
    }

    private static func testActualSRCDips() throws {
        for duration in [100, 140, 160] {
            let result = try pipeline(true, dipDuration: duration)
            for stream in [result.native.shortWindows!, result.pcm] {
                let low = stream.windows.filter { ($0.level.rms ?? 1) < 0.07 }
                expect(low.first?.start == anchor + 1_000_000_000,
                       "actual SRC preserves the known dip's content-window onset")
                expect(low.last?.end == anchor + 1_000_000_000 + UInt64(duration) * 1_000_000,
                       "actual SRC preserves the known dip's content-window end")
            }
        }
    }

    private static func testIdentityAndSeal() throws {
        var stats = nativeStats()
        for (configuration, generation) in [(3, 7), (4, 7), (3, 8)] {
            stats.recordShortNative(buffer(0), contentTime: anchor, srcAligned: true,
                                    configurationID: UInt64(configuration), generation: UInt64(generation))
        }
        stats.seal()
        let saved = stats.snapshot.shortWindows!
        expect(saved.windows.count == 5 && saved.windows.allSatisfy { $0.level.sampleCount == 320 },
               "stale contexts never enter the current run")
        stats.recordShortNative(buffer(0), contentTime: anchor + 100_000_000, srcAligned: true,
                                configurationID: 3, generation: 7)
        expect(stats.snapshot.shortWindows == saved, "seal stops further statistical writes")
        var replacement = MacSpeechNativeVoiceDebugStats(runID: UUID(), generation: 8)
        replacement.seal()
        expect(replacement.snapshot.shortWindows?.windows.isEmpty == true, "new run has no old slots")
    }

    private static func testCapacityAndCounts() {
        var stats = MacSpeechShortWindowStats(source: .pcm)
        let zero = pcm(0)
        for index in 0 ..< 1000 {
            stats.recordPCM(zero, start: anchor + UInt64(index) * 20_000_000)
        }
        let before = stats.snapshot(identity: identity)
        stats.recordPCM(zero, start: anchor + 20_000_000_000)
        let after = stats.snapshot(identity: identity)
        expect(before.windows.count == 1000 && after.windows.count == 1000 && after.fault == "capacity",
               "fixed capacity never expands or overwrites an old window")
        expect(before.windows[0].level.zeroCount == 480, "zeros are counted without retaining samples")
        let endpoints = fixture([1, -1], native: false)
        expect(endpoints.windows.allSatisfy { $0.level.fullScaleCount == 480 }, "PCM exact endpoints counted")
        let nonfinite = fixture([.nan], native: true)
        expect(allUnknown(rows(nonfinite, fixture([0], native: false))), "nonfinite values cannot pair")
    }
}

private extension NativePCMShortWindowTests {
    static func testIncrementalCallbackCost() {
        var stats = nativeStats()
        let data = buffer(0)
        var elapsed: [UInt64] = []
        for index in 0 ..< 100 {
            let start = DispatchTime.now().uptimeNanoseconds
            stats.recordShortNative(data, contentTime: anchor + UInt64(index) * 100_000_000,
                                    srcAligned: true, configurationID: 3, generation: 7)
            elapsed.append(DispatchTime.now().uptimeNanoseconds - start)
        }
        elapsed.sort()
        print("m19_incremental_native_callback_ns p50=\(elapsed[50]) p95=\(elapsed[95]) max=\(elapsed[99])")
        print("m19_accumulator_level_bytes=\(1000 * MemoryLayout<MacSpeechNativeVoiceDebugChannel>.stride)")
    }

    static func testMicrophoneModes() {
        let modes = MacSpeechMicrophoneModeReadback.read { (active: 2, preferred: 0) }
        expect(modes.active == 2 && modes.preferred == 0 && modes.status == "CONFIRMED_PUBLIC_API",
               "active and preferred are independent readbacks")
        let unavailable = MacSpeechMicrophoneModeReadback.read { nil }
        expect(unavailable.active == nil && unavailable.preferred == nil && unavailable.status == "UNAVAILABLE",
               "unavailable is never replaced by Standard")
        let unknown = MacSpeechMicrophoneModeReadback.read { (active: 99, preferred: 1) }
        expect(unknown.active == nil && unknown.preferred == 1 && unknown.status == "UNKNOWN_ENUM",
               "preferred never substitutes for unknown active mode")
    }
}
