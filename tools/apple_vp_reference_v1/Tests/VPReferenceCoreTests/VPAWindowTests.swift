import VPRecorder
import VPReferenceCore
import XCTest

private final class VPAObserver: PlaybackConfigurationObserving {
    var registered = 0
    var removed = 0
    var invalid = false
    func register() { registered += 1 }
    func remove() { removed += 1 }
    func check() throws {
        if invalid { throw EngineeringFailure(stage: .vpConfiguration, code: .prePlaybackConfigurationInvalid) }
    }
}

final class VPAWindowTests: XCTestCase {
    func testActualControlLifecycleQuietPlayTailAndSingleCleanup() throws {
        let observer = VPAObserver()
        var events: [String] = []
        try VPAWindow.capture(
            observer: observer,
            beforePlayback: {
                events.append("start-validate")
                events.append("quiet")
            }, play: { events.append("play") },
            score: { events.append("material-tail") },
            cleanup: (invalidate: { XCTFail("No failure expected") }, stop: { events.append("stop") }))
        XCTAssertEqual(events, ["start-validate", "quiet", "play", "material-tail", "stop"])
        XCTAssertEqual(observer.registered, 1)
        XCTAssertEqual(observer.removed, 1)
    }

    func testConfigurationFailureDuringQuietCannotPlayOrScore() {
        let observer = VPAObserver()
        XCTAssertThrowsError(
            try VPAWindow.capture(
                observer: observer, beforePlayback: { observer.invalid = true },
                play: { XCTFail("Cannot play") }, score: { XCTFail("Cannot score") },
                cleanup: (invalidate: {}, stop: {})))
        XCTAssertEqual(observer.removed, 1)
    }

    func testStartupFailureInvalidatesBeforeSingleStop() {
        let observer = VPAObserver()
        var order: [String] = []
        XCTAssertThrowsError(
            try VPAWindow.capture(
                observer: observer,
                beforePlayback: { throw EngineeringFailure(stage: .engineStart, code: .engineStartFailed) },
                play: { XCTFail("No play") },
                score: { XCTFail("No score") },
                cleanup: (invalidate: { order.append("invalid") }, stop: { order.append("stop") })))
        XCTAssertEqual(order, ["invalid", "stop"])
        XCTAssertEqual(observer.removed, 1)
    }

    func testPlayAdmissionFailureSkipsScoreAndCleansOnce() {
        let observer = VPAObserver()
        var stops = 0
        XCTAssertThrowsError(
            try VPAWindow.capture(
                observer: observer, beforePlayback: {},
                play: { throw EngineeringFailure(stage: .recorder, code: .recorderInvalid) },
                score: { XCTFail("Cannot score") }, cleanup: (invalidate: {}, stop: { stops += 1 })))
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(observer.removed, 1)
    }

    func testScoreFailureKeepsOriginalReasonAndClosesAdmissionBeforeStop() {
        let observer = VPAObserver()
        var order: [String] = []
        XCTAssertThrowsError(
            try VPAWindow.capture(
                observer: observer, beforePlayback: {}, play: {},
                score: { throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged) },
                cleanup: (invalidate: { order.append("invalid") }, stop: { order.append("stop") }))
        ) { error in XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "ROUTE_CHANGED") }
        XCTAssertEqual(order, ["invalid", "stop"])
    }

    func testWindowPollsKnownInvalidAndStopsBeforeRemainingTime() {
        var clock = 0.0
        XCTAssertThrowsError(
            try VPAWindow.wait(
                seconds: 8, elapsedSeconds: { clock },
                check: {
                    if clock >= 0.2 { throw EngineeringFailure(stage: .recorder, code: .recorderInvalid) }
                }, observe: {}, sleep: { clock += $0 }))
        XCTAssertLessThan(clock, 1)
    }

    func testThreeWindowsUseBoundedObservationsAndExactSyntheticCoverage() throws {
        var clock = 0.2
        var observations = 0
        for seconds in [VPARequest.quietSeconds, VPARequest.materialSeconds, VPARequest.tailSeconds] {
            try VPAWindow.wait(
                seconds: seconds, elapsedSeconds: { clock }, check: {}, observe: { observations += 1 },
                sleep: { clock += $0 })
        }
        XCTAssertEqual(clock, 13.2, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(observations, 20)
    }

    func testFrozenClockHasFiniteIterationBound() {
        var waits = 0
        XCTAssertThrowsError(
            try VPAWindow.wait(
                seconds: 2, elapsedSeconds: { 0 }, check: {}, observe: {}, sleep: { _ in waits += 1 }))
        XCTAssertEqual(waits, 322)
    }

    func testNonFiniteBackwardClockOrInsufficientAdmissionIsRejected() {
        for clock in [Double.nan, .infinity, -1, 15] {
            XCTAssertThrowsError(
                try VPAWindow.wait(seconds: 2, elapsedSeconds: { clock }, check: {}, observe: {}, sleep: { _ in }))
        }
        var calls = 0
        XCTAssertThrowsError(
            try VPAWindow.wait(
                seconds: 2,
                elapsedSeconds: {
                    calls += 1
                    return calls == 1 ? 1 : 0
                }, check: {}, observe: {},
                sleep: { _ in }))
    }

    func testSlowObservationExceedingHardDeadlineCannotComplete() {
        var clock = 0.0
        XCTAssertThrowsError(
            try VPAWindow.wait(
                seconds: 8, elapsedSeconds: { clock }, check: {}, observe: { clock = 17 }, sleep: { _ in }))
    }

    func testControlObservationBudgetCannotConsumeScoringWindow() {
        var clock = 0.0
        XCTAssertThrowsError(
            try VPAWindow.wait(
                seconds: 2, elapsedSeconds: { clock }, check: {}, observe: { clock += 0.251 }, sleep: { _ in }))
    }

    func testSixteenSecondAdmissionRetainsOriginalRecorderBudgets() throws {
        let fixture = try RecorderFixture { $0.maximum_seconds = VPARequest.maximumSeconds }
        try fixture.arm()
        let boundary = fixture.startTick + vp_recorder_ticks_for_seconds(16)
        XCTAssertTrue(fixture.submit(fixture.identity(tick: boundary)))
        XCTAssertFalse(fixture.submit(fixture.identity(sample: 4, tick: boundary + 1)))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_TIME), 0)
        XCTAssertLessThanOrEqual(snapshot.resident_bytes, 8 * 1_024 * 1_024)
        XCTAssertEqual(vp_recorder_default_config().maximum_pcm_bytes, 64 * 1_024 * 1_024)
    }
}
