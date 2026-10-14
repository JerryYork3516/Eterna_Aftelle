import Foundation
import XCTest

@testable import VPReferenceAudio

final class AggregateBindingTests: XCTestCase {
    func testUniquePhysicalDirectionsAndOrderedStreamsQualify() {
        XCTAssertTrue(fixture().qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testDescriptorDifferenceIsPreservedWithIndependentPhysicalStreams() {
        let snapshot = fixture()
        XCTAssertEqual(snapshot.members[1].configuredInputChannels, 2)
        XCTAssertEqual(snapshot.members[1].inputChannels, 0)
        XCTAssertTrue(snapshot.qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testUnknownTapStateRejects() {
        XCTAssertFalse(fixture(taps: nil).qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testAdditionalProcessTapRejects() {
        XCTAssertFalse(fixture(taps: 1).qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testMissingActiveMemberRejects() {
        XCTAssertFalse(
            fixture(active: [input.anonymousID]).qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testExtraInactiveMemberRejects() {
        var snapshot = fixture()
        let members = snapshot.members + [snapshot.members[0]]
        snapshot = fixture(members: members)
        XCTAssertFalse(snapshot.qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testDuplicatePhysicalMembersRejects() {
        let first = fixture().members[0]
        XCTAssertFalse(
            fixture(members: [first, first]).qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testSecondPhysicalInputSourceRejects() {
        var members = fixture().members
        members[1] = AggregateDeviceSnapshot.Member(
            device: output, inputChannels: 2, outputChannels: 2,
            configuredInputChannels: 2, configuredOutputChannels: 2)
        XCTAssertFalse(fixture(members: members).qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testMissingAggregateStreamsRejects() {
        var snapshot = fixture()
        snapshot.inputStreams = nil
        XCTAssertFalse(snapshot.qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testWrongAggregateChannelRangeRejects() {
        var snapshot = fixture()
        snapshot.inputStreams = [stream(owner: node, direction: 1, channels: 1, start: 2)]
        XCTAssertFalse(snapshot.qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testWrongAggregateOwnerRejects() {
        var snapshot = fixture()
        snapshot.inputStreams = [stream(owner: input, direction: 1, channels: 1)]
        XCTAssertFalse(snapshot.qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    func testMissingPhysicalStreamsRejects() {
        var members = fixture().members
        members[0].inputStreams = nil
        XCTAssertFalse(fixture(members: members).qualifies(node: node, defaultInput: input, defaultOutput: output))
    }

    private var input: AudioDeviceSnapshot {
        AudioDeviceSnapshot(anonymousID: "synthetic-usb", transport: 1, nominalSampleRate: 16_000)
    }

    private var output: AudioDeviceSnapshot {
        AudioDeviceSnapshot(anonymousID: "synthetic-built-in", transport: 2, nominalSampleRate: 48_000)
    }

    private var node: AudioDeviceSnapshot {
        AudioDeviceSnapshot(anonymousID: "synthetic-aggregate", transport: 3, nominalSampleRate: 48_000)
    }

    private func stream(
        owner: AudioDeviceSnapshot, direction: UInt32, channels: UInt32, start: UInt32 = 1
    ) -> AggregateDeviceSnapshot.Stream {
        AggregateDeviceSnapshot.Stream(
            direction: direction, startingChannel: start, channelCount: channels,
            sampleRate: owner.nominalSampleRate, ownerID: owner.anonymousID)
    }

    private func fixture(
        taps: Int? = 0, active: [String]? = nil, members: [AggregateDeviceSnapshot.Member]? = nil
    ) -> AggregateDeviceSnapshot {
        var microphone = AggregateDeviceSnapshot.Member(
            device: input, inputChannels: 1, outputChannels: 0,
            configuredInputChannels: 1, configuredOutputChannels: 0)
        microphone.inputStreams = [stream(owner: input, direction: 1, channels: 1)]
        microphone.outputStreams = []
        var speaker = AggregateDeviceSnapshot.Member(
            device: output, inputChannels: 0, outputChannels: 2,
            configuredInputChannels: 2, configuredOutputChannels: 2)
        speaker.inputStreams = []
        speaker.outputStreams = [stream(owner: output, direction: 0, channels: 2)]
        var snapshot = AggregateDeviceSnapshot(
            status: "MEMBERSHIP_RECORDED_NOT_RUNTIME_PROOF", members: members ?? [microphone, speaker],
            activeMemberIDs: active ?? [input.anonymousID, output.anonymousID],
            inputChannels: 1, outputChannels: 2, isPrivate: true, isStacked: nil,
            tapCount: taps, activeTapCount: taps)
        snapshot.inputStreams = [stream(owner: node, direction: 1, channels: 1)]
        snapshot.outputStreams = [stream(owner: node, direction: 0, channels: 2)]
        return snapshot
    }
}
