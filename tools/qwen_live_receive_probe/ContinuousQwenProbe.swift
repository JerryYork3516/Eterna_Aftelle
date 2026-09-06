import AVFoundation
import CryptoKit
import Foundation

#if AFTELLE_CONTINUOUS_PROBE
private struct ContinuousProbeFailure: Error { let code: String }

// Virtual hardware advances only on the sample clock. It never makes an
// interruption decision or calls Host clear itself.
private final class SilentClockedPlayer: MacSpeechAudioOutputPlaying, @unchecked Sendable {
    private struct Chunk {
        let bytes: [UInt8]
        var offset = 0
        let completion: @Sendable (Result<Int, MacSpeechAudioOutputHostError>) -> Void
    }
    private let lock = NSLock()
    private let aec: MacSpeechAcousticEchoHost
    private var chunks: [Chunk] = []
    private var retired: [Chunk] = []
    private var running = false
    private var clears = 0
    private var played = 0
    private var starts = 0
    private var lateCallbacks = 0
    private var playedAtClear = 0
    private var clearedAtNanoseconds: UInt64 = 0

    init(aec: MacSpeechAcousticEchoHost) { self.aec = aec }
    func prepare() throws -> MacSpeechLocalPlaybackFormat {
        .init(sampleRate: 48_000, channelCount: 1, sampleFormat: "Float32", isInterleaved: false)
    }
    func schedule(pcm16Bytes: Data, fadeIn: MacSpeechPCMOutputFadeIn?,
                  completion: @escaping @Sendable (Result<Int, MacSpeechAudioOutputHostError>) -> Void)
        throws -> MacSpeechPCMOutputEnvelope.ProcessingResult {
        let processed = MacSpeechPCMOutputEnvelope.processing(to: pcm16Bytes, fadeIn: fadeIn)
        lock.withLock { chunks.append(Chunk(bytes: Array(processed.bytes), completion: completion)) }
        return processed
    }
    func resetForPlaybackGeneration() {}
    func start() throws {
        lock.withLock { running = true; starts += 1 }
        aec.playbackStarted()
    }
    func finishPlayback() {
        lock.withLock { running = false }
        aec.playbackStopped()
    }
    func clearScheduledPlayback() {
        lock.withLock {
            clears += 1; playedAtClear = played
            clearedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
            retired += chunks; chunks.removeAll(); running = false
        }
        aec.playbackStopped()
    }
    func stop() {
        lock.withLock { retired += chunks; chunks.removeAll(); running = false }
        aec.playbackStopped()
    }
    func close() { stop() }
    func tick() -> [Float] {
        var finished: [Chunk] = []
        let samples: [Float] = lock.withLock {
            // Deliver old hardware callbacks after clear, including during N+1.
            if !retired.isEmpty { finished += retired; lateCallbacks += retired.count; retired.removeAll() }
            var samples = [Float](repeating: 0, count: 480)
            guard running else { return samples }
            for index in 0 ..< 240 {
                guard !chunks.isEmpty else { break }
                let offset = chunks[0].offset
                let value = Int16(bitPattern: UInt16(chunks[0].bytes[offset]) | UInt16(chunks[0].bytes[offset + 1]) << 8)
                samples[index * 2] = Float(value) / 32768
                samples[index * 2 + 1] = samples[index * 2]
                chunks[0].offset += 2
                played += 1
                if chunks[0].offset == chunks[0].bytes.count { finished.append(chunks.removeFirst()) }
            }
            return samples
        }
        for chunk in finished { chunk.completion(.success(chunk.bytes.count)) }
        return samples
    }
    var snapshot: (clears: Int, starts: Int, played: Int, postClearPlayed: Int, late: Int, pending: Int, clearedAt: UInt64) {
        lock.withLock { (clears, starts, played, played - playedAtClear, lateCallbacks, chunks.count, clearedAtNanoseconds) }
    }
}

