import Foundation

actor FakeRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    enum Call: Sendable, Equatable {
        case connect(URL)
        case send(RealtimeWebSocketFrame)
        case receive
        case close(RealtimeWebSocketCloseReason)
    }

    enum ReceiveResult: Sendable, Equatable {
        case frame(RealtimeWebSocketFrame)
        case failure(NativeSpeechError)
    }

    private var receiveResults: [ReceiveResult]
    private var connectResults: [Result<Void, NativeSpeechError>]
    private let audioAppendError: NativeSpeechError?
    private let responseCancelDelay: Duration
    private let waitsWhenEmpty: Bool
    private var pendingReceive:
        CheckedContinuation<RealtimeWebSocketFrame, any Error>?
    private var activeReceiveCount = 0
    private(set) var calls: [Call] = []
    private(set) var capturedBearerToken: String?
    private(set) var maximumConcurrentReceiveCount = 0

    init(
        frames: [RealtimeWebSocketFrame] = [],
        audioAppendError: NativeSpeechError? = nil,
        responseCancelDelay: Duration = .zero,
        connectResults: [Result<Void, NativeSpeechError>] = [],
        receiveResults: [ReceiveResult] = [],
        waitsWhenEmpty: Bool = false
    ) {
        self.receiveResults = frames.map(ReceiveResult.frame)
            + receiveResults
        self.connectResults = connectResults
        self.audioAppendError = audioAppendError
        self.responseCancelDelay = responseCancelDelay
        self.waitsWhenEmpty = waitsWhenEmpty
    }

    func connect(endpoint: URL, bearerToken: String) async throws {
        calls.append(.connect(endpoint))
        capturedBearerToken = bearerToken
        if !connectResults.isEmpty {
            try connectResults.removeFirst().get()
        }
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        calls.append(.send(frame))
        if case .text(let text) = frame,
           text.contains("\"type\":\"response.cancel\"") {
            try await Task.sleep(for: responseCancelDelay)
        }
        if case .text(let text) = frame,
           text.contains("\"type\":\"input_audio_buffer.append\""),
           let audioAppendError {
            throw audioAppendError
        }
    }

    func receive() async throws -> RealtimeWebSocketFrame {
        calls.append(.receive)
        activeReceiveCount += 1
        maximumConcurrentReceiveCount = max(
            maximumConcurrentReceiveCount,
            activeReceiveCount
        )
        defer { activeReceiveCount -= 1 }
        if !receiveResults.isEmpty {
            return try receiveResults.removeFirst().get()
        }
        guard waitsWhenEmpty, pendingReceive == nil else {
            throw NativeSpeechError.transportFailure
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingReceive = continuation
        }
    }

    func close(reason: RealtimeWebSocketCloseReason) async {
        calls.append(.close(reason))
        pendingReceive?.resume(throwing: NativeSpeechError.cancelled)
        pendingReceive = nil
    }

    func enqueue(_ frame: RealtimeWebSocketFrame) {
        enqueue(.frame(frame))
    }

    func enqueueFailure(_ error: NativeSpeechError) {
        enqueue(.failure(error))
    }

    private func enqueue(_ result: ReceiveResult) {
        if let pendingReceive {
            self.pendingReceive = nil
            switch result {
            case .frame(let frame):
                pendingReceive.resume(returning: frame)
            case .failure(let error):
                pendingReceive.resume(throwing: error)
            }
        } else {
            receiveResults.append(result)
        }
    }
}

private extension FakeRealtimeWebSocketTransport.ReceiveResult {
    func get() throws -> RealtimeWebSocketFrame {
        switch self {
        case .frame(let frame):
            return frame
        case .failure(let error):
            throw error
        }
    }
}
