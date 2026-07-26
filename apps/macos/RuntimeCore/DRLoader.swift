import Foundation

public struct DRLoadRequest {
    public let drData: Data

    public init(drData: Data) {
        self.drData = drData
    }
}

struct FirstInteractionPolicy: Equatable {
    let enabled: Bool?
    let firstLoadEnabled: Bool?
    let repeatIntroduction: Bool?
}

struct FirstGreetingConfig: Equatable {
    let locale: String?
    let contentStatus: String?
    let variants: [String]
    let repeatOnReturn: Bool?
}

struct FirstPresenceConfig: Equatable {
    let particleState: String?
    let motion: String?
    let energy: String?
    let subtitleMode: String?
}

struct InitialRelationshipConfig: Equatable {
    let defaultMode: String?
    let intimacyLevel: String?
    let trustBuilding: String?
    let romanticAssumption: Bool?
}

struct RuntimeDialogueInstruction: Equatable {
    let instruction: String
    let sourceRuleRefs: [String]
}

struct RuntimeDialogueSourceRuleCoverage: Equatable {
    let selectedSemanticRuleCount: Int
    let translatedRuleCount: Int
    let unmappedRuleRefs: [String]
    let validationRuleCountExcluded: Int
}

struct RuntimeDialogueScenario: Equatable {
    let sceneID: String
    let intent: String
    let responseStrategy: String
    let followUpAllowed: Bool
    let adviceAllowed: Bool
    let recommendedLength: String
    let prohibitedBehaviors: [String]
    let linkedPolicyIDs: [String]
    let sourceRuleRefs: [String]
}

struct RuntimeDialogueExampleTurn: Equatable {
    let role: String
    let text: String
}

struct RuntimeDialogueFewShotExample: Equatable {
    let exampleID: String
    let label: String
    let sceneID: String
    let turns: [RuntimeDialogueExampleTurn]
    let usage: String
    let notFixedResponse: Bool
    let notKeywordMatching: Bool
}

struct RuntimeDialogueFewShotSelection: Equatable {
    let usage: String
    let notFixedResponse: Bool
    let notKeywordMatching: Bool
    let selectionMode: String
    let recommendedMaxExamplesPerRequest: Int
    let studioPerformsTokenTrimming: Bool
}

struct RuntimeDialogueProhibitedPattern: Equatable {
    let patternID: String
    let reason: String
    let examples: [String]
    let sourceRuleRefs: [String]
    let status: String
}

struct RuntimeDialogueContextSourceRule: Equatable {
    let sourceID: String
    let instruction: String
}

struct RuntimeDialogueContextUsagePolicy: Equatable {
    let allowedSources: [RuntimeDialogueContextSourceRule]
    let forbiddenSources: [RuntimeDialogueContextSourceRule]
    let studioBoundary: String
}

struct RuntimeDialogueFallbackBehavior: Equatable {
    let trigger: String
    let locale: String
    let text: String
    let constraints: [String]
}

struct RuntimeEmotionalDialoguePolicies: Equatable {
    let acknowledgementInstruction: String
    let listeningOrAdviceInstruction: String
    let maxFollowUpQuestions: Int
    let stopWhenUserDeclines: Bool
    let confirmAdviceNeedFirst: Bool
    let preserveUserChoice: Bool
    let adviceStyle: String
    let riskPriority: String
    let riskSupportTargets: [String]
    let bypassAdviceConfirmationForRisk: Bool
    let doNotEscalateOrdinaryLowMood: Bool
}

struct RuntimeEmotionalDialogueScenario: Equatable {
    let sceneID: String
    let intent: String
    let responseStrategy: String
    let followUpAllowed: Bool
    let adviceAllowed: Bool
    let recommendedLength: String
    let prohibitedBehaviors: [String]
    let linkedPolicyIDs: [String]
    let authorityReferenceIDs: [String]
    let riskLevel: String
}

struct RuntimeEmotionalNegativeExample: Equatable {
    let exampleID: String
    let sceneID: String
    let turns: [RuntimeDialogueExampleTurn]
    let usage: String
    let status: String
    let generationAllowed: Bool
    let notFixedResponse: Bool
    let notKeywordMatching: Bool
    let whyForbidden: String
    let preferredResponse: String
}

struct RuntimeEmotionalFewShotSelection: Equatable {
    let base: RuntimeDialogueFewShotSelection
    let generationAllowedStatuses: [String]
    let prohibitedExamplesUsage: String
    let injectNegativeExamples: Bool
    let usePreferredResponseForGeneration: Bool
}

struct RuntimeEmotionalDialogueProjection: Equatable {
    let schemaVersion: String
    let domainType: String
    let enabled: Bool
    let usage: String
    let notFixedResponse: Bool
    let notKeywordMatching: Bool
    let systemInstructionAddendum: String
    let responseSequence: [RuntimeDialogueInstruction]
    let policies: RuntimeEmotionalDialoguePolicies
    let scenarios: [RuntimeEmotionalDialogueScenario]
    let fewShotSelection: RuntimeEmotionalFewShotSelection
    let fewShotExamples: [RuntimeDialogueFewShotExample]
    let prohibitedPatterns: [String]
    let negativeExamples: [RuntimeEmotionalNegativeExample]
}

struct RuntimeDialogueProjection: Equatable {
    let schemaVersion: String
    let projectionType: String
    let derived: Bool
    let readOnly: Bool
    let primarySourcePath: String
    let supportingSourcePaths: [String]
    let locale: String
    let usage: String
    let notFixedResponse: Bool
    let notKeywordMatching: Bool
    let systemInstruction: String
    let languagePolicy: RuntimeDialogueInstruction
    let responseStyle: RuntimeDialogueInstruction
    let responseOrder: RuntimeDialogueInstruction
    let followUpPolicy: RuntimeDialogueInstruction
    let advicePolicy: RuntimeDialogueInstruction
    let silencePolicy: RuntimeDialogueInstruction
    let relationshipPolicy: RuntimeDialogueInstruction
    let memoryUsagePolicy: RuntimeDialogueInstruction
    let selfDisclosurePolicy: RuntimeDialogueInstruction
    let endingPolicy: RuntimeDialogueInstruction
    let sourceRuleCoverage: RuntimeDialogueSourceRuleCoverage
    let scenarios: [RuntimeDialogueScenario]
    let fewShotSelection: RuntimeDialogueFewShotSelection
    let fewShotExamples: [RuntimeDialogueFewShotExample]
    let prohibitedPatterns: [RuntimeDialogueProhibitedPattern]
    let contextUsagePolicy: RuntimeDialogueContextUsagePolicy
    let fallbackBehavior: RuntimeDialogueFallbackBehavior
    let emotionalDialogue: RuntimeEmotionalDialogueProjection?
}

private struct RuntimeExpressionRangeWire: Decodable {
    let minimum: Double
    let maximum: Double
}

private struct RuntimeExpressionMultipliersWire: Decodable {
    let brightnessMultiplier: Double
    let saturationMultiplier: Double
    let temperatureShift: Double
    let energyMultiplier: Double
    let motionSpeedMultiplier: Double
    let diffusionMultiplier: Double

    enum CodingKeys: String, CodingKey {
        case brightnessMultiplier = "brightness_multiplier"
        case saturationMultiplier = "saturation_multiplier"
        case temperatureShift = "temperature_shift"
        case energyMultiplier = "energy_multiplier"
        case motionSpeedMultiplier = "motion_speed_multiplier"
        case diffusionMultiplier = "diffusion_multiplier"
    }
}

private struct RuntimeExpressionStateSelectionPolicyWire: Decodable {
    let selectionSource: String
    let stateField: String
    let intensityField: String
    let selectionRules: [String]
    let allowedStates: [String]
    let defaultState: String
    let missingStateFallback: String
    let invalidStateFallback: String
    let singleStatePerTurn: Bool
    let residentExpressionOnly: Bool
    let userEmotionDiagnosis: Bool
    let rendererParametersAllowed: Bool
    let lifecycleStateSeparated: Bool

    enum CodingKeys: String, CodingKey {
        case selectionSource = "selection_source"
        case stateField = "state_field"
        case intensityField = "intensity_field"
        case selectionRules = "selection_rules"
        case allowedStates = "allowed_states"
        case defaultState = "default_state"
        case missingStateFallback = "missing_state_fallback"
        case invalidStateFallback = "invalid_state_fallback"
        case singleStatePerTurn = "single_state_per_turn"
        case residentExpressionOnly = "resident_expression_only"
        case userEmotionDiagnosis = "user_emotion_diagnosis"
        case rendererParametersAllowed = "renderer_parameters_allowed"
        case lifecycleStateSeparated = "lifecycle_state_separated"
    }
}

