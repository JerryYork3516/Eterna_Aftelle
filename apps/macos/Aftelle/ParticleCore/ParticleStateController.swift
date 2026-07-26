import Foundation

enum ParticleExpressionState: String, CaseIterable, Equatable {
    case neutral
    case calm
    case caring
    case subdued
    case joyful
}

struct ParticleExpressionMultipliers: Equatable {
    let brightnessMultiplier: Float
    let saturationMultiplier: Float
    let temperatureShift: Float
    let energyMultiplier: Float
    let motionSpeedMultiplier: Float
    let diffusionMultiplier: Float

    static let unit = ParticleExpressionMultipliers(
        brightnessMultiplier: 1,
        saturationMultiplier: 1,
        temperatureShift: 0,
        energyMultiplier: 1,
        motionSpeedMultiplier: 1,
        diffusionMultiplier: 1
    )

    var isFinite: Bool {
        brightnessMultiplier.isFinite
            && saturationMultiplier.isFinite
            && temperatureShift.isFinite
            && energyMultiplier.isFinite
            && motionSpeedMultiplier.isFinite
            && diffusionMultiplier.isFinite
    }

    func interpolated(
        to target: ParticleExpressionMultipliers,
        progress: Float
    ) -> ParticleExpressionMultipliers {
        ParticleExpressionMultipliers(
            brightnessMultiplier: brightnessMultiplier
                + (target.brightnessMultiplier - brightnessMultiplier) * progress,
            saturationMultiplier: saturationMultiplier
                + (target.saturationMultiplier - saturationMultiplier) * progress,
            temperatureShift: temperatureShift
                + (target.temperatureShift - temperatureShift) * progress,
            energyMultiplier: energyMultiplier
                + (target.energyMultiplier - energyMultiplier) * progress,
            motionSpeedMultiplier: motionSpeedMultiplier
                + (target.motionSpeedMultiplier - motionSpeedMultiplier) * progress,
            diffusionMultiplier: diffusionMultiplier
                + (target.diffusionMultiplier - diffusionMultiplier) * progress
        )
    }

    func isApproximatelyEqual(
        to other: ParticleExpressionMultipliers,
        tolerance: Float = 0.001
    ) -> Bool {
        abs(brightnessMultiplier - other.brightnessMultiplier) < tolerance
            && abs(saturationMultiplier - other.saturationMultiplier) < tolerance
            && abs(temperatureShift - other.temperatureShift) < tolerance
            && abs(energyMultiplier - other.energyMultiplier) < tolerance
            && abs(motionSpeedMultiplier - other.motionSpeedMultiplier) < tolerance
            && abs(diffusionMultiplier - other.diffusionMultiplier) < tolerance
    }

    func applyingColor(to color: SIMD4<Float>) -> SIMD4<Float> {
        guard self != .unit else { return color }
        let source = SIMD3<Float>(color.x, color.y, color.z)
        let sourceLuminance = Self.luminance(source)
        var adjusted = SIMD3<Float>(repeating: sourceLuminance)
            + (source - SIMD3<Float>(repeating: sourceLuminance))
            * saturationMultiplier
        let luminanceBeforeTemperature = Self.luminance(adjusted)
        adjusted += SIMD3<Float>(
            temperatureShift,
            0,
            -temperatureShift
        )
        let luminanceCorrection = luminanceBeforeTemperature
            - Self.luminance(adjusted)
        adjusted += SIMD3<Float>(repeating: luminanceCorrection)
        return SIMD4<Float>(
            Self.clampColor(adjusted.x),
            Self.clampColor(adjusted.y),
            Self.clampColor(adjusted.z),
            color.w
        )
    }

    func applyingBrightness(to brightness: Float) -> Float {
        guard self != .unit else { return brightness }
        return brightness * brightnessMultiplier
    }

    func applyingEnergy(
        to flowMotionStrength: Float,
        maximum: Float
    ) -> Float {
        guard self != .unit else {
            return min(maximum, flowMotionStrength)
        }
        return min(maximum, flowMotionStrength * energyMultiplier)
    }

    func applyingMotionSpeed(to flowTimeStep: Float) -> Float {
        guard self != .unit else { return flowTimeStep }
        return flowTimeStep * motionSpeedMultiplier
    }

    func applyingDiffusion(
        to flowShapeStrength: Float,
        maximum: Float
    ) -> Float {
        guard self != .unit else { return flowShapeStrength }
        return min(maximum, max(0, flowShapeStrength * diffusionMultiplier))
    }