private actor ContinuousWire: RealtimeWebSocketTransport {
    let base: ProbeTransport
    let scripted: R3FakeRealtimeWebSocketTransport?
    private(set) var connects = 0
    private(set) var creates = 0
    private(set) var cancels = 0
    private(set) var finals: [String] = []
    private(set) var failure: String?
    private(set) var active = false
    private(set) var activeSpeechResponses: Set<Int> = []
    private(set) var activeCancelResponses: Set<Int> = []
    let targetRounds: Int
    let injectResponseError: Bool
    let terminalResponses: Bool
    let reassociateAtRound: Int?
    let omitProvisionalPreview: Bool

    init(base: ProbeTransport, scripted: R3FakeRealtimeWebSocketTransport?, targetRounds: Int, injectResponseError: Bool, terminalResponses: Bool, reassociateAtRound: Int?, omitProvisionalPreview: Bool) {
        self.base = base; self.scripted = scripted
        self.targetRounds = targetRounds; self.injectResponseError = injectResponseError
        self.terminalResponses = terminalResponses
        self.reassociateAtRound = reassociateAtRound
        self.omitProvisionalPreview = omitProvisionalPreview
    }
    func connect(endpoint: URL, bearerToken: String) async throws {
        connects += 1
        try await base.connect(endpoint: endpoint, bearerToken: bearerToken)
    }
    func send(_ frame: RealtimeWebSocketFrame) async throws {
        let type = object(frame)?["type"] as? String
        if type == "response.create" {
            creates += 1
            await scripted?.useNextResponseID("continuous-\(creates)")
        }
        if type == "response.cancel" {
            cancels += 1
            if active { activeCancelResponses.insert(creates) }
        }
        try await base.send(frame)
        if type == "response.create", let scripted {
            if injectResponseError && creates == 2 {
                await scripted.enqueueText(#"{"type":"error","error":{"code":"test_response_failure","message":"fixture"}}"#)
                return
            }
            let pcm = (0 ..< 96_000).flatMap { index -> [UInt8] in
                let value = Int16(sin(Double(index) * .pi * 2 * 180 / 24_000) * 9000)
                let bits = UInt16(bitPattern: value)
                return [UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8)]
            }
            for offset in stride(from: 0, to: pcm.count, by: 9600) {
                let bytes = Data(pcm[offset ..< min(offset + 9600, pcm.count)])
                await scripted.enqueueText(#"{"type":"response.audio.delta","response_id":"continuous-\#(creates)","delta":"\#(bytes.base64EncodedString())"}"#)
            }
            if creates == targetRounds + 1 || terminalResponses {
                await scripted.enqueueText(#"{"type":"response.audio.done","response_id":"continuous-\#(creates)"}"#)
                await scripted.enqueueText(#"{"type":"response.done","response":{"id":"continuous-\#(creates)","status":"completed","output":[{"type":"message","content":[{"type":"text","text":"最后一轮正常回答"}]}]}}"#)
            }
        }
    }
    func receive() async throws -> RealtimeWebSocketFrame {
        let frame = try await base.receive()
        if let data = object(frame), let type = data["type"] as? String {
            if type == "response.created" { active = true }
            if type == "response.done" { active = false }
            if type == "input_audio_buffer.speech_started", active {
                activeSpeechResponses.insert(creates)
            }
            if type == "error" { failure = "provider_error_observed" }
            if type == "conversation.item.input_audio_transcription.completed",
               let text = data["transcript"] as? String { finals.append(text) }
        }
        return frame
    }
    func close(reason: RealtimeWebSocketCloseReason) async { await base.close(reason: reason) }
    private func object(_ frame: RealtimeWebSocketFrame) -> [String: Any]? {
        let data: Data
        switch frame { case .text(let text): data = Data(text.utf8); case .binary(let bytes): data = bytes }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    // Only the offline self-test scripts wire events. Live mode never injects
    // transcripts, semantic proposals, cancel ACKs or Provider output.
    func scriptStart(_ index: Int) async {
        guard let scripted else { return }
        await scripted.enqueueText(#"{"type":"input_audio_buffer.speech_started","item_id":"user-\#(index)","audio_start_ms":\#(index * 10000)}"#)
        if index != reassociateAtRound || !omitProvisionalPreview {
            await scripted.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"user-\#(index)","text":"请解释","stash":""}"#)
        }
    }
    func scriptEnd(_ index: Int) async {
        guard let scripted else { return }
        let itemID = index == reassociateAtRound ? "committed-\(index)" : "user-\(index)"
        // The captured round 9 switched item IDs without any provisional-ID
        // preview. Preserve that wire ordering, without replaying private words.
        if index == reassociateAtRound {
            await scripted.enqueueText(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"\#(itemID)","text":"","stash":"请解释"}"#)
        }
        await scripted.enqueueText(#"{"type":"input_audio_buffer.speech_stopped","item_id":"\#(itemID)","audio_end_ms":\#(index * 10000 + 1600)}"#)
        await scripted.enqueueText(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"\#(itemID)","transcript":"请解释你刚才的第\#(index + 1)个观点"}"#)
    }
}

@main
@MainActor
private struct ContinuousQwenProbe {
    static func require(_ condition: Bool, _ code: String) throws {
        if !condition { throw ContinuousProbeFailure(code: code) }
    }
    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]).write(to: url, options: .atomic)
    }
    static func main() async {
        var output: URL?
        var controller: AppController?
        var wire: ContinuousWire?
        var completed: [[String: Any]] = []
        var phase = "arguments"
        var round = 0
        var requireActiveCancel = false
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            func value(_ key: String) -> String? {
                guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            if args.contains("--authorize-keychain") || args.contains("--check-keychain") {
                let attended = args.contains("--authorize-keychain")
                try require(attended != args.contains("--check-keychain")
                    && args.contains("--allow-keychain-interaction") == attended && !args.contains("--live")
                    && !args.contains("--self-test") && !args.contains("--allow-audio-upload") && value("--pcm") == nil,
                    "authorization_requires_local_consent")
                guard let destination = value("--output") else { throw ContinuousProbeFailure(code: "missing_paths") }
                output = URL(fileURLWithPath: destination)
                let reader = ProbeKeychainCredential(diagnostics: NativeSpeechDiagnosticBuffer(),
                    output: URL(fileURLWithPath: destination), allowInteraction: attended)
                defer { reader.discardCachedCredentials() }
                _ = try reader.readCredential(for: ProviderKeychainStore.qwenKeyRef)
                if attended {
                    print("continuous_keychain_authorization=PASS online=NOT_RUN persistent_access=NOT_VERIFIED")
                } else {
                    print("continuous_keychain_check=PASS interaction=false online=NOT_RUN")
                }
                return
            }
            let live = args.contains("--live")
            requireActiveCancel = args.contains("--require-active-cancel")
            try require(live != args.contains("--self-test"), "choose_one_mode")
            try require(!live || args.contains("--allow-audio-upload"), "audio_upload_not_authorized")
            let injectResponseError = args.contains("--inject-response-error")
            let terminalResponses = args.contains("--terminal-responses")
            let reassociationArgument = value("--reassociate-at-round")
            let reassociateAtRound = reassociationArgument.flatMap(Int.init)
            let omitProvisionalPreview = args.contains("--omit-provisional-preview")
            try require(!live || (!injectResponseError && !terminalResponses && !args.contains("--reassociate-at-round") && !omitProvisionalPreview), "live_fault_injection_forbidden")
            try require(live || (!args.contains("--allow-keychain-interaction") && !args.contains("--allow-audio-upload") && value("--pcm") == nil), "self_test_external_access")
            let rounds = Int(value("--rounds") ?? "10") ?? 0
            let seconds = Int(value("--seconds") ?? "300") ?? 0
            try require((1 ... 10).contains(rounds) && (1 ... 300).contains(seconds), "invalid_budget")
            if args.contains("--reassociate-at-round") {
                try require(reassociateAtRound.map { (1 ... rounds).contains($0) } == true, "invalid_reassociation_round")
            }
            try require(!omitProvisionalPreview || reassociateAtRound != nil, "missing_reassociation_round")
            guard let destination = value("--output"), let fixture = value("--fixture") else {
                throw ContinuousProbeFailure(code: "missing_paths")
            }
            let directory = URL(fileURLWithPath: destination, isDirectory: true)
            output = directory
            var pcm: [UInt8]
            if live {
                guard let path = value("--pcm") else { throw ContinuousProbeFailure(code: "missing_pcm") }
                pcm = Array(try Data(contentsOf: URL(fileURLWithPath: path)))
                try require(!pcm.isEmpty && pcm.count <= 960_000 && pcm.count.isMultiple(of: 320), "invalid_pcm")
            } else {
                pcm = (0 ..< 25_600).flatMap { index -> [UInt8] in
                    let value = Int16(sin(Double(index) * .pi * 2 * 570 / 16_000) * 8000)
                    let bits = UInt16(bitPattern: value)
                    return [UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8)]
                }
            }
            let sourcePCMHash = SHA256.hash(data: Data(pcm)).map { String(format: "%02x", $0) }.joined()
            let pcmStart = Int(value("--pcm-start-ms") ?? "0") ?? -1
            let pcmEnd = Int(value("--pcm-end-ms") ?? String(pcm.count / 32)) ?? -1
            try require(pcmStart >= 0 && pcmEnd > pcmStart && pcmEnd <= pcm.count / 32
                && pcmStart.isMultiple(of: 10) && pcmEnd.isMultiple(of: 10), "invalid_pcm_range")
            // Fixture selection only: exact bytes, original rate, no speech or
            // production VAD threshold adjustment. Keep the source file intact.
            pcm = Array(pcm[(pcmStart * 32) ..< (pcmEnd * 32)])
            try write(["schema_version": 1, "source_sha256": sourcePCMHash,
                "start_ms": pcmStart, "end_ms": pcmEnd, "byte_count": pcm.count,
                "selected_sha256": SHA256.hash(data: Data(pcm)).map { String(format: "%02x", $0) }.joined(),
                "require_active_cancel": requireActiveCancel], to: directory.appendingPathComponent("input-selection.json"))
            let diagnostics = NativeSpeechDiagnosticBuffer()
            let scripted = live ? nil : R3FakeRealtimeWebSocketTransport()
            let underlying: any RealtimeWebSocketTransport
            if let scripted { underlying = scripted }
            else { underlying = URLSessionRealtimeWebSocketTransport(diagnosticBuffer: diagnostics, diagnosticRouteKind: .realtimeBrain) }
            let transport = ContinuousWire(base: try ProbeTransport(underlying: underlying,
                output: directory.appendingPathComponent("wire.ndjson"), diagnostics: diagnostics), scripted: scripted,
                targetRounds: rounds, injectResponseError: injectResponseError, terminalResponses: terminalResponses,
                reassociateAtRound: reassociateAtRound, omitProvisionalPreview: omitProvisionalPreview)
            wire = transport
            let credential: any ProviderCredentialReading = live
                ? ProbeKeychainCredential(diagnostics: diagnostics, output: directory,
                    allowInteraction: args.contains("--allow-keychain-interaction"))
                : ProbeFixtureCredential()
            defer { (credential as? ProbeKeychainCredential)?.discardCachedCredentials() }
            let adapter = QwenRealtimeResidentBrainAdapter(credentialReader: credential, transport: transport,
                configuration: QwenRealtimeResidentBrainConfiguration(
                    endpoint: URL(string: "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-omni-plus-realtime")!,
                    keyRef: ProviderKeychainStore.qwenKeyRef, defaultProviderVoiceID: "Tina"), diagnosticBuffer: diagnostics)
            let router = ProviderRouter(credentialReader: credential, realtimeResidentBrainProvider: adapter)
            let runtime = RuntimeCore(executionEngine: ExecutionEngine(providerRouter: router), providerRouter: router, sessionStore: SessionStore())
            runtime.attachNativeSpeechDiagnosticBuffer(diagnostics)
            let backend = R823AECBackend()
            let aec = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
            try require(aec.configure() == .webRTCAEC3, "fixture_backend_configuration")
            let capture = try R823AudioCapture(acousticEchoHost: aec)
            let player = SilentClockedPlayer(aec: aec)
            let outputHost = MacSpeechAudioOutputHost(player: player, deviceMonitor: FakeMacSpeechOutputDeviceMonitor())
            let app = AppController(orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
                speechAudioHost: MacSpeechAudioHost(authorizationProvider: R823AuthorizationProvider(), capture: capture, deviceMonitor: R823DeviceMonitor()),
                speechAudioOutputHost: outputHost, nativeSpeechDiagnosticBuffer: diagnostics)
            controller = app
            app.debugImportResident(from: URL(fileURLWithPath: fixture))
            try require(app.isResidentTextInputAvailable, "fixture_import_failed")
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(seconds))
            phase = "starting"
            try write(["schema_version": 1, "phase": phase, "completed": 0], to: directory.appendingPathComponent("progress.json"))
            await app.startRealtimeResidentBrainRoute()
            try require(app.formalSpeechRouteDebugSnapshot.phase == .listening, "session_start_failed")
            guard let lease = runtime.activeBrainLeaseForTesting(), case .realtimeResidentBrain(let initialGeneration) = lease.generation else {
                throw ContinuousProbeFailure(code: "missing_initial_lease")
            }
            var cursor: Int? = 0
            var playbackReadyAt: UInt64?
            var lastProgress = clock.now
            var history = [[Float]](repeating: [Float](repeating: 0, count: 480), count: 8)
            var tickDue = clock.now
            var tickIndex = 0
            var maxTickLateness = Duration.zero
            var diagnosticsTail: [[String: Any]] = []
            var lastDiagnosticID: UInt64 = 0
            var openingEvidence: UInt64 = 0
            var clearBefore = 0
            var playedBefore = 0
            var finished = false
            var confirmedDecisions = Set<UUID>()
            phase = "initial_input"
            while !finished {
                try require(clock.now < deadline, "total_timeout")
                try require(lastProgress.duration(to: clock.now) < .seconds(40), "phase_timeout_\(phase)")
                if clock.now < tickDue { try await clock.sleep(until: tickDue) }
                let lateness = tickDue.duration(to: clock.now)
                maxTickLateness = max(maxTickLateness, lateness)
                try require(lateness < .milliseconds(100), "virtual_device_pacing_overrun")
                tickDue = clock.now.advanced(by: .milliseconds(10))
                let timestamp = DispatchTime.now().uptimeNanoseconds
                let render = player.tick()
                let delayedRender = history.removeFirst()
                history.append(render)
                if aec.acousticObservationSnapshot().isPlaybackActive {
                    aec.processRender(render, hostTimeNanoseconds: timestamp)
                }
                var nearEnd = [Float](repeating: 0, count: 480)
                if let offset = cursor {
                    for sample in 0 ..< 160 {
                        let i = offset + sample * 2
                        let value = Float(Int16(bitPattern: UInt16(pcm[i]) | UInt16(pcm[i + 1]) << 8)) / 32768
                        for repeatIndex in 0 ..< 3 { nearEnd[sample * 3 + repeatIndex] = value }
                    }
                    cursor = offset + 320 == pcm.count ? nil : offset + 320
                    if !live && offset == 6400 { await transport.scriptStart(round) }
                    if cursor == nil {
                        await transport.scriptEnd(round)
                        phase = round == 0 ? "await_initial_reply" : "await_rebound"
                        lastProgress = clock.now
                    }
                }
                // Acoustic backend is an explicit post-AEC test fixture, not
                // the WebRTC implementation. Host classifier/gates run normally.
                backend.setCaptureOutput(nearEnd)
                let raw = zip(nearEnd, delayedRender).map { $0 + $1 * 0.25 }
                let before = aec.acousticObservationSnapshot()
                let processed = aec.processCapture(raw, hostTimeNanoseconds: timestamp)
                _ = try capture.emit(processedSamples: processed, acousticBefore: before)
                tickIndex += 1
                if tickIndex % 10 != 0 { continue }
                await app.refreshMicrophoneAuthorization()
                let route = app.formalSpeechRouteDebugSnapshot
                try require(route.lastErrorCode == nil && route.phase != .failed && route.phase != .idle, route.lastErrorCode ?? "route_stopped")
                try require(await transport.failure == nil, "provider_error_observed")
                let currentLease = runtime.activeBrainLeaseForTesting()
                try require(currentLease?.brainLeaseID == lease.brainLeaseID && currentLease?.runtimeSessionID == lease.runtimeSessionID
                    && currentLease?.routeEpoch == lease.routeEpoch, "session_or_lease_replaced")
                let playback = player.snapshot
                let input = app.realtimeBrainInputBridgeSnapshot
                let cancels = await transport.cancels
                let creates = await transport.creates
                try require(cancels <= round && playback.clears <= round && creates <= round + 1, "duplicate_control_effect")
                try require((route.generation ?? 0) <= initialGeneration + UInt64(round), "extra_generation_advance")
                let evidence = runtime.realtimeInterruptionEvidenceDebugSnapshot()
                if completed.count < rounds, cursor == nil, evidence.playbackTarget?.session.generation == initialGeneration + UInt64(round),
                   playback.played > playedBefore, creates == round + 1 {
                    if playbackReadyAt == nil { playbackReadyAt = timestamp }
                    if timestamp - playbackReadyAt! >= 300_000_000 {
                        if round > 0 {
                            let canonical = runtime.realtimeUserTurnDispositionDebugSnapshot().lastCanonicalTranscript ?? ""
                            let finals = await transport.finals
                            try require(finals.count == round + 1 && !canonical.isEmpty && canonical == finals.last, "canonical_content_not_preserved")
                            guard let confirmation = runtime.realtimeInterruptionTimingForTesting() else {
                                throw ContinuousProbeFailure(code: "missing_confirmed_decision")
                            }
                            try require(confirmation.interruptedIdentity.generation == initialGeneration + UInt64(round - 1)
                                && confirmedDecisions.insert(confirmation.decisionID).inserted
                                && playback.clears == round && route.generation == initialGeneration + UInt64(round), "missing_confirmed_handoff")
                            try require(playback.clearedAt >= confirmation.confirmedAtNanoseconds
                                && playback.clearedAt - confirmation.confirmedAtNanoseconds <= 50_000_000, "confirmed_to_clear_latency")
                            try require(input.hasActivePump && app.realtimeBrainOutputBridgeSnapshot.hasActiveReceiveLoop, "rebound_loop_missing")
                            try require(playback.postClearPlayed > 0, "no_new_audio_after_clear")
                            let activeAtSpeechStart = await transport.activeSpeechResponses.contains(round)
                            let activeAtCancel = await transport.activeCancelResponses.contains(round)
                            if requireActiveCancel {
                                try require(activeAtSpeechStart && activeAtCancel && cancels == round,
                                    "coverage_missing_active_generation_cancel")
                            }
                            let record: [String: Any] = ["round": round, "generation": route.generation ?? 0,
                                "session_unchanged": true, "canonical_matches_provider_final": true,
                                "canonical_sha256": hash(canonical), "canonical_length": canonical.count,
                                "cancels": cancels, "clears": playback.clears, "creates": creates,
                                "provider_active_at_speech_start": activeAtSpeechStart,
                                "provider_active_at_cancel_submission": activeAtCancel,
                                "unique_confirmed_decisions": confirmedDecisions.count,
                                "confirmed_to_clear_ms": Double(playback.clearedAt - confirmation.confirmedAtNanoseconds) / 1_000_000,
                                "post_clear_played_samples": playback.postClearPlayed,
                                "late_callbacks_delivered": playback.late,
                                "acoustic_evidence_before": openingEvidence, "acoustic_evidence_after": input.acousticEvidenceCount]
                            completed.append(record)
                            try write(["schema_version": 1, "completed": completed, "human_gate": "NOT_RUN"], to: directory.appendingPathComponent("rounds.json"))
                            print("continuous_round=\(round) PASS generation=\(route.generation ?? 0)")
                            if completed.count == rounds {
                                phase = "final_reply_drain"
                                lastProgress = clock.now
                                continue
                            }
                        } else {
                            try require(cancels == 0 && playback.clears == 0, "resident_only_false_interrupt")
                        }
                        round += 1
                        phase = "overlap_input"
                        cursor = 0
                        playedBefore = playback.played
                        clearBefore = playback.clears
                        openingEvidence = input.acousticEvidenceCount
                        playbackReadyAt = nil
                        lastProgress = clock.now
                        try write(["schema_version": 1, "phase": phase, "round": round, "completed": completed.count,
                            "provider_active_at_overlap": await transport.active], to: directory.appendingPathComponent("progress.json"))
                    }
                } else { playbackReadyAt = nil }
                if completed.count == rounds && route.phase == .listening && evidence.playbackTarget == nil && playback.pending == 0 {
                    finished = true
                }
                // Metadata only: never persist canonical text, raw Provider IDs,
                // resident contents or credentials in diagnostics.
                let newEvents = app.realtimeSpeechDiagnosticTimeline.events.filter { $0.id > lastDiagnosticID }
                let responseFailed = newEvents.contains { $0.category == "recoverable_response_error" }
                if let latest = newEvents.last { lastDiagnosticID = latest.id }
                diagnosticsTail += newEvents.map {
                    ["category": $0.category, "disposition": $0.disposition ?? "none",
                     "error": $0.errorCode ?? "none", "elapsed_ms": String($0.elapsedMilliseconds)]
                }
                try require(diagnosticsTail.count <= 20_000, "diagnostic_capacity_exceeded")
                if tickIndex % 50 == 0 || responseFailed {
                    try write(["schema_version": 1, "phase": phase, "round": round,
                        "route_phase": route.phase.rawValue, "session_unchanged": true,
                        "input_pump_active": input.hasActivePump,
                        "output_loop_active": app.realtimeBrainOutputBridgeSnapshot.hasActiveReceiveLoop,
                        "generation": route.generation ?? 0, "clears": playback.clears, "clear_before": clearBefore,
                        "acoustic_evidence": input.acousticEvidenceCount, "source_gated_frames": input.sourceGatedNearEndFrameCount,
                        "forwarded_frames": input.forwardedFrameCount, "input_error": input.lastError ?? "none",
                        "playback_starts": playback.starts, "played_samples": playback.played, "pending_chunks": playback.pending,
                        "playback_target_present": evidence.playbackTarget != nil,
                        "output_chunks": app.realtimeBrainOutputBridgeSnapshot.audioChunkCount,
                        "output_error": app.realtimeBrainOutputBridgeSnapshot.lastError ?? "none",
                        "classification": aec.acousticObservationSnapshot().inputClassification.rawValue,
                        "source_gate_open": aec.acousticObservationSnapshot().sourceGateOpen,
                        "events": diagnosticsTail], to: directory.appendingPathComponent("diagnostics.json"))
                }
                try require(!responseFailed, "recoverable_response_error")
            }
            try require(await transport.connects == 1, "not_one_connection")
            phase = "stopping"
            await app.stopSpeechAudioCapture()
            try require(app.formalSpeechRouteDebugSnapshot.phase == .idle, "stop_did_not_finish")
            try write(["schema_version": 1, "outcome": "PASS", "mode": live ? "live" : "self-test",
                "completed_rounds": completed.count, "connections": await transport.connects,
                "require_active_cancel": requireActiveCancel,
                "records": completed, "max_tick_lateness": String(describing: maxTickLateness),
                "final_reply_drained": true,
                "pcm_sha256": SHA256.hash(data: Data(pcm)).map { String(format: "%02x", $0) }.joined(),
                "aec_backend": "FIXTURE_NOT_WEBRTC", "hardware": "SILENT_CLOCKED_TEST_DEVICE",
                "semantic_answer_correctness": "NOT_ASSESSED", "human_gate": "NOT_RUN"], to: directory.appendingPathComponent("report.json"))
            print("continuous_probe=PASS rounds=\(completed.count) connections=1 human_gate=NOT_RUN")
        } catch {
            let code = (error as? ContinuousProbeFailure)?.code ?? (error as? ProbeError)?.rawValue ?? "configuration_or_io_failure"
            let outcome = code.hasPrefix("coverage_") ? "COVERAGE_NOT_MET" : "FAIL"
            if let output {
                do {
                    try write(["schema_version": 1, "outcome": outcome, "error": code, "phase": phase,
                        "require_active_cancel": requireActiveCancel,
                        "round": round, "completed_rounds": completed.count, "records": completed,
                        "human_gate": "NOT_RUN"], to: output.appendingPathComponent("report.json"))
                } catch { print("continuous_evidence_write=FAIL") }
            }
            print("continuous_probe=\(outcome) error=\(code) completed=\(completed.count)")
            // Preserve first failure before bounded external-watchdog teardown.
            if let controller { await controller.stopSpeechAudioCapture() }
            if let wire { await wire.close(reason: .cancelled) }
            exit(1)
        }
    }
}
#endif
