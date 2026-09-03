import CryptoKit
import Foundation

private struct ReplayAudioFile: Decodable {
    let fileName: String
    let sha256: String
    let byteCount: Int
    let sampleRate: Int
    let channelCount: Int
    let frameSampleCount: Int
}

private struct ReplayFrame: Decodable {
    let captureFrameIndex: UInt64
    let sampleOffset: Int
    let timestampNanoseconds: UInt64
    let captureHostTimeNanoseconds: UInt64?
    let timingMatchAvailable: Bool
    let matchedRenderHostTimeNanoseconds: UInt64?
    let aecBufferDelayMilliseconds: Int
    let sourceAlignmentLocked: Bool
    let classifier: String
    let sourceGateOpen: Bool
    let playbackSequence: UInt64
    let playbackActive: Bool
}

private struct ReplayManifest: Decodable {
    let schemaVersion: Int
    let attemptId: UUID
    let targetCaptureFrameCount: Int
    let capturedFrameCount: Int
    let durationMilliseconds: Int
    let missingTimingMatchFrameCount: Int
    let isSealed: Bool
    let renderReferenceSemantics: String
    let rawMicrophone: ReplayAudioFile
    let renderReference: ReplayAudioFile
    let aecClean: ReplayAudioFile
    let frames: [ReplayFrame]
}

private final class RecordedCleanBackend:
    MacSpeechAECBackend, @unchecked Sendable
{
    private let cleanSamples: [Float]
    private var captureIndex = 0
    private(set) var underflowCount = 0
    private(set) var delayMilliseconds = 0

    init(cleanSamples: [Float]) {
        self.cleanSamples = cleanSamples
    }

    func configure() throws {}

    func processRender(_ samples: [Float]) throws {
        guard samples.count == MacSpeechAcousticEchoHost.frameSampleCount else {
            throw MacSpeechAECBackendError.renderFailed
        }
    }

    func processCapture(_ samples: [Float]) throws
        -> MacSpeechAECCaptureResult {
        let frameSize = MacSpeechAcousticEchoHost.frameSampleCount
        let start = captureIndex * frameSize
        let end = start + frameSize
        guard end <= cleanSamples.count else {
            underflowCount += 1
            throw MacSpeechAECBackendError.captureFailed
        }
        captureIndex += 1
        let clean = Array(cleanSamples[start ..< end])
        return MacSpeechAECCaptureResult(
            processedSamples: clean,
            linearOutputSamples: stride(from: 0, to: clean.count, by: 3)
                .map { index in
                    (clean[index] + clean[index + 1] + clean[index + 2]) / 3
                }
        )
    }

    func setDelay(milliseconds: Int) throws {
        delayMilliseconds = milliseconds
    }

    func reset() throws {
        captureIndex = 0
    }

    func stats() throws -> MacSpeechAECBackendStats {
        MacSpeechAECBackendStats(
            enabled: true,
            active: true,
            estimatedDelayMilliseconds: 0,
            erlDecibels: 20,
            erleDecibels: 3.04
        )
    }

    var consumedFrameCount: Int { captureIndex }
}

private struct ReplayRun: Equatable {
    let classifications: [String]
    let gateOpen: [Bool]
    let timingMatchAvailable: [Bool]
    let alignmentLocked: [Bool]
    let forwardedFrameIndexes: [Int]
    let snapshot: MacSpeechAcousticEchoSnapshot
}

private struct ReplayRenderEvent {
    let hostTimeNanoseconds: UInt64
    let samples: [Float]
}

