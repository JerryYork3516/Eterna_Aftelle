import Foundation

@main
struct ContinuousProbeMeasurementTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ label: String) throws {
            checks += 1
            guard value else { throw ProbeMeasurementError(code: label) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("probe-measurement-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        var clock = ProbeSampleClock(origin: 1_000_000)
        var previousWakeDeadline = clock.origin
        for index in 0 ..< 10_000 {
            // Controlled late wake-ups; no actual sleeps or network.
            let jitter: UInt64 = [0, 200_000, 1_500_000, 100_000][index % 4]
            try check(clock.deadline == clock.origin + UInt64(index) * 10_000_000, "sample_clock_drift")
            previousWakeDeadline += 10_000_000 + jitter
            clock.advance()
        }
        let oldDrift = previousWakeDeadline - clock.deadline
        try check(oldDrift == 4_500_000_000, "old_pacing_counterexample")
        var drain = ProbePlaybackProgress(lastProgress: 0, played: 0)
        for second in 1 ... 60 {
            let now = UInt64(second) * 1_000_000_000
            drain.observe(played: second * 24_000, now: now)
            try check(!drain.stalled(at: now), "playing_reply_mistaken_for_stall")
        }
        drain.observe(played: 60 * 24_000, now: 99_000_000_000)
        try check(drain.stalled(at: 100_000_000_000), "no_progress_timeout_extended")
        try check(drain.lastProgress == 60_000_000_000, "polling_does_not_extend_watchdog")

        let pcm = Data([0, 0, 0xff, 0x7f])
        let original = "换个问题，请分五点详细解释为什么会下雨，每一点都举一个例子。"
        let url = directory.appendingPathComponent("reference.json")
        let referenceData = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "pcm_sha256": ProbeTranscriptReference.digest(pcm), "text": original])
        try referenceData.write(to: url)
        let reference = try ProbeTranscriptReference.load(from: url, pcm: pcm)
        try check(reference.matches(original), "reference_exact")
        try check(reference.matches(original.replacingOccurrences(of: "，", with: " ")), "punctuation_not_missing_words")
        let truncated = [
            "是为会下雨，每一点都举一个例子。",
            "题，请分五点详细解释为什么会下雨，每一点都举一个例子。",
            "怎么会下雨？每一点都举一个例子。",
            "请分详细解释为什么会下雨，每一点都举一个例子。",
            "五点详细解释为什么会下雨，每一点都举一个例子。",
            "题，请分五点详细解释为什么会下雨，每一点都举一个例子。"
        ]
        var oldFalsePasses = 0
        var newMismatches = 0
        for final in truncated {
            let canonical = final
            if canonical == final { oldFalsePasses += 1 }
            if !reference.matches(final) { newMismatches += 1 }
            try check(!reference.matches(final), "truncation_not_detected")
        }
        try check(!reference.matches(""), "empty_final")
        do {
            _ = try ProbeTranscriptReference.load(from: url, pcm: Data([1, 2]))
            try check(false, "wrong_pcm_reference_accepted")
        } catch let error as ProbeMeasurementError {
            try check(error.code == "reference_pcm_mismatch", "wrong_pcm_reference_reason")
        }

        do {
            let evidence = try ProbeAudioEvidence(directory: directory)
            try evidence.capture(render: [0, 1], gated: [0.5], fields: ["round": 1, "uptime_ns": 100])
            let sequence = try evidence.beginAppend(pcm, round: 1)
            try evidence.event(["event": "send_returned", "sequence": sequence, "uptime_ns": 200])
            let next = try evidence.beginAppend(pcm, round: 2)
            try evidence.event(["event": "send_threw", "sequence": next, "uptime_ns": 300])
            do {
                _ = try evidence.beginAppend(Data([1]), round: 2)
                try check(false, "odd_pcm_accepted")
            } catch let error as ProbeMeasurementError {
                try check(error.code == "outbound_pcm_format", "odd_pcm_reason")
            }
        }
        try check(Data(contentsOf: directory.appendingPathComponent("probe-outbound.s16le.pcm")) == pcm + pcm, "exact_outbound_bytes")
        try check(Data(contentsOf: directory.appendingPathComponent("probe-render.f32le.pcm")) == Data([0, 0, 0, 0, 0, 0, 0x80, 0x3f]), "render_little_endian")
        let records = try String(contentsOf: directory.appendingPathComponent("probe-audio-timeline.ndjson"), encoding: .utf8)
            .split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        let attempts = records.filter { $0["event"] as? String == "append_attempt" }
        try check(attempts.count == 2 && attempts[1]["byte_offset"] as? Int == pcm.count, "outbound_offsets")
        try check(attempts.allSatisfy { $0["sha256"] as? String == ProbeTranscriptReference.digest(pcm) }, "outbound_digest")
        try check(records.filter { $0["event"] as? String == "send_returned" }.count == 1, "send_return_not_server_ack")
        try check(records.filter { $0["event"] as? String == "send_threw" }.count == 1, "failed_append_preserved")
        for name in ["probe-render.f32le.pcm", "probe-gate-output.f32le.pcm", "probe-outbound.s16le.pcm", "probe-audio-timeline.ndjson"] {
            let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)[.posixPermissions] as? Int
            try check(permissions == 0o600, "private_evidence_permissions")
        }
        print("measurement_checks=\(checks) PASS old_clock_drift_ms=\(oldDrift / 1_000_000) new_clock_drift_ms=0")
        print("truncation_counterexamples=\(truncated.count) old_false_passes=\(oldFalsePasses) new_mismatches=\(newMismatches)")
        print("measurement_artifacts=\(directory.path) online=NOT_RUN")
    }
}
