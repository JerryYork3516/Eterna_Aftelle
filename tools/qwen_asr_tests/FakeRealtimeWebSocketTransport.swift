import Foundation

actor QwenASRFakeRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    enum Call: Sendable, Equatable {
        case connect(URL)
        case send(RealtimeWebSocketFrame)
        case receive
        case close(RealtimeWebSocketCloseReason)
    }

    private var frames: [RealtimeWebSocketFrame]
    private(set) var calls: [Call] = []
    private(set) var bearerToken: String?

    init(frames: [RealtimeWebSocketFrame]) {
        self.frames = frames
    }

    func connect(endpoint: URL, bearerToken: String) async throws {
        calls.append(.connect(endpoint))
        self.bearerToken = bearerToken
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        calls.append(.send(frame))
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
}
