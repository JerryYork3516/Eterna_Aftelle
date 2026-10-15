import VPRecorder
import VPReferenceCore

struct VPCRenderDistribution: Encodable {
    struct Counts: Encodable {
        var samples: UInt64 = 0
        var nonZero: UInt64 = 0
        var firstSignal: Int64?
        var lastSignal: Int64?

        mutating func merge(_ other: Self) {
            samples += other.samples
            nonZero += other.nonZero
            if firstSignal == nil { firstSignal = other.firstSignal }
            if let last = other.lastSignal { lastSignal = last }
        }
    }

    struct Bin: Encodable {
        let nativeSampleSecond: Int64
        var channels: [Counts]
    }

    struct Phase: Encodable {
        let name: String
        let plannedStart: Double
        let plannedEnd: Double
        let displayedStart: VPBClock
        let nextRequest: VPBClock
        var bins: [Bin] = []
        var channels: [Counts] = []
    }

    private(set) var phases: [Phase] = []
    private(set) var status = "EVIDENCE_UNVERIFIED"
    let meaning =
        "Whole buffers bracketed by successive raw host anchors inside actual display/request phases; "
        + "one-second bins use native sampleTime, not exact planned or acoustic time"
    private var pendingHost: UInt64?
    private var pending: [Bin] = []
    private var rate: Int64 = 0

    private enum CodingKeys: String, CodingKey { case phases, status, meaning }

    init(receipts: [VPBDisplayReceipt]) {
        guard receipts.count == 6 else { return }
        for (index, name) in ["residentBefore", "doubleTalkCandidate", "residentAfter"].enumerated() {
            let starts = [2.0, 4, 9]
            let ends = [4.0, 9, 10]
            phases.append(
                Phase(
                    name: name, plannedStart: starts[index], plannedEnd: ends[index],
                    displayedStart: receipts[index + 1].displayed, nextRequest: receipts[index + 2].requested))
        }
    }

    mutating func prepare(_ identity: VPFrameIdentity) throws {
        guard let sampleRate = Int64(exactly: identity.format.mSampleRate), sampleRate >= 1_000 else {
            throw failure()
        }
        for index in phases.indices {
            let end = phases[index].nextRequest.absoluteBefore
            let start = phases[index].displayedStart.absoluteAfter
            if let host = pendingHost, host >= start, identity.host_time > host, identity.host_time <= end {
                try mergePending(into: index)
            }
        }
        pendingHost = identity.host_time
        pending = []
        rate = sampleRate
    }

    mutating func include(_ value: Float, anchor: VPCPCMRead.SignalAnchor, channelCount: Int) throws {
        let quotient = anchor.sampleTime / rate
        let second = anchor.sampleTime < 0 && anchor.sampleTime % rate != 0 ? quotient - 1 : quotient
        if pending.last?.nativeSampleSecond != second {
            guard pending.count < 34 else { throw failure() }
            pending.append(Bin(nativeSampleSecond: second, channels: Array(repeating: Counts(), count: channelCount)))
        }
        let index = pending.count - 1
        pending[index].channels[anchor.channel].samples += 1
        if value.isFinite, value != 0 {
            pending[index].channels[anchor.channel].nonZero += 1
            if pending[index].channels[anchor.channel].firstSignal == nil {
                pending[index].channels[anchor.channel].firstSignal = anchor.sampleTime
            }
            pending[index].channels[anchor.channel].lastSignal = anchor.sampleTime
        }
    }

    private mutating func mergePending(into phase: Int) throws {
        for bin in pending {
            if phases[phase].channels.isEmpty {
                phases[phase].channels = Array(repeating: Counts(), count: bin.channels.count)
            }
            if phases[phase].bins.last?.nativeSampleSecond != bin.nativeSampleSecond {
                guard phases[phase].bins.count < 16 else { throw failure() }
                phases[phase].bins.append(
                    Bin(
                        nativeSampleSecond: bin.nativeSampleSecond,
                        channels: Array(repeating: Counts(), count: bin.channels.count)))
            }
            let last = phases[phase].bins.count - 1
            for channel in bin.channels.indices {
                phases[phase].channels[channel].merge(bin.channels[channel])
                phases[phase].bins[last].channels[channel].merge(bin.channels[channel])
            }
        }
    }

    mutating func finish(reference: VPCRenderReference) {
        guard phases.count == 3, rate > 0 else { return }
        let near = phases[1]
        for (index, channel) in near.channels.enumerated() {
            guard reference.channels.indices.contains(index), reference.channels[index].complete,
                channel.nonZero > UInt64(rate), let first = channel.firstSignal, let last = channel.lastSignal
            else { continue }
            let span = last.subtractingReportingOverflow(first)
            let activeBins = near.bins.filter { $0.channels[index].nonZero > 0 }.count
            if !span.overflow, span.partialValue > rate, activeBins >= 2 {
                status = "MATCHED_SOURCE_AND_DOUBLE_TALK_DIGITAL_SIGNAL"
            }
        }
    }

    private func failure() -> EngineeringFailure {
        EngineeringFailure(stage: .recorder, code: .experimentCoverageUnverified)
    }
}
