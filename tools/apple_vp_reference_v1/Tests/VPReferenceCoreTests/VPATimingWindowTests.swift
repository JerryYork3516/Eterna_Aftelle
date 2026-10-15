import VPRecorder
import VPReferenceCore
import XCTest

final class VPATimingWindowTests: XCTestCase {
    func testAdmissionChecksRetainExactSixteenSecondTickBoundary() throws {
        try VPAWindow.requireAdmission(armTick: 100, currentTick: 16_100, maximumTicks: 16_000)
        for tick: UInt64 in [99, 16_101] {
            XCTAssertThrowsError(try VPAWindow.requireAdmission(armTick: 100, currentTick: tick, maximumTicks: 16_000))
        }
        XCTAssertThrowsError(try VPAWindow.requireAdmission(armTick: nil, currentTick: 100, maximumTicks: 16_000))
        XCTAssertThrowsError(try VPAWindow.requireAdmission(armTick: 100, currentTick: 100, maximumTicks: 0))
    }

    func testOriginalWindowsStayFixedAndPostRollIsSeparate() throws {
        var clock = 0.2
        var requests: [Double] = []
        var boundaries: [Double] = []
        try wait(seconds: VPARequest.quietSeconds, clock: &clock)
        try VPAWindow.finishPlayback(
            wait: {
                requests.append($0)
                try self.wait(seconds: $0, clock: &clock)
            }, boundary: { _ in boundaries.append(clock) })
        XCTAssertEqual(VPARequest.quietSeconds, 2)
        XCTAssertEqual(requests, [8, 3, 0.5])
        XCTAssertEqual(boundaries.count, 3)
        XCTAssertEqual(boundaries[0], 10.2, accuracy: 0.000_001)
        XCTAssertEqual(boundaries[1], 13.2, accuracy: 0.000_001)
        XCTAssertEqual(boundaries[2], 13.7, accuracy: 0.000_001)
        XCTAssertEqual(VPARequest.maximumSeconds, 16)
    }

    func testInsufficientBudgetCannotCompletePostRoll() {
        var clock = 4.7
        var completed = false
        XCTAssertThrowsError(
            try VPAWindow.finishPlayback(
                wait: { try self.wait(seconds: $0, clock: &clock) },
                boundary: { if case .complete = $0 { completed = true } }))
        XCTAssertFalse(completed)
        XCTAssertLessThanOrEqual(clock, 16)
    }

    func testPostRollInvalidStopsImmediatelyWithOriginalReason() {
        var clock = 0.0
        var postRoll = false
        var sleepsAfterInvalid = 0
        XCTAssertThrowsError(
            try VPAWindow.finishPlayback(
                wait: { seconds in
                    try VPAWindow.wait(
                        seconds: seconds, elapsedSeconds: { clock },
                        check: {
                            if postRoll { throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged) }
                        }, observe: {},
                        sleep: {
                            clock += $0
                            if postRoll { sleepsAfterInvalid += 1 }
                        })
                }, boundary: { if case .postRoll = $0 { postRoll = true } })
        ) { XCTAssertEqual(($0 as? EngineeringFailure)?.diagnostic.code, "ROUTE_CHANGED") }
        XCTAssertEqual(sleepsAfterInvalid, 0)
        XCTAssertEqual(clock, 11, accuracy: 0.000_001)
    }

    func testEachCompletionBoundaryFailureSkipsFollowingWindows() {
        for failed in 0..<3 {
            var waits = 0
            var boundaries = 0
            XCTAssertThrowsError(
                try VPAWindow.finishPlayback(
                    wait: { _ in waits += 1 },
                    boundary: { _ in
                        defer { boundaries += 1 }
                        if boundaries == failed {
                            throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
                        }
                    }))
            XCTAssertEqual(waits, failed + 1)
            XCTAssertEqual(boundaries, failed + 1)
        }
    }

    func testNormalAndFailurePathsUseOneStopAndOneRealRecorderSeal() throws {
        for failPostRoll in [false, true] {
            let fixture = try RecorderFixture { $0.maximum_seconds = VPARequest.maximumSeconds }
            let observer = TimingObserver()
            var stops = 0
            var seals = 0
            let capture = {
                try VPAWindow.capture(
                    observer: observer, beforePlayback: { try fixture.arm() }, play: {},
                    score: {
                        try VPAWindow.finishPlayback(
                            wait: { _ in },
                            boundary: {
                                if case .postRoll = $0, failPostRoll {
                                    throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
                                }
                            })
                    },
                    cleanup: (
                        invalidate: { vp_recorder_invalidate(fixture.recorder, UInt32(VP_INVALID_ABORT)) },
                        stop: { stops += 1 }
                    ))
            }
            if failPostRoll { XCTAssertThrowsError(try capture()) } else { try capture() }
            seals += 1
            XCTAssertTrue(vp_recorder_seal(fixture.recorder))
            let validation = fixture.evidence.path.withCString { vp_recorder_validate_file($0) }
            XCTAssertEqual(stops, 1)
            XCTAssertEqual(seals, 1)
            XCTAssertEqual(observer.removed, 1)
            XCTAssertTrue(validation.complete)
            XCTAssertEqual(validation.invalid_reasons == 0, !failPostRoll)
        }
    }

    func testClockFailuresAtAllSixCapturePhasesCleanOnce() {
        for failedPhase in VPAClockPair.Phase.allCases {
            let observer = TimingObserver()
            var stops = 0
            var invalidations = 0
            let sample: (VPAClockPair.Phase) throws -> Void = {
                if $0 == failedPhase { throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid) }
            }
            XCTAssertThrowsError(
                try VPAWindow.capture(
                    observer: observer,
                    beforePlayback: {
                        try sample(.beforeStart)
                        try sample(.quietStart)
                    },
                    play: { try sample(.playRequest) },
                    score: {
                        try VPAWindow.finishPlayback(
                            wait: { _ in },
                            boundary: {
                                if case .plannedTail = $0 { try sample(.plannedTail) }
                                if case .postRoll = $0 { try sample(.postRollStart) }
                                if case .complete = $0 { try sample(.beforeStop) }
                            })
                    }, cleanup: (invalidate: { invalidations += 1 }, stop: { stops += 1 }))
            ) { XCTAssertEqual(($0 as? EngineeringFailure)?.diagnostic.code, "EXPERIMENT_CLOCK_INVALID") }
            XCTAssertEqual(stops, 1)
            XCTAssertEqual(invalidations, 1)
            XCTAssertEqual(observer.removed, 1)
        }
    }

    private func wait(seconds: Double, clock: inout Double) throws {
        try VPAWindow.wait(
            seconds: seconds, elapsedSeconds: { clock }, check: {}, observe: {}, sleep: { clock += $0 })
    }
}

private final class TimingObserver: PlaybackConfigurationObserving {
    var removed = 0
    func register() {}
    func check() throws {}
    func remove() { removed += 1 }
}
