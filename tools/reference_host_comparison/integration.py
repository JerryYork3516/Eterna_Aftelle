"""Single-run REF/HOST connection, derived from the registered sync_once.py loop.

Device launch defaults to disabled. R4 requires separate explicit single-run consent.
The original SingleRun and R2 clock translator remain the timing authorities.
"""
import ctypes
import json
import os
from pathlib import Path
import select
import signal
import subprocess

from controller import original_single_run, ReferenceRun
from prepare_player import CONTROLLER_SHA, FIXTURES, require_identity, sha

DEVICE_DISABLED = True
REF_BINARY_SHA = "54d2eaf775eccdf806c82f8996a7038db4b219e4ddba60ea8914122997385ade"
REF_GUI_BINARY_SHA = "65fadd2acbb09dc9cf19e8f8a93013ad795ff93cef543a3e65420d5d59a9a52b"
HOST_BINARY_SHA = "ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118"
HOST_DYLIB_SHA = "34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1"
M03_HOST_DYLIB_SHA = "6f81387668c4625c88f80895778dad46e4a8a39badde25ad95527ae4492e2eef"
M07_HOST_DYLIB_SHA = "094ce973dc6f3589db56fedca067af4ddc1d0865534bc5150952a66c603f764c"
F1_HOST_DYLIB_SHA = "ecf6a86f4f05b3a594c978af45fc47d7af96c6761a9f7c1419ee494c96de8d5e"
M20_HOST_DYLIB_SHA = "4de26c8850e670dd6be73b03ce60b29c8404b2791d154276087d34295d32433e"
PLAYER_BINARY_SHA = "ff47b7a948fde6cc47c96ffdee30822563c89abc32e94419390942e213d037d8"
R4_CONSENT = "R4_REF_HOST_ONCE_LOCAL_RECORDING_AND_ANALYSIS"


def disabled_spawn(*args, **kwargs):
    raise PermissionError("DEVICE_DISABLED: no real process launch is authorized")


def require_reference_identity(executable):
    digest = sha(executable)
    if digest == REF_BINARY_SHA:
        return "R3_ADAPTED_REF"
    if digest == REF_GUI_BINARY_SHA:
        return "R4_GUI_ENTRY_ADAPTED_REF"
    raise ValueError("Frozen REF identity mismatch")


def now_ns():
    class Timebase(ctypes.Structure):
        _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]
    lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    lib.mach_absolute_time.restype = ctypes.c_uint64
    base = Timebase()
    if lib.mach_timebase_info(ctypes.byref(base)) != 0 or not base.denom:
        raise ValueError("timebase unavailable")
    return lib.mach_absolute_time() * base.numer // base.denom


def mac_aec_context(value):
    import uuid
    if (not isinstance(value, dict) or set(value) != {"batch_id", "round", "limit"}
            or type(value["round"]) is not int or type(value["limit"]) is not int
            or not 1 <= value["round"] <= value["limit"] <= 3
            or str(uuid.UUID(value["batch_id"])).upper() != value["batch_id"]):
        raise ValueError("invalid M20 batch identity or limit")
    return value


