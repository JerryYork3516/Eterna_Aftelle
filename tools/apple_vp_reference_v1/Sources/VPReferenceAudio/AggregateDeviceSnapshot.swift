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
        var inputStreams: [Stream]?
        var outputStreams: [Stream]?
    }

    struct Stream: Codable, Equatable {
        let direction: UInt32
        let startingChannel: UInt32
        let channelCount: UInt32
        let sampleRate: Double
        let ownerID: String
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
    var inputStreams: [Stream]?
    var outputStreams: [Stream]?

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
            var member = Member(
                device: try AudioDeviceSnapshot.read(identifier: physical),
                inputChannels: try AudioHardwareRead.channels(physical, scope: kAudioObjectPropertyScopeInput),
                outputChannels: try AudioHardwareRead.channels(physical, scope: kAudioObjectPropertyScopeOutput),
                configuredInputChannels: (configured?["channels-in"] as? NSNumber)?.intValue,
                configuredOutputChannels: (configured?["channels-out"] as? NSNumber)?.intValue)
            member.inputStreams = try streams(physical, scope: kAudioObjectPropertyScopeInput)
            member.outputStreams = try streams(physical, scope: kAudioObjectPropertyScopeOutput)
            return member
        }
        let activeIDs = try active.map { digest(try AudioHardwareRead.uid($0)) }.sorted()
        let taps = try? AudioHardwareRead.strings(identifier, selector: kAudioAggregateDevicePropertyTapList)
        let activeTaps = try? AudioHardwareRead.objects(identifier, selector: kAudioAggregateDevicePropertySubTapList)
        var snapshot = Self(
            status: "MEMBERSHIP_RECORDED_NOT_RUNTIME_PROOF", members: members, activeMemberIDs: activeIDs,
            inputChannels: try AudioHardwareRead.channels(identifier, scope: kAudioObjectPropertyScopeInput),
            outputChannels: try AudioHardwareRead.channels(identifier, scope: kAudioObjectPropertyScopeOutput),
            isPrivate: (composition["private"] as? NSNumber)?.boolValue,
            isStacked: (composition["stacked"] as? NSNumber)?.boolValue,
            tapCount: taps?.count, activeTapCount: activeTaps?.count)
        snapshot.inputStreams = try streams(identifier, scope: kAudioObjectPropertyScopeInput)
        snapshot.outputStreams = try streams(identifier, scope: kAudioObjectPropertyScopeOutput)
        return snapshot
    }

    private static func streams(_ identifier: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [Stream] {
        try AudioHardwareRead.objects(identifier, selector: kAudioDevicePropertyStreams, scope: scope).map { stream in
            let owner: AudioObjectID = try AudioDeviceSnapshot.scalar(stream, selector: kAudioObjectPropertyOwner)
            let direction: UInt32 = try AudioDeviceSnapshot.scalar(stream, selector: kAudioStreamPropertyDirection)
            let startingChannel: UInt32 = try AudioDeviceSnapshot.scalar(
                stream, selector: kAudioStreamPropertyStartingChannel)
            let format: AudioStreamBasicDescription = try AudioDeviceSnapshot.scalar(
                stream, selector: kAudioStreamPropertyVirtualFormat)
            return Stream(
                direction: direction, startingChannel: startingChannel,
                channelCount: format.mChannelsPerFrame, sampleRate: format.mSampleRate,
                ownerID: try AudioDeviceSnapshot.read(identifier: owner).anonymousID)
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func qualifies(
        node: AudioDeviceSnapshot, defaultInput: AudioDeviceSnapshot, defaultOutput: AudioDeviceSnapshot
    ) -> Bool {
        guard status == "MEMBERSHIP_RECORDED_NOT_RUNTIME_PROOF", tapCount == 0, activeTapCount == 0,
            members.count == 2, Set(activeMemberIDs) == Set([defaultInput.anonymousID, defaultOutput.anonymousID]),
            activeMemberIDs.count == 2,
            let input = members.first(where: { $0.device == defaultInput }),
            let output = members.first(where: { $0.device == defaultOutput }),
            input.inputChannels > 0, input.outputChannels == 0,
            output.inputChannels == 0, output.outputChannels > 0,
            inputChannels == input.inputChannels, outputChannels == output.outputChannels
        else { return false }
        return directionMatches(input: true, node: node) && directionMatches(input: false, node: node)
    }

    private func directionMatches(input: Bool, node: AudioDeviceSnapshot) -> Bool {
        let direction: UInt32 = input ? 1 : 0
        var expected: [UInt32] = []
        for member in members {
            guard let physical = input ? member.inputStreams : member.outputStreams,
                Self.validStreams(physical, direction: direction, ownerID: member.device.anonymousID),
                physical.reduce(0, { $0 + $1.channelCount }) == (input ? member.inputChannels : member.outputChannels)
            else { return false }
            expected.append(contentsOf: physical.map(\.channelCount))
        }
        guard let aggregate = input ? inputStreams : outputStreams,
            Self.validStreams(aggregate, direction: direction, ownerID: node.anonymousID)
        else { return false }
        return aggregate.map(\.channelCount) == expected
    }

    private static func validStreams(_ streams: [Stream], direction: UInt32, ownerID: String) -> Bool {
        guard streams.count <= AudioHardwareRead.maximumObjects else { return false }
        var nextChannel: UInt32 = 1
        for stream in streams {
            guard stream.direction == direction, stream.ownerID == ownerID,
                stream.startingChannel == nextChannel, stream.channelCount > 0,
                stream.channelCount <= 64, nextChannel <= 65 - stream.channelCount,
                stream.sampleRate.isFinite, stream.sampleRate > 0
            else { return false }
            nextChannel += stream.channelCount
        }
        return true
    }
}
