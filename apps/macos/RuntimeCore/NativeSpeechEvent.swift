import Foundation

nonisolated struct NativeSpeechToolRequest: Sendable, Equatable {
    let requestID: String
    let toolName: String
    let arguments: Data
}

nonisolated enum NativeSpeechEventKind: Sendable, Equatable {
    case connected
    case sessionUpdated
    case inputSpeechStarted
    case inputSpeechEnded
    case partialTranscript(String)
    case finalTranscript(String)
    case thinking
    case outputText(text: String, isFinal: Bool)
    case outputAudio(NativeSpeechAudioPayload)
    case toolRequestCandidate(NativeSpeechToolRequest)
    case responseCompleted
    case turnFailed(NativeSpeechError)
    case cancelled(reason: String?)
    case closed
    case failed(NativeSpeechError)
}

nonisolated struct NativeSpeechEvent: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let kind: NativeSpeechEventKind
}
