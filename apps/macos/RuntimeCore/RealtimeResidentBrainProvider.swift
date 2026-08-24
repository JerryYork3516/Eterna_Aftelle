import Foundation

nonisolated enum RealtimeResidentBrainError: Error, Sendable, Equatable {
    case unavailable
    case voiceBindingUnavailable
    case invalidIdentity
    case invalidContextRevision
    case invalidAudioFrame
    case operationInFlight
    case invalidEvent
    case timedOut
    case cancelled
    case transportFailure
    case providerFailure
}

nonisolated struct RealtimeBrainSessionIdentity: Hashable, Sendable {
    let residentID: String
    let runtimeSessionID: String
    let brainLeaseID: UUID
    let routeEpoch: UInt64
    let generation: UInt64
}

nonisolated struct RealtimeBrainTurnID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct RealtimeBrainResponseID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct RealtimeBrainToolCallID: Hashable, Sendable {
    let rawValue: String
}

nonisolated struct RealtimeBrainToolAdvertisement: Sendable, Equatable {
    let name: String
    let description: String
    let parametersJSON: Data
}

nonisolated struct RuntimeVoiceProviderIdentity:
    RawRepresentable,
    Hashable,
    Sendable {
    static let activeRealtimeProvider = Self(
        rawValue: "active-realtime-provider"
    )

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated enum RuntimeVoiceBindingMode: String, Sendable, Equatable {
    case providerDefault
    case providerBuiltIn
    case providerCustom
    case providerCloned
}

nonisolated enum RuntimeVoiceBindingFallback: String, Sendable, Equatable {
    case providerDefault
    case failClosed
}

nonisolated struct RuntimeVoiceBinding: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
    let providerIdentity: RuntimeVoiceProviderIdentity
    let mode: RuntimeVoiceBindingMode
    let voiceProfileID: String?
    let providerPrivateVoiceReference: String?
    let fallback: RuntimeVoiceBindingFallback

    static func providerDefault(
        identity: RealtimeBrainSessionIdentity
    ) -> Self {
        Self(
            identity: identity,
            providerIdentity: .activeRealtimeProvider,
            mode: .providerDefault,
            voiceProfileID: nil,
            providerPrivateVoiceReference: nil,
            fallback: .providerDefault
        )
    }

    func rebound(
        to nextIdentity: RealtimeBrainSessionIdentity
    ) -> Self? {
        guard identity.residentID == nextIdentity.residentID,
              identity.runtimeSessionID == nextIdentity.runtimeSessionID,
              identity.brainLeaseID == nextIdentity.brainLeaseID,
              identity.routeEpoch == nextIdentity.routeEpoch,
              nextIdentity.generation > identity.generation else {
            return nil
        }
        return Self(
            identity: nextIdentity,
            providerIdentity: providerIdentity,
            mode: mode,
            voiceProfileID: voiceProfileID,
            providerPrivateVoiceReference: providerPrivateVoiceReference,
            fallback: fallback
        )
    }
}

nonisolated struct RealtimeBrainOpenSessionCommand: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
    let voiceBinding: RuntimeVoiceBinding
    let tools: [RealtimeBrainToolAdvertisement]

    init(
        identity: RealtimeBrainSessionIdentity,
        tools: [RealtimeBrainToolAdvertisement] = []
    ) {
        self.identity = identity
        voiceBinding = .providerDefault(identity: identity)
        self.tools = tools
    }

    init(
        identity: RealtimeBrainSessionIdentity,
        voiceBinding: RuntimeVoiceBinding,
        tools: [RealtimeBrainToolAdvertisement] = []
    ) {
        self.identity = identity
        self.voiceBinding = voiceBinding
        self.tools = tools
    }
}

nonisolated enum RealtimeBrainContextUpdateKind:
    String,
    Sendable,
    Equatable {
    case bootstrap
    case delta
}

nonisolated enum RealtimeBrainContextScope:
    String,
    Hashable,
    Sendable {
    case stableResident
    case dynamicSession
    case memoryDelta
    case relationshipDelta
    case toolResultContext
}

nonisolated struct RealtimeBrainContextSection: Sendable, Equatable {
    let scope: RealtimeBrainContextScope
    let content: String
}

nonisolated struct RealtimeBrainRuntimeContextUpdate:
    Sendable,
    Equatable {
    let identity: RealtimeBrainSessionIdentity
    let kind: RealtimeBrainContextUpdateKind
    let contextRevision: UInt64
    let sections: [RealtimeBrainContextSection]
}

nonisolated enum RealtimeBrainPCMEncoding: String, Sendable, Equatable {
    case pcm16LittleEndian
}

nonisolated struct RealtimeBrainAudioFormat: Sendable, Equatable {
    let encoding: RealtimeBrainPCMEncoding
    let sampleRate: Int
    let channelCount: Int
}

nonisolated enum RealtimeBrainAudioProvenance:
    String,
    Sendable,
    Equatable {
    case microphoneCapture
    case acousticEchoProcessed
    case voiceProcessed
    case providerGenerated
}

nonisolated struct RealtimeBrainAudioFrame: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
    let sequence: UInt64
    let timestampNanoseconds: UInt64
    let format: RealtimeBrainAudioFormat
    let provenance: RealtimeBrainAudioProvenance
    let bytes: Data
}

nonisolated enum RealtimeBrainLocalAudioActivityKind:
    String,
    Sendable,
    Equatable {
    case none
    case listeningNearEnd = "listening_near_end"
    case sourceGatedNearEnd = "source_gated_near_end"
}

nonisolated struct RealtimeBrainLocalAudioActivity:
    Sendable,
    Equatable {
    let kind: RealtimeBrainLocalAudioActivityKind
    let residentPlaybackSequence: UInt64
    let residentPlaybackActive: Bool
    let lastAudibleResidentRenderTimestampNanoseconds: UInt64?
    let sourceGateEpoch: UInt64
    let routeStable: Bool
    let inputDeviceAvailable: Bool
    let outputDeviceAvailable: Bool

    static let none = RealtimeBrainLocalAudioActivity(
        kind: .none,
        residentPlaybackSequence: 0,
        residentPlaybackActive: false,
        lastAudibleResidentRenderTimestampNanoseconds: nil,
        sourceGateEpoch: 0,
        routeStable: false,
        inputDeviceAvailable: false,
        outputDeviceAvailable: false
    )
}

nonisolated struct RealtimeBrainAudioDelta: Sendable, Equatable {
    let sequence: UInt64
    let timestampNanoseconds: UInt64
    let format: RealtimeBrainAudioFormat
    let provenance: RealtimeBrainAudioProvenance
    let bytes: Data
}

nonisolated struct RealtimeBrainEventIdentity: Hashable, Sendable {
    let session: RealtimeBrainSessionIdentity
    let turnID: RealtimeBrainTurnID?
    let responseID: RealtimeBrainResponseID?
    let contextRevision: UInt64
}

nonisolated struct RealtimeBrainNarrativeMemoryCandidate:
    Sendable,
    Equatable {
    let identity: RealtimeBrainEventIdentity
    let candidateID: String
    let memoryType: String
    let summary: String
    let sourceTurnIDs: [String]
    let consentSignal: String
    let sensitivityFlags: [String]
    let evidenceSource: String
    let inputClassification: String
    let confidence: Double
}

nonisolated struct RealtimeBrainRelationshipEvidenceCandidate:
    Sendable,
    Equatable {
    let identity: RealtimeBrainEventIdentity
    let evidenceType: String
    let evidenceDetected: Bool
    let evidenceSource: String
    let requiresUserConfirmation: Bool
    let confidence: Double
}

nonisolated struct RealtimeBrainGrowthObservationCandidate:
    Sendable,
    Equatable {
    let identity: RealtimeBrainEventIdentity
    let observation: String
    let confidence: Double
}

nonisolated struct RealtimeBrainSemanticOutput: Sendable, Equatable {
    let canonicalText: String
    let narrativeMemoryCandidates:
        [RealtimeBrainNarrativeMemoryCandidate]
    let relationshipEvidenceCandidates:
        [RealtimeBrainRelationshipEvidenceCandidate]
    let growthObservationCandidates:
        [RealtimeBrainGrowthObservationCandidate]

    init(
        canonicalText: String,
        narrativeMemoryCandidates:
            [RealtimeBrainNarrativeMemoryCandidate] = [],
        relationshipEvidenceCandidates:
            [RealtimeBrainRelationshipEvidenceCandidate] = [],
        growthObservationCandidates:
            [RealtimeBrainGrowthObservationCandidate] = []
    ) {
        self.canonicalText = canonicalText
        self.narrativeMemoryCandidates = narrativeMemoryCandidates
        self.relationshipEvidenceCandidates =
            relationshipEvidenceCandidates
        self.growthObservationCandidates = growthObservationCandidates
    }
}

nonisolated struct RealtimeBrainToolCallCandidate: Sendable, Equatable {
    let identity: RealtimeBrainEventIdentity
    let callID: RealtimeBrainToolCallID
    let toolName: String
    let arguments: Data
}

nonisolated struct RealtimeBrainInterruptionProposal:
    Sendable,
    Equatable {
    let identity: RealtimeBrainEventIdentity
    let reason: String
}

nonisolated enum RealtimeAcousticClassification:
    String,
    Sendable,
    Equatable {
    case silenceOrNoise = "silence_or_noise"
    case farEndDominant = "far_end_dominant"
    case residualEchoLikely = "residual_echo_likely"
    case nearEndCandidate = "near_end_candidate"
    case indeterminate
}

