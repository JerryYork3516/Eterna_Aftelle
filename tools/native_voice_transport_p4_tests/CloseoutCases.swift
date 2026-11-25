#if NATIVE_VOICE_P3_OFFLINE_TEST
    private extension RealtimeInterruptionEvidenceTests {
        static func runNativeVoiceP4() async throws {
            testNativeVoiceAdmission()
            testNativeVoiceCaptureQueue()
            try await testNativeVoicePlaybackAndClear(verifyCloseout: true)
            try await testNativeVoiceController(verifyCloseout: true)
            print("native_voice_p4_checks=\(checks)")
            print("native_voice_p4_device_access=ZERO")
        }

        static func testNativeVoiceAdmission() {
            let arg = AppleNativeVoiceDebugAdmission.argument
            expect(!AppleNativeVoiceDebugAdmission.deviceBuildAuthorized,
                   "offline Shadow has no device build authorization")
            let hardware = FakeVoiceHardware()
            let candidate = MacSpeechNativeRealtimeSession(makeTransport: { hardware.makeTransport() })
            let cases: [([String], Bool, AppleNativeVoiceDebugAdmission)] = [
                ([], false, .off), ([], true, .off),
                (["--apple-vp-debug"], true, .off),
                ([arg], false, .sealed), ([arg, arg], true, .sealed),
                ([arg + "=true"], true, .sealed), ([arg, "--apple-vp-debug"], true, .sealed),
                ([arg], true, .admitted)
            ]
            for (arguments, authorized, expected) in cases {
                let admission = AppleNativeVoiceDebugAdmission.resolve(
                    arguments: arguments, deviceBuildAuthorized: authorized
                )
                var factories = 0
                let selected = admission.backend {
                    factories += 1
                    return candidate
                }
                expect(admission == expected && (selected.candidate != nil) == (expected == .admitted)
                    && factories == (expected == .admitted ? 1 : 0), "only the exact admitted request selects native")
            }
            expect(hardware.update { $0.graphs.isEmpty }, "selecting a backend starts no graph")
        }

        static func testNativeVoiceCaptureQueue() {
            let active = NativeVoiceIdentity.Capture(
                authority: .init(runtimeGeneration: 2, routeEpoch: 4, configurationID: 5), generation: 1, token: 2
            )
            let stale = NativeVoiceIdentity.Capture(
                authority: .init(runtimeGeneration: 1, routeEpoch: 4, configurationID: 5), generation: 1, token: 1
            )
            func packet(_ index: Int, identity: NativeVoiceIdentity.Capture) -> NativeVoiceCapturePacket {
                .init(bytes: Data(repeating: 1, count: 960), identity: identity, segment: 3,
                      sampleCount: UInt64(index) * 480, hostTimeNanoseconds: nil, timingStatus: .unknown)
            }
            var facts = MacSpeechNativeRealtimeFacts()
            let capacity = MacSpeechAudioInputFormat.frameCapacity
            facts.bufferCapture((0 ..< capacity + 4).map { packet($0, identity: active) }, expected: active)
            facts.bufferCapture([packet(0, identity: stale)], expected: active)
            let queue = facts.captureQueue
            expect(queue.pendingPackets == capacity && queue.highWaterPackets == capacity
                && queue.generatedPackets == UInt64(capacity + 4)
                && queue.overflowPackets == 4 && queue.stalePackets == 1
                && queue.lastContentSegment == 3 && queue.lastPacketStartSample == UInt64(capacity + 3) * 480,
                "bounded capture queue records overflow and stale packets separately from content segment")
            let frames = facts.drainCapture(maxCount: 2)
            expect(frames.map(\.sequenceNumber) == [5, 6] && facts.captureQueue.deliveredPackets == 2,
                   "overflow drops the oldest with a visible sequence gap")
            facts.discardCapture(forTransition: true)
            facts.bufferCapture([packet(capacity + 4, identity: active)], expected: active)
            facts.discardCapture(forTransition: false)
            let retired = facts.captureQueue
            expect(retired.transitionDiscardedPackets == UInt64(capacity - 2) && retired.closeDiscardedPackets == 1
                && retired.pendingPackets == 0 && facts.deliveredCapture.isEmpty,
                "transition and close discards reconcile independently")
        }

        static func nativeVoiceDiagnostic(_ adapter: MacSpeechNativeRealtimeSession) async throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: await adapter.nativeVoiceDiagnosticData()) as? [String: Any] ?? [:]
        }

        static func verifyNativeVoiceHandoff(_ adapter: MacSpeechNativeRealtimeSession, generation: UInt64) async throws {
            let facts = try await nativeVoiceDiagnostic(adapter)
            let source = facts["lastDigitalHandoff"] as? [String: Any]
            let playback = source?["playback"] as? [String: Any]
            let transport = facts["transport"] as? [String: Any]
            let route = transport?["route"] as? [String: Any]
            expect(source?["hostTime"] != nil && source?["sampleTime"] != nil
                && source?["frameCount"] as? Int == 193 && playback?["token"] as? UInt64 == generation,
                "actual callback EOS readback carries Source time, frames and the exact playback token")
            let submit = facts["lastNonzeroSubmission"] as? [String: Any]
            let submitPlayback = submit?["playback"] as? [String: Any]
            let idle = facts["lastSource"] as? [String: Any]
            expect(idle?["nonzeroFrames"] as? Int == 0 && (submit?["nonzeroFrames"] as? Int ?? 0) > 0
                && submit?["nonzeroSpan"] != nil && submitPlayback?["token"] as? UInt64 == generation,
                "idle renders preserve the last positive digital submission and its own playback identity")
            expect(facts["physicalPlayback"] as? String == "UNKNOWN" && facts["humanSource"] as? String == "UNKNOWN"
                && transport?["voiceProcessing"] == nil && route?["active"] as? Bool == true
                && route?["inputUnitDevice"] as? Int == 50 && route?["inputActiveMembers"] as? [Int] == [6, 9],
                "digital EOS leaves the graph live without filling unavailable physical or VP facts")
        }

        static func verifyNativeVoiceContentFence(
            _ adapter: MacSpeechNativeRealtimeSession, engine: FakeVoiceEngine, provider: R81RealtimeProvider
        ) async throws {
            let before = await provider.audioCount()
            let stale = [Float](repeating: 0.9, count: 882)
            engine.capture(stale, sampleTime: 7056, hostTime: 1)
            engine.capture(stale, sampleTime: 7938, hostTime: 0, flags: 1)
            let after = await provider.audioCount()
            let facts = try await nativeVoiceDiagnostic(adapter)
            let transport = facts["transport"] as? [String: Any]
            let count = transport?["captureCounters"] as? [String: UInt64]
            expect(transport?["captureMinimumHostNanoseconds"] as? UInt64 ?? 0 > 1
                && count?["beforeFenceNativeFrames"] == 882 && count?["missingFenceEvidenceNativeFrames"] == 882,
                "N+1 rejects late content with a fresh token and exposes missing timestamp evidence")
            expect(before == after, "neither late nor unproven PCM enters the Fake Provider")
        }

        static func verifyNativeVoiceControllerEOS(
            _ adapter: MacSpeechNativeRealtimeSession, provider: R81RealtimeProvider, controller: AppController,
            next: RealtimeBrainSessionIdentity
        ) async throws {
            let target = R81Target(session: next, turnID: .init(), responseID: .init(), contextRevision: 1)
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: .init(session: next, turnID: target.turnID, responseID: nil, contextRevision: 1),
                sequence: 1, kind: .userTranscriptFinal("synthetic following turn")
            ))
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: eventIdentity(target), sequence: 2, kind: .residentAudioDelta(nativeResidentPCM())
            ))
            await waitUntil("following native turn speaks") {
                controller.realtimeFullDuplexSpeechStatus.phase == .speaking
            }
            await provider.enqueue(RealtimeResidentBrainEvent(
                identity: eventIdentity(target), sequence: 3, kind: .residentSpeakingStopped
            ))
            await waitUntil("following Source EOS releases Controller presentation") {
                controller.realtimeFullDuplexSpeechStatus.phase == .listening
            }
            let facts = try await nativeVoiceDiagnostic(adapter)
            let handoff = facts["lastDigitalHandoff"] as? [String: Any]
            let playback = handoff?["playback"] as? [String: Any]
            let authority = playback?["authority"] as? [String: Any]
            expect(authority?["runtimeGeneration"] as? UInt64 == next.generation
                && facts["physicalPlayback"] as? String == "UNKNOWN" && facts["humanSource"] as? String == "UNKNOWN",
                "Controller settles the N+1 response on its own digital EOS without physical or human qualification")
        }

        static func verifyNativeVoiceSealed(
            _ adapter: MacSpeechNativeRealtimeSession, controller: AppController, generation: UInt64
        ) async throws {
            let data = try await adapter.nativeVoiceDiagnosticData()
            let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            defer { try? FileManager.default.removeItem(at: path) }
            try controller.writeRealtimeSpeechDiagnostics(to: path, nativeVoiceData: data)
            let evidence = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any]
            let facts = evidence?["facts"] as? [String: Any]
            let transport = facts?["transport"] as? [String: Any]
            let route = transport?["route"] as? [String: Any]
            let sink = transport?["lastConsumedSink"] as? [String: Any]
            let capture = sink?["identity"] as? [String: Any]
            let authority = capture?["authority"] as? [String: Any]
            let queue = facts?["captureQueue"] as? [String: Any]
            expect(evidence?["backend"] as? String == "apple_native_voice_transport"
                && (evidence?["buildBinarySHA256"] as? String)?.count == 64 && facts?["sealed"] as? Bool == true
                && facts?["terminalReason"] as? String == "microphone_permission_revoked"
                && route?["active"] as? Bool == false, "existing atomic writer seals bounded candidate facts and identity")
            expect(sink?["callbackFrames"] as? Int == 882 && sink?["hostTime"] != nil
                && authority?["runtimeGeneration"] as? UInt64 == generation
                && (queue?["deliveredPackets"] as? Int ?? 0) > 0 && evidence?["audioCapsule"] == nil,
                "recovery delivers genuine N+1 Sink facts and exported evidence contains no audio capsule")
        }
    }
#endif
