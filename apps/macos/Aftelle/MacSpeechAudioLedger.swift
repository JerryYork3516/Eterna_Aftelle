#if DEBUG && AFTELLE_AUDIO_OBSERVATION
    import Foundation

    nonisolated enum MacSpeechAudioLedger {
        enum Action: UInt64 {
            case pass = 1, retain, release, zero, reset
            case accepted, rejected, dropOldest, drain, clear, pending
        }

        static var recorder: MacSpeechAudioObservation { MacSpeechAudioObservation.shared }

        static func snapshot(
            _ value: MacSpeechAcousticObservationSnapshot?, into event: inout MacSpeechAudioObservationEvent?
        ) {
            guard let value else { event?.flags |= 1; return }
            event?.reserved = value.captureFrameIndex
            event?.detail = value.playbackSequence
            event?.epoch = value.sourceGateEpoch
            event?.contentTime = value.captureHostTimeNanoseconds ?? 0
            event?.format = classification(value.inputClassification)
            event?.flags |= value.sourceGateOpen ? 2 : 0
            event?.flags |= value.captureHostTimeNanoseconds == nil ? 4 : 0
        }

        static func classification(_ value: MacSpeechAcousticInputClassification) -> UInt64 {
            switch value {
            case .echoOnly: 1
            case .nearEndSpeech: 2
            case .doubleTalk: 3
            case .uncertain: 4
            }
        }

        static func branch(_ value: String?) -> UInt64 {
            switch value {
            case "playback_inactive": 1
            case "alternative_echo_reference": 2
            case "no_match_isolated_near_end": 3
            case "no_match_uncertain": 4
            case "resident_only": 5
            case "immediate_double_talk": 6
            default: secondaryBranch(value)
            }
        }

        private static func secondaryBranch(_ value: String?) -> UInt64 {
            switch value {
            case "adaptive_double_talk": 7
            case "isolated_near_end": 8
            case "unaligned_isolated_near_end": 9
            case "low_correlation_near_end": 10
            case "locked_echo": 11
            case "uncertain": 12
            default: 0
            }
        }

        static func reason(_ value: MacSpeechSourceGateCloseReason?) -> UInt64 {
            switch value {
            case .nonUserHangover: 1
            case .sourceEvidenceReset: 2
            case .residualEchoProtection: 3
            case .playbackLifecycle: 4
            case .routeRebuild: 5
            case .hostFallback: 6
            case nil: 0
            }
        }

        static func fallback(_ reason: MacSpeechAECFallbackReason, object: UInt64) {
            var event = recorder.begin(.hostFallback, stream: 1)
            event?.object = object
            event?.status = fallbackCode(reason)
            recorder.finish(event)
        }

        private static func fallbackCode(_ reason: MacSpeechAECFallbackReason) -> UInt64 {
            switch reason {
            case .initializationFailed: 1
            case .renderProcessingFailed: 2
            case .captureProcessingFailed: 3
            case .delayInvalid: 4
            case .statsUnavailable: 5
            default: otherFallbackCode(reason)
            }
        }

        private static func otherFallbackCode(_ reason: MacSpeechAECFallbackReason) -> UInt64 {
            switch reason {
            case .fifoOverflow: 6
            case .residualEcho: 7
            case .sourceAlignmentUnavailable: 8
            case .sourceClassificationUncertain: 9
            case .routeRebuild: 10
            case .requested: 11
            default: 0
            }
        }

        static func gate(
            _ action: Action, object: UInt64, snapshot value: MacSpeechAcousticObservationSnapshot,
            count: Int, currentEpoch: UInt64, reason: MacSpeechSourceGateCloseReason? = nil,
            context: UInt64 = 0
        ) {
            var event = recorder.begin(.gateAction, stream: 1)
            snapshot(value, into: &event)
            event?.object = object
            event?.status = action.rawValue
            event?.frameCount = UInt64(count)
            event?.inputEnd = UInt64(count)
            // New kinds use parent as an event ID only. The original epoch stays in
            // epoch; current gate epoch and reason are a separate state record.
            let parent = event?.id ?? 0
            recorder.finish(event)
            guard parent != 0 else { return }
            var state = recorder.begin(.gateDecision, stream: 1, parent: parent)
            state?.object = object
            state?.epoch = currentEpoch
            state?.status = self.reason(reason)
            state?.detail = context
            recorder.finish(state)
        }

        static func hostOutput(
            _ spans: [MacSpeechAcousticCaptureSpan], call: MacSpeechAudioObservationEvent?
        ) {
            guard let call else { return }
            var summary = recorder.begin(.hostOutput, stream: 1, parent: call.id)
            summary?.object = call.object
            summary?.frameCount = UInt64(spans.count)
            summary?.flags = 8 // Summary, not a source span.
            summary?.status = call.status
            recorder.finish(summary)
            var position: UInt64 = 0
            for span in spans {
                var event = recorder.begin(.hostOutput, stream: 1, parent: call.id)
                guard event != nil else { return }
                snapshot(span.observation, into: &event)
                event?.object = call.object
                event?.inputEnd = UInt64(span.samples.count)
                event?.frameCount = UInt64(span.samples.count)
                event?.outputStart = position
                position += UInt64(span.samples.count)
                event?.outputEnd = position
                recorder.finish(event)
            }
        }
    }
#endif
