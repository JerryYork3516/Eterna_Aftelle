import Foundation

public struct RuntimeStepRequest {
    public var residentID: String
    public var inputText: String

    public init(residentID: String, inputText: String) {
        self.residentID = residentID
        self.inputText = inputText
    }
}

public struct RuntimeLoadRequest {
    public var drData: Data

    public init(drData: Data) {
        self.drData = drData
    }
}

public enum RuntimeInterruptReason: String {
    case cancelled
    case interrupted
}

public struct RuntimeCancellationRequest {
    public var reason: RuntimeInterruptReason

    public init(reason: RuntimeInterruptReason) {
        self.reason = reason
    }
}

public struct RuntimeCancellationState {
    public var isCancelled: Bool
    public var reason: RuntimeInterruptReason?

    public init(isCancelled: Bool = false, reason: RuntimeInterruptReason? = nil) {
        self.isCancelled = isCancelled
        self.reason = reason
    }

    public static let none = RuntimeCancellationState()
}

public struct AvatarState {
    public var residentID: String
    public var displayName: String
    public var mode: String
    public var presence: String
    public var moodHint: String
    public var activityHint: String
    public var particleHint: String
    public var updatedAt: Date

    public init(
        residentID: String,
        displayName: String,
        mode: String,
        presence: String,
        moodHint: String,
        activityHint: String,
        particleHint: String,
        updatedAt: Date = Date()
    ) {
        self.residentID = residentID
        self.displayName = displayName
        self.mode = mode
        self.presence = presence
        self.moodHint = moodHint
        self.activityHint = activityHint
        self.particleHint = particleHint
        self.updatedAt = updatedAt
    }
}

public struct RuntimeResidentState {
    public var residentID: String
    public var sessionID: String
    public var lifecycleStatus: String
    public var presence: String
    public var lastActivitySummary: String
    public var lastUpdatedAt: Date
    public var avatarMode: String?

    public init(
        residentID: String,
        sessionID: String,
        lifecycleStatus: String,
        presence: String,
        lastActivitySummary: String,
        lastUpdatedAt: Date = Date(),
        avatarMode: String? = nil
    ) {
        self.residentID = residentID
        self.sessionID = sessionID
        self.lifecycleStatus = lifecycleStatus
        self.presence = presence
        self.lastActivitySummary = lastActivitySummary
        self.lastUpdatedAt = lastUpdatedAt
        self.avatarMode = avatarMode
    }
}

public struct RuntimeStepResponse {
    public var outputText: String
    public var visualState: VisualState
    public var avatarState: AvatarState
    public var residentState: RuntimeResidentState
    public var cancellationState: RuntimeCancellationState
    public var traceEvents: [TraceEvent]
    public var diagnostics: RuntimeDiagnostics

    public init(
        outputText: String,
        visualState: VisualState,
        avatarState: AvatarState,
        residentState: RuntimeResidentState,
        cancellationState: RuntimeCancellationState = .none,
        traceEvents: [TraceEvent],
        diagnostics: RuntimeDiagnostics
    ) {
        self.outputText = outputText
        self.visualState = visualState
        self.avatarState = avatarState
        self.residentState = residentState
        self.cancellationState = cancellationState
        self.traceEvents = traceEvents
        self.diagnostics = diagnostics
    }
}

public struct RuntimeDiagnostics {
    public var runtimeStepCount: Int
    public var providerMode: String
    public var providerProfileID: String?
    public var providerSecretRefPresent: Bool
    public var providerKeyRefPresent: Bool
    public var cancellationState: String

    public init(
        runtimeStepCount: Int = 0,
        providerMode: String = "mock",
        providerProfileID: String? = nil,
        providerSecretRefPresent: Bool = false,
        providerKeyRefPresent: Bool = false,
        cancellationState: String = "none"
    ) {
        self.runtimeStepCount = runtimeStepCount
        self.providerMode = providerMode
        self.providerProfileID = providerProfileID
        self.providerSecretRefPresent = providerSecretRefPresent
        self.providerKeyRefPresent = providerKeyRefPresent
        self.cancellationState = cancellationState
    }
}

public enum RuntimeStepEventType: String {
    case runtimeStep = "runtime.step"
    case providerMock = "provider.mock"
    case visualStateChanged = "visual_state.changed"
}

public struct TraceEvent {
    public var type: RuntimeStepEventType
    public var message: String

    public init(type: RuntimeStepEventType, message: String) {
        self.type = type
        self.message = message
    }
}

public enum VisualStateMode: String {
    case idle
    case thinking
    case speaking
}

public struct VisualState {
    public var mode: VisualStateMode

    public init(mode: VisualStateMode) {
        self.mode = mode
    }
}

public struct RuntimeSessionID: Equatable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> RuntimeSessionID {
        RuntimeSessionID(rawValue: UUID().uuidString)
    }
}

public struct RuntimeSessionContext: Equatable {
    public var residentID: String
    public var sessionID: RuntimeSessionID

    public init(residentID: String, sessionID: RuntimeSessionID) {
        self.residentID = residentID
        self.sessionID = sessionID
    }
}

struct RuntimeResidentIdentityProjection: Equatable {
    let residentID: String
    let displayName: String
    let primaryLanguage: String
    let citySymbol: String?
    let personalitySummary: String?
    let domainFocus: [String]
    let residentDescription: String?
    let residentDisclosure: String?

    init(loadedDR: LoadedDR) {
        residentID = loadedDR.residentID
        displayName = loadedDR.displayName
        primaryLanguage = loadedDR.primaryLanguage
        citySymbol = loadedDR.citySymbol
        personalitySummary = loadedDR.personalitySummary
        domainFocus = loadedDR.domainFocus
        residentDescription = loadedDR.residentDescription
        residentDisclosure = loadedDR.residentDisclosure
    }
}

enum RuntimeMemorySupportLevel: String, Equatable {
    case none
    case supported
    case supportedMinimalKV = "supported_minimal_kv"
    case policyOnly = "policy_only"
    case displayCacheOnly = "display_cache_only"
}

struct RuntimeMemoryPolicyProjection: Equatable {
    let source: String
    let shortTermMemory: RuntimeMemorySupportLevel
    let preferenceMemory: RuntimeMemorySupportLevel
    let eventMemory: RuntimeMemorySupportLevel
    let relationshipMemory: RuntimeMemorySupportLevel
    let interactionLog: RuntimeMemorySupportLevel

    init(loadedDR: LoadedDR) {
        source = loadedDR.memoryPolicySource
        shortTermMemory = Self.level(for: "short_term_memory", in: loadedDR)
        preferenceMemory = Self.level(for: "preference_memory", in: loadedDR)
        eventMemory = Self.level(for: "event_memory", in: loadedDR)
        relationshipMemory = Self.level(for: "relationship_memory", in: loadedDR)
        interactionLog = Self.level(for: "interaction_log", in: loadedDR)
    }

    private static func level(for capability: String, in loadedDR: LoadedDR) -> RuntimeMemorySupportLevel {
        guard let rawValue = loadedDR.memorySupportLevels[capability] else { return .none }
        return RuntimeMemorySupportLevel(rawValue: rawValue) ?? .none
    }
}

struct RuntimeFirstAppearanceProjection: Equatable {
    let interaction: FirstInteractionPolicy?
    let greeting: FirstGreetingConfig?
    let presence: FirstPresenceConfig?
    let relationship: InitialRelationshipConfig?

    init?(loadedDR: LoadedDR) {
        guard loadedDR.firstInteractionPolicy != nil
                || loadedDR.firstGreetingConfig != nil
                || loadedDR.firstPresenceConfig != nil
                || loadedDR.initialRelationshipConfig != nil else {
            return nil
        }
        interaction = loadedDR.firstInteractionPolicy
        greeting = loadedDR.firstGreetingConfig
        presence = loadedDR.firstPresenceConfig
        relationship = loadedDR.initialRelationshipConfig
    }
}

struct RuntimeFirstAppearanceResult: Equatable {
    let residentID: String
    let greetingText: String
    let particleState: String?
    let motion: String?
    let energy: String?
    let subtitleMode: String?
}

struct ResidentDialogueMessage: Equatable {
    let role: String
    let text: String
    let timestamp: Date
}

struct ResidentDialogueFewShotReference: Equatable {
    let exampleID: String
    let kind: String
}

private struct ResidentDialogueFewShotSelection {
    let example: RuntimeDialogueFewShotExample
    let kind: String
}

struct ResidentDialogueContextSummary: Equatable {
    let instructionCount: Int
    let scenarioCount: Int
    let selectedFewShotCount: Int
    let recentMessageCount: Int
    let approvedPreferenceCount: Int
    let prohibitedPatternCount: Int
    let estimatedCharacterCount: Int
}

struct RuntimeRelationshipDialogueContext: Equatable {
    let stageID: String
    let stageBoundary: RuntimeRelationshipStageBoundary
    let allowedEvidenceTypes: [String]

    var instruction: String {
        """
        Current relationship stage: \(stageID).
        Stage semantics: \(stageBoundary.stageSemantics)
        Initiative boundary: \(stageBoundary.initiativeLevel)
        Familiarity boundary: \(stageBoundary.familiarityLevel)
        Address style: \(stageBoundary.addressStyle)
        Self-disclosure boundary: \(stageBoundary.selfDisclosureLevel)
        Follow-up boundary: \(stageBoundary.followUpBoundary)
        Advice boundary: \(stageBoundary.adviceBoundary)
        Stay within these boundaries. Relationship stage decisions belong to RuntimeCore.
        """
    }
}

