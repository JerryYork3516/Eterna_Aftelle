@preconcurrency import AudioToolbox
@preconcurrency import CoreAudio
import Foundation

/// Checked HAL reads and registrations. Owned by the non-realtime graph control.
final nonisolated class NativeVoiceHALRoute {
    struct Registration {
        let hasProperty: (AudioObjectID, AudioObjectPropertyAddress) -> Bool
        let add: (AudioObjectID, AudioObjectPropertyAddress, DispatchQueue, @escaping AudioObjectPropertyListenerBlock)
            -> OSStatus
        let remove: (
            AudioObjectID,
            AudioObjectPropertyAddress,
            DispatchQueue,
            @escaping AudioObjectPropertyListenerBlock
        )
            -> Void

        static var system: Registration {
            Registration(
                hasProperty: { id, property in
                    var address = property
                    return AudioObjectHasProperty(id, &address)
                },
                add: { id, property, queue, listener in
                    var address = property
                    return AudioObjectAddPropertyListenerBlock(id, &address, queue, listener)
                },
                remove: { id, property, queue, listener in
                    var address = property
                    AudioObjectRemovePropertyListenerBlock(id, &address, queue, listener)
                }
            )
        }
    }

    private struct Watch {
        let id: AudioObjectID
        let address: AudioObjectPropertyAddress
        let listener: AudioObjectPropertyListenerBlock
    }

    private let registration: Registration
    private let queue = DispatchQueue(label: "com.eterna.aftelle.native-voice.devices")
    private var watches: [Watch] = []

    init(registration: Registration = .system) {
        self.registration = registration
    }

    static func defaultDevices() throws -> NativeVoiceGraphSnapshot.Defaults {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let input = try read(system, address(kAudioHardwarePropertyDefaultInputDevice), initial: AudioDeviceID(0))
        let output = try read(system, address(kAudioHardwarePropertyDefaultOutputDevice), initial: AudioDeviceID(0))
        for id in Set([input, output]) {
            guard id != kAudioObjectUnknown,
                  try read(id, address(kAudioDevicePropertyDeviceIsAlive), initial: UInt32(0)) != 0
            else { throw NativeVoiceSessionError.route }
        }
        return .init(input: input, output: output)
    }

    /// A Global CurrentDevice ID can identify the shared VPIO Aggregate.
    static func currentDevice(_ unit: AudioUnit?) throws -> AudioDeviceID {
        guard let unit else { throw NativeVoiceSessionError.route }
        var id = AudioDeviceID(kAudioObjectUnknown)
        var bytes = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            &bytes
        ) == noErr, bytes == MemoryLayout<AudioDeviceID>.size, id != kAudioObjectUnknown
        else { throw NativeVoiceSessionError.route }
        return id
    }

    static func bindings(roots: [AudioDeviceID]) throws -> [NativeVoiceDeviceBinding] {
        var pending = roots
        var result: [AudioDeviceID: NativeVoiceDeviceBinding] = [:]
        while let id = pending.popLast() {
            if result[id] != nil {
                continue
            }
            let device = try binding(id)
            result[id] = device
            pending.append(contentsOf: device.activeMembers)
        }
        return result.values.sorted { $0.id < $1.id }
    }

    static func streamBindings(_ bindings: [NativeVoiceDeviceBinding]) throws -> [NativeVoiceStreamBinding] {
        try Set(bindings.flatMap { $0.inputStreams + $0.outputStreams }).sorted().map { id in
            try NativeVoiceStreamBinding(
                id: id, virtualFormat: streamFormat(id, kAudioStreamPropertyVirtualFormat),
                physicalFormat: streamFormat(id, kAudioStreamPropertyPhysicalFormat)
            )
        }
    }

    func start(_ snapshot: NativeVoiceGraphSnapshot, changed: @escaping @Sendable () -> Void) throws {
        guard watches.isEmpty else { throw NativeVoiceSessionError.state }
        let roots = [
            snapshot.defaults.input,
            snapshot.defaults.output,
            snapshot.inputUnitDevice,
            snapshot.outputUnitDevice
        ]
        let members = snapshot.bindings.flatMap(\.activeMembers)
        let streams = snapshot.bindings.flatMap { $0.inputStreams + $0.outputStreams }
        guard Set(roots + members).isSubset(of: Set(snapshot.bindings.map(\.id))),
              Set(streams) == Set(snapshot.streams.map(\.id)) else { throw NativeVoiceSessionError.route }
        let listener: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        do {
            let system = AudioObjectID(kAudioObjectSystemObject)
            for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice,
                             kAudioHardwarePropertyDevices] {
                try watch(system, Self.address(selector), required: true, listener: listener)
            }
            for binding in snapshot.bindings {
                try watchDevice(binding, listener: listener)
            }
            for stream in snapshot.streams {
                try watch(
                    stream.id,
                    Self.address(kAudioStreamPropertyVirtualFormat),
                    required: true,
                    listener: listener
                )
                try watch(
                    stream.id,
                    Self.address(kAudioStreamPropertyPhysicalFormat),
                    required: true,
                    listener: listener
                )
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        for watch in watches.reversed() {
            registration.remove(watch.id, watch.address, queue, watch.listener)
        }
        watches.removeAll()
    }

    private func watchDevice(_ binding: NativeVoiceDeviceBinding, listener: @escaping AudioObjectPropertyListenerBlock)
        throws {
        try watch(binding.id, Self.address(kAudioDevicePropertyDeviceIsAlive), required: true, listener: listener)
        try watch(binding.id, Self.address(kAudioDevicePropertyNominalSampleRate), required: true, listener: listener)
        let directions = [(kAudioObjectPropertyScopeInput, binding.inputStreams, binding.inputChannels),
                          (kAudioObjectPropertyScopeOutput, binding.outputStreams, binding.outputChannels)]
        for (scope, streams, channels) in directions {
            let required = !streams.isEmpty || channels.contains { $0 > 0 }
            for selector in [kAudioDevicePropertyStreams, kAudioDevicePropertyStreamConfiguration] {
                try watch(binding.id, Self.address(selector, scope: scope), required: required, listener: listener)
            }
        }
        if binding.aggregateUIDs != nil {
            try watch(
                binding.id,
                Self.address(kAudioAggregateDevicePropertyActiveSubDeviceList),
                required: true,
                listener: listener
            )
            try watch(
                binding.id,
                Self.address(kAudioAggregateDevicePropertyFullSubDeviceList),
                required: true,
                listener: listener
            )
            try watch(
                binding.id,
                Self.address(kAudioAggregateDevicePropertyMainSubDevice),
                required: binding.clockMemberUID != nil,
                listener: listener
            )
        }
    }

    private func watch(
        _ id: AudioObjectID, _ address: AudioObjectPropertyAddress, required: Bool,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) throws {
        guard registration.hasProperty(id, address) else {
            if required {
                throw NativeVoiceSessionError.route
            }
            return
        }
        guard registration.add(id, address, queue, listener) == noErr else { throw NativeVoiceSessionError.route }
        watches.append(Watch(id: id, address: address, listener: listener))
    }
}

