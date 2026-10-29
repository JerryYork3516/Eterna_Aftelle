@preconcurrency import AVFoundation
import CoreAudio
import Foundation

private struct R81CredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? { nil }
}

private extension RealtimeInterruptionEvidenceTests {
    static func testD1Only() async throws {
        let exportDirectory = try d1ExportTestDirectory()
        expect(!FileManager.default.fileExists(atPath: exportDirectory.path),
               "D1 starts without exporting any evidence")
        testD1LaunchMode()
        await testD1InitializationIsolation()
        testD1PreparationAndConsent()
        try await testD1ListeningCapture()
        try await testD1PlaybackScenarios()
        await testD1StopDuringAuthorization()
        await testD1PermissionAndCaptureFailures()
        await testD1ByteLimitAndPreviousResult()
        try await testD1PlaybackFailure()
        try await testD1PlaybackPressureAndLateCompletion()
        await testD1StaleCapture()
        await testD1RouteChange()
        expect(!FileManager.default.fileExists(atPath: exportDirectory.path),
               "Stop and failure never automatically export")
        try await testD2SilentSmoke()
        await testD2SilentPermissionFence()
        let remaining = try FileManager.default.contentsOfDirectory(atPath: exportDirectory.path)
        expect(remaining.isEmpty, "explicit silent exports leave no unknown synthetic files")
        try FileManager.default.removeItem(at: exportDirectory)
        print("d1_export_synthetic_cleanup=PASS")
        print("d1_dependency_factory_calls=0")
        print("d1_initialization_microphone_queries=0")
        print("d1_initialization_microphone_requests=0")
        print("d1_initialization_capture_starts=0")
        print("d1_initialization_playback_starts=0")
        print("d1_only_cases=\(cases)")
        print("d1_only_checks=\(checks)")
        try await testComprehensiveC()
        try await testStatsOnlyC()
        try await testAcousticAGCProfiles()
        try await testWarmupPreparation()
        try await testScoreControl()
    }

    static func testD2SilentSmoke() async throws {
        for scenario in AppleVPAcousticTestScenario.allCases {
            cases += 1
            let stack = D1ControllerStack(byteLimit: 1920, silentScenario: scenario)
            stack.controller.start()
            stack.controller.start()
            await waitUntil("silent smoke capture running") {
                stack.controller.appleVPAcousticTestState.phase == .running
            }
            if scenario != .humanOnly {
                await waitUntil("silent smoke complete zero output") {
                    stack.player.completeScheduledChunk()
                    let output = await stack.output.currentSnapshot()
                    return stack.player.payloads.reduce(0) { $0 + $1.count } == 96000
                        && output.state == .completed
                }
                expect(stack.player.payloads.allSatisfy { $0.allSatisfy { $0 == 0 } },
                       "silent smoke schedules zero PCM through the original player")
            }
            stack.capture.emitPackets(2)
            await waitUntil("silent smoke sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            let jsonURL = try stack.controller.appleVPAcousticTestExportURL(asWAV: false)
            await waitUntil("silent smoke stats exported") { FileManager.default.fileExists(atPath: jsonURL.path) }
            defer { try? FileManager.default.removeItem(at: jsonURL) }
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any]
            expect(manifest?["retained_pcm_bytes"] as? Int == 0, "actual input content is not retained")
            expect(manifest?["input_device"] as? String == "default_input"
                && manifest?["output_device"] as? String == "default_output",
                "silent statistics retain route aliases without hardware identifiers")
            expect(manifest?["processed_sha256"] is NSNull, "discarded PCM never receives a fabricated digest")
            expect(manifest?["packet_count"] as? Int == 2, "metadata still validates the actual packet sequence")
            expect(manifest?["physical_acceptance"] as? String == "UNVERIFIED", "silent control is not acoustic PASS")
            expect(stack.controller.appleVPAcousticTestState.errorCode == nil, "silent Fake lifecycle completes")
            expect(stack.capture.startCount == 1 && stack.dependencies.calls == 0, "one isolated capture only")
            let requests = await stack.authorization.requestCount()
            expect(requests == 0, "silent mode cannot request a new system permission")
            do {
                _ = try stack.controller.appleVPAcousticTestProcessedWAVData()
                expect(false, "silent mode must refuse raw-input WAV export")
            } catch {
                expect(true, "silent mode refuses raw-input WAV export")
            }
            expectD1Cleanup(stack)
        }
    }

    static func testD2SilentPermissionFence() async {
        cases += 1
        let stack = D1ControllerStack(authorizationState: .notDetermined, silentScenario: .residentOnly)
        stack.controller.start()
        await waitUntil("silent permission refusal") { stack.controller.appleVPAcousticTestState.phase == .sealed }
        let requests = await stack.authorization.requestCount()
        expect(requests == 0 && stack.capture.startCount == 0 && stack.player.startCount == 0,
               "new permission requires a user action, never silent approval")
        expect(stack.controller.appleVPAcousticTestState.errorCode == "microphone_not_authorized",
               "silent permission failure remains explicit")
        expectD1Cleanup(stack)
        if let url = try? stack.controller.appleVPAcousticTestExportURL(asWAV: false) {
            await waitUntil("silent failure stats exported") { FileManager.default.fileExists(atPath: url.path) }
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func testD1LaunchMode() {
        cases += 1
        let flag = AppleVPAcousticTestLaunchMode.argument
        expect(flag == "--apple-vp-acoustic-test", "D1 launch flag is explicit and stable")
        let disabledArguments: [[String]] = [[], ["Aftelle"], ["Aftelle", flag + "=false"], ["Aftelle", flag + "s"]]
        for arguments in disabledArguments {
            expect(!AppleVPAcousticTestLaunchMode.isEnabled(arguments: arguments),
                   "D1 is disabled without the exact launch flag")
        }
        expect(AppleVPAcousticTestLaunchMode.isEnabled(arguments: ["Aftelle", flag]),
               "only the exact flag enables D1")
        for scenario in AppleVPAcousticTestScenario.allCases {
            let duration = AppleVPAcousticTestLaunchMode.collectionDuration(silentScenario: scenario)
            expect(duration == (scenario == .residentOnly ? 18_000_000_000 : 4_000_000_000),
                   "only silent A extends beyond the historical failure boundary")
        }
        expect(AppleVPAcousticTestLaunchMode.collectionDuration(silentScenario: nil) == 15_000_000_000,
               "voiced collection remains limited to fifteen seconds")
    }

    static func testD1InitializationIsolation() async {
        cases += 1
        let spy = D1NormalDependenciesSpy()
        let authorization = R855MicrophoneAuthorizationProvider(authorization: .notDetermined)
        let capture = R81AudioCapture(acousticEchoHost: MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing))
        let host = MacSpeechAudioHost(
            authorizationProvider: authorization, capture: capture, deviceMonitor: R81DeviceMonitor()
        )
        let player = FakeMacSpeechAudioOutputPlayer()
        let output = MacSpeechAudioOutputHost(player: player, deviceMonitor: FakeMacSpeechOutputDeviceMonitor())
        let controller = AppController(
            acousticTestArguments: ["Aftelle", "--apple-vp-acoustic-test"],
            speechAudioHost: host, speechAudioOutputHost: output,
            normalDependenciesFactory: spy.make
        )
        expect(controller.isAppleVPAcousticTestMode, "D1 Controller selects isolated mode before normal dependencies")
        expect(spy.calls == 0, "D1 initialization never constructs normal dependencies")
        expect(!controller.isResidentTextInputAvailable, "D1 initialization restores no resident or session")
        controller.start()
        controller.markSessionUncleanIfPossible()
        controller.persistForNormalTerminationIfPossible()
        await controller.startNativeSpeechInputBridge()
        await controller.shutdownSpeechAudioHost()
        await controller.shutdownSpeechAudioHost()
        expect(spy.calls == 0, "D1 startup and termination never construct normal dependencies")
        expect(!controller.isResidentTextInputAvailable, "D1 lifecycle restores no resident or session")
        let queries = await authorization.queryCount()
        let requests = await authorization.requestCount()
        expect(queries == 0, "D1 mode selection and cleanup never query microphone authorization")
        expect(requests == 0, "D1 mode selection and cleanup never request microphone authorization")
        expect(capture.startCount == 0, "D1 mode selection and cleanup never start capture")
        expect(player.prepareCount == 0, "D1 mode selection and cleanup never prepare playback")
        expect(player.startCount == 0, "D1 mode selection and cleanup never start playback")
        expect(!controller.speechAudioHostSnapshot.isCapturing, "D1 shutdown leaves capture stopped")
        expect(controller.speechAudioOutputHostSnapshot.state == .closed, "D1 shutdown closes the original OutputHost")
    }
}

@MainActor
private final class ComprehensiveCClock {
    let start = DispatchTime.now().uptimeNanoseconds
    var elapsed: UInt64 = 0
    var now: UInt64 {
        start + elapsed
    }
}

private extension RealtimeInterruptionEvidenceTests {
    static func testComprehensiveC() async throws {
        let originalCases = cases
        let originalChecks = checks
        try await testComprehensiveCRepetition()
        try await testComprehensiveCPreconditions()
        try await testComprehensiveCFailures()
        let directory = try d1ExportTestDirectory()
        expect(!FileManager.default.fileExists(atPath: directory.path),
               "C leaves no synthetic exports after all positive and negative controls")
        print("c_preparation_cases=\(cases - originalCases)")
        print("c_preparation_checks=\(checks - originalChecks)")
        print("c_preparation_fake=PASS")
    }

    static func prepareComprehensiveC(
        _ stack: D1ControllerStack, source: URL, discard: Bool = false,
        dataMode: AppleVPAcousticDataMode = .recording,
        processingProfile: MacSpeechAppleVPDebugProfile = .agcOn
    ) {
        expect(stack.controller.prepareAppleVPAcousticTest(
            .doubleTalk, discardPreviousResult: discard, comprehensiveC: true, dataMode: dataMode,
            processingProfile: processingProfile
        ), "C prepares an explicit isolated guided run")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "C selects synthetic offline audio")
        stack.controller.startAppleVPAcousticTest(
            microphoneConsent: true, speakerConsent: true, localCaptureConsent: dataMode == .recording
        )
    }

    static func driveComprehensiveC(
        _ stack: D1ControllerStack, clock: ComprehensiveCClock, dataMode: AppleVPAcousticDataMode? = nil
    ) async {
        await waitUntil("C capture running") { stack.controller.appleVPAcousticTestState.phase == .running }
        expect(stack.player.startCount == stack.capture.startCount - 1,
               "no new playback at the beginning of the human-only stage")
        for tick in 0 ..< 30 {
            clock.elapsed = UInt64(tick) * 500_000_000
            stack.capture.emitPackets(25)
            await waitUntil("C drains each bounded synthetic batch") {
                stack.player.completeScheduledChunk()
                return stack.controller.appleVPAcousticTestState.packetCount == (tick + 1) * 25
            }
            if let dataMode {
                let state = stack.controller.appleVPAcousticTestState
                let retained = dataMode == .statsOnly ? 0 : state.byteCount
                expect(state.dataMode == dataMode && state.retainedPCMByteCount == retained,
                       "every drained batch respects the prepared retention mode")
            }
            if tick == 0 {
                expect(stack.controller.appleVPAcousticTestState.guideStage == "human_only",
                       "C begins with an observable human-only guide")
            }
            if tick == 6 {
                await waitUntil("C synthetic output completes exactly once") {
                    stack.player.completeScheduledChunk()
                    return await stack.output.currentSnapshot().state == .completed
                }
            }
        }
        clock.elapsed = 15_000_000_000
        await waitUntil("C seals and releases resources") {
            stack.controller.appleVPAcousticTestState.phase == .sealed
        }
    }

    static func testComprehensiveCRepetition() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(clock: { clock.now })
        var previousRun: UUID?
        for iteration in 0 ..< 2 {
            cases += 1
            clock.elapsed = 0
            prepareComprehensiveC(stack, source: source, discard: iteration > 0)
            await driveComprehensiveC(stack, clock: clock)
            let state = stack.controller.appleVPAcousticTestState
            expect(state.errorCode == nil && state.packetCount == 750, "C seals all 15 synthetic seconds")
            expect(state.runID != previousRun, "each repeated C has a distinct run identity")
            expect(stack.capture.startCount == iteration + 1 && stack.capture.stopCount == iteration + 1,
                   "repeated C releases the previous capture before starting another")
            previousRun = state.runID
            try expectComprehensiveCManifest(stack.controller)
            let wav = try stack.controller.appleVPAcousticTestProcessedWAVData()
            try expectD1ExportConsent(stack.controller, expected: wav)
            try testComprehensiveCExportPermission(stack.controller)
            expectD1Cleanup(stack)
        }
    }

    static func expectComprehensiveCManifest(_ controller: AppController) throws {
        let manifest = try JSONSerialization.jsonObject(with: controller.appleVPAcousticTestManifestData())
            as? [String: Any]
        let guide = manifest?["comprehensive_c"] as? [String: Any]
        let events = guide?["events_ns"] as? [String: UInt64]
        expect(Set(events?.keys.map { $0 } ?? []) == Set(["human_only", "double_talk", "human_tail", "quiet"]),
               "C evidence has exactly four bounded guidance marks")
        expect(guide?["physical_overlap_seconds"] is NSNull && guide?["human_speech_windows"] is NSNull,
               "software guidance cannot fabricate actual speech or physical overlap")
        expect(manifest?["physical_acceptance"] as? String == "UNVERIFIED", "Fake C cannot pass acoustics")
    }

    static func testComprehensiveCPreconditions() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        for kind in ["denied", "unknown", "output", "capture"] {
            cases += 1
            let authorization: MicrophoneAuthorizationState = kind == "denied" ? .denied
                : kind == "unknown" ? .notDetermined : .authorized
            let stack = D1ControllerStack(
                authorizationState: authorization, requestedAuthorization: authorization,
                failsCaptureStart: kind == "capture"
            )
            if kind == "output" {
                stack.player.prepareError = .outputUnavailable
            }
            prepareComprehensiveC(stack, source: source)
            await waitUntil("C prerequisite failure sealed") {
                stack.controller.appleVPAcousticTestState.phase == .sealed
            }
            expect(stack.controller.appleVPAcousticTestState.errorCode != nil, "C prerequisite failure cannot pass")
            expect(stack.player.startCount == 0, "failed C preflight never plays audio")
            try expectComprehensiveCPartialEvidence(stack.controller)
            expectD1Cleanup(stack)
        }
        try await testComprehensiveCBudget()
    }

    static func testComprehensiveCBudget() async throws {
        cases += 1
        let source = try d1SyntheticPlayback(packets: 301)
        defer { try? FileManager.default.removeItem(at: source) }
        let stack = D1ControllerStack()
        expect(!stack.controller.prepareAppleVPAcousticTest(.humanOnly, comprehensiveC: true),
               "the comprehensive plan cannot silently replace B")
        prepareComprehensiveC(stack, source: source)
        await waitUntil("overlong C asset refused before permission") {
            stack.controller.appleVPAcousticTestState.phase == .sealed
        }
        expect(stack.controller.appleVPAcousticTestState.errorCode == "invalid_playback_wav",
               "a C asset outside the pre-registered six-second budget fails closed")
        expect(stack.capture.startCount == 0 && stack.player.prepareCount == 0,
               "invalid C budget never initializes capture or playback")
        expectD1Cleanup(stack)
    }

    static func testComprehensiveCFailures() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        for kind in ["playback", "timeline", "configuration", "generation", "seal", "cancel", "shutdown", "late"] {
            cases += 1
            let clock = ComprehensiveCClock()
            let stack = D1ControllerStack(clock: { clock.now })
            prepareComprehensiveC(stack, source: source)
            await waitUntil("C failure injection ready") { stack.controller.appleVPAcousticTestState.phase == .running }
            await injectComprehensiveCFailure(kind, stack: stack, clock: clock)
            await waitUntil("C injected failure sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            expect(stack.controller.appleVPAcousticTestState.errorCode != nil, "injected C failure remains a failure")
            try expectComprehensiveCPartialEvidence(stack.controller)
            expectD1Cleanup(stack)
        }
    }

    static func injectComprehensiveCFailure(
        _ kind: String, stack: D1ControllerStack, clock: ComprehensiveCClock
    ) async {
        switch kind {
        case "playback":
            stack.player.scheduleError = .outputUnavailable
            clock.elapsed = 3_000_000_000
        case "late": clock.elapsed = 6_000_000_000
        case "cancel": await stack.controller.stopAppleVPAcousticTest()
        case "shutdown": await stack.controller.shutdownSpeechAudioHost()
        default:
            if kind == "seal" {
                stack.capture.omitsSeal = true
            }
            if kind == "timeline" {
                stack.capture.invalidateTimeline()
            }
            if kind == "configuration" {
                stack.capture.invalidateTimeline(configuration: 2)
            }
            if kind == "generation" {
                stack.capture.emitPreviousGenerationPacket()
            }
            await driveComprehensiveC(stack, clock: clock)
        }
    }

    static func expectComprehensiveCPartialEvidence(_ controller: AppController) throws {
        let manifest = try JSONSerialization.jsonObject(with: controller.appleVPAcousticTestManifestData())
            as? [String: Any]
        expect(manifest?["error"] is String && manifest?["comprehensive_c"] is [String: Any],
               "even failed or unsealed native evidence retains explicit partial run metadata")
        expect(manifest?["source_commit"] is NSNull && manifest?["build_identity"] is NSNull,
               "unbound real source and build identities remain UNKNOWN")
        expectD1ExportRejected("partial JSON export also requires explicit consent") {
            let url = try controller.appleVPAcousticTestExportURL(asWAV: false)
            try controller.writeAppleVPAcousticTestJSON(to: url, localExportConsent: false)
        }
        let url = try controller.appleVPAcousticTestExportURL(asWAV: false)
        let directory = try d1ExportTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try controller.writeAppleVPAcousticTestJSON(to: url, localExportConsent: true)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        expect(saved?["error"] is String, "explicit export preserves the failed run instead of losing all metadata")
    }

    static func testComprehensiveCExportPermission(_ controller: AppController) throws {
        cases += 1
        let directory = try d1ExportTestDirectory()
        let parent = directory.deletingLastPathComponent()
        let attributes = try FileManager.default.attributesOfItem(atPath: parent.path)
        let original = attributes[.posixPermissions] as? NSNumber ?? 0o700
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: original], ofItemAtPath: parent.path) }
        expectD1ExportRejected("an unwritable isolated cache parent cannot redirect evidence elsewhere") {
            let url = try controller.appleVPAcousticTestExportURL(asWAV: false)
            try controller.writeAppleVPAcousticTestJSON(to: url, localExportConsent: true)
        }
        expect(!FileManager.default.fileExists(atPath: directory.path), "permission failure creates no partial export")
    }
}

private extension RealtimeInterruptionEvidenceTests {
    static func testStatsOnlyC() async throws {
        let originalCases = cases
        let originalChecks = checks
        try await testStatsOnlyCRepetition()
        try await testStatsOnlyCConsentAndStop()
        try await testStatsOnlyCFailures()
        let directory = try d1ExportTestDirectory()
        expect(!FileManager.default.fileExists(atPath: directory.path), "statistics tests clean all synthetic exports")
        print("stats_only_cases=\(cases - originalCases)")
        print("stats_only_checks=\(checks - originalChecks)")
        print("stats_only_fake=PASS")
    }

    static func testStatsOnlyCRepetition() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(clock: { clock.now })
        let modes: [AppleVPAcousticDataMode] = [.recording, .statsOnly, .recording, .statsOnly]
        var runIDs = Set<UUID>()
        for (index, mode) in modes.enumerated() {
            cases += 1
            clock.elapsed = 0
            prepareComprehensiveC(stack, source: source, discard: index > 0, dataMode: mode)
            expect(stack.controller.appleVPAcousticTestState.retainedPCMByteCount == 0,
                   "Prepare discards the previous run's recording before switching modes")
            await driveComprehensiveC(stack, clock: clock, dataMode: mode)
            let state = stack.controller.appleVPAcousticTestState
            expect(state.errorCode == nil && state.packetCount == 750, "both modes validate 750 continuous packets")
            if let runID = state.runID {
                runIDs.insert(runID)
            }
            try expectComprehensiveCManifest(stack.controller)
            if mode == .statsOnly {
                try expectStatsOnlyEvidence(stack.controller)
                try testStatsOnlyJSONExport(stack.controller)
                try testStatsOnlyJSONSymlink(stack.controller)
                try testComprehensiveCExportPermission(stack.controller)
            } else {
                let wav = try stack.controller.appleVPAcousticTestProcessedWAVData()
                expect(state.canExportWAV && wav.count == 720_044, "ordinary C retains complete synthetic WAV access")
            }
            expectD1Cleanup(stack)
        }
        expect(runIDs.count == modes.count, "mixed retention modes never reuse a run identity")
    }

    static func expectStatsOnlyEvidence(_ controller: AppController) throws {
        let state = controller.appleVPAcousticTestState
        let manifest = try JSONSerialization.jsonObject(with: controller.appleVPAcousticTestManifestData())
            as? [String: Any]
        expect(state.dataMode == .statsOnly && state.retainedPCMByteCount == 0 && !state.canExportWAV,
               "sealed success, failure and Stop retain no recording and expose no WAV control")
        expect(manifest?["retained_pcm_bytes"] as? Int == 0 && manifest?["processed_sha256"] is NSNull,
               "statistics report actual zero retention and no PCM digest")
        expect(manifest?["data_mode"] as? String == "STATS_ONLY", "each manifest identifies its immutable mode")
        expect(manifest?["input_device"] as? String == "default_input"
            && manifest?["output_device"] as? String == "default_output", "statistics redact hardware identities")
        expectD1ExportRejected("statistics mode refuses WAV encoding") {
            _ = try controller.appleVPAcousticTestProcessedWAVData()
        }
        expectD1ExportRejected("statistics mode refuses WAV destination creation") {
            _ = try controller.appleVPAcousticTestExportURL(asWAV: true)
        }
        let directory = try d1ExportTestDirectory()
        let wav = directory.appendingPathComponent("run-\(state.runID?.uuidString ?? "UNKNOWN").wav")
        expectD1ExportRejected("even explicit export consent cannot write a statistics run as WAV") {
            try controller.writeAppleVPAcousticTestWAV(to: wav, localExportConsent: true)
        }
        expect(!FileManager.default.fileExists(atPath: wav.path), "rejected WAV operations leave no file")
    }

    static func testStatsOnlyJSONExport(_ controller: AppController) throws {
        cases += 1
        let directory = try d1ExportTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try controller.appleVPAcousticTestExportURL(asWAV: false)
        expect(!FileManager.default.fileExists(atPath: directory.path), "statistics never export automatically")
        expectD1ExportRejected("statistics JSON still requires explicit export consent") {
            try controller.writeAppleVPAcousticTestJSON(to: url, localExportConsent: false)
        }
        let outside = directory.deletingLastPathComponent().appendingPathComponent("outside-stats.json")
        expectD1ExportRejected("statistics cannot escape the approved directory") {
            try controller.writeAppleVPAcousticTestJSON(to: outside, localExportConsent: true)
        }
        try controller.writeAppleVPAcousticTestJSON(to: url, localExportConsent: true)
        let before = try Data(contentsOf: url)
        let manifest = try JSONSerialization.jsonObject(with: before) as? [String: Any]
        expect(manifest?["run_id"] as? String == controller.appleVPAcousticTestState.runID?.uuidString,
               "explicit statistics export binds the sealed run")
        try expectD1ExportPermissions(directory: directory, files: [url])
        expectD1ExportRejected("statistics JSON cannot overwrite an existing result") {
            try controller.writeAppleVPAcousticTestJSON(to: url, localExportConsent: true)
        }
        let after = try Data(contentsOf: url)
        expect(after == before, "rejected overwrite preserves the existing statistics")
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        expect(contents == [url.lastPathComponent], "the only exported file is this run's statistics JSON")
    }

    static func testStatsOnlyJSONSymlink(_ controller: AppController) throws {
        cases += 1
        let directory = try d1ExportTestDirectory()
        let target = directory.deletingLastPathComponent().appendingPathComponent("stats-symlink-target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: target)
        expectD1ExportRejected("statistics JSON rejects an evidence-directory symlink") {
            let url = try controller.appleVPAcousticTestExportURL(asWAV: false)
            try controller.writeAppleVPAcousticTestJSON(to: url, localExportConsent: true)
        }
        let contents = try FileManager.default.contentsOfDirectory(atPath: target.path)
        expect(contents.isEmpty, "symlink refusal writes no statistics outside the controlled root")
    }

    static func testStatsOnlyCConsentAndStop() async throws {
        cases += 1
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let stack = D1ControllerStack()
        expect(stack.controller.prepareAppleVPAcousticTest(.doubleTalk, comprehensiveC: true, dataMode: .statsOnly),
               "statistics mode is fixed during Prepare")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "statistics select only synthetic playback")
        for (microphone, speaker) in [(false, true), (true, false)] {
            stack.controller.startAppleVPAcousticTest(
                microphoneConsent: microphone, speakerConsent: speaker, localCaptureConsent: false
            )
            expect(stack.capture.startCount == 0 && stack.player.prepareCount == 0,
                   "statistics never bypass microphone or playback consent")
        }
        stack.controller.startAppleVPAcousticTest(
            microphoneConsent: true, speakerConsent: true, localCaptureConsent: false
        )
        await waitUntil("statistics run started without recording consent") {
            stack.controller.appleVPAcousticTestState.phase == .running
        }
        expect(!stack.controller.prepareAppleVPAcousticTest(
            .doubleTalk, discardPreviousResult: true, comprehensiveC: true, dataMode: .recording
        ), "a running statistics run cannot be changed into recording mode")
        stack.capture.emitPackets(2)
        await waitUntil("statistics drained before Stop") { stack.controller.appleVPAcousticTestState.packetCount == 2 }
        await stack.controller.stopAppleVPAcousticTest()
        try expectStatsOnlyEvidence(stack.controller)
        expectD1Cleanup(stack)
    }

    static func testStatsOnlyCFailures() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        for kind in ["playback", "timeline", "configuration", "generation", "seal", "cancel", "shutdown", "late"] {
            cases += 1
            let clock = ComprehensiveCClock()
            let stack = D1ControllerStack(clock: { clock.now })
            prepareComprehensiveC(stack, source: source, dataMode: .statsOnly)
            await waitUntil("statistics failure injection ready") {
                stack.controller.appleVPAcousticTestState.phase == .running
            }
            await injectComprehensiveCFailure(kind, stack: stack, clock: clock)
            await waitUntil("statistics failure sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            expect(stack.controller.appleVPAcousticTestState.errorCode != nil, "statistics failure cannot become PASS")
            try expectStatsOnlyEvidence(stack.controller)
            try expectComprehensiveCPartialEvidence(stack.controller)
            expectD1Cleanup(stack)
        }
    }
}

private extension RealtimeInterruptionEvidenceTests {
    static func testAcousticAGCProfiles() async throws {
        let originalCases = cases
        let originalChecks = checks
        try await testAcousticAGCRepetition()
        await testAcousticAGCRejections()
        testAcousticAGCPreparation()
        print("acoustic_agc_profile_cases=\(cases - originalCases)")
        print("acoustic_agc_profile_checks=\(checks - originalChecks)")
        print("acoustic_agc_device_access=ZERO")
    }

