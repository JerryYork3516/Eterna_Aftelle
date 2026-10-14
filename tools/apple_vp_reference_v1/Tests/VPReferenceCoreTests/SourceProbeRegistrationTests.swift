import VPReferenceCore
import XCTest

final class SourceProbeRegistrationTests: XCTestCase {
    private let inputID = String(repeating: "a", count: 64)
    private let outputID = String(repeating: "b", count: 64)

    private func registration(
        input: String? = nil, version: Int = 1, stimulus: String? = nil
    ) -> SourceProbeRegistration {
        SourceProbeRegistration(
            schemaVersion: version, inputDeviceID: input ?? inputID, outputDeviceID: outputID,
            stimulusProtocol: stimulus ?? SourceProbeRegistration.protocolID)
    }

    func testRegisteredDefaultsPermitOnlyDiagnosticPrerequisites() throws {
        try registration().validateDefaults(inputID: inputID, outputID: outputID, isUSB: true, isBuiltIn: true)
    }

    func testNonUSBAndUnsupportedOutputAreRejected() {
        XCTAssertThrowsError(
            try registration().validateDefaults(inputID: inputID, outputID: outputID, isUSB: false, isBuiltIn: true))
        XCTAssertThrowsError(
            try registration().validateDefaults(inputID: inputID, outputID: outputID, isUSB: true, isBuiltIn: false))
    }

    func testOtherUSBOrOutputIdentityIsNotTheRegisteredTarget() {
        for identities in [(outputID, outputID), (inputID, inputID)] {
            XCTAssertThrowsError(
                try registration().validateDefaults(
                    inputID: identities.0, outputID: identities.1, isUSB: true, isBuiltIn: true))
        }
    }

    func testMalformedOrAmbiguousIdentityIsRejected() {
        for value in ["", "raw-device-name", String(repeating: "g", count: 64), outputID] {
            XCTAssertThrowsError(try registration(input: value).validate())
        }
    }

    func testSchemaAndStimulusProtocolMustBeRegistered() {
        XCTAssertThrowsError(try registration(version: 2).validate())
        XCTAssertThrowsError(try registration(stimulus: "unknown").validate())
    }
}
