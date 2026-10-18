import Foundation

@MainActor
enum AppleVPDebugProfileTests {
    private static var cases = 0
    private static var checks = 0
    private static let anchor: UInt64 = 10_000_000_000

    static func run() {
        nativeAGCProfiles()
        nativeAGCRegistration()
        print("apple_vp_debug_profile_cases=\(cases)")
        print("apple_vp_debug_profile_checks=\(checks)")
        print("apple_vp_debug_profile_device_access=ZERO")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    private static func nativeAGCProfiles() {
        let format = MacSpeechNativeInputFormat(sampleRate: 48000, channelCount: 1)
        for profile in MacSpeechAppleVPDebugProfile.allCases {
            for bad in 0 ... 6 {
                cases += 1
                let voice = MacSpeechVoiceProcessingSnapshot(
                    mode: bad == 5 ? .webRTCAEC3 : .appleVoiceProcessing, configurationID: 3,
                    inputEnabled: bad != 1, outputEnabled: bad != 2, bypassed: bad == 3,
                    inputMuted: bad == 4,
                    automaticGainControlEnabled: bad == 0
                        ? !profile.automaticGainControlEnabled : profile.automaticGainControlEnabled,
                    inputFormat: format, outputFormat: format, validatedAtNanoseconds: anchor
                )
                expect(profile.accepts(voice) == (bad == 6), "profile requires exact AGC and VP states")
                var stats = MacSpeechNativeVoiceDebugStats(runID: UUID(), generation: 7, profile: profile)
                stats.bind(configurationID: 3, voiceProcessing: voice)
                expect(stats.snapshot.issues.contains("voice_processing") == (bad != 6),
                       "native evidence enforces the prepared profile")
                if bad == 6 {
                    expect(voice.hasValidAppleProcessing == (profile == .agcOn),
                           "the production AGC-ON predicate is unchanged")
                }
            }
        }
    }

    private static func nativeAGCRegistration() {
        cases += 1
        let engine = SystemMacSpeechVoiceProcessingEngine()
        let run = UUID()
        expect(!engine.armNativeVoiceDebug(runID: run, generation: 7, profile: .agcOff),
               "WebRTC mode cannot register an Apple AGC-OFF experiment")
        do {
            try engine.selectProcessingMode(.appleVoiceProcessing)
            expect(engine.armNativeVoiceDebug(runID: run, generation: 7, profile: .agcOff),
                   "an idle DEBUG run registers once without configuring a device")
            expect(!engine.armNativeVoiceDebug(runID: UUID(), generation: 8, profile: .agcOn),
                   "a new run cannot replace an armed configuration")
            do {
                _ = try engine.startCapture(generation: 8, frameBuffer: MacSpeechAudioFrameBuffer())
                expect(false, "a mismatched generation must fail before engine creation")
            } catch {
                expect(error as? MacSpeechAudioCaptureError == .voiceProcessingUnavailable,
                       "the stale generation is rejected at the configuration fence")
            }
            expect(engine.voiceProcessingSnapshot() == nil, "offline failure creates no VP readback")
            expect(engine.voiceProcessingConfigurationDebug()["agc_off_registration_present"] as? Bool == false,
                   "a mismatched generation invalidates the experiment registration")
            engine.clearNativeVoiceDebug(runID: UUID())
            expect(!engine.armNativeVoiceDebug(runID: UUID(), generation: 8, profile: .agcOff),
                   "a wrong run ID cannot clear the old evidence")
            engine.clearNativeVoiceDebug(runID: run)
            nativeAGCResetFences(engine)
        } catch {
            expect(false, "idle DEBUG registration must not require a device")
        }
    }

    private static func nativeAGCResetFences(_ engine: SystemMacSpeechVoiceProcessingEngine) {
        for action in ["route", "generation", "close", "stop"] {
            cases += 1
            let run = UUID()
            expect(engine.armNativeVoiceDebug(runID: run, generation: 9, profile: .agcOff),
                   "each reset test registers a fresh offline run")
            switch action {
            case "route": engine.routeWillRebuild(); engine.routeDidRebuild()
            case "generation": engine.discardPendingAudioForGenerationTransition()
            case "stop": engine.stopCapture()
            default: engine.closeOutput()
            }
            expect(engine.voiceProcessingConfigurationDebug()["agc_off_registration_present"] as? Bool == false,
                   "route, generation, close and Stop remove the DEBUG exception")
            expect(engine.voiceProcessingSnapshot() == nil, "reset never fabricates a hardware readback")
            engine.clearNativeVoiceDebug(runID: run)
        }
        let run = UUID()
        expect(engine.armNativeVoiceDebug(runID: run, generation: 10), "the old API remains AGC-ON")
        expect(engine.nativeVoiceDebugSnapshot(runID: run)?.profile == .agcOn,
               "a later default run cannot inherit AGC-OFF")
        engine.stopCapture()
        engine.clearNativeVoiceDebug(runID: run)
    }
}
