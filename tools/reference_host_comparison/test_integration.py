"""Registered Foundation admission plus real pipes with Fake child handles only."""
import io
import json
import os
import re
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import integration as target
from prepare_player import FIXTURES

BUNDLE = Path(os.environ["R3_BUNDLE"]).resolve()
REF = Path(os.environ["R3_REF_EXECUTABLE"])
HOST = Path(os.environ["R3_HOST_EXECUTABLE"])
START = 10_000_000_000
ID = "11111111-1111-4111-8111-111111111111"
REF_ARGS = ("vp-c", "--authorize-vp-c", "--material-content-reviewed", "--enable-audio", "--arm-diagnostics",
            "--mode", "VP_ON", "--duration", "16", "--target-registration", "NOT_READ_FAKE_REGISTRATION",
            "--material", "NOT_READ_REF_RESIDENT", "--material-sha256", "NOT_USED_BY_FAKE",
            "--material-pcm-sha256", "NOT_USED_BY_FAKE", "--study-id", "R3_OFFLINE",
            "--output-dir", "NOT_CREATED_BY_FAKE")


def schedule(mode):
    if mode == "REF":
        return dict(schema_version=1, source="ADAPTED_REF", clock="mach_absolute_nanoseconds", event="schedule",
                    run_id=ID, observation_start_ns=START, near_start_ns=START+4_000_000_000,
                    near_stop_ns=START+9_000_000_000,
                    anchor=dict(absolute_before=START, absolute_after=START, continuous=START+900_000_000,
                                numer=1, denom=1))
    return dict(schema_version=1, clock="mach_absolute_nanoseconds", event="schedule", run_id=ID,
                score_start_ns=START+4_000_000_000, proxy_stop_ns=START+15_000_000_000)


def proxy_ready(mode):
    return dict(event="proxy_ready", play_calls=0, uid_sha256="FAKE_REDACTED", uptime_ns=START,
                fixture_sha256=FIXTURES[mode+"_proxy.wav"],
                duration_seconds=(264310 if mode == "REF" else 360310)/24000)


class FakeChild:
    def __init__(self):
        self.code = None
        self.terminated = self.killed = False
        self.waits = 0
        self.resist_terminate = False
        self.resist_kill = False

    def poll(self):
        return self.code

    def wait(self, timeout):
        self.waits += 1
        if self.code is None:
            raise subprocess.TimeoutExpired("FAKE_ONLY", timeout)
        return self.code

    def terminate(self):
        self.terminated = True
        if not self.resist_terminate:
            self.code = -15

    def kill(self):
        self.killed = True
        if not self.resist_kill:
            self.code = -9


