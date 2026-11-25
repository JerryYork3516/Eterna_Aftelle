import Foundation

#if APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED && (!DEBUG || NATIVE_VOICE_P3_OFFLINE_TEST)
    #error("Device execution and offline Shadow cannot share a build")
#endif

/// Short-lived readback owned by the session worker. Source submissions are digital evidence.
nonisolated struct MacSpeechNativeRealtimeFacts {
    private struct BufferedCapture {
        let frame: MacSpeechAudioFrame
        let packet: NativeVoiceCapturePacket
    }

    private var capture: [BufferedCapture] = []
    private(set) var captureQueue = MacSpeechNativeCaptureQueueReadback()
    var deliveredCapture: [UInt64: NativeVoiceCapturePacket] = [:]
    private(set) var lastNonzero: NativeVoiceRenderFact?
    private(set) var lastMetrics: RealtimeAcousticMetrics?
    private(set) var lastSource: NativeVoiceRenderFact?
    private(set) var lastNonzeroSubmission: NativeVoiceRenderFact?
    private(set) var lastDigitalHandoff: NativeVoiceRenderFact?
    private var droppedRenders: UInt64 = 0

    #if NATIVE_VOICE_P3_OFFLINE_TEST
        typealias ShadowEvidence = @Sendable (NativeVoiceCapturePacket, NativeVoiceRenderFact)
            -> RealtimeAcousticMetrics?
        var shadowEvidence: ShadowEvidence?
    #endif

    mutating func bufferCapture(_ packets: [NativeVoiceCapturePacket], expected: NativeVoiceIdentity.Capture) {
        let arrival = DispatchTime.now().uptimeNanoseconds
        for packet in packets {
            guard packet.identity == expected else {
                captureQueue.stalePackets &+= 1
                continue
            }
            captureQueue.generatedPackets &+= 1
            captureQueue.lastContentSegment = packet.segment
            captureQueue.lastPacketStartSample = packet.sampleCount
            // Runtime orders delivery by arrival; packet HostTime alone drives acoustic freshness.
            let frame = MacSpeechAudioFrame(
                captureGeneration: expected.generation, sequenceNumber: captureQueue.generatedPackets,
                monotonicTimestampNanoseconds: arrival, pcm16Bytes: packet.bytes, activity: 0
            )
            if capture.count == MacSpeechAudioInputFormat.frameCapacity {
                capture.removeFirst()
                captureQueue.overflowPackets &+= 1
            }
            capture.append(BufferedCapture(frame: frame, packet: packet))
            captureQueue.highWaterPackets = max(captureQueue.highWaterPackets, capture.count)
        }
        captureQueue.pendingPackets = capture.count
    }

    mutating func drainCapture(maxCount: Int) -> [MacSpeechAudioFrame] {
        let count = min(max(0, maxCount), capture.count)
        let frames = capture.prefix(count)
        deliveredCapture = Dictionary(uniqueKeysWithValues: frames.map { ($0.frame.sequenceNumber, $0.packet) })
        let result = frames.map(\.frame)
        capture.removeFirst(count)
        captureQueue.pendingPackets = capture.count
        captureQueue.deliveredPackets &+= UInt64(count)
        return result
    }

    mutating func discardCapture(forTransition: Bool) {
        if forTransition {
            captureQueue.transitionDiscardedPackets &+= UInt64(capture.count)
            captureQueue.lastContentSegment = nil
            captureQueue.lastPacketStartSample = nil
        } else {
            captureQueue.closeDiscardedPackets &+= UInt64(capture.count)
        }
        capture.removeAll(keepingCapacity: true)
        deliveredCapture.removeAll(keepingCapacity: true)
        captureQueue.pendingPackets = 0
    }

    mutating func recordSource(_ render: [NativeVoiceRenderFact], expected: NativeVoiceIdentity.Playback) {
        if let observed = render.last(where: { $0.playback == expected }) {
            lastSource = observed
        }
        if let submitted = render.last(where: { $0.playback == expected && $0.nonzeroFrames > 0 }) {
            lastNonzeroSubmission = submitted
        }
        if let handoff = render.last(where: { $0.playback == expected && $0.isDigitalHandoff }) {
            lastDigitalHandoff = handoff
        }
    }

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

nonisolated struct MacSpeechNativeCaptureQueueReadback: Encodable, Sendable {
    var generatedPackets: UInt64 = 0
    var deliveredPackets: UInt64 = 0
    var overflowPackets: UInt64 = 0
    var stalePackets: UInt64 = 0
    var transitionDiscardedPackets: UInt64 = 0
    var closeDiscardedPackets: UInt64 = 0
    var highWaterPackets = 0
    var pendingPackets = 0
    var lastContentSegment: UInt64?
    var lastPacketStartSample: UInt64?
}

#if DEBUG
    extension MacSpeechNativeRealtimeFacts {
        func diagnosticReadback(
            transport: NativeVoiceTransportReadback?, sealed: Bool, terminalReason: String?, clearedAt: UInt64?
        ) -> MacSpeechNativeVoiceDiagnosticReadback {
            .init(
                sealed: sealed, terminalReason: terminalReason, transport: transport, captureQueue: captureQueue,
                lastSource: lastSource, lastNonzeroSubmission: lastNonzeroSubmission,
                lastDigitalHandoff: lastDigitalHandoff, lastClearObservedAtNanoseconds: clearedAt
            )
        }
    }

    nonisolated struct MacSpeechNativeVoiceDiagnosticReadback: Encodable, Sendable {
        let sealed: Bool
        let terminalReason: String?
        let physicalPlayback = "UNKNOWN"
        let humanSource = "UNKNOWN"
        let transport: NativeVoiceTransportReadback?
        let captureQueue: MacSpeechNativeCaptureQueueReadback
        let lastSource: NativeVoiceRenderFact?
        let lastNonzeroSubmission: NativeVoiceRenderFact?
        let lastDigitalHandoff: NativeVoiceRenderFact?
        let lastClearObservedAtNanoseconds: UInt64?
    }
#endif

nonisolated extension MacSpeechDeviceRoute {
    init(nativeVoiceDefaults defaults: NativeVoiceGraphSnapshot.Defaults) {
        input = MacSpeechAudioDevice(identifier: String(defaults.input), name: "Core Audio", isAvailable: true)
        output = MacSpeechAudioDevice(identifier: String(defaults.output), name: "Core Audio", isAvailable: true)
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
    static func nativeVoiceCapture(_ graph: NativeVoiceGraphSnapshot, route: MacSpeechDeviceRoute) -> Self {
        .init(
            authorization: .authorized, state: .capturing, isCapturing: true,
            inputDevice: route.input, outputDevice: route.output,
            actualSampleRate: graph.plan.capture.sampleRate, actualChannelCount: graph.plan.capture.channels,
            normalizedOutputFormat: MacSpeechAudioInputFormat.description, generatedFrameCount: 0,
            droppedFrameCount: 0, rejectedStaleFrameCount: 0, queuedFrameCount: 0, latestActivity: 0, lastError: nil
        )
    }
}

nonisolated struct MacSpeechNativePlaybackCounters {
    var chunkCount = 0
    var byteCount = 0
    var pressureWaits = 0
    var outputDevice = MacSpeechAudioDevice.unavailable
}

nonisolated extension MacSpeechAudioOutputHostSnapshot {
    static func nativeVoiceOutput(
        state: MacSpeechAudioOutputHostState, token: UInt64, counters: MacSpeechNativePlaybackCounters,
        started: Bool, error: MacSpeechAudioOutputHostError?
    ) -> Self {
        .init(
            state: state, generation: token, outputDevice: counters.outputDevice,
            providerFormat: MacSpeechPCMOutputFormat.description, localFormat: "Apple VP Source",
            queueCapacity: 1, queueDepth: 0, bufferedDurationMilliseconds: 0, scheduledChunkCount: 0,
            enqueuedChunkCount: counters.chunkCount, enqueuedByteCount: counters.byteCount, playedChunkCount: 0,
            playedByteCount: 0, playbackStartedCount: started ? 1 : 0, playbackCompletedCount: 0,
            underrunCount: 0, pressureWaitCount: counters.pressureWaits, rejectedCallbackCount: 0,
            lastError: error?.rawValue, recentEvents: []
        )
    }
}

nonisolated struct MacSpeechNativePlayback {
    let response: RealtimeBrainEventIdentity
    var lastSequence: UInt64 = 0
    var started = false
    var eosDeadline: UInt64?
}

extension MacSpeechNativeRealtimeSession {
    #if DEBUG
        func nativeVoiceDiagnosticData() async throws -> Data {
            try JSONEncoder().encode(await nativeVoiceDiagnosticReadback())
        }
    #endif

    /// Selected explicitly by the authorized DEBUG foreground route.
    nonisolated static func appleVoiceProcessing() -> MacSpeechNativeRealtimeSession {
        MacSpeechNativeRealtimeSession(makeTransport: { AppleNativeVoiceTransport.macOS() })
    }
}