private extension NativeVoiceHALRoute {
    nonisolated static func binding(_ id: AudioDeviceID) throws -> NativeVoiceDeviceBinding {
        let alive = try read(id, address(kAudioDevicePropertyDeviceIsAlive), initial: UInt32(0))
        let transport = try read(id, address(kAudioDevicePropertyTransportType), initial: UInt32(0))
        let rate = try read(id, address(kAudioDevicePropertyNominalSampleRate), initial: Double(0))
        guard alive != 0, rate.isFinite, rate > 0 else { throw NativeVoiceSessionError.route }
        let aggregate = transport == kAudioDeviceTransportTypeAggregate
        let members = aggregate ? try ids(id, address(kAudioAggregateDevicePropertyActiveSubDeviceList)) : []
        let uids: [String]? = aggregate ? try object(id, address(kAudioAggregateDevicePropertyFullSubDeviceList)) : nil
        var main = address(kAudioAggregateDevicePropertyMainSubDevice)
        let clock: String? = aggregate && AudioObjectHasProperty(id, &main) ? try object(id, main) : nil
        guard !aggregate || (!members.isEmpty && uids?.isEmpty == false) else { throw NativeVoiceSessionError.route }
        return try NativeVoiceDeviceBinding(
            id: id, uid: object(id, address(kAudioDevicePropertyDeviceUID)), nominalRate: rate,
            inputStreams: ids(id, address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)),
            outputStreams: ids(id, address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)),
            inputChannels: channels(id, scope: kAudioObjectPropertyScopeInput),
            outputChannels: channels(id, scope: kAudioObjectPropertyScopeOutput),
            aggregateUIDs: uids, activeMembers: members, clockMemberUID: clock
        )
    }

    nonisolated static func streamFormat(
        _ id: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) throws -> NativeVoiceStreamBinding.Format {
        let format = try read(id, address(selector), initial: AudioStreamBasicDescription())
        return .init(sampleRateBits: format.mSampleRate.bitPattern, encoding: [
            format.mFormatID, format.mFormatFlags, format.mBytesPerPacket, format.mFramesPerPacket,
            format.mBytesPerFrame, format.mChannelsPerFrame, format.mBitsPerChannel
        ])
    }

    nonisolated static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated static func read<T>(
        _ id: AudioObjectID,
        _ property: AudioObjectPropertyAddress,
        initial: T
    ) throws -> T {
        var address = property
        var value = initial
        let size = MemoryLayout<T>.size
        var bytes = UInt32(size)
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &bytes, $0.baseAddress!)
        }
        guard status == noErr, bytes == size else { throw NativeVoiceSessionError.route }
        return value
    }

    nonisolated static func object<T>(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress) throws -> T {
        let value = try read(id, property, initial: Unmanaged<CFTypeRef>?.none)
        guard let result = value?.takeRetainedValue() as? T else { throw NativeVoiceSessionError.route }
        return result
    }

    nonisolated static func ids(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress) throws -> [AudioObjectID] {
        var address = property
        if !AudioObjectHasProperty(id, &address) {
            return []
        }
        var size: UInt32 = 0
        let width = MemoryLayout<AudioObjectID>.stride
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size <= 65536, Int(size).isMultiple(of: width) else { throw NativeVoiceSessionError.route }
        if size == 0 {
            return []
        }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / width)
        let capacity = size
        let status = values.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr, size <= capacity, Int(size).isMultiple(of: width)
        else { throw NativeVoiceSessionError.route }
        return Array(values.prefix(Int(size) / width))
    }

    nonisolated static func channels(_ id: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [UInt32] {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        if !AudioObjectHasProperty(id, &property) {
            return []
        }
        let offset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr,
              size >= offset, size <= 65536 else { throw NativeVoiceSessionError.route }
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { memory.deallocate() }
        let capacity = size
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, memory) == noErr,
              size >= offset, size <= capacity else { throw NativeVoiceSessionError.route }
        let count = memory.load(as: UInt32.self)
        let width = MemoryLayout<AudioBuffer>.stride
        guard Int(count) <= (Int(size) - offset) / width else { throw NativeVoiceSessionError.route }
        return (0 ..< Int(count)).map {
            memory.load(fromByteOffset: offset + $0 * width, as: AudioBuffer.self).mNumberChannels
        }
    }
}
