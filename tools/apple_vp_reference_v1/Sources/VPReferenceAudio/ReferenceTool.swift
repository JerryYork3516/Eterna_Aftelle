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
                printHelp()
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
                try runSourceProbe(request)
            case .vpa(let request):
                try runVPA(request)
            case .vpb(let request):
                try runVPB(request: request)
            case .record(let configuration):
                let outcome = try VP0AudioSession().run(configuration: configuration)
                try emitRecordOutcome(outcome)
            }
        } catch {
            let failure = EngineeringFailure.capture(error, stage: .command, code: .invalidArguments)
            emitFailure(failure)
            exit(2)
        }
    }

    private static func printHelp() {
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
            vp-b --authorize-vp-b --target-registration <existing-private-json> \
            --enable-audio --arm-diagnostics --mode VP_OFF|VP_ON --duration 16 \
            --study-id <non-private-alias> --output-dir <new-private-directory-outside-Git>
            VP-B requires a visible native prompt and separate site consent; no resident playback.
            vp-a --authorize-vp-a --target-registration <existing-private-json> \
            --enable-audio --arm-diagnostics --mode VP_OFF|VP_ON --duration 16 \
            --material <fixed-8s-PCM> --material-sha256 <preapproved-file-SHA256> \
            --material-pcm-sha256 <preapproved-native-PCM-SHA256> \
            --study-id <non-private-alias> --output-dir <new-private-directory-outside-Git>
            record --enable-audio --arm-diagnostics --mode VP_OFF|VP_ON \
            --duration <seconds <= 60> --study-id <non-private-alias> \
            --output-dir <new-private-directory-outside-Git> [--material <registered-PCM-file>]
            Device recording requires separate controller authorization. No Runtime authority is granted.
            """)
    }

    private static func runSourceProbe(_ request: SourceProbeRequest) throws {
        let outcome = try SourceProbe().run(request: request)
        print("source_status=SOURCE_UNVERIFIED source_qualification=false evidence=\(outcome.status)")
        print("input_records=\(outcome.inputWrittenRecords) input_frames=\(outcome.inputWrittenFrames)")
    }

    private static func runVPA(_ request: VPARequest) throws {
        let session = VP0AudioSession()
        let outcome = try session.runVPA(request: request)
        print("vp_a_source=SOURCE_UNVERIFIED source_qualification=false evidence=\(outcome.status)")
    }

    @MainActor
    private static func runVPB(request: VPBRequest) throws {
        try request.validate()
        let prompt = VPBPrompt()
        defer { prompt.close() }
        let confirmed = try prompt.confirm(mode: request.configuration.mode)
        let outcome = try VPBSession().run(request: request, preflight: confirmed, prompt: prompt)
        print("vp_b_evidence=\(outcome.status) content=EVIDENCE_UNVERIFIED source_qualification=false")
    }

    private static func emitRecordOutcome(_ outcome: AudioRunOutcome) throws {
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
