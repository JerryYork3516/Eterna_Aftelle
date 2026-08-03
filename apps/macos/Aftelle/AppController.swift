import Combine
import Foundation
#if DEBUG
import AppKit
import UniformTypeIdentifiers
#endif

private enum DefaultTextProviderConfiguration {
    static let profileDefaultsKey = "aftelle.textProviderProfile.v1"
    static let profile = ProviderProfile(
        profileID: "primary-text-llm",
        providerID: "deepseek",
        adapterType: "openai_compatible",
        modelID: "deepseek-v4-flash",
        baseURL: "https://api.deepseek.com",
        keyRef: ProviderKeychainStore.keyRef,
        enabled: true,
        timeout: 30,
        stream: false,
        thinkingMode: "disabled"
    )
}

#if DEBUG
private enum Stage75NativeSpeechConfiguration {
    static let profile = NativeSpeechProviderProfile(
        profileID: "stage7_5_stepfun_realtime_primary",
        providerID: "StepFun",
        capability: "native_speech",
        adapterID: "stepfun_realtime",
        modelID: "stepaudio-2.5-realtime",
        voiceID: "linjiajiejie",
        endpoint: URL(
            string: "wss://api.stepfun.com/v1/realtime?model=stepaudio-2.5-realtime"
        )!,
        transport: "websocket",
        inputAudioFormat: .pcm16,
        outputAudioFormat: .pcm16,
        turnDetection: NativeSpeechTurnDetection(
            type: .serverVAD,
            prefixPaddingMilliseconds: 500
        ),
        languageMetadata: "zh-CN",
        keyRef: ProviderKeychainStore.stepFunKeyRef
    )
}
#endif

enum ParticleColorSource: String, CaseIterable, Identifiable {
    case digitalResident
    case systemDefault

    var id: String { rawValue }
}

@MainActor
final class AppController: ObservableObject {
    private static let residentBookmarkKey = "aftelle.activeResidentBookmark.v1"

    @Published private(set) var startupState: AppStartupState = .idle
    @Published private(set) var runtimeStatus = "Runtime status: not loaded"
    @Published private(set) var fixtureStatus = "DR fixture: not loaded"
    @Published private(set) var residentID = "resident_id: -"
    @Published private(set) var displayName = "display_name: -"
    @Published private(set) var diagnostics = ""
    @Published private(set) var sessionState = AppSessionState()
    @Published private(set) var avatarState = AppAvatarState()
    @Published private(set) var residentState = AppResidentState()
    @Published private(set) var traceState = RuntimeTraceViewState()
    @Published private(set) var clockState = RuntimeClockViewState()
    @Published private(set) var debugPanelState = DebugPanelViewState()
    @Published private(set) var runtimeState: AppRuntimeState = .idle
    @Published private(set) var residentVisualIntent: ResidentVisualIntent = .idle
    @Published private(set) var residentSpeechSignal: ResidentSpeechSignal = .inactive
    @Published private(set) var particleExpressionInput =
        ParticleExpressionInput.neutral
    @Published private(set) var particleAvatarMode: ParticleAvatarMode = .particleCore
    @Published private(set) var particleRenderKind: ParticleRenderKind = .particleCore
    @Published private(set) var particleShellMode: ParticleShellMode = .darkShell
    @Published var isParticleDebugPanelPresented = false
    @Published private(set) var particleColorProfile = ParticleColorProfile.systemDefault
    @Published private(set) var particleDRColorPalette: [String] = []
    @Published private(set) var particleColorSource: ParticleColorSource = .digitalResident
    @Published private(set) var effectiveParticleColorProfile =
        ParticleColorProfile.systemDefault
    @Published private(set) var particleSubtitleState = ParticleSubtitleState.hidden
    @Published private(set) var particleDebugSnapshot = ParticleDebugSnapshot.empty
    @Published private(set) var residentTextInputState = ResidentTextInputViewState()
    @Published private(set) var providerDebugState = ProviderDebugViewState(
        profile: DefaultTextProviderConfiguration.profile
    )
    #if DEBUG
    @Published private(set) var nativeSpeechProviderDebugState =
        NativeSpeechProviderDebugViewState(
            profile: Stage75NativeSpeechConfiguration.profile
        )
    @Published private(set) var speechAudioHostSnapshot =
        MacSpeechAudioHostSnapshot.initial
    @Published private(set) var dialogueAuditState = DialogueAuditViewState()
    @Published private(set) var runtimeOrchestrationState = RuntimeOrchestrationViewState()
    @Published private(set) var relationshipProgressionDebugState =
        RelationshipProgressionDebugViewState()
    #endif

    private let orchestrationKernel: OrchestrationKernel
    private let providerKeychainStore: ProviderKeychainStore
    private var activeProviderProfile: ProviderProfile?
    private var loadedResidentID = ""
    private var loadedSessionID = ""
    private var dialogueEntries: [AppDialogueEntryState] = []
    private var latestParticleRenderMetrics = ParticleRenderMetrics.empty
    private var effectiveColorProfileSource = "systemDefault"
    private var effectiveColorProfileFallbackUsed = true
    private var residentTextRequestID: UUID?
    private var residentTextTask:
        Task<Result<RuntimeResidentReply, ProviderRequestError>, Never>?
    private var residentTextPresentationID: UUID?
    private var providerConfigurationGeneration = 0
    #if DEBUG
    private let speechAudioHost: MacSpeechAudioHost
    private let debugSubtitleKeys = [
        "particleSubtitle.test.0",
        "particleSubtitle.test.1",
        "particleSubtitle.test.2"
    ]
    private var debugSubtitleIndex = 0
    private var providerTestRequestID: UUID?
    private var providerTestTask:
        Task<Result<RuntimeResidentReply, ProviderRequestError>, Never>?
    #endif

    init() {
        let credentialStore = ProviderKeychainStore()
        let runtimeCore: RuntimeCore
        #if DEBUG
        speechAudioHost = MacSpeechAudioHost()
        runtimeCore = StepFunRealtimeRuntimeComposition.makeRuntimeCore(
            credentialReader: credentialStore
        )
        #else
        runtimeCore = RuntimeCore(providerCredentialReader: credentialStore)
        #endif
        providerKeychainStore = credentialStore
        orchestrationKernel = OrchestrationKernel(
            runtimeCore: runtimeCore
        )
        restoreProviderConfiguration()
        #if DEBUG
        refreshNativeSpeechProviderDebugState()
        #endif
    }

    init(orchestrationKernel: OrchestrationKernel) {
        self.orchestrationKernel = orchestrationKernel
        providerKeychainStore = ProviderKeychainStore()
        #if DEBUG
        speechAudioHost = MacSpeechAudioHost()
        #endif
        restoreProviderConfiguration()
        #if DEBUG
        refreshNativeSpeechProviderDebugState()
        #endif
    }

