import Foundation

/// The realtime Bridges share this session's one transport. The Controller supplies Runtime identities.
actor MacSpeechNativeRealtimeSession: MacSpeechRealtimeAudioCandidate, MacSpeechRealtimeAcousticFactSourcing {
    private let makeTransport: @Sendable () -> AppleNativeVoiceTransport
    private let playbackTimeout = MacSpeechPCMPlaybackConfiguration.standard.consumerTimeoutNanoseconds
    private var transport: AppleNativeVoiceTransport?
    private var session: RealtimeBrainSessionIdentity?
    private var identity: NativeVoiceIdentity?
    private var configurationSerial: UInt64 = 0
    private var preparedGeneration: UInt64?
    private var serviceTask: Task<Void, Never>?
    private var facts = MacSpeechNativeRealtimeFacts()
    #if DEBUG && (APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED || NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST)
        nonisolated let acousticEvidence = MacSpeechNativeAcousticEvidence()
    #endif
    #if DEBUG
        private var sealedTransport: NativeVoiceTransportReadback?
        private var terminalReason: String?
    #endif
    private var outputState = MacSpeechAudioOutputHostState.idle
    private var outputError: MacSpeechAudioOutputHostError?
    private var playback: MacSpeechNativePlayback?
    private var eventSink: MacSpeechAudioOutputHost.EventSink?
    private var eventOrdinal: UInt64 = 0
    private var counters = MacSpeechNativePlaybackCounters()
    var latestNonzeroRender: NativeVoiceRenderFact? { facts.lastNonzero }
    private(set) var lastClearCompletedAtNanoseconds: UInt64?

    #if NATIVE_VOICE_P3_OFFLINE_TEST
        func setShadowEvidence(_ evidence: @escaping MacSpeechNativeRealtimeFacts.ShadowEvidence) {
            facts.shadowEvidence = evidence
        }

        func acousticMetricsForTesting() -> RealtimeAcousticMetrics? { facts.lastMetrics }
    #endif

    init(makeTransport: @escaping @Sendable () -> AppleNativeVoiceTransport) {
        self.makeTransport = makeTransport
    }

    func reserveCaptureGeneration() -> UInt64? {
        guard transport == nil, preparedGeneration == nil, configurationSerial < UInt64.max else { return nil }
        configurationSerial += 1
        preparedGeneration = configurationSerial
        return configurationSerial
    }

    func cancelPreparedCapture(generation: UInt64) {
        if preparedGeneration == generation { preparedGeneration = nil }
    }

    func startCapture(
        session: RealtimeBrainSessionIdentity, generation: UInt64,
        failed: @escaping @Sendable (String) async -> Void
    ) async throws -> MacSpeechAudioHostSnapshot {
        guard preparedGeneration == generation, transport == nil else { throw NativeVoiceSessionError.state }
        let graph = makeTransport()
        let initial = NativeVoiceIdentity(
            authority: .init(realtime: session, configuration: generation),
            captureGeneration: generation, captureToken: 1, playbackEpoch: 1, playbackToken: 1
        )
        preparedGeneration = nil
        self.session = session
        identity = initial
        transport = graph
        outputState = .idle
        outputError = nil
        facts = MacSpeechNativeRealtimeFacts()
        #if DEBUG
            sealedTransport = nil
            terminalReason = nil
        #endif
        lastClearCompletedAtNanoseconds = nil
        do {
            try await graph.start(identity: initial)
            let binding = try await graph.configuredGraph()
            guard transport === graph else { throw NativeVoiceTransportError.staleIdentity }
            let route = MacSpeechDeviceRoute(nativeVoiceDefaults: binding.defaults)
            counters = MacSpeechNativePlaybackCounters(outputDevice: route.output)
            #if APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED || NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST
                acousticEvidence.bind(session, capture: initial.capture)
            #endif
            installService(graph, failed: failed)
            return .nativeVoiceCapture(binding, route: route)
        } catch {
            if transport === graph { _ = await close() }
            throw error
        }
    }

    func activeCaptureGeneration() -> UInt64? { identity?.capture.generation }

    func isCaptureGenerationActive(_ generation: UInt64) -> Bool {
        identity?.capture.generation == generation && serviceTask != nil
    }

    func drainFrames(maxCount: Int) -> [MacSpeechAudioFrame] {
        #if DEBUG && (APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED || NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST)
            defer {
                let renderedPlayback = playback != nil ? identity?.playback : nil
                acousticEvidence.rememberCapture(facts.deliveredCapture, playback: renderedPlayback)
            }
        #endif
        return facts.drainCapture(maxCount: maxCount)
    }

    func advanceGeneration(
        from previous: RealtimeBrainSessionIdentity, to next: RealtimeBrainSessionIdentity
    ) async throws {
        guard session == previous, let graph = transport, let current = identity,
              next.brainLeaseID == previous.brainLeaseID, next.residentID == previous.residentID,
              next.runtimeSessionID == previous.runtimeSessionID, next.routeEpoch == previous.routeEpoch,
              current.capture.token < UInt64.max - 1, current.playback.token < UInt64.max else {
            throw NativeVoiceTransportError.staleIdentity
        }
        #if DEBUG && (APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED || NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST)
            acousticEvidence.stop(.identityChanged)
        #endif
        let successor = NativeVoiceIdentity(
            authority: .init(realtime: next, configuration: current.capture.authority.configurationID),
            captureGeneration: current.capture.generation, captureToken: current.capture.token + 1,
            playbackEpoch: current.playback.epoch, playbackToken: current.playback.token + 1
        )
        try await graph.advanceGeneration(from: current, to: successor)
        guard transport === graph, session == previous else { throw NativeVoiceTransportError.staleIdentity }
        identity = successor
        session = next
        facts.discardCapture(forTransition: true)
        facts.invalidatePlayback()
    }

    func setEventSink(_ sink: @escaping MacSpeechAudioOutputHost.EventSink) {
        eventSink = sink
    }

    func currentSnapshot() -> MacSpeechAudioOutputHostSnapshot { snapshot() }

    func preparePlayback(identity response: RealtimeBrainEventIdentity) async -> MacSpeechAudioOutputHostSnapshot {
        guard response.session == session, response.responseID != nil, let graph = transport, let current = identity,
              playback == nil, outputState != .failed, current.playback.token < UInt64.max else {
            return fail(.invalidState)
        }
        let next = current.replacingPlayback(cancelled: false)
        identity = next
        playback = MacSpeechNativePlayback(response: response)
        facts.invalidatePlayback()
        counters = MacSpeechNativePlaybackCounters(outputDevice: counters.outputDevice)
        do {
            try await graph.beginPlayback(next.playback)
            guard isCurrent(graph, next.playback) else { return snapshot() }
            outputState = .prepared
            return snapshot()
        } catch {
            return isCurrent(graph, next.playback) ? fail(.playbackFailed) : snapshot()
        }
    }

    func enqueue(pcm16Bytes: Data, sequence: UInt64, generation: UInt64) async -> MacSpeechAudioOutputHostSnapshot {
        guard let graph = transport, let current = identity?.playback, generation == current.token,
              let playback, playback.eosDeadline == nil else { return snapshot() }
        guard sequence > playback.lastSequence else { return fail(.outOfOrderSequence) }
        guard !pcm16Bytes.isEmpty, pcm16Bytes.count.isMultiple(of: 2) else { return fail(.invalidPCMByteCount) }
        self.playback?.lastSequence = sequence
        do {
            for offset in stride(from: pcm16Bytes.startIndex, to: pcm16Bytes.endIndex, by: 48000) {
                let slice = pcm16Bytes.subdata(in: offset ..< min(pcm16Bytes.endIndex, offset + 48000))
                try await waitForPlaybackSpace(graph, current, bytes: slice.count) {
                    try await graph.enqueuePlayback(slice, identity: current)
                }
            }
            #if DEBUG && (APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED || NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST)
                if self.playback?.lastSequence == sequence {
                    acousticEvidence.recordPlaybackEnqueued(
                        sequence: sequence, playback: current, firstByte: counters.byteCount, byteCount: pcm16Bytes.count
                    )
                }
            #endif
            counters.chunkCount += 1
            counters.byteCount += pcm16Bytes.count
            return snapshot()
        } catch {
            return isCurrent(graph, current) ? fail(.playbackFailed) : snapshot()
        }
    }

    func start() -> MacSpeechAudioOutputHostSnapshot { snapshot() }

    func finishProviderResponse(generation: UInt64) async -> MacSpeechAudioOutputHostSnapshot {
        guard let graph = transport, let current = identity?.playback, generation == current.token,
              let playback, playback.eosDeadline == nil else { return snapshot() }
        do {
            try await waitForPlaybackSpace(graph, current, bytes: 0) {
                try await graph.finishPlayback(identity: current)
            }
            outputState = .draining
            self.playback?.eosDeadline = DispatchTime.now().uptimeNanoseconds &+ playbackTimeout
            return snapshot()
        } catch {
            return isCurrent(graph, current) ? fail(.playbackFailed) : snapshot()
        }
    }

    func clear() async -> MacSpeechAudioOutputHostSnapshot {
        await clearPlayback(confirmedAt: DispatchTime.now().uptimeNanoseconds)
    }

    func clearConfirmed(
        _ decision: RealtimeConfirmedInterruption, confirmedAt: UInt64
    ) async -> MacSpeechAudioOutputHostSnapshot {
        guard session == decision.interruptedIdentity, decision.hostCommand == .clearPlayback,
              playback?.response.turnID == decision.turnID, playback?.response.responseID == decision.responseID
        else { return snapshot(failing: .staleGeneration) }
        return await clearPlayback(confirmedAt: confirmedAt)
    }

    func close() async -> MacSpeechAudioOutputHostSnapshot {
        #if DEBUG && (APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED || NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST)
            acousticEvidence.stop(.sessionClosed)
        #endif
        let graph = transport
        #if DEBUG
            let closingConfiguration = configurationSerial
        #endif
        transport = nil
        session = nil
        identity = nil
        preparedGeneration = nil
        serviceTask?.cancel()
        serviceTask = nil
        playback = nil
        facts.invalidatePlayback()
        eventSink = nil
        facts.discardCapture(forTransition: false)
        counters.outputDevice = .unavailable
        outputState = .closed
        outputError = nil
        await graph?.close()
        #if DEBUG
            if let readback = await graph?.readback(), configurationSerial == closingConfiguration, transport == nil {
                sealedTransport = readback
            }
        #endif
        return snapshot()
    }
}

