"""M03 offline connection checks using the existing Fake processes and real pipes."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import integration
import m03_once
from prepare_player import FIXTURES
from test_integration import BUNDLE, HOST, FakeProcesses


class BatchProcesses(FakeProcesses):
    def __init__(self, group, fault=None):
        super().__init__("HOST", fault)
        self.group = group

    def emit(self, fd, value):
        if value.get("event") == "proxy_ready":
            value.update(fixture_sha256=FIXTURES["REF_proxy.wav"], duration_seconds=264310/24000)
        if value.get("event") in ("schedule", "stop"):
            value.update(batch="R5_M03", scenario="C" if self.fault == "wrong_group" else self.group)
        super().emit(fd, value)

    def __call__(self, argv, **kwargs):
        if self.group != "A":
            return super().__call__(argv, **kwargs)
        self.calls.append((argv, kwargs))
        self.app_write = os.dup(kwargs["pass_fds"][0])
        self.descriptors.append(self.app_write)
        self.emit(self.app_write, self.schedule)
        return self.child


class M03Tests(unittest.TestCase):
    def connected(self, group, fault=None):
        fake = BatchProcesses(group, fault)
        try:
            with tempfile.TemporaryDirectory() as root:
                evidence = Path(root) / "run"
                if fault:
                    with self.assertRaises((ValueError, AssertionError, RuntimeError, EOFError, TimeoutError)):
                        integration._connected_run(BUNDLE, "HOST", HOST, evidence,
                                                   spawn=fake, clock=fake.clock, m03_group=group)
                    self.assertEqual(json.loads((evidence/"result.json").read_text())["status"], "FAIL")
                    self.assertIsNotNone(fake.child.poll())
                    self.assertIsNotNone(fake.helper.poll())
                else:
                    result = integration._connected_run(BUNDLE, "HOST", HOST, evidence,
                                                        spawn=fake, clock=fake.clock, m03_group=group)
                    self.assertEqual(result["status"], "PASS_OFFLINE_CONTROL_ONLY")
                    self.assertEqual(result["commands"], [] if group == "A" else ["PLAY", "STOP"])
                    self.assertEqual(len(fake.calls), 1 if group == "A" else 2)
                    self.assertIn("--apple-vp-bt-abc="+group, fake.calls[-1][0])
                    if group != "A":
                        self.assertEqual(Path(fake.calls[0][0][-1]).name, "REF_proxy.wav")
        finally:
            fake.close()

    def test_a(self): self.connected("A")
    def test_b(self): self.connected("B")
    def test_c(self): self.connected("C")
    def test_cancel(self): self.connected("B", "cancel")
    def test_wrong_group(self): self.connected("B", "wrong_group")
    def test_foreign_run(self): self.connected("B", "foreign")
    def test_late(self): self.connected("B", "late")
    def test_eof(self): self.connected("B", "eof")
    def test_missing(self): self.connected("B", "no_schedule")
    def test_duplicate(self): self.connected("B", "duplicate")
    def test_clock(self): self.connected("B", "clock")

    def test_default_disabled(self):
        with patch("subprocess.Popen") as spawn:
            with self.assertRaises(PermissionError):
                m03_once.run(BUNDLE, "A", HOST, Path("NOT_CREATED"))
            spawn.assert_not_called()

    def test_one_attempt(self):
        fake = BatchProcesses("A")
        try:
            with tempfile.TemporaryDirectory() as root:
                path = Path(root).resolve()/"A"
                m03_once.run(BUNDLE, "A", HOST, path, spawn=fake, clock=fake.clock)
                with self.assertRaises(FileExistsError):
                    m03_once.run(BUNDLE, "A", HOST, path, spawn=fake, clock=fake.clock)
                self.assertEqual(len(fake.calls), 1)
        finally:
            fake.close()

    def test_identity_rejected(self):
        with tempfile.TemporaryDirectory() as root, patch("subprocess.Popen") as spawn:
            wrong = Path(root)/"Aftelle"
            wrong.write_bytes(b"synthetic_wrong_binary")
            with self.assertRaises(ValueError):
                m03_once.run(BUNDLE, "A", wrong, Path(root)/"A", spawn=BatchProcesses("A"))
            spawn.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
