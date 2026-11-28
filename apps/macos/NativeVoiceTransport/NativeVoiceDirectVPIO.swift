#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS && NATIVE_VOICE_DIRECT_VPIO
@preconcurrency import AudioToolbox
@preconcurrency import AVFoundation
import Foundation
import os

nonisolated enum NativeVoiceDirectVPIOLaunch {
    static let argument = "--apple-native-voice-direct-vpio-candidate"

    static func isRequested(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains { $0 == argument || $0.hasPrefix(argument + "=") }
    }

    static func isAllowed(_ arguments: [String], authorized: Bool) -> Bool {
        authorized && arguments.dropFirst().elementsEqual([argument])
    }
}

nonisolated struct NativeVoiceDirectVPIOFailure: Error {
    let stage: String
    var code: OSStatus?

    var detail: String {
        code.map { "\(stage) / OSStatus \($0)" } ?? stage
    }
}

extension AppleNativeVoiceTransport {
    static func directVPIO(limits: Limits) -> AppleNativeVoiceTransport {
        AppleNativeVoiceTransport(
            makeEngine: { NativeVoiceDirectVPIO(callbackLimit: limits.callbackFrames) },
            authorized: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
            limits: limits
        )
    }
}

/// A single stopped Audio Unit is negotiated before the transport allocates its Worker.
final nonisolated class NativeVoiceDirectVPIO: NativeVoiceGraphBackend, NativeVoiceSameFrameSystemReading {
    struct UnitAPI {
        var create: () throws -> AudioUnit = NativeVoiceDirectVPIO.createUnit
        var get = AudioUnitGetProperty
        var set = AudioUnitSetProperty
        var initialize = AudioUnitInitialize
        var start = AudioOutputUnitStart
        var stop = AudioOutputUnitStop
        var uninitialize = AudioUnitUninitialize
        var dispose = AudioComponentInstanceDispose
        var listen = AudioUnitAddPropertyListener
        var unlisten = AudioUnitRemovePropertyListenerWithUserData
    }

    struct RouteAPI {
        var defaults = NativeVoiceHALRoute.defaultDevices
        var bindings = NativeVoiceHALRoute.bindings
        var streams = NativeVoiceHALRoute.streamBindings
    }

    private struct Property {
        let id: AudioUnitPropertyID
        let scope: AudioUnitScope
        let bus: AudioUnitElement

        init(
            _ id: AudioUnitPropertyID, _ scope: AudioUnitScope = kAudioUnitScope_Global,
            _ bus: AudioUnitElement = 0
        ) {
            self.id = id
            self.scope = scope
            self.bus = bus
        }

        var address: String {
            "\(id).\(scope).\(bus)"
        }

        static let inputIO = Property(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1)
        static let outputIO = Property(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0)
        static let captureFormat = Property(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1)
        static let renderFormat = Property(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0)
        static let inputDevice = Property(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 1)
        static let outputDevice = Property(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0)
    }

    private static let slot = OSAllocatedUnfairLock(initialState: false)
    private static let processing = NativeVoiceProcessingReadback(
        inputEnabled: true, outputEnabled: true, agcEnabled: true, bypassed: false, inputMuted: false
    )
    private let callbackLimit: UInt32
    private let api: UnitAPI
    private let route: RouteAPI
    private let devices: NativeVoiceHALRoute
    private var defaults: NativeVoiceGraphSnapshot.Defaults?
    private var plan: NativeVoiceGraphPlan?
    private var unit: AudioUnit?
    private var callbacks: OpaquePointer?
    private var retainedLease: Unmanaged<NativeVoiceCallbackLease>?
    private var watched: [AudioUnitPropertyID] = []
    private var initialized = false
    private var startAttempted = false
    private var ownsSlot = false

    init(
        callbackLimit: UInt32, api: UnitAPI = .init(), route: RouteAPI = .init(),
        devices: NativeVoiceHALRoute = .init()
    ) {
        self.callbackLimit = callbackLimit
        self.api = api
        self.route = route
        self.devices = devices
    }

    deinit { stop() }

    func negotiate() throws -> NativeVoiceGraphPlan {
        guard !ownsSlot else { throw NativeVoiceSessionError.state }
        let targets = try route.defaults()
        ownsSlot = Self.slot.withLock { inUse in
            guard !inUse else { return false }
            inUse = true
            return true
        }
        guard ownsSlot else { throw NativeVoiceDirectVPIOFailure(stage: "unit_in_use") }

        let unit = try api.create()
        self.unit = unit
        defaults = targets
        try write(unit, .inputIO, UInt32(1))
        try write(unit, .outputIO, UInt32(1))
        try write(unit, .inputDevice, targets.input)
        try write(unit, .outputDevice, targets.output)
        try writeVoice(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, 1)
        try writeVoice(unit, kAUVoiceIOProperty_BypassVoiceProcessing, 0)
        try writeVoice(unit, kAUVoiceIOProperty_MuteOutput, 0)
        let plan = try configureFormats(unit)
        self.plan = plan
        return plan
    }

    func install(
        _ plan: NativeVoiceGraphPlan,
        lease: NativeVoiceCallbackLease,
        configurationChanged _: @escaping @Sendable () -> Void
    ) throws {
        guard let unit, plan == self.plan, callbacks == nil, !initialized else {
            throw NativeVoiceSessionError.state
        }
        guard let context = nvt_direct_vpio_create(lease.context, unit) else {
            throw NativeVoiceTransportError.allocation
        }
        callbacks = context
        retainedLease = .passRetained(lease)
        let ref = UnsafeMutableRawPointer(context)
        try write(unit, Property(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1),
                  AURenderCallbackStruct(inputProc: nvt_direct_vpio_capture, inputProcRefCon: ref))
        try write(unit, Property(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0),
                  AURenderCallbackStruct(inputProc: nvt_direct_vpio_render, inputProcRefCon: ref))
        try Self.check(api.initialize(unit), "initialize")
        initialized = true
        // The unit can invalidate the lease synchronously even before the HAL listener or actor runs.
        for id in [kAudioOutputUnitProperty_CurrentDevice, kAudioUnitProperty_StreamFormat] {
            try Self.check(api.listen(unit, id, nvt_direct_vpio_changed, ref), "listen.\(id)")
            watched.append(id)
        }
    }

    func start() throws {
        guard let unit, initialized, !startAttempted else { throw NativeVoiceSessionError.state }
        _ = try validatedSnapshot(unit)
        startAttempted = true
        try Self.check(api.start(unit), "start")
    }

    func snapshot() throws -> NativeVoiceGraphSnapshot {
        guard let unit, startAttempted else { throw NativeVoiceSessionError.state }
        guard try read(unit, Property(kAudioOutputUnitProperty_IsRunning), UInt32(0)) != 0
        else { throw NativeVoiceDirectVPIOFailure(stage: "unit_not_running") }
        return try validatedSnapshot(unit)
    }

    func watchDevices(_ snapshot: NativeVoiceGraphSnapshot, changed: @escaping @Sendable () -> Void) throws {
        try devices.start(snapshot, changed: changed)
    }

    func stop() {
        retainedLease?.takeUnretainedValue().close()
        devices.stop()
        if let unit {
            self.unit = nil
            if startAttempted {
                _ = api.stop(unit)
            }
            if let callbacks {
                for id in watched.reversed() {
                    _ = api.unlisten(unit, id, nvt_direct_vpio_changed, UnsafeMutableRawPointer(callbacks))
                }
            }
            if initialized {
                _ = api.uninitialize(unit)
            }
            // If disposal fails, the unit may still hold refCon. Retire it closed
            // and keep the lease, callback storage and exclusive slot until process exit.
            guard api.dispose(unit) == noErr else { return }
        } else if callbacks != nil {
            return
        }
        nvt_direct_vpio_destroy(callbacks)
        callbacks = nil
        retainedLease?.release()
        retainedLease = nil
        if ownsSlot {
            ownsSlot = false
            Self.slot.withLock { $0 = false }
        }
    }
}

