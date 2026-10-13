import AVFoundation
import CryptoKit
import Foundation
import VPReferenceCore

struct PCMSourceMaterial {
    static let maximumBytes: UInt64 = 8 * 1024 * 1024
    let buffer: AVAudioPCMBuffer
    let identity: PCMSourceIdentity

    static func load(url: URL) throws -> Self {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileBytes = (attributes[.size] as? NSNumber)?.uint64Value ?? UInt64.max
        guard fileBytes <= maximumBytes else { throw AudioReferenceError.materialTooLarge }
        let descriptor = try AVAudioFile(forReading: url)
        let format = descriptor.fileFormat
        guard format.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM,
            format.commonFormat != .otherFormat, descriptor.length > 0
        else {
            throw AudioReferenceError.unsupportedMaterial
        }
        let bytesPerFrame = UInt64(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0, format.channelCount > 0, format.channelCount <= 32 else {
            throw AudioReferenceError.unsupportedMaterial
        }
        let totalBytesPerFrame = bytesPerFrame * (format.isInterleaved ? 1 : UInt64(format.channelCount))
        guard UInt64(descriptor.length) <= maximumBytes / totalBytesPerFrame,
            descriptor.length <= UInt32.max
        else {
            throw AudioReferenceError.materialTooLarge
        }
        let reader = try AVAudioFile(
            forReading: url, commonFormat: format.commonFormat, interleaved: format.isInterleaved
        )
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: reader.processingFormat,
                frameCapacity: AVAudioFrameCount(reader.length))
        else {
            throw AudioReferenceError.unsupportedMaterial
        }
        try reader.read(into: buffer)
        guard Int64(buffer.frameLength) == reader.length else { throw AudioReferenceError.unsupportedMaterial }
        let identity = PCMSourceIdentity(
            sha256: try hash(url: url), nativePCMSHA256: hash(buffer: buffer),
            fileBytes: fileBytes, sourceStartFrame: 0,
            sourceFrameCount: UInt64(buffer.frameLength), nativeFormat: AppleEngineDriver.snapshot(buffer.format)
        )
        return Self(buffer: buffer, identity: identity)
    }

    private static func hash(buffer: AVAudioPCMBuffer) -> String {
        var digest = SHA256()
        for audio in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            let bytes = UnsafeRawBufferPointer(start: audio.mData, count: Int(audio.mDataByteSize))
            digest.update(bufferPointer: bytes)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