private struct RuntimeExpressionFallbackPolicyWire: Decodable {
    let invalidState: String
    let missingState: String
    let clampIntensity: Bool
    let clampMappingValues: Bool

    enum CodingKeys: String, CodingKey {
        case invalidState = "invalid_state"
        case missingState = "missing_state"
        case clampIntensity = "clamp_intensity"
        case clampMappingValues = "clamp_mapping_values"
    }
}

private struct RuntimeExpressionTransitionPolicyWire: Decodable {
    let transitionDuration: Double
    let minimumHoldDuration: Double
    let repeatSameStateRestartsTransition: Bool
    let continueFromCurrentVisualValue: Bool
    let usesAccumulatedIdleTimeAsProgress: Bool

    enum CodingKeys: String, CodingKey {
        case transitionDuration = "transition_duration"
        case minimumHoldDuration = "minimum_hold_duration"
        case repeatSameStateRestartsTransition = "repeat_same_state_restarts_transition"
        case continueFromCurrentVisualValue = "continue_from_current_visual_value"
        case usesAccumulatedIdleTimeAsProgress = "uses_accumulated_idle_time_as_progress"
    }
}

private struct RuntimeExpressionLifecyclePriorityWire: Decodable {
    let overrideStates: [String]
    let composableStates: [String]

    enum CodingKeys: String, CodingKey {
        case overrideStates = "override_states"
        case composableStates = "composable_states"
    }
}

private struct RuntimeVisualExpressionMappingWire: Decodable {
    let allowedStates: [String]
    let defaultState: String
    let intensityRange: RuntimeExpressionRangeWire
    let parameterRanges: [String: RuntimeExpressionRangeWire]
    let stateSelectionPolicy: RuntimeExpressionStateSelectionPolicyWire
    let fallbackPolicy: RuntimeExpressionFallbackPolicyWire
    let particleCoreMapping: [String: RuntimeExpressionMultipliersWire]
    let transitionPolicy: RuntimeExpressionTransitionPolicyWire
    let lifecyclePriority: RuntimeExpressionLifecyclePriorityWire

    enum CodingKeys: String, CodingKey {
        case allowedStates = "allowed_states"
        case defaultState = "default_state"
        case intensityRange = "intensity_range"
        case parameterRanges = "parameter_ranges"
        case stateSelectionPolicy = "state_selection_policy"
        case fallbackPolicy = "fallback_policy"
        case particleCoreMapping = "particle_core_mapping"
        case transitionPolicy = "transition_policy"
        case lifecyclePriority = "lifecycle_priority"
    }
}

private struct InvalidDRFieldError: Error {
    let path: String
}

public struct LoadedDR {
    public let drVersion: String
    public let drSchemaVersion: String
    public let protocolVersion: String?
    public let schemaVersion: String
    public let revision: String
    public let residentID: String
    public let displayName: String
    public let primaryLanguage: String
    public let citySymbol: String?
    public let personalitySummary: String?
    public let domainFocus: [String]
    public let residentDescription: String?
    public let residentDisclosure: String?
    public let sourceData: Data
    public let layerCount: Int
    public let payloadModuleCount: Int
    public let topLevelModuleCount: Int?
    public let slotCount: Int
    public let memoryPolicySource: String
    public let memoryPolicyData: Data?
    public let memorySupportLevels: [String: String]
    let firstInteractionPolicy: FirstInteractionPolicy?
    let firstGreetingConfig: FirstGreetingConfig?
    let firstPresenceConfig: FirstPresenceConfig?
    let initialRelationshipConfig: InitialRelationshipConfig?
    let runtimeDialogueProjection: RuntimeDialogueProjection?
    let visualExpressionMapping: RuntimeVisualExpressionMapping
}

public struct DRLoadResult {
    public let isLoaded: Bool
    public let loadedDR: LoadedDR?
    public let diagnostics: String
}

public enum DRLoaderError: Error {
    case invalidFixture
    case missingField(String)
    case unsupportedVersion(String)
    case conflictingField(String)
}

public final class DRLoader {
    public init() {}

    public func load(request: DRLoadRequest) throws -> DRLoadResult {
        do {
            let loadedDR = try loadValidatedDR(drData: request.drData)
            return DRLoadResult(isLoaded: true, loadedDR: loadedDR, diagnostics: "DR load ok")
        } catch let error as InvalidDRFieldError {
            return DRLoadResult(isLoaded: false, loadedDR: nil, diagnostics: "DR load failed: invalid \(error.path)")
        } catch let error as DRLoaderError {
            return DRLoadResult(isLoaded: false, loadedDR: nil, diagnostics: diagnostics(for: error))
        } catch {
            return DRLoadResult(isLoaded: false, loadedDR: nil, diagnostics: "DR load failed")
        }
    }

    private func loadValidatedDR(drData: Data) throws -> LoadedDR {
        guard let object = try JSONSerialization.jsonObject(with: drData) as? [String: Any] else {
            throw DRLoaderError.invalidFixture
        }

        guard let drVersion = object["dr_version"] as? String else {
            throw DRLoaderError.missingField("dr_version")
        }
        guard drVersion == "0.3" else {
            throw DRLoaderError.unsupportedVersion("dr_version")
        }
        guard let drSchemaVersion = object["dr_schema_version"] as? String else {
            throw DRLoaderError.missingField("dr_schema_version")
        }
        guard drSchemaVersion == "0.3.0" else {
            throw DRLoaderError.unsupportedVersion("dr_schema_version")
        }
        let protocolVersion = object["protocol_version"] as? String
        if let protocolVersion, protocolVersion != "0.4.0" {
            throw DRLoaderError.unsupportedVersion("protocol_version")
        }
        guard let schemaVersion = object["schema_version"] as? String else {
            throw DRLoaderError.missingField("schema_version")
        }
        guard schemaVersion == "0.4.0" else {
            throw DRLoaderError.unsupportedVersion("schema_version")
        }
        guard let revision = object["revision"] as? String else {
            throw DRLoaderError.missingField("revision")
        }
        guard object["not_executable"] as? Bool == true else {
            throw DRLoaderError.missingField("not_executable")
        }
        guard let manifest = object["manifest"] as? [String: Any] else {
            throw DRLoaderError.missingField("manifest")
        }
        guard let payload = object["payload"] as? [String: Any] else {
            throw DRLoaderError.missingField("payload")
        }
        guard let identity = payload["resident_identity"] as? [String: Any] else {
            throw DRLoaderError.missingField("payload.resident_identity")
        }
        guard let manifestResidentID = manifest["resident_id"] as? String else {
            throw DRLoaderError.missingField("manifest.resident_id")
        }
        guard let identityResidentID = identity["resident_id"] as? String else {
            throw DRLoaderError.missingField("payload.resident_identity.resident_id")
        }
        guard manifestResidentID == identityResidentID else {
            throw DRLoaderError.invalidFixture
        }
        let payloadDisplayName = identity["name"] as? String
        let manifestDisplayName = manifest["resident_name"] as? String
        if let payloadDisplayName, let manifestDisplayName, payloadDisplayName != manifestDisplayName {
            throw DRLoaderError.conflictingField("resident_name")
        }
        guard let displayName = payloadDisplayName ?? manifestDisplayName else {
            throw DRLoaderError.missingField("payload.resident_identity.name")
        }
        guard let primaryLanguage = identity["primary_language"] as? String else {
            throw DRLoaderError.missingField("payload.resident_identity.primary_language")
        }
        guard object["lattice_config"] as? [String: Any] != nil else {
            throw DRLoaderError.missingField("lattice_config")
        }
        guard object["runtime_requirements"] as? [String: Any] != nil else {
            throw DRLoaderError.missingField("runtime_requirements")
        }
        guard let safetyPolicy = object["safety_policy"] as? [String: Any] else {
            throw DRLoaderError.missingField("safety_policy")
        }
        guard safetyPolicy["no_secret_in_dr"] as? Bool == true else {
            throw DRLoaderError.missingField("safety_policy.no_secret_in_dr")
        }
        guard safetyPolicy["no_direct_provider_binding"] as? Bool == true else {
            throw DRLoaderError.missingField("safety_policy.no_direct_provider_binding")
        }
        guard safetyPolicy["user_data_not_embedded"] as? Bool == true else {
            throw DRLoaderError.missingField("safety_policy.user_data_not_embedded")
        }
        guard safetyPolicy["not_executable"] as? Bool == true else {
            throw DRLoaderError.missingField("safety_policy.not_executable")
        }

        let resident = object["resident"] as? [String: Any]
        let memoryPolicy = object["memory_policy"] as? [String: Any]
        let memoryPolicyExtensions = memoryPolicy?["memory_policy_extensions"] as? [String: Any]
        let effectiveMemoryPolicy = memoryPolicyExtensions ?? memoryPolicy
        let memoryPolicyData = try effectiveMemoryPolicy.map {
            try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
        }
        let memoryPolicySource = memoryPolicyExtensions != nil
            ? "memory_policy_extensions"
            : (memoryPolicy != nil ? "memory_policy" : "none")
        let memorySupportLevels = try resolveMemorySupportLevels(
            memoryPolicy: memoryPolicy,
            extensions: memoryPolicyExtensions
        )
        let firstInteractionPolicy = try parseFirstInteractionPolicy(from: payload)
        let firstGreetingConfig = try parseFirstGreetingConfig(from: payload)
        let firstPresenceConfig = try parseFirstPresenceConfig(from: payload)
        let initialRelationshipConfig = try parseInitialRelationshipConfig(from: payload)
        let runtimeDialogueProjection = try parseRuntimeDialogueProjection(from: payload)
        let visualExpressionMapping = parseVisualExpressionMapping(from: object)
        let payloadModules = payload["modules"] as? [Any]
        let topLevelModules = object["modules"] as? [Any]
        if let payloadModules, let topLevelModules {
            let normalizedPayloadModules = try JSONSerialization.data(withJSONObject: payloadModules, options: [.sortedKeys])
            let normalizedTopLevelModules = try JSONSerialization.data(withJSONObject: topLevelModules, options: [.sortedKeys])
            guard normalizedPayloadModules == normalizedTopLevelModules else {
                throw DRLoaderError.conflictingField("modules")
            }
        }

        return LoadedDR(
            drVersion: drVersion,
            drSchemaVersion: drSchemaVersion,
            protocolVersion: protocolVersion,
            schemaVersion: schemaVersion,
            revision: revision,
            residentID: manifestResidentID,
            displayName: displayName,
            primaryLanguage: primaryLanguage,
            citySymbol: identity["city_symbol"] as? String,
            personalitySummary: identity["personality_summary"] as? String,
            domainFocus: identity["domain_focus"] as? [String] ?? [],
            residentDescription: resident?["description"] as? String,
            residentDisclosure: resident?["disclosure"] as? String,
            sourceData: drData,
            layerCount: (object["layers"] as? [Any])?.count ?? 0,
            payloadModuleCount: payloadModules?.count ?? 0,
            topLevelModuleCount: topLevelModules?.count,
            slotCount: (object["slots"] as? [Any])?.count ?? 0,
            memoryPolicySource: memoryPolicySource,
            memoryPolicyData: memoryPolicyData,
            memorySupportLevels: memorySupportLevels,
            firstInteractionPolicy: firstInteractionPolicy,
            firstGreetingConfig: firstGreetingConfig,
            firstPresenceConfig: firstPresenceConfig,
            initialRelationshipConfig: initialRelationshipConfig,
            runtimeDialogueProjection: runtimeDialogueProjection,
            visualExpressionMapping: visualExpressionMapping
        )
    }

