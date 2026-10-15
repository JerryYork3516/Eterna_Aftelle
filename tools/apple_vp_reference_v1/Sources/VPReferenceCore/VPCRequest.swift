import Foundation

public struct VPCRequest: Sendable {
    public static let protocolID = "VPC_LIVE_ZH_V1"
    public static let observationSeconds = 13.0
    public static let postRollSeconds = 0.5
    public static let controlReserve = 0.5
    public static let openingDeadline = 2.0
    public let materialRequest: VPARequest
    public let materialContentReviewed: Bool
    public var configuration: RunConfiguration { materialRequest.configuration }

    public init(materialRequest: VPARequest, materialContentReviewed: Bool) {
        self.materialRequest = materialRequest
        self.materialContentReviewed = materialContentReviewed
    }

    public func validate() throws {
        guard materialRequest.experimentAuthorized, materialContentReviewed, configuration.mode == .enabled else {
            throw EngineeringFailure(stage: .command, code: .invalidArguments)
        }
        try materialRequest.validate()
    }
}

public enum VPCCue: String, CaseIterable, Encodable, Sendable {
    case quiet = "QUIET"
    case resident = "RESIDENT_START"
    case nearEnd = "NEAR_CONTINUOUS"
    case residentAfter = "RESIDENT_AFTER"
    case tail = "TAIL"
    case postRoll = "POST_ROLL"

    public var offset: Double { [0, 2, 4, 9, 10, 13][Self.allCases.firstIndex(of: self)!] }
    public var end: Double { [2, 4, 9, 10, 13, 13.5][Self.allCases.firstIndex(of: self)!] }
    public static let phrase = "绿色纸船经过小桥，我会继续说完这句话。"
}

public struct VPCPlaybackAdmission {
    public private(set) var requests = 0
    public init() {}

    public mutating func request(at relative: Double) throws {
        guard requests == 0, relative.isFinite, relative >= 2, relative <= 2.25 else {
            throw EngineeringFailure(stage: .engineStart, code: .experimentPlaybackFailed)
        }
        requests = 1
    }
}

public enum VPCAction {
    case cue(VPCCue)
    case play
}
