#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r81-evidence.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
host_sources=(
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleTuning.swift"
  "$repo_root/apps/macos/Aftelle/ParticleCore/ResidentVisualIntent.swift"
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleStateController.swift"
  "$repo_root/apps/macos/Aftelle/AppModels.swift"
  "$repo_root/apps/macos/Aftelle/ProviderKeychainStore.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainOutputBridge.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechNativeInputBridge.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechNativeOutputBridge.swift"
  "$repo_root/apps/macos/Aftelle/RealtimeSpeechPresentationMapper.swift"
  "$repo_root/apps/macos/Aftelle/AppController.swift"
  "$repo_root/tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift"
)

swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  -framework AVFoundation \
  -framework CoreAudio \
  -framework AppKit \
  -framework Security \
  -framework UniformTypeIdentifiers \
  "${runtime_sources[@]}" \
  "${host_sources[@]}" \
  "$repo_root/tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift" \
  -o "$build_dir/realtime_interruption_evidence_tests"

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/realtime_interruption_evidence_tests" "$fixture"

contract="$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
models="$repo_root/apps/macos/Aftelle/AppModels.swift"

rg -q 'RealtimeInterruptionEvidenceIdentity' "$contract"
rg -q 'isActiveInterruptionTarget' "$contract" "$runtime"
rg -q 'submitRealtimeResidentBrainAcousticEvidence' "$runtime"
rg -q 'submitRealtimeResidentBrainAcousticEvidence' "$models"
rg -q 'submitRealtimeResidentBrainAcousticEvidence' "$controller"
rg -q 'claimRealtimeResidentBrainInterruptionDecision' "$runtime"
rg -q 'claimRealtimeResidentBrainInterruptionDecision' "$models"
rg -q 'claimRealtimeResidentBrainInterruptionDecision' "$controller"
rg -q 'completeRealtimeResidentBrainInterruption' "$runtime"
rg -q 'completeRealtimeResidentBrainInterruption' "$models"
rg -q 'completeRealtimeResidentBrainInterruption' "$controller"
echo "realtime_interruption_evidence_identity_fence=PASS"

if rg -q 'cancelRealtimeResidentBrainGeneration|interruptRealtimeResidentBrain' \
  "$models" "$controller"; then
  echo "realtime_interruption_runtime_authority=FAIL"
  exit 1
fi
if rg -q 'source: \.realtimeBrain' "$controller"; then
  echo "realtime_interruption_host_execution_only=FAIL"
  exit 1
fi
awk \
  '/private func applyConfirmedRealtimeResidentBrainInterruption/ { active = 1 } /private func stopRealtimeResidentBrainRoute/ { active = 0 } active' \
  "$controller" | rg -q 'speechAudioOutputHost.clear'
awk \
  '/private func applyConfirmedRealtimeResidentBrainInterruption/ { active = 1 } /private func stopRealtimeResidentBrainRoute/ { active = 0 } active' \
  "$controller" | rg -q 'completeRealtimeResidentBrainInterruption'
echo "realtime_interruption_host_execution_only=PASS"

rg -q '"interrupt_response": false' "$adapter"
rg -q '"create_response": false' "$adapter"
rg -q 'reconnect: false' "$adapter"
rg -q 'throw RealtimeResidentBrainError.invalidEvent' "$adapter"
echo "realtime_interruption_qwen_proposal_only=PASS"
