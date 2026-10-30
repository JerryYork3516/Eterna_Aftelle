import Combine
import Foundation
#if DEBUG
import AppKit
import CryptoKit
    import Darwin
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
    static let preferenceKey = "aftelle.realtimeSpeech.modelID"

    static var selectedModel: Stage75QwenRealtimeModel {
        UserDefaults.standard.string(forKey: preferenceKey)
            .flatMap(Stage75QwenRealtimeModel.init(rawValue:)) ?? .plus
    }

    static var value: QwenRealtimeResidentBrainConfiguration {
        makeValue(model: selectedModel)
    }

    static func makeValue(
        model: Stage75QwenRealtimeModel
    ) -> QwenRealtimeResidentBrainConfiguration {
        let modelID = model.rawValue
        return QwenRealtimeResidentBrainConfiguration(
            endpoint: URL(
                string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=\(modelID)"
            )!,
            modelID: modelID,
            keyRef: ProviderKeychainStore.qwenKeyRef,
            defaultProviderVoiceID: "Tina"
        )
    }
}

nonisolated enum Stage75QwenRealtimeModel: String, CaseIterable, Sendable {
    case flash = "qwen3.5-omni-flash-realtime"
    case plus = "qwen3.5-omni-plus-realtime"
}

#if DEBUG
    nonisolated struct AppleVPMacAECBatchRun {
        static let argument = "--apple-vp-mac-aec="
        static let residentSHA256 = "774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea"
        let batchID: UUID
        let round: Int
        let limit: Int

        init?(arguments: [String]) {
            let values = arguments.filter { $0.hasPrefix(Self.argument) }
            guard values.count == 1 else { return nil }
            let fields = values[0].dropFirst(Self.argument.count).split(separator: ":")
            guard fields.count == 3, let batchID = UUID(uuidString: String(fields[0])),
                  let round = Int(fields[1]), let limit = Int(fields[2]),
                  (1 ... 3).contains(limit), (1 ... limit).contains(round)
            else { return nil }
            self.batchID = batchID
            self.round = round
            self.limit = limit
        }

        var manifest: [String: Any] {
            ["batch": "R5_M20", "batch_id": batchID.uuidString, "round": round, "limit": limit,
             "scenario": "A", "proxy_requested": false]
        }
    }

    nonisolated struct AppleVPAdaptationRun {
        static let argument = "--apple-vp-adaptation="
        enum Arm: String, CaseIterable {
            case voicedTwice, delayOnly, silentPrime
        }

        let batchID: UUID
        let arm: Arm
        var round: Int {
            Arm.allCases.firstIndex(of: arm)! + 1
        }

        var plays: [(offset: UInt64, silent: Bool)] {
            if arm == .delayOnly {
                return [(9_000_000_000, false)]
            }
            return [(3_000_000_000, arm == .silentPrime), (9_000_000_000, false)]
        }

        init?(arguments: [String]) {
            let values = arguments.filter { $0.hasPrefix(Self.argument) }
            guard values.count == 1 else { return nil }
            let fields = values[0].dropFirst(Self.argument.count).split(separator: ":")
            guard fields.count == 2, let batch = UUID(uuidString: String(fields[0])),
                  let arm = Arm(rawValue: String(fields[1])) else { return nil }
            batchID = batch
            self.arm = arm
        }

        static func acceptsMicrophoneModes(_ modes: [MacSpeechMicrophoneModeReadback]) -> Bool {
            !modes.isEmpty && modes.count <= 2
                && modes.allSatisfy { $0.status == "CONFIRMED_PUBLIC_API" && $0.active == 0 }
        }

        var manifest: [String: Any] {
            ["batch": "R5_M22", "batch_id": batchID.uuidString, "arm": arm.rawValue,
             "round": round, "limit": 3, "scenario": "A", "proxy_requested": false]
        }
    }

    nonisolated struct AppleVPScoreControl {
        static let argument = "--apple-vp-score-control-fd="
        let descriptor: Int32

        init?(arguments: [String]) throws {
            let values = arguments.filter { $0.hasPrefix(Self.argument) }
            guard !values.isEmpty else { return nil }
            guard values.count == 1,
                  let descriptor = Int32(values[0].dropFirst(Self.argument.count)), descriptor > 2
            else { throw AppleVPAcousticTestError.externalPlaybackControl }
            var info = stat()
            let flags = fcntl(descriptor, F_GETFL)
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFIFO,
                  flags >= 0, flags & O_ACCMODE == O_WRONLY,
                  fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
                  fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0
            else { throw AppleVPAcousticTestError.externalPlaybackControl }
            self.descriptor = descriptor
        }

        func send(
            _ event: String, runID: UUID, scoreStart: UInt64 = 0,
            batchScenario: AppleVPAcousticTestScenario? = nil, humanBatch: Bool = false,
            onsetProfile: AppleVPHumanOnsetProfile? = nil, macAECBatch: AppleVPMacAECBatchRun? = nil,
            adaptation: AppleVPAdaptationRun? = nil, allocation: MacSpeechChannelAllocation.Run? = nil,
        ) throws {
            guard onsetProfile == nil || (humanBatch && batchScenario == .doubleTalk) else {
                throw AppleVPAcousticTestError.externalPlaybackControl
            }
            var message: [String: Any] = ["schema_version": 1, "event": event, "run_id": runID.uuidString]
            if let batchScenario {
                message["batch"] = onsetProfile != nil ? "R5_M07_F1" : humanBatch ? "R5_M07" : "R5_M03"
                message["scenario"] = batchScenario.rawValue
            }
            if let macAECBatch {
                guard batchScenario == .residentOnly, !humanBatch, onsetProfile == nil else {
                    throw AppleVPAcousticTestError.externalPlaybackControl
                }
                message.merge(macAECBatch.manifest) { _, new in new }
            }
            if let adaptation {
                guard macAECBatch == nil, batchScenario == .residentOnly, !humanBatch, onsetProfile == nil else {
                    throw AppleVPAcousticTestError.externalPlaybackControl
                }
                message.merge(adaptation.manifest) { _, new in new }
            }
            try mergeAllocation(allocation, into: &message,
                                eligible: macAECBatch == nil && adaptation == nil && batchScenario == .residentOnly
                                    && !humanBatch && onsetProfile == nil)
            if humanBatch {
                message["source"] = "human"
                message["proxy_requested"] = false
            }
            if let onsetProfile {
                message["onset_group"] = onsetProfile.rawValue
                message["human_start_cue_ns"] = scoreStart + onsetProfile.cueDelayNanoseconds
            }
            message["score_start_ns"] = scoreStart
            message[humanBatch ? "human_speech_stop_ns" : "proxy_stop_ns"] = scoreStart + 11_000_000_000
            message["clock"] = "mach_absolute_nanoseconds"
            var bytes = try JSONSerialization.data(withJSONObject: message, options: .sortedKeys)
            bytes.append(10)
            guard bytes.count <= 512 else { throw AppleVPAcousticTestError.externalPlaybackControl }
            let written = bytes.withUnsafeBytes { buffer in
                Darwin.write(descriptor, buffer.baseAddress, buffer.count)
            }
            guard written == bytes.count else { throw AppleVPAcousticTestError.externalPlaybackControl }
        }

        private func mergeAllocation(
            _ allocation: MacSpeechChannelAllocation.Run?, into message: inout [String: Any],
            eligible: Bool,
        ) throws {
            guard let allocation else { return }
            guard eligible else {
                throw AppleVPAcousticTestError.externalPlaybackControl
            }
            message.merge(allocation.eventIdentity) { _, new in new }
        }
    }

    nonisolated enum AppleVPAcousticTestLaunchMode {
        static let argument = "--apple-vp-acoustic-test"
        static let silentArgument = "--apple-vp-silent-smoke="

        static func isEnabled(arguments: [String]) -> Bool {
            arguments.contains(argument)
        }

        static func collectionDuration(silentScenario: AppleVPAcousticTestScenario?) -> UInt64 {
            switch silentScenario {
            case .residentOnly: 18_000_000_000
            case .humanOnly, .doubleTalk: 4_000_000_000
            case nil: 15_000_000_000
            }
        }
    }

    nonisolated enum AppleVPAcousticTestScenario: String, CaseIterable {
        case residentOnly = "A"
        case humanOnly = "B"
        case doubleTalk = "C"
    }

    nonisolated enum AppleVPAcousticTestPhase: String {
        case idle, ready, starting, running, stopping, sealed
    }

    nonisolated enum AppleVPAcousticDataMode: String {
        case recording = "RECORDING"
        case statsOnly = "STATS_ONLY"
    }

    nonisolated enum AppleVPHumanOnsetProfile: String, CaseIterable {
        case residentFirst = "A"
        case humanFirst = "B"

        var cueDelayNanoseconds: UInt64 {
            self == .residentFirst ? 5_500_000_000 : 0
        }
    }

    nonisolated struct AppleVPWarmupDrainState {
        let plan: MacSpeechAcousticWindowPlan
        var statistics: MacSpeechAcousticWindowStats
        private(set) var drainedPackets: UInt64 = 0
        private(set) var warmupPackets: UInt64 = 0
        private(set) var boundaryPackets: UInt64 = 0
        private(set) var outsidePackets: UInt64 = 0
        private(set) var lastPacketTime: UInt64?
        private(set) var firstPacketTime: UInt64?

        init(plan: MacSpeechAcousticWindowPlan) {
            self.plan = plan
            statistics = MacSpeechAcousticWindowStats(plan: plan)
        }

        mutating func retain(_ frame: MacSpeechAudioFrame) throws -> Bool {
            guard frame.sequenceNumber == drainedPackets + 1, frame.pcm16Bytes.count == 960,
                  frame.monotonicTimestampNanoseconds > 0 else { throw AppleVPAcousticTestError.invalidPacket }
            let start = frame.monotonicTimestampNanoseconds
            let end = start.addingReportingOverflow(20_000_000)
            guard !end.overflow else { throw AppleVPAcousticTestError.invalidPacket }
            if let lastPacketTime {
                let expected = lastPacketTime.addingReportingOverflow(20_000_000)
                guard !expected.overflow, start == expected.partialValue else {
                    throw AppleVPAcousticTestError.invalidPacket
                }
            }
            firstPacketTime = firstPacketTime ?? start
            lastPacketTime = start
            drainedPackets += 1
            statistics.recordPCM(frame.pcm16Bytes, hostTime: start)
            if start >= plan.scoreStartedAt, end.partialValue <= plan.scoreEndedAt {
                return true
            }
            if start >= plan.captureStartedAt, end.partialValue <= plan.scoreStartedAt {
                warmupPackets += 1
            } else if start < plan.scoreEndedAt, end.partialValue > plan.scoreStartedAt {
                boundaryPackets += 1
            } else {
                outsidePackets += 1
            }
            return false
        }

        func manifest() -> [String: Any] {
            ["capture_start_returned_ns": plan.captureStartedAt, "score_start_content_boundary_ns": plan.scoreStartedAt,
             "score_end_content_boundary_ns": plan.scoreEndedAt, "drained_packets": drainedPackets,
             "warmup_packets_not_retained": warmupPackets, "excluded_boundary_packets": boundaryPackets,
             "excluded_outside_packets": outsidePackets, "first_drained_content_ns": firstPacketTime ?? NSNull() as Any,
             "last_drained_content_ns": lastPacketTime ?? NSNull() as Any, "pcm_statistics": statistics.manifest(),
             "warmup_retained_pcm_bytes": 0, "alignment": "whole_packets_inside_content_time_window",
             "partial_tail": "UNKNOWN", "tail_coverage": "REVIEW_REQUIRED"]
        }
    }

    nonisolated struct AppleVPAcousticTestState {
        var scenario = AppleVPAcousticTestScenario.residentOnly
        var phase = AppleVPAcousticTestPhase.idle
        fileprivate(set) var dataMode = AppleVPAcousticDataMode.recording
        fileprivate(set) var processingProfile = MacSpeechAppleVPDebugProfile.agcOn
        fileprivate(set) var warmupProfile: MacSpeechWarmupProfile?
        fileprivate var warmupDrain: AppleVPWarmupDrainState?
        fileprivate var pcmShortWindows: MacSpeechShortWindowStats?
        fileprivate var lastCollectionClock: UInt64?
        var runID: UUID?
        var errorCode: String?
        fileprivate var playbackURL: URL?
        fileprivate var pcm = Data()
        fileprivate var packets: [[UInt64]] = []
        fileprivate var generation: UInt64?
        fileprivate var playbackGeneration: UInt64?
        fileprivate var stopGeneration: UInt64 = 0
        fileprivate var authorizationRunID: UUID?
        fileprivate var playbackFailure: String?
        fileprivate var playbackSHA256: String?
        fileprivate var route = MacSpeechAudioHostSnapshot.initial
        fileprivate var captureFinal = MacSpeechAudioHostSnapshot.initial
        fileprivate var macAECFinalDrain: [String: UInt64]?
        fileprivate var playbackFinal = MacSpeechAudioOutputHostSnapshot.initial
        fileprivate var native: MacSpeechNativeVoiceDebugSnapshot?
        fileprivate var lastRefresh: UInt64 = 0
        fileprivate var cleanupInFlight = false
        var comprehensiveC = false
        fileprivate(set) var btAcousticBatch = false
        fileprivate(set) var humanAcousticBatch = false
        fileprivate(set) var macAECBatch: AppleVPMacAECBatchRun?
        fileprivate(set) var adaptation: AppleVPAdaptationRun?
        fileprivate(set) var allocation: MacSpeechChannelAllocation.Run?
        fileprivate var adaptationPlays: [[String: Any]] = []
        fileprivate(set) var macAECCancelled = false
        fileprivate(set) var humanOnsetProfile: AppleVPHumanOnsetProfile?
        fileprivate(set) var humanSpeechCueAtNanoseconds: UInt64?
        fileprivate var guideStartedAt: UInt64?
        fileprivate var guideEvents: [String: UInt64] = [:]

        var isAcousticBatch: Bool {
            btAcousticBatch || humanAcousticBatch || macAECBatch != nil || adaptation != nil || allocation != nil
        }

        mutating func recordHumanSpeechCue(at now: UInt64, elapsed: UInt64) {
            guard let profile = humanOnsetProfile, humanSpeechCueAtNanoseconds == nil,
                  elapsed >= profile.cueDelayNanoseconds else { return }
            humanSpeechCueAtNanoseconds = now
        }

        var guideStage: String? {
            ["quiet", "human_tail", "double_talk", "human_only"].first { guideEvents[$0] != nil }
                ?? (warmupDrain != nil && phase == .running ? "warmup" : nil)
        }

        var selectedPlaybackFileName: String {
            playbackURL?.lastPathComponent ?? ""
        }

        var packetCount: Int {
            packets.count
        }

        var byteCount: Int {
            packets.count * MacSpeechAudioInputFormat.packetByteCount
        }

        var retainedPCMByteCount: Int {
            pcm.count
        }

        var drainedPacketCount: UInt64 {
            warmupDrain?.drainedPackets ?? UInt64(packetCount)
        }

        var isBusy: Bool {
            phase == .starting || phase == .running || phase == .stopping
        }

        var canExport: Bool {
            phase == .sealed && runID != nil
        }

        var canExportWAV: Bool {
            canExport && dataMode == .recording && !pcm.isEmpty
        }

        var authorizationPending: Bool {
            authorizationRunID != nil
        }

        var canStart: Bool {
            phase == .ready && !authorizationPending && !cleanupInFlight && !macAECCancelled
        }
    }

    nonisolated enum AppleVPRuntimeSafetyError: String, Error {
        case configurationChanged = "engine_configuration_changed"
        case identityMismatch = "runtime_identity_mismatch"
        case evidenceUnavailable = "runtime_diagnostics_unavailable"
        case bindingUnverified = "runtime_process_binding_unverified"
        case processingUnverified = "runtime_processing_unverified"

        static func validate(
            _ timing: MacSpeechTimingSnapshot?, identity: MacSpeechRuntimeReadback.Identity,
            pid: Int32, agcEnabled: Bool, residentStarted: Bool
        ) throws {
            guard let timing else { throw evidenceUnavailable }
            guard pid > 0, identity.generation > 0, identity.configurationID > 0,
                  timing.runID == identity.runID, timing.captureGeneration == identity.generation,
                  timing.configurationID == identity.configurationID, !timing.callbacksClosed,
                  timing.identityChanges == 0 else { throw identityMismatch }
            let events = timing.engineConfigurationEvents
            guard events.count == 0 else { throw configurationChanged }
            guard events.status == "CONFIRMED", !events.observationClosed, events.skippedNotifications == 0,
                  !timing.runtimeReadbacks.isEmpty, timing.runtimeReadbacks.count <= 2,
                  !residentStarted || timing.runtimeReadbacks.count == 2 else { throw evidenceUnavailable }
            let first = timing.runtimeReadbacks[0].payload
            for (index, snapshot) in timing.runtimeReadbacks.enumerated() {
                guard snapshot.runID == identity.runID, snapshot.captureGeneration == identity.generation,
                      snapshot.configurationID == identity.configurationID,
                      snapshot.phase == (index == 0 ? .engineStarted : .residentPlaybackStarted)
                else { throw identityMismatch }
                try validatePayload(snapshot.payload, first: first, pid: pid, agcEnabled: agcEnabled)
            }
        }

        private static func validatePayload(
            _ payload: MacSpeechRuntimeReadback.Payload, first: MacSpeechRuntimeReadback.Payload,
            pid: Int32, agcEnabled: Bool
        ) throws {
            let process = payload.processBinding
            let pids = [process.requestedPID, process.observedPID, process.observedPIDAfter]
            guard pids.compactMap(\.self).allSatisfy({ $0 == pid }) else { throw identityMismatch }
            guard pids.allSatisfy({ $0 != nil }), process.status == "CONFIRMED",
                  process.input?.status == "CONFIRMED", process.output?.status == "CONFIRMED"
            else { throw evidenceUnavailable }
            let known = ["PROCESS_DEVICE_METADATA_MATCHES_DEFAULT", "PROCESS_AGGREGATE_DIRECTION_QUALIFIED"]
            let sharedInput = process.input?.bindingStatus == MacSpeechRuntimeReadback.sharedIODeviceSetBinding
                && payload.route.map { MacSpeechRuntimeReadback.qualifiesSharedIODeviceSet(process, route: $0) } == true
            guard known.contains(process.input?.bindingStatus ?? "") || sharedInput,
                  known.contains(process.output?.bindingStatus ?? "") else { throw bindingUnverified }
            guard let inputIDs = process.input?.deviceIDs, let outputIDs = process.output?.deviceIDs,
                  !inputIDs.isEmpty, !outputIDs.isEmpty,
                  inputIDs.count == Set(inputIDs).count, outputIDs.count == Set(outputIDs).count,
                  Set(inputIDs) == Set(first.processBinding.input?.deviceIDs ?? []),
                  Set(outputIDs) == Set(first.processBinding.output?.deviceIDs ?? []),
                  payload.route?.defaultInput.id == first.route?.defaultInput.id,
                  payload.route?.defaultOutput.id == first.route?.defaultOutput.id
            else { throw identityMismatch }
            let expected = ["engineRunning": true, "inputEnabled": true, "outputEnabled": true,
                            "agcEnabled": agcEnabled, "bypass": false, "inputMuted": false]
            guard expected.allSatisfy({ payload.voiceProcessing[$0.key] == $0.value }),
                  payload.playerMixerBus != nil, payload.mixerOutputConnected, payload.issues.isEmpty
            else { throw processingUnverified }
        }
    }

    private nonisolated enum AppleVPAcousticTestError: String, Error {
        case externalPlaybackControl = "external_playback_control_unavailable"
        case consentRequired = "consent_required"
        case unavailable = "debug_capture_unavailable"
        case permissionDenied = "microphone_not_authorized"
        case invalidFile = "invalid_playback_wav"
        case captureUnavailable = "capture_unavailable"
        case voiceProcessingUnavailable = "voice_processing_unverified"
        case routeChanged = "route_changed"
        case captureDropped = "capture_frame_drop"
        case playbackFailed = "playback_failed"
        case invalidPacket = "invalid_processed_packet"
        case capacityExceeded = "processed_pcm_capacity_exceeded"
    }

