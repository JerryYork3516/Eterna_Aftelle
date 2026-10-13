import Foundation
import VPReferenceCore

struct PCMSourceIdentity: Codable {
    let sha256: String
    let nativePCMSHA256: String
    let fileBytes: UInt64
    let sourceStartFrame: Int64
    let sourceFrameCount: UInt64
    let nativeFormat: NativeAudioFormat
}
