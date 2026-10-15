import XCTest

@testable import VPReferenceCore

final class VPBWindowTests: XCTestCase {
    func testInputOnlyWarmupAndFixedScorePlusIndependentPostRoll() throws {
        let fixture = VPBControlFixture()
        try fixture.run()
        XCTAssertEqual(fixture.cues, VPBCue.allCases)
        XCTAssertEqual(fixture.events.count, 9)
        XCTAssertEqual(fixture.events.first?.id, "observationStart")
        XCTAssertEqual(fixture.events.last?.id, "beforeStop")
        let start = try XCTUnwrap(fixture.events.first)
        let end = try XCTUnwrap(fixture.events.last)
        XCTAssertGreaterThanOrEqual(end.seconds(end.continuous - start.continuous), 12.5)
        XCTAssertLessThan(fixture.now, 16)
    }

    func testNoInputWarmupCannotOpenWindow() {
        let fixture = VPBControlFixture()
        fixture.readyAt = .infinity
        XCTAssertThrowsError(try fixture.run())
        XCTAssertTrue(fixture.cues.isEmpty)
        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testThreeSecondOpenLimitIncludesFinalObservation() {
        let fixture = VPBControlFixture()
        fixture.now = 2.9
        fixture.observationCost = 0.2
        XCTAssertThrowsError(try fixture.run())
        XCTAssertTrue(fixture.cues.isEmpty)
    }

    func testClockBackwardsAndSixteenSecondBudgetStop() {
        for jump in [-1.0, 16.0] {
            let fixture = VPBControlFixture()
            fixture.jumpAt = 1
            fixture.jumpTo = jump
            XCTAssertThrowsError(try fixture.run())
            XCTAssertEqual(fixture.cues, [.quietInitial])
        }
    }

    func testSkippedHalfSecondPhaseCannotBeCaughtUp() {
        let fixture = VPBControlFixture()
        fixture.jumpAt = 5.1
        fixture.jumpTo = 6
        XCTAssertThrowsError(try fixture.run())
        XCTAssertFalse(fixture.cues.contains(.short))
    }

    func testBoundaryObservationCannotSendAnExpiredCue() {
        let fixture = VPBControlFixture()
        fixture.boundaryDelay = 4
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(fixture.cues, [.quietInitial])
    }

    func testClockPairDelayCannotSendAnExpiredCue() {
        let fixture = VPBControlFixture()
        fixture.eventDelayID = VPBCue.normal.rawValue
        fixture.eventDelay = 4
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(fixture.cues, [.quietInitial])
    }

    func testPostRollAlwaysLastsHalfASecondFromItsActualBoundary() throws {
        let fixture = VPBControlFixture()
        fixture.eventDelayID = VPBCue.postRoll.rawValue
        fixture.eventDelay = 0.1
        try fixture.run()
        let first = try XCTUnwrap(fixture.events.first { $0.id == VPBCue.postRoll.rawValue })
        let last = try XCTUnwrap(fixture.events.last)
        XCTAssertGreaterThanOrEqual(last.seconds(last.continuous - first.continuous), 0.5)
    }

    func testInvalidAndMissingDisplayPreventAllLaterCues() {
        for missingDisplay in [false, true] {
            let fixture = VPBControlFixture()
            fixture.failureAt = missingDisplay ? .infinity : 2
            fixture.badCue = missingDisplay ? .normal : nil
            XCTAssertThrowsError(try fixture.run())
            XCTAssertFalse(fixture.cues.contains(.short))
        }
    }

    func testMissingPreflightNeverRegistersOrStarts() {
        let observer = VPBObserverFixture()
        var starts = 0
        var stops = 0
        XCTAssertThrowsError(
            try VPBWindow.capture(
                admission: (false, observer), start: { starts += 1 }, window: {}, invalidate: {},
                stop: { stops += 1 }))
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertEqual(observer.registrations, 0)
    }

    func testNormalCueAtFourPointEightSecondsIsRejectedBeforeDisplay() {
        let fixture = VPBControlFixture()
        fixture.jumpAt = 2.19
        fixture.jumpTo = 5.0  // Observation origin is about arm+0.2: A would be shown at relative 4.8.
        XCTAssertThrowsError(try fixture.run()) { error in
            let timing = (error as? VPBCueTimingFailure)?.timing
            XCTAssertEqual(timing?.cueID, .normal)
            XCTAssertEqual(timing?.controlLateSeconds ?? 0, 2.8, accuracy: 0.01)
        }
        XCTAssertEqual(fixture.cues, [.quietInitial])
    }

    func testInitialQuietNearItsEndIsRejectedBeforeDisplay() {
        let fixture = VPBControlFixture()
        fixture.afterOriginDelay = 1.8
        XCTAssertThrowsError(try fixture.run()) { error in
            XCTAssertEqual((error as? VPBCueTimingFailure)?.timing.cueID, .quietInitial)
        }
        XCTAssertTrue(fixture.cues.isEmpty)
    }

    func testObservationAndPairDelaysCannotConsumePhaseStartBudget() {
        for delayEvent in [false, true] {
            let fixture = VPBControlFixture()
            fixture.boundaryDelay = delayEvent ? 0 : 0.3
            fixture.eventDelayID = delayEvent ? VPBCue.normal.rawValue : ""
            fixture.eventDelay = 0.3
            XCTAssertThrowsError(try fixture.run()) { error in
                XCTAssertEqual((error as? VPBCueTimingFailure)?.timing.cueID, .normal)
            }
            XCTAssertEqual(fixture.cues, [.quietInitial])
        }
    }

    func testLateDisplayKeepsActualReceiptAndPreventsFollowingCues() throws {
        let fixture = VPBControlFixture()
        fixture.delayedCue = .normal
        fixture.displayDelay = 0.3
        XCTAssertThrowsError(try fixture.run()) { error in
            let timing = (error as? VPBCueTimingFailure)?.timing
            XCTAssertEqual(timing?.cueID, .normal)
            XCTAssertGreaterThan(timing?.displayLateSeconds ?? 0, 0.25)
            XCTAssertLessThan(timing?.remainingPlannedSeconds ?? 3, 2.75)
        }
        XCTAssertEqual(fixture.cues, [.quietInitial, .normal])
        XCTAssertEqual(fixture.receipts.count, 2)
        XCTAssertEqual(fixture.receipts.last?.cueID, VPBCue.normal.rawValue)
    }

    func testLateDisplayUsesActualLifecycleInvalidatesAndCleansUpOnce() {
        let fixture = VPBControlFixture()
        fixture.delayedCue = .normal
        fixture.displayDelay = 0.3
        let observer = VPBObserverFixture()
        var stops = 0
        var removals = 0
        var invalidations = 0
        XCTAssertThrowsError(
            try VPBWindow.capture(
                admission: (true, observer), start: {}, window: { try fixture.run() },
                invalidate: { invalidations += 1 },
                stop: {
                    stops += 1
                    removals += 2
                }))
        XCTAssertEqual(invalidations, 1)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(removals, 2)
        XCTAssertEqual(observer.removals, 1)
        XCTAssertFalse(fixture.cues.contains(.short))
    }

    func testActualLifecycleCleansUpExactlyOnceOnEveryExit() throws {
        for failure in ["none", "start", "score", "observer"] {
            let observer = VPBObserverFixture()
            observer.fail = failure == "observer"
            var stops = 0
            var scores = 0
            var invalidations = 0
            let operation = {
                try VPBWindow.capture(
                    admission: (true, observer),
                    start: { if failure == "start" { throw VPBFixtureFailure.expected } },
                    window: {
                        scores += 1
                        if failure == "score" { throw VPBFixtureFailure.expected }
                    },
                    invalidate: { invalidations += 1 }, stop: { stops += 1 })
            }
            if failure == "none" { XCTAssertNoThrow(try operation()) } else { XCTAssertThrowsError(try operation()) }
            XCTAssertEqual(observer.registrations, 1)
            XCTAssertEqual(observer.removals, 1)
            XCTAssertEqual(stops, 1)
            XCTAssertEqual(scores, ["none", "score"].contains(failure) ? 1 : 0)
            XCTAssertEqual(invalidations, failure == "none" ? 0 : 1)
        }
    }
}

private enum VPBFixtureFailure: Error { case expected }

private final class VPBObserverFixture: PlaybackConfigurationObserving {
    var registrations = 0
    var removals = 0
    var fail = false
    func register() { registrations += 1 }
    func check() throws { if fail { throw VPBFixtureFailure.expected } }
    func remove() { removals += 1 }
}

private final class VPBControlFixture {
    var now = 0.1
    var readyAt = 0.2
    var observationCost = 0.0
    var failureAt = Double.infinity
    var jumpAt = Double.infinity
    var jumpTo = 0.0
    var badCue: VPBCue?
    var cues: [VPBCue] = []
    var events: [VPBClock] = []
    var boundaryDelay = 0.0
    var fullAtNormal = 0
    var eventDelayID = ""
    var eventDelay = 0.0
    var displayDelay = 0.0
    var delayedCue: VPBCue?
    var receipts: [VPBDisplayReceipt] = []
    var afterOriginDelay = 0.0

