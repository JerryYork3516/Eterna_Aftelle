#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
exec /usr/bin/python3 - "$repo_root" "$@" <<'PY'
import argparse
from array import array
import datetime
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import uuid

repo = Path(sys.argv[1])
parser = argparse.ArgumentParser(description="Silent Test 3 capsule replay; no devices or provider calls.")
parser.add_argument("inputs", nargs="+", type=Path, help="Case directory or a run's evidence directory")
args = parser.parse_args(sys.argv[2:])
cases = []
for item in args.inputs:
    item = item.resolve()
    candidates = [item] if (item / "audio-calls.json").is_file() else sorted(item.glob("*/audio-calls.json"))
    if not candidates:
        parser.error("No local audio capsules: " + str(item))
    cases.extend(candidate if candidate.is_dir() else candidate.parent for candidate in candidates)
cases = list(dict.fromkeys(cases))
run_id = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
output = repo / ".build/test3-silent-replay" / run_id
output.mkdir(parents=True)
sources = [repo / "apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift",
           repo / "tools/speech_aec_host_tests/RecordedAcousticReplay.swift",
           repo / "tools/test3_local_audio/replay.sh"]
required = ["initial-state.json", "final-state.json", "audio-calls.json", "control-events.json",
            "capture-frames.json", "render-frames.json", "result.json",
            "raw-mic-48k.f32le.pcm", "render-48k.f32le.pcm", "clean-48k.f32le.pcm", "linear-16k.f32le.pcm"]