    static func testAcousticAGCRepetition() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(clock: { clock.now })
        var previousRun: UUID?
        for (index, profile) in [MacSpeechAppleVPDebugProfile.agcOff, .agcOn, .agcOff].enumerated() {
            cases += 1
            clock.elapsed = 0
            let mode: AppleVPAcousticDataMode = index == 2 ? .statsOnly : .recording
            prepareComprehensiveC(stack, source: source, discard: index > 0,
                                  dataMode: mode, processingProfile: profile)
            await waitUntil("AGC profile running") { stack.controller.appleVPAcousticTestState.phase == .running }
            expect(!stack.controller.prepareAppleVPAcousticTest(.humanOnly, processingProfile: .agcOn),
                   "a prepared profile cannot change during capture")
            expect(stack.capture.voiceProcessingSnapshot()?.automaticGainControlEnabled
                == profile.automaticGainControlEnabled, "the requested profile reaches the capture dependency")
            await driveComprehensiveC(stack, clock: clock, dataMode: mode)
            let state = stack.controller.appleVPAcousticTestState
            let manifest = try JSONSerialization.jsonObject(
                with: stack.controller.appleVPAcousticTestManifestData()
            ) as? [String: Any]
            expect(state.processingProfile == profile && state.errorCode == nil,
                   "both explicit profiles complete the unchanged guided C lifecycle")
            expect(state.runID != previousRun && state.packetCount == 750,
                   "repetition binds a fresh run and accepts every continuous synthetic packet")
            expect(manifest?["processing_profile"] as? String == profile.rawValue,
                   "the manifest records the prepared profile independently of actual readback")
            expect(stack.capture.voiceProcessingSnapshot()?.automaticGainControlEnabled == true,
                   "Stop removes the Fake experiment configuration")
            if mode == .statsOnly {
                try expectStatsOnlyEvidence(stack.controller)
            } else {
                let wav = try stack.controller.appleVPAcousticTestProcessedWAVData()
                expect(wav.count > 44,
                       "ordinary recording C retains its original synthetic WAV ability")
            }
            previousRun = state.runID
            expectD1Cleanup(stack)
        }
    }

    static func testAcousticAGCRejections() async {
        for profile in MacSpeechAppleVPDebugProfile.allCases {
            cases += 1
            let stack = D1ControllerStack()
            stack.capture.agcReadbackOverride = !profile.automaticGainControlEnabled
            expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly, processingProfile: profile),
                   "readback negative control prepares explicitly")
            startD1(stack.controller)
            await waitUntil("wrong AGC readback sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            expect(stack.controller.appleVPAcousticTestState.errorCode != nil,
                   "both wrong AGC readbacks fail closed")
            expect(stack.controller.appleVPAcousticTestState.retainedPCMByteCount == 0,
                   "rejected processing produces no recording")
            expectD1Cleanup(stack)
        }
        cases += 1
        let unsupported = D1ControllerStack()
        unsupported.capture.supportsAGCProfile = false
        _ = unsupported.controller.prepareAppleVPAcousticTest(.humanOnly, processingProfile: .agcOff)
        startD1(unsupported.controller)
        await waitUntil("unsupported AGC profile sealed") {
            unsupported.controller.appleVPAcousticTestState.phase == .sealed
        }
        expect(unsupported.capture.startCount == 0, "unsupported AGC-OFF fails before capture start")
        expect(unsupported.controller.appleVPAcousticTestState.errorCode != nil, "unsupported is not PASS")
        expectD1Cleanup(unsupported)
    }

    static func testAcousticAGCPreparation() {
        cases += 1
        let stack = D1ControllerStack()
        expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly), "ordinary Prepare still succeeds")
        expect(stack.controller.appleVPAcousticTestState.processingProfile == .agcOn,
               "the original default remains AGC-ON")
        _ = stack.controller.prepareAppleVPAcousticTest(.humanOnly, processingProfile: .agcOff)
        stack.controller.startAppleVPAcousticTest(
            microphoneConsent: false, speakerConsent: true, localCaptureConsent: true
        )
        expect(stack.capture.startCount == 0 && stack.controller.appleVPAcousticTestState.runID == nil,
               "a prepared OFF selection does not authorize microphone use")
        cases += 1
        let silent = D1ControllerStack(silentScenario: .doubleTalk)
        expect(!silent.controller.prepareAppleVPAcousticTest(.doubleTalk, processingProfile: .agcOff),
               "silent-smoke cannot silently acquire an AGC-OFF experiment")
        expect(silent.capture.startCount == 0, "rejected silent selection starts no device")
    }
}

private extension RealtimeInterruptionEvidenceTests {
    static func testWarmupPreparation() async throws {
        let originalCases = cases
        let originalChecks = checks
        try await testWarmupRepetition()
        try await testWarmupFailures()
        try await testWarmupStartReadbackFailures()
        try await testWarmupQueuedTail()
        testWarmupInvalidPrepare()
        try testWarmupPacketBoundary()
        print("warmup_control_cases=\(cases - originalCases)")
        print("warmup_control_checks=\(checks - originalChecks)")
        print("warmup_control_device_access=ZERO")
    }

    static func testScoreControl() async throws {
        let originalCases = cases
        let originalChecks = checks
        for profile in [MacSpeechWarmupProfile.zero, .four] {
            try await testScoreControlRun(profile)
        }
        try await testScoreControlRun(.four, processingProfile: .agcOff)
        try await testScoreControlRun(.four, processingProfile: .agcOff, mode: .statsOnly)
        try testScoreControlPreparationFence()
        try await testScoreControlCancellation()
        try testScoreControlRejectedDescriptors()
        try testScoreControlBlockedReader()
        print("score_control_cases=\(cases - originalCases)")
        print("score_control_checks=\(checks - originalChecks)")
        print("score_control_device_access=ZERO")
    }

    static func scoreControlEvents(_ channel: Pipe) throws -> [[String: Any]] {
        var bytes = [UInt8](repeating: 0, count: 2048)
        let count = read(channel.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
        expect(count > 0, "the dedicated control pipe contains bounded events")
        return try bytes.prefix(max(0, count)).split(separator: 10).map {
            try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] ?? [:]
        }
    }

    static func testScoreControlRun(
        _ profile: MacSpeechWarmupProfile, processingProfile: MacSpeechAppleVPDebugProfile = .agcOn,
        mode: AppleVPAcousticDataMode = .recording
    ) async throws {
        cases += 1
        let channel = Pipe()
        defer { try? channel.fileHandleForReading.close(); try? channel.fileHandleForWriting.close() }
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(clock: { clock.now },
                                      scoreControlDescriptor: channel.fileHandleForWriting.fileDescriptor)
        stack.capture.contentStartOverride = clock.start
        prepareWarmupC(stack, source: source, profile: profile, mode: mode, processingProfile: processingProfile)
        await driveWarmupC(stack, clock: clock, profile: profile)
        let events = try scoreControlEvents(channel)
        expect(events.count == 2, "one schedule and one terminal stop are emitted")
        expect(events.map { $0["event"] as? String } == ["schedule", "stop"], "control order is fixed")
        let scheduled = events[0]
        let start = clock.start + profile.nanoseconds
        expect(scheduled["score_start_ns"] as? UInt64 == start, "the trigger uses the content-window score anchor")
        expect(scheduled["proxy_stop_ns"] as? UInt64 == start + 11_000_000_000, "quiet starts at score11")
        expect(scheduled["run_id"] as? String == stack.controller.appleVPAcousticTestState.runID?.uuidString,
               "the control event belongs to the active run")
        expect(events[1]["run_id"] as? String == scheduled["run_id"] as? String, "Stop retains run identity")
        expect(stack.controller.appleVPAcousticTestState.retainedPCMByteCount == (mode == .recording ? 720_000 : 0),
               "the control pipe cannot enlarge the score recording")
        expect(stack.controller.appleVPAcousticTestState.processingProfile == processingProfile,
               "the external control channel cannot change the prepared AGC profile")
        if mode == .statsOnly {
            try expectStatsOnlyEvidence(stack.controller)
        }
        expectD1Cleanup(stack)
    }

