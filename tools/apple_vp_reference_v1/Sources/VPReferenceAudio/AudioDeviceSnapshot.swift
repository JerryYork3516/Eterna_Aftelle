import AVFoundation
import CoreAudio
import CryptoKit
import Foundation

struct AudioDeviceSnapshot: Codable, Equatable {
    let anonymousID: String
    let transport: UInt32
    let nominalSampleRate: Double

    static func read(identifier: AudioObjectID) throws -> Self {
        guard identifier != kAudioObjectUnknown else { throw AudioReferenceError.unavailableDevice }
        let unmanagedUID: Unmanaged<CFString>? = try scalar(identifier, selector: kAudioDevicePropertyDeviceUID)
        guard let unmanagedUID else { throw AudioReferenceError.unavailableDevice }
        let deviceUID = unmanagedUID.takeRetainedValue()
        let digest = SHA256.hash(data: Data((deviceUID as String).utf8))
        let anonymousID = digest.map { String(format: "%02x", $0) }.joined()
        let transport: UInt32 = try scalar(identifier, selector: kAudioDevicePropertyTransportType)
        let sampleRate: Double = try scalar(identifier, selector: kAudioDevicePropertyNominalSampleRate)
        return Self(anonymousID: anonymousID, transport: transport, nominalSampleRate: sampleRate)
    }

    static func scalar<Value>(
        _ identifier: AudioObjectID, selector: AudioObjectPropertySelector
    ) throws -> Value {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Value>.size, alignment: MemoryLayout<Value>.alignment
        )
        defer { storage.deallocate() }
        var byteCount = UInt32(MemoryLayout<Value>.size)
        let status = AudioObjectGetPropertyData(identifier, &address, 0, nil, &byteCount, storage)
        guard status == noErr, byteCount == MemoryLayout<Value>.size else {
            throw AudioReferenceError.unavailableDevice
        }
        return storage.load(as: Value.self)
    }

    static func defaultDevice(selector: AudioObjectPropertySelector) throws -> AudioObjectID {
        try scalar(AudioObjectID(kAudioObjectSystemObject), selector: selector)
    }
}
