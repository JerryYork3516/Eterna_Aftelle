import Foundation

public enum AppStartupState {
    case idle
    case loading
    case loaded
    case failed
}

public enum AppRuntimeState: Equatable {
    case idle
    case running
    case cancelled
    case interrupted
}

public enum ParticleAvatarMode: String, CaseIterable, Identifiable {
    case particleCore = "particle_core"
    case abstractBustReserved = "abstract_bust_reserved"

    public var id: String {
        rawValue
    }

    var localizedKey: String {
        switch self {
        case .particleCore:
            return "particleDebug.avatarMode.particleCore"
        case .abstractBustReserved:
            return "particleDebug.avatarMode.abstractBustReserved"
        }
    }

    var renderFallback: String {
        "particle_core"
    }

    var renderFallbackReason: String {
        switch self {
        case .particleCore:
            return "active_renderer"
        case .abstractBustReserved:
            return "reserved_not_implemented"
        }
    }

    var particleCoreStatus: String {
        switch self {
        case .particleCore:
            return "current / enabled"
        case .abstractBustReserved:
            return "fallback / enabled"
        }
    }

    var abstractBustStatus: String {
        switch self {
        case .particleCore:
            return "reserved / disabled"
        case .abstractBustReserved:
            return "selected / reserved / disabled"
        }
    }
}

public enum ParticleRenderKind: String, CaseIterable, Identifiable {
    case particleCore = "particle_core"
    case abstractBustReserved = "abstract_bust_reserved"
    case dualResidentReserved = "dual_resident_reserved"
    case arTransitionReserved = "ar_transition_reserved"

    public var id: String {
        rawValue
    }

    var localizedKey: String {
        switch self {
        case .particleCore:
            return "particleDebug.renderKind.particleCore"
        case .abstractBustReserved:
            return "particleDebug.renderKind.abstractBustReserved"
        case .dualResidentReserved:
            return "particleDebug.renderKind.dualResidentReserved"
        case .arTransitionReserved:
            return "particleDebug.renderKind.arTransitionReserved"
        }
    }

    var avatarMode: ParticleAvatarMode {
        switch self {
        case .abstractBustReserved:
            return .abstractBustReserved
        case .particleCore, .dualResidentReserved, .arTransitionReserved:
            return .particleCore
        }
    }
}

public struct ParticleRenderResolution: Equatable {
    public var requestedMode: String
    public var activeRenderer: String
    public var fallbackRenderer: String
    public var reason: String
    public var supportedRenderers: String
    public var reservedRenderers: String

    public static func resolve(requested: ParticleRenderKind) -> ParticleRenderResolution {
        let supported = "particle_core"
        let reserved = "abstract_bust, dual_resident, ar_transition"

        switch requested {
        case .particleCore:
            return ParticleRenderResolution(
                requestedMode: requested.rawValue,
                activeRenderer: "particle_core",
                fallbackRenderer: "none",
                reason: "active",
                supportedRenderers: supported,
                reservedRenderers: reserved
            )
        case .abstractBustReserved, .dualResidentReserved, .arTransitionReserved:
            return ParticleRenderResolution(
                requestedMode: requested.rawValue,
                activeRenderer: "particle_core",
                fallbackRenderer: "particle_core",
                reason: "reserved_not_implemented",
                supportedRenderers: supported,
                reservedRenderers: reserved
            )
        }
    }
}

public enum ParticleShellMode: String, CaseIterable, Identifiable {
    case darkShell = "dark_shell"
    case immersiveShell = "immersive_shell"
    case transparentShell = "transparent_shell"

    public var id: String {
        rawValue
    }

    var localizedKey: String {
        switch self {
        case .darkShell:
            return "particleDebug.shellMode.darkShell"
        case .immersiveShell:
            return "particleDebug.shellMode.immersiveShell"
        case .transparentShell:
            return "particleDebug.shellMode.transparentShell"
        }
    }
}

public struct ParticleShellResolution: Equatable {
    public var requestedMode: String
    public var activeMode: String
    public var fallbackReason: String
    public var darkShellStatus: String
    public var immersiveShellStatus: String
    public var transparentShellStatus: String

    public static func resolve(current: ParticleShellMode) -> ParticleShellResolution {
        switch current {
        case .darkShell:
            return ParticleShellResolution(
                requestedMode: current.rawValue,
                activeMode: "dark_shell",
                fallbackReason: "active",
                darkShellStatus: "current / enabled",
                immersiveShellStatus: "enabled / visual-only / debug-only",
                transparentShellStatus: "enabled / debug-only"
            )
        case .immersiveShell:
            return ParticleShellResolution(
                requestedMode: current.rawValue,
                activeMode: "immersive_shell",
                fallbackReason: "visual_only",
                darkShellStatus: "enabled",
                immersiveShellStatus: "current / enabled / visual-only / debug-only",
                transparentShellStatus: "enabled / debug-only"
            )
        case .transparentShell:
            return ParticleShellResolution(
                requestedMode: current.rawValue,
                activeMode: "transparent_shell",
                fallbackReason: "debug_only",
                darkShellStatus: "enabled",
                immersiveShellStatus: "enabled / visual-only / debug-only",
                transparentShellStatus: "current / enabled / debug-only"
            )
        }
    }
}

public enum ParticleSubtitlePhase: Equatable {
    case hidden
    case showing
    case fading
}

public struct ParticleSubtitleState: Equatable {
    public var text: String
    public var phase: ParticleSubtitlePhase

    public static let hidden = ParticleSubtitleState(text: "", phase: .hidden)

    public init(text: String = "", phase: ParticleSubtitlePhase = .hidden) {
        self.text = text
        self.phase = text.isEmpty ? .hidden : phase
    }
}

public struct ParticleRenderMetrics: Equatable {
    public var fps: Double
    public var particleCount: Int
    public var drawableSize: String
    public var preferredFramesPerSecond: Int
    public var currentVisualState: String
    public var targetVisualState: String
    public var renderElapsedTime: Double
    public var motionElapsedTime: Double
    public var frameDeltaTime: Double
    public var stateElapsedTime: Double
    public var transitionDuration: Double
    public var transitionProgress: Double
    public var speechPhase: String
    public var speechIntensity: Double
    public var lastTransitionReason: String
    public var currentShape: String
    public var targetShape: String
    public var morphElapsedTime: Double
    public var morphDuration: Double
    public var morphProgress: Double
    public var lastMorphReason: String
    public var mouseInfluenceEnabled: Bool
    public var mouseInsideParticleArea: Bool
    public var interactionStrength: Double
    var expression: ParticleExpressionVisualState

    public static let empty = ParticleRenderMetrics(
        fps: 0,
        particleCount: 0,
        drawableSize: "-",
        preferredFramesPerSecond: 0,
        currentVisualState: "idle",
        targetVisualState: "idle",
        renderElapsedTime: 0,
        motionElapsedTime: 0,
        frameDeltaTime: 0,
        stateElapsedTime: 0,
        transitionDuration: 0,
        transitionProgress: 1,
        speechPhase: "inactive",
        speechIntensity: 0,
        lastTransitionReason: "startup",
        currentShape: "sphere",
        targetShape: "sphere",
        morphElapsedTime: 0,
        morphDuration: 0,
        morphProgress: 1,
        lastMorphReason: "startup",
        mouseInfluenceEnabled: true,
        mouseInsideParticleArea: false,
        interactionStrength: 0,
        expression: .neutral
    )
}

