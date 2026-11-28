#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS && NATIVE_VOICE_DIRECT_VPIO
@preconcurrency import AudioToolbox

/// The Direct VPIO control path owns this output-only unit and retires both units together.
final nonisolated class NativeVoiceSplitAUHAL {
    private typealias Property = NativeVoiceDirectVPIO.Property

    private let api: NativeVoiceDirectVPIO.UnitAPI
    private let callbackLimit: UInt32
    private var unit: AudioUnit?
    private var voicePlan: NativeVoiceGraphPlan?
    private var deviceChannels: UInt32 = 0
    private var watched: [AudioUnitPropertyID] = []
    private var initialized = false
    private var startAttempted = false

    init(api: NativeVoiceDirectVPIO.UnitAPI, callbackLimit: UInt32) {
        self.api = api
        self.callbackLimit = callbackLimit
    }

    static func createUnit() throws -> AudioUnit {
        try NativeVoiceDirectVPIO.createUnit(kAudioUnitSubType_HALOutput)
    }

    func negotiate(
        referenceDevice: AudioDeviceID, voicePlan: NativeVoiceGraphPlan, voiceUnit: AudioUnit
    ) throws -> NativeVoiceGraphPlan {
        try operation {
            let output = try api.create()
            guard output != voiceUnit else { throw NativeVoiceDirectVPIOFailure(stage: "duplicate_unit") }
            unit = output
            self.voicePlan = voicePlan

            let directions = [(Property.inputIO, UInt32(0)), (.outputIO, UInt32(1))]
            for (address, required) in directions where try api.read(output, address, UInt32(0)) != required {
                try api.write(output, address, required)
            }
            try api.write(output, .outputDevice, referenceDevice)
            let deviceFormat = try api.read(output, .deviceRenderFormat, AudioStreamBasicDescription())
            guard deviceFormat.mSampleRate.isFinite, deviceFormat.mSampleRate > 0,
                  (1 ... 32).contains(deviceFormat.mChannelsPerFrame)
            else { throw NativeVoiceDirectVPIOFailure(stage: "device_format") }
            deviceChannels = deviceFormat.mChannelsPerFrame
            let format = NativeVoiceDirectVPIO.floatFormat(deviceFormat.mSampleRate, 1, false)
            try api.write(output, .renderFormat, format)
            if deviceChannels > 1 {
                // Keep the mono waveform at unity on the mapped device channels.
                let map = [Int32](repeating: 0, count: Int(deviceChannels))
                let property = Property.playbackChannelMap
                try map.withUnsafeBytes { bytes in
                    try NativeVoiceDirectVPIO.check(api.set(output, property.id, property.scope, property.bus,
                                                            bytes.baseAddress!, UInt32(bytes.count)), "channel_map")
                }
            }
            return try clientPlan(output, referenceDevice: referenceDevice, voicePlan: voicePlan)
        }
    }

    func install(_ reference: UnsafeMutableRawPointer) throws {
        try operation {
            guard let unit else { throw NativeVoiceSessionError.state }
            let callback = Property(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0)
            try api.write(unit, callback, AURenderCallbackStruct(
                inputProc: nvt_direct_vpio_render, inputProcRefCon: reference
            ))
            try NativeVoiceDirectVPIO.check(api.initialize(unit), "initialize")
            initialized = true
            var properties = [kAudioOutputUnitProperty_CurrentDevice, kAudioUnitProperty_StreamFormat,
                              kAudioOutputUnitProperty_EnableIO]
            if deviceChannels > 1 { properties.append(kAudioOutputUnitProperty_ChannelMap) }
            for id in properties {
                try NativeVoiceDirectVPIO.check(
                    api.listen(unit, id, nvt_direct_vpio_changed, reference), "listen.\(id)"
                )
                watched.append(id)
            }
        }
    }

    func start() throws {
        try operation {
            guard let unit, initialized, !startAttempted else { throw NativeVoiceSessionError.state }
            startAttempted = true
            try NativeVoiceDirectVPIO.check(api.start(unit), "start")
        }
    }

    func requireRunning() throws {
        try operation {
            guard let unit, try api.read(unit, Property(kAudioOutputUnitProperty_IsRunning), UInt32(0)) != 0
            else { throw NativeVoiceDirectVPIOFailure(stage: "unit_not_running") }
        }
    }

    func validatedPlan(referenceDevice: AudioDeviceID, voicePlan: NativeVoiceGraphPlan) throws -> NativeVoiceGraphPlan {
        try operation {
            guard let unit, voicePlan == self.voicePlan else {
                throw NativeVoiceDirectVPIOFailure(stage: "vpio_format_changed")
            }
            let maximum = try api.read(unit, Property(kAudioUnitProperty_MaximumFramesPerSlice), UInt32(0))
            guard maximum > 0, maximum <= callbackLimit
            else { throw NativeVoiceDirectVPIOFailure(stage: "callback_capacity") }
            return try clientPlan(unit, referenceDevice: referenceDevice, voicePlan: voicePlan)
        }
    }

    func release(callbacks: OpaquePointer?, cleanup: NativeVoiceDirectVPIOCleanup) -> Bool {
        guard let unit else { return true }
        self.unit = nil
        return !cleanup.release(
            unit, api: api, callbacks: callbacks, watched: watched,
            phase: (startAttempted, initialized), splitPlayback: true
        ).failed
    }

    func systemState(voiceRender: NativeVoiceIOFormat?) -> NativeVoiceSameFrameDiagnostics.SplitAUHAL? {
        unit.map { output in
            .init(device: try? api.read(output, .outputDevice, UInt32(0)),
                  clientFormat: try? NativeVoiceDirectVPIO.describe(
                      api.read(output, .renderFormat, AudioStreamBasicDescription())
                  ),
                  vpioSilentRenderFormat: voiceRender)
        }
    }

    private func clientPlan(
        _ output: AudioUnit, referenceDevice: AudioDeviceID, voicePlan: NativeVoiceGraphPlan
    ) throws -> NativeVoiceGraphPlan {
        guard referenceDevice != 0, try api.read(output, .outputDevice, UInt32(0)) == referenceDevice
        else { throw NativeVoiceDirectVPIOFailure(stage: "reference_device_mismatch") }
        guard try api.read(output, .inputIO, UInt32(0)) == 0, try api.read(output, .outputIO, UInt32(0)) == 1
        else { throw NativeVoiceDirectVPIOFailure(stage: "output_only_unverified") }
        let render = try NativeVoiceDirectVPIO.describe(api.read(output, .renderFormat, AudioStreamBasicDescription()))
        let device = try api.read(output, .deviceRenderFormat, AudioStreamBasicDescription())
        guard render.channels == 1, render.sampleRate == device.mSampleRate, device.mChannelsPerFrame == deviceChannels
        else { throw NativeVoiceDirectVPIOFailure(stage: "client_device_format_mismatch") }
        if deviceChannels > 1 {
            let property = Property.playbackChannelMap
            var map = [Int32](repeating: -1, count: Int(deviceChannels))
            try map.withUnsafeMutableBytes { bytes in
                var count = UInt32(bytes.count)
                try NativeVoiceDirectVPIO.check(api.get(output, property.id, property.scope, property.bus,
                                                        bytes.baseAddress!, &count), "channel_map_readback")
                guard count == bytes.count else { throw NativeVoiceDirectVPIOFailure(stage: "channel_map_size") }
            }
            guard map.allSatisfy({ $0 == 0 }) else { throw NativeVoiceDirectVPIOFailure(stage: "channel_map_mismatch") }
        }
        return .init(capture: voicePlan.capture, render: render)
    }

    private func operation<T>(_ call: () throws -> T) throws -> T {
        do {
            return try call()
        } catch let error as NativeVoiceDirectVPIOFailure {
            throw NativeVoiceDirectVPIOFailure(stage: "split_auhal.\(error.stage)", code: error.code)
        }
    }
}

