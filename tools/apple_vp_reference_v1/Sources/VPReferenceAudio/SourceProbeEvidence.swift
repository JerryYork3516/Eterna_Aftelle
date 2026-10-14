import Foundation
import VPReferenceCore

struct SourceProbeEvidence: Encodable {
    struct Cue: Encodable {
        let phase: SourceProbePhase
        let armRelativeSeconds: Double
    }

    let schemaVersion = 1
    let entryPoint = "source-probe"
    let sourceStatus = "SOURCE_UNVERIFIED"
    let sourceQualificationGranted = false
    let channelRoles = "DEVICE_UNVERIFIED; no selection or downmix"
    let stimulusStatus = "NOT_ANALYZED; cue times are not acoustic arrival times"
    let stimulusProtocol = SourceProbeRegistration.protocolID
    let maximumAdmissionSeconds = SourceProbeRequest.maximumSeconds
    let registrationSHA256: String
    let defaultInputBeforeVP: AudioDeviceSnapshot
    let defaultOutputBeforeVP: AudioDeviceSnapshot
    var cues: [Cue] = []
    var inputObservation = "NOT_MEASURED"
    var runningEngineObserved: Bool?
    var postStopEngineObserved: Bool?
}
