import AVFoundation
import CoreAudio
import Foundation
import VPReferenceCore

struct AudioRouteSnapshot: Codable, Equatable {
    let defaultInput: AudioDeviceSnapshot
    let defaultOutput: AudioDeviceSnapshot
    let inputNodeDevice: AudioDeviceSnapshot
    let outputNodeDevice: AudioDeviceSnapshot
    let deviceBindingStatus: String
    let microphoneModeSource: String
    let preferredMicrophoneMode: String
    let activeMicrophoneMode: String
    let inputAggregate: AggregateDeviceSnapshot?
    let outputAggregate: AggregateDeviceSnapshot?

    var hasVerifiedBinding: Bool {
        deviceBindingStatus == "NODE_IDS_MATCH_DEFAULTS" || deviceBindingStatus == "AGGREGATE_IO_DIRECTION_QUALIFIED"
    }

    static func read(engine: AVAudioEngine) throws -> Self {
        let inputID = try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let outputID = try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let inputDevice = try AudioDeviceSnapshot.read(identifier: inputID)
        let outputDevice = try AudioDeviceSnapshot.read(identifier: outputID)
        guard inputDevice.transport == kAudioDeviceTransportTypeUSB,
            outputDevice.transport == kAudioDeviceTransportTypeBuiltIn
        else {
            throw EngineeringFailure(stage: .deviceBinding, code: .unsupportedRoute)
        }
        let inputNodeID = engine.inputNode.auAudioUnit.deviceID
        let outputNodeID = engine.outputNode.auAudioUnit.deviceID
        let inputNode = try AudioDeviceSnapshot.read(identifier: inputNodeID)
        let outputNode = try AudioDeviceSnapshot.read(identifier: outputNodeID)
        let bindingMatches =
            inputNode.anonymousID == inputDevice.anonymousID
            && outputNode.anonymousID == outputDevice.anonymousID
        let inputAggregate =
            inputNode.transport == kAudioDeviceTransportTypeAggregate
            ? AggregateDeviceSnapshot.capture(inputNodeID) : nil
        let outputAggregate =
            outputNode.transport == kAudioDeviceTransportTypeAggregate
            ? AggregateDeviceSnapshot.capture(outputNodeID) : nil
        let inputQualified =
            inputNode == inputDevice
            || inputAggregate?.qualifies(node: inputNode, defaultInput: inputDevice, defaultOutput: outputDevice)
                == true
        let outputQualified =
            outputNode == outputDevice
            || outputAggregate?.qualifies(node: outputNode, defaultInput: inputDevice, defaultOutput: outputDevice)
                == true
        guard try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice) == inputID,
            try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice) == outputID
        else { throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged) }
        let status =
            bindingMatches
            ? "NODE_IDS_MATCH_DEFAULTS"
            : (inputQualified && outputQualified ? "AGGREGATE_IO_DIRECTION_QUALIFIED" : "UNAVAILABLE")
        return Self(
            defaultInput: inputDevice, defaultOutput: outputDevice,
            inputNodeDevice: inputNode, outputNodeDevice: outputNode,
            deviceBindingStatus: status,
            microphoneModeSource: "AVCaptureDevice process property; this engine attribution UNVERIFIED",
            preferredMicrophoneMode: microphoneMode(preferred: true),
            activeMicrophoneMode: microphoneMode(preferred: false),
            inputAggregate: inputAggregate, outputAggregate: outputAggregate
        )
    }

    private static func microphoneMode(preferred: Bool) -> String {
        if #available(macOS 12.0, *) {
            let mode = preferred ? AVCaptureDevice.preferredMicrophoneMode : AVCaptureDevice.activeMicrophoneMode
            switch mode {
            case .standard: return "STANDARD"
            case .wideSpectrum: return "WIDE_SPECTRUM"
            case .voiceIsolation: return "VOICE_ISOLATION"
            @unknown default: return "UNAVAILABLE"
            }
        }
        return "UNAVAILABLE"
    }
}
