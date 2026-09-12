#if DEBUG
import AppKit
import AVFoundation
import CryptoKit
import Foundation

@MainActor
enum Test3LocalAudioRunner {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--test3-local-audio-preflight")
            || CommandLine.arguments.contains("--test3-local-audio")
    }

    static func start() {
        if CommandLine.arguments.contains("--test3-local-audio-preflight") {
            do {
                let root = try testRoot()
                let authorization = microphoneAuthorization()
                try printJSON([
                    "schema_version": 1, "microphone_authorization": authorization,
                    "authorized": authorization == "authorized", "test_root": root.path,
                    "permission_requested": false, "qwen_calls": 0
                ])
                exit(0)
            } catch {
                try? printJSON(["schema_version": 1, "error": String(describing: error)])
                exit(1)
            }
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await run()
                exit(0)
            } catch {
                try? printJSON(["status": "FAILED", "error": String(describing: error)])
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    private static func testRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("test3-local-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private static func microphoneAuthorization() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "authorized"
        case .notDetermined: "not_determined"
        case .denied: "denied"
        case .restricted: "restricted"
        @unknown default: "unknown"
        }
    }

    private static func run() async throws {
        guard let index = CommandLine.arguments.firstIndex(of: "--test3-local-audio"),
              CommandLine.arguments.indices.contains(index + 1) else {
            throw RunnerError.invalidConfiguration
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            .resolvingSymlinksInPath()
        guard directory.path.hasPrefix(try testRoot().path + "/") else {
            throw RunnerError.invalidConfiguration
        }
        let configuration = try JSONDecoder().decode(Configuration.self,
            from: Data(contentsOf: directory.appendingPathComponent("config.json")))
        guard configuration.schema_version == 1 else { throw RunnerError.invalidConfiguration }
        let residentURL = try localFile(configuration.resident_file, in: directory)
        let nearURL = try localFile(configuration.near_file, in: directory)
        let fixtureURL = try localFile(configuration.fixture_file, in: directory)
        let resident = try samples(at: residentURL)
        let near = try samples(at: nearURL)
        var results: [[String: Any]] = []
        let cases: [(String, Float, Bool)] = [
            ("normal_echo_only", 0.5, false), ("normal_software_near", 0.5, true),
            ("higher_echo_only", 1, false), ("higher_software_near", 1, true)
        ]
        for (name, gain, positive) in cases {
            let caseDirectory = directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
            var result: [String: Any]
            do {
                guard microphoneAuthorization() == "authorized" else {
                    throw RunnerError.microphoneNotAuthorized
                }
                result = try await runCase(name: name, gain: gain, positive: positive,
                    resident: resident, near: near, fixture: fixtureURL, directory: caseDirectory)
            } catch {
                result = ["case": name, "status": "FAIL", "error": String(describing: error)]
            }
            results.append(result)
            try writeJSON(result, to: caseDirectory.appendingPathComponent("result.json"))
            try writeJSON([
                "schema_version": 1, "status": results.count == cases.count ? "COMPLETED" : "RUNNING",
                "qwen_calls": 0, "permission_requested": false,
                "semantic_source": "local_stub_fixture_after_runtime_acoustic_evidence",
                "physical_double_talk": "NOT_TESTED_BY_SOFTWARE_INJECTION",
                "gain_description": "Relative PCM gain only; system volume unchanged; SPL not calibrated",
                "resident_sha256": try sha256(residentURL), "near_sha256": try sha256(nearURL),
                "cases": results
            ], to: directory.appendingPathComponent("result.json"))
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private static func runCase(name: String, gain: Float, positive: Bool,
        resident: [Float], near: [Float], fixture: URL, directory: URL) async throws -> [String: Any] {
        let files = IsolatedFileManager(root: directory.appendingPathComponent("stores", isDirectory: true))
        let store = SessionStore(fileManager: files)
        let provider = LocalProvider()
        let router = ProviderRouter(credentialReader: NoCredentials(), realtimeResidentBrainProvider: provider)
        let runtime = RuntimeCore(executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router, sessionStore: store,
            memoryController: MemoryController(store: MemoryStore(fileManager: files)))
        runtime.useNarrativeMemoryStoreForTesting(NarrativeMemoryStore(fileManager: files))
        runtime.useRelationshipStateStoreForTesting(RelationshipStateStore(fileManager: files))
        let engine = SystemMacSpeechVoiceProcessingEngine(audioProcessingMode: .webRTCAEC3)
        let audioHost = MacSpeechAudioHost(authorizationProvider: NoPromptAuthorization(),
            capture: SystemMacSpeechAudioCapture(audioEngine: engine))
        let outputHost = MacSpeechAudioOutputHost(player: SystemMacSpeechAudioOutputPlayer(audioEngine: engine))
        let playbackObservations = PlaybackObservations()
        await outputHost.observePlaybackForTesting { playbackObservations.append($0) }
        let controller = AppController(orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
            speechAudioHost: audioHost, speechAudioOutputHost: outputHost,
            realtimeSpeechDiagnosticAudioEngine: engine, restoreProviderSettings: false)
        controller.debugImportTestResident(from: fixture)
        let attemptID = UUID()
        let captureArmed = engine.armAcousticReplayCapture(attemptID: attemptID, targetCaptureFrameCount: 1_100)
        await controller.startRealtimeResidentBrainRoute()
        guard await wait(seconds: 5, until: {
            let hasSession = await provider.lastSession() != nil
            return controller.formalSpeechRouteDebugSnapshot.phase == .listening && hasSession
        }), let session = await provider.lastSession() else {
            await controller.shutdownSpeechAudioHost()
            throw RunnerError.routeNotListening
        }
        let aec = engine.acousticEchoSnapshot()
        guard aec.mode == .webRTCAEC3, aec.enabled, aec.fallbackCount == 0 else {
            await controller.shutdownSpeechAudioHost()
            throw RunnerError.aecUnavailable
        }
        let identity = RealtimeBrainEventIdentity(session: session, turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(), contextRevision: await provider.contextRevision())
        await provider.enqueue(RealtimeResidentBrainEvent(identity: RealtimeBrainEventIdentity(
            session: session, turnID: identity.turnID, responseID: nil, contextRevision: identity.contextRevision),
            sequence: 2, kind: .userTranscriptFinal("Local Test 3 playback fixture")))
        var initialTiming = await outputHost.timingDebugSnapshot()
        let initialHost = engine.acousticEchoSnapshot()
        let initialAcousticEvidenceCount = controller.realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        var initialProvider = await provider.counts()
        var audioSequence: UInt64 = 1
        var nextAudioAt = now()
        var playbackAt: UInt64?
        var injectionScheduledAt: UInt64?
        var semanticAt: UInt64?
        var firstAcousticAt: UInt64?
        var firstForwardAt: UInt64?
        var firstGateAt: UInt64?
        var preInjectionGateOpens: UInt64 = 0
        var preInjectionForwards: UInt64 = 0
        var maximumRawRMS = 0.0
        var maximumRenderRMS = 0.0
        var acousticBeforeInjection = false
        var lastObservedFrame: UInt64 = 0
        var polling: [[String: Any]] = []
        let started = now()
        var dialogueBaseline: [SessionDialogueEntry]?
        var memoryBaseline: RuntimeNarrativeMemoryStoreSnapshot?
        var relationshipBaseline: RuntimeRelationshipInstanceState?
        while now() - started < 11_500_000_000 {
            let time = now()
            let providerCounts = await provider.counts()
            if time >= nextAudioAt, audioSequence <= 105, semanticAt == nil, providerCounts.interrupt == 0 {
                let bytes = pcmChunk(resident, offset: Int(audioSequence - 1) * 4_800,
                    sampleCount: 4_800, gain: gain)
                await provider.enqueue(RealtimeResidentBrainEvent(identity: identity,
                    sequence: audioSequence + 2,
                    kind: .residentAudioDelta(RealtimeBrainAudioDelta(sequence: audioSequence,
                        timestampNanoseconds: time, format: RealtimeBrainAudioFormat(
                            encoding: .pcm16LittleEndian, sampleRate: 24_000, channelCount: 1),
                        provenance: .providerGenerated, bytes: bytes))))
                audioSequence += 1
                nextAudioAt = time + 80_000_000
            }
            await controller.refreshMicrophoneAuthorization()
            let snapshot = engine.acousticEchoSnapshot()
            let observation = engine.acousticObservationSnapshot()
            let evidence = runtime.realtimeInterruptionEvidenceDebugSnapshot()
            if snapshot.isPlaybackActive, playbackAt == nil {
                playbackAt = time
                initialTiming = await outputHost.timingDebugSnapshot()
                initialProvider = await provider.counts()
                dialogueBaseline = (try? store.loadMostRecentDialogueEntries(limit: 100)) ?? []
                memoryBaseline = runtime.narrativeMemoryDebugSnapshot()
                relationshipBaseline = runtime.currentRelationshipState
                if positive {
                    injectionScheduledAt = time + 3_000_000_000
                    engine.setTest3NearEndInjection(samples: near, startAtNanoseconds: injectionScheduledAt!)
                }
            }
            let injection = engine.test3NearEndInjectionSnapshot()
            if snapshot.isPlaybackActive, injection.startedAtNanoseconds == nil {
                preInjectionGateOpens = snapshot.sourceGateOpenCount &- initialHost.sourceGateOpenCount
                preInjectionForwards = snapshot.sourceForwardedFrameCount &- initialHost.sourceForwardedFrameCount
                if evidence.hasAcousticEvidence { acousticBeforeInjection = true }
            }
            if snapshot.isPlaybackActive, snapshot.sourceGateOpen, firstGateAt == nil { firstGateAt = time }
            if snapshot.isPlaybackActive, snapshot.sourceForwardedFrameCount > initialHost.sourceForwardedFrameCount,
               firstForwardAt == nil { firstForwardAt = time }
            if snapshot.isPlaybackActive, evidence.hasAcousticEvidence, firstAcousticAt == nil { firstAcousticAt = time }
            if positive, injection.injectedSampleCount > 0, evidence.hasAcousticEvidence,
               evidence.session == session, semanticAt == nil, snapshot.isPlaybackActive {
                semanticAt = time
                await provider.enqueue(RealtimeResidentBrainEvent(identity: identity, sequence: audioSequence + 2,
                    kind: .interruptionProposed(RealtimeBrainInterruptionProposal(identity: identity,
                        reason: "user_speech_started_during_resident_response"))))
            }
            if observation.captureFrameIndex != lastObservedFrame {
                lastObservedFrame = observation.captureFrameIndex
                maximumRawRMS = max(maximumRawRMS, snapshot.rawCaptureRMS)
                maximumRenderRMS = max(maximumRenderRMS, observation.renderReferenceRMS ?? 0)
                polling.append([
                    "observed_at_ns": time, "capture_frame": snapshot.captureFrameCount,
                    "capture_at_ns": observation.captureHostTimeNanoseconds as Any? ?? NSNull(),
                    "playback_active": snapshot.isPlaybackActive, "source_gate_open": snapshot.sourceGateOpen,
                    "source_gate_open_count": snapshot.sourceGateOpenCount,
                    "source_forwarded_frames": snapshot.sourceForwardedFrameCount,
                    "raw_rms": snapshot.rawCaptureRMS, "clean_rms": snapshot.processedCaptureRMS,
                    "linear_rms": snapshot.linearAECOutputRMS,
                    "render_rms": observation.renderReferenceRMS as Any? ?? NSNull(),
                    "raw_render_correlation": snapshot.renderCaptureCorrelation,
                    "residual_render_correlation": snapshot.residualRenderCorrelation,
                    "processed_linear_correlation": snapshot.processedLinearCorrelation,
                    "classification": snapshot.inputClassification.rawValue,
                    "runtime_acoustic": evidence.hasAcousticEvidence,
                    "generation": controller.formalSpeechRouteDebugSnapshot.generation as Any? ?? NSNull()
                ])
            }
            if let playbackAt, time - playbackAt >= 10_500_000_000 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        engine.sealAcousticReplayCapture(matchingAttemptID: attemptID)
        let capsule = engine.acousticReplayCaptureSnapshot()
        let injection = engine.test3NearEndInjectionSnapshot()
        let finalHost = engine.acousticEchoSnapshot()
        let finalTiming = await outputHost.timingDebugSnapshot()
        let output = await outputHost.currentSnapshot()
        let input = await audioHost.currentSnapshot()
        let finalProvider = await provider.counts()
        let confirmed = runtime.realtimeInterruptionTimingForTesting()
        let finalGeneration = controller.formalSpeechRouteDebugSnapshot.generation
        let history = (try? store.loadMostRecentDialogueEntries(limit: 100)) ?? []
        let historyCount = history.count
        let finalAcousticEvidenceCount = controller.realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        let memoryUnchanged = runtime.narrativeMemoryDebugSnapshot() == memoryBaseline
        let relationshipUnchanged = runtime.currentRelationshipState == relationshipBaseline
        let clearDelta = finalTiming.clearCompletionCount &- initialTiming.clearCompletionCount
        let interruptDelta = finalProvider.interrupt - initialProvider.interrupt
        let cancelDelta = finalProvider.cancel - initialProvider.cancel
        let createDelta = finalProvider.create - initialProvider.create
        let frames = capsule?.captureFrames ?? []
        let playbackFrames = frames.filter(\.isPlaybackActive)
        let echoFrames = playbackFrames.filter {
            guard let injectionAt = injection.startedAtNanoseconds else { return true }
            return ($0.captureHostTimeNanoseconds ?? $0.timestampNanoseconds) < injectionAt
        }
        let preInjectionGateFrames = echoFrames.filter(\.sourceGateOpen).count
        let preInjectionForwardedSpans = echoFrames.flatMap(\.emittedSpans).filter { !$0.silenced }.count
        let playbackTimes = playbackFrames.map { $0.captureHostTimeNanoseconds ?? $0.timestampNanoseconds }
        let captureCoverageMilliseconds = playbackTimes.count > 1
            ? Double(playbackTimes.last! - playbackTimes.first!) / 1_000_000 + 10 : 0
        let maximumCaptureGapMilliseconds = zip(playbackTimes, playbackTimes.dropFirst()).map {
            $1 >= $0 ? Double($1 - $0) / 1_000_000 : Double(UInt64.max)
        }.max() ?? 0
        let couplingFrames = echoFrames.filter {
            $0.rawCaptureRMS > 0.001 && ($0.renderReferenceRMS ?? 0) > 0.001
                && ($0.timingCorrelation ?? 0) >= 0.65
        }.count
        let gateFrames = playbackFrames.filter(\.sourceGateOpen).count
        let forwardedSpans = playbackFrames.flatMap(\.emittedSpans).filter { !$0.silenced }.count
        let firstRecordedGate = playbackFrames.first(where: \.sourceGateOpen)
            .map { $0.captureHostTimeNanoseconds ?? $0.timestampNanoseconds }
        var clearLatencyMilliseconds: Double?
        if let confirmed, finalTiming.lastClearCompletedAtNanoseconds >= confirmed.confirmedAtNanoseconds,
           clearDelta > 0 {
            clearLatencyMilliseconds = Double(finalTiming.lastClearCompletedAtNanoseconds
                - confirmed.confirmedAtNanoseconds) / 1_000_000
        }
        let playbackEvents = playbackObservations.snapshot()
        let stalePlayback = playbackEvents.filter {
            clearDelta > 0 && $0.time >= finalTiming.lastClearCompletedAtNanoseconds
                && $0.generation == initialTiming.generation && ($0.kind == "scheduled" || $0.accepted == true)
        }.count
        var failures: [String] = []
        if stalePlayback > 0 { failures.append("Old generation playback accepted after clear") }
        if finalHost.mode != .webRTCAEC3 || finalHost.fallbackCount > 0 { failures.append("AEC fallback") }
        if playbackAt == nil || output.playbackStartedCount == 0 { failures.append("No actual playback") }
        if !captureArmed || frames.isEmpty { failures.append("Missing 10 ms capture evidence") }
        if createDelta != 0 { failures.append("Unexpected response.create") }
        if cancelDelta != 0 { failures.append("Unexpected separate cancelGeneration") }
        if history != dialogueBaseline { failures.append("Unexpected dialogue persistence or content mutation") }
        if !input.isCapturing || input.lastError != nil || output.lastError != nil {
            failures.append("Capture/output ended in an unavailable or error state")
        }
        if input.droppedFrameCount > 0 { failures.append("Capture frame buffer dropped audio") }
        if !memoryUnchanged || !relationshipUnchanged { failures.append("Unexpected memory/relationship mutation") }
        if positive {
            if injection.injectedSampleCount == 0 { failures.append("Software near-end not injected") }
            if preInjectionGateFrames != 0 || preInjectionForwardedSpans != 0
                || preInjectionGateOpens != 0 || preInjectionForwards != 0 || acousticBeforeInjection {
                failures.append("Echo-only prefix opened source gate")
            }
            if firstAcousticAt == nil || semanticAt == nil || forwardedSpans == 0 {
                failures.append("Injected near-end did not reach Runtime acoustic evidence")
            }
            if interruptDelta != 1 || clearDelta != 1 || finalGeneration != session.generation + 1 {
                failures.append("Expected exactly one Runtime interrupt, clear and generation advance")
            }
            if clearLatencyMilliseconds == nil || clearLatencyMilliseconds! > 50 {
                failures.append("Confirmed interrupt to clear exceeds 50 ms or missing")
            }
        } else {
            if playbackFrames.count < 800 || captureCoverageMilliseconds < 8_000
                || maximumCaptureGapMilliseconds > 200 {
                failures.append("Insufficient continuous capture during resident playback")
            }
            if finalAcousticEvidenceCount != initialAcousticEvidenceCount {
                failures.append("Echo-only emitted Runtime acoustic evidence")
            }
            if gateFrames != 0 || forwardedSpans != 0 || firstAcousticAt != nil {
                failures.append("Echo-only produced user acoustic evidence or forwarded audio")
            }
            if interruptDelta != 0 || clearDelta != 0 || finalGeneration != session.generation {
                failures.append("Echo-only changed interruption ownership")
            }
        }
        let status = !failures.isEmpty ? "FAIL" : couplingFrames < 20 ? "INCONCLUSIVE" : "PASS"
        var result: [String: Any] = [
            "case": name, "status": status, "failures": failures, "resident_gain": gain,
            "positive_input": positive, "qwen_calls": 0,
            "microphone": ["id": input.inputDevice.identifier, "name": input.inputDevice.name],
            "speaker": ["id": output.outputDevice.identifier, "name": output.outputDevice.name],
            "capture_sample_rate": input.actualSampleRate as Any? ?? NSNull(),
            "aec_mode": finalHost.mode.rawValue, "aec_fallback_count": finalHost.fallbackCount,
            "coupled_echo_frames": couplingFrames, "minimum_coupled_echo_frames": 20,
            "coupling_criterion": "20 playback frames with raw/render RMS > .001 and matched correlation >= .65",
            "playback_frames": playbackFrames.count,
            "playback_capture_coverage_ms": captureCoverageMilliseconds,
            "maximum_capture_gap_ms": maximumCaptureGapMilliseconds,
            "input_is_capturing_at_end": input.isCapturing, "input_state": input.state.rawValue,
            "input_dropped_frames": input.droppedFrameCount,
            "input_rejected_stale_frames": input.rejectedStaleFrameCount,
            "input_error": input.lastError.map { String(describing: $0) } as Any? ?? NSNull(),
            "output_error": output.lastError.map { String(describing: $0) } as Any? ?? NSNull(),
            "output_state": output.state.rawValue,
            "acoustic_evidence_before": initialAcousticEvidenceCount,
            "acoustic_evidence_after": finalAcousticEvidenceCount, "playback_gate_open_frames": gateFrames,
            "playback_forwarded_spans": forwardedSpans, "pre_injection_gate_opens": preInjectionGateOpens,
            "pre_injection_forwarded_frames": preInjectionForwards,
            "pre_injection_gate_open_frames_exact": preInjectionGateFrames,
            "pre_injection_forwarded_spans_exact": preInjectionForwardedSpans,
            "maximum_raw_rms": maximumRawRMS, "maximum_render_rms": maximumRenderRMS,
            "playback_started_at_ns": playbackAt as Any? ?? NSNull(),
            "injection_scheduled_at_ns": injectionScheduledAt as Any? ?? NSNull(),
            "injection_started_at_ns": injection.startedAtNanoseconds as Any? ?? NSNull(),
            "injected_sample_count": injection.injectedSampleCount,
            "first_source_gate_at_ns": firstRecordedGate as Any? ?? firstGateAt as Any? ?? NSNull(),
            "first_forward_observed_at_ns": firstForwardAt as Any? ?? NSNull(),
            "first_runtime_acoustic_observed_at_ns": firstAcousticAt as Any? ?? NSNull(),
            "fixture_semantic_proposal_at_ns": semanticAt as Any? ?? NSNull(),
            "generation_before": session.generation, "generation_after": finalGeneration as Any? ?? NSNull(),
            "interrupt_count": interruptDelta, "cancel_generation_count": cancelDelta,
            "clear_count": clearDelta, "response_create_count": createDelta,
            "stale_playback_count": stalePlayback, "self_interrupt_count": (positive ? nil : interruptDelta) as Any? ?? NSNull(),
            "confirmed_to_clear_ms": clearLatencyMilliseconds as Any? ?? NSNull(),
            "confirmed_to_clear_limit_ms": 50, "dialogue_entries_before": dialogueBaseline?.count as Any? ?? NSNull(),
            "dialogue_entries_after": historyCount, "memory_unchanged": memoryUnchanged,
            "relationship_unchanged": relationshipUnchanged, "provider_audio_frames": finalProvider.audio,
            "capture_armed": captureArmed, "capture_frame_count": frames.count,
            "polling_is_decimated": true, "exact_10ms_metrics_file": "capture-frames.json"
        ]
        if couplingFrames < 20 { result["evidence_limitation"] = "Insufficient measured speaker-to-microphone echo coupling" }
        try JSONEncoder().encode(controller.realtimeSpeechDiagnosticTimeline.events)
            .write(to: directory.appendingPathComponent("runtime-events.json"))
        engine.clearTest3NearEndInjection()
        await controller.stopRealtimeFullDuplexSpeech()
        await controller.shutdownSpeechAudioHost()
        try writeJSON(polling, to: directory.appendingPathComponent("runtime-polling.json"))
        try JSONEncoder().encode(playbackEvents).write(to: directory.appendingPathComponent("playback-events.json"))
        if let capsule { try save(capsule, directory: directory) }
        return result
    }

    private static func save(_ capture: MacSpeechAcousticReplayCaptureSnapshot, directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(capture.captureFrames).write(to: directory.appendingPathComponent("capture-frames.json"))
        try encoder.encode(capture.renderFrames).write(to: directory.appendingPathComponent("render-frames.json"))
        try encoder.encode(capture.audioCalls).write(to: directory.appendingPathComponent("audio-calls.json"))
        try encoder.encode(capture.controlEvents).write(to: directory.appendingPathComponent("control-events.json"))
        try encoder.encode(capture.initialState).write(to: directory.appendingPathComponent("initial-state.json"))
        try encoder.encode(capture.finalState).write(to: directory.appendingPathComponent("final-state.json"))
        for (name, samples) in [("raw-mic-48k", capture.rawMicrophoneSamples),
            ("render-48k", capture.chronologicalRenderSamples), ("clean-48k", capture.aecCleanSamples),
            ("linear-16k", capture.aecLinearSamples)] {
            try samples.withUnsafeBytes { Data($0) }
                .write(to: directory.appendingPathComponent(name + ".f32le.pcm"))
        }
    }

    private static func pcmChunk(_ samples: [Float], offset: Int, sampleCount: Int, gain: Float) -> Data {
        var pcm = [Int16]()
        pcm.reserveCapacity(sampleCount / 2)
        for index in stride(from: 0, to: sampleCount, by: 2) {
            let value = (samples[(offset + index) % samples.count]
                + samples[(offset + index + 1) % samples.count]) * 0.5 * gain
            pcm.append(Int16((max(-1, min(1, value)) * 32_767).rounded()).littleEndian)
        }
        return pcm.withUnsafeBytes { Data($0) }
    }

    private static func samples(at url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.count.isMultiple(of: 4), data.count <= 48_000 * 4 * 30 else {
            throw RunnerError.invalidPCM
        }
        let values = data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 4).map {
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
            }
        }
        guard values.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { throw RunnerError.invalidPCM }
        return values
    }

    private static func localFile(_ name: String, in directory: URL) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw RunnerError.invalidConfiguration
        }
        let url = directory.appendingPathComponent(name).resolvingSymlinksInPath()
        guard url.deletingLastPathComponent() == directory else { throw RunnerError.invalidConfiguration }
        return url
    }

    private static func wait(seconds: Double, until condition: () async -> Bool) async -> Bool {
        let start = now()
        while Double(now() - start) / 1_000_000_000 < seconds {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    private static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
    private static func writeJSON(_ object: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
    private static func printJSON(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        FileHandle.standardOutput.write(data + Data([10]))
    }

    private struct Configuration: Decodable {
        let schema_version: Int
        let resident_file: String
        let near_file: String
        let fixture_file: String
    }
    private enum RunnerError: Error {
        case invalidConfiguration, invalidPCM, microphoneNotAuthorized, routeNotListening, aecUnavailable
    }
    nonisolated private struct NoCredentials: ProviderCredentialReading {
        nonisolated func readCredential(for keyRef: String) throws -> String? { nil }
    }
    nonisolated private struct NoPromptAuthorization: MicrophoneAuthorizationProviding {
        nonisolated func currentAuthorization() async throws -> MicrophoneAuthorizationState {
            try await SystemMicrophoneAuthorizationProvider().currentAuthorization()
        }
        nonisolated func requestAuthorization() async throws -> MicrophoneAuthorizationState {
            try await currentAuthorization()
        }
    }
    nonisolated private final class IsolatedFileManager: FileManager, @unchecked Sendable {
        let root: URL
        init(root: URL) { self.root = root; super.init() }
        override func urls(for directory: FileManager.SearchPathDirectory,
            in domainMask: FileManager.SearchPathDomainMask) -> [URL] { [root] }
        override var temporaryDirectory: URL { root }
    }

    nonisolated private final class PlaybackObservations: @unchecked Sendable {
        struct Entry: Codable, Sendable {
            let time: UInt64
            let generation: UInt64
            let sequence: UInt64
            let kind: String
            let accepted: Bool?
        }
        private let lock = NSLock()
        private var entries: [Entry] = []
        func append(_ observation: MacSpeechAudioOutputObservation) {
            let entry: Entry
            switch observation {
            case .scheduled(let generation, let sequence):
                entry = Entry(time: DispatchTime.now().uptimeNanoseconds, generation: generation,
                    sequence: sequence, kind: "scheduled", accepted: nil)
            case .completion(let generation, let sequence, let accepted):
                entry = Entry(time: DispatchTime.now().uptimeNanoseconds, generation: generation,
                    sequence: sequence, kind: "completion", accepted: accepted)
            }
            lock.withLock { entries.append(entry) }
        }
        func snapshot() -> [Entry] { lock.withLock { entries } }
    }

    private actor LocalProvider: RealtimeResidentBrainProvider {
        private var events: [RealtimeResidentBrainEvent] = []
        private var continuation: CheckedContinuation<RealtimeResidentBrainEvent, Error>?
        private var session: RealtimeBrainSessionIdentity?
        private var revision: UInt64 = 1
        private var counters = Counts()
        nonisolated struct Counts: Sendable { var interrupt = 0; var cancel = 0; var create = 0; var audio = 0 }
        func counts() -> Counts { counters }
        func lastSession() -> RealtimeBrainSessionIdentity? { session }
        func contextRevision() -> UInt64 { revision }
        func openSession(_ command: RealtimeBrainOpenSessionCommand) async throws { session = command.identity }
        func updateRuntimeContext(_ update: RealtimeBrainRuntimeContextUpdate) async throws {
            revision = update.contextRevision
            if update.kind == .bootstrap {
                enqueue(RealtimeResidentBrainEvent(identity: RealtimeBrainEventIdentity(session: update.identity,
                    turnID: nil, responseID: nil, contextRevision: update.contextRevision), sequence: 1, kind: .sessionReady))
            }
        }
        func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws { counters.audio += 1 }
        func submitToolResult(_ command: RealtimeBrainToolResultCommand) async throws {}
        func createResponse(_ command: RealtimeBrainCreateResponseCommand) async throws { counters.create += 1 }
        func cancelGeneration(_ command: RealtimeBrainCancelGenerationCommand) async throws { counters.cancel += 1 }
        func interrupt(_ command: RealtimeBrainInterruptCommand) async throws { counters.interrupt += 1 }
        func receiveEvent(session: RealtimeBrainSessionIdentity) async throws -> RealtimeResidentBrainEvent {
            if !events.isEmpty { return events.removeFirst() }
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func closeSession(_ command: RealtimeBrainCloseSessionCommand) async throws {
            let pending = continuation
            continuation = nil
            events.removeAll()
            pending?.resume(throwing: RealtimeResidentBrainError.cancelled)
        }
        func enqueue(_ event: RealtimeResidentBrainEvent) {
            if let pending = continuation { continuation = nil; pending.resume(returning: event) }
            else { events.append(event) }
        }
    }
}
#endif
