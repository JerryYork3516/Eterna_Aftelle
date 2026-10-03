#!/usr/bin/env python3
"""Audit Test3 physical timing without granting source or Runtime authority."""

import argparse
import hashlib
import json
import math
from pathlib import Path


INPUT_UID = "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1"
OUTPUT_UID = "BuiltInSpeakerDevice"
FRAME_NS = 10_000_000
MIN_RENDER_OVERLAP_NS = 50_000_000


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def load_case(folder):
    result = read_json(folder / "result.json")
    aggregate_path = folder.parent / "result.json"
    if aggregate_path.exists():
        aggregate = read_json(aggregate_path)
        result["_resident_sha256"] = aggregate.get("resident_sha256")
    events_path = folder / "causal-candidate-events.json"
    trace_path = folder / "timing-frames.json"
    return (result,
            read_json(events_path) if events_path.exists() else [],
            read_json(trace_path) if trace_path.exists() else None)


def environment_errors(result, observation=False):
    errors = []
    if result.get("microphone", {}).get("id") != INPUT_UID:
        errors.append("wrong_input_uid")
    if result.get("speaker", {}).get("id") != OUTPUT_UID:
        errors.append("wrong_output_uid")
    if result.get("aec_mode") != "appleVoiceProcessing" or result.get("aec_fallback_count") != 0:
        errors.append("apple_voice_processing_unavailable")
    if result.get("physical_route_stayed_exact") is not True:
        errors.append("route_changed")
    if result.get("playback_capture_coverage_ms", 0) < 8_000 or result.get(
            "maximum_capture_gap_ms", float("inf")) > 200:
        errors.append("incomplete_capture")
    if result.get("playback_started_at_ns") is None or result.get(
            "input_is_capturing_at_end") is not True:
        errors.append("playback_or_input_unavailable")
    if result.get("injected_sample_count") != 0 or result.get(
            "fixture_semantic_proposal_at_ns") is not None:
        errors.append("software_or_semantic_injection")
    if result.get("near_delivery") not in ("none", "external_source_unverified"):
        errors.append("nonphysical_near_delivery")
    if observation and (result.get("physical_observation") is not True
                        or result.get("status") not in ("UNVERIFIED", "FAIL")):
        errors.append("not_physical_observation")
    if not observation and result.get("physical_echo_only") is not True:
        errors.append("not_physical_echo_control")
    return errors


def negative_status(results):
    rows = []
    for result in results:
        errors = environment_errors(result)
        if result.get("interrupt_count", 0) or result.get("clear_count", 0):
            status = "FAIL_FORMAL"
        elif errors:
            status = "FAIL_ENV"
        elif result.get("provisional_pause_count", 0) or result.get(
                "playback_forwarded_activity", 0) or result.get("playback_gate_activity", 0):
            status = "FAIL_FALSE_CANDIDATE"
        elif result.get("status") not in ("PASS", "UNVERIFIED") or result.get(
                "failures") or result.get("error"):
            status = "FAIL_RUN"
        else:
            status = "UNVERIFIED_ECHO_COUPLING"
        rows.append({"case": result.get("case"), "status": status,
                     "environment_errors": errors,
                     "physical_echo_coupling": "UNVERIFIED",
                     "provisional_pause_count": result.get("provisional_pause_count"),
                     "formal_interrupt_count": result.get("interrupt_count")})
    return rows


def verify_file(path, expected_hash):
    return (isinstance(expected_hash, str) and path.is_file()
            and len(expected_hash) == 64
            and hashlib.sha256(path.read_bytes()).hexdigest() == expected_hash)


