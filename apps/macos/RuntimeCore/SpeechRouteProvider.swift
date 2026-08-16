import Foundation

nonisolated enum SpeechRouteError: Error, Sendable, Equatable {
    case invalidConfiguration
    case unavailable
    case timedOut
    case cancelled
    case transportFailure
    case invalidEvent
    case staleGeneration
}

nonisolated enum SpeechPCMFormat: String, Sendable, Equatable {
    case pcm16
}

nonisolated enum ASRAudioSource: String, Sendable, Equatable {
    case aec3Processed
}

nonisolated struct ASRStartRequest: Sendable, Equatable {
    let generation: UInt64
    let locale: String?
}

nonisolated struct ASRAudioInput: Sendable, Equatable {
    let generation: UInt64
    let sequenceNumber: UInt64
    let bytes: Data
    let format: SpeechPCMFormat
    let sampleRate: Int
    let channelCount: Int
    let source: ASRAudioSource
}

nonisolated enum ASRSpeechActivity: String, Sendable, Equatable {
    case started
    case ended
}

nonisolated enum ASREventKind: Sendable, Equatable {
    case partialTranscript(String)
    case finalTranscript(String)
    case speechActivity(ASRSpeechActivity)
    case cancelled
    case error(SpeechRouteError)
    case staleGeneration
}

nonisolated struct ASREvent: Sendable, Equatable {
    let generation: UInt64
    let kind: ASREventKind
}

nonisolated protocol ASRProvider: Sendable {
    func start(request: ASRStartRequest) async throws
    func send(_ input: ASRAudioInput) async throws
    func receive(generation: UInt64) async throws -> ASREvent
    func cancel(generation: UInt64) async throws
    func close(generation: UInt64) async throws
}

nonisolated struct SpeechVoiceProfile: Sendable, Equatable {
    let profileID: String
    let locale: String?
}

nonisolated struct TTSSynthesisRequest: Sendable, Equatable {
    let generation: UInt64
    let canonicalResponseText: String
    let voiceProfile: SpeechVoiceProfile
    let emotion: String?
    let pace: Double
    let style: String?
}

nonisolated struct TTSAudioChunk: Sendable, Equatable {
    let generation: UInt64
    let sequenceNumber: UInt64
    let bytes: Data
    let format: SpeechPCMFormat
    let sampleRate: Int
    let channelCount: Int
}

nonisolated enum TTSEventKind: Sendable, Equatable {
    case started
    case audio(TTSAudioChunk)
    case done
    case cancelled
    case error(SpeechRouteError)
}

nonisolated struct TTSEvent: Sendable, Equatable {
    let generation: UInt64
    let kind: TTSEventKind
}

nonisolated protocol TTSProvider: Sendable {
    func start(request: TTSSynthesisRequest) async throws
    func receive(generation: UInt64) async throws -> TTSEvent
    func cancel(generation: UInt64) async throws
    func close(generation: UInt64) async throws
}
