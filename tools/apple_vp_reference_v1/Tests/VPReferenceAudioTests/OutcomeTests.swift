import VPRecorder
import XCTest

@testable import VPReferenceAudio

final class OutcomeTests: XCTestCase {
    func testZeroInputFramesCannotBeComplete() {
        var snapshot = validSnapshot()
        snapshot.input_written_frames = 0
        let result = outcome(snapshot: snapshot)
        XCTAssertFalse(result.isCompleteForReference)
        XCTAssertEqual(result.coverageStatus, "INCOMPLETE")
    }

    func testMaterialRequiresRenderFrames() {
        let result = outcome(snapshot: validSnapshot(), expectsRender: true)
        XCTAssertFalse(result.isCompleteForReference)
        XCTAssertEqual(result.coverageStatus, "INCOMPLETE")
    }

    func testResidentSilentDoesNotRequireRenderFrames() {
        let result = outcome(snapshot: validSnapshot())
        XCTAssertTrue(result.isCompleteForReference)
        XCTAssertEqual(result.coverageStatus, "MINIMUM_STREAM_PRESENCE")
    }

    func testFailedSealCannotBeComplete() {
        let result = outcome(snapshot: validSnapshot(), sealSucceeded: false)
        XCTAssertFalse(result.isCompleteForReference)
        XCTAssertEqual(result.integrityStatus, "INVALID")
    }

    func testMissingTimestampValidityCannotClaimVerifiedTiming() {
        var snapshot = validSnapshot()
        snapshot.missing_sample_time_records = 1
        snapshot.missing_host_time_records = 1
        snapshot.continuity_unknown_records = 1
        XCTAssertEqual(outcome(snapshot: snapshot).timestampStatus, "UNVERIFIED")
    }

    func testFileCounterMismatchCannotBeComplete() {
        let snapshot = validSnapshot()
        var file = validFile(snapshot: snapshot)
        file.pcm_bytes += 1
        let result = AudioRunOutcome(snapshot: snapshot, file: file, expectsRender: false, controlSealSucceeded: true)
        XCTAssertFalse(result.isCompleteForReference)
    }

    private func outcome(
        snapshot: VPRecorderSnapshot, expectsRender: Bool = false, sealSucceeded: Bool = true
    ) -> AudioRunOutcome {
        AudioRunOutcome(
            snapshot: snapshot, file: validFile(snapshot: snapshot),
            expectsRender: expectsRender, controlSealSucceeded: sealSucceeded
        )
    }

    private func validSnapshot() -> VPRecorderSnapshot {
        var snapshot = VPRecorderSnapshot()
        snapshot.sealed = true
        snapshot.written_records = 1
        snapshot.written_pcm_bytes = 4
        snapshot.input_written_records = 1
        snapshot.input_written_frames = 1
        return snapshot
    }

    private func validFile(snapshot: VPRecorderSnapshot) -> VPFileValidation {
        var file = VPFileValidation()
        file.complete = true
        file.checksum_matches = true
        file.record_count = snapshot.written_records
        file.pcm_bytes = snapshot.written_pcm_bytes
        file.invalid_reasons = snapshot.invalid_reasons
        return file
    }
}