struct ResidentDialogueContext: Equatable {
    let identity: RuntimeResidentIdentityProjection
    let locale: String
    let systemInstruction: String
    let languagePolicy: RuntimeDialogueInstruction
    let responseStyle: RuntimeDialogueInstruction
    let responseOrder: RuntimeDialogueInstruction
    let followUpPolicy: RuntimeDialogueInstruction
    let advicePolicy: RuntimeDialogueInstruction
    let silencePolicy: RuntimeDialogueInstruction
    let endingPolicy: RuntimeDialogueInstruction
    let relationshipPolicy: RuntimeDialogueInstruction
    let selfDisclosurePolicy: RuntimeDialogueInstruction
    let memoryUsagePolicy: RuntimeDialogueInstruction
    let initialRelationship: InitialRelationshipConfig?
    let relationshipProgression: RuntimeRelationshipDialogueContext?
    let memoryPolicy: RuntimeMemoryPolicyProjection
    let scenarios: [RuntimeDialogueScenario]
    let selectedFewShots: [RuntimeDialogueFewShotExample]
    let selectedFewShotReferences: [ResidentDialogueFewShotReference]
    let requestedFewShotSelectionMode: String
    let appliedFewShotSelectionMode: String
    let prohibitedPatterns: [RuntimeDialogueProhibitedPattern]
    let contextUsagePolicy: RuntimeDialogueContextUsagePolicy
    let recentMessages: [ResidentDialogueMessage]
    let approvedPreferences: [String: String]
    let currentUserInput: String
    let fallbackText: String
    let summary: ResidentDialogueContextSummary
}

struct ResidentDialogueContextSource: Equatable {
    let identity: RuntimeResidentIdentityProjection
    let projection: RuntimeDialogueProjection
    let memoryPolicy: RuntimeMemoryPolicyProjection
    let initialRelationship: InitialRelationshipConfig?

    func compile(
        currentUserInput: String,
        recentMessages: [ResidentDialogueMessage],
        recentMessageLimit: Int,
        fewShotLimit: Int,
        relationshipProgression:
            RuntimeRelationshipDialogueContext? = nil
    ) -> ResidentDialogueContext {
        let emotionalDialogue = projection.emotionalDialogue.flatMap { $0.enabled ? $0 : nil }
        let configuredFewShotLimit = max(
            0,
            min(
                fewShotLimit,
                projection.fewShotSelection.recommendedMaxExamplesPerRequest,
                emotionalDialogue?.fewShotSelection.base.recommendedMaxExamplesPerRequest ?? Int.max
            )
        )
        let selectedFewShotSelection = selectFewShots(
            base: eligibleFewShots(projection.fewShotExamples),
            emotional: eligibleFewShots(emotionalDialogue?.fewShotExamples ?? []),
            limit: configuredFewShotLimit
        )
        let selectedFewShots = selectedFewShotSelection.map(\.example)
        let selectedFewShotReferences = selectedFewShotSelection.map {
            ResidentDialogueFewShotReference(exampleID: $0.example.exampleID, kind: $0.kind)
        }
        let prohibitedPatterns = projection.prohibitedPatterns.filter { $0.status == "forbidden" }
            + (emotionalDialogue?.prohibitedPatterns.enumerated().map { index, reason in
                RuntimeDialogueProhibitedPattern(
                    patternID: "emotional_dialogue.prohibited.\(index)",
                    reason: reason,
                    examples: [],
                    sourceRuleRefs: [],
                    status: "forbidden"
                )
            } ?? [])
        let scenarios = projection.scenarios + (emotionalDialogue?.scenarios.map {
            RuntimeDialogueScenario(
                sceneID: $0.sceneID,
                intent: $0.intent,
                responseStrategy: $0.responseStrategy,
                followUpAllowed: $0.followUpAllowed,
                adviceAllowed: $0.adviceAllowed,
                recommendedLength: $0.recommendedLength,
                prohibitedBehaviors: $0.prohibitedBehaviors,
                linkedPolicyIDs: $0.linkedPolicyIDs,
                sourceRuleRefs: $0.authorityReferenceIDs
            )
        } ?? [])
        let systemInstruction = mergedText(
            [projection.systemInstruction] + emotionalSystemInstructions(emotionalDialogue)
        )
        let responseStyle = mergedInstruction(
            projection.responseStyle,
            additions: emotionalDialogue.map {
                [$0.policies.acknowledgementInstruction, $0.policies.listeningOrAdviceInstruction]
            } ?? []
        )
        let responseOrder = mergedInstruction(
            projection.responseOrder,
            additions: emotionalDialogue?.responseSequence.map(\.instruction) ?? []
        )
        let followUpPolicy = mergedInstruction(
            projection.followUpPolicy,
            additions: emotionalDialogue.map {
                [
                    "Emotional dialogue follow-up question limit per response: \($0.policies.maxFollowUpQuestions).",
                    "Stop emotional follow-up when the user declines: \($0.policies.stopWhenUserDeclines)."
                ]
            } ?? []
        )
        let advicePolicy = mergedInstruction(
            projection.advicePolicy,
            additions: emotionalDialogue.map {
                [
                    $0.policies.adviceStyle,
                    "Confirm that emotional advice is wanted before advising: \($0.policies.confirmAdviceNeedFirst).",
                    "Preserve the user's choice in emotional advice: \($0.policies.preserveUserChoice)."
                ]
            } ?? []
        )
        let boundedRecentMessages = Array(recentMessages.suffix(max(0, recentMessageLimit)))
        let instructionTexts = [
            systemInstruction,
            projection.languagePolicy.instruction,
            responseStyle.instruction,
            responseOrder.instruction,
            followUpPolicy.instruction,
            advicePolicy.instruction,
            projection.silencePolicy.instruction,
            projection.endingPolicy.instruction,
            projection.relationshipPolicy.instruction,
            projection.selfDisclosurePolicy.instruction,
            projection.memoryUsagePolicy.instruction,
            relationshipProgression?.instruction
        ]
        .compactMap { $0 }
        let estimatedCharacterCount = contextCharacterCount(
            instructionTexts: instructionTexts,
            selectedFewShots: selectedFewShots,
            prohibitedPatterns: prohibitedPatterns,
            scenarios: scenarios,
            recentMessages: boundedRecentMessages,
            currentUserInput: currentUserInput
        )

        return ResidentDialogueContext(
            identity: identity,
            locale: projection.locale,
            systemInstruction: systemInstruction,
            languagePolicy: projection.languagePolicy,
            responseStyle: responseStyle,
            responseOrder: responseOrder,
            followUpPolicy: followUpPolicy,
            advicePolicy: advicePolicy,
            silencePolicy: projection.silencePolicy,
            endingPolicy: projection.endingPolicy,
            relationshipPolicy: projection.relationshipPolicy,
            selfDisclosurePolicy: projection.selfDisclosurePolicy,
            memoryUsagePolicy: projection.memoryUsagePolicy,
            initialRelationship: initialRelationship,
            relationshipProgression: relationshipProgression,
            memoryPolicy: memoryPolicy,
            scenarios: scenarios,
            selectedFewShots: selectedFewShots,
            selectedFewShotReferences: selectedFewShotReferences,
            requestedFewShotSelectionMode: projection.fewShotSelection.selectionMode,
            appliedFewShotSelectionMode: emotionalDialogue == nil
                ? "deterministic_baseline"
                : "deterministic_balanced_baseline",
            prohibitedPatterns: prohibitedPatterns,
            contextUsagePolicy: projection.contextUsagePolicy,
            recentMessages: boundedRecentMessages,
            approvedPreferences: [:],
            currentUserInput: currentUserInput,
            fallbackText: projection.fallbackBehavior.text,
            summary: ResidentDialogueContextSummary(
                instructionCount: instructionTexts.count,
                scenarioCount: scenarios.count,
                selectedFewShotCount: selectedFewShots.count,
                recentMessageCount: boundedRecentMessages.count,
                approvedPreferenceCount: 0,
                prohibitedPatternCount: prohibitedPatterns.count,
                estimatedCharacterCount: estimatedCharacterCount
            )
        )
    }

    private func contextCharacterCount(
        instructionTexts: [String],
        selectedFewShots: [RuntimeDialogueFewShotExample],
        prohibitedPatterns: [RuntimeDialogueProhibitedPattern],
        scenarios: [RuntimeDialogueScenario],
        recentMessages: [ResidentDialogueMessage],
        currentUserInput: String
    ) -> Int {
        let identityTexts = [
            identity.residentID,
            identity.displayName,
            identity.primaryLanguage,
            identity.citySymbol,
            identity.personalitySummary,
            identity.residentDescription,
            identity.residentDisclosure
        ].compactMap { $0 } + identity.domainFocus
        let scenarioTexts = scenarios.flatMap {
            [$0.sceneID, $0.intent, $0.responseStrategy, $0.recommendedLength]
                + $0.prohibitedBehaviors
        }
        let fewShotTexts = selectedFewShots.flatMap { example in
            [example.exampleID, example.label, example.sceneID]
                + example.turns.flatMap { [$0.role, $0.text] }
        }
        let prohibitedTexts = prohibitedPatterns.flatMap {
            [$0.patternID, $0.reason] + $0.examples
        }
        let relationshipTexts = [
            initialRelationship?.defaultMode,
            initialRelationship?.intimacyLevel,
            initialRelationship?.trustBuilding
        ].compactMap { $0 }
        let contextBoundaryTexts = (
            projection.contextUsagePolicy.allowedSources
                + projection.contextUsagePolicy.forbiddenSources
        ).flatMap { [$0.sourceID, $0.instruction] }
        let allTexts = identityTexts
            + instructionTexts
            + scenarioTexts
            + fewShotTexts
            + prohibitedTexts
            + relationshipTexts
            + contextBoundaryTexts
            + recentMessages.flatMap { [$0.role, $0.text] }
            + [currentUserInput, projection.fallbackBehavior.text]
        return allTexts.reduce(0) { $0 + $1.count }
    }