class FakeProcesses:
    device_disabled = True

    def __init__(self, mode, fault=None):
        self.mode, self.fault = mode, fault
        self.helper, self.child = FakeChild(), FakeChild()
        self.helper.resist_terminate = fault in ("hung_helper", "unreapable")
        self.helper.resist_kill = fault == "unreapable"
        self.calls, self.commands = [], []
        self.descriptors = []
        self.app_write = None
        self.tick = -1
        self.value = START
        self.schedule = schedule(mode)
        if fault == "clock":
            self.schedule["clock"] = "mach_continuous_ticks"

    def emit(self, fd, value):
        os.write(fd, (json.dumps(value, separators=(",", ":"))+"\n").encode())

    def __call__(self, argv, **kwargs):
        self.calls.append((argv, kwargs))
        if len(self.calls) == 1:
            read, self.proxy_write = os.pipe()
            self.descriptors.append(self.proxy_write)
            self.helper.stdout = os.fdopen(read, "rb", buffering=0)
            factory = self
            class Commands(io.StringIO):
                def write(self, data):
                    command = data.strip()
                    factory.commands.append((command, factory.value))
                    if factory.fault == "broken_stdin":
                        raise BrokenPipeError("Fake closed stdin")
                    if command == "PLAY":
                        factory.emit(factory.proxy_write, dict(event="proxy_play_call", accepted=True, play_calls=1))
                        if factory.fault == "duplicate_play_ack":
                            factory.emit(factory.proxy_write, dict(event="proxy_play_call", accepted=True, play_calls=1))
                    elif command == "STOP":
                        if factory.fault != "missing_ack":
                            factory.emit(factory.proxy_write, dict(event="proxy_stop_call"))
                            factory.emit(factory.proxy_write, dict(event="proxy_stopped", success=True, not_playing=True))
                        if factory.fault not in ("hung_helper", "unreapable"):
                            factory.helper.code = 7 if factory.fault == "proxy_failure_after_stop" else 0
                    return super().write(data)
            self.helper.stdin = Commands()
            if self.fault != "no_ready":
                ready = proxy_ready(self.mode)
                if self.fault == "wrong_duration_field":
                    ready["duration_s"] = ready.pop("duration_seconds")
                self.emit(self.proxy_write, ready)
            return self.helper
        self.app_write = os.dup(kwargs["pass_fds"][0])
        self.descriptors.append(self.app_write)
        if self.fault != "no_schedule":
            self.emit(self.app_write, self.schedule)
        if self.fault == "duplicate":
            self.emit(self.app_write, self.schedule)
        if self.fault == "oversized":
            os.write(self.app_write, b"x"*513+b"\n")
        return self.child

    def clock(self):
        if self.app_write is None:
            if self.fault == "no_ready":
                self.value += 13_000_000_000
            return self.value
        self.tick += 1
        stop = 9 if self.mode == "REF" else 15
        end = 13.5 if self.mode == "REF" else 19
        offset = [0, 0, 4, stop, end][min(self.tick, 4)]
        if self.fault == "no_schedule" and self.tick > 0:
            offset = 241
        if self.fault == "late" and self.tick == 2:
            offset = 4.050000001
        if self.fault == "late_stop" and self.tick == 3:
            offset = stop+.050000001
        if self.fault == "backwards" and self.tick == 2:
            offset = -1
        if self.fault == "proxy_failure_after_stop" and self.tick == 4:
            offset = stop+.01
        self.value = START + int(offset*1e9)
        if self.tick == 2:
            if self.fault in ("cancel", "foreign"):
                event = dict(schema_version=1, clock="mach_absolute_nanoseconds", event="cancel" if self.mode == "REF" else "stop", run_id=ID)
                if self.mode == "REF": event["source"] = "ADAPTED_REF"
                if self.fault == "foreign": event["run_id"] = "22222222-2222-4222-8222-222222222222"
                self.emit(self.app_write, event)
            if self.fault == "eof":
                os.close(self.app_write)
                self.descriptors.remove(self.app_write)
            if self.fault == "child_exit": self.child.code = 7
            if self.fault == "helper_exit": self.helper.code = 7
        if self.tick == 4 and self.fault != "proxy_failure_after_stop":
            terminal = dict(schema_version=1, clock="mach_absolute_nanoseconds", event="stop", run_id=ID)
            if self.mode == "REF": terminal["source"] = "ADAPTED_REF"
            self.emit(self.app_write, terminal)
            if self.fault == "duplicate_terminal": self.emit(self.app_write, terminal)
            if self.fault == "partial_terminal": os.write(self.app_write, b'{"unfinished":')
            self.child.code = 7 if self.fault == "exit_failure" else 0
        return self.value

    def close(self):
        for descriptor in self.descriptors:
            os.close(descriptor)


