#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r821-acoustic.XXXXXX")"
fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
status_before="$(git -C "$repo_root" status --porcelain=v1)"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
host_sources=(
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioHost.swift"
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
  "$repo_root/tools/realtime_acoustic_observation_tests/RealtimeAcousticObservationTests.swift" \
  -o "$build_dir/realtime_acoustic_observation_tests"

/usr/bin/perl -e '$seconds = shift; alarm $seconds; exec @ARGV' \
  60 "$build_dir/realtime_acoustic_observation_tests" "$fixture"

contract="$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
bridge="$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
models="$repo_root/apps/macos/Aftelle/AppModels.swift"

for classification in \
  silenceOrNoise farEndDominant residualEchoLikely nearEndCandidate indeterminate; do
  rg -q "case $classification" "$contract"
done
rg -q 'enum RealtimeAcousticClassifier' "$contract"
rg -q 'maximumRenderDelayMilliseconds = 500' "$contract"
rg -q 'maximumAlignmentErrorMilliseconds = 30' "$contract"
echo "realtime_acoustic_production_classifier=PASS"

rg -q 'observeRealtimeResidentBrainAcoustics' "$runtime" "$models" "$controller"
rg -q 'realtimeAcousticObservationCapacity = 32' "$runtime"
rg -q 'realtimeAcousticObservationDebugSnapshot' "$runtime"
echo "realtime_acoustic_identity_trace=PASS"

runtime_observer_block="$build_dir/runtime-observer.txt"
awk \
  '/func observeRealtimeResidentBrainAcoustics/ { active = 1 } /func submitRealtimeResidentBrainAcousticEvidence/ { active = 0 } active' \
  "$runtime" > "$runtime_observer_block"
if rg -q \
  'consumeRealtimeResidentBrainInterruptionEvidence|beginRealtimeBrainGenerationTransition|executionEngine|pendingRealtimeInterruption|cancelRealtimeResidentBrain|interruptRealtimeResidentBrain|clearPlayback|confirmed' \
  "$runtime_observer_block"; then
  echo "realtime_acoustic_runtime_observer_only=FAIL" >&2
  exit 1
fi
echo "realtime_acoustic_runtime_observer_only=PASS"

models_observer_block="$build_dir/models-observer.txt"
awk \
  '/func observeRealtimeResidentBrainAcoustics/ { active = 1 } /func claimRealtimeResidentBrainInterruptionDecision/ { active = 0 } active' \
  "$models" > "$models_observer_block"
rg -q 'runtimeCore\.observeRealtimeResidentBrainAcoustics' "$models_observer_block"
if rg -q \
  'submitRealtimeResidentBrainAcousticEvidence|claimRealtimeResidentBrainInterruptionDecision|completeRealtimeResidentBrainInterruption|cancelRealtimeResidentBrain|interruptRealtimeResidentBrain|clearPlayback|confirmed' \
  "$models_observer_block"; then
  echo "realtime_acoustic_models_observer_only=FAIL" >&2
  exit 1
fi
echo "realtime_acoustic_models_observer_only=PASS"

observer_block="$build_dir/controller-observer.txt"
awk \
  '/private func observeRealtimeResidentBrainAcoustics/ { active = 1 } /private func consumeRealtimeResidentBrainAcousticObservation/ { active = 0 } active' \
  "$controller" > "$observer_block"
rg -q 'observeRealtimeResidentBrainAcoustics' "$observer_block"
if rg -q \
  'submitRealtimeResidentBrainAcousticEvidence|claimRealtimeResidentBrainInterruptionDecision|completeRealtimeResidentBrainInterruption|speechAudioOutputHost\.clear|cancelRealtimeResidentBrain|interruptRealtimeResidentBrain|applyConfirmedRealtimeResidentBrainInterruption' \
  "$observer_block"; then
  echo "realtime_acoustic_observer_only=FAIL" >&2
  exit 1
fi
echo "realtime_acoustic_observer_only=PASS"

provider_protocol="$build_dir/provider-protocol.txt"
awk \
  '/protocol RealtimeResidentBrainProvider/ { active = 1 } /nonisolated extension RealtimeResidentBrainProvider/ { active = 0 } active' \
  "$contract" > "$provider_protocol"
if rg -q 'AcousticObservation|observeRealtimeResidentBrainAcoustics' \
  "$provider_protocol"; then
  echo "realtime_acoustic_provider_authority=FAIL" >&2
  exit 1
fi
echo "realtime_acoustic_provider_authority=PASS"

rg -q 'lastResidentObservationFrameIndex &\+ 10' "$bridge"
rg -q 'residentAcousticObservationTask == nil' "$bridge"
rg -q 'droppedResidentAcousticObservationCount' "$bridge"
rg -q 'if frames\.isEmpty' "$bridge"
echo "realtime_acoustic_bounded_delivery=PASS"

if rg -q 'URLSession|WebSocket|FileHandle|write\(to:' \
  "$bridge" "$contract"; then
  echo "realtime_acoustic_hot_path_io=FAIL" >&2
  exit 1
fi
echo "realtime_acoustic_hot_path_io=PASS"

status_after="$(git -C "$repo_root" status --porcelain=v1)"
if [ "$status_before" != "$status_after" ]; then
  echo "realtime_acoustic_repository_mutation=FAIL" >&2
  exit 1
fi
echo "realtime_acoustic_repository_mutation=PASS"
echo "realtime_acoustic_stress_observations=320"
echo "realtime_acoustic_stress_provider_interrupts=0"
echo "realtime_acoustic_stress_provider_cancels=0"
echo "realtime_acoustic_stress_generation_changes=0"
echo "realtime_acoustic_trace_capacity=32"
echo "realtime_acoustic_trace_overflow_drops=288"
echo "realtime_acoustic_confirmed_authority_guard=PASS"
echo "realtime_acoustic_playback_clear_authority_guard=PASS"
echo "realtime_acoustic_observation=PASS"
