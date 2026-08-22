#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r823-freeze.XXXXXX")"
fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
status_before="$(git -C "$repo_root" status --porcelain=v1)"
trap 'rm -rf "$build_dir"' EXIT

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
  "$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift" \
  -o "$build_dir/realtime_resident_only_zero_self_interrupt_tests"

output="$build_dir/output.log"
runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  /usr/bin/perl -e '$seconds = shift; alarm $seconds; exec @ARGV' \
  120 "$build_dir/realtime_resident_only_zero_self_interrupt_tests" "$fixture" \
  | tee "$output"

rg -qx 'realtime_resident_only_zero_self_interrupt_cases=12' "$output"
rg -qx 'realtime_resident_only_zero_self_interrupt_checks=90' "$output"
rg -qx 'resident_only_scenarios=5' "$output"
rg -qx 'resident_only_eligible_evidence=0' "$output"
rg -qx 'resident_only_confirmed_interruptions=0' "$output"
rg -qx 'resident_only_provider_interrupts=0' "$output"
rg -qx 'resident_only_provider_cancels=0' "$output"
rg -qx 'resident_only_runtime_clear_decisions=0' "$output"
rg -qx 'resident_only_host_playback_clears=0' "$output"
rg -qx 'resident_only_generation_changes=0' "$output"
rg -qx 'resident_only_lease_changes=0' "$output"
rg -qx 'resident_only_false_turns=0' "$output"

rg -qx 'r823_long_stress_observations=120' "$output"
rg -qx 'r823_long_stress_frames=3840' "$output"
rg -qx 'r823_long_stress_eligible=0' "$output"
rg -qx 'r823_long_stress_confirmed=0' "$output"
rg -qx 'r823_long_stress_provider_interrupts=0' "$output"
rg -qx 'r823_long_stress_provider_cancels=0' "$output"
rg -qx 'r823_long_stress_host_clears=0' "$output"

rg -q 'positive_control_eligible_evidence=[1-9][0-9]*' "$output"
rg -qx 'positive_control_confirmed_interruptions=0' "$output"
rg -qx 'positive_control_provider_interrupts=0' "$output"

contract="$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
bridge="$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"

rg -q 'RealtimeAcousticInterruptionEligibilityGate' "$contract"
rg -q 'observationFreshnessNanoseconds: UInt64 = 500_000_000' "$contract"
rg -q 'residualTailWindowNanoseconds: UInt64 = 500_000_000' "$contract"

if rg -q 'submitRealtimeResidentBrainAcousticEvidence\(' "$runtime"; then
  echo "r823_raw_acoustic_bypass=FAIL" >&2
  exit 1
fi
rg -q 'submitRealtimeResidentBrainAcousticEvidenceForTesting' "$runtime"
if rg -q 'submitRealtimeResidentBrainAcousticEvidenceForTesting' \
  "$repo_root/apps/macos/Aftelle/AppModels.swift" \
  "$controller"; then
  echo "r823_host_raw_acoustic_bypass=FAIL" >&2
  exit 1
fi
rg -q 'submitRealtimeResidentBrainEligibleAcousticEvidence' \
  "$runtime" "$repo_root/apps/macos/Aftelle/AppModels.swift" "$controller"
rg -q 'consumeRealtimeResidentBrainAcousticObservation' "$controller"
rg -q 'matchesCurrentPlayback' "$bridge"
echo "r823_authority_chain=PASS"

if rg -q 'speechAudioOutputHost\.clear' \
  "$(awk '/private func consumeRealtimeResidentBrainAcousticObservation/ { active = 1 } /private func applyConfirmedRealtimeResidentBrainInterruption/ { active = 0 } active' "$controller")"; then
  echo "r823_consumer_clear_authority=FAIL" >&2
  exit 1
fi
echo "r823_consumer_clear_authority=PASS"

git -C "$repo_root" diff --check
status_after="$(git -C "$repo_root" status --porcelain=v1)"
if [ "$status_before" != "$status_after" ]; then
  echo "r823_repository_mutation=FAIL" >&2
  exit 1
fi
echo "r823_repository_mutation=PASS"
echo "realtime_resident_only_zero_self_interrupt_freeze=PASS"
