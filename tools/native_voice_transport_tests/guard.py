#!/usr/bin/env python3
"""P1 isolation fence. Read-only: no devices, audio assets or provider access."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FROZEN = "574fc735ca239c9b334029debbdee546cda18d49"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


allowed = {"apps/macos/Aftelle/Aftelle-Bridging-Header.h",
           "apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"}
files = git("ls-tree", "-r", "--name-only", FROZEN, "apps").decode().splitlines()
for name in files:
    if name in allowed:
        continue
    assert (ROOT / name).read_bytes() == git("show", FROZEN + ":" + name), name

header = "apps/macos/Aftelle/Aftelle-Bridging-Header.h"
assert (ROOT / header).read_bytes() == git("show", FROZEN + ":" + header) + b'#include "../NativeVoiceTransport/NativeVoiceRing.h"\n'
project = "apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"
assert git("diff", "--numstat", FROZEN, "--", project).decode().split()[:2] == ["16", "0"]

sources = ROOT / "apps/macos/NativeVoiceTransport"
swift = "\n".join(p.read_text() for p in sources.glob("*.swift"))
assert swift.count("AVAudioConverter(from:") == 1
for forbidden in ("AVAudioEngine", "AVAudioSourceNode", "AVAudioSinkNode", "AVCaptureDevice",
                  "URLSession", "import RuntimeCore", "Task {", "DispatchQueue("):
    assert forbidden not in swift, forbidden
for path in (ROOT / "apps/macos/Aftelle").glob("*.swift"):
    text = path.read_text()
    assert "AppleNativeVoiceTransportWorker" not in text and "nvt_ring_" not in text, str(path)

ring = (sources / "NativeVoiceRing.c").read_text()
realtime = ring[ring.index("NVTWriteStatus nvt_ring_write"):]
for forbidden in ("malloc(", "calloc(", "free(", "pthread_", "printf(", "sleep("):
    assert forbidden not in realtime, forbidden
print("native_voice_frozen_existing_app_files=" + str(len(files) - len(allowed)))
print("native_voice_production_switches=0")
print("native_voice_isolation_guard=PASS")