private extension MacSpeechNativeRealtimeSession {
    func clearPlayback(confirmedAt: UInt64) async -> MacSpeechAudioOutputHostSnapshot {
        guard let graph = transport, let current = identity, playback != nil,
              current.playback.token < UInt64.max, current.playback.epoch < UInt64.max else {
            return fail(.invalidState)
        }
        lastClearCompletedAtNanoseconds = nil
        let next = current.replacingPlayback(cancelled: true)
        playback = nil
        identity = next
        facts.invalidatePlayback()
        do {
            try await graph.cancelPlayback(current.playback, replacingWith: next.playback)
            while transport === graph, identity?.playback == next.playback {
                let progress = try await graph.progress()
                guard transport === graph, identity?.playback == next.playback else { return snapshot() }
                let now = DispatchTime.now().uptimeNanoseconds
                guard now >= confirmedAt, now - confirmedAt <= 50_000_000 else { return fail(.consumerTimedOut) }
                if progress.token == next.playback.token, progress.renderClearAcknowledged {
                    lastClearCompletedAtNanoseconds = now
                    outputState = .prepared
                    return snapshot()
                }
                try await Task.sleep(for: .milliseconds(1))
            }
            return snapshot()
        } catch {
            return transport === graph ? fail(.playbackFailed) : snapshot()
        }
    }

