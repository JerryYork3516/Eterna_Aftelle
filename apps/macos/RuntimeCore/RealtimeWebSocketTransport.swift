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

nonisolated struct NativeSpeechInternalDiagnosticEvent: Sendable {
    let timestamp: Date
    let monotonicTimestampNanoseconds: UInt64
    let source: NativeSpeechInternalDiagnosticSource
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
    let arrivalIntervalMilliseconds: UInt64?
    let wireToStandardDurationMilliseconds: UInt64?
    let pendingWriteCount: Int?
    let durationMilliseconds: UInt64?
    let errorCode: String?

    init(
        source: NativeSpeechInternalDiagnosticSource,
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
        arrivalIntervalMilliseconds: UInt64? = nil,
        wireToStandardDurationMilliseconds: UInt64? = nil,
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
        self.pendingWriteCount = pendingWriteCount
        self.durationMilliseconds = durationMilliseconds
        self.errorCode = errorCode
    }
}

nonisolated final class NativeSpeechDiagnosticBuffer: @unchecked Sendable {
    private static let capacity = 30_000
    private let lock = NSLock()
    private var events: [NativeSpeechInternalDiagnosticEvent] = []
    private var droppedEventCount: UInt64 = 0

    func append(_ event: NativeSpeechInternalDiagnosticEvent) {
        lock.withLock {
            if events.count == Self.capacity {
                events.removeFirst()
                droppedEventCount &+= 1
            }
            events.append(event)
        }
    }

    func drain() -> (
        events: [NativeSpeechInternalDiagnosticEvent],
        droppedEventCount: UInt64
    ) {
        lock.withLock {
            let drained = events
            let dropped = droppedEventCount
            events.removeAll(keepingCapacity: true)
            droppedEventCount = 0
            return (drained, dropped)
        }
    }

    func clear() {
        lock.withLock {
            events.removeAll(keepingCapacity: true)
            droppedEventCount = 0
        }
    }
}
