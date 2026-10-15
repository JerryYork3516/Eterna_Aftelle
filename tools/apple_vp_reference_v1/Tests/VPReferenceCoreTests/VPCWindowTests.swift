import VPReferenceCore
import XCTest

final class VPCWindowTests: XCTestCase {
    func testFixedOriginPlayAndSpeechSchedule() throws {
        let fixture = VPCControlFixture()
        try fixture.run()
        XCTAssertEqual(fixture.cues, VPCCue.allCases)
        XCTAssertEqual(fixture.playTimes.count, 1)
        XCTAssertEqual(fixture.playTimes[0] - fixture.origin, 2, accuracy: 0.001)
        XCTAssertEqual(fixture.displayTimes[.nearEnd]! - fixture.origin, 4, accuracy: 0.001)
        XCTAssertEqual(fixture.now - fixture.origin, 13.5, accuracy: 0.001)
        XCTAssertLessThan(fixture.now, 15.5)
    }

    func testActualStartupSequenceSchedulesOnceAndStopsAtFirstFailure() {
        for failure in ["none", "schedule", "prepare", "start", "validate"] {
            var calls: [String] = []
            func step(_ name: String) throws {
                calls.append(name)
                if name == failure { throw VPCFixtureError.expected }
            }
            let operation = {
                try VPCWindow.start(
                    schedule: { try step("schedule") }, prepare: { try step("prepare") },
                    start: { try step("start") }, validate: { try step("validate") })
            }
            if failure == "none" { XCTAssertNoThrow(try operation()) } else { XCTAssertThrowsError(try operation()) }
            let order = ["schedule", "prepare", "start", "validate"]
            let end = failure == "none" ? 4 : order.firstIndex(of: failure)! + 1
            XCTAssertEqual(calls, Array(order.prefix(end)))
        }
    }

    func testEarlyRepeatedAndLatePlaybackRejected() throws {
        var admission = VPCPlaybackAdmission()
        for time in [1.999, 2.251, Double.nan] { XCTAssertThrowsError(try admission.request(at: time)) }
        XCTAssertEqual(admission.requests, 0)
        try admission.request(at: 2)
        XCTAssertThrowsError(try admission.request(at: 2.1))
        XCTAssertEqual(admission.requests, 1)
    }

    func testBothStreamsMustPrewarm() {
        for ready in [(false, false), (true, false), (false, true)] {
            let fixture = VPCControlFixture()
            fixture.ready = ready
            XCTAssertThrowsError(try fixture.run())
            XCTAssertTrue(fixture.cues.isEmpty)
            XCTAssertTrue(fixture.playTimes.isEmpty)
        }
    }

    func testOpeningAndObservationCostsMustLeaveHalfSecondReserve() {
        for start in [1.95, 2.01] {
            let fixture = VPCControlFixture()
            fixture.now = start
            fixture.observeCost = 0.06
            XCTAssertThrowsError(try fixture.run())
            XCTAssertTrue(fixture.playTimes.isEmpty)
        }
        XCTAssertNoThrow(try VPCWindow.requireReserve(now: 4, origin: 2))
        XCTAssertThrowsError(try VPCWindow.requireReserve(now: 4, origin: 2.001))
    }

    func testDisplayRequestAndReceiptBothHaveCumulativeDeadline() {
        for phase in [VPCCue.quiet, .resident, .nearEnd] {
            let fixture = VPCControlFixture()
            fixture.delayedCue = phase
            fixture.displayDelay = 0.251
            XCTAssertThrowsError(try fixture.run())
            XCTAssertEqual(fixture.cues.last, phase)
            XCTAssertFalse(fixture.cues.contains(.tail))
            if phase != .nearEnd { XCTAssertTrue(fixture.playTimes.isEmpty) }
        }
    }

    func testLateObservationAndPlayRequestClockCannotReachPlayer() {
        let fixture = VPCControlFixture()
        fixture.delayedEvent = "playRequest"
        fixture.eventDelay = 0.251
        XCTAssertThrowsError(try fixture.run())
        XCTAssertTrue(fixture.playTimes.isEmpty)
    }

    func testFixedPostRollDeadlineDoesNotAccumulateBoundaryDelay() throws {
        let fixture = VPCControlFixture()
        fixture.delayedEvent = VPCCue.postRoll.rawValue
        fixture.eventDelay = 0.1
        try fixture.run()
        XCTAssertEqual(fixture.now - fixture.origin, 13.5, accuracy: 0.001)
    }

