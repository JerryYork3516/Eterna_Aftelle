import AVFoundation
import AudioToolbox
import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPCPCMFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vp-c-synthetic-\(UUID().uuidString)")
    let owner: RecorderOwner
    var recorder: OpaquePointer { owner.handle }
    let arm: UInt64 = vp_recorder_now_tick()
    var events: [VPBClock] {
        let ids = [
            "beforeStart", "observationStart", "RESIDENT_START", "playRequest", "NEAR_CONTINUOUS",
            "RESIDENT_AFTER", "TAIL", "POST_ROLL", "beforeStop"
        ]
        let ticks: [UInt64] = [100, 1_000, 3_002, 3_005, 5_006, 10_008, 11_010, 14_012, 14_514]
        return zip(ids, ticks).map {
            VPBClock(
                id: $0, absoluteBefore: $1, continuous: $1 + arm, absoluteAfter: $1 + 1, numerator: 1_000_000,
                denominator: 1)
        }
    }

    var receipts: [VPBDisplayReceipt] {
        VPCCue.allCases.enumerated().map { index, phase in
            let event = events[[1, 2, 4, 5, 6, 7][index]]
            func clock(_ delay: UInt64) -> VPBClock {
                VPBClock(
                    id: phase.rawValue, absoluteBefore: event.absoluteBefore + delay,
                    continuous: event.continuous + delay, absoluteAfter: event.absoluteAfter + delay,
                    numerator: event.numerator, denominator: event.denominator)
            }
            return VPBDisplayReceipt(cueID: phase.rawValue, requested: clock(2), displayed: clock(4), visible: true)
        }
    }

    func receipt(phase: VPCCue, request: UInt64, display: UInt64) -> VPBDisplayReceipt {
        func clock(_ tick: UInt64) -> VPBClock {
            VPBClock(
                id: phase.rawValue, absoluteBefore: tick, continuous: tick + arm, absoluteAfter: tick + 1,
                numerator: 1_000_000, denominator: 1)
        }
        return VPBDisplayReceipt(
            cueID: phase.rawValue, requested: clock(request), displayed: clock(display), visible: true)
    }

    init() throws {
        let config = RunConfiguration(
            mode: .enabled, durationSeconds: 16,
            diagnosticsArmed: true, audioExplicitlyEnabled: true, outputDirectory: directory,
            materialURL: nil, studyID: "synthetic-double-talk")
        owner = try RecorderOwner(configuration: config, maximumSeconds: 16)
        XCTAssertTrue(vp_recorder_arm(recorder, arm))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func material(amplitude: Float = 0.25) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 1_000,
                channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        let values = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<8_000 { values[index] = amplitude }
        return buffer
    }

    func identity(host: UInt64, sample: Int64, planar: Bool = false) -> VPFrameIdentity {
        var value = VPFrameIdentity()
        value.stream_kind = UInt32(VP_STREAM_INPUT)
        value.frame_count = 100
        value.format = AudioStreamBasicDescription(
            mSampleRate: 1_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: planar ? 41 : 9, mBytesPerPacket: planar ? 4 : 12, mFramesPerPacket: 1,
            mBytesPerFrame: planar ? 4 : 12,
            mChannelsPerFrame: 3, mBitsPerChannel: 32, mReserved: 0)
        value.host_time_valid = true
        value.sample_time_valid = true
        value.host_time = host
        value.sample_time = sample
        value.callback_enter_tick = arm + 1
        return value
    }

    func write(
        through end: UInt64 = 14_900, input: Bool = true, render: Bool = true,
        amplitude: Float = 0.25, signal: String = "play"
    ) throws {
        var records: UInt64 = 0
        var sample: Int64 = 0
        for host in stride(from: UInt64(900), through: end, by: 100) {
            for stream in [UInt32(VP_STREAM_INPUT), UInt32(VP_STREAM_RENDER)] {
                if stream == UInt32(VP_STREAM_INPUT) && !input { continue }
                if stream == UInt32(VP_STREAM_RENDER) && !render { continue }
                var value = identity(host: host, sample: sample)
                value.stream_kind = stream
                if signal == "gapInput", stream == UInt32(VP_STREAM_INPUT), host >= 7_000 { value.sample_time += 1 }
                if signal == "gapRender", stream == UInt32(VP_STREAM_RENDER), host >= 7_000 { value.sample_time += 1 }
                var samples: [Float] = (0..<300).map {
                    if stream == UInt32(VP_STREAM_INPUT) { return 0.125 }
                    return renderSample(host: host, offset: $0, amplitude: amplitude, signal: signal)
                }
                var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer())
                let accepted = samples.withUnsafeMutableBytes { bytes in
                    buffer.mBuffers = AudioBuffer(mNumberChannels: 3, mDataByteSize: 1_200, mData: bytes.baseAddress)
                    return vp_recorder_submit(recorder, &value, &buffer)
                }
                if !accepted, signal.hasPrefix("gap") { return }
                XCTAssertTrue(accepted)
                records += 1
                let deadline = Date().addingTimeInterval(2)
                while vp_recorder_snapshot(recorder).written_records < records {
                    guard Date() < deadline else { throw AudioReferenceError.recorderUnavailable }
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
            sample += 100
        }
    }
    private func renderSample(host: UInt64, offset: Int, amplitude: Float, signal: String) -> Float {
        guard offset % 3 == 2 else { return 0 }
        let frame = offset / 3
        switch signal {
        case "crossTail": return host == 11_000 && offset == 299 ? amplitude : 0
        case "quiet": return host < 3_000 ? amplitude : 0
        case "preOnly": return host >= 3_100 && host < 5_000 ? amplitude : 0
        case "pulse": return host == 6_100 && frame == 0 ? amplitude : 0
        case "shortPulses": return host >= 3_100 && host <= 11_000 && frame == 0 ? amplitude : 0
        case "earlyFull": return host >= 1_100 && host <= 9_000 ? amplitude : 0
        case "lateFull": return host >= 5_100 && host <= 13_000 ? amplitude : 0
        case "leadingSilence": return host >= 3_600 && host <= 11_000 ? amplitude : 0
        default: return host >= 3_100 && host <= 11_000 ? amplitude : 0
        }
    }

}