nonisolated enum RealtimeAcousticSourceAssessment:
    String,
    Sendable,
    Equatable {
    case echoOnly = "echo_only"
    case nearEndSpeech = "near_end_speech"
    case doubleTalk = "double_talk"
    case uncertain
}

nonisolated enum RealtimeAcousticDriftState:
    String,
    Sendable,
    Equatable {
    case stable
    case renderAhead = "render_ahead"
    case captureAhead = "capture_ahead"
    case unknown
}

nonisolated struct RealtimeAcousticMetrics: Sendable, Equatable {
    let residentPlaybackSequence: UInt64
    let residentPlaybackActive: Bool
    let lastAudibleResidentRenderTimestampNanoseconds: UInt64?
    let renderReferenceAvailable: Bool
    let renderReferenceRMS: Double?
    let rawCaptureRMS: Double?
    let aecOutputRMS: Double?
    let linearAECOutputRMS: Double?
    let renderCaptureCorrelation: Double?
    let residualRenderCorrelation: Double?
    let linearRenderCorrelation: Double?
    let captureTimestampNanoseconds: UInt64?
    let renderTimestampNanoseconds: UInt64?
    let sourceAlignmentDelayMilliseconds: Int?
    let estimatedDelayMilliseconds: Int?
    let erlDecibels: Double?
    let erleDecibels: Double?
    let renderCaptureSkewFrames: Int64?
    let driftState: RealtimeAcousticDriftState
    let sourceAssessment: RealtimeAcousticSourceAssessment
    let sourceGateOpen: Bool
    let sourceGateEpoch: UInt64
    let aecActive: Bool
    let sourceAlignmentLocked: Bool
    let routeStable: Bool
    let inputDeviceAvailable: Bool
    let outputDeviceAvailable: Bool
}

nonisolated enum RealtimeAcousticEligibilitySuppressionReason:
    String,
    Sendable,
    Equatable {
    case invalidObservation = "invalid_observation"
    case staleIdentity = "stale_identity"
    case staleObservation = "stale_observation"
    case duplicateObservation = "duplicate_observation"
    case silenceOrNoise = "silence_or_noise"
    case farEndDominant = "far_end_dominant"
    case residualEchoLikely = "residual_echo_likely"
    case indeterminate
    case playbackTail = "playback_tail"
    case residentPlaybackInactive = "resident_playback_inactive"
    case unstableNearEnd = "unstable_near_end"
    case alreadyEligible = "already_eligible"
}

nonisolated enum RealtimeAcousticEligibilityDisposition:
    Sendable,
    Equatable {
    case suppressed(RealtimeAcousticEligibilitySuppressionReason)
    case eligible
}

nonisolated struct RealtimeAcousticObservationIdentity:
    Sendable,
    Equatable {
    let session: RealtimeBrainSessionIdentity
    let captureGeneration: UInt64
    let sequence: UInt64
    let timestampNanoseconds: UInt64
}

nonisolated struct RealtimeAcousticObservation: Sendable, Equatable {
    let identity: RealtimeAcousticObservationIdentity
    let metrics: RealtimeAcousticMetrics
    let classification: RealtimeAcousticClassification
}

nonisolated enum RealtimeAcousticObservationIgnoreReason:
    String,
    Sendable,
    Equatable {
    case invalidObservation = "invalid_observation"
    case staleIdentity = "stale_identity"
    case staleObservation = "stale_observation"
    case duplicateObservation = "duplicate_observation"
}

nonisolated enum RealtimeAcousticObservationDisposition:
    Sendable,
    Equatable {
    case ignored(RealtimeAcousticObservationIgnoreReason)
    case observed
}

nonisolated enum RealtimeAcousticClassifier {
    static let silenceRMS = 0.005
    static let activityRMS = 0.012
    static let minimumTimingCorrelation = 0.35
    static let residualEchoCorrelation = 0.55
    static let reliableERLEDecibels = 3.0
    static let maximumRenderDelayMilliseconds = 500
    static let maximumAlignmentErrorMilliseconds = 30

    static func classify(
        metrics: RealtimeAcousticMetrics,
        observationTimestampNanoseconds: UInt64
    ) -> RealtimeAcousticClassification {
        guard metrics.routeStable,
              metrics.inputDeviceAvailable,
              metrics.outputDeviceAvailable,
              let rawCaptureRMS = finiteNonnegative(
                  metrics.rawCaptureRMS
              ),
              let aecOutputRMS = finiteNonnegative(
                  metrics.aecOutputRMS
              ),
              let linearAECOutputRMS = finiteNonnegative(
                  metrics.linearAECOutputRMS
              ) else {
            return .indeterminate
        }

        let outputRMS = max(aecOutputRMS, linearAECOutputRMS)
        if !metrics.residentPlaybackActive {
            return max(rawCaptureRMS, outputRMS) < activityRMS
                ? .silenceOrNoise : .nearEndCandidate
        }

        guard metrics.aecActive,
              metrics.renderReferenceAvailable,
              metrics.sourceAlignmentLocked,
              let renderRMS = finiteNonnegative(
                  metrics.renderReferenceRMS
              ),
              timingIsAligned(
                  metrics: metrics,
                  observationTimestampNanoseconds:
                      observationTimestampNanoseconds
              ) else {
            return .indeterminate
        }

        if renderRMS < silenceRMS {
            if max(rawCaptureRMS, outputRMS) < activityRMS {
                return .silenceOrNoise
            }
            switch metrics.sourceAssessment {
            case .nearEndSpeech, .doubleTalk:
                return .nearEndCandidate
            case .echoOnly, .uncertain:
                return .indeterminate
            }
        }

        switch metrics.sourceAssessment {
        case .nearEndSpeech, .doubleTalk:
            return .nearEndCandidate
        case .uncertain:
            return .indeterminate
        case .echoOnly:
            let residualCorrelation = max(
                finiteUnit(metrics.residualRenderCorrelation) ?? 0,
                finiteUnit(metrics.linearRenderCorrelation) ?? 0
            )
            if outputRMS >= activityRMS,
               residualCorrelation >= residualEchoCorrelation {
                return .residualEchoLikely
            }
            let rawCorrelation = finiteUnit(
                metrics.renderCaptureCorrelation
            ) ?? 0
            let erleIsReliable = finiteValue(metrics.erleDecibels).map {
                $0 >= reliableERLEDecibels
            } ?? false
            if rawCorrelation >= minimumTimingCorrelation,
               outputRMS < activityRMS || erleIsReliable {
                return .farEndDominant
            }
            return .indeterminate
        }
    }

    private static func timingIsAligned(
        metrics: RealtimeAcousticMetrics,
        observationTimestampNanoseconds: UInt64
    ) -> Bool {
        guard observationTimestampNanoseconds > 0,
              let captureTimestamp = metrics.captureTimestampNanoseconds,
              let renderTimestamp = metrics.renderTimestampNanoseconds,
              captureTimestamp == observationTimestampNanoseconds,
              captureTimestamp >= renderTimestamp,
              let alignedDelay = metrics.sourceAlignmentDelayMilliseconds,
              alignedDelay >= 0 else {
            return false
        }
        let measuredDelay = Int((
            Double(captureTimestamp - renderTimestamp) / 1_000_000
        ).rounded())
        return measuredDelay <= maximumRenderDelayMilliseconds
            && abs(measuredDelay - alignedDelay)
                <= maximumAlignmentErrorMilliseconds
    }

    private static func finiteNonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func finiteUnit(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0 ... 1).contains(value) else {
            return nil
        }
        return value
    }

    private static func finiteValue(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}

