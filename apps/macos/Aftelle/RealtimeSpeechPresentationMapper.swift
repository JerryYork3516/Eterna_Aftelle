import Foundation

struct RealtimeSpeechParticlePresentation: Equatable {
    let visualIntent: ResidentVisualIntent
    let speechSignal: ResidentSpeechSignal
}

enum RealtimeSpeechPresentationMapper {
    static func map(
        state: RealtimeSpeechState,
        previousState: RealtimeSpeechState,
        currentSpeechSignal: ResidentSpeechSignal
    ) -> RealtimeSpeechParticlePresentation {
        let visualIntent: ResidentVisualIntent = switch state {
        case .idle: .idle
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: .speaking
        }

        let speechSignal: ResidentSpeechSignal
        if state == .speaking {
            speechSignal = previousState == .speaking
                ? ResidentSpeechSignal(
                    phase: .sustained,
                    intensity: max(
                        currentSpeechSignal.intensity,
                        ParticleTuning.Engine.defaultSpeechIntensity
                    )
                )
                : ResidentSpeechSignal(
                    phase: .started,
                    intensity: ParticleTuning.Engine.defaultSpeechIntensity
                )
        } else {
            speechSignal = .ended
        }

        return RealtimeSpeechParticlePresentation(
            visualIntent: visualIntent,
            speechSignal: speechSignal
        )
    }
}
