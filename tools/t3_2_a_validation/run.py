"""Sequential, single-attempt offline wrapper around existing Aftelle tests."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TIMEOUT = ROOT / "tools/realtime_total_regression_tests/run_with_timeout.pl"
FIXTURE = ROOT / "apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def identity():
    files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(HERE.iterdir()) if p.suffix in (".py", ".sh")}
    return {"source_commit": git("rev-parse", "HEAD").decode().strip(),
            "production_tree": git("rev-parse", "HEAD:apps").decode().strip(),
            "tracked_code_diff_sha256": hashlib.sha256(
                git("diff", "--no-ext-diff", "HEAD", "--", "apps", "tools")).hexdigest(),
            "automation_files_sha256": files}


def job(name, command, seconds=180, fixture=False):
    return {"name": name, "command": command, "timeout_seconds": seconds,
            "max_attempts": 1, "requires_fixture": fixture}


def plan(mode, run_dir):
    def shell(name, path, *args, fixture=False):
        return job(name, ["bash", "tools/" + path + "/check.sh", *args], fixture=fixture)
    jobs = [job("automation-self-tests", [sys.executable, str(HERE / "self_tests.py")]),
            job("synthetic-onset", [sys.executable, str(HERE / "signals.py")]),
            shell("release-guard", "realtime_release_route_guard"),
            shell("architecture-guard", "architecture_guard"),
            shell("secret-guard", "secret_guard"),
            shell("audio-host", "speech_audio_host_tests"),
            shell("playback", "speech_audio_output_tests"),
            shell("debug-stats-timing", "speech_aec_host_tests", "d1-stats-only")]
    if mode == "FULL":
        jobs += [shell("aec-converter-replay", "speech_aec_host_tests"),
                 shell("d1-control-export", "realtime_interruption_evidence_tests", "d1-only"),
                 shell("r81-evidence", "realtime_interruption_evidence_tests", fixture=True),
                 shell("input-bridge", "mac_speech_realtime_brain_input_tests", fixture=True),
                 shell("resident-negative", "realtime_resident_only_zero_self_interrupt_tests",
                       "r823-full", fixture=True),
                 shell("qwen-fake", "realtime_resident_only_zero_self_interrupt_tests",
                       "r853-qwen-suite", fixture=True),
                 shell("confirmed-cancel", "realtime_confirmed_interruption_tests", fixture=True),
                 shell("latency-stale", "realtime_barge_in_latency_stale_audio_tests", fixture=True),
                 shell("double-talk-fake", "realtime_double_talk_acoustic_tests", fixture=True),
                 shell("legacy-total", "realtime_total_regression_tests")]
        derived = str(run_dir / "DerivedData")
        for configuration in ("Debug", "Release"):
            jobs.append(job("build-" + configuration.lower(), [
                "xcodebuild", "-project", "apps/macos/Aftelle/Aftelle.xcodeproj",
                "-scheme", "Aftelle", "-configuration", configuration,
                "-destination", "platform=macOS", "-derivedDataPath", derived,
                "-disableAutomaticPackageResolution", "-skipPackageUpdates",
                "CODE_SIGNING_ALLOWED=NO", "build"], 900))
        jobs.append(job("build-identity-isolation", [sys.executable,
                        str(HERE / "build_identity.py"), derived]))
    assert len({j["name"] for j in jobs}) == len(jobs)
    return jobs


def counters(text):
    return {key: int(value) for key, value in re.findall(
        r"^([A-Za-z][A-Za-z0-9_]*(?:cases|checks))=(\d+)$", text, re.MULTILINE)}


def execute(item, root, directory):
    directory.mkdir(mode=0o700)
    temp = directory / "tmp"
    temp.mkdir(mode=0o700)
    log = directory / "output.log"
    env = dict(os.environ, TMPDIR=str(temp) + "/", PYTHONDONTWRITEBYTECODE="1")
    started = time.monotonic()
    row = {**item, "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
           "execution": "EXECUTED", "attempts": 1, "counts": {}}
    command = ["/usr/bin/perl", str(TIMEOUT), str(item["timeout_seconds"]), *item["command"]]
    with log.open("x") as output:
        os.chmod(log, 0o600)
        process = subprocess.Popen(command, cwd=root, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=item["timeout_seconds"] + 10)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            code = 130 if isinstance(error, KeyboardInterrupt) else 124
            row["wrapper_error"] = type(error).__name__
        finally:
            # Also remove descendants left by an exited or interrupted wrapper.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
    text = log.read_text(errors="replace")
    status = "PASS" if code == 0 else "FAIL"
    if (item["name"] == "legacy-total" and code == 1 and
            re.search(r"^r851_production_mutations=0$", text, re.MULTILINE) and
            re.search(r"^r851_production_baseline=FAIL expected=[a-f0-9]+ observed=[a-f0-9]+$",
                      text, re.MULTILINE)):
        status = "BLOCKED"
        row["reason"] = "Frozen historical production digest mismatch; guard unchanged"
    row.update(exit_code=code, status=status, counts=counters(text),
               elapsed_seconds=round(time.monotonic() - started, 3), log=str(log),
               log_sha256=hashlib.sha256(log.read_bytes()).hexdigest())
    return row


def reuse_fast(path, source):
    if path is None:
        return {}
    path = path.resolve(strict=True)
    if not path.is_relative_to((ROOT / ".build/t3_2_a_validation").resolve()):
        raise ValueError("FAST report must be in this checkout's validation directory")
    report = json.loads(path.read_text())
    if (report.get("schema_version") != 1 or report.get("mode") != "FAST" or
            report.get("status") != "PASS" or report.get("identity") != source):
        raise ValueError("FAST report is not a passing run of this exact candidate")
    rows = {}
    for row in report["tests"]:
        log = Path(row["log"]).resolve(strict=True)
        if (not log.is_relative_to(path.parent) or row["status"] != "PASS" or
                row["exit_code"] != 0 or
                hashlib.sha256(log.read_bytes()).hexdigest() != row["log_sha256"]):
            raise ValueError("FAST result/log integrity mismatch")
        rows[row["name"]] = {**row, "execution": "REUSED_FAST", "reused_from": str(path)}
    return rows


def run_jobs(jobs, root, directory, reused):
    rows, halted = [], False
    for item in jobs:
        if halted:
            row = {**item, "status": "NOT_RUN", "exit_code": None, "counts": {},
                   "attempts": 0, "elapsed_seconds": None, "reason": "Stopped after first failure"}
        elif item["requires_fixture"] and not FIXTURE.is_file():
            row = {**item, "status": "BLOCKED", "exit_code": None, "counts": {},
                   "attempts": 0, "elapsed_seconds": None, "reason": "Fixed offline fixture missing"}
        elif item["name"] in reused and item["command"] == reused[item["name"]]["command"]:
            row = reused[item["name"]]
        else:
            row = execute(item, root, directory / item["name"])
        rows.append(row)
        print(f'{item["name"]}: {row["status"]} exit={row["exit_code"]} '
              f'{row.get("execution", "NOT_EXECUTED")}', flush=True)
        halted = halted or row["status"] == "FAIL" or row["exit_code"] == 130
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("FAST", "FULL"))
    parser.add_argument("--reuse-fast", type=Path)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.reuse_fast and args.mode != "FULL":
        parser.error("--reuse-fast is only valid for FULL")
    if args.list:
        for item in plan(args.mode, Path(".build/t3_2_a_validation/RUN")):
            print(item["name"] + ": " + shlex.join(item["command"]))
        return 0
    os.umask(0o077)
    base = ROOT / ".build/t3_2_a_validation"
    if (ROOT / ".build").is_symlink() or base.is_symlink():
        raise ValueError("Validation output directory cannot be a symlink")
    subprocess.run(["git", "-C", str(ROOT), "check-ignore", "-q", str(base / "probe")],
                   check=True)
    base.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory = Path(tempfile.mkdtemp(prefix=args.mode.lower() + "-", dir=base))
    source = identity()
    reused = reuse_fast(args.reuse_fast, source)
    rows = run_jobs(plan(args.mode, directory), ROOT, directory, reused)
    if identity() != source:
        raise RuntimeError("Candidate changed during validation; results cannot be accepted")
    status = ("FAIL" if any(r["status"] == "FAIL" for r in rows) else
              "BLOCKED" if any(r["status"] != "PASS" for r in rows) else "PASS")
    for row in rows:
        row["source_commit"] = source["source_commit"]
        row["command_text"] = shlex.join(row["command"])
    report = {"schema_version": 1, "mode": args.mode, "status": status,
              "identity": source, "tests": rows, "max_attempts": 1,
              "R3_M01": "OPEN: 80ms onset origin UNKNOWN; synthetic results do not close it",
              "acoustic_acceptance": "NOT_RUN", "Test3.execution_authorized": False}
    output = directory / "results.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"RESULT={status}\nREPORT={output}")
    return {"PASS": 0, "FAIL": 1, "BLOCKED": 2}[status]


if __name__ == "__main__":
    raise SystemExit(main())