public struct ParticleDebugSnapshot: Equatable {
    public var fps: Double
    public var particleCount: Int
    public var drawableSize: String
    public var preferredFramesPerSecond: Int
    public var currentVisualState: String
    public var targetVisualState: String
    public var frameDeltaTime: Double
    public var stateElapsedTime: Double
    public var transitionDuration: Double
    public var transitionProgress: Double
    public var speechPhase: String
    public var speechIntensity: Double
    public var lastTransitionReason: String
    public var currentShape: String
    public var targetShape: String
    public var morphElapsedTime: Double
    public var morphDuration: Double
    public var morphProgress: Double
    public var lastMorphReason: String
    public var sourceAvatarState: String
    public var mappedParticleState: String
    public var isDebugOverrideActive: Bool
    public var avatarMode: String
    public var particleCoreModeStatus: String
    public var abstractBustModeStatus: String
    public var renderFallback: String
    public var renderFallbackReason: String
    public var requestedRenderKind: String
    public var activeRenderer: String
    public var fallbackRenderer: String
    public var fallbackReason: String
    public var supportedRenderers: String
    public var reservedRenderers: String
    public var requestedShellMode: String
    public var activeShellMode: String
    public var shellFallbackReason: String
    public var darkShellStatus: String
    public var immersiveShellStatus: String
    public var transparentShellStatus: String
    public var colorProfileSource: String
    public var baseColor: String
    public var ridgeColor: String
    public var highlightColor: String
    public var fallbackUsed: Bool
    public var subtitlePhase: String
    public var hasSubtitleText: Bool
    public var mouseInfluenceEnabled: Bool
    public var mouseInsideParticleArea: Bool
    public var interactionStrength: Double
    public var runtimeCoreModified: Bool
    public var runtimeAPIModified: Bool
    public var drSchemaModified: Bool
    public var providerTTSConnected: Bool

    public static let empty = ParticleDebugSnapshot(
        fps: 0,
        particleCount: 0,
        drawableSize: "-",
        preferredFramesPerSecond: 0,
        currentVisualState: "idle",
        targetVisualState: "idle",
        frameDeltaTime: 0,
        stateElapsedTime: 0,
        transitionDuration: 0,
        transitionProgress: 1,
        speechPhase: "inactive",
        speechIntensity: 0,
        lastTransitionReason: "startup",
        currentShape: "sphere",
        targetShape: "sphere",
        morphElapsedTime: 0,
        morphDuration: 0,
        morphProgress: 1,
        lastMorphReason: "startup",
        sourceAvatarState: "mode=idle presence=unknown",
        mappedParticleState: "idle",
        isDebugOverrideActive: false,
        avatarMode: "particle_core",
        particleCoreModeStatus: "current / enabled",
        abstractBustModeStatus: "reserved / disabled",
        renderFallback: "none",
        renderFallbackReason: "active",
        requestedRenderKind: "particle_core",
        activeRenderer: "particle_core",
        fallbackRenderer: "none",
        fallbackReason: "active",
        supportedRenderers: "particle_core",
        reservedRenderers: "abstract_bust, dual_resident, ar_transition",
        requestedShellMode: "dark_shell",
        activeShellMode: "dark_shell",
        shellFallbackReason: "active",
        darkShellStatus: "current / enabled",
        immersiveShellStatus: "enabled / visual-only / debug-only",
        transparentShellStatus: "enabled / debug-only",
        colorProfileSource: "systemDefault",
        baseColor: "0.82, 0.84, 0.88",
        ridgeColor: "0.95, 0.96, 0.98",
        highlightColor: "0.98, 0.99, 1.00",
        fallbackUsed: true,
        subtitlePhase: "hidden",
        hasSubtitleText: false,
        mouseInfluenceEnabled: true,
        mouseInsideParticleArea: false,
        interactionStrength: 0,
        runtimeCoreModified: false,
        runtimeAPIModified: false,
        drSchemaModified: false,
        providerTTSConnected: false
    )
}

struct AppResidentVisualIntentMapper {
    static func map(
        visualStateMode: String? = nil,
        avatarState: AppAvatarState? = nil,
        residentState: AppResidentState? = nil,
        startupState: AppStartupState = .idle,
        runtimeState: AppRuntimeState = .idle
    ) -> ResidentVisualIntent {
        let tokens = [
            visualStateMode,
            avatarState?.mode,
            avatarState?.presence,
            avatarState?.moodHint,
            avatarState?.activityHint,
            avatarState?.particleHint,
            residentState?.lifecycleStatus,
            residentState?.presence,
            residentState?.avatarMode,
            startupToken(for: startupState),
            runtimeToken(for: runtimeState)
        ]

        if matches(tokens, ["error", "failed", "failure", "unavailable", "degraded"]) {
            return .error
        }
        if matches(tokens, ["exit", "exiting", "closing", "dismissed"]) {
            return .exit
        }
        if runtimeState == .cancelled || runtimeState == .interrupted {
            return .idle
        }
        if let visualStateMode,
           let intent = ResidentVisualIntent(
               rawValue: visualStateMode
                   .trimmingCharacters(in: .whitespacesAndNewlines)
                   .lowercased()
           ) {
            return intent
        }
        if matches(tokens, ["sleeping", "asleep", "dormant"]) {
            return .sleeping
        }
        if matches(tokens, ["speaking", "responding", "outputting"]) {
            return .speaking
        }
        if matches(tokens, ["listening", "attentive", "receiving"]) {
            return .listening
        }
        if matches(tokens, ["loading", "connecting", "preparing", "waiting"]) {
            return .loading
        }
        if matches(tokens, ["thinking", "reasoning", "processing", "composing", "focused"]) {
            return .thinking
        }
        return .idle
    }

    private static func startupToken(for state: AppStartupState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded:
            return "idle"
        case .failed:
            return "failed"
        }
    }

    private static func runtimeToken(for state: AppRuntimeState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .running:
            return "processing"
        case .cancelled:
            return "idle"
        case .interrupted:
            return "idle"
        }
    }

    private static func matches(_ values: [String?], _ candidates: [String]) -> Bool {
        values.contains { value in
            guard let value else { return false }
            let normalized = value.lowercased()
            return candidates.contains { normalized.contains($0) }
        }
    }
}

public struct AppDialogueEntryState: Equatable, Identifiable {
    public var id: String
    public var role: String
    public var text: String
    public var timestamp: String

    public init(id: String, role: String, text: String, timestamp: String) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

#if DEBUG
struct RelationshipProgressionDebugViewState: Equatable {
    var isAvailable = false
    var stageID: String?
    var evidenceIDs: [String] = []
    var lastTransitionReason: String?
    var enabled = false
    var revision: Int?

    init() {}