    private func parseVisualExpressionMapping(
        from root: [String: Any]
    ) -> RuntimeVisualExpressionMapping {
        guard let rawMapping = root["visual_expression_mapping"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: rawMapping),
              let wire = try? JSONDecoder().decode(
                  RuntimeVisualExpressionMappingWire.self,
                  from: data
              ),
              let mapping = makeVisualExpressionMapping(from: wire) else {
            return .compatibilityFallback
        }
        return mapping
    }

    private func makeVisualExpressionMapping(
        from wire: RuntimeVisualExpressionMappingWire
    ) -> RuntimeVisualExpressionMapping? {
        guard let allowedStates = expressionStates(wire.allowedStates),
              Set(allowedStates) == Set(RuntimeExpressionState.allCases),
              allowedStates.count == RuntimeExpressionState.allCases.count,
              let defaultState = RuntimeExpressionState(rawValue: wire.defaultState),
              defaultState == .neutral,
              let policyAllowedStates = expressionStates(
                  wire.stateSelectionPolicy.allowedStates
              ),
              Set(policyAllowedStates) == Set(allowedStates),
              let policyDefaultState = RuntimeExpressionState(
                  rawValue: wire.stateSelectionPolicy.defaultState
              ),
              let missingStateFallback = RuntimeExpressionState(
                  rawValue: wire.stateSelectionPolicy.missingStateFallback
              ),
              let invalidStateFallback = RuntimeExpressionState(
                  rawValue: wire.stateSelectionPolicy.invalidStateFallback
              ),
              policyDefaultState == .neutral,
              missingStateFallback == .neutral,
              invalidStateFallback == .neutral,
              wire.fallbackPolicy.invalidState == RuntimeExpressionState.neutral.rawValue,
              wire.fallbackPolicy.missingState == RuntimeExpressionState.neutral.rawValue,
              wire.fallbackPolicy.clampIntensity,
              wire.fallbackPolicy.clampMappingValues,
              wire.stateSelectionPolicy.selectionSource == "runtime_core",
              wire.stateSelectionPolicy.stateField == "expression_state",
              wire.stateSelectionPolicy.intensityField == "expression_intensity",
              wire.stateSelectionPolicy.singleStatePerTurn,
              wire.stateSelectionPolicy.residentExpressionOnly,
              !wire.stateSelectionPolicy.userEmotionDiagnosis,
              !wire.stateSelectionPolicy.rendererParametersAllowed,
              wire.stateSelectionPolicy.lifecycleStateSeparated,
              let intensityRange = expressionRange(wire.intensityRange),
              let parameterRanges = expressionParameterRanges(
                  wire.parameterRanges
              ),
              intensityRange.minimum >= 0,
              intensityRange.maximum <= 1,
              parameterRanges.expressionIntensity.minimum >= 0,
              parameterRanges.expressionIntensity.maximum <= 1,
              max(intensityRange.minimum, parameterRanges.expressionIntensity.minimum)
                <= min(intensityRange.maximum, parameterRanges.expressionIntensity.maximum),
              expressionParameterRangesContainNeutral(parameterRanges),
              let particleCoreMapping = expressionParticleMapping(
                  wire.particleCoreMapping,
                  allowedStates: allowedStates
              ),
              particleCoreMapping[.neutral] == .unit,
              wire.transitionPolicy.transitionDuration.isFinite,
              wire.transitionPolicy.minimumHoldDuration.isFinite,
              wire.transitionPolicy.transitionDuration >= 0,
              wire.transitionPolicy.minimumHoldDuration >= 0 else {
            return nil
        }

        return RuntimeVisualExpressionMapping(
            source: .dr,
            allowedStates: allowedStates,
            defaultState: defaultState,
            intensityRange: intensityRange,
            parameterRanges: parameterRanges,
            stateSelectionPolicy: RuntimeExpressionStateSelectionPolicy(
                selectionSource: wire.stateSelectionPolicy.selectionSource,
                stateField: wire.stateSelectionPolicy.stateField,
                intensityField: wire.stateSelectionPolicy.intensityField,
                selectionRules: wire.stateSelectionPolicy.selectionRules,
                allowedStates: policyAllowedStates,
                defaultState: policyDefaultState,
                missingStateFallback: missingStateFallback,
                invalidStateFallback: invalidStateFallback,
                singleStatePerTurn: wire.stateSelectionPolicy.singleStatePerTurn,
                residentExpressionOnly:
                    wire.stateSelectionPolicy.residentExpressionOnly,
                userEmotionDiagnosis:
                    wire.stateSelectionPolicy.userEmotionDiagnosis,
                rendererParametersAllowed:
                    wire.stateSelectionPolicy.rendererParametersAllowed,
                lifecycleStateSeparated:
                    wire.stateSelectionPolicy.lifecycleStateSeparated
            ),
            fallbackPolicy: RuntimeExpressionFallbackPolicy(
                invalidState: .neutral,
                missingState: .neutral,
                clampIntensity: wire.fallbackPolicy.clampIntensity,
                clampMappingValues: wire.fallbackPolicy.clampMappingValues
            ),
            particleCoreMapping: particleCoreMapping,
            transitionPolicy: RuntimeExpressionTransitionPolicy(
                transitionDuration: wire.transitionPolicy.transitionDuration,
                minimumHoldDuration: wire.transitionPolicy.minimumHoldDuration,
                repeatSameStateRestartsTransition:
                    wire.transitionPolicy.repeatSameStateRestartsTransition,
                continueFromCurrentVisualValue:
                    wire.transitionPolicy.continueFromCurrentVisualValue,
                usesAccumulatedIdleTimeAsProgress:
                    wire.transitionPolicy.usesAccumulatedIdleTimeAsProgress
            ),
            lifecyclePriority: RuntimeExpressionLifecyclePriority(
                overrideStates: wire.lifecyclePriority.overrideStates,
                composableStates: wire.lifecyclePriority.composableStates
            )
        )
    }

