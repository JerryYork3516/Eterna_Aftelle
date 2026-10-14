import Foundation

public enum SourceProbePhase: String, Codable {
    case initialQuiet = "QUIET_INITIAL"
    case phraseOne = "PHRASE_ONE"
    case betweenQuiet = "QUIET_BETWEEN"
    case phraseTwo = "PHRASE_TWO"
    case finalQuiet = "QUIET_FINAL"
}

public enum SourceProbeWindow {
    public static func capture(
        observer: any PlaybackConfigurationObserving, startAndValidate: () throws -> Void,
        window: () throws -> Void, stop: () -> Void
    ) throws {
        var failure: Error?
        try PlaybackLifecycle.run(
            observer: observer, startAndValidate: startAndValidate, play: {},
            score: {
                do { try window() } catch { failure = error }
            }, stop: stop)
        if let failure { throw failure }
    }

    public static func run(
        durationSeconds: Double, elapsedSeconds: () -> Double, observe: () throws -> Void,
        cue: (SourceProbePhase, Double) -> Void, wait: (Double) -> Void
    ) throws {
        guard durationSeconds.isFinite, durationSeconds > 0, durationSeconds <= 8 else {
            throw EngineeringFailure(stage: .command, code: .invalidArguments)
        }
        let phases: [(Double, SourceProbePhase)] = [
            (0, .initialQuiet), (2, .phraseOne), (3.3, .betweenQuiet), (4, .phraseTwo), (5.5, .finalQuiet)
        ]
        var nextPhase = 0
        var previous = 0.0
        for _ in 0..<162 {
            let elapsed = elapsedSeconds()
            guard elapsed.isFinite, elapsed >= previous else {
                throw EngineeringFailure(stage: .recorder, code: .probeClockInvalid)
            }
            previous = elapsed
            try observe()
            let observed = elapsedSeconds()
            guard observed.isFinite, observed >= previous else {
                throw EngineeringFailure(stage: .recorder, code: .probeClockInvalid)
            }
            previous = observed
            if observed >= durationSeconds {
                guard nextPhase == phases.count else {
                    throw EngineeringFailure(stage: .recorder, code: .probeStimulusWindowMissed)
                }
                return
            }
            if nextPhase < phases.count, observed >= phases[nextPhase].0 {
                guard nextPhase + 1 == phases.count || observed < phases[nextPhase + 1].0 else {
                    throw EngineeringFailure(stage: .recorder, code: .probeStimulusWindowMissed)
                }
                cue(phases[nextPhase].1, observed)
                nextPhase += 1
            }
            wait(min(0.05, durationSeconds - observed))
        }
        throw EngineeringFailure(stage: .recorder, code: .probeClockInvalid)
    }
}
