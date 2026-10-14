import Foundation
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class SourceProbeRegistrationFileTests: XCTestCase {
    private func withRegistration(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("registration.json")
        let registration = SourceProbeRegistration(
            schemaVersion: 1, inputDeviceID: String(repeating: "a", count: 64),
            outputDeviceID: String(repeating: "b", count: 64), stimulusProtocol: SourceProbeRegistration.protocolID)
        try JSONEncoder().encode(registration).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try body(file)
    }

    func testPrivateBoundedRegistrationLoadsWithoutAudio() throws {
        try withRegistration { file in
            let loaded = try SourceProbeRegistrationFile.load(file)
            XCTAssertEqual(loaded.registration.stimulusProtocol, SourceProbeRegistration.protocolID)
            XCTAssertEqual(loaded.sha256.count, 64)
        }
    }

    func testPublicReadableRegistrationIsRejected() throws {
        try withRegistration { file in
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            XCTAssertThrowsError(try SourceProbeRegistrationFile.load(file))
        }
    }

    func testNonPrivateParentIsRejected() throws {
        try withRegistration { file in
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: file.deletingLastPathComponent().path)
            XCTAssertThrowsError(try SourceProbeRegistrationFile.load(file))
        }
    }

    func testSymlinkRegistrationIsRejected() throws {
        try withRegistration { file in
            let link = file.deletingLastPathComponent().appendingPathComponent("link.json")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            XCTAssertThrowsError(try SourceProbeRegistrationFile.load(link))
        }
    }

    func testOversizedRegistrationIsRejected() throws {
        try withRegistration { file in
            try Data(repeating: 7, count: SourceProbeRegistrationFile.maximumBytes + 1).write(to: file)
            XCTAssertThrowsError(try SourceProbeRegistrationFile.load(file))
        }
    }

    func testMalformedJSONIsRejected() throws {
        try withRegistration { file in
            try Data("not a registration".utf8).write(to: file)
            XCTAssertThrowsError(try SourceProbeRegistrationFile.load(file))
        }
    }
}
