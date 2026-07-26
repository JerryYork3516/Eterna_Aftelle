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
        interactionStrength: 0
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
        steps = interaction.steps.map {
            RuntimeOrchestrationStepViewState(
                kind: $0.kind.rawValue,
                status: $0.status.rawValue,
                durationMilliseconds: $0.durationMilliseconds
            )
        }
    }
}

struct RuntimeOrchestrationViewState: Equatable {
    var interactions: [RuntimeOrchestrationInteractionViewState] = []
    var statusKey: String?
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
    private let runtimeCore: RuntimeCore
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
        await runtimeCore.testResidentReply(inputText: inputText, interactionID: interactionID)
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
