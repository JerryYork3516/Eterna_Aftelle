import CryptoKit
import Foundation
#if AFTELLE_REPLAY_INPUT_CHAIN
import AVFoundation
#endif

private typealias ReplayAudioFile = MacSpeechAcousticReplayAudioFile
private typealias ReplayManifest = MacSpeechAcousticReplayManifest

private final class RecordedAECBackend:
    MacSpeechAECBackend,
    @unchecked Sendable {
    private let cleanSamples: [Float]
    private let linearSamples: [Float]
    private var captureFrameIndex = 0
    private var currentStats: MacSpeechAECBackendStats
    private(set) var underflowCount = 0

    init(
        cleanSamples: [Float],
        linearSamples: [Float],
        initialStats: MacSpeechAECBackendStats
    ) {
        self.cleanSamples = cleanSamples
        self.linearSamples = linearSamples
        currentStats = initialStats
    }

    func configure() throws {}

    func processRender(_ samples: [Float]) throws {
        guard samples.count == MacSpeechAcousticEchoHost.frameSampleCount else {
            throw MacSpeechAECBackendError.renderFailed
        }
    }

    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult {
        let cleanFrameSize = MacSpeechAcousticEchoHost.frameSampleCount
        let linearFrameSize =
            MacSpeechAcousticEchoHost.linearOutputFrameSampleCount
        let cleanStart = captureFrameIndex * cleanFrameSize
        let linearStart = captureFrameIndex * linearFrameSize
        guard cleanStart + cleanFrameSize <= cleanSamples.count,
              linearStart + linearFrameSize <= linearSamples.count else {
            underflowCount += 1
            throw MacSpeechAECBackendError.captureFailed
        }
        captureFrameIndex += 1
        return MacSpeechAECCaptureResult(
            processedSamples: Array(
                cleanSamples[cleanStart ..< cleanStart + cleanFrameSize]
            ),
            linearOutputSamples: Array(
                linearSamples[linearStart ..< linearStart + linearFrameSize]
            )
        )
    }

    func setDelay(milliseconds _: Int) throws {}
    func reset() throws {}

    func stats() throws -> MacSpeechAECBackendStats { currentStats }

    func prepareStats(
        _ stats: MacSpeechAcousticReplayBackendStatsSnapshot
    ) {
        currentStats = stats.backendStats
    }

    var consumedCaptureFrameCount: Int { captureFrameIndex }
}

private final class FixtureAECBackend:
    MacSpeechAECBackend,
    @unchecked Sendable {
    private var delayMilliseconds = 0
    private var processedSamples = [Float](
        repeating: 0,
        count: MacSpeechAcousticEchoHost.frameSampleCount
    )
    private var linearSamples = [Float](
        repeating: 0,
        count: MacSpeechAcousticEchoHost.linearOutputFrameSampleCount
    )

    func configure() throws {}

    func processRender(_ samples: [Float]) throws {
        guard samples.count == MacSpeechAcousticEchoHost.frameSampleCount else {
            throw MacSpeechAECBackendError.renderFailed
        }
    }

    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult {
        guard samples.count == MacSpeechAcousticEchoHost.frameSampleCount else {
            throw MacSpeechAECBackendError.captureFailed
        }
        return MacSpeechAECCaptureResult(
            processedSamples: processedSamples,
            linearOutputSamples: linearSamples
        )
    }

    func setDelay(milliseconds: Int) throws {
        delayMilliseconds = milliseconds
    }

    func reset() throws {}

    func stats() throws -> MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(
            enabled: true,
            active: true,
            estimatedDelayMilliseconds: delayMilliseconds,
            erlDecibels: 12,
            erleDecibels: 24
        )
    }

    func setCaptureOutput(_ samples: [Float]) {
        processedSamples = samples
        linearSamples = downsample(samples)
    }
}

private enum ReplayTimelineEvent {
    case audio(MacSpeechAcousticReplayAudioCallSnapshot)
    case control(MacSpeechAcousticReplayControlEventSnapshot)

    var ordinal: UInt64 {
        switch self {
        case let .audio(call): call.ordinal
        case let .control(event): event.ordinal
        }
    }
}

private struct ReplayComparison {
    let captureFrameMismatches: [Int]
    let classifierMismatches: [Int]
    let gateMismatches: [Int]
    let timingMismatches: [Int]
    let audioCallsMatch: Bool
    let controlEventsMatch: Bool
    let renderFramesMatch: Bool
    let initialStateMatches: Bool
    let finalStateMatches: Bool
    let tracksMatch: Bool

    var isExact: Bool {
        captureFrameMismatches.isEmpty
            && classifierMismatches.isEmpty
            && gateMismatches.isEmpty
            && timingMismatches.isEmpty
            && audioCallsMatch
            && controlEventsMatch
            && renderFramesMatch
            && initialStateMatches
            && finalStateMatches
            && tracksMatch
    }
}

private struct ReplayWindowMetrics {
    let classifications: String
    let firstUserEvidenceFrame: UInt64?
    let firstConfirmedUserEvidenceFrame: UInt64?
    let userEvidenceFrameCount: Int
    let maximumContinuousUserEvidenceFrameCount: Int
    let firstGateOpenFrame: UInt64?
    let firstForwardedFrame: UInt64?
    let lastForwardedFrame: UInt64?
    let forwardedFrameCount: Int
    let maximumContinuousForwardedFrameCount: Int
    let timingMatchFrameCount: Int
    let alignmentLockedFrameCount: Int
    let isolationEstablishedFrameCount: Int
    let timingDelayRange: String
    let matchedRenderBackwardCount: Int
    let matchedRenderRepeatedCount: Int
}

@main
private struct RecordedAcousticReplay {
    private static let sourceGatePreRollFrameCount = 15
    private static let requiredSourceGateEvidenceFrames = 3
    private static let maximumTargetEvidenceLatencyFrames =
        sourceGatePreRollFrameCount

