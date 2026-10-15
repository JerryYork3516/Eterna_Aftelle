import VPRecorder

public struct VPCCoverage: Encodable {
    public struct Anchor: Encodable {
        public let recordIndex: UInt64
        public let hostTime: UInt64
        public let sampleTime: Int64
    }

    public struct Window: Encodable {
        public let name: String
        public let required: Bool
        public let plannedStartSeconds: Double
        public let plannedEndSeconds: Double
        public let startAbsoluteEarliest: UInt64
        public let endAbsoluteLatest: UInt64
        public let startBoundary: VPCPlannedBoundary
        public let endBoundary: VPCPlannedBoundary
        public let actualControl: VPCControlSpan
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
        + "fixed planned boundaries use monotonic local brackets; "
        + "actual cue spans are separate; acoustic timing unverified"
    private var previous: [UInt32: VPFrameIdentity] = [:]
    private var failed = false
    private var timebaseNumerator: UInt32 = 0
    private var timebaseDenominator: UInt32 = 0

    private enum CodingKeys: String, CodingKey {
        case status, reason, recordCount, windows, meaning
    }

    public var formalWindowsCovered: Bool { status == "DIGITAL_SAMPLE_SPAN_COVERED" }

    public init(events: [VPBClock], receipts: [VPBDisplayReceipt]) {
        let ids = [
            "beforeStart", "observationStart", "RESIDENT_START", "playRequest", "NEAR_CONTINUOUS",
            "RESIDENT_AFTER", "TAIL", "POST_ROLL", "beforeStop"
        ]
        guard events.map(\.id) == ids, events.allSatisfy(\.valid), receipts.count == VPCCue.allCases.count else {
            reject("C_BOUNDARIES_OR_CUES_UNVERIFIED")
            return
        }
        for index in 1..<events.count {
            let first = events[index - 1]
            let last = events[index]
            guard last.absoluteBefore > first.absoluteAfter, last.continuous > first.continuous,
                first.numerator == last.numerator, first.denominator == last.denominator
            else {
                reject("C_CLOCK_ORDER_OR_UNITS")
                return
            }
        }
        do {
            for (phase, receipt) in zip(VPCCue.allCases, receipts) {
                try VPCWindow.validate(receipt: receipt, phase: phase, origin: events[1])
            }
        } catch {
            reject("C_CUE_TIMING_INVALID")
            return
        }
        for (index, planned) in zip([2, 3, 4, 5, 6, 7, 8], [2.0, 2, 4, 9, 10, 13, 13.5]) {
            guard events[index].continuous >= events[1].continuous else {
                reject("C_EVENT_BEFORE_ORIGIN")
                return
            }
            let relative = events[1].seconds(events[index].continuous - events[1].continuous)
            guard relative >= planned, relative <= planned + 0.25 else {
                reject("C_EVENT_DEADLINE_MISMATCH")
                return
            }
        }
        timebaseNumerator = events[0].numerator
        timebaseDenominator = events[0].denominator
        makeWindows(events, receipts: receipts)
    }

    private struct Plan {
        let name: String
        let first: Int
        let last: Int
        let start: Double
        let end: Double
    }

    private mutating func makeWindows(_ events: [VPBClock], receipts: [VPBDisplayReceipt]) {
        let bounds = [
            Plan(name: "formal13", first: 1, last: 7, start: 0, end: 13),
            Plan(name: "quiet", first: 1, last: 2, start: 0, end: 2),
            Plan(name: "residentPlay", first: 2, last: 6, start: 2, end: 10),
            Plan(name: "residentBefore", first: 2, last: 4, start: 2, end: 4),
            Plan(name: "doubleTalkCandidate", first: 4, last: 5, start: 4, end: 9),
            Plan(name: "residentAfter", first: 5, last: 6, start: 9, end: 10),
            Plan(name: "tail", first: 6, last: 7, start: 10, end: 13),
            Plan(name: "postRoll", first: 7, last: 8, start: 13, end: 13.5)
        ]
        guard let clocks = VPCPlannedBoundary.ordered(events: events, receipts: receipts) else {
            reject("C_LOCAL_CLOCK_ORDER_INVALID")
            return
        }
        let cueIndices = [1: 0, 2: 1, 4: 2, 5: 3, 6: 4, 7: 5]
        for plan in bounds {
            guard let start = VPCPlannedBoundary.make(origin: events[1], seconds: plan.start, clocks: clocks),
                let end = VPCPlannedBoundary.make(origin: events[1], seconds: plan.end, clocks: clocks),
                end.absoluteLatest > start.absoluteEarliest,
                let firstCue = cueIndices[plan.first]
            else {
                reject("C_PLANNED_BOUNDARY_UNBRACKETED")
                return
            }
            let actual = VPCControlSpan(
                start: receipts[firstCue].displayed,
                end: cueIndices[plan.last].map { receipts[$0].requested } ?? events[plan.last],
                plannedSeconds: plan.end - plan.start, origin: events[1], startOffset: plan.start)
            let minimum = events[plan.last].absoluteBefore - events[plan.first].absoluteAfter
            windows.append(
                Window(
                    name: plan.name, required: plan.name != "postRoll",
                    plannedStartSeconds: plan.start, plannedEndSeconds: plan.end,
                    startAbsoluteEarliest: start.absoluteEarliest, endAbsoluteLatest: end.absoluteLatest,
                    startBoundary: start, endBoundary: end, actualControl: actual,
                    minimumAbsoluteSpanTicks: minimum, minimumDurationVerified: actual.valid))
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
        guard recordCount == expectedRecords, windows.count == 8 else {
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
                && plannedSamples(windows[index].inputSampleSpan, window: window, stream: UInt32(VP_STREAM_INPUT))
                && plannedSamples(windows[index].renderSampleSpan, window: window, stream: UInt32(VP_STREAM_RENDER))
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

    private func plannedSamples(_ frames: UInt64?, window: Window, stream: UInt32) -> Bool {
        guard let frames, let rate = previous[stream]?.format.mSampleRate else { return false }
        return Double(frames) >= (window.plannedEndSeconds - window.plannedStartSeconds) * rate
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