nonisolated struct RealtimeAcousticInterruptionEligibilityGate: Sendable {
    static let minimumConsecutiveNearEndObservations: UInt64 = 1
    static let observationFreshnessNanoseconds: UInt64 = 500_000_000
    static let residualTailWindowNanoseconds: UInt64 = 500_000_000

    private let session: RealtimeBrainSessionIdentity
    private let captureGeneration: UInt64
    private var lastSequence: UInt64 = 0
    private var lastTimestampNanoseconds: UInt64 = 0
    private var lastPlaybackSequence: UInt64 = 0
    private var lastAudibleRenderTimestampNanoseconds: UInt64 = 0
    private var consecutiveNearEndObservations: UInt64 = 0
    private var eligibilityIssued = false

    init(
        session: RealtimeBrainSessionIdentity,
        captureGeneration: UInt64
    ) {
        self.session = session
        self.captureGeneration = captureGeneration
    }

    mutating func evaluate(
        _ observation: RealtimeAcousticObservation,
        receivedAtNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> RealtimeAcousticEligibilityDisposition {
        let identity = observation.identity
        guard identity.session == session,
              identity.captureGeneration == captureGeneration else {
            return .suppressed(.staleIdentity)
        }
        guard identity.sequence > 0,
              identity.timestampNanoseconds > 0,
              identity.timestampNanoseconds <= receivedAtNanoseconds,
              receivedAtNanoseconds - identity.timestampNanoseconds
                <= Self.observationFreshnessNanoseconds,
              observation.classification == RealtimeAcousticClassifier
                .classify(
                    metrics: observation.metrics,
                    observationTimestampNanoseconds:
                        identity.timestampNanoseconds
                ),
              !observation.metrics.residentPlaybackActive
                || observation.metrics.residentPlaybackSequence > 0 else {
            resetCandidateStability()
            return .suppressed(.invalidObservation)
        }
        if identity.sequence == lastSequence {
            return .suppressed(.duplicateObservation)
        }
        guard identity.sequence > lastSequence,
              identity.timestampNanoseconds >= lastTimestampNanoseconds,
              observation.metrics.residentPlaybackSequence
                >= lastPlaybackSequence else {
            resetCandidateStability()
            return .suppressed(.staleObservation)
        }

        let metrics = observation.metrics
        let beginsNewPlayback = metrics.residentPlaybackSequence
            > lastPlaybackSequence
        let captureTimestamp = metrics.captureTimestampNanoseconds
        if let audibleRenderTimestamp = metrics
            .lastAudibleResidentRenderTimestampNanoseconds {
            guard audibleRenderTimestamp > 0,
                  captureTimestamp.map({
                      audibleRenderTimestamp <= $0
                  }) ?? !metrics.residentPlaybackActive,
                  beginsNewPlayback
                    || audibleRenderTimestamp
                        >= lastAudibleRenderTimestampNanoseconds else {
                resetCandidateStability()
                return .suppressed(.staleObservation)
            }
        }

        lastSequence = identity.sequence
        lastTimestampNanoseconds = identity.timestampNanoseconds
        if metrics.residentPlaybackSequence > lastPlaybackSequence {
            lastPlaybackSequence = metrics.residentPlaybackSequence
            lastAudibleRenderTimestampNanoseconds = 0
            resetEligibilityEpoch()
        }
        if let audibleRenderTimestamp = metrics
            .lastAudibleResidentRenderTimestampNanoseconds {
            lastAudibleRenderTimestampNanoseconds = audibleRenderTimestamp
        }

        guard metrics.residentPlaybackActive else {
            resetEligibilityEpoch()
            if lastAudibleRenderTimestampNanoseconds > 0,
               captureTimestamp == nil {
                return .suppressed(.indeterminate)
            }
            if let captureTimestamp,
               lastAudibleRenderTimestampNanoseconds > 0,
               captureTimestamp >= lastAudibleRenderTimestampNanoseconds,
               captureTimestamp - lastAudibleRenderTimestampNanoseconds
                    < Self.residualTailWindowNanoseconds {
                return .suppressed(.playbackTail)
            }
            return .suppressed(.residentPlaybackInactive)
        }

        switch observation.classification {
        case .silenceOrNoise:
            resetForSuppressedObservation(metrics)
            return .suppressed(.silenceOrNoise)
        case .farEndDominant:
            resetForSuppressedObservation(metrics)
            return .suppressed(.farEndDominant)
        case .residualEchoLikely:
            resetForSuppressedObservation(metrics)
            return .suppressed(.residualEchoLikely)
        case .indeterminate:
            resetForSuppressedObservation(metrics)
            return .suppressed(.indeterminate)
        case .nearEndCandidate:
            consecutiveNearEndObservations &+= 1
            guard metrics.sourceGateOpen else {
                resetEligibilityEpoch()
                return .suppressed(.unstableNearEnd)
            }
            guard consecutiveNearEndObservations
                    >= Self.minimumConsecutiveNearEndObservations else {
                return .suppressed(.unstableNearEnd)
            }
            guard !eligibilityIssued else {
                return .suppressed(.alreadyEligible)
            }
            eligibilityIssued = true
            return .eligible
        }
    }

    private mutating func resetForSuppressedObservation(
        _ metrics: RealtimeAcousticMetrics
    ) {
        if metrics.sourceGateOpen {
            resetCandidateStability()
        } else {
            resetEligibilityEpoch()
        }
    }

    private mutating func resetCandidateStability() {
        consecutiveNearEndObservations = 0
    }

    private mutating func resetEligibilityEpoch() {
        resetCandidateStability()
        eligibilityIssued = false
    }

}

nonisolated struct RealtimeInterruptionEvidenceIdentity:
    Sendable,
    Equatable {
    let session: RealtimeBrainSessionIdentity
    let turnID: RealtimeBrainTurnID?
    let responseID: RealtimeBrainResponseID?
    let contextRevision: UInt64
    let sequence: UInt64
    let timestampNanoseconds: UInt64
}

nonisolated struct RealtimeInterruptionAcousticFacts:
    Sendable,
    Equatable {
    let sourceGateEpoch: UInt64
    let nearEndDetected: Bool
    let farEndActive: Bool
    let sourceGateOpen: Bool
    let renderReferenceConfidence: Double
    let routeStable: Bool
    let inputDeviceAvailable: Bool
    let outputDeviceAvailable: Bool
}

nonisolated struct RealtimeInterruptionSemanticFacts:
    Sendable,
    Equatable {
    let reason: String
}

nonisolated enum RealtimeInterruptionEvidenceSource:
    Sendable,
    Equatable {
    case acousticHost(RealtimeInterruptionAcousticFacts)
    case realtimeBrain(RealtimeInterruptionSemanticFacts)
}

nonisolated struct RealtimeInterruptionEvidence:
    Sendable,
    Equatable {
    let identity: RealtimeInterruptionEvidenceIdentity
    let source: RealtimeInterruptionEvidenceSource
}

nonisolated enum RealtimeInterruptionIgnoreReason:
    String,
    Sendable,
    Equatable {
    case invalidEvidence
    case staleIdentity
    case staleEvidence
    case duplicateEvidence
}

nonisolated enum RealtimeInterruptionHostCommand:
    String,
    Sendable,
    Equatable {
    case clearPlayback
}

nonisolated struct RealtimeConfirmedInterruption:
    Sendable,
    Equatable {
    let decisionID: UUID
    let interruptedIdentity: RealtimeBrainSessionIdentity
    let nextIdentity: RealtimeBrainSessionIdentity
    let turnID: RealtimeBrainTurnID
    let responseID: RealtimeBrainResponseID
    let hostCommand: RealtimeInterruptionHostCommand
}

nonisolated enum RealtimeInterruptionDecision:
    Sendable,
    Equatable {
    case ignored(RealtimeInterruptionIgnoreReason)
    case observed
    case confirmed(RealtimeConfirmedInterruption)
}

nonisolated struct RealtimeBrainToolResultCommand: Sendable, Equatable {
    let identity: RealtimeBrainEventIdentity
    let sequence: UInt64
    let callID: RealtimeBrainToolCallID
    let output: String
    let isError: Bool
}

nonisolated struct RealtimeBrainCreateResponseCommand: Sendable, Equatable {
    let identity: RealtimeBrainEventIdentity
    let sourceEventSequence: UInt64
}

nonisolated enum RealtimeBrainCancellationReason:
    String,
    Sendable,
    Equatable {
    case stopped
    case interrupted
    case superseded
    case sessionReplaced
    case runtimeDecision
}

nonisolated struct RealtimeBrainCancelGenerationCommand:
    Sendable,
    Equatable {
    let identity: RealtimeBrainSessionIdentity
    let nextGeneration: UInt64
    let reason: RealtimeBrainCancellationReason
}

nonisolated enum RealtimeBrainInterruptReason:
    String,
    Sendable,
    Equatable {
    case runtimeDecision
    case sessionClosing
    case sessionReplaced
}

nonisolated struct RealtimeBrainInterruptCommand: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
    let nextGeneration: UInt64
    let reason: RealtimeBrainInterruptReason
}

nonisolated struct RealtimeBrainCloseSessionCommand: Sendable, Equatable {
    let identity: RealtimeBrainSessionIdentity
}

nonisolated enum RealtimeResidentBrainEventKind: Sendable, Equatable {
    case sessionReady
    case sessionClosed
    // Recoverable response error. Terminal session failure is thrown by receiveEvent.
    case error(RealtimeResidentBrainError)
    case userSpeechStarted
    case userSpeechStopped
    case userTranscriptPartial(String)
    case userTranscriptFinal(String)
    case residentTextDelta(String)
    case residentTextFinal(String)
    case residentAudioDelta(RealtimeBrainAudioDelta)
    case residentSpeakingStarted
    case residentSpeakingStopped
    case residentSemanticFinal(RealtimeBrainSemanticOutput)
    case toolCall(RealtimeBrainToolCallCandidate)
    case interruptionProposed(RealtimeBrainInterruptionProposal)
    case cancelled(RealtimeBrainCancellationReason)
}

nonisolated struct RealtimeResidentBrainEvent: Sendable, Equatable {
    let identity: RealtimeBrainEventIdentity
    let sequence: UInt64
    let kind: RealtimeResidentBrainEventKind
}

nonisolated protocol RealtimeResidentBrainProvider: Sendable {
    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws
    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws
    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws
    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws
    func createResponse(
        _ command: RealtimeBrainCreateResponseCommand
    ) async throws
    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws
    func interrupt(_ command: RealtimeBrainInterruptCommand) async throws
    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent
    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws
}

nonisolated enum RealtimeBrainEventDisposition: Sendable, Equatable {
    case accepted(RealtimeResidentBrainEvent)
    case rejectedStale
    case rejectedDuplicate
    case rejectedOutOfOrder
    case rejectedBufferOverflow
    case deferredOutOfOrder
    case rejectedClosed
    case rejectedInvalidIdentity
    case rejectedInvalidEvent
    case rejectedContextTransition
    case rejectedReceiveInFlight
}

nonisolated enum RuntimeRealtimeBrainSessionLifecycle:
    Sendable,
    Equatable {
    case opening
    case awaitingBootstrap
    case active
    case transitioningGeneration
    case closing
    case closed
}

nonisolated enum RuntimeRealtimeBrainProviderCloseOutcome:
    Sendable,
    Equatable {
    case closed
    case failed(RealtimeResidentBrainError)
}

