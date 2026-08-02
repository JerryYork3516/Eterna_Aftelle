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
