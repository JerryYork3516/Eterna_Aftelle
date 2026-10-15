import Foundation
import VPReferenceCore

struct VPBEvidence: Encodable {
    let schemaVersion = 1
    let protocolID = VPBRequest.protocolID
    let sourceType = "LIVE_HUMAN_RESEARCH"
    let sourceStatus = "SOURCE_UNVERIFIED"
    let sourceQualificationGranted = false
    let researchResult = VPBResearchResult.unverified
    let runtime = "NOT_EXERCISED"
    let manualReview = "PENDING_SEPARATE_CONSENT; actual speech, first/last words, overrun, intelligibility, distortion"
    let phrases = VPBCue.allCases.compactMap(\.phrase)
    let firstLastContent = ["A_NORMAL": ["今天", "散步"], "B_SHORT": ["我", "听见了"], "C_SOFT": ["请", "一点"]]
    let preflight: VPBDisplayReceipt
    var armTick: UInt64?
    var events: [VPBClock] = []
    var receipts: [VPBDisplayReceipt] = []
    var rejectedCue: VPBCueTiming?
    var analysis: VPBPCMRead?

    mutating func append(_ event: VPBClock) throws {
        guard events.count < 10, event.valid else {
            throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
        }
        if let previous = events.last {
            guard event.absoluteBefore > previous.absoluteAfter, event.continuous > previous.continuous,
                event.numerator == previous.numerator, event.denominator == previous.denominator
            else { throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid) }
        }
        events.append(event)
    }
}
