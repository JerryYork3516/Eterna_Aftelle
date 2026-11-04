"""Source-only controls. No compiler, App, Engine or audio device is invoked."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
import aec_delay_gate as gate

HERE = Path(__file__).resolve().parent
CAPTURE = HERE.parents[1] / "apps/macos/Aftelle/MacSpeechAudioCapture.swift"
REFRESH = "refreshAcousticEchoPresentationLatencyLocked"
CACHED = "updateAcousticEchoDelayLocked"
DIAGNOSTIC = "beginAdaptationPlayback"


def change(source, name, old, new):
    rows = gate.tokens(source)
    start, end = gate.function(rows, name)
    a, b = rows[start][1], rows[end][2]
    body = source[a:b]
    if body.count(old) != 1:
        raise AssertionError("mutation did not identify exactly one real code location")
    return source[:a] + body.replace(old, new, 1) + source[b:]


class DelayGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = CAPTURE.read_text()

    def check(self, source, reason=None):
        with tempfile.TemporaryDirectory(prefix="aftelle-delay-gate-") as directory:
            path = Path(directory) / "Capture.swift"
            path.write_text(source)
            result = subprocess.run([sys.executable, str(HERE / "aec_delay_gate.py"), str(path)],
                                    capture_output=True, text=True, check=False)
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.returncode, 1 if reason else 0)
        expected = "aec_delay_gate=FAIL reason=" + reason if reason else "aec_delay_gate=PASS"
        self.assertEqual(result.stdout.strip(), expected)

    def test_current_source(self):
        self.check(self.source)

    def test_m22_read_only_metadata_exists(self):
        self.assertIn('"playerOutputPresentation": playerNode.outputPresentationLatency', self.source)
        self.assertIn("latenciesSeconds: latencies", self.source)
        self.check(self.source)

    def test_multiline_member_and_call_formatting(self):
        source = self.source.replace("engine.outputNode.presentationLatency",
                                     "engine\n . outputNode /* hardware */\n . presentationLatency")
        source = source.replace("acousticEchoHost.updateDelay(", "acousticEchoHost\n . updateDelay (\n")
        source = source.replace("func " + REFRESH + "()", "func\n " + REFRESH + "\n()")
        self.check(source)

    def test_comments_and_literal_braces_do_not_create_scopes(self):
        source = self.source + "\n/* func fake() { /* nested */ playerNode.outputPresentationLatency } */\n"
        rows = gate.tokens(source)
        start, _ = gate.function(rows, "processCapture")
        point = rows[start][2]
        source = source[:point] + '\nlet braceText = "{ \\(String("}")) }"\n' + source[point:]
        self.check(source)

    def test_player_replaces_hardware_source(self):
        self.check(change(self.source, REFRESH, "engine.outputNode.presentationLatency",
                          "playerNode!.outputPresentationLatency"), "PLAYER_DELAY_IN_AEC")

    def test_player_enters_actual_update_parameter(self):
        self.check(change(self.source, CACHED, "outputPresentationLatencySeconds,",
                          "playerNode!\n . outputPresentationLatency,"), "PLAYER_DELAY_IN_AEC")

    def test_indirect_m22_cache_pollution(self):
        self.check(change(self.source, DIAGNOSTIC, "let latencies =", "outputPresentationLatencySeconds = 0\nlet latencies ="),
                   "AEC_CACHE_WRITE_OUTSIDE_CONTROL")
        self.check(change(self.source, DIAGNOSTIC, "guard latencies.values", 'outputPresentationLatencySeconds = latencies["playerOutputPresentation"] ?? 0\nguard latencies.values'),
                   "AEC_CACHE_WRITE_OUTSIDE_CONTROL")

    def test_changed_parameter_chain_without_new_player_property(self):
        self.check(change(self.source, CACHED, "outputPresentationLatencySeconds,", "0.0,"),
                   "AEC_DELAY_CHAIN_CHANGED")

    def test_output_source_removed(self):
        self.check(change(self.source, REFRESH, "engine.outputNode.presentationLatency", "0.0"),
                   "REQUIRED_IO_SOURCE")

    def test_input_source_corrupted(self):
        self.check(change(self.source, REFRESH, "engine.inputNode.presentationLatency", "engine.outputNode.presentationLatency"),
                   "REQUIRED_IO_SOURCE")

    def test_unknown_sink_or_method_reference(self):
        self.check(change(self.source, DIAGNOSTIC, "let latencies =", "let unsafeSink = acousticEchoHost.updateDelay\nlet latencies ="),
                   "UPDATE_DELAY_CALLSITE")

    def test_capture_callback_hardware_read(self):
        self.inject_read("processCapture", "_ = engine?.inputNode.presentationLatency", "CALLBACK_HARDWARE_LATENCY")

    def test_render_callback_hardware_read(self):
        self.inject_read("processRenderedOutput", "_ = engine?.outputNode.presentationLatency", "CALLBACK_HARDWARE_LATENCY")

    def test_callback_interpolation_is_not_hidden(self):
        self.inject_read("processCapture", 'let text = "\\(engine?.outputNode.presentationLatency)"', "CALLBACK_HARDWARE_LATENCY")

    def inject_read(self, name, code, reason):
        rows = gate.tokens(self.source)
        start, _ = gate.function(rows, name)
        point = rows[start][2]
        self.check(self.source[:point] + "\n" + code + "\n" + self.source[point:], reason)

    def test_m22_not_a_blanket_whitelist(self):
        self.check(change(self.source, DIAGNOSTIC, "let latencies =", "let unreviewed = 1\nlet latencies ="),
                   "DIAGNOSTIC_CONTRACT_CHANGED")

    def test_missing_scope_fails_closed(self):
        self.check(self.source.replace("func " + REFRESH, "func renamedRefresh", 1), "FUNCTION_SCOPE")

    def test_readback_error_is_not_a_safety_negative(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(HERE / "aec_delay_gate.py"), str(Path(directory) / "missing.swift")],
                                    capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout.strip(), "aec_delay_gate=ERROR reason=READBACK_UNAVAILABLE")
        self.assertEqual(result.stderr, "")

    def cache_change(self, code, reason):
        rows = gate.tokens(self.source)
        start, _ = gate.function(rows, "tearDownIfIdle")
        point = rows[start][2]
        self.check(self.source[:point] + "\n" + code + "\n" + self.source[point:], reason)

    def test_compound_cache_writes(self):
        for field in ("outputPresentationLatencySeconds", "capturePresentationLatencySeconds"):
            for prefix in ("", "self.\n"):
                for operator in ("+=", "-=", "*=", "/=", "%=", "&+=", "&-=", "&*=", "<<=", ">>=", "&=", "|=", "^="):
                    with self.subTest(field=field, prefix=prefix, operator=operator):
                        self.cache_change(prefix + field + " " + operator + " 1", "AEC_CACHE_WRITE_OUTSIDE_CONTROL")

    def test_inout_cache_writes(self):
        for field in ("outputPresentationLatencySeconds", "capturePresentationLatencySeconds"):
            for prefix in ("", "self."):
                with self.subTest(field=field, prefix=prefix):
                    self.cache_change("withUnsafeMutablePointer(to: &" + prefix + field + ") { $0.pointee = 1 }",
                                      "AEC_CACHE_WRITE_OUTSIDE_CONTROL")

    def test_unknown_cache_modification_fails_closed(self):
        for code in ("self.outputPresentationLatencySeconds.negate()",
                     r"let key = \SystemMacSpeechVoiceProcessingEngine.capturePresentationLatencySeconds",
                     "self.`outputPresentationLatencySeconds` += 1",
                     'let text = "\\(self.outputPresentationLatencySeconds)"'):
            with self.subTest(code=code):
                self.cache_change(code, "AEC_CACHE_ACCESS_OUTSIDE_CONTROL")


if __name__ == "__main__":
    program = unittest.main(exit=False)
    print("aec_delay_gate_control_cases=" + str(program.result.testsRun))
    print("aec_delay_gate_controls=" + ("PASS" if program.result.wasSuccessful() else "FAIL"))
    raise SystemExit(0 if program.result.wasSuccessful() else 1)
