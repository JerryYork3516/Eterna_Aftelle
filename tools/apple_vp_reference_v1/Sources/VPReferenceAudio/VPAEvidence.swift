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
    let timingRevision = "EVENT_LOCAL_WINDOWS_V2_PROPOSED"
    let clockMappingMeaning =
        "Each event uses its own absolute bracket; no global offset is required; acoustic timing is unverified"
    let maximumObservationSeconds = VPARequest.maximumObservationSeconds
    let timelineMeaning = "Control requests only; not measured acoustic onset/end or speaker sound pressure"
    var prewarmStartTick: UInt64?
    var prewarmEndTick: UInt64?
    var prewarmInputRecords: UInt64 = 0
    var prewarmRenderRecords: UInt64 = 0
    var prewarmCompleted = false
    var windowCoverage: VPAWindowCoverage?
    var armTick: UInt64?
    var quietStartTick: UInt64?
    var playRequestTick: UInt64?
    var plannedTailStartTick: UInt64?
    var postRollStartTick: UInt64?
    var postRollEndTick: UInt64?
    var normalStopBoundaryTick: UInt64?
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
        guard let prewarmStartTick, let prewarmEndTick, prewarmEndTick >= prewarmStartTick,
            let quietStartTick, quietStartTick >= prewarmEndTick,
            let postRollStartTick, let postRollEndTick, postRollEndTick >= postRollStartTick,
            prewarmInputRecords > 0, prewarmRenderRecords > 0, normalStopBoundaryTick == postRollEndTick
        else { return false }
        let ticks = [quietStartTick, playRequestTick, plannedTailStartTick, postRollStartTick, postRollEndTick]
        guard ticks.compactMap({ $0 }) == clockPairs.dropFirst().map(\.continuousTick) else { return false }
        return prewarmCompleted && windowsCompleted && postRollCompleted && !clockInvalid
            && clockPairs.count == VPAClockPair.Phase.allCases.count
            && clockEvidenceStatus == "EVENT_LOCAL_BRACKETS_GLOBAL_MAPPING_NOT_USED"
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
        recordBoundary(pair)
        clockEvidenceStatus = "EVENT_LOCAL_BRACKETS_GLOBAL_MAPPING_NOT_USED"
    }

    private mutating func recordBoundary(_ pair: VPAClockPair) {
        switch pair.phase {
        case .beforeStart: break
        case .quietStart: quietStartTick = pair.continuousTick
        case .playRequest: playRequestTick = pair.continuousTick
        case .plannedTail: plannedTailStartTick = pair.continuousTick
        case .postRollStart: postRollStartTick = pair.continuousTick
        case .beforeStop:
            postRollEndTick = pair.continuousTick
            normalStopBoundaryTick = pair.continuousTick
        }
    }

    private mutating func invalidClock(_ status: String) throws -> Never {
        clockInvalid = true
        clockEvidenceStatus = status
        throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
    }
}
