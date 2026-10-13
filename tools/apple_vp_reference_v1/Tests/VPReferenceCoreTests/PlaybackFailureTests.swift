import VPRecorder
import VPReferenceCore
import XCTest

final class PlaybackFailureTests: XCTestCase {
    func testRunningStateFailureNeverPlaysOrScoresAndKeepsAdmittedEvidence() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        XCTAssertTrue(fixture.submit(fixture.identity()))
        let actual = RunningConfigurationSnapshot(
            state: EngineeringFixture.state(enabled: false), formats: EngineeringFixture.formats,
            hardwareOutput: EngineeringFixture.format()
        )
        var plays = 0
        var scores = 0
        var stops = 0
        var diagnostics = RunDiagnostics()
        do {
            try PlaybackLifecycle.run(
                startAndValidate: {
                    try RunningConfigurationPlan.validate(
                        configured: try EngineeringFixture.configured(),
                        expectedHardwareOutput: EngineeringFixture.format(), actual: actual
                    )
                }, play: { plays += 1 }, score: { scores += 1 }, stop: { stops += 1 }
            )
            XCTFail("Failed running state must abort")
        } catch {
            diagnostics.record(EngineeringFailure.capture(error, stage: .engineStart, code: .engineStartFailed))
            vp_recorder_invalidate(fixture.recorder, UInt32(VP_INVALID_ABORT))
        }
        XCTAssertEqual(plays, 0)
        XCTAssertEqual(scores, 0)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(diagnostics.primary?.stage, .vpState)
        XCTAssertEqual(diagnostics.primary?.code, FailureCode.vpStateChanged.rawValue)
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder).written_records, 1)
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder).pending_records, 0)
        XCTAssertTrue(fixture.validate().complete)
        XCTAssertNotEqual(fixture.validate().invalid_reasons, 0)
    }

    func testInputOutputAndHardwareMismatchesNeverPlay() {
        let changed = EngineeringFixture.format(rate: 16_000)
        let variants = [
            RunningConfigurationSnapshot(
                state: EngineeringFixture.state(),
                formats: AudioFormats(
                    input: changed, mixer: EngineeringFixture.format(), output: EngineeringFixture.format()),
                hardwareOutput: EngineeringFixture.format()),
            RunningConfigurationSnapshot(
                state: EngineeringFixture.state(),
                formats: AudioFormats(input: EngineeringFixture.format(), mixer: changed, output: changed),
                hardwareOutput: EngineeringFixture.format()),
            RunningConfigurationSnapshot(
                state: EngineeringFixture.state(), formats: EngineeringFixture.formats, hardwareOutput: changed)
        ]
        for actual in variants {
            var plays = 0
            var scores = 0
            var stops = 0
            XCTAssertThrowsError(
                try PlaybackLifecycle.run(
                    startAndValidate: {
                        try RunningConfigurationPlan.validate(
                            configured: try EngineeringFixture.configured(),
                            expectedHardwareOutput: EngineeringFixture.format(), actual: actual)
                    }, play: { plays += 1 }, score: { scores += 1 }, stop: { stops += 1 }
                ))
            XCTAssertEqual(plays + scores, 0)
            XCTAssertEqual(stops, 1)
        }
    }

    func testSnapshotReadFailureNeverPlays() {
        var plays = 0
        var stops = 0
        XCTAssertThrowsError(
            try PlaybackLifecycle.run(
                startAndValidate: {
                    try EngineeringFailure.check(stage: .vpState, code: .stateReadFailed) {
                        throw EngineeringFixtureFailure.synthetic
                    }
                }, play: { plays += 1 }, score: { XCTFail("No scoring after failed snapshot") }, stop: { stops += 1 }
            )
        ) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, FailureCode.stateReadFailed.rawValue)
        }
        XCTAssertEqual(plays, 0)
        XCTAssertEqual(stops, 1)
    }

    func testPrepareAndStartFailuresRunOnceAndNeverPlay() {
        for stage in [FailureStage.enginePrepare, .engineStart] {
            var operations = 0
            var plays = 0
            var stops = 0
            XCTAssertThrowsError(
                try PlaybackLifecycle.run(
                    startAndValidate: {
                        try EngineeringFailure.check(stage: stage, code: .engineStartFailed) {
                            operations += 1
                            throw EngineeringFixtureFailure.synthetic
                        }
                    }, play: { plays += 1 }, score: { XCTFail("No scoring after failed startup") }, stop: { stops += 1 }
                )
            ) { error in XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.stage, stage) }
            XCTAssertEqual(operations, 1)
            XCTAssertEqual(plays, 0)
            XCTAssertEqual(stops, 1)
        }
    }

    func testNormalLifecyclePreservesOrderAndSingleStop() throws {
        var order: [String] = []
        try PlaybackLifecycle.run(
            startAndValidate: {
                try RunningConfigurationPlan.validate(
                    configured: try EngineeringFixture.configured(),
                    expectedHardwareOutput: EngineeringFixture.format(),
                    actual: EngineeringFixture.snapshot)
                order.append("validated")
            }, play: { order.append("play") }, score: { order.append("score") }, stop: { order.append("stop") }
        )
        XCTAssertEqual(order, ["validated", "play", "score", "stop"])
    }
}
