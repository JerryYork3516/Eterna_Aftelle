public enum VPCWindow {
    public static func run(
        clock: (armTick: UInt64, elapsed: () -> Double), observe: (Bool) throws -> (Bool, Bool),
        event: (String) throws -> VPBClock,
        perform: (VPCAction) throws -> VPBDisplayReceipt?, wait: (Double) -> Void
    ) throws {
        var previous = 0.0
        func now() throws -> Double {
            let value = clock.elapsed()
            guard value.isFinite, value >= previous, value < 16 else {
                throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
            }
            previous = value
            return value
        }
        let origin = try open(arm: clock.armTick, now: now, observe: observe, event: event, wait: wait)
        let start = origin.seconds(origin.continuous - clock.armTick)
        var next = 0
        var lastFull = -1.0
        var playback = VPCPlaybackAdmission()
        for _ in 0..<330 {
            let relative = try now() - start
            _ = try observe(relative - lastFull >= 1)
            if relative - lastFull >= 1 { lastFull = relative }
            let current = try now() - start
            if next < VPCCue.allCases.count, current >= VPCCue.allCases[next].offset {
                let phase = VPCCue.allCases[next]
                try emit(phase: phase, origin: origin, now: { try now() - start }, event: event, perform: perform)
                _ = try observe(true)
                if phase == .resident {
                    try requireReserve(now: now(), origin: start)
                    try playback.request(at: now() - start)
                    _ = try event("playRequest")
                    try playbackTime(now() - start)
                    _ = try perform(.play)
                    _ = try observe(false)
                }
                next += 1
            }
            let after = try now() - start
            if after >= 13.5 {
                guard next == VPCCue.allCases.count, playback.requests == 1, after <= 13.75 else {
                    throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
                }
                _ = try event("beforeStop")
                _ = try now()
                return
            }
            let nextDeadline = next < VPCCue.allCases.count ? VPCCue.allCases[next].offset : 13.5
            wait(min(0.05, max(0, nextDeadline - after)))
        }
        throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
    }

    private static func open(
        arm: UInt64, now: () throws -> Double, observe: (Bool) throws -> (Bool, Bool),
        event: (String) throws -> VPBClock, wait: (Double) -> Void
    ) throws -> VPBClock {
        try prewarm(now: now, observe: observe, wait: wait)
        _ = try observe(true)
        let origin = try event("observationStart")
        let opened = try now()
        guard origin.valid, origin.continuous >= arm, opened <= VPCRequest.openingDeadline else {
            throw EngineeringFailure(stage: .recorder, code: .experimentPrewarmInvalid)
        }
        let start = origin.seconds(origin.continuous - arm)
        guard start <= opened else { throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid) }
        try requireReserve(now: opened, origin: start)
        return origin
    }

    public static func start(
        schedule: () throws -> Void, prepare: () throws -> Void,
        start: () throws -> Void, validate: () throws -> Void
    ) throws {
        try schedule()
        try prepare()
        try start()
        try validate()
    }

    public static func requireReserve(now: Double, origin: Double) throws {
        guard now.isFinite, origin.isFinite, now >= origin, origin <= 2,
            now + max(0, 13.5 - (now - origin)) + VPCRequest.controlReserve <= 16
        else { throw EngineeringFailure(stage: .recorder, code: .experimentPrewarmInvalid) }
    }

    private static func prewarm(
        now: () throws -> Double, observe: (Bool) throws -> (Bool, Bool), wait: (Double) -> Void
    ) throws {
        for _ in 0..<42 {
            let ready = try observe(false)
            guard try now() <= VPCRequest.openingDeadline else {
                throw EngineeringFailure(stage: .recorder, code: .experimentPrewarmInvalid)
            }
            if ready.0 && ready.1 { return }
            wait(0.05)
        }
        throw EngineeringFailure(stage: .recorder, code: .experimentPrewarmInvalid)
    }

    private static func emit(
        phase: VPCCue, origin: VPBClock, now: () throws -> Double,
        event: (String) throws -> VPBClock, perform: (VPCAction) throws -> VPBDisplayReceipt?
    ) throws {
        try playbackOrCueTime(now(), phase: phase)
        if phase != .quiet { _ = try event(phase.rawValue) }
        try playbackOrCueTime(now(), phase: phase)
        guard let receipt = try perform(.cue(phase)) else {
            throw EngineeringFailure(stage: .command, code: .promptUnconfirmed)
        }
        try validate(receipt: receipt, phase: phase, origin: origin)
        try playbackOrCueTime(now(), phase: phase)
    }

    public static func validate(receipt: VPBDisplayReceipt, phase: VPCCue, origin: VPBClock) throws {
        try receipt.validate(id: phase.rawValue)
        for point in [receipt.requested, receipt.displayed] {
            guard point.id == phase.rawValue, point.numerator == origin.numerator,
                point.denominator == origin.denominator, point.absoluteBefore >= origin.absoluteAfter,
                point.continuous >= origin.continuous
            else { throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid) }
            try playbackOrCueTime(origin.seconds(point.continuous - origin.continuous), phase: phase)
        }
    }

    private static func playbackOrCueTime(_ value: Double, phase: VPCCue) throws {
        guard value.isFinite, value >= phase.offset, value <= phase.offset + 0.25, value < phase.end else {
            throw EngineeringFailure(stage: .command, code: .probeStimulusWindowMissed)
        }
    }

    private static func playbackTime(_ value: Double) throws {
        try playbackOrCueTime(value, phase: .resident)
    }
}
