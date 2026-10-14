import CryptoKit
import Darwin
import Foundation
import VPReferenceCore

enum SourceProbeRegistrationFile {
    static let maximumBytes = 4096

    static func load(_ url: URL) throws -> (registration: SourceProbeRegistration, sha256: String) {
        let parent = url.deletingLastPathComponent().path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard parent >= 0 else { throw EngineeringFailure(stage: .command, code: .invalidArguments) }
        defer { Darwin.close(parent) }
        var directoryInfo = stat()
        guard fstat(parent, &directoryInfo) == 0, directoryInfo.st_uid == getuid(),
            directoryInfo.st_mode & 0o777 == 0o700
        else { throw EngineeringFailure(stage: .command, code: .invalidArguments) }
        let descriptor = url.lastPathComponent.withCString {
            Darwin.openat(parent, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw EngineeringFailure(stage: .command, code: .invalidArguments) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == getuid(), info.st_mode & 0o777 == 0o600,
            info.st_size > 0, info.st_size <= maximumBytes,
            let data = try handle.read(upToCount: maximumBytes + 1), data.count == info.st_size
        else { throw EngineeringFailure(stage: .command, code: .invalidArguments) }
        let registration = try JSONDecoder().decode(SourceProbeRegistration.self, from: data)
        try registration.validate()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (registration, digest)
    }
}
