import Foundation

nonisolated enum RealtimeWebSocketFrame: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

nonisolated enum RealtimeWebSocketCloseReason: Sendable, Equatable {
    case normal
    case cancelled
}

nonisolated protocol RealtimeWebSocketTransport: Sendable {
    func connect(endpoint: URL, bearerToken: String) async throws
    func send(_ frame: RealtimeWebSocketFrame) async throws
    func receive() async throws -> RealtimeWebSocketFrame
    func close(reason: RealtimeWebSocketCloseReason) async
}

nonisolated enum NativeSpeechInternalDiagnosticSource: String, Sendable {
    case transport
    case wire
    case adapter
    case runtime
}

nonisolated enum NativeSpeechDiagnosticRouteKind: String, Sendable, Hashable {
    case realtimeBrain = "realtime_full_duplex"
    case nativeSpeech = "native_speech"
    case cascadedASR = "cascaded_asr"
    case cascadedTTS = "cascaded_tts"
}

nonisolated struct NativeSpeechTransportWriteDiagnosticSnapshot:
    Sendable,
    Equatable {
    static let defaultWebSocketWriteWindowCapacity = 8

    let writeWindowCapacity: Int
    let pendingWriteCount: Int
    let maximumPendingWriteCount: Int
    let submittedAudioAppendCount: UInt64
    let completedAudioAppendCount: UInt64
    let submittedResponseCreateCount: UInt64
    let completedResponseCreateCount: UInt64
    let capacityWaitCount: UInt64
    let capacityWaitTotalDurationMilliseconds: UInt64
    let capacityWaitMaximumDurationMilliseconds: UInt64
    let audioAppendWriteTotalDurationMilliseconds: UInt64
    let audioAppendWriteMaximumDurationMilliseconds: UInt64

    static let zero = NativeSpeechTransportWriteDiagnosticSnapshot(
        writeWindowCapacity: 0,
        pendingWriteCount: 0,
        maximumPendingWriteCount: 0,
        submittedAudioAppendCount: 0,
        completedAudioAppendCount: 0,
        submittedResponseCreateCount: 0,
        completedResponseCreateCount: 0,
        capacityWaitCount: 0,
        capacityWaitTotalDurationMilliseconds: 0,
        capacityWaitMaximumDurationMilliseconds: 0,
        audioAppendWriteTotalDurationMilliseconds: 0,
        audioAppendWriteMaximumDurationMilliseconds: 0
    )
}

nonisolated struct NativeSpeechInternalDiagnosticEvent: Sendable {
    let timestamp: Date
    let monotonicTimestampNanoseconds: UInt64
    let source: NativeSpeechInternalDiagnosticSource
    let category: String
    let routeKind: NativeSpeechDiagnosticRouteKind?
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
    let queueDepth: Int?
    let byteCount: Int?
    let arrivalIntervalMilliseconds: UInt64?
    let wireToStandardDurationMilliseconds: UInt64?
    let writeWindowCapacity: Int?
    let pendingWriteCount: Int?
    let durationMilliseconds: UInt64?
    let pcmPeak: Double?
    let pcmRMS: Double?
    let errorCode: String?

    init(
        source: NativeSpeechInternalDiagnosticSource,
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
        queueDepth: Int? = nil,
        byteCount: Int? = nil,
        arrivalIntervalMilliseconds: UInt64? = nil,
        wireToStandardDurationMilliseconds: UInt64? = nil,
        writeWindowCapacity: Int? = nil,
        pendingWriteCount: Int? = nil,
        durationMilliseconds: UInt64? = nil,
        pcmPeak: Double? = nil,
        pcmRMS: Double? = nil,
        errorCode: String? = nil,
        timestamp: Date = Date(),
        monotonicTimestampNanoseconds: UInt64 =
            DispatchTime.now().uptimeNanoseconds
    ) {
        self.timestamp = timestamp
        self.monotonicTimestampNanoseconds = monotonicTimestampNanoseconds
        self.source = source
        self.category = category
        self.routeKind = routeKind
        self.interactionShortID = interactionShortID
        self.turnNumber = turnNumber
        self.turnGeneration = turnGeneration
        self.stateBefore = stateBefore
        self.stateAfter = stateAfter
        self.disposition = disposition
        self.wireSequence = wireSequence
        self.responseCorrelationHash = responseCorrelationHash
        self.itemCorrelationHash = itemCorrelationHash
        self.audioSequence = audioSequence
        self.queueDepth = queueDepth
        self.byteCount = byteCount
        self.arrivalIntervalMilliseconds = arrivalIntervalMilliseconds
        self.wireToStandardDurationMilliseconds =
            wireToStandardDurationMilliseconds
        self.writeWindowCapacity = writeWindowCapacity
        self.pendingWriteCount = pendingWriteCount
        self.durationMilliseconds = durationMilliseconds
        self.pcmPeak = pcmPeak
        self.pcmRMS = pcmRMS
        self.errorCode = errorCode
    }
}