    func testClockBackwardFrozenAndBudgetExhaustionFailClosed() {
        for jump in [-1.0, 16.0] {
            let fixture = VPCControlFixture()
            fixture.jumpAt = 1
            fixture.jumpTo = jump
            XCTAssertThrowsError(try fixture.run())
            XCTAssertTrue(fixture.playTimes.isEmpty)
        }
        let frozen = VPCControlFixture()
        frozen.frozen = true
        XCTAssertThrowsError(try frozen.run())
    }

    func testObservedInvalidBeforePlaybackStopsAllLaterActions() {
        let fixture = VPCControlFixture()
        fixture.failureAt = 2
        XCTAssertThrowsError(try fixture.run())
        XCTAssertTrue(fixture.playTimes.isEmpty)
        XCTAssertFalse(fixture.cues.contains(.nearEnd))
    }

    func testMissingConfirmationNeverRegistersOrStarts() {
        let observer = VPCObserver()
        var calls = 0
        XCTAssertThrowsError(
            try VPBWindow.capture(
                admission: (false, observer), start: { calls += 1 }, window: { calls += 1 },
                invalidate: { calls += 1 }, stop: { calls += 1 }))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(observer.registered, 0)
    }

    func testActualCaptureWrapperStopsAndRemovesOnceForEveryFailure() {
        for failure in ["none", "register", "start", "window", "configuration", "cue"] {
            let observer = VPCObserver()
            observer.failRegister = failure == "register"
            observer.failCheck = failure == "configuration"
            var stops = 0
            var taps = 0
            var invalids = 0
            let fixture = VPCControlFixture()
            if failure == "cue" {
                fixture.delayedCue = .nearEnd
                fixture.displayDelay = 0.3
            }
            let run = {
                try VPBWindow.capture(
                    admission: (true, observer),
                    start: {
                        if failure == "start" { throw VPCFixtureError.expected }
                    },
                    window: {
                        if failure == "window" { throw VPCFixtureError.expected }
                        try fixture.run()
                    }, invalidate: { invalids += 1 },
                    stop: {
                        stops += 1
                        taps += 2
                    })
            }
            if failure == "none" { XCTAssertNoThrow(try run()) } else { XCTAssertThrowsError(try run()) }
            XCTAssertEqual(stops, 1)
            XCTAssertEqual(taps, 2)
            XCTAssertEqual(observer.removed, 1)
            XCTAssertEqual(invalids, failure == "none" ? 0 : 1)
        }
    }
}

private enum VPCFixtureError: Error { case expected }

private final class VPCObserver: PlaybackConfigurationObserving {
    var registered = 0
    var removed = 0
    var failRegister = false
    var failCheck = false
    func register() throws {
        registered += 1
        if failRegister { throw VPCFixtureError.expected }
    }
    func check() throws { if failCheck { throw VPCFixtureError.expected } }
    func remove() { removed += 1 }
}

private final class VPCControlFixture {
    var now = 0.2
    var origin = 0.0
    var ready = (true, true)
    var observeCost = 0.0
    var failureAt = Double.infinity
    var delayedCue: VPCCue?
    var displayDelay = 0.0
    var delayedEvent = ""
    var eventDelay = 0.0
    var jumpAt = Double.infinity
    var jumpTo = 0.0
    var frozen = false
    var cues: [VPCCue] = []
    var playTimes: [Double] = []
    var displayTimes: [VPCCue: Double] = [:]

    func point(_ id: String) -> VPBClock {
        now += 0.000001
        let tick = UInt64(max(0, now + 1) * 1_000_000_000)
        return VPBClock(
            id: id, absoluteBefore: tick, continuous: tick, absoluteAfter: tick + 1,
            numerator: 1, denominator: 1)
    }

    func run() throws {
        try VPCWindow.run(
            clock: (1_000_000_000, { self.now }),
            observe: { _ in
                self.now += self.observeCost
                if self.now >= self.failureAt { throw VPCFixtureError.expected }
                return self.ready
            },
            event: { id in
                if id == self.delayedEvent { self.now += self.eventDelay }
                let value = self.point(id)
                if id == "observationStart" { self.origin = value.seconds(value.continuous - 1_000_000_000) }
                return value
            },
            perform: { action in
                guard case .cue(let phase) = action else {
                    self.playTimes.append(self.now)
                    return nil
                }
                self.cues.append(phase)
                let requested = self.point(phase.rawValue)
                if self.delayedCue == phase { self.now += self.displayDelay }
                let displayed = self.point(phase.rawValue)
                self.displayTimes[phase] = self.now
                return VPBDisplayReceipt(
                    cueID: phase.rawValue, requested: requested, displayed: displayed, visible: true)
            },
            wait: { delay in
                if !self.frozen { self.now += delay }
                if self.now >= self.jumpAt {
                    self.now = self.jumpTo
                    self.jumpAt = .infinity
                }
            }
        )
    }
}
