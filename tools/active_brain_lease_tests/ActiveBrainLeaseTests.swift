import Foundation

private struct LeaseCredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "test-credential"
    }
}

private final class LeaseTextTransport: ProviderHTTPTransport {
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []
    private var shouldHoldNextResponse = false
    private var heldResponse: CheckedContinuation<Void, Never>?
    private var heldRequestWaiters: [CheckedContinuation<Void, Never>] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let shouldHold = lock.withLock {
            capturedRequests.append(request)
            let shouldHold = shouldHoldNextResponse
            shouldHoldNextResponse = false
            return shouldHold
        }
        if shouldHold {
            await withCheckedContinuation { continuation in
                let waiters = lock.withLock {
                    heldResponse = continuation
                    let waiters = heldRequestWaiters
                    heldRequestWaiters.removeAll(keepingCapacity: true)
                    return waiters
                }
                waiters.forEach { $0.resume() }
            }
        }
        let reply = #"{"reply_text":"single brain response","expression_state":"neutral","expression_intensity":0}"#
        let body: [String: Any] = [
            "choices": [["message": ["content": reply]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func requestCount() -> Int {
        lock.withLock { capturedRequests.count }
    }

    func holdNextResponse() {
        lock.withLock { shouldHoldNextResponse = true }
    }

    func waitForHeldRequest() async {
        await withCheckedContinuation { continuation in
            let isAlreadyHeld = lock.withLock {
                if heldResponse != nil {
                    return true
                }
                heldRequestWaiters.append(continuation)
                return false
            }
            if isAlreadyHeld {
                continuation.resume()
            }
        }
    }

    func resumeHeldResponse() {
        let continuation = lock.withLock {
            let continuation = heldResponse
            heldResponse = nil
            return continuation
        }
        continuation?.resume()
    }
}

private actor LeaseASRProvider: ASRProvider {
    private var activeGeneration: UInt64?
    private var nextEventKind: ASREventKind = .partialTranscript("active")
    private var cancelError: SpeechRouteError?
    private var closeError: SpeechRouteError?
    private var shouldHoldNextStart = false
    private var heldStart: CheckedContinuation<Void, Never>?
    private var heldStartWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var startedGenerations: [UInt64] = []
    private(set) var cancelledGenerations: [UInt64] = []
    private(set) var closedGenerations: [UInt64] = []

    func start(request: ASRStartRequest) async throws {
        activeGeneration = request.generation
        startedGenerations.append(request.generation)
        if shouldHoldNextStart {
            shouldHoldNextStart = false
            await withCheckedContinuation { continuation in
                heldStart = continuation
                let waiters = heldStartWaiters
                heldStartWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
    }

    func send(_ input: ASRAudioInput) async throws {
        guard activeGeneration == input.generation else {
            throw SpeechRouteError.staleGeneration
        }
    }

    func receive(generation: UInt64) async throws -> ASREvent {
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        let kind = nextEventKind
        nextEventKind = .partialTranscript("active")
        return ASREvent(
            generation: generation,
            kind: kind
        )
    }

    func cancel(generation: UInt64) async throws {
        cancelledGenerations.append(generation)
        if let cancelError {
            throw cancelError
        }
        if activeGeneration == generation {
            activeGeneration = nil
        }
    }

    func close(generation: UInt64) async throws {
        closedGenerations.append(generation)
        if let closeError {
            throw closeError
        }
        if activeGeneration == generation {
            activeGeneration = nil
        }
    }

    func holdNextStart() {
        shouldHoldNextStart = true
    }

    func waitForHeldStart() async {
        if heldStart != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldStartWaiters.append(continuation)
        }
    }

    func resumeHeldStart() {
        let continuation = heldStart
        heldStart = nil
        continuation?.resume()
    }

    func failTeardown() {
        cancelError = .transportFailure
        closeError = .transportFailure
    }

    func emitFinal(_ transcript: String) {
        nextEventKind = .finalTranscript(transcript)
    }
}

private actor LeaseTTSProvider: TTSProvider {
    private var activeGeneration: UInt64?
    private var shouldFailNextStart = false
    private(set) var startedGenerations: [UInt64] = []
    private(set) var cancelledGenerations: [UInt64] = []
    private(set) var closedGenerations: [UInt64] = []

    func start(request: TTSSynthesisRequest) async throws {
        activeGeneration = request.generation
        startedGenerations.append(request.generation)
        if shouldFailNextStart {
            shouldFailNextStart = false
            throw SpeechRouteError.transportFailure
        }
    }

    func receive(generation: UInt64) async throws -> TTSEvent {
        guard activeGeneration == generation else {
            throw SpeechRouteError.staleGeneration
        }
        return TTSEvent(generation: generation, kind: .done)
    }

    func cancel(generation: UInt64) async throws {
        cancelledGenerations.append(generation)
        if activeGeneration == generation {
            activeGeneration = nil
        }
    }

    func close(generation: UInt64) async throws {
        closedGenerations.append(generation)
        if activeGeneration == generation {
            activeGeneration = nil
        }
    }

    func failNextStart() {
        shouldFailNextStart = true
    }
}

private actor LeaseNativeSpeechProvider:
    NativeSpeechProvider,
    RealtimeSpeechContextProviding {
    private var preparedProjection: RealtimeSpeechContextProjection?
    private var shouldHoldNextClose = false
    private var heldClose: CheckedContinuation<Void, Never>?
    private var heldCloseWaiters: [CheckedContinuation<Void, Never>] = []
    private var closeError: NativeSpeechError?
    private(set) var startedInteractionIDs: [NativeSpeechInteractionID] = []
    private(set) var cancelledInteractionIDs: [NativeSpeechInteractionID] = []
    private(set) var closedInteractionIDs: [NativeSpeechInteractionID] = []

    func prepareContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws {
        preparedProjection = projection
    }

    func updateContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws {}

    func start(request: NativeSpeechStartRequest) async throws {
        guard preparedProjection?.isBound(to: request.interaction) == true else {
            throw NativeSpeechError.interactionMismatch
        }
        preparedProjection = nil
        startedInteractionIDs.append(request.interaction.id)
    }

    func send(audio: NativeSpeechAudioPayload) async throws {}

    func receive(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEvent {
        throw NativeSpeechError.unavailable
    }

    func cancel(
        interactionID: NativeSpeechInteractionID,
        reason: NativeSpeechCancellationReason
    ) async throws {
        cancelledInteractionIDs.append(interactionID)
    }

    func close(interactionID: NativeSpeechInteractionID) async throws {
        closedInteractionIDs.append(interactionID)
        if shouldHoldNextClose {
            shouldHoldNextClose = false
            await withCheckedContinuation { continuation in
                heldClose = continuation
                let waiters = heldCloseWaiters
                heldCloseWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
        if let closeError {
            throw closeError
        }
    }

    func startCount() -> Int {
        startedInteractionIDs.count
    }

    func holdNextClose() {
        shouldHoldNextClose = true
    }

    func waitForHeldClose() async {
        if heldClose != nil {
            return
        }
        await withCheckedContinuation { continuation in
            heldCloseWaiters.append(continuation)
        }
    }

    func resumeHeldClose() {
        let continuation = heldClose
        heldClose = nil
        continuation?.resume()
    }

    func failClose() {
        closeError = .transportFailure
    }
}

private struct LeaseRuntimeStack {
    let runtime: RuntimeCore
    let textTransport: LeaseTextTransport
    let asrProvider: LeaseASRProvider
    let ttsProvider: LeaseTTSProvider
    let nativeProvider: LeaseNativeSpeechProvider
}

@main
@MainActor
private struct ActiveBrainLeaseTests {
    private static var checks = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        testLeaseGate()
        try await testRuntimeEnforcement(fixture: fixture)
        try await testPendingRouteEnforcement(fixture: fixture)
        try await testTTSStartFailureSettlement(fixture: fixture)
        try await testTeardownFailureEnforcement(fixture: fixture)
        try await testIndependentRuntimeSessions(fixture: fixture)

        print("active_brain_lease_checks=\(checks)")
    }

    private static func testLeaseGate() {
        let gate = RuntimeActiveBrainLeaseGate()
        let first = gate.acquire(
            residentID: "resident-a",
            runtimeSessionID: "session-a",
            route: .cascadedSpeech,
            generation: .speechRoute(1)
        )
        expect(first != nil, "an empty session gate acquires one brain")
        guard let first else { return }
        expect(first.state == .active, "an acquired lease is active")
        expect(
            gate.acquire(
                residentID: "resident-a",
                runtimeSessionID: "session-a",
                route: .nativeSpeech,
                generation: .nativeInteraction(
                    NativeSpeechInteractionID()
                )
            ) == nil,
            "the same session rejects a second brain"
        )

        let otherRuntimeGate = RuntimeActiveBrainLeaseGate()
        let independent = otherRuntimeGate.acquire(
            residentID: "resident-b",
            runtimeSessionID: "session-b",
            route: .nativeSpeech,
            generation: .nativeInteraction(NativeSpeechInteractionID())
        )
        expect(
            independent != nil,
            "a different Runtime session owns its independent brain"
        )

        let advanced = gate.advanceGeneration(
            for: first,
            to: .speechRoute(2)
        )
        expect(advanced != nil, "the current route advances generation")
        guard let advanced else { return }
        expect(
            advanced.brainLeaseID == first.brainLeaseID
                && advanced.routeEpoch == first.routeEpoch,
            "generation advance keeps the same route lifecycle"
        )
        expect(!gate.isCurrent(first), "the old generation is stale")
        expect(!gate.release(first), "an old lease cannot clear the current one")
        expect(gate.release(advanced), "the current lease releases")
        expect(!gate.isCurrent(advanced), "a released callback is stale")

        let replacement = gate.acquire(
            residentID: "resident-a",
            runtimeSessionID: "session-a",
            route: .textConversation,
            generation: .textRequest(UUID())
        )
        expect(replacement != nil, "release permits a replacement brain")
        guard let replacement else { return }
        expect(
            replacement.routeEpoch > first.routeEpoch,
            "a new route lifecycle increments route epoch"
        )
        expect(!gate.isCurrent(first), "an old lease ID stays stale")
        let newerTextRequest = gate.acquire(
            residentID: "resident-a",
            runtimeSessionID: "session-a",
            route: .textConversation,
            generation: .textRequest(UUID()),
            replacingCurrentRoute: true
        )
        expect(
            newerTextRequest?.routeEpoch ?? 0 > replacement.routeEpoch,
            "a newer same-route text request atomically advances epoch"
        )
        expect(
            !gate.isCurrent(replacement),
            "the superseded same-route text callback is stale"
        )
        guard let newerTextRequest else { return }
        expect(
            gate.invalidate() == newerTextRequest,
            "session invalidation clears only the current lease"
        )
        expect(gate.current() == nil, "invalidated session has no brain")

        let settlementGate = RuntimeActiveBrainLeaseGate()
        guard let startLease = settlementGate.acquire(
            residentID: "resident-settlement",
            runtimeSessionID: "session-settlement",
            route: .cascadedSpeech,
            generation: .speechRoute(1)
        ) else {
            fatalError("FAILED: settlement gate acquires")
        }
        expect(
            settlementGate.beginProviderStart(for: startLease),
            "the active lease registers one Provider start"
        )
        guard let settlingLease = settlementGate.beginSettlement(
            for: startLease
        ) else {
            fatalError("FAILED: active lease begins settlement")
        }
        expect(
            settlingLease.state == .settling
                && !settlementGate.isCurrent(startLease),
            "settlement immediately makes old callbacks stale"
        )
        expect(
            settlementGate.acquire(
                residentID: "resident-new",
                runtimeSessionID: "session-new",
                route: .nativeSpeech,
                generation: .nativeInteraction(
                    NativeSpeechInteractionID()
                )
            ) == nil,
            "a settling lease still blocks new Brain admission"
        )
        expect(
            !settlementGate.release(settlingLease),
            "settlement cannot release while Provider start is in flight"
        )
        settlementGate.finishProviderStart(for: startLease)
        expect(
            settlementGate.release(settlingLease),
            "settlement releases after Provider start finishes"
        )
    }

    private static func testRuntimeEnforcement(
        fixture: Data
    ) async throws {
        let stack = configuredStack(fixture: fixture)
        let runtime = stack.runtime

        let native = try await runtime.startNativeSpeechInteraction()
        guard let nativeLease = runtime.activeBrainLeaseForTesting() else {
            fatalError("FAILED: native route must own a lease")
        }
        expect(
            nativeLease.route == .nativeSpeech
                && nativeLease.generation
                    == .nativeInteraction(native.id),
            "Native speech owns the RuntimeCore lease"
        )
        expectSpeechFailure(
            await runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "Native active rejects Cascaded route start"
        )
        expectProviderFailure(
            await runtime.requestResidentReply(inputText: "second answer"),
            equals: .cancelled,
            "Native active rejects ordinary text generation"
        )
        let blockedStep = runtime.step(request: RuntimeStepRequest(
            residentID: native.residentID,
            inputText: "legacy second answer"
        ))
        expect(
            blockedStep.cancellationState.isCancelled,
            "Native active rejects legacy text generation"
        )
        expect(
            stack.textTransport.requestCount() == 0,
            "rejected text paths produce no Provider answer"
        )
        let startedASRGenerations = await stack.asrProvider
            .startedGenerations
        expect(
            startedASRGenerations.isEmpty,
            "rejected Cascaded route never starts ASR"
        )

        try await runtime.cancelActiveNativeSpeechInteraction(
            reason: .stopped
        )
        expect(
            runtime.activeBrainLeaseForTesting() == nil,
            "Native cancel releases its lease"
        )

        let cascadedGeneration = try speechSuccess(
            await runtime.startSpeechRouteASR(locale: "en-US")
        )
        guard let cascadedLease = runtime.activeBrainLeaseForTesting() else {
            fatalError("FAILED: Cascaded route must own a lease")
        }
        expect(
            cascadedLease.route == .cascadedSpeech
                && cascadedLease.routeEpoch > nativeLease.routeEpoch,
            "Cascaded acquire advances route epoch"
        )
        do {
            _ = try await runtime.startNativeSpeechInteraction()
            fatalError("FAILED: Cascaded active must reject Native")
        } catch NativeSpeechError.invalidConfiguration {
            checks += 1
        }
        let nativeStartCount = await stack.nativeProvider.startCount()
        expect(
            nativeStartCount == 1,
            "rejected Native route starts no second Provider brain"
        )
        expectProviderFailure(
            await runtime.requestResidentReply(inputText: "parallel text"),
            equals: .cancelled,
            "Cascaded active rejects ordinary text generation"
        )
        expect(
            stack.textTransport.requestCount() == 0,
            "Cascaded ownership prevents a parallel text answer"
        )

        let interruptedGeneration = try speechSuccess(
            await runtime.interruptSpeechRouteForNearEnd(
                generation: cascadedGeneration,
                locale: "en-US"
            )
        )
        guard let interruptedLease = runtime.activeBrainLeaseForTesting()
        else {
            fatalError("FAILED: interrupted route keeps its lease")
        }
        expect(
            interruptedLease.brainLeaseID == cascadedLease.brainLeaseID
                && interruptedLease.routeEpoch
                    == cascadedLease.routeEpoch,
            "interrupt keeps the same route epoch and brain lease"
        )
        expect(
            interruptedLease.generation
                == .speechRoute(interruptedGeneration),
            "interrupt advances only the existing generation"
        )
        let oldGenerationEvent = try await runtime
            .receiveSpeechRouteASREvent(generation: cascadedGeneration)
        expect(
            oldGenerationEvent.kind == .staleGeneration,
            "old generation callback is stale after interrupt"
        )
        expectSpeechFailure(
            runtime.commitSpeechRoutePlayback(
                generation: cascadedGeneration
            ).map { _ in () },
            equals: .staleGeneration,
            "old playback completion is stale after interrupt"
        )
        _ = try speechSuccess(await runtime.cancelSpeechRoute(
            generation: interruptedGeneration
        ))
        expect(
            runtime.activeBrainLeaseForTesting() == nil,
            "Cascaded cancel releases its lease"
        )
        let cancelledEvent = try await runtime
            .receiveSpeechRouteASREvent(generation: interruptedGeneration)
        expect(
            cancelledEvent.kind == .staleGeneration,
            "cancelled generation cannot become current again"
        )

        _ = try await runtime.startNativeSpeechInteraction()
        try await runtime.closeActiveNativeSpeechInteraction()
        expect(
            runtime.activeBrainLeaseForTesting() == nil,
            "Native close releases its lease"
        )

        let textResult = await runtime.requestResidentReply(
            inputText: "single text answer"
        )
        switch textResult {
        case .success:
            checks += 1
        case .failure(let error):
            fatalError("FAILED: released lease permits text: \(error)")
        }
        expect(
            stack.textTransport.requestCount() == 1,
            "one released text route produces exactly one answer"
        )
        expect(
            runtime.activeBrainLeaseForTesting() == nil,
            "ordinary text releases its lease after completion"
        )

        let sessionGeneration = try speechSuccess(
            await runtime.startSpeechRouteASR(locale: "en-US")
        )
        guard let sessionLease = runtime.activeBrainLeaseForTesting() else {
            fatalError("FAILED: session route owns a lease")
        }
        expect(runtime.loadDR(from: fixture).isLoaded, "session reload succeeds")
        let sessionStaleEvent = try await runtime
            .receiveSpeechRouteASREvent(generation: sessionGeneration)
        expect(
            sessionStaleEvent.kind == .staleGeneration,
            "old session callback is stale"
        )
        let reloadedGeneration = try speechSuccess(
            await runtime.startSpeechRouteASR(locale: "en-US")
        )
        guard let reloadedLease = runtime.activeBrainLeaseForTesting() else {
            fatalError("FAILED: reloaded route owns a lease")
        }
        expect(
            reloadedLease.routeEpoch > sessionLease.routeEpoch,
            "new session route advances epoch"
        )
        _ = try speechSuccess(await runtime.closeSpeechRoute(
            generation: reloadedGeneration
        ))
        expect(
            runtime.activeBrainLeaseForTesting() == nil,
            "route close releases the current lease"
        )
    }

    private static func testIndependentRuntimeSessions(
        fixture: Data
    ) async throws {
        let first = configuredStack(fixture: fixture)
        let second = configuredStack(fixture: fixture)
        let firstGeneration = try speechSuccess(
            await first.runtime.startSpeechRouteASR(locale: "en-US")
        )
        let secondGeneration = try speechSuccess(
            await second.runtime.startSpeechRouteASR(locale: "en-US")
        )
        expect(
            first.runtime.activeBrainLeaseForTesting() != nil
                && second.runtime.activeBrainLeaseForTesting() != nil,
            "different Runtime sessions each own one brain"
        )
        _ = try speechSuccess(await first.runtime.cancelSpeechRoute(
            generation: firstGeneration
        ))
        _ = try speechSuccess(await second.runtime.cancelSpeechRoute(
            generation: secondGeneration
        ))
    }

    private static func testPendingRouteEnforcement(
        fixture: Data
    ) async throws {
        let speechStack = configuredStack(fixture: fixture)
        await speechStack.asrProvider.holdNextStart()
        let firstStart = Task {
            await speechStack.runtime.startSpeechRouteASR(locale: "en-US")
        }
        await speechStack.asrProvider.waitForHeldStart()
        expectSpeechFailure(
            await speechStack.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "an ASR start in flight rejects a second route start"
        )
        let startedGenerations = await speechStack.asrProvider
            .startedGenerations
        expect(
            startedGenerations.count == 1,
            "a rejected concurrent route does not reach the Provider"
        )
        await speechStack.asrProvider.resumeHeldStart()
        let generation = try speechSuccess(await firstStart.value)
        _ = try speechSuccess(await speechStack.runtime.cancelSpeechRoute(
            generation: generation
        ))

        let replacementStack = configuredStack(fixture: fixture)
        await replacementStack.asrProvider.holdNextStart()
        let oldSessionStart = Task {
            await replacementStack.runtime.startSpeechRouteASR(
                locale: "en-US"
            )
        }
        await replacementStack.asrProvider.waitForHeldStart()
        expect(
            replacementStack.runtime.loadDR(from: fixture).isLoaded,
            "session replacement publishes the new Runtime session"
        )
        expect(
            replacementStack.runtime.activeBrainLeaseForTesting()?.state
                == .settling,
            "session replacement immediately marks the old lease settling"
        )
        let newSessionStart = Task {
            await replacementStack.runtime.startSpeechRouteASR(
                locale: "en-US"
            )
        }
        let startsBeforeRelease = await replacementStack.asrProvider
            .startedGenerations
        expect(
            startsBeforeRelease.count == 1,
            "new Session waits while the old Provider start is in flight"
        )
        await replacementStack.asrProvider.resumeHeldStart()
        expectSpeechFailure(
            await oldSessionStart.value,
            equals: .cancelled,
            "the old in-flight start returns stale after Session replacement"
        )
        let replacementGeneration = try speechSuccess(
            await newSessionStart.value
        )
        let closedOldGenerations = await replacementStack.asrProvider
            .closedGenerations
        expect(
            closedOldGenerations.contains(1),
            "old Provider closes before the new Session starts"
        )
        _ = try speechSuccess(
            await replacementStack.runtime.cancelSpeechRoute(
                generation: replacementGeneration
            )
        )

        let textStack = configuredStack(fixture: fixture)
        textStack.textTransport.holdNextResponse()
        let textRequest = Task {
            await textStack.runtime.requestResidentReply(
                inputText: "pending text answer"
            )
        }
        await textStack.textTransport.waitForHeldRequest()
        expectSpeechFailure(
            await textStack.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "pending text generation rejects Cascaded route start"
        )
        do {
            _ = try await textStack.runtime.startNativeSpeechInteraction()
            fatalError("FAILED: pending text must reject Native")
        } catch NativeSpeechError.invalidConfiguration {
            checks += 1
        }
        let blockedASRStarts = await textStack.asrProvider
            .startedGenerations
        expect(
            blockedASRStarts.isEmpty,
            "pending text prevents a second ASR Provider start"
        )
        let blockedNativeStarts = await textStack.nativeProvider.startCount()
        expect(
            blockedNativeStarts == 0,
            "pending text prevents a second Native Provider start"
        )
        textStack.textTransport.resumeHeldResponse()
        switch await textRequest.value {
        case .success:
            checks += 1
        case .failure(let error):
            fatalError("FAILED: the original text route completes: \(error)")
        }
        expect(
            textStack.textTransport.requestCount() == 1,
            "pending text produces exactly one resident answer"
        )

        let teardownStack = configuredStack(fixture: fixture)
        _ = try await teardownStack.runtime.startNativeSpeechInteraction()
        await teardownStack.nativeProvider.holdNextClose()
        let closeTask = Task {
            try await teardownStack.runtime
                .closeActiveNativeSpeechInteraction()
        }
        await teardownStack.nativeProvider.waitForHeldClose()
        expect(
            teardownStack.runtime.activeBrainLeaseForTesting()?.route
                == .nativeSpeech,
            "Native teardown keeps its lease until Provider close settles"
        )
        expectSpeechFailure(
            await teardownStack.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "Native teardown in flight rejects a new Cascaded route"
        )
        expectProviderFailure(
            await teardownStack.runtime.requestResidentReply(
                inputText: "teardown overlap"
            ),
            equals: .cancelled,
            "Native teardown in flight rejects ordinary text generation"
        )
        await teardownStack.nativeProvider.resumeHeldClose()
        try await closeTask.value
        expect(
            teardownStack.runtime.activeBrainLeaseForTesting() == nil,
            "Provider close completion releases the Native lease"
        )
    }

    private static func testTTSStartFailureSettlement(
        fixture: Data
    ) async throws {
        let stack = configuredStack(fixture: fixture)
        let generation = try speechSuccess(
            await stack.runtime.startSpeechRouteASR(locale: "en-US")
        )
        await stack.asrProvider.emitFinal("voice request")
        let finalEvent = try await stack.runtime.receiveSpeechRouteASREvent(
            generation: generation
        )
        _ = try speechSuccess(
            await stack.runtime.finishSpeechRouteASR(
                generation: generation
            )
        )
        let turn: SpeechRouteTurnResult
        switch await stack.runtime.submitSpeechRouteASRFinal(finalEvent) {
        case .success(let result):
            turn = result
        case .failure(let error):
            fatalError("FAILED: final ASR reaches text Brain: \(error)")
        }
        checks += 1
        await stack.ttsProvider.failNextStart()
        expectSpeechFailure(
            await stack.runtime.startSpeechRouteTTS(
                request: TTSSynthesisRequest(
                    generation: generation,
                    canonicalResponseText: turn.canonicalResponseText,
                    voiceProfile: SpeechVoiceProfile(
                        profileID: "test-profile",
                        locale: "en-US"
                    ),
                    emotion: nil,
                    pace: 1,
                    style: nil
                )
            ),
            equals: .transportFailure,
            "TTS start failure is reported"
        )
        let closedGenerations = await stack.ttsProvider.closedGenerations
        expect(
            closedGenerations.contains(generation),
            "TTS start failure definitively closes the Provider"
        )
        expect(
            stack.runtime.activeBrainLeaseForTesting() == nil,
            "definitive TTS settlement releases the route lease"
        )
    }

    private static func testTeardownFailureEnforcement(
        fixture: Data
    ) async throws {
        let speechStack = configuredStack(fixture: fixture)
        let generation = try speechSuccess(
            await speechStack.runtime.startSpeechRouteASR(locale: "en-US")
        )
        await speechStack.asrProvider.failTeardown()
        expectSpeechFailure(
            await speechStack.runtime.interruptSpeechRouteForNearEnd(
                generation: generation,
                locale: "en-US"
            ),
            equals: .transportFailure,
            "failed Cascaded teardown reports the Provider error"
        )
        expect(
            speechStack.runtime.activeBrainLeaseForTesting()?.route
                == .cascadedSpeech,
            "failed Cascaded teardown retains its terminal lease"
        )
        expectSpeechFailure(
            await speechStack.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "failed Cascaded teardown keeps admission fail-closed"
        )
        expect(
            speechStack.runtime.loadDR(from: fixture).isLoaded,
            "session replacement records new state while cleanup is pending"
        )
        expectSpeechFailure(
            await speechStack.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "failed replacement cleanup still blocks new Brain admission"
        )
        expect(
            speechStack.runtime.activeBrainLeaseForTesting()?.route
                == .cascadedSpeech,
            "failed replacement cleanup preserves the terminal lease"
        )

        let nativeStack = configuredStack(fixture: fixture)
        _ = try await nativeStack.runtime.startNativeSpeechInteraction()
        await nativeStack.nativeProvider.failClose()
        do {
            try await nativeStack.runtime.closeActiveNativeSpeechInteraction()
            fatalError("FAILED: Native close failure must be reported")
        } catch NativeSpeechError.transportFailure {
            checks += 1
        }
        expect(
            nativeStack.runtime.activeBrainLeaseForTesting()?.route
                == .nativeSpeech,
            "failed Native close retains its terminal lease"
        )
        expectProviderFailure(
            await nativeStack.runtime.requestResidentReply(
                inputText: "blocked after close failure"
            ),
            equals: .cancelled,
            "failed Native close keeps text admission fail-closed"
        )
        expect(
            nativeStack.runtime.loadDR(from: fixture).isLoaded,
            "Native session replacement can publish new resident state"
        )
        expectSpeechFailure(
            await nativeStack.runtime.startSpeechRouteASR(locale: "en-US"),
            equals: .unavailable,
            "failed Native replacement cleanup blocks new Brain admission"
        )
        expect(
            nativeStack.runtime.activeBrainLeaseForTesting()?.route
                == .nativeSpeech,
            "failed Native replacement cleanup keeps the old lease"
        )
    }

    private static func configuredStack(
        fixture: Data
    ) -> LeaseRuntimeStack {
        let textTransport = LeaseTextTransport()
        let asrProvider = LeaseASRProvider()
        let ttsProvider = LeaseTTSProvider()
        let nativeProvider = LeaseNativeSpeechProvider()
        let router = ProviderRouter(
            credentialReader: LeaseCredentialReader(),
            transport: textTransport,
            asrProvider: asrProvider,
            ttsProvider: ttsProvider,
            nativeSpeechProvider: nativeProvider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: SessionStore()
        )
        expect(runtime.loadDR(from: fixture).isLoaded, "resident loads")
        expect(
            runtime.configureTextProvider(profile: ProviderProfile(
                profileID: "text-profile",
                providerID: "text-provider",
                adapterType: "openai_compatible",
                modelID: "existing-model",
                baseURL: "https://example.invalid/v1",
                keyRef: "keychain://test/text",
                enabled: true,
                timeout: 5,
                stream: false,
                thinkingMode: "disabled"
            )) == nil,
            "text Provider configures"
        )
        expect(
            runtime.configureNativeSpeechProvider(
                profile: nativeSpeechProfile()
            ) == nil,
            "Native Provider configures"
        )
        return LeaseRuntimeStack(
            runtime: runtime,
            textTransport: textTransport,
            asrProvider: asrProvider,
            ttsProvider: ttsProvider,
            nativeProvider: nativeProvider
        )
    }

    private static func nativeSpeechProfile()
        -> NativeSpeechProviderProfile {
        NativeSpeechProviderProfile(
            profileID: "native-profile",
            providerID: "native-provider",
            capability: "native_speech",
            adapterID: "test-native",
            modelID: "test-model",
            voiceID: "test-voice",
            endpoint: URL(string: "wss://example.invalid/realtime")!,
            transport: "websocket",
            inputAudioFormat: .pcm16,
            outputAudioFormat: .pcm16,
            turnDetection: NativeSpeechTurnDetection(
                type: .semanticVAD,
                prefixPaddingMilliseconds: 500
            ),
            languageMetadata: "en-US",
            keyRef: "keychain://test/native"
        )
    }

    private static func speechSuccess<T>(
        _ result: Result<T, SpeechRouteError>
    ) throws -> T {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    private static func expectSpeechFailure<T>(
        _ result: Result<T, SpeechRouteError>,
        equals expected: SpeechRouteError,
        _ message: String
    ) {
        guard case .failure(let actual) = result,
              actual == expected else {
            fatalError("FAILED: \(message)")
        }
        checks += 1
    }

    private static func expectProviderFailure<T>(
        _ result: Result<T, ProviderRequestError>,
        equals expected: ProviderRequestError,
        _ message: String
    ) {
        guard case .failure(let actual) = result,
              actual == expected else {
            fatalError("FAILED: \(message)")
        }
        checks += 1
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
