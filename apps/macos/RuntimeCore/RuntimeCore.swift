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

enum SpeechRouteTurnError: Error, Equatable {
    case invalidASREvent
    case emptyTranscript
    case finalAlreadySubmitted
    case staleGeneration
    case runtime(ProviderRequestError)
}

struct SpeechRouteTurnResult: Equatable {
    let generation: UInt64
    let reply: RuntimeResidentReply

    var canonicalResponseText: String { reply.replyText }
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
    let narrativeMemoryCount: Int
    let prohibitedPatternCount: Int
    let estimatedCharacterCount: Int
}

struct RuntimeNarrativeMemoryContextItem: Equatable {
    let type: RuntimeNarrativeMemoryType
    let summary: String
    let temporalContext: String
}

struct RuntimeRelationshipDialogueContext: Equatable {
    let stageID: String
    let stageBoundary: RuntimeRelationshipStageBoundary
    let allowedEvidenceTypes: [String]

    nonisolated var instruction: String {
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
    let narrativeMemories: [RuntimeNarrativeMemoryContextItem]
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
            RuntimeRelationshipDialogueContext? = nil,
        narrativeMemories:
            [RuntimeNarrativeMemoryContextItem] = []
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
            narrativeMemories: narrativeMemories,
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
            narrativeMemories: narrativeMemories,
            currentUserInput: currentUserInput,
            fallbackText: projection.fallbackBehavior.text,
            summary: ResidentDialogueContextSummary(
                instructionCount: instructionTexts.count,
                scenarioCount: scenarios.count,
                selectedFewShotCount: selectedFewShots.count,
                recentMessageCount: boundedRecentMessages.count,
                approvedPreferenceCount: 0,
                narrativeMemoryCount: narrativeMemories.count,
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
        narrativeMemories: [RuntimeNarrativeMemoryContextItem],
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
            + narrativeMemories.flatMap {
                [$0.type.rawValue, $0.summary, $0.temporalContext]
            }
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

struct RuntimeNarrativeMemoryOrchestrationMetadata: Equatable {
    static let none = RuntimeNarrativeMemoryOrchestrationMetadata(
        retrievalCount: 0,
        retrievedMemoryIDs: [],
        affectedMemoryIDs: [],
        userOperation: "none",
        decision: "no_change",
        reason: "no_user_control"
    )

    let retrievalCount: Int
    let retrievedMemoryIDs: [String]
    let affectedMemoryIDs: [String]
    let userOperation: String
    let decision: String
    let reason: String
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
    let narrativeMemoryDecisions:
        [RuntimeNarrativeMemoryDecision]
    let narrativeMemoryActivity:
        RuntimeNarrativeMemoryOrchestrationMetadata
    var steps: [RuntimeOrchestrationStep]

    var durationMilliseconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt) * 1_000))
    }
}
#endif

private struct RuntimeNormalizedNarrativeMemoryCandidate {
    let candidateID: String
    let memoryType: RuntimeNarrativeMemoryType
    let summary: String
    let sourceTurnIDs: [String]
    let consentSignal: String
    let sensitivityFlags: Set<String>
}

private struct RuntimeNarrativeMemoryCandidateOutcome {
    let decision: RuntimeNarrativeMemoryDecision
    let didMutateStore: Bool
}

private enum RuntimeNarrativeMemoryUserControl: String {
    case remember
    case doNotRemember = "do_not_remember"
    case correct
    case forget
    case clearAll = "clear_all"
}

private struct RuntimeNarrativeMemoryControlResult {
    let control: RuntimeNarrativeMemoryUserControl?
    let affectedMemoryIDs: [String]
    let decision: String
    let reason: String
}

private struct RuntimeNarrativeMemoryRetrieval {
    let memoryID: String
    let item: RuntimeNarrativeMemoryContextItem
}

private struct RuntimeCompiledDialogueContext {
    let context: ResidentDialogueContext
    let retrievedMemoryIDs: [String]
}

nonisolated enum NativeSpeechEventDisposition: Equatable {
    case accepted(NativeSpeechEvent)
    case rejectedStale
    case rejectedLate
    case rejectedOutOfOrder
}

private struct RuntimeNativeSpeechPendingInterrupt: Equatable {
    let interactionID: NativeSpeechInteractionID
    let turnNumber: UInt64
    let turnGeneration: UInt64
}

nonisolated final class RuntimeNativeSpeechInteractionGate:
    @unchecked Sendable {
    private let lock = NSLock()
    private var interaction: NativeSpeechInteraction?
    private var contextProjection: RealtimeSpeechContextProjection?
    private var compilationKey: RealtimeSpeechContextCompilationKey?
    private var pendingInterrupt: RuntimeNativeSpeechPendingInterrupt?

    func current() -> NativeSpeechInteraction? {
        lock.withLock { interaction }
    }

    func reserve(
        _ interaction: NativeSpeechInteraction,
        contextProjection: RealtimeSpeechContextProjection,
        compilationKey: RealtimeSpeechContextCompilationKey
    ) -> Bool {
        lock.withLock {
            guard self.interaction == nil else { return false }
            self.interaction = interaction
            self.contextProjection = contextProjection
            self.compilationKey = compilationKey
            return true
        }
    }

    func activate(_ interaction: NativeSpeechInteraction) -> Bool {
        lock.withLock {
            guard self.interaction?.id == interaction.id else {
                return false
            }
            self.interaction = interaction
            return true
        }
    }

    func setPendingInterrupt(
        interactionID: NativeSpeechInteractionID,
        turnNumber: UInt64,
        turnGeneration: UInt64
    ) -> Bool {
        lock.withLock {
            guard interaction?.id == interactionID else { return false }
            pendingInterrupt = RuntimeNativeSpeechPendingInterrupt(
                interactionID: interactionID,
                turnNumber: turnNumber,
                turnGeneration: turnGeneration
            )
            return true
        }
    }

    func claimPendingInterrupt(
        interactionID: NativeSpeechInteractionID,
        turnNumber: UInt64,
        turnGeneration: UInt64
    ) -> Bool {
        lock.withLock {
            let expected = RuntimeNativeSpeechPendingInterrupt(
                interactionID: interactionID,
                turnNumber: turnNumber,
                turnGeneration: turnGeneration
            )
            guard pendingInterrupt == expected,
                  interaction?.id == interactionID else {
                return false
            }
            pendingInterrupt = nil
            return true
        }
    }

    func currentContextProjection(
        matching interactionID: NativeSpeechInteractionID
    ) -> RealtimeSpeechContextProjection? {
        lock.withLock {
            guard interaction?.id == interactionID else { return nil }
            return contextProjection
        }
    }

    func hasCompilationKey(
        _ key: RealtimeSpeechContextCompilationKey
    ) -> Bool {
        lock.withLock {
            interaction?.id == key.interactionID
                && compilationKey == key
        }
    }

    @discardableResult
    func updateContextProjection(
        _ projection: RealtimeSpeechContextProjection,
        compilationKey: RealtimeSpeechContextCompilationKey
    ) -> Bool {
        lock.withLock {
            guard interaction?.id == projection.interactionID else {
                return false
            }
            contextProjection = projection
            self.compilationKey = compilationKey
            return true
        }
    }

    @discardableResult
    func updateCompilationKey(
        _ key: RealtimeSpeechContextCompilationKey
    ) -> Bool {
        lock.withLock {
            guard interaction?.id == key.interactionID else {
                return false
            }
            compilationKey = key
            return true
        }
    }

    @discardableResult
    func clear(
        matching interactionID: NativeSpeechInteractionID? = nil
    ) -> NativeSpeechInteraction? {
        lock.withLock {
            guard interactionID == nil
                    || interaction?.id == interactionID else {
                return nil
            }
            let cleared = interaction
            interaction = nil
            contextProjection = nil
            compilationKey = nil
            pendingInterrupt = nil
            return cleared
        }
    }
}

nonisolated final class RuntimeNativeSpeechTimeoutHandler:
    @unchecked Sendable {
    private let stateMachine: RealtimeSpeechStateMachine
    private let subtitleStateMachine: RealtimeSpeechSubtitleStateMachine
    private let interactionGate: RuntimeNativeSpeechInteractionGate
    private let inputGate: NativeSpeechInputGate
    private let executionEngine: ExecutionEngine
    private let onTerminal: () -> Void

    init(
        stateMachine: RealtimeSpeechStateMachine,
        subtitleStateMachine: RealtimeSpeechSubtitleStateMachine,
        interactionGate: RuntimeNativeSpeechInteractionGate,
        inputGate: NativeSpeechInputGate,
        executionEngine: ExecutionEngine,
        onTerminal: @escaping () -> Void
    ) {
        self.stateMachine = stateMachine
        self.subtitleStateMachine = subtitleStateMachine
        self.interactionGate = interactionGate
        self.inputGate = inputGate
        self.executionEngine = executionEngine
        self.onTerminal = onTerminal
    }

    func handle(_ request: RealtimeSpeechGuardRequest) async {
        let result = stateMachine.applyTimeout(request)
        guard result.disposition == .applied,
              let interaction = interactionGate.clear(
                matching: request.identity.interactionID
              ) else {
            return
        }
        _ = subtitleStateMachine.terminate(
            interactionID: interaction.id,
            reason: .failed
        )
        inputGate.invalidate(interactionID: interaction.id)
        onTerminal()
        try? await executionEngine.cancelNativeSpeech(
            interactionID: interaction.id,
            reason: .interrupted
        )
        try? await executionEngine.closeNativeSpeech(
            interactionID: interaction.id
        )
    }
}

#if DEBUG
nonisolated struct NativeSpeechToolLifecycleDebugSnapshot: Equatable {
    let executionTaskCount: Int
    let permissionTaskCount: Int
    let pendingPermissionCount: Int
    let handledCallCount: Int
    let hasTurnState: Bool
    let playbackIdentityCount: Int
    let continuationClaimed: Bool
}
#endif

public final class RuntimeCore {
    private static let nativeSpeechToolExecutionCapacity = 8

    private struct SpeechRouteASRFinalState {
        let generation: UInt64
        let transcript: String
        let session: RuntimeSessionContext
        var isSubmitted: Bool
    }

    private struct SpeechRoutePendingTurn {
        let generation: UInt64
        let inputText: String
        let reply: RuntimeResidentReply
        let session: RuntimeSessionContext
        let interactionID: UUID?
    }

    private struct NativeSpeechTurnCommitIdentity: Equatable {
        let interactionID: NativeSpeechInteractionID
        let turnNumber: UInt64
        let turnGeneration: UInt64
    }

    private struct NativeSpeechToolTurnState {
        let identity: NativeSpeechToolTurnIdentity
        var outputs: [NativeSpeechToolOutput]
        var pendingCallIDs: Set<String>
        var responseBoundaryReceived: Bool
        var waitsForPlaybackDrain: Bool
        var playbackDrained: Bool
        var continuationRequested: Bool
    }

    private struct NativeSpeechToolPermissionContext {
        let permissionRequest: NativeSpeechToolPermissionRequest
        let toolRequest: NativeSpeechToolRequest
        let definition: NativeSpeechToolDefinition
        let interaction: NativeSpeechInteraction
    }

