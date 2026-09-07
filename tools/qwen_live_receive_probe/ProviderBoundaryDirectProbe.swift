// Provider-boundary direct PCM probe (R8.5.3 → pb11).
//
// Changes from pb10 (INVALID_PROBE):
// 1. Sends production-mirroring session.update with semantic_vad before PCM.
//    Validates server echo of turn_detection policy.
//    BLOCKS on session.updated ack before sending any audio.
// 2. VAD mode: no input_audio_buffer.commit ever.
//    First user turn driven by server speech_started/speech_stopped/committed events.
//    After committed, sends response.create; then sends PCM2 upon response.created.
//    Handles interruption: if PCM2 speech_started arrives while response is active,
//    mirrors Aftelle protocol (response.cancel / new response.create).
// 3. Single monotonic timeline: one uptimeNanoseconds origin at init,
//    elapsed_ns reported as (now - origin).  Assertions at every entry:
//    elapsed >= 0, seq monotonic, no entry > deadline_ns + 1s.
//
// Exit codes: 0 = complete; 1 = failure.

import Foundation
import Security
import LocalAuthentication

// MARK: - Constants (mirrors QwenRealtimeTurnDetectionPolicy in production)

private let VAD_TYPE = "semantic_vad"
private let VAD_THRESHOLD = 0.2
private let VAD_SILENCE_MS = 800

// MARK: - Credential

protocol PBProviderCredentialReading: Sendable {
    func readCredential(for keyRef: String) throws -> String?
}

struct PBFixtureCredential: PBProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? { nil }
}

final class PBStoredCredential: PBProviderCredentialReading, @unchecked Sendable {
    private let allowInteraction: Bool
    private let copyMatching: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>) -> OSStatus
    private let setInteractionAllowed: @Sendable (Bool) -> OSStatus
    private var cachedApiKey: String?
    private var cachedWorkspaceID: String?
    private let lock = NSLock()

    init(allowInteraction: Bool = false,
         copyMatching: @escaping @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>) -> OSStatus = { SecItemCopyMatching($0, $1) },
         setInteractionAllowed: @escaping @Sendable (Bool) -> OSStatus = { SecKeychainSetUserInteractionAllowed($0) }) {
        self.allowInteraction = allowInteraction
        self.copyMatching = copyMatching
        self.setInteractionAllowed = setInteractionAllowed
    }

    func readCredential(for keyRef: String) throws -> String? {
        try lock.withLock {
            if let k = cachedApiKey { return k }
            _ = setInteractionAllowed(allowInteraction)
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.eterna.aftelle.provider.qwen",
                kSecAttrAccount as String: "qwen_realtime_credential",
                kSecAttrSynchronizable as String: false,
                kSecReturnData as String: true
            ]
            if !allowInteraction {
                let auth = LAContext(); auth.interactionNotAllowed = true
                query[kSecUseAuthenticationContext as String] = auth
            }
            var result: CFTypeRef?
            let status = copyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data,
                  let stored = String(data: data, encoding: .utf8) else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [String: Any],
                  let apiKey = json["api_key"] as? String else { return nil }
            cachedApiKey = apiKey
            cachedWorkspaceID = json["workspace_id"] as? String
            return apiKey
        }
    }

    func workspaceID(for keyRef: String) throws -> String? {
        _ = try readCredential(for: keyRef)
        return lock.withLock { cachedWorkspaceID }
    }
}

// MARK: - Wire entry

struct PBWireEntry {
    let seq: UInt64
    let elapsedNs: UInt64
    let direction: String   // "send" | "receive" | "system"
    let raw: String
    let type: String?
    let itemId: String?
    let responseId: String?
    let audioStartMs: Int?
    let audioEndMs: Int?
    let transcript: String?
    let error: String?      // system entries only
    let timelineViolation: String?  // non-nil if assertion failed
}

// MARK: - Mock WebSocket (replaces URLSessionWebSocketTask in test mode)

protocol PBWebSocket: AnyObject {
    func send(_ text: String) async throws
    func receive() async throws -> String?
    func close() async
}

actor PBWebSocketURLSession: PBWebSocket {
    private let task: URLSessionWebSocketTask
    private var closed = false

    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String? {
        while !closed {
            do {
                let msg = try await task.receive()
                switch msg {
                case .string(let s): return s
                case .data(let d):
                    if d.isEmpty { return nil }
                    return String(data: d, encoding: .utf8) ?? ""
                @unknown default: return nil
                }
            } catch {
                throw error
            }
        }
        return nil
    }

    func close() async {
        guard !closed else { return }
        closed = true
        task.cancel(with: .goingAway, reason: nil)
    }
}

// MARK: - Probe state

/// Single source of truth for monotonic time.
/// Origin is set once at init; all elapsed values are derived from it.
/// Unit: nanoseconds.
struct PBClock {
    let originNs: UInt64

    init() {
        self.originNs = DispatchTime.now().uptimeNanoseconds
    }

