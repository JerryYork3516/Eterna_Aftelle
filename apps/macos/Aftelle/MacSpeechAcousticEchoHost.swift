import Foundation
import OSLog

nonisolated enum MacSpeechAudioProcessingMode: String, Sendable, Equatable {
    case webRTCAEC3
    case appleVoiceProcessing
    case halfDuplexFallback
}

nonisolated enum MacSpeechAECFallbackReason: String, Sendable, Equatable {
    case initializationFailed = "initialization_failed"
    case renderProcessingFailed = "render_processing_failed"
    case captureProcessingFailed = "capture_processing_failed"
    case delayInvalid = "delay_invalid"
    case statsUnavailable = "stats_unavailable"
    case fifoOverflow = "fifo_overflow"
    case residualEcho = "residual_echo"
    case sourceAlignmentUnavailable = "source_alignment_unavailable"
    case sourceClassificationUncertain = "source_classification_uncertain"
    case routeRebuild = "route_rebuild"
    case requested = "requested"
}

nonisolated enum MacSpeechAcousticInputClassification: String, Sendable, Equatable {
    case echoOnly = "echo_only"
    case nearEndSpeech = "near_end_speech"
    case doubleTalk = "double_talk"
    case uncertain
}

nonisolated enum MacSpeechSourceGateCloseReason: String, Sendable, Equatable {
    case nonUserHangover = "non_user_hangover"
    case sourceEvidenceReset = "source_evidence_reset"
    case residualEchoProtection = "residual_echo_protection"
    case playbackLifecycle = "playback_lifecycle"
    case routeRebuild = "route_rebuild"
    case hostFallback = "host_fallback"
}

nonisolated struct MacSpeechAECBackendStats: Sendable, Equatable {
    let enabled: Bool
    let active: Bool
    let estimatedDelayMilliseconds: Int
    let erlDecibels: Double
    let erleDecibels: Double
}

nonisolated enum MacSpeechAECBackendError: Error, Sendable, Equatable {
    case createFailed
    case configureFailed
    case renderFailed
    case captureFailed
    case delayFailed
    case resetFailed
    case statsFailed
}

nonisolated protocol MacSpeechAECBackend: AnyObject, Sendable {
    func configure() throws
    func processRender(_ samples: [Float]) throws
    func processCapture(_ samples: [Float]) throws -> [Float]
    func setDelay(milliseconds: Int) throws
    func reset() throws
    func stats() throws -> MacSpeechAECBackendStats
}

nonisolated struct MacSpeechAcousticEchoSnapshot: Sendable, Equatable {
    let mode: MacSpeechAudioProcessingMode
    let enabled: Bool
    let active: Bool
    let sampleRate: Int
    let renderFrameCount: UInt64
    let captureFrameCount: UInt64
    let delayMilliseconds: Int
    let estimatedDelayMilliseconds: Int
    let erlDecibels: Double
    let erleDecibels: Double
    let renderFIFOSampleCount: Int
    let captureFIFOSampleCount: Int
    let renderCaptureSkewFrames: Int64
    let driftTrend: String
    let presentationDelayMilliseconds: Int
    let alignedDelayMilliseconds: Int?
    let renderTimingFrameCount: Int
    let rawCaptureRMS: Double
    let processedCaptureRMS: Double
    let renderCaptureCorrelation: Double
    let residualRenderCorrelation: Double
    let inputClassification: MacSpeechAcousticInputClassification
    let sourceGateOpen: Bool
    let sourceGatePreRollFrameCount: Int
    let echoOnlyFrameCount: UInt64
    let nearEndSpeechFrameCount: UInt64
    let doubleTalkFrameCount: UInt64
    let uncertainFrameCount: UInt64
    let sourceForwardedFrameCount: UInt64
    let sourceSuppressedFrameCount: UInt64
    let sourceTimingCandidateFrameCount: UInt64
    let sourceTimingUnavailableFrameCount: UInt64
    let sourceGateOpenCount: UInt64
    let sourceGateCloseCount: UInt64
    let maximumContinuousSourceForwardedFrameCount: UInt64
    let lastSourceGateCloseReason: MacSpeechSourceGateCloseReason?
    let fallbackCount: UInt64
    let lastFallbackReason: MacSpeechAECFallbackReason?
    let routeResetCount: UInt64
    let fallbackReason: MacSpeechAECFallbackReason?
    let isPlaybackActive: Bool
}

