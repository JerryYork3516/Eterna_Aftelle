import AVFoundation
import CryptoKit
import Foundation
import VPReferenceCore

struct AudioRunManifest: Encodable {
    let schemaVersion = 1
    let runID: String
    let studyID: String
    let buildSHA256: String
    let configSHA256: String
    let mode: VPMode
    let durationSeconds: Double
    let configured: ConfiguredEngine
    let routeBefore: AudioRouteSnapshot
    var postStopRoute: AudioRouteSnapshot?
    var runningRoute: AudioRouteSnapshot?
    var runningFormats: AudioFormats?
    var runningState: VoiceProcessingState?
    var runningHardwareOutputFormat: NativeAudioFormat?
    var postStopFormats: AudioFormats?
    var postStopState: VoiceProcessingState?
    var postStopHardwareOutputFormat: NativeAudioFormat?
    let hardwareOutputFormat: NativeAudioFormat
    let material: PCMSourceIdentity?
    let materialStatus: String
    let renderMeaning = "DIGITAL_MIXER_OUTPUT; not actual speaker sound pressure"
    let inputMeaning: String
    let sampleMapping = "Render sample timestamps are native; exact source-frame mapping UNVERIFIED"
    var snapshotTiming = "Running snapshot follows engine start, before playback; terminal snapshots follow stop"
    var diagnosticClockOrigin =
        "MACH_CONTINUOUS_TIME; arm before engine prepare/start; 60s includes startup/sleep; "
        + "raw AVAudioTime.hostTime retains its separate clock domain"
    var outcome: AudioRunOutcome?
    var terminalStatus: String
    var diagnostics = RunDiagnostics()
    var sourceProbe: SourceProbeEvidence?
    var vpaExperiment: VPAEvidence?
    let diagnosticsSchemaVersion = 1

    static func create(
        configuration: RunConfiguration, configured: ConfiguredEngine,
        route: AudioRouteSnapshot, driver: AppleEngineDriver, material: PCMSourceMaterial?
    ) throws -> Self {
        let configurationIdentity = ConfigurationIdentity(
            mode: configuration.mode, durationSeconds: configuration.durationSeconds,
            studyID: configuration.studyID, materialSHA256: material?.identity.sha256,
            nativePCMSHA256: material?.identity.nativePCMSHA256,
            inputDevice: route.defaultInput.anonymousID, outputDevice: route.defaultOutput.anonymousID
        )
        let identityEncoder = JSONEncoder()
        identityEncoder.outputFormatting = [.sortedKeys]
        let encoded = try identityEncoder.encode(configurationIdentity)
        let inputMeaning =
            configuration.mode == .disabled
            ? "VP_OFF_CAPTURE; not ADC raw truth" : "VP_ON_NATIVE_CAPTURE"
        return Self(
            runID: UUID().uuidString, studyID: configuration.studyID,
            buildSHA256: try buildIdentity(), configSHA256: digest(encoded), mode: configuration.mode,
            durationSeconds: configuration.durationSeconds, configured: configured,
            routeBefore: route,
            hardwareOutputFormat: AppleEngineDriver.snapshot(
                driver.engine.outputNode.outputFormat(forBus: 0)
            ), material: material?.identity,
            materialStatus: material == nil ? "RESIDENT_SILENT" : "FIXED_LINEAR_PCM",
            inputMeaning: inputMeaning,
            terminalStatus: "PREPARED_NOT_STARTED"
        )
    }

    func writePrepared(directory: URL) throws {
        try write(directory: directory, filename: "prepared.json")
    }

    mutating func prepareVPA(registrationSHA256: String) {
        vpaExperiment = VPAEvidence(registrationSHA256: registrationSHA256)
        diagnosticClockOrigin =
            "MACH_CONTINUOUS_TIME; VP-A 16s hard admission includes prepare/start; "
            + "raw AVAudioTime.hostTime retains its separate clock domain"
        snapshotTiming = "VP-A: latest post-start/window control snapshot; terminal snapshots follow stop"
    }

    func writeFinal(directory: URL) throws {
        try write(directory: directory, filename: "manifest.json")
    }

    private func write(directory: URL, filename: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try PrivateManifestWriter.write(data: data, target: directory.appendingPathComponent(filename))
    }

    private static func buildIdentity() throws -> String {
        guard let executable = Bundle.main.executableURL else { return "UNAVAILABLE" }
        let handle = try FileHandle(forReadingFrom: executable)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case studyID = "study_id"
        case buildSHA256 = "build_sha256"
        case configSHA256 = "config_sha256"
        case mode = "vp_mode"
        case durationSeconds = "planned_duration_seconds"
        case configured
        case routeBefore = "route_before"
        case postStopRoute = "post_stop_route"
        case runningRoute = "running_route"
        case runningFormats = "running_formats"
        case runningState = "running_state"
        case runningHardwareOutputFormat = "running_hardware_output_format"
        case postStopFormats = "post_stop_formats"
        case postStopState = "post_stop_state"
        case postStopHardwareOutputFormat = "post_stop_hardware_output_format"
        case hardwareOutputFormat = "configured_hardware_output_format"
        case material, materialStatus, renderMeaning, inputMeaning
        case sampleMapping, snapshotTiming, diagnosticClockOrigin, outcome, terminalStatus, diagnostics
        case diagnosticsSchemaVersion = "diagnostics_schema_version"
        case sourceProbe = "source_probe"
        case vpaExperiment = "vpa_experiment"
    }
}

private struct ConfigurationIdentity: Codable {
    let mode: VPMode
    let durationSeconds: Double
    let studyID: String
    let materialSHA256: String?
    let nativePCMSHA256: String?
    let inputDevice: String
    let outputDevice: String
}
