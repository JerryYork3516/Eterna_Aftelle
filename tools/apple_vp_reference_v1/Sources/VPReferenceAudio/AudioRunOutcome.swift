import Foundation
import VPRecorder

public struct AudioRunOutcome: Codable {
    public let isCompleteForReference: Bool
    public let controlSealSucceeded: Bool
    public let status: String
    public let integrityStatus: String
    public let coverageStatus: String
    public let timestampStatus: String
    public let sealed: Bool
    public let writtenRecords: UInt64
    public let writtenPCMBytes: UInt64
    public let lostRecords: UInt64
    public let overflowRecords: UInt64
    public let pendingRecords: UInt64
    public let invalidReasons: UInt32
    public let residentBytes: UInt64
    public let inputWrittenRecords: UInt64
    public let inputWrittenFrames: UInt64
    public let renderWrittenRecords: UInt64
    public let renderWrittenFrames: UInt64
    public let suppressedRecords: UInt64
    public let discardedRecords: UInt64
    public let missingSampleTimeRecords: UInt64
    public let missingHostTimeRecords: UInt64
    public let continuityUnknownRecords: UInt64

    init(
        snapshot: VPRecorderSnapshot, file: VPFileValidation,
        expectsRender: Bool, controlSealSucceeded: Bool
    ) {
        let intact =
            controlSealSucceeded && snapshot.sealed && file.complete && file.checksum_matches
            && file.record_count == snapshot.written_records && file.pcm_bytes == snapshot.written_pcm_bytes
            && file.invalid_reasons == snapshot.invalid_reasons
        let covered = snapshot.input_written_frames > 0 && (!expectsRender || snapshot.render_written_frames > 0)
        self.controlSealSucceeded = controlSealSucceeded
        isCompleteForReference = intact && covered && snapshot.invalid_reasons == 0
        integrityStatus = intact ? "VERIFIED" : "INVALID"
        coverageStatus = covered ? "MINIMUM_STREAM_PRESENCE" : "INCOMPLETE"
        timestampStatus =
            snapshot.missing_sample_time_records == 0 && snapshot.missing_host_time_records == 0
                && snapshot.continuity_unknown_records == 0 ? "RAW_TIMESTAMPS_RECORDED" : "UNVERIFIED"
        status = intact && covered && snapshot.invalid_reasons == 0 ? "SEALED_EVIDENCE" : "INVALID"
        sealed = snapshot.sealed
        writtenRecords = snapshot.written_records
        writtenPCMBytes = snapshot.written_pcm_bytes
        lostRecords = snapshot.lost_records
        overflowRecords = snapshot.overflow_records
        pendingRecords = snapshot.pending_records
        invalidReasons = snapshot.invalid_reasons
        residentBytes = snapshot.resident_bytes
        inputWrittenRecords = snapshot.input_written_records
        inputWrittenFrames = snapshot.input_written_frames
        renderWrittenRecords = snapshot.render_written_records
        renderWrittenFrames = snapshot.render_written_frames
        suppressedRecords = snapshot.suppressed_records
        discardedRecords = snapshot.discarded_records
        missingSampleTimeRecords = snapshot.missing_sample_time_records
        missingHostTimeRecords = snapshot.missing_host_time_records
        continuityUnknownRecords = snapshot.continuity_unknown_records
    }
}
