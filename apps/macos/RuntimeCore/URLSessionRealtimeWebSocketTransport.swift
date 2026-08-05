import Foundation

actor URLSessionRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    private let diagnosticBuffer: NativeSpeechDiagnosticBuffer?
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var writeOrdinal: UInt64 = 0
    private var pendingWriteCount = 0

    init(diagnosticBuffer: NativeSpeechDiagnosticBuffer? = nil) {
        self.diagnosticBuffer = diagnosticBuffer
    }

    func connect(endpoint: URL, bearerToken: String) async throws {
        guard task == nil else {
            throw NativeSpeechError.invalidConfiguration
        }
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
        self.session = session
        self.task = task
        task.resume()
        record(category: "websocket_connect_submitted")
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        guard let task else {
            throw NativeSpeechError.transportFailure
        }
        writeOrdinal &+= 1
        let ordinal = writeOrdinal
        pendingWriteCount += 1
        let startedAt = DispatchTime.now().uptimeNanoseconds
        record(
            category: "write_submitted_\(safeWriteCategory(frame))",
            wireSequence: ordinal,
            byteCount: frameByteCount(frame),
            pendingWriteCount: pendingWriteCount,
            nowNanoseconds: startedAt
        )
        do {
            switch frame {
            case .text(let text):
                try await task.send(.string(text))
            case .binary(let data):
                try await task.send(.data(data))
            }
            pendingWriteCount -= 1
            record(
                category: "write_completed_\(safeWriteCategory(frame))",
                wireSequence: ordinal,
                byteCount: frameByteCount(frame),
                pendingWriteCount: pendingWriteCount,
                durationMilliseconds:
                    (DispatchTime.now().uptimeNanoseconds &- startedAt)
                        / 1_000_000
            )
        } catch {
            pendingWriteCount -= 1
            let mapped = mappedError(for: task, fallback: error)
            record(
                category: "write_failed_\(safeWriteCategory(frame))",
                wireSequence: ordinal,
                byteCount: frameByteCount(frame),
                pendingWriteCount: pendingWriteCount,
                durationMilliseconds:
                    (DispatchTime.now().uptimeNanoseconds &- startedAt)
                        / 1_000_000,
                errorCode: Self.standardErrorName(mapped)
            )
            throw mapped
        }
    }

    func receive() async throws -> RealtimeWebSocketFrame {
        guard let task else {
            throw NativeSpeechError.transportFailure
        }
        do {
            switch try await task.receive() {
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
            throw mappedError(for: task, fallback: error)
        }
    }

    func close(reason: RealtimeWebSocketCloseReason) async {
        guard let task else { return }
        self.task = nil
        let closeCode: URLSessionWebSocketTask.CloseCode =
            reason == .normal ? .normalClosure : .goingAway
        task.cancel(with: closeCode, reason: nil)
        session?.invalidateAndCancel()
        session = nil
        pendingWriteCount = 0
        record(category: "websocket_closed")
    }

    private func mappedError(
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

    private func safeWriteCategory(
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

    private func frameByteCount(_ frame: RealtimeWebSocketFrame) -> Int {
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
