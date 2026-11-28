@preconcurrency import AudioToolbox
import Foundation

extension DirectVPIOTests {
    static func splitAUHAL() async throws {
        splitAdmission()
        onsetAdmission()
        try await splitSession()
        for fault in [FakeDirectVPIO.Failure.create, .format, .callback, .initialize, .listen, .start] {
            try await splitRollback(voice: FakeDirectVPIO(), output: splitOutput(fault))
        }
        for fault in [FakeDirectVPIO.Failure.initialize, .start] {
            try await splitRollback(voice: FakeDirectVPIO(fault), output: splitOutput())
        }
        try await splitReadbackFailures()
    }

    private static func splitAdmission() {
        let split = NativeVoiceSameFrameLaunch.splitAUHALArgument
        let args = ["Aftelle", split]
        check(NativeVoiceSameFrameLaunch.isRequested(args), "intercept split candidate")
        check(NativeVoiceSameFrameLaunch.isAllowed(args, authorized: true), "explicit split admission")
        check(NativeVoiceSameFrameLaunch.backendTag(args) == NativeVoiceSameFrameLaunch.splitAUHALBackend,
              "split backend tag")
        check(!NativeVoiceSameFrameLaunch.isAllowed(args, authorized: false), "split permission gate")
        check(!NativeVoiceDirectVPIOLaunch.isRequested(args), "split is separate from direct")
        let conflicts = [split, NativeVoiceDirectVPIOLaunch.argument, NativeVoiceSameFrameLaunch.argument,
                         "--apple-native-voice-candidate"]
        for conflict in conflicts {
            check(!NativeVoiceSameFrameLaunch.isAllowed(args + [conflict], authorized: true), "exclusive split launch")
        }
        let malformed = ["Aftelle", split + "=true"]
        check(NativeVoiceSameFrameLaunch.isRequested(malformed)
            && !NativeVoiceSameFrameLaunch.isAllowed(malformed, authorized: true), "intercept malformed split launch")
    }

    private static func onsetAdmission() {
        let onset = NativeVoiceSameFrameLaunch.onsetHistoryArgument
        let args = ["Aftelle", onset]
        check(NativeVoiceSameFrameLaunch.isRequested(args) && NativeVoiceSameFrameLaunch.isOnsetHistory(args),
              "exact onset launch routes to the lab")
        let authorized = NativeVoiceSameFrameLaunch.isAllowed(args, authorized: true)
        let unauthorized = NativeVoiceSameFrameLaunch.isAllowed(args, authorized: false)
        check(authorized && !unauthorized, "onset launch retains authorization gate")
        check(NativeVoiceSameFrameLaunch.backendTag(args) == NativeVoiceSameFrameLaunch.splitAUHALBackend,
              "onset entry selects the split backend")
        let ordinaryFlags = [
            NativeVoiceSameFrameLaunch.splitAUHALArgument,
            NativeVoiceDirectVPIOLaunch.argument,
            NativeVoiceSameFrameLaunch.argument
        ]
        let conflicts = [["Aftelle", onset + "=true"]] + (ordinaryFlags + [onset]).map { args + [$0] }
        for wrong in conflicts {
            check(NativeVoiceSameFrameLaunch.isRequested(wrong)
                && !NativeVoiceSameFrameLaunch.isAllowed(wrong, authorized: true), "ambiguous onset entry fails closed")
        }
        for flag in ordinaryFlags {
            let ordinary = ["Aftelle", flag]
            let ordinaryAuthorized = NativeVoiceSameFrameLaunch.isAllowed(ordinary, authorized: true)
            check(!NativeVoiceSameFrameLaunch.isOnsetHistory(ordinary) && ordinaryAuthorized,
                  "ordinary lab flags stay independent")
        }
    }

    private static func splitOutput(_ failure: FakeDirectVPIO.Failure = .none) -> FakeDirectVPIO {
        let output = FakeDirectVPIO(failure, unitID: 23)
        let hardwareFormat = FakeDirectVPIO.Key(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0)
        output.put(hardwareFormat, output.pcm(rate: 48000, channels: 2))
        output.put(.init(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1), UInt32(1))
        return output
    }

