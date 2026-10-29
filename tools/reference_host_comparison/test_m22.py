"""M22 control and evidence contracts with synthetic PCM and existing Fake handles only."""
import copy
import hashlib
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch

import numpy as np

import integration
import m22_adaptation as target
from m20_echo import RATE, load_wav
from prepare_player import sha
from test_integration import BUNDLE, HOST, FakeProcesses
from test_m07 import HumanProcesses
import test_m20


class AdaptationProcesses(HumanProcesses):
    def __init__(self, context, fault=None):
        super().__init__("A", fault)
        self.context = context

    def emit(self, fd, event):
        event = dict(event, batch="R5_M22", scenario="A", proxy_requested=False, **self.context)
        event.setdefault("score_start_ns", self.schedule["score_start_ns"])
        event.setdefault("proxy_stop_ns", self.schedule["proxy_stop_ns"])
        if self.fault == "foreign_arm": event["arm"] = "foreign"
        if self.fault == "old_batch": event["batch"] = "R5_M20"
        FakeProcesses.emit(self, fd, event)


def context(arm):
    return dict(batch_id="22222222-2222-4222-8222-222222222222", arm=arm,
                round=target.ARMS.index(arm)+1, limit=3)


class ControlTests(unittest.TestCase):
    def test_real_pipe_loop_without_proxy_and_identity_faults(self):
        for arm in target.ARMS:
            for fault in (None, "foreign_arm", "old_batch", "foreign", "clock", "no_schedule", "duplicate",
                          "eof", "late", "cancel", "backwards"):
                with self.subTest(arm=arm, fault=fault), tempfile.TemporaryDirectory() as directory:
                    fake = AdaptationProcesses(context(arm), fault)
                    try:
                        with patch.object(integration, "M22_HOST_DYLIB_SHA", sha(HOST.with_name("Aftelle.debug.dylib"))):
                            action = lambda: integration._connected_run(BUNDLE, "HOST", HOST, Path(directory)/"run",
                                spawn=fake, clock=fake.clock, adaptation=context(arm))
                            if fault is None:
                                result = action()
                                self.assertEqual(result["commands"], [])
                                self.assertEqual(result["status"], "PASS_OFFLINE_CONTROL_ONLY")
                            else:
                                with self.assertRaises((ValueError, AssertionError, RuntimeError, EOFError, TimeoutError, subprocess.TimeoutExpired)):
                                    action()
                        self.assertEqual(len(fake.calls), 1)
                        self.assertTrue(any(x.startswith("--apple-vp-adaptation=") for x in fake.calls[0][0]))
                        self.assertFalse(any("--apple-vp-mac-aec" in x for x in fake.calls[0][0]))
                        self.assertIsNotNone(fake.child.poll())
                    finally:
                        fake.close()

    def test_stop_and_preserve_exact_owned_fake_process(self):
        fake = AdaptationProcesses(context("voicedTwice"))
        fake.child.pid = 4242
        calls = []
        try:
            with tempfile.TemporaryDirectory() as directory, patch.object(integration, "M22_HOST_DYLIB_SHA",
                                                                          sha(HOST.with_name("Aftelle.debug.dylib"))):
                def preserve(pid):
                    calls.append(pid)
                    fake.child.code = 0
                with self.assertRaises(InterruptedError):
                    integration._connected_run(BUNDLE, "HOST", HOST, Path(directory)/"run", spawn=fake,
                        clock=fake.clock, adaptation=context("voicedTwice"), device=True,
                        device_ui=lambda pid: None, failure_ui=preserve, cancel_requested=lambda: True)
                self.assertEqual(calls, [4242])
                self.assertIsNotNone(fake.child.poll())
        finally:
            fake.close()

    def test_mixed_or_wrong_sha_and_order_rejected(self):
        with patch.object(integration, "M22_HOST_DYLIB_SHA", "0"*64):
            with self.assertRaises(ValueError): integration.command("HOST", HOST, 3, adaptation=context("voicedTwice"))
        for kwargs in (dict(mac_aec={}), dict(m03_group="A"), dict(human_group="A")):
            with self.assertRaises(ValueError): integration.command("HOST", HOST, 3, adaptation=context("voicedTwice"), **kwargs)
        wrong = context("voicedTwice")
        wrong["round"] = 2
        with self.assertRaises(ValueError): integration.adaptation_context(wrong)

    def test_three_arms_stop_bound_and_non_reusable_authorization(self):
        for failure in (None, 1, 2, 3, "stop"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                root.chmod(0o700)
                plan = dict(task="R5_M22", ready=True, limit=3, arms=list(target.ARMS),
                            batch_id=str(uuid.uuid4()).upper(), evidence_root=str(root))
                calls = []
                def execute(p, c, path):
                    calls.append(c["arm"])
                    if failure == len(calls): raise RuntimeError("synthetic technical failure")
                    if failure == "stop": (root/"STOP").touch()
                    return dict(technical_ok=True, resources_released=True, run_id=str(uuid.uuid4()), result="INCONCLUSIVE")
                with self.assertRaises(PermissionError): target.run_batch(plan, "old consent", root, execute=execute, check=lambda _: None)
                self.assertEqual(calls, [])
                action = lambda: target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
                if failure is None:
                    self.assertEqual(len(action()), 3)
                else:
                    with self.assertRaises((RuntimeError, InterruptedError)): action()
                self.assertEqual(calls, list(target.ARMS)[:len(calls)])
                count = len(calls)
                with self.assertRaises(FileExistsError): action()
                self.assertEqual(len(calls), count)


class EvidenceTests(unittest.TestCase):
    def manifest(self, arm):
        base = test_m20.ManifestControls()
        base.setUp()
        value = base.manifest
        value.pop("mac_aec_batch")
        value["adaptation_experiment"] = dict(batch="R5_M22", scenario="A", proxy_requested=False, **context(arm))
        value["adaptation_final_drain"] = value.pop("mac_aec_final_drain")
        value["warmup"]["score_start_content_boundary_ns"] = 1_000_000_000
        value["adaptation_plays"] = []
        witnesses = []
        for index, (offset, silent) in enumerate(target.plays_for(arm), 1):
            planned = 1_000_000_000+offset*1_000_000_000
            zero_sha = hashlib.sha256(bytes(228064)).hexdigest()
            value["adaptation_plays"].append(dict(index=index, silent=silent, source_pcm_bytes=228064,
                source_pcm_sha256=zero_sha if silent else target.RESIDENT_PCM_SHA, planned_ns=planned,
                request_ns=planned+20, completed_ns=planned+4_800_000_000, playback_generation=index+1))
            witnesses.append(dict(index=index, silent=silent, generation=index+1, playerWasPlaying=index > 1, preparedAtNs=planned+10,
                startedAtNs=planned+30, completedAtNs=planned+4_750_000_000, scheduledFrames=76010,
                scheduledNonzeroFrames=0 if silent else 50000,
                render=dict(nonzeroFrames=0 if silent else 50000)))
        timing = value["host_timing"]
        for read in timing["runtimeReadbacks"]:
            read["payload"]["microphoneModes"]["status"] = "CONFIRMED_PUBLIC_API"
        timing["events"] = [dict(event=name, count=1) for name in
                            ("engineStartBefore", "engineStartReturned", "playerPlayBefore", "playerPlayReturned")]
        timing["events"] += [dict(event=name, count=len(witnesses)) for name in ("playbackStarted", "playbackCompleted")]
        timing["adaptation"] = dict(first=witnesses[0])
        if len(witnesses) == 2: timing["adaptation"]["second"] = witnesses[1]
        value["playback_started_count"] = len(witnesses)
        for key in ("scheduledFrames", "scheduledNonzeroFrames"):
            timing[key] = sum(x[key] for x in witnesses)
        timing["playerRender"]["nonzeroFrames"] = timing["scheduledNonzeroFrames"]
        return value, base.wav

    def test_registered_arms_and_all_negative_evidence(self):
        for arm in target.ARMS:
            value, wav = self.manifest(arm)
            self.assertTrue(target.audit_manifest(value, context(arm), wav, expected_pid=42)["trustworthy"])
        value, wav = self.manifest("voicedTwice")
        for fault in ("generation", "overlap", "late", "extra", "capture", "render", "mode", "source", "configuration"):
            with self.subTest(fault=fault):
                bad = copy.deepcopy(value)
                if fault == "generation": bad["adaptation_plays"][1]["playback_generation"] = 2
                if fault == "overlap": bad["host_timing"]["adaptation"]["second"]["preparedAtNs"] = 1
                if fault == "late": bad["adaptation_plays"][1]["request_ns"] += 500_000_000
                if fault == "extra": bad["adaptation_plays"].append(copy.deepcopy(bad["adaptation_plays"][0]))
                if fault == "capture": bad["capture_queued_at_seal"] = 1
                if fault == "render": bad["host_timing"]["playerRender"]["nonzeroFrames"] += 1
                if fault == "mode": bad["host_timing"]["runtimeReadbacks"][0]["payload"]["microphoneModes"]["active"] = None
                if fault == "source": bad["adaptation_plays"][0]["source_pcm_sha256"] = "wrong"
                if fault == "configuration": bad["host_timing"]["engineConfigurationEvents"]["count"] = 1
                with self.assertRaises(ValueError): target.audit_manifest(bad, context("voicedTwice"), wav, expected_pid=42)

    def test_two_template_windows_and_no_audio_mutation(self):
        source, _ = load_wav(os.environ["M20_RESIDENT_WAV"], resident=True)
        samples = np.random.default_rng(22).normal(0, 1e-5, round(14.86*RATE))
        witnesses, records = [], []
        for index, (onset, gain) in enumerate(((4.15, 0.5), (10.15, 0.05)), 1):
            content = source[RATE:round(4.75*RATE)]
            pos = round((onset+0.10)*RATE)
            samples[pos:pos+len(content)] += content*gain
            witnesses.append(dict(index=index, silent=False, render=dict(firstNonzeroContentNs=round(onset*1e9),
                                                                        lastNonzeroContentNs=round((onset+3.75)*1e9))))
            records.append({})
        metadata = dict(trustworthy=True, plays=witnesses, playback_records=records, origin_ns=0)
        before = samples.tobytes(), source.tobytes()
        result = target.analyse_plays(samples, source, metadata)
        self.assertEqual(result["result"], "INCONCLUSIVE")
        self.assertEqual(result["physical_emission"], "UNVERIFIED")
        for index, row in enumerate(result["plays"]):
            self.assertGreater(row["match"]["ncc"], 0.99)
            self.assertAlmostEqual(row["composite_delay_seconds"], 0.1, delta=1/RATE)
            self.assertGreater(row["match"]["ncc"]-abs(row["reverse_control"]["ncc"]), 0.1)
            self.assertEqual(len(row["energy_windows"]["20"]), 187)
        delta = result["plays"][0]["residual"]["rms_dbfs"]-result["plays"][1]["residual"]["rms_dbfs"]
        self.assertAlmostEqual(delta, 20, delta=0.01)
        self.assertEqual(before, (samples.tobytes(), source.tobytes()))
        for invalid in (np.zeros_like(source), source[:100]):
            with self.assertRaises(ValueError): target.analyse_plays(samples, invalid, metadata)
        with self.assertRaises(ValueError): target.analyse_plays(samples[:12*RATE], source, metadata)


if __name__ == "__main__":
    unittest.main(verbosity=2)
