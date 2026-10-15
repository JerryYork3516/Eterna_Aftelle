import AudioToolbox
import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPBEvidenceTests: XCTestCase {
    func testInputOnlyNativeFileProvesWindowsAndKeepsEveryChannel() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let result = try VPBPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events, receipts: fixture.receipts)
        XCTAssertEqual(result.status, "DIGITAL_INPUT_SPAN_COVERED")
        XCTAssertEqual(result.coverage.windows.count, 8)
        XCTAssertTrue(result.coverage.windows.allSatisfy(\.covered))
        XCTAssertEqual(result.inputChannels.count, 3)
        XCTAssertEqual(result.inputChannels[0].peak, 0.25)
        XCTAssertEqual(result.inputChannels[1].peak, 0.5)
        XCTAssertEqual(result.inputChannels[2].peak, 0.75)
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder).render_written_frames, 0)
    }

    func testMissingLastHostAnchorCannotUseNominalBufferEnd() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_000)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertEqual(
            try VPBPCMRead.evaluate(directory: fixture.directory, events: fixture.events, receipts: fixture.receipts)
                .status, "UNVERIFIED")
    }

    func testPlanarChannelsAreRetainedWithoutSelectingOrDownmixing() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_600, planar: true)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let result = try VPBPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events, receipts: fixture.receipts)
        XCTAssertEqual(result.inputChannels.map(\.peak), [0.25, 0.5, 0.75])
        XCTAssertEqual(result.status, "DIGITAL_INPUT_SPAN_COVERED")
    }

    func testFiniteOvershootIsRecordedWithoutRejectingDigitalCoverage() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_600, amplitudes: [2, -0.5, 0.75])
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let result = try VPBPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events, receipts: fixture.receipts)
        XCTAssertGreaterThan(result.inputChannels[0].outOfRange, 0)
        XCTAssertEqual(result.status, "DIGITAL_INPUT_SPAN_COVERED")
    }

    func testContainerArmMustMatchAndSupportsIndependentBudgetRecheck() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertNoThrow(
            try VPBPCMRead.evaluate(
                directory: fixture.directory, events: fixture.events, receipts: fixture.receipts,
                expectedArmTick: fixture.arm))
        XCTAssertThrowsError(
            try VPBPCMRead.evaluate(
                directory: fixture.directory, events: fixture.events, receipts: fixture.receipts,
                expectedArmTick: fixture.arm + 1))
    }

    func testContinuousPCMCannotPassWithLateActualDisplay() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        var receipts = fixture.receipts
        receipts[1] = fixture.receipt(phase: .normal, request: 3_020, display: 5_800)
        let result = try VPBPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events, receipts: receipts)
        XCTAssertEqual(result.status, "UNVERIFIED")
        XCTAssertFalse(result.coverage.windows[1].covered)
        XCTAssertFalse(result.coverage.windows[1].cueTimingAccepted)
        XCTAssertGreaterThan(result.coverage.cueTimings[1].displayLateSeconds ?? 0, 2.7)
        XCTAssertTrue(result.coverage.windows[1].first != nil && result.coverage.windows[1].last != nil)
    }

    func testContinuousPCMCannotPassWithMissingDuplicateOrOutOfOrderReceipts() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let reordered = [fixture.receipts[1], fixture.receipts[0]] + fixture.receipts.dropFirst(2)
        for receipts in [[], Array(fixture.receipts.dropLast()), fixture.receipts + [fixture.receipts[0]], reordered] {
            let result = try VPBPCMRead.evaluate(
                directory: fixture.directory, events: fixture.events, receipts: receipts)
            XCTAssertEqual(result.status, "UNVERIFIED")
            XCTAssertFalse(result.coverage.windows.contains(where: \.covered))
        }
    }

    func testTimelyCoverageIncludesOriginalReceiptLateness() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let result = try VPBPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events, receipts: fixture.receipts)
        XCTAssertEqual(result.coverage.cueTimings.count, 8)
        XCTAssertTrue(result.coverage.cueTimings.allSatisfy(\.accepted))
        XCTAssertEqual(result.coverage.cueTimings[1].displayLateSeconds ?? 0, 0.006, accuracy: 0.000001)
    }

    func testPostRollCueTimingRemainsRequiredWhenItsPCMCoverageIsIndependent() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_600)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        var receipts = fixture.receipts
        receipts[7] = fixture.receipt(phase: .postRoll, request: 13_200, display: 13_400)
        let result = try VPBPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events, receipts: receipts)
        XCTAssertTrue(result.coverage.windows.dropLast().allSatisfy(\.covered))
        XCTAssertFalse(result.coverage.cueTimings[7].accepted)
        XCTAssertEqual(result.status, "UNVERIFIED")
    }

    func testRejectedCueAndRawLateReceiptSurviveInvalidSeal() throws {
        let fixture = try SourceProbeFixture()
        let pcm = try VPBPCMFixture()
        let receipt = pcm.receipt(phase: .normal, request: 3_020, display: 5_800)
        var evidence = VPBEvidence(preflight: receipt)
        evidence.receipts.append(receipt)
        evidence.rejectedCue = VPBCueTiming(phase: .normal, observed: 2.02, origin: pcm.events[1], receipt: receipt)
        fixture.manifest.vpbExperiment = evidence
        fixture.manifest.diagnostics.record(EngineeringDiagnostic(stage: .recorder, code: .probeStimulusWindowMissed))
        vp_recorder_invalidate(fixture.recorder.handle, UInt32(VP_INVALID_ABORT))
        XCTAssertThrowsError(
            try VPBSession.finish(recorder: fixture.recorder, manifest: &fixture.manifest, directory: fixture.directory)
        )
        XCTAssertEqual(fixture.manifest.terminalStatus, "INVALID")
        XCTAssertEqual(fixture.manifest.diagnostics.primary?.code, FailureCode.probeStimulusWindowMissed.rawValue)
        XCTAssertTrue(vp_recorder_snapshot(fixture.recorder.handle).sealed)
        let encoded = try JSONEncoder().encode(fixture.manifest.vpbExperiment)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let rejected = try XCTUnwrap(object["rejectedCue"] as? [String: Any])
        XCTAssertEqual(rejected["displayLateSeconds"] as? Double ?? 0, 2.8, accuracy: 0.000001)
        XCTAssertEqual((object["receipts"] as? [Any])?.count, 1)
    }

    func testChinesePromptResourcesLoadWithoutCreatingApplicationOrWindow() {
        XCTAssertTrue(VPBPrompt.localized("ready").contains("尚未录音"))
        XCTAssertTrue(VPBPrompt.localized("quiet").contains("保持安静"))
        XCTAssertEqual(VPBResearchResult.allCases.count, 4)
    }

    func testPostRollIsIndependentOfScore() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 13_100)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let result = try VPBPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events, receipts: fixture.receipts)
        XCTAssertEqual(result.status, "DIGITAL_INPUT_SPAN_COVERED")
        XCTAssertFalse(try XCTUnwrap(result.coverage.windows.last).covered)
    }

    func testNaNInfinityFullScaleAndRMSAreDescriptiveOnly() throws {
        var statistics = VPBChannelStatistics()
        for value: Float in [0.5, -0.5, 1, -1, 2, .nan, .infinity] { statistics.include(value) }
        XCTAssertEqual(statistics.samples, 7)
        XCTAssertEqual(statistics.nonFinite, 2)
        XCTAssertEqual(statistics.fullScale, 2)
        XCTAssertEqual(statistics.outOfRange, 1)
        XCTAssertEqual(statistics.peak, 2)
        XCTAssertEqual(statistics.rms, sqrt(6.5 / 5), accuracy: 0.000001)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(statistics)) as? [String: Any])
        XCTAssertNotNil(object["rms"])
        XCTAssertNil(object["NEAR_END_PRESERVED"])
    }

    func testTruncationAndInvalidSealRejectAnalysis() throws {
        let fixture = try VPBPCMFixture()
        try fixture.write(through: 1_000)
        vp_recorder_invalidate(fixture.recorder, UInt32(VP_INVALID_ABORT))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertThrowsError(
            try VPBPCMRead.evaluate(directory: fixture.directory, events: fixture.events, receipts: fixture.receipts))
        let handle = try FileHandle(forWritingTo: fixture.directory.appendingPathComponent("evidence.vp0"))
        try handle.truncate(atOffset: 100)
        try handle.close()
        XCTAssertThrowsError(
            try VPBPCMRead.evaluate(directory: fixture.directory, events: fixture.events, receipts: fixture.receipts))
    }

    func testMissingDuplicateClockAndWideBracketsCannotProveScore() throws {
        let fixture = try VPBPCMFixture()
        for events in [Array(fixture.events.dropLast()), fixture.events + [fixture.events[0]]] {
            var proof = VPBInputCoverage(events: events, receipts: fixture.receipts)
            proof.finish()
            XCTAssertEqual(proof.status, "UNVERIFIED")
        }
        let wide = VPBClock(
            id: "observationStart", absoluteBefore: 1, continuous: 1, absoluteAfter: 1_000, numerator: 1_000_000,
            denominator: 1)
        XCTAssertFalse(wide.valid)
    }

    func testSparseSamplesWithHugeHostJumpCannotPass() throws {
        let fixture = try VPBPCMFixture()
        var proof = VPBInputCoverage(events: fixture.events, receipts: fixture.receipts)
        proof.include(fixture.identity(host: 900, sample: 0), index: 0)
        proof.include(fixture.identity(host: 14_000, sample: 100), index: 1)
        proof.finish()
        XCTAssertEqual(proof.status, "UNVERIFIED")
    }

    func testDiscontinuousMissingTimeAndFormatChangesFailClosed() throws {
        let fixture = try VPBPCMFixture()
        for failure in ["sample", "host", "format", "missing"] {
            var proof = VPBInputCoverage(events: fixture.events, receipts: fixture.receipts)
            proof.include(fixture.identity(host: 900, sample: 0), index: 0)
            var next = fixture.identity(host: 1_000, sample: 100)
            if failure == "sample" { next.sample_time = 101 }
            if failure == "host" { next.host_time = 899 }
            if failure == "format" { next.format.mSampleRate = 48_000 }
            if failure == "missing" { next.host_time_valid = false }
            proof.include(next, index: 1)
            proof.finish()
            XCTAssertEqual(proof.status, "UNVERIFIED")
        }
    }

    func testEvidenceIsBoundedAndNeverGrantsSourceOrContentPass() throws {
        let fixture = try VPBPCMFixture()
        let first = fixture.events[0]
        let preflight = VPBDisplayReceipt(cueID: "PREFLIGHT", requested: first, displayed: first, visible: false)
        var evidence = VPBEvidence(preflight: preflight)
        for event in fixture.events { try evidence.append(event) }
        XCTAssertThrowsError(try evidence.append(first))
        XCTAssertEqual(evidence.events.count, 10)
        XCTAssertFalse(evidence.sourceQualificationGranted)
        XCTAssertEqual(evidence.researchResult, .unverified)
        XCTAssertEqual(evidence.runtime, "NOT_EXERCISED")
    }

    func testVPONPresentationCannotRelaxVPOFFBinding() {
        let route = SourceProbeFixture.route()
        XCTAssertNoThrow(
            try VPBSession.validateRoute(route, mode: .enabled, input: route.defaultInput, output: route.defaultOutput))
        XCTAssertThrowsError(
            try VPBSession.validateRoute(route, mode: .disabled, input: route.defaultInput, output: route.defaultOutput)
        )
        XCTAssertFalse(route.hasVerifiedBinding)
    }

    func testFinishPreservesOriginalFailureAndSealsOnlyOnce() throws {
        let fixture = try SourceProbeFixture()
        fixture.manifest.diagnostics.record(EngineeringDiagnostic(stage: .engineStart, code: .engineStartFailed))
        vp_recorder_invalidate(fixture.recorder.handle, UInt32(VP_INVALID_ABORT))
        XCTAssertThrowsError(
            try VPBSession.finish(recorder: fixture.recorder, manifest: &fixture.manifest, directory: fixture.directory)
        ) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.stage, .engineStart)
        }
        XCTAssertTrue(vp_recorder_snapshot(fixture.recorder.handle).sealed)
        XCTAssertTrue(fixture.recorder.seal())
        XCTAssertEqual(fixture.manifest.terminalStatus, "INVALID")
    }
}

