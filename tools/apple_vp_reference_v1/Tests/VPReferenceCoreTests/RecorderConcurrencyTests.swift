import Foundation
import VPRecorder
import XCTest

final class RecorderConcurrencyTests: XCTestCase {
    func testContentionIsOneNonwaitingRejection() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        XCTAssertTrue(vp_recorder_fixture_hold_admission(fixture.recorder, true))
        XCTAssertFalse(fixture.submit(fixture.identity()))
        XCTAssertTrue(vp_recorder_fixture_hold_admission(fixture.recorder, false))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(snapshot.reserved_records, 0)
        XCTAssertEqual(snapshot.lost_records, 1)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_CONTENTION), 0)
        XCTAssertTrue(fixture.validate().complete)
    }

    func testConcurrentInvalidationAndSealAgreeWithImmutableEvidence() throws {
        for _ in 0..<32 {
            let fixture = try RecorderFixture()
            try fixture.arm()
            XCTAssertTrue(fixture.submit(fixture.identity()))
            let address = UInt(bitPattern: fixture.recorder)
            let start = DispatchSemaphore(value: 0)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                start.wait()
                vp_recorder_invalidate(OpaquePointer(bitPattern: address), UInt32(VP_INVALID_ABORT))
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                start.wait()
                vp_recorder_seal(OpaquePointer(bitPattern: address))
                group.leave()
            }
            start.signal()
            start.signal()
            XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
            let sealed = vp_recorder_snapshot(fixture.recorder)
            let validated = fixture.validate()
            XCTAssertTrue(sealed.sealed)
            XCTAssertTrue(validated.complete)
            XCTAssertEqual(sealed.invalid_reasons, validated.invalid_reasons)
            vp_recorder_invalidate(fixture.recorder, UInt32(VP_INVALID_LAYOUT))
            let after = vp_recorder_snapshot(fixture.recorder)
            XCTAssertEqual(after.invalid_reasons, sealed.invalid_reasons)
            XCTAssertEqual(after.lost_records, sealed.lost_records)
            XCTAssertEqual(fixture.validate().invalid_reasons, sealed.invalid_reasons)
        }
    }

    func testConcurrentProducersAndSealPreserveCountConservation() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        let address = UInt(bitPattern: fixture.recorder)
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        for stream in [UInt32(VP_STREAM_INPUT), UInt32(VP_STREAM_RENDER)] {
            group.enter()
            DispatchQueue.global().async {
                start.wait()
                guard let pointer = OpaquePointer(bitPattern: address) else {
                    group.leave()
                    return
                }
                var identity = VPFrameIdentity()
                identity.stream_kind = stream
                identity.frame_count = 32_768
                identity.format = RecorderFixture.nativeMonoFormat
                identity.callback_enter_tick = 1_025
                let bytes = Array(repeating: UInt8(17), count: 128 * 1_024)
                bytes.withUnsafeBytes { buffer in
                    for _ in 0..<64 {
                        vp_recorder_submit_synthetic(pointer, &identity, buffer.baseAddress, UInt32(buffer.count))
                    }
                }
                group.leave()
            }
        }
        group.enter()
        DispatchQueue.global().async {
            start.wait()
            vp_recorder_seal(OpaquePointer(bitPattern: address))
            group.leave()
        }
        for _ in 0..<3 { start.signal() }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(
            snapshot.reserved_records,
            snapshot.written_records + snapshot.discarded_records + snapshot.pending_records)
        XCTAssertEqual(snapshot.pending_records, 0)
        XCTAssertEqual(snapshot.reserved_pcm_bytes, snapshot.written_pcm_bytes)
        XCTAssertTrue(fixture.validate().complete)
        XCTAssertEqual(fixture.validate().invalid_reasons, snapshot.invalid_reasons)
    }
}
