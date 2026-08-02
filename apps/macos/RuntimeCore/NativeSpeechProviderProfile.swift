import Foundation

nonisolated enum NativeSpeechTurnDetectionType: String, Sendable, Equatable {
    case serverVAD = "server_vad"
}

nonisolated struct NativeSpeechTurnDetection: Sendable, Equatable {
    let type: NativeSpeechTurnDetectionType
    let prefixPaddingMilliseconds: Int
}

nonisolated struct NativeSpeechProviderProfile: Sendable, Equatable {
    let profileID: String
    let providerID: String
    let capability: String
    let adapterID: String
    let modelID: String
    let voiceID: String
    let endpoint: URL
    let transport: String
    let inputAudioFormat: NativeSpeechAudioFormat
    let outputAudioFormat: NativeSpeechAudioFormat
    let turnDetection: NativeSpeechTurnDetection
    let languageMetadata: String
    let keyRef: String

    func validate() throws {
        let requiredIdentifiers = [
            profileID,
            providerID,
            capability,
            adapterID,
            modelID,
            voiceID,
            transport
        ]
        guard requiredIdentifiers.allSatisfy({ !$0.isEmpty }) else {
            throw NativeSpeechError.invalidConfiguration
        }
        guard endpoint.scheme?.lowercased() == "wss" else {
            throw NativeSpeechError.invalidConfiguration
        }
        guard keyRef.hasPrefix("keychain://"),
              keyRef.count > "keychain://".count else {
            throw NativeSpeechError.invalidConfiguration
        }
        guard turnDetection.prefixPaddingMilliseconds >= 0 else {
            throw NativeSpeechError.invalidConfiguration
        }
    }
}
