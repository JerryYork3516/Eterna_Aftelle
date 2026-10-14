import Foundation

public struct NativeAudioFormat: Codable, Equatable, Sendable {
    public let sampleRate: Double
    public let channelCount: UInt32
    public let formatID: UInt32
    public let formatFlags: UInt32
    public let bytesPerFrame: UInt32
    public let bitsPerChannel: UInt32

    public init(
        sampleRate: Double, channelCount: UInt32, formatID: UInt32,
        formatFlags: UInt32, bytesPerFrame: UInt32, bitsPerChannel: UInt32
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.formatID = formatID
        self.formatFlags = formatFlags
        self.bytesPerFrame = bytesPerFrame
        self.bitsPerChannel = bitsPerChannel
    }

    public var isValidPCM: Bool {
        sampleRate.isFinite && sampleRate > 0 && channelCount > 0 && channelCount <= 32
            && formatID == 0x6C70_636D && bytesPerFrame > 0 && bitsPerChannel > 0
    }
}

public struct AudioFormats: Codable, Equatable, Sendable {
    public let input: NativeAudioFormat
    public let mixer: NativeAudioFormat
    public let output: NativeAudioFormat

    public init(input: NativeAudioFormat, mixer: NativeAudioFormat, output: NativeAudioFormat) {
        self.input = input
        self.mixer = mixer
        self.output = output
    }
}

public struct VoiceProcessingState: Codable, Equatable, Sendable {
    public let inputEnabled: Bool
    public let outputEnabled: Bool
    public let bypassed: Bool?
    public let agcEnabled: Bool?
    public let inputMuted: Bool?

    public init(
        inputEnabled: Bool, outputEnabled: Bool,
        bypassed: Bool?, agcEnabled: Bool?, inputMuted: Bool?
    ) {
        self.inputEnabled = inputEnabled
        self.outputEnabled = outputEnabled
        self.bypassed = bypassed
        self.agcEnabled = agcEnabled
        self.inputMuted = inputMuted
    }

    private enum CodingKeys: String, CodingKey {
        case inputEnabled, outputEnabled, bypassed, agcEnabled, inputMuted
        case bypassStatus, agcStatus, muteStatus
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inputEnabled = try values.decode(Bool.self, forKey: .inputEnabled)
        outputEnabled = try values.decode(Bool.self, forKey: .outputEnabled)
        bypassed = try values.decodeIfPresent(Bool.self, forKey: .bypassed)
        agcEnabled = try values.decodeIfPresent(Bool.self, forKey: .agcEnabled)
        inputMuted = try values.decodeIfPresent(Bool.self, forKey: .inputMuted)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(inputEnabled, forKey: .inputEnabled)
        try values.encode(outputEnabled, forKey: .outputEnabled)
        try values.encode(bypassed, forKey: .bypassed)
        try values.encode(agcEnabled, forKey: .agcEnabled)
        try values.encode(inputMuted, forKey: .inputMuted)
        try values.encode(bypassed == nil ? "UNAVAILABLE" : "AVAILABLE", forKey: .bypassStatus)
        try values.encode(agcEnabled == nil ? "UNAVAILABLE" : "AVAILABLE", forKey: .agcStatus)
        try values.encode(inputMuted == nil ? "UNAVAILABLE" : "AVAILABLE", forKey: .muteStatus)
    }
}

public protocol EngineConfigurationDriving: AnyObject {
    var isRunning: Bool { get }
    func setVoiceProcessingEnabled(_ enabled: Bool) throws
    func readVoiceProcessingState() throws -> VoiceProcessingState
    func readFormats() throws -> AudioFormats
    func connectPlayback(using formats: AudioFormats) throws
}

public struct ConfiguredEngine: Codable, Sendable {
    public let mode: VPMode
    public let state: VoiceProcessingState
    public let formats: AudioFormats
    public let preConnectionFormats: AudioFormats
}

public enum ConfigurationPlan {
    public static func configure(
        mode: VPMode, driver: any EngineConfigurationDriving
    ) throws -> ConfiguredEngine {
        guard !driver.isRunning else {
            throw EngineeringFailure(stage: .vpConfiguration, code: .engineAlreadyRunning)
        }
        try EngineeringFailure.check(stage: .vpConfiguration, code: .vpEnableFailed) {
            try driver.setVoiceProcessingEnabled(mode.isEnabled)
        }
        let state = try EngineeringFailure.check(stage: .vpState, code: .stateReadFailed) {
            try driver.readVoiceProcessingState()
        }
        try validate(state: state, mode: mode)
        let formats = try readFormats(driver: driver)
        try validatePCM(formats: formats)
        try EngineeringFailure.check(stage: .outputFormat, code: .graphConnectionFailed) {
            try driver.connectPlayback(using: formats)
        }
        let connectedFormats = try readFormats(driver: driver)
        try validate(formats: connectedFormats, mode: mode)
        guard connectedFormats.input == formats.input else {
            throw EngineeringFailure(stage: .inputFormat, code: .inputFormatChanged)
        }
        let expectedOutput = mode == .enabled ? formats.input : formats.output
        guard connectedFormats.output == expectedOutput else {
            throw EngineeringFailure(stage: .outputFormat, code: .outputFormatChanged)
        }
        guard connectedFormats.mixer == connectedFormats.output else {
            throw EngineeringFailure(stage: .outputFormat, code: .mixerFormatMismatch)
        }
        return ConfiguredEngine(
            mode: mode, state: state, formats: connectedFormats, preConnectionFormats: formats
        )
    }

    private static func readFormats(driver: any EngineConfigurationDriving) throws -> AudioFormats {
        try EngineeringFailure.check(stage: .vpConfiguration, code: .formatReadFailed) {
            try driver.readFormats()
        }
    }

    public static func validate(state: VoiceProcessingState, mode: VPMode) throws {
        guard state.inputEnabled == mode.isEnabled, state.outputEnabled == mode.isEnabled else {
            throw EngineeringFailure(stage: .vpState, code: .vpModeMismatch)
        }
        if mode == .enabled {
            guard state.bypassed == false, state.inputMuted == false, state.agcEnabled != nil else {
                throw EngineeringFailure(stage: .vpState, code: .vpStateUnavailable)
            }
        }
    }

    public static func validate(formats: AudioFormats, mode: VPMode) throws {
        try validatePCM(formats: formats)
        if mode == .enabled, formats.input != formats.output {
            throw EngineeringFailure(stage: .outputFormat, code: .vpIOFormatMismatch)
        }
    }

    private static func validatePCM(formats: AudioFormats) throws {
        guard formats.input.isValidPCM else {
            throw EngineeringFailure(stage: .inputFormat, code: .inputFormatUnavailable)
        }
        guard formats.mixer.isValidPCM, formats.output.isValidPCM else {
            throw EngineeringFailure(stage: .outputFormat, code: .outputFormatUnavailable)
        }
    }
}
