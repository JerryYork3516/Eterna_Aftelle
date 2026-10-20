@preconcurrency import CoreAudio
import Foundation

nonisolated struct MacSpeechAudioDevice: Sendable, Equatable {
    let identifier: String
    let name: String
    let isAvailable: Bool

    static let unavailable = MacSpeechAudioDevice(
        identifier: "unavailable",
        name: "—",
        isAvailable: false
    )
}

nonisolated struct MacSpeechDeviceRoute: Sendable, Equatable {
    let input: MacSpeechAudioDevice
    let output: MacSpeechAudioDevice

    static let unavailable = MacSpeechDeviceRoute(
        input: .unavailable,
        output: .unavailable
    )
}

nonisolated protocol MacSpeechDeviceRouteMonitoring: AnyObject, Sendable {
    func currentRoute() -> MacSpeechDeviceRoute
    func start(onChange: @escaping @Sendable () -> Void)
    func stop()
}

nonisolated final class SystemMacSpeechDeviceMonitor:
    MacSpeechDeviceRouteMonitoring, @unchecked Sendable
{
    private let lock = NSLock()
    private let callbackQueue = DispatchQueue(
        label: "com.eterna.aftelle.audio-device-route"
    )
    private var listeners: [
        AudioObjectPropertySelector: AudioObjectPropertyListenerBlock
    ] = [:]
    private var isMonitoring = false

    func currentRoute() -> MacSpeechDeviceRoute {
        MacSpeechDeviceRoute(
            input: device(
                for: kAudioHardwarePropertyDefaultInputDevice
            ),
            output: device(
                for: kAudioHardwarePropertyDefaultOutputDevice
            )
        )
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        lock.withLock {
            guard !isMonitoring else { return }
            let selectors = [
                kAudioHardwarePropertyDevices,
                kAudioHardwarePropertyDefaultInputDevice,
                kAudioHardwarePropertyDefaultOutputDevice
            ]
            for selector in selectors {
                var address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                let listener: AudioObjectPropertyListenerBlock = { _, _ in
                    onChange()
                }
                let status = AudioObjectAddPropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    callbackQueue,
                    listener
                )
                guard status == noErr else {
                    removeListeners()
                    return
                }
                listeners[selector] = listener
            }
            isMonitoring = true
        }
    }

    func stop() {
        lock.withLock {
            guard isMonitoring else { return }
            removeListeners()
            isMonitoring = false
        }
    }

    private func device(
        for selector: AudioObjectPropertySelector
    ) -> MacSpeechAudioDevice {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return .unavailable
        }
        return MacSpeechAudioDevice(
            identifier: stringProperty(
                kAudioDevicePropertyDeviceUID,
                deviceID: deviceID
            ) ?? "audio-device-\(deviceID)",
            name: stringProperty(
                kAudioObjectPropertyName,
                deviceID: deviceID
            ) ?? "Audio Device \(deviceID)",
            isAvailable: isAlive(deviceID)
        )
    }

    private func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    private func isAlive(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        return status == noErr && value != 0
    }

    private func removeListeners() {
        for (selector, listener) in listeners {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                callbackQueue,
                listener
            )
        }
        listeners.removeAll()
    }
}

