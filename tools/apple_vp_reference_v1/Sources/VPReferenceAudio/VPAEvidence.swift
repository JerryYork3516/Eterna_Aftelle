import VPReferenceCore

struct VPAEvidence: Encodable {
    let protocolID = VPARequest.protocolID
    let protocolApproval = "PROPOSED; requires separate controller and site authorization"
    let deviceRegistrationUse = "Existing P3/P4 targets only; not the source-probe stimulus contract"
    let sourceStatus = "SOURCE_UNVERIFIED"
    let sourceQualificationGranted = false
    let registrationSHA256: String
    var materialSafety: VPAMaterialSafety?
    let quietSeconds = VPARequest.quietSeconds
    let materialSeconds = VPARequest.materialSeconds
    let tailSeconds = VPARequest.tailSeconds
    let postRollSeconds = VPARequest.postRollSeconds
    let timingRevision = "POSTROLL_CLOCK_PAIRS_V1_PROPOSED"
    let clockMappingMeaning = "Local brackets only; overlap does not establish constant offset or acoustic timing"
    let maximumObservationSeconds = VPARequest.maximumObservationSeconds
    let timelineMeaning = "Control requests only; not measured acoustic onset/end or speaker sound pressure"
    var armTick: UInt64?
    var quietStartTick: UInt64?
    var playRequestTick: UInt64?
    var plannedTailStartTick: UInt64?
    var postRollStartTick: UInt64?
    var postRollEndTick: UInt64?
    var stopRequestTick: UInt64?
    var windowsCompleted = false
    var postRollCompleted = false
    private(set) var clockPairs: [VPAClockPair] = []
    private(set) var clockEvidenceStatus = "INCOMPLETE"
    private(set) var clockInvalid = false
    var observationCount = 0
    var maximumObservationTicks: UInt64 = 0
    var runningEngineObserved: Bool?
    var postStopEngineObserved: Bool?
    var playerVolume: Float?
    var mixerVolume: Float?
    var playerPlayingAfterRequest: Bool?

    var isTimingComplete: Bool {
        guard let postRollStartTick, let postRollEndTick, postRollEndTick >= postRollStartTick else { return false }
        return windowsCompleted && postRollCompleted && !clockInvalid
            && clockPairs.count == VPAClockPair.Phase.allCases.count
            && clockEvidenceStatus == "LOCAL_BRACKETS_ONLY_GLOBAL_MAPPING_UNVERIFIED"
    }

    mutating func recordClockPair(_ pair: VPAClockPair) throws {
        guard !clockInvalid else { throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid) }
        let phases = VPAClockPair.Phase.allCases
        guard clockPairs.count < phases.count else { try invalidClock("PAIR_LIMIT_EXCEEDED") }
        let expected = phases[clockPairs.count]
        let previous = clockPairs.last
        clockPairs.append(pair)
        guard pair.phase == expected, pair.isValid,
            let width = pair.bracketSeconds, width <= VPARequest.maximumObservationSeconds
        else { try invalidClock("INVALID_PAIR") }
        if let previous {
            guard pair.absoluteBeforeTick > previous.absoluteAfterTick,
                pair.continuousTick > previous.continuousTick,
                pair.timebaseNumerator == previous.timebaseNumerator,
                pair.timebaseDenominator == previous.timebaseDenominator
            else { try invalidClock("CLOCK_ORDER_OR_UNITS_CHANGED") }
        }
        for earlier in clockPairs.dropLast() {
            guard let lower = pair.offsetLowerBoundTicks, let upper = pair.offsetUpperBoundTicks,
                let earlierLower = earlier.offsetLowerBoundTicks, let earlierUpper = earlier.offsetUpperBoundTicks
            else { try invalidClock("INVALID_PAIR") }
            if lower > earlierUpper || upper < earlierLower {
                try invalidClock("OFFSET_CHANGE_OBSERVED")
            }
        }
        clockEvidenceStatus = "LOCAL_BRACKETS_ONLY_GLOBAL_MAPPING_UNVERIFIED"
    }

    private mutating func invalidClock(_ status: String) throws -> Never {
        clockInvalid = true
        clockEvidenceStatus = status
        throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
    }
}