    static func testScoreControlPreparationFence() throws {
        for profile in MacSpeechAppleVPDebugProfile.allCases {
            cases += 1
            let channel = Pipe()
            defer { try? channel.fileHandleForReading.close(); try? channel.fileHandleForWriting.close() }
            let stack = D1ControllerStack(scoreControlDescriptor: channel.fileHandleForWriting.fileDescriptor)
            expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly, processingProfile: profile),
                   "an independent AGC profile remains available without external score control")
            startD1(stack.controller)
            let state = stack.controller.appleVPAcousticTestState
            expect(state.errorCode == "external_playback_control_unavailable" && state.runID == nil,
                   "a valid control descriptor does not qualify an unregistered comparison")
            expect(stack.capture.startCount == 0 && stack.player.startCount == 0,
                   "external control qualification fails before any Capture or Playback")
        }
    }

    static func testScoreControlCancellation() async throws {
        cases += 1
        let channel = Pipe()
        defer { try? channel.fileHandleForReading.close(); try? channel.fileHandleForWriting.close() }
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(clock: { clock.now },
                                      scoreControlDescriptor: channel.fileHandleForWriting.fileDescriptor)
        prepareWarmupC(stack, source: source, profile: .four)
        await waitUntil("control run starts") { stack.controller.appleVPAcousticTestState.phase == .running }
        await stack.controller.stopAppleVPAcousticTest()
        let events = try scoreControlEvents(channel)
        expect(events.count == 2 && events[1]["event"] as? String == "stop",
               "cancellation during warm-up cancels future proxy playback")
        expect(stack.controller.appleVPAcousticTestState.retainedPCMByteCount == 0,
               "warm-up cancellation retains no PCM")
        expectD1Cleanup(stack)
    }

    static func testScoreControlRejectedDescriptors() throws {
        for value in ["0", "invalid", "2147483647"] {
            cases += 1
            var rejected = false
            do { _ = try AppleVPScoreControl(arguments: [AppleVPScoreControl.argument + value]) } catch {
                rejected = true
            }
            expect(rejected, "invalid or standard descriptors are never accepted")
        }
        cases += 1
        let disabled = try AppleVPScoreControl(arguments: ["Aftelle"])
        expect(disabled == nil, "the normal launch has no control channel")
    }

    static func testScoreControlBlockedReader() throws {
        cases += 1
        let channel = Pipe()
        defer { try? channel.fileHandleForReading.close(); try? channel.fileHandleForWriting.close() }
        let descriptor = channel.fileHandleForWriting.fileDescriptor
        let control = try AppleVPScoreControl(arguments: [AppleVPScoreControl.argument + String(descriptor)])
        expect(fcntl(descriptor, F_GETFL) & O_NONBLOCK != 0, "control writes never wait on the reader")
        var padding = [UInt8](repeating: 0, count: 512)
        var writtenPackets = 0
        while writtenPackets < 256, write(descriptor, &padding, padding.count) >= 0 {
            writtenPackets += 1
        }
        expect(writtenPackets < 256, "the negative control really fills the pipe")
        var rejected = false
        do { try control?.send("schedule", runID: UUID(), scoreStart: 1) } catch { rejected = true }
        expect(rejected, "a blocked control channel fails instead of pretending playback was triggered")
        try channel.fileHandleForReading.close()
        rejected = false
        do { try control?.send("stop", runID: UUID()) } catch { rejected = true }
        expect(rejected, "a closed reader is an error rather than SIGPIPE or a false success")
    }

    static func prepareWarmupC(
        _ stack: D1ControllerStack, source: URL, profile: MacSpeechWarmupProfile,
        mode: AppleVPAcousticDataMode = .recording, discard: Bool = false,
        processingProfile: MacSpeechAppleVPDebugProfile = .agcOn
    ) {
        expect(stack.controller.prepareAppleVPAcousticTest(
            .doubleTalk, discardPreviousResult: discard, comprehensiveC: true,
            dataMode: mode, processingProfile: processingProfile, warmupProfile: profile
        ), "warm-up profile is fixed at Prepare")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "synthetic source selected")
        startD1(stack.controller)
    }

    static func driveWarmupC(
        _ stack: D1ControllerStack, clock: ComprehensiveCClock, profile: MacSpeechWarmupProfile,
        queuedTail: Int = 0, residentEnabled: Bool = true
    ) async {
        await waitUntil("warm-up capture started") { stack.controller.appleVPAcousticTestState.phase == .running }
        let starts = stack.player.startCount
        expect(!stack.controller.prepareAppleVPAcousticTest(
            .doubleTalk, discardPreviousResult: true, comprehensiveC: true,
            warmupProfile: profile == .four ? .zero : .four
        ), "a running experiment cannot switch its prepared warm-up profile")
        let prepared = stack.controller.appleVPAcousticTestState.processingProfile
        expect(!stack.controller.prepareAppleVPAcousticTest(
            .doubleTalk, discardPreviousResult: true, comprehensiveC: true,
            processingProfile: prepared == .agcOn ? .agcOff : .agcOn, warmupProfile: .four
        ), "a running experiment cannot switch AGC even when both preparations are valid")
        let warmupTicks = profile == .four ? 8 : 0
        for tick in 0 ..< (30 + warmupTicks) {
            clock.elapsed = UInt64(tick) * 500_000_000
            let withheld = tick == 29 + warmupTicks ? queuedTail : 0
            stack.capture.emitPackets(25 - withheld, marker: tick < warmupTicks ? 9 : 1)
            let expected = max(0, tick + 1 - warmupTicks) * 25 - withheld
            await waitUntil("bounded warm-up batch drained") {
                stack.player.completeScheduledChunk()
                let state = stack.controller.appleVPAcousticTestState
                let seen = state.drainedPacketCount
                return state.packetCount == expected && seen == UInt64((tick + 1) * 25 - withheld)
            }
            if tick < warmupTicks {
                let state = stack.controller.appleVPAcousticTestState
                expect(state.retainedPCMByteCount == 0 && state.guideStage == "warmup",
                       "warm-up processes packets but retains no recording and starts no scoring")
                expect(stack.player.startCount == starts, "warm-up never starts the Player")
            }
            expect(stack.controller.appleVPAcousticTestState.retainedPCMByteCount <= 720_000,
                   "19-second processing cannot enlarge the recording cap")
            if let onset = stack.controller.appleVPAcousticTestState.humanOnsetProfile, tick >= warmupTicks {
                let due = clock.elapsed >= profile.nanoseconds + onset.cueDelayNanoseconds
                expect((stack.controller.appleVPAcousticTestState.humanSpeechCueAtNanoseconds != nil) == due,
                       "F1 has no early cue and never changes the score origin")
            }
            if residentEnabled, tick == warmupTicks + 6 {
                await waitUntil("one warm-up output completes") {
                    stack.player.completeScheduledChunk()
                    return await stack.output.currentSnapshot().state == .completed
                }
            }
        }
        if queuedTail > 0 {
            stack.capture.emitPackets(queuedTail)
        }
        clock.elapsed = 15_000_000_000 + profile.nanoseconds
        await waitUntil("warm-up run sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
    }

    static func runtimeDevice(
        _ id: UInt32, input: UInt32, output: UInt32, aggregate: Bool = false
    ) -> MacSpeechRuntimeReadback.Device {
        MacSpeechRuntimeReadback.Device(
            id: id, transport: aggregate ? 3 : 1, aggregate: aggregate, alive: true,
            inputChannels: input, outputChannels: output,
            inputStreams: input == 0 ? [] : [.init(owner: id, direction: 1, start: 1, channels: input, rate: 16000)],
            outputStreams: output == 0 ? [] : [.init(owner: id, direction: 0, start: 1, channels: output, rate: 48000)]
        )
    }

    static func testM04RouteBinding() {
        cases += 1
        let microphone = runtimeDevice(1, input: 1, output: 0)
        let speaker = runtimeDevice(2, input: 0, output: 2)
        let node = runtimeDevice(100, input: 1, output: 2, aggregate: true)
        func route(_ aggregate: MacSpeechRuntimeReadback.Aggregate) -> MacSpeechRuntimeReadback.Route {
            .init(defaultInput: microphone, defaultOutput: speaker, actualInput: aggregate.device,
                  actualOutput: aggregate.device, aggregates: [aggregate])
        }
        let valid = MacSpeechRuntimeReadback.Aggregate(device: node, members: [microphone, speaker],
                                                       activeMembers: [1, 2], tapCount: 0, activeTapCount: 0)
        expect(route(valid).binding == "AGGREGATE_IO_DIRECTION_QUALIFIED",
               "different node IDs can represent a verified physical aggregate pair")
        let direct = MacSpeechRuntimeReadback.Route(defaultInput: microphone, defaultOutput: speaker,
                                                    actualInput: microphone, actualOutput: speaker, aggregates: [])
        expect(direct.binding == "NODE_IDS_MATCH_DEFAULTS", "direct hardware identities are verified")
        let wrong = MacSpeechRuntimeReadback.Route(defaultInput: microphone, defaultOutput: speaker,
                                                   actualInput: speaker, actualOutput: speaker, aggregates: [])
        expect(wrong.binding == "UNKNOWN_UNVERIFIED_BINDING", "default route alone cannot prove actual input")
        testM04Membership(microphone, speaker: speaker, node: node)
        for stream in [
            MacSpeechRuntimeReadback.Stream(owner: 100, direction: 0, start: 1, channels: 1, rate: 16000),
            .init(owner: 99, direction: 1, start: 1, channels: 1, rate: 16000),
            .init(owner: 100, direction: 1, start: 2, channels: 1, rate: 16000),
            .init(owner: 100, direction: 1, start: 1, channels: 2, rate: 16000),
            .init(owner: 100, direction: 1, start: 1, channels: 1, rate: .nan)
        ] {
            let broken = MacSpeechRuntimeReadback.Device(
                id: node.id, transport: node.transport, aggregate: true, alive: true,
                inputChannels: 1, outputChannels: 2, inputStreams: [stream], outputStreams: node.outputStreams
            )
            let value = MacSpeechRuntimeReadback.Aggregate(device: broken, members: valid.members,
                                                           activeMembers: valid.activeMembers,
                                                           tapCount: 0, activeTapCount: 0)
            expect(route(value).binding == "UNKNOWN_UNVERIFIED_BINDING",
                   "aggregate stream direction, owner, ordering, width and rate must match")
        }
    }

    static func testM04Membership(
        _ microphone: MacSpeechRuntimeReadback.Device, speaker: MacSpeechRuntimeReadback.Device,
        node: MacSpeechRuntimeReadback.Device
    ) {
        cases += 1
        for (members, active, taps, activeTaps) in [
            ([microphone, speaker], [UInt32(1)], Optional(0), Optional(0)),
            ([microphone, speaker], [1, 1], 0, 0),
            ([microphone, microphone], [1, 2], 0, 0),
            ([microphone, speaker, runtimeDevice(3, input: 0, output: 1)], [1, 2, 3], 0, 0),
            ([microphone, speaker], [1, 2], 1, 0),
            ([microphone, speaker], [1, 2], 0, 1),
            ([microphone, speaker], [1, 2], nil, 0),
            ([microphone, speaker], [1, 2], 0, nil)
        ] {
            let value = MacSpeechRuntimeReadback.Aggregate(device: node, members: members, activeMembers: active,
                                                           tapCount: taps, activeTapCount: activeTaps)
            expect(!value.qualifies(input: microphone, output: speaker),
                   "missing, duplicated, extra, tapped or unreadable membership never qualifies")
        }
    }

    static func testM04BoundedReadbacks() throws {
        cases += 1
        typealias Readback = MacSpeechRuntimeReadback
        let run = UUID()
        let identity = Readback.Identity(runID: run, generation: 1, configurationID: 2)
        var records: [Readback.Snapshot] = []
        var reads = 0
        func read() -> Readback.Payload {
            reads += 1
            return runtimePayload(reads)
        }
        func take(_ phase: Readback.Phase, as value: Readback.Identity? = nil, active: Bool = true) -> Bool {
            Readback.record(phase, identity: value ?? identity, active: active, snapshots: &records, read: read)
        }
        expect(!take(.residentPlaybackStarted), "playback cannot fabricate a missing engine-start snapshot")
        expect(!take(.engineStarted, active: false), "stopped or invalidated runs cannot query devices")
        expect(reads == 0, "rejected control points perform zero reads")
        expect(take(.engineStarted), "one engine-start snapshot records even unavailable HAL fields")
        let foreign: [Readback.Identity] = [
            .init(runID: UUID(), generation: 1, configurationID: 2),
            .init(runID: run, generation: 2, configurationID: 2),
            .init(runID: run, generation: 1, configurationID: 3)
        ]
        for value in foreign {
            expect(!take(.residentPlaybackStarted, as: value), "foreign run/generation/configuration is rejected")
        }
        expect(!take(.engineStarted), "duplicate start cannot query devices again")
        expect(reads == 1, "rejected identities and duplicate points are side-effect free")
        expect(take(.residentPlaybackStarted), "playback records the same run and configuration")
        expect(!take(.residentPlaybackStarted), "two snapshots is the hard per-run cap")
        expect(reads == 2 && records.count == 2, "no readback retry or extra snapshot")
        try testM04ReadbackManifest(records, run: run)
        records.removeAll(keepingCapacity: true)
        expect(take(.engineStarted, as: .init(runID: UUID(), generation: 2, configurationID: 3)),
               "a new preparation receives independent run-local evidence")
        print("m04_runtime_readback_fake=PASS")
        print("m04_runtime_device_reads=FAKE_ONLY")
    }

    static func runtimePayload(_ read: Int) -> MacSpeechRuntimeReadback.Payload {
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3) else {
            fatalError("FAILED: synthetic runtime layout")
        }
        let format = MacSpeechPlaybackFormatWitness(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, interleaved: false, channelLayout: layout)
        )
        let names = ["inputOutput", "playerOutput", "mixerPlayerInput", "mixerOutput", "outputInput", "hardwareOutput"]
        var formats = Dictionary(uniqueKeysWithValues: names.map { ($0, format) })
        formats["hardwareOutput"] = MacSpeechPlaybackFormatWitness(
            AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        )
        let microphone = runtimeDevice(1, input: 1, output: 0)
        let speaker = runtimeDevice(2, input: 0, output: 2)
        let node = runtimeDevice(100, input: 1, output: 2, aggregate: true)
        let aggregate = MacSpeechRuntimeReadback.Aggregate(
            device: node, members: [microphone, speaker], activeMembers: [1, 2], tapCount: 0, activeTapCount: 0
        )
        let route: MacSpeechRuntimeReadback.Route? = read == 1 ? nil : .init(
            defaultInput: microphone, defaultOutput: speaker, actualInput: node, actualOutput: node,
            aggregates: [aggregate]
        )
        return .init(readStartedAtNs: UInt64(read * 100), readFinishedAtNs: UInt64(read * 100 + 10),
                     voiceProcessing: ["inputEnabled": true, "outputEnabled": true, "agcEnabled": read == 1,
                                       "bypass": false, "inputMuted": false],
                     formats: formats, playerMixerBus: 0, mixerOutputConnected: true, route: route,
                     issues: route == nil ? ["synthetic_route_unavailable"] : [],
                     bindingStatus: route?.binding ?? "UNKNOWN_READ_FAILED")
    }

    static func testM04ReadbackManifest(
        _ records: [MacSpeechRuntimeReadback.Snapshot], run: UUID
    ) throws {
        cases += 1
        var timing = MacSpeechTimingSnapshot(runID: run, captureGeneration: 1)
        timing.runtimeReadbacks = records
        let data = try JSONEncoder().encode(timing)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let encoded = json?["runtimeReadbacks"] as? [[String: Any]]
        expect(encoded?.count == 2 && encoded?.allSatisfy { $0["runID"] as? String == run.uuidString } == true,
               "existing timing manifest carries two same-run snapshots")
        let payload = encoded?.first?["payload"] as? [String: Any]
        expect((payload?["formats"] as? [String: Any])?.count == 6,
               "all six graph and hardware format witnesses are exported")
        expect(payload?["bindingStatus"] as? String == "UNKNOWN_READ_FAILED",
               "read failure remains UNKNOWN instead of a cached valid route")
        let hardware = (payload?["formats"] as? [String: [String: Any]])?["hardwareOutput"]
        expect(hardware?["sampleRate"] as? Double == 48000, "hardware format is independent of the VP graph")
        expect(records[1].payload.voiceProcessing["agcEnabled"] == false
            && records[1].payload.readStartedAtNs == 200,
            "later actual properties and read time cannot be replaced by the first cached snapshot")
        expect(records[1].payload.route?.aggregates.first?.members.count == 2
            && records[1].payload.bindingStatus == "AGGREGATE_IO_DIRECTION_QUALIFIED",
            "qualified aggregate membership remains in the same-run record")
        expect(String(data: data, encoding: .utf8)?.contains("pcm") == false, "readbacks contain no PCM payload")
    }

    static func testM12EvidenceSchema() throws {
        cases += 1
        var timing = MacSpeechTimingSnapshot(runID: UUID(), captureGeneration: 1)
        timing.runtimeReadbacks = [.init(phase: .engineStarted, runID: timing.runID,
                                         captureGeneration: 1, configurationID: 2, payload: runtimePayload(1))]
        let data = try JSONEncoder().encode(timing)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = ((json?["runtimeReadbacks"] as? [[String: Any]])?.first?["payload"]) as? [String: Any]
        let process = payload?["processBinding"] as? [String: Any]
        let events = json?["engineConfigurationEvents"] as? [String: Any]
        expect(process?["status"] as? String == "UNAVAILABLE"
            && events?["status"] as? String == "UNAVAILABLE",
            "M12 must export explicit UNAVAILABLE process and Engine-event evidence instead of missing fields")
    }

    static func m12ProcessReader(_ mode: String = "direct") -> MacSpeechRuntimeReadback.ProcessReader {
        let microphone = runtimeDevice(1, input: 1, output: 0)
        let speaker = runtimeDevice(2, input: 0, output: 2)
        let node = runtimeDevice(100, input: 1, output: 2, aggregate: true)
        var pidReads = 0
        return .init(translate: { _ in
            if mode == "halFailure" {
                throw NSError(domain: "SyntheticHAL", code: -50)
            }
            return mode == "missingProcess" ? 0 : 89
        }, pid: { _ in
            pidReads += 1
            return mode == "wrongPID" || (mode == "changedPID" && pidReads == 2) ? 4322 : 4321
        }, devices: { _, scope in try m12ProcessDevices(mode, scope: scope)
        }, device: { deviceID in
            if mode == "wrongDirection" {
                return speaker
            }
            if mode == "invalidStream" {
                return .init(id: deviceID, transport: 1, aggregate: false, alive: true,
                             inputChannels: 1, outputChannels: 2, inputStreams: [], outputStreams: [])
            }
            switch deviceID {
            case 1: return microphone
            case 2: return speaker
            case 100: return node
            default: return runtimeDevice(deviceID, input: 1, output: 0)
            }
        }, aggregate: { _ in
            .init(device: node, members: [microphone, speaker], activeMembers: [1, 2],
                  tapCount: mode == "aggregateUnknown" ? nil : 0, activeTapCount: 0)
        })
    }

    static func m12ProcessDevices(_ mode: String, scope: UInt32) throws -> [UInt32] {
        switch mode {
        case "listFailure": throw NSError(domain: "SyntheticHAL", code: -2000)
        case "empty": return []
        case "duplicate": return [1, 1]
        case "oversized": return Array(1 ... 17)
        case "aggregate", "aggregateUnknown": return [100]
        case "multiple" where scope == kAudioObjectPropertyScopeInput: return [1, 3]
        default: return scope == kAudioObjectPropertyScopeInput ? [1] : [2]
        }
    }

    static func testM12ProcessReadback() throws {
        cases += 1
        var time: UInt64 = 100
        let route = runtimePayload(2).route
        let result = MacSpeechRuntimeReadback.readProcess(pid: 4321, route: route,
                                                          using: m12ProcessReader(), now: { time += 10; return time })
        expect(result.status == "CONFIRMED" && result.processObjectID == 89
            && result.observedPID == 4321 && result.observedPIDAfter == 4321, "only the verified target PID is read")
        expect(result.input?.scope == kAudioObjectPropertyScopeInput && result.input?.deviceIDs == [1]
            && result.output?.scope == kAudioObjectPropertyScopeOutput && result.output?.deviceIDs == [2],
            "process device lists use separate input/output scopes")
        expect(result.input?.bindingStatus == "PROCESS_DEVICE_METADATA_MATCHES_DEFAULT"
            && result.output?.bindingStatus == "PROCESS_DEVICE_METADATA_MATCHES_DEFAULT", "direction metadata matches")
        expect(result.readStartedAtNs == 110 && result.readFinishedAtNs == 120
            && result.queries.count == 7 && result.queries.allSatisfy { $0.osStatus == 0 },
            "query status and duration survive")
        var snapshots: [MacSpeechRuntimeReadback.Snapshot] = []
        let identity = MacSpeechRuntimeReadback.Identity(runID: UUID(), generation: 1, configurationID: 2)
        var reads = 0
        let phases: [MacSpeechRuntimeReadback.Phase] = [
            .engineStarted, .engineStarted, .residentPlaybackStarted, .residentPlaybackStarted
        ]
        for phase in phases {
            _ = MacSpeechRuntimeReadback.record(phase, identity: identity, active: true, snapshots: &snapshots) {
                reads += 1
                var payload = runtimePayload(reads)
                payload.processBinding = result
                return payload
            }
        }
        expect(reads == 2 && snapshots.count == 2, "PID diagnostics share the existing two-point read budget")
        var timing = MacSpeechTimingSnapshot(runID: identity.runID, captureGeneration: 1)
        timing.runtimeReadbacks = snapshots
        let data = try JSONEncoder().encode(timing)
        expect(String(data: data, encoding: .utf8)?.contains("PROCESS_DEVICE_METADATA_MATCHES_DEFAULT") == true,
               "the existing timing JSON exports process evidence")
        testM12ProcessFailures(route)
        testM12ProcessAggregates(route)
    }

    static func testM12ProcessFailures(_ route: MacSpeechRuntimeReadback.Route?) {
        cases += 1
        let modes = ["halFailure", "missingProcess", "wrongPID", "changedPID", "listFailure", "empty",
                     "duplicate", "oversized", "invalidStream"]
        for mode in modes {
            let result = MacSpeechRuntimeReadback.readProcess(pid: 4321, route: route, using: m12ProcessReader(mode))
            expect(
                result.status == "UNKNOWN",
                "PID, HAL, empty, oversized, duplicate or direction failure stays UNKNOWN"
            )
            expect(result.input?.bindingStatus != "PROCESS_DEVICE_METADATA_MATCHES_DEFAULT"
                && result.output?.bindingStatus != "PROCESS_DEVICE_METADATA_MATCHES_DEFAULT", "no default substitution")
            expect(result.queries.contains { $0.status == "UNKNOWN" }, "failed query/validation remains observable")
            if mode == "wrongPID" || mode == "missingProcess" {
                expect(result.input == nil && result.output == nil, "unverified process cannot query devices")
            }
            if mode == "halFailure" {
                expect(result.queries.first?.osStatus == -50, "the original OSStatus is retained")
            }
            if mode == "changedPID" {
                expect(result.observedPIDAfter == 4322, "PID race is recorded")
            }
        }
        let partial = MacSpeechRuntimeReadback.readProcess(pid: 4321, route: route,
                                                           using: m12ProcessReader("wrongDirection"))
        expect(partial.status == "UNKNOWN" && partial.input?.status == "UNKNOWN"
            && partial.input?.deviceIDs == [1] && partial.input?.devices.isEmpty == true,
            "failed input metadata cannot be replaced by default devices")
        expect(partial.output?.status == "CONFIRMED" && partial.output?.deviceIDs == [2],
               "independently successful output query is retained without claiming the input is valid")
        print("m12_partial_direction=input_UNKNOWN_output_CONFIRMED")
    }

    static func testM12ProcessAggregates(_ route: MacSpeechRuntimeReadback.Route?) {
        cases += 1
        for mode in ["aggregate", "aggregateUnknown", "multiple"] {
            let result = MacSpeechRuntimeReadback.readProcess(pid: 4321, route: route, using: m12ProcessReader(mode))
            expect(
                result.status == "CONFIRMED",
                "successfully read process lists remain separate from binding inference"
            )
            expect(
                result.input?
                    .bindingStatus == (mode == "aggregate" ? "PROCESS_AGGREGATE_DIRECTION_QUALIFIED" : "UNKNOWN"),
                "only the existing strict aggregate contract qualifies; ambiguous binding stays UNKNOWN"
            )
        }
        let noRoute = MacSpeechRuntimeReadback.readProcess(pid: 4321, route: nil, using: m12ProcessReader())
        expect(noRoute.status == "CONFIRMED" && noRoute.input?.bindingStatus == "UNKNOWN", "no cached default route")
    }

    static func m12SharedIOFixture(
        _ mode: String = "valid", inputIDs: [UInt32] = [1, 2], outputIDs: [UInt32] = [2]
    ) -> (MacSpeechRuntimeReadback.Route, MacSpeechRuntimeReadback.ProcessReader) {
        func device(_ id: UInt32, input: UInt32, output: UInt32, transport: UInt32) -> MacSpeechRuntimeReadback.Device {
            let value = runtimeDevice(id, input: input, output: output)
            return .init(id: id, transport: transport, aggregate: false, alive: true,
                         inputChannels: input, outputChannels: output,
                         inputStreams: value.inputStreams, outputStreams: value.outputStreams)
        }
        let microphone = device(1, input: 1, output: 0,
                                transport: mode == "inputTransport" ? kAudioDeviceTransportTypeBluetooth
                                    : kAudioDeviceTransportTypeUSB)
        let speaker = device(2, input: 2, output: 2,
                             transport: mode == "outputTransport" ? kAudioDeviceTransportTypeUSB
                                 : kAudioDeviceTransportTypeBuiltIn)
        let route = MacSpeechRuntimeReadback.Route(defaultInput: microphone, defaultOutput: speaker,
                                                   actualInput: mode == "notShared" ? microphone : speaker,
                                                   actualOutput: speaker, aggregates: [])
        var pidReads = 0
        let reader = MacSpeechRuntimeReadback.ProcessReader(translate: { _ in 89 }, pid: { _ in
            pidReads += 1
            return mode == "wrongPID" || (mode == "changedPID" && pidReads == 2) ? 4322 : 4321
        }, devices: { _, scope in
            if mode == "hal" {
                throw NSError(domain: "SyntheticHAL", code: -50)
            }
            return scope == kAudioObjectPropertyScopeInput ? inputIDs : outputIDs
        }, device: { id in
            if id == 1 {
                return microphone
            }
            if id != 2 {
                return runtimeDevice(id, input: 1, output: 1)
            }
            if mode == "metadata" {
                return device(2, input: 3, output: 2, transport: speaker.transport)
            }
            if mode == "transport" {
                return device(2, input: 2, output: 2, transport: kAudioDeviceTransportTypeUSB)
            }
            if mode == "dead" {
                return .init(id: 2, transport: speaker.transport, aggregate: false, alive: false,
                             inputChannels: 2, outputChannels: 2,
                             inputStreams: speaker.inputStreams, outputStreams: speaker.outputStreams)
            }
            if mode == "stream" {
                return .init(id: 2, transport: speaker.transport, aggregate: false, alive: true,
                             inputChannels: 2, outputChannels: 2,
                             inputStreams: [], outputStreams: speaker.outputStreams)
            }
            return speaker
        }, aggregate: { _ in throw NSError(domain: "UnexpectedSyntheticAggregate", code: -1) })
        return (route, reader)
    }

    static func testM12SharedIOReadback() {
        cases += 1
        let (route, reader) = m12SharedIOFixture()
        let process = MacSpeechRuntimeReadback.readProcess(pid: 4321, route: route, using: reader)
        expect(process.status == "CONFIRMED"
            && process.input?.bindingStatus == "PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED",
            "the exact observed shared-IO input device set must qualify by metadata, not list cardinality")
        expect(process.input?.deviceIDs == [1, 2] && process.output?.deviceIDs == [2]
            && process.queries.count == 7 && process.queries.allSatisfy { $0.osStatus == 0 },
            "raw lists and the existing seven-query budget are preserved")
        expect(route.binding == "UNKNOWN_UNVERIFIED_BINDING",
               "process metadata qualification does not promote AU IDs to physical-source proof")
    }

    static func testM12SharedIOFailures() {
        cases += 1
        func reject(_ mode: String = "valid", input: [UInt32] = [1, 2], output: [UInt32] = [2]) {
            let (route, reader) = m12SharedIOFixture(mode, inputIDs: input, outputIDs: output)
            let process = MacSpeechRuntimeReadback.readProcess(pid: 4321, route: route, using: reader)
            expect(process.input?.bindingStatus != "PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED",
                   "unknown members, metadata, streams, scope, PID and HAL failures cannot qualify a device set")
        }
        for input in [[UInt32(1), 3], [1, 2, 3], [2], [1, 1]] {
            reject(input: input)
        }
        reject(output: [2, 3])
        let shapeModes = ["notShared", "metadata", "transport", "stream", "dead"]
        let otherModes = ["wrongPID", "changedPID", "hal", "inputTransport", "outputTransport"]
        for mode in shapeModes + otherModes {
            reject(mode)
        }
    }

    static func testM12SharedIOSafety() {
        cases += 1
        let run = UUID()
        let identity = MacSpeechRuntimeReadback.Identity(runID: run, generation: 1, configurationID: 1)
        var timing = m12SafetyTiming(run, residentStarted: true)
        for index in timing.runtimeReadbacks.indices {
            let (route, reader) = m12SharedIOFixture(inputIDs: index == 0 ? [1, 2] : [2, 1])
            var payload = timing.runtimeReadbacks[index].payload
            payload.route = route
            var process = MacSpeechRuntimeReadback.readProcess(pid: 4321, route: route, using: reader)
            process.requestedPID = getpid()
            process.observedPID = getpid()
            process.observedPIDAfter = getpid()
            payload.processBinding = process
            timing.runtimeReadbacks[index] = .init(
                phase: index == 0 ? .engineStarted : .residentPlaybackStarted,
                runID: run, captureGeneration: 1, configurationID: 1, payload: payload
            )
        }
        func result(_ value: MacSpeechTimingSnapshot) -> AppleVPRuntimeSafetyError? {
            do {
                try AppleVPRuntimeSafetyError.validate(value, identity: identity, pid: getpid(),
                                                       agcEnabled: true, residentStarted: true)
                return nil
            } catch { return error as? AppleVPRuntimeSafetyError }
        }
        expect(result(timing) == nil, "stable device membership may arrive in a different HAL array order")
        testM12SharedIOSetChanges(timing, result: result)
    }

    static func testM12SharedIOSetChanges(
        _ timing: MacSpeechTimingSnapshot, result: (MacSpeechTimingSnapshot) -> AppleVPRuntimeSafetyError?
    ) {
        let run = timing.runID
        for ids in [[UInt32(1), 1], [1, 3]] {
            var invalid = timing
            var payload = invalid.runtimeReadbacks[1].payload
            payload.processBinding.input?.deviceIDs = ids
            invalid.runtimeReadbacks[1] = .init(phase: .residentPlaybackStarted, runID: run,
                                                captureGeneration: 1, configurationID: 1, payload: payload)
            expect(result(invalid) == .bindingUnverified, "a shared-input label cannot authorize invalid membership")
        }
        var invalidOutput = timing
        var payload = invalidOutput.runtimeReadbacks[1].payload
        payload.processBinding.output?.bindingStatus = MacSpeechRuntimeReadback.sharedIODeviceSetBinding
        invalidOutput.runtimeReadbacks[1] = .init(phase: .residentPlaybackStarted, runID: run,
                                                  captureGeneration: 1, configurationID: 1, payload: payload)
        expect(result(invalidOutput) == .bindingUnverified, "shared-input qualification never grants output permission")
        let third = runtimeDevice(3, input: 1, output: 0)
        let replacement = MacSpeechRuntimeReadback.Device(
            id: 3, transport: kAudioDeviceTransportTypeUSB, aggregate: false, alive: true,
            inputChannels: 1, outputChannels: 0, inputStreams: third.inputStreams, outputStreams: []
        )
        var changed = timing
        payload = changed.runtimeReadbacks[1].payload
        let speaker = m12SharedIOFixture().0.defaultOutput
        payload.route = .init(defaultInput: replacement, defaultOutput: speaker,
                              actualInput: speaker, actualOutput: speaker, aggregates: [])
        payload.processBinding.input?.deviceIDs = [3, 2]
        payload.processBinding.input?.devices = [replacement, speaker]
        changed.runtimeReadbacks[1] = .init(phase: .residentPlaybackStarted, runID: run,
                                            captureGeneration: 1, configurationID: 1, payload: payload)
        expect(result(changed) == .identityMismatch, "a different valid device set still stops the active run")
    }

    static func testM12ConfigurationNotifications() {
        cases += 1
        let center = NotificationCenter()
        let object = NSObject()
        let timing = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 1)
        timing.bind(configurationID: 2)
        expect(timing.observeEngineConfiguration(object, configurationID: 2, center: center), "register exact object")
        expect(!timing.observeEngineConfiguration(object, configurationID: 2, center: center), "no duplicate observer")
        timing.event(.engineStartBefore)
        center.post(name: .AVAudioEngineConfigurationChange, object: NSObject())
        expect(timing.snapshot()?.engineConfigurationEvents.count == 0, "other Engine objects are excluded")
        center.post(name: .AVAudioEngineConfigurationChange, object: object)
        timing.event(.playerPlayReturned)
        center.post(name: .AVAudioEngineConfigurationChange, object: object)
        let events = timing.snapshot()?.engineConfigurationEvents
        expect(events?.count == 2 && events?.first?.runID == timing.runID && events?.first?.generation == 1
            && events?.first?.configurationID == 2 && (events?.first?.atNs ?? 0) > 0,
            "first witness is same-run metadata")
        expect(events?.first?.lifecyclePhase == "engineStarting", "first lifecycle phase is immutable")
        timing.recordEngineConfiguration(configurationID: 3)
        expect(timing.snapshot()?.engineConfigurationEvents.count == 2, "stale configuration cannot enter evidence")
        timing.stopObservingEngineConfiguration()
        center.post(name: .AVAudioEngineConfigurationChange, object: object)
        expect(timing.snapshot()?.engineConfigurationEvents.count == 2
            && timing.snapshot()?.engineConfigurationEvents.observationClosed == true,
            "seal removes and closes observation")
        expect(
            !timing.observeEngineConfiguration(object, configurationID: 2, center: center),
            "sealed run cannot rearm"
        )
        testM12NotificationLifetime(object, center: center)
    }

    static func testM12NotificationLifetime(_ object: NSObject, center: NotificationCenter) {
        cases += 1
        weak var released: MacSpeechNativeVoiceTiming?
        do {
            let old = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 1)
            released = old
            old.bind(configurationID: 2)
            expect(
                old.observeEngineConfiguration(object, configurationID: 2, center: center),
                "temporary listener registered"
            )
        }
        expect(released == nil, "notification registration does not retain timing or Engine")
        let current = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 2)
        current.bind(configurationID: 3)
        expect(
            current.observeEngineConfiguration(object, configurationID: 3, center: center),
            "new generation isolated"
        )
        center.post(name: .AVAudioEngineConfigurationChange, object: object)
        expect(current.snapshot()?.engineConfigurationEvents.count == 1
            && current.snapshot()?.engineConfigurationEvents.first?.generation == 2,
            "old generation cannot pollute new evidence")
        current.bind(configurationID: 4)
        center.post(name: .AVAudioEngineConfigurationChange, object: object)
        expect(
            current.snapshot()?.engineConfigurationEvents.count == 1,
            "invalidated generation rejects queued notification"
        )
        current.stopObservingEngineConfiguration()
    }

    static func testM12NotificationConcurrency() {
        cases += 1
        let timing = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 1)
        timing.bind(configurationID: 2)
        expect(timing.observeEngineConfiguration(NSObject(), configurationID: 2, center: NotificationCenter()),
               "concurrency fixture registers without creating an Engine")
        DispatchQueue.concurrentPerform(iterations: 128) { _ in timing.recordEngineConfiguration(configurationID: 2) }
        guard let events = timing.snapshot()?.engineConfigurationEvents
        else { fatalError("missing concurrent snapshot") }
        expect(events.count + events.skippedNotifications == 128, "contention is counted rather than hidden")
        expect(
            events.status == (events.skippedNotifications > 0 ? "UNKNOWN" : "CONFIRMED"),
            "loss cannot claim full observation"
        )
        expect(events.first != nil && events.count > 0, "fixed first witness survives concurrent delivery")
        timing.stopObservingEngineConfiguration()
        DispatchQueue.concurrentPerform(iterations: 128) { _ in timing.recordEngineConfiguration(configurationID: 2) }
        expect(timing.snapshot()?.engineConfigurationEvents.count == events.count, "closed evidence cannot change")
    }

    static func testM12SnapshotContention() throws {
        cases += 1
        let timing = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 1)
        timing.bind(configurationID: 1)
        expect(timing.observeEngineConfiguration(NSObject(), configurationID: 1, center: NotificationCenter()),
               "synthetic observer starts without an Engine")
        defer { timing.stopObservingEngineConfiguration() }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            timing.withUpdateForTesting {
                entered.signal()
                _ = release.wait(timeout: .now() + 1)
            }
            finished.signal()
        }
        expect(entered.wait(timeout: .now() + 1) == .success, "deterministic writer owns the real timing flag")
        defer { release.signal() }
        var waits = 0
        let value = timing.snapshot(clock: { 1000 }, wait: {
            waits += 1
            release.signal()
            expect(finished.wait(timeout: .now() + 1) == .success, "writer completes before the read retries")
        })
        expect(value != nil && waits == 1, "temporary snapshot contention must not fabricate unavailable evidence")
        var valid = value!
        valid.runtimeReadbacks = m12SafetyTiming(timing.runID).runtimeReadbacks
        try AppleVPRuntimeSafetyError.validate(
            valid, identity: .init(runID: timing.runID, generation: 1, configurationID: 1),
            pid: getpid(), agcEnabled: true, residentStarted: false
        )
        expect(valid.skippedUpdates == 0, "control waiting neither changes nor loses the writer evidence")
    }

    static func testM12SnapshotTimeouts() {
        cases += 1
        for mode in ["deadline", "attemptCap", "backwards"] {
            let timing = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 1)
            var clock: UInt64 = 1000
            var waits = 0
            timing.withUpdateForTesting {
                let value = timing.snapshot(clock: { clock }, wait: {
                    waits += 1
                    if mode == "deadline" {
                        clock += 1_000_000
                    }
                    if mode == "backwards" {
                        clock = 0
                    }
                })
                expect(value == nil, "a stalled or invalid snapshot never becomes qualified evidence")
                expect(waits == (mode == "attemptCap" ? 19 : mode == "deadline" ? 5 : 1),
                       "snapshot waiting has both a clock budget and an attempt cap")
                do {
                    try AppleVPRuntimeSafetyError.validate(
                        value, identity: .init(runID: timing.runID, generation: 1, configurationID: 1),
                        pid: getpid(), agcEnabled: true, residentStarted: false
                    )
                    fatalError("missing evidence must still stop")
                } catch {
                    expect(error as? AppleVPRuntimeSafetyError == .evidenceUnavailable,
                           "exhausted snapshot acquisition preserves fail-closed")
                }
                timing.event(.engineStartBefore)
            }
            expect(timing.snapshot()?.skippedUpdates == 1, "callback-side updates keep their one-attempt behavior")
        }
    }

    static func testM12SnapshotInvalidation() throws {
        cases += 1
        let timing = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 1)
        timing.bind(configurationID: 1)
        expect(timing.observeEngineConfiguration(NSObject(), configurationID: 1, center: NotificationCenter()),
               "invalidation fixture starts without device access")
        timing.recordEngineConfiguration(configurationID: 1)
        var value = timing.snapshot()!
        value.runtimeReadbacks = m12SafetyTiming(timing.runID).runtimeReadbacks
        do {
            try AppleVPRuntimeSafetyError.validate(
                value, identity: .init(runID: timing.runID, generation: 1, configurationID: 1),
                pid: getpid(), agcEnabled: true, residentStarted: false
            )
            fatalError("configuration changes must still stop")
        } catch {
            expect(error as? AppleVPRuntimeSafetyError == .configurationChanged,
                   "fresh snapshots retain real configuration changes")
        }
        timing.stopObservingEngineConfiguration()
        expect(timing.snapshot()?.engineConfigurationEvents.observationClosed == true,
               "control waiting never reopens a closed observer")
    }

    static func testM12PCMInvariance() throws {
        cases += 1
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960),
              let samples = buffer.floatChannelData?[0] else { fatalError("synthetic converter fixture") }
        buffer.frameLength = 960
        for frame in 0 ..< 960 {
            samples[frame] = Float(sin(Double(frame) * 0.1) * 0.2)
        }
        for jump in [false, true] {
            var outputs: [[MacSpeechPCM16Packet]] = []
            var rejected: [Int] = []
            for enabled in [false, true] {
                let result = try m12ConvertedPackets(buffer, enabled: enabled, jump: jump)
                outputs.append(result.packets)
                rejected.append(result.empty)
            }
            expect(
                !outputs[0].isEmpty && outputs[0] == outputs[1],
                "diagnostics preserve PCM values, order and content time"
            )
            expect(rejected[0] == rejected[1], "diagnostics preserve existing clock rejection")
            if jump {
                expect(rejected[0] >= 6, "real content-time failure remains fail-closed")
            }
        }
    }

    static func m12ConvertedPackets(
        _ buffer: AVAudioPCMBuffer, enabled: Bool, jump: Bool
    ) throws -> (packets: [MacSpeechPCM16Packet], empty: Int) {
        let converter = try MacSpeechAudioConverter(inputFormat: buffer.format)
        let timing = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 1)
        let object = NSObject()
        timing.bind(configurationID: 2)
        if enabled {
            expect(timing.observeEngineConfiguration(object, configurationID: 2, center: NotificationCenter()),
                   "synthetic enabled observer")
        }
        defer { timing.stopObservingEngineConfiguration() }
        var packets: [MacSpeechPCM16Packet] = []
        var empty = 0
        for frame in 0 ..< 10 {
            if enabled {
                timing.recordEngineConfiguration(configurationID: 2)
            }
            let time = UInt64(1_000_000_000 + frame * 20_000_000 + (jump && frame == 4 ? 3_000_000 : 0))
            let result = try converter.convert(buffer, contentTimestampNanoseconds: time, requireContentTime: true)
            packets.append(contentsOf: result)
            if result.isEmpty {
                empty += 1
            }
        }
        return (packets, empty)
    }

    static func testM03Batch() async throws {
        try testM12SnapshotContention()
        testM12SnapshotTimeouts()
        try testM12SnapshotInvalidation()
        testM12SharedIOReadback()
        testM12SharedIOFailures()
        testM12SharedIOSafety()
        let safetyCases = cases
        let safetyChecks = checks
        testM12RuntimeSafetyEvidence()
        try await testM12RuntimeSafetyStop()
        try await testM12RuntimeSafetyStop(afterPlayback: true)
        try await testM12RuntimeSafetySuccess()
        print("m12_runtime_gate_cases=\(cases - safetyCases)")
        print("m12_runtime_gate_checks=\(checks - safetyChecks)")
        let beforeCases = cases
        let beforeChecks = checks
        try testM12EvidenceSchema()
        try testM12ProcessReadback()
        testM12ConfigurationNotifications()
        testM12NotificationConcurrency()
        try testM12PCMInvariance()
        print("m12_device_and_hal_access=ZERO")
        print("m12_cases=\(cases - beforeCases)")
        print("m12_checks=\(checks - beforeChecks)")
        testM04RouteBinding()
        try testM04BoundedReadbacks()
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        for scenario in AppleVPAcousticTestScenario.allCases {
            try await testM03Group(scenario, source: source)
        }
        cases += 1
        let missingPipe = D1ControllerStack(batchScenario: .humanOnly)
        expect(missingPipe.controller.prepareAppleVPAcousticTest(
            .humanOnly, comprehensiveC: true, warmupProfile: .four, btAcousticBatch: true
        ), "preparation alone cannot start devices")
        startD1(missingPipe.controller)
        expect(missingPipe.capture.startCount == 0
            && missingPipe.controller.appleVPAcousticTestState.errorCode == "external_playback_control_unavailable",
            "missing external control fails before capture")
        try await testScoreControlCancellation()
        try testScoreControlBlockedReader()
        try testWarmupPacketBoundary()
        print("m03_fake_cases=\(cases)")
        print("m03_fake_checks=\(checks)")
        print("m03_fake_device_access=ZERO")
    }

    static func m12SafetyTiming(
        _ run: UUID, residentStarted: Bool = false, agcEnabled: Bool = true, aggregate: Bool = false
    ) -> MacSpeechTimingSnapshot {
        let base = runtimePayload(2)
        var payload = MacSpeechRuntimeReadback.Payload(
            readStartedAtNs: base.readStartedAtNs, readFinishedAtNs: base.readFinishedAtNs,
            voiceProcessing: ["engineRunning": true, "inputEnabled": true, "outputEnabled": true,
                              "agcEnabled": agcEnabled, "bypass": false, "inputMuted": false],
            formats: base.formats, playerMixerBus: base.playerMixerBus,
            mixerOutputConnected: base.mixerOutputConnected, route: base.route, issues: []
        )
        var process = MacSpeechRuntimeReadback.readProcess(
            pid: 4321, route: payload.route, using: m12ProcessReader(aggregate ? "aggregate" : "direct")
        )
        process.requestedPID = getpid()
        process.observedPID = getpid()
        process.observedPIDAfter = getpid()
        payload.processBinding = process
        var timing = MacSpeechTimingSnapshot(runID: run, captureGeneration: 1)
        timing.configurationID = 1
        timing.engineConfigurationEvents.status = "CONFIRMED"
        timing.runtimeReadbacks = [.init(phase: .engineStarted, runID: run,
                                         captureGeneration: 1, configurationID: 1, payload: payload)]
        if residentStarted {
            timing.runtimeReadbacks.append(.init(phase: .residentPlaybackStarted, runID: run,
                                                 captureGeneration: 1, configurationID: 1, payload: payload))
        }
        return timing
    }

    static func testM12RuntimeSafetyEvidence() {
        cases += 1
        let run = UUID()
        let identity = MacSpeechRuntimeReadback.Identity(runID: run, generation: 1, configurationID: 1)
        let valid = m12SafetyTiming(run)
        func result(
            _ timing: MacSpeechTimingSnapshot?, resident: Bool = false, agc: Bool = true
        ) -> AppleVPRuntimeSafetyError? {
            do {
                try AppleVPRuntimeSafetyError.validate(timing, identity: identity, pid: getpid(),
                                                       agcEnabled: agc, residentStarted: resident)
                return nil
            } catch { return error as? AppleVPRuntimeSafetyError }
        }
        expect(result(valid) == nil && result(m12SafetyTiming(run, residentStarted: true), resident: true) == nil,
               "the original two readback points admit confirmed direction metadata")
        expect(result(nil) == .evidenceUnavailable && result(valid, resident: true) == .evidenceUnavailable,
               "missing timing or missing post-play readback fails closed")
        expect(result(m12SafetyTiming(run, agcEnabled: false), agc: false) == nil
            && result(m12SafetyTiming(run, agcEnabled: false)) == .processingUnverified,
            "runtime AGC must match the prepared profile without changing either profile")
        for field in ["run", "generation", "configuration", "closed", "skipped", "observer"] {
            var timing = valid
            switch field {
            case "run": timing = m12SafetyTiming(UUID())
            case "generation": timing = .init(runID: run, captureGeneration: 2)
            case "configuration": timing.configurationID = 2
            case "closed": timing.callbacksClosed = true
            case "skipped": timing.engineConfigurationEvents.skippedNotifications = 1
            default: timing.engineConfigurationEvents.observationClosed = true
            }
            let expected: AppleVPRuntimeSafetyError = ["skipped", "observer"].contains(field)
                ? .evidenceUnavailable : .identityMismatch
            expect(result(timing) == expected, "stale identity and unavailable observation cannot authorize a run")
        }
        testM12RuntimeProcessSafety(valid) { result($0) }
        var stale = valid
        stale.runtimeReadbacks[0] = .init(phase: .engineStarted, runID: UUID(), captureGeneration: 1,
                                          configurationID: 1, payload: valid.runtimeReadbacks[0].payload)
        expect(result(stale) == .identityMismatch, "foreign snapshot cannot enter the current run")
        var postPlay = m12SafetyTiming(run, residentStarted: true)
        postPlay.runtimeReadbacks[1] = stale.runtimeReadbacks[0]
        expect(result(postPlay, resident: true) == .identityMismatch, "the second readback is checked independently")
        var changed = valid
        changed.runtimeReadbacks.append(
            m12SafetyTiming(run, residentStarted: true, aggregate: true).runtimeReadbacks[1]
        )
        expect(result(changed, resident: true) == .identityMismatch, "direction device changes between readbacks stop")
        expect(result(m12SafetyTiming(run, residentStarted: true, aggregate: true), resident: true) == nil,
               "a stable qualified Aggregate is admitted at both observation points")
    }

    static func testM12RuntimeProcessSafety(
        _ valid: MacSpeechTimingSnapshot, result: (MacSpeechTimingSnapshot?) -> AppleVPRuntimeSafetyError?
    ) {
        for mode in ["aggregate", "aggregateUnknown", "wrongPID", "changedPID", "halFailure", "empty", "listFailure"] {
            var timing = valid
            var payload = valid.runtimeReadbacks[0].payload
            var process = MacSpeechRuntimeReadback.readProcess(
                pid: 4321, route: payload.route, using: m12ProcessReader(mode)
            )
            process.requestedPID = getpid()
            process.observedPID = mode == "wrongPID" ? getpid() + 1 : getpid()
            process.observedPIDAfter = mode == "changedPID" ? getpid() + 1 : getpid()
            payload.processBinding = process
            timing.runtimeReadbacks[0] = .init(phase: .engineStarted, runID: valid.runID,
                                               captureGeneration: 1, configurationID: 1, payload: payload)
            let expected: AppleVPRuntimeSafetyError? = mode == "aggregate" ? nil
                : mode == "aggregateUnknown" ? .bindingUnverified
                : ["wrongPID", "changedPID"].contains(mode) ? .identityMismatch : .evidenceUnavailable
            expect(result(timing) == expected, "valid Aggregate, UNKNOWN and actual PID mismatch remain distinct")
            var second = valid
            second.runtimeReadbacks.append(.init(phase: .residentPlaybackStarted, runID: valid.runID,
                                                 captureGeneration: 1, configurationID: 1, payload: payload))
            expect(result(second) == (mode == "aggregate" ? .identityMismatch : expected),
                   "an unavailable second query is never mislabeled as a confirmed device change")
        }
    }

    static func testM12RuntimeSafetyStop(afterPlayback: Bool = false) async throws {
        cases += 1
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let clock = ComprehensiveCClock()
        var changed = false
        var residentStarted = { false }
        let stack = D1ControllerStack(
            clock: { clock.now }, scoreControlDescriptor: pipe.fileHandleForWriting.fileDescriptor,
            batchScenario: .residentOnly, runtimeTiming: { run in
                var timing = m12SafetyTiming(run, residentStarted: residentStarted())
                if changed {
                    timing.engineConfigurationEvents.count = 1
                    timing.engineConfigurationEvents.first = .init(
                        atNs: clock.now, runID: run, generation: 1, configurationID: 1, lifecyclePhase: "capture"
                    )
                }
                return timing
            }
        )
        residentStarted = { stack.player.startCount > 0 }
        expect(stack.controller.prepareAppleVPAcousticTest(
            .residentOnly, comprehensiveC: true, warmupProfile: .four, btAcousticBatch: true
        ), "M12 gate uses the existing bounded A preparation")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "M12 uses synthetic resident only")
        startD1(stack.controller)
        await waitUntil("M12 safe capture started") { stack.controller.appleVPAcousticTestState.phase == .running }
        if afterPlayback {
            clock.elapsed = 7_000_000_000
            await waitUntil("M12 fake resident started") {
                stack.player.completeScheduledChunk()
                return stack.player.startCount == 1
            }
        }
        changed = true
        await waitUntil("M12 event stopped capture") {
            stack.controller.appleVPAcousticTestState.phase == .sealed
        }
        let state = stack.controller.appleVPAcousticTestState
        expect(state.phase == .sealed && state.errorCode == "engine_configuration_changed",
               "M12 configuration evidence must stop and seal through the existing control path")
        expect(stack.capture.stopCount == 1 && stack.player.startCount == (afterPlayback ? 1 : 0),
               "configuration events stop the existing capture and resident lifecycle")
        expectD1Cleanup(stack)
        let events = try scoreControlEvents(pipe)
        expect(events.map { $0["event"] as? String } == ["schedule", "stop"],
               "M12 failure emits exactly one terminal STOP")
    }

    static func testM12RuntimeSafetySuccess() async throws {
        cases += 1
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let clock = ComprehensiveCClock()
        var residentStarted = { false }
        let stack = D1ControllerStack(
            clock: { clock.now }, scoreControlDescriptor: pipe.fileHandleForWriting.fileDescriptor,
            batchScenario: .residentOnly,
            runtimeTiming: { run in m12SafetyTiming(run, residentStarted: residentStarted()) }
        )
        residentStarted = { stack.player.startCount > 0 }
        stack.capture.contentStartOverride = clock.start
        expect(stack.controller.prepareAppleVPAcousticTest(
            .residentOnly, comprehensiveC: true, warmupProfile: .four, btAcousticBatch: true
        ), "M12 success uses the unchanged bounded scoring preparation")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "M12 success selects the synthetic fixture")
        startD1(stack.controller)
        await driveWarmupC(stack, clock: clock, profile: .four)
        let state = stack.controller.appleVPAcousticTestState
        expect(state.errorCode == nil && state.packetCount == 750 && state.retainedPCMByteCount == 720_000,
               "the safety consumer preserves 19-second processing and the 15-second recording cap")
        expectD1Cleanup(stack)
        let events = try scoreControlEvents(pipe)
        expect(events.map { $0["event"] as? String } == ["schedule", "stop"], "normal STOP remains single")
    }

    static func testM07Batch() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        for scenario in AppleVPAcousticTestScenario.allCases {
            try await testM03Group(scenario, source: source, humanBatch: true)
        }
        cases += 1
        let missingPipe = D1ControllerStack(humanBatchScenario: .humanOnly)
        expect(missingPipe.controller.prepareAppleVPAcousticTest(
            .humanOnly, comprehensiveC: true, warmupProfile: .four, humanAcousticBatch: true
        ), "HUMAN preparation does not start devices")
        startD1(missingPipe.controller)
        expect(missingPipe.capture.startCount == 0
            && missingPipe.controller.appleVPAcousticTestState.errorCode == "external_playback_control_unavailable",
            "HUMAN requires its explicit score-control pipe before capture")
        let mixed = D1ControllerStack(batchScenario: .humanOnly, humanBatchScenario: .humanOnly)
        for human in [false, true] {
            expect(!mixed.controller.prepareAppleVPAcousticTest(
                .humanOnly, comprehensiveC: true, warmupProfile: .four,
                btAcousticBatch: !human, humanAcousticBatch: human
            ), "HUMAN and BT launch identities cannot be mixed")
        }
        print("m07_fake_cases=\(cases)")
        print("m07_fake_checks=\(checks)")
        print("m07_fake_device_access=ZERO")
    }

    static func testM03Group(
        _ scenario: AppleVPAcousticTestScenario, source: URL, humanBatch: Bool = false,
        onsetProfile: AppleVPHumanOnsetProfile? = nil
    ) async throws {
        cases += 1
        let channel = Pipe()
        defer { try? channel.fileHandleForReading.close(); try? channel.fileHandleForWriting.close() }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(
            clock: { clock.now }, scoreControlDescriptor: channel.fileHandleForWriting.fileDescriptor,
            batchScenario: humanBatch ? nil : scenario,
            humanBatchScenario: humanBatch && onsetProfile == nil ? scenario : nil,
            humanOnsetProfile: onsetProfile
        )
        stack.capture.contentStartOverride = clock.start
        expect(!stack.controller.prepareAppleVPAcousticTest(
            scenario, comprehensiveC: true, processingProfile: .agcOff,
            warmupProfile: .four, btAcousticBatch: !humanBatch, humanAcousticBatch: humanBatch,
            humanOnsetProfile: onsetProfile
        ), "the acoustic batch cannot switch off AGC")
        expect(!stack.controller.prepareAppleVPAcousticTest(
            scenario, comprehensiveC: true, warmupProfile: .zero,
            btAcousticBatch: !humanBatch, humanAcousticBatch: humanBatch, humanOnsetProfile: onsetProfile
        ), "the acoustic batch requires four seconds of continuous warm-up")
        expect(!stack.controller.prepareAppleVPAcousticTest(.doubleTalk, comprehensiveC: true),
               "the acoustic batch cannot accidentally start a legacy scenario")
        if humanBatch {
            expect(!stack.controller.prepareAppleVPAcousticTest(
                scenario, comprehensiveC: true, dataMode: .statsOnly,
                warmupProfile: .four, humanAcousticBatch: true, humanOnsetProfile: onsetProfile
            ), "HUMAN cannot change its frozen recording mode")
        }
        expect(stack.controller.prepareAppleVPAcousticTest(
            scenario, comprehensiveC: true, warmupProfile: .four,
            btAcousticBatch: !humanBatch, humanAcousticBatch: humanBatch, humanOnsetProfile: onsetProfile
        ), "the explicit acoustic source combination prepares")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "same synthetic fixture selected")
        if humanBatch {
            for (microphone, local) in [(false, true), (true, false)] {
                stack.controller.startAppleVPAcousticTest(
                    microphoneConsent: microphone, speakerConsent: true, localCaptureConsent: local
                )
                expect(stack.capture.startCount == 0 && stack.player.prepareCount == 0,
                       "HUMAN preserves microphone and local-recording consent before device preparation")
            }
        }
        startD1(stack.controller)
        await driveWarmupC(stack, clock: clock, profile: .four, residentEnabled: scenario != .humanOnly)
        let state = stack.controller.appleVPAcousticTestState
        expect(state.errorCode == nil && state.packetCount == 750 && state.retainedPCMByteCount == 720_000,
               "each source combination completes the same bounded scoring window")
        expect(stack.player.startCount == (scenario == .humanOnly ? 0 : 1), "resident starts only in A and C")
        let events = try scoreControlEvents(channel)
        expect(events.count == 2 && events.map { $0["event"] as? String } == ["schedule", "stop"],
               "one schedule and one stop are emitted")
        let identityMatches = events.allSatisfy {
            $0["batch"] as? String == (onsetProfile != nil ? "R5_M07_F1" : humanBatch ? "R5_M07" : "R5_M03")
                && $0["scenario"] as? String == scenario.rawValue
                && $0["run_id"] as? String == state.runID?.uuidString
        }
        expect(identityMatches, "both events bind the source combination")
        expect(events[0]["score_start_ns"] as? UInt64 == clock.start + 4_000_000_000,
               "all groups share the four-second score origin")
        if humanBatch {
            expect(events.allSatisfy {
                $0["source"] as? String == "human" && $0["proxy_requested"] as? Bool == false
                    && $0["proxy_stop_ns"] == nil
            }, "HUMAN score messages never request a proxy")
            expect(events.allSatisfy {
                $0["score_start_ns"] as? UInt64 == clock.start + 4_000_000_000
                    && $0["human_speech_stop_ns"] as? UInt64 == clock.start + 15_000_000_000
            }, "HUMAN speaking ends at score eleven after four seconds of warm-up")
            let manifest = try JSONSerialization.jsonObject(
                with: stack.controller.appleVPAcousticTestManifestData()
            ) as? [String: Any] ?? [:]
            let human = manifest["human_acoustic_batch"] as? [String: Any]
            expect(manifest["bt_acoustic_batch"] == nil
                && human?["batch"] as? String == (onsetProfile == nil ? "R5_M07" : "R5_M07_F1")
                && human?["source"] as? String == "human" && human?["proxy_requested"] as? Bool == false
                && human?["human_requested"] as? Bool == (scenario != .residentOnly),
                "HUMAN metadata preserves the actual requested source and excludes BT metadata")
            if let onsetProfile {
                let cue = clock.start + 4_000_000_000 + onsetProfile.cueDelayNanoseconds
                expect(events.allSatisfy {
                    $0["onset_group"] as? String == onsetProfile.rawValue
                        && $0["human_start_cue_ns"] as? UInt64 == cue
                }, "F1 schedule and terminal bind one frozen onset profile and cue")
                expect(state.humanSpeechCueAtNanoseconds == cue, "F1 control cue follows score content origin")
                let onset = manifest["human_onset_comparison"] as? [String: Any]
                expect(onset?["physical_overlap_seconds"] is NSNull
                    && onset?["physical_human_onset_ns"] is NSNull,
                    "F1 software cue cannot fabricate physical speech or overlap")
                expect(!stack.controller.prepareAppleVPAcousticTest(
                    .doubleTalk, discardPreviousResult: true, comprehensiveC: true, warmupProfile: .four,
                    humanAcousticBatch: true,
                    humanOnsetProfile: onsetProfile == .residentFirst ? .humanFirst : .residentFirst
                ), "the launch profile cannot be swapped after seal")
            }
        }
        try expectWarmupManifest(stack.controller, profile: .four)
        let wav = try stack.controller.appleVPAcousticTestProcessedWAVData()
        expect(wav.dropFirst(44).enumerated().allSatisfy { $0.offset % 2 == 0 ? $0.element == 1 : $0.element == 0 },
               "no warm-up marker is retained in the scoring WAV")
        expectD1Cleanup(stack)
    }

    static func testM07F1() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        for profile in AppleVPHumanOnsetProfile.allCases {
            try await testM03Group(.doubleTalk, source: source, humanBatch: true, onsetProfile: profile)
        }
        cases += 1
        let mixed = D1ControllerStack(humanBatchScenario: .doubleTalk, humanOnsetProfile: .residentFirst)
        let unregistered = D1ControllerStack()
        for stack in [mixed, unregistered] {
            expect(!stack.controller.prepareAppleVPAcousticTest(
                .doubleTalk, comprehensiveC: true, warmupProfile: .four,
                humanAcousticBatch: true, humanOnsetProfile: .residentFirst
            ), "F1 cannot mix with old M07 or enter without its registered launch argument")
            expect(stack.capture.startCount == 0 && stack.player.prepareCount == 0,
                   "invalid F1 identity never prepares hardware")
        }
        let missing = D1ControllerStack(humanOnsetProfile: .residentFirst)
        expect(missing.controller.prepareAppleVPAcousticTest(
            .doubleTalk, comprehensiveC: true, warmupProfile: .four,
            humanAcousticBatch: true, humanOnsetProfile: .residentFirst
        ), "offline F1 Prepare is safe without opening a device")
        startD1(missing.controller)
        expect(missing.capture.startCount == 0
            && missing.controller.appleVPAcousticTestState.errorCode == "external_playback_control_unavailable",
            "F1 must bind the existing score pipe before capture")
        print("m07_f1_fake_cases=\(cases)")
        print("m07_f1_fake_checks=\(checks)")
        print("m07_f1_fake_device_access=ZERO")
    }

    static func testWarmupRepetition() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(clock: { clock.now })
        stack.capture.contentStartOverride = clock.start
        for (index, profile) in [MacSpeechWarmupProfile.zero, .four, .four, .zero, .four, .four, .four].enumerated() {
            cases += 1
            clock.elapsed = 0
            let mode: AppleVPAcousticDataMode = index == 2 || index == 5 ? .statsOnly : .recording
            let processing: MacSpeechAppleVPDebugProfile = index == 4 || index == 5 ? .agcOff : .agcOn
            prepareWarmupC(stack, source: source, profile: profile, mode: mode, discard: index > 0,
                           processingProfile: processing)
            await driveWarmupC(stack, clock: clock, profile: profile)
            let state = stack.controller.appleVPAcousticTestState
            expect(state.errorCode == nil && state.packetCount == 750,
                   "each scoring run retains 750 valid packets")
            expect(!stack.controller.prepareAppleVPAcousticTest(.doubleTalk, warmupProfile: .four),
                   "sealed results cannot be silently replaced")
            try expectWarmupManifest(stack.controller, profile: profile)
            let manifest = try JSONSerialization.jsonObject(
                with: stack.controller.appleVPAcousticTestManifestData()
            ) as? [String: Any] ?? [:]
            expect(state.processingProfile == processing
                && manifest["requested_agc_enabled"] as? Bool == processing.automaticGainControlEnabled,
                "successive ON/OFF runs retain their own requested AGC without inheriting old configuration")
            if mode == .statsOnly {
                try expectStatsOnlyEvidence(stack.controller)
                try testStatsOnlyJSONExport(stack.controller)
            } else {
                let wav = try stack.controller.appleVPAcousticTestProcessedWAVData()
                expect(wav.count == 720_044, "only 15 scoring seconds appear in the WAV")
                let matches = wav.dropFirst(44).enumerated().allSatisfy {
                    $0.offset % 2 == 0 ? $0.element == 1 : $0.element == 0
                }
                expect(matches, "the warm-up marker never leaks into the scoring recording")
            }
            expect(stack.capture.startCount == index + 1 && stack.capture.stopCount == index + 1,
                   "each run starts and stops the original Capture once, not at the boundary")
            expectD1Cleanup(stack)
        }
    }

    static func expectWarmupManifest(_ controller: AppController, profile: MacSpeechWarmupProfile) throws {
        let value = try JSONSerialization.jsonObject(with: controller.appleVPAcousticTestManifestData())
        let manifest = value as? [String: Any] ?? [:]
        let warmup = manifest["warmup"] as? [String: Any] ?? [:]
        let guide = manifest["comprehensive_c"] as? [String: Any] ?? [:]
        let events = guide["events_ns"] as? [String: UInt64] ?? [:]
        let start = warmup["score_start_content_boundary_ns"] as? UInt64 ?? 0
        expect(manifest["warmup_profile"] as? String == profile.rawValue, "the manifest binds the selected profile")
        expect(manifest["total_collection_limit_ns"] as? UInt64 == 15_000_000_000 + profile.nanoseconds,
               "only the DEBUG run has the 19-second total budget")
        expect(manifest["byte_limit"] as? Int == 720_000
            && warmup["warmup_retained_pcm_bytes"] as? Int == 0,
            "warm-up has no second recording or expanded cap")
        expect(warmup["drained_packets"] as? UInt64 == (profile == .four ? 950 : 750), "all packets were drained")
        expect(events["double_talk"] == start + 3_000_000_000 && events["quiet"] == start + 11_000_000_000,
               "playback and guidance keep the original scoring-relative schedule")
        expect(warmup["partial_tail"] as? String == "UNKNOWN", "unknown converter tail is never fabricated")
    }

    static func testWarmupFailures() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let failures = ["stop", "shutdown", "route", "timeout", "clock", "generation",
                        "configuration", "agc", "unsupported", "run", "profile"]
        for (index, kind) in (failures + failures).enumerated() {
            cases += 1
            let clock = ComprehensiveCClock()
            let stack = D1ControllerStack(clock: { clock.now })
            stack.capture.contentStartOverride = clock.start
            stack.capture.supportsWarmupWindows = kind != "unsupported"
            let processing: MacSpeechAppleVPDebugProfile = index < failures.count ? .agcOn : .agcOff
            prepareWarmupC(stack, source: source, profile: .four, processingProfile: processing)
            if kind != "unsupported" {
                await waitUntil("warm-up failure ready") { stack.controller.appleVPAcousticTestState.phase == .running }
                await injectWarmupFailure(kind, stack: stack, clock: clock)
            }
            await waitUntil("warm-up failure sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            expect(stack.controller.appleVPAcousticTestState.errorCode != nil, "injected failures cannot become PASS")
            expect(stack.controller.appleVPAcousticTestState.retainedPCMByteCount == 0,
                   "failure before scoring leaves no warm-up recording")
            expect(stack.player.startCount == 0, "a failed warm-up does not play resident audio")
            expectD1Cleanup(stack)
        }
    }

    static func testWarmupStartReadbackFailures() async throws {
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        for profile in MacSpeechAppleVPDebugProfile.allCases {
            cases += 1
            let clock = ComprehensiveCClock()
            let stack = D1ControllerStack(clock: { clock.now })
            stack.capture.agcReadbackOverride = !profile.automaticGainControlEnabled
            prepareWarmupC(stack, source: source, profile: .four, processingProfile: profile)
            await waitUntil("four-second comparison refuses mismatched start readback") {
                stack.controller.appleVPAcousticTestState.phase == .sealed
            }
            let state = stack.controller.appleVPAcousticTestState
            expect(state.errorCode != nil && state.processingProfile == profile,
                   "mismatched readback fails without fallback or profile substitution")
            expect(state.retainedPCMByteCount == 0 && stack.player.startCount == 0,
                   "failed registration cannot produce scoring audio or resident playback")
            expectD1Cleanup(stack)
        }
    }

    static func injectWarmupFailure(_ kind: String, stack: D1ControllerStack, clock: ComprehensiveCClock) async {
        switch kind {
        case "stop": await stack.controller.stopAppleVPAcousticTest()
        case "shutdown": await stack.controller.shutdownSpeechAudioHost()
        case "route": stack.captureMonitor.changeInput(identifier: "other", name: "Fake changed", available: true)
        case "timeout": clock.elapsed = 20_000_000_000
        case "clock":
            clock.elapsed = 500_000_000
            stack.capture.emitPackets(1)
            await waitUntil("clock advanced once") { stack.controller.appleVPAcousticTestState.drainedPacketCount == 1 }
            clock.elapsed = 0
        case "generation": stack.capture.emitPreviousGenerationPacket()
        case "configuration": stack.capture.invalidateTimeline(configuration: 2)
        default: injectWarmupProfileFailure(kind, stack: stack)
        }
    }

    static func injectWarmupProfileFailure(_ kind: String, stack: D1ControllerStack) {
        switch kind {
        case "agc":
            let previous = stack.capture.voiceProcessingSnapshot()?.automaticGainControlEnabled ?? true
            stack.capture.agcReadbackOverride = !previous
        case "run": stack.capture.replaceNativeContext(runID: UUID())
        case "profile":
            let prepared = stack.controller.appleVPAcousticTestState.processingProfile
            stack.capture.replaceNativeContext(profile: prepared == .agcOn ? .agcOff : .agcOn)
        default: preconditionFailure("unknown warm-up failure control")
        }
    }

    static func testWarmupQueuedTail() async throws {
        cases += 1
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(clock: { clock.now })
        stack.capture.contentStartOverride = clock.start
        prepareWarmupC(stack, source: source, profile: .four)
        await driveWarmupC(stack, clock: clock, profile: .four, queuedTail: 5)
        let value = try JSONSerialization.jsonObject(with: stack.controller.appleVPAcousticTestManifestData())
        let manifest = value as? [String: Any] ?? [:]
        let warmup = manifest["warmup"] as? [String: Any] ?? [:]
        expect(warmup["queued_at_seal"] as? Int == 5, "queued tail remains distinct from drained content")
        expect(warmup["tail_coverage"] as? String == "PARTIAL", "partial tail is not padded into a complete result")
        expect((warmup["quiet_drained_ns"] as? UInt64 ?? 0) >= 1_000_000_000, "quiet coverage uses actual drained time")
        expect(stack.controller.appleVPAcousticTestState.packetCount == 745, "five queued packets are not in the WAV")
        expectD1Cleanup(stack)
    }

    static func testWarmupInvalidPrepare() {
        cases += 1
        let stack = D1ControllerStack()
        expect(!stack.controller.prepareAppleVPAcousticTest(.humanOnly, warmupProfile: .four),
               "warm-up cannot affect ordinary B or production input")
        expect(!stack.controller.prepareAppleVPAcousticTest(.doubleTalk, comprehensiveC: true,
                                                            processingProfile: .agcOff, warmupProfile: .zero),
               "the unregistered AGC-OFF plus zero-delay comparison remains rejected")
        let silent = D1ControllerStack(silentScenario: .doubleTalk)
        expect(!silent.controller.prepareAppleVPAcousticTest(.doubleTalk, comprehensiveC: true, warmupProfile: .four),
               "the original four-second silent-smoke cannot acquire a warm-up run")
    }

    static func testWarmupPacketBoundary() throws {
        cases += 1
        guard let plan = MacSpeechAcousticWindowPlan(captureStartedAt: 10_000_000_000, profile: .four) else {
            throw CocoaError(.coderInvalidValue)
        }
        var drain = AppleVPWarmupDrainState(plan: plan)
        var retained = 0
        for index in 0 ..< 951 {
            let frame = MacSpeechAudioFrame(
                captureGeneration: 1, sequenceNumber: UInt64(index + 1),
                monotonicTimestampNanoseconds: plan.captureStartedAt - 10_000_000 + UInt64(index) * 20_000_000,
                pcm16Bytes: Data(repeating: 0, count: 960), activity: 0
            )
            if try drain.retain(frame) {
                retained += 1
            }
        }
        expect(retained == 749 && drain.boundaryPackets == 2 && drain.outsidePackets == 1,
               "both crossing packets are excluded without padding, cropping or timestamp rewriting")
        let duplicate = MacSpeechAudioFrame(captureGeneration: 1, sequenceNumber: 951,
                                            monotonicTimestampNanoseconds: plan.scoreEndedAt,
                                            pcm16Bytes: Data(repeating: 0, count: 960), activity: 0)
        do {
            _ = try drain.retain(duplicate)
            expect(false, "duplicate packets cannot become scoring content")
        } catch { expect(drain.drainedPackets == 951, "rejected duplicate leaves counters unchanged") }
    }
}