private extension NativeVoiceDirectVPIO {
    nonisolated func validatedSnapshot(_ unit: AudioUnit) throws -> NativeVoiceGraphSnapshot {
        let actualPlan = try formats(unit)
        let maximum = try read(unit, Property(kAudioUnitProperty_MaximumFramesPerSlice), UInt32(0))
        guard actualPlan == plan, maximum > 0, maximum <= callbackLimit
        else { throw NativeVoiceDirectVPIOFailure(stage: "client_format_or_callback_capacity") }
        let processing = try voiceProcessing(unit)
        guard processing == Self.processing else { throw NativeVoiceSessionError.voiceProcessing }
        let input = try read(unit, .inputDevice, UInt32(0))
        let output = try read(unit, .outputDevice, UInt32(0))
        let current = try route.defaults()
        guard current == defaults, input != 0, output != 0, input == current.input, output == current.output
        else { throw NativeVoiceDirectVPIOFailure(stage: "directional_route_unverified") }
        let bindings = try route.bindings([input, output])
        guard bindings.contains(where: { $0.id == input && $0.inputChannels.contains(where: { $0 > 0 }) }),
              bindings.contains(where: { $0.id == output && $0.outputChannels.contains(where: { $0 > 0 }) })
        else { throw NativeVoiceDirectVPIOFailure(stage: "device_directions_unverified") }
        return try .init(
            plan: actualPlan, defaults: current, inputUnitDevice: input, outputUnitDevice: output,
            bindings: bindings, streams: route.streams(bindings), voiceProcessing: processing
        )
    }

