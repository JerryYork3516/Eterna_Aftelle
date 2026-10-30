"""Synthetic PCM/metadata, real local pipes and existing Fake children only."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid
from unittest.mock import Mock, patch

import numpy as np

import integration
import m26_channel_allocation as target
from prepare_player import sha
from test_integration import BUNDLE, HOST, FakeProcesses
from test_m07 import HumanProcesses
import test_m20


def context(arm):
    return dict(batch_id="26262626-2626-4262-8262-262626262626", arm=arm,
                round=target.ARMS.index(arm)+1, limit=2)


class AllocationProcesses(HumanProcesses):
    def __init__(self, context, fault=None):
        super().__init__("A", fault)
        self.context = context

    def emit(self, fd, event):
        event = dict(event, batch="R5_M26", scenario="A", proxy_requested=False, **self.context)
        event.setdefault("score_start_ns", self.schedule["score_start_ns"])
        event.setdefault("proxy_stop_ns", self.schedule["proxy_stop_ns"])
        if self.fault == "old_batch": event["batch"] = "R5_M20"
        if self.fault == "wrong_arm": event["arm"] = "foreign"
        FakeProcesses.emit(self, fd, event)


class ControlTests(unittest.TestCase):
    def test_pipe_events_clocks_identity_and_reaping(self):
        for arm in target.ARMS:
            for fault in (None, "old_batch", "wrong_arm", "foreign", "clock", "no_schedule", "duplicate", "eof", "late", "cancel", "backwards"):
                with self.subTest(arm=arm, fault=fault), tempfile.TemporaryDirectory() as directory:
                    fake = AllocationProcesses(context(arm), fault)
                    try:
                        with patch.object(integration, "M26_HOST_DYLIB_SHA", sha(HOST.with_name("Aftelle.debug.dylib"))):
                            action = lambda: integration._connected_run(BUNDLE, "HOST", HOST, Path(directory)/"run",
                                spawn=fake, clock=fake.clock, allocation=context(arm))
                            if fault is None:
                                result = action()
                                self.assertEqual(result["status"], "PASS_OFFLINE_CONTROL_ONLY")
                                self.assertEqual(result["commands"], [])
                            else:
                                with self.assertRaises((ValueError, AssertionError, RuntimeError, EOFError, TimeoutError, subprocess.TimeoutExpired)):
                                    action()
                        self.assertEqual(len(fake.calls), 1)
                        self.assertTrue(any(x.startswith("--apple-vp-channel-allocation=") for x in fake.calls[0][0]))
                        self.assertIsNotNone(fake.child.poll())
                    finally:
                        fake.close()

    def test_wrong_build_mixed_contract_and_frozen_order(self):
        with patch.object(integration, "M26_HOST_DYLIB_SHA", "0"*64):
            with self.assertRaises(ValueError): integration.command("HOST", HOST, 3, allocation=context(target.ARMS[0]))
        for extra in (dict(mac_aec={}), dict(adaptation={}), dict(m03_group="A"), dict(human_group="A")):
            with self.assertRaises(ValueError):
                integration.command("HOST", HOST, 3, allocation=context(target.ARMS[0]), **extra)
        wrong = context(target.ARMS[0]); wrong["round"] = 2
        with self.assertRaises(ValueError): integration.allocation_context(wrong)

    def test_exact_pid_stop_cleanup(self):
        fake = AllocationProcesses(context(target.ARMS[0]))
        fake.child.pid = 4262
        calls = []
        try:
            with tempfile.TemporaryDirectory() as directory, patch.object(integration, "M26_HOST_DYLIB_SHA",
                                                                          sha(HOST.with_name("Aftelle.debug.dylib"))):
                def preserve(pid):
                    calls.append(pid)
                    fake.child.code = 0
                with self.assertRaises(InterruptedError):
                    integration._connected_run(BUNDLE, "HOST", HOST, Path(directory)/"run", spawn=fake,
                        clock=fake.clock, allocation=context(target.ARMS[0]), device=True,
                        device_ui=lambda pid: None, failure_ui=preserve, cancel_requested=lambda: True)
                self.assertEqual(calls, [4262])
                self.assertIsNotNone(fake.child.poll())
        finally:
            fake.close()

    def test_batch_bounds_fresh_consent_stop_failure_and_reuse(self):
        for fault in (None, "stop", "failed_release", "duplicate_run", "exception"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); root.chmod(0o700)
                plan = dict(task="R5_M26", ready=True, limit=2, arms=list(target.ARMS), parameters=target.PARAMETERS,
                            batch_id=str(uuid.uuid4()).upper(), evidence_root=str(root))
                calls, fixed_run = [], str(uuid.uuid4())
                def execute(p, c, r):
                    calls.append(c)
                    if fault == "exception": raise RuntimeError("synthetic failure")
                    if fault == "stop": (root/"STOP").touch()
                    return dict(technical_ok=True, resources_released=fault != "failed_release",
                                run_id=fixed_run if fault == "duplicate_run" else str(uuid.uuid4()), result="INCONCLUSIVE")
                for bad in ("old consent", None):
                    with self.assertRaises(PermissionError):
                        target.run_batch(plan, bad, root, execute=execute, check=lambda _: None)
                with self.assertRaises(PermissionError):
                    target.run_batch(plan, target.CONSENT, root, check=lambda _: None)
                self.assertEqual(calls, [])
                action = lambda: target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
                if fault is None:
                    self.assertEqual(len(action()), 2)
                    self.assertEqual([x["arm"] for x in calls], list(target.ARMS))
                else:
                    with self.assertRaises((RuntimeError, ValueError, InterruptedError)): action()
                count = len(calls)
                with self.assertRaises(FileExistsError): action()
                self.assertEqual(len(calls), count)
                self.assertLessEqual(count, 2)
                self.assertEqual((root/"M26_AUTHORIZATION_CONSUMED.json").stat().st_mode & 0o777, 0o600)


class PlanContractTests(unittest.TestCase):
    def plan(self, root):
        here = Path(target.__file__).resolve().parent
        files = {key: dict(path=str(here/name)) for key, name in (
            ("m26", "m26_channel_allocation.py"), ("integration", "integration.py"),
            ("batch", "m20_batch.py"), ("scorer", "m20_echo.py"),
            ("prepare_ui", "prepare_host_original_ui.applescript"),
            ("start_ui", "start_host_original_ui.applescript"))}
        files.update(dylib=dict(sha256=integration.M26_HOST_DYLIB_SHA),
                     resident=dict(path=str(root/"registered.wav"), sha256=target.RESIDENT_SHA))
        return dict(task="R5_M26", ready=True, limit=2, arms=list(target.ARMS), parameters=target.PARAMETERS,
                    batch_id=str(uuid.uuid4()).upper(), evidence_root=str(root), cache=str(root),
                    executable=str(HOST), bundle=str(BUNDLE), files=files, resident=files["resident"]["path"])

    def test_resident_path_rejected_before_execution_and_authorization_consumption(self):
        for fault in ("missing", None, "", "unregistered.wav", ["registered.wav"]):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); root.chmod(0o700)
                plan = self.plan(root)
                if fault == "missing": plan.pop("resident")
                else: plan["resident"] = fault
                execute = Mock(side_effect=AssertionError("unsafe execution reached"))
                with patch.object(target.batch, "check_plan") as shared:
                    with self.assertRaisesRegex(ValueError, "resident"):
                        target.run_batch(plan, target.CONSENT, root, execute=execute, check=target.check_plan)
                    shared.assert_not_called()
                execute.assert_not_called()
                self.assertFalse((root/"M26_AUTHORIZATION_CONSUMED.json").exists())
                self.assertFalse((root/"arm-1").exists())

    def test_registered_path_reaches_original_prepare_and_start_ui(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = self.plan(root)
            with patch.object(target.batch, "check_plan") as shared:
                target.check_plan(plan)
                shared.assert_called_once_with(plan)
            def connected(*args, **kwargs):
                kwargs["device_ui"](42)
                raise InterruptedError("FAKE_UI_BOUNDARY")
            with patch.object(integration, "_connected_run", side_effect=connected), \
                    patch.object(target.batch, "verify_loaded") as identity, \
                    patch.object(target.batch, "ui", return_value="FAKE_ORIGINAL_UI") as ui:
                with self.assertRaisesRegex(InterruptedError, "FAKE_UI_BOUNDARY"):
                    target.batch.device_round(plan, context(target.ARMS[0]), root, allocation=True)
                self.assertEqual(identity.call_count, 2)
                self.assertEqual(ui.call_args_list[0].args,
                                 (plan["files"]["prepare_ui"]["path"], 42, plan["files"]["resident"]["path"]))
                self.assertEqual(ui.call_args_list[1].args, (plan["files"]["start_ui"]["path"], 42))

    def test_wrong_sha_and_shared_safety_failure_still_reject_before_consumption(self):
        for fault in ("sha", "shared"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); root.chmod(0o700)
                plan = self.plan(root)
                if fault == "sha": plan["files"]["resident"]["sha256"] = "0"*64
                execute = Mock(side_effect=AssertionError("unsafe execution reached"))
                with patch.object(target.batch, "check_plan", side_effect=ValueError("FAKE_SHA_OR_ROUTE_FAILURE")):
                    with self.assertRaises(ValueError):
                        target.run_batch(plan, target.CONSENT, root, execute=execute, check=target.check_plan)
                execute.assert_not_called()
                self.assertFalse((root/"M26_AUTHORIZATION_CONSUMED.json").exists())


class EvidenceTests(unittest.TestCase):
    def fixture(self, arm):
        base = test_m20.ManifestControls(); base.setUp()
        value = base.manifest
        value.pop("mac_aec_batch")
        value["playback_generation"] = 3
        value["host_timing"]["playbackGeneration"] = 2
        expected = dict(batch="R5_M26", scenario="A", proxy_requested=False, **context(arm),
                        source_sha256=target.RESIDENT_SHA, build_sha256=integration.M26_HOST_DYLIB_SHA)
        value["channel_allocation_experiment"] = expected
        value["channel_allocation_witness"] = dict(expected, run_id=value["run_id"], capture_generation=1,
            playback_generation=2, configuration_id=2, frames=76010, buffers=48, closed=True,
            format="16000Hz/3ch/Float32/planar/DiscreteInOrder")
        value["channel_allocation_final_drain"] = value.pop("mac_aec_final_drain")
        value["retained_pcm_bytes"] = 720000
        value["capture_generated_at_seal"] = value["warmup"]["drained_packets"] = 950
        value["packets_sequence_host_time_ns_bytes"] = [[i+1, 1+i*20000000, 960] for i in range(750)]
        value["short_window_diagnostics"]["windows"] *= 750
        for read in value["host_timing"]["runtimeReadbacks"]:
            read["payload"]["microphoneModes"] = dict(status="CONFIRMED_PUBLIC_API", active=0)
        return value, dict(frames=360000, pcm_sha256="synthetic")

    def test_allocation_metadata_and_all_identity_negative_controls(self):
        for arm in target.ARMS:
            value, wav = self.fixture(arm)
            self.assertTrue(target.audit_manifest(value, context(arm), wav, expected_pid=42)["trustworthy"])
            for key, bad in (("run_id", str(uuid.uuid4())), ("capture_generation", 2), ("playback_generation", 3),
                             ("configuration_id", 4), ("source_sha256", "0"*64), ("build_sha256", "0"*64),
                             ("buffers", 49), ("closed", False), ("format", "mono")):
                invalid = copy.deepcopy(value); invalid["channel_allocation_witness"][key] = bad
                with self.assertRaises(ValueError): target.audit_manifest(invalid, context(arm), wav)
            invalid = copy.deepcopy(value); invalid["playback_sha256"] = "0"*64
            with self.assertRaises(ValueError): target.audit_manifest(invalid, context(arm), wav)
            invalid = copy.deepcopy(value); invalid["host_timing"]["playbackGeneration"] = 4
            with self.assertRaises(ValueError): target.audit_manifest(invalid, context(arm), wav)
            invalid = copy.deepcopy(value); invalid["playback_generation"] = 1
            with self.assertRaises(ValueError): target.audit_manifest(invalid, context(arm), wav)
            invalid = copy.deepcopy(value); invalid["host_timing"]["runtimeReadbacks"][0]["payload"]["microphoneModes"]["active"] = 1
            with self.assertRaises(ValueError): target.audit_manifest(invalid, context(arm), wav)

    def test_burst_metric_is_bounded_and_does_not_change_classification(self):
        sample = np.zeros(24000)
        self.assertIsNone(target.transient_share(sample, 0, 1))
        self.assertIsNone(target.transient_share(sample, -1, 1))
        sample[480:1920] = 0.5
        self.assertEqual(target.transient_share(sample, 0, 1), 1)
        self.assertAlmostEqual(target.transient_share(np.ones(24000), 0, 1), 0.06)


if __name__ == "__main__":
    unittest.main(verbosity=2)
