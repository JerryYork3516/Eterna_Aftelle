import Foundation
import XCTest

@testable import VPReferenceAudio

final class AggregateEvidenceTests: XCTestCase {
    func testUnknownPropertiesRemainUnknownInEvidence() throws {
        let snapshot = AggregateDeviceSnapshot(
            status: "HAL_AGGREGATE_PROPERTIES_UNAVAILABLE", members: [], activeMemberIDs: [],
            inputChannels: nil, outputChannels: nil, isPrivate: nil, isStacked: nil,
            tapCount: nil, activeTapCount: nil)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AggregateDeviceSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertNil(decoded.tapCount)
        XCTAssertNil(decoded.inputChannels)
    }

    func testMembershipKeepsPhysicalAndConfiguredChannelsSeparate() throws {
        let member = AggregateDeviceSnapshot.Member(
            device: AudioDeviceSnapshot(anonymousID: "synthetic-anonymous", transport: 0, nominalSampleRate: 48_000),
            inputChannels: 1, outputChannels: 0, configuredInputChannels: nil, configuredOutputChannels: nil)
        let data = try JSONEncoder().encode(member)
        let decoded = try JSONDecoder().decode(AggregateDeviceSnapshot.Member.self, from: data)
        XCTAssertEqual(decoded.inputChannels, 1)
        XCTAssertNil(decoded.configuredInputChannels)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("deviceUID"))
        XCTAssertFalse(text.contains("/Users/"))
    }
}
