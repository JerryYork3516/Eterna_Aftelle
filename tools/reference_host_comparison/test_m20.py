"""M20 deterministic controls. No device process, audio Engine or UI handler runs."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch

import numpy as np

import integration
import m20_batch as batch
from m20_echo import RATE, analyse, best_match


class EchoControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        rng = np.random.default_rng(20)
        content = rng.normal(size=90000)
        content = np.convolve(content, [1., 0.7, 0.3], "same")
        envelope = np.repeat(np.tile([0.1, 1, 0.3, 0.7, 0.05], 38)[:188], 480)[:90000]
        content = content * envelope * 0.025
        cls.resident = np.r_[np.zeros(RATE), content, np.zeros(32)]

    def signal(self, *, start=4.34, gain=0.5, seed=21):
        signal = np.random.default_rng(seed).normal(0, 1e-5, round(14.86*RATE))
        content = self.resident[RATE:round(4.75*RATE)]
        index = round(start*RATE)
        signal[index:index+len(content)] += content * gain
        return signal

    def screen(self, signal, **kwargs):
        return analyse(signal, kwargs.pop("resident", self.resident), render_start=4.19,
                       render_end=7.94, trustworthy=kwargs.pop("trustworthy", True), **kwargs)

    def test_echo_gain_polarity_delay_and_mild_filter(self):
        for gain in (0.5, -0.5):
            with self.subTest(gain=gain):
                result = self.screen(self.signal(gain=gain))
                self.assertEqual(result["result"], "ECHO_DETECTED")
                self.assertLessEqual(abs(result["metrics"]["match"]["start_seconds"]-4.34), 1/RATE)
                self.assertEqual(result["aec_acceptance"], "UNVERIFIED")
        filtered = np.convolve(self.signal(), [0.8, 0.2], "same")
        self.assertEqual(self.screen(filtered)["result"], "ECHO_DETECTED")

    def test_weak_echo_below_fixed_amplitude_limit_is_inconclusive(self):
        result = self.screen(self.signal(gain=0.15))
        self.assertEqual(result["result"], "INCONCLUSIVE")
        self.assertGreater(abs(result["metrics"]["match"]["ncc"]), 0.99)

    def test_absent_and_silent_microphone_never_prove_speaker_emission(self):
        for signal in (self.signal(gain=0), np.zeros(round(14.86*RATE))):
            result = self.screen(signal)
            self.assertEqual(result["result"], "ECHO_NOT_DETECTED")
            self.assertEqual(result["aec_acceptance"], "UNVERIFIED")
            self.assertEqual(result["physical_emission"], "UNVERIFIED")

    def test_silent_playback_reference_and_time_misalignment_are_inconclusive(self):
        self.assertEqual(self.screen(self.signal(), resident=np.zeros(114032))["result"], "INCONCLUSIVE")
        misplaced = self.screen(self.signal(start=1.0))
        self.assertEqual(misplaced["result"], "INCONCLUSIVE")
        self.assertEqual(misplaced["reason"], "TEMPLATE_OUTSIDE_RENDER_SEARCH")

    def test_reverse_unrelated_loud_noise_and_insufficient_evidence(self):
        unrelated = np.random.default_rng(22).normal(0, 0.03, round(14.86*RATE))
        reverse = self.signal(gain=0)
        reverse[round(4.34*RATE):round(4.34*RATE)+90000] += self.resident[RATE:round(4.75*RATE)][::-1]
        for value in (unrelated, reverse, self.signal()[:5*RATE]):
            self.assertEqual(self.screen(value)["result"], "INCONCLUSIVE")
        self.assertEqual(self.screen(self.signal(), trustworthy=False)["result"], "INCONCLUSIVE")

    def test_reference_purity_determinism_and_search_error(self):
        signal = self.signal()
        before = signal.tobytes(), self.resident.tobytes()
        first = self.screen(signal)
        self.assertEqual(first, self.screen(signal))
        self.assertEqual(before, (signal.tobytes(), self.resident.tobytes()))
        template = self.resident[RATE:round(4.75*RATE)]
        self.assertIsNone(best_match(np.zeros(5), template, 0, 1))


class BatchControls(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.root.chmod(0o700)
        self.plan = dict(task="R5_M20", ready=True, batch_id=str(uuid.uuid4()).upper(), limit=3,
                         evidence_root=str(self.root))
        self.calls, self.checks = [], 0

    def check(self, plan):
        self.checks += 1

    def execute(self, plan, context, root):
        self.calls.append(context)
        return dict(run_id=str(uuid.uuid4()).upper(), technical_ok=True, resources_released=True,
                    result="ECHO_DETECTED" if context["round"] == 1 else "INCONCLUSIVE")

    def run_plan(self, **kwargs):
        return batch.run_batch(self.plan, batch.CONSENT, self.root,
                               execute=kwargs.get("execute", self.execute), check=kwargs.get("check", self.check))

    def test_three_independent_lifecycles_no_acoustic_retry(self):
        result = self.run_plan()
        self.assertEqual(len(result), 3)
        self.assertEqual([x["round"] for x in self.calls], [1, 2, 3])
        self.assertEqual(len({x["run_id"] for x in result}), 3)
        self.assertEqual(self.checks, 3)
        with self.assertRaises(FileExistsError):
            self.run_plan()
        self.assertEqual(len(self.calls), 3)

    def test_default_disabled_missing_consent_precheck_and_limit(self):
        with self.assertRaises(PermissionError):
            batch.run_batch(self.plan, batch.CONSENT, self.root)
        for consent in (None, "R4_REF_HOST_ONCE_LOCAL_RECORDING_AND_ANALYSIS"):
            with self.assertRaises(PermissionError):
                batch.run_batch(self.plan, consent, self.root, execute=self.execute, check=self.check)
        for limit in (0, 4, True):
            self.plan["limit"] = limit
            with self.assertRaises(ValueError):
                self.run_plan()
        self.assertEqual(self.calls, [])
        self.assertFalse((self.root/"M20_AUTHORIZATION_CONSUMED.json").exists())

    def test_stop_failure_or_failed_release_stops_all_remaining_rounds(self):
        for failure in ("cancel", "export", "identity", "release", "permission"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); root.chmod(0o700)
                calls = []
                def execute(*args):
                    calls.append(args[1]["round"])
                    if failure == "release":
                        return dict(technical_ok=True, resources_released=False, result="INCONCLUSIVE")
                    raise InterruptedError(failure)
                with self.assertRaises((InterruptedError, RuntimeError)):
                    batch.run_batch(dict(self.plan, evidence_root=str(root)), batch.CONSENT, root,
                                    execute=execute, check=self.check)
                self.assertEqual(calls, [1])
                self.assertTrue((root/"BATCH_STOPPED.json").is_file())
                self.assertTrue((root/"M20_AUTHORIZATION_CONSUMED.json").is_file())

    def test_duplicate_run_stop_between_rounds_and_permission_scope(self):
        fixed = str(uuid.uuid4())
        def duplicate(*args):
            return dict(self.execute(*args), run_id=fixed)
        with self.assertRaises(ValueError): self.run_plan(execute=duplicate)
        self.assertEqual(len(self.calls), 2)
        self.root.chmod(0o755)
        with self.assertRaises(PermissionError): batch.private_directory(self.root)

    def test_no_rebinding_authorization_and_stop_between_rounds(self):
        with tempfile.TemporaryDirectory() as other:
            Path(other).chmod(0o700)
            with self.assertRaises(PermissionError):
                batch.run_batch(self.plan, batch.CONSENT, Path(other), execute=self.execute, check=self.check)
        def stopped(*args):
            result = self.execute(*args)
            (self.root/"STOP").touch()
            return result
        with self.assertRaises(InterruptedError): self.run_plan(execute=stopped)
        self.assertEqual(len(self.calls), 1)

    def test_initial_precheck_failure_is_consumed_without_capture(self):
        def mismatch(_): raise ValueError("SHA mismatch")
        with self.assertRaises(ValueError): self.run_plan(check=mismatch)
        self.assertEqual(self.calls, [])
        self.assertTrue((self.root/"BATCH_STOPPED.json").is_file())
        self.assertTrue((self.root/"M20_AUTHORIZATION_CONSUMED.json").is_file())

    def test_process_and_context_default_no_device_side_effect(self):
        for value in (dict(batch_id=self.plan["batch_id"], round=4, limit=3),
                      dict(batch_id=self.plan["batch_id"], round=True, limit=3)):
            with self.assertRaises(ValueError): integration.mac_aec_context(value)
        with patch("subprocess.Popen") as spawn:
            with self.assertRaises(PermissionError): batch.disabled_round()
            spawn.assert_not_called()

    def test_route_and_unknown_volume_fail_before_capture(self):
        devices = dict(input=dict(name="FAKE BT", transport="blue", input_channels=1, output_channels=0),
                       output=dict(name="FAKE BT", transport="blue", output_channels=2))
        plan = dict(device_probe="FAKE_ONLY_PROBE", devices={})
        with patch("subprocess.check_output", side_effect=[json.dumps(devices), "input volume:53, output volume:75"]):
            with self.assertRaisesRegex(ValueError, "target route"):
                batch.probe(plan)
        devices["input"].update(name="TinyUSB Fake", transport="usb ")
        devices["output"].update(name="Mac mini Fake", transport="bltn", output_volume_scalar="UNKNOWN", output_muted=0)
        for direction in ("input", "output"):
            devices[direction].update(uid_sha256="FAKE", alive=1, running=0)
        plan["devices"] = copy.deepcopy(devices)
        with patch("subprocess.check_output", side_effect=[json.dumps(devices), "input volume:60, output volume:55, output muted:false"]):
            with self.assertRaisesRegex(ValueError, "volume/mute"):
                batch.probe(plan)


class ManifestControls(unittest.TestCase):
    def setUp(self):
        self.context = dict(batch_id=str(uuid.uuid4()).upper(), round=1, limit=3)
        self.wav = dict(pcm_sha256="synthetic", frames=480)
        direction = dict(status="CONFIRMED", bindingStatus="PROCESS_DEVICE_METADATA_MATCHES_DEFAULT", deviceIDs=[1])
        payload = dict(issues=[], formats=dict(input="FAKE_16K_3CH"), microphoneModes=dict(active=0),
                       voiceProcessing=dict(engineRunning=True, inputEnabled=True, outputEnabled=True,
                                            agcEnabled=True, bypass=False, inputMuted=False),
                       processBinding=dict(status="CONFIRMED", requestedPID=42, observedPID=42, observedPIDAfter=42,
                                           input=direction, output=copy.deepcopy(direction)))
        run_id = str(uuid.uuid4()).upper()
        stream = dict(missingTime=0, duplicate=0, backwards=0, sampleDiscontinuities=0, hostDiscontinuities=0)
        timing = dict(runID=run_id, captureGeneration=1, configurationID=2, skippedUpdates=0,
                      invalidBuffers=0, staleCallbacks=0,
                      input=stream, playerRender=dict(stream, firstNonzeroContentNs=4_200_000_000,
                                                    lastNonzeroContentNs=7_940_000_000),
                      engineConfigurationEvents=dict(status="CONFIRMED", count=0, skippedNotifications=0,
                                                     observationClosed=True), runtimeReadbacks=[])
        for phase in ("engineStarted", "residentPlaybackStarted"):
            timing["runtimeReadbacks"].append(dict(phase=phase, runID=run_id, captureGeneration=1,
                                                  configurationID=2, payload=copy.deepcopy(payload)))
        self.manifest = dict(mac_aec_batch=dict(batch="R5_M20", scenario="A", proxy_requested=False, **self.context),
            scenario="A", playback_sha256=batch.RESIDENT_SHA, processed_sha256="synthetic", retained_pcm_bytes=960,
            playback_started_count=1, playback_state="completed", data_mode="RECORDING", requested_agc_enabled=True,
            byte_limit=720000, silent_smoke=False, capture_generation=1, run_id=run_id, host_timing=timing,
            mac_aec_final_drain=dict(generation=1, pending_before=0, drained=0), capture_generated_at_seal=1,
            native=dict(coverage_valid=True, issues=[], rejections=dict(native_clock=0), run_id=run_id,
                        configuration_id=2, generation=1),
            packets_sequence_host_time_ns_bytes=[[1, 1, 960]], total_collection_limit_ns=19_000_000_000,
            short_window_diagnostics=dict(windows=[dict(status="MATCHED_CONTENT_COVERAGE")]),
            warmup=dict(tail_coverage="PARTIAL", drained_packets=1))
        for key in ("capture_drop_count", "capture_stale_count", "capture_queued_at_seal", "playback_underrun_count",
                    "playback_rejected_callback_count"):
            self.manifest[key] = 0

    def test_exact_metadata_contract_and_missing_windows(self):
        result = batch.audit_manifest(self.manifest, self.context, self.wav, expected_pid=42)
        self.assertTrue(result["trustworthy"])
        self.assertEqual(result["mic_modes"], [dict(active=0), dict(active=0)])
        self.manifest["short_window_diagnostics"]["windows"] = []
        self.assertFalse(batch.audit_manifest(self.manifest, self.context, self.wav)["trustworthy"])

    def test_final_drain_requires_generation_and_packet_conservation(self):
        for kind in ("missing", "wrong_generation", "missing_packet", "bad_count", "boolean_count", "missing_counts"):
            manifest = copy.deepcopy(self.manifest)
            if kind == "missing": manifest.pop("mac_aec_final_drain")
            if kind == "wrong_generation": manifest["mac_aec_final_drain"]["generation"] += 1
            if kind == "missing_packet": manifest["warmup"]["drained_packets"] = 0
            if kind == "bad_count": manifest["mac_aec_final_drain"]["pending_before"] = 5
            if kind == "boolean_count": manifest["mac_aec_final_drain"]["drained"] = False
            if kind == "missing_counts":
                manifest.pop("capture_generated_at_seal")
                manifest["warmup"].pop("drained_packets")
            with self.assertRaisesRegex(ValueError, "final drain"):
                batch.audit_manifest(manifest, self.context, self.wav)

    def test_observation_loss_and_render_clock_fault_stop_batch_qualification(self):
        for key in ("skippedUpdates", "invalidBuffers", "staleCallbacks", "render_clock"):
            manifest = copy.deepcopy(self.manifest)
            if key == "render_clock": manifest["host_timing"]["playerRender"]["sampleDiscontinuities"] = 1
            else: manifest["host_timing"][key] = 1
            with self.assertRaises(ValueError): batch.audit_manifest(manifest, self.context, self.wav)

    def test_runtime_identity_engine_configuration_clock_and_export_faults(self):
        for fault in ("pid", "agc", "engine", "clock", "sha", "run", "mode", "format", "counter"):
            with self.subTest(fault=fault):
                manifest = copy.deepcopy(self.manifest)
                timing = manifest["host_timing"]
                payload = timing["runtimeReadbacks"][1]["payload"]
                if fault == "pid": payload["processBinding"]["requestedPID"] = 43
                if fault == "agc": payload["voiceProcessing"]["agcEnabled"] = False
                if fault == "engine": timing["engineConfigurationEvents"]["count"] = 1
                if fault == "clock": timing["input"]["sampleDiscontinuities"] = 1
                if fault == "sha": manifest["processed_sha256"] = "wrong"
                if fault == "run": manifest["native"]["run_id"] = "foreign"
                if fault == "mode": payload["microphoneModes"]["active"] = 1
                if fault == "format": payload["formats"] = dict(output="changed")
                if fault == "counter": manifest["capture_drop_count"] = 1
                with self.assertRaises(ValueError):
                    batch.audit_manifest(manifest, self.context, self.wav, expected_pid=42)


if __name__ == "__main__":
    unittest.main(verbosity=2)
