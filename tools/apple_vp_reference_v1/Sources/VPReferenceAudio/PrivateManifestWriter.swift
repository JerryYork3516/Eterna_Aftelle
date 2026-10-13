import Darwin
import Foundation

enum PrivateManifestWriter {
    static let maximumBytes = 64 * 1024

    static func write(data: Data, target: URL) throws {
        guard !data.isEmpty, data.count <= maximumBytes else { throw AudioReferenceError.evidenceWriteFailed }
        let descriptor = target.path.withCString { path in
            Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw AudioReferenceError.evidenceWriteFailed }
        defer { Darwin.close(descriptor) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw AudioReferenceError.evidenceWriteFailed }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw AudioReferenceError.evidenceWriteFailed }
                offset += count
            }
        }
        guard Darwin.fsync(descriptor) == 0 else { throw AudioReferenceError.evidenceWriteFailed }
    }
}