    static func main() async throws {
#if AFTELLE_REPLAY_INPUT_CHAIN
        if CommandLine.arguments.count == 4,
           CommandLine.arguments[2] == "--input-chain" {
            try await runInputChain(
                manifestURL: URL(fileURLWithPath: CommandLine.arguments[1]),
                fixtureURL: URL(fileURLWithPath: CommandLine.arguments[3])
            )
            return
        }
#endif
        if CommandLine.arguments.count == 2,
           CommandLine.arguments[1] == "--self-check" {
            try runSelfCheck()
            return
        }
        guard CommandLine.arguments.count == 6,
              CommandLine.arguments[2]
                == "--resident-only-capture-index",
              let residentOnlyRange = parseRange(CommandLine.arguments[3]),
              CommandLine.arguments[4] == "--speech-capture-index",
              let speechRange = parseRange(CommandLine.arguments[5])
        else {
            fputs(
                "usage: RecordedAcousticReplay <sample.aec-timeline.json> "
                    + "--resident-only-capture-index <start:end> "
                    + "--speech-capture-index <start:end>\n"
                    + "       RecordedAcousticReplay --self-check\n",
                stderr
            )
            Foundation.exit(64)
        }

        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifest = try loadManifest(manifestURL)
        let snapshot = try loadSnapshot(manifest, from: manifestURL)
        try validate(
            manifest: manifest,
            snapshot: snapshot,
            captureIndexRanges: [residentOnlyRange, speechRange]
        )

        let replayed = try (0 ..< 3).map { _ in
            try replay(snapshot)
        }
        let comparisons = replayed.dropFirst().map {
            compare(replayed[0], $0)
        }
        guard comparisons.allSatisfy(\.isExact),
              replayInputMatches(snapshot, replayed[0]) else {
            if let comparison = comparisons.first {
                printComparison(comparison)
            }
            throw ReplayError.liveReplayMismatch
        }

        let current = replayed[0]
        let recordedDelta = compare(snapshot, current)
        let recordedResident = windowMetrics(
            snapshot,
            in: residentOnlyRange
        )
        let replayedResident = windowMetrics(
            current,
            in: residentOnlyRange
        )
        let residentOnlyNegativeControlPassed =
            replayedResident.firstGateOpenFrame == nil
            && replayedResident.forwardedFrameCount == 0
        let recordedSpeech = windowMetrics(
            snapshot,
            in: speechRange
        )
        let replayedSpeech = windowMetrics(
            current,
            in: speechRange
        )
        let speechOnsetRange = max(
            0,
            speechRange.lowerBound - sourceGatePreRollFrameCount
        ) ..< min(
            Int(current.captureFrames.last?.captureFrameIndex ?? 0) + 1,
            speechRange.lowerBound
                + maximumTargetEvidenceLatencyFrames + 1
        )
        let speechOnset = windowMetrics(current, in: speechOnsetRange)
        let speechGateTransitionFrame = gateTransitions(
            current,
            in: speechOnsetRange
        ).first(where: { $0.open })?.frame
        let firstEvidenceOffsetFrames =
            replayedSpeech.firstUserEvidenceFrame.map {
                Int($0) - speechRange.lowerBound
            }
        let confirmedEvidenceOffsetFrames =
            replayedSpeech.firstConfirmedUserEvidenceFrame.map {
                Int($0) - speechRange.lowerBound
            }
        let gateTransitionOffsetFrames = speechGateTransitionFrame.map {
            Int($0) - speechRange.lowerBound
        }
        let firstForwardedOffsetFrames =
            speechOnset.firstForwardedFrame.map {
                Int($0) - speechRange.lowerBound
            }
        let onsetStartedClosed = captureFrames(
            in: speechOnsetRange.lowerBound
                ..< speechOnsetRange.lowerBound + 1,
            snapshot: current
        ).first?.sourceGateOpen == false
        let speechPositiveControlPassed =
            onsetStartedClosed
            && firstEvidenceOffsetFrames.map {
                (0 ... maximumTargetEvidenceLatencyFrames).contains($0)
            } ?? false
            && confirmedEvidenceOffsetFrames.map {
                (0 ... maximumTargetEvidenceLatencyFrames).contains($0)
            } ?? false
            && gateTransitionOffsetFrames.map {
                (-sourceGatePreRollFrameCount
                    ... maximumTargetEvidenceLatencyFrames).contains($0)
            } ?? false
            && firstForwardedOffsetFrames.map {
                (-sourceGatePreRollFrameCount
                    ... maximumTargetEvidenceLatencyFrames).contains($0)
            } ?? false
            && replayedSpeech.userEvidenceFrameCount
                >= requiredSourceGateEvidenceFrames
            && replayedSpeech.maximumContinuousUserEvidenceFrameCount
                >= requiredSourceGateEvidenceFrames
            && replayedSpeech.forwardedFrameCount == speechRange.count
            && replayedSpeech.maximumContinuousForwardedFrameCount
                == speechRange.count
            && replayedSpeech.lastForwardedFrame
                == UInt64(speechRange.upperBound - 1)

        print("sample_valid_for_exact_replay=true")
        print("attempt_id=\(manifest.attemptID)")
        print("schema_version=\(manifest.schemaVersion)")
        print("capture_frames=\(snapshot.captureFrames.count)")
        print("render_frames=\(snapshot.renderFrames.count)")
        print("post_playback_capture_frames=\(snapshot.postPlaybackCaptureFrameCount)")
        print("current_replay_runs=3")
        printComparison(comparisons[0])
        print("recorded_capture_frame_delta_count=\(recordedDelta.captureFrameMismatches.count)")
        print("recorded_classifier_delta_count=\(recordedDelta.classifierMismatches.count)")
        print("recorded_gate_delta_count=\(recordedDelta.gateMismatches.count)")
        print("recorded_timing_delta_count=\(recordedDelta.timingMismatches.count)")
        print("recorded_classifier=\(classificationCounts(snapshot))")
        print("recorded_gate_open_frames=\(gateOpenFrameCount(snapshot))")
        print("resident_only_capture_index_range=\(residentOnlyRange.lowerBound):\(residentOnlyRange.upperBound)")
        printWindowMetrics("resident_before", recordedResident)
        printWindowMetrics("resident_after", replayedResident)
        print("resident_after_timing_discontinuities=\(timingDiscontinuities(current, in: residentOnlyRange))")
        print("resident_only_negative_control=\(residentOnlyNegativeControlPassed ? "PASS" : "FAIL")")
        printWindowMetrics("speech_before", recordedSpeech)
        printWindowMetrics("speech_after", replayedSpeech)
        print("speech_after_timing_discontinuities=\(timingDiscontinuities(current, in: speechRange))")
        print("speech_before_gate_transitions=\(gateTransitionFrames(snapshot, around: speechRange))")
        print("speech_after_gate_transitions=\(gateTransitionFrames(current, around: speechRange))")
        print("speech_after_forwarded_runs=\(forwardedRuns(current, around: speechRange))")
        print("speech_after_gate_open_evidence=\(gateOpenEvidence(current, around: speechRange))")
        print("speech_first_evidence_offset_frames=\(firstEvidenceOffsetFrames ?? Int.min)")
        print("speech_confirmed_evidence_offset_frames=\(confirmedEvidenceOffsetFrames ?? Int.min)")
        print("speech_gate_transition_offset_frames=\(gateTransitionOffsetFrames ?? Int.min)")
        print("speech_first_forwarded_offset_frames=\(firstForwardedOffsetFrames ?? Int.min)")
        print("speech_positive_control=\(speechPositiveControlPassed ? "PASS" : "FAIL")")
        guard residentOnlyNegativeControlPassed,
              speechPositiveControlPassed else {
            Foundation.exit(1)
        }
        print("current_replay=PASS")
    }

    private static func runSelfCheck() throws {
        let live = try makeLiveFixture()
        guard live.isExactReplayReady else {
            throw ReplayError.invalidSnapshot
        }
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "aftelle-replay-v2-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        let manifestURL = try writeFixture(
            live,
            to: fixtureDirectory
        )
        let manifest = try loadManifest(manifestURL)
        guard try manifest.encodedData() == Data(contentsOf: manifestURL)
        else {
            throw ReplayError.fileRoundTripMismatch
        }
        let loaded = try loadSnapshot(manifest, from: manifestURL)
        try validate(
            manifest: manifest,
            snapshot: loaded,
            captureIndexRanges: [1 ..< 25]
        )
        guard capsulePayloadMatches(live, loaded) else {
            throw ReplayError.fileRoundTripMismatch
        }
        let residentOnlyRange = 1 ..< 25
        let residentFrames = Array(loaded.captureFrames[residentOnlyRange])
        guard residentFrames.allSatisfy({
            !$0.sourceGateOpen
                && !$0.emittedSpans.contains(where: \.sourceGateOpen)
                && !$0.emittedSpans.contains(where: { !$0.silenced })
        }) else {
            throw ReplayError.residentOnlyNegativeControlFailed
        }
        let positiveGateOpenFrames = loaded.captureFrames[25...].filter {
            $0.sourceGateOpen
                || $0.emittedSpans.contains(where: \.sourceGateOpen)
        }.count
        let positiveForwardedFrames = loaded.captureFrames[25...].filter {
            $0.emittedSpans.contains(where: { !$0.silenced })
        }.count
        guard positiveGateOpenFrames > 0,
              positiveForwardedFrames > 0 else {
            throw ReplayError.positiveControlFailed
        }

        let comparisons = try (0 ..< 3).map { _ in
            compare(loaded, try replay(loaded))
        }
        guard comparisons.allSatisfy(\.isExact) else {
            printComparison(comparisons[0])
            throw ReplayError.liveReplayMismatch
        }

