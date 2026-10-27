"""One explicitly consented Mac-only A batch; default entry never launches devices."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import uuid

import numpy as np

import integration
from m20_echo import RESIDENT_SHA, analyse, load_wav

CONSENT = "授权开始M20单批3轮AEC测试"
DEVICE_DISABLED = True


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def private_directory(path):
    path = Path(path)
    info = path.lstat()
    if path.is_symlink() or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise PermissionError("expected owned 0700 directory")
    return path


def save(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as file:
        json.dump(value, file, ensure_ascii=False, indent=2, allow_nan=False)


def disabled_round(*args):
    raise PermissionError("DEVICE_DISABLED: fresh M20 batch authorization required")


def run_batch(plan, authorization, root, *, execute=disabled_round, check=None):
    """The same finite loop is used with offline Fake or the explicit device adapter."""
    if execute is disabled_round:
        disabled_round()
    if authorization != CONSENT or plan.get("task") != "R5_M20" or plan.get("ready") is not True:
        raise PermissionError("fresh M20 authorization and prepared plan required")
    limit = plan.get("limit")
    if type(limit) is not int or not 1 <= limit <= 3 or not callable(check):
        raise ValueError("invalid batch bound or missing precheck")
    batch_id = str(uuid.UUID(plan["batch_id"])).upper()
    root = private_directory(root)
    if root.resolve() != Path(plan["evidence_root"]).resolve():
        raise PermissionError("authorization is bound to one evidence directory")
    save(root/"M20_AUTHORIZATION_CONSUMED.json", dict(batch_id=batch_id, consent=authorization,
         limit=limit, plan_sha256=hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()))
    results = []
    try:
        for number in range(1, limit+1):
            print(json.dumps(dict(event="M20_ROUND_PRECHECK", batch_id=batch_id, round=number, limit=limit)), flush=True)
            if (root/"STOP").exists():
                raise InterruptedError("M20 batch stopped")
            check(plan)
            round_root = root/f"round-{number}"
            round_root.mkdir(mode=0o700)
            save(round_root/"ATTEMPT_RESERVED.json", dict(round=number, retries=0))
            context = dict(batch_id=batch_id, round=number, limit=limit)
            result = execute(plan, context, round_root)
            if (result.get("technical_ok") is not True or result.get("resources_released") is not True
                    or result.get("result") not in ("ECHO_DETECTED", "ECHO_NOT_DETECTED", "INCONCLUSIVE")):
                raise RuntimeError("round failed safety, export or cleanup qualification")
            run_id = str(uuid.UUID(result["run_id"])).upper()
            if run_id in [item["run_id"] for item in results]:
                raise ValueError("RunID reused across rounds")
            result["run_id"] = run_id
            save(round_root/"analysis.json", result)
            results.append(result)
            print(json.dumps(dict(event="M20_ROUND_RELEASED", round=number, result=result["result"])), flush=True)
        save(root/"BATCH_COMPLETE.json", dict(batch_id=batch_id, rounds=len(results), results=results,
             aec_acceptance="UNVERIFIED", device_access="CONTROL_COMPLETED_NOT_ACOUSTIC_PASS"))
        return results
    except BaseException as error:
        save(root/"BATCH_STOPPED.json", dict(batch_id=batch_id, completed=len(results),
             error_type=type(error).__name__, error=str(error), retries=0))
        raise


def probe(plan):
    raw = subprocess.check_output([plan["device_probe"]], timeout=5)
    devices = json.loads(raw)
    volumes = subprocess.check_output(["osascript", "-e", "get volume settings"], text=True, timeout=5)
    microphone, speaker = devices["input"], devices["output"]
    if ("TinyUSB" not in microphone["name"] or microphone["transport"] != "usb "
            or microphone["input_channels"] <= 0 or microphone["output_channels"] != 0
            or "Mac mini" not in speaker["name"] or speaker["transport"] != "bltn"
            or speaker["output_channels"] <= 0):
        raise ValueError("target route is not TinyUSB and Mac mini built-in speaker")
    for direction in ("input", "output"):
        device, frozen = devices[direction], plan["devices"][direction]
        if (device["uid_sha256"] != frozen["uid_sha256"] or device["alive"] != 1
                or device["running"] != 0 or device["transport"] != frozen["transport"]):
            raise ValueError("device identity, route, availability or release changed")
    scalar = devices["output"]["output_volume_scalar"]
    if (type(scalar) not in (int, float) or not np.isfinite(scalar)
            or "input volume:60" not in volumes or "output volume:55" not in volumes
            or "output muted:false" not in volumes
            or devices["output"]["output_muted"] not in (False, 0)
            or abs(scalar-0.55) > 1e-6):
        raise ValueError("frozen volume/mute mismatch; never auto-adjust")
    return devices


def check_plan(plan):
    private_directory(plan["cache"])
    here = Path(__file__).resolve().parent
    scripts = {"prepare_ui": "prepare_host_original_ui.applescript", "start_ui": "start_host_original_ui.applescript",
               "stop_ui": "stop_host_original_ui.applescript", "finish_ui": "finish_host_original_ui.applescript"}
    if any(Path(plan["files"][key]["path"]) != here/name for key, name in scripts.items()):
        raise ValueError("unregistered original UI path")
    if plan["source_commit"] != subprocess.check_output(["git", "rev-parse", "HEAD"],
            cwd=here.parents[1], text=True).strip():
        raise ValueError("prepared source commit changed")
    for name, identity in plan["files"].items():
        path = Path(identity["path"])
        if path.is_symlink() or sha(path) != identity["sha256"]:
            raise ValueError("frozen file mismatch: "+name)
    executable = Path(plan["executable"])
    integration.command("HOST", executable, 3, mac_aec=dict(batch_id=plan["batch_id"], round=1, limit=plan["limit"]))
    probe(plan)
    # Reading the process list does not launch/activate any App.
    processes = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True)
    if any(line.rstrip().endswith(("/Aftelle", "/apple-vp-reference", "/bt_proxy_registered"))
           for line in processes.splitlines()):
        raise ValueError("conflicting audio experiment process")


def verify_loaded(pid, plan):
    executable = str(Path(plan["executable"]).resolve())
    actual = subprocess.check_output(["ps", "-p", str(pid), "-o", "comm="], text=True).strip()
    mappings = subprocess.check_output(["lsof", "-a", "-p", str(pid), "-d", "txt", "-Fn"], text=True)
    dylib = str(Path(executable).with_name("Aftelle.debug.dylib"))
    if actual != executable or "n"+dylib not in mappings.splitlines():
        raise ValueError("actual PID or loaded dylib mismatch")
    for name in ("launcher", "dylib"):
        item = plan["files"][name]
        if sha(item["path"]) != item["sha256"]:
            raise ValueError("loaded candidate identity changed")


def ui(script, *args):
    child = subprocess.Popen(["osascript", str(script), *map(str, args)],
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        output, error = child.communicate(timeout=20)
        if child.returncode != 0:
            raise RuntimeError("original UI failed: "+error)
        return output
    finally:
        if child.poll() is None:
            child.terminate()
            try: child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=1)


def audit_manifest(manifest, context, wav_identity, *, expected_pid=None):
    """Reject technical faults; incomplete measurement metadata cannot become absent echo."""
    if (manifest.get("mac_aec_batch") != dict(batch="R5_M20", scenario="A", proxy_requested=False, **context)
            or manifest.get("scenario") != "A" or manifest.get("playback_sha256") != RESIDENT_SHA
            or manifest.get("processed_sha256") != wav_identity["pcm_sha256"]
            or manifest.get("retained_pcm_bytes") != wav_identity["frames"]*2
            or manifest.get("error") is not None or manifest.get("capture_error") is not None
            or manifest.get("playback_error") is not None or manifest.get("playback_started_count") != 1
            or manifest.get("playback_state") != "completed"):
        raise ValueError("run/fixture/export identity or execution failure")
    if (manifest.get("data_mode") != "RECORDING" or manifest.get("requested_agc_enabled") is not True
            or manifest.get("byte_limit") != 720000 or manifest.get("silent_smoke") is not False
            or manifest.get("bt_acoustic_batch") is not None or manifest.get("human_acoustic_batch") is not None):
        raise ValueError("frozen experiment configuration changed")
    for key in ("capture_drop_count", "capture_stale_count", "capture_queued_at_seal",
                "playback_underrun_count", "playback_rejected_callback_count"):
        if manifest.get(key) != 0:
            raise ValueError("capture/playback counter failure: "+key)
    native, timing = manifest["native"], manifest["host_timing"]
    if (native.get("coverage_valid") is not True or native.get("issues") != []
            or any(native["rejections"].values()) or native.get("raw_timestamp_diagnostic") is not None
            or native["run_id"] != manifest["run_id"] or timing["runID"] != manifest["run_id"]
            or timing["captureGeneration"] != manifest["capture_generation"]
            or timing["configurationID"] != native["configuration_id"]):
        raise ValueError("Native clock, generation or configuration failure")
    events = timing["engineConfigurationEvents"]
    if (events.get("status") != "CONFIRMED" or events.get("count") != 0
            or events.get("skippedNotifications") != 0 or events.get("observationClosed") is not True):
        raise ValueError("Engine configuration event or listener failure")
    reads = timing["runtimeReadbacks"]
    if len(reads) != 2:
        raise ValueError("missing runtime readbacks")
    expected = dict(engineRunning=True, inputEnabled=True, outputEnabled=True,
                    agcEnabled=True, bypass=False, inputMuted=False)
    previous_process = None
    for index, read in enumerate(reads):
        payload = read["payload"]
        if (read["phase"] != ("engineStarted", "residentPlaybackStarted")[index]
                or read["runID"] != manifest["run_id"] or read["captureGeneration"] != native["generation"]
                or read["configurationID"] != native["configuration_id"] or payload.get("issues") != []
                or any(payload["voiceProcessing"].get(k) is not v for k, v in expected.items())
                or payload["processBinding"].get("status") != "CONFIRMED"):
            raise ValueError("runtime VP or binding evidence failure")
        process = payload["processBinding"]
        ids = [process.get(k) for k in ("requestedPID", "observedPID", "observedPIDAfter")]
        if None in ids or len(set(ids)) != 1 or ids[0] <= 0:
            raise ValueError("runtime process PID mismatch")
        if expected_pid is not None and ids[0] != expected_pid:
            raise ValueError("readback belongs to another PID")
        bindings = []
        for direction in ("input", "output"):
            values = process[direction]
            allowed = ("PROCESS_DEVICE_METADATA_MATCHES_DEFAULT", "PROCESS_AGGREGATE_DIRECTION_QUALIFIED")
            if direction == "input": allowed += ("PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED",)
            if (values["status"] != "CONFIRMED" or values["bindingStatus"] not in allowed
                    or not values["deviceIDs"] or len(set(values["deviceIDs"])) != len(values["deviceIDs"])):
                raise ValueError("runtime direction binding unavailable")
            bindings.append(set(values["deviceIDs"]))
        if previous_process is not None and previous_process != (ids, bindings):
            raise ValueError("process device direction changed")
        previous_process = ids, bindings
    if reads[0]["payload"]["formats"] != reads[1]["payload"]["formats"]:
        raise ValueError("runtime client formats changed")
    modes = [read["payload"].get("microphoneModes", {}).get("active") for read in reads]
    if all(value is not None for value in modes) and modes[0] != modes[1]:
        raise ValueError("active Microphone Mode changed")
    packets = manifest["packets_sequence_host_time_ns_bytes"]
    if len(packets)*480 != wav_identity["frames"] or not packets:
        raise ValueError("WAV packet identity missing")
    for previous, current in zip(packets, packets[1:]):
        if current != [previous[0]+1, previous[1]+20_000_000, 960]:
            raise ValueError("processed PCM discontinuity")
    rows = manifest["short_window_diagnostics"].get("windows", [])
    trusted = (len(rows) == len(packets) and all(row.get("status") == "MATCHED_CONTENT_COVERAGE" for row in rows)
               and timing.get("skippedUpdates") == 0)
    if packets[0][2] != 960 or manifest.get("total_collection_limit_ns") != 19_000_000_000:
        raise ValueError("capture budget or packet size mismatch")
    for stream in (timing["input"], timing["playerRender"]):
        if any(stream.get(key) != 0 for key in (
                "missingTime", "duplicate", "backwards", "sampleDiscontinuities", "hostDiscontinuities")):
            if stream is timing["input"]:
                raise ValueError("input content clock discontinuity")
            trusted = False
    render = timing["playerRender"]
    origin = packets[0][1]
    start, end = render.get("firstNonzeroContentNs"), render.get("lastNonzeroContentNs")
    if start is None or end is None:
        trusted = False
        start = end = origin
    return dict(trustworthy=trusted, render_start=(start-origin)/1e9, render_end=(end-origin)/1e9,
                short_windows=rows, mic_modes=[x["payload"].get("microphoneModes") for x in reads],
                tail_coverage=manifest["warmup"].get("tail_coverage"), raw_timestamp_diagnostic=None)


def device_round(plan, context, root):
    executable, cache = Path(plan["executable"]), Path(plan["cache"])
    pid_holder = []

    def prepare(pid):
        pid_holder.append(pid)
        verify_loaded(pid, plan)
        save(root/"prepare_ui.json", dict(receipt=ui(plan["files"]["prepare_ui"]["path"], pid, plan["resident"])))
        verify_loaded(pid, plan)
        if (root.parent/"STOP").exists():
            raise InterruptedError("M20 stopped before Capture")
        save(root/"start_ui.json", dict(receipt=ui(plan["files"]["start_ui"]["path"], pid)))

    def finish(pid):
        verify_loaded(pid, plan)
        receipt = ui(plan["files"]["finish_ui"]["path"], pid, cache)
        save(root/"finish_ui.json", dict(receipt=receipt))

    def stop_and_preserve(pid):
        verify_loaded(pid, plan)
        save(root/"stop_ui.json", dict(receipt=ui(plan["files"]["stop_ui"]["path"], pid)))
        finish(pid)

    integration._connected_run(plan["bundle"], "HOST", executable, root/"control",
        spawn=subprocess.Popen, clock=integration.now_ns, device=True, mac_aec=context,
        device_ui=prepare, finish_ui=finish, failure_ui=stop_and_preserve,
        cancel_requested=lambda: (root.parent/"STOP").exists())
    control = json.loads((root/"control/result.json").read_text())
    run_id = str(uuid.UUID(control["run_id"])).upper()
    for suffix in ("json", "wav"):
        file = cache/f"run-{run_id}.{suffix}"
        info = file.lstat()
        if file.is_symlink() or not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise PermissionError("export not owned regular 0600 file")
    json_file, wav_file = cache/f"run-{run_id}.json", cache/f"run-{run_id}.wav"
    if json_file.stat().st_size > 4_000_000:
        raise ValueError("unbounded manifest")
    manifest = json.loads(json_file.read_text())
    samples, identity = load_wav(wav_file)
    resident, _ = load_wav(plan["resident"], resident=True)
    metadata = audit_manifest(manifest, context, identity, expected_pid=pid_holder[0])
    if manifest["run_id"] != run_id:
        raise ValueError("export filename and control RunID mismatch")
    for channel in manifest["native"]["channels"]:
        if channel["non_finite"] != 0 or channel["full_scale"] > channel["samples"]*0.01:
            raise ValueError("nonfinite or sustained Native full scale; stop batch")
    for index, row in enumerate(metadata["short_windows"]):
        pcm = row["pcm"]
        window = samples[index*480:(index+1)*480]
        if pcm.get("status") != "COMPLETE":
            metadata["trustworthy"] = False
            continue
        if (row["start_ns"] != manifest["packets_sequence_host_time_ns_bytes"][index][1]
                or pcm["samples"] != 480 or not len(window)
                or abs(pcm["rms"]-float(np.sqrt(np.mean(window**2)))) > 1e-12
                or abs(pcm["peak"]-float(np.max(np.abs(window)))) > 1e-12):
            raise ValueError("M19 windows do not match saved WAV")
    if np.count_nonzero((samples == -1) | (samples == 32767/32768)) > len(samples)*0.01:
        raise ValueError("sustained PCM full scale; stop remaining batch")
    result = analyse(samples, resident, **{key: metadata[key] for key in ("trustworthy", "render_start", "render_end")})
    result.update(run_id=run_id, technical_ok=True, wav=identity, json_sha256=sha(json_file),
                  native_pcm=metadata, resources_released=False)
    if not pid_holder or subprocess.run(["kill", "-0", str(pid_holder[0])], capture_output=True).returncode == 0:
        raise RuntimeError("exact App PID did not exit")
    probe(plan)
    result["resources_released"] = True
    return result


def run_device(plan, authorization, root):
    if authorization != CONSENT:
        raise PermissionError("M20 current user consent required")
    os.umask(0o077)
    previous = signal.getsignal(signal.SIGTERM)
    def cancelled(*_):
        raise InterruptedError("M20 operator Stop")
    signal.signal(signal.SIGTERM, cancelled)
    try:
        return run_batch(plan, authorization, root, execute=device_round, check=check_plan)
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--authorize-batch", choices=[CONSENT])
    args = parser.parse_args()
    if args.authorize_batch is None:
        raise SystemExit("DEVICE_DISABLED: preparation is not device authorization")
    run_device(json.loads(args.plan.read_text()), args.authorize_batch, args.evidence)
