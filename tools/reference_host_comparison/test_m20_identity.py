"""Owned-process identity controls with non-audio files and Fake readbacks only."""
from pathlib import Path
import tempfile
import unittest
import subprocess
from unittest.mock import patch

import m20_batch as batch


class LoadedIdentityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.executable = self.root/"identity_fixture"
        self.dylib = self.root/"Aftelle.debug.dylib"
        self.executable.write_bytes(b"NON_AUDIO_LAUNCHER")
        self.dylib.write_bytes(b"NON_AUDIO_LIBRARY")
        self.plan = dict(executable=str(self.executable), files={
            name: dict(path=str(path), sha256=batch.sha(path))
            for name, path in (("launcher", self.executable), ("dylib", self.dylib))})

    def readback(self, executable=None, dylib=None):
        def mapping(path):
            info = path.stat()
            return dict(path=str(path), inode=info.st_ino, device=info.st_dev)
        executable, dylib = executable or self.executable, dylib or self.dylib
        return dict(pid=4242, executable=str(executable), executable_after=str(executable),
                    mappings=[mapping(executable), mapping(dylib)])

    def test_equivalent_filesystem_paths_are_not_rejected_as_text(self):
        alias = self.root/"alias"
        alias.symlink_to(self.root, target_is_directory=True)
        data = self.readback(alias/self.executable.name, alias/self.dylib.name)
        # The legacy gate and replacement consume the same Fake identity facts.
        with patch.object(batch, "_process_readback", return_value=data, create=True), \
                patch.object(batch.subprocess, "check_output", side_effect=[
                    data["executable"]+"\n", "p4242\nn"+data["mappings"][1]["path"]+"\n"]):
            batch.verify_loaded(4242, self.plan)

    def verify(self, data=None, **kwargs):
        return batch.verify_loaded(4242, self.plan,
            readback=kwargs.pop("readback", lambda pid, timeout: data or self.readback()), **kwargs)

    def rejects(self, code, **kwargs):
        with self.assertRaises(batch.IdentityError) as result:
            self.verify(**kwargs)
        self.assertEqual(result.exception.code, code)

    def test_correct_pid_mapping_inode_and_sha(self):
        receipts = []
        result = self.verify(record=receipts.append)
        self.assertEqual(result["code"], "VERIFIED")
        self.assertEqual(result["files"]["dylib"]["sha256"], self.plan["files"]["dylib"]["sha256"])
        self.assertEqual(receipts, [result])

    def test_wrong_pid_executable_or_second_path_immediately_rejected(self):
        wrong = self.root/"other_executable"
        wrong.write_bytes(self.executable.read_bytes())
        for key, value in (("pid", 4243), ("executable", str(wrong)), ("executable_after", str(wrong))):
            data = self.readback(); data[key] = value
            waits = []
            self.rejects("PROCESS_IDENTITY_MISMATCH", data=data, startup=True, sleep=waits.append)
            self.assertEqual(waits, [])

    def test_wrong_registered_sha_never_queries_or_waits(self):
        for name, code in (("launcher", "PROCESS_IDENTITY_MISMATCH"), ("dylib", "DYLIB_IDENTITY_MISMATCH")):
            with self.subTest(name=name), patch.object(batch, "_process_readback") as query:
                original = self.plan["files"][name]["sha256"]
                self.plan["files"][name]["sha256"] = "0"*64
                try:
                    with self.assertRaises(batch.IdentityError) as result:
                        batch.verify_loaded(4242, self.plan, startup=True)
                    self.assertEqual(result.exception.code, code)
                    query.assert_not_called()
                finally:
                    self.plan["files"][name]["sha256"] = original

    def test_wrong_loaded_library_or_stale_inode_is_not_readiness(self):
        other = self.root/"wrong"; other.mkdir()
        library = other/self.dylib.name; library.write_bytes(b"WRONG")
        for include_correct in (False, True):
            data = self.readback(dylib=library)
            if include_correct: data["mappings"].append(self.readback()["mappings"][1])
            waits = []
            self.rejects("DYLIB_IDENTITY_MISMATCH", data=data, startup=True, sleep=waits.append)
            self.assertEqual(waits, [])
        data = self.readback(); data["mappings"][1]["inode"] += 1
        self.rejects("DYLIB_IDENTITY_MISMATCH", data=data)
        data = self.readback(); data["mappings"][1]["path"] += " (deleted)"
        self.rejects("DYLIB_IDENTITY_MISMATCH", data=data)

    def test_missing_library_has_only_bounded_startup_wait(self):
        now, calls = [0.0], []
        def query(pid, timeout):
            calls.append(timeout)
            data = self.readback()
            if len(calls) < 3: data["mappings"].pop()
            return data
        result = self.verify(readback=query, startup=True, clock=lambda: now[0],
                             sleep=lambda seconds: now.__setitem__(0, now[0]+seconds))
        self.assertEqual([x["code"] for x in result["attempts"]], ["DYLIB_NOT_READY"]*2+["VERIFIED"])
        self.assertAlmostEqual(now[0], .2)
        self.assertEqual(len(calls), 3)

    def test_missing_library_timeout_and_post_startup_rejection(self):
        data = self.readback(); data["mappings"].pop()
        now, waits = [0.0], []
        def sleep(seconds):
            waits.append(seconds); now[0] += seconds
        self.rejects("STARTUP_TIMEOUT", data=data, startup=True, clock=lambda: now[0], sleep=sleep)
        self.assertAlmostEqual(now[0], 3.0)
        self.assertLessEqual(len(waits), 32)
        waits.clear()
        self.rejects("DYLIB_NOT_READY", data=data, sleep=waits.append)
        self.assertEqual(waits, [])

    def test_failed_query_and_late_readback_are_fail_closed(self):
        for error in (OSError("unavailable"), subprocess.TimeoutExpired("FAKE", 1)):
            def query(*args): raise error
            self.rejects("READBACK_UNAVAILABLE", readback=query, startup=True)
        now = [0.0]
        def slow(*args):
            now[0] = 3.01
            return self.readback()
        self.rejects("STARTUP_TIMEOUT", readback=slow, startup=True, clock=lambda: now[0])

    def test_stop_during_readiness_prevents_further_query(self):
        now, calls, receipts = [0.0], [], []
        def query(*args):
            calls.append(1)
            data = self.readback(); data["mappings"].pop()
            return data
        with self.assertRaises(InterruptedError):
            self.verify(readback=query, startup=True, cancelled=lambda: now[0] > 0,
                clock=lambda: now[0], sleep=lambda seconds: now.__setitem__(0, seconds), record=receipts.append)
        self.assertEqual(len(calls), 1)
        self.assertEqual(receipts[0]["code"], "CANCELLED")

    def test_mapping_parser_requires_pid_inode_device_and_complete_query(self):
        valid = "p4242\nftxt\nD0x10\ni42\nn/test\n"
        with patch.object(batch, "_process_path", return_value="/test"):
            for text, code in ((valid, None), (valid.replace("4242", "4243"), "PROCESS_IDENTITY_MISMATCH"),
                               (valid.replace("i42\n", ""), "READBACK_UNAVAILABLE")):
                with patch.object(batch.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, text, "")):
                    if code is None:
                        self.assertEqual(batch._process_readback(4242, 1)["mappings"][0]["device"], 16)
                    else:
                        with self.assertRaises(batch.IdentityError) as result: batch._process_readback(4242, 1)
                        self.assertEqual(result.exception.code, code)

    def test_startup_failure_skips_ui_but_capture_failure_preserves(self):
        self.plan.update(cache=str(self.root), bundle=str(self.root), resident="NON_AUDIO_FAKE",
                         files=dict(self.plan["files"], **{
                             key: dict(path=key) for key in ("prepare_ui", "start_ui", "stop_ui", "finish_ui")}))
        for before_capture in (True, False):
            folder = self.root/("startup" if before_capture else "capture"); folder.mkdir()
            def connected(*args, **kwargs):
                try:
                    kwargs["device_ui"](4242)
                    raise RuntimeError("FAKE post-Capture failure")
                except (batch.IdentityError, RuntimeError):
                    phase = kwargs["failure_ui"](4242)
                    self.assertEqual(phase, "PRE_CAPTURE_OWNED_CHILD_REAP" if before_capture
                                     else "CAPTURE_REQUESTED_STOP_EXPORT_QUIT")
                    raise
            with patch.object(batch.integration, "_connected_run", side_effect=connected), \
                    patch.object(batch, "verify_loaded", side_effect=(
                        batch.IdentityError("PROCESS_IDENTITY_MISMATCH", "FAKE") if before_capture else None)), \
                    patch.object(batch, "ui", return_value="FAKE_ORIGINAL_UI") as ui:
                with self.assertRaises((batch.IdentityError, RuntimeError)):
                    batch.device_round(self.plan, {}, folder)
                self.assertEqual([x.args[0] for x in ui.call_args_list], [] if before_capture else
                                 ["prepare_ui", "start_ui", "stop_ui", "finish_ui"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
