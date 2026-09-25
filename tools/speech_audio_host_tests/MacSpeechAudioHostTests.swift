@preconcurrency import AVFoundation
import Foundation

private enum FakeAuthorizationError: Error {
    case unavailable
}

private actor FakeMicrophoneAuthorizationProvider:
    MicrophoneAuthorizationProviding
{
    private var authorization: MicrophoneAuthorizationState
    private let requestedAuthorization: MicrophoneAuthorizationState
    private let queryFails: Bool
    private let requestFails: Bool
    private(set) var queryCount = 0
    private(set) var requestCount = 0

    init(
        authorization: MicrophoneAuthorizationState,
        requestedAuthorization: MicrophoneAuthorizationState = .authorized,
        queryFails: Bool = false,
        requestFails: Bool = false
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
        self.queryFails = queryFails
        self.requestFails = requestFails
    }

    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        queryCount += 1
        if queryFails { throw FakeAuthorizationError.unavailable }
        return authorization
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        requestCount += 1
        if requestFails { throw FakeAuthorizationError.unavailable }
        authorization = requestedAuthorization
        return authorization
    }
}

private final class FakeMacSpeechAudioCapture:
    MacSpeechAudioCapturing, @unchecked Sendable
{
    private let lock = NSLock()
    private let startError: MacSpeechAudioCaptureError?
    private let processingMode: MacSpeechAudioProcessingMode?
    private var frameBuffer: MacSpeechAudioFrameBuffer?
    private var generation: UInt64?
    private var started = false
    private var starts = 0
    private var stops = 0
    private var routeResets = 0
    private var routeRebuildCompletions = 0
    private var routeRebuildCompletionsWhileStarted = 0
    private var acousticDiagnosticResets = 0

    init(
        startError: MacSpeechAudioCaptureError? = nil,
        processingMode: MacSpeechAudioProcessingMode? = nil
    ) {
        self.startError = startError
        self.processingMode = processingMode
    }

    func start(
        generation: UInt64,
        frameBuffer: MacSpeechAudioFrameBuffer
    ) throws -> MacSpeechNativeInputFormat {
        if let startError { throw startError }
        return lock.withLock {
            guard !started else {
                return MacSpeechNativeInputFormat(
                    sampleRate: 48_000,
                    channelCount: 2
                )
            }
            started = true
            starts += 1
            self.generation = generation
            self.frameBuffer = frameBuffer
            return MacSpeechNativeInputFormat(
                sampleRate: 48_000,
                channelCount: 2
            )
        }
    }

    func stop() {
        lock.withLock {
            guard started else { return }
            started = false
            stops += 1
        }
    }

    func routeWillRebuild() {
        lock.withLock { routeResets += 1 }
    }

    func routeDidRebuild() {
        lock.withLock {
            routeRebuildCompletions += 1
            if started { routeRebuildCompletionsWhileStarted += 1 }
        }
    }

    func currentAudioProcessingMode() -> MacSpeechAudioProcessingMode? {
        processingMode
    }

    func resetAcousticEchoDiagnostics() {
        lock.withLock { acousticDiagnosticResets += 1 }
    }

    @discardableResult
    func emit(
        bytes: Data = Data([0, 0]),
        activity: Float = 0.25,
        timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Bool {
        let target = lock.withLock { (frameBuffer, generation) }
        guard let frameBuffer = target.0, let generation = target.1 else {
            return false
        }
        return frameBuffer.append(
            pcm16Bytes: bytes,
            activity: activity,
            generation: generation,
            timestamp: timestamp
        )
    }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    var routeResetCount: Int { lock.withLock { routeResets } }
    var routeRebuildCompletionCount: Int {
        lock.withLock { routeRebuildCompletions }
    }
    var routeRebuildCompletionWhileStartedCount: Int {
        lock.withLock { routeRebuildCompletionsWhileStarted }
    }
    var acousticDiagnosticResetCount: Int {
        lock.withLock { acousticDiagnosticResets }
    }
    var isStarted: Bool { lock.withLock { started } }
}

private struct DefaultCaptureLeaseAudioFrameSource:
    MacSpeechAudioFrameSourcing {
    func activeCaptureGeneration() async -> UInt64? { nil }

    func isCaptureGenerationActive(_ generation: UInt64) async -> Bool {
        false
    }

    func drainFrames(maxCount: Int) async -> [MacSpeechAudioFrame] { [] }
}

private final class FakeMacSpeechDeviceMonitor:
    MacSpeechDeviceRouteMonitoring, @unchecked Sendable
{
    private let lock = NSLock()
    private let monitoringStartsSuccessfully: Bool
    private var route: MacSpeechDeviceRoute
    private var routeRevision: UInt64 = 0
    private var onChange: (@Sendable () -> Void)?
    private var starts = 0

    init(
        route: MacSpeechDeviceRoute,
        monitoringStartsSuccessfully: Bool = true
    ) {
        self.route = route
        self.monitoringStartsSuccessfully = monitoringStartsSuccessfully
    }

    func currentRoute() -> MacSpeechDeviceRoute {
        lock.withLock { route }
    }

    func currentRouteRevision() -> UInt64 {
        lock.withLock { routeRevision }
    }

    func hasActiveRouteChangeMonitoring() -> Bool {
        lock.withLock { onChange != nil }
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        lock.withLock {
            guard self.onChange == nil else { return }
            starts += 1
            guard monitoringStartsSuccessfully else { return }
            self.onChange = onChange
        }
    }

    func stop() {
        lock.withLock { onChange = nil }
    }

    func setRoute(_ route: MacSpeechDeviceRoute) {
        lock.withLock {
            self.route = route
            routeRevision &+= 1
        }
    }

    func notifyRouteChange(_ route: MacSpeechDeviceRoute) {
        let callback = lock.withLock { () -> (@Sendable () -> Void)? in
            self.route = route
            routeRevision &+= 1
            return onChange
        }
        callback?()
    }

    var startCount: Int { lock.withLock { starts } }
}

@MainActor
@main
private struct MacSpeechAudioHostTests {
    private static var checks = 0

    private static let inputA = MacSpeechAudioDevice(
        identifier: "input-a",
        name: "Built-in Microphone",
        isAvailable: true,
        hasExactDeviceUID: true
    )
    private static let inputB = MacSpeechAudioDevice(
        identifier: "input-b",
        name: "AirPods Pro Microphone",
        isAvailable: true,
        hasExactDeviceUID: true
    )
    private static let outputA = MacSpeechAudioDevice(
        identifier: "output-a",
        name: "Built-in Output",
        isAvailable: true,
        hasExactDeviceUID: true
    )
    private static let outputB = MacSpeechAudioDevice(
        identifier: "output-b",
        name: "AirPods Pro",
        isAvailable: true,
        hasExactDeviceUID: true
    )

    static func main() async {
        await testInitialStateDoesNotQueryOrRequest()
        await testAuthorizationMappings()
        await testExplicitRequestAndRepeatSafety()
        await testRequestFailure()
        await testQueryFailure()
        await testUnauthorizedCaptureIsRejected()
        await testVoiceProcessingUnavailableFailsClosed()
        await testStartStopRestartAreIdempotent()
        await testPreparedCaptureDefersProducerAndResetsGenerationStats()
        await testTier2RouteCaptureLeaseDefaultsToNil()
        await testTier2RouteCaptureLeaseRequiresExactBindings()
        await testTier2RouteCaptureLeaseTracksCaptureLifecycle()
        await testTier2RouteCaptureLeaseRequiresActiveMonitoring()
        await testTier2RouteCaptureLeaseRejectsBindingFlips()
        await testTier2RouteCaptureLeaseRejectsFoldedRouteChanges()
        await testNotificationDrivenRouteInvalidation()
        testPCM16Encoding()
        testExactTwentyMillisecondPacketization()
        do {
            try testStereoConversionToFrozenMonoFormat()
        } catch {
            fatalError("FAILED: 48 kHz stereo conversion: \(error)")
        }
        do {
            try testVoiceProcessingThreeChannelConversionIsAudible()
        } catch {
            fatalError("FAILED: 16 kHz voice-processing conversion: \(error)")
        }
        testBoundedFrameBuffer()
        await testHostFrameDiagnosticsAndStaleRejection()
        testAcousticDiagnosticsPassThrough()
        await testInputOutputAndCombinedRouteRebuilds()
        await testDeviceChangesStopSafelyWithoutAutomaticRestart()
        print("speech_audio_host_checks=\(checks)")
    }

    private static func makeHost(
        authorization: MicrophoneAuthorizationState,
        route: MacSpeechDeviceRoute = availableRoute,
        frameCapacity: Int = MacSpeechAudioInputFormat.frameCapacity,
        processingMode: MacSpeechAudioProcessingMode? = nil,
        tier2RouteEnrollment: MacSpeechTier2RouteEnrollment? = nil,
        monitoringStartsSuccessfully: Bool = true
    ) -> (
        MacSpeechAudioHost,
        FakeMicrophoneAuthorizationProvider,
        FakeMacSpeechAudioCapture,
        FakeMacSpeechDeviceMonitor
    ) {
        let provider = FakeMicrophoneAuthorizationProvider(
            authorization: authorization
        )
        let capture = FakeMacSpeechAudioCapture(
            processingMode: processingMode
        )
        let monitor = FakeMacSpeechDeviceMonitor(
            route: route,
            monitoringStartsSuccessfully: monitoringStartsSuccessfully
        )
        return (
            MacSpeechAudioHost(
                authorizationProvider: provider,
                capture: capture,
                deviceMonitor: monitor,
                frameCapacity: frameCapacity,
                tier2RouteEnrollment: tier2RouteEnrollment
            ),
            provider,
            capture,
            monitor
        )
    }

    private static var availableRoute: MacSpeechDeviceRoute {
        MacSpeechDeviceRoute(input: inputA, output: outputA)
    }

    private static func makeTier2RouteEnrollment(
        inputDeviceUID: String = inputA.identifier,
        outputDeviceUID: String = outputA.identifier,
        audioProcessingMode: MacSpeechAudioProcessingMode =
            .appleVoiceProcessing,
        decisionRevision: String =
            MacSpeechTier2RouteCaptureLease.frozenDecisionRevision,
        evidenceRecordID: String = "test3-tier2-route-evidence"
    ) -> MacSpeechTier2RouteEnrollment {
        MacSpeechTier2RouteEnrollment(
            inputDeviceUID: inputDeviceUID,
            outputDeviceUID: outputDeviceUID,
            audioProcessingMode: audioProcessingMode,
            decisionRevision: decisionRevision,
            evidenceRecordID: evidenceRecordID
        )
    }

    private static func testInitialStateDoesNotQueryOrRequest() async {
        let (host, provider, _, _) = makeHost(authorization: .notDetermined)
        let initial = await host.currentSnapshot()
        expect(initial == .initial, "host starts idle")
        expect(await provider.queryCount == 0, "init does not query permission")
        expect(await provider.requestCount == 0, "init does not request permission")

        let snapshot = await host.refreshAuthorization()
        expect(
            snapshot.state == .permissionRequired,
            "query maps notDetermined to permissionRequired"
        )
        expect(await provider.requestCount == 0, "query never requests permission")
    }

    private static func testAuthorizationMappings() async {
        let cases: [(MicrophoneAuthorizationState, MacSpeechAudioHostState)] = [
            (.notDetermined, .permissionRequired),
            (.authorized, .ready),
            (.denied, .denied),
            (.restricted, .restricted)
        ]
        for (authorization, expectedState) in cases {
            let (host, provider, _, monitor) = makeHost(
                authorization: authorization
            )
            let snapshot = await host.refreshAuthorization()
            expect(
                snapshot.authorization == authorization,
                "authorization value is preserved"
            )
            expect(snapshot.state == expectedState, "authorization maps to host state")
            expect(await provider.requestCount == 0, "status mapping does not request")
            expect(monitor.startCount == 1, "route listener installs once")
            _ = await host.refreshAuthorization()
            expect(monitor.startCount == 1, "route listener is idempotent")
        }
    }

    private static func testExplicitRequestAndRepeatSafety() async {
        let (host, provider, _, _) = makeHost(authorization: .notDetermined)
        let first = await host.requestMicrophoneAuthorization()
        expect(first.authorization == .authorized, "request returns authorized")
        expect(first.state == .ready, "authorized request enters ready")
        expect(await provider.requestCount == 1, "explicit request runs once")

        let second = await host.requestMicrophoneAuthorization()
        expect(second.state == .ready, "repeated request remains ready")
        expect(await provider.requestCount == 1, "repeated request is safe")
    }

    private static func testRequestFailure() async {
        let provider = FakeMicrophoneAuthorizationProvider(
            authorization: .notDetermined,
            requestFails: true
        )
        let host = MacSpeechAudioHost(
            authorizationProvider: provider,
            capture: FakeMacSpeechAudioCapture(),
            deviceMonitor: FakeMacSpeechDeviceMonitor(route: availableRoute)
        )
        let snapshot = await host.requestMicrophoneAuthorization()
        expect(snapshot.authorization == .failed, "request failure is standardized")
        expect(snapshot.state == .failed, "request failure enters failed")
    }

    private static func testQueryFailure() async {
        let provider = FakeMicrophoneAuthorizationProvider(
            authorization: .notDetermined,
            queryFails: true
        )
        let host = MacSpeechAudioHost(
            authorizationProvider: provider,
            capture: FakeMacSpeechAudioCapture(),
            deviceMonitor: FakeMacSpeechDeviceMonitor(route: availableRoute)
        )
        let snapshot = await host.refreshAuthorization()
        expect(snapshot.authorization == .failed, "query failure is standardized")
        expect(snapshot.state == .failed, "query failure enters failed")
        expect(await provider.requestCount == 0, "query failure does not request")
    }

    private static func testUnauthorizedCaptureIsRejected() async {
        let (host, _, capture, _) = makeHost(authorization: .denied)
        let snapshot = await host.startCapture()
        expect(!snapshot.isCapturing, "unauthorized capture does not start")
        expect(capture.startCount == 0, "unauthorized capture never reaches engine")
        expect(snapshot.lastError == "microphone_not_authorized", "authorization failure is diagnostic")
    }

    private static func testVoiceProcessingUnavailableFailsClosed() async {
        let capture = FakeMacSpeechAudioCapture(
            startError: .voiceProcessingUnavailable
        )
        let host = MacSpeechAudioHost(
            authorizationProvider: FakeMicrophoneAuthorizationProvider(
                authorization: .authorized
            ),
            capture: capture,
            deviceMonitor: FakeMacSpeechDeviceMonitor(route: availableRoute)
        )

        let snapshot = await host.startCapture()
        expect(!snapshot.isCapturing, "capture does not bypass voice processing")
        expect(snapshot.state == .failed, "voice processing failure stops capture")
        expect(
            snapshot.lastError == "voice_processing_unavailable",
            "voice processing failure is diagnostic"
        )
        expect(!capture.isStarted, "raw microphone capture never starts")
    }

    private static func testStartStopRestartAreIdempotent() async {
        let (host, _, capture, _) = makeHost(authorization: .authorized)
        let first = await host.startCapture()
        expect(first.isCapturing, "authorized start captures")
        expect(first.state == .capturing, "capture enters capturing state")
        expect(first.actualSampleRate == 48_000, "native sample rate is diagnostic")
        expect(first.actualChannelCount == 2, "native channel count is diagnostic")

        _ = await host.startCapture()
        expect(capture.startCount == 1, "repeated start does not install another tap")
        _ = await host.stopCapture()
        _ = await host.stopCapture()
        expect(capture.stopCount == 1, "repeated stop is idempotent")

        let restarted = await host.startCapture()
        expect(restarted.isCapturing, "capture can restart manually")
        expect(capture.startCount == 2, "restart creates one new capture generation")
        _ = await host.stopCapture()
    }

    private static func testPreparedCaptureDefersProducerAndResetsGenerationStats()
        async
    {
        let (host, _, capture, _) = makeHost(
            authorization: .authorized,
            frameCapacity: 2
        )
        _ = await host.startCapture()
        expect(capture.emit(timestamp: 1), "first generation accepts frame one")
        expect(capture.emit(timestamp: 2), "first generation accepts frame two")
        expect(capture.emit(timestamp: 3), "first generation accepts frame three")
        expect(
            await host.currentSnapshot().droppedFrameCount == 1,
            "first generation records its overflow"
        )

        guard let generation = await host.prepareCaptureGeneration() else {
            fatalError("FAILED: capture generation is prepared")
        }
        let prepared = await host.currentSnapshot()
        expect(!capture.isStarted, "preparation keeps the producer stopped")
        expect(!prepared.isCapturing, "prepared host is not yet capturing")
        expect(
            prepared.generatedFrameCount == 0
                && prepared.droppedFrameCount == 0
                && prepared.queuedFrameCount == 0,
            "new generation starts with isolated frame diagnostics"
        )
        expect(
            await host.activeCaptureGeneration() == nil,
            "prepared generation is not reported as active"
        )

        let active = await host.startPreparedCapture(generation: generation)
        expect(active.isCapturing, "prepared generation can activate capture")
        expect(capture.isStarted, "producer starts only after activation")
        expect(
            await host.activeCaptureGeneration() == generation,
            "active capture keeps the prepared generation"
        )
        _ = await host.stopCapture()
    }

    private static func testTier2RouteCaptureLeaseDefaultsToNil() async {
        let defaultSource: any MacSpeechAudioFrameSourcing =
            DefaultCaptureLeaseAudioFrameSource()
        expect(
            await defaultSource.tier2RouteCaptureLease() == nil,
            "frame source protocol defaults to no automatic capture lease"
        )
        let inactiveLease = MacSpeechTier2RouteCaptureLease(
            inputDeviceUID: inputA.identifier,
            outputDeviceUID: outputA.identifier,
            audioProcessingMode: .appleVoiceProcessing,
            decisionRevision:
                MacSpeechTier2RouteCaptureLease.frozenDecisionRevision,
            evidenceRecordID: "default-source-test",
            captureGeneration: 1,
            routeRevision: 0
        )
        expect(
            !(await defaultSource.isTier2RouteCaptureLeaseActive(inactiveLease)),
            "frame source protocol cannot validate a route lease by default"
        )

        let (host, _, _, _) = makeHost(
            authorization: .authorized,
            processingMode: .appleVoiceProcessing
        )
        _ = await host.startCapture()
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "unenrolled physical route remains explicit-only"
        )
        _ = await host.stopCapture()
    }

    private static func testTier2RouteCaptureLeaseRequiresExactBindings()
        async
    {
        let enrollment = makeTier2RouteEnrollment()
        let (qualifiedHost, _, _, _) = makeHost(
            authorization: .authorized,
            processingMode: .appleVoiceProcessing,
            tier2RouteEnrollment: enrollment
        )
        _ = await qualifiedHost.startCapture()
        let lease = await qualifiedHost.tier2RouteCaptureLease()
        expect(
            lease?.inputDeviceUID == enrollment.inputDeviceUID
                && lease?.outputDeviceUID == enrollment.outputDeviceUID
                && lease?.audioProcessingMode
                    == enrollment.audioProcessingMode
                && lease?.decisionRevision == enrollment.decisionRevision
                && lease?.evidenceRecordID == enrollment.evidenceRecordID
                && lease?.captureGeneration == 1
                && lease?.routeRevision == 0,
            "exact enrolled route, mode, evidence, and generation lease"
        )
        _ = await qualifiedHost.stopCapture()

        let fallbackInput = MacSpeechAudioDevice(
            identifier: inputA.identifier,
            name: inputA.name,
            isAvailable: true
        )
        let fallbackOutput = MacSpeechAudioDevice(
            identifier: outputA.identifier,
            name: outputA.name,
            isAvailable: true
        )
        let mismatches: [(
            String,
            MacSpeechTier2RouteEnrollment,
            MacSpeechAudioProcessingMode?,
            MacSpeechDeviceRoute
        )] = [
            (
                "input UID mismatch",
                makeTier2RouteEnrollment(inputDeviceUID: "input-b"),
                .appleVoiceProcessing,
                availableRoute
            ),
            (
                "output UID mismatch",
                makeTier2RouteEnrollment(outputDeviceUID: "output-b"),
                .appleVoiceProcessing,
                availableRoute
            ),
            (
                "enrolled mode mismatch",
                makeTier2RouteEnrollment(
                    audioProcessingMode: .webRTCAEC3
                ),
                .appleVoiceProcessing,
                availableRoute
            ),
            (
                "runtime mode mismatch",
                makeTier2RouteEnrollment(),
                .webRTCAEC3,
                availableRoute
            ),
            (
                "unreported runtime mode",
                makeTier2RouteEnrollment(),
                nil,
                availableRoute
            ),
            (
                "decision revision mismatch",
                makeTier2RouteEnrollment(
                    decisionRevision: "test3_tier2_capture_lease_other"
                ),
                .appleVoiceProcessing,
                availableRoute
            ),
            (
                "fallback input identity",
                makeTier2RouteEnrollment(),
                .appleVoiceProcessing,
                MacSpeechDeviceRoute(input: fallbackInput, output: outputA)
            ),
            (
                "fallback output identity",
                makeTier2RouteEnrollment(),
                .appleVoiceProcessing,
                MacSpeechDeviceRoute(input: inputA, output: fallbackOutput)
            ),
            (
                "unavailable output",
                makeTier2RouteEnrollment(),
                .appleVoiceProcessing,
                MacSpeechDeviceRoute(input: inputA, output: .unavailable)
            ),
            (
                "missing evidence record",
                makeTier2RouteEnrollment(evidenceRecordID: " \n"),
                .appleVoiceProcessing,
                availableRoute
            )
        ]
        for (name, candidate, processingMode, route) in mismatches {
            let (host, _, _, _) = makeHost(
                authorization: .authorized,
                route: route,
                processingMode: processingMode,
                tier2RouteEnrollment: candidate
            )
            _ = await host.startCapture()
            expect(
                await host.tier2RouteCaptureLease() == nil,
                "\(name) cannot obtain a capture lease"
            )
            _ = await host.stopCapture()
        }
    }

    private static func testTier2RouteCaptureLeaseTracksCaptureLifecycle()
        async
    {
        let enrollment = makeTier2RouteEnrollment()
        let (host, _, _, monitor) = makeHost(
            authorization: .authorized,
            processingMode: .appleVoiceProcessing,
            tier2RouteEnrollment: enrollment
        )
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "idle host does not expose a capture lease"
        )
        guard let preparedGeneration = await host.prepareCaptureGeneration() else {
            fatalError("FAILED: enrolled route prepares a capture generation")
        }
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "prepared but inactive generation does not expose a lease"
        )
        _ = await host.startPreparedCapture(generation: preparedGeneration)
        guard let firstLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: active enrolled route exposes a capture lease")
        }
        expect(
            firstLease.captureGeneration == preparedGeneration,
            "lease binds the active prepared generation"
        )
        expect(
            await host.isTier2RouteCaptureLeaseActive(firstLease),
            "newly issued route lease revalidates while capture is unchanged"
        )
        _ = await host.stopCapture()
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "stopped generation retires its lease"
        )
        expect(
            !(await host.isTier2RouteCaptureLeaseActive(firstLease)),
            "stopped generation invalidates its issued route lease"
        )

        _ = await host.startCapture()
        guard let restartedLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: restarted enrolled route exposes a lease")
        }
        expect(
            restartedLease.captureGeneration == preparedGeneration + 1
                && restartedLease != firstLease,
            "restart issues a fresh generation-bound lease"
        )
        let firstLeaseAfterRestart = await host
            .isTier2RouteCaptureLeaseActive(firstLease)
        let restartedLeaseIsActive = await host
            .isTier2RouteCaptureLeaseActive(restartedLease)
        expect(
            !firstLeaseAfterRestart && restartedLeaseIsActive,
            "restart rejects the old lease and validates only the new lease"
        )

        monitor.setRoute(MacSpeechDeviceRoute(input: inputB, output: outputB))
        await host.refreshDeviceRoute()
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "route change retires the prior capture lease"
        )
        expect(
            !(await host.isTier2RouteCaptureLeaseActive(restartedLease)),
            "route revision change invalidates the issued lease"
        )
        monitor.setRoute(availableRoute)
        await host.refreshDeviceRoute()
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "restored route remains lease-free until a fresh capture starts"
        )
        _ = await host.startCapture()
        guard let restoredLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: restored route exposes a fresh capture lease")
        }
        expect(
            restoredLease.captureGeneration == restartedLease.captureGeneration + 1,
            "restored exact route uses a new generation"
        )
        expect(
            await host.isTier2RouteCaptureLeaseActive(restoredLease),
            "restored route validates only its fresh lease"
        )
        _ = await host.stopCapture()
    }

    private static func testTier2RouteCaptureLeaseRequiresActiveMonitoring()
        async
    {
        let (host, _, _, monitor) = makeHost(
            authorization: .authorized,
            processingMode: .appleVoiceProcessing,
            tier2RouteEnrollment: makeTier2RouteEnrollment(),
            monitoringStartsSuccessfully: false
        )
        let snapshot = await host.startCapture()
        expect(
            snapshot.isCapturing,
            "route listener failure does not disable explicit Tier1 capture"
        )
        expect(
            monitor.startCount == 1
                && !monitor.hasActiveRouteChangeMonitoring(),
            "failed route listener registration is observable as inactive"
        )
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "inactive route monitoring cannot issue a Tier2 capture lease"
        )
        _ = await host.stopCapture()
    }

    private static func testTier2RouteCaptureLeaseRejectsBindingFlips() async {
        let enrollment = makeTier2RouteEnrollment()
        let (host, _, _, monitor) = makeHost(
            authorization: .authorized,
            processingMode: .appleVoiceProcessing,
            tier2RouteEnrollment: enrollment
        )
        _ = await host.startCapture()
        guard let firstLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: exact route starts with a capture lease")
        }

        let fallbackInput = MacSpeechAudioDevice(
            identifier: inputA.identifier,
            name: inputA.name,
            isAvailable: true
        )
        monitor.setRoute(
            MacSpeechDeviceRoute(input: fallbackInput, output: outputA)
        )
        await host.refreshDeviceRoute()
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "same UID with fallback provenance retires the capture lease"
        )

        monitor.setRoute(availableRoute)
        await host.refreshDeviceRoute()
        _ = await host.startCapture()
        guard let restoredLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: restored exact route starts a new lease")
        }
        expect(
            restoredLease.captureGeneration == firstLease.captureGeneration + 1,
            "provenance flip requires a fresh capture generation"
        )

        let unavailableInput = MacSpeechAudioDevice(
            identifier: inputA.identifier,
            name: inputA.name,
            isAvailable: false,
            hasExactDeviceUID: true
        )
        monitor.setRoute(
            MacSpeechDeviceRoute(input: unavailableInput, output: outputA)
        )
        await host.refreshDeviceRoute()
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "same UID becoming unavailable retires the capture lease"
        )

        monitor.setRoute(availableRoute)
        await host.refreshDeviceRoute()
        _ = await host.startCapture()
        guard let exactOutputLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: restored exact output starts a new lease")
        }
        let fallbackOutput = MacSpeechAudioDevice(
            identifier: outputA.identifier,
            name: outputA.name,
            isAvailable: true
        )
        monitor.setRoute(
            MacSpeechDeviceRoute(input: inputA, output: fallbackOutput)
        )
        await host.refreshDeviceRoute()
        let exactOutputLeaseIsActive = await host
            .isTier2RouteCaptureLeaseActive(exactOutputLease)
        let fallbackOutputGeneration = await host.activeCaptureGeneration()
        expect(
            await host.tier2RouteCaptureLease() == nil
                && !exactOutputLeaseIsActive
                && fallbackOutputGeneration == nil,
            "same output UID with fallback provenance retires its lease"
        )

        monitor.setRoute(availableRoute)
        await host.refreshDeviceRoute()
        _ = await host.startCapture()
        guard let availableOutputLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: available exact output starts a new lease")
        }
        let exactOutputLeaseAfterRestart = await host
            .isTier2RouteCaptureLeaseActive(exactOutputLease)
        let availableOutputLeaseIsInitiallyActive = await host
            .isTier2RouteCaptureLeaseActive(availableOutputLease)
        expect(
            availableOutputLease.captureGeneration
                == exactOutputLease.captureGeneration + 1
                && !exactOutputLeaseAfterRestart
                && availableOutputLeaseIsInitiallyActive,
            "fallback output recovery requires and validates a fresh generation"
        )
        let unavailableOutput = MacSpeechAudioDevice(
            identifier: outputA.identifier,
            name: outputA.name,
            isAvailable: false,
            hasExactDeviceUID: true
        )
        monitor.setRoute(
            MacSpeechDeviceRoute(input: inputA, output: unavailableOutput)
        )
        await host.refreshDeviceRoute()
        let availableOutputLeaseIsActive = await host
            .isTier2RouteCaptureLeaseActive(availableOutputLease)
        let unavailableOutputGeneration = await host.activeCaptureGeneration()
        expect(
            await host.tier2RouteCaptureLease() == nil
                && !availableOutputLeaseIsActive
                && unavailableOutputGeneration == nil,
            "same output UID becoming unavailable retires its lease"
        )

        monitor.setRoute(availableRoute)
        await host.refreshDeviceRoute()
        _ = await host.startCapture()
        guard let restoredOutputLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: restored available output starts a new lease")
        }
        let unavailableOldLeaseIsActive = await host
            .isTier2RouteCaptureLeaseActive(availableOutputLease)
        let restoredOutputLeaseIsActive = await host
            .isTier2RouteCaptureLeaseActive(restoredOutputLease)
        expect(
            restoredOutputLease.captureGeneration
                == availableOutputLease.captureGeneration + 1
                && !unavailableOldLeaseIsActive
                && restoredOutputLeaseIsActive,
            "unavailable output recovery requires and validates a fresh generation"
        )
        _ = await host.stopCapture()
    }

    private static func testTier2RouteCaptureLeaseRejectsFoldedRouteChanges()
        async
    {
        let enrollment = makeTier2RouteEnrollment()
        let (host, _, capture, monitor) = makeHost(
            authorization: .authorized,
            processingMode: .appleVoiceProcessing,
            tier2RouteEnrollment: enrollment
        )
        _ = await host.startCapture()
        guard let originalLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: exact route starts with a capture lease")
        }

        monitor.setRoute(MacSpeechDeviceRoute(input: inputB, output: outputB))
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "live route mismatch closes the lease before actor refresh"
        )
        monitor.setRoute(availableRoute)
        expect(
            await host.tier2RouteCaptureLease() == nil,
            "A-to-B-to-A notifications cannot revive the old route revision"
        )

        await host.refreshDeviceRoute()
        let foldedLease = await host.tier2RouteCaptureLease()
        let foldedGeneration = await host.activeCaptureGeneration()
        expect(
            foldedLease == nil
                && foldedGeneration == nil
                && capture.stopCount == 1,
            "folded route changes invalidate the active capture generation"
        )
        _ = await host.startCapture()
        guard let revisedLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: fresh capture exposes a revised route lease")
        }
        expect(
            revisedLease.captureGeneration == originalLease.captureGeneration + 1
                && revisedLease.routeRevision
                    == originalLease.routeRevision + 2
                && revisedLease.routeRevision
                    == monitor.currentRouteRevision(),
            "folded route changes require a fresh generation and lease revision"
        )
        let originalLeaseIsActive = await host
            .isTier2RouteCaptureLeaseActive(originalLease)
        let revisedLeaseIsActive = await host
            .isTier2RouteCaptureLeaseActive(revisedLease)
        expect(
            !originalLeaseIsActive && revisedLeaseIsActive,
            "folded route validates only its fresh generation lease"
        )
        _ = await host.stopCapture()
    }

    private static func testNotificationDrivenRouteInvalidation() async {
        let (host, _, capture, monitor) = makeHost(
            authorization: .authorized,
            processingMode: .appleVoiceProcessing,
            tier2RouteEnrollment: makeTier2RouteEnrollment()
        )
        _ = await host.startCapture()
        guard let originalLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: notification test starts with a route lease")
        }

        monitor.notifyRouteChange(
            MacSpeechDeviceRoute(input: inputB, output: outputB)
        )
        monitor.notifyRouteChange(availableRoute)
        for _ in 0..<100 {
            if await host.activeCaptureGeneration() == nil { break }
            await Task.yield()
        }
        let invalidatedGeneration = await host.activeCaptureGeneration()
        expect(
            invalidatedGeneration == nil
                && capture.stopCount == 1
                && monitor.currentRouteRevision()
                    == originalLease.routeRevision + 2,
            "stored route callback invalidates folded route generation"
        )
        expect(
            !(await host.isTier2RouteCaptureLeaseActive(originalLease)),
            "notification-driven route change invalidates the issued lease"
        )

        _ = await host.startCapture()
        guard let restartedLease = await host.tier2RouteCaptureLease() else {
            fatalError("FAILED: notification route can restart with a lease")
        }
        expect(
            restartedLease.captureGeneration
                == originalLease.captureGeneration + 1
                && restartedLease.routeRevision
                    == monitor.currentRouteRevision(),
            "notification route restart uses new generation and exact revision"
        )
        _ = await host.stopCapture()
    }

    private static func testPCM16Encoding() {
        let values: [Float] = [
            -2, -1, -0.5, 0, 0.5, 1, 2,
            .nan, .infinity, -.infinity
        ]
        let encoded = MacSpeechPCM16Encoder.encode(samples: values)
        expect(
            decodePCM16(encoded) == [
                -32_768, -32_768, -16_384, 0, 16_384,
                32_767, 32_767, 0, 0, 0
            ],
            "Float32 values clamp and encode as little-endian PCM16"
        )
    }

    private static func testStereoConversionToFrozenMonoFormat() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024),
        let channels = buffer.floatChannelData else {
            fatalError("FAILED: test audio buffer creation")
        }
        buffer.frameLength = 1_024
        for channel in 0 ..< 2 {
            for index in 0 ..< 1_024 {
                channels[channel][index] = index < 512 ? -1 : 1
            }
        }
        let packets = try MacSpeechAudioConverter(inputFormat: format)
            .convert(buffer)
        expect(packets.count == 1, "converter emits one complete 20 ms packet")
        guard let converted = packets.first else {
            fatalError("FAILED: converted packet unavailable")
        }
        let decoded = decodePCM16(converted.bytes)
        expect(
            decoded.count == MacSpeechAudioInputFormat.packetSampleCount,
            "converter emits exactly 480 samples"
        )
        expect(converted.bytes.count == 960, "converter emits exactly 960 bytes")
        expect(decoded.prefix(128).contains { $0 < -20_000 }, "stereo negative peak converts to mono")
        expect(decoded.suffix(128).contains { $0 > 20_000 }, "stereo positive peak converts to mono")
        expect(converted.activity > 0, "converter reports bounded activity")
    }

    private static func testVoiceProcessingThreeChannelConversionIsAudible()
        throws
    {
        guard let layout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3
        ) else {
            fatalError("FAILED: voice-processing channel layout creation")
        }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            interleaved: false,
            channelLayout: layout
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 1_024
        ),
        let channels = buffer.floatChannelData else {
            fatalError("FAILED: voice-processing test buffer creation")
        }
        buffer.frameLength = 1_024
        for channel in 0 ..< 3 {
            for index in 0 ..< 1_024 {
                channels[channel][index] = index < 512 ? -0.5 : 0.5
            }
        }

        let packets = try MacSpeechAudioConverter(inputFormat: format)
            .convert(buffer)
        guard let converted = packets.first else {
            fatalError("FAILED: voice-processing packet unavailable")
        }
        let decoded = decodePCM16(converted.bytes)
        expect(
            decoded.contains { abs(Int($0)) > 10_000 },
            "three-channel voice-processing input remains audible after mono conversion"
        )
        expect(
            converted.activity > 0.1,
            "three-channel voice-processing input retains speech activity"
        )
    }

    private static func testExactTwentyMillisecondPacketization() {
        var packetizer = MacSpeechPCM16Packetizer()
        expect(
            packetizer.append(samples: Array(repeating: 0.25, count: 127))
                .isEmpty,
            "partial device callback is retained"
        )
        let first = packetizer.append(
            samples: Array(repeating: 0.25, count: 353)
        )
        expect(first.count == 1, "irregular callbacks form one exact packet")
        expect(first[0].bytes.count == 960, "packet is 20 ms PCM16")

        let next = packetizer.append(
            samples: Array(repeating: -0.5, count: 1_123)
        )
        expect(next.count == 2, "large callback emits all complete packets")
        expect(
            next.allSatisfy { $0.bytes.count == 960 },
            "every emitted packet has an exact byte count"
        )
        let final = packetizer.append(
            samples: Array(repeating: 0, count: 317)
        )
        expect(final.count == 1, "remainder is preserved across callbacks")

        var transitionPacketizer = MacSpeechPCM16Packetizer()
        expect(transitionPacketizer.append(
            samples: Array(repeating: 0.75, count: 240)
        ).isEmpty, "pre-transition half packet remains pending")
        transitionPacketizer.reset()
        expect(transitionPacketizer.append(
            samples: Array(repeating: -0.75, count: 240)
        ).isEmpty, "generation fence discards the old half packet")
        let rebound = transitionPacketizer.append(
            samples: Array(repeating: -0.75, count: 240)
        )
        expect(rebound.count == 1
                && decodePCM16(rebound[0].bytes).allSatisfy { $0 < 0 },
               "N+1 packet contains only post-fence samples")

        var captureFence = MacSpeechCaptureGenerationFence()
        expect(captureFence.accepts(hostTimeNanoseconds: nil),
               "initial capture generation accepts the live callback")
        captureFence.advance(to: 1_000)
        expect(!captureFence.accepts(hostTimeNanoseconds: nil)
                && !captureFence.accepts(hostTimeNanoseconds: 999),
               "generation fence rejects untimed and pre-fence callbacks")
        expect(captureFence.accepts(hostTimeNanoseconds: 1_000)
                && captureFence.accepts(hostTimeNanoseconds: 1_001),
               "generation fence accepts current callbacks")
    }

    private static func testBoundedFrameBuffer() {
        let buffer = MacSpeechAudioFrameBuffer(capacity: 2)
        buffer.begin(generation: 7)
        expect(buffer.append(pcm16Bytes: Data([1, 0]), activity: 0.1, generation: 7, timestamp: 5), "first frame accepted")
        expect(buffer.append(pcm16Bytes: Data([2, 0]), activity: 0.2, generation: 7, timestamp: 4), "second frame accepted")
        expect(buffer.append(pcm16Bytes: Data([3, 0]), activity: 0.3, generation: 7, timestamp: 4), "third frame accepted")
        let stats = buffer.stats()
        expect(stats.generatedCount == 3, "generated frames are counted")
        expect(stats.droppedCount == 1, "full queue drops oldest frame")
        expect(stats.queuedCount == 2, "queue never exceeds capacity")
        let frames = buffer.drain(maxCount: 8)
        expect(frames.map(\.sequenceNumber) == [2, 3], "drop-oldest policy is deterministic")
        expect(frames[1].monotonicTimestampNanoseconds > frames[0].monotonicTimestampNanoseconds, "timestamps remain monotonic")
        buffer.end(generation: 7)
        expect(!buffer.append(pcm16Bytes: Data([4, 0]), activity: 1, generation: 7), "ended generation rejects late frame")
    }

    private static func testHostFrameDiagnosticsAndStaleRejection() async {
        let (host, _, capture, _) = makeHost(
            authorization: .authorized,
            frameCapacity: 2
        )
        _ = await host.startCapture()
        expect(capture.emit(timestamp: 1), "active capture accepts first frame")
        expect(capture.emit(timestamp: 2), "active capture accepts second frame")
        expect(capture.emit(timestamp: 3), "active capture accepts third frame")
        let active = await host.currentSnapshot()
        expect(active.generatedFrameCount == 3, "host reports generated frames")
        expect(active.droppedFrameCount == 1, "host reports dropped frames")
        expect(active.queuedFrameCount == 2, "host reports bounded queue depth")
        let drained = await host.drainFrames(maxCount: 8)
        expect(drained.map(\.sequenceNumber) == [2, 3], "host drains newest bounded frames")

        _ = await host.stopCapture()
        expect(!capture.emit(timestamp: 4), "stop rejects late capture callback")
        let stopped = await host.currentSnapshot()
        expect(stopped.generatedFrameCount == 3, "late frame does not increment generated count")
        expect(stopped.rejectedStaleFrameCount == 1, "late frame rejection is counted")
    }

    private static func testDeviceChangesStopSafelyWithoutAutomaticRestart() async {
        let (host, _, capture, monitor) = makeHost(authorization: .authorized)
        _ = await host.startCapture()
        monitor.setRoute(
            MacSpeechDeviceRoute(input: .unavailable, output: outputB)
        )
        await host.refreshDeviceRoute()
        let disconnected = await host.currentSnapshot()
        expect(!disconnected.isCapturing, "input disconnect stops capture")
        expect(disconnected.state == .deviceUnavailable, "input disconnect marks device unavailable")
        expect(disconnected.lastError == "input_device_unavailable", "input disconnect is diagnostic")
        expect(capture.stopCount == 1, "input disconnect releases capture once")

        monitor.setRoute(MacSpeechDeviceRoute(input: inputB, output: outputB))
        await host.refreshDeviceRoute()
        let recovered = await host.currentSnapshot()
        expect(recovered.state == .ready, "available route becomes restartable")
        expect(!recovered.isCapturing, "route recovery does not auto-capture")
        expect(capture.startCount == 1, "route recovery does not restart engine")

        _ = await host.startCapture()
        monitor.setRoute(MacSpeechDeviceRoute(input: inputB, output: outputA))
        await host.refreshDeviceRoute()
        let outputSwitched = await host.currentSnapshot()
        expect(!outputSwitched.isCapturing, "output route change stops old capture reference")
        expect(outputSwitched.lastError == "audio_route_changed", "output switch is diagnostic")

        monitor.setRoute(MacSpeechDeviceRoute(input: inputA, output: outputA))
        await host.refreshDeviceRoute()
        let switched = await host.currentSnapshot()
        expect(!switched.isCapturing, "default input switch stops old capture")
        expect(switched.state == .ready, "input switch remains explicitly restartable")
        expect(capture.stopCount == 2, "input switch releases active capture")
        expect(capture.routeResetCount == 5, "all route changes invalidate AEC reference")
    }

    private static func testInputOutputAndCombinedRouteRebuilds() async {
        let cases: [(String, MacSpeechDeviceRoute)] = [
            ("input-only", MacSpeechDeviceRoute(input: inputB, output: outputA)),
            ("output-only", MacSpeechDeviceRoute(input: inputA, output: outputB)),
            ("input+output", MacSpeechDeviceRoute(input: inputB, output: outputB))
        ]
        for (name, changedRoute) in cases {
            let (host, _, capture, monitor) = makeHost(
                authorization: .authorized
            )
            _ = await host.startCapture()
            monitor.setRoute(changedRoute)
            await host.refreshDeviceRoute()
            let rebuilding = await host.currentSnapshot()
            expect(!rebuilding.isCapturing,
                   "\(name) route rebuild pauses capture")
            expect(capture.routeResetCount == 2,
                   "\(name) route rebuild completes once after initial setup")
            expect(capture.routeRebuildCompletionCount == 2,
                   "\(name) route rebuild has a deterministic completion")
            expect(capture.routeRebuildCompletionWhileStartedCount == 0,
                   "\(name) route rebuild completes only after old capture stops")
            let recovered = await host.startCapture()
            expect(recovered.isCapturing,
                   "\(name) route rebuild is deterministically restartable")
            _ = await host.stopCapture()
        }
    }

    private static func testAcousticDiagnosticsPassThrough() {
        let (host, _, capture, _) = makeHost(authorization: .authorized)
        expect(host.currentAcousticEchoSnapshot() == nil,
               "non-AEC capture reports unavailable diagnostics")
        host.resetAcousticEchoDiagnostics()
        expect(capture.acousticDiagnosticResetCount == 1,
               "audio host forwards diagnostic reset to capture")
    }

    private static func decodePCM16(_ data: Data) -> [Int16] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - 1, by: 2).map { index in
            let bits = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
            return Int16(bitPattern: bits)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
