#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
exec /usr/bin/python3 - "$repo_root" "$@" <<'PY'
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import shutil
import signal
import struct
import subprocess
import sys
import time
import uuid

repo = Path(sys.argv[1])
parser = argparse.ArgumentParser(description="Local Test 3 audio checks; no Qwen calls.")
parser.add_argument("--app", type=Path, help="Current Debug .app built in this worktree")
parser.add_argument("--skip-build", action="store_true", help="Use the explicitly supplied current build")
parser.add_argument("--preflight-only", action="store_true")
parser.add_argument("--resident-pcm", type=Path,
                    default=repo / ".build/test3-local-automation/fixtures/resident-window-48k.f32le.pcm")
parser.add_argument("--near-pcm", type=Path,
                    default=repo / ".build/test3-local-automation/fixtures/near-preplayback-mic-48k.f32le.pcm")
args = parser.parse_args(sys.argv[2:])
if bool(args.app) != args.skip_build:
    parser.error("--app and --skip-build must be supplied together")

bundle_id = "com.eterna.aftelle.Aftelle"
artifacts = repo / ".build/test3-local-automation"
run_id = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
run_dir = artifacts / "runs" / run_id
run_dir.mkdir(parents=True)
stage = None
transfer_path = None
record = {
    "schema_version": 1, "run_id": run_id, "status": "INCOMPLETE",
    "build_mode": "caller_supplied_current_debug_build" if args.skip_build else "xcodebuild_current_worktree",
    "runner_timeout_seconds": 300, "qwen_calls": 0,
    "validation_scope": "host_runtime_postprocessing_injection",
    "test3_acceptance": "REVIEW_REQUIRED",
    "positive_input": "software_near_end_added_after_apple_voice_processing_before_host_gate",
    "semantic_proposal": "local_stub_test_fixture",
    "physical_double_talk": "NOT_CLAIMED_CAPTURE_INJECTION_USED",
    "artifacts": str(run_dir),
}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bounded(command, log_path, seconds, stderr_path=None, stdin_path=None):
    with log_path.open("wb") as stdout:
        stderr = stderr_path.open("wb") if stderr_path else stdout
        stdin = stdin_path.open("rb") if stdin_path else None
        try:
            process = subprocess.Popen(command, cwd=repo, stdin=stdin, stdout=stdout,
                                       stderr=stderr, start_new_session=True)
            try:
                return process.wait(timeout=max(1, seconds - 2))
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                # Only this launch's process group is terminated.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
                return 124
        finally:
            if stdin:
                stdin.close()
            if stderr_path:
                stderr.close()


def assert_app_closed(executable_name="Aftelle"):
    found = subprocess.run(["/usr/bin/pgrep", "-x", executable_name],
                           capture_output=True, text=True, timeout=5)
    if found.returncode not in (0, 1):
        raise RuntimeError("Unable to establish whether Aftelle is running")
    for pid in found.stdout.split():
        process = subprocess.run(["/bin/ps", "-p", pid, "-o", "comm="],
                                 capture_output=True, text=True, timeout=5)
        executable = process.stdout.strip()
        if not executable:  # The process exited after pgrep.
            continue
        candidate = Path(executable)
        if len(candidate.parents) >= 3:
            info = candidate.parents[2] / "Contents/Info.plist"
            if info.is_file():
                with info.open("rb") as handle:
                    if plistlib.load(handle).get("CFBundleIdentifier") != bundle_id:
                        continue
        raise RuntimeError("Aftelle is still running (pid %s); quit the app before this test" % pid)


def validate_pcm(path):
    path = path.expanduser().resolve(strict=True)
    size = path.stat().st_size
    if size == 0 or size % 4:
        raise RuntimeError("Expected nonempty 48 kHz mono Float32 LE PCM: " + str(path))
    with path.open("rb") as handle:
        if any(not math.isfinite(sample[0]) for sample in struct.iter_unpack("<f", handle.read())):
            raise RuntimeError("PCM contains nonfinite samples: " + str(path))
    return {"path": str(path), "byte_count": size,
            "sha256": sha256(path), "duration_seconds": size / (4 * 48000)}