@MainActor
private final class D1NormalDependenciesSpy {
    private(set) var calls = 0

    func make() -> (OrchestrationKernel, ProviderKeychainStore) {
        calls += 1
        fatalError("D1 must not construct normal dependencies")
    }
}

private final class D1AudioCapture: MacSpeechAudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var frameBuffer: MacSpeechAudioFrameBuffer?
    private var generation: UInt64 = 0
    private var sampleCursor: Int64 = 0
    private var contentStart: UInt64 = 0
    private var stats: MacSpeechNativeVoiceDebugStats?
    private var starts = 0
    private var stops = 0
    private var active = false
    private let failsStart: Bool
    var omitsSeal = false
    var agcReadbackOverride: Bool?
    var supportsAGCProfile = true
    var supportsWarmupWindows = true
    var contentStartOverride: UInt64?
    private var processingProfile = MacSpeechAppleVPDebugProfile.agcOn

    init(failsStart: Bool = false) {
        self.failsStart = failsStart
    }

    func selectProcessingMode(_ mode: MacSpeechAudioProcessingMode) throws {
        guard mode == .appleVoiceProcessing else { throw MacSpeechAudioCaptureError.voiceProcessingUnavailable }
    }

    func voiceProcessingSnapshot() -> MacSpeechVoiceProcessingSnapshot? {
        lock.withLock { makeVoiceProcessingSnapshot() }
    }

    private func makeVoiceProcessingSnapshot() -> MacSpeechVoiceProcessingSnapshot {
        let format = MacSpeechNativeInputFormat(sampleRate: 48000, channelCount: 1)
        return MacSpeechVoiceProcessingSnapshot(
            mode: .appleVoiceProcessing, configurationID: 1, inputEnabled: true, outputEnabled: true,
            bypassed: false, inputMuted: false,
            automaticGainControlEnabled: agcReadbackOverride ?? processingProfile.automaticGainControlEnabled,
            inputFormat: format, outputFormat: format, validatedAtNanoseconds: 1
        )
    }

    func start(generation: UInt64, frameBuffer: MacSpeechAudioFrameBuffer) throws -> MacSpeechNativeInputFormat {
        try lock.withLock {
            guard !failsStart else { throw MacSpeechAudioCaptureError.engineStartFailed }
            active = true
            starts += 1
            self.generation = generation
            self.frameBuffer = frameBuffer
            contentStart = contentStartOverride ?? DispatchTime.now().uptimeNanoseconds
            sampleCursor = 0
        }
        return MacSpeechNativeInputFormat(sampleRate: 48000, channelCount: 1)
    }

    func stop() {
        lock.withLock {
            processingProfile = .agcOn
            guard active else { return }
            active = false
            stops += 1
            frameBuffer = nil
        }
    }

    func armNativeVoiceDebug(runID: UUID, generation: UInt64) -> Bool {
        armNativeVoiceDebug(runID: runID, generation: generation, profile: .agcOn)
    }

    func armNativeVoiceDebug(runID: UUID, generation: UInt64, profile: MacSpeechAppleVPDebugProfile) -> Bool {
        lock.withLock {
            guard profile == .agcOn || supportsAGCProfile else { return false }
            processingProfile = profile
            var value = MacSpeechNativeVoiceDebugStats(runID: runID, generation: generation, profile: profile)
            value.bind(configurationID: 1, voiceProcessing: makeVoiceProcessingSnapshot())
            stats = value
            return true
        }
    }

    func configureNativeAcousticWindows(
        runID: UUID, generation: UInt64, plan: MacSpeechAcousticWindowPlan
    ) -> Bool {
        lock.withLock {
            guard supportsWarmupWindows, stats?.runID == runID, stats?.captureGeneration == generation else {
                return false
            }
            return stats?.configureWindows(plan) == true
        }
    }

    func nativeVoiceDebugSnapshot(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
        lock.withLock { stats?.snapshot.runID == runID ? stats?.snapshot : nil }
    }

    func sealNativeVoiceDebug(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
        lock.withLock {
            guard !omitsSeal else { return nil }
            guard stats?.snapshot.runID == runID else { return nil }
            stats?.seal()
            return stats?.snapshot
        }
    }

    func stopAndSealNativeVoiceDebug(runID: UUID, generation expected: UInt64) -> MacSpeechNativeVoiceDebugSnapshot? {
        guard lock.withLock({ generation == expected }),
              let sealed = sealNativeVoiceDebug(runID: runID) else { return nil }
        stop()
        return sealed
    }

    func clearNativeVoiceDebug(runID: UUID) {
        lock.withLock {
            if stats?.snapshot.runID == runID {
                stats = nil
                processingProfile = .agcOn
            }
        }
    }

    func emitPackets(_ count: Int, marker: UInt8 = 1) {
        lock.withLock {
            guard active, let frameBuffer else { return }
            for _ in 0 ..< count {
                let timestamp = contentStart + UInt64(sampleCursor) * 1_000_000_000 / 48000
                let pcm = Data((0 ..< 480).flatMap { _ in [marker, 0] })
                let accepted = frameBuffer.append(
                    pcm16Bytes: pcm, activity: 0, generation: generation, timestamp: timestamp
                )
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                                           channels: 1, interleaved: false)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960)!
                buffer.frameLength = 960
                buffer.floatChannelData![0].initialize(repeating: Float(marker) / 32768, count: 960)
                stats?.recordNative(buffer, hostTimeNanoseconds: timestamp, sampleTime: sampleCursor,
                                    configurationID: 1, generation: generation)
                stats?.recordPacket(timestamp: timestamp, byteCount: pcm.count, accepted: accepted,
                                    configurationID: 1, generation: generation)
                sampleCursor += 960
            }
        }
    }

    func emitPreviousGenerationPacket() {
        lock.withLock {
            guard active, let frameBuffer, generation > 0 else { return }
            let previous = generation - 1
            let accepted = frameBuffer.append(
                pcm16Bytes: Data(repeating: 9, count: 960), activity: 0,
                generation: previous, timestamp: contentStart
            )
            stats?.recordPacket(timestamp: contentStart, byteCount: 960, accepted: accepted,
                                configurationID: 1, generation: previous)
        }
    }

    func replaceNativeContext(runID: UUID? = nil, profile: MacSpeechAppleVPDebugProfile? = nil) {
        lock.withLock {
            guard let current = stats?.snapshot else { return }
            var replacement = MacSpeechNativeVoiceDebugStats(
                runID: runID ?? current.runID, generation: generation, profile: profile ?? processingProfile
            )
            replacement.bind(configurationID: 1, voiceProcessing: makeVoiceProcessingSnapshot())
            stats = replacement
        }
    }

    func invalidateTimeline(configuration: UInt64 = 1) {
        lock.withLock {
            stats?.recordPacket(timestamp: contentStart + 123, byteCount: 960, accepted: false,
                                configurationID: configuration, generation: generation)
        }
    }

    var startCount: Int {
        lock.withLock { starts }
    }

    var stopCount: Int {
        lock.withLock { stops }
    }
}

@MainActor
private struct D1ControllerStack {
    let controller: AppController
    let dependencies: D1NormalDependenciesSpy
    let authorization: R855MicrophoneAuthorizationProvider
    let capture: D1AudioCapture
    let player: FakeMacSpeechAudioOutputPlayer
    let output: MacSpeechAudioOutputHost
    let captureMonitor: FakeMacSpeechOutputDeviceMonitor