        print("replay_capsule_schema=2")
        print("shared_manifest_codec_round_trip=true")
        print("replay_payload_round_trip_match=true")
        print("live_capture_frames=\(loaded.captureFrames.count)")
        print("live_render_frames=\(loaded.renderFrames.count)")
        print("chronological_render_samples=\(loaded.chronologicalRenderSamples.count)")
        print("raw_microphone_samples=\(loaded.rawMicrophoneSamples.count)")
        print("aec_clean_samples=\(loaded.aecCleanSamples.count)")
        print("aec_linear_samples=\(loaded.aecLinearSamples.count)")
        print("resident_only_gate_open_frames=0")
        print("resident_only_forwarded_frames=0")
        print("positive_gate_open_frames=\(positiveGateOpenFrames)")
        print("positive_forwarded_frames=\(positiveForwardedFrames)")
        print("live_replay_runs=3")
        printComparison(comparisons[0])
        print("live_replay=PASS")
    }

    private static func makeLiveFixture() throws
        -> MacSpeechAcousticReplayCaptureSnapshot {
        let backend = FixtureAECBackend()
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        guard host.configure() == .webRTCAEC3 else {
            throw ReplayError.hostConfigurationFailed
        }
        host.updateDelay(
            outputPresentationLatencySeconds: 0.020,
            capturePresentationLatencySeconds: 0.010
        )
        guard host.armAcousticReplayCapture(
            attemptID: UUID(),
            targetCaptureFrameCount: 30
        ) else {
            throw ReplayError.captureArmFailed
        }

        let baseTime: UInt64 = 20_000_000_000
        let prePlayback = signal(seed: 7, amplitude: 0.08)
        backend.setCaptureOutput(prePlayback.map { $0 * 0.5 })
        _ = host.processCaptureSpans(
            Array(prePlayback[..<240]),
            hostTimeNanoseconds: baseTime - 100_000_000
        )
        _ = host.processCaptureSpans(
            Array(prePlayback[240...]),
            hostTimeNanoseconds: baseTime - 95_000_000
        )
        host.updateDelay(
            outputPresentationLatencySeconds: 0.022,
            capturePresentationLatencySeconds: 0.010
        )
        host.playbackStarted()

        for index in 0 ..< 30 {
            let render = signal(
                seed: UInt32(100 + index),
                amplitude: 0.35
            )
            let renderTime = baseTime + UInt64(index) * 10_000_000
            if index == 28 {
                host.playbackStopped()
            }
            if index < 28 {
                host.processRender(render, hostTimeNanoseconds: renderTime)
            }
            let rawCapture: [Float]
            if index < 24 {
                let residual = render.map { $0 * 0.10 }
                backend.setCaptureOutput(residual)
                rawCapture = render.map { $0 * 0.80 }
            } else {
                let user = signal(
                    seed: UInt32(1_000 + index),
                    amplitude: 0.20
                )
                backend.setCaptureOutput(user)
                rawCapture = zip(render, user).map {
                    $0.0 * 0.80 + $0.1
                }
            }
            _ = host.processCaptureSpans(
                rawCapture,
                hostTimeNanoseconds: renderTime + 80_000_000
            )
            host.recordCaptureProcessingDuration(
                nanoseconds: UInt64(300_000 + index)
            )
        }
        guard let snapshot = host.acousticReplayCaptureSnapshot() else {
            throw ReplayError.invalidSnapshot
        }
        return snapshot
    }

    private static func replay(
        _ recorded: MacSpeechAcousticReplayCaptureSnapshot
    ) throws -> MacSpeechAcousticReplayCaptureSnapshot {
        let backend = RecordedAECBackend(
            cleanSamples: recorded.aecCleanSamples,
            linearSamples: recorded.aecLinearSamples,
            initialStats: recorded.initialState.backendStats.backendStats
        )
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        guard host.configure() == .webRTCAEC3,
              host.restoreAcousticReplayInitialState(recorded.initialState),
              host.armAcousticReplayCapture(
                  attemptID: UUID(),
                  targetCaptureFrameCount:
                    recorded.targetPostPlaybackCaptureFrameCount
              ) else {
            throw ReplayError.hostConfigurationFailed
        }

        let events = (
            recorded.audioCalls.map(ReplayTimelineEvent.audio)
                + recorded.controlEvents.map(ReplayTimelineEvent.control)
        ).sorted { $0.ordinal < $1.ordinal }
        for event in events {
            switch event {
            case let .audio(call):
                backend.prepareStats(call.backendStatsAfter)
                switch call.kind {
                case .render:
                    host.processRender(
                        try samples(
                            recorded.chronologicalRenderSamples,
                            offset: call.sampleOffset,
                            count: call.sampleCount
                        ),
                        hostTimeNanoseconds: call.hostTimeNanoseconds
                    )
                case .capture:
                    _ = host.processCaptureSpans(
                        try samples(
                            recorded.rawMicrophoneSamples,
                            offset: call.sampleOffset,
                            count: call.sampleCount
                        ),
                        hostTimeNanoseconds: call.hostTimeNanoseconds
                    )
                }
            case let .control(event):
                try apply(event, to: host)
            }
        }

        guard backend.underflowCount == 0,
              backend.consumedCaptureFrameCount
                == recorded.captureFrames.count,
              let replayed = host.acousticReplayCaptureSnapshot(),
              replayed.isExactReplayReady else {
            throw ReplayError.backendFrameMismatch
        }
        return replayed
    }

    private static func apply(
        _ event: MacSpeechAcousticReplayControlEventSnapshot,
        to host: MacSpeechAcousticEchoHost
    ) throws {
        switch event.kind {
        case .playbackStarted:
            host.playbackStarted()
        case .playbackCompleted:
            host.playbackCompleted()
        case .playbackStopped:
            host.playbackStopped()
        case .discardPendingCapture:
            host.discardPendingCaptureForGenerationTransition()
        case .delayUpdated:
            guard let output = event.outputPresentationLatencySeconds,
                  let capture = event.capturePresentationLatencySeconds else {
                throw ReplayError.invalidTimeline
            }
            host.updateDelay(
                outputPresentationLatencySeconds: output,
                capturePresentationLatencySeconds: capture
            )
        case .captureProcessingDuration:
            guard let duration =
                    event.captureProcessingDurationNanoseconds else {
                throw ReplayError.invalidTimeline
            }
            host.recordCaptureProcessingDuration(nanoseconds: duration)
        }
    }

    private static func compare(
        _ expected: MacSpeechAcousticReplayCaptureSnapshot,
        _ actual: MacSpeechAcousticReplayCaptureSnapshot
    ) -> ReplayComparison {
        ReplayComparison(
            captureFrameMismatches: mismatchIndexes(
                expected.captureFrames,
                actual.captureFrames
            ),
            classifierMismatches: pairedMismatchIndexes(
                expected.captureFrames,
                actual.captureFrames
            ) { $0.inputClassification == $1.inputClassification },
            gateMismatches: pairedMismatchIndexes(
                expected.captureFrames,
                actual.captureFrames
            ) {
                $0.sourceGateOpen == $1.sourceGateOpen
                    && $0.sourceGateEpoch == $1.sourceGateEpoch
                    && $0.sourceGatePreRollFrameCount
                        == $1.sourceGatePreRollFrameCount
                    && $0.sourceGateConfirmationFrameCount
                        == $1.sourceGateConfirmationFrameCount
                    && $0.sourceGateNonUserHangoverFrameCount
                        == $1.sourceGateNonUserHangoverFrameCount
                    && $0.pendingSourceGateReset
                        == $1.pendingSourceGateReset
                    && $0.emittedSpans == $1.emittedSpans
            },
            timingMismatches: pairedMismatchIndexes(
                expected.captureFrames,
                actual.captureFrames
            ) {
                $0.captureHostTimeNanoseconds
                        == $1.captureHostTimeNanoseconds
                    && $0.timingMatchAvailable
                        == $1.timingMatchAvailable
                    && $0.matchedRenderCallOrdinal
                        == $1.matchedRenderCallOrdinal
                    && $0.matchedRenderHostTimeNanoseconds
                        == $1.matchedRenderHostTimeNanoseconds
                    && $0.timingDelayMilliseconds
                        == $1.timingDelayMilliseconds
                    && $0.timingCorrelation == $1.timingCorrelation
                    && $0.sourceAlignmentLocked
                        == $1.sourceAlignmentLocked
                    && $0.sourceAlignmentDelayMilliseconds
                        == $1.sourceAlignmentDelayMilliseconds
                    && $0.timingLockCandidateMilliseconds
                        == $1.timingLockCandidateMilliseconds
                    && $0.timingLockCandidateFrameCount
                        == $1.timingLockCandidateFrameCount
                    && $0.timingLockedDelayMilliseconds
                        == $1.timingLockedDelayMilliseconds
                    && $0.timingLockConsecutiveMissFrameCount
                        == $1.timingLockConsecutiveMissFrameCount
            },
            audioCallsMatch: expected.audioCalls == actual.audioCalls,
            controlEventsMatch:
                expected.controlEvents == actual.controlEvents,
            renderFramesMatch: expected.renderFrames == actual.renderFrames,
            initialStateMatches:
                expected.initialState == actual.initialState,
            finalStateMatches:
                expected.finalState == actual.finalState,
            tracksMatch:
                expected.rawMicrophoneSamples == actual.rawMicrophoneSamples
                    && expected.chronologicalRenderSamples
                        == actual.chronologicalRenderSamples
                    && expected.aecCleanSamples == actual.aecCleanSamples
                    && expected.aecLinearSamples == actual.aecLinearSamples
        )
    }

    private static func replayInputMatches(
        _ recorded: MacSpeechAcousticReplayCaptureSnapshot,
        _ replayed: MacSpeechAcousticReplayCaptureSnapshot
    ) -> Bool {
        recorded.initialState == replayed.initialState
            && recorded.rawMicrophoneSamples == replayed.rawMicrophoneSamples
            && recorded.chronologicalRenderSamples
                == replayed.chronologicalRenderSamples
            && recorded.aecCleanSamples == replayed.aecCleanSamples
            && recorded.aecLinearSamples == replayed.aecLinearSamples
            && recorded.audioCalls == replayed.audioCalls
            && recorded.controlEvents == replayed.controlEvents
            && recorded.renderFrames == replayed.renderFrames
    }

    private static func captureFrames(
        in range: Range<Int>,
        snapshot: MacSpeechAcousticReplayCaptureSnapshot
    ) -> [MacSpeechAcousticReplayFrameSnapshot] {
        snapshot.captureFrames.filter {
            range.contains(Int($0.captureFrameIndex))
        }
    }

    private static func forwardedCaptureFrameIndexes(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        in range: Range<Int>
    ) -> [UInt64] {
        Array(Set(snapshot.captureFrames.flatMap(\.emittedSpans)
            .filter { !$0.silenced }
            .map(\.captureFrameIndex)
            .filter { range.contains(Int($0)) }))
            .sorted()
    }

    private static func windowMetrics(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        in range: Range<Int>
    ) -> ReplayWindowMetrics {
        let frames = captureFrames(in: range, snapshot: snapshot)
        let forwarded = forwardedCaptureFrameIndexes(snapshot, in: range)
        let userEvidence = frames.filter {
            $0.inputClassification == .nearEndSpeech
                || $0.inputClassification == .doubleTalk
        }.map(\.captureFrameIndex)
        return ReplayWindowMetrics(
            classifications: classificationCounts(frames),
            firstUserEvidenceFrame: userEvidence.first,
            firstConfirmedUserEvidenceFrame: firstContinuousRunEnd(
                userEvidence,
                requiredCount: requiredSourceGateEvidenceFrames
            ),
            userEvidenceFrameCount: userEvidence.count,
            maximumContinuousUserEvidenceFrameCount:
                maximumContinuousRun(userEvidence),
            firstGateOpenFrame: frames.first {
                $0.sourceGateOpen
            }?.captureFrameIndex,
            firstForwardedFrame: forwarded.first,
            lastForwardedFrame: forwarded.last,
            forwardedFrameCount: forwarded.count,
            maximumContinuousForwardedFrameCount:
                maximumContinuousRun(forwarded),
            timingMatchFrameCount: frames.filter(\.timingMatchAvailable).count,
            alignmentLockedFrameCount: frames.filter {
                $0.sourceAlignmentLocked
            }.count,
            isolationEstablishedFrameCount: frames.filter {
                $0.renderCaptureIsolationEstablished
            }.count,
            timingDelayRange: timingDelayRange(frames),
            matchedRenderBackwardCount:
                matchedRenderProgressCounts(frames).backward,
            matchedRenderRepeatedCount:
                matchedRenderProgressCounts(frames).repeated
        )
    }

    private static func timingDelayRange(
        _ frames: [MacSpeechAcousticReplayFrameSnapshot]
    ) -> String {
        let delays = frames.compactMap(\.timingDelayMilliseconds)
        guard let minimum = delays.min(), let maximum = delays.max() else {
            return "none"
        }
        return String(format: "%.1f-%.1f", minimum, maximum)
    }

    private static func matchedRenderProgressCounts(
        _ frames: [MacSpeechAcousticReplayFrameSnapshot]
    ) -> (backward: Int, repeated: Int) {
        var previous: UInt64?
        var backward = 0
        var repeated = 0
        for frame in frames {
            guard let current = frame.matchedRenderHostTimeNanoseconds else {
                continue
            }
            if let previous {
                if current < previous {
                    backward += 1
                } else if current == previous {
                    repeated += 1
                }
            }
            previous = current
        }
        return (backward, repeated)
    }

    private static func timingDiscontinuities(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        in range: Range<Int>
    ) -> String {
        let frames = captureFrames(in: range, snapshot: snapshot)
        var previous: MacSpeechAcousticReplayFrameSnapshot?
        var values: [String] = []
        for frame in frames {
            guard let render = frame.matchedRenderHostTimeNanoseconds else {
                continue
            }
            if let previous,
               let previousRender = previous.matchedRenderHostTimeNanoseconds,
               render <= previousRender {
                let captureAdvance = Double(
                    frame.captureHostTimeNanoseconds ?? 0
                ) - Double(previous.captureHostTimeNanoseconds ?? 0)
                let renderAdvance = Double(render) - Double(previousRender)
                let captureAdvanceMilliseconds = String(
                    format: "%.1f",
                    captureAdvance / 1_000_000
                )
                let renderAdvanceMilliseconds = String(
                    format: "%.1f",
                    renderAdvance / 1_000_000
                )
                let delayMilliseconds = String(
                    format: "%.1f",
                    frame.timingDelayMilliseconds ?? -1
                )
                values.append(
                    "\(frame.captureFrameIndex){capture_advance_ms=\(captureAdvanceMilliseconds),render_advance_ms=\(renderAdvanceMilliseconds),configured_delay_ms=\(frame.aecBufferDelayMilliseconds),matched_delay_ms=\(delayMilliseconds),candidate_frames=\(frame.timingLockCandidateFrameCount),miss_frames=\(frame.timingLockConsecutiveMissFrameCount)}"
                )
            }
            previous = frame
        }
        return values.isEmpty ? "none" : values.joined(separator: ";")
    }

    private static func maximumContinuousRun(_ values: [UInt64]) -> Int {
        guard let first = values.first else { return 0 }
        var previous = first
        var current = 1
        var maximum = 1
        for value in values.dropFirst() {
            if value == previous &+ 1 {
                current += 1
                maximum = max(maximum, current)
            } else {
                current = 1
            }
            previous = value
        }
        return maximum
    }

    private static func firstContinuousRunEnd(
        _ values: [UInt64],
        requiredCount: Int
    ) -> UInt64? {
        guard requiredCount > 0 else { return values.first }
        var previous: UInt64?
        var count = 0
        for value in values {
            count = previous.map { value == $0 &+ 1 } == true
                ? count + 1 : 1
            if count >= requiredCount { return value }
            previous = value
        }
        return nil
    }

    private static func gateTransitionFrames(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        around range: Range<Int>
    ) -> String {
        let lowerBound = max(0, range.lowerBound - 400)
        let upperBound = min(
            Int(snapshot.captureFrames.last?.captureFrameIndex ?? 0) + 1,
            range.upperBound + 1
        )
        let frames = captureFrames(
            in: lowerBound ..< upperBound,
            snapshot: snapshot
        )
        guard let first = frames.first else { return "none" }
        var previous = first.sourceGateOpen
        var transitions: [String] = []
        for frame in frames.dropFirst() where frame.sourceGateOpen != previous {
            transitions.append(
                "\(frame.captureFrameIndex):\(frame.sourceGateOpen ? "open" : "closed")"
            )
            previous = frame.sourceGateOpen
        }
        return transitions.isEmpty ? "none" : transitions.joined(separator: ",")
    }

    private static func gateTransitions(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        in range: Range<Int>
    ) -> [(frame: UInt64, open: Bool)] {
        let lowerContext = max(0, range.lowerBound - 1)
        let frames = captureFrames(
            in: lowerContext ..< range.upperBound,
            snapshot: snapshot
        )
        guard let first = frames.first else { return [] }
        var previous = first.sourceGateOpen
        return frames.dropFirst().compactMap { frame in
            defer { previous = frame.sourceGateOpen }
            guard frame.sourceGateOpen != previous,
                  range.contains(Int(frame.captureFrameIndex)) else {
                return nil
            }
            return (frame.captureFrameIndex, frame.sourceGateOpen)
        }
    }

    private static func forwardedRuns(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        around range: Range<Int>
    ) -> String {
        let lowerBound = max(0, range.lowerBound - 400)
        let upperBound = min(
            Int(snapshot.captureFrames.last?.captureFrameIndex ?? 0) + 1,
            range.upperBound + 1
        )
        let values = forwardedCaptureFrameIndexes(
            snapshot,
            in: lowerBound ..< upperBound
        )
        guard let first = values.first else { return "none" }
        var runs: [ClosedRange<UInt64>] = []
        var start = first
        var previous = first
        for value in values.dropFirst() {
            if value != previous &+ 1 {
                runs.append(start ... previous)
                start = value
            }
            previous = value
        }
        runs.append(start ... previous)
        return runs.map { "\($0.lowerBound)-\($0.upperBound)" }
            .joined(separator: ",")
    }

    private static func gateOpenEvidence(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        around range: Range<Int>
    ) -> String {
        let lowerBound = max(0, range.lowerBound - 400)
        let upperBound = min(
            Int(snapshot.captureFrames.last?.captureFrameIndex ?? 0) + 1,
            range.upperBound + 1
        )
        let frames = captureFrames(
            in: lowerBound ..< upperBound,
            snapshot: snapshot
        )
        var previousOpen = frames.first?.sourceGateOpen ?? false
        var evidence: [String] = []
        for (offset, frame) in frames.enumerated() {
            if frame.sourceGateOpen && !previousOpen {
                let start = max(0, offset - 3)
                let context = frames[start ... offset].map { item in
                    let correlation = item.timingCorrelation.map {
                        String(format: "%.3f", $0)
                    } ?? "nil"
                    let delay = item.timingDelayMilliseconds.map {
                        String(format: "%.1f", $0)
                    } ?? "nil"
                    return "\(item.captureFrameIndex){\(item.inputClassification.rawValue),raw=\(String(format: "%.4f", item.rawCaptureRMS)),clean=\(String(format: "%.4f", item.processedCaptureRMS)),linear=\(String(format: "%.4f", item.linearAECOutputRMS)),corr=\(correlation),delay=\(delay),locked=\(item.sourceAlignmentLocked),isolation=\(item.renderCaptureIsolationEstablished)}"
                }.joined(separator: ";")
                evidence.append(context)
            }
            previousOpen = frame.sourceGateOpen
        }
        return evidence.isEmpty ? "none" : evidence.joined(separator: "|")
    }

    private static func printWindowMetrics(
        _ prefix: String,
        _ metrics: ReplayWindowMetrics
    ) {
        print("\(prefix)_classifier=\(metrics.classifications)")
        print("\(prefix)_first_user_evidence_frame=\(metrics.firstUserEvidenceFrame.map(String.init) ?? "none")")
        print("\(prefix)_first_confirmed_user_evidence_frame=\(metrics.firstConfirmedUserEvidenceFrame.map(String.init) ?? "none")")
        print("\(prefix)_user_evidence_frame_count=\(metrics.userEvidenceFrameCount)")
        print("\(prefix)_maximum_continuous_user_evidence_frame_count=\(metrics.maximumContinuousUserEvidenceFrameCount)")
        print("\(prefix)_first_gate_open_frame=\(metrics.firstGateOpenFrame.map(String.init) ?? "none")")
        print("\(prefix)_first_forwarded_frame=\(metrics.firstForwardedFrame.map(String.init) ?? "none")")
        print("\(prefix)_last_forwarded_frame=\(metrics.lastForwardedFrame.map(String.init) ?? "none")")
        print("\(prefix)_forwarded_frame_count=\(metrics.forwardedFrameCount)")
        print("\(prefix)_maximum_continuous_forwarded_frame_count=\(metrics.maximumContinuousForwardedFrameCount)")
        print("\(prefix)_timing_match_frame_count=\(metrics.timingMatchFrameCount)")
        print("\(prefix)_alignment_locked_frame_count=\(metrics.alignmentLockedFrameCount)")
        print("\(prefix)_isolation_established_frame_count=\(metrics.isolationEstablishedFrameCount)")
        print("\(prefix)_timing_delay_ms=\(metrics.timingDelayRange)")
        print("\(prefix)_matched_render_backward_count=\(metrics.matchedRenderBackwardCount)")
        print("\(prefix)_matched_render_repeated_count=\(metrics.matchedRenderRepeatedCount)")
    }

    private static func capsulePayloadMatches(
        _ expected: MacSpeechAcousticReplayCaptureSnapshot,
        _ actual: MacSpeechAcousticReplayCaptureSnapshot
    ) -> Bool {
        expected.attemptID == actual.attemptID
            && expected.targetPostPlaybackCaptureFrameCount
                == actual.targetPostPlaybackCaptureFrameCount
            && expected.postPlaybackCaptureFrameCount
                == actual.postPlaybackCaptureFrameCount
            && expected.initialState == actual.initialState
            && expected.finalState == actual.finalState
            && expected.rawMicrophoneSamples == actual.rawMicrophoneSamples
            && expected.chronologicalRenderSamples
                == actual.chronologicalRenderSamples
            && expected.aecCleanSamples == actual.aecCleanSamples
            && expected.aecLinearSamples == actual.aecLinearSamples
            && expected.audioCalls == actual.audioCalls
            && expected.controlEvents == actual.controlEvents
            && expected.renderFrames == actual.renderFrames
            && expected.captureFrames == actual.captureFrames
            && expected.isSealed == actual.isSealed
            && expected.sealReason == actual.sealReason
    }

    private static func writeFixture(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        to directory: URL
    ) throws -> URL {
        let raw = MacSpeechAcousticReplayCodec.float32LittleEndianData(
            snapshot.rawMicrophoneSamples
        )
        let render = MacSpeechAcousticReplayCodec.float32LittleEndianData(
            snapshot.chronologicalRenderSamples
        )
        let clean = MacSpeechAcousticReplayCodec.float32LittleEndianData(
            snapshot.aecCleanSamples
        )
        let linear = MacSpeechAcousticReplayCodec.float32LittleEndianData(
            snapshot.aecLinearSamples
        )
        let files: [(String, Data)] = [
            ("fixture.raw-mic.f32le.pcm", raw),
            ("fixture.render-full.f32le.pcm", render),
            ("fixture.aec-clean.f32le.pcm", clean),
            ("fixture.aec-linear.f32le.pcm", linear)
        ]
        for (name, data) in files {
            try data.write(
                to: directory.appendingPathComponent(name),
                options: .atomic
            )
        }
        let descriptor: (String, Data, String, Int, Int) -> ReplayAudioFile = {
            name,
            data,
            stage,
            sampleRate,
            frameSampleCount in
            ReplayAudioFile(
                fileName: name,
                sha256: sha256(data),
                stage: stage,
                encoding: "float32le",
                sampleRate: sampleRate,
                channelCount: 1,
                frameSampleCount: frameSampleCount,
                byteCount: data.count
            )
        }
        let producerFingerprint = Data(
            "RecordedAcousticReplay.self-check".utf8
        )
        let manifest = ReplayManifest(
            schemaVersion: 2,
            producerBinaryName: "RecordedAcousticReplay.self-check",
            producerBinarySHA256: sha256(producerFingerprint),
            attemptID: snapshot.attemptID.uuidString,
            armedAt: snapshot.armedAt,
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
            targetPostPlaybackCaptureFrameCount:
                snapshot.targetPostPlaybackCaptureFrameCount,
            postPlaybackCaptureFrameCount:
                snapshot.postPlaybackCaptureFrameCount,
            capturedFrameCount: snapshot.captureFrames.count,
            renderedFrameCount: snapshot.renderFrames.count,
            durationMilliseconds: snapshot.durationMilliseconds,
            missingTimingMatchFrameCount: snapshot.captureFrames.filter {
                !$0.timingMatchAvailable
            }.count,
            isSealed: snapshot.isSealed,
            sealReason: snapshot.sealReason,
            exactReplayReady: snapshot.isExactReplayReady,
            renderReferenceSemantics:
                "chronological_host_render_callback_input",
            rawMicrophone: descriptor(
                files[0].0,
                raw,
                "post_device_conversion_pre_aec_callback_input",
                MacSpeechAcousticEchoHost.sampleRate,
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            chronologicalRender: descriptor(
                files[1].0,
                render,
                "chronological_post_device_conversion_render_callback_input",
                MacSpeechAcousticEchoHost.sampleRate,
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            aecClean: descriptor(
                files[2].0,
                clean,
                "post_aec_pre_source_gate",
                MacSpeechAcousticEchoHost.sampleRate,
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            aecLinear: descriptor(
                files[3].0,
                linear,
                "webrtc_aec_linear_output",
                MacSpeechAcousticEchoHost.linearOutputSampleRate,
                MacSpeechAcousticEchoHost.linearOutputFrameSampleCount
            ),
            initialState: snapshot.initialState,
            finalState: snapshot.finalState,
            audioCalls: snapshot.audioCalls,
            controlEvents: snapshot.controlEvents,
            renderFrames: snapshot.renderFrames,
            captureFrames: snapshot.captureFrames
        )
        let manifestURL = directory.appendingPathComponent(
            "fixture.aec-timeline.json"
        )
        try manifest.encodedData().write(to: manifestURL, options: .atomic)
        return manifestURL
    }

    private static func loadManifest(_ url: URL) throws -> ReplayManifest {
        try ReplayManifest.decode(from: Data(contentsOf: url))
    }

    private static func loadSnapshot(
        _ manifest: ReplayManifest,
        from manifestURL: URL
    ) throws -> MacSpeechAcousticReplayCaptureSnapshot {
        let directory = manifestURL.deletingLastPathComponent()
        let raw = try loadTrack(
            manifest.rawMicrophone,
            from: directory,
            expectedStage:
                "post_device_conversion_pre_aec_callback_input",
            sampleRate: MacSpeechAcousticEchoHost.sampleRate,
            frameSampleCount: MacSpeechAcousticEchoHost.frameSampleCount
        )
        let render = try loadTrack(
            manifest.chronologicalRender,
            from: directory,
            expectedStage:
                "chronological_post_device_conversion_render_callback_input",
            sampleRate: MacSpeechAcousticEchoHost.sampleRate,
            frameSampleCount: MacSpeechAcousticEchoHost.frameSampleCount
        )
        let clean = try loadTrack(
            manifest.aecClean,
            from: directory,
            expectedStage: "post_aec_pre_source_gate",
            sampleRate: MacSpeechAcousticEchoHost.sampleRate,
            frameSampleCount: MacSpeechAcousticEchoHost.frameSampleCount
        )
        let linear = try loadTrack(
            manifest.aecLinear,
            from: directory,
            expectedStage: "webrtc_aec_linear_output",
            sampleRate: MacSpeechAcousticEchoHost.linearOutputSampleRate,
            frameSampleCount:
                MacSpeechAcousticEchoHost.linearOutputFrameSampleCount
        )
        guard let attemptID = UUID(uuidString: manifest.attemptID) else {
            throw ReplayError.invalidManifest
        }
        return MacSpeechAcousticReplayCaptureSnapshot(
            attemptID: attemptID,
            armedAt: manifest.armedAt,
            startedAt: manifest.startedAt,
            endedAt: manifest.endedAt,
            targetPostPlaybackCaptureFrameCount:
                manifest.targetPostPlaybackCaptureFrameCount,
            postPlaybackCaptureFrameCount:
                manifest.postPlaybackCaptureFrameCount,
            initialState: manifest.initialState,
            finalState: manifest.finalState,
            rawMicrophoneSamples: raw,
            chronologicalRenderSamples: render,
            aecCleanSamples: clean,
            aecLinearSamples: linear,
            audioCalls: manifest.audioCalls,
            controlEvents: manifest.controlEvents,
            renderFrames: manifest.renderFrames,
            captureFrames: manifest.captureFrames,
            isSealed: manifest.isSealed,
            sealReason: manifest.sealReason
        )
    }

    private static func validate(
        manifest: ReplayManifest,
        snapshot: MacSpeechAcousticReplayCaptureSnapshot,
        captureIndexRanges: [Range<Int>]
    ) throws {
        let missingTimingMatchFrameCount = snapshot.captureFrames.filter {
            !$0.timingMatchAvailable
        }.count
        guard manifest.schemaVersion == 2,
              !manifest.producerBinaryName.isEmpty,
              manifest.producerBinarySHA256.count == 64,
              manifest.producerBinarySHA256.allSatisfy({
                  $0.isHexDigit
              }),
              manifest.exactReplayReady,
              snapshot.isExactReplayReady,
              manifest.renderReferenceSemantics
                == "chronological_host_render_callback_input",
              manifest.capturedFrameCount == snapshot.captureFrames.count,
              manifest.renderedFrameCount == snapshot.renderFrames.count,
              manifest.durationMilliseconds == snapshot.durationMilliseconds,
              manifest.missingTimingMatchFrameCount
                == missingTimingMatchFrameCount,
              captureIndexRanges.allSatisfy({ range in
                  guard !range.isEmpty else { return false }
                  let indexes = captureFrames(
                      in: range,
                      snapshot: snapshot
                  ).map(\.captureFrameIndex)
                  return indexes.count == range.count
                      && indexes.first == UInt64(range.lowerBound)
                      && indexes.last == UInt64(range.upperBound - 1)
              }) else {
            throw ReplayError.invalidManifest
        }
    }

    private static func loadTrack(
        _ descriptor: ReplayAudioFile,
        from directory: URL,
        expectedStage: String,
        sampleRate: Int,
        frameSampleCount: Int
    ) throws -> [Float] {
        guard descriptor.fileName == (descriptor.fileName as NSString)
                .lastPathComponent,
              descriptor.encoding == "float32le",
              descriptor.sampleRate == sampleRate,
              descriptor.channelCount == 1,
              descriptor.frameSampleCount == frameSampleCount,
              descriptor.stage == expectedStage else {
            throw ReplayError.invalidAudioFormat
        }
        let data = try Data(
            contentsOf: directory.appendingPathComponent(descriptor.fileName)
        )
        guard data.count == descriptor.byteCount,
              sha256(data) == descriptor.sha256,
              data.count.isMultiple(of: MemoryLayout<UInt32>.size) else {
            throw ReplayError.invalidAudioFile
        }
        return data.withUnsafeBytes { bytes in
            (0 ..< data.count / MemoryLayout<UInt32>.size).map { index in
                let bits = bytes.loadUnaligned(
                    fromByteOffset: index * MemoryLayout<UInt32>.size,
                    as: UInt32.self
                )
                return Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
    }

    private static func samples(
        _ track: [Float],
        offset: Int,
        count: Int
    ) throws -> [Float] {
        guard offset >= 0,
              count > 0,
              offset + count <= track.count else {
            throw ReplayError.invalidTimeline
        }
        return Array(track[offset ..< offset + count])
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func parseRange(_ value: String) -> Range<Int>? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              start < end else { return nil }
        return start ..< end
    }

    private static func mismatchIndexes<T: Equatable>(
        _ expected: [T],
        _ actual: [T]
    ) -> [Int] {
        pairedMismatchIndexes(expected, actual, matches: ==)
    }

    private static func pairedMismatchIndexes<T, U>(
        _ expected: [T],
        _ actual: [U],
        matches: (T, U) -> Bool
    ) -> [Int] {
        let sharedCount = min(expected.count, actual.count)
        var mismatches = (0 ..< sharedCount).filter {
            !matches(expected[$0], actual[$0])
        }
        if expected.count != actual.count {
            mismatches.append(contentsOf:
                sharedCount ..< max(expected.count, actual.count)
            )
        }
        return mismatches
    }

    private static func printComparison(_ comparison: ReplayComparison) {
        print("capture_frame_mismatch_count=\(comparison.captureFrameMismatches.count)")
        print("classifier_mismatch_count=\(comparison.classifierMismatches.count)")
        print("gate_mismatch_count=\(comparison.gateMismatches.count)")
        print("timing_mismatch_count=\(comparison.timingMismatches.count)")
        print("audio_calls_match=\(comparison.audioCallsMatch)")
        print("control_events_match=\(comparison.controlEventsMatch)")
        print("render_frames_match=\(comparison.renderFramesMatch)")
        print("initial_state_match=\(comparison.initialStateMatches)")
        print("final_state_match=\(comparison.finalStateMatches)")
        print("audio_tracks_match=\(comparison.tracksMatch)")
    }

    private static func classificationCounts(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot
    ) -> String {
        classificationCounts(snapshot.captureFrames)
    }

    private static func classificationCounts(
        _ frames: [MacSpeechAcousticReplayFrameSnapshot]
    ) -> String {
        Dictionary(
            grouping: frames.map {
                $0.inputClassification.rawValue
            },
            by: { $0 }
        )
        .mapValues(\.count)
        .sorted { $0.key < $1.key }
        .map { "\($0.key):\($0.value)" }
        .joined(separator: ",")
    }

    private static func gateOpenFrameCount(
        _ snapshot: MacSpeechAcousticReplayCaptureSnapshot
    ) -> Int {
        snapshot.captureFrames.filter {
            $0.sourceGateOpen
                || $0.emittedSpans.contains(where: \.sourceGateOpen)
        }.count
    }
}

private func signal(seed: UInt32, amplitude: Float) -> [Float] {
    var state = seed
    return (0 ..< MacSpeechAcousticEchoHost.frameSampleCount).map { _ in
        state = state &* 1_664_525 &+ 1_013_904_223
        let unit = Float(state >> 8) / Float(0x00FF_FFFF)
        return (unit * 2 - 1) * amplitude
    }
}

private func downsample(_ samples: [Float]) -> [Float] {
    stride(from: 0, to: samples.count, by: 3).map { index in
        (samples[index] + samples[index + 1] + samples[index + 2]) / 3
    }
}

#if AFTELLE_REPLAY_INPUT_CHAIN
private struct ReplayCredentials: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? { nil }
}

private struct ReplayAuthorization: MicrophoneAuthorizationProviding {
    func currentAuthorization() async throws -> MicrophoneAuthorizationState { .authorized }
    func requestAuthorization() async throws -> MicrophoneAuthorizationState { .authorized }
}

private final class ReplayDeviceMonitor: MacSpeechDeviceRouteMonitoring, @unchecked Sendable {
    func currentRoute() -> MacSpeechDeviceRoute {
        MacSpeechDeviceRoute(
            input: MacSpeechAudioDevice(identifier: "replay-input", name: "Replay", isAvailable: true),
            output: MacSpeechAudioDevice(identifier: "replay-output", name: "Replay", isAvailable: true)
        )
    }
    func start(onChange: @escaping @Sendable () -> Void) {}
    func stop() {}
}

private actor ReplayInputProvider: RealtimeResidentBrainProvider {
    private var events: [RealtimeResidentBrainEvent] = []
    private var receiver: CheckedContinuation<RealtimeResidentBrainEvent, Error>?
    private(set) var session: RealtimeBrainSessionIdentity?
    private(set) var audioCount = 0
    private(set) var interruptCount = 0
    private(set) var cancelCount = 0
    private(set) var responseCount = 0

    func openSession(_ command: RealtimeBrainOpenSessionCommand) async throws {}
    func updateRuntimeContext(_ update: RealtimeBrainRuntimeContextUpdate) async throws {
        session = update.identity
        if update.kind == .bootstrap {
            enqueue(RealtimeResidentBrainEvent(
                identity: RealtimeBrainEventIdentity(session: update.identity, turnID: nil,
                    responseID: nil, contextRevision: update.contextRevision),
                sequence: 1, kind: .sessionReady
            ))
        }
    }
    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws { audioCount += 1 }
    func submitToolResult(_ command: RealtimeBrainToolResultCommand) async throws {}
    func createResponse(_ command: RealtimeBrainCreateResponseCommand) async throws { responseCount += 1 }
    func cancelGeneration(_ command: RealtimeBrainCancelGenerationCommand) async throws { cancelCount += 1 }
    func interrupt(_ command: RealtimeBrainInterruptCommand) async throws { interruptCount += 1 }
    func receiveEvent(session: RealtimeBrainSessionIdentity) async throws -> RealtimeResidentBrainEvent {
        if !events.isEmpty { return events.removeFirst() }
        return try await withCheckedThrowingContinuation {
            precondition(receiver == nil)
            receiver = $0
        }
    }
    func closeSession(_ command: RealtimeBrainCloseSessionCommand) async throws {
        let pending = receiver
        receiver = nil
        pending?.resume(throwing: RealtimeResidentBrainError.cancelled)
    }
    func enqueue(_ event: RealtimeResidentBrainEvent) {
        if let pending = receiver {
            receiver = nil
            pending.resume(returning: event)
        } else { events.append(event) }
    }
}

private final class ReplayInputCapture: MacSpeechAudioCapturing, @unchecked Sendable {
    let host: MacSpeechAcousticEchoHost
    private let converter: MacSpeechAudioConverter
    private let lock = NSLock()
    private var target: (UInt64, MacSpeechAudioFrameBuffer)?
    private(set) var packets = 0

    init(host: MacSpeechAcousticEchoHost) throws {
        self.host = host
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000, channels: 1, interleaved: false) else {
            throw ReplayError.invalidAudioFormat
        }
        converter = try MacSpeechAudioConverter(inputFormat: format)
    }
    func start(generation: UInt64, frameBuffer: MacSpeechAudioFrameBuffer) throws -> MacSpeechNativeInputFormat {
        lock.withLock { target = (generation, frameBuffer) }
        return MacSpeechNativeInputFormat(sampleRate: 48_000, channelCount: 1)
    }
    func stop() { lock.withLock { target = nil } }
    func discardPendingAudioForGenerationTransition() { converter.resetForGenerationTransition() }
    func acousticEchoSnapshot() -> MacSpeechAcousticEchoSnapshot? { host.snapshot() }
    func acousticObservationSnapshot() -> MacSpeechAcousticObservationSnapshot? { host.acousticObservationSnapshot() }
    func resetAcousticEchoDiagnostics() { host.resetDiagnostics() }

    func emit(_ spans: [MacSpeechAcousticCaptureSpan]) throws {
        guard let (generation, buffer) = lock.withLock({ target }) else {
            throw ReplayError.hostConfigurationFailed
        }
        for packet in try converter.convert(captureSpans: spans) {
            guard let acoustic = packet.acousticSnapshot,
                  let timestamp = acoustic.captureHostTimeNanoseconds else {
                throw ReplayError.invalidTimeline
            }
            guard buffer.append(pcm16Bytes: packet.bytes, activity: packet.activity,
                generation: generation, timestamp: timestamp,
                activityEvidenceKind: packet.activityEvidenceKind,
                residentPlaybackSequence: acoustic.playbackSequence,
                residentPlaybackActive: acoustic.isPlaybackActive,
                lastAudibleResidentRenderTimestampNanoseconds: acoustic.lastAudibleRenderHostTimeNanoseconds,
                sourceGateEpoch: packet.activityEvidenceKind == .sourceGatedNearEnd ? acoustic.sourceGateEpoch : 0,
                acousticSnapshot: acoustic) else { throw ReplayError.invalidTimeline }
            packets += 1
        }
    }
}

extension RecordedAcousticReplay {
    @MainActor
    private static func runInputChain(manifestURL: URL, fixtureURL: URL) async throws {
        let manifest = try loadManifest(manifestURL)
        let recorded = try loadSnapshot(manifest, from: manifestURL)
        try validate(manifest: manifest, snapshot: recorded,
            captureIndexRanges: [1029 ..< 1229, 1798 ..< 1959])
        let reference = try replay(recorded)
        let backend = RecordedAECBackend(cleanSamples: recorded.aecCleanSamples,
            linearSamples: recorded.aecLinearSamples,
            initialStats: recorded.initialState.backendStats.backendStats)
        let host = MacSpeechAcousticEchoHost(mode: .webRTCAEC3, backend: backend)
        guard host.configure() == .webRTCAEC3 else { throw ReplayError.hostConfigurationFailed }
        let capture = try ReplayInputCapture(host: host)
        let provider = ReplayInputProvider()
        let router = ProviderRouter(credentialReader: ReplayCredentials(), realtimeResidentBrainProvider: provider)
        let runtime = RuntimeCore(executionEngine: ExecutionEngine(providerRouter: router), providerRouter: router)
        let player = FakeMacSpeechAudioOutputPlayer()
        let controller = AppController(
            orchestrationKernel: OrchestrationKernel(runtimeCore: runtime),
            speechAudioHost: MacSpeechAudioHost(authorizationProvider: ReplayAuthorization(),
                capture: capture, deviceMonitor: ReplayDeviceMonitor()),
            speechAudioOutputHost: MacSpeechAudioOutputHost(player: player,
                deviceMonitor: FakeMacSpeechOutputDeviceMonitor(),
                configuration: MacSpeechPCMPlaybackConfiguration(capacity: 4, lowWatermark: 1,
                    consumerTimeoutNanoseconds: 30_000_000_000, startupBufferCount: 1,
                    startupBufferDurationNanoseconds: 0, scheduleAheadCount: 2))
        )
        controller.debugImportResident(from: fixtureURL)
        await controller.startRealtimeResidentBrainRoute()
        try await awaitReplayCondition {
            controller.formalSpeechRouteDebugSnapshot.phase == .listening
        }
        guard let session = await provider.session else { throw ReplayError.hostConfigurationFailed }
        let lease = runtime.activeBrainLeaseForTesting()
        let identity = RealtimeBrainEventIdentity(session: session, turnID: RealtimeBrainTurnID(),
            responseID: RealtimeBrainResponseID(), contextRevision: 1)
        await provider.enqueue(RealtimeResidentBrainEvent(
            identity: RealtimeBrainEventIdentity(session: session, turnID: identity.turnID,
                responseID: nil, contextRevision: 1),
            sequence: 2, kind: .userTranscriptFinal("Replay fixture playback")
        ))
        await provider.enqueue(RealtimeResidentBrainEvent(identity: identity, sequence: 3,
            kind: .residentAudioDelta(RealtimeBrainAudioDelta(sequence: 1,
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                format: RealtimeBrainAudioFormat(encoding: .pcm16LittleEndian, sampleRate: 24_000, channelCount: 1),
                provenance: .providerGenerated, bytes: Data(repeating: 0, count: 960)))))
        try await awaitReplayCondition { player.startCount == 1 }
        let responsesBefore = await provider.responseCount

        // Translate the entire monotonic epoch once, including both FIFO remainders.
        // Preserve every relative timestamp and callback order; pace whole recorded callbacks.
        let originalStart = ([recorded.initialState.renderRemainderHostTimeNanoseconds,
            recorded.initialState.captureRemainderHostTimeNanoseconds].compactMap { $0 }
            + recorded.audioCalls.compactMap(\.hostTimeNanoseconds)).min()!
        let replayStart = DispatchTime.now().uptimeNanoseconds + 20_000_000
        func translated(_ timestamp: UInt64) -> UInt64 { replayStart + timestamp - originalStart }
        var initialObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(recorded.initialState)) as! [String: Any]
        for key in ["renderRemainderHostTimeNanoseconds", "captureRemainderHostTimeNanoseconds"] {
            if let value = initialObject[key] as? NSNumber { initialObject[key] = translated(value.uint64Value) }
        }
        let initial = try JSONDecoder().decode(MacSpeechAcousticReplayInitialStateSnapshot.self,
            from: JSONSerialization.data(withJSONObject: initialObject))
        guard host.restoreAcousticReplayInitialState(initial),
              host.armAcousticReplayCapture(attemptID: UUID(),
                targetCaptureFrameCount: recorded.targetPostPlaybackCaptureFrameCount) else {
            throw ReplayError.hostConfigurationFailed
        }
        var residentGate = 0
        var residentForwarded = Set<UInt64>()
        var residentRuntime = Set<UInt64>()
        var speechForwarded = Set<UInt64>()
        var speechRuntime = Set<UInt64>()
        var maximumCallbackLateness: UInt64 = 0
        var evidenceBeforeTarget: UInt64 = 0
        let speechFirst = reference.captureFrames.first { $0.captureFrameIndex == 1798 }!.captureHostTimeNanoseconds!
        let speechLast = reference.captureFrames.first { $0.captureFrameIndex == 1958 }!.captureHostTimeNanoseconds!
        let residentFirst = reference.captureFrames.first { $0.captureFrameIndex == 1029 }!.captureHostTimeNanoseconds!
        let residentLast = reference.captureFrames.first { $0.captureFrameIndex == 1228 }!.captureHostTimeNanoseconds!
        let events = (recorded.audioCalls.map(ReplayTimelineEvent.audio)
            + recorded.controlEvents.map(ReplayTimelineEvent.control)).sorted { $0.ordinal < $1.ordinal }
        for event in events {
            switch event {
            case let .control(control): try apply(control, to: host)
            case let .audio(call):
                guard let timestamp = call.hostTimeNanoseconds else { throw ReplayError.invalidTimeline }
                let frameEnd: UInt64
                if call.frameCount > 0 {
                    let lastIndex = call.firstFrameIndex + call.frameCount - 1
                    frameEnd = call.kind == .capture
                        ? recorded.captureFrames[lastIndex].captureHostTimeNanoseconds!
                        : recorded.renderFrames[lastIndex].hostTimeNanoseconds!
                } else { frameEnd = timestamp }
                let deadline = translated(max(timestamp, frameEnd))
                let now = DispatchTime.now().uptimeNanoseconds
                if deadline > now { try await Task.sleep(nanoseconds: deadline - now) }
                maximumCallbackLateness = max(maximumCallbackLateness,
                    DispatchTime.now().uptimeNanoseconds - deadline)
                backend.prepareStats(call.backendStatsAfter)
                if call.kind == .render {
                    host.processRender(try samples(recorded.chronologicalRenderSamples,
                        offset: call.sampleOffset, count: call.sampleCount), hostTimeNanoseconds: translated(timestamp))
                } else {
                    let spans = host.processCaptureSpans(try samples(recorded.rawMicrophoneSamples,
                        offset: call.sampleOffset, count: call.sampleCount), hostTimeNanoseconds: translated(timestamp))
                    for span in spans where span.samples.contains(where: { $0 != 0 }) {
                        let index = span.observation.captureFrameIndex
                        if (1029 ..< 1229).contains(index) { residentForwarded.insert(index) }
                        if (1798 ..< 1959).contains(index) { speechForwarded.insert(index) }
                    }
                    try capture.emit(spans)
                    await controller.refreshMicrophoneAuthorization()
                    let acoustic = host.acousticObservationSnapshot()
                    if acoustic.captureFrameIndex < 1783 {
                        evidenceBeforeTarget = controller.realtimeBrainInputBridgeSnapshot.acousticEvidenceCount
                    }
                }
            }
            for record in runtime.realtimeAcousticObservationDebugSnapshot().records
                where record.disposition == .observed && record.observation.classification == .nearEndCandidate {
                let time = record.observation.identity.timestampNanoseconds
                if (translated(residentFirst) ... translated(residentLast)).contains(time) {
                    residentRuntime.insert(record.observation.identity.sequence)
                }
                if (translated(speechFirst) ... translated(speechLast)).contains(time) {
                    speechRuntime.insert(record.observation.identity.sequence)
                }
            }
        }
        try await awaitReplayCondition {
            await controller.refreshMicrophoneAuthorization()
            return controller.realtimeBrainInputBridgeSnapshot.forwardedFrameCount >= capture.packets
        }
        guard let replayed = host.acousticReplayCaptureSnapshot(), replayed.isExactReplayReady,
              backend.underflowCount == 0 else { throw ReplayError.backendFrameMismatch }
        residentGate = replayed.captureFrames.filter {
            (1029 ..< 1229).contains($0.captureFrameIndex) && $0.sourceGateOpen
        }.count
        // Normalize only absolute timestamps before using the existing exact comparator.
        var normalizedFrames: [MacSpeechAcousticReplayFrameSnapshot] = []
        for frame in replayed.captureFrames {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as! [String: Any]
            for key in ["timestampNanoseconds", "captureHostTimeNanoseconds", "matchedRenderHostTimeNanoseconds"] {
                if let value = object[key] as? NSNumber {
                    object[key] = value.uint64Value - replayStart + originalStart
                }
            }
            normalizedFrames.append(try JSONDecoder().decode(MacSpeechAcousticReplayFrameSnapshot.self,
                from: JSONSerialization.data(withJSONObject: object)))
        }
        let mismatches = mismatchIndexes(reference.captureFrames, normalizedFrames)
        let bridge = controller.realtimeBrainInputBridgeSnapshot
        let acousticEvidence = runtime.realtimeInterruptionEvidenceDebugSnapshot()
        let interrupts = await provider.interruptCount
        let cancels = await provider.cancelCount
        let providerAudioCount = await provider.audioCount
        let extraResponses = await provider.responseCount - responsesBefore
        print("rb1_input_pcm_packets=\(capture.packets)")
        print("rb1_input_forwarded_packets=\(bridge.forwardedFrameCount)")
        print("rb1_input_provider_received_packets=\(providerAudioCount)")
        print("rb1_input_source_gated_packets=\(bridge.sourceGatedNearEndFrameCount)")
        print("rb1_input_eligibility_candidates=\(bridge.acousticEligibilityCandidateCount)")
        print("rb1_input_acoustic_evidence=\(bridge.acousticEvidenceCount)")
        print("rb1_input_target_new_evidence=\(bridge.acousticEvidenceCount - evidenceBeforeTarget)")
        print("rb1_input_target_runtime_observations=\(speechRuntime.count)")
        print("rb1_input_runtime_has_acoustic_evidence=\(acousticEvidence.hasAcousticEvidence)")
        print("rb1_input_runtime_has_semantic_evidence=\(acousticEvidence.hasSemanticEvidence)")
        print("rb1_input_resident_gate_open=\(residentGate)")
        print("rb1_input_resident_forwarded_frames=\(residentForwarded.count)")
        print("rb1_input_resident_runtime_observations=\(residentRuntime.count)")
        print("rb1_input_speech_forwarded_frames=\(speechForwarded.count)")
        print("rb1_input_rebased_frame_mismatches=\(mismatches.count)")
        print("rb1_input_rebased_mismatch_indexes=\(mismatches.prefix(10))")
        print("rb1_input_callback_max_lateness_ms=\(Double(maximumCallbackLateness) / 1_000_000)")
        print("rb1_input_eligibility_dispositions=\(bridge.acousticEligibilityDispositionCounts)")
        print("rb1_input_forward_dispositions=\(bridge.acousticEvidenceForwardDispositionCounts)")
        print("rb1_input_runtime_rejected_packets=\(bridge.runtimeRejectedFrameCount)")
        print("rb1_input_stale_evidence_fences=\(bridge.acousticEvidenceStaleFenceCount)")
        print("rb1_input_provider_interrupt=\(interrupts)")
        print("rb1_input_provider_cancel=\(cancels)")
        print("rb1_input_playback_clear=\(player.clearScheduledPlaybackCount)")
        print("rb1_input_extra_response=\(extraResponses)")
        let unchangedLease = runtime.activeBrainLeaseForTesting() == lease
        print("rb1_input_generation_and_lease_unchanged=\(unchangedLease)")
        let passed = mismatches.isEmpty && residentGate == 0 && residentForwarded.isEmpty
            && residentRuntime.isEmpty && speechForwarded.count == 161 && !speechRuntime.isEmpty
            && bridge.acousticEvidenceCount > evidenceBeforeTarget && acousticEvidence.hasAcousticEvidence
            && !acousticEvidence.hasSemanticEvidence && interrupts == 0 && cancels == 0
            && player.clearScheduledPlaybackCount == 0 && extraResponses == 0 && unchangedLease
            && providerAudioCount == capture.packets && bridge.runtimeRejectedFrameCount == 0
            && bridge.acousticEvidenceStaleFenceCount == 0
        await controller.stopSpeechAudioCapture()
        print("rb1_input_chain=\(passed ? "PASS" : "FAIL")")
        print("rb1_input_backend=recorded_aec_clean_and_linear")
        print("rb1_input_timing_classifier_gate_bridge_controller_runtime=production")
        print("rb1_input_real_qwen_and_device=NOT_RUN")
        fflush(stdout)
        if !passed { Foundation.exit(1) }
    }

    @MainActor
    private static func awaitReplayCondition(_ condition: () async -> Bool) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while !(await condition()) {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw ReplayError.hostConfigurationFailed }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
#endif

private enum ReplayError: Error {
    case invalidManifest
    case invalidSnapshot
    case invalidTimeline
    case invalidAudioFormat
    case invalidAudioFile
    case hostConfigurationFailed
    case captureArmFailed
    case backendFrameMismatch
    case liveReplayMismatch
    case fileRoundTripMismatch
    case residentOnlyNegativeControlFailed
    case positiveControlFailed
}
