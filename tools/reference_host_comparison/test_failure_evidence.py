"""Failure receipts and original-UI handoff, using Fake children only."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import integration
from test_integration import BUNDLE, HOST
from test_m03 import BatchProcesses


class StartupStopProcesses(BatchProcesses):
    def __init__(self):
        super().__init__("A")
        self.child.pid = 4242
        self.schedule.update(event="stop", score_start_ns=0, proxy_stop_ns=11_000_000_000)


class FailureEvidenceTests(unittest.TestCase):
    def exercise(self, callback=None, *, offline=False, startup=True):
        fake = StartupStopProcesses() if startup else BatchProcesses("A", "foreign")
        fake.child.pid = 4242
        try:
            with tempfile.TemporaryDirectory() as root:
                evidence = Path(root)/"A"
                options = {} if callback is None else {"failure_ui": lambda pid: callback(fake, pid)}
                with patch("subprocess.Popen", side_effect=AssertionError("Real process forbidden")):
                    with self.assertRaisesRegex(AssertionError, "foreign terminal event"):
                        integration._connected_run(BUNDLE, "HOST", HOST, evidence, spawn=fake,
                                                   clock=fake.clock, device=not offline, m03_group="A", **options)
                result = json.loads((evidence/"result.json").read_text())
                self.assertEqual(result["status"], "FAIL")
                self.assertEqual(result["commands"], [])
                self.assertEqual(len(fake.calls), 1)
                self.assertIsNotNone(fake.child.poll())
                self.assertEqual((evidence/"result.json").stat().st_mode & 0o777, 0o600)
                return result, fake
        finally:
            fake.close()

    def test_rejected_startup_stop_is_retained(self):
        result, fake = self.exercise()
        self.assertEqual(len(result["events"]), 1)
        self.assertEqual(result["events"][0]["event"], "stop")
        self.assertNotIn("run_id", result)
        self.assertTrue(fake.child.terminated)

    def test_original_ui_can_export_before_reaping(self):
        calls = []

        def original_ui(fake, pid):
            self.assertEqual(pid, 4242)
            self.assertIsNone(fake.child.poll())
            self.assertFalse(fake.child.terminated)
            calls.append("FAKE_ORIGINAL_STOP_SEAL_EXPORT_QUIT")
            fake.child.code = 0

        result, fake = self.exercise(original_ui)
        self.assertEqual(calls, ["FAKE_ORIGINAL_STOP_SEAL_EXPORT_QUIT"])
        self.assertEqual(result["failure_ui"], "COMPLETED")
        self.assertFalse(fake.child.terminated)
        self.assertNotIn("run_id", result)

    def test_export_error_preserves_primary_error_and_cleans_up(self):
        def unavailable(fake, pid):
            raise TimeoutError("FAKE original UI unavailable")

        result, fake = self.exercise(unavailable)
        self.assertEqual(result["error"], "foreign terminal event")
        self.assertEqual(result["failure_ui_error"], "FAKE original UI unavailable")
        self.assertTrue(fake.child.terminated)

    def test_foreign_run_after_schedule_keeps_immediate_rejection(self):
        calls = []
        result, fake = self.exercise(lambda *args: calls.append(args), startup=False)
        self.assertEqual(calls, [])
        self.assertEqual(len(result["events"]), 2)
        self.assertTrue(fake.child.terminated)

    def test_ui_handoff_requires_explicit_resident_only_device_path(self):
        for device, group in ((False, "A"), (True, "B"), (True, "C")):
            with self.subTest(device=device, group=group), tempfile.TemporaryDirectory() as root:
                fake = BatchProcesses(group)
                try:
                    with self.assertRaisesRegex(ValueError, "failure UI requires resident-only device execution"):
                        integration._connected_run(BUNDLE, "HOST", HOST, Path(root)/"A", spawn=fake,
                                                   clock=fake.clock, device=device, m03_group=group,
                                                   failure_ui=lambda pid: None)
                    self.assertEqual(fake.calls, [])
                finally:
                    fake.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
