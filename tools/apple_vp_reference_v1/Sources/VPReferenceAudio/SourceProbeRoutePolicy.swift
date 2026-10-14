import CoreAudio
import VPReferenceCore

enum SourceProbeRoutePolicy {
    static func validateEngineState(isRunning: Bool, stopped: Bool) throws {
        guard isRunning != stopped else {
            throw EngineeringFailure(stage: stopped ? .engineStop : .engineStart, code: .probeEngineStateMismatch)
        }
    }

    static func validate(_ route: AudioRouteSnapshot) throws {
        guard route.defaultInput.transport == kAudioDeviceTransportTypeUSB,
            route.defaultOutput.transport == kAudioDeviceTransportTypeBuiltIn
        else { throw EngineeringFailure(stage: .deviceBinding, code: .unsupportedRoute) }
        let observedBuiltInPresentation =
            route.inputNodeDevice == route.defaultOutput && route.outputNodeDevice == route.defaultOutput
            && route.inputAggregate == nil && route.outputAggregate == nil
        guard route.hasVerifiedBinding || observedBuiltInPresentation else {
            throw EngineeringFailure(stage: .deviceBinding, code: .deviceBindingMismatch)
        }
    }
}
