"""One reviewed DEBUG snapshot exception; shares the delay gate's Swift lexer."""

from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from aec_delay_gate import GateFailure, declaration, tokens

ROOT = Path(__file__).resolve().parents[2]
PROFILE = {'baseline': '15ae07c97d500c8a65382bec1a488ede4cef554b',
 'pins': {'snapshot': {'location': ['capture', 'func', 'snapshot', ['class', 'MacSpeechNativeVoiceTiming']],
                       'sha256': 'cab7e849fe4fbbbd012ee458f9c2167aace7d626b0313d40bb264bf48bdc7a1d'},
          'acquire': {'location': ['capture',
                                   'func',
                                   'acquireSnapshotAccess',
                                   ['class', 'MacSpeechNativeVoiceTiming']],
                      'sha256': 'c2d4fdf1945f6b44d9c7670ed1771a95543ae73c331e994a4eef8270f7b39ccd'},
          'read': {'location': ['capture',
                                'func',
                                'nativeVoiceTimingSnapshot',
                                ['extension', 'SystemMacSpeechVoiceProcessingEngine']],
                   'sha256': 'bc9fb3fde067df6d8366431c16999fae58aa7d81f63fef25c5b56c9db4140cb5'},
          'echo': {'location': ['capture',
                                'func',
                                'acousticEchoSnapshot',
                                ['class', 'SystemMacSpeechVoiceProcessingEngine']],
                   'sha256': 'c1addd7f73d5260011587769da049779eb5accc74ef499991a3df73895fce486'},
          'stats': {'location': ['capture',
                                 'func',
                                 'nativeVoiceDebugSnapshot',
                                 ['extension', 'SystemMacSpeechVoiceProcessingEngine']],
                    'sha256': '252e1485a261a1320a7efb983805f8f985e41a3fd1e930360f61f335ef80fe02'},
          'seal': {'location': ['capture',
                                'func',
                                'sealNativeVoiceDebug',
                                ['extension', 'SystemMacSpeechVoiceProcessingEngine']],
                   'sha256': '6749eb2fc2f3ed23bc5cc380d76927ac8274f5019d3bcc71988bffefa834d839'},
          'stop_seal': {'location': ['capture',
                                     'func',
                                     'stopAndSealNativeVoiceDebug',
                                     ['extension', 'SystemMacSpeechVoiceProcessingEngine']],
                        'sha256': 'd67c05e639fc6a3788f4c2b10500430872d94de44b01ac3591198d5529c62090'},
          'stats_value': {'location': ['capture',
                                       'var',
                                       'snapshot',
                                       ['struct', 'MacSpeechNativeVoiceDebugStats']],
                          'sha256': '488ac40dd197dab762ccfa6066a8b3281d016ff4d6ad0dd66932e1be29004be2'},
          'validate': {'location': ['controller', 'func', 'validateAppleVPRuntimeDiagnostics', None],
                       'sha256': '5397db74f298c6b97ff499d2e1614c94a8ad24377a41d0e218314bfd498a4f06'},
          'manifest': {'location': ['controller', 'func', 'appleVPAcousticTimingManifest', None],
                       'sha256': 'a1ee185da9e74e8c0752bfa3f571911bc62c3b026c8ee442304c9f1712ad9bb8'}},
 'callbacks': {'startCapture': '813bf0c16c149291f081f135da38bfd3514e6d1e31afb962a13c3a5af39cdc2b',
               'processCapture': 'afd7d0749a48dbfff91c337beb4a574a7017597c93a2e408c4a2c57a53b0605a',
               'processRenderedOutput': '9d5c133a782e99213f2475d008260537d6ba630fad182a3e83833ecffa935d3d',
               'installRenderReferenceTapLocked': 'ac36de948695a165da0c10a84833542f1571480b522e6437de66ca1c2c72ee61'},
 'aec_tokens_sha256': '4c8d48995bd5bbec6c6a9b60eff38838584d8b3046c8581136ab81834ebc59dc'}


def digest(rows):
    return hashlib.sha256(json.dumps([r[0] for r in rows], ensure_ascii=False).encode()).hexdigest()


def block(rows, kind, name, owner=None):
    within = None
    if owner:
        _, start, end = declaration(rows, owner[0], owner[1])
        within = start, end
    return declaration(rows, kind, name, within)


