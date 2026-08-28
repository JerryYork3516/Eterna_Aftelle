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
    let byteCount: Int?
    let arrivalIntervalMilliseconds: UInt64?
    let wireToStandardDurationMilliseconds: UInt64?
    let writeWindowCapacity: Int?
    let pendingWriteCount: Int?
    let durationMilliseconds: UInt64?
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
        byteCount: Int? = nil,
        arrivalIntervalMilliseconds: UInt64? = nil,
        wireToStandardDurationMilliseconds: UInt64? = nil,
        writeWindowCapacity: Int? = nil,
        pendingWriteCount: Int? = nil,
        durationMilliseconds: UInt64? = nil,
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
        self.byteCount = byteCount
        self.arrivalIntervalMilliseconds = arrivalIntervalMilliseconds
        self.wireToStandardDurationMilliseconds =
            wireToStandardDurationMilliseconds
        self.writeWindowCapacity = writeWindowCapacity
        self.pendingWriteCount = pendingWriteCount
        self.durationMilliseconds = durationMilliseconds
        self.errorCode = errorCode
    }
}

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
        }
    }
}
