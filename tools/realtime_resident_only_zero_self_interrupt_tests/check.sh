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
    && [ "$test_mode" != "r831-positive-only" ] \
    && [ "$test_mode" != "r832-confirmed-only" ] \
    && [ "$test_mode" != "r833-latency-stale-only" ]; then
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
elif [ "$test_mode" = "r832-confirmed-only" ]; then
  runner_arguments+=("--r832-confirmed-only")
elif [ "$test_mode" = "r833-latency-stale-only" ]; then
  runner_arguments+=("--r833-latency-stale-only")
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
         /private static func submitPostInterruptionInputThroughProductionChain/ { active = 0 }
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
elif [ "$test_mode" = "r832-confirmed-only" ]; then
  rg -qx 'realtime_confirmed_interruption_cases=1' "$output"
  rg -qx 'realtime_confirmed_interruption_checks=62' "$output"
  rg -qx 'r832_production_acoustic_eligibility=1' "$output"
  rg -qx 'r832_runtime_near_end_observations=1' "$output"
  rg -qx 'r832_runtime_acoustic_evidence=1' "$output"
  rg -qx 'r832_formal_semantic_evidence=1' "$output"
  rg -qx 'r832_confirmed_interruptions=1' "$output"
  rg -qx 'r832_provider_interrupts=1' "$output"
  rg -qx 'r832_provider_cancels=0' "$output"
  rg -qx 'r832_host_playback_clears=1' "$output"
  rg -qx 'r832_playback_generation_delta=1' "$output"
  rg -qx 'r832_runtime_generation_delta=1' "$output"
  rg -qx 'r832_generation_before=1' "$output"
  rg -qx 'r832_generation_after=2' "$output"
  rg -qx 'r832_resident_id_changes=0' "$output"
  rg -qx 'r832_runtime_session_id_changes=0' "$output"
  rg -qx 'r832_brain_lease_id_changes=0' "$output"
  rg -qx 'r832_route_epoch_changes=0' "$output"
  rg -qx 'r832_provider_reopens=0' "$output"
  rg -qx 'r832_provider_closes=0' "$output"
  rg -qx 'r832_response_creates=0' "$output"
  rg -qx 'r832_input_bridge_rebound=1' "$output"
  rg -qx 'r832_output_bridge_rebound=1' "$output"
  rg -qx 'r832_route_listening=1' "$output"
  rg -qx 'r832_capture_persistent=1' "$output"
  rg -qx 'r832_injected_old_output_events_rejected=2' "$output"
  rg -qx 'r832_old_playback_callbacks_rejected=1' "$output"
  rg -qx 'r832_extra_interruptions=0' "$output"
  rg -qx 'r832_extra_playback_clears=0' "$output"
  rg -qx 'r832_false_user_turns=0' "$output"
  rg -qx 'r832_false_history_writes=0' "$output"
  rg -qx 'r832_false_memory_writes=0' "$output"
  rg -qx 'r832_relationship_changes=0' "$output"

  r832_case_source="$(
    awk '/private static func testR832ConfirmedInterruptionProductionChain/ { active = 1 }
         /private static func testPositiveNearEndControl/ { active = 0 }
         active' "$test_source"
  )"
  r832_semantic_source="$(
    awk '/private static func submitSemanticProposal/ { active = 1 }
         /private static func testHistoryMemorySafety/ { active = 0 }
         active' "$test_source"
  )"
  r832_acoustic_source="$(
    awk '/private static func submitTrueNearEndThroughProductionChain/ { active = 1 }
         /private static func submitPostInterruptionInputThroughProductionChain/ { active = 0 }
         active' "$test_source"
  )"
  r832_rebound_source="$(
    awk '/private static func submitPostInterruptionInputThroughProductionChain/ { active = 1 }
         /private enum ResidentOnlyMixer/ { active = 0 }
         active' "$test_source"
  )"
  r832_source="${r832_case_source}${r832_semantic_source}${r832_acoustic_source}${r832_rebound_source}"
  if rg -q \
      'RealtimeAcousticObservation\(|MacSpeechResidentAcousticSnapshot\(|RealtimeConfirmedInterruption\(|RealtimeBrain(Interrupt|CancelGeneration)Command\(|classification: \.nearEndCandidate|submitRealtimeResidentBrain(Acoustic|EligibleAcoustic)Evidence|consumeRealtimeResidentBrainInterruptionEvidence|receiveRealtimeResidentBrainEvent|claimRealtimeResidentBrainInterruptionDecision|completeRealtimeResidentBrainInterruption|cancelRealtimeResidentBrainGenerationForTesting|beginRealtimeBrainGenerationTransition|finishRealtimeBrainGenerationInterruption|speechAudioOutputHost\.clear\(|clearScheduledPlayback\(|provider\.(interrupt|cancelGeneration)\(|suspendForGenerationTransition|resumeAfterGenerationTransition|frameBuffer\.append\(|capture\.emit\(0x' \
      <<< "$r832_source"; then
    echo "r832_test_seam_bypass=FAIL" >&2
    exit 1
  fi
  rg -q 'submitTrueNearEndThroughProductionChain' <<< "$r832_source"
  rg -q 'submitPostInterruptionInputThroughProductionChain' \
    <<< "$r832_source"
  rg -q 'submitSemanticProposal\(stack: stack, sequence: 4\)' \
    <<< "$r832_case_source"
  rg -q 'await stack\.provider\.enqueue' <<< "$r832_semantic_source"
  rg -q 'kind: \.interruptionProposed' <<< "$r832_semantic_source"
  rg -q 'session: stack\.target\.session' <<< "$r832_semantic_source"
  rg -q 'turnID: stack\.target\.turnID' <<< "$r832_semantic_source"
  rg -q 'responseID: stack\.target\.responseID' <<< "$r832_semantic_source"
  rg -q 'contextRevision: stack\.target\.contextRevision' \
    <<< "$r832_semantic_source"
  rg -q 'reason: "user_speech_started_during_resident_response"' \
    <<< "$r832_semantic_source"
  rg -q 'playbackStarted\(' <<< "$r832_source"
  rg -q 'playbackStopped\(' <<< "$r832_rebound_source"
  rg -q 'processRender\(' <<< "$r832_source"
  rg -q 'processCapture\(' <<< "$r832_source"
  rg -q 'processedSamples: processed' <<< "$r832_source"
  rg -q 'outputConverter\.convert\(cleanedBuffer\)' "$test_source"
  echo "r832_production_chain_fixture=PASS"
