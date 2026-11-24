import Darwin
import Foundation

@main
struct SessionTests {
    private static var checks = 0

    static func main() async throws {
        try negotiationContract()
        try listenerContract()
        try await continuousSession()
        try await observedCaptureLoss()
        try await deviceLifecycle()
        try await liveRouteChanges()
        try await startupFailures()
        try await permissionLifecycle()
        print("native_voice_p2_session_checks=\(checks)")
        print("native_voice_p2_fake_engine_device_access=ZERO")
    }

    static func expect(_ success: Bool, _ message: String) {
        checks += 1
        precondition(success, message)
    }

    static func identity(_ number: UInt64 = 1) -> NativeVoiceIdentity {
        NativeVoiceIdentity(
            authority: .init(runtimeGeneration: 3, routeEpoch: number, configurationID: number),
            captureGeneration: number, captureToken: number, playbackEpoch: number, playbackToken: number
        )
    }

    private static func nextPlayback(
        _ from: NativeVoiceIdentity.Playback,
        token: UInt64,
        cancel: Bool = false
    ) -> NativeVoiceIdentity.Playback {
        .init(authority: from.authority, epoch: from.epoch + (cancel ? 1 : 0), token: token)
    }

    private static func wave(_ count: Int, rate: Double) -> [Float] {
        (0 ..< count).map { Float(sin(Double($0) * 2 * .pi * 357 / rate) * 0.3) }
    }

