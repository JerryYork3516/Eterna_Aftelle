import VPRecorder

public struct VPBInputCoverage: Encodable {
    public struct Anchor: Encodable {
        public let record: UInt64
        public let host: UInt64
        public let sample: Int64
    }

    public struct Window: Encodable {
        public let cue: VPBCue
        public let start: UInt64
        public let end: UInt64
        public var first: Anchor?
        public var last: Anchor?
        public var covered = false
    }

    public private(set) var status = "UNVERIFIED"
    public private(set) var windows: [Window] = []
    private var previous: VPFrameIdentity?
    private var clock: VPBClock?
    private var rejected = false

    private enum CodingKeys: String, CodingKey { case status, windows }

    public init(events: [VPBClock]) {
        let ids = ["beforeStart", "observationStart"] + VPBCue.allCases.dropFirst().map(\.rawValue) + ["beforeStop"]
        guard events.map(\.id) == ids, events.allSatisfy(\.valid) else {
            rejected = true
            return
        }
        for index in 1..<events.count {
            guard events[index].absoluteBefore > events[index - 1].absoluteAfter,
                events[index].continuous > events[index - 1].continuous,
                events[index].numerator == events[0].numerator,
                events[index].denominator == events[0].denominator
            else {
                rejected = true
                return
            }
        }
        clock = events[0]
        for (index, cue) in VPBCue.allCases.enumerated() {
            windows.append(
                Window(cue: cue, start: events[index + 1].absoluteBefore, end: events[index + 2].absoluteAfter))
        }
        // The required score span is 12s; post-roll is independently reported.
        if events[0].seconds(events[8].absoluteBefore - events[1].absoluteAfter) < 12 { rejected = true }
    }

    public mutating func include(_ value: VPFrameIdentity, index: UInt64) {
        guard !rejected, value.stream_kind == UInt32(VP_STREAM_INPUT) else { return }
        guard value.sample_time_valid, value.host_time_valid, value.frame_count > 0,
            value.format.mSampleRate.isFinite, value.format.mSampleRate > 0,
            value.format.mFormatID == kAudioFormatLinearPCM, value.format.mBitsPerChannel == 32,
            value.format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            value.format.mChannelsPerFrame > 0, value.format.mChannelsPerFrame <= 32
        else {
            rejected = true
            return
        }
        if let previous {
            let next = previous.sample_time.addingReportingOverflow(Int64(previous.frame_count))
            guard !next.overflow, value.sample_time == next.partialValue, value.host_time > previous.host_time,
                value.format.mSampleRate == previous.format.mSampleRate,
                value.format.mFormatFlags == previous.format.mFormatFlags,
                value.format.mChannelsPerFrame == previous.format.mChannelsPerFrame,
                value.format.mBytesPerFrame == previous.format.mBytesPerFrame
            else {
                rejected = true
                return
            }
        }
        previous = value
        let anchor = Anchor(record: index, host: value.host_time, sample: value.sample_time)
        for index in windows.indices {
            if anchor.host <= windows[index].start { windows[index].first = anchor }
            if anchor.host >= windows[index].end, windows[index].last == nil { windows[index].last = anchor }
        }
    }

    public mutating func finish() {
        guard !rejected, let clock, let previous, let rate = UInt64(exactly: previous.format.mSampleRate) else {
            return
        }
        for index in windows.indices {
            guard let first = windows[index].first, let last = windows[index].last else { continue }
            let difference = last.sample.subtractingReportingOverflow(first.sample)
            guard !difference.overflow, difference.partialValue > 0,
                let lhs = product([UInt64(difference.partialValue), 1_000_000_000, UInt64(clock.denominator)]),
                let rhs = product([windows[index].end - windows[index].start, rate, UInt64(clock.numerator)])
            else { continue }
            windows[index].covered = lhs >= rhs
        }
        if windows.count == 8, windows.dropLast().allSatisfy(\.covered) { status = "DIGITAL_INPUT_SPAN_COVERED" }
    }

    private func product(_ values: [UInt64]) -> UInt64? {
        var total: UInt64 = 1
        for value in values {
            let next = total.multipliedReportingOverflow(by: value)
            guard !next.overflow else { return nil }
            total = next.partialValue
        }
        return total
    }
}
