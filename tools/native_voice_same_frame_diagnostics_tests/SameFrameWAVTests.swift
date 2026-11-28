import Darwin
import Foundation

extension SameFrameTests {
    static func captureFromExistingWorker() async throws {
        let (transport, hardware) = graph(channelCount: 1, interleaved: false, rate: 24000, diagnostics: true)
        try await transport.start(identity: captureIdentity)
        let context = hardware.update { $0.graphs[0].read().lease!.context }
        var recording = NativeVoiceSameFrameCapture(identity: captureIdentity.capture)
        var expected = Data()
        for index in 0 ..< 750 {
            let samples = (0 ..< 480).map { frame in Float((index + frame) % 127 - 63) / 128 }
            inject([samples], into: context, at: index * 480, rate: 24000, interleaved: false)
            let batch = try await transport.bridgeService(maxCaptureFrames: 2048)
            if index == 0 {
                check(batch.packets.first?.timingStatus == .unknown, "uncertain host time does not drop content")
            }
            recording.append(batch.packets)
            expected.append(NativeVoicePCM16.encode(samples))
        }
        await transport.close()
        let take = recording.finish(endedNormally: true)
        check(take.summary.state == .complete && take.summary.frames == 360_000, "15 real seconds from existing Worker")
        check(take.summary.sampleRate == 24000 && take.summary.bitsPerSample == 16 && take.summary.channels == 1,
              "standard WAV PCM format")
        let matchesIdentity = take.summary.identity == captureIdentity.capture
        check(take.summary.segment == 0 && take.summary.firstSampleCount == 0 && matchesIdentity,
              "file content origin matches technical packet identity")
        check(take.pcm?.count == 720_000 && take.pcm == expected, "all captured PCM bytes kept in order")
        recording.append([captureTestPacket(at: 360_000)])
        check(!recording.needsPackets && recording.finish(endedNormally: true).pcm == expected,
              "excess data cannot extend or overwrite the retained 15 seconds")
        let stopped = recording.finish(endedNormally: false)
        check(stopped.pcm == nil && stopped.summary.state == .stopped, "aborted session cannot produce WAV")
    }

    private static func captureTestPacket(
        at sample: UInt64, segment: UInt64 = 0, bytes: Int = 960,
        identity: NativeVoiceIdentity.Capture = captureIdentity.capture
    ) -> NativeVoiceCapturePacket {
        .init(bytes: Data(repeating: 0x12, count: bytes), identity: identity, segment: segment,
              sampleCount: sample, hostTimeNanoseconds: nil, timingStatus: .unknown)
    }

    static func captureRejectsGaps() {
        var capture = NativeVoiceSameFrameCapture(identity: captureIdentity.capture)
        let prefix = (0 ..< 749).map { captureTestPacket(at: UInt64($0 * 480)) }
        capture.append(prefix)
        let partial = capture.finish(endedNormally: true)
        check(partial.summary.state == .incomplete && partial.pcm == nil
            && partial.summary.frames == 359_520, "a missing final packet is never zero padded")

        let other = NativeVoiceIdentity(
            authority: .init(runtimeGeneration: 1, routeEpoch: 1, configurationID: 10),
            captureGeneration: 2, captureToken: 2, playbackEpoch: 1, playbackToken: 1
        )
        let invalidPackets = [captureTestPacket(at: 960), captureTestPacket(at: 0),
                              captureTestPacket(at: 480, segment: 1), captureTestPacket(at: 480, bytes: 958),
                              captureTestPacket(at: 480, identity: other.capture)]
        for bad in invalidPackets {
            var broken = NativeVoiceSameFrameCapture(identity: captureIdentity.capture)
            broken.append([captureTestPacket(at: 0), bad, captureTestPacket(at: 480)])
            let result = broken.finish(endedNormally: true)
            check(result.summary.state == .discontinuous && result.pcm == nil && !broken.needsPackets,
                  "gaps, duplicates, wrong size, and changed identity forbid a padded or resumed WAV")
        }
    }

    static func localEvidencePublication() throws {
        let files = NativeVoiceSameFrameFiles.self
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: root) }

        let parent = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        check(parent >= 0, "authorized test root")
        defer { close(parent) }

        let folder = root.appendingPathComponent(files.folderName)
        try rejectSymlinkFolder(parent: parent, folder: folder)
        let directory = try files.openFolder(in: parent)
        defer { close(directory) }
        try files.checkWritable(in: directory)
        try check(manager.contentsOfDirectory(atPath: folder.path).isEmpty, "preflight leaves no artifacts")

        let manifest = Data("{\"captureWAV\":\"test\"}".utf8)
        let bytes = Data(repeating: 0x56, count: 720_044)
        let run = UUID()
        try files.publish(json: manifest, wav: bytes, runID: run, in: directory)
        let bundle = folder.appendingPathComponent(files.trialName(run))
        let wav = bundle.appendingPathComponent(files.wavName)
        let json = bundle.appendingPathComponent(files.jsonName)
        try check(Data(contentsOf: wav) == bytes && Data(contentsOf: json) == manifest,
                  "both files are published with byte identity")
        for (url, permissions) in [(folder, 0o700), (bundle, 0o700), (wav, 0o600), (json, 0o600)] {
            let attributes = try manager.attributesOfItem(atPath: url.path)
            check(attributes[.posixPermissions] as? Int == permissions, "private directory and file modes")
        }
        do {
            try files.publish(json: Data("replacement".utf8), wav: nil, runID: run, in: directory)
            check(false, "cannot replace published trial")
        } catch {
            try check(Data(contentsOf: wav) == bytes && Data(contentsOf: json) == manifest,
                      "failed duplicate publication preserves the original pair")
        }

        let statsOnly = UUID()
        try files.publish(json: manifest, wav: nil, runID: statsOnly, in: directory)
        let statsFolder = folder.appendingPathComponent(files.trialName(statsOnly))
        try check(manager.contentsOfDirectory(atPath: statsFolder.path) == [files.jsonName],
                  "statistics-only preserves JSON without WAV")
        try check(manager.contentsOfDirectory(atPath: folder.path).count == 2, "failed publish leaves no staging files")
    }

    private static func rejectSymlinkFolder(parent: Int32, folder: URL) throws {
        let files = NativeVoiceSameFrameFiles.self
        let manager = FileManager.default
        let outside = folder.deletingLastPathComponent().appendingPathComponent("outside")
        try manager.createDirectory(at: outside, withIntermediateDirectories: false)
        try manager.createSymbolicLink(at: folder, withDestinationURL: outside)
        do {
            let unexpected = try files.openFolder(in: parent)
            close(unexpected)
            check(false, "cannot follow a symlink to another directory")
        } catch {
            try check(manager.contentsOfDirectory(atPath: outside.path).isEmpty, "no escape through symlink")
        }
        try manager.removeItem(at: folder)
    }
}
