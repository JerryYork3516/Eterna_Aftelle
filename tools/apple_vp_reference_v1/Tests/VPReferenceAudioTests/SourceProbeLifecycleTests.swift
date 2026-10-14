import AVFoundation
import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class SourceProbeLifecycleTests: XCTestCase {
    func testFailureClosesAdmissionBeforeStopAndKeepsOriginalReason() throws {
        let fixture = try SourceProbeFixture()
        let observer = ConfigurationChangeObserver(
            observedObject: NSObject(), recorder: fixture.recorder, center: NotificationCenter())
        var stops = 0
        XCTAssertThrowsError(
            try SourceProbeWindow.capture(
                observer: observer,
                startAndValidate: {
                    XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
                    XCTAssertTrue(fixture.submitThreeChannels())
                },
                window: {
                    try SourceProbe().invalidateOnFailure(recorder: fixture.recorder) {
                        throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged)
                    }
                },
                stop: {
                    stops += 1
                    XCTAssertFalse(vp_recorder_snapshot(fixture.recorder.handle).accepting)
                })
        ) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "ROUTE_CHANGED")
        }
        XCTAssertEqual(stops, 1)
        XCTAssertThrowsError(try fixture.finish())
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder.handle).written_records, 1)
    }

    func testProbeNormalCaptureUsesObserverStopAndRealSealOnce() throws {
        let fixture = try SourceProbeFixture()
        let center = NotificationCenter()
        let object = NSObject()
        let observer = ProbeTraceObserver(
            delegate: ConfigurationChangeObserver(observedObject: object, recorder: fixture.recorder, center: center))
        var time = 0.0
        var stops = 0
        try SourceProbeWindow.capture(
            observer: observer,
            startAndValidate: {
                XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
                XCTAssertTrue(fixture.submitThreeChannels())
            },
            window: {
                try SourceProbeWindow.run(
                    durationSeconds: 8, elapsedSeconds: { time }, observe: { try observer.check() },
                    cue: { _, _ in }, wait: { time += $0 })
            }, stop: { stops += 1 })
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(observer.registers, 1)
        XCTAssertEqual(observer.removes, 1)
        center.post(name: .AVAudioEngineConfigurationChange, object: object)
        XCTAssertEqual(vp_recorder_snapshot(fixture.recorder.handle).invalid_reasons, 0)
        XCTAssertTrue(try fixture.finish().isCompleteForReference)
        XCTAssertEqual(fixture.manifest.sourceProbe?.sourceQualificationGranted, false)
    }

    func testObservedRunningConfigurationChangeStopsAndPreservesInvalidEvidence() throws {
        let fixture = try SourceProbeFixture()
        let center = NotificationCenter()
        let object = NSObject()
        let observer = ProbeTraceObserver(
            delegate: ConfigurationChangeObserver(observedObject: object, recorder: fixture.recorder, center: center))
        var stops = 0
        XCTAssertThrowsError(
            try SourceProbeWindow.capture(
                observer: observer,
                startAndValidate: {
                    XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
                    XCTAssertTrue(fixture.submitThreeChannels())
                },
                window: {
                    try SourceProbeWindow.run(
                        durationSeconds: 8, elapsedSeconds: { 0 },
                        observe: {
                            center.post(name: .AVAudioEngineConfigurationChange, object: object)
                            try observer.check()
                        }, cue: { _, _ in XCTFail("No cue after invalid") }, wait: { _ in XCTFail("No wait") })
                }, stop: { stops += 1 }))
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(observer.removes, 1)
        XCTAssertThrowsError(try fixture.finish())
        let snapshot = vp_recorder_snapshot(fixture.recorder.handle)
        XCTAssertTrue(snapshot.sealed)
        XCTAssertNotEqual(snapshot.invalid_reasons & UInt32(VP_INVALID_FORMAT), 0)
        XCTAssertEqual(snapshot.written_records, 1)
        XCTAssertEqual(snapshot.pending_records, 0)
    }

    func testStartupFailureNeverRunsProbeWindowAndCleansOnce() throws {
        let fixture = try SourceProbeFixture()
        let observer = ProbeTraceObserver(
            delegate: ConfigurationChangeObserver(
                observedObject: NSObject(), recorder: fixture.recorder, center: NotificationCenter()))
        var stops = 0
        XCTAssertThrowsError(
            try SourceProbeWindow.capture(
                observer: observer,
                startAndValidate: { throw EngineeringFailure(stage: .engineStart, code: .engineStartFailed) },
                window: { XCTFail("Failed startup must not collect") }, stop: { stops += 1 }))
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(observer.removes, 1)
        XCTAssertThrowsError(try fixture.finish())
        XCTAssertTrue(vp_recorder_snapshot(fixture.recorder.handle).sealed)
    }

    func testFinalizedProbeOwnerReleasesAfterObserverIsRemoved() throws {
        weak var owner: RecorderOwner?
        do {
            var fixture: SourceProbeFixture? = try SourceProbeFixture()
            owner = fixture?.recorder
            var observer: ConfigurationChangeObserver? = ConfigurationChangeObserver(
                observedObject: NSObject(), recorder: try XCTUnwrap(fixture).recorder, center: NotificationCenter())
            try SourceProbeWindow.capture(
                observer: try XCTUnwrap(observer), startAndValidate: {}, window: {}, stop: {})
            XCTAssertThrowsError(try fixture?.finish())
            XCTAssertTrue(
                try XCTUnwrap(fixture).recorder.outcome(
                    directory: try XCTUnwrap(fixture).directory, expectsRender: false
                ).sealed)
            observer = nil
            fixture = nil
        }
        XCTAssertNil(owner)
    }
}

private final class ProbeTraceObserver: PlaybackConfigurationObserving {
    let delegate: ConfigurationChangeObserver
    var registers = 0
    var removes = 0

    init(delegate: ConfigurationChangeObserver) { self.delegate = delegate }
    func register() throws {
        registers += 1
        try delegate.register()
    }
    func check() throws { try delegate.check() }
    func remove() {
        removes += 1
        delegate.remove()
    }
}
