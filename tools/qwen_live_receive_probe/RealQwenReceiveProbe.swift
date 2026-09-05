import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum ProbeError: String, Error {
    case arguments, audioUploadNotAuthorized, invalidPCM, fixtureUnavailable
    case evidenceWrite, startupTimeout, phaseTimeout, totalTimeout, coverageMissing, selfTestFailed
    case credentialUnavailable
}

private struct ProbeOptions {
    var mode = ""
    var pcm: URL?
    var replay: URL?
    var output: URL?
    var fixture: URL?
    var attempts = 5
    var seconds = 300
    var uploadAuthorized = false

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            index += 1
            if ["--live", "--replay", "--self-test"].contains(flag) {
                guard mode.isEmpty else { throw ProbeError.arguments }
                mode = flag
                continue
            }
            if flag == "--allow-audio-upload" { uploadAuthorized = true; continue }
            guard index < arguments.count else { throw ProbeError.arguments }
            let value = arguments[index]
            index += 1
            switch flag {
            case "--pcm": pcm = URL(fileURLWithPath: value)
            case "--wire": replay = URL(fileURLWithPath: value)
            case "--output": output = URL(fileURLWithPath: value)
            case "--fixture": fixture = URL(fileURLWithPath: value)
            case "--attempts": attempts = Int(value) ?? 0
            case "--seconds": seconds = Int(value) ?? 0
            default: throw ProbeError.arguments
            }
        }
        guard output != nil, fixture != nil, (1 ... 5).contains(attempts), (1 ... 300).contains(seconds),
              ["--live", "--replay", "--self-test"].contains(mode) else { throw ProbeError.arguments }
        if mode == "--live", !uploadAuthorized { throw ProbeError.audioUploadNotAuthorized }
        if mode != "--self-test", pcm == nil { throw ProbeError.arguments }
        if mode == "--replay", replay == nil { throw ProbeError.arguments }
    }
}

private struct ProbeFixtureCredential: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        try QwenRealtimeCredential(workspaceID: "fixture-workspace", secret: "fixture-secret").storedValue()
    }
}

// Use the existing Keychain reference, but never wait indefinitely for an unattended UI prompt.
private struct ProbeKeychainCredential: ProviderCredentialReading {
    let diagnostics: NativeSpeechDiagnosticBuffer
    func readCredential(for keyRef: String) throws -> String? {
        diagnostics.append(NativeSpeechInternalDiagnosticEvent(
            source: .adapter, category: "probe_startup", routeKind: .realtimeBrain, disposition: "keychain_begin"
        ))
        defer {
            diagnostics.append(NativeSpeechInternalDiagnosticEvent(
                source: .adapter, category: "probe_startup", routeKind: .realtimeBrain, disposition: "keychain_end"
            ))
        }
        guard let location = ProviderKeychainStore.location(for: keyRef) else { throw ProbeError.credentialUnavailable }
        let authentication = LAContext()
        authentication.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: location.service, kSecAttrAccount as String: location.account,
            kSecAttrSynchronizable as String: false, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: authentication
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            diagnostics.append(NativeSpeechInternalDiagnosticEvent(
                source: .adapter, category: "probe_credential_failure", routeKind: .realtimeBrain,
                disposition: "keychain_access_denied_or_missing", errorCode: "credentialUnavailable"
            ))
            throw ProbeError.credentialUnavailable
        }
        return value
    }
}

