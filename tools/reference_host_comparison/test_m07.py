"""Human control identity, no-proxy, one-attempt and cancellation checks; Fake processes only."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import integration
import m07_once
from prepare_player import sha
from test_integration import BUNDLE, HOST, FakeProcesses


class HumanProcesses(FakeProcesses):
    def __init__(self, group, fault=None):
        super().__init__("HOST", fault)
        self.group = group

    def emit(self, fd, event):
        event = dict(event)
        event.update(batch="R5_M07", scenario=self.group, source="human", proxy_requested=False)
        event["human_speech_stop_ns"] = event.pop("proxy_stop_ns", 11_000_000_000)
        if self.fault == "wrong_source": event["source"] = "bluetooth"
        if self.fault == "wrong_group": event["scenario"] = "A"
        if self.fault == "proxy_requested": event["proxy_requested"] = True
        if self.fault == "duration": event["human_speech_stop_ns"] += 1
        super().emit(fd, event)

    def __call__(self, argv, **kwargs):
        self.calls.append((argv, kwargs))
        self.app_write = os.dup(kwargs["pass_fds"][0])
        self.descriptors.append(self.app_write)
        if self.fault != "no_schedule": self.emit(self.app_write, self.schedule)
        if self.fault == "duplicate": self.emit(self.app_write, self.schedule)
        return self.child


class HumanTests(unittest.TestCase):
    def setUp(self):
        self.identity = patch.object(integration, "M07_HOST_DYLIB_SHA", sha(HOST.with_name("Aftelle.debug.dylib")))
        self.identity.start()
        self.addCleanup(self.identity.stop)

    def connected(self, group, fault=None):
        fake = HumanProcesses(group, fault)
        try:
            with tempfile.TemporaryDirectory() as directory:
                evidence = Path(directory)/"run"
                if fault:
                    with self.assertRaises((ValueError, AssertionError, RuntimeError, EOFError, TimeoutError,
                                            subprocess.TimeoutExpired)):
                        integration._connected_run(BUNDLE, "HOST", HOST, evidence,
                                                   spawn=fake, clock=fake.clock, human_group=group)
                    self.assertEqual(json.loads((evidence/"result.json").read_text())["status"], "FAIL")
                    self.assertIsNotNone(fake.child.poll())
                else:
                    result = integration._connected_run(BUNDLE, "HOST", HOST, evidence,
                                                        spawn=fake, clock=fake.clock, human_group=group)
                    self.assertEqual(result["status"], "PASS_OFFLINE_CONTROL_ONLY")
                    self.assertEqual(result["commands"], [])
                    self.assertFalse(result["proxy_requested"])
                    self.assertEqual(result["source"], "human")
                self.assertEqual(len(fake.calls), 1)
                self.assertIn("--apple-vp-human-abc="+group, fake.calls[0][0])
                self.assertFalse(any("--apple-vp-bt-abc=" in x for x in fake.calls[0][0]))
        finally:
            fake.close()

    def test_human_a_b_c_no_proxy(self):
        for group in ("A", "B", "C"):
            with self.subTest(group=group): self.connected(group)

    def test_negative_controls_cleanup(self):
        for fault in ("wrong_source", "wrong_group", "proxy_requested", "duration", "foreign", "clock",
                      "no_schedule", "duplicate", "eof", "late", "cancel"):
            with self.subTest(fault=fault): self.connected("B", fault)

    def test_default_disabled(self):
        with patch("subprocess.Popen") as spawn:
            with self.assertRaises(PermissionError):
                m07_once.run(BUNDLE, "A", HOST, Path("NOT_CREATED"))
            spawn.assert_not_called()

    def test_one_attempt(self):
        fake = HumanProcesses("A")
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve(); root.chmod(0o700)
                m07_once.run(BUNDLE, "A", HOST, root/"A", spawn=fake, clock=fake.clock)
                with self.assertRaises(FileExistsError):
                    m07_once.run(BUNDLE, "A", HOST, root/"A", spawn=fake, clock=fake.clock)
                self.assertEqual(len(fake.calls), 1)
        finally:
            fake.close()

    def test_mixed_or_ref_rejected_before_spawn(self):
        for mode, m03, human in (("REF", None, "A"), ("HOST", "A", "A"), ("HOST", None, "D")):
            with self.subTest(mode=mode, m03=m03, human=human):
                with self.assertRaises(ValueError):
                    integration.command(mode, HOST, 3, m03_group=m03, human_group=human)

    def test_foreign_predecessor_rejected_before_spawn(self):
        for foreign in ("batch", "group", "source", "run_id", "proxy_requested"):
            with self.subTest(foreign=foreign), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve(); root.chmod(0o700); (root/"A").mkdir()
                result = dict(status="PASS_OFFLINE_CONTROL_ONLY", batch="R5_M07", group="A",
                              source="human", proxy_requested=False, run_id="current-human-run")
                release = dict(safe_to_continue=True, batch="R5_M07", group="A", run_id=result["run_id"])
                if foreign == "run_id": release["run_id"] = "foreign-run"
                else: result[foreign] = 0 if foreign == "proxy_requested" else "foreign"
                (root/"A/result.json").write_text(json.dumps(result))
                (root/"A/release.json").write_text(json.dumps(release))
                fake = HumanProcesses("B")
                try:
                    with self.assertRaises(ValueError):
                        m07_once.run(BUNDLE, "B", HOST, root/"B", spawn=fake, clock=fake.clock)
                    self.assertEqual(fake.calls, [])
                finally:
                    fake.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
