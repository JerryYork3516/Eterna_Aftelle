#if DEBUG && AFTELLE_AUDIO_OBSERVATION
    /// Fixed-width, scalar-only records. Units and field meanings are versioned in
    /// the Step 2A report; no pointers, strings, identifiers from devices, or PCM.
    nonisolated struct MacSpeechAudioObservationEvent {
        var id: UInt64 = 0
        var kind: UInt64 = 0
        var stream: UInt64 = 0
        var parent: UInt64 = 0
        var thread: UInt64 = 0
        var entered: UInt64 = 0
        var began: UInt64 = 0
        var completed: UInt64 = 0
        var contentTime: UInt64 = 0
        var nativeHostTime: UInt64 = 0
        var nativeSampleTime: UInt64 = 0
        var flags: UInt64 = 0
        var object: UInt64 = 0
        var epoch: UInt64 = 0
        var generation: UInt64 = 0
        var inputStart: UInt64 = 0
        var inputEnd: UInt64 = 0
        var outputStart: UInt64 = 0
        var outputEnd: UInt64 = 0
        var sampleRate: UInt64 = 0
        var format: UInt64 = 0
        var frameCount: UInt64 = 0
        var remainderBefore: UInt64 = 0
        var remainderAfter: UInt64 = 0
        var status: UInt64 = 0
        var detail: UInt64 = 0
        var run: UInt64 = 0
        var reserved: UInt64 = 0
    }

    nonisolated enum MacSpeechAudioObservationKind: UInt64 {
        case nativeCallback = 1
        case converter, hostCall, aecFrame, streamReset
        case captureLock, rejected, frameAssembly
    }

    nonisolated enum MacSpeechAudioObservationStatus: UInt64 {
        case valid = 0
        case missingHostTime, missingSampleTime, conversionFailed
        case rejectedGeneration, unavailable, processingFailed, discontinuity
        case fifoOverflow, unprocessed, pending, unsupportedMode
    }

    extension MacSpeechAudioObservation {
        static func converterTimeFailure(_ reason: String?) -> UInt64 {
            switch reason {
            case nil: 0
            case "output_cursor_ahead_of_input": 1
            case "output_cursor_uncovered": 2
            case "first_input_time_missing": 3
            case "input_time_missing": 4
            case "input_time_discontinuity": 5
            default: 6
            }
        }

        struct Summary {
            let run: UInt64
            let admitted: UInt64
            let written: UInt64
            let lost: UInt64
            let pending: UInt64
            let invalidReasons: UInt64
            let sealed: Bool
        }

        /// Invalid reasons are a bitset, so a later write failure cannot conceal an
        /// earlier overflow. Arm/seal are control-thread operations only.
        enum Invalid: UInt64 {
            case overflow = 1
            case deadline = 2
            case writeFailure = 4
            case pending = 8
            case workerSetup = 16
        }
    }

    /// Owned by the existing Host serial queue. These cursors never participate in
    /// audio processing; a new diagnostic run cannot invent pre-arm remainder IDs.
    nonisolated struct MacSpeechAudioObservationCursor {
        private var run: UInt64 = 0
        private(set) var epoch: UInt64 = 0
        private(set) var position: UInt64 = 0

        mutating func begin(run next: UInt64, count: Int) -> UInt64 {
            if run != next {
                run = next
                epoch = 0
                position = 0
            }
            let start = position
            position += UInt64(count)
            return start
        }

        mutating func reset() {
            epoch &+= 1
            position = 0
        }
    }
#endif
