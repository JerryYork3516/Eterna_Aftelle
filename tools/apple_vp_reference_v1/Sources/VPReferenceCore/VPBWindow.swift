public enum VPBWindow {
    public static func capture(
        admission: (confirmed: Bool, observer: any PlaybackConfigurationObserving), start: () throws -> Void,
        window: () throws -> Void, invalidate: () -> Void, stop: () -> Void
    ) throws {
        guard admission.confirmed else { throw EngineeringFailure(stage: .command, code: .promptUnconfirmed) }
        var failure: Error?
        var invalidated = false
        func reject() {
            if !invalidated {
                invalidated = true
                invalidate()
            }
        }
        do {
            try PlaybackLifecycle.run(
                observer: admission.observer,
                startAndValidate: {
                    do { try start() } catch {
                        reject()
                        throw error
                    }
                }, play: {},
                score: {
                    do { try window() } catch {
                        reject()
                        failure = error
                    }
                }, stop: stop)
        } catch {
            reject()
            throw error
        }
        if let failure { throw failure }
    }

    public static func run(
        clock: (armTick: UInt64, elapsed: () -> Double), observe: (Bool) throws -> Bool,
        event: (String) throws -> VPBClock, cue: (VPBCue) throws -> Void, wait: (Double) -> Void
    ) throws {
        var previous = 0.0
        func checkedTime() throws -> Double {
            try validateTime(clock.elapsed(), previous: &previous)
        }
        try prewarm(now: checkedTime, observe: observe, wait: wait)
        _ = try observe(true)
        let origin = try event("observationStart")
        let start = try checkedTime()
        guard origin.valid, origin.continuous >= clock.armTick, start <= 3, start + 12.5 <= 16 else {
            throw EngineeringFailure(stage: .recorder, code: .experimentPrewarmInvalid)
        }
        // Deadlines use the event's own continuous tick, not a later clock read.
        let originSeconds = origin.seconds(origin.continuous - clock.armTick)
        guard originSeconds <= start else {
            throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
        }
        var next = 0
        var lastFull = -1.0
        var stopAt = 12.5
        var postRollBoundary: VPBClock?
        for _ in 0..<322 {
            var relative = try checkedTime() - originSeconds
            if relative - lastFull >= 1 {
                _ = try observe(true)
                lastFull = relative
            } else {
                _ = try observe(false)
            }
            relative = try checkedTime() - originSeconds
            if next < VPBCue.allCases.count, relative >= VPBCue.allCases[next].offset {
                let phase = VPBCue.allCases[next]
                let boundary = try emit(
                    phase: phase, now: { try checkedTime() - originSeconds },
                    observe: { _ = try observe(true) }, event: event, cue: cue)
                if phase == .postRoll, let boundary {
                    postRollBoundary = boundary
                    stopAt = boundary.seconds(boundary.continuous - origin.continuous) + 0.5
                }
                next += 1
            }
            relative = try checkedTime() - originSeconds
            if relative >= stopAt {
                try finish(postRoll: postRollBoundary, completed: next, event: event)
                _ = try checkedTime()
                return
            }
            wait(min(0.05, max(0, stopAt - relative)))
        }
        throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
    }

    private static func prewarm(
        now: () throws -> Double, observe: (Bool) throws -> Bool, wait: (Double) -> Void
    ) throws {
        for _ in 0..<62 {
            let ready = try observe(false)
            guard try now() <= 3 else { throw EngineeringFailure(stage: .recorder, code: .experimentPrewarmInvalid) }
            if ready { return }
            wait(0.05)
        }
        throw EngineeringFailure(stage: .recorder, code: .experimentPrewarmInvalid)
    }

    private static func validateTime(_ now: Double, previous: inout Double) throws -> Double {
        guard now.isFinite, now >= previous, now < 16 else {
            throw EngineeringFailure(stage: .recorder, code: .experimentClockInvalid)
        }
        previous = now
        return now
    }

    private static func emit(
        phase: VPBCue, now: () throws -> Double, observe: () throws -> Void,
        event: (String) throws -> VPBClock, cue: (VPBCue) throws -> Void
    ) throws -> VPBClock? {
        guard try now() < phase.end else {
            throw EngineeringFailure(stage: .recorder, code: .probeStimulusWindowMissed)
        }
        try observe()
        guard try now() < phase.end else {
            throw EngineeringFailure(stage: .recorder, code: .probeStimulusWindowMissed)
        }
        let boundary = phase == .quietInitial ? nil : try event(phase.rawValue)
        guard try now() < phase.end else {
            throw EngineeringFailure(stage: .recorder, code: .probeStimulusWindowMissed)
        }
        try cue(phase)
        guard try now() < phase.end else {
            throw EngineeringFailure(stage: .recorder, code: .probeStimulusWindowMissed)
        }
        return boundary
    }

    private static func finish(postRoll: VPBClock?, completed: Int, event: (String) throws -> VPBClock) throws {
        guard completed == VPBCue.allCases.count, let postRoll else {
            throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
        }
        let end = try event("beforeStop")
        guard end.continuous >= postRoll.continuous, end.seconds(end.continuous - postRoll.continuous) >= 0.5 else {
            throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
        }
    }
}
