import Combine
import Foundation
#if DEBUG
import AppKit
import CryptoKit
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

nonisolated private enum ProductionQwenRealtimeBrainConfiguration {
    static let value = QwenRealtimeResidentBrainConfiguration(
        endpoint: URL(
            string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-plus-realtime"
        )!,
        keyRef: ProviderKeychainStore.qwenKeyRef,
        defaultProviderVoiceID: "Tina"
    )
}

#if DEBUG
nonisolated enum Stage75QwenRealtimeModel: String, CaseIterable, Sendable {
    case flash = "qwen3.5-omni-flash-realtime"
    case plus = "qwen3.5-omni-plus-realtime"
}

nonisolated private enum Stage75NativeSpeechConfiguration {
    static let profile = makeProfile(model: .flash)

    static func makeProfile(
        model: Stage75QwenRealtimeModel
    ) -> NativeSpeechProviderProfile {
        NativeSpeechProviderProfile(
            profileID: "stage7_5_qwen_realtime_development_beijing",
            providerID: "Qwen",
            capability: "native_speech",
            adapterID: "qwen_realtime",
            modelID: model.rawValue,
            voiceID: "Maia",
            endpoint: URL(
                string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=\(model.rawValue)"
            )!,
            transport: "websocket",
            inputAudioFormat: .pcm16,
            outputAudioFormat: .pcm16,
            turnDetection: NativeSpeechTurnDetection(
                type: .semanticVAD,
                prefixPaddingMilliseconds: 500
            ),
            languageMetadata: "zh-CN",
            keyRef: ProviderKeychainStore.qwenKeyRef
        )
    }
}

nonisolated private enum Stage7511QwenASRConfiguration {
    static let value = QwenRealtimeASRConfiguration(
        endpoint: URL(
            string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3-asr-flash-realtime"
        )!,
        modelID: "qwen3-asr-flash-realtime",
        keyRef: ProviderKeychainStore.qwenKeyRef
    )
}

nonisolated private enum Stage7511QwenTTSConfiguration {
    static let value = QwenRealtimeTTSConfiguration(
        endpoint: URL(
            string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3-tts-instruct-flash-realtime"
        )!,
        modelID: "qwen3-tts-instruct-flash-realtime",
        keyRef: ProviderKeychainStore.qwenKeyRef,
        voiceBindings: ["resident-default": "Cherry"]
    )
}

nonisolated struct RealtimeSpeechPlaybackSubtitleIdentity:
    Sendable,
    Equatable {
    let interactionID: NativeSpeechInteractionID
    let turnNumber: UInt64
    let turnGeneration: UInt64
    let playbackGeneration: UInt64
}

private struct NativeSpeechPlaybackBinding: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let turnNumber: UInt64
    let turnGeneration: UInt64
    let playbackGeneration: UInt64

    var subtitleIdentity: RealtimeSpeechPlaybackSubtitleIdentity {
        RealtimeSpeechPlaybackSubtitleIdentity(
            interactionID: interactionID,
            turnNumber: turnNumber,
            turnGeneration: turnGeneration,
            playbackGeneration: playbackGeneration
        )
    }
}

private struct NativeSpeechDialogueHistoryIdentity: Hashable {
    let interactionID: NativeSpeechInteractionID
    let turnNumber: UInt64
    let turnGeneration: UInt64
}

nonisolated struct RealtimeSpeechPlaybackSubtitleSynchronizer: Sendable {
    private struct CompletedPlayback: Sendable {
        let interactionShortID: String
        let turnNumber: UInt64
        let turnGeneration: UInt64
        let text: String

        func matches(
            _ canonical: RealtimeSpeechCompletedSubtitle?
        ) -> Bool {
            guard let canonical else { return false }
            return interactionShortID == canonical.interactionShortID
                && turnNumber == canonical.turnNumber
                && turnGeneration == canonical.turnGeneration
                && text == canonical.residentFinal
        }
    }

    private(set) var displayText: String?
    private var activeIdentity: RealtimeSpeechPlaybackSubtitleIdentity?
    private var pendingFinalText: String?
    private var lastPlayedAudioSequence: UInt64?
    private var lastCompletedPlayback: CompletedPlayback?
    private var playbackCompleted = false

    var hasPendingText: Bool {
        pendingFinalText != nil
    }

    var playedAudioSequence: UInt64? {
        lastPlayedAudioSequence
    }

    mutating func reset() {
        displayText = nil
        activeIdentity = nil
        pendingFinalText = nil
        lastPlayedAudioSequence = nil
        playbackCompleted = false
    }

    mutating func resetForInteraction() {
        reset()
        lastCompletedPlayback = nil
    }

    mutating func resetForTerminal(
        canonicalCompleted: RealtimeSpeechCompletedSubtitle?
    ) {
        let completedPlayback = lastCompletedPlayback
        reset()
        if completedPlayback?.matches(canonicalCompleted) == true {
            displayText = completedPlayback?.text
        }
    }

    mutating func prepare(
        identity: RealtimeSpeechPlaybackSubtitleIdentity
    ) {
        guard activeIdentity != identity else { return }
        displayText = nil
        pendingFinalText = nil
        lastPlayedAudioSequence = nil
        playbackCompleted = false
        activeIdentity = identity
    }

    @discardableResult
    mutating func applyPartial(
        text: String,
        requiredAudioSequence: UInt64,
        identity: RealtimeSpeechPlaybackSubtitleIdentity
    ) -> Bool {
        let normalized = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty,
              activeIdentity == identity,
              !playbackCompleted,
              let lastPlayedAudioSequence,
              requiredAudioSequence <= lastPlayedAudioSequence else {
            return false
        }
        displayText = normalized
        return true
    }

    @discardableResult
    mutating func enqueueFinal(
        text: String,
        identity: RealtimeSpeechPlaybackSubtitleIdentity
    ) -> Bool {
        let normalized = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty,
              activeIdentity == identity else { return false }
        if playbackCompleted {
            displayText = normalized
            lastCompletedPlayback = CompletedPlayback(
                interactionShortID: String(
                    identity.interactionID.rawValue.uuidString.prefix(8)
                ),
                turnNumber: identity.turnNumber,
                turnGeneration: identity.turnGeneration,
                text: normalized
            )
            pendingFinalText = nil
        } else {
            pendingFinalText = normalized
        }
        return true
    }

    mutating func advance(
        playedSequence: UInt64,
        identity: RealtimeSpeechPlaybackSubtitleIdentity
    ) {
        guard activeIdentity == identity else { return }
        if let lastPlayedAudioSequence {
            self.lastPlayedAudioSequence = max(
                lastPlayedAudioSequence,
                playedSequence
            )
        } else {
            lastPlayedAudioSequence = playedSequence
        }
    }

    mutating func completePlayback(
        identity: RealtimeSpeechPlaybackSubtitleIdentity
    ) {
        guard activeIdentity == identity else { return }
        playbackCompleted = true
        if let pendingFinalText {
            displayText = pendingFinalText
            lastCompletedPlayback = CompletedPlayback(
                interactionShortID: String(
                    identity.interactionID.rawValue.uuidString.prefix(8)
                ),
                turnNumber: identity.turnNumber,
                turnGeneration: identity.turnGeneration,
                text: pendingFinalText
            )
            self.pendingFinalText = nil
        }
    }

    mutating func noteUnplayedResponse() {
        pendingFinalText = nil
        displayText = nil
        activeIdentity = nil
        lastPlayedAudioSequence = nil
        playbackCompleted = false
    }
}

private struct RealtimeSpeechSubtitleProjection: Equatable {
    let interactionShortID: String?
    let turnNumber: UInt64
    let turnGeneration: UInt64
    let text: String?
}

nonisolated struct NativeSpeechPlaybackDebugSnapshot: Sendable, Equatable {
    let turnNumber: UInt64?
    let playbackGeneration: UInt64?
    let interruptClearCount: UInt64
    let stopClearCount: UInt64
    let rejectedEventCount: UInt64

    static let initial = NativeSpeechPlaybackDebugSnapshot(
        turnNumber: nil,
        playbackGeneration: nil,
        interruptClearCount: 0,
        stopClearCount: 0,
        rejectedEventCount: 0
    )
}
#endif

nonisolated struct RealtimeBrainSubtitlePresentation: Sendable, Equatable {
    private static let retiredIdentityCapacity = 64

    private(set) var identity: RealtimeBrainEventIdentity?
    private(set) var text = ""
    private var isFinal = false
    private var retiredIdentities: Set<RealtimeBrainEventIdentity> = []
    private var retiredIdentityOrder: [RealtimeBrainEventIdentity] = []

    var displayText: String? {
        let normalized = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized.isEmpty ? nil : normalized
    }

    mutating func reset() {
        retiredIdentities.removeAll(keepingCapacity: true)
        retiredIdentityOrder.removeAll(keepingCapacity: true)
        clearCurrent()
    }

    mutating func retire(
        _ eventIdentity: RealtimeBrainEventIdentity? = nil
    ) {
        if let retiredIdentity = eventIdentity ?? identity,
           retiredIdentities.insert(retiredIdentity).inserted {
            retiredIdentityOrder.append(retiredIdentity)
            if retiredIdentityOrder.count > Self.retiredIdentityCapacity {
                retiredIdentities.remove(retiredIdentityOrder.removeFirst())
            }
        }
        clearCurrent()
    }

    private mutating func clearCurrent() {
        identity = nil
        text = ""
        isFinal = false
    }

    @discardableResult
    mutating func consume(_ event: RealtimeResidentBrainEvent) -> Bool {
        guard event.identity.turnID != nil,
              event.identity.responseID != nil,
              !retiredIdentities.contains(event.identity) else {
            return false
        }
        if let identity {
            guard identity == event.identity else { return false }
        } else {
            identity = event.identity
        }

        let previous = displayText
        switch event.kind {
        case .residentTextDelta(let delta):
            guard !isFinal else { return false }
            text.append(delta)
        case .residentTextFinal(let final):
            text = final
            isFinal = true
        case .residentSemanticFinal(let semantic):
            text = semantic.canonicalText
            isFinal = true
        default:
            return false
        }
        return displayText != previous
    }
}

enum ParticleColorSource: String, CaseIterable, Identifiable {
    case digitalResident
    case systemDefault

    var id: String { rawValue }
}

