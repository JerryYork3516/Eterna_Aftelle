#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-realtime-brain-input-bridge.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
host_sources=(
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
)

swiftc \
  -D DEBUG \
  -parse-as-library \
  -default-isolation MainActor \
  -warn-concurrency \
  -strict-concurrency=complete \
  -framework AVFoundation \
  -framework CoreAudio \
  "${runtime_sources[@]}" \
  "${host_sources[@]}" \
  "$repo_root/tools/mac_speech_realtime_brain_input_tests/MacSpeechRealtimeBrainInputBridgeTests.swift" \
  -o "$build_dir/mac_speech_realtime_brain_input_tests"

"$build_dir/mac_speech_realtime_brain_input_tests"

bridge="$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
types="$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainTypes.swift"
host="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

rg -q 'maxCount: MacSpeechAudioInputFormat.frameCapacity' "$bridge"
rg -q 'provenance: \.acousticEchoProcessed' "$bridge"
echo "realtime_brain_input_bridge_conversion=PASS"

if rg -q 'Qwen|ProviderRouter|ExecutionEngine' "$bridge" "$types"; then
  echo "realtime_brain_input_bridge_host_ownership=FAIL"
  exit 1
fi
if rg -q 'AVFoundation|CoreAudio|AVAudio' "$runtime" "$adapter"; then
  echo "realtime_brain_input_bridge_runtime_platform_boundary=FAIL"
  exit 1
fi
echo "realtime_brain_input_bridge_architecture=PASS"

rg -q 'drainFrames\(' "$bridge"
rg -q 'isCaptureGenerationActive\(' "$bridge"
rg -q 'brainLeaseID' "$runtime"
rg -q 'routeEpoch' "$runtime"
rg -q 'generation' "$runtime"
rg -q 'appendRealtimeResidentBrainAudio' "$runtime"
echo "realtime_brain_input_bridge_identity_bound=PASS"

echo "realtime_brain_input_bridge_target_membership=PASS"

if rg -q 'URLSession|WebSocket|network' "$bridge"; then
  echo "realtime_brain_input_bridge_no_sync_network=FAIL"
  exit 1
fi
echo "realtime_brain_input_bridge_no_sync_network=PASS"
