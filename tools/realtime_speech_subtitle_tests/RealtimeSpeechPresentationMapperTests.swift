import Foundation

enum ResidentVisualIntent: String, Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

enum ResidentSpeechPhase: String, Equatable {
    case inactive
    case started
    case sustained
    case paused
    case ended
}

struct ResidentSpeechSignal: Equatable {
    var phase: ResidentSpeechPhase
    var intensity: Float

    static let ended = ResidentSpeechSignal(phase: .ended, intensity: 0)
}

enum ParticleTuning {
    enum Engine {
        static let defaultSpeechIntensity: Float = 0.68
    }
}

enum RealtimeSpeechState: String, Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

@main
@MainActor
private struct RealtimeSpeechPresentationMapperTests {
    private static var checks = 0

    static func main() {
        verifyNonSpeakingState(.idle, intent: .idle)
        verifyNonSpeakingState(.listening, intent: .listening)
        verifyNonSpeakingState(.thinking, intent: .thinking)

        let started = RealtimeSpeechPresentationMapper.map(
            state: .speaking,
            previousState: .thinking,
            currentSpeechSignal: .ended
        )
        expect(started.visualIntent == .speaking, "speaking maps exactly")
        expect(started.speechSignal.phase == .started, "real speaking entry emits started")
        expect(started.speechSignal.intensity == 0.68, "started uses standard intensity")

        let sustained = RealtimeSpeechPresentationMapper.map(
            state: .speaking,
            previousState: .speaking,
            currentSpeechSignal: ResidentSpeechSignal(
                phase: .started,
                intensity: 0.8
            )
        )
        expect(sustained.visualIntent == .speaking, "sustained intent remains speaking")
        expect(sustained.speechSignal.phase == .sustained, "continued playback emits sustained")
        expect(sustained.speechSignal.intensity == 0.8, "sustained intensity is not reduced")

        let playbackEnded = RealtimeSpeechPresentationMapper.map(
            state: .listening,
            previousState: .speaking,
            currentSpeechSignal: sustained.speechSignal
        )
        expect(playbackEnded.visualIntent == .listening, "playback completion returns listening")
        expect(playbackEnded.speechSignal == .ended, "playback completion emits ended")

        print("realtime_speech_particle_mapping_checks=\(checks)")
    }

    private static func verifyNonSpeakingState(
        _ state: RealtimeSpeechState,
        intent: ResidentVisualIntent
    ) {
        let mapping = RealtimeSpeechPresentationMapper.map(
            state: state,
            previousState: .listening,
            currentSpeechSignal: ResidentSpeechSignal(
                phase: .sustained,
                intensity: 1
            )
        )
        expect(mapping.visualIntent == intent, "\(state.rawValue) maps exactly")
        expect(mapping.speechSignal == .ended, "\(state.rawValue) emits ended")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
