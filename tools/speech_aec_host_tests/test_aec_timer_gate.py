"""Timer controls use only isolated source copies and the actual gate CLI."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
import aec_timer_gate as gate

HERE = Path(__file__).resolve().parent
APP = HERE.parents[1] / "apps/macos/Aftelle"


class TimerGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = [(APP / name).read_text() for name in
                      ("MacSpeechAudioCapture.swift", "MacSpeechAcousticEchoHost.swift", "AppController.swift")]

    def check(self, source, reason=None):
        with tempfile.TemporaryDirectory(prefix="aftelle-timer-gate-") as directory:
            paths = [Path(directory) / (str(i) + ".swift") for i in range(3)]
            for path, value in zip(paths, source):
                path.write_text(value)
            result = subprocess.run([sys.executable, str(HERE / "aec_timer_gate.py"), *map(str, paths)],
                                    capture_output=True, text=True, check=False)
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.returncode, 1 if reason else 0)
        expected = "aec_timer_gate=FAIL reason=" + reason if reason else "aec_timer_gate=PASS"
        self.assertEqual(result.stdout.strip(), expected)

    def change(self, key, old, new):
        source = self.source.copy()
        file, kind, name, owner = gate.PROFILE["pins"][key]["location"]
        index = {"capture": 0, "aec": 1, "controller": 2}[file]
        rows = gate.tokens(source[index]);start, _, end = gate.block(rows, kind, name, owner)
        a, b = rows[start][1], rows[end][2];text = source[index][a:b]
        self.assertEqual(text.count(old), 1)
        source[index] = source[index][:a] + text.replace(old, new, 1) + source[index][b:]
        return source

    def inject(self, file, name, code, reason):
        source = self.source.copy();rows = gate.tokens(source[file])
        _, start, _ = gate.block(rows, "func", name, None)
        point = rows[start][2]
        source[file] = source[file][:point] + "\n" + code + "\n" + source[file][point:]
        self.check(source, reason)

    def test_current_source_and_host(self):
        self.check(self.source)

    def test_exact_snapshot_budget_remains(self):
        self.assertIn("Thread.sleep(forTimeInterval: 0.00025)", self.source[0])
        self.assertIn("for attempt in 0 ..< 20", self.source[0])
        self.assertIn("now - started < 5_000_000", self.source[0])
        self.assertIn("if attempt < 19", self.source[0])
        self.check(self.source)

    def test_comments_and_formatting(self):
        source = self.source.copy()
        source[0] = source[0].replace("Thread.sleep(forTimeInterval:", "Thread\n . sleep ( forTimeInterval:")
        source[0] += "\n/* Thread.sleep(1) /* nested */ #if DEBUG */\n"
        self.check(source)

    def test_capture_thread_sleep(self):
        self.inject(0, "processCapture", "Thread.sleep(forTimeInterval: 0.1)", "WAIT_OUTSIDE_SNAPSHOT")

    def test_render_usleep(self):
        self.inject(0, "processRenderedOutput", "usleep(1)", "WAIT_OUTSIDE_SNAPSHOT")

    def test_tap_wait(self):
        source = self.source.copy();marker = ") { [weak self] buffer, when in"
        rows = gate.tokens(source[0]);start, _, end = gate.block(rows, "func", "installRenderReferenceTapLocked", None)
        a, b = rows[start][1], rows[end][2];body = source[0][a:b]
        self.assertEqual(body.count(marker), 1)
        source[0] = source[0][:a] + body.replace(marker, marker + "\nThread.sleep(forTimeInterval: 0.1)", 1) + source[0][b:]
        self.check(source, "WAIT_OUTSIDE_SNAPSHOT")

    def test_aec_task_sleep(self):
        self.inject(1, "processCaptureSpans", "Task { try? await Task.sleep(nanoseconds: 1) }", "WAIT_OUTSIDE_SNAPSHOT")

    def test_wait_alias_and_unknown_wait(self):
        self.inject(0, "processCapture", "let pause = Thread.sleep", "WAIT_OUTSIDE_SNAPSHOT")
        self.inject(0, "processCapture", "let unknownWait: () -> Void = {}; unknownWait()", "WAIT_OUTSIDE_SNAPSHOT")

    def test_unknown_indirect_callback(self):
        self.inject(0, "processCapture", "let thunk: () -> Void = {}; thunk()", "CALLBACK_BODY_CONTRACT")

    def test_unknown_aec_change(self):
        self.inject(1, "processCaptureSpans", "let unreviewed = 1", "UNREVIEWED_AEC_SOURCE")

    def test_other_debug_function_is_not_excepted(self):
        self.inject(0, "beginAdaptationPlayback", "Thread.sleep(forTimeInterval: 0.1)", "WAIT_OUTSIDE_SNAPSHOT")

    def test_exception_cannot_expand(self):
        self.check(self.change("snapshot", "0.00025", "0.001"), "SNAPSHOT_WAIT_CONTRACT")

    def test_exception_cannot_move(self):
        source = self.change("snapshot", "Thread.sleep(forTimeInterval: 0.00025)", "()")
        rows = gate.tokens(source[0]);_, start, _ = gate.block(rows, "func", "nativeVoiceTimingSnapshot", None)
        point = rows[start][2]
        source[0] = source[0][:point] + "\nThread.sleep(forTimeInterval: 0.00025)\n" + source[0][point:]
        self.check(source, "WAIT_OUTSIDE_SNAPSHOT")

    def test_bounds_and_failure_exit_cannot_change(self):
        for old, new in [("0 ..< 20", "0 ..< 200"), ("5_000_000", "50_000_000"),
                         ("attempt < 19", "attempt < 190"), ("return false\n        }", "return true\n        }")]:
            with self.subTest(old=old):
                self.check(self.change("acquire", old, new), "SNAPSHOT_BOUND_CONTRACT")

    def test_debug_scope_cannot_be_spoofed_by_comment(self):
        source = self.source.copy()
        source[0] = "/*\n#if DEBUG\n*/\n" + source[0].replace("#if DEBUG", "#if !DEBUG")
        self.check(source, "SNAPSHOT_NOT_DEBUG")

    def test_snapshot_cannot_enter_audio_callback(self):
        self.inject(0, "processCapture", "let _ = nativeVoiceTimingDebug?.snapshot()", "SNAPSHOT_CALLSITE")

    def test_new_control_caller_requires_review(self):
        self.inject(2, "validateAppleVPAcousticRoute", "let _ = realtimeSpeechDiagnosticAudioEngine?.nativeVoiceTimingSnapshot(runID: UUID())",
                    "SNAPSHOT_CALLSITE")

    def test_control_actor_cannot_be_removed(self):
        source = self.source.copy();source[2] = source[2].replace("@MainActor\nfinal class AppController", "final class AppController", 1)
        self.check(source, "CONTROL_ACTOR_CONTRACT")


if __name__ == "__main__":
    program = unittest.main(exit=False)
    print("aec_timer_gate_control_cases=" + str(program.result.testsRun))
    print("aec_timer_gate_controls=" + ("PASS" if program.result.wasSuccessful() else "FAIL"))
    raise SystemExit(0 if program.result.wasSuccessful() else 1)
