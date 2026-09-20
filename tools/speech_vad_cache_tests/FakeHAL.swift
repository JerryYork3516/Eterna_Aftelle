import Foundation
import CoreAudio

nonisolated enum FakeHAL {
    nonisolated(unsafe) static var device: AudioDeviceID? = 42
    nonisolated(unsafe) static var supported = true
    nonisolated(unsafe) static var state: UInt32? = 0
    nonisolated(unsafe) static var onStateRead: (() -> Void)?
    static func readState() -> UInt32? {
        let result = state
        if let action = onStateRead { onStateRead = nil; action() }
        return result
    }
    nonisolated(unsafe) static var enabled: UInt32? = 0
    nonisolated(unsafe) static var setSuccess = true
    nonisolated(unsafe) static var listenerStatus: OSStatus = noErr
}

nonisolated func auditAddListener(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ queue: DispatchQueue?, _ block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
    return FakeHAL.listenerStatus
}
@discardableResult nonisolated func auditRemoveListener(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ queue: DispatchQueue?, _ block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
    return noErr
}
