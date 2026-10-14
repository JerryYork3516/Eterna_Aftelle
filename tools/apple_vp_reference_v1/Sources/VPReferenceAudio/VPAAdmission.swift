import CoreAudio
import Foundation
import VPReferenceCore

struct VPAAdmission {
    let request: VPARequest
    let registrationSHA256: String
    let input: AudioDeviceSnapshot
    let output: AudioDeviceSnapshot
    var materialSafety: VPAMaterialSafety?

    static func prepare(request: VPARequest, material: PCMSourceMaterial?) throws -> Self {
        let safety = try inspectMaterial(request: request, material: material)
        let registered = try EngineeringFailure.check(stage: .command, code: .invalidArguments) {
            try SourceProbeRegistrationFile.load(request.targetRegistrationURL)
        }
        return try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            let inputID = try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
            let outputID = try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
            let input = try AudioDeviceSnapshot.read(identifier: inputID)
            let output = try AudioDeviceSnapshot.read(identifier: outputID)
            try registered.registration.validateDefaults(
                inputID: input.anonymousID, outputID: output.anonymousID,
                isUSB: input.transport == kAudioDeviceTransportTypeUSB,
                isBuiltIn: output.transport == kAudioDeviceTransportTypeBuiltIn)
            return Self(
                request: request, registrationSHA256: registered.sha256, input: input, output: output,
                materialSafety: safety)
        }
    }

    static func inspectMaterial(request: VPARequest, material: PCMSourceMaterial?) throws -> VPAMaterialSafety {
        guard let material else { throw EngineeringFailure(stage: .sourceMaterial, code: .materialIdentityMismatch) }
        try validateMaterial(request: request, identity: material.identity)
        return try VPAMaterialSafety.inspect(material.buffer)
    }

    static func validateMaterial(request: VPARequest, identity: PCMSourceIdentity?) throws {
        guard let identity, identity.sha256 == request.materialSHA256,
            identity.nativePCMSHA256 == request.nativePCMSHA256,
            identity.nativeFormat.sampleRate.isFinite, identity.nativeFormat.sampleRate > 0,
            identity.nativeFormat.formatFlags & kAudioFormatFlagIsFloat != 0,
            identity.nativeFormat.bitsPerChannel == 32,
            Double(identity.sourceFrameCount) == VPARequest.materialSeconds * identity.nativeFormat.sampleRate,
            identity.sourceStartFrame == 0
        else { throw EngineeringFailure(stage: .sourceMaterial, code: .materialIdentityMismatch) }
    }

    static func requirePlaybackStarted(_ playing: Bool) throws {
        guard playing else { throw EngineeringFailure(stage: .engineStart, code: .experimentPlaybackFailed) }
    }

    static func validateStopped(_ manifest: AudioRunManifest) throws {
        guard let state = manifest.postStopState, let formats = manifest.postStopFormats,
            let hardware = manifest.postStopHardwareOutputFormat
        else { throw EngineeringFailure(stage: .vpConfiguration, code: .formatReadFailed) }
        try RunningConfigurationPlan.validate(
            configured: manifest.configured, expectedHardwareOutput: manifest.hardwareOutputFormat,
            actual: RunningConfigurationSnapshot(state: state, formats: formats, hardwareOutput: hardware))
    }

    func validateRoute(_ route: AudioRouteSnapshot) throws {
        guard route.defaultInput.transport == kAudioDeviceTransportTypeUSB,
            route.defaultOutput.transport == kAudioDeviceTransportTypeBuiltIn
        else { throw EngineeringFailure(stage: .deviceBinding, code: .unsupportedRoute) }
        guard route.defaultInput == input, route.defaultOutput == output else {
            throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged)
        }
        if request.configuration.mode == .enabled {
            // Reuse diagnostic admission only; the no-play probe contract is unchanged.
            try SourceProbeRoutePolicy.validate(route)
        } else {
            guard route.hasVerifiedBinding else {
                throw EngineeringFailure(stage: .deviceBinding, code: .deviceBindingMismatch)
            }
        }
    }
}
