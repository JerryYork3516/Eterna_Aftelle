import Darwin
import Foundation

enum PrivateManifestWriter {
    static let maximumBytes = 64 * 1024

    static func write(
        data: Data, target: URL, synchronize: (Int32) -> Int32 = Darwin.fsync
    ) throws {
        guard !data.isEmpty, data.count <= maximumBytes else { throw AudioReferenceError.evidenceWriteFailed }
        let pending = target.deletingLastPathComponent()
            .appendingPathComponent(".vp0-pending-\(UUID().uuidString)")
        let descriptor = pending.path.withCString { path in
            Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw AudioReferenceError.evidenceWriteFailed }
        defer {
            Darwin.close(descriptor)
            _ = pending.path.withCString { Darwin.unlink($0) }
        }
        try writeBytes(data, descriptor: descriptor)
        guard synchronize(descriptor) == 0 else { throw AudioReferenceError.evidenceWriteFailed }
        let published = pending.path.withCString { source in
            target.path.withCString { destination in
                Darwin.renameatx_np(AT_FDCWD, source, AT_FDCWD, destination, UInt32(RENAME_EXCL))
            }
        }
        guard published == 0 else { throw AudioReferenceError.evidenceWriteFailed }
    }

    private static func writeBytes(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw AudioReferenceError.evidenceWriteFailed }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw AudioReferenceError.evidenceWriteFailed }
                offset += count
            }
        }
    }
}
