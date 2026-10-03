#!/usr/bin/env python3
"""Check whether a physical Test3 pair can support a short-speech claim.

This audits saved evidence only. It neither runs a Decision nor grants formal
interruption authority.
"""

import argparse
from array import array
import json
from pathlib import Path
import sys


INPUT_UID = "AppleUSBAudioEngine:Timesintelli:USB Microphone:123482:1"
OUTPUT_UID = "BuiltInSpeakerDevice"
TRACKS = ("pre-Apple-input-candidate", "processed", "output-render-reference")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def inspect_capture(path, scenario):
    result = read_json(path / "result.json")
    restore = read_json(path / "restore.json")
    problems = []
    if result["scenario"] != scenario:
        problems.append("scenario_mismatch")
    if result["input"]["uid"] != INPUT_UID or result["output"]["uid"] != OUTPUT_UID:
        problems.append("device_uid_mismatch")
    if (result["input_unit_device"] != result["input"]["id"]
            or result["output_unit_device"] != result["output"]["id"]):
        problems.append("audio_unit_binding_mismatch")
    started = next((event for event in result["events"]
                    if event["kind"] == "engine_started"), None)
    if (not started or not started["input_vp"]
            or not started["output_vp"] or started["bypassed"]):
        problems.append("apple_voice_processing_inactive")
    if not restore["restored"] or restore["errors"]:
        problems.append("device_defaults_not_restored")
    clipping = {}
    for name in TRACKS:
        track = result["tracks"][name]
        chunks = track["chunks"]
        if track["overflow_callbacks"] or track["invalid_timestamps"]:
            problems.append(name + "_capture_error")
        if not chunks or chunks[0]["offset"] != 0:
            problems.append(name + "_missing_chunks")
        else:
            for previous, current in zip(chunks, chunks[1:]):
                if current["offset"] != previous["offset"] + previous["frames"]:
                    problems.append(name + "_sample_gap")
                    break
                if (current["sample_time"] != previous["sample_time"]
                        + previous["frames"]
                        or current["host_ns"] <= previous["host_ns"]):
                    problems.append(name + "_clock_discontinuity")
                    break
            if chunks[-1]["offset"] + chunks[-1]["frames"] != track["frames"]:
                problems.append(name + "_frame_count_mismatch")
        pcm = path / (name + ".f32le.pcm")
        if pcm.stat().st_size != track["frames"] * 4:
            problems.append(name + "_pcm_size_mismatch")
        samples = array("f")
        samples.frombytes(pcm.read_bytes())
        if sys.byteorder != "little":
            samples.byteswap()
        clipping[name] = sum(abs(sample) >= 0.999 for sample in samples)
    return result, problems, clipping


def overlap_ns(first, second):
    return max(0, min(first[1], second[1]) - max(first[0], second[0]))


def first_yield_host_ns(result):
    return next(event["host_ns"] for event in result["events"]
                if event["kind"] == "provisional_yield_0_started")


