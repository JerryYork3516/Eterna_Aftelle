import CryptoKit
import Foundation

struct ProbeMeasurementError: Error { let code: String }

// Deadlines are anchored to the sample clock, not the previous wake-up.
struct ProbeSampleClock {
    let origin: UInt64
    private(set) var frameIndex: UInt64 = 0
    var deadline: UInt64 { origin + frameIndex * 10_000_000 }
    mutating func advance() { frameIndex += 1 }
}

struct ProbePlaybackProgress {
    private(set) var lastProgress: UInt64
    private(set) var played: Int
    mutating func observe(played: Int, now: UInt64) {
        if played > self.played { lastProgress = now }
        self.played = played
    }
    func stalled(at now: UInt64) -> Bool { now - lastProgress >= 40_000_000_000 }
}

struct ProbeTranscriptReference: Decodable {
    let schema_version: Int
    let pcm_sha256: String
    let text: String

    static func load(from url: URL, pcm: Data) throws -> Self {
        let data = try Data(contentsOf: url)
        guard data.count <= 16_384 else { throw ProbeMeasurementError(code: "reference_too_large") }
        let reference = try JSONDecoder().decode(Self.self, from: data)
        guard reference.schema_version == 1, !normalized(reference.text).isEmpty,
              reference.pcm_sha256 == digest(pcm) else {
            throw ProbeMeasurementError(code: "reference_pcm_mismatch")
        }
        return reference
    }

    static func normalized(_ text: String) -> String {
        String(text.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
        })
    }

    func matches(_ actual: String) -> Bool { Self.normalized(text) == Self.normalized(actual) }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// Opt-in, local-only evidence. No microphone, credentials, context, or wire IDs.
// send_returned means transport admission, not server receipt or write ACK.
final class ProbeAudioEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private let render: FileHandle
    private let gate: FileHandle
    private let outbound: FileHandle
    private let timeline: FileHandle
    private var byteCount = 0
    private var renderOffset = 0
    private var gateOffset = 0
    private var outboundOffset = 0
    private var appendSequence = 0

    init(directory: URL) throws {
        func create(_ name: String) throws -> FileHandle {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                attributes: [.posixPermissions: 0o600]) else {
                throw ProbeMeasurementError(code: "audio_evidence_create_failed")
            }
            return try FileHandle(forWritingTo: url)
        }
        render = try create("probe-render.f32le.pcm")
        gate = try create("probe-gate-output.f32le.pcm")
        outbound = try create("probe-outbound.s16le.pcm")
        timeline = try create("probe-audio-timeline.ndjson")
        try event(["event": "formats", "schema_version": 1, "render_rate": 48_000,
            "gate_rate": 48_000, "outbound_rate": 16_000, "channels": 1,
            "byte_order": "little_endian", "clock": "DispatchTime.uptimeNanoseconds",
            "aec_backend": "FIXTURE_NOT_WEBRTC"])
    }

    deinit {
        try? render.close(); try? gate.close(); try? outbound.close(); try? timeline.close()
    }

    func capture(render samples: [Float], gated: [Float], fields: [String: Any]) throws {
        try lock.withLock {
            func pcm(_ values: [Float]) -> Data {
                let bits = values.map { $0.bitPattern.littleEndian }
                return bits.withUnsafeBytes { Data($0) }
            }
            var record = fields
            record["event"] = "capture"
            record["render_sample_offset"] = renderOffset
            record["render_sample_count"] = samples.count
            record["gate_sample_offset"] = gateOffset
            record["gate_sample_count"] = gated.count
            try append(pcm(samples), to: render)
            try append(pcm(gated), to: gate)
            try line(record)
            renderOffset += samples.count
            gateOffset += gated.count
        }
    }

    func beginAppend(_ pcm: Data, round: Int) throws -> Int {
        try lock.withLock {
            guard pcm.count.isMultiple(of: 2) else { throw ProbeMeasurementError(code: "outbound_pcm_format") }
            appendSequence += 1
            try append(pcm, to: outbound)
            try line(["event": "append_attempt", "sequence": appendSequence, "round": round,
                "uptime_ns": DispatchTime.now().uptimeNanoseconds,
                "byte_offset": outboundOffset, "byte_count": pcm.count,
                "sha256": ProbeTranscriptReference.digest(pcm)])
            outboundOffset += pcm.count
            return appendSequence
        }
    }

    func event(_ record: [String: Any]) throws { try lock.withLock { try line(record) } }

    private func line(_ record: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        data.append(10)
        try append(data, to: timeline)
    }

    private func append(_ data: Data, to file: FileHandle) throws {
        guard byteCount + data.count <= 320_000_000 else {
            throw ProbeMeasurementError(code: "audio_evidence_capacity_exceeded")
        }
        try file.write(contentsOf: data)
        byteCount += data.count
    }
}
