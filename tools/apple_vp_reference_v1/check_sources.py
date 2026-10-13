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
manifest = (root / "Package.swift").read_text()
assert "dependencies: [" in manifest and ".package(" not in manifest
assert not any(name in manifest for name in [".iOS", ".visionOS", ".watchOS", ".tvOS"])
print("PASS: independent SDK-only sources, explicit live branch, bounded tap entry")
