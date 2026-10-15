import VPRecorder

public struct VPAWindowCoverage: Encodable {
    public struct Anchor: Encodable {
        public let recordIndex: UInt64
        public let hostTime: UInt64
        public let sampleTime: Int64
    }

    public struct Window: Encodable {
        public let name: String
        public let required: Bool
        public let startAbsoluteEarliest: UInt64
        public let endAbsoluteLatest: UInt64
        public let minimumAbsoluteSpanTicks: UInt64
        public let minimumDurationVerified: Bool
        public var inputSampleSpan: UInt64?
        public var renderSampleSpan: UInt64?
        public var inputStart: Anchor?
        public var inputEnd: Anchor?
        public var renderStart: Anchor?
        public var renderEnd: Anchor?
        public var covered = false
    }

    public private(set) var status = "UNVERIFIED"
    public private(set) var reason = "RECORDS_NOT_EVALUATED"
    public private(set) var recordCount: UInt64 = 0
    public private(set) var windows: [Window] = []
    public let meaning =
        "Raw host anchors bracket event-local windows in continuous digital sample sequences; "
        + "intra-buffer and acoustic timing remain unverified"
    private var previous: [UInt32: VPFrameIdentity] = [:]
    private var failed = false
    private var timebaseNumerator: UInt32 = 0
    private var timebaseDenominator: UInt32 = 0

    private enum CodingKeys: String, CodingKey {
        case status, reason, recordCount, windows, meaning
    }

    public var formalWindowsCovered: Bool { status == "DIGITAL_SAMPLE_SPAN_COVERED" }

    public init(clockPairs: [VPAClockPair]) {
        guard clockPairs.map(\.phase) == VPAClockPair.Phase.allCases,
            clockPairs.allSatisfy({
                $0.isValid && ($0.bracketSeconds ?? .infinity) <= VPARequest.maximumObservationSeconds
            })
        else {
            reject("LOCAL_BOUNDARIES_UNVERIFIED")
            return
        }
        for index in 1..<clockPairs.count {
            let first = clockPairs[index - 1]
            let last = clockPairs[index]
            guard last.absoluteBeforeTick > first.absoluteAfterTick, last.continuousTick > first.continuousTick,
                last.timebaseNumerator == first.timebaseNumerator, last.timebaseDenominator == first.timebaseDenominator
            else {
                reject("LOCAL_BOUNDARIES_UNVERIFIED")
                return
            }
        }
        timebaseNumerator = clockPairs[0].timebaseNumerator
        timebaseDenominator = clockPairs[0].timebaseDenominator
        let names = ["quiet", "play", "tail", "postRoll"]
        let seconds = [
            VPARequest.quietSeconds, VPARequest.materialSeconds, VPARequest.tailSeconds, VPARequest.postRollSeconds
        ]
        for index in 0..<names.count {
            let first = clockPairs[index + 1]
            let last = clockPairs[index + 2]
            let minimum = last.absoluteBeforeTick - first.absoluteAfterTick
            windows.append(
                Window(
                    name: names[index], required: index < 3,
                    startAbsoluteEarliest: first.absoluteBeforeTick, endAbsoluteLatest: last.absoluteAfterTick,
                    minimumAbsoluteSpanTicks: minimum,
                    minimumDurationVerified: durationVerified(ticks: minimum, halfSeconds: UInt64(seconds[index] * 2))))
        }
    }

    public mutating func include(_ identity: VPFrameIdentity) {
        guard !failed else { return }
        guard identity.stream_kind == UInt32(VP_STREAM_INPUT) || identity.stream_kind == UInt32(VP_STREAM_RENDER),
            identity.host_time_valid, identity.sample_time_valid, identity.frame_count > 0,
            validFormat(identity.format)
        else {
            reject("FRAME_IDENTITY_UNVERIFIED")
            return
        }
        if let old = previous[identity.stream_kind] {
            let next = old.sample_time.addingReportingOverflow(Int64(old.frame_count))
            guard !next.overflow, identity.sample_time == next.partialValue, identity.host_time > old.host_time,
                sameFormat(old.format, identity.format)
            else {
                reject("STREAM_SEQUENCE_UNVERIFIED")
                return
            }
        }
        previous[identity.stream_kind] = identity
        let anchor = Anchor(recordIndex: recordCount, hostTime: identity.host_time, sampleTime: identity.sample_time)
        for index in windows.indices {
            if identity.stream_kind == UInt32(VP_STREAM_INPUT) {
                if anchor.hostTime <= windows[index].startAbsoluteEarliest { windows[index].inputStart = anchor }
                if anchor.hostTime >= windows[index].endAbsoluteLatest, windows[index].inputEnd == nil {
                    windows[index].inputEnd = anchor
                }
            } else {
                if anchor.hostTime <= windows[index].startAbsoluteEarliest { windows[index].renderStart = anchor }
                if anchor.hostTime >= windows[index].endAbsoluteLatest, windows[index].renderEnd == nil {
                    windows[index].renderEnd = anchor
                }
            }
            windows[index].covered =
                windows[index].inputStart != nil && windows[index].inputEnd != nil
                && windows[index].renderStart != nil && windows[index].renderEnd != nil
        }
        recordCount += 1
    }