nonisolated enum RuntimeRealtimeBrainProviderCloseClaim:
    Sendable,
    Equatable {
    case perform(UUID, [RealtimeBrainSessionIdentity])
    case wait(UUID)
    case closed
    case invalid
}

nonisolated enum RuntimeRealtimeBrainAudioInputStart:
    Sendable,
    Equatable {
    case accepted(UUID)
    case busy
    case invalid
}

nonisolated enum RuntimeRealtimeBrainResponseCreateStart:
    Sendable,
    Equatable {
    case accepted(UUID)
    case droppedOverlap(RealtimeBrainTurnID)
    case alreadyAuthorized(RealtimeBrainTurnID)
    case invalid
}

nonisolated enum RuntimeRealtimeBrainReceiveStart:
    Sendable,
    Equatable {
    case provider(UUID)
    case buffered(RealtimeResidentBrainEvent)
    case rejected(RealtimeBrainEventDisposition)
}

nonisolated struct RuntimeRealtimeBrainAcceptedAudioInputBoundary:
    Sendable,
    Equatable {
    let sequence: UInt64
    let timestampNanoseconds: UInt64
    let contextRevision: UInt64
    let activity: RealtimeBrainLocalAudioActivity
    let userActivityEvidence: Bool
    let lastUserActivitySequence: UInt64
    let lastUserActivityTimestampNanoseconds: UInt64
    let lastUserActivityContextRevision: UInt64
    let lastUserActivity:
        RealtimeBrainLocalAudioActivity
}

nonisolated struct RuntimeRealtimeBrainSemanticFinalKey:
    Hashable,
    Sendable {
    let turnID: RealtimeBrainTurnID
    let responseID: RealtimeBrainResponseID
}

nonisolated final class RuntimeRealtimeBrainProviderOperationGate:
    @unchecked Sendable {
    private struct Waiter {
        let excludedToken: UUID?
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var tokens: Set<UUID> = []
    private var waiters: [Waiter] = []

    func begin(_ token: UUID) {
        lock.withLock {
            _ = tokens.insert(token)
        }
    }

    func finish(_ token: UUID) {
        let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard tokens.remove(token) != nil else { return [] }
            var ready: [CheckedContinuation<Void, Never>] = []
            waiters.removeAll { waiter in
                let isReady = isSatisfied(
                    excluding: waiter.excludedToken
                )
                if isReady { ready.append(waiter.continuation) }
                return isReady
            }
            return ready
        }
        continuations.forEach { $0.resume() }
    }

    func waitForAll() async {
        await waitForAll(excluding: nil)
    }

    func waitForAll(excluding token: UUID) async {
        await waitForAll(excluding: Optional(token))
    }

    private func waitForAll(excluding token: UUID?) async {
        await withCheckedContinuation { continuation in
            let resumesImmediately = lock.withLock {
                guard !isSatisfied(excluding: token) else { return true }
                waiters.append(Waiter(
                    excludedToken: token,
                    continuation: continuation
                ))
                return false
            }
            if resumesImmediately {
                continuation.resume()
            }
        }
    }

    private func isSatisfied(excluding token: UUID?) -> Bool {
        guard let token else { return tokens.isEmpty }
        return tokens.allSatisfy { $0 == token }
    }
}