#if DEBUG
nonisolated struct NativeSpeechRealtimeAudioCapsuleSnapshot:
    Sendable,
    Equatable {
    let attemptID: UUID
    let routeAttemptID: UUID
    let brainLeaseID: UUID
    let routeEpoch: UInt64
    let startedAt: Date?
    let endedAt: Date?
    let firstGeneration: UInt64?
    let lastGeneration: UInt64?
    let firstBatchTerminalAudioSequence: UInt64?
    let lastBatchTerminalAudioSequence: UInt64?
    let bytes: Data
    let isSealed: Bool

    var durationMilliseconds: UInt64 {
        UInt64(bytes.count) * 1_000 / (16_000 * 2)
    }
}
#endif

nonisolated final class NativeSpeechDiagnosticBuffer: @unchecked Sendable {
    private struct TransportWriteDiagnosticAccumulator {
        var writeWindowCapacity = 0
        var pendingWriteCount = 0
        var maximumPendingWriteCount = 0
        var submittedAudioAppendCount: UInt64 = 0
        var completedAudioAppendCount: UInt64 = 0
        var submittedResponseCreateCount: UInt64 = 0
        var completedResponseCreateCount: UInt64 = 0
        var capacityWaitCount: UInt64 = 0
        var capacityWaitTotalDurationMilliseconds: UInt64 = 0
        var capacityWaitMaximumDurationMilliseconds: UInt64 = 0
        var audioAppendWriteTotalDurationMilliseconds: UInt64 = 0
        var audioAppendWriteMaximumDurationMilliseconds: UInt64 = 0

        mutating func consume(_ event: NativeSpeechInternalDiagnosticEvent) {
            if let writeWindowCapacity = event.writeWindowCapacity {
                self.writeWindowCapacity = writeWindowCapacity
            }
            if let pendingWriteCount = event.pendingWriteCount {
                self.pendingWriteCount = pendingWriteCount
                maximumPendingWriteCount = max(
                    maximumPendingWriteCount,
                    pendingWriteCount
                )
            }
            switch event.category {
            case "write_submitted_audio_append":
                submittedAudioAppendCount &+= 1
            case "write_completed_audio_append":
                completedAudioAppendCount &+= 1
                let duration = event.durationMilliseconds ?? 0
                audioAppendWriteTotalDurationMilliseconds &+= duration
                audioAppendWriteMaximumDurationMilliseconds = max(
                    audioAppendWriteMaximumDurationMilliseconds,
                    duration
                )
            case "write_submitted_response_create":
                submittedResponseCreateCount &+= 1
            case "write_completed_response_create":
                completedResponseCreateCount &+= 1
            case "write_capacity_wait_started_audio_append":
                capacityWaitCount &+= 1
            case "write_capacity_wait_completed_audio_append",
                 "write_capacity_wait_cancelled_audio_append":
                let duration = event.durationMilliseconds ?? 0
                capacityWaitTotalDurationMilliseconds &+= duration
                capacityWaitMaximumDurationMilliseconds = max(
                    capacityWaitMaximumDurationMilliseconds,
                    duration
                )
            default:
                break
            }
        }

        var snapshot: NativeSpeechTransportWriteDiagnosticSnapshot {
            NativeSpeechTransportWriteDiagnosticSnapshot(
                writeWindowCapacity: writeWindowCapacity,
                pendingWriteCount: pendingWriteCount,
                maximumPendingWriteCount: maximumPendingWriteCount,
                submittedAudioAppendCount: submittedAudioAppendCount,
                completedAudioAppendCount: completedAudioAppendCount,
                submittedResponseCreateCount:
                    submittedResponseCreateCount,
                completedResponseCreateCount:
                    completedResponseCreateCount,
                capacityWaitCount: capacityWaitCount,
                capacityWaitTotalDurationMilliseconds:
                    capacityWaitTotalDurationMilliseconds,
                capacityWaitMaximumDurationMilliseconds:
                    capacityWaitMaximumDurationMilliseconds,
                audioAppendWriteTotalDurationMilliseconds:
                    audioAppendWriteTotalDurationMilliseconds,
                audioAppendWriteMaximumDurationMilliseconds:
                    audioAppendWriteMaximumDurationMilliseconds
            )
        }
    }

    private static let defaultCapacity = 30_000
    private let lock = NSLock()
    private let capacity: Int
    private var storage: [NativeSpeechInternalDiagnosticEvent?]
    private var nextWriteIndex = 0
    private var eventCount = 0
    private var droppedEventCount: UInt64 = 0
    private var transportWriteDiagnostics: [
        NativeSpeechDiagnosticRouteKind:
            TransportWriteDiagnosticAccumulator
    ] = [:]
    #if DEBUG
    private struct RealtimeAudioCapsule {
        let attemptID: UUID
        let routeAttemptID: UUID
        let brainLeaseID: UUID
        let routeEpoch: UInt64
        var startedAt: Date?
        var endedAt: Date?
        var firstGeneration: UInt64?
        var lastGeneration: UInt64?
        var firstBatchTerminalAudioSequence: UInt64?
        var lastBatchTerminalAudioSequence: UInt64?
        var bytes = Data()
        var isSealed = false
    }

    private static let realtimeAudioCapsuleByteCapacity = 320_000
    private var realtimeAudioCapsule: RealtimeAudioCapsule?
    #endif

    init(capacity: Int = NativeSpeechDiagnosticBuffer.defaultCapacity) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    func append(_ event: NativeSpeechInternalDiagnosticEvent) {
        lock.withLock {
            if event.source == .transport, let routeKind = event.routeKind {
                var accumulator = transportWriteDiagnostics[routeKind]
                    ?? TransportWriteDiagnosticAccumulator()
                accumulator.consume(event)
                transportWriteDiagnostics[routeKind] = accumulator
            }
            if eventCount == capacity {
                droppedEventCount &+= 1
            } else {
                eventCount += 1
            }
            storage[nextWriteIndex] = event
            nextWriteIndex = (nextWriteIndex + 1) % capacity
        }
    }

    func transportWriteSnapshot(
        for routeKind: NativeSpeechDiagnosticRouteKind
    ) -> NativeSpeechTransportWriteDiagnosticSnapshot {
        lock.withLock {
            transportWriteDiagnostics[routeKind]?.snapshot ?? .zero
        }
    }

    #if DEBUG
    func armRealtimeAudioCapsule(
        attemptID: UUID,
        routeAttemptID: UUID,
        session: RealtimeBrainSessionIdentity
    ) -> Bool {
        lock.withLock {
            guard realtimeAudioCapsule == nil else { return false }
            realtimeAudioCapsule = RealtimeAudioCapsule(
                attemptID: attemptID,
                routeAttemptID: routeAttemptID,
                brainLeaseID: session.brainLeaseID,
                routeEpoch: session.routeEpoch
            )
            return true
        }
    }

    func appendRealtimeAudioCapsuleBatch(
        _ bytes: Data,
        identity: RealtimeBrainSessionIdentity,
        audioSequence: UInt64,
        capturedAt: Date = Date()
    ) {
        lock.withLock {
            guard var capsule = realtimeAudioCapsule,
                  !capsule.isSealed,
                  !bytes.isEmpty,
                  identity.brainLeaseID == capsule.brainLeaseID,
                  identity.routeEpoch == capsule.routeEpoch else { return }
            let remaining = Self.realtimeAudioCapsuleByteCapacity
                - capsule.bytes.count
            guard remaining > 0 else {
                capsule.isSealed = true
                realtimeAudioCapsule = capsule
                return
            }
            let appendedByteCount = min(remaining, bytes.count)
            capsule.bytes.append(
                contentsOf: bytes.prefix(appendedByteCount)
            )
            if capsule.startedAt == nil {
                capsule.startedAt = capturedAt
                capsule.firstGeneration = identity.generation
                capsule.firstBatchTerminalAudioSequence = audioSequence
            }
            capsule.endedAt = capturedAt
            capsule.lastGeneration = identity.generation
            capsule.lastBatchTerminalAudioSequence = audioSequence
            if capsule.bytes.count == Self.realtimeAudioCapsuleByteCapacity {
                capsule.isSealed = true
            }
            realtimeAudioCapsule = capsule
        }
    }

    func sealRealtimeAudioCapsule() {
        lock.withLock {
            realtimeAudioCapsule?.isSealed = true
        }
    }

    func realtimeAudioCapsuleSnapshot()
        -> NativeSpeechRealtimeAudioCapsuleSnapshot? {
        lock.withLock {
            realtimeAudioCapsule.map {
                NativeSpeechRealtimeAudioCapsuleSnapshot(
                    attemptID: $0.attemptID,
                    routeAttemptID: $0.routeAttemptID,
                    brainLeaseID: $0.brainLeaseID,
                    routeEpoch: $0.routeEpoch,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    firstGeneration: $0.firstGeneration,
                    lastGeneration: $0.lastGeneration,
                    firstBatchTerminalAudioSequence:
                        $0.firstBatchTerminalAudioSequence,
                    lastBatchTerminalAudioSequence:
                        $0.lastBatchTerminalAudioSequence,
                    bytes: $0.bytes,
                    isSealed: $0.isSealed
                )
            }
        }
    }

    func clearRealtimeAudioCapsule(
        matchingAttemptID attemptID: UUID? = nil
    ) {
        lock.withLock {
            guard attemptID == nil
                    || realtimeAudioCapsule?.attemptID == attemptID else {
                return
            }
            realtimeAudioCapsule = nil
        }
    }
    #endif

    func drain() -> (
        events: [NativeSpeechInternalDiagnosticEvent],
        droppedEventCount: UInt64
    ) {
        lock.withLock {
            var drained: [NativeSpeechInternalDiagnosticEvent] = []
            drained.reserveCapacity(eventCount)
            let firstIndex =
                (nextWriteIndex + capacity - eventCount) % capacity
            for offset in 0 ..< eventCount {
                let index = (firstIndex + offset) % capacity
                if let event = storage[index] {
                    drained.append(event)
                    storage[index] = nil
                }
            }
            let dropped = droppedEventCount
            nextWriteIndex = 0
            eventCount = 0
            droppedEventCount = 0
            return (drained, dropped)
        }
    }

    func clear() {
        lock.withLock {
            for index in storage.indices {
                storage[index] = nil
            }
            nextWriteIndex = 0
            eventCount = 0
            droppedEventCount = 0
            transportWriteDiagnostics.removeAll(keepingCapacity: true)
            #if DEBUG
            realtimeAudioCapsule = nil
            #endif
        }
    }
}
