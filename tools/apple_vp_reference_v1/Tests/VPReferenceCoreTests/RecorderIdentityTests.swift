import AudioToolbox
import Foundation
import VPRecorder
import XCTest

final class RecorderIdentityTests: XCTestCase {
    func testPreArmInvalidationCannotReopenAdmission() throws {
        let fixture = try RecorderFixture()
        vp_recorder_invalidate(fixture.recorder, UInt32(VP_INVALID_FORMAT))
        XCTAssertFalse(vp_recorder_arm(fixture.recorder, fixture.startTick))
        XCTAssertFalse(fixture.submit(fixture.identity()))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertFalse(snapshot.armed)
        XCTAssertFalse(snapshot.accepting)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_FORMAT), 0)
        XCTAssertEqual(snapshot.reserved_records, 0)
    }

    func testArmIsOneShotAndSealCannotBeRearmed() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        XCTAssertFalse(vp_recorder_arm(fixture.recorder, fixture.startTick))
        XCTAssertTrue(fixture.submit(fixture.identity()))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertFalse(vp_recorder_arm(fixture.recorder, fixture.startTick))
        XCTAssertFalse(vp_recorder_snapshot(fixture.recorder).accepting)
    }

    func testFailedArmCannotRetryWithAnotherClock() throws {
        let fixture = try RecorderFixture()
        XCTAssertFalse(vp_recorder_arm(fixture.recorder, 0))
        XCTAssertFalse(vp_recorder_arm(fixture.recorder, fixture.startTick))
        XCTAssertFalse(fixture.submit(fixture.identity()))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertFalse(snapshot.armed)
        XCTAssertFalse(snapshot.accepting)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_CLOCK), 0)
    }

    func testDefaultIsUnarmedAndRejectsRecording() throws {
        let fixture = try RecorderFixture()
        XCTAssertFalse(fixture.submit(fixture.identity()))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertFalse(snapshot.armed)
        XCTAssertFalse(snapshot.accepting)
        XCTAssertEqual(snapshot.reserved_records, 0)
        XCTAssertEqual(snapshot.lost_records, 0)
        XCTAssertFalse(fixture.validate().complete)
    }

    func testNativeIdentityAndMissingValiditySurviveSeal() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        var first = fixture.identity()
        first.source_range_valid = true
        first.source_start_frame = 120
        first.source_frame_count = 4
        XCTAssertTrue(fixture.submit(first))
        var missing = fixture.identity(sample: 4)
        missing.sample_time_valid = false
        missing.host_time_valid = false
        missing.sample_time = -77
        missing.host_time = 0
        XCTAssertTrue(fixture.submit(missing))
        XCTAssertTrue(fixture.submit(fixture.identity(sample: 99)))
        XCTAssertTrue(fixture.submit(fixture.identity(stream: UInt32(VP_STREAM_RENDER))))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(snapshot.written_records, 4)
        XCTAssertEqual(snapshot.written_pcm_bytes, 64)
        XCTAssertEqual(snapshot.input_written_frames, 12)
        XCTAssertEqual(snapshot.render_written_frames, 4)
        XCTAssertEqual(snapshot.missing_sample_time_records, 1)
        XCTAssertEqual(snapshot.missing_host_time_records, 1)
        XCTAssertEqual(snapshot.continuity_unknown_records, 4)
        XCTAssertEqual(snapshot.pending_records, 0)
        XCTAssertEqual(snapshot.invalid_reasons, 0)
        XCTAssertTrue(fixture.validate().complete)
        var readback = VPFrameIdentity()
        var buffers: UInt32 = 0
        var bytes: UInt64 = 0
        XCTAssertTrue(
            fixture.evidence.path.withCString {
                vp_recorder_read_identity($0, 1, &readback, &buffers, &bytes)
            })
        XCTAssertFalse(readback.sample_time_valid)
        XCTAssertFalse(readback.host_time_valid)
        XCTAssertEqual(readback.sample_time, -77)
        XCTAssertEqual(readback.host_time, 0)
        XCTAssertEqual(readback.format.mSampleRate, 48_000)
        XCTAssertEqual(buffers, 1)
        XCTAssertEqual(bytes, 16)
    }

    func testSampleDiscontinuityInvalidatesWithoutInventingSamples() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        XCTAssertTrue(fixture.submit(fixture.identity()))
        XCTAssertFalse(fixture.submit(fixture.identity(sample: 9)))
        XCTAssertFalse(fixture.submit(fixture.identity(sample: 13)))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(snapshot.reserved_records, 1)
        XCTAssertEqual(snapshot.lost_records, 2)
        XCTAssertEqual(snapshot.suppressed_records, 1)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_DISCONTINUITY), 0)
        XCTAssertTrue(fixture.validate().complete)
        XCTAssertNotEqual(fixture.validate().invalid_reasons, 0)
    }

    func testChangedNativeFormatInvalidatesWithoutConversion() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        XCTAssertTrue(fixture.submit(fixture.identity()))
        var changed = fixture.identity(sample: 4)
        changed.format.mSampleRate = 44_100
        XCTAssertFalse(fixture.submit(changed))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertNotEqual(vp_recorder_snapshot(fixture.recorder).invalid_reasons & UInt32(VP_INVALID_FORMAT), 0)
        XCTAssertEqual(fixture.validate().pcm_bytes, 16)
    }

    func testPlanarNativeBuffersRemainSeparate() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        var identity = fixture.identity()
        identity.format.mChannelsPerFrame = 2
        identity.format.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
        let buffers = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(buffers.unsafeMutablePointer) }
        buffers.unsafeMutablePointer.pointee.mNumberBuffers = 2
        var left: [Float] = [1, 2, 3, 4]
        var right: [Float] = [5, 6, 7, 8]
        let accepted = left.withUnsafeMutableBytes { leftBytes in
            right.withUnsafeMutableBytes { rightBytes in
                buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: leftBytes.baseAddress)
                buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: rightBytes.baseAddress)
                return vp_recorder_submit(fixture.recorder, &identity, buffers.unsafePointer)
            }
        }
        XCTAssertTrue(accepted)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertEqual(fixture.validate().pcm_bytes, 32)
        var readback = VPFrameIdentity()
        var count: UInt32 = 0
        var bytes: UInt64 = 0
        XCTAssertTrue(
            fixture.evidence.path.withCString {
                vp_recorder_read_identity($0, 0, &readback, &count, &bytes)
            })
        XCTAssertEqual(count, 2)
        XCTAssertEqual(readback.format.mChannelsPerFrame, 2)
        XCTAssertEqual(bytes, 32)
    }
}