    init(_ snapshot: RuntimeRelationshipDebugSnapshot) {
        isAvailable = snapshot.isAvailable
        stageID = snapshot.stageID
        evidenceIDs = snapshot.evidenceIDs
        lastTransitionReason = snapshot.lastTransitionReason
        enabled = snapshot.enabled
        revision = snapshot.revision
    }
}

struct RuntimeOrchestrationFewShotViewState: Equatable, Identifiable {
    let exampleID: String
    let kind: String

    var id: String { "\(kind):\(exampleID)" }
}

struct RuntimeOrchestrationStepViewState: Equatable, Identifiable {
    let kind: String
    let status: String
    let durationMilliseconds: Int

    var id: String { kind }
}

struct RuntimeOrchestrationInteractionViewState: Equatable, Identifiable {
    let id: UUID
    let residentID: String
    let sessionID: String
    let startedAt: Date
    let endedAt: Date
    let durationMilliseconds: Int
    let dailyRulesEnabled: Bool
    let emotionalRulesEnabled: Bool
    let recentMessageCount: Int
    let fewShotReferences: [RuntimeOrchestrationFewShotViewState]
    let approvedPreferenceCount: Int
    let providerID: String?
    let modelID: String?
    let adapterType: String?
    let result: String
    let errorCategory: String?
    let sessionWriteStatus: String
    let subtitleState: String
    let particleState: String
    let lifecycleState: String
    let expressionState: String
    let expressionIntensity: Double
    let expressionFallbackOccurred: Bool
    let expressionMappingSource: String
    let relationshipStageID: String?
    let relationshipEvidenceIDs: [String]
    let relationshipDecision: String
    let relationshipReason: String
    var expressionTransitionProgress: Double
    var expressionLifecycleOverrideActive: Bool
    var currentBrightnessMultiplier: Double
    var currentSaturationMultiplier: Double
    var currentTemperatureShift: Double
    var currentEnergyMultiplier: Double
    var currentMotionSpeedMultiplier: Double
    var currentDiffusionMultiplier: Double
    let brightnessMultiplier: Double
    let saturationMultiplier: Double
    let temperatureShift: Double
    let energyMultiplier: Double
    let motionSpeedMultiplier: Double
    let diffusionMultiplier: Double
    let steps: [RuntimeOrchestrationStepViewState]

    init(_ interaction: RuntimeOrchestrationInteraction) {
        id = interaction.id
        residentID = interaction.residentID
        sessionID = interaction.sessionID
        startedAt = interaction.startedAt
        endedAt = interaction.endedAt
        durationMilliseconds = interaction.durationMilliseconds
        dailyRulesEnabled = interaction.dailyRulesEnabled
        emotionalRulesEnabled = interaction.emotionalRulesEnabled
        recentMessageCount = interaction.recentMessageCount
        fewShotReferences = interaction.fewShotReferences.map {
            RuntimeOrchestrationFewShotViewState(exampleID: $0.exampleID, kind: $0.kind)
        }
        approvedPreferenceCount = interaction.approvedPreferenceCount
        providerID = interaction.provider?.providerID
        modelID = interaction.provider?.modelID
        adapterType = interaction.provider?.adapterType
        result = interaction.result.rawValue
        errorCategory = interaction.errorCategory
        sessionWriteStatus = interaction.sessionWriteStatus.rawValue
        subtitleState = interaction.subtitleState
        particleState = interaction.particleState
        lifecycleState = interaction.lifecycleState.rawValue
        expressionState = interaction.expressionState
        expressionIntensity = interaction.expressionIntensity
        expressionFallbackOccurred = interaction.expressionFallbackOccurred
        expressionMappingSource = interaction.expressionMappingSource
        relationshipStageID = interaction.relationshipStageID
        relationshipEvidenceIDs = interaction.relationshipEvidenceIDs
        relationshipDecision = interaction.relationshipDecision
        relationshipReason = interaction.relationshipReason
        expressionTransitionProgress = 0
        expressionLifecycleOverrideActive = [
            "error", "loading", "exit"
        ].contains(interaction.lifecycleState.rawValue)
        brightnessMultiplier =
            interaction.expressionMapping.brightnessMultiplier
        saturationMultiplier =
            interaction.expressionMapping.saturationMultiplier
        temperatureShift = interaction.expressionMapping.temperatureShift
        energyMultiplier = interaction.expressionMapping.energyMultiplier
        motionSpeedMultiplier =
            interaction.expressionMapping.motionSpeedMultiplier
        diffusionMultiplier =
            interaction.expressionMapping.diffusionMultiplier
        currentBrightnessMultiplier = 1
        currentSaturationMultiplier = 1
        currentTemperatureShift = 0
        currentEnergyMultiplier = 1
        currentMotionSpeedMultiplier = 1
        currentDiffusionMultiplier = 1
        steps = interaction.steps.map {
            RuntimeOrchestrationStepViewState(
                kind: $0.kind.rawValue,
                status: $0.status.rawValue,
                durationMilliseconds: $0.durationMilliseconds
            )
        }
    }

    mutating func apply(
        particleExpression: ParticleExpressionVisualState
    ) {
        guard particleExpression.matches(
            interactionID: id,
            state: expressionState,
            intensity: expressionIntensity,
            fallbackOccurred: expressionFallbackOccurred,
            mappingSource: expressionMappingSource,
            targetMultipliers: targetMultipliers
        ) else {
            return
        }

        applyCurrent(particleExpression)
        expressionTransitionProgress = Double(
            particleExpression.transitionProgress
        )
    }

    mutating func applyPendingCurrent(
        particleExpression: ParticleExpressionVisualState
    ) {
        applyCurrent(particleExpression)
        expressionTransitionProgress = 0
    }

    mutating func preserveParticleExpressionProjection(
        from previous: RuntimeOrchestrationInteractionViewState
    ) {
        guard id == previous.id,
              sessionID == previous.sessionID else {
            return
        }
        expressionTransitionProgress =
            previous.expressionTransitionProgress
        expressionLifecycleOverrideActive =
            expressionLifecycleOverrideActive
                || previous.expressionLifecycleOverrideActive
        currentBrightnessMultiplier =
            previous.currentBrightnessMultiplier
        currentSaturationMultiplier =
            previous.currentSaturationMultiplier
        currentTemperatureShift =
            previous.currentTemperatureShift
        currentEnergyMultiplier =
            previous.currentEnergyMultiplier
        currentMotionSpeedMultiplier =
            previous.currentMotionSpeedMultiplier
        currentDiffusionMultiplier =
            previous.currentDiffusionMultiplier
    }

    private var targetMultipliers: ParticleExpressionMultipliers {
        ParticleExpressionMultipliers(
            brightnessMultiplier: Float(brightnessMultiplier),
            saturationMultiplier: Float(saturationMultiplier),
            temperatureShift: Float(temperatureShift),
            energyMultiplier: Float(energyMultiplier),
            motionSpeedMultiplier: Float(motionSpeedMultiplier),
            diffusionMultiplier: Float(diffusionMultiplier)
        )
    }

