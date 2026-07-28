import Foundation

enum RuntimeExpressionState: String, CaseIterable, Codable {
    case neutral
    case calm
    case caring
    case subdued
    case joyful
}

enum RuntimeExpressionMappingSource: String, Equatable {
    case dr
    case compatibilityFallback = "compatibility_fallback"
}

struct RuntimeExpressionRange: Equatable {
    let minimum: Double
    let maximum: Double

    func clamp(_ value: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}

struct RuntimeExpressionParameterRanges: Equatable {
    let expressionIntensity: RuntimeExpressionRange
    let brightnessMultiplier: RuntimeExpressionRange
    let saturationMultiplier: RuntimeExpressionRange
    let temperatureShift: RuntimeExpressionRange
    let energyMultiplier: RuntimeExpressionRange
    let motionSpeedMultiplier: RuntimeExpressionRange
    let diffusionMultiplier: RuntimeExpressionRange
}

struct RuntimeExpressionStateSelectionPolicy: Equatable {
    let selectionSource: String
    let stateField: String
    let intensityField: String
    let selectionRules: [String]
    let allowedStates: [RuntimeExpressionState]
    let defaultState: RuntimeExpressionState
    let missingStateFallback: RuntimeExpressionState
    let invalidStateFallback: RuntimeExpressionState
    let singleStatePerTurn: Bool
    let residentExpressionOnly: Bool
    let userEmotionDiagnosis: Bool
    let rendererParametersAllowed: Bool
    let lifecycleStateSeparated: Bool
}

struct RuntimeExpressionFallbackPolicy: Equatable {
    let invalidState: RuntimeExpressionState
    let missingState: RuntimeExpressionState
    let clampIntensity: Bool
    let clampMappingValues: Bool
}

struct RuntimeExpressionTransitionPolicy: Equatable {
    let transitionDuration: Double
    let minimumHoldDuration: Double
    let repeatSameStateRestartsTransition: Bool
    let continueFromCurrentVisualValue: Bool
    let usesAccumulatedIdleTimeAsProgress: Bool
}

struct RuntimeExpressionLifecyclePriority: Equatable {
    let overrideStates: [String]
    let composableStates: [String]
}

struct RuntimeExpressionMultipliers: Equatable {
    let brightnessMultiplier: Double
    let saturationMultiplier: Double
    let temperatureShift: Double
    let energyMultiplier: Double
    let motionSpeedMultiplier: Double
    let diffusionMultiplier: Double

    static let unit = RuntimeExpressionMultipliers(
        brightnessMultiplier: 1,
        saturationMultiplier: 1,
        temperatureShift: 0,
        energyMultiplier: 1,
        motionSpeedMultiplier: 1,
        diffusionMultiplier: 1
    )

    func scaled(by intensity: Double) -> RuntimeExpressionMultipliers {
        RuntimeExpressionMultipliers(
            brightnessMultiplier: 1 + (brightnessMultiplier - 1) * intensity,
            saturationMultiplier: 1 + (saturationMultiplier - 1) * intensity,
            temperatureShift: temperatureShift * intensity,
            energyMultiplier: 1 + (energyMultiplier - 1) * intensity,
            motionSpeedMultiplier: 1 + (motionSpeedMultiplier - 1) * intensity,
            diffusionMultiplier: 1 + (diffusionMultiplier - 1) * intensity
        )
    }

    func clamped(to ranges: RuntimeExpressionParameterRanges) -> RuntimeExpressionMultipliers {
        RuntimeExpressionMultipliers(
            brightnessMultiplier: ranges.brightnessMultiplier.clamp(brightnessMultiplier),
            saturationMultiplier: ranges.saturationMultiplier.clamp(saturationMultiplier),
            temperatureShift: ranges.temperatureShift.clamp(temperatureShift),
            energyMultiplier: ranges.energyMultiplier.clamp(energyMultiplier),
            motionSpeedMultiplier: ranges.motionSpeedMultiplier.clamp(motionSpeedMultiplier),
            diffusionMultiplier: ranges.diffusionMultiplier.clamp(diffusionMultiplier)
        )
    }
}

struct RuntimeVisualExpressionMapping: Equatable {
    let source: RuntimeExpressionMappingSource
    let allowedStates: [RuntimeExpressionState]
    let defaultState: RuntimeExpressionState
    let intensityRange: RuntimeExpressionRange
    let parameterRanges: RuntimeExpressionParameterRanges
    let stateSelectionPolicy: RuntimeExpressionStateSelectionPolicy
    let fallbackPolicy: RuntimeExpressionFallbackPolicy
    let particleCoreMapping: [RuntimeExpressionState: RuntimeExpressionMultipliers]
    let transitionPolicy: RuntimeExpressionTransitionPolicy
    let lifecyclePriority: RuntimeExpressionLifecyclePriority