class MaterialTests(unittest.TestCase):
    def probe(self, root, name):
        return subprocess.run([str(BUNDLE/"registry_check"), str(root), name], capture_output=True, text=True, timeout=5)

    def test_registered_materials(self):
        for name, expected in FIXTURES.items():
            result = self.probe(BUNDLE/"assets", name)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["sha256"], expected)

    def test_sha_format_duration_and_leading_negative_controls(self):
        original = (BUNDLE/"assets/HOST_proxy.wav").read_bytes()
        data = original.index(b"data")+8
        fmt = original.index(b"fmt ")+8
        for condition in ("sha", "format", "duration", "leading", "filename", "symlink", "truncated"):
            with self.subTest(condition=condition), tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory:
                root = Path(directory).resolve()
                payload = bytearray(original)
                if condition == "sha": payload[data+200000] ^= 1
                if condition == "format": struct.pack_into('<I', payload, fmt+4, 48000)
                if condition == "duration":
                    del payload[data+720618:data+720620]
                    struct.pack_into('<I', payload, data-4, 720618)
                    struct.pack_into('<I', payload, 4, len(payload)-8)
                if condition == "leading": payload[data] = 1
                if condition == "truncated": payload = payload[:40]
                name = "unregistered.wav" if condition == "filename" else "HOST_proxy.wav"
                file = root/name
                if condition == "symlink": file.symlink_to(BUNDLE/"assets/HOST_proxy.wav")
                else: file.write_bytes(payload)
                result = self.probe(root, name)
                self.assertEqual(result.returncode, 1, condition)
                reasons = {"sha": "SHA mismatch", "format": "PCM format mismatch", "duration": "Frame count mismatch",
                           "leading": "Leading silence mismatch", "filename": "Unregistered filename",
                           "symlink": "Unregistered path or symlink", "truncated": "Invalid RIFF"}
                self.assertIn(reasons[condition], result.stderr)

    def test_wrong_profile_and_unregistered_path(self):
        with tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory:
            root = Path(directory).resolve()
            shutil.copyfile(BUNDLE/"assets/REF_proxy.wav", root/"HOST_proxy.wav")
            self.assertEqual(self.probe(root, "HOST_proxy.wav").returncode, 1)
            (root/"nested").mkdir()
            shutil.copyfile(BUNDLE/"assets/REF_proxy.wav", root/"nested/REF_proxy.wav")
            self.assertEqual(self.probe(root, "nested/REF_proxy.wav").returncode, 1)


