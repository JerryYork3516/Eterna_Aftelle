import Foundation
import VPReferenceCore
import XCTest

final class SourceProbeCommandTests: XCTestCase {
    private var arguments: [String] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return [
            "source-probe", "--enable-audio", "--arm-diagnostics", "--authorize-source-probe",
            "--mode", "VP_ON", "--duration", "8", "--study-id", "synthetic-probe",
            "--output-dir", root.appendingPathComponent("evidence").path,
            "--probe-registration", root.appendingPathComponent("registration.json").path
        ]
    }

    func testExplicitProbeSelectsOnlyResearchCommand() throws {
        guard case .sourceProbe(let request) = try CommandLinePlan.parse(arguments) else {
            return XCTFail("Probe must not select record")
        }
        XCTAssertTrue(request.researchAuthorized)
        XCTAssertEqual(request.configuration.mode, .enabled)
        XCTAssertNil(request.configuration.materialURL)
        XCTAssertEqual(request.configuration.durationSeconds, 8)
    }

    func testEachExplicitFlagIsRequired() {
        for flag in ["--enable-audio", "--arm-diagnostics", "--authorize-source-probe"] {
            XCTAssertThrowsError(try CommandLinePlan.parse(arguments.filter { $0 != flag }))
        }
    }

    func testProbeWithoutArgumentsIsDenied() {
        XCTAssertThrowsError(try CommandLinePlan.parse(["source-probe"]))
    }

    func testProbeRequiresPrivateRegistrationOption() {
        XCTAssertThrowsError(try CommandLinePlan.parse(Array(arguments.dropLast(2))))
    }

    func testProbeRejectsOffMode() {
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments.map { $0 == "VP_ON" ? "VP_OFF" : $0 }))
    }

    func testProbeRejectsInvalidOrExcessDuration() {
        for value in ["0", "1", "7.99", "8.01", "60", "nan", "inf"] {
            XCTAssertThrowsError(try CommandLinePlan.parse(arguments.map { $0 == "8" ? value : $0 }))
        }
    }

    func testProbeForbidsPlaybackMaterial() {
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments + ["--material", "synthetic.wav"]))
    }

    func testRecordRejectsResearchAuthorizationFlag() {
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments.map { $0 == "source-probe" ? "record" : $0 }))
    }

    func testRecordRetainsItsSixtySecondCommandBudget() throws {
        var values = Array(arguments.dropLast(2)).filter { $0 != "--authorize-source-probe" }
        values = values.map { $0 == "source-probe" ? "record" : ($0 == "8" ? "60" : $0) }
        guard case .record(let configuration) = try CommandLinePlan.parse(values) else {
            return XCTFail("Normal record must keep its own path")
        }
        XCTAssertEqual(configuration.durationSeconds, 60)
    }

    func testRegistrationCannotBeInsideGit() {
        let registration = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("registration.json")
        var values = arguments
        values[values.count - 1] = registration.path
        XCTAssertThrowsError(try CommandLinePlan.parse(values))
    }
}