extension NativeVoiceDirectVPIO.UnitAPI {
    nonisolated func read<T>(_ unit: AudioUnit, _ property: NativeVoiceDirectVPIO.Property, _ initial: T) throws -> T {
        var bytes = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            get(unit, property.id, property.scope, property.bus, buffer.baseAddress!, &bytes)
        }
        try NativeVoiceDirectVPIO.check(status, "read.\(property.address)")
        guard bytes == MemoryLayout<T>.size else {
            throw NativeVoiceDirectVPIOFailure(stage: "property_size.\(property.address)")
        }
        return value
    }

    nonisolated func write<T>(_ unit: AudioUnit, _ property: NativeVoiceDirectVPIO.Property, _ value: T) throws {
        let status = withUnsafeBytes(of: value) { buffer in
            set(unit, property.id, property.scope, property.bus, buffer.baseAddress!, UInt32(buffer.count))
        }
        try NativeVoiceDirectVPIO.check(status, "write.\(property.address)")
    }
}

extension NativeVoiceDirectVPIO {
    nonisolated static func floatFormat(
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

    nonisolated static func describe(_ format: AudioStreamBasicDescription) throws -> NativeVoiceIOFormat {
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

    nonisolated static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw NativeVoiceDirectVPIOFailure(stage: operation, code: status) }
    }

    nonisolated static func createUnit(_ subtype: OSType) throws -> AudioUnit {
        var type = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: subtype,
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
#endif
