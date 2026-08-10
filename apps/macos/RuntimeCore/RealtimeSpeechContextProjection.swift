import Foundation

nonisolated enum RealtimeSpeechContextLayer: String, CaseIterable, Sendable {
    case identityCore = "identity_core"
    case personality
    case safetyBoundary = "safety_boundary"
    case legalAuthorization = "legal_authorization"
    case memory
    case knowledge
    case worldEnvironment = "world_environment"
    case behavior
    case capabilityTools = "capability_tools"
    case multimodalExpression = "multimodal_expression"
    case relationship
    case selfGrowth = "self_growth"
    case outputDeployment = "output_deployment"
}

nonisolated enum RealtimeSpeechProjectionCategory: String, Sendable {
    case sessionBase = "SESSION_BASE"
    case turnRequired = "TURN_REQUIRED"
    case onDemand = "ON_DEMAND"
    case runtimeOnly = "RUNTIME_ONLY"
    case notApplicableYet = "NOT_APPLICABLE_YET"
}

nonisolated enum RealtimeSpeechContextPriority: Int, Sendable {
    case critical = 0
    case high = 1
    case medium = 2
    case low = 3
}

nonisolated enum RealtimeSpeechContextPrivacy: String, Sendable {
    case residentCore = "RESIDENT_CORE"
    case safetyCritical = "SAFETY_CRITICAL"
    case authorizationRestricted = "AUTHORIZATION_RESTRICTED"
    case userPrivate = "USER_PRIVATE"
    case authorizedKnowledge = "AUTHORIZED_KNOWLEDGE"
    case sessionSensitive = "SESSION_SENSITIVE"
    case capabilityRestricted = "CAPABILITY_RESTRICTED"
    case presentationOnly = "PRESENTATION_ONLY"
    case relationshipPrivate = "RELATIONSHIP_PRIVATE"
    case internalRuntime = "INTERNAL_RUNTIME"
}

nonisolated enum RealtimeSpeechContextRefreshReason: String, Sendable {
    case interactionStarted = "interaction_started"
    case finalTranscript = "final_transcript"
    case residentChanged = "resident_changed"
    case sessionChanged = "session_changed"
    case relationshipChanged = "relationship_changed"
    case memoryChanged = "memory_changed"
    case toolPermissionChanged = "tool_permission_changed"
}

nonisolated enum RealtimeSpeechContextSectionScope: String, Sendable {
    case sessionBase = "session_base"
    case currentTurn = "current_turn"
    case dynamic = "dynamic"
    case recentDialogue = "recent_dialogue"
}

nonisolated enum RealtimeSpeechConversationPacingPolicy {
    static let instruction = """
    For realtime voice replies, give the direct conclusion or answer first.
    By default, reply in one to three concise spoken sentences, then stop naturally so the user can respond.
    Expand beyond three sentences only when the user explicitly asks for detail.
    Avoid long monologues, repeated summaries, written-answer recitation, and generic assistant filler.
    """
}

nonisolated enum RealtimeSpeechContextSource: Sendable, Equatable {
    case residentLayer(RealtimeSpeechContextLayer)
    case recentDialogue
}

nonisolated struct RealtimeSpeechContextLayerPolicy: Sendable, Equatable {
    let layer: RealtimeSpeechContextLayer
    let category: RealtimeSpeechProjectionCategory
    let priority: RealtimeSpeechContextPriority
    let privacy: RealtimeSpeechContextPrivacy
    let allowsTrimming: Bool
    let providerEligible: Bool
}

nonisolated enum RealtimeSpeechContextContract {
    static let layerPolicies: [RealtimeSpeechContextLayerPolicy] = [
        .init(layer: .identityCore, category: .sessionBase, priority: .critical, privacy: .residentCore, allowsTrimming: false, providerEligible: true),
        .init(layer: .personality, category: .sessionBase, priority: .high, privacy: .residentCore, allowsTrimming: true, providerEligible: true),
        .init(layer: .safetyBoundary, category: .sessionBase, priority: .critical, privacy: .safetyCritical, allowsTrimming: false, providerEligible: true),
        .init(layer: .legalAuthorization, category: .sessionBase, priority: .critical, privacy: .authorizationRestricted, allowsTrimming: false, providerEligible: true),
        .init(layer: .memory, category: .onDemand, priority: .high, privacy: .userPrivate, allowsTrimming: true, providerEligible: true),
        .init(layer: .knowledge, category: .onDemand, priority: .medium, privacy: .authorizedKnowledge, allowsTrimming: true, providerEligible: true),
        .init(layer: .worldEnvironment, category: .onDemand, priority: .medium, privacy: .sessionSensitive, allowsTrimming: true, providerEligible: true),
        .init(layer: .behavior, category: .sessionBase, priority: .high, privacy: .residentCore, allowsTrimming: true, providerEligible: true),
        .init(layer: .capabilityTools, category: .notApplicableYet, priority: .high, privacy: .capabilityRestricted, allowsTrimming: true, providerEligible: false),
        .init(layer: .multimodalExpression, category: .runtimeOnly, priority: .low, privacy: .presentationOnly, allowsTrimming: true, providerEligible: false),
        .init(layer: .relationship, category: .turnRequired, priority: .high, privacy: .relationshipPrivate, allowsTrimming: true, providerEligible: true),
        .init(layer: .selfGrowth, category: .notApplicableYet, priority: .low, privacy: .residentCore, allowsTrimming: true, providerEligible: false),
        .init(layer: .outputDeployment, category: .runtimeOnly, priority: .critical, privacy: .internalRuntime, allowsTrimming: false, providerEligible: false)
    ]

    static func policy(
        for layer: RealtimeSpeechContextLayer
    ) -> RealtimeSpeechContextLayerPolicy {
        layerPolicies.first { $0.layer == layer }!
    }
}

nonisolated struct RealtimeSpeechContextSection: Sendable, Equatable {
    let id: String
    let source: RealtimeSpeechContextSource
    let scope: RealtimeSpeechContextSectionScope
    let priority: RealtimeSpeechContextPriority
    let privacy: RealtimeSpeechContextPrivacy
    let allowsTrimming: Bool
    let trimOrder: Int
    let text: String
}

nonisolated struct RealtimeSpeechContextBudget: Sendable, Equatable {
    let maximumUTF8Bytes: Int
    let untrimmedUTF8Bytes: Int
    let finalUTF8Bytes: Int
    let removedSectionIDs: [String]
}

nonisolated struct RealtimeSpeechContextProjection: Sendable, Equatable {
    let residentID: String
    let sessionID: String
    let interactionID: NativeSpeechInteractionID
    let sections: [RealtimeSpeechContextSection]
    let instructions: String
    let budget: RealtimeSpeechContextBudget
    let refreshReason: RealtimeSpeechContextRefreshReason
    let compilationVersion: String

    func isBound(to interaction: NativeSpeechInteraction) -> Bool {
        interactionID == interaction.id
            && residentID == interaction.residentID
            && sessionID == interaction.sessionID
    }
}

nonisolated struct RealtimeSpeechContextCompilationKey: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let refreshReason: RealtimeSpeechContextRefreshReason
    let sourceRevision: UInt64
    let currentUserInput: String
}

nonisolated enum RealtimeSpeechContextProjectionError: Error, Equatable {
    case fixedContentExceedsBudget(requiredUTF8Bytes: Int, maximumUTF8Bytes: Int)
}

nonisolated protocol RealtimeSpeechContextProviding: Sendable {
    func prepareContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws
    func updateContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws
}
