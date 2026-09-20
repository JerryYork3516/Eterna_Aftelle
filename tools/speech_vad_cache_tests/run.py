"""Run cached HAL state regressions without accessing audio devices."""
from pathlib import Path
import argparse
import json
import subprocess

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, default=REPO / ".build/speech-vad-cache-tests")
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)

source = (REPO / "apps/macos/Aftelle/MacSpeechDeviceMonitor.swift").read_text()
# Compile the production state machine with only its HAL I/O substituted.
source = source[:source.index("nonisolated final class SystemMacSpeechDeviceMonitor:")]
source = source.replace("    private func refreshState() {", "    func auditRefreshForTesting() { refreshState() }\n\n    private func refreshState() {", 1)
source = source.replace("AudioObjectAddPropertyListenerBlock(", "auditAddListener(", 1)
source = source.replace("AudioObjectRemovePropertyListenerBlock(", "auditRemoveListener(", 1)
start = source.index("    private static func defaultInputDevice()")
source = source[:start] + """
    private static func defaultInputDevice() -> AudioDeviceID? { FakeHAL.device }
    private static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }
    private static func hasProperty(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> Bool { FakeHAL.supported }
    private static func uint32Property(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> UInt32? {
        selector == kAudioDevicePropertyVoiceActivityDetectionState ? FakeHAL.readState() : FakeHAL.enabled
    }
    private static func setUInt32Property(_ value: UInt32, selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> Bool {
        if FakeHAL.setSuccess { FakeHAL.enabled = value }
        return FakeHAL.setSuccess
    }
}
"""
# Capture references the route monitor type but the tests never instantiate it.
original = (REPO / "apps/macos/Aftelle/MacSpeechDeviceMonitor.swift").read_text()
source += original[original.index("nonisolated final class SystemMacSpeechDeviceMonitor:"):]
device = output / "Device-test-seam.swift"
device.write_text(source)
command = ["xcrun", "swiftc", "-O", "-D", "DEBUG", "-parse-as-library",
           "-module-cache-path", str(output / "module-cache"), str(device),
           str(REPO / "apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"),
           str(REPO / "apps/macos/Aftelle/MacSpeechAudioCapture.swift"),
           str(ROOT / "FakeHAL.swift"), str(ROOT / "VADCacheTests.swift"),
           "-o", str(output / "vad-cache-tests")]
subprocess.run(command, check=True)
subprocess.run([str(output / "vad-cache-tests"), str(output / "results.json")], check=True)
result = json.loads((output / "results.json").read_text())
assert result["passed"] == 18 and result["failed"] == 0
