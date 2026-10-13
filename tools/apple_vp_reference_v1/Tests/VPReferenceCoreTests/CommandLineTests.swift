import Foundation
import VPReferenceCore
import XCTest

final class CommandLineTests: XCTestCase {
    func testNoArgumentsAndHelpNeverRequestAudio() throws {
        if case .help = try CommandLinePlan.parse([]) {} else { XCTFail("Expected help") }
        if case .help = try CommandLinePlan.parse(["--help"]) {} else { XCTFail("Expected help") }
    }

    func testVerifyOnlyUsesOfflineCommand() throws {
        guard case .verify = try CommandLinePlan.parse(["verify", "/tmp/synthetic-evidence"]) else {
            return XCTFail("Expected offline verify")
        }
    }

    func testRecordRequiresSeparateAudioAndDiagnosticFlags() {
        XCTAssertThrowsError(try CommandLinePlan.parse(recordOptions()))
        XCTAssertThrowsError(try CommandLinePlan.parse(recordOptions() + ["--enable-audio"]))
        XCTAssertThrowsError(try CommandLinePlan.parse(recordOptions() + ["--arm-diagnostics"]))
    }

    func testExplicitModeAndBoundedDurationAreRequired() throws {
        let flags = ["--enable-audio", "--arm-diagnostics"]
        guard case .record(let configuration) = try CommandLinePlan.parse(recordOptions() + flags) else {
            return XCTFail("Expected record plan")
        }
        XCTAssertEqual(configuration.mode, .disabled)
        XCTAssertThrowsError(try CommandLinePlan.parse(recordOptions(duration: "60.001") + flags))
        XCTAssertThrowsError(try CommandLinePlan.parse(recordOptions(duration: "nan") + flags))
        XCTAssertThrowsError(try CommandLinePlan.parse(recordOptions(duration: "0") + flags))
    }

    func testUnknownAndDuplicateOptionsFailBeforeAudio() {
        XCTAssertThrowsError(try CommandLinePlan.parse(recordOptions() + ["--unknown", "1"]))
        XCTAssertThrowsError(try CommandLinePlan.parse(recordOptions() + ["--mode", "VP_ON"]))
        XCTAssertThrowsError(try CommandLinePlan.parse(["run-both-modes"]))
    }

    func testPrivateEvidenceCannotBePlacedInsideGit() {
        let flags = ["--enable-audio", "--arm-diagnostics"]
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let options = [
            "record", "--mode", "VP_ON", "--duration", "1", "--study-id", "synthetic",
            "--output-dir", directory.appendingPathComponent("not-created").path
        ]
        XCTAssertThrowsError(try CommandLinePlan.parse(options + flags))
    }

    private func recordOptions(duration: String = "1") -> [String] {
        [
            "record", "--mode", "VP_OFF", "--duration", duration,
            "--study-id", "synthetic", "--output-dir", "/tmp/vp0-not-created"
        ]
    }
}