private final class VPBPCMFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vp-b-synthetic-\(UUID().uuidString)")
    let recorder: OpaquePointer
    let arm: UInt64 = 1_024
    var events: [VPBClock] {
        let ids = ["beforeStart", "observationStart"] + VPBCue.allCases.dropFirst().map(\.rawValue) + ["beforeStop"]
        let ticks: [UInt64] = [100, 1_000, 3_002, 6_004, 6_506, 8_008, 8_510, 11_012, 13_014, 13_516]
        return zip(ids, ticks).map {
            VPBClock(
                id: $0, absoluteBefore: $1, continuous: $1 + arm, absoluteAfter: $1 + 1, numerator: 1_000_000,
                denominator: 1)
        }
    }

    var receipts: [VPBDisplayReceipt] {
        VPBCue.allCases.enumerated().map { index, phase in
            let event = events[index + 1]
            func clock(_ delay: UInt64) -> VPBClock {
                VPBClock(
                    id: phase.rawValue, absoluteBefore: event.absoluteBefore + delay,
                    continuous: event.continuous + delay, absoluteAfter: event.absoluteAfter + delay,
                    numerator: event.numerator, denominator: event.denominator)
            }
            return VPBDisplayReceipt(cueID: phase.rawValue, requested: clock(2), displayed: clock(4), visible: true)
        }
    }

    func receipt(phase: VPBCue, request: UInt64, display: UInt64) -> VPBDisplayReceipt {
        func clock(_ tick: UInt64) -> VPBClock {
            VPBClock(
                id: phase.rawValue, absoluteBefore: tick, continuous: tick + arm, absoluteAfter: tick + 1,
                numerator: 1_000_000, denominator: 1)
        }
        return VPBDisplayReceipt(
            cueID: phase.rawValue, requested: clock(request), displayed: clock(display), visible: true)
    }

    init() throws {
        var config = vp_recorder_default_config()
        config.fixture_mode = true
        config.maximum_seconds = 16
        var error: Int32 = 0
        recorder = try XCTUnwrap(directory.path.withCString { vp_recorder_create($0, &config, &error) })
        XCTAssertTrue(vp_recorder_arm(recorder, arm))
    }

    deinit {
        vp_recorder_destroy(recorder)
        try? FileManager.default.removeItem(at: directory)
    }

    func identity(host: UInt64, sample: Int64, planar: Bool = false) -> VPFrameIdentity {
        var value = VPFrameIdentity()
        value.stream_kind = UInt32(VP_STREAM_INPUT)
        value.frame_count = 100
        value.format = AudioStreamBasicDescription(
            mSampleRate: 1_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: planar ? 41 : 9, mBytesPerPacket: planar ? 4 : 12, mFramesPerPacket: 1,
            mBytesPerFrame: planar ? 4 : 12,
            mChannelsPerFrame: 3, mBitsPerChannel: 32, mReserved: 0)
        value.host_time_valid = true
        value.sample_time_valid = true
        value.host_time = host
        value.sample_time = sample
        value.callback_enter_tick = arm + 1
        return value
    }

    func write(through end: UInt64, planar: Bool = false, amplitudes: [Float] = [0.25, -0.5, 0.75]) throws {
        var records: UInt64 = 0
        for host in stride(from: UInt64(900), through: end, by: 100) {
            var value = identity(host: host, sample: Int64(records * 100), planar: planar)
            var samples: [Float] = (0..<300).map { amplitudes[planar ? $0 / 100 : $0 % 3] }
            let buffers = AudioBufferList.allocate(maximumBuffers: planar ? 3 : 1)
            let accepted = samples.withUnsafeMutableBytes { bytes in
                buffers.unsafeMutablePointer.pointee.mNumberBuffers = planar ? 3 : 1
                for plane in 0..<(planar ? 3 : 1) {
                    buffers[plane] = AudioBuffer(
                        mNumberChannels: planar ? 1 : 3, mDataByteSize: planar ? 400 : 1_200,
                        mData: bytes.baseAddress?.advanced(by: plane * 400))
                }
                return vp_recorder_submit(recorder, &value, buffers.unsafePointer)
            }
            free(buffers.unsafeMutablePointer)
            XCTAssertTrue(accepted)
            records += 1
            let deadline = Date().addingTimeInterval(2)
            while vp_recorder_snapshot(recorder).written_records < records {
                guard Date() < deadline else { throw AudioReferenceError.recorderUnavailable }
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
    }
}
