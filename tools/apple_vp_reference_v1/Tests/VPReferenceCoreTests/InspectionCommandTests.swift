import Foundation
import XCTest

@testable import VPReferenceCore

final class InspectionCommandTests: XCTestCase {
    private var arguments: [String] {
        [
            "inspect-route", "--enable-audio", "--arm-diagnostics", "--mode", "VP_OFF", "--duration", "8",
            "--study-id", "inspection", "--output-dir",
            FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
        ]
    }

    func testInspectionRequiresExplicitFlags() {
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments.filter { $0 != "--enable-audio" }))
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments.filter { $0 != "--arm-diagnostics" }))
    }

    func testInspectionSelectsSeparateCommand() throws {
        guard case .inspectRoute(let configuration) = try CommandLinePlan.parse(arguments) else {
            return XCTFail("Inspection must not select record")
        }
        XCTAssertEqual(configuration.mode, .disabled)
        XCTAssertNil(configuration.materialURL)
    }

    func testInspectionRejectsMaterial() {
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments + ["--material", "synthetic.wav"]))
    }

    func testPermissionStatusIsExactSeparateCommand() throws {
        guard case .permissionStatus = try CommandLinePlan.parse(["permission-status"]) else {
            return XCTFail("Status must not select permission request or record")
        }
        XCTAssertThrowsError(try CommandLinePlan.parse(["permission-status", "unexpected"]))
    }
}
