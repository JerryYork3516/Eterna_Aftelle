import VPReferenceCore
import XCTest

final class DiagnosticLifecycleTests: XCTestCase {
    func testDiagnosticWriteFailureDoesNotShortenAudioWindow() {
        var events = ["AUDIO_STARTED"]
        var waitedSeconds = 0.0
        DiagnosticLifecycle.finishWindow(
            durationSeconds: 60, elapsedSeconds: { 0.25 },
            observe: {
                events.append("DIAGNOSTIC_WRITE_FAILED")
                throw FixtureFailure.writeFailed
            },
            onFailure: { _ in events.append("INVALID") },
            wait: { duration in
                waitedSeconds = duration
                events.append("PLANNED_WAIT")
            }
        )
        events.append("AUDIO_STOPPED")
        XCTAssertEqual(waitedSeconds, 59.75)
        XCTAssertEqual(
            events,
            [
                "AUDIO_STARTED", "DIAGNOSTIC_WRITE_FAILED", "INVALID", "PLANNED_WAIT", "AUDIO_STOPPED"
            ])
    }

    func testDiagnosticObservationCompletesBeforeRemainingWindow() {
        var failed = false
        var waitedSeconds = -1.0
        DiagnosticLifecycle.finishWindow(
            durationSeconds: 1, elapsedSeconds: { 0.2 }, observe: {},
            onFailure: { _ in failed = true }, wait: { waitedSeconds = $0 }
        )
        XCTAssertFalse(failed)
        XCTAssertEqual(waitedSeconds, 0.8, accuracy: 0.000001)
    }

    func testObservationBeyondWindowDoesNotWaitAgain() {
        var waitedSeconds = -1.0
        DiagnosticLifecycle.finishWindow(
            durationSeconds: 1, elapsedSeconds: { 1.2 }, observe: {},
            onFailure: { _ in }, wait: { waitedSeconds = $0 }
        )
        XCTAssertEqual(waitedSeconds, 0)
    }
}

private enum FixtureFailure: Error {
    case writeFailed
}
