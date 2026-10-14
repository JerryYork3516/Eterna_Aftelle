import CoreAudio
import Foundation

enum AudioHardwareRead {
    static let maximumObjects = 64
    static let maximumPropertyBytes = 64 * 1024

    static func bytes(
        _ identifier: AudioObjectID, selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> Data {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(identifier, &address, 0, nil, &size) == noErr,
            size <= maximumPropertyBytes
        else { throw AudioReferenceError.unavailableDevice }
        if size == 0 { return Data() }
        let capacity = Int(size)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(identifier, &address, 0, nil, &size, storage) == noErr,
            Int(size) <= capacity
        else { throw AudioReferenceError.unavailableDevice }
        return Data(bytes: storage, count: Int(size))
    }

    static func objects(
        _ identifier: AudioObjectID, selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [AudioObjectID] {
        let data = try bytes(identifier, selector: selector, scope: scope)
        let stride = MemoryLayout<AudioObjectID>.stride
        guard data.count % stride == 0, data.count / stride <= maximumObjects else {
            throw AudioReferenceError.unavailableDevice
        }
        return data.withUnsafeBytes { buffer in
            (0..<(data.count / stride)).map { buffer.loadUnaligned(fromByteOffset: $0 * stride, as: UInt32.self) }
        }
    }

    static func uid(_ identifier: AudioObjectID) throws -> String {
        let value: Unmanaged<CFString>? = try AudioDeviceSnapshot.scalar(
            identifier, selector: kAudioDevicePropertyDeviceUID)
        guard let value else { throw AudioReferenceError.unavailableDevice }
        let string = value.takeRetainedValue()
        guard CFGetTypeID(string) == CFStringGetTypeID(), CFStringGetLength(string) <= 4096 else {
            throw AudioReferenceError.unavailableDevice
        }
        return string as String
    }

    static func physicalDevice(uid: String) throws -> AudioObjectID {
        var qualifier = uid as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var identifier = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) {
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), $0, &size, &identifier)
        }
        guard status == noErr, size == MemoryLayout<AudioObjectID>.size,
            identifier != kAudioObjectUnknown
        else { throw AudioReferenceError.unavailableDevice }
        return identifier
    }

    static func channels(_ identifier: AudioObjectID, scope: AudioObjectPropertyScope) throws -> UInt32 {
        let data = try bytes(identifier, selector: kAudioDevicePropertyStreamConfiguration, scope: scope)
        if data.isEmpty { return 0 }
        return try data.withUnsafeBytes { buffer in
            guard data.count >= MemoryLayout<UInt32>.size else { throw AudioReferenceError.unavailableDevice }
            let count = Int(buffer.loadUnaligned(as: UInt32.self))
            let offset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers)!
            let stride = MemoryLayout<AudioBuffer>.stride
            guard count <= maximumObjects, data.count >= offset + count * stride else {
                throw AudioReferenceError.unavailableDevice
            }
            var total: UInt32 = 0
            for index in 0..<count {
                let item = buffer.loadUnaligned(fromByteOffset: offset + index * stride, as: AudioBuffer.self)
                guard item.mData == nil, item.mNumberChannels <= 64, total <= 64 - item.mNumberChannels else {
                    throw AudioReferenceError.unavailableDevice
                }
                total += item.mNumberChannels
            }
            return total
        }
    }

    static func strings(_ identifier: AudioObjectID, selector: AudioObjectPropertySelector) throws -> [String] {
        let value: Unmanaged<CFArray>? = try AudioDeviceSnapshot.scalar(identifier, selector: selector)
        guard let value else { throw AudioReferenceError.unavailableDevice }
        let array = value.takeRetainedValue()
        guard CFGetTypeID(array) == CFArrayGetTypeID(), CFArrayGetCount(array) <= maximumObjects,
            let strings = array as? [String], strings.allSatisfy({ $0.utf8.count <= 4096 })
        else { throw AudioReferenceError.unavailableDevice }
        return strings
    }
}
