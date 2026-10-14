import CoreAudio
import Foundation
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class SourceProbeRouteTests: XCTestCase {
    func testUnexpectedEngineStopOrIncompleteStopIsRejected() throws {
        try SourceProbeRoutePolicy.validateEngineState(isRunning: true, stopped: false)
        try SourceProbeRoutePolicy.validateEngineState(isRunning: false, stopped: true)
        for stopped in [true, false] {
            XCTAssertThrowsError(
                try SourceProbeRoutePolicy.validateEngineState(isRunning: stopped, stopped: stopped)
            ) { error in
                XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "PROBE_ENGINE_STATE_MISMATCH")
                XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.stage, stopped ? .engineStop : .engineStart)
            }
        }
    }

    func testSameBuiltInPresentationIsDiagnosticOnlyAndNormalGuardStillRejects() throws {
        let route = SourceProbeFixture.route()
        XCTAssertFalse(route.hasVerifiedBinding)
        XCTAssertNoThrow(try SourceProbeRoutePolicy.validate(route))
    }

    func testThirdDeviceAndVirtualNodeAreRejectedEvenWithUSBDefaults() {
        for transport in [
            kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate
        ] {
            let unknown = AudioDeviceSnapshot(
                anonymousID: String(repeating: "f", count: 64), transport: transport, nominalSampleRate: 48_000)
            XCTAssertThrowsError(try SourceProbeRoutePolicy.validate(SourceProbeFixture.route(nodeInput: unknown)))
            XCTAssertThrowsError(try SourceProbeRoutePolicy.validate(SourceProbeFixture.route(nodeOutput: unknown)))
        }
    }

    func testProbeRunWithoutResearchAuthorizationNeverReachesPermissionOrEngine() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = RunConfiguration(
            mode: .enabled, durationSeconds: 8, diagnosticsArmed: true, audioExplicitlyEnabled: true,
            outputDirectory: root.appendingPathComponent("evidence"), materialURL: nil, studyID: "synthetic-probe")
        let request = SourceProbeRequest(
            configuration: configuration, researchAuthorized: false,
            registrationURL: root.appendingPathComponent("registration.json"))
        XCTAssertThrowsError(try SourceProbe().run(request: request))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testProbeRunWithDefaultDisabledFlagsNeverReachesEngine() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = RunConfiguration(
            mode: .enabled, durationSeconds: 8, diagnosticsArmed: false, audioExplicitlyEnabled: false,
            outputDirectory: root.appendingPathComponent("evidence"), materialURL: nil, studyID: "synthetic-probe")
        XCTAssertThrowsError(
            try SourceProbe().run(
                request: SourceProbeRequest(
                    configuration: configuration, researchAuthorized: true,
                    registrationURL: root.appendingPathComponent("registration.json"))))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