def validate(capture, aec, controller):
    sources = {"capture": capture, "aec": aec, "controller": controller}
    rows = {key: tokens(value) for key, value in sources.items()}
    spans = {}
    for key, entry in PROFILE["pins"].items():
        file, kind, name, owner = entry["location"]
        spans[key] = block(rows[file], kind, name, owner)

    def contains(i, key, header=False):
        decl, start, end = spans[key]
        return (decl if header else start) <= i <= end

    def is_debug(position):
        stack = []
        for i, (word, start, _) in enumerate(rows["capture"]):
            if start >= position:
                break
            if word != "#" or capture[capture.rfind("\n", 0, start) + 1:start].strip():
                continue
            op = rows["capture"][i + 1][0]
            end = capture.find("\n", start)
            condition = [r[0] for r in rows["capture"][i + 2:] if r[1] < end]
            if op == "if":
                stack.append(condition == ["DEBUG"])
            elif op == "endif":
                if not stack:
                    raise GateFailure("DEBUG_SCOPE")
                stack.pop()
            elif stack:
                stack[-1] = condition == ["DEBUG"] if op == "elseif" else False
        return any(stack)

    if not is_debug(rows["capture"][spans["snapshot"][0]][1]):
        raise GateFailure("SNAPSHOT_NOT_DEBUG")
    for file in ("capture", "aec"):
        for i, (word, _, _) in enumerate(rows[file]):
            hidden = word.startswith('"') and "\\(" in word and re.search(r"\b\w*(sleep|wait)\w*\b", word, re.I)
            waiting = not word.startswith('"') and word != "await" and re.search(r"sleep|wait", word, re.I)
            if waiting or hidden:
                if file != "capture" or not (contains(i, "snapshot", True) or contains(i, "acquire", True)):
                    raise GateFailure("WAIT_OUTSIDE_SNAPSHOT")

    for file, content in rows.items():
        for i, (word, _, _) in enumerate(content):
            if file == "controller" and word == "MacSpeechNativeVoiceTiming":
                raise GateFailure("UNREVIEWED_SNAPSHOT_TYPE_REFERENCE")
            if word in ("nativeVoiceTimingSnapshot", "acquireSnapshotAccess"):
                definition = i > 0 and content[i - 1][0] == "func"
                allowed = (file == "capture" and (definition or contains(i, "snapshot", True)))
                allowed |= file == "controller" and any(contains(i, key) for key in ("validate", "manifest"))
                if not allowed:
                    raise GateFailure("SNAPSHOT_CALLSITE")
            if file != "controller" and word == "snapshot" and i and content[i - 1][0] == ".":
                allowed = file == "capture" and any(contains(i, key) for key in
                    ("read", "echo", "stats", "seal", "stop_seal", "stats_value"))
                if not allowed:
                    raise GateFailure("SNAPSHOT_CALLSITE")

    for name, expected in PROFILE["callbacks"].items():
        start, _, end = block(rows["capture"], "func", name, None)
        if digest(rows["capture"][start:end + 1]) != expected:
            raise GateFailure("CALLBACK_BODY_CONTRACT")
    if digest(rows["aec"]) != PROFILE["aec_tokens_sha256"]:
        raise GateFailure("UNREVIEWED_AEC_SOURCE")

    decl, start, _ = declaration(rows["controller"], "class", "AppController")
    if [r[0] for r in rows["controller"][decl - 3:start + 1]] != [
            "@", "MainActor", "final", "class", "AppController", ":", "ObservableObject", "{"]:
        raise GateFailure("CONTROL_ACTOR_CONTRACT")
    for key, entry in PROFILE["pins"].items():
        file, _, _, _ = entry["location"]
        decl, _, end = spans[key]
        if key in ("validate", "manifest"):
            previous = decl - 1
            while previous >= 0 and rows[file][previous][0] not in ("{", "}", ";"):
                previous -= 1
            if [r[0] for r in rows[file][previous + 1:decl]] != ["private"]:
                raise GateFailure("CONTROL_ACTOR_CONTRACT")
        if digest(rows[file][decl:end + 1]) != entry["sha256"]:
            reason = "SNAPSHOT_BOUND_CONTRACT" if key == "acquire" else (
                "SNAPSHOT_WAIT_CONTRACT" if key == "snapshot" else "SNAPSHOT_CALLER_CONTRACT")
            raise GateFailure(reason)


def inventory():
    result = subprocess.run(["git", "-C", str(ROOT), "grep", "-l", "-E",
        "MacSpeechNativeVoiceTiming|nativeVoiceTimingSnapshot|acquireSnapshotAccess", "--", "apps/macos/*.swift"],
        capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise OSError("Caller inventory unavailable")
    if set(result.stdout.splitlines()) != {"apps/macos/Aftelle/MacSpeechAudioCapture.swift",
                                         "apps/macos/Aftelle/AppController.swift"}:
        raise GateFailure("UNREVIEWED_PRODUCTION_CALLER_FILE")


def main(paths):
    try:
        source = [path.read_text() for path in paths]
        inventory()
        validate(*source)
    except (OSError, UnicodeError):
        print("aec_timer_gate=ERROR reason=READBACK_UNAVAILABLE")
        return 2
    except GateFailure as error:
        print("aec_timer_gate=FAIL reason=" + str(error))
        return 1
    print("aec_timer_gate=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main([Path(p) for p in sys.argv[1:]]))
