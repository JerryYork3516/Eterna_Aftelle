"""Self-check the wrapper and synthetic diagnostics; no device or audio files."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import run as runner
import signals


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
                "p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(20)']); "
                f"pathlib.Path({str(pid_file)!r}).write_text(str(p.pid)); time.sleep(20)")
        rows = runner.run_jobs([self.command("timeout", code, 1),
                                self.command("never", "pass")], runner.ROOT, self.path, {})
        self.assertEqual(rows[0]["exit_code"], 124)
        self.assertEqual(rows[1]["status"], "NOT_RUN")
        pid = int(pid_file.read_text())
        state = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True).stdout.strip()
        self.assertTrue(not state or state.startswith(b"Z"), "descendant still running")

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

    def test_isolated_tmp_and_single_attempt_plan(self):
        row = runner.execute(self.command("tmp", "import os; print(os.environ['TMPDIR'])"),
                             runner.ROOT, self.path / "tmp-job")
        self.assertIn(str(self.path / "tmp-job/tmp"), Path(row["log"]).read_text())
        for mode in ("FAST", "FULL"):
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
        path.write_text(json.dumps(report))
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
        with self.assertRaises(ValueError):
            runner.reuse_fast(path, {})


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    print(f"automation_self_cases={result.testsRun}")
    raise SystemExit(not result.wasSuccessful())
