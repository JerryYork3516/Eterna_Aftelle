import XCTest

@testable import VPReferenceCore

final class VPBCueTimingTests: XCTestCase {
    func testTimelyReceiptsPreserveActualLatenessAndRemainingWindow() throws {
        let result = timing(request: 2_020, display: 2_040)
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(try XCTUnwrap(result.requestLateSeconds), 0.02, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(result.displayLateSeconds), 0.04, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(result.remainingPlannedSeconds), 2.96, accuracy: 0.000001)
    }

    func testFastDisplayAfterLateRequestStillFailsPlannedStartBudget() throws {
        let receipt = receipt(request: 2_200, display: 2_400)
        XCTAssertNoThrow(try receipt.validate(id: VPBCue.normal.rawValue))
        let result = VPBCueTiming(phase: .normal, observed: 2.2, origin: clock(0), receipt: receipt)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(try XCTUnwrap(result.displayLateSeconds), 0.4, accuracy: 0.000001)
    }

    func testBothFourPointEightSecondRequestAndLateDisplayFail() {
        XCTAssertFalse(timing(request: 4_800, display: 4_801).accepted)
        XCTAssertFalse(timing(request: 2_010, display: 4_800).accepted)
    }

    func testDisplayBudgetBoundaryRejectsOneTickWithFractionalTimebase() {
        let origin = fractional(100)
        let request = fractional(100 + 52_800_000)
        for extra: UInt64 in [0, 1] {
            let receipt = VPBDisplayReceipt(
                cueID: VPBCue.normal.rawValue, requested: request,
                displayed: fractional(100 + 54_000_000 + extra), visible: true)
            let value = VPBCueTiming(phase: .normal, observed: 2.2, origin: origin, receipt: receipt)
            XCTAssertEqual(value.accepted, extra == 0)
        }
    }

    func testEarlyCueIsRejectedWithoutClampingNegativeLateness() throws {
        let value = timing(request: 1_900, display: 1_950)
        XCTAssertFalse(value.accepted)
        XCTAssertEqual(try XCTUnwrap(value.requestLateSeconds), -0.1, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(value.displayLateSeconds), -0.05, accuracy: 0.000001)
    }

    func testHiddenWrongIDBackwardAndMismatchedClockFailClosed() {
        let source = receipt(request: 2_010, display: 2_020)
        let wrongUnit = VPBClock(
            id: VPBCue.normal.rawValue, absoluteBefore: 2_021, continuous: 2_021, absoluteAfter: 2_022,
            numerator: 1, denominator: 1)
        let invalid = [
            VPBDisplayReceipt(
                cueID: source.cueID, requested: source.requested, displayed: source.displayed, visible: false),
            VPBDisplayReceipt(
                cueID: "B_SHORT", requested: source.requested, displayed: source.displayed, visible: true),
            VPBDisplayReceipt(
                cueID: source.cueID, requested: source.displayed, displayed: source.requested, visible: true),
            VPBDisplayReceipt(cueID: source.cueID, requested: source.requested, displayed: wrongUnit, visible: true)
        ]
        for receipt in invalid {
            XCTAssertFalse(VPBCueTiming(phase: .normal, origin: clock(0), receipt: receipt).accepted)
        }
    }

    func testPreDisplayFailureKeepsRawControlLatenessAndNoInventedReceipt() throws {
        XCTAssertThrowsError(try VPBCueTiming.requireStart(phase: .normal, observed: 4.8, origin: clock(0))) { error in
            let value = (error as? VPBCueTimingFailure)?.timing
            XCTAssertEqual(value?.controlLateSeconds ?? 0, 2.8, accuracy: 0.000001)
            XCTAssertNil(value?.requestLateSeconds)
            XCTAssertNil(value?.displayLateSeconds)
        }
        let missing = VPBCueTiming(phase: .normal, origin: clock(0))
        XCTAssertFalse(missing.accepted)
        XCTAssertNil(missing.remainingPlannedSeconds)
    }

    private func timing(request: UInt64, display: UInt64) -> VPBCueTiming {
        VPBCueTiming(phase: .normal, origin: clock(0), receipt: receipt(request: request, display: display))
    }

    private func receipt(request: UInt64, display: UInt64) -> VPBDisplayReceipt {
        VPBDisplayReceipt(
            cueID: VPBCue.normal.rawValue, requested: clock(request), displayed: clock(display), visible: true)
    }

    private func clock(_ milliseconds: UInt64) -> VPBClock {
        VPBClock(
            id: VPBCue.normal.rawValue, absoluteBefore: milliseconds + 1, continuous: milliseconds + 1,
            absoluteAfter: milliseconds + 2, numerator: 1_000_000, denominator: 1)
    }

    private func fractional(_ tick: UInt64) -> VPBClock {
        VPBClock(
            id: VPBCue.normal.rawValue, absoluteBefore: tick, continuous: tick, absoluteAfter: tick + 1,
            numerator: 125, denominator: 3)
    }
}
