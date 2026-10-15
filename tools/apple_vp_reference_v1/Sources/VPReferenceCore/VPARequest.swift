import Foundation

public struct VPARequest: Sendable {
    public static let protocolID = "VPA_PURE_ECHO_V1"
    public static let maximumSeconds: UInt32 = 16
    public static let quietSeconds = 2.0
    public static let materialSeconds = 8.0
    public static let tailSeconds = 3.0
    public static let postRollSeconds = 0.5
    public static let prewarmDeadlineSeconds =
        Double(maximumSeconds) - quietSeconds - materialSeconds - tailSeconds - postRollSeconds
    public static let maximumObservationSeconds = 0.25
    public let configuration: RunConfiguration
    public let experimentAuthorized: Bool
    public let targetRegistrationURL: URL
    public let materialSHA256: String
    public let nativePCMSHA256: String

    public init(
        configuration: RunConfiguration, experimentAuthorized: Bool,
        targetRegistrationURL: URL, materialSHA256: String, nativePCMSHA256: String
    ) {
        self.configuration = configuration
        self.experimentAuthorized = experimentAuthorized
        self.targetRegistrationURL = targetRegistrationURL
        self.materialSHA256 = materialSHA256
        self.nativePCMSHA256 = nativePCMSHA256
    }

    public func validate() throws {
        try configuration.validateForAudio()
        guard experimentAuthorized, configuration.durationSeconds == Double(Self.maximumSeconds),
            configuration.materialURL != nil, targetRegistrationURL.isFileURL,
            targetRegistrationURL.pathExtension == "json",
            [materialSHA256, nativePCMSHA256].allSatisfy({ value in
                value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            })
        else { throw EngineeringFailure(stage: .command, code: .invalidArguments) }
        var ancestor = targetRegistrationURL.resolvingSymlinksInPath().standardizedFileURL
        while ancestor.path != "/" {
            guard !FileManager.default.fileExists(atPath: ancestor.appendingPathComponent(".git").path) else {
                throw EngineeringFailure(stage: .command, code: .invalidArguments)
            }
            ancestor.deleteLastPathComponent()
        }
    }
}