def command(mode, executable, descriptor, ref_arguments=(), *, m03_group=None, human_group=None, onset_group=None,
            mac_aec=None):
    executable = Path(executable).resolve()
    if mac_aec is not None:
        mac_aec_context(mac_aec)
        if mode != "HOST" or any(x is not None for x in (m03_group, human_group, onset_group)):
            raise ValueError("M20 is Mac-only resident A")
    if onset_group is not None and (onset_group not in ("A", "B") or human_group != "C"):
        raise ValueError("F1 requires a registered human C onset group")
    if human_group is not None and (mode != "HOST" or m03_group is not None or human_group not in ("A", "B", "C")):
        raise ValueError("unregistered or mixed human group")
    if mode == "HOST":
        if ref_arguments:
            raise ValueError("REF arguments cannot enter HOST")
        require_identity(executable, HOST_BINARY_SHA)
        if m03_group is not None and m03_group not in ("A", "B", "C"):
            raise ValueError("unregistered M03 group")
        require_identity(executable.with_name("Aftelle.debug.dylib"),
                         M20_HOST_DYLIB_SHA if mac_aec else F1_HOST_DYLIB_SHA if onset_group else M07_HOST_DYLIB_SHA if human_group
                         else M03_HOST_DYLIB_SHA if m03_group else HOST_DYLIB_SHA)
        args = [str(executable), "--apple-vp-acoustic-test", "--apple-vp-score-control-fd=" + str(descriptor)]
        if mac_aec:
            args.append("--apple-vp-mac-aec={batch_id}:{round}:{limit}".format(**mac_aec))
        if m03_group:
            args.append("--apple-vp-bt-abc=" + m03_group)
        if human_group:
            args.append("--apple-vp-human-onset=" + onset_group if onset_group
                        else "--apple-vp-human-abc=" + human_group)
        return args, {}
    if m03_group is not None:
        raise ValueError("M03 never starts REF")
    if mode != "REF":
        raise ValueError("Expected REF or HOST, never legacy --arm A/B")
    require_reference_identity(executable)
    required = ["vp-c", "--authorize-vp-c", "--material-content-reviewed", "--enable-audio", "--arm-diagnostics"]
    values = ["--mode", "--duration", "--target-registration", "--material", "--material-sha256",
              "--material-pcm-sha256", "--study-id", "--output-dir"]
    if list(ref_arguments[:len(required)]) != required:
        raise ValueError("Original REF consent flags are required")
    rest = list(ref_arguments[len(required):])
    if len(rest) != len(values) * 2 or rest[::2] != values or rest[1:4:2] != ["VP_ON", "16"]:
        raise ValueError("Original REF invocation contract mismatch")
    return [str(executable), *ref_arguments], {"AFTELLE_VPC_COMPARISON_FD": str(descriptor)}


class Plan:
    def __init__(self, mode, original):
        if not __debug__:
            raise RuntimeError("Python optimization would disable original safety assertions")
        self.mode = mode
        self.adapter = ReferenceRun(original) if mode == "REF" else original(4)
        self.state = self.adapter.plan if mode == "REF" else self.adapter
        self.cancelled = False

    def accept(self, event, now):
        if self.state.terminal:
            raise ValueError("duplicate terminal event")
        if self.mode == "HOST" and "source" in event:
            raise ValueError("REF event cannot enter HOST")
        if event.get("event") == "schedule" and self.mode == "HOST":
            for key in ("score_start_ns", "proxy_stop_ns"):
                if type(event[key]) is not int or not 0 < event[key] < 2**64:
                    raise ValueError("invalid HOST time")
        self.adapter.accept(event, now)
        self.cancelled = event.get("event") == "cancel"

    def actions(self, now):
        return self.adapter.actions(now)


def verify_bundle(bundle, mode):
    if mode not in ("REF", "HOST"):
        raise ValueError("unregistered mode")
    bundle = Path(bundle).resolve()
    receipt = json.loads((bundle / "build.json").read_text())
    for name in ("bt_proxy_registered", "bt_proxy_speech_once.m", "native_dual_sound.m", "proxy_registry.h"):
        require_identity(bundle / name, receipt["files"][name])
    require_identity(bundle / "original_sync_once.py", CONTROLLER_SHA)
    require_identity(bundle / "proxy_registry.h", sha(Path(__file__).with_name("proxy_registry.h")))
    fixture = bundle / "assets" / (mode + "_proxy.wav")
    if fixture.resolve() != fixture:
        raise ValueError("symlink fixture")
    require_identity(fixture, FIXTURES[fixture.name])
    return bundle, fixture


def run(bundle, mode, executable, evidence, ref_arguments=(), *, spawn=disabled_spawn, clock=now_ns):
    if spawn is disabled_spawn or not getattr(spawn, "device_disabled", False):
        disabled_spawn()
    return _connected_run(bundle, mode, executable, evidence, ref_arguments, spawn=spawn, clock=clock)