def load_reference(path):
    reference = read_json(path)
    if reference.get("schema_version") != 1 or reference.get(
            "source_kind") != "live_human_near_mouth":
        raise ValueError("Independent live-human reference is missing")
    if reference.get("alignment_method") not in (
            "same_host_clock_second_mic", "shared_acoustic_anchor"):
        raise ValueError("Independent clock alignment is missing")
    if not isinstance(reference.get("recording_file"), str):
        raise ValueError("Independent recording is missing")
    recording = Path(reference["recording_file"])
    if not recording.is_absolute():
        recording = path.parent / recording
    if not verify_file(recording, reference.get("recording_sha256", "")):
        raise ValueError("Independent recording hash does not match")
    if reference["alignment_method"] == "shared_acoustic_anchor":
        if not isinstance(reference.get("alignment_evidence_file"), str):
            raise ValueError("Shared-anchor evidence is missing")
        evidence = Path(reference["alignment_evidence_file"])
        if not evidence.is_absolute():
            evidence = path.parent / evidence
        if not verify_file(evidence, reference.get("alignment_evidence_sha256", "")):
            raise ValueError("Shared-anchor evidence hash does not match")
    error = reference.get("alignment_max_error_ns")
    intervals = reference.get("voice_intervals_host_ns")
    if not isinstance(error, int) or error < 0 or not isinstance(intervals, list):
        raise ValueError("Clock error or voice intervals are missing")
    if any(not isinstance(item, dict) or item.get("kind") not in ("short", "long")
           or not isinstance(item.get("start_ns"), int)
           or not isinstance(item.get("end_ns"), int)
           for item in intervals):
        raise ValueError("Voice intervals are malformed")
    reference["_audio_reference_status"] = "UNVERIFIED"
    return reference


def overlap(first, second):
    return max(0, min(first[1], second[1]) - max(first[0], second[0]))


def valid_trace(trace):
    if not trace or trace.get("schema_version") != 1 or trace.get("truncated") is not False:
        return False
    for name in ("renderFrames", "captureFrames"):
        frames = trace.get(name, [])
        if len(frames) < 800 or any(not isinstance(frame.get("index"), int)
                             or not isinstance(frame.get("hostTimeNanoseconds"), int)
                             or not isinstance(frame.get("rms"), (int, float))
                             or not math.isfinite(frame["rms"])
                             for frame in frames):
            return False
        if any(next_frame["index"] <= frame["index"] or
               (name == "captureFrames" and next_frame["index"] != frame["index"] + 1)
               or abs(next_frame["hostTimeNanoseconds"] - frame["hostTimeNanoseconds"]
                      - (next_frame["index"] - frame["index"]) * FRAME_NS) > 2_000_000
               for frame, next_frame in zip(frames, frames[1:])):
            return False
    return True


def event_window(event):
    frames = event.get("qualifyingFiveFrames", [])
    if len(frames) != 5 or event.get("pauseAccepted") is not True:
        return None
    if any(not isinstance(frame.get("index"), int)
           or not isinstance(frame.get("hostTimeNanoseconds"), int)
           for frame in frames):
        return None
    if any(next_frame["index"] != frame["index"] + 1 or
           not 9_999_999 <= next_frame["hostTimeNanoseconds"]
           - frame["hostTimeNanoseconds"] <= 10_000_001
           for frame, next_frame in zip(frames, frames[1:])):
        return None
    window = (frames[0]["hostTimeNanoseconds"],
              frames[-1]["hostTimeNanoseconds"] + FRAME_NS)
    packet_time = event.get("packetTimestampNanoseconds")
    if not isinstance(packet_time, int) or not window[0] - 20_000_000 <= packet_time <= window[1] + 300_000_000:
        return None
    return window


