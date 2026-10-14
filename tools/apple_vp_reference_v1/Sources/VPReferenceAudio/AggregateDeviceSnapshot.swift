import CoreAudio
import CryptoKit
import Foundation

struct AggregateDeviceSnapshot: Codable, Equatable {
    struct Member: Codable, Equatable {
        let device: AudioDeviceSnapshot
        let inputChannels: UInt32
        let outputChannels: UInt32
        let configuredInputChannels: Int?
        let configuredOutputChannels: Int?
    }

    let status: String
    let members: [Member]
    let activeMemberIDs: [String]
    let inputChannels: UInt32?
    let outputChannels: UInt32?
    let isPrivate: Bool?
    let isStacked: Bool?
    let tapCount: Int?
    let activeTapCount: Int?

    static func capture(_ identifier: AudioObjectID) -> Self {
        do { return try read(identifier) } catch {
            return Self(
                status: "HAL_AGGREGATE_PROPERTIES_UNAVAILABLE", members: [], activeMemberIDs: [],
                inputChannels: nil, outputChannels: nil, isPrivate: nil, isStacked: nil,
                tapCount: nil, activeTapCount: nil)
        }
    }

    private static func read(_ identifier: AudioObjectID) throws -> Self {
        let full = try AudioHardwareRead.strings(identifier, selector: kAudioAggregateDevicePropertyFullSubDeviceList)
        let active = try AudioHardwareRead.objects(
            identifier, selector: kAudioAggregateDevicePropertyActiveSubDeviceList)
        let value: Unmanaged<CFDictionary>? = try AudioDeviceSnapshot.scalar(
            identifier, selector: kAudioAggregateDevicePropertyComposition)
        guard let value else { throw AudioReferenceError.unavailableDevice }
        let dictionary = value.takeRetainedValue()
        guard CFGetTypeID(dictionary) == CFDictionaryGetTypeID(),
            let composition = dictionary as? [String: Any],
            let subdevices = composition["subdevices"] as? [[String: Any]],
            subdevices.count <= AudioHardwareRead.maximumObjects
        else { throw AudioReferenceError.unavailableDevice }
        let members = try full.map { uid in
            let physical = try AudioHardwareRead.physicalDevice(uid: uid)
            let configured = subdevices.first { $0["uid"] as? String == uid }
            return Member(
                device: try AudioDeviceSnapshot.read(identifier: physical),
                inputChannels: try AudioHardwareRead.channels(physical, scope: kAudioObjectPropertyScopeInput),
                outputChannels: try AudioHardwareRead.channels(physical, scope: kAudioObjectPropertyScopeOutput),
                configuredInputChannels: (configured?["channels-in"] as? NSNumber)?.intValue,
                configuredOutputChannels: (configured?["channels-out"] as? NSNumber)?.intValue)
        }
        let activeIDs = try active.map { digest(try AudioHardwareRead.uid($0)) }.sorted()
        let taps = try? AudioHardwareRead.strings(identifier, selector: kAudioAggregateDevicePropertyTapList)
        let activeTaps = try? AudioHardwareRead.objects(identifier, selector: kAudioAggregateDevicePropertySubTapList)
        return Self(
            status: "MEMBERSHIP_RECORDED_NOT_RUNTIME_PROOF", members: members, activeMemberIDs: activeIDs,
            inputChannels: try AudioHardwareRead.channels(identifier, scope: kAudioObjectPropertyScopeInput),
            outputChannels: try AudioHardwareRead.channels(identifier, scope: kAudioObjectPropertyScopeOutput),
            isPrivate: (composition["private"] as? NSNumber)?.boolValue,
            isStacked: (composition["stacked"] as? NSNumber)?.boolValue,
            tapCount: taps?.count, activeTapCount: activeTaps?.count)
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
