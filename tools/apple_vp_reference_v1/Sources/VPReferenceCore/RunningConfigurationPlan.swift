public struct RunningConfigurationSnapshot {
    public let state: VoiceProcessingState
    public let formats: AudioFormats
    public let hardwareOutput: NativeAudioFormat

    public init(state: VoiceProcessingState, formats: AudioFormats, hardwareOutput: NativeAudioFormat) {
        self.state = state
        self.formats = formats
        self.hardwareOutput = hardwareOutput
    }
}

public enum RunningConfigurationPlan {
    public static func validate(
        configured: ConfiguredEngine, expectedHardwareOutput: NativeAudioFormat,
        actual: RunningConfigurationSnapshot
    ) throws {
        guard actual.state == configured.state else {
            throw EngineeringFailure(stage: .vpState, code: .vpStateChanged)
        }
        guard actual.formats.input == configured.formats.input else {
            throw EngineeringFailure(stage: .inputFormat, code: .inputFormatChanged)
        }
        guard actual.formats.output == configured.formats.output,
            actual.formats.mixer == configured.formats.mixer
        else {
            throw EngineeringFailure(stage: .outputFormat, code: .outputFormatChanged)
        }
        guard actual.hardwareOutput == expectedHardwareOutput else {
            throw EngineeringFailure(stage: .outputFormat, code: .outputFormatChanged)
        }
    }
}