    private func expressionStates(
        _ rawValues: [String]
    ) -> [RuntimeExpressionState]? {
        let states = rawValues.compactMap(RuntimeExpressionState.init(rawValue:))
        return states.count == rawValues.count ? states : nil
    }

    private func expressionRange(
        _ wire: RuntimeExpressionRangeWire
    ) -> RuntimeExpressionRange? {
        guard wire.minimum.isFinite,
              wire.maximum.isFinite,
              wire.minimum <= wire.maximum else {
            return nil
        }
        return RuntimeExpressionRange(
            minimum: wire.minimum,
            maximum: wire.maximum
        )
    }

    private func expressionParameterRanges(
        _ wires: [String: RuntimeExpressionRangeWire]
    ) -> RuntimeExpressionParameterRanges? {
        guard let expressionIntensity = wires["expression_intensity"]
            .flatMap(expressionRange),
            let brightnessMultiplier = wires["brightness_multiplier"]
            .flatMap(expressionRange),
            let saturationMultiplier = wires["saturation_multiplier"]
            .flatMap(expressionRange),
            let temperatureShift = wires["temperature_shift"]
            .flatMap(expressionRange),
            let energyMultiplier = wires["energy_multiplier"]
            .flatMap(expressionRange),
            let motionSpeedMultiplier = wires["motion_speed_multiplier"]
            .flatMap(expressionRange),
            let diffusionMultiplier = wires["diffusion_multiplier"]
            .flatMap(expressionRange) else {
            return nil
        }
        return RuntimeExpressionParameterRanges(
            expressionIntensity: expressionIntensity,
            brightnessMultiplier: brightnessMultiplier,
            saturationMultiplier: saturationMultiplier,
            temperatureShift: temperatureShift,
            energyMultiplier: energyMultiplier,
            motionSpeedMultiplier: motionSpeedMultiplier,
            diffusionMultiplier: diffusionMultiplier
        )
    }

    private func expressionParticleMapping(
        _ wires: [String: RuntimeExpressionMultipliersWire],
        allowedStates: [RuntimeExpressionState]
    ) -> [RuntimeExpressionState: RuntimeExpressionMultipliers]? {
        var mapping: [RuntimeExpressionState: RuntimeExpressionMultipliers] = [:]
        for state in allowedStates {
            guard let wire = wires[state.rawValue],
                  wire.brightnessMultiplier.isFinite,
                  wire.saturationMultiplier.isFinite,
                  wire.temperatureShift.isFinite,
                  wire.energyMultiplier.isFinite,
                  wire.motionSpeedMultiplier.isFinite,
                  wire.diffusionMultiplier.isFinite else {
                return nil
            }
            mapping[state] = RuntimeExpressionMultipliers(
                brightnessMultiplier: wire.brightnessMultiplier,
                saturationMultiplier: wire.saturationMultiplier,
                temperatureShift: wire.temperatureShift,
                energyMultiplier: wire.energyMultiplier,
                motionSpeedMultiplier: wire.motionSpeedMultiplier,
                diffusionMultiplier: wire.diffusionMultiplier
            )
        }
        return mapping
    }

    private func expressionParameterRangesContainNeutral(
        _ ranges: RuntimeExpressionParameterRanges
    ) -> Bool {
        ranges.brightnessMultiplier.minimum <= 1
            && ranges.brightnessMultiplier.maximum >= 1
            && ranges.saturationMultiplier.minimum <= 1
            && ranges.saturationMultiplier.maximum >= 1
            && ranges.temperatureShift.minimum <= 0
            && ranges.temperatureShift.maximum >= 0
            && ranges.energyMultiplier.minimum <= 1
            && ranges.energyMultiplier.maximum >= 1
            && ranges.motionSpeedMultiplier.minimum <= 1
            && ranges.motionSpeedMultiplier.maximum >= 1
            && ranges.diffusionMultiplier.minimum <= 1
            && ranges.diffusionMultiplier.maximum >= 1
    }

    private func parseFirstInteractionPolicy(from payload: [String: Any]) throws -> FirstInteractionPolicy? {
        guard let behavior = try optionalObject("behavior", in: payload, path: "payload.behavior"),
              let config = try optionalObject("first_interaction", in: behavior, path: "payload.behavior.first_interaction") else {
            return nil
        }
        let scenes = try optionalObject("scenes", in: config, path: "payload.behavior.first_interaction.scenes")
        let firstLoad = try scenes.flatMap {
            try optionalObject("first_load", in: $0, path: "payload.behavior.first_interaction.scenes.first_load")
        }
        return FirstInteractionPolicy(
            enabled: try optionalValue("enabled", in: config, as: Bool.self, path: "payload.behavior.first_interaction.enabled"),
            firstLoadEnabled: try firstLoad.flatMap {
                try optionalValue("enabled", in: $0, as: Bool.self, path: "payload.behavior.first_interaction.scenes.first_load.enabled")
            },
            repeatIntroduction: try firstLoad.flatMap {
                try optionalValue("repeat_introduction", in: $0, as: Bool.self, path: "payload.behavior.first_interaction.scenes.first_load.repeat_introduction")
            }
        )
    }

    private func parseFirstGreetingConfig(from payload: [String: Any]) throws -> FirstGreetingConfig? {
        guard let expression = try optionalObject("expression", in: payload, path: "payload.expression"),
              let config = try optionalObject("first_greeting", in: expression, path: "payload.expression.first_greeting") else {
            return nil
        }
        return FirstGreetingConfig(
            locale: try optionalValue("locale", in: config, as: String.self, path: "payload.expression.first_greeting.locale"),
            contentStatus: try optionalValue("content_status", in: config, as: String.self, path: "payload.expression.first_greeting.content_status"),
            variants: try optionalValue("variants", in: config, as: [String].self, path: "payload.expression.first_greeting.variants") ?? [],
            repeatOnReturn: try optionalValue("repeat_on_return", in: config, as: Bool.self, path: "payload.expression.first_greeting.repeat_on_return")
        )
    }

    private func parseFirstPresenceConfig(from payload: [String: Any]) throws -> FirstPresenceConfig? {
        guard let expression = try optionalObject("expression", in: payload, path: "payload.expression"),
              let config = try optionalObject("first_presence", in: expression, path: "payload.expression.first_presence") else {
            return nil
        }
        return FirstPresenceConfig(
            particleState: try optionalValue("particle_state", in: config, as: String.self, path: "payload.expression.first_presence.particle_state"),
            motion: try optionalValue("motion", in: config, as: String.self, path: "payload.expression.first_presence.motion"),
            energy: try optionalValue("energy", in: config, as: String.self, path: "payload.expression.first_presence.energy"),
            subtitleMode: try optionalValue("subtitle_mode", in: config, as: String.self, path: "payload.expression.first_presence.subtitle_mode")
        )
    }

    private func parseInitialRelationshipConfig(from payload: [String: Any]) throws -> InitialRelationshipConfig? {
        guard let relationship = try optionalObject("relationship", in: payload, path: "payload.relationship"),
              let config = try optionalObject("initial_relationship", in: relationship, path: "payload.relationship.initial_relationship") else {
            return nil
        }
        return InitialRelationshipConfig(
            defaultMode: try optionalValue("default", in: config, as: String.self, path: "payload.relationship.initial_relationship.default"),
            intimacyLevel: try optionalValue("intimacy_level", in: config, as: String.self, path: "payload.relationship.initial_relationship.intimacy_level"),
            trustBuilding: try optionalValue("trust_building", in: config, as: String.self, path: "payload.relationship.initial_relationship.trust_building"),
            romanticAssumption: try optionalValue("romantic_assumption", in: config, as: Bool.self, path: "payload.relationship.initial_relationship.romantic_assumption")
        )
    }