def load_echo_annotation(path, alignment_path, observation_folder):
    annotation = read_json(path)
    alignment = read_json(alignment_path)
    expected_case = f"{observation_folder.parent.name}/{observation_folder.name}"
    phone = Path(alignment.get("phone_file", ""))
    result_path = observation_folder / "result.json"
    if (annotation.get("schema_version") != 1
            or alignment.get("schema_version") != 1
            or annotation.get("case") != expected_case
            or annotation.get("phone_file_sha256") != alignment.get("phone_sha256")
            or not verify_file(phone, alignment.get("phone_sha256", ""))
            or not verify_file(result_path, alignment.get("positive_case_sha256", ""))):
        raise ValueError("Echo-only annotation is not bound to this recording and case")
    interval = annotation.get("user_confirmed_echo_only_phone_seconds")
    mapped = annotation.get("mapped_accepted_candidate_phone_seconds")
    if (not isinstance(interval, list) or len(interval) != 2
            or not isinstance(mapped, list) or len(mapped) != 2
            or any(not isinstance(value, (int, float)) or not math.isfinite(value)
                   for value in interval + mapped)
            or interval[0] >= interval[1] or mapped[0] >= mapped[1]
            or not isinstance(alignment.get("positive_render_first_host_ns"), int)
            or not isinstance(alignment.get("phone_positive_refined_seconds"), (int, float))
            or not math.isfinite(alignment["phone_positive_refined_seconds"])):
        raise ValueError("Echo-only annotation or alignment is malformed")
    return {"interval": interval, "mapped": mapped,
            "render_host_ns": alignment["positive_render_first_host_ns"],
            "phone_render_seconds": alignment["phone_positive_refined_seconds"]}


def annotated_echo_candidate(result, events, trace, annotation):
    if trace["renderFrames"][0]["hostTimeNanoseconds"] != annotation["render_host_ns"]:
        raise ValueError("Echo-only alignment does not match the render trace")
    accepted = [event for event in events if event.get("pauseAccepted") is True]
    if len(accepted) != result.get("provisional_pause_count"):
        raise ValueError("Echo-only candidate count does not match the run")
    capture_times = {frame["index"]: frame["hostTimeNanoseconds"]
                     for frame in trace["captureFrames"]}
    interval = annotation["interval"]
    expected = annotation["mapped"]
    for event in accepted:
        window = event_window(event)
        if window is None or any(capture_times.get(frame["index"])
                                 != frame["hostTimeNanoseconds"]
                                 for frame in event["qualifyingFiveFrames"]):
            raise ValueError("Echo-only candidate does not match the capture trace")
        mapped = [annotation["phone_render_seconds"]
                  + (time - annotation["render_host_ns"]) / 1e9 for time in window]
        if all(abs(actual - saved) <= 0.005 for actual, saved in zip(mapped, expected)):
            if mapped[0] < interval[0] + 0.1 or mapped[1] > interval[1] - 0.1:
                raise ValueError("Echo-only label has insufficient timing margin")
            return mapped
    raise ValueError("Echo-only annotation does not match an accepted candidate")