    func start() {
        startupState = .loading
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()

        let bookmarkedResident = loadBookmarkedResident()
        if let bookmarkedResident {
            applyLoadResult(
                bookmarkedResident.result,
                drData: bookmarkedResident.data,
                sourceLabel: "Debug DR",
                shouldPresentFirstGreeting: false
            )
        }

        let restoreResult = orchestrationKernel.restoreMostRecentSession()
        if restoreResult.didRestore {
            let restoredDisplayName = avatarState.residentID == restoreResult.residentID
                ? avatarState.displayName
                : ""
            loadedResidentID = restoreResult.residentID
            loadedSessionID = restoreResult.sessionID
            dialogueEntries = restoreResult.dialogueEntries.map {
                AppDialogueEntryState(
                    id: "\($0.role)-\(Int($0.timestamp.timeIntervalSince1970))",
                    role: $0.role,
                    text: $0.text,
                    timestamp: ISO8601DateFormatter().string(from: $0.timestamp)
                )
            }
            runtimeStatus = "Runtime status: session restored"
            fixtureStatus = "DR fixture: loaded"
            residentID = "resident_id: \(restoreResult.residentID.isEmpty ? "-" : restoreResult.residentID)"
            displayName = "display_name: \(restoredDisplayName.isEmpty ? "restored session" : restoredDisplayName)"
            sessionState = AppSessionState(
                residentID: restoreResult.residentID,
                sessionID: restoreResult.sessionID,
                lastUserInput: restoreResult.lastUserInput,
                lastResidentOutput: restoreResult.lastResidentOutput,
                lastActivity: restoreResult.lastActivity,
                shutdownState: restoreResult.shutdownState.rawValue,
                recoveryRequired: restoreResult.recoveryRequired,
                recoveredAt: restoreResult.recoveredAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                dialogueEntries: dialogueEntries
            )
            residentState = AppResidentState(
                residentID: restoreResult.residentID,
                sessionID: restoreResult.sessionID,
                lifecycleStatus: restoreResult.recoveryRequired ? "recovered" : "restored",
                presence: "available",
                lastActivitySummary: restoreResult.lastActivity,
                lastUpdatedAt: ISO8601DateFormatter().string(from: Date()),
                avatarMode: restoreResult.avatarMode
            )
            avatarState = AppAvatarState(
                residentID: restoreResult.residentID,
                displayName: restoredDisplayName,
                mode: restoreResult.avatarMode,
                presence: restoreResult.avatarPresence,
                moodHint: restoreResult.avatarMoodHint,
                activityHint: restoreResult.avatarActivityHint,
                particleHint: restoreResult.avatarParticleHint
            )
            diagnostics = restoreResult.recoveryRequired ? "Session restored after unclean shutdown" : "Session restored"
            traceState = RuntimeTraceViewState(summary: diagnostics, entries: [])
            refreshDebugPanelState(shutdownState: restoreResult.shutdownState.rawValue, recoveryRequired: restoreResult.recoveryRequired, recoveredAt: restoreResult.recoveredAt.map { ISO8601DateFormatter().string(from: $0) } ?? "")
            startupState = .loaded
            refreshResidentVisualIntent()
            refreshParticleDebugSnapshot()
            return
        }

        if bookmarkedResident != nil {
            return
        }

        startupState = .idle
        runtimeState = .idle
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()
    }

    func updateParticleRenderMetrics(_ metrics: ParticleRenderMetrics) {
        latestParticleRenderMetrics = metrics
        refreshParticleDebugSnapshot()
        #if DEBUG
        refreshRuntimeOrchestrationState()
        #endif
    }

    func setParticleColorSource(_ source: ParticleColorSource) {
        particleColorSource = source
        applyEffectiveParticleColorProfile()
        refreshParticleDebugSnapshot()
    }

    var isResidentTextInputAvailable: Bool {
        !loadedResidentID.isEmpty && !loadedSessionID.isEmpty
    }

    @discardableResult
    func submitResidentText(_ inputText: String) async -> Bool {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, !residentTextInputState.isSubmitting else { return false }
        guard isResidentTextInputAvailable else {
            residentTextInputState.errorKey = "residentInput.error.residentUnavailable"
            runtimeState = .idle
            presentResidentTextVisualState(.error)
            return false
        }

        let requestID = UUID()
        residentTextRequestID = requestID
        residentTextPresentationID = nil
        let residentIDAtStart = loadedResidentID
        let sessionIDAtStart = loadedSessionID
        let profileAtStart = activeProviderProfile
        let configurationGenerationAtStart = providerConfigurationGeneration

        residentTextInputState = ResidentTextInputViewState(isSubmitting: true)
        residentSpeechSignal = .ended
        runtimeState = .running
        refreshResidentVisualIntent(
            visualStateMode: ResidentVisualIntent.thinking.rawValue
        )
        let thinkingPresentationStart = ProcessInfo.processInfo.systemUptime
        refreshParticleDebugSnapshot()
        #if DEBUG
        appendDialogueAuditUser(trimmedInput)
        #endif

        let requestTask = Task {
            await orchestrationKernel.requestResidentReply(
                inputText: trimmedInput,
                interactionID: requestID
            )
        }
        residentTextTask = requestTask
        let result = await requestTask.value
        if case .success = result {
            let elapsed = ProcessInfo.processInfo.systemUptime
                - thinkingPresentationStart
            let remaining = ParticleTuning.Engine.minimumThinkingPresentationDuration
                - elapsed
            if remaining > 0 {
                try? await Task.sleep(
                    nanoseconds: Self.nanoseconds(remaining)
                )
            }
        }
        guard residentTextRequestID == requestID else {
            #if DEBUG
            completeRuntimeOrchestrationPresentation(
                interactionID: requestID,
                expectedSessionID: sessionIDAtStart,
                subtitleState: "skipped",
                particleState: "skipped",
                lifecycleState: .idle,
                status: .skipped
            )
            #endif
            return false
        }
        residentTextRequestID = nil
        residentTextTask = nil
        residentTextInputState.isSubmitting = false

        guard loadedResidentID == residentIDAtStart,
              loadedSessionID == sessionIDAtStart,
              activeProviderProfile == profileAtStart,
              providerConfigurationGeneration == configurationGenerationAtStart else {
            residentTextInputState.errorKey = statusKey(for: .cancelled)
            runtimeState = .idle
            presentResidentTextVisualState(.error)
            #if DEBUG
            completeRuntimeOrchestrationPresentation(
                interactionID: requestID,
                expectedSessionID: sessionIDAtStart,
                subtitleState: String(describing: particleSubtitleState.phase),
                particleState: String(describing: residentVisualIntent),
                lifecycleState: .idle,
                status: .completed
            )
            #endif
            return false
        }

        switch result {
        case .success(let reply):
            let replyText = reply.replyText
            particleExpressionInput = makeParticleExpressionInput(
                from: reply.expression,
                interactionID: requestID
            )
            let timestamp = ISO8601DateFormatter().string(from: Date())
            dialogueEntries.append(AppDialogueEntryState(
                id: "user-\(UUID().uuidString)",
                role: "user",
                text: trimmedInput,
                timestamp: timestamp
            ))
            dialogueEntries.append(AppDialogueEntryState(
                id: "resident-\(UUID().uuidString)",
                role: "resident",
                text: replyText,
                timestamp: timestamp
            ))
            dialogueEntries = Array(dialogueEntries.suffix(8))
            sessionState.residentID = residentIDAtStart
            sessionState.sessionID = sessionIDAtStart
            sessionState.lastUserInput = trimmedInput
            sessionState.lastResidentOutput = replyText
            sessionState.dialogueEntries = dialogueEntries
            #if DEBUG
            appendDialogueAuditResident(
                replyText,
                displayName: avatarState.displayName
            )
            #endif
            residentTextInputState.errorKey = nil
            particleSubtitleState = ParticleSubtitleState(
                text: replyText,
                phase: .showing
            )
            runtimeState = .idle
            presentResidentTextVisualState(.speaking)
            #if DEBUG
            completeRuntimeOrchestrationPresentation(
                interactionID: requestID,
                expectedSessionID: sessionIDAtStart,
                subtitleState: String(describing: particleSubtitleState.phase),
                particleState: String(describing: residentVisualIntent),
                lifecycleState: .speaking,
                status: .completed
            )
            #endif
            return true
        case .failure(let error):
            residentTextInputState.errorKey = statusKey(for: error)
            runtimeState = .idle
            presentResidentTextVisualState(.error)
            #if DEBUG
            completeRuntimeOrchestrationPresentation(
                interactionID: requestID,
                expectedSessionID: sessionIDAtStart,
                subtitleState: String(describing: particleSubtitleState.phase),
                particleState: String(describing: residentVisualIntent),
                lifecycleState: error == .cancelled ? .idle : .error,
                status: .completed
            )
            #endif
            return false
        }
    }

