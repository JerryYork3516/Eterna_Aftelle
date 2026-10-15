import VPRecorder
import VPReferenceCore
import XCTest

final class VPAPrewarmTests: XCTestCase {
    func testWaitsForBothStreamsBeforeFullQuietWindow() throws {
        var clock = 0.2
        var warmupEnd = 0.0
        try VPAWindow.prewarm(
            elapsedSeconds: { clock }, check: {}, ready: { clock >= 0.5 }, observe: {}, sleep: { clock += $0 })
        warmupEnd = clock
        try VPAWindow.wait(seconds: 2, elapsedSeconds: { clock }, check: {}, observe: {}, sleep: { clock += $0 })
        XCTAssertGreaterThanOrEqual(warmupEnd, 0.5)
        XCTAssertEqual(clock - warmupEnd, 2, accuracy: 0.000_001)
        XCTAssertEqual(VPARequest.prewarmDeadlineSeconds, 2.5)
    }

    func testMissingStreamOrNoFramesIsNotReady() throws {
        var snapshot = VPRecorderSnapshot()
        XCTAssertFalse(try VPAWindow.readyPCM(snapshot))
        snapshot.input_written_records = 1
        snapshot.input_written_frames = 100
        snapshot.render_written_records = 1
        XCTAssertFalse(try VPAWindow.readyPCM(snapshot))
        snapshot.render_written_frames = 100
        XCTAssertTrue(try VPAWindow.readyPCM(snapshot))
    }

    func testMissingValidTimeOrRecorderFailureCannotWarmUp() {
        for kind in 0..<5 {
            var snapshot = VPRecorderSnapshot()
            switch kind {
            case 0: snapshot.missing_host_time_records = 1
            case 1: snapshot.missing_sample_time_records = 1
            case 2: snapshot.invalid_reasons = UInt32(VP_INVALID_FORMAT)
            case 3: snapshot.writer_failure = true
            default: snapshot.lost_records = 1
            }
            XCTAssertThrowsError(try VPAWindow.readyPCM(snapshot))
        }
    }

    func testWarmupTimeoutLeavesAllScoringTimeReserved() {
        var clock = 0.2
        XCTAssertThrowsError(
            try VPAWindow.prewarm(
                elapsedSeconds: { clock }, check: {}, ready: { false }, observe: {}, sleep: { clock += $0 }))
        XCTAssertLessThanOrEqual(clock, 2.5)
    }

    func testFrozenBackwardOrOverBudgetClockIsRejected() {
        for initial in [Double.nan, -Double.infinity, -1, 2.500_001] {
            XCTAssertThrowsError(
                try VPAWindow.prewarm(
                    elapsedSeconds: { initial }, check: {}, ready: { true }, observe: {}, sleep: { _ in }))
        }
        var sleeps = 0
        XCTAssertThrowsError(
            try VPAWindow.prewarm(
                elapsedSeconds: { 0.2 }, check: {}, ready: { false }, observe: {}, sleep: { _ in sleeps += 1 }))
        XCTAssertEqual(sleeps, 52)
    }

    func testObservationCannotConsumeReservedBudgetOrHideInvalid() {
        for advance in [0.251, 3.0] {
            var clock = 0.2
            XCTAssertThrowsError(
                try VPAWindow.prewarm(
                    elapsedSeconds: { clock }, check: {}, ready: { true }, observe: { clock += advance },
                    sleep: { _ in }))
        }
        var invalid = false
        XCTAssertThrowsError(
            try VPAWindow.prewarm(
                elapsedSeconds: { 0.2 },
                check: {
                    if invalid { throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged) }
                }, ready: { true }, observe: { invalid = true }, sleep: { _ in XCTFail("No wait after INVALID") }))
    }

    func testActualRecorderReadinessAndFailureUseSingleCleanupAndSeal() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        var input = fixture.identity()
        input.host_time = 1_000
        XCTAssertTrue(fixture.submit(input))
        var render = fixture.identity(stream: UInt32(VP_STREAM_RENDER))
        render.host_time = 1_000
        XCTAssertTrue(fixture.submit(render))
        try fixture.waitForWritten(2)
        XCTAssertTrue(try VPAWindow.readyPCM(vp_recorder_snapshot(fixture.recorder)))
        var stops = 0
        var clock = 2.4
        let observer = PrewarmObserver()
        XCTAssertThrowsError(
            try VPAWindow.capture(
                observer: observer,
                beforePlayback: {
                    try VPAWindow.prewarm(
                        elapsedSeconds: { clock }, check: {}, ready: { false }, observe: {}, sleep: { clock += $0 })
                }, play: { XCTFail("No playback") }, score: { XCTFail("No score") },
                cleanup: (
                    invalidate: { vp_recorder_invalidate(fixture.recorder, UInt32(VP_INVALID_ABORT)) },
                    stop: { stops += 1 }
                )))
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(observer.removed, 1)
        XCTAssertTrue(fixture.validate().complete)
        XCTAssertNotEqual(fixture.validate().invalid_reasons, 0)
    }
}

private final class PrewarmObserver: PlaybackConfigurationObserving {
    var removed = 0
    func register() {}
    func check() throws {}
    func remove() { removed += 1 }
}