private actor ProbeScriptedTransport: RealtimeWebSocketTransport {
    let fake = R3FakeRealtimeWebSocketTransport()
    let malformed: Bool
    let stallsAudio: Bool
    let startupDelayNanoseconds: UInt64
    var stalledSend: CheckedContinuation<Void, any Error>?
    var appends = 0
    var responseAppends: Int?

    init(malformed: Bool, stallsAudio: Bool = false, startupDelayNanoseconds: UInt64 = 0) {
        self.malformed = malformed
        self.stallsAudio = stallsAudio
        self.startupDelayNanoseconds = startupDelayNanoseconds
    }
    func connect(endpoint: URL, bearerToken: String) async throws {
        if startupDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: startupDelayNanoseconds) }
        try await fake.connect(endpoint: endpoint, bearerToken: bearerToken)
    }
    func receive() async throws -> RealtimeWebSocketFrame { try await fake.receive() }
    func close(reason: RealtimeWebSocketCloseReason) async {
        let pending = stalledSend
        stalledSend = nil
        pending?.resume(throwing: NativeSpeechError.cancelled)
        await fake.close(reason: reason)
    }
    func send(_ frame: RealtimeWebSocketFrame) async throws {
        try await fake.send(frame)
        guard case .text(let text) = frame,
              let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
        if object["type"] as? String == "response.create" {
            responseAppends = 0
            await fake.enqueueText(#"{"type":"response.audio.delta","response_id":"response-tool-1","delta":"AAA="}"#)
        }
        guard object["type"] as? String == "input_audio_buffer.append" else { return }
        if stallsAudio {
            try await withCheckedThrowingContinuation { stalledSend = $0 }
            return
        }
        appends += 1
        if appends == 1 {
            await fake.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"opening"}"#)
        }
        if appends == 6 {
            await fake.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"opening"}"#)
            await fake.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"opening","transcript":"请详细介绍三个有趣的话题"}"#)
        }
        if let count = responseAppends {
            responseAppends = count + 1
            if count == 1 {
                await fake.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"overlap"}"#)
                let partial = malformed
                    ? #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"overlap","text":"private-sensitive-text"}"#
                    : #"{"type":"conversation.item.input_audio_transcription.delta","item_id":"overlap","text":"先停一下","stash":""}"#
                await fake.enqueueText(partial)
            }
            if count == 6 {
                await fake.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"overlap"}"#)
                await fake.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"overlap","transcript":"先停一下我想问第二点是什么意思"}"#)
            }
        }
    }
}

@MainActor
private final class ProbeRound {
    let runtime: RuntimeCore
    let transport: ProbeTransport
    let diagnostics: NativeSpeechDiagnosticBuffer
    let output: URL
    var identity: RealtimeBrainSessionIdentity?
    var receiver: Task<Void, Never>?
    var watchdog: Task<Void, Never>?
    var stopping = false
    var failure: String?
    var firstProviderFailure: String?
    var timeoutInitiated = false
    var firstAudioAt: UInt64?
    var lastProgress = DispatchTime.now().uptimeNanoseconds
    var speechStarts = 0
    var transcriptFinals = 0
    var audioEvents = 0
    var acceptedEvents = 0
    var overlapAt: UInt64?
    var startedAt: UInt64 = 0
    var completedInputFrames = 0
    var lastMilestone = "not_started"
    var milestonesMs: [String: Double] = [:]
    var maximumSendLatenessNs: UInt64 = 0
    var maximumAppendDurationNs: UInt64 = 0
    var diagnosticRecords: [[String: String]] = []

