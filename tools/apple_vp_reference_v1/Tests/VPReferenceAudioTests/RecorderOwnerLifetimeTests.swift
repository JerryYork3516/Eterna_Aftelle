import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class RecorderOwnerLifetimeTests: XCTestCase {
    func testRetainedCallbackOwnerSurvivesExternalReleaseAndRejectsLateSubmission() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = RunConfiguration(
            mode: .disabled, durationSeconds: 1, diagnosticsArmed: true, audioExplicitlyEnabled: true,
            outputDirectory: directory, materialURL: nil, studyID: "synthetic-lifetime")
        var owner: RecorderOwner? = try RecorderOwner(configuration: configuration)
        weak let observed = owner
        var callback: (() -> Bool)? = try retainedCallback(owner: XCTUnwrap(owner))
        XCTAssertTrue(try XCTUnwrap(owner).seal())
        XCTAssertTrue(try XCTUnwrap(owner).seal())
        owner = nil
        XCTAssertNotNil(observed)
        XCTAssertEqual(callback?(), false)
        callback = nil
        XCTAssertNil(observed)
    }

    private func retainedCallback(owner: RecorderOwner) -> () -> Bool {
        {
            var identity = VPFrameIdentity()
            var buffer = AudioBufferList()
            return vp_recorder_submit(owner.handle, &identity, &buffer)
        }
    }
}