@MainActor
final class AppController: ObservableObject {
    private static let residentBookmarkKey = "aftelle.activeResidentBookmark.v1"
    private static let realtimeBrainMissingSpeechStopPresentationDelay:
        Duration = .milliseconds(1_100)

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
    @Published private(set) var realtimeFullDuplexSpeechStatus =
        RealtimeFullDuplexSpeechStatus.idle
    #if DEBUG
    @Published private(set) var speechAudioHostSnapshot =
        MacSpeechAudioHostSnapshot.initial
    @Published private(set) var realtimeBrainInputBridgeSnapshot =
        MacSpeechRealtimeBrainInputBridgeSnapshot.initial
    @Published private(set) var realtimeBrainOutputBridgeSnapshot =
        MacSpeechRealtimeBrainOutputBridgeSnapshot.initial
    @Published private(set) var speechAudioOutputHostSnapshot =
        MacSpeechAudioOutputHostSnapshot.initial
    #else
    private var speechAudioHostSnapshot = MacSpeechAudioHostSnapshot.initial
    private var realtimeBrainInputBridgeSnapshot =
        MacSpeechRealtimeBrainInputBridgeSnapshot.initial
    private var realtimeBrainOutputBridgeSnapshot =
        MacSpeechRealtimeBrainOutputBridgeSnapshot.initial
    private var speechAudioOutputHostSnapshot =
        MacSpeechAudioOutputHostSnapshot.initial
    #endif
    #if DEBUG
    @Published private(set) var nativeSpeechProviderDebugState =
        NativeSpeechProviderDebugViewState(
            profile: Stage75NativeSpeechConfiguration.profile
        )
    @Published private(set) var speechInputBridgeSnapshot =
        MacSpeechNativeInputBridgeSnapshot.initial
    @Published private(set) var speechOutputBridgeSnapshot =
        MacSpeechNativeOutputBridgeSnapshot.initial
    @Published private(set) var nativeSpeechPlaybackDebugSnapshot =
        NativeSpeechPlaybackDebugSnapshot.initial
    @Published private(set) var realtimeSpeechStateSnapshot =
        RealtimeSpeechStateSnapshot.initial
    @Published private(set) var realtimeSpeechSubtitleSnapshot =
        RealtimeSpeechSubtitleSnapshot.initial
    private(set) var realtimeSpeechDiagnosticTimeline =
        RealtimeSpeechDiagnosticTimeline()
    @Published private(set) var realtimeSpeechDiagnosticViewState =
        RealtimeSpeechDiagnosticViewState.initial
    @Published private(set) var realtimeSpeechDiagnosticStatusKey: String?
    @Published private(set) var formalSpeechRouteDebugSnapshot =
        FormalSpeechRouteDebugSnapshot.idle
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
    private let speechAudioHost: MacSpeechAudioHost
    private let speechAudioOutputHost: MacSpeechAudioOutputHost
    private var speechHostLifecycleOperationCount = 0
    private var speechAudioHostShutdownOperation:
        (id: UUID, task: Task<Void, Never>)?
    private var speechAudioHostShutdownCompleted = false
    private var realtimeBrainInputBinding:
        MacSpeechRealtimeBrainInputBinding?
    private var realtimeBrainPlaybackResponseID: RealtimeBrainResponseID?
    private var realtimeBrainPlaybackEventIdentity:
        RealtimeBrainEventIdentity?
    private var realtimeBrainPlaybackProviderFinishedResponseID:
        RealtimeBrainResponseID?
    private var realtimeBrainPlaybackGeneration: UInt64?
    private var realtimeBrainPlaybackDrainWaiter:
        CheckedContinuation<Bool, Never>?
    private var realtimeBrainRouteAttemptID: UUID?
    private var realtimeBrainPreparedCaptureGeneration: UInt64?
    private var realtimeBrainStartInFlight = false
    private var realtimeBrainGenerationTransitionID: UUID?
    private var realtimeBrainGenerationTransitionTask: Task<
        Result<RealtimeBrainSessionIdentity, RealtimeResidentBrainError>,
        Never
    >?
    private var realtimeBrainStopping = false
    private var realtimePassiveBackchannelPresentation:
        RealtimePassiveBackchannelPresentation?
    private var realtimeBrainLatestSpeechStopIdentity:
        RealtimeBrainEventIdentity?
    private var realtimeBrainMissingSpeechStopPresentationIdentity:
        RealtimeBrainEventIdentity?
    private var realtimeBrainMissingSpeechStopPresentationTask:
        Task<Void, Never>?
    private var realtimeBrainSubtitlePresentation =
        RealtimeBrainSubtitlePresentation()
    private var realtimeBrainAcousticDiagnosticRecorder:
        MacSpeechRealtimeBrainInputBridge.RecordAcousticDiagnostic? {
        #if DEBUG
        return { [weak self] diagnostic in
            let packetTrace = diagnostic.packetTrace.map {
                RealtimeSpeechAcousticPacketTrace(
                    packetSequence: $0.packetSequence,
                    captureFrameIndex: $0.captureFrameIndex,
                    observationSequence: $0.observationSequence,
                    observationTimestampNanoseconds:
                        $0.observationTimestampNanoseconds,
                    playbackSequence: $0.playbackSequence,
                    sourceGateEpoch: $0.sourceGateEpoch,
                    sourceAssessment: $0.sourceAssessment,
                    classification: $0.classification,
                    captureTimestampNanoseconds:
                        $0.captureTimestampNanoseconds,
                    lastAudibleRenderTimestampNanoseconds:
                        $0.lastAudibleRenderTimestampNanoseconds,
                    gateLastSequence: $0.gateLastSequence,
                    gateLastTimestampNanoseconds:
                        $0.gateLastTimestampNanoseconds,
                    gateLastPlaybackSequence:
                        $0.gateLastPlaybackSequence,
                    gateLastAudibleRenderTimestampNanoseconds:
                        $0.gateLastAudibleRenderTimestampNanoseconds
                )
            }
            self?.recordRealtimeSpeechDiagnostic(
                source: .inputBridge,
                category: diagnostic.category,
                routeKind: .realtimeBrain,
                turnGeneration: diagnostic.turnGeneration,
                disposition: diagnostic.disposition,
                wireSequence: packetTrace?.observationSequence,
                audioSequence: packetTrace?.packetSequence
                    ?? diagnostic.observationSequence,
                sourceGateEpoch: diagnostic.sourceGateEpoch,
                acousticPacketTrace: packetTrace,
                nowNanoseconds: diagnostic.timestampNanoseconds
            )
        }
        #else
        return nil
        #endif
    }
    private lazy var realtimeBrainInputBridge = MacSpeechRealtimeBrainInputBridge(
        source: speechAudioHost,
        sendFrameWithActivity: { [orchestrationKernel] frame, activity in
            await orchestrationKernel.sendRealtimeResidentBrainAudio(
                frame,
                activity: activity.localActivity
            )
        },
        confirmAcceptedLocalActivity: {
            [orchestrationKernel] frame, activity in
            await orchestrationKernel
                .confirmRealtimeResidentBrainAcceptedLocalAudioActivity(
                    frame: frame,
                    activity: activity.localActivity
                )
        },
        stopInput: { [orchestrationKernel] binding in
            await orchestrationKernel.stopRealtimeResidentBrainInput(
                session: binding.session
            )
        },
        observeResidentAcoustics: { [weak self] observation in
            await self?.observeRealtimeResidentBrainAcoustics(observation)
                ?? .ignored(.staleIdentity)
        },
        consumeAcousticObservation: { [weak self] observation in
            await self?.consumeRealtimeResidentBrainAcousticObservation(
                observation
            )
        },
        recordAcousticDiagnostic: realtimeBrainAcousticDiagnosticRecorder
    )
    private lazy var realtimeBrainOutputBridge =
        MacSpeechRealtimeBrainOutputBridge(
            receiveEvent: { [orchestrationKernel] session in
                await orchestrationKernel.receiveRealtimeResidentBrainEvent(
                    session: session
                )
            },
            consumeEvent: { [weak self] event in
                await self?.consumeRealtimeResidentBrainEvent(event)
            },
            sessionEnded: { [weak self] session, error in
                await self?.realtimeResidentBrainSessionEnded(
                    session: session,
                    error: error
                )
            }
        )
    #if DEBUG
    private let nativeSpeechDiagnosticBuffer: NativeSpeechDiagnosticBuffer
    private let realtimeSpeechDiagnosticAudioEngine:
        SystemMacSpeechVoiceProcessingEngine?
    private let speechOutputDebugSink = MacSpeechNativeDebugOutputSink()
    private var nativeSpeechPlaybackBinding: NativeSpeechPlaybackBinding?
    private var formalSpeechRouteGeneration: UInt64?
    private var formalSpeechCaptureGeneration: UInt64?
    private var formalSpeechPlaybackGeneration: UInt64?
    private var formalSpeechInteractionID: UUID?
    private var formalSpeechUserFinal: String?
    private var formalSpeechCanonicalResponse: String?
    private var formalSpeechInputTask: Task<Void, Never>?
    private var formalSpeechRouteTask: Task<Void, Never>?
    private var formalSpeechPlaybackCommitted = false
    private var formalSpeechASRAcceptsAudio = false
    private var formalSpeechFailingGeneration: UInt64?
    private var formalSpeechObservedSourceGateOpenCount: UInt64 = 0
    private var formalSpeechInterruptingGeneration: UInt64?
    private var projectedNativeSpeechDialogueHistoryIdentities:
        Set<NativeSpeechDialogueHistoryIdentity> = []
    private var realtimeSpeechPlaybackSubtitleSynchronizer =
        RealtimeSpeechPlaybackSubtitleSynchronizer()
    private var lastRealtimeSpeechSubtitleProjection:
        RealtimeSpeechSubtitleProjection?
    private var lastPlaybackEventOrdinal: UInt64 = 0
    private var playbackInterruptClearCount: UInt64 = 0
    private var playbackStopClearCount: UInt64 = 0
    private var rejectedPlaybackEventCount: UInt64 = 0
    private var lastDiagnosticAggregateNanoseconds: UInt64 = 0
    private var lastDiagnosticInputForwardedCount: UInt64 = 0
    private var lastDiagnosticInputRejectedCount: UInt64 = 0
    private var lastDiagnosticCaptureGeneratedCount: UInt64 = 0
    private var lastDiagnosticCaptureDroppedCount: UInt64 = 0
    private var lastDiagnosticPCMEndSample: Int16?
    private var realtimeBrainRecoverableResponseErrorCount: UInt64 = 0
    private var lastRealtimeBrainRecoverableResponseErrorCode: String?
    private var realtimeSpeechDiagnosticViewRefreshTask: Task<Void, Never>?
    private var realtimeSpeechAudioCaptureTask: Task<Void, Never>?
    private var realtimeSpeechReplayCaptureAttemptID: UUID?
    private lazy var speechInputBridge = MacSpeechNativeInputBridge(
        source: speechAudioHost,
        sendFrame: { [orchestrationKernel] payload, context in
            return await orchestrationKernel.sendNativeSpeechInput(
                payload,
                context: context
            )
        },
        stopInput: { [weak self] binding, reason in
            guard let self else { return .success(()) }
            return await orchestrationKernel.stopNativeSpeechInput(
                binding: binding,
                reason: reason
            )
        }
    )
    private lazy var speechOutputBridge = MacSpeechNativeOutputBridge(
        receiveEvent: { [orchestrationKernel] interactionID in
            await orchestrationKernel.receiveNativeSpeechEvent(
                interactionID: interactionID
            )
        },
        consumeEvent: { [weak self] event in
            await self?.consumeNativeSpeechOutputEvent(event)
        },
        residentSubtitleCheckpointReady: { [weak self] in
            await self?.consumeResidentSubtitleCheckpointReady()
        },
        clearOutputForSpeechStart: { [speechAudioOutputHost] in
            _ = await speechAudioOutputHost
                .clearForAcceptedSpeechStart()
        },
        endInputPump: { [weak self] in
            guard let self else { return }
            _ = await speechInputBridge.stop()
        },
        stopInput: { [weak self] binding, reason in
            guard let self else { return .success(()) }
            return await orchestrationKernel.stopNativeSpeechInput(
                binding: binding,
                reason: reason
            )
        },
        closeInput: { [orchestrationKernel] binding in
            await orchestrationKernel.closeNativeSpeechInput(
                binding: binding
            )
        }
    )
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
        let speechAudioEngine = SystemMacSpeechVoiceProcessingEngine()
        speechAudioHost = MacSpeechAudioHost(
            capture: SystemMacSpeechAudioCapture(
                audioEngine: speechAudioEngine
            )
        )
        speechAudioOutputHost = MacSpeechAudioOutputHost(
            player: SystemMacSpeechAudioOutputPlayer(
                audioEngine: speechAudioEngine
            )
        )
        #if DEBUG
        let speechDiagnosticBuffer = NativeSpeechDiagnosticBuffer()
        nativeSpeechDiagnosticBuffer = speechDiagnosticBuffer
        realtimeSpeechDiagnosticAudioEngine = speechAudioEngine
        runtimeCore = QwenRealtimeRuntimeComposition.makeDebugRuntimeCore(
            credentialReader: credentialStore,
            diagnosticBuffer: speechDiagnosticBuffer,
            realtimeBrainConfiguration:
                ProductionQwenRealtimeBrainConfiguration.value,
            asrConfiguration: Stage7511QwenASRConfiguration.value,
            ttsConfiguration: Stage7511QwenTTSConfiguration.value
        )
        #else
        runtimeCore = QwenRealtimeRuntimeComposition.makeRuntimeCore(
            credentialReader: credentialStore,
            realtimeBrainConfiguration:
                ProductionQwenRealtimeBrainConfiguration.value
        )
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
        let speechAudioEngine = SystemMacSpeechVoiceProcessingEngine()
        speechAudioHost = MacSpeechAudioHost(
            capture: SystemMacSpeechAudioCapture(
                audioEngine: speechAudioEngine
            )
        )
        speechAudioOutputHost = MacSpeechAudioOutputHost(
            player: SystemMacSpeechAudioOutputPlayer(
                audioEngine: speechAudioEngine
            )
        )
        #if DEBUG
        nativeSpeechDiagnosticBuffer = NativeSpeechDiagnosticBuffer()
        realtimeSpeechDiagnosticAudioEngine = speechAudioEngine
        #endif
        restoreProviderConfiguration()
        #if DEBUG
        refreshNativeSpeechProviderDebugState()
        #endif
    }

    #if DEBUG
    init(
        orchestrationKernel: OrchestrationKernel,
        speechAudioHost: MacSpeechAudioHost,
        speechAudioOutputHost: MacSpeechAudioOutputHost =
            MacSpeechAudioOutputHost(),
        nativeSpeechProfile: NativeSpeechProviderProfile =
            Stage75NativeSpeechConfiguration.profile,
        nativeSpeechDiagnosticBuffer: NativeSpeechDiagnosticBuffer =
            NativeSpeechDiagnosticBuffer(),
        realtimeSpeechDiagnosticAudioEngine:
            SystemMacSpeechVoiceProcessingEngine? = nil
    ) {
        self.orchestrationKernel = orchestrationKernel
        providerKeychainStore = ProviderKeychainStore()
        self.speechAudioHost = speechAudioHost
        self.speechAudioOutputHost = speechAudioOutputHost
        self.nativeSpeechDiagnosticBuffer = nativeSpeechDiagnosticBuffer
        self.realtimeSpeechDiagnosticAudioEngine =
            realtimeSpeechDiagnosticAudioEngine
        nativeSpeechProviderDebugState = NativeSpeechProviderDebugViewState(
            profile: nativeSpeechProfile
        )
        restoreProviderConfiguration()
        refreshNativeSpeechProviderDebugState()
    }
    #endif

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

    var canStartRealtimeFullDuplexSpeech: Bool {
        isResidentTextInputAvailable
            && realtimeBrainInputBinding == nil
            && realtimeBrainRouteAttemptID == nil
            && !realtimeBrainStartInFlight
            && !realtimeBrainStopping
            && !hasActiveAlternateSpeechRoute
            && speechAudioHostShutdownOperation == nil
            && speechHostLifecycleOperationCount == 0
    }

    var canStopRealtimeFullDuplexSpeech: Bool {
        !realtimeBrainStopping
            && (realtimeBrainInputBinding != nil
                || realtimeBrainRouteAttemptID != nil
                || realtimeBrainPreparedCaptureGeneration != nil)
    }

    private var hasActiveAlternateSpeechRoute: Bool {
        #if DEBUG
        formalSpeechRouteGeneration != nil
            || speechInputBridgeSnapshot.hasActivePump
            || speechOutputBridgeSnapshot.hasActiveReceiveLoop
        #else
        false
        #endif
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

    func exportRealtimeSpeechDiagnostics() {
        let exportedAt = Date()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = String(
            localized: "particleDebug.realtimeDiagnostics.chooseLocation"
        )

        panel.begin { [weak self] response in
            guard response == .OK,
                  let directoryURL = panel.url,
                  let self else { return }
            let url = directoryURL.appendingPathComponent(
                self.realtimeSpeechDiagnosticFileName(exportedAt: exportedAt)
            )
            do {
                try self.writeRealtimeSpeechDiagnostics(
                    to: url,
                    exportedAt: exportedAt
                )
                self.realtimeSpeechDiagnosticStatusKey =
                    "particleDebug.realtimeDiagnostics.status.exported"
            } catch {
                self.realtimeSpeechDiagnosticStatusKey =
                    "particleDebug.realtimeDiagnostics.status.exportFailed"
            }
        }
    }

    func armRealtimeSpeechAudioCapsule() {
        guard let routeAttemptID = realtimeBrainRouteAttemptID,
              let binding = realtimeBrainInputBinding,
              isCurrentRealtimeBrainRoute(
                attemptID: routeAttemptID,
                session: binding.session
              ) else {
            realtimeSpeechDiagnosticStatusKey =
                "particleDebug.realtimeDiagnostics.status.audioUnavailable"
            return
        }
        let attemptID = UUID()
        guard nativeSpeechDiagnosticBuffer.armRealtimeAudioCapsule(
            attemptID: attemptID,
            routeAttemptID: routeAttemptID,
            session: binding.session
        ) else {
            realtimeSpeechDiagnosticStatusKey =
                "particleDebug.realtimeDiagnostics.status.audioAlreadyArmed"
            return
        }
        guard realtimeSpeechDiagnosticAudioEngine?.armAcousticReplayCapture(
            attemptID: attemptID
        ) == true else {
            nativeSpeechDiagnosticBuffer.clearRealtimeAudioCapsule(
                matchingAttemptID: attemptID
            )
            realtimeSpeechDiagnosticStatusKey =
                "particleDebug.realtimeDiagnostics.status.audioUnavailable"
            return
        }
        realtimeSpeechReplayCaptureAttemptID = attemptID
        realtimeSpeechAudioCaptureTask?.cancel()
        realtimeSpeechAudioCaptureTask = Task { @MainActor [weak self] in
            let maximumWaitingForPlaybackPollCount = 600
            let maximumRecordingPollCount = 300
            var waitingForPlaybackPollCount = 0
            var recordingPollCount = 0
            var sawPlaybackStart = false
            while waitingForPlaybackPollCount
                    < maximumWaitingForPlaybackPollCount,
                  recordingPollCount < maximumRecordingPollCount {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
                guard let self,
                      let snapshot = self.realtimeSpeechDiagnosticAudioEngine?
                        .acousticReplayCaptureSnapshot(),
                      snapshot.attemptID == attemptID else { return }
                sawPlaybackStart = sawPlaybackStart
                    || snapshot.controlEvents.contains(where: {
                        $0.kind == .playbackStarted
                    })
                if sawPlaybackStart {
                    recordingPollCount += 1
                } else {
                    waitingForPlaybackPollCount += 1
                }
                guard snapshot.isSealed else { continue }
                let auxiliaryCapsuleSealed = self
                    .sealRealtimeAudioCapsule(matchingAttemptID: attemptID)
                let exactReplayReady = snapshot.isExactReplayReady
                    && auxiliaryCapsuleSealed
                self.recordRealtimeSpeechDiagnostic(
                    source: .lifecycle,
                    category: "acoustic_replay_capture_sealed",
                    routeKind: .realtimeBrain,
                    interactionShortID:
                        String(attemptID.uuidString.prefix(8)),
                    disposition: exactReplayReady
                        ? "ready_to_export" : "invalid_capture"
                )
                self.realtimeSpeechDiagnosticStatusKey =
                    exactReplayReady
                    ? "particleDebug.realtimeDiagnostics.status.audioCaptured"
                    : "particleDebug.realtimeDiagnostics.status.audioInvalid"
                self.realtimeSpeechAudioCaptureTask = nil
                return
            }
            guard let self else { return }
            self.realtimeSpeechDiagnosticAudioEngine?
                .sealAcousticReplayCapture(
                    reason: .timeout,
                    matchingAttemptID: attemptID
                )
            _ = self.sealRealtimeAudioCapsule(
                matchingAttemptID: attemptID
            )
            self.realtimeSpeechDiagnosticStatusKey =
                "particleDebug.realtimeDiagnostics.status.audioInvalid"
            self.realtimeSpeechAudioCaptureTask = nil
        }
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "acoustic_replay_capture_armed",
            routeKind: .realtimeBrain,
            interactionShortID: String(attemptID.uuidString.prefix(8)),
            disposition: "armed_before_next_playback"
        )
        realtimeSpeechDiagnosticStatusKey =
            "particleDebug.realtimeDiagnostics.status.audioArmed"
    }

    func clearRealtimeSpeechDiagnostics() {
        realtimeSpeechAudioCaptureTask?.cancel()
        realtimeSpeechAudioCaptureTask = nil
        realtimeSpeechDiagnosticViewRefreshTask?.cancel()
        realtimeSpeechDiagnosticViewRefreshTask = nil
        realtimeSpeechDiagnosticTimeline.clear()
        nativeSpeechDiagnosticBuffer.clear()
        realtimeSpeechDiagnosticAudioEngine?.clearAcousticReplayCapture()
        realtimeSpeechReplayCaptureAttemptID = nil
        speechAudioHost.resetAcousticEchoDiagnostics()
        publishRealtimeSpeechDiagnosticViewState()
        realtimeSpeechDiagnosticStatusKey = nil
        lastDiagnosticAggregateNanoseconds = 0
        lastDiagnosticInputForwardedCount = 0
        lastDiagnosticInputRejectedCount = 0
        lastDiagnosticCaptureGeneratedCount = 0
        lastDiagnosticCaptureDroppedCount = 0
        lastDiagnosticPCMEndSample = nil
    }

    func realtimeSpeechDiagnosticExportData(
        exportedAt: Date = Date(),
        audioCapsuleFileName: String? = nil,
        audioCapsuleSHA256: String? = nil
    ) throws -> Data {
        drainNativeSpeechInternalDiagnostics()
        let bundle = Bundle.main
        let qwenRealtime = qwenRealtimeDiagnosticExport()
        let qwenInputAudioCapsule = nativeSpeechDiagnosticBuffer
            .realtimeAudioCapsuleSnapshot()
        let buildBinary = Self.runningBuildBinary()
        let turnCompletion = orchestrationKernel
            .realtimeUtteranceCompletionDebugSnapshot()
        let export = RealtimeSpeechDiagnosticExport(
            schemaVersion: 11,
            exportedAt: exportedAt,
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "-",
            appBuild: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "-",
            buildBinaryName: buildBinary.name,
            buildBinarySHA256: buildBinary.sha256,
            routeKind: NativeSpeechDiagnosticRouteKind.realtimeBrain.rawValue,
            formalRoute: RealtimeSpeechFormalRouteDiagnosticExport(
                state: realtimeFullDuplexSpeechStatus.phase.rawValue,
                generation: realtimeBrainInputBinding?.session.generation,
                lastTerminalError:
                    realtimeFullDuplexSpeechStatus.lastErrorCode,
                recoverableResponseErrorCount:
                    realtimeBrainRecoverableResponseErrorCount,
                lastRecoverableResponseError:
                    lastRealtimeBrainRecoverableResponseErrorCode
            ),
            captureAEC: RealtimeSpeechCaptureDiagnosticExport(
                authorization: speechAudioHostSnapshot.authorization.rawValue,
                state: speechAudioHostSnapshot.state.rawValue,
                isCapturing: speechAudioHostSnapshot.isCapturing,
                inputDeviceID:
                    speechAudioHostSnapshot.inputDevice.identifier,
                inputDeviceName: speechAudioHostSnapshot.inputDevice.name,
                outputDeviceID:
                    speechAudioHostSnapshot.outputDevice.identifier,
                outputDeviceName: speechAudioHostSnapshot.outputDevice.name,
                actualSampleRate: speechAudioHostSnapshot.actualSampleRate,
                actualChannelCount:
                    speechAudioHostSnapshot.actualChannelCount,
                normalizedOutputFormat:
                    speechAudioHostSnapshot.normalizedOutputFormat,
                generatedFrameCount:
                    speechAudioHostSnapshot.generatedFrameCount,
                droppedFrameCount:
                    speechAudioHostSnapshot.droppedFrameCount,
                rejectedStaleFrameCount:
                    speechAudioHostSnapshot.rejectedStaleFrameCount,
                queuedFrameCount: speechAudioHostSnapshot.queuedFrameCount,
                lastError: speechAudioHostSnapshot.lastError,
                acousticEcho: realtimeSpeechAcousticEchoDiagnosticExport()
            ),
            realtimeBrainInput: RealtimeBrainInputDiagnosticExport(
                state: realtimeBrainInputBridgeSnapshot.state.rawValue,
                sessionShortID:
                    realtimeBrainInputBridgeSnapshot.sessionShortID,
                forwardedFrameCount:
                    realtimeBrainInputBridgeSnapshot.forwardedFrameCount,
                runtimeRejectedFrameCount:
                    realtimeBrainInputBridgeSnapshot.runtimeRejectedFrameCount,
                sendOperationCount:
                    realtimeBrainInputBridgeSnapshot.sendOperationCount,
                noneActivityFrameCount:
                    realtimeBrainInputBridgeSnapshot.noneActivityFrameCount,
                listeningNearEndFrameCount:
                    realtimeBrainInputBridgeSnapshot
                        .listeningNearEndFrameCount,
                sourceGatedNearEndFrameCount:
                    realtimeBrainInputBridgeSnapshot
                        .sourceGatedNearEndFrameCount,
                listeningConfirmationAttemptCount:
                    realtimeBrainInputBridgeSnapshot
                        .listeningConfirmationAttemptCount,
                listeningConfirmationAcceptedCount:
                    realtimeBrainInputBridgeSnapshot
                        .listeningConfirmationAcceptedCount,
                listeningConfirmationRejectedCount:
                    realtimeBrainInputBridgeSnapshot
                        .listeningConfirmationRejectedCount,
                listeningFreshnessRejectedCount:
                    realtimeBrainInputBridgeSnapshot
                        .listeningFreshnessRejectedCount,
                averageSendDurationMilliseconds:
                    realtimeBrainInputBridgeSnapshot
                        .averageSendDurationMilliseconds,
                maximumSendDurationMilliseconds:
                    realtimeBrainInputBridgeSnapshot
                        .maximumSendDurationMilliseconds,
                acousticObservationCount:
                    realtimeBrainInputBridgeSnapshot
                        .residentAcousticObservationCount,
                rejectedAcousticObservationCount:
                    realtimeBrainInputBridgeSnapshot
                        .rejectedResidentAcousticObservationCount,
                droppedAcousticObservationCount:
                    realtimeBrainInputBridgeSnapshot
                        .droppedResidentAcousticObservationCount,
                acousticEvidenceCount:
                    realtimeBrainInputBridgeSnapshot.acousticEvidenceCount,
                acousticEligibilityCandidateCount:
                    realtimeBrainInputBridgeSnapshot
                        .acousticEligibilityCandidateCount,
                acousticEligibilityRearmedCount:
                    realtimeBrainInputBridgeSnapshot
                        .acousticEligibilityRearmedCount,
                acousticEvidenceStaleFenceCount:
                    realtimeBrainInputBridgeSnapshot
                        .acousticEvidenceStaleFenceCount,
                acousticEligibilityDispositionCounts:
                    realtimeBrainInputBridgeSnapshot
                        .acousticEligibilityDispositionCounts,
                acousticEvidenceForwardDispositionCounts:
                    realtimeBrainInputBridgeSnapshot
                        .acousticEvidenceForwardDispositionCounts,
                lastAcousticEligibilityDisposition:
                    realtimeBrainInputBridgeSnapshot
                        .lastAcousticEligibilityDisposition,
                lastAcousticEvidenceForwardDisposition:
                    realtimeBrainInputBridgeSnapshot
                        .lastAcousticEvidenceForwardDisposition,
                lastError: realtimeBrainInputBridgeSnapshot.lastError,
                hasActivePump:
                    realtimeBrainInputBridgeSnapshot.hasActivePump
            ),
            realtimeBrainOutput: RealtimeBrainOutputDiagnosticExport(
                state: realtimeBrainOutputBridgeSnapshot.state.rawValue,
                sessionShortID:
                    realtimeBrainOutputBridgeSnapshot.sessionShortID,
                acceptedEventCount:
                    realtimeBrainOutputBridgeSnapshot.acceptedEventCount,
                rejectedEventCount:
                    realtimeBrainOutputBridgeSnapshot.rejectedEventCount,
                audioChunkCount:
                    realtimeBrainOutputBridgeSnapshot.audioChunkCount,
                audioByteCount:
                    realtimeBrainOutputBridgeSnapshot.audioByteCount,
                completedResponseCount:
                    realtimeBrainOutputBridgeSnapshot.completedResponseCount,
                lastError: realtimeBrainOutputBridgeSnapshot.lastError,
                hasActiveReceiveLoop:
                    realtimeBrainOutputBridgeSnapshot.hasActiveReceiveLoop
            ),
            qwenRealtime: qwenRealtime,
            turnCompletion: RealtimeTurnCompletionDiagnosticExport(
                phase: turnCompletion.phase.rawValue,
                sessionShortID: turnCompletion.session.map {
                    String($0.brainLeaseID.uuidString.prefix(8))
                },
                turnShortID: turnCompletion.turnID.map {
                    String($0.rawValue.uuidString.prefix(8))
                },
                sourceTurnShortID: turnCompletion.sourceTurnID.map {
                    String($0.rawValue.uuidString.prefix(8))
                },
                contextRevision: turnCompletion.contextRevision,
                completionCandidateCount:
                    turnCompletion.completionCandidateCount,
                resumedPauseCount: turnCompletion.resumedPauseCount,
                claimedAcousticSequence:
                    turnCompletion.claimedAcousticSequence,
                claimedListeningAudioSequence:
                    turnCompletion.claimedListeningAudioSequence,
                providerListeningAuthorizationCount:
                    turnCompletion.providerListeningAuthorizationCount,
                responseAuthorizationCount:
                    turnCompletion.responseAuthorizationCount,
                pendingStartTurnShortID:
                    turnCompletion.pendingStartTurnID.map {
                        String($0.rawValue.uuidString.prefix(8))
                    },
                pendingStartAtNanoseconds:
                    turnCompletion.pendingStartAtNanoseconds
            ),
            nativeSpeech: NativeSpeechDiagnosticExport(
                providerProfileID:
                    nativeSpeechProviderDebugState.profile.profileID,
                providerID:
                    nativeSpeechProviderDebugState.profile.providerID,
                modelID: nativeSpeechProviderDebugState.profile.modelID,
                voiceID: nativeSpeechProviderDebugState.profile.voiceID,
                state: realtimeSpeechStateSnapshot.state.rawValue,
                interactionShortID:
                    realtimeSpeechStateSnapshot.interactionShortID,
                turnNumber: realtimeSpeechStateSnapshot.currentTurnNumber,
                turnGeneration:
                    realtimeSpeechSubtitleSnapshot.turnGeneration,
                inputForwardedFrameCount:
                    speechInputBridgeSnapshot.forwardedFrameCount,
                inputRejectedFrameCount:
                    speechInputBridgeSnapshot.runtimeRejectedFrameCount,
                inputSendOperationCount:
                    speechInputBridgeSnapshot.sendOperationCount,
                inputAverageSendDurationMilliseconds:
                    speechInputBridgeSnapshot.averageSendDurationMilliseconds,
                inputMaximumSendDurationMilliseconds:
                    speechInputBridgeSnapshot.maximumSendDurationMilliseconds,
                outputAudioChunkCount:
                    speechOutputBridgeSnapshot.outputAudioChunkCount,
                outputAudioByteCount:
                    speechOutputBridgeSnapshot.outputAudioByteCount,
                outputRuntimeRejectedEventCount:
                    speechOutputBridgeSnapshot.runtimeRejectedEventCount
            ),
            playbackShared: RealtimeSpeechPlaybackDiagnosticExport(
                state: speechAudioOutputHostSnapshot.state.rawValue,
                generation: speechAudioOutputHostSnapshot.generation,
                outputDeviceID:
                    speechAudioOutputHostSnapshot.outputDevice.identifier,
                outputDeviceName:
                    speechAudioOutputHostSnapshot.outputDevice.name,
                queueDepth: speechAudioOutputHostSnapshot.queueDepth,
                scheduledChunkCount:
                    speechAudioOutputHostSnapshot.scheduledChunkCount,
                enqueuedChunkCount:
                    speechAudioOutputHostSnapshot.enqueuedChunkCount,
                enqueuedByteCount:
                    speechAudioOutputHostSnapshot.enqueuedByteCount,
                playedChunkCount:
                    speechAudioOutputHostSnapshot.playedChunkCount,
                playedByteCount:
                    speechAudioOutputHostSnapshot.playedByteCount,
                playbackStartedCount:
                    speechAudioOutputHostSnapshot.playbackStartedCount,
                playbackCompletedCount:
                    speechAudioOutputHostSnapshot.playbackCompletedCount,
                rejectedCallbackCount:
                    speechAudioOutputHostSnapshot.rejectedCallbackCount,
                lastError: speechAudioOutputHostSnapshot.lastError
            ),
            qwenInputAudioCapsule: qwenInputAudioCapsule.map {
                RealtimeSpeechAudioCapsuleDiagnosticExport(
                    attemptID: $0.attemptID.uuidString,
                    routeAttemptID: $0.routeAttemptID.uuidString,
                    brainLeaseID: $0.brainLeaseID.uuidString,
                    routeEpoch: $0.routeEpoch,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    firstGeneration: $0.firstGeneration,
                    lastGeneration: $0.lastGeneration,
                    firstBatchTerminalAudioSequence:
                        $0.firstBatchTerminalAudioSequence,
                    lastBatchTerminalAudioSequence:
                        $0.lastBatchTerminalAudioSequence,
                    encoding: "pcm16le",
                    sampleRate: 16_000,
                    channelCount: 1,
                    byteCount: $0.bytes.count,
                    durationMilliseconds: $0.durationMilliseconds,
                    sha256: audioCapsuleSHA256,
                    isSealed: $0.isSealed,
                    fileName: audioCapsuleFileName
                )
            },
            droppedEventCount:
                realtimeSpeechDiagnosticTimeline.droppedEventCount,
            events: realtimeSpeechDiagnosticTimeline.events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    private func qwenRealtimeDiagnosticExport()
        -> QwenRealtimeDiagnosticExport {
        let writeSnapshot = nativeSpeechDiagnosticBuffer
            .transportWriteSnapshot(
                for: .realtimeBrain
            )
        let averageWriteDuration =
            writeSnapshot.completedAudioAppendCount == 0
            ? 0
            : writeSnapshot.audioAppendWriteTotalDurationMilliseconds
                / writeSnapshot.completedAudioAppendCount
        let configuration = ProductionQwenRealtimeBrainConfiguration.value
        let writeWindowCapacity = writeSnapshot.writeWindowCapacity == 0
            ? NativeSpeechTransportWriteDiagnosticSnapshot
                .defaultWebSocketWriteWindowCapacity
            : writeSnapshot.writeWindowCapacity
        return QwenRealtimeDiagnosticExport(
            providerID: "Qwen",
            modelID: configuration.modelID,
            voiceID: configuration.defaultProviderVoiceID,
            writeWindowCapacity: writeWindowCapacity,
            pendingWriteCount: writeSnapshot.pendingWriteCount,
            maximumPendingWriteCount:
                writeSnapshot.maximumPendingWriteCount,
            submittedAudioAppendCount:
                writeSnapshot.submittedAudioAppendCount,
            completedAudioAppendCount:
                writeSnapshot.completedAudioAppendCount,
            submittedResponseCreateCount:
                writeSnapshot.submittedResponseCreateCount,
            completedResponseCreateCount:
                writeSnapshot.completedResponseCreateCount,
            capacityWaitCount: writeSnapshot.capacityWaitCount,
            capacityWaitTotalDurationMilliseconds:
                writeSnapshot.capacityWaitTotalDurationMilliseconds,
            capacityWaitMaximumDurationMilliseconds:
                writeSnapshot.capacityWaitMaximumDurationMilliseconds,
            averageAudioAppendWriteDurationMilliseconds:
                averageWriteDuration,
            maximumAudioAppendWriteDurationMilliseconds:
                writeSnapshot.audioAppendWriteMaximumDurationMilliseconds
        )
    }

    func writeRealtimeSpeechDiagnostics(
        to url: URL,
        exportedAt: Date = Date()
    ) throws {
        let expectedReplayAttemptID = realtimeSpeechReplayCaptureAttemptID
        let pendingCapsule = nativeSpeechDiagnosticBuffer
            .realtimeAudioCapsuleSnapshot()
        let pendingAcousticReplay = realtimeSpeechDiagnosticAudioEngine?
            .acousticReplayCaptureSnapshot()
        if let expectedReplayAttemptID {
            guard let pendingCapsule,
                  pendingCapsule.attemptID == expectedReplayAttemptID,
                  let pendingAcousticReplay,
                  pendingAcousticReplay.attemptID == expectedReplayAttemptID,
                  pendingAcousticReplay.isExactReplayReady else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        realtimeSpeechAudioCaptureTask?.cancel()
        realtimeSpeechAudioCaptureTask = nil
        if let expectedReplayAttemptID,
           !sealRealtimeAudioCapsule(
                matchingAttemptID: expectedReplayAttemptID
           ) {
            throw CocoaError(.fileWriteUnknown)
        }
        let capsule = nativeSpeechDiagnosticBuffer
            .realtimeAudioCapsuleSnapshot()
        let qwenPCMURL = capsule.flatMap { snapshot -> URL? in
            guard !snapshot.bytes.isEmpty else { return nil }
            return url.deletingPathExtension()
                .appendingPathExtension("qwen-input.pcm")
        }
        let audioCapsuleSHA256 = capsule.flatMap { snapshot in
            snapshot.bytes.isEmpty ? nil : Self.sha256Hex(snapshot.bytes)
        }
        let acousticReplay = realtimeSpeechDiagnosticAudioEngine?
            .acousticReplayCaptureSnapshot()
        if let expectedReplayAttemptID,
           (capsule?.attemptID != expectedReplayAttemptID
                || acousticReplay?.attemptID != expectedReplayAttemptID) {
            throw CocoaError(.fileWriteUnknown)
        }
        if let acousticReplay, !acousticReplay.isExactReplayReady {
            throw CocoaError(.fileWriteUnknown)
        }
        let rawMicrophoneData = acousticReplay.map {
            MacSpeechAcousticReplayCodec.float32LittleEndianData(
                $0.rawMicrophoneSamples
            )
        }
        let chronologicalRenderData = acousticReplay.map {
            MacSpeechAcousticReplayCodec.float32LittleEndianData(
                $0.chronologicalRenderSamples
            )
        }
        let aecCleanData = acousticReplay.map {
            MacSpeechAcousticReplayCodec.float32LittleEndianData(
                $0.aecCleanSamples
            )
        }
        let aecLinearData = acousticReplay.map {
            MacSpeechAcousticReplayCodec.float32LittleEndianData(
                $0.aecLinearSamples
            )
        }
        let baseURL = url.deletingPathExtension()
        let rawMicrophoneURL = rawMicrophoneData.flatMap { data in
            data.isEmpty ? nil : baseURL.appendingPathExtension(
                "raw-mic.f32le.pcm"
            )
        }
        let chronologicalRenderURL = chronologicalRenderData.flatMap { data in
            data.isEmpty ? nil : baseURL.appendingPathExtension(
                "render-full.f32le.pcm"
            )
        }
        let aecCleanURL = aecCleanData.flatMap { data in
            data.isEmpty ? nil : baseURL.appendingPathExtension(
                "aec-clean.f32le.pcm"
            )
        }
        let aecLinearURL = aecLinearData.flatMap { data in
            data.isEmpty ? nil : baseURL.appendingPathExtension(
                "aec-linear.f32le.pcm"
            )
        }
        let acousticTimelineURL = acousticReplay.flatMap { snapshot in
            snapshot.captureFrames.isEmpty
                ? nil : baseURL.appendingPathExtension(
                "aec-timeline.json"
            )
        }
        let acousticTimelineData: Data?
        if let acousticReplay,
           let rawMicrophoneData,
           let chronologicalRenderData,
           let aecCleanData,
           let aecLinearData,
           let rawMicrophoneURL,
           let chronologicalRenderURL,
           let aecCleanURL,
           let aecLinearURL {
            acousticTimelineData = try acousticReplayManifestData(
                snapshot: acousticReplay,
                rawMicrophoneData: rawMicrophoneData,
                rawMicrophoneFileName: rawMicrophoneURL.lastPathComponent,
                chronologicalRenderData: chronologicalRenderData,
                chronologicalRenderFileName:
                    chronologicalRenderURL.lastPathComponent,
                aecCleanData: aecCleanData,
                aecCleanFileName: aecCleanURL.lastPathComponent,
                aecLinearData: aecLinearData,
                aecLinearFileName: aecLinearURL.lastPathComponent
            )
        } else {
            acousticTimelineData = nil
        }
        let data = try realtimeSpeechDiagnosticExportData(
            exportedAt: exportedAt,
            audioCapsuleFileName: qwenPCMURL?.lastPathComponent,
            audioCapsuleSHA256: audioCapsuleSHA256
        )

        struct Sidecar {
            let url: URL
            let data: Data
        }

        var sidecars: [Sidecar] = []
        if let capsule, let qwenPCMURL, !capsule.bytes.isEmpty {
            sidecars.append(Sidecar(url: qwenPCMURL, data: capsule.bytes))
        }
        if let rawMicrophoneURL, let rawMicrophoneData {
            sidecars.append(Sidecar(
                url: rawMicrophoneURL,
                data: rawMicrophoneData
            ))
        }
        if let chronologicalRenderURL, let chronologicalRenderData {
            sidecars.append(Sidecar(
                url: chronologicalRenderURL,
                data: chronologicalRenderData
            ))
        }
        if let aecCleanURL, let aecCleanData {
            sidecars.append(Sidecar(url: aecCleanURL, data: aecCleanData))
        }
        if let aecLinearURL, let aecLinearData {
            sidecars.append(Sidecar(url: aecLinearURL, data: aecLinearData))
        }
        if let acousticTimelineURL, let acousticTimelineData {
            sidecars.append(Sidecar(
                url: acousticTimelineURL,
                data: acousticTimelineData
            ))
        }

        let fileManager = FileManager.default
        let destinations = [url] + sidecars.map(\.url)
        guard !destinations.contains(where: {
            fileManager.fileExists(atPath: $0.path)
        }) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let stagingID = UUID().uuidString
        let stagingDirectory = url.deletingLastPathComponent()
        let jsonStagingURL = stagingDirectory.appendingPathComponent(
            ".aftelle-diagnostics-\(stagingID).json.tmp"
        )
        let sidecarStagingURLs = sidecars.enumerated().map { index, _ in
            stagingDirectory.appendingPathComponent(
                ".aftelle-diagnostics-\(stagingID)-\(index).tmp"
            )
        }
        defer {
            try? fileManager.removeItem(at: jsonStagingURL)
            for stagingURL in sidecarStagingURLs {
                try? fileManager.removeItem(at: stagingURL)
            }
        }
        try data.write(to: jsonStagingURL, options: .atomic)
        for (sidecar, stagingURL) in zip(sidecars, sidecarStagingURLs) {
            try sidecar.data.write(to: stagingURL, options: .atomic)
        }
        var movedURLs: [URL] = []
        do {
            try fileManager.moveItem(at: jsonStagingURL, to: url)
            movedURLs.append(url)
            for (sidecar, stagingURL) in zip(sidecars, sidecarStagingURLs) {
                try fileManager.moveItem(at: stagingURL, to: sidecar.url)
                movedURLs.append(sidecar.url)
            }
        } catch {
            for movedURL in movedURLs {
                try? fileManager.removeItem(at: movedURL)
            }
            throw error
        }
        if let attemptID = capsule?.attemptID {
            nativeSpeechDiagnosticBuffer.clearRealtimeAudioCapsule(
                matchingAttemptID: attemptID
            )
        }
        if let attemptID = acousticReplay?.attemptID {
            realtimeSpeechDiagnosticAudioEngine?.clearAcousticReplayCapture(
                matchingAttemptID: attemptID
            )
        }
        if expectedReplayAttemptID != nil {
            realtimeSpeechReplayCaptureAttemptID = nil
        }
    }

    private func sealRealtimeAudioCapsule(
        matchingAttemptID attemptID: UUID
    ) -> Bool {
        guard nativeSpeechDiagnosticBuffer.realtimeAudioCapsuleSnapshot()?
            .attemptID == attemptID else { return false }
        nativeSpeechDiagnosticBuffer.sealRealtimeAudioCapsule()
        guard let snapshot = nativeSpeechDiagnosticBuffer
            .realtimeAudioCapsuleSnapshot() else { return false }
        return snapshot.attemptID == attemptID && snapshot.isSealed
    }

    private func acousticReplayManifestData(
        snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        rawMicrophoneData: Data,
        rawMicrophoneFileName: String,
        chronologicalRenderData: Data,
        chronologicalRenderFileName: String,
        aecCleanData: Data,
        aecCleanFileName: String,
        aecLinearData: Data,
        aecLinearFileName: String
    ) throws -> Data {
        let audioFile: (String, Data, String, Int, Int) ->
            MacSpeechAcousticReplayAudioFile = {
                fileName,
                data,
                stage,
                sampleRate,
                frameSampleCount in
                MacSpeechAcousticReplayAudioFile(
                    fileName: fileName,
                    sha256: Self.sha256Hex(data),
                    stage: stage,
                    encoding: "float32le",
                    sampleRate: sampleRate,
                    channelCount: 1,
                    frameSampleCount: frameSampleCount,
                    byteCount: data.count
                )
            }
        let producerBinary = Self.runningBuildBinary()
        guard producerBinary.name != "-",
              producerBinary.sha256.count == 64 else {
            throw CocoaError(.fileWriteUnknown)
        }
        let manifest = MacSpeechAcousticReplayManifest(
            schemaVersion: 2,
            producerBinaryName: producerBinary.name,
            producerBinarySHA256: producerBinary.sha256,
            attemptID: snapshot.attemptID.uuidString,
            armedAt: snapshot.armedAt,
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
            targetPostPlaybackCaptureFrameCount:
                snapshot.targetPostPlaybackCaptureFrameCount,
            postPlaybackCaptureFrameCount:
                snapshot.postPlaybackCaptureFrameCount,
            capturedFrameCount: snapshot.captureFrames.count,
            renderedFrameCount: snapshot.renderFrames.count,
            durationMilliseconds: snapshot.durationMilliseconds,
            missingTimingMatchFrameCount: snapshot.captureFrames.reduce(0) {
                $0 + ($1.timingMatchAvailable ? 0 : 1)
            },
            isSealed: snapshot.isSealed,
            sealReason: snapshot.sealReason,
            exactReplayReady: snapshot.isExactReplayReady,
            renderReferenceSemantics:
                "chronological_host_render_callback_input",
            rawMicrophone: audioFile(
                rawMicrophoneFileName,
                rawMicrophoneData,
                "post_device_conversion_pre_aec_callback_input",
                MacSpeechAcousticEchoHost.sampleRate,
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            chronologicalRender: audioFile(
                chronologicalRenderFileName,
                chronologicalRenderData,
                "chronological_post_device_conversion_render_callback_input",
                MacSpeechAcousticEchoHost.sampleRate,
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            aecClean: audioFile(
                aecCleanFileName,
                aecCleanData,
                "post_aec_pre_source_gate",
                MacSpeechAcousticEchoHost.sampleRate,
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            aecLinear: audioFile(
                aecLinearFileName,
                aecLinearData,
                "webrtc_aec_linear_output",
                MacSpeechAcousticEchoHost.linearOutputSampleRate,
                MacSpeechAcousticEchoHost.linearOutputFrameSampleCount
            ),
            initialState: snapshot.initialState,
            finalState: snapshot.finalState,
            audioCalls: snapshot.audioCalls,
            controlEvents: snapshot.controlEvents,
            renderFrames: snapshot.renderFrames,
            captureFrames: snapshot.captureFrames
        )
        return try manifest.encodedData()
    }

    private static func runningBuildBinary() -> (
        name: String,
        sha256: String
    ) {
        guard let executableURL = Bundle.main.executableURL else {
            return ("-", "-")
        }
        let debugLibraryURL = executableURL.deletingLastPathComponent()
            .appendingPathComponent(
                "\(executableURL.lastPathComponent).debug.dylib"
            )
        let binaryURL = FileManager.default.fileExists(
            atPath: debugLibraryURL.path
        ) ? debugLibraryURL : executableURL
        guard let data = try? Data(contentsOf: binaryURL) else {
            return (binaryURL.lastPathComponent, "-")
        }
        let sha256 = SHA256.hash(data: data)
        return (binaryURL.lastPathComponent, Self.hexString(sha256))
    }

    private static func sha256Hex(_ data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    private static func hexString<S: Sequence>(_ bytes: S) -> String
        where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func realtimeSpeechAcousticEchoDiagnosticExport()
        -> RealtimeSpeechAcousticEchoDiagnosticExport {
        var export = RealtimeSpeechAcousticEchoDiagnosticExport()
        guard let snapshot = speechAudioHost.currentAcousticEchoSnapshot()
        else { return export }

        export.available = true
        export.mode = snapshot.mode.rawValue
        export.enabled = snapshot.enabled
        export.active = snapshot.active
        export.isPlaybackActive = snapshot.isPlaybackActive
        export.inputClassification = snapshot.inputClassification.rawValue
        export.sourceGateOpen = snapshot.sourceGateOpen
        export.sourceGatePreRollFrameCount =
            snapshot.sourceGatePreRollFrameCount
        export.renderFrameCount = snapshot.renderFrameCount
        export.captureFrameCount = snapshot.captureFrameCount
        export.delayMilliseconds = snapshot.delayMilliseconds
        export.aecBufferDelayMilliseconds =
            snapshot.aecBufferDelayMilliseconds
        export.presentationDelayMilliseconds =
            snapshot.presentationDelayMilliseconds
        export.alignedDelayMilliseconds = snapshot.alignedDelayMilliseconds
        export.sourceAlignmentDelayMilliseconds =
            snapshot.sourceAlignmentDelayMilliseconds
        export.estimatedDelayMilliseconds =
            snapshot.estimatedDelayMilliseconds
        export.erlDecibels = snapshot.erlDecibels
        export.erleDecibels = snapshot.erleDecibels
        export.rawCaptureRMS = snapshot.rawCaptureRMS
        export.processedCaptureRMS = snapshot.processedCaptureRMS
        export.renderCaptureCorrelation = snapshot.renderCaptureCorrelation
        export.residualRenderCorrelation =
            snapshot.residualRenderCorrelation
        export.linearAECOutputRMS = snapshot.linearAECOutputRMS
        export.linearRenderCorrelation = snapshot.linearRenderCorrelation
        export.processedLinearCorrelation =
            snapshot.processedLinearCorrelation
        export.renderTimingFrameCount = snapshot.renderTimingFrameCount
        export.renderFIFOSampleCount = snapshot.renderFIFOSampleCount
        export.captureFIFOSampleCount = snapshot.captureFIFOSampleCount
        export.echoOnlyFrameCount = snapshot.echoOnlyFrameCount
        export.nearEndSpeechFrameCount = snapshot.nearEndSpeechFrameCount
        export.doubleTalkFrameCount = snapshot.doubleTalkFrameCount
        export.uncertainFrameCount = snapshot.uncertainFrameCount
        export.sourceForwardedFrameCount =
            snapshot.sourceForwardedFrameCount
        export.sourceSuppressedFrameCount =
            snapshot.sourceSuppressedFrameCount
        export.sourceTimingCandidateFrameCount =
            snapshot.sourceTimingCandidateFrameCount
        export.sourceTimingUnavailableFrameCount =
            snapshot.sourceTimingUnavailableFrameCount
        export.sourceGateOpenCount = snapshot.sourceGateOpenCount
        export.sourceGateCloseCount = snapshot.sourceGateCloseCount
        export.maximumSourceGateOpenFrameCount =
            snapshot.maximumSourceGateOpenFrameCount
        export.maximumContinuousSourceForwardedFrameCount =
            snapshot.maximumContinuousSourceForwardedFrameCount
        export.rawEchoGainBaseline =
            snapshot.rawEchoGainBaseline
        export.residualEchoGainBaseline =
            snapshot.residualEchoGainBaseline
        export.linearAECOutputGainBaseline =
            snapshot.linearAECOutputGainBaseline
        export.residualEchoBaselineFrameCount =
            snapshot.residualEchoBaselineFrameCount
        export.residualEchoBaselineFrozen =
            snapshot.residualEchoBaselineFrozen
        export.residualEchoBaselineUpdateCount =
            snapshot.residualEchoBaselineUpdateCount
        export.residualEchoBaselineFreezeCount =
            snapshot.residualEchoBaselineFreezeCount
        export.adaptiveEvidenceCandidateFrameCount =
            snapshot.adaptiveEvidenceCandidateFrameCount
        export.adaptiveDoubleTalkFrameCount =
            snapshot.adaptiveDoubleTalkFrameCount
        export.maximumAdaptiveRawExcessRMS =
            snapshot.maximumAdaptiveRawExcessRMS
        export.maximumAdaptiveResidualExcessRMS =
            snapshot.maximumAdaptiveResidualExcessRMS
        export.maximumAdaptiveLinearExcessRMS =
            snapshot.maximumAdaptiveLinearExcessRMS
        export.renderCaptureIsolationEstablished =
            snapshot.renderCaptureIsolationEstablished
        export.renderCaptureIsolationQuietFrameCount =
            snapshot.renderCaptureIsolationQuietFrameCount
        export.renderCaptureIsolationEstablishmentCount =
            snapshot.renderCaptureIsolationEstablishmentCount
        export.renderCaptureIsolationRevocationCount =
            snapshot.renderCaptureIsolationRevocationCount
        export.sourceAlignmentLocked = snapshot.sourceAlignmentLocked
        export.sourceAlignmentAcquisitionFrameCount =
            snapshot.sourceAlignmentAcquisitionFrameCount
        export.sourceAlignmentMissCount = snapshot.sourceAlignmentMissCount
        export.sourceAlignmentReacquisitionCount =
            snapshot.sourceAlignmentReacquisitionCount
        export.lastSourceGateCloseReason =
            snapshot.lastSourceGateCloseReason?.rawValue
        export.sourceGateEpochs = snapshot.sourceGateEpochs.map { epoch in
            RealtimeSpeechSourceGateEpochDiagnosticExport(
                playbackSequence: epoch.playbackSequence,
                epochSequence: epoch.epochSequence,
                openedAtCaptureFrame: epoch.openedAtCaptureFrame,
                closedAtCaptureFrame: epoch.closedAtCaptureFrame,
                totalFrameCount: epoch.totalFrameCount,
                forwardedFrameCount: epoch.forwardedFrameCount,
                suppressedFrameCount: epoch.suppressedFrameCount,
                echoOnlyFrameCount: epoch.echoOnlyFrameCount,
                nearEndSpeechFrameCount: epoch.nearEndSpeechFrameCount,
                doubleTalkFrameCount: epoch.doubleTalkFrameCount,
                uncertainFrameCount: epoch.uncertainFrameCount,
                rawEchoGainBaselineAtOpen:
                    epoch.rawEchoGainBaselineAtOpen,
                rawEchoGainBaselineAtClose:
                    epoch.rawEchoGainBaselineAtClose,
                residualEchoGainBaselineAtOpen:
                    epoch.residualEchoGainBaselineAtOpen,
                residualEchoGainBaselineAtClose:
                    epoch.residualEchoGainBaselineAtClose,
                linearAECOutputGainBaselineAtOpen:
                    epoch.linearAECOutputGainBaselineAtOpen,
                linearAECOutputGainBaselineAtClose:
                    epoch.linearAECOutputGainBaselineAtClose,
                aecBufferDelayMillisecondsAtOpen:
                    epoch.aecBufferDelayMillisecondsAtOpen,
                aecBufferDelayMillisecondsAtClose:
                    epoch.aecBufferDelayMillisecondsAtClose,
                sourceAlignmentDelayMillisecondsAtOpen:
                    epoch.sourceAlignmentDelayMillisecondsAtOpen,
                sourceAlignmentDelayMillisecondsAtClose:
                    epoch.sourceAlignmentDelayMillisecondsAtClose,
                estimatedDelayMillisecondsAtOpen:
                    epoch.estimatedDelayMillisecondsAtOpen,
                estimatedDelayMillisecondsAtClose:
                    epoch.estimatedDelayMillisecondsAtClose,
                closeReason: epoch.closeReason?.rawValue
            )
        }
        export.fallbackCount = snapshot.fallbackCount
        export.fallbackReason = snapshot.fallbackReason?.rawValue
        export.lastFallbackReason = snapshot.lastFallbackReason?.rawValue
        export.routeResetCount = snapshot.routeResetCount
        export.driftTrend = snapshot.driftTrend
        return export
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

    private var speechHostAllowsSessionReplacement: Bool {
        guard speechHostLifecycleOperationCount == 0,
              !speechAudioHostSnapshot.isCapturing,
              formalSpeechRouteGeneration == nil,
              !speechInputBridgeSnapshot.hasActivePump,
              !speechOutputBridgeSnapshot.hasActiveReceiveLoop,
              realtimeBrainInputBinding == nil,
              !realtimeBrainInputBridgeSnapshot.hasActivePump,
              !realtimeBrainOutputBridgeSnapshot.hasActiveReceiveLoop,
              nativeSpeechPlaybackBinding == nil else {
            return false
        }
        switch speechAudioOutputHostSnapshot.state {
        case .prepared, .playing, .stalled, .draining:
            return false
        case .idle, .completed, .stopped, .failed, .closed:
            return true
        }
    }

    func clearDialogueTestData() {
        guard speechHostAllowsSessionReplacement else {
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "session_replacement_blocked_active_host"
            )
            return
        }
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

    private func realtimeSpeechDiagnosticFileName(
        exportedAt: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "aftelle-realtime-speech-diagnostics-\(formatter.string(from: exportedAt)).json"
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
        guard speechHostAllowsSessionReplacement else {
            fixtureStatus = "Debug DR: stop speech before import"
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "session_replacement_blocked_active_host"
            )
            return
        }
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

    func saveNativeSpeechProviderCredential(
        workspaceID: String,
        secret: String
    ) {
        do {
            let credential = try QwenRealtimeCredential(
                workspaceID: workspaceID,
                secret: secret
            ).storedValue()
            try providerKeychainStore.save(
                credential,
                for: ProviderKeychainStore.qwenKeyRef
            )
            nativeSpeechProviderDebugState.credentialSaved = true
            nativeSpeechProviderDebugState.statusKey =
                "particleDebug.qwen.status.credentialSaved"
        } catch {
            refreshNativeSpeechProviderDebugState(
                statusKey: "particleDebug.qwen.status.credentialFailed"
            )
        }
    }

    func selectNativeSpeechModel(_ modelID: String) {
        guard let model = Stage75QwenRealtimeModel(rawValue: modelID),
              !nativeSpeechProviderDebugState.isTesting,
              !speechInputBridgeSnapshot.hasActivePump,
              !speechOutputBridgeSnapshot.hasActiveReceiveLoop else {
            return
        }
        let currentState = nativeSpeechProviderDebugState
        nativeSpeechProviderDebugState = NativeSpeechProviderDebugViewState(
            profile: Stage75NativeSpeechConfiguration.makeProfile(
                model: model
            ),
            credentialSaved: currentState.credentialSaved,
            statusKey: "particleDebug.qwen.status.ready"
        )
    }

    func refreshMicrophoneAuthorization() async {
        speechAudioHostShutdownCompleted = false
        speechAudioHostSnapshot =
            await speechAudioHost.refreshAuthorization()
        speechInputBridgeSnapshot =
            await speechInputBridge.currentSnapshot()
        speechOutputBridgeSnapshot =
            await speechOutputBridge.currentSnapshot()
        realtimeBrainInputBridgeSnapshot =
            await realtimeBrainInputBridge.currentSnapshot()
        realtimeBrainOutputBridgeSnapshot =
            await realtimeBrainOutputBridge.currentSnapshot()
        speechAudioOutputHostSnapshot =
            await speechAudioOutputHost.refreshDiagnostics()
        syncRealtimeSpeechPresentation()
        recordRealtimeSpeechInputAggregateIfNeeded()
    }

    func requestMicrophoneAuthorization() async {
        speechAudioHostShutdownCompleted = false
        _ = await ensureRealtimeMicrophoneAuthorization()
    }

    func startSpeechAudioCapture() async {
        speechAudioHostShutdownCompleted = false
        speechHostLifecycleOperationCount += 1
        defer { speechHostLifecycleOperationCount -= 1 }
        speechAudioHostSnapshot = await speechAudioHost.startCapture()
        if speechAudioHostSnapshot.isCapturing {
            lastDiagnosticAggregateNanoseconds = 0
            lastDiagnosticCaptureGeneratedCount = 0
            lastDiagnosticCaptureDroppedCount = 0
        }
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: speechAudioHostSnapshot.isCapturing
                ? "capture_started" : "capture_start_failed",
            errorCode: speechAudioHostSnapshot.lastError
        )
    }

    func stopSpeechAudioCapture() async {
        speechHostLifecycleOperationCount += 1
        defer { speechHostLifecycleOperationCount -= 1 }
        await cancelFormalSpeechRoute()
        await stopRealtimeResidentBrainRoute()
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "manual_stop_started"
        )
        if nativeSpeechPlaybackBinding != nil {
            playbackStopClearCount &+= 1
        }
        nativeSpeechPlaybackBinding = nil
        speechAudioOutputHostSnapshot = await speechAudioOutputHost.close()
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "player_released",
            stateAfter: speechAudioOutputHostSnapshot.state.rawValue
        )
        realtimeSpeechPlaybackSubtitleSynchronizer.resetForTerminal(
            canonicalCompleted:
                realtimeSpeechSubtitleSnapshot.lastCompleted
        )
        speechOutputBridgeSnapshot = await speechOutputBridge.stop()
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "receive_loop_released",
            stateAfter: speechOutputBridgeSnapshot.state.rawValue
        )
        speechInputBridgeSnapshot = await speechInputBridge.stop()
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "input_pump_released",
            stateAfter: speechInputBridgeSnapshot.state.rawValue
        )
        speechAudioHostSnapshot = await speechAudioHost.stopCapture()
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "capture_released",
            stateAfter: speechAudioHostSnapshot.state.rawValue
        )
        syncRealtimeSpeechPresentation()
        refreshNativeSpeechPlaybackDebugSnapshot()
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "manual_stop_completed",
            stateAfter: realtimeSpeechStateSnapshot.state.rawValue
        )
    }
    #endif

    func shutdownSpeechAudioHost() async {
        guard !speechAudioHostShutdownCompleted else { return }
        if let operation = speechAudioHostShutdownOperation {
            await operation.task.value
            return
        }
        let operationID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performSpeechAudioHostShutdown()
        }
        speechAudioHostShutdownOperation = (operationID, task)
        await task.value
        if speechAudioHostShutdownOperation?.id == operationID {
            speechAudioHostShutdownOperation = nil
            speechAudioHostShutdownCompleted = true
            objectWillChange.send()
        }
    }

    private func performSpeechAudioHostShutdown() async {
        speechHostLifecycleOperationCount += 1
        defer { speechHostLifecycleOperationCount -= 1 }
        await stopRealtimeResidentBrainRoute()
        #if DEBUG
        await cancelFormalSpeechRoute()
        if nativeSpeechPlaybackBinding != nil {
            playbackStopClearCount &+= 1
        }
        nativeSpeechPlaybackBinding = nil
        #endif
        speechAudioOutputHostSnapshot = await speechAudioOutputHost.close()
        #if DEBUG
        realtimeSpeechPlaybackSubtitleSynchronizer.resetForTerminal(
            canonicalCompleted:
                realtimeSpeechSubtitleSnapshot.lastCompleted
        )
        speechOutputBridgeSnapshot = await speechOutputBridge.stop()
        speechInputBridgeSnapshot = await speechInputBridge.stop()
        syncRealtimeSpeechPresentation()
        refreshNativeSpeechPlaybackDebugSnapshot()
        #endif
        await speechAudioHost.shutdown()
        speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
    }

    func startRealtimeFullDuplexSpeech() async {
        await startRealtimeResidentBrainRoute()
    }

    func startRealtimeResidentBrainRoute() async {
        if realtimeBrainRouteAttemptID != nil || realtimeBrainStartInFlight {
            return
        }
        guard realtimeBrainInputBinding == nil,
              !realtimeBrainStopping,
              !hasActiveAlternateSpeechRoute,
              speechAudioHostShutdownOperation == nil,
              speechHostLifecycleOperationCount == 0 else {
            publishRealtimeResidentBrainRouteFailure("speech_input_busy")
            return
        }
        guard isResidentTextInputAvailable else {
            publishRealtimeResidentBrainRouteFailure("resident_unavailable")
            return
        }
        speechAudioHostShutdownCompleted = false

        let attemptID = UUID()
        realtimeBrainRouteAttemptID = attemptID
        resetRealtimeBrainMissingSpeechStopPresentation()
        realtimePassiveBackchannelPresentation = nil
        realtimeBrainSubtitlePresentation.reset()
        particleSubtitleState = .hidden
        #if DEBUG
        realtimeBrainRecoverableResponseErrorCount = 0
        lastRealtimeBrainRecoverableResponseErrorCode = nil
        lastDiagnosticAggregateNanoseconds = 0
        lastDiagnosticInputForwardedCount = 0
        lastDiagnosticInputRejectedCount = 0
        lastDiagnosticCaptureGeneratedCount = 0
        lastDiagnosticCaptureDroppedCount = 0
        #endif
        orchestrationKernel.setRealtimePassiveBackchannelHandler {
            [weak self] presentation in
            self?.consumeRealtimePassiveBackchannelPresentation(
                presentation
            )
        }
        orchestrationKernel.setRealtimePendingAnswerPresentationHandler { [weak self] identity, error in
            guard let self,
                  self.isCurrentRealtimeBrainRoute(attemptID: attemptID, session: identity.session),
                  !self.realtimeBrainStopping else { return }
            self.updateRealtimeFullDuplexSpeechStatus(
                error == nil ? .processing : .listening,
                generation: identity.session.generation,
                lastErrorCode: error.map(Self.realtimeResidentBrainErrorCode)
            )
        }
        realtimeBrainStartInFlight = true
        defer {
            realtimeBrainStartInFlight = false
            objectWillChange.send()
        }
        speechHostLifecycleOperationCount += 1
        defer { speechHostLifecycleOperationCount -= 1 }
        updateRealtimeFullDuplexSpeechStatus(
            .starting,
            generation: nil,
            lastErrorCode: nil
        )
        let microphoneAuthorization =
            await ensureRealtimeMicrophoneAuthorization()
        guard realtimeBrainRouteAttemptID == attemptID,
              speechAudioHostShutdownOperation == nil,
              !speechAudioHostShutdownCompleted else {
            if speechAudioHostShutdownOperation != nil
                || speechAudioHostShutdownCompleted {
                await speechAudioHost.shutdown()
                speechAudioHostSnapshot =
                    await speechAudioHost.currentSnapshot()
            }
            return
        }
        switch microphoneAuthorization {
        case .authorized:
            break
        case .notDetermined:
            realtimeBrainRouteAttemptID = nil
            publishRealtimeResidentBrainRouteFailure(
                "microphone_permission_required"
            )
            return
        case .denied:
            realtimeBrainRouteAttemptID = nil
            publishRealtimeResidentBrainRouteFailure(
                "microphone_permission_denied"
            )
            return
        case .restricted, .failed:
            realtimeBrainRouteAttemptID = nil
            publishRealtimeResidentBrainRouteFailure(
                "microphone_permission_unavailable"
            )
            return
        }
        let preparedCaptureGeneration =
            await speechAudioHost.prepareCaptureGeneration()
        guard realtimeBrainRouteAttemptID == attemptID else {
            if let preparedCaptureGeneration {
                _ = await speechAudioHost.cancelPreparedCapture(
                    generation: preparedCaptureGeneration
                )
            }
            return
        }
        guard let captureGeneration = preparedCaptureGeneration else {
            speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
            guard realtimeBrainRouteAttemptID == attemptID else { return }
            realtimeBrainRouteAttemptID = nil
            publishRealtimeResidentBrainRouteFailure("capture_unavailable")
            return
        }
        realtimeBrainPreparedCaptureGeneration = captureGeneration

        let startResult = await orchestrationKernel
            .startRealtimeResidentBrainInput()
        guard realtimeBrainRouteAttemptID == attemptID else {
            await settleAbandonedRealtimeBrainStart(
                result: startResult,
                captureGeneration: captureGeneration
            )
            return
        }
        guard case .success(let session) = startResult else {
            realtimeBrainRouteAttemptID = nil
            realtimeBrainPreparedCaptureGeneration = nil
            speechAudioHostSnapshot = await speechAudioHost
                .cancelPreparedCapture(generation: captureGeneration)
            if case .failure(let error) = startResult {
                publishRealtimeResidentBrainRouteFailure(
                    Self.realtimeResidentBrainErrorCode(error)
                )
            }
            return
        }

        let binding = MacSpeechRealtimeBrainInputBinding(
            session: session,
            captureGeneration: captureGeneration
        )

        realtimeBrainPreparedCaptureGeneration = nil
        realtimeBrainInputBinding = binding
        realtimeBrainPlaybackResponseID = nil
        realtimeBrainPlaybackEventIdentity = nil
        realtimeBrainPlaybackProviderFinishedResponseID = nil
        realtimeBrainPlaybackGeneration = nil
        realtimeBrainGenerationTransitionTask = nil
        realtimeBrainStopping = false
        runtimeState = .running
        residentSpeechSignal = .ended
        refreshResidentVisualIntent(
            visualStateMode: ResidentVisualIntent.listening.rawValue
        )
        await speechAudioOutputHost.setEventSink { [weak self] event in
            await self?.consumeRealtimeResidentBrainPlaybackEvent(
                event,
                attemptID: attemptID,
                session: session
            )
        }
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: session
        ) else { return }
        realtimeBrainOutputBridgeSnapshot = await realtimeBrainOutputBridge
            .start(session: binding.session)
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: session
        ) else { return }
        speechAudioHostSnapshot = await speechAudioHost
            .startPreparedCapture(generation: captureGeneration)
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: session
        ) else { return }
        guard speechAudioHostSnapshot.isCapturing else {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: "capture_start_failed"
            )
            return
        }
        realtimeBrainInputBridgeSnapshot = await realtimeBrainInputBridge
            .start(binding: binding)
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: session
        ) else { return }
        guard realtimeBrainInputBridgeSnapshot.hasActivePump else {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: "input_bridge_start_failed"
            )
            return
        }

        updateRealtimeFullDuplexSpeechStatus(
            .listening,
            generation: binding.session.generation,
            lastErrorCode: nil
        )
        #if DEBUG
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "realtime_brain_route_listening",
            routeKind: .realtimeBrain,
            turnGeneration: binding.session.generation,
            stateAfter: FormalSpeechRoutePhase.listening.rawValue
        )
        #endif
        refreshParticleDebugSnapshot()
    }

    private func ensureRealtimeMicrophoneAuthorization() async
        -> MicrophoneAuthorizationState {
        speechAudioHostSnapshot = await speechAudioHost.refreshAuthorization()
        if speechAudioHostSnapshot.authorization == .notDetermined {
            speechAudioHostSnapshot =
                await speechAudioHost.requestMicrophoneAuthorization()
        }
        return speechAudioHostSnapshot.authorization
    }

    func stopRealtimeFullDuplexSpeech() async {
        await stopRealtimeResidentBrainRoute()
    }

    private func resetRealtimeBrainMissingSpeechStopPresentation() {
        realtimeBrainMissingSpeechStopPresentationTask?.cancel()
        realtimeBrainMissingSpeechStopPresentationTask = nil
        realtimeBrainMissingSpeechStopPresentationIdentity = nil
        realtimeBrainLatestSpeechStopIdentity = nil
    }

    private func cancelRealtimeBrainMissingSpeechStopPresentation() {
        realtimeBrainMissingSpeechStopPresentationTask?.cancel()
        realtimeBrainMissingSpeechStopPresentationTask = nil
        realtimeBrainMissingSpeechStopPresentationIdentity = nil
    }

    private func observeRealtimeBrainUserSpeechStarted() {
        realtimeBrainLatestSpeechStopIdentity = nil
    }

    private func observeRealtimeBrainUserSpeechStopped(
        _ identity: RealtimeBrainEventIdentity
    ) {
        realtimeBrainLatestSpeechStopIdentity = identity
        if realtimeBrainMissingSpeechStopPresentationIdentity == identity {
            cancelRealtimeBrainMissingSpeechStopPresentation()
        }
    }

    private func hasObservedRealtimeBrainUserSpeechStop(
        matching identity: RealtimeBrainEventIdentity
    ) -> Bool {
        guard let stopped = realtimeBrainLatestSpeechStopIdentity else {
            return false
        }
        return stopped == identity
    }

    private func scheduleRealtimeBrainMissingSpeechStopPresentationRecovery(
        identity: RealtimeBrainEventIdentity,
        attemptID: UUID
    ) {
        if hasObservedRealtimeBrainUserSpeechStop(matching: identity) {
            return
        }
        if realtimeBrainMissingSpeechStopPresentationIdentity == identity,
           realtimeBrainMissingSpeechStopPresentationTask != nil {
            return
        }
        cancelRealtimeBrainMissingSpeechStopPresentation()
        realtimeBrainMissingSpeechStopPresentationIdentity = identity
        realtimeBrainMissingSpeechStopPresentationTask = Task {
            @MainActor [weak self] in
            do {
                try await Task.sleep(
                    for: Self
                        .realtimeBrainMissingSpeechStopPresentationDelay
                )
            } catch {
                return
            }
            guard let self,
                  self.realtimeBrainMissingSpeechStopPresentationIdentity
                    == identity,
                  self.isCurrentRealtimeBrainRoute(
                    attemptID: attemptID,
                    session: identity.session
                  ),
                  self.realtimeFullDuplexSpeechStatus.phase == .processing,
                  self.realtimeBrainPlaybackResponseID == nil,
                  self.realtimeBrainGenerationTransitionID == nil,
                  !self.hasObservedRealtimeBrainUserSpeechStop(
                    matching: identity
                  )
            else { return }
            self.realtimeBrainMissingSpeechStopPresentationTask = nil
            self.realtimeBrainMissingSpeechStopPresentationIdentity = nil
            self.updateRealtimeFullDuplexSpeechStatus(
                .listening,
                generation: identity.session.generation,
                lastErrorCode: nil
            )
            self.residentSpeechSignal = .ended
            self.refreshResidentVisualIntent(
                visualStateMode: ResidentVisualIntent.listening.rawValue
            )
            #if DEBUG
            self.recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "missing_speech_stop_presentation_recovered",
                routeKind: .realtimeBrain,
                turnGeneration: identity.session.generation,
                stateAfter: FormalSpeechRoutePhase.listening.rawValue
            )
            #endif
            self.refreshParticleDebugSnapshot()
        }
    }

    private func settleAbandonedRealtimeBrainStart(
        result: Result<
            RealtimeBrainSessionIdentity,
            RealtimeResidentBrainError
        >,
        captureGeneration: UInt64
    ) async {
        realtimeBrainPreparedCaptureGeneration = nil
        speechAudioHostSnapshot = await speechAudioHost
            .cancelPreparedCapture(generation: captureGeneration)
        guard case .success(let session) = result else { return }
        let closeResult = await orchestrationKernel
            .stopRealtimeResidentBrainInput(session: session)
        if case .failure(let error) = closeResult {
            realtimeBrainInputBinding = MacSpeechRealtimeBrainInputBinding(
                session: session,
                captureGeneration: captureGeneration
            )
            publishRealtimeResidentBrainRouteFailure(
                Self.realtimeResidentBrainErrorCode(error)
            )
        }
    }

    private func consumeRealtimeResidentBrainEvent(
        _ event: RealtimeResidentBrainEvent
    ) async {
        guard let attemptID = realtimeBrainRouteAttemptID,
              let binding = realtimeBrainInputBinding,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ),
              event.identity.session == binding.session else { return }
        #if DEBUG
        recordRealtimeSpeechDiagnostic(
            source: .providerEvent,
            category: Self.realtimeResidentBrainEventCategory(event.kind),
            routeKind: .realtimeBrain,
            interactionShortID: String(
                binding.session.brainLeaseID.uuidString.prefix(8)
            ),
            turnGeneration: binding.session.generation,
            disposition: "accepted",
            responseCorrelationHash: event.identity.responseID.map {
                String($0.rawValue.uuidString.prefix(8))
            },
            itemCorrelationHash: event.identity.turnID.map {
                String($0.rawValue.uuidString.prefix(8))
            }
        )
        #endif
        switch event.kind {
        case .sessionReady:
            resetRealtimeBrainMissingSpeechStopPresentation()
            updateRealtimeFullDuplexSpeechStatus(
                .listening,
                generation: binding.session.generation,
                lastErrorCode: nil
            )
        case .userTranscriptFinal:
            if realtimePassiveBackchannelPresentation?.contains(
                event.identity
            ) == true {
                break
            } else if realtimeBrainPlaybackResponseID == nil,
               realtimeBrainGenerationTransitionID == nil {
                updateRealtimeFullDuplexSpeechStatus(
                    .processing,
                    generation: binding.session.generation,
                    lastErrorCode: nil
                )
                refreshResidentVisualIntent(
                    visualStateMode: ResidentVisualIntent.thinking.rawValue
                )
                scheduleRealtimeBrainMissingSpeechStopPresentationRecovery(
                    identity: event.identity,
                    attemptID: attemptID
                )
            }
        case .residentAudioDelta(let audio):
            cancelRealtimeBrainMissingSpeechStopPresentation()
            await enqueueRealtimeResidentBrainAudio(
                audio,
                identity: event.identity,
                attemptID: attemptID
            )
        case .residentSpeakingStopped:
            await finishRealtimeResidentBrainPlayback(
                identity: event.identity,
                attemptID: attemptID
            )
        case .residentTextDelta, .residentTextFinal,
             .residentSemanticFinal:
            cancelRealtimeBrainMissingSpeechStopPresentation()
            if realtimeBrainSubtitlePresentation.consume(event) {
                syncRealtimeBrainSubtitlePresentation()
            }
        case .error(let error):
            resetRealtimeBrainMissingSpeechStopPresentation()
            let shouldClearPlayback = realtimeBrainPlaybackGeneration != nil
            let playbackIdentity = realtimeBrainPlaybackEventIdentity
            if let playbackIdentity {
                orchestrationKernel
                    .settleRealtimeResidentBrainPlaybackTarget(
                        playbackIdentity
                    )
            }
            realtimeBrainSubtitlePresentation.retire(playbackIdentity)
            syncRealtimeBrainSubtitlePresentation()
            realtimeBrainPlaybackResponseID = nil
            realtimeBrainPlaybackEventIdentity = nil
            realtimeBrainPlaybackProviderFinishedResponseID = nil
            realtimeBrainPlaybackGeneration = nil
            if shouldClearPlayback {
                let snapshot = await speechAudioOutputHost.clear()
                guard isCurrentRealtimeBrainRoute(
                    attemptID: attemptID,
                    session: binding.session
                ) else { return }
                speechAudioOutputHostSnapshot = snapshot
            }
            #if DEBUG
            let recoverableErrorCode = Self.realtimeResidentBrainErrorCode(
                error
            )
            realtimeBrainRecoverableResponseErrorCount &+= 1
            lastRealtimeBrainRecoverableResponseErrorCode =
                recoverableErrorCode
            recordRealtimeSpeechDiagnostic(
                source: .providerEvent,
                category: "recoverable_response_error",
                routeKind: .realtimeBrain,
                turnGeneration: binding.session.generation,
                disposition: "returned_to_listening",
                errorCode: recoverableErrorCode
            )
            #endif
            updateRealtimeFullDuplexSpeechStatus(
                .listening,
                generation: binding.session.generation,
                lastErrorCode: nil
            )
            residentSpeechSignal = .ended
            refreshResidentVisualIntent(
                visualStateMode: ResidentVisualIntent.listening.rawValue
            )
        case .interruptionProposed:
            await consumeRealtimeResidentBrainInterruptionDecision(
                await orchestrationKernel
                    .claimRealtimeResidentBrainInterruptionDecision(
                        for: event
                    ),
                attemptID: attemptID,
                expectedSession: binding.session
            )
        case .sessionClosed, .cancelled:
            resetRealtimeBrainMissingSpeechStopPresentation()
            realtimeBrainSubtitlePresentation.retire(
                realtimeBrainPlaybackEventIdentity
            )
            syncRealtimeBrainSubtitlePresentation()
        case .userSpeechStarted:
            observeRealtimeBrainUserSpeechStarted()
            await consumeRealtimeResidentBrainInterruptionDecision(
                await orchestrationKernel
                    .claimRealtimeResidentBrainInterruptionDecision(
                        for: event
                    ),
                attemptID: attemptID,
                expectedSession: binding.session
            )
        case .userSpeechStopped:
            observeRealtimeBrainUserSpeechStopped(event.identity)
        case .residentSpeakingStarted:
            cancelRealtimeBrainMissingSpeechStopPresentation()
        case .userTranscriptPartial, .toolCall:
            break
        }
        if isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: binding.session
        ) {
            refreshParticleDebugSnapshot()
        }
    }

    private func consumeRealtimePassiveBackchannelPresentation(
        _ presentation: RealtimePassiveBackchannelPresentation
    ) {
        guard let attemptID = realtimeBrainRouteAttemptID,
              let binding = realtimeBrainInputBinding,
              presentation.session == binding.session,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else { return }
        cancelRealtimeBrainMissingSpeechStopPresentation()
        if let current = realtimePassiveBackchannelPresentation,
           current.session == presentation.session,
           current.contextRevision == presentation.contextRevision {
            realtimePassiveBackchannelPresentation =
                RealtimePassiveBackchannelPresentation(
                    session: presentation.session,
                    contextRevision: presentation.contextRevision,
                    turnIDs: current.turnIDs.union(presentation.turnIDs)
                )
        } else {
            realtimePassiveBackchannelPresentation = presentation
        }
        guard realtimeBrainPlaybackResponseID == nil,
              realtimeBrainGenerationTransitionID == nil else { return }
        updateRealtimeFullDuplexSpeechStatus(
            .listening,
            generation: binding.session.generation,
            lastErrorCode: nil
        )
        residentSpeechSignal = .ended
        refreshResidentVisualIntent(
            visualStateMode: ResidentVisualIntent.listening.rawValue
        )
        refreshParticleDebugSnapshot()
    }

    private func observeRealtimeResidentBrainAcoustics(
        _ observation: RealtimeAcousticObservation
    ) async -> RealtimeAcousticObservationDisposition {
        guard let attemptID = realtimeBrainRouteAttemptID,
              let binding = realtimeBrainInputBinding,
              observation.identity.session == binding.session,
              observation.identity.captureGeneration
                == binding.captureGeneration,
              realtimeBrainGenerationTransitionID == nil,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else {
            return .ignored(.staleIdentity)
        }
        return orchestrationKernel
            .observeRealtimeResidentBrainAcoustics(observation)
    }

    private func consumeRealtimeResidentBrainAcousticObservation(
        _ observation: MacSpeechRealtimeBrainAcousticObservation
    ) async {
        guard let attemptID = realtimeBrainRouteAttemptID,
              let binding = realtimeBrainInputBinding,
              let playbackIdentity = realtimeBrainPlaybackEventIdentity,
              observation.session == binding.session,
              observation.captureGeneration == binding.captureGeneration,
              playbackIdentity.session == binding.session,
              playbackIdentity.responseID == realtimeBrainPlaybackResponseID,
              playbackIdentity.turnID != nil,
              playbackIdentity.responseID != nil,
              realtimeBrainGenerationTransitionID == nil,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else { return }
        guard let currentAcousticSnapshot = await speechAudioHost
            .residentAcousticSnapshot(),
              observation.matchesCurrentPlayback(currentAcousticSnapshot),
              realtimeBrainRouteAttemptID == attemptID,
              realtimeBrainInputBinding == binding,
              realtimeBrainPlaybackEventIdentity == playbackIdentity,
              realtimeBrainPlaybackResponseID == playbackIdentity.responseID,
              realtimeBrainGenerationTransitionID == nil,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else { return }
        let evidence = RealtimeInterruptionEvidence(
                identity: RealtimeInterruptionEvidenceIdentity(
                    session: binding.session,
                    turnID: playbackIdentity.turnID,
                    responseID: playbackIdentity.responseID,
                    contextRevision: playbackIdentity.contextRevision,
                    sequence: observation.sequence,
                    timestampNanoseconds: observation.timestampNanoseconds
                ),
                source: .acousticHost(observation.facts)
        )
        await consumeRealtimeResidentBrainInterruptionDecision(
            await orchestrationKernel
                .submitRealtimeResidentBrainEligibleAcousticEvidence(
                    observation: observation.observation,
                    evidence: evidence
                ),
            attemptID: attemptID,
            expectedSession: binding.session
        )
    }

    private func consumeRealtimeResidentBrainInterruptionDecision(
        _ result: Result<
            RealtimeInterruptionDecision,
            RealtimeResidentBrainError
        >,
        attemptID: UUID,
        expectedSession: RealtimeBrainSessionIdentity
    ) async {
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: expectedSession
        ) else { return }
        switch result {
        case .success(.ignored), .success(.observed):
            return
        case .success(.confirmed(let decision)):
            await applyConfirmedRealtimeResidentBrainInterruption(
                decision,
                attemptID: attemptID
            )
        case .failure(let error):
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: Self.realtimeResidentBrainErrorCode(error)
            )
        }
    }

    private func enqueueRealtimeResidentBrainAudio(
        _ audio: RealtimeBrainAudioDelta,
        identity: RealtimeBrainEventIdentity,
        attemptID: UUID
    ) async {
        guard let binding = realtimeBrainInputBinding,
              identity.session == binding.session,
              realtimeBrainGenerationTransitionID == nil,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else { return }
        guard let responseID = identity.responseID,
              audio.format == RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: Int(MacSpeechPCMOutputFormat.sampleRate),
                channelCount: Int(MacSpeechPCMOutputFormat.channelCount)
              ),
              audio.provenance == .providerGenerated else {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: "invalid_audio_format"
            )
            return
        }

        if let activeResponseID = realtimeBrainPlaybackResponseID,
           activeResponseID != responseID {
            guard realtimeBrainPlaybackProviderFinishedResponseID
                    == activeResponseID else {
                await stopRealtimeResidentBrainRoute(
                    expectedAttemptID: attemptID,
                    errorCode: "overlapping_audio_response"
                )
                return
            }
            let current = await speechAudioOutputHost.currentSnapshot()
            guard isCurrentRealtimeBrainRoute(
                attemptID: attemptID,
                session: binding.session
            ), realtimeBrainGenerationTransitionID == nil else { return }
            switch current.state {
            case .completed:
                break
            case .prepared, .playing, .stalled, .draining:
                let completed = await waitForRealtimeBrainPlaybackDrain(
                    attemptID: attemptID,
                    session: binding.session,
                    responseID: activeResponseID
                )
                guard completed else { return }
            case .idle, .stopped, .failed, .closed:
                await stopRealtimeResidentBrainRoute(
                    expectedAttemptID: attemptID,
                    errorCode: "playback_boundary_failed"
                )
                return
            }
            guard isCurrentRealtimeBrainRoute(
                attemptID: attemptID,
                session: binding.session
            ), realtimeBrainGenerationTransitionID == nil else { return }
            let settled = await speechAudioOutputHost.currentSnapshot()
            guard isCurrentRealtimeBrainRoute(
                attemptID: attemptID,
                session: binding.session
            ), realtimeBrainGenerationTransitionID == nil else { return }
            guard settled.state == .completed else {
                await stopRealtimeResidentBrainRoute(
                    expectedAttemptID: attemptID,
                    errorCode: "playback_boundary_failed"
                )
                return
            }
            if let completedIdentity = realtimeBrainPlaybackEventIdentity {
                orchestrationKernel
                    .settleRealtimeResidentBrainPlaybackTarget(
                        completedIdentity
                    )
            }
            realtimeBrainPlaybackResponseID = nil
            realtimeBrainPlaybackEventIdentity = nil
            realtimeBrainPlaybackProviderFinishedResponseID = nil
            realtimeBrainPlaybackGeneration = nil
        }

        if realtimeBrainPlaybackResponseID == nil {
            let prepared = await speechAudioOutputHost.prepare()
            guard isCurrentRealtimeBrainRoute(
                attemptID: attemptID,
                session: binding.session
            ), realtimeBrainGenerationTransitionID == nil else { return }
            guard prepared.state == .prepared else {
                await stopRealtimeResidentBrainRoute(
                    expectedAttemptID: attemptID,
                    errorCode: prepared.lastError ?? "playback_prepare_failed"
                )
                return
            }
            speechAudioOutputHostSnapshot = prepared
            switch orchestrationKernel
                .registerRealtimeResidentBrainPlaybackTarget(identity) {
            case .success:
                break
            case .failure(let error):
                await stopRealtimeResidentBrainRoute(
                    expectedAttemptID: attemptID,
                    errorCode: Self.realtimeResidentBrainErrorCode(error)
                )
                return
            }
            realtimeBrainPlaybackResponseID = responseID
            realtimeBrainPlaybackEventIdentity = identity
            realtimeBrainPlaybackProviderFinishedResponseID = nil
            realtimeBrainPlaybackGeneration = prepared.generation
        }

        guard realtimeBrainPlaybackResponseID == responseID,
              realtimeBrainPlaybackEventIdentity == identity,
              realtimeBrainGenerationTransitionID == nil,
              let playbackGeneration = realtimeBrainPlaybackGeneration else {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: "invalid_playback_identity"
            )
            return
        }
        var snapshot = await speechAudioOutputHost.enqueue(
            pcm16Bytes: audio.bytes,
            sequence: audio.sequence,
            generation: playbackGeneration
        )
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: binding.session
        ), realtimeBrainGenerationTransitionID == nil,
           realtimeBrainPlaybackResponseID == responseID,
           realtimeBrainPlaybackGeneration == playbackGeneration else {
            return
        }
        if snapshot.state == .prepared || snapshot.state == .completed {
            snapshot = await speechAudioOutputHost.start()
            guard isCurrentRealtimeBrainRoute(
                attemptID: attemptID,
                session: binding.session
            ), realtimeBrainGenerationTransitionID == nil,
               realtimeBrainPlaybackResponseID == responseID,
               realtimeBrainPlaybackGeneration == playbackGeneration else {
                return
            }
        }
        speechAudioOutputHostSnapshot = snapshot
        if snapshot.state == .failed {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: snapshot.lastError ?? "playback_failed"
            )
        }
    }

    private func finishRealtimeResidentBrainPlayback(
        identity: RealtimeBrainEventIdentity,
        attemptID: UUID
    ) async {
        guard isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: identity.session
              ),
              realtimeBrainGenerationTransitionID == nil,
              identity.responseID == realtimeBrainPlaybackResponseID,
              let playbackGeneration = realtimeBrainPlaybackGeneration else {
            return
        }
        let snapshot = await speechAudioOutputHost
            .finishProviderResponse(generation: playbackGeneration)
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: identity.session
        ), realtimeBrainGenerationTransitionID == nil,
           identity.responseID == realtimeBrainPlaybackResponseID,
           playbackGeneration == realtimeBrainPlaybackGeneration else {
            return
        }
        speechAudioOutputHostSnapshot = snapshot
        if snapshot.state == .failed {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: snapshot.lastError
                    ?? "playback_failed"
            )
            return
        }
        realtimeBrainPlaybackProviderFinishedResponseID = identity.responseID
    }

    private func consumeRealtimeResidentBrainPlaybackEvent(
        _ event: MacSpeechAudioOutputEvent,
        attemptID: UUID,
        session: RealtimeBrainSessionIdentity
    ) async {
        guard isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: session
              ),
              realtimeBrainGenerationTransitionID == nil,
              event.generation == realtimeBrainPlaybackGeneration else {
            return
        }
        switch event.kind {
        case .playbackStarted:
            updateRealtimeFullDuplexSpeechStatus(
                .speaking,
                generation: realtimeBrainInputBinding?.session.generation,
                lastErrorCode: nil
            )
            residentSpeechSignal = ResidentSpeechSignal(
                phase: .started,
                intensity: ParticleTuning.Engine.defaultSpeechIntensity
            )
            refreshResidentVisualIntent(
                visualStateMode: ResidentVisualIntent.speaking.rawValue
            )
        case .playbackCompleted:
            if let completedIdentity = realtimeBrainPlaybackEventIdentity {
                orchestrationKernel
                    .settleRealtimeResidentBrainPlaybackTarget(
                        completedIdentity
                    )
            }
            realtimeBrainSubtitlePresentation.retire(
                realtimeBrainPlaybackEventIdentity
            )
            syncRealtimeBrainSubtitlePresentation()
            realtimeBrainPlaybackResponseID = nil
            realtimeBrainPlaybackEventIdentity = nil
            realtimeBrainPlaybackProviderFinishedResponseID = nil
            realtimeBrainPlaybackGeneration = nil
            resumeRealtimeBrainPlaybackDrainWaiter(completed: true)
            updateRealtimeFullDuplexSpeechStatus(
                .listening,
                generation: realtimeBrainInputBinding?.session.generation,
                lastErrorCode: nil
            )
            residentSpeechSignal = .ended
            refreshResidentVisualIntent(
                visualStateMode: ResidentVisualIntent.listening.rawValue
            )
        case .failed:
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: event.error?.rawValue ?? "playback_failed"
            )
        case .stopped, .closed:
            if !realtimeBrainStopping {
                await stopRealtimeResidentBrainRoute(
                    expectedAttemptID: attemptID,
                    errorCode: "playback_stopped"
                )
            }
        case .prepared, .firstChunkQueued, .playbackStalled,
             .playbackResumed, .bufferPressure, .bufferLow,
             .bufferUnderrun, .outputSafetyLimited, .chunkPlayed:
            break
        }
        if isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: session
        ) {
            refreshParticleDebugSnapshot()
        }
    }

    private func realtimeResidentBrainSessionEnded(
        session: RealtimeBrainSessionIdentity,
        error: RealtimeResidentBrainError?
    ) async {
        guard let attemptID = realtimeBrainRouteAttemptID,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: session
              ) else { return }
        await stopRealtimeResidentBrainRoute(
            expectedAttemptID: attemptID,
            errorCode: error.map(Self.realtimeResidentBrainErrorCode)
        )
    }

    private func waitForRealtimeBrainPlaybackDrain(
        attemptID: UUID,
        session: RealtimeBrainSessionIdentity,
        responseID: RealtimeBrainResponseID
    ) async -> Bool {
        guard realtimeBrainPlaybackDrainWaiter == nil else { return false }
        return await withCheckedContinuation { continuation in
            guard isCurrentRealtimeBrainRoute(
                      attemptID: attemptID,
                      session: session
                  ), realtimeBrainGenerationTransitionID == nil else {
                continuation.resume(returning: false)
                return
            }
            guard realtimeBrainPlaybackResponseID == responseID else {
                continuation.resume(returning: true)
                return
            }
            realtimeBrainPlaybackDrainWaiter = continuation
        }
    }

    private func resumeRealtimeBrainPlaybackDrainWaiter(
        completed: Bool = false
    ) {
        let waiter = realtimeBrainPlaybackDrainWaiter
        realtimeBrainPlaybackDrainWaiter = nil
        waiter?.resume(returning: completed)
    }

    private func applyConfirmedRealtimeResidentBrainInterruption(
        _ decision: RealtimeConfirmedInterruption,
        attemptID: UUID
    ) async {
        guard realtimeBrainRouteAttemptID == attemptID,
              let binding = realtimeBrainInputBinding,
              binding.session == decision.interruptedIdentity,
              decision.hostCommand == .clearPlayback,
              realtimeBrainGenerationTransitionID == nil,
              realtimeBrainGenerationTransitionTask == nil,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else { return }
        if let playbackIdentity = realtimeBrainPlaybackEventIdentity,
           playbackIdentity.session != decision.interruptedIdentity
                || playbackIdentity.turnID != decision.turnID
                || playbackIdentity.responseID != decision.responseID {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: "interruption_playback_identity_mismatch"
            )
            return
        }

        let transitionID = UUID()
        realtimeBrainGenerationTransitionID = transitionID
        realtimeBrainSubtitlePresentation.retire(
            realtimeBrainPlaybackEventIdentity
        )
        syncRealtimeBrainSubtitlePresentation()

        realtimeBrainInputBridgeSnapshot = await realtimeBrainInputBridge
            .suspendForGenerationTransition(session: binding.session)
        guard realtimeBrainGenerationTransitionID == transitionID,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else {
            if realtimeBrainGenerationTransitionID == transitionID {
                realtimeBrainGenerationTransitionID = nil
            }
            return
        }
        realtimeBrainOutputBridgeSnapshot = await realtimeBrainOutputBridge
            .suspendForGenerationTransition(session: binding.session)
        guard realtimeBrainGenerationTransitionID == transitionID,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else {
            if realtimeBrainGenerationTransitionID == transitionID {
                realtimeBrainGenerationTransitionID = nil
            }
            return
        }
        realtimeBrainPlaybackResponseID = nil
        realtimeBrainPlaybackEventIdentity = nil
        realtimeBrainPlaybackProviderFinishedResponseID = nil
        realtimeBrainPlaybackGeneration = nil
        resumeRealtimeBrainPlaybackDrainWaiter()
        let clearedOutput = await speechAudioOutputHost.clear()
        guard realtimeBrainGenerationTransitionID == transitionID,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: binding.session
              ) else {
            if realtimeBrainGenerationTransitionID == transitionID {
                realtimeBrainGenerationTransitionID = nil
            }
            return
        }
        speechAudioOutputHostSnapshot = clearedOutput

        let transitionTask = Task { [orchestrationKernel] in
            await orchestrationKernel
                .completeRealtimeResidentBrainInterruption(decision)
        }
        realtimeBrainGenerationTransitionTask = transitionTask
        let result = await transitionTask.value
        guard realtimeBrainGenerationTransitionID == transitionID else {
            return
        }
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: binding.session
        ) else { return }
        guard case .success(let nextIdentity) = result,
              nextIdentity == decision.nextIdentity else {
            realtimeBrainGenerationTransitionTask = nil
            realtimeBrainGenerationTransitionID = nil
            let errorCode: String
            if case .failure(let error) = result {
                errorCode = Self.realtimeResidentBrainErrorCode(error)
            } else {
                errorCode = "interruption_generation_mismatch"
            }
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: errorCode
            )
            return
        }

        let nextBinding = MacSpeechRealtimeBrainInputBinding(
            session: nextIdentity,
            captureGeneration: binding.captureGeneration
        )
        realtimeBrainInputBinding = nextBinding
        await speechAudioOutputHost.setEventSink { [weak self] event in
            await self?.consumeRealtimeResidentBrainPlaybackEvent(
                event,
                attemptID: attemptID,
                session: nextIdentity
            )
        }
        guard isCurrentRealtimeBrainRoute(
            attemptID: attemptID,
            session: nextIdentity
        ), realtimeBrainGenerationTransitionID == transitionID else { return }
        realtimeBrainOutputBridgeSnapshot = await realtimeBrainOutputBridge
            .resumeAfterGenerationTransition(session: nextIdentity)
        guard realtimeBrainOutputBridgeSnapshot.hasActiveReceiveLoop,
              realtimeBrainGenerationTransitionID == transitionID,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: nextIdentity
              ) else {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: "output_bridge_rebind_failed"
            )
            return
        }
        realtimeBrainInputBridgeSnapshot = await realtimeBrainInputBridge
            .resumeAfterGenerationTransition(session: nextIdentity)
        guard realtimeBrainInputBridgeSnapshot.hasActivePump,
              realtimeBrainGenerationTransitionID == transitionID,
              isCurrentRealtimeBrainRoute(
                  attemptID: attemptID,
                  session: nextIdentity
              ) else {
            await stopRealtimeResidentBrainRoute(
                expectedAttemptID: attemptID,
                errorCode: "input_bridge_rebind_failed"
            )
            return
        }
        realtimeBrainGenerationTransitionID = nil
        realtimeBrainGenerationTransitionTask = nil
        resetRealtimeBrainMissingSpeechStopPresentation()
        realtimePassiveBackchannelPresentation = nil
        updateRealtimeFullDuplexSpeechStatus(
            .listening,
            generation: nextIdentity.generation,
            lastErrorCode: nil
        )
        residentSpeechSignal = .ended
        refreshResidentVisualIntent(
            visualStateMode: ResidentVisualIntent.listening.rawValue
        )
        refreshParticleDebugSnapshot()
    }

    private func stopRealtimeResidentBrainRoute(
        expectedAttemptID: UUID? = nil,
        errorCode: String? = nil
    ) async {
        if let expectedAttemptID,
           realtimeBrainRouteAttemptID != expectedAttemptID {
            return
        }
        let binding = realtimeBrainInputBinding
        let preparedCaptureGeneration =
            realtimeBrainPreparedCaptureGeneration
        let generationTransitionTask =
            realtimeBrainGenerationTransitionTask
        guard !realtimeBrainStopping,
              realtimeBrainRouteAttemptID != nil
                || binding != nil
                || preparedCaptureGeneration != nil else { return }

        realtimeBrainRouteAttemptID = nil
        realtimeBrainStopping = true
        resetRealtimeBrainMissingSpeechStopPresentation()
        updateRealtimeFullDuplexSpeechStatus(
            .stopping,
            generation: binding?.session.generation,
            lastErrorCode: nil
        )
        realtimeBrainPreparedCaptureGeneration = nil
        if let playbackIdentity = realtimeBrainPlaybackEventIdentity {
            orchestrationKernel
                .settleRealtimeResidentBrainPlaybackTarget(playbackIdentity)
        }
        realtimeBrainPlaybackResponseID = nil
        realtimeBrainPlaybackEventIdentity = nil
        realtimeBrainPlaybackProviderFinishedResponseID = nil
        realtimeBrainPlaybackGeneration = nil
        realtimePassiveBackchannelPresentation = nil
        realtimeBrainSubtitlePresentation.reset()
        syncRealtimeBrainSubtitlePresentation()
        resumeRealtimeBrainPlaybackDrainWaiter()

        realtimeBrainInputBridgeSnapshot = await realtimeBrainInputBridge
            .stopForwarding()
        realtimeBrainOutputBridgeSnapshot = await realtimeBrainOutputBridge
            .stop()
        speechAudioOutputHostSnapshot = await speechAudioOutputHost.close()
        if let preparedCaptureGeneration {
            speechAudioHostSnapshot = await speechAudioHost
                .cancelPreparedCapture(
                    generation: preparedCaptureGeneration
                )
        }
        speechAudioHostSnapshot = await speechAudioHost.stopCapture()

        var closeIdentity = binding?.session
        if let generationTransitionTask {
            if case .success(let nextIdentity) =
                await generationTransitionTask.value {
                closeIdentity = nextIdentity
            }
        }
        realtimeBrainGenerationTransitionTask = nil
        realtimeBrainGenerationTransitionID = nil
        let closeResult: Result<Void, RealtimeResidentBrainError>
        if let closeIdentity {
            closeResult = await orchestrationKernel
                .stopRealtimeResidentBrainInput(session: closeIdentity)
        } else {
            closeResult = .success(())
        }
        let closeError: RealtimeResidentBrainError?
        switch closeResult {
        case .success:
            closeError = nil
            realtimeBrainInputBinding = nil
            realtimeBrainInputBridgeSnapshot = await realtimeBrainInputBridge
                .settleExternalCloseSuccess(session: closeIdentity)
        case .failure(let error):
            closeError = error
            if let closeIdentity, let binding {
                realtimeBrainInputBinding = MacSpeechRealtimeBrainInputBinding(
                    session: closeIdentity,
                    captureGeneration: binding.captureGeneration
                )
            }
            realtimeBrainInputBridgeSnapshot = await realtimeBrainInputBridge
                .fail(error)
        }
        let finalErrorCode = closeError.map(
            Self.realtimeResidentBrainErrorCode
        ) ?? errorCode
        let finalPhase: RealtimeFullDuplexSpeechPhase =
            finalErrorCode == nil ? .idle : .failed
        updateRealtimeFullDuplexSpeechStatus(
            finalPhase,
            generation: closeError == nil
                ? nil : closeIdentity?.generation,
            lastErrorCode: finalErrorCode
        )
        residentSpeechSignal = .ended
        runtimeState = closeError == nil ? .idle : .cancelled
        refreshResidentVisualIntent()
        #if DEBUG
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: finalErrorCode == nil
                ? "realtime_brain_route_stopped"
                : "realtime_brain_route_failed",
            routeKind: .realtimeBrain,
            turnGeneration: closeIdentity?.generation,
            stateAfter: finalPhase.rawValue,
            errorCode: finalErrorCode
        )
        #endif
        realtimeBrainStopping = false
        objectWillChange.send()
        refreshParticleDebugSnapshot()
    }

    private func isCurrentRealtimeBrainRoute(
        attemptID: UUID,
        session: RealtimeBrainSessionIdentity? = nil
    ) -> Bool {
        guard realtimeBrainRouteAttemptID == attemptID,
              !realtimeBrainStopping else { return false }
        if let session {
            return realtimeBrainInputBinding?.session == session
        }
        return true
    }

    private func publishRealtimeResidentBrainRouteFailure(
        _ errorCode: String
    ) {
        updateRealtimeFullDuplexSpeechStatus(
            .failed,
            generation: realtimeBrainInputBinding?.session.generation,
            lastErrorCode: errorCode
        )
        #if DEBUG
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "realtime_brain_route_start_failed",
            routeKind: .realtimeBrain,
            stateAfter: FormalSpeechRoutePhase.failed.rawValue,
            errorCode: errorCode
        )
        #endif
    }

    private func updateRealtimeFullDuplexSpeechStatus(
        _ phase: RealtimeFullDuplexSpeechPhase,
        generation: UInt64?,
        lastErrorCode: String?
    ) {
        realtimeFullDuplexSpeechStatus = RealtimeFullDuplexSpeechStatus(
            phase: phase,
            lastErrorCode: lastErrorCode
        )
        #if DEBUG
        formalSpeechRouteDebugSnapshot = FormalSpeechRouteDebugSnapshot(
            phase: phase,
            generation: generation,
            lastErrorCode: lastErrorCode
        )
        #endif
    }

    private static func realtimeResidentBrainErrorCode(
        _ error: RealtimeResidentBrainError
    ) -> String {
        switch error {
        case .unavailable: "unavailable"
        case .voiceBindingUnavailable: "voice_binding_unavailable"
        case .invalidIdentity: "invalid_identity"
        case .invalidContextRevision: "invalid_context_revision"
        case .invalidAudioFrame: "invalid_audio_frame"
        case .operationInFlight: "operation_in_flight"
        case .invalidEvent: "invalid_event"
        case .timedOut: "timed_out"
        case .cancelled: "cancelled"
        case .transportFailure: "transport_failure"
        case .providerFailure: "provider_failure"
        }
    }

    private func syncRealtimeBrainSubtitlePresentation() {
        let displayText = realtimeBrainSubtitlePresentation.displayText
        let subtitleState = displayText.map {
            ParticleSubtitleState(text: $0, phase: .showing)
        } ?? .hidden
        if particleSubtitleState != subtitleState {
            particleSubtitleState = subtitleState
            #if DEBUG
            let identity = realtimeBrainSubtitlePresentation.identity
            recordRealtimeSpeechDiagnostic(
                source: .subtitle,
                category: displayText == nil
                    ? "formal_subtitle_hidden"
                    : "formal_subtitle_presented",
                routeKind: .realtimeBrain,
                turnGeneration: identity?.session.generation
                    ?? realtimeBrainInputBinding?.session.generation,
                disposition: "accepted_formal_realtime_event",
                responseCorrelationHash: identity?.responseID.map {
                    String($0.rawValue.uuidString.prefix(8))
                },
                byteCount: displayText?.utf8.count
            )
            #endif
        }
        refreshParticleDebugSnapshot()
    }

    #if DEBUG
    private static func realtimeResidentBrainEventCategory(
        _ kind: RealtimeResidentBrainEventKind
    ) -> String {
        switch kind {
        case .sessionReady: "session_ready"
        case .sessionClosed: "session_closed"
        case .error: "response_error"
        case .userSpeechStarted: "user_speech_started"
        case .userSpeechStopped: "user_speech_stopped"
        case .userTranscriptPartial: "user_transcript_partial"
        case .userTranscriptFinal: "user_transcript_final"
        case .residentTextDelta: "resident_text_delta"
        case .residentTextFinal: "resident_text_final"
        case .residentAudioDelta: "resident_audio_delta"
        case .residentSpeakingStarted: "resident_speaking_started"
        case .residentSpeakingStopped: "resident_speaking_stopped"
        case .residentSemanticFinal: "resident_semantic_final"
        case .toolCall: "tool_call"
        case .interruptionProposed: "interruption_proposed"
        case .cancelled: "cancelled"
        }
    }

    func startFormalSpeechRoute() async {
        guard formalSpeechRouteGeneration == nil else { return }
        guard speechHostLifecycleOperationCount == 0 else {
            publishFormalSpeechRouteFailure("speech_input_busy")
            return
        }
        // Host capture readiness only; RuntimeCore owns Brain admission.
        guard !speechInputBridgeSnapshot.hasActivePump else {
            publishFormalSpeechRouteFailure("speech_input_busy")
            return
        }
        guard isResidentTextInputAvailable else {
            publishFormalSpeechRouteFailure("resident_unavailable")
            return
        }
        speechAudioHostShutdownCompleted = false
        speechHostLifecycleOperationCount += 1
        defer { speechHostLifecycleOperationCount -= 1 }
        formalSpeechRouteDebugSnapshot = FormalSpeechRouteDebugSnapshot(
            phase: .starting,
            generation: nil,
            lastErrorCode: nil
        )
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "formal_route_start_requested",
            stateAfter: FormalSpeechRoutePhase.starting.rawValue
        )
        guard let captureGeneration =
            await speechAudioHost.prepareCaptureGeneration() else {
            speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
            publishFormalSpeechRouteFailure("capture_unavailable")
            return
        }
        let startResult = await orchestrationKernel.startSpeechRouteASR(
            locale: "zh-CN"
        )
        guard case .success(let generation) = startResult else {
            speechAudioHostSnapshot = await speechAudioHost
                .cancelPreparedCapture(generation: captureGeneration)
            if case .failure(let error) = startResult {
                publishFormalSpeechRouteFailure(
                    Self.formalSpeechErrorCode(error)
                )
            }
            return
        }

        let interactionID = UUID()
        formalSpeechRouteGeneration = generation
        formalSpeechCaptureGeneration = captureGeneration
        formalSpeechInteractionID = interactionID
        formalSpeechUserFinal = nil
        formalSpeechCanonicalResponse = nil
        formalSpeechPlaybackGeneration = nil
        formalSpeechPlaybackCommitted = false
        formalSpeechASRAcceptsAudio = true
        formalSpeechFailingGeneration = nil
        formalSpeechObservedSourceGateOpenCount = speechAudioHost
            .currentAcousticEchoSnapshot()?.sourceGateOpenCount ?? 0
        residentTextPresentationID = nil
        residentSpeechSignal = .ended
        particleSubtitleState = .hidden
        runtimeState = .running
        refreshResidentVisualIntent(
            visualStateMode: ResidentVisualIntent.listening.rawValue
        )
        await speechAudioOutputHost.setEventSink { [weak self] event in
            await self?.consumeFormalSpeechPlaybackEvent(event)
        }
        speechAudioHostSnapshot = await speechAudioHost
            .startPreparedCapture(generation: captureGeneration)
        guard speechAudioHostSnapshot.isCapturing else {
            await failFormalSpeechRoute(
                generation: generation,
                errorCode: "capture_start_failed"
            )
            return
        }
        formalSpeechRouteDebugSnapshot = FormalSpeechRouteDebugSnapshot(
            phase: .listening,
            generation: generation,
            lastErrorCode: nil
        )
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "formal_route_listening",
            turnGeneration: generation,
            stateAfter: FormalSpeechRoutePhase.listening.rawValue
        )

        formalSpeechInputTask = Task { @MainActor [weak self] in
            await self?.pumpFormalSpeechAudio(
                captureGeneration: captureGeneration
            )
        }
        formalSpeechRouteTask = Task { @MainActor [weak self] in
            await self?.receiveFormalSpeechRoute(
                generation: generation,
                interactionID: interactionID
            )
        }
        refreshParticleDebugSnapshot()
    }

    private func pumpFormalSpeechAudio(
        captureGeneration: UInt64
    ) async {
        while !Task.isCancelled,
              formalSpeechCaptureGeneration == captureGeneration,
              await speechAudioHost.isCaptureGenerationActive(
                  captureGeneration
              ) {
            let frames = await speechAudioHost.drainFrames(
                maxCount: MacSpeechAudioInputFormat.frameCapacity
            )
            if frames.isEmpty {
                try? await Task.sleep(for: .milliseconds(5))
                continue
            }
            _ = await handleFormalNearEndSpeechStartedIfNeeded()
            guard formalSpeechASRAcceptsAudio,
                  let generation = formalSpeechRouteGeneration else {
                continue
            }
            for frame in frames {
                guard !Task.isCancelled,
                      formalSpeechRouteGeneration == generation,
                      frame.captureGeneration == captureGeneration else {
                    return
                }
                do {
                    try await orchestrationKernel.sendSpeechRouteASRAudio(
                        ASRAudioInput(
                            generation: generation,
                            sequenceNumber: frame.sequenceNumber,
                            bytes: frame.pcm16Bytes,
                            format: .pcm16,
                            sampleRate: Int(
                                MacSpeechAudioInputFormat.sampleRate
                            ),
                            channelCount: 1,
                            source: .aec3Processed
                        )
                    )
                } catch {
                    if !formalSpeechASRAcceptsAudio,
                       formalSpeechRouteGeneration == generation {
                        recordRealtimeSpeechDiagnostic(
                            source: .lifecycle,
                            category: "formal_route_late_asr_send_ignored",
                            turnGeneration: generation,
                            disposition: "ignored_after_final",
                            errorCode: Self.formalSpeechErrorCode(error)
                        )
                    }
                    guard formalSpeechASRAcceptsAudio,
                          formalSpeechRouteGeneration == generation,
                          !Task.isCancelled else {
                        break
                    }
                    await failFormalSpeechRoute(
                        generation: generation,
                        errorCode: Self.formalSpeechErrorCode(error)
                    )
                    return
                }
            }
        }
    }

    private func receiveFormalSpeechRoute(
        generation: UInt64,
        interactionID: UUID
    ) async {
        while !Task.isCancelled,
              formalSpeechRouteGeneration == generation {
            let event: ASREvent
            do {
                event = try await orchestrationKernel
                    .receiveSpeechRouteASREvent(generation: generation)
            } catch {
                await failFormalSpeechRoute(
                    generation: generation,
                    errorCode: Self.formalSpeechErrorCode(error)
                )
                return
            }
            guard formalSpeechRouteGeneration == generation else { return }
            switch event.kind {
            case .speechActivity(.started):
                residentSpeechSignal = .ended
                refreshResidentVisualIntent(
                    visualStateMode: ResidentVisualIntent.listening.rawValue
                )
            case .speechActivity(.ended):
                break
            case .partialTranscript(let text):
                let normalized = text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !normalized.isEmpty {
                    particleSubtitleState = ParticleSubtitleState(
                        text: normalized,
                        phase: .showing
                    )
                    refreshParticleDebugSnapshot()
                }
            case .finalTranscript:
                await handleFormalSpeechFinal(
                    event,
                    generation: generation,
                    interactionID: interactionID
                )
                return
            case .cancelled:
                await failFormalSpeechRoute(
                    generation: generation,
                    errorCode: "cancelled"
                )
                return
            case .error(let error):
                await failFormalSpeechRoute(
                    generation: generation,
                    errorCode: Self.formalSpeechErrorCode(error)
                )
                return
            case .staleGeneration:
                await failFormalSpeechRoute(
                    generation: generation,
                    errorCode: "stale_generation"
                )
                return
            }
        }
    }

    private func handleFormalSpeechFinal(
        _ event: ASREvent,
        generation: UInt64,
        interactionID: UUID
    ) async {
        guard case .finalTranscript(let transcript) = event.kind else {
            await failFormalSpeechRoute(
                generation: generation,
                errorCode: "invalid_asr_final"
            )
            return
        }
        let userFinal = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !userFinal.isEmpty else {
            await failFormalSpeechRoute(
                generation: generation,
                errorCode: "empty_asr_final"
            )
            return
        }
        formalSpeechUserFinal = userFinal
        formalSpeechASRAcceptsAudio = false
        formalSpeechRouteDebugSnapshot = FormalSpeechRouteDebugSnapshot(
            phase: .processing,
            generation: generation,
            lastErrorCode: nil
        )
        particleSubtitleState = ParticleSubtitleState(
            text: userFinal,
            phase: .showing
        )
        let asrFinishResult = await orchestrationKernel.finishSpeechRouteASR(
            generation: generation
        )
        guard case .success = asrFinishResult else {
            let errorCode: String
            if case .failure(let error) = asrFinishResult {
                errorCode = Self.formalSpeechErrorCode(error)
            } else {
                errorCode = "asr_finish_failed"
            }
            await failFormalSpeechRoute(
                generation: generation,
                errorCode: errorCode
            )
            return
        }
        residentSpeechSignal = .ended
        refreshResidentVisualIntent(
            visualStateMode: ResidentVisualIntent.thinking.rawValue
        )

        let turnResult = await orchestrationKernel.submitSpeechRouteASRFinal(
            event,
            interactionID: interactionID
        )
        guard case .success(let turn) = turnResult,
              formalSpeechRouteGeneration == generation else {
            await failFormalSpeechRoute(
                generation: generation,
                errorCode: "runtime_turn_failed"
            )
            return
        }
        let canonicalText = turn.canonicalResponseText
        formalSpeechCanonicalResponse = canonicalText
        particleExpressionInput = makeParticleExpressionInput(
            from: turn.reply.expression,
            interactionID: interactionID
        )

        let prepared = await speechAudioOutputHost.prepare()
        speechAudioOutputHostSnapshot = prepared
        guard prepared.state == .prepared else {
            await failFormalSpeechRoute(
                generation: generation,
                errorCode: "playback_prepare_failed"
            )
            return
        }
        formalSpeechPlaybackGeneration = prepared.generation
        let ttsResult = await orchestrationKernel.startSpeechRouteTTS(
            request: TTSSynthesisRequest(
                generation: generation,
                canonicalResponseText: canonicalText,
                voiceProfile: SpeechVoiceProfile(
                    profileID: "resident-default",
                    locale: "zh-CN"
                ),
                emotion: nil,
                pace: 1,
                style: nil
            )
        )
        guard case .success = ttsResult else {
            let errorCode: String
            if case .failure(let error) = ttsResult {
                errorCode = Self.formalSpeechErrorCode(error)
            } else {
                errorCode = "tts_start_failed"
            }
            await failFormalSpeechRoute(
                generation: generation,
                errorCode: errorCode
            )
            return
        }
        await receiveFormalSpeechTTS(
            generation: generation,
            playbackGeneration: prepared.generation
        )
    }

    private func receiveFormalSpeechTTS(
        generation: UInt64,
        playbackGeneration: UInt64
    ) async {
        while !Task.isCancelled,
              formalSpeechRouteGeneration == generation {
            let event: TTSEvent
            do {
                event = try await orchestrationKernel
                    .receiveSpeechRouteTTSEvent(generation: generation)
            } catch {
                if formalSpeechInterruptingGeneration == generation
                    || Task.isCancelled {
                    return
                }
                await failFormalSpeechRoute(
                    generation: generation,
                    errorCode: Self.formalSpeechErrorCode(error)
                )
                return
            }
            guard formalSpeechInterruptingGeneration != generation,
                  !Task.isCancelled,
                  formalSpeechRouteGeneration == generation else {
                return
            }
            switch event.kind {
            case .started:
                break
            case .audio(let chunk):
                guard chunk.format == .pcm16,
                      chunk.sampleRate == 24_000,
                      chunk.channelCount == 1 else {
                    await failFormalSpeechRoute(
                        generation: generation,
                        errorCode: "invalid_tts_audio_format"
                    )
                    return
                }
                speechAudioOutputHostSnapshot = await speechAudioOutputHost
                    .enqueue(
                        pcm16Bytes: chunk.bytes,
                        sequence: chunk.sequenceNumber,
                        generation: playbackGeneration
                    )
                speechAudioOutputHostSnapshot = await speechAudioOutputHost
                    .start()
            case .done:
                speechAudioOutputHostSnapshot = await speechAudioOutputHost
                    .finishProviderResponse(generation: playbackGeneration)
                _ = await orchestrationKernel.finishSpeechRouteTTS(
                    generation: generation
                )
                formalSpeechRouteTask = nil
                return
            case .cancelled:
                await failFormalSpeechRoute(
                    generation: generation,
                    errorCode: "cancelled"
                )
                return
            case .error(let error):
                await failFormalSpeechRoute(
                    generation: generation,
                    errorCode: Self.formalSpeechErrorCode(error)
                )
                return
            }
        }
    }

    private func handleFormalNearEndSpeechStartedIfNeeded() async -> Bool {
        guard let snapshot = speechAudioHost.currentAcousticEchoSnapshot()
        else { return false }
        if snapshot.sourceGateOpenCount
                < formalSpeechObservedSourceGateOpenCount {
            formalSpeechObservedSourceGateOpenCount =
                snapshot.sourceGateOpenCount
        }
        guard !formalSpeechASRAcceptsAudio,
              formalSpeechPlaybackGeneration != nil,
              snapshot.mode == .webRTCAEC3,
              snapshot.isPlaybackActive,
              snapshot.sourceGateOpen,
              snapshot.sourceGateOpenCount
                > formalSpeechObservedSourceGateOpenCount,
              let interruptedGeneration = formalSpeechRouteGeneration else {
            return false
        }
        formalSpeechObservedSourceGateOpenCount = snapshot.sourceGateOpenCount

        speechAudioOutputHostSnapshot = await speechAudioOutputHost
            .clearForAcceptedSpeechStart()
        formalSpeechPlaybackGeneration = nil
        formalSpeechInterruptingGeneration = interruptedGeneration

        let interruptResult = await orchestrationKernel
            .interruptSpeechRouteForNearEnd(
                generation: interruptedGeneration,
                locale: "zh-CN"
            )
        guard case .success(let nextGeneration) = interruptResult,
              formalSpeechRouteGeneration == interruptedGeneration else {
            formalSpeechInterruptingGeneration = nil
            await failFormalSpeechRoute(
                generation: interruptedGeneration,
                errorCode: "interrupt_failed"
            )
            return false
        }

        formalSpeechRouteTask?.cancel()
        formalSpeechRouteTask = nil
        let interactionID = UUID()
        formalSpeechRouteGeneration = nextGeneration
        formalSpeechInteractionID = interactionID
        formalSpeechUserFinal = nil
        formalSpeechCanonicalResponse = nil
        formalSpeechPlaybackCommitted = false
        formalSpeechASRAcceptsAudio = true
        formalSpeechRouteDebugSnapshot = FormalSpeechRouteDebugSnapshot(
            phase: .listening,
            generation: nextGeneration,
            lastErrorCode: nil
        )
        formalSpeechInterruptingGeneration = nil
        residentSpeechSignal = .ended
        particleSubtitleState = .hidden
        runtimeState = .running
        refreshResidentVisualIntent(
            visualStateMode: ResidentVisualIntent.listening.rawValue
        )
        formalSpeechRouteTask = Task { @MainActor [weak self] in
            await self?.receiveFormalSpeechRoute(
                generation: nextGeneration,
                interactionID: interactionID
            )
        }
        refreshParticleDebugSnapshot()
        return true
    }

    private func consumeFormalSpeechPlaybackEvent(
        _ event: MacSpeechAudioOutputEvent
    ) async {
        guard let generation = formalSpeechRouteGeneration,
              event.generation == formalSpeechPlaybackGeneration else {
            return
        }
        switch event.kind {
        case .playbackStarted:
            formalSpeechRouteDebugSnapshot = FormalSpeechRouteDebugSnapshot(
                phase: .speaking,
                generation: generation,
                lastErrorCode: nil
            )
            if let canonicalText = formalSpeechCanonicalResponse {
                particleSubtitleState = ParticleSubtitleState(
                    text: canonicalText,
                    phase: .showing
                )
            }
            residentSpeechSignal = ResidentSpeechSignal(
                phase: .started,
                intensity: ParticleTuning.Engine.defaultSpeechIntensity
            )
            refreshResidentVisualIntent(
                visualStateMode: ResidentVisualIntent.speaking.rawValue
            )
            refreshParticleDebugSnapshot()
        case .playbackResumed:
            residentSpeechSignal = ResidentSpeechSignal(
                phase: .sustained,
                intensity: ParticleTuning.Engine.defaultSpeechIntensity
            )
            refreshResidentVisualIntent(
                visualStateMode: ResidentVisualIntent.speaking.rawValue
            )
        case .playbackCompleted:
            guard !formalSpeechPlaybackCommitted else { return }
            formalSpeechPlaybackCommitted = true
            formalSpeechInputTask?.cancel()
            formalSpeechInputTask = nil
            speechAudioHostSnapshot = await speechAudioHost.stopCapture()
            let commitResult = orchestrationKernel
                .commitSpeechRoutePlayback(generation: generation)
            guard case .success = commitResult else {
                await failFormalSpeechRoute(
                    generation: generation,
                    errorCode: "playback_commit_failed"
                )
                return
            }
            projectFormalSpeechDialogueHistory()
            formalSpeechPlaybackGeneration = nil
            _ = await orchestrationKernel.closeSpeechRoute(
                generation: generation
            )
            resetFormalSpeechRouteState()
            formalSpeechRouteDebugSnapshot = .idle
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "formal_route_completed",
                turnGeneration: generation,
                stateAfter: FormalSpeechRoutePhase.idle.rawValue
            )
            residentSpeechSignal = .ended
            runtimeState = .idle
            refreshResidentVisualIntent(
                visualStateMode: ResidentVisualIntent.idle.rawValue
            )
            hideDebugSubtitle()
            refreshParticleDebugSnapshot()
        case .failed, .stopped:
            await failFormalSpeechRoute(
                generation: generation,
                errorCode: "playback_failed"
            )
        default:
            break
        }
    }

    private func projectFormalSpeechDialogueHistory() {
        guard let interactionID = formalSpeechInteractionID,
              let userFinal = formalSpeechUserFinal,
              let canonicalResponse = formalSpeechCanonicalResponse else {
            return
        }
        appendDialogueAuditUser(userFinal)
        appendDialogueAuditResident(
            canonicalResponse,
            displayName: currentAuditResidentDisplayName
        )
        let timestamp = ISO8601DateFormatter().string(from: Date())
        dialogueEntries.append(AppDialogueEntryState(
            id: "user-speech-route-\(interactionID.uuidString)",
            role: "user",
            text: userFinal,
            timestamp: timestamp
        ))
        dialogueEntries.append(AppDialogueEntryState(
            id: "resident-speech-route-\(interactionID.uuidString)",
            role: "resident",
            text: canonicalResponse,
            timestamp: timestamp
        ))
        dialogueEntries = Array(dialogueEntries.suffix(8))
        sessionState.residentID = loadedResidentID
        sessionState.sessionID = loadedSessionID
        sessionState.lastUserInput = userFinal
        sessionState.lastResidentOutput = canonicalResponse
        sessionState.dialogueEntries = dialogueEntries
        completeRuntimeOrchestrationPresentation(
            interactionID: interactionID,
            expectedSessionID: loadedSessionID,
            subtitleState: String(describing: particleSubtitleState.phase),
            particleState: String(describing: residentVisualIntent),
            lifecycleState: .speaking,
            status: .completed
        )
    }

    private func cancelFormalSpeechRoute() async {
        guard let generation = formalSpeechRouteGeneration else { return }
        formalSpeechInputTask?.cancel()
        formalSpeechRouteTask?.cancel()
        formalSpeechInterruptingGeneration = nil
        await failFormalSpeechRoute(
            generation: generation,
            errorCode: "cancelled",
            terminalPhase: .idle
        )
    }

    private func failFormalSpeechRoute(
        generation: UInt64,
        errorCode: String,
        terminalPhase: FormalSpeechRoutePhase = .failed
    ) async {
        guard formalSpeechRouteGeneration == generation,
              formalSpeechInterruptingGeneration != generation,
              formalSpeechFailingGeneration != generation else {
            return
        }
        formalSpeechFailingGeneration = generation
        formalSpeechInputTask?.cancel()
        formalSpeechRouteTask?.cancel()
        formalSpeechInputTask = nil
        formalSpeechRouteTask = nil
        _ = await orchestrationKernel.cancelSpeechRoute(
            generation: generation
        )
        speechAudioHostSnapshot = await speechAudioHost.stopCapture()
        speechAudioOutputHostSnapshot = await speechAudioOutputHost.stop()
        resetFormalSpeechRouteState()
        formalSpeechRouteDebugSnapshot = FormalSpeechRouteDebugSnapshot(
            phase: terminalPhase,
            generation: nil,
            lastErrorCode: terminalPhase == .failed ? errorCode : nil
        )
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: terminalPhase == .failed
                ? "formal_route_failed" : "formal_route_cancelled",
            turnGeneration: generation,
            stateAfter: terminalPhase.rawValue,
            errorCode: errorCode
        )
        residentSpeechSignal = .ended
        runtimeState = .idle
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()
        formalSpeechFailingGeneration = nil
    }

    private func publishFormalSpeechRouteFailure(_ errorCode: String) {
        formalSpeechRouteDebugSnapshot = FormalSpeechRouteDebugSnapshot(
            phase: .failed,
            generation: nil,
            lastErrorCode: errorCode
        )
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "formal_route_start_failed",
            stateAfter: FormalSpeechRoutePhase.failed.rawValue,
            errorCode: errorCode
        )
    }

    private static func formalSpeechErrorCode(
        _ error: Error
    ) -> String {
        guard let error = error as? SpeechRouteError else {
            return "unknown"
        }
        return formalSpeechErrorCode(error)
    }

    private static func formalSpeechErrorCode(
        _ error: SpeechRouteError
    ) -> String {
        switch error {
        case .invalidConfiguration: "invalid_configuration"
        case .unavailable: "unavailable"
        case .timedOut: "timed_out"
        case .cancelled: "cancelled"
        case .transportFailure: "transport_failure"
        case .invalidEvent: "invalid_event"
        case .staleGeneration: "stale_generation"
        }
    }

    private func resetFormalSpeechRouteState() {
        formalSpeechRouteGeneration = nil
        formalSpeechCaptureGeneration = nil
        formalSpeechPlaybackGeneration = nil
        formalSpeechInteractionID = nil
        formalSpeechUserFinal = nil
        formalSpeechCanonicalResponse = nil
        formalSpeechInputTask = nil
        formalSpeechRouteTask = nil
        formalSpeechPlaybackCommitted = false
        formalSpeechASRAcceptsAudio = false
        formalSpeechObservedSourceGateOpenCount = 0
        formalSpeechInterruptingGeneration = nil
    }

    func startNativeSpeechInputBridge() async {
        realtimeSpeechPlaybackSubtitleSynchronizer.resetForInteraction()
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "bridge_start_requested"
        )
        guard speechHostLifecycleOperationCount == 0,
              !speechInputBridgeSnapshot.hasActivePump else {
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "bridge_start_ignored_active"
            )
            return
        }
        speechAudioHostShutdownCompleted = false
        speechHostLifecycleOperationCount += 1
        defer { speechHostLifecycleOperationCount -= 1 }
        guard let captureGeneration =
            await speechAudioHost.prepareCaptureGeneration() else {
            speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
            speechInputBridgeSnapshot =
                await speechInputBridge.fail(.unavailable)
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "bridge_start_failed",
                errorCode: "capture_unavailable"
            )
            return
        }
        speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
        lastDiagnosticAggregateNanoseconds = 0
        lastDiagnosticCaptureGeneratedCount = 0
        lastDiagnosticCaptureDroppedCount = 0
        recordRealtimeSpeechDiagnostic(
            source: .lifecycle,
            category: "capture_prepared"
        )
        let result = await orchestrationKernel.startNativeSpeechInput(
            profile: nativeSpeechProviderDebugState.profile,
            captureGeneration: captureGeneration
        )
        switch result {
        case .success(let binding):
            residentTextPresentationID = nil
            await speechOutputDebugSink.reset()
            nativeSpeechPlaybackBinding = nil
            projectedNativeSpeechDialogueHistoryIdentities.removeAll(
                keepingCapacity: true
            )
            lastPlaybackEventOrdinal = 0
            await speechAudioOutputHost.setEventSink { [weak self] event in
                await self?.consumePlaybackHostEvent(event)
            }
            speechOutputBridgeSnapshot = await speechOutputBridge.start(
                binding: binding
            )
            speechAudioHostSnapshot = await speechAudioHost
                .startPreparedCapture(generation: captureGeneration)
            guard speechAudioHostSnapshot.isCapturing else {
                speechOutputBridgeSnapshot = await speechOutputBridge.stop()
                speechInputBridgeSnapshot =
                    await speechInputBridge.fail(.unavailable)
                recordRealtimeSpeechDiagnostic(
                    source: .lifecycle,
                    category: "bridge_start_failed",
                    errorCode: speechAudioHostSnapshot.lastError
                        ?? "capture_unavailable"
                )
                syncRealtimeSpeechPresentation()
                refreshNativeSpeechPlaybackDebugSnapshot()
                return
            }
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "capture_started",
                interactionShortID: String(
                    binding.interactionID.rawValue.uuidString.prefix(8)
                )
            )
            speechInputBridgeSnapshot = await speechInputBridge.start(
                binding: binding
            )
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "receive_loop_started",
                interactionShortID: String(
                    binding.interactionID.rawValue.uuidString.prefix(8)
                ),
                stateAfter: speechOutputBridgeSnapshot.state.rawValue
            )
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "input_pump_started",
                interactionShortID: String(
                    binding.interactionID.rawValue.uuidString.prefix(8)
                ),
                stateAfter: speechInputBridgeSnapshot.state.rawValue
            )
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "bridge_started",
                interactionShortID: String(
                    binding.interactionID.rawValue.uuidString.prefix(8)
                )
            )
        case .failure(let error):
            speechAudioHostSnapshot = await speechAudioHost
                .cancelPreparedCapture(generation: captureGeneration)
            speechInputBridgeSnapshot = await speechInputBridge.fail(error)
            recordRealtimeSpeechDiagnostic(
                source: .lifecycle,
                category: "bridge_start_failed",
                errorCode: Self.nativeSpeechErrorName(error)
            )
        }
        syncRealtimeSpeechPresentation()
        refreshNativeSpeechPlaybackDebugSnapshot()
    }

    private func consumeNativeSpeechOutputEvent(
        _ event: NativeSpeechEvent
    ) async {
        guard !Task.isCancelled else { return }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let stateBefore = realtimeSpeechStateSnapshot.state.rawValue
        if case .inputSpeechStarted = event.kind {
            residentTextPresentationID = nil
            realtimeSpeechPlaybackSubtitleSynchronizer.reset()
            syncRealtimeSpeechPresentation()
            await commitAcceptedInterruptIfNeeded(
                event,
                startedAtNanoseconds: startedAt
            )
            guard !Task.isCancelled else { return }
        }
        if case .outputAudio(let payload) = event.kind {
            await enqueueNativeSpeechOutput(payload)
            guard !Task.isCancelled else { return }
        }
        await speechOutputDebugSink.consume(event)
        guard !Task.isCancelled else { return }
        switch event.kind {
        case .partialTranscript:
            break
        case .outputText(let text, let isFinal):
            if isFinal {
                guard let binding = nativeSpeechPlaybackBinding,
                      binding.interactionID == event.interactionID,
                      realtimeSpeechPlaybackSubtitleSynchronizer
                        .enqueueFinal(
                            text: text,
                            identity: binding.subtitleIdentity
                        ) else {
                    recordRealtimeSpeechDiagnostic(
                        source: .subtitle,
                        category: "subtitle_playback_identity_unavailable",
                        interactionShortID: String(
                            event.interactionID.rawValue.uuidString.prefix(8)
                        ),
                        turnNumber:
                            realtimeSpeechStateSnapshot.currentTurnNumber,
                        turnGeneration:
                            realtimeSpeechSubtitleSnapshot.turnGeneration,
                        disposition: "final_not_displayed"
                    )
                    break
                }
            } else {
                recordRealtimeSpeechDiagnostic(
                    source: .subtitle,
                    category: "subtitle_partial_unexpected_consumer_path",
                    interactionShortID: String(
                        event.interactionID.rawValue.uuidString.prefix(8)
                    ),
                    turnNumber:
                        realtimeSpeechStateSnapshot.currentTurnNumber,
                    turnGeneration:
                        realtimeSpeechSubtitleSnapshot.turnGeneration,
                    disposition: "bridge_mailbox_bypassed"
                )
            }
            syncRealtimeSpeechPresentation()
        case .outputAudio:
            break
        case .turnFailed:
            realtimeSpeechPlaybackSubtitleSynchronizer.reset()
            refreshRealtimeSpeechPresentationImmediately()
        case .cancelled(let reason):
            if reason == "interrupted" {
                realtimeSpeechPlaybackSubtitleSynchronizer.reset()
            } else {
                realtimeSpeechPlaybackSubtitleSynchronizer
                    .resetForTerminal(
                        canonicalCompleted:
                            realtimeSpeechSubtitleSnapshot.lastCompleted
                    )
            }
            refreshRealtimeSpeechPresentationImmediately()
        case .closed, .failed:
            realtimeSpeechPlaybackSubtitleSynchronizer.resetForTerminal(
                canonicalCompleted:
                    realtimeSpeechSubtitleSnapshot.lastCompleted
            )
            refreshRealtimeSpeechPresentationImmediately()
        default:
            refreshRealtimeSpeechPresentationImmediately()
        }
        let stateAfter = orchestrationKernel.realtimeSpeechStateSnapshot()
            .state.rawValue
        let duration = (
            DispatchTime.now().uptimeNanoseconds &- startedAt
        ) / 1_000_000
        recordRealtimeSpeechProviderEvent(
            event,
            stateBefore: stateBefore,
            stateAfter: stateAfter,
            durationMilliseconds: duration
        )
        switch event.kind {
        case .turnFailed:
            nativeSpeechPlaybackBinding = nil
            let cleared = await speechAudioOutputHost.clear()
            guard !Task.isCancelled else { return }
            speechAudioOutputHostSnapshot = cleared
            recordRealtimeSpeechDiagnostic(
                source: .playback,
                category: "turn_failed_local_clear",
                interactionShortID: String(
                    event.interactionID.rawValue.uuidString.prefix(8)
                ),
                stateAfter: realtimeSpeechStateSnapshot.state.rawValue
            )
        case .responseCompleted:
            if let playbackBinding = nativeSpeechPlaybackBinding {
                let finished =
                    await speechAudioOutputHost.finishProviderResponse(
                        generation: playbackBinding.playbackGeneration
                    )
                guard !Task.isCancelled else { return }
                speechAudioOutputHostSnapshot = finished
                await consumePlaybackEvents(
                    in: speechAudioOutputHostSnapshot
                )
                guard !Task.isCancelled else { return }
            } else {
                realtimeSpeechPlaybackSubtitleSynchronizer
                    .noteUnplayedResponse()
                recordRealtimeSpeechDiagnostic(
                    source: .subtitle,
                    category: "subtitle_playback_unavailable",
                    interactionShortID: String(
                        event.interactionID.rawValue.uuidString.prefix(8)
                    ),
                    turnNumber:
                        realtimeSpeechStateSnapshot.currentTurnNumber,
                    turnGeneration:
                        realtimeSpeechSubtitleSnapshot.turnGeneration,
                    disposition: "final_not_displayed"
                )
                syncRealtimeSpeechPresentation()
            }
        case .outputAudio:
            break
        default:
            break
        }
        let currentOutputSnapshot =
            await speechAudioOutputHost.currentSnapshot()
        guard !Task.isCancelled else { return }
        speechAudioOutputHostSnapshot = currentOutputSnapshot
        refreshNativeSpeechPlaybackDebugSnapshot()
    }

    private func commitAcceptedInterruptIfNeeded(
        _ event: NativeSpeechEvent,
        startedAtNanoseconds: UInt64
    ) async {
        let stateSnapshot = orchestrationKernel.realtimeSpeechStateSnapshot()
        guard stateSnapshot.lastTransitionReason == .interrupted else {
            return
        }
        let subtitleSnapshot = orchestrationKernel
            .realtimeSpeechSubtitleSnapshot()
        let turnNumber = stateSnapshot.currentTurnNumber
        let turnGeneration = subtitleSnapshot.turnGeneration
        let cleared = finalizeInterruptedPlaybackClearIfNeeded(
            stateSnapshot: stateSnapshot
        )
        speechOutputBridgeSnapshot =
            await speechOutputBridge.currentSnapshot()
        let clearDuration = speechOutputBridgeSnapshot
            .lastSpeechStartPreclearDurationMilliseconds
            ?? ((DispatchTime.now().uptimeNanoseconds &- startedAtNanoseconds)
                / 1_000_000)
        let interactionShortID = String(
            event.interactionID.rawValue.uuidString.prefix(8)
        )
        recordRealtimeSpeechDiagnostic(
            source: .playback,
            category: "interrupt_local_clear",
            interactionShortID: interactionShortID,
            turnNumber: turnNumber,
            turnGeneration: turnGeneration,
            disposition: cleared ? "cleared" : "already_clear",
            durationMilliseconds: clearDuration
        )
        recordRealtimeSpeechDiagnostic(
            source: .runtime,
            category: "provider_cancel_requested",
            interactionShortID: interactionShortID,
            turnNumber: turnNumber,
            turnGeneration: turnGeneration
        )
        let result = await orchestrationKernel.commitNativeSpeechInterrupt(
            interactionID: event.interactionID,
            turnNumber: turnNumber,
            turnGeneration: turnGeneration
        )
        switch result {
        case .success(let committed):
            recordRealtimeSpeechDiagnostic(
                source: .runtime,
                category: "provider_cancel_committed",
                interactionShortID: interactionShortID,
                turnNumber: turnNumber,
                turnGeneration: turnGeneration,
                disposition: committed ? "committed" : "duplicate"
            )
        case .failure(let error):
            recordRealtimeSpeechDiagnostic(
                source: .runtime,
                category: "provider_cancel_failed",
                interactionShortID: interactionShortID,
                turnNumber: turnNumber,
                turnGeneration: turnGeneration,
                errorCode: Self.nativeSpeechErrorName(error)
            )
        }
    }

    private func enqueueNativeSpeechOutput(
        _ payload: NativeSpeechAudioPayload
    ) async {
        guard !Task.isCancelled else { return }
        let turnNumber = realtimeSpeechStateSnapshot.currentTurnNumber
        if nativeSpeechPlaybackBinding?.interactionID
                != payload.interactionID
            || nativeSpeechPlaybackBinding?.turnNumber != turnNumber {
            let prepared = await speechAudioOutputHost.prepare()
            guard !Task.isCancelled else { return }
            speechAudioOutputHostSnapshot = prepared
            let binding = NativeSpeechPlaybackBinding(
                interactionID: payload.interactionID,
                turnNumber: turnNumber,
                turnGeneration:
                    realtimeSpeechSubtitleSnapshot.turnGeneration,
                playbackGeneration: prepared.generation
            )
            nativeSpeechPlaybackBinding = binding
            realtimeSpeechPlaybackSubtitleSynchronizer.prepare(
                identity: binding.subtitleIdentity
            )
            guard prepared.state == .prepared else {
                await consumePlaybackEvents(in: prepared)
                return
            }
        }
        guard let binding = nativeSpeechPlaybackBinding else { return }
        var snapshot = await speechAudioOutputHost.enqueue(
            pcm16Bytes: payload.bytes,
            sequence: payload.sequenceNumber,
            generation: binding.playbackGeneration
        )
        guard !Task.isCancelled else { return }
        if snapshot.state == .prepared || snapshot.state == .completed {
            snapshot = await speechAudioOutputHost.start()
            guard !Task.isCancelled else { return }
        }
        speechAudioOutputHostSnapshot = snapshot
        await consumePlaybackEvents(in: snapshot)
    }

    private func finalizeInterruptedPlaybackClearIfNeeded(
        stateSnapshot: RealtimeSpeechStateSnapshot
    ) -> Bool {
        guard let binding = nativeSpeechPlaybackBinding,
              stateSnapshot.lastTransitionReason == .interrupted,
              stateSnapshot.currentTurnNumber > binding.turnNumber else {
            return false
        }
        playbackInterruptClearCount &+= 1
        nativeSpeechPlaybackBinding = nil
        return true
    }

    private func consumePlaybackEvents(
        in snapshot: MacSpeechAudioOutputHostSnapshot
    ) async {
        for event in snapshot.recentEvents
            where event.ordinal > lastPlaybackEventOrdinal {
            guard !Task.isCancelled else { return }
            await consumePlaybackHostEvent(event)
        }
    }

    private func consumeResidentSubtitleCheckpointReady() async {
        guard let binding = nativeSpeechPlaybackBinding else { return }
        await releaseResidentSubtitleCheckpointIfReady(binding: binding)
        syncRealtimeSpeechPresentation()
    }

    private func releaseResidentSubtitleCheckpointIfReady(
        binding: NativeSpeechPlaybackBinding
    ) async {
        guard nativeSpeechPlaybackBinding == binding,
              let playedSequence =
                realtimeSpeechPlaybackSubtitleSynchronizer
                    .playedAudioSequence,
              let checkpoint = await speechOutputBridge
                .takeResidentSubtitleCheckpoint(
                    interactionID: binding.interactionID,
                    throughAudioSequence: playedSequence
                ),
              nativeSpeechPlaybackBinding == binding else {
            return
        }
        _ = realtimeSpeechPlaybackSubtitleSynchronizer.applyPartial(
            text: checkpoint.text,
            requiredAudioSequence: checkpoint.requiredAudioSequence,
            identity: binding.subtitleIdentity
        )
    }

    private func consumePlaybackHostEvent(
        _ event: MacSpeechAudioOutputEvent
    ) async {
        guard event.ordinal > lastPlaybackEventOrdinal else { return }
        lastPlaybackEventOrdinal = event.ordinal
        guard let binding = nativeSpeechPlaybackBinding,
              event.generation == binding.playbackGeneration else {
            if event.kind == .playbackStarted
                || event.kind == .playbackStalled
                || event.kind == .playbackResumed
                || event.kind == .playbackCompleted
                || event.kind == .failed {
                rejectedPlaybackEventCount &+= 1
            }
            recordRealtimeSpeechDiagnostic(
                source: .playback,
                category: event.kind.rawValue,
                interactionShortID:
                    realtimeSpeechStateSnapshot.interactionShortID,
                turnNumber: realtimeSpeechStateSnapshot.currentTurnNumber,
                turnGeneration:
                    realtimeSpeechSubtitleSnapshot.turnGeneration,
                stateAfter: realtimeSpeechStateSnapshot.state.rawValue,
                disposition: "rejected_binding_or_generation",
                audioSequence: event.sequence,
                playbackGeneration: event.generation,
                errorCode: event.error?.rawValue
            )
            refreshNativeSpeechPlaybackDebugSnapshot()
            return
        }
        if event.kind == .chunkPlayed {
            speechAudioOutputHostSnapshot =
                await speechAudioOutputHost.currentSnapshot()
            if let sequence = event.sequence {
                realtimeSpeechPlaybackSubtitleSynchronizer.advance(
                    playedSequence: sequence,
                    identity: binding.subtitleIdentity
                )
                await releaseResidentSubtitleCheckpointIfReady(
                    binding: binding
                )
            }
            syncRealtimeSpeechPresentation()
            recordRealtimeSpeechDiagnostic(
                source: .playback,
                category: event.kind.rawValue,
                interactionShortID:
                    realtimeSpeechStateSnapshot.interactionShortID,
                turnNumber: binding.turnNumber,
                turnGeneration:
                    realtimeSpeechSubtitleSnapshot.turnGeneration,
                stateAfter: realtimeSpeechStateSnapshot.state.rawValue,
                disposition: "accepted_host",
                audioSequence: event.sequence,
                queueDepth: speechAudioOutputHostSnapshot.queueDepth,
                playbackGeneration: event.generation
            )
            refreshNativeSpeechPlaybackDebugSnapshot()
            return
        }
        if event.kind == .outputSafetyLimited {
            recordRealtimeSpeechDiagnostic(
                source: .playback,
                category: event.kind.rawValue,
                interactionShortID:
                    realtimeSpeechStateSnapshot.interactionShortID,
                turnNumber: binding.turnNumber,
                turnGeneration:
                    realtimeSpeechSubtitleSnapshot.turnGeneration,
                stateAfter: realtimeSpeechStateSnapshot.state.rawValue,
                disposition: "accepted_host",
                audioSequence: event.sequence,
                queueDepth: speechAudioOutputHostSnapshot.queueDepth,
                playbackGeneration: event.generation
            )
            return
        }
        if event.kind == .playbackCompleted {
            speechAudioOutputHostSnapshot =
                await speechAudioOutputHost.currentSnapshot()
        } else if event.kind == .failed {
            realtimeSpeechPlaybackSubtitleSynchronizer.resetForTerminal(
                canonicalCompleted:
                    realtimeSpeechSubtitleSnapshot.lastCompleted
            )
        }
        let kind: RealtimeSpeechPlaybackEventKind
        switch event.kind {
        case .playbackStarted:
            kind = .started
        case .playbackStalled:
            kind = .stalled
        case .playbackResumed:
            kind = .resumed
        case .playbackCompleted:
            kind = .completed
        case .failed:
            kind = .failed(Self.nativeSpeechError(for: event.error))
        default:
            return
        }
        let disposition = await orchestrationKernel
            .handleNativeSpeechPlaybackEvent(
                RealtimeSpeechPlaybackEvent(
                    interactionID: binding.interactionID,
                    turnNumber: binding.turnNumber,
                    playbackGeneration: binding.playbackGeneration,
                    kind: kind
                )
            )
        if disposition == .rejectedLate
            || disposition == .rejectedStale
            || disposition == .rejectedOutOfOrder {
            rejectedPlaybackEventCount &+= 1
        }
        if event.kind == .playbackCompleted,
           disposition == .applied {
            realtimeSpeechPlaybackSubtitleSynchronizer.completePlayback(
                identity: binding.subtitleIdentity
            )
        }
        syncRealtimeSpeechPresentation()
        if event.kind == .playbackCompleted,
           disposition == .applied {
            projectCompletedNativeSpeechDialogueHistoryIfNeeded(
                binding: binding
            )
        }
        recordRealtimeSpeechDiagnostic(
            source: .playback,
            category: event.kind.rawValue,
            interactionShortID: realtimeSpeechStateSnapshot
                .interactionShortID,
            turnNumber: binding.turnNumber,
            turnGeneration: realtimeSpeechSubtitleSnapshot.turnGeneration,
            stateAfter: realtimeSpeechStateSnapshot.state.rawValue,
            disposition: disposition.rawValue,
            audioSequence: event.sequence,
            queueDepth: speechAudioOutputHostSnapshot.queueDepth,
            playbackGeneration: event.generation,
            errorCode: event.error?.rawValue
        )
        if event.kind == .playbackCompleted,
           realtimeSpeechStateSnapshot.state == .listening {
            nativeSpeechPlaybackBinding = nil
        } else if event.kind == .failed {
            nativeSpeechPlaybackBinding = nil
        }
        speechAudioOutputHostSnapshot =
            await speechAudioOutputHost.currentSnapshot()
        refreshNativeSpeechPlaybackDebugSnapshot()
    }

    private func projectCompletedNativeSpeechDialogueHistoryIfNeeded(
        binding: NativeSpeechPlaybackBinding
    ) {
        guard let completed = realtimeSpeechSubtitleSnapshot.lastCompleted,
              completed.interactionShortID == String(
                  binding.interactionID.rawValue.uuidString.prefix(8)
              ),
              completed.turnNumber == binding.turnNumber,
              completed.turnGeneration == binding.turnGeneration,
              let userFinal = completed.userFinal?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !userFinal.isEmpty,
              let residentFinal = completed.residentFinal?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !residentFinal.isEmpty else {
            return
        }
        let identity = NativeSpeechDialogueHistoryIdentity(
            interactionID: binding.interactionID,
            turnNumber: binding.turnNumber,
            turnGeneration: binding.turnGeneration
        )
        guard projectedNativeSpeechDialogueHistoryIdentities
            .insert(identity).inserted else {
            return
        }

        appendDialogueAuditUser(userFinal)
        appendDialogueAuditResident(
            residentFinal,
            displayName: currentAuditResidentDisplayName
        )

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entryID = [
            "speech",
            binding.interactionID.rawValue.uuidString,
            String(binding.turnNumber),
            String(binding.turnGeneration)
        ].joined(separator: "-")
        dialogueEntries.append(AppDialogueEntryState(
            id: "user-\(entryID)",
            role: "user",
            text: userFinal,
            timestamp: timestamp
        ))
        dialogueEntries.append(AppDialogueEntryState(
            id: "resident-\(entryID)",
            role: "resident",
            text: residentFinal,
            timestamp: timestamp
        ))
        dialogueEntries = Array(dialogueEntries.suffix(8))
        sessionState.residentID = loadedResidentID
        sessionState.sessionID = loadedSessionID
        sessionState.lastUserInput = userFinal
        sessionState.lastResidentOutput = residentFinal
        sessionState.dialogueEntries = dialogueEntries
    }

    private func syncRealtimeSpeechPresentation() {
        if realtimeBrainRouteAttemptID != nil
            || realtimeBrainInputBinding != nil {
            syncRealtimeBrainSubtitlePresentation()
            return
        }
        let previousState = realtimeSpeechStateSnapshot.state
        let stateSnapshot = orchestrationKernel
            .realtimeSpeechStateSnapshot()
        let subtitleSnapshot = orchestrationKernel
            .realtimeSpeechSubtitleSnapshot()
        realtimeSpeechStateSnapshot = stateSnapshot
        realtimeSpeechSubtitleSnapshot = subtitleSnapshot

        let presentation = RealtimeSpeechPresentationMapper.map(
            state: stateSnapshot.state,
            previousState: previousState,
            currentSpeechSignal: residentSpeechSignal
        )
        residentVisualIntent = presentation.visualIntent
        residentSpeechSignal = presentation.speechSignal

        let subtitleText = realtimeSpeechPlaybackSubtitleSynchronizer
            .displayText
            ?? subtitleSnapshot.userFinal
        let subtitleProjection = RealtimeSpeechSubtitleProjection(
            interactionShortID: subtitleSnapshot.interactionShortID,
            turnNumber: subtitleSnapshot.turnNumber,
            turnGeneration: subtitleSnapshot.turnGeneration,
            text: subtitleText
        )
        let subtitleProjectionChanged =
            subtitleProjection != lastRealtimeSpeechSubtitleProjection
        lastRealtimeSpeechSubtitleProjection = subtitleProjection
        let subtitleState = subtitleText.map {
            ParticleSubtitleState(text: $0, phase: .showing)
        } ?? .hidden
        if subtitleProjectionChanged,
           residentTextPresentationID == nil,
           particleSubtitleState != subtitleState {
            particleSubtitleState = subtitleState
        }
        refreshParticleDebugSnapshot()
    }

    private func refreshRealtimeSpeechPresentationImmediately() {
        syncRealtimeSpeechPresentation()
    }

    private func refreshNativeSpeechPlaybackDebugSnapshot() {
        nativeSpeechPlaybackDebugSnapshot = NativeSpeechPlaybackDebugSnapshot(
            turnNumber: nativeSpeechPlaybackBinding?.turnNumber,
            playbackGeneration:
                nativeSpeechPlaybackBinding?.playbackGeneration,
            interruptClearCount: playbackInterruptClearCount,
            stopClearCount: playbackStopClearCount,
            rejectedEventCount: rejectedPlaybackEventCount
        )
    }

    private func recordRealtimeSpeechProviderEvent(
        _ event: NativeSpeechEvent,
        stateBefore: String,
        stateAfter: String,
        durationMilliseconds: UInt64
    ) {
        let metadata = Self.nativeSpeechEventMetadata(event.kind)
        let pcmMetrics: (
            peak: Double,
            rms: Double,
            clipCount: Int,
            boundaryJump: Double?,
            finalSample: Int16
        )?
        if case .outputAudio(let payload) = event.kind {
            pcmMetrics = Self.pcmMetrics(
                payload.bytes,
                previousFinalSample: lastDiagnosticPCMEndSample
            )
            lastDiagnosticPCMEndSample = pcmMetrics?.finalSample
        } else {
            pcmMetrics = nil
            if case .thinking = event.kind,
               stateBefore == RealtimeSpeechState.listening.rawValue {
                lastDiagnosticPCMEndSample = nil
            }
        }
        recordRealtimeSpeechDiagnostic(
            source: .providerEvent,
            category: metadata.category,
            interactionShortID: String(
                event.interactionID.rawValue.uuidString.prefix(8)
            ),
            turnNumber: realtimeSpeechStateSnapshot.currentTurnNumber,
            turnGeneration: realtimeSpeechSubtitleSnapshot.turnGeneration,
            stateBefore: stateBefore,
            stateAfter: stateAfter,
            disposition: "accepted",
            audioSequence: metadata.audioSequence,
            byteCount: metadata.byteCount,
            queueDepth: speechAudioOutputHostSnapshot.queueDepth,
            playbackGeneration:
                nativeSpeechPlaybackDebugSnapshot.playbackGeneration,
            durationMilliseconds: durationMilliseconds,
            pcmPeak: pcmMetrics?.peak,
            pcmRMS: pcmMetrics?.rms,
            pcmClipCount: pcmMetrics?.clipCount,
            pcmBoundaryJump: pcmMetrics?.boundaryJump,
            errorCode: metadata.errorCode
        )
    }

    private static func pcmMetrics(
        _ data: Data,
        previousFinalSample: Int16?
    ) -> (
        peak: Double,
        rms: Double,
        clipCount: Int,
        boundaryJump: Double?,
        finalSample: Int16
    )? {
        guard data.count >= 2, data.count.isMultiple(of: 2) else {
            return nil
        }
        let bytes = [UInt8](data)
        var peak = 0
        var squaredSum = 0.0
        var clipCount = 0
        var firstSample: Int16?
        var finalSample: Int16 = 0
        var sampleCount = 0
        for index in stride(from: 0, to: bytes.count, by: 2) {
            let raw = UInt16(bytes[index])
                | (UInt16(bytes[index + 1]) << 8)
            let sample = Int16(bitPattern: raw)
            let amplitude = abs(Int(sample))
            peak = max(peak, amplitude)
            squaredSum += Double(sample) * Double(sample)
            if amplitude >= 32_760 { clipCount += 1 }
            if firstSample == nil { firstSample = sample }
            finalSample = sample
            sampleCount += 1
        }
        let boundaryJump = previousFinalSample.flatMap { previous in
            firstSample.map {
                Double(abs(Int($0) - Int(previous))) / 65_535.0
            }
        }
        return (
            peak: Double(peak) / 32_768.0,
            rms: sqrt(squaredSum / Double(sampleCount)) / 32_768.0,
            clipCount: clipCount,
            boundaryJump: boundaryJump,
            finalSample: finalSample
        )
    }

    private func recordRealtimeSpeechInputAggregateIfNeeded() {
        let now = DispatchTime.now().uptimeNanoseconds
        guard lastDiagnosticAggregateNanoseconds == 0
                || now &- lastDiagnosticAggregateNanoseconds
                    >= 1_000_000_000 else {
            return
        }
        let isRealtimeBrainRoute =
            realtimeFullDuplexSpeechStatus.phase.isActive
                || realtimeBrainInputBinding != nil
                || realtimeBrainRouteAttemptID != nil
        let forwarded = isRealtimeBrainRoute
            ? realtimeBrainInputBridgeSnapshot.forwardedFrameCount
            : speechInputBridgeSnapshot.forwardedFrameCount
        let rejected = isRealtimeBrainRoute
            ? realtimeBrainInputBridgeSnapshot.runtimeRejectedFrameCount
            : speechInputBridgeSnapshot.runtimeRejectedFrameCount
        let generated = speechAudioHostSnapshot.generatedFrameCount
        let dropped = speechAudioHostSnapshot.droppedFrameCount
        recordRealtimeSpeechDiagnostic(
            source: .inputBridge,
            category: "one_second_aggregate",
            routeKind: isRealtimeBrainRoute ? .realtimeBrain : .nativeSpeech,
            interactionShortID: isRealtimeBrainRoute
                ? realtimeBrainInputBridgeSnapshot.sessionShortID
                : speechInputBridgeSnapshot.interactionShortID,
            turnNumber: isRealtimeBrainRoute
                ? nil : realtimeSpeechStateSnapshot.currentTurnNumber,
            turnGeneration: isRealtimeBrainRoute
                ? realtimeBrainInputBinding?.session.generation
                : realtimeSpeechSubtitleSnapshot.turnGeneration,
            queueDepth: speechAudioHostSnapshot.queuedFrameCount,
            inputForwardedFrameDelta:
                Self.diagnosticCounterDelta(
                    forwarded,
                    since: lastDiagnosticInputForwardedCount
                ),
            inputRejectedFrameDelta:
                Self.diagnosticCounterDelta(
                    rejected,
                    since: lastDiagnosticInputRejectedCount
                ),
            captureGeneratedFrameDelta:
                Self.diagnosticCounterDelta(
                    generated,
                    since: lastDiagnosticCaptureGeneratedCount
                ),
            captureDroppedFrameDelta:
                Self.diagnosticCounterDelta(
                    dropped,
                    since: lastDiagnosticCaptureDroppedCount
                ),
            errorCode: isRealtimeBrainRoute
                ? realtimeBrainInputBridgeSnapshot.lastError
                : speechInputBridgeSnapshot.lastError,
            nowNanoseconds: now
        )
        lastDiagnosticAggregateNanoseconds = now
        lastDiagnosticInputForwardedCount = forwarded
        lastDiagnosticInputRejectedCount = rejected
        lastDiagnosticCaptureGeneratedCount = generated
        lastDiagnosticCaptureDroppedCount = dropped
    }

    private static func diagnosticCounterDelta(
        _ current: UInt64,
        since previous: UInt64
    ) -> UInt64 {
        current >= previous ? current - previous : current
    }

    private func recordRealtimeSpeechDiagnostic(
        source: RealtimeSpeechDiagnosticSource,
        category: String,
        routeKind: NativeSpeechDiagnosticRouteKind? = nil,
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
        sourceGateEpoch: UInt64? = nil,
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
        acousticPacketTrace: RealtimeSpeechAcousticPacketTrace? = nil,
        nowNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        drainNativeSpeechInternalDiagnostics()
        realtimeSpeechDiagnosticTimeline.append(
            source: source,
            category: category,
            routeKind: routeKind?.rawValue,
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
            sourceGateEpoch: sourceGateEpoch,
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
            errorCode: errorCode,
            acousticPacketTrace: acousticPacketTrace,
            nowNanoseconds: nowNanoseconds
        )
        if Self.realtimeSpeechDiagnosticNeedsImmediateRefresh(category) {
            realtimeSpeechDiagnosticViewRefreshTask?.cancel()
            realtimeSpeechDiagnosticViewRefreshTask = nil
            publishRealtimeSpeechDiagnosticViewState()
        } else {
            scheduleRealtimeSpeechDiagnosticViewRefresh()
        }
    }

    private func drainNativeSpeechInternalDiagnostics() {
        let drained = nativeSpeechDiagnosticBuffer.drain()
        for event in drained.events {
            let source: RealtimeSpeechDiagnosticSource = switch event.source {
            case .transport: .transport
            case .wire: .wire
            case .adapter: .adapter
            case .runtime: .runtime
            }
            realtimeSpeechDiagnosticTimeline.append(
                source: source,
                category: event.category,
                routeKind: event.routeKind?.rawValue,
                interactionShortID: event.interactionShortID,
                turnNumber: event.turnNumber,
                turnGeneration: event.turnGeneration,
                stateBefore: event.stateBefore,
                stateAfter: event.stateAfter,
                disposition: event.disposition,
                wireSequence: event.wireSequence,
                responseCorrelationHash:
                    event.responseCorrelationHash,
                itemCorrelationHash: event.itemCorrelationHash,
                audioSequence: event.audioSequence,
                byteCount: event.byteCount,
                queueDepth: event.queueDepth,
                pendingWriteCount: event.pendingWriteCount,
                arrivalIntervalMilliseconds:
                    event.arrivalIntervalMilliseconds,
                wireToStandardDurationMilliseconds:
                    event.wireToStandardDurationMilliseconds,
                durationMilliseconds: event.durationMilliseconds,
                pcmPeak: event.pcmPeak,
                pcmRMS: event.pcmRMS,
                errorCode: event.errorCode,
                timestamp: event.timestamp,
                nowNanoseconds: event.monotonicTimestampNanoseconds
            )
        }
        if drained.droppedEventCount > 0 {
            realtimeSpeechDiagnosticTimeline.append(
                source: .lifecycle,
                category: "internal_diagnostic_overflow",
                disposition: "dropped_\(drained.droppedEventCount)"
            )
        }
    }

    private func scheduleRealtimeSpeechDiagnosticViewRefresh() {
        guard realtimeSpeechDiagnosticViewRefreshTask == nil else { return }
        realtimeSpeechDiagnosticViewRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            realtimeSpeechDiagnosticViewRefreshTask = nil
            publishRealtimeSpeechDiagnosticViewState()
        }
    }

    private func publishRealtimeSpeechDiagnosticViewState() {
        realtimeSpeechDiagnosticViewState = RealtimeSpeechDiagnosticViewState(
            timeline: realtimeSpeechDiagnosticTimeline
        )
    }

    private static func realtimeSpeechDiagnosticNeedsImmediateRefresh(
        _ category: String
    ) -> Bool {
        switch category {
        case "failed", "closed", "cancelled",
             "manual_stop_completed", "interrupt_local_clear",
             "provider_cancel_failed":
            return true
        default:
            return false
        }
    }

    private static func nativeSpeechEventMetadata(
        _ kind: NativeSpeechEventKind
    ) -> (
        category: String,
        audioSequence: UInt64?,
        byteCount: Int?,
        errorCode: String?
    ) {
        switch kind {
        case .connected: ("connected", nil, nil, nil)
        case .sessionUpdated: ("session_updated", nil, nil, nil)
        case .inputSpeechStarted: ("input_speech_started", nil, nil, nil)
        case .inputSpeechEnded: ("input_speech_ended", nil, nil, nil)
        case .partialTranscript(let text):
            ("user_partial", nil, text.utf8.count, nil)
        case .finalTranscript(let text):
            ("user_final", nil, text.utf8.count, nil)
        case .thinking: ("thinking", nil, nil, nil)
        case .outputText(let text, let isFinal):
            (isFinal ? "resident_final" : "resident_partial",
             nil, text.utf8.count, nil)
        case .outputAudio(let payload):
            ("output_audio", payload.sequenceNumber,
             payload.bytes.count, nil)
        case .toolRequestCandidate:
            ("tool_request_candidate", nil, nil, nil)
        case .responseCompleted:
            ("response_completed", nil, nil, nil)
        case .turnFailed(let error):
            ("turn_failed", nil, nil, nativeSpeechErrorName(error))
        case .cancelled:
            ("cancelled", nil, nil, nil)
        case .closed:
            ("closed", nil, nil, nil)
        case .failed(let error):
            ("failed", nil, nil, nativeSpeechErrorName(error))
        }
    }

    private static func nativeSpeechError(
        for error: MacSpeechAudioOutputHostError?
    ) -> NativeSpeechError {
        switch error {
        case .outputUnavailable, .outputDeviceChanged:
            return .unavailable
        case .consumerTimedOut:
            return .timedOut
        default:
            return .transportFailure
        }
    }

    private static func nativeSpeechErrorName(
        _ error: NativeSpeechError
    ) -> String {
        switch error {
        case .invalidConfiguration: "invalid_configuration"
        case .missingCredential: "missing_credential"
        case .unauthorized: "unauthorized"
        case .rateLimited: "rate_limited"
        case .unavailable: "unavailable"
        case .timedOut: "timed_out"
        case .cancelled: "cancelled"
        case .transportFailure: "transport_failure"
        case .invalidEvent: "invalid_event"
        case .interactionMismatch: "interaction_mismatch"
        }
    }

    func deleteNativeSpeechProviderCredential() {
        do {
            try providerKeychainStore.delete(
                for: ProviderKeychainStore.qwenKeyRef
            )
            nativeSpeechProviderDebugState.credentialSaved = false
            nativeSpeechProviderDebugState.statusKey =
                "particleDebug.qwen.status.credentialDeleted"
        } catch {
            refreshNativeSpeechProviderDebugState(
                statusKey: "particleDebug.qwen.status.credentialFailed"
            )
        }
    }

    func testNativeSpeechProviderConnectivity() async {
        guard providerKeychainStore.exists(
            for: ProviderKeychainStore.qwenKeyRef
        ) else {
            refreshNativeSpeechProviderDebugState(
                statusKey: "particleDebug.qwen.status.credentialMissing"
            )
            return
        }

        nativeSpeechProviderDebugState.isTesting = true
        nativeSpeechProviderDebugState.statusKey =
            "particleDebug.qwen.status.testing"
        let result = await orchestrationKernel.testNativeSpeechConnectivity(
            profile: nativeSpeechProviderDebugState.profile
        )
        nativeSpeechProviderDebugState.isTesting = false
        switch result {
        case .success:
            nativeSpeechProviderDebugState.statusKey =
                "particleDebug.qwen.status.pass"
        case .failure(let error):
            nativeSpeechProviderDebugState.statusKey =
                nativeSpeechConnectivityStatusKey(for: error)
        }
        nativeSpeechProviderDebugState.credentialSaved =
            providerKeychainStore.exists(
                for: ProviderKeychainStore.qwenKeyRef
            )
    }

    private func refreshNativeSpeechProviderDebugState(
        statusKey: String? = nil
    ) {
        nativeSpeechProviderDebugState.credentialSaved =
            providerKeychainStore.exists(
                for: ProviderKeychainStore.qwenKeyRef
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
            return "particleDebug.qwen.status.failedAuthentication"
        case .rateLimited, .unavailable, .timedOut, .transportFailure:
            return "particleDebug.qwen.status.failedNetwork"
        case .cancelled:
            return "particleDebug.qwen.status.cancelled"
        case .invalidConfiguration, .missingCredential, .invalidEvent,
             .interactionMismatch:
            return "particleDebug.qwen.status.failedProviderConfiguration"
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