    private mutating func applyCurrent(
        _ particleExpression: ParticleExpressionVisualState
    ) {
        let current = particleExpression.currentMultipliers
        expressionLifecycleOverrideActive =
            ["error", "loading", "exit"].contains(lifecycleState)
            || particleExpression.lifecycleOverrideActive
        currentBrightnessMultiplier = Double(current.brightnessMultiplier)
        currentSaturationMultiplier = Double(current.saturationMultiplier)
        currentTemperatureShift = Double(current.temperatureShift)
        currentEnergyMultiplier = Double(current.energyMultiplier)
        currentMotionSpeedMultiplier = Double(current.motionSpeedMultiplier)
        currentDiffusionMultiplier = Double(current.diffusionMultiplier)
    }
}

struct RuntimeOrchestrationViewState: Equatable {
    var interactions: [RuntimeOrchestrationInteractionViewState] = []
    var statusKey: String?

    mutating func preserveParticleExpressionProjections(
        from previous: RuntimeOrchestrationViewState
    ) {
        let previousByID = Dictionary(
            uniqueKeysWithValues: previous.interactions.map {
                ($0.id, $0)
            }
        )
        for index in interactions.indices {
            guard let previousInteraction =
                previousByID[interactions[index].id] else {
                continue
            }
            interactions[index].preserveParticleExpressionProjection(
                from: previousInteraction
            )
        }
    }

    mutating func applyParticleExpression(
        rendered particleExpression: ParticleExpressionVisualState,
        pendingInput: ParticleExpressionInput,
        sessionID: String
    ) {
        let renderedInteractionID =
            particleExpression.targetInput.interactionID
        if let renderedInteractionID,
           let index = interactions.lastIndex(where: {
               $0.id == renderedInteractionID
                   && $0.sessionID == sessionID
           }) {
            interactions[index].apply(
                particleExpression: particleExpression
            )
        }
        if let pendingInteractionID = pendingInput.interactionID,
           pendingInteractionID != renderedInteractionID,
           let index = interactions.lastIndex(where: {
               $0.id == pendingInteractionID
                   && $0.sessionID == sessionID
           }) {
            interactions[index].applyPendingCurrent(
                particleExpression: particleExpression
            )
        }
    }
}

enum DialogueAuditRole: Equatable {
    case user
    case resident
}

struct DialogueAuditEntry: Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let role: DialogueAuditRole
    let displayName: String
    let text: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        role: DialogueAuditRole,
        displayName: String,
        text: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.displayName = displayName
        self.text = text
    }
}

struct DialogueAuditViewState: Equatable {
    static let capacity = 200

    private(set) var entries: [DialogueAuditEntry] = []
    var statusKey: String?

    mutating func append(_ entry: DialogueAuditEntry) {
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        statusKey = nil
    }

    mutating func clear() {
        entries.removeAll(keepingCapacity: true)
        statusKey = nil
    }
}

enum RealtimeSpeechDiagnosticSource: String, Codable, Sendable {
    case lifecycle
    case transport
    case wire
    case adapter
    case providerEvent = "provider_event"
    case runtime
    case inputBridge = "input_bridge"
    case outputBridge = "output_bridge"
    case playback
    case subtitle
}

struct RealtimeSpeechDiagnosticEvent: Codable, Equatable, Identifiable,
    Sendable
{
    let id: UInt64
    let timestamp: Date
    let elapsedMilliseconds: UInt64
    let source: RealtimeSpeechDiagnosticSource
    let category: String
    let interactionShortID: String?
    let turnNumber: UInt64?
    let turnGeneration: UInt64?
    let stateBefore: String?
    let stateAfter: String?
    let disposition: String?
    let wireSequence: UInt64?
    let responseCorrelationHash: String?
    let itemCorrelationHash: String?
    let audioSequence: UInt64?
    let byteCount: Int?
    let queueDepth: Int?
    let pendingWriteCount: Int?
    let playbackGeneration: UInt64?
    let arrivalIntervalMilliseconds: UInt64?
    let wireToStandardDurationMilliseconds: UInt64?
    let durationMilliseconds: UInt64?
    let inputForwardedFrameDelta: UInt64?
    let inputRejectedFrameDelta: UInt64?
    let captureGeneratedFrameDelta: UInt64?
    let captureDroppedFrameDelta: UInt64?
    let pcmPeak: Double?
    let pcmRMS: Double?
    let pcmClipCount: Int?
    let pcmBoundaryJump: Double?
    let errorCode: String?
}

struct RealtimeSpeechDiagnosticTimeline: Sendable {
    static let capacity = 30_000
    static let visibleCapacity = 80

    private var storage = [RealtimeSpeechDiagnosticEvent?](
        repeating: nil,
        count: capacity
    )
    private var startIndex = 0
    private(set) var eventCount = 0
    private(set) var droppedEventCount: UInt64 = 0
    private var startedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var nextSequence: UInt64 = 0

    var events: [RealtimeSpeechDiagnosticEvent] {
        orderedEvents(startingAt: 0)
    }

    var visibleEvents: [RealtimeSpeechDiagnosticEvent] {
        orderedEvents(
            startingAt: max(0, eventCount - Self.visibleCapacity)
        )
    }

    mutating func append(
        source: RealtimeSpeechDiagnosticSource,
        category: String,
        interactionShortID: String? = nil,
        turnNumber: UInt64? = nil,
        turnGeneration: UInt64? = nil,
        stateBefore: String? = nil,
        stateAfter: String? = nil,
        disposition: String? = nil,
        wireSequence: UInt64? = nil,
        responseCorrelationHash: String? = nil,
        itemCorrelationHash: String? = nil,
        audioSequence: UInt64? = nil,
        byteCount: Int? = nil,
        queueDepth: Int? = nil,
        pendingWriteCount: Int? = nil,
        playbackGeneration: UInt64? = nil,
        arrivalIntervalMilliseconds: UInt64? = nil,
        wireToStandardDurationMilliseconds: UInt64? = nil,
        durationMilliseconds: UInt64? = nil,
        inputForwardedFrameDelta: UInt64? = nil,
        inputRejectedFrameDelta: UInt64? = nil,
        captureGeneratedFrameDelta: UInt64? = nil,
        captureDroppedFrameDelta: UInt64? = nil,
        pcmPeak: Double? = nil,
        pcmRMS: Double? = nil,
        pcmClipCount: Int? = nil,
        pcmBoundaryJump: Double? = nil,
        errorCode: String? = nil,
        timestamp: Date = Date(),
        nowNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        nextSequence &+= 1
        let event = RealtimeSpeechDiagnosticEvent(
            id: nextSequence,
            timestamp: timestamp,
            elapsedMilliseconds:
                (nowNanoseconds &- startedAtNanoseconds) / 1_000_000,
            source: source,
            category: category,
            interactionShortID: interactionShortID,
            turnNumber: turnNumber,
            turnGeneration: turnGeneration,
            stateBefore: stateBefore,
            stateAfter: stateAfter,
            disposition: disposition,
            wireSequence: wireSequence,
            responseCorrelationHash: responseCorrelationHash,
            itemCorrelationHash: itemCorrelationHash,
            audioSequence: audioSequence,
            byteCount: byteCount,
            queueDepth: queueDepth,
            pendingWriteCount: pendingWriteCount,
            playbackGeneration: playbackGeneration,
            arrivalIntervalMilliseconds: arrivalIntervalMilliseconds,
            wireToStandardDurationMilliseconds:
                wireToStandardDurationMilliseconds,
            durationMilliseconds: durationMilliseconds,
            inputForwardedFrameDelta: inputForwardedFrameDelta,
            inputRejectedFrameDelta: inputRejectedFrameDelta,
            captureGeneratedFrameDelta: captureGeneratedFrameDelta,
            captureDroppedFrameDelta: captureDroppedFrameDelta,
            pcmPeak: pcmPeak,
            pcmRMS: pcmRMS,
            pcmClipCount: pcmClipCount,
            pcmBoundaryJump: pcmBoundaryJump,
            errorCode: errorCode
        )
        if eventCount < Self.capacity {
            let index = (startIndex + eventCount) % Self.capacity
            storage[index] = event
            eventCount += 1
        } else {
            storage[startIndex] = event
            startIndex = (startIndex + 1) % Self.capacity
            droppedEventCount &+= 1
        }
    }

