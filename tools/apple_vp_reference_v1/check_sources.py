"""Static independence and callback guards; never opens an audio device."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
allowed = {
    "AVFoundation", "CoreAudio", "CryptoKit", "Darwin", "Foundation",
    "VPRecorder", "VPReferenceCore",
}
for source in (root / "Sources").rglob("*.swift"):
    text = source.read_text()
    imports = re.findall(r"^import (\w+)", text, re.MULTILINE)
    assert set(imports) <= allowed, (source.name, imports)
    assert not re.search(
        r"AudioObjectSetPropertyData|AudioUnitSetProperty|VoiceActivityDetection|"
        r"WebRTC|RuntimeCore|NativeSpeechProvider|ProviderAdapter|Aftelle", text
    ), source.name
tap = (root / "Sources/VPReferenceAudio/NativePCMTap.swift").read_text()
assert "vp_recorder_submit" in tap and "recorder: RecorderOwner" in tap
assert not re.search(r"Data\(|Array\(|Task\s*\{|async|\.write\(|JSON|SHA|FFT|\.sync|\.lock\(", tap)
entry = (root / "Sources/VPReferenceAudio/ReferenceTool.swift").read_text()
assert entry.count("VP0AudioSession()") == 1
assert entry.index("case .record") < entry.index("VP0AudioSession()")
assert entry.count("case .requestMicrophone") == 1
assert entry.count("requestExplicitly(") == 1
request_sources = [
    source.name for source in (root / "Sources").rglob("*.swift")
    if "AVCaptureDevice.requestAccess" in source.read_text()
]
assert request_sources == ["MicrophonePermissionAccess.swift"], request_sources
session = (root / "Sources/VPReferenceAudio/VP0AudioSession.swift").read_text()
assert "requestExplicitly" not in session and "requestAccess" not in session
assert session.index("requireAuthorized") < session.index("AppleEngineDriver(")
assert session.count("recorder.seal()") == 1
lifecycle = (root / "Sources/VPReferenceCore/PlaybackLifecycle.swift").read_text()
assert lifecycle.index("try startAndValidate()") < lifecycle.index("play()\n")
assert lifecycle.index("observer?.register()") < lifecycle.index("try startAndValidate()")
assert lifecycle.index("observer?.remove()") < lifecycle.index("stop()\n")
assert lifecycle.index("try observer?.check()", lifecycle.index("try startAndValidate()")) < lifecycle.index("play()\n")
assert "observer: observer" in session
inspection = (root / "Sources/VPReferenceAudio/RouteInspection.swift").read_text()
assert inspection.index("requireAuthorized") < inspection.index("AppleEngineDriver(")
assert not re.search(r"\.start\(|\.prepare\(|\.play\(|installTaps|NativePCMTap|RecorderOwner|requestAccess", inspection)
assert "addObserver" not in session
observer_source = (root / "Sources/VPReferenceAudio/ConfigurationChangeObserver.swift").read_text()
assert observer_source.count("center.addObserver") == 1
callback = observer_source.split("{ _ in", 1)[1].split("}", 1)[0]
assert "vp_recorder_invalidate" in callback
assert not re.search(r"Data\(|Array\(|Task\s*\{|\.write\(|JSON|SHA|FFT|\.sync|\.lock\(", callback)
manifest = (root / "Package.swift").read_text()
assert "dependencies: [" in manifest and ".package(" not in manifest
assert not any(name in manifest for name in [".iOS", ".visionOS", ".watchOS", ".tvOS"])
print("PASS: SDK-only sources, explicit permission/live branches, fail-closed playback, bounded tap entry")
