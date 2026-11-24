import Foundation

/// Short-lived readback owned by the session worker. Source submissions are digital evidence.
nonisolated struct MacSpeechNativeRealtimeFacts {
    var deliveredCapture: [UInt64: NativeVoiceCapturePacket] = [:]
    private(set) var lastNonzero: NativeVoiceRenderFact?
    private(set) var lastMetrics: RealtimeAcousticMetrics?
    private var droppedRenders: UInt64 = 0

    #if NATIVE_VOICE_P3_OFFLINE_TEST
        typealias ShadowEvidence = @Sendable (NativeVoiceCapturePacket, NativeVoiceRenderFact)
            -> RealtimeAcousticMetrics?
        var shadowEvidence: ShadowEvidence?
    #endif

    mutating func invalidatePlayback() {
        lastNonzero = nil
        lastMetrics = nil
    }

    mutating func accept(
        _ batch: AppleNativeVoiceTransport.ServiceBatch, expected: NativeVoiceIdentity.Playback
    ) -> Bool {
        if batch.progress.droppedRenderFacts != droppedRenders {
            droppedRenders = batch.progress.droppedRenderFacts
            invalidatePlayback()
            return false
        }
        guard let rendered = batch.render.last(where: { $0.playback == expected && $0.nonzeroFrames > 0 })
        else { return false }
        lastNonzero = rendered
        return true
    }

    mutating func metrics(
        for sequence: UInt64, capture: NativeVoiceIdentity.Capture, playback: NativeVoiceIdentity.Playback?
    ) -> RealtimeAcousticMetrics? {
        guard let packet = deliveredCapture[sequence], packet.identity == capture else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        let captureAt = packet.hasFreshTiming(now: now) ? packet.hostTimeNanoseconds : nil
        let render = lastNonzero
        let digitalOutput = playback != nil && render?.playback == playback
        let renderAt = digitalOutput ? render?.hostTimeNanoseconds : nil
        #if NATIVE_VOICE_P3_OFFLINE_TEST
            if let captureAt, let render, let renderAt, render.sampleTime != nil, renderAt <= captureAt,
               NativeVoiceClock.isFresh(hostTime: renderAt, now: now), let metrics = shadowEvidence?(packet, render) {
                lastMetrics = metrics
                return metrics
            }
        #endif
        let metrics = RealtimeAcousticMetrics(
            residentPlaybackSequence: playback?.token ?? 0,
            residentPlaybackActive: digitalOutput,
            lastAudibleResidentRenderTimestampNanoseconds: nil,
            renderReferenceAvailable: false,
            renderReferenceRMS: nil,
            rawCaptureRMS: nil,
            aecOutputRMS: nil,
            linearAECOutputRMS: nil,
            renderCaptureCorrelation: nil,
            residualRenderCorrelation: nil,
            linearRenderCorrelation: nil,
            captureTimestampNanoseconds: captureAt,
            renderTimestampNanoseconds: renderAt,
            sourceAlignmentDelayMilliseconds: nil,
            estimatedDelayMilliseconds: nil,
            erlDecibels: nil,
            erleDecibels: nil,
            renderCaptureSkewFrames: nil,
            driftState: .unknown,
            sourceAssessment: .uncertain,
            sourceGateOpen: false,
            sourceGateEpoch: 0,
            aecActive: false,
            renderCaptureIsolationEstablished: false,
            sourceAlignmentLocked: false,
            routeStable: true,
            inputDeviceAvailable: true,
            outputDeviceAvailable: true
        )
        lastMetrics = metrics
        return metrics
    }

    func matches(_ metrics: RealtimeAcousticMetrics, playback: NativeVoiceIdentity.Playback) -> Bool {
        metrics.residentPlaybackSequence == playback.token
            && metrics.sourceGateOpen && metrics.sourceGateEpoch > 0 && metrics == lastMetrics
            && NativeVoiceClock.isFresh(
                hostTime: metrics.captureTimestampNanoseconds, now: DispatchTime.now().uptimeNanoseconds
            )
    }
}

nonisolated extension NativeVoiceIdentity.Authority {
    init(realtime session: RealtimeBrainSessionIdentity, configuration: UInt64) {
        self.init(runtimeGeneration: session.generation, routeEpoch: session.routeEpoch, configurationID: configuration)
    }
}

nonisolated extension NativeVoiceIdentity {
    func replacingPlayback(cancelled: Bool) -> NativeVoiceIdentity {
        .init(
            authority: capture.authority, captureGeneration: capture.generation, captureToken: capture.token,
            playbackEpoch: playback.epoch + (cancelled ? 1 : 0), playbackToken: playback.token + 1
        )
    }
}

nonisolated extension MacSpeechAudioHostSnapshot {
    static func nativeVoiceCapture(_ format: NativeVoiceIOFormat) -> Self {
        .init(
            authorization: .authorized, state: .capturing, isCapturing: true,
            inputDevice: .unavailable, outputDevice: .unavailable,
            actualSampleRate: format.sampleRate, actualChannelCount: format.channels,
            normalizedOutputFormat: MacSpeechAudioInputFormat.description, generatedFrameCount: 0,
            droppedFrameCount: 0, rejectedStaleFrameCount: 0, queuedFrameCount: 0, latestActivity: 0, lastError: nil
        )
    }
}

nonisolated struct MacSpeechNativePlaybackCounters {
    var chunkCount = 0
    var byteCount = 0
    var pressureWaits = 0
}

nonisolated extension MacSpeechAudioOutputHostSnapshot {
    static func nativeVoiceOutput(
        state: MacSpeechAudioOutputHostState, token: UInt64, counters: MacSpeechNativePlaybackCounters,
        started: Bool, error: MacSpeechAudioOutputHostError?
    ) -> Self {
        .init(
            state: state, generation: token, outputDevice: .unavailable,
            providerFormat: MacSpeechPCMOutputFormat.description, localFormat: "Apple VP Source",
            queueCapacity: 1, queueDepth: 0, bufferedDurationMilliseconds: 0, scheduledChunkCount: 0,
            enqueuedChunkCount: counters.chunkCount, enqueuedByteCount: counters.byteCount, playedChunkCount: 0,
            playedByteCount: 0, playbackStartedCount: started ? 1 : 0, playbackCompletedCount: 0,
            underrunCount: 0, pressureWaitCount: counters.pressureWaits, rejectedCallbackCount: 0,
            lastError: error?.rawValue, recentEvents: []
        )
    }
}
