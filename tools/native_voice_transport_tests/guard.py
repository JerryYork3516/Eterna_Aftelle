#!/usr/bin/env python3
"""P1/P2 realtime constraints and the bounded P3/P4 host integration surface."""
from pathlib import Path
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FROZEN = "574fc735ca239c9b334029debbdee546cda18d49"
P1 = "5ef549f634a0cb75eaca6e49c0a903214261119a"
P3_BASE = "8d4d2a6cbc1566dacba5229826bf98adac9b00c9"
P4_BASE = "b1dedd8b02680eb5bfa4c676421cd0da421e1afe"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"})


header = "apps/macos/Aftelle/Aftelle-Bridging-Header.h"
project = "apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"
app = "apps/macos/Aftelle/"
candidate = app + "MacSpeechNativeRealtimeSession.swift"
facts = app + "MacSpeechNativeRealtimeFacts.swift"
p3 = (ROOT / candidate).is_file()
integration = {app + name for name in (
    "AppController.swift", "MacSpeechRealtimeBrainInputBridge.swift", "MacSpeechAudioOutputHost.swift",
)} if p3 else set()
compile_files = [line for line in git("ls-tree", "-r", "--name-only", FROZEN, "apps").decode().splitlines()
                 if line not in {header, project}]
for name in compile_files:
    if name not in integration:
        assert (ROOT / name).read_bytes() == git("show", FROZEN + ":" + name), name

if p3:
    p4_transport = {
        "apps/macos/NativeVoiceTransport/" + name for name in (
            "NativeVoiceRing.h", "NativeVoiceRealtime.c", "NativeVoiceRealtime.h", "NativeVoiceGraph.swift",
            "NativeVoiceSystemEngine.swift", "NativeVoiceSessionGraph.swift", "AppleNativeVoiceTransport.swift",
            "AppleNativeVoiceTransportWorker.swift",
        )
    }
    changed = set(git("diff", "--name-only", P3_BASE, "--", "apps").decode().splitlines())
    changed.update(git("ls-files", "--others", "--exclude-standard", "--", "apps").decode().splitlines())
    permitted = {candidate, facts, project} | integration | p4_transport | {
        "apps/macos/NativeVoiceTransport/" + name for name in (
            "AppleNativeVoiceTransport.swift", "NativeVoiceSessionGraph.swift", "NativeVoiceRealtime.c",
            "NativeVoiceRealtime.h", "NativeVoiceRealtimeLease.mm",
        )
    }
    assert changed <= permitted, changed - permitted
    p4_changed = set(git("diff", "--name-only", P4_BASE, "--", "apps").decode().splitlines())
    p4_changed.update(git("ls-files", "--others", "--exclude-standard", "--", "apps").decode().splitlines())
    p4_permitted = {candidate, facts, app + "AppController.swift",
                    app + "MacSpeechRealtimeBrainInputBridge.swift"} | p4_transport
    assert p4_changed <= p4_permitted, p4_changed - p4_permitted
    assert (ROOT / project).read_bytes() == git("show", P4_BASE + ":" + project)
    controller = (ROOT / (app + "AppController.swift")).read_text()
    frozen_controller = git("show", FROZEN + ":" + app + "AppController.swift").decode()
    shipped_initializer = "    init() {"
    shipped = controller.split(shipped_initializer)[1].split("    init(", 1)[0]
    frozen = frozen_controller.split(shipped_initializer)[1].split("    init(", 1)[0]
    release_start = "        #else\n            let credentialStore = ProviderKeychainStore()"
    assert shipped.split(release_start, 1)[1] == frozen.split(release_start, 1)[1]
    assert shipped.split(release_start, 1)[0] == """
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let admission = AppleNativeVoiceDebugAdmission.resolve(
                arguments: arguments, deviceBuildAuthorized: AppleNativeVoiceDebugAdmission.deviceBuildAuthorized
            )
            nativeVoiceDebugAdmission = admission
            isAppleVPAcousticTestMode = admission == .off
                && AppleVPAcousticTestLaunchMode.isEnabled(arguments: arguments)
            #if APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED
                realtimeAudioBackend = admission.backend {
                    MacSpeechNativeRealtimeSession.appleVoiceProcessing()
                }
            #endif
"""
    assert controller.count("case .appleNativeCandidate") == 1
    assert controller.count("realtimeAudioBackend = MacSpeechRealtimeAudioBackend.frozen") == 1
    assert controller.count("self.realtimeAudioBackend = realtimeAudioBackend") == 2
    assert "AppleNativeVoiceTransport.macOS()" not in controller
    for required in (
        "await ensureRealtimeMicrophoneAuthorization()", "await speechAudioHost.prepareCaptureGeneration()",
        "prepared = await speechAudioOutputHost.prepare()", "clearedOutput = await speechAudioOutputHost.clear()",
        ".completeRealtimeResidentBrainInterruption(decision)",
    ):
        assert required in controller, required
    start = controller.split("    func startRealtimeResidentBrainRoute() async {", 1)[1].split(
        "    private func ensureRealtimeMicrophoneAuthorization", 1
    )[0]
    assert start.index("native_voice_candidate_not_authorized") < start.index(
        "await ensureRealtimeMicrophoneAuthorization()"
    ) < start.index(
        "await candidate.reserveCaptureGeneration()"
    ) < start.index(".startRealtimeResidentBrainInput()") < start.index("await candidate.startCapture(")
    output_host = app + "MacSpeechAudioOutputHost.swift"
    old_host = git("show", FROZEN + ":" + output_host)
    before = b"nonisolated struct MacSpeechAudioOutputEvent:"
    after = b"nonisolated struct MacSpeechAudioOutputHostSnapshot:"
    current_host = (ROOT / output_host).read_bytes()
    assert old_host.split(before)[0] == current_host.split(before)[0]
    assert old_host.split(after)[1] == current_host.split(after)[1]
    candidate_source = (ROOT / candidate).read_text()
    assert candidate_source.count("AppleNativeVoiceTransport.macOS()") == 1
    assert "isSourceHandoff: handoff" in candidate_source
    assert "renderClearAcknowledged" in candidate_source
    assert candidate_source.count("#if NATIVE_VOICE_P3_OFFLINE_TEST") == 1
    assert (ROOT / facts).read_text().count("#if NATIVE_VOICE_P3_OFFLINE_TEST") == 2
    assert b"NATIVE_VOICE_P3_OFFLINE_TEST" not in (ROOT / project).read_bytes()
    assert b"APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED" not in (ROOT / project).read_bytes()
    assert "#if APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED && (!DEBUG || NATIVE_VOICE_P3_OFFLINE_TEST)" in (
        ROOT / facts
    ).read_text()
    assert controller.count("MacSpeechNativeRealtimeSession.appleVoiceProcessing()") == 1
    assert "event.isSourceHandoff == (realtimeAudioBackend.candidate != nil)" in controller

