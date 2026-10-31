"""M27 parent contract; each round delegates one unchanged M26-A single run."""
import copy
import hashlib
import json
from pathlib import Path
import uuid

import m26_channel_allocation as allocation

batch = allocation.batch
ARM = "TRIPLE_EQUAL"
CONSENT = "授权开始M27单批3轮原始AEC稳定性测试"
DEVICE_DISABLED = True
DYLIB_SHA = "cac8ebb261362d6d5c443fbd5c4d5ddf179b7744589df3e335bfe5ee06b904f7"
PARAMETERS = dict(version="M27_v0.1", arm=ARM, warmup_seconds=4, score_seconds=15,
                  resident_request_seconds=3, total_capture_seconds=57, playback_count=3,
                  per_run_pcm_limit=720000, retries=0, scorer="M20_v0.1")


def context(batch_id, number):
    if type(number) is not int or not 1 <= number <= 3:
        raise ValueError("M27 round must be 1..3")
    parent = uuid.UUID(batch_id)
    if str(parent).upper() != batch_id:
        raise ValueError("M27 requires a canonical batch UUID")
    return dict(batch_id=str(uuid.uuid5(parent, f"M27/TRIPLE_EQUAL/{number}")).upper(),
                round=1, limit=2, arm=ARM)


def child_plan(plan, number):
    """An unready M26 view is not authorization to execute the original A/B batch."""
    return dict(copy.deepcopy(plan), task="R5_M26", batch_id=context(plan["batch_id"], number)["batch_id"],
                ready=False, limit=2, arms=list(allocation.ARMS), parameters=allocation.PARAMETERS,
                evidence_root=str(Path(plan["evidence_root"])/f"round-{number}"))


def validate_contract(plan):
    if (plan.get("schema_version") != 1 or plan.get("task") != "R5_M27"
            or type(plan.get("limit")) is not int or plan["limit"] != 3
            or plan.get("arms") != [ARM]*3 or plan.get("parameters") != PARAMETERS
            or allocation.ARMS != (ARM, "FIRST_CHANNEL_ONLY")
            or allocation.integration.M26_HOST_DYLIB_SHA != DYLIB_SHA
            or plan["files"]["dylib"]["sha256"] != DYLIB_SHA
            or plan["files"]["launcher"]["sha256"] != allocation.integration.HOST_BINARY_SHA
            or plan["files"]["resident"]["sha256"] != allocation.RESIDENT_SHA
            or Path(plan["files"]["m27"]["path"]) != Path(__file__).resolve()):
        raise ValueError("M27 frozen identity, three-A order or parameters mismatch")
    if (plan.get("rounds") != [context(plan["batch_id"], n) for n in range(1, 4)]
            or Path(plan["evidence_root"]) != Path(plan["cache"])/f"m27-original-aec-{plan['batch_id']}"):
        raise ValueError("M27 parent/child UUID or directory binding mismatch")


def check_plan(plan):
    validate_contract(plan)
    allocation.check_plan(child_plan(plan, 1))


def qualify_result(result, child):
    if (result.get("technical_ok") is not True or result.get("resources_released") is not True
            or result.get("result") not in ("ECHO_DETECTED", "ECHO_NOT_DETECTED", "INCONCLUSIVE")):
        raise RuntimeError("M27 child evidence, safety or cleanup failure")
    run = str(uuid.UUID(result["run_id"])).upper()
    witness = result.get("channel_allocation", {})
    expected = dict(child, run_id=run, batch="R5_M26", scenario="A", proxy_requested=False,
                    source_sha256=allocation.RESIDENT_SHA, build_sha256=DYLIB_SHA, closed=True)
    if (result["run_id"] != run or any(witness.get(k) != v for k, v in expected.items())
            or result.get("native_pcm", {}).get("channel_allocation") != witness
            or any(type(witness.get(k)) is not int or witness[k] <= 0
                   for k in ("capture_generation", "playback_generation", "configuration_id"))):
        raise ValueError("M27 result does not belong to its frozen M26-A child")
    return run


def run_batch(plan, authorization, root, *, execute=batch.disabled_round, check=None):
    if (authorization != CONSENT or plan.get("ready") is not True
            or execute is batch.disabled_round or not callable(check)):
        raise PermissionError("fresh M27 authorization and a ready plan required")
    validate_contract(plan)
    root = batch.private_directory(root)
    if root.resolve() != Path(plan["evidence_root"]).resolve():
        raise PermissionError("M27 evidence directory mismatch")
    check(plan)
    batch.save(root/"M27_AUTHORIZATION_CONSUMED.json", dict(batch_id=plan["batch_id"], consent=authorization,
        plan_sha256=hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()))
    results, rounds = [], []
    try:
        for number in range(1, 4):
            if (root/"STOP").exists():
                raise InterruptedError("M27 operator Stop")
            check(plan)
            directory = root/f"round-{number}"
            directory.mkdir(mode=0o700)
            child = context(plan["batch_id"], number)
            binding = dict(batch_id=plan["batch_id"], round=number, limit=3, arm=ARM, m26_child=child)
            batch.save(directory/"ATTEMPT_RESERVED.json", dict(binding, retries=0))
            view = child_plan(plan, number)
            batch.save(directory/"M26_SINGLE_ROUND_VIEW.json", view)
            print(json.dumps(dict(event="M27_ROUND", **binding)), flush=True)
            result = execute(view, child, directory)
            run = qualify_result(result, child)
            if any(x["run_id"] == run for x in results):
                raise ValueError("M27 RunID reuse")
            record = dict(m27=binding, child_result=result)
            batch.save(directory/"analysis.json", record)
            rounds.append(record)
            results.append(result)
        verdicts = [x["result"] for x in results]
        screen = "3_OF_3_NOT_DETECTED" if verdicts == ["ECHO_NOT_DETECTED"]*3 else "NOT_ESTABLISHED"
        batch.save(root/"BATCH_COMPLETE.json", dict(rounds=rounds, stability_screen=screen,
            classification_counts={key: verdicts.count(key) for key in ("ECHO_DETECTED", "ECHO_NOT_DETECTED", "INCONCLUSIVE")},
            aec_residual_variability="REPRODUCED" if "ECHO_DETECTED" in verdicts else "NOT_ESTABLISHED",
            aec_acceptance="UNVERIFIED", physical_emission="UNVERIFIED"))
        return results
    except BaseException as error:
        batch.save(root/"BATCH_STOPPED.json", dict(completed=len(results), error_type=type(error).__name__,
                                                  error=str(error), retries=0))
        raise


def main():
    import argparse
    import os
    import signal
    import stat
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--authorization", required=True)
    args = parser.parse_args()
    if args.authorization != CONSENT:
        raise PermissionError("M27 device execution is not authorized")
    os.umask(0o077)
    batch.private_directory(args.plan.parent)
    info = args.plan.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 65536):
        raise PermissionError("M27 plan must be an owned regular 0600 bounded file")
    plan = json.loads(args.plan.read_text())
    previous = signal.getsignal(signal.SIGTERM)
    def cancel(*_):
        raise InterruptedError("M27 operator cancellation")
    signal.signal(signal.SIGTERM, cancel)
    try:
        run_batch(plan, args.authorization, args.plan.parent, check=check_plan,
                  execute=lambda p, c, r: batch.device_round(p, c, r, allocation=True))
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == "__main__":
    main()
