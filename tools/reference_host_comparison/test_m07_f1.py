"""F1 reuses M07 human capture with separate onset identity; Fake processes only."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import integration
import m07_once
from prepare_player import sha
from test_integration import BUNDLE, HOST, FakeProcesses
from test_m07 import HumanProcesses


class OnsetProcesses(HumanProcesses):
    def emit(self, fd, event):
        event = dict(event, batch="R5_M07_F1", scenario="C", source="human", proxy_requested=False,
                     onset_group=self.group, score_start_ns=self.schedule["score_start_ns"])
        event["human_speech_stop_ns"] = event.pop("proxy_stop_ns", event["score_start_ns"] + 11_000_000_000)
        event["human_start_cue_ns"] = event["score_start_ns"] + (5_500_000_000 if self.group == "A" else 0)
        if self.fault == "legacy": event["batch"] = "R5_M07"
        if self.fault == "wrong_group": event["onset_group"] = "B"
        if self.fault == "wrong_source": event["source"] = "bluetooth"
        if self.fault == "cue": event["human_start_cue_ns"] += 1
        if self.fault == "bool_cue": event["human_start_cue_ns"] = True
        if self.fault == "duration": event["human_speech_stop_ns"] += 1
        if self.fault == "shifted_stop" and event["event"] == "stop":
            event["score_start_ns"] += 1
            event["human_start_cue_ns"] += 1
        FakeProcesses.emit(self, fd, event)


class OnsetTests(unittest.TestCase):
    def setUp(self):
        identity = patch.object(integration, "F1_HOST_DYLIB_SHA", sha(HOST.with_name("Aftelle.debug.dylib")))
        identity.start()
        self.addCleanup(identity.stop)

    def test_a_b_control_and_failure_cleanup(self):
        for group, fault in [("A", None), ("B", None)] + [("A", x) for x in (
                "legacy", "wrong_group", "wrong_source", "cue", "bool_cue", "duration", "foreign",
                "clock", "no_schedule", "duplicate", "eof", "late", "cancel", "child_exit", "shifted_stop")]:
            with self.subTest(group=group, fault=fault), tempfile.TemporaryDirectory() as directory:
                fake = OnsetProcesses(group, fault)
                evidence = Path(directory) / "run"
                try:
                    args = dict(spawn=fake, clock=fake.clock, human_group="C", onset_group=group)
                    if fault:
                        with self.assertRaises((ValueError, AssertionError, RuntimeError, EOFError, TimeoutError,
                                                subprocess.TimeoutExpired)):
                            integration._connected_run(BUNDLE, "HOST", HOST, evidence, **args)
                        self.assertEqual(json.loads((evidence / "result.json").read_text())["status"], "FAIL")
                        self.assertIsNotNone(fake.child.poll())
                    else:
                        result = integration._connected_run(BUNDLE, "HOST", HOST, evidence, **args)
                        self.assertEqual((result["batch"], result["group"], result["commands"]),
                                         ("R5_M07_F1", group, []))
                        self.assertEqual(result["status"], "PASS_OFFLINE_CONTROL_ONLY")
                    self.assertEqual(len(fake.calls), 1)
                    self.assertIn("--apple-vp-human-onset=" + group, fake.calls[0][0])
                    self.assertFalse(any("--apple-vp-human-abc=" in x for x in fake.calls[0][0]))
                finally:
                    fake.close()

    def test_default_and_old_consent_cannot_launch(self):
        for consent in (None, m07_once.CONSENT):
            with self.subTest(consent=consent), patch("subprocess.Popen") as spawn:
                with self.assertRaises(PermissionError):
                    m07_once.run(BUNDLE, "A", HOST, Path("NOT_CREATED"), consent=consent, onset=True)
                spawn.assert_not_called()

    def test_each_group_consumed_once_and_prior_release_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); root.chmod(0o700)
            for group in ("A", "B"):
                fake = OnsetProcesses(group)
                try:
                    result = m07_once.run(BUNDLE, group, HOST, root / group, onset=True,
                                          spawn=fake, clock=fake.clock)
                    with self.assertRaises(FileExistsError):
                        m07_once.run(BUNDLE, group, HOST, root / group, onset=True,
                                     spawn=fake, clock=fake.clock)
                    self.assertEqual(len(fake.calls), 1)
                    (root / group / "release.json").write_text(json.dumps(dict(
                        batch="R5_M07_F1", group=group, run_id=result["run_id"], safe_to_continue=True)))
                finally:
                    fake.close()

    def test_old_batch_and_failed_release_block_b(self):
        for batch, safe in (("R5_M07", True), ("R5_M07_F1", False), ("R5_M07_F1", 1)):
            with self.subTest(batch=batch, safe=safe), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve(); root.chmod(0o700); (root / "A").mkdir()
                result = dict(status="PASS_OFFLINE_CONTROL_ONLY", batch=batch, group="A", source="human",
                              proxy_requested=False, run_id="previous")
                (root / "A/result.json").write_text(json.dumps(result))
                (root / "A/release.json").write_text(json.dumps(dict(
                    batch=batch, group="A", run_id="previous", safe_to_continue=safe)))
                fake = OnsetProcesses("B")
                try:
                    with self.assertRaises(ValueError):
                        m07_once.run(BUNDLE, "B", HOST, root / "B", onset=True, spawn=fake, clock=fake.clock)
                    self.assertEqual(fake.calls, [])
                finally:
                    fake.close()

    def test_invalid_combinations_and_sha_rejected(self):
        for human, onset in (("A", "A"), ("C", "C"), (None, "A")):
            with self.subTest(human=human, onset=onset), self.assertRaises(ValueError):
                integration.command("HOST", HOST, 3, human_group=human, onset_group=onset)
        with patch.object(integration, "F1_HOST_DYLIB_SHA", "0" * 64), self.assertRaises(ValueError):
            integration.command("HOST", HOST, 3, human_group="C", onset_group="A")


if __name__ == "__main__":
    unittest.main(verbosity=2)
