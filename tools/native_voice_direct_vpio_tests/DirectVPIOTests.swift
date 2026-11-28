@preconcurrency import AudioToolbox
@preconcurrency import CoreAudio
import Foundation

@main
@MainActor
struct DirectVPIOTests {
    private static var checks = 0
    static let identity = NativeVoiceIdentity(
        authority: .init(runtimeGeneration: 0, routeEpoch: 0, configurationID: 41),
        captureGeneration: 1, captureToken: 1, playbackEpoch: 1, playbackToken: 1
    )

    static func main() async throws {
        if let mode = CommandLine.arguments.dropFirst().first {
            try await isolatedReleaseFailure(mode)
        } else {
            admission()
            try await session()
            try await fallbackFormat()
            try await exclusive()
            for failure in FakeDirectVPIO.Failure.allCases where failure != .none {
                try await rollback(failure)
            }
            try await enableIOCompatibility()
            try await cleanRelease()
        }
        print("native_voice_direct_vpio_swift_checks=\(checks)")
    }

    static func check(_ test: Bool, _ message: String) {
        precondition(test, message)
        checks += 1
    }

    private static func admission() {
        let argument = NativeVoiceDirectVPIOLaunch.argument
        check(NativeVoiceDirectVPIOLaunch.isAllowed(["Aftelle", argument], authorized: true), "explicit launch")
        check(!NativeVoiceDirectVPIOLaunch.isAllowed(["Aftelle", argument], authorized: false), "compile authorization")
        let denied = [[argument + "=1"], [argument, argument], [argument, NativeVoiceSameFrameLaunch.argument],
                      [argument, "--apple-native-voice-candidate"], [NativeVoiceSameFrameLaunch.argument]]
        for args in denied {
            check(!NativeVoiceDirectVPIOLaunch.isAllowed(["Aftelle"] + args, authorized: true), "exclusive argument")
        }
        check(NativeVoiceSameFrameLaunch.isRequested(["Aftelle", argument]), "the entry intercepts the candidate")
        check(NativeVoiceSameFrameLaunch.isAllowed(["Aftelle", argument], authorized: true),
              "the entry admits the candidate")
        check(NativeVoiceSameFrameLaunch.backendTag(["Aftelle", NativeVoiceSameFrameLaunch.argument]) == nil,
              "the original entry keeps its original backend")
        check(NativeVoiceDirectVPIOLaunch.isRequested(["Aftelle", argument + "=1"]), "malformed request is intercepted")
        check(!NativeVoiceDirectVPIOLaunch.isRequested(["Aftelle", NativeVoiceSameFrameLaunch.argument]), "old launch")
    }

    private static func session() async throws {
        let fake = FakeDirectVPIO()
        let transport = fake.transport()
        try await transport.start(identity: identity)
        verifySetup(fake, await transport.readback())

        try await transport.beginPlayback(identity.playback)
        let pcm = Data(repeating: 0x11, count: 4800)
        let accepted = try await transport.enqueuePlayback(pcm, identity: identity.playback)
        check(accepted, "Worker/SRC accepts resident PCM")
        let output = try fake.render(frames: 32)
        check(output.samples.contains { $0 != 0 } && !output.silent, "render uses the same Worker and ring")
        let batch = try await transport.bridgeService(maxCaptureFrames: 128)
        check(batch.render.first?.playback == identity.playback
            && batch.render.first?.frameCount == 32 && batch.render.first?.hostTime == 456, "real render fact fields")

        let replacement = NativeVoiceIdentity.Playback(authority: identity.playback.authority, epoch: 2, token: 2)
        try await transport.cancelPlayback(identity.playback, replacingWith: replacement)
        let cleared = try fake.render(frames: 32)
        let afterClear = try await transport.bridgeService(maxCaptureFrames: 128)
        check(cleared.silent && cleared.samples.allSatisfy { $0 == 0 }
            && afterClear.progress.renderClearAcknowledged, "cancellation uses the existing clear fence")

        fake.invalidateUnitRoute()
        try check(fake.render(frames: 16).silent, "property invalidation silences callbacks before actor teardown")
        do {
            _ = try await transport.bridgeService(maxCaptureFrames: 128)
            throw Unexpected.success
        } catch NativeVoiceSessionError.route {
            check(await transport.state == .rebuildRequired, "route changed safely")
        }
        await transport.close()
        let lifecycle = fake.lifecycle
        check(Array(lifecycle.suffix(5)) == ["stop", "unlisten.8", "unlisten.2000", "uninitialize", "dispose"],
              "ordered stop and disposal")
        check(fake.removed.count == fake.watched.count, "HAL registrations removed")
        await transport.close()
        check(fake.lifecycle == lifecycle, "close is idempotent")
    }