elif [ "$test_mode" = "r833-latency-stale-only" ]; then
  rg -qx 'realtime_barge_in_latency_stale_cases=1' "$output"
  rg -qx 'realtime_barge_in_latency_stale_checks=68' "$output"
  first_to_eligibility_ns="$(
    awk -F= '/^r833_first_valid_near_end_to_acoustic_eligibility_ns=/ { print $2 }' "$output"
  )"
  confirmed_to_clear_ns="$(
    awk -F= '/^r833_confirmed_to_playback_clear_ns=/ { print $2 }' "$output"
  )"
  first_to_clear_ns="$(
    awk -F= '/^r833_first_valid_near_end_to_playback_clear_ns=/ { print $2 }' "$output"
  )"
  [ -n "$first_to_eligibility_ns" ]
  [ -n "$confirmed_to_clear_ns" ]
  [ -n "$first_to_clear_ns" ]
  [ "$confirmed_to_clear_ns" -le 50000000 ]
  [ "$first_to_clear_ns" -le 200000000 ]
  [ "$first_to_eligibility_ns" -le "$first_to_clear_ns" ]
  rg -qx 'r833_preclear_old_pcm=4' "$output"
  rg -qx 'r833_preclear_queued_pcm=2' "$output"
  rg -qx 'r833_preclear_scheduled_pcm=2' "$output"
  rg -qx 'r833_stale_events_injected=110' "$output"
  rg -qx 'r833_stale_events_returned=110' "$output"
  rg -qx 'r833_old_generation_output_accepted_after_fence=0' "$output"
  rg -qx 'r833_old_generation_audio_played=0' "$output"
  rg -qx 'r833_old_playback_restarts=0' "$output"
  rg -qx 'r833_old_text_or_subtitle_resurrections=0' "$output"
  rg -qx 'r833_old_playback_callbacks_rejected=2' "$output"
  rg -qx 'r833_extra_interruptions=0' "$output"
  rg -qx 'r833_extra_playback_clears=0' "$output"
  rg -qx 'r833_extra_generation_changes=0' "$output"
  rg -qx 'r833_n_plus_one_input_rebound=1' "$output"
  rg -qx 'r833_n_plus_one_output_rebound=1' "$output"
  rg -qx 'r833_n_plus_one_playback=1' "$output"
  rg -qx 'r833_n_plus_one_listening=1' "$output"
  rg -qx 'r833_real_qwen_semantic_latency=NOT_RUN_HUMAN_GATE' "$output"
  rg -qx 'r833_real_device_latency=NOT_RUN_HUMAN_GATE' "$output"

  r833_case_source="$(
    awk '/private static func testR833BargeInLatencyAndStaleClosure/ { active = 1 }
         /private static func testR832ConfirmedInterruptionProductionChain/ { active = 0 }
         active' "$test_source"
  )"
  r833_stale_source="$(
    awk '/private static func oldGenerationOutputEvents/ { active = 1 }
         /private static func testHistoryMemorySafety/ { active = 0 }
         active' "$test_source"
  )"
  r833_acoustic_source="$(
    awk '/private static func submitTrueNearEndThroughProductionChain/ { active = 1 }
         /private static func submitPostInterruptionInputThroughProductionChain/ { active = 0 }
         active' "$test_source"
  )"
  r833_rebound_source="$(
    awk '/private static func submitPostInterruptionInputThroughProductionChain/ { active = 1 }
         /private enum ResidentOnlyMixer/ { active = 0 }
         active' "$test_source"
  )"
  r833_source="${r833_case_source}${r833_stale_source}${r833_acoustic_source}${r833_rebound_source}"
  if rg -q \
      'RealtimeAcousticObservation\(|MacSpeechResidentAcousticSnapshot\(|RealtimeConfirmedInterruption\(|RealtimeBrain(Interrupt|CancelGeneration)Command\(|classification: \.nearEndCandidate|submitRealtimeResidentBrain(Acoustic|EligibleAcoustic)Evidence|consumeRealtimeResidentBrainInterruptionEvidence|receiveRealtimeResidentBrainEvent|claimRealtimeResidentBrainInterruptionDecision|completeRealtimeResidentBrainInterruption|cancelRealtimeResidentBrainGenerationForTesting|beginRealtimeBrainGenerationTransition|finishRealtimeBrainGenerationInterruption|speechAudioOutputHost\.clear\(|clearScheduledPlayback\(|provider\.(interrupt|cancelGeneration)\(|suspendForGenerationTransition|resumeAfterGenerationTransition|frameBuffer\.append\(|capture\.emit\(0x|Date\(\)|Thread\.sleep|usleep' \
      <<< "$r833_source"; then
    echo "r833_test_seam_bypass=FAIL" >&2
    exit 1
  fi
  if rg -q 'Task\.sleep' <<< "${r833_case_source}${r833_stale_source}"; then
    echo "r833_latency_sleep=FAIL" >&2
    exit 1
  fi
  rg -q 'submitTrueNearEndThroughProductionChain' <<< "$r833_case_source"
  rg -q 'submitPostInterruptionInputThroughProductionChain' \
    <<< "$r833_case_source"
  rg -q 'realtimeInterruptionTimingForTesting' <<< "$r833_case_source"
  rg -q 'acousticReceivedAtNanoseconds' <<< "$r833_case_source"
  rg -q 'outputHost\.timingDebugSnapshot' <<< "$r833_case_source"
  rg -q '50_000_000' <<< "$r833_case_source"
  rg -q '200_000_000' <<< "$r833_case_source"
  rg -q 'holdInterrupt\(' <<< "$r833_case_source"
  rg -q 'releaseInterrupt\(' <<< "$r833_case_source"
  rg -q 'kind: \.residentAudioDelta' <<< "$r833_stale_source"
  rg -q 'kind: \.residentTextDelta' <<< "$r833_stale_source"
  rg -q 'kind: \.residentTextFinal' <<< "$r833_stale_source"
  rg -q 'kind: \.residentSpeakingStarted' <<< "$r833_stale_source"
  rg -q 'kind: \.residentSpeakingStopped' <<< "$r833_stale_source"
  rg -q 'kind: \.residentSemanticFinal' <<< "$r833_stale_source"
  rg -q 'kind: \.cancelled' <<< "$r833_stale_source"
  rg -q 'kind: \.sessionClosed' <<< "$r833_stale_source"
  rg -q 'playbackStarted\(' <<< "$r833_acoustic_source"
  rg -q 'processRender\(' <<< "$r833_acoustic_source"
  rg -q 'processCapture\(' <<< "$r833_source"
  rg -q 'processedSamples: processed' <<< "$r833_source"
  rg -q 'outputConverter\.convert\(cleanedBuffer\)' "$test_source"
  echo "r833_production_chain_fixture=PASS"
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
elif [ "$test_mode" = "r832-confirmed-only" ]; then
  echo "realtime_confirmed_interruption=PASS"
elif [ "$test_mode" = "r833-latency-stale-only" ]; then
  echo "realtime_barge_in_latency_stale_audio=PASS"
else
  echo "realtime_resident_only_zero_self_interrupt_freeze=PASS"
fi
