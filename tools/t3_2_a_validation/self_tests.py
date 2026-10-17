"""Self-check the wrapper and synthetic diagnostics; no device or audio files."""

import ast
from contextlib import redirect_stdout
import hashlib
import io
import json
import os
import signal
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import run as runner
import signals
import test3_total


class SyntheticChecks(unittest.TestCase):
    def result(self, name):
        samples, reference, start, end = signals.fixture(name)
        return signals.measure(samples, reference, signals.RATE, start, end)

    def test_normal_weak_short_and_crescendo(self):
        for name in ("normal", "weak", "short", "crescendo"):
            with self.subTest(name=name):
                self.assertEqual(self.result(name)["flags"], [])

    def test_eighty_ms_burst_duration_and_level(self):
        result = self.result("burst")
        self.assertEqual(result["first_active_span_ms"], 80)
        self.assertAlmostEqual(result["first_active_window_s"], 0.1)
        self.assertGreaterEqual(result["peak"], .12)
        self.assertGreater(result["rms"], 0)
        self.assertIn("unexpected_pre_onset_signal", result["flags"])

    def test_fault_specific_flags(self):
        for name, flag in (("clipping", "clipping"), ("gain_jump", "gain_jump"),
                           ("boundary", "boundary_nonzero"),
                           ("stale", "stale_after_declared_stop"),
                           ("chunk_duplicate", "reference_content_mismatch"),
                           ("chunk_loss", "reference_content_mismatch")):
            with self.subTest(name=name):
                self.assertIn(flag, self.result(name)["flags"])

    def test_positive_controls_really_exit_one(self):
        for name in signals.FIXTURES:
            with self.subTest(name=name):
                process = subprocess.run([sys.executable, str(runner.HERE / "signals.py"),
                                          "--fixture", name], capture_output=True)
                expected = 0 if name in ("normal", "weak", "short", "crescendo") else 1
                self.assertEqual(process.returncode, expected)
                self.assertIn(b"SYNTHETIC_DIAGNOSTIC_ONLY", process.stdout)

    def test_silence_and_invalid_input(self):
        self.assertEqual(signals.measure([0.] * 120, [0.] * 120, 24000, 0, .005)["flags"], [])
        for samples, rate in (([], 24000), ([float("nan")], 24000), ([0.], 0)):
            with self.assertRaises(ValueError):
                signals.measure(samples, samples, rate, 0, 1)


class RunnerChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)

    def command(self, name, code, seconds=10):
        return runner.job(name, [sys.executable, "-c", code], seconds)

    def test_exit_counts_timing_permissions(self):
        row = runner.execute(self.command("pass", "print('example_cases=2'); print('example_checks=7')"),
                             runner.ROOT, self.path / "job")
        self.assertEqual((row["status"], row["exit_code"]), ("PASS", 0))
        self.assertEqual(row["counts"], {"example_cases": 2, "example_checks": 7})
        self.assertGreater(row["elapsed_seconds"], 0)
        self.assertEqual(Path(row["log"]).stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.path / "job").stat().st_mode & 0o777, 0o700)

    def test_failure_stops_without_retry(self):
        jobs = [self.command("fail", "raise SystemExit(17)"),
                self.command("never", "raise SystemExit(0)"),
                self.command("also-never", "raise SystemExit(0)")]
        rows = runner.run_jobs(jobs, runner.ROOT, self.path, {})
        self.assertEqual([r["status"] for r in rows], ["FAIL", "NOT_RUN", "NOT_RUN"])
        self.assertEqual([r["attempts"] for r in rows], [1, 0, 0])
        self.assertFalse((self.path / "never").exists())

    def test_timeout_kills_descendant_and_stops(self):
        pid_file = self.path / "pid"
        code = ("import subprocess,sys,time,pathlib; "
                "p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(20)'],"
                "start_new_session=True); "
                f"pathlib.Path({str(pid_file)!r}).write_text(str(p.pid)); time.sleep(20)")
        rows = runner.run_jobs([self.command("timeout", code, 1),
                                self.command("never", "pass")], runner.ROOT, self.path, {})
        self.assertEqual(rows[0]["exit_code"], 124)
        self.assertEqual(rows[1]["status"], "NOT_RUN")
        pid = int(pid_file.read_text())
        state = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True).stdout.strip()
        self.assertTrue(not state or state.startswith(b"Z"), "descendant still running")

    def test_interrupt_cleans_nested_sessions(self):
        pid_file = self.path / "nested-pid"
        child = ("import subprocess,sys,time,pathlib; "
                 "p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(20)'],"
                 "start_new_session=True); "
                 f"pathlib.Path({str(pid_file)!r}).write_text(str(p.pid)); time.sleep(20)")
        code = ("import sys; sys.path.insert(0," + repr(str(runner.HERE)) + "); "
                "import run; from pathlib import Path; "
                f"r=run.execute(run.job('interrupt',[sys.executable,'-c',{child!r}],10),"
                f"run.ROOT,Path({str(self.path / 'interrupted')!r})); "
                "raise SystemExit(r['exit_code'])")
        process = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        deadline = time.monotonic() + 5
        while not pid_file.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertTrue(pid_file.exists(), "synthetic descendant did not start")
        os.kill(process.pid, signal.SIGINT)
        self.assertEqual(process.wait(timeout=8), 130)
        state = subprocess.run(["ps", "-o", "stat=", "-p", pid_file.read_text()],
                               capture_output=True).stdout.strip()
        self.assertTrue(not state or state.startswith(b"Z"))

    def test_historical_block_preserves_failure_exit(self):
        code = ("print('r851_production_mutations=0'); "
                "print('r851_production_baseline=FAIL expected=abc observed=def'); raise SystemExit(1)")
        row = runner.execute(self.command("legacy-total", code), runner.ROOT, self.path / "legacy")
        self.assertEqual((row["status"], row["exit_code"]), ("BLOCKED", 1))
        row = runner.execute(self.command("other", code), runner.ROOT, self.path / "other")
        self.assertEqual(row["status"], "FAIL")

    def test_missing_fixture_is_blocked_not_pass(self):
        item = self.command("missing", "raise SystemExit(0)")
        item["requires_fixture"] = True
        with patch.object(runner, "FIXTURE", self.path / "absent"):
            row = runner.run_jobs([item], runner.ROOT, self.path, {})[0]
        self.assertEqual((row["status"], row["exit_code"], row["attempts"]), ("BLOCKED", None, 0))

    def test_candidate_block_keeps_exit_and_requires_valid_report(self):
        destination = self.path / "blocked-report"
        code = ("import sys; from pathlib import Path; sys.path.insert(0," +
                repr(str(runner.HERE)) + "); import run; p=Path(sys.argv[1]); p.mkdir(); "
                "run.write_report(p/'results.json', {'status':'BLOCKED','reason':'missing evidence'}); "
                "raise SystemExit(2)")
        item = self.command("test3-candidate", code)
        item["command"].append(str(destination))
        row = runner.execute(item, runner.ROOT, self.path / "candidate-block")
        self.assertEqual((row["status"], row["exit_code"]), ("BLOCKED", 2))
        item = self.command("test3-candidate", "raise SystemExit(2)")
        item["command"].append(str(self.path / "absent-report"))
        row = runner.execute(item, runner.ROOT, self.path / "invalid-block")
        self.assertEqual((row["status"], row["exit_code"]), ("FAIL", 2))

    def test_isolated_tmp_and_single_attempt_plan(self):
        row = runner.execute(self.command("tmp", "import os; print(os.environ['TMPDIR'])"),
                             runner.ROOT, self.path / "tmp-job")
        self.assertIn(str(self.path / "tmp-job/tmp"), Path(row["log"]).read_text())
        for mode in ("FAST", "FULL", "TEST3", "FULL_CURRENT"):
            jobs = runner.plan(mode, self.path)
            self.assertEqual(len(jobs), len({x["name"] for x in jobs}))
            self.assertTrue(all(x["max_attempts"] == 1 and x["timeout_seconds"] > 0 for x in jobs))
            self.assertFalse(any("--r3-m01-wav" in x["command"] for x in jobs))

    def test_counter_subsets_not_summed(self):
        self.assertEqual(runner.counters("a_cases=2\na_checks=8\nsubset_checks=3\npeak=12\n"),
                         {"a_cases": 2, "a_checks": 8, "subset_checks": 3})

    def test_reuse_requires_exact_candidate_and_untampered_log(self):
        directory = self.path / ".build/t3_2_a_validation/fast"
        directory.mkdir(parents=True)
        log = directory / "pass.log"
        log.write_text("good")
        source = {"source_commit": "candidate"}
        row = {"name": "pass", "log": str(log), "status": "PASS", "exit_code": 0,
               "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}
        report = {"schema_version": 1, "mode": "FAST", "status": "PASS",
                  "identity": source, "tests": [row]}
        path = directory / "results.json"
        runner.write_report(path, report)
        with patch.object(runner, "ROOT", self.path):
            self.assertEqual(runner.reuse_fast(path, source)["pass"]["execution"], "REUSED_FAST")
            with self.assertRaises(ValueError):
                runner.reuse_fast(path, {"source_commit": "changed"})
            log.write_text("tampered")
            with self.assertRaises(ValueError):
                runner.reuse_fast(path, source)

    def test_reuse_rejects_outside_report(self):
        path = self.path / "unapproved.json"
        path.write_text("{}")
        with patch.object(runner, "ROOT", self.path / "different-checkout"):
            with self.assertRaisesRegex(ValueError, "this checkout"):
                runner.reuse_fast(path, {})

    def test_result_receipt_rejects_metadata_tampering(self):
        path = self.path / "results.json"
        runner.write_report(path, {"status": "PASS", "counts": 1})
        self.assertEqual(runner.read_report(path)["counts"], 1)
        path.write_text(json.dumps({"status": "PASS", "counts": 999}))
        with self.assertRaises(ValueError):
            runner.read_report(path)

    def test_external_pcm_and_partial_test_overrides_removed(self):
        overrides = {key: "SYNTHETIC_OVERRIDE_NOT_A_REAL_PATH" for key in runner.TEST_OVERRIDES}
        # Check only the known switches; no values from the caller are logged.
        code = ("import os; raise SystemExit(int(any(k in os.environ for k in " +
                repr(list(runner.TEST_OVERRIDES)) + ")))")
        with patch.dict(os.environ, overrides):
            row = runner.execute(self.command("env", code), runner.ROOT, self.path / "env")
        self.assertEqual(row["exit_code"], 0)

    def test_source_or_workspace_drift_stops_after_first_job(self):
        for field in ("production_tree", "workspace_metadata_sha256"):
            with self.subTest(field=field):
                before, after = {field: "before"}, {field: "after"}
                directory = self.path / field
                directory.mkdir()
                with patch.object(runner, "identity", return_value=after):
                    rows = runner.run_jobs([self.command("changed", "pass"),
                                            self.command("never", "pass")],
                                           runner.ROOT, directory, {}, before)
                self.assertEqual(rows[0]["status"], "FAIL")
                self.assertEqual(rows[1]["status"], "NOT_RUN")

    def test_candidate_static_contracts_and_no_frozen_bypass(self):
        result = test3_total.static_contracts(runner.ROOT)
        self.assertEqual(tuple(result["invariant_ids"]), test3_total.IDS)
        self.assertTrue(all(result["checks"].values()))
        self.assertEqual(len(test3_total.jobs()), 7)
        self.assertFalse(any("realtime_total_regression_tests/check.sh" in x["command"]
                             for x in test3_total.jobs()))
        self.assertEqual(len(runner.plan("FAST", self.path)), 8)
        self.assertEqual(len(runner.plan("TEST3", self.path)), 1)

    def test_original_mode_plans_match_v02(self):
        original = ast.parse(runner.git(
            "show", "30f2b0aaf1b9a439c5bf429d3eb3be97254a580a:tools/t3_2_a_validation/run.py"))
        functions = [n for n in original.body if isinstance(n, ast.FunctionDef) and
                     n.name in ("job", "plan")]
        namespace = dict(vars(runner))
        exec(compile(ast.Module(body=functions, type_ignores=[]), "v0.2-plan", "exec"), namespace)
        for mode in ("FAST", "TEST3", "FULL"):
            with self.subTest(mode=mode):
                self.assertEqual(runner.plan(mode, self.path), namespace["plan"](mode, self.path))

    def test_current_plan_only_excludes_historical_gate(self):
        full = runner.plan("FULL", self.path)
        current = runner.plan("FULL_CURRENT", self.path)
        self.assertEqual(len(full), 22)
        self.assertEqual(len(current), 21)
        self.assertEqual(current, [j for j in full if j["name"] != "legacy-total"])
        self.assertEqual(sum(j["name"] == "test3-candidate" for j in current), 1)

    def run_current_cli(self, jobs):
        output = io.StringIO()
        with patch.object(sys, "argv", ["run.py", "FULL_CURRENT"]), \
                patch.object(runner, "plan", return_value=jobs), redirect_stdout(output):
            code = runner.main()
        path = Path(re.search(r"^REPORT=(.+)$", output.getvalue(), re.MULTILINE).group(1))
        return code, runner.read_report(path)

    def test_current_cli_candidate_failure_stops_and_exits_one(self):
        code, result = self.run_current_cli([
            self.command("test3-candidate", "raise SystemExit(1)"),
            self.command("never", "pass")])
        self.assertEqual((code, result["FULL_CURRENT"]), (1, "FAIL"))
        self.assertEqual([r["status"] for r in result["tests"]], ["FAIL", "NOT_RUN"])
        self.assertEqual([r["attempts"] for r in result["tests"]], [1, 0])
        self.assertEqual(result["LEGACY_R851"], "HISTORICAL_BASELINE_BLOCKED")
        self.assertFalse(result["LEGACY_R851_EXECUTED_IN_CURRENT"])

    def test_current_cli_missing_fixture_blocks_without_execution(self):
        item = self.command("requires-fixture", "raise SystemExit(0)")
        item["requires_fixture"] = True
        with patch.object(runner, "FIXTURE", self.path / "absent"):
            code, result = self.run_current_cli([item])
        self.assertEqual((code, result["FULL_CURRENT"]), (2, "BLOCKED"))
        self.assertEqual(result["tests"][0]["attempts"], 0)
        self.assertFalse(result["LEGACY_R851_EXECUTED_IN_CURRENT"])

    def current_evidence_fixture(self):
        source = {"source_commit": "SYNTHETIC_METADATA_ONLY"}
        required = runner.plan("FULL_CURRENT", self.path)
        metrics = test3_total.required_metrics()
        metrics["random"].update({"r851_randomized_" + k: "1" for k in (
            "final_before_stop", "completion_before_final", "partial_final_stop",
            "short_pause_resume", "provider_first_start")})

        def evidence(item, values):
            log = self.path / (item["name"] + ".log")
            log.write_text("\n".join(k + "=" + v for k, v in values.items()) + "\n")
            return {**item, "status": "PASS", "exit_code": 0, "log": str(log),
                    "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}

        rows = [evidence(j, {}) for j in required]
        children = [evidence(j, metrics[j["name"]]) for j in test3_total.jobs()]
        directory = self.path / "candidate"
        directory.mkdir()
        runner.write_report(directory / "results.json", {
            "status": "PASS", "reason": "TEST3_CANDIDATE_PASS", "identity": source,
            "invariants": dict.fromkeys(test3_total.IDS, "PASS"), "tests": children})
        return required, rows, source

    def test_current_final_log_integrity_accepts_control_and_rejects_tampering(self):
        required, rows, source = self.current_evidence_fixture()
        with patch.object(runner, "identity", return_value=source):
            self.assertEqual(runner.current_status(required, rows, source, self.path)[0], "PASS")
            Path(rows[0]["log"]).write_text("tampered")
            status, reason = runner.current_status(required, rows, source, self.path)
        self.assertEqual(status, "FAIL")
        self.assertEqual(reason, "Log tampering")

    def test_current_final_source_drift_is_fail(self):
        required, rows, source = self.current_evidence_fixture()
        with patch.object(runner, "identity", return_value={"source_commit": "changed"}):
            self.assertEqual(runner.current_status(required, rows, source, self.path)[0], "FAIL")

    def test_current_missing_evidence_and_incomplete_scope_cannot_pass(self):
        required, rows, source = self.current_evidence_fixture()
        path = self.path / "candidate/results.json"
        result = runner.read_report(path)
        result["invariants"].pop("I1")
        runner.write_report(path, result)
        with patch.object(runner, "identity", return_value=source):
            self.assertEqual(runner.current_status(required, rows, source, self.path)[0], "BLOCKED")
            path.unlink()
            self.assertEqual(runner.current_status(required, rows, source, self.path)[0], "BLOCKED")
            self.assertEqual(runner.current_status(required, rows[:-1], source, self.path)[0], "BLOCKED")
            self.assertEqual(runner.current_status([], [], source, self.path)[0], "BLOCKED")
            rows[0]["exit_code"] = 1
            self.assertEqual(runner.current_status(required, rows, source, self.path)[0], "FAIL")

    def test_evidence_success_markers_match_existing_producer(self):
        script = (runner.ROOT / "tools/realtime_interruption_evidence_tests/check.sh").read_text()
        emitted = set(re.findall(r'echo "([A-Za-z0-9_]+)=PASS"', script))
        self.assertTrue(set(test3_total.required_metrics()["evidence"]).issubset(emitted))
        self.assertIn('echo "realtime_interruption_runtime_authority=FAIL"\n  exit 1', script)

    def test_invariant_and_old_generation_bad_acceptance_really_fail(self):
        for key in ("r851_false_memory_writes", "r851_stale_generation_side_effects"):
            with self.subTest(key=key):
                code = ("import sys; sys.path.insert(0," + repr(str(runner.HERE)) + "); "
                        "import test3_total as t; m=t.required_metrics(); "
                        "m['random'].update({'r851_randomized_'+k:'1' for k in "
                        "('final_before_stop','completion_before_final','partial_final_stop',"
                        "'short_pause_resume','provider_first_start')}); "
                        "m['cross'][" + repr(key) + "]='1'; t.validate_metrics(m)")
                item = self.command(key, code)
                # Explicit checks must survive optimized Python as well.
                item["command"].insert(1, "-O")
                row = runner.execute(item, runner.ROOT, self.path / key)
                self.assertEqual((row["status"], row["exit_code"]), ("FAIL", 1))

    def test_candidate_missing_evidence_blocked_and_log_tamper_failed(self):
        with self.assertRaises(test3_total.EvidenceMissing):
            test3_total.validate_metrics({})
        log = self.path / "data.log"
        log.write_text("original")
        row = {"name": "cross", "status": "PASS", "exit_code": 0, "log": str(log),
               "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}
        log.write_text("modified")
        with self.assertRaisesRegex(ValueError, "Log tampering"):
            test3_total.read_metrics([row])

    def test_candidate_missing_fixture_has_real_blocked_report(self):
        directory = self.path / ".build/t3_2_a_validation/candidate"
        directory.parent.mkdir(parents=True)
        with patch.object(runner, "ROOT", self.path), \
                patch.object(runner, "FIXTURE", self.path / "absent"), \
                patch.object(runner, "identity", return_value={"source_commit": "synthetic"}):
            code = test3_total.main(directory)
        self.assertEqual(code, 2)
        report = runner.read_report(directory / "results.json")
        self.assertEqual(report["status"], "BLOCKED")
        self.assertEqual(report["tests"], [])
        self.assertEqual(set(report["invariants"].values()), {"BLOCKED"})


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    print(f"automation_self_cases={result.testsRun}")
    raise SystemExit(not result.wasSuccessful())
