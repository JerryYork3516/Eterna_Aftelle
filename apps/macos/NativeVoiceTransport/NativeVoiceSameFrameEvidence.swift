#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
import Darwin
import Foundation

/// A bounded copy of the selected run's already produced Worker packets, owned by the Lab.
nonisolated struct NativeVoiceSameFrameCapture {
    static let packetCount = 750
    static let framesPerPacket = 480
    static let pcmBytes = packetCount * framesPerPacket * 2

    enum State: String, Encodable, Sendable {
        case complete, incomplete, discontinuous, stopped
    }

    struct Summary: Encodable, Sendable {
        let state: State
        let identity: NativeVoiceIdentity.Capture
        let segment: UInt64?
        let firstSampleCount: UInt64?
        let frames: Int
        let sampleRate = 24000
        let channels = 1
        let bitsPerSample = 16
    }

    private let identity: NativeVoiceIdentity.Capture
    private var segment: UInt64?
    private var pcm = Data(capacity: pcmBytes)
    private var count = 0
    private var discontinuous = false

    init(identity: NativeVoiceIdentity.Capture) {
        self.identity = identity
    }

    var needsPackets: Bool {
        !discontinuous && count < Self.packetCount
    }

    mutating func append(_ packets: [NativeVoiceCapturePacket]) {
        for packet in packets {
            guard needsPackets else { return }
            guard packet.identity == identity, segment == nil || segment == packet.segment,
                  packet.sampleCount == UInt64(count * Self.framesPerPacket),
                  packet.bytes.count == Self.framesPerPacket * 2
            else {
                discontinuous = true
                pcm = Data()
                return
            }
            segment = packet.segment
            pcm.append(packet.bytes)
            count += 1
        }
    }

    func finish(endedNormally: Bool) -> (summary: Summary, pcm: Data?) {
        let state: State
        if !endedNormally {
            state = .stopped
        } else if discontinuous {
            state = .discontinuous
        } else {
            state = count == Self.packetCount ? .complete : .incomplete
        }
        let summary = Summary(
            state: state, identity: identity, segment: segment,
            firstSampleCount: count > 0 ? 0 : nil, frames: count * Self.framesPerPacket
        )
        return (summary, state == .complete ? pcm : nil)
    }
}

/// AppController supplies the already verified App Sandbox Caches directory descriptor.
nonisolated enum NativeVoiceSameFrameFiles {
    static let folderName = "same-frame-exports"
    static let wavName = "capture.wav"
    static let jsonName = "diagnostics.json"

    static func trialName(_ runID: UUID) -> String {
        "run-" + runID.uuidString
    }

    static func openFolder(in parent: Int32) throws -> Int32 {
        if mkdirat(parent, folderName, 0o700) != 0, errno != EEXIST {
            throw currentError()
        }
        return try openPrivateDirectory(folderName, in: parent)
    }

    static func checkWritable(in folder: Int32) throws {
        let probe = ".preflight-" + UUID().uuidString
        let descriptor = try createStaging(probe, in: folder)
        defer { Darwin.close(descriptor) }
        do {
            try write(Data(), as: jsonName, in: descriptor)
        } catch {
            try removeStaging(probe, opened: descriptor, in: folder)
            throw error
        }
        try removeStaging(probe, opened: descriptor, in: folder)
    }

    static func publish(json: Data, wav: Data?, runID: UUID, in folder: Int32) throws {
        let staging = ".saving-" + UUID().uuidString
        let directory = try createStaging(staging, in: folder)
        defer { Darwin.close(directory) }

        var pending = staging
        do {
            try write(json, as: jsonName, in: directory)
            if let wav {
                try write(wav, as: wavName, in: directory)
            }
            let destination = trialName(runID)
            guard fsync(directory) == 0,
                  renameatx_np(folder, staging, folder, destination, UInt32(RENAME_EXCL)) == 0
            else { throw currentError() }
            pending = destination
            guard fsync(folder) == 0 else { throw currentError() }
        } catch {
            try removeStaging(pending, opened: directory, in: folder)
            throw error
        }
    }

    private static func createStaging(_ name: String, in folder: Int32) throws -> Int32 {
        guard mkdirat(folder, name, 0o700) == 0 else { throw currentError() }
        do {
            return try openPrivateDirectory(name, in: folder)
        } catch {
            guard unlinkat(folder, name, AT_REMOVEDIR) == 0 else { throw currentError() }
            throw error
        }
    }

    private static func openPrivateDirectory(_ name: String, in parent: Int32) throws -> Int32 {
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw currentError() }
        var result = stat()
        guard fstat(descriptor, &result) == 0, result.st_uid == getuid(), result.st_mode & 0o7777 == 0o700 else {
            Darwin.close(descriptor)
            throw CocoaError(.fileWriteNoPermission)
        }
        return descriptor
    }

    private static func write(_ bytes: Data, as name: String, in directory: Int32) throws {
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw currentError() }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            var attributes = stat()
            guard fchmod(descriptor, 0o600) == 0, fstat(descriptor, &attributes) == 0,
                  attributes.st_uid == getuid(), attributes.st_nlink == 1,
                  attributes.st_mode & S_IFMT == S_IFREG, attributes.st_mode & 0o7777 == 0o600
            else { throw CocoaError(.fileWriteNoPermission) }
            try file.write(contentsOf: bytes)
            try file.synchronize()
            try file.close()
        } catch {
            try? file.close()
            throw error
        }
    }

    private static func removeStaging(_ name: String, opened: Int32, in folder: Int32) throws {
        var expected = stat(), actual = stat()
        guard fstat(opened, &expected) == 0, fstatat(folder, name, &actual, AT_SYMLINK_NOFOLLOW) == 0,
              actual.st_dev == expected.st_dev, actual.st_ino == expected.st_ino
        else { throw CocoaError(.fileWriteNoPermission) }
        for fileName in [wavName, jsonName] {
            if unlinkat(opened, fileName, 0) != 0, errno != ENOENT {
                throw currentError()
            }
        }
        guard unlinkat(folder, name, AT_REMOVEDIR) == 0 else { throw currentError() }
    }

    private static func currentError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
#endif
