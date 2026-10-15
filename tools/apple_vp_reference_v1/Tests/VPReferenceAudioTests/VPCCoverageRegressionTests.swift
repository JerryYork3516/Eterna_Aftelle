import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPCCoverageRegressionTests: XCTestCase {
    func testLegalFourPointZeroFiveToNinePointZeroTwoPreservesPlan() throws {
        let fixture = try VPCPCMFixture()
        var events = fixture.events
        events[4] = shifted(events[4], by: 44)
        events[5] = shifted(events[5], by: 12)
        let value = cover(fixture, events: events)
        let near = try XCTUnwrap(value.windows.first { $0.name == "doubleTalkCandidate" })
        XCTAssertTrue(value.formalWindowsCovered)
        XCTAssertEqual(near.actualControl.availableSeconds, 4.968, accuracy: 0.000001)
        XCTAssertTrue(near.minimumDurationVerified)
        XCTAssertEqual(near.plannedEndSeconds - near.plannedStartSeconds, 5)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(near.inputSampleSpan), 5_000)
    }

    func testUnequalLegalLatenessDoesNotCompressFixedThirteenSeconds() throws {
        let fixture = try VPCPCMFixture()
        let delays: [UInt64] = [0, 0, 50, 50, 100, 20, 200, 10, 20]
        let events = zip(fixture.events, delays).map { shifted($0, by: $1) }
        let proof = cover(fixture, events: events)
        XCTAssertTrue(proof.formalWindowsCovered)
        let formal = try XCTUnwrap(proof.windows.first)
        XCTAssertEqual(formal.plannedEndSeconds, 13)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(formal.inputSampleSpan), 13_000)
        XCTAssertEqual(proof.windows.last?.plannedEndSeconds, 13.5)
        XCTAssertEqual(VPARequest.maximumSeconds, 16)
    }

    func testOverBudgetDisplayAndCompressedControlReject() throws {
        let fixture = try VPCPCMFixture()
        var receipts = fixture.receipts
        receipts[2] = fixture.receipt(phase: .nearEnd, request: 5_006, display: 5_251)
        let proof = VPCCoverage(events: fixture.events, receipts: receipts)
        XCTAssertEqual(proof.reason, "C_CUE_TIMING_INVALID")
        XCTAssertFalse(proof.formalWindowsCovered)
    }

    func testPlannedQuietCannotUseOnlyLateDisplayStartCoverage() throws {
        let fixture = try VPCPCMFixture()
        let proof = cover(fixture, events: fixture.events, firstHost: 1_100)
        XCTAssertFalse(proof.formalWindowsCovered)
        XCTAssertNil(proof.windows.first?.inputStart)
    }

    func testRawClockReversalAndCrossPairContradictionReject() throws {
        let fixture = try VPCPCMFixture()
        var events = fixture.events
        events[5] = VPBClock(
            id: events[5].id, absoluteBefore: 4_000, continuous: events[5].continuous,
            absoluteAfter: 4_001, numerator: 1_000_000, denominator: 1)
        XCTAssertFalse(cover(fixture, events: events).formalWindowsCovered)
        var receipts = fixture.receipts
        let old = receipts[2]
        let display = VPBClock(
            id: old.cueID, absoluteBefore: 2_900, continuous: old.displayed.continuous,
            absoluteAfter: 2_901, numerator: 1_000_000, denominator: 1)
        receipts[2] = VPBDisplayReceipt(cueID: old.cueID, requested: old.requested, displayed: display, visible: true)
        XCTAssertFalse(VPCCoverage(events: fixture.events, receipts: receipts).formalWindowsCovered)
    }

    func testMissingSuccessorCannotBeInferredFromLastBufferLength() throws {
        let fixture = try VPCPCMFixture()
        let proof = cover(fixture, events: fixture.events, lastHost: 14_000)
        XCTAssertFalse(proof.formalWindowsCovered)
        XCTAssertNil(proof.windows.first?.renderEnd)
    }

    func testLocalClockOffsetMayVaryWithoutGlobalProjection() throws {
        let fixture = try VPCPCMFixture()
        let offsets: [UInt64] = [0, 0, 6, 6, 9, 12, 15, 18, 21]
        let events = fixture.events.enumerated().map { index, clock in
            VPBClock(
                id: clock.id, absoluteBefore: clock.absoluteBefore + offsets[index],
                continuous: clock.continuous, absoluteAfter: clock.absoluteAfter + offsets[index],
                numerator: clock.numerator, denominator: clock.denominator)
        }
        let proof = cover(fixture, events: events)
        XCTAssertTrue(proof.formalWindowsCovered)
        let near = try XCTUnwrap(proof.windows.first { $0.name == "doubleTalkCandidate" })
        XCTAssertLessThan(near.startBoundary.lowerPairContinuous, near.startBoundary.continuousEarliest)
        XCTAssertGreaterThan(near.startBoundary.upperPairContinuous, near.startBoundary.continuousLatest)
    }

    func testIndependentPostRollStillRequiresItsOwnSuccessor() throws {
        let fixture = try VPCPCMFixture()
        let proof = cover(fixture, events: fixture.events, lastHost: 14_300)
        XCTAssertTrue(proof.formalWindowsCovered)
        XCTAssertFalse(try XCTUnwrap(proof.windows.last).covered)
    }

    private func shifted(_ clock: VPBClock, by delay: UInt64) -> VPBClock {
        VPBClock(
            id: clock.id, absoluteBefore: clock.absoluteBefore + delay, continuous: clock.continuous + delay,
            absoluteAfter: clock.absoluteAfter + delay, numerator: clock.numerator, denominator: clock.denominator)
    }

    private func cueClock(_ clock: VPBClock, phase: VPCCue) -> VPBClock {
        VPBClock(
            id: phase.rawValue, absoluteBefore: clock.absoluteBefore, continuous: clock.continuous,
            absoluteAfter: clock.absoluteAfter, numerator: clock.numerator, denominator: clock.denominator)
    }

    private func cover(
        _ fixture: VPCPCMFixture, events: [VPBClock], firstHost: UInt64 = 900,
        lastHost: UInt64 = 14_900
    ) -> VPCCoverage {
        let indices = [1, 2, 4, 5, 6, 7]
        let receipts = VPCCue.allCases.enumerated().map { index, phase in
            let clock = events[indices[index]]
            return VPBDisplayReceipt(
                cueID: phase.rawValue,
                requested: cueClock(shifted(clock, by: 2), phase: phase),
                displayed: cueClock(shifted(clock, by: 4), phase: phase), visible: true)
        }
        var proof = VPCCoverage(events: events, receipts: receipts)
        var count: UInt64 = 0
        for host in stride(from: firstHost, through: lastHost, by: 100) {
            for stream in [VP_STREAM_INPUT, VP_STREAM_RENDER] {
                var identity = fixture.identity(host: host, sample: Int64(host - firstHost))
                identity.stream_kind = UInt32(stream)
                proof.include(identity)
                count += 1
            }
        }
        proof.finish(expectedRecords: count)
        return proof
    }
}
