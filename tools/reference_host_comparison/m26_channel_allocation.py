"""Independent M26 allocation contract; existing Engine/UI/scorer only. No launch on import."""
import hashlib
import json
from pathlib import Path
import uuid

import numpy as np

import integration
import m20_batch as batch
from m20_echo import RATE, RESIDENT_SHA

ARMS = integration.ALLOCATION_ARMS
CONSENT = "授权开始M26单批2臂输出声道对照"
DEVICE_DISABLED = True
PARAMETERS = dict(version="M26_v1", arms=list(ARMS), warmup_seconds=4, score_seconds=15,
                  resident_request_seconds=3, total_capture_seconds=38, playback_count=2,
                  per_run_pcm_limit=720000, retries=0, change="post_converter_channel_allocation_only")


def check_plan(plan):
    if (plan.get("task") != "R5_M26" or plan.get("arms") != list(ARMS)
            or plan.get("parameters") != PARAMETERS or plan.get("limit") != 2
            or plan["files"]["dylib"]["sha256"] != integration.M26_HOST_DYLIB_SHA
            or plan["files"]["resident"]["sha256"] != RESIDENT_SHA):
        raise ValueError("M26 frozen identity/order/parameters mismatch")
    if (not isinstance(plan.get("resident"), str)
            or plan["resident"] != plan["files"]["resident"]["path"]):
        raise ValueError("M26 resident path must match the registered fixture")
    for key, name in (("m26", "m26_channel_allocation.py"), ("integration", "integration.py"),
                      ("batch", "m20_batch.py"), ("scorer", "m20_echo.py")):
        if Path(plan["files"][key]["path"]) != Path(__file__).resolve().with_name(name):
            raise ValueError("unregistered M26 control source")
    batch.check_plan(plan)


def audit_manifest(manifest, context, wav_identity, *, expected_pid=None):
    integration.allocation_context(context)
    expected = dict(batch="R5_M26", scenario="A", proxy_requested=False, **context,
                    source_sha256=RESIDENT_SHA, build_sha256=integration.M26_HOST_DYLIB_SHA)
    witness = manifest.get("channel_allocation_witness", {})
    identity = dict(expected, run_id=manifest.get("run_id"), capture_generation=manifest.get("capture_generation"),
                    playback_generation=manifest.get("host_timing", {}).get("playbackGeneration"),
                    configuration_id=manifest.get("native", {}).get("configuration_id"))
    if (manifest.get("channel_allocation_experiment") != expected
            or any(manifest.get(k) is not None for k in ("mac_aec_batch", "adaptation_experiment", "error", "capture_error", "playback_error"))
            or manifest.get("scenario") != "A" or manifest.get("playback_sha256") != RESIDENT_SHA
            or manifest.get("processed_sha256") != wav_identity["pcm_sha256"]
            or manifest.get("retained_pcm_bytes") != wav_identity["frames"]*2
            or not 14 <= wav_identity["frames"]/RATE <= 15
            or manifest.get("playback_started_count") != 1 or manifest.get("playback_state") != "completed"
            or not isinstance(witness, dict) or any(witness.get(k) != v for k, v in identity.items())
            or witness.get("closed") is not True or witness.get("buffers") != 48
            or type(witness.get("frames")) is not int or not 75900 <= witness["frames"] <= 76032
            or witness.get("format") != "16000Hz/3ch/Float32/planar/DiscreteInOrder"
            or any(type(identity[k]) is not int or identity[k] <= 0
                   for k in ("capture_generation", "playback_generation", "configuration_id"))):
        raise ValueError("M26 identity, allocation or export evidence failed")
    final_generation = manifest.get("playback_generation")
    if type(final_generation) is not int or final_generation < identity["playback_generation"]:
        raise ValueError("sealed output generation cannot predate active playback binding")
    result = batch.audit_capture_manifest(manifest, wav_identity, expected_pid=expected_pid,
                                         final_drain_key="channel_allocation_final_drain")
    if (not result["trustworthy"] or any(mode is None or mode.get("status") != "CONFIRMED_PUBLIC_API"
            or type(mode.get("active")) is not int or mode["active"] != 0 for mode in result["mic_modes"])):
        raise ValueError("M26 requires complete windows and active Standard Mic Mode")
    result["channel_allocation"] = witness
    return result


