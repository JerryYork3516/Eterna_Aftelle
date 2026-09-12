#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
exec /usr/bin/python3 - "$repo_root" "$@" <<'PY'
import argparse
import datetime
import hashlib
import json
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
           repo / "tools/speech_aec_host_tests/RecordedAcousticReplay.swift"]
required = ["initial-state.json", "final-state.json", "audio-calls.json", "control-events.json",
            "capture-frames.json", "render-frames.json", "result.json",
            "raw-mic-48k.f32le.pcm", "render-48k.f32le.pcm", "clean-48k.f32le.pcm", "linear-16k.f32le.pcm"]


def digest(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


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
                 str(output / "module-cache"), *map(str, sources), "-o", str(binary)],
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
            result["input_sha256"] = before
            result["input_unchanged"] = before == digest([case / name for name in required])
            if not result["input_unchanged"]:
                result["status"] = "ERROR"
        except (OSError, ValueError) as error:
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