assert (ROOT / header).read_bytes() == git("show", FROZEN + ":" + header) + (
    b'#include "../NativeVoiceTransport/NativeVoiceRing.h"\n'
    b'#include "../NativeVoiceTransport/NativeVoiceRealtime.h"\n'
)
p2 = ["AppleNativeVoiceTransport.swift", "NativeVoiceGraph.swift", "NativeVoiceSessionGraph.swift",
      "NativeVoiceHALRoute.swift", "NativeVoiceSystemEngine.swift", "NativeVoiceRealtime.c", "NativeVoiceRealtimeLease.mm"]
project_lines = (ROOT / project).read_bytes().splitlines(keepends=True)
if p3:
    p3_members = [line for line in project_lines if re.match(rb"\s*A07B130000000000000000[01][12] ", line)]
    assert len(p3_members) == 8
    for member in (candidate, facts):
        assert sum(Path(member).name.encode() in line for line in p3_members) == 4
    project_lines = [line for line in project_lines if line not in p3_members]
    assert b"".join(project_lines) == git("show", P3_BASE + ":" + project)
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

print("native_voice_frozen_existing_app_files=" + str(len(compile_files) - len(integration)))
if p3:
    print("native_voice_p3_integrated_legacy_files=3")
    print("native_voice_p4_debug_device_authorization=SEALED")
print("native_voice_production_switches=0")
print("native_voice_p2_graph_members=7")
print("native_voice_isolation_guard=PASS")