@main
private struct RecordedAcousticReplay {
    static func main() throws {
        guard CommandLine.arguments.count == 4,
              CommandLine.arguments[2] == "--resident-only",
              let residentOnlyRange = parseRange(CommandLine.arguments[3]) else {
            fputs(
                "usage: RecordedAcousticReplay <sample.aec-frames.json> "
                    + "--resident-only <start:end>\n",
                stderr
            )
            Foundation.exit(64)
        }

        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(
            ReplayManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let directory = manifestURL.deletingLastPathComponent()
        let raw = try loadTrack(
            manifest.rawMicrophone,
            from: directory
        )
        let render = try loadTrack(
            manifest.renderReference,
            from: directory
        )
        let clean = try loadTrack(manifest.aecClean, from: directory)

        try validate(
            manifest: manifest,
            rawSampleCount: raw.count,
            renderSampleCount: render.count,
            cleanSampleCount: clean.count,
            residentOnlyRange: residentOnlyRange
        )

        let runs = try (0 ..< 3).map { _ in
            try replay(
                manifest: manifest,
                raw: raw,
                render: render,
                clean: clean
            )
        }
        guard runs.dropFirst().allSatisfy({ $0 == runs[0] }) else {
            throw ReplayError.nondeterministicReplay
        }

        let result = runs[0]
        let recordedClassifications = manifest.frames.map(\.classifier)
        let recordedGate = manifest.frames.map(\.sourceGateOpen)
        let recordedTiming = manifest.frames.map(\.timingMatchAvailable)
        let recordedAlignment = manifest.frames.map(\.sourceAlignmentLocked)
        let classifierMismatches = mismatchIndexes(
            recordedClassifications,
            result.classifications
        )
        let gateMismatches = mismatchIndexes(recordedGate, result.gateOpen)
        let timingMismatches = mismatchIndexes(
            recordedTiming,
            result.timingMatchAvailable
        )
        let alignmentMismatches = mismatchIndexes(
            recordedAlignment,
            result.alignmentLocked
        )
        let negativeGateFrames = residentOnlyRange.filter {
            result.gateOpen[$0]
        }
        let negativeForwardedFrames = result.forwardedFrameIndexes.filter {
            residentOnlyRange.contains($0)
        }

        let faithfulReplay = classifierMismatches.isEmpty
            && gateMismatches.isEmpty
            && timingMismatches.isEmpty
            && alignmentMismatches.isEmpty
        print("archive_integrity_valid=true")
        print("sample_valid_for_bit_exact_host_replay=false")
        print("failure_reproduced=\(faithfulReplay)")
        print("attempt_id=\(manifest.attemptId.uuidString)")
        print("captured_frames=\(manifest.frames.count)")
        print("duration_ms=\(manifest.durationMilliseconds)")
        print("replay_runs=3")
        print("replay_deterministic=true")
        print("linear_output_source=downsampled_recorded_clean")
        print("render_history=sparse_selected_matches")
        print("bit_exact=false")
        print("recorded_classifier=\(counts(recordedClassifications))")
        print("replay_classifier=\(counts(result.classifications))")
        print("classifier_mismatch_count=\(classifierMismatches.count)")
        print("classifier_mismatch_first=\(prefix(classifierMismatches))")
        print("recorded_gate_open_frames=\(recordedGate.filter { $0 }.count)")
        print("replay_gate_open_frames=\(result.gateOpen.filter { $0 }.count)")
        print("recorded_first_gate_open=\(firstTrue(recordedGate))")
        print("replay_first_gate_open=\(firstTrue(result.gateOpen))")
        print("gate_mismatch_count=\(gateMismatches.count)")
        print("gate_mismatch_first=\(prefix(gateMismatches))")
        print("recorded_timing_match_frames=\(recordedTiming.filter { $0 }.count)")
        print("replay_timing_match_frames=\(result.timingMatchAvailable.filter { $0 }.count)")
        print("timing_mismatch_count=\(timingMismatches.count)")
        print("alignment_mismatch_count=\(alignmentMismatches.count)")
        print("replay_forwarded_frames=\(result.forwardedFrameIndexes.count)")
        print("replay_source_gate_epochs=\(result.snapshot.sourceGateOpenCount)")
        print("resident_only_range=\(residentOnlyRange.lowerBound):\(residentOnlyRange.upperBound)")
        print("resident_only_gate_open_frames=\(negativeGateFrames.count)")
        print("resident_only_forwarded_frames=\(negativeForwardedFrames.count)")
    }

    private static func replay(
        manifest: ReplayManifest,
        raw: [Float],
        render: [Float],
        clean: [Float]
    ) throws -> ReplayRun {
        let backend = RecordedCleanBackend(cleanSamples: clean)
        let host = MacSpeechAcousticEchoHost(
            mode: .webRTCAEC3,
            backend: backend
        )
        guard host.configure() == .webRTCAEC3 else {
            throw ReplayError.hostConfigurationFailed
        }

        let frameSize = MacSpeechAcousticEchoHost.frameSampleCount
        let renderEvents = try makeRenderEvents(
            manifest: manifest,
            render: render
        )
        var renderEventIndex = 0
        var playbackActive = false
        var playbackSequence: UInt64 = 0
        var classifications: [String] = []
        var gateOpen: [Bool] = []
        var timingMatchAvailable: [Bool] = []
        var alignmentLocked: [Bool] = []
        var forwardedFrameIndexes: [Int] = []

        for (index, frame) in manifest.frames.enumerated() {
            if frame.playbackActive,
               !playbackActive || frame.playbackSequence != playbackSequence {
                host.playbackStarted()
            } else if !frame.playbackActive, playbackActive {
                host.playbackCompleted()
            }
            playbackActive = frame.playbackActive
            playbackSequence = frame.playbackSequence

            host.updateDelay(
                outputPresentationLatencySeconds:
                    Double(frame.aecBufferDelayMilliseconds) / 1_000,
                capturePresentationLatencySeconds: 0
            )
            let start = index * frameSize
            let end = start + frameSize
            let captureTimestamp = frame.captureHostTimeNanoseconds
                ?? frame.timestampNanoseconds
            while renderEventIndex < renderEvents.count,
                  renderEvents[renderEventIndex].hostTimeNanoseconds
                    <= captureTimestamp {
                let event = renderEvents[renderEventIndex]
                host.processRender(
                    event.samples,
                    hostTimeNanoseconds: event.hostTimeNanoseconds
                )
                renderEventIndex += 1
            }
            let spans = host.processCaptureSpans(
                Array(raw[start ..< end]),
                hostTimeNanoseconds: captureTimestamp
            )
            let observation = host.acousticObservationSnapshot()
            classifications.append(observation.inputClassification.rawValue)
            gateOpen.append(observation.sourceGateOpen)
            timingMatchAvailable.append(
                observation.renderHostTimeNanoseconds != nil
            )
            alignmentLocked.append(observation.sourceAlignmentLocked)
            forwardedFrameIndexes.append(contentsOf: spans.compactMap {
                guard $0.observation.sourceGateOpen else { return nil }
                return max(0, Int($0.observation.captureFrameIndex) - 1)
            })
        }

        guard backend.consumedFrameCount == manifest.frames.count,
              backend.underflowCount == 0 else {
            throw ReplayError.backendFrameMismatch
        }
        return ReplayRun(
            classifications: classifications,
            gateOpen: gateOpen,
            timingMatchAvailable: timingMatchAvailable,
            alignmentLocked: alignmentLocked,
            forwardedFrameIndexes: forwardedFrameIndexes,
            snapshot: host.snapshot()
        )
    }

    private static func makeRenderEvents(
        manifest: ReplayManifest,
        render: [Float]
    ) throws -> [ReplayRenderEvent] {
        let frameSize = MacSpeechAcousticEchoHost.frameSampleCount
        var samplesByTimestamp: [UInt64: [Float]] = [:]
        for (index, frame) in manifest.frames.enumerated() {
            guard frame.timingMatchAvailable,
                  let timestamp = frame.matchedRenderHostTimeNanoseconds else {
                continue
            }
            let start = index * frameSize
            let samples = Array(render[start ..< start + frameSize])
            if let existing = samplesByTimestamp[timestamp],
               existing != samples {
                throw ReplayError.inconsistentRenderReference
            }
            samplesByTimestamp[timestamp] = samples
        }
        return samplesByTimestamp
            .map {
                ReplayRenderEvent(
                    hostTimeNanoseconds: $0.key,
                    samples: $0.value
                )
            }
            .sorted { $0.hostTimeNanoseconds < $1.hostTimeNanoseconds }
    }

    private static func validate(
        manifest: ReplayManifest,
        rawSampleCount: Int,
        renderSampleCount: Int,
        cleanSampleCount: Int,
        residentOnlyRange: Range<Int>
    ) throws {
        let frameSize = MacSpeechAcousticEchoHost.frameSampleCount
        let expectedSamples = manifest.frames.count * frameSize
        guard manifest.schemaVersion == 1,
              manifest.isSealed,
              manifest.targetCaptureFrameCount == manifest.frames.count,
              manifest.capturedFrameCount == manifest.frames.count,
              manifest.durationMilliseconds
                == manifest.frames.count
                    * MacSpeechAcousticEchoHost.frameDurationMilliseconds,
              rawSampleCount == expectedSamples,
              renderSampleCount == expectedSamples,
              cleanSampleCount == expectedSamples,
              manifest.renderReferenceSemantics
                == "matched_per_capture_frame_zero_when_unavailable",
              residentOnlyRange.lowerBound >= 0,
              residentOnlyRange.upperBound <= manifest.frames.count,
              residentOnlyRange.count >= 23 else {
            throw ReplayError.invalidManifest
        }
        for (index, frame) in manifest.frames.enumerated() {
            guard frame.sampleOffset == index * frameSize,
                  index == 0
                    || frame.timestampNanoseconds
                        > manifest.frames[index - 1].timestampNanoseconds else {
                throw ReplayError.invalidTimeline
            }
        }
        guard manifest.frames.filter({ !$0.timingMatchAvailable }).count
                == manifest.missingTimingMatchFrameCount else {
            throw ReplayError.invalidTimeline
        }
    }

    private static func loadTrack(
        _ descriptor: ReplayAudioFile,
        from directory: URL
    ) throws -> [Float] {
        guard descriptor.sampleRate == MacSpeechAcousticEchoHost.sampleRate,
              descriptor.channelCount == 1,
              descriptor.frameSampleCount
                == MacSpeechAcousticEchoHost.frameSampleCount else {
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
        zip(expected, actual).enumerated().compactMap { index, pair in
            pair.0 == pair.1 ? nil : index
        }
    }

    private static func counts(_ values: [String]) -> String {
        Dictionary(grouping: values, by: { $0 })
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }

    private static func firstTrue(_ values: [Bool]) -> String {
        values.firstIndex(of: true).map(String.init) ?? "none"
    }

    private static func prefix(_ values: [Int]) -> String {
        values.prefix(20).map(String.init).joined(separator: ",")
    }
}

private enum ReplayError: Error {
    case invalidManifest
    case invalidTimeline
    case invalidAudioFormat
    case invalidAudioFile
    case hostConfigurationFailed
    case backendFrameMismatch
    case nondeterministicReplay
    case inconsistentRenderReference
}
