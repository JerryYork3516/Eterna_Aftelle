import Darwin
import Foundation
import VPRecorder
import VPReferenceCore

@main
enum ReferenceTool {
    static func main() {
        do {
            switch try CommandLinePlan.parse(Array(CommandLine.arguments.dropFirst())) {
            case .help:
                print(
                    """
                    Apple VP reference v1: diagnostics and audio are OFF by default.
                    help
                    verify <private-evidence-directory>
                    record --enable-audio --arm-diagnostics --mode VP_OFF|VP_ON \
                    --duration <seconds <= 60> --study-id <non-private-alias> \
                    --output-dir <new-private-directory-outside-Git> [--material <registered-PCM-file>]
                    Device recording requires separate controller authorization. No Runtime authority is granted.
                    """)
            case .verify(let directory):
                verify(directory: directory)
            case .record(let configuration):
                let outcome = try VP0AudioSession().run(configuration: configuration)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(outcome)
                guard let summary = String(data: data, encoding: .utf8) else {
                    throw ReferenceFailure.blocked("Summary encoding failed")
                }
                print(summary)
                if !outcome.isCompleteForReference { exit(1) }
            }
        } catch ReferenceFailure.blocked(let reason) {
            fputs("BLOCKED: \(reason)\n", stderr)
            exit(2)
        } catch {
            // Keep source paths and hardware identifiers out of terminal diagnostics.
            fputs("BLOCKED: configuration, permission, recording, or private evidence failed\n", stderr)
            exit(2)
        }
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
