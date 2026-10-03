#!/usr/bin/env python3
"""Audit a saved Test3 runner feed without using audio devices."""

import argparse
import json
import math
from pathlib import Path
import statistics


FILES = ("audio-feed-events.json", "provider-audio-events.json",
         "playback-events.json", "timing-frames.json")
INPUT_UID = "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1"
OUTPUT_UID = "BuiltInSpeakerDevice"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def audit(case):
    result = read_json(case / "result.json")
    missing = [name for name in FILES if not (case / name).is_file()]
    if missing:
        return {"schema_version": 1, "status": "UNVERIFIED_LEGACY_TRACE",
                "missing": missing, "test3_acceptance": "BLOCKED"}

    feed, provider, playback, timing = (read_json(case / name) for name in FILES)
    errors = []
    incomplete = []
    count = len(feed)
    chunk_ns = 100_000_000
    if not (result.get("physical_echo_only") or result.get("physical_observation")):
        errors.append("not_a_physical_route_case")
    if (result.get("microphone", {}).get("id") != INPUT_UID
            or result.get("speaker", {}).get("id") != OUTPUT_UID
            or result.get("physical_route_stayed_exact") is not True):
        errors.append("physical_route_mismatch")
    if (result.get("aec_mode") != "appleVoiceProcessing"
            or result.get("aec_fallback_count") != 0
            or result.get("input_is_capturing_at_end") is not True):
        incomplete.append("capture_or_aec_unavailable")
    if count != 105:
        incomplete.append("expected_105_audio_chunks")
    if (result.get("audio_feed_payload_duration_ms") != 100
            or result.get("audio_feed_source_frames_per_chunk") != 4800
            or result.get("audio_feed_payload_frames_per_chunk") != 2400):
        errors.append("payload_clock_contract_mismatch")
    source_count = result.get("resident_source_sample_count", 0)
    if not isinstance(source_count, int) or source_count <= 0:
        errors.append("missing_source_sample_count")

    overdue = 0
    max_late_ns = 0
    for index, entry in enumerate(feed):
        if entry["audio_sequence"] != index + 1:
            errors.append("feed_sequence_gap")
        if entry["source_offset_48k"] != index * 4800:
            errors.append("source_offset_mismatch")
        if index and entry["target_enqueue_at_ns"] - feed[index - 1]["target_enqueue_at_ns"] != chunk_ns:
            errors.append("feed_target_spacing_mismatch")
        late = entry["producer_observed_at_ns"] - entry["target_enqueue_at_ns"]
        if late < 0 or late != entry["late_by_ns"]:
            errors.append("feed_lateness_mismatch")
        overdue += late >= chunk_ns
        max_late_ns = max(max_late_ns, late)
        digest = entry.get("payload_sha256", "")
        if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
            errors.append("missing_payload_hash")
        rms = entry.get("payload_rms_10ms", [])
        if len(rms) != 10 or any(not isinstance(value, (int, float))
                                 or not math.isfinite(value) or value < 0 for value in rms):
            errors.append("missing_content_envelope")

    if result.get("audio_feed_overdue_chunk_count") != overdue:
        errors.append("overdue_count_mismatch")
    if abs(result.get("audio_feed_max_late_ms", -1) - max_late_ns / 1_000_000) > 0.000001:
        errors.append("maximum_lateness_mismatch")
    if source_count > 0:
        wraps = (count * 4800 - 1) // source_count if count else 0
        if result.get("audio_feed_source_wrap_count") != wraps:
            errors.append("source_wrap_count_mismatch")
    else:
        wraps = None

    by_provider = {}
    for event in provider:
        by_provider.setdefault(event["sequence"], {}).setdefault(event["kind"], []).append(event)
    if set(by_provider) - set(range(1, count + 1)):
        errors.append("provider_sequence_outside_feed")
    provider_depth = 0
    provider_wait_ns = []
    provider_enqueued_at = {}
    received_at = {}
    for entry in feed:
        sequence = entry["audio_sequence"]
        stages = by_provider.get(sequence, {})
        enqueued = stages.get("enqueued", [])
        received = stages.get("received", [])
        if len(enqueued) != 1 or len(received) != 1:
            errors.append("provider_event_pair_mismatch")
            continue
        first, second = enqueued[0], received[0]
        if not (entry["producer_observed_at_ns"] <= first["time"] <= second["time"]):
            errors.append("provider_event_order_mismatch")
        provider_depth = max(provider_depth, first["queueDepth"])
        provider_wait_ns.append(second["time"] - first["time"])
        provider_enqueued_at[sequence] = first["time"]
        received_at[sequence] = second["time"]
    enqueue_intervals = [provider_enqueued_at[sequence + 1] - provider_enqueued_at[sequence]
                         for sequence in range(1, count)
                         if sequence in provider_enqueued_at
                         and sequence + 1 in provider_enqueued_at]
    short_intervals = sum(interval < 50_000_000 for interval in enqueue_intervals)
    long_intervals = sum(interval > 150_000_000 for interval in enqueue_intervals)
    actual_lateness = [provider_enqueued_at[entry["audio_sequence"]]
                       - entry["target_enqueue_at_ns"] for entry in feed
                       if entry["audio_sequence"] in provider_enqueued_at]
    actual_overdue = sum(late >= chunk_ns for late in actual_lateness)

    requests = {}
    scheduled = {}
    for event in playback:
        if event["kind"] == "enqueue_requested":
            requests.setdefault(event["sequence"], []).append(event["time"])
        elif event["kind"] == "scheduled":
            scheduled.setdefault(event["sequence"], []).append(event["time"])
    if not requests or not scheduled:
        incomplete.append("missing_output_progress")
    if set(requests) - set(range(1, count + 1)):
        errors.append("output_sequence_outside_feed")
    for sequence in range(1, count + 1):
        if len(requests.get(sequence, [])) != 1 or len(scheduled.get(sequence, [])) != 1:
            incomplete.append("output_sequence_not_one_to_one")
    generations = {event.get("generation") for event in playback
                   if event["kind"] in ("enqueue_requested", "scheduled")}
    if len(generations) != 1:
        errors.append("output_generation_mismatch")
    bridge_waits = []
    for sequence, times in requests.items():
        if sequence not in received_at or min(times) < received_at[sequence]:
            errors.append("output_request_before_provider_receipt")
        else:
            bridge_waits.append((sequence, min(times) - received_at[sequence]))
    bridge_waits.sort()
    bridge_head = [delay for _, delay in bridge_waits[:10]]
    bridge_tail = [delay for _, delay in bridge_waits[-10:]]
    output_wait_ns = []
    for sequence, times in scheduled.items():
        matching = requests.get(sequence, [])
        if not matching or min(matching) > min(times):
            errors.append("output_schedule_without_enqueue_request")
        else:
            output_wait_ns.append(min(times) - min(matching))

    render = timing.get("renderFrames", [])
    capture = timing.get("captureFrames", [])
    if timing.get("truncated") is not False:
        incomplete.append("timing_trace_truncated")
    if (len(render) != result.get("timing_render_frame_count")
            or len(capture) != result.get("timing_capture_frame_count")):
        errors.append("timing_frame_count_mismatch")
    for name, frames in (("render", render), ("capture", capture)):
        times = [frame["hostTimeNanoseconds"] for frame in frames]
        gaps = [later - earlier for earlier, later in zip(times, times[1:])]
        if (len(frames) < 800 or not times or times[-1] - times[0] < 8_000_000_000
                or any(gap <= 0 or gap > 200_000_000 for gap in gaps)):
            incomplete.append(name + "_coverage_under_8s_or_gap_over_200ms")
    if not any(frame["rms"] > 0 for frame in render):
        incomplete.append("no_render_activity")
    if (result.get("output_error") is not None
            or result.get("output_state") not in ("playing", "completed")
            or not result.get("playback_started_at_ns")):
        incomplete.append("playback_render_not_verified")
    status = ("INVALID_TRACE" if errors else
              "INCOMPLETE_TRACE" if incomplete else
              "INVALID_FEED_TIMING" if overdue or actual_overdue
              or short_intervals or long_intervals else
              "RUNNER_FAILED" if result.get("status") != "UNVERIFIED"
              or result.get("failures") else "VALID_FEED_TRACE_ONLY")
    return {
        "schema_version": 1, "status": status,
        "errors": sorted(set(errors)), "feed_chunk_count": count,
        "incomplete": sorted(set(incomplete)),
        "runner_status": result.get("status"),
        "runner_failures": result.get("failures"),
        "feed_overdue_chunk_count": overdue,
        "feed_max_late_ms": max_late_ns / 1_000_000,
        "feed_actual_provider_overdue_count": actual_overdue,
        "feed_actual_provider_max_late_ms": max(actual_lateness, default=0) / 1_000_000,
        "feed_min_provider_enqueue_interval_ms": min(enqueue_intervals, default=0) / 1_000_000,
        "feed_short_interval_count": short_intervals,
        "feed_long_interval_count": long_intervals,
        "source_wrap_count": wraps,
        "provider_max_queue_depth": provider_depth,
        "provider_max_wait_ms": max(provider_wait_ns, default=0) / 1_000_000,
        "provider_receive_to_output_request_max_ms": max(
            (delay for _, delay in bridge_waits), default=0) / 1_000_000,
        "provider_receive_to_output_request_median_ms": statistics.median(
            delay for _, delay in bridge_waits) / 1_000_000 if bridge_waits else None,
        "provider_receive_to_output_request_tail_growth_ms": (
            statistics.median(bridge_tail) - statistics.median(bridge_head)
        ) / 1_000_000 if bridge_head and bridge_tail else None,
        "output_max_enqueue_to_schedule_attempt_ms": max(output_wait_ns, default=0) / 1_000_000,
        "output_underrun_count": result.get("output_underrun_count"),
        "render_frame_count": len(render),
        "capture_frame_count": len(capture),
        "source_sample_rate": "ASSUMED_48_KHZ_RAW_PCM",
        "content_alignment": "UNVERIFIED",
        "source_repetition": "YES" if wraps else "NO",
        "source_attribution_decision": "UNVERIFIED",
        "test3_acceptance": "BLOCKED",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output exists; preserve prior evidence")
    report = audit(args.case)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                           encoding="utf-8")
    print(report["status"], args.output)
    return 0 if report["status"] == "VALID_FEED_TRACE_ONLY" else 1


if __name__ == "__main__":
    raise SystemExit(main())
