import Foundation

actor BoundedRealtimeWebSocketWriteWindow {
    typealias Submit = @Sendable (
        RealtimeWebSocketFrame,
        @escaping @Sendable (NativeSpeechError?) -> Void
    ) -> Void

    struct Snapshot: Sendable {
        let pendingWriteCount: Int
        let maximumPendingWriteCount: Int
        let submittedWriteCount: UInt64
        let completedWriteCount: UInt64
        let latchedError: NativeSpeechError?
    }

    private struct PendingWrite: Sendable {
        let category: String
        let byteCount: Int
        let startedAtNanoseconds: UInt64
    }

    private struct CapacityWaiter {
        let generation: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct DrainWaiter {
        let generation: UInt64
        let continuation: CheckedContinuation<NativeSpeechError?, Never>
    }

    private let capacity: Int
    private let diagnosticBuffer: NativeSpeechDiagnosticBuffer?
    private var generation: UInt64 = 0
    private var writeOrdinal: UInt64 = 0
    private var completedWriteCount: UInt64 = 0
    private var maximumPendingWriteCount = 0
    private var pendingWrites: [UInt64: PendingWrite] = [:]
    private var capacityWaiters: [CapacityWaiter] = []
    private var drainWaiters: [DrainWaiter] = []
    private var isAdmittingWaiter = false
    private var isClosing = false
    private var latchedError: NativeSpeechError?

    init(
        capacity: Int = 8,
        diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil
    ) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.diagnosticBuffer = diagnosticBuffer
    }

    func reset() {
        generation &+= 1
        resumeAllWaiters(throwing: NativeSpeechError.cancelled)
        resumeAllDrainWaiters(with: .cancelled)
        pendingWrites.removeAll(keepingCapacity: true)
        isAdmittingWaiter = false
        isClosing = false
        latchedError = nil
        writeOrdinal = 0
        completedWriteCount = 0
        maximumPendingWriteCount = 0
    }

    func enqueue(
        _ frame: RealtimeWebSocketFrame,
        submit: @escaping Submit
    ) async throws {
        let acceptedGeneration = generation
        try throwIfFailed()
        guard !isClosing else {
            throw NativeSpeechError.cancelled
        }

        if pendingWrites.count >= capacity
            || !capacityWaiters.isEmpty
            || isAdmittingWaiter {
            try await withCheckedThrowingContinuation {
                continuation in
                capacityWaiters.append(
                    CapacityWaiter(
                        generation: acceptedGeneration,
                        continuation: continuation
                    )
                )
            }
        }

        guard acceptedGeneration == generation else {
            throw NativeSpeechError.cancelled
        }
        try throwIfFailed()
        guard !isClosing else {
            throw NativeSpeechError.cancelled
        }
        isAdmittingWaiter = false

        writeOrdinal &+= 1
        let ordinal = writeOrdinal
        let category = Self.safeWriteCategory(frame)
        let byteCount = Self.frameByteCount(frame)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        pendingWrites[ordinal] = PendingWrite(
            category: category,
            byteCount: byteCount,
            startedAtNanoseconds: startedAt
        )
        maximumPendingWriteCount = max(
            maximumPendingWriteCount,
            pendingWrites.count
        )
        record(
            category: "write_submitted_\(category)",
            wireSequence: ordinal,
            byteCount: byteCount,
            pendingWriteCount: pendingWrites.count,
            nowNanoseconds: startedAt
        )

        submit(frame) { [weak self] error in
            Task {
                await self?.complete(
                    ordinal: ordinal,
                    generation: acceptedGeneration,
                    error: error
                )
            }
        }
        admitNextWaiterIfPossible()
    }

    func beginCloseAndDrain(
        timeoutNanoseconds: UInt64
    ) async -> NativeSpeechError? {
        precondition(timeoutNanoseconds > 0)
        if let latchedError {
            return latchedError
        }
        isClosing = true
        resumeAllWaiters(throwing: NativeSpeechError.cancelled)
        isAdmittingWaiter = false
        guard !pendingWrites.isEmpty else {
            record(category: "write_drain_completed", pendingWriteCount: 0)
            return nil
        }

        let drainGeneration = generation
        record(
            category: "write_drain_started",
            pendingWriteCount: pendingWrites.count
        )
        return await withCheckedContinuation { continuation in
            drainWaiters.append(
                DrainWaiter(
                    generation: drainGeneration,
                    continuation: continuation
                )
            )
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                await self?.timeOutDrain(generation: drainGeneration)
            }
        }
    }

    func close() {
        generation &+= 1
        resumeAllWaiters(throwing: NativeSpeechError.cancelled)
        resumeAllDrainWaiters(with: .cancelled)
        pendingWrites.removeAll(keepingCapacity: true)
        isAdmittingWaiter = false
        isClosing = true
        latchedError = .cancelled
    }

    func currentError() -> NativeSpeechError? {
        latchedError
    }

    func snapshot() -> Snapshot {
        Snapshot(
            pendingWriteCount: pendingWrites.count,
            maximumPendingWriteCount: maximumPendingWriteCount,
            submittedWriteCount: writeOrdinal,
            completedWriteCount: completedWriteCount,
            latchedError: latchedError
        )
    }

    private func complete(
        ordinal: UInt64,
        generation completedGeneration: UInt64,
        error: NativeSpeechError?
    ) {
        guard completedGeneration == generation,
              let pending = pendingWrites.removeValue(forKey: ordinal) else {
            return
        }
        let duration =
            (DispatchTime.now().uptimeNanoseconds
                &- pending.startedAtNanoseconds) / 1_000_000

        if let error {
            latchedError = error
            record(
                category: "write_failed_\(pending.category)",
                wireSequence: ordinal,
                byteCount: pending.byteCount,
                pendingWriteCount: pendingWrites.count,
                durationMilliseconds: duration,
                errorCode: Self.standardErrorName(error)
            )
            pendingWrites.removeAll(keepingCapacity: true)
            resumeAllWaiters(throwing: error)
            resumeAllDrainWaiters(with: error)
            isAdmittingWaiter = false
            return
        }

        completedWriteCount &+= 1
        record(
            category: "write_completed_\(pending.category)",
            wireSequence: ordinal,
            byteCount: pending.byteCount,
            pendingWriteCount: pendingWrites.count,
            durationMilliseconds: duration
        )
        if isClosing && pendingWrites.isEmpty {
            record(category: "write_drain_completed", pendingWriteCount: 0)
            resumeAllDrainWaiters(with: nil)
        }
        admitNextWaiterIfPossible()
    }

    private func admitNextWaiterIfPossible() {
        guard !isAdmittingWaiter,
              !isClosing,
              pendingWrites.count < capacity,
              !capacityWaiters.isEmpty,
              latchedError == nil else {
            return
        }
        let waiter = capacityWaiters.removeFirst()
        guard waiter.generation == generation else {
            waiter.continuation.resume(throwing: NativeSpeechError.cancelled)
            admitNextWaiterIfPossible()
            return
        }
        isAdmittingWaiter = true
        waiter.continuation.resume()
    }

    private func resumeAllWaiters(throwing error: NativeSpeechError) {
        let waiters = capacityWaiters
        capacityWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.continuation.resume(throwing: error)
        }
    }

    private func resumeAllDrainWaiters(with error: NativeSpeechError?) {
        let waiters = drainWaiters
        drainWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.continuation.resume(returning: error)
        }
    }

    private func timeOutDrain(generation timedOutGeneration: UInt64) {
        guard timedOutGeneration == generation,
              isClosing,
              !pendingWrites.isEmpty else {
            return
        }
        let matchingWaiters = drainWaiters.filter {
            $0.generation == timedOutGeneration
        }
        guard !matchingWaiters.isEmpty else { return }
        drainWaiters.removeAll {
            $0.generation == timedOutGeneration
        }
        record(
            category: "write_drain_timed_out",
            pendingWriteCount: pendingWrites.count,
            errorCode: "timed_out"
        )
        for waiter in matchingWaiters {
            waiter.continuation.resume(returning: .timedOut)
        }
    }

    private func throwIfFailed() throws {
        if let latchedError {
            throw latchedError
        }
    }

    private func record(
        category: String,
        wireSequence: UInt64? = nil,
        byteCount: Int? = nil,
        pendingWriteCount: Int? = nil,
        durationMilliseconds: UInt64? = nil,
        errorCode: String? = nil,
        nowNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        diagnosticBuffer?.append(
            NativeSpeechInternalDiagnosticEvent(
                source: .transport,
                category: category,
                wireSequence: wireSequence,
                byteCount: byteCount,
                pendingWriteCount: pendingWriteCount,
                durationMilliseconds: durationMilliseconds,
                errorCode: errorCode,
                monotonicTimestampNanoseconds: nowNanoseconds
            )
        )
    }

    private static func safeWriteCategory(
        _ frame: RealtimeWebSocketFrame
    ) -> String {
        guard case .text(let text) = frame,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let type = object["type"] as? String else {
            return "binary_or_unknown"
        }
        switch type {
        case "session.update": return "session_update"
        case "input_audio_buffer.append": return "audio_append"
        case "response.cancel": return "response_cancel"
        default: return "other"
        }
    }

    private static func frameByteCount(
        _ frame: RealtimeWebSocketFrame
    ) -> Int {
        switch frame {
        case .text(let text): text.utf8.count
        case .binary(let data): data.count
        }
    }

    private static func standardErrorName(
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
}

