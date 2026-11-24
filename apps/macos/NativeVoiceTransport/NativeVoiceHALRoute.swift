@preconcurrency import AudioToolbox
@preconcurrency import CoreAudio
import Foundation

/// Read and watch the devices bound to the active Engine, including live Aggregate membership.
final nonisolated class NativeVoiceHALRoute {
    private struct Watch {
        let id: AudioObjectID
        var address: AudioObjectPropertyAddress
        let listener: AudioObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(label: "com.eterna.aftelle.native-voice.devices")
    private var watches: [Watch] = []

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
        ) == noErr, id != kAudioObjectUnknown
        else { throw NativeVoiceSessionError.route }
        return id
    }

    static func bindings(input: AudioDeviceID, output: AudioDeviceID) throws -> [NativeVoiceDeviceBinding] {
        var pending = [input, output]
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

    func start(_ bindings: [NativeVoiceDeviceBinding], changed: @escaping @Sendable () -> Void) throws {
        for binding in bindings {
            for address in Self.observedProperties(aggregate: binding.aggregateUIDs != nil) {
                var address = address
                guard AudioObjectHasProperty(binding.id, &address) else { continue }
                let listener: AudioObjectPropertyListenerBlock = { _, _ in changed() }
                let status = AudioObjectAddPropertyListenerBlock(binding.id, &address, queue, listener)
                guard status == noErr else { throw NativeVoiceSessionError.route }
                watches.append(Watch(id: binding.id, address: address, listener: listener))
            }
        }
    }

    func stop() {
        for var watch in watches {
            AudioObjectRemovePropertyListenerBlock(watch.id, &watch.address, queue, watch.listener)
        }
        watches.removeAll()
    }

    private static func binding(_ id: AudioDeviceID) throws -> NativeVoiceDeviceBinding {
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

    private static func observedProperties(aggregate: Bool) -> [AudioObjectPropertyAddress] {
        var properties = [
            address(kAudioDevicePropertyDeviceIsAlive), address(kAudioDevicePropertyNominalSampleRate),
            address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput),
            address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput),
            address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput),
            address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        ]
        if aggregate {
            properties += [
                address(kAudioAggregateDevicePropertyActiveSubDeviceList),
                address(kAudioAggregateDevicePropertyFullSubDeviceList),
                address(kAudioAggregateDevicePropertyMainSubDevice)
            ]
        }
        return properties
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress, initial: T) throws -> T {
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

    private static func object<T>(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress) throws -> T {
        let value = try read(id, property, initial: Unmanaged<CFTypeRef>?.none)
        guard let result = value?.takeRetainedValue() as? T else { throw NativeVoiceSessionError.route }
        return result
    }

    private static func ids(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress) throws -> [AudioObjectID] {
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

    private static func channels(_ id: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [UInt32] {
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