    mutating func clear() {
        storage = [RealtimeSpeechDiagnosticEvent?](
            repeating: nil,
            count: Self.capacity
        )
        startIndex = 0
        eventCount = 0
        droppedEventCount = 0
        startedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
        nextSequence = 0
    }

    private func orderedEvents(
        startingAt offset: Int
    ) -> [RealtimeSpeechDiagnosticEvent] {
        guard offset < eventCount else { return [] }
        var result: [RealtimeSpeechDiagnosticEvent] = []
        result.reserveCapacity(eventCount - offset)
        for position in offset ..< eventCount {
            let index = (startIndex + position) % Self.capacity
            if let event = storage[index] {
                result.append(event)
            }
        }
        return result
    }
}

struct RealtimeSpeechDiagnosticViewState: Equatable, Sendable {
    let eventCount: Int
    let droppedEventCount: UInt64
    let visibleEvents: [RealtimeSpeechDiagnosticEvent]

    static let initial = RealtimeSpeechDiagnosticViewState(
        eventCount: 0,
        droppedEventCount: 0,
        visibleEvents: []
    )

    init(timeline: RealtimeSpeechDiagnosticTimeline) {
        eventCount = timeline.eventCount
        droppedEventCount = timeline.droppedEventCount
        visibleEvents = timeline.visibleEvents
    }

    private init(
        eventCount: Int,
        droppedEventCount: UInt64,
        visibleEvents: [RealtimeSpeechDiagnosticEvent]
    ) {
        self.eventCount = eventCount
        self.droppedEventCount = droppedEventCount
        self.visibleEvents = visibleEvents
    }
}

enum FormalSpeechRoutePhase: String, Equatable, Sendable {
    case idle
    case starting
    case listening
    case processing
    case speaking
    case failed

    var isActive: Bool {
        switch self {
        case .starting, .listening, .processing, .speaking:
            true
        case .idle, .failed:
            false
        }
    }
}

struct FormalSpeechRouteDebugSnapshot: Equatable, Sendable {
    let phase: FormalSpeechRoutePhase
    let generation: UInt64?
    let lastErrorCode: String?

    static let idle = FormalSpeechRouteDebugSnapshot(
        phase: .idle,
        generation: nil,
        lastErrorCode: nil
    )
}

struct RealtimeSpeechSourceGateEpochDiagnosticExport: Encodable, Sendable {
    let playbackSequence: UInt64
    let epochSequence: UInt64
    let openedAtCaptureFrame: UInt64
    let closedAtCaptureFrame: UInt64?
    let totalFrameCount: UInt64
    let forwardedFrameCount: UInt64
    let suppressedFrameCount: UInt64
    let echoOnlyFrameCount: UInt64
    let nearEndSpeechFrameCount: UInt64
    let doubleTalkFrameCount: UInt64
    let uncertainFrameCount: UInt64
    let rawEchoGainBaselineAtOpen: Double
    let rawEchoGainBaselineAtClose: Double
    let residualEchoGainBaselineAtOpen: Double
    let residualEchoGainBaselineAtClose: Double
    let linearAECOutputGainBaselineAtOpen: Double
    let linearAECOutputGainBaselineAtClose: Double
    let aecBufferDelayMillisecondsAtOpen: Int
    let aecBufferDelayMillisecondsAtClose: Int
    let sourceAlignmentDelayMillisecondsAtOpen: Int?
    let sourceAlignmentDelayMillisecondsAtClose: Int?
    let estimatedDelayMillisecondsAtOpen: Int
    let estimatedDelayMillisecondsAtClose: Int
    let closeReason: String?
}

struct RealtimeSpeechAcousticEchoDiagnosticExport: Encodable, Sendable {
    var available = false
    var mode = "unavailable"
    var enabled = false
    var active = false
    var isPlaybackActive = false
    var inputClassification = "uncertain"
    var sourceGateOpen = false
    var sourceGatePreRollFrameCount = 0
    var renderFrameCount: UInt64 = 0
    var captureFrameCount: UInt64 = 0
    var delayMilliseconds = 0
    var aecBufferDelayMilliseconds = 0
    var presentationDelayMilliseconds = 0
    var alignedDelayMilliseconds: Int?
    var sourceAlignmentDelayMilliseconds: Int?
    var estimatedDelayMilliseconds = 0
    var erlDecibels = 0.0
    var erleDecibels = 0.0
    var rawCaptureRMS = 0.0
    var processedCaptureRMS = 0.0
    var renderCaptureCorrelation = 0.0
    var residualRenderCorrelation = 0.0
    var linearAECOutputRMS = 0.0
    var linearRenderCorrelation = 0.0
    var processedLinearCorrelation = 0.0
    var renderTimingFrameCount = 0
    var renderFIFOSampleCount = 0
    var captureFIFOSampleCount = 0
    var echoOnlyFrameCount: UInt64 = 0
    var nearEndSpeechFrameCount: UInt64 = 0
    var doubleTalkFrameCount: UInt64 = 0
    var uncertainFrameCount: UInt64 = 0
    var sourceForwardedFrameCount: UInt64 = 0
    var sourceSuppressedFrameCount: UInt64 = 0
    var sourceTimingCandidateFrameCount: UInt64 = 0
    var sourceTimingUnavailableFrameCount: UInt64 = 0
    var sourceGateOpenCount: UInt64 = 0
    var sourceGateCloseCount: UInt64 = 0
    var maximumSourceGateOpenFrameCount: UInt64 = 0
    var maximumContinuousSourceForwardedFrameCount: UInt64 = 0
    var rawEchoGainBaseline = 0.0
    var residualEchoGainBaseline = 0.0
    var linearAECOutputGainBaseline = 0.0
    var residualEchoBaselineFrameCount: UInt64 = 0
    var residualEchoBaselineFrozen = false
    var residualEchoBaselineUpdateCount: UInt64 = 0
    var residualEchoBaselineFreezeCount: UInt64 = 0
    var adaptiveEvidenceCandidateFrameCount: UInt64 = 0
    var adaptiveDoubleTalkFrameCount: UInt64 = 0
    var maximumAdaptiveRawExcessRMS = 0.0
    var maximumAdaptiveResidualExcessRMS = 0.0
    var maximumAdaptiveLinearExcessRMS = 0.0
    var sourceAlignmentLocked = false
    var sourceAlignmentAcquisitionFrameCount = 0
    var sourceAlignmentMissCount: UInt64 = 0
    var sourceAlignmentReacquisitionCount: UInt64 = 0
    var lastSourceGateCloseReason: String?
    var sourceGateEpochs: [
        RealtimeSpeechSourceGateEpochDiagnosticExport
    ] = []
    var fallbackCount: UInt64 = 0
    var fallbackReason: String?
    var lastFallbackReason: String?
    var routeResetCount: UInt64 = 0
    var driftTrend = "stable"
}