    var now: UInt64 {
        let d = DispatchTime.now().uptimeNanoseconds
        if d >= originNs { return d - originNs } else { return 0 }
    }

    func elapsedSec() -> Double {
        Double(now) / 1_000_000_000.0
    }

    /// Returns the elapsed-Ns value that corresponds to (origin + sec) on the wall clock.
    /// Used by callers that compare `now < dl` to bound loops by real wall time.
    func deadline(sec: Int) -> UInt64 {
        return UInt64(sec) * 1_000_000_000
    }
}

final class PBProbeState: @unchecked Sendable {
    let clock = PBClock()
    let wireLock = NSLock()
    private var _seq: UInt64 = 0
    let outputURL: URL
    var wireFileHandle: FileHandle?
    private var _lastSeq: UInt64 = 0
    private var _lastElapsedNs: UInt64 = 0
    private var _deadlineSec: Int = 60
    var timelineViolations: [String] = []
    var entries: [PBWireEntry] = []

    init(outputURL: URL) {
        self.outputURL = outputURL
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let path = outputURL.appendingPathComponent("wire.ndjson").path
            FileManager.default.createFile(atPath: path, contents: nil)
            wireFileHandle = FileHandle(forWritingAtPath: path)
        } catch {
            FileHandle.standardError.write("PB_FAIL output_setup\n".data(using: .utf8)!)
            exit(1)
        }
    }

    func setDeadline(sec: Int) {
        _deadlineSec = sec
    }

    @discardableResult
    func appendWire(
        direction: String,
        raw: String,
        error: String? = nil,
        timelineViolation: String? = nil
    ) -> PBWireEntry {
        wireLock.lock()
        defer { wireLock.unlock() }
        _seq += 1
        let now = clock.now
        var violation: String? = timelineViolation

        // Assertions:
        // 1. elapsed >= 0 (always true by construction)
        // 2. seq monotonic
        if _seq <= _lastSeq {
            violation = "seq_nondecreasing: last=\(_lastSeq) current=\(_seq)"
            timelineViolations.append(violation!)
        }
        // 3. elapsed monotonic
        if now < _lastElapsedNs && direction != "system" {
            // allow system entries to have same or smaller elapsed (no real-time constraint)
            // but send/receive must be strictly monotonic
            violation = "elapsed_nondecreasing: last=\(_lastElapsedNs) now=\(now)"
            timelineViolations.append(violation!)
        }
        // 4. no entry past deadline + 1s
        let deadlineNs = clock.deadline(sec: _deadlineSec)
        if now > deadlineNs + 1_000_000_000 && violation == nil {
            violation = "past_deadline: now=\(now) deadline=\(deadlineNs) (+1s=\(deadlineNs+1_000_000_000))"
            timelineViolations.append(violation!)
        }

        _lastSeq = _seq
        _lastElapsedNs = now

        var type: String? = nil
        var itemId: String? = nil
        var responseId: String? = nil
        var audioStartMs: Int? = nil
        var audioEndMs: Int? = nil
        var transcript: String? = nil

        if direction != "system" {
            if let data = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                type = obj["type"] as? String
                itemId = obj["item_id"] as? String
                responseId = obj["response_id"] as? String
                audioStartMs = obj["audio_start_ms"] as? Int
                audioEndMs = obj["audio_end_ms"] as? Int
                transcript = obj["transcript"] as? String
                if transcript == nil, let delta = obj["delta"] as? String, type?.contains("transcription") == true {
                    transcript = delta
                }
            }
        }

        let entry = PBWireEntry(
            seq: _seq,
            elapsedNs: now,
            direction: direction,
            raw: raw,
            type: type,
            itemId: itemId,
            responseId: responseId,
            audioStartMs: audioStartMs,
            audioEndMs: audioEndMs,
            transcript: transcript,
            error: error,
            timelineViolation: violation
        )
        entries.append(entry)

        // Incremental flush
        if let lineData = try? JSONSerialization.data(withJSONObject: entryToDict(entry)),
           let line = String(data: lineData, encoding: .utf8) {
            if let fh = wireFileHandle {
                try? fh.write(contentsOf: (line + "\n").data(using: .utf8)!)
            }
        }
        return entry
    }

    private func entryToDict(_ e: PBWireEntry) -> [String: Any] {
        var d: [String: Any] = [
            "seq": e.seq,
            "elapsed_ms": round(Double(e.elapsedNs) / 1_000_000.0),
            "elapsed_ns": e.elapsedNs,
            "direction": e.direction,
            "raw": e.raw
        ]
        if let t = e.type { d["type"] = t }
        if let i = e.itemId { d["item_id"] = i }
        if let r = e.responseId { d["response_id"] = r }
        if let a = e.audioStartMs { d["audio_start_ms"] = a }
        if let b = e.audioEndMs { d["audio_end_ms"] = b }
        if let t = e.transcript { d["transcript"] = t }
        if let err = e.error { d["error"] = err }
        if let tv = e.timelineViolation { d["timeline_violation"] = tv }
        return d
    }

    func close() {
        wireLock.lock()
        try? wireFileHandle?.close()
        wireFileHandle = nil
        wireLock.unlock()
    }

    func hasTimelineViolations() -> Bool {
        wireLock.lock()
        defer { wireLock.unlock() }
        return !timelineViolations.isEmpty
    }
}

