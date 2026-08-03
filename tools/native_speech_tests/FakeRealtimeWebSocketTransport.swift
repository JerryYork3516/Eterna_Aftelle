import Foundation

actor FakeRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    enum Call: Sendable, Equatable {
        case connect(URL)
        case send(RealtimeWebSocketFrame)
        case receive
        case close(RealtimeWebSocketCloseReason)
    }

    private var frames: [RealtimeWebSocketFrame]
    private let audioAppendError: NativeSpeechError?
    private(set) var calls: [Call] = []
    private(set) var capturedBearerToken: String?

    init(
        frames: [RealtimeWebSocketFrame] = [],
        audioAppendError: NativeSpeechError? = nil
    ) {
        self.frames = frames
        self.audioAppendError = audioAppendError
    }

    func connect(endpoint: URL, bearerToken: String) async throws {
        calls.append(.connect(endpoint))
        capturedBearerToken = bearerToken
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        calls.append(.send(frame))
        if case .text(let text) = frame,
           text.contains("\"type\":\"input_audio_buffer.append\""),
           let audioAppendError {
            throw audioAppendError
        }
    }

    func receive() async throws -> RealtimeWebSocketFrame {
        calls.append(.receive)
        guard !frames.isEmpty else {
            throw NativeSpeechError.transportFailure
        }
        return frames.removeFirst()
    }

    func close(reason: RealtimeWebSocketCloseReason) async {
        calls.append(.close(reason))
    }

    func enqueue(_ frame: RealtimeWebSocketFrame) {
        frames.append(frame)
    }
}
