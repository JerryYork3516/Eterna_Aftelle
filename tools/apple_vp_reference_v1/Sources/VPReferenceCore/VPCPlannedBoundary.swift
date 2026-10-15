public struct VPCPlannedBoundary: Encodable {
    public let continuousEarliest: UInt64
    public let continuousLatest: UInt64
    public let absoluteEarliest: UInt64
    public let absoluteLatest: UInt64
    public let lowerPairContinuous: UInt64
    public let upperPairContinuous: UInt64
    public let meaning = "Monotonic bracket only; no constant cross-clock offset or acoustic timestamp"

    static func ordered(events: [VPBClock], receipts: [VPBDisplayReceipt]) -> [VPBClock]? {
        let clocks = (events + receipts.flatMap { [$0.requested, $0.displayed] })
            .sorted { $0.continuous < $1.continuous }
        guard let first = clocks.first else { return nil }
        for (index, clock) in clocks.enumerated() {
            guard clock.valid, clock.numerator == first.numerator, clock.denominator == first.denominator else {
                return nil
            }
            if index > 0 {
                let previous = clocks[index - 1]
                guard previous.absoluteBefore <= clock.absoluteAfter,
                    previous.continuous == clock.continuous || previous.absoluteAfter <= clock.absoluteBefore
                else { return nil }
            }
        }
        return clocks
    }

    static func make(origin: VPBClock, seconds: Double, clocks: [VPBClock]) -> Self? {
        guard let halves = UInt64(exactly: seconds * 2) else { return nil }
        let nanos = halves.multipliedReportingOverflow(by: 500_000_000)
        let scaled = nanos.partialValue.multipliedReportingOverflow(by: UInt64(origin.denominator))
        guard !nanos.overflow, !scaled.overflow, origin.numerator > 0 else { return nil }
        let units = UInt64(origin.numerator)
        let lowerTick = origin.continuous.addingReportingOverflow(scaled.partialValue / units)
        let upperTick = lowerTick.partialValue.addingReportingOverflow(scaled.partialValue % units == 0 ? 0 : 1)
        guard !lowerTick.overflow, !upperTick.overflow,
            let lower = clocks.last(where: { $0.continuous <= lowerTick.partialValue }),
            let upper = clocks.first(where: { $0.continuous >= upperTick.partialValue }),
            upper.absoluteAfter >= lower.absoluteBefore
        else { return nil }
        return Self(
            continuousEarliest: lowerTick.partialValue, continuousLatest: upperTick.partialValue,
            absoluteEarliest: lower.absoluteBefore, absoluteLatest: upper.absoluteAfter,
            lowerPairContinuous: lower.continuous, upperPairContinuous: upper.continuous)
    }
}

public struct VPCControlSpan: Encodable {
    public let displayedStartContinuous: UInt64
    public let nextRequestContinuous: UInt64
    public let startAbsoluteAfter: UInt64
    public let endAbsoluteBefore: UInt64
    public let availableSeconds: Double
    public let startLatenessSeconds: Double
    public let minimumAllowedSeconds: Double
    public let valid: Bool
    public let meaning = "Control/display span only; independent 250ms lateness does not shorten planned PCM scoring"

    init(start: VPBClock, end: VPBClock, plannedSeconds: Double, origin: VPBClock, startOffset: Double) {
        displayedStartContinuous = start.continuous
        nextRequestContinuous = end.continuous
        startAbsoluteAfter = start.absoluteAfter
        endAbsoluteBefore = end.absoluteBefore
        availableSeconds = end.continuous >= start.continuous ? start.seconds(end.continuous - start.continuous) : -1
        startLatenessSeconds =
            start.continuous >= origin.continuous
            ? origin.seconds(start.continuous - origin.continuous) - startOffset : -1
        minimumAllowedSeconds = plannedSeconds - 0.25
        valid = availableSeconds >= minimumAllowedSeconds && startLatenessSeconds >= 0 && startLatenessSeconds <= 0.25
    }
}