    private static func luminance(_ color: SIMD3<Float>) -> Float {
        color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722
    }

    private static func clampColor(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}

struct ParticleExpressionInput: Equatable {
    let interactionID: UUID?
    let state: ParticleExpressionState
    let intensity: Float
    let fallbackOccurred: Bool
    let mappingSource: String
    let multipliers: ParticleExpressionMultipliers

    static let neutral = ParticleExpressionInput.neutral(
        mappingSource: "compatibility_fallback",
        fallbackOccurred: true
    )

    init(
        interactionID: UUID? = nil,
        state rawState: String?,
        intensity rawIntensity: Double?,
        fallbackOccurred: Bool,
        mappingSource rawMappingSource: String?,
        brightnessMultiplier: Double?,
        saturationMultiplier: Double?,
        temperatureShift: Double?,
        energyMultiplier: Double?,
        motionSpeedMultiplier: Double?,
        diffusionMultiplier: Double?
    ) {
        guard let rawState,
              let state = ParticleExpressionState(rawValue: rawState),
              let rawIntensity,
              rawIntensity.isFinite,
              let brightnessMultiplier,
              brightnessMultiplier.isFinite,
              let saturationMultiplier,
              saturationMultiplier.isFinite,
              let temperatureShift,
              temperatureShift.isFinite,
              let energyMultiplier,
              energyMultiplier.isFinite,
              let motionSpeedMultiplier,
              motionSpeedMultiplier.isFinite,
              let diffusionMultiplier,
              diffusionMultiplier.isFinite,
              let rawMappingSource,
              rawMappingSource == "dr"
                || rawMappingSource == "compatibility_fallback" else {
            self = .neutral(
                mappingSource: rawMappingSource == "dr"
                    ? "dr"
                    : "compatibility_fallback",
                fallbackOccurred: true,
                interactionID: interactionID
            )
            return
        }

        let mappedMultipliers = ParticleExpressionMultipliers(
            brightnessMultiplier: Float(brightnessMultiplier),
            saturationMultiplier: Float(saturationMultiplier),
            temperatureShift: Float(temperatureShift),
            energyMultiplier: Float(energyMultiplier),
            motionSpeedMultiplier: Float(motionSpeedMultiplier),
            diffusionMultiplier: Float(diffusionMultiplier)
        )
        guard mappedMultipliers.isFinite else {
            self = .neutral(
                mappingSource: rawMappingSource,
                fallbackOccurred: true,
                interactionID: interactionID
            )
            return
        }

        self.interactionID = interactionID
        self.state = state
        intensity = Float(min(1, max(0, rawIntensity)))
        self.fallbackOccurred = fallbackOccurred
        mappingSource = rawMappingSource
        multipliers = state == .neutral ? .unit : mappedMultipliers
    }

    static func neutral(
        mappingSource: String,
        fallbackOccurred: Bool,
        interactionID: UUID? = nil
    ) -> ParticleExpressionInput {
        ParticleExpressionInput(
            interactionID: interactionID,
            state: .neutral,
            intensity: 0,
            fallbackOccurred: fallbackOccurred,
            mappingSource: mappingSource,
            multipliers: .unit
        )
    }

    private init(
        interactionID: UUID?,
        state: ParticleExpressionState,
        intensity: Float,
        fallbackOccurred: Bool,
        mappingSource: String,
        multipliers: ParticleExpressionMultipliers
    ) {
        self.interactionID = interactionID
        self.state = state
        self.intensity = intensity
        self.fallbackOccurred = fallbackOccurred
        self.mappingSource = mappingSource
        self.multipliers = multipliers
    }

    func matchesTransitionIdentity(_ other: ParticleExpressionInput) -> Bool {
        state == other.state
            && intensity == other.intensity
            && multipliers == other.multipliers
    }

    var requiresImmediateNeutralReset: Bool {
        state == .neutral
            && mappingSource == "compatibility_fallback"
            && fallbackOccurred
    }
}

struct ParticleExpressionVisualState: Equatable {
    let targetInput: ParticleExpressionInput
    let currentMultipliers: ParticleExpressionMultipliers
    let targetMultipliers: ParticleExpressionMultipliers
    let appliedMultipliers: ParticleExpressionMultipliers
    let transitionProgress: Float
    let lifecycleOverrideActive: Bool

