enum ResidentVisualIntent: String, CaseIterable, Equatable, Identifiable {
    case idle
    case listening
    case thinking
    case speaking
    case sleeping
    case error
    case loading
    case exit

    var id: String {
        rawValue
    }

    var debugLocalizedKey: String {
        "particleDebug.transition.state.\(rawValue)"
    }
}

enum ResidentSpeechPhase: String, CaseIterable, Equatable, Identifiable {
    case inactive
    case started
    case sustained
    case paused
    case ended

    var id: String {
        rawValue
    }

    var debugLocalizedKey: String {
        "particleDebug.speech.phase.\(rawValue)"
    }
}

struct ResidentSpeechSignal: Equatable {
    var phase: ResidentSpeechPhase
    var intensity: Float

    static let inactive = ResidentSpeechSignal(phase: .inactive, intensity: 0)
    static let ended = ResidentSpeechSignal(phase: .ended, intensity: 0)

    func normalized() -> ResidentSpeechSignal {
        ResidentSpeechSignal(
            phase: phase,
            intensity: min(1, max(0, intensity))
        )
    }
}
