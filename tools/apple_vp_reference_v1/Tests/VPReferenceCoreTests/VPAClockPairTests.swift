import Foundation
import VPReferenceCore
import XCTest

final class VPAClockPairTests: XCTestCase {
    func testLocalBoundsRetainNegativeLowerEndpoint() {
        let pair = VPAClockPair(
            phase: .beforeStart, absoluteBeforeTick: 100, continuousTick: 101, absoluteAfterTick: 102,
            timebaseNumerator: 1, timebaseDenominator: 1)
        XCTAssertTrue(pair.isValid)
        XCTAssertEqual(pair.offsetLowerBoundTicks, -1)
        XCTAssertEqual(pair.offsetUpperBoundTicks, 1)
        XCTAssertEqual(pair.bracketTicks, 2)
        XCTAssertEqual(pair.bracketSeconds, 0.000_000_002)
    }

    func testLargeRawTicksKeepSmallDifferencesExact() {
        let base: UInt64 = 9_007_199_254_740_993
        let pair = VPAClockPair(
            phase: .playRequest, absoluteBeforeTick: base, continuousTick: base + 7,
            absoluteAfterTick: base + 2, timebaseNumerator: 125, timebaseDenominator: 3)
        XCTAssertEqual(pair.offsetLowerBoundTicks, 5)
        XCTAssertEqual(pair.offsetUpperBoundTicks, 7)
        XCTAssertEqual(pair.bracketTicks, 2)
    }

    func testBackwardOrUnrepresentableTicksRemainInvalidRawEvidence() {
        for after: UInt64 in [99, .max] {
            let pair = VPAClockPair(
                phase: .plannedTail, absoluteBeforeTick: 100, continuousTick: 101, absoluteAfterTick: after,
                timebaseNumerator: 1, timebaseDenominator: 1)
            XCTAssertFalse(pair.isValid)
            XCTAssertEqual(pair.absoluteAfterTick, after)
            XCTAssertNil(pair.offsetLowerBoundTicks)
        }
    }

    func testUnavailableTimebaseDoesNotInventUnits() {
        for units: (UInt32, UInt32) in [(0, 1), (1, 0)] {
            let pair = VPAClockPair(
                phase: .beforeStop, absoluteBeforeTick: 1, continuousTick: 2, absoluteAfterTick: 3,
                timebaseNumerator: units.0, timebaseDenominator: units.1)
            XCTAssertFalse(pair.isValid)
            XCTAssertNil(pair.bracketSeconds)
        }
    }

    func testEncodedPairPreservesRawValuesAndBounds() throws {
        let pair = VPAClockPair(
            phase: .beforeStart, absoluteBeforeTick: 100, continuousTick: 101, absoluteAfterTick: 102,
            timebaseNumerator: 125, timebaseDenominator: 3)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pair)) as? [String: Any])
        XCTAssertEqual(object["phase"] as? String, "beforeStart")
        XCTAssertEqual(object["absoluteBeforeTick"] as? Int, 100)
        XCTAssertEqual(object["continuousTick"] as? Int, 101)
        XCTAssertEqual(object["absoluteAfterTick"] as? Int, 102)
        XCTAssertEqual(object["offsetLowerBoundTicks"] as? Int, -1)
        XCTAssertEqual(object["bracketTicks"] as? Int, 2)
    }
}