    private static func verifySetup(_ fake: FakeDirectVPIO, _ readback: NativeVoiceTransportReadback?) {
        let addresses = fake.writes.map(\.key)
        check(Array(addresses.prefix(4)) == [
            .init(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1),
            .init(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0),
            .init(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 1),
            .init(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0)
        ], "I/O and directions")
        check(Array(addresses.suffix(4)) == [
            .captureFormat, .renderFormat,
            .init(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1),
            .init(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0)
        ], "client format and callback addresses")
        let controls = fake.writes.filter {
            [kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAUVoiceIOProperty_BypassVoiceProcessing,
             kAUVoiceIOProperty_MuteOutput].contains($0.key.id)
        }
        check(controls.map { $0.bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } } == [1, 0, 0], "VP values")
        check(controls.allSatisfy { $0.key.scope == kAudioUnitScope_Global && $0.key.bus == 1 }, "VP scope")
        check(fake.lifecycle == ["create", "initialize", "listen.2000", "listen.8", "start"], "control order")
        check(fake.captureCallback?.inputProcRefCon == fake.renderCallback?.inputProcRefCon
            && fake.captureCallback != nil, "callbacks share the unit's storage")
        check(readback?.formats["sink"]?.channels == 4 && readback?.formats["source"]?.channels == 1, "formats")
        check(readback?.formats["source"]?.sampleRate == 44100, "no fixed sample rate")
        check(readback?.route.inputUnitDevice == 101 && readback?.route.outputUnitDevice == 202,
              "directional readback")
        check(fake.watched.contains(kAudioHardwarePropertyDefaultInputDevice)
            && fake.watched.contains(kAudioDevicePropertyDeviceIsAlive), "reuse HAL watches")
    }

    private static func fallbackFormat() async throws {
        let fake = FakeDirectVPIO()
        fake.acceptedRate = 48000
        let transport = fake.transport()
        try await transport.start(identity: identity)
        let readback = await transport.readback()
        check(readback?.formats["sink"]?.sampleRate == 48000, "try another offered rate")
        check(fake.writes.filter { $0.key == .captureFormat }.count > 1, "original rate was rejected")
        await transport.close()
    }

    private static func exclusive() async throws {
        let fake = FakeDirectVPIO()
        let first = fake.transport()
        try await first.start(identity: identity)
        let other = FakeDirectVPIO()
        let second = other.transport()
        do {
            try await second.start(identity: identity)
            throw Unexpected.success
        } catch let error as NativeVoiceDirectVPIOFailure {
            check(error.stage == "unit_in_use" && other.lifecycle.isEmpty, "one process slot")
        }
        await second.close()
        await first.close()
    }

    private static func rollback(_ failure: FakeDirectVPIO.Failure) async throws {
        let fake = FakeDirectVPIO(failure)
        let transport = fake.transport()
        do {
            try await transport.start(identity: identity)
            throw Unexpected.success
        } catch is Unexpected {
            throw Unexpected.success
        } catch {
            check(await transport.state == .rebuildRequired, "failure is contained")
        }
        let cleanup = fake.lifecycle
        if failure == .create {
            check(cleanup == ["create"], "no unit to dispose")
        } else {
            check(cleanup.last == "dispose" && cleanup.filter { $0 == "dispose" }.count == 1, "release exactly once")
        }
        check(cleanup.contains("stop") == [.start, .watch].contains(failure), "stop after attempting start")
        check(cleanup.contains("uninitialize") == [.listen, .route, .formatReadback, .frames, .start, .watch]
            .contains(failure), "uninitialize exactly after successful initialization")
        if failure == .route || failure == .formatReadback || failure == .frames {
            check(!cleanup.contains("start"), "do not start an unverified route or format")
        }
        await transport.close()
        check(fake.lifecycle == cleanup, "cleanup repeated")
    }

    enum Unexpected: Error { case success }
}

