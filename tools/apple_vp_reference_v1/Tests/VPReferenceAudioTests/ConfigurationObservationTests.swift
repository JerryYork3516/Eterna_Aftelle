import AVFoundation
import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class ConfigurationObservationTests: XCTestCase {
    func testChangeBeforeStartIsObservedAndPreventsStartupAndPlayback() throws {
        let fixture = try ObservationFixture()
        defer { fixture.dispose() }
        fixture.changeAt = .beforeStart
        let failure = fixture.run()
        XCTAssertEqual(failure?.diagnostic.code, "PRE_PLAYBACK_CONFIGURATION_INVALID")
        XCTAssertFalse(fixture.events.contains("start"))
        assertInvalidConfiguration(fixture)
    }

    func testChangeBetweenStartAndValidationBlocksPlayback() throws {
        let fixture = try ObservationFixture()
        defer { fixture.dispose() }
        fixture.changeAt = .afterStart
        let failure = fixture.run()
        XCTAssertEqual(failure?.diagnostic.stage, .vpConfiguration)
        XCTAssertTrue(fixture.events.contains("start"))
        XCTAssertTrue(fixture.events.contains("validate"))
        assertInvalidConfiguration(fixture)
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder.handle).written_records, 1)
    }

    func testObservedChangeAfterValidationBlocksPlayback() throws {
        let fixture = try ObservationFixture()
        defer { fixture.dispose() }
        fixture.changeAt = .afterValidation
        let failure = fixture.run()
        XCTAssertEqual(failure?.diagnostic.code, "PRE_PLAYBACK_CONFIGURATION_INVALID")
        XCTAssertLessThan(
            try XCTUnwrap(fixture.events.firstIndex(of: "validate")),
            try XCTUnwrap(fixture.events.firstIndex(of: "change")))
        assertInvalidConfiguration(fixture)
    }

    func testUnchangedConfigurationPreservesControlOrder() throws {
        let fixture = try ObservationFixture()
        defer { fixture.dispose() }
        XCTAssertNil(fixture.run())
        XCTAssertEqual(
            fixture.events,
            ["register", "check", "start", "validate", "check", "play", "score", "remove", "stop", "seal"])
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder.handle).invalid_reasons, 0)
        XCTAssertTrue(
            fixture.recorder.outcome(directory: fixture.directory, expectsRender: false).isCompleteForReference)
        assertSingleCleanup(fixture)
    }

    func testStartFailureRemovesObserverAndSealsOnceWithoutReplacingReason() throws {
        let fixture = try ObservationFixture()
        defer { fixture.dispose() }
        fixture.failAt = .engineStart
        let failure = fixture.run()
        XCTAssertEqual(failure?.diagnostic.stage, .engineStart)
        XCTAssertEqual(failure?.diagnostic.code, "ENGINE_START_FAILED")
        XCTAssertFalse(fixture.events.contains("play"))
        XCTAssertFalse(fixture.events.contains("score"))
        assertSingleCleanup(fixture)
        XCTAssertTrue(vp_recorder_snapshot(fixture.recorder.handle).sealed)
    }

    func testStateFailureRemovesObserverBeforeSealAndPreservesReason() throws {
        let fixture = try ObservationFixture()
        defer { fixture.dispose() }
        fixture.failAt = .vpState
        let failure = fixture.run()
        XCTAssertEqual(failure?.diagnostic.stage, .vpState)
        XCTAssertEqual(failure?.diagnostic.code, "VP_STATE_CHANGED")
        XCTAssertFalse(fixture.events.contains("play"))
        XCTAssertFalse(fixture.events.contains("score"))
        assertSingleCleanup(fixture)
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder.handle).written_records, 1)
    }

    func testObserverCannotRegisterTwiceOrClearObservedInvalidity() throws {
        let fixture = try ObservationFixture()
        defer { fixture.dispose() }
        let observer = fixture.makeObserver()
        try observer.register()
        fixture.postChange()
        XCTAssertThrowsError(try observer.register())
        XCTAssertThrowsError(try observer.check())
        observer.remove()
        observer.remove()
        XCTAssertThrowsError(try observer.register())
        XCTAssertThrowsError(try observer.check())
        XCTAssertTrue(fixture.recorder.seal())
    }

    private func assertInvalidConfiguration(_ fixture: ObservationFixture) {
        XCTAssertFalse(fixture.events.contains("play"))
        XCTAssertFalse(fixture.events.contains("score"))
        let snapshot = vp_recorder_snapshot(fixture.recorder.handle)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_FORMAT), 0)
        XCTAssertTrue(snapshot.sealed)
        XCTAssertEqual(snapshot.pending_records, 0)
        assertSingleCleanup(fixture)
    }

    private func assertSingleCleanup(_ fixture: ObservationFixture) {
        for event in ["register", "remove", "stop", "seal"] {
            XCTAssertEqual(fixture.events.filter { $0 == event }.count, 1, event)
        }
        XCTAssertFalse(fixture.notificationAfterRemovalChangedRecorder)
    }
}