struct RealtimeSpeechDiagnosticExport: Encodable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let appBuild: String
    let providerProfileID: String
    let providerID: String
    let modelID: String
    let voiceID: String
    let formalRouteState: String
    let formalRouteGeneration: UInt64?
    let formalRouteLastError: String?
    let finalState: String
    let interactionShortID: String?
    let turnNumber: UInt64
    let turnGeneration: UInt64
    let inputForwardedFrameCount: UInt64
    let inputRejectedFrameCount: UInt64
    let inputSendOperationCount: UInt64
    let inputAverageSendDurationMilliseconds: UInt64
    let inputMaximumSendDurationMilliseconds: UInt64
    let captureGeneratedFrameCount: UInt64
    let captureDroppedFrameCount: UInt64
    let captureQueuedFrameCount: Int
    let outputAudioChunkCount: UInt64
    let outputAudioByteCount: UInt64
    let playbackStartedCount: Int
    let playbackCompletedCount: Int
    let playbackRejectedCount: UInt64
    let outputRuntimeRejectedEventCount: UInt64
    let acousticEcho: RealtimeSpeechAcousticEchoDiagnosticExport
    let droppedEventCount: UInt64
    let events: [RealtimeSpeechDiagnosticEvent]
}
#endif

public struct AppSessionState: Equatable {
    public var residentID: String
    public var sessionID: String
    public var lastUserInput: String
    public var lastResidentOutput: String
    public var lastActivity: String
    public var shutdownState: String
    public var recoveryRequired: Bool
    public var recoveredAt: String
    public var dialogueEntries: [AppDialogueEntryState]

    public init(
        residentID: String = "",
        sessionID: String = "",
        lastUserInput: String = "",
        lastResidentOutput: String = "",
        lastActivity: String = "",
        shutdownState: String = "unknown",
        recoveryRequired: Bool = false,
        recoveredAt: String = "",
        dialogueEntries: [AppDialogueEntryState] = []
    ) {
        self.residentID = residentID
        self.sessionID = sessionID
        self.lastUserInput = lastUserInput
        self.lastResidentOutput = lastResidentOutput
        self.lastActivity = lastActivity
        self.shutdownState = shutdownState
        self.recoveryRequired = recoveryRequired
        self.recoveredAt = recoveredAt
        self.dialogueEntries = dialogueEntries
    }
}

public struct AppAvatarState: Equatable {
    public var residentID: String
    public var displayName: String
    public var mode: String
    public var presence: String
    public var moodHint: String
    public var activityHint: String
    public var particleHint: String

    public init(
        residentID: String = "",
        displayName: String = "",
        mode: String = "idle",
        presence: String = "unknown",
        moodHint: String = "",
        activityHint: String = "",
        particleHint: String = ""
    ) {
        self.residentID = residentID
        self.displayName = displayName
        self.mode = mode
        self.presence = presence
        self.moodHint = moodHint
        self.activityHint = activityHint
        self.particleHint = particleHint
    }
}

public struct AppResidentState: Equatable {
    public var residentID: String
    public var sessionID: String
    public var lifecycleStatus: String
    public var presence: String
    public var lastActivitySummary: String
    public var lastUpdatedAt: String
    public var avatarMode: String

