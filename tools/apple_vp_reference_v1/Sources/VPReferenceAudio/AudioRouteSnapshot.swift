import AVFoundation
import CoreAudio
import Foundation

struct AudioRouteSnapshot: Codable, Equatable {
    let defaultInput: AudioDeviceSnapshot
    let defaultOutput: AudioDeviceSnapshot
    let inputNodeDevice: AudioDeviceSnapshot
    let outputNodeDevice: AudioDeviceSnapshot
    let deviceBindingStatus: String
    let microphoneModeSource: String
    let preferredMicrophoneMode: String
    let activeMicrophoneMode: String

    static func read(engine: AVAudioEngine) throws -> Self {
        let inputID = try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let outputID = try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let inputDevice = try AudioDeviceSnapshot.read(identifier: inputID)
        let outputDevice = try AudioDeviceSnapshot.read(identifier: outputID)
        guard inputDevice.transport == kAudioDeviceTransportTypeUSB,
            outputDevice.transport == kAudioDeviceTransportTypeBuiltIn
        else {
            throw AudioReferenceError.unsupportedRoute
        }
        let inputNode = try AudioDeviceSnapshot.read(identifier: engine.inputNode.auAudioUnit.deviceID)
        let outputNode = try AudioDeviceSnapshot.read(identifier: engine.outputNode.auAudioUnit.deviceID)
        let bindingMatches =
            inputNode.anonymousID == inputDevice.anonymousID
            && outputNode.anonymousID == outputDevice.anonymousID
        return Self(
            defaultInput: inputDevice, defaultOutput: outputDevice,
            inputNodeDevice: inputNode, outputNodeDevice: outputNode,
            deviceBindingStatus: bindingMatches ? "NODE_IDS_MATCH_DEFAULTS" : "UNAVAILABLE",
            microphoneModeSource: "AVCaptureDevice process property; this engine attribution UNVERIFIED",
            preferredMicrophoneMode: microphoneMode(preferred: true),
            activeMicrophoneMode: microphoneMode(preferred: false)
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