    private static func ticks(_ sample: Int, rate: Double) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        precondition(mach_timebase_info(&timebase) == KERN_SUCCESS)
        let nanos = 10_000_000_000 + Double(sample) * 1e9 / rate
        return UInt64((nanos * Double(timebase.denom) / Double(timebase.numer)).rounded())
    }

    private static func continuousSession() async throws {
        let hardware = FakeVoiceHardware()
        let transport = hardware.makeTransport(ringFrames: 1024)
        let session = identity()
        try await transport.start(identity: session)
        let graph = hardware.update { $0.graphs[0] }
        let installed = graph.read().installedPlan!
        expect(installed.capture.channels == 2 && installed.capture.interleaved, "negotiated sink layout")
        expect(
            installed.capture.sampleRate == 44100 && installed.source.sampleRate == 48000,
            "independent VP I/O rates"
        )
        expect(installed.source.channels == 1 && installed.source.float32, "mono float source for mixer")
        let counts = [193, 501, 977, 613, 803, 1009, 367, 631, 509, 769]
        let samples = wave(counts.reduce(0, +), rate: 44100)
        var packets: [NativeVoiceCapturePacket] = []
        var offset = 0
        for (index, count) in counts.enumerated() {
            graph.capture(
                Array(samples[offset ..< offset + count]),
                sampleTime: offset,
                hostTime: ticks(offset, rate: 44100)
            )
            if index == 3 {
                packets += try await completedTurn(transport, graph: graph, identity: session.playback)
            }
            if index == 6 {
                try await cancelAfterNextTurn(transport, graph: graph, first: session.playback)
            }
            for _ in 0 ..< (count + 136) / 137 {
                packets += try await transport.service(maxCaptureFrames: 137)
            }
            offset += count
        }
        try compareCapture(packets, to: samples, identity: session.capture)
        expect(graph.read().starts == 1 && graph.read().stops == 0, "turns reuse the same graph")
        await transport.close()
        await transport.close()
        expect(graph.read().stops == 1, "close tears down once")
        graph.capture([9], sampleTime: offset, hostTime: ticks(offset, rate: 44100))
        expect(graph.render(19).allSatisfy { $0 == 0 }, "old graph renders silence after close")
        print("native_voice_p2_continuous_session=PASS")
    }

    private static func completedTurn(
        _ transport: AppleNativeVoiceTransport, graph: FakeVoiceEngine, identity: NativeVoiceIdentity.Playback
    ) async throws -> [NativeVoiceCapturePacket] {
        try await transport.beginPlayback(identity)
        let logical = wave(1701, rate: 24000)
        let bytes = NativeVoicePCM16.encode(logical)
        await expect(
            try transport.enqueuePlayback(bytes, identity: identity),
            "first chunk accepted through backpressure"
        )
        await expect(try !transport.enqueuePlayback(bytes, identity: identity), "unaccepted bytes can be retried")
        var output: [Float] = []
        var captured: [NativeVoiceCapturePacket] = []
        for index in 0 ..< 40 {
            _ = try await transport.finishPlayback(identity: identity)
            output += graph.render([173, 257, 111][index % 3])
            captured += try await transport.service(maxCaptureFrames: 23)
            if try await transport.progress().renderHandoff {
                break
            }
        }
        let progress = try await transport.progress()
        let oracle = try NativeVoiceStreamingSRC(inputRate: 24000, outputRate: 48000)
        var reference = try oracle.append(NativeVoicePCM16.decode(bytes))
        reference += try oracle.finish()
        expect(progress.renderHandoff && progress.playback == .ending, "consumed EOS is a render handoff")
        expect(
            output.count >= reference.count && Array(output.prefix(reference.count)) == reference,
            "EOS and backpressure preserve all native playback frames"
        )
        expect(output.dropFirst(reference.count).allSatisfy { $0 == 0 }, "EOS fills only its final suffix with silence")
        expect(progress.underrunFrames == 0, "normal EOS does not create underruns")
        return captured
    }

    private static func cancelAfterNextTurn(
        _ transport: AppleNativeVoiceTransport, graph: FakeVoiceEngine, first: NativeVoiceIdentity.Playback
    ) async throws {
        let current = nextPlayback(first, token: 2)
        try await transport.beginPlayback(current)
        let afterBegin = try await transport.progress()
        expect(
            !afterBegin.consumerAcknowledged && afterBegin.token == 2,
            "logical clear precedes render acknowledgement"
        )
        expect(graph.render(73).allSatisfy { $0 == 0 }, "pre-roll silence while source acknowledges")
        let bytes = NativeVoicePCM16.encode([Float](repeating: -0.3, count: 2048))
        await expect(try transport.enqueuePlayback(bytes, identity: current), "second turn streams")
        expect(graph.render(101).contains { $0 < -0.1 }, "second turn is audible in fake output")
        let cancel = nextPlayback(current, token: 3, cancel: true)
        async let finish: Bool? = try? transport.finishPlayback(identity: current)
        try await transport.cancelPlayback(current, replacingWith: cancel)
        _ = await finish
        let before = try await transport.progress()
        expect(before.playback == .cancelled && !before.renderHandoff, "cancel has no natural EOS")
        expect(graph.render(91).allSatisfy { $0 == 0 }, "old PCM cannot resume after cancel")
        let after = try await transport.progress()
        expect(after.consumerAcknowledged && after.cancelledFrames >= 91, "consumer clear and cancel classified")
        do {
            _ = try await transport.enqueuePlayback(bytes, identity: current)
            preconditionFailure("stale packet accepted")
        } catch NativeVoiceTransportError.staleIdentity {}
    }

    private static func compareCapture(
        _ packets: [NativeVoiceCapturePacket], to samples: [Float], identity: NativeVoiceIdentity.Capture
    ) throws {
        let oracle = try NativeVoiceStreamingSRC(inputRate: 44100, outputRate: 24000)
        var reference = try oracle.append(samples)
        reference += try oracle.finish()
        let actual = packets.reduce(into: Data()) { $0.append($1.bytes) }
        expect(
            packets.count >= 4 && actual == NativeVoicePCM16.encode(Array(reference.prefix(actual.count / 2))),
            "capture content survives playback EOS, next turn and cancellation"
        )
        expect(
            packets.allSatisfy { $0.identity == identity && $0.segment == 0 },
            "capture clock and segment stay in session"
        )
        expect(packets.dropFirst().allSatisfy { $0.timingStatus == .valid }, "capture mapping remains qualified")
    }
}

private extension SessionTests {
    static func observedCaptureLoss() async throws {
        let hardware = FakeVoiceHardware()
        hardware.update { $0.snapshot = FakeVoiceHardware.makeSnapshot(capture: 24000) }
        let transport = hardware.makeTransport(ringFrames: 1024)
        try await transport.start(identity: identity())
        let graph = hardware.update { $0.graphs[0] }
        graph.capture([Float](repeating: 0.4, count: 700), sampleTime: 0, hostTime: ticks(0, rate: 24000))
        let before = try await transport.service(maxCaptureFrames: 1024)
        expect(before.count == 1, "one packet and a partial packet queued before loss")
        graph.capture([Float](repeating: 0.7, count: 1200), sampleTime: 700, hostTime: ticks(700, rate: 24000))
        graph.capture([Float](repeating: -0.4, count: 480), sampleTime: 700, hostTime: ticks(700, rate: 24000))
        let after = try await transport.service(maxCaptureFrames: 1024)
        expect(after.count == 1 && after[0].segment == 1 && after[0].sampleCount == 0, "explicit overflow breaks PCM")
        expect(
            after[0].bytes == NativeVoicePCM16.encode([Float](repeating: -0.4, count: 480)),
            "missing frames are never padded or mixed with the old partial packet"
        )
        expect(after[0].hostTimeNanoseconds == nil, "loss invalidates qualification even without a sample-time gap")
        let stats = try await transport.progress()
        expect(stats.captureDroppedFrames == 1200 && stats.captureOverflowEvents == 1, "ring loss witnessed")
        await transport.close()
    }