nonisolated private enum Stage75NativeSpeechConfiguration {
    static var profile: NativeSpeechProviderProfile {
        makeProfile(model: ProductionQwenRealtimeBrainConfiguration.selectedModel)
    }

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
                profile: Stage75NativeSpeechConfiguration.makeProfile(model: .plus)
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

    #if DEBUG
        private struct NormalDependencies {
            let orchestrationKernel: OrchestrationKernel
            let providerKeychainStore: ProviderKeychainStore
        }

        let isAppleVPAcousticTestMode: Bool
        private let appleVPAcousticTestCapture: (any MacSpeechAudioCapturing)?
        private let appleVPSilentSmokeScenario: AppleVPAcousticTestScenario?
        private var appleVPSilentSmokeStarted = false
        private let appleVPAcousticTestDurationNanoseconds: UInt64
        private let appleVPAcousticTestByteLimit: Int
        private var appleVPAcousticRun = AppleVPAcousticTestState()
        private var appleVPAcousticTestTask: Task<Void, Never>?
        private var appleVPAcousticPlaybackTask: Task<Void, Never>?
        private var appleVPAcousticClock: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
        private var appleVPScoreControlArguments = ProcessInfo.processInfo.arguments
        private var appleVPScoreControl: AppleVPScoreControl?
        private var appleVPAcousticRuntimeTiming: ((UUID) -> MacSpeechTimingSnapshot?)?

        private var appleVPChannelBuildVerifier: (String) -> Bool = MacSpeechChannelAllocation.Run.verifiesBuild
        private var appleVPChannelInstaller: ((MacSpeechChannelAllocation.Run, UUID, UInt64, UInt64) throws -> Void)?

        var appleVPChannelAllocation: MacSpeechChannelAllocation.Run? {
            guard isAppleVPAcousticTestMode else { return nil }
            return MacSpeechChannelAllocation.Run(arguments: appleVPScoreControlArguments)
        }

        var appleVPAdaptation: AppleVPAdaptationRun? {
            AppleVPAdaptationRun(arguments: appleVPScoreControlArguments)
        }

        var appleVPMacAECBatch: AppleVPMacAECBatchRun? {
            guard isAppleVPAcousticTestMode else { return nil }
            return AppleVPMacAECBatchRun(arguments: appleVPScoreControlArguments)
        }

        var appleVPBTBatchScenario: AppleVPAcousticTestScenario? {
            let values = appleVPScoreControlArguments.filter { $0.hasPrefix("--apple-vp-bt-abc=") }
            guard isAppleVPAcousticTestMode, values.count == 1 else { return nil }
            return AppleVPAcousticTestScenario(rawValue: String(values[0].dropFirst("--apple-vp-bt-abc=".count)))
        }

        var appleVPHumanBatchScenario: AppleVPAcousticTestScenario? {
            if appleVPHumanOnsetProfile != nil {
                return .doubleTalk
            }
            let values = appleVPScoreControlArguments.filter { $0.hasPrefix("--apple-vp-human-abc=") }
            guard isAppleVPAcousticTestMode, values.count == 1 else { return nil }
            return AppleVPAcousticTestScenario(rawValue: String(values[0].dropFirst("--apple-vp-human-abc=".count)))
        }

        var appleVPHumanOnsetProfile: AppleVPHumanOnsetProfile? {
            let prefix = "--apple-vp-human-onset="
            let values = appleVPScoreControlArguments.filter { $0.hasPrefix(prefix) }
            guard isAppleVPAcousticTestMode, values.count == 1 else { return nil }
            return AppleVPHumanOnsetProfile(rawValue: String(values[0].dropFirst(prefix.count)))
        }

        var appleVPAcousticTestState: AppleVPAcousticTestState {
            var snapshot = appleVPAcousticRun
            snapshot.cleanupInFlight = speechAudioHostShutdownOperation != nil || speechHostLifecycleOperationCount != 0
            return snapshot
        }

        private let normalDependenciesFactory: @MainActor () -> NormalDependencies
        private lazy var normalDependencies = normalDependenciesFactory()
        private var orchestrationKernel: OrchestrationKernel {
            normalDependencies.orchestrationKernel
        }

        private var providerKeychainStore: ProviderKeychainStore {
            normalDependencies.providerKeychainStore
        }
    #else
        private let orchestrationKernel: OrchestrationKernel
        private let providerKeychainStore: ProviderKeychainStore
    #endif
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
    private var speechHostStopGeneration: UInt64 = 0
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
    #if DEBUG
        private var realtimeBrainSessionConfiguration =
            ProductionQwenRealtimeBrainConfiguration.makeValue(model: .plus)
    #else
        private var realtimeBrainSessionConfiguration =
            ProductionQwenRealtimeBrainConfiguration.value
    #endif
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
    private lazy var realtimeBrainInputBridge = makeRealtimeBrainInputBridge()

    private func makeRealtimeBrainInputBridge() -> MacSpeechRealtimeBrainInputBridge {
        let orchestrationKernel = self.orchestrationKernel
        return MacSpeechRealtimeBrainInputBridge(
            source: speechAudioHost,
            sendFrameWithActivity: { [orchestrationKernel] frame, activity in
                await orchestrationKernel.sendRealtimeResidentBrainAudio(
                    frame,
                    activity: activity.localActivity
                )
            },
            confirmAcceptedLocalActivity: { [orchestrationKernel] frame, activity in
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
    }

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
    var realtimePlaybackEnqueueObserverForTesting:
        ((UInt64, UInt64, UInt64) -> Void)?
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
        #if DEBUG
            isAppleVPAcousticTestMode = AppleVPAcousticTestLaunchMode.isEnabled(
                arguments: ProcessInfo.processInfo.arguments
            )
        #else
            let credentialStore = ProviderKeychainStore()
        #endif
        let speechAudioEngine = SystemMacSpeechVoiceProcessingEngine()
        let speechCapture = SystemMacSpeechAudioCapture(audioEngine: speechAudioEngine)
        speechAudioHost = MacSpeechAudioHost(capture: speechCapture)
        #if DEBUG
            appleVPAcousticTestCapture = speechCapture
            appleVPSilentSmokeScenario = Self.silentSmokeScenario(arguments: ProcessInfo.processInfo.arguments)
            appleVPAcousticTestDurationNanoseconds = AppleVPAcousticTestLaunchMode.collectionDuration(
                silentScenario: appleVPSilentSmokeScenario
            )
            appleVPAcousticTestByteLimit = max(
                720_000, Int(appleVPAcousticTestDurationNanoseconds / 1_000_000_000) * 48000
            )
        #endif
        speechAudioOutputHost = MacSpeechAudioOutputHost(
            player: SystemMacSpeechAudioOutputPlayer(
                audioEngine: speechAudioEngine
            )
        )
        #if DEBUG
            let speechDiagnosticBuffer = NativeSpeechDiagnosticBuffer()
            nativeSpeechDiagnosticBuffer = speechDiagnosticBuffer
            realtimeSpeechDiagnosticAudioEngine = speechAudioEngine
            normalDependenciesFactory = {
                Self.makeNormalDependencies(diagnosticBuffer: speechDiagnosticBuffer)
            }
            restoreNormalConfiguration()
        #else
            let runtimeCore = QwenRealtimeRuntimeComposition.makeRuntimeCore(
                credentialReader: credentialStore,
                realtimeBrainConfiguration:
                ProductionQwenRealtimeBrainConfiguration.value,
                realtimeBrainConfigurationProvider: {
                    ProductionQwenRealtimeBrainConfiguration.value
                }
            )
            providerKeychainStore = credentialStore
            orchestrationKernel = OrchestrationKernel(runtimeCore: runtimeCore)
            restoreProviderConfiguration()
        #endif
    }

    init(orchestrationKernel: OrchestrationKernel) {
        #if DEBUG
            isAppleVPAcousticTestMode = false
            appleVPSilentSmokeScenario = nil
            normalDependenciesFactory = {
                NormalDependencies(
                    orchestrationKernel: orchestrationKernel,
                    providerKeychainStore: ProviderKeychainStore()
                )
            }
        #else
            self.orchestrationKernel = orchestrationKernel
            providerKeychainStore = ProviderKeychainStore()
        #endif
        let speechAudioEngine = SystemMacSpeechVoiceProcessingEngine()
        let speechCapture = SystemMacSpeechAudioCapture(audioEngine: speechAudioEngine)
        speechAudioHost = MacSpeechAudioHost(capture: speechCapture)
        #if DEBUG
            appleVPAcousticTestCapture = speechCapture
            appleVPAcousticTestDurationNanoseconds = 15_000_000_000
            appleVPAcousticTestByteLimit = 720_000
        #endif
        speechAudioOutputHost = MacSpeechAudioOutputHost(
            player: SystemMacSpeechAudioOutputPlayer(
                audioEngine: speechAudioEngine
            )
        )
        #if DEBUG
            nativeSpeechDiagnosticBuffer = NativeSpeechDiagnosticBuffer()
            realtimeSpeechDiagnosticAudioEngine = speechAudioEngine
            restoreNormalConfiguration()
        #else
            restoreProviderConfiguration()
        #endif
    }

    #if DEBUG
        init(
            orchestrationKernel: OrchestrationKernel,
            speechAudioHost: MacSpeechAudioHost,
            speechAudioOutputHost: MacSpeechAudioOutputHost =
                MacSpeechAudioOutputHost(),
            speechAudioCapture: (any MacSpeechAudioCapturing)? = nil,
            nativeSpeechProfile: NativeSpeechProviderProfile =
                Stage75NativeSpeechConfiguration.profile,
            nativeSpeechDiagnosticBuffer: NativeSpeechDiagnosticBuffer =
                NativeSpeechDiagnosticBuffer(),
            realtimeSpeechDiagnosticAudioEngine:
            SystemMacSpeechVoiceProcessingEngine? = nil
        ) {
            isAppleVPAcousticTestMode = false
            appleVPSilentSmokeScenario = nil
            normalDependenciesFactory = {
                NormalDependencies(
                    orchestrationKernel: orchestrationKernel,
                    providerKeychainStore: ProviderKeychainStore()
                )
            }
            self.speechAudioHost = speechAudioHost
            self.speechAudioOutputHost = speechAudioOutputHost
            appleVPAcousticTestCapture = speechAudioCapture
            appleVPAcousticTestDurationNanoseconds = 15_000_000_000
            appleVPAcousticTestByteLimit = 720_000
            self.nativeSpeechDiagnosticBuffer = nativeSpeechDiagnosticBuffer
            self.realtimeSpeechDiagnosticAudioEngine =
                realtimeSpeechDiagnosticAudioEngine
            restoreNormalConfiguration(nativeSpeechProfile: nativeSpeechProfile)
        }

        init(
            acousticTestArguments: [String],
            speechAudioHost: MacSpeechAudioHost,
            speechAudioOutputHost: MacSpeechAudioOutputHost,
            speechAudioCapture: (any MacSpeechAudioCapturing)? = nil,
            acousticTestDurationNanoseconds: UInt64 = 15_000_000_000,
            acousticTestByteLimit: Int = 720_000,
            acousticTestClock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
            acousticRuntimeTiming: ((UUID) -> MacSpeechTimingSnapshot?)? = nil,
            channelAllocationBuildVerifier: @escaping (String) -> Bool = MacSpeechChannelAllocation.Run.verifiesBuild,
            channelAllocationInstaller: ((MacSpeechChannelAllocation.Run, UUID, UInt64, UInt64) throws -> Void)? = nil,
            normalDependenciesFactory:
            @escaping @MainActor () -> (OrchestrationKernel, ProviderKeychainStore)
        ) {
            isAppleVPAcousticTestMode = AppleVPAcousticTestLaunchMode.isEnabled(
                arguments: acousticTestArguments
            )
            self.normalDependenciesFactory = {
                let (kernel, credentialStore) = normalDependenciesFactory()
                return NormalDependencies(
                    orchestrationKernel: kernel,
                    providerKeychainStore: credentialStore
                )
            }
            self.speechAudioHost = speechAudioHost
            self.speechAudioOutputHost = speechAudioOutputHost
            appleVPAcousticTestCapture = speechAudioCapture
            appleVPSilentSmokeScenario = Self.silentSmokeScenario(arguments: acousticTestArguments)
            appleVPAcousticTestDurationNanoseconds = min(15_000_000_000, max(1, acousticTestDurationNanoseconds))
            appleVPAcousticTestByteLimit = min(720_000, max(960, acousticTestByteLimit))
            appleVPAcousticClock = acousticTestClock
            appleVPAcousticRuntimeTiming = acousticRuntimeTiming
            appleVPScoreControlArguments = acousticTestArguments
            appleVPChannelBuildVerifier = channelAllocationBuildVerifier
            appleVPChannelInstaller = channelAllocationInstaller
            nativeSpeechDiagnosticBuffer = NativeSpeechDiagnosticBuffer()
            realtimeSpeechDiagnosticAudioEngine = nil
            restoreNormalConfiguration()
        }

        private static func makeNormalDependencies(
            diagnosticBuffer: NativeSpeechDiagnosticBuffer
        ) -> NormalDependencies {
            let credentialStore = ProviderKeychainStore()
            let runtimeCore = QwenRealtimeRuntimeComposition.makeDebugRuntimeCore(
                credentialReader: credentialStore,
                diagnosticBuffer: diagnosticBuffer,
                realtimeBrainConfiguration:
                ProductionQwenRealtimeBrainConfiguration.value,
                asrConfiguration: Stage7511QwenASRConfiguration.value,
                ttsConfiguration: Stage7511QwenTTSConfiguration.value,
                realtimeBrainConfigurationProvider: {
                    ProductionQwenRealtimeBrainConfiguration.value
                }
            )
            return NormalDependencies(
                orchestrationKernel: OrchestrationKernel(runtimeCore: runtimeCore),
                providerKeychainStore: credentialStore
            )
        }

        private func restoreNormalConfiguration() {
            guard !isAppleVPAcousticTestMode else { return }
            _ = normalDependencies
            realtimeBrainSessionConfiguration =
                ProductionQwenRealtimeBrainConfiguration.value
            nativeSpeechProviderDebugState = NativeSpeechProviderDebugViewState(
                profile: Stage75NativeSpeechConfiguration.profile
            )
            restoreProviderConfiguration()
            refreshNativeSpeechProviderDebugState()
        }

        private func restoreNormalConfiguration(
            nativeSpeechProfile: NativeSpeechProviderProfile
        ) {
            _ = normalDependencies
            realtimeBrainSessionConfiguration =
                ProductionQwenRealtimeBrainConfiguration.value
            nativeSpeechProviderDebugState = NativeSpeechProviderDebugViewState(
                profile: nativeSpeechProfile
            )
            restoreProviderConfiguration()
            refreshNativeSpeechProviderDebugState()
        }
    #endif

    func start() {
        #if DEBUG
            guard !isAppleVPAcousticTestMode else {
                startAppleVPAcousticMode()
                return
            }
        #endif
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
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
        latestParticleRenderMetrics = metrics
        refreshParticleDebugSnapshot()
        #if DEBUG
        refreshRuntimeOrchestrationState()
        #endif
    }

    func setParticleColorSource(_ source: ParticleColorSource) {
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
        particleColorSource = source
        applyEffectiveParticleColorProfile()
        refreshParticleDebugSnapshot()
    }

    var isResidentTextInputAvailable: Bool {
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return false }
        #endif
        return !loadedResidentID.isEmpty && !loadedSessionID.isEmpty
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
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return false }
        #endif
        return !realtimeBrainStopping
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
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return false }
        #endif
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
            guard !isAppleVPAcousticTestMode else { return }
        copyDialogueAudit { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
    }

    func copyDialogueAudit(using writer: (String) -> Bool) {
            guard !isAppleVPAcousticTestMode else { return }
        guard writer(dialogueAuditTranscript()) else {
            dialogueAuditState.statusKey = "dialogueAudit.status.copyFailed"
            return
        }
        dialogueAuditState.statusKey = "dialogueAudit.status.copied"
    }

    func exportDialogueAudit() {
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
        dialogueAuditState.clear()
    }

    func exportRealtimeSpeechDiagnostics() {
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { throw CocoaError(.featureUnsupported) }
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
        let configuration = realtimeBrainSessionConfiguration
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
            guard !isAppleVPAcousticTestMode else { throw CocoaError(.featureUnsupported) }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
        guard let text = runtimeOrchestrationTranscript(interactionID: interactionID),
              writer(text) else {
            runtimeOrchestrationState.statusKey = "runtimeOrchestration.status.copyFailed"
            return
        }
        runtimeOrchestrationState.statusKey = "runtimeOrchestration.status.copied"
    }

    func exportRuntimeOrchestrationInteraction(_ interactionID: UUID) {
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
        orchestrationKernel.clearRuntimeOrchestrationRecords()
        runtimeOrchestrationState = RuntimeOrchestrationViewState(
            statusKey: "runtimeOrchestration.status.cleared"
        )
    }

    func runtimeOrchestrationTranscript(
        interactionID: UUID,
        exportedAt: Date = Date()
    ) -> String? {
            guard !isAppleVPAcousticTestMode else { return nil }
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
            guard !isAppleVPAcousticTestMode else { throw CocoaError(.featureUnsupported) }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return "" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return dialogueAuditState.entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] \(entry.displayName)\n\(entry.text)"
        }.joined(separator: "\n\n")
    }

    func dialogueAuditExportText(exportedAt: Date = Date()) -> String {
            guard !isAppleVPAcousticTestMode else { return "" }
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
            guard !isAppleVPAcousticTestMode else { throw CocoaError(.featureUnsupported) }
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
            guard !isAppleVPAcousticTestMode else { return }
        relationshipProgressionDebugState =
            orchestrationKernel.resetRelationshipProgressionForDebug()
    }

    func setParticleAvatarMode(_ mode: ParticleAvatarMode) {
            guard !isAppleVPAcousticTestMode else { return }
        particleAvatarMode = mode
        particleRenderKind = mode == .abstractBustReserved ? .abstractBustReserved : .particleCore
        refreshParticleDebugSnapshot()
    }

    func setParticleRenderKind(_ kind: ParticleRenderKind) {
            guard !isAppleVPAcousticTestMode else { return }
        particleRenderKind = kind
        particleAvatarMode = kind.avatarMode
        refreshParticleDebugSnapshot()
    }

    func toggleParticleDebugPanel() {
            guard !isAppleVPAcousticTestMode else { return }
        isParticleDebugPanelPresented.toggle()
    }

    func setParticleDebugPanelPresented(_ isPresented: Bool) {
            guard !isAppleVPAcousticTestMode else { return }
        isParticleDebugPanelPresented = isPresented
        if isPresented {
            refreshRuntimeOrchestrationState()
        }
    }

    func setParticleShellMode(_ mode: ParticleShellMode) {
            guard !isAppleVPAcousticTestMode else { return }
        particleShellMode = mode
        refreshParticleDebugSnapshot()
    }

    func showDebugSubtitle() {
            guard !isAppleVPAcousticTestMode else { return }
        showDebugSubtitle(at: debugSubtitleIndex)
    }

    func showNextDebugSubtitle() {
            guard !isAppleVPAcousticTestMode else { return }
        debugSubtitleIndex = (debugSubtitleIndex + 1) % debugSubtitleKeys.count
        showDebugSubtitle(at: debugSubtitleIndex)
    }

    func hideDebugSubtitle() {
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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

    var canSelectRealtimeSpeechModel: Bool {
            !isAppleVPAcousticTestMode && !nativeSpeechProviderDebugState.isTesting
            && !speechInputBridgeSnapshot.hasActivePump
            && !speechOutputBridgeSnapshot.hasActiveReceiveLoop
            && realtimeBrainRouteAttemptID == nil
            && !realtimeBrainStartInFlight
            && !realtimeBrainStopping
            && realtimeBrainInputBinding == nil
            && speechHostLifecycleOperationCount == 0
            && speechAudioHostShutdownOperation == nil
    }

    func selectNativeSpeechModel(_ modelID: String) {
            guard !isAppleVPAcousticTestMode else { return }
        guard let model = Stage75QwenRealtimeModel(rawValue: modelID),
              canSelectRealtimeSpeechModel else { return }
        UserDefaults.standard.set(
            model.rawValue,
            forKey: ProductionQwenRealtimeBrainConfiguration.preferenceKey
        )
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
        speechAudioHostShutdownCompleted = false
        _ = await ensureRealtimeMicrophoneAuthorization()
    }

    func startSpeechAudioCapture() async {
            guard !isAppleVPAcousticTestMode else { return }
            guard speechHostLifecycleOperationCount == 0,
                  realtimeBrainRouteAttemptID == nil,
                  realtimeBrainInputBinding == nil,
                  !hasActiveAlternateSpeechRoute else { return }
        speechAudioHostShutdownCompleted = false
            let stopGeneration = speechHostStopGeneration
        speechHostLifecycleOperationCount += 1
        defer { speechHostLifecycleOperationCount -= 1 }
            do {
                try await selectSpeechAudioProcessingMode(
                    .webRTCAEC3,
                    stopGeneration: stopGeneration
                )
            } catch {
                recordRealtimeSpeechDiagnostic(
                    source: .lifecycle,
                    category: "capture_start_failed",
                    errorCode: (error as? MacSpeechAudioCaptureError)?.rawValue
                        ?? "audio_backend_unavailable"
                )
                return
            }
        speechAudioHostSnapshot = await speechAudioHost.startCapture()
            guard speechHostStopGeneration == stopGeneration else {
                speechAudioHostSnapshot = await speechAudioHost.stopCapture()
                return
            }
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
            guard !isAppleVPAcousticTestMode else { return }
            speechHostStopGeneration &+= 1
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
        speechHostStopGeneration &+= 1
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
        #if DEBUG
            if isAppleVPAcousticTestMode {
                await closeAppleVPAcousticRunForShutdown()
                return
            }
        #endif
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
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
        await startRealtimeResidentBrainRoute()
    }

    func startRealtimeResidentBrainRoute() async {
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
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
        realtimeBrainSessionConfiguration = ProductionQwenRealtimeBrainConfiguration.value
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
            await settleAbandonedRealtimeAuthorization()
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
        guard await prepareRealtimeSpeechAudioBackend(attemptID: attemptID) else {
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

    private func prepareRealtimeSpeechAudioBackend(attemptID: UUID) async -> Bool {
        do {
            try await selectSpeechAudioProcessingMode(
                .appleVoiceProcessing,
                stopGeneration: speechHostStopGeneration
            )
        } catch {
            guard realtimeBrainRouteAttemptID == attemptID else { return false }
            realtimeBrainRouteAttemptID = nil
            publishRealtimeResidentBrainRouteFailure(
                (error as? MacSpeechAudioCaptureError)?.rawValue
                    ?? "audio_backend_unavailable"
            )
            return false
        }
        guard realtimeBrainRouteAttemptID == attemptID else { return false }
        return true
    }

    private func settleAbandonedRealtimeAuthorization() async {
        if speechAudioHostShutdownOperation != nil || speechAudioHostShutdownCompleted {
            await speechAudioHost.shutdown()
            speechAudioHostSnapshot =
                await speechAudioHost.currentSnapshot()
        }
    }

    private func selectSpeechAudioProcessingMode(
        _ mode: MacSpeechAudioProcessingMode,
        stopGeneration: UInt64
    ) async throws {
        guard speechHostStopGeneration == stopGeneration,
              speechAudioHostShutdownOperation == nil,
              !speechAudioHostShutdownCompleted,
              await speechAudioOutputHost.canSelectAudioProcessingMode(),
              speechHostStopGeneration == stopGeneration
        else {
            throw MacSpeechAudioCaptureError.processingModeBusy
        }
        try await speechAudioHost.selectProcessingMode(mode)
        guard speechHostStopGeneration == stopGeneration,
              speechAudioHostShutdownOperation == nil,
              !speechAudioHostShutdownCompleted
        else {
            throw MacSpeechAudioCaptureError.processingModeBusy
        }
    }

    func stopRealtimeFullDuplexSpeech() async {
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
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
        #if DEBUG
        realtimePlaybackEnqueueObserverForTesting?(
            identity.session.generation, playbackGeneration, audio.sequence
        )
        #endif
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
            guard !isAppleVPAcousticTestMode else { return }
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
            let stopGeneration = speechHostStopGeneration
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
            guard let captureGeneration = await prepareFormalSpeechCapture(
                stopGeneration: stopGeneration
            ) else { return }
            guard let generation = await startFormalSpeechASR(
                captureGeneration: captureGeneration,
                stopGeneration: stopGeneration
            ) else { return }

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
            guard speechHostStopGeneration == stopGeneration else { return }
        speechAudioHostSnapshot = await speechAudioHost
            .startPreparedCapture(generation: captureGeneration)
            guard speechHostStopGeneration == stopGeneration else { return }
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

        private func prepareFormalSpeechCapture(stopGeneration: UInt64) async -> UInt64? {
            do {
                try await selectSpeechAudioProcessingMode(
                    .webRTCAEC3,
                    stopGeneration: stopGeneration
                )
            } catch {
                guard speechHostStopGeneration == stopGeneration else { return nil }
                publishFormalSpeechRouteFailure(
                    (error as? MacSpeechAudioCaptureError)?.rawValue
                        ?? "audio_backend_unavailable"
                )
                return nil
            }
            let preparedCaptureGeneration =
                await speechAudioHost.prepareCaptureGeneration()
            guard speechHostStopGeneration == stopGeneration else {
                if let preparedCaptureGeneration {
                    _ = await speechAudioHost.cancelPreparedCapture(
                        generation: preparedCaptureGeneration
                    )
                }
                return nil
            }
            guard let captureGeneration = preparedCaptureGeneration else {
                speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
                publishFormalSpeechRouteFailure("capture_unavailable")
                return nil
            }
            return captureGeneration
        }

        private func startFormalSpeechASR(
            captureGeneration: UInt64,
            stopGeneration: UInt64
        ) async -> UInt64? {
            let startResult = await orchestrationKernel.startSpeechRouteASR(
                locale: "zh-CN"
            )
            guard speechHostStopGeneration == stopGeneration else {
                if case let .success(generation) = startResult {
                    _ = await orchestrationKernel.cancelSpeechRoute(generation: generation)
                }
                _ = await speechAudioHost.cancelPreparedCapture(generation: captureGeneration)
                return nil
            }
            guard case let .success(generation) = startResult else {
                speechAudioHostSnapshot = await speechAudioHost
                    .cancelPreparedCapture(generation: captureGeneration)
                if case let .failure(error) = startResult {
                    publishFormalSpeechRouteFailure(
                        Self.formalSpeechErrorCode(error)
                    )
                }
                return nil
            }

            return generation
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
                speechAudioOutputHostSnapshot = await speechAudioOutputHost.close()
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
            speechAudioOutputHostSnapshot = await speechAudioOutputHost.close()
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
            guard !isAppleVPAcousticTestMode else { return }
            await startNormalNativeSpeechInput()
        }

        private func startNormalNativeSpeechInput() async {
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
            let stopGeneration = speechHostStopGeneration
        speechHostLifecycleOperationCount += 1
        defer { speechHostLifecycleOperationCount -= 1 }
            guard let captureGeneration = await prepareNativeSpeechCapture(
                stopGeneration: stopGeneration
            ) else { return }
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
            guard speechHostStopGeneration == stopGeneration else {
                if case let .success(binding) = result {
                    _ = await orchestrationKernel.closeNativeSpeechInput(binding: binding)
                }
                _ = await speechAudioHost.cancelPreparedCapture(generation: captureGeneration)
                return
            }
        switch result {
        case .success(let binding):
                guard await prepareNativeSpeechPlayback(
                    binding: binding,
                    stopGeneration: stopGeneration
                ) else { return }
            speechAudioHostSnapshot = await speechAudioHost
                .startPreparedCapture(generation: captureGeneration)
                guard speechHostStopGeneration == stopGeneration else {
                    _ = await orchestrationKernel.closeNativeSpeechInput(binding: binding)
                    return
                }
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
                guard speechHostStopGeneration == stopGeneration else { return }
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

        private func prepareNativeSpeechCapture(stopGeneration: UInt64) async -> UInt64? {
            do {
                try await selectSpeechAudioProcessingMode(
                    .webRTCAEC3,
                    stopGeneration: stopGeneration
                )
            } catch {
                guard speechHostStopGeneration == stopGeneration else { return nil }
                speechInputBridgeSnapshot = await speechInputBridge.fail(.unavailable)
                recordRealtimeSpeechDiagnostic(
                    source: .lifecycle,
                    category: "bridge_start_failed",
                    errorCode: (error as? MacSpeechAudioCaptureError)?.rawValue
                        ?? "audio_backend_unavailable"
                )
                return nil
            }
            let preparedCaptureGeneration =
                await speechAudioHost.prepareCaptureGeneration()
            guard speechHostStopGeneration == stopGeneration else {
                if let preparedCaptureGeneration {
                    _ = await speechAudioHost.cancelPreparedCapture(
                        generation: preparedCaptureGeneration
                    )
                }
                return nil
            }
            guard let captureGeneration = preparedCaptureGeneration else {
                speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
                speechInputBridgeSnapshot =
                    await speechInputBridge.fail(.unavailable)
                recordRealtimeSpeechDiagnostic(
                    source: .lifecycle,
                    category: "bridge_start_failed",
                    errorCode: "capture_unavailable"
                )
                return nil
            }
            return captureGeneration
        }

        private func prepareNativeSpeechPlayback(
            binding: NativeSpeechInputBinding,
            stopGeneration: UInt64
        ) async -> Bool {
            residentTextPresentationID = nil
            await speechOutputDebugSink.reset()
            guard speechHostStopGeneration == stopGeneration else {
                _ = await orchestrationKernel.closeNativeSpeechInput(binding: binding)
                return false
            }
            nativeSpeechPlaybackBinding = nil
            projectedNativeSpeechDialogueHistoryIdentities.removeAll(
                keepingCapacity: true
            )
            lastPlaybackEventOrdinal = 0
            await speechAudioOutputHost.setEventSink { [weak self] event in
                await self?.consumePlaybackHostEvent(event)
            }
            guard speechHostStopGeneration == stopGeneration else {
                _ = await orchestrationKernel.closeNativeSpeechInput(binding: binding)
                return false
            }
            speechOutputBridgeSnapshot = await speechOutputBridge.start(
                binding: binding
            )
            guard speechHostStopGeneration == stopGeneration else {
                _ = await orchestrationKernel.closeNativeSpeechInput(binding: binding)
                return false
            }
            return true
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
            guard !isAppleVPAcousticTestMode else { return }
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
            guard !isAppleVPAcousticTestMode else { return }
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
        #if DEBUG
            guard !isAppleVPAcousticTestMode else {
                return RuntimeStepResponse(
                    outputText: "",
                    visualState: VisualState(mode: .idle),
                    avatarState: AvatarState(
                        residentID: "", displayName: "", mode: "idle",
                        presence: "unavailable", moodHint: "", activityHint: "",
                        particleHint: ""
                    ),
                    residentState: RuntimeResidentState(
                        residentID: "", sessionID: "", lifecycleStatus: "unavailable",
                        presence: "unavailable", lastActivitySummary: ""
                    ),
                    cancellationState: RuntimeCancellationState(
                        isCancelled: true, reason: .cancelled
                    ),
                    traceEvents: [],
                    diagnostics: RuntimeDiagnostics(
                        providerMode: "unavailable", cancellationState: "cancelled"
                    )
                )
            }
        #endif
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
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
        orchestrationKernel.cancelCurrentStep()
        runtimeState = .cancelled
        residentSpeechSignal = .ended
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()
    }

    func interrupt() {
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
        orchestrationKernel.interrupt()
        runtimeState = .interrupted
        residentSpeechSignal = .ended
        refreshResidentVisualIntent()
        refreshParticleDebugSnapshot()
    }

    func runtimeTick() {
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
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
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
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
        #if DEBUG
            guard !isAppleVPAcousticTestMode else { return }
        #endif
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

#if DEBUG
    extension AppController {
        private static func silentSmokeScenario(arguments: [String]) -> AppleVPAcousticTestScenario? {
            guard AppleVPAcousticTestLaunchMode.isEnabled(arguments: arguments),
                  let argument = arguments.first(where: { $0.hasPrefix(AppleVPAcousticTestLaunchMode.silentArgument) })
            else { return nil }
            return AppleVPAcousticTestScenario(rawValue: String(argument.dropFirst(
                AppleVPAcousticTestLaunchMode.silentArgument.count
            )))
        }

        private func startAppleVPAcousticMode() {
            startupState = .idle
            runtimeState = .idle
            guard appleVPSilentSmokeScenario != nil, !appleVPSilentSmokeStarted else { return }
            appleVPSilentSmokeStarted = true
            Task { @MainActor [weak self] in await self?.runAppleVPSilentSmoke() }
        }

        private func runAppleVPSilentSmoke() async {
            guard let scenario = appleVPSilentSmokeScenario, prepareAppleVPAcousticTest(scenario) else { return }
            startAppleVPAcousticTest(microphoneConsent: true, speakerConsent: true, localCaptureConsent: true)
            await appleVPAcousticTestTask?.value
            guard appleVPAcousticRun.canExport else { return }
            do {
                let url = try appleVPAcousticTestExportURL(asWAV: false)
                try writeAppleVPAcousticTestJSON(to: url, localExportConsent: true)
                print("apple_vp_silent_smoke_manifest=\(url.lastPathComponent)")
            } catch {
                print("apple_vp_silent_smoke_export=FAIL")
            }
        }

        @discardableResult
        func prepareAppleVPAcousticTest(
            _ scenario: AppleVPAcousticTestScenario,
            discardPreviousResult: Bool = false,
            comprehensiveC: Bool = false,
            dataMode: AppleVPAcousticDataMode = .recording,
            processingProfile: MacSpeechAppleVPDebugProfile = .agcOn,
            warmupProfile: MacSpeechWarmupProfile? = nil,
            btAcousticBatch: Bool = false,
            humanAcousticBatch: Bool = false,
            humanOnsetProfile: AppleVPHumanOnsetProfile? = nil,
            macAECBatch: Bool = false
        ) -> Bool {
            let batchArguments = appleVPScoreControlArguments.filter { $0.hasPrefix("--apple-vp-bt-abc=") }
            let humanArguments = appleVPScoreControlArguments.filter { $0.hasPrefix("--apple-vp-human-abc=") }
            let onsetArguments = appleVPScoreControlArguments.filter { $0.hasPrefix("--apple-vp-human-onset=") }
            let isBatch = btAcousticBatch || humanAcousticBatch || macAECBatch
                || appleVPAdaptation != nil || appleVPChannelAllocation != nil
            guard acceptsAdaptationPreparation(
                (comprehensiveC, btAcousticBatch || humanAcousticBatch || macAECBatch || humanOnsetProfile != nil),
                scenario: scenario, dataMode: dataMode, profile: processingProfile, warmup: warmupProfile
            ) else { return false }
            guard acceptsMacAECPreparation(
                (macAECBatch, comprehensiveC), scenario: scenario, mode: dataMode,
                processing: processingProfile, warmup: warmupProfile
            ) else { return false }
            guard !(btAcousticBatch && humanAcousticBatch),
                  onsetArguments.isEmpty || (humanArguments.isEmpty && batchArguments.isEmpty
                      && humanOnsetProfile != nil && humanOnsetProfile == appleVPHumanOnsetProfile),
                  humanOnsetProfile == nil || (humanAcousticBatch && scenario == .doubleTalk
                      && humanOnsetProfile == appleVPHumanOnsetProfile),
                  batchArguments.isEmpty || (btAcousticBatch && appleVPBTBatchScenario == scenario),
                  humanArguments.isEmpty || (humanAcousticBatch && appleVPHumanBatchScenario == scenario),
                  !btAcousticBatch || (appleVPBTBatchScenario == scenario && comprehensiveC
                      && processingProfile == .agcOn && warmupProfile == .four && dataMode == .recording),
                  !humanAcousticBatch || (appleVPHumanBatchScenario == scenario && comprehensiveC
                      && processingProfile == .agcOn && warmupProfile == .four && dataMode == .recording
                      && appleVPAcousticTestDurationNanoseconds == 15_000_000_000
                      && appleVPAcousticTestByteLimit == 720_000)
            else { return false }
            guard isAppleVPAcousticTestMode, appleVPAcousticTestTask == nil,
                  !comprehensiveC
                  || ((scenario == .doubleTalk || isBatch) && appleVPSilentSmokeScenario == nil),
                  processingProfile == .agcOn || appleVPSilentSmokeScenario == nil,
                  warmupProfile == nil || (comprehensiveC && (processingProfile == .agcOn || warmupProfile == .four)),
                  speechAudioHostShutdownOperation == nil, speechHostLifecycleOperationCount == 0,
                  !appleVPAcousticRun.isBusy,
                  appleVPAcousticRun.runID == nil || discardPreviousResult else { return false }
            resetAppleVPAcousticPreparation()
            appleVPAcousticRun.scenario = scenario
            appleVPAcousticRun.comprehensiveC = comprehensiveC
            appleVPAcousticRun.btAcousticBatch = btAcousticBatch
            appleVPAcousticRun.humanAcousticBatch = humanAcousticBatch
            appleVPAcousticRun.macAECBatch = macAECBatch ? appleVPMacAECBatch : nil
            appleVPAcousticRun.adaptation = appleVPAdaptation
            appleVPAcousticRun.allocation = appleVPChannelAllocation
            appleVPAcousticRun.humanOnsetProfile = humanOnsetProfile
            appleVPAcousticRun.dataMode = appleVPSilentSmokeScenario == nil ? dataMode : .statsOnly
            appleVPAcousticRun.processingProfile = processingProfile
            appleVPAcousticRun.warmupProfile = warmupProfile
            appleVPAcousticRun.phase = .ready
            publishAppleVPAcousticState(force: true)
            return true
        }

        private func resetAppleVPAcousticPreparation() {
            if let runID = appleVPAcousticRun.runID {
                appleVPAcousticTestCapture?.clearNativeVoiceDebug(runID: runID)
            }
            let url = appleVPAcousticRun.playbackURL
            let pendingAuthorization = appleVPAcousticRun.authorizationRunID
            appleVPAcousticRun = AppleVPAcousticTestState()
            appleVPAcousticRun.authorizationRunID = pendingAuthorization
            appleVPAcousticRun.playbackURL = url
        }

        private func acceptsChannelAllocationPreparation(
            _ options: (guided: Bool, otherBatch: Bool), scenario: AppleVPAcousticTestScenario,
            mode: AppleVPAcousticDataMode, profile: MacSpeechAppleVPDebugProfile, warmup: MacSpeechWarmupProfile?,
        ) -> Bool {
            let args = appleVPScoreControlArguments
            guard args.contains(where: { $0.hasPrefix(MacSpeechChannelAllocation.Run.argument) }) else { return true }
            let excluded = [AppleVPMacAECBatchRun.argument, AppleVPAdaptationRun.argument,
                            "--apple-vp-bt-abc=", "--apple-vp-human-abc=", "--apple-vp-human-onset="]
            return appleVPChannelAllocation != nil && !options.otherBatch
                && !args.contains { arg in excluded.contains { arg.hasPrefix($0) } }
                && options.guided && scenario == .residentOnly && mode == .recording && profile == .agcOn
                && warmup == .four && appleVPSilentSmokeScenario == nil
                && appleVPAcousticRun.runID == nil && !appleVPAcousticRun.macAECCancelled
                && appleVPAcousticTestDurationNanoseconds == 15_000_000_000 && appleVPAcousticTestByteLimit == 720_000
        }

        private func acceptsAdaptationPreparation(
            _ options: (guided: Bool, otherBatch: Bool), scenario: AppleVPAcousticTestScenario,
            dataMode: AppleVPAcousticDataMode, profile: MacSpeechAppleVPDebugProfile, warmup: MacSpeechWarmupProfile?
        ) -> Bool {
            guard acceptsChannelAllocationPreparation(
                options, scenario: scenario, mode: dataMode, profile: profile, warmup: warmup,
            ) else { return false }
            let args = appleVPScoreControlArguments
            guard args.contains(where: { $0.hasPrefix(AppleVPAdaptationRun.argument) }) else { return true }
            let excluded = [AppleVPMacAECBatchRun.argument, "--apple-vp-bt-abc=",
                            "--apple-vp-human-abc=", "--apple-vp-human-onset="]
            return appleVPAdaptation != nil && !options.otherBatch
                && !args.contains { arg in excluded.contains { arg.hasPrefix($0) } }
                && scenario == .residentOnly && options.guided && dataMode == .recording
                && profile == .agcOn && warmup == .four && appleVPSilentSmokeScenario == nil
                && appleVPAcousticRun.runID == nil && !appleVPAcousticRun.macAECCancelled
                && appleVPAcousticTestDurationNanoseconds == 15_000_000_000
                && appleVPAcousticTestByteLimit == 720_000
        }

        private func acceptsMacAECPreparation(
            _ options: (requested: Bool, guided: Bool), scenario: AppleVPAcousticTestScenario,
            mode: AppleVPAcousticDataMode, processing: MacSpeechAppleVPDebugProfile,
            warmup: MacSpeechWarmupProfile?
        ) -> Bool {
            let arguments = appleVPScoreControlArguments
            let hasArgument = arguments.contains { $0.hasPrefix(AppleVPMacAECBatchRun.argument) }
            guard options.requested else { return !hasArgument }
            let legacyPrefixes = ["--apple-vp-bt-abc=", "--apple-vp-human-abc=", "--apple-vp-human-onset="]
            return appleVPMacAECBatch != nil && !arguments.contains { value in
                legacyPrefixes.contains { value.hasPrefix($0) }
            } && scenario == .residentOnly && options.guided && mode == .recording
                && processing == .agcOn && warmup == .four && appleVPSilentSmokeScenario == nil
                && appleVPAcousticRun.runID == nil && !appleVPAcousticRun.macAECCancelled
                && appleVPAcousticTestDurationNanoseconds == 15_000_000_000
                && appleVPAcousticTestByteLimit == 720_000
        }

        @discardableResult
        func selectAppleVPAcousticPlaybackURL(_ url: URL?) -> Bool {
            guard isAppleVPAcousticTestMode, !appleVPAcousticRun.isBusy,
                  appleVPAcousticRun.runID == nil else { return false }
            appleVPAcousticRun.playbackURL = url
            publishAppleVPAcousticState(force: true)
            return true
        }

        func startAppleVPAcousticTest(
            microphoneConsent: Bool, speakerConsent: Bool, localCaptureConsent: Bool
        ) {
            guard isAppleVPAcousticTestMode, appleVPAcousticRun.phase == .ready,
                  !appleVPAcousticRun.macAECCancelled,
                  appleVPAcousticTestTask == nil, speechAudioHostShutdownOperation == nil,
                  speechHostLifecycleOperationCount == 0 else { return }
            guard microphoneConsent, appleVPAcousticRun.dataMode == .statsOnly || localCaptureConsent,
                  (appleVPAcousticRun.scenario == .humanOnly && !appleVPAcousticRun.btAcousticBatch) || speakerConsent
            else {
                appleVPAcousticRun.errorCode = AppleVPAcousticTestError.consentRequired.rawValue
                publishAppleVPAcousticState(force: true)
                return
            }
            guard appleVPAcousticRun.authorizationRunID == nil else {
                appleVPAcousticRun.errorCode = "authorization_pending"
                publishAppleVPAcousticState(force: true)
                return
            }
            guard appleVPAcousticTestCapture != nil else {
                appleVPAcousticRun.errorCode = AppleVPAcousticTestError.unavailable.rawValue
                publishAppleVPAcousticState(force: true)
                return
            }
            do {
                appleVPScoreControl = try AppleVPScoreControl(arguments: appleVPScoreControlArguments)
                guard !appleVPAcousticRun.isAcousticBatch || appleVPScoreControl != nil else {
                    throw AppleVPAcousticTestError.externalPlaybackControl
                }
                guard appleVPScoreControl == nil || (appleVPAcousticRun.comprehensiveC
                    && appleVPAcousticRun.warmupProfile != nil
                    && (appleVPAcousticRun.processingProfile == .agcOn || appleVPAcousticRun.warmupProfile == .four))
                else { throw AppleVPAcousticTestError.externalPlaybackControl }
            } catch {
                appleVPAcousticRun.errorCode = AppleVPAcousticTestError.externalPlaybackControl.rawValue
                publishAppleVPAcousticState(force: true)
                return
            }
            speechAudioHostShutdownCompleted = false
            let runID = UUID()
            appleVPAcousticRun.runID = runID
            appleVPAcousticRun.stopGeneration = speechHostStopGeneration
            appleVPAcousticRun.errorCode = nil
            appleVPAcousticRun.phase = .starting
            publishAppleVPAcousticState(force: true)
            appleVPAcousticTestTask = Task { @MainActor [weak self] in
                await self?.runAppleVPAcousticTest(runID: runID)
            }
        }

        func stopAppleVPAcousticTest() async {
            guard isAppleVPAcousticTestMode else { return }
            if appleVPMacAECBatch != nil || appleVPAdaptation != nil || appleVPChannelAllocation != nil {
                appleVPAcousticRun.macAECCancelled = true
                appleVPAcousticRun.errorCode = "cancelled"
            }
            if appleVPAcousticRun.isBusy {
                appleVPAcousticRun.phase = .stopping
                appleVPAcousticRun.errorCode = "cancelled"
            }
            await shutdownSpeechAudioHost()
        }

        private func runAppleVPAcousticTest(runID: UUID) async {
            var failure: String?
            do {
                let playback = try appleVPAcousticPlaybackBytes()
                if let allocation = appleVPAcousticRun.allocation,
                   !appleVPChannelBuildVerifier(allocation.buildSHA) {
                    throw AppleVPAcousticTestError.externalPlaybackControl
                }
                try await authorizeAppleVPAcousticTest(runID: runID)
                let generation = try await prepareAppleVPAcousticAudio(runID: runID)
                try await startAppleVPAcousticAudio(runID: runID, generation: generation, playback: playback)
                appleVPAcousticRun.phase = .running
                publishAppleVPAcousticState(force: true)
                try await collectAppleVPAcousticFrames(runID: runID, playback: playback)
                try validateAppleVPRuntimeDiagnostics(runID: runID)
                try validateAppleVPAcousticCCompletion()
            } catch {
                failure = error is CancellationError ? "cancelled"
                    : (error as? AppleVPRuntimeSafetyError)?.rawValue
                    ?? (error as? AppleVPAcousticTestError)?.rawValue ?? "acoustic_test_failed"
            }
            await finishAppleVPAcousticTest(runID: runID, failure: failure)
        }

        private func appleVPAcousticPlaybackBytes() throws -> Data? {
            guard appleVPAcousticRun.scenario != .humanOnly else { return nil }
            if appleVPSilentSmokeScenario != nil {
                return Data(repeating: 0, count: 96000)
            }
            guard let url = appleVPAcousticRun.playbackURL else { throw AppleVPAcousticTestError.invalidFile }
            do {
                let source = try AppleVPAcousticWAV.read(url: url)
                appleVPAcousticRun.playbackSHA256 = source.sha256
                let macResidentSHA = AppleVPMacAECBatchRun.residentSHA256
                if appleVPAcousticRun.macAECBatch != nil || appleVPAcousticRun.adaptation != nil
                    || appleVPAcousticRun.allocation != nil,
                   source.sha256 != macResidentSHA {
                    throw AppleVPAcousticTestError.invalidFile
                }
                if appleVPAcousticRun.comprehensiveC {
                    guard (144_000 ... 288_000).contains(source.pcm.count),
                          appleVPAcousticTestDurationNanoseconds == 15_000_000_000,
                          appleVPAcousticTestByteLimit == 720_000
                    else {
                        throw AppleVPAcousticTestError.invalidFile
                    }
                }
                return source.pcm
            } catch { throw AppleVPAcousticTestError.invalidFile }
        }

        private func authorizeAppleVPAcousticTest(runID: UUID) async throws {
            appleVPAcousticRun.authorizationRunID = runID
            let current = await speechAudioHost.refreshAuthorization()
            try await acceptAppleVPAcousticAuthorization(current, runID: runID)
            if appleVPSilentSmokeScenario != nil, speechAudioHostSnapshot.authorization != .authorized {
                throw AppleVPAcousticTestError.permissionDenied
            }
            if speechAudioHostSnapshot.authorization == .notDetermined {
                appleVPAcousticRun.authorizationRunID = runID
                let requested = await speechAudioHost.requestMicrophoneAuthorization()
                try await acceptAppleVPAcousticAuthorization(requested, runID: runID)
            }
            guard speechAudioHostSnapshot.authorization == .authorized else {
                throw AppleVPAcousticTestError.permissionDenied
            }
            guard speechAudioHostSnapshot.inputDevice.isAvailable,
                  speechAudioHostSnapshot.outputDevice.isAvailable else { throw AppleVPAcousticTestError.routeChanged }
        }

        private func acceptAppleVPAcousticAuthorization(
            _ snapshot: MacSpeechAudioHostSnapshot, runID: UUID
        ) async throws {
            do { try checkAppleVPAcousticRun(runID) } catch {
                if !appleVPAcousticRun.isBusy, speechAudioHostShutdownOperation == nil {
                    speechAudioHostShutdownCompleted = false
                    await shutdownSpeechAudioHost()
                }
                if appleVPAcousticRun.authorizationRunID == runID {
                    appleVPAcousticRun.authorizationRunID = nil
                    publishAppleVPAcousticState(force: true)
                }
                throw error
            }
            if appleVPAcousticRun.authorizationRunID == runID {
                appleVPAcousticRun.authorizationRunID = nil
            }
            speechAudioHostSnapshot = snapshot
        }

        private func prepareAppleVPAcousticAudio(runID: UUID) async throws -> UInt64 {
            try await selectSpeechAudioProcessingMode(.appleVoiceProcessing, stopGeneration: speechHostStopGeneration)
            try checkAppleVPAcousticRun(runID)
            let generation = await speechAudioHost.prepareCaptureGeneration()
            try checkAppleVPAcousticRun(runID)
            guard let generation,
                  appleVPAcousticTestCapture?.armNativeVoiceDebug(
                      runID: runID, generation: generation, profile: appleVPAcousticRun.processingProfile
                  ) == true
            else {
                throw AppleVPAcousticTestError.captureUnavailable
            }
            appleVPAcousticRun.generation = generation
            return generation
        }

        private func startAppleVPAcousticAudio(runID: UUID, generation: UInt64, playback: Data?) async throws {
            if playback != nil || appleVPAcousticRun.isAcousticBatch {
                let output = await speechAudioOutputHost.prepare()
                try checkAppleVPAcousticRun(runID)
                speechAudioOutputHostSnapshot = output
                guard output.state == .prepared else { throw AppleVPAcousticTestError.playbackFailed }
                if appleVPAcousticRun.comprehensiveC {
                    appleVPAcousticRun.playbackGeneration = output.generation
                }
                realtimeSpeechDiagnosticAudioEngine?.bindNativeVoiceTimingPlayback(
                    runID: runID, generation: output.generation
                )
                if let allocation = appleVPAcousticRun.allocation {
                    if let engine = realtimeSpeechDiagnosticAudioEngine {
                        try engine.configureChannelAllocation(allocation, runID: runID,
                                                              generation: generation,
                                                              playbackGeneration: output.generation)
                    } else if let install = appleVPChannelInstaller {
                        try install(allocation, runID, generation, output.generation)
                    } else {
                        throw AppleVPAcousticTestError.playbackFailed
                    }
                }
            }
            let capture = await speechAudioHost.startPreparedCapture(generation: generation)
            try checkAppleVPAcousticRun(runID)
            speechAudioHostSnapshot = capture
            guard capture.isCapturing else { throw AppleVPAcousticTestError.captureUnavailable }
            appleVPAcousticRun.route = capture
            appleVPAcousticRun.native = appleVPAcousticTestCapture?.nativeVoiceDebugSnapshot(runID: runID)
            guard let voice = appleVPAcousticRun.native?.voiceProcessing,
                  appleVPAcousticRun.native?.runID == runID,
                  appleVPAcousticRun.native?.profile == appleVPAcousticRun.processingProfile,
                  appleVPAcousticRun.processingProfile.accepts(voice),
                  voice.configurationID > 0, voice.validatedAtNanoseconds > 0,
                  appleVPAcousticRun.native?.captureGeneration == generation,
                  appleVPAcousticRun.native?.configurationID == voice.configurationID
            else {
                throw AppleVPAcousticTestError.voiceProcessingUnavailable
            }
            try validateAppleVPRuntimeDiagnostics(runID: runID)
            if appleVPAcousticRun.comprehensiveC {
                try beginAppleVPAcousticScoring(runID: runID, generation: generation)
                return
            }
            guard let playback else { return }
            scheduleAppleVPAcousticPlayback(playback, runID: runID)
        }

        private func beginAppleVPAcousticScoring(runID: UUID, generation: UInt64) throws {
            appleVPAcousticRun.pcmShortWindows = MacSpeechShortWindowStats(source: .pcm)
            let now = appleVPAcousticClock()
            var scoreStart = now
            if let profile = appleVPAcousticRun.warmupProfile {
                guard let plan = MacSpeechAcousticWindowPlan(captureStartedAt: now, profile: profile),
                      appleVPAcousticTestCapture?.configureNativeAcousticWindows(
                          runID: runID, generation: generation, plan: plan
                      ) == true else { throw AppleVPAcousticTestError.voiceProcessingUnavailable }
                appleVPAcousticRun.warmupDrain = AppleVPWarmupDrainState(plan: plan)
                scoreStart = plan.scoreStartedAt
            }
            appleVPAcousticRun.lastCollectionClock = now
            appleVPAcousticRun.guideStartedAt = scoreStart
            if scoreStart == now {
                appleVPAcousticRun.guideEvents["human_only"] = now
            }
            try appleVPScoreControl?.send(
                "schedule", runID: runID, scoreStart: scoreStart,
                batchScenario: appleVPAcousticRun.isAcousticBatch ? appleVPAcousticRun.scenario : nil,
                humanBatch: appleVPAcousticRun.humanAcousticBatch,
                onsetProfile: appleVPAcousticRun.humanOnsetProfile,
                macAECBatch: appleVPAcousticRun.macAECBatch, adaptation: appleVPAcousticRun.adaptation,
                allocation: appleVPAcousticRun.allocation,
            )
        }

        private func scheduleAppleVPAcousticPlayback(_ playback: Data, runID: UUID) {
            let outputGeneration = speechAudioOutputHostSnapshot.generation
            appleVPAcousticRun.playbackGeneration = outputGeneration
            appleVPAcousticPlaybackTask = Task { @MainActor [weak self] in
                await self?.pumpAppleVPAcousticPlayback(playback, generation: outputGeneration, runID: runID)
            }
        }

        private func pumpAppleVPAcousticPlayback(_ pcm: Data, generation: UInt64, runID: UUID) async {
            let startsBefore = speechAudioOutputHostSnapshot.playbackStartedCount
            do {
                var offset = 0
                var sequence: UInt64 = 1
                while offset < pcm.count {
                    try checkAppleVPAcousticRun(runID)
                    let end = min(offset + 4800, pcm.count)
                    let output = await speechAudioOutputHost.enqueue(
                        pcm16Bytes: pcm.subdata(in: offset ..< end), sequence: sequence, generation: generation
                    )
                    try checkAppleVPAcousticRun(runID)
                    guard output.lastError == nil else { throw AppleVPAcousticTestError.playbackFailed }
                    speechAudioOutputHostSnapshot = output
                    if output.state == .prepared {
                        let started = await speechAudioOutputHost.start()
                        try checkAppleVPAcousticRun(runID)
                        speechAudioOutputHostSnapshot = started
                    }
                    offset = end
                    sequence += 1
                }
                let finished = await speechAudioOutputHost.finishProviderResponse(generation: generation)
                try checkAppleVPAcousticRun(runID)
                speechAudioOutputHostSnapshot = finished
                guard finished.playbackStartedCount == startsBefore + 1 else {
                    throw AppleVPAcousticTestError.playbackFailed
                }
            } catch {
                if (try? checkAppleVPAcousticRun(runID)) != nil {
                    appleVPAcousticRun.playbackFailure = "playback_failed"
                }
            }
        }

        private func collectAppleVPAcousticFrames(runID: UUID, playback: Data?) async throws {
            let started = appleVPAcousticRun.guideStartedAt ?? appleVPAcousticClock()
            let deadline = started + appleVPAcousticTestDurationNanoseconds
            while appleVPAcousticClock() < deadline {
                try checkAppleVPAcousticRun(runID)
                let capture = await speechAudioHost.currentSnapshot()
                try checkAppleVPAcousticRun(runID)
                let output = await speechAudioOutputHost.currentSnapshot()
                try checkAppleVPAcousticRun(runID)
                speechAudioHostSnapshot = capture
                speechAudioOutputHostSnapshot = output
                try validateAppleVPRuntimeDiagnostics(runID: runID)
                guard appleVPAcousticRun.playbackFailure == nil else { throw AppleVPAcousticTestError.playbackFailed }
                try validateAppleVPAcousticRoute()
                let now = appleVPAcousticClock()
                if let previous = appleVPAcousticRun.lastCollectionClock, now < previous {
                    throw AppleVPAcousticTestError.invalidPacket
                }
                appleVPAcousticRun.lastCollectionClock = now
                if now >= deadline {
                    break
                }
                try await advanceAppleVPAcousticPlaybackPlan(playback: playback, runID: runID)
                let frames = await speechAudioHost.drainFrames(maxCount: 25)
                try checkAppleVPAcousticRun(runID)
                for frame in frames {
                    try appendAppleVPAcousticFrame(frame)
                }
                appleVPAcousticRun.native = appleVPAcousticTestCapture?.nativeVoiceDebugSnapshot(runID: runID)
                guard appleVPAcousticRun.native?.sealReason == nil else { throw AppleVPAcousticTestError.routeChanged }
                if appleVPAcousticRun.warmupProfile != nil {
                    guard let voice = appleVPAcousticTestCapture?.voiceProcessingSnapshot(),
                          appleVPAcousticRun.processingProfile.accepts(voice),
                          appleVPAcousticRun.native?.profile == appleVPAcousticRun.processingProfile,
                          appleVPAcousticRun.native?.runID == runID,
                          appleVPAcousticRun.native?.captureGeneration == appleVPAcousticRun.generation,
                          voice.configurationID == appleVPAcousticRun.native?.configurationID,
                          appleVPAcousticRun.native?.issues.isEmpty == true
                    else {
                        throw AppleVPAcousticTestError.voiceProcessingUnavailable
                    }
                }
                publishAppleVPAcousticState()
                if appleVPAcousticRun.byteCount == appleVPAcousticTestByteLimit {
                    return
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        private func advanceAppleVPAcousticPlaybackPlan(playback: Data?, runID: UUID) async throws {
            if appleVPAcousticRun.adaptation != nil {
                try await advanceAppleVPAdaptation(playback: playback, runID: runID)
            } else {
                try advanceAppleVPAcousticCGuide(playback: playback, runID: runID)
            }
        }

        private func advanceAppleVPAdaptation(playback: Data?, runID: UUID) async throws {
            guard let experiment = appleVPAcousticRun.adaptation,
                  let start = appleVPAcousticRun.guideStartedAt, let playback else {
                throw AppleVPAcousticTestError.playbackFailed
            }
            let now = appleVPAcousticClock()
            if now < start {
                return
            }
            let count = appleVPAcousticRun.adaptationPlays.count
            if count > 0, appleVPAcousticRun.adaptationPlays[count - 1]["completed_ns"] == nil,
               speechAudioOutputHostSnapshot.state == .completed {
                appleVPAcousticRun.adaptationPlays[count - 1]["completed_ns"] = now
            }
            guard count < experiment.plays.count else { return }
            let play = experiment.plays[count]
            guard now >= start + play.offset else { return }
            guard now < start + play.offset + 250_000_000 else {
                throw AppleVPAcousticTestError.playbackFailed
            }
            if count > 0 {
                try await prepareSecondAdaptationPlayback(runID: runID)
            }
            let generation = speechAudioOutputHostSnapshot.generation
            if let engine = realtimeSpeechDiagnosticAudioEngine {
                guard engine.beginAdaptationPlayback(
                    runID: runID, generation: generation, index: count + 1, silent: play.silent
                ) else { throw AppleVPAcousticTestError.voiceProcessingUnavailable }
            }
            let bytes = play.silent ? Data(repeating: 0, count: playback.count) : playback
            appleVPAcousticRun.adaptationPlays.append([
                "index": count + 1, "silent": play.silent, "planned_ns": start + play.offset,
                "request_ns": appleVPAcousticClock(), "playback_generation": generation,
                "source_pcm_sha256": AppleVPAcousticWAV.digest(bytes), "source_pcm_bytes": bytes.count
            ])
            scheduleAppleVPAcousticPlayback(bytes, runID: runID)
        }

        private func prepareSecondAdaptationPlayback(runID: UUID) async throws {
            guard appleVPAcousticRun.adaptationPlays.last?["completed_ns"] != nil else {
                throw AppleVPAcousticTestError.playbackFailed
            }
            await appleVPAcousticPlaybackTask?.value
            let output = await speechAudioOutputHost.prepare()
            try checkAppleVPAcousticRun(runID)
            guard output.state == .prepared, output.generation > speechAudioOutputHostSnapshot.generation else {
                throw AppleVPAcousticTestError.playbackFailed
            }
            speechAudioOutputHostSnapshot = output
        }

        private func advanceAppleVPAcousticCGuide(playback: Data?, runID: UUID) throws {
            guard let started = appleVPAcousticRun.guideStartedAt else { return }
            let now = appleVPAcousticClock()
            guard now >= started else {
                if appleVPAcousticRun.warmupProfile == .four {
                    return
                }
                throw AppleVPAcousticTestError.invalidPacket
            }
            if appleVPAcousticRun.guideEvents["human_only"] == nil {
                appleVPAcousticRun.guideEvents["human_only"] = now
            }
            let elapsed = now - started
            appleVPAcousticRun.recordHumanSpeechCue(at: now, elapsed: elapsed)
            if elapsed >= 3_000_000_000, appleVPAcousticRun.guideEvents["double_talk"] == nil {
                guard elapsed < 4_000_000_000 else {
                    throw AppleVPAcousticTestError.playbackFailed
                }
                appleVPAcousticRun.guideEvents["double_talk"] = now
                try scheduleAppleVPScoringResident(playback, runID: runID)
            }
            if elapsed >= 9_000_000_000, appleVPAcousticRun.guideEvents["human_tail"] == nil {
                guard appleVPAcousticResidentComplete else {
                    throw AppleVPAcousticTestError.playbackFailed
                }
                appleVPAcousticRun.guideEvents["human_tail"] = now
            }
            if elapsed >= 11_000_000_000, appleVPAcousticRun.guideEvents["quiet"] == nil {
                guard elapsed < 14_000_000_000 else { throw AppleVPAcousticTestError.invalidPacket }
                appleVPAcousticRun.guideEvents["quiet"] = now
            }
        }

        private func scheduleAppleVPScoringResident(_ playback: Data?, runID: UUID) throws {
            if let playback {
                scheduleAppleVPAcousticPlayback(playback, runID: runID)
            } else if !appleVPAcousticRun.isAcousticBatch || appleVPAcousticRun.scenario != .humanOnly {
                throw AppleVPAcousticTestError.playbackFailed
            }
        }

        private func validateAppleVPAcousticCCompletion() throws {
            guard appleVPAcousticRun.comprehensiveC else { return }
            if let experiment = appleVPAcousticRun.adaptation {
                guard appleVPAcousticRun.adaptationPlays.count == experiment.plays.count,
                      let completed = appleVPAcousticRun.adaptationPlays.last?["completed_ns"] as? UInt64,
                      appleVPAcousticClock() >= completed + 500_000_000,
                      speechAudioOutputHostSnapshot.playbackStartedCount == experiment.plays.count,
                      appleVPAcousticResidentComplete else { throw AppleVPAcousticTestError.playbackFailed }
                return
            }
            guard appleVPAcousticRun.guideEvents.count == 4,
                  let quiet = appleVPAcousticRun.guideEvents["quiet"],
                  appleVPAcousticClock() >= quiet + 1_000_000_000,
                  appleVPAcousticResidentComplete
            else {
                throw AppleVPAcousticTestError.invalidPacket
            }
        }

        private var appleVPAcousticResidentComplete: Bool {
            if appleVPAcousticRun.isAcousticBatch, appleVPAcousticRun.scenario == .humanOnly {
                return speechAudioOutputHostSnapshot.state == .prepared
                    && speechAudioOutputHostSnapshot.playbackStartedCount == 0
            }
            return speechAudioOutputHostSnapshot.state == .completed
        }

        private func validateAppleVPRuntimeDiagnostics(runID: UUID) throws {
            guard realtimeSpeechDiagnosticAudioEngine != nil || appleVPAcousticRuntimeTiming != nil else { return }
            let timing = if let read = appleVPAcousticRuntimeTiming {
                read(runID)
            } else {
                realtimeSpeechDiagnosticAudioEngine?.nativeVoiceTimingSnapshot(runID: runID)
            }
            try AppleVPRuntimeSafetyError.validate(
                timing, identity: .init(
                    runID: runID, generation: appleVPAcousticRun.generation ?? 0,
                    configurationID: appleVPAcousticRun.native?.configurationID ?? 0
                ),
                pid: getpid(), agcEnabled: appleVPAcousticRun.processingProfile.automaticGainControlEnabled,
                residentStarted: [.playing, .draining, .completed].contains(speechAudioOutputHostSnapshot.state)
            )
            if appleVPAcousticRun.adaptation != nil || appleVPAcousticRun.allocation != nil {
                let modes = timing?.runtimeReadbacks.map { $0.payload.microphoneModes } ?? []
                guard AppleVPAdaptationRun.acceptsMicrophoneModes(modes) else {
                    throw AppleVPAcousticTestError.voiceProcessingUnavailable
                }
            }
        }

        private func validateAppleVPAcousticRoute() throws {
            let previous = appleVPAcousticRun.route
            guard speechAudioHostSnapshot.isCapturing, speechAudioHostSnapshot.lastError == nil,
                  speechAudioHostSnapshot.inputDevice == previous.inputDevice,
                  speechAudioHostSnapshot.outputDevice == previous.outputDevice
            else {
                throw AppleVPAcousticTestError.routeChanged
            }
            guard speechAudioHostSnapshot.droppedFrameCount == previous.droppedFrameCount else {
                throw AppleVPAcousticTestError.captureDropped
            }
            if let generation = appleVPAcousticRun.playbackGeneration {
                guard speechAudioOutputHostSnapshot.generation == generation,
                      speechAudioOutputHostSnapshot.lastError == nil
                else {
                    throw AppleVPAcousticTestError.playbackFailed
                }
            }
        }

        private func appendAppleVPAcousticFrame(_ frame: MacSpeechAudioFrame) throws {
            if appleVPAcousticRun.warmupDrain != nil {
                guard frame.captureGeneration == appleVPAcousticRun.generation else {
                    throw AppleVPAcousticTestError.invalidPacket
                }
                guard try appleVPAcousticRun.warmupDrain?.retain(frame) == true else { return }
                try retainAppleVPAcousticFrame(frame)
                return
            }
            guard frame.captureGeneration == appleVPAcousticRun.generation,
                  frame.pcm16Bytes.count == 960, frame.monotonicTimestampNanoseconds > 0,
                  frame.sequenceNumber == UInt64(appleVPAcousticRun.packetCount + 1)
            else {
                throw AppleVPAcousticTestError.invalidPacket
            }
            if let previous = appleVPAcousticRun.packets.last {
                let expected = previous[1].addingReportingOverflow(20_000_000)
                guard !expected.overflow, frame.monotonicTimestampNanoseconds == expected.partialValue else {
                    throw AppleVPAcousticTestError.invalidPacket
                }
            }
            try retainAppleVPAcousticFrame(frame)
        }

        private func retainAppleVPAcousticFrame(_ frame: MacSpeechAudioFrame) throws {
            guard appleVPAcousticRun.byteCount + frame.pcm16Bytes.count <= appleVPAcousticTestByteLimit else {
                throw AppleVPAcousticTestError.capacityExceeded
            }
            if appleVPAcousticRun.dataMode == .recording {
                appleVPAcousticRun.pcm.append(frame.pcm16Bytes)
            }
            appleVPAcousticRun.pcmShortWindows?.recordPCM(
                frame.pcm16Bytes, start: frame.monotonicTimestampNanoseconds
            )
            appleVPAcousticRun.packets.append([frame.sequenceNumber, frame.monotonicTimestampNanoseconds, 960])
        }

        private func checkAppleVPAcousticRun(_ runID: UUID) throws {
            guard !Task.isCancelled, appleVPAcousticRun.runID == runID,
                  appleVPAcousticRun.stopGeneration == speechHostStopGeneration,
                  appleVPAcousticRun.phase == .starting || appleVPAcousticRun.phase == .running
            else {
                throw CancellationError()
            }
        }

        private func finishAppleVPAcousticTest(runID: UUID, failure: String?) async {
            guard appleVPAcousticRun.runID == runID,
                  appleVPAcousticRun.phase == .starting || appleVPAcousticRun.phase == .running else { return }
            appleVPAcousticRun.errorCode = failure
            appleVPAcousticRun.phase = .stopping
            await shutdownSpeechAudioHost()
        }

        private func closeAppleVPAcousticRunForShutdown() async {
            if appleVPAcousticRun.phase == .starting || appleVPAcousticRun.phase == .running {
                appleVPAcousticRun.errorCode = "cancelled"
                appleVPAcousticRun.phase = .stopping
            }
            appleVPAcousticTestTask?.cancel()
            let playbackTask = appleVPAcousticPlaybackTask
            playbackTask?.cancel()
            if appleVPAcousticRun.phase == .stopping {
                if let runID = appleVPAcousticRun.runID {
                    do {
                        try appleVPScoreControl?.send(
                            "stop", runID: runID,
                            scoreStart: appleVPAcousticRun.humanAcousticBatch || appleVPAcousticRun.macAECBatch != nil
                                || appleVPAcousticRun.adaptation != nil || appleVPAcousticRun.allocation != nil
                                ? appleVPAcousticRun.guideStartedAt ?? 0 : 0,
                            batchScenario: appleVPAcousticRun.isAcousticBatch ? appleVPAcousticRun.scenario : nil,
                            humanBatch: appleVPAcousticRun.humanAcousticBatch,
                            onsetProfile: appleVPAcousticRun.humanOnsetProfile,
                            macAECBatch: appleVPAcousticRun.macAECBatch, adaptation: appleVPAcousticRun.adaptation,
                            allocation: appleVPAcousticRun.allocation,
                        )
                    } catch {
                        appleVPAcousticRun.errorCode = appleVPAcousticRun.errorCode
                            ?? AppleVPAcousticTestError.externalPlaybackControl.rawValue
                    }
                }
                await finishMacAECBatchCapture()
                appleVPAcousticRun.captureFinal = await speechAudioHost.currentSnapshot()
                appleVPAcousticRun.playbackFinal = await speechAudioOutputHost.currentSnapshot()
                if let runID = appleVPAcousticRun.runID {
                    appleVPAcousticRun.native = appleVPAcousticTestCapture?.sealNativeVoiceDebug(runID: runID)
                }
                if appleVPAcousticRun.errorCode == nil, appleVPAcousticRun.native?.coverageValid != true {
                    appleVPAcousticRun.errorCode = "native_coverage_unverified"
                }
                if appleVPAcousticRun.errorCode == nil, appleVPAcousticRun.packetCount == 0 {
                    appleVPAcousticRun.errorCode = "no_processed_pcm"
                }
            }
            speechAudioOutputHostSnapshot = await speechAudioOutputHost.close()
            await speechAudioHost.shutdown()
            speechAudioHostSnapshot = await speechAudioHost.currentSnapshot()
            await playbackTask?.value
            if appleVPAcousticRun.phase == .stopping {
                appleVPAcousticRun.phase = .sealed
            }
            appleVPAcousticTestTask = nil
            appleVPAcousticPlaybackTask = nil
            publishAppleVPAcousticState(force: true)
        }

        private func finishMacAECBatchCapture() async {
            guard appleVPAcousticRun.macAECBatch != nil || appleVPAcousticRun.adaptation != nil
                || appleVPAcousticRun.allocation != nil,
                appleVPAcousticRun.errorCode == nil else { return }
            guard let runID = appleVPAcousticRun.runID, let generation = appleVPAcousticRun.generation,
                  let drained = await speechAudioHost.finishDebugCapture(runID: runID, generation: generation) else {
                appleVPAcousticRun.errorCode = "debug_final_drain_unverified"
                return
            }
            do {
                for frame in drained.frames {
                    try appendAppleVPAcousticFrame(frame)
                }
                appleVPAcousticRun.macAECFinalDrain = [
                    "generation": generation,
                    "pending_before": UInt64(drained.pending), "drained": UInt64(drained.frames.count)
                ]
            } catch {
                appleVPAcousticRun.errorCode = AppleVPAcousticTestError.invalidPacket.rawValue
            }
        }

        private func publishAppleVPAcousticState(force: Bool = false) {
            let now = DispatchTime.now().uptimeNanoseconds
            guard force || now - appleVPAcousticRun.lastRefresh >= 200_000_000 else { return }
            appleVPAcousticRun.lastRefresh = now
            objectWillChange.send()
        }
    }
#endif

#if DEBUG
    private enum AppleVPAcousticWAV {
        static func read(url: URL) throws -> (pcm: Data, sha256: String) {
            guard url.isFileURL else { throw AppleVPAcousticTestError.invalidFile }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let bytes = try file.read(upToCount: 724_097) ?? Data()
            guard bytes.count <= 724_096 else { throw AppleVPAcousticTestError.invalidFile }
            return try (pcm(from: bytes), digest(bytes))
        }

        static func pcm(from bytes: Data) throws -> Data {
            guard bytes.count >= 44, bytes.prefix(4) == Data("RIFF".utf8),
                  bytes[8 ..< 12] == Data("WAVE".utf8), integer(bytes, 4, 4) + 8 == bytes.count
            else {
                throw AppleVPAcousticTestError.invalidFile
            }
            var offset = 12
            var validFormat = false
            var result: Data?
            while offset + 8 <= bytes.count {
                let size = integer(bytes, offset + 4, 4)
                let content = offset + 8
                guard size <= bytes.count - content else { throw AppleVPAcousticTestError.invalidFile }
                let tag = bytes[offset ..< content - 4]
                if tag == Data("fmt ".utf8) {
                    guard !validFormat, size >= 16 else { throw AppleVPAcousticTestError.invalidFile }
                    guard validPCMFormat(bytes, offset: content) else { throw AppleVPAcousticTestError.invalidFile }
                    validFormat = true
                } else if tag == Data("data".utf8) {
                    guard result == nil, size > 0, size <= 720_000, size.isMultiple(of: 2) else {
                        throw AppleVPAcousticTestError.invalidFile
                    }
                    result = bytes.subdata(in: content ..< content + size)
                }
                offset = content + size + size % 2
            }
            guard validFormat, offset == bytes.count, let result,
                  bytes.count - result.count <= 4096 else { throw AppleVPAcousticTestError.invalidFile }
            return result
        }

        static func digest(_ bytes: Data) -> String {
            SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }

        private static func integer(_ bytes: Data, _ offset: Int, _ count: Int) -> Int {
            (0 ..< count).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }

        private static func validPCMFormat(_ bytes: Data, offset: Int) -> Bool {
            integer(bytes, offset, 2) == 1 && integer(bytes, offset + 2, 2) == 1
                && integer(bytes, offset + 4, 4) == 24000 && integer(bytes, offset + 8, 4) == 48000
                && integer(bytes, offset + 12, 2) == 2 && integer(bytes, offset + 14, 2) == 16
        }

        static func encoded(pcm: Data) -> Data {
            var output = Data("RIFF".utf8)
            append(UInt32(pcm.count + 36), to: &output)
            output.append(Data("WAVEfmt ".utf8))
            append(16, to: &output)
            output.append(contentsOf: [1, 0, 1, 0])
            append(24000, to: &output)
            append(48000, to: &output)
            output.append(contentsOf: [2, 0, 16, 0])
            output.append(Data("data".utf8))
            append(UInt32(pcm.count), to: &output)
            output.append(pcm)
            return output
        }

        private static func append(_ value: UInt32, to bytes: inout Data) {
            bytes.append(contentsOf: (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
    }
#endif

#if DEBUG
    extension AppController {
        var appleVPAcousticStatusLines: [String] {
            let native = appleVPAcousticRun.native
            let voice = native?.voiceProcessing
            let unknown = "UNKNOWN"
            let fact: (Bool?) -> String = { $0.map(String.init) ?? unknown }
            let generation = appleVPAcousticRun.generation.map(String.init) ?? unknown
            let configuration = native?.configurationID.map(String.init) ?? unknown
            let nativeFormat = native?.nativeFormat.map {
                "\($0.sampleRate) Hz / \($0.channelCount) ch / \($0.sampleFormat) / interleaved=\($0.isInterleaved)"
            } ?? unknown
            let channels = native.map { String(describing: $0.channels) } ?? unknown
            let dropped = speechAudioHostSnapshot.droppedFrameCount
            let stale = speechAudioHostSnapshot.rejectedStaleFrameCount
            let coverage = native.map { String($0.coverageValid) } ?? unknown
            var lines = [String]()
            lines.append("phase=\(appleVPAcousticRun.phase.rawValue) scenario=\(appleVPAcousticRun.scenario.rawValue)")
            lines.append("run=\(appleVPAcousticRun.runID?.uuidString ?? unknown)")
            lines.append("file=\(appleVPAcousticRun.selectedPlaybackFileName)")
            lines.append("error=\(appleVPAcousticRun.errorCode ?? unknown)")
            lines.append("authorization_pending=\(appleVPAcousticTestState.authorizationPending); result=UNKNOWN")
            lines.append("generation=\(generation) configuration=\(configuration)")
            lines.append("VP input=\(fact(voice?.inputEnabled)) output=\(fact(voice?.outputEnabled))")
            lines.append("AGC=\(fact(voice?.automaticGainControlEnabled))")
            lines.append("bypass=\(fact(voice?.bypassed)) muted=\(fact(voice?.inputMuted))")
            lines.append("readback_ns=\(voice.map { String($0.validatedAtNanoseconds) } ?? unknown)")
            lines.append("VP input=\(voice.map { appleVPAcousticFormatDescription($0.inputFormat) } ?? unknown)")
            lines.append("VP output=\(voice.map { appleVPAcousticFormatDescription($0.outputFormat) } ?? unknown)")
            lines.append("native=\(nativeFormat); processed=24000 Hz / mono / PCM16 LE / channel[0]")
            lines.append("packets=\(appleVPAcousticRun.packetCount) bytes=\(appleVPAcousticRun.byteCount)")
            lines.append("drop=\(dropped) stale=\(stale) coverage=\(coverage)")
            lines.append("native channels peak/fullScale/overScale/nonFinite=\(channels)")
            lines.append("Physical acceptance=UNVERIFIED; Source=OPEN; Runtime interruption=DISABLED")
            return lines
        }

        func appleVPAcousticTestManifestData() throws -> Data {
            guard isAppleVPAcousticTestMode, appleVPAcousticRun.canExport else { throw CocoaError(.featureUnsupported) }
            let state = appleVPAcousticRun
            var manifest = [String: Any]()
            manifest["schema_version"] = 1
            manifest["run_id"] = state.runID?.uuidString ?? "UNKNOWN"
            manifest["scenario"] = state.scenario.rawValue
            manifest["source_commit"] = NSNull()
            manifest["build_identity"] = NSNull()
            manifest["physical_acceptance"] = "UNVERIFIED"
            manifest["runtime_interruption"] = "DISABLED"
            manifest["source_qualification"] = "OPEN"
            manifest["error"] = state.errorCode ?? NSNull() as Any
            manifest["playback_file_name"] = state.selectedPlaybackFileName
            manifest["playback_sha256"] = state.playbackSHA256 ?? NSNull() as Any
            manifest["capture_generation"] = state.generation ?? NSNull() as Any
            manifest["input_device"] = state.dataMode == .recording
                ? state.route.inputDevice.identifier : "default_input"
            manifest["output_device"] = state.dataMode == .recording
                ? state.route.outputDevice.identifier : "default_output"
            manifest["processed_sample_rate"] = 24000
            manifest["processed_channels"] = 1
            manifest["processed_encoding"] = "PCM16_LE"
            manifest["processed_channel_map"] = [0]
            manifest["short_window_diagnostics"] = appleVPAcousticShortWindowManifest(state)
            manifest["duration_limit_ns"] = appleVPAcousticTestDurationNanoseconds
            manifest["byte_limit"] = appleVPAcousticTestByteLimit
            manifest["packet_count"] = state.packetCount
            manifest["byte_count"] = state.byteCount
            manifest["silent_smoke"] = appleVPSilentSmokeScenario != nil
            manifest["retained_pcm_bytes"] = state.retainedPCMByteCount
            manifest["processed_sha256"] = state.dataMode == .recording
                ? AppleVPAcousticWAV.digest(state.pcm) as Any : NSNull()
            manifest["configuration_debug"] = realtimeSpeechDiagnosticAudioEngine?.voiceProcessingConfigurationDebug()
                ?? [:]
            manifest["packets_sequence_host_time_ns_bytes"] = state.packets
            manifest["capture_drop_count"] = state.captureFinal.droppedFrameCount
            manifest["capture_stale_count"] = state.captureFinal.rejectedStaleFrameCount
            manifest["capture_state"] = state.captureFinal.state.rawValue
            manifest["capture_queued_at_seal"] = state.captureFinal.queuedFrameCount
            manifest["capture_generated_at_seal"] = state.captureFinal.generatedFrameCount
            manifest["partial_converter_tail_samples"] = NSNull()
            manifest["capture_error"] = state.captureFinal.lastError ?? NSNull() as Any
            manifest["playback_state"] = state.playbackFinal.state.rawValue
            manifest["playback_generation"] = state.playbackFinal.generation
            manifest["playback_started_count"] = state.playbackFinal.playbackStartedCount
            manifest["playback_underrun_count"] = state.playbackFinal.underrunCount
            manifest["playback_rejected_callback_count"] = state.playbackFinal.rejectedCallbackCount
            manifest["playback_error"] = state.playbackFinal.lastError ?? NSNull() as Any
            manifest["native"] = appleVPAcousticNativeManifest(state.native)
            return try encodeAppleVPAcousticManifest(manifest, runID: state.runID)
        }

        private func encodeAppleVPAcousticManifest(_ manifest: [String: Any], runID: UUID?) throws -> Data {
            var result = manifest
            let mode = appleVPAcousticRun.dataMode
            result["data_mode"] = mode.rawValue
            result["processing_profile"] = appleVPAcousticRun.processingProfile.rawValue
            result["requested_agc_enabled"] = appleVPAcousticRun.processingProfile.automaticGainControlEnabled
            result["external_playback_control"] = appleVPScoreControl == nil ? "DISABLED" : "DEBUG_PIPE_BOUND"
            if let batch = appleVPAcousticRun.macAECBatch {
                result["mac_aec_batch"] = batch.manifest
                result["mac_aec_final_drain"] = appleVPAcousticRun.macAECFinalDrain ?? NSNull() as Any
            }
            appendAdaptationManifest(to: &result)
            appendChannelAllocationManifest(to: &result)
            if appleVPAcousticRun.btAcousticBatch {
                var batch: [String: Any] = ["batch": "R5_M03", "scenario": appleVPAcousticRun.scenario.rawValue]
                batch["resident_enabled"] = appleVPAcousticRun.scenario != .humanOnly
                batch["proxy_requested"] = appleVPAcousticRun.scenario != .residentOnly
                result["bt_acoustic_batch"] = batch
            }
            if appleVPAcousticRun.humanAcousticBatch {
                result["human_acoustic_batch"] = [
                    "batch": appleVPAcousticRun.humanOnsetProfile == nil ? "R5_M07" : "R5_M07_F1",
                    "scenario": appleVPAcousticRun.scenario.rawValue,
                    "source": "human", "proxy_requested": false,
                    "resident_enabled": appleVPAcousticRun.scenario != .humanOnly,
                    "human_requested": appleVPAcousticRun.scenario != .residentOnly
                ] as [String: Any]
            }
            if let profile = appleVPAcousticRun.humanOnsetProfile {
                result["human_onset_comparison"] = [
                    "group": profile.rawValue, "planned_cue_offset_ns": profile.cueDelayNanoseconds,
                    "control_cue_ns": appleVPAcousticRun.humanSpeechCueAtNanoseconds ?? NSNull() as Any,
                    "cue_semantics": "software_hint_only; A waits for 1–2 seconds of audible resident speech",
                    "physical_human_onset_ns": NSNull(), "physical_overlap_seconds": NSNull()
                ] as [String: Any]
            }
            if let warmup = appleVPAcousticRun.warmupProfile {
                result["warmup_profile"] = warmup.rawValue
                result["total_collection_limit_ns"] = 15_000_000_000 + warmup.nanoseconds
                result["warmup"] = appleVPAcousticWarmupManifest()
            }
            result["export_scope"] = mode == .statsOnly
                ? "statistics only; PCM not retained; queued/partial converter tail not padded"
                : "drained full20ms packets; queued/partial converter tail not padded"
            result["host_timing"] = try appleVPAcousticTimingManifest(runID)
            if appleVPAcousticRun.comprehensiveC, appleVPAcousticRun.adaptation == nil {
                result["comprehensive_c"] = appleVPAcousticCManifest()
            }
            return try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        }

        private func appendChannelAllocationManifest(to result: inout [String: Any]) {
            if let allocation = appleVPAcousticRun.allocation {
                result["channel_allocation_experiment"] = allocation.manifest
                result["channel_allocation_witness"] = appleVPAcousticRun.runID.flatMap {
                    realtimeSpeechDiagnosticAudioEngine?.channelAllocationSnapshot(runID: $0)
                } ?? NSNull() as Any
                result["channel_allocation_final_drain"] = appleVPAcousticRun.macAECFinalDrain ?? NSNull() as Any
            }
        }

        private func appendAdaptationManifest(to result: inout [String: Any]) {
            guard let adaptation = appleVPAcousticRun.adaptation else { return }
            result["adaptation_experiment"] = adaptation.manifest
            result["adaptation_plays"] = appleVPAcousticRun.adaptationPlays
            result["adaptation_final_drain"] = appleVPAcousticRun.macAECFinalDrain ?? NSNull() as Any
        }

        private func appleVPAcousticShortWindowManifest(_ state: AppleVPAcousticTestState) -> [String: Any] {
            guard let run = state.runID, let generation = state.generation,
                  let configuration = state.native?.configurationID
            else {
                return ["version": 1, "status": "UNKNOWN_MISSING_IDENTITY"]
            }
            let identity = MacSpeechRuntimeReadback.Identity(
                runID: run, generation: generation, configurationID: configuration
            )
            return MacSpeechShortWindowSnapshot.pairedManifest(
                native: state.native?.shortWindows, pcm: state.pcmShortWindows?.snapshot(identity: identity),
                identity: identity, clockTrusted: state.native?.coverageValid == true,
                savedPCM: state.dataMode == .recording
            )
        }

        private func appleVPAcousticWarmupManifest() -> [String: Any] {
            guard let drain = appleVPAcousticRun.warmupDrain else { return [:] }
            var result = drain.manifest()
            let packets = appleVPAcousticRun.packets
            let first = packets.first?[1]
            let lastEnd = packets.last.map { $0[1] + 20_000_000 }
            let quietStart = max(drain.plan.scoreStartedAt + 11_000_000_000,
                                 appleVPAcousticRun.guideEvents["quiet"] ?? drain.plan.scoreEndedAt)
            let quiet = packets.reduce(UInt64(0)) { total, packet in
                let start = max(packet[1], quietStart)
                let end = min(packet[1] + 20_000_000, drain.plan.scoreEndedAt)
                return total + (end > start ? end - start : 0)
            }
            let complete = first == drain.plan.scoreStartedAt && lastEnd == drain.plan.scoreEndedAt
                && packets.count == 750
            result["scoring_packet_coverage"] = complete ? "COMPLETE_FULL_PACKETS" : "PARTIAL"
            result["scoring_drained_ns"] = UInt64(packets.count) * 20_000_000
            result["quiet_drained_ns"] = quiet
            result["first_scoring_content_ns"] = first ?? NSNull() as Any
            result["last_scoring_content_end_ns"] = lastEnd ?? NSNull() as Any
            result["queued_at_seal"] = appleVPAcousticRun.captureFinal.queuedFrameCount
            result["tail_coverage"] = complete ? "CONVERTER_PARTIAL_TAIL_UNKNOWN" : "PARTIAL"
            return result
        }

        private func appleVPAcousticCManifest() -> [String: Any] {
            var result: [String: Any] = ["version": 1]
            result["clock"] = "monotonic_software_guidance_not_physical_audio"
            result["events_ns"] = appleVPAcousticRun.guideEvents
            result["human_speech_windows"] = NSNull()
            result["physical_overlap_seconds"] = NSNull()
            result["post_roll_coverage"] = "REVIEW_REQUIRED"
            result["planned_seconds"] = ["human_only": 0, "schedule_playback": 3, "human_tail": 9, "quiet": 11]
            return result
        }

        private func appleVPAcousticTimingManifest(_ runID: UUID?) throws -> [String: Any] {
            guard let runID,
                  let timing = realtimeSpeechDiagnosticAudioEngine?.nativeVoiceTimingSnapshot(runID: runID)
            else {
                return ["status": "UNKNOWN"]
            }
            let data = try JSONEncoder().encode(timing)
            guard var result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.coderInvalidValue)
            }
            result["status"] = timing.skippedUpdates == 0 ? "OBSERVED_PARTIAL_METADATA" : "UNKNOWN_OBSERVATION_LOSS"
            if timing.input.callbacks == 0 {
                result["status"] = "UNKNOWN_NO_INPUT_CALLBACKS"
            }
            result["render_generation_source"] = "run/capture binding and tap configuration; "
                + "no callback playback-generation field"
            return result
        }

        func appleVPAcousticTestProcessedWAVData() throws -> Data {
            guard isAppleVPAcousticTestMode, appleVPAcousticRun.canExportWAV
            else { throw CocoaError(.featureUnsupported) }
            return AppleVPAcousticWAV.encoded(pcm: appleVPAcousticRun.pcm)
        }

        func writeAppleVPAcousticTestJSON(to url: URL, localExportConsent: Bool) throws {
            guard localExportConsent else { throw CocoaError(.featureUnsupported) }
            try AppleVPAcousticEvidenceExport.write(
                appleVPAcousticTestManifestData(), to: url,
                expected: appleVPAcousticTestExportURL(asWAV: false)
            )
        }

        func writeAppleVPAcousticTestWAV(to url: URL, localExportConsent: Bool) throws {
            guard localExportConsent else { throw CocoaError(.featureUnsupported) }
            try AppleVPAcousticEvidenceExport.write(
                appleVPAcousticTestProcessedWAVData(), to: url,
                expected: appleVPAcousticTestExportURL(asWAV: true)
            )
        }

        func appleVPAcousticTestExportURL(asWAV: Bool) throws -> URL {
            guard isAppleVPAcousticTestMode, appleVPAcousticRun.canExport,
                  !asWAV || appleVPAcousticRun.dataMode == .recording,
                  let runID = appleVPAcousticRun.runID else { throw CocoaError(.featureUnsupported) }
            return try AppleVPAcousticEvidenceExport.destination(runID: runID, asWAV: asWAV)
        }

        private func appleVPAcousticNativeManifest(_ native: MacSpeechNativeVoiceDebugSnapshot?) -> [String: Any] {
            guard let native else { return ["status": "UNKNOWN"] }
            var result = [String: Any]()
            result["run_id"] = native.runID.uuidString
            result["generation"] = native.captureGeneration
            result["configuration_id"] = native.configurationID ?? NSNull() as Any
            result["sealed"] = native.isSealed
            result["seal_reason"] = native.sealReason ?? NSNull() as Any
            result["coverage_valid"] = native.coverageValid
            result["issues"] = native.issues
            result["rejections"] = native.rejections
            result["native_buffers"] = native.nativeBufferCount
            result["native_frames"] = native.nativeFrameCount
            result["packet_count"] = native.packetCount
            result["packet_bytes"] = native.packetByteCount
            result["first_native_host_time"] = native.firstNativeHostTime ?? NSNull() as Any
            result["last_native_host_time"] = native.lastNativeHostTime ?? NSNull() as Any
            result["first_native_sample_time"] = native.firstNativeSampleTime ?? NSNull() as Any
            result["last_native_sample_time"] = native.lastNativeSampleTime ?? NSNull() as Any
            result["first_packet_time_ns"] = native.firstPacketTime ?? NSNull() as Any
            result["last_packet_time_ns"] = native.lastPacketTime ?? NSNull() as Any
            let format = native.nativeFormat.map(appleVPAcousticNativeFormatManifest)
            let voice = native.voiceProcessing.map(appleVPAcousticVoiceManifest)
            result["native_format"] = format ?? ["status": "UNKNOWN"]
            result["channels"] = native.channels.map(appleVPAcousticChannelManifest)
            result["acoustic_windows"] = native.acousticWindows?.manifest() ?? NSNull() as Any
            result["raw_timestamp_diagnostic"] = native.rawTimestampDiagnostic?.manifest(
                runID: native.runID, generation: native.captureGeneration,
                configurationID: native.configurationID, sealed: native.isSealed
            ) ?? NSNull() as Any
            result["voice_processing"] = voice ?? ["status": "UNKNOWN"]
            return result
        }

        private func appleVPAcousticVoiceManifest(_ voice: MacSpeechVoiceProcessingSnapshot) -> [String: Any] {
            var result = [String: Any]()
            result["mode"] = voice.mode.rawValue
            result["configuration_id"] = voice.configurationID
            result["input_enabled"] = voice.inputEnabled
            result["output_enabled"] = voice.outputEnabled
            result["bypassed"] = voice.bypassed
            result["input_muted"] = voice.inputMuted
            result["agc_enabled"] = voice.automaticGainControlEnabled
            result["validated_at_ns"] = voice.validatedAtNanoseconds
            result["input_format"] = appleVPAcousticFormatDescription(voice.inputFormat)
            result["output_format"] = appleVPAcousticFormatDescription(voice.outputFormat)
            result["noise_suppression"] = "Apple native; no independent public readback"
            return result
        }

        private func appleVPAcousticNativeFormatManifest(_ format: MacSpeechNativeVoiceDebugFormat) -> [String: Any] {
            var result = [String: Any]()
            result["rate"] = format.sampleRate
            result["channels"] = format.channelCount
            result["sample_format"] = format.sampleFormat
            result["interleaved"] = format.isInterleaved
            return result
        }

        private func appleVPAcousticChannelManifest(_ channel: MacSpeechNativeVoiceDebugChannel) -> [String: Any] {
            var result = [String: Any]()
            result["samples"] = channel.sampleCount
            result["peak"] = channel.peakMagnitude ?? NSNull() as Any
            result["full_scale"] = channel.fullScaleCount
            result["over_scale"] = channel.overScaleCount
            result["non_finite"] = channel.nonFiniteCount
            return result
        }

        private func appleVPAcousticFormatDescription(_ format: MacSpeechNativeInputFormat) -> String {
            "\(format.sampleRate) Hz / \(format.channelCount) ch"
        }
    }

    private enum AppleVPAcousticEvidenceExport {
        static func destination(runID: UUID, asWAV: Bool) throws -> URL {
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
            let expectedCache = home.appendingPathComponent("Library/Caches", isDirectory: true)
            guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                  cache.path == expectedCache.path
            else {
                throw CocoaError(.fileWriteNoPermission)
            }
            return cache.appendingPathComponent("com.eterna.aftelle.debug-apple-vp-evidence", isDirectory: true)
                .appendingPathComponent("run-\(runID.uuidString).\(asWAV ? "wav" : "json")")
        }

        static func write(_ bytes: Data, to url: URL, expected: URL) throws {
            guard url.isFileURL, url.host?.isEmpty != false, url.query == nil, url.fragment == nil,
                  url.path == url.standardizedFileURL.path, url.path == expected.path
            else {
                throw CocoaError(.fileWriteNoPermission)
            }
            let directory = try openDirectory(expected.deletingLastPathComponent())
            defer { Darwin.close(directory) }
            let flags = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
            let descriptor = openat(directory, expected.lastPathComponent, flags, 0o600)
            guard descriptor >= 0 else { throw currentError() }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                try validateFile(descriptor)
                try file.write(contentsOf: bytes)
                try file.synchronize()
                try file.close()
            } catch {
                try? file.close()
                unlinkat(directory, expected.lastPathComponent, 0)
                throw error
            }
        }

        private static func openDirectory(_ url: URL) throws -> Int32 {
            var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw currentError() }
            let homeDepth = FileManager.default.homeDirectoryForCurrentUser.pathComponents.count - 1
            do {
                for (index, component) in url.pathComponents.dropFirst().enumerated() {
                    try rejectUnsafeLocation(component: component, directory: descriptor)
                    let child = try openChild(component, directory: descriptor, canCreate: index >= homeDepth)
                    Darwin.close(descriptor)
                    descriptor = child
                }
                try rejectUnsafeLocation(component: "", directory: descriptor)
                var status = stat()
                guard fstat(descriptor, &status) == 0,
                      status.st_uid == getuid(), status.st_mode & 0o7777 == 0o700
                else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                return descriptor
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }

        private static func openChild(_ name: String, directory: Int32, canCreate: Bool) throws -> Int32 {
            let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            var child = openat(directory, name, flags)
            if child < 0, errno == ENOENT, canCreate {
                guard mkdirat(directory, name, 0o700) == 0 else { throw currentError() }
                child = openat(directory, name, flags)
            }
            guard child >= 0 else { throw currentError() }
            return child
        }

        private static func rejectUnsafeLocation(component: String, directory: Int32) throws {
            let forbidden = [".git", "mobile documents", "cloudstorage", "dropbox", "onedrive", "google drive",
                             "googledrive", "icloud drive", "session", "sessions", "memory"]
            guard !forbidden.contains(component.lowercased()), !component.hasSuffix(".digital_resident") else {
                throw CocoaError(.fileWriteNoPermission)
            }
            var marker = stat()
            let result = fstatat(directory, ".git", &marker, AT_SYMLINK_NOFOLLOW)
            guard result < 0, errno == ENOENT else { throw CocoaError(.fileWriteNoPermission) }
        }

        private static func validateFile(_ descriptor: Int32) throws {
            var status = stat()
            guard fchmod(descriptor, 0o600) == 0, fstat(descriptor, &status) == 0,
                  status.st_uid == getuid(), status.st_nlink == 1,
                  status.st_mode & S_IFMT == S_IFREG, status.st_mode & 0o7777 == 0o600
            else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }

        private static func currentError() -> NSError {
            NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
#endif