    public mutating func finish(expectedRecords: UInt64) {
        guard !failed else { return }
        guard recordCount == expectedRecords, windows.count == 4 else {
            reject("RECORD_COUNT_OR_BOUNDARIES_UNVERIFIED")
            return
        }
        for index in windows.indices {
            let window = windows[index]
            windows[index].inputSampleSpan = sampleSpan(window.inputStart, window.inputEnd)
            windows[index].renderSampleSpan = sampleSpan(window.renderStart, window.renderEnd)
            let ticks = window.endAbsoluteLatest - window.startAbsoluteEarliest
            windows[index].covered =
                window.minimumDurationVerified
                && samplesCover(windows[index].inputSampleSpan, ticks: ticks, stream: UInt32(VP_STREAM_INPUT))
                && samplesCover(windows[index].renderSampleSpan, ticks: ticks, stream: UInt32(VP_STREAM_RENDER))
        }
        guard windows.filter(\.required).allSatisfy(\.covered) else {
            reject("HOST_ANCHORS_OR_SAMPLE_SPAN_DO_NOT_COVER_FORMAL_WINDOWS")
            return
        }
        status = "DIGITAL_SAMPLE_SPAN_COVERED"
        reason = "EVENT_LOCAL_RAW_HOST_ANCHORS; INTRA_BUFFER_AND_PHYSICAL_TIMING_UNVERIFIED"
    }

    public mutating func reject(_ reason: String) {
        guard !failed else { return }
        failed = true
        self.reason = reason
        status = "UNVERIFIED"
    }

    private func durationVerified(ticks: UInt64, halfSeconds: UInt64) -> Bool {
        guard let left = product([ticks, UInt64(timebaseNumerator), 2]),
            let right = product([halfSeconds, 1_000_000_000, UInt64(timebaseDenominator)])
        else { return false }
        return left >= right
    }

    private func sampleSpan(_ first: Anchor?, _ last: Anchor?) -> UInt64? {
        guard let first, let last else { return nil }
        let span = last.sampleTime.subtractingReportingOverflow(first.sampleTime)
        return !span.overflow && span.partialValue > 0 ? UInt64(span.partialValue) : nil
    }

    private func samplesCover(_ frames: UInt64?, ticks: UInt64, stream: UInt32) -> Bool {
        guard let frames, let format = previous[stream]?.format, let rate = UInt64(exactly: format.mSampleRate),
            let left = product([frames, 1_000_000_000, UInt64(timebaseDenominator)]),
            let right = product([ticks, rate, UInt64(timebaseNumerator)])
        else { return false }
        return left >= right
    }

    private func product(_ values: [UInt64]) -> UInt64? {
        var result: UInt64 = 1
        for value in values {
            let next = result.multipliedReportingOverflow(by: value)
            guard !next.overflow else { return nil }
            result = next.partialValue
        }
        return result
    }

    private func validFormat(_ value: AudioStreamBasicDescription) -> Bool {
        guard value.mSampleRate.isFinite, value.mSampleRate > 0, value.mFormatID == kAudioFormatLinearPCM,
            value.mFormatFlags & kAudioFormatFlagIsFloat != 0, value.mBitsPerChannel == 32,
            value.mChannelsPerFrame > 0, value.mChannelsPerFrame <= 32
        else { return false }
        let bytes: UInt32 = value.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 4 : value.mChannelsPerFrame * 4
        return value.mBytesPerFrame == bytes && value.mBytesPerPacket == bytes && value.mFramesPerPacket == 1
    }

    private func sameFormat(_ first: AudioStreamBasicDescription, _ last: AudioStreamBasicDescription) -> Bool {
        first.mSampleRate == last.mSampleRate && first.mFormatID == last.mFormatID
            && first.mFormatFlags == last.mFormatFlags && first.mBytesPerPacket == last.mBytesPerPacket
            && first.mFramesPerPacket == last.mFramesPerPacket && first.mBytesPerFrame == last.mBytesPerFrame
            && first.mChannelsPerFrame == last.mChannelsPerFrame && first.mBitsPerChannel == last.mBitsPerChannel
    }
}
