import VPReferenceCore

enum EngineeringFixture {
    static func format(rate: Double = 48_000) -> NativeAudioFormat {
        NativeAudioFormat(
            sampleRate: rate, channelCount: 2, formatID: 0x6C70_636D,
            formatFlags: 9, bytesPerFrame: 8, bitsPerChannel: 32
        )
    }

    static func state(enabled: Bool = true) -> VoiceProcessingState {
        VoiceProcessingState(
            inputEnabled: enabled, outputEnabled: enabled,
            bypassed: false, agcEnabled: true, inputMuted: false
        )
    }

    static var formats: AudioFormats {
        AudioFormats(input: format(), mixer: format(), output: format())
    }

    static func configured() throws -> ConfiguredEngine {
        // The same public configuration path as production; this driver never constructs an engine.
        try ConfigurationPlan.configure(mode: .enabled, driver: ConfigurationFixtureDriver())
    }

    static var snapshot: RunningConfigurationSnapshot {
        RunningConfigurationSnapshot(state: state(), formats: formats, hardwareOutput: format())
    }
}

final class ConfigurationFixtureDriver: EngineConfigurationDriving {
    var isRunning = false
    var failure: FailureStage?
    var inputInvalid = false
    var outputInvalid = false
    var finalMixerMismatch = false
    var calls = 0
    private var reads = 0

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        calls += 1
        if failure == .vpConfiguration { throw EngineeringFixtureFailure.synthetic }
    }

    func readVoiceProcessingState() throws -> VoiceProcessingState {
        if failure == .vpState { throw EngineeringFixtureFailure.synthetic }
        return EngineeringFixture.state()
    }

    func readFormats() throws -> AudioFormats {
        reads += 1
        return AudioFormats(
            input: EngineeringFixture.format(rate: inputInvalid ? 0 : 48_000),
            mixer: EngineeringFixture.format(rate: finalMixerMismatch && reads > 1 ? 16_000 : 48_000),
            output: EngineeringFixture.format(rate: outputInvalid ? 0 : 48_000)
        )
    }

    func connectPlayback(using formats: AudioFormats) throws {}
}

enum EngineeringFixtureFailure: Error {
    case synthetic
}
