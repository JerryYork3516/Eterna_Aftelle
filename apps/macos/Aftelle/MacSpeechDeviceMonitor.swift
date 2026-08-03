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