    private static func splitSession() async throws {
        let voice = FakeDirectVPIO()
        let output = splitOutput()
        let cleanup = NativeVoiceDirectVPIOCleanup()
        let transport = voice.transport(cleanup: cleanup, splitOutput: output)
        try await transport.start(identity: identity)
        let readback = await transport.readback()
        verifySplitSetup(voice: voice, output: output, readback: readback)

        let pcm = Data(repeating: 0x11, count: 480)
        try await transport.beginPlayback(identity.playback)
        try check(await transport.enqueuePlayback(pcm, identity: identity.playback), "split Worker enqueues PCM")
        try check(await transport.finishPlayback(identity: identity.playback), "split Worker enqueues EOS")
        let silent = try voice.render(frames: 16)
        let before = try await transport.bridgeService(maxCaptureFrames: 128)
        check(silent.silent && silent.samples.allSatisfy { $0 == 0 } && before.render.isEmpty,
              "VPIO bus 0 does not consume, acknowledge or emit render facts")
        let first = try output.render(frames: 32)
        let fact = try await transport.bridgeService(maxCaptureFrames: 128).render.first
        check(!first.silent && first.samples.contains { $0 != 0 }, "AUHAL consumes the resident PCM")
        check(fact?.playback == identity.playback && fact?.sampleTime == 123 && fact?.hostTime == 456,
              "AUHAL timestamps flow into the actual consumer fact")
        var sawEnd = false
        for _ in 0 ..< 20 {
            _ = try output.render(frames: 64)
            if try await transport.bridgeService(maxCaptureFrames: 128).render.contains(where: \.isDigitalHandoff) {
                sawEnd = true
                break
            }
        }
        check(sawEnd, "AUHAL, as consumer, emits EOS")

        try await verifyPlaybackClear(transport, voice: voice, output: output, pcm: pcm)

        output.invalidateUnitRoute()
        try check(voice.render(frames: 16).silent && output.render(frames: 16).silent, "shared route fence")
        do {
            _ = try await transport.bridgeService(maxCaptureFrames: 128)
            throw Unexpected.success
        } catch NativeVoiceSessionError.route {
            check(await transport.state == .rebuildRequired, "AUHAL route change invalidates both units")
        }
        await transport.close()
        check(cleanup.report?.failed == false && cleanup.splitPlaybackReport?.failed == false, "both cleanup receipts")
        check(voice.lifecycle.last == "dispose" && output.lifecycle.last == "dispose", "both units disposed")
        check(voice.lifecycle.filter { $0 == "stop" }.count == 1
            && output.lifecycle.filter { $0 == "stop" }.count == 1,
            "repeated close is idempotent")
    }

    private static func verifyPlaybackClear(
        _ transport: AppleNativeVoiceTransport, voice: FakeDirectVPIO, output: FakeDirectVPIO, pcm: Data
    ) async throws {
        let replacement = NativeVoiceIdentity.Playback(authority: identity.playback.authority, epoch: 2, token: 2)
        try await transport.cancelPlayback(identity.playback, replacingWith: replacement)
        _ = try voice.render(frames: 16)
        try check(await !transport.bridgeService(maxCaptureFrames: 128).progress.renderClearAcknowledged,
                  "VPIO silence never acknowledges clear")
        let cleared = try output.render(frames: 32)
        let after = try await transport.bridgeService(maxCaptureFrames: 128)
        check(cleared.silent && cleared.samples.allSatisfy { $0 == 0 }
            && after.progress.renderClearAcknowledged, "AUHAL acknowledges clear without stale samples")
        do {
            _ = try await transport.enqueuePlayback(pcm, identity: identity.playback)
            throw Unexpected.success
        } catch NativeVoiceTransportError.staleIdentity {
            check(true, "old token stays rejected")
        }
    }