nonisolated final class RuntimeRealtimeBrainSessionGate:
    @unchecked Sendable {
    private static let deferredEventCapacity = 16

    private let lock = NSLock()
    private let providerOperations =
        RuntimeRealtimeBrainProviderOperationGate()
    private var identity: RealtimeBrainSessionIdentity?
    private var lifecycle = RuntimeRealtimeBrainSessionLifecycle.closed
    private var contextRevision: UInt64 = 0
    private var lastAcceptedEventSequence: UInt64 = 0
    private var deferredEvents: [UInt64: RealtimeResidentBrainEvent] = [:]
    private var receiveToken: UUID?
    private var contextUpdateToken: UUID?
    private var pendingContextUpdate: RealtimeBrainRuntimeContextUpdate?
    private var audioInputToken: UUID?
    private var pendingAudioInput: RealtimeBrainAudioFrame?
    private var pendingAudioInputActivity =
        RealtimeBrainLocalAudioActivity.none
    private var lastAudioInputSequence: UInt64 = 0
    private var lastAudioInputTimestamp: UInt64 = 0
    private var lastAudioInputFrame: RealtimeBrainAudioFrame?
    private var lastAudioInputContextRevision: UInt64 = 0
    private var lastAudioInputActivity =
        RealtimeBrainLocalAudioActivity.none
    private var lastAudioInputUserActivityEvidence = false
    private var lastUserActivityInputSequence: UInt64 = 0
    private var lastUserActivityInputTimestamp: UInt64 = 0
    private var lastUserActivityInputContextRevision: UInt64 = 0
    private var lastUserActivityInputActivity =
        RealtimeBrainLocalAudioActivity.none
    private var audioInputSinceStableBoundary = false
    private var lastAudioOutputSequence: UInt64 = 0
    private var lastAudioOutputTimestamp: UInt64 = 0
    private var semanticFinals:
        Set<RuntimeRealtimeBrainSemanticFinalKey> = []
    private var activeTurnIDs: Set<RealtimeBrainTurnID> = []
    private var activeResponseIDs:
        Set<RuntimeRealtimeBrainSemanticFinalKey> = []
    private var terminalTurnIDs: Set<RealtimeBrainTurnID> = []
    private var terminalResponseIDs:
        Set<RuntimeRealtimeBrainSemanticFinalKey> = []
    private var toolResultToken: UUID?
    private var pendingToolResult: RealtimeBrainToolResultCommand?
    private var lastToolResultSequence: UInt64 = 0
    private var toolCandidates:
        [RealtimeBrainToolCallID: RealtimeBrainEventIdentity] = [:]
    private var completedToolCalls: Set<RealtimeBrainToolCallID> = []
    private var responseCreateToken: UUID?
    private var pendingResponseCreate: RealtimeBrainCreateResponseCommand?
    private var pendingResponseCreateSourceTurnIDs:
        Set<RealtimeBrainTurnID> = []
    private var responseCreateExecutionClaimed = false
    private var responseAuthorizationCandidates:
        [RealtimeBrainTurnID: UInt64] = [:]
    private var consumedResponseAuthorizationTurns:
        Set<RealtimeBrainTurnID> = []
    private var awaitingResponseTurn: RealtimeBrainTurnID?
    private var awaitingResponseExcludedID: RealtimeBrainResponseID?
    private var generationTransitionToken: UUID?
    private var pendingGenerationIdentity: RealtimeBrainSessionIdentity?
    private var closeIdentityCandidates: [RealtimeBrainSessionIdentity] = []
    private var closeAttemptID: UUID?
    private var closeWaiters:
        [UUID: [CheckedContinuation<
            RuntimeRealtimeBrainProviderCloseOutcome,
            Never
        >]] = [:]
    private var closeWaiterClaimCounts: [UUID: Int] = [:]
    private var completedCloseOutcomes:
        [UUID: RuntimeRealtimeBrainProviderCloseOutcome] = [:]
    private var closedIdentity: RealtimeBrainSessionIdentity?

    func reserve(_ identity: RealtimeBrainSessionIdentity) -> Bool {
        lock.withLock {
            guard self.identity == nil else { return false }
            self.identity = identity
            lifecycle = .opening
            resetSessionStateLocked()
            closedIdentity = nil
            return true
        }
    }

    func activate(_ identity: RealtimeBrainSessionIdentity) -> Bool {
        lock.withLock {
            guard self.identity == identity,
                  lifecycle == .opening else { return false }
            lifecycle = .awaitingBootstrap
            return true
        }
    }

    func isActive(_ identity: RealtimeBrainSessionIdentity) -> Bool {
        lock.withLock {
            isReadyLocked(identity)
        }
    }

    func isCurrent(_ identity: RealtimeBrainEventIdentity) -> Bool {
        lock.withLock {
            isReadyLocked(identity.session)
                && contextRevision == identity.contextRevision
        }
    }

    func acceptedAudioInputBoundary(
        for identity: RealtimeBrainSessionIdentity
    ) -> RuntimeRealtimeBrainAcceptedAudioInputBoundary? {
        lock.withLock {
            guard isReadyLocked(identity) else { return nil }
            return RuntimeRealtimeBrainAcceptedAudioInputBoundary(
                sequence: lastAudioInputSequence,
                timestampNanoseconds: lastAudioInputTimestamp,
                contextRevision: lastAudioInputContextRevision,
                activity: lastAudioInputActivity,
                userActivityEvidence:
                    lastAudioInputUserActivityEvidence,
                lastUserActivitySequence:
                    lastUserActivityInputSequence,
                lastUserActivityTimestampNanoseconds:
                    lastUserActivityInputTimestamp,
                lastUserActivityContextRevision:
                    lastUserActivityInputContextRevision,
                lastUserActivity: lastUserActivityInputActivity
            )
        }
    }

    func acceptedAudioInputSequence(
        for identity: RealtimeBrainSessionIdentity
    ) -> UInt64? {
        acceptedAudioInputBoundary(for: identity)?.sequence
    }

    func isActiveInterruptionTarget(
        _ identity: RealtimeBrainEventIdentity
    ) -> Bool {
        lock.withLock {
            guard isReadyLocked(identity.session),
                  contextRevision == identity.contextRevision,
                  let turnID = identity.turnID,
                  let responseID = Self.semanticFinalKey(
                    for: identity
                  ) else { return false }
            return activeTurnIDs.contains(turnID)
                && activeResponseIDs.contains(responseID)
        }
    }

    func beginContextUpdate(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) -> UUID? {
        lock.withLock {
            guard identity == update.identity,
                  contextUpdateToken == nil,
                  receiveToken == nil,
                  audioInputToken == nil,
                  !audioInputSinceStableBoundary,
                  toolResultToken == nil,
                  responseCreateToken == nil,
                  awaitingResponseTurn == nil,
                  toolCandidates.isEmpty,
                  activeTurnIDs.isEmpty,
                  activeResponseIDs.isEmpty,
                  deferredEvents.isEmpty,
                  generationTransitionToken == nil,
                  Self.hasUniqueContextScopes(update.sections),
                  update.contextRevision > contextRevision else {
                return nil
            }
            let isValid: Bool
            switch update.kind {
            case .bootstrap:
                isValid = lifecycle == .awaitingBootstrap
                    && contextRevision == 0
            case .delta:
                isValid = lifecycle == .active
                    && contextRevision > 0
            }
            guard isValid else { return nil }
            let token = UUID()
            contextUpdateToken = token
            pendingContextUpdate = update
            providerOperations.begin(token)
            return token
        }
    }

    func finishContextUpdate(
        token: UUID,
        update: RealtimeBrainRuntimeContextUpdate,
        succeeded: Bool
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard contextUpdateToken == token,
                  pendingContextUpdate == update else {
                return false
            }
            contextUpdateToken = nil
            pendingContextUpdate = nil
            guard succeeded,
                  identity == update.identity,
                  update.contextRevision > contextRevision else {
                return false
            }
            switch update.kind {
            case .bootstrap:
                guard lifecycle == .awaitingBootstrap,
                      contextRevision == 0 else { return false }
                lifecycle = .active
            case .delta:
                guard lifecycle == .active,
                      contextRevision > 0 else { return false }
            }
            contextRevision = update.contextRevision
            return true
        }
    }

    func beginAudioInput(
        _ frame: RealtimeBrainAudioFrame,
        activity: RealtimeBrainLocalAudioActivity
    ) -> RuntimeRealtimeBrainAudioInputStart {
        lock.withLock {
            guard isReadyLocked(frame.identity) else { return .invalid }
            guard audioInputToken == nil else { return .busy }
            guard frame.sequence == lastAudioInputSequence &+ 1,
                  lastAudioInputSequence == 0
                    || frame.timestampNanoseconds
                        >= lastAudioInputTimestamp,
                  Self.isValidLocalAudioActivity(
                    activity,
                    provenance: frame.provenance
                  ),
                  Self.isValidPCM(frame.format, bytes: frame.bytes),
                  Self.isInputProvenance(frame.provenance) else {
                return .invalid
            }
            let token = UUID()
            audioInputToken = token
            pendingAudioInput = frame
            pendingAudioInputActivity = activity
            providerOperations.begin(token)
            return .accepted(token)
        }
    }

    func finishAudioInput(
        token: UUID,
        frame: RealtimeBrainAudioFrame,
        activity: RealtimeBrainLocalAudioActivity,
        succeeded: Bool
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard audioInputToken == token,
                  pendingAudioInput == frame,
                  pendingAudioInputActivity == activity else { return false }
            audioInputToken = nil
            pendingAudioInput = nil
            pendingAudioInputActivity = .none
            guard succeeded,
                  isReadyLocked(frame.identity) else { return false }
            let userActivityEvidence = Self.authorizesUserActivity(
                activity,
                frameTimestampNanoseconds: frame.timestampNanoseconds
            ) && activity.kind == .sourceGatedNearEnd
            lastAudioInputSequence = frame.sequence
            lastAudioInputTimestamp = frame.timestampNanoseconds
            lastAudioInputFrame = frame
            lastAudioInputContextRevision = contextRevision
            lastAudioInputActivity = activity
            lastAudioInputUserActivityEvidence =
                userActivityEvidence
            if userActivityEvidence {
                lastUserActivityInputSequence = frame.sequence
                lastUserActivityInputTimestamp =
                    frame.timestampNanoseconds
                lastUserActivityInputContextRevision = contextRevision
                lastUserActivityInputActivity = activity
            }
            audioInputSinceStableBoundary = true
            return true
        }
    }

    func confirmListeningAudioInput(
        frame: RealtimeBrainAudioFrame,
        activity: RealtimeBrainLocalAudioActivity
    ) -> Bool {
        lock.withLock {
            guard isReadyLocked(frame.identity),
                  activity.kind == .listeningNearEnd,
                  lastAudioInputFrame == frame,
                  lastAudioInputActivity == activity,
                  lastAudioInputContextRevision == contextRevision,
                  !lastAudioInputUserActivityEvidence,
                  Self.isValidLocalAudioActivity(
                    activity,
                    provenance: frame.provenance
                  ),
                  Self.authorizesUserActivity(
                    activity,
                    frameTimestampNanoseconds:
                        frame.timestampNanoseconds
                  ) else { return false }
            lastAudioInputUserActivityEvidence = true
            lastUserActivityInputSequence = frame.sequence
            lastUserActivityInputTimestamp = frame.timestampNanoseconds
            lastUserActivityInputContextRevision = contextRevision
            lastUserActivityInputActivity = activity
            return true
        }
    }

    func beginToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) -> UUID? {
        lock.withLock {
            guard isReadyLocked(command.identity.session),
                  contextRevision == command.identity.contextRevision,
                  toolResultToken == nil,
                  let turnID = command.identity.turnID,
                  !terminalTurnIDs.contains(turnID),
                  awaitingResponseTurn == nil
                    || awaitingResponseTurn == turnID,
                  command.sequence == lastToolResultSequence &+ 1,
                  toolCandidates[command.callID] == command.identity,
                  !completedToolCalls.contains(command.callID) else {
                return nil
            }
            let token = UUID()
            toolResultToken = token
            pendingToolResult = command
            awaitingResponseTurn = turnID
            awaitingResponseExcludedID = command.identity.responseID
            providerOperations.begin(token)
            return token
        }
    }

    func finishToolResult(
        token: UUID,
        command: RealtimeBrainToolResultCommand,
        succeeded: Bool
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard toolResultToken == token,
                  pendingToolResult == command else { return false }
            toolResultToken = nil
            pendingToolResult = nil
            let turnID = command.identity.turnID
            if !succeeded, awaitingResponseTurn == turnID {
                awaitingResponseTurn = nil
                awaitingResponseExcludedID = nil
            }
            guard succeeded,
                  isReadyLocked(command.identity.session),
                  contextRevision == command.identity.contextRevision,
                  let turnID else {
                return false
            }
            lastToolResultSequence = command.sequence
            toolCandidates.removeValue(forKey: command.callID)
            completedToolCalls.insert(command.callID)
            if let key = Self.semanticFinalKey(for: command.identity) {
                activeResponseIDs.remove(key)
            }
            return hasAuthorizedResponseProgressLocked(for: turnID)
        }
    }

    func beginResponseCreate(
        _ command: RealtimeBrainCreateResponseCommand,
        sourceTurnIDs: Set<RealtimeBrainTurnID>? = nil
    ) -> RuntimeRealtimeBrainResponseCreateStart {
        lock.withLock {
            guard isReadyLocked(command.identity.session),
                  contextRevision == command.identity.contextRevision,
                  command.identity.responseID == nil,
                  let turnID = command.identity.turnID else { return .invalid }
            let authorizedSourceTurnIDs = sourceTurnIDs ?? [turnID]
            guard !authorizedSourceTurnIDs.isEmpty,
                  authorizedSourceTurnIDs.contains(turnID) else {
                return .invalid
            }
            if consumedResponseAuthorizationTurns.contains(turnID) {
                return .alreadyAuthorized(turnID)
            }
            guard authorizedSourceTurnIDs.allSatisfy({
                activeTurnIDs.contains($0)
                    && !terminalTurnIDs.contains($0)
            }) else { return .invalid }
            guard responseAuthorizationCandidates[turnID]
                    == command.sourceEventSequence else { return .invalid }
            responseAuthorizationCandidates.removeValue(forKey: turnID)
            consumedResponseAuthorizationTurns.insert(turnID)
            guard responseCreateToken == nil,
                  awaitingResponseTurn == nil,
                  activeResponseIDs.isEmpty,
                  toolResultToken == nil else {
                retireUserActivityTurnsLocked(authorizedSourceTurnIDs)
                return .droppedOverlap(turnID)
            }
            let token = UUID()
            responseCreateToken = token
            pendingResponseCreate = command
            pendingResponseCreateSourceTurnIDs = authorizedSourceTurnIDs
            responseCreateExecutionClaimed = false
            awaitingResponseTurn = turnID
            awaitingResponseExcludedID = nil
            providerOperations.begin(token)
            return .accepted(token)
        }
    }

    func claimResponseCreateExecution(
        token: UUID,
        command: RealtimeBrainCreateResponseCommand,
        sourceTurnIDs: Set<RealtimeBrainTurnID>
    ) -> Bool {
        lock.withLock {
            guard responseCreateToken == token,
                  pendingResponseCreate == command,
                  pendingResponseCreateSourceTurnIDs == sourceTurnIDs,
                  !responseCreateExecutionClaimed,
                  isReadyLocked(command.identity.session),
                  contextRevision == command.identity.contextRevision,
                  let turnID = command.identity.turnID,
                  !sourceTurnIDs.isEmpty,
                  sourceTurnIDs.contains(turnID),
                  sourceTurnIDs.allSatisfy({
                    activeTurnIDs.contains($0)
                        && !terminalTurnIDs.contains($0)
                  }),
                  awaitingResponseTurn == turnID,
                  !terminalTurnIDs.contains(turnID) else {
                return false
            }
            retireUserActivityTurnsLocked(sourceTurnIDs.subtracting([turnID]))
            responseCreateExecutionClaimed = true
            return true
        }
    }

    func retireUserActivityTurns(
        _ turnIDs: Set<RealtimeBrainTurnID>,
        session: RealtimeBrainSessionIdentity,
        contextRevision: UInt64,
        afterCommittedTerminalEvent: Bool = false
    ) -> Bool {
        lock.withLock {
            guard isReadyLocked(session),
                  self.contextRevision == contextRevision else {
                return false
            }
            if afterCommittedTerminalEvent {
                guard !turnIDs.isDisjoint(with: terminalTurnIDs) else {
                    return false
                }
            } else {
                guard awaitingResponseTurn.map({
                    !turnIDs.contains($0)
                }) ?? true,
                activeResponseIDs.allSatisfy({
                    !turnIDs.contains($0.turnID)
                }) else {
                    return false
                }
            }
            retireUserActivityTurnsLocked(turnIDs)
            return true
        }
    }

    func finishResponseCreate(
        token: UUID,
        command: RealtimeBrainCreateResponseCommand,
        succeeded: Bool
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard responseCreateToken == token,
                  pendingResponseCreate == command else { return false }
            responseCreateToken = nil
            pendingResponseCreate = nil
            pendingResponseCreateSourceTurnIDs.removeAll(
                keepingCapacity: true
            )
            responseCreateExecutionClaimed = false
            let turnID = command.identity.turnID
            if !succeeded, awaitingResponseTurn == turnID {
                awaitingResponseTurn = nil
                awaitingResponseExcludedID = nil
            }
            guard succeeded,
                  isReadyLocked(command.identity.session),
                  contextRevision == command.identity.contextRevision,
                  let turnID else { return false }
            return hasAuthorizedResponseProgressLocked(for: turnID)
        }
    }

    func beginGenerationTransition(
        from current: RealtimeBrainSessionIdentity,
        to next: RealtimeBrainSessionIdentity
    ) -> UUID? {
        lock.withLock {
            guard isReadyLocked(current),
                  generationTransitionToken == nil,
                  current.brainLeaseID == next.brainLeaseID,
                  current.routeEpoch == next.routeEpoch,
                  next.generation > current.generation else {
                return nil
            }
            let token = UUID()
            generationTransitionToken = token
            pendingGenerationIdentity = next
            lifecycle = .transitioningGeneration
            providerOperations.begin(token)
            invalidateInFlightOperationsLocked()
            deferredEvents.removeAll(keepingCapacity: true)
            return token
        }
    }

    func commitGenerationTransition(
        token: UUID,
        from current: RealtimeBrainSessionIdentity,
        to next: RealtimeBrainSessionIdentity
    ) -> Bool {
        defer { providerOperations.finish(token) }
        return lock.withLock {
            guard generationTransitionToken == token,
                  identity == current,
                  pendingGenerationIdentity == next,
                  lifecycle == .transitioningGeneration else {
                return false
            }
            identity = next
            lifecycle = .active
            generationTransitionToken = nil
            pendingGenerationIdentity = nil
            resetGenerationStateLocked()
            return true
        }
    }

    func cancelGenerationTransition(token: UUID) {
        defer { providerOperations.finish(token) }
        lock.withLock {
            if generationTransitionToken == token {
                generationTransitionToken = nil
            }
        }
    }

    func beginReceiving(
        _ identity: RealtimeBrainSessionIdentity
    ) -> RuntimeRealtimeBrainReceiveStart {
        lock.withLock {
            if let rejection = receptionRejectionLocked(for: identity) {
                return .rejected(rejection)
            }
            let nextSequence = lastAcceptedEventSequence &+ 1
            if let event = deferredEvents.removeValue(
                forKey: nextSequence
            ) {
                guard event.identity.session == identity,
                      event.identity.contextRevision == contextRevision,
                      Self.hasRequiredIdentity(event) else {
                    consumeRejectedSequenceLocked(event)
                    return .rejected(.rejectedInvalidIdentity)
                }
                guard Self.hasStructurallyValidPayload(event),
                      hasStatefullyValidPayloadLocked(event) else {
                    consumeRejectedSequenceLocked(event)
                    return .rejected(.rejectedInvalidEvent)
                }
                commitEventLocked(event)
                return .buffered(event)
            }
            guard receiveToken == nil else {
                return .rejected(.rejectedReceiveInFlight)
            }
            let token = UUID()
            receiveToken = token
            return .provider(token)
        }
    }

    func cancelReceiving(token: UUID) {
        lock.withLock {
            if receiveToken == token {
                receiveToken = nil
            }
        }
    }

    func accept(
        _ event: RealtimeResidentBrainEvent,
        expected identity: RealtimeBrainSessionIdentity,
        token: UUID
    ) -> RealtimeBrainEventDisposition {
        return lock.withLock {
            guard receiveToken == token else {
                return receptionRejectionLocked(for: identity)
                    ?? .rejectedStale
            }
            receiveToken = nil
            guard self.identity == identity,
                  lifecycle == .active,
                  event.identity.session == identity else {
                return closedIdentity == identity
                    ? .rejectedClosed : .rejectedStale
            }
            if event.sequence <= lastAcceptedEventSequence
                || deferredEvents[event.sequence] != nil {
                return .rejectedDuplicate
            }
            let expectedSequence = lastAcceptedEventSequence &+ 1
            if event.sequence != expectedSequence {
                guard deferredEvents.count
                        < Self.deferredEventCapacity else {
                    return .rejectedBufferOverflow
                }
                deferredEvents[event.sequence] = event
                return .deferredOutOfOrder
            }
            guard event.identity.contextRevision == contextRevision,
                  Self.hasRequiredIdentity(event) else {
                consumeRejectedSequenceLocked(event)
                return .rejectedInvalidIdentity
            }
            guard Self.hasStructurallyValidPayload(event) else {
                consumeRejectedSequenceLocked(event)
                return .rejectedInvalidEvent
            }
            guard hasStatefullyValidPayloadLocked(event) else {
                consumeRejectedSequenceLocked(event)
                return .rejectedInvalidEvent
            }
            commitEventLocked(event)
            return .accepted(event)
        }
    }

    func claimClose(
        _ identity: RealtimeBrainSessionIdentity
    ) -> RuntimeRealtimeBrainProviderCloseClaim {
        lock.withLock {
            if closedIdentity == identity {
                return .closed
            }
            guard self.identity == identity else { return .invalid }
            if let closeAttemptID {
                closeWaiterClaimCounts[closeAttemptID, default: 0] += 1
                return .wait(closeAttemptID)
            }
            let attemptID = UUID()
            if closeIdentityCandidates.isEmpty {
                closeIdentityCandidates = [identity]
                if let pendingGenerationIdentity,
                   pendingGenerationIdentity != identity {
                    closeIdentityCandidates.append(
                        pendingGenerationIdentity
                    )
                }
            }
            closeAttemptID = attemptID
            lifecycle = .closing
            generationTransitionToken = nil
            pendingGenerationIdentity = nil
            invalidateInFlightOperationsLocked()
            deferredEvents.removeAll(keepingCapacity: true)
            return .perform(attemptID, closeIdentityCandidates)
        }
    }

    func waitForClose(
        attemptID: UUID
    ) async -> RuntimeRealtimeBrainProviderCloseOutcome {
        await withCheckedContinuation { continuation in
            let immediate: RuntimeRealtimeBrainProviderCloseOutcome? =
                lock.withLock {
                    if let outcome = completedCloseOutcomes[attemptID] {
                        consumeCloseWaiterClaimLocked(attemptID)
                        return outcome
                    }
                    guard closeAttemptID == attemptID else {
                        consumeCloseWaiterClaimLocked(attemptID)
                        return .failed(.invalidIdentity)
                    }
                    closeWaiters[attemptID, default: []].append(
                        continuation
                    )
                    return nil
                }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }

    func finishClose(
        identity: RealtimeBrainSessionIdentity,
        attemptID: UUID,
        outcome: RuntimeRealtimeBrainProviderCloseOutcome
    ) {
        let waiters: [CheckedContinuation<
            RuntimeRealtimeBrainProviderCloseOutcome,
            Never
        >] = lock.withLock {
            guard closeAttemptID == attemptID,
                  self.identity == identity else { return [] }
            let waiters = closeWaiters.removeValue(
                forKey: attemptID
            ) ?? []
            closeAttemptID = nil
            let remainingClaims = max(
                0,
                (closeWaiterClaimCounts[attemptID] ?? 0)
                    - waiters.count
            )
            if remainingClaims > 0 {
                closeWaiterClaimCounts[attemptID] = remainingClaims
                completedCloseOutcomes[attemptID] = outcome
            } else {
                closeWaiterClaimCounts.removeValue(forKey: attemptID)
                completedCloseOutcomes.removeValue(forKey: attemptID)
            }
            if outcome == .closed {
                markClosedLocked(identity)
            } else {
                lifecycle = .closing
            }
            return waiters
        }
        waiters.forEach { $0.resume(returning: outcome) }
    }

    func isClosed(_ identity: RealtimeBrainSessionIdentity) -> Bool {
        lock.withLock { closedIdentity == identity }
    }

    func waitForProviderOperationsToFinish() async {
        await providerOperations.waitForAll()
    }

    func waitForProviderOperationsToFinish(
        excludingGenerationTransition token: UUID
    ) async {
        await providerOperations.waitForAll(excluding: token)
    }

    private func receptionRejectionLocked(
        for identity: RealtimeBrainSessionIdentity
    ) -> RealtimeBrainEventDisposition? {
        if closedIdentity == identity {
            return .rejectedClosed
        }
        guard self.identity == identity else { return .rejectedStale }
        if lifecycle == .awaitingBootstrap
            || contextUpdateToken != nil {
            return .rejectedContextTransition
        }
        guard lifecycle == .active else { return .rejectedStale }
        return nil
    }

    private func consumeCloseWaiterClaimLocked(_ attemptID: UUID) {
        let remainingClaims = max(
            0,
            (closeWaiterClaimCounts[attemptID] ?? 0) - 1
        )
        if remainingClaims == 0 {
            closeWaiterClaimCounts.removeValue(forKey: attemptID)
            completedCloseOutcomes.removeValue(forKey: attemptID)
        } else {
            closeWaiterClaimCounts[attemptID] = remainingClaims
        }
    }

    private func isReadyLocked(
        _ identity: RealtimeBrainSessionIdentity
    ) -> Bool {
        self.identity == identity
            && lifecycle == .active
            && contextUpdateToken == nil
            && generationTransitionToken == nil
            && closeAttemptID == nil
    }

    private func commitEventLocked(_ event: RealtimeResidentBrainEvent) {
        lastAcceptedEventSequence = event.sequence
        updateOpenTurnLedgerLocked(event)
        switch event.kind {
        case .userTranscriptFinal:
            if let turnID = event.identity.turnID,
               !consumedResponseAuthorizationTurns.contains(turnID),
               responseAuthorizationCandidates[turnID] == nil {
                responseAuthorizationCandidates[turnID] = event.sequence
            }
        case .residentAudioDelta(let audio):
            lastAudioOutputSequence = audio.sequence
            lastAudioOutputTimestamp = audio.timestampNanoseconds
        case .residentSemanticFinal:
            if let key = Self.semanticFinalKey(for: event.identity) {
                _ = semanticFinals.insert(key)
            }
        case .toolCall(let candidate):
            toolCandidates[candidate.callID] = candidate.identity
        default:
            break
        }
    }

    private func consumeRejectedSequenceLocked(
        _ event: RealtimeResidentBrainEvent
    ) {
        guard event.sequence == lastAcceptedEventSequence &+ 1 else {
            return
        }
        lastAcceptedEventSequence = event.sequence
        if case .residentAudioDelta(let audio) = event.kind,
           audio.sequence == lastAudioOutputSequence &+ 1 {
            lastAudioOutputSequence = audio.sequence
            if Self.hasStructurallyValidPayload(event),
               audio.timestampNanoseconds >= lastAudioOutputTimestamp {
                lastAudioOutputTimestamp = audio.timestampNanoseconds
            }
        }
    }

    private func updateOpenTurnLedgerLocked(
        _ event: RealtimeResidentBrainEvent
    ) {
        switch event.kind {
        case .sessionReady:
            break
        case .sessionClosed:
            audioInputSinceStableBoundary = false
            terminalTurnIDs.formUnion(activeTurnIDs)
            terminalResponseIDs.formUnion(activeResponseIDs)
            activeTurnIDs.removeAll(keepingCapacity: true)
            activeResponseIDs.removeAll(keepingCapacity: true)
            responseAuthorizationCandidates.removeAll(keepingCapacity: true)
            awaitingResponseTurn = nil
            awaitingResponseExcludedID = nil
        case .error, .residentSemanticFinal:
            audioInputSinceStableBoundary = false
            markTurnTerminalLocked(event.identity)
        case .cancelled:
            audioInputSinceStableBoundary = false
            if event.identity.turnID != nil {
                markTurnTerminalLocked(event.identity)
            } else {
                terminalTurnIDs.formUnion(activeTurnIDs)
                terminalResponseIDs.formUnion(activeResponseIDs)
                activeTurnIDs.removeAll(keepingCapacity: true)
                activeResponseIDs.removeAll(keepingCapacity: true)
                responseAuthorizationCandidates.removeAll(
                    keepingCapacity: true
                )
                awaitingResponseTurn = nil
                awaitingResponseExcludedID = nil
            }
        case .userSpeechStarted, .userSpeechStopped,
             .userTranscriptPartial, .userTranscriptFinal:
            if let turnID = event.identity.turnID {
                activeTurnIDs.insert(turnID)
            }
        case .residentTextDelta, .residentTextFinal,
             .residentAudioDelta, .residentSpeakingStarted,
             .residentSpeakingStopped, .toolCall,
             .interruptionProposed:
            if let turnID = event.identity.turnID {
                activeTurnIDs.insert(turnID)
                if claimsAwaitingResponseLocked(event.identity) {
                    awaitingResponseTurn = nil
                    awaitingResponseExcludedID = nil
                }
            }
            if let responseID = Self.semanticFinalKey(
                for: event.identity
            ) {
                activeResponseIDs.insert(responseID)
            }
        }
    }

    private func markTurnTerminalLocked(
        _ identity: RealtimeBrainEventIdentity
    ) {
        if let turnID = identity.turnID {
            terminalTurnIDs.insert(turnID)
            responseAuthorizationCandidates.removeValue(forKey: turnID)
            if awaitingResponseTurn == turnID {
                awaitingResponseTurn = nil
                awaitingResponseExcludedID = nil
            }
        }
        if let responseID = Self.semanticFinalKey(for: identity) {
            terminalResponseIDs.insert(responseID)
        }
        closeTurnLocked(identity.turnID)
    }

    private func closeTurnLocked(_ turnID: RealtimeBrainTurnID?) {
        guard let turnID else { return }
        activeTurnIDs.remove(turnID)
        activeResponseIDs = Set(
            activeResponseIDs.filter { $0.turnID != turnID }
        )
        toolCandidates = toolCandidates.filter {
            $0.value.turnID != turnID
        }
    }

    private func retireUserActivityTurnsLocked(
        _ turnIDs: Set<RealtimeBrainTurnID>
    ) {
        for turnID in turnIDs {
            terminalTurnIDs.insert(turnID)
            responseAuthorizationCandidates.removeValue(forKey: turnID)
            consumedResponseAuthorizationTurns.insert(turnID)
            closeTurnLocked(turnID)
        }
        if let awaitingResponseTurn,
           turnIDs.contains(awaitingResponseTurn) {
            self.awaitingResponseTurn = nil
            awaitingResponseExcludedID = nil
        }
    }

    private func hasStatefullyValidPayloadLocked(
        _ event: RealtimeResidentBrainEvent
    ) -> Bool {
        if let turnID = event.identity.turnID,
           terminalTurnIDs.contains(turnID) {
            return false
        }
        if let responseID = Self.semanticFinalKey(for: event.identity),
           terminalResponseIDs.contains(responseID) {
            return false
        }
        switch event.kind {
        case .residentAudioDelta(let audio):
            return isAuthorizedResponseEventLocked(event.identity)
                && audio.sequence == lastAudioOutputSequence &+ 1
                && (lastAudioOutputSequence == 0
                    || audio.timestampNanoseconds
                        >= lastAudioOutputTimestamp)
        case .residentSemanticFinal:
            guard let key = Self.semanticFinalKey(
                for: event.identity
            ) else { return false }
            return isAuthorizedResponseEventLocked(event.identity)
                && !semanticFinals.contains(key)
        case .toolCall(let candidate):
            return isAuthorizedResponseEventLocked(event.identity)
                && toolCandidates[candidate.callID] == nil
                && !completedToolCalls.contains(candidate.callID)
        case .error, .residentTextDelta, .residentTextFinal,
             .residentSpeakingStarted, .residentSpeakingStopped:
            return isAuthorizedResponseEventLocked(event.identity)
        case .interruptionProposed:
            guard let turnID = event.identity.turnID,
                  let responseID = Self.semanticFinalKey(
                    for: event.identity
                  ) else { return false }
            return activeTurnIDs.contains(turnID)
                && (activeResponseIDs.contains(responseID)
                    || claimsAwaitingResponseLocked(event.identity))
        default:
            return true
        }
    }

    private func isAuthorizedResponseEventLocked(
        _ identity: RealtimeBrainEventIdentity
    ) -> Bool {
        guard let responseID = Self.semanticFinalKey(for: identity) else {
            return false
        }
        return activeResponseIDs.contains(responseID)
            || claimsAwaitingResponseLocked(identity)
    }

    private func claimsAwaitingResponseLocked(
        _ identity: RealtimeBrainEventIdentity
    ) -> Bool {
        guard let turnID = identity.turnID,
              let responseID = identity.responseID,
              awaitingResponseTurn == turnID else { return false }
        return responseID != awaitingResponseExcludedID
    }

    private func hasAuthorizedResponseProgressLocked(
        for turnID: RealtimeBrainTurnID
    ) -> Bool {
        awaitingResponseTurn == turnID
            || activeResponseIDs.contains { $0.turnID == turnID }
            || terminalTurnIDs.contains(turnID)
    }

    private static func hasStructurallyValidPayload(
        _ event: RealtimeResidentBrainEvent
    ) -> Bool {
        switch event.kind {
        case .sessionReady, .sessionClosed, .error, .cancelled,
             .userSpeechStarted, .userSpeechStopped,
             .residentSpeakingStarted, .residentSpeakingStopped:
            return true
        case .userTranscriptPartial(let text),
             .userTranscriptFinal(let text),
             .residentTextDelta(let text),
             .residentTextFinal(let text):
            return !text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        case .residentAudioDelta(let audio):
            return audio.provenance == .providerGenerated
                && Self.isValidPCM(audio.format, bytes: audio.bytes)
        case .residentSemanticFinal(let output):
            return Self.hasValidSemanticOutput(
                output,
                identity: event.identity
            )
        case .toolCall(let candidate):
            return candidate.identity == event.identity
                && !candidate.callID.rawValue.isEmpty
                && !candidate.toolName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        case .interruptionProposed(let proposal):
            return proposal.identity == event.identity
                && !proposal.reason.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        }
    }

    private static func isValidPCM(
        _ format: RealtimeBrainAudioFormat,
        bytes: Data
    ) -> Bool {
        guard format.sampleRate > 0,
              format.channelCount > 0,
              format.channelCount <= 64,
              !bytes.isEmpty else { return false }
        let bytesPerFrame = 2 * format.channelCount
        return bytes.count.isMultiple(of: bytesPerFrame)
    }

    private static func hasUniqueContextScopes(
        _ sections: [RealtimeBrainContextSection]
    ) -> Bool {
        Set(sections.map(\.scope)).count == sections.count
    }

    private static func hasValidSemanticOutput(
        _ output: RealtimeBrainSemanticOutput,
        identity: RealtimeBrainEventIdentity
    ) -> Bool {
        guard !output.canonicalText.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              Set(output.narrativeMemoryCandidates.map(\.candidateID))
                .count == output.narrativeMemoryCandidates.count else {
            return false
        }
        let memoriesAreValid = output.narrativeMemoryCandidates.allSatisfy {
            candidate in
            candidate.identity == identity
                && hasText(candidate.candidateID)
                && hasText(candidate.memoryType)
                && hasText(candidate.summary)
                && !candidate.sourceTurnIDs.isEmpty
                && candidate.sourceTurnIDs.allSatisfy(hasText)
                && hasText(candidate.consentSignal)
                && candidate.sensitivityFlags.allSatisfy(hasText)
                && hasText(candidate.evidenceSource)
                && hasText(candidate.inputClassification)
                && hasValidConfidence(candidate.confidence)
        }
        let relationshipsAreValid =
            output.relationshipEvidenceCandidates.allSatisfy { candidate in
                candidate.identity == identity
                    && hasText(candidate.evidenceType)
                    && hasText(candidate.evidenceSource)
                    && hasValidConfidence(candidate.confidence)
            }
        let growthObservationsAreValid =
            output.growthObservationCandidates.allSatisfy { candidate in
                candidate.identity == identity
                    && hasText(candidate.observation)
                    && hasValidConfidence(candidate.confidence)
            }
        return memoriesAreValid
            && relationshipsAreValid
            && growthObservationsAreValid
    }

    private static func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func hasValidConfidence(_ confidence: Double) -> Bool {
        confidence.isFinite && (0...1).contains(confidence)
    }

    private static func semanticFinalKey(
        for identity: RealtimeBrainEventIdentity
    ) -> RuntimeRealtimeBrainSemanticFinalKey? {
        guard let turnID = identity.turnID,
              let responseID = identity.responseID else { return nil }
        return RuntimeRealtimeBrainSemanticFinalKey(
            turnID: turnID,
            responseID: responseID
        )
    }

    private static func isInputProvenance(
        _ provenance: RealtimeBrainAudioProvenance
    ) -> Bool {
        switch provenance {
        case .microphoneCapture, .acousticEchoProcessed,
             .voiceProcessed:
            return true
        case .providerGenerated:
            return false
        }
    }

    private static func isValidLocalAudioActivity(
        _ activity: RealtimeBrainLocalAudioActivity,
        provenance: RealtimeBrainAudioProvenance
    ) -> Bool {
        switch activity.kind {
        case .none:
            return activity.sourceGateEpoch == 0
        case .listeningNearEnd:
            return provenance == .acousticEchoProcessed
                && !activity.residentPlaybackActive
                && activity.sourceGateEpoch == 0
                && activity.routeStable
                && activity.inputDeviceAvailable
                && activity.outputDeviceAvailable
                && (activity
                    .lastAudibleResidentRenderTimestampNanoseconds
                    .map { $0 > 0 } ?? true)
        case .sourceGatedNearEnd:
            return provenance == .acousticEchoProcessed
                && activity.residentPlaybackActive
                && activity.residentPlaybackSequence > 0
                && activity.sourceGateEpoch > 0
                && activity.routeStable
                && activity.inputDeviceAvailable
                && activity.outputDeviceAvailable
        }
    }

    private static func authorizesUserActivity(
        _ activity: RealtimeBrainLocalAudioActivity,
        frameTimestampNanoseconds: UInt64
    ) -> Bool {
        switch activity.kind {
        case .none:
            return false
        case .sourceGatedNearEnd:
            return true
        case .listeningNearEnd:
            guard frameTimestampNanoseconds > 0,
                  let audibleTimestamp = activity
                    .lastAudibleResidentRenderTimestampNanoseconds else {
                return frameTimestampNanoseconds > 0
            }
            return frameTimestampNanoseconds >= audibleTimestamp
                && frameTimestampNanoseconds - audibleTimestamp
                    >= RealtimeAcousticInterruptionEligibilityGate
                        .residualTailWindowNanoseconds
        }
    }

    private func invalidateInFlightOperationsLocked() {
        receiveToken = nil
        contextUpdateToken = nil
        pendingContextUpdate = nil
        audioInputToken = nil
        pendingAudioInput = nil
        pendingAudioInputActivity = .none
        toolResultToken = nil
        pendingToolResult = nil
        responseCreateToken = nil
        pendingResponseCreate = nil
        pendingResponseCreateSourceTurnIDs.removeAll(keepingCapacity: true)
        responseCreateExecutionClaimed = false
    }

    private func resetGenerationStateLocked() {
        lastAcceptedEventSequence = 0
        deferredEvents.removeAll(keepingCapacity: true)
        receiveToken = nil
        lastAudioInputSequence = 0
        lastAudioInputTimestamp = 0
        lastAudioInputFrame = nil
        lastAudioInputContextRevision = 0
        lastAudioInputActivity = .none
        lastAudioInputUserActivityEvidence = false
        lastUserActivityInputSequence = 0
        lastUserActivityInputTimestamp = 0
        lastUserActivityInputContextRevision = 0
        lastUserActivityInputActivity = .none
        audioInputSinceStableBoundary = false
        audioInputToken = nil
        pendingAudioInput = nil
        pendingAudioInputActivity = .none
        lastAudioOutputSequence = 0
        lastAudioOutputTimestamp = 0
        semanticFinals.removeAll(keepingCapacity: true)
        activeTurnIDs.removeAll(keepingCapacity: true)
        activeResponseIDs.removeAll(keepingCapacity: true)
        terminalTurnIDs.removeAll(keepingCapacity: true)
        terminalResponseIDs.removeAll(keepingCapacity: true)
        toolResultToken = nil
        pendingToolResult = nil
        lastToolResultSequence = 0
        toolCandidates.removeAll(keepingCapacity: true)
        completedToolCalls.removeAll(keepingCapacity: true)
        responseCreateToken = nil
        pendingResponseCreate = nil
        pendingResponseCreateSourceTurnIDs.removeAll(keepingCapacity: true)
        responseCreateExecutionClaimed = false
        responseAuthorizationCandidates.removeAll(keepingCapacity: true)
        consumedResponseAuthorizationTurns.removeAll(keepingCapacity: true)
        awaitingResponseTurn = nil
        awaitingResponseExcludedID = nil
    }

    private func resetSessionStateLocked() {
        contextRevision = 0
        contextUpdateToken = nil
        pendingContextUpdate = nil
        generationTransitionToken = nil
        pendingGenerationIdentity = nil
        closeAttemptID = nil
        closeIdentityCandidates.removeAll(keepingCapacity: true)
        closeWaiters.removeAll(keepingCapacity: true)
        resetGenerationStateLocked()
    }

    private func markClosedLocked(
        _ identity: RealtimeBrainSessionIdentity
    ) {
        self.identity = nil
        lifecycle = .closed
        resetSessionStateLocked()
        closedIdentity = identity
    }

    private static func hasRequiredIdentity(
        _ event: RealtimeResidentBrainEvent
    ) -> Bool {
        let hasTurn = event.identity.turnID != nil
        let hasResponse = event.identity.responseID != nil
        switch event.kind {
        case .sessionReady, .sessionClosed, .cancelled:
            return true
        case .error:
            return hasTurn && hasResponse
        case .userSpeechStarted, .userSpeechStopped,
             .userTranscriptPartial, .userTranscriptFinal:
            return hasTurn && !hasResponse
        case .residentTextDelta, .residentTextFinal,
             .residentAudioDelta, .residentSpeakingStarted,
             .residentSpeakingStopped, .residentSemanticFinal:
            return hasTurn && hasResponse
        case .toolCall(let candidate):
            return hasTurn && hasResponse
                && candidate.identity == event.identity
        case .interruptionProposed(let proposal):
            return hasTurn && hasResponse
                && proposal.identity == event.identity
        }
    }
}