    init(
        authorizationState: MicrophoneAuthorizationState = .authorized,
        requestedAuthorization: MicrophoneAuthorizationState = .authorized,
        holdQueryNumber: Int? = nil,
        failsCaptureStart: Bool = false,
        byteLimit: Int = 720_000,
        silentScenario: AppleVPAcousticTestScenario? = nil,
        clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        scoreControlDescriptor: Int32? = nil,
        batchScenario: AppleVPAcousticTestScenario? = nil,
        humanBatchScenario: AppleVPAcousticTestScenario? = nil,
        humanOnsetProfile: AppleVPHumanOnsetProfile? = nil,
        macAECArgument: String? = nil,
        runtimeTiming: ((UUID) -> MacSpeechTimingSnapshot?)? = nil,
        outputConfiguration: MacSpeechPCMPlaybackConfiguration = .standard
    ) {
        let dependencies = D1NormalDependenciesSpy()
        let authorization = R855MicrophoneAuthorizationProvider(
            authorization: authorizationState, requestedAuthorization: requestedAuthorization,
            holdQueryNumber: holdQueryNumber
        )
        let capture = D1AudioCapture(failsStart: failsCaptureStart)
        let player = FakeMacSpeechAudioOutputPlayer()
        self.dependencies = dependencies
        self.authorization = authorization
        self.capture = capture
        self.player = player
        let captureMonitor = FakeMacSpeechOutputDeviceMonitor()
        captureMonitor.changeInput(identifier: "d1-input", name: "D1 Fake Input", available: true)
        self.captureMonitor = captureMonitor
        let host = MacSpeechAudioHost(
            authorizationProvider: authorization, capture: capture, deviceMonitor: captureMonitor
        )
        let output = MacSpeechAudioOutputHost(
            player: player, deviceMonitor: FakeMacSpeechOutputDeviceMonitor(), configuration: outputConfiguration
        )
        self.output = output
        controller = AppController(
            acousticTestArguments: ["Aftelle", "--apple-vp-acoustic-test"]
                + (silentScenario.map { ["--apple-vp-silent-smoke=" + $0.rawValue] } ?? [])
                + (scoreControlDescriptor.map { [AppleVPScoreControl.argument + String($0)] } ?? [])
                + (batchScenario.map { ["--apple-vp-bt-abc=" + $0.rawValue] } ?? [])
                + (humanBatchScenario.map { ["--apple-vp-human-abc=" + $0.rawValue] } ?? [])
                + (humanOnsetProfile.map { ["--apple-vp-human-onset=" + $0.rawValue] } ?? [])
                + (macAECArgument.map { [AppleVPMacAECBatchRun.argument + $0] } ?? []),
            speechAudioHost: host, speechAudioOutputHost: output, speechAudioCapture: capture,
            acousticTestDurationNanoseconds: 15_000_000_000, acousticTestByteLimit: byteLimit,
            acousticTestClock: clock,
            acousticRuntimeTiming: runtimeTiming,
            normalDependenciesFactory: dependencies.make
        )
    }
}

private extension RealtimeInterruptionEvidenceTests {
    static func startD1(_ controller: AppController) {
        controller.startAppleVPAcousticTest(
            microphoneConsent: true, speakerConsent: true, localCaptureConsent: true
        )
    }

    static func expectD1Cleanup(_ stack: D1ControllerStack) {
        expect(stack.controller.appleVPAcousticTestState.phase == .sealed, "D1 terminal evidence is sealed")
        expect(!stack.controller.speechAudioHostSnapshot.isCapturing, "D1 terminal cleanup releases capture")
        expect(stack.controller.speechAudioOutputHostSnapshot.state == .closed, "D1 terminal cleanup closes output")
        expect(stack.dependencies.calls == 0, "D1 never initializes the normal Runtime/Provider/Store graph")
    }

    static func testD1PreparationAndConsent() {
        cases += 1
        let stack = D1ControllerStack()
        expect(stack.controller.appleVPAcousticTestState.phase == .idle, "D1 is initially unarmed")
        expect(stack.controller.prepareAppleVPAcousticTest(.residentOnly), "D1 explicitly prepares a scenario")
        expect(stack.controller.appleVPAcousticTestState.phase == .ready, "preparation alone is device-free")
        stack.controller.startAppleVPAcousticTest(
            microphoneConsent: false, speakerConsent: false, localCaptureConsent: false
        )
        expect(stack.controller.appleVPAcousticTestState.phase == .ready
            && stack.controller.appleVPAcousticTestState.errorCode == "consent_required",
            "missing consent rejects before an asynchronous device operation")
        expect(stack.capture.startCount == 0 && stack.player.prepareCount == 0,
               "preparation and consent refusal perform no audio activation")
        expect(stack.dependencies.calls == 0, "preparation never creates normal dependencies")
        expectD1ExportRejected("an unsealed run has no export destination") {
            _ = try stack.controller.appleVPAcousticTestExportURL(asWAV: false)
        }
        expectD1ExportRejected("an unsealed run cannot export JSON") {
            let directory = try d1ExportTestDirectory()
            try stack.controller.writeAppleVPAcousticTestJSON(
                to: directory.appendingPathComponent("unsealed.json"), localExportConsent: true
            )
        }
    }

    static func testD1ListeningCapture() async throws {
        cases += 1
        let stack = D1ControllerStack(byteLimit: 960)
        expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly), "B prepares without a playback file")
        stack.controller.startAppleVPAcousticTest(
            microphoneConsent: true, speakerConsent: false, localCaptureConsent: true
        )
        await waitUntil("D1 B running") { stack.controller.appleVPAcousticTestState.phase == .running }
        startD1(stack.controller)
        expect(!stack.controller.prepareAppleVPAcousticTest(.residentOnly), "busy run cannot switch scenario")
        expect(!stack.controller.selectAppleVPAcousticPlaybackURL(nil), "busy run cannot change playback source")
        stack.capture.emitPackets(1)
        await waitUntil("D1 B sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
        expect(stack.capture.startCount == 1, "duplicate Start does not create a second capture")
        expect(stack.player.prepareCount == 0 && stack.player.startCount == 0, "B never prepares or plays output")
        expect(stack.controller.appleVPAcousticTestState.packetCount == 1
            && stack.controller.appleVPAcousticTestState.byteCount == 960, "B retains exactly the emitted packet")
        let wav = try stack.controller.appleVPAcousticTestProcessedWAVData()
        expect(wav.suffix(960) == Data((0 ..< 480).flatMap { _ in [UInt8(1), 0] }),
               "WAV data is byte-identical to the retained processed packet")
        let manifest = try JSONSerialization.jsonObject(with: stack.controller.appleVPAcousticTestManifestData())
            as? [String: Any]
        expect(manifest?["physical_acceptance"] as? String == "UNVERIFIED"
            && manifest?["runtime_interruption"] as? String == "DISABLED",
            "Fake engineering success cannot grant physical or Runtime acceptance")
        try expectD1ExportConsent(stack.controller, expected: wav)
        expectD1Cleanup(stack)
    }

    static func testD1PlaybackScenarios() async throws {
        let source = try d1SyntheticPlayback(packets: 6)
        defer { try? FileManager.default.removeItem(at: source) }
        for scenario in [AppleVPAcousticTestScenario.residentOnly, .doubleTalk] {
            cases += 1
            let stack = D1ControllerStack(byteLimit: 960)
            expect(stack.controller.prepareAppleVPAcousticTest(scenario), "A/C prepare explicitly")
            expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "A/C accept only the selected test URL")
            startD1(stack.controller)
            await waitUntil("D1 playback running") { stack.controller.appleVPAcousticTestState.phase == .running }
            await waitUntil("D1 playback source scheduled") {
                stack.player.startCount == 1 && stack.player.payloads.reduce(0) { $0 + $1.count } == 5760
            }
            expect(stack.player.prepareCount == 1 && stack.player.startCount == 1,
                   "A/C feed the original OutputHost and injected FakePlayer")
            expect(stack.player.payloads.allSatisfy { $0.count <= 4800 },
                   "playback chunks are bounded to 100ms before the original consumer watchdog")
            expect(stack.player.payloads.reduce(into: Data()) { $0.append($1) }
                == Data((0 ..< 2880).flatMap { _ in [UInt8(2), 0] }),
                "OutputHost receives the complete selected synthetic source sequence")
            stack.capture.emitPackets(1)
            await waitUntil("D1 playback sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            expect(stack.controller.appleVPAcousticTestState.errorCode == nil,
                   "complete Fake engineering evidence seals without a physical PASS")
            try expectD1ExportConsent(
                stack.controller, expected: stack.controller.appleVPAcousticTestProcessedWAVData()
            )
            expectD1Cleanup(stack)
        }
    }

    static func testD1StopDuringAuthorization() async {
        cases += 1
        let stack = D1ControllerStack(holdQueryNumber: 1, byteLimit: 960)
        expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly), "held authorization scenario prepares")
        startD1(stack.controller)
        await waitUntil("D1 authorization barrier") { await stack.authorization.isQueryPending() }
        var stopReturned = false
        let stopping = Task { @MainActor in
            await stack.controller.stopAppleVPAcousticTest()
            stopReturned = true
        }
        await waitUntil("D1 Stop returns before permission callback") { stopReturned }
        await stopping.value
        let permissionStillPending = await stack.authorization.isQueryPending()
        expect(permissionStillPending, "Stop never waits for the uncancellable microphone callback")
        expect(stack.capture.startCount == 0 && stack.player.startCount == 0,
               "late authorization cannot start retired audio")
        expect(stack.controller.appleVPAcousticTestState.errorCode == "cancelled", "Stop preserves cancellation")
        expectD1Cleanup(stack)
        let retiredRun = stack.controller.appleVPAcousticTestState.runID
        expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly, discardPreviousResult: true),
               "an explicit next preparation preserves the unresolved authorization fence")
        startD1(stack.controller)
        expect(stack.controller.appleVPAcousticTestState.authorizationPending
            && !stack.controller.appleVPAcousticTestState.canStart
            && stack.controller.appleVPAcousticTestState.errorCode == "authorization_pending"
            && stack.capture.startCount == 0, "pending authorization prevents a concurrent replacement capture")
        await stack.authorization.releaseQuery()
        await waitUntil("D1 old authorization cleanup") { stack.controller.appleVPAcousticTestState.canStart }
        startD1(stack.controller)
        await waitUntil("D1 next run starts") { stack.controller.appleVPAcousticTestState.phase == .running }
        expect(stack.controller.appleVPAcousticTestState.runID != retiredRun && stack.capture.startCount == 1,
               "only explicit Start after old authorization cleanup can create the next capture")
        stack.capture.emitPackets(1)
        await waitUntil("D1 next run sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
        expect(stack.controller.appleVPAcousticTestState.errorCode == nil, "next run recovers after stale permission")
        expectD1Cleanup(stack)
    }

    static func testD1PermissionAndCaptureFailures() async {
        for captureFailure in [false, true] {
            cases += 1
            let stack = D1ControllerStack(
                authorizationState: captureFailure ? .authorized : .denied, failsCaptureStart: captureFailure
            )
            expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly), "failure scenario prepares")
            startD1(stack.controller)
            await waitUntil("D1 failure sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            expect(stack.controller.appleVPAcousticTestState.errorCode
                == (captureFailure ? "capture_unavailable" : "microphone_not_authorized"),
                "the first permission/capture failure remains explicit")
            expect(stack.capture.startCount == 0 && stack.player.startCount == 0,
                   "failed permission or capture cannot create playback")
            expectD1ExportRejected("a sealed run without valid PCM cannot create a WAV") {
                let url = try stack.controller.appleVPAcousticTestExportURL(asWAV: true)
                try stack.controller.writeAppleVPAcousticTestWAV(to: url, localExportConsent: true)
            }
            expectD1Cleanup(stack)
        }
    }

    static func testD1ByteLimitAndPreviousResult() async {
        cases += 1
        let stack = D1ControllerStack(byteLimit: 960)
        expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly), "bounded capture prepares")
        startD1(stack.controller)
        await waitUntil("D1 bounded capture running") { stack.controller.appleVPAcousticTestState.phase == .running }
        stack.capture.emitPackets(2)
        await waitUntil("D1 capacity failure sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
        expect(stack.controller.appleVPAcousticTestState.errorCode == "processed_pcm_capacity_exceeded",
               "overflow preserves a capacity failure rather than silently truncating")
        expect(stack.controller.appleVPAcousticTestState.byteCount == 960,
               "retained bytes never exceed the configured bound")
        let runID = stack.controller.appleVPAcousticTestState.runID
        expect(!stack.controller.prepareAppleVPAcousticTest(.doubleTalk), "a sealed result requires explicit discard")
        expect(stack.controller.appleVPAcousticTestState.runID == runID, "failed preparation preserves sealed identity")
        expectD1Cleanup(stack)
        expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly, discardPreviousResult: true),
               "explicit discard is the only way to prepare the next run")
        expect(stack.controller.appleVPAcousticTestState.byteCount == 0, "new preparation carries no old PCM")
    }

    static func testD1PlaybackFailure() async throws {
        cases += 1
        let source = try d1SyntheticPlayback()
        defer { try? FileManager.default.removeItem(at: source) }
        let stack = D1ControllerStack()
        stack.player.prepareError = .outputUnavailable
        expect(stack.controller.prepareAppleVPAcousticTest(.residentOnly), "playback failure scenario prepares")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "playback test selects only its own asset")
        startD1(stack.controller)
        await waitUntil("D1 playback failure sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
        expect(stack.controller.appleVPAcousticTestState.errorCode == "playback_failed",
               "playback preparation failure closes without another route")
        expect(stack.capture.startCount == 0 && stack.player.startCount == 0,
               "failed output preparation cannot start capture or playback")
        expectD1Cleanup(stack)
    }

    static func testD1StaleCapture() async {
        cases += 1
        let stack = D1ControllerStack(byteLimit: 960)
        expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly), "stale callback scenario prepares")
        startD1(stack.controller)
        await waitUntil("D1 stale test running") { stack.controller.appleVPAcousticTestState.phase == .running }
        stack.capture.emitPreviousGenerationPacket()
        stack.capture.emitPackets(1, marker: 3)
        await waitUntil("D1 stale evidence sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
        expect(stack.controller.appleVPAcousticTestState.byteCount == 960,
               "old-generation PCM never joins current bytes")
        expect(stack.controller.speechAudioHostSnapshot.rejectedStaleFrameCount == 1,
               "old-generation callback remains visible as rejected")
        expect(stack.controller.appleVPAcousticTestState.errorCode == "native_coverage_unverified",
               "stale native evidence cannot be promoted to valid coverage")
        expectD1Cleanup(stack)
    }

    static func testD1PlaybackPressureAndLateCompletion() async throws {
        cases += 1
        let source = try d1SyntheticPlayback(packets: 12)
        defer { try? FileManager.default.removeItem(at: source) }
        let configuration = MacSpeechPCMPlaybackConfiguration(
            capacity: 1, lowWatermark: 0, consumerTimeoutNanoseconds: 2_000_000_000,
            startupBufferCount: 1, startupBufferDurationNanoseconds: 0, scheduleAheadCount: 1
        )
        let stack = D1ControllerStack(outputConfiguration: configuration)
        expect(stack.controller.prepareAppleVPAcousticTest(.doubleTalk), "pressure scenario prepares")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source),
               "pressure test selects its own synthetic source")
        startD1(stack.controller)
        await waitUntil("D1 output pressure") { await stack.output.currentSnapshot().pressureWaitCount > 0 }
        var stopReturned = false
        let stopping = Task { @MainActor in
            await stack.controller.stopAppleVPAcousticTest()
            stopReturned = true
        }
        await waitUntil("D1 Stop releases pressured output") { stopReturned }
        await stopping.value
        let retired = await stack.output.currentSnapshot()
        stack.player.completeStoppedChunk()
        await waitUntil("D1 late output completion rejected") {
            await stack.output.currentSnapshot().rejectedCallbackCount > retired.rejectedCallbackCount
        }
        let afterLate = await stack.output.currentSnapshot()
        expect(afterLate.state == .closed && afterLate.generation == retired.generation,
               "late completion cannot revive closed output")
        expect(stack.player.payloads.allSatisfy { $0.count <= 4800 },
               "queue pressure never expands playback chunk duration")
        expect(stack.controller.appleVPAcousticTestState.errorCode == "cancelled",
               "Stop retains the first cancellation while waking blocked playback")
        expectD1Cleanup(stack)
    }

    static func expectD1ExportConsent(_ controller: AppController, expected: Data) throws {
        let wavURL = try controller.appleVPAcousticTestExportURL(asWAV: true)
        let jsonURL = try controller.appleVPAcousticTestExportURL(asWAV: false)
        let directory = try d1ExportTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        cases += 1
        expect(wavURL.deletingLastPathComponent() == directory,
               "Controller chooses the isolated approved cache directory")
        expect(!FileManager.default.fileExists(atPath: directory.path),
               "computing destinations creates no files or directory")
        expectD1ExportRejected("local WAV export requires its own explicit consent") {
            try controller.writeAppleVPAcousticTestWAV(to: wavURL, localExportConsent: false)
        }
        expectD1ExportRejected("local JSON export requires its own explicit consent") {
            try controller.writeAppleVPAcousticTestJSON(to: jsonURL, localExportConsent: false)
        }
        expect(!FileManager.default.fileExists(atPath: directory.path), "refused consent writes no evidence")
        try testD1ExportPathRefusals(controller, wavURL: wavURL)
        try testD1ExportDirectorySymlink(controller, wavURL: wavURL)
        try testD1ExportRepositoryAncestor(controller, wavURL: wavURL)
        try testD1ExportPair(controller, wavURL: wavURL, jsonURL: jsonURL, expected: expected)
    }

    static func d1ExportTestDirectory() throws -> URL {
        guard let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let cache = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        guard cache.path.hasPrefix(URL(fileURLWithPath: home).path + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return cache.appendingPathComponent("com.eterna.aftelle.debug-apple-vp-evidence", isDirectory: true)
    }

    static func expectD1ExportRejected(_ message: String, operation: () throws -> Void) {
        do {
            try operation()
            expect(false, message)
        } catch {
            expect(true, message)
        }
    }

    static func testD1ExportPathRefusals(_ controller: AppController, wavURL: URL) throws {
        cases += 1
        let directory = try d1ExportTestDirectory()
        let outside = directory.deletingLastPathComponent().appendingPathComponent("d1-r2-outside.wav")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("d1-r2-refused.wav")
        let wrongRun = directory.appendingPathComponent("run-\(UUID().uuidString).wav")
        let traversal = URL(fileURLWithPath:
            directory.path + "/../" + directory.lastPathComponent + "/" + wavURL.lastPathComponent)
        for target in [outside, repository, wrongRun, traversal] {
            expectD1ExportRejected("WAV refuses any nonexact approved run destination") {
                try controller.writeAppleVPAcousticTestWAV(to: target, localExportConsent: true)
            }
            expect(!FileManager.default.fileExists(atPath: target.path), "rejected path creates no file")
        }
        expectD1ExportRejected("a WAV destination cannot receive JSON") {
            try controller.writeAppleVPAcousticTestJSON(to: wavURL, localExportConsent: true)
        }
        expect(!FileManager.default.fileExists(atPath: directory.path),
               "invalid destinations never create the evidence directory")
    }

    static func testD1ExportDirectorySymlink(_ controller: AppController, wavURL: URL) throws {
        cases += 1
        let directory = try d1ExportTestDirectory()
        let escaped = directory.deletingLastPathComponent().appendingPathComponent("d1-r2-escape-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: escaped, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: escaped)
        }
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: escaped)
        expectD1ExportRejected("an approved-directory symlink cannot escape to another directory") {
            try controller.writeAppleVPAcousticTestWAV(to: wavURL, localExportConsent: true)
        }
        let contents = try FileManager.default.contentsOfDirectory(atPath: escaped.path)
        expect(contents.isEmpty, "symlink refusal writes no escaped file")
    }

    static func testD1ExportRepositoryAncestor(_ controller: AppController, wavURL: URL) throws {
        cases += 1
        let directory = try d1ExportTestDirectory()
        let marker = directory.deletingLastPathComponent().appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: marker) }
        expectD1ExportRejected("the approved basename inside a Git ancestor is refused") {
            try controller.writeAppleVPAcousticTestWAV(to: wavURL, localExportConsent: true)
        }
        expect(!FileManager.default.fileExists(atPath: wavURL.path), "Git ancestor refusal writes no audio")
    }

    static func testD1ExportPair(
        _ controller: AppController, wavURL: URL, jsonURL: URL, expected: Data
    ) throws {
        cases += 1
        let directory = try d1ExportTestDirectory()
        try controller.writeAppleVPAcousticTestWAV(to: wavURL, localExportConsent: true)
        try controller.writeAppleVPAcousticTestJSON(to: jsonURL, localExportConsent: true)
        let exported = try Data(contentsOf: wavURL)
        expect(exported == expected, "explicit Fake export preserves exact processed WAV bytes")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any]
        let runID = controller.appleVPAcousticTestState.runID?.uuidString
        expect(manifest?["run_id"] as? String == runID, "JSON belongs to the sealed capture run")
        expect(wavURL.deletingPathExtension().lastPathComponent == "run-" + (runID ?? "UNKNOWN")
            && jsonURL.deletingPathExtension().lastPathComponent == wavURL.deletingPathExtension().lastPathComponent,
            "the JSON/WAV pair shares the exact run filename identity")
        expect(manifest?["source_commit"] is NSNull && manifest?["build_identity"] is NSNull,
               "unregistered source and build identities remain UNKNOWN")
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        expect(Set(contents) == Set([wavURL.lastPathComponent, jsonURL.lastPathComponent]),
               "only the explicit corresponding JSON/WAV pair exists")
        try expectD1ExportPermissions(directory: directory, files: [wavURL, jsonURL])
        try expectD1ExportNoOverwrite(controller, wavURL: wavURL, jsonURL: jsonURL)
        try testD1ExportFileSymlink(controller, wavURL: wavURL)
    }

    static func expectD1ExportPermissions(directory: URL, files: [URL]) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
               "evidence directory permissions are 0700")
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                   "exported file permissions are 0600")
        }
    }

    static func expectD1ExportNoOverwrite(_ controller: AppController, wavURL: URL, jsonURL: URL) throws {
        cases += 1
        let wavBefore = try Data(contentsOf: wavURL)
        let jsonBefore = try Data(contentsOf: jsonURL)
        expectD1ExportRejected("WAV export never overwrites an existing file") {
            try controller.writeAppleVPAcousticTestWAV(to: wavURL, localExportConsent: true)
        }
        expectD1ExportRejected("JSON export never overwrites an existing file") {
            try controller.writeAppleVPAcousticTestJSON(to: jsonURL, localExportConsent: true)
        }
        let wavAfter = try Data(contentsOf: wavURL)
        let jsonAfter = try Data(contentsOf: jsonURL)
        expect(wavAfter == wavBefore && jsonAfter == jsonBefore,
               "refused overwrites preserve both original byte sequences")
    }

    static func testD1ExportFileSymlink(_ controller: AppController, wavURL: URL) throws {
        cases += 1
        let escaped = wavURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("d1-r2-existing-\(UUID().uuidString)")
        let marker = Data("synthetic sentinel".utf8)
        try marker.write(to: escaped, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: escaped) }
        try FileManager.default.removeItem(at: wavURL)
        try FileManager.default.createSymbolicLink(at: wavURL, withDestinationURL: escaped)
        expectD1ExportRejected("an existing output symlink is refused without following it") {
            try controller.writeAppleVPAcousticTestWAV(to: wavURL, localExportConsent: true)
        }
        let after = try Data(contentsOf: escaped)
        expect(after == marker, "output symlink refusal preserves the unrelated synthetic target")
    }

    static func testD1RouteChange() async {
        for changesInput in [true, false] {
            cases += 1
            let stack = D1ControllerStack()
            expect(stack.controller.prepareAppleVPAcousticTest(.humanOnly), "route change scenario prepares")
            startD1(stack.controller)
            await waitUntil("D1 route test running") { stack.controller.appleVPAcousticTestState.phase == .running }
            if changesInput {
                stack.captureMonitor.changeInput(identifier: "d1-replacement", name: "D1 Fake Input", available: true)
            } else {
                stack.captureMonitor.changeOutput(identifier: "d1-replacement", name: "D1 Fake Output", available: true)
            }
            await waitUntil("D1 route failure sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            expect(stack.controller.appleVPAcousticTestState.errorCode == "route_changed",
                   "an actual Fake route callback seals the run as invalid")
            expect(stack.capture.startCount == 1 && stack.capture.stopCount == 1,
                   "route failure releases capture once and never automatically restarts")
            expectD1Cleanup(stack)
        }
    }

    static func d1SyntheticPlayback(packets: Int = 1) throws -> URL {
        let pcm = Data((0 ..< (480 * packets)).flatMap { _ in [UInt8(2), 0] })
        var bytes = Data("RIFF".utf8)
        d1AppendLittleEndian(UInt32(36 + pcm.count), to: &bytes)
        bytes.append(Data("WAVEfmt ".utf8))
        d1AppendLittleEndian(16, to: &bytes)
        bytes.append(contentsOf: [1, 0, 1, 0])
        d1AppendLittleEndian(24000, to: &bytes)
        d1AppendLittleEndian(48000, to: &bytes)
        bytes.append(contentsOf: [2, 0, 16, 0])
        bytes.append(Data("data".utf8))
        d1AppendLittleEndian(UInt32(pcm.count), to: &bytes)
        bytes.append(pcm)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aftelle-d1-synthetic-\(UUID().uuidString).wav")
        try bytes.write(to: url, options: .withoutOverwriting)
        return url
    }

    static func d1AppendLittleEndian(_ value: UInt32, to bytes: inout Data) {
        bytes.append(contentsOf: (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}

private struct T32CascadedCredentialReader: ProviderCredentialReading {
    func readCredential(for _: String) throws -> String? {
        "offline-test-credential"
    }
}

private struct T32CascadedTextTransport: ProviderHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let content = #"{"reply_text":"offline reply","expression_state":"neutral","expression_intensity":0}"#
        let payload = ["choices": [["message": ["content": content]]]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return (body, HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!)
    }
}

private actor T32CascadedASRProvider: ASRProvider {
    private var starts = 0
    private var inputs: [ASRAudioInput] = []
    private var inputContinuation: CheckedContinuation<Void, Never>?
    func start(request _: ASRStartRequest) async throws {
        starts += 1
    }

    func send(_ input: ASRAudioInput) async throws {
        inputs.append(input)
        let continuation = inputContinuation
        inputContinuation = nil
        continuation?.resume()
    }

    func receive(generation: UInt64) async throws -> ASREvent {
        if !inputs.contains(where: { $0.generation == generation }) {
            await withCheckedContinuation { inputContinuation = $0 }
        }
        return ASREvent(generation: generation, kind: .finalTranscript("offline turn \(starts)"))
    }

    func cancel(generation _: UInt64) async throws {
        let continuation = inputContinuation
        inputContinuation = nil
        continuation?.resume()
    }

    func close(generation _: UInt64) async throws {}
    func startCount() -> Int {
        starts
    }

    func sources() -> [ASRAudioSource] {
        inputs.map(\.source)
    }
}

private actor T32CascadedTTSProvider: TTSProvider {
    private var events: [TTSEvent] = []
    private var starts = 0
    func start(request: TTSSynthesisRequest) async throws {
        starts += 1
        let started = TTSEvent(generation: request.generation, kind: .started)
        let audio = TTSEvent(generation: request.generation, kind: .audio(TTSAudioChunk(
            generation: request.generation,
            sequenceNumber: 1,
            bytes: Data(repeating: 1, count: 960),
            format: .pcm16, sampleRate: 24000, channelCount: 1
        )))
        let done = TTSEvent(generation: request.generation, kind: .done)
        events = [started, audio, done]
    }

    func receive(generation _: UInt64) async throws -> TTSEvent {
        guard !events.isEmpty else { throw SpeechRouteError.invalidEvent }
        return events.removeFirst()
    }

    func cancel(generation _: UInt64) async throws {
        events.removeAll()
    }

    func close(generation _: UInt64) async throws {}
    func startCount() -> Int {
        starts
    }
}

private struct R81AuthorizationProvider: MicrophoneAuthorizationProviding {
    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        .authorized
    }
}

private actor R855MicrophoneAuthorizationProvider:
    MicrophoneAuthorizationProviding {
    private var authorization: MicrophoneAuthorizationState
    private var requestedAuthorization: MicrophoneAuthorizationState
    private var holdsRequest: Bool
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var queries = 0
    private var requests = 0
    private let holdQueryNumber: Int?
    private var queryContinuation: CheckedContinuation<Void, Never>?

    init(
        authorization: MicrophoneAuthorizationState,
        requestedAuthorization: MicrophoneAuthorizationState = .authorized,
        holdsRequest: Bool = false,
        holdQueryNumber: Int? = nil
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
        self.holdsRequest = holdsRequest
        self.holdQueryNumber = holdQueryNumber
    }

    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        queries += 1
        if queries == holdQueryNumber {
            await withCheckedContinuation { continuation in
                queryContinuation = continuation
            }
        }
        return authorization
    }

    func isQueryPending() -> Bool {
        queryContinuation != nil
    }

    func releaseQuery() {
        let continuation = queryContinuation
        queryContinuation = nil
        continuation?.resume()
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        requests += 1
        if holdsRequest {
            await withCheckedContinuation { continuation in
                requestContinuation = continuation
            }
        }
        authorization = requestedAuthorization
        return authorization
    }

    func releaseRequest(as authorization: MicrophoneAuthorizationState) {
        requestedAuthorization = authorization
        holdsRequest = false
        let continuation = requestContinuation
        requestContinuation = nil
        continuation?.resume()
    }

    func isRequestPending() -> Bool {
        requestContinuation != nil
    }

    func requestCount() -> Int { requests }
    func queryCount() -> Int { queries }
}

