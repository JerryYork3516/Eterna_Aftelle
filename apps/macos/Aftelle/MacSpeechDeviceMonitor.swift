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

nonisolated protocol MacSpeechVoiceActivityDetecting: AnyObject, Sendable {
    func start() -> Bool
    func stop()
    func isVoiceDetected() -> Bool
}

nonisolated final class SystemMacSpeechVoiceActivityDetector:
    MacSpeechVoiceActivityDetecting, @unchecked Sendable
{
    private let lock = NSLock()
    private let callbackQueue = DispatchQueue(
        label: "com.eterna.aftelle.voice-activity"
    )
    private var deviceID = AudioDeviceID(kAudioObjectUnknown)
    private var originalEnableValue: UInt32?
    private var listener: AudioObjectPropertyListenerBlock?
    private var isRunning = false
    private var lifecycle: UInt64 = 0
    private var voiceDetected = false

    func start() -> Bool {
        lock.withLock {
            guard !isRunning else { return true }
            guard let inputDevice = Self.defaultInputDevice(),
                  Self.hasProperty(
                    kAudioDevicePropertyVoiceActivityDetectionEnable,
                    deviceID: inputDevice
                  ),
                  Self.hasProperty(
                    kAudioDevicePropertyVoiceActivityDetectionState,
                    deviceID: inputDevice
                  ),
                  let previousEnable = Self.uint32Property(
                    kAudioDevicePropertyVoiceActivityDetectionEnable,
                    deviceID: inputDevice
                  ) else {
                return false
            }
            if previousEnable == 0,
               !Self.setUInt32Property(
                1,
                selector:
                    kAudioDevicePropertyVoiceActivityDetectionEnable,
                deviceID: inputDevice
               ) {
                return false
            }
            var address = Self.propertyAddress(
                kAudioDevicePropertyVoiceActivityDetectionState
            )
            let listener: AudioObjectPropertyListenerBlock = {
                [weak self] _, _ in
                self?.refreshState()
            }
            let status = AudioObjectAddPropertyListenerBlock(
                inputDevice,
                &address,
                callbackQueue,
                listener
            )
            guard status == noErr else {
                if previousEnable == 0 {
                    _ = Self.setUInt32Property(
                        0,
                        selector:
                            kAudioDevicePropertyVoiceActivityDetectionEnable,
                        deviceID: inputDevice
                    )
                }
                return false
            }
            deviceID = inputDevice
            originalEnableValue = previousEnable
            self.listener = listener
            voiceDetected = Self.uint32Property(
                kAudioDevicePropertyVoiceActivityDetectionState,
                deviceID: inputDevice
            ) == 1
            isRunning = true
            return true
        }
    }

    func stop() {
        let state = lock.withLock { () -> (
            AudioDeviceID,
            UInt32?,
            AudioObjectPropertyListenerBlock?
        ) in
            let state = (deviceID, originalEnableValue, listener)
            deviceID = AudioDeviceID(kAudioObjectUnknown)
            originalEnableValue = nil
            listener = nil
            isRunning = false
            lifecycle &+= 1
            voiceDetected = false
            return state
        }
        guard state.0 != kAudioObjectUnknown else { return }
        if let listener = state.2 {
            var address = Self.propertyAddress(
                kAudioDevicePropertyVoiceActivityDetectionState
            )
            AudioObjectRemovePropertyListenerBlock(
                state.0,
                &address,
                callbackQueue,
                listener
            )
        }
        if state.1 == 0 {
            _ = Self.setUInt32Property(
                0,
                selector: kAudioDevicePropertyVoiceActivityDetectionEnable,
                deviceID: state.0
            )
        }
    }

    func isVoiceDetected() -> Bool {
        lock.withLock { isRunning && voiceDetected }
    }

    private func refreshState() {
        let (inputDevice, currentLifecycle) = lock.withLock {
            (isRunning ? deviceID : AudioDeviceID(kAudioObjectUnknown), lifecycle)
        }
        guard inputDevice != kAudioObjectUnknown else { return }
        let state = Self.uint32Property(
            kAudioDevicePropertyVoiceActivityDetectionState,
            deviceID: inputDevice
        )
        lock.withLock {
            guard isRunning, deviceID == inputDevice,
                  lifecycle == currentLifecycle else { return }
            voiceDetected = state == 1
        }
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &value
        )
        return status == noErr && value != kAudioObjectUnknown
            ? value : nil
    }

    private static func propertyAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func hasProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> Bool {
        var address = propertyAddress(selector)
        return AudioObjectHasProperty(deviceID, &address)
    }

    private static func uint32Property(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> UInt32? {
        var address = propertyAddress(selector)
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
        return status == noErr ? value : nil
    }

    private static func setUInt32Property(
        _ value: UInt32,
        selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> Bool {
        var address = propertyAddress(selector)
        var value = value
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &value
        ) == noErr
    }
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
