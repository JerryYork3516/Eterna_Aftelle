import AVFoundation
import Foundation
import VPRecorder
import XCTest

@testable import VPReferenceAudio

final class VPCRenderRegressionTests: XCTestCase {
    func testPreOnlyCannotProveDoubleTalkRender() throws {
        let value = try evaluate(signal: "preOnly")
        XCTAssertEqual(value.status, "UNVERIFIED")
        XCTAssertGreaterThan(value.distribution.phases[0].channels[2].nonZero, 0)
        XCTAssertEqual(value.distribution.phases[1].channels[2].nonZero, 0)
    }

    func testOnePulseAndRepeatedShortPulsesCannotProveSustainedRender() throws {
        for signal in ["pulse", "shortPulses"] {
            let value = try evaluate(signal: signal)
            XCTAssertEqual(value.status, "UNVERIFIED")
            XCTAssertEqual(value.distribution.status, "EVIDENCE_UNVERIFIED")
        }
    }

    func testSustainedUnrelatedWaveformCannotReplaceRegisteredSource() throws {
        let value = try evaluate(amplitude: 0.125)
        XCTAssertGreaterThan(value.distribution.phases[1].channels[2].nonZero, 1_000)
        XCTAssertEqual(value.reference.status, "MATERIAL_COMPATIBILITY_UNVERIFIED")
        XCTAssertEqual(value.status, "UNVERIFIED")
    }

    func testExactSustainedSourceHasPerPhaseAndPerChannelDigitalEvidence() throws {
        let value = try evaluate()
        XCTAssertEqual(value.status, "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT")
        XCTAssertEqual(value.reference.channels.map(\.complete), [false, false, true])
        XCTAssertEqual(value.reference.channels[2].matchedFrames, 8_000)
        XCTAssertTrue(value.reference.channels[2].playCausalityVerified)
        XCTAssertEqual(
            value.distribution.phases.map(\.name), ["residentBefore", "doubleTalkCandidate", "residentAfter"])
        for phase in value.distribution.phases {
            XCTAssertGreaterThan(phase.channels[2].nonZero, 0)
            XCTAssertEqual(phase.channels[0].nonZero, 0)
            XCTAssertFalse(phase.bins.isEmpty)
        }
    }

    func testCompleteSourceBeforeRequestOrAfterResidentBeforePhaseRejects() throws {
        for signal in ["earlyFull", "lateFull"] {
            let value = try evaluate(signal: signal)
            XCTAssertEqual(value.status, "UNVERIFIED")
            XCTAssertFalse(value.reference.channels[2].playCausalityVerified)
            XCTAssertEqual(value.reference.channels[2].matchedFrames, 8_000)
        }
    }

    func testLeadingSourceSilenceUsesSampleAlignmentNotFirstSignalHost() throws {
        let fixture = try VPCPCMFixture()
        let material = try fixture.material()
        for index in 0..<500 { material.floatChannelData![0][index] = 0 }
        try fixture.write(signal: "leadingSilence")
        XCTAssertTrue(fixture.owner.seal())
        let value = try read(fixture, material: material)
        XCTAssertEqual(value.status, "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT")
        XCTAssertEqual(value.reference.channels[2].sourceStartSample, 2_200)
    }

    func testMaterialWhichIsOnlyOnePulseRemainsInsufficientEvenIfExactlyMatched() throws {
        let fixture = try VPCPCMFixture()
        let material = try fixture.material(amplitude: 0)
        material.floatChannelData![0][3_000] = 0.25
        try fixture.write(signal: "pulse")
        XCTAssertTrue(fixture.owner.seal())
        let value = try read(fixture, material: material)
        XCTAssertTrue(value.reference.channels[2].complete)
        XCTAssertEqual(value.distribution.status, "EVIDENCE_UNVERIFIED")
        XCTAssertEqual(value.status, "UNVERIFIED")
    }

    func testMissingReferenceAndUnsupportedRateNeverFallBackToNonzero() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write()
        XCTAssertTrue(fixture.owner.seal())
        XCTAssertEqual(try read(fixture, material: nil).status, "UNVERIFIED")
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 2_000,
                channels: 1, interleaved: false))
        let wrong = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        wrong.frameLength = 16_000
        for index in 0..<16_000 { wrong.floatChannelData![0][index] = 0.25 }
        XCTAssertEqual(try read(fixture, material: wrong).status, "UNVERIFIED")
    }

    func testInputAndRenderDiscontinuitiesRejectMatchedMaterial() throws {
        for signal in ["gapInput", "gapRender"] {
            let fixture = try VPCPCMFixture()
            try fixture.write(signal: signal)
            XCTAssertTrue(fixture.owner.seal())
            XCTAssertNotEqual(vp_recorder_snapshot(fixture.recorder).invalid_reasons, 0)
            XCTAssertThrowsError(try read(fixture, material: fixture.material()))
        }
    }

    func testLastRenderBufferWithoutSuccessorCannotSupplyDistribution() throws {
        let fixture = try VPCPCMFixture()
        var evidence = VPCRenderDistribution(receipts: fixture.receipts)
        var identity = fixture.identity(host: 6_000, sample: 5_100)
        identity.stream_kind = UInt32(VP_STREAM_RENDER)
        try evidence.prepare(identity)
        for sample in 5_100..<5_200 {
            try evidence.include(
                0.25,
                anchor: VPCPCMRead.SignalAnchor(
                    recordIndex: 0, bufferHostTime: 6_000,
                    sampleTime: Int64(sample), channel: 2), channelCount: 3)
        }
        XCTAssertTrue(evidence.phases[1].channels.isEmpty)
        identity.host_time = 11_000
        identity.sample_time = 10_100
        try evidence.prepare(identity)
        XCTAssertTrue(evidence.phases[1].channels.isEmpty)
    }

    func testLateLegalPlayStillAlignsWholeEightSecondSequence() throws {
        let fixture = try VPCPCMFixture()
        try fixture.write()
        XCTAssertTrue(fixture.owner.seal())
        var events = fixture.events
        let old = events[3]
        events[3] = .init(
            id: old.id, absoluteBefore: old.absoluteBefore + 40,
            continuous: old.continuous + 40, absoluteAfter: old.absoluteAfter + 40,
            numerator: old.numerator, denominator: old.denominator)
        let value = try VPCPCMRead.evaluate(
            directory: fixture.directory, events: events,
            receipts: fixture.receipts, arm: fixture.arm, material: fixture.material())
        XCTAssertEqual(value.status, "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT")
    }

    private func evaluate(amplitude: Float = 0.25, signal: String = "play") throws -> VPCPCMRead {
        let fixture = try VPCPCMFixture()
        try fixture.write(amplitude: amplitude, signal: signal)
        XCTAssertTrue(fixture.owner.seal())
        return try read(fixture, material: fixture.material())
    }

    private func read(_ fixture: VPCPCMFixture, material: AVAudioPCMBuffer?) throws -> VPCPCMRead {
        try VPCPCMRead.evaluate(
            directory: fixture.directory, events: fixture.events,
            receipts: fixture.receipts, arm: fixture.arm, material: material)
    }
}