private final class R81DeviceMonitor:
    MacSpeechDeviceRouteMonitoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private let route = MacSpeechDeviceRoute(
        input: MacSpeechAudioDevice(
            identifier: "r81-input",
            name: "R8.1 Input",
            isAvailable: true
        ),
        output: MacSpeechAudioDevice(
            identifier: "r81-output",
            name: "R8.1 Output",
            isAvailable: true
        )
    )
    private var monitoring = false
    private var starts = 0
    private var stops = 0

    func currentRoute() -> MacSpeechDeviceRoute { route }
    func start(onChange: @escaping @Sendable () -> Void) {
        lock.withLock {
            guard !monitoring else { return }
            monitoring = true
            starts += 1
        }
    }
    func stop() {
        lock.withLock {
            guard monitoring else { return }
            monitoring = false
            stops += 1
        }
    }

    var isMonitoring: Bool { lock.withLock { monitoring } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
}

private final class R81AECBackend: MacSpeechAECBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var captureOutput: [Float]?

    func configure() throws {}
    func processRender(_ samples: [Float]) throws {}

    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult {
        let processed = lock.withLock { captureOutput ?? samples }
        return MacSpeechAECCaptureResult(
            processedSamples: processed,
            linearOutputSamples: stride(
                from: 0,
                to: processed.count,
                by: 3
            ).map { index in
                (processed[index] + processed[index + 1]
                    + processed[index + 2]) / 3
            }
        )
    }

    func setDelay(milliseconds: Int) throws {}
    func reset() throws {}

    func stats() throws -> MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(
            enabled: true,
            active: true,
            estimatedDelayMilliseconds: 0,
            erlDecibels: 12,
            erleDecibels: 24
        )
    }

    func setCaptureOutput(_ samples: [Float]) {
        lock.withLock { captureOutput = samples }
    }
}

private final class R81AudioCapture:
    MacSpeechAudioCapturing,
    @unchecked Sendable {
    private let lock = NSLock()
    private var frameBuffer: MacSpeechAudioFrameBuffer?
    private var generation: UInt64?
    private var started = false
    private var starts = 0
    private var stops = 0
    private var selectedProcessingMode = MacSpeechAudioProcessingMode.webRTCAEC3
    let acousticEchoHost: MacSpeechAcousticEchoHost

    init(acousticEchoHost: MacSpeechAcousticEchoHost) {
        self.acousticEchoHost = acousticEchoHost
    }

    func selectProcessingMode(_ mode: MacSpeechAudioProcessingMode) throws {
        try lock.withLock {
            guard !started else {
                throw MacSpeechAudioCaptureError.processingModeBusy
            }
            // Mechanical route seam only; this fake retains its injected acoustic evidence.
            selectedProcessingMode = mode
        }
    }

    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        lock.withLock {
            started = true
            starts += 1
            self.generation = generation
            self.frameBuffer = frameBuffer
        }
        return MacSpeechNativeInputFormat(
            sampleRate: 48_000,
            channelCount: 1
        )
    }

    func stop() {
        lock.withLock {
            guard started else { return }
            started = false
            stops += 1
        }
    }

    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot? {
        acousticEchoHost.snapshot()
    }

    func acousticObservationSnapshot()
        -> MacSpeechAcousticObservationSnapshot? {
        acousticEchoHost.acousticObservationSnapshot()
    }

    func resetAcousticEchoDiagnostics() {
        acousticEchoHost.resetDiagnostics()
    }

    var isStarted: Bool { lock.withLock { started } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    var processingMode: MacSpeechAudioProcessingMode {
        lock.withLock { selectedProcessingMode }
    }

    @discardableResult
    func emit(_ marker: UInt8) -> Bool {
        let target = lock.withLock { (started, frameBuffer, generation) }
        guard target.0,
              let frameBuffer = target.1,
              let generation = target.2 else { return false }
        let acoustic = acousticEchoHost.acousticObservationSnapshot()
        let activityEvidenceKind: MacSpeechAudioActivityEvidenceKind =
            acoustic.sourceGateOpen
                && acoustic.sourceGateEpoch > 0
                && (acoustic.inputClassification == .nearEndSpeech
                    || acoustic.inputClassification == .doubleTalk)
                ? .sourceGatedNearEnd : .none
        return frameBuffer.append(
            pcm16Bytes: Data(repeating: marker, count: 960),
            activity: 0.25,
            generation: generation,
            timestamp: acoustic.captureHostTimeNanoseconds
                ?? DispatchTime.now().uptimeNanoseconds,
            activityEvidenceKind: activityEvidenceKind,
            residentPlaybackSequence: acoustic.playbackSequence,
            residentPlaybackActive: acoustic.isPlaybackActive,
            lastAudibleResidentRenderTimestampNanoseconds:
                acoustic.lastAudibleRenderHostTimeNanoseconds,
            sourceGateEpoch: activityEvidenceKind == .sourceGatedNearEnd
                ? acoustic.sourceGateEpoch : 0,
            acousticSnapshot: acoustic
        )
    }
}

private actor R81RealtimeProvider: RealtimeResidentBrainProvider {
    private var openCommands: [RealtimeBrainOpenSessionCommand] = []
    private var contextUpdates: [RealtimeBrainRuntimeContextUpdate] = []
    private var audioFrames: [RealtimeBrainAudioFrame] = []
    private var responseCreateCommands:
        [RealtimeBrainCreateResponseCommand] = []
    private var interruptCommands: [RealtimeBrainInterruptCommand] = []
    private var closeCommands: [RealtimeBrainCloseSessionCommand] = []
    private var events: [RealtimeResidentBrainEvent] = []
    private var receiveCallCount = 0
    private var receiveContinuation:
        CheckedContinuation<RealtimeResidentBrainEvent, Error>?
    private var holdsInterrupt = false
    private var wakesReceiveOnInterrupt = false
    private var interruptContinuation: CheckedContinuation<Void, Never>?
    private var nextInterruptError: RealtimeResidentBrainError?
    private var holdsAudio = false
    private var audioContinuation: CheckedContinuation<Void, Never>?

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        openCommands.append(command)
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {
        contextUpdates.append(update)
        if update.kind == .bootstrap {
            deliver(RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(
                    session: update.identity,
                    turnID: nil,
                    responseID: nil,
                    contextRevision: update.contextRevision
                ),
                sequence: 1,
                kind: .sessionReady
            ))
        }
    }

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {
        audioFrames.append(frame)
        if holdsAudio {
            await withCheckedContinuation { continuation in
                audioContinuation = continuation
            }
        }
    }

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {}

    func createResponse(
        _ command: RealtimeBrainCreateResponseCommand
    ) async throws {
        responseCreateCommands.append(command)
    }

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {}

    func interrupt(_ command: RealtimeBrainInterruptCommand) async throws {
        interruptCommands.append(command)
        if let error = nextInterruptError {
            nextInterruptError = nil
            throw error
        }
        if holdsInterrupt {
            await withCheckedContinuation { continuation in
                interruptContinuation = continuation
            }
        }
        if wakesReceiveOnInterrupt, let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(
                    session: command.identity,
                    turnID: nil,
                    responseID: nil,
                    contextRevision: contextUpdates.last?.contextRevision ?? 1
                ),
                sequence: 1,
                kind: .cancelled(.interrupted)
            ))
        }
    }

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        receiveCallCount += 1
        if !events.isEmpty { return events.removeFirst() }
        return try await withCheckedThrowingContinuation { continuation in
            precondition(receiveContinuation == nil)
            receiveContinuation = continuation
        }
    }

    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws {
        closeCommands.append(command)
        let continuation = receiveContinuation
        receiveContinuation = nil
        continuation?.resume(throwing: RealtimeResidentBrainError.cancelled)
    }

    func enqueue(_ event: RealtimeResidentBrainEvent) {
        deliver(event)
    }

    func holdInterrupt() {
        holdsInterrupt = true
    }

    func enableInterruptReceiveWake() {
        wakesReceiveOnInterrupt = true
    }

    func failNextInterrupt(_ error: RealtimeResidentBrainError) {
        nextInterruptError = error
    }

    func holdAudio() {
        holdsAudio = true
    }

    func releaseAudio() {
        holdsAudio = false
        let continuation = audioContinuation
        audioContinuation = nil
        continuation?.resume()
    }

    func isAudioHeld() -> Bool {
        audioContinuation != nil
    }

    func releaseInterrupt() {
        holdsInterrupt = false
        let continuation = interruptContinuation
        interruptContinuation = nil
        continuation?.resume()
    }

    func isInterruptHeld() -> Bool {
        interruptContinuation != nil
    }

    func hasPendingReceive() -> Bool {
        receiveContinuation != nil
    }

    func openCount() -> Int { openCommands.count }
    func audioCount() -> Int { audioFrames.count }
    func interruptCount() -> Int { interruptCommands.count }
    func closeCount() -> Int { closeCommands.count }
    func responseCreateCount() -> Int { responseCreateCommands.count }

    func recordedResponseCreateCommands()
        -> [RealtimeBrainCreateResponseCommand] {
        responseCreateCommands
    }
    func receiveCount() -> Int { receiveCallCount }

    func lastAudioFrame() -> RealtimeBrainAudioFrame? {
        audioFrames.last
    }

    func lastCloseCommand() -> RealtimeBrainCloseSessionCommand? {
        closeCommands.last
    }

    func closeGenerations() -> [UInt64] {
        closeCommands.map(\.identity.generation)
    }

    func lastInterruptCommand() -> RealtimeBrainInterruptCommand? {
        interruptCommands.last
    }

    func latestSession() -> RealtimeBrainSessionIdentity? {
        openCommands.last?.identity
    }

    private func deliver(_ event: RealtimeResidentBrainEvent) {
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: event)
        } else {
            events.append(event)
        }
    }
}

private actor R81StartBarrier {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waiterCount() -> Int { waiters.count }

    func release() {
        isOpen = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: true)
        pending.forEach { $0.resume() }
    }
}

private struct R81Target {
    let session: RealtimeBrainSessionIdentity
    let turnID: RealtimeBrainTurnID
    let responseID: RealtimeBrainResponseID
    let contextRevision: UInt64
}

private struct R81Stack {
    let runtime: RuntimeCore
    let provider: R81RealtimeProvider
    let sessionStore: SessionStore
    let target: R81Target
}

@MainActor
private struct R81ControllerStack {
    let controller: AppController
    let runtime: RuntimeCore
    let provider: R81RealtimeProvider
    let aecBackend: R81AECBackend
    let acousticEchoHost: MacSpeechAcousticEchoHost
    let capture: R81AudioCapture
    let outputPlayer: FakeMacSpeechAudioOutputPlayer
    let session: RealtimeBrainSessionIdentity
    let target: R81Target
}

@MainActor
private struct R855PermissionControllerStack {
    let controller: AppController
    let runtime: RuntimeCore
    let provider: R81RealtimeProvider
    let authorizationProvider: R855MicrophoneAuthorizationProvider
    let capture: R81AudioCapture
    let deviceMonitor: R81DeviceMonitor
    let outputPlayer: FakeMacSpeechAudioOutputPlayer
}

@MainActor
@main
private struct RealtimeInterruptionEvidenceTests {
    private static var cases = 0
    private static var checks = 0
    private static var acousticOnlyPlaybackClearCount = -1
    private static var microphoneAuthorizationCases = 0
    private static var permissionFailClosedProviderSessions = -1
    private static var stalePermissionProviderSessions = -1
    private static var stalePermissionPrepareCalls = -1
    private static var duplicateStartPermissionRequests = -1
    private static var duplicateStartProviderSessions = -1

