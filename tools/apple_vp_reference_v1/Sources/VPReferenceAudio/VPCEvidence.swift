import VPReferenceCore

struct VPCEvidence: Encodable {
    let schemaVersion = 1
    let protocolID = VPCRequest.protocolID
    let sourceType = "LIVE_HUMAN_RESEARCH"
    let sourceStatus = "SOURCE_UNVERIFIED"
    let sourceQualificationGranted = false
    var engineeringValidity = "NOT_EVALUATED"
    let physicalOverlapEvidence = "EVIDENCE_UNVERIFIED"
    let nearEndPreservation = "EVIDENCE_UNVERIFIED"
    let echoResidual = "EVIDENCE_UNVERIFIED"
    let runtime = "NOT_EXERCISED"
    let materialSpeechReview = "Operator attestation required; content, acoustic overlap and source remain unverified"
    let phrase = VPCCue.phrase
    let firstLastWords = ["绿色", "这句话"]
    let deadlines = VPCCue.allCases.map(\.offset) + [13.5]
    let controlReserveSeconds = VPCRequest.controlReserve
    let preflight: VPBDisplayReceipt
    let registrationSHA256: String
    let materialSafety: VPAMaterialSafety?
    let preConfigurationState: VoiceProcessingState
    let preConfigurationFormats: AudioFormats
    var armTick: UInt64?
    var events: [VPBClock] = []
    var receipts: [VPBDisplayReceipt] = []
    var runningEngineObserved: Bool?
    var stoppedEngineObserved: Bool?
    var playerPlayingAfterRequest: Bool?
    var stopRequested: VPBClock?
    var playerPlayingBeforeStop: Bool?
    var playerPlayingAfterStop: Bool?
    var analysis: VPCPCMRead?

    mutating func append(_ event: VPBClock) throws {
        guard events.count < 9 else {
            throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
        }
        let previous = events.last
        events.append(event)
        guard event.valid else { throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid) }
        if let previous {
            guard event.absoluteBefore > previous.absoluteAfter, event.continuous > previous.continuous,
                event.numerator == previous.numerator, event.denominator == previous.denominator
            else { throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid) }
        }
    }
}
