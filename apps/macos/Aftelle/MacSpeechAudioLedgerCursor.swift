#if DEBUG && AFTELLE_AUDIO_OBSERVATION
    import Foundation

    /// Scalar counters owned by the existing converter lock or packetizer value.
    nonisolated struct MacSpeechAudioLedgerCursor {
        let object = MacSpeechAudioObservation.shared.nextObjectID()
        private var run: UInt64 = 0
        private(set) var epoch: UInt64 = 0
        var input: UInt64 = 0
        var output: UInt64 = 0
        var unobservedInput = false

        mutating func prepare(
            _ event: inout MacSpeechAudioObservationEvent?, pending: Int = 0, stateful: Bool = false
        ) {
            guard let next = event?.run else { return }
            if run != next {
                if stateful, input != 0 { unobservedInput = true }
                run = next
                epoch = 0
                input = UInt64(pending)
                output = 0
                event?.flags |= pending == 0 ? 0 : 128
            }
            event?.object = object
            event?.epoch = epoch
            event?.inputStart = input
            event?.outputStart = output
            event?.remainderBefore = UInt64(pending)
        }

        func endpoints(_ event: inout MacSpeechAudioObservationEvent?, pending: Int = 0) {
            event?.inputEnd = input
            event?.outputEnd = output
            event?.remainderAfter = UInt64(pending)
        }

        mutating func reset() {
            unobservedInput = false
            epoch &+= 1
            input = 0
            output = 0
        }
    }

    nonisolated struct MacSpeechPCMEncodingObservation {
        private var event = MacSpeechAudioObservation.shared.begin(.encode16, stream: 1)
        private var runStart: UInt64 = 0
        private var runReason: UInt64 = 0

        mutating func append(sample: Float, encoded: Int16) {
            guard let cursor = event?.frameCount else { return }
            let reason: UInt64
            if !sample.isFinite {
                reason = 1
                event?.detail += 1
            } else if sample != 0, encoded == 0 {
                reason = 2
                event?.reserved += 1
            } else {
                reason = 0
            }
            if reason != runReason {
                finishRun(at: cursor)
                runStart = cursor
                runReason = reason
            }
            event?.frameCount += 1
        }

        private mutating func finishRun(at end: UInt64) {
            guard runReason != 0, let owner = event else { return }
            var range = MacSpeechAudioObservation.shared.begin(
                .encodingZeroRange,
                stream: 1,
                parent: owner.id
            )
            range?.inputStart = runStart
            range?.inputEnd = end
            range?.status = runReason
            if range == nil {
                event?.flags |= 2048
            }
            MacSpeechAudioObservation.shared.finish(range)
        }

        mutating func finish() {
            finishRun(at: event?.frameCount ?? 0)
            MacSpeechAudioObservation.shared.finish(event)
        }
    }
#endif
