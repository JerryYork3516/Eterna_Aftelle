@preconcurrency import AVFoundation
import Foundation

@main
@MainActor
enum WarmupWindowStatsTests {
    private static let anchor: UInt64 = 10_000_000_000
    private static var cases = 0
    private static var checks = 0

    static func main() throws {
        try testNativeWindows()
        try testBoundaryAndPCM()
        try testIdentityAndInvalid()
        print("warmup_native_cases=\(cases)")
        print("warmup_native_checks=\(checks)")
        print("warmup_native_device_access=ZERO")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    private static func plan(_ profile: MacSpeechWarmupProfile) throws -> MacSpeechAcousticWindowPlan {
        guard let value = MacSpeechAcousticWindowPlan(captureStartedAt: anchor, profile: profile) else {
            throw CocoaError(.coderInvalidValue)
        }
        return value
    }

    private static func buffer(frames: Int = 1600, interleaved: Bool = false) throws -> AVAudioPCMBuffer {
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3) else {
            throw CocoaError(.coderInvalidValue)
        }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   interleaved: interleaved, channelLayout: layout)
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(frames)),
              let data = result.floatChannelData else { throw CocoaError(.coderInvalidValue) }
        result.frameLength = result.frameCapacity
        for frame in 0 ..< frames {
            let sample = Float(sin(Double(frame) * .pi / 8) * 0.25)
            for channel in 0 ..< 3 {
                data[interleaved ? 0 : channel][interleaved ? frame * 3 + channel : frame] =
                    channel == 2 ? 0 : sample
            }
        }
        return result
    }

    private static func rows(_ stats: MacSpeechAcousticWindowStats) throws -> [[String: Any]] {
        guard let result = stats.manifest()["windows"] as? [[String: Any]] else {
            throw CocoaError(.coderInvalidValue)
        }
        return result
    }

    private static func testNativeWindows() throws {
        for profile in MacSpeechWarmupProfile.allCases {
            cases += 1
            var stats = try MacSpeechAcousticWindowStats(plan: plan(profile))
            let samples = try buffer()
            let count = profile == .four ? 190 : 150
            for index in 0 ..< count {
                stats.recordNative(samples, hostTime: anchor + UInt64(index) * 100_000_000)
            }
            let windows = try rows(stats)
            let seconds = [profile == .four ? 4 : 0, 3, 6, 2, 4]
            for (index, window) in windows.enumerated() {
                let channels = window["channels"] as? [[String: Any]] ?? []
                expect(channels.count == 3, "all native channels remain observable")
                expect(channels[0]["samples"] as? UInt64 == UInt64(seconds[index] * 16000),
                       "native windows partition content samples without dropping the warm-up")
                expect(channels[1]["compared_to_ch0_finite_samples"] as? UInt64
                    == channels[1]["numerically_equal_to_ch0_samples"] as? UInt64,
                    "duplicate synthetic channels are measured equal, not assigned physical meaning")
                if seconds[index] > 0 {
                    let rms = channels[0]["rms"] as? Double ?? -1
                    expect(abs(rms - 0.25 / sqrt(2)) < 0.00001, "known native RMS is independent of PCM16")
                    expect(channels[2]["rms"] as? Double == 0, "the third channel is independently silent")
                }
            }
            expect(stats.excludedFrames == 0 && stats.invalidBuffers == 0, "aligned windows cover the full run")
        }
    }

    private static func testBoundaryAndPCM() throws {
        cases += 1
        var stats = try MacSpeechAcousticWindowStats(plan: plan(.four))
        let value = try buffer(interleaved: true)
        stats.recordNative(value, hostTime: anchor + 3_990_031_337)
        expect(stats.excludedFrames == 1, "a native sample crossing a boundary is excluded, not split or relabelled")
        let windows = try rows(stats)
        let warmup = windows[0]["channels"] as? [[String: Any]] ?? []
        let scoring = windows[1]["channels"] as? [[String: Any]] ?? []
        expect((warmup[0]["samples"] as? UInt64 ?? 0) + (scoring[0]["samples"] as? UInt64 ?? 0) == 1599,
               "interleaved boundary accounting is complete and bounded")
        cases += 1
        var pcm = try MacSpeechAcousticWindowStats(plan: plan(.four))
        for index in 0 ..< 950 {
            pcm.recordPCM(Data(repeating: 0, count: 960), hostTime: anchor + UInt64(index) * 20_000_000)
        }
        let pcmWindows = try rows(pcm)
        let total = pcmWindows.reduce(UInt64(0)) { sum, item in
            let channels = item["channels"] as? [[String: Any]] ?? []
            return sum + (channels.first?["samples"] as? UInt64 ?? 0)
        }
        expect(total == 456_000, "all 19 seconds are measured without storing PCM")
        expect(pcmWindows.count == 5, "statistics have fixed capacity")
        pcm.recordPCM(Data(repeating: 0, count: 1), hostTime: anchor)
        expect(pcm.invalidBuffers == 1, "invalid PCM does not become valid statistics")
        for index in 950 ..< 1050 {
            pcm.recordPCM(Data(repeating: 0, count: 960), hostTime: anchor + UInt64(index) * 20_000_000)
        }
        let finalWindows = try rows(pcm)
        expect(finalWindows.count == 5, "post-budget data cannot grow the window collection")
        expect(MacSpeechAcousticWindowPlan(captureStartedAt: .max, profile: .four) == nil,
               "time overflow cannot create an open-ended run")
    }

    private static func testIdentityAndInvalid() throws {
        let format = MacSpeechNativeInputFormat(sampleRate: 16000, channelCount: 3)
        let four = try plan(.four)
        let zero = try plan(.zero)
        for profile in MacSpeechAppleVPDebugProfile.allCases {
            cases += 1
            var stats = MacSpeechNativeVoiceDebugStats(runID: UUID(), generation: 7, profile: profile)
            stats.bind(configurationID: 3, voiceProcessing: MacSpeechVoiceProcessingSnapshot(
                mode: .appleVoiceProcessing, configurationID: 3, inputEnabled: true, outputEnabled: true,
                bypassed: false, inputMuted: false, automaticGainControlEnabled: profile == .agcOn,
                inputFormat: format, outputFormat: format, validatedAtNanoseconds: anchor
            ))
            expect(stats.configureWindows(four) == (profile == .agcOn), "warm-up requires AGC-ON")
            expect(!stats.configureWindows(zero), "a configured run cannot change its windows")
            try stats.recordNative(buffer(), hostTimeNanoseconds: anchor, sampleTime: 0,
                                   configurationID: 3, generation: 6)
            expect(stats.snapshot.nativeBufferCount == 0, "old generation never enters the window statistics")
            expect(stats.snapshot.issues.contains("stale_context"), "old generation retains the original rejection")
            stats.seal()
            expect(!stats.configureWindows(four), "sealed runs reject reconfiguration")
        }
        cases += 1
        var stats = try MacSpeechAcousticWindowStats(plan: plan(.zero))
        let values = try buffer(frames: 10)
        values.floatChannelData?[0][0] = .nan
        stats.recordNative(values, hostTime: anchor)
        let window = try rows(stats)[1]
        let channels = window["channels"] as? [[String: Any]] ?? []
        expect(channels[0]["non_finite"] as? UInt64 == 1 && channels[0]["rms"] is NSNull,
               "nonfinite data remains UNKNOWN rather than a successful RMS")
        stats.recordNative(values, hostTime: nil)
        expect(stats.invalidBuffers == 1, "missing content time cannot be substituted with callback arrival")
    }
}
