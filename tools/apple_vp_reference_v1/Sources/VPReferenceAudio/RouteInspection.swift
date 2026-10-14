import Darwin
import Foundation
import VPReferenceCore

enum RouteInspection {
    static func run(configuration: RunConfiguration) throws {
        try configuration.validateForAudio()
        try MicrophonePermissionPlan.requireAuthorized(status: MicrophonePermissionAccess.currentStatus())
        let driver = AppleEngineDriver(material: nil)
        let configured = try configure(configuration: configuration, driver: driver)
        let route = try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            try AudioRouteSnapshot.read(engine: driver.engine)
        }
        let manifest = try EngineeringFailure.check(stage: .evidenceWrite, code: .identityFailed) {
            try AudioRunManifest.create(
                configuration: configuration, configured: configured, route: route, driver: driver, material: nil)
        }
        try EngineeringFailure.check(stage: .evidenceWrite, code: .preparedWriteFailed) {
            guard configuration.outputDirectory.path.withCString({ mkdir($0, mode_t(0o700)) }) == 0 else {
                throw AudioReferenceError.evidenceWriteFailed
            }
            try manifest.writePrepared(directory: configuration.outputDirectory)
        }
        print("route_inspection=COMPLETE binding=\(route.deviceBindingStatus) engine=NOT_STARTED; no PCM")
    }

    private static func configure(
        configuration: RunConfiguration, driver: AppleEngineDriver
    ) throws -> ConfiguredEngine {
        do { return try ConfigurationPlan.configure(mode: configuration.mode, driver: driver) } catch {
            let failure = EngineeringFailure.capture(error, stage: .vpConfiguration, code: .formatReadFailed)
            var diagnostics = RunDiagnostics()
            diagnostics.record(failure)
            let snapshot = ConfigurationFailureSnapshot(
                mode: configuration.mode, primary: failure.diagnostic,
                state: try? driver.readVoiceProcessingState(), formats: try? driver.readFormats())
            do {
                guard configuration.outputDirectory.path.withCString({ mkdir($0, mode_t(0o700)) }) == 0 else {
                    throw AudioReferenceError.evidenceWriteFailed
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try PrivateManifestWriter.write(
                    data: encoder.encode(snapshot),
                    target: configuration.outputDirectory.appendingPathComponent("configuration_failure.json"))
            } catch { diagnostics.record(EngineeringDiagnostic(stage: .evidenceWrite, code: .preparedWriteFailed)) }
            throw EngineeringFailure(diagnostics: diagnostics)
        }
    }
}

private struct ConfigurationFailureSnapshot: Encodable {
    let schemaVersion = 1
    let terminal = "CONFIGURATION_FAILED_ENGINE_NOT_STARTED"
    let mode: VPMode
    let primary: EngineeringDiagnostic
    let state: VoiceProcessingState?
    let formats: AudioFormats?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case terminal, mode, primary, state, formats
    }
}