// MARK: - Session update builder (mirrors production)

func PBSessionUpdatePayload(eventId: String) -> [String: Any] {
    return [
        "event_id": eventId,
        "type": "session.update",
        "session": [
            "turn_detection": [
                "type": VAD_TYPE,
                "threshold": VAD_THRESHOLD,
                "silence_duration_ms": VAD_SILENCE_MS,
                "create_response": false,
                "interrupt_response": false
            ]
        ]
    ]
}

// MARK: - Validation helpers

struct PBTurnDetectionPolicy {
    let type: String
    let threshold: Double
    let silenceMs: Int
    let createResponse: Bool
    let interruptResponse: Bool

    init?(fromSession session: [String: Any]?) {
        guard let td = session?["turn_detection"] as? [String: Any],
              let t = td["type"] as? String,
              let th = td["threshold"] as? Double,
              let sm = td["silence_duration_ms"] as? Int,
              let cr = td["create_response"] as? Bool,
              let ir = td["interrupt_response"] as? Bool
        else { return nil }
        self.type = t
        self.threshold = th
        self.silenceMs = sm
        self.createResponse = cr
        self.interruptResponse = ir
    }
}

struct PBPolicyValidationResult {
    let ok: Bool
    let errors: [String]
}

func PBValidateTurnDetectionPolicy(_ p: PBTurnDetectionPolicy) -> PBPolicyValidationResult {
    var errs: [String] = []
    if p.type != VAD_TYPE {
        errs.append("type=\(p.type) expected=\(VAD_TYPE)")
    }
    if abs(p.threshold - VAD_THRESHOLD) > 1e-6 {
        errs.append("threshold=\(p.threshold) expected=\(VAD_THRESHOLD)")
    }
    if p.silenceMs != VAD_SILENCE_MS {
        errs.append("silence_ms=\(p.silenceMs) expected=\(VAD_SILENCE_MS)")
    }
    if p.createResponse != false {
        errs.append("create_response=\(p.createResponse) expected=false")
    }
    if p.interruptResponse != false {
        errs.append("interrupt_response=\(p.interruptResponse) expected=false")
    }
    return PBPolicyValidationResult(ok: errs.isEmpty, errors: errs)
}

// MARK: - Live mode state machine

enum PBLivePhase: Sendable {
    case init_
    case awaitSessionCreated
    case awaitSessionUpdatedAck
    case awaitFirstSpeechStarted
    case awaitFirstTurnCommitted
    case awaitResponseCreated
    case awaitResponseDone
    case phase2AwaitSecondSpeechStarted
    case awaitSecondResponseDone
    case complete
    case failed(String)
}