    private func eligibleFewShots(
        _ examples: [RuntimeDialogueFewShotExample]
    ) -> [RuntimeDialogueFewShotExample] {
        examples.filter {
            $0.usage == "behavior_guidance_only"
                && $0.notFixedResponse
                && $0.notKeywordMatching
        }
    }

    private func selectFewShots(
        base: [RuntimeDialogueFewShotExample],
        emotional: [RuntimeDialogueFewShotExample],
        limit: Int
    ) -> [ResidentDialogueFewShotSelection] {
        guard limit > 0 else { return [] }
        let baseSelections = base.map { ResidentDialogueFewShotSelection(example: $0, kind: "daily") }
        let emotionalSelections = emotional.map {
            ResidentDialogueFewShotSelection(example: $0, kind: "emotional")
        }
        guard !emotionalSelections.isEmpty else { return Array(baseSelections.prefix(limit)) }
        guard !baseSelections.isEmpty else { return Array(emotionalSelections.prefix(limit)) }

        let baseCount = min(baseSelections.count, (limit + 1) / 2)
        let emotionalCount = min(emotionalSelections.count, limit / 2)
        var selected = Array(baseSelections.prefix(baseCount))
            + Array(emotionalSelections.prefix(emotionalCount))
        let remaining = Array(baseSelections.dropFirst(baseCount))
            + Array(emotionalSelections.dropFirst(emotionalCount))
        selected.append(contentsOf: remaining.prefix(max(0, limit - selected.count)))
        return selected
    }

    private func mergedInstruction(
        _ base: RuntimeDialogueInstruction,
        additions: [String]
    ) -> RuntimeDialogueInstruction {
        RuntimeDialogueInstruction(
            instruction: mergedText([base.instruction] + additions),
            sourceRuleRefs: base.sourceRuleRefs
        )
    }

    private func mergedText(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func emotionalSystemInstructions(
        _ emotional: RuntimeEmotionalDialogueProjection?
    ) -> [String] {
        guard let emotional else { return [] }
        let riskPolicy = emotional.policies
        let riskInstruction = [
            "Emotional safety priority: \(riskPolicy.riskPriority).",
            "Emotional safety support targets: \(riskPolicy.riskSupportTargets.joined(separator: ", ")).",
            "Bypass ordinary advice confirmation for high-risk safety: \(riskPolicy.bypassAdviceConfirmationForRisk).",
            "Do not escalate ordinary low mood as high risk: \(riskPolicy.doNotEscalateOrdinaryLowMood)."
        ].joined(separator: " ")
        let scenarios = emotional.scenarios.map { scenario in
            [
                "Emotional scenario: \(scenario.sceneID).",
                "Risk level: \(scenario.riskLevel).",
                "Intent: \(scenario.intent).",
                "Response strategy: \(scenario.responseStrategy).",
                "Follow-up allowed: \(scenario.followUpAllowed).",
                "Advice allowed: \(scenario.adviceAllowed).",
                "Recommended length: \(scenario.recommendedLength).",
                "Prohibited behaviors: \(scenario.prohibitedBehaviors.joined(separator: "; "))."
            ].joined(separator: " ")
        }
        return [emotional.systemInstructionAddendum, riskInstruction] + scenarios
    }
}

public struct RuntimeClockState: Equatable {
    public var tickCount: Int
    public var lastTickAt: Date?

    public init(tickCount: Int = 0, lastTickAt: Date? = nil) {
        self.tickCount = tickCount
        self.lastTickAt = lastTickAt
    }
}

public struct RuntimeTickRequest {
    public var reason: String

    public init(reason: String = "noop") {
        self.reason = reason
    }
}

public struct RuntimeTickResponse {
    public var clockState: RuntimeClockState
    public var traceEvent: TraceEvent
    public var diagnostics: RuntimeDiagnostics

    public init(clockState: RuntimeClockState, traceEvent: TraceEvent, diagnostics: RuntimeDiagnostics) {
        self.clockState = clockState
        self.traceEvent = traceEvent
        self.diagnostics = diagnostics
    }
}

public struct RuntimeLoadResult {
    public let isLoaded: Bool
    public let residentID: String
    public let sessionID: RuntimeSessionID?
    public let displayName: String
    public let statusMessage: String
    public let diagnostics: String
    public let avatarState: AvatarState?
    public let residentState: RuntimeResidentState?
}

public struct RuntimeDialogueEntryState {
    public var role: String
    public var text: String
    public var timestamp: Date

    public init(role: String, text: String, timestamp: Date) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public struct RuntimeSessionRestoreResult {
    public let didRestore: Bool
    public let residentID: String
    public let sessionID: String
    public let lastUserInput: String
    public let lastResidentOutput: String
    public let lastActivity: String
    public let avatarMode: String
    public let avatarPresence: String
    public let avatarMoodHint: String
    public let avatarActivityHint: String
    public let avatarParticleHint: String
    public let shutdownState: SessionShutdownState
    public let recoveryRequired: Bool
    public let recoveredAt: Date?
    public let dialogueEntries: [RuntimeDialogueEntryState]

    public init(
        didRestore: Bool,
        residentID: String = "",
        sessionID: String = "",
        lastUserInput: String = "",
        lastResidentOutput: String = "",
        lastActivity: String = "",
        avatarMode: String = "idle",
        avatarPresence: String = "unknown",
        avatarMoodHint: String = "",
        avatarActivityHint: String = "",
        avatarParticleHint: String = "",
        shutdownState: SessionShutdownState = .unclean,
        recoveryRequired: Bool = false,
        recoveredAt: Date? = nil,
        dialogueEntries: [RuntimeDialogueEntryState] = []
    ) {
        self.didRestore = didRestore
        self.residentID = residentID
        self.sessionID = sessionID
        self.lastUserInput = lastUserInput
        self.lastResidentOutput = lastResidentOutput
        self.lastActivity = lastActivity
        self.avatarMode = avatarMode
        self.avatarPresence = avatarPresence
        self.avatarMoodHint = avatarMoodHint
        self.avatarActivityHint = avatarActivityHint
        self.avatarParticleHint = avatarParticleHint
        self.shutdownState = shutdownState
        self.recoveryRequired = recoveryRequired
        self.recoveredAt = recoveredAt
        self.dialogueEntries = dialogueEntries
    }
}

struct RuntimeRelationshipDecision: Equatable {
    let stageID: String?
    let evidenceIDs: [String]
    let decision: String
    let reason: String

    static let unavailable = RuntimeRelationshipDecision(
        stageID: nil,
        evidenceIDs: [],
        decision: "feature_unavailable",
        reason: "projection_missing"
    )
}

#if DEBUG
struct RuntimeRelationshipDebugSnapshot: Equatable {
    let isAvailable: Bool
    let stageID: String?
    let evidenceIDs: [String]
    let lastTransitionReason: String?
    let enabled: Bool
    let revision: Int?
}

enum RuntimeOrchestrationStepKind: String, CaseIterable {
    case inputReceived = "input_received"
    case residentSessionConfirmed = "resident_session_confirmed"
    case contextCompiled = "context_compiled"
    case contextSelected = "context_selected"
    case memoryChecked = "memory_checked"
    case providerRouted = "provider_routed"
    case requestCompleted = "request_completed"
    case sessionPersisted = "session_persisted"
    case presentationUpdated = "presentation_updated"
}

enum RuntimeOrchestrationStepStatus: String {
    case pending
    case completed
    case failed
    case cancelled
    case skipped
}

enum RuntimeOrchestrationResultStatus: String {
    case success
    case failure
    case cancelled
}

enum RuntimeOrchestrationSessionWriteStatus: String {
    case saved
    case failed
    case skipped
}

enum RuntimeLifecycleState: String, Equatable {
    case idle
    case thinking
    case speaking
    case loading
    case error
    case exit
}

struct RuntimeOrchestrationProviderMetadata: Equatable {
    let providerID: String
    let modelID: String
    let adapterType: String
}

struct RuntimeOrchestrationFewShotReference: Equatable {
    let exampleID: String
    let kind: String
}

struct RuntimeOrchestrationStep: Equatable {
    let kind: RuntimeOrchestrationStepKind
    var status: RuntimeOrchestrationStepStatus
    var durationMilliseconds: Int
}

struct RuntimeOrchestrationInteraction: Equatable, Identifiable {
    let id: UUID
    let residentID: String
    let sessionID: String
    let startedAt: Date
    var endedAt: Date
    let dailyRulesEnabled: Bool
    let emotionalRulesEnabled: Bool
    let recentMessageCount: Int
    let fewShotReferences: [RuntimeOrchestrationFewShotReference]
    let approvedPreferenceCount: Int
    let provider: RuntimeOrchestrationProviderMetadata?
    var result: RuntimeOrchestrationResultStatus
    var errorCategory: String?
    var sessionWriteStatus: RuntimeOrchestrationSessionWriteStatus
    var subtitleState: String
    var particleState: String
    var lifecycleState: RuntimeLifecycleState
    let expressionState: String
    let expressionIntensity: Double
    let expressionFallbackOccurred: Bool
    let expressionMapping: RuntimeExpressionMultipliers
    let expressionMappingSource: String
    let relationshipStageID: String?
    let relationshipEvidenceIDs: [String]
    let relationshipDecision: String
    let relationshipReason: String
    var steps: [RuntimeOrchestrationStep]

