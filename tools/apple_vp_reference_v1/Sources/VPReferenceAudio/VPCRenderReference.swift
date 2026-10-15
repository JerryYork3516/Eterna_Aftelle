import AVFoundation
import VPRecorder
import VPReferenceCore

struct VPCRenderReference: Encodable {
    struct Channel: Encodable {
        var sourceStartSample: Int64?
        var matchedFrames: UInt64 = 0
        var mismatches: UInt64 = 0
        var complete = false
        var startHostEarliest: UInt64?
        var startHostLatest: UInt64?
        var playCausalityVerified = false
    }

    let model =
        "Exact native Float32 mono source, same rate, integer alignment at first nonzero; no gain fitting or search"
    private(set) var status = "MATERIAL_COMPATIBILITY_UNVERIFIED"
    private(set) var sampleRate: Double = 0
    private(set) var sourceFrames = 0
    private(set) var channels: [Channel] = []
    private let source: AVAudioPCMBuffer?
    private var firstSourceSignal = 0
    private var firstRenderSample: Int64?
    private var supported = false
    private struct FrameAnchor {
        let hostTime: UInt64
        let sampleTime: Int64
    }
    private var anchors: [FrameAnchor] = []

    private enum CodingKeys: String, CodingKey { case model, status, sampleRate, sourceFrames, channels }

    init(source: AVAudioPCMBuffer?) {
        self.source = source
        guard let source, source.format.commonFormat == .pcmFormatFloat32, source.format.channelCount == 1,
            source.format.sampleRate >= 1_000, source.format.sampleRate <= 192_000,
            UInt64(source.frameLength) * 4 <= PCMSourceMaterial.maximumBytes,
            Double(source.frameLength) == source.format.sampleRate * 8,
            let samples = source.floatChannelData?[0]
        else { return }
        sourceFrames = Int(source.frameLength)
        sampleRate = source.format.sampleRate
        var first: Int?
        for index in 0..<sourceFrames {
            guard samples[index].isFinite, abs(samples[index]) <= 1 else { return }
            if first == nil, samples[index] != 0 { first = index }
        }
        guard let first else { return }
        firstSourceSignal = first
        supported = true
    }

    mutating func prepare(_ identity: VPFrameIdentity) {
        guard anchors.count < 4_096 else {
            supported = false
            return
        }
        anchors.append(
            FrameAnchor(hostTime: identity.host_time, sampleTime: identity.sample_time))
        guard supported else { return }
        guard identity.format.mSampleRate == sampleRate else {
            supported = false
            return
        }
        if channels.isEmpty {
            channels = Array(repeating: Channel(), count: Int(identity.format.mChannelsPerFrame))
            firstRenderSample = identity.sample_time
        }
    }

    mutating func include(_ value: Float, channel: Int, sample: Int64) {
        guard supported, channels.indices.contains(channel), let source, let values = source.floatChannelData?[0] else {
            return
        }
        if channels[channel].sourceStartSample == nil, value != 0 {
            let start = sample.subtractingReportingOverflow(Int64(firstSourceSignal))
            guard !start.overflow, let firstRenderSample, start.partialValue >= firstRenderSample else {
                supported = false
                return
            }
            channels[channel].sourceStartSample = start.partialValue
            channels[channel].matchedFrames = UInt64(firstSourceSignal)
        }
        guard let start = channels[channel].sourceStartSample else { return }
        let position = sample.subtractingReportingOverflow(start)
        guard !position.overflow else {
            supported = false
            return
        }
        if position.partialValue >= 0, position.partialValue < sourceFrames {
            if value.bitPattern == values[Int(position.partialValue)].bitPattern {
                channels[channel].matchedFrames += 1
            } else {
                channels[channel].mismatches += 1
            }
        } else if value != 0 {
            channels[channel].mismatches += 1
        }
    }

    mutating func finish(events: [VPBClock]) {
        for index in channels.indices {
            verifyStart(channel: index, events: events)
            channels[index].complete =
                supported && channels[index].playCausalityVerified
                && channels[index].mismatches == 0 && channels[index].matchedFrames == sourceFrames
        }
        if channels.contains(where: \.complete) { status = "EXACT_REGISTERED_SOURCE_SEQUENCE_SUPPORTED" }
    }
    private mutating func verifyStart(channel: Int, events: [VPBClock]) {
        guard let start = channels[channel].sourceStartSample, events.count == 9,
            let lower = anchors.last(where: { $0.sampleTime <= start }),
            let upper = anchors.first(where: { $0.sampleTime > start })
        else { return }
        channels[channel].startHostEarliest = lower.hostTime
        channels[channel].startHostLatest = upper.hostTime
        channels[channel].playCausalityVerified =
            lower.hostTime >= events[3].absoluteAfter
            && upper.hostTime <= events[4].absoluteBefore
    }

}
