#if DEBUG
import AppKit
import AVFoundation
import CryptoKit
import Foundation

@MainActor
enum Test3LocalAudioRunner {
    nonisolated private struct PhysicalFeedEntry: Sendable {
        let sequence: UInt64
        let sourceOffset: Int
        let targetAt: UInt64
        let sleepReturnedAt: UInt64
        let observedAt: UInt64
        let enqueueReturnedAt: UInt64
        let payloadSHA256: String
        let payloadRMS10ms: [Double]

        var json: [String: Any] {
            ["audio_sequence": sequence,
             "source_offset_48k": sourceOffset,
             "target_enqueue_at_ns": targetAt,
             "sleep_returned_at_ns": sleepReturnedAt,
             "producer_observed_at_ns": observedAt,
             "enqueue_returned_at_ns": enqueueReturnedAt,
             "late_by_ns": observedAt &- targetAt,
             "payload_sha256": payloadSHA256,
             "payload_rms_10ms": payloadRMS10ms]
        }
    }

    nonisolated private struct PhysicalFeedResult: Sendable {
        let entries: [PhysicalFeedEntry]
        let nextSequence: UInt64
        let maximumLateNanoseconds: UInt64
        let overdueChunks: Int
        let terminalSent: Bool
    }

    nonisolated private static func feedPhysicalAudio(
        provider: LocalProvider,
        identity: RealtimeBrainEventIdentity,
        chunks: [(sourceOffset: Int, bytes: Data, sha256: String,
                  rms10ms: [Double])]
    ) async -> PhysicalFeedResult {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var entries: [PhysicalFeedEntry] = []
        entries.reserveCapacity(chunks.count)
        var maximumLate: UInt64 = 0
        var overdue = 0
        for (index, chunk) in chunks.enumerated() {
            let targetAt = startedAt + UInt64(index) * 100_000_000
            let beforeSleep = DispatchTime.now().uptimeNanoseconds
            if beforeSleep < targetAt {
                do {
                    try await Task.sleep(nanoseconds: targetAt - beforeSleep)
                } catch {
                    break
                }
            }
            if Task.isCancelled { break }
            let sleepReturnedAt = DispatchTime.now().uptimeNanoseconds
            let observedAt = DispatchTime.now().uptimeNanoseconds
            let sequence = UInt64(index + 1)
            let accepted = await provider.enqueueAudioUnlessInterrupted(RealtimeResidentBrainEvent(
                identity: identity, sequence: sequence + 2,
                kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                    sequence: sequence, timestampNanoseconds: observedAt,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: 24_000, channelCount: 1
                    ), provenance: .providerGenerated, bytes: chunk.bytes
                ))
            ))
            let enqueueReturnedAt = DispatchTime.now().uptimeNanoseconds
            if !accepted { break }
            entries.append(PhysicalFeedEntry(
                sequence: sequence, sourceOffset: chunk.sourceOffset,
                targetAt: targetAt, sleepReturnedAt: sleepReturnedAt,
                observedAt: observedAt, enqueueReturnedAt: enqueueReturnedAt,
                payloadSHA256: chunk.sha256, payloadRMS10ms: chunk.rms10ms
            ))
            let late = observedAt &- targetAt
            maximumLate = max(maximumLate, late)
            if late >= 100_000_000 { overdue += 1 }
        }
        let terminalSent = entries.count == chunks.count && !Task.isCancelled
        if terminalSent {
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: identity,
                sequence: UInt64(chunks.count + 3),
                kind: .residentSpeakingStopped
            ))
        }
        return PhysicalFeedResult(
            entries: entries, nextSequence: UInt64(entries.count + 1),
            maximumLateNanoseconds: maximumLate, overdueChunks: overdue,
            terminalSent: terminalSent
        )
    }

    static var isRequested: Bool {
        CommandLine.arguments.contains("--test3-local-audio-preflight")
            || CommandLine.arguments.contains("--test3-local-audio")
            || CommandLine.arguments.contains("--test3-webrtc-local-audio")
            || CommandLine.arguments.contains("--test3-physical-echo")
            || CommandLine.arguments.contains("--test3-physical-observe")
            || CommandLine.arguments.contains("--test3-webrtc-physical-echo")
            || CommandLine.arguments.contains("--test3-webrtc-physical-observe")
            || CommandLine.arguments.contains("--test3-physical-yield-tail")
    }

    static func start() {
        if CommandLine.arguments.contains("--test3-local-audio-preflight") {
            do {
                let root = try testRoot()
                let authorization = microphoneAuthorization()
                let route = SystemMacSpeechDeviceMonitor().currentRoute()
                try printJSON([
                    "schema_version": 1, "microphone_authorization": authorization,
                    "authorized": authorization == "authorized", "test_root": root.path,
                    "input_device_uid": route.input.identifier,
                    "output_device_uid": route.output.identifier,
                    "input_device_available": route.input.isAvailable,
                    "output_device_available": route.output.isAvailable,
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
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
            .appendingPathComponent("Aftelle", isDirectory: true)
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
        let webRTCLocalAudio = CommandLine.arguments.contains(
            "--test3-webrtc-local-audio"
        )
        let webRTCPhysicalEchoOnly = CommandLine.arguments.contains(
            "--test3-webrtc-physical-echo"
        )
        let webRTCPhysicalObservation = CommandLine.arguments.contains(
            "--test3-webrtc-physical-observe"
        )
        let physicalEchoOnly = webRTCPhysicalEchoOnly
            || CommandLine.arguments.contains("--test3-physical-echo")
        let physicalObservation = webRTCPhysicalObservation
            || CommandLine.arguments.contains("--test3-physical-observe")
        let physicalYieldTail = CommandLine.arguments.contains(
            "--test3-physical-yield-tail"
        )
        let physicalRouteOnly = physicalEchoOnly || physicalObservation
            || physicalYieldTail
        let flag = webRTCPhysicalEchoOnly
            ? "--test3-webrtc-physical-echo"
            : webRTCPhysicalObservation
            ? "--test3-webrtc-physical-observe"
            : physicalYieldTail
            ? "--test3-physical-yield-tail"
            : physicalEchoOnly
            ? "--test3-physical-echo"
            : physicalObservation
                ? "--test3-physical-observe"
                : webRTCLocalAudio
                    ? "--test3-webrtc-local-audio" : "--test3-local-audio"
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else {
            throw RunnerError.invalidConfiguration
        }
        let argument = CommandLine.arguments[index + 1]
        let directory = argument == "-"
            ? try prepareStdinDirectory()
            : URL(fileURLWithPath: argument, isDirectory: true)
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
        guard let executableURL = Bundle.main.executableURL else {
            throw RunnerError.invalidConfiguration
        }
        let debugCodeURL = executableURL.deletingLastPathComponent()
            .appendingPathComponent("Aftelle.debug.dylib")
        let activeCodeURL = FileManager.default.fileExists(atPath: debugCodeURL.path)
            ? debugCodeURL : executableURL
        let resident = try samples(at: residentURL)
        let near = try samples(at: nearURL)
        var results: [[String: Any]] = []
        var aggregate: [String: Any] = [:]
        if physicalRouteOnly,
           FileManager.default.fileExists(atPath:
                directory.appendingPathComponent("result.json").path) {
            throw RunnerError.evidenceDirectoryExists
        }
        let existingCases: [(String, Float, Bool, MacSpeechAudioProcessingMode)] = [
            ("apple_normal_echo_only", 0.5, false, .appleVoiceProcessing),
            ("apple_normal_software_near", 0.5, true, .appleVoiceProcessing),
            ("apple_higher_echo_only", 1, false, .appleVoiceProcessing),
            ("apple_higher_software_near", 1, true, .appleVoiceProcessing)
        ]
        let webRTCCases: [(String, Float, Bool, MacSpeechAudioProcessingMode)] = [
            ("webrtc_normal_echo_only", 0.5, false, .webRTCAEC3),
            ("webrtc_normal_software_near", 0.5, true, .webRTCAEC3),
            ("webrtc_higher_echo_only", 1, false, .webRTCAEC3),
            ("webrtc_higher_software_near", 1, true, .webRTCAEC3)
        ]
        let physicalMode: MacSpeechAudioProcessingMode =
            webRTCPhysicalEchoOnly || webRTCPhysicalObservation
                ? .webRTCAEC3 : .appleVoiceProcessing
        let physicalCasePrefix = physicalMode == .webRTCAEC3
            ? "webrtc" : "apple"
        let cases = physicalRouteOnly
            ? [(physicalYieldTail ? "apple_physical_yield_tail"
                : physicalEchoOnly
                    ? "\(physicalCasePrefix)_physical_echo_only"
                    : "\(physicalCasePrefix)_physical_observation",
                0.5, false, physicalMode)]
            : webRTCLocalAudio ? webRTCCases : existingCases
        for (name, gain, positive, mode) in cases {
            let caseDirectory = directory.appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: caseDirectory.path) {
                throw RunnerError.evidenceDirectoryExists
            }
            try FileManager.default.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
            var result: [String: Any]
            do {
                guard microphoneAuthorization() == "authorized" else {
                    throw RunnerError.microphoneNotAuthorized
                }
                result = try await runCase(
                    name: name,
                    gain: gain,
                    positive: positive,
                    mode: mode,
                    resident: resident,
                    near: near,
                    fixture: fixtureURL,
                    directory: caseDirectory,
                    physicalEchoOnly: physicalEchoOnly,
                    physicalObservation: physicalObservation,
                    physicalYieldTail: physicalYieldTail
                )
            } catch {
                result = ["case": name, "status": "FAIL", "error": String(describing: error)]
            }
            results.append(result)
            try writeJSON(result, to: caseDirectory.appendingPathComponent("result.json"))
            let physicalCaseFailed = physicalRouteOnly && results.contains {
                ($0["status"] as? String) == "FAIL"
            }
            aggregate = [
                "schema_version": 1,
                "status": physicalCaseFailed ? "FAIL"
                    : physicalRouteOnly ? "UNVERIFIED"
                    : results.count == cases.count
                        ? "COMPLETED" : "RUNNING",
                "qwen_calls": 0, "permission_requested": false,
                "semantic_source": physicalRouteOnly
                    ? "none_during_playback" : "local_stub_fixture_after_runtime_acoustic_evidence",
                "physical_double_talk": (physicalEchoOnly || physicalYieldTail)
                    ? "NOT_TESTED_RESIDENT_ONLY"
                    : physicalObservation ? "UNVERIFIED_EXTERNAL_SOURCE"
                    : "NOT_CLAIMED_CAPTURE_INJECTION_USED",
                "automatic_provisional_source": physicalRouteOnly
                    ? "production_capture_pump_no_provider_proposal" : "mixed_existing_cases",
                "gain_description": "Relative PCM gain only; system volume unchanged; SPL not calibrated",
                "test3_acceptance": "BLOCKED",
                "near_fixture_loaded_but_not_delivered": physicalRouteOnly,
                "runtime_code_sha256": try sha256(activeCodeURL),
                "runtime_code_file": activeCodeURL.lastPathComponent,
                "resident_sha256": try sha256(residentURL), "near_sha256": try sha256(nearURL),
                "evidence_directory": directory.path,
                "cases": results
            ]
            try writeJSON(
                aggregate,
                to: directory.appendingPathComponent("result.json")
            )
            try? await Task.sleep(for: .milliseconds(300))
        }
        try printJSON(aggregate)
        if physicalRouteOnly {
            exit(2)
        }
    }

    private static func prepareStdinDirectory() throws -> URL {
        let payload = FileHandle.standardInput.readDataToEndOfFile()
        guard payload.count >= MemoryLayout<UInt32>.size else {
            throw RunnerError.invalidConfiguration
        }
        let headerLength = payload.withUnsafeBytes {
            Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)))
        }
        let headerStart = MemoryLayout<UInt32>.size
        let headerEnd = headerStart + headerLength
        guard headerLength > 0, headerEnd <= payload.count else {
            throw RunnerError.invalidConfiguration
        }
        let transfer = try JSONDecoder().decode(
            TransferConfiguration.self,
            from: payload.subdata(in: headerStart..<headerEnd)
        )
        guard transfer.schema_version == 1,
              transfer.resident_length > 0,
              transfer.near_length > 0,
              transfer.fixture_length > 0,
              transfer.resident_length <= 48_000 * 4 * 30,
              transfer.near_length <= 48_000 * 4 * 30,
              transfer.fixture_length <= 10 * 1_024 * 1_024,
              headerEnd + transfer.resident_length
                + transfer.near_length + transfer.fixture_length
                    == payload.count else {
            throw RunnerError.invalidConfiguration
        }
        let directory = try testRoot().appendingPathComponent(
            "test3-local-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        var offset = headerEnd
        let residentEnd = offset + transfer.resident_length
        try payload.subdata(in: offset..<residentEnd).write(
            to: directory.appendingPathComponent("resident.f32le.pcm"),
            options: .atomic
        )
        offset = residentEnd
        let nearEnd = offset + transfer.near_length
        try payload.subdata(in: offset..<nearEnd).write(
            to: directory.appendingPathComponent("near.f32le.pcm"),
            options: .atomic
        )
        offset = nearEnd
        try payload.subdata(in: offset..<payload.count).write(
            to: directory.appendingPathComponent("resident.digital_resident"),
            options: .atomic
        )
        try writeJSON([
            "schema_version": 1,
            "resident_file": "resident.f32le.pcm",
            "near_file": "near.f32le.pcm",
            "fixture_file": "resident.digital_resident"
        ], to: directory.appendingPathComponent("config.json"))
        return directory.resolvingSymlinksInPath()
    }

    private static func runCase(
        name: String,
        gain: Float,
        positive: Bool,
        mode: MacSpeechAudioProcessingMode,
        resident: [Float],
        near: [Float],
        fixture: URL,
        directory: URL,
        physicalEchoOnly: Bool = false,
        physicalObservation: Bool = false,
        physicalYieldTail: Bool = false
    ) async throws -> [String: Any] {
        let physicalRouteOnly = physicalEchoOnly || physicalObservation
            || physicalYieldTail
        let routeMonitor = SystemMacSpeechDeviceMonitor()
        if physicalRouteOnly {
            let route = routeMonitor.currentRoute()
            guard route.input.identifier
                    == "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1",
                  route.output.identifier == "BuiltInSpeakerDevice" else {
                throw RunnerError.wrongPhysicalRoute(
                    "before_start input=\(route.input.identifier) output=\(route.output.identifier)"
                )
            }
        }
        let preparedAudio = (0..<105).map { index in
            let sourceOffset = index * 4_800
            let bytes = pcmChunk(resident, offset: sourceOffset,
                sampleCount: 4_800, gain: gain)
            return (sourceOffset: sourceOffset, bytes: bytes,
                sha256: SHA256.hash(data: bytes).map {
                    String(format: "%02x", $0)
                }.joined(), rms10ms: pcmRMS10ms(bytes))
        }
        let files = IsolatedFileManager(root: directory.appendingPathComponent("stores", isDirectory: true))
        let store = SessionStore(fileManager: files)
        let provider = LocalProvider()
        let router = ProviderRouter(credentialReader: NoCredentials(), realtimeResidentBrainProvider: provider)
        let runtime = RuntimeCore(executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router, sessionStore: store,
            memoryController: MemoryController(store: MemoryStore(fileManager: files)))
        runtime.useNarrativeMemoryStoreForTesting(NarrativeMemoryStore(fileManager: files))
        runtime.useRelationshipStateStoreForTesting(RelationshipStateStore(fileManager: files))
        let engine = SystemMacSpeechVoiceProcessingEngine(
            audioProcessingMode: mode
        )
        let audioHost = MacSpeechAudioHost(authorizationProvider: NoPromptAuthorization(),
            capture: SystemMacSpeechAudioCapture(audioEngine: engine))
        let outputHost = MacSpeechAudioOutputHost(player: SystemMacSpeechAudioOutputPlayer(audioEngine: engine))
        let playbackObservations = PlaybackObservations()
        await outputHost.observePlaybackForTesting { playbackObservations.append($0) }
        let controller = AppController(orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
            speechAudioHost: audioHost, speechAudioOutputHost: outputHost,
            realtimeSpeechDiagnosticAudioEngine: engine, restoreProviderSettings: false)
        controller.realtimePlaybackEnqueueObserverForTesting = { _, generation, sequence in
            playbackObservations.appendEnqueueRequested(generation: generation, sequence: sequence)
        }
        controller.debugImportTestResident(from: fixture)
        let attemptID = UUID()
        let captureArmed = mode == .webRTCAEC3
            ? engine.armAcousticReplayCapture(
                attemptID: attemptID,
                targetCaptureFrameCount: 1_100
              ) : false
        await controller.startRealtimeResidentBrainRoute()
        guard await wait(seconds: 5, until: {
            let hasSession = await provider.lastSession() != nil
            return controller.formalSpeechRouteDebugSnapshot.phase == .listening && hasSession
        }), let session = await provider.lastSession() else {
            await controller.shutdownSpeechAudioHost()
            throw RunnerError.routeNotListening
        }
        let aec = engine.acousticEchoSnapshot()
        guard aec.mode == mode,
              aec.enabled,
              aec.active,
              aec.fallbackCount == 0 else {
            await controller.shutdownSpeechAudioHost()
            throw RunnerError.aecUnavailable
        }
        if physicalRouteOnly {
            let route = routeMonitor.currentRoute()
            let activeInput = await audioHost.currentSnapshot()
            guard route.input.identifier
                    == "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1",
                  route.output.identifier == "BuiltInSpeakerDevice",
                  activeInput.inputDevice.identifier == route.input.identifier else {
                await controller.shutdownSpeechAudioHost()
                throw RunnerError.wrongPhysicalRoute(
                    "after_start input=\(route.input.identifier) output=\(route.output.identifier) "
                        + "active_input=\(activeInput.inputDevice.identifier)"
                )
            }
        }
        let timingTraceArmed = physicalRouteOnly
            ? engine.armTest3TimingTrace() : false
        if physicalRouteOnly && !timingTraceArmed {
            await controller.shutdownSpeechAudioHost()
            throw RunnerError.timingTraceUnavailable
        }
        let identity = RealtimeBrainEventIdentity(session: session, turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(), contextRevision: await provider.contextRevision())
        await provider.enqueue(RealtimeResidentBrainEvent(identity: RealtimeBrainEventIdentity(
            session: session, turnID: identity.turnID, responseID: nil, contextRevision: identity.contextRevision),
            sequence: 2, kind: .userTranscriptFinal("Local Test 3 playback fixture")))
        let initialTiming = await outputHost.timingDebugSnapshot()
        let initialHost = engine.acousticEchoSnapshot()
        let initialAcousticEvidenceCount = controller.realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
        let initialProvider = await provider.counts()
        var playbackStartCreateCount = initialProvider.create
        var audioSequence: UInt64 = 1
        var nextAudioAt = now()
        var audioFeedSchedule: [[String: Any]] = []
        var maximumAudioFeedLateNanoseconds: UInt64 = 0
        var overdueAudioFeedChunks = 0
        var physicalFeedTerminalSent = false
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
        var firstPlaybackCaptureAt: UInt64?
        var lastPlaybackCaptureAt: UInt64?
        var maximumPlaybackCaptureGapMilliseconds = 0.0
        var playbackCaptureObservations = 0
        var polling: [[String: Any]] = []
        var physicalRouteStayedExact = true
        let yieldID = UUID()
        var yieldFirstRenderAt: UInt64?
        var yieldTargetRenderAt: UInt64?
        var yieldPauseRequestAt: UInt64?
        var yieldPauseReturnedAt: UInt64?
        var yieldPauseAccepted = false
        var yieldResumeRequestAt: UInt64?
        var yieldResumeReturnedAt: UInt64?
        var yieldResumeAccepted = false
        var yieldRecoveryAttempted = false
        var yieldAborted = false
        var yieldGeneration: UInt64?
        var fullPlaybackObservedAt: UInt64?
        let started = now()
        let physicalFeedTask = physicalRouteOnly
            ? Task.detached(priority: .userInitiated) {
                await feedPhysicalAudio(
                    provider: provider, identity: identity,
                    chunks: preparedAudio
                )
            } : nil
        var dialogueBaseline: [SessionDialogueEntry]?
        var memoryBaseline: RuntimeNarrativeMemoryStoreSnapshot?
        var relationshipBaseline: RuntimeRelationshipInstanceState?
        while now() - started < (physicalYieldTail
            ? 14_000_000_000
            : physicalEchoOnly ? 13_000_000_000 : 11_500_000_000) {
            if physicalRouteOnly {
                let route = routeMonitor.currentRoute()
                let activeInput = await audioHost.currentSnapshot()
                physicalRouteStayedExact = physicalRouteStayedExact
                    && route.input.identifier
                        == "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1"
                    && route.output.identifier == "BuiltInSpeakerDevice"
                    && activeInput.inputDevice.identifier == route.input.identifier
                if physicalYieldTail && !physicalRouteStayedExact {
                    yieldAborted = true
                    _ = await outputHost.stop()
                    break
                }
            }
            let providerCounts = await provider.counts()
            let feedNow = now()
            if !physicalRouteOnly, feedNow >= nextAudioAt,
               audioSequence <= 105, semanticAt == nil,
               providerCounts.interrupt == 0 {
                let chunk = preparedAudio[Int(audioSequence - 1)]
                let targetAt = nextAudioAt
                let lateBy = feedNow - targetAt
                await provider.enqueue(RealtimeResidentBrainEvent(identity: identity,
                    sequence: audioSequence + 2,
                    kind: .residentAudioDelta(RealtimeBrainAudioDelta(sequence: audioSequence,
                        timestampNanoseconds: feedNow, format: RealtimeBrainAudioFormat(
                            encoding: .pcm16LittleEndian, sampleRate: 24_000, channelCount: 1),
                        provenance: .providerGenerated, bytes: chunk.bytes))))
                audioFeedSchedule.append([
                    "audio_sequence": audioSequence,
                    "source_offset_48k": chunk.sourceOffset,
                    "target_enqueue_at_ns": targetAt,
                    "producer_observed_at_ns": feedNow,
                    "late_by_ns": lateBy,
                    "payload_sha256": chunk.sha256,
                    "payload_rms_10ms": chunk.rms10ms
                ])
                maximumAudioFeedLateNanoseconds = max(maximumAudioFeedLateNanoseconds, lateBy)
                if lateBy >= 100_000_000 { overdueAudioFeedChunks += 1 }
                audioSequence += 1
                nextAudioAt = targetAt + 100_000_000
            }
            await controller.refreshMicrophoneAuthorization()
            let snapshot = engine.acousticEchoSnapshot()
            let observation = engine.acousticObservationSnapshot()
            let evidence = runtime.realtimeInterruptionEvidenceDebugSnapshot()
            if snapshot.isPlaybackActive, playbackAt == nil {
                playbackAt = now()
                playbackStartCreateCount = (await provider.counts()).create
                dialogueBaseline = (try? store.loadMostRecentDialogueEntries(limit: 100)) ?? []
                memoryBaseline = runtime.narrativeMemoryDebugSnapshot()
                relationshipBaseline = runtime.currentRelationshipState
                if positive {
                    injectionScheduledAt = now() + 3_000_000_000
                    engine.setTest3NearEndInjection(
                        samples: near,
                        startAtNanoseconds: injectionScheduledAt!
                    )
                }
            }
            let observedNow = now()
            if physicalYieldTail, playbackAt != nil {
                let bounds = engine.test3RenderTimingBounds()
                if yieldFirstRenderAt == nil,
                   let first = bounds.firstContent {
                    yieldFirstRenderAt = first
                    yieldTargetRenderAt = first + 5_000_000_000
                }
                if yieldPauseRequestAt == nil,
                   let target = yieldTargetRenderAt,
                   let latest = bounds.latest,
                   latest >= target {
                    yieldGeneration = await outputHost.currentSnapshot().generation
                    yieldPauseRequestAt = now()
                    yieldPauseAccepted = await outputHost.pauseForProvisionalInterruption(
                        id: yieldID, generation: yieldGeneration!
                    )
                    yieldPauseReturnedAt = now()
                    if !yieldPauseAccepted {
                        yieldAborted = true
                        _ = await outputHost.stop()
                        break
                    }
                }
                if yieldPauseAccepted,
                   yieldResumeRequestAt == nil,
                   let pausedAt = yieldPauseReturnedAt,
                   now() >= pausedAt + 600_000_000 {
                    yieldResumeRequestAt = now()
                    yieldResumeAccepted = await outputHost.resumeProvisionalInterruption(
                        id: yieldID, generation: yieldGeneration!
                    )
                    yieldResumeReturnedAt = now()
                    if !yieldResumeAccepted {
                        yieldAborted = true
                        _ = await outputHost.stop()
                        break
                    }
                }
            }
            let injection = engine.test3NearEndInjectionSnapshot()
            let positiveInputStarted =
                injection.startedAtNanoseconds != nil
            if snapshot.isPlaybackActive, !positiveInputStarted {
                preInjectionGateOpens = snapshot.sourceGateOpenCount &- initialHost.sourceGateOpenCount
                preInjectionForwards = snapshot.sourceForwardedFrameCount &- initialHost.sourceForwardedFrameCount
                if evidence.hasAcousticEvidence { acousticBeforeInjection = true }
            }
            if snapshot.isPlaybackActive, snapshot.sourceGateOpen, firstGateAt == nil { firstGateAt = observedNow }
            if snapshot.isPlaybackActive, snapshot.sourceForwardedFrameCount > initialHost.sourceForwardedFrameCount,
               firstForwardAt == nil { firstForwardAt = observedNow }
            if snapshot.isPlaybackActive, evidence.hasAcousticEvidence, firstAcousticAt == nil { firstAcousticAt = observedNow }
            if positive, positiveInputStarted, evidence.hasAcousticEvidence,
               evidence.session == session, semanticAt == nil, snapshot.isPlaybackActive {
                semanticAt = observedNow
                await provider.enqueue(RealtimeResidentBrainEvent(identity: identity, sequence: audioSequence + 2,
                    kind: .interruptionProposed(RealtimeBrainInterruptionProposal(identity: identity,
                        reason: "user_speech_started_during_resident_response"))))
            }
            if observation.captureFrameIndex != lastObservedFrame {
                lastObservedFrame = observation.captureFrameIndex
                maximumRawRMS = max(maximumRawRMS, snapshot.rawCaptureRMS)
                maximumRenderRMS = max(maximumRenderRMS, observation.renderReferenceRMS ?? 0)
                if snapshot.isPlaybackActive,
                   let captureAt = observation.captureHostTimeNanoseconds {
                    playbackCaptureObservations += 1
                    firstPlaybackCaptureAt = firstPlaybackCaptureAt ?? captureAt
                    if let previous = lastPlaybackCaptureAt,
                       captureAt >= previous {
                        maximumPlaybackCaptureGapMilliseconds = max(
                            maximumPlaybackCaptureGapMilliseconds,
                            Double(captureAt - previous) / 1_000_000
                        )
                    }
                    lastPlaybackCaptureAt = captureAt
                }
                polling.append([
                    "observed_at_ns": observedNow, "capture_frame": snapshot.captureFrameCount,
                    "capture_at_ns": observation.captureHostTimeNanoseconds as Any? ?? NSNull(),
                    "playback_active": snapshot.isPlaybackActive, "source_gate_open": snapshot.sourceGateOpen,
                    "system_vad": engine.systemVoiceActivityForTesting(),
                    "source_gate_open_count": snapshot.sourceGateOpenCount,
                    "source_forwarded_frames": snapshot.sourceForwardedFrameCount,
                    "raw_rms": snapshot.rawCaptureRMS, "clean_rms": snapshot.processedCaptureRMS,
                    "linear_rms": snapshot.linearAECOutputRMS,
                    "render_rms": observation.renderReferenceRMS as Any? ?? NSNull(),
                    "source_alignment_delay_ms": snapshot.sourceAlignmentDelayMilliseconds as Any? ?? NSNull(),
                    "raw_render_correlation": snapshot.renderCaptureCorrelation,
                    "residual_render_correlation": snapshot.residualRenderCorrelation,
                    "processed_linear_correlation": snapshot.processedLinearCorrelation,
                    "classification": snapshot.inputClassification.rawValue,
                    "runtime_acoustic": evidence.hasAcousticEvidence,
                    "generation": controller.formalSpeechRouteDebugSnapshot.generation as Any? ?? NSNull()
                ])
            }
            if let playbackAt,
               observedNow - playbackAt >= (physicalYieldTail
                ? 11_100_000_000 : 10_500_000_000) {
                if physicalEchoOnly || physicalYieldTail {
                    let played = await outputHost.currentSnapshot().playedChunkCount
                    if played == 105 {
                        fullPlaybackObservedAt = fullPlaybackObservedAt ?? observedNow
                        if observedNow - fullPlaybackObservedAt! >= 200_000_000 {
                            break
                        }
                    }
                } else {
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        if physicalYieldTail && yieldPauseAccepted && !yieldResumeAccepted
            && !yieldAborted {
            yieldRecoveryAttempted = true
            _ = await outputHost.resumeProvisionalInterruption(
                id: yieldID, generation: yieldGeneration!
            )
        }
        if yieldAborted { physicalFeedTask?.cancel() }
        if let physicalFeedTask {
            let feed = await physicalFeedTask.value
            audioSequence = feed.nextSequence
            audioFeedSchedule = feed.entries.map(\.json)
            maximumAudioFeedLateNanoseconds = feed.maximumLateNanoseconds
            overdueAudioFeedChunks = feed.overdueChunks
            physicalFeedTerminalSent = feed.terminalSent
        }
        if physicalRouteOnly {
            engine.sealTest3TimingTrace()
        }
        engine.sealAcousticReplayCapture(matchingAttemptID: attemptID)
        let capsule = engine.acousticReplayCaptureSnapshot()
        let injection = engine.test3NearEndInjectionSnapshot()
        let finalHost = engine.acousticEchoSnapshot()
        let finalTiming = await outputHost.timingDebugSnapshot()
        let output = await outputHost.currentSnapshot()
        let input = await audioHost.currentSnapshot()
        if physicalRouteOnly {
            physicalRouteStayedExact = physicalRouteStayedExact
                && input.inputDevice.identifier
                    == "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1"
                && output.outputDevice.identifier == "BuiltInSpeakerDevice"
        }
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
        let createDelta = finalProvider.create - playbackStartCreateCount
        let frames = capsule?.captureFrames ?? []
        let timingTrace = physicalRouteOnly
            ? engine.test3TimingTraceSnapshot() : nil
        let captureCallbackTrace = physicalRouteOnly
            ? engine.test3CaptureCallbackSnapshot() : nil
        let renderCallbackTrace = physicalRouteOnly
            ? engine.test3RenderCallbackSnapshot() : nil
        let appleDecision = physicalRouteOnly
            && mode == .appleVoiceProcessing
            ? engine.test3AppleDecisionSnapshot() : nil
        let appleInput = physicalRouteOnly
            && mode == .appleVoiceProcessing
            ? engine.test3AppleInputSnapshot() : nil
        let appleInputPCM = appleInput.map {
            $0.samples.withUnsafeBytes { Data($0) }
        }
        let appleInputSHA256 = appleInputPCM.map {
            SHA256.hash(data: $0).map {
                String(format: "%02x", $0)
            }.joined()
        }
        let appleInputAdditionalPCM = appleInput.map { input in
            input.additionalChannels.map { samples in
                samples.withUnsafeBytes { Data($0) }
            }
        }
        let appleInputAdditionalSHA256 = appleInputAdditionalPCM?.map { data in
            SHA256.hash(data: data).map {
                String(format: "%02x", $0)
            }.joined()
        }
        let appleProcessedPCM = appleDecision.map {
            $0.processedSamples.withUnsafeBytes { Data($0) }
        }
        let appleProcessedSHA256 = appleProcessedPCM.map {
            SHA256.hash(data: $0).map {
                String(format: "%02x", $0)
            }.joined()
        }
        let appleVADReads = physicalRouteOnly
            && mode == .appleVoiceProcessing
            ? engine.test3AppleVADReadSnapshot() : nil
        let playbackFrames = frames.filter(\.isPlaybackActive)
        let positiveStartedAt = injection.startedAtNanoseconds
        let echoFrames = playbackFrames.filter {
            guard let injectionAt = positiveStartedAt else { return true }
            return ($0.captureHostTimeNanoseconds ?? $0.timestampNanoseconds) < injectionAt
        }
        let preInjectionGateFrames = echoFrames.filter(\.sourceGateOpen).count
        let preInjectionForwardedSpans = echoFrames.flatMap(\.emittedSpans).filter { !$0.silenced }.count
        let playbackTimes = playbackFrames.map { $0.captureHostTimeNanoseconds ?? $0.timestampNanoseconds }
        let exactCaptureCoverageMilliseconds = playbackTimes.count > 1
            ? Double(playbackTimes.last! - playbackTimes.first!) / 1_000_000 + 10 : 0
        let exactMaximumCaptureGapMilliseconds = zip(playbackTimes, playbackTimes.dropFirst()).map {
            $1 >= $0 ? Double($1 - $0) / 1_000_000 : Double(UInt64.max)
        }.max() ?? 0
        let observedCaptureCoverageMilliseconds: Double
        if let firstPlaybackCaptureAt, let lastPlaybackCaptureAt,
           lastPlaybackCaptureAt >= firstPlaybackCaptureAt {
            observedCaptureCoverageMilliseconds =
                Double(lastPlaybackCaptureAt - firstPlaybackCaptureAt)
                    / 1_000_000 + 10
        } else {
            observedCaptureCoverageMilliseconds = 0
        }
        let physicalCaptureTimes = (timingTrace?.captureFrames ?? [])
            .compactMap(\.hostTimeNanoseconds)
            .filter { captureAt in
                guard let playbackAt, let lastPlaybackCaptureAt else { return false }
                return captureAt >= playbackAt && captureAt <= lastPlaybackCaptureAt
            }
        let physicalCaptureCoverageMilliseconds = physicalCaptureTimes.count > 1
            ? Double(physicalCaptureTimes.last! - physicalCaptureTimes.first!) / 1_000_000 + 10 : 0
        let physicalMaximumCaptureGapMilliseconds = zip(
            physicalCaptureTimes, physicalCaptureTimes.dropFirst()
        ).map {
            $1 >= $0 ? Double($1 - $0) / 1_000_000 : Double(UInt64.max)
        }.max() ?? 0
        let physicalRenderTimes = (timingTrace?.renderFrames ?? [])
            .compactMap(\.hostTimeNanoseconds)
        let physicalRenderCoverageMilliseconds = physicalRenderTimes.count > 1
            ? Double(physicalRenderTimes.last! - physicalRenderTimes.first!)
                / 1_000_000 + 10 : 0
        let physicalMaximumRenderGapMilliseconds = zip(
            physicalRenderTimes, physicalRenderTimes.dropFirst()
        ).map {
            $1 >= $0 ? Double($1 - $0) / 1_000_000
                : Double(UInt64.max)
        }.max() ?? 0
        let physicalRenderGapsOver25Milliseconds = zip(
            physicalRenderTimes, physicalRenderTimes.dropFirst()
        ).compactMap { earlier, later -> Double? in
            guard later >= earlier else { return Double(UInt64.max) }
            let gap = Double(later - earlier) / 1_000_000
            return gap > 25 ? gap : nil
        }
        let preYieldRenderTimes = physicalYieldTail
            ? physicalRenderTimes.filter {
                guard let first = yieldFirstRenderAt,
                      let target = yieldTargetRenderAt else { return false }
                return $0 >= first && $0 <= target
            } : []
        let preYieldRenderGapsOver25Milliseconds = zip(
            preYieldRenderTimes, preYieldRenderTimes.dropFirst()
        ).filter { earlier, later in
            later < earlier || later - earlier > 25_000_000
        }.count
        let callbacksDuringYield = (renderCallbackTrace?.callbacks ?? [])
            .filter { callback in
                guard let pausedAt = yieldPauseReturnedAt,
                      let resumedAt = yieldResumeRequestAt else { return false }
                return callback.enteredAtNanoseconds >= pausedAt
                    && callback.enteredAtNanoseconds < resumedAt
            }
        let captureCoverageMilliseconds = physicalRouteOnly
            ? physicalCaptureCoverageMilliseconds
            : mode == .webRTCAEC3
                ? exactCaptureCoverageMilliseconds : observedCaptureCoverageMilliseconds
        let maximumCaptureGapMilliseconds = physicalRouteOnly
            ? physicalMaximumCaptureGapMilliseconds
            : mode == .webRTCAEC3
                ? exactMaximumCaptureGapMilliseconds : maximumPlaybackCaptureGapMilliseconds
        let couplingFrames = echoFrames.filter {
            $0.rawCaptureRMS > 0.001 && ($0.renderReferenceRMS ?? 0) > 0.001
                && ($0.timingCorrelation ?? 0) >= 0.65
        }.count
        let gateFrames = playbackFrames.filter(\.sourceGateOpen).count
        let forwardedSpans = playbackFrames.flatMap(\.emittedSpans).filter { !$0.silenced }.count
        let gateOpenDelta = finalHost.sourceGateOpenCount
            &- initialHost.sourceGateOpenCount
        let forwardedFrameDelta = finalHost.sourceForwardedFrameCount
            &- initialHost.sourceForwardedFrameCount
        let gateActivityCount = mode == .webRTCAEC3
            ? UInt64(gateFrames) : gateOpenDelta
        let forwardedActivityCount = mode == .webRTCAEC3
            ? UInt64(forwardedSpans) : forwardedFrameDelta
        let playbackFrameObservationCount = mode == .webRTCAEC3
            ? playbackFrames.count : playbackCaptureObservations
        let qualificationObservations = polling.filter {
            ($0["system_vad"] as? Bool) == true
                || ($0["source_gate_open"] as? Bool) == true
        }
        let minimumPlaybackFrameObservationCount = mode == .webRTCAEC3
            ? 800 : 80
        let firstRecordedGate = playbackFrames.first(where: \.sourceGateOpen)
            .map { $0.captureHostTimeNanoseconds ?? $0.timestampNanoseconds }
        var clearLatencyMilliseconds: Double?
        if let confirmed, finalTiming.lastClearCompletedAtNanoseconds >= confirmed.confirmedAtNanoseconds,
           clearDelta > 0 {
            clearLatencyMilliseconds = Double(finalTiming.lastClearCompletedAtNanoseconds
                - confirmed.confirmedAtNanoseconds) / 1_000_000
        }
        let playbackEvents = playbackObservations.snapshot()
        let scheduledAudio = playbackEvents
            .filter { $0.kind == "scheduled"
                && $0.generation == session.generation }
        let scheduledAudioSequences = Set(scheduledAudio.map(\.sequence))
        let providerAudioEvents = await provider.audioEventSnapshot()
        let provisionalEvents = controller.realtimeSpeechDiagnosticTimeline.events
            .filter {
                $0.category == "causal_provisional_paused"
                    || $0.category == "causal_provisional_resumed"
            }
        let provisionalPauseCount = provisionalEvents.filter {
            $0.category == "causal_provisional_paused"
        }.count
        let provisionalResumeCount = provisionalEvents.filter {
            $0.category == "causal_provisional_resumed"
        }.count
        let causalCandidateDebug = physicalRouteOnly
            ? await controller.test3CausalCandidateDebugSnapshot() : []
        let stalePlayback = playbackEvents.filter {
            clearDelta > 0 && $0.time >= finalTiming.lastClearCompletedAtNanoseconds
                && $0.generation == session.generation && ($0.kind == "scheduled" || $0.accepted == true)
        }.count
        var failures: [String] = []
        if stalePlayback > 0 { failures.append("Old generation playback accepted after clear") }
        if finalHost.mode != mode || finalHost.fallbackCount > 0 { failures.append("AEC fallback") }
        if playbackAt == nil || output.playbackStartedCount == 0 { failures.append("No actual playback") }
        if mode == .webRTCAEC3, (!captureArmed || frames.isEmpty) {
            failures.append("Missing 10 ms capture evidence")
        }
        if mode == .appleVoiceProcessing,
           playbackCaptureObservations == 0 {
            failures.append("Missing Apple voice-processing capture evidence")
        }
        if createDelta != 0 { failures.append("Unexpected response.create") }
        if cancelDelta != 0 { failures.append("Unexpected separate cancelGeneration") }
        if history != dialogueBaseline { failures.append("Unexpected dialogue persistence or content mutation") }
        if !input.isCapturing || input.lastError != nil || output.lastError != nil {
            failures.append("Capture/output ended in an unavailable or error state")
        }
        if input.droppedFrameCount > 0 { failures.append("Capture frame buffer dropped audio") }
        if !memoryUnchanged || !relationshipUnchanged { failures.append("Unexpected memory/relationship mutation") }
        if physicalRouteOnly && !physicalRouteStayedExact {
            failures.append("Physical device route changed during capture")
        }
        if physicalRouteOnly && output.outputDevice.identifier != "BuiltInSpeakerDevice" {
            failures.append("Physical playback output was not the built-in speaker")
        }
        if physicalRouteOnly && (!timingTraceArmed
            || timingTrace?.truncated != false
            || timingTrace?.renderFrames.isEmpty != false
            || timingTrace?.captureFrames.isEmpty != false) {
            failures.append("Missing complete 10 ms physical timing trace")
        }
        if physicalRouteOnly && (audioSequence != 106
            || audioFeedSchedule.count != 105
            || !physicalFeedTerminalSent
            || scheduledAudio.count != 105
            || scheduledAudioSequences != Set(UInt64(1)...105)
            || overdueAudioFeedChunks != 0
            || output.underrunCount != 0
            || physicalRenderCoverageMilliseconds < 10_000
            || (!physicalYieldTail
                && physicalMaximumRenderGapMilliseconds > 25)) {
            failures.append("Incomplete or discontinuous physical resident playback")
        }
        if (physicalEchoOnly || physicalYieldTail)
            && (output.playedChunkCount != 105
                || fullPlaybackObservedAt == nil) {
            failures.append("Last resident chunk did not finish before capture ended")
        }
        if physicalYieldTail && (!yieldPauseAccepted || !yieldResumeAccepted
            || yieldAborted || yieldRecoveryAttempted
            || yieldFirstRenderAt == nil || yieldTargetRenderAt == nil
            || yieldPauseRequestAt == nil || yieldPauseReturnedAt == nil
            || yieldResumeRequestAt == nil || yieldResumeReturnedAt == nil) {
            failures.append("Controlled yield did not pause and resume exactly once")
        }
        if physicalYieldTail && (preYieldRenderTimes.count < 480
            || preYieldRenderGapsOver25Milliseconds != 0
            || (preYieldRenderTimes.last ?? 0) + 25_000_000
                < (yieldTargetRenderAt ?? UInt64.max)) {
            failures.append("Resident render was not continuous before fixed yield point")
        }
        if physicalYieldTail && (output.playedChunkCount != 105
            || (timingTrace?.renderFrames.count ?? 0) < 1_000) {
            failures.append("Resident audio was not fully played after yield")
        }
        if physicalYieldTail,
           let pausedAt = yieldPauseReturnedAt,
           let resumedAt = yieldResumeRequestAt,
           (resumedAt < pausedAt + 600_000_000
            || resumedAt > pausedAt + 650_000_000) {
            failures.append("Controlled yield duration missed the fixed 600 ms window")
        }
        if physicalRouteOnly,
           (captureCallbackTrace?.callbacks.isEmpty != false
            || captureCallbackTrace?.truncated != false) {
            failures.append("Missing complete capture callback timing trace")
        }
        if physicalRouteOnly,
           (renderCallbackTrace?.callbacks.isEmpty != false
            || renderCallbackTrace?.truncated != false) {
            failures.append("Missing complete render callback timing trace")
        }
        if physicalRouteOnly, mode == .appleVoiceProcessing,
           (appleDecision?.trace.frames.isEmpty != false
            || appleDecision?.trace.truncated != false
            || appleDecision?.trace.frames.count
                != timingTrace?.captureFrames.count
            || (appleDecision?.trace.frames.count ?? 0) * 480
                != appleDecision?.processedSamples.count
            || appleDecision?.trace.processedSampleCount
                != appleDecision?.processedSamples.count
            || appleVADReads?.reads.isEmpty != false
            || appleVADReads?.truncated != false
            || appleVADReads?.detector?.truncated != false
            || appleVADReads?.detector?.deviceUID
                != "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1") {
            failures.append("Missing complete Apple source-gate diagnostic trace")
        }
        if physicalRouteOnly, mode == .appleVoiceProcessing,
           (appleInput?.trace.callbacks.isEmpty != false
            || appleInput?.trace.truncated != false
            || appleInput?.trace.unsupportedFormat != false
            || appleInput?.trace.allChannelsComplete != true
            || appleInput?.trace.capturedChannelCount
                != (appleInput?.additionalChannels.count ?? -1) + 1
            || appleInput?.trace.callbacks.count
                != captureCallbackTrace?.callbacks.count
            || appleInput?.trace.callbacks.contains(where: {
                $0.copiedSampleCount != $0.inputFrameLength
            }) != false
            || appleInput?.trace.callbacks.reduce(0, {
                $0 + $1.copiedSampleCount
            }) != appleInput?.samples.count
            || appleInput?.trace.sampleCount != appleInput?.samples.count
            || appleInput?.trace.channelSampleCounts
                != ([appleInput?.samples.count ?? -1]
                    + (appleInput?.additionalChannels.map(\.count) ?? []))) {
            failures.append("Missing complete Apple pre-converter input witness")
        }
        if (physicalEchoOnly || physicalYieldTail) && provisionalPauseCount > 0 {
            failures.append("Resident echo consumed automatic provisional playback sequence")
        }
        if physicalRouteOnly,
           causalCandidateDebug.filter({ $0.pauseAccepted == true }).count
                != provisionalPauseCount {
            failures.append("Missing exact causal trigger snapshot")
        }
        if positive {
            if injection.injectedSampleCount == 0 {
                failures.append("Software near-end not injected")
            }
            if preInjectionGateFrames != 0 || preInjectionForwardedSpans != 0
                || preInjectionGateOpens != 0 || preInjectionForwards != 0 || acousticBeforeInjection {
                failures.append("Echo-only prefix opened source gate")
            }
            if mode == .webRTCAEC3 {
                if forwardedActivityCount == 0 {
                    failures.append("Software near-end did not reach the candidate gate")
                }
                if firstAcousticAt != nil || interruptDelta != 0
                    || clearDelta != 0 || finalGeneration != session.generation {
                    failures.append("Unverified source gained formal interruption authority")
                }
            } else {
                if firstAcousticAt == nil || semanticAt == nil
                    || forwardedActivityCount == 0 {
                    failures.append("Near-end did not reach Runtime acoustic evidence")
                }
                if interruptDelta != 1 || clearDelta != 1
                    || finalGeneration != session.generation + 1 {
                    failures.append("Expected exactly one Runtime interrupt, clear and generation advance")
                }
                if clearLatencyMilliseconds == nil || clearLatencyMilliseconds! > 50 {
                    failures.append("Confirmed interrupt to clear exceeds 50 ms or missing")
                }
            }
        } else if !physicalObservation {
            if playbackFrameObservationCount
                    < minimumPlaybackFrameObservationCount
                || captureCoverageMilliseconds < 8_000
                || maximumCaptureGapMilliseconds > 200 {
                failures.append("Insufficient continuous capture during resident playback")
            }
            if finalAcousticEvidenceCount != initialAcousticEvidenceCount {
                failures.append("Echo-only emitted Runtime acoustic evidence")
            }
            if gateActivityCount != 0 || forwardedActivityCount != 0
                || firstAcousticAt != nil {
                failures.append("Echo-only produced user acoustic evidence or forwarded audio")
            }
            if interruptDelta != 0 || clearDelta != 0 || finalGeneration != session.generation {
                failures.append("Echo-only changed interruption ownership")
            }
        } else {
            if playbackFrameObservationCount < minimumPlaybackFrameObservationCount
                || captureCoverageMilliseconds < 8_000
                || maximumCaptureGapMilliseconds > 200 {
                failures.append("Insufficient continuous physical capture during resident playback")
            }
            if interruptDelta != 0 || clearDelta != 0
                || finalGeneration != session.generation {
                failures.append("Unverified source changed interruption ownership")
            }
        }
        let status = !failures.isEmpty
            ? "FAIL"
            : physicalRouteOnly ? "UNVERIFIED"
            : mode == .webRTCAEC3 && couplingFrames < 20
                ? "INCONCLUSIVE"
                : mode == .webRTCAEC3 ? "CANDIDATE_ONLY" : "PASS"
        var result: [String: Any] = [
            "case": name, "status": status, "failures": failures, "resident_gain": gain,
            "test3_acceptance": "NOT_ESTABLISHED",
            "positive_input": positive,
            "near_delivery": positive
                ? mode == .webRTCAEC3
                    ? "software_before_webrtc_aec3_before_host_gate"
                    : "software_after_apple_voice_processing_before_host_gate"
                : physicalObservation ? "external_source_unverified" : "none",
            "qwen_calls": 0,
            "microphone": ["id": input.inputDevice.identifier, "name": input.inputDevice.name],
            "speaker": ["id": output.outputDevice.identifier, "name": output.outputDevice.name],
            "capture_sample_rate": input.actualSampleRate as Any? ?? NSNull(),
            "aec_mode": finalHost.mode.rawValue,
            "aec_fallback_count": finalHost.fallbackCount,
            "aec_fallback_reason": finalHost.fallbackReason?.rawValue as Any? ?? NSNull(),
            "coupled_echo_frames": couplingFrames, "minimum_coupled_echo_frames": 20,
            "coupling_criterion": "20 playback frames with raw/render RMS > .001 and matched correlation >= .65",
            "playback_frames": playbackFrameObservationCount,
            "playback_capture_coverage_ms": captureCoverageMilliseconds,
            "maximum_capture_gap_ms": maximumCaptureGapMilliseconds,
            "capture_gap_source": physicalRouteOnly ? "10ms_timing_trace"
                : mode == .webRTCAEC3 ? "10ms_capture_frames" : "decimated_polling",
            "input_is_capturing_at_end": input.isCapturing, "input_state": input.state.rawValue,
            "input_dropped_frames": input.droppedFrameCount,
            "input_rejected_stale_frames": input.rejectedStaleFrameCount,
            "input_error": input.lastError.map { String(describing: $0) } as Any? ?? NSNull(),
            "output_error": output.lastError.map { String(describing: $0) } as Any? ?? NSNull(),
            "output_state": output.state.rawValue,
            "acoustic_evidence_before": initialAcousticEvidenceCount,
            "acoustic_evidence_after": finalAcousticEvidenceCount,
            "playback_gate_activity": gateActivityCount,
            "playback_forwarded_activity": forwardedActivityCount,
            "pre_injection_gate_opens": preInjectionGateOpens,
            "pre_injection_forwarded_frames": preInjectionForwards,
            "pre_injection_gate_open_frames_exact": preInjectionGateFrames,
            "pre_injection_forwarded_spans_exact": preInjectionForwardedSpans,
            "maximum_raw_rms": maximumRawRMS, "maximum_render_rms": maximumRenderRMS,
            "playback_started_at_ns": playbackAt as Any? ?? NSNull(),
            "injection_scheduled_at_ns": injectionScheduledAt as Any? ?? NSNull(),
            "injection_started_at_ns": positiveStartedAt as Any? ?? NSNull(),
            "injected_sample_count": injection.injectedSampleCount,
            "first_source_gate_at_ns": firstRecordedGate as Any? ?? firstGateAt as Any? ?? NSNull(),
            "first_forward_observed_at_ns": firstForwardAt as Any? ?? NSNull(),
            "first_runtime_acoustic_observed_at_ns": firstAcousticAt as Any? ?? NSNull(),
            "fixture_semantic_proposal_at_ns": semanticAt as Any? ?? NSNull(),
            "generation_before": session.generation, "generation_after": finalGeneration as Any? ?? NSNull(),
            "playback_timing_generation_before": initialTiming.generation,
            "scheduled_resident_audio_count": scheduledAudio.count,
            "interrupt_count": interruptDelta, "cancel_generation_count": cancelDelta,
            "clear_count": clearDelta, "response_create_count": createDelta,
            "stale_playback_count": stalePlayback,
            "self_interrupt_count": (positive || physicalObservation ? nil : interruptDelta) as Any? ?? NSNull(),
            "confirmed_to_clear_ms": clearLatencyMilliseconds as Any? ?? NSNull(),
            "confirmed_to_clear_limit_ms": 50, "dialogue_entries_before": dialogueBaseline?.count as Any? ?? NSNull(),
            "dialogue_entries_after": historyCount, "memory_unchanged": memoryUnchanged,
            "relationship_unchanged": relationshipUnchanged, "provider_audio_frames": finalProvider.audio,
            "resident_source_sample_rate_hz_assumed": 48_000,
            "resident_source_sample_count": resident.count,
            "audio_feed_source_frames_per_chunk": 4_800,
            "audio_feed_payload_frames_per_chunk": 2_400,
            "audio_feed_payload_duration_ms": 100,
            "audio_feed_pump": physicalRouteOnly
                ? "detached_monotonic_100ms" : "polled_100ms",
            "audio_feed_source_wrap_count": audioSequence > 1
                ? (Int(audioSequence - 1) * 4_800 - 1) / resident.count : 0,
            "audio_feed_max_late_ms": Double(maximumAudioFeedLateNanoseconds) / 1_000_000,
            "audio_feed_overdue_chunk_count": overdueAudioFeedChunks,
            "physical_feed_terminal_sent": physicalFeedTerminalSent,
            "audio_feed_trace_file": "audio-feed-events.json",
            "provider_audio_trace_file": "provider-audio-events.json",
            "output_underrun_count": output.underrunCount,
            "output_pressure_wait_count": output.pressureWaitCount,
            "capture_armed": captureArmed, "capture_frame_count": frames.count,
            "polling_is_decimated": true,
            "capture_metrics_file": mode == .webRTCAEC3
                ? "capture-frames.json" : "runtime-polling.json",
            "physical_echo_only": physicalEchoOnly,
            "physical_observation": physicalObservation,
            "physical_yield_tail_measurement_only": physicalYieldTail,
            "controlled_yield_first_render_content_ns": yieldFirstRenderAt as Any? ?? NSNull(),
            "controlled_yield_target_render_content_ns": yieldTargetRenderAt as Any? ?? NSNull(),
            "controlled_yield_pause_requested_ns": yieldPauseRequestAt as Any? ?? NSNull(),
            "controlled_yield_pause_returned_ns": yieldPauseReturnedAt as Any? ?? NSNull(),
            "controlled_yield_pause_accepted": yieldPauseAccepted,
            "controlled_yield_resume_requested_ns": yieldResumeRequestAt as Any? ?? NSNull(),
            "controlled_yield_resume_returned_ns": yieldResumeReturnedAt as Any? ?? NSNull(),
            "controlled_yield_resume_accepted": yieldResumeAccepted,
            "controlled_yield_recovery_attempted": yieldRecoveryAttempted,
            "controlled_yield_aborted": yieldAborted,
            "controlled_yield_generation": yieldGeneration as Any? ?? NSNull(),
            "controlled_yield_pre_render_frame_count": preYieldRenderTimes.count,
            "controlled_yield_pre_render_gap_count":
                preYieldRenderGapsOver25Milliseconds,
            "controlled_yield_render_callback_count_during_hold":
                callbacksDuringYield.count,
            "controlled_yield_max_render_callback_rms_during_hold":
                callbacksDuringYield.compactMap(\.convertedRMS).max()
                    as Any? ?? NSNull(),
            "controlled_yield_acoustic_tail": physicalYieldTail
                ? "PENDING_OFFLINE_PHYSICAL_AUDIT" : "NOT_APPLICABLE",
            "output_played_chunk_count": output.playedChunkCount,
            "output_playback_completed_count": output.playbackCompletedCount,
            "full_playback_observed_at_ns":
                fullPlaybackObservedAt as Any? ?? NSNull(),
            "physical_route_stayed_exact": physicalRouteStayedExact,
            "physical_speaker_mic_coupling": physicalRouteOnly
                ? "UNVERIFIED" : "NOT_APPLICABLE",
            "physical_audibility": physicalRouteOnly
                ? "UNVERIFIED" : "NOT_APPLICABLE",
            "provisional_pause_count": provisionalPauseCount,
            "provisional_resume_count": provisionalResumeCount,
            "causal_candidate_debug_count": causalCandidateDebug.count,
            "causal_candidate_debug_file": physicalRouteOnly
                ? "causal-candidate-events.json" : NSNull() as Any,
            "timing_trace_file": physicalRouteOnly
                ? "timing-frames.json" : NSNull() as Any,
            "capture_callback_trace_file": captureCallbackTrace != nil
                ? "capture-callbacks.json" : NSNull() as Any,
            "render_callback_trace_file": renderCallbackTrace != nil
                ? "render-callbacks.json" : NSNull() as Any,
            "timing_trace_truncated": timingTrace?.truncated as Any? ?? NSNull(),
            "timing_render_frame_count": timingTrace?.renderFrames.count as Any? ?? NSNull(),
            "timing_capture_frame_count": timingTrace?.captureFrames.count as Any? ?? NSNull(),
            "physical_render_coverage_ms": physicalRouteOnly
                ? physicalRenderCoverageMilliseconds : NSNull() as Any,
            "physical_maximum_render_gap_ms": physicalRouteOnly
                ? physicalMaximumRenderGapMilliseconds : NSNull() as Any,
            "physical_render_gaps_over_25_ms": physicalRouteOnly
                ? physicalRenderGapsOver25Milliseconds : NSNull() as Any,
            "apple_decision_trace_file": appleDecision != nil
                ? "apple-decision-frames.json" : NSNull() as Any,
            "apple_processed_pcm_file": appleDecision != nil
                ? "apple-processed-48k.f32le.pcm" : NSNull() as Any,
            "apple_vad_reads_file": appleVADReads != nil
                ? "apple-vad-reads.json" : NSNull() as Any,
            "apple_decision_frame_count": appleDecision?.trace.frames.count as Any? ?? NSNull(),
            "apple_processed_sample_count": appleDecision?.processedSamples.count as Any? ?? NSNull(),
            "apple_processed_pcm_sha256": appleProcessedSHA256 as Any? ?? NSNull(),
            "apple_input_trace_file": appleInput != nil
                ? "apple-vp-input-callbacks.json" : NSNull() as Any,
            "apple_input_pcm_file": appleInput != nil
                ? "apple-vp-input-native.f32le.pcm" : NSNull() as Any,
            "apple_input_pcm_sha256": appleInputSHA256 as Any? ?? NSNull(),
            "apple_input_sample_count": appleInput?.samples.count as Any? ?? NSNull(),
            "apple_input_captured_channel_count": appleInput?.trace.capturedChannelCount as Any? ?? NSNull(),
            "apple_input_channel_sample_counts": appleInput?.trace.channelSampleCounts as Any? ?? NSNull(),
            "apple_input_all_channels_complete": appleInput?.trace.allChannelsComplete as Any? ?? NSNull(),
            "apple_input_additional_pcm_files": appleInputAdditionalPCM?.indices.map {
                "apple-vp-input-ch\($0 + 1)-native.f32le.pcm"
            } as Any? ?? NSNull(),
            "apple_input_additional_pcm_sha256": appleInputAdditionalSHA256 as Any? ?? NSNull(),
            "apple_input_sample_rate_hz": appleInput?.trace.callbacks.first?
                .inputSampleRate as Any? ?? NSNull(),
            "apple_input_max_copy_us": appleInput?.trace.callbacks.map {
                Double($0.copyNanoseconds) / 1_000
            }.max() as Any? ?? NSNull(),
            "apple_input_trace_truncated": appleInput?.trace.truncated as Any? ?? NSNull(),
            "apple_input_unsupported_format": appleInput?.trace.unsupportedFormat as Any? ?? NSNull(),
            "apple_decision_trace_truncated": appleDecision?.trace.truncated as Any? ?? NSNull(),
            "apple_vad_reads_truncated": appleVADReads?.truncated as Any? ?? NSNull(),
            "provisional_events": provisionalEvents.map { event in
                ["category": event.category,
                 "elapsed_ms": event.elapsedMilliseconds,
                 "playback_sequence": event.audioSequence as Any? ?? NSNull(),
                 "id": event.interactionShortID as Any? ?? NSNull()]
                    as [String: Any]
            },
            "qualification_observations": qualificationObservations
        ]
        if mode == .webRTCAEC3, couplingFrames < 20 {
            result["evidence_limitation"] =
                "Insufficient measured speaker-to-microphone echo coupling"
        } else if physicalRouteOnly {
            result["evidence_limitation"] =
                "Render reference and capture continuity do not establish speaker-to-microphone coupling"
        }
        let runtimeEvents = controller.realtimeSpeechDiagnosticTimeline.events
        engine.clearTest3NearEndInjection()
        await controller.stopRealtimeFullDuplexSpeech()
        await controller.shutdownSpeechAudioHost()
        if let capsule { try save(capsule, directory: directory) }
        try JSONEncoder().encode(runtimeEvents)
            .write(to: directory.appendingPathComponent("runtime-events.json"))
        if physicalRouteOnly {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(causalCandidateDebug).write(
                to: directory.appendingPathComponent("causal-candidate-events.json")
            )
            if let timingTrace {
                try encoder.encode(timingTrace).write(
                    to: directory.appendingPathComponent("timing-frames.json")
                )
            }
            if let captureCallbackTrace {
                try encoder.encode(captureCallbackTrace).write(
                    to: directory.appendingPathComponent("capture-callbacks.json")
                )
            }
            if let renderCallbackTrace {
                try encoder.encode(renderCallbackTrace).write(
                    to: directory.appendingPathComponent("render-callbacks.json")
                )
            }
            if let appleDecision, let appleProcessedPCM {
                try encoder.encode(appleDecision.trace).write(
                    to: directory.appendingPathComponent("apple-decision-frames.json")
                )
                try appleProcessedPCM.write(
                    to: directory.appendingPathComponent(
                        "apple-processed-48k.f32le.pcm"
                    )
                )
            }
            if let appleInput, let appleInputPCM {
                try encoder.encode(appleInput.trace).write(
                    to: directory.appendingPathComponent(
                        "apple-vp-input-callbacks.json"
                    )
                )
                try appleInputPCM.write(
                    to: directory.appendingPathComponent(
                        "apple-vp-input-native.f32le.pcm"
                    )
                )
                for (index, pcm) in (appleInputAdditionalPCM ?? []).enumerated() {
                    try pcm.write(to: directory.appendingPathComponent(
                        "apple-vp-input-ch\(index + 1)-native.f32le.pcm"
                    ))
                }
            }
            if let appleVADReads {
                try encoder.encode(appleVADReads).write(
                    to: directory.appendingPathComponent("apple-vad-reads.json")
                )
            }
        }
        try writeJSON(polling, to: directory.appendingPathComponent("runtime-polling.json"))
        try writeJSON(audioFeedSchedule, to: directory.appendingPathComponent("audio-feed-events.json"))
        try JSONEncoder().encode(providerAudioEvents).write(
            to: directory.appendingPathComponent("provider-audio-events.json")
        )
        try JSONEncoder().encode(playbackEvents).write(to: directory.appendingPathComponent("playback-events.json"))
        return result
    }

    private static func save(_ capture: MacSpeechAcousticReplayCaptureSnapshot, directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var files: [String: Any] = [:]
        func write(_ data: Data, name: String) throws {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard try sha256(url) == expected else { throw RunnerError.evidenceWriteMismatch }
            files[name] = ["sha256": expected, "byte_count": data.count]
        }
        try write(encoder.encode(capture.captureFrames), name: "capture-frames.json")
        try write(encoder.encode(capture.renderFrames), name: "render-frames.json")
        try write(encoder.encode(capture.audioCalls), name: "audio-calls.json")
        try write(encoder.encode(capture.controlEvents), name: "control-events.json")
        try write(encoder.encode(capture.initialState), name: "initial-state.json")
        try write(encoder.encode(capture.finalState), name: "final-state.json")
        for (name, samples) in [("raw-mic-48k", capture.rawMicrophoneSamples),
            ("render-48k", capture.chronologicalRenderSamples), ("clean-48k", capture.aecCleanSamples),
            ("linear-16k", capture.aecLinearSamples)] {
            try write(samples.withUnsafeBytes { Data($0) }, name: name + ".f32le.pcm")
        }
        try writeJSON([
            "schema_version": 1, "attempt_id": capture.attemptID.uuidString,
            "is_sealed": capture.isSealed,
            "seal_reason": capture.sealReason?.rawValue as Any? ?? NSNull(),
            "target_post_playback_capture_frames": capture.targetPostPlaybackCaptureFrameCount,
            "post_playback_capture_frames": capture.postPlaybackCaptureFrameCount,
            "capture_frames": capture.captureFrames.count, "render_frames": capture.renderFrames.count,
            "exact_replay_ready": capture.isExactReplayReady,
            "test3_acceptance": "NOT_ESTABLISHED", "files": files
        ], to: directory.appendingPathComponent("capsule-integrity.json"))
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

    private static func pcmRMS10ms(_ pcm: Data) -> [Double] {
        pcm.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 480).map { start in
                var energy = 0.0
                for offset in stride(from: start, to: start + 480, by: 2) {
                    let sample = Double(Int16(littleEndian:
                        bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self))) / 32_768
                    energy += sample * sample
                }
                return sqrt(energy / 240)
            }
        }
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
    private struct TransferConfiguration: Decodable {
        let schema_version: Int
        let resident_length: Int
        let near_length: Int
        let fixture_length: Int
    }
    private enum RunnerError: Error {
        case invalidConfiguration, invalidPCM, evidenceDirectoryExists,
            evidenceWriteMismatch, microphoneNotAuthorized, timingTraceUnavailable,
            routeNotListening, aecUnavailable
        case wrongPhysicalRoute(String)
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
        func appendEnqueueRequested(generation: UInt64, sequence: UInt64) {
            let entry = Entry(time: DispatchTime.now().uptimeNanoseconds,
                generation: generation, sequence: sequence,
                kind: "enqueue_requested", accepted: nil)
            lock.withLock { entries.append(entry) }
        }
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
        struct AudioEvent: Codable, Sendable {
            let time: UInt64
            let sequence: UInt64
            let kind: String
            let queueDepth: Int
            let directHandoff: Bool
        }
        private var events: [RealtimeResidentBrainEvent] = []
        private var audioEvents: [AudioEvent] = []
        private var continuation: CheckedContinuation<RealtimeResidentBrainEvent, Error>?
        private var session: RealtimeBrainSessionIdentity?
        private var revision: UInt64 = 1
        private var counters = Counts()
        nonisolated struct Counts: Sendable { var interrupt = 0; var cancel = 0; var create = 0; var audio = 0 }
        func counts() -> Counts { counters }
        func enqueueAudioUnlessInterrupted(_ event: RealtimeResidentBrainEvent) -> Bool {
            guard counters.interrupt == 0 else { return false }
            enqueue(event)
            return true
        }
        func audioEventSnapshot() -> [AudioEvent] { audioEvents }
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
            if !events.isEmpty {
                let event = events.removeFirst()
                if case .residentAudioDelta(let audio) = event.kind {
                    audioEvents.append(AudioEvent(time: DispatchTime.now().uptimeNanoseconds,
                        sequence: audio.sequence, kind: "received", queueDepth: events.count,
                        directHandoff: false))
                }
                return event
            }
            let event: RealtimeResidentBrainEvent = try await withCheckedThrowingContinuation {
                continuation = $0
            }
            if case .residentAudioDelta(let audio) = event.kind {
                audioEvents.append(AudioEvent(time: DispatchTime.now().uptimeNanoseconds,
                    sequence: audio.sequence, kind: "received", queueDepth: events.count,
                    directHandoff: true))
            }
            return event
        }
        func closeSession(_ command: RealtimeBrainCloseSessionCommand) async throws {
            let pending = continuation
            continuation = nil
            events.removeAll()
            pending?.resume(throwing: RealtimeResidentBrainError.cancelled)
        }
        func enqueue(_ event: RealtimeResidentBrainEvent) {
            let directHandoff = continuation != nil
            if case .residentAudioDelta(let audio) = event.kind {
                audioEvents.append(AudioEvent(time: DispatchTime.now().uptimeNanoseconds,
                    sequence: audio.sequence, kind: "enqueued",
                    queueDepth: events.count + (directHandoff ? 0 : 1),
                    directHandoff: directHandoff))
            }
            if let pending = continuation {
                continuation = nil
                if case .residentAudioDelta(let audio) = event.kind {
                    audioEvents.append(AudioEvent(time: DispatchTime.now().uptimeNanoseconds,
                        sequence: audio.sequence, kind: "handed_off",
                        queueDepth: events.count, directHandoff: true))
                }
                pending.resume(returning: event)
            } else { events.append(event) }
        }
    }
}
#endif