#if DEBUG
    nonisolated enum MacSpeechRuntimeDeviceReadback {
        private enum ReadFailure: Error { case property(UInt32, OSStatus), invalidProperty(UInt32) }
        private static let maximumObjects = 16
        private static let maximumBytes: UInt32 = 4096

        static func read(input: UInt32, output: UInt32) throws -> MacSpeechRuntimeReadback.Route {
            let system = AudioObjectID(kAudioObjectSystemObject)
            let inputID: UInt32 = try scalar(system, kAudioHardwarePropertyDefaultInputDevice, initial: 0)
            let outputID: UInt32 = try scalar(system, kAudioHardwarePropertyDefaultOutputDevice, initial: 0)
            let expectedInput = try device(inputID)
            let expectedOutput = try device(outputID)
            let actualInput = try device(input)
            let actualOutput = try device(output)
            let nodes = actualInput.id == actualOutput.id ? [actualInput] : [actualInput, actualOutput]
            let aggregates = try nodes.filter(\.aggregate).map { try aggregate($0) }
            let inputAfter: UInt32 = try scalar(system, kAudioHardwarePropertyDefaultInputDevice, initial: 0)
            let outputAfter: UInt32 = try scalar(system, kAudioHardwarePropertyDefaultOutputDevice, initial: 0)
            guard inputID == inputAfter, outputID == outputAfter else {
                throw ReadFailure.invalidProperty(kAudioHardwarePropertyDefaultOutputDevice)
            }
            return MacSpeechRuntimeReadback.Route(defaultInput: expectedInput, defaultOutput: expectedOutput,
                                                  actualInput: actualInput, actualOutput: actualOutput,
                                                  aggregates: aggregates)
        }

        private static func device(_ id: UInt32) throws -> MacSpeechRuntimeReadback.Device {
            guard id != kAudioObjectUnknown else { throw ReadFailure.invalidProperty(0) }
            let transport: UInt32 = try scalar(id, kAudioDevicePropertyTransportType, initial: 0)
            let alive: UInt32 = try scalar(id, kAudioDevicePropertyDeviceIsAlive, initial: 0)
            return try MacSpeechRuntimeReadback.Device(
                id: id, transport: transport, aggregate: transport == kAudioDeviceTransportTypeAggregate,
                alive: alive != 0, inputChannels: channels(id, scope: kAudioObjectPropertyScopeInput),
                outputChannels: channels(id, scope: kAudioObjectPropertyScopeOutput),
                inputStreams: streams(id, scope: kAudioObjectPropertyScopeInput),
                outputStreams: streams(id, scope: kAudioObjectPropertyScopeOutput)
            )
        }

        private static func aggregate(
            _ node: MacSpeechRuntimeReadback.Device
        ) throws -> MacSpeechRuntimeReadback.Aggregate {
            let full = try strings(node.id, kAudioAggregateDevicePropertyFullSubDeviceList)
            let members = try full.map { try device(translate($0)) }
            let active = try objects(node.id, kAudioAggregateDevicePropertyActiveSubDeviceList)
            // Missing tap properties cannot qualify an aggregate as a physical I/O pair.
            let taps = try? strings(node.id, kAudioAggregateDevicePropertyTapList).count
            let activeTaps = try? objects(node.id, kAudioAggregateDevicePropertySubTapList).count
            return MacSpeechRuntimeReadback.Aggregate(device: node, members: members, activeMembers: active,
                                                      tapCount: taps, activeTapCount: activeTaps)
        }

        private static func streams(
            _ id: UInt32, scope: AudioObjectPropertyScope
        ) throws -> [MacSpeechRuntimeReadback.Stream] {
            try objects(id, kAudioDevicePropertyStreams, scope: scope).map { stream in
                let owner: UInt32 = try scalar(stream, kAudioObjectPropertyOwner, initial: 0)
                let direction: UInt32 = try scalar(stream, kAudioStreamPropertyDirection, initial: 0)
                let start: UInt32 = try scalar(stream, kAudioStreamPropertyStartingChannel, initial: 0)
                let format = try scalar(stream, kAudioStreamPropertyVirtualFormat,
                                        initial: AudioStreamBasicDescription())
                guard format.mSampleRate.isFinite, format.mSampleRate > 0 else {
                    throw ReadFailure.invalidProperty(kAudioStreamPropertyVirtualFormat)
                }
                return MacSpeechRuntimeReadback.Stream(owner: owner, direction: direction, start: start,
                                                       channels: format.mChannelsPerFrame, rate: format.mSampleRate)
            }
        }

        private static func scalar<T>(
            _ id: UInt32, _ selector: AudioObjectPropertySelector, initial: T
        ) throws -> T {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var value = initial
            var size = UInt32(MemoryLayout<T>.size)
            let result = withUnsafeMutablePointer(to: &value) {
                AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
            }
            guard result == noErr, size == MemoryLayout<T>.size else {
                throw ReadFailure.property(selector, result)
            }
            return value
        }

        private static func bytes(
            _ id: UInt32, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope
        ) throws -> Data {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                     mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            let result = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
            guard result == noErr, size <= maximumBytes else { throw ReadFailure.property(selector, result) }
            if size == 0 {
                return Data()
            }
            var data = Data(count: Int(size))
            let capacity = size
            let status = data.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0.baseAddress!)
            }
            guard status == noErr, size <= capacity else { throw ReadFailure.property(selector, status) }
            return data.prefix(Int(size))
        }

        private static func objects(
            _ id: UInt32, _ selector: AudioObjectPropertySelector,
            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
        ) throws -> [UInt32] {
            let data = try bytes(id, selector, scope: scope)
            guard data.count % 4 == 0, data.count / 4 <= maximumObjects else {
                throw ReadFailure.invalidProperty(selector)
            }
            return data.withUnsafeBytes { buffer in
                (0 ..< data.count / 4).map { buffer.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) }
            }
        }

        private static func strings(_ id: UInt32, _ selector: AudioObjectPropertySelector) throws -> [String] {
            let value: Unmanaged<CFArray>? = try scalar(id, selector, initial: nil)
            guard let value else { throw ReadFailure.invalidProperty(selector) }
            let array = value.takeRetainedValue()
            guard CFGetTypeID(array) == CFArrayGetTypeID(), CFArrayGetCount(array) <= maximumObjects,
                  let strings = array as? [String], strings.allSatisfy({ $0.utf8.count <= 4096 })
            else {
                throw ReadFailure.invalidProperty(selector)
            }
            return strings
        }

        private static func translate(_ uid: String) throws -> UInt32 {
            var qualifier = uid as CFString
            let selector = kAudioHardwarePropertyTranslateUIDToDevice
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var id = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            let result = withUnsafePointer(to: &qualifier) {
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                           UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
            }
            guard result == noErr, size == MemoryLayout<AudioObjectID>.size, id != kAudioObjectUnknown else {
                throw ReadFailure.property(selector, result)
            }
            return id
        }

        private static func channels(_ id: UInt32, scope: AudioObjectPropertyScope) throws -> UInt32 {
            let selector = kAudioDevicePropertyStreamConfiguration
            let data = try bytes(id, selector, scope: scope)
            if data.isEmpty {
                return 0
            }
            return try data.withUnsafeBytes { buffer in
                guard data.count >= MemoryLayout<UInt32>.size,
                      let offset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers)
                else {
                    throw ReadFailure.invalidProperty(selector)
                }
                let count = Int(buffer.loadUnaligned(as: UInt32.self))
                let stride = MemoryLayout<AudioBuffer>.stride
                guard count <= maximumObjects, data.count >= offset + count * stride else {
                    throw ReadFailure.invalidProperty(selector)
                }
                var sum: UInt32 = 0
                for index in 0 ..< count {
                    let value = buffer.loadUnaligned(fromByteOffset: offset + index * stride, as: AudioBuffer.self)
                    guard value.mData == nil, value.mNumberChannels <= 64, sum <= 64 - value.mNumberChannels else {
                        throw ReadFailure.invalidProperty(selector)
                    }
                    sum += value.mNumberChannels
                }
                return sum
            }
        }
    }
#endif
