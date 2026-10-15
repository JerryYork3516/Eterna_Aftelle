import Foundation

public enum VPBResearchResult: String, Codable, CaseIterable, Sendable {
    case preserved = "NEAR_END_PRESERVED"
    case degraded = "NEAR_END_DEGRADED"
    case suppressed = "NEAR_END_SUPPRESSED"
    case unverified = "EVIDENCE_UNVERIFIED"
}

public struct VPBRequest: Sendable {
    public static let protocolID = "VPB_LIVE_ZH_V1"
    public static let maximumSeconds: UInt32 = 16
    public let configuration: RunConfiguration
    public let authorized: Bool
    public let registrationURL: URL

    public init(configuration: RunConfiguration, authorized: Bool, registrationURL: URL) {
        self.configuration = configuration
        self.authorized = authorized
        self.registrationURL = registrationURL
    }

    public func validate() throws {
        try configuration.validateForAudio()
        guard authorized, configuration.durationSeconds == 16, configuration.materialURL == nil,
            registrationURL.isFileURL, registrationURL.pathExtension == "json"
        else {
            throw EngineeringFailure(stage: .command, code: .invalidArguments)
        }
        var ancestor = registrationURL.resolvingSymlinksInPath().standardizedFileURL
        while ancestor.path != "/" {
            guard !FileManager.default.fileExists(atPath: ancestor.appendingPathComponent(".git").path) else {
                throw EngineeringFailure(stage: .command, code: .invalidArguments)
            }
            ancestor.deleteLastPathComponent()
        }
    }
}

public enum VPBCue: String, Codable, CaseIterable, Sendable {
    case quietInitial = "D_INITIAL"
    case normal = "A_NORMAL"
    case quietAfterNormal = "D_AFTER_A"
    case short = "B_SHORT"
    case quietAfterShort = "D_AFTER_B"
    case soft = "C_SOFT"
    case quietFinal = "D_FINAL"
    case postRoll = "POST_ROLL"

    public var offset: Double { [0, 2, 5, 5.5, 7, 7.5, 10, 12][Self.allCases.firstIndex(of: self)!] }
    public var end: Double { [2, 5, 5.5, 7, 7.5, 10, 12, 12.5][Self.allCases.firstIndex(of: self)!] }
    public var phrase: String? {
        switch self {
        case .normal: return "今天下午天气不错，我想出去散步。"
        case .short: return "我听见了。"
        case .soft: return "请把声音调低一点。"
        default: return nil
        }
    }
}