    private actor NativeSpeechToolTaskStartGate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func open() {
            guard !isOpen else { return }
            isOpen = true
            let pendingWaiters = waiters
            waiters.removeAll(keepingCapacity: true)
            pendingWaiters.forEach { $0.resume() }
        }
    }

    static let recentDialogueMessageLimit = 8
    static let fewShotSelectionLimit = 4
    static let narrativeMemoryRetrievalLimit = 3

    private let drLoader: DRLoader
    private nonisolated let executionEngine: ExecutionEngine
    private let providerRouter: ProviderRouter
    private let hostEnv: HostEnv
    private let sessionStore: SessionStore
    private let memoryController: MemoryController
    private let realtimeSpeechContextCompiler =
        RealtimeSpeechContextCompiler()
    private var relationshipStateStore = RelationshipStateStore()
    private var narrativeMemoryStore = NarrativeMemoryStore()
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
    private(set) var currentNarrativeMemoryProjection:
        RuntimeNarrativeMemoryProjection?
    private var activeExpressionRequestID: UUID?
    private var speechRouteGeneration: UInt64 = 0
    private var speechRouteASRFinalState: SpeechRouteASRFinalState?
    private var speechRoutePendingTurn: SpeechRoutePendingTurn?
    private var speechRouteASRActive = false
    private var speechRouteTTSActive = false
    private let nativeSpeechInteractionGate =
        RuntimeNativeSpeechInteractionGate()
    private nonisolated let nativeSpeechInputGate = NativeSpeechInputGate()
    private let realtimeSpeechStateMachine = RealtimeSpeechStateMachine()
    private let realtimeSpeechSubtitleStateMachine =
        RealtimeSpeechSubtitleStateMachine()
    private var lastCommittedNativeSpeechTurn:
        NativeSpeechTurnCommitIdentity?
    private var lastAppliedNativeSpeechUserControls:
        NativeSpeechTurnCommitIdentity?
    private var nativeSpeechDiagnosticBuffer:
        NativeSpeechDiagnosticBuffer?
    private var nativeSpeechToolDefinitions: [NativeSpeechToolDefinition] = []
    private var nativeSpeechToolExecutor: any NativeSpeechToolExecuting =
        UnavailableNativeSpeechToolExecutor()
    private var nativeSpeechToolPermissionResolver:
        any NativeSpeechToolPermissionResolving =
            UnavailableNativeSpeechToolPermissionResolver()
    private var handledNativeSpeechToolCalls:
        Set<NativeSpeechToolCallIdentity> = []
    private var nativeSpeechToolTurnState: NativeSpeechToolTurnState?
    private var nativeSpeechToolExecutionTasks:
        [NativeSpeechToolCallIdentity: Task<Void, Never>] = [:]
    private var nativeSpeechToolPermissionTasks:
        [NativeSpeechToolCallIdentity: Task<Void, Never>] = [:]
    private var pendingNativeSpeechToolPermissions:
        [NativeSpeechToolCallIdentity: NativeSpeechToolPermissionContext] = [:]
    private let nativeSpeechToolContinuationClaimLock = NSLock()
    private var nativeSpeechTurnsWithOutputAudio:
        Set<NativeSpeechToolTurnIdentity> = []
    private let realtimeSpeechGuardScheduler =
        RealtimeSpeechGuardScheduler()
    private lazy var realtimeSpeechTimeoutHandler =
        RuntimeNativeSpeechTimeoutHandler(
            stateMachine: realtimeSpeechStateMachine,
            subtitleStateMachine: realtimeSpeechSubtitleStateMachine,
            interactionGate: nativeSpeechInteractionGate,
            inputGate: nativeSpeechInputGate,
            executionEngine: executionEngine,
            onTerminal: { [weak self] in
                self?.resetNativeSpeechToolState()
            }
        )
    private var realtimeSpeechContextSourceRevision: UInt64 = 0
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

    func startSpeechRouteASR(
        locale: String? = nil
    ) async -> Result<UInt64, SpeechRouteError> {
        activeExpressionRequestID = nil
        speechRouteGeneration &+= 1
        speechRouteASRFinalState = nil
        speechRoutePendingTurn = nil
        speechRouteASRActive = false
        speechRouteTTSActive = false
        let generation = speechRouteGeneration
        do {
            try await executionEngine.startASR(
                request: ASRStartRequest(
                    generation: generation,
                    locale: locale
                )
            )
            speechRouteASRActive = true
            return .success(generation)
        } catch let error as SpeechRouteError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    func sendSpeechRouteASRAudio(
        _ input: ASRAudioInput
    ) async throws {
        guard input.generation == speechRouteGeneration else {
            throw SpeechRouteError.staleGeneration
        }
        try await executionEngine.sendASRAudio(input)
    }

    func receiveSpeechRouteASREvent(
        generation: UInt64
    ) async throws -> ASREvent {
        guard generation == speechRouteGeneration else {
            return ASREvent(
                generation: generation,
                kind: .staleGeneration
            )
        }
        let event = try await executionEngine.receiveASREvent(
            generation: generation
        )
        guard event.generation == speechRouteGeneration else {
            return ASREvent(
                generation: event.generation,
                kind: .staleGeneration
            )
        }
        if case .finalTranscript(let transcript) = event.kind {
            let normalized = transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !normalized.isEmpty,
               speechRouteASRFinalState == nil,
               let sessionContext {
                speechRouteASRFinalState = SpeechRouteASRFinalState(
                    generation: event.generation,
                    transcript: normalized,
                    session: sessionContext,
                    isSubmitted: false
                )
            }
        }
        return event
    }

    func submitSpeechRouteASRFinal(
        _ event: ASREvent,
        interactionID: UUID? = nil
    ) async -> Result<SpeechRouteTurnResult, SpeechRouteTurnError> {
        guard event.generation == speechRouteGeneration else {
            return .failure(.staleGeneration)
        }
        guard case .finalTranscript(let transcript) = event.kind else {
            return .failure(.invalidASREvent)
        }
        let inputText = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !inputText.isEmpty else {
            return .failure(.emptyTranscript)
        }
        guard var finalState = speechRouteASRFinalState,
              finalState.generation == event.generation,
              finalState.transcript == inputText,
              finalState.session == sessionContext else {
            return .failure(.invalidASREvent)
        }
        guard !finalState.isSubmitted else {
            return .failure(.finalAlreadySubmitted)
        }
        finalState.isSubmitted = true
        speechRouteASRFinalState = finalState

        let result = await requestResidentReply(
            inputText: inputText,
            interactionID: interactionID,
            defersSuccessfulCommit: true
        )
        guard event.generation == speechRouteGeneration else {
            return .failure(.staleGeneration)
        }
        switch result {
        case .failure(let error):
            return .failure(.runtime(error))
        case .success(let reply):
            guard let sessionContext,
                  sessionContext == finalState.session else {
                return .failure(.staleGeneration)
            }
            speechRoutePendingTurn = SpeechRoutePendingTurn(
                generation: event.generation,
                inputText: inputText,
                reply: reply,
                session: sessionContext,
                interactionID: interactionID
            )
            return .success(SpeechRouteTurnResult(
                generation: event.generation,
                reply: reply
            ))
        }
    }

    func startSpeechRouteTTS(
        request: TTSSynthesisRequest
    ) async -> Result<Void, SpeechRouteError> {
        guard request.generation == speechRouteGeneration,
              let pendingTurn = speechRoutePendingTurn,
              pendingTurn.generation == request.generation,
              pendingTurn.session == sessionContext else {
            return .failure(.staleGeneration)
        }
        guard request.canonicalResponseText == pendingTurn.reply.replyText else {
            return .failure(.invalidEvent)
        }
        do {
            try await executionEngine.startTTS(request: request)
            speechRouteTTSActive = true
            return .success(())
        } catch let error as SpeechRouteError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    func receiveSpeechRouteTTSEvent(
        generation: UInt64
    ) async throws -> TTSEvent {
        guard generation == speechRouteGeneration else {
            throw SpeechRouteError.staleGeneration
        }
        let event = try await executionEngine.receiveTTSEvent(
            generation: generation
        )
        guard event.generation == speechRouteGeneration else {
            throw SpeechRouteError.staleGeneration
        }
        return event
    }

    func finishSpeechRouteASR(
        generation: UInt64
    ) async -> Result<Void, SpeechRouteError> {
        guard generation == speechRouteGeneration else {
            return .failure(.staleGeneration)
        }
        guard speechRouteASRActive else { return .success(()) }
        do {
            try await executionEngine.closeASR(generation: generation)
            speechRouteASRActive = false
            return .success(())
        } catch let error as SpeechRouteError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    func finishSpeechRouteTTS(
        generation: UInt64
    ) async -> Result<Void, SpeechRouteError> {
        guard generation == speechRouteGeneration else {
            return .failure(.staleGeneration)
        }
        guard speechRouteTTSActive else { return .success(()) }
        do {
            try await executionEngine.closeTTS(generation: generation)
            speechRouteTTSActive = false
            return .success(())
        } catch let error as SpeechRouteError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    func commitSpeechRoutePlayback(
        generation: UInt64
    ) -> Result<SpeechRouteTurnResult, SpeechRouteError> {
        guard generation == speechRouteGeneration,
              let pendingTurn = speechRoutePendingTurn,
              pendingTurn.generation == generation,
              pendingTurn.session == sessionContext else {
            return .failure(.staleGeneration)
        }
        speechRoutePendingTurn = nil

        let relationshipControl = relationshipUserControl(
            for: pendingTurn.inputText
        )
        if relationshipControl != nil {
            _ = applyRelationshipUserControl(relationshipControl)
        } else {
            _ = evaluateRelationshipEvidence(
                pendingTurn.reply.relationshipEvidenceCandidates
            )
        }
        let narrativeMemoryControl = narrativeMemoryUserControl(
            for: pendingTurn.inputText
        )
        _ = applyNarrativeMemoryUserControl(
            narrativeMemoryControl,
            input: pendingTurn.inputText,
            residentID: pendingTurn.session.residentID
        )
        _ = evaluateNarrativeMemoryCandidates(
            pendingTurn.reply.narrativeMemoryCandidates,
            session: pendingTurn.session,
            userControl: narrativeMemoryControl
        )
        _ = commitExpressionResult(
            pendingTurn.reply.expression,
            expectedSession: pendingTurn.session
        )
        guard persistResidentDialogueExchange(
            userInput: pendingTurn.inputText,
            residentReply: pendingTurn.reply.replyText,
            session: pendingTurn.session
        ) else {
            completeSpeechRoutePersistence(
                interactionID: pendingTurn.interactionID,
                succeeded: false
            )
            return .failure(.transportFailure)
        }
        completeSpeechRoutePersistence(
            interactionID: pendingTurn.interactionID,
            succeeded: true
        )
        return .success(SpeechRouteTurnResult(
            generation: generation,
            reply: pendingTurn.reply
        ))
    }

    func cancelSpeechRoute(
        generation: UInt64
    ) async -> Result<Void, SpeechRouteError> {
        guard generation == speechRouteGeneration else {
            return .failure(.staleGeneration)
        }
        activeExpressionRequestID = nil
        speechRouteGeneration &+= 1
        speechRouteASRFinalState = nil
        speechRoutePendingTurn = nil
        let providerError = await stopSpeechRouteProviders(
            generation: generation,
            close: false
        )
        if let providerError {
            return .failure(providerError)
        }
        return .success(())
    }

    func closeSpeechRoute(
        generation: UInt64
    ) async -> Result<Void, SpeechRouteError> {
        guard generation == speechRouteGeneration else {
            return .failure(.staleGeneration)
        }
        activeExpressionRequestID = nil
        speechRouteGeneration &+= 1
        speechRouteASRFinalState = nil
        speechRoutePendingTurn = nil
        let providerError = await stopSpeechRouteProviders(
            generation: generation,
            close: true
        )
        if let providerError {
            return .failure(providerError)
        }
        return .success(())
    }

    private func stopSpeechRouteProviders(
        generation: UInt64,
        close: Bool
    ) async -> SpeechRouteError? {
        var firstError: SpeechRouteError?
        if speechRouteASRActive {
            do {
                if close {
                    try await executionEngine.closeASR(generation: generation)
                } else {
                    try await executionEngine.cancelASR(generation: generation)
                }
            } catch let error as SpeechRouteError {
                if error != .unavailable {
                    firstError = error
                }
            } catch {
                firstError = .transportFailure
            }
            speechRouteASRActive = false
        }

        if speechRouteTTSActive {
            do {
                if close {
                    try await executionEngine.closeTTS(generation: generation)
                } else {
                    try await executionEngine.cancelTTS(generation: generation)
                }
            } catch let error as SpeechRouteError {
                if error != .unavailable {
                    firstError = firstError ?? error
                }
            } catch {
                firstError = firstError ?? .transportFailure
            }
            speechRouteTTSActive = false
        }
        return firstError
    }

    func attachNativeSpeechDiagnosticBuffer(
        _ buffer: NativeSpeechDiagnosticBuffer
    ) {
        nativeSpeechDiagnosticBuffer = buffer
    }

    func configureNativeSpeechToolPermissionResolver(
        _ resolver: any NativeSpeechToolPermissionResolving
    ) {
        nativeSpeechToolPermissionResolver = resolver
    }

    #if DEBUG
    func configureNativeSpeechToolsForTesting(
        definitions: [NativeSpeechToolDefinition],
        executor: any NativeSpeechToolExecuting
    ) {
        nativeSpeechToolDefinitions = definitions
        nativeSpeechToolExecutor = executor
    }
    #endif

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
            nativeSpeechInteractionGate.clear()
            resetRealtimeSpeechState()
            realtimeSpeechContextSourceRevision &+= 1
            sessionContext = RuntimeSessionContext(residentID: loadedDR.residentID, sessionID: sessionID)
            activeExpressionRequestID = nil
            invalidateNativeSpeechInput()
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
            currentNarrativeMemoryProjection =
                loadedDR.narrativeMemoryProjection
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
        nativeSpeechInteractionGate.clear()
        resetRealtimeSpeechState()
        sessionContext = RuntimeSessionContext(
            residentID: record.residentID,
            sessionID: RuntimeSessionID(rawValue: record.sessionID)
        )
        activeExpressionRequestID = nil
        invalidateNativeSpeechInput()
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

    func compileResidentDialogueContext(
        currentUserInput: String
    ) -> ResidentDialogueContext? {
        compiledResidentDialogueContext(
            currentUserInput: currentUserInput
        )?.context
    }

    private func compiledResidentDialogueContext(
        currentUserInput: String
    ) -> RuntimeCompiledDialogueContext? {
        guard let source = currentDialogueContextSource,
              sessionContext?.residentID == source.identity.residentID else {
            return nil
        }
        let retrieved = retrieveNarrativeMemories(
            relevantTo: currentUserInput,
            residentID: source.identity.residentID
        )
        let context = source.compile(
            currentUserInput: currentUserInput,
            recentMessages: recentDialogueMessages(limit: Self.recentDialogueMessageLimit),
            recentMessageLimit: Self.recentDialogueMessageLimit,
            fewShotLimit: Self.fewShotSelectionLimit,
            relationshipProgression: relationshipDialogueContext(),
            narrativeMemories: retrieved.map(\.item)
        )
        return RuntimeCompiledDialogueContext(
            context: context,
            retrievedMemoryIDs: retrieved.map(\.memoryID)
        )
    }

    private func retrieveNarrativeMemories(
        relevantTo input: String,
        residentID: String
    ) -> [RuntimeNarrativeMemoryRetrieval] {
        guard let projection = currentNarrativeMemoryProjection,
              projection.enabled,
              Set(
                  projection.retrievalPolicy.allowedLifecycleStates
              ) == [.active],
              projection.retrievalPolicy.excludedLifecycleStates
                .contains(.deleted),
              projection.retrievalPolicy.excludedLifecycleStates
                .contains(.superseded),
              projection.retrievalPolicy.excludedLifecycleStates
                .contains(.rejected),
              let snapshot = try? narrativeMemoryStore.load(
                  residentID: residentID
              ) else {
            return []
        }
        return snapshot.records
            .filter {
                $0.residentID == residentID
                    && $0.status == .active
                    && projection.allowedMemoryTypes
                        .contains($0.type)
                    && (
                        $0.consentState == .notRequired
                            || $0.consentState == .granted
                    )
                    && !$0.summary.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    && permanentlyForbiddenNarrativeContentCategory(
                        in: $0.summary
                    ) == nil
            }
            .compactMap { record -> (
                RuntimeNarrativeMemoryRecord,
                Int
            )? in
                let score = narrativeMemoryRelevanceScore(
                    input,
                    record.summary
                )
                return score > 0 ? (record, score) : nil
            }
            .sorted {
                $0.1 == $1.1
                    ? $0.0.updatedAt > $1.0.updatedAt
                    : $0.1 > $1.1
            }
            .prefix(Self.narrativeMemoryRetrievalLimit)
            .map {
                RuntimeNarrativeMemoryRetrieval(
                    memoryID: $0.0.memoryID,
                    item: RuntimeNarrativeMemoryContextItem(
                        type: $0.0.type,
                        summary: $0.0.summary,
                        temporalContext: narrativeMemoryTemporalContext(
                            for: $0.0.updatedAt
                        )
                    )
                )
            }
    }

    private func narrativeMemoryRelevanceScore(
        _ input: String,
        _ summary: String
    ) -> Int {
        let inputTerms = narrativeMemoryTopicTerms(input)
        let summaryTerms = narrativeMemoryTopicTerms(summary)
        return inputTerms.intersection(summaryTerms).count
    }

    private func narrativeMemoryTopicTerms(
        _ text: String
    ) -> Set<String> {
        let words = text.lowercased().split {
            !$0.isLetter && !$0.isNumber
        }.map(String.init)
        var terms = Set(words.filter { $0.count >= 2 })
        for word in words where containsCJK(word) {
            let characters = Array(word)
            guard characters.count >= 2 else { continue }
            for index in 0..<(characters.count - 1) {
                terms.insert(String(characters[index...index + 1]))
            }
        }
        return terms
    }

    private func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value)
        }
    }

    private func narrativeMemoryTemporalContext(
        for date: Date
    ) -> String {
        let age = max(0, Date().timeIntervalSince(date))
        if age < 86_400 {
            return "recent"
        }
        if age < 604_800 {
            return "within_last_week"
        }
        if age < 2_592_000 {
            return "within_last_month"
        }
        return "earlier"
    }

    private func narrativeMemoryUserControl(
        for input: String
    ) -> RuntimeNarrativeMemoryUserControl? {
        let normalized = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let controls: [([String], RuntimeNarrativeMemoryUserControl)] = [
            (
                [
                    "清空全部叙事记忆",
                    "清空所有叙事记忆",
                    "清空我的全部记忆",
                    "清空当前居民全部叙事记忆",
                    "清空叙事记忆",
                    "clear all narrative memories"
                ],
                .clearAll
            ),
            (
                [
                    "不要记住",
                    "别记住",
                    "不要记录",
                    "不需要记",
                    "do not remember",
                    "don't remember"
                ],
                .doNotRemember
            ),
            (
                [
                    "我之前说错了",
                    "更正记忆",
                    "修正记忆",
                    "修正已有记忆",
                    "请改成",
                    "correct that memory"
                ],
                .correct
            ),
            (
                [
                    "请记住",
                    "帮我记住",
                    "记一下",
                    "不要忘记",
                    "别忘记",
                    "remember that"
                ],
                .remember
            ),
            (
                [
                    "忘记",
                    "删除这条记忆",
                    "forget"
                ],
                .forget
            )
        ]
        return controls.first {
            phrases, _ in phrases.contains {
                normalized.contains($0)
            }
        }?.1
    }

    private func applyNarrativeMemoryUserControl(
        _ control: RuntimeNarrativeMemoryUserControl?,
        input: String,
        residentID: String
    ) -> RuntimeNarrativeMemoryControlResult {
        guard let control else {
            return RuntimeNarrativeMemoryControlResult(
                control: nil,
                affectedMemoryIDs: [],
                decision: "no_change",
                reason: "no_user_control"
            )
        }
        guard let projection = currentNarrativeMemoryProjection,
              projection.enabled else {
            return RuntimeNarrativeMemoryControlResult(
                control: control,
                affectedMemoryIDs: [],
                decision: "feature_unavailable",
                reason: "projection_missing_or_disabled"
            )
        }
        switch control {
        case .clearAll:
            return clearNarrativeMemories(
                residentID: residentID,
                projection: projection
            )
        case .forget:
            return forgetNarrativeMemory(
                relevantTo: input,
                residentID: residentID,
                projection: projection
            )
        case .doNotRemember:
            return RuntimeNarrativeMemoryControlResult(
                control: control,
                affectedMemoryIDs: [],
                decision: "applied",
                reason: "user_blocked_memory_write"
            )
        case .remember, .correct:
            return RuntimeNarrativeMemoryControlResult(
                control: control,
                affectedMemoryIDs: [],
                decision: "pending_candidate",
                reason: "awaiting_valid_candidate"
            )
        }
    }

    private func clearNarrativeMemories(
        residentID: String,
        projection: RuntimeNarrativeMemoryProjection
    ) -> RuntimeNarrativeMemoryControlResult {
        guard projection.deletionPolicy.clearAll else {
            return narrativeMemoryControlFailure(
                .clearAll,
                reason: "clear_all_not_allowed"
            )
        }
        do {
            guard let snapshot = try narrativeMemoryStore.load(
                residentID: residentID
            ) else {
                return narrativeMemoryControlFailure(
                    .clearAll,
                    reason: "no_active_memory"
                )
            }
            var records = snapshot.records
            let indexes = records.indices.filter {
                records[$0].status == .active
            }
            guard !indexes.isEmpty else {
                return narrativeMemoryControlFailure(
                    .clearAll,
                    reason: "no_active_memory"
                )
            }
            let now = Date()
            for index in indexes {
                records[index].status = .deleted
                records[index].updatedAt = now
            }
            try narrativeMemoryStore.save(
                RuntimeNarrativeMemoryStoreSnapshot(
                    residentID: residentID,
                    records: records
                )
            )
            realtimeSpeechContextSourceRevision &+= 1
            return RuntimeNarrativeMemoryControlResult(
                control: .clearAll,
                affectedMemoryIDs: indexes.map {
                    records[$0].memoryID
                },
                decision: "applied",
                reason: "user_cleared_all"
            )
        } catch {
            return narrativeMemoryControlFailure(
                .clearAll,
                reason: "persistence_failed"
            )
        }
    }

    private func forgetNarrativeMemory(
        relevantTo input: String,
        residentID: String,
        projection: RuntimeNarrativeMemoryProjection
    ) -> RuntimeNarrativeMemoryControlResult {
        guard projection.deletionPolicy.singleItemDelete else {
            return narrativeMemoryControlFailure(
                .forget,
                reason: "single_delete_not_allowed"
            )
        }
        do {
            guard let snapshot = try narrativeMemoryStore.load(
                residentID: residentID
            ) else {
                return narrativeMemoryControlFailure(
                    .forget,
                    reason: "memory_not_found"
                )
            }
            var records = snapshot.records
            let match = records.indices
                .filter { records[$0].status == .active }
                .map {
                    (
                        $0,
                        narrativeMemoryRelevanceScore(
                            input,
                            records[$0].summary
                        )
                    )
                }
                .filter { $0.1 > 0 }
                .max {
                    $0.1 == $1.1
                        ? records[$0.0].updatedAt
                            < records[$1.0].updatedAt
                        : $0.1 < $1.1
                }
            guard let index = match?.0 else {
                return narrativeMemoryControlFailure(
                    .forget,
                    reason: "memory_not_found"
                )
            }
            records[index].status = .deleted
            records[index].updatedAt = Date()
            try narrativeMemoryStore.save(
                RuntimeNarrativeMemoryStoreSnapshot(
                    residentID: residentID,
                    records: records
                )
            )
            realtimeSpeechContextSourceRevision &+= 1
            return RuntimeNarrativeMemoryControlResult(
                control: .forget,
                affectedMemoryIDs: [records[index].memoryID],
                decision: "applied",
                reason: "user_forgot_memory"
            )
        } catch {
            return narrativeMemoryControlFailure(
                .forget,
                reason: "persistence_failed"
            )
        }
    }

    private func narrativeMemoryControlFailure(
        _ control: RuntimeNarrativeMemoryUserControl,
        reason: String
    ) -> RuntimeNarrativeMemoryControlResult {
        RuntimeNarrativeMemoryControlResult(
            control: control,
            affectedMemoryIDs: [],
            decision: "not_applied",
            reason: reason
        )
    }

    private func finalizedNarrativeMemoryControlResult(
        _ result: RuntimeNarrativeMemoryControlResult,
        candidateDecisions: [RuntimeNarrativeMemoryDecision],
        providerSucceeded: Bool
    ) -> RuntimeNarrativeMemoryControlResult {
        guard result.decision == "pending_candidate",
              let control = result.control else {
            return result
        }
        guard providerSucceeded else {
            return narrativeMemoryControlFailure(
                control,
                reason: "provider_failed"
            )
        }
        let acceptedKinds: Set<RuntimeNarrativeMemoryDecisionKind>
        switch control {
        case .remember:
            acceptedKinds = [.accept, .merge]
        case .correct:
            acceptedKinds = [.supersede]
        case .doNotRemember, .forget, .clearAll:
            acceptedKinds = []
        }
        let applied = candidateDecisions.filter {
            acceptedKinds.contains($0.decision)
        }
        guard !applied.isEmpty else {
            return narrativeMemoryControlFailure(
                control,
                reason: "valid_candidate_missing"
            )
        }
        return RuntimeNarrativeMemoryControlResult(
            control: control,
            affectedMemoryIDs: applied.compactMap(\.memoryID),
            decision: "applied",
            reason: control == .remember
                ? "user_remembered_memory"
                : "user_corrected_memory"
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
            realtimeSpeechContextSourceRevision &+= 1
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

    private func evaluateNarrativeMemoryCandidates(
        _ candidates: [ProviderNarrativeMemoryCandidate],
        session: RuntimeSessionContext,
        userControl: RuntimeNarrativeMemoryUserControl? = nil
    ) -> [RuntimeNarrativeMemoryDecision] {
        guard !candidates.isEmpty,
              let projection = currentNarrativeMemoryProjection,
              projection.enabled else {
            return []
        }
        if userControl == .doNotRemember
            || userControl == .forget
            || userControl == .clearAll {
            return candidates.map {
                rejectedNarrativeMemoryDecision(
                    candidateID: safeNarrativeCandidateID(
                        $0.candidateID
                    ),
                    memoryType: $0.memoryType,
                    reason: "user_control_preempted_candidate"
                )
            }
        }

        let existingSnapshot: RuntimeNarrativeMemoryStoreSnapshot?
        do {
            existingSnapshot = try narrativeMemoryStore.load(
                residentID: session.residentID
            )
        } catch {
            return candidates.map {
                rejectedNarrativeMemoryDecision(
                    candidateID: safeNarrativeCandidateID(
                        $0.candidateID
                    ),
                    memoryType: nil,
                    reason: "store_unavailable"
                )
            }
        }

        var records = existingSnapshot?.records ?? []
        var outcomes = [RuntimeNarrativeMemoryCandidateOutcome]()
        for candidate in candidates {
            outcomes.append(
                evaluateNarrativeMemoryCandidate(
                    candidate,
                    projection: projection,
                    session: session,
                    userControl: userControl,
                    records: &records
                )
            )
        }

        guard outcomes.contains(where: \.didMutateStore) else {
            return outcomes.map(\.decision)
        }
        do {
            try narrativeMemoryStore.save(
                RuntimeNarrativeMemoryStoreSnapshot(
                    residentID: session.residentID,
                    records: records
                )
            )
            realtimeSpeechContextSourceRevision &+= 1
            return outcomes.map(\.decision)
        } catch {
            return outcomes.map { outcome in
                guard outcome.didMutateStore else {
                    return outcome.decision
                }
                return rejectedNarrativeMemoryDecision(
                    candidateID: outcome.decision.candidateID,
                    memoryType: outcome.decision.memoryType,
                    reason: "persistence_failed"
                )
            }
        }
    }

    private func evaluateNarrativeMemoryCandidate(
        _ candidate: ProviderNarrativeMemoryCandidate,
        projection: RuntimeNarrativeMemoryProjection,
        session: RuntimeSessionContext,
        userControl: RuntimeNarrativeMemoryUserControl?,
        records: inout [RuntimeNarrativeMemoryRecord]
    ) -> RuntimeNarrativeMemoryCandidateOutcome {
        guard let normalized = normalizedNarrativeMemoryCandidate(
            candidate,
            projection: projection,
            userControl: userControl
        ) else {
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: rejectedNarrativeMemoryDecision(
                    candidateID: safeNarrativeCandidateID(
                        candidate.candidateID
                    ),
                    memoryType: RuntimeNarrativeMemoryType(
                        rawValue: candidate.memoryType
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .lowercased()
                    )?.rawValue,
                    reason: narrativeMemoryCandidateRejectionReason(
                        candidate,
                        projection: projection
                    )
                ),
                didMutateStore: false
            )
        }

        if permanentlyForbiddenNarrativeContentCategory(
            in: normalized.summary
        ) != nil {
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: rejectedNarrativeMemoryDecision(
                    candidateID: normalized.candidateID,
                    memoryType: normalized.memoryType.rawValue,
                    reason: "permanently_forbidden_content"
                ),
                didMutateStore: false
            )
        }
        if !normalized.sensitivityFlags.isDisjoint(
            with: projection.sensitivityPolicy
                .permanentlyForbiddenCategories
        ) {
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: rejectedNarrativeMemoryDecision(
                    candidateID: normalized.candidateID,
                    memoryType: normalized.memoryType.rawValue,
                    reason: "permanently_forbidden_content"
                ),
                didMutateStore: false
            )
        }
        if !normalized.sensitivityFlags.isDisjoint(
            with: projection.forbiddenContentRules
        ) {
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: rejectedNarrativeMemoryDecision(
                    candidateID: normalized.candidateID,
                    memoryType: normalized.memoryType.rawValue,
                    reason: "forbidden_content"
                ),
                didMutateStore: false
            )
        }

        switch normalized.consentSignal {
        case "forget_requested":
            return deleteNarrativeMemory(
                normalized,
                records: &records
            )
        case "user_correction":
            return supersedeNarrativeMemory(
                normalized,
                session: session,
                records: &records
            )
        case "consent_missing":
            return rejectNarrativeMemoryCandidate(
                normalized,
                session: session,
                reason: "consent_required",
                records: &records
            )
        case "consent_rejected":
            return rejectNarrativeMemoryCandidate(
                normalized,
                session: session,
                reason: "consent_rejected",
                records: &records
            )
        case "not_required",
             "explicit_remember_request",
             "explicit_consent":
            break
        default:
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: rejectedNarrativeMemoryDecision(
                    candidateID: normalized.candidateID,
                    memoryType: normalized.memoryType.rawValue,
                    reason: "invalid_consent_signal"
                ),
                didMutateStore: false
            )
        }

        if !normalized.sensitivityFlags.isEmpty,
           normalized.consentSignal != "explicit_remember_request",
           normalized.consentSignal != "explicit_consent" {
            return rejectNarrativeMemoryCandidate(
                normalized,
                session: session,
                reason: "consent_required",
                records: &records
            )
        }
        return acceptOrMergeNarrativeMemory(
            normalized,
            session: session,
            records: &records
        )
    }

    private func normalizedNarrativeMemoryCandidate(
        _ candidate: ProviderNarrativeMemoryCandidate,
        projection: RuntimeNarrativeMemoryProjection,
        userControl: RuntimeNarrativeMemoryUserControl?
    ) -> RuntimeNormalizedNarrativeMemoryCandidate? {
        let candidateID = safeNarrativeCandidateID(
            candidate.candidateID
        )
        let rawMemoryType = candidate.memoryType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let summary = candidate.summary.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let evidenceSource = candidate.evidenceSource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let inputClassification = candidate.inputClassification
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var consentSignal = candidate.consentSignal
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if userControl == .remember {
            consentSignal = "explicit_remember_request"
        } else if userControl == .correct {
            consentSignal = "user_correction"
        }
        let sourceTurnIDs = Array(Set(
            candidate.sourceTurnIDs.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        )).sorted()
        let sensitivityFlags = Set(
            candidate.sensitivityFlags.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }.filter { !$0.isEmpty }
        )

        guard candidateID != "invalid_candidate",
              let memoryType = RuntimeNarrativeMemoryType(
                  rawValue: rawMemoryType
              ),
              projection.allowedMemoryTypes.contains(memoryType),
              !summary.isEmpty,
              summary.count <= 500,
              !sourceTurnIDs.isEmpty,
              sourceTurnIDs.count <= 16,
              evidenceSource == "explicit_user_statement",
              inputClassification == "explicit_memory_worthy",
              !consentSignal.isEmpty else {
            return nil
        }
        return RuntimeNormalizedNarrativeMemoryCandidate(
            candidateID: candidateID,
            memoryType: memoryType,
            summary: summary,
            sourceTurnIDs: sourceTurnIDs,
            consentSignal: consentSignal,
            sensitivityFlags: sensitivityFlags
        )
    }

    private func narrativeMemoryCandidateRejectionReason(
        _ candidate: ProviderNarrativeMemoryCandidate,
        projection: RuntimeNarrativeMemoryProjection
    ) -> String {
        let rawMemoryType = candidate.memoryType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if RuntimeNarrativeMemoryType(rawValue: rawMemoryType) == nil {
            return "memory_type_not_allowed"
        }
        let evidenceSource = candidate.evidenceSource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let inputClassification = candidate.inputClassification
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if evidenceSource != "explicit_user_statement"
            || projection.candidateEvidenceRules.excludedInputs
                .contains(inputClassification)
            || inputClassification != "explicit_memory_worthy" {
            return "source_not_eligible"
        }
        return "invalid_candidate"
    }

    private func acceptOrMergeNarrativeMemory(
        _ candidate: RuntimeNormalizedNarrativeMemoryCandidate,
        session: RuntimeSessionContext,
        records: inout [RuntimeNarrativeMemoryRecord]
    ) -> RuntimeNarrativeMemoryCandidateOutcome {
        if let index = records.firstIndex(where: {
            $0.status == .active
                && $0.type == candidate.memoryType
                && (
                    normalizedNarrativeSummary($0.summary)
                        == normalizedNarrativeSummary(
                            candidate.summary
                        )
                    || Set($0.sourceTurnIDs)
                        == Set(candidate.sourceTurnIDs)
                )
        }) {
            let existing = records[index]
            records[index] = RuntimeNarrativeMemoryRecord(
                memoryID: existing.memoryID,
                residentID: existing.residentID,
                type: existing.type,
                summary: existing.summary,
                sourceSessionID: existing.sourceSessionID,
                sourceTurnIDs: Array(Set(
                    existing.sourceTurnIDs
                        + candidate.sourceTurnIDs
                )).sorted(),
                status: .active,
                consentState: existing.consentState,
                createdAt: existing.createdAt,
                updatedAt: Date(),
                supersedesMemoryID: existing.supersedesMemoryID
            )
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: RuntimeNarrativeMemoryDecision(
                    candidateID: candidate.candidateID,
                    memoryID: existing.memoryID,
                    memoryType: existing.type.rawValue,
                    decision: .merge,
                    reason: "duplicate_merged"
                ),
                didMutateStore: true
            )
        }

        let record = activeNarrativeMemoryRecord(
            candidate,
            session: session,
            supersedesMemoryID: nil
        )
        records.append(record)
        return RuntimeNarrativeMemoryCandidateOutcome(
            decision: RuntimeNarrativeMemoryDecision(
                candidateID: candidate.candidateID,
                memoryID: record.memoryID,
                memoryType: record.type.rawValue,
                decision: .accept,
                reason: "candidate_accepted"
            ),
            didMutateStore: true
        )
    }

    private func supersedeNarrativeMemory(
        _ candidate: RuntimeNormalizedNarrativeMemoryCandidate,
        session: RuntimeSessionContext,
        records: inout [RuntimeNarrativeMemoryRecord]
    ) -> RuntimeNarrativeMemoryCandidateOutcome {
        guard let index = records.indices
            .filter({
                records[$0].status == .active
                    && records[$0].type == candidate.memoryType
            })
            .max(by: {
                records[$0].updatedAt < records[$1].updatedAt
            }) else {
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: rejectedNarrativeMemoryDecision(
                    candidateID: candidate.candidateID,
                    memoryType: candidate.memoryType.rawValue,
                    reason: "supersession_target_not_found"
                ),
                didMutateStore: false
            )
        }
        let existing = records[index]
        records[index] = RuntimeNarrativeMemoryRecord(
            memoryID: existing.memoryID,
            residentID: existing.residentID,
            type: existing.type,
            summary: existing.summary,
            sourceSessionID: existing.sourceSessionID,
            sourceTurnIDs: existing.sourceTurnIDs,
            status: .superseded,
            consentState: existing.consentState,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            supersedesMemoryID: existing.supersedesMemoryID
        )
        let replacement = activeNarrativeMemoryRecord(
            candidate,
            session: session,
            supersedesMemoryID: existing.memoryID
        )
        records.append(replacement)
        return RuntimeNarrativeMemoryCandidateOutcome(
            decision: RuntimeNarrativeMemoryDecision(
                candidateID: candidate.candidateID,
                memoryID: replacement.memoryID,
                memoryType: replacement.type.rawValue,
                decision: .supersede,
                reason: "latest_user_correction"
            ),
            didMutateStore: true
        )
    }

    private func deleteNarrativeMemory(
        _ candidate: RuntimeNormalizedNarrativeMemoryCandidate,
        records: inout [RuntimeNarrativeMemoryRecord]
    ) -> RuntimeNarrativeMemoryCandidateOutcome {
        let exactIndex = records.firstIndex(where: {
            $0.status == .active
                && $0.type == candidate.memoryType
                && normalizedNarrativeSummary($0.summary)
                    == normalizedNarrativeSummary(candidate.summary)
        })
        let latestTypeIndex = records.indices
            .filter {
                records[$0].status == .active
                    && records[$0].type == candidate.memoryType
            }
            .max {
                records[$0].updatedAt < records[$1].updatedAt
            }
        guard let index = exactIndex ?? latestTypeIndex else {
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: rejectedNarrativeMemoryDecision(
                    candidateID: candidate.candidateID,
                    memoryType: candidate.memoryType.rawValue,
                    reason: "deletion_target_not_found"
                ),
                didMutateStore: false
            )
        }
        let existing = records[index]
        records[index] = RuntimeNarrativeMemoryRecord(
            memoryID: existing.memoryID,
            residentID: existing.residentID,
            type: existing.type,
            summary: existing.summary,
            sourceSessionID: existing.sourceSessionID,
            sourceTurnIDs: existing.sourceTurnIDs,
            status: .deleted,
            consentState: .granted,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            supersedesMemoryID: existing.supersedesMemoryID
        )
        return RuntimeNarrativeMemoryCandidateOutcome(
            decision: RuntimeNarrativeMemoryDecision(
                candidateID: candidate.candidateID,
                memoryID: existing.memoryID,
                memoryType: existing.type.rawValue,
                decision: .delete,
                reason: "user_forget_request"
            ),
            didMutateStore: true
        )
    }

    private func rejectNarrativeMemoryCandidate(
        _ candidate: RuntimeNormalizedNarrativeMemoryCandidate,
        session: RuntimeSessionContext,
        reason: String,
        records: inout [RuntimeNarrativeMemoryRecord]
    ) -> RuntimeNarrativeMemoryCandidateOutcome {
        if let existing = records.first(where: {
            $0.status == .rejected
                && $0.type == candidate.memoryType
                && Set($0.sourceTurnIDs)
                    == Set(candidate.sourceTurnIDs)
        }) {
            return RuntimeNarrativeMemoryCandidateOutcome(
                decision: RuntimeNarrativeMemoryDecision(
                    candidateID: candidate.candidateID,
                    memoryID: existing.memoryID,
                    memoryType: existing.type.rawValue,
                    decision: .reject,
                    reason: "duplicate_rejected"
                ),
                didMutateStore: false
            )
        }
        let now = Date()
        let record = RuntimeNarrativeMemoryRecord(
            memoryID: UUID().uuidString.lowercased(),
            residentID: session.residentID,
            type: candidate.memoryType,
            summary: "[redacted]",
            sourceSessionID: session.sessionID.rawValue,
            sourceTurnIDs: candidate.sourceTurnIDs,
            status: .rejected,
            consentState: .rejected,
            createdAt: now,
            updatedAt: now,
            supersedesMemoryID: nil
        )
        records.append(record)
        return RuntimeNarrativeMemoryCandidateOutcome(
            decision: RuntimeNarrativeMemoryDecision(
                candidateID: candidate.candidateID,
                memoryID: record.memoryID,
                memoryType: record.type.rawValue,
                decision: .reject,
                reason: reason
            ),
            didMutateStore: true
        )
    }

    private func activeNarrativeMemoryRecord(
        _ candidate: RuntimeNormalizedNarrativeMemoryCandidate,
        session: RuntimeSessionContext,
        supersedesMemoryID: String?
    ) -> RuntimeNarrativeMemoryRecord {
        let now = Date()
        let consentState: RuntimeNarrativeMemoryConsentState =
            candidate.consentSignal == "not_required"
                ? .notRequired
                : .granted
        return RuntimeNarrativeMemoryRecord(
            memoryID: UUID().uuidString.lowercased(),
            residentID: session.residentID,
            type: candidate.memoryType,
            summary: candidate.summary,
            sourceSessionID: session.sessionID.rawValue,
            sourceTurnIDs: candidate.sourceTurnIDs,
            status: .active,
            consentState: consentState,
            createdAt: now,
            updatedAt: now,
            supersedesMemoryID: supersedesMemoryID
        )
    }

    private func rejectedNarrativeMemoryDecision(
        candidateID: String,
        memoryType: String?,
        reason: String
    ) -> RuntimeNarrativeMemoryDecision {
        RuntimeNarrativeMemoryDecision(
            candidateID: candidateID,
            memoryID: nil,
            memoryType: memoryType,
            decision: .reject,
            reason: reason
        )
    }

    private func safeNarrativeCandidateID(_ value: String) -> String {
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalized.range(
            of: "^[A-Za-z0-9._:-]{1,128}$",
            options: .regularExpression
        ) != nil else {
            return "invalid_candidate"
        }
        return normalized
    }

    private func normalizedNarrativeSummary(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func permanentlyForbiddenNarrativeContentCategory(
        in summary: String
    ) -> String? {
        let patterns: [(String, String)] = [
            ("password", #"(?i)(password|passcode|密码|口令)\s*[:：是为]?"#),
            (
                "verification_code",
                #"(?i)(verification[ _-]?code|one[ _-]?time[ _-]?code|otp|验证码|校验码)\s*[:：是为]?"#
            ),
            (
                "api_key",
                #"(?i)(api[ _-]?key|access[ _-]?token|secret[ _-]?key|sk-[a-z0-9_-]{8,})\s*[:：是为]?"#
            ),
            (
                "payment_credential",
                #"(?i)(payment[ _-]?credential|card[ _-]?number|credit[ _-]?card|cvv|支付凭据|银行卡号|信用卡号)\s*[:：是为]?"#
            ),
            (
                "precise_identity_credential",
                #"(?i)(passport[ _-]?number|identity[ _-]?number|身份证号|护照号)\s*[:：是为]?"#
            ),
            (
                "authentication_information",
                #"(?i)(authentication[ _-]?information|auth[ _-]?token|login[ _-]?credential|认证信息|登录凭据)\s*[:：是为]?"#
            )
        ]
        return patterns.first {
            summary.range(
                of: $0.1,
                options: .regularExpression
            ) != nil
        }?.0
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

    func configureNativeSpeechProvider(
        profile: NativeSpeechProviderProfile
    ) -> NativeSpeechError? {
        executionEngine.configureNativeSpeechProvider(profile: profile)
    }

    #if DEBUG
    func testNativeSpeechConnectivity(
        profile: NativeSpeechProviderProfile
    ) async -> Result<Void, NativeSpeechError> {
        if let error = configureNativeSpeechProvider(profile: profile) {
            return .failure(error)
        }
        do {
            let interaction = try await startNativeSpeechInteraction()
            let created = try await receiveNativeSpeechEvent(
                interactionID: interaction.id
            )
            guard case .accepted(let createdEvent) = created,
                  createdEvent.kind == .connected else {
                throw NativeSpeechError.invalidEvent
            }
            let updated = try await receiveNativeSpeechEvent(
                interactionID: interaction.id
            )
            guard case .accepted(let updatedEvent) = updated,
                  updatedEvent.kind == .sessionUpdated else {
                throw NativeSpeechError.invalidEvent
            }
            try await closeActiveNativeSpeechInteraction()
            return .success(())
        } catch let error as NativeSpeechError {
            try? await closeActiveNativeSpeechInteraction()
            return .failure(error)
        } catch {
            try? await closeActiveNativeSpeechInteraction()
            return .failure(.transportFailure)
        }
    }
    #endif

    func startNativeSpeechInteraction() async throws -> NativeSpeechInteraction {
        guard let session = sessionContext,
              currentResidentIdentity?.residentID == session.residentID,
              let providerProfileID =
                executionEngine.configuredNativeSpeechProfileID() else {
            throw NativeSpeechError.unavailable
        }

        let interaction = NativeSpeechInteraction(
            residentID: session.residentID,
            sessionID: session.sessionID.rawValue,
            providerProfileID: providerProfileID
        )
        guard let compiledContext = compiledResidentDialogueContext(
            currentUserInput: ""
        ) else {
            throw NativeSpeechError.unavailable
        }
        let refreshReason = RealtimeSpeechContextRefreshReason.interactionStarted
        let compilationKey = RealtimeSpeechContextCompilationKey(
            interactionID: interaction.id,
            refreshReason: refreshReason,
            sourceRevision: realtimeSpeechContextSourceRevision,
            currentUserInput: ""
        )
        let contextProjection = try realtimeSpeechContextCompiler.compile(
            context: compiledContext.context,
            interaction: interaction,
            refreshReason: refreshReason
        )
        guard nativeSpeechInteractionGate.reserve(
            interaction,
            contextProjection: contextProjection,
            compilationKey: compilationKey
        ) else {
            throw NativeSpeechError.invalidConfiguration
        }

        do {
            try await executionEngine.startNativeSpeech(
                interaction: interaction,
                contextProjection: contextProjection,
                tools: nativeSpeechToolDefinitions
            )
        } catch {
            nativeSpeechInteractionGate.clear(matching: interaction.id)
            throw error
        }

        guard sessionContext == session,
              nativeSpeechInteractionGate.current()?.id == interaction.id else {
            nativeSpeechInteractionGate.clear(matching: interaction.id)
            resetNativeSpeechToolState()
            try? await executionEngine.cancelNativeSpeech(
                interactionID: interaction.id,
                reason: .superseded
            )
            try? await executionEngine.closeNativeSpeech(
                interactionID: interaction.id
            )
            throw NativeSpeechError.cancelled
        }

        let active = NativeSpeechInteraction(
            id: interaction.id,
            residentID: interaction.residentID,
            sessionID: interaction.sessionID,
            providerProfileID: interaction.providerProfileID,
            lifecycleState: .active
        )
        guard nativeSpeechInteractionGate.activate(active) else {
            resetNativeSpeechToolState()
            try? await executionEngine.cancelNativeSpeech(
                interactionID: interaction.id,
                reason: .superseded
            )
            try? await executionEngine.closeNativeSpeech(
                interactionID: interaction.id
            )
            throw NativeSpeechError.cancelled
        }
        return active
    }

    func startNativeSpeechInput(
        captureGeneration: UInt64
    ) async throws -> NativeSpeechInputBinding {
        let interaction = try await startNativeSpeechInteraction()
        let binding = NativeSpeechInputBinding(
            interactionID: interaction.id,
            residentID: interaction.residentID,
            sessionID: interaction.sessionID,
            captureGeneration: captureGeneration
        )
        nativeSpeechInputGate.activate(binding)
        let stateTransition = realtimeSpeechStateMachine.start(
            interaction: interaction
        )
        resetNativeSpeechToolState()
        lastCommittedNativeSpeechTurn = nil
        lastAppliedNativeSpeechUserControls = nil
        realtimeSpeechSubtitleStateMachine.start(
            interactionID: interaction.id,
            turnNumber: stateTransition.snapshot.currentTurnNumber
        )
        scheduleRealtimeSpeechGuard(for: interaction)
        return binding
    }

    nonisolated func sendNativeSpeechInput(
        _ payload: NativeSpeechAudioPayload,
        context: NativeSpeechInputFrameContext
    ) async throws -> NativeSpeechInputFrameDisposition {
        guard nativeSpeechInputGate.accepts(payload, context: context) else {
            return .rejectedStale
        }
        try await executionEngine.sendNativeSpeechAudio(payload)
        return .forwarded
    }

    func stopNativeSpeechInput(
        binding: NativeSpeechInputBinding,
        reason: NativeSpeechCancellationReason
    ) async throws {
        let wasCurrentInput = nativeSpeechInputGate.invalidate(
            binding: binding
        )
        if nativeSpeechInteractionGate.current()?.id
            == binding.interactionID {
            try await cancelActiveNativeSpeechInteraction(reason: reason)
            return
        }
        guard !wasCurrentInput,
              nativeSpeechInteractionGate.current() == nil else {
            return
        }
        realtimeSpeechGuardScheduler.cancel()
        realtimeSpeechStateMachine.stop(
            interactionID: binding.interactionID,
            reason: reason
        )
    }

    func closeNativeSpeechInput(
        binding: NativeSpeechInputBinding
    ) async throws {
        let wasCurrentInput = nativeSpeechInputGate.invalidate(
            binding: binding
        )
        if nativeSpeechInteractionGate.current()?.id
            == binding.interactionID {
            try await closeActiveNativeSpeechInteraction()
            return
        }
        guard !wasCurrentInput,
              nativeSpeechInteractionGate.current() == nil else {
            return
        }
        try await executionEngine.closeNativeSpeech(
            interactionID: binding.interactionID
        )
    }

    func sendNativeSpeechAudio(
        _ payload: NativeSpeechAudioPayload
    ) async throws {
        guard nativeSpeechInteractionGate.current()?.id
                == payload.interactionID else {
            throw NativeSpeechError.interactionMismatch
        }
        try await executionEngine.sendNativeSpeechAudio(payload)
    }

    func receiveNativeSpeechEvent(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEventDisposition {
        guard nativeSpeechInteractionGate.current()?.id == interactionID else {
            recordNativeSpeechRuntimeRejection(
                eventKind: nil,
                interactionID: interactionID,
                stateBefore: realtimeSpeechStateMachine.snapshot(),
                stateAfter: realtimeSpeechStateMachine.snapshot(),
                disposition: .rejectedStale
            )
            return .rejectedStale
        }
        do {
            let event = try await executionEngine.receiveNativeSpeechEvent(
                interactionID: interactionID
            )
            guard let interaction = nativeSpeechInteractionGate.current(),
                  interaction.id == interactionID else {
                recordNativeSpeechRuntimeRejection(
                    eventKind: event.kind,
                    interactionID: interactionID,
                    stateBefore: realtimeSpeechStateMachine.snapshot(),
                    stateAfter: realtimeSpeechStateMachine.snapshot(),
                    disposition: .rejectedStale
                )
                return .rejectedStale
            }
            let stateBefore = realtimeSpeechStateMachine.snapshot()
            let turnIdentity = NativeSpeechToolTurnIdentity(
                interactionID: interaction.id,
                turnNumber: stateBefore.currentTurnNumber,
                turnGeneration:
                    realtimeSpeechSubtitleStateMachine.snapshot()
                        .turnGeneration
            )
            if case .responseCompleted = event.kind,
               var toolState = nativeSpeechToolTurnState,
               toolState.identity == turnIdentity {
                toolState.responseBoundaryReceived = true
                nativeSpeechToolTurnState = toolState
                recordNativeSpeechToolDiagnostic(
                    category: "tool_response_segment_boundary",
                    identity: turnIdentity,
                    disposition: "awaiting_safe_continuation"
                )
                try await continueNativeSpeechToolTurnIfReady(
                    interaction: interaction
                )
                return .accepted(event)
            }
            var stateTransition: RealtimeSpeechTransitionResult?
            var requiresInterruptCommit = false
            if realtimeSpeechStateMachine.tracks(interaction) {
                let transition = realtimeSpeechStateMachine.transition(
                    event: event,
                    interaction: interaction,
                    nowNanoseconds: DispatchTime.now().uptimeNanoseconds
                )
                stateTransition = transition
                switch transition.disposition {
                case .rejectedStale:
                    recordRejectedSubtitleEventIfNeeded(
                        event.kind,
                        disposition: .rejectedStale
                    )
                    recordNativeSpeechRuntimeRejection(
                        eventKind: event.kind,
                        interactionID: interactionID,
                        stateBefore: stateBefore,
                        stateAfter: transition.snapshot,
                        disposition: .rejectedStale
                    )
                    return .rejectedStale
                case .rejectedLate:
                    recordRejectedSubtitleEventIfNeeded(
                        event.kind,
                        disposition: .rejectedLate
                    )
                    recordNativeSpeechRuntimeRejection(
                        eventKind: event.kind,
                        interactionID: interactionID,
                        stateBefore: stateBefore,
                        stateAfter: transition.snapshot,
                        disposition: .rejectedLate
                    )
                    return .rejectedLate
                case .rejectedOutOfOrder:
                    recordRejectedSubtitleEventIfNeeded(
                        event.kind,
                        disposition: .rejectedOutOfOrder
                    )
                    recordNativeSpeechRuntimeRejection(
                        eventKind: event.kind,
                        interactionID: interactionID,
                        stateBefore: stateBefore,
                        stateAfter: transition.snapshot,
                        disposition: .rejectedOutOfOrder
                    )
                    return .rejectedOutOfOrder
                case .applied, .ignoredDuplicate:
                    scheduleRealtimeSpeechGuard(for: interaction)
                }
                requiresInterruptCommit =
                    transition.effect == .interruptProvider
            }
            if case .outputAudio = event.kind,
               stateTransition?.disposition == .applied
                    || stateTransition?.disposition == .ignoredDuplicate {
                nativeSpeechTurnsWithOutputAudio.insert(turnIdentity)
                if var toolState = nativeSpeechToolTurnState,
                   toolState.identity == turnIdentity {
                    toolState.waitsForPlaybackDrain = true
                    toolState.playbackDrained = false
                    nativeSpeechToolTurnState = toolState
                }
            }
            let disposition = nativeSpeechDisposition(
                for: event,
                expectedInteractionID: interactionID
            )
            if case .accepted = disposition,
               let subtitleDisposition = applyRealtimeSpeechSubtitleEvent(
                    event,
                    stateBefore: stateBefore,
                    transition: stateTransition
               ), subtitleDisposition != .accepted {
                switch subtitleDisposition {
                case .rejectedStale:
                    recordNativeSpeechRuntimeRejection(
                        eventKind: event.kind,
                        interactionID: interactionID,
                        stateBefore: stateBefore,
                        stateAfter: realtimeSpeechStateMachine.snapshot(),
                        disposition: .rejectedStale
                    )
                    return .rejectedStale
                case .rejectedLate:
                    recordNativeSpeechRuntimeRejection(
                        eventKind: event.kind,
                        interactionID: interactionID,
                        stateBefore: stateBefore,
                        stateAfter: realtimeSpeechStateMachine.snapshot(),
                        disposition: .rejectedLate
                    )
                    return .rejectedLate
                case .rejectedRevision, .rejectedFinalLocked,
                     .rejectedDuplicate, .rejectedOutOfOrder:
                    recordNativeSpeechRuntimeRejection(
                        eventKind: event.kind,
                        interactionID: interactionID,
                        stateBefore: stateBefore,
                        stateAfter: realtimeSpeechStateMachine.snapshot(),
                        disposition: .rejectedOutOfOrder
                    )
                    return .rejectedOutOfOrder
                case .accepted:
                    break
                }
            }
            let currentToolTurnIdentity = NativeSpeechToolTurnIdentity(
                interactionID: interaction.id,
                turnNumber: realtimeSpeechStateMachine.snapshot()
                    .currentTurnNumber,
                turnGeneration: realtimeSpeechSubtitleStateMachine.snapshot()
                    .turnGeneration
            )
            if currentToolTurnIdentity != turnIdentity,
               realtimeSpeechSubtitleStateMachine.snapshot()
                    .lastClosureReason != .completed {
                pruneStaleNativeSpeechToolCallHistory(
                    retaining: currentToolTurnIdentity
                )
            }
            if case .accepted(let acceptedEvent) = disposition,
               case .finalTranscript = acceptedEvent.kind {
                pruneStaleNativeSpeechToolCallHistory(
                    retaining: currentToolTurnIdentity
                )
            }
            if case .accepted(let acceptedEvent) = disposition,
               case .toolRequestCandidate(let request) =
                    acceptedEvent.kind {
                await handleNativeSpeechToolRequest(
                    request,
                    interaction: interaction,
                    identity: turnIdentity
                )
            }
            if case .accepted(let acceptedEvent) = disposition,
               case .finalTranscript(let transcript) = acceptedEvent.kind {
                applyNativeSpeechUserFinalControls(
                    interaction: interaction,
                    userFinal: transcript
                )
                try await refreshNativeSpeechContext(
                    interactionID: interactionID,
                    currentUserInput: transcript,
                    reason: .finalTranscript
                )
            }
            if requiresInterruptCommit {
                let subtitleSnapshot =
                    realtimeSpeechSubtitleStateMachine.snapshot()
                guard nativeSpeechInteractionGate.setPendingInterrupt(
                    interactionID: interactionID,
                    turnNumber: realtimeSpeechStateMachine.snapshot()
                        .currentTurnNumber,
                    turnGeneration: subtitleSnapshot.turnGeneration
                ) else {
                    recordNativeSpeechRuntimeRejection(
                        eventKind: event.kind,
                        interactionID: interactionID,
                        stateBefore: stateBefore,
                        stateAfter: realtimeSpeechStateMachine.snapshot(),
                        disposition: .rejectedStale
                    )
                    return .rejectedStale
                }
            }
            if case .accepted = disposition,
               nativeSpeechEventIsTerminal(event) {
                try? await executionEngine.closeNativeSpeech(
                    interactionID: interactionID
                )
            }
            return disposition
        } catch let error as NativeSpeechError {
            guard nativeSpeechInteractionGate.current()?.id
                    == interactionID else {
                return .rejectedStale
            }
            await failActiveNativeSpeechInteraction(
                interactionID: interactionID,
                error: error
            )
            throw error
        } catch {
            guard nativeSpeechInteractionGate.current()?.id
                    == interactionID else {
                return .rejectedStale
            }
            await failActiveNativeSpeechInteraction(
                interactionID: interactionID,
                error: .transportFailure
            )
            throw NativeSpeechError.transportFailure
        }
    }

    func commitNativeSpeechInterrupt(
        interactionID: NativeSpeechInteractionID,
        turnNumber: UInt64,
        turnGeneration: UInt64
    ) async throws -> Bool {
        guard nativeSpeechInteractionGate.claimPendingInterrupt(
            interactionID: interactionID,
            turnNumber: turnNumber,
            turnGeneration: turnGeneration
        ) else {
            return false
        }
        do {
            try await executionEngine.cancelNativeSpeech(
                interactionID: interactionID,
                reason: .interrupted
            )
            return true
        } catch let error as NativeSpeechError {
            await failActiveNativeSpeechInteraction(
                interactionID: interactionID,
                error: error
            )
            throw error
        } catch {
            await failActiveNativeSpeechInteraction(
                interactionID: interactionID,
                error: .transportFailure
            )
            throw NativeSpeechError.transportFailure
        }
    }

    func handleNativeSpeechPlaybackEvent(
        _ event: RealtimeSpeechPlaybackEvent
    ) async -> RealtimeSpeechTransitionDisposition {
        guard let interaction = nativeSpeechInteractionGate.current(),
              interaction.id == event.interactionID else {
            recordNativeSpeechRuntimeRejection(
                eventKind: nil,
                interactionID: event.interactionID,
                stateBefore: realtimeSpeechStateMachine.snapshot(),
                stateAfter: realtimeSpeechStateMachine.snapshot(),
                disposition: .rejectedStale,
                category: "playback_\(Self.playbackEventCategory(event.kind))"
            )
            return .rejectedStale
        }
        let stateBefore = realtimeSpeechStateMachine.snapshot()
        let transition = realtimeSpeechStateMachine.transition(
            playbackEvent: event,
            interaction: interaction,
            nowNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        switch transition.disposition {
        case .applied, .ignoredDuplicate:
            scheduleRealtimeSpeechGuard(for: interaction)
        case .rejectedStale, .rejectedLate, .rejectedOutOfOrder:
            recordNativeSpeechRuntimeRejection(
                eventKind: nil,
                interactionID: event.interactionID,
                stateBefore: stateBefore,
                stateAfter: transition.snapshot,
                disposition: transition.disposition,
                category: "playback_\(Self.playbackEventCategory(event.kind))"
            )
            break
        }
        if transition.disposition == .applied,
           case .completed = event.kind {
            let identity = NativeSpeechToolTurnIdentity(
                interactionID: interaction.id,
                turnNumber: stateBefore.currentTurnNumber,
                turnGeneration:
                    realtimeSpeechSubtitleStateMachine.snapshot()
                        .turnGeneration
            )
            nativeSpeechTurnsWithOutputAudio.remove(identity)
            if var toolState = nativeSpeechToolTurnState,
               toolState.identity == identity {
                toolState.playbackDrained = true
                nativeSpeechToolTurnState = toolState
                do {
                    try await continueNativeSpeechToolTurnIfReady(
                        interaction: interaction
                    )
                } catch let error as NativeSpeechError {
                    await failActiveNativeSpeechInteraction(
                        interactionID: interaction.id,
                        error: error
                    )
                } catch {
                    await failActiveNativeSpeechInteraction(
                        interactionID: interaction.id,
                        error: .transportFailure
                    )
                }
            }
        }
        if transition.disposition == .applied {
            if transition.snapshot.lastTransitionReason
                    == .responseCompleted,
               transition.snapshot.currentTurnNumber
                    > stateBefore.currentTurnNumber {
                let subtitleDisposition =
                    realtimeSpeechSubtitleStateMachine.completeTurn(
                        interactionID: interaction.id,
                        completedTurnNumber: stateBefore.currentTurnNumber,
                        nextTurnNumber:
                            transition.snapshot.currentTurnNumber
                    )
                if subtitleDisposition == .accepted {
                    commitCompletedNativeSpeechTurn(
                        interaction: interaction,
                        completedTurnNumber: stateBefore.currentTurnNumber
                    )
                }
            } else if case .failed = event.kind {
                _ = realtimeSpeechSubtitleStateMachine.terminate(
                    interactionID: interaction.id,
                    reason: .failed
                )
            }
        }
        guard transition.effect == .terminateProvider else {
            return transition.disposition
        }
        realtimeSpeechGuardScheduler.cancel()
        resetNativeSpeechToolState()
        nativeSpeechInteractionGate.clear(matching: interaction.id)
        invalidateNativeSpeechInput(for: interaction.id)
        try? await executionEngine.cancelNativeSpeech(
            interactionID: interaction.id,
            reason: .interrupted
        )
        try? await executionEngine.closeNativeSpeech(
            interactionID: interaction.id
        )
        return transition.disposition
    }

    private func applyRealtimeSpeechSubtitleEvent(
        _ event: NativeSpeechEvent,
        stateBefore: RealtimeSpeechStateSnapshot,
        transition: RealtimeSpeechTransitionResult?
    ) -> RealtimeSpeechSubtitleDisposition? {
        guard realtimeSpeechSubtitleStateMachine.tracks(
            event.interactionID
        ) else {
            return nil
        }
        let stateAfter = transition?.snapshot
            ?? realtimeSpeechStateMachine.snapshot()
        switch event.kind {
        case .partialTranscript(let text):
            return realtimeSpeechSubtitleStateMachine
                .applyProviderTranscript(
                    interactionID: event.interactionID,
                    turnNumber: stateAfter.currentTurnNumber,
                    direction: .user,
                    contentState: .partial,
                    text: text
                ).disposition
        case .finalTranscript(let text):
            return realtimeSpeechSubtitleStateMachine
                .applyProviderTranscript(
                    interactionID: event.interactionID,
                    turnNumber: stateAfter.currentTurnNumber,
                    direction: .user,
                    contentState: .final,
                    text: text
                ).disposition
        case .outputText(let text, let isFinal):
            return realtimeSpeechSubtitleStateMachine
                .applyProviderTranscript(
                    interactionID: event.interactionID,
                    turnNumber: stateAfter.currentTurnNumber,
                    direction: .resident,
                    contentState: isFinal ? .final : .partial,
                    text: text
                ).disposition
        case .inputSpeechStarted
            where transition?.effect == .interruptProvider:
            return realtimeSpeechSubtitleStateMachine.interrupt(
                interactionID: event.interactionID,
                interruptedTurnNumber: stateBefore.currentTurnNumber,
                nextTurnNumber: stateAfter.currentTurnNumber
            )
        case .responseCompleted:
            if stateAfter.lastTransitionReason == .responseCompleted,
               stateAfter.currentTurnNumber > stateBefore.currentTurnNumber {
                let disposition =
                    realtimeSpeechSubtitleStateMachine.completeTurn(
                        interactionID: event.interactionID,
                        completedTurnNumber: stateBefore.currentTurnNumber,
                        nextTurnNumber: stateAfter.currentTurnNumber
                    )
                if disposition == .accepted,
                   let interaction = nativeSpeechInteractionGate.current() {
                    commitCompletedNativeSpeechTurn(
                        interaction: interaction,
                        completedTurnNumber: stateBefore.currentTurnNumber
                    )
                }
                return disposition
            } else if transition?.disposition == .ignoredDuplicate {
                realtimeSpeechSubtitleStateMachine.recordRejectedEvent(
                    .rejectedDuplicate
                )
                return .rejectedDuplicate
            }
            return .accepted
        case .turnFailed:
            return realtimeSpeechSubtitleStateMachine.failTurn(
                interactionID: event.interactionID,
                failedTurnNumber: stateBefore.currentTurnNumber,
                nextTurnNumber: stateAfter.currentTurnNumber
            )
        case .cancelled:
            return realtimeSpeechSubtitleStateMachine.terminate(
                interactionID: event.interactionID,
                reason: .cancelled
            )
        case .failed:
            return realtimeSpeechSubtitleStateMachine.terminate(
                interactionID: event.interactionID,
                reason: .failed
            )
        case .closed:
            return realtimeSpeechSubtitleStateMachine.terminate(
                interactionID: event.interactionID,
                reason: .closed
            )
        case .connected, .sessionUpdated, .inputSpeechStarted,
             .inputSpeechEnded, .thinking, .outputAudio,
             .toolRequestCandidate:
            return nil
        }
    }

    private func commitCompletedNativeSpeechTurn(
        interaction: NativeSpeechInteraction,
        completedTurnNumber: UInt64
    ) {
        let subtitle = realtimeSpeechSubtitleStateMachine.snapshot()
        guard subtitle.lastClosureReason == .completed,
              let completed = subtitle.lastCompleted,
              completed.turnNumber == completedTurnNumber,
              let userFinal = completed.userFinal?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !userFinal.isEmpty,
              let residentFinal = completed.residentFinal?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !residentFinal.isEmpty,
              let session = sessionContext,
              session.residentID == interaction.residentID,
              session.sessionID.rawValue == interaction.sessionID else {
            return
        }
        let identity = NativeSpeechTurnCommitIdentity(
            interactionID: interaction.id,
            turnNumber: completed.turnNumber,
            turnGeneration: completed.turnGeneration
        )
        guard lastCommittedNativeSpeechTurn != identity else { return }
        lastCommittedNativeSpeechTurn = identity

        _ = persistResidentDialogueExchange(
            userInput: userFinal,
            residentReply: residentFinal,
            session: session
        )
        let toolIdentity = NativeSpeechToolTurnIdentity(
            interactionID: identity.interactionID,
            turnNumber: identity.turnNumber,
            turnGeneration: identity.turnGeneration
        )
        if handledNativeSpeechToolCalls.contains(where: {
            $0.turn == toolIdentity
        }) {
            recordNativeSpeechToolDiagnostic(
                category: "tool_formal_turn_completed",
                identity: toolIdentity,
                disposition: "committed"
            )
        }
        pruneCompletedNativeSpeechToolCallHistory(toolIdentity)
        realtimeSpeechContextSourceRevision &+= 1
    }

    private func pruneCompletedNativeSpeechToolCallHistory(
        _ identity: NativeSpeechToolTurnIdentity
    ) {
        guard !nativeSpeechToolExecutionTasks.keys.contains(where: {
            $0.turn == identity
        }) else {
            recordNativeSpeechToolDiagnostic(
                category: "tool_call_history_prune_deferred",
                identity: identity,
                disposition: "pending_execution"
            )
            return
        }
        let retained = handledNativeSpeechToolCalls.filter {
            $0.turn != identity
        }
        let removedCount = handledNativeSpeechToolCalls.count
            - retained.count
        guard removedCount > 0 else { return }
        handledNativeSpeechToolCalls = Set(retained)
        recordNativeSpeechToolDiagnostic(
            category: "tool_call_history_pruned",
            identity: identity,
            disposition: "completed_turn_removed:\(removedCount)"
        )
    }

    private func pruneStaleNativeSpeechToolCallHistory(
        retaining identity: NativeSpeechToolTurnIdentity
    ) {
        invalidateStaleNativeSpeechToolExecutions(retaining: identity)
        invalidateStaleNativeSpeechToolPermissions(retaining: identity)
        discardStaleNativeSpeechToolTurnState(retaining: identity)
        nativeSpeechTurnsWithOutputAudio = Set(
            nativeSpeechTurnsWithOutputAudio.filter { $0 == identity }
        )
        let retained = handledNativeSpeechToolCalls.filter {
            $0.turn == identity
        }
        let removedCount = handledNativeSpeechToolCalls.count
            - retained.count
        guard removedCount > 0 else { return }
        handledNativeSpeechToolCalls = Set(retained)
        recordNativeSpeechToolDiagnostic(
            category: "tool_call_history_pruned",
            identity: identity,
            disposition: "stale_turn_removed:\(removedCount)"
        )
    }

    private func invalidateStaleNativeSpeechToolExecutions(
        retaining identity: NativeSpeechToolTurnIdentity
    ) {
        let staleIdentities = nativeSpeechToolExecutionTasks.keys.filter {
            $0.turn != identity
        }
        for callIdentity in staleIdentities {
            nativeSpeechToolExecutionTasks.removeValue(
                forKey: callIdentity
            )?.cancel()
            recordNativeSpeechToolDiagnostic(
                category: "tool_execution_stale",
                identity: callIdentity.turn,
                disposition: "turn_invalidated"
            )
        }
    }

    private func invalidateStaleNativeSpeechToolPermissions(
        retaining identity: NativeSpeechToolTurnIdentity
    ) {
        let staleIdentities = Set(
            pendingNativeSpeechToolPermissions.keys.filter {
                $0.turn != identity
            } + nativeSpeechToolPermissionTasks.keys.filter {
                $0.turn != identity
            }
        )
        for callIdentity in staleIdentities {
            let context = pendingNativeSpeechToolPermissions.removeValue(
                forKey: callIdentity
            )
            nativeSpeechToolPermissionTasks.removeValue(
                forKey: callIdentity
            )?.cancel()
            guard let context else { continue }
            recordNativeSpeechToolDiagnostic(
                category: "tool_permission_stale",
                identity: callIdentity.turn,
                disposition: "turn_invalidated",
                correlationHash: context.permissionRequest.correlationHash,
                toolName: context.permissionRequest.toolName
            )
        }
    }

    private func discardStaleNativeSpeechToolTurnState(
        retaining identity: NativeSpeechToolTurnIdentity
    ) {
        nativeSpeechToolContinuationClaimLock.lock()
        defer { nativeSpeechToolContinuationClaimLock.unlock() }
        guard nativeSpeechToolTurnState?.identity != identity else { return }
        nativeSpeechToolTurnState = nil
    }

    private func applyNativeSpeechUserFinalControls(
        interaction: NativeSpeechInteraction,
        userFinal: String
    ) {
        guard let session = sessionContext,
              session.residentID == interaction.residentID,
              session.sessionID.rawValue == interaction.sessionID else {
            return
        }
        let identity = NativeSpeechTurnCommitIdentity(
            interactionID: interaction.id,
            turnNumber: realtimeSpeechStateMachine.snapshot()
                .currentTurnNumber,
            turnGeneration: realtimeSpeechSubtitleStateMachine.snapshot()
                .turnGeneration
        )
        guard lastAppliedNativeSpeechUserControls != identity else { return }
        lastAppliedNativeSpeechUserControls = identity

        _ = applyRelationshipUserControl(
            relationshipUserControl(for: userFinal)
        )
        _ = applyNarrativeMemoryUserControl(
            narrativeMemoryUserControl(for: userFinal),
            input: userFinal,
            residentID: session.residentID
        )
    }

    private func recordRejectedSubtitleEventIfNeeded(
        _ eventKind: NativeSpeechEventKind,
        disposition: RealtimeSpeechSubtitleDisposition
    ) {
        switch eventKind {
        case .partialTranscript, .finalTranscript, .outputText,
             .responseCompleted, .turnFailed, .cancelled, .closed,
             .failed:
            realtimeSpeechSubtitleStateMachine.recordRejectedEvent(
                disposition
            )
        default:
            break
        }
    }

    private func recordNativeSpeechRuntimeRejection(
        eventKind: NativeSpeechEventKind?,
        interactionID: NativeSpeechInteractionID,
        stateBefore: RealtimeSpeechStateSnapshot,
        stateAfter: RealtimeSpeechStateSnapshot,
        disposition: RealtimeSpeechTransitionDisposition,
        category: String? = nil
    ) {
        nativeSpeechDiagnosticBuffer?.append(
            NativeSpeechInternalDiagnosticEvent(
                source: .runtime,
                category: category
                    ?? Self.nativeSpeechEventCategory(eventKind),
                interactionShortID: String(
                    interactionID.rawValue.uuidString.prefix(8)
                ),
                turnNumber: stateAfter.currentTurnNumber,
                turnGeneration:
                    realtimeSpeechSubtitleStateMachine.snapshot()
                        .turnGeneration,
                stateBefore: stateBefore.state.rawValue,
                stateAfter: stateAfter.state.rawValue,
                disposition: disposition.rawValue,
                errorCode: stateAfter.lastStandardError
            )
        )
    }

    private func handleNativeSpeechToolRequest(
        _ request: NativeSpeechToolRequest,
        interaction: NativeSpeechInteraction,
        identity: NativeSpeechToolTurnIdentity
    ) async {
        let callIdentity = NativeSpeechToolCallIdentity(
            turn: identity,
            callID: request.callID
        )
        guard handledNativeSpeechToolCalls.insert(callIdentity).inserted else {
            recordNativeSpeechToolDiagnostic(
                category: "tool_request_duplicate",
                identity: identity,
                disposition: "ignored",
                correlationHash: request.correlationHash
            )
            if pendingNativeSpeechToolPermissions[callIdentity] != nil {
                recordNativeSpeechToolDiagnostic(
                    category: "tool_permission_duplicate",
                    identity: identity,
                    disposition: "ignored",
                    correlationHash: request.correlationHash,
                    toolName: request.toolName
                )
            }
            return
        }

        stageNativeSpeechToolCall(
            callID: request.callID,
            identity: identity
        )

        let output: String
        guard let argumentsObject =
                Self.nativeSpeechToolArgumentsObject(request.arguments) else {
            output = Self.nativeSpeechToolErrorOutput("invalid_arguments")
            recordNativeSpeechToolDiagnostic(
                category: "tool_request_rejected",
                identity: identity,
                disposition: "invalid_arguments",
                correlationHash: request.correlationHash
            )
            await stageNativeSpeechToolOutput(
                NativeSpeechToolOutput(
                    callID: request.callID,
                    output: output
                ),
                interaction: interaction,
                identity: identity
            )
            return
        }
        guard let definition = nativeSpeechToolDefinitions.first(where: {
            $0.name == request.toolName
        }) else {
            output = Self.nativeSpeechToolErrorOutput("unknown_tool")
            recordNativeSpeechToolDiagnostic(
                category: "tool_request_rejected",
                identity: identity,
                disposition: "unknown_tool",
                correlationHash: request.correlationHash
            )
            await stageNativeSpeechToolOutput(
                NativeSpeechToolOutput(
                    callID: request.callID,
                    output: output
                ),
                interaction: interaction,
                identity: identity
            )
            return
        }
        guard Self.nativeSpeechToolArguments(
            argumentsObject,
            satisfy: definition.parametersJSON
        ) else {
            output = Self.nativeSpeechToolErrorOutput("invalid_arguments")
            recordNativeSpeechToolDiagnostic(
                category: "tool_request_rejected",
                identity: identity,
                disposition: "invalid_arguments",
                correlationHash: request.correlationHash,
                toolName: definition.name
            )
            await stageNativeSpeechToolOutput(
                NativeSpeechToolOutput(
                    callID: request.callID,
                    output: output
                ),
                interaction: interaction,
                identity: identity
            )
            return
        }
        guard nativeSpeechToolExecutionTasks.count
                + nativeSpeechToolPermissionTasks.count
                < Self.nativeSpeechToolExecutionCapacity else {
            recordNativeSpeechToolDiagnostic(
                category: "tool_request_rejected",
                identity: identity,
                disposition: "executor_busy",
                correlationHash: request.correlationHash,
                toolName: definition.name
            )
            await stageNativeSpeechToolOutput(
                NativeSpeechToolOutput(
                    callID: request.callID,
                    output: Self.nativeSpeechToolErrorOutput("executor_busy")
                ),
                interaction: interaction,
                identity: identity
            )
            return
        }

        switch definition.permission {
        case .permissionFree:
            await scheduleNativeSpeechToolExecution(
                request,
                definition: definition,
                interaction: interaction,
                callIdentity: callIdentity
            )
        case .requiresPermission:
            await scheduleNativeSpeechToolPermission(
                request,
                definition: definition,
                interaction: interaction,
                callIdentity: callIdentity
            )
        }
    }

    private func scheduleNativeSpeechToolExecution(
        _ request: NativeSpeechToolRequest,
        definition: NativeSpeechToolDefinition,
        interaction: NativeSpeechInteraction,
        callIdentity: NativeSpeechToolCallIdentity
    ) async {
        guard nativeSpeechToolExecutionTasks.count
                + nativeSpeechToolPermissionTasks.count
                < Self.nativeSpeechToolExecutionCapacity else {
            recordNativeSpeechToolDiagnostic(
                category: "tool_request_rejected",
                identity: callIdentity.turn,
                disposition: "executor_busy",
                correlationHash: request.correlationHash,
                toolName: definition.name
            )
            await stageNativeSpeechToolOutput(
                NativeSpeechToolOutput(
                    callID: request.callID,
                    output: Self.nativeSpeechToolErrorOutput("executor_busy")
                ),
                interaction: interaction,
                identity: callIdentity.turn
            )
            do {
                try await continueNativeSpeechToolTurnIfReady(
                    interaction: interaction
                )
            } catch let error as NativeSpeechError {
                await failActiveNativeSpeechInteraction(
                    interactionID: interaction.id,
                    error: error
                )
            } catch {
                await failActiveNativeSpeechInteraction(
                    interactionID: interaction.id,
                    error: .transportFailure
                )
            }
            return
        }

        let executor = nativeSpeechToolExecutor
        let executionRequest = NativeSpeechToolExecutionRequest(
            interactionID: callIdentity.turn.interactionID,
            turnNumber: callIdentity.turn.turnNumber,
            turnGeneration: callIdentity.turn.turnGeneration,
            callID: request.callID,
            toolName: request.toolName,
            arguments: request.arguments,
            correlationHash: request.correlationHash
        )
        let taskStartGate = NativeSpeechToolTaskStartGate()
        let executionTask = Task { [weak self] in
            await taskStartGate.wait()
            guard !Task.isCancelled else { return }
            let result: Result<String, any Error>
            do {
                result = .success(try await executor.execute(executionRequest))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            await self?.completeNativeSpeechToolExecution(
                result,
                request: request,
                definition: definition,
                interaction: interaction,
                callIdentity: callIdentity
            )
        }
        nativeSpeechToolExecutionTasks[callIdentity] = executionTask
        await taskStartGate.open()
        recordNativeSpeechToolDiagnostic(
            category: "tool_execution_scheduled",
            identity: callIdentity.turn,
            disposition: "scheduled",
            correlationHash: request.correlationHash,
            toolName: definition.name
        )
    }

    private func scheduleNativeSpeechToolPermission(
        _ request: NativeSpeechToolRequest,
        definition: NativeSpeechToolDefinition,
        interaction: NativeSpeechInteraction,
        callIdentity: NativeSpeechToolCallIdentity
    ) async {
        let permissionRequest = NativeSpeechToolPermissionRequest(
            identity: callIdentity,
            toolName: definition.name,
            permission: definition.permission,
            displaySummary: definition.description,
            state: .pending,
            correlationHash: request.correlationHash
        )
        pendingNativeSpeechToolPermissions[callIdentity] =
            NativeSpeechToolPermissionContext(
                permissionRequest: permissionRequest,
                toolRequest: request,
                definition: definition,
                interaction: interaction
            )
        let resolver = nativeSpeechToolPermissionResolver
        let taskStartGate = NativeSpeechToolTaskStartGate()
        let permissionTask = Task { [weak self] in
            await taskStartGate.wait()
            guard !Task.isCancelled else { return }
            let decision = await resolver.resolve(permissionRequest)
            guard !Task.isCancelled else { return }
            await self?.completeNativeSpeechToolPermission(
                decision,
                request: permissionRequest
            )
        }
        nativeSpeechToolPermissionTasks[callIdentity] = permissionTask
        await taskStartGate.open()
        recordNativeSpeechToolDiagnostic(
            category: "tool_permission_requested",
            identity: callIdentity.turn,
            disposition: "pending",
            correlationHash: request.correlationHash,
            toolName: definition.name
        )
    }

    private func completeNativeSpeechToolPermission(
        _ decision: NativeSpeechToolPermissionDecision,
        request: NativeSpeechToolPermissionRequest
    ) async {
        let callIdentity = request.identity
        nativeSpeechToolPermissionTasks[callIdentity] = nil
        guard let context = pendingNativeSpeechToolPermissions.removeValue(
            forKey: callIdentity
        ) else {
            let isCurrent = nativeSpeechInteractionGate.current()?.id
                    == callIdentity.turn.interactionID
                && realtimeSpeechStateMachine.snapshot().currentTurnNumber
                    == callIdentity.turn.turnNumber
                && realtimeSpeechSubtitleStateMachine.snapshot()
                    .turnGeneration == callIdentity.turn.turnGeneration
            recordNativeSpeechToolDiagnostic(
                category: isCurrent
                    ? "tool_permission_duplicate"
                    : "tool_permission_stale",
                identity: callIdentity.turn,
                disposition: "ignored",
                correlationHash: request.correlationHash,
                toolName: request.toolName
            )
            return
        }
        guard nativeSpeechToolTurnIsCurrent(
            callIdentity.turn,
            interaction: context.interaction
        ), handledNativeSpeechToolCalls.contains(callIdentity),
           nativeSpeechToolTurnState?.identity == callIdentity.turn,
           nativeSpeechToolTurnState?.pendingCallIDs.contains(
                callIdentity.callID
           ) == true else {
            recordNativeSpeechToolDiagnostic(
                category: "tool_permission_stale",
                identity: callIdentity.turn,
                disposition: "discarded",
                correlationHash: request.correlationHash,
                toolName: request.toolName
            )
            return
        }

        switch decision {
        case .approved:
            recordNativeSpeechToolDiagnostic(
                category: "tool_permission_approved",
                identity: callIdentity.turn,
                disposition: "approved",
                correlationHash: request.correlationHash,
                toolName: request.toolName
            )
            await scheduleNativeSpeechToolExecution(
                context.toolRequest,
                definition: context.definition,
                interaction: context.interaction,
                callIdentity: callIdentity
            )
        case .denied:
            await completeNativeSpeechToolPermissionRejection(
                code: "permission_denied",
                category: "tool_permission_denied",
                context: context
            )
        case .unavailable:
            await completeNativeSpeechToolPermissionRejection(
                code: "permission_unavailable",
                category: "tool_permission_unavailable",
                context: context
            )
        case .cancelled:
            await completeNativeSpeechToolPermissionRejection(
                code: "permission_cancelled",
                category: "tool_permission_cancelled",
                context: context
            )
        case .stale:
            await completeNativeSpeechToolPermissionRejection(
                code: "permission_stale",
                category: "tool_permission_stale",
                context: context
            )
        }
    }

    private func completeNativeSpeechToolPermissionRejection(
        code: String,
        category: String,
        context: NativeSpeechToolPermissionContext
    ) async {
        let request = context.permissionRequest
        recordNativeSpeechToolDiagnostic(
            category: category,
            identity: request.identity.turn,
            disposition: code,
            correlationHash: request.correlationHash,
            toolName: request.toolName
        )
        await stageNativeSpeechToolOutput(
            NativeSpeechToolOutput(
                callID: request.identity.callID,
                output: Self.nativeSpeechToolErrorOutput(code)
            ),
            interaction: context.interaction,
            identity: request.identity.turn
        )
        do {
            try await continueNativeSpeechToolTurnIfReady(
                interaction: context.interaction
            )
        } catch let error as NativeSpeechError {
            await failActiveNativeSpeechInteraction(
                interactionID: context.interaction.id,
                error: error
            )
        } catch {
            await failActiveNativeSpeechInteraction(
                interactionID: context.interaction.id,
                error: .transportFailure
            )
        }
    }

    private func stageNativeSpeechToolCall(
        callID: String,
        identity: NativeSpeechToolTurnIdentity
    ) {
        var state = nativeSpeechToolTurnState
        if state?.identity != identity {
            state = NativeSpeechToolTurnState(
                identity: identity,
                outputs: [],
                pendingCallIDs: [],
                responseBoundaryReceived: false,
                waitsForPlaybackDrain:
                    nativeSpeechTurnsWithOutputAudio.contains(identity),
                playbackDrained: false,
                continuationRequested: false
            )
        }
        state?.pendingCallIDs.insert(callID)
        nativeSpeechToolTurnState = state
    }

    private func completeNativeSpeechToolExecution(
        _ result: Result<String, any Error>,
        request: NativeSpeechToolRequest,
        definition: NativeSpeechToolDefinition,
        interaction: NativeSpeechInteraction,
        callIdentity: NativeSpeechToolCallIdentity
    ) async {
        nativeSpeechToolExecutionTasks[callIdentity] = nil
        guard nativeSpeechToolTurnIsCurrent(
            callIdentity.turn,
            interaction: interaction
        ), handledNativeSpeechToolCalls.contains(callIdentity),
           nativeSpeechToolTurnState?.identity == callIdentity.turn,
           nativeSpeechToolTurnState?.pendingCallIDs.contains(request.callID)
                == true else {
            recordNativeSpeechToolDiagnostic(
                category: "tool_execution_stale",
                identity: callIdentity.turn,
                disposition: "discarded",
                correlationHash: request.correlationHash,
                toolName: definition.name
            )
            return
        }
        let output: String
        switch result {
        case .success(let value):
            output = value
            recordNativeSpeechToolDiagnostic(
                category: "tool_request_executed",
                identity: callIdentity.turn,
                disposition: "completed",
                correlationHash: request.correlationHash,
                toolName: definition.name
            )
            recordNativeSpeechToolDiagnostic(
                category: "tool_execution_completed",
                identity: callIdentity.turn,
                disposition: "completed",
                correlationHash: request.correlationHash,
                toolName: definition.name
            )
        case .failure:
            output = Self.nativeSpeechToolErrorOutput("execution_failed")
            recordNativeSpeechToolDiagnostic(
                category: "tool_request_failed",
                identity: callIdentity.turn,
                disposition: "execution_failed",
                correlationHash: request.correlationHash,
                toolName: definition.name
            )
            recordNativeSpeechToolDiagnostic(
                category: "tool_execution_completed",
                identity: callIdentity.turn,
                disposition: "execution_failed",
                correlationHash: request.correlationHash,
                toolName: definition.name
            )
        }
        await stageNativeSpeechToolOutput(
            NativeSpeechToolOutput(callID: request.callID, output: output),
            interaction: interaction,
            identity: callIdentity.turn
        )
        do {
            try await continueNativeSpeechToolTurnIfReady(
                interaction: interaction
            )
        } catch let error as NativeSpeechError {
            await failActiveNativeSpeechInteraction(
                interactionID: interaction.id,
                error: error
            )
        } catch {
            await failActiveNativeSpeechInteraction(
                interactionID: interaction.id,
                error: .transportFailure
            )
        }
    }

    private func stageNativeSpeechToolOutput(
        _ output: NativeSpeechToolOutput,
        interaction: NativeSpeechInteraction,
        identity: NativeSpeechToolTurnIdentity
    ) async {
        guard nativeSpeechToolTurnIsCurrent(
            identity,
            interaction: interaction
        ) else {
            recordNativeSpeechToolDiagnostic(
                category: "tool_execution_stale",
                identity: identity,
                disposition: "discarded"
            )
            return
        }
        var state = nativeSpeechToolTurnState
        if state?.identity != identity {
            state = NativeSpeechToolTurnState(
                identity: identity,
                outputs: [],
                pendingCallIDs: [],
                responseBoundaryReceived: false,
                waitsForPlaybackDrain:
                    nativeSpeechTurnsWithOutputAudio.contains(identity),
                playbackDrained: false,
                continuationRequested: false
            )
        }
        state?.pendingCallIDs.remove(output.callID)
        state?.outputs.append(output)
        nativeSpeechToolTurnState = state
    }

    private func continueNativeSpeechToolTurnIfReady(
        interaction: NativeSpeechInteraction
    ) async throws {
        guard let state = claimNativeSpeechToolContinuationIfReady() else {
            return
        }
        guard nativeSpeechToolTurnIsCurrent(
            state.identity,
            interaction: interaction
        ) else {
            discardNativeSpeechToolContinuationClaim(
                identity: state.identity
            )
            return
        }
        let transition = realtimeSpeechStateMachine.prepareToolContinuation(
            interaction: interaction,
            turnNumber: state.identity.turnNumber,
            nowNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        guard transition.disposition == .applied else {
            releaseNativeSpeechToolContinuationClaim(
                identity: state.identity
            )
            recordNativeSpeechToolDiagnostic(
                category: "tool_continuation_rejected",
                identity: state.identity,
                disposition: transition.disposition.rawValue
            )
            return
        }
        let subtitleDisposition = realtimeSpeechSubtitleStateMachine
            .prepareResidentContinuation(
                interactionID: interaction.id,
                turnNumber: state.identity.turnNumber,
                turnGeneration: state.identity.turnGeneration
            )
        guard subtitleDisposition == .accepted else {
            releaseNativeSpeechToolContinuationClaim(
                identity: state.identity
            )
            recordNativeSpeechToolDiagnostic(
                category: "tool_continuation_rejected",
                identity: state.identity,
                disposition: subtitleDisposition.rawValue
            )
            return
        }
        for output in state.outputs {
            try await executionEngine.submitNativeSpeechToolOutput(
                output,
                interactionID: interaction.id
            )
            guard nativeSpeechToolContinuationIsCurrent(
                state,
                interaction: interaction
            ) else {
                recordNativeSpeechToolDiagnostic(
                    category: "tool_continuation_stale",
                    identity: state.identity,
                    disposition: "terminated_after_output"
                )
                return
            }
        }
        try await executionEngine.requestNativeSpeechToolContinuation(
            interactionID: interaction.id
        )
        guard nativeSpeechToolContinuationIsCurrent(
            state,
            interaction: interaction
        ) else {
                recordNativeSpeechToolDiagnostic(
                    category: "tool_continuation_stale",
                    identity: state.identity,
                    disposition: "terminated_after_continuation_request"
                )
            return
        }
        recordNativeSpeechToolDiagnostic(
            category: "tool_continuation_started",
            identity: state.identity,
            disposition: "continuation_requested"
        )
        nativeSpeechTurnsWithOutputAudio.remove(state.identity)
        discardNativeSpeechToolContinuationClaim(identity: state.identity)
        scheduleRealtimeSpeechGuard(for: interaction)
    }

    private func nativeSpeechToolContinuationIsCurrent(
        _ state: NativeSpeechToolTurnState,
        interaction: NativeSpeechInteraction
    ) -> Bool {
        guard nativeSpeechToolTurnIsCurrent(
            state.identity,
            interaction: interaction
        ) else {
            return false
        }
        nativeSpeechToolContinuationClaimLock.lock()
        defer { nativeSpeechToolContinuationClaimLock.unlock() }
        return nativeSpeechToolTurnState?.identity == state.identity
            && nativeSpeechToolTurnState?.continuationRequested == true
    }

    private func claimNativeSpeechToolContinuationIfReady()
        -> NativeSpeechToolTurnState? {
        nativeSpeechToolContinuationClaimLock.lock()
        defer { nativeSpeechToolContinuationClaimLock.unlock() }
        guard var state = nativeSpeechToolTurnState,
              state.responseBoundaryReceived,
              state.pendingCallIDs.isEmpty,
              !state.outputs.isEmpty,
              !state.continuationRequested,
              !state.waitsForPlaybackDrain || state.playbackDrained else {
            return nil
        }
        state.continuationRequested = true
        nativeSpeechToolTurnState = state
        return state
    }

    private func releaseNativeSpeechToolContinuationClaim(
        identity: NativeSpeechToolTurnIdentity
    ) {
        nativeSpeechToolContinuationClaimLock.lock()
        defer { nativeSpeechToolContinuationClaimLock.unlock() }
        guard var state = nativeSpeechToolTurnState,
              state.identity == identity else {
            return
        }
        state.continuationRequested = false
        nativeSpeechToolTurnState = state
    }

    private func discardNativeSpeechToolContinuationClaim(
        identity: NativeSpeechToolTurnIdentity
    ) {
        nativeSpeechToolContinuationClaimLock.lock()
        defer { nativeSpeechToolContinuationClaimLock.unlock() }
        guard nativeSpeechToolTurnState?.identity == identity else {
            return
        }
        nativeSpeechToolTurnState = nil
    }

    private func nativeSpeechToolTurnIsCurrent(
        _ identity: NativeSpeechToolTurnIdentity,
        interaction: NativeSpeechInteraction
    ) -> Bool {
        guard nativeSpeechInteractionGate.current()?.id
                == identity.interactionID,
              interaction.id == identity.interactionID,
              realtimeSpeechStateMachine.snapshot().currentTurnNumber
                == identity.turnNumber,
              realtimeSpeechSubtitleStateMachine.snapshot().turnGeneration
                == identity.turnGeneration else {
            return false
        }
        return true
    }

    private func recordNativeSpeechToolDiagnostic(
        category: String,
        identity: NativeSpeechToolTurnIdentity,
        disposition: String,
        correlationHash: String? = nil,
        toolName: String? = nil
    ) {
        nativeSpeechDiagnosticBuffer?.append(
            NativeSpeechInternalDiagnosticEvent(
                source: .runtime,
                category: toolName.map { "\(category):\($0)" }
                    ?? category,
                interactionShortID: String(
                    identity.interactionID.rawValue.uuidString.prefix(8)
                ),
                turnNumber: identity.turnNumber,
                turnGeneration: identity.turnGeneration,
                stateBefore: realtimeSpeechStateMachine.snapshot()
                    .state.rawValue,
                stateAfter: realtimeSpeechStateMachine.snapshot()
                    .state.rawValue,
                disposition: disposition,
                itemCorrelationHash: correlationHash
            )
        )
    }

    private static func nativeSpeechToolArgumentsObject(
        _ arguments: Data
    ) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: arguments))
            as? [String: Any]
    }

    private static func nativeSpeechToolArguments(
        _ arguments: [String: Any],
        satisfy schemaData: Data
    ) -> Bool {
        guard let schema = try? JSONSerialization.jsonObject(
            with: schemaData
        ) as? [String: Any],
              (schema["type"] as? String).map({ $0 == "object" })
                ?? true else {
            return false
        }
        let required = schema["required"] as? [String] ?? []
        guard required.allSatisfy({ arguments[$0] != nil }) else {
            return false
        }
        guard let properties = schema["properties"]
                as? [String: [String: Any]] else {
            return true
        }
        for (name, value) in arguments {
            guard let property = properties[name],
                  let type = property["type"] as? String else {
                continue
            }
            let matches = switch type {
            case "string": value is String
            case "boolean": value is Bool
            case "number": value is NSNumber && !(value is Bool)
            case "integer": (value as? NSNumber).map {
                !(value is Bool)
                    && floor($0.doubleValue) == $0.doubleValue
            } ?? false
            case "object": value is [String: Any]
            case "array": value is [Any]
            case "null": value is NSNull
            default: false
            }
            guard matches else { return false }
        }
        return true
    }

    private static func nativeSpeechToolErrorOutput(
        _ code: String
    ) -> String {
        "{\"error\":{\"code\":\"\(code)\"}}"
    }

    private static func nativeSpeechEventCategory(
        _ kind: NativeSpeechEventKind?
    ) -> String {
        guard let kind else { return "receive_request" }
        return switch kind {
        case .connected: "connected"
        case .sessionUpdated: "session_updated"
        case .inputSpeechStarted: "input_speech_started"
        case .inputSpeechEnded: "input_speech_ended"
        case .partialTranscript: "user_partial"
        case .finalTranscript: "user_final"
        case .thinking: "thinking"
        case .outputText(_, let isFinal):
            isFinal ? "resident_final" : "resident_partial"
        case .outputAudio: "output_audio"
        case .toolRequestCandidate: "tool_request_candidate"
        case .responseCompleted: "response_completed"
        case .turnFailed: "turn_failed"
        case .cancelled: "cancelled"
        case .closed: "closed"
        case .failed: "failed"
        }
    }

    private static func playbackEventCategory(
        _ kind: RealtimeSpeechPlaybackEventKind
    ) -> String {
        return switch kind {
        case .started: "started"
        case .stalled: "stalled"
        case .resumed: "resumed"
        case .completed: "completed"
        case .failed: "failed"
        }
    }

    private func failActiveNativeSpeechInteraction(
        interactionID: NativeSpeechInteractionID,
        error: NativeSpeechError
    ) async {
        guard let interaction = nativeSpeechInteractionGate.clear(
            matching: interactionID
        ) else {
            return
        }
        realtimeSpeechGuardScheduler.cancel()
        resetNativeSpeechToolState()
        _ = realtimeSpeechStateMachine.fail(
            interactionID: interaction.id,
            error: error
        )
        if realtimeSpeechSubtitleStateMachine.tracks(interaction.id) {
            _ = realtimeSpeechSubtitleStateMachine.terminate(
                interactionID: interaction.id,
                reason: .failed
            )
        }
        invalidateNativeSpeechInput(for: interaction.id)
        try? await executionEngine.cancelNativeSpeech(
            interactionID: interaction.id,
            reason: .interrupted
        )
        try? await executionEngine.closeNativeSpeech(
            interactionID: interaction.id
        )
    }

    private func refreshNativeSpeechContext(
        interactionID: NativeSpeechInteractionID,
        currentUserInput: String,
        reason: RealtimeSpeechContextRefreshReason
    ) async throws {
        guard let interaction = nativeSpeechInteractionGate.current(),
              interaction.id == interactionID,
              sessionContext?.residentID == interaction.residentID,
              sessionContext?.sessionID.rawValue == interaction.sessionID else {
            throw NativeSpeechError.interactionMismatch
        }
        let compilationKey = RealtimeSpeechContextCompilationKey(
            interactionID: interactionID,
            refreshReason: reason,
            sourceRevision: realtimeSpeechContextSourceRevision,
            currentUserInput: currentUserInput
        )
        guard !nativeSpeechInteractionGate.hasCompilationKey(
            compilationKey
        ) else {
            return
        }
        guard let compiledContext = compiledResidentDialogueContext(
            currentUserInput: currentUserInput
        ) else {
            throw NativeSpeechError.unavailable
        }
        let projection = try realtimeSpeechContextCompiler.compile(
            context: compiledContext.context,
            interaction: interaction,
            refreshReason: reason
        )
        if nativeSpeechInteractionGate.currentContextProjection(
            matching: interactionID
        )?.compilationVersion == projection.compilationVersion {
            guard nativeSpeechInteractionGate.updateCompilationKey(
                compilationKey
            ) else {
                throw NativeSpeechError.interactionMismatch
            }
            return
        }
        try await executionEngine.updateNativeSpeechContext(projection)
        guard nativeSpeechInteractionGate.updateContextProjection(
            projection,
            compilationKey: compilationKey
        ) else {
            throw NativeSpeechError.interactionMismatch
        }
    }

    func cancelActiveNativeSpeechInteraction(
        reason: NativeSpeechCancellationReason
    ) async throws {
        guard let interaction = nativeSpeechInteractionGate.clear() else {
            return
        }
        realtimeSpeechGuardScheduler.cancel()
        resetNativeSpeechToolState()
        realtimeSpeechStateMachine.stop(
            interactionID: interaction.id,
            reason: reason
        )
        if realtimeSpeechSubtitleStateMachine.tracks(interaction.id) {
            _ = realtimeSpeechSubtitleStateMachine.terminate(
                interactionID: interaction.id,
                reason: Self.subtitleClosureReason(reason)
            )
        }
        invalidateNativeSpeechInput(for: interaction.id)
        do {
            try await executionEngine.cancelNativeSpeech(
                interactionID: interaction.id,
                reason: reason
            )
        } catch {
            try? await executionEngine.closeNativeSpeech(
                interactionID: interaction.id
            )
            throw error
        }
        try await executionEngine.closeNativeSpeech(
            interactionID: interaction.id
        )
    }

    func closeActiveNativeSpeechInteraction() async throws {
        guard let interaction = nativeSpeechInteractionGate.clear() else {
            return
        }
        realtimeSpeechGuardScheduler.cancel()
        resetNativeSpeechToolState()
        realtimeSpeechStateMachine.stop(
            interactionID: interaction.id,
            reason: .interrupted
        )
        if realtimeSpeechSubtitleStateMachine.tracks(interaction.id) {
            _ = realtimeSpeechSubtitleStateMachine.terminate(
                interactionID: interaction.id,
                reason: .closed
            )
        }
        invalidateNativeSpeechInput(for: interaction.id)
        try await executionEngine.closeNativeSpeech(
            interactionID: interaction.id
        )
    }

    func nativeSpeechDisposition(
        for event: NativeSpeechEvent,
        expectedInteractionID: NativeSpeechInteractionID
    ) -> NativeSpeechEventDisposition {
        guard let interaction = nativeSpeechInteractionGate.current(),
              interaction.id == expectedInteractionID,
              event.interactionID == expectedInteractionID else {
            return .rejectedStale
        }
        if case .outputAudio(let payload) = event.kind,
           payload.interactionID != expectedInteractionID {
            return .rejectedStale
        }
        switch event.kind {
        case .cancelled, .closed, .failed:
            realtimeSpeechGuardScheduler.cancel()
            resetNativeSpeechToolState()
            nativeSpeechInteractionGate.clear(
                matching: expectedInteractionID
            )
            invalidateNativeSpeechInput(for: expectedInteractionID)
        default:
            break
        }
        return .accepted(event)
    }

    private func invalidateNativeSpeechInput(
        for interactionID: NativeSpeechInteractionID? = nil
    ) {
        nativeSpeechInputGate.invalidate(interactionID: interactionID)
    }

    func realtimeSpeechStateSnapshot() -> RealtimeSpeechStateSnapshot {
        realtimeSpeechStateMachine.snapshot()
    }

    func realtimeSpeechSubtitleSnapshot()
        -> RealtimeSpeechSubtitleSnapshot {
        realtimeSpeechSubtitleStateMachine.snapshot()
    }

    #if DEBUG
    func handledNativeSpeechToolCallCountForTesting() -> Int {
        handledNativeSpeechToolCalls.count
    }

    func pendingNativeSpeechToolPermissionCountForTesting() -> Int {
        pendingNativeSpeechToolPermissions.count
    }

    func nativeSpeechToolPermissionTaskCountForTesting() -> Int {
        nativeSpeechToolPermissionTasks.count
    }

    func nativeSpeechToolLifecycleDebugSnapshot()
        -> NativeSpeechToolLifecycleDebugSnapshot {
        nativeSpeechToolContinuationClaimLock.lock()
        let turnState = nativeSpeechToolTurnState
        nativeSpeechToolContinuationClaimLock.unlock()
        return NativeSpeechToolLifecycleDebugSnapshot(
            executionTaskCount: nativeSpeechToolExecutionTasks.count,
            permissionTaskCount: nativeSpeechToolPermissionTasks.count,
            pendingPermissionCount: pendingNativeSpeechToolPermissions.count,
            handledCallCount: handledNativeSpeechToolCalls.count,
            hasTurnState: turnState != nil,
            playbackIdentityCount: nativeSpeechTurnsWithOutputAudio.count,
            continuationClaimed: turnState?.continuationRequested == true
        )
    }

    func applyNativeSpeechToolPermissionDecisionForTesting(
        _ decision: NativeSpeechToolPermissionDecision,
        request: NativeSpeechToolPermissionRequest
    ) async {
        await completeNativeSpeechToolPermission(
            decision,
            request: request
        )
    }

    func waitForNativeSpeechToolPermissionTasksForTesting() async {
        let tasks = Array(nativeSpeechToolPermissionTasks.values)
        for task in tasks {
            await task.value
        }
    }
    #endif

    func useRealtimeSpeechTimeoutConfigurationForTesting(
        _ configuration: RealtimeSpeechTimeoutConfiguration
    ) {
        realtimeSpeechStateMachine.useTimeoutConfigurationForTesting(
            configuration
        )
    }

    private func scheduleRealtimeSpeechGuard(
        for interaction: NativeSpeechInteraction
    ) {
        let request = realtimeSpeechStateMachine.guardRequest(
            interaction: interaction,
            nowNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        realtimeSpeechGuardScheduler.schedule(request) {
            [realtimeSpeechTimeoutHandler] request in
            await realtimeSpeechTimeoutHandler.handle(request)
        }
    }

    private func resetRealtimeSpeechState() {
        realtimeSpeechGuardScheduler.cancel()
        realtimeSpeechStateMachine.reset()
        realtimeSpeechSubtitleStateMachine.reset()
        resetNativeSpeechToolState()
    }

    private func resetNativeSpeechToolState() {
        for task in nativeSpeechToolExecutionTasks.values {
            task.cancel()
        }
        for task in nativeSpeechToolPermissionTasks.values {
            task.cancel()
        }
        nativeSpeechToolExecutionTasks.removeAll(keepingCapacity: true)
        nativeSpeechToolPermissionTasks.removeAll(keepingCapacity: true)
        pendingNativeSpeechToolPermissions.removeAll(keepingCapacity: true)
        handledNativeSpeechToolCalls.removeAll(keepingCapacity: true)
        nativeSpeechToolContinuationClaimLock.lock()
        nativeSpeechToolTurnState = nil
        nativeSpeechToolContinuationClaimLock.unlock()
        nativeSpeechTurnsWithOutputAudio.removeAll(keepingCapacity: true)
    }

    private func nativeSpeechEventIsTerminal(
        _ event: NativeSpeechEvent
    ) -> Bool {
        switch event.kind {
        case .cancelled, .closed, .failed:
            return true
        default:
            return false
        }
    }

    private static func subtitleClosureReason(
        _ reason: NativeSpeechCancellationReason
    ) -> RealtimeSpeechSubtitleClosureReason {
        switch reason {
        case .stopped: .stopped
        case .interrupted: .cancelled
        case .superseded: .superseded
        }
    }

    func requestResidentReply(
        inputText: String,
        interactionID: UUID? = nil,
        defersSuccessfulCommit: Bool = false
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
        var relationshipDecision = defersSuccessfulCommit
            ? currentRelationshipDecision(reason: "playback_pending")
            : applyRelationshipUserControl(relationshipControl)
        let narrativeMemoryControl = narrativeMemoryUserControl(
            for: inputText
        )
        var narrativeMemoryControlResult = defersSuccessfulCommit
            ? RuntimeNarrativeMemoryControlResult(
                control: narrativeMemoryControl,
                affectedMemoryIDs: [],
                decision: "pending",
                reason: "playback_pending"
            )
            : applyNarrativeMemoryUserControl(
                narrativeMemoryControl,
                input: inputText,
                residentID: sessionAtStart.residentID
            )
        var narrativeMemoryDecisions =
            [RuntimeNarrativeMemoryDecision]()
        guard let compiledContext = compiledResidentDialogueContext(
            currentUserInput: inputText
        ) else {
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
                relationshipDecision: relationshipDecision,
                narrativeMemoryActivity:
                    runtimeNarrativeMemoryOrchestrationMetadata(
                        controlResult:
                            narrativeMemoryControlResult,
                        retrievedMemoryIDs: []
                    )
            )
            #endif
            return .failure(.residentUnavailable)
        }
        let context = compiledContext.context

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
        let result = await executionEngine.requestResidentReply(
            context: context,
            expressionMapping: expressionMappingAtStart,
            narrativeMemoryProjection:
                currentNarrativeMemoryProjection
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
                relationshipDecision: relationshipDecision,
                narrativeMemoryActivity:
                    runtimeNarrativeMemoryOrchestrationMetadata(
                        controlResult:
                            narrativeMemoryControlResult,
                        retrievedMemoryIDs:
                            compiledContext.retrievedMemoryIDs
                    )
            )
            #endif
            return .failure(.cancelled)
        }
        activeExpressionRequestID = nil

        var sessionWriteSucceeded = false
        #if DEBUG
        let sessionWriteStartedAt = Date()
        #endif
        if case .success(let reply) = result,
           !defersSuccessfulCommit {
            _ = commitExpressionResult(
                reply.expression,
                expectedSession: sessionAtStart
            )
            if relationshipControl == nil {
                relationshipDecision = evaluateRelationshipEvidence(
                    reply.relationshipEvidenceCandidates
                )
            }
            narrativeMemoryDecisions =
                evaluateNarrativeMemoryCandidates(
                    reply.narrativeMemoryCandidates,
                    session: sessionAtStart,
                    userControl: narrativeMemoryControl
                )
            sessionWriteSucceeded = persistResidentDialogueExchange(
                userInput: inputText,
                residentReply: reply.replyText,
                session: sessionAtStart
            )
        }
        let providerSucceeded: Bool
        if case .success = result {
            providerSucceeded = true
        } else {
            providerSucceeded = false
        }
        narrativeMemoryControlResult =
            finalizedNarrativeMemoryControlResult(
                narrativeMemoryControlResult,
                candidateDecisions: narrativeMemoryDecisions,
                providerSucceeded: providerSucceeded
            )
        #if DEBUG
        let sessionWriteStatus: RuntimeOrchestrationSessionWriteStatus
        let sessionStepStatus: RuntimeOrchestrationStepStatus
        switch result {
        case .success:
            if defersSuccessfulCommit {
                sessionWriteStatus = .skipped
                sessionStepStatus = .pending
            } else {
                sessionWriteStatus = sessionWriteSucceeded ? .saved : .failed
                sessionStepStatus = sessionWriteSucceeded ? .completed : .failed
            }
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
            relationshipDecision: relationshipDecision,
            narrativeMemoryDecisions:
                narrativeMemoryDecisions,
            narrativeMemoryActivity:
                runtimeNarrativeMemoryOrchestrationMetadata(
                    controlResult: narrativeMemoryControlResult,
                    retrievedMemoryIDs:
                        compiledContext.retrievedMemoryIDs
                )
        )
        #endif
        return result
    }

    func testResidentReply(
        inputText: String,
        interactionID: UUID? = nil
    ) async -> Result<RuntimeResidentReply, ProviderRequestError> {
        await requestResidentReply(
            inputText: inputText,
            interactionID: interactionID
        )
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

    private func completeSpeechRoutePersistence(
        interactionID: UUID?,
        succeeded: Bool
    ) {
        #if DEBUG
        guard let interactionID,
              let index = runtimeOrchestrationRecords.firstIndex(where: {
                  $0.id == interactionID
              }) else {
            return
        }
        runtimeOrchestrationRecords[index].sessionWriteStatus =
            succeeded ? .saved : .failed
        if let stepIndex = runtimeOrchestrationRecords[index].steps.firstIndex(where: {
            $0.kind == .sessionPersisted
        }) {
            runtimeOrchestrationRecords[index].steps[stepIndex].status =
                succeeded ? .completed : .failed
        }
        runtimeOrchestrationRecords[index].endedAt = Date()
        #endif
    }

    #if DEBUG
    func useNarrativeMemoryStoreForTesting(
        _ store: NarrativeMemoryStore
    ) {
        narrativeMemoryStore = store
        realtimeSpeechContextSourceRevision &+= 1
    }

    func narrativeMemoryDebugSnapshot()
        -> RuntimeNarrativeMemoryStoreSnapshot? {
        guard let residentID = currentResidentIdentity?.residentID else {
            return nil
        }
        return try? narrativeMemoryStore.load(
            residentID: residentID
        )
    }

    func realtimeSpeechContextSourceRevisionForTesting() -> UInt64 {
        realtimeSpeechContextSourceRevision
    }

    func useRelationshipStateStoreForTesting(
        _ store: RelationshipStateStore
    ) {
        relationshipStateStore = store
        realtimeSpeechContextSourceRevision &+= 1
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
            RuntimeRelationshipDecision = .unavailable,
        narrativeMemoryDecisions:
            [RuntimeNarrativeMemoryDecision] = [],
        narrativeMemoryActivity:
            RuntimeNarrativeMemoryOrchestrationMetadata = .none
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
            narrativeMemoryDecisions: narrativeMemoryDecisions,
            narrativeMemoryActivity: narrativeMemoryActivity,
            steps: normalizedSteps
        )
        runtimeOrchestrationRecords.append(interaction)
        if runtimeOrchestrationRecords.count > Self.runtimeOrchestrationCapacity {
            runtimeOrchestrationRecords.removeFirst(
                runtimeOrchestrationRecords.count - Self.runtimeOrchestrationCapacity
            )
        }
    }

    private func runtimeNarrativeMemoryOrchestrationMetadata(
        controlResult: RuntimeNarrativeMemoryControlResult,
        retrievedMemoryIDs: [String]
    ) -> RuntimeNarrativeMemoryOrchestrationMetadata {
        RuntimeNarrativeMemoryOrchestrationMetadata(
            retrievalCount: retrievedMemoryIDs.count,
            retrievedMemoryIDs: retrievedMemoryIDs,
            affectedMemoryIDs: controlResult.affectedMemoryIDs,
            userOperation: controlResult.control?.rawValue ?? "none",
            decision: controlResult.decision,
            reason: controlResult.reason
        )
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