    private nonisolated func configureFormats(_ unit: AudioUnit) throws -> NativeVoiceGraphPlan {
        let capture = try read(unit, .captureFormat, AudioStreamBasicDescription())
        let render = try read(unit, .renderFormat, AudioStreamBasicDescription())
        let native = [Property(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1),
                      Property(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0)]
            .compactMap { try? read(unit, $0, AudioStreamBasicDescription()).mSampleRate }
        let channels: [UInt32] = (2 ... 32).contains(capture.mChannelsPerFrame) ? [capture.mChannelsPerFrame, 1] : [1]
        let planar = capture.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        var rates: Set<Double> = []
        var failure: Error = NativeVoiceDirectVPIOFailure(stage: "client_format_unavailable")
        let offered = [capture.mSampleRate, render.mSampleRate] + native
        for rate in offered where rate.isFinite && rate > 0 && rates.insert(rate).inserted {
            for count in channels {
                do {
                    try write(unit, .captureFormat, Self.floatFormat(rate, count, planar))
                    try write(unit, .renderFormat, Self.floatFormat(rate, 1, false))
                    return try formats(unit)
                } catch {
                    failure = error
                }
            }
        }
        throw failure
    }

    private nonisolated func formats(_ unit: AudioUnit) throws -> NativeVoiceGraphPlan {
        let capture = try Self.describe(read(unit, .captureFormat, AudioStreamBasicDescription()))
        let render = try Self.describe(read(unit, .renderFormat, AudioStreamBasicDescription()))
        guard render.channels == 1, capture.sampleRate == render.sampleRate
        else { throw NativeVoiceDirectVPIOFailure(stage: "incompatible_client_formats") }
        return NativeVoiceGraphPlan(capture: capture, render: render)
    }

    private nonisolated static func floatFormat(
        _ rate: Double, _ channels: UInt32, _ planar: Bool
    ) -> AudioStreamBasicDescription {
        let bytes: UInt32 = 4 * (planar ? 1 : channels)
        return .init(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
                | (planar ? kAudioFormatFlagIsNonInterleaved : 0),
            mBytesPerPacket: bytes, mFramesPerPacket: 1, mBytesPerFrame: bytes,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0
        )
    }

    private nonisolated static func describe(_ format: AudioStreamBasicDescription) throws -> NativeVoiceIOFormat {
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let float = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        guard format.mSampleRate.isFinite, format.mSampleRate > 0, (1 ... 32).contains(format.mChannelsPerFrame),
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & float == float,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mBitsPerChannel == 32, format.mFramesPerPacket == 1,
              format.mBytesPerPacket == format.mBytesPerFrame,
              format.mBytesPerFrame == 4 * (interleaved ? format.mChannelsPerFrame : 1)
        else { throw NativeVoiceDirectVPIOFailure(stage: "unsupported_client_format") }
        return .init(
            sampleRate: format.mSampleRate, channels: format.mChannelsPerFrame,
            interleaved: interleaved, float32: true
        )
    }

