import Foundation
import VPRecorder
import XCTest

final class RecorderFailureTests: XCTestCase {
    func testWriteFailureAccountsForDiscardedAdmissions() throws {
        let fixture = try RecorderFixture {
            $0.fixture_pause_writer = true
            $0.fixture_write_failure_after_bytes = 100
        }
        try fixture.arm()
        XCTAssertTrue(fixture.submit(fixture.identity()))
        XCTAssertTrue(fixture.submit(fixture.identity(sample: 4)))
        XCTAssertFalse(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertTrue(snapshot.writer_failure)
        XCTAssertEqual(snapshot.reserved_records, 2)
        XCTAssertEqual(snapshot.written_records, 0)
        XCTAssertEqual(snapshot.discarded_records, 2)
        XCTAssertEqual(snapshot.pending_records, 0)
        XCTAssertEqual(snapshot.lost_records, 0)
        XCTAssertFalse(vp_recorder_arm(fixture.recorder, fixture.startTick))
        XCTAssertFalse(fixture.validate().complete)
    }

    func testEvidenceSyncFailureCannotLeaveSuccessfulSealReceipt() throws {
        let fixture = try RecorderFixture { $0.fixture_evidence_sync_failure = true }
        try fixture.arm()
        XCTAssertTrue(fixture.submit(fixture.identity()))
        XCTAssertFalse(vp_recorder_seal(fixture.recorder))
        XCTAssertTrue(vp_recorder_snapshot(fixture.recorder).writer_failure)
        XCTAssertFalse(fixture.validate().complete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.evidence.path + ".seal"))
    }

    func testMissingSealAndTruncatedEvidenceCannotBeComplete() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        XCTAssertTrue(fixture.submit(fixture.identity()))
        try fixture.waitForWritten(1)
        XCTAssertFalse(fixture.validate().complete)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertTrue(fixture.validate().complete)
        let handle = try FileHandle(forWritingTo: fixture.evidence)
        try handle.truncate(atOffset: 20)
        try handle.close()
        XCTAssertFalse(fixture.validate().complete)
    }

    func testSealFreezesCountsAndRejectsNewAdmission() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        XCTAssertTrue(fixture.submit(fixture.identity()))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let before = vp_recorder_snapshot(fixture.recorder)
        XCTAssertFalse(fixture.submit(fixture.identity(sample: 4)))
        let after = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(after.reserved_records, before.reserved_records)
        XCTAssertEqual(after.lost_records, before.lost_records)
        XCTAssertEqual(after.suppressed_records, before.suppressed_records)
        XCTAssertTrue(fixture.validate().complete)
    }

    func testBodyAndFooterTamperingFailsWholeFileIntegrity() throws {
        let invalidOffset = try XCTUnwrap(MemoryLayout<VPRecorderSnapshot>.offset(of: \.invalid_reasons))
        let lostOffset = try XCTUnwrap(MemoryLayout<VPRecorderSnapshot>.offset(of: \.lost_records))
        let validityOffset = try XCTUnwrap(
            MemoryLayout<VPRecorderSnapshot>.offset(of: \.missing_sample_time_records)
        )
        let timeOffset = try XCTUnwrap(MemoryLayout<VPRecorderSnapshot>.offset(of: \.first_callback_tick))
        for footerOffset in [0, 8, 24 + invalidOffset, 24 + lostOffset, 24 + validityOffset, 24 + timeOffset] {
            let fixture = try RecorderFixture()
            try fixture.arm()
            XCTAssertTrue(fixture.submit(fixture.identity()))
            XCTAssertTrue(vp_recorder_seal(fixture.recorder))
            var data = try Data(contentsOf: fixture.evidence)
            let footerMagic = Data([0x56, 0x56, 0x50, 0x53, 0x45, 0x41, 0x4c, 0x31])
            let range = try XCTUnwrap(data.range(of: footerMagic, options: .backwards))
            data[range.lowerBound + footerOffset] ^= 1
            try data.write(to: fixture.evidence)
            XCTAssertFalse(fixture.validate().complete)
        }
    }

    func testNativeTimestampTamperingFailsRecordIntegrity() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        let original: Int64 = 345_678_901_234
        XCTAssertTrue(fixture.submit(fixture.identity(sample: original)))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        var data = try Data(contentsOf: fixture.evidence)
        var nativeSample = original.littleEndian
        let pattern = withUnsafeBytes(of: &nativeSample) { Data($0) }
        let range = try XCTUnwrap(data.range(of: pattern))
        data[range.lowerBound] ^= 1
        try data.write(to: fixture.evidence)
        XCTAssertFalse(fixture.validate().complete)
        XCTAssertFalse(fixture.validate().checksum_matches)
    }

    func testPrivatePermissionsAndExistingDirectoryRejection() throws {
        let fixture = try RecorderFixture()
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fixture.evidence.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        var config = vp_recorder_default_config()
        var errorCode: Int32 = 0
        XCTAssertNil(fixture.directory.path.withCString { vp_recorder_create($0, &config, &errorCode) })
        XCTAssertNotEqual(errorCode, 0)
    }
}
