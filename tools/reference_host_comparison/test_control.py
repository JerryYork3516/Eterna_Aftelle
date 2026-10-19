import ast
import hashlib
import io
import json
import os
from pathlib import Path
import queue
import select
import subprocess
import tempfile
import threading
import types
import unittest
import uuid

import numpy as np
from scipy.io import wavfile

from controller import original_single_run, ReferenceRun, schedule
from materials import digest, pcm16, PROXY_SHA, RESIDENT_SHA

SOURCE = Path(os.environ["R2_ORIGINAL_CONTROLLER"])
ASSETS = Path(os.environ["R2_ASSETS_DIR"])
START = 10_000_000_000
IDENTITY = "11111111-1111-4111-8111-111111111111"


def event():
    return dict(schema_version=1, source="ADAPTED_REF", event="schedule", run_id=IDENTITY,
                clock="mach_absolute_nanoseconds", observation_start_ns=START,
                near_start_ns=START+4_000_000_000, near_stop_ns=START+9_000_000_000,
                anchor=dict(absolute_before=START, continuous=START+900_000_000,
                            absolute_after=START, numer=1, denom=1))


class ControlTests(unittest.TestCase):
    def setUp(self):
        self.original = original_single_run(SOURCE)

    def test_reference_play_stop_once(self):
        plan = ReferenceRun(self.original)
        plan.accept(event(), START)
        self.assertEqual(plan.actions(START), [])
        self.assertEqual(plan.actions(START+4_000_000_000), ["PLAY"])
        self.assertEqual(plan.actions(START+4_000_000_000), [])
        self.assertEqual(plan.actions(START+9_000_000_000), ["STOP"])
        self.assertEqual(plan.actions(START+10_000_000_000), [])

    def test_host_eleven_second_window_unchanged(self):
        plan = self.original(4)
        message = dict(schema_version=1, clock="mach_absolute_nanoseconds", event="schedule",
                       run_id=IDENTITY, score_start_ns=START+4_000_000_000, proxy_stop_ns=START+15_000_000_000)
        plan.accept(message, START)
        self.assertEqual(plan.actions(START+4_000_000_000), ["PLAY"])
        self.assertEqual(plan.actions(START+15_000_000_000), ["STOP"])

    def test_cancel_and_foreign_run(self):
        for started in (False, True):
            plan = ReferenceRun(self.original)
            plan.accept(event(), START)
            if started: self.assertEqual(plan.actions(START+4_000_000_000), ["PLAY"])
            terminal = dict(schema_version=1, source="ADAPTED_REF", clock="mach_absolute_nanoseconds",
                            event="cancel", run_id=str(uuid.uuid4()))
            with self.assertRaises(AssertionError): plan.accept(terminal, START+5_000_000_000)
            terminal["run_id"] = IDENTITY
            plan.accept(terminal, START+5_000_000_000)
            self.assertEqual(plan.actions(START+5_000_000_000), ["STOP"])
            self.assertEqual(plan.actions(START+5_000_000_000), [])

    def test_missing_schedule_does_not_play(self):
        self.assertEqual(ReferenceRun(self.original).actions(START+99_000_000_000), [])

    def test_bad_fields_fail_closed(self):
        for key, value in [("run_id", "bad"), ("clock", "mach_continuous_ticks"),
                           ("source", "FROZEN_REF"), ("schema_version", 2),
                           ("near_start_ns", START), ("near_stop_ns", START+11_000_000_000),
                           ("observation_start_ns", START+1)]:
            message = event()
            message[key] = value
            with self.assertRaises((ValueError, AssertionError)):
                ReferenceRun(self.original).accept(message, START)

    def test_clock_zero_overflow_and_wide_bracket(self):
        for key, value in [("numer", 0), ("denom", 0), ("absolute_after", START-1),
                           ("absolute_after", START+1_000_001), ("continuous", 0),
                           ("absolute_before", True), ("absolute_before", 2**65)]:
            message = event()
            message["anchor"][key] = value
            with self.assertRaises(ValueError): schedule(message)

    def test_nonunit_timebase_matches_swift(self):
        message = event()
        message["anchor"] = dict(absolute_before=1_000_000_000, continuous=1_000_900_000,
                                 absolute_after=1_000_000_002, numer=125, denom=3)
        message.update(observation_start_ns=41_666_666_708, near_start_ns=45_666_666_708,
                       near_stop_ns=50_666_666_708)
        self.assertEqual(schedule(message)["score_start_ns"], 45_666_666_708)

    def test_duplicate_late_start_and_stop(self):
        plan = ReferenceRun(self.original)
        plan.accept(event(), START)
        with self.assertRaises(AssertionError): plan.accept(event(), START)
        plan = ReferenceRun(self.original)
        plan.accept(event(), START)
        with self.assertRaisesRegex(AssertionError, "missed start"):
            plan.actions(START+4_050_000_001)
        plan = ReferenceRun(self.original)
        plan.accept(event(), START)
        self.assertEqual(plan.actions(START+4_000_000_000), ["PLAY"])
        with self.assertRaisesRegex(AssertionError, "missed quiet"):
            plan.actions(START+9_050_000_001)

    def test_original_controller_identity_change_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory)/"changed.py"
            file.write_bytes(SOURCE.read_bytes()+b"\n")
            with self.assertRaises(ValueError): original_single_run(file)

    def test_common_proxy_samples_and_no_source_truncation(self):
        ref = pcm16(ASSETS/"REF_proxy.wav", PROXY_SHA)
        rate, host = wavfile.read(ASSETS/"HOST_proxy.wav")
        self.assertEqual(rate, 24000)
        self.assertTrue(np.all(host[:96000] == 0))
        self.assertTrue(np.array_equal(ref, host[96000:]))
        self.assertTrue(np.array_equal(ref[:120000], host[96000:216000]))

    def test_resident_content_and_onset_alignment(self):
        rate, ref = wavfile.read(ASSETS/"REF_resident_8s_f32.wav")
        host = pcm16(ASSETS/"HOST_resident.wav", RESIDENT_SHA)
        self.assertEqual((rate, ref.dtype, len(ref)), (16000, np.dtype("float32"), 128000))
        ref_start = 2+np.flatnonzero(ref)[0]/16000
        host_start = 3+np.flatnonzero(host)[0]/24000
        self.assertLessEqual(abs(ref_start-host_start), 0.001)
        self.assertLessEqual(np.max(np.abs(ref)), 1)
        self.assertEqual(digest(ASSETS/"HOST_resident.wav"), RESIDENT_SHA)

    def test_existing_execute_cleans_up_on_child_exit_and_pipe_loss(self):
        tree = ast.parse(SOURCE.read_text())
        execute = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "execute")
        for failed_child in (True, False):
            with tempfile.TemporaryDirectory() as directory:
                helper = types.SimpleNamespace(
                    stdout=io.StringIO('{"event":"proxy_ready"}\n'), stdin=io.StringIO(),
                    poll=lambda: None, wait=lambda **kw: 0, terminate=lambda: None)
                child = types.SimpleNamespace(pid=100, poll=lambda: 1 if failed_child else None,
                                               terminate=lambda: None, wait=lambda **kw: 0, kill=lambda: None)
                launches = []
                def spawn(argv, **kwargs):
                    launches.append(argv)
                    return helper if len(launches) == 1 else child
                fake = types.SimpleNamespace(Popen=spawn, PIPE=subprocess.PIPE, DEVNULL=subprocess.DEVNULL,
                                             TimeoutExpired=subprocess.TimeoutExpired)
                namespace = dict(__file__=str(Path(directory)/"sync_once.py"), Path=Path, os=os, json=json,
                                 subprocess=fake, queue=queue, threading=threading, select=select,
                                 hashlib=hashlib, now_ns=lambda: START, SingleRun=self.original)
                exec(compile(ast.Module(body=[execute], type_ignores=[]), str(SOURCE), "exec"), namespace)
                args = types.SimpleNamespace(arm="B", fixture=str(ASSETS/"REF_proxy.wav"), executable="NEVER_EXECUTED")
                with self.assertRaises(AssertionError): namespace["execute"](args)
                self.assertEqual(len(launches), 2)
                self.assertEqual(helper.stdin.getvalue(), "STOP\n")

    def test_legacy_controller_rejects_derived_host_fixture_before_launch(self):
        tree = ast.parse(SOURCE.read_text())
        execute = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "execute")
        with tempfile.TemporaryDirectory() as directory:
            launches = []
            fake = types.SimpleNamespace(Popen=lambda *a, **k: launches.append(a))
            namespace = dict(__file__=str(Path(directory)/"sync_once.py"), Path=Path, os=os,
                             json=json, hashlib=hashlib, subprocess=fake)
            exec(compile(ast.Module(body=[execute], type_ignores=[]), str(SOURCE), "exec"), namespace)
            args = types.SimpleNamespace(arm="B", fixture=str(ASSETS/"HOST_proxy.wav"), executable="NEVER_EXECUTED")
            with self.assertRaises(AssertionError): namespace["execute"](args)
            self.assertEqual(launches, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