def positive_status(result, events, trace, reference, echo_annotation=None):
    errors = environment_errors(result, observation=True)
    if result.get("interrupt_count", 0) or result.get("clear_count", 0):
        return {"status": "FAIL_UNVERIFIED_FORMAL", "environment_errors": errors}
    if errors:
        return {"status": "FAIL_ENV", "environment_errors": errors}
    if result.get("status") != "UNVERIFIED" or result.get("failures") or result.get("error"):
        return {"status": "FAIL_RUN", "environment_errors": []}
    if not valid_trace(trace):
        return {"status": "UNVERIFIED_TIMING_TRACE", "environment_errors": []}
    if echo_annotation is not None:
        mapped = annotated_echo_candidate(result, events, trace, echo_annotation)
        return {"status": "FAIL_FALSE_CANDIDATE", "environment_errors": [],
                "user_confirmed_echo_only_phone_seconds": echo_annotation["interval"],
                "accepted_candidate_phone_seconds": mapped,
                "scope": "automatic provisional candidate only; formal Decision remains unverified"}
    if reference is None or reference.get("_audio_reference_status") == "UNVERIFIED":
        return {"status": "UNVERIFIED_SOURCE_REFERENCE", "environment_errors": []}
    error = reference["alignment_max_error_ns"]
    intervals = reference["voice_intervals_host_ns"]
    if not {"short", "long"}.issubset({item.get("kind") for item in intervals}):
        return {"status": "UNVERIFIED_UTTERANCE_SET", "environment_errors": []}
    if any(not isinstance(item.get("start_ns"), int)
           or not isinstance(item.get("end_ns"), int)
           or item["end_ns"] <= item["start_ns"] for item in intervals):
        return {"status": "UNVERIFIED_SOURCE_REFERENCE", "environment_errors": []}
    render_reference = [(frame["hostTimeNanoseconds"],
                         frame["hostTimeNanoseconds"] + FRAME_NS)
                        for frame in trace["renderFrames"] if frame["rms"] > 0]
    windows = [event_window(event) for event in events]
    if any(window is None for event, window in zip(events, windows)
           if event.get("pauseAccepted") is True):
        return {"status": "UNVERIFIED_CANDIDATE_TIMING", "environment_errors": []}
    capture_by_index = {frame["index"]: frame["hostTimeNanoseconds"]
                        for frame in trace["captureFrames"]}
    if any(any(capture_by_index.get(frame["index"])
               != frame["hostTimeNanoseconds"]
               for frame in event.get("qualifyingFiveFrames", []))
           for event in events if event.get("pauseAccepted") is True):
        return {"status": "UNVERIFIED_CANDIDATE_TIMING", "environment_errors": []}
    accepted = [window for window in windows if window is not None]
    earliest_voice = min(item["start_ns"] - error for item in intervals)
    if any(window[1] <= earliest_voice for window in accepted):
        return {"status": "FAIL_EARLY_CANDIDATE", "environment_errors": []}
    possible_voice = [(item["start_ns"] - error,
                       item["end_ns"] + error) for item in intervals]
    if any(not any(overlap(window, voice) > 0 for voice in possible_voice)
           for window in accepted):
        return {"status": "FAIL_UNMATCHED_CANDIDATE", "environment_errors": []}
    rows = []
    for item in intervals:
        start, end = item.get("start_ns"), item.get("end_ns")
        duration = end - start
        if (item["kind"] == "short" and not 300_000_000 <= duration <= 600_000_000
                or item["kind"] == "long" and duration < 1_000_000_000):
            return {"status": "INVALID_UTTERANCE_DURATION", "environment_errors": []}
        certain_voice = (start + error, end - error)
        render_overlap = sum(overlap(certain_voice, frame)
                             for frame in render_reference)
        covered = any(overlap(certain_voice, window) > 0 for window in accepted)
        rows.append({"kind": item["kind"], "duration_ms": duration / 1e6,
                     "guaranteed_render_reference_overlap_ms": render_overlap / 1e6,
                     "automatic_candidate_covered": covered})
    if any(row["guaranteed_render_reference_overlap_ms"]
           < MIN_RENDER_OVERLAP_NS / 1e6
           for row in rows):
        status = "INVALID_TIMING"
    elif any(not row["automatic_candidate_covered"] for row in rows):
        status = "FAIL_COVERAGE"
    else:
        status = "UNVERIFIED_SOURCE_ANNOTATION"
    return {"status": status, "environment_errors": [], "utterances": rows,
            "source_annotation_provenance": "UNVERIFIED",
            "speaker_audibility": "UNVERIFIED"}


def pairing_status(negative_results, observation):
    if observation is None:
        return "UNVERIFIED_NO_POSITIVE_RUN"
    positive_result = observation[0]
    cases = [*negative_results, positive_result]
    hashes = [case.get("_resident_sha256") for case in cases]
    gains = [case.get("resident_gain") for case in cases]
    if any(not isinstance(value, str) or len(value) != 64 for value in hashes):
        return "UNVERIFIED_FIXTURE_HASH"
    if len(set(hashes)) != 1 or len(set(gains)) != 1:
        return "FAIL_FIXTURE_OR_GAIN_MISMATCH"
    return "UNVERIFIED_SYSTEM_VOLUME_AND_POSITION"


