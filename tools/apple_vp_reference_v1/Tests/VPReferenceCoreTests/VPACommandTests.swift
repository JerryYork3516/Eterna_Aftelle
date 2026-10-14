import Foundation
import VPReferenceCore
import XCTest

final class VPACommandTests: XCTestCase {
    private var arguments: [String] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return [
            "vp-a", "--enable-audio", "--arm-diagnostics", "--authorize-vp-a", "--mode", "VP_ON",
            "--duration", "16", "--study-id", "synthetic-echo", "--output-dir", root.appendingPathComponent("run").path,
            "--target-registration", root.appendingPathComponent("registration.json").path,
            "--material", root.appendingPathComponent("synthetic.wav").path,
            "--material-sha256", String(repeating: "a", count: 64),
            "--material-pcm-sha256", String(repeating: "b", count: 64)
        ]
    }

    func testBothModesSelectOnlyExplicitExperiment() throws {
        for mode in ["VP_ON", "VP_OFF"] {
            guard case .vpa(let request) = try CommandLinePlan.parse(arguments.map { $0 == "VP_ON" ? mode : $0 })
            else { return XCTFail("Wrong command") }
            XCTAssertTrue(request.experimentAuthorized)
            XCTAssertEqual(request.configuration.mode.rawValue, mode)
            XCTAssertEqual(request.configuration.durationSeconds, 16)
        }
    }

    func testNoArgumentsOrMissingEachLiveFlagIsRejected() {
        XCTAssertThrowsError(try CommandLinePlan.parse(["vp-a"]))
        for flag in ["--authorize-vp-a", "--enable-audio", "--arm-diagnostics"] {
            XCTAssertThrowsError(try CommandLinePlan.parse(arguments.filter { $0 != flag }))
        }
    }

    func testEveryMaterialAndTargetOptionIsRequired() {
        for option in ["--target-registration", "--material", "--material-sha256", "--material-pcm-sha256"] {
            var values = arguments
            let index = values.firstIndex(of: option)!
            values.removeSubrange(index...index + 1)
            XCTAssertThrowsError(try CommandLinePlan.parse(values))
        }
    }

    func testNonFixedDurationAndAutomaticModeAreRejected() {
        for duration in ["0", "8", "15.9", "16.1", "60", "nan", "inf"] {
            XCTAssertThrowsError(try CommandLinePlan.parse(arguments.map { $0 == "16" ? duration : $0 }))
        }
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments.map { $0 == "VP_ON" ? "BOTH" : $0 }))
    }

    func testMalformedDigestIsRejected() {
        for option in ["--material-sha256", "--material-pcm-sha256"] {
            for value in ["", "abc", String(repeating: "g", count: 64), String(repeating: "A", count: 64)] {
                var values = arguments
                values[values.firstIndex(of: option)! + 1] = value
                XCTAssertThrowsError(try CommandLinePlan.parse(values))
            }
        }
    }

    func testDuplicateAndUnrelatedConsentAreRejected() {
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments + ["--authorize-vp-a"]))
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments + ["--authorize-source-probe"]))
    }

    func testOrdinaryRecordAndProbeRejectExperimentArguments() {
        for command in ["record", "source-probe", "inspect-route"] {
            XCTAssertThrowsError(try CommandLinePlan.parse(arguments.map { $0 == "vp-a" ? command : $0 }))
        }
    }

    func testTargetRegistrationAndEvidenceInsideGitAreRejected() {
        for option in ["--target-registration", "--output-dir"] {
            var values = arguments
            values[values.firstIndex(of: option)! + 1] =
                URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().appendingPathComponent("registration.json").path
            XCTAssertThrowsError(try CommandLinePlan.parse(values))
        }
    }
}
