"""Reuse original pipe/Fake lifecycle controls for M20. Never spawn an App."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import integration
from prepare_player import sha
from test_integration import BUNDLE, HOST, FakeProcesses
from test_m07 import HumanProcesses

CONTEXT = dict(batch_id="22222222-2222-4222-8222-222222222222", round=1, limit=3)


class MacProcesses(HumanProcesses):
    def __init__(self, fault=None):
        super().__init__("A", fault)

    def emit(self, fd, event):
        event = dict(event, batch="R5_M20", scenario="A", proxy_requested=False, **CONTEXT)
        event.setdefault("score_start_ns", self.schedule["score_start_ns"])
        event.setdefault("proxy_stop_ns", self.schedule["proxy_stop_ns"])
        if self.fault == "wrong_round": event["round"] = 2
        if self.fault == "wrong_batch": event["batch_id"] = "foreign"
        if self.fault == "proxy_requested": event["proxy_requested"] = True
        if self.fault == "foreign_source": event["source"] = "human"
        FakeProcesses.emit(self, fd, event)


class MacAECControlTests(unittest.TestCase):
    def test_real_loop_with_fake_process_and_event_faults(self):
        for fault in (None, "wrong_round", "wrong_batch", "proxy_requested", "foreign_source", "foreign",
                      "clock", "no_schedule", "duplicate", "eof", "late", "cancel", "backwards"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                fake = MacProcesses(fault)
                try:
                    with patch.object(integration, "M20_HOST_DYLIB_SHA", sha(HOST.with_name("Aftelle.debug.dylib"))):
                        action = lambda: integration._connected_run(BUNDLE, "HOST", HOST, Path(directory)/"run",
                            spawn=fake, clock=fake.clock, mac_aec=CONTEXT)
                        if fault is None:
                            result = action()
                            self.assertEqual(result["status"], "PASS_OFFLINE_CONTROL_ONLY")
                            self.assertEqual(result["commands"], [])
                            self.assertFalse(result["proxy_requested"])
                        else:
                            with self.assertRaises((ValueError, AssertionError, RuntimeError, EOFError, TimeoutError,
                                                    subprocess.TimeoutExpired)):
                                action()
                            receipt = json.loads((Path(directory)/"run/result.json").read_text())
                            self.assertEqual(receipt["status"], "FAIL")
                        self.assertEqual(len(fake.calls), 1)
                        self.assertTrue(any(x.startswith("--apple-vp-mac-aec=") for x in fake.calls[0][0]))
                        self.assertFalse(any("--apple-vp-bt-" in x for x in fake.calls[0][0]))
                        self.assertIsNotNone(fake.child.poll())
                finally:
                    fake.close()

    def test_wrong_candidate_and_mixed_modes_rejected(self):
        with patch.object(integration, "M20_HOST_DYLIB_SHA", "0"*64):
            with self.assertRaises(ValueError): integration.command("HOST", HOST, 3, mac_aec=CONTEXT)
        for kwargs in (dict(human_group="A"), dict(m03_group="A"), dict(onset_group="A")):
            with self.assertRaises(ValueError):
                integration.command("HOST", HOST, 3, mac_aec=CONTEXT, **kwargs)

    def test_operator_batch_stop_reaps_only_owned_fake_child(self):
        fake = MacProcesses()
        try:
            with tempfile.TemporaryDirectory() as directory:
                with patch.object(integration, "M20_HOST_DYLIB_SHA", sha(HOST.with_name("Aftelle.debug.dylib"))):
                    with self.assertRaises(InterruptedError):
                        integration._connected_run(BUNDLE, "HOST", HOST, Path(directory)/"run", spawn=fake,
                            clock=fake.clock, mac_aec=CONTEXT, cancel_requested=lambda: True)
                self.assertTrue(fake.child.terminated)
                self.assertEqual(len(fake.calls), 1)
                result = json.loads((Path(directory)/"run/result.json").read_text())
                self.assertEqual(result["status"], "FAIL")
                self.assertIn("operator Stop", result["error"])
                self.assertEqual(result["audio_exit"], -15)
        finally:
            fake.close()

    def test_original_ui_callbacks_and_failure_preservation_with_fake_pid_only(self):
        for fails in (False, True):
            with self.subTest(fails=fails), tempfile.TemporaryDirectory() as directory:
                fake = MacProcesses()
                fake.child.pid = 4242  # Fake handle; no PID lookup or UI operation is performed.
                calls = []
                def prepare(pid):
                    calls.append(("prepare", pid))
                    if fails: raise TimeoutError("FAKE original consent unavailable")
                def finish(pid):
                    calls.append(("finish", pid))
                    fake.child.code = 0
                try:
                    with patch.object(integration, "M20_HOST_DYLIB_SHA", sha(HOST.with_name("Aftelle.debug.dylib"))):
                        action = lambda: integration._connected_run(BUNDLE, "HOST", HOST, Path(directory)/"run",
                            spawn=fake, clock=fake.clock, mac_aec=CONTEXT, device=True,
                            device_ui=prepare, finish_ui=finish, failure_ui=finish)
                        if fails:
                            with self.assertRaises(TimeoutError): action()
                        else: action()
                    self.assertEqual(calls, [("prepare", 4242), ("finish", 4242)])
                    self.assertIsNotNone(fake.child.poll())
                    receipt = json.loads((Path(directory)/"run/result.json").read_text())
                    self.assertEqual(receipt["audio_exit"], 0)
                finally:
                    fake.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