    func waitForPlaybackSpace(
        _ graph: AppleNativeVoiceTransport, _ expected: NativeVoiceIdentity.Playback, bytes: Int,
        accepting: @escaping @Sendable () async throws -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds &+ MacSpeechAudioOutputHost.consumerWatchdogNanoseconds(
            inFlightByteCount: bytes, safetyMarginNanoseconds: playbackTimeout
        )
        while isCurrent(graph, expected), !Task.isCancelled {
            let accepted = try await accepting()
            guard isCurrent(graph, expected), !Task.isCancelled else { break }
            if accepted { return }
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw MacSpeechAudioOutputHostError.consumerTimedOut
            }
            counters.pressureWaits += 1
            try await Task.sleep(for: .milliseconds(2))
        }
        throw NativeVoiceTransportError.staleIdentity
    }

    func isCurrent(_ graph: AppleNativeVoiceTransport, _ expected: NativeVoiceIdentity.Playback) -> Bool {
        transport === graph && identity?.playback == expected && playback != nil
    }

    func installService(
        _ graph: AppleNativeVoiceTransport, failed: @escaping @Sendable (String) async -> Void
    ) {
        serviceTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                guard await self.service(graph, failed: failed) else { return }
                do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
            }
        }
    }

    func service(
        _ graph: AppleNativeVoiceTransport, failed: @escaping @Sendable (String) async -> Void
    ) async -> Bool {
        do {
            let batch = try await graph.bridgeService(maxCaptureFrames: 8192)
            guard transport === graph, let identity else { return false }
            facts.bufferCapture(batch.packets, expected: identity.capture)
            #if DEBUG
                facts.recordSource(batch.render, expected: identity.playback)
            #endif
            try await observeRender(batch, playback: identity.playback)
            return transport === graph
        } catch {
            guard transport === graph else { return false }
            let reason = (error as? NativeVoiceSessionError) == .permission
                ? "microphone_permission_revoked" : "native_audio_transport_failed"
            #if DEBUG
                terminalReason = reason
            #endif
            _ = await close()
            Task { await failed(reason) }
            return false
        }
    }

    func observeRender(
        _ batch: AppleNativeVoiceTransport.ServiceBatch, playback expected: NativeVoiceIdentity.Playback
    ) async throws {
        guard batch.progress.token == expected.token, let active = playback else { return }
        if facts.accept(batch, expected: expected), !active.started {
            playback?.started = true
            if outputState == .prepared { outputState = .playing }
            await publish(.playbackStarted, token: expected.token)
        }
        guard identity?.playback == expected, playback != nil else { return }
        if batch.progress.renderHandoff, outputState == .draining {
            playback = nil
            facts.invalidatePlayback()
            outputState = .completed
            await publish(.playbackCompleted, token: expected.token, handoff: true)
        } else if let deadline = playback?.eosDeadline, DispatchTime.now().uptimeNanoseconds >= deadline {
            throw MacSpeechAudioOutputHostError.consumerTimedOut
        }
    }

    func publish(_ kind: MacSpeechAudioOutputEventKind, token: UInt64, handoff: Bool = false) async {
        eventOrdinal &+= 1
        await eventSink?(MacSpeechAudioOutputEvent(
            ordinal: eventOrdinal, kind: kind, generation: token, sequence: nil, error: nil, isSourceHandoff: handoff
        ))
    }

    func fail(_ error: MacSpeechAudioOutputHostError) -> MacSpeechAudioOutputHostSnapshot {
        outputState = .failed
        outputError = error
        return snapshot()
    }

    func snapshot(failing failure: MacSpeechAudioOutputHostError? = nil) -> MacSpeechAudioOutputHostSnapshot {
        .nativeVoiceOutput(
            state: failure == nil ? outputState : .failed, token: identity?.playback.token ?? 0,
            counters: counters, started: playback?.started == true, error: failure ?? outputError
        )
    }
}