nonisolated final class MacSpeechAcousticEchoHost: @unchecked Sendable {
    static let sampleRate = 48_000
    static let frameSampleCount = 480
    static let frameDurationMilliseconds = 10
    static let maximumDelayMilliseconds = 500
    static let standardFIFOFrameCapacity = 12
    private static let timingHistoryFrameCapacity =
        maximumDelayMilliseconds / frameDurationMilliseconds
    private static let minimumTimingCorrelation = 0.35
    private static let minimumTimingRMS = 0.005
    private static let minimumNearEndRMS = 0.012
    private static let maximumNearEndCorrelation = 0.25
    private static let maximumDoubleTalkResidualCorrelation = 0.25
    private static let requiredSourceGateConfirmationFrames = 3
    private static let maximumSourceGateNonUserHangoverFrames = 20
    private static let sourceGatePreRollFrameCapacity = 15
    private static let sourceGateResetFrameCount = 20
    private static let reliableERLEDecibels = 3.0
    private static let failedERLEDecibels = 1.0
    private static let residualEchoGateResetFrameCount: UInt64 = 5

    private let queue = DispatchQueue(
        label: "com.eterna.aftelle.speech-aec-processing"
    )
    private let backend: (any MacSpeechAECBackend)?
    private let fifoSampleCapacity: Int
    private let logger = Logger(
        subsystem: "com.eterna.aftelle",
        category: "speech-aec"
    )
    private let requestedMode: MacSpeechAudioProcessingMode
    private var mode: MacSpeechAudioProcessingMode
    private var renderFIFO: [Float] = []
    private var captureFIFO: [Float] = []
    private var renderRemainderHostTimeNanoseconds: UInt64?
    private var captureRemainderHostTimeNanoseconds: UInt64?
    private var renderTimingHistory: [TimedRenderFrame] = []
    private var renderFrameCount: UInt64 = 0
    private var captureFrameCount: UInt64 = 0
    private var lastLoggedCaptureFrameCount: UInt64 = 0
    private var delayMilliseconds = 0
    private var presentationDelayMilliseconds = 0
    private var alignedDelayMilliseconds: Double?
    private var captureProcessingMilliseconds = 0.0
    private var rawCaptureRMS = 0.0
    private var processedCaptureRMS = 0.0
    private var renderCaptureCorrelation = 0.0
    private var residualRenderCorrelation = 0.0
    private var inputClassification: MacSpeechAcousticInputClassification =
        .uncertain
    private var sourceGateOpen = false
    private var sourceGatePreRoll: [[Float]] = []
    private var sourceGateConfirmationFrameCount = 0
    private var sourceGateNonUserHangoverFrameCount = 0
    private var consecutiveSourceAlignmentUnavailableFrameCount = 0
    private var consecutiveSourceUncertainFrameCount = 0
    private var pendingSourceGateReset = false
    private var echoOnlyFrameCount: UInt64 = 0
    private var nearEndSpeechFrameCount: UInt64 = 0
    private var doubleTalkFrameCount: UInt64 = 0
    private var uncertainFrameCount: UInt64 = 0
    private var sourceForwardedFrameCount: UInt64 = 0
    private var sourceSuppressedFrameCount: UInt64 = 0
    private var sourceTimingCandidateFrameCount: UInt64 = 0
    private var sourceTimingUnavailableFrameCount: UInt64 = 0
    private var sourceGateOpenCount: UInt64 = 0
    private var sourceGateCloseCount: UInt64 = 0
    private var currentContinuousSourceForwardedFrameCount: UInt64 = 0
    private var maximumContinuousSourceForwardedFrameCount: UInt64 = 0
    private var lastSourceGateCloseReason: MacSpeechSourceGateCloseReason?
    private var fallbackCount: UInt64 = 0
    private var lastFallbackReason: MacSpeechAECFallbackReason?
    private var lastDriftSkew: Int64 = 0
    private var driftTrend = "stable"
    private var routeResetCount: UInt64 = 0
    private var fallbackReason: MacSpeechAECFallbackReason?
    private var isPlaybackActive = false
    private var isRouteRebuilding = false
    private var hasReliableEchoCancellation = false
    private var poorResidualEchoFrameCount: UInt64 = 0
    private var backendStats = MacSpeechAECBackendStats(
        enabled: false,
        active: false,
        estimatedDelayMilliseconds: 0,
        erlDecibels: 0,
        erleDecibels: 0
    )

    init(
        mode: MacSpeechAudioProcessingMode,
        backend: (any MacSpeechAECBackend)? = nil,
        fifoFrameCapacity: Int = standardFIFOFrameCapacity
    ) {
        precondition(fifoFrameCapacity > 0)
        requestedMode = mode
        self.mode = mode
        self.backend = backend
        fifoSampleCapacity = fifoFrameCapacity * Self.frameSampleCount
        renderFIFO.reserveCapacity(fifoSampleCapacity)
        captureFIFO.reserveCapacity(fifoSampleCapacity)
        renderTimingHistory.reserveCapacity(Self.timingHistoryFrameCapacity)
        sourceGatePreRoll.reserveCapacity(
            Self.sourceGatePreRollFrameCapacity
        )
    }

    @discardableResult
    func configure() -> MacSpeechAudioProcessingMode {
        queue.sync {
            clearFIFOs()
            renderFrameCount = 0
            captureFrameCount = 0
            lastLoggedCaptureFrameCount = 0
            resetTimingState()
            resetDiagnosticCounters()
            isRouteRebuilding = false
            lastDriftSkew = 0
            driftTrend = "stable"
            fallbackReason = nil
            hasReliableEchoCancellation = false
            poorResidualEchoFrameCount = 0
            switch requestedMode {
            case .webRTCAEC3:
                guard let backend else {
                    enterFallback(.initializationFailed)
                    return mode
                }
                do {
                    try backend.configure()
                    mode = .webRTCAEC3
                    backendStats = try backend.stats()
                    logConfiguration()
                } catch {
                    enterFallback(.initializationFailed)
                }
            case .appleVoiceProcessing:
                mode = .appleVoiceProcessing
                backendStats = disabledStats()
                logConfiguration()
            case .halfDuplexFallback:
                enterFallback(.requested)
            }
            return mode
        }
    }

    func processRender(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64? = nil
    ) {
        guard !samples.isEmpty else { return }
        queue.sync {
            guard mode == .webRTCAEC3, let backend else { return }
            do {
                try processFrames(
                    samples,
                    hostTimeNanoseconds: hostTimeNanoseconds,
                    remainder: &renderFIFO,
                    remainderHostTimeNanoseconds:
                        &renderRemainderHostTimeNanoseconds
                ) { frame, frameHostTimeNanoseconds in
                    try backend.processRender(frame)
                    renderFrameCount &+= 1
                    if isPlaybackActive,
                       let frameHostTimeNanoseconds {
                        appendRenderTimingFrame(
                            frame,
                            hostTimeNanoseconds: frameHostTimeNanoseconds
                        )
                    }
                }
            } catch FrameProcessingError.fifoOverflow {
                enterFallback(.fifoOverflow)
                return
            } catch {
                enterFallback(.renderProcessingFailed)
                return
            }
            refreshBackendStats()
            updateDrift()
        }
    }

    func renderConversionFailed() {
        queue.sync { enterFallback(.renderProcessingFailed) }
    }

    func processCapture(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64? = nil
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        return queue.sync {
            if mode == .halfDuplexFallback {
                captureFIFO.removeAll(keepingCapacity: true)
                return isPlaybackActive || isRouteRebuilding ? [] : samples
            }
            guard mode == .webRTCAEC3, let backend else {
                return samples
            }
            var output: [Float] = []
            output.reserveCapacity(samples.count)
            let captureFrameCountBeforeProcessing = captureFrameCount
            do {
                try processFrames(
                    samples,
                    hostTimeNanoseconds: hostTimeNanoseconds,
                    remainder: &captureFIFO,
                    remainderHostTimeNanoseconds:
                        &captureRemainderHostTimeNanoseconds
                ) { frame, frameHostTimeNanoseconds in
                    let timingMatch = timingMatch(
                        for: frame,
                        captureHostTimeNanoseconds: frameHostTimeNanoseconds
                    )
                    if let timingMatch,
                       timingMatch.correlation
                           >= Self.minimumTimingCorrelation {
                        updateAlignedDelay(timingMatch.delayMilliseconds)
                    }
                    let processedFrame = try backend.processCapture(frame)
                    updateSignalDiagnostics(
                        rawCapture: frame,
                        processedCapture: processedFrame,
                        timingMatch: timingMatch
                    )
                    output.append(contentsOf: gatedCaptureFrame(
                        processedFrame,
                        timingMatch: timingMatch
                    ))
                    captureFrameCount &+= 1
                }
            } catch FrameProcessingError.fifoOverflow {
                enterFallback(.fifoOverflow)
                return isPlaybackActive || isRouteRebuilding ? [] : samples
            } catch {
                enterFallback(.captureProcessingFailed)
                return isPlaybackActive || isRouteRebuilding ? [] : samples
            }
            refreshBackendStats()
            applyResidualEchoGateProtection(
                processedFrameCount:
                    captureFrameCount - captureFrameCountBeforeProcessing
            )
            updateDrift()
            return mode == .halfDuplexFallback
                    && (isPlaybackActive || isRouteRebuilding)
                ? [] : output
        }
    }

    func updateDelay(
        outputPresentationLatencySeconds: Double,
        capturePresentationLatencySeconds: Double
    ) {
        queue.sync {
            guard outputPresentationLatencySeconds.isFinite,
                  capturePresentationLatencySeconds.isFinite else {
                enterFallback(.delayInvalid)
                return
            }
            let totalSeconds = max(0, outputPresentationLatencySeconds)
                + max(0, capturePresentationLatencySeconds)
            presentationDelayMilliseconds = Int(
                (totalSeconds * 1_000).rounded()
            )
            let measuredMilliseconds = Int((
                Double(presentationDelayMilliseconds)
                    + max(0, captureProcessingMilliseconds)
            ).rounded())
            guard measuredMilliseconds <= Self.maximumDelayMilliseconds else {
                enterFallback(.delayInvalid)
                return
            }
            if alignedDelayMilliseconds == nil {
                applyDelay(measuredMilliseconds)
            }
        }
    }

    func recordCaptureProcessingDuration(nanoseconds: UInt64) {
        queue.sync {
            captureProcessingMilliseconds = Double(nanoseconds) / 1_000_000
        }
    }

    func playbackStarted() {
        queue.sync {
            isPlaybackActive = true
            clearTimingHistory()
            alignedDelayMilliseconds = nil
            resetSignalDiagnostics()
            resetSourceGate(closeReason: .playbackLifecycle)
            poorResidualEchoFrameCount = 0
        }
    }

    func playbackCompleted() {
        queue.sync {
            isPlaybackActive = false
            captureFIFO.removeAll(keepingCapacity: true)
            captureRemainderHostTimeNanoseconds = nil
            clearTimingHistory()
            resetSourceGate(closeReason: .playbackLifecycle)
            poorResidualEchoFrameCount = 0
            guard mode == .halfDuplexFallback,
                  fallbackReason != .routeRebuild,
                  requestedMode == .webRTCAEC3,
                  let backend else { return }
            do {
                try backend.reset()
                try backend.setDelay(milliseconds: delayMilliseconds)
                mode = .webRTCAEC3
                fallbackReason = nil
                hasReliableEchoCancellation = false
                backendStats = try backend.stats()
                logConfiguration()
            } catch {
                enterFallback(.initializationFailed)
            }
        }
    }

    func playbackStopped() {
        queue.sync {
            isPlaybackActive = false
            captureFIFO.removeAll(keepingCapacity: true)
            captureRemainderHostTimeNanoseconds = nil
            clearTimingHistory()
            resetSourceGate(closeReason: .playbackLifecycle)
            poorResidualEchoFrameCount = 0
        }
    }

    func routeWillRebuild() {
        queue.sync {
            routeResetCount &+= 1
            isRouteRebuilding = true
            hasReliableEchoCancellation = false
            poorResidualEchoFrameCount = 0
            clearFIFOs()
            resetTimingState(closeReason: .routeRebuild)
            if requestedMode == .webRTCAEC3 {
                enterFallback(.routeRebuild)
            }
            logger.notice(
                "AEC route reset count=\(self.routeResetCount, privacy: .public) mode=\(self.mode.rawValue, privacy: .public)"
            )
        }
    }

    @discardableResult
    func routeDidRebuild() -> MacSpeechAudioProcessingMode {
        queue.sync {
            clearFIFOs()
            isRouteRebuilding = false
            guard requestedMode == .webRTCAEC3, let backend else {
                mode = requestedMode
                return mode
            }
            do {
                try backend.reset()
                try backend.configure()
                try backend.setDelay(milliseconds: delayMilliseconds)
                mode = .webRTCAEC3
                fallbackReason = nil
                hasReliableEchoCancellation = false
                backendStats = try backend.stats()
                logConfiguration()
            } catch {
                enterFallback(.initializationFailed)
            }
            return mode
        }
    }

    func snapshot() -> MacSpeechAcousticEchoSnapshot {
        queue.sync { makeSnapshot() }
    }

    func resetDiagnostics() {
        queue.sync { resetDiagnosticCounters() }
    }

    private enum FrameProcessingError: Error {
        case fifoOverflow
    }

    private struct TimedRenderFrame {
        let hostTimeNanoseconds: UInt64
        let samples: [Float]
        let rms: Double
    }

    private struct TimingMatch {
        let renderSamples: [Float]
        let delayMilliseconds: Double
        let correlation: Double
    }

    private func processFrames(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64?,
        remainder: inout [Float],
        remainderHostTimeNanoseconds: inout UInt64?,
        process: ([Float], UInt64?) throws -> Void
    ) throws {
        guard remainder.count < Self.frameSampleCount,
              remainder.count <= fifoSampleCapacity else {
            throw FrameProcessingError.fifoOverflow
        }

        var offset = 0
        if !remainder.isEmpty {
            let needed = Self.frameSampleCount - remainder.count
            let consumed = min(needed, samples.count)
            remainder.append(contentsOf: samples.prefix(consumed))
            offset += consumed
            if remainder.count == Self.frameSampleCount {
                try process(remainder, remainderHostTimeNanoseconds)
                remainder.removeAll(keepingCapacity: true)
                remainderHostTimeNanoseconds = nil
            }
        }

        while samples.count - offset >= Self.frameSampleCount {
            let end = offset + Self.frameSampleCount
            try process(
                Array(samples[offset ..< end]),
                advancedHostTime(
                    hostTimeNanoseconds,
                    sampleOffset: offset
                )
            )
            offset = end
        }

        if offset < samples.count {
            if remainder.isEmpty {
                remainderHostTimeNanoseconds = advancedHostTime(
                    hostTimeNanoseconds,
                    sampleOffset: offset
                )
            }
            remainder.append(contentsOf: samples[offset...])
        }
        guard remainder.count < Self.frameSampleCount,
              remainder.count <= fifoSampleCapacity else {
            remainder.removeAll(keepingCapacity: true)
            remainderHostTimeNanoseconds = nil
            throw FrameProcessingError.fifoOverflow
        }
    }

    private func advancedHostTime(
        _ hostTimeNanoseconds: UInt64?,
        sampleOffset: Int
    ) -> UInt64? {
        guard let hostTimeNanoseconds else { return nil }
        let offsetNanoseconds = UInt64((
            Double(sampleOffset) * 1_000_000_000
                / Double(Self.sampleRate)
        ).rounded())
        return hostTimeNanoseconds &+ offsetNanoseconds
    }

    private func appendRenderTimingFrame(
        _ samples: [Float],
        hostTimeNanoseconds: UInt64
    ) {
        if renderTimingHistory.count == Self.timingHistoryFrameCapacity {
            renderTimingHistory.removeFirst()
        }
        renderTimingHistory.append(TimedRenderFrame(
            hostTimeNanoseconds: hostTimeNanoseconds,
            samples: samples,
            rms: signalRMS(samples)
        ))
    }

    private func timingMatch(
        for captureSamples: [Float],
        captureHostTimeNanoseconds: UInt64?
    ) -> TimingMatch? {
        guard isPlaybackActive,
              let captureHostTimeNanoseconds,
              signalRMS(captureSamples) >= Self.minimumTimingRMS else {
            return nil
        }
        var bestMatch: TimingMatch?
        for renderFrame in renderTimingHistory {
            guard captureHostTimeNanoseconds >= renderFrame.hostTimeNanoseconds
            else { continue }
            let delayMilliseconds = Double(
                captureHostTimeNanoseconds - renderFrame.hostTimeNanoseconds
            ) / 1_000_000
            guard delayMilliseconds <= Double(Self.maximumDelayMilliseconds),
                  renderFrame.rms >= Self.minimumTimingRMS else {
                continue
            }
            let correlation = normalizedCorrelation(
                captureSamples,
                renderFrame.samples
            )
            if bestMatch == nil
                || correlation > (bestMatch?.correlation ?? 0) {
                bestMatch = TimingMatch(
                    renderSamples: renderFrame.samples,
                    delayMilliseconds: delayMilliseconds,
                    correlation: correlation
                )
            }
        }
        return bestMatch
    }

    private func gatedCaptureFrame(
        _ processedFrame: [Float],
        timingMatch: TimingMatch?
    ) -> [Float] {
        guard isPlaybackActive else {
            inputClassification = .nearEndSpeech
            resetSourceGate(
                keepingClassification: true,
                closeReason: .playbackLifecycle
            )
            return processedFrame
        }

        inputClassification = classifyCapture(
            processedFrame,
            timingMatch: timingMatch
        )
        recordSourceClassification(timingMatch: timingMatch)
        if pendingSourceGateReset {
            return suppressCaptureFrameAndCloseGate(
                reason: .sourceEvidenceReset
            )
        }
        if sourceGateOpen {
            return captureWhileGateIsOpen(processedFrame)
        }

        switch inputClassification {
        case .echoOnly:
            return suppressClosedGateFrame()
        case .uncertain:
            return suppressClosedGateFrame()
        case .nearEndSpeech, .doubleTalk:
            appendSourceGatePreRoll(processedFrame)
            sourceGateConfirmationFrameCount += 1
            guard sourceGateConfirmationFrameCount
                    >= Self.requiredSourceGateConfirmationFrames else {
                return []
            }
            sourceGateOpen = true
            sourceGateOpenCount &+= 1
            sourceGateConfirmationFrameCount = 0
            sourceGateNonUserHangoverFrameCount = 0
            return drainSourceGatePreRoll()
        }
    }

    private func classifyCapture(
        _ processedFrame: [Float],
        timingMatch: TimingMatch?
    ) -> MacSpeechAcousticInputClassification {
        guard let timingMatch else { return .uncertain }
        let cleanRMS = signalRMS(processedFrame)
        guard cleanRMS >= Self.minimumNearEndRMS else {
            return timingMatch.correlation
                    >= Self.minimumTimingCorrelation
                ? .echoOnly : .uncertain
        }

        let residualCorrelation = normalizedCorrelation(
            processedFrame,
            timingMatch.renderSamples
        )
        if timingMatch.correlation >= Self.minimumTimingCorrelation {
            return residualCorrelation
                    <= Self.maximumDoubleTalkResidualCorrelation
                ? .doubleTalk : .echoOnly
        }
        if timingMatch.correlation <= Self.maximumNearEndCorrelation,
           residualCorrelation <= Self.maximumNearEndCorrelation {
            return .nearEndSpeech
        }
        return .uncertain
    }

    private func captureWhileGateIsOpen(_ processedFrame: [Float]) -> [Float] {
        switch inputClassification {
        case .nearEndSpeech, .doubleTalk:
            sourceGateNonUserHangoverFrameCount = 0
            recordForwardedSourceFrames(1)
            return processedFrame
        case .uncertain:
            sourceGateNonUserHangoverFrameCount += 1
            if sourceGateNonUserHangoverFrameCount
                >= Self.maximumSourceGateNonUserHangoverFrames {
                return suppressCaptureFrameAndCloseGate(
                    reason: .nonUserHangover
                )
            }
            guard signalRMS(processedFrame) >= Self.minimumNearEndRMS else {
                recordSuppressedSourceFrames(1)
                return silenceFrames(1)
            }
            recordForwardedSourceFrames(1)
            return processedFrame
        case .echoOnly:
            sourceGateNonUserHangoverFrameCount += 1
            if sourceGateNonUserHangoverFrameCount
                >= Self.maximumSourceGateNonUserHangoverFrames {
                return suppressCaptureFrameAndCloseGate(
                    reason: .nonUserHangover
                )
            }
            recordSuppressedSourceFrames(1)
            return silenceFrames(1)
        }
    }

    private func recordSourceClassification(timingMatch: TimingMatch?) {
        switch inputClassification {
        case .echoOnly:
            echoOnlyFrameCount &+= 1
        case .nearEndSpeech:
            nearEndSpeechFrameCount &+= 1
        case .doubleTalk:
            doubleTalkFrameCount &+= 1
        case .uncertain:
            uncertainFrameCount &+= 1
        }

        if timingMatch == nil,
           rawCaptureRMS >= Self.minimumNearEndRMS {
            sourceTimingUnavailableFrameCount &+= 1
            consecutiveSourceAlignmentUnavailableFrameCount += 1
            consecutiveSourceUncertainFrameCount = 0
            if consecutiveSourceAlignmentUnavailableFrameCount
                >= Self.sourceGateResetFrameCount {
                pendingSourceGateReset = true
            }
            return
        }

        consecutiveSourceAlignmentUnavailableFrameCount = 0
        if timingMatch != nil {
            sourceTimingCandidateFrameCount &+= 1
        }
        if inputClassification == .uncertain,
           rawCaptureRMS >= Self.minimumNearEndRMS {
            consecutiveSourceUncertainFrameCount += 1
            if consecutiveSourceUncertainFrameCount
                >= Self.sourceGateResetFrameCount {
                pendingSourceGateReset = true
            }
        } else {
            consecutiveSourceUncertainFrameCount = 0
        }
    }

    private func appendSourceGatePreRoll(_ frame: [Float]) {
        if sourceGatePreRoll.count
            == Self.sourceGatePreRollFrameCapacity {
            sourceGatePreRoll.removeFirst()
            recordSuppressedSourceFrames(1)
        }
        sourceGatePreRoll.append(frame)
    }

    private func suppressClosedGateFrame() -> [Float] {
        let suppressedFrameCount = sourceGatePreRoll.count + 1
        sourceGatePreRoll.removeAll(keepingCapacity: true)
        sourceGateConfirmationFrameCount = 0
        recordSuppressedSourceFrames(suppressedFrameCount)
        return silenceFrames(suppressedFrameCount)
    }

    private func suppressCaptureFrameAndCloseGate(
        reason: MacSpeechSourceGateCloseReason
    ) -> [Float] {
        let suppressedFrameCount = sourceGatePreRoll.count + 1
        resetSourceGate(
            keepingClassification: true,
            closeReason: reason
        )
        recordSuppressedSourceFrames(1)
        return silenceFrames(suppressedFrameCount)
    }

    private func silenceFrames(_ frameCount: Int) -> [Float] {
        [Float](
            repeating: 0,
            count: frameCount * Self.frameSampleCount
        )
    }

    private func recordForwardedSourceFrames(_ frameCount: Int) {
        let count = UInt64(frameCount)
        sourceForwardedFrameCount &+= count
        currentContinuousSourceForwardedFrameCount &+= count
        maximumContinuousSourceForwardedFrameCount = max(
            maximumContinuousSourceForwardedFrameCount,
            currentContinuousSourceForwardedFrameCount
        )
    }

    private func recordSuppressedSourceFrames(_ frameCount: Int) {
        sourceSuppressedFrameCount &+= UInt64(frameCount)
        currentContinuousSourceForwardedFrameCount = 0
    }

    private func drainSourceGatePreRoll() -> [Float] {
        let output = sourceGatePreRoll.flatMap { $0 }
        recordForwardedSourceFrames(sourceGatePreRoll.count)
        sourceGatePreRoll.removeAll(keepingCapacity: true)
        return output
    }

    private func updateAlignedDelay(_ contentDelayMilliseconds: Double) {
        let measuredDelay = max(
            contentDelayMilliseconds,
            Double(presentationDelayMilliseconds)
        ) + max(0, captureProcessingMilliseconds)
        guard measuredDelay.isFinite,
              measuredDelay <= Double(Self.maximumDelayMilliseconds) else {
            return
        }
        let smoothedDelay = alignedDelayMilliseconds.map {
            $0 * 0.8 + measuredDelay * 0.2
        } ?? measuredDelay
        alignedDelayMilliseconds = smoothedDelay
        applyDelay(Int(smoothedDelay.rounded()))
    }

    private func applyDelay(_ milliseconds: Int) {
        guard milliseconds >= 0,
              milliseconds <= Self.maximumDelayMilliseconds else {
            enterFallback(.delayInvalid)
            return
        }
        guard delayMilliseconds != milliseconds else { return }
        delayMilliseconds = milliseconds
        guard mode == .webRTCAEC3, let backend else { return }
        do {
            try backend.setDelay(milliseconds: milliseconds)
        } catch {
            enterFallback(.delayInvalid)
        }
    }

    private func updateSignalDiagnostics(
        rawCapture: [Float],
        processedCapture: [Float],
        timingMatch: TimingMatch?
    ) {
        rawCaptureRMS = signalRMS(rawCapture)
        processedCaptureRMS = signalRMS(processedCapture)
        if let timingMatch {
            renderCaptureCorrelation = timingMatch.correlation
            residualRenderCorrelation = normalizedCorrelation(
                processedCapture,
                timingMatch.renderSamples
            )
        }
    }

    private func signalRMS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { partial, sample in
            let value = Double(sample.isFinite ? sample : 0)
            return partial + value * value
        }
        return sqrt(sum / Double(samples.count))
    }

    private func normalizedCorrelation(
        _ first: [Float],
        _ second: [Float]
    ) -> Double {
        guard first.count == second.count, !first.isEmpty else { return 0 }
        let firstMean = first.reduce(0.0) { $0 + Double($1) }
            / Double(first.count)
        let secondMean = second.reduce(0.0) { $0 + Double($1) }
            / Double(second.count)
        var covariance = 0.0
        var firstEnergy = 0.0
        var secondEnergy = 0.0
        for index in first.indices {
            let firstValue = Double(first[index]) - firstMean
            let secondValue = Double(second[index]) - secondMean
            covariance += firstValue * secondValue
            firstEnergy += firstValue * firstValue
            secondEnergy += secondValue * secondValue
        }
        guard firstEnergy > 0, secondEnergy > 0 else { return 0 }
        return min(abs(covariance / sqrt(firstEnergy * secondEnergy)), 1)
    }

    private func updateDrift() {
        let skew = Int64(renderFrameCount) - Int64(captureFrameCount)
        if skew > lastDriftSkew {
            driftTrend = "render_ahead"
        } else if skew < lastDriftSkew {
            driftTrend = "capture_ahead"
        } else {
            driftTrend = "stable"
        }
        lastDriftSkew = skew
        let shouldLogInitialState = lastLoggedCaptureFrameCount == 0
            && captureFrameCount >= 10
        let shouldLogPeriodicState = lastLoggedCaptureFrameCount > 0
            && captureFrameCount >= lastLoggedCaptureFrameCount + 100
        if shouldLogInitialState || shouldLogPeriodicState {
            lastLoggedCaptureFrameCount = captureFrameCount
            logger.info(
                "AEC mode=\(self.mode.rawValue, privacy: .public) enabled=\(self.backendStats.enabled, privacy: .public) active=\(self.backendStats.active, privacy: .public) frames=\(self.renderFrameCount, privacy: .public)/\(self.captureFrameCount, privacy: .public) delay_ms=\(self.delayMilliseconds, privacy: .public) presentation_ms=\(self.presentationDelayMilliseconds, privacy: .public) aligned_ms=\(self.alignedDelayMilliseconds ?? -1, privacy: .public) estimated_ms=\(self.backendStats.estimatedDelayMilliseconds, privacy: .public) erl=\(self.backendStats.erlDecibels, privacy: .public) erle=\(self.backendStats.erleDecibels, privacy: .public) raw_rms=\(self.rawCaptureRMS, privacy: .public) clean_rms=\(self.processedCaptureRMS, privacy: .public) correlation=\(self.renderCaptureCorrelation, privacy: .public) residual_correlation=\(self.residualRenderCorrelation, privacy: .public) source=\(self.inputClassification.rawValue, privacy: .public) source_gate=\(self.sourceGateOpen, privacy: .public) source_forwarded=\(self.sourceForwardedFrameCount, privacy: .public) source_suppressed=\(self.sourceSuppressedFrameCount, privacy: .public) source_max_run=\(self.maximumContinuousSourceForwardedFrameCount, privacy: .public) source_close=\(self.lastSourceGateCloseReason?.rawValue ?? "-", privacy: .public) source_timing=\(self.sourceTimingCandidateFrameCount, privacy: .public)/\(self.sourceTimingUnavailableFrameCount, privacy: .public) preroll_frames=\(self.sourceGatePreRoll.count, privacy: .public) timing_frames=\(self.renderTimingHistory.count, privacy: .public) fifo=\(self.renderFIFO.count, privacy: .public)/\(self.captureFIFO.count, privacy: .public) drift=\(self.driftTrend, privacy: .public)"
            )
        }
    }

    private func refreshBackendStats() {
        guard let backend else { return }
        do {
            backendStats = try backend.stats()
        } catch {
            enterFallback(.statsUnavailable)
        }
    }

    private func applyResidualEchoGateProtection(
        processedFrameCount: UInt64
    ) {
        guard processedFrameCount > 0,
              isPlaybackActive,
              mode == .webRTCAEC3,
              backendStats.active,
              backendStats.erleDecibels.isFinite else {
            poorResidualEchoFrameCount = 0
            return
        }
        if backendStats.erleDecibels >= Self.reliableERLEDecibels {
            hasReliableEchoCancellation = true
            poorResidualEchoFrameCount = 0
            return
        }
        guard hasReliableEchoCancellation,
              backendStats.erleDecibels < Self.failedERLEDecibels else {
            poorResidualEchoFrameCount = 0
            return
        }
        guard inputClassification == .echoOnly
                || inputClassification == .uncertain else {
            poorResidualEchoFrameCount = 0
            return
        }
        poorResidualEchoFrameCount &+= processedFrameCount
        if poorResidualEchoFrameCount
            >= Self.residualEchoGateResetFrameCount {
            resetSourceGate(
                keepingClassification: true,
                closeReason: .residualEchoProtection
            )
            poorResidualEchoFrameCount = 0
        }
    }

    private func enterFallback(_ reason: MacSpeechAECFallbackReason) {
        if mode != .halfDuplexFallback || fallbackReason != reason {
            fallbackCount &+= 1
        }
        lastFallbackReason = reason
        mode = .halfDuplexFallback
        fallbackReason = reason
        backendStats = disabledStats()
        poorResidualEchoFrameCount = 0
        clearFIFOs()
        resetSourceGate(closeReason: .hostFallback)
        logger.error(
            "AEC fallback reason=\(reason.rawValue, privacy: .public) delay_ms=\(self.delayMilliseconds, privacy: .public)"
        )
    }

    private func clearFIFOs() {
        renderFIFO.removeAll(keepingCapacity: true)
        captureFIFO.removeAll(keepingCapacity: true)
        renderRemainderHostTimeNanoseconds = nil
        captureRemainderHostTimeNanoseconds = nil
    }

    private func clearTimingHistory() {
        renderTimingHistory.removeAll(keepingCapacity: true)
    }

    private func resetSignalDiagnostics() {
        rawCaptureRMS = 0
        processedCaptureRMS = 0
        renderCaptureCorrelation = 0
        residualRenderCorrelation = 0
    }

    private func resetSourceGate(
        keepingClassification: Bool = false,
        closeReason: MacSpeechSourceGateCloseReason? = nil
    ) {
        if sourceGateOpen {
            sourceGateCloseCount &+= 1
            lastSourceGateCloseReason = closeReason
        }
        recordSuppressedSourceFrames(sourceGatePreRoll.count)
        sourceGateOpen = false
        sourceGatePreRoll.removeAll(keepingCapacity: true)
        sourceGateConfirmationFrameCount = 0
        sourceGateNonUserHangoverFrameCount = 0
        consecutiveSourceAlignmentUnavailableFrameCount = 0
        consecutiveSourceUncertainFrameCount = 0
        pendingSourceGateReset = false
        if !keepingClassification {
            inputClassification = .uncertain
        }
    }

    private func resetDiagnosticCounters() {
        echoOnlyFrameCount = 0
        nearEndSpeechFrameCount = 0
        doubleTalkFrameCount = 0
        uncertainFrameCount = 0
        sourceForwardedFrameCount = 0
        sourceSuppressedFrameCount = 0
        sourceTimingCandidateFrameCount = 0
        sourceTimingUnavailableFrameCount = 0
        sourceGateOpenCount = 0
        sourceGateCloseCount = 0
        currentContinuousSourceForwardedFrameCount = 0
        maximumContinuousSourceForwardedFrameCount = 0
        lastSourceGateCloseReason = nil
        fallbackCount = 0
        lastFallbackReason = nil
        consecutiveSourceAlignmentUnavailableFrameCount = 0
        consecutiveSourceUncertainFrameCount = 0
        pendingSourceGateReset = false
    }

    private func resetTimingState(
        closeReason: MacSpeechSourceGateCloseReason? = nil
    ) {
        clearTimingHistory()
        delayMilliseconds = 0
        presentationDelayMilliseconds = 0
        alignedDelayMilliseconds = nil
        resetSignalDiagnostics()
        resetSourceGate(closeReason: closeReason)
    }

    private func disabledStats() -> MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(
            enabled: false,
            active: false,
            estimatedDelayMilliseconds: 0,
            erlDecibels: 0,
            erleDecibels: 0
        )
    }

    private func makeSnapshot() -> MacSpeechAcousticEchoSnapshot {
        MacSpeechAcousticEchoSnapshot(
            mode: mode,
            enabled: backendStats.enabled,
            active: backendStats.active,
            sampleRate: Self.sampleRate,
            renderFrameCount: renderFrameCount,
            captureFrameCount: captureFrameCount,
            delayMilliseconds: delayMilliseconds,
            estimatedDelayMilliseconds:
                backendStats.estimatedDelayMilliseconds,
            erlDecibels: backendStats.erlDecibels,
            erleDecibels: backendStats.erleDecibels,
            renderFIFOSampleCount: renderFIFO.count,
            captureFIFOSampleCount: captureFIFO.count,
            renderCaptureSkewFrames:
                Int64(renderFrameCount) - Int64(captureFrameCount),
            driftTrend: driftTrend,
            presentationDelayMilliseconds: presentationDelayMilliseconds,
            alignedDelayMilliseconds: alignedDelayMilliseconds.map {
                Int($0.rounded())
            },
            renderTimingFrameCount: renderTimingHistory.count,
            rawCaptureRMS: rawCaptureRMS,
            processedCaptureRMS: processedCaptureRMS,
            renderCaptureCorrelation: renderCaptureCorrelation,
            residualRenderCorrelation: residualRenderCorrelation,
            inputClassification: inputClassification,
            sourceGateOpen: sourceGateOpen,
            sourceGatePreRollFrameCount: sourceGatePreRoll.count,
            echoOnlyFrameCount: echoOnlyFrameCount,
            nearEndSpeechFrameCount: nearEndSpeechFrameCount,
            doubleTalkFrameCount: doubleTalkFrameCount,
            uncertainFrameCount: uncertainFrameCount,
            sourceForwardedFrameCount: sourceForwardedFrameCount,
            sourceSuppressedFrameCount: sourceSuppressedFrameCount,
            sourceTimingCandidateFrameCount: sourceTimingCandidateFrameCount,
            sourceTimingUnavailableFrameCount:
                sourceTimingUnavailableFrameCount,
            sourceGateOpenCount: sourceGateOpenCount,
            sourceGateCloseCount: sourceGateCloseCount,
            maximumContinuousSourceForwardedFrameCount:
                maximumContinuousSourceForwardedFrameCount,
            lastSourceGateCloseReason: lastSourceGateCloseReason,
            fallbackCount: fallbackCount,
            lastFallbackReason: lastFallbackReason,
            routeResetCount: routeResetCount,
            fallbackReason: fallbackReason,
            isPlaybackActive: isPlaybackActive
        )
    }

    private func logConfiguration() {
        logger.notice(
            "AEC configured mode=\(self.mode.rawValue, privacy: .public) enabled=\(self.backendStats.enabled, privacy: .public) sample_rate=\(Self.sampleRate, privacy: .public) frame_samples=\(Self.frameSampleCount, privacy: .public)"
        )
    }
}
