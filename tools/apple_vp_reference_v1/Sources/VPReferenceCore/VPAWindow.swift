public enum VPAWindow {
    public static func capture(
        observer: any PlaybackConfigurationObserving, beforePlayback: () throws -> Void,
        play: () throws -> Void, score: () throws -> Void,
        cleanup: (invalidate: () -> Void, stop: () -> Void)
    ) throws {
        var failure: Error?
        try PlaybackLifecycle.run(
            observer: observer,
            startAndValidate: {
                do { try beforePlayback() } catch {
                    cleanup.invalidate()
                    throw error
                }
            },
            play: {
                do { try play() } catch {
                    cleanup.invalidate()
                    failure = error
                }
            },
            score: {
                guard failure == nil else { return }
                do { try score() } catch {
                    cleanup.invalidate()
                    failure = error
                }
            }, stop: cleanup.stop)
        if let failure { throw failure }
    }
    /// Control-path windows only. No clock here represents physical acoustic arrival.
    public static func wait(
        seconds: Double, elapsedSeconds: () -> Double, check: () throws -> Void,
        observe: () throws -> Void, sleep: (Double) -> Void
    ) throws {
        let start = elapsedSeconds()
        guard start.isFinite, start >= 0, seconds.isFinite, seconds > 0,
            start + seconds <= Double(VPARequest.maximumSeconds)
        else { throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid) }
        var previous = start
        var nextObservation = start
        for _ in 0..<322 {
            let now = elapsedSeconds()
            guard now.isFinite, now >= previous, now <= Double(VPARequest.maximumSeconds) else {
                throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
            }
            previous = now
            try check()
            if now >= nextObservation || now >= start + seconds {
                try observe()
                nextObservation = now + 1
            }
            let observed = elapsedSeconds()
            guard observed.isFinite, observed >= previous, observed <= Double(VPARequest.maximumSeconds),
                observed - now <= VPARequest.maximumObservationSeconds
            else {
                throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
            }
            previous = observed
            try check()
            if observed >= start + seconds { return }
            sleep(min(0.05, start + seconds - observed))
        }
        throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
    }
}