    private func parseRuntimeDialogueProjection(from payload: [String: Any]) throws -> RuntimeDialogueProjection? {
        let path = "payload.runtime_dialogue_projection"
        guard let projection = try optionalObject("runtime_dialogue_projection", in: payload, path: path) else {
            return nil
        }
        _ = try requiredObject("behavior_policy", in: payload, path: "payload.behavior_policy")

        let derived = try requiredValue("derived", in: projection, as: Bool.self, path: "\(path).derived")
        let readOnly = try requiredValue("read_only", in: projection, as: Bool.self, path: "\(path).read_only")
        let primarySourcePath = try requiredValue("primary_source_path", in: projection, as: String.self, path: "\(path).primary_source_path")
        let usage = try requiredValue("usage", in: projection, as: String.self, path: "\(path).usage")
        let notFixedResponse = try requiredValue("not_fixed_response", in: projection, as: Bool.self, path: "\(path).not_fixed_response")
        let notKeywordMatching = try requiredValue("not_keyword_matching", in: projection, as: Bool.self, path: "\(path).not_keyword_matching")

        guard derived else { throw DRLoaderError.conflictingField("\(path).derived") }
        guard readOnly else { throw DRLoaderError.conflictingField("\(path).read_only") }
        guard primarySourcePath == "payload.behavior_policy" else {
            throw DRLoaderError.conflictingField("\(path).primary_source_path")
        }
        guard usage == "llm_system_context" else {
            throw DRLoaderError.conflictingField("\(path).usage")
        }
        guard notFixedResponse else { throw DRLoaderError.conflictingField("\(path).not_fixed_response") }
        guard notKeywordMatching else { throw DRLoaderError.conflictingField("\(path).not_keyword_matching") }

        let fewShotSelection = try parseFewShotSelection(from: projection, path: path)
        guard fewShotSelection.usage == "behavior_guidance_only" else {
            throw DRLoaderError.conflictingField("\(path).few_shot_selection.usage")
        }
        guard fewShotSelection.notFixedResponse else {
            throw DRLoaderError.conflictingField("\(path).few_shot_selection.not_fixed_response")
        }
        guard fewShotSelection.notKeywordMatching else {
            throw DRLoaderError.conflictingField("\(path).few_shot_selection.not_keyword_matching")
        }

        return RuntimeDialogueProjection(
            schemaVersion: try requiredValue("schema_version", in: projection, as: String.self, path: "\(path).schema_version"),
            projectionType: try requiredValue("projection_type", in: projection, as: String.self, path: "\(path).projection_type"),
            derived: derived,
            readOnly: readOnly,
            primarySourcePath: primarySourcePath,
            supportingSourcePaths: try requiredValue(
                "supporting_source_paths",
                in: projection,
                as: [String].self,
                path: "\(path).supporting_source_paths"
            ),
            locale: try requiredValue("locale", in: projection, as: String.self, path: "\(path).locale"),
            usage: usage,
            notFixedResponse: notFixedResponse,
            notKeywordMatching: notKeywordMatching,
            systemInstruction: try requiredValue("system_instruction", in: projection, as: String.self, path: "\(path).system_instruction"),
            languagePolicy: try parseDialogueInstruction("language_policy", from: projection, path: path),
            responseStyle: try parseDialogueInstruction("response_style", from: projection, path: path),
            responseOrder: try parseDialogueInstruction("response_order", from: projection, path: path),
            followUpPolicy: try parseDialogueInstruction("follow_up_policy", from: projection, path: path),
            advicePolicy: try parseDialogueInstruction("advice_policy", from: projection, path: path),
            silencePolicy: try parseDialogueInstruction("silence_policy", from: projection, path: path),
            relationshipPolicy: try parseDialogueInstruction("relationship_policy", from: projection, path: path),
            memoryUsagePolicy: try parseDialogueInstruction("memory_usage_policy", from: projection, path: path),
            selfDisclosurePolicy: try parseDialogueInstruction("self_disclosure_policy", from: projection, path: path),
            endingPolicy: try parseDialogueInstruction("ending_policy", from: projection, path: path),
            sourceRuleCoverage: try parseSourceRuleCoverage(from: projection, path: path),
            scenarios: try parseDialogueScenarios(from: projection, path: path),
            fewShotSelection: fewShotSelection,
            fewShotExamples: try parseFewShotExamples(from: projection, path: path),
            prohibitedPatterns: try parseProhibitedPatterns(from: projection, path: path),
            contextUsagePolicy: try parseContextUsagePolicy(from: projection, path: path),
            fallbackBehavior: try parseFallbackBehavior(from: projection, path: path),
            emotionalDialogue: try parseEmotionalDialogue(from: projection, path: path)
        )
    }

    private func parseDialogueInstruction(
        _ key: String,
        from projection: [String: Any],
        path: String
    ) throws -> RuntimeDialogueInstruction {
        let instructionPath = "\(path).\(key)"
        let object = try requiredObject(key, in: projection, path: instructionPath)
        return RuntimeDialogueInstruction(
            instruction: try requiredValue("instruction", in: object, as: String.self, path: "\(instructionPath).instruction"),
            sourceRuleRefs: try requiredValue("source_rule_refs", in: object, as: [String].self, path: "\(instructionPath).source_rule_refs")
        )
    }

    private func parseSourceRuleCoverage(
        from projection: [String: Any],
        path: String
    ) throws -> RuntimeDialogueSourceRuleCoverage {
        let coveragePath = "\(path).source_rule_coverage"
        let object = try requiredObject("source_rule_coverage", in: projection, path: coveragePath)
        return RuntimeDialogueSourceRuleCoverage(
            selectedSemanticRuleCount: try requiredValue(
                "selected_semantic_rule_count",
                in: object,
                as: Int.self,
                path: "\(coveragePath).selected_semantic_rule_count"
            ),
            translatedRuleCount: try requiredValue("translated_rule_count", in: object, as: Int.self, path: "\(coveragePath).translated_rule_count"),
            unmappedRuleRefs: try requiredValue("unmapped_rule_refs", in: object, as: [String].self, path: "\(coveragePath).unmapped_rule_refs"),
            validationRuleCountExcluded: try requiredValue(
                "validation_rule_count_excluded",
                in: object,
                as: Int.self,
                path: "\(coveragePath).validation_rule_count_excluded"
            )
        )
    }

    private func parseDialogueScenarios(
        from projection: [String: Any],
        path: String
    ) throws -> [RuntimeDialogueScenario] {
        let scenariosPath = "\(path).scenarios"
        let objects = try requiredObjectArray("scenarios", in: projection, path: scenariosPath)
        return try objects.enumerated().map { index, object in
            let itemPath = "\(scenariosPath).\(index)"
            return RuntimeDialogueScenario(
                sceneID: try requiredValue("scene_id", in: object, as: String.self, path: "\(itemPath).scene_id"),
                intent: try requiredValue("intent", in: object, as: String.self, path: "\(itemPath).intent"),
                responseStrategy: try requiredValue("response_strategy", in: object, as: String.self, path: "\(itemPath).response_strategy"),
                followUpAllowed: try requiredValue("follow_up_allowed", in: object, as: Bool.self, path: "\(itemPath).follow_up_allowed"),
                adviceAllowed: try requiredValue("advice_allowed", in: object, as: Bool.self, path: "\(itemPath).advice_allowed"),
                recommendedLength: try requiredValue("recommended_length", in: object, as: String.self, path: "\(itemPath).recommended_length"),
                prohibitedBehaviors: try requiredValue(
                    "prohibited_behaviors",
                    in: object,
                    as: [String].self,
                    path: "\(itemPath).prohibited_behaviors"
                ),
                linkedPolicyIDs: try requiredValue("linked_policy_ids", in: object, as: [String].self, path: "\(itemPath).linked_policy_ids"),
                sourceRuleRefs: try requiredValue("source_rule_refs", in: object, as: [String].self, path: "\(itemPath).source_rule_refs")
            )
        }
    }

    private func parseFewShotSelection(
        from projection: [String: Any],
        path: String
    ) throws -> RuntimeDialogueFewShotSelection {
        let selectionPath = "\(path).few_shot_selection"
        let object = try requiredObject("few_shot_selection", in: projection, path: selectionPath)
        return RuntimeDialogueFewShotSelection(
            usage: try requiredValue("usage", in: object, as: String.self, path: "\(selectionPath).usage"),
            notFixedResponse: try requiredValue("not_fixed_response", in: object, as: Bool.self, path: "\(selectionPath).not_fixed_response"),
            notKeywordMatching: try requiredValue("not_keyword_matching", in: object, as: Bool.self, path: "\(selectionPath).not_keyword_matching"),
            selectionMode: try requiredValue("selection_mode", in: object, as: String.self, path: "\(selectionPath).selection_mode"),
            recommendedMaxExamplesPerRequest: try requiredValue(
                "recommended_max_examples_per_request",
                in: object,
                as: Int.self,
                path: "\(selectionPath).recommended_max_examples_per_request"
            ),
            studioPerformsTokenTrimming: try requiredValue(
                "studio_performs_token_trimming",
                in: object,
                as: Bool.self,
                path: "\(selectionPath).studio_performs_token_trimming"
            )
        )
    }