    #if DEBUG
    func copyDialogueAudit() {
        copyDialogueAudit { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
    }

    func copyDialogueAudit(using writer: (String) -> Bool) {
        guard writer(dialogueAuditTranscript()) else {
            dialogueAuditState.statusKey = "dialogueAudit.status.copyFailed"
            return
        }
        dialogueAuditState.statusKey = "dialogueAudit.status.copied"
    }

    func exportDialogueAudit() {
        let exportedAt = Date()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = String(localized: "dialogueAudit.chooseLocation")
        panel.nameFieldStringValue = dialogueAuditFileName(exportedAt: exportedAt)

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.writeDialogueAudit(to: url, exportedAt: exportedAt)
                self.dialogueAuditState.statusKey = "dialogueAudit.status.exported"
            } catch {
                self.dialogueAuditState.statusKey = "dialogueAudit.status.exportFailed"
            }
        }
    }

    func clearDialogueAudit() {
        dialogueAuditState.clear()
    }

    func copyRuntimeOrchestrationInteraction(_ interactionID: UUID) {
        copyRuntimeOrchestrationInteraction(interactionID) { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
    }

    func copyRuntimeOrchestrationInteraction(
        _ interactionID: UUID,
        using writer: (String) -> Bool
    ) {
        guard let text = runtimeOrchestrationTranscript(interactionID: interactionID),
              writer(text) else {
            runtimeOrchestrationState.statusKey = "runtimeOrchestration.status.copyFailed"
            return
        }
        runtimeOrchestrationState.statusKey = "runtimeOrchestration.status.copied"
    }

    func exportRuntimeOrchestrationInteraction(_ interactionID: UUID) {
        guard runtimeOrchestrationState.interactions.contains(where: { $0.id == interactionID }) else {
            runtimeOrchestrationState.statusKey = "runtimeOrchestration.status.exportFailed"
            return
        }
        let exportedAt = Date()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = String(localized: "runtimeOrchestration.chooseLocation")
        panel.nameFieldStringValue = runtimeOrchestrationFileName(
            interactionID: interactionID,
            exportedAt: exportedAt
        )

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.writeRuntimeOrchestrationInteraction(
                    interactionID,
                    to: url,
                    exportedAt: exportedAt
                )
                self.runtimeOrchestrationState.statusKey = "runtimeOrchestration.status.exported"
            } catch {
                self.runtimeOrchestrationState.statusKey = "runtimeOrchestration.status.exportFailed"
            }
        }
    }

    func clearRuntimeOrchestrationRecords() {
        orchestrationKernel.clearRuntimeOrchestrationRecords()
        runtimeOrchestrationState = RuntimeOrchestrationViewState(
            statusKey: "runtimeOrchestration.status.cleared"
        )
    }

    func runtimeOrchestrationTranscript(
        interactionID: UUID,
        exportedAt: Date = Date()
    ) -> String? {
        guard let interaction = runtimeOrchestrationState.interactions.first(where: {
            $0.id == interactionID
        }) else {
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let fewShotLines = interaction.fewShotReferences.map {
            localizedFormat(
                "runtimeOrchestration.export.fewShot",
                $0.exampleID,
                runtimeOrchestrationLocalizedValue("fewShotKind", $0.kind)
            )
        }
        let stepLines = interaction.steps.map {
            localizedFormat(
                "runtimeOrchestration.export.step",
                runtimeOrchestrationLocalizedValue("step", $0.kind),
                runtimeOrchestrationLocalizedValue("status", $0.status),
                $0.durationMilliseconds
            )
        }
        let lines = [
            String(localized: "runtimeOrchestration.export.title"),
            localizedFormat("runtimeOrchestration.export.interactionID", interaction.id.uuidString),
            localizedFormat("runtimeOrchestration.export.residentID", interaction.residentID),
            localizedFormat("runtimeOrchestration.export.sessionID", interaction.sessionID),
            localizedFormat(
                "runtimeOrchestration.export.startedAt",
                dateFormatter.string(from: interaction.startedAt)
            ),
            localizedFormat(
                "runtimeOrchestration.export.endedAt",
                dateFormatter.string(from: interaction.endedAt)
            ),
            localizedFormat("runtimeOrchestration.export.duration", interaction.durationMilliseconds),
            localizedFormat(
                "runtimeOrchestration.export.dailyRules",
                runtimeOrchestrationLocalizedValue(
                    "boolean",
                    interaction.dailyRulesEnabled ? "enabled" : "disabled"
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.emotionalRules",
                runtimeOrchestrationLocalizedValue(
                    "boolean",
                    interaction.emotionalRulesEnabled ? "enabled" : "disabled"
                )
            ),
            localizedFormat("runtimeOrchestration.export.recentMessages", interaction.recentMessageCount),
            localizedFormat("runtimeOrchestration.export.fewShotCount", interaction.fewShotReferences.count)
        ] + fewShotLines + [
            localizedFormat(
                "runtimeOrchestration.export.preferenceCount",
                interaction.approvedPreferenceCount
            ),
            localizedFormat("runtimeOrchestration.export.provider", interaction.providerID ?? "-"),
            localizedFormat("runtimeOrchestration.export.model", interaction.modelID ?? "-"),
            localizedFormat("runtimeOrchestration.export.adapter", interaction.adapterType ?? "-"),
            localizedFormat(
                "runtimeOrchestration.export.result",
                runtimeOrchestrationLocalizedValue("result", interaction.result)
            ),
            localizedFormat(
                "runtimeOrchestration.export.error",
                interaction.errorCategory.map {
                    runtimeOrchestrationLocalizedValue("error", $0)
                } ?? "-"
            ),
            localizedFormat(
                "runtimeOrchestration.export.sessionWrite",
                runtimeOrchestrationLocalizedValue("sessionWrite", interaction.sessionWriteStatus)
            ),
            localizedFormat(
                "runtimeOrchestration.export.subtitle",
                runtimeOrchestrationLocalizedValue("presentation", interaction.subtitleState)
            ),
            localizedFormat(
                "runtimeOrchestration.export.particle",
                runtimeOrchestrationLocalizedValue("presentation", interaction.particleState)
            ),
            localizedFormat(
                "runtimeOrchestration.export.lifecycle",
                runtimeOrchestrationLocalizedValue(
                    "presentation",
                    interaction.lifecycleState
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.expressionState",
                runtimeOrchestrationLocalizedValue(
                    "expressionState",
                    interaction.expressionState
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.expressionIntensity",
                String(format: "%.3f", interaction.expressionIntensity)
            ),
            localizedFormat(
                "runtimeOrchestration.export.expressionTransitionProgress",
                String(
                    format: "%.3f",
                    interaction.expressionTransitionProgress
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.expressionFallback",
                runtimeOrchestrationLocalizedValue(
                    "boolean",
                    interaction.expressionFallbackOccurred
                        ? "enabled"
                        : "disabled"
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.expressionLifecycleOverride",
                runtimeOrchestrationLocalizedValue(
                    "boolean",
                    interaction.expressionLifecycleOverrideActive
                        ? "enabled"
                        : "disabled"
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.expressionMappingSource",
                runtimeOrchestrationLocalizedValue(
                    "mappingSource",
                    interaction.expressionMappingSource
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.relationshipStage",
                interaction.relationshipStageID ?? "-"
            ),
            localizedFormat(
                "runtimeOrchestration.export.relationshipEvidence",
                interaction.relationshipEvidenceIDs.isEmpty
                    ? "-"
                    : interaction.relationshipEvidenceIDs.joined(
                        separator: ", "
                    )
            ),
            localizedFormat(
                "runtimeOrchestration.export.relationshipDecision",
                interaction.relationshipDecision
            ),
            localizedFormat(
                "runtimeOrchestration.export.relationshipReason",
                interaction.relationshipReason
            ),
            localizedFormat(
                "runtimeOrchestration.export.brightnessMultiplier",
                expressionMultiplierTransition(
                    interaction.currentBrightnessMultiplier,
                    interaction.brightnessMultiplier
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.saturationMultiplier",
                expressionMultiplierTransition(
                    interaction.currentSaturationMultiplier,
                    interaction.saturationMultiplier
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.temperatureShift",
                expressionMultiplierTransition(
                    interaction.currentTemperatureShift,
                    interaction.temperatureShift
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.energyMultiplier",
                expressionMultiplierTransition(
                    interaction.currentEnergyMultiplier,
                    interaction.energyMultiplier
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.motionSpeedMultiplier",
                expressionMultiplierTransition(
                    interaction.currentMotionSpeedMultiplier,
                    interaction.motionSpeedMultiplier
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.diffusionMultiplier",
                expressionMultiplierTransition(
                    interaction.currentDiffusionMultiplier,
                    interaction.diffusionMultiplier
                )
            ),
            localizedFormat(
                "runtimeOrchestration.export.exportedAt",
                dateFormatter.string(from: exportedAt)
            ),
            "",
            String(localized: "runtimeOrchestration.export.timeline")
        ] + stepLines
        return lines.joined(separator: "\n")
    }

    func writeRuntimeOrchestrationInteraction(
        _ interactionID: UUID,
        to url: URL,
        exportedAt: Date = Date()
    ) throws {
        guard let text = runtimeOrchestrationTranscript(
            interactionID: interactionID,
            exportedAt: exportedAt
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try Data(text.utf8).write(to: url, options: .withoutOverwriting)
    }

    func clearDialogueTestData() {
        invalidateResidentTextSubmission()
        providerTestRequestID = nil
        providerTestTask?.cancel()
        providerTestTask = nil
        providerDebugState.isTesting = false
        providerDebugState.replyText = ""
        providerDebugState.statusKey = "particleDebug.provider.status.ready"

        do {
            let newSessionID = try orchestrationKernel.clearDialogueTestData()
            loadedSessionID = newSessionID ?? ""
            dialogueEntries.removeAll(keepingCapacity: true)
            if let newSessionID {
                sessionState = AppSessionState(residentID: loadedResidentID, sessionID: newSessionID)
                residentState.sessionID = newSessionID
                residentState.lastActivitySummary = ""
                residentState.lastUpdatedAt = ISO8601DateFormatter().string(from: Date())
            } else {
                loadedResidentID = ""
                residentID = "resident_id: -"
                displayName = "display_name: -"
                sessionState = AppSessionState()
                residentState = AppResidentState()
                avatarState = AppAvatarState()
                runtimeStatus = "Runtime status: not loaded"
                fixtureStatus = "DR fixture: not loaded"
                startupState = .idle
            }
            particleSubtitleState = .hidden
            particleExpressionInput = .neutral
            residentTextInputState = ResidentTextInputViewState()
            runtimeState = .idle
            dialogueAuditState.clear()
            dialogueAuditState.statusKey = "dialogueAudit.status.testDataCleared"
            refreshDebugPanelState()
            refreshRelationshipProgressionDebugState()
            refreshResidentVisualIntent()
            refreshParticleDebugSnapshot()
        } catch {
            dialogueAuditState.statusKey = "dialogueAudit.status.testDataClearFailed"
        }
    }

    func dialogueAuditTranscript() -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return dialogueAuditState.entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] \(entry.displayName)\n\(entry.text)"
        }.joined(separator: "\n\n")
    }

    func dialogueAuditExportText(exportedAt: Date = Date()) -> String {
        let residentName = currentAuditResidentDisplayName
        let modelID = activeProviderProfile?.modelID ?? "-"
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let header = [
            String(localized: "dialogueAudit.export.title"),
            localizedFormat("dialogueAudit.export.resident", residentName),
            localizedFormat("dialogueAudit.export.model", modelID),
            localizedFormat("dialogueAudit.export.time", dateFormatter.string(from: exportedAt)),
            localizedFormat("dialogueAudit.export.count", dialogueAuditState.entries.count)
        ].joined(separator: "\n")
        let transcript = dialogueAuditTranscript()
        return transcript.isEmpty ? header : "\(header)\n\n\(transcript)"
    }

    func writeDialogueAudit(to url: URL, exportedAt: Date = Date()) throws {
        let data = Data(dialogueAuditExportText(exportedAt: exportedAt).utf8)
        try data.write(to: url, options: [.withoutOverwriting])
    }

    private func appendDialogueAuditUser(_ text: String) {
        dialogueAuditState.append(DialogueAuditEntry(
            role: .user,
            displayName: String(localized: "dialogueAudit.role.user"),
            text: text
        ))
    }

    private func appendDialogueAuditResident(_ text: String, displayName: String) {
        dialogueAuditState.append(DialogueAuditEntry(
            role: .resident,
            displayName: displayName.isEmpty
                ? String(localized: "dialogueAudit.role.resident")
                : displayName,
            text: text
        ))
    }

    private var currentAuditResidentDisplayName: String {
        avatarState.displayName.isEmpty
            ? String(localized: "dialogueAudit.role.resident")
            : avatarState.displayName
    }

    private func dialogueAuditFileName(exportedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let residentName = currentAuditResidentDisplayName.map { character in
            "/\\:?*|\"<>".contains(character) ? "_" : character
        }
        return localizedFormat(
            "dialogueAudit.fileName",
            String(residentName),
            formatter.string(from: exportedAt)
        )
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: String(localized: String.LocalizationValue(key)),
            locale: Locale.current,
            arguments: arguments
        )
    }

    private func runtimeOrchestrationFileName(
        interactionID: UUID,
        exportedAt: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return localizedFormat(
            "runtimeOrchestration.fileName",
            String(interactionID.uuidString.prefix(8)),
            formatter.string(from: exportedAt)
        )
    }

    private func runtimeOrchestrationLocalizedValue(_ namespace: String, _ value: String) -> String {
        let key = "runtimeOrchestration.\(namespace).\(value)"
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private func expressionMultiplierTransition(
        _ current: Double,
        _ target: Double
    ) -> String {
        String(format: "%.3f → %.3f", current, target)
    }

    private func completeRuntimeOrchestrationPresentation(
        interactionID: UUID,
        expectedSessionID: String,
        subtitleState: String,
        particleState: String,
        lifecycleState: RuntimeLifecycleState,
        status: RuntimeOrchestrationStepStatus
    ) {
        orchestrationKernel.completeRuntimeOrchestrationPresentation(
            interactionID: interactionID,
            expectedSessionID: expectedSessionID,
            subtitleState: subtitleState,
            particleState: particleState,
            lifecycleState: lifecycleState,
            status: status
        )
        refreshRuntimeOrchestrationState()
        refreshRelationshipProgressionDebugState()
    }

    private func refreshRuntimeOrchestrationState() {
        var state = orchestrationKernel.runtimeOrchestrationViewState()
        state.preserveParticleExpressionProjections(
            from: runtimeOrchestrationState
        )
        state.applyParticleExpression(
            rendered: latestParticleRenderMetrics.expression,
            pendingInput: particleExpressionInput,
            sessionID: loadedSessionID
        )
        runtimeOrchestrationState = state
    }

    private func refreshRelationshipProgressionDebugState() {
        relationshipProgressionDebugState =
            orchestrationKernel.relationshipProgressionDebugViewState()
    }

    func resetRelationshipProgressionForDebug() {
        relationshipProgressionDebugState =
            orchestrationKernel.resetRelationshipProgressionForDebug()
    }

    func setParticleAvatarMode(_ mode: ParticleAvatarMode) {
        particleAvatarMode = mode
        particleRenderKind = mode == .abstractBustReserved ? .abstractBustReserved : .particleCore
        refreshParticleDebugSnapshot()
    }

    func setParticleRenderKind(_ kind: ParticleRenderKind) {
        particleRenderKind = kind
        particleAvatarMode = kind.avatarMode
        refreshParticleDebugSnapshot()
    }

    func toggleParticleDebugPanel() {
        isParticleDebugPanelPresented.toggle()
    }

    func setParticleDebugPanelPresented(_ isPresented: Bool) {
        isParticleDebugPanelPresented = isPresented
        if isPresented {
            refreshRuntimeOrchestrationState()
        }
    }

    func setParticleShellMode(_ mode: ParticleShellMode) {
        particleShellMode = mode
        refreshParticleDebugSnapshot()
    }

    func showDebugSubtitle() {
        showDebugSubtitle(at: debugSubtitleIndex)
    }

    func showNextDebugSubtitle() {
        debugSubtitleIndex = (debugSubtitleIndex + 1) % debugSubtitleKeys.count
        showDebugSubtitle(at: debugSubtitleIndex)
    }

    func hideDebugSubtitle() {
        guard !particleSubtitleState.text.isEmpty else {
            particleSubtitleState = .hidden
            return
        }
        let fadingText = particleSubtitleState.text
        particleSubtitleState = ParticleSubtitleState(text: fadingText, phase: .fading)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            if particleSubtitleState.phase == .fading, particleSubtitleState.text == fadingText {
                particleSubtitleState = .hidden
                refreshParticleDebugSnapshot()
            }
        }
        refreshParticleDebugSnapshot()
    }

    func debugImportResident(from url: URL) {
        invalidateResidentTextSubmission()
        startupState = .loading
        refreshResidentVisualIntent()
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let drData = try? Data(contentsOf: url) else {
            applyFailure(runtimeMessage: "Runtime status: DR load failed", diagnosticsMessage: "Debug DR unreadable")
            return
        }

        let result = orchestrationKernel.loadResident(fixtureData: drData)
        if result.isLoaded {
            saveResidentBookmark(for: url)
        }
        applyLoadResult(
            result,
            drData: drData,
            sourceLabel: "Debug DR",
            shouldPresentFirstGreeting: true
        )
    }

    func saveProviderConfiguration(_ profile: ProviderProfile) {
        if let error = orchestrationKernel.configureTextProvider(profile: profile) {
            providerDebugState.statusKey = statusKey(for: error)
            providerDebugState.configurationSaved = activeProviderProfile != nil
            providerDebugState.replyText = ""
            return
        }

        guard let encoded = try? JSONEncoder().encode(profile) else {
            providerDebugState.statusKey = "particleDebug.provider.status.configurationFailed"
            providerDebugState.configurationSaved = false
            return
        }
        UserDefaults.standard.set(encoded, forKey: DefaultTextProviderConfiguration.profileDefaultsKey)
        activeProviderProfile = profile
        providerConfigurationGeneration += 1
        providerDebugState.profile = profile
        providerDebugState.configurationSaved = true
        providerDebugState.credentialSaved = providerKeychainStore.exists(for: profile.keyRef)
        providerDebugState.statusKey = "particleDebug.provider.status.configurationSaved"
        providerDebugState.replyText = ""
    }

    func saveProviderCredential(_ credential: String) {
        do {
            try providerKeychainStore.save(credential, for: providerDebugState.profile.keyRef)
            providerConfigurationGeneration += 1
            providerDebugState.credentialSaved = true
            providerDebugState.statusKey = "particleDebug.provider.status.credentialSaved"
        } catch {
            providerDebugState.credentialSaved = providerKeychainStore.exists(
                for: providerDebugState.profile.keyRef
            )
            providerDebugState.statusKey = "particleDebug.provider.status.credentialFailed"
        }
    }

    func deleteProviderCredential() {
        do {
            try providerKeychainStore.delete(for: providerDebugState.profile.keyRef)
            providerConfigurationGeneration += 1
            providerDebugState.credentialSaved = false
            providerDebugState.statusKey = "particleDebug.provider.status.credentialDeleted"
        } catch {
            providerDebugState.statusKey = "particleDebug.provider.status.credentialFailed"
        }
    }

    func testResidentReply(inputText: String) async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            providerDebugState.statusKey = "particleDebug.provider.status.inputRequired"
            providerDebugState.replyText = ""
            return
        }

        providerDebugState.isTesting = true
        providerDebugState.statusKey = "particleDebug.provider.status.testing"
        providerDebugState.replyText = ""
        let requestID = UUID()
        providerTestRequestID = requestID
        let residentIDAtStart = loadedResidentID
        let sessionIDAtStart = loadedSessionID
        let profileAtStart = activeProviderProfile
        let configurationGenerationAtStart = providerConfigurationGeneration
        let requestTask = Task {
            await orchestrationKernel.testResidentReply(
                inputText: inputText,
                interactionID: requestID
            )
        }
        providerTestTask = requestTask
        let result = await requestTask.value

        guard providerTestRequestID == requestID else {
            completeRuntimeOrchestrationPresentation(
                interactionID: requestID,
                expectedSessionID: sessionIDAtStart,
                subtitleState: "skipped",
                particleState: "skipped",
                lifecycleState: .idle,
                status: .skipped
            )
            return
        }
        providerTestRequestID = nil
        providerTestTask = nil
        providerDebugState.isTesting = false
        guard loadedResidentID == residentIDAtStart,
              loadedSessionID == sessionIDAtStart,
              activeProviderProfile == profileAtStart,
              providerConfigurationGeneration == configurationGenerationAtStart else {
            providerDebugState.statusKey = "particleDebug.provider.error.cancelled"
            providerDebugState.replyText = ""
            completeRuntimeOrchestrationPresentation(
                interactionID: requestID,
                expectedSessionID: sessionIDAtStart,
                subtitleState: "unchanged",
                particleState: String(describing: residentVisualIntent),
                lifecycleState: .idle,
                status: .skipped
            )
            return
        }
        let lifecycleState: RuntimeLifecycleState
        switch result {
        case .success(let reply):
            providerDebugState.statusKey = "particleDebug.provider.status.replyReceived"
            providerDebugState.replyText = reply.replyText
            lifecycleState = .idle
        case .failure(let error):
            providerDebugState.statusKey = statusKey(for: error)
            providerDebugState.replyText = ""
            lifecycleState = error == .cancelled ? .idle : .error
        }
        completeRuntimeOrchestrationPresentation(
            interactionID: requestID,
            expectedSessionID: sessionIDAtStart,
            subtitleState: "unchanged",
            particleState: String(describing: residentVisualIntent),
            lifecycleState: lifecycleState,
            status: .skipped
        )
        refreshRelationshipProgressionDebugState()
    }

    func saveNativeSpeechProviderCredential(_ credential: String) {
        do {
            try providerKeychainStore.save(
                credential,
                for: ProviderKeychainStore.stepFunKeyRef
            )
            nativeSpeechProviderDebugState.credentialSaved = true
            nativeSpeechProviderDebugState.statusKey =
                "particleDebug.stepfun.status.credentialSaved"
        } catch {
            refreshNativeSpeechProviderDebugState(
                statusKey: "particleDebug.stepfun.status.credentialFailed"
            )
        }
    }

    func refreshMicrophoneAuthorization() async {
        speechAudioHostSnapshot =
            await speechAudioHost.refreshAuthorization()
    }

    func requestMicrophoneAuthorization() async {
        speechAudioHostSnapshot =
            await speechAudioHost.requestMicrophoneAuthorization()
    }

    func startSpeechAudioCapture() async {
        speechAudioHostSnapshot = await speechAudioHost.startCapture()
    }

    func stopSpeechAudioCapture() async {
        speechAudioHostSnapshot = await speechAudioHost.stopCapture()
    }

    func shutdownSpeechAudioHost() async {
        await speechAudioHost.shutdown()
        speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
    }

    func deleteNativeSpeechProviderCredential() {
        do {
            try providerKeychainStore.delete(
                for: ProviderKeychainStore.stepFunKeyRef
            )
            nativeSpeechProviderDebugState.credentialSaved = false
            nativeSpeechProviderDebugState.statusKey =
                "particleDebug.stepfun.status.credentialDeleted"
        } catch {
            refreshNativeSpeechProviderDebugState(
                statusKey: "particleDebug.stepfun.status.credentialFailed"
            )
        }
    }

    func testNativeSpeechProviderConnectivity() async {
        guard providerKeychainStore.exists(
            for: ProviderKeychainStore.stepFunKeyRef
        ) else {
            refreshNativeSpeechProviderDebugState(
                statusKey: "particleDebug.stepfun.status.credentialMissing"
            )
            return
        }

        nativeSpeechProviderDebugState.isTesting = true
        nativeSpeechProviderDebugState.statusKey =
            "particleDebug.stepfun.status.testing"
        let result = await orchestrationKernel.testNativeSpeechConnectivity(
            profile: nativeSpeechProviderDebugState.profile
        )
        nativeSpeechProviderDebugState.isTesting = false
        switch result {
        case .success:
            nativeSpeechProviderDebugState.statusKey =
                "particleDebug.stepfun.status.pass"
        case .failure(let error):
            nativeSpeechProviderDebugState.statusKey =
                nativeSpeechConnectivityStatusKey(for: error)
        }
        nativeSpeechProviderDebugState.credentialSaved =
            providerKeychainStore.exists(
                for: ProviderKeychainStore.stepFunKeyRef
            )
    }

    private func refreshNativeSpeechProviderDebugState(
        statusKey: String? = nil
    ) {
        nativeSpeechProviderDebugState.credentialSaved =
            providerKeychainStore.exists(
                for: ProviderKeychainStore.stepFunKeyRef
            )
        if let statusKey {
            nativeSpeechProviderDebugState.statusKey = statusKey
        }
    }

    private func nativeSpeechConnectivityStatusKey(
        for error: NativeSpeechError
    ) -> String {
        switch error {
        case .unauthorized:
            return "particleDebug.stepfun.status.failedAuthentication"
        case .rateLimited, .unavailable, .timedOut, .transportFailure:
            return "particleDebug.stepfun.status.failedNetwork"
        case .cancelled:
            return "particleDebug.stepfun.status.cancelled"
        case .invalidConfiguration, .missingCredential, .invalidEvent,
             .interactionMismatch:
            return "particleDebug.stepfun.status.failedProviderConfiguration"
        }
    }

    private func showDebugSubtitle(at index: Int) {
        let key = debugSubtitleKeys[index]
        particleSubtitleState = ParticleSubtitleState(
            text: String(localized: String.LocalizationValue(key)),
            phase: .showing
        )
        refreshParticleDebugSnapshot()
    }
    #endif

    private func restoreProviderConfiguration() {
        guard let data = UserDefaults.standard.data(
            forKey: DefaultTextProviderConfiguration.profileDefaultsKey
        ), let profile = try? JSONDecoder().decode(ProviderProfile.self, from: data) else {
            providerDebugState.credentialSaved = providerKeychainStore.exists(
                for: providerDebugState.profile.keyRef
            )
            return
        }

        providerDebugState.profile = profile
        providerDebugState.credentialSaved = providerKeychainStore.exists(for: profile.keyRef)
        if let error = orchestrationKernel.configureTextProvider(profile: profile) {
            providerDebugState.configurationSaved = false
            providerDebugState.statusKey = statusKey(for: error)
            return
        }
        activeProviderProfile = profile
        providerDebugState.configurationSaved = true
        providerDebugState.statusKey = "particleDebug.provider.status.configurationSaved"
    }

    private func statusKey(for error: ProviderRequestError) -> String {
        switch error {
        case .unconfigured:
            return "particleDebug.provider.error.unconfigured"
        case .missingCredential:
            return "particleDebug.provider.error.missingCredential"
        case .invalidURL:
            return "particleDebug.provider.error.invalidURL"
        case .unauthorized:
            return "particleDebug.provider.error.unauthorized"
        case .rateLimited:
            return "particleDebug.provider.error.rateLimited"
        case .serverUnavailable:
            return "particleDebug.provider.error.serverUnavailable"
        case .timedOut:
            return "particleDebug.provider.error.timedOut"
        case .cancelled:
            return "particleDebug.provider.error.cancelled"
        case .networkFailure:
            return "particleDebug.provider.error.networkFailure"
        case .invalidResponse:
            return "particleDebug.provider.error.invalidResponse"
        case .emptyReply:
            return "particleDebug.provider.error.emptyReply"
        case .residentUnavailable:
            return "particleDebug.provider.error.residentUnavailable"
        }
    }

    private func presentResidentTextVisualState(
        _ intent: ResidentVisualIntent
    ) {
        let presentationID = UUID()
        residentTextPresentationID = presentationID
        let isSpeaking = intent == .speaking
        residentSpeechSignal = isSpeaking
            ? ResidentSpeechSignal(
                phase: .started,
                intensity: ParticleTuning.Engine.defaultSpeechIntensity
            )
            : .ended
        refreshResidentVisualIntent(visualStateMode: intent.rawValue)
        refreshParticleDebugSnapshot()
        Task { @MainActor [weak self] in
            if isSpeaking {
                try? await Task.sleep(
                    nanoseconds: Self.nanoseconds(
                        ParticleTuning.Engine.speechStartHoldDuration
                    )
                )
                guard let self,
                      self.residentTextPresentationID == presentationID else {
                    return
                }
                self.residentSpeechSignal = ResidentSpeechSignal(
                    phase: .sustained,
                    intensity: ParticleTuning.Engine.defaultSpeechIntensity
                )

                try? await Task.sleep(
                    nanoseconds: Self.nanoseconds(
                        ParticleTuning.Engine.speechSustainHoldDuration
                    )
                )
                guard self.residentTextPresentationID == presentationID else {
                    return
                }
                self.residentSpeechSignal = ResidentSpeechSignal(
                    phase: .paused,
                    intensity: 0
                )

                try? await Task.sleep(
                    nanoseconds: Self.nanoseconds(
                        ParticleTuning.Engine.speechPauseHoldDuration
                    )
                )
                guard self.residentTextPresentationID == presentationID else {
                    return
                }
                self.residentSpeechSignal = .ended

                try? await Task.sleep(
                    nanoseconds: Self.nanoseconds(
                        ParticleTuning.Engine.speechEndHoldDuration
                    )
                )
            } else {
                try? await Task.sleep(
                    nanoseconds: Self.nanoseconds(
                        ParticleTuning.Engine.transientStatePresentationDuration
                    )
                )
            }
            guard let self,
                  self.residentTextPresentationID == presentationID,
                  !self.residentTextInputState.isSubmitting else { return }
            self.residentTextPresentationID = nil
            if isSpeaking {
                self.refreshResidentVisualIntent(
                    visualStateMode: ResidentVisualIntent.idle.rawValue
                )
            } else {
                self.refreshResidentVisualIntent()
            }
            self.refreshParticleDebugSnapshot()
        }
    }

    private func invalidateResidentTextSubmission() {
        residentTextRequestID = nil
        residentTextTask?.cancel()
        residentTextTask = nil
        residentTextPresentationID = nil
        residentSpeechSignal = .ended
        residentTextInputState = ResidentTextInputViewState()
        runtimeState = .idle
    }

    private func applyLoadResult(
        _ result: RuntimeLoadResult,
        drData: Data,
        sourceLabel: String,
        shouldPresentFirstGreeting: Bool
    ) {
        guard result.isLoaded else {
            runtimeStatus = "Runtime status: \(result.statusMessage)"
            fixtureStatus = "\(sourceLabel): not loaded"
            diagnostics = result.diagnostics
            traceState = RuntimeTraceViewState(summary: result.diagnostics, entries: [])
            runtimeState = .idle
            refreshDebugPanelState()
            startupState = .failed
            refreshResidentVisualIntent()
            refreshParticleDebugSnapshot()
            return
        }

        loadedResidentID = result.residentID
        loadedSessionID = result.sessionID?.rawValue ?? ""
        particleExpressionInput = .neutral
        particleColorProfile = ParticleColorProfile.make(fromDRData: drData)
        particleDRColorPalette = Self.drColorPalette(from: drData)
        applyEffectiveParticleColorProfile()
        runtimeStatus = "Runtime status: \(result.statusMessage)"
        fixtureStatus = "\(sourceLabel): loaded"
        residentID = "resident_id: \(result.residentID.isEmpty ? "-" : result.residentID)"
        displayName = "display_name: \(result.displayName.isEmpty ? "-" : result.displayName)"
        sessionState = AppSessionState(
            residentID: result.residentID,
            sessionID: loadedSessionID,
            lastActivity: result.residentState?.lastActivitySummary ?? ""
        )
        dialogueEntries = []
        avatarState = result.avatarState.map {
            AppAvatarState(
                residentID: $0.residentID,
                displayName: $0.displayName,
                mode: $0.mode,
                presence: $0.presence,
                moodHint: $0.moodHint,
                activityHint: $0.activityHint,
                particleHint: $0.particleHint
            )
        } ?? AppAvatarState(residentID: result.residentID, displayName: result.displayName)
        residentState = result.residentState.map {
            AppResidentState(
                residentID: $0.residentID,
                sessionID: $0.sessionID,
                lifecycleStatus: $0.lifecycleStatus,
                presence: $0.presence,
                lastActivitySummary: $0.lastActivitySummary,
                lastUpdatedAt: ISO8601DateFormatter().string(from: $0.lastUpdatedAt),
                avatarMode: $0.avatarMode ?? ""
            )
        } ?? AppResidentState(residentID: result.residentID, sessionID: result.sessionID?.rawValue ?? "")
        diagnostics = result.diagnostics
        traceState = RuntimeTraceViewState(summary: result.diagnostics, entries: [])
        #if DEBUG
        refreshRelationshipProgressionDebugState()
        #endif
        refreshDebugPanelState()
        startupState = .loaded
        if shouldPresentFirstGreeting {
            particleSubtitleState = .hidden
        }
        residentSpeechSignal = .inactive
        let firstAppearance = orchestrationKernel.consumeFirstAppearance(
            for: result.residentID,
            userInitiated: shouldPresentFirstGreeting
        )
        if let firstAppearance {
            particleSubtitleState = ParticleSubtitleState(
                text: firstAppearance.greetingText,
                phase: .showing
            )
            refreshResidentVisualIntent(
                visualStateMode: firstAppearance.particleState == "calm" ? "idle" : nil
            )
        } else {
            refreshResidentVisualIntent()
        }
        refreshParticleDebugSnapshot()
    }

    func step(inputText: String) -> RuntimeStepResponse {
        let response = orchestrationKernel.step(residentID: loadedResidentID, inputText: inputText)
        runtimeState = response.cancellationState.isCancelled ? (response.cancellationState.reason == .interrupted ? .interrupted : .cancelled) : .running
        dialogueEntries.append(
            AppDialogueEntryState(
                id: "user-\(dialogueEntries.count)",
                role: "user",
                text: inputText,
                timestamp: ISO8601DateFormatter().string(from: response.residentState.lastUpdatedAt)
            )
        )
        dialogueEntries.append(
            AppDialogueEntryState(
                id: "resident-\(dialogueEntries.count)",
                role: "resident",
                text: response.outputText,
                timestamp: ISO8601DateFormatter().string(from: response.residentState.lastUpdatedAt)
            )
        )
        if dialogueEntries.count > 20 {
            dialogueEntries = Array(dialogueEntries.suffix(20))
        }
        residentState = AppResidentState(
            residentID: response.residentState.residentID,
            sessionID: response.residentState.sessionID,
            lifecycleStatus: response.residentState.lifecycleStatus,
            presence: response.residentState.presence,
            lastActivitySummary: response.residentState.lastActivitySummary,
            lastUpdatedAt: ISO8601DateFormatter().string(from: response.residentState.lastUpdatedAt),
            avatarMode: response.residentState.avatarMode ?? ""
        )
        avatarState = AppAvatarState(
            residentID: response.avatarState.residentID,
            displayName: response.avatarState.displayName,
            mode: response.avatarState.mode,
            presence: response.avatarState.presence,
            moodHint: response.avatarState.moodHint,
            activityHint: response.avatarState.activityHint,
            particleHint: response.avatarState.particleHint
        )
        sessionState = AppSessionState(
            residentID: response.residentState.residentID,
            sessionID: response.residentState.sessionID,
            lastUserInput: inputText,
            lastResidentOutput: response.outputText,
            lastActivity: response.residentState.lastActivitySummary,
            dialogueEntries: dialogueEntries
        )
        loadedSessionID = response.residentState.sessionID
        particleSubtitleState = response.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .hidden
            : ParticleSubtitleState(text: response.outputText, phase: .showing)
        startupState = .loaded
        traceState = RuntimeTraceViewState(
            summary: response.diagnostics.cancellationState,
            entries: response.traceEvents.enumerated().map {
                RuntimeTraceEntryViewState(id: "\($0.offset)", type: $0.element.type.rawValue, message: $0.element.message)
            }
        )
        refreshDebugPanelState()
        if response.visualState.mode.rawValue
            == ResidentVisualIntent.speaking.rawValue {
            presentResidentTextVisualState(.speaking)
        } else {
            residentSpeechSignal = .ended
            refreshResidentVisualIntent(
                visualStateMode: response.visualState.mode.rawValue
            )
        }
        refreshParticleDebugSnapshot()
        return response
    }

    func cancelCurrentStep() {
        orchestrationKernel.cancelCurrentStep()
        runtimeState = .cancelled
        residentSpeechSignal = .ended
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()
    }

    func interrupt() {
        orchestrationKernel.interrupt()
        runtimeState = .interrupted
        residentSpeechSignal = .ended
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()
    }

    func runtimeTick() {
        let response = orchestrationKernel.runtimeTick()
        clockState = RuntimeClockViewState(
            tickCount: response.clockState.tickCount,
            lastTickSummary: response.traceEvent.message
        )
        traceState = RuntimeTraceViewState(
            summary: response.diagnostics.cancellationState,
            entries: [
                RuntimeTraceEntryViewState(id: "tick-\(response.clockState.tickCount)", type: response.traceEvent.type.rawValue, message: response.traceEvent.message)
            ]
        )
        refreshDebugPanelState()
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()
    }

    func persistForNormalTerminationIfPossible() {
        guard !loadedResidentID.isEmpty, !loadedSessionID.isEmpty else { return }
        orchestrationKernel.saveCurrentSession(
            lastUserInput: sessionState.lastUserInput,
            lastResidentOutput: sessionState.lastResidentOutput,
            lastActivity: sessionState.lastActivity,
            avatarState: currentAvatarSnapshot(),
            dialogueEntries: dialogueEntries.compactMap {
                guard let timestamp = ISO8601DateFormatter().date(from: $0.timestamp) else { return nil }
                return RuntimeDialogueEntryState(role: $0.role, text: $0.text, timestamp: timestamp)
            }
        )
    }

    func markSessionUncleanIfPossible() {
        guard !loadedResidentID.isEmpty, !loadedSessionID.isEmpty else { return }
        orchestrationKernel.markSessionUnclean(
            lastUserInput: sessionState.lastUserInput,
            lastResidentOutput: sessionState.lastResidentOutput,
            lastActivity: sessionState.lastActivity,
            avatarState: currentAvatarSnapshot(),
            dialogueEntries: dialogueEntries.map {
                RuntimeDialogueEntryState(
                    role: $0.role,
                    text: $0.text,
                    timestamp: ISO8601DateFormatter().date(from: $0.timestamp) ?? Date()
                )
            }
        )
    }

    private func currentAvatarSnapshot() -> AvatarState {
        AvatarState(
            residentID: avatarState.residentID.isEmpty ? loadedResidentID : avatarState.residentID,
            displayName: avatarState.displayName,
            mode: avatarState.mode,
            presence: avatarState.presence,
            moodHint: avatarState.moodHint,
            activityHint: avatarState.activityHint,
            particleHint: avatarState.particleHint
        )
    }

    private func refreshDebugPanelState(shutdownState: String = "unknown", recoveryRequired: Bool = false, recoveredAt: String = "") {
        debugPanelState = DebugPanelViewState(
            residentID: residentState.residentID,
            sessionID: sessionState.sessionID.isEmpty ? loadedSessionID : sessionState.sessionID,
            lifecycleStatus: residentState.lifecycleStatus,
            presence: residentState.presence,
            avatarMode: avatarState.mode,
            lastActivitySummary: residentState.lastActivitySummary,
            traceSummary: traceState.summary,
            tickCount: clockState.tickCount,
            clockStatus: clockState.lastTickSummary.isEmpty ? "noop" : clockState.lastTickSummary,
            cancellationStatus: runtimeState == .idle ? "none" : String(describing: runtimeState),
            shutdownState: shutdownState,
            recoveryRequired: recoveryRequired,
            recoveredAt: recoveredAt
        )
    }

    private func refreshResidentVisualIntent(visualStateMode: String? = nil) {
        residentVisualIntent = AppResidentVisualIntentMapper.map(
            visualStateMode: visualStateMode,
            avatarState: avatarState,
            residentState: residentState,
            startupState: startupState,
            runtimeState: runtimeState
        )
    }

    private func refreshParticleDebugSnapshot() {
        let renderState = latestParticleRenderMetrics.currentVisualState
        let mappedState = String(describing: residentVisualIntent)
        let renderResolution = ParticleRenderResolution.resolve(requested: particleRenderKind)
        let shellResolution = ParticleShellResolution.resolve(current: particleShellMode)
        particleDebugSnapshot = ParticleDebugSnapshot(
            fps: latestParticleRenderMetrics.fps,
            particleCount: latestParticleRenderMetrics.particleCount,
            drawableSize: latestParticleRenderMetrics.drawableSize,
            preferredFramesPerSecond: latestParticleRenderMetrics.preferredFramesPerSecond,
            currentVisualState: renderState,
            targetVisualState: latestParticleRenderMetrics.targetVisualState,
            frameDeltaTime: latestParticleRenderMetrics.frameDeltaTime,
            stateElapsedTime: latestParticleRenderMetrics.stateElapsedTime,
            transitionDuration: latestParticleRenderMetrics.transitionDuration,
            transitionProgress: latestParticleRenderMetrics.transitionProgress,
            speechPhase: latestParticleRenderMetrics.speechPhase,
            speechIntensity: latestParticleRenderMetrics.speechIntensity,
            lastTransitionReason: latestParticleRenderMetrics.lastTransitionReason,
            currentShape: latestParticleRenderMetrics.currentShape,
            targetShape: latestParticleRenderMetrics.targetShape,
            morphElapsedTime: latestParticleRenderMetrics.morphElapsedTime,
            morphDuration: latestParticleRenderMetrics.morphDuration,
            morphProgress: latestParticleRenderMetrics.morphProgress,
            lastMorphReason: latestParticleRenderMetrics.lastMorphReason,
            sourceAvatarState: avatarStateSummary(),
            mappedParticleState: mappedState,
            isDebugOverrideActive: renderState != mappedState
                || latestParticleRenderMetrics.lastTransitionReason.hasPrefix("debug"),
            avatarMode: particleAvatarMode.rawValue,
            particleCoreModeStatus: particleAvatarMode.particleCoreStatus,
            abstractBustModeStatus: particleAvatarMode.abstractBustStatus,
            renderFallback: renderResolution.fallbackRenderer,
            renderFallbackReason: renderResolution.reason,
            requestedRenderKind: renderResolution.requestedMode,
            activeRenderer: renderResolution.activeRenderer,
            fallbackRenderer: renderResolution.fallbackRenderer,
            fallbackReason: renderResolution.reason,
            supportedRenderers: renderResolution.supportedRenderers,
            reservedRenderers: renderResolution.reservedRenderers,
            requestedShellMode: shellResolution.requestedMode,
            activeShellMode: shellResolution.activeMode,
            shellFallbackReason: shellResolution.fallbackReason,
            darkShellStatus: shellResolution.darkShellStatus,
            immersiveShellStatus: shellResolution.immersiveShellStatus,
            transparentShellStatus: shellResolution.transparentShellStatus,
            colorProfileSource: effectiveColorProfileSource,
            baseColor: colorString(
                red: effectiveParticleColorProfile.baseRed,
                green: effectiveParticleColorProfile.baseGreen,
                blue: effectiveParticleColorProfile.baseBlue
            ),
            ridgeColor: colorString(
                red: effectiveParticleColorProfile.ridgeRed,
                green: effectiveParticleColorProfile.ridgeGreen,
                blue: effectiveParticleColorProfile.ridgeBlue
            ),
            highlightColor: colorString(
                red: effectiveParticleColorProfile.highlightRed,
                green: effectiveParticleColorProfile.highlightGreen,
                blue: effectiveParticleColorProfile.highlightBlue
            ),
            fallbackUsed: effectiveColorProfileFallbackUsed,
            subtitlePhase: String(describing: particleSubtitleState.phase),
            hasSubtitleText: !particleSubtitleState.text.isEmpty,
            mouseInfluenceEnabled: latestParticleRenderMetrics.mouseInfluenceEnabled,
            mouseInsideParticleArea: latestParticleRenderMetrics.mouseInsideParticleArea,
            interactionStrength: latestParticleRenderMetrics.interactionStrength,
            runtimeCoreModified: false,
            runtimeAPIModified: false,
            drSchemaModified: false,
            providerTTSConnected: false
        )
    }

    private func avatarStateSummary() -> String {
        "mode=\(avatarState.mode) presence=\(avatarState.presence) mood=\(avatarState.moodHint) activity=\(avatarState.activityHint) particle=\(avatarState.particleHint)"
    }

    private func colorString(red: Double, green: Double, blue: Double) -> String {
        String(format: "%.2f, %.2f, %.2f", red, green, blue)
    }

    private func makeParticleExpressionInput(
        from expression: RuntimeExpressionResult,
        interactionID: UUID
    ) -> ParticleExpressionInput {
        ParticleExpressionInput(
            interactionID: interactionID,
            state: expression.expressionState.rawValue,
            intensity: expression.expressionIntensity,
            fallbackOccurred: expression.expressionFallbackOccurred,
            mappingSource: expression.mappingSource.rawValue,
            brightnessMultiplier:
                expression.expressionMapping.brightnessMultiplier,
            saturationMultiplier:
                expression.expressionMapping.saturationMultiplier,
            temperatureShift: expression.expressionMapping.temperatureShift,
            energyMultiplier: expression.expressionMapping.energyMultiplier,
            motionSpeedMultiplier:
                expression.expressionMapping.motionSpeedMultiplier,
            diffusionMultiplier:
                expression.expressionMapping.diffusionMultiplier
        )
    }

    private static func nanoseconds(_ duration: TimeInterval) -> UInt64 {
        UInt64(max(0, duration) * 1_000_000_000)
    }

    private func applyFailure(runtimeMessage: String, diagnosticsMessage: String) {
        if !loadedResidentID.isEmpty {
            runtimeStatus = runtimeMessage
            fixtureStatus = "DR fixture: not loaded"
            traceState = RuntimeTraceViewState(summary: diagnosticsMessage, entries: [])
            runtimeState = .idle
            diagnostics = diagnosticsMessage
            refreshDebugPanelState()
            startupState = .failed
            refreshResidentVisualIntent()
            refreshParticleDebugSnapshot()
            return
        }

        runtimeStatus = runtimeMessage
        fixtureStatus = "DR fixture: not loaded"
        loadedResidentID = ""
        loadedSessionID = ""
        particleExpressionInput = .neutral
        residentID = "resident_id: -"
        displayName = "display_name: -"
        sessionState = AppSessionState()
        dialogueEntries = []
        avatarState = AppAvatarState()
        particleColorProfile = .systemDefault
        particleDRColorPalette = []
        applyEffectiveParticleColorProfile()
        traceState = RuntimeTraceViewState(summary: diagnosticsMessage, entries: [])
        runtimeState = .idle
        diagnostics = diagnosticsMessage
        refreshDebugPanelState()
        startupState = .failed
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()
    }

    private func applyEffectiveParticleColorProfile() {
        switch particleColorSource {
        case .digitalResident:
            guard !particleDRColorPalette.isEmpty else {
                effectiveParticleColorProfile = .systemDefault
                effectiveColorProfileSource = "systemDefault (DR color unavailable)"
                effectiveColorProfileFallbackUsed = true
                return
            }
            effectiveParticleColorProfile = particleColorProfile
            effectiveColorProfileSource = "DR lattice_config.color_palette"
            effectiveColorProfileFallbackUsed = false
        case .systemDefault:
            effectiveParticleColorProfile = .systemDefault
            effectiveColorProfileSource = "systemDefault"
            effectiveColorProfileFallbackUsed = false
        }
    }

    private static func drColorPalette(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let lattice = object["lattice_config"] as? [String: Any],
            let palette = lattice["color_palette"] as? [String] else {
            return []
        }
        return palette.compactMap(normalizedHexColor)
    }

    private static func normalizedHexColor(_ value: String) -> String? {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, Int(raw, radix: 16) != nil else { return nil }
        return "#\(raw.uppercased())"
    }

    private func saveResidentBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: Self.residentBookmarkKey)
    }

    private func loadBookmarkedResident() -> (result: RuntimeLoadResult, data: Data)? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.residentBookmarkKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let drData = try? Data(contentsOf: url) else { return nil }
        let result = orchestrationKernel.loadResident(fixtureData: drData)
        guard result.isLoaded else { return nil }
        if isStale {
            saveResidentBookmark(for: url)
        }
        return (result, drData)
    }
}