def audit(negative_results, observation=None, reference=None, echo_annotation=None):
    negatives = negative_status(negative_results)
    positive = ({"status": "UNVERIFIED_NO_OBSERVATION"}
                if observation is None else positive_status(*observation, reference,
                                                            echo_annotation))
    failed_negative = next((row["status"] for row in negatives
                            if row["status"].startswith("FAIL")), None)
    pairing = pairing_status(negative_results, observation)
    return {"schema_version": 1, "audit": "physical_timing_only",
            "negative_controls": negatives, "positive": positive,
            "pairing_status": pairing,
            "overall": failed_negative or (pairing if pairing.startswith("FAIL")
                                          else positive["status"]),
            "source_attribution_decision": "UNVERIFIED",
            "test3": "BLOCKED",
            "limit": "Render reference does not prove audible speaker output or microphone coupling. "
                     "Independent voice annotation, clock alignment, device level and position "
                     "require separate verification. Candidate timing never authorizes "
                     "formal Runtime interruption."}


def self_test():
    base = {"case": "apple_physical_echo_only", "microphone": {"id": INPUT_UID},
            "speaker": {"id": OUTPUT_UID}, "aec_mode": "appleVoiceProcessing",
            "aec_fallback_count": 0, "physical_route_stayed_exact": True,
            "playback_capture_coverage_ms": 10_400, "maximum_capture_gap_ms": 100,
            "playback_started_at_ns": 10_000_000, "input_is_capturing_at_end": True,
            "injected_sample_count": 0, "fixture_semantic_proposal_at_ns": None,
            "near_delivery": "none", "physical_echo_only": True,
            "provisional_pause_count": 0, "interrupt_count": 0, "clear_count": 0,
            "status": "PASS", "failures": []}
    observation = {**base, "case": "apple_physical_observation",
                   "physical_echo_only": False, "physical_observation": True,
                   "near_delivery": "external_source_unverified", "status": "UNVERIFIED"}
    trace = {"schema_version": 1, "truncated": False,
             "renderFrames": [{"index": i, "hostTimeNanoseconds": i * FRAME_NS,
                               "rms": 0.1} for i in range(1, 1201)],
             "captureFrames": [{"index": i, "hostTimeNanoseconds": i * FRAME_NS,
                                "rms": 0.02} for i in range(1, 1201)]}
    reference = {"alignment_max_error_ns": 5_000_000,
                 "voice_intervals_host_ns": [
                     {"kind": "short", "start_ns": 500_000_000, "end_ns": 900_000_000},
                     {"kind": "long", "start_ns": 1_100_000_000,
                      "end_ns": 2_100_000_000}]}
    def event(index):
        return {"pauseAccepted": True,
                "packetTimestampNanoseconds": index * FRAME_NS + 40_000_000,
                "qualifyingFiveFrames": [
                    {"index": index + j, "hostTimeNanoseconds": (index + j) * FRAME_NS}
                    for j in range(5)]}
    assert positive_status(observation, [event(60), event(130)], trace, reference)[
        "status"] == "UNVERIFIED_SOURCE_ANNOTATION"
    assert positive_status(observation, [event(60), {**event(130),
                            "qualifyingFiveFrames": [
                                {**frame, "index": frame["index"] + 1_000}
                                for frame in event(130)["qualifyingFiveFrames"]]}],
                           trace, reference)["status"] == "UNVERIFIED_CANDIDATE_TIMING"
    assert positive_status(observation, [event(60)], trace, reference)[
        "status"] == "FAIL_COVERAGE"
    assert positive_status(observation, [event(20), event(60), event(130)], trace,
                           reference)["status"] == "FAIL_EARLY_CANDIDATE"
    assert positive_status(observation, [event(60), event(100), event(130)], trace,
                           reference)["status"] == "FAIL_UNMATCHED_CANDIDATE"
    assert positive_status(observation, [event(60), event(130)], trace,
                           {**reference, "alignment_max_error_ns": 250_000_000})[
                               "status"] == "INVALID_TIMING"
    assert positive_status(observation, [event(60), event(130)],
                           {**trace, "renderFrames": [
                               {**frame, "hostTimeNanoseconds": frame["hostTimeNanoseconds"] // 2}
                               for frame in trace["renderFrames"]]}, reference)[
                                   "status"] == "UNVERIFIED_TIMING_TRACE"
    assert valid_trace({**trace, "renderFrames": [
        frame for frame in trace["renderFrames"] if not 110 <= frame["index"] <= 130]})
    assert positive_status(observation, [], trace, None)["status"] == "UNVERIFIED_SOURCE_REFERENCE"
    assert positive_status(observation, [event(60)], trace,
                           {**reference, "_audio_reference_status": "UNVERIFIED"})[
                               "status"] == "UNVERIFIED_SOURCE_REFERENCE"
    assert positive_status({**observation, "provisional_pause_count": 1},
                           [event(60)], trace, None,
                           {"interval": [0.4, 0.9], "mapped": [0.6, 0.65],
                            "render_host_ns": FRAME_NS,
                            "phone_render_seconds": 0.01})["status"] == "FAIL_FALSE_CANDIDATE"
    assert positive_status({**observation, "microphone": {"id": "28U1"}}, [], trace,
                           reference)["status"] == "FAIL_ENV"
    assert positive_status({**observation, "injected_sample_count": 1}, [], trace,
                           reference)["status"] == "FAIL_ENV"
    assert negative_status([{**base, "provisional_pause_count": 1}])[0][
        "status"] == "FAIL_FALSE_CANDIDATE"
    assert negative_status([{**base, "interrupt_count": 1}])[0]["status"] == "FAIL_FORMAL"
    assert negative_status([{**base, "status": "FAIL",
                             "failures": ["unknown failure"]}])[0]["status"] == "FAIL_RUN"
    assert negative_status([base])[0]["status"] == "UNVERIFIED_ECHO_COUPLING"
    assert positive_status({**observation, "status": "FAIL",
                            "failures": ["unknown failure"]},
                           [event(60), event(130)], trace, reference)["status"] == "FAIL_RUN"
    assert audit([{**base, "provisional_pause_count": 1}],
                 (observation, [event(60), event(130)], trace),
                 reference)["overall"] == "FAIL_FALSE_CANDIDATE"
    assert pairing_status([{"_resident_sha256": "a" * 64, "resident_gain": 0.5}],
                          ({"_resident_sha256": "b" * 64, "resident_gain": 0.5}, [], None)) \
        == "FAIL_FIXTURE_OR_GAIN_MISMATCH"
    print("audit_test3_live_overlap_self_test=PASS cases=20")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--negative", type=Path, action="append")
    parser.add_argument("--observation", type=Path)
    parser.add_argument("--source-reference", type=Path)
    parser.add_argument("--echo-only-annotation", type=Path)
    parser.add_argument("--phone-alignment", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.negative:
        parser.error("At least one --negative control is required")
    if args.source_reference and not args.observation:
        parser.error("--source-reference requires --observation")
    if bool(args.echo_only_annotation) != bool(args.phone_alignment) or (
            args.echo_only_annotation and not args.observation):
        parser.error("Echo-only annotation requires --observation and --phone-alignment")
    if args.output is None or args.output.exists():
        parser.error("Choose a new --output path; existing evidence is preserved")
    result = audit([load_case(folder)[0] for folder in args.negative],
                   load_case(args.observation) if args.observation else None,
                   load_reference(args.source_reference) if args.source_reference else None,
                   load_echo_annotation(args.echo_only_annotation, args.phone_alignment,
                                        args.observation) if args.echo_only_annotation else None)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(result["overall"], args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
