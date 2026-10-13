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
            throw ReferenceFailure.blocked("VP configuration requires a stopped fresh engine")
        }
        try driver.setVoiceProcessingEnabled(mode.isEnabled)
        let state = try driver.readVoiceProcessingState()
        try validate(state: state, mode: mode)
        let formats = try driver.readFormats()
        try validate(formats: formats, mode: mode)
        try driver.connectPlayback(using: formats)
        let connectedFormats = try driver.readFormats()
        try validate(formats: connectedFormats, mode: mode)
        guard connectedFormats.input == formats.input, connectedFormats.output == formats.output else {
            throw ReferenceFailure.blocked("Graph connection changed I/O formats; do not use stale formats")
        }
        return ConfiguredEngine(
            mode: mode, state: state, formats: connectedFormats, preConnectionFormats: formats
        )
    }

    public static func validate(state: VoiceProcessingState, mode: VPMode) throws {
        guard state.inputEnabled == mode.isEnabled, state.outputEnabled == mode.isEnabled else {
            throw ReferenceFailure.blocked("Actual I/O voice-processing mode does not match requested mode")
        }
        if mode == .enabled {
            guard state.bypassed == false, state.inputMuted == false, state.agcEnabled != nil else {
                throw ReferenceFailure.blocked("VP ON state is bypassed, muted, or unavailable")
            }
        }
    }

    public static func validate(formats: AudioFormats, mode: VPMode) throws {
        guard formats.input.isValidPCM, formats.mixer.isValidPCM, formats.output.isValidPCM else {
            throw ReferenceFailure.blocked("A required native PCM format is unavailable")
        }
        if mode == .enabled, formats.input != formats.output {
            throw ReferenceFailure.blocked("VP I/O formats differ")
        }
    }
}
