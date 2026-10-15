import AudioToolbox
import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPACoverageFileTests: XCTestCase {
    func testSealedSyntheticFileProvesDigitalWindowSpans() throws {
        let fixture = try CoverageFixture()
        try fixture.write(through: 14_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let proof = VPACoverageFile.evaluate(directory: fixture.directory, clockPairs: fixture.pairs)
        XCTAssertTrue(proof.formalWindowsCovered)
        XCTAssertTrue(proof.windows.allSatisfy(\.covered))
    }

    func testNominalEndWithoutLaterHostAnchorCannotPass() throws {
        let fixture = try CoverageFixture()
        try fixture.write(through: 14_000)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let proof = VPACoverageFile.evaluate(directory: fixture.directory, clockPairs: fixture.pairs)
        XCTAssertFalse(proof.formalWindowsCovered)
    }

    func testPostRollCoverageDoesNotChangeFormalScoring() throws {
        let fixture = try CoverageFixture()
        try fixture.write(through: 14_100)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let proof = VPACoverageFile.evaluate(directory: fixture.directory, clockPairs: fixture.pairs)
        XCTAssertTrue(proof.formalWindowsCovered)
        XCTAssertFalse(proof.windows[3].covered)
    }

    func testMissingFileAndInvalidSealCannotGrantCoverage() throws {
        let fixture = try CoverageFixture()
        let missing = fixture.directory.appendingPathComponent("not-created")
        XCTAssertFalse(VPACoverageFile.evaluate(directory: missing, clockPairs: fixture.pairs).formalWindowsCovered)
        try fixture.write(through: 14_600)
        vp_recorder_invalidate(fixture.recorder, UInt32(VP_INVALID_ABORT))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertFalse(
            VPACoverageFile.evaluate(directory: fixture.directory, clockPairs: fixture.pairs).formalWindowsCovered)
    }

    func testTruncatedSyntheticFileRemainsUnverified() throws {
        let fixture = try CoverageFixture()
        try fixture.write(through: 14_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let file = fixture.directory.appendingPathComponent("evidence.vp0")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 100)
        try handle.close()
        XCTAssertFalse(
            VPACoverageFile.evaluate(directory: fixture.directory, clockPairs: fixture.pairs).formalWindowsCovered)
    }

    func testOfflineTraversalHasExplicitFiniteRecordBound() {
        XCTAssertFalse(VPACoverageFile.permits(recordCount: 0))
        XCTAssertTrue(VPACoverageFile.permits(recordCount: 4_096))
        XCTAssertFalse(VPACoverageFile.permits(recordCount: 4_097))
    }

    func testCoverageReadDoesNotChangeSealedRecorder() throws {
        let fixture = try CoverageFixture()
        try fixture.write(through: 14_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let before = vp_recorder_snapshot(fixture.recorder)
        _ = VPACoverageFile.evaluate(directory: fixture.directory, clockPairs: fixture.pairs)
        let after = vp_recorder_snapshot(fixture.recorder)
        XCTAssertTrue(after.sealed)
        XCTAssertEqual(after.written_records, before.written_records)
        XCTAssertEqual(after.invalid_reasons, before.invalid_reasons)
        XCTAssertEqual(after.pending_records, 0)
    }
}

private final class CoverageFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vp-window-\(UUID().uuidString)")
    let recorder: OpaquePointer
    let start: UInt64 = 1_024
    var pairs: [VPAClockPair] {
        zip(VPAClockPair.Phase.allCases, [0, 1_000, 3_002, 11_004, 14_006, 14_508]).map {
            VPAClockPair(
                phase: $0.0, absoluteBeforeTick: UInt64($0.1), continuousTick: UInt64($0.1),
                absoluteAfterTick: UInt64($0.1 + 1), timebaseNumerator: 1_000_000, timebaseDenominator: 1)
        }
    }

    init() throws {
        var config = vp_recorder_default_config()
        config.fixture_mode = true
        var error: Int32 = 0
        recorder = try XCTUnwrap(directory.path.withCString { vp_recorder_create($0, &config, &error) })
        XCTAssertTrue(vp_recorder_arm(recorder, start))
    }

    deinit {
        vp_recorder_destroy(recorder)
        try? FileManager.default.removeItem(at: directory)
    }

    func write(through last: UInt64) throws {
        var count: UInt64 = 0
        var sample: Int64 = 0
        for host in stride(from: UInt64(900), through: last, by: 100) {
            for stream in [UInt32(VP_STREAM_INPUT), UInt32(VP_STREAM_RENDER)] {
                var identity = VPFrameIdentity()
                identity.stream_kind = stream
                identity.frame_count = 100
                identity.format = AudioStreamBasicDescription(
                    mSampleRate: 1_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: 9,
                    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                    mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
                identity.host_time_valid = true
                identity.sample_time_valid = true
                identity.host_time = host
                identity.sample_time = sample
                identity.callback_enter_tick = start + 1
                let accepted = Array(repeating: UInt8(0), count: 400).withUnsafeBytes {
                    vp_recorder_submit_synthetic(recorder, &identity, $0.baseAddress, UInt32($0.count))
                }
                XCTAssertTrue(accepted)
                count += 1
                let limit = Date().addingTimeInterval(5)
                while vp_recorder_snapshot(recorder).written_records < count {
                    if Date() >= limit { throw AudioReferenceError.recorderUnavailable }
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
            sample += 100
        }
    }
}
