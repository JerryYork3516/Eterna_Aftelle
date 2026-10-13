import VPReferenceCore
import XCTest

final class PermissionCommandTests: XCTestCase {
    func testPermissionRequestRequiresExactExplicitCommand() throws {
        guard case .requestMicrophone = try CommandLinePlan.parse(["request-microphone"]) else {
            return XCTFail("Expected explicit permission command")
        }
        XCTAssertThrowsError(try CommandLinePlan.parse(["request-microphone", "--enable-audio"]))
        XCTAssertThrowsError(try CommandLinePlan.parse(["request-microphone", "extra"]))
    }

    func testDefaultAndVerifyCannotSelectPermissionRequest() throws {
        guard case .help = try CommandLinePlan.parse([]) else { return XCTFail("Expected default help") }
        guard case .verify = try CommandLinePlan.parse(["verify", "synthetic-directory"]) else {
            return XCTFail("Expected offline verify")
        }
    }
}
