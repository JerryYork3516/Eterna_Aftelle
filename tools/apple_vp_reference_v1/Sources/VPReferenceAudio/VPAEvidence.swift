import VPReferenceCore

struct VPAEvidence: Encodable {
    let protocolID = VPARequest.protocolID
    let protocolApproval = "PROPOSED; requires separate controller and site authorization"
    let deviceRegistrationUse = "Existing P3/P4 targets only; not the source-probe stimulus contract"
    let sourceStatus = "SOURCE_UNVERIFIED"
    let sourceQualificationGranted = false
    let registrationSHA256: String
    let quietSeconds = VPARequest.quietSeconds
    let materialSeconds = VPARequest.materialSeconds
    let tailSeconds = VPARequest.tailSeconds
    let maximumObservationSeconds = VPARequest.maximumObservationSeconds
    let timelineMeaning = "Control requests only; not measured acoustic onset/end or speaker sound pressure"
    var armTick: UInt64?
    var quietStartTick: UInt64?
    var playRequestTick: UInt64?
    var plannedTailStartTick: UInt64?
    var stopRequestTick: UInt64?
    var windowsCompleted = false
    var observationCount = 0
    var maximumObservationTicks: UInt64 = 0
    var runningEngineObserved: Bool?
    var postStopEngineObserved: Bool?
    var playerVolume: Float?
    var mixerVolume: Float?
    var playerPlayingAfterRequest: Bool?
}
