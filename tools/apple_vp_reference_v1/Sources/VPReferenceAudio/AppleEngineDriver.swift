import AVFoundation
import Foundation
import VPReferenceCore

final class AppleEngineDriver: EngineConfigurationDriving {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    private let material: AVAudioPCMBuffer?

    init(material: AVAudioPCMBuffer?) {
        self.material = material
    }

    var isRunning: Bool { engine.isRunning }

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        guard !engine.isRunning else { throw AudioReferenceError.inconsistentRuntimeState }
        try engine.inputNode.setVoiceProcessingEnabled(enabled)
    }

    func readVoiceProcessingState() throws -> VoiceProcessingState {
        let input = engine.inputNode
        return VoiceProcessingState(
            inputEnabled: input.isVoiceProcessingEnabled,
            outputEnabled: engine.outputNode.isVoiceProcessingEnabled,
            bypassed: input.isVoiceProcessingBypassed,
            agcEnabled: input.isVoiceProcessingAGCEnabled,
            inputMuted: input.isVoiceProcessingInputMuted
        )
    }

    func readFormats() throws -> AudioFormats {
        AudioFormats(
            input: Self.snapshot(engine.inputNode.outputFormat(forBus: 0)),
            mixer: Self.snapshot(engine.mainMixerNode.outputFormat(forBus: 0)),
            output: Self.snapshot(engine.outputNode.inputFormat(forBus: 0))
        )
    }

    func connectPlayback(using formats: AudioFormats) throws {
        guard !engine.isRunning else { throw AudioReferenceError.inconsistentRuntimeState }
        let previousOutput = engine.outputNode.inputFormat(forBus: 0)
        guard Self.snapshot(previousOutput) == formats.output else {
            throw AudioReferenceError.inconsistentRuntimeState
        }
        let outputFormat =
            engine.inputNode.isVoiceProcessingEnabled
            ? engine.inputNode.outputFormat(forBus: 0) : previousOutput
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: material?.format ?? outputFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
    }

    func schedulePlayback() {
        if let material {
            player.scheduleBuffer(material, at: nil, options: [])
        }
    }

    static func snapshot(_ format: AVAudioFormat) -> NativeAudioFormat {
        let native = format.streamDescription.pointee
        return NativeAudioFormat(
            sampleRate: native.mSampleRate, channelCount: native.mChannelsPerFrame,
            formatID: native.mFormatID, formatFlags: native.mFormatFlags,
            bytesPerFrame: native.mBytesPerFrame, bitsPerChannel: native.mBitsPerChannel
        )
    }
}
