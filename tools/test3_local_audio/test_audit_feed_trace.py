#!/usr/bin/env python3
"""Silent failure-boundary checks for the Test3 feed trace auditor."""

import json
from pathlib import Path
import tempfile
import unittest

from audit_feed_trace import audit


class FeedTraceAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.case = Path(self.temporary.name)
        self.result = {
            "physical_echo_only": True, "status": "UNVERIFIED", "failures": [],
            "microphone": {"id": "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1"},
            "speaker": {"id": "BuiltInSpeakerDevice"},
            "physical_route_stayed_exact": True,
            "aec_mode": "appleVoiceProcessing", "aec_fallback_count": 0,
            "input_is_capturing_at_end": True, "output_state": "playing",
            "output_error": None, "playback_started_at_ns": 1_000_000_000,
            "audio_feed_payload_duration_ms": 100,
            "audio_feed_source_frames_per_chunk": 4800,
            "audio_feed_payload_frames_per_chunk": 2400,
            "resident_source_sample_count": 504000,
            "audio_feed_overdue_chunk_count": 0,
            "audio_feed_max_late_ms": 0,
            "audio_feed_source_wrap_count": 0,
        }
        self.feed = []
        self.provider = []
        self.playback = []
        for index in range(105):
            sequence = index + 1
            target = 1_000_000_000 + index * 100_000_000
            self.feed.append({
                "audio_sequence": sequence, "source_offset_48k": index * 4800,
                "target_enqueue_at_ns": target, "producer_observed_at_ns": target,
                "late_by_ns": 0, "payload_sha256": "0" * 64,
                "payload_rms_10ms": [0.1] * 10,
            })
            self.provider.extend([
                {"sequence": sequence, "kind": "enqueued", "time": target + 1,
                 "queueDepth": 0},
                {"sequence": sequence, "kind": "received", "time": target + 2,
                 "queueDepth": 0},
            ])
            self.playback.extend([
                {"sequence": sequence, "kind": "enqueue_requested",
                 "time": target + 3, "generation": 1},
                {"sequence": sequence, "kind": "scheduled",
                 "time": target + 4, "generation": 1},
            ])
        self.timing = {
            "truncated": False,
            "renderFrames": [
                {"hostTimeNanoseconds": 1_000_000_000 + index * 10_000_000,
                 "rms": 0.1}
                for index in range(801)
            ],
            "captureFrames": [
                {"hostTimeNanoseconds": 1_000_000_000 + index * 10_000_000,
                 "rms": 0.0}
                for index in range(801)
            ],
        }
        self.result["timing_render_frame_count"] = 801
        self.result["timing_capture_frame_count"] = 801
        self.save()

    def tearDown(self):
        self.temporary.cleanup()

    def save(self):
        for name, value in (
            ("result.json", self.result),
            ("audio-feed-events.json", self.feed),
            ("provider-audio-events.json", self.provider),
            ("playback-events.json", self.playback),
            ("timing-frames.json", self.timing),
        ):
            (self.case / name).write_text(json.dumps(value), encoding="utf-8")

    def test_complete_trace_does_not_grant_source_attribution(self):
        report = audit(self.case)
        self.assertEqual(report["status"], "VALID_FEED_TRACE_ONLY")
        self.assertEqual(report["source_attribution_decision"], "UNVERIFIED")
        self.assertEqual(report["content_alignment"], "UNVERIFIED")

    def test_catch_up_burst_invalidates_timing(self):
        self.feed[1]["producer_observed_at_ns"] += 95_000_000
        self.feed[1]["late_by_ns"] += 95_000_000
        for event in self.provider + self.playback:
            if event["sequence"] == 2:
                event["time"] += 95_000_000
        self.result["audio_feed_max_late_ms"] = 95
        self.save()
        report = audit(self.case)
        self.assertEqual(report["status"], "INVALID_FEED_TIMING")
        self.assertEqual(report["feed_short_interval_count"], 1)

    def test_one_render_frame_is_incomplete(self):
        self.timing["renderFrames"] = self.timing["renderFrames"][:1]
        self.result["timing_render_frame_count"] = 1
        self.save()
        self.assertEqual(audit(self.case)["status"], "INCOMPLETE_TRACE")

    def test_runner_failure_is_not_a_valid_trace(self):
        self.result["status"] = "FAIL"
        self.result["failures"] = ["capture missing"]
        self.save()
        self.assertEqual(audit(self.case)["status"], "RUNNER_FAILED")

    def test_mismatched_source_offset_invalidates_trace(self):
        self.feed[1]["source_offset_48k"] = 0
        self.save()
        self.assertEqual(audit(self.case)["status"], "INVALID_TRACE")

    def test_old_evidence_stays_unverified(self):
        (self.case / "audio-feed-events.json").unlink()
        self.assertEqual(audit(self.case)["status"], "UNVERIFIED_LEGACY_TRACE")


if __name__ == "__main__":
    unittest.main()
