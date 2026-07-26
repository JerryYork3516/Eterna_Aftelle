import Foundation

struct ParticleVisualChannels: Equatable {
    var focus: Float
    var pulse: Float
    var circulation: Float
    var disruption: Float
    var dissolution: Float

    static func target(for intent: ResidentVisualIntent) -> ParticleVisualChannels {
        let profile: ParticleVisualProfile
        switch intent {
        case .idle:
            profile = ParticleTuning.Engine.idleProfile
        case .listening:
            profile = ParticleTuning.Engine.listeningProfile
        case .thinking:
            profile = ParticleTuning.Engine.thinkingProfile
        case .speaking:
            profile = ParticleTuning.Engine.speakingProfile
        case .sleeping:
            profile = ParticleTuning.Engine.sleepingProfile
        case .error:
            profile = ParticleTuning.Engine.errorProfile
        case .loading:
            profile = ParticleTuning.Engine.loadingProfile
        case .exit:
            profile = ParticleTuning.Engine.exitProfile
        }
        return ParticleVisualChannels(
            focus: profile.focus,
            pulse: profile.pulse,
            circulation: profile.circulation,
            disruption: profile.disruption,
            dissolution: profile.dissolution
        )
    }

    func applying(speechSignal: ResidentSpeechSignal) -> ParticleVisualChannels {
        let signal = speechSignal.normalized()
        var result = self
        switch signal.phase {
        case .inactive, .paused, .ended:
            break
        case .started:
            result.pulse = max(
                result.pulse,
                ParticleTuning.Engine.speechStartPulseBase
                    + signal.intensity
                    * ParticleTuning.Engine.speechStartPulseIntensityScale
            )
            result.circulation = max(
                result.circulation,
                ParticleTuning.Engine.speechCirculationBase
            )
        case .sustained:
            result.pulse = max(
                result.pulse,
                ParticleTuning.Engine.speechSustainPulseBase
                    + signal.intensity
                    * ParticleTuning.Engine.speechSustainPulseIntensityScale
            )
            result.circulation = max(
                result.circulation,
                ParticleTuning.Engine.speechCirculationBase
                    + signal.intensity
                    * ParticleTuning.Engine.speechCirculationIntensityScale
            )
        }
        return result.clamped()
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

    func clamped() -> ParticleVisualChannels {
        ParticleVisualChannels(
            focus: min(1, max(0, focus)),
            pulse: min(1, max(0, pulse)),
            circulation: min(1, max(0, circulation)),
            disruption: min(1, max(0, disruption)),
            dissolution: min(1, max(0, dissolution))
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
    let speechSignal: ResidentSpeechSignal
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
    private(set) var speechSignal: ResidentSpeechSignal
    private(set) var transitionReason = "startup"
    private(set) var transitionState: ParticleTransitionState
    private var previousTime: TimeInterval
    private var deltaTime: Float = 0
    private var errorRecoveryTime: TimeInterval?

    init(
        intent: ResidentVisualIntent = .idle,
        speechSignal: ResidentSpeechSignal = .inactive,
        time: TimeInterval
    ) {
        let signal = speechSignal.normalized()
        let channels = ParticleVisualChannels.target(for: intent)
            .applying(speechSignal: signal)
        currentIntent = intent
        targetIntent = intent
        self.speechSignal = signal
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

        if intent == .error {
            errorRecoveryTime = time + ParticleTuning.Engine.errorImpulseHoldDuration
        } else {
            errorRecoveryTime = nil
        }

        guard targetIntent != intent || intent == .error else {
            transitionReason = reason
            return
        }

        currentIntent = targetIntent
        targetIntent = intent
        beginTransition(
            from: liveChannels,
            to: combinedTarget(errorImpulseActive: intent == .error),
            duration: ParticleTuning.Engine.visualTransitionDuration,
            reason: reason,
            time: time
        )
    }

    func setSpeechSignal(
        _ signal: ResidentSpeechSignal,
        reason: String,
        time: TimeInterval
    ) {
        let normalizedSignal = signal.normalized()
        guard speechSignal != normalizedSignal else { return }

        updateClock(time: time)
        let liveChannels = resolveChannels(time: time)
        settleCompletedTransition()
        speechSignal = normalizedSignal
        beginTransition(
            from: liveChannels,
            to: combinedTarget(errorImpulseActive: errorRecoveryTime != nil),
            duration: speechTransitionDuration(for: normalizedSignal.phase),
            reason: reason,
            time: time
        )
    }

    func advance(time: TimeInterval) -> ParticleVisualState {
        updateClock(time: time)
        recoverErrorImpulseIfNeeded(time: time)
        let channels = resolveChannels(time: time)
        settleCompletedTransition()

        let flowSpeedMultiplier = min(
            ParticleTuning.Engine.maximumStateFlowScale,
            max(
                ParticleTuning.Engine.minimumStateFlowScale,
                1
                    - ParticleTuning.Engine.focusFlowReduction * channels.focus
                    + ParticleTuning.Engine.pulseFlowIncrease * channels.pulse
                    + ParticleTuning.Engine.circulationFlowIncrease
                    * channels.circulation
                    - ParticleTuning.Engine.instabilityFlowReduction
                    * channels.disruption
                    - ParticleTuning.Engine.dissolutionFlowReduction
                    * channels.dissolution
            )
        )

        return ParticleVisualState(
            currentIntent: currentIntent,
            targetIntent: targetIntent,
            speechSignal: speechSignal,
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

    private func beginTransition(
        from current: ParticleVisualChannels,
        to target: ParticleVisualChannels,
        duration: TimeInterval,
        reason: String,
        time: TimeInterval
    ) {
        transitionReason = reason
        transitionState = ParticleTransitionState(
            currentChannels: current,
            targetChannels: target,
            startTime: time,
            duration: duration,
            progress: 0
        )
    }

    private func combinedTarget(errorImpulseActive: Bool) -> ParticleVisualChannels {
        if targetIntent == .exit {
            return ParticleVisualChannels.target(for: .exit)
        }
        var channels = ParticleVisualChannels.target(for: targetIntent)
            .applying(speechSignal: speechSignal)
        if errorImpulseActive, targetIntent == .error {
            channels.disruption = max(
                channels.disruption,
                ParticleTuning.Engine.errorImpulseStrength
            )
        }
        return channels.clamped()
    }

    private func recoverErrorImpulseIfNeeded(time: TimeInterval) {
        guard let errorRecoveryTime, time >= errorRecoveryTime else { return }
        let liveChannels = resolveChannels(time: time)
        self.errorRecoveryTime = nil
        beginTransition(
            from: liveChannels,
            to: combinedTarget(errorImpulseActive: false),
            duration: ParticleTuning.Engine.errorRecoveryDuration,
            reason: "errorRecovery",
            time: time
        )
    }

    private func speechTransitionDuration(
        for phase: ResidentSpeechPhase
    ) -> TimeInterval {
        switch phase {
        case .started:
            return ParticleTuning.Engine.speechStartDuration
        case .sustained:
            return ParticleTuning.Engine.speechStartDuration
        case .paused:
            return ParticleTuning.Engine.speechPauseDuration
        case .inactive, .ended:
            return ParticleTuning.Engine.speechEndDuration
        }
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
