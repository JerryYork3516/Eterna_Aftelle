import Darwin
import Foundation
import VPRecorder
import VPReferenceCore

@main
enum ReferenceTool {
    static func main() async {
        do {
            switch try CommandLinePlan.parse(Array(CommandLine.arguments.dropFirst())) {
            case .help:
                print(
                    """
                    Apple VP reference v1: diagnostics and audio are OFF by default.
                    help
                    verify <private-evidence-directory>
                    request-microphone
                    permission-status
                    inspect-route <same explicit flags as record; no material; no engine start>
                    source-probe --authorize-source-probe --probe-registration <private-json> \
                    --enable-audio --arm-diagnostics --mode VP_ON --duration 8 \
                    --study-id <non-private-alias> --output-dir <new-private-directory-outside-Git>
                    record --enable-audio --arm-diagnostics --mode VP_OFF|VP_ON \
                    --duration <seconds <= 60> --study-id <non-private-alias> \
                    --output-dir <new-private-directory-outside-Git> [--material <registered-PCM-file>]
                    Device recording requires separate controller authorization. No Runtime authority is granted.
                    """)
            case .verify(let directory):
                verify(directory: directory)
            case .requestMicrophone:
                let status = try await MicrophonePermissionPlan().requestExplicitly(using: MicrophonePermissionAccess())
                print("permission_status=\(status.rawValue); no audio started")
            case .permissionStatus:
                print("permission_status=\(MicrophonePermissionAccess.currentStatus().rawValue); no audio started")
            case .inspectRoute(let configuration):
                try RouteInspection.run(configuration: configuration)
            case .sourceProbe(let request):
                let outcome = try SourceProbe().run(request: request)
                print("source_status=SOURCE_UNVERIFIED source_qualification=false evidence=\(outcome.status)")
                print("input_records=\(outcome.inputWrittenRecords) input_frames=\(outcome.inputWrittenFrames)")
            case .record(let configuration):
                let outcome = try VP0AudioSession().run(configuration: configuration)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try EngineeringFailure.check(stage: .evidenceWrite, code: .summaryEncodingFailed) {
                    try encoder.encode(outcome)
                }
                guard let summary = String(data: data, encoding: .utf8) else {
                    throw EngineeringFailure(stage: .evidenceWrite, code: .summaryEncodingFailed)
                }
                print(summary)
                if !outcome.isCompleteForReference { exit(1) }
            }
        } catch {
            let failure = EngineeringFailure.capture(error, stage: .command, code: .invalidArguments)
            emitFailure(failure)
            exit(2)
        }
    }

    private static func emitFailure(_ failure: EngineeringFailure) {
        emit(failure.diagnostic, kind: "PRIMARY")
        for diagnostic in failure.secondary { emit(diagnostic, kind: "SECONDARY") }
        if failure.omittedSecondary > 0 {
            fputs("diagnostic_secondary_omitted=\(failure.omittedSecondary)\n", stderr)
        }
    }

    private static func emit(_ diagnostic: EngineeringDiagnostic, kind: String) {
        fputs("BLOCKED \(kind) stage=\(diagnostic.stage.rawValue) code=\(diagnostic.code)\n", stderr)
    }

    private static func verify(directory: URL) {
        let file = directory.appendingPathComponent("evidence.vp0")
        let validation = file.path.withCString { vp_recorder_validate_file($0) }
        let complete = validation.complete && validation.checksum_matches
        let valid = complete && validation.invalid_reasons == 0
        print("container_complete=\(complete) invalid_reasons=\(validation.invalid_reasons)")
        print("records=\(validation.record_count) pcm_bytes=\(validation.pcm_bytes)")
        print("This validates recorder structure only; source truth and Apple AEC remain NOT_MEASURED.")
        if !valid { exit(1) }
    }
}
