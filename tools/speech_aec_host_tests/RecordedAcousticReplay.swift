import CryptoKit
import Foundation

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

@main
private struct RecordedAcousticReplay {
    static func main() throws {
        if CommandLine.arguments.count == 2,
           CommandLine.arguments[1] == "--self-check" {
            try runSelfCheck()
            return
        }
        guard CommandLine.arguments.count == 4,
              CommandLine.arguments[2] == "--resident-only",
              let residentOnlyRange = parseRange(CommandLine.arguments[3])
        else {
            fputs(
                "usage: RecordedAcousticReplay <sample.aec-timeline.json> "
                    + "--resident-only <start:end>\n"
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
            residentOnlyRange: residentOnlyRange
        )

        let comparisons = try (0 ..< 3).map { _ in
            compare(snapshot, try replay(snapshot))
        }
        guard comparisons.allSatisfy(\.isExact) else {
            printComparison(comparisons[0])
            throw ReplayError.liveReplayMismatch
        }

        let residentFrames = Array(
            snapshot.captureFrames[residentOnlyRange]
        )
        let residentOnlyGateOpenFrames = residentFrames.filter {
            $0.sourceGateOpen
                || $0.emittedSpans.contains(where: \.sourceGateOpen)
        }.count
        let residentOnlyForwardedFrames = residentFrames.filter { frame in
            frame.emittedSpans.contains(where: { !$0.silenced })
        }.count
        guard residentOnlyGateOpenFrames == 0,
              residentOnlyForwardedFrames == 0 else {
            throw ReplayError.residentOnlyNegativeControlFailed
        }

        print("sample_valid_for_exact_replay=true")
        print("attempt_id=\(manifest.attemptID)")
        print("schema_version=\(manifest.schemaVersion)")
        print("capture_frames=\(snapshot.captureFrames.count)")
        print("render_frames=\(snapshot.renderFrames.count)")
        print("post_playback_capture_frames=\(snapshot.postPlaybackCaptureFrameCount)")
        print("live_replay_runs=3")
        printComparison(comparisons[0])
        print("recorded_classifier=\(classificationCounts(snapshot))")
        print("recorded_gate_open_frames=\(gateOpenFrameCount(snapshot))")
        print("resident_only_range=\(residentOnlyRange.lowerBound):\(residentOnlyRange.upperBound)")
        print("resident_only_gate_open_frames=0")
        print("resident_only_forwarded_frames=0")
        print("live_replay=PASS")
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
            residentOnlyRange: 1 ..< 25
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
        residentOnlyRange: Range<Int>
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
              residentOnlyRange.lowerBound >= 0,
              residentOnlyRange.upperBound <= snapshot.captureFrames.count,
              !residentOnlyRange.isEmpty else {
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
        Dictionary(
            grouping: snapshot.captureFrames.map {
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
