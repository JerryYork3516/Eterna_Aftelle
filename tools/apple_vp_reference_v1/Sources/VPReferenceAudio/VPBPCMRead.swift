import Foundation
import VPRecorder
import VPReferenceCore

struct VPBChannelStatistics: Encodable {
    var samples: UInt64 = 0
    var nonFinite: UInt64 = 0
    var fullScale: UInt64 = 0
    var outOfRange: UInt64 = 0
    var peak: Double = 0
    var sumSquares: Double = 0
    var rms: Double { samples > nonFinite ? sqrt(sumSquares / Double(samples - nonFinite)) : 0 }

    private enum CodingKeys: String, CodingKey { case samples, nonFinite, fullScale, outOfRange, peak, rms }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(samples, forKey: .samples)
        try values.encode(nonFinite, forKey: .nonFinite)
        try values.encode(fullScale, forKey: .fullScale)
        try values.encode(outOfRange, forKey: .outOfRange)
        try values.encode(peak, forKey: .peak)
        try values.encode(rms, forKey: .rms)
    }

    mutating func include(_ value: Float) {
        samples += 1
        guard value.isFinite else {
            nonFinite += 1
            return
        }
        let magnitude = abs(Double(value))
        if magnitude == 1 { fullScale += 1 }
        if magnitude > 1 { outOfRange += 1 }
        peak = max(peak, magnitude)
        sumSquares += Double(value) * Double(value)
    }
}

struct VPBPCMRead: Encodable {
    var coverage: VPBInputCoverage
    var inputChannels: [VPBChannelStatistics] = []
    var status = "UNVERIFIED"
    var containerArmTick: UInt64 = 0
    let meaning = "Whole native Input descriptive statistics; content/first-last words require private manual review"

    static func evaluate(
        directory: URL, events: [VPBClock], receipts: [VPBDisplayReceipt], expectedArmTick: UInt64? = nil
    ) throws -> Self {
        let url = directory.appendingPathComponent("evidence.vp0")
        let before = url.path.withCString { vp_recorder_validate_file($0) }
        guard before.complete, before.checksum_matches, before.invalid_reasons == 0,
            before.record_count > 0, before.record_count <= 4_096,
            before.pcm_bytes <= vp_recorder_default_config().maximum_pcm_bytes
        else { throw EngineeringFailure(stage: .recorder, code: .experimentCoverageUnverified) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let file = try read(handle, count: 56)
        guard u64(file, 0) == 0x3152_4345_5250_5656, u32(file, 8) == 1, u32(file, 12) == 56,
            u32(file, 16) == 392, u32(file, 20) == 24 + MemoryLayout<VPRecorderSnapshot>.stride,
            u32(file, 28) == 0x0102_0304
        else { throw EngineeringFailure(stage: .recorder, code: .experimentCoverageUnverified) }
        var result = Self(coverage: VPBInputCoverage(events: events, receipts: receipts))
        result.containerArmTick = u64(file, 48)
        if let expectedArmTick {
            guard result.containerArmTick == expectedArmTick, events.count == 10,
                events[1].continuous >= expectedArmTick, events[9].continuous >= events[1].continuous,
                events[1].seconds(events[1].continuous - expectedArmTick) <= 3,
                events[9].seconds(events[9].continuous - expectedArmTick) <= 16
            else { throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid) }
        }
        var payloadTotal: UInt64 = 0
        for index in 0..<before.record_count {
            try autoreleasepool {
                let header = try read(handle, count: 392)
                var identity = VPFrameIdentity()
                var buffers: UInt32 = 0
                var bytes: UInt64 = 0
                guard url.path.withCString({ vp_recorder_read_identity($0, index, &identity, &buffers, &bytes) }),
                    u32(header, 0) == 0x3152_4356, u32(header, 4) == 1, u32(header, 8) == 392,
                    u64(header, 16) == index, u32(header, 12) == identity.stream_kind,
                    u32(header, 24) == identity.frame_count, u32(header, 128) == buffers,
                    buffers > 0, buffers <= 32, bytes == UInt64(u32(header, 28)), bytes <= UInt64(VP_SLOT_BYTES)
                else { throw EngineeringFailure(stage: .recorder, code: .experimentCoverageUnverified) }
                result.coverage.include(identity, index: index)
                let payload = try read(handle, count: Int(bytes))
                payloadTotal += bytes
                if identity.stream_kind == UInt32(VP_STREAM_INPUT) {
                    try result.include(payload, header: header, identity: identity, buffers: Int(buffers))
                }
            }
        }
        try validateFinished(url: url, before: before, payloadTotal: payloadTotal)
        result.coverage.finish()
        result.status = result.coverage.status
        return result
    }

    private static func validateFinished(url: URL, before: VPFileValidation, payloadTotal: UInt64) throws {
        let after = url.path.withCString { vp_recorder_validate_file($0) }
        guard after.complete, after.checksum_matches, after.invalid_reasons == 0,
            after.record_count == before.record_count, after.pcm_bytes == payloadTotal,
            after.pcm_bytes == before.pcm_bytes
        else { throw EngineeringFailure(stage: .recorder, code: .experimentCoverageUnverified) }
    }

    private mutating func include(_ bytes: Data, header: Data, identity: VPFrameIdentity, buffers: Int) throws {
        let format = identity.format
        let count = Int(format.mChannelsPerFrame)
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard count > 0, count <= 32, format.mFormatID == kAudioFormatLinearPCM,
            format.mBitsPerChannel == 32, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
            format.mBytesPerFrame == (planar ? 4 : count * 4), buffers == (planar ? count : 1)
        else { throw EngineeringFailure(stage: .inputFormat, code: .inputFormatUnavailable) }
        if inputChannels.isEmpty { inputChannels = Array(repeating: VPBChannelStatistics(), count: count) }
        guard inputChannels.count == count else {
            throw EngineeringFailure(stage: .inputFormat, code: .inputFormatChanged)
        }
        let frames = Int(identity.frame_count)
        for plane in 0..<buffers {
            guard Self.u32(header, 136 + plane * 8) == (planar ? 1 : count),
                Self.u32(header, 140 + plane * 8) == frames * (planar ? 4 : count * 4)
            else { throw EngineeringFailure(stage: .inputFormat, code: .inputFormatUnavailable) }
        }
        guard bytes.count == frames * count * 4 else {
            throw EngineeringFailure(stage: .inputFormat, code: .inputFormatUnavailable)
        }
        for frame in 0..<frames {
            for channel in 0..<count {
                let sample = planar ? channel * frames + frame : frame * count + channel
                inputChannels[channel].include(Float(bitPattern: Self.u32(bytes, sample * 4)))
            }
        }
    }

    private static func read(_ handle: FileHandle, count: Int) throws -> Data {
        guard let bytes = try handle.read(upToCount: count), bytes.count == count else {
            throw EngineeringFailure(stage: .recorder, code: .experimentCoverageUnverified)
        }
        return bytes
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    private static func u64(_ data: Data, _ offset: Int) -> UInt64 {
        data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
    }
}
