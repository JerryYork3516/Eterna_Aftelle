import Foundation

struct ParticleVisualState {
    let currentIntent: ResidentVisualIntent
    let previousIntent: ResidentVisualIntent
    let transitionReason: String
    let transitionElapsedTime: Float
    let focusStrength: Float
    let pulseStrength: Float
    let circulationStrength: Float
    let disruptionStrength: Float
    let dissolutionStrength: Float
    let flowSpeedMultiplier: Float
}

final class ParticleStateController {
    private(set) var currentIntent: ResidentVisualIntent
    private(set) var previousIntent: ResidentVisualIntent
    private(set) var transitionReason = "startup"
    private var transitionStartTime: TimeInterval
    private var focusStrength: Float
    private var pulseStrength: Float
    private var circulationStrength: Float
    private var disruptionStrength: Float
    private var dissolutionStrength: Float

    init(intent: ResidentVisualIntent = .idle, time: TimeInterval) {
        currentIntent = intent
        previousIntent = intent
        transitionStartTime = time
        focusStrength = Self.targetStrength(for: .thinking, current: intent)
        pulseStrength = Self.targetStrength(for: .speaking, current: intent)
        circulationStrength = Self.targetStrength(for: .loading, current: intent)
        disruptionStrength = Self.targetStrength(for: .error, current: intent)
        dissolutionStrength = Self.targetStrength(for: .exit, current: intent)
    }

    func setIntent(_ intent: ResidentVisualIntent, reason: String, time: TimeInterval) {
        if currentIntent == intent {
            if intent == .exit {
                transitionStartTime = time
            }
            transitionReason = reason
            return
        }

        previousIntent = currentIntent
        currentIntent = intent
        transitionStartTime = time
        transitionReason = reason
        if intent == .idle {
            dissolutionStrength = 0
        }
    }

    func advance(time: TimeInterval) -> ParticleVisualState {
        let response = ParticleTuning.Engine.stateResponse
        focusStrength += (Self.targetStrength(for: .thinking, current: currentIntent) - focusStrength) * response
        pulseStrength += (Self.targetStrength(for: .speaking, current: currentIntent) - pulseStrength) * response
        circulationStrength += (Self.targetStrength(for: .loading, current: currentIntent) - circulationStrength) * response
        disruptionStrength += (Self.targetStrength(for: .error, current: currentIntent) - disruptionStrength) * response
        let dissolutionResponse = currentIntent == .exit
            ? ParticleTuning.Engine.dissolutionRiseResponse
            : ParticleTuning.Engine.dissolutionFallResponse
        dissolutionStrength += (
            Self.targetStrength(for: .exit, current: currentIntent) - dissolutionStrength
        ) * dissolutionResponse

        let focus = Self.eased(focusStrength)
        let pulse = Self.eased(pulseStrength)
        let instability = max(Self.eased(disruptionStrength), dissolutionStrength)
        let flowSpeedMultiplier = (1 - ParticleTuning.Engine.focusFlowReduction * focus)
            * (1 + ParticleTuning.Engine.pulseFlowIncrease * pulse)
            * (1 - ParticleTuning.Engine.instabilityFlowReduction * instability)

        return ParticleVisualState(
            currentIntent: currentIntent,
            previousIntent: previousIntent,
            transitionReason: transitionReason,
            transitionElapsedTime: Float(max(0, time - transitionStartTime)),
            focusStrength: focusStrength,
            pulseStrength: pulseStrength,
            circulationStrength: circulationStrength,
            disruptionStrength: disruptionStrength,
            dissolutionStrength: dissolutionStrength,
            flowSpeedMultiplier: flowSpeedMultiplier
        )
    }

    private static func targetStrength(
        for intent: ResidentVisualIntent,
        current: ResidentVisualIntent
    ) -> Float {
        current == intent ? 1 : 0
    }

    private static func eased(_ value: Float) -> Float {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