actor URLSessionRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    private static let maximumPendingWrites = 8
    private static let closeDrainTimeoutNanoseconds: UInt64 = 1_000_000_000
    private let diagnosticBuffer: NativeSpeechDiagnosticBuffer?
    private let writeWindow: BoundedRealtimeWebSocketWriteWindow
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var connectionGeneration: UInt64 = 0
    private var isConnecting = false
    private var isClosing = false

    init(diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil) {
        self.diagnosticBuffer = diagnosticBuffer
        writeWindow = BoundedRealtimeWebSocketWriteWindow(
            capacity: Self.maximumPendingWrites,
            diagnosticBuffer: diagnosticBuffer
        )
    }

    func connect(endpoint: URL, bearerToken: String) async throws {
        guard task == nil, !isConnecting, !isClosing else {
            throw NativeSpeechError.invalidConfiguration
        }
        isConnecting = true
        defer { isConnecting = false }
        connectionGeneration &+= 1
        let acceptedGeneration = connectionGeneration
        record(category: "websocket_connect_started")
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15

        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: request)
        await writeWindow.reset()
        guard acceptedGeneration == connectionGeneration,
              !isClosing,
              self.task == nil else {
            task.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            throw NativeSpeechError.cancelled
        }
        self.session = session
        self.task = task
        task.resume()
        record(category: "websocket_connect_submitted")
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        guard let task, !isClosing else {
            throw NativeSpeechError.transportFailure
        }
        try await writeWindow.enqueue(frame) { frame, completion in
            let message: URLSessionWebSocketTask.Message
            switch frame {
            case .text(let text): message = .string(text)
            case .binary(let data): message = .data(data)
            }
            task.send(message) { error in
                guard let error else {
                    completion(nil)
                    return
                }
                let mapped = Self.mappedError(for: task, fallback: error)
                task.cancel(with: .goingAway, reason: nil)
                completion(mapped)
            }
        }
    }

    func receive() async throws -> RealtimeWebSocketFrame {
        guard let task, !isClosing else {
            throw NativeSpeechError.transportFailure
        }
        let acceptedGeneration = connectionGeneration
        if let writeError = await writeWindow.currentError() {
            throw writeError
        }
        do {
            let message = try await task.receive()
            guard acceptedGeneration == connectionGeneration,
                  self.task === task,
                  !isClosing else {
                throw NativeSpeechError.cancelled
            }
            switch message {
            case .string(let text):
                return .text(text)
            case .data(let data):
                return .binary(data)
            @unknown default:
                throw NativeSpeechError.invalidEvent
            }
        } catch let error as NativeSpeechError {
            throw error
        } catch {
            guard acceptedGeneration == connectionGeneration,
                  self.task === task,
                  !isClosing else {
                throw NativeSpeechError.cancelled
            }
            if let writeError = await writeWindow.currentError() {
                throw writeError
            }
            throw Self.mappedError(for: task, fallback: error)
        }
    }

    func close(reason: RealtimeWebSocketCloseReason) async {
        if isConnecting, task == nil {
            connectionGeneration &+= 1
            return
        }
        guard let task, !isClosing else { return }
        isClosing = true
        connectionGeneration &+= 1
        let closingSession = session
        let drainError = await writeWindow.beginCloseAndDrain(
            timeoutNanoseconds: Self.closeDrainTimeoutNanoseconds
        )
        if let drainError {
            let category: String
            switch drainError {
            case .timedOut:
                category = "websocket_close_write_drain_timed_out"
            default:
                category = "websocket_close_write_drain_failed"
            }
            record(category: category)
        }
        let closeCode: URLSessionWebSocketTask.CloseCode =
            reason == .normal ? .normalClosure : .goingAway
        task.cancel(with: closeCode, reason: nil)
        await writeWindow.close()
        if self.task === task {
            self.task = nil
            session = nil
        }
        isClosing = false
        if reason == .normal {
            closingSession?.finishTasksAndInvalidate()
        } else {
            closingSession?.invalidateAndCancel()
        }
        record(category: "websocket_closed")
    }

    private nonisolated static func mappedError(
        for task: URLSessionWebSocketTask,
        fallback: Error
    ) -> NativeSpeechError {
        if let response = task.response as? HTTPURLResponse {
            switch response.statusCode {
            case 401, 403:
                return .unauthorized
            case 429:
                return .rateLimited
            case 500...599:
                return .unavailable
            default:
                break
            }
        }
        if (fallback as NSError).code == NSURLErrorTimedOut {
            return .timedOut
        }
        return .transportFailure
    }

    private func record(
        category: String,
        wireSequence: UInt64? = nil,
        byteCount: Int? = nil,
        pendingWriteCount: Int? = nil,
        durationMilliseconds: UInt64? = nil,
        errorCode: String? = nil,
        nowNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        diagnosticBuffer?.append(
            NativeSpeechInternalDiagnosticEvent(
                source: .transport,
                category: category,
                wireSequence: wireSequence,
                byteCount: byteCount,
                pendingWriteCount: pendingWriteCount,
                durationMilliseconds: durationMilliseconds,
                errorCode: errorCode,
                monotonicTimestampNanoseconds: nowNanoseconds
            )
        )
    }

}
