import Foundation
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPCFinishTests: XCTestCase {
    func testCompleteCFinishAndFinalWriteFailureRemainSeparateFromAcoustics() throws {
        for failWrite in [false, true] {
            let fixture = try VPCPCMFixture()
            try fixture.write()
            let context = try SourceProbeFixture()
            let point = VPBClock(
                id: "PREFLIGHT", absoluteBefore: 1, continuous: 10, absoluteAfter: 2,
                numerator: 1, denominator: 1)
            let displayed = VPBClock(
                id: "PREFLIGHT", absoluteBefore: 3, continuous: 12, absoluteAfter: 4,
                numerator: 1, denominator: 1)
            let receipt = VPBDisplayReceipt(
                cueID: "PREFLIGHT", requested: point, displayed: displayed,
                visible: true, userConfirmed: true)
            var evidence = VPCEvidence(
                preflight: receipt, registrationSHA256: String(repeating: "a", count: 64),
                materialSafety: nil, preConfigurationState: context.manifest.configured.state,
                preConfigurationFormats: context.manifest.configured.formats)
            evidence.armTick = fixture.arm
            evidence.events = fixture.events
            evidence.receipts = fixture.receipts
            context.manifest.vpcExperiment = evidence
            if failWrite {
                try FileManager.default.createDirectory(
                    at: fixture.directory.appendingPathComponent("manifest.json"), withIntermediateDirectories: false)
                XCTAssertThrowsError(
                    try VPCSession.finish(
                        recorder: fixture.owner,
                        manifest: &context.manifest, directory: fixture.directory, material: fixture.material()))
            } else {
                XCTAssertNoThrow(
                    try VPCSession.finish(
                        recorder: fixture.owner,
                        manifest: &context.manifest, directory: fixture.directory, material: fixture.material()))
            }
            XCTAssertEqual(
                context.manifest.vpcExperiment?.engineeringValidity,
                failWrite ? "INVALID" : "ENGINEERING_VALID")
            XCTAssertEqual(context.manifest.vpcExperiment?.physicalOverlapEvidence, "EVIDENCE_UNVERIFIED")
            XCTAssertEqual(context.manifest.vpcExperiment?.nearEndPreservation, "EVIDENCE_UNVERIFIED")
            XCTAssertEqual(context.manifest.vpcExperiment?.echoResidual, "EVIDENCE_UNVERIFIED")
        }
    }

}
