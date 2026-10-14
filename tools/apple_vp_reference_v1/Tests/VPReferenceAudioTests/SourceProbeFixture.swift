import AVFoundation
import CoreAudio
import Foundation
import VPRecorder
import XCTest

@testable import VPReferenceAudio
@testable import VPReferenceCore

final class SourceProbeFixture {
    let directory: URL
    let configuration: RunConfiguration
    let recorder: RecorderOwner
    let startTick: UInt64
    var manifest: AudioRunManifest

    init(maximumSeconds: UInt32 = 8) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vp0-probe-synthetic-\(UUID().uuidString)")
        configuration = RunConfiguration(
            mode: .enabled, durationSeconds: 8, diagnosticsArmed: true, audioExplicitlyEnabled: true,
            outputDirectory: directory, materialURL: nil, studyID: "synthetic-probe")
        recorder = try RecorderOwner(configuration: configuration, maximumSeconds: maximumSeconds)
        startTick = vp_recorder_now_tick()
        let format = NativeAudioFormat(
            sampleRate: 16_000, channelCount: 3, formatID: kAudioFormatLinearPCM,
            formatFlags: 41, bytesPerFrame: 4, bitsPerChannel: 32)
        let formats = AudioFormats(input: format, mixer: format, output: format)
        let state = VoiceProcessingState(
            inputEnabled: true, outputEnabled: true, bypassed: false, agcEnabled: true, inputMuted: false)
        manifest = AudioRunManifest(
            runID: UUID().uuidString, studyID: "synthetic-probe", buildSHA256: String(repeating: "c", count: 64),
            configSHA256: String(repeating: "d", count: 64), mode: .enabled, durationSeconds: 8,
            configured: ConfiguredEngine(mode: .enabled, state: state, formats: formats, preConnectionFormats: formats),
            routeBefore: Self.route(), hardwareOutputFormat: format, material: nil, materialStatus: "RESIDENT_SILENT",
            inputMeaning: "VP_ON_NATIVE_CAPTURE", terminalStatus: "PREPARED_NOT_STARTED")
        manifest.sourceProbe = SourceProbeEvidence(
            registrationSHA256: String(repeating: "e", count: 64),
            defaultInputBeforeVP: Self.input, defaultOutputBeforeVP: Self.output)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    static let input = AudioDeviceSnapshot(
        anonymousID: String(repeating: "a", count: 64), transport: kAudioDeviceTransportTypeUSB,
        nominalSampleRate: 16_000)
    static let output = AudioDeviceSnapshot(
        anonymousID: String(repeating: "b", count: 64), transport: kAudioDeviceTransportTypeBuiltIn,
        nominalSampleRate: 48_000)

    static func route(
        nodeInput: AudioDeviceSnapshot? = nil, nodeOutput: AudioDeviceSnapshot? = nil
    ) -> AudioRouteSnapshot {
        AudioRouteSnapshot(
            defaultInput: input, defaultOutput: output, inputNodeDevice: nodeInput ?? output,
            outputNodeDevice: nodeOutput ?? output,
            deviceBindingStatus: "UNAVAILABLE", microphoneModeSource: "synthetic",
            preferredMicrophoneMode: "UNAVAILABLE",
            activeMicrophoneMode: "UNAVAILABLE", inputAggregate: nil, outputAggregate: nil)
    }

    func submitThreeChannels(tick: UInt64? = nil) -> Bool {
        var identity = VPFrameIdentity()
        identity.stream_kind = UInt32(VP_STREAM_INPUT)
        identity.frame_count = 4
        identity.format = AudioStreamBasicDescription(
            mSampleRate: 16_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: 41,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 3, mBitsPerChannel: 32,
            mReserved: 0)
        identity.sample_time_valid = true
        identity.host_time_valid = true
        identity.callback_enter_tick = tick ?? startTick + 1
        let buffers = AudioBufferList.allocate(maximumBuffers: 3)
        defer { free(buffers.unsafeMutablePointer) }
        buffers.unsafeMutablePointer.pointee.mNumberBuffers = 3
        var one: [Float] = [1, 2, 3, 4]
        var two: [Float] = [-5, -6, -7, -8]
        var three: [Float] = [9, 10, 11, 12]
        return one.withUnsafeMutableBytes { aBytes in
            two.withUnsafeMutableBytes { bBytes in
                three.withUnsafeMutableBytes { cBytes in
                    buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: aBytes.baseAddress)
                    buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: bBytes.baseAddress)
                    buffers[2] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: cBytes.baseAddress)
                    return vp_recorder_submit(recorder.handle, &identity, buffers.unsafePointer)
                }
            }
        }
    }

    func finish() throws -> AudioRunOutcome {
        try SourceProbe().finish(recorder: recorder, manifest: &manifest, directory: directory)
    }
}
