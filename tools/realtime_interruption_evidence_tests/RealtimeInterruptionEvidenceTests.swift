@preconcurrency import AVFoundation
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
        print("d1_export_synthetic_cleanup=PASS")
        print("d1_dependency_factory_calls=0")
        print("d1_initialization_microphone_queries=0")
        print("d1_initialization_microphone_requests=0")
        print("d1_initialization_capture_starts=0")
        print("d1_initialization_playback_starts=0")
        print("d1_only_cases=\(cases)")
        print("d1_only_checks=\(checks)")
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

    init(failsStart: Bool = false) {
        self.failsStart = failsStart
    }

    func selectProcessingMode(_ mode: MacSpeechAudioProcessingMode) throws {
        guard mode == .appleVoiceProcessing else { throw MacSpeechAudioCaptureError.voiceProcessingUnavailable }
    }

    func voiceProcessingSnapshot() -> MacSpeechVoiceProcessingSnapshot? {
        let format = MacSpeechNativeInputFormat(sampleRate: 48000, channelCount: 1)
        return MacSpeechVoiceProcessingSnapshot(
            mode: .appleVoiceProcessing, configurationID: 1, inputEnabled: true, outputEnabled: true,
            bypassed: false, inputMuted: false, automaticGainControlEnabled: true,
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
            contentStart = DispatchTime.now().uptimeNanoseconds
            sampleCursor = 0
        }
        return MacSpeechNativeInputFormat(sampleRate: 48000, channelCount: 1)
    }

    func stop() {
        lock.withLock {
            guard active else { return }
            active = false
            stops += 1
            frameBuffer = nil
        }
    }

    func armNativeVoiceDebug(runID: UUID, generation: UInt64) -> Bool {
        lock.withLock {
            var value = MacSpeechNativeVoiceDebugStats(runID: runID, generation: generation)
            value.bind(configurationID: 1, voiceProcessing: voiceProcessingSnapshot())
            stats = value
            return true
        }
    }

    func nativeVoiceDebugSnapshot(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
        lock.withLock { stats?.snapshot.runID == runID ? stats?.snapshot : nil }
    }

    func sealNativeVoiceDebug(runID: UUID) -> MacSpeechNativeVoiceDebugSnapshot? {
        lock.withLock {
            guard stats?.snapshot.runID == runID else { return nil }
            stats?.seal()
            return stats?.snapshot
        }
    }

    func clearNativeVoiceDebug(runID: UUID) {
        lock.withLock {
            if stats?.snapshot.runID == runID {
                stats = nil
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
        holdQueryNumber: Int? = nil,
        failsCaptureStart: Bool = false,
        byteLimit: Int = 720_000,
        outputConfiguration: MacSpeechPCMPlaybackConfiguration = .standard
    ) {
        let dependencies = D1NormalDependenciesSpy()
        let authorization = R855MicrophoneAuthorizationProvider(
            authorization: authorizationState, holdQueryNumber: holdQueryNumber
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
            acousticTestArguments: ["Aftelle", "--apple-vp-acoustic-test"],
            speechAudioHost: host, speechAudioOutputHost: output, speechAudioCapture: capture,
            acousticTestDurationNanoseconds: 15_000_000_000, acousticTestByteLimit: byteLimit,
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

    static func main() async throws {
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
