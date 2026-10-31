"""M27 parent/child identity and finite batch tests; no device or UI execution."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import Mock, patch

import m27_stability as target
import test_m26 as legacy


def plan_for(root):
    batch_id = str(uuid.uuid4()).upper()
    evidence = root/f"m27-original-aec-{batch_id}"
    evidence.mkdir(mode=0o700)
    plan = legacy.PlanContractTests().plan(root)
    plan.update(task="R5_M27", limit=3, arms=[target.ARM]*3, parameters=target.PARAMETERS,
                schema_version=1, batch_id=batch_id, evidence_root=str(evidence), cache=str(root))
    plan["rounds"] = [target.context(batch_id, n) for n in range(1, 4)]
    plan["files"]["m27"] = dict(path=str(Path(target.__file__).resolve()), sha256="synthetic")
    plan["files"]["launcher"] = dict(sha256=target.allocation.integration.HOST_BINARY_SHA)
    return plan, evidence


def result_for(context, *, run_id=None, verdict="ECHO_NOT_DETECTED"):
    run_id = run_id or str(uuid.uuid4()).upper()
    witness = dict(context, batch="R5_M26", scenario="A", proxy_requested=False,
                   run_id=run_id, source_sha256=target.allocation.RESIDENT_SHA,
                   build_sha256=target.DYLIB_SHA, capture_generation=1,
                   playback_generation=2, configuration_id=2, closed=True)
    return dict(result=verdict, run_id=run_id, technical_ok=True, resources_released=True,
                channel_allocation=witness, native_pcm=dict(channel_allocation=copy.deepcopy(witness)))


class BatchTests(unittest.TestCase):
    def test_three_independent_a_runs_use_original_single_round_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            plan, root = plan_for(Path(directory)); calls = []
            def execute(child, context, output):
                calls.append((child, context, output))
                self.assertFalse(child["ready"])
                self.assertEqual(child["task"], "R5_M26")
                self.assertEqual(context, target.context(plan["batch_id"], len(calls)))
                self.assertEqual(context["arm"], "TRIPLE_EQUAL")
                self.assertEqual((context["round"], context["limit"]), (1, 2))
                self.assertEqual(child["files"], plan["files"])
                return result_for(context)
            results = target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
            self.assertEqual(len(results), 3)
            self.assertEqual(len({x[1]["batch_id"] for x in calls}), 3)
            self.assertEqual(len({x["run_id"] for x in results}), 3)
            self.assertEqual([x[2].name for x in calls], ["round-1", "round-2", "round-3"])
            self.assertFalse((root/"round-4").exists())
            complete = json.loads((root/"BATCH_COMPLETE.json").read_text())
            self.assertEqual(complete["stability_screen"], "3_OF_3_NOT_DETECTED")
            self.assertEqual(complete["aec_acceptance"], "UNVERIFIED")
            with self.assertRaises(FileExistsError):
                target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
            self.assertEqual(len(calls), 3)

    def test_contract_failures_precede_authorization_consumption(self):
        for fault in ("arm_b", "limit4", "order", "parameters", "dylib", "resident", "launcher", "controller", "child", "root"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                plan, root = plan_for(Path(directory))
                if fault == "arm_b": plan["arms"][1] = "FIRST_CHANNEL_ONLY"
                elif fault == "limit4": plan["limit"] = 4
                elif fault == "order": plan["rounds"].reverse()
                elif fault == "parameters": plan["parameters"] = dict(target.PARAMETERS, retries=1)
                elif fault in ("dylib", "resident", "launcher"): plan["files"][fault]["sha256"] = "0"*64
                elif fault == "controller": plan["files"]["m27"]["path"] = "/UNREGISTERED.py"
                elif fault == "child": plan["rounds"][0]["arm"] = "FIRST_CHANNEL_ONLY"
                else: plan["evidence_root"] = str(root/"foreign")
                execute = Mock()
                with self.assertRaises(ValueError):
                    target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
                execute.assert_not_called()
                self.assertFalse((root/"M27_AUTHORIZATION_CONSUMED.json").exists())

    def test_default_disabled_fresh_consent_ready_and_original_contracts(self):
        with tempfile.TemporaryDirectory() as directory:
            plan, root = plan_for(Path(directory)); execute = Mock()
            for consent in (None, target.allocation.CONSENT, "old consent"):
                with self.assertRaises(PermissionError):
                    target.run_batch(plan, consent, root, execute=execute, check=lambda _: None)
            with self.assertRaises(PermissionError):
                target.run_batch(plan, target.CONSENT, root, check=lambda _: None)
            plan["ready"] = False
            with self.assertRaises(PermissionError):
                target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
            plan["ready"] = True
            view = target.child_plan(plan, 1)
            with self.assertRaises(PermissionError):
                target.allocation.run_batch(view, target.allocation.CONSENT, root, execute=execute, check=lambda _: None)
            for number in (0, 4, True):
                with self.assertRaises(ValueError): target.context(plan["batch_id"], number)
            execute.assert_not_called()
            self.assertTrue(target.DEVICE_DISABLED)
            self.assertEqual(target.allocation.ARMS, ("TRIPLE_EQUAL", "FIRST_CHANNEL_ONLY"))

    def test_real_shared_precheck_is_retained_and_failure_does_not_consume(self):
        with tempfile.TemporaryDirectory() as directory:
            plan, root = plan_for(Path(directory))
            with patch.object(target.allocation.batch, "check_plan") as shared:
                target.check_plan(plan)
                shared.assert_called_once_with(target.child_plan(plan, 1))
            for fault in ("source/SHA", "device/volume", "conflicting PID"):
                execute = Mock()
                with patch.object(target.allocation, "check_plan", side_effect=ValueError(fault)):
                    with self.assertRaises(ValueError):
                        target.run_batch(plan, target.CONSENT, root, execute=execute, check=target.check_plan)
                execute.assert_not_called()
                self.assertFalse((root/"M27_AUTHORIZATION_CONSUMED.json").exists())

    def test_stop_cleanup_identity_failure_and_authorization_reuse(self):
        for fault in ("stop", "technical", "release", "exception", "duplicate", "run", "arm", "generation", "sha", "child"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                plan, root = plan_for(Path(directory)); calls = []; fixed = str(uuid.uuid4()).upper()
                def execute(p, c, r):
                    calls.append(c)
                    if fault == "exception": raise EOFError("synthetic child failure; original executor owns cleanup")
                    value = result_for(c, run_id=fixed if fault == "duplicate" else None)
                    if fault == "stop": (root/"STOP").touch()
                    elif fault in ("technical", "release"): value["technical_ok" if fault == "technical" else "resources_released"] = False
                    elif fault in ("run", "arm", "generation", "sha", "child"):
                        field, bad = {"run": ("run_id", str(uuid.uuid4()).upper()), "arm": ("arm", "FIRST_CHANNEL_ONLY"),
                                      "generation": ("capture_generation", 0), "sha": ("build_sha256", "0"*64),
                                      "child": ("batch_id", str(uuid.uuid4()).upper())}[fault]
                        value["channel_allocation"][field] = bad
                    return value
                with self.assertRaises((InterruptedError, RuntimeError, ValueError, EOFError)):
                    target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
                self.assertEqual(len(calls), 2 if fault == "duplicate" else 1)
                self.assertTrue((root/"BATCH_STOPPED.json").exists())
                self.assertFalse((root/"BATCH_COMPLETE.json").exists())
                with self.assertRaises(FileExistsError):
                    target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
                self.assertEqual(len(calls), 2 if fault == "duplicate" else 1)

    def test_acoustic_failure_and_inconclusive_are_kept_without_retries(self):
        with tempfile.TemporaryDirectory() as directory:
            plan, root = plan_for(Path(directory)); calls = []
            def execute(p, c, r):
                calls.append(c)
                return result_for(c, verdict=("ECHO_DETECTED", "INCONCLUSIVE", "ECHO_NOT_DETECTED")[len(calls)-1])
            results = target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
            self.assertEqual(len(results), 3)
            complete = json.loads((root/"BATCH_COMPLETE.json").read_text())
            self.assertEqual(complete["aec_residual_variability"], "REPRODUCED")
            self.assertEqual(complete["stability_screen"], "NOT_ESTABLISHED")
            self.assertEqual(complete["classification_counts"], dict(ECHO_DETECTED=1, ECHO_NOT_DETECTED=1, INCONCLUSIVE=1))
            self.assertEqual(complete["physical_emission"], "UNVERIFIED")
            for item in root.rglob("*.json"):
                self.assertEqual(item.stat().st_mode & 0o777, 0o600)

    def test_three_fake_children_use_original_pipes_and_reaping(self):
        integration = target.allocation.integration
        class IndependentProcesses(legacy.AllocationProcesses):
            def __init__(self, context):
                super().__init__(context)
                self.run_id = str(uuid.uuid4()).upper()
            def emit(self, fd, event):
                if event.get("run_id") == self.schedule["run_id"]:
                    event = dict(event, run_id=self.run_id)
                super().emit(fd, event)
        with tempfile.TemporaryDirectory() as directory:
            plan, root = plan_for(Path(directory)); children = []
            def execute(p, c, r):
                fake = IndependentProcesses(c); fake.child.pid = 2700+len(children)
                children.append(fake.child)
                try:
                    with patch.object(integration, "M26_HOST_DYLIB_SHA", legacy.sha(legacy.HOST.with_name("Aftelle.debug.dylib"))):
                        value = integration._connected_run(legacy.BUNDLE, "HOST", legacy.HOST, r/"control",
                            spawn=fake, clock=fake.clock, allocation=c)
                    self.assertEqual(len(fake.calls), 1)
                    self.assertIsNotNone(fake.child.poll())
                    self.assertTrue(any(":TRIPLE_EQUAL:" in x for x in fake.calls[0][0]))
                    return result_for(c, run_id=value["run_id"].upper())
                finally:
                    fake.close()
            target.run_batch(plan, target.CONSENT, root, execute=execute, check=lambda _: None)
            self.assertEqual(len({id(x) for x in children}), 3)
            self.assertEqual(len({x.pid for x in children}), 3)

    def test_cli_retains_private_plan_and_original_allocation_executor(self):
        import sys
        with tempfile.TemporaryDirectory() as directory:
            plan, root = plan_for(Path(directory)); path = root/"plan.ready.json"
            target.batch.save(path, plan)
            with patch.object(sys, "argv", ["m27_stability.py", "--plan", str(path), "--authorization", target.CONSENT]), \
                    patch.object(target, "run_batch") as run, patch.object(target.batch, "device_round") as execute:
                target.main()
                run.assert_called_once()
                self.assertIs(run.call_args.kwargs["check"], target.check_plan)
                child = target.child_plan(plan, 1); ctx = target.context(plan["batch_id"], 1)
                run.call_args.kwargs["execute"](child, ctx, root/"round-1")
                execute.assert_called_once_with(child, ctx, root/"round-1", allocation=True)


class SharedEvidenceTests(unittest.TestCase):
    def test_existing_strict_native_witness_clock_generation_and_pcm_gates(self):
        fixture, wav = legacy.EvidenceTests().fixture(target.ARM)
        ctx = legacy.context(target.ARM)
        self.assertTrue(target.allocation.audit_manifest(fixture, ctx, wav)["trustworthy"])
        paths = (("host_timing", "skippedUpdates"), ("host_timing", "invalidBuffers"),
                 ("host_timing", "staleCallbacks"), ("host_timing", "input", "sampleDiscontinuities"),
                 ("host_timing", "input", "hostDiscontinuities"), ("host_timing", "playerRender", "hostDiscontinuities"),
                 ("capture_drop_count",), ("capture_queued_at_seal",), ("channel_allocation_witness", "capture_generation"),
                 ("channel_allocation_witness", "configuration_id"))
        for path in paths:
            with self.subTest(path=path):
                value = copy.deepcopy(fixture); cursor = value
                for key in path[:-1]: cursor = cursor[key]
                cursor[path[-1]] += 1
                with self.assertRaises(ValueError): target.allocation.audit_manifest(value, ctx, wav)
        value = copy.deepcopy(fixture)
        first = next(iter(value["native"]["rejections"]))
        value["native"]["rejections"][first] = 1
        with self.assertRaises(ValueError): target.allocation.audit_manifest(value, ctx, wav)


if __name__ == "__main__":
    unittest.main(verbosity=2)
