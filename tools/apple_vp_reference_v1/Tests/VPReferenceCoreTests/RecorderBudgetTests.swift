import Darwin
import Foundation
import VPRecorder
import XCTest

final class RecorderBudgetTests: XCTestCase {
    func testBudgetClockUsesContinuousMachTimeDomain() {
        let before = mach_continuous_time()
        let observed = vp_recorder_now_tick()
        let after = mach_continuous_time()
        XCTAssertGreaterThanOrEqual(observed, before)
        XCTAssertLessThanOrEqual(observed, after)
        XCTAssertGreaterThan(vp_recorder_ticks_for_seconds(60), 0)
    }

    func testHardDefaultsAndResidentCertificate() {
        let config = vp_recorder_default_config()
        XCTAssertEqual(config.maximum_seconds, 60)
        XCTAssertEqual(config.maximum_pcm_bytes, 64 * 1_024 * 1_024)
        XCTAssertFalse(config.fixture_mode)
        XCTAssertLessThanOrEqual(vp_recorder_resident_bytes(), 8 * 1_024 * 1_024)
        XCTAssertGreaterThan(vp_recorder_resident_bytes(), 32 * 128 * 1_024)
    }

    func testRejectsLimitsAboveHardMaximumBeforeCreatingDirectory() {
        for change in [0, 1] {
            var config = vp_recorder_default_config()
            if change == 0 { config.maximum_seconds = 61 }
            if change == 1 { config.maximum_pcm_bytes += 1 }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("vp0-limit-\(UUID().uuidString)")
            var errorCode: Int32 = 0
            let recorder = directory.path.withCString { vp_recorder_create($0, &config, &errorCode) }
            XCTAssertNil(recorder)
            XCTAssertNotEqual(errorCode, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
    }

    func testSixtySecondBoundaryAndSingleTickOverflow() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        let boundary = fixture.startTick + vp_recorder_ticks_for_seconds(60)
        XCTAssertTrue(fixture.submit(fixture.identity(tick: boundary)))
        XCTAssertFalse(fixture.submit(fixture.identity(sample: 4, tick: boundary + 1)))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(snapshot.written_pcm_bytes, 16)
        XCTAssertEqual(snapshot.lost_records, 1)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_TIME), 0)
    }

    func testExactSixtyFourMiBAggregateAndOneMoreFrameIsRejected() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        let bytes = Array(repeating: UInt8(31), count: 128 * 1_024)
        let frames: UInt32 = 2_048
        for index in 0..<512 {
            var identity = fixture.identity(frames: frames, sample: Int64(index) * Int64(frames))
            identity.format.mSampleRate = 384_000
            identity.format.mChannelsPerFrame = 16
            identity.format.mBytesPerFrame = 64
            identity.format.mBytesPerPacket = 64
            XCTAssertTrue(fixture.submit(identity, bytes: bytes))
            try fixture.waitForWritten(UInt64(index + 1))
        }
        var excess = fixture.identity(frames: 1, sample: 512 * Int64(frames))
        excess.format.mSampleRate = 384_000
        excess.format.mChannelsPerFrame = 16
        excess.format.mBytesPerFrame = 64
        excess.format.mBytesPerPacket = 64
        XCTAssertFalse(fixture.submit(excess, bytes: Array(repeating: 0, count: 64)))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(snapshot.reserved_pcm_bytes, 64 * 1_024 * 1_024)
        XCTAssertEqual(snapshot.written_pcm_bytes, snapshot.reserved_pcm_bytes)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_BYTE_LIMIT), 0)
        XCTAssertTrue(fixture.validate().complete)
    }

    func testInputAndRenderShareOneByteBudget() throws {
        let fixture = try RecorderFixture { $0.maximum_pcm_bytes = 32 }
        try fixture.arm()
        XCTAssertTrue(fixture.submit(fixture.identity()))
        XCTAssertTrue(fixture.submit(fixture.identity(stream: UInt32(VP_STREAM_RENDER))))
        XCTAssertFalse(fixture.submit(fixture.identity(sample: 4)))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder).written_pcm_bytes, 32)
        XCTAssertEqual(fixture.validate().record_count, 2)
    }

    func testRingOverflowRejectsWholeRecordAndRetainsAdmittedEvidence() throws {
        let fixture = try RecorderFixture { $0.fixture_pause_writer = true }
        try fixture.arm()
        for index in 0..<32 {
            XCTAssertTrue(fixture.submit(fixture.identity(sample: Int64(index) * 4)))
        }
        XCTAssertFalse(fixture.submit(fixture.identity(sample: 128)))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(snapshot.reserved_records, 32)
        XCTAssertEqual(snapshot.written_records, 32)
        XCTAssertEqual(snapshot.overflow_records, 1)
        XCTAssertEqual(snapshot.lost_records, 1)
        XCTAssertEqual(snapshot.pending_records, 0)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_OVERFLOW), 0)
        XCTAssertTrue(fixture.validate().complete)
    }

    func testOversizeNativeCallbackRejectsWholePayload() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        let bytes = Array(repeating: UInt8(0), count: 128 * 1_024 + 4)
        let identity = fixture.identity(frames: UInt32(bytes.count / 4))
        XCTAssertFalse(fixture.submit(identity, bytes: bytes))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(snapshot.reserved_pcm_bytes, 0)
        XCTAssertEqual(snapshot.lost_records, 1)
        XCTAssertEqual(snapshot.overflow_records, 1)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_OVERFLOW), 0)
    }
}