    static func deviceLifecycle() async throws {
        let hardware = FakeVoiceHardware()
        let transport = hardware.makeTransport()
        try await transport.start(identity: identity())
        let old = hardware.update { $0.graphs[0] }
        let before = old.read().snapshots
        old.read().deviceChanged?() // A devices-list notification without a route or format change.
        try await eventually { old.read().snapshots > before }
        await expect(transport.state == .running && old.read().stops == 0, "unrelated device enumeration is harmless")

        hardware.update { $0.snapshot = FakeVoiceHardware.makeSnapshot(members: [6, 8]) }
        old.read().deviceChanged?()
        try await eventually { await transport.state == .rebuildRequired }
        expect(old.read().stops == 1 && hardware.update { $0.graphs.count } == 1, "aggregate membership forces stop")
        do {
            try await transport.rebuild(identity: identity())
            preconditionFailure("reused a retired identity")
        } catch NativeVoiceTransportError.staleIdentity {}

        hardware.update { $0.snapshot = FakeVoiceHardware.makeSnapshot(capture: 32000, render: 44100) }
        try await transport.rebuild(identity: identity(2))
        let fresh = hardware.update { $0.graphs[1] }
        expect(fresh.read().installedPlan?.capture.sampleRate == 32000, "rebuild renegotiates capture")
        expect(fresh.read().installedPlan?.source.sampleRate == 44100, "rebuild renegotiates mono render")
        old.read().configurationChanged?()
        old.capture([1], sampleTime: 0, hostTime: 0, flags: 0)
        expect(old.render(19).allSatisfy { $0 == 0 }, "retired callbacks stay bound to their retired graph")
        await expect(try transport.service(maxCaptureFrames: 32).isEmpty, "old capture cannot populate the new graph")
        await expect(
            transport.state == .running && fresh.read().stops == 0,
            "late notification cannot stop the new graph"
        )
        fresh.read().configurationChanged?()
        try await eventually { await transport.state == .rebuildRequired }
        expect(fresh.read().stops == 1, "engine configuration notification is a definitive invalidation")
    }

    static func startupFailures() async throws {
        for fault in FakeVoiceFailure.allCases {
            let hardware = FakeVoiceHardware()
            hardware.update { $0.failure = fault }
            let transport = hardware.makeTransport()
            do {
                try await transport.start(identity: identity())
                preconditionFailure("ignored fake failure")
            } catch let injected as FakeVoiceFailure {
                expect(injected == fault, "propagate the failed startup step")
            }
            let graph = hardware.update { $0.graphs[0] }
            let attempted = graph.read()
            await expect(transport.state == .rebuildRequired && attempted.stops == 1, "partial startup rolls back once")
            if attempted.lease != nil {
                expect(!nvt_rt_active(attempted.lease!.context), "failed graph cannot be activated by a late callback")
            }
            do {
                try await transport.start(identity: identity())
                preconditionFailure("implicit retry")
            } catch NativeVoiceSessionError.state {}
            expect(hardware.update { $0.graphs.count } == 1, "failure never schedules another attempt")
            await transport.close()
            await transport.close()
            expect(graph.read().stops == 1, "failed stop is idempotent")
        }
    }

    static func permissionLifecycle() async throws {
        let denied = FakeVoiceHardware()
        denied.update { $0.authorized = false }
        let inactive = denied.makeTransport()
        do {
            try await inactive.start(identity: identity())
            preconditionFailure("no permission")
        } catch NativeVoiceSessionError.permission {}
        expect(denied.update { $0.graphs.isEmpty }, "permission checked before engine creation")

        let hardware = FakeVoiceHardware()
        let transport = hardware.makeTransport()
        try await transport.start(identity: identity())
        do {
            try await transport.start(identity: identity())
            preconditionFailure("duplicate start")
        } catch NativeVoiceSessionError.state {}
        let graph = hardware.update { $0.graphs[0] }
        hardware.update { $0.authorized = false }
        await transport.permissionRevoked()
        await transport.close()
        await expect(transport.state == .closed && graph.read().stops == 1, "revocation closes once")
        expect(graph.render(19).allSatisfy { $0 == 0 }, "revocation mutes the old graph")
    }
}

extension SessionTests {
    static func eventually(_ check: () async -> Bool) async throws {
        for _ in 0 ..< 250 {
            if await check() {
                return
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        preconditionFailure("expected fake notification")
    }
}