    static func testM19ExportContract() async throws {
        let clock = ComprehensiveCClock()
        let source = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: source) }
        for mode in [AppleVPAcousticDataMode.recording, .statsOnly] {
            let stack = D1ControllerStack(clock: { clock.now })
            stack.capture.contentStartOverride = clock.start
            clock.elapsed = 0
            prepareWarmupC(stack, source: source, profile: .four, mode: mode)
            await driveWarmupC(stack, clock: clock, profile: .four)
            let data = try stack.controller.appleVPAcousticTestManifestData()
            let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            expect(manifest["short_window_diagnostics"] is [String: Any],
                   "M19 must export bounded same-content-time Native/final-PCM diagnostics")
            let short = manifest["short_window_diagnostics"] as? [String: Any] ?? [:]
            let windows = short["windows"] as? [[String: Any]] ?? []
            let scope = mode == .recording ? "EXACT_RETAINED_WAV_PACKETS" : "SCORE_PACKETS_NOT_SAVED"
            expect(windows.count == 750 && short["pcm_scope"] as? String == scope,
                   "only 750 retained scoring packets enter the final PCM statistics")
            expect(windows.first?["start_ns"] as? UInt64 == clock.start + 4_000_000_000,
                   "four seconds of warm-up are absent from the final-PCM window series")
            expect(windows.allSatisfy { ($0["pcm"] as? [String: Any])?["samples"] as? UInt64 == 480 },
                   "each actual final packet has 480 samples, not the drained warm-up total")
            if mode == .recording {
                let wav = try stack.controller.appleVPAcousticTestProcessedWAVData()
                expect(wav.count == 720_044 && wav.dropFirst(44).enumerated().allSatisfy {
                    $0.offset % 2 == 0 ? $0.element == 1 : $0.element == 0
                }, "new numerical statistics leave the original synthetic scoring WAV bytes unchanged")
            } else {
                expect(stack.controller.appleVPAcousticTestState.retainedPCMByteCount == 0,
                       "STATS_ONLY keeps zero audio while recording bounded numerical windows")
            }
            expectD1Cleanup(stack)
        }
        print("m19_export_device_access=ZERO")
    }

    static func testM20BatchContract() async throws {
        let batch = UUID().uuidString
        let valid = batch + ":1:3"
        let prefix = AppleVPMacAECBatchRun.argument
        for suffix in [":0:3", ":4:3", ":1:4", ":1:0", ":A:3"] {
            expect(AppleVPMacAECBatchRun(arguments: [prefix + batch + suffix]) == nil,
                   "M20 refuses invalid round and batch bounds")
        }
        expect(AppleVPMacAECBatchRun(arguments: [prefix + valid, prefix + valid]) == nil,
               "duplicate batch arguments cannot authorize a run")
        let missing = D1ControllerStack(macAECArgument: valid)
        expect(!missing.controller.prepareAppleVPAcousticTest(.doubleTalk, comprehensiveC: true),
               "M20 cannot prepare a legacy C scenario")
        expect(!missing.controller.prepareAppleVPAcousticTest(
            .residentOnly, comprehensiveC: true, warmupProfile: .zero, macAECBatch: true
        ), "M20 cannot reduce continuous warm-up")
        expect(!missing.controller.prepareAppleVPAcousticTest(
            .residentOnly, comprehensiveC: true, processingProfile: .agcOff,
            warmupProfile: .four, macAECBatch: true
        ), "M20 cannot change AGC")
        expect(missing.controller.prepareAppleVPAcousticTest(
            .residentOnly, comprehensiveC: true, warmupProfile: .four, macAECBatch: true
        ), "M20 prepares without devices")
        startD1(missing.controller)
        expect(missing.capture.startCount == 0 && missing.player.prepareCount == 0,
               "M20 requires the original ScoreControl pipe before devices")
        await missing.controller.stopAppleVPAcousticTest()
        expect(!missing.controller.appleVPAcousticTestState.canStart,
               "Stop before Capture revokes the pending batch round")
    }

    static func testM20SingleRound(queuedTail: Int = 0) async throws {
        let batch = UUID().uuidString
        let valid = batch + ":1:3"
        let source = try URL(fileURLWithPath: requireEnv("M20_RESIDENT_WAV"))
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let clock = ComprehensiveCClock()
        let stack = D1ControllerStack(
            clock: { clock.now }, scoreControlDescriptor: pipe.fileHandleForWriting.fileDescriptor,
            macAECArgument: valid
        )
        stack.capture.contentStartOverride = clock.start
        expect(stack.controller.prepareAppleVPAcousticTest(
            .residentOnly, comprehensiveC: true, warmupProfile: .four, macAECBatch: true
        ), "M20 uses the original A capture and playback lifecycle")
        expect(stack.controller.selectAppleVPAcousticPlaybackURL(source), "M20 selects its fixed non-private WAV")
        for consent in [(false, true, true), (true, false, true), (true, true, false)] {
            stack.controller.startAppleVPAcousticTest(
                microphoneConsent: consent.0, speakerConsent: consent.1, localCaptureConsent: consent.2
            )
            expect(stack.capture.startCount == 0 && stack.player.startCount == 0,
                   "M20 retains microphone, speaker and local recording consent")
        }
        startD1(stack.controller)
        await driveWarmupC(stack, clock: clock, profile: .four, queuedTail: queuedTail)
        let state = stack.controller.appleVPAcousticTestState
        expect(state.errorCode == nil && state.packetCount == 750 && state.retainedPCMByteCount == 720_000,
               "M20 preserves the 19-second plan and 15-second/720KB scoring cap")
        expect(stack.capture.startCount == 1 && stack.player.startCount == 1,
               "one round starts one existing Capture and one resident playback")
        let manifest = try JSONSerialization.jsonObject(with: stack.controller.appleVPAcousticTestManifestData())
            as? [String: Any] ?? [:]
        expect(manifest["capture_queued_at_seal"] as? Int == 0,
               "M20 must retain every generated scoring packet before ending its FIFO generation")
        let finalDrain = manifest["mac_aec_final_drain"] as? [String: UInt64]
        expect(finalDrain?["pending_before"] == UInt64(queuedTail)
            && finalDrain?["drained"] == UInt64(queuedTail),
            "the final FIFO receipt accounts for actual packets rather than clearing the queue")
        try expectM20Sealed(stack, pipe: pipe, batch: batch)
    }

    private static func expectM20Sealed(_ stack: D1ControllerStack, pipe: Pipe, batch: String) throws {
        let events = try scoreControlEvents(pipe)
        expect(events.count == 2 && events.allSatisfy {
            $0["batch"] as? String == "R5_M20" && $0["batch_id"] as? String == batch
                && $0["round"] as? Int == 1 && $0["limit"] as? Int == 3
                && $0["proxy_requested"] as? Bool == false && $0["source"] == nil
        }, "schedule and STOP bind the same Mac-only batch round")
        expect(!stack.controller.prepareAppleVPAcousticTest(
            .residentOnly, discardPreviousResult: true, comprehensiveC: true, warmupProfile: .four, macAECBatch: true
        ), "one App lifecycle cannot record twice under one batch round")
        let manifest = try JSONSerialization.jsonObject(with: stack.controller.appleVPAcousticTestManifestData())
            as? [String: Any] ?? [:]
        expect((manifest["mac_aec_batch"] as? [String: Any])?["batch_id"] as? String == batch,
               "export retains batch identity")
        try expectWarmupManifest(stack.controller, profile: .four)
        let wav = try stack.controller.appleVPAcousticTestProcessedWAVData()
        expect(wav.count == 720_044 && wav.dropFirst(44).enumerated().allSatisfy {
            $0.offset % 2 == 0 ? $0.element == 1 : $0.element == 0
        }, "M20 does not alter existing synthetic PCM bytes or retain warm-up audio")
        expectD1Cleanup(stack)
    }

    private static func requireEnv(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[key] else { throw CocoaError(.fileReadNoSuchFile) }
        return value
    }

    static func testM20FailureCleanup() async throws {
        let source = try URL(fileURLWithPath: requireEnv("M20_RESIDENT_WAV"))
        let wrong = try d1SyntheticPlayback(packets: 150)
        defer { try? FileManager.default.removeItem(at: wrong) }
        for fault in ["permission", "stop", "fixture"] {
            let pipe = Pipe()
            defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
            let clock = ComprehensiveCClock()
            let stack = D1ControllerStack(
                authorizationState: fault == "permission" ? .denied : .authorized,
                clock: { clock.now }, scoreControlDescriptor: pipe.fileHandleForWriting.fileDescriptor,
                macAECArgument: UUID().uuidString + ":1:3"
            )
            expect(stack.controller.prepareAppleVPAcousticTest(
                .residentOnly, comprehensiveC: true, warmupProfile: .four, macAECBatch: true
            ), "M20 negative control prepares without real devices")
            expect(stack.controller.selectAppleVPAcousticPlaybackURL(fault == "fixture" ? wrong : source),
                   "M20 validates file contents at original Start")
            startD1(stack.controller)
            if fault == "stop" {
                await waitUntil("M20 warm-up running") { stack.controller.appleVPAcousticTestState.phase == .running }
                await stack.controller.stopAppleVPAcousticTest()
            }
            await waitUntil("M20 failure sealed") { stack.controller.appleVPAcousticTestState.phase == .sealed }
            let expected = fault == "permission" ? "microphone_not_authorized"
                : fault == "fixture" ? "invalid_playback_wav" : "cancelled"
            expect(stack.controller.appleVPAcousticTestState.errorCode == expected,
                   "M20 preserves the exact failure and original fail-closed semantics")
            expect(stack.player.startCount == 0 && stack.capture.startCount == (fault == "stop" ? 1 : 0),
                   "rejected consent or fixture never starts devices; Stop closes warm-up without resident playback")
            expectD1Cleanup(stack)
        }
    }

    static func main() async throws {
        if CommandLine.arguments.dropFirst().elementsEqual(["--m20-only"]) {
            try await testM20BatchContract()
            try await testM20SingleRound()
            try await testM20SingleRound(queuedTail: 5)
            try await testWarmupQueuedTail()
            try await testM20FailureCleanup()
            try await testM19ExportContract()
            print("m20_fake_checks=\(checks)")
            print("m20_fake_device_access=ZERO")
            return
        }
        if CommandLine.arguments.dropFirst().elementsEqual(["--m19-only"]) {
            try await testM19ExportContract()
            return
        }
        if CommandLine.arguments.dropFirst().elementsEqual(["--m07-f1-only"]) {
            try await testM03Batch()
            try await testM07Batch()
            try await testM07F1()
            return
        }
        if CommandLine.arguments.dropFirst().elementsEqual(["--m07-only"]) {
            try await testM03Batch()
            try await testM07Batch()
            return
        }
        if CommandLine.arguments.dropFirst().elementsEqual(["--m03-only"]) {
            try await testM03Batch()
            return
        }
        if CommandLine.arguments.dropFirst().elementsEqual(["--d1-only"]) {
            try await testD1Only()
            return
        }
        try await runFixtureTests()
    }

    private static func runFixtureTests() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture path required")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        let primary = try await makeStack(fixture: fixture)
        cases += 1
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(primary.target, sequence: 0)
                ),
            equals: .ignored(.invalidEvidence),
            "zero source sequence is invalid"
        )
        for wrongSession in wrongSessions(for: primary.target.session) {
            expectDecision(
                await primary.runtime
                    .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                        acoustic(
                            R81Target(
                                session: wrongSession,
                                turnID: primary.target.turnID,
                                responseID: primary.target.responseID,
                                contextRevision: primary.target.contextRevision
                            ),
                            sequence: 1
                        )
                    ),
                equals: .ignored(.staleIdentity),
                "wrong session, lease, epoch, or generation is stale"
            )
        }
        let now = monotonicNow()
        let expiredTimestamp = now > 3_000_000_000
            ? now - 3_000_000_000 : 1
        expectDecision(
            await primary.runtime.submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acoustic(
                    primary.target,
                    sequence: 1,
                    timestamp: expiredTimestamp
                )
            ),
            equals: .ignored(.invalidEvidence),
            "expired acoustic evidence is rejected by the fixed freshness fence"
        )
        expectDecision(
            await primary.runtime.submitRealtimeResidentBrainAcousticEvidenceForTesting(
                semantic(primary.target, sequence: 4)
            ),
            equals: .ignored(.invalidEvidence),
            "Host cannot forge Realtime Brain semantic evidence"
        )
        expectDecision(
            await primary.runtime.submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acoustic(primary.target, sequence: 1, confidence: 0)
            ),
            equals: .ignored(.invalidEvidence),
            "zero render-reference confidence cannot confirm interruption"
        )
        let invalidInterruptCount = await primary.provider.interruptCount()
        expect(invalidInterruptCount == 0,
               "invalid identity evidence has no Provider side effect")

        cases += 1
        let primaryAcoustic = acoustic(primary.target, sequence: 2)
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    primaryAcoustic
                ),
            equals: .observed,
            "acoustic evidence alone is observed"
        )
        let acousticOnlyInterruptCount = await primary.provider.interruptCount()
        expect(acousticOnlyInterruptCount == 0,
               "acoustic evidence alone cannot interrupt")
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    primaryAcoustic
                ),
            equals: .ignored(.duplicateEvidence),
            "duplicate acoustic evidence is ignored"
        )
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(primary.target, sequence: 1)
                ),
            equals: .ignored(.staleEvidence),
            "out-of-order acoustic evidence is stale"
        )

        cases += 1
        let wrongTarget = R81Target(
            session: primary.target.session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: primary.target.contextRevision
        )
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(wrongTarget, sequence: 3)
                ),
            equals: .ignored(.staleEvidence),
            "unowned turn and response cannot enter evidence fusion"
        )
        let wrongContext = R81Target(
            session: primary.target.session,
            turnID: primary.target.turnID,
            responseID: primary.target.responseID,
            contextRevision: primary.target.contextRevision + 1
        )
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(wrongContext, sequence: 3)
                ),
            equals: .ignored(.staleEvidence),
            "wrong context revision cannot enter evidence fusion"
        )

        let wrongSemantic = try await makeStack(fixture: fixture)
        cases += 1
        let wrongSemanticTarget = R81Target(
            session: wrongSemantic.target.session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: wrongSemantic.target.contextRevision
        )
        let wrongSemanticEvent = proposalEvent(
            wrongSemanticTarget,
            sequence: 4
        )
        let wrongSemanticResult = try await receiveProposal(
            wrongSemantic,
            event: wrongSemanticEvent
        )
        expect(
            wrongSemanticResult.disposition == .rejectedInvalidEvent,
            "Provider cannot make an invented turn and response active"
        )
        expectDecision(
            wrongSemanticResult.decision,
            equals: .ignored(.staleEvidence),
            "semantic evidence for an unowned turn and response cannot fuse"
        )

        let semanticOnly = try await makeStack(fixture: fixture)
        cases += 1
        let semanticOnlyEvent = proposalEvent(
            semanticOnly.target,
            sequence: 4
        )
        let semanticOnlyDisposition = try await receiveProposal(
            semanticOnly,
            event: semanticOnlyEvent
        )
        expect(
            semanticOnlyDisposition.disposition
                == .accepted(semanticOnlyEvent),
            "Runtime accepts an identity-bound semantic proposal"
        )
        expectDecision(
            semanticOnlyDisposition.decision,
            equals: .observed,
            "semantic evidence alone is observed"
        )
        let semanticOnlyInterruptCount = await semanticOnly.provider
            .interruptCount()
        expect(semanticOnlyInterruptCount == 0,
               "semantic evidence alone cannot interrupt")
        let semanticOnlyLease = semanticOnly.runtime.activeBrainLeaseForTesting()
        expect(
            semanticOnlyLease?.brainLeaseID
                == semanticOnly.target.session.brainLeaseID,
            "semantic evidence alone preserves the active Brain lease"
        )
        await semanticOnly.provider.enqueue(semanticOnlyEvent)
        let duplicateSemantic = try await semanticOnly.runtime
            .receiveRealtimeResidentBrainEvent(
                session: semanticOnly.target.session
            )
        expect(duplicateSemantic == .rejectedDuplicate,
               "duplicate semantic evidence is rejected at the event fence")
        let staleSemanticEvent = proposalEvent(
            semanticOnly.target,
            sequence: 3
        )
        await semanticOnly.provider.enqueue(staleSemanticEvent)
        let staleSemantic = try await semanticOnly.runtime
            .receiveRealtimeResidentBrainEvent(
                session: semanticOnly.target.session
            )
        expect(staleSemantic == .rejectedDuplicate,
               "stale semantic sequence is rejected at the event fence")

        let responseAuthority = try await makeStack(fixture: fixture)
        cases += 1
        let repeatedFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: responseAuthority.target.session,
                turnID: responseAuthority.target.turnID,
                responseID: nil,
                contextRevision: responseAuthority.target.contextRevision
            ),
            sequence: 4,
            kind: .userTranscriptFinal("repeat the same final")
        )
        await responseAuthority.provider.enqueue(repeatedFinal)
        let repeatedFinalDisposition = try await responseAuthority.runtime
            .receiveRealtimeResidentBrainEvent(
                session: responseAuthority.target.session
            )
        expect(
            repeatedFinalDisposition == .accepted(repeatedFinal),
            "a repeated final on the authorized turn remains one-shot"
        )
        let overlapTurn = RealtimeBrainTurnID()
        let overlapFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: responseAuthority.target.session,
                turnID: overlapTurn,
                responseID: nil,
                contextRevision: responseAuthority.target.contextRevision
            ),
            sequence: 5,
            kind: .userTranscriptFinal("overlap is not queued")
        )
        await responseAuthority.provider.enqueue(overlapFinal)
        let overlapDisposition = try await responseAuthority.runtime
            .receiveRealtimeResidentBrainEvent(
                session: responseAuthority.target.session
            )
        expect(
            overlapDisposition == .accepted(overlapFinal),
            "overlapping final is consumed without Provider auto-response"
        )
        let oneShotCommands = await responseAuthority.provider
            .recordedResponseCreateCommands()
        expect(
            oneShotCommands.count == 1,
            "repeated and overlapping finals cannot duplicate response.create"
        )
        let terminal = RealtimeResidentBrainEvent(
            identity: eventIdentity(responseAuthority.target),
            sequence: 6,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "The authorized response is complete."
            ))
        )
        await responseAuthority.provider.enqueue(terminal)
        let terminalDisposition = try await responseAuthority.runtime
            .receiveRealtimeResidentBrainEvent(
                session: responseAuthority.target.session
            )
        expect(
            terminalDisposition == .accepted(terminal),
            "the authorized response reaches its terminal boundary"
        )
        expectRealtimeSuccess(
            await responseAuthority.runtime
                .updateRealtimeResidentBrainContext(
                    RealtimeBrainRuntimeContextUpdate(
                        identity: responseAuthority.target.session,
                        kind: .delta,
                        contextRevision: 3,
                        sections: [RealtimeBrainContextSection(
                            scope: .dynamicSession,
                            content: "overlap drop leaves no orphan turn"
                        )]
                    )
                ),
            "overlap drop leaves no pending turn or transcript"
        )
        expectRealtimeSuccess(
            await responseAuthority.runtime.closeRealtimeResidentBrainSession(
                identity: responseAuthority.target.session
            ),
            "response-authority fixture closes"
        )

        cases += 1
        let primaryProposal = proposalEvent(primary.target, sequence: 4)
        let primaryProposalResult = try await receiveProposal(
            primary,
            event: primaryProposal
        )
        let primaryDecision = confirmedDecision(
            primaryProposalResult.decision,
            message: "matching acoustic and semantic evidence confirms"
        )
        let nextSession = expectRealtimeIdentity(
            await primary.runtime.completeRealtimeResidentBrainInterruption(
                primaryDecision
            ),
            "confirmed interruption settles the Provider transition"
        )
        expect(nextSession.generation == primary.target.session.generation + 1,
               "Runtime confirmation advances generation exactly once")
        expect(
            nextSession.brainLeaseID == primary.target.session.brainLeaseID
                && nextSession.routeEpoch == primary.target.session.routeEpoch
                && nextSession.runtimeSessionID
                    == primary.target.session.runtimeSessionID,
            "confirmed interruption preserves session, lease, and epoch"
        )
        let primaryInterruptCount = await primary.provider.interruptCount()
        expect(primaryInterruptCount == 1,
               "Runtime sends exactly one Provider interrupt")
        let primaryOpenCount = await primary.provider.openCount()
        let primaryCloseCount = await primary.provider.closeCount()
        expect(primaryOpenCount == 1 && primaryCloseCount == 0,
               "confirmed interruption does not reopen or close Provider")
        let primaryInterruptCommand = await primary.provider
            .lastInterruptCommand()
        expect(primaryInterruptCommand?.nextGeneration == nextSession.generation,
               "Provider command carries the Runtime-issued generation")

        cases += 1
        expectDecision(
            await primary.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    primaryAcoustic
                ),
            equals: .ignored(.staleIdentity),
            "old-generation duplicate evidence is stale after confirmation"
        )
        let duplicateInterruptCount = await primary.provider.interruptCount()
        expect(duplicateInterruptCount == 1,
               "duplicate evidence cannot interrupt twice")

        let reverse = try await makeStack(fixture: fixture)
        cases += 1
        let reverseProposal = proposalEvent(reverse.target, sequence: 4)
        let reverseProposalResult = try await receiveProposal(
            reverse,
            event: reverseProposal
        )
        expectDecision(
            reverseProposalResult.decision,
            equals: .observed,
            "semantic-first fusion waits for acoustic evidence"
        )
        let reverseDecision = await reverse.runtime
            .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acoustic(reverse.target, sequence: 2)
            )
        let reverseConfirmation = confirmedDecision(
            reverseDecision,
            message: "fusion is deterministic in either arrival order"
        )
        let reverseNextSession = expectRealtimeIdentity(
            await reverse.runtime.completeRealtimeResidentBrainInterruption(
                reverseConfirmation
            ),
            "reverse-order interruption settles"
        )
        let reverseInterruptCount = await reverse.provider.interruptCount()
        expect(reverseInterruptCount == 1,
               "reverse-order fusion interrupts once")

        let mutationRace = try await makeStack(fixture: fixture)
        cases += 1
        await mutationRace.provider.holdAudio()
        let pendingInput = Task { @MainActor in
            await mutationRace.runtime.appendRealtimeResidentBrainAudio(
                inputFrame(session: mutationRace.target.session)
            )
        }
        await waitUntil("old-generation audio mutation is in flight") {
            await mutationRace.provider.isAudioHeld()
        }
        let mutationProposal = proposalEvent(
            mutationRace.target,
            sequence: 4
        )
        let mutationProposalResult = try await receiveProposal(
            mutationRace,
            event: mutationProposal
        )
        expectDecision(
            mutationProposalResult.decision,
            equals: .observed,
            "in-flight mutation fixture records semantic evidence"
        )
        let mutationDecision = confirmedDecision(
            await mutationRace.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    acoustic(mutationRace.target, sequence: 2)
                ),
            message: "in-flight audio cannot block Runtime confirmation"
        )
        let mutationInterruptCountBeforeDrain = await mutationRace.provider
            .interruptCount()
        expect(
            mutationInterruptCountBeforeDrain == 0,
            "Provider interrupt waits for the retired audio mutation"
        )
        await mutationRace.provider.releaseAudio()
        expectFailure(
            await pendingInput.value,
            equals: .cancelled,
            "retired in-flight audio resolves as cancelled"
        )
        let mutationNextSession = expectRealtimeIdentity(
            await mutationRace.runtime
                .completeRealtimeResidentBrainInterruption(mutationDecision),
            "Provider interrupt runs after the retired mutation drains"
        )
        let mutationInterruptCountAfterDrain = await mutationRace.provider
            .interruptCount()
        expect(
            mutationInterruptCountAfterDrain == 1
                && mutationNextSession.generation
                    == mutationRace.target.session.generation + 1,
            "mutation race produces one interrupt and one generation advance"
        )

        let race = try await makeStack(fixture: fixture)
        let dialogueBefore = try race.sessionStore.loadMostRecentDialogueEntries()
        let narrativeBefore = race.runtime.narrativeMemoryDebugSnapshot()
        let relationshipBefore = race.runtime.currentRelationshipState
        let raceProposal = proposalEvent(race.target, sequence: 4)
        let raceProposalResult = try await receiveProposal(
            race,
            event: raceProposal
        )
        expectDecision(
            raceProposalResult.decision,
            equals: .observed,
            "race fixture records authentic semantic evidence"
        )
        await race.provider.holdInterrupt()
        let duplicateBarrier = R81StartBarrier()
        let duplicateAcoustic = acoustic(race.target, sequence: 2)
        let firstSubmission = Task { @MainActor in
            await duplicateBarrier.wait()
            return await race.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    duplicateAcoustic
                )
        }
        let secondSubmission = Task { @MainActor in
            await duplicateBarrier.wait()
            return await race.runtime
                .submitRealtimeResidentBrainAcousticEvidenceForTesting(
                    duplicateAcoustic
                )
        }
        await waitUntil("concurrent duplicate evidence is ready") {
            await duplicateBarrier.waiterCount() == 2
        }
        await duplicateBarrier.release()
        let concurrentResults = [
            await firstSubmission.value,
            await secondSubmission.value
        ]
        let confirmations: [RealtimeConfirmedInterruption] =
            concurrentResults.compactMap { result in
                guard case .success(.confirmed(let decision)) = result else {
                    return nil
                }
                return decision
            }
        let ignoredDuplicates = concurrentResults.filter { result in
            guard case .success(.ignored(let reason)) = result else {
                return false
            }
            return reason == .staleIdentity || reason == .duplicateEvidence
        }
        expect(
            confirmations.count == 1 && ignoredDuplicates.count == 1,
            "concurrent duplicate evidence yields one Runtime confirmation"
        )
        guard let raceConfirmation = confirmations.first else {
            fatalError("concurrent Runtime confirmation missing")
        }
        await waitUntil("held Provider interrupt") {
            await race.provider.isInterruptHeld()
        }
        expect(raceConfirmation.hostCommand == .clearPlayback,
               "Runtime publishes the Host command while Provider is held")

        cases += 1
        await race.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(race.target),
            sequence: 5,
            kind: .residentAudioDelta(audioDelta(sequence: 2))
        ))
        let pendingDisposition = try await race.runtime
            .receiveRealtimeResidentBrainEvent(
                session: race.target.session
            )
        expect(pendingDisposition == .rejectedStale,
               "old output audio is rejected while Provider interrupt is held")
        let oldInput = await race.runtime.appendRealtimeResidentBrainAudio(
            inputFrame(session: race.target.session)
        )
        expectFailure(oldInput, equals: .invalidIdentity,
                      "old input audio is rejected after Runtime confirmation")
        let rejectedAudioCount = await race.provider.audioCount()
        expect(rejectedAudioCount == 0,
               "rejected old input never reaches Provider")

        cases += 1
        expectDecision(
            await race.runtime.submitRealtimeResidentBrainAcousticEvidenceForTesting(
                acoustic(race.target, sequence: 2)
            ),
            equals: .ignored(.staleIdentity),
            "duplicate evidence during confirmation cannot start a second transition"
        )
        expectDecision(
            await race.runtime.claimRealtimeResidentBrainInterruptionDecision(
                for: raceProposal
            ),
            equals: .ignored(.staleEvidence),
            "a semantic proposal decision can be claimed only once"
        )
        let heldInterruptCount = await race.provider.interruptCount()
        expect(heldInterruptCount == 1,
               "in-flight duplicate evidence sends one Provider interrupt")

        await race.provider.releaseInterrupt()
        let raceNextSession = expectRealtimeIdentity(
            await race.runtime.completeRealtimeResidentBrainInterruption(
                raceConfirmation
            ),
            "held Provider acknowledgement completes confirmation"
        )
        expect(
            raceNextSession.generation
                == race.target.session.generation + 1,
            "concurrent duplicate evidence advances generation exactly once"
        )
        let lateAudio = try await race.runtime
            .receiveRealtimeResidentBrainEvent(session: raceNextSession)
        expect(lateAudio == .rejectedStale,
               "queued old Provider audio stays stale after settlement")

        cases += 1
        let lateIdentity = eventIdentity(race.target)
        await race.provider.enqueue(RealtimeResidentBrainEvent(
            identity: lateIdentity,
            sequence: 6,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "late old response",
                narrativeMemoryCandidates: [
                    RealtimeBrainNarrativeMemoryCandidate(
                        identity: lateIdentity,
                        candidateID: "late-r81-memory",
                        memoryType: "confirmed_plan",
                        summary: "This stale candidate must never be committed.",
                        sourceTurnIDs: [
                            race.target.turnID.rawValue.uuidString.lowercased()
                        ],
                        consentSignal: "explicit_remember_request",
                        sensitivityFlags: [],
                        evidenceSource: "explicit_user_statement",
                        inputClassification: "explicit_memory_worthy",
                        confidence: 0.95
                    )
                ],
                relationshipEvidenceCandidates: [
                    RealtimeBrainRelationshipEvidenceCandidate(
                        identity: lateIdentity,
                        evidenceType: "explicit_familiarity_or_trust",
                        evidenceDetected: true,
                        evidenceSource: "explicit_user_expression",
                        requiresUserConfirmation: false,
                        confidence: 0.95
                    )
                ]
            ))
        ))
        let lateSemantic = try await race.runtime
            .receiveRealtimeResidentBrainEvent(session: raceNextSession)
        expect(lateSemantic == .rejectedStale,
               "late old semantic final is rejected as stale")
        let dialogueAfter = try race.sessionStore.loadMostRecentDialogueEntries()
        expect(dialogueAfter == dialogueBefore,
               "late semantic final writes no dialogue history")
        expect(race.runtime.narrativeMemoryDebugSnapshot() == narrativeBefore,
               "late semantic final writes no Narrative Memory")
        expect(race.runtime.currentRelationshipState == relationshipBefore,
               "late semantic final writes no Relationship state")
        let raceInterruptCount = await race.provider.interruptCount()
        expect(raceInterruptCount == 1,
               "late callbacks cannot trigger another Provider interrupt")

        let memoryControl = try await makeStack(fixture: fixture)
        cases += 1
        let memoryControlIdentity = eventIdentity(memoryControl.target)
        await memoryControl.provider.enqueue(RealtimeResidentBrainEvent(
            identity: memoryControlIdentity,
            sequence: 4,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "Remember the current-generation plan.",
                narrativeMemoryCandidates: [
                    RealtimeBrainNarrativeMemoryCandidate(
                        identity: memoryControlIdentity,
                        candidateID: "r81-current-memory-control",
                        memoryType: "confirmed_plan",
                        summary: "Current-generation memory control.",
                        sourceTurnIDs: [
                            memoryControl.target.turnID.rawValue.uuidString
                                .lowercased()
                        ],
                        consentSignal: "explicit_remember_request",
                        sensitivityFlags: [],
                        evidenceSource: "explicit_user_statement",
                        inputClassification: "explicit_memory_worthy",
                        confidence: 0.95
                    )
                ]
            ))
        ))
        guard case .accepted = try await memoryControl.runtime
                .receiveRealtimeResidentBrainEvent(
                    session: memoryControl.target.session
                ) else {
            fatalError("current-generation memory control was not accepted")
        }
        expect(
            memoryControl.runtime.narrativeMemoryDebugSnapshot()?.records
                .contains { record in
                    record.summary == "Current-generation memory control."
                } == true,
            "current-generation candidate proves the durable Memory observer"
        )
        expectRealtimeSuccess(
            await memoryControl.runtime.closeRealtimeResidentBrainSession(
                identity: memoryControl.target.session
            ),
            "memory control session closes"
        )

        try await testControllerPreparationAndRouteRecovery(fixture: fixture)
        try await testControllerSemanticFirstInterruption(fixture: fixture)
        try await testControllerPlaybackCompletionAndStopRace(fixture: fixture)
        try await testControllerInterruptFailureCanRestart(fixture: fixture)

        cases += 1
        expectRealtimeSuccess(
            await primary.runtime.closeRealtimeResidentBrainSession(
                identity: nextSession
            ),
            "primary session closes"
        )
        expectRealtimeSuccess(
            await semanticOnly.runtime.closeRealtimeResidentBrainSession(
                identity: semanticOnly.target.session
            ),
            "semantic-only session closes"
        )
        expectRealtimeSuccess(
            await wrongSemantic.runtime.closeRealtimeResidentBrainSession(
                identity: wrongSemantic.target.session
            ),
            "wrong-semantic session closes"
        )
        let reverseNext = reverse.runtime.activeBrainLeaseForTesting()
        expect(reverseNext?.brainLeaseID == reverse.target.session.brainLeaseID,
               "reverse fusion keeps the original Brain lease")
        expectRealtimeSuccess(
            await reverse.runtime.closeRealtimeResidentBrainSession(
                identity: reverseNextSession
            ),
            "reverse-order session closes"
        )
        expectRealtimeSuccess(
            await mutationRace.runtime.closeRealtimeResidentBrainSession(
                identity: mutationNextSession
            ),
            "mutation-race session closes"
        )
        expectRealtimeSuccess(
            await race.runtime.closeRealtimeResidentBrainSession(
                identity: raceNextSession
            ),
            "race session closes"
        )

        print("realtime_interruption_evidence_cases=\(cases)")
        print("realtime_interruption_evidence_checks=\(checks)")
        print("r81_acoustic_only_playback_clears=\(acousticOnlyPlaybackClearCount)")
        print("r855r1r1_microphone_authorization_cases=\(microphoneAuthorizationCases)")
        print("r855r1r1_permission_fail_closed_provider_sessions=\(permissionFailClosedProviderSessions)")
        print("r855r1r1_stale_permission_provider_sessions=\(stalePermissionProviderSessions)")
        print("r855r1r1_stale_permission_prepare_calls=\(stalePermissionPrepareCalls)")
        print("r855r1r1_duplicate_start_permission_requests=\(duplicateStartPermissionRequests)")
        print("r855r1r1_duplicate_start_provider_sessions=\(duplicateStartProviderSessions)")
    }

    private static func testControllerMicrophoneAuthorization(
        fixture: Data
    ) async throws {
        try await testAuthorizedMicrophoneStartsWithoutRequest(fixture: fixture)
        try await testFirstRunMicrophoneGrantContinuesStart(fixture: fixture)
        try await testFirstRunMicrophoneDenialFailsClosed(fixture: fixture)
        try await testUnavailableMicrophoneFailsClosed(fixture: fixture)
        try await testPendingMicrophoneRequestCancellation(fixture: fixture)
        try await testDuplicateStartRequestsMicrophoneOnce(fixture: fixture)
    }

    private static func testControllerPreparationAndRouteRecovery(fixture: Data) async throws {
        try await testControllerMicrophoneAuthorization(fixture: fixture)
        try await testStopDuringCapturePreparation(fixture: fixture)
        try await testConsecutiveCascadedTurnsReleaseBackend(fixture: fixture)
    }

    private static func testConsecutiveCascadedTurnsReleaseBackend(fixture: Data) async throws {
        cases += 1
        let asr = T32CascadedASRProvider()
        let tts = T32CascadedTTSProvider()
        let router = ProviderRouter(
            credentialReader: T32CascadedCredentialReader(),
            transport: T32CascadedTextTransport(), asrProvider: asr, ttsProvider: tts
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router, sessionStore: SessionStore()
        )
        let acoustic = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: R81AECBackend())
        expect(acoustic.configure() == .webRTCAEC3, "Cascaded fake retains injected AEC3 provenance")
        let capture = R81AudioCapture(acousticEchoHost: acoustic)
        let host = MacSpeechAudioHost(
            authorizationProvider: R81AuthorizationProvider(), capture: capture,
            deviceMonitor: R81DeviceMonitor()
        )
        let player = FakeMacSpeechAudioOutputPlayer()
        let output = MacSpeechAudioOutputHost(
            player: player, deviceMonitor: FakeMacSpeechOutputDeviceMonitor(),
            configuration: MacSpeechPCMPlaybackConfiguration(
                capacity: 4, lowWatermark: 1, consumerTimeoutNanoseconds: 30_000_000_000,
                startupBufferCount: 1, startupBufferDurationNanoseconds: 0, scheduleAheadCount: 2
            )
        )
        let controller = AppController(
            orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
            speechAudioHost: host, speechAudioOutputHost: output
        )
        try importResidentFixture(fixture, into: controller, name: "t32-cascaded")
        configureCascadedTextDependency(runtime)
        for turn in 1 ... 2 {
            await controller.startFormalSpeechRoute()
            expect(capture.emit(UInt8(turn)), "Cascaded turn \(turn) emits offline input")
            await waitUntil("Cascaded turn \(turn) schedules fake playback") { player.pendingCount == 1 }
            player.completeScheduledChunk()
            await waitUntil("Cascaded turn \(turn) completes and releases prepared resources") {
                controller.formalSpeechRouteDebugSnapshot.phase == .idle
                    && player.closeCount == turn
            }
            await expectCascadedBackendReleased(capture: capture, output: output, runtime: runtime, turn: turn)
        }
        await expectConsecutiveCascadedProviderEvents(asr: asr, tts: tts)
        print("t32a_consecutive_cascaded_turns=2")
        await controller.shutdownSpeechAudioHost()
    }

    private static func expectCascadedBackendReleased(
        capture: R81AudioCapture,
        output: MacSpeechAudioOutputHost,
        runtime: RuntimeCore,
        turn: Int
    ) async {
        expect(capture.processingMode == .webRTCAEC3,
               "Cascaded turn \(turn) keeps its registered AEC3 backend")
        let backendReleased = await output.canSelectAudioProcessingMode()
        expect(backendReleased,
               "completed Cascaded turn \(turn) releases backend ownership")
        expect(!capture.isStarted && runtime.activeBrainLeaseForTesting() == nil,
               "completed Cascaded turn \(turn) releases capture and Runtime lease")
    }

    private static func importResidentFixture(
        _ fixture: Data,
        into controller: AppController,
        name: String
    ) throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).digital_resident")
        try fixture.write(to: fixtureURL, options: .atomic)
        controller.debugImportResident(from: fixtureURL)
        try? FileManager.default.removeItem(at: fixtureURL)
    }

    private static func configureCascadedTextDependency(_ runtime: RuntimeCore) {
        expect(runtime.configureTextProvider(profile: ProviderProfile(
            profileID: "offline-text", providerID: "offline-provider", adapterType: "openai_compatible",
            modelID: "offline-model", baseURL: "https://example.invalid/v1",
            keyRef: "keychain://offline-test/text", enabled: true,
            timeout: 5, stream: false, thinkingMode: "disabled"
        )) == nil, "Cascaded text dependency is explicitly offline")
    }

    private static func expectConsecutiveCascadedProviderEvents(
        asr: T32CascadedASRProvider,
        tts: T32CascadedTTSProvider
    ) async {
        let asrStarts = await asr.startCount()
        let ttsStarts = await tts.startCount()
        let sources = await asr.sources()
        expect(asrStarts == 2 && ttsStarts == 2,
               "two consecutive Cascaded messages complete without a manual repair Stop")
        expect(sources == [.aec3Processed, .aec3Processed],
               "Cascaded input preserves AEC3 source labeling on both offline messages")
    }

    private static func testStopDuringCapturePreparation(fixture: Data) async throws {
        for route in ["realtime", "cascaded", "native"] {
            cases += 1
            let stack = try makePermissionControllerStack(
                fixture: fixture,
                authorization: .authorized,
                holdQueryNumber: route == "realtime" ? 2 : 1
            )
            let start = Task { @MainActor in
                switch route {
                case "realtime":
                    await stack.controller.startRealtimeFullDuplexSpeech()
                case "cascaded":
                    await stack.controller.startFormalSpeechRoute()
                default:
                    await stack.controller.startNativeSpeechInputBridge()
                }
            }
            await waitUntil("\(route) capture preparation reaches its offline barrier") {
                await stack.authorizationProvider.isQueryPending()
            }
            expect(stack.capture.processingMode == (route == "realtime"
                       ? .appleVoiceProcessing : .webRTCAEC3),
            "\(route) selects only its registered backend before preparation")
            await stack.controller.stopSpeechAudioCapture()
            await stack.authorizationProvider.releaseQuery()
            await start.value
            expect(stack.capture.startCount == 0 && !stack.capture.isStarted,
                   "\(route) late preparation cannot restart capture after Stop")
            let openedProviderSessions = await stack.provider.openCount()
            expect(openedProviderSessions == 0,
                   "\(route) late preparation cannot open a Provider after Stop")
            expect(stack.runtime.activeBrainLeaseForTesting() == nil,
                   "\(route) late preparation cannot acquire Runtime ownership")
            expect(!stack.controller.realtimeBrainInputBridgeSnapshot.hasActivePump
                && !stack.controller.speechInputBridgeSnapshot.hasActivePump,
                "\(route) late preparation cannot start either input pump")
        }
        print("t32a_stop_during_capture_preparation_cases=3")
    }

    private static func testAuthorizedMicrophoneStartsWithoutRequest(
        fixture: Data
    ) async throws {
        cases += 1
        microphoneAuthorizationCases += 1
        let stack = try makePermissionControllerStack(
            fixture: fixture,
            authorization: .authorized
        )

        await stack.controller.startRealtimeFullDuplexSpeech()
        await waitUntil("authorized microphone route listens") {
            await stack.provider.openCount() == 1
                && stack.capture.isStarted
                && stack.controller.realtimeFullDuplexSpeechStatus.phase
                    == .listening
        }
        let requestCount = await stack.authorizationProvider.requestCount()
        let queryCount = await stack.authorizationProvider.queryCount()
        expect(stack.capture.processingMode == .appleVoiceProcessing,
               "Realtime requests Apple processing through the mechanical fake seam")
        expect(
            requestCount == 0,
            "authorized microphone does not request permission again"
        )
        expect(
            queryCount == 2,
            "authorized Start refreshes permission before capture preparation"
        )
        expect(
            stack.controller.realtimeBrainInputBridgeSnapshot.hasActivePump
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop,
            "authorized microphone continues through both formal Bridges"
        )
        await stopPermissionRouteAndExpectClean(
            stack,
            label: "authorized microphone"
        )
    }

    private static func testFirstRunMicrophoneGrantContinuesStart(
        fixture: Data
    ) async throws {
        cases += 1
        microphoneAuthorizationCases += 1
        let stack = try makePermissionControllerStack(
            fixture: fixture,
            authorization: .notDetermined,
            requestedAuthorization: .authorized
        )

        await stack.controller.startRealtimeFullDuplexSpeech()
        await waitUntil("first-run microphone grant reaches Listening") {
            await stack.provider.openCount() == 1
                && stack.capture.isStarted
                && stack.controller.realtimeFullDuplexSpeechStatus.phase
                    == .listening
        }
        let requestCount = await stack.authorizationProvider.requestCount()
        let queryCount = await stack.authorizationProvider.queryCount()
        expect(
            requestCount == 1,
            "first-run microphone permission is requested exactly once"
        )
        expect(
            queryCount == 3,
            "granted first-run Start prepares capture only after permission"
        )
        expect(
            stack.runtime.activeBrainLeaseForTesting() != nil,
            "granted first-run permission admits exactly one formal Brain"
        )
        await stopPermissionRouteAndExpectClean(
            stack,
            label: "first-run microphone grant"
        )
    }

    private static func testFirstRunMicrophoneDenialFailsClosed(
        fixture: Data
    ) async throws {
        cases += 1
        microphoneAuthorizationCases += 1
        let stack = try makePermissionControllerStack(
            fixture: fixture,
            authorization: .notDetermined,
            requestedAuthorization: .denied
        )

        await stack.controller.startRealtimeFullDuplexSpeech()
        let requestCount = await stack.authorizationProvider.requestCount()
        let queryCount = await stack.authorizationProvider.queryCount()
        expect(
            requestCount == 1,
            "first-run denial follows one system permission request"
        )
        expect(
            queryCount == 2,
            "first-run denial never reaches capture preparation"
        )
        await expectPermissionStartDidNotReachRoute(
            stack,
            errorCode: "microphone_permission_denied",
            label: "first-run denial"
        )
        permissionFailClosedProviderSessions = await stack.provider.openCount()
    }

    private static func testUnavailableMicrophoneFailsClosed(
        fixture: Data
    ) async throws {
        cases += 1
        microphoneAuthorizationCases += 1
        let cases: [(MicrophoneAuthorizationState, String)] = [
            (.denied, "microphone_permission_denied"),
            (.restricted, "microphone_permission_unavailable"),
            (.failed, "microphone_permission_unavailable")
        ]
        var providerSessions = 0
        for (authorization, errorCode) in cases {
            let stack = try makePermissionControllerStack(
                fixture: fixture,
                authorization: authorization
            )
            await stack.controller.startRealtimeFullDuplexSpeech()
            let requestCount = await stack.authorizationProvider.requestCount()
            let queryCount = await stack.authorizationProvider.queryCount()
            expect(
                requestCount == 0,
                "existing \(authorization.rawValue) permission does not request again"
            )
            expect(
                queryCount == 1,
                "existing \(authorization.rawValue) permission never prepares capture"
            )
            await expectPermissionStartDidNotReachRoute(
                stack,
                errorCode: errorCode,
                label: "existing \(authorization.rawValue) permission"
            )
            providerSessions += await stack.provider.openCount()
        }
        permissionFailClosedProviderSessions += providerSessions
    }

    private static func testPendingMicrophoneRequestCancellation(
        fixture: Data
    ) async throws {
        cases += 1
        microphoneAuthorizationCases += 1
        var providerSessions = 0

        let stopStack = try makePermissionControllerStack(
            fixture: fixture,
            authorization: .notDetermined,
            holdsRequest: true
        )
        let stoppedStart = Task { @MainActor in
            await stopStack.controller.startRealtimeFullDuplexSpeech()
        }
        await waitUntil("permission request waits before Stop") {
            await stopStack.authorizationProvider.isRequestPending()
        }
        await stopStack.controller.stopRealtimeFullDuplexSpeech()
        await stopStack.authorizationProvider.releaseRequest(as: .authorized)
        await stoppedStart.value
        let stopQueryCount = await stopStack.authorizationProvider.queryCount()
        expect(
            stopQueryCount == 2,
            "permission Stop cancellation never prepares capture"
        )
        await expectPermissionStartDidNotReachRoute(
            stopStack,
            errorCode: nil,
            label: "permission Stop cancellation"
        )
        providerSessions += await stopStack.provider.openCount()

        let shutdownStack = try makePermissionControllerStack(
            fixture: fixture,
            authorization: .notDetermined,
            holdsRequest: true
        )
        let shutdownStart = Task { @MainActor in
            await shutdownStack.controller.startRealtimeFullDuplexSpeech()
        }
        await waitUntil("permission request waits before shutdown") {
            await shutdownStack.authorizationProvider.isRequestPending()
        }
        await shutdownStack.controller.shutdownSpeechAudioHost()
        await shutdownStack.authorizationProvider.releaseRequest(as: .authorized)
        await shutdownStart.value
        let shutdownQueryCount =
            await shutdownStack.authorizationProvider.queryCount()
        expect(
            shutdownQueryCount == 2,
            "permission lifecycle cancellation never prepares capture"
        )
        expect(
            !shutdownStack.deviceMonitor.isMonitoring
                && shutdownStack.deviceMonitor.startCount
                    == shutdownStack.deviceMonitor.stopCount,
            "late permission completion cannot resurrect route monitoring after shutdown"
        )
        await expectPermissionStartDidNotReachRoute(
            shutdownStack,
            errorCode: nil,
            label: "permission lifecycle cancellation"
        )
        providerSessions += await shutdownStack.provider.openCount()
        stalePermissionProviderSessions = providerSessions
        stalePermissionPrepareCalls = stopQueryCount == 2
            && shutdownQueryCount == 2 ? 0 : 1
    }

    private static func testDuplicateStartRequestsMicrophoneOnce(
        fixture: Data
    ) async throws {
        cases += 1
        microphoneAuthorizationCases += 1
        let stack = try makePermissionControllerStack(
            fixture: fixture,
            authorization: .notDetermined,
            holdsRequest: true
        )
        let firstStart = Task { @MainActor in
            await stack.controller.startRealtimeFullDuplexSpeech()
        }
        await waitUntil("first Start waits for permission") {
            await stack.authorizationProvider.isRequestPending()
        }
        await stack.controller.startRealtimeFullDuplexSpeech()
        expect(
            stack.controller.realtimeFullDuplexSpeechStatus.phase == .starting,
            "duplicate Start leaves the pending lifecycle in starting"
        )
        await stack.authorizationProvider.releaseRequest(as: .authorized)
        await firstStart.value
        await waitUntil("duplicate Start settles one route") {
            await stack.provider.openCount() == 1
                && stack.capture.isStarted
                && stack.controller.realtimeFullDuplexSpeechStatus.phase
                    == .listening
        }
        duplicateStartPermissionRequests =
            await stack.authorizationProvider.requestCount()
        duplicateStartProviderSessions = await stack.provider.openCount()
        let queryCount = await stack.authorizationProvider.queryCount()
        expect(
            duplicateStartPermissionRequests == 1,
            "duplicate Start requests microphone permission exactly once"
        )
        expect(
            duplicateStartProviderSessions == 1
                && stack.runtime.activeBrainLeaseForTesting() != nil,
            "duplicate Start admits exactly one formal Brain"
        )
        expect(
            queryCount == 3,
            "duplicate Start prepares capture exactly once after permission"
        )
        await stopPermissionRouteAndExpectClean(
            stack,
            label: "duplicate Start"
        )
    }

    private static func expectPermissionStartDidNotReachRoute(
        _ stack: R855PermissionControllerStack,
        errorCode: String?,
        label: String
    ) async {
        let providerOpenCount = await stack.provider.openCount()
        expect(
            providerOpenCount == 0,
            "\(label) creates no Provider Session"
        )
        expect(
            !stack.capture.isStarted
                && stack.capture.startCount == 0
                && !stack.controller.realtimeBrainInputBridgeSnapshot
                    .hasActivePump
                && !stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop
                && stack.outputPlayer.startCount == 0,
            "\(label) starts no Capture, Bridge, or Playback"
        )
        expect(
            stack.runtime.activeBrainLeaseForTesting() == nil,
            "\(label) acquires no Brain lease"
        )
        if let errorCode {
            expect(
                stack.controller.realtimeFullDuplexSpeechStatus.phase == .failed
                    && stack.controller.realtimeFullDuplexSpeechStatus
                        .lastErrorCode == errorCode,
                "\(label) publishes the explicit failed status"
            )
        } else {
            expect(
                stack.controller.realtimeFullDuplexSpeechStatus.phase == .idle,
                "\(label) leaves the cancelled lifecycle idle"
            )
        }
    }

    private static func stopPermissionRouteAndExpectClean(
        _ stack: R855PermissionControllerStack,
        label: String
    ) async {
        await stack.controller.stopRealtimeFullDuplexSpeech()
        let providerCloseCount = await stack.provider.closeCount()
        expect(
            providerCloseCount == 1
                && stack.capture.startCount == 1
                && stack.capture.stopCount == 1
                && !stack.capture.isStarted,
            "\(label) Stop closes Provider and Capture exactly once"
        )
        expect(
            !stack.controller.realtimeBrainInputBridgeSnapshot.hasActivePump
                && !stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop
                && stack.runtime.activeBrainLeaseForTesting() == nil
                && stack.controller.realtimeFullDuplexSpeechStatus.phase == .idle,
            "\(label) Stop leaves Bridges, lease, and lifecycle clean"
        )
    }

    private static func testControllerSemanticFirstInterruption(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeControllerStack(fixture: fixture)
        let receiveCountBeforeProposal = await stack.provider.receiveCount()
        await stack.provider.enqueue(proposalEvent(stack.target, sequence: 4))
        await waitUntil("semantic proposal consumed") {
            await stack.provider.receiveCount() > receiveCountBeforeProposal
        }
        let semanticOnlyInterruptCount = await stack.provider.interruptCount()
        let semanticOnlyOpenCount = await stack.provider.openCount()
        let semanticOnlyCloseCount = await stack.provider.closeCount()
        let semanticOnlyResponseCreateCount = await stack.provider
            .responseCreateCount()
        expect(
            semanticOnlyInterruptCount == 0
                && semanticOnlyResponseCreateCount == 1
                && stack.outputPlayer.clearScheduledPlaybackCount == 0
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .speaking,
            "Brain semantic evidence alone cannot create, clear, or interrupt"
        )
        expect(
            semanticOnlyOpenCount == 1
                && semanticOnlyCloseCount == 0
                && stack.capture.isStarted,
            "semantic evidence alone preserves Provider session and Capture"
        )

        await stack.provider.holdInterrupt()
        await emitNearEndEvidence(stack, marker: 0x31, expectedAudioCount: 3)
        await waitUntil("Host clear before held Provider settlement") {
            await stack.provider.isInterruptHeld()
                && stack.outputPlayer.clearScheduledPlaybackCount == 1
        }
        expect(
            stack.outputPlayer.clearScheduledPlaybackCount == 1,
            "Runtime-issued command pre-clears Playback before Provider ACK"
        )
        await stack.provider.releaseInterrupt()
        await waitUntil("semantic-first interruption rebound") {
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .listening
                && stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == stack.session.generation + 1
                && stack.controller.realtimeBrainInputBridgeSnapshot
                    .hasActivePump
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop
        }
        guard let interruptCommand = await stack.provider
                .lastInterruptCommand() else {
            fatalError("confirmed Host interruption command missing")
        }
        let nextSession = nextSession(
            after: stack.session,
            generation: interruptCommand.nextGeneration
        )
        stack.outputPlayer.completeStoppedChunk()
        expect(stack.capture.emit(0x41),
               "persistent Capture submits the next-generation frame")
        await waitUntil("next-generation input reaches Provider") {
            await stack.provider.audioCount() == 4
        }
        let nextInput = await stack.provider.lastAudioFrame()
        expect(
            nextInput?.identity == nextSession && nextInput?.sequence == 1,
            "next interaction reuses Capture with sequence reset to one"
        )

        let nextTarget = R81Target(
            session: nextSession,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: nextSession,
                turnID: nextTarget.turnID,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 1,
            kind: .userTranscriptFinal("next turn")
        ))
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(nextTarget),
            sequence: 2,
            kind: .residentAudioDelta(audioDelta(sequence: 1))
        ))
        await waitUntil("next-generation response speaking") {
            stack.outputPlayer.startCount == 2
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .speaking
        }
        let responseCreateCount = await stack.provider.responseCreateCount()
        expect(
            responseCreateCount == 2,
            "two accepted user finals receive exactly two Runtime create commands"
        )
        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(nextTarget),
            sequence: 3,
            kind: .residentSpeakingStopped
        ))
        await waitUntil("next response marked draining") {
            stack.controller.speechAudioOutputHostSnapshot.state == .draining
        }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil("next response returns listening") {
            stack.outputPlayer.finishPlaybackCount == 1
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
                && stack.controller.formalSpeechRouteDebugSnapshot.generation
                    == nextSession.generation
        }
        let openCount = await stack.provider.openCount()
        let closeCount = await stack.provider.closeCount()
        expect(openCount == 1 && closeCount == 0 && stack.capture.isStarted,
               "two turns keep one Provider session and persistent Capture")
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func testControllerPlaybackCompletionAndStopRace(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeControllerStack(fixture: fixture)
        await emitNearEndEvidence(stack, marker: 0x51, expectedAudioCount: 3)
        let acousticOnlyInterruptCount = await stack.provider.interruptCount()
        expect(
            acousticOnlyInterruptCount == 0
                && stack.outputPlayer.clearScheduledPlaybackCount == 0
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .speaking,
            "Host acoustic evidence alone cannot clear Playback or interrupt"
        )
        acousticOnlyPlaybackClearCount =
            stack.outputPlayer.clearScheduledPlaybackCount

        await stack.provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(stack.target),
            sequence: 4,
            kind: .residentSpeakingStopped
        ))
        await waitUntil("old response marked draining") {
            stack.controller.speechAudioOutputHostSnapshot.state == .draining
        }
        stack.outputPlayer.completeScheduledChunk()
        await waitUntil("old Playback naturally completed") {
            stack.outputPlayer.finishPlaybackCount == 1
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
        }
        expect(stack.outputPlayer.clearScheduledPlaybackCount == 0,
               "natural completion does not impersonate interruption clear")

        await stack.provider.holdInterrupt()
        await stack.provider.enqueue(proposalEvent(stack.target, sequence: 5))
        await waitUntil("completed Playback still receives confirmed command") {
            await stack.provider.isInterruptHeld()
                && stack.outputPlayer.clearScheduledPlaybackCount == 1
        }
        expect(
            stack.controller.formalSpeechRouteDebugSnapshot.generation
                == stack.session.generation,
            "Host does not bind the next generation before Provider settlement"
        )
        let stopTask = Task { @MainActor in
            await stack.controller.stopSpeechAudioCapture()
        }
        await waitUntil("Stop halts Capture while Provider is held") {
            !stack.capture.isStarted
        }
        await stack.provider.releaseInterrupt()
        await stopTask.value
        let closeCommand = await stack.provider.lastCloseCommand()
        expect(
            closeCommand?.identity.generation == stack.session.generation + 1,
            "Stop closes the Runtime-confirmed next identity, not the stale one"
        )
        let openCount = await stack.provider.openCount()
        let closeCount = await stack.provider.closeCount()
        expect(
            openCount == 1 && closeCount == 1 && !stack.capture.isStarted,
            "Stop during confirmation leaves no Provider lease or Capture leak"
        )
        expect(
            stack.controller.formalSpeechRouteDebugSnapshot.phase == .idle,
            "Stop during confirmation settles the formal Realtime route"
        )
    }

    private static func testControllerInterruptFailureCanRestart(
        fixture: Data
    ) async throws {
        cases += 1
        let stack = try await makeControllerStack(fixture: fixture)
        await stack.provider.failNextInterrupt(.transportFailure)
        await emitNearEndEvidence(stack, marker: 0x61, expectedAudioCount: 3)
        await stack.provider.enqueue(proposalEvent(stack.target, sequence: 4))
        await waitUntil("failed Provider interruption settles Host route") {
            let closeCount = await stack.provider.closeCount()
            return closeCount == 2
                && !stack.capture.isStarted
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .failed
        }
        expect(
            stack.outputPlayer.clearScheduledPlaybackCount == 1,
            "confirmed Host command clears Playback before Provider failure settles"
        )
        let interruptCount = await stack.provider.interruptCount()
        let closeCount = await stack.provider.closeCount()
        let closeGenerations = await stack.provider.closeGenerations()
        expect(
            interruptCount == 1
                && closeCount == 2
                && closeGenerations.sorted() == [
                    stack.session.generation,
                    stack.session.generation + 1
                ]
                && stack.runtime.activeBrainLeaseForTesting() == nil,
            "failed transition closes old and pending identities once each"
        )

        await stack.controller.startRealtimeResidentBrainRoute()
        await waitUntil("formal Realtime route restarts after Provider failure") {
            await stack.provider.openCount() == 2
                && stack.capture.isStarted
                && stack.controller.formalSpeechRouteDebugSnapshot.phase
                    == .listening
        }
        expect(
            stack.controller.realtimeBrainInputBridgeSnapshot.hasActivePump
                && stack.controller.realtimeBrainOutputBridgeSnapshot
                    .hasActiveReceiveLoop,
            "failed transition leaves no closed binding that blocks restart"
        )
        await stack.controller.stopSpeechAudioCapture()
    }

    private static func makePermissionControllerStack(
        fixture: Data,
        authorization: MicrophoneAuthorizationState,
        requestedAuthorization: MicrophoneAuthorizationState = .authorized,
        holdsRequest: Bool = false,
        holdQueryNumber: Int? = nil
    ) throws -> R855PermissionControllerStack {
        let provider = R81RealtimeProvider()
        let router = ProviderRouter(
            credentialReader: R81CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        let authorizationProvider = R855MicrophoneAuthorizationProvider(
            authorization: authorization,
            requestedAuthorization: requestedAuthorization,
            holdsRequest: holdsRequest,
            holdQueryNumber: holdQueryNumber
        )
        let acousticEchoHost = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: R81AECBackend()
        )
        expect(
            acousticEchoHost.configure() == .webRTCAEC3,
            "permission test configures the formal AEC Host"
        )
        let capture = R81AudioCapture(acousticEchoHost: acousticEchoHost)
        let deviceMonitor = R81DeviceMonitor()
        let audioHost = MacSpeechAudioHost(
            authorizationProvider: authorizationProvider,
            capture: capture,
            deviceMonitor: deviceMonitor
        )
        let outputPlayer = FakeMacSpeechAudioOutputPlayer()
        let outputHost = MacSpeechAudioOutputHost(
            player: outputPlayer,
            deviceMonitor: FakeMacSpeechOutputDeviceMonitor(),
            configuration: MacSpeechPCMPlaybackConfiguration(
                capacity: 4,
                lowWatermark: 1,
                consumerTimeoutNanoseconds: 2_000_000_000,
                startupBufferCount: 1,
                startupBufferDurationNanoseconds: 0,
                scheduleAheadCount: 2
            )
        )
        let controller = AppController(
            orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
            speechAudioHost: audioHost,
            speechAudioOutputHost: outputHost
        )
        try importResidentFixture(fixture, into: controller, name: "r855-permission")
        expect(
            controller.isResidentTextInputAvailable,
            "permission test loads the formal resident fixture"
        )
        return R855PermissionControllerStack(
            controller: controller,
            runtime: runtime,
            provider: provider,
            authorizationProvider: authorizationProvider,
            capture: capture,
            deviceMonitor: deviceMonitor,
            outputPlayer: outputPlayer
        )
    }

    private static func makeControllerStack(
        fixture: Data
    ) async throws -> R81ControllerStack {
        let provider = R81RealtimeProvider()
        await provider.enableInterruptReceiveWake()
        let router = ProviderRouter(
            credentialReader: R81CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        let aecBackend = R81AECBackend()
        let acousticEchoHost = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: aecBackend
        )
        expect(acousticEchoHost.configure() == .webRTCAEC3,
               "formal Realtime Host uses the configured AEC evidence source")
        let capture = R81AudioCapture(acousticEchoHost: acousticEchoHost)
        let audioHost = MacSpeechAudioHost(
            authorizationProvider: R81AuthorizationProvider(),
            capture: capture,
            deviceMonitor: R81DeviceMonitor()
        )
        let outputPlayer = FakeMacSpeechAudioOutputPlayer()
        let outputHost = MacSpeechAudioOutputHost(
            player: outputPlayer,
            deviceMonitor: FakeMacSpeechOutputDeviceMonitor(),
            configuration: MacSpeechPCMPlaybackConfiguration(
                capacity: 4,
                lowWatermark: 1,
                consumerTimeoutNanoseconds: 2_000_000_000,
                startupBufferCount: 1,
                startupBufferDurationNanoseconds: 0,
                scheduleAheadCount: 2
            )
        )
        let controller = AppController(
            orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
            speechAudioHost: audioHost,
            speechAudioOutputHost: outputHost
        )
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "r81-controller-\(UUID().uuidString).digital_resident"
            )
        try fixture.write(to: fixtureURL, options: .atomic)
        controller.debugImportResident(from: fixtureURL)
        try? FileManager.default.removeItem(at: fixtureURL)
        expect(controller.isResidentTextInputAvailable,
               "AppController loads the R8.1 fixture resident")

        await controller.startRealtimeResidentBrainRoute()
        await waitUntil("formal Realtime route listening") {
            let hasSession = await provider.latestSession() != nil
            return controller.formalSpeechRouteDebugSnapshot.phase == .listening
                && hasSession
        }
        guard let session = await provider.latestSession() else {
            fatalError("formal Realtime session missing")
        }
        let target = R81Target(
            session: session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let userFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: target.turnID,
                responseID: nil,
                contextRevision: 1
            ),
            sequence: 2,
            kind: .userTranscriptFinal("interrupt now")
        )
        await provider.enqueue(userFinal)
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(target),
            sequence: 3,
            kind: .residentAudioDelta(audioDelta(sequence: 1))
        ))
        await waitUntil("resident playback speaking") {
            outputPlayer.startCount == 1
                && controller.formalSpeechRouteDebugSnapshot.phase == .speaking
        }
        let responseCreateCount = await provider.responseCreateCount()
        expect(
            responseCreateCount == 1,
            "the accepted user final receives one Runtime response-create command"
        )
        expect(outputPlayer.clearScheduledPlaybackCount == 0,
               "resident Playback is intact before evidence fusion")
        return R81ControllerStack(
            controller: controller,
            runtime: runtime,
            provider: provider,
            aecBackend: aecBackend,
            acousticEchoHost: acousticEchoHost,
            capture: capture,
            outputPlayer: outputPlayer,
            session: session,
            target: target
        )
    }

    private static func emitNearEndEvidence(
        _ stack: R81ControllerStack,
        marker: UInt8,
        expectedAudioCount: Int
    ) async {
        stack.acousticEchoHost.playbackStarted()
        let render = signal(seed: 2, amplitude: 0.3)
        let nearEnd = signal(seed: 3, amplitude: 0.25)
        let baseTimestamp = monotonicNow() - 150_000_000
        // Acquire the real timing lock from cancelled far-end before overlap.
        stack.aecBackend.setCaptureOutput(Array(repeating: 0, count: render.count))
        for index in 0 ..< 3 {
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds: baseTimestamp + UInt64(index * 10_000_000)
            )
            _ = stack.acousticEchoHost.processCapture(
                render,
                hostTimeNanoseconds: baseTimestamp + 80_000_000
                    + UInt64(index * 10_000_000)
            )
        }
        expect(stack.acousticEchoHost.snapshot().sourceAlignmentLocked,
               "far-end warm-up acquires production timing alignment")
        stack.aecBackend.setCaptureOutput(nearEnd)
        for index in 0 ..< 3 {
            stack.acousticEchoHost.processRender(
                render,
                hostTimeNanoseconds:
                    baseTimestamp + 30_000_000 + UInt64(index * 10_000_000)
            )
            _ = stack.acousticEchoHost.processCapture(
                zip(render, nearEnd).map(+),
                hostTimeNanoseconds:
                    baseTimestamp + 110_000_000
                        + UInt64(index * 10_000_000)
            )
            try? await Task.sleep(for: .milliseconds(12))
            expect(
                stack.capture.emit(marker &+ UInt8(index)),
                "identity-bound near-end frame enters the Realtime pump"
            )
            await waitUntil("acoustic frame reaches Provider") {
                await stack.provider.audioCount()
                    == expectedAudioCount - 2 + index
            }
        }
        let acoustic = stack.acousticEchoHost.snapshot()
        expect(
            acoustic.sourceAlignmentLocked && acoustic.sourceGateOpen,
            "valid aligned near-end evidence opens the existing source gate"
        )
        for _ in 0 ..< 400 {
            await stack.controller.refreshMicrophoneAuthorization()
            if stack.controller.realtimeBrainInputBridgeSnapshot
                .acousticEvidenceCount == 1 {
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        await stack.controller.refreshMicrophoneAuthorization()
        let bridgeSnapshot = stack.controller
            .realtimeBrainInputBridgeSnapshot
        let eligibilityDisposition =
            bridgeSnapshot.lastAcousticEligibilityDisposition ?? "nil"
        let forwardDisposition =
            bridgeSnapshot.lastAcousticEvidenceForwardDisposition ?? "nil"
        expect(
            bridgeSnapshot.acousticEvidenceCount == 1,
            "Host forwards one source-gate acoustic evidence edge; evidence=\(bridgeSnapshot.acousticEvidenceCount), candidates=\(bridgeSnapshot.acousticEligibilityCandidateCount), rearmed=\(bridgeSnapshot.acousticEligibilityRearmedCount), stale=\(bridgeSnapshot.acousticEvidenceStaleFenceCount), eligibility=\(eligibilityDisposition), forward=\(forwardDisposition), sends=\(bridgeSnapshot.sendOperationCount), forwarded=\(bridgeSnapshot.forwardedFrameCount)"
        )
    }

    private static func nextSession(
        after session: RealtimeBrainSessionIdentity,
        generation: UInt64
    ) -> RealtimeBrainSessionIdentity {
        RealtimeBrainSessionIdentity(
            residentID: session.residentID,
            runtimeSessionID: session.runtimeSessionID,
            brainLeaseID: session.brainLeaseID,
            routeEpoch: session.routeEpoch,
            generation: generation
        )
    }

    private static func signal(
        seed: UInt32,
        amplitude: Float
    ) -> [Float] {
        var state = seed
        return (0 ..< MacSpeechAcousticEchoHost.frameSampleCount).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit = Float(state >> 8) / Float(0x00FF_FFFF)
            return (unit * 2 - 1) * amplitude
        }
    }

    private static func makeStack(fixture: Data) async throws -> R81Stack {
        let provider = R81RealtimeProvider()
        let router = ProviderRouter(
            credentialReader: R81CredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let sessionStore = SessionStore()
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: sessionStore
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "interruption evidence fixture resident loads")
        guard case .success(let session) =
                await runtime.startRealtimeResidentBrainSession() else {
            fatalError("Realtime session did not start")
        }
        guard case .accepted(let ready) = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session),
              ready.kind == .sessionReady else {
            fatalError("Realtime session did not become ready")
        }
        let target = R81Target(
            session: session,
            turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(),
            contextRevision: 1
        )
        let userFinal = RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(
                session: session,
                turnID: target.turnID,
                responseID: nil,
                contextRevision: target.contextRevision
            ),
            sequence: 2,
            kind: .userTranscriptFinal("interrupt the resident")
        )
        await provider.enqueue(userFinal)
        guard case .accepted = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session) else {
            fatalError("user turn did not activate")
        }
        let responseCreateCommands = await provider
            .recordedResponseCreateCommands()
        // A fresh command has a different attempt; compare the authorized source binding.
        expect(
            responseCreateCommands.count == 1
                && responseCreateCommands.first?.identity == userFinal.identity
                && responseCreateCommands.first?.sourceEventSequence == userFinal.sequence,
            "Runtime response authorization binds the exact final identity and sequence"
        )
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: eventIdentity(target),
            sequence: 3,
            kind: .residentAudioDelta(audioDelta(sequence: 1))
        ))
        guard case .accepted = try await runtime
                .receiveRealtimeResidentBrainEvent(session: session) else {
            fatalError("resident response did not activate")
        }
        return R81Stack(
            runtime: runtime,
            provider: provider,
            sessionStore: sessionStore,
            target: target
        )
    }

    private static func acoustic(
        _ target: R81Target,
        sequence: UInt64,
        timestamp: UInt64? = nil,
        confidence: Double = 1
    ) -> RealtimeInterruptionEvidence {
        RealtimeInterruptionEvidence(
            identity: RealtimeInterruptionEvidenceIdentity(
                session: target.session,
                turnID: target.turnID,
                responseID: target.responseID,
                contextRevision: target.contextRevision,
                sequence: sequence,
                timestampNanoseconds: timestamp ?? monotonicNow()
            ),
            source: .acousticHost(RealtimeInterruptionAcousticFacts(
                sourceGateEpoch: 1,
                nearEndDetected: true,
                farEndActive: true,
                sourceGateOpen: true,
                renderReferenceConfidence: confidence,
                routeStable: true,
                inputDeviceAvailable: true,
                outputDeviceAvailable: true
            ))
        )
    }

    private static func semantic(
        _ target: R81Target,
        sequence: UInt64,
        timestamp: UInt64? = nil
    ) -> RealtimeInterruptionEvidence {
        RealtimeInterruptionEvidence(
            identity: RealtimeInterruptionEvidenceIdentity(
                session: target.session,
                turnID: target.turnID,
                responseID: target.responseID,
                contextRevision: target.contextRevision,
                sequence: sequence,
                timestampNanoseconds: timestamp ?? monotonicNow()
            ),
            source: .realtimeBrain(RealtimeInterruptionSemanticFacts(
                reason: "user_speech_started_during_resident_response"
            ))
        )
    }

    private static func proposalEvent(
        _ target: R81Target,
        sequence: UInt64
    ) -> RealtimeResidentBrainEvent {
        let identity = eventIdentity(target)
        return RealtimeResidentBrainEvent(
            identity: identity,
            sequence: sequence,
            kind: .interruptionProposed(RealtimeBrainInterruptionProposal(
                identity: identity,
                reason: "user_speech_started_during_resident_response"
            ))
        )
    }

    private static func receiveProposal(
        _ stack: R81Stack,
        event: RealtimeResidentBrainEvent
    ) async throws -> (
        disposition: RealtimeBrainEventDisposition,
        decision: Result<
            RealtimeInterruptionDecision,
            RealtimeResidentBrainError
        >
    ) {
        await stack.provider.enqueue(event)
        let disposition = try await stack.runtime
            .receiveRealtimeResidentBrainEvent(session: stack.target.session)
        let decision = await stack.runtime
            .claimRealtimeResidentBrainInterruptionDecision(for: event)
        return (disposition, decision)
    }

    private static func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func wrongSessions(
        for session: RealtimeBrainSessionIdentity
    ) -> [RealtimeBrainSessionIdentity] {
        [
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID + "-wrong",
                brainLeaseID: session.brainLeaseID,
                routeEpoch: session.routeEpoch,
                generation: session.generation
            ),
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID,
                brainLeaseID: UUID(),
                routeEpoch: session.routeEpoch,
                generation: session.generation
            ),
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID,
                brainLeaseID: session.brainLeaseID,
                routeEpoch: session.routeEpoch + 1,
                generation: session.generation
            ),
            RealtimeBrainSessionIdentity(
                residentID: session.residentID,
                runtimeSessionID: session.runtimeSessionID,
                brainLeaseID: session.brainLeaseID,
                routeEpoch: session.routeEpoch,
                generation: session.generation + 1
            )
        ]
    }

    private static func eventIdentity(
        _ target: R81Target
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: target.session,
            turnID: target.turnID,
            responseID: target.responseID,
            contextRevision: target.contextRevision
        )
    }

    private static func audioDelta(
        sequence: UInt64
    ) -> RealtimeBrainAudioDelta {
        RealtimeBrainAudioDelta(
            sequence: sequence,
            timestampNanoseconds: sequence * 20_000_000,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .providerGenerated,
            bytes: Data(repeating: 1, count: 960)
        )
    }

    private static func inputFrame(
        session: RealtimeBrainSessionIdentity
    ) -> RealtimeBrainAudioFrame {
        RealtimeBrainAudioFrame(
            identity: session,
            sequence: 1,
            timestampNanoseconds: 1,
            format: RealtimeBrainAudioFormat(
                encoding: .pcm16LittleEndian,
                sampleRate: 24_000,
                channelCount: 1
            ),
            provenance: .acousticEchoProcessed,
            bytes: Data(repeating: 1, count: 960)
        )
    }

    private static func confirmedDecision(
        _ result: Result<
            RealtimeInterruptionDecision,
            RealtimeResidentBrainError
        >,
        message: String
    ) -> RealtimeConfirmedInterruption {
        guard case .success(.confirmed(let decision)) = result else {
            expect(false, message)
            fatalError(message)
        }
        expect(decision.hostCommand == .clearPlayback, message)
        return decision
    }

    private static func expectRealtimeIdentity(
        _ result: Result<
            RealtimeBrainSessionIdentity,
            RealtimeResidentBrainError
        >,
        _ message: String
    ) -> RealtimeBrainSessionIdentity {
        guard case .success(let identity) = result else {
            expect(false, message)
            fatalError(message)
        }
        expect(true, message)
        return identity
    }

    private static func expectDecision(
        _ result: Result<
            RealtimeInterruptionDecision,
            RealtimeResidentBrainError
        >,
        equals expected: RealtimeInterruptionDecision,
        _ message: String
    ) {
        switch result {
        case .success(let decision):
            expect(decision == expected, message)
        case .failure:
            expect(false, message)
        }
    }

    private static func expectFailure<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        equals expected: RealtimeResidentBrainError,
        _ message: String
    ) {
        switch result {
        case .failure(let error): expect(error == expected, message)
        case .success: expect(false, message)
        }
    }

    private static func expectRealtimeSuccess<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        _ message: String
    ) {
        switch result {
        case .success: expect(true, message)
        case .failure: expect(false, message)
        }
    }

    private static func waitUntil(
        _ label: String,
        condition: @escaping () async -> Bool
    ) async {
        for _ in 0 ..< 400 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        fatalError("timed out: \(label)")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        checks += 1
        if !condition() { fatalError("FAILED: \(message)") }
    }

}
