import Foundation
import VPRecorder
import VPReferenceCore

enum VPACoverageFile {
    // Bounded offline header traversal through the existing C reader, never a callback operation.
    static let maximumRecords: UInt64 = 4_096

    static func evaluate(directory: URL, clockPairs: [VPAClockPair]) -> VPAWindowCoverage {
        var proof = VPAWindowCoverage(clockPairs: clockPairs)
        let path = directory.appendingPathComponent("evidence.vp0").path
        let validation = path.withCString { vp_recorder_validate_file($0) }
        guard validation.complete, validation.checksum_matches, validation.invalid_reasons == 0,
            permits(recordCount: validation.record_count)
        else {
            proof.reject("SEALED_FILE_INVALID_OR_RECORD_LIMIT")
            return proof
        }
        for index in 0..<validation.record_count {
            var identity = VPFrameIdentity()
            var buffers: UInt32 = 0
            var bytes: UInt64 = 0
            let read = path.withCString { vp_recorder_read_identity($0, index, &identity, &buffers, &bytes) }
            guard read else {
                proof.reject("FRAME_HEADER_UNAVAILABLE")
                return proof
            }
            proof.include(identity)
        }
        let final = path.withCString { vp_recorder_validate_file($0) }
        guard final.complete, final.checksum_matches, final.invalid_reasons == 0,
            final.record_count == validation.record_count, final.pcm_bytes == validation.pcm_bytes
        else {
            proof.reject("SEALED_FILE_CHANGED_OR_INVALID")
            return proof
        }
        proof.finish(expectedRecords: validation.record_count)
        return proof
    }

    static func permits(recordCount: UInt64) -> Bool {
        recordCount > 0 && recordCount <= maximumRecords
    }
}
