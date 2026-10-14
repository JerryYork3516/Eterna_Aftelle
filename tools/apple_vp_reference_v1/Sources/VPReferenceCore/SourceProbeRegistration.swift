import Foundation

public struct SourceProbeRegistration: Codable, Sendable {
    public static let protocolID = "QUIET_TWO_PHRASES_V1"
    public let schemaVersion: Int
    public let inputDeviceID: String
    public let outputDeviceID: String
    public let stimulusProtocol: String

    public init(schemaVersion: Int, inputDeviceID: String, outputDeviceID: String, stimulusProtocol: String) {
        self.schemaVersion = schemaVersion
        self.inputDeviceID = inputDeviceID
        self.outputDeviceID = outputDeviceID
        self.stimulusProtocol = stimulusProtocol
    }

    public func validate() throws {
        let identifiers = [inputDeviceID, outputDeviceID]
        guard schemaVersion == 1, stimulusProtocol == Self.protocolID, inputDeviceID != outputDeviceID,
            identifiers.allSatisfy({ value in
                value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            })
        else { throw EngineeringFailure(stage: .command, code: .invalidArguments) }
    }

    public func validateDefaults(inputID: String, outputID: String, isUSB: Bool, isBuiltIn: Bool) throws {
        try validate()
        guard isUSB, isBuiltIn else { throw EngineeringFailure(stage: .deviceBinding, code: .unsupportedRoute) }
        guard inputID == inputDeviceID, outputID == outputDeviceID else {
            throw EngineeringFailure(stage: .deviceBinding, code: .deviceBindingMismatch)
        }
    }
}
