import AVFoundation
import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class SourceProbeEvidenceTests: XCTestCase {
    func testThreeNativePlanesAndBytesSurviveProbeSealWithoutRoles() throws {
        let fixture = try SourceProbeFixture()
        XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
        XCTAssertTrue(fixture.submitThreeChannels())
        let outcome = try fixture.finish()
        XCTAssertTrue(outcome.isCompleteForReference)
        XCTAssertEqual(outcome.writtenPCMBytes, 48)
        XCTAssertEqual(fixture.manifest.terminalStatus, "PROBE_SEALED_SOURCE_UNVERIFIED")
        var identity = VPFrameIdentity()
        var buffers: UInt32 = 0
        var bytes: UInt64 = 0
        let evidence = fixture.directory.appendingPathComponent("evidence.vp0")
        XCTAssertTrue(evidence.path.withCString { vp_recorder_read_identity($0, 0, &identity, &buffers, &bytes) })
        XCTAssertEqual(identity.format.mChannelsPerFrame, 3)
        XCTAssertEqual(buffers, 3)
        XCTAssertEqual(bytes, 48)
        let values: [Float] = [1, 2, 3, 4, -5, -6, -7, -8, 9, 10, 11, 12]
        let payload = values.withUnsafeBytes { Data($0) }
        XCTAssertNotNil(try Data(contentsOf: evidence).range(of: payload))
        XCTAssertEqual(fixture.manifest.sourceProbe?.sourceStatus, "SOURCE_UNVERIFIED")
        XCTAssertEqual(fixture.manifest.sourceProbe?.sourceQualificationGranted, false)
        XCTAssertEqual(fixture.manifest.sourceProbe?.inputObservation, "INPUT_PCM_PRESENT")
    }

    func testEveryKnownRecorderFailureCannotBecomeValidSourceEvidence() throws {
        for reason in [
            VP_INVALID_TIME, VP_INVALID_BYTE_LIMIT, VP_INVALID_OVERFLOW, VP_INVALID_CONTENTION, VP_INVALID_WRITE
        ] {
            let fixture = try SourceProbeFixture()
            XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
            XCTAssertTrue(fixture.submitThreeChannels())
            vp_recorder_invalidate(fixture.recorder.handle, UInt32(reason))
            XCTAssertThrowsError(try fixture.finish())
            XCTAssertEqual(fixture.manifest.terminalStatus, "INVALID")
            XCTAssertEqual(fixture.manifest.sourceProbe?.sourceStatus, "SOURCE_UNVERIFIED")
            XCTAssertEqual(fixture.manifest.sourceProbe?.sourceQualificationGranted, false)
            XCTAssertEqual(vp_recorder_snapshot(fixture.recorder.handle).pending_records, 0)
        }
    }

    func testEightSecondAdmissionRejectsLateFrameWithTimeInvalid() throws {
        let fixture = try SourceProbeFixture()
        XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
        XCTAssertFalse(fixture.submitThreeChannels(tick: fixture.startTick + vp_recorder_ticks_for_seconds(8) + 1))
        XCTAssertThrowsError(try fixture.finish())
        XCTAssertNotEqual(vp_recorder_snapshot(fixture.recorder.handle).invalid_reasons & UInt32(VP_INVALID_TIME), 0)
        XCTAssertLessThanOrEqual(
            vp_recorder_snapshot(fixture.recorder.handle).resident_bytes, UInt64(8 * 1024 * 1024))
    }

    func testNormalRecorderBudgetStillAllowsFramePastEightSeconds() throws {
        let fixture = try SourceProbeFixture(maximumSeconds: UInt32(VP_MAX_SECONDS))
        XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
        XCTAssertTrue(fixture.submitThreeChannels(tick: fixture.startTick + vp_recorder_ticks_for_seconds(9)))
        XCTAssertNoThrow(try fixture.finish())
    }

    func testEvidenceWriteFailureCannotReplaceOriginalCause() throws {
        let fixture = try SourceProbeFixture()
        XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
        XCTAssertTrue(fixture.submitThreeChannels())
        fixture.manifest.diagnostics.record(EngineeringDiagnostic(stage: .engineStart, code: .engineStartFailed))
        vp_recorder_invalidate(fixture.recorder.handle, UInt32(VP_INVALID_ABORT))
        try Data("synthetic existing manifest".utf8).write(
            to: fixture.directory.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try fixture.finish()) { error in
            let failure = error as? EngineeringFailure
            XCTAssertEqual(failure?.diagnostic.code, "ENGINE_START_FAILED")
            XCTAssertTrue(failure?.secondary.contains(where: { $0.code == "FINAL_WRITE_FAILED" }) == true)
        }
        XCTAssertTrue(vp_recorder_snapshot(fixture.recorder.handle).sealed)
    }

    func testNoInputCannotClaimProbeSuccess() throws {
        let fixture = try SourceProbeFixture()
        XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
        XCTAssertThrowsError(try fixture.finish())
        XCTAssertEqual(fixture.manifest.terminalStatus, "INVALID")
        XCTAssertEqual(fixture.manifest.sourceProbe?.inputObservation, "NOT_MEASURED")
    }
}
