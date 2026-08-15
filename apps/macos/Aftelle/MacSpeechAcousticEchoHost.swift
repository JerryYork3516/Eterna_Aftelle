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
    case routeRebuild = "route_rebuild"
    case requested = "requested"
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
    private var renderFrameCount: UInt64 = 0
    private var captureFrameCount: UInt64 = 0
    private var delayMilliseconds = 0
    private var captureProcessingMilliseconds = 0.0
    private var lastDriftSkew: Int64 = 0
    private var driftTrend = "stable"
    private var routeResetCount: UInt64 = 0
    private var fallbackReason: MacSpeechAECFallbackReason?
    private var isPlaybackActive = false
    private var isRouteRebuilding = false
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
    }

    @discardableResult
    func configure() -> MacSpeechAudioProcessingMode {
        queue.sync {
            clearFIFOs()
            renderFrameCount = 0
            captureFrameCount = 0
            isRouteRebuilding = false
            lastDriftSkew = 0
            driftTrend = "stable"
            fallbackReason = nil
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

    func processRender(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        queue.sync {
            guard mode == .webRTCAEC3, let backend else { return }
            guard appendBounded(samples, to: &renderFIFO) else {
                enterFallback(.fifoOverflow)
                return
            }
            while renderFIFO.count >= Self.frameSampleCount {
                let frame = takeFrame(from: &renderFIFO)
                do {
                    try backend.processRender(frame)
                    renderFrameCount &+= 1
                } catch {
                    enterFallback(.renderProcessingFailed)
                    return
                }
            }
            refreshBackendStats()
            updateDrift()
        }
    }

    func processCapture(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        return queue.sync {
            if mode == .halfDuplexFallback {
                captureFIFO.removeAll(keepingCapacity: true)
                return isPlaybackActive || isRouteRebuilding ? [] : samples
            }
            guard mode == .webRTCAEC3, let backend else {
                return samples
            }
            guard appendBounded(samples, to: &captureFIFO) else {
                enterFallback(.fifoOverflow)
                return isPlaybackActive || isRouteRebuilding ? [] : samples
            }
            var output: [Float] = []
            output.reserveCapacity(captureFIFO.count)
            while captureFIFO.count >= Self.frameSampleCount {
                let frame = takeFrame(from: &captureFIFO)
                do {
                    output.append(contentsOf: try backend.processCapture(frame))
                    captureFrameCount &+= 1
                } catch {
                    enterFallback(.captureProcessingFailed)
                    return isPlaybackActive || isRouteRebuilding ? [] : samples
                }
            }
            refreshBackendStats()
            updateDrift()
            return mode == .halfDuplexFallback
                    && (isPlaybackActive || isRouteRebuilding)
                ? [] : output
        }
    }

    func updateDelay(
        outputPresentationLatencySeconds: Double,
        capturePresentationLatencySeconds: Double,
        queuedOutputFrameCount: Int,
        outputSampleRate: Double
    ) {
        queue.sync {
            guard outputPresentationLatencySeconds.isFinite,
                  capturePresentationLatencySeconds.isFinite,
                  outputSampleRate.isFinite,
                  outputSampleRate > 0,
                  queuedOutputFrameCount >= 0 else {
                enterFallback(.delayInvalid)
                return
            }
            let queuedSeconds = Double(queuedOutputFrameCount)
                / outputSampleRate
            let totalSeconds = max(0, outputPresentationLatencySeconds)
                + max(0, capturePresentationLatencySeconds)
                + queuedSeconds
                + max(0, captureProcessingMilliseconds) / 1_000
            let measuredMilliseconds = Int((totalSeconds * 1_000).rounded())
            guard measuredMilliseconds <= Self.maximumDelayMilliseconds else {
                enterFallback(.delayInvalid)
                return
            }
            delayMilliseconds = measuredMilliseconds
            guard mode == .webRTCAEC3, let backend else { return }
            do {
                try backend.setDelay(milliseconds: measuredMilliseconds)
            } catch {
                enterFallback(.delayInvalid)
            }
        }
    }

    func recordCaptureProcessingDuration(nanoseconds: UInt64) {
        queue.sync {
            captureProcessingMilliseconds = Double(nanoseconds) / 1_000_000
        }
    }

    func playbackStarted() {
        queue.sync { isPlaybackActive = true }
    }

    func playbackCompleted() {
        queue.sync {
            isPlaybackActive = false
            captureFIFO.removeAll(keepingCapacity: true)
            guard mode == .halfDuplexFallback,
                  fallbackReason != .routeRebuild,
                  requestedMode == .webRTCAEC3,
                  let backend else { return }
            do {
                try backend.reset()
                try backend.setDelay(milliseconds: delayMilliseconds)
                mode = .webRTCAEC3
                fallbackReason = nil
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
        }
    }

    func routeWillRebuild() {
        queue.sync {
            routeResetCount &+= 1
            isRouteRebuilding = true
            clearFIFOs()
            if requestedMode == .webRTCAEC3 {
                enterFallback(.routeRebuild)
            }
            logger.notice(
                "AEC route reset count=\(self.routeResetCount, privacy: .public) mode=\(self.mode.rawValue, privacy: .public)"
            )
        }
    }

    func snapshot() -> MacSpeechAcousticEchoSnapshot {
        queue.sync { makeSnapshot() }
    }

    private func appendBounded(
        _ samples: [Float],
        to fifo: inout [Float]
    ) -> Bool {
        guard samples.count <= fifoSampleCapacity,
              fifo.count <= fifoSampleCapacity - samples.count else {
            fifo.removeAll(keepingCapacity: true)
            return false
        }
        fifo.append(contentsOf: samples)
        return true
    }

    private func takeFrame(from fifo: inout [Float]) -> [Float] {
        let frame = Array(fifo.prefix(Self.frameSampleCount))
        fifo.removeFirst(Self.frameSampleCount)
        return frame
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
        if (renderFrameCount + captureFrameCount).isMultiple(of: 200) {
            logger.debug(
                "AEC mode=\(self.mode.rawValue, privacy: .public) enabled=\(self.backendStats.enabled, privacy: .public) frames=\(self.renderFrameCount, privacy: .public)/\(self.captureFrameCount, privacy: .public) delay_ms=\(self.delayMilliseconds, privacy: .public) estimated_ms=\(self.backendStats.estimatedDelayMilliseconds, privacy: .public) erl=\(self.backendStats.erlDecibels, privacy: .public) erle=\(self.backendStats.erleDecibels, privacy: .public) fifo=\(self.renderFIFO.count, privacy: .public)/\(self.captureFIFO.count, privacy: .public) drift=\(self.driftTrend, privacy: .public)"
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

    private func enterFallback(_ reason: MacSpeechAECFallbackReason) {
        mode = .halfDuplexFallback
        fallbackReason = reason
        backendStats = disabledStats()
        clearFIFOs()
        logger.error(
            "AEC fallback reason=\(reason.rawValue, privacy: .public) delay_ms=\(self.delayMilliseconds, privacy: .public)"
        )
    }

    private func clearFIFOs() {
        renderFIFO.removeAll(keepingCapacity: true)
        captureFIFO.removeAll(keepingCapacity: true)
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