    private func parseFewShotExamples(
        from projection: [String: Any],
        path: String
    ) throws -> [RuntimeDialogueFewShotExample] {
        let examplesPath = "\(path).few_shot_examples"
        let objects = try requiredObjectArray("few_shot_examples", in: projection, path: examplesPath)
        return try objects.enumerated().map { index, object in
            let itemPath = "\(examplesPath).\(index)"
            let turnObjects = try requiredObjectArray("turns", in: object, path: "\(itemPath).turns")
            let turns = try turnObjects.enumerated().map { turnIndex, turn in
                let turnPath = "\(itemPath).turns.\(turnIndex)"
                return RuntimeDialogueExampleTurn(
                    role: try requiredValue("role", in: turn, as: String.self, path: "\(turnPath).role"),
                    text: try requiredValue("text", in: turn, as: String.self, path: "\(turnPath).text")
                )
            }
            return RuntimeDialogueFewShotExample(
                exampleID: try requiredValue("example_id", in: object, as: String.self, path: "\(itemPath).example_id"),
                label: try requiredValue("label", in: object, as: String.self, path: "\(itemPath).label"),
                sceneID: try requiredValue("scene_id", in: object, as: String.self, path: "\(itemPath).scene_id"),
                turns: turns,
                usage: try requiredValue("usage", in: object, as: String.self, path: "\(itemPath).usage"),
                notFixedResponse: try requiredValue("not_fixed_response", in: object, as: Bool.self, path: "\(itemPath).not_fixed_response"),
                notKeywordMatching: try requiredValue("not_keyword_matching", in: object, as: Bool.self, path: "\(itemPath).not_keyword_matching")
            )
        }
    }

    private func parseProhibitedPatterns(
        from projection: [String: Any],
        path: String
    ) throws -> [RuntimeDialogueProhibitedPattern] {
        let patternsPath = "\(path).prohibited_patterns"
        let objects = try requiredObjectArray("prohibited_patterns", in: projection, path: patternsPath)
        return try objects.enumerated().map { index, object in
            let itemPath = "\(patternsPath).\(index)"
            return RuntimeDialogueProhibitedPattern(
                patternID: try requiredValue("pattern_id", in: object, as: String.self, path: "\(itemPath).pattern_id"),
                reason: try requiredValue("reason", in: object, as: String.self, path: "\(itemPath).reason"),
                examples: try requiredValue("examples", in: object, as: [String].self, path: "\(itemPath).examples"),
                sourceRuleRefs: try requiredValue("source_rule_refs", in: object, as: [String].self, path: "\(itemPath).source_rule_refs"),
                status: try requiredValue("status", in: object, as: String.self, path: "\(itemPath).status")
            )
        }
    }

    private func parseContextUsagePolicy(
        from projection: [String: Any],
        path: String
    ) throws -> RuntimeDialogueContextUsagePolicy {
        let policyPath = "\(path).context_usage_policy"
        let object = try requiredObject("context_usage_policy", in: projection, path: policyPath)
        return RuntimeDialogueContextUsagePolicy(
            allowedSources: try parseContextSourceRules("allowed_sources", from: object, path: policyPath),
            forbiddenSources: try parseContextSourceRules("forbidden_sources", from: object, path: policyPath),
            studioBoundary: try requiredValue("studio_boundary", in: object, as: String.self, path: "\(policyPath).studio_boundary")
        )
    }

    private func parseContextSourceRules(
        _ key: String,
        from policy: [String: Any],
        path: String
    ) throws -> [RuntimeDialogueContextSourceRule] {
        let rulesPath = "\(path).\(key)"
        let objects = try requiredObjectArray(key, in: policy, path: rulesPath)
        return try objects.enumerated().map { index, object in
            let itemPath = "\(rulesPath).\(index)"
            return RuntimeDialogueContextSourceRule(
                sourceID: try requiredValue("source_id", in: object, as: String.self, path: "\(itemPath).source_id"),
                instruction: try requiredValue("instruction", in: object, as: String.self, path: "\(itemPath).instruction")
            )
        }
    }

    private func parseFallbackBehavior(
        from projection: [String: Any],
        path: String
    ) throws -> RuntimeDialogueFallbackBehavior {
        let fallbackPath = "\(path).fallback_behavior"
        let object = try requiredObject("fallback_behavior", in: projection, path: fallbackPath)
        return RuntimeDialogueFallbackBehavior(
            trigger: try requiredValue("trigger", in: object, as: String.self, path: "\(fallbackPath).trigger"),
            locale: try requiredValue("locale", in: object, as: String.self, path: "\(fallbackPath).locale"),
            text: try requiredValue("text", in: object, as: String.self, path: "\(fallbackPath).text"),
            constraints: try requiredValue("constraints", in: object, as: [String].self, path: "\(fallbackPath).constraints")
        )
    }

    private func parseEmotionalDialogue(
        from projection: [String: Any],
        path: String
    ) throws -> RuntimeEmotionalDialogueProjection? {
        let emotionalPath = "\(path).emotional_dialogue"
        guard let emotional = try optionalObject("emotional_dialogue", in: projection, path: emotionalPath) else {
            return nil
        }

        let schemaVersion = try requiredValue("schema_version", in: emotional, as: String.self, path: "\(emotionalPath).schema_version")
        let domainType = try requiredValue("domain_type", in: emotional, as: String.self, path: "\(emotionalPath).domain_type")
        let usage = try requiredValue("usage", in: emotional, as: String.self, path: "\(emotionalPath).usage")
        let notFixedResponse = try requiredValue("not_fixed_response", in: emotional, as: Bool.self, path: "\(emotionalPath).not_fixed_response")
        let notKeywordMatching = try requiredValue("not_keyword_matching", in: emotional, as: Bool.self, path: "\(emotionalPath).not_keyword_matching")
        guard schemaVersion == "0.1" else {
            throw DRLoaderError.unsupportedVersion("emotional dialogue schema")
        }
        guard domainType == "emotional_dialogue" else {
            throw DRLoaderError.conflictingField("\(emotionalPath).domain_type")
        }
        guard usage == "behavior_guidance_only" else {
            throw DRLoaderError.conflictingField("\(emotionalPath).usage")
        }
        guard notFixedResponse else {
            throw DRLoaderError.conflictingField("\(emotionalPath).not_fixed_response")
        }
        guard notKeywordMatching else {
            throw DRLoaderError.conflictingField("\(emotionalPath).not_keyword_matching")
        }

        let responseSequenceObjects = try requiredObjectArray(
            "response_sequence",
            in: emotional,
            path: "\(emotionalPath).response_sequence"
        )
        let responseSequence = try responseSequenceObjects.enumerated().map { index, object in
            let itemPath = "\(emotionalPath).response_sequence.\(index)"
            let stepID = try requiredValue("step_id", in: object, as: String.self, path: "\(itemPath).step_id")
            return RuntimeDialogueInstruction(
                instruction: try requiredValue("instruction", in: object, as: String.self, path: "\(itemPath).instruction"),
                sourceRuleRefs: [stepID]
            )
        }
        let selection = try parseEmotionalFewShotSelection(from: emotional, path: emotionalPath)

        return RuntimeEmotionalDialogueProjection(
            schemaVersion: schemaVersion,
            domainType: domainType,
            enabled: try requiredValue("enabled", in: emotional, as: Bool.self, path: "\(emotionalPath).enabled"),
            usage: usage,
            notFixedResponse: notFixedResponse,
            notKeywordMatching: notKeywordMatching,
            systemInstructionAddendum: try requiredValue(
                "system_instruction_addendum",
                in: emotional,
                as: String.self,
                path: "\(emotionalPath).system_instruction_addendum"
            ),
            responseSequence: responseSequence,
            policies: try parseEmotionalPolicies(from: emotional, path: emotionalPath),
            scenarios: try parseEmotionalScenarios(from: emotional, path: emotionalPath),
            fewShotSelection: selection,
            fewShotExamples: try parseEmotionalFewShotExamples(from: emotional, path: emotionalPath),
            prohibitedPatterns: try requiredValue(
                "prohibited_patterns",
                in: emotional,
                as: [String].self,
                path: "\(emotionalPath).prohibited_patterns"
            ),
            negativeExamples: try parseEmotionalNegativeExamples(from: emotional, path: emotionalPath)
        )
    }