    public init(
        residentID: String = "",
        sessionID: String = "",
        lifecycleStatus: String = "loaded",
        presence: String = "unknown",
        lastActivitySummary: String = "",
        lastUpdatedAt: String = "",
        avatarMode: String = ""
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

public struct RuntimeTraceEntryViewState: Equatable, Identifiable {
    public var id: String
    public var type: String
    public var message: String

    public init(id: String, type: String, message: String) {
        self.id = id
        self.type = type
        self.message = message
    }
}

public struct RuntimeTraceViewState: Equatable {
    public var summary: String
    public var entries: [RuntimeTraceEntryViewState]

    public init(summary: String = "", entries: [RuntimeTraceEntryViewState] = []) {
        self.summary = summary
        self.entries = entries
    }
}

public struct RuntimeClockViewState: Equatable {
    public var tickCount: Int
    public var lastTickSummary: String

    public init(tickCount: Int = 0, lastTickSummary: String = "") {
        self.tickCount = tickCount
        self.lastTickSummary = lastTickSummary
    }
}

public struct DebugPanelViewState: Equatable {
    public var residentID: String
    public var sessionID: String
    public var lifecycleStatus: String
    public var presence: String
    public var avatarMode: String
    public var lastActivitySummary: String
    public var traceSummary: String
    public var tickCount: Int
    public var clockStatus: String
    public var cancellationStatus: String
    public var shutdownState: String
    public var recoveryRequired: Bool
    public var recoveredAt: String

    public init(
        residentID: String = "",
        sessionID: String = "",
        lifecycleStatus: String = "",
        presence: String = "",
        avatarMode: String = "",
        lastActivitySummary: String = "",
        traceSummary: String = "",
        tickCount: Int = 0,
        clockStatus: String = "",
        cancellationStatus: String = "",
        shutdownState: String = "unknown",
        recoveryRequired: Bool = false,
        recoveredAt: String = ""
    ) {
        self.residentID = residentID
        self.sessionID = sessionID
        self.lifecycleStatus = lifecycleStatus
        self.presence = presence
        self.avatarMode = avatarMode
        self.lastActivitySummary = lastActivitySummary
        self.traceSummary = traceSummary
        self.tickCount = tickCount
        self.clockStatus = clockStatus
        self.cancellationStatus = cancellationStatus
        self.shutdownState = shutdownState
        self.recoveryRequired = recoveryRequired
        self.recoveredAt = recoveredAt
    }
}

struct ProviderDebugViewState: Equatable {
    var profile: ProviderProfile
    var configurationSaved: Bool
    var credentialSaved: Bool
    var isTesting: Bool
    var statusKey: String
    var replyText: String

    init(
        profile: ProviderProfile,
        configurationSaved: Bool = false,
        credentialSaved: Bool = false,
        isTesting: Bool = false,
        statusKey: String = "particleDebug.provider.status.ready",
        replyText: String = ""
    ) {
        self.profile = profile
        self.configurationSaved = configurationSaved
        self.credentialSaved = credentialSaved
        self.isTesting = isTesting
        self.statusKey = statusKey
        self.replyText = replyText
    }
}

#if DEBUG
struct NativeSpeechProviderDebugViewState: Equatable {
    let profile: NativeSpeechProviderProfile
    var credentialSaved: Bool
    var isTesting: Bool
    var statusKey: String

    init(
        profile: NativeSpeechProviderProfile,
        credentialSaved: Bool = false,
        isTesting: Bool = false,
        statusKey: String = "particleDebug.qwen.status.ready"
    ) {
        self.profile = profile
        self.credentialSaved = credentialSaved
        self.isTesting = isTesting
        self.statusKey = statusKey
    }
}
#endif

struct ResidentTextInputViewState: Equatable {
    var isSubmitting = false
    var errorKey: String?
}

public struct OrchestrationKernelDiagnostics: Equatable {
    public var stateSummary: String

    public init(stateSummary: String = "unprepared") {
        self.stateSummary = stateSummary
    }
}

@MainActor
public final class OrchestrationKernel {
    private nonisolated(unsafe) let runtimeCore: RuntimeCore
    private var isPrepared = false
    private var lastDiagnostics = OrchestrationKernelDiagnostics()

    public init(runtimeCore: RuntimeCore) {
        self.runtimeCore = runtimeCore
    }

    @MainActor
    public convenience init() {
        self.init(runtimeCore: RuntimeCore())
    }

    public func prepare() {
        isPrepared = true
        lastDiagnostics = OrchestrationKernelDiagnostics(stateSummary: "prepared")
    }

    public func currentDiagnostics() -> OrchestrationKernelDiagnostics {
        lastDiagnostics
    }

    public func loadResident(fixtureData: Data) -> RuntimeLoadResult {
        prepare()
        let result = runtimeCore.loadDR(request: RuntimeLoadRequest(drData: fixtureData))
        lastDiagnostics = OrchestrationKernelDiagnostics(stateSummary: result.isLoaded ? "resident_loaded" : "resident_load_failed")
        return result
    }

    public func restoreMostRecentSession() -> RuntimeSessionRestoreResult {
        prepare()
        let result = runtimeCore.restoreMostRecentSession()
        lastDiagnostics = OrchestrationKernelDiagnostics(stateSummary: result.didRestore ? "session_restored" : "session_restore_empty")
        return result
    }

    #if DEBUG
    func clearDialogueTestData() throws -> String? {
        try runtimeCore.clearDialogueTestData()
    }

    func relationshipProgressionDebugViewState()
        -> RelationshipProgressionDebugViewState {
        RelationshipProgressionDebugViewState(
            runtimeCore.relationshipProgressionDebugSnapshot()
        )
    }

    func resetRelationshipProgressionForDebug()
        -> RelationshipProgressionDebugViewState {
        RelationshipProgressionDebugViewState(
            runtimeCore.resetRelationshipProgressionForDebug()
        )
    }

    func runtimeOrchestrationViewState() -> RuntimeOrchestrationViewState {
        RuntimeOrchestrationViewState(
            interactions: runtimeCore.runtimeOrchestrationSnapshot().map(
                RuntimeOrchestrationInteractionViewState.init
            )
        )
    }

    func completeRuntimeOrchestrationPresentation(
        interactionID: UUID,
        expectedSessionID: String,
        subtitleState: String,
        particleState: String,
        lifecycleState: RuntimeLifecycleState,
        status: RuntimeOrchestrationStepStatus
    ) {
        runtimeCore.completeRuntimeOrchestrationPresentation(
            interactionID: interactionID,
            expectedSessionID: expectedSessionID,
            subtitleState: subtitleState,
            particleState: particleState,
            lifecycleState: lifecycleState,
            status: status
        )
    }

    func clearRuntimeOrchestrationRecords() {
        runtimeCore.clearRuntimeOrchestrationRecords()
    }
    #endif

    func consumeFirstAppearance(
        for residentID: String,
        userInitiated: Bool
    ) -> RuntimeFirstAppearanceResult? {
        runtimeCore.consumeFirstAppearance(for: residentID, userInitiated: userInitiated)
    }

    func saveCurrentSession(
        lastUserInput: String,
        lastResidentOutput: String,
        lastActivity: String,
        avatarState: AvatarState,
        dialogueEntries: [RuntimeDialogueEntryState]
    ) {
        runtimeCore.saveCurrentSession(
            lastUserInput: lastUserInput,
            lastResidentOutput: lastResidentOutput,
            lastActivity: lastActivity,
            avatarState: avatarState,
            dialogueEntries: dialogueEntries
        )
    }

    func markSessionUnclean(
        lastUserInput: String,
        lastResidentOutput: String,
        lastActivity: String,
        avatarState: AvatarState,
        dialogueEntries: [RuntimeDialogueEntryState]
    ) {
        runtimeCore.markSessionUnclean(
            lastUserInput: lastUserInput,
            lastResidentOutput: lastResidentOutput,
            lastActivity: lastActivity,
            avatarState: avatarState,
            dialogueEntries: dialogueEntries
        )
    }

    public func step(residentID: String, inputText: String) -> RuntimeStepResponse {
        prepare()
        lastDiagnostics = OrchestrationKernelDiagnostics(stateSummary: "passthrough_step")
        return runtimeCore.step(request: RuntimeStepRequest(residentID: residentID, inputText: inputText))
    }

    func configureTextProvider(profile: ProviderProfile) -> ProviderRequestError? {
        runtimeCore.configureTextProvider(profile: profile)
    }

    #if DEBUG
    func realtimeSpeechStateSnapshot() -> RealtimeSpeechStateSnapshot {
        runtimeCore.realtimeSpeechStateSnapshot()
    }

    func realtimeSpeechSubtitleSnapshot()
        -> RealtimeSpeechSubtitleSnapshot {
        runtimeCore.realtimeSpeechSubtitleSnapshot()
    }

    func testNativeSpeechConnectivity(
        profile: NativeSpeechProviderProfile
    ) async -> Result<Void, NativeSpeechError> {
        await runtimeCore.testNativeSpeechConnectivity(profile: profile)
    }
    #endif

    func startSpeechRouteASR(
        locale: String? = nil
    ) async -> Result<UInt64, SpeechRouteError> {
        await runtimeCore.startSpeechRouteASR(locale: locale)
    }

    func sendSpeechRouteASRAudio(
        _ input: ASRAudioInput
    ) async throws {
        try await runtimeCore.sendSpeechRouteASRAudio(input)
    }

    func receiveSpeechRouteASREvent(
        generation: UInt64
    ) async throws -> ASREvent {
        try await runtimeCore.receiveSpeechRouteASREvent(
            generation: generation
        )
    }

    func submitSpeechRouteASRFinal(
        _ event: ASREvent,
        interactionID: UUID
    ) async -> Result<SpeechRouteTurnResult, SpeechRouteTurnError> {
        await runtimeCore.submitSpeechRouteASRFinal(
            event,
            interactionID: interactionID
        )
    }

    func startSpeechRouteTTS(
        request: TTSSynthesisRequest
    ) async -> Result<Void, SpeechRouteError> {
        await runtimeCore.startSpeechRouteTTS(request: request)
    }

    func receiveSpeechRouteTTSEvent(
        generation: UInt64
    ) async throws -> TTSEvent {
        try await runtimeCore.receiveSpeechRouteTTSEvent(
            generation: generation
        )
    }

    func finishSpeechRouteASR(
        generation: UInt64
    ) async -> Result<Void, SpeechRouteError> {
        await runtimeCore.finishSpeechRouteASR(generation: generation)
    }

    func finishSpeechRouteTTS(
        generation: UInt64
    ) async -> Result<Void, SpeechRouteError> {
        await runtimeCore.finishSpeechRouteTTS(generation: generation)
    }

    func commitSpeechRoutePlayback(
        generation: UInt64
    ) -> Result<SpeechRouteTurnResult, SpeechRouteError> {
        runtimeCore.commitSpeechRoutePlayback(generation: generation)
    }

    func cancelSpeechRoute(
        generation: UInt64
    ) async -> Result<Void, SpeechRouteError> {
        await runtimeCore.cancelSpeechRoute(generation: generation)
    }

    func interruptSpeechRouteForNearEnd(
        generation: UInt64,
        locale: String? = nil
    ) async -> Result<UInt64, SpeechRouteError> {
        await runtimeCore.interruptSpeechRouteForNearEnd(
            generation: generation,
            locale: locale
        )
    }

    func closeSpeechRoute(
        generation: UInt64
    ) async -> Result<Void, SpeechRouteError> {
        await runtimeCore.closeSpeechRoute(generation: generation)
    }

    func startNativeSpeechInput(
        profile: NativeSpeechProviderProfile,
        captureGeneration: UInt64
    ) async -> Result<NativeSpeechInputBinding, NativeSpeechError> {
        if let error = runtimeCore.configureNativeSpeechProvider(
            profile: profile
        ) {
            return .failure(error)
        }
        do {
            return .success(
                try await runtimeCore.startNativeSpeechInput(
                    captureGeneration: captureGeneration
                )
            )
        } catch let error as NativeSpeechError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    nonisolated func sendNativeSpeechInput(
        _ payload: NativeSpeechAudioPayload,
        context: NativeSpeechInputFrameContext
    ) async -> Result<
        NativeSpeechInputFrameDisposition,
        NativeSpeechError
    > {
        do {
            return .success(
                try await runtimeCore.sendNativeSpeechInput(
                    payload,
                    context: context
                )
            )
        } catch let error as NativeSpeechError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    nonisolated func receiveNativeSpeechEvent(
        interactionID: NativeSpeechInteractionID
    ) async -> Result<NativeSpeechEventDisposition, NativeSpeechError> {
        do {
            return .success(
                try await runtimeCore.receiveNativeSpeechEvent(
                    interactionID: interactionID
                )
            )
        } catch let error as NativeSpeechError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    nonisolated func handleNativeSpeechPlaybackEvent(
        _ event: RealtimeSpeechPlaybackEvent
    ) async -> RealtimeSpeechTransitionDisposition {
        await runtimeCore.handleNativeSpeechPlaybackEvent(event)
    }

    nonisolated func commitNativeSpeechInterrupt(
        interactionID: NativeSpeechInteractionID,
        turnNumber: UInt64,
        turnGeneration: UInt64
    ) async -> Result<Bool, NativeSpeechError> {
        do {
            return .success(
                try await runtimeCore.commitNativeSpeechInterrupt(
                    interactionID: interactionID,
                    turnNumber: turnNumber,
                    turnGeneration: turnGeneration
                )
            )
        } catch let error as NativeSpeechError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    func stopNativeSpeechInput(
        binding: NativeSpeechInputBinding,
        reason: NativeSpeechCancellationReason
    ) async -> Result<Void, NativeSpeechError> {
        do {
            try await runtimeCore.stopNativeSpeechInput(
                binding: binding,
                reason: reason
            )
            return .success(())
        } catch let error as NativeSpeechError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    nonisolated func closeNativeSpeechInput(
        binding: NativeSpeechInputBinding
    ) async -> Result<Void, NativeSpeechError> {
        do {
            try await runtimeCore.closeNativeSpeechInput(binding: binding)
            return .success(())
        } catch let error as NativeSpeechError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    func startRealtimeResidentBrainInput() async -> Result<
        RealtimeBrainSessionIdentity,
        RealtimeResidentBrainError
    > {
        await runtimeCore.startRealtimeResidentBrainSession()
    }

    nonisolated func sendRealtimeResidentBrainAudio(
        _ frame: RealtimeBrainAudioFrame,
        sourceGateEpoch: UInt64 = 0,
        userActivityEvidence: Bool = false
    ) async -> Result<Void, RealtimeResidentBrainError> {
        await runtimeCore.appendRealtimeResidentBrainAudio(
            frame,
            sourceGateEpoch: sourceGateEpoch,
            userActivityEvidence: userActivityEvidence
        )
    }

    nonisolated func receiveRealtimeResidentBrainEvent(
        session: RealtimeBrainSessionIdentity
    ) async -> Result<RealtimeBrainEventDisposition, RealtimeResidentBrainError> {
        do {
            return .success(
                try await runtimeCore.receiveRealtimeResidentBrainEvent(
                    session: session
                )
            )
        } catch let error as RealtimeResidentBrainError {
            return .failure(error)
        } catch {
            return .failure(.transportFailure)
        }
    }

    nonisolated func stopRealtimeResidentBrainInput(
        session: RealtimeBrainSessionIdentity
    ) async -> Result<Void, RealtimeResidentBrainError> {
        await runtimeCore.closeRealtimeResidentBrainSession(
            identity: session
        )
    }

    func submitRealtimeResidentBrainEligibleAcousticEvidence(
        observation: RealtimeAcousticObservation,
        evidence: RealtimeInterruptionEvidence
    ) async -> Result<
        RealtimeInterruptionDecision,
        RealtimeResidentBrainError
    > {
        await runtimeCore.submitRealtimeResidentBrainEligibleAcousticEvidence(
            observation: observation,
            evidence: evidence
        )
    }

    func observeRealtimeResidentBrainAcoustics(
        _ observation: RealtimeAcousticObservation
    ) -> RealtimeAcousticObservationDisposition {
        runtimeCore.observeRealtimeResidentBrainAcoustics(observation)
    }

    func claimRealtimeResidentBrainInterruptionDecision(
        for event: RealtimeResidentBrainEvent
    ) async -> Result<
        RealtimeInterruptionDecision,
        RealtimeResidentBrainError
    > {
        await runtimeCore.claimRealtimeResidentBrainInterruptionDecision(
            for: event
        )
    }

    func completeRealtimeResidentBrainInterruption(
        _ decision: RealtimeConfirmedInterruption
    ) async -> Result<
        RealtimeBrainSessionIdentity,
        RealtimeResidentBrainError
    > {
        await runtimeCore.completeRealtimeResidentBrainInterruption(decision)
    }

    func testResidentReply(
        inputText: String,
        interactionID: UUID? = nil
    ) async -> Result<RuntimeResidentReply, ProviderRequestError> {
        await requestResidentReply(inputText: inputText, interactionID: interactionID)
    }

    func requestResidentReply(
        inputText: String,
        interactionID: UUID? = nil
    ) async -> Result<RuntimeResidentReply, ProviderRequestError> {
        await runtimeCore.requestResidentReply(
            inputText: inputText,
            interactionID: interactionID
        )
    }

    public func cancelCurrentStep() {
        runtimeCore.cancelCurrentStep()
    }

    public func interrupt() {
        runtimeCore.interrupt(request: RuntimeCancellationRequest(reason: .interrupted))
    }

    public func runtimeTick() -> RuntimeTickResponse {
        runtimeCore.runtimeTick()
    }
}