def transient_share(samples, start, end):
    if not (0 <= start < end <= len(samples)/RATE):
        return None
    window = samples[round(start*RATE):round(end*RATE)]
    n = len(window)//480
    if n < 3 or not np.isfinite(window).all():
        return None
    energy = np.sum(window[:n*480].reshape(n, 480)**2, axis=1)
    total = np.sum(energy)
    return float(np.max(np.convolve(energy, np.ones(3), "valid"))/total) if total > 0 else None


def run_batch(plan, authorization, root, *, execute=batch.disabled_round, check=None):
    if (authorization != CONSENT or plan.get("ready") is not True or plan.get("task") != "R5_M26"
            or plan.get("arms") != list(ARMS) or plan.get("parameters") != PARAMETERS or plan.get("limit") != 2
            or execute is batch.disabled_round or not callable(check)):
        raise PermissionError("fresh M26 authorization and complete frozen plan required")
    root = batch.private_directory(root)
    batch_id = str(uuid.UUID(plan["batch_id"])).upper()
    if root.resolve() != Path(plan["evidence_root"]).resolve() or batch_id != plan["batch_id"]:
        raise PermissionError("M26 UUID/directory binding mismatch")
    check(plan)
    batch.save(root/"M26_AUTHORIZATION_CONSUMED.json", dict(batch_id=batch_id, consent=authorization,
        plan_sha256=hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()))
    results = []
    try:
        for number, arm in enumerate(ARMS, 1):
            if (root/"STOP").exists():
                raise InterruptedError("M26 operator Stop")
            check(plan)
            directory = root/f"arm-{number}"
            directory.mkdir(mode=0o700)
            context = dict(batch_id=batch_id, round=number, limit=2, arm=arm)
            batch.save(directory/"ATTEMPT_RESERVED.json", dict(context, retries=0))
            print(json.dumps(dict(event="M26_ARM", **context)), flush=True)
            result = execute(plan, context, directory)
            if (result.get("technical_ok") is not True or result.get("resources_released") is not True
                    or result.get("result") not in ("ECHO_DETECTED", "ECHO_NOT_DETECTED", "INCONCLUSIVE")):
                raise RuntimeError("M26 safety, evidence or cleanup failure")
            run = str(uuid.UUID(result["run_id"])).upper()
            if any(x["run_id"] == run for x in results):
                raise ValueError("M26 RunID reuse")
            result["run_id"] = run
            batch.save(directory/"analysis.json", result)
            results.append(result)
        batch.save(root/"BATCH_COMPLETE.json", dict(results=results, aec_acceptance="UNVERIFIED"))
        return results
    except BaseException as error:
        batch.save(root/"BATCH_STOPPED.json", dict(completed=len(results), error_type=type(error).__name__,
                                                  error=str(error), retries=0))
        raise


def main():
    import argparse
    import os
    import signal
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--authorization", required=True)
    args = parser.parse_args()
    if args.authorization != CONSENT:
        raise PermissionError("M26 device execution is not authorized")
    os.umask(0o077)
    plan = json.loads(args.plan.read_text())
    previous = signal.getsignal(signal.SIGTERM)
    def cancel(*_):
        raise InterruptedError("M26 operator cancellation")
    signal.signal(signal.SIGTERM, cancel)
    try:
        run_batch(plan, args.authorization, Path(plan["evidence_root"]), check=check_plan,
                  execute=lambda p, c, r: batch.device_round(p, c, r, allocation=True))
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == "__main__":
    main()