def digest(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def near_coverage(case, target):
    metadata = json.loads((case / "result.json").read_text())
    if metadata.get("case") not in ("normal_software_near", "higher_software_near"):
        return {"status": "NOT_APPLICABLE"}
    launcher = json.loads((case.parent.parent / "launcher-result.json").read_text())
    source = launcher["inputs"]["near"]
    source_data = Path(source["path"]).read_bytes()
    if hashlib.sha256(source_data).hexdigest() != source["sha256"] or len(source_data) % 4:
        raise ValueError("Near source hash or encoding mismatch")
    near = array("f")
    near.frombytes(source_data)
    if sys.byteorder != "little":
        near.byteswap()
    if not near or not all(math.isfinite(value) for value in near):
        raise ValueError("Invalid near source samples")
    initial = json.loads((case / "initial-state.json").read_text())
    if initial["captureFIFOSamples"] or initial["captureFrameCount"] != 0:
        raise ValueError("Near source coverage requires an empty initial capture FIFO")
    calls = json.loads((case / "audio-calls.json").read_text())
    frames = json.loads((target / "capture-frames.json").read_text())
    raw_count = (case / "raw-mic-48k.f32le.pcm").stat().st_size // 4
    truth = array("f", [0]) * raw_count
    cursor, started = 0, None
    for call in sorted(calls, key=lambda item: item["ordinal"]):
        if call["kind"] != "capture" or cursor == len(near):
            continue
        timestamp, size = call["hostTimeNanoseconds"], call["sampleCount"]
        offset = 0
        if started is None and timestamp < metadata["injection_scheduled_at_ns"]:
            remaining = (metadata["injection_scheduled_at_ns"] - timestamp) * 48000 / 1e9
            if remaining >= size:
                continue
            offset = math.ceil(remaining)
        if offset >= size:
            continue
        if started is None:
            started = timestamp + int(offset * 1e9 / 48000)
        count = min(size - offset, len(near) - cursor)
        destination = call["sampleOffset"] + offset
        if destination < 0 or destination + count > raw_count:
            raise ValueError("Near source exceeds capture bounds")
        truth[destination:destination + count] = near[cursor:cursor + count]
        cursor += count
    if started != metadata["injection_started_at_ns"] or cursor != metadata["injected_sample_count"] or cursor != len(near):
        raise ValueError("Near injection start or sample count mismatch")
    delay = initial["processedOutputDelaySamples"] * 3
    if not 0 <= delay < 480 or len(frames) * 480 > raw_count:
        raise ValueError("Unsupported output alignment")
    emitted = bytearray(len(frames) * 480)
    duplicates = []
    for frame in frames:
        for span in frame["emittedSpans"]:
            if span["silenced"]:
                continue
            start = (span["captureFrameIndex"] - 1) * 480
            if start < 0 or start + 480 > len(emitted):
                raise ValueError("Emitted source frame out of bounds")
            if any(emitted[start:start + 480]):
                duplicates.append(span["captureFrameIndex"])
            emitted[start:start + 480] = b"\x01" * 480
    active, missing, truncated = [], [], []
    for index in range(len(frames)):
        samples = truth[index * 480:(index + 1) * 480]
        # Same independent activity convention as silent_doubletalk, not Host labels.
        if math.sqrt(sum(value * value for value in samples) / 480) < 0.006:
            continue
        active.append(index + 1)
        start = index * 480 + delay
        if start + 480 > len(emitted):
            truncated.append(index + 1)
        elif not all(emitted[start:start + 480]):
            missing.append(index + 1)
    return {"status": "PASS" if active and not missing and not truncated and not duplicates else "FAIL",
            "known_active_source_frames": len(active), "missing_source_ids": missing,
            "truncated_source_ids": truncated, "duplicate_source_ids": duplicates,
            "source_sha256_verified": True, "injection_reproduced": True,
            "processed_output_delay_samples_48k": delay,
            "limits": "Independent source coverage only; does not prove AEC signal preservation, word intelligibility or physical double-talk."}


def bounded(command, log, timeout):
    with log.open("w") as handle:
        try:
            return subprocess.run(command, cwd=repo, stdout=handle, stderr=subprocess.STDOUT,
                                  timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            return 124


summary = {"schema_version": 1, "mode": "recorded_aec_outputs_current_host",
           "status": "INCOMPLETE", "test3_acceptance": "NOT_ESTABLISHED_BY_REPLAY",
           "qwen_calls": 0, "device_playback": False, "device_capture": False,
           "cases": [], "artifacts": str(output)}
source_hashes = digest(sources)
summary["source_sha256"] = source_hashes
binary = output / "replay"
build = bounded(["/usr/bin/xcrun", "swiftc", "-O", "-D", "DEBUG", "-parse-as-library",
                 "-warn-concurrency", "-strict-concurrency=complete", "-module-cache-path",
                 str(output / "module-cache"), *[str(source) for source in sources if source.suffix == ".swift"], "-o", str(binary)],
                output / "build.log", 180)
summary["build_exit_code"] = build
if build == 0:
    for index, case in enumerate(cases):
        result = {"source": str(case), "status": "ERROR"}
        target = output / (str(index + 1).zfill(2) + "-" + case.name)
        try:
            before = digest([case / name for name in required])
            code = bounded([str(binary), "--local-capsule", str(case), str(target)],
                           output / (target.name + ".log"), 120)
            result["exit_code"] = code
            if code == 0:
                result.update(json.loads((target / "result.json").read_text()))
                result["legacy_status"] = result["status"]
                result["near_source_coverage"] = near_coverage(case, target)
                if result["near_source_coverage"]["status"] == "FAIL":
                    result["status"] = "FAIL"
            result["input_sha256"] = before
            result["input_unchanged"] = before == digest([case / name for name in required])
            if not result["input_unchanged"]:
                result["status"] = "ERROR"
        except (OSError, ValueError, KeyError, TypeError) as error:
            result["status"] = "ERROR"
            result["error"] = str(error)
        summary["cases"].append(result)
        print(case.name + ": " + result["status"], flush=True)
summary["source_unchanged"] = source_hashes == digest(sources)
summary["status"] = ("PASS" if build == 0 and summary["source_unchanged"]
                     and len(summary["cases"]) == len(cases)
                     and all(case["status"] == "PASS" for case in summary["cases"]) else "FAIL")
(output / "result.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")
print("silent_replay=" + summary["status"] + " artifacts=" + str(output), flush=True)
sys.exit(0 if summary["status"] == "PASS" else 1)
PY