    static let neutral = ParticleExpressionVisualState(
        targetInput: .neutral,
        currentMultipliers: .unit,
        targetMultipliers: .unit,
        appliedMultipliers: .unit,
        transitionProgress: 1,
        lifecycleOverrideActive: false
    )

    func matches(
        interactionID: UUID,
        state: String,
        intensity: Double,
        fallbackOccurred: Bool,
        mappingSource: String,
        targetMultipliers: ParticleExpressionMultipliers
    ) -> Bool {
        targetInput.interactionID == interactionID
            && targetInput.state.rawValue == state
            && abs(Double(targetInput.intensity) - intensity) < 0.001
            && targetInput.fallbackOccurred == fallbackOccurred
            && targetInput.mappingSource == mappingSource
            && self.targetMultipliers.isApproximatelyEqual(
                to: targetMultipliers
            )
    }
}

private struct ParticleExpressionTransitionState {
    var currentMultipliers: ParticleExpressionMultipliers
    var targetMultipliers: ParticleExpressionMultipliers
    var startTime: TimeInterval
    var progress: Float
}

private final class ParticleExpressionController {
    private static let transitionDuration: TimeInterval = 0.6
    private static let minimumHoldDuration: TimeInterval = 0.35

    private var acceptedInput: ParticleExpressionInput
    private var pendingInput: ParticleExpressionInput?
    private var transitionState: ParticleExpressionTransitionState
    private var previousWallTime: TimeInterval
    private var logicalTime: TimeInterval = 0
    private var acceptedAt: TimeInterval = 0
    private var lifecycleOverrideActive = false

    init(input: ParticleExpressionInput = .neutral, time: TimeInterval) {
        acceptedInput = input
        previousWallTime = time
        transitionState = ParticleExpressionTransitionState(
            currentMultipliers: input.multipliers,
            targetMultipliers: input.multipliers,
            startTime: 0,
            progress: 1
        )
    }

    @discardableResult
    func setInput(
        _ input: ParticleExpressionInput,
        time: TimeInterval
    ) -> Bool {
        updateClock(time: time, paused: lifecycleOverrideActive)
        let liveMultipliers = resolveMultipliers()

        if input.requiresImmediateNeutralReset {
            let changed = acceptedInput != input
                || liveMultipliers != .unit
            acceptedInput = input
            pendingInput = nil
            acceptedAt = logicalTime
            transitionState = ParticleExpressionTransitionState(
                currentMultipliers: .unit,
                targetMultipliers: .unit,
                startTime: logicalTime,
                progress: 1
            )
            return changed
        }
        if input.matchesTransitionIdentity(acceptedInput) {
            pendingInput = nil
            acceptedInput = input
            return false
        }
        guard logicalTime - acceptedAt >= Self.minimumHoldDuration else {
            pendingInput = input
            return false
        }
        accept(input, from: liveMultipliers)
        return true
    }

    func advance(
        time: TimeInterval,
        lifecycleOverrideActive: Bool
    ) -> ParticleExpressionVisualState {
        let wasLifecycleOverrideActive = self.lifecycleOverrideActive
        updateClock(
            time: time,
            paused: lifecycleOverrideActive || wasLifecycleOverrideActive
        )
        self.lifecycleOverrideActive = lifecycleOverrideActive
        if wasLifecycleOverrideActive && !lifecycleOverrideActive {
            resumeFromLifecycleOverride()
        }
        var currentMultipliers = resolveMultipliers()
        if acceptPendingInputIfReady(from: currentMultipliers) {
            currentMultipliers = resolveMultipliers()
        }
        let displayInput = pendingInput ?? acceptedInput
        let progress = pendingInput == nil ? transitionState.progress : 0
        return ParticleExpressionVisualState(
            targetInput: displayInput,
            currentMultipliers: currentMultipliers,
            targetMultipliers: displayInput.multipliers,
            appliedMultipliers: lifecycleOverrideActive
                ? .unit
                : currentMultipliers,
            transitionProgress: progress,
            lifecycleOverrideActive: lifecycleOverrideActive
        )
    }

    private func accept(
        _ input: ParticleExpressionInput,
        from currentMultipliers: ParticleExpressionMultipliers
    ) {
        acceptedInput = input
        pendingInput = nil
        acceptedAt = logicalTime
        transitionState = ParticleExpressionTransitionState(
            currentMultipliers: currentMultipliers,
            targetMultipliers: input.multipliers,
            startTime: logicalTime,
            progress: 0
        )
    }