    var durationMilliseconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt) * 1_000))
    }
}
#endif

public final class RuntimeCore {
    static let recentDialogueMessageLimit = 8
    static let fewShotSelectionLimit = 4

    private let drLoader: DRLoader
    private let executionEngine: ExecutionEngine
    private let providerRouter: ProviderRouter
    private let hostEnv: HostEnv
    private let sessionStore: SessionStore
    private let memoryController: MemoryController
    private var relationshipStateStore = RelationshipStateStore()
    private var cancellationState = RuntimeCancellationState.none
    private var sessionContext: RuntimeSessionContext?
    private(set) var currentResidentIdentity: RuntimeResidentIdentityProjection?
    private(set) var currentMemoryPolicy: RuntimeMemoryPolicyProjection?
    private(set) var currentFirstAppearance: RuntimeFirstAppearanceProjection?
    private(set) var currentDialogueContextSource: ResidentDialogueContextSource?
    private(set) var currentExpressionResult = RuntimeExpressionResult.neutral(
        source: .compatibilityFallback,
        fallbackOccurred: true
    )
    private var currentVisualExpressionMapping =
        RuntimeVisualExpressionMapping.compatibilityFallback
    private var currentRelationshipProgressionProjection:
        RuntimeRelationshipProgressionProjection?
    private(set) var currentRelationshipState:
        RuntimeRelationshipInstanceState?
    private var activeExpressionRequestID: UUID?
    private var handledFirstAppearanceResidentIDs: Set<String> = []
    private var clockState = RuntimeClockState()
    #if DEBUG
    private static let runtimeOrchestrationCapacity = 50
    private var runtimeOrchestrationRecords: [RuntimeOrchestrationInteraction] = []
    private var runtimeOrchestrationProviderMetadata: RuntimeOrchestrationProviderMetadata?
    #endif

    public init(
        drLoader: DRLoader = DRLoader(),
        executionEngine: ExecutionEngine = ExecutionEngine(),
        providerRouter: ProviderRouter = ProviderRouter(),
        hostEnv: HostEnv = DefaultHostEnv(),
        sessionStore: SessionStore = SessionStore(),
        memoryController: MemoryController = MemoryController()
    ) {
        self.drLoader = drLoader
        self.executionEngine = executionEngine
        self.providerRouter = providerRouter
        self.hostEnv = hostEnv
        self.sessionStore = sessionStore
        self.memoryController = memoryController
    }

    convenience init(providerCredentialReader: ProviderCredentialReading) {
        let router = ProviderRouter(credentialReader: providerCredentialReader)
        self.init(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router
        )
    }

    public func loadDR(from data: Data) -> RuntimeLoadResult {
        do {
            let result = try drLoader.load(request: DRLoadRequest(drData: data))
            guard let loadedDR = result.loadedDR, result.isLoaded else {
                return RuntimeLoadResult(
                    isLoaded: false,
                    residentID: "",
                    sessionID: nil,
                    displayName: "",
                    statusMessage: "DR load failed",
                    diagnostics: result.diagnostics,
                    avatarState: nil,
                    residentState: nil
                )
            }

            let sessionID = RuntimeSessionID.make()
            let identityProjection = RuntimeResidentIdentityProjection(loadedDR: loadedDR)
            let memoryPolicyProjection = RuntimeMemoryPolicyProjection(loadedDR: loadedDR)
            let firstAppearanceProjection = RuntimeFirstAppearanceProjection(loadedDR: loadedDR)
            let dialogueContextSource = loadedDR.runtimeDialogueProjection.map {
                ResidentDialogueContextSource(
                    identity: identityProjection,
                    projection: $0,
                    memoryPolicy: memoryPolicyProjection,
                    initialRelationship: loadedDR.initialRelationshipConfig
                )
            }
            sessionContext = RuntimeSessionContext(residentID: loadedDR.residentID, sessionID: sessionID)
            activeExpressionRequestID = nil
            cancellationState = .none
            currentResidentIdentity = identityProjection
            currentMemoryPolicy = memoryPolicyProjection
            currentFirstAppearance = firstAppearanceProjection
            currentDialogueContextSource = dialogueContextSource
            currentVisualExpressionMapping = loadedDR.visualExpressionMapping
            currentRelationshipProgressionProjection =
                loadedDR.relationshipProgressionProjection
            currentRelationshipState = loadRelationshipState(
                residentID: loadedDR.residentID,
                projection: loadedDR.relationshipProgressionProjection
            )
            currentExpressionResult = .neutral(
                source: loadedDR.visualExpressionMapping.source,
                fallbackOccurred:
                    loadedDR.visualExpressionMapping.source == .compatibilityFallback
            )
            memoryController.setActiveResidentID(loadedDR.residentID)
            let avatarState = AvatarState(
                residentID: loadedDR.residentID,
                displayName: loadedDR.displayName,
                mode: "idle",
                presence: "present",
                moodHint: "calm",
                activityHint: "ready",
                particleHint: "calibration_idle"
            )
            let residentState = RuntimeResidentState(
                residentID: loadedDR.residentID,
                sessionID: sessionID.rawValue,
                lifecycleStatus: "loaded",
                presence: "available",
                lastActivitySummary: "DR loaded",
                lastUpdatedAt: Date(),
                avatarMode: avatarState.mode
            )

            return RuntimeLoadResult(
                isLoaded: true,
                residentID: loadedDR.residentID,
                sessionID: sessionID,
                displayName: loadedDR.displayName,
                statusMessage: "DR loaded",
                diagnostics: result.diagnostics,
                avatarState: avatarState,
                residentState: residentState
            )
        } catch {
            return RuntimeLoadResult(
                isLoaded: false,
                residentID: "",
                sessionID: nil,
                displayName: "",
                statusMessage: "DR load failed",
                diagnostics: "DR load failed",
                avatarState: nil,
                residentState: nil
            )
        }
    }

    public func loadDR(request: RuntimeLoadRequest) -> RuntimeLoadResult {
        loadDR(from: request.drData)
    }