extension MacSpeechNativeRealtimeSession {
    #if DEBUG
        func nativeVoiceDiagnosticReadback() async -> MacSpeechNativeVoiceDiagnosticReadback {
            let graph = transport
            let observed = await graph?.readback()
            return facts.diagnosticReadback(
                transport: graph === transport ? observed ?? sealedTransport : sealedTransport,
                sealed: transport == nil && sealedTransport != nil,
                terminalReason: terminalReason, clearedAt: lastClearCompletedAtNanoseconds)
        }
    #endif

    func acousticMetrics(for frame: MacSpeechAudioFrame) -> RealtimeAcousticMetrics? {
        guard let identity else { return nil }
        return facts.metrics(
            for: frame.sequenceNumber, capture: identity.capture, playback: playback == nil ? nil : identity.playback
        )
    }

    func matchesAcousticObservation(_ observation: RealtimeAcousticObservation) async -> Bool {
        guard let graph = transport, let expected = identity, playback != nil,
              observation.identity.session == session,
              observation.identity.captureGeneration == expected.capture.generation,
              let progress = try? await graph.progress(), progress.token == expected.playback.token,
              transport === graph, identity?.playback == expected.playback, playback != nil else { return false }
        return facts.matches(observation.metrics, playback: expected.playback)
    }
}
