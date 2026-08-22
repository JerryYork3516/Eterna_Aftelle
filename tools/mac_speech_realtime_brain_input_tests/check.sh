#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-realtime-brain-input-bridge.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
host_sources=(
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainOutputBridge.swift"
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

AFTELLE_R7_FIXTURE="$fixture" \
  "$build_dir/mac_speech_realtime_brain_input_tests"

bridge="$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
output_bridge="$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainOutputBridge.swift"
host="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
models="$repo_root/apps/macos/Aftelle/AppModels.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

rg -q 'maxCount: MacSpeechAudioInputFormat.frameCapacity' "$bridge"
rg -q 'provenance: \.acousticEchoProcessed' "$bridge"
echo "realtime_brain_input_bridge_conversion=PASS"

if rg -q 'Qwen|ProviderRouter|ExecutionEngine' "$bridge" "$output_bridge"; then
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

rg -q 'startRealtimeResidentBrainSession' "$models"
rg -q 'receiveRealtimeResidentBrainEvent' "$models" "$output_bridge"
rg -q 'startRealtimeResidentBrainRoute' "$controller"
rg -q 'residentAudioDelta' "$controller"
rg -q 'speechAudioOutputHost\.enqueue' "$controller"
echo "realtime_brain_formal_host_route=PASS"

rg -q 'submitRealtimeResidentBrainEligibleAcousticEvidence' \
  "$models" "$controller"
rg -q 'observation\.matchesCurrentPlayback\(currentAcousticSnapshot\)' \
  "$controller"
rg -q 'snapshot\.sourceGateOpen' "$bridge"
rg -q 'snapshot\.sourceGateEpoch == sourceGateEpoch' "$bridge"
rg -q 'claimRealtimeResidentBrainInterruptionDecision' "$models" "$controller"
if rg -q 'cancelRealtimeResidentBrainGeneration' "$models" "$controller"; then
  echo "realtime_brain_runtime_decision_authority=FAIL"
  exit 1
fi
rg -q 'suspendForGenerationTransition' "$bridge" "$output_bridge"
rg -q 'resumeAfterGenerationTransition' "$bridge" "$output_bridge"
rg -q 'realtimeBrainRouteAttemptID' "$controller"
echo "realtime_brain_generation_rebind=PASS"

rg -q 'pendingCloseBinding' "$bridge"
rg -q 'finishedAudioResponseID' "$output_bridge"
rg -q 'expectedAttemptID' "$controller"
rg -q 'realtimeBrainGenerationTransitionID == nil' "$controller"
rg -q 'let generationTransitionTask =' "$controller"
rg -q 'waitForRealtimeBrainPlaybackDrain' "$controller"
rg -q 'resumeRealtimeBrainPlaybackDrainWaiter' "$controller"
rg -q 'realtimeBrainPlaybackProviderFinishedResponseID' "$controller"
rg -q 'CheckedContinuation<Bool, Never>' "$controller"
rg -q 'formalRouteSnapshot.generation != nil' \
  "$repo_root/apps/macos/Aftelle/ContentView.swift"
rg -Fq 'generation: realtimeBrainInputBinding?.session.generation' \
  "$controller"
echo "realtime_brain_stop_late_audio_fence=PASS"

rg -q 'MacSpeechRealtimeBrainInputBridge.swift in Sources' "$project"
rg -q 'MacSpeechRealtimeBrainOutputBridge.swift in Sources' "$project"
echo "realtime_brain_input_bridge_target_membership=PASS"

if rg -q 'URLSession|WebSocket|network' "$bridge" "$output_bridge"; then
  echo "realtime_brain_input_bridge_no_sync_network=FAIL"
  exit 1
fi
echo "realtime_brain_input_bridge_no_sync_network=PASS"
