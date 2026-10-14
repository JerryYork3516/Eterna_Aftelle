import VPReferenceCore
import XCTest

final class SourceProbeWindowTests: XCTestCase {
    func testNormalWindowHasOnlyFiveOrderedVisualCues() throws {
        var time = 0.0
        var phases: [SourceProbePhase] = []
        try SourceProbeWindow.run(
            durationSeconds: 8, elapsedSeconds: { time }, observe: {},
            cue: { phase, _ in phases.append(phase) }, wait: { time += $0 })
        XCTAssertEqual(phases, [.initialQuiet, .phraseOne, .betweenQuiet, .phraseTwo, .finalQuiet])
        XCTAssertEqual(time, 8, accuracy: 0.0001)
    }

    func testKnownFailureStopsWithoutAnotherWaitOrCue() {
        var waits = 0
        XCTAssertThrowsError(
            try SourceProbeWindow.run(
                durationSeconds: 8, elapsedSeconds: { 0 },
                observe: { throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged) },
                cue: { _, _ in XCTFail("No cue after failure") }, wait: { _ in waits += 1 }))
        XCTAssertEqual(waits, 0)
    }

    func testFrozenClockCannotCauseUnboundedPolling() {
        var waits = 0
        XCTAssertThrowsError(
            try SourceProbeWindow.run(
                durationSeconds: 8, elapsedSeconds: { 0 }, observe: {}, cue: { _, _ in }, wait: { _ in waits += 1 }))
        XCTAssertEqual(waits, 162)
    }

    func testInvalidAndBackwardClocksAreRejected() {
        for invalid in [Double.nan, .infinity, -1] {
            XCTAssertThrowsError(
                try SourceProbeWindow.run(
                    durationSeconds: 8, elapsedSeconds: { invalid }, observe: {},
                    cue: { _, _ in XCTFail("No invalid clock cue") }, wait: { _ in XCTFail("No wait") }))
        }
        var time = 1.0
        XCTAssertThrowsError(
            try SourceProbeWindow.run(
                durationSeconds: 8, elapsedSeconds: { time }, observe: { time = 0 },
                cue: { _, _ in XCTFail("No backwards clock cue") }, wait: { _ in XCTFail("No wait") }))
    }

    func testWindowRejectsDurationBeyondEightSeconds() {
        XCTAssertThrowsError(
            try SourceProbeWindow.run(
                durationSeconds: 8.01, elapsedSeconds: { 0 }, observe: { XCTFail("No observation") },
                cue: { _, _ in }, wait: { _ in XCTFail("No wait") }))
    }

    func testSkippedStimulusPhaseIsInvalidInsteadOfCatchUpCues() {
        var cues = 0
        XCTAssertThrowsError(
            try SourceProbeWindow.run(
                durationSeconds: 8, elapsedSeconds: { 4 }, observe: {},
                cue: { _, _ in cues += 1 }, wait: { _ in XCTFail("No wait after skipped phase") })
        ) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "PROBE_STIMULUS_WINDOW_MISSED")
        }
        XCTAssertEqual(cues, 0)
    }

    func testCueTimeIsReadAfterObservation() throws {
        var time = 0.0
        var cueTime = -1.0
        XCTAssertThrowsError(
            try SourceProbeWindow.run(
                durationSeconds: 8, elapsedSeconds: { time }, observe: { time += 0.5 },
                cue: { _, observed in if cueTime < 0 { cueTime = observed } }, wait: { _ in time = 9 }))
        XCTAssertEqual(cueTime, 0.5)
    }
}
