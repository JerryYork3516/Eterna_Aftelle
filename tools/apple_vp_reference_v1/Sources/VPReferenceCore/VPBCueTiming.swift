public struct VPBCueTiming: Encodable, Sendable {
    // Reuse the reviewed 250ms control-observation budget, now applied end-to-end from planned cue start.
    public static let maximumLateSeconds = 0.25
    public let cueID: VPBCue
    public let plannedStartSeconds: Double
    public let plannedEndSeconds: Double
    public let observedControlSeconds: Double?
    public let controlLateSeconds: Double?
    public let requestLateSeconds: Double?
    public let displayLateSeconds: Double?
    public let remainingPlannedSeconds: Double?
    public let accepted: Bool

    public init(phase: VPBCue, observed: Double? = nil, origin: VPBClock, receipt: VPBDisplayReceipt? = nil) {
        cueID = phase
        plannedStartSeconds = phase.offset
        plannedEndSeconds = phase.end
        let control = observed.flatMap { $0.isFinite ? $0 : nil }
        let request = receipt.flatMap { Self.relative($0.requested, origin: origin) }
        observedControlSeconds = control
        controlLateSeconds = control.map { $0 - phase.offset }
        requestLateSeconds = request.map { $0 - phase.offset }
        let display = receipt.flatMap { Self.relative($0.displayed, origin: origin) }
        displayLateSeconds = display.map { $0 - phase.offset }
        remainingPlannedSeconds = (display ?? control).map { phase.end - $0 }
        accepted =
            (control ?? request).map { Self.startIsTimely(phase: phase, observed: $0) } == true
            && Self.receiptIsTimely(receipt, phase: phase, origin: origin)
    }

    public static func requireStart(phase: VPBCue, observed: Double, origin: VPBClock) throws {
        guard startIsTimely(phase: phase, observed: observed) else {
            throw VPBCueTimingFailure(timing: Self(phase: phase, observed: observed, origin: origin))
        }
    }

    private static func startIsTimely(phase: VPBCue, observed: Double) -> Bool {
        observed.isFinite && observed >= phase.offset && observed <= phase.offset + maximumLateSeconds
            && observed < phase.end
    }

    private static func receiptIsTimely(_ receipt: VPBDisplayReceipt?, phase: VPBCue, origin: VPBClock) -> Bool {
        guard let receipt else { return false }
        do { try receipt.validate(id: phase.rawValue) } catch { return false }
        guard receipt.requested.id == phase.rawValue, receipt.displayed.id == phase.rawValue else { return false }
        return withinBudget(receipt.requested, phase: phase, origin: origin)
            && withinBudget(receipt.displayed, phase: phase, origin: origin)
    }

    private static func relative(_ value: VPBClock, origin: VPBClock) -> Double? {
        guard value.numerator == origin.numerator, value.denominator == origin.denominator,
            value.continuous >= origin.continuous
        else { return nil }
        return origin.seconds(value.continuous - origin.continuous)
    }

    private static func withinBudget(_ value: VPBClock, phase: VPBCue, origin: VPBClock) -> Bool {
        guard origin.valid, value.valid, value.absoluteBefore >= origin.absoluteAfter,
            relative(value, origin: origin) != nil,
            let elapsed = product([value.continuous - origin.continuous, UInt64(origin.numerator), 4]),
            let planned = product([UInt64(phase.offset * 4), 1_000_000_000, UInt64(origin.denominator)]),
            let latest = product([UInt64(phase.offset * 4) + 1, 1_000_000_000, UInt64(origin.denominator)])
        else { return false }
        return elapsed >= planned && elapsed <= latest
    }

    private static func product(_ values: [UInt64]) -> UInt64? {
        var result: UInt64 = 1
        for value in values {
            let next = result.multipliedReportingOverflow(by: value)
            guard !next.overflow else { return nil }
            result = next.partialValue
        }
        return result
    }
}

public struct VPBCueTimingFailure: Error, Sendable {
    public let timing: VPBCueTiming
}
