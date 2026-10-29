"""Bounded M22 adaptation protocol. Imports existing controls; never runs devices on import."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import uuid

import numpy as np

import integration
import m20_batch as batch
from m20_echo import RATE, RESIDENT_SHA, best_match, levels, envelope_correlation

CONSENT = "授权开始M22单批3轮适应对照"
ARMS = integration.ADAPTATION_ARMS
RESIDENT_PCM_SHA = '7fd9318b95233f4f188b3d186aaf3befc8b7fd64b21f24b7674e1004e12d3960'
DEVICE_DISABLED = True
PARAMETERS = dict(version="M22_metrics_v1", requests_seconds=[3, 9], score_seconds=15, warmup_seconds=4,
                  request_late_limit_seconds=0.25, template_seconds=[1.0, 4.75], search_seconds=[-0.10, 0.65],
                  early_seconds=0.5, late_seconds=0.5, frame_seconds=[0.02, 0.10], retries=0)


def plays_for(arm):
    if arm not in ARMS:
        raise ValueError("unregistered M22 arm")
    return [(9, False)] if arm == "delayOnly" else [(3, arm == "silentPrime"), (9, False)]


def audit_manifest(manifest, context, wav_identity, *, expected_pid=None):
    integration.adaptation_context(context)
    expected = dict(batch="R5_M22", scenario="A", proxy_requested=False, **context)
    plays = manifest.get("adaptation_plays", [])
    planned = plays_for(context["arm"])
    if (manifest.get("adaptation_experiment") != expected or manifest.get("mac_aec_batch") is not None
            or manifest.get("scenario") != "A" or manifest.get("playback_sha256") != RESIDENT_SHA
            or manifest.get("processed_sha256") != wav_identity["pcm_sha256"]
            or manifest.get("retained_pcm_bytes") != wav_identity["frames"]*2
            or any(manifest.get(k) is not None for k in ("error", "capture_error", "playback_error"))
            or manifest.get("playback_started_count") != len(planned)
            or manifest.get("playback_state") != "completed" or len(plays) != len(planned)):
        raise ValueError("M22 run/playback/recording identity failed")
    result = batch.audit_capture_manifest(manifest, wav_identity, expected_pid=expected_pid,
                                         final_drain_key="adaptation_final_drain")
    timing = manifest["host_timing"]
    if not result["trustworthy"] or any(mode is None or type(mode.get("active")) is not int or mode["active"] != 0
            or mode.get("status") != "CONFIRMED_PUBLIC_API" for mode in result["mic_modes"]):
        raise ValueError("M22 requires trustworthy M19 coverage and active Standard Mic Mode")
    events = {x["event"]: x["count"] for x in timing["events"]}
    if (any(events.get(k) != 1 for k in ("engineStartBefore", "engineStartReturned", "playerPlayBefore", "playerPlayReturned"))
            or any(events.get(k) != len(planned) for k in ("playbackStarted", "playbackCompleted"))):
        raise ValueError("one Engine/Player start and exact playback events are required")
    witness = timing.get("adaptation", {})
    witnesses = [witness.get("first"), witness.get("second")]
    if len(planned) == 1 and witnesses[1] is not None:
        raise ValueError("unexpected second playback witness")
    witnesses = witnesses[:len(planned)]
    if any(x is None for x in witnesses):
        raise ValueError("missing per-play Render witness")
    origin = manifest["packets_sequence_host_time_ns_bytes"][0][1]
    score = manifest["warmup"]["score_start_content_boundary_ns"]
    previous_end, previous_generation = 0, 0
    for index, (play, seen, (offset, silent)) in enumerate(zip(plays, witnesses, planned), 1):
        if (play.get("index") != index or seen.get("index") != index
                or play.get("silent") is not silent or seen.get("silent") is not silent
                or seen.get("playerWasPlaying") is not (index > 1)
                or play.get("source_pcm_bytes") != 228064
                or play.get("planned_ns") != score+offset*1_000_000_000):
            raise ValueError("playback index, material or plan differs")
        times = [seen.get(k) for k in ("preparedAtNs", "startedAtNs", "completedAtNs")]
        request, complete = play.get("request_ns"), play.get("completed_ns")
        if (any(type(x) is not int for x in [*times, request, complete])
                or not 0 <= request-play["planned_ns"] < 250_000_000
                or not previous_end <= times[0] <= request <= times[1] <= times[2] <= complete
                or complete >= score+14_500_000_000
                or play.get("playback_generation") != seen.get("generation")
                or not previous_generation < seen["generation"]):
            raise ValueError("invalid/late/overlapping playback or generation")
        previous_end, previous_generation = complete, seen["generation"]
        if silent:
            if (play["source_pcm_sha256"] != hashlib.sha256(bytes(228064)).hexdigest()
                    or seen["scheduledNonzeroFrames"] != 0 or seen["render"]["nonzeroFrames"] != 0):
                raise ValueError("registered silence primer was not zero")
        elif play["source_pcm_sha256"] != RESIDENT_PCM_SHA:
            raise ValueError("voiced content changed")
        if not 75900 <= seen["scheduledFrames"] <= 76100:
            raise ValueError("incomplete scheduled output")
    for key in ("scheduledFrames", "scheduledNonzeroFrames"):
        if sum(x[key] for x in witnesses) != timing[key]:
            raise ValueError("unattributed output buffers")
    if sum(x["render"]["nonzeroFrames"] for x in witnesses) != timing["playerRender"]["nonzeroFrames"]:
        raise ValueError("unattributed nonzero Render")
    result.update(plays=witnesses, playback_records=plays, origin_ns=origin, arm=context["arm"])
    return result


def analyse_plays(samples, resident, metadata):
    """Measurements only: M20's single-play classifier is inapplicable to two-play recordings."""
    result = dict(result="INCONCLUSIVE", reason="CONTROLLED_COMPARISON_REQUIRES_REVIEW", parameters=PARAMETERS,
                  aec_acceptance="UNVERIFIED", physical_emission="UNVERIFIED", plays=[])
    if (not metadata.get("trustworthy") or not 14 <= len(samples)/RATE <= 15
            or len(resident) != 114032 or not np.isfinite(samples).all() or not np.isfinite(resident).all()):
        raise ValueError("insufficient M22 sample coverage")
    template = resident[RATE:round(4.75*RATE)]
    if not np.any(template):
        raise ValueError("silent resident cannot test voiced adaptation")
    for play, record in zip(metadata["plays"], metadata["playback_records"]):
        row = dict(index=play["index"], silent=play["silent"], physical_emission="UNVERIFIED")
        if play["silent"]:
            result["plays"].append(row)
            continue
        render = play["render"]
        start, end = render.get("firstNonzeroContentNs"), render.get("lastNonzeroContentNs")
        if start is None or end is None:
            raise ValueError("nonzero Render onset missing; cannot interpret absence as AEC")
        start, end = (start-metadata["origin_ns"])/1e9, (end-metadata["origin_ns"])/1e9
        if not 3.5 <= end-start <= 4.0 or start < 0.1 or start+0.65+len(template)/RATE > len(samples)/RATE:
            raise ValueError("incomplete per-play template search coverage")
        match = best_match(samples, template, start-0.1, start+0.65)
        reverse = best_match(samples, template[::-1], start-0.1, start+0.65)
        wrong_time = best_match(samples, template, 0, 0.1)
        if any(x is None for x in (match, reverse, wrong_time)):
            raise ValueError("template/control unavailable")
        pos = round(match["start_seconds"]*RATE)
        aligned = samples[pos:pos+len(template)]
        row.update(render_start=start, render_end=end, match=match, reverse_control=reverse,
                   time_control=wrong_time, composite_delay_seconds=match["start_seconds"]-start,
                   delay_status="CANDIDATE_ONLY_NOT_HARDWARE_DELAY", residual=levels(aligned),
                   early=levels(aligned[:RATE//2]), late=levels(aligned[-RATE//2:]),
                   envelope_correlation=envelope_correlation(aligned, template))
        row["energy_windows"] = {str(ms): [dict(start_seconds=(pos+n)/RATE, **levels(aligned[n:n+ms*24]))
            for n in range(0, len(aligned)-ms*24+1, ms*24)] for ms in (20, 100)}
        result["plays"].append(row)
    return result


def check_plan(plan):
    if (plan.get("task") != "R5_M22" or plan.get("arms") != list(ARMS)
            or plan.get("parameters") != PARAMETERS or plan.get("limit") != 3):
        raise ValueError("M22 frozen contract mismatch")
    for key, name in (("m22", "m22_adaptation.py"), ("integration", "integration.py"),
                      ("batch", "m20_batch.py"), ("scorer", "m20_echo.py")):
        if Path(plan["files"][key]["path"]) != Path(__file__).resolve().with_name(name):
            raise ValueError("unregistered control source")
    batch.check_plan(plan)


def run_batch(plan, authorization, root, *, execute=batch.disabled_round, check=None):
    if (authorization != CONSENT or plan.get("task") != "R5_M22" or plan.get("ready") is not True
            or plan.get("arms") != list(ARMS) or plan.get("limit") != 3
            or execute is batch.disabled_round or not callable(check)):
        raise PermissionError("fresh M22 authorization and complete prepared contract required")
    root = batch.private_directory(root)
    if root.resolve() != Path(plan["evidence_root"]).resolve():
        raise PermissionError("M22 directory binding mismatch")
    batch_id = str(uuid.UUID(plan["batch_id"])).upper()
    check(plan)
    batch.save(root/"M22_AUTHORIZATION_CONSUMED.json", dict(batch_id=batch_id, consent=authorization,
        plan_sha256=hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()))
    results = []
    try:
        for number, arm in enumerate(ARMS, 1):
            if (root/"STOP").exists():
                raise InterruptedError("M22 batch Stop")
            check(plan)
            directory = root/f"round-{number}"
            directory.mkdir(mode=0o700)
            batch.save(directory/"ATTEMPT_RESERVED.json", dict(arm=arm, retries=0))
            context = dict(batch_id=batch_id, round=number, limit=3, arm=arm)
            print(json.dumps(dict(event="M22_ROUND", **context)), flush=True)
            result = execute(plan, context, directory)
            if result.get("technical_ok") is not True or result.get("resources_released") is not True:
                raise RuntimeError("M22 technical or cleanup failure")
            run = str(uuid.UUID(result["run_id"])).upper()
            if any(x["run_id"] == run for x in results):
                raise ValueError("M22 RunID reuse")
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--authorization", required=True)
    args = parser.parse_args()
    if args.authorization != CONSENT:
        raise PermissionError("M22 device execution is not authorized")
    os.umask(0o077)
    plan = json.loads(args.plan.read_text())
    previous = signal.getsignal(signal.SIGTERM)
    def cancel(*_):
        raise InterruptedError("M22 operator cancellation")
    signal.signal(signal.SIGTERM, cancel)
    try:
        run_batch(plan, args.authorization, Path(plan["evidence_root"]), check=check_plan,
                  execute=lambda p, c, r: batch.device_round(p, c, r, adaptation=True))
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == "__main__":
    main()
