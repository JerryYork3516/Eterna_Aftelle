import Foundation
import XCTest

@testable import VPReferenceAudio

final class ManifestWriterTests: XCTestCase {
    func testManifestUsesPrivateFilePermissions() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("fixture.json")
            let bytes = Data("{}".utf8)
            try PrivateManifestWriter.write(data: bytes, target: target)
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testExistingEvidenceFileCannotBeOverwritten() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("fixture.json")
            let original = Data("original fixture".utf8)
            try PrivateManifestWriter.write(data: original, target: target)
            XCTAssertThrowsError(try PrivateManifestWriter.write(data: Data("replacement".utf8), target: target))
            XCTAssertEqual(try Data(contentsOf: target), original)
        }
    }

    func testSymbolicLinkCannotRedirectManifestWrites() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("fixture.json")
            let original = directory.appendingPathComponent("original.json")
            let bytes = Data("fixture".utf8)
            try PrivateManifestWriter.write(data: bytes, target: original)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: original)
            XCTAssertThrowsError(try PrivateManifestWriter.write(data: Data("replacement".utf8), target: target))
            XCTAssertEqual(try Data(contentsOf: original), bytes)
        }
    }

    func testExactManifestByteLimitIsAccepted() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("fixture.json")
            let bytes = Data(repeating: 0x20, count: PrivateManifestWriter.maximumBytes)
            try PrivateManifestWriter.write(data: bytes, target: target)
            XCTAssertEqual(try Data(contentsOf: target).count, PrivateManifestWriter.maximumBytes)
        }
    }

    func testOverBudgetManifestDoesNotCreateFile() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("fixture.json")
            let bytes = Data(repeating: 0x20, count: PrivateManifestWriter.maximumBytes + 1)
            XCTAssertThrowsError(try PrivateManifestWriter.write(data: bytes, target: target))
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        }
    }

    func testUnavailableParentFailsWithoutCreatingFile() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("missing/fixture.json")
            XCTAssertThrowsError(try PrivateManifestWriter.write(data: Data("{}".utf8), target: target))
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