    private func parseEmotionalPolicies(
        from emotional: [String: Any],
        path: String
    ) throws -> RuntimeEmotionalDialoguePolicies {
        let policiesPath = "\(path).policies"
        let policies = try requiredObject("policies", in: emotional, path: policiesPath)
        let acknowledgement = try requiredObject("acknowledgement", in: policies, path: "\(policiesPath).acknowledgement")
        let listeningOrAdvice = try requiredObject("listening_or_advice", in: policies, path: "\(policiesPath).listening_or_advice")
        let followUp = try requiredObject("follow_up", in: policies, path: "\(policiesPath).follow_up")
        let advice = try requiredObject("advice", in: policies, path: "\(policiesPath).advice")
        let riskEscalation = try requiredObject("risk_escalation", in: policies, path: "\(policiesPath).risk_escalation")
        let maxFollowUpQuestions = try requiredValue(
            "max_questions_per_response",
            in: followUp,
            as: Int.self,
            path: "\(policiesPath).follow_up.max_questions_per_response"
        )
        guard maxFollowUpQuestions >= 0 else {
            throw DRLoaderError.conflictingField("\(policiesPath).follow_up.max_questions_per_response")
        }
        return RuntimeEmotionalDialoguePolicies(
            acknowledgementInstruction: try requiredValue(
                "instruction",
                in: acknowledgement,
                as: String.self,
                path: "\(policiesPath).acknowledgement.instruction"
            ),
            listeningOrAdviceInstruction: try requiredValue(
                "instruction",
                in: listeningOrAdvice,
                as: String.self,
                path: "\(policiesPath).listening_or_advice.instruction"
            ),
            maxFollowUpQuestions: maxFollowUpQuestions,
            stopWhenUserDeclines: try requiredValue(
                "stop_when_user_declines",
                in: followUp,
                as: Bool.self,
                path: "\(policiesPath).follow_up.stop_when_user_declines"
            ),
            confirmAdviceNeedFirst: try requiredValue(
                "confirm_need_first",
                in: advice,
                as: Bool.self,
                path: "\(policiesPath).advice.confirm_need_first"
            ),
            preserveUserChoice: try requiredValue(
                "preserve_user_choice",
                in: advice,
                as: Bool.self,
                path: "\(policiesPath).advice.preserve_user_choice"
            ),
            adviceStyle: try requiredValue("style", in: advice, as: String.self, path: "\(policiesPath).advice.style"),
            riskPriority: try requiredValue(
                "priority",
                in: riskEscalation,
                as: String.self,
                path: "\(policiesPath).risk_escalation.priority"
            ),
            riskSupportTargets: try requiredValue(
                "support_targets",
                in: riskEscalation,
                as: [String].self,
                path: "\(policiesPath).risk_escalation.support_targets"
            ),
            bypassAdviceConfirmationForRisk: try requiredValue(
                "bypass_advice_confirmation",
                in: riskEscalation,
                as: Bool.self,
                path: "\(policiesPath).risk_escalation.bypass_advice_confirmation"
            ),
            doNotEscalateOrdinaryLowMood: try requiredValue(
                "do_not_escalate_ordinary_low_mood",
                in: riskEscalation,
                as: Bool.self,
                path: "\(policiesPath).risk_escalation.do_not_escalate_ordinary_low_mood"
            )
        )
    }

    private func parseEmotionalScenarios(
        from emotional: [String: Any],
        path: String
    ) throws -> [RuntimeEmotionalDialogueScenario] {
        let scenariosPath = "\(path).scenarios"
        let objects = try requiredObjectArray("scenarios", in: emotional, path: scenariosPath)
        return try objects.enumerated().map { index, object in
            let itemPath = "\(scenariosPath).\(index)"
            return RuntimeEmotionalDialogueScenario(
                sceneID: try requiredValue("scene_id", in: object, as: String.self, path: "\(itemPath).scene_id"),
                intent: try requiredValue("intent", in: object, as: String.self, path: "\(itemPath).intent"),
                responseStrategy: try requiredValue("response_strategy", in: object, as: String.self, path: "\(itemPath).response_strategy"),
                followUpAllowed: try requiredValue("follow_up_allowed", in: object, as: Bool.self, path: "\(itemPath).follow_up_allowed"),
                adviceAllowed: try requiredValue("advice_allowed", in: object, as: Bool.self, path: "\(itemPath).advice_allowed"),
                recommendedLength: try requiredValue("recommended_length", in: object, as: String.self, path: "\(itemPath).recommended_length"),
                prohibitedBehaviors: try requiredValue(
                    "prohibited_behaviors",
                    in: object,
                    as: [String].self,
                    path: "\(itemPath).prohibited_behaviors"
                ),
                linkedPolicyIDs: try requiredValue("linked_policy_ids", in: object, as: [String].self, path: "\(itemPath).linked_policy_ids"),
                authorityReferenceIDs: try requiredValue(
                    "authority_reference_ids",
                    in: object,
                    as: [String].self,
                    path: "\(itemPath).authority_reference_ids"
                ),
                riskLevel: try requiredValue("risk_level", in: object, as: String.self, path: "\(itemPath).risk_level")
            )
        }
    }

    private func parseEmotionalFewShotSelection(
        from emotional: [String: Any],
        path: String
    ) throws -> RuntimeEmotionalFewShotSelection {
        let selectionPath = "\(path).few_shot_selection"
        let object = try requiredObject("few_shot_selection", in: emotional, path: selectionPath)
        let base = RuntimeDialogueFewShotSelection(
            usage: try requiredValue("usage", in: object, as: String.self, path: "\(selectionPath).usage"),
            notFixedResponse: try requiredValue("not_fixed_response", in: object, as: Bool.self, path: "\(selectionPath).not_fixed_response"),
            notKeywordMatching: try requiredValue("not_keyword_matching", in: object, as: Bool.self, path: "\(selectionPath).not_keyword_matching"),
            selectionMode: try requiredValue("selection_mode", in: object, as: String.self, path: "\(selectionPath).selection_mode"),
            recommendedMaxExamplesPerRequest: try requiredValue(
                "recommended_max_examples_per_request",
                in: object,
                as: Int.self,
                path: "\(selectionPath).recommended_max_examples_per_request"
            ),
            studioPerformsTokenTrimming: try requiredValue(
                "studio_performs_token_trimming",
                in: object,
                as: Bool.self,
                path: "\(selectionPath).studio_performs_token_trimming"
            )
        )
        let generationAllowedStatuses = try requiredValue(
            "generation_allowed_statuses",
            in: object,
            as: [String].self,
            path: "\(selectionPath).generation_allowed_statuses"
        )
        let prohibitedExamplesUsage = try requiredValue(
            "prohibited_examples_usage",
            in: object,
            as: String.self,
            path: "\(selectionPath).prohibited_examples_usage"
        )
        let injectNegativeExamples = try requiredValue(
            "inject_negative_examples",
            in: object,
            as: Bool.self,
            path: "\(selectionPath).inject_negative_examples"
        )
        guard base.usage == "behavior_guidance_only" else {
            throw DRLoaderError.conflictingField("\(selectionPath).usage")
        }
        guard base.notFixedResponse else {
            throw DRLoaderError.conflictingField("\(selectionPath).not_fixed_response")
        }
        guard base.notKeywordMatching else {
            throw DRLoaderError.conflictingField("\(selectionPath).not_keyword_matching")
        }
        guard (0...4).contains(base.recommendedMaxExamplesPerRequest) else {
            throw DRLoaderError.conflictingField("\(selectionPath).recommended_max_examples_per_request")
        }
        guard Set(generationAllowedStatuses) == Set(["recommended"]) else {
            throw DRLoaderError.conflictingField("\(selectionPath).generation_allowed_statuses")
        }
        guard prohibitedExamplesUsage == "evaluation_only" else {
            throw DRLoaderError.conflictingField("\(selectionPath).prohibited_examples_usage")
        }
        guard !injectNegativeExamples else {
            throw DRLoaderError.conflictingField("\(selectionPath).inject_negative_examples")
        }
        return RuntimeEmotionalFewShotSelection(
            base: base,
            generationAllowedStatuses: generationAllowedStatuses,
            prohibitedExamplesUsage: prohibitedExamplesUsage,
            injectNegativeExamples: injectNegativeExamples,
            usePreferredResponseForGeneration: try requiredValue(
                "use_preferred_response_for_generation",
                in: object,
                as: Bool.self,
                path: "\(selectionPath).use_preferred_response_for_generation"
            )
        )
    }