    static let compatibilityFallback: RuntimeVisualExpressionMapping = {
        let unitRange = RuntimeExpressionRange(minimum: 1, maximum: 1)
        let zeroRange = RuntimeExpressionRange(minimum: 0, maximum: 0)
        let intensityRange = RuntimeExpressionRange(minimum: 0, maximum: 1)
        return RuntimeVisualExpressionMapping(
            source: .compatibilityFallback,
            allowedStates: [.neutral],
            defaultState: .neutral,
            intensityRange: intensityRange,
            parameterRanges: RuntimeExpressionParameterRanges(
                expressionIntensity: intensityRange,
                brightnessMultiplier: unitRange,
                saturationMultiplier: unitRange,
                temperatureShift: zeroRange,
                energyMultiplier: unitRange,
                motionSpeedMultiplier: unitRange,
                diffusionMultiplier: unitRange
            ),
            stateSelectionPolicy: RuntimeExpressionStateSelectionPolicy(
                selectionSource: "runtime_core",
                stateField: "expression_state",
                intensityField: "expression_intensity",
                selectionRules: ["prefer_neutral_when_context_insufficient"],
                allowedStates: [.neutral],
                defaultState: .neutral,
                missingStateFallback: .neutral,
                invalidStateFallback: .neutral,
                singleStatePerTurn: true,
                residentExpressionOnly: true,
                userEmotionDiagnosis: false,
                rendererParametersAllowed: false,
                lifecycleStateSeparated: true
            ),
            fallbackPolicy: RuntimeExpressionFallbackPolicy(
                invalidState: .neutral,
                missingState: .neutral,
                clampIntensity: true,
                clampMappingValues: true
            ),
            particleCoreMapping: [.neutral: .unit],
            transitionPolicy: RuntimeExpressionTransitionPolicy(
                transitionDuration: 0.6,
                minimumHoldDuration: 0.35,
                repeatSameStateRestartsTransition: false,
                continueFromCurrentVisualValue: true,
                usesAccumulatedIdleTimeAsProgress: false
            ),
            lifecyclePriority: RuntimeExpressionLifecyclePriority(
                overrideStates: ["error", "loading", "exit"],
                composableStates: ["idle", "thinking", "speaking"]
            )
        )
    }()
}

struct RuntimeExpressionResult: Equatable {
    let expressionState: RuntimeExpressionState
    let expressionIntensity: Double
    let expressionFallbackOccurred: Bool
    let expressionMapping: RuntimeExpressionMultipliers
    let mappingSource: RuntimeExpressionMappingSource

    static func neutral(
        source: RuntimeExpressionMappingSource,
        fallbackOccurred: Bool
    ) -> RuntimeExpressionResult {
        RuntimeExpressionResult(
            expressionState: .neutral,
            expressionIntensity: 0,
            expressionFallbackOccurred: fallbackOccurred,
            expressionMapping: .unit,
            mappingSource: source
        )
    }
}

struct RuntimeResidentReply: Equatable {
    let replyText: String
    let expression: RuntimeExpressionResult
    let relationshipEvidenceCandidates:
        [ProviderRelationshipEvidenceCandidate]
}

public final class VisualStateMapper {
    public init() {}

    public func map(mode: VisualStateMode) -> VisualState {
        VisualState(mode: mode)
    }

    func mapExpression(
        reply: ProviderResidentReply,
        mapping: RuntimeVisualExpressionMapping
    ) -> RuntimeExpressionResult {
        guard mapping.source == .dr else {
            return .neutral(source: mapping.source, fallbackOccurred: true)
        }
        guard reply.expressionEnvelopeParsed,
              let rawState = reply.expressionState?
              .trimmingCharacters(in: .whitespacesAndNewlines)
              .lowercased(),
              let state = RuntimeExpressionState(rawValue: rawState),
              mapping.allowedStates.contains(state),
              let rawIntensity = reply.expressionIntensity,
              rawIntensity.isFinite,
              let target = mapping.particleCoreMapping[state] else {
            return .neutral(source: mapping.source, fallbackOccurred: true)
        }

        let intensity = mapping.parameterRanges.expressionIntensity.clamp(
            mapping.intensityRange.clamp(min(1, max(0, rawIntensity)))
        )
        let multipliers = state == .neutral
            ? RuntimeExpressionMultipliers.unit
            : target.scaled(by: intensity).clamped(to: mapping.parameterRanges)
        return RuntimeExpressionResult(
            expressionState: state,
            expressionIntensity: intensity,
            expressionFallbackOccurred: mapping.source == .compatibilityFallback,
            expressionMapping: multipliers,
            mappingSource: mapping.source
        )
    }

    public func mapAvatarState(visualState: VisualState, residentID: String, displayName: String) -> AvatarState {
        switch visualState.mode {
        case .idle:
            return AvatarState(
                residentID: residentID,
                displayName: displayName,
                mode: "idle",
                presence: "present",
                moodHint: "calm",
                activityHint: "resting",
                particleHint: "calibration_idle"
            )
        case .thinking:
            return AvatarState(
                residentID: residentID,
                displayName: displayName,
                mode: "thinking",
                presence: "present",
                moodHint: "focused",
                activityHint: "processing",
                particleHint: "calibration_thinking"
            )
        case .speaking:
            return AvatarState(
                residentID: residentID,
                displayName: displayName,
                mode: "speaking",
                presence: "active",
                moodHint: "expressive",
                activityHint: "speaking",
                particleHint: "calibration_speaking"
            )
        }
    }
}
