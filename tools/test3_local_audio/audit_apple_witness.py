#!/usr/bin/env python3
"""Recompute saved Apple Host witnesses locally; never access audio devices.

Requires timing schema 2 with actual Host render PCM. NumPy performs direct
sliding dot products over every integer start; math.fsum independently checks
the selected windows. Phone recordings and resident source files are not inputs.
"""

import argparse
import base64
import bisect
import hashlib
import json
import math
from pathlib import Path

import numpy as np


N = 480
RATE = 48000
HISTORY = 51
MAX_DELAY_NS = 500_000_000
CONTINUITY_NS = 2 * 1_000_000_000 // RATE
MIN_RENDER_RMS = 0.005
MIN_LEVEL_RMS = 0.012
MAX_CORRELATION = 0.25
CORRELATION_TOLERANCE = 1e-8
RMS_TOLERANCE = 1e-8
DELAY_TOLERANCE_MS = 1e-6
INPUT_UID = "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1"
OUTPUT_UID = "BuiltInSpeakerDevice"
CONTRACT = {
    "frame_samples": N, "sample_rate": RATE, "history_capacity": HISTORY,
    "max_delay_ns": MAX_DELAY_NS, "continuity_tolerance_ns": CONTINUITY_NS,
    "minimum_render_rms": MIN_RENDER_RMS, "minimum_level_rms": MIN_LEVEL_RMS,
    "maximum_near_end_correlation": MAX_CORRELATION,
    "correlation_tolerance": CORRELATION_TOLERANCE,
    "rms_tolerance": RMS_TOLERANCE, "delay_tolerance_ms": DELAY_TOLERANCE_MS,
    "formula": "abs(centered_capture_dot_render)/sqrt(capture_energy*render_energy)",
    "ranking": "unclipped_product_squared/render_energy; earliest exact maximum",
    "independent_full_search": "NumPy_direct_sliding_dot_products_all_integer_starts_no_FFT_or_pruning",
    "scalar_check": "math.fsum_recomputes_independent_and_recorded_winning_windows",
    "alternative_branch": "not_participating_in_Apple_path",
    "HAL_event_time_field": "current_Capture_aliases_detectorEventNanoseconds_to_cache_read_time",
}


