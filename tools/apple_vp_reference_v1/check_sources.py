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
    permitted = allowed | {"AppKit"} if source.name == "VPBPrompt.swift" else allowed
    assert set(imports) <= permitted, (source.name, imports)
    assert not re.search(
        r"AudioObjectSetPropertyData|AudioUnitSetProperty|VoiceActivityDetection|"
        r"WebRTC|RuntimeCore|NativeSpeechProvider|ProviderAdapter|Aftelle", text
    ), source.name
tap = (root / "Sources/VPReferenceAudio/NativePCMTap.swift").read_text()
assert "vp_recorder_submit" in tap and "recorder: RecorderOwner" in tap
assert not re.search(r"Data\(|Array\(|Task\s*\{|async|\.write\(|JSON|SHA|FFT|\.sync|\.lock\(", tap)
entry = (root / "Sources/VPReferenceAudio/ReferenceTool.swift").read_text()
assert entry.count("VP0AudioSession()") == 2
assert "case .record(let configuration):\n                let outcome = try VP0AudioSession().run" in entry
assert "case .vpa(let request):" in entry and "session.runVPA(request: request)" in entry
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
assert "guard route.hasVerifiedBinding" in session
assert "manifest.runningRoute = route" in session
assert "addObserver" not in session
probe = (root / "Sources/VPReferenceAudio/SourceProbe.swift").read_text()
assert entry.count("SourceProbe()") == 1 and "case .sourceProbe" in entry
assert probe.index("request.validate()") < probe.index("requireAuthorized") < probe.index("AppleEngineDriver(")
assert "SourceProbeRegistrationFile.load" in probe and "SourceProbeRoutePolicy.validate" in probe
assert "maximumSeconds: SourceProbeRequest.maximumSeconds" in probe
assert "SourceProbeWindow.capture" in probe and probe.count("recorder.seal()") == 1
assert not re.search(r"\.play\(|schedulePlayback|PCMSourceMaterial|requestAccess|requestExplicitly", probe)
evidence = (root / "Sources/VPReferenceAudio/SourceProbeEvidence.swift").read_text()
assert 'sourceStatus = "SOURCE_UNVERIFIED"' in evidence and "sourceQualificationGranted = false" in evidence
assert "USB_SOURCE_CONFIRMED" not in probe + evidence
probe_window = (root / "Sources/VPReferenceCore/SourceProbeWindow.swift").read_text()
assert "play: {}" in probe_window and "0..<162" in probe_window
assert "probeStimulusWindowMissed" in probe_window and "let observed = elapsedSeconds()" in probe_window
observer_source = (root / "Sources/VPReferenceAudio/ConfigurationChangeObserver.swift").read_text()
assert observer_source.count("center.addObserver") == 1
callback = observer_source.split("{ _ in", 1)[1].split("}", 1)[0]
assert "vp_recorder_invalidate" in callback
assert not re.search(r"Data\(|Array\(|Task\s*\{|\.write\(|JSON|SHA|FFT|\.sync|\.lock\(", callback)
manifest = (root / "Package.swift").read_text()
assert "dependencies: [" in manifest and ".package(" not in manifest
assert not any(name in manifest for name in [".iOS", ".visionOS", ".watchOS", ".tvOS"])
assert session.index("try request.validate()") < session.index("requireAuthorized")
assert "if let admission" in session and "VPAWindow.capture" in session
assert "maximumSeconds: vpa == nil ? 60 : VPARequest.maximumSeconds" in session
assert session.count("driver.player.play()") == 2
echo_evidence = (root / "Sources/VPReferenceAudio/VPAEvidence.swift").read_text()
assert 'sourceStatus = "SOURCE_UNVERIFIED"' in echo_evidence
assert "sourceQualificationGranted = false" in echo_evidence
echo_window = (root / "Sources/VPReferenceCore/VPAWindow.swift").read_text()
assert "PlaybackLifecycle.run" in echo_window and "0..<322" in echo_window
assert "maximumObservationSeconds" in echo_window
near_end = (root / "Sources/VPReferenceAudio/VPBSession.swift").read_text()
assert near_end.index('preflight.validate') < near_end.index('requireAuthorized') < near_end.index('AppleEngineDriver(')
assert not re.search(r"\.play\(|schedulePlayback|PCMSourceMaterial|requestAccess|requestExplicitly", near_end)
assert 'SourceProbeRoutePolicy.validate(route)' in near_end and '!route.hasVerifiedBinding' in near_end
assert near_end.count('recorder.seal()') == 1
near_evidence = (root / "Sources/VPReferenceAudio/VPBEvidence.swift").read_text()
assert 'sourceQualificationGranted = false' in near_evidence and 'researchResult = VPBResearchResult.unverified' in near_evidence
assert near_end.count('removeTap(onBus: 0)') == 2 and near_end.count('driver.engine.stop()') == 1
print("PASS: SDK-only sources, isolated unknown-source probe, fail-closed playback, bounded tap entry")