    private func resumeFromLifecycleOverride() {
        let resumeInput = pendingInput ?? acceptedInput
        acceptedInput = resumeInput
        pendingInput = nil
        acceptedAt = logicalTime
        transitionState = ParticleExpressionTransitionState(
            currentMultipliers: .unit,
            targetMultipliers: resumeInput.multipliers,
            startTime: logicalTime,
            progress: 0
        )
    }

    @discardableResult
    private func acceptPendingInputIfReady(
        from currentMultipliers: ParticleExpressionMultipliers
    ) -> Bool {
        guard let pendingInput,
              logicalTime - acceptedAt >= Self.minimumHoldDuration else {
            return false
        }
        accept(pendingInput, from: currentMultipliers)
        return true
    }

    private func updateClock(
        time: TimeInterval,
        paused: Bool
    ) {
        let rawDelta = max(0, time - previousWallTime)
        previousWallTime = time
        guard !paused else { return }
        logicalTime += min(
            rawDelta,
            TimeInterval(ParticleTuning.Engine.maximumSimulationStep)
        )
    }

    private func resolveMultipliers() -> ParticleExpressionMultipliers {
        guard transitionState.progress < 1 else {
            return transitionState.targetMultipliers
        }
        let elapsed = logicalTime - transitionState.startTime
        let progress = Float(
            min(1, max(0, elapsed / Self.transitionDuration))
        )
        transitionState.progress = progress
        return transitionState.currentMultipliers.interpolated(
            to: transitionState.targetMultipliers,
            progress: Self.eased(progress)
        )
    }

    private static func eased(_ progress: Float) -> Float {
        progress * progress * progress
            * (progress * (progress * 6 - 15) + 10)
    }
}

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
    let expression: ParticleExpressionVisualState

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
    private let expressionController: ParticleExpressionController
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
        expressionController = ParticleExpressionController(time: time)
        transitionState = ParticleTransitionState(
            currentChannels: channels,
            targetChannels: channels,
            startTime: time,
            duration: ParticleTuning.Engine.visualTransitionDuration,
            progress: 1
        )
    }

    @discardableResult
    func setExpressionInput(
        _ input: ParticleExpressionInput,
        time: TimeInterval
    ) -> Bool {
        expressionController.setInput(input, time: time)
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
            duration: transitionDuration(for: intent),
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
        let expression = expressionController.advance(
            time: time,
            lifecycleOverrideActive: Self.lifecycleOverridesExpression(
                currentIntent: currentIntent,
                targetIntent: targetIntent
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
            flowSpeedMultiplier: flowSpeedMultiplier,
            expression: expression
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
            return ParticleTuning.Engine.speechStartTransitionDuration
        case .sustained:
            return ParticleTuning.Engine.speechSustainTransitionDuration
        case .paused:
            return ParticleTuning.Engine.speechPauseTransitionDuration
        case .inactive, .ended:
            return ParticleTuning.Engine.speechEndTransitionDuration
        }
    }

    private func transitionDuration(
        for intent: ResidentVisualIntent
    ) -> TimeInterval {
        switch intent {
        case .thinking:
            return ParticleTuning.Engine.thinkingTransitionDuration
        case .speaking:
            return ParticleTuning.Engine.speakingTransitionDuration
        case .loading:
            return ParticleTuning.Engine.loadingTransitionDuration
        case .error:
            return ParticleTuning.Engine.errorTransitionDuration
        case .exit:
            return ParticleTuning.Engine.exitTransitionDuration
        case .idle, .listening, .sleeping:
            return ParticleTuning.Engine.visualTransitionDuration
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
        progress * progress * progress
            * (progress * (progress * 6 - 15) + 10)
    }

    private static func lifecycleOverridesExpression(
        currentIntent: ResidentVisualIntent,
        targetIntent: ResidentVisualIntent
    ) -> Bool {
        !isExpressionComposable(currentIntent)
            || !isExpressionComposable(targetIntent)
    }

    private static func isExpressionComposable(
        _ intent: ResidentVisualIntent
    ) -> Bool {
        switch intent {
        case .idle, .thinking, .speaking:
            return true
        case .listening, .sleeping, .error, .loading, .exit:
            return false
        }
    }
}