    private nonisolated func voiceProcessing(_ unit: AudioUnit) throws -> NativeVoiceProcessingReadback {
        let agc = try voiceProperty(kAUVoiceIOProperty_VoiceProcessingEnableAGC) { try read(unit, $0, UInt32(0)) }
        let bypass = try voiceProperty(kAUVoiceIOProperty_BypassVoiceProcessing) { try read(unit, $0, UInt32(0)) }
        let mute = try voiceProperty(kAUVoiceIOProperty_MuteOutput) { try read(unit, $0, UInt32(0)) }
        return try .init(
            inputEnabled: read(unit, .inputIO, UInt32(0)) == 1,
            outputEnabled: read(unit, .outputIO, UInt32(0)) == 1,
            agcEnabled: agc == 1, bypassed: bypass != 0, inputMuted: mute != 0
        )
    }

    private nonisolated func writeVoice(_ unit: AudioUnit, _ id: AudioUnitPropertyID, _ value: UInt32) throws {
        try voiceProperty(id) { try write(unit, $0, value) }
    }

    private nonisolated func voiceProperty<T>(_ id: AudioUnitPropertyID, access: (Property) throws -> T) throws -> T {
        do {
            return try access(Property(id, kAudioUnitScope_Global, 1))
        } catch let error as NativeVoiceDirectVPIOFailure {
            guard error.code == kAudioUnitErr_InvalidElement || error.code == kAudioUnitErr_InvalidProperty
            else { throw error }
            return try access(Property(id))
        }
    }

    private nonisolated func read<T>(_ unit: AudioUnit, _ property: Property, _ initial: T) throws -> T {
        var bytes = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            api.get(unit, property.id, property.scope, property.bus, buffer.baseAddress!, &bytes)
        }
        try Self.check(status, "read.\(property.address)")
        guard bytes == MemoryLayout<T>.size else {
            throw NativeVoiceDirectVPIOFailure(stage: "property_size.\(property.address)")
        }
        return value
    }

    private nonisolated func write<T>(_ unit: AudioUnit, _ property: Property, _ value: T) throws {
        let status = withUnsafeBytes(of: value) { buffer in
            api.set(unit, property.id, property.scope, property.bus, buffer.baseAddress!, UInt32(buffer.count))
        }
        try Self.check(status, "write.\(property.address)")
    }

    private nonisolated static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw NativeVoiceDirectVPIOFailure(stage: operation, code: status) }
    }

    private nonisolated static func createUnit() throws -> AudioUnit {
        var type = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &type)
        else { throw NativeVoiceDirectVPIOFailure(stage: "component_unavailable") }
        var instance: AudioUnit?
        try check(AudioComponentInstanceNew(component, &instance), "create")
        guard let instance else { throw NativeVoiceDirectVPIOFailure(stage: "unit_unavailable") }
        return instance
    }
}

extension NativeVoiceDirectVPIO {
    nonisolated func sameFrameSystemState() -> NativeVoiceSameFrameDiagnostics.SystemState {
        let current = try? route.defaults()
        let input = unit.flatMap { try? read($0, .inputDevice, UInt32(0)) }
        let output = unit.flatMap { try? read($0, .outputDevice, UInt32(0)) }
        let inputRoots = [current?.input, input].compactMap { $0 }
        let outputRoots = [current?.output, output].compactMap { $0 }
        let bindings = (try? route.bindings(inputRoots + outputRoots)) ?? []
        let inputMembers = bindings.first { $0.id == input }?.activeMembers
        let outputMembers = bindings.first { $0.id == output }?.activeMembers
        let ducking = unit.flatMap {
            try? read($0, Property(kAUVoiceIOProperty_OtherAudioDuckingConfiguration),
                      AUVoiceIOOtherAudioDuckingConfiguration())
        }
        return .init(
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            activeMicMode: AVCaptureDevice.activeMicrophoneMode.rawValue,
            preferredMicMode: AVCaptureDevice.preferredMicrophoneMode.rawValue, defaults: current,
            inputUnitDevice: input, outputUnitDevice: output,
            inputActiveMembers: inputMembers, outputActiveMembers: outputMembers,
            voiceProcessingRequested: Self.processing,
            voiceProcessingReadback: unit.flatMap { try? voiceProcessing($0) },
            ducking: ducking.map {
                .init(advanced: $0.mEnableAdvancedDucking.boolValue, level: Int($0.mDuckingLevel.rawValue))
            },
            deviceControls: NativeVoiceHALRoute.sameFrameControls(
                inputs: inputRoots + (inputMembers ?? []),
                outputs: outputRoots + (outputMembers ?? []), bindings: bindings
            )
        )
    }
}
#endif