exit_code = 1
started = time.monotonic()
try:
    assert_app_closed()
    record["git_head"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    with (run_dir / "worktree-status.txt").open("w") as handle:
        subprocess.run(["git", "status", "--short", "--branch"],
                       cwd=repo, stdout=handle, check=True)
    if args.skip_build:
        app = args.app.expanduser().resolve(strict=True)
    else:
        derived = artifacts / "DerivedData"
        build_status = bounded([
            "/usr/bin/xcodebuild", "-project",
            str(repo / "apps/macos/Aftelle/Aftelle.xcodeproj"),
            "-scheme", "Aftelle", "-configuration", "Debug",
            "-derivedDataPath", str(derived),
            "-disableAutomaticPackageResolution", "-skipPackageUpdates", "build",
        ], run_dir / "build.log", 180)
        record["build_exit_code"] = build_status
        if build_status:
            raise RuntimeError("Current Debug build failed or timed out; see build.log")
        app = derived / "Build/Products/Debug/Aftelle.app"
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleIdentifier") != bundle_id:
        raise RuntimeError("Unexpected app bundle identifier")
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or Path(executable_name).name != executable_name:
        raise RuntimeError("Invalid bundle executable")
    executable = app / "Contents/MacOS" / executable_name
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise RuntimeError("App executable is missing or not executable")
    # Xcode Debug's code normally resides in its debug dylib, not its launcher.
    images = {executable.name: sha256(executable)}
    for dylib in sorted((app / "Contents/MacOS").glob("*.debug.dylib")):
        images[dylib.name] = sha256(dylib)
    record.update(app=str(app), binary_sha256=images,
                  bundle_identifier=bundle_id)
    assert_app_closed(executable_name)
    preflight_status = bounded([str(executable), "--test3-local-audio-preflight"],
                              run_dir / "preflight.json", 15,
                              run_dir / "preflight.stderr.log")
    record["preflight_exit_code"] = preflight_status
    if preflight_status:
        raise RuntimeError("App runner preflight failed or timed out")
    preflight_lines = (run_dir / "preflight.json").read_text().strip().splitlines()
    if len(preflight_lines) != 1:
        raise RuntimeError("Runner preflight must return exactly one JSON line")
    preflight = json.loads(preflight_lines[0])
    if not isinstance(preflight, dict) or preflight.get("schema_version") != 1:
        raise RuntimeError("Current app does not implement the expected local runner")
    auth = preflight.get("microphone_authorization")
    record["microphone_authorization"] = auth
    if auth not in ("authorized", "not_determined", "denied", "restricted"):
        raise RuntimeError("Unrecognized microphone authorization state")
    if auth != "authorized" or preflight.get("authorized") is not True:
        raise RuntimeError("Microphone authorization is %s; no permission request was made" % auth)
    returned_root = preflight.get("test_root")
    if not isinstance(returned_root, str) or not Path(returned_root).is_absolute():
        raise RuntimeError("Preflight did not provide an absolute test_root")
    test_root = Path(returned_root).resolve(strict=True)
    expected_tmp = (Path.home() / "Library/Containers" / bundle_id / "Data/tmp").resolve()
    try:
        test_root.relative_to(expected_tmp)
    except ValueError:
        raise RuntimeError("test_root is outside this app's container temporary directory")
    if not test_root.is_dir():
        raise RuntimeError("test_root is not a directory")
    record["test_root"] = str(test_root)
    if args.preflight_only:
        record["status"] = "PREFLIGHT_PASS"
        exit_code = 0
    else:
        inputs = {"resident": validate_pcm(args.resident_pcm),
                  "near": validate_pcm(args.near_pcm)}
        fixture = repo / "apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
        if not fixture.is_file():
            raise RuntimeError("Public Stage 7.5 resident fixture is missing")
        record["inputs"] = inputs
        record["fixture_sha256"] = sha256(fixture)
        transfer_path = run_dir / "input-transfer.bin"
        transfer_header = json.dumps({
            "schema_version": 1,
            "resident_length": Path(inputs["resident"]["path"]).stat().st_size,
            "near_length": Path(inputs["near"]["path"]).stat().st_size,
            "fixture_length": fixture.stat().st_size,
        }, separators=(",", ":")).encode("utf-8")
        with transfer_path.open("wb") as transfer:
            transfer.write(struct.pack("<I", len(transfer_header)))
            transfer.write(transfer_header)
            for source in (Path(inputs["resident"]["path"]),
                           Path(inputs["near"]["path"]), fixture):
                with source.open("rb") as handle:
                    shutil.copyfileobj(handle, transfer)
        assert_app_closed(executable_name)
        run_status = bounded([str(executable), "--test3-local-audio", "-"],
                             run_dir / "app.log", 300,
                             run_dir / "app.stderr.log", transfer_path)
        record["runner_exit_code"] = run_status
        if run_status:
            raise RuntimeError("Local runner failed or timed out; partial evidence is retained")
        result_lines = (run_dir / "app.log").read_text().strip().splitlines()
        if len(result_lines) != 1:
            raise RuntimeError("Local runner must return exactly one result JSON line")
        result = json.loads(result_lines[0])
        if result.get("schema_version") != 1 or not isinstance(result.get("cases"), list):
            raise RuntimeError("Local runner returned an invalid result summary")
        write_json(run_dir / "result.json", result)
        record["app_evidence_directory"] = result.get("evidence_directory")
        case_statuses = [case.get("status") for case in result["cases"]]
        record["case_statuses"] = case_statuses
        all_cases_passed = bool(case_statuses) and all(
            status == "PASS" for status in case_statuses
        )
        record["status"] = "PASS" if all_cases_passed else "FAIL"
        exit_code = 0 if all_cases_passed else 1
except Exception as error:
    record["status"] = "BLOCKED_OR_FAILED"
    record["error"] = str(error)
    print("local_audio_error=" + str(error), file=sys.stderr)
finally:
    if transfer_path is not None:
        try:
            transfer_path.unlink(missing_ok=True)
        except Exception as error:
            record["transfer_cleanup_error"] = str(error)
            record["status"] = "BLOCKED_OR_FAILED"
            exit_code = 1
    if stage is not None and stage.is_dir():
        try:
            shutil.copytree(stage, run_dir / "evidence", symlinks=True)
        except Exception as error:
            record["evidence_copy_error"] = str(error)
            record["status"] = "BLOCKED_OR_FAILED"
            exit_code = 1
    record["elapsed_seconds"] = round(time.monotonic() - started, 3)
    write_json(run_dir / "launcher-result.json", record)
    print("local_audio_checks_status=" + record["status"])
    print("test3_acceptance=" + record["test3_acceptance"])
    print("local_audio_artifacts=" + str(run_dir))
    print("qwen_calls=0; semantic_proposal=local_stub_test_fixture")
    print("positive_input=software_after_apple_voice_processing_before_host_gate; physical_double_talk=NOT_CLAIMED")
sys.exit(exit_code)
PY