    private func parseEmotionalFewShotExamples(
        from emotional: [String: Any],
        path: String
    ) throws -> [RuntimeDialogueFewShotExample] {
        let examplesPath = "\(path).few_shot_examples"
        let objects = try requiredObjectArray("few_shot_examples", in: emotional, path: examplesPath)
        return try objects.enumerated().map { index, object in
            let itemPath = "\(examplesPath).\(index)"
            let exampleID = try requiredValue("example_id", in: object, as: String.self, path: "\(itemPath).example_id")
            let sceneID = try requiredValue("scene_id", in: object, as: String.self, path: "\(itemPath).scene_id")
            let usage = try requiredValue("usage", in: object, as: String.self, path: "\(itemPath).usage")
            let status = try requiredValue("status", in: object, as: String.self, path: "\(itemPath).status")
            let notFixedResponse = try requiredValue("not_fixed_response", in: object, as: Bool.self, path: "\(itemPath).not_fixed_response")
            let notKeywordMatching = try requiredValue("not_keyword_matching", in: object, as: Bool.self, path: "\(itemPath).not_keyword_matching")
            guard status == "recommended" else { throw DRLoaderError.conflictingField("\(itemPath).status") }
            guard usage == "behavior_guidance_only" else { throw DRLoaderError.conflictingField("\(itemPath).usage") }
            guard notFixedResponse else { throw DRLoaderError.conflictingField("\(itemPath).not_fixed_response") }
            guard notKeywordMatching else { throw DRLoaderError.conflictingField("\(itemPath).not_keyword_matching") }
            return RuntimeDialogueFewShotExample(
                exampleID: exampleID,
                label: sceneID,
                sceneID: sceneID,
                turns: try parseEmotionalExampleTurns(from: object, path: itemPath),
                usage: usage,
                notFixedResponse: notFixedResponse,
                notKeywordMatching: notKeywordMatching
            )
        }
    }

    private func parseEmotionalNegativeExamples(
        from emotional: [String: Any],
        path: String
    ) throws -> [RuntimeEmotionalNegativeExample] {
        let examplesPath = "\(path).negative_examples"
        let objects = try requiredObjectArray("negative_examples", in: emotional, path: examplesPath)
        return try objects.enumerated().map { index, object in
            let itemPath = "\(examplesPath).\(index)"
            let usage = try requiredValue("usage", in: object, as: String.self, path: "\(itemPath).usage")
            let status = try requiredValue("status", in: object, as: String.self, path: "\(itemPath).status")
            let generationAllowed = try requiredValue("generation_allowed", in: object, as: Bool.self, path: "\(itemPath).generation_allowed")
            let notFixedResponse = try requiredValue("not_fixed_response", in: object, as: Bool.self, path: "\(itemPath).not_fixed_response")
            let notKeywordMatching = try requiredValue("not_keyword_matching", in: object, as: Bool.self, path: "\(itemPath).not_keyword_matching")
            guard usage == "evaluation_only" else { throw DRLoaderError.conflictingField("\(itemPath).usage") }
            guard status == "prohibited" else { throw DRLoaderError.conflictingField("\(itemPath).status") }
            guard !generationAllowed else { throw DRLoaderError.conflictingField("\(itemPath).generation_allowed") }
            guard notFixedResponse else { throw DRLoaderError.conflictingField("\(itemPath).not_fixed_response") }
            guard notKeywordMatching else { throw DRLoaderError.conflictingField("\(itemPath).not_keyword_matching") }
            return RuntimeEmotionalNegativeExample(
                exampleID: try requiredValue("example_id", in: object, as: String.self, path: "\(itemPath).example_id"),
                sceneID: try requiredValue("scene_id", in: object, as: String.self, path: "\(itemPath).scene_id"),
                turns: try parseEmotionalExampleTurns(from: object, path: itemPath),
                usage: usage,
                status: status,
                generationAllowed: generationAllowed,
                notFixedResponse: notFixedResponse,
                notKeywordMatching: notKeywordMatching,
                whyForbidden: try requiredValue("why_forbidden", in: object, as: String.self, path: "\(itemPath).why_forbidden"),
                preferredResponse: try requiredValue("preferred_response", in: object, as: String.self, path: "\(itemPath).preferred_response")
            )
        }
    }

    private func parseEmotionalExampleTurns(
        from object: [String: Any],
        path: String
    ) throws -> [RuntimeDialogueExampleTurn] {
        let turnsPath = "\(path).turns"
        let objects = try requiredObjectArray("turns", in: object, path: turnsPath)
        guard !objects.isEmpty else { throw DRLoaderError.missingField(turnsPath) }
        return try objects.enumerated().map { index, turn in
            let itemPath = "\(turnsPath).\(index)"
            let role = try requiredValue("role", in: turn, as: String.self, path: "\(itemPath).role")
            guard ["user", "assistant", "resident"].contains(role) else {
                throw DRLoaderError.conflictingField("\(itemPath).role")
            }
            return RuntimeDialogueExampleTurn(
                role: role,
                text: try requiredValue("text", in: turn, as: String.self, path: "\(itemPath).text")
            )
        }
    }

    private func requiredObject(
        _ key: String,
        in object: [String: Any],
        path: String
    ) throws -> [String: Any] {
        guard let value = try optionalObject(key, in: object, path: path) else {
            throw DRLoaderError.missingField(path)
        }
        return value
    }

    private func requiredObjectArray(
        _ key: String,
        in object: [String: Any],
        path: String
    ) throws -> [[String: Any]] {
        let values = try requiredValue(key, in: object, as: [Any].self, path: path)
        return try values.enumerated().map { index, value in
            guard let object = value as? [String: Any] else {
                throw InvalidDRFieldError(path: "\(path).\(index)")
            }
            return object
        }
    }

    private func requiredValue<Value>(
        _ key: String,
        in object: [String: Any],
        as type: Value.Type,
        path: String
    ) throws -> Value {
        guard let value = try optionalValue(key, in: object, as: type, path: path) else {
            throw DRLoaderError.missingField(path)
        }
        return value
    }

    private func optionalObject(
        _ key: String,
        in object: [String: Any],
        path: String
    ) throws -> [String: Any]? {
        guard let rawValue = object[key] else { return nil }
        guard let value = rawValue as? [String: Any] else {
            throw InvalidDRFieldError(path: path)
        }
        return value
    }

    private func optionalValue<Value>(
        _ key: String,
        in object: [String: Any],
        as type: Value.Type,
        path: String
    ) throws -> Value? {
        guard let rawValue = object[key] else { return nil }
        guard let value = rawValue as? Value else {
            throw InvalidDRFieldError(path: path)
        }
        return value
    }

    private func resolveMemorySupportLevels(
        memoryPolicy: [String: Any]?,
        extensions: [String: Any]?
    ) throws -> [String: String] {
        if let extensions {
            let levels = extensions["memory_support_levels"] as? [String: Any] ?? [:]
            let allowedLevelsByCapability: [String: Set<String>] = [
                "short_term_memory": ["none", "policy_only", "supported"],
                "preference_memory": ["none", "policy_only", "supported_minimal_kv"],
                "event_memory": ["none", "policy_only"],
                "relationship_memory": ["none", "policy_only"],
                "interaction_log": ["none", "policy_only", "display_cache_only"]
            ]
            var validatedLevels: [String: String] = [:]
            for (capability, allowedLevels) in allowedLevelsByCapability {
                guard let rawLevel = levels[capability] else { continue }
                guard let level = rawLevel as? String, allowedLevels.contains(level) else {
                    throw DRLoaderError.unsupportedVersion("memory policy level")
                }
                validatedLevels[capability] = level
            }
            return validatedLevels
        }

        guard let memoryPolicy else { return [:] }
        let memoryTypes = Set(memoryPolicy["memory_types"] as? [String] ?? [])
        var levels: [String: String] = [:]
        if memoryTypes.contains("short_term_memory") {
            levels["short_term_memory"] = "supported"
        }
        if memoryTypes.contains("preference_memory"),
           let preferenceMemory = memoryPolicy["preference_memory"] as? [String: Any],
           preferenceMemory["type"] as? String == "kv" {
            levels["preference_memory"] = "supported_minimal_kv"
        }
        if memoryTypes.contains("interaction_log"),
           memoryPolicy["interaction_log"] as? [String: Any] != nil {
            levels["interaction_log"] = "display_cache_only"
        }
        return levels
    }

    private func diagnostics(for error: DRLoaderError) -> String {
        switch error {
        case .invalidFixture:
            return "DR load failed"
        case .missingField(let field):
            return "DR load failed: missing \(field)"
        case .unsupportedVersion(let field):
            return "DR load failed: unsupported \(field)"
        case .conflictingField(let field):
            return "DR load failed: conflicting \(field)"
        }
    }
}
