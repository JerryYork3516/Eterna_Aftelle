public enum FailureStage: String, Codable, Sendable, CaseIterable {
    case command = "COMMAND"
    case permission = "PERMISSION"
    case sourceMaterial = "SOURCE_MATERIAL"
    case vpConfiguration = "VP_CONFIGURATION"
    case vpState = "VP_STATE"
    case inputFormat = "INPUT_FORMAT"
    case outputFormat = "OUTPUT_FORMAT"
    case deviceBinding = "DEVICE_BINDING"
    case enginePrepare = "ENGINE_PREPARE"
    case engineStart = "ENGINE_START"
    case engineStop = "ENGINE_STOP"
    case recorder = "RECORDER"
    case seal = "SEAL"
    case evidenceWrite = "EVIDENCE_WRITE"
}

public enum FailureCode: String, Sendable {
    case invalidArguments = "INVALID_ARGUMENTS"
    case sessionAlreadyUsed = "SESSION_ALREADY_USED"
    case materialLoadFailed = "MATERIAL_LOAD_FAILED"
    case materialIdentityMismatch = "MATERIAL_IDENTITY_MISMATCH"
    case materialSampleLayoutInvalid = "MATERIAL_SAMPLE_LAYOUT_INVALID"
    case materialNonFiniteSamples = "MATERIAL_NON_FINITE_SAMPLES"
    case materialOutOfRangeSamples = "MATERIAL_OUT_OF_RANGE_SAMPLES"
    case experimentWindowInvalid = "EXPERIMENT_WINDOW_INVALID"
    case experimentClockInvalid = "EXPERIMENT_CLOCK_INVALID"
    case experimentEngineStateMismatch = "EXPERIMENT_ENGINE_STATE_MISMATCH"
    case experimentPlaybackFailed = "EXPERIMENT_PLAYBACK_FAILED"
    case vpEnableFailed = "VP_ENABLE_FAILED"
    case engineAlreadyRunning = "ENGINE_ALREADY_RUNNING"
    case stateReadFailed = "STATE_READ_FAILED"
    case vpModeMismatch = "VP_MODE_MISMATCH"
    case vpStateUnavailable = "VP_STATE_UNAVAILABLE"
    case vpStateChanged = "VP_STATE_CHANGED"
    case formatReadFailed = "FORMAT_READ_FAILED"
    case inputFormatUnavailable = "INPUT_FORMAT_UNAVAILABLE"
    case inputFormatChanged = "INPUT_FORMAT_CHANGED"
    case outputFormatUnavailable = "OUTPUT_FORMAT_UNAVAILABLE"
    case outputFormatChanged = "OUTPUT_FORMAT_CHANGED"
    case vpIOFormatMismatch = "VP_IO_FORMAT_MISMATCH"
    case mixerFormatMismatch = "MIXER_FORMAT_MISMATCH"
    case graphConnectionFailed = "GRAPH_CONNECTION_FAILED"
    case deviceReadFailed = "DEVICE_READ_FAILED"
    case unsupportedRoute = "UNSUPPORTED_ROUTE"
    case deviceBindingMismatch = "DEVICE_BINDING_MISMATCH"
    case routeChanged = "ROUTE_CHANGED"
    case prePlaybackConfigurationInvalid = "PRE_PLAYBACK_CONFIGURATION_INVALID"
    case enginePrepareFailed = "ENGINE_PREPARE_FAILED"
    case engineStartFailed = "ENGINE_START_FAILED"
    case recorderCreateFailed = "RECORDER_CREATE_FAILED"
    case recorderArmFailed = "RECORDER_ARM_FAILED"
    case recorderInvalid = "RECORDER_INVALID"
    case probeClockInvalid = "PROBE_CLOCK_INVALID"
    case probeStimulusWindowMissed = "PROBE_STIMULUS_WINDOW_MISSED"
    case probeEngineStateMismatch = "PROBE_ENGINE_STATE_MISMATCH"
    case sealFailed = "SEAL_FAILED"
    case identityFailed = "IDENTITY_FAILED"
    case preparedWriteFailed = "PREPARED_WRITE_FAILED"
    case finalWriteFailed = "FINAL_WRITE_FAILED"
    case summaryEncodingFailed = "SUMMARY_ENCODING_FAILED"
}

public struct EngineeringDiagnostic: Encodable, Equatable, Sendable {
    public let stage: FailureStage
    public let code: String

    public init(stage: FailureStage, code: FailureCode) {
        self.stage = stage
        self.code = code.rawValue
    }

    public init(permission: MicrophonePermissionFailure) {
        stage = .permission
        code = permission.rawValue
    }
}

public struct EngineeringFailure: Error, Sendable {
    public let diagnostic: EngineeringDiagnostic
    public let secondary: [EngineeringDiagnostic]
    public let omittedSecondary: UInt64

    public init(stage: FailureStage, code: FailureCode) {
        diagnostic = EngineeringDiagnostic(stage: stage, code: code)
        secondary = []
        omittedSecondary = 0
    }

    public init(diagnostics: RunDiagnostics) {
        diagnostic = diagnostics.primary ?? EngineeringDiagnostic(stage: .command, code: .invalidArguments)
        secondary = diagnostics.secondary
        omittedSecondary = diagnostics.omittedSecondary
    }

    public static func capture(_ error: any Error, stage: FailureStage, code: FailureCode) -> Self {
        if let existing = error as? Self { return existing }
        if let permission = error as? MicrophonePermissionFailure {
            var diagnostics = RunDiagnostics()
            diagnostics.record(EngineeringDiagnostic(permission: permission))
            return Self(diagnostics: diagnostics)
        }
        return Self(stage: stage, code: code)
    }

    public static func check<Result>(
        stage: FailureStage, code: FailureCode, operation: () throws -> Result
    ) throws -> Result {
        do { return try operation() } catch { throw capture(error, stage: stage, code: code) }
    }
}

public struct RunDiagnostics: Encodable, Sendable {
    public private(set) var primary: EngineeringDiagnostic?
    public private(set) var secondary: [EngineeringDiagnostic] = []
    public private(set) var omittedSecondary: UInt64 = 0
    public static let maximumSecondary = 4

    public init() {}

    public mutating func record(_ diagnostic: EngineeringDiagnostic) {
        if primary == nil {
            primary = diagnostic
        } else if secondary.count < Self.maximumSecondary {
            secondary.append(diagnostic)
        } else {
            omittedSecondary += 1
        }
    }

    public mutating func record(_ failure: EngineeringFailure) {
        record(failure.diagnostic)
        for diagnostic in failure.secondary { record(diagnostic) }
        omittedSecondary += failure.omittedSecondary
    }
}