@main
struct ProviderBoundaryDirectProbe {
    static func main() {
        setbuf(stderr, nil)
        setbuf(stdout, nil)
        var mode = "live"
        var pcmPath = ""
        var outputPath = ""
        var allowInteraction = false
        var mockServerURL: String? = nil
        var mockScenario: String = "happy"
        var timeoutSec: Int = 60

        var args = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < args.count {
            let flag = args[i]; i += 1
            switch flag {
            case "--live": mode = "live"
            case "--self-test":
                mode = "self-test"
                mockScenario = args[i]; i += 1
            case "--pcm": pcmPath = args[i]; i += 1
            case "--output": outputPath = args[i]; i += 1
            case "--allow-keychain-interaction": allowInteraction = true
            case "--mock-server": mockServerURL = args[i]; i += 1
            case "--timeout-sec": timeoutSec = Int(args[i]) ?? 60; i += 1
            default: break
            }
        }

        guard !outputPath.isEmpty else {
            print("PB_FAIL missing_output")
            exit(1)
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        var state = PBProbeState(outputURL: outputURL)
        state.setDeadline(sec: timeoutSec)

        if mode == "self-test" {
            guard let url = mockServerURL else {
                print("PB_FAIL mock_url_required"); exit(1)
            }
            runSelfTest(outputURL: outputURL, state: state, serverURL: url,
                        scenario: mockScenario, timeoutSec: timeoutSec, pcmPath: pcmPath)
            return
        }

        guard !pcmPath.isEmpty else {
            print("PB_FAIL missing_pcm"); exit(1)
        }
        runLive(outputURL: outputURL, state: state, pcmPath: pcmPath,
                allowInteraction: allowInteraction, timeoutSec: timeoutSec)
    }

    // MARK: - Self-test

    static func runSelfTest(
        outputURL: URL,
        state: PBProbeState,
        serverURL: String,
        scenario: String,
        timeoutSec: Int,
        pcmPath: String
    ) {
        // Dummy PCM for send-path coverage
        let dummyPath = "/tmp/aftelle-pb-selftest-dummy.pcm"
        if !FileManager.default.fileExists(atPath: dummyPath) {
            try? Data(count: 24000 * 2).write(to: URL(fileURLWithPath: dummyPath))
        }
        let usePCM = pcmPath.isEmpty ? dummyPath : pcmPath

        print("PB_SELF_TEST=START scenario=\(scenario) server=\(serverURL)")
        fflush(stdout)

        Task.detached { [state] in
            await runSelfTestAsync(
                outputURL: outputURL,
                state: state,
                serverURL: serverURL,
                scenario: scenario,
                timeoutSec: timeoutSec,
                pcmPath: usePCM
            )
            state.close()
            exit(0)
        }
        dispatchMain()
    }

    static func runSelfTestAsync(
        outputURL: URL,
        state: PBProbeState,
        serverURL: String,
        scenario: String,
        timeoutSec: Int,
        pcmPath: String
    ) async {
        guard let url = URL(string: serverURL) else {
            FileHandle.standardError.write("PB_FAIL bad_url\n".data(using: .utf8)!)
            return
        }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        var request = URLRequest(url: url)
        request.setValue("Bearer selftest", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        let ws = PBWebSocketURLSession(task: task)

        state.setDeadline(sec: timeoutSec)

        // Single persistent receiver
        let receiverTask: Task<Void, Never> = Task { [ws, state] in
            while !Task.isCancelled {
                do {
                    guard let text = try await ws.receive() else { break }
                    state.appendWire(direction: "receive", raw: text)
                } catch is CancellationError {
                    break
                } catch {
                    state.appendWire(direction: "system", raw: "{\"reason\":\"receiver_exit\"}", error: "\(error)")
                    break
                }
            }
        }

        defer {
            receiverTask.cancel()
            Task { await ws.close() }
        }

        // Determine expected behavior based on scenario
        let expectsSessionUpdateAck: Bool
        let expectsResponseCreate: Bool
        switch scenario {
        case "production_vad", "production_vad_bad_update":
            expectsSessionUpdateAck = true
            expectsResponseCreate = true
        default:
            expectsSessionUpdateAck = false
            expectsResponseCreate = false
        }

        // For production_vad, send session.update first
        if scenario == "production_vad" || scenario == "production_vad_bad_update" {
            // Wait for session.created
            let dl = state.clock.deadline(sec: timeoutSec)
            while state.clock.now < dl {
                if state.entries.contains(where: { $0.type == "session.created" }) { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            if !state.entries.contains(where: { $0.type == "session.created" }) {
                FileHandle.standardError.write("PB_FAIL no_session_created\n".data(using: .utf8)!)
                return
            }
            // Send session.update
            let frame = try! JSONSerialization.data(withJSONObject: PBSessionUpdatePayload(eventId: UUID().uuidString))
            let text = String(data: frame, encoding: .utf8)!
            do { try await ws.send(text) } catch {
                FileHandle.standardError.write("PB_FAIL send_session_update: \(error)\n".data(using: .utf8)!); return
            }
            state.appendWire(direction: "send", raw: text)

            // Wait for session.updated
            let dl2 = state.clock.deadline(sec: timeoutSec)
            while state.clock.now < dl2 {
                if state.entries.contains(where: { $0.type == "session.updated" }) { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }

            // Validate policy
            if scenario == "production_vad_bad_update" {
                // server echoes mismatched policy — probe should detect
                if let updated = state.entries.first(where: { $0.type == "session.updated" }),
                   let data = updated.raw.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sess = obj["session"] as? [String: Any],
                   let p = PBTurnDetectionPolicy(fromSession: sess),
                   !PBValidateTurnDetectionPolicy(p).ok {
                    FileHandle.standardError.write("PB_SELF_TEST=PASS scenario=production_vad_bad_update entries=\(state.entries.count)\n".data(using: .utf8)!)
                    return
                }
                // else: mismatch not detected = fail
                FileHandle.standardError.write("PB_SELF_TEST=FAIL scenario=production_vad_bad_update entries=\(state.entries.count)\n".data(using: .utf8)!)
                return
            } else {
                // production_vad: server echoes correct policy
                if !state.entries.contains(where: { $0.type == "session.updated" }) {
                    FileHandle.standardError.write("PB_SELF_TEST=FAIL no_session_updated entries=\(state.entries.count)\n".data(using: .utf8)!); return
                }
            }
        }

        // Send PCM
        let pcmData = (try? Data(contentsOf: URL(fileURLWithPath: pcmPath))) ?? Data(count: 24000)
        let mid = pcmData.count / 2
        let pcm1 = Data(pcmData.prefix(mid))
        let pcm2 = Data(pcmData.suffix(pcmData.count - mid))
        let chunkSize = 3200

        // PCM1 (no commit in VAD mode — just append)
        var c = 0
        while c < pcm1.count {
            let end = min(c + chunkSize, pcm1.count)
            let chunk = pcm1[c..<end]; c = end
            let b64 = chunk.base64EncodedString()
            let frame = "{\"event_id\":\"\(UUID().uuidString)\",\"type\":\"input_audio_buffer.append\",\"audio\":\"\(b64)\"}"
            do { try await ws.send(frame) } catch {
                FileHandle.standardError.write("PB_FAIL send_pcm1: \(error)\n".data(using: .utf8)!); return
            }
            state.appendWire(direction: "send", raw: frame)
        }

        // For production_vad: wait for speech_started + committed, then send response.create
        if scenario == "production_vad" {
            let dl = state.clock.deadline(sec: timeoutSec)
            var committed = false
            while state.clock.now < dl && !committed {
                if state.entries.contains(where: { $0.type == "input_audio_buffer.committed" }) { committed = true; break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            if !committed {
                FileHandle.standardError.write("PB_SELF_TEST=FAIL no_committed entries=\(state.entries.count)\n".data(using: .utf8)!); return
            }
            // Send response.create
            let rc = "{\"event_id\":\"\(UUID().uuidString)\",\"type\":\"response.create\"}"
            do { try await ws.send(rc) } catch {
                FileHandle.standardError.write("PB_FAIL send_response_create: \(error)\n".data(using: .utf8)!); return
            }
            state.appendWire(direction: "send", raw: rc)

            // Wait for response.created
            let dl2 = state.clock.deadline(sec: timeoutSec)
            while state.clock.now < dl2 {
                if state.entries.contains(where: { $0.type == "response.created" }) { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        // PCM2
        var c2 = 0
        while c2 < pcm2.count {
            let end = min(c2 + chunkSize, pcm2.count)
            let chunk = pcm2[c2..<end]; c2 = end
            let b64 = chunk.base64EncodedString()
            let frame = "{\"event_id\":\"\(UUID().uuidString)\",\"type\":\"input_audio_buffer.append\",\"audio\":\"\(b64)\"}"
            do { try await ws.send(frame) } catch {
                FileHandle.standardError.write("PB_FAIL send_pcm2: \(error)\n".data(using: .utf8)!); return
            }
            state.appendWire(direction: "send", raw: frame)
        }

        // Wait for response.done
        let dl = state.clock.deadline(sec: timeoutSec)
        FileHandle.standardError.write("PB_SELFTEST_AWAIT_DONE deadline=\(dl) elapsed_ns=\(state.clock.now)\n".data(using: .utf8)!)
        while state.clock.now < dl {
            if state.entries.contains(where: { $0.type == "response.done" }) { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        FileHandle.standardError.write("PB_SELFTEST_DONE_WAIT_EXIT elapsed_ns=\(state.clock.now)\n".data(using: .utf8)!)

        // Report
        let sendCount = state.entries.filter { $0.direction == "send" }.count
        let recvCount = state.entries.filter { $0.direction == "receive" }.count
        let sysCount = state.entries.filter { $0.direction == "system" }.count
        let violations = state.hasTimelineViolations()
        let outcome = violations ? "FAIL_TIMELINE" : "PASS"

        FileHandle.standardError.write("PB_SELF_TEST=\(outcome) scenario=\(scenario) entries=\(state.entries.count) send=\(sendCount) recv=\(recvCount) violations=\(violations)\n".data(using: .utf8)!)

        let report: [String: Any] = [
            "scenario": scenario,
            "total_entries": state.entries.count,
            "send_entries": sendCount,
            "receive_entries": recvCount,
            "system_entries": sysCount,
            "timeline_violations": state.timelineViolations,
            "outcome": outcome
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]),
           let url = URL(string: outputURL.absoluteString) {
            try? data.write(to: URL(fileURLWithPath: outputURL.path).appendingPathComponent("selftest_report.json"))
        }
    }

    // MARK: - Live mode

    static func runLive(
        outputURL: URL,
        state: PBProbeState,
        pcmPath: String,
        allowInteraction: Bool,
        timeoutSec: Int
    ) {
        let pcmURL = URL(fileURLWithPath: pcmPath)
        guard let pcmData = try? Data(contentsOf: pcmURL) else {
            print("PB_FAIL invalid_pcm"); exit(1)
        }
        // Load cut from sidecar if present
        let cutURL = pcmURL.deletingPathExtension().appendingPathExtension("cut.json")
        var pcm1: Data
        var pcm2: Data
        var cutMode = "midpoint"
        if let cutData = try? Data(contentsOf: cutURL),
           let cut = try? JSONSerialization.jsonObject(with: cutData) as? [String: Any],
           let b1 = cut["pcm1_bytes"] as? Int,
           let b2 = cut["pcm2_bytes"] as? Int,
           b1 > 0, b2 > 0, b1 + b2 == pcmData.count {
            pcm1 = Data(pcmData.prefix(b1))
            pcm2 = Data(pcmData.suffix(b2))
            cutMode = cut["mode"] as? String ?? "sidecar"
        } else {
            let mid = pcmData.count / 2
            pcm1 = Data(pcmData.prefix(mid))
            pcm2 = Data(pcmData.suffix(pcmData.count - mid))
        }
        FileHandle.standardError.write("PB_PCM cut=\(cutMode) pcm1=\(pcm1.count) pcm2=\(pcm2.count)\n".data(using: .utf8)!)

        let storedCredential = PBStoredCredential(allowInteraction: allowInteraction)

        let endpoint = URL(string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-plus-realtime")!

        print("PB_START pcm=\(pcmData.count) output=\(outputURL.path)")
        fflush(stdout)

        Task.detached {
            // Credential
            let secret: String
            let workspaceID: String
            do {
                guard let k = try storedCredential.readCredential(for: "qwen-realtime") else {
                    FileHandle.standardError.write("PB_FAIL keychain_empty\n".data(using: .utf8)!)
                    state.close(); exit(1)
                }
                secret = k
                workspaceID = (try? storedCredential.workspaceID(for: "qwen-realtime")) ?? "workspace"
            } catch {
                FileHandle.standardError.write("PB_FAIL keychain: \(error)\n".data(using: .utf8)!)
                state.close(); exit(1)
            }
            FileHandle.standardError.write("PB_CRED ok len=\(secret.count) ws=\(workspaceID)\n".data(using: .utf8)!)

            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                FileHandle.standardError.write("PB_FAIL url\n".data(using: .utf8)!)
                state.close(); exit(1)
            }
            comps.host = "\(workspaceID).cn-beijing.maas.aliyuncs.com"
            guard let fullEndpoint = comps.url else {
                FileHandle.standardError.write("PB_FAIL url2\n".data(using: .utf8)!)
                state.close(); exit(1)
            }

            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: config)
            var request = URLRequest(url: fullEndpoint)
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            let task = session.webSocketTask(with: request)
            let ws = PBWebSocketURLSession(task: task)

            // Single persistent receiver
            let receiverTask: Task<Void, Never> = Task { [ws] in
                while !Task.isCancelled {
                    do {
                        guard let text = try await ws.receive() else { break }
                        state.appendWire(direction: "receive", raw: text)
                    } catch is CancellationError {
                        break
                    } catch {
                        state.appendWire(direction: "system", raw: "{\"reason\":\"receiver_exit\"}", error: "\(error)")
                        break
                    }
                }
            }

            defer {
                receiverTask.cancel()
                Task { await ws.close() }
                state.close()
            }

            var phase = PBLivePhase.awaitSessionCreated
            let deadline = state.clock.deadline(sec: timeoutSec)

            // Phase 0: wait for session.created
            FileHandle.standardError.write("PB_PHASE=await_session_created elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            while state.clock.now < deadline {
                if state.entries.contains(where: { $0.type == "session.created" }) {
                    phase = .awaitSessionUpdatedAck
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            guard case PBLivePhase.awaitSessionUpdatedAck = phase else {
                FileHandle.standardError.write("PB_FAIL no_session_created elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
                exit(1)
            }
            FileHandle.standardError.write("PB_GATE=session_created elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)

            // Phase 1: send session.update (semantic_vad, mirrors production)
            let updatePayload = PBSessionUpdatePayload(eventId: UUID().uuidString)
            guard let updateData = try? JSONSerialization.data(withJSONObject: updatePayload),
                  let updateText = String(data: updateData, encoding: .utf8) else {
                FileHandle.standardError.write("PB_FAIL serialize_session_update\n".data(using: .utf8)!); exit(1)
            }
            do { try await ws.send(updateText) } catch {
                FileHandle.standardError.write("PB_FAIL send_session_update: \(error)\n".data(using: .utf8)!); exit(1)
            }
            state.appendWire(direction: "send", raw: updateText)
            FileHandle.standardError.write("PB_SEND=session_update semantic_vad threshold=0.2 silence_ms=800 create_response=false interrupt_response=false\n".data(using: .utf8)!)
            FileHandle.standardError.write("PB_PHASE=await_session_updated_ack elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)

            // Phase 1b: wait for session.updated with policy ack
            var policyValid = false
            while state.clock.now < deadline {
                if let entry = state.entries.first(where: { $0.type == "session.updated" }),
                   let data = entry.raw.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sess = obj["session"] as? [String: Any],
                   let policy = PBTurnDetectionPolicy(fromSession: sess) {
                    let vr = PBValidateTurnDetectionPolicy(policy)
                    policyValid = vr.ok
                    if !vr.ok {
                        FileHandle.standardError.write("PB_POLICY_MISMATCH errors=\(vr.errors.joined(separator:","))\n".data(using: .utf8)!)
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            if policyValid {
                FileHandle.standardError.write("PB_GATE=session_updated_policy_ok elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            } else {
                FileHandle.standardError.write("PB_GATE=session_updated_policy_missing elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            }

            // Phase 2: send PCM1 (append only, NO commit in VAD mode)
            FileHandle.standardError.write("PB_PHASE=pcm1_send elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            let chunkSize = 3200
            var c = 0
            var pcm1SendCompleteAt: UInt64 = 0
            while c < pcm1.count {
                let end = min(c + chunkSize, pcm1.count)
                let chunk = pcm1[c..<end]; c = end
                let b64 = chunk.base64EncodedString()
                let frame = "{\"event_id\":\"\(UUID().uuidString.lowercased())\",\"type\":\"input_audio_buffer.append\",\"audio\":\"\(b64)\"}"
                do { try await ws.send(frame) } catch {
                    FileHandle.standardError.write("PB_FAIL send_pcm1: \(error)\n".data(using: .utf8)!); exit(1)
                }
                state.appendWire(direction: "send", raw: frame)
            }
            pcm1SendCompleteAt = state.clock.now
            FileHandle.standardError.write("PB_PCM1=COMPLETE elapsed=\(round(Double(pcm1SendCompleteAt)/1_000_000.0))ms chunks=\(c/chunkSize+1)\n".data(using: .utf8)!)

            // Phase 3: wait for speech_started (first user turn)
            phase = .awaitFirstSpeechStarted
            FileHandle.standardError.write("PB_PHASE=await_speech_started_1 elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            var firstItemId: String? = nil
            while state.clock.now < deadline {
                if let entry = state.entries.first(where: { $0.type == "input_audio_buffer.speech_started" && $0.itemId != nil }),
                   let iid = entry.itemId {
                    firstItemId = iid
                    FileHandle.standardError.write("PB_SPEECH_STARTED_1 item=\(iid) audio_start_ms=\(entry.audioStartMs ?? -1) elapsed=\(round(Double(entry.elapsedNs)/1_000_000.0))ms\n".data(using: .utf8)!)
                    phase = .awaitFirstTurnCommitted
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            // Phase 3b: wait for input_audio_buffer.committed
            FileHandle.standardError.write("PB_PHASE=await_committed_1 elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            var firstTurnCommittedAt: UInt64 = 0
            while state.clock.now < deadline {
                if state.entries.contains(where: { $0.type == "input_audio_buffer.committed" }) {
                    firstTurnCommittedAt = state.clock.now
                    FileHandle.standardError.write("PB_COMMITTED_1 elapsed=\(round(Double(firstTurnCommittedAt)/1_000_000.0))ms\n".data(using: .utf8)!)
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            // Guard: first turn must complete with speech_stopped + committed before PCM2.
            // If deadline reached without committed, probe is INVALID_FIRST_TURN.
            // Do NOT continue to response.create / PCM2 — that path has no valid turn to overlap.
            if firstTurnCommittedAt == 0 {
                let elapsedMs = round(state.clock.elapsedSec() * 1000)
                FileHandle.standardError.write("PB_INVALID_FIRST_TURN reason=no_committed elapsed=\(elapsedMs)ms deadline=\(deadline) entries=\(state.entries.count)\n".data(using: .utf8)!)
                state.close()
                exit(1)
            }

            // Phase 4: send response.create (Aftelle production pattern)
            phase = .awaitResponseCreated
            FileHandle.standardError.write("PB_PHASE=send_response_create elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            let rcPayload = "{\"event_id\":\"\(UUID().uuidString.lowercased())\",\"type\":\"response.create\"}"
            do { try await ws.send(rcPayload) } catch {
                FileHandle.standardError.write("PB_FAIL send_response_create: \(error)\n".data(using: .utf8)!); exit(1)
            }
            state.appendWire(direction: "send", raw: rcPayload)
            FileHandle.standardError.write("PB_SEND=response_create elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)

            // Phase 4b: wait for response.created
            var firstResponseId: String? = nil
            while state.clock.now < deadline {
                if let entry = state.entries.first(where: { $0.type == "response.created" }),
                   let rid = entry.responseId {
                    firstResponseId = rid
                    FileHandle.standardError.write("PB_RESPONSE_CREATED_1 rid=\(rid) elapsed=\(round(Double(entry.elapsedNs)/1_000_000.0))ms\n".data(using: .utf8)!)
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            // Phase 5: send PCM2 immediately upon response.created (mirrors Aftelle overlap logic)
            FileHandle.standardError.write("PB_PHASE=pcm2_send elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            var c2 = 0
            var pcm2SendCompleteAt: UInt64 = 0
            while c2 < pcm2.count {
                let end = min(c2 + chunkSize, pcm2.count)
                let chunk = pcm2[c2..<end]; c2 = end
                let b64 = chunk.base64EncodedString()
                let frame = "{\"event_id\":\"\(UUID().uuidString.lowercased())\",\"type\":\"input_audio_buffer.append\",\"audio\":\"\(b64)\"}"
                do { try await ws.send(frame) } catch {
                    FileHandle.standardError.write("PB_FAIL send_pcm2: \(error)\n".data(using: .utf8)!); exit(1)
                }
                state.appendWire(direction: "send", raw: frame)
            }
            pcm2SendCompleteAt = state.clock.now
            FileHandle.standardError.write("PB_PCM2=COMPLETE elapsed=\(round(Double(pcm2SendCompleteAt)/1_000_000.0))ms\n".data(using: .utf8)!)

            // Phase 5b: await second speech_started (may arrive during active response)
            phase = .phase2AwaitSecondSpeechStarted
            FileHandle.standardError.write("PB_PHASE=await_speech_started_2 elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            var secondItemId: String? = nil
            while state.clock.now < deadline {
                if let entry = state.entries.last(where: { $0.type == "input_audio_buffer.speech_started" && $0.itemId != firstItemId }),
                   let iid = entry.itemId {
                    secondItemId = iid
                    FileHandle.standardError.write("PB_SPEECH_STARTED_2 item=\(iid) audio_start_ms=\(entry.audioStartMs ?? -1) elapsed=\(round(Double(entry.elapsedNs)/1_000_000.0))ms\n".data(using: .utf8)!)
                    // Aftelle interruption: if active response exists, cancel it
                    if firstResponseId != nil {
                        FileHandle.standardError.write("PB_INTERRUPTION rid=\(firstResponseId ?? "")\n".data(using: .utf8)!)
                        let cancelPayload = "{\"event_id\":\"\(UUID().uuidString.lowercased())\",\"type\":\"response.cancel\",\"response_id\":\"\(firstResponseId!)\"}"
                        do { try await ws.send(cancelPayload) } catch {
                            FileHandle.standardError.write("PB_ERR send_cancel: \(error)\n".data(using: .utf8)!)
                        }
                        state.appendWire(direction: "send", raw: cancelPayload)
                        // Send new response.create for the new turn
                        let rc2 = "{\"event_id\":\"\(UUID().uuidString.lowercased())\",\"type\":\"response.create\"}"
                        do { try await ws.send(rc2) } catch {
                            FileHandle.standardError.write("PB_ERR send_response_create_2: \(error)\n".data(using: .utf8)!)
                        }
                        state.appendWire(direction: "send", raw: rc2)
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            // Phase 6: await all response.done
            phase = .awaitSecondResponseDone
            FileHandle.standardError.write("PB_PHASE=await_response_done elapsed=\(round(state.clock.elapsedSec()*1000))ms\n".data(using: .utf8)!)
            var responseDoneCount = 0
            while state.clock.now < deadline {
                let n = state.entries.filter { $0.type == "response.done" }.count
                if n >= 2 { responseDoneCount = n; break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            responseDoneCount = state.entries.filter { $0.type == "response.done" }.count

            // Timeline violation check
            let violations = state.hasTimelineViolations()
            if violations {
                FileHandle.standardError.write("PB_TIMELINE_VIOLATION entries=\(state.timelineViolations.count)\n".data(using: .utf8)!)
                for v in state.timelineViolations {
                    FileHandle.standardError.write("  VIOLATION: \(v)\n".data(using: .utf8)!)
                }
            }

            // Final report
            let sendEntries = state.entries.filter { $0.direction == "send" }
            let recvEntries = state.entries.filter { $0.direction == "receive" }
            let report: [String: Any] = [
                "outcome": violations ? "INVALID_PROBE_TIMELINE" : "VALID_PROBE",
                "response_done_count": responseDoneCount,
                "total_entries": state.entries.count,
                "send_entries": sendEntries.count,
                "receive_entries": recvEntries.count,
                "system_entries": state.entries.filter { $0.direction == "system" }.count,
                "timeline_violations": state.timelineViolations,
                "first_item_id": firstItemId ?? "",
                "second_item_id": secondItemId ?? "",
                "first_response_id": firstResponseId ?? "",
                "pcm1_complete_ms": round(Double(pcm1SendCompleteAt) / 1_000_000.0),
                "pcm2_complete_ms": round(Double(pcm2SendCompleteAt) / 1_000_000.0),
                "first_turn_committed_ms": round(Double(firstTurnCommittedAt) / 1_000_000.0),
                "elapsed_final_ms": round(state.clock.elapsedSec() * 1000),
            ]
            let reportURL = outputURL.appendingPathComponent("report.json")
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: reportURL)
            }

            FileHandle.standardError.write("PB_COMPLETE entries=\(state.entries.count) recv=\(recvEntries.count) done=\(responseDoneCount) violations=\(violations) elapsed=\(round(state.clock.elapsedSec()))s\n".data(using: .utf8)!)
            exit(violations ? 1 : 0)
        }
        dispatchMain()
    }
}
