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
                let active = signal == "quiet" ? host < 3_000 : host >= 3_100 && host <= 11_000
                var samples: [Float] = (0..<300).map {
                    if stream == UInt32(VP_STREAM_INPUT) { return 0.125 }
                    if signal == "crossTail" { return host == 11_000 && $0 == 299 ? amplitude : 0 }
                    return active && $0 % 3 == 2 ? amplitude : 0
                }
                var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer())
                let accepted = samples.withUnsafeMutableBytes { bytes in
                    buffer.mBuffers = AudioBuffer(mNumberChannels: 3, mDataByteSize: 1_200, mData: bytes.baseAddress)
                    return vp_recorder_submit(recorder, &value, &buffer)
                }
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
}
