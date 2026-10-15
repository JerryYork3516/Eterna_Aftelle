import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPCEvidenceTests: XCTestCase {
    func testDualStreamsAndThirdChannelOnlyRenderAreRetained() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write()
        XCTAssertTrue(fixture.owner.seal())
        let value = try read(fixture)
        XCTAssertEqual(value.status, "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT")
        XCTAssertEqual(value.inputChannels.count, 3)
        XCTAssertEqual(value.renderChannels.map(\.peak), [0, 0, 0.25])
        XCTAssertGreaterThan(value.renderPlayNonZeroSamples, 0)
        XCTAssertEqual(value.firstRenderSignal?.channel, 2)
    }

    func testZeroRenderAndQuietOnlyNoiseAreNotPlaybackEvidence() throws {
        for signal in ["zero", "quiet"] {
            let fixture = try VPCPCMFixture()
            try fixture.write(amplitude: signal == "zero" ? 0 : 0.25, signal: signal)
            XCTAssertTrue(fixture.owner.seal())
            let value = try read(fixture)
            XCTAssertEqual(value.renderPlayNonZeroSamples, 0)
            XCTAssertEqual(value.status, "UNVERIFIED")
        }
    }

    func testMissingEitherStreamIsNotValid() throws {
        for streams in [(true, false), (false, true)] {
            let fixture = try VPCPCMFixture()
            try fixture.write(input: streams.0, render: streams.1)
            XCTAssertTrue(fixture.owner.seal())
            XCTAssertEqual(try read(fixture).status, "UNVERIFIED")
        }
    }

    func testFormalTailMissingSuccessorCannotUseBufferEnd() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write(through: 14_000)
        XCTAssertTrue(fixture.owner.seal())
        XCTAssertEqual(try read(fixture).status, "UNVERIFIED")
    }

    func testPostRollIsIndependentAndCannotFillFormalScore() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write(through: 14_300)
        XCTAssertTrue(fixture.owner.seal())
        let value = try read(fixture)
        XCTAssertEqual(value.status, "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT")
        XCTAssertFalse(try XCTUnwrap(value.coverage.windows.last).covered)
    }

    func testNonFiniteRenderCannotCountAsPlaybackSuccess() throws {
        for amplitude in [Float.nan, .infinity] {
            let fixture = try VPCPCMFixture()
            try fixture.write(amplitude: amplitude)
            XCTAssertTrue(fixture.owner.seal())
            let value = try read(fixture)
            XCTAssertEqual(value.status, "UNVERIFIED")
            XCTAssertGreaterThan(value.renderChannels[2].nonFinite, 0)
        }
    }

    func testWrongArmTruncatedContainerAndInvalidSealReject() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write()
        XCTAssertTrue(fixture.owner.seal())
        XCTAssertThrowsError(
            try VPCPCMRead.evaluate(
                directory: fixture.directory, events: fixture.events, receipts: fixture.receipts, arm: fixture.arm + 1))
        let handle = try FileHandle(forWritingTo: fixture.directory.appendingPathComponent("evidence.vp0"))
        try handle.truncate(atOffset: 100)
        try handle.close()
        XCTAssertThrowsError(try read(fixture))
    }

    func testInvalidAndLateCallbackRemainInvalidAfterSingleSeal() throws {
        let fixture = try VPCPCMFixture()
        vp_recorder_invalidate(fixture.recorder, UInt32(VP_INVALID_ABORT))
        XCTAssertTrue(fixture.owner.seal())
        XCTAssertTrue(fixture.owner.seal())
        XCTAssertThrowsError(try read(fixture))
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder).pending_records, 0)
    }

    func testFirstFailureSurvivesActualCFinishAndManifestIsInvalid() throws {
        let fixture = try SourceProbeFixture(maximumSeconds: 16)
        fixture.manifest.diagnostics.record(EngineeringDiagnostic(stage: .engineStart, code: .engineStartFailed))
        vp_recorder_invalidate(fixture.recorder.handle, UInt32(VP_INVALID_ABORT))
        XCTAssertThrowsError(
            try VPCSession.finish(
                recorder: fixture.recorder, manifest: &fixture.manifest, directory: fixture.directory))
        XCTAssertEqual(fixture.manifest.diagnostics.primary?.code, FailureCode.engineStartFailed.rawValue)
        XCTAssertEqual(fixture.manifest.terminalStatus, "INVALID")
        XCTAssertTrue(vp_recorder_snapshot(fixture.recorder.handle).sealed)
    }

    func testFourDimensionsNeverAutomaticallyGrantAcousticResults() throws {
        let fixture = try SourceProbeFixture()
        let clock = VPBClock(
            id: "PREFLIGHT", absoluteBefore: 1, continuous: 10, absoluteAfter: 2,
            numerator: 1, denominator: 1)
        let receipt = VPBDisplayReceipt(
            cueID: "PREFLIGHT", requested: clock, displayed: clock,
            visible: true, userConfirmed: true)
        let evidence = VPCEvidence(
            preflight: receipt, registrationSHA256: String(repeating: "a", count: 64),
            materialSafety: nil, preConfigurationState: fixture.manifest.configured.state,
            preConfigurationFormats: fixture.manifest.configured.formats)
        XCTAssertEqual(evidence.engineeringValidity, "NOT_EVALUATED")
        XCTAssertEqual(evidence.physicalOverlapEvidence, "EVIDENCE_UNVERIFIED")
        XCTAssertEqual(evidence.nearEndPreservation, "EVIDENCE_UNVERIFIED")
        XCTAssertEqual(evidence.echoResidual, "EVIDENCE_UNVERIFIED")
        XCTAssertFalse(evidence.sourceQualificationGranted)
        XCTAssertTrue(VPCPrompt.localized("ready").contains("尚未录音"))
    }

    func testRenderOnlyInCrossTailBlockCannotProvePlayback() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write(signal: "crossTail")
        XCTAssertTrue(fixture.owner.seal())
        let value = try read(fixture)
        XCTAssertNotNil(value.firstRenderSignal)
        XCTAssertEqual(value.renderPlayNonZeroSamples, 0)
        XCTAssertEqual(value.status, "UNVERIFIED")
    }

    func testCompressedTailAndDoubleTalkCannotHideBehindFullThirteenSeconds() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write()
        XCTAssertTrue(fixture.owner.seal())
        for (index, cueIndex, name) in [(6, 4, "tail"), (4, 2, "doubleTalkCandidate")] {
            var events = fixture.events
            let old = events[index]
            events[index] = VPBClock(
                id: old.id, absoluteBefore: old.absoluteBefore + 200,
                continuous: old.continuous + 200, absoluteAfter: old.absoluteAfter + 200,
                numerator: old.numerator, denominator: old.denominator)
            var receipts = fixture.receipts
            let phase = VPCCue.allCases[cueIndex]
            receipts[cueIndex] = fixture.receipt(
                phase: phase,
                request: old.absoluteBefore + 202, display: old.absoluteBefore + 204)
            let value = try VPCPCMRead.evaluate(
                directory: fixture.directory, events: events,
                receipts: receipts, arm: fixture.arm)
            XCTAssertEqual(value.status, "UNVERIFIED")
            XCTAssertFalse(try XCTUnwrap(value.coverage.windows.first { $0.name == name }).minimumDurationVerified)
            XCTAssertTrue(try XCTUnwrap(value.coverage.windows.first { $0.name == "formal13" }).covered)
        }
    }

    func testSealReceiptWriteFailureRemainsEngineeringFailure() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write(through: 1_100)
        try FileManager.default.createDirectory(
            at: fixture.directory.appendingPathComponent("evidence.vp0.seal"), withIntermediateDirectories: false)
        let context = try SourceProbeFixture()
        XCTAssertThrowsError(
            try VPCSession.finish(
                recorder: fixture.owner,
                manifest: &context.manifest, directory: fixture.directory))
        XCTAssertEqual(context.manifest.diagnostics.primary?.code, FailureCode.sealFailed.rawValue)
        XCTAssertEqual(context.manifest.terminalStatus, "INVALID")
    }

    func testActualCFinishRejectsFailedVerifyWithoutCallingItAcousticFailure() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write()
        XCTAssertTrue(fixture.owner.seal())
        let handle = try FileHandle(forWritingTo: fixture.directory.appendingPathComponent("evidence.vp0"))
        try handle.truncate(atOffset: 100)
        try handle.close()
        let context = try SourceProbeFixture()
        XCTAssertThrowsError(
            try VPCSession.finish(
                recorder: fixture.owner,
                manifest: &context.manifest, directory: fixture.directory))
        XCTAssertEqual(context.manifest.terminalStatus, "INVALID")
        XCTAssertEqual(context.manifest.diagnostics.primary?.code, FailureCode.recorderInvalid.rawValue)
    }

    func testFinalManifestFailureCannotOverrideOriginalError() throws {
        let fixture = try SourceProbeFixture()
        fixture.manifest.diagnostics.record(EngineeringDiagnostic(stage: .deviceBinding, code: .routeChanged))
        try FileManager.default.createDirectory(
            at: fixture.directory.appendingPathComponent("manifest.json"), withIntermediateDirectories: false)
        XCTAssertThrowsError(
            try VPCSession.finish(
                recorder: fixture.recorder,
                manifest: &fixture.manifest, directory: fixture.directory))
        XCTAssertEqual(fixture.manifest.diagnostics.primary?.code, FailureCode.routeChanged.rawValue)
        XCTAssertTrue(
            fixture.manifest.diagnostics.secondary.contains { $0.code == FailureCode.finalWriteFailed.rawValue })
    }

    func testSharedRunningStateAndRouteGuardsRejectChanges() {
        XCTAssertThrowsError(try SourceProbeRoutePolicy.validateEngineState(isRunning: false, stopped: false))
        XCTAssertThrowsError(
            try VPBSession.validateRoute(
                SourceProbeFixture.route(), mode: .enabled,
                input: SourceProbeFixture.output, output: SourceProbeFixture.output))
    }

    func testCStreamIdentityRejectsGapsClockAndFormatChanges() throws {
        let fixture = try VPCPCMFixture()
        for fault in ["sample", "host", "format", "missing"] {
            var proof = VPCCoverage(events: fixture.events, receipts: fixture.receipts)
            proof.include(fixture.identity(host: 900, sample: 0))
            var next = fixture.identity(host: 1_000, sample: 100)
            if fault == "sample" { next.sample_time = 101 }
            if fault == "host" { next.host_time = 899 }
            if fault == "format" { next.format.mSampleRate = 2_000 }
            if fault == "missing" { next.host_time_valid = false }
            proof.include(next)
            XCTAssertEqual(proof.status, "UNVERIFIED")
            XCTAssertEqual(
                proof.reason, fault == "missing" ? "FRAME_IDENTITY_UNVERIFIED" : "STREAM_SEQUENCE_UNVERIFIED")
        }
    }

    func testLateCallbackRejectedWithoutChangingSealedCEvidence() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write()
        XCTAssertTrue(fixture.owner.seal())
        XCTAssertEqual(try read(fixture).status, "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT")
        var identity = fixture.identity(host: 15_000, sample: 14_100)
        var samples = [Float](repeating: 0.25, count: 300)
        var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer())
        let accepted = samples.withUnsafeMutableBytes { data in
            buffer.mBuffers = AudioBuffer(mNumberChannels: 3, mDataByteSize: 1_200, mData: data.baseAddress)
            return vp_recorder_submit(fixture.recorder, &identity, &buffer)
        }
        XCTAssertFalse(accepted)
        XCTAssertEqual(try read(fixture).status, "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT")
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder).written_records, 282)

    }

    private func read(_ fixture: VPCPCMFixture) throws -> VPCPCMRead {
        try VPCPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events, receipts: fixture.receipts, arm: fixture.arm)
    }
}