    private static func verifySplitSetup(
        voice: FakeDirectVPIO, output: FakeDirectVPIO, readback: NativeVoiceTransportReadback?
    ) {
        check(readback?.formats["sink"]?.sampleRate == 44100 && readback?.formats["source"]?.sampleRate == 48000,
              "capture and playback each use their negotiated SRC rate")
        check(readback?.route.outputUnitDevice == 202, "reference output route")
        check(output.captureCallback == nil && voice.captureCallback != nil, "only VPIO captures")
        check(voice.renderCallback?.inputProcRefCon == output.renderCallback?.inputProcRefCon, "shared lease reference")
        let setup = output.writes.prefix(4)
        check(setup.map(\.key.id) == [
            kAudioOutputUnitProperty_EnableIO, kAudioOutputUnitProperty_EnableIO,
            kAudioOutputUnitProperty_CurrentDevice, kAudioUnitProperty_StreamFormat
        ], "AUHAL I/O before device and format")
        check(setup.prefix(3).map { $0.bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } } == [0, 1, 202],
              "AUHAL is output-only with the same reference AudioDeviceID")
        let maps = output.writes.filter { $0.key.id == kAudioOutputUnitProperty_ChannelMap }
        check(maps.count == 1 && maps[0].key.scope == kAudioUnitScope_Output && maps[0].key.bus == 0
            && maps[0].bytes == Data(repeating: 0, count: 8), "mono source at unity to both hardware channels")
    }

    private static func splitRollback(
        voice: FakeDirectVPIO, output: FakeDirectVPIO, stage: String? = nil
    ) async throws {
        let cleanup = NativeVoiceDirectVPIOCleanup()
        let transport = voice.transport(cleanup: cleanup, splitOutput: output)
        do {
            try await transport.start(identity: identity)
            throw Unexpected.success
        } catch let error as NativeVoiceDirectVPIOFailure {
            if let stage { check(error.stage == stage, "first failure stage: \(error.stage)") }
            check(await transport.state == .rebuildRequired, "failed split startup is contained")
        }
        for device in [voice, output] {
            let created = device.lifecycle.contains("create") && device.failure != .create
            check(device.lifecycle.filter { $0 == "dispose" }.count == (created ? 1 : 0), "each created unit disposed")
            check(device.lifecycle.contains("stop") == device.lifecycle.contains("start"), "stop attempted start")
            let initialized = device.lifecycle.contains("initialize") && device.failure != .initialize
            check(device.lifecycle.contains("uninitialize") == initialized, "uninitialize initialized unit")
        }
        if voice.failure != .start, output.failure != .start {
            check(!voice.lifecycle.contains("start") && !output.lifecycle.contains("start"),
                  "no start after negotiation or setup failure")
        }
        let before = (voice.lifecycle, output.lifecycle)
        await transport.close()
        check(voice.lifecycle == before.0 && output.lifecycle == before.1, "startup rollback cannot repeat")
    }

    private static func splitReadbackFailures() async throws {
        let wrongDevice = splitOutput()
        wrongDevice.configure = { [unowned wrongDevice] api in
            let initialize = api.initialize
            api.initialize = { unit in
                let status = initialize(unit)
                wrongDevice.put(.init(kAudioOutputUnitProperty_CurrentDevice), UInt32(203))
                return status
            }
        }
        try await splitRollback(
            voice: FakeDirectVPIO(), output: wrongDevice, stage: "split_auhal.reference_device_mismatch"
        )

        let wrongFormat = splitOutput()
        wrongFormat.configure = { [unowned wrongFormat] api in
            let initialize = api.initialize
            api.initialize = { unit in
                let status = initialize(unit)
                wrongFormat.put(.renderFormat, wrongFormat.pcm(rate: 44100, channels: 1))
                return status
            }
        }
        try await splitRollback(
            voice: FakeDirectVPIO(), output: wrongFormat, stage: "split_auhal.client_device_format_mismatch"
        )

        let changedVoice = FakeDirectVPIO()
        changedVoice.configure = { [unowned changedVoice] api in
            let initialize = api.initialize
            api.initialize = { unit in
                let status = initialize(unit)
                changedVoice.put(.captureFormat, changedVoice.pcm(rate: 44100, channels: 1))
                return status
            }
        }
        try await splitRollback(voice: changedVoice, output: splitOutput(), stage: "split_auhal.vpio_format_changed")
    }

    static func splitReleaseFailure(_ mode: String) async throws {
        let voice = FakeDirectVPIO()
        let output = splitOutput()
        let failed = mode == "split-output-stop" ? output : voice
        failed.configure = { api in
            let stop = api.stop
            api.stop = { unit in
                _ = stop(unit)
                return kAudioUnitErr_CannotDoInCurrentContext
            }
        }
        let receipt = NativeVoiceDirectVPIOCleanup()
        let transport = voice.transport(cleanup: receipt, splitOutput: output)
        try await transport.start(identity: identity)
        await transport.close()
        check(receipt.report?.failed == (failed === voice)
            && receipt.splitPlaybackReport?.failed == (failed === output),
            "release receipt attributes the failure to the unit")
        check(voice.lifecycle.last == "dispose" && output.lifecycle.last == "dispose",
              "release attempts continue on both units")
        try check(voice.render(frames: 8).silent && output.render(frames: 8).silent,
                  "late callbacks stay valid and silent after uncertain stop")
        let second = FakeDirectVPIO().transport()
        do {
            try await second.start(identity: identity)
            throw Unexpected.success
        } catch let error as NativeVoiceDirectVPIOFailure {
            check(error.stage == "unit_in_use", "quarantine covers Direct VPIO and split")
        }
        await second.close()
        await transport.close()
        check(voice.lifecycle.filter { $0 == "dispose" }.count == 1
            && output.lifecycle.filter { $0 == "dispose" }.count == 1,
            "release fault cannot trigger a second disposal")
    }
}
