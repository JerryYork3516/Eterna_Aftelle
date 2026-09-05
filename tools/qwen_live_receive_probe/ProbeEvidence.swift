import Foundation

nonisolated struct ProbeWireRecord: Codable, Sendable {
    let sequence: Int
    let adapterSequence: Int?
    let elapsedNanoseconds: UInt64
    let sentCount: Int
    let binary: Bool
    let replayFrame: String
}

// Private test artifacts only. No original transcripts, credentials or PCM are retained.
actor ProbeTransport: RealtimeWebSocketTransport {
    private let underlying: (any RealtimeWebSocketTransport)?
    private let replay: [ProbeWireRecord]?
    private let file: FileHandle
    private let diagnostics: NativeSpeechDiagnosticBuffer?
    private var replayOrigin: UInt64 = 0
    private var receiveCount = 0
    private var sentCount = 0
    private var closed = false
    private var aliases: [String: String] = [:]
    private(set) var activeResponse = false
    private(set) var responseCreates = 0
    private(set) var responseCancels = 0
    private(set) var inputClears = 0
    private(set) var audioAppends = 0
    private var overlap = false
    private(set) var overlapAppendsWhileActive = 0
    private(set) var overlapStartsWhileActive = 0

    func beginOverlap() { overlap = true }

    init(underlying: (any RealtimeWebSocketTransport)?, replay: [ProbeWireRecord]? = nil, output: URL,
         diagnostics: NativeSpeechDiagnosticBuffer? = nil) throws {
        self.underlying = underlying
        self.replay = replay
        self.diagnostics = diagnostics
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw ProbeError.evidenceWrite
        }
        file = try FileHandle(forWritingTo: output)
    }

    func connect(endpoint: URL, bearerToken: String) async throws {
        replayOrigin = DispatchTime.now().uptimeNanoseconds
        diagnostics?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter, category: "probe_startup", routeKind: .realtimeBrain, disposition: "transport_connect_begin"
        ))
        if let underlying { try await underlying.connect(endpoint: endpoint, bearerToken: bearerToken) }
        diagnostics?.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter, category: "probe_startup", routeKind: .realtimeBrain, disposition: "transport_connect_returned"
        ))
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        sentCount += 1
        switch Self.object(frame)?["type"] as? String {
        case "response.create": responseCreates += 1
        case "response.cancel": responseCancels += 1
        case "input_audio_buffer.clear": inputClears += 1
        case "input_audio_buffer.append":
            audioAppends += 1
            if overlap, activeResponse { overlapAppendsWhileActive += 1 }
        default: break
        }
        if let underlying { try await underlying.send(frame) }
    }

    func receive() async throws -> RealtimeWebSocketFrame {
        let frame: RealtimeWebSocketFrame
        if let underlying {
            frame = try await underlying.receive()
        } else if let replay {
            while !closed {
                try Task.checkCancellation()
                if receiveCount < replay.count {
                    let record = replay[receiveCount]
                    if sentCount >= record.sentCount,
                       DispatchTime.now().uptimeNanoseconds - replayOrigin >= record.elapsedNanoseconds {
                        break
                    }
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard !closed, receiveCount < replay.count else { throw NativeSpeechError.cancelled }
            let record = replay[receiveCount]
            frame = record.binary ? .binary(Data(record.replayFrame.utf8)) : .text(record.replayFrame)
        } else { throw NativeSpeechError.transportFailure }
        receiveCount += 1
        let object = Self.object(frame)
        if object?["type"] as? String == "response.created" { activeResponse = true }
        if object?["type"] as? String == "response.done" { activeResponse = false }
        if overlap, activeResponse, object?["type"] as? String == "input_audio_buffer.speech_started" {
            overlapStartsWhileActive += 1
        }
        let sanitized = try sanitizedFrame(frame)
        let record = ProbeWireRecord(
            sequence: receiveCount,
            adapterSequence: receiveCount > 2 ? receiveCount - 2 : nil,
            elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - replayOrigin,
            sentCount: sentCount,
            binary: { if case .binary = frame { return true }; return false }(),
            replayFrame: sanitized
        )
        var encoded = try JSONEncoder().encode(record)
        encoded.append(0x0A)
        try file.write(contentsOf: encoded)
        return frame
    }

    func close(reason: RealtimeWebSocketCloseReason) async {
        closed = true
        if let underlying { await underlying.close(reason: reason) }
        do { try file.synchronize() }
        catch { print("probe_evidence_sync=FAILED") }
    }

    private static func object(_ frame: RealtimeWebSocketFrame) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: bytes(frame))) as? [String: Any]
    }

    private static func bytes(_ frame: RealtimeWebSocketFrame) -> Data {
        switch frame { case .text(let value): Data(value.utf8); case .binary(let value): value }
    }

    func sanitizedFrame(_ frame: RealtimeWebSocketFrame) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Self.bytes(frame), options: [.fragmentsAllowed]) else {
            return "{" // Preserve malformed-JSON rejection without keeping the offending payload.
        }
        let value = sanitize(object, key: "", eventType: "", depth: 0)
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    private func sanitize(_ value: Any, key: String, eventType: String, depth: Int) -> Any {
        guard depth < 12 else { return NSNull() }
        if let object = value as? [String: Any] {
            let type = object["type"] as? String ?? eventType
            let allowed = Set(["type", "item_id", "response_id", "response", "id", "status", "session",
                "turn_detection", "threshold", "silence_duration_ms", "create_response", "interrupt_response",
                "text", "stash", "transcript", "delta", "arguments", "name", "call_id", "output", "content",
                "audio_start_ms", "audio_end_ms", "item", "role", "previous_item_id", "content_index"])
            return object.reduce(into: [String: Any]()) { result, entry in
                if allowed.contains(entry.key) {
                    result[entry.key] = sanitize(entry.value, key: entry.key, eventType: type, depth: depth + 1)
                }
            }
        }
        if let array = value as? [Any] {
            return array.prefix(256).map { sanitize($0, key: key, eventType: eventType, depth: depth + 1) }
        }
        guard let string = value as? String else { return value }
        if string.isEmpty { return string }
        switch key {
        case "type", "status", "role":
            let allowed = Set(["session.created", "session.updated", "input_audio_buffer.cleared",
                "input_audio_buffer.committed", "conversation.item.created", "response.output_item.added", "response.output_item.done",
                "input_audio_buffer.speech_started", "input_audio_buffer.speech_stopped",
                "conversation.item.input_audio_transcription.delta", "conversation.item.input_audio_transcription.completed",
                "conversation.item.input_audio_transcription.failed", "response.created", "response.done",
                "response.audio.delta", "response.audio.done", "response.text.delta", "response.text.done",
                "response.audio_transcript.delta", "response.audio_transcript.done", "response.function_call_arguments.done",
                "error", "semantic_vad", "server_vad", "completed", "cancelled", "incomplete", "failed", "in_progress",
                "message", "text", "audio", "input_audio", "user", "assistant", "system", "tool"])
            return allowed.contains(string) ? string : "unknown"
        case "id", "item_id", "response_id", "call_id", "previous_item_id":
            if aliases[string] == nil { aliases[string] = "id_\(aliases.count + 1)" }
            return aliases[string]!
        case "delta" where eventType == "response.audio.delta":
            return Data(base64Encoded: string) == nil ? "!" : "AAA="
        case "arguments":
            guard let object = try? JSONSerialization.jsonObject(with: Data(string.utf8), options: [.fragmentsAllowed]) else { return "{" }
            return JSONSerialization.isValidJSONObject(object) ? "{}" : "1"
        default: return "redacted substantive fixture"
        }
    }
}