final nonisolated class FakeDirectVPIO: @unchecked Sendable {
    struct Key: Hashable {
        let id: AudioUnitPropertyID
        let scope: AudioUnitScope
        let bus: AudioUnitElement

        init(_ id: AudioUnitPropertyID, _ scope: AudioUnitScope = kAudioUnitScope_Global, _ bus: AudioUnitElement = 0) {
            self.id = id
            self.scope = scope
            self.bus = bus
        }

        static let captureFormat = Key(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1)
        static let renderFormat = Key(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0)
    }

    enum Failure: CaseIterable {
        case none, create, format, callback, initialize, listen, route, formatReadback, frames, start, watch
    }

    let failure: Failure
    let unit = AudioUnit(bitPattern: 17)!
    var acceptedRate: Double?
    var configure: ((inout NativeVoiceDirectVPIO.UnitAPI) -> Void)?
    var lifecycle: [String] = []
    var writes: [(key: Key, bytes: Data)] = []
    var captureCallback, renderCallback: AURenderCallbackStruct?
    var watched: [AudioObjectPropertySelector] = []
    var removed: [AudioObjectPropertySelector] = []
    private var values = [Key: Data]()
    private var listeners = [AudioUnitPropertyID: (AudioUnitPropertyListenerProc, UnsafeMutableRawPointer?)]()

    init(_ failure: Failure = .none) {
        self.failure = failure
        put(.captureFormat, pcm(rate: 44100, channels: 4))
        put(.renderFormat, pcm(rate: 48000, channels: 1))
        put(.init(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1), UInt32(0))
        put(.init(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0), UInt32(0))
        put(.init(kAudioOutputUnitProperty_IsRunning), UInt32(0))
        put(.init(kAudioUnitProperty_MaximumFramesPerSlice), UInt32(64))
    }

    func transport(cleanup: NativeVoiceDirectVPIOCleanup = .init()) -> AppleNativeVoiceTransport {
        .init(makeEngine: { [self] in makeEngine(cleanup: cleanup) },
              authorized: { true }, limits: .init(callbackFrames: 128))
    }

    private func unitAPI() -> NativeVoiceDirectVPIO.UnitAPI {
        var api = NativeVoiceDirectVPIO.UnitAPI()
        api.create = { [self] in
            lifecycle.append("create")
            if failure == .create {
                throw NativeVoiceDirectVPIOFailure(stage: "test_create")
            }
            return unit
        }
        api.get = { [self] _, id, scope, bus, bytes, size in read(Key(id, scope, bus), bytes, size) }
        api.set = { [self] _, id, scope, bus, bytes, size in write(Key(id, scope, bus), bytes!, Int(size)) }
        api.initialize = { [self] _ in initialize() }
        api.start = { [self] _ in
            lifecycle.append("start")
            put(.init(kAudioOutputUnitProperty_IsRunning), UInt32(1))
            return failure == .start ? kAudioUnitErr_FailedInitialization : noErr
        }
        api.stop = { [self] _ in
            lifecycle.append("stop")
            put(.init(kAudioOutputUnitProperty_IsRunning), UInt32(0))
            return noErr
        }
        api.uninitialize = { [self] _ in lifecycle.append("uninitialize"); return noErr }
        api.dispose = { [self] _ in lifecycle.append("dispose"); return noErr }
        api.listen = { [self] _, id, proc, ref in
            lifecycle.append("listen.\(id)")
            if failure == .listen, !listeners.isEmpty {
                return kAudioUnitErr_InvalidProperty
            }
            listeners[id] = (proc, ref)
            return noErr
        }
        api.unlisten = { [self] _, id, _, _ in
            lifecycle.append("unlisten.\(id)")
            listeners[id] = nil
            return noErr
        }

        configure?(&api)
        return api
    }

    private func makeEngine(cleanup: NativeVoiceDirectVPIOCleanup) -> NativeVoiceDirectVPIO {
        let routes = NativeVoiceDirectVPIO.RouteAPI(
            defaults: { .init(input: 101, output: 202) },
            bindings: { _ in
                [Self.binding(101, input: true), Self.binding(202, input: false)]
            },
            streams: { _ in [] }
        )
        let registration = NativeVoiceHALRoute.Registration(
            hasProperty: { _, _ in true },
            add: { [self] _, address, _, _ in
                if failure == .watch {
                    return -1
                }
                watched.append(address.mSelector)
                return noErr
            },
            remove: { [self] _, address, _, _ in removed.append(address.mSelector) }
        )
        return NativeVoiceDirectVPIO(
            callbackLimit: 128, api: unitAPI(), route: routes,
            devices: NativeVoiceHALRoute(registration: registration), cleanup: cleanup
        )
    }

    private func initialize() -> OSStatus {
        lifecycle.append("initialize")
        switch failure {
        case .initialize: return kAudioUnitErr_FailedInitialization
        case .route:
            put(.init(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 1), UInt32(202))
        case .formatReadback: put(.renderFormat, pcm(rate: 44100, channels: 2))
        case .frames: put(.init(kAudioUnitProperty_MaximumFramesPerSlice), UInt32(129))
        default: break
        }
        return noErr
    }

    private func read(
        _ key: Key, _ destination: UnsafeMutableRawPointer, _ size: UnsafeMutablePointer<UInt32>
    ) -> OSStatus {
        guard let data = values[key], size.pointee >= data.count else { return kAudioUnitErr_InvalidProperty }
        data.copyBytes(to: destination.assumingMemoryBound(to: UInt8.self), count: data.count)
        size.pointee = UInt32(data.count)
        return noErr
    }

    private func write(_ key: Key, _ source: UnsafeRawPointer, _ size: Int) -> OSStatus {
        let bytes = Data(bytes: source, count: size)
        writes.append((key, bytes))
        if key == .captureFormat || key == .renderFormat {
            let format = source.loadUnaligned(as: AudioStreamBasicDescription.self)
            if failure == .format || acceptedRate.map({ $0 != format.mSampleRate }) == true {
                return kAudioUnitErr_FormatNotSupported
            }
        }
        switch key.id {
        case kAudioOutputUnitProperty_SetInputCallback:
            captureCallback = source.loadUnaligned(as: AURenderCallbackStruct.self)
        case kAudioUnitProperty_SetRenderCallback:
            if failure == .callback {
                return kAudioUnitErr_InvalidProperty
            }
            renderCallback = source.loadUnaligned(as: AURenderCallbackStruct.self)
        default: break
        }
        values[key] = bytes
        return noErr
    }

    func invalidateUnitRoute() {
        let id = kAudioOutputUnitProperty_CurrentDevice
        let (proc, ref) = listeners[id]!
        proc(ref!, unit, id, kAudioUnitScope_Global, 1)
    }

    func render(frames: UInt32) throws -> (samples: [Float], silent: Bool) {
        var stamp = AudioTimeStamp()
        stamp.mSampleTime = 123
        stamp.mHostTime = 456
        stamp.mFlags = [.sampleTimeValid, .hostTimeValid]
        var flags: AudioUnitRenderActionFlags = []
        var samples = [Float](repeating: -1, count: Int(frames))
        let callback = renderCallback!
        let status = samples.withUnsafeMutableBufferPointer { pointer in
            var output = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: 4 * frames, mData: pointer.baseAddress
            ))
            return callback.inputProc!(callback.inputProcRefCon!, &flags, &stamp, 0, frames, &output)
        }
        guard status == noErr else { throw NativeVoiceDirectVPIOFailure(stage: "test_render", code: status) }
        return (samples, flags.contains(.unitRenderAction_OutputIsSilence))
    }

    private func put<T>(_ key: Key, _ value: T) {
        values[key] = withUnsafeBytes(of: value) { Data($0) }
    }

    private func pcm(rate: Double, channels: UInt32) -> AudioStreamBasicDescription {
        .init(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0
        )
    }

    private static func binding(_ id: UInt32, input: Bool) -> NativeVoiceDeviceBinding {
        .init(
            id: id, uid: "fake-\(id)", nominalRate: input ? 44100 : 48000,
            inputStreams: [], outputStreams: [], inputChannels: input ? [1] : [],
            outputChannels: input ? [] : [2], aggregateUIDs: nil, activeMembers: nil, clockMemberUID: nil
        )
    }
}
