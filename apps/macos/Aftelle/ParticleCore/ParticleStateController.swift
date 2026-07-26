import Foundation

struct ParticleVisualChannels: Equatable {
    var focus: Float
    var pulse: Float
    var circulation: Float
    var disruption: Float
    var dissolution: Float

    static func target(for intent: ResidentVisualIntent) -> ParticleVisualChannels {
        ParticleVisualChannels(
            focus: intent == .thinking ? 1 : 0,
            pulse: intent == .speaking ? 1 : 0,
            circulation: intent == .loading ? 1 : 0,
            disruption: intent == .error ? 1 : 0,
            dissolution: intent == .exit ? 1 : 0
        )
    }

    func interpolated(
        to target: ParticleVisualChannels,
        progress: Float
    ) -> ParticleVisualChannels {
        ParticleVisualChannels(
            focus: focus + (target.focus - focus) * progress,
            pulse: pulse + (target.pulse - pulse) * progress,
            circulation: circulation + (target.circulation - circulation) * progress,
            disruption: disruption + (target.disruption - disruption) * progress,
            dissolution: dissolution + (target.dissolution - dissolution) * progress
        )
    }
}

struct ParticleTransitionState {
    var currentChannels: ParticleVisualChannels
    var targetChannels: ParticleVisualChannels
    var startTime: TimeInterval
    var duration: TimeInterval
    var progress: Float
}

struct ParticleVisualState {
    let currentIntent: ResidentVisualIntent
    let targetIntent: ResidentVisualIntent
    let transitionReason: String
    let transitionElapsedTime: Float
    let transitionDuration: Float
    let transitionProgress: Float
    let deltaTime: Float
    let focusStrength: Float
    let pulseStrength: Float
    let circulationStrength: Float
    let disruptionStrength: Float
    let dissolutionStrength: Float
    let flowSpeedMultiplier: Float

    var channels: ParticleVisualChannels {
        ParticleVisualChannels(
            focus: focusStrength,
            pulse: pulseStrength,
            circulation: circulationStrength,
            disruption: disruptionStrength,
            dissolution: dissolutionStrength
        )
    }
}

final class ParticleStateController {
    private(set) var currentIntent: ResidentVisualIntent
    private(set) var targetIntent: ResidentVisualIntent
    private(set) var transitionReason = "startup"
    private(set) var transitionState: ParticleTransitionState
    private var previousTime: TimeInterval
    private var deltaTime: Float = 0

    init(intent: ResidentVisualIntent = .idle, time: TimeInterval) {
        let channels = ParticleVisualChannels.target(for: intent)
        currentIntent = intent
        targetIntent = intent
        previousTime = time
        transitionState = ParticleTransitionState(
            currentChannels: channels,
            targetChannels: channels,
            startTime: time,
            duration: ParticleTuning.Engine.visualTransitionDuration,
            progress: 1
        )
    }

    func setIntent(_ intent: ResidentVisualIntent, reason: String, time: TimeInterval) {
        updateClock(time: time)
        let liveChannels = resolveChannels(time: time)
        settleCompletedTransition()

        guard targetIntent != intent else {
            transitionReason = reason
            return
        }

        currentIntent = targetIntent
        targetIntent = intent
        transitionReason = reason
        transitionState = ParticleTransitionState(
            currentChannels: liveChannels,
            targetChannels: ParticleVisualChannels.target(for: intent),
            startTime: time,
            duration: ParticleTuning.Engine.visualTransitionDuration,
            progress: 0
        )
    }

    func advance(time: TimeInterval) -> ParticleVisualState {
        updateClock(time: time)
        let channels = resolveChannels(time: time)
        settleCompletedTransition()

        let instability = max(channels.disruption, channels.dissolution)
        let flowSpeedMultiplier = (
            1 - ParticleTuning.Engine.focusFlowReduction * channels.focus
        ) * (
            1 + ParticleTuning.Engine.pulseFlowIncrease * channels.pulse
        ) * (
            1 - ParticleTuning.Engine.instabilityFlowReduction * instability
        )

        return ParticleVisualState(
            currentIntent: currentIntent,
            targetIntent: targetIntent,
            transitionReason: transitionReason,
            transitionElapsedTime: Float(
                transitionState.duration * Double(transitionState.progress)
            ),
            transitionDuration: Float(transitionState.duration),
            transitionProgress: transitionState.progress,
            deltaTime: deltaTime,
            focusStrength: channels.focus,
            pulseStrength: channels.pulse,
            circulationStrength: channels.circulation,
            disruptionStrength: channels.disruption,
            dissolutionStrength: channels.dissolution,
            flowSpeedMultiplier: flowSpeedMultiplier
        )
    }

    private func updateClock(time: TimeInterval) {
        let rawDelta = max(0, time - previousTime)
        let maximumDelta = TimeInterval(ParticleTuning.Engine.maximumSimulationStep)
        let clampedDelta = min(rawDelta, maximumDelta)
        let discardedDelta = rawDelta - clampedDelta
        if discardedDelta > 0, transitionState.progress < 1 {
            transitionState.startTime += discardedDelta
        }
        previousTime = time
        deltaTime = Float(clampedDelta)
    }

    private func resolveChannels(time: TimeInterval) -> ParticleVisualChannels {
        let duration = max(
            transitionState.duration,
            ParticleTuning.Engine.minimumTransitionDuration
        )
        let rawProgress = (time - transitionState.startTime) / duration
        let progress = Float(min(1, max(0, rawProgress)))
        transitionState.progress = progress
        return transitionState.currentChannels.interpolated(
            to: transitionState.targetChannels,
            progress: Self.eased(progress)
        )
    }

    private func settleCompletedTransition() {
        guard transitionState.progress >= 1 else { return }
        currentIntent = targetIntent
        transitionState.currentChannels = transitionState.targetChannels
    }

    private static func eased(_ progress: Float) -> Float {
        progress * progress * (3 - 2 * progress)
    }
}