def run_device_once(bundle, mode, executable, evidence, ref_arguments=(), *, consent=None):
    if consent != R4_CONSENT:
        disabled_spawn()
    bundle, _ = verify_bundle(bundle, mode)
    require_identity(bundle / "bt_proxy_registered", PLAYER_BINARY_SHA)
    # Validate the target before reserving a run or starting even the waiting player.
    command(mode, executable, 3, ref_arguments)
    evidence = Path(evidence).absolute()
    if evidence.resolve() != evidence:
        raise ValueError("R4 evidence path must not traverse symlinks")
    parent = evidence.parent
    if parent.is_symlink() or parent.stat().st_uid != os.getuid() or parent.stat().st_mode & 0o777 != 0o700:
        raise ValueError("R4 evidence parent must be owned private directory")
    fd = os.open(parent / ("R4_" + mode + "_consumed.json"),
                 os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(dict(schema_version=1, mode=mode, consent=consent, status="ATTEMPT_RESERVED"), output)

    def cancelled(signum, frame):
        raise InterruptedError("R4 operator cancellation")

    previous = signal.signal(signal.SIGTERM, cancelled)
    try:
        return _connected_run(bundle, mode, executable, evidence, ref_arguments,
                              spawn=subprocess.Popen, clock=now_ns, device=True)
    finally:
        signal.signal(signal.SIGTERM, previous)


def _connected_run(bundle, mode, executable, evidence, ref_arguments=(), *, spawn, clock, device=False,
                   m03_group=None, human_group=None, onset_group=None, failure_ui=None,
                   mac_aec=None, device_ui=None, finish_ui=None, cancel_requested=None):
    if any(value is not None and not callable(value) for value in (device_ui, finish_ui, cancel_requested)):
        raise ValueError("invalid M20 control callback")
    if cancel_requested is not None and mac_aec is None:
        raise ValueError("batch cancellation requires M20")
    if any(x is not None for x in (device_ui, finish_ui)) and (not device or mac_aec is None):
        raise ValueError("M20 UI requires explicit device execution")
    if mac_aec is not None:
        mac_aec_context(mac_aec)
        if mode != "HOST" or any(x is not None for x in (m03_group, human_group, onset_group)):
            raise ValueError("M20 cannot mix source modes")
    if failure_ui is not None and (not device or mode != "HOST" or (m03_group != "A" and mac_aec is None)
                                   or human_group is not None or not callable(failure_ui)):
        raise ValueError("failure UI requires resident-only device execution")
    if onset_group is not None and (onset_group not in ("A", "B") or human_group != "C"):
        raise ValueError("F1 requires a registered human C onset group")
    if human_group is not None and (mode != "HOST" or m03_group is not None or human_group not in ("A", "B", "C")):
        raise ValueError("unregistered or mixed human group")
    if mac_aec is not None:
        bundle, fixture = Path(bundle).resolve(), None
        require_identity(bundle / "original_sync_once.py", CONTROLLER_SHA)
    else:
        bundle, fixture = verify_bundle(bundle, "REF" if m03_group or human_group else mode)
    use_proxy = mac_aec is None and human_group is None and m03_group != "A"
    plan = Plan(mode, original_single_run(bundle / "original_sync_once.py"))
    evidence = Path(evidence)
    evidence.mkdir(mode=0o700, parents=False, exist_ok=False)
    state = dict(schema_version=1, mode=mode, device_access="R4_EXPLICIT_ONCE" if device else "ZERO_FAKE_ONLY",
                 events=[], commands=[], status="RUNNING")
    if m03_group:
        state.update(batch="R5_M03", group=m03_group,
                     device_access="M03_EXPLICIT_ONCE" if device else "ZERO_FAKE_ONLY")
    if human_group:
        state.update(batch="R5_M07_F1" if onset_group else "R5_M07", group=onset_group or human_group,
                     source="human", proxy_requested=False,
                     device_access=("M07_F1_EXPLICIT_ONCE" if onset_group else "M07_EXPLICIT_ONCE")
                     if device else "ZERO_FAKE_ONLY")
    if mac_aec is not None:
        state.update(batch="R5_M20", **mac_aec, proxy_requested=False)
    if mode == "REF":
        state["reference_variant"] = require_reference_identity(executable)
    helper = child = None
    read_fd = write_fd = None
    buffers = {}
    last_now = 0

    def stamp():
        nonlocal last_now
        value = clock()
        if type(value) is not int or value < last_now:
            raise ValueError("monotonic clock moved backwards")
        last_now = value
        return value

    def send(text):
        if text in state["commands"]:
            raise ValueError("duplicate " + text)
        state["commands"].append(text)
        if helper is not None:
            helper.stdin.write(text + "\n")
            helper.stdin.flush()

    def lines(descriptor):
        data = os.read(descriptor, 4096)
        if not data:
            raise EOFError("child control pipe EOF")
        buffers[descriptor] = buffers.get(descriptor, b"") + data
        if len(buffers[descriptor]) > 4096:
            raise ValueError("unbounded control input")
        result = []
        while b"\n" in buffers[descriptor]:
            line, buffers[descriptor] = buffers[descriptor].split(b"\n", 1)
            if len(line) > 512:
                raise ValueError("oversized control event")
            result.append(json.loads(line))
        return result

    def record(event):
        if len(state["events"]) >= 64:
            raise ValueError("event capacity exceeded")
        # Do not retain device identifiers even in the controller receipt.
        state["events"].append({k: v for k, v in event.items() if k not in ("uid_sha256", "devices")})

    def reap(process, seconds):
        if process is None:
            return
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=seconds)

    try:
        read_fd, write_fd = os.pipe()
        os.set_blocking(read_fd, False)
        os.set_blocking(write_fd, False)
        argv, extra_env = command(mode, executable, write_fd, ref_arguments,
                                  m03_group=m03_group, human_group=human_group, onset_group=onset_group,
                                  mac_aec=mac_aec)
        proxy_fd = None
        if use_proxy:
            helper = spawn([str(bundle / "bt_proxy_registered"), "--authorized-proxy-once", str(fixture)],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
            proxy_fd = helper.stdout.fileno()
            os.set_blocking(proxy_fd, False)
        ready_limit = stamp() + 12_000_000_000
        while use_proxy:
            if stamp() > ready_limit or helper.poll() is not None:
                raise TimeoutError("proxy ready missing or child exited")
            if not select.select([proxy_fd], [], [], .01)[0]:
                continue
            ready = lines(proxy_fd)
            for event in ready:
                record(event)
            expected_duration = (264310 if mode == "REF" or m03_group else 360310) / 24000
            if len(ready) != 1 or ready[0].get("event") != "proxy_ready" or ready[0].get("play_calls") != 0:
                raise ValueError("invalid proxy readiness")
            if ready[0].get("fixture_sha256") != FIXTURES[fixture.name] or abs(ready[0].get("duration_seconds", 0)-expected_duration) > .001:
                raise ValueError("proxy fixture readback mismatch")
            break
        environment = dict(os.environ)
        environment.pop("AFTELLE_VPC_COMPARISON_FD", None)
        environment.update(extra_env)
        child = spawn(argv, pass_fds=(write_fd,), env=environment, stdin=subprocess.DEVNULL,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if device:
            print(json.dumps(dict(event="awaiting_original_UI_consent", app_pid=child.pid,
                                  m03_group=m03_group, human_group=human_group)), flush=True)
            if device_ui is not None:
                device_ui(child.pid)
        os.close(write_fd)
        write_fd = None
        wait_limit = stamp() + 240_000_000_000
        while not plan.state.terminal:
            if cancel_requested is not None and cancel_requested():
                raise InterruptedError("M20 operator Stop")
            now = stamp()
            if now > wait_limit or (plan.state.start is not None and now > plan.state.start + (10 if mode == "REF" else 15.5)*1e9):
                raise TimeoutError("UI/control watchdog")
            if select.select([read_fd], [], [], 0)[0]:
                for event in lines(read_fd):
                    record(event)
                    if m03_group and (event.get("batch"), event.get("scenario")) != ("R5_M03", m03_group):
                        raise ValueError("M03 source combination mismatch")
                    checked_event = event
                    if mac_aec is not None and (
                            event.get("batch") != "R5_M20" or event.get("scenario") != "A"
                            or event.get("proxy_requested") is not False
                            or any(event.get(k) != v for k, v in mac_aec.items())
                            or "source" in event):
                        raise ValueError("M20 event identity mismatch")
                    if mac_aec is not None and plan.state.start is not None and (
                            event.get("score_start_ns") != plan.state.start
                            or event.get("proxy_stop_ns") != plan.state.start + 11_000_000_000):
                        raise ValueError("M20 score clock changed")
                    if human_group:
                        batch = "R5_M07_F1" if onset_group else "R5_M07"
                        if (event.get("batch"), event.get("scenario"), event.get("source")) != (batch, human_group, "human") or event.get("proxy_requested") is not False:
                            raise ValueError("M07 human source identity mismatch")
                        if onset_group:
                            delay = 5_500_000_000 if onset_group == "A" else 0
                            if (event.get("onset_group") != onset_group
                                    or type(event.get("score_start_ns")) is not int
                                    or type(event.get("human_start_cue_ns")) is not int
                                    or event["human_start_cue_ns"] != event["score_start_ns"] + delay):
                                raise ValueError("F1 onset identity or cue mismatch")
                            if plan.state.start is not None and event["score_start_ns"] != plan.state.start:
                                raise ValueError("F1 score origin changed within one run")
                        elif "onset_group" in event:
                            raise ValueError("F1 event cannot enter the original M07 batch")
                        if "proxy_stop_ns" in event or type(event.get("human_speech_stop_ns")) is not int:
                            raise ValueError("M07 human timing contract mismatch")
                        checked_event = dict(event)
                        checked_event.pop("source")
                        checked_event["proxy_stop_ns"] = checked_event.pop("human_speech_stop_ns")
                    plan.accept(checked_event, now)
            if not plan.state.terminal and child.poll() is not None:
                raise RuntimeError("audio process exited before terminal event")
            proxy_exit = helper.poll() if helper is not None else None
            if proxy_exit not in (None, 0) or (proxy_exit == 0 and not plan.state.stopped):
                raise RuntimeError("proxy exited unexpectedly")
            for action in plan.actions(now):
                if use_proxy:
                    send(action)
            if use_proxy and select.select([proxy_fd], [], [], 0)[0] and helper.poll() is None:
                for event in lines(proxy_fd):
                    record(event)
                    if event.get("event") == "proxy_failed":
                        raise RuntimeError("proxy failure")
            select.select([read_fd], [], [], .001)
        if plan.cancelled:
            raise RuntimeError("REF cancelled")
        state["proxy_exit"] = helper.wait(timeout=5) if helper is not None else None
        while use_proxy and select.select([proxy_fd], [], [], 0)[0]:
            try:
                for event in lines(proxy_fd):
                    record(event)
            except EOFError:
                break
        if buffers.get(proxy_fd) or buffers.get(read_fd):
            raise ValueError("incomplete terminal event")
        play = [e for e in state["events"] if e.get("event") == "proxy_play_call"]
        stop = [e for e in state["events"] if e.get("event") == "proxy_stop_call"]
        done = [e for e in state["events"] if e.get("event") == "proxy_stopped"]
        if use_proxy and ((len(play), len(stop), len(done)) != (1, 1, 1) or not play[0].get("accepted")
                          or not done[0].get("success") or not done[0].get("not_playing")):
            raise ValueError("proxy PLAY/STOP/completion evidence missing")
        if device:
            print(json.dumps(dict(event="sealed_awaiting_original_export_and_quit",
                                  run_id=plan.state.run_id, m03_group=m03_group, human_group=human_group)), flush=True)
            if finish_ui is not None:
                finish_ui(child.pid)
        state["audio_exit"] = child.wait(timeout=240)  # Original export/quit consent remains external.
        if (use_proxy and state["proxy_exit"] != 0) or state["audio_exit"] != 0:
            raise RuntimeError("child exit failure")
        state.update(status="CONTROL_COMPLETED_DEVICE" if device else "PASS_OFFLINE_CONTROL_ONLY",
                     run_id=plan.state.run_id)
        return state
    except BaseException as error:
        state.update(status="FAIL", error=str(error))
        startup_failure = (isinstance(error, (AssertionError, ValueError)) and plan.state.run_id is None
                           and state["events"] and state["events"][-1].get("event") == "stop")
        if (failure_ui is not None and (mac_aec is not None or startup_failure)
                and child is not None and child.poll() is None):
            # The original App must stop/seal/export before its in-memory failure is reaped.
            try:
                preservation = failure_ui(child.pid)
                state["failure_ui"] = preservation if preservation is not None else "COMPLETED"
            except BaseException as preservation_error:
                state["failure_ui_error"] = str(preservation_error)
        raise
    finally:
        cleanup_error = None
        try:
            if helper is not None and helper.poll() is None and "STOP" not in state["commands"]:
                try:
                    send("STOP")
                except (BrokenPipeError, OSError):
                    state["stop_delivery"] = "FAILED_CHILD_TERMINATED"
            elif helper is not None and "STOP" not in state["commands"]:
                state["stop_delivery"] = "CHILD_ALREADY_EXITED"
            for process in (helper, child):
                try:
                    reap(process, 3)
                except BaseException as error:
                    state.update(status="FAIL", cleanup_error=str(error))
                    cleanup_error = error
                finally:
                    if process is not None:
                        state["audio_exit" if process is child else "proxy_exit"] = process.poll()
        finally:
            for descriptor in (read_fd, write_fd):
                if descriptor is not None:
                    os.close(descriptor)
            if helper is not None:
                helper.stdin.close()
                helper.stdout.close()
            fd = os.open(evidence / "result.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as output:
                json.dump(state, output, indent=2)
        if cleanup_error is not None:
            raise cleanup_error


if __name__ == "__main__":
    raise SystemExit("DEVICE_DISABLED: use the offline tests; device execution requires separate authorization")
