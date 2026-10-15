import AVFoundation
import Foundation
import VPRecorder
import VPReferenceCore

struct VPCPCMRead: Encodable {
    var coverage: VPCCoverage
    var reference: VPCRenderReference
    var distribution: VPCRenderDistribution
    var inputChannels: [VPBChannelStatistics] = []
    var renderChannels: [VPBChannelStatistics] = []
    var renderPlayNonZeroSamples: UInt64 = 0
    private var pendingRenderHost: UInt64?
    private var pendingPlayNonZero: UInt64 = 0
    var firstRenderSignal: SignalAnchor?
    var lastRenderSignal: SignalAnchor?
    var status = "UNVERIFIED"
    let meaning = "Native digital samples only; Render is not speaker pressure, speech content or physical overlap"

    struct SignalAnchor: Encodable {
        let recordIndex: UInt64
        let bufferHostTime: UInt64
        let sampleTime: Int64
        let channel: Int
        let meaning = "Sample index in this buffer; hostTime is the buffer anchor, not acoustic sample arrival"
    }

    static func evaluate(
        directory: URL, events: [VPBClock], receipts: [VPBDisplayReceipt], arm: UInt64?,
        material: AVAudioPCMBuffer? = nil
    ) throws -> Self {
        let url = directory.appendingPathComponent("evidence.vp0")
        let before = url.path.withCString { vp_recorder_validate_file($0) }
        guard before.complete, before.checksum_matches, before.invalid_reasons == 0,
            before.record_count > 0, before.record_count <= 4_096,
            before.pcm_bytes <= vp_recorder_default_config().maximum_pcm_bytes
        else { throw failure() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let file = try VPBPCMRead.read(handle, count: 56)
        guard VPBPCMRead.u64(file, 0) == 0x3152_4345_5250_5656,
            VPBPCMRead.u32(file, 8) == 1, VPBPCMRead.u32(file, 12) == 56,
            VPBPCMRead.u32(file, 16) == 392, VPBPCMRead.u32(file, 20) == 24 + MemoryLayout<VPRecorderSnapshot>.stride,
            VPBPCMRead.u32(file, 28) == 0x0102_0304,
            let arm, VPBPCMRead.u64(file, 48) == arm, events.count == 9, events[1].continuous >= arm,
            events[1].seconds(events[1].continuous - arm) <= 2, events[8].continuous >= arm,
            events[8].seconds(events[8].continuous - arm) < 16
        else { throw failure() }
        var result = Self(
            coverage: VPCCoverage(events: events, receipts: receipts),
            reference: VPCRenderReference(source: material), distribution: VPCRenderDistribution(receipts: receipts))
        var total: UInt64 = 0
        for index in 0..<before.record_count {
            try autoreleasepool {
                let header = try VPBPCMRead.read(handle, count: 392)
                var identity = VPFrameIdentity()
                var buffers: UInt32 = 0
                var bytes: UInt64 = 0
                guard url.path.withCString({ vp_recorder_read_identity($0, index, &identity, &buffers, &bytes) }),
                    VPBPCMRead.u32(header, 0) == 0x3152_4356, VPBPCMRead.u32(header, 4) == 1,
                    VPBPCMRead.u32(header, 8) == 392, VPBPCMRead.u64(header, 16) == index,
                    VPBPCMRead.u32(header, 12) == identity.stream_kind,
                    VPBPCMRead.u32(header, 24) == identity.frame_count, VPBPCMRead.u32(header, 128) == buffers,
                    buffers > 0, buffers <= 32, bytes == UInt64(VPBPCMRead.u32(header, 28)),
                    bytes <= UInt64(VP_SLOT_BYTES)
                else { throw failure() }
                result.coverage.include(identity)
                let payload = try VPBPCMRead.read(handle, count: Int(bytes))
                total += bytes
                try result.include(payload, header: header, identity: identity, index: index, events: events)
            }
        }
        let after = url.path.withCString { vp_recorder_validate_file($0) }
        guard after.complete, after.checksum_matches, after.invalid_reasons == 0,
            after.record_count == before.record_count, after.pcm_bytes == before.pcm_bytes, total == before.pcm_bytes
        else { throw failure() }
        result.finish(expectedRecords: before.record_count, events: events)
        return result
    }

    private mutating func finish(expectedRecords: UInt64, events: [VPBClock]) {
        coverage.finish(expectedRecords: expectedRecords)
        let finite = (inputChannels + renderChannels).allSatisfy { $0.nonFinite == 0 }
        reference.finish(events: events)
        distribution.finish(reference: reference)
        let playbackVerified = distribution.status == "MATCHED_SOURCE_AND_DOUBLE_TALK_DIGITAL_SIGNAL"
        if coverage.formalWindowsCovered, playbackVerified, finite {
            status = "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT"
        }
    }

    private mutating func include(
        _ data: Data, header: Data, identity: VPFrameIdentity, index: UInt64, events: [VPBClock]
    ) throws {
        let layout = try Self.layout(data, header: header, identity: identity)
        let count = layout.channels
        let frames = layout.frames
        let planar = layout.planar
        let render = identity.stream_kind == UInt32(VP_STREAM_RENDER)
        var channels = render ? renderChannels : inputChannels
        if channels.isEmpty { channels = Array(repeating: VPBChannelStatistics(), count: count) }
        guard channels.count == count else { throw Self.failure() }
        // A whole block is admitted only after its next Render host anchor is also inside play.
        if render {
            reference.prepare(identity)
            try distribution.prepare(identity)
            acceptPendingRender(identity: identity, start: events[3], end: events[6])
            pendingRenderHost = identity.host_time
            pendingPlayNonZero = 0
        }
        for frame in 0..<frames {
            for channel in 0..<count {
                let offset = planar ? channel * frames + frame : frame * count + channel
                let value = Float(bitPattern: VPBPCMRead.u32(data, offset * 4))
                channels[channel].include(value)
                if render {
                    let sample = identity.sample_time.addingReportingOverflow(Int64(frame))
                    guard !sample.overflow else { throw Self.failure() }
                    let anchor = SignalAnchor(
                        recordIndex: index, bufferHostTime: identity.host_time,
                        sampleTime: sample.partialValue, channel: channel)
                    reference.include(value, channel: channel, sample: sample.partialValue)
                    try distribution.include(value, anchor: anchor, channelCount: count)
                    if value.isFinite, value != 0 {
                        if firstRenderSignal == nil { firstRenderSignal = anchor }
                        lastRenderSignal = anchor
                        pendingPlayNonZero += 1
                    }
                }
            }
        }
        if render { renderChannels = channels } else { inputChannels = channels }
    }

    private mutating func acceptPendingRender(identity: VPFrameIdentity, start: VPBClock, end: VPBClock) {
        guard let previous = pendingRenderHost, previous >= start.absoluteAfter,
            identity.host_time > previous, identity.host_time <= end.absoluteBefore
        else { return }
        renderPlayNonZeroSamples += pendingPlayNonZero
    }

    private struct Layout {
        let channels: Int
        let frames: Int
        let planar: Bool
    }

    private static func layout(_ data: Data, header: Data, identity: VPFrameIdentity) throws -> Layout {
        let format = identity.format
        let count = Int(format.mChannelsPerFrame)
        let frames = Int(identity.frame_count)
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard count > 0, count <= 32, format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
            format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
            format.mBytesPerFrame == (planar ? 4 : count * 4),
            VPBPCMRead.u32(header, 128) == (planar ? count : 1), data.count == frames * count * 4
        else { throw Self.failure() }
        for plane in 0..<(planar ? count : 1) {
            guard VPBPCMRead.u32(header, 136 + plane * 8) == (planar ? 1 : count),
                VPBPCMRead.u32(header, 140 + plane * 8) == frames * (planar ? 4 : count * 4)
            else { throw Self.failure() }
        }
        return Layout(channels: count, frames: frames, planar: planar)
    }

    private static func failure() -> EngineeringFailure {
        EngineeringFailure(stage: .recorder, code: .experimentCoverageUnverified)
    }
}
