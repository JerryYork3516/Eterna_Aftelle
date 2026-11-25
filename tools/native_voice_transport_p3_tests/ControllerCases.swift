#if NATIVE_VOICE_P3_OFFLINE_TEST
    import Darwin

    private actor NativeVoiceTestEvents {
        var output: [MacSpeechAudioOutputEvent] = []
        var faults: [String] = []

        func record(_ event: MacSpeechAudioOutputEvent) { output.append(event) }
        func fault(_ reason: String) { faults.append(reason) }
    }

    private extension RealtimeInterruptionEvidenceTests {
        static func runNativeVoiceP3() async throws {
            testNativeVoiceTimingUnavailable()
            try await testNativeVoicePlaybackAndClear()
            try await testNativeVoiceStartupRollback()
            try await testNativeVoiceController()
            print("native_voice_p3_checks=\(checks)")
            print("native_voice_p3_device_access=ZERO")
        }

        static func testNativeVoiceTimingUnavailable() {
            let identity = NativeVoiceIdentity(
                authority: .init(runtimeGeneration: 1, routeEpoch: 2, configurationID: 3),
                captureGeneration: 3, captureToken: 1, playbackEpoch: 1, playbackToken: 2
            )
            var facts = MacSpeechNativeRealtimeFacts()
            facts.deliveredCapture[1] = NativeVoiceCapturePacket(
                bytes: Data(repeating: 2, count: 960), identity: identity.capture, segment: 1, sampleCount: 480,
                hostTimeNanoseconds: monotonicNow(), timingStatus: .invalid
            )
            let reading = facts.metrics(for: 1, capture: identity.capture, playback: identity.playback)!
            expect(reading.captureTimestampNanoseconds == nil && reading.sourceAssessment == .uncertain
                && !reading.sourceGateOpen && !reading.renderReferenceAvailable && reading.erleDecibels == nil,
                "ineligible clock and private Apple facts cannot open acoustic eligibility")
        }

        static func testNativeVoicePlaybackAndClear(verifyCloseout: Bool = false) async throws {
            let hardware = FakeVoiceHardware()
            let adapter = MacSpeechNativeRealtimeSession(makeTransport: { hardware.makeTransport(ringFrames: 1024) })
            let events = NativeVoiceTestEvents()
            let session = RealtimeBrainSessionIdentity(
                residentID: "fake", runtimeSessionID: "test", brainLeaseID: UUID(), routeEpoch: 9, generation: 5
            )
            let next = RealtimeBrainSessionIdentity(
                residentID: session.residentID, runtimeSessionID: session.runtimeSessionID,
                brainLeaseID: session.brainLeaseID, routeEpoch: session.routeEpoch, generation: session.generation + 1
            )
            await adapter.setEventSink { await events.record($0) }
            let captureGeneration = await adapter.reserveCaptureGeneration()!
            let started = try await adapter.startCapture(session: session, generation: captureGeneration) {
                await events.fault($0)
            }
            expect(started.isCapturing, "candidate starts its single Fake Engine")
            let engine = hardware.update { $0.graphs[0] }
            for turn in 0 ..< 2 {
                let target = R81Target(session: session, turnID: .init(), responseID: .init(), contextRevision: 1)
                let prepared = await adapter.preparePlayback(identity: eventIdentity(target))
                expect(prepared.state == .prepared, "new response uses current engine")
                let queued = await adapter.enqueue(pcm16Bytes: audioDelta(sequence: 1).bytes, sequence: 1,
                                                   generation: prepared.generation)
                expect(queued.enqueuedChunkCount == 1, "one Provider chunk enters native SRC")
                let eos = Task { await adapter.finishProviderResponse(generation: prepared.generation) }
                await waitUntil("native EOS handoff round \(turn)") {
                    _ = engine.render(193, sampleTime: Double(turn * 48_000), hostTime: mach_absolute_time(), flags: 3)
                    let snapshot = await adapter.currentSnapshot()
                    return snapshot.state == .completed
                }
                _ = await eos.value
                if verifyCloseout {
                    _ = engine.render(77, sampleTime: Double(turn * 48_000 + 12_000),
                                      hostTime: mach_absolute_time(), flags: 3)
                    await waitUntil("idle callback reaches bounded diagnostic readback") {
                        let facts = try? await nativeVoiceDiagnostic(adapter)
                        return (facts?["lastSource"] as? [String: Any])?["frameCount"] as? Int == 77
                    }
                    try await verifyNativeVoiceHandoff(adapter, generation: prepared.generation)
                }
            }
            let handoffs = await events.output.filter { $0.kind == .playbackCompleted }
            expect(handoffs.count == 2 && handoffs.allSatisfy(\.isSourceHandoff), "EOS is recorded as Source handoff")
            expect(engine.read().starts == 1 && engine.read().stops == 0, "natural EOS leaves the same engine running")

            let third = R81Target(session: session, turnID: .init(), responseID: .init(), contextRevision: 1)
            let prepared = await adapter.preparePlayback(identity: eventIdentity(third))
            let big = Data(repeating: 6, count: 12_000)
            _ = await adapter.enqueue(pcm16Bytes: big, sequence: 1, generation: prepared.generation)
            let backpressured = Task {
                await adapter.enqueue(pcm16Bytes: big, sequence: 2, generation: prepared.generation)
            }
            await waitUntil("old producer is bounded by native ring") {
                await adapter.currentSnapshot().pressureWaitCount > 0
            }
            let decision = RealtimeConfirmedInterruption(
                decisionID: UUID(), interruptedIdentity: session, nextIdentity: next,
                turnID: third.turnID, responseID: third.responseID, hostCommand: .clearPlayback
            )
            let began = monotonicNow()
            let clear = Task { await adapter.clearConfirmed(decision, confirmedAt: began) }
            let lease = engine.read().lease!
            await waitUntil("logical cancellation publishes a new token") {
                nvt_rt_stats(lease.context).active_token > prepared.generation
            }
            let notYetAcknowledged = await adapter.lastClearCompletedAtNanoseconds == nil
            expect(notYetAcknowledged, "clear request is not render confirmation")
            let zeros = engine.render(259, sampleTime: 90_000, hostTime: mach_absolute_time(), flags: 3)
            expect(zeros.allSatisfy { $0 == 0 }, "old queued audio is cleared in Source")
            let cleared = await clear.value
            let completion = await adapter.lastClearCompletedAtNanoseconds
            expect(cleared.state == .prepared && completion.map { $0 - began <= 50_000_000 } == true,
                   "consumer-confirmed clear completes within the contract")
            _ = await backpressured.value
            let duplicate = await adapter.clearConfirmed(decision, confirmedAt: began)
            expect(duplicate.state == .failed && nvt_rt_stats(lease.context).active_token == cleared.generation,
                   "duplicate confirmation has no additional clear effect")
            try await adapter.advanceGeneration(from: session, to: next)
            let stillCapturing = await adapter.isCaptureGenerationActive(captureGeneration)
            expect(stillCapturing && engine.read().starts == 1 && engine.read().stops == 0,
                   "Runtime N+1 advances both fences without rebuilding the graph")
            let stale = await adapter.enqueue(pcm16Bytes: big, sequence: 3, generation: prepared.generation)
            let staleEOS = await adapter.finishProviderResponse(generation: prepared.generation)
            expect(stale.generation == staleEOS.generation && stale.generation > cleared.generation,
                   "late PCM and EOS cannot reactivate the old playback")

            let lateTarget = R81Target(session: next, turnID: .init(), responseID: .init(), contextRevision: 1)
            let latePrepared = await adapter.preparePlayback(identity: eventIdentity(lateTarget))
            _ = await adapter.enqueue(pcm16Bytes: big, sequence: 1, generation: latePrepared.generation)
            let late = RealtimeConfirmedInterruption(
                decisionID: UUID(), interruptedIdentity: next, nextIdentity: next,
                turnID: lateTarget.turnID, responseID: lateTarget.responseID, hostCommand: .clearPlayback
            )
            let timedOut = await adapter.clearConfirmed(late, confirmedAt: monotonicNow() - 60_000_000)
            let missed = await adapter.lastClearCompletedAtNanoseconds
            expect(timedOut.lastError == MacSpeechAudioOutputHostError.consumerTimedOut.rawValue && missed == nil,
                   "clear without timely callback cannot report completion")

            engine.read().configurationChanged?()
            await waitUntil("route fault after capture token rotation") { await events.faults.count == 1 }
            let closed = await adapter.close()
            expect(closed.state == .closed && engine.read().stops == 1, "old graph closes once on route fault")
        }

        static func testNativeVoiceStartupRollback() async throws {
            let hardware = FakeVoiceHardware()
            hardware.update { $0.failure = .watch }
            let adapter = MacSpeechNativeRealtimeSession(makeTransport: { hardware.makeTransport() })
            let session = RealtimeBrainSessionIdentity(
                residentID: "fake", runtimeSessionID: "startup", brainLeaseID: UUID(), routeEpoch: 1, generation: 1
            )
            let prepared = await adapter.reserveCaptureGeneration()!
            do {
                _ = try await adapter.startCapture(session: session, generation: prepared) { _ in }
                fatalError("partial start unexpectedly accepted")
            } catch FakeVoiceFailure.watch {}
            let graph = hardware.update { $0.graphs[0] }
            let generation = await adapter.activeCaptureGeneration()
            expect(generation == nil && graph.read().starts == 1 && graph.read().stops == 1,
                   "partial startup rolls back and leaves no active source")
        }

        static func testNativeVoiceController(verifyCloseout: Bool = false) async throws {
            let hardware = FakeVoiceHardware()
            let adapter = MacSpeechNativeRealtimeSession(makeTransport: { hardware.makeTransport() })
            let provider = R81RealtimeProvider()
            await provider.enableInterruptReceiveWake()
            let router = ProviderRouter(credentialReader: R81CredentialReader(), realtimeResidentBrainProvider: provider)
            let runtime = RuntimeCore(
                executionEngine: ExecutionEngine(providerRouter: router), providerRouter: router, sessionStore: SessionStore()
            )
            let legacyCapture = R81AudioCapture(acousticEchoHost: MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing))
            let legacyPlayer = FakeMacSpeechAudioOutputPlayer()
            let controller = AppController(
                orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
                speechAudioHost: MacSpeechAudioHost(
                    authorizationProvider: R81AuthorizationProvider(), capture: legacyCapture, deviceMonitor: R81DeviceMonitor()
                ),
                speechAudioOutputHost: MacSpeechAudioOutputHost(
                    player: legacyPlayer, deviceMonitor: FakeMacSpeechOutputDeviceMonitor()
                ),
                realtimeAudioBackend: .appleNativeCandidate(adapter)
            )
            let fixture = URL(fileURLWithPath: "apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident")
            controller.debugImportResident(from: fixture)
            expect(controller.isResidentTextInputAvailable, "controller imports the offline fixture")
            await controller.startRealtimeResidentBrainRoute()
            await waitUntil("native Controller route listens") {
                controller.realtimeFullDuplexSpeechStatus.phase == .listening
            }
            let session = await provider.latestSession()!
            let target = R81Target(session: session, turnID: .init(), responseID: .init(), contextRevision: 1)
            let engine = hardware.update { $0.graphs[0] }
            let renderer = Task.detached {
                var position: Double = 0
                while !Task.isCancelled {
                    _ = engine.render(211, sampleTime: position, hostTime: mach_absolute_time(), flags: 3)
                    position += 211
                    do { try await Task.sleep(for: .milliseconds(3)) } catch { return }
                }
            }
            defer { renderer.cancel() }
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: .init(session: session, turnID: target.turnID, responseID: nil, contextRevision: 1),
                sequence: 2, kind: .userTranscriptFinal("synthetic voice test")
            ))
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: eventIdentity(target), sequence: 3, kind: .residentAudioDelta(nativeResidentPCM())
            ))
            await waitUntil("Source nonzero render drives Controller speaking") {
                controller.realtimeFullDuplexSpeechStatus.phase == .speaking
            }
            let source = await adapter.latestNonzeroRender!
            expect(source.nonzeroFrames > 0 && source.frameCount == 211 && source.sampleTime != nil
                && source.playback.authority.runtimeGeneration == session.generation
                && source.playback.authority.routeEpoch == session.routeEpoch,
                "Source frame facts carry the live Runtime and callback identity")
            expect(legacyCapture.startCount == 0 && legacyPlayer.startCount == 0,
                   "the explicit candidate drives both Bridges without the frozen audio backend")

            let capturedAt = monotonicNow()
            await adapter.setShadowEvidence { capture, render in shadowMetrics(capture, render, nearEnd: false) }
            try await feedNativeCapture(engine, packets: 5, samplePosition: 0, hostStart: capturedAt)
            await waitUntil("provider receives captured PCM") { await provider.audioCount() >= 3 }
            let input = await provider.lastAudioFrame()!
            expect(input.bytes.count == 960 && input.identity == session && input.bytes.contains { $0 != 0 },
                   "24 kHz converted PCM crosses InputBridge and Runtime into the Fake Provider")
            await waitUntil("pure echo receives negative classification") {
                runtime.realtimeAcousticObservationDebugSnapshot().records.contains {
                    $0.observation.classification == .farEndDominant && $0.disposition == .observed
                }
            }
            let proposalReceiveCount = await provider.receiveCount()
            await provider.enqueue(proposalEvent(target, sequence: 4))
            await waitUntil("semantic proposal consumed for noise control") {
                await provider.receiveCount() > proposalReceiveCount
            }
            let echoInterrupts = await provider.interruptCount()
            expect(echoInterrupts == 0, "echo-only evidence plus a semantic proposal does not interrupt")

            await provider.holdInterrupt()
            await adapter.setShadowEvidence { capture, render in shadowMetrics(capture, render, nearEnd: true) }
            try await feedNativeCapture(
                engine, packets: 5, samplePosition: 5 * 882, hostStart: capturedAt + 100_000_000, includeNearEnd: true
            )
            for _ in 0 ..< 400 {
                if await provider.isInterruptHeld(), await adapter.lastClearCompletedAtNanoseconds != nil { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            let held = await provider.isInterruptHeld()
            let cleared = await adapter.lastClearCompletedAtNanoseconds
            if !held || cleared == nil {
                let record = runtime.realtimeAcousticObservationDebugSnapshot().records.last
                let evidence = runtime.realtimeInterruptionEvidenceDebugSnapshot()
                let metrics = await adapter.acousticMetricsForTesting()
                let state = controller.realtimeFullDuplexSpeechStatus
                let interrupts = await provider.interruptCount()
                let message = "p3 shadow debug: phase=\(state.phase) error=\(String(describing: state.lastErrorCode)) "
                    + "source=\(String(describing: metrics?.sourceAssessment)) "
                    + "captureTime=\(metrics?.captureTimestampNanoseconds != nil) "
                    + "observation=\(String(describing: record?.observation.classification)) "
                    + "disposition=\(String(describing: record?.disposition)) "
                    + "acoustic=\(evidence.hasAcousticEvidence) semantic=\(evidence.hasSemanticEvidence) "
                    + "interrupts=\(interrupts) clear=\(cleared != nil)\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
            expect(held && cleared != nil, "confirmed cancel obtains Source clear before Provider ACK")
            let timing = runtime.realtimeInterruptionTimingForTesting()!
            let clearAt = await adapter.lastClearCompletedAtNanoseconds!
            expect(timing.interruptedIdentity == session && clearAt >= timing.confirmedAtNanoseconds
                && clearAt - timing.confirmedAtNanoseconds <= 50_000_000,
                "the original Runtime confirmation to actual Source clear remains inside 50ms")
            print("native_voice_p3_confirmed_to_clear_ns=\(clearAt - timing.confirmedAtNanoseconds)")
            await provider.releaseInterrupt()
            await waitUntil("both Bridges rebind to N+1") {
                controller.formalSpeechRouteDebugSnapshot.phase == .listening
                    && controller.formalSpeechRouteDebugSnapshot.generation == session.generation + 1
                    && controller.realtimeBrainInputBridgeSnapshot.hasActivePump
                    && controller.realtimeBrainOutputBridgeSnapshot.hasActiveReceiveLoop
            }
            let oldWireReceiveCount = await provider.receiveCount()
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: eventIdentity(target), sequence: 5, kind: .residentAudioDelta(audioDelta(sequence: 2))
            ))
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: eventIdentity(target), sequence: 6, kind: .residentSpeakingStopped
            ))
            await waitUntil("late wire audio and EOS receive no native playback target") {
                await provider.receiveCount() >= oldWireReceiveCount + 2
            }
            let afterOldWire = await adapter.currentSnapshot()
            expect(afterOldWire.state == .prepared, "old Runtime PCM and EOS never arm native rendering")
            if verifyCloseout {
                try await verifyNativeVoiceContentFence(adapter, engine: engine, provider: provider)
            }
            let newStart = monotonicNow()
            try await feedNativeCapture(engine, packets: 5, samplePosition: 10 * 882, hostStart: newStart)
            await waitUntil("N+1 packets cross the same graph") {
                await provider.lastAudioFrame()?.identity.generation == session.generation + 1
            }
            let interrupts = await provider.interruptCount()
            expect(interrupts == 1 && engine.read().starts == 1 && engine.read().stops == 0,
                   "only Runtime confirmed once, reusing the session graph")
            if verifyCloseout {
                let next = await provider.lastAudioFrame()!.identity
                try await verifyNativeVoiceControllerEOS(adapter, provider: provider, controller: controller, next: next)
            }
            hardware.update { $0.authorized = false }
            await waitUntil("permission revoke closes Runtime and audio") {
                let closeCount = await provider.closeCount()
                return closeCount == 1 && controller.realtimeFullDuplexSpeechStatus.phase == .failed
            }
            expect(engine.read().stops == 1, "permission revoke retires the engine")
            if verifyCloseout {
                try await verifyNativeVoiceSealed(adapter, controller: controller, generation: session.generation + 1)
            }
        }

        nonisolated static func shadowMetrics(
            _ capture: NativeVoiceCapturePacket, _ render: NativeVoiceRenderFact, nearEnd: Bool
        ) -> RealtimeAcousticMetrics {
            .init(
                residentPlaybackSequence: render.playback.token, residentPlaybackActive: true,
                lastAudibleResidentRenderTimestampNanoseconds: render.hostTimeNanoseconds, renderReferenceAvailable: true,
                renderReferenceRMS: 0.2, rawCaptureRMS: 0.3, aecOutputRMS: nearEnd ? 0.2 : 0.001,
                linearAECOutputRMS: nearEnd ? 0.2 : 0.001, renderCaptureCorrelation: nearEnd ? 0.1 : 0.9,
                residualRenderCorrelation: 0.1, linearRenderCorrelation: 0.1,
                captureTimestampNanoseconds: capture.hostTimeNanoseconds, renderTimestampNanoseconds: render.hostTimeNanoseconds,
                sourceAlignmentDelayMilliseconds: nil, estimatedDelayMilliseconds: nil,
                erlDecibels: nil, erleDecibels: nil, renderCaptureSkewFrames: nil,
                driftState: .unknown, sourceAssessment: nearEnd ? .doubleTalk : .echoOnly,
                sourceGateOpen: nearEnd, sourceGateEpoch: nearEnd ? 1 : 0, aecActive: true,
                renderCaptureIsolationEstablished: true, sourceAlignmentLocked: false,
                routeStable: true, inputDeviceAvailable: true, outputDeviceAvailable: true
            )
        }

        static func feedNativeCapture(
            _ engine: FakeVoiceEngine, packets: Int, samplePosition: Int, hostStart: UInt64,
            includeNearEnd: Bool = false
        ) async throws {
            var timebase = mach_timebase_info_data_t()
            expect(mach_timebase_info(&timebase) == KERN_SUCCESS, "Fake capture uses callback clock coordinates")
            for index in 0 ..< packets {
                let ns = hostStart + UInt64(index) * 20_000_000
                while monotonicNow() < ns { try await Task.sleep(for: .milliseconds(1)) }
                let ticks = UInt64(Double(ns) * Double(timebase.denom) / Double(timebase.numer))
                let input = (0 ..< 882).map { offset in
                    let seconds = Double(samplePosition + index * 882 + offset) / 44_100.0
                    let echo = sin(seconds * 2 * .pi * 440) * 0.2
                    let nearEnd = includeNearEnd ? sin(seconds * 2 * .pi * 710) * 0.24 : 0
                    return Float(echo + nearEnd)
                }
                engine.capture(input, sampleTime: samplePosition + index * 882, hostTime: ticks)
            }
        }

        static func nativeResidentPCM() -> RealtimeBrainAudioDelta {
            let samples = (0 ..< 480).map { sample in
                Int16(sin(Double(sample) * 2 * .pi * 440 / 24_000.0) * 6553).littleEndian
            }
            return RealtimeBrainAudioDelta(
                sequence: 1, timestampNanoseconds: 20_000_000,
                format: .init(encoding: .pcm16LittleEndian, sampleRate: 24_000, channelCount: 1),
                provenance: .providerGenerated, bytes: samples.withUnsafeBytes { Data($0) }
            )
        }
    }
#endif
