import Foundation
import XCTest

@testable import VPReferenceCore

final class VPBProtocolTests: XCTestCase {
    private func arguments(_ mode: String = "VP_ON") -> [String] {
        [
            "vp-b", "--authorize-vp-b", "--enable-audio", "--arm-diagnostics", "--mode", mode,
            "--duration", "16", "--study-id", "synthetic-b", "--output-dir", "/tmp/vpb-never-created",
            "--target-registration", "/tmp/vpb-never-read.json"
        ]
    }

    func testExplicitModesRemainSingleIndependentRequests() throws {
        for mode in ["VP_OFF", "VP_ON"] {
            guard case .vpb(let request) = try CommandLinePlan.parse(arguments(mode)) else {
                return XCTFail("Expected isolated VP-B request")
            }
            XCTAssertEqual(request.configuration.mode.rawValue, mode)
            XCTAssertNil(request.configuration.materialURL)
            XCTAssertEqual(request.configuration.durationSeconds, 16)
        }
    }

    func testMissingConsentRejectedBeforeAnyFileOrDeviceAccess() {
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments().filter { $0 != "--authorize-vp-b" }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/vpb-never-created"))
    }

    func testLiveFlagsRemainRequired() {
        for flag in ["--enable-audio", "--arm-diagnostics"] {
            XCTAssertThrowsError(try CommandLinePlan.parse(arguments().filter { $0 != flag }))
        }
    }

    func testMaterialAndForeignEntryFlagsRejected() {
        for flag in ["--material", "--authorize-source-probe", "--authorize-vp-a", "--protocol"] {
            XCTAssertThrowsError(try CommandLinePlan.parse(arguments() + [flag, "forbidden"]))
        }
    }

    func testDurationDuplicateAndInvalidModeRejected() {
        var wrong = arguments()
        wrong[wrong.firstIndex(of: "16")!] = "8"
        XCTAssertThrowsError(try CommandLinePlan.parse(wrong))
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments() + ["--mode", "VP_OFF"]))
        XCTAssertThrowsError(try CommandLinePlan.parse(arguments("AUTO")))
    }

    func testFixedCorpusAndWindowsCannotBeOverridden() {
        XCTAssertEqual(VPBRequest.protocolID, "VPB_LIVE_ZH_V1")
        XCTAssertEqual(VPBCue.allCases.map(\.offset), [0, 2, 5, 5.5, 7, 7.5, 10, 12])
        XCTAssertEqual(VPBCue.postRoll.end, 12.5)
        XCTAssertEqual(VPBCue.allCases.compactMap(\.phrase), ["今天下午天气不错，我想出去散步。", "我听见了。", "请把声音调低一点。"])
    }

    func testVisibleReceiptRequiresActualConfirmationAndCorrectCue() throws {
        let receipt = VPBDisplayReceipt(cueID: "PREFLIGHT", requested: clock(1), displayed: clock(2), visible: true)
        XCTAssertThrowsError(try receipt.validate(id: "PREFLIGHT", requiresUser: true))
        XCTAssertThrowsError(try receipt.validate(id: "A_NORMAL"))
        let confirmed = VPBDisplayReceipt(
            cueID: "PREFLIGHT", requested: clock(1), displayed: clock(2), visible: true, userConfirmed: true)
        XCTAssertNoThrow(try confirmed.validate(id: "PREFLIGHT", requiresUser: true))
        let hidden = VPBDisplayReceipt(
            cueID: "PREFLIGHT", requested: clock(1), displayed: clock(2), visible: false, userConfirmed: true)
        XCTAssertThrowsError(try hidden.validate(id: "PREFLIGHT", requiresUser: true))
    }

    func testMissingOrSlowDisplayReceiptFailsClosed() {
        let late = VPBDisplayReceipt(cueID: "A_NORMAL", requested: clock(1), displayed: clock(400), visible: true)
        XCTAssertThrowsError(try late.validate(id: "A_NORMAL"))
        XCTAssertFalse(
            VPBClock(id: "bad", absoluteBefore: 2, continuous: 1, absoluteAfter: 1, numerator: 1, denominator: 1).valid)
        XCTAssertFalse(
            VPBClock(id: "bad", absoluteBefore: 1, continuous: 1, absoluteAfter: 2, numerator: 1, denominator: 0).valid)
    }

    private func clock(_ tick: UInt64) -> VPBClock {
        VPBClock(
            id: "receipt", absoluteBefore: tick, continuous: tick, absoluteAfter: tick + 1, numerator: 1_000_000,
            denominator: 1)
    }
}
