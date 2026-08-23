#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_mode="${1:-r823-full}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r823-freeze.XXXXXX")"
fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
test_source="$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift"

worktree_fingerprint() {
  {
    git -C "$repo_root" diff --binary --no-ext-diff HEAD
    while IFS= read -r -d '' untracked; do
      printf '%s\0' "$untracked"
      shasum -a 256 "$repo_root/$untracked"
    done < <(git -C "$repo_root" ls-files --others --exclude-standard -z)
  } | shasum -a 256 | awk '{print $1}'
}

status_before="$(git -C "$repo_root" status --porcelain=v1)"
worktree_fingerprint_before="$(worktree_fingerprint)"
head_before="$(git -C "$repo_root" rev-parse HEAD)"
branch_before="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || true)"
trap 'rm -rf "$build_dir"' EXIT

if [ "$test_mode" != "r823-full" ] \
    && [ "$test_mode" != "r831-positive-only" ]; then
  echo "unsupported test mode: $test_mode" >&2
  exit 2
fi

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
  "$test_source" \
  -o "$build_dir/realtime_resident_only_zero_self_interrupt_tests"

output="$build_dir/output.log"
runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
runner_arguments=("$fixture")
if [ "$test_mode" = "r831-positive-only" ]; then
  runner_arguments+=("--r831-positive-only")
fi
CFFIXED_USER_HOME="$runtime_home" \
  /usr/bin/perl -e '$seconds = shift; alarm $seconds; exec @ARGV' \
  120 "$build_dir/realtime_resident_only_zero_self_interrupt_tests" \
  "${runner_arguments[@]}" \
  | tee "$output"

if [ "$test_mode" = "r831-positive-only" ]; then
  rg -qx 'realtime_true_near_end_opening_cases=1' "$output"
  rg -qx 'realtime_true_near_end_opening_checks=29' "$output"
  rg -qx 'r831_positive_control_acoustic_eligibility=1' "$output"
  rg -qx 'r831_runtime_near_end_observations=1' "$output"
  rg -qx 'r831_runtime_acoustic_evidence=1' "$output"
  rg -qx 'r831_confirmed_interruptions=0' "$output"
  rg -qx 'r831_provider_interrupts=0' "$output"
  rg -qx 'r831_provider_cancels=0' "$output"
  rg -qx 'r831_host_playback_clears=0' "$output"
  rg -qx 'r831_generation_changes=0' "$output"
  rg -qx 'r831_lease_changes=0' "$output"
  rg -qx 'r831_false_history_writes=0' "$output"
  rg -qx 'r831_false_memory_writes=0' "$output"
  rg -qx 'r831_relationship_changes=0' "$output"

  positive_source="$({
    awk '/private static func testPositiveNearEndControl/ { active = 1 }
         /private static func submitSemanticProposal/ { active = 0 }
         active' "$test_source"
    awk '/private static func submitTrueNearEndThroughProductionChain/ { active = 1 }
         /private enum ResidentOnlyMixer/ { active = 0 }
         active' "$test_source"
  })"
  if rg -q \
      'RealtimeAcousticObservation\(|MacSpeechResidentAcousticSnapshot\(|classification: \.nearEndCandidate|submitSemanticProposal|submitRealtimeResidentBrain(Acoustic|EligibleAcoustic)Evidence|capture\.emit\(0x' \
      <<< "$positive_source"; then
    echo "r831_manual_acoustic_injection=FAIL" >&2
    exit 1
  fi
  rg -q 'playbackStarted\(' <<< "$positive_source"
  rg -q 'processRender\(' <<< "$positive_source"
  rg -q 'processCapture\(' <<< "$positive_source"
  rg -q 'processedSamples: processed' <<< "$positive_source"
  rg -q 'outputConverter\.convert\(cleanedBuffer\)' "$test_source"
  echo "r831_production_chain_fixture=PASS"
else
  rg -qx 'realtime_resident_only_zero_self_interrupt_cases=12' "$output"
  rg -qx 'realtime_resident_only_zero_self_interrupt_checks=126' "$output"
  rg -qx 'resident_only_scenarios=6' "$output"
  rg -qx 'resident_only_eligible_evidence=0' "$output"
  rg -qx 'resident_only_confirmed_interruptions=0' "$output"
  rg -qx 'resident_only_provider_interrupts=0' "$output"
  rg -qx 'resident_only_provider_cancels=0' "$output"
  rg -qx 'resident_only_runtime_clear_decisions=0' "$output"
  rg -qx 'resident_only_host_playback_clears=0' "$output"
  rg -qx 'resident_only_generation_changes=0' "$output"
  rg -qx 'resident_only_lease_changes=0' "$output"
  rg -qx 'resident_only_false_turns=0' "$output"
  rg -qx 'resident_only_false_history_writes=0' "$output"
  rg -qx 'resident_only_false_memory_writes=0' "$output"
  rg -qx 'resident_only_relationship_changes=0' "$output"

  rg -qx 'r823_long_stress_observations=120' "$output"
  rg -qx 'r823_long_stress_frames=3840' "$output"
  rg -qx 'r823_long_stress_eligible=0' "$output"
  rg -qx 'r823_long_stress_confirmed=0' "$output"
  rg -qx 'r823_long_stress_provider_interrupts=0' "$output"
  rg -qx 'r823_long_stress_provider_cancels=0' "$output"
  rg -qx 'r823_long_stress_host_clears=0' "$output"

  rg -qx 'positive_control_eligible_evidence=1' "$output"
  rg -qx 'positive_control_runtime_observed=1' "$output"
  rg -qx 'positive_control_runtime_acoustic_evidence=1' "$output"
  rg -qx 'positive_control_confirmed_interruptions=0' "$output"
  rg -qx 'positive_control_provider_interrupts=0' "$output"
  rg -qx 'positive_control_provider_cancels=0' "$output"
  rg -qx 'positive_control_host_playback_clears=0' "$output"
  rg -qx 'positive_control_generation_changes=0' "$output"
  rg -qx 'positive_control_lease_changes=0' "$output"
  rg -qx 'positive_control_false_history_writes=0' "$output"
  rg -qx 'positive_control_false_memory_writes=0' "$output"
  rg -qx 'positive_control_relationship_changes=0' "$output"
fi

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

if awk '/private func consumeRealtimeResidentBrainAcousticObservation/ { active = 1 }
        /private func applyConfirmedRealtimeResidentBrainInterruption/ { active = 0 }
        active' "$controller" \
    | rg -q 'speechAudioOutputHost\.clear'; then
  echo "r823_consumer_clear_authority=FAIL" >&2
  exit 1
fi
echo "r823_consumer_clear_authority=PASS"

git -C "$repo_root" diff --check
status_after="$(git -C "$repo_root" status --porcelain=v1)"
worktree_fingerprint_after="$(worktree_fingerprint)"
head_after="$(git -C "$repo_root" rev-parse HEAD)"
branch_after="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || true)"
if [ "$status_before" != "$status_after" ] \
    || [ "$worktree_fingerprint_before" != "$worktree_fingerprint_after" ] \
    || [ "$head_before" != "$head_after" ] \
    || [ "$branch_before" != "$branch_after" ]; then
  echo "r823_repository_mutation=FAIL" >&2
  exit 1
fi
echo "r823_repository_mutation=PASS"
if [ "$test_mode" = "r831-positive-only" ]; then
  echo "realtime_true_near_end_opening=PASS"
else
  echo "realtime_resident_only_zero_self_interrupt_freeze=PASS"
fi
