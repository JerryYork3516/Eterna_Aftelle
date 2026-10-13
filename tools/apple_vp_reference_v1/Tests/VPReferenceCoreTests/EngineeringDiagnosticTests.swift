import Foundation
import VPReferenceCore
import XCTest

final class EngineeringDiagnosticTests: XCTestCase {
    func testAllRequiredStagesHaveStableEncodableIdentity() throws {
        let required = [
            "PERMISSION", "VP_CONFIGURATION", "VP_STATE", "INPUT_FORMAT", "OUTPUT_FORMAT", "DEVICE_BINDING",
            "ENGINE_PREPARE", "ENGINE_START", "RECORDER", "SEAL", "EVIDENCE_WRITE"
        ]
        XCTAssertTrue(Set(required).isSubset(of: Set(FailureStage.allCases.map(\.rawValue))))
        for stage in FailureStage.allCases {
            let data = try JSONEncoder().encode(EngineeringDiagnostic(stage: stage, code: .recorderInvalid))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            XCTAssertEqual(json["stage"], stage.rawValue)
            XCTAssertEqual(json["code"], "RECORDER_INVALID")
        }
    }

    func testSealAndWriteFailuresCannotReplaceOriginalReason() {
        var diagnostics = RunDiagnostics()
        diagnostics.record(EngineeringFailure(stage: .vpState, code: .vpStateChanged))
        diagnostics.record(EngineeringDiagnostic(stage: .seal, code: .sealFailed))
        diagnostics.record(EngineeringDiagnostic(stage: .evidenceWrite, code: .finalWriteFailed))
        let failure = EngineeringFailure(diagnostics: diagnostics)
        XCTAssertEqual(failure.diagnostic.stage, .vpState)
        XCTAssertEqual(failure.secondary.map(\.stage), [.seal, .evidenceWrite])
    }

    func testSecondaryCollectionHasFixedLimit() {
        var diagnostics = RunDiagnostics()
        diagnostics.record(EngineeringDiagnostic(stage: .engineStart, code: .engineStartFailed))
        for _ in 0..<12 { diagnostics.record(EngineeringDiagnostic(stage: .evidenceWrite, code: .finalWriteFailed)) }
        XCTAssertEqual(diagnostics.secondary.count, 4)
        XCTAssertEqual(diagnostics.omittedSecondary, 8)
        XCTAssertEqual(diagnostics.primary?.stage, .engineStart)
    }

    func testStageCheckNeverRetriesOrOverwritesTypedFailure() {
        var calls = 0
        XCTAssertThrowsError(
            try EngineeringFailure.check(stage: .vpConfiguration, code: .vpEnableFailed) {
                calls += 1
                throw EngineeringFailure(stage: .outputFormat, code: .outputFormatUnavailable)
            }
        ) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.stage, .outputFormat)
        }
        XCTAssertEqual(calls, 1)
    }

    func testUnknownErrorDetailsAreNeverEncoded() throws {
        let error = NSError(
            domain: "private-fixture-device-path-credential", code: 123,
            userInfo: [
                NSLocalizedDescriptionKey: "sensitive-fixture-value"
            ])
        let failure = EngineeringFailure.capture(error, stage: .deviceBinding, code: .deviceReadFailed)
        let encoded = try JSONEncoder().encode(failure.diagnostic)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("private-fixture"))
        XCTAssertFalse(text.contains("sensitive-fixture"))
        XCTAssertTrue(text.contains("DEVICE_READ_FAILED"))
    }

    func testPermissionErrorRetainsItsTypedStageAndCode() {
        let failure = EngineeringFailure.capture(
            MicrophonePermissionFailure.denied, stage: .command, code: .invalidArguments)
        XCTAssertEqual(failure.diagnostic.stage, .permission)
        XCTAssertEqual(failure.diagnostic.code, "MICROPHONE_DENIED")
    }

    func testEnableFailureDoesNotRepeatStatefulConfiguration() {
        let driver = ConfigurationFixtureDriver()
        driver.failure = .vpConfiguration
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: driver)) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.stage, .vpConfiguration)
        }
        XCTAssertEqual(driver.calls, 1)
    }

    func testUnavailableStateAndInputOutputFormatsHaveDistinctStages() {
        let state = ConfigurationFixtureDriver()
        state.failure = .vpState
        let input = ConfigurationFixtureDriver()
        input.inputInvalid = true
        let output = ConfigurationFixtureDriver()
        output.outputInvalid = true
        for (driver, stage) in [(state, FailureStage.vpState), (input, .inputFormat), (output, .outputFormat)] {
            XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: driver)) { error in
                XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.stage, stage)
            }
        }
    }

    func testFinalMixerMismatchFailsOutputFormatStage() {
        let driver = ConfigurationFixtureDriver()
        driver.finalMixerMismatch = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: driver)) { error in
            let failure = error as? EngineeringFailure
            XCTAssertEqual(failure?.diagnostic.stage, .outputFormat)
            XCTAssertEqual(failure?.diagnostic.code, "MIXER_FORMAT_MISMATCH")
        }
    }
}