    func run() throws {
        try VPBWindow.run(
            clock: (1_000_000_000, { self.now }),
            observe: { full in
                self.now += self.observationCost
                if full, self.now >= 2.19, self.now < 2.35 {
                    self.fullAtNormal += 1
                    if self.fullAtNormal == 1 { self.now += self.boundaryDelay }
                }
                if self.now >= self.failureAt { throw VPBFixtureFailure.expected }
                return self.now >= self.readyAt
            },
            event: { id in
                if id == self.eventDelayID { self.now += self.eventDelay }
                self.now += 0.000001
                let tick = UInt64((self.now + 1) * 1_000_000_000)
                let value = VPBClock(
                    id: id, absoluteBefore: tick, continuous: tick, absoluteAfter: tick + 1, numerator: 1,
                    denominator: 1)
                self.events.append(value)
                if id == "observationStart" { self.now += self.afterOriginDelay }
                return value
            },
            cue: { phase in
                if self.badCue == phase { throw VPBFixtureFailure.expected }
                self.cues.append(phase)
                func clock() -> VPBClock {
                    self.now += 0.000001
                    let tick = UInt64((self.now + 1) * 1_000_000_000)
                    return VPBClock(
                        id: phase.rawValue, absoluteBefore: tick, continuous: tick, absoluteAfter: tick + 1,
                        numerator: 1, denominator: 1)
                }
                let request = clock()
                if phase == self.delayedCue { self.now += self.displayDelay }
                let receipt = VPBDisplayReceipt(
                    cueID: phase.rawValue, requested: request, displayed: clock(), visible: true)
                self.receipts.append(receipt)
                return receipt
            },
            wait: { seconds in
                self.now += seconds
                if self.now >= self.jumpAt {
                    self.now = self.jumpTo
                    self.jumpAt = .infinity
                }
            })
    }
}
