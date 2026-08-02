import Foundation

nonisolated enum NativeSpeechAudioFormat: String, Sendable, Equatable {
    case pcm16
}

nonisolated struct NativeSpeechAudioPayload: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let sequenceNumber: UInt64
    let bytes: Data
    let format: NativeSpeechAudioFormat
}