private enum ObservationPhase {
    case beforeStart
    case afterStart
    case afterValidation
}

private final class ObservationFixture {
    let directory: URL
    let recorder: RecorderOwner
    let center = NotificationCenter()
    let observedObject = NSObject()
    var events: [String] = []
    var changeAt: ObservationPhase?
    var failAt: FailureStage?
    var notificationAfterRemovalChangedRecorder = false

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        recorder = try RecorderOwner(
            configuration: RunConfiguration(
                mode: .disabled, durationSeconds: 1, diagnosticsArmed: true, audioExplicitlyEnabled: true,
                outputDirectory: directory, materialURL: nil, studyID: "synthetic-notification"))
    }

    func makeObserver() -> ConfigurationChangeObserver {
        ConfigurationChangeObserver(observedObject: observedObject, recorder: recorder, center: center)
    }

    func run() -> EngineeringFailure? {
        let observer = TracedObservation(actual: makeObserver(), fixture: self)
        var failure: EngineeringFailure?
        do {
            try PlaybackLifecycle.run(
                observer: observer,
                startAndValidate: {
                    guard vp_recorder_arm(recorder.handle, vp_recorder_now_tick()) else {
                        try observer.check()
                        throw EngineeringFailure(stage: .recorder, code: .recorderArmFailed)
                    }
                    events.append("start")
                    if failAt == .engineStart {
                        throw EngineeringFailure(stage: .engineStart, code: .engineStartFailed)
                    }
                    seedNativePCM()
                    inject(at: .afterStart)
                    events.append("validate")
                    if failAt == .vpState { throw EngineeringFailure(stage: .vpState, code: .vpStateChanged) }
                    inject(at: .afterValidation)
                }, play: { events.append("play") }, score: { events.append("score") },
                stop: {
                    events.append("stop")
                    let before = vp_recorder_snapshot(recorder.handle).invalid_reasons
                    postChange()
                    notificationAfterRemovalChangedRecorder =
                        vp_recorder_snapshot(recorder.handle).invalid_reasons != before
                }
            )
        } catch {
            failure = EngineeringFailure.capture(error, stage: .recorder, code: .recorderInvalid)
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT))
        }
        events.append("seal")
        XCTAssertTrue(recorder.seal())
        return failure
    }

    func inject(at phase: ObservationPhase) {
        if changeAt == phase {
            events.append("change")
            postChange()
        }
    }

    func postChange() {
        center.post(name: .AVAudioEngineConfigurationChange, object: observedObject)
    }

    func dispose() { try? FileManager.default.removeItem(at: directory) }

    private func seedNativePCM() {
        var identity = VPFrameIdentity()
        identity.stream_kind = UInt32(VP_STREAM_INPUT)
        identity.frame_count = 4
        identity.format = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        identity.sample_time_valid = true
        identity.callback_enter_tick = vp_recorder_now_tick()
        let samples: [Float] = [0.25, -0.25, 0.5, -0.5]
        samples.withUnsafeBytes { bytes in
            var buffers = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(bytes.count),
                    mData: UnsafeMutableRawPointer(mutating: bytes.baseAddress)))
            XCTAssertTrue(vp_recorder_submit(recorder.handle, &identity, &buffers))
        }
    }
}

/// Trace-only decorator delegates every registration/check/removal to the actual SDK observer.
private final class TracedObservation: PlaybackConfigurationObserving {
    let actual: ConfigurationChangeObserver
    let fixture: ObservationFixture

    init(actual: ConfigurationChangeObserver, fixture: ObservationFixture) {
        self.actual = actual
        self.fixture = fixture
    }

    func register() throws {
        fixture.events.append("register")
        try actual.register()
        fixture.inject(at: .beforeStart)
    }

    func check() throws {
        fixture.events.append("check")
        try actual.check()
    }

    func remove() {
        fixture.events.append("remove")
        actual.remove()
    }
}
