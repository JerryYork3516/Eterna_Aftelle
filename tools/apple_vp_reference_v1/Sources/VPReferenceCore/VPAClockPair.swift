public struct VPAClockPair: Encodable, Sendable {
    public enum Phase: String, Encodable, CaseIterable, Sendable {
        case beforeStart, quietStart, playRequest, plannedTail, postRollStart, beforeStop
    }

    public let phase: Phase
    public let absoluteBeforeTick: UInt64
    public let continuousTick: UInt64
    public let absoluteAfterTick: UInt64
    public let timebaseNumerator: UInt32
    public let timebaseDenominator: UInt32
    public let bracketTicks: UInt64?
    public let offsetLowerBoundTicks: Int64?
    public let offsetUpperBoundTicks: Int64?

    public init(
        phase: Phase, absoluteBeforeTick: UInt64, continuousTick: UInt64, absoluteAfterTick: UInt64,
        timebaseNumerator: UInt32, timebaseDenominator: UInt32
    ) {
        self.phase = phase
        self.absoluteBeforeTick = absoluteBeforeTick
        self.continuousTick = continuousTick
        self.absoluteAfterTick = absoluteAfterTick
        self.timebaseNumerator = timebaseNumerator
        self.timebaseDenominator = timebaseDenominator
        bracketTicks = absoluteAfterTick >= absoluteBeforeTick ? absoluteAfterTick - absoluteBeforeTick : nil
        guard let before = Int64(exactly: absoluteBeforeTick), let after = Int64(exactly: absoluteAfterTick),
            let continuous = Int64(exactly: continuousTick), bracketTicks != nil,
            timebaseNumerator > 0, timebaseDenominator > 0
        else {
            offsetLowerBoundTicks = nil
            offsetUpperBoundTicks = nil
            return
        }
        offsetLowerBoundTicks = continuous - after
        offsetUpperBoundTicks = continuous - before
    }

    public var isValid: Bool { offsetLowerBoundTicks != nil && offsetUpperBoundTicks != nil }

    public var bracketSeconds: Double? {
        guard isValid, let bracketTicks else { return nil }
        return Double(bracketTicks) * Double(timebaseNumerator) / Double(timebaseDenominator) / 1_000_000_000
    }
}