class ExecutionTests(unittest.TestCase):
    def exercise(self, mode, fault=None):
        fake = FakeProcesses(mode, fault)
        with tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory:
            path = Path(directory)/mode
            try:
                with patch.object(subprocess, "Popen", side_effect=AssertionError("Real process forbidden")):
                    if fault:
                        reasons = {
                            "foreign": "foreign terminal", "cancel": "REF cancelled", "duplicate": "duplicate schedule",
                            "clock": "invalid REF schedule identity", "backwards": "monotonic clock moved backwards",
                            "late": "missed start deadline", "no_ready": "proxy ready missing", "no_schedule": "watchdog",
                            "eof": "pipe EOF", "child_exit": "audio process exited", "helper_exit": "proxy exited",
                            "broken_stdin": "Fake closed stdin", "missing_ack": "completion evidence missing",
                            "hung_helper": "timed out", "duplicate_terminal": "duplicate terminal",
                            "partial_terminal": "incomplete terminal", "oversized": "oversized control event",
                            "late_stop": "missed quiet deadline", "exit_failure": "child exit failure",
                            "duplicate_play_ack": "completion evidence missing",
                            "unreapable": "timed out",
                            "proxy_failure_after_stop": "proxy exited unexpectedly",
                            "wrong_duration_field": "proxy fixture readback mismatch",
                        }
                        with self.assertRaisesRegex((ValueError, AssertionError, RuntimeError, TimeoutError, EOFError, BrokenPipeError, subprocess.TimeoutExpired), reasons[fault]):
                            target.run(BUNDLE, mode, REF if mode == "REF" else HOST, path,
                                       REF_ARGS if mode == "REF" else (), spawn=fake, clock=fake.clock)
                    else:
                        target.run(BUNDLE, mode, REF if mode == "REF" else HOST, path,
                                   REF_ARGS if mode == "REF" else (), spawn=fake, clock=fake.clock)
                result = json.loads((path/"result.json").read_text())
                self.assertEqual(result["status"], "FAIL" if fault else "PASS_OFFLINE_CONTROL_ONLY")
                self.assertEqual((path/"result.json").stat().st_mode & 0o777, 0o600)
                commands = [command for command, _ in fake.commands]
                self.assertLessEqual(commands.count("PLAY"), 1)
                self.assertLessEqual(commands.count("STOP"), 1)
                if fault == "helper_exit":
                    self.assertEqual(commands, [])
                    self.assertEqual(result["stop_delivery"], "CHILD_ALREADY_EXITED")
                    self.assertGreater(fake.helper.waits, 0)
                else:
                    self.assertEqual(commands.count("STOP"), 1)
                if fault == "unreapable":
                    self.assertIn("cleanup_error", result)
                    self.assertTrue(fake.helper.terminated and fake.helper.killed)
                else:
                    self.assertIsNotNone(fake.helper.poll())
                if len(fake.calls) == 2: self.assertIsNotNone(fake.child.poll())
                self.assertTrue(fake.helper.stdin.closed and fake.helper.stdout.closed)
                if fault == "hung_helper":
                    self.assertTrue(fake.helper.terminated and fake.helper.killed)
                    self.assertGreaterEqual(fake.helper.waits, 3)
                if not fault:
                    self.assertEqual(fake.commands, [("PLAY", START+4_000_000_000), ("STOP", START+(9 if mode == "REF" else 15)*1_000_000_000)])
                    argv, kwargs = fake.calls[1]
                    if mode == "REF":
                        self.assertIn("AFTELLE_VPC_COMPARISON_FD", kwargs["env"])
                        self.assertFalse(any("score-control" in x for x in argv))
                    else:
                        self.assertNotIn("AFTELLE_VPC_COMPARISON_FD", kwargs["env"])
                        self.assertTrue(any("score-control-fd=" in x for x in argv))
                self.assertTrue(target.DEVICE_DISABLED)
            finally:
                fake.close()

    def test_ref_full_loop(self): self.exercise("REF")
    def test_host_full_loop(self): self.exercise("HOST")
    def test_wrong_run(self): self.exercise("REF", "foreign")
    def test_ref_cancel(self): self.exercise("REF", "cancel")
    def test_duplicate_schedule(self): self.exercise("HOST", "duplicate")
    def test_wrong_clock(self): self.exercise("REF", "clock")
    def test_backwards_clock(self): self.exercise("HOST", "backwards")
    def test_late_play(self): self.exercise("REF", "late")
    def test_late_stop(self): self.exercise("REF", "late_stop")
    def test_no_ready(self): self.exercise("REF", "no_ready")
    def test_wrong_duration_field_refused(self): self.exercise("REF", "wrong_duration_field")
    def test_no_schedule(self): self.exercise("HOST", "no_schedule")
    def test_eof(self): self.exercise("REF", "eof")
    def test_child_exit(self): self.exercise("HOST", "child_exit")
    def test_proxy_exit(self): self.exercise("HOST", "helper_exit")
    def test_proxy_error_after_stop_aborts_audio_child(self): self.exercise("HOST", "proxy_failure_after_stop")
    def test_broken_stdin(self): self.exercise("HOST", "broken_stdin")
    def test_missing_completion(self): self.exercise("HOST", "missing_ack")
    def test_hung_proxy(self): self.exercise("HOST", "hung_helper")
    def test_unreapable_child_cannot_report_pass(self): self.exercise("HOST", "unreapable")
    def test_duplicate_terminal(self): self.exercise("REF", "duplicate_terminal")
    def test_partial_terminal(self): self.exercise("HOST", "partial_terminal")
    def test_oversized_event(self): self.exercise("REF", "oversized")
    def test_failed_exit(self): self.exercise("HOST", "exit_failure")
    def test_duplicate_play_ack(self): self.exercise("HOST", "duplicate_play_ack")

    def test_host_clears_ref_environment(self):
        with patch.dict(os.environ, {"AFTELLE_VPC_COMPARISON_FD": "999"}):
            self.exercise("HOST")

    def test_existing_evidence_not_overwritten(self):
        with tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory:
            existing = Path(directory)/"REF"
            existing.mkdir()
            sentinel = existing/"sentinel"
            sentinel.write_text("keep")
            fake = FakeProcesses("REF")
            with self.assertRaises(FileExistsError):
                target.run(BUNDLE, "REF", REF, existing, REF_ARGS, spawn=fake, clock=fake.clock)
            self.assertEqual(fake.calls, [])
            self.assertEqual(sentinel.read_text(), "keep")

    def test_binary_identity_before_any_launch(self):
        with tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory:
            fake = FakeProcesses("REF")
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                target.run(BUNDLE, "REF", HOST, Path(directory)/"REF", REF_ARGS, spawn=fake, clock=fake.clock)
            self.assertEqual(fake.calls, [])

    def test_device_launch_disabled(self):
        with tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory, patch.object(subprocess, "Popen") as spawn:
            with self.assertRaisesRegex(PermissionError, "DEVICE_DISABLED"):
                target.run(BUNDLE, "REF", REF, Path(directory)/"unused", REF_ARGS)
            spawn.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_optimized_python_cannot_disable_original_assertions(self):
        code = 'from integration import Plan; Plan("REF", None)'
        result = subprocess.run([sys.executable, "-B", "-O", "-c", code], cwd=Path(__file__).parent,
                                capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("would disable original safety assertions", result.stderr)

    def test_mode_identity_and_consent(self):
        with self.assertRaises(ValueError): target.verify_bundle(BUNDLE, "A")
        with self.assertRaises(ValueError): target.command("REF", HOST, 10, REF_ARGS)
        with self.assertRaises(ValueError): target.command("HOST", HOST, 10, REF_ARGS)
        with self.assertRaises(ValueError): target.command("REF", REF, 10, REF_ARGS[1:])
        plan = target.Plan("HOST", target.original_single_run(BUNDLE/"original_sync_once.py"))
        with self.assertRaises(ValueError): plan.accept(schedule("REF"), START)

    def test_fake_readiness_matches_registered_native_source(self):
        source = (BUNDLE/"bt_proxy_speech_once.m").read_text()
        line = next(line for line in source.splitlines() if '@"event":@"proxy_ready"' in line)
        keys = set(re.findall(r'@"(\w+)":', line))
        self.assertEqual(set(proxy_ready("REF")), keys)
        self.assertIn("duration_seconds", keys)
        self.assertNotIn("duration_s", keys)


class DeviceGateTests(unittest.TestCase):
    def test_missing_or_wrong_consent_never_spawns(self):
        with patch.object(subprocess, "Popen") as spawn:
            for consent in (None, True, "R3", ""):
                with self.assertRaises(PermissionError):
                    target.run_device_once(BUNDLE, "REF", REF, "unused", REF_ARGS, consent=consent)
            spawn.assert_not_called()

    def test_target_identity_precedes_reservation_and_launch(self):
        with tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory, patch.object(subprocess, "Popen") as spawn:
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                target.run_device_once(BUNDLE, "REF", HOST, Path(directory)/"REF", REF_ARGS,
                                       consent=target.R4_CONSENT)
            self.assertEqual(list(Path(directory).iterdir()), [])
            spawn.assert_not_called()

    def test_player_requires_frozen_binary_not_only_receipt(self):
        with patch.object(target, "PLAYER_BINARY_SHA", "0"*64), patch.object(subprocess, "Popen") as spawn:
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                target.run_device_once(BUNDLE, "REF", REF, "unused", REF_ARGS, consent=target.R4_CONSENT)
            spawn.assert_not_called()

    def test_explicit_entry_uses_real_spawn_and_consumes_once(self):
        with tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory, patch.object(target, "_connected_run") as loop:
            parent = Path(directory).resolve()
            parent.chmod(0o700)
            target.run_device_once(BUNDLE, "REF", REF, parent/"REF", REF_ARGS, consent=target.R4_CONSENT)
            self.assertIs(loop.call_args.kwargs["spawn"], subprocess.Popen)
            self.assertTrue(loop.call_args.kwargs["device"])
            self.assertEqual((parent/"R4_REF_consumed.json").stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                target.run_device_once(BUNDLE, "REF", REF, parent/"another", REF_ARGS, consent=target.R4_CONSENT)
            self.assertEqual(loop.call_count, 1)

    def test_unsafe_or_symlink_evidence_parent_refused(self):
        with tempfile.TemporaryDirectory(dir=BUNDLE.parent) as directory, patch.object(target, "_connected_run") as loop:
            parent = Path(directory).resolve()
            parent.chmod(0o755)
            with self.assertRaisesRegex(ValueError, "owned private"):
                target.run_device_once(BUNDLE, "HOST", HOST, parent/"HOST", consent=target.R4_CONSENT)
            parent.chmod(0o700)
            (parent/"alias").symlink_to(parent, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symlinks"):
                target.run_device_once(BUNDLE, "HOST", HOST, parent/"alias/HOST", consent=target.R4_CONSENT)
            loop.assert_not_called()

    def test_cli_still_requires_explicit_mode_and_consent(self):
        result = subprocess.run([sys.executable, "-B", str(Path(target.__file__).with_name("device_once.py"))],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--authorize-device-once", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
