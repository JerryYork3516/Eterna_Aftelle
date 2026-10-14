import Foundation

public struct SourceProbeRequest: Sendable {
    public static let maximumSeconds: UInt32 = 8
    public let configuration: RunConfiguration
    public let researchAuthorized: Bool
    public let registrationURL: URL

    public init(configuration: RunConfiguration, researchAuthorized: Bool, registrationURL: URL) {
        self.configuration = configuration
        self.researchAuthorized = researchAuthorized
        self.registrationURL = registrationURL
    }

    public func validate() throws {
        try configuration.validateForAudio()
        guard researchAuthorized, configuration.mode == .enabled, configuration.materialURL == nil,
            configuration.durationSeconds == Double(Self.maximumSeconds),
            registrationURL.isFileURL, registrationURL.pathExtension == "json"
        else { throw EngineeringFailure(stage: .command, code: .invalidArguments) }
        var ancestor = registrationURL.resolvingSymlinksInPath().standardizedFileURL
        while ancestor.path != "/" {
            guard !FileManager.default.fileExists(atPath: ancestor.appendingPathComponent(".git").path) else {
                throw EngineeringFailure(stage: .command, code: .invalidArguments)
            }
            ancestor.deleteLastPathComponent()
        }
    }
}