class EvidenceMissing(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise EvidenceMissing(reason)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(data):
    return json.loads(data, parse_constant=lambda value: require(False, "nonfinite_json_" + value))


def scalar_correlation(capture, render):
    mean_x = math.fsum(map(float, capture)) / N
    mean_y = math.fsum(map(float, render)) / N
    x = [float(value) - mean_x for value in capture]
    y = [float(value) - mean_y for value in render]
    ex = math.fsum(value * value for value in x)
    ey = math.fsum(value * value for value in y)
    return min(abs(math.fsum(a * b for a, b in zip(x, y))) / math.sqrt(ex * ey), 1)


def search(capture, history, times, capture_time, playback):
    """Independent direct full-domain search, excluding gaps and future samples."""
    if not playback:
        return {"missing_reason": "playback_inactive"}
    if capture_time is None:
        return {"missing_reason": "capture_time_missing"}
    capture = capture.astype(np.float64)
    centered = capture - math.fsum(map(float, capture)) / N
    energy = math.fsum(float(value) ** 2 for value in centered)
    total = math.fsum(float(value) ** 2 for value in capture)
    if not len(history) or energy <= total * (64 * np.finfo(float).eps * N):
        return {"missing_reason": "insufficient_render_history",
                "search_unavailable_cause": "no_recorded_history" if not len(history) else "capture_no_usable_variance"}

    render = history.astype(np.float64)
    count = len(render) - N + 1
    starts = np.arange(count, dtype=np.int64)
    frame = starts // N
    offset = starts % N
    last = (starts + N - 1) // N
    times = np.asarray(times, dtype=np.int64)
    start_times = times[frame] + offset * 1_000_000_000 // RATE
    sums = np.concatenate(([0.0], np.cumsum(render)))
    squares = np.concatenate(([0.0], np.cumsum(render * render)))
    window_sum = sums[N:] - sums[:-N]
    window_squares = squares[N:] - squares[:-N]
    window_energy = window_squares - window_sum * window_sum / N
    valid = window_energy > window_squares * (64 * np.finfo(float).eps * len(render))
    valid &= window_squares >= N * MIN_RENDER_RMS ** 2
    valid &= (start_times <= capture_time) & (capture_time - start_times <= MAX_DELAY_NS)
    valid &= (last == frame) | (
        (times[last] > times[frame])
        & (np.abs(times[last] - times[frame] - 10_000_000) <= CONTINUITY_NS)
        & (times[last] <= capture_time + (N - offset) * 1_000_000_000 // RATE))
    if not np.any(valid):
        reason = "no_valid_render_window" if np.any(times[frame] <= capture_time) else "render_after_capture"
        return {"missing_reason": reason, "legal_window_count": 0}
    products = np.correlate(render, centered, mode="valid")
    scores = np.full(count, -1.0)
    scores[valid] = products[valid] ** 2 / window_energy[valid]
    winner = int(np.argmax(scores))
    correlation = min(abs(float(products[winner])) / math.sqrt(energy * window_energy[winner]), 1)
    start_time = int(start_times[winner])
    return {
        "start": winner, "start_ns": start_time,
        "offset": winner % N, "delay_ms": (capture_time - start_time) / 1_000_000,
        "correlation": correlation, "legal_window_count": int(np.count_nonzero(valid)),
        "scalar_correlation": scalar_correlation(capture, render[winner:winner + N]),
        "_valid": valid, "_times": start_times, "_scores": scores,
    }


def load_inputs(paths, hashes):
    raw = {}
    for key, path in paths.items():
        require(path.is_file(), "missing_" + key + ":" + str(path))
        raw[key] = path.read_bytes()
        hashes[key] = {"path": str(path), "sha256": digest(raw[key])}
    data = {key: read_json(value) for key, value in raw.items() if key != "processed"}
    timing, decisions = data["timing"], data["decisions"]
    require(timing.get("schema_version") == 2, "timing_schema_2_required_actual_Host_render_PCM")
    require(decisions.get("schemaVersion") == 1, "unsupported_decision_schema")
    require(timing.get("truncated") is False and decisions.get("truncated") is False,
            "truncated_timing_or_decisions")
    require((timing.get("renderPCMFormat"), timing.get("renderSampleRate"),
             timing.get("renderFrameSampleCount")) == ("f32le", RATE, N), "render_format_mismatch")
    require("renderPCM" in timing, "actual_Host_render_PCM_missing")
    render_raw = base64.b64decode(timing["renderPCM"], validate=True)
    require(len(render_raw) % 4 == 0 and len(raw["processed"]) % 4 == 0, "incomplete_float_sample")
    render = np.frombuffer(render_raw, dtype="<f4")
    processed = np.frombuffer(raw["processed"], dtype="<f4")
    require(len(render) == timing.get("renderSampleCount") == len(timing["renderFrames"]) * N,
            "render_sample_identity_incomplete")
    require(len(processed) == decisions.get("processedSampleCount") == len(decisions["frames"]) * N,
            "processed_sample_identity_incomplete")
    require(np.isfinite(render).all() and np.isfinite(processed).all(), "nonfinite_PCM")
    data.update(render=render, processed=processed)
    hashes["decoded_Host_render_PCM"] = {"sha256": digest(render_raw), "sample_count": len(render)}
    return data, hashes


def validate_timeline(timing, decisions):
    renders, captures = timing["renderFrames"], timing["captureFrames"]
    require(len(captures) == len(decisions["frames"]) > 0, "capture_decision_coverage_mismatch")
    for stream in (renders, captures):
        require(all(isinstance(frame.get("arrivalOrdinal"), int) for frame in stream), "arrival_identity_missing")
        require(all(isinstance(frame.get("rms"), (int, float)) and math.isfinite(frame["rms"])
                    and frame["rms"] >= 0 for frame in stream), "nonfinite_or_invalid_frame_RMS")
        require(all(frame.get("hostTimeNanoseconds") is None or
                    type(frame["hostTimeNanoseconds"]) is int and 0 <= frame["hostTimeNanoseconds"] < 2**63
                    for frame in stream), "unsupported_host_time")
        require(all(a["arrivalOrdinal"] < b["arrivalOrdinal"] and a["index"] < b["index"]
                    for a, b in zip(stream, stream[1:])), "frame_order_or_index_gap")
    require(all(a["index"] + 1 == b["index"] for a, b in zip(captures, captures[1:])), "capture_index_gap")
    ordinals = sorted(frame["arrivalOrdinal"] for frame in renders + captures)
    require(ordinals == list(range(1, len(ordinals) + 1)), "arrival_trace_gap_or_duplicate")
    require(all(isinstance(frame.get("hostTimeNanoseconds"), int) for frame in renders), "render_time_missing")
    arrival = [frame["arrivalOrdinal"] for frame in renders]
    for capture, decision in zip(captures, decisions["frames"]):
        require(capture["index"] == decision["captureFrameIndex"]
                and capture.get("hostTimeNanoseconds") == decision.get("hostTimeNanoseconds"),
                "capture_decision_identity_mismatch")
        require(all(type(decision.get(key)) is bool for key in (
            "systemVoiceActivityDetected", "systemVoiceActivityReadValid", "playbackActive", "renderMatchAvailable",
            "voiceActivityQualified", "levelQualified", "separationQualified", "nearEndQualified", "sourceGateOpen")),
            "missing_boolean_decision_field")
        require(isinstance(decision.get("processedRMS"), (int, float))
                and math.isfinite(decision["processedRMS"]) and decision["processedRMS"] >= 0,
                "nonfinite_or_missing_processed_RMS")
        if decision["renderMatchAvailable"]:
            require(all(isinstance(decision.get(key), (int, float)) and math.isfinite(decision[key])
                        for key in ("renderCaptureCorrelation", "renderMatchDelayMilliseconds")),
                    "nonfinite_or_missing_recorded_match")
            require(type(decision.get("renderMatchStartHostTimeNanoseconds")) is int,
                    "recorded_winner_time_missing")
        h = capture.get("renderHistoryFrameCount")
        arrived = bisect.bisect_left(arrival, capture["arrivalOrdinal"])
        require(isinstance(h, int) and 0 <= h <= min(HISTORY, arrived),
                "unrecorded_pre_arm_render_history_or_invalid_history_count")
        require(h == 0 or h == renders[arrived - 1].get("renderHistoryFrameCount"),
                "capture_history_count_differs_from_latest_arrived_render")
    # Each render either appends to the prior history or follows a lifecycle clear.
    previous = 0
    for frame in renders:
        count = frame.get("renderHistoryFrameCount")
        require(count in (1, min(previous + 1, HISTORY)), "unexplained_render_history_count")
        previous = count


def vad_rows(vad):
    require(vad.get("schemaVersion") == 1 and vad.get("truncated") is False,
            "incomplete_or_unsupported_HAL_trace")
    reads = vad.get("reads", [])
    by_sequence = {read["sequence"]: read for read in reads}
    require(len(by_sequence) == len(reads), "duplicate_HAL_read_sequence")
    detector = vad.get("detector", {})
    require(detector.get("truncated") is False, "truncated_HAL_events")
    events = {event["sequence"]: event for event in detector.get("events", [])}
    require(len(events) == len(detector.get("events", [])) == detector.get("eventCount"),
            "duplicate_or_incomplete_HAL_event_sequence")
    return by_sequence, events


def check_vad(frame, reads, events, issues):
    read = reads.get(frame.get("vadSampleSequence"))
    require(read is not None, "missing_consumed_HAL_read")
    require(read.get("captureHostTimeNanoseconds") == frame.get("hostTimeNanoseconds")
            and read.get("sampleCount") == N, "HAL_capture_identity_mismatch")
    capture_time = frame.get("hostTimeNanoseconds")
    read_time = read.get("detectorReadNanoseconds")
    valid = read.get("detectorReadStatus") == 0 and isinstance(read.get("detectorVoiceDetected"), bool)
    if read_time is not None:
        require(capture_time is not None and isinstance(read_time, int) and read_time <= capture_time,
                "HAL_causal_read_identity_missing")
        require(read.get("sampledAtNanoseconds", -1) >= read_time, "HAL_read_after_consumption")
    else:
        require(not valid, "HAL_valid_without_read_identity")
    effective = read.get("effectiveVoiceDetected")
    if effective != read.get("detectorVoiceDetected"):
        issues.append("effective_HAL_differs_from_detector_possible_injection")
    if (frame["systemVoiceActivityReadValid"] != valid
            or frame["systemVoiceActivityDetected"] != (effective is True)):
        issues.append("HAL_consumed_value_mismatch")
    event_sequence = read.get("detectorEventSequence")
    if event_sequence:
        event = events.get(event_sequence)
        require(event is not None, "consumed_HAL_event_missing")
        if any(read.get(key) != event.get(event_key) for key, event_key in (
            ("detectorReadNanoseconds", "readAtNanoseconds"),
            ("detectorReadStatus", "readStatus"), ("detectorVoiceDetected", "state"),
            ("detectorEventNanoseconds", "readAtNanoseconds"))):
            issues.append("HAL_event_identity_mismatch")
    return {"event_sequence": event_sequence, "read_ns": read_time,
            "age_at_capture_ms": (capture_time - read_time) / 1_000_000 if read_time is not None else None, "valid": valid}


def audit(data):
    timing, decisions = data["timing"], data["decisions"]
    validate_timeline(timing, decisions)
    renders = timing["renderFrames"]
    for position, frame in enumerate(renders):
        samples = data["render"][position * N:(position + 1) * N]
        rms = math.sqrt(math.fsum(float(value) ** 2 for value in samples) / N)
        require(abs(rms - frame["rms"]) <= RMS_TOLERANCE, "recorded_render_PCM_RMS_identity_mismatch")
    arrival = [frame["arrivalOrdinal"] for frame in renders]
    reads, events = vad_rows(data["vad"]) if "vad" in data else ({}, {})
    rows = []
    for position, (capture, frame) in enumerate(zip(timing["captureFrames"], decisions["frames"])):
        require(frame.get("processedSampleOffset") == position * N, "processed_offset_gap")
        samples = data["processed"][position * N:(position + 1) * N]
        arrived = bisect.bisect_left(arrival, capture["arrivalOrdinal"])
        h = capture["renderHistoryFrameCount"]
        first = arrived - h
        history = data["render"][first * N:arrived * N]
        times = [entry["hostTimeNanoseconds"] for entry in renders[first:arrived]]
        found = search(samples, history, times, capture.get("hostTimeNanoseconds"), frame["playbackActive"])
        issues = []
        available = "start" in found
        if frame["renderMatchAvailable"] != available:
            issues.append("match_availability_mismatch")
        ambiguous = False
        if available and frame["renderMatchAvailable"]:
            observed = frame.get("renderCaptureCorrelation")
            require(isinstance(observed, (int, float)) and math.isfinite(observed), "missing_recorded_correlation")
            candidates = np.flatnonzero(found["_valid"] & (found["_times"] == frame.get("renderMatchStartHostTimeNanoseconds")))
            if len(candidates) > 1:
                raise EvidenceMissing("nonunique_recorded_witness_time_requires_sample_identity")
            if not len(candidates):
                issues.append("recorded_winner_not_a_legal_window")
            else:
                index = int(candidates[0])
                scalar = scalar_correlation(samples, history[index:index + N])
                found["recorded_witness_scalar_correlation"] = scalar
                found["recorded_witness_global_sample_start"] = first * N + index
                if abs(scalar - observed) > CORRELATION_TOLERANCE:
                    issues.append("recorded_witness_correlation_mismatch")
                if index != found["start"]:
                    if found["correlation"] - scalar > CORRELATION_TOLERANCE:
                        issues.append("recorded_winner_inferior_to_full_search")
                    else:
                        ambiguous = True
            if abs(found["correlation"] - observed) > CORRELATION_TOLERANCE:
                issues.append("maximum_correlation_mismatch")
            if abs(found["scalar_correlation"] - found["correlation"]) > CORRELATION_TOLERANCE:
                issues.append("independent_scalar_vs_sliding_dot_mismatch")
            delay = (capture["hostTimeNanoseconds"] - frame["renderMatchStartHostTimeNanoseconds"]) / 1_000_000
            if abs(delay - frame.get("renderMatchDelayMilliseconds", math.inf)) > DELAY_TOLERANCE_MS:
                issues.append("recorded_delay_identity_mismatch")
        elif not available and not frame["renderMatchAvailable"]:
            if frame.get("renderMatchMissingReason") != found["missing_reason"]:
                issues.append("missing_reference_reason_mismatch")
        rms = math.sqrt(math.fsum(float(value) ** 2 for value in samples) / N)
        if abs(rms - frame["processedRMS"]) > RMS_TOLERANCE or abs(rms - capture["rms"]) > RMS_TOLERANCE:
            issues.append("processed_RMS_mismatch")
        voice = frame["systemVoiceActivityReadValid"] and frame["systemVoiceActivityDetected"]
        level = rms >= MIN_LEVEL_RMS
        separation = not frame["playbackActive"] or (available and found["correlation"] <= MAX_CORRELATION)
        recorded_level = frame["processedRMS"] >= MIN_LEVEL_RMS
        recorded_separation = (not frame["playbackActive"] or
                               (frame["renderMatchAvailable"] and frame["renderCaptureCorrelation"] <= MAX_CORRELATION))
        recorded_expected = {"voiceActivityQualified": voice, "levelQualified": recorded_level,
                             "separationQualified": recorded_separation,
                             "nearEndQualified": voice and recorded_level and recorded_separation}
        for key, value in recorded_expected.items():
            if frame[key] != value:
                issues.append(key + "_recorded_logic_mismatch")
        expected = {"voiceActivityQualified": voice, "levelQualified": level,
                    "separationQualified": separation, "nearEndQualified": voice and level and separation}
        boundary_ambiguous = False
        for key, value in expected.items():
            if frame[key] != value:
                if ((key in ("levelQualified", "nearEndQualified") and abs(rms - MIN_LEVEL_RMS) <= RMS_TOLERANCE)
                        or (key in ("separationQualified", "nearEndQualified") and available
                            and abs(found["correlation"] - MAX_CORRELATION) <= CORRELATION_TOLERANCE)):
                    boundary_ambiguous = True
                else:
                    issues.append(key + "_mismatch")
        blockers = []
        if not frame["systemVoiceActivityReadValid"]:
            blockers.append("HAL_read_invalid")
        elif not frame["systemVoiceActivityDetected"]:
            blockers.append("HAL_false")
        if not level:
            blockers.append("level_below_0.012")
        if frame["playbackActive"] and not available:
            blockers.append("render_unavailable")
        elif not separation:
            blockers.append("render_correlation_above_0.25")
        row = {"capture_frame": frame["captureFrameIndex"], "capture_ns": capture.get("hostTimeNanoseconds"),
               "arrival_ordinal": capture["arrivalOrdinal"], "processed_sample_start": position * N,
               "arrived_render_frames": arrived, "history_frames": h,
               "history_global_sample_range": [first * N, arrived * N],
               "render_arrival_ordinals": [entry["arrivalOrdinal"] for entry in renders[first:arrived]],
               "actual_branch": "Apple", "alternative": "not_participating",
               "recorded": frame, "recomputed": {key: value for key, value in found.items() if not key.startswith("_")},
               "qualification": expected, "blockers": blockers,
               "first_AND_disqualifier": blockers[0] if blockers else None,
               "numerically_ambiguous_winner": ambiguous,
               "numerically_ambiguous_qualification": boundary_ambiguous, "issues": issues}
        if available:
            row["recomputed"]["global_sample_start"] = first * N + found["start"]
            row["recomputed"]["render_frame_index"] = renders[first + found["start"] // N]["index"]
        if "vad" in data:
            row["HAL_cache"] = check_vad(frame, reads, events, issues)
        rows.append(row)
    return rows


def summary(rows):
    return {"frames": len(rows), "mismatch_frames": sum(bool(row["issues"]) for row in rows),
            "ambiguous_winner_frames": sum(row["numerically_ambiguous_winner"] for row in rows),
            "ambiguous_qualification_frames": sum(row["numerically_ambiguous_qualification"] for row in rows),
            "recorded_gate_frames": sum(row["recorded"]["sourceGateOpen"] for row in rows),
            "HAL_consumptions": sum("HAL_cache" in row for row in rows),
            "HAL_distinct_consumed_reads": len({(row["HAL_cache"]["event_sequence"], row["HAL_cache"]["read_ns"])
                                                for row in rows if "HAL_cache" in row}),
            "recorded_qualification": {key: sum(row["recorded"][key] for row in rows) for key in (
                "voiceActivityQualified", "levelQualified", "separationQualified", "nearEndQualified")},
            **{key: sum(row["qualification"][key] for row in rows) for key in (
                "voiceActivityQualified", "levelQualified", "separationQualified", "nearEndQualified")}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timing", default="timing-frames.json")
    parser.add_argument("--decisions", default="apple-decision-frames.json")
    parser.add_argument("--processed", default="apple-processed-48k.f32le.pcm")
    parser.add_argument("--vad", help="HAL reads file; default uses apple-vad-reads.json when present")
    parser.add_argument("--labels", type=Path, help="Evaluation-only frame intervals; never detection input")
    args = parser.parse_args()
    paths = {key: (args.case / getattr(args, key)).resolve() for key in ("timing", "decisions", "processed")}
    vad_path = args.case / (args.vad or "apple-vad-reads.json")
    if args.vad or vad_path.exists():
        paths["vad"] = vad_path.resolve()
    report = {"schema_version": 1, "test3_acceptance": "BLOCKED", "contract": CONTRACT,
              "auditor_sha256": digest(Path(__file__).read_bytes()), "input_hashes": {},
              "HAL_audit": "included" if "vad" in paths else "UNVERIFIED_no_HAL_trace",
              "formal_interruption": "NOT_ASSESSED", "source_attribution_decision": "UNVERIFIED",
              "source_to_running_binary": "UNVERIFIED_requires_run_build_manifest",
              "Gate_confirmation_and_forwarded_PCM": "recorded_only_not_independently_recomputed",
              "HAL_event_arrival_order": "UNVERIFIED_only_cache_read_identity_is_recorded",
              "PCM_and_Gate_mutation": "none"}
    rows = []
    try:
        data, hashes = load_inputs(paths, report["input_hashes"])
        rows = audit(data)
        counts = summary(rows)
        report["summary"] = counts
        report["status"] = ("IMPLEMENTATION_DIFFERENCE" if counts["mismatch_frames"] else
                            "INDETERMINATE_NUMERICS" if counts["ambiguous_winner_frames"] or counts["ambiguous_qualification_frames"] else
                            "MATCH_RECOMPUTED_HAL_UNVERIFIED" if "vad" not in data else
                            "WITNESS_RECOMPUTED")
        report["discontinuities"] = data["timing"].get("discontinuities", [])
        report["segments"] = []
        if args.labels:
            label_raw = args.labels.read_bytes()
            labels = read_json(label_raw)
            require(labels.get("schema_version") == 1, "unsupported_label_schema")
            report["input_hashes"]["evaluation_labels"] = {"path": str(args.labels.resolve()), "sha256": digest(label_raw)}
            for label in labels["segments"]:
                selected = [row for row in rows if label["start_frame"] <= row["capture_frame"] <= label["end_frame"]]
                require(len(selected) == label["end_frame"] - label["start_frame"] + 1, "incomplete_label_frame_coverage")
                report["segments"].append({**label, **summary(selected)})
        result_path = args.case / "result.json"
        report["physical_route"] = "UNVERIFIED_no_runner_result"
        if result_path.is_file():
            raw = result_path.read_bytes()
            result = read_json(raw)
            report["input_hashes"]["runner_result"] = {"path": str(result_path.resolve()), "sha256": digest(raw)}
            route_ok = (result.get("microphone", {}).get("id") == INPUT_UID
                        and result.get("speaker", {}).get("id") == OUTPUT_UID
                        and result.get("physical_route_stayed_exact") is True
                        and result.get("aec_mode") == "appleVoiceProcessing"
                        and result.get("injected_sample_count") == 0)
            report["physical_route"] = "metadata_exact_no_injection" if route_ok else "UNVERIFIED_route_or_injection"
    except (EvidenceMissing, KeyError, ValueError, TypeError) as error:
        report["status"] = "INSUFFICIENT_EVIDENCE"
        report["reason"] = str(error)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name in ("report.json", "frames.json", "report.md"):
        if (output / name).exists():
            parser.error("refusing to replace existing audit artifact: " + str(output / name))
    report_json = json.dumps(report, indent=2, allow_nan=False) + "\n"
    frames_json = json.dumps(rows, indent=2, allow_nan=False) + "\n"
    (output / "report.json").write_text(report_json)
    (output / "frames.json").write_text(frames_json)
    (output / "report.md").write_text(
        "# Test3 Apple witness audit\n\nStatus: **" + report["status"] + "**\n\n"
        + "Test3/03: **BLOCKED**. Witness consistency does not establish source attribution or formal interruption.\n\n"
        + "HAL: " + report["HAL_audit"] + ".\n\n"
        + ("Reason: " + report["reason"] + "\n\n" if "reason" in report else "")
        + "```json\n" + json.dumps(report.get("summary", {}), indent=2) + "\n```\n\n"
        + "All capture frames are retained in frames.json; no PCM is copied to this report.\n")
    print(json.dumps({"status": report["status"], "summary": report.get("summary"), "reason": report.get("reason"),
                      "report": str(output / "report.md"), "test3_acceptance": "BLOCKED"}))
    return 0 if report["status"] in ("WITNESS_RECOMPUTED", "MATCH_RECOMPUTED_HAL_UNVERIFIED") else 2


if __name__ == "__main__":
    raise SystemExit(main())
