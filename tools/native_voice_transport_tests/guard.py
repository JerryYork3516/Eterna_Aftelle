#!/usr/bin/env python3
"""P1 realtime constraints plus the exact P2 graph membership. No audio or device access."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FROZEN = "574fc735ca239c9b334029debbdee546cda18d49"
P1 = "5ef549f634a0cb75eaca6e49c0a903214261119a"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


header = "apps/macos/Aftelle/Aftelle-Bridging-Header.h"
project = "apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"
compile_files = [line for line in git("ls-tree", "-r", "--name-only", FROZEN, "apps").decode().splitlines()
                 if line not in {header, project}]
for name in compile_files:
    assert (ROOT / name).read_bytes() == git("show", FROZEN + ":" + name), name

assert (ROOT / header).read_bytes() == git("show", FROZEN + ":" + header) + (
    b'#include "../NativeVoiceTransport/NativeVoiceRing.h"\n'
    b'#include "../NativeVoiceTransport/NativeVoiceRealtime.h"\n'
)
p2 = ["AppleNativeVoiceTransport.swift", "NativeVoiceGraph.swift", "NativeVoiceSessionGraph.swift",
      "NativeVoiceHALRoute.swift", "NativeVoiceSystemEngine.swift", "NativeVoiceRealtime.c", "NativeVoiceRealtimeLease.mm"]
project_lines = (ROOT / project).read_bytes().splitlines(keepends=True)
members = [line for line in project_lines if re.match(rb"\s*A07B120000000000000000[01][1-7] ", line)]
assert b"".join(line for line in project_lines if line not in members) == git("show", P1 + ":" + project)
assert len(members) == 4 * len(p2)
for ordinal, name in enumerate(p2, 1):
    encoded = name.encode()
    ref = ("A07B1200000000000000001" + str(ordinal)).encode()
    build = ("A07B1200000000000000000" + str(ordinal)).encode()
    assert sum(line.lstrip().startswith(ref + b" /* " + encoded + b" */") for line in members) == 2
    assert sum(line.lstrip().startswith(build + b" /* " + encoded + b" in Sources */") for line in members) == 2
    assert sum(b"path = ../NativeVoiceTransport/" + encoded + b"; sourceTree = SOURCE_ROOT;" in line
               for line in members) == 1
assert any(b"NativeVoiceRealtime.c in Sources" in line and b'-std=c11' in line for line in members)

sources = ROOT / "apps/macos/NativeVoiceTransport"
p1 = ("AppleNativeVoiceTransportWorker.swift", "NativeVoiceClock.swift", "NativeVoiceStreamingSRC.swift")
kernels = "\n".join((sources / f).read_text() for f in p1)
assert kernels.count("AVAudioConverter(from:") == 1
devices = ("AVAudioEngine", "AVAudioSourceNode", "AVAudioSinkNode", "AVCaptureDevice")
for forbidden in (*devices, "URLSession", "import RuntimeCore", "Task {", "DispatchQueue("):
    assert forbidden not in kernels, forbidden

for name in compile_files:
    if name.endswith(".swift"):
        text = (ROOT / name).read_text()
        assert not re.search(r"\b(AppleNativeVoiceTransport(?:Worker)?|NativeVoiceSystemEngine|NVTRTLease|nvt_rt_\w+|nvt_ring_\w+)\b",
                             text), name
swift = "\n".join(p.read_text() for p in sources.glob("*.swift"))
for forbidden in ("URLSession", "import RuntimeCore", "installTap(", "AVAudioPlayerNode", "WebRTCAEC"):
    assert forbidden not in swift, forbidden
for name in p2:
    if name.endswith(".swift") and name != "NativeVoiceSystemEngine.swift":
        assert not any(symbol in (sources / name).read_text() for symbol in devices), name

engine = (sources / "NativeVoiceSystemEngine.swift").read_text()
assert swift.count("AVAudioEngine()") == 1
for contract in ("setVoiceProcessingEnabled(true)", "isVoiceProcessingAGCEnabled = true",
                 "isVoiceProcessingBypassed = false", "isAutoShutdownEnabled = false",
                 "nvt_negotiate_voice_output(", "nvt_connect_voice_graph("):
    assert engine.count(contract) == 1, contract
assert "capture.isEqual(render)" in engine and "proposed.isEqual(input)" in engine
assert "SystemMacSpeechDeviceMonitor" not in swift
bridge = (sources / "NativeVoiceRealtimeLease.mm").read_text()
for contract in ("initWithReceiverBlock:", "initWithFormat:format renderBlock:",
                 "connect:engine.inputNode to:sink format:capture",
                 "connect:source to:engine.mainMixerNode format:sourceFormat",
                 "connect:engine.mainMixerNode to:engine.outputNode format:capture"):
    assert bridge.count(contract) == 1, contract

ring = (sources / "NativeVoiceRing.c").read_text()
io = (sources / "NativeVoiceRealtime.c").read_text()
realtime = ring[ring.index("static NVTWriteStatus write_frames"):] + io[io.index("static bool has_float_frames"):]
for forbidden in ("malloc(", "calloc(", "free(", "pthread_", "printf(", "sleep(", "dispatch_",
                  "fopen(", "AudioObject", "AVAudio"):
    assert forbidden not in realtime, forbidden

print("native_voice_frozen_existing_app_files=" + str(len(compile_files)))
print("native_voice_production_switches=0")
print("native_voice_p2_graph_members=7")
print("native_voice_isolation_guard=PASS")
