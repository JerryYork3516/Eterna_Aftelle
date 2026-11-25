#if NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST
    import Synchronization

    private final nonisolated class EvidenceTestClock: Sendable {
        let time = Atomic<UInt64>(10)
    }

    private extension RealtimeInterruptionEvidenceTests {
        static func runNativeVoiceAcousticEvidence() async throws {
            testAcousticEvidenceScopeAndLimits()
            testAcousticEvidenceDeadlineAndRevocation()
            testAcousticEvidenceBindingContention()
            try await testAcousticEvidenceBridgeAndSeal()
            print("native_voice_acoustic_evidence_checks=\(checks)")
            print("native_voice_acoustic_evidence_device_access=ZERO")
        }

        static func testAcousticEvidenceBindingContention() {
            let (target, capture) = acousticEvidenceTestIdentity()
            let recorder = MacSpeechNativeAcousticEvidence()
            expect(recorder.arm(), "one grant is ready")
            recorder.holdLockForTesting { recorder.bind(target, capture: capture) }
            expect(
                recorder.phase == .ended && recorder.takeForSave() == nil,
                "contended binding ends the evidence grant without waiting on audio startup")
        }

        static func acousticEvidenceTestIdentity() -> (RealtimeBrainSessionIdentity, NativeVoiceIdentity.Capture) {
            let target = RealtimeBrainSessionIdentity(
                residentID: "synthetic", runtimeSessionID: "local", brainLeaseID: .init(), routeEpoch: 1, generation: 3
            )
            let capture = NativeVoiceIdentity.Capture(
                authority: .init(runtimeGeneration: 3, routeEpoch: 1, configurationID: 5), generation: 5, token: 1
            )
            return (target, capture)
        }

        static func testAcousticEvidenceScopeAndLimits() {
            let (target, capture) = acousticEvidenceTestIdentity()
            let clock = EvidenceTestClock()
            let recorder = MacSpeechNativeAcousticEvidence(
                limits: .init(durationNanoseconds: 100, pcmBytes: 1920, packetCount: 2),
                now: { clock.time.load(ordering: .relaxed) }
            )
            let frame = RealtimeBrainAudioFrame(
                identity: target, sequence: 5, timestampNanoseconds: 200_000_000,
                format: .init(encoding: .pcm16LittleEndian, sampleRate: 24_000, channelCount: 1),
                provenance: .acousticEchoProcessed, bytes: Data(repeating: 3, count: 960)
            )
            recorder.bind(target, capture: capture)
            expect(
                recorder.phase == .off && recorder.recordUplink(frame, captureSequence: 6) == nil,
                "device compilation alone does not open evidence collection")
            expect(
                recorder.arm() && !recorder.arm() && recorder.recordUplink(frame, captureSequence: 6) == nil,
                "the distinct grant is single-use and starts without a bound session")
            recorder.bind(target, capture: capture)
            let stale = RealtimeBrainAudioFrame(
                identity: .init(
                    residentID: target.residentID, runtimeSessionID: target.runtimeSessionID,
                    brainLeaseID: target.brainLeaseID, routeEpoch: target.routeEpoch, generation: 4),
                sequence: 5, timestampNanoseconds: 10, format: frame.format,
                provenance: .acousticEchoProcessed, bytes: frame.bytes
            )
            expect(recorder.recordUplink(stale, captureSequence: 1) == nil, "N+1 data cannot enter the prior grant")
            recorder.holdLockForTesting {
                expect(
                    recorder.recordUplink(frame, captureSequence: 6) == nil,
                    "a contended offer returns immediately")
            }
            recorder.rememberCapture(
                [
                    6: NativeVoiceCapturePacket(
                        bytes: frame.bytes, identity: capture, segment: 2, sampleCount: 480,
                        hostTimeNanoseconds: 100, timingStatus: .valid
                    )
                ], playback: nil)
            let first = recorder.recordUplink(frame, captureSequence: 6)!
            recorder.completeUplink(first, result: .failure(.invalidIdentity))
            let second = recorder.recordUplink(frame, captureSequence: 7)!
            expect(recorder.takeForSave() == nil, "an active grant cannot be written")
            expect(
                recorder.recordUplink(frame, captureSequence: 8) == nil && recorder.phase == .ended,
                "capacity closes evidence while leaving the audio caller free to continue")
            recorder.completeUplink(second, result: .success(()))
            verifyCapacitySeal(recorder)
        }

        static func verifyCapacitySeal(_ recorder: MacSpeechNativeAcousticEvidence) {
            let sealed = recorder.takeForSave()!
            expect(
                sealed.endReason == "capacityLimit" && sealed.pcmBytes == 1920 && sealed.packets.count == 2
                    && sealed.packets[0].captureContent?.sampleCount24k == 480
                    && sealed.packets[0].disposition == .runtimeAppendFailed
                    && sealed.packets[1].disposition == .pending,
                "the bounded snapshot keeps exact PCM, original content coordinates, and unresolved results")
            expect(
                sealed.evidenceLoss.rejectedIdentity == 1 && sealed.evidenceLoss.capacityRejected == 1
                    && sealed.evidenceLoss.contendedPacketOffers == 1 && sealed.evidenceLoss.missingCaptureContent == 1
                    && sealed.evidenceLoss.uplinkOffers == 5, "evidence gaps are counted independently")
            expect(recorder.takeForSave() == nil && !recorder.revoke(), "the explicitly claimed seal has one writer")
            recorder.finishSave(succeeded: false)
            expect(
                recorder.phase == .ended && recorder.takeForSave()?.runID == sealed.runID,
                "a failed seal can retry the same snapshot")
            recorder.finishSave(succeeded: true)
            expect(recorder.phase == .saved && !recorder.arm(), "successful seal spends the grant")

        }

        static func testAcousticEvidenceDeadlineAndRevocation() {
            let (target, capture) = acousticEvidenceTestIdentity()
            let clock = EvidenceTestClock()
            let frame = RealtimeBrainAudioFrame(
                identity: target, sequence: 5, timestampNanoseconds: 200_000_000,
                format: .init(encoding: .pcm16LittleEndian, sampleRate: 24_000, channelCount: 1),
                provenance: .acousticEchoProcessed, bytes: Data(repeating: 3, count: 960)
            )
            let timed = MacSpeechNativeAcousticEvidence(
                limits: .init(durationNanoseconds: 20), now: { clock.time.load(ordering: .relaxed) }
            )
            expect(timed.arm(), "time-bounded evidence can be independently granted")
            timed.bind(target, capture: capture)
            expect(timed.recordUplink(frame, captureSequence: 7) != nil, "valid offer under deadline")
            clock.time.store(30, ordering: .relaxed)
            expect(timed.recordUplink(frame, captureSequence: 8) == nil, "deadline is exclusive")
            expect(timed.takeForSave()?.endReason == "durationLimit", "the duration cutoff is recorded")
            let revoked = MacSpeechNativeAcousticEvidence()
            expect(revoked.arm(), "a separate local recorder can be granted")
            revoked.bind(target, capture: capture)
            expect(revoked.recordUplink(frame, captureSequence: 7) != nil, "authorized data rests in memory")
            revoked.holdLockForTesting {
                expect(revoked.revoke(), "revocation does not wait on the writer lock")
            }
            revoked.discardRevoked()
            expect(
                revoked.phase == .revoked && revoked.takeForSave() == nil
                    && revoked.recordUplink(frame, captureSequence: 8) == nil && !revoked.arm(),
                "revocation rejects new PCM and destroys unsaved evidence")
        }

        private struct EvidenceStack {
            let controller: AppController
            let candidate: MacSpeechNativeRealtimeSession
            let hardware: FakeVoiceHardware
            let provider: R81RealtimeProvider
        }

        private static func makeAcousticEvidenceStack() -> EvidenceStack {
            let hardware = FakeVoiceHardware()
            let candidate = MacSpeechNativeRealtimeSession(makeTransport: { hardware.makeTransport() })
            let provider = R81RealtimeProvider()
            let router = ProviderRouter(
                credentialReader: R81CredentialReader(), realtimeResidentBrainProvider: provider
            )
            let runtime = RuntimeCore(
                executionEngine: ExecutionEngine(providerRouter: router), providerRouter: router,
                sessionStore: SessionStore()
            )
            let controller = AppController(
                orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
                speechAudioHost: MacSpeechAudioHost(
                    authorizationProvider: R81AuthorizationProvider(),
                    capture: R81AudioCapture(acousticEchoHost: MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)),
                    deviceMonitor: R81DeviceMonitor()
                ),
                speechAudioOutputHost: MacSpeechAudioOutputHost(
                    player: FakeMacSpeechAudioOutputPlayer(), deviceMonitor: FakeMacSpeechOutputDeviceMonitor()
                ),
                realtimeAudioBackend: .appleNativeCandidate(candidate)
            )
            let armed = candidate.acousticEvidence.arm()
            expect(armed, "independent grant precedes all capture")
            return .init(controller: controller, candidate: candidate, hardware: hardware, provider: provider)
        }

        static func testAcousticEvidenceBridgeAndSeal() async throws {
            let stack = makeAcousticEvidenceStack()
            let controller = stack.controller
            let candidate = stack.candidate
            let provider = stack.provider
            let fixtureRoot = URL(fileURLWithPath: "apps/macos/Aftelle/Fixtures/Stage7_5")
            let fixture = fixtureRoot.appendingPathComponent("resident_stage7_5_fixture_v1.digital_resident")
            controller.debugImportResident(from: fixture)
            await controller.startRealtimeResidentBrainRoute()
            await waitUntil("synthetic native route active for evidence") {
                controller.realtimeFullDuplexSpeechStatus.phase == .listening
            }
            let session = await provider.latestSession()!
            let engine = stack.hardware.update { $0.graphs[0] }
            let target = R81Target(session: session, turnID: .init(), responseID: .init(), contextRevision: 1)
            let resident = nativeResidentPCM()
            await provider.enqueue(
                .init(
                    identity: .init(
                        session: session, turnID: target.turnID, responseID: nil, contextRevision: 1
                    ), sequence: 2, kind: .userTranscriptFinal("synthetic witness")))
            await provider.enqueue(
                .init(
                    identity: eventIdentity(target), sequence: 3, kind: .residentAudioDelta(resident)
                ))
            await waitUntil("provider reference reaches the non-realtime enqueue boundary") {
                _ = engine.render(211, sampleTime: 0, hostTime: mach_absolute_time(), flags: 3)
                return controller.realtimeFullDuplexSpeechStatus.phase == .speaking
            }
            try await feedNativeCapture(engine, packets: 6, samplePosition: 0, hostStart: monotonicNow())
            await waitUntil("Runtime receives the synthetic uplink") { await provider.audioCount() >= 3 }
            let forwarded = await provider.lastAudioFrame()!
            await waitUntil("the offered PCM has its Runtime result") {
                candidate.acousticEvidence.hasCompletedUplinkForTesting(forwarded.sequence)
            }
            await controller.stopRealtimeFullDuplexSpeech()
            let outcome = candidate.acousticEvidence.takeForSave()!
            verifyBridgePCM(outcome, forwarded: forwarded, resident: resident, response: target.responseID)
            expect(
                outcome.endReason == "sessionClosed" && engine.read().starts == 1 && engine.read().stops == 1,
                "session close ends acquisition without adding an Engine lifecycle")
            let diagnostics = await candidate.nativeVoiceDiagnosticReadback()
            expect(
                diagnostics.sealed && diagnostics.transport?.identity.capture == outcome.capture
                    && diagnostics.transport?.lastConsumedSink != nil && diagnostics.lastNonzeroSubmission != nil,
                "sealed P4 technical Source and Sink facts share the recorded configuration")
            try verifyNativeVoiceEvidenceFile(outcome, diagnostics: diagnostics)
            candidate.acousticEvidence.finishSave(succeeded: true)
        }

        static func verifyBridgePCM(
            _ outcome: NativeVoiceEvidenceArchive, forwarded: RealtimeBrainAudioFrame,
            resident: RealtimeBrainAudioDelta, response: RealtimeBrainResponseID
        ) {
            let upstream = outcome.packets.filter { $0.direction == .uplink }
            let downstream = outcome.packets.filter { $0.direction == .providerReference }
            expect(
                upstream.contains {
                    $0.pcm == forwarded.bytes && $0.sequence == forwarded.sequence
                        && $0.disposition == .runtimeAppendSucceeded
                        && $0.captureContent != nil
                }, "the captured bytes are the exact VP-path PCM submitted through the existing Runtime boundary")
            expect(
                downstream.count == 1 && downstream[0].pcm == resident.bytes
                    && downstream[0].responseID == response.rawValue && downstream[0].playbackToken != nil
                    && downstream[0].disposition == .hostEnqueueReturned
                    && downstream[0].hostReturnedToken == downstream[0].playbackToken
                    && downstream[0].providerTimestampNanoseconds == resident.timestampNanoseconds,
                "unmodified Provider bytes have their own timestamp and playback identity")
        }

        static func verifyNativeVoiceEvidenceFile(
            _ outcome: NativeVoiceEvidenceArchive, diagnostics: MacSpeechNativeVoiceDiagnosticReadback
        ) throws {
            let path = try AppController.writeNativeVoiceEvidence(
                outcome, technical: diagnostics, observedAt: monotonicNow()
            )
            let isolatedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]!
            expect(
                path.path.hasPrefix(isolatedHome + "/Library/Caches/"),
                "synthetic save is inside the dedicated isolated home")
            let bytes = try Data(contentsOf: path)
            let manifest = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            let facts = manifest?["technical"] as? [String: Any]
            let evidence = manifest?["evidence"] as? [String: Any]
            let fileRecords = evidence?["packets"] as? [[String: Any]]
            expect(
                facts?["physicalPlayback"] as? String == "UNKNOWN" && manifest?["sampleRate"] as? Int == 24_000
                    && manifest?["technicalReadbackMatchesScope"] as? Bool == true
                    && (manifest?["buildBinarySHA256"] as? String)?.count == 64
                    && fileRecords?.count == outcome.packets.count
                    && (fileRecords?.first?["pcm"] as? String) == outcome.packets.first?.pcm.base64EncodedString(),
                "sealed JSON preserves digital PCM and only admits matching technical facts")
            let manager = FileManager.default
            let folder = path.deletingLastPathComponent()
            let fileMode = try manager.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int
            let folderMode = try manager.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int
            expect(fileMode == 0o600 && folderMode == 0o700, "the single archive is owner-only")
            do {
                _ = try AppController.writeNativeVoiceEvidence(
                    outcome, technical: diagnostics, observedAt: monotonicNow()
                )
                fatalError("duplicate evidence seal overwrote its archive")
            } catch let error as NSError {
                let deniedPath =
                    error.domain == NSCocoaErrorDomain
                    && error.code == CocoaError.Code.fileWriteNoPermission.rawValue
                let existingFile = error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST)
                expect(deniedPath || existingFile, "the private writer refuses a duplicate")
            }
            let sealed = try Data(contentsOf: path)
            let files = try manager.contentsOfDirectory(atPath: folder.path)
            expect(sealed == bytes && files == [path.lastPathComponent], "failed seal leaves one original archive")
        }
    }
#endif