def audit(calibration, negative, positive):
    calibration_run, calibration_errors, calibration_clip = inspect_capture(
        calibration, "phone-only")
    negative_run, negative_errors, negative_clip = inspect_capture(
        negative, "phone-pure-echo")
    positive_run, positive_errors, positive_clip = inspect_capture(
        positive, "phone-mixed")
    alignment = read_json(positive / "physical-source-alignment.json")
    source = read_json(positive / "source-alignment.json")
    calibration_source = read_json(calibration / "source-alignment.json")
    negative_decision = read_json(negative / "decision.json")
    positive_decision = read_json(positive / "decision.json")
    template = alignment["source_template_seconds"]
    voice_start = alignment["mixed_raw_peaks"][0]["voice_start_host_ns"]
    calibration_voice_start = calibration_source["correlation_peaks"][0][
        "physical_voice_start_host_ns"]
    source_start = source["correlation_peaks"][0]["physical_voice_start_host_ns"]
    voice_interval = [voice_start, voice_start + (template[1] - template[0]) * 1e9]
    trials = []
    for trial in positive_decision["trials"]:
        window = trial["evidence_window_ns"]
        trials.append({
            "outcome": trial["outcome"],
            "evidence_window_ns": window,
            "voice_overlap_ms": overlap_ns(window, voice_interval) / 1e6,
            "candidate_precedes_voice_ms":
                (voice_start - window[1]) / 1e6
                if trial["outcome"] == "CONFIRM_CANDIDATE" and window[1] < voice_start
                else None,
        })
    negative_candidates = sum(trial["outcome"] == "CONFIRM_CANDIDATE"
                              for trial in negative_decision["trials"])
    positive_candidates = sum(trial["outcome"] == "CONFIRM_CANDIDATE"
                              for trial in positive_decision["trials"])
    covered = any(trial["voice_overlap_ms"] > 0 for trial in trials)
    acquisition_errors = (calibration_errors + negative_errors + positive_errors)
    if acquisition_errors:
        timing_status = "INVALID_ACQUISITION"
    elif not covered:
        timing_status = "INVALID_TIMING"
    elif not any(trial["outcome"] == "CONFIRM_CANDIDATE"
                 and trial["voice_overlap_ms"] > 0 for trial in trials):
        timing_status = "MISSED_POSITIVE"
    else:
        timing_status = "TIMING_CANDIDATE_ONLY"
    return {
        "schema_version": 1,
        "audit": "physical_timing_only",
        "capture_route": "Timesintelli USB microphone + Mac built-in speaker",
        "acquisition_errors": acquisition_errors,
        "clipped_samples_by_run": {
            "calibration": calibration_clip,
            "negative": negative_clip,
            "positive": positive_clip,
        },
        "voice_interval_host_ns": voice_interval,
        "voice_start_method_difference_ms": (voice_start - source_start) / 1e6,
        "calibration_voice_relative_to_first_yield_ms":
            (calibration_voice_start - first_yield_host_ns(calibration_run)) / 1e6,
        "positive_voice_relative_to_first_yield_ms":
            (voice_start - first_yield_host_ns(positive_run)) / 1e6,
        "calibration_player_started_host_ns": next(
            event["host_ns"] for event in calibration_run["events"]
            if event["kind"] == "player_started"),
        "negative_candidates": negative_candidates,
        "positive_candidates": positive_candidates,
        "positive_trials": trials,
        "positive_timing_status": timing_status,
        "isolated_candidate_timing_status":
            "NON_TARGET_CANDIDATE" if any(
                trial["candidate_precedes_voice_ms"] is not None
                for trial in trials) else "NO_EARLY_CANDIDATE",
        "isolated_negative_status": "FAILED_CANDIDATE" if negative_candidates
            else "NO_CANDIDATE_IN_THIS_RUN",
        "automatic_trigger_exercised": False,
        "runtime_executed": bool(negative_decision["runtime_executed"]
                                 or positive_decision["runtime_executed"]),
        "formal_actions": negative_decision["formal_actions"]
                          + positive_decision["formal_actions"],
        "test3_acceptance": "NOT_ESTABLISHED_BY_THIS_AUDIT",
        "limits": "pre-Apple input is mixed; phone playback is not live speech; "
                  "post-render reference is digital, not a measured speaker waveform",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("calibration", type=Path)
    parser.add_argument("negative", type=Path)
    parser.add_argument("positive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = audit(args.calibration, args.negative, args.positive)
    if args.output.exists():
        parser.error("Output exists; preserve prior audit and choose a new path")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n",
                           encoding="utf-8")
    print(result["positive_timing_status"], args.output)
    timing_qualified = result["positive_timing_status"] == "TIMING_CANDIDATE_ONLY"
    controls_clean = (result["negative_candidates"] == 0
                      and result["isolated_candidate_timing_status"]
                      == "NO_EARLY_CANDIDATE")
    return 0 if timing_qualified and controls_clean else 1


if __name__ == "__main__":
    raise SystemExit(main())
