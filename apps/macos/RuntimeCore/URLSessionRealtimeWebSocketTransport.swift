import Foundation

actor URLSessionRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    func connect(endpoint: URL, bearerToken: String) async throws {
        guard task == nil else {
            throw NativeSpeechError.invalidConfiguration
        }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20

        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        guard let task else {
            throw NativeSpeechError.transportFailure
        }
        do {
            switch frame {
            case .text(let text):
                try await task.send(.string(text))
            case .binary(let data):
                try await task.send(.data(data))
            }
        } catch {
            throw mappedError(for: task, fallback: error)
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
}
