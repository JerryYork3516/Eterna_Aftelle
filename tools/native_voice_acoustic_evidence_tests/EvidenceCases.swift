#if NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST
    import Synchronization

    private final nonisolated class EvidenceTestClock: Sendable {
        let time = Atomic<UInt64>(10)
    }

    private final nonisolated class EvidenceSealGate: Sendable {
        let arrived = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)

        func stopWriter() {
            arrived.signal()
            precondition(proceed.wait(timeout: .now() + 15) == .success, "seal test gate timed out")
        }
    }

    private nonisolated struct EvidenceSealFixture: Sendable {
        let recorder: MacSpeechNativeAcousticEvidence
        let archive: NativeVoiceEvidenceArchive

        static var directory: URL {
            URL(fileURLWithPath: ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]!, isDirectory: true)
                .appendingPathComponent("Library/Caches/com.eterna.aftelle.debug-native-voice-evidence", isDirectory: true)
        }

        var directory: URL { Self.directory }

        var destination: URL { directory.appendingPathComponent("run-\(archive.runID.uuidString).json") }

        func save() throws -> URL {
            try AppController.writeNativeVoiceEvidence(
                archive, recorder: recorder, technical: .init(
                    sealed: false, terminalReason: nil, transport: nil, captureQueue: .init(),
                    lastSource: nil, lastNonzeroSubmission: nil, lastDigitalHandoff: nil, lastClearObservedAtNanoseconds: nil
                ), observedAt: 0
            )
        }
    }

    private extension RealtimeInterruptionEvidenceTests {
        static func runNativeVoiceAcousticEvidence() async throws {
            if let mode = ProcessInfo.processInfo.environment[AppController.nativeVoiceEvidenceMultiRecoveryTestKey] {
                if mode == "directory-suite" {
                    try testDirectoryEnumeration()
                    return
                }
                if ["directory-read-eio", "directory-open-emfile", "directory-close-eio"].contains(mode) {
                    let code = mode == "directory-open-emfile" ? EMFILE : EIO
                    expectRecoveryDeniesGrant(domain: NSPOSIXErrorDomain, code: Int(code))
                    let tag = mode.replacingOccurrences(of: "-", with: "_")
                    print("native_voice_evidence_\(tag)_authorization_gate=PASS")
                    return
                }
                if mode == "suite" {
                    try runMultiMarkerRecoveryCases()
                } else {
                    try AppController.recoverNativeVoiceEvidence()
                }
                return
            }
            if ProcessInfo.processInfo.environment[NativeVoiceEvidenceRevocationStep.testEnvironmentKey] != nil {
                let fixture = makeEvidenceSealFixture()
                _ = try fixture.save()
                _ = try fixture.recorder.revoke()
                fatalError("revocation test child missed its exit checkpoint")
            }
            testAcousticEvidenceScopeAndLimits()
            testAcousticEvidenceDeadlineAndRevocation()
            testAcousticEvidenceBindingContention()
            testAcousticEvidencePlaybackMapping()
            try await testAcousticEvidenceBridgeAndSeal()
            try await testSealRevocationRaces()
            try testPublishedRevocationCrashRecovery()
            try testRevocationRecoveryIdentityChecks()
            try testSealFailureAndRecovery()
            print("native_voice_acoustic_evidence_checks=\(checks)")
            print("native_voice_acoustic_evidence_device_access=ZERO")
            try runMultiMarkerRecoveryInTemporaryDirectory()
            try runDirectoryEnumerationInTemporaryDirectory()
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
            expect(recorder.takeForSave() == nil, "the explicitly claimed seal has one writer")
            try! recorder.abandonSeal()
            expect(
                recorder.phase == .ended && recorder.takeForSave()?.runID == sealed.runID,
                "a failed seal can retry the same snapshot")
            let revoked = try! recorder.revoke()
            expect(revoked && recorder.phase == .revoked && !recorder.arm(), "a claimed seal can still be revoked")
            recorder.discardRevoked()
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
                let accepted = try! revoked.revoke()
                expect(accepted, "revocation does not wait on the capture lock")
            }
            revoked.discardRevoked()
            expect(
                revoked.phase == .revoked && revoked.takeForSave() == nil
                    && revoked.recordUplink(frame, captureSequence: 8) == nil && !revoked.arm(),
                "revocation rejects new PCM and destroys unsaved evidence")
        }

        static func testAcousticEvidencePlaybackMapping() {
            let (target, capture) = acousticEvidenceTestIdentity()
            let recorder = MacSpeechNativeAcousticEvidence()
            expect(recorder.arm(), "one playback evidence scope")
            recorder.bind(target, capture: capture)
            let event = RealtimeBrainEventIdentity(
                session: target, turnID: .init(), responseID: .init(), contextRevision: 1
            )
            let resident = nativeResidentPCM()
            let playback = NativeVoiceIdentity.Playback(authority: capture.authority, epoch: 2, token: 3)
            let wrongConfiguration = NativeVoiceIdentity.Playback(
                authority: .init(runtimeGeneration: target.generation, routeEpoch: target.routeEpoch, configurationID: 9),
                epoch: playback.epoch, token: playback.token
            )
            let first = recorder.recordProvider(resident, identity: event, playbackToken: playback.token)!
            recorder.completeProvider(first, snapshot: .initial)
            recorder.recordPlaybackEnqueued(
                sequence: resident.sequence, playback: wrongConfiguration, firstByte: 0, byteCount: resident.bytes.count
            )
            let next = RealtimeBrainAudioDelta(
                sequence: resident.sequence + 1, timestampNanoseconds: 20_000_000,
                format: resident.format, provenance: resident.provenance, bytes: resident.bytes
            )
            _ = recorder.recordProvider(next, identity: event, playbackToken: playback.token)
            recorder.recordPlaybackEnqueued(
                sequence: resident.sequence, playback: playback, firstByte: 0, byteCount: resident.bytes.count
            )
            recorder.recordPlaybackEnqueued(
                sequence: next.sequence, playback: playback, firstByte: 0, byteCount: 2
            )
            recorder.recordPlaybackEnqueued(
                sequence: next.sequence, playback: playback, firstByte: 960, byteCount: next.bytes.count
            )
            recorder.stop(.sessionClosed)
            let archive = recorder.takeForSave()!
            expect(
                archive.packets[0].disposition == .hostEnqueueReturned && archive.packets[0].playbackEnqueuedPCM == nil
                    && archive.packets[1].playbackEnqueuedPCM?.playback == playback
                    && archive.packets[1].playbackEnqueuedPCM?.firstSample24k == 480
                    && archive.packets[1].playbackEnqueuedPCM?.sampleCount24k == next.bytes.count / 2,
                "host returns, stale identity, replaced sequence and partial bytes cannot prove full acceptance"
            )
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
            try verifyNativeVoiceEvidenceFile(outcome, recorder: candidate.acousticEvidence, diagnostics: diagnostics)
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
                    && downstream[0].providerTimestampNanoseconds == resident.timestampNanoseconds
                    && downstream[0].playbackEnqueuedPCM?.firstSample24k == 0
                    && downstream[0].playbackEnqueuedPCM?.sampleCount24k == resident.bytes.count / 2
                    && downstream[0].playbackEnqueuedPCM?.playback.token == downstream[0].playbackToken,
                "the full accepted range preserves original Provider samples and exact playback identity")
        }

        static func verifyNativeVoiceEvidenceFile(
            _ outcome: NativeVoiceEvidenceArchive, recorder: MacSpeechNativeAcousticEvidence,
            diagnostics: MacSpeechNativeVoiceDiagnosticReadback
        ) throws {
            let path = try AppController.writeNativeVoiceEvidence(
                outcome, recorder: recorder, technical: diagnostics, observedAt: monotonicNow()
            )
            let isolatedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]!
            expect(
                path.path.hasPrefix(isolatedHome + "/Library/Caches/"),
                "synthetic save is inside the dedicated isolated home")
            let bytes = try Data(contentsOf: path)
            let manifest = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            let facts = manifest?["technical"] as? [String: Any]
            let downlink = manifest?["downlinkEvidence"] as? [String: String]
            let downlinkRecord = outcome.packets.first { $0.direction == .providerReference }
            expect(
                manifest?["schemaVersion"] as? Int == 2
                    && downlink?["providerReceivedPCM"] == "runtimeAcceptedUnmodifiedDelta"
                    && downlink?["playbackEnqueuedPCM"] == "fullDeltaAcceptedAtNativeTransport24kInput"
                    && diagnostics.lastNonzeroSubmission?.playback == downlinkRecord?.playbackEnqueuedPCM?.playback
                    && downlink?["sourceConsumedPCM"] == "UNKNOWN",
                "even matching Source submission and host acceptance do not establish a per-packet Source mapping"
            )
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
            let files = try manager.contentsOfDirectory(atPath: folder.path)
            expect(recorder.phase == .saved && files == [path.lastPathComponent], "one atomically published archive")
            let revoked = try recorder.revoke()
            expect(revoked && !manager.fileExists(atPath: path.path), "post-save revocation removes the archive")
        }

        private static func makeEvidenceSealFixture() -> EvidenceSealFixture {
            let (target, capture) = acousticEvidenceTestIdentity()
            let recorder = MacSpeechNativeAcousticEvidence()
            expect(recorder.arm(), "one grant for a synthetic seal")
            recorder.bind(target, capture: capture)
            let resident = nativeResidentPCM()
            let large = RealtimeBrainAudioDelta(
                sequence: resident.sequence, timestampNanoseconds: resident.timestampNanoseconds,
                format: resident.format, provenance: resident.provenance, bytes: Data(repeating: 7, count: 150_000)
            )
            let identity = RealtimeBrainEventIdentity(
                session: target, turnID: .init(), responseID: .init(), contextRevision: 1
            )
            expect(
                recorder.recordProvider(large, identity: identity, playbackToken: 1) != nil,
                "synthetic JSON spans multiple staging writes"
            )
            recorder.stop(.userStopped)
            return .init(recorder: recorder, archive: recorder.takeForSave()!)
        }

        static func testSealRevocationRaces() async throws {
            for stage in NativeVoiceEvidenceSealStage.allCases {
                let fixture = makeEvidenceSealFixture()
                let gate = EvidenceSealGate()
                fixture.recorder.sealStageForTesting = { observed in
                    if stage == observed { gate.stopWriter() }
                }
                let writer = Task.detached { try fixture.save() }
                expect(gate.arrived.wait(timeout: .now() + 15) == .success, "reached seal stage \(stage)")
                try verifyStagingAtRace(stage, fixture: fixture)
                if stage == .renaming {
                    // The writer already owns the publication lock when revocation starts.
                    let started = DispatchSemaphore(value: 0)
                    let revoker = Task.detached {
                        started.signal()
                        return try fixture.recorder.revoke()
                    }
                    expect(started.wait(timeout: .now() + 15) == .success, "revocation overlaps the rename transaction")
                    gate.proceed.signal()
                    let revoked = try await revoker.value
                    let url = try await writer.value
                    expect(revoked && url == fixture.destination, "publication wins the lock and is then revoked")
                } else {
                    let revoked = try fixture.recorder.revoke()
                    expect(revoked, "revocation succeeds at \(stage)")
                    gate.proceed.signal()
                    do {
                        _ = try await writer.value
                        expect(stage == .afterRename, "only an earlier publication may report that rename succeeded")
                    } catch NativeVoiceEvidenceSealError.revoked {
                        expect(stage != .afterRename, "revocation before rename prevents publication")
                    }
                }
                fixture.recorder.discardRevoked()
                let files = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
                expect(fixture.recorder.phase == .revoked && files.isEmpty, "no evidence file remains at \(stage)")
            }
            print("native_voice_evidence_revocation_stages=preparing,writing,synchronized,beforeRename,renaming,afterRename")
        }

        private static func verifyStagingAtRace(
            _ stage: NativeVoiceEvidenceSealStage, fixture: EvidenceSealFixture
        ) throws {
            let manager = FileManager.default
            if stage == .writing {
                let entries = try manager.contentsOfDirectory(atPath: fixture.directory.path)
                expect(entries.count == 1, "one open temporary file during a multi-write seal")
                let path = fixture.directory.appendingPathComponent(entries[0]).path
                let attributes = try manager.attributesOfItem(atPath: path)
                expect(attributes[.size] as? Int == 65_536, "revoke during a multi-write file")
                do {
                    try AppController.recoverNativeVoiceEvidence()
                    fatalError("recovery disturbed an active writer")
                } catch let error as NSError {
                    expect(error.domain == NSPOSIXErrorDomain && error.code == Int(EWOULDBLOCK),
                           "recovery cannot take a live writer's folder lock")
                }
            }
            expect(
                manager.fileExists(atPath: fixture.destination.path) == (stage == .afterRename),
                "atomic publication stage is visible only after rename"
            )
        }

        private static func testPublishedRevocationCrashRecovery() throws {
            let manager = FileManager.default
            let normal = makeEvidenceSealFixture()
            let unmarked = try normal.save()
            for step in NativeVoiceEvidenceRevocationStep.allCases {
                let crash = try terminateRevocation(at: step)
                let targetRemains = [.beforeMarker, .markerCreated, .markerSynced, .beforeTargetUnlink].contains(step)
                let markerRemains = step != .beforeMarker && step != .markerUnlinked
                expect((crash.target != nil) == targetRemains && (crash.marker != nil) == markerRemains,
                       "disk matches process exit point \(step.rawValue)")
                if let marker = crash.marker {
                    let attrs = try manager.attributesOfItem(atPath: marker.path)
                    expect(attrs[.size] as? Int == 0 && attrs[.posixPermissions] as? Int == 0o600,
                           "the durable intent contains no payload and is owner-only")
                    if let target = crash.target {
                        let runID = UUID(uuidString: String(target.lastPathComponent.dropFirst(4).dropLast(5)))!
                        let expected = try revocationMarker(for: target, runID: runID)
                        expect(marker == expected, "marker names the exact archive, device, inode and version")
                    }
                }

                try AppController.recoverNativeVoiceEvidence()
                let remaining = Set(try manager.contentsOfDirectory(atPath: normal.directory.path))
                var expected = Set([unmarked.lastPathComponent])
                if step == .beforeMarker, let target = crash.target { expected.insert(target.lastPathComponent) }
                expect(remaining == expected, "fresh recovery touches only the recorded revocation at \(step.rawValue)")
                if step == .beforeMarker, let target = crash.target { try manager.removeItem(at: target) }
            }
            let revoked = try normal.recorder.revoke()
            expect(revoked, "synthetic negative-control archive is removable by an explicit revocation")
            let steps = NativeVoiceEvidenceRevocationStep.allCases.map(\.rawValue).joined(separator: ",")
            print("native_voice_evidence_process_exit_recovery=\(steps)")
        }

        private static func testRevocationRecoveryIdentityChecks() throws {
            let manager = FileManager.default
            let crash = try terminateRevocation(at: .markerSynced)
            let target = crash.target!
            let marker = crash.marker!
            let moved = target.deletingLastPathComponent().appendingPathComponent("original-\(UUID().uuidString)")
            let substitute = Data([3, 1, 4])
            try manager.moveItem(at: target, to: moved)
            try substitute.write(to: target, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            try expectRevocationRecoveryFailure()
            let preserved = try Data(contentsOf: target)
            expect(preserved == substitute && manager.fileExists(atPath: marker.path),
                   "inode mismatch preserves the substitute and the unresolved intent")

            try manager.removeItem(at: target)
            try manager.moveItem(at: moved, to: target)
            let wrongRun = try revocationMarker(for: target, runID: UUID())
            let unsupportedVersion = marker.deletingLastPathComponent().appendingPathComponent(
                marker.lastPathComponent.replacingOccurrences(of: ".revoke-v1.", with: ".revoke-v2.", options: .anchored)
            )
            try manager.removeItem(at: marker)
            for malformed in [wrongRun, unsupportedVersion] {
                try Data().write(to: malformed, options: .withoutOverwriting)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: malformed.path)
                try expectRevocationRecoveryFailure()
                expect(manager.fileExists(atPath: target.path) && manager.fileExists(atPath: malformed.path),
                       "unrecognized intent cannot authorize deletion")
                try manager.removeItem(at: malformed)
            }
            try Data().write(to: marker, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
            try AppController.recoverNativeVoiceEvidence()
            expect(!manager.fileExists(atPath: target.path) && !manager.fileExists(atPath: marker.path),
                   "restoring the exact identity allows fresh recovery to finish")
            print("native_voice_evidence_recovery_identity_guards=inode_mismatch,wrong_run,unknown_version")
        }

        private static func expectRevocationRecoveryFailure() throws {
            do {
                try AppController.recoverNativeVoiceEvidence()
                fatalError("invalid revocation allowed recovery to report success")
            } catch NativeVoiceEvidenceSealError.cleanupFailed {
                expect(true, "startup and consent recovery report a distinct cleanup failure")
            }
        }

        private static func terminateRevocation(
            at step: NativeVoiceEvidenceRevocationStep
        ) throws -> (target: URL?, marker: URL?) {
            let manager = FileManager.default
            let directory = EvidenceSealFixture.directory
            let before = Set(try manager.contentsOfDirectory(atPath: directory.path))
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--native-voice-acoustic-evidence"]
            var environment = ProcessInfo.processInfo.environment
            environment[NativeVoiceEvidenceRevocationStep.testEnvironmentKey] = step.rawValue
            child.environment = environment
            try child.run()
            child.waitUntilExit()
            expect(child.terminationReason == .exit && child.terminationStatus == NativeVoiceEvidenceRevocationStep.testExitCode,
                   "the original recorder process exits without unwinding at \(step.rawValue)")

            let created = Set(try manager.contentsOfDirectory(atPath: directory.path)).subtracting(before)
            let targets = created.filter { $0.hasPrefix("run-") }
            let markers = created.filter { $0.hasPrefix(".revoke-v1.") }
            expect(targets.count <= 1 && markers.count <= 1 && created.count == targets.count + markers.count,
                   "only the synthetic archive and its intent can survive exit")
            return (targets.first.map { directory.appendingPathComponent($0) },
                    markers.first.map { directory.appendingPathComponent($0) })
        }

        private static func revocationMarker(for archive: URL, runID: UUID) throws -> URL {
            var status = stat()
            guard lstat(archive.path, &status) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            let name = ".revoke-v1.\(runID.uuidString).\(status.st_dev).\(status.st_ino).\(archive.lastPathComponent)"
            return archive.deletingLastPathComponent().appendingPathComponent(name)
        }

        private struct MultiMarkerFixture {
            let target: URL
            let marker: URL
        }

        private static func runMultiMarkerRecoveryInTemporaryDirectory() throws {
            let manager = FileManager.default
            let directory = URL(fileURLWithPath: "/private/tmp/aftelle-voice-evidence.\(UUID().uuidString)", isDirectory: true)
            let home = directory.appendingPathComponent("runtime-home", isDirectory: true)
            try manager.createDirectory(at: home.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: directory) }
            let child = multiRecoveryProcess(mode: "suite", home: home.path)
            try child.run()
            child.waitUntilExit()
            guard child.terminationReason == .exit, child.terminationStatus == 0 else {
                throw CocoaError(.fileReadUnknown)
            }
        }

        private static func runMultiMarkerRecoveryCases() throws {
            try testMultiMarkerRecoverySets()
            try testMultiMarkerUnlinkFailures()
            try testMultiMarkerInodeMismatch()
            try testMultiMarkerInvalidNames()
            try testInterruptedMultiMarkerRecovery()
            print("native_voice_evidence_multi_marker_scenarios=11")
            print("native_voice_evidence_multi_marker_checks=\(checks)")
        }

        private static func testMultiMarkerRecoverySets() throws {
            _ = try seedMultiMarkerFixtures(count: 2)
            try AppController.recoverNativeVoiceEvidence()
            try expectMultiMarkerFiles([], "both RunIDs recover in one call")

            for mode in ["ascending", "descending"] {
                _ = try seedMultiMarkerFixtures(count: 3)
                let child = multiRecoveryProcess(mode: mode)
                try child.run()
                child.waitUntilExit()
                expect(child.terminationReason == .exit && child.terminationStatus == 0,
                       "three markers recover with \(mode) enumeration")
                try expectMultiMarkerFiles([], "enumeration order leaves the same empty state")
            }

            let normal = makeEvidenceSealFixture()
            let unmarked = try normal.save()
            _ = try seedMultiMarkerFixtures(count: 4)
            try AppController.recoverNativeVoiceEvidence()
            try expectMultiMarkerFiles([], extra: [unmarked], "mixed recovery leaves the normal archive")
            try AppController.recoverNativeVoiceEvidence()
            try expectMultiMarkerFiles([], extra: [unmarked], "a fresh repeat is idempotent")
            let revoked = try normal.recorder.revoke()
            expect(revoked, "the synthetic negative control is cleaned by an explicit revocation")
        }

        private static func testMultiMarkerUnlinkFailures() throws {
            for protectMarker in [false, true] {
                let fixtures = try seedMultiMarkerFixtures(count: 3)
                let failed = fixtures[1]
                let protected = protectMarker ? failed.marker : failed.target
                try setSyntheticImmutable(protected, true)
                defer {
                    if FileManager.default.fileExists(atPath: protected.path) { try? setSyntheticImmutable(protected, false) }
                }

                expectRecoveryDeniesGrant(domain: NSPOSIXErrorDomain, code: Int(EPERM))
                if protectMarker {
                    try expectMultiMarkerFiles([fixtures[2]], extra: [failed.marker],
                                               "marker unlink failure retains the intent and stops before the next RunID")
                } else {
                    try expectMultiMarkerFiles(Array(fixtures.dropFirst()),
                                               "archive unlink failure retains that pair and the next RunID")
                }
                try setSyntheticImmutable(protected, false)
                try AppController.recoverNativeVoiceEvidence()
                try expectMultiMarkerFiles([], "fresh retry completes the unprocessed markers")
            }
        }

        private static func testMultiMarkerInodeMismatch() throws {
            let manager = FileManager.default
            let fixtures = try seedMultiMarkerFixtures(count: 2)
            let first = fixtures[0]
            let original = first.target.deletingLastPathComponent().appendingPathComponent("synthetic-original")
            let substitute = Data([1, 2, 3])
            try manager.moveItem(at: first.target, to: original)
            try substitute.write(to: first.target, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: first.target.path)
            expectRecoveryDeniesGrant(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
            try expectMultiMarkerFiles(fixtures, extra: [original],
                                       "inode mismatch protects the substitute and the other RunID")
            let remainingBytes = try Data(contentsOf: first.target)
            expect(remainingBytes == substitute, "the replacement bytes remain untouched")
            try manager.removeItem(at: first.target)
            try manager.moveItem(at: original, to: first.target)
            try AppController.recoverNativeVoiceEvidence()
            try expectMultiMarkerFiles([], "restoring the expected inode allows both recoveries")
        }

        private static func testMultiMarkerInvalidNames() throws {
            let manager = FileManager.default
            let fixtures = try seedMultiMarkerFixtures(count: 2)
            let last = fixtures[1]
            let folder = last.marker.deletingLastPathComponent()
            let unknown = folder.appendingPathComponent(
                last.marker.lastPathComponent.replacingOccurrences(of: ".revoke-v1.", with: ".revoke-v2.", options: .anchored)
            )
            try manager.moveItem(at: last.marker, to: unknown)
            expectRecoveryDeniesGrant(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
            try expectMultiMarkerFiles([fixtures[0]], extra: [unknown, last.target],
                                       "unknown version blocks the whole snapshot before deleting any target")
            try manager.moveItem(at: unknown, to: last.marker)

            var fields = last.marker.lastPathComponent.dropFirst(".revoke-v1.".count)
                .split(separator: ".", maxSplits: 3).map(String.init)
            fields[2] = String(UInt64(fields[2])! &+ 1)
            let duplicate = folder.appendingPathComponent(".revoke-v1." + fields.joined(separator: "."))
            try seedMultiMarker(duplicate)
            expectRecoveryDeniesGrant(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
            try expectMultiMarkerFiles(fixtures, extra: [duplicate],
                                       "conflicting identities for one RunID fail before target absence can hide a mismatch")
            try manager.removeItem(at: duplicate)

            let first = fixtures[0]
            let savedMarker = folder.appendingPathComponent("synthetic-saved-marker")
            try manager.moveItem(at: first.marker, to: savedMarker)
            try manager.createSymbolicLink(at: first.marker, withDestinationURL: savedMarker)
            expectRecoveryDeniesGrant(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
            try expectMultiMarkerFiles(fixtures, extra: [savedMarker],
                                       "recovery cannot accept a symlink as the reopened marker")
            try manager.removeItem(at: first.marker)
            try manager.moveItem(at: savedMarker, to: first.marker)
            try AppController.recoverNativeVoiceEvidence()
            try expectMultiMarkerFiles([], "remaining valid RunIDs recover after synthetic conflicts are removed")
        }

        private static func testInterruptedMultiMarkerRecovery() throws {
            let fixtures = try seedMultiMarkerFixtures(count: 3)
            let ready = Pipe()
            let proceed = Pipe()
            let child = multiRecoveryProcess(mode: "interrupt")
            child.standardOutput = ready
            child.standardInput = proceed
            try child.run()
            defer { try? proceed.fileHandleForWriting.close() }
            let checkpoint = try ready.fileHandleForReading.read(upToCount: 1)
            expect(checkpoint == Data([1]), "child has completed the first sorted item and still holds the directory lock")
            try expectMultiMarkerFiles(Array(fixtures.dropFirst()),
                                       "descending enumeration still processes the first canonical marker first")
            expectRecoveryDeniesGrant(domain: NSPOSIXErrorDomain, code: Int(EWOULDBLOCK), cleanupFailure: false)
            try proceed.fileHandleForWriting.write(contentsOf: Data([1]))
            child.waitUntilExit()
            expect(child.terminationReason == .exit && child.terminationStatus == NativeVoiceEvidenceRevocationStep.testExitCode,
                   "the original recovery instance exits between markers without unwinding")
            try AppController.recoverNativeVoiceEvidence()
            try expectMultiMarkerFiles([], "new instance recovers every remaining valid marker")
            try AppController.recoverNativeVoiceEvidence()
            try expectMultiMarkerFiles([], "interrupted batch remains idempotent after recovery")
        }

        private static func multiRecoveryProcess(mode: String, home: String? = nil) -> Process {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--native-voice-acoustic-evidence"]
            var environment = ProcessInfo.processInfo.environment
            environment[AppController.nativeVoiceEvidenceMultiRecoveryTestKey] = mode
            if let home { environment["CFFIXED_USER_HOME"] = home }
            child.environment = environment
            return child
        }

        private static func seedMultiMarkerFixtures(count: Int) throws -> [MultiMarkerFixture] {
            let fixtures = try (0..<count).map { _ in
                let fixture = makeEvidenceSealFixture()
                let target = try fixture.save()
                return MultiMarkerFixture(target: target, marker: try revocationMarker(for: target, runID: fixture.archive.runID))
            }.sorted { $0.marker.lastPathComponent < $1.marker.lastPathComponent }
            // Save all archives before planting any marker; a save itself runs recovery.
            for fixture in fixtures.reversed() { try seedMultiMarker(fixture.marker) }
            return fixtures
        }

        private static func seedMultiMarker(_ marker: URL) throws {
            try Data().write(to: marker, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        }

        private static func expectMultiMarkerFiles(_ fixtures: [MultiMarkerFixture], extra: [URL] = [], _ reason: String) throws {
            let expected = Set((fixtures.flatMap { [$0.target, $0.marker] } + extra).map(\.lastPathComponent))
            let actual = Set(try FileManager.default.contentsOfDirectory(atPath: EvidenceSealFixture.directory.path))
            expect(actual == expected, reason)
        }

        private static func expectRecoveryDeniesGrant(domain: String, code: Int, cleanupFailure: Bool = true) {
            let next = MacSpeechNativeAcousticEvidence()
            do {
                try AppController.recoverNativeVoiceEvidence()
                _ = next.arm()
                fatalError("an unfinished recovery passed the recording authorization gate")
            } catch NativeVoiceEvidenceSealError.cleanupFailed(let underlying) {
                let error = underlying as NSError
                expect(cleanupFailure && error.domain == domain && error.code == code && next.phase == .off,
                       "cleanup failure blocks a new grant")
            } catch let error as NSError {
                expect(!cleanupFailure && error.domain == domain && error.code == code && next.phase == .off,
                       "a live recovery lock blocks a new grant")
            }
        }

        private static func setSyntheticImmutable(_ file: URL, _ immutable: Bool) throws {
            guard chflags(file.path, immutable ? UInt32(UF_IMMUTABLE) : 0) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }

        private struct DirectoryFixtureState: Equatable {
            let bytes: Data
            let device: dev_t
            let inode: ino_t
            let mode: mode_t
            let links: nlink_t
        }

        private static func runDirectoryEnumerationInTemporaryDirectory() throws {
            let manager = FileManager.default
            let directory = URL(fileURLWithPath: "/private/tmp/aftelle-voice-evidence.\(UUID().uuidString)", isDirectory: true)
            let home = directory.appendingPathComponent("runtime-home", isDirectory: true)
            try manager.createDirectory(at: home.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: directory) }
            try runDirectoryEnumerationProcess("directory-suite", home: home.path)
        }

        private static func testDirectoryEnumeration() throws {
            let control = makeEvidenceSealFixture()
            _ = try control.save()
            let normal = try directoryFixtureState()

            _ = try seedMultiMarkerFixtures(count: 3)
            try AppController.recoverNativeVoiceEvidence()
            let afterEOF = try directoryFixtureState()
            expect(afterEOF == normal, "normal EOF recovers all three markers and preserves the unmarked archive")
            print("native_voice_evidence_directory_normal_eof=PASS")

            _ = try seedMultiMarkerFixtures(count: 3)
            let beforeError = try directoryFixtureState()
            expect(beforeError.count == 7, "error fixture has three pairs and one unmarked archive")
            try runDirectoryEnumerationProcess("directory-read-eio")
            let afterError = try directoryFixtureState()
            expect(afterError == beforeError, "EIO after two marker reads leaves all six files and the control intact")
            print("native_voice_evidence_directory_partial_snapshot_unchanged=PASS")

            try AppController.recoverNativeVoiceEvidence()
            let afterRetry = try directoryFixtureState()
            expect(afterRetry == normal, "a fresh recovery completes all three previously blocked intents")
            print("native_voice_evidence_directory_fresh_recovery=PASS")

            _ = try seedMultiMarkerFixtures(count: 3)
            try runDirectoryEnumerationProcess("directory-stale-errno")
            let afterStaleErrno = try directoryFixtureState()
            expect(afterStaleErrno == normal, "stale errno from the previous entry does not turn EOF into an error")
            print("native_voice_evidence_directory_errno_isolation=PASS")

            _ = try seedMultiMarkerFixtures(count: 3)
            let beforeStreamFailures = try directoryFixtureState()
            for mode in ["directory-open-emfile", "directory-close-eio"] {
                try runDirectoryEnumerationProcess(mode)
                let afterFailure = try directoryFixtureState()
                expect(afterFailure == beforeStreamFailures, "stream open or close failure leaves every marked pair intact")
            }
            try AppController.recoverNativeVoiceEvidence()
            let afterStreamRetry = try directoryFixtureState()
            expect(afterStreamRetry == normal, "retry succeeds after the stream failures have been removed")
            let revoked = try control.recorder.revoke()
            expect(revoked, "the isolated control is removed by an explicit revocation")
            print("native_voice_evidence_directory_enumeration_scenarios=6")
            print("native_voice_evidence_directory_enumeration_checks=\(checks)")
        }

        private static func runDirectoryEnumerationProcess(_ mode: String, home: String? = nil) throws {
            let child = multiRecoveryProcess(mode: mode, home: home)
            try child.run()
            child.waitUntilExit()
            guard child.terminationReason == .exit, child.terminationStatus == 0 else {
                throw CocoaError(.fileReadUnknown)
            }
        }

        private static func directoryFixtureState() throws -> [String: DirectoryFixtureState] {
            let folder = EvidenceSealFixture.directory
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            return try Dictionary(uniqueKeysWithValues: names.map { name in
                let url = folder.appendingPathComponent(name)
                var status = stat()
                guard lstat(url.path, &status) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                let entry = DirectoryFixtureState(bytes: try Data(contentsOf: url), device: status.st_dev,
                                                  inode: status.st_ino, mode: status.st_mode, links: status.st_nlink)
                return (name, entry)
            })
        }

        static func testSealFailureAndRecovery() throws {
            let fixture = makeEvidenceSealFixture()
            let manager = FileManager.default
            try AppController.recoverNativeVoiceEvidence()
            let existing = Data([1, 2, 3])
            try existing.write(to: fixture.destination, options: .withoutOverwriting)
            do {
                _ = try fixture.save()
                fatalError("exclusive rename overwrote an existing archive")
            } catch let error as NSError {
                expect(error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST), "rename reports collision")
            }
            let preserved = try Data(contentsOf: fixture.destination)
            let afterFailure = try manager.contentsOfDirectory(atPath: fixture.directory.path)
            expect(
                fixture.recorder.phase == .ended && preserved == existing
                    && afterFailure == [fixture.destination.lastPathComponent],
                "failed seal removes only its staging file and keeps the existing file unchanged"
            )
            try manager.removeItem(at: fixture.destination)
            expect(fixture.recorder.takeForSave()?.runID == fixture.archive.runID, "failed seal may retry the same grant")
            _ = try fixture.save()
            try testPublishedCleanupFailure(fixture)
            try testStagingCleanupFailure()
            try testStagingRecovery(fixture)
            print("native_voice_evidence_cleanup=rename_collision,real_unlink_failure,retry,exclusive_recovery")
        }

        private static func testPublishedCleanupFailure(_ fixture: EvidenceSealFixture) throws {
            let manager = FileManager.default
            let marker = try revocationMarker(for: fixture.destination, runID: fixture.archive.runID)
            try Data().write(to: marker, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
            try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
            do {
                _ = try fixture.recorder.revoke()
                fatalError("revocation masked a failed unlink")
            } catch NativeVoiceEvidenceSealError.cleanupFailed(let underlying) {
                let error = underlying as NSError
                expect(error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES),
                       "published file cleanup reports the real unlink errno")
            }
            expect(fixture.recorder.phase == .cleanupFailed && manager.fileExists(atPath: fixture.destination.path)
                       && manager.fileExists(atPath: marker.path),
                   "a failed unlink preserves the published file and the revocation intent")
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
            let retried = try fixture.recorder.revoke()
            expect(retried && !manager.fileExists(atPath: fixture.destination.path) && !manager.fileExists(atPath: marker.path),
                   "retry removes the same published file and its intent")
        }

        private static func testStagingCleanupFailure() throws {
            let fixture = makeEvidenceSealFixture()
            let manager = FileManager.default
            fixture.recorder.sealStageForTesting = { stage in
                if stage == .beforeRename {
                    precondition(chmod(fixture.directory.path, 0o500) == 0, "could not set synthetic directory permissions")
                }
            }
            do {
                _ = try fixture.save()
                fatalError("seal with protected directory did not report staging cleanup failure")
            } catch NativeVoiceEvidenceSealError.cleanupFailed(let underlying) {
                let error = underlying as NSError
                expect(error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES), "staging cleanup returns unlink failure")
            }
            let files = try manager.contentsOfDirectory(atPath: fixture.directory.path)
            expect(
                fixture.recorder.phase == .cleanupFailed && files.count == 1 && files[0].hasSuffix(".tmp"),
                "no success is reported while a staging file remains"
            )
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
            let retried = try fixture.recorder.revoke()
            let remaining = try manager.contentsOfDirectory(atPath: fixture.directory.path)
            expect(retried && remaining.isEmpty, "retry removes failed staging without publishing")
        }

        private static func testStagingRecovery(_ fixture: EvidenceSealFixture) throws {
            let manager = FileManager.default
            let name = ".sealing-\(UUID().uuidString).tmp"
            let orphan = fixture.directory.appendingPathComponent(name)
            let neighbor = fixture.directory.deletingLastPathComponent().appendingPathComponent(name)
            let lookalike = fixture.directory.appendingPathComponent(".sealing-not-a-uuid.tmp")
            for path in [orphan, neighbor, lookalike] {
                try Data([8]).write(to: path)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            }
            try AppController.recoverNativeVoiceEvidence()
            expect(!manager.fileExists(atPath: orphan.path) && manager.fileExists(atPath: neighbor.path)
                       && manager.fileExists(atPath: lookalike.path), "recovery removes only the app's reserved staging name")
            try manager.createSymbolicLink(at: orphan, withDestinationURL: neighbor)
            do {
                try AppController.recoverNativeVoiceEvidence()
                fatalError("recovery accepted a symlink")
            } catch NativeVoiceEvidenceSealError.cleanupFailed {
                expect(manager.fileExists(atPath: orphan.path) && manager.fileExists(atPath: neighbor.path),
                       "recovery refuses symlinks and reports a cleanup failure")
            }
            try manager.removeItem(at: orphan)
            let legacy = fixture.directory.appendingPathComponent(".sealing-\(UUID().uuidString)")
            try Data([9]).write(to: legacy)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacy.path)
            do {
                try AppController.recoverNativeVoiceEvidence()
                fatalError("recovery ignored a file with an unverifiable legacy writer")
            } catch NativeVoiceEvidenceSealError.cleanupFailed {
                expect(manager.fileExists(atPath: legacy.path), "legacy staging is reported for manual review")
            }
        }
    }
#endif