    init(credential: any ProviderCredentialReading, transport: ProbeTransport, diagnostics: NativeSpeechDiagnosticBuffer, output: URL) {
        self.transport = transport
        self.diagnostics = diagnostics
        self.output = output
        // Same non-secret configuration as the current App. check.sh detects drift.
        let adapter = QwenRealtimeResidentBrainAdapter(
            credentialReader: credential, transport: transport,
            configuration: QwenRealtimeResidentBrainConfiguration(
                endpoint: URL(string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-plus-realtime")!,
                keyRef: ProviderKeychainStore.qwenKeyRef, defaultProviderVoiceID: "Tina"
            ), diagnosticBuffer: diagnostics
        )
        let router = ProviderRouter(credentialReader: credential, realtimeResidentBrainProvider: adapter)
        runtime = RuntimeCore(executionEngine: ExecutionEngine(providerRouter: router), providerRouter: router, sessionStore: SessionStore())
        runtime.attachNativeSpeechDiagnosticBuffer(diagnostics)
    }

    func run(pcm: Data, fixture: Data, delayMs: UInt64, deadline: UInt64) async -> [String: Any] {
        var outcome = "NOT_REPRODUCED"
        startedAt = DispatchTime.now().uptimeNanoseconds
        watchdog = Task { [self] in
            while !Task.isCancelled, !stopping {
                let now = DispatchTime.now().uptimeNanoseconds
                if let timeout = Self.timeout(now: now, deadline: deadline, startedAt: startedAt,
                                              sessionReady: identity != nil, lastProgress: lastProgress) {
                    failure = firstProviderFailure ?? failure ?? timeout.rawValue
                    timeoutInitiated = true
                    // Test-process resource shutdown, never a synthetic Runtime interruption decision.
                    await transport.close(reason: .cancelled)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
        }
        do {
            try milestone("fixture_load_begin")
            guard runtime.loadDR(from: fixture).isLoaded else { throw ProbeError.fixtureUnavailable }
            try milestone("session_start_begin")
            let session = try await runtime.startRealtimeResidentBrainSession().get()
            identity = session
            lastProgress = DispatchTime.now().uptimeNanoseconds
            try milestone("session_ready")
            try drainDiagnostics()
            receiver = Task { [self] in
                do {
                    while !stopping {
                        let disposition = try await runtime.receiveRealtimeResidentBrainEvent(session: session)
                        if case .accepted(let event) = disposition {
                            acceptedEvents += 1
                            switch event.kind {
                            case .userSpeechStarted:
                                speechStarts += 1; lastProgress = DispatchTime.now().uptimeNanoseconds
                                if speechStarts == 1 { try milestone("first_speech_started") }
                            case .userTranscriptFinal:
                                transcriptFinals += 1; lastProgress = DispatchTime.now().uptimeNanoseconds
                                if transcriptFinals == 1 { try milestone("first_transcript_final") }
                            case .residentAudioDelta:
                                audioEvents += 1
                                if firstAudioAt == nil {
                                    firstAudioAt = DispatchTime.now().uptimeNanoseconds; lastProgress = firstAudioAt!
                                    try milestone("first_audio_received")
                                }
                            case .error(let error): failure = "recoverable_\(Self.errorCode(error))"
                            default: break
                            }
                        }
                        try drainDiagnostics()
                    }
                } catch { if !stopping, failure == nil { failure = Self.errorCode(error) } }
            }
            let origin = DispatchTime.now().uptimeNanoseconds
            var sequence: UInt64 = 0
            var cursor: Int? = 0
            var overlapEnded: UInt64?
            while !stopping {
                let due = origin + sequence * 20_000_000
                let now = DispatchTime.now().uptimeNanoseconds
                if let timeout = Self.timeout(now: now, deadline: deadline, startedAt: startedAt,
                                              sessionReady: true, lastProgress: lastProgress) { throw timeout }
                if let failure { throw ProbeRecordedError(code: failure) }
                if now < due { try await Task.sleep(nanoseconds: due - now) }
                let timestamp = DispatchTime.now().uptimeNanoseconds
                maximumSendLatenessNs = max(maximumSendLatenessNs, timestamp > due ? timestamp - due : 0)
                // Never burst-send to catch up after a slow network append.
                if maximumSendLatenessNs > 100_000_000 { throw ProbeRecordedError(code: "input_pacing_overrun") }
                if cursor == nil, overlapAt == nil, let firstAudioAt,
                   timestamp - firstAudioAt >= delayMs * 1_000_000,
                   await transport.activeResponse {
                    cursor = 0
                    await transport.beginOverlap()
                    overlapAt = timestamp
                    lastProgress = timestamp
                    try milestone("overlap_begin")
                }
                var bytes = Data(repeating: 0, count: 640)
                let prerecordedActivity = cursor != nil
                if let offset = cursor {
                    let end = min(offset + 640, pcm.count)
                    bytes.replaceSubrange(0 ..< (end - offset), with: pcm[offset ..< end])
                    cursor = end == pcm.count ? nil : end
                    if cursor == nil, overlapAt != nil { overlapEnded = timestamp }
                }
                sequence += 1
                let frame = RealtimeBrainAudioFrame(identity: session, sequence: sequence,
                    timestampNanoseconds: timestamp,
                    format: RealtimeBrainAudioFormat(encoding: .pcm16LittleEndian, sampleRate: 16_000, channelCount: 1),
                    provenance: .acousticEchoProcessed, bytes: bytes)
                // Explicit post-AEC fixture input, not a claim that AEC/source gate detected speech.
                let activity = RealtimeBrainLocalAudioActivity(
                    kind: prerecordedActivity ? .listeningNearEnd : .none,
                    residentPlaybackSequence: 0, residentPlaybackActive: false,
                    lastAudibleResidentRenderTimestampNanoseconds: nil, sourceGateEpoch: 0,
                    routeStable: true, inputDeviceAvailable: true, outputDeviceAvailable: true)
                if sequence == 1 { try milestone("first_append_begin") }
                try await runtime.appendRealtimeResidentBrainAudio(frame, activity: activity).get()
                completedInputFrames += 1
                if sequence == 1 { try milestone("first_append_completed") }
                if prerecordedActivity {
                    try await runtime.confirmRealtimeResidentBrainAcceptedLocalAudioActivity(frame: frame, activity: activity).get()
                }
                maximumAppendDurationNs = max(maximumAppendDurationNs, DispatchTime.now().uptimeNanoseconds - timestamp)
                try drainDiagnostics()
                if let overlapEnded, timestamp - overlapEnded >= 3_000_000_000 {
                    guard speechStarts >= 2, transcriptFinals >= 2, audioEvents > 0,
                          await transport.overlapAppendsWhileActive > 0,
                          await transport.overlapStartsWhileActive > 0 else { throw ProbeError.coverageMissing }
                    break
                }
            }
        } catch {
            try? drainDiagnostics()
            failure = firstProviderFailure ?? failure ?? Self.errorCode(error)
            outcome = failure == "invalid_event" ? "FAILURE_REPRODUCED" : "ERROR_OBSERVED"
            if error is ProbeError, firstProviderFailure == nil { outcome = "INCONCLUSIVE" }
            if ["totalTimeout", "startupTimeout", "phaseTimeout"].contains(failure ?? "") { outcome = "TIMEOUT" }
            if failure == "credentialUnavailable" { outcome = "CONFIGURATION_BLOCKED" }
        }
        stopping = true
        watchdog?.cancel()
        // Save the first failure before any potentially slow provider teardown.
        try? drainDiagnostics()
        var report: [String: Any] = [
            "outcome": outcome, "error": failure ?? "none", "speech_starts": speechStarts,
            "last_milestone": lastMilestone, "milestones_ms": milestonesMs,
            "elapsed_ms": Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000,
            "startup_limit_ms": 60_000, "speech_no_progress_limit_ms": 30_000,
            "input_frames_completed": completedInputFrames, "wire_audio_appends": await transport.audioAppends,
            "transcript_finals": transcriptFinals, "audio_events": audioEvents, "accepted_events": acceptedEvents,
            "overlap_started_while_provider_active": overlapAt != nil,
            "overlap_appends_while_provider_active": await transport.overlapAppendsWhileActive,
            "overlap_speech_starts_while_provider_active": await transport.overlapStartsWhileActive,
            "maximum_send_lateness_ms": Double(maximumSendLatenessNs) / 1_000_000,
            "maximum_append_duration_ms": Double(maximumAppendDurationNs) / 1_000_000,
            "response_create": await transport.responseCreates, "response_cancel": await transport.responseCancels,
            "input_clear": await transport.inputClears, "generation": identity?.generation ?? 0,
            "local_activity_source": "prerecorded_post_aec_fixture_NOT_AEC_DETECTION",
            "aec_source_gate": "NOT_TESTED", "confirmed_interruption": "NOT_TESTED",
            "physical_playback_clear": "NOT_TESTED", "n_plus_1": "NOT_TESTED", "human_gate": "NOT_RUN"
        ]
        do { try Self.writeJSON(report, to: output.appendingPathComponent("report.json")) }
        catch {
            report["outcome"] = "ERROR_OBSERVED"
            report["error"] = "evidenceWrite"
            print("probe_report_write=FAILED")
        }
        receiver?.cancel()
        if let identity { _ = await runtime.closeRealtimeResidentBrainSession(identity: identity) }
        await transport.close(reason: .normal)
        return report
    }

    static func timeout(now: UInt64, deadline: UInt64, startedAt: UInt64,
                        sessionReady: Bool, lastProgress: UInt64) -> ProbeError? {
        if now >= deadline { return .totalTimeout }
        if !sessionReady { return now - startedAt >= 60_000_000_000 ? .startupTimeout : nil }
        return now - lastProgress >= 30_000_000_000 ? .phaseTimeout : nil
    }

    func milestone(_ name: String) throws {
        lastMilestone = name
        milestonesMs[name] = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        try Self.writeJSON(["last_milestone": name, "milestones_ms": milestonesMs],
                           to: output.appendingPathComponent("progress.json"))
        print("probe_milestone=\(name) elapsed_ms=\(Int(milestonesMs[name]!))")
    }

    func drainDiagnostics() throws {
        let previousCount = diagnosticRecords.count
        for event in diagnostics.drain().events {
            // Keep only code-owned fields needed for this investigation.
            if ["qwen_receive_failure", "probe_credential_failure", "probe_startup", "qwen_speech_started_received",
                "qwen_input_item_reassociated", "qwen_transcript_final_received", "qwen_transcript_final_enqueued",
                "qwen_transcript_final_delivered", "qwen_transcript_final_enqueue_rejected",
                "runtime_user_transcript_final_disposition", "runtime_user_transcript_final_admission"].contains(event.category) {
                if ["qwen_receive_failure", "probe_credential_failure"].contains(event.category), firstProviderFailure == nil, !timeoutInitiated {
                    firstProviderFailure = event.errorCode
                    failure = firstProviderFailure
                }
                diagnosticRecords.append([
                    "category": event.category, "monotonic_ns": String(event.monotonicTimestampNanoseconds),
                    "generation": event.turnGeneration.map(String.init) ?? "none",
                    "state_before": event.stateBefore ?? "none", "disposition": event.disposition ?? "none",
                    "wire_sequence": event.wireSequence.map(String.init) ?? "none", "error": event.errorCode ?? "none"
                ])
            }
        }
        if diagnosticRecords.count != previousCount {
            try Self.writeJSON(diagnosticRecords, to: output.appendingPathComponent("diagnostics.json"))
        }
    }

    static func writeJSON(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    static func errorCode(_ error: any Error) -> String {
        if let error = error as? ProbeError { return error.rawValue }
        if let error = error as? ProbeRecordedError { return error.code }
        if let error = error as? RealtimeResidentBrainError {
            return error == .invalidEvent ? "invalid_event" : String(describing: error)
        }
        return error is CancellationError ? "cancelled" : "configuration_or_io_failure"
    }
}

private struct ProbeRecordedError: Error { let code: String }

@main
@MainActor
private struct RealQwenReceiveProbe {
    static func main() async {
        do {
            let options = try ProbeOptions(Array(CommandLine.arguments.dropFirst()))
            guard let output = options.output, let fixtureURL = options.fixture else { throw ProbeError.arguments }
            let fixture = try Data(contentsOf: fixtureURL)
            let pcm: Data
            if options.mode == "--self-test" {
                pcm = Data((0 ..< 9_600).flatMap { _ in [UInt8(0x90), UInt8(0x01)] })
            } else {
                guard let url = options.pcm else { throw ProbeError.arguments }
                pcm = try Data(contentsOf: url)
            }
            try validatePCM(pcm)
            if options.mode == "--self-test" { try testSafetyValidation(); try testTimeouts() }
            let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(options.seconds) * 1_000_000_000
            var reports: [[String: Any]] = []
            let count = options.mode == "--self-test" ? 5 : (options.mode == "--replay" ? 1 : options.attempts)
            for index in 0 ..< count {
                let directory = output.appendingPathComponent("attempt-\(index + 1)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                let diagnostics = NativeSpeechDiagnosticBuffer()
                let underlying: (any RealtimeWebSocketTransport)?
                let credential: any ProviderCredentialReading
                var replay: [ProbeWireRecord]?
                if options.mode == "--live" {
                    credential = ProbeKeychainCredential(diagnostics: diagnostics)
                    underlying = URLSessionRealtimeWebSocketTransport(diagnosticBuffer: diagnostics, diagnosticRouteKind: .realtimeBrain)
                } else {
                    credential = ProbeFixtureCredential()
                    underlying = options.mode == "--self-test" && index != 2
                        ? ProbeScriptedTransport(malformed: index == 1, stallsAudio: index == 3,
                                                 startupDelayNanoseconds: index == 4 ? 500_000_000 : 0) : nil
                    let replayURL = options.mode == "--self-test" && index == 2
                        ? output.appendingPathComponent("attempt-2/wire.ndjson") : options.replay
                    if let url = replayURL {
                        replay = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
                            try JSONDecoder().decode(ProbeWireRecord.self, from: Data($0.utf8))
                        }
                    }
                }
                let transport = try ProbeTransport(underlying: underlying, replay: replay,
                                                   output: directory.appendingPathComponent("wire.ndjson"), diagnostics: diagnostics)
                let round = ProbeRound(credential: credential, transport: transport, diagnostics: diagnostics, output: directory)
                let delayMs: UInt64 = options.mode == "--live" ? [0, 200, 600, 1_000, 0][index] : 0
                let roundDeadline = options.mode == "--self-test" && index == 3
                    ? DispatchTime.now().uptimeNanoseconds + 200_000_000 : deadline
                let report = await round.run(pcm: pcm, fixture: fixture, delayMs: delayMs, deadline: roundDeadline)
                reports.append(report)
                print("attempt=\(index + 1) outcome=\(report["outcome"] ?? "unknown") error=\(report["error"] ?? "unknown")")
                if options.mode != "--self-test", report["outcome"] as? String != "NOT_REPRODUCED" { break }
            }
            let summary: [String: Any] = [
                "schema_version": 1, "mode": options.mode, "attempts": reports,
                "pcm_sha256": SHA256.hash(data: pcm).map { String(format: "%02x", $0) }.joined(),
                "pcm_format": "16000Hz_mono_signed16_little_endian", "pcm_duration_ms": pcm.count / 32,
                "replay_fidelity": "sanitized_codec_state_only_NOT_BIT_EXACT_NOT_SEMANTIC_REPLAY",
                "human_gate": "NOT_RUN"
            ]
            try ProbeRound.writeJSON(summary, to: output.appendingPathComponent("summary.json"))
            if options.mode == "--self-test" {
                guard reports.count == 5, reports[0]["outcome"] as? String == "NOT_REPRODUCED",
                      reports[1]["error"] as? String == "invalid_event",
                      reports[2]["error"] as? String == "invalid_event",
                      reports[3]["outcome"] as? String == "TIMEOUT",
                      reports[4]["outcome"] as? String == "NOT_REPRODUCED",
                      (reports[4]["input_frames_completed"] as? Int ?? 0) > 0,
                      let milestones = reports[4]["milestones_ms"] as? [String: Double],
                      let ready = milestones["session_ready"], ready >= 500,
                      let append = milestones["first_append_completed"], append >= ready else { throw ProbeError.selfTestFailed }
                print("probe_delayed_startup_input=PASS")
                let wire = try String(contentsOf: output.appendingPathComponent("attempt-2/wire.ndjson"), encoding: .utf8)
                guard !wire.contains("private-sensitive-text"), !wire.contains("fixture-secret") else { throw ProbeError.selfTestFailed }
                var branches: [String] = []
                for attempt in [2, 3] {
                    let data = try Data(contentsOf: output.appendingPathComponent("attempt-\(attempt)/diagnostics.json"))
                    let events = try JSONSerialization.jsonObject(with: data) as? [[String: String]]
                    guard let branch = events?.first(where: { $0["category"] == "qwen_receive_failure" })?["disposition"] else {
                        throw ProbeError.selfTestFailed
                    }
                    branches.append(branch)
                }
                guard branches[0] == branches[1], branches[0].contains("branch=transcript_text_or_stash") else {
                    throw ProbeError.selfTestFailed
                }
                print("probe_replay_first_failure_branch=PASS")
                print("probe_self_test=PASS")
            }
            print("probe_finished=YES human_gate=NOT_RUN")
            if options.mode != "--self-test", reports.contains(where: { $0["outcome"] as? String != "NOT_REPRODUCED" }) { exit(2) }
        } catch {
            print("probe_error=\(ProbeRound.errorCode(error))")
            exit(1)
        }
    }

    static func validatePCM(_ data: Data) throws {
        guard (3_200 ... 960_000).contains(data.count), data.count.isMultiple(of: 2),
              !data.starts(with: Data("RIFF".utf8)), data.contains(where: { $0 != 0 }) else { throw ProbeError.invalidPCM }
    }

    static func testSafetyValidation() throws {
        let base = ["--output", "/tmp/fixture-output", "--fixture", "/tmp/fixture-input"]
        let invalidArguments = [
            base + ["--live", "--pcm", "/tmp/fixture.pcm"],
            base + ["--self-test", "--attempts", "6"],
            base + ["--self-test", "--seconds", "301"],
            base + ["--self-test", "--seconds", "0"],
            base + ["--self-test", "--live"]
        ]
        for arguments in invalidArguments {
            do { _ = try ProbeOptions(arguments); throw ProbeError.selfTestFailed }
            catch ProbeError.arguments { }
            catch ProbeError.audioUploadNotAuthorized { }
        }
        for data in [Data(), Data(repeating: 1, count: 3_201), Data(repeating: 0, count: 3_200), Data("RIFF".utf8) + Data(repeating: 1, count: 3_196)] {
            do { try validatePCM(data); throw ProbeError.selfTestFailed }
            catch ProbeError.invalidPCM { }
        }
        print("probe_safety_rejection_checks=9")
    }

    static func testTimeouts() throws {
        let second: UInt64 = 1_000_000_000
        let cases: [(UInt64, Bool, UInt64, UInt64, ProbeError?)] = [
            (40, false, 0, 300, nil), (60, false, 0, 300, .startupTimeout),
            (40, true, 40, 300, nil), (69, true, 40, 300, nil),
            (70, true, 40, 300, .phaseTimeout), (40, false, 0, 40, .totalTimeout)
        ]
        for (now, ready, progress, deadline, expected) in cases {
            guard ProbeRound.timeout(now: now * second, deadline: deadline * second, startedAt: 0,
                                     sessionReady: ready, lastProgress: progress * second) == expected else {
                throw ProbeError.selfTestFailed
            }
        }
        print("probe_monotonic_timeout_checks=6")
    }
}