    func consumeFirstAppearance(
        for residentID: String,
        userInitiated: Bool
    ) -> RuntimeFirstAppearanceResult? {
        guard !residentID.isEmpty,
              currentResidentIdentity?.residentID == residentID,
              !handledFirstAppearanceResidentIDs.contains(residentID) else {
            return nil
        }
        handledFirstAppearanceResidentIDs.insert(residentID)
        guard userInitiated,
              let projection = currentFirstAppearance,
              projection.interaction?.enabled == true,
              projection.interaction?.firstLoadEnabled == true,
              projection.greeting?.contentStatus == "authored",
              let greetingText = projection.greeting?.variants.first(where: {
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            return nil
        }
        return RuntimeFirstAppearanceResult(
            residentID: residentID,
            greetingText: greetingText,
            particleState: projection.presence?.particleState,
            motion: projection.presence?.motion,
            energy: projection.presence?.energy,
            subtitleMode: projection.presence?.subtitleMode
        )
    }

    public func restoreMostRecentSession() -> RuntimeSessionRestoreResult {
        guard let record = try? sessionStore.loadMostRecentRecord() else {
            return RuntimeSessionRestoreResult(didRestore: false)
        }
        let displayCache = try? sessionStore.loadDisplayCache()
        guard record.schemaVersion == SessionStore.schemaVersion else {
            return RuntimeSessionRestoreResult(didRestore: false)
        }
        if let currentResidentIdentity, currentResidentIdentity.residentID != record.residentID {
            return RuntimeSessionRestoreResult(didRestore: false)
        }
        let dialogueEntries = (try? sessionStore.loadMostRecentDialogueEntries()) ?? []
        let avatarMode = displayCache?.avatarMode ?? "idle"
        let avatarPresence = displayCache?.avatarPresence ?? "unknown"
        let avatarMoodHint = displayCache?.avatarMoodHint ?? ""
        let avatarActivityHint = displayCache?.avatarActivityHint ?? ""
        let avatarParticleHint = displayCache?.avatarParticleHint ?? ""
        sessionContext = RuntimeSessionContext(
            residentID: record.residentID,
            sessionID: RuntimeSessionID(rawValue: record.sessionID)
        )
        activeExpressionRequestID = nil
        cancellationState = .none
        currentExpressionResult = .neutral(
            source: currentVisualExpressionMapping.source,
            fallbackOccurred:
                currentVisualExpressionMapping.source == .compatibilityFallback
        )
        handledFirstAppearanceResidentIDs.insert(record.residentID)
        memoryController.setActiveResidentID(record.residentID)
        let recoveredAt = Date()
        let recoveryRequired = record.shutdownState == .unclean
        let updatedRecord = SessionStoreRecord(
            schemaVersion: record.schemaVersion,
            residentID: record.residentID,
            sessionID: record.sessionID,
            createdAt: record.createdAt,
            updatedAt: recoveredAt,
            lastUserInput: record.lastUserInput,
            lastResidentOutput: record.lastResidentOutput,
            lastActivity: record.lastActivity,
            shutdownState: .unclean,
            recoveryRequired: recoveryRequired,
            recoveredAt: recoveredAt
        )
        try? sessionStore.save(record: updatedRecord)
        try? sessionStore.saveDisplayCache(SessionDisplayCache(
            residentID: record.residentID,
            sessionID: record.sessionID,
            lastUserInput: record.lastUserInput,
            lastResidentOutput: record.lastResidentOutput,
            lastActivity: record.lastActivity,
            avatarMode: avatarMode,
            avatarPresence: avatarPresence,
            avatarMoodHint: avatarMoodHint,
            avatarActivityHint: avatarActivityHint,
            avatarParticleHint: avatarParticleHint,
            shutdownState: record.shutdownState,
            recoveryRequired: recoveryRequired,
            recoveredAt: recoveredAt,
            updatedAt: recoveredAt
        ))
        return RuntimeSessionRestoreResult(
            didRestore: true,
            residentID: record.residentID,
            sessionID: record.sessionID,
            lastUserInput: record.lastUserInput,
            lastResidentOutput: record.lastResidentOutput,
            lastActivity: record.lastActivity,
            avatarMode: avatarMode,
            avatarPresence: avatarPresence,
            avatarMoodHint: avatarMoodHint,
            avatarActivityHint: avatarActivityHint,
            avatarParticleHint: avatarParticleHint,
            shutdownState: record.shutdownState,
            recoveryRequired: recoveryRequired,
            recoveredAt: recoveredAt,
            dialogueEntries: dialogueEntries.map {
                RuntimeDialogueEntryState(role: $0.role, text: $0.text, timestamp: $0.timestamp)
            }
        )
    }

    func saveCurrentSession(
        lastUserInput: String,
        lastResidentOutput: String,
        lastActivity: String,
        avatarState: AvatarState,
        dialogueEntries: [RuntimeDialogueEntryState]
    ) {
        persistSessionSnapshot(
            shutdownState: .clean,
            recoveryRequired: false,
            recoveredAt: nil,
            lastUserInput: lastUserInput,
            lastResidentOutput: lastResidentOutput,
            lastActivity: lastActivity,
            avatarState: avatarState,
            dialogueEntries: dialogueEntries
        )
    }

    func markSessionUnclean(
        lastUserInput: String = "",
        lastResidentOutput: String = "",
        lastActivity: String = "",
        avatarState: AvatarState? = nil,
        dialogueEntries: [RuntimeDialogueEntryState] = []
    ) {
        persistSessionSnapshot(
            shutdownState: .unclean,
            recoveryRequired: false,
            recoveredAt: nil,
            lastUserInput: lastUserInput,
            lastResidentOutput: lastResidentOutput,
            lastActivity: lastActivity,
            avatarState: avatarState,
            dialogueEntries: dialogueEntries
        )
    }

    private func persistSessionSnapshot(
        shutdownState: SessionShutdownState,
        recoveryRequired: Bool,
        recoveredAt: Date?,
        lastUserInput: String,
        lastResidentOutput: String,
        lastActivity: String,
        avatarState: AvatarState?,
        dialogueEntries: [RuntimeDialogueEntryState]
    ) {
        guard let context = sessionContext else { return }
        let now = Date()
        let record = SessionStoreRecord(
            residentID: context.residentID,
            sessionID: context.sessionID.rawValue,
            createdAt: now,
            updatedAt: now,
            lastUserInput: lastUserInput,
            lastResidentOutput: lastResidentOutput,
            lastActivity: lastActivity,
            shutdownState: shutdownState,
            recoveryRequired: recoveryRequired,
            recoveredAt: recoveredAt
        )
        try? sessionStore.save(record: record)
        try? sessionStore.saveDisplayCache(SessionDisplayCache(
            residentID: context.residentID,
            sessionID: context.sessionID.rawValue,
            lastUserInput: lastUserInput,
            lastResidentOutput: lastResidentOutput,
            lastActivity: lastActivity,
            avatarMode: avatarState?.mode ?? "idle",
            avatarPresence: avatarState?.presence ?? "unknown",
            avatarMoodHint: avatarState?.moodHint ?? "",
            avatarActivityHint: avatarState?.activityHint ?? "",
            avatarParticleHint: avatarState?.particleHint ?? "",
            shutdownState: shutdownState,
            recoveryRequired: recoveryRequired,
            recoveredAt: recoveredAt,
            updatedAt: now
        ))
        let entries = dialogueEntries.map {
            SessionDialogueEntry(role: $0.role, text: $0.text, timestamp: $0.timestamp)
        }
        try? sessionStore.saveDialogueEntries(entries, for: context.sessionID.rawValue)
    }

    public func step(inputText: String) -> RuntimeStepResponse {
        let residentID = sessionContext?.residentID ?? ""
        let request = RuntimeStepRequest(residentID: residentID, inputText: inputText)
        return step(request: request)
    }

    public func step(request: RuntimeStepRequest) -> RuntimeStepResponse {
        let pendingCancellation = cancellationState
        cancellationState = .none
        let displayName = currentResidentIdentity?.residentID == request.residentID
            ? currentResidentIdentity?.displayName ?? ""
            : ""
        var response = executionEngine.step(
            request: request,
            residentDisplayName: displayName,
            cancellationState: pendingCancellation
        )
        guard !request.residentID.isEmpty else {
            return response
        }

        let sessionID = sessionContext?.sessionID ?? .make()
        sessionContext = RuntimeSessionContext(residentID: request.residentID, sessionID: sessionID)
        response.residentState.sessionID = sessionID.rawValue
        markSessionUnclean(
            lastUserInput: request.inputText,
            lastResidentOutput: response.outputText,
            lastActivity: response.residentState.lastActivitySummary,
            avatarState: response.avatarState,
            dialogueEntries: [
                RuntimeDialogueEntryState(role: "user", text: request.inputText, timestamp: response.residentState.lastUpdatedAt),
                RuntimeDialogueEntryState(role: "resident", text: response.outputText, timestamp: response.residentState.lastUpdatedAt)
            ]
        )
        return response
    }

    func compileResidentDialogueContext(currentUserInput: String) -> ResidentDialogueContext? {
        guard let source = currentDialogueContextSource,
              sessionContext?.residentID == source.identity.residentID else {
            return nil
        }
        return source.compile(
            currentUserInput: currentUserInput,
            recentMessages: recentDialogueMessages(limit: Self.recentDialogueMessageLimit),
            recentMessageLimit: Self.recentDialogueMessageLimit,
            fewShotLimit: Self.fewShotSelectionLimit,
            relationshipProgression: relationshipDialogueContext()
        )
    }

    private enum RelationshipUserControl {
        case disable
        case reset
        case downgrade
        case rejectUpgrade
    }

    private func relationshipDialogueContext()
        -> RuntimeRelationshipDialogueContext? {
        guard let projection = currentRelationshipProgressionProjection,
              let state = currentRelationshipState,
              state.enabled,
              projection.enabledStages.contains(state.currentStage),
              let boundary =
                projection.stageDefinitions[state.currentStage] else {
            return nil
        }
        return RuntimeRelationshipDialogueContext(
            stageID: state.currentStage.rawValue,
            stageBoundary: boundary,
            allowedEvidenceTypes:
                projection.allowedEvidenceTypes.sorted()
        )
    }

    private func loadRelationshipState(
        residentID: String,
        projection: RuntimeRelationshipProgressionProjection?
    ) -> RuntimeRelationshipInstanceState? {
        guard let projection else { return nil }
        if let stored = try? relationshipStateStore.load(
            residentID: residentID
        ),
           projection.enabledStages.contains(stored.currentStage),
           stored.revision > 0,
           stored.validEvidenceIDs.count
                == Set(stored.validEvidenceIDs).count,
           Set(stored.validEvidenceIDs).isSubset(
                of: projection.allowedEvidenceTypes
           ),
           Set(stored.validEvidenceIDs).isDisjoint(
                with: projection.forbiddenEvidenceTypes
           ) {
            return stored
        }

        let state = RuntimeRelationshipInstanceState(
            residentID: residentID,
            currentStage: projection.defaultStage
        )
        do {
            try relationshipStateStore.save(state)
            return state
        } catch {
            return RuntimeRelationshipInstanceState(
                residentID: residentID,
                currentStage: projection.defaultStage,
                lastTransitionReason: "persistence_failed"
            )
        }
    }

    private func relationshipUserControl(
        for input: String
    ) -> RelationshipUserControl? {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let controls: [([String], RelationshipUserControl)] = [
            (
                [
                    "关闭关系演进",
                    "停止关系演进",
                    "disable relationship progression"
                ],
                .disable
            ),
            (
                [
                    "重置关系",
                    "恢复初识",
                    "reset relationship"
                ],
                .reset
            ),
            (
                [
                    "关系回退",
                    "退回上一个关系阶段",
                    "downgrade relationship"
                ],
                .downgrade
            ),
            (
                [
                    "拒绝关系升级",
                    "不要升级关系",
                    "不同意关系升级",
                    "撤回关系确认",
                    "撤回关系升级",
                    "reject relationship upgrade",
                    "revoke relationship confirmation"
                ],
                .rejectUpgrade
            )
        ]
        return controls.first {
            phrases, _ in phrases.contains {
                normalized.contains($0)
            }
        }?.1
    }

    private func currentRelationshipDecision(
        decision: String = "no_change",
        reason: String = "no_valid_evidence"
    ) -> RuntimeRelationshipDecision {
        guard currentRelationshipProgressionProjection != nil,
              let state = currentRelationshipState else {
            return .unavailable
        }
        return RuntimeRelationshipDecision(
            stageID: state.currentStage.rawValue,
            evidenceIDs: state.validEvidenceIDs,
            decision: decision,
            reason: reason
        )
    }

    private func applyRelationshipUserControl(
        _ control: RelationshipUserControl?
    ) -> RuntimeRelationshipDecision {
        guard let control else {
            return currentRelationshipDecision(
                reason: "no_user_control"
            )
        }
        guard let projection = currentRelationshipProgressionProjection,
              var state = currentRelationshipState else {
            return .unavailable
        }

        let decision: String
        let reason: String
        switch control {
        case .disable:
            state.enabled = false
            state.validEvidenceIDs = []
            decision = "disabled"
            reason = "user_disabled_progression"
        case .reset:
            state.currentStage = projection.resetTarget
            state.enabled = true
            state.validEvidenceIDs = []
            decision = "reset"
            reason = "user_reset_to_initial"
        case .downgrade:
            if let previous = state.currentStage.previous {
                state.currentStage = previous
                decision = "downgraded"
                reason = "user_requested_downgrade"
            } else {
                decision = "no_change"
                reason = "already_at_initial_stage"
            }
            state.validEvidenceIDs = []
        case .rejectUpgrade:
            state.validEvidenceIDs = []
            decision = "upgrade_rejected"
            reason = "user_rejected_upgrade"
        }
        return persistRelationshipState(
            state,
            decision: decision,
            reason: reason
        )
    }

    private func evaluateRelationshipEvidence(
        _ candidates: [ProviderRelationshipEvidenceCandidate]
    ) -> RuntimeRelationshipDecision {
        guard let projection = currentRelationshipProgressionProjection,
              var state = currentRelationshipState else {
            return .unavailable
        }
        guard state.enabled else {
            return currentRelationshipDecision(
                decision: "no_change",
                reason: "relationship_progression_disabled"
            )
        }

        let detectedUserEvidence = Set(
            candidates.compactMap { candidate -> String? in
                let evidenceSource = candidate.evidenceSource
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard candidate.evidenceDetected,
                      evidenceSource == "explicit_user_expression" else {
                    return nil
                }
                return candidate.evidenceType
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
        )
        guard detectedUserEvidence.isDisjoint(
            with: projection.forbiddenEvidenceTypes
        ),
        !detectedUserEvidence.contains(
            "user_requested_downgrade_or_reset"
        ) else {
            return currentRelationshipDecision(
                decision: "evidence_ignored",
                reason: "forbidden_evidence_present"
            )
        }

        let evidenceIDs = Set(candidates.compactMap { candidate -> String? in
            let evidenceType = candidate.evidenceType
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let evidenceSource = candidate.evidenceSource
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard candidate.evidenceDetected,
                  evidenceSource == "explicit_user_expression",
                  projection.allowedEvidenceTypes.contains(evidenceType),
                  !projection.forbiddenEvidenceTypes.contains(evidenceType),
                  evidenceType != "user_requested_downgrade_or_reset",
                  evidenceType
                    != RuntimeRelationshipProgressionProjection
                        .reservedStageID else {
                return nil
            }
            return evidenceType
        })

        guard !evidenceIDs.isEmpty else {
            return currentRelationshipDecision(
                decision: "evidence_ignored",
                reason: "no_valid_evidence"
            )
        }

        guard let nextStage = state.currentStage.next,
              projection.enabledStages.contains(nextStage) else {
            return currentRelationshipDecision(
                decision: "no_change",
                reason: "highest_enabled_stage_reached"
            )
        }

        let existingEvidence = Set(state.validEvidenceIDs)
        let novelEvidence = evidenceIDs.subtracting(existingEvidence)
        guard !novelEvidence.isEmpty else {
            return currentRelationshipDecision(
                decision: "evidence_ignored",
                reason: "no_new_independent_evidence"
            )
        }
        let combinedEvidence = existingEvidence.union(evidenceIDs)
        let traceEvidenceIDs = combinedEvidence.sorted()
        if relationshipEvidenceSatisfiesTransition(
            from: state.currentStage,
            existingEvidence: existingEvidence,
            novelEvidence: novelEvidence,
            combinedEvidence: combinedEvidence
        ) {
            state.currentStage = nextStage
            state.validEvidenceIDs = []
            return persistRelationshipState(
                state,
                decision: "upgraded",
                reason: "evidence_combination_satisfied",
                decisionEvidenceIDs: traceEvidenceIDs
            )
        }

        state.validEvidenceIDs = traceEvidenceIDs
        return persistRelationshipState(
            state,
            decision: "evidence_recorded",
            reason: "evidence_combination_incomplete"
        )
    }

    private func relationshipEvidenceSatisfiesTransition(
        from stage: RuntimeRelationshipStage,
        existingEvidence: Set<String>,
        novelEvidence: Set<String>,
        combinedEvidence: Set<String>
    ) -> Bool {
        guard !existingEvidence.isEmpty,
              !novelEvidence.isEmpty,
              combinedEvidence.count >= 2 else {
            return false
        }

        let explicitRelationshipEvidence = Set([
            "explicit_willingness_to_continue",
            "explicit_familiarity_or_trust",
            "user_confirmed_relationship_change"
        ])
        switch stage {
        case .initialAcquaintance:
            return !combinedEvidence.isDisjoint(
                with: explicitRelationshipEvidence
            )
        case .growingFamiliarity:
            return combinedEvidence.contains(
                "explicit_willingness_to_continue"
            ) && combinedEvidence.count >= 2
        case .stableCompanionship:
            return combinedEvidence.contains(
                "explicit_familiarity_or_trust"
            ) && combinedEvidence.count >= 2
        case .trustedRelationship:
            return false
        }
    }

    private func persistRelationshipState(
        _ pendingState: RuntimeRelationshipInstanceState,
        decision: String,
        reason: String,
        decisionEvidenceIDs: [String]? = nil
    ) -> RuntimeRelationshipDecision {
        var state = pendingState
        state.lastTransitionReason = reason
        state.updatedAt = Date()
        state.revision += 1
        do {
            try relationshipStateStore.save(state)
            currentRelationshipState = state
            return RuntimeRelationshipDecision(
                stageID: state.currentStage.rawValue,
                evidenceIDs:
                    decisionEvidenceIDs ?? state.validEvidenceIDs,
                decision: decision,
                reason: reason
            )
        } catch {
            return currentRelationshipDecision(
                decision: "persistence_failed",
                reason: "relationship_state_not_updated"
            )
        }
    }

    func configureTextProvider(profile: ProviderProfile) -> ProviderRequestError? {
        let error = executionEngine.configureTextProvider(profile: profile)
        if error == nil {
            activeExpressionRequestID = nil
        }
        #if DEBUG
        if error == nil {
            runtimeOrchestrationProviderMetadata = profile.enabled
                ? RuntimeOrchestrationProviderMetadata(
                    providerID: profile.providerID,
                    modelID: profile.modelID,
                    adapterType: profile.adapterType
                )
                : nil
        }
        #endif
        return error
    }

    func testResidentReply(
        inputText: String,
        interactionID: UUID? = nil
    ) async -> Result<RuntimeResidentReply, ProviderRequestError> {
        #if DEBUG
        let orchestrationID = interactionID ?? UUID()
        let orchestrationStartedAt = Date()
        let orchestrationProviderMetadata = runtimeOrchestrationProviderMetadata
        let orchestrationEmotionalRulesEnabled =
            currentDialogueContextSource?.projection.emotionalDialogue?.enabled == true
        let orchestrationExpressionSnapshot = currentExpressionResult
        var orchestrationSteps = [runtimeOrchestrationStep(
            .inputReceived,
            status: .completed,
            startedAt: orchestrationStartedAt
        )]
        let sessionConfirmationStartedAt = Date()
        #endif

        guard let sessionAtStart = sessionContext else {
            #if DEBUG
            orchestrationSteps.append(runtimeOrchestrationStep(
                .residentSessionConfirmed,
                status: .failed,
                startedAt: sessionConfirmationStartedAt
            ))
            appendRuntimeOrchestrationRecord(
                id: orchestrationID,
                session: nil,
                startedAt: orchestrationStartedAt,
                context: nil,
                result: .failure(.residentUnavailable),
                expressionSnapshot: orchestrationExpressionSnapshot,
                sessionWriteStatus: .skipped,
                steps: orchestrationSteps,
                presentationPending: true,
                providerMetadata: orchestrationProviderMetadata,
                emotionalRulesEnabled: orchestrationEmotionalRulesEnabled
            )
            #endif
            return .failure(.residentUnavailable)
        }

        #if DEBUG
        orchestrationSteps.append(runtimeOrchestrationStep(
            .residentSessionConfirmed,
            status: .completed,
            startedAt: sessionConfirmationStartedAt
        ))
        let contextCompilationStartedAt = Date()
        #endif
        let relationshipControl = relationshipUserControl(
            for: inputText
        )
        var relationshipDecision = applyRelationshipUserControl(
            relationshipControl
        )
        guard let context = compileResidentDialogueContext(currentUserInput: inputText) else {
            #if DEBUG
            orchestrationSteps.append(runtimeOrchestrationStep(
                .contextCompiled,
                status: .failed,
                startedAt: contextCompilationStartedAt
            ))
            appendRuntimeOrchestrationRecord(
                id: orchestrationID,
                session: sessionAtStart,
                startedAt: orchestrationStartedAt,
                context: nil,
                result: .failure(.residentUnavailable),
                expressionSnapshot: orchestrationExpressionSnapshot,
                sessionWriteStatus: .skipped,
                steps: orchestrationSteps,
                presentationPending: true,
                providerMetadata: orchestrationProviderMetadata,
                emotionalRulesEnabled: orchestrationEmotionalRulesEnabled,
                relationshipDecision: relationshipDecision
            )
            #endif
            return .failure(.residentUnavailable)
        }

        #if DEBUG
        orchestrationSteps.append(runtimeOrchestrationStep(
            .contextCompiled,
            status: .completed,
            startedAt: contextCompilationStartedAt
        ))
        orchestrationSteps.append(runtimeOrchestrationStep(
            .contextSelected,
            status: .completed,
            startedAt: Date()
        ))
        orchestrationSteps.append(runtimeOrchestrationStep(
            .memoryChecked,
            status: .completed,
            startedAt: Date()
        ))
        orchestrationSteps.append(runtimeOrchestrationStep(
            .providerRouted,
            status: orchestrationProviderMetadata == nil ? .failed : .completed,
            startedAt: Date()
        ))
        let requestStartedAt = Date()
        #endif
        let expressionRequestID = UUID()
        activeExpressionRequestID = expressionRequestID
        let expressionMappingAtStart = currentVisualExpressionMapping
        let result = await executionEngine.testResidentReply(
            context: context,
            expressionMapping: expressionMappingAtStart
        )

        #if DEBUG
        orchestrationSteps.append(runtimeOrchestrationStep(
            .requestCompleted,
            status: runtimeOrchestrationStepStatus(for: result),
            startedAt: requestStartedAt
        ))
        #endif
        let staleSession = sessionContext != sessionAtStart
        let staleRequest = activeExpressionRequestID != expressionRequestID
        let requestCancelled = Task.isCancelled || cancellationState.isCancelled
        guard !staleSession, !staleRequest, !requestCancelled else {
            if activeExpressionRequestID == expressionRequestID {
                activeExpressionRequestID = nil
            }
            if requestCancelled, sessionContext == sessionAtStart {
                cancellationState = .none
            }
            #if DEBUG
            orchestrationSteps.append(runtimeOrchestrationStep(
                .sessionPersisted,
                status: .skipped,
                startedAt: Date()
            ))
            orchestrationSteps.append(runtimeOrchestrationStep(
                .presentationUpdated,
                status: .skipped,
                startedAt: Date()
            ))
            appendRuntimeOrchestrationRecord(
                id: orchestrationID,
                session: sessionAtStart,
                startedAt: orchestrationStartedAt,
                context: context,
                result: .failure(.cancelled),
                expressionSnapshot: orchestrationExpressionSnapshot,
                errorCategoryOverride:
                    staleSession ? "stale_session"
                    : (staleRequest ? "stale_request" : "cancelled"),
                sessionWriteStatus: .skipped,
                steps: orchestrationSteps,
                presentationPending: false,
                providerMetadata: orchestrationProviderMetadata,
                emotionalRulesEnabled: orchestrationEmotionalRulesEnabled,
                relationshipDecision: relationshipDecision
            )
            #endif
            return .failure(.cancelled)
        }
        activeExpressionRequestID = nil

        var sessionWriteSucceeded = false
        #if DEBUG
        let sessionWriteStartedAt = Date()
        #endif
        if case .success(let reply) = result {
            _ = commitExpressionResult(
                reply.expression,
                expectedSession: sessionAtStart
            )
            if relationshipControl == nil {
                relationshipDecision = evaluateRelationshipEvidence(
                    reply.relationshipEvidenceCandidates
                )
            }
            sessionWriteSucceeded = persistResidentDialogueExchange(
                userInput: inputText,
                residentReply: reply.replyText,
                session: sessionAtStart
            )
        }
        #if DEBUG
        let sessionWriteStatus: RuntimeOrchestrationSessionWriteStatus
        let sessionStepStatus: RuntimeOrchestrationStepStatus
        switch result {
        case .success:
            sessionWriteStatus = sessionWriteSucceeded ? .saved : .failed
            sessionStepStatus = sessionWriteSucceeded ? .completed : .failed
        case .failure:
            sessionWriteStatus = .skipped
            sessionStepStatus = .skipped
        }
        orchestrationSteps.append(runtimeOrchestrationStep(
            .sessionPersisted,
            status: sessionStepStatus,
            startedAt: sessionWriteStartedAt
        ))
        appendRuntimeOrchestrationRecord(
            id: orchestrationID,
            session: sessionAtStart,
            startedAt: orchestrationStartedAt,
            context: context,
            result: result,
            expressionSnapshot: orchestrationExpressionSnapshot,
            sessionWriteStatus: sessionWriteStatus,
            steps: orchestrationSteps,
            presentationPending: true,
            providerMetadata: orchestrationProviderMetadata,
            emotionalRulesEnabled: orchestrationEmotionalRulesEnabled,
            relationshipDecision: relationshipDecision
        )
        #endif
        return result
    }

    @discardableResult
    func commitExpressionResult(
        _ result: RuntimeExpressionResult,
        expectedSession: RuntimeSessionContext
    ) -> Bool {
        guard sessionContext == expectedSession else { return false }
        currentExpressionResult = result
        return true
    }

    private func persistResidentDialogueExchange(
        userInput: String,
        residentReply: String,
        session: RuntimeSessionContext
    ) -> Bool {
        guard sessionContext == session else { return false }
        var writeSucceeded = true
        let now = Date()
        let existingRecord = try? sessionStore.load(sessionID: session.sessionID.rawValue)
        let lastActivity = existingRecord?.lastActivity ?? ""
        let record = SessionStoreRecord(
            schemaVersion: existingRecord?.schemaVersion ?? SessionStore.schemaVersion,
            residentID: session.residentID,
            sessionID: session.sessionID.rawValue,
            createdAt: existingRecord?.createdAt ?? now,
            updatedAt: now,
            lastUserInput: userInput,
            lastResidentOutput: residentReply,
            lastActivity: lastActivity,
            shutdownState: existingRecord?.shutdownState ?? .unclean,
            recoveryRequired: existingRecord?.recoveryRequired ?? false,
            recoveredAt: existingRecord?.recoveredAt
        )
        do {
            try sessionStore.save(record: record)
        } catch {
            writeSucceeded = false
        }

        let previousEntries = recentDialogueMessages(
            limit: max(0, Self.recentDialogueMessageLimit - 2)
        ).map {
            SessionDialogueEntry(role: $0.role, text: $0.text, timestamp: $0.timestamp)
        }
        let entries = Array((previousEntries + [
            SessionDialogueEntry(role: "user", text: userInput, timestamp: now),
            SessionDialogueEntry(role: "resident", text: residentReply, timestamp: now)
        ]).suffix(Self.recentDialogueMessageLimit))
        do {
            try sessionStore.saveDialogueEntries(entries, for: session.sessionID.rawValue)
        } catch {
            writeSucceeded = false
        }

        let savedDisplayCache = try? sessionStore.loadDisplayCache()
        let displayCache = savedDisplayCache?.residentID == session.residentID
            && savedDisplayCache?.sessionID == session.sessionID.rawValue
            ? savedDisplayCache
            : nil
        do {
            try sessionStore.saveDisplayCache(SessionDisplayCache(
                residentID: session.residentID,
                sessionID: session.sessionID.rawValue,
                lastUserInput: userInput,
                lastResidentOutput: residentReply,
                lastActivity: lastActivity,
                avatarMode: displayCache?.avatarMode ?? "idle",
                avatarPresence: displayCache?.avatarPresence ?? "unknown",
                avatarMoodHint: displayCache?.avatarMoodHint ?? "",
                avatarActivityHint: displayCache?.avatarActivityHint ?? "",
                avatarParticleHint: displayCache?.avatarParticleHint ?? "",
                shutdownState: record.shutdownState,
                recoveryRequired: record.recoveryRequired,
                recoveredAt: record.recoveredAt,
                updatedAt: now
            ))
        } catch {
            writeSucceeded = false
        }
        return writeSucceeded
    }

    private func recentDialogueMessages(limit: Int) -> [ResidentDialogueMessage] {
        guard let sessionContext,
              let record = try? sessionStore.loadMostRecentRecord(),
              record.residentID == sessionContext.residentID,
              record.sessionID == sessionContext.sessionID.rawValue,
              let entries = try? sessionStore.loadMostRecentDialogueEntries(limit: limit) else {
            return []
        }
        return entries.map {
            ResidentDialogueMessage(role: $0.role, text: $0.text, timestamp: $0.timestamp)
        }
    }

    #if DEBUG
    func useRelationshipStateStoreForTesting(
        _ store: RelationshipStateStore
    ) {
        relationshipStateStore = store
    }

    func relationshipProgressionDebugSnapshot()
        -> RuntimeRelationshipDebugSnapshot {
        guard currentRelationshipProgressionProjection != nil,
              let state = currentRelationshipState else {
            return RuntimeRelationshipDebugSnapshot(
                isAvailable: false,
                stageID: nil,
                evidenceIDs: [],
                lastTransitionReason: nil,
                enabled: false,
                revision: nil
            )
        }
        return RuntimeRelationshipDebugSnapshot(
            isAvailable: true,
            stageID: state.currentStage.rawValue,
            evidenceIDs: state.validEvidenceIDs,
            lastTransitionReason: state.lastTransitionReason,
            enabled: state.enabled,
            revision: state.revision
        )
    }

    @discardableResult
    func resetRelationshipProgressionForDebug()
        -> RuntimeRelationshipDebugSnapshot {
        guard let projection = currentRelationshipProgressionProjection,
              let state = currentRelationshipState else {
            return relationshipProgressionDebugSnapshot()
        }
        let reset = RuntimeRelationshipInstanceState(
            residentID: state.residentID,
            currentStage: projection.resetTarget,
            enabled: true,
            lastTransitionReason: "debug_reset",
            updatedAt: Date(),
            revision: state.revision
        )
        _ = persistRelationshipState(
            reset,
            decision: "reset",
            reason: "debug_reset"
        )
        return relationshipProgressionDebugSnapshot()
    }

    func runtimeOrchestrationSnapshot() -> [RuntimeOrchestrationInteraction] {
        runtimeOrchestrationRecords
    }

    func completeRuntimeOrchestrationPresentation(
        interactionID: UUID,
        expectedSessionID: String,
        subtitleState: String,
        particleState: String,
        lifecycleState: RuntimeLifecycleState,
        status: RuntimeOrchestrationStepStatus
    ) {
        guard let index = runtimeOrchestrationRecords.firstIndex(where: { $0.id == interactionID }),
              runtimeOrchestrationRecords[index].sessionID == expectedSessionID,
              (sessionContext?.sessionID.rawValue ?? "") == expectedSessionID else {
            return
        }
        let completedAt = Date()
        let presentationStartedAt = runtimeOrchestrationRecords[index].endedAt
        let duration = max(0, Int(completedAt.timeIntervalSince(presentationStartedAt) * 1_000))
        if let stepIndex = runtimeOrchestrationRecords[index].steps.firstIndex(where: {
            $0.kind == .presentationUpdated
        }) {
            runtimeOrchestrationRecords[index].steps[stepIndex].status = status
            runtimeOrchestrationRecords[index].steps[stepIndex].durationMilliseconds = duration
        }
        runtimeOrchestrationRecords[index].subtitleState = runtimeOrchestrationPresentationState(
            subtitleState
        )
        runtimeOrchestrationRecords[index].particleState = runtimeOrchestrationPresentationState(
            particleState
        )
        runtimeOrchestrationRecords[index].lifecycleState = lifecycleState
        runtimeOrchestrationRecords[index].endedAt = completedAt
    }

    func clearRuntimeOrchestrationRecords() {
        runtimeOrchestrationRecords.removeAll(keepingCapacity: true)
    }

    func clearDialogueTestData() throws -> String? {
        let residentID = currentResidentIdentity?.residentID
        activeExpressionRequestID = nil
        try sessionStore.clearDialogueTestData(
            residentID: residentID,
            currentSessionID: sessionContext?.sessionID.rawValue
        )
        guard let residentID, !residentID.isEmpty else {
            sessionContext = nil
            cancellationState = .none
            return nil
        }

        let sessionID = RuntimeSessionID.make()
        sessionContext = RuntimeSessionContext(residentID: residentID, sessionID: sessionID)
        currentExpressionResult = .neutral(
            source: currentVisualExpressionMapping.source,
            fallbackOccurred:
                currentVisualExpressionMapping.source == .compatibilityFallback
        )
        memoryController.setActiveResidentID(residentID)
        cancellationState = .none
        return sessionID.rawValue
    }

    private func appendRuntimeOrchestrationRecord(
        id: UUID,
        session: RuntimeSessionContext?,
        startedAt: Date,
        context: ResidentDialogueContext?,
        result: Result<RuntimeResidentReply, ProviderRequestError>,
        expressionSnapshot: RuntimeExpressionResult,
        errorCategoryOverride: String? = nil,
        sessionWriteStatus: RuntimeOrchestrationSessionWriteStatus,
        steps: [RuntimeOrchestrationStep],
        presentationPending: Bool,
        providerMetadata: RuntimeOrchestrationProviderMetadata?,
        emotionalRulesEnabled: Bool,
        relationshipDecision:
            RuntimeRelationshipDecision = .unavailable
    ) {
        let expressionResult: RuntimeExpressionResult
        switch result {
        case .success(let reply):
            expressionResult = reply.expression
        case .failure:
            expressionResult = expressionSnapshot
        }
        let normalizedSteps = RuntimeOrchestrationStepKind.allCases.map { kind in
            if let step = steps.first(where: { $0.kind == kind }) {
                return step
            }
            return RuntimeOrchestrationStep(
                kind: kind,
                status: kind == .presentationUpdated && presentationPending ? .pending : .skipped,
                durationMilliseconds: 0
            )
        }
        let interaction = RuntimeOrchestrationInteraction(
            id: id,
            residentID: session?.residentID ?? currentResidentIdentity?.residentID ?? "",
            sessionID: session?.sessionID.rawValue ?? "",
            startedAt: startedAt,
            endedAt: Date(),
            dailyRulesEnabled: context != nil,
            emotionalRulesEnabled: context != nil && emotionalRulesEnabled,
            recentMessageCount: context?.summary.recentMessageCount ?? 0,
            fewShotReferences: context?.selectedFewShotReferences.map {
                RuntimeOrchestrationFewShotReference(exampleID: $0.exampleID, kind: $0.kind)
            } ?? [],
            approvedPreferenceCount: context?.summary.approvedPreferenceCount ?? 0,
            provider: providerMetadata,
            result: runtimeOrchestrationResultStatus(for: result),
            errorCategory: errorCategoryOverride ?? runtimeOrchestrationErrorCategory(for: result),
            sessionWriteStatus: sessionWriteStatus,
            subtitleState: presentationPending ? "pending" : "skipped",
            particleState: presentationPending ? "pending" : "skipped",
            lifecycleState: presentationPending ? .thinking : .idle,
            expressionState: expressionResult.expressionState.rawValue,
            expressionIntensity: expressionResult.expressionIntensity,
            expressionFallbackOccurred:
                expressionResult.expressionFallbackOccurred,
            expressionMapping: expressionResult.expressionMapping,
            expressionMappingSource: expressionResult.mappingSource.rawValue,
            relationshipStageID: relationshipDecision.stageID,
            relationshipEvidenceIDs: relationshipDecision.evidenceIDs,
            relationshipDecision: relationshipDecision.decision,
            relationshipReason: relationshipDecision.reason,
            steps: normalizedSteps
        )
        runtimeOrchestrationRecords.append(interaction)
        if runtimeOrchestrationRecords.count > Self.runtimeOrchestrationCapacity {
            runtimeOrchestrationRecords.removeFirst(
                runtimeOrchestrationRecords.count - Self.runtimeOrchestrationCapacity
            )
        }
    }

    private func runtimeOrchestrationStep(
        _ kind: RuntimeOrchestrationStepKind,
        status: RuntimeOrchestrationStepStatus,
        startedAt: Date
    ) -> RuntimeOrchestrationStep {
        RuntimeOrchestrationStep(
            kind: kind,
            status: status,
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        )
    }

    private func runtimeOrchestrationStepStatus(
        for result: Result<RuntimeResidentReply, ProviderRequestError>
    ) -> RuntimeOrchestrationStepStatus {
        switch result {
        case .success:
            return .completed
        case .failure(.cancelled):
            return .cancelled
        case .failure:
            return .failed
        }
    }

    private func runtimeOrchestrationResultStatus(
        for result: Result<RuntimeResidentReply, ProviderRequestError>
    ) -> RuntimeOrchestrationResultStatus {
        switch result {
        case .success:
            return .success
        case .failure(.cancelled):
            return .cancelled
        case .failure:
            return .failure
        }
    }

    private func runtimeOrchestrationErrorCategory(
        for result: Result<RuntimeResidentReply, ProviderRequestError>
    ) -> String? {
        guard case .failure(let error) = result else { return nil }
        switch error {
        case .unconfigured:
            return "unconfigured"
        case .missingCredential:
            return "missing_credential"
        case .invalidURL:
            return "invalid_url"
        case .unauthorized:
            return "unauthorized"
        case .rateLimited:
            return "rate_limited"
        case .serverUnavailable:
            return "server_unavailable"
        case .timedOut:
            return "timed_out"
        case .cancelled:
            return "cancelled"
        case .networkFailure:
            return "network_failure"
        case .invalidResponse:
            return "invalid_response"
        case .emptyReply:
            return "empty_reply"
        case .residentUnavailable:
            return "resident_unavailable"
        }
    }

    private func runtimeOrchestrationPresentationState(_ value: String) -> String {
        let allowed = [
            "pending", "hidden", "showing", "fading", "idle", "loading", "thinking",
            "speaking", "error", "exit", "unchanged", "skipped", "unknown"
        ]
        return allowed.contains(value) ? value : "unknown"
    }

    #endif

    public func readMemoryValue(for key: String, residentID: String) -> String? {
        guard canAccessPreferenceMemory(residentID: residentID) else { return nil }
        return memoryController.loadValue(for: key, residentID: residentID)
    }

    public func saveMemoryValue(_ value: String, for key: String, residentID: String) {
        guard canAccessPreferenceMemory(residentID: residentID) else { return }
        memoryController.saveValue(value, for: key, residentID: residentID)
    }

    private func canAccessPreferenceMemory(residentID: String) -> Bool {
        guard currentResidentIdentity?.residentID == residentID,
              sessionContext?.residentID == residentID,
              currentMemoryPolicy?.preferenceMemory == .supportedMinimalKV else {
            return false
        }
        return true
    }

    public func cancelCurrentStep() {
        activeExpressionRequestID = nil
        cancellationState = RuntimeCancellationState(isCancelled: true, reason: .cancelled)
    }

    public func interrupt(request: RuntimeCancellationRequest) {
        activeExpressionRequestID = nil
        cancellationState = RuntimeCancellationState(isCancelled: true, reason: request.reason)
    }

    public func runtimeTick(request: RuntimeTickRequest = RuntimeTickRequest()) -> RuntimeTickResponse {
        clockState = RuntimeClockState(tickCount: clockState.tickCount + 1, lastTickAt: Date())
        let traceEvent = TraceEvent(type: .runtimeStep, message: "system.tick no-op")
        let diagnostics = RuntimeDiagnostics(cancellationState: "none")
        return RuntimeTickResponse(clockState: clockState, traceEvent: traceEvent, diagnostics: diagnostics)
    }

    public func currentRuntimeConfig() -> RuntimeConfig {
        hostEnv.runtimeConfig.currentRuntimeConfig()
    }

}
