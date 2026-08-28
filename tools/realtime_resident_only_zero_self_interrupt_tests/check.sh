#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_mode="${1:-r823-full}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r823-freeze.XXXXXX")"
fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
test_source="$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift"
timeout_runner="$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl"

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
    && [ "$test_mode" != "r833-latency-stale-only" ] \
    && [ "$test_mode" != "r841-double-talk-only" ] \
    && [ "$test_mode" != "r842-listening-only" ] \
    && [ "$test_mode" != "r842-turn-completion-only" ] \
    && [ "$test_mode" != "r843-semantic-fusion-only" ] \
    && [ "$test_mode" != "r844-classifier-only" ] \
    && [ "$test_mode" != "r844-response-policy-only" ] \
    && [ "$test_mode" != "r852-subtitle-diagnostics-only" ] \
    && [ "$test_mode" != "r851-cross-node-only" ] \
    && [ "$test_mode" != "r851-randomized-only" ] \
    && [ "$test_mode" != "r851-key-repeat" ]; then
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

run_bounded_binary() {
  local name="$1"
  local timeout_seconds="$2"
  local log_file="$3"
  shift 3
  local run_home="$runtime_home/$name"
  mkdir -p "$run_home"
  printf 'r851_subprocess_start=%s\n' "$name"
  set +e
  CFFIXED_USER_HOME="$run_home" \
    /usr/bin/perl "$timeout_runner" \
    "$timeout_seconds" \
    "$build_dir/realtime_resident_only_zero_self_interrupt_tests" \
    "$@" 2>&1 | tee "$log_file"
  local pipeline_status=("${PIPESTATUS[@]}")
  local command_status="${pipeline_status[0]}"
  local tee_status="${pipeline_status[1]}"
  set -e
  if [ "$command_status" -eq 124 ]; then
    printf 'r851_subprocess_timeout=%s\n' "$name" >&2
    return 124
  fi
  if [ "$command_status" -ne 0 ]; then
    printf 'r851_subprocess_fail=%s exit=%s\n' \
      "$name" "$command_status" >&2
    return "$command_status"
  fi
  if [ "$tee_status" -ne 0 ]; then
    printf 'r851_subprocess_log_fail=%s exit=%s\n' \
      "$name" "$tee_status" >&2
    return "$tee_status"
  fi
  printf 'r851_subprocess_pass=%s\n' "$name"
}

runner_arguments=("$fixture")
if [ "$test_mode" = "r831-positive-only" ]; then
  runner_arguments+=("--r831-positive-only")
elif [ "$test_mode" = "r832-confirmed-only" ]; then
  runner_arguments+=("--r832-confirmed-only")
elif [ "$test_mode" = "r833-latency-stale-only" ]; then
  runner_arguments+=("--r833-latency-stale-only")
elif [ "$test_mode" = "r841-double-talk-only" ]; then
  runner_arguments+=("--r841-double-talk-only")
elif [ "$test_mode" = "r842-listening-only" ]; then
  runner_arguments+=("--r842-listening-only")
elif [ "$test_mode" = "r842-turn-completion-only" ]; then
  runner_arguments+=("--r842-turn-completion-only")
elif [ "$test_mode" = "r843-semantic-fusion-only" ]; then
  runner_arguments+=("--r843-semantic-fusion-only")
elif [ "$test_mode" = "r844-classifier-only" ]; then
  runner_arguments+=("--r844-classifier-only")
elif [ "$test_mode" = "r844-response-policy-only" ]; then
  runner_arguments+=("--r844-response-policy-only")
elif [ "$test_mode" = "r852-subtitle-diagnostics-only" ]; then
  runner_arguments+=("--r852-subtitle-diagnostics-only")
elif [ "$test_mode" = "r851-cross-node-only" ]; then
  runner_arguments+=("--r851-cross-node-only")
elif [ "$test_mode" = "r851-randomized-only" ]; then
  runner_arguments+=("--r851-randomized-only")
fi

if [ "$test_mode" = "r851-key-repeat" ]; then
  repeat_runs=0
  repeat_subprocesses=0
  for repetition in 1 2 3; do
    for suite in r842-listening r843-semantic r832-confirmed r833-stale; do
      case "$suite" in
        r842-listening) argument="--r842-listening-only" ;;
        r843-semantic) argument="--r843-semantic-fusion-only" ;;
        r832-confirmed) argument="--r832-confirmed-only" ;;
        r833-stale) argument="--r833-latency-stale-only" ;;
      esac
      run_log="$build_dir/${suite}-${repetition}.log"
      run_bounded_binary \
        "${suite}-${repetition}" 120 "$run_log" \
        "$fixture" "$argument"
      repeat_subprocesses=$((repeat_subprocesses + 1))
      normalized="$build_dir/${suite}-${repetition}.normalized"
      rg '^(realtime_|r8)[a-zA-Z0-9_]*=' "$run_log" \
        | rg -v '^r833_(first_valid_near_end_to_|confirmed_to_)' \
        | LC_ALL=C sort \
        > "$normalized"
      if [ "$repetition" -eq 1 ]; then
        cp "$normalized" "$build_dir/${suite}-expected.normalized"
      elif ! cmp -s \
          "$build_dir/${suite}-expected.normalized" "$normalized"; then
        printf 'r851_repeat_counter_mismatch=%s-%s\n' \
          "$suite" "$repetition" >&2
        diff -u "$build_dir/${suite}-expected.normalized" \
          "$normalized" >&2 || true
        exit 1
      fi
      repeat_runs=$((repeat_runs + 1))
    done

    classifier_log="$build_dir/r844-classifier-${repetition}.log"
    policy_log="$build_dir/r844-policy-${repetition}.log"
    run_bounded_binary \
      "r844-classifier-${repetition}" 120 "$classifier_log" \
      "$fixture" --r844-classifier-only
    run_bounded_binary \
      "r844-policy-${repetition}" 120 "$policy_log" \
      "$fixture" --r844-response-policy-only
    repeat_subprocesses=$((repeat_subprocesses + 2))
    normalized="$build_dir/r844-${repetition}.normalized"
    rg '^(realtime_|r844_)[a-zA-Z0-9_]*=' \
      "$classifier_log" "$policy_log" \
      | sed 's|^[^:]*:||' \
      | LC_ALL=C sort > "$normalized"
    if [ "$repetition" -eq 1 ]; then
      cp "$normalized" "$build_dir/r844-expected.normalized"
    elif ! cmp -s \
        "$build_dir/r844-expected.normalized" "$normalized"; then
      printf 'r851_repeat_counter_mismatch=r844-%s\n' \
        "$repetition" >&2
      diff -u "$build_dir/r844-expected.normalized" \
        "$normalized" >&2 || true
      exit 1
    fi
    repeat_runs=$((repeat_runs + 1))
  done

  rg -qx 'realtime_turn_completion_listening_checks=139' \
    "$build_dir/r842-listening-1.log"
  rg -qx 'realtime_turn_completion_listening_cases=1' \
    "$build_dir/r842-listening-1.log"
  rg -qx 'realtime_semantic_turn_taking_checks=306' \
    "$build_dir/r843-semantic-1.log"
  rg -qx 'realtime_semantic_turn_taking_cases=13' \
    "$build_dir/r843-semantic-1.log"
  rg -qx 'realtime_backchannel_classifier_checks=46' \
    "$build_dir/r844-classifier-1.log"
  rg -qx 'realtime_backchannel_classifier_cases=43' \
    "$build_dir/r844-classifier-1.log"
  rg -qx 'realtime_backchannel_response_policy_checks=455' \
    "$build_dir/r844-policy-1.log"
  rg -qx 'realtime_backchannel_response_policy_cases=13' \
    "$build_dir/r844-policy-1.log"
  rg -qx 'realtime_confirmed_interruption_checks=62' \
    "$build_dir/r832-confirmed-1.log"
  rg -qx 'realtime_confirmed_interruption_cases=1' \
    "$build_dir/r832-confirmed-1.log"
  rg -qx 'realtime_barge_in_latency_stale_checks=68' \
    "$build_dir/r833-stale-1.log"
  rg -qx 'realtime_barge_in_latency_stale_cases=1' \
    "$build_dir/r833-stale-1.log"
  printf 'r851_key_suite_repeat_runs=%d\n' "$repeat_runs" | tee "$output"
  printf 'r851_key_suite_repeat_subprocesses=%d\n' \
    "$repeat_subprocesses" | tee -a "$output"
  printf 'r851_key_suite_repeat_failures=0\n' | tee -a "$output"
else
  run_bounded_binary \
    "$test_mode" 120 "$output" "${runner_arguments[@]}"
fi

if [ "$test_mode" = "r851-key-repeat" ]; then
  rg -qx 'r851_key_suite_repeat_runs=15' "$output"
  rg -qx 'r851_key_suite_repeat_subprocesses=18' "$output"
  rg -qx 'r851_key_suite_repeat_failures=0' "$output"
elif [ "$test_mode" = "r851-cross-node-only" ]; then
  rg -qx 'realtime_total_cross_node_cases=12' "$output"
  cross_node_checks="$(
    awk -F= '/^realtime_total_cross_node_checks=/ { print $2 }' "$output"
  )"
  [ -n "$cross_node_checks" ]
  [ "$cross_node_checks" -gt 0 ]
  rg -qx 'r851_cross_node_executable_scenarios=12' "$output"
  rg -qx 'r851_cross_node_failures=0' "$output"
  rg -qx 'r851_rapid_consecutive_turns=20' "$output"
  rg -qx 'r851_repeated_interruption_cycles=10' "$output"
  rg -qx 'r851_stop_restart_points=5' "$output"
  rg -qx 'r851_delayed_provider_ordering_cases=6' "$output"
  rg -qx 'r851_duplicate_response_creates=0' "$output"
  rg -qx 'r851_duplicate_interrupts=0' "$output"
  rg -qx 'r851_duplicate_clears=0' "$output"
  rg -qx 'r851_stale_generation_side_effects=0' "$output"
  rg -qx 'r851_false_self_interrupts=0' "$output"
  rg -qx 'r851_false_persistence_writes=0' "$output"
  rg -qx 'r851_false_history_writes=0' "$output"
  rg -qx 'r851_false_memory_writes=0' "$output"
  rg -qx 'r851_false_relationship_changes=0' "$output"
  rg -qx 'r851_false_growth_writes=0' "$output"
  rg -qx 'r851_generation_drift=0' "$output"
  rg -qx 'r851_lease_drift=0' "$output"
elif [ "$test_mode" = "r851-randomized-only" ]; then
  rg -qx 'realtime_total_randomized_cases=1' "$output"
  randomized_checks="$(
    awk -F= '/^realtime_total_randomized_checks=/ { print $2 }' "$output"
  )"
  [ -n "$randomized_checks" ]
  [ "$randomized_checks" -gt 0 ]
  rg -qx 'r851_randomized_seed=0x851511A7' "$output"
  rg -qx 'r851_randomized_race_iterations=100' "$output"
  rg -qx 'r851_randomized_race_failures=0' "$output"
  rg -qx 'r851_randomized_generation_transitions_expected=9' "$output"
  rg -qx 'r851_randomized_generation_transitions_observed=9' "$output"
  for ordering_counter in \
    r851_randomized_final_before_stop \
    r851_randomized_completion_before_final \
    r851_randomized_partial_final_stop \
    r851_randomized_short_pause_resume \
    r851_randomized_provider_first_start; do
    ordering_count="$(awk -F= -v key="$ordering_counter" \
      '$1 == key { print $2 }' "$output")"
    [ -n "$ordering_count" ]
    [ "$ordering_count" -gt 0 ]
  done
  rg -qx 'r851_randomized_duplicate_response_creates=0' "$output"
  rg -qx 'r851_randomized_false_self_interrupts=0' "$output"
  rg -qx 'r851_randomized_false_persistence_writes=0' "$output"
  rg -qx 'r851_randomized_generation_drift=0' "$output"
  rg -qx 'r851_randomized_lease_drift=0' "$output"
elif [ "$test_mode" = "r852-subtitle-diagnostics-only" ]; then
  rg -qx 'realtime_formal_subtitle_diagnostics_cases=4' "$output"
  subtitle_checks="$(
    awk -F= '/^realtime_formal_subtitle_diagnostics_checks=/ { print $2 }' \
      "$output"
  )"
  [ -n "$subtitle_checks" ]
  [ "$subtitle_checks" -gt 0 ]
  rg -qx 'r852_subtitle_delta_presentations=2' "$output"
  rg -qx 'r852_subtitle_final_presentations=1' "$output"
  rg -qx 'r852_user_final_fallback_presentations=0' "$output"
  rg -qx 'r852_playback_completion_resurrections=0' "$output"
  rg -qx 'r852_audio_first_resurrections=0' "$output"
  rg -qx 'r852_interruption_resurrections=0' "$output"
  rg -qx 'r852_old_identity_resurrections=0' "$output"
  rg -qx 'r852_recoverable_response_errors=1' "$output"
  rg -qx 'r852_terminal_stops=0' "$output"
  rg -qx 'r852_post_error_response_rebound=1' "$output"
  rg -qx 'r852_provider_closes_on_response_error=0' "$output"

  subtitle_source="$({
    awk '/private static func testR852FormalRealtimeSubtitleAndDiagnostics/ { active = 1 }
         /private static func testR833BargeInLatencyAndStaleClosure/ { active = 0 }
         active' "$test_source"
  })"
  rg -q 'kind: \.residentTextDelta' <<< "$subtitle_source"
  rg -q 'kind: \.residentTextFinal' <<< "$subtitle_source"
  rg -q 'particleSubtitleState' <<< "$subtitle_source"
  rg -q 'kind: \.error\(\.providerFailure\)' <<< "$subtitle_source"
  rg -q 'recoverable_response_error' <<< "$subtitle_source"
  rg -q 'submitTrueNearEndThroughProductionChain' <<< "$subtitle_source"
  rg -q 'submitSemanticProposal' <<< "$subtitle_source"
  if rg -q \
      'syncRealtimeBrainSubtitlePresentation\(|syncRealtimeSpeechPresentation\(|consumeRealtimeResidentBrainEvent\(|speechAudioOutputHost\.clear\(|stopRealtimeResidentBrainRoute\(' \
      <<< "$subtitle_source"; then
    echo "r852_test_seam_bypass=FAIL" >&2
    exit 1
  fi
  echo "r852_formal_production_fixture=PASS"
elif [ "$test_mode" = "r844-classifier-only" ]; then
  rg -qx 'realtime_backchannel_classifier_cases=43' "$output"
  rg -qx 'realtime_backchannel_classifier_checks=46' "$output"
  rg -qx 'r844_classifier_passive_cases=19' "$output"
  rg -qx 'r844_classifier_substantive_cases=24' "$output"
  rg -qx 'r844_classifier_false_passive=0' "$output"
  rg -qx 'r844_classifier_false_substantive=0' "$output"
  classifier_source="$({
    awk '/private static func testR844BackchannelClassifier/ { active = 1 }
         /private static func testR844BackchannelResponsePolicy/ { active = 0 }
         active' "$test_source"
  })"
  rg -q 'realtimeUserTurnDispositionForTesting' <<< "$classifier_source"
  rg -q '"嗯", "嗯嗯", "唔", "唔嗯", "哦", "哦哦"' \
    <<< "$classifier_source"
  rg -q '"好", "好的", "可以", "行", "对", "是", "是的"' \
    <<< "$classifier_source"
  rg -q '"继续"' <<< "$classifier_source"
  rg -q '"嗯？"' <<< "$classifier_source"
  echo "r844_classifier_fixed_set=PASS"
  echo "r844_classifier_fail_open=PASS"
elif [ "$test_mode" = "r844-response-policy-only" ]; then
  rg -qx 'realtime_backchannel_response_policy_cases=13' "$output"
  rg -qx 'realtime_backchannel_response_policy_checks=455' "$output"
  rg -qx 'r844_passive_backchannel_cases=11' "$output"
  rg -qx 'r844_passive_backchannel_dispositions=11' "$output"
  rg -qx 'r844_passive_backchannel_response_creates=0' "$output"
  rg -qx 'r844_substantive_cases=12' "$output"
  rg -qx 'r844_substantive_dispositions=12' "$output"
  rg -qx 'r844_substantive_response_creates=12' "$output"
  rg -qx 'r844_response_creates=12' "$output"
  rg -qx 'r844_cross_source_mixed_response_creates=1' "$output"
  rg -qx 'r844_cross_source_passive_response_creates=0' "$output"
  rg -qx 'r844_duplicate_response_creates=0' "$output"
  rg -qx 'r844_provider_only_response_creates=0' "$output"
  rg -qx 'r844_provider_only_dispositions=0' "$output"
  rg -qx 'r844_stale_generation_response_creates=0' "$output"
  rg -qx 'r844_n_plus_one_substantive_response_creates=1' "$output"
  rg -qx 'r844_false_history_writes=0' "$output"
  rg -qx 'r844_false_memory_writes=0' "$output"
  rg -qx 'r844_relationship_changes=0' "$output"
  rg -qx 'r844_growth_writes=0' "$output"
  rg -qx 'r844_extra_interrupts=0' "$output"
  rg -qx 'r844_extra_playback_clears=0' "$output"
  rg -qx 'r844_extra_generation_advances=0' "$output"
  rg -qx 'r844_real_qwen_and_devices=NOT_RUN_HUMAN_GATE' "$output"

  r844_source="$({
    awk '/private static func testR844BackchannelResponsePolicy/ { active = 1 }
         /private static func testR843SemanticTurnTakingFusion/ { active = 0 }
         active' "$test_source"
    awk '/private static func emitR842ListeningSamples/ { active = 1 }
         /private static func assertR842ListeningHasNoDecisionSideEffects/ { active = 0 }
         active' "$test_source"
  })"
  capture_activity_source="$({
    awk '/private final class R823AudioCapture/ { active = 1 }
         /private struct R823ControllerStack/ { active = 0 }
         active' "$test_source"
  })"
  if rg -q \
      'realtimeUserTurnDispositionForTesting|provider\.createResponse\(|RealtimeBrainCreateResponseCommand\(|createRealtimeResidentBrainResponseIfEligible|authorizeRealtimeResidentBrainResponseIfEligible|beginResponseCreate|claimResponseCreateExecution|retireRealtimeUtterance|finishRealtimeUtteranceCompletionWindow|submitRealtimeResidentBrain(Acoustic|EligibleAcoustic)Evidence|RealtimeAcousticObservation\(|MacSpeechResidentAcousticSnapshot\(|cancelRealtimeResidentBrainGenerationForTesting|interruptRealtimeResidentBrainForTesting|beginRealtimeBrainGenerationTransition|finishRealtimeBrainGenerationInterruption|frameBuffer\.append\(' \
      <<< "$r844_source"; then
    echo "r844_test_seam_bypass=FAIL" >&2
    exit 1
  fi
  rg -q 'MacSpeechAudioActivityEvidenceKind\.classify' \
    <<< "$capture_activity_source"
  rg -q 'emitR842ListeningSamples' <<< "$r844_source"
  rg -q 'processCapture\(' <<< "$r844_source"
  rg -q 'processedSamples: processed' <<< "$r844_source"
  rg -q 'kind: \.userSpeechStarted' <<< "$r844_source"
  rg -q 'kind: \.userSpeechStopped' <<< "$r844_source"
  rg -q 'kind: \.userTranscriptFinal' <<< "$r844_source"
  rg -q 'waitForR842Completion' <<< "$r844_source"
  rg -q 'stack\.provider\.createCount' <<< "$r844_source"
  rg -q 'stack\.provider\.lastCreateCommand' <<< "$r844_source"
  rg -q 'loadMostRecentDialogueEntries' <<< "$r844_source"
  rg -q 'narrativeMemoryDebugSnapshot' <<< "$r844_source"
  rg -q 'currentRelationshipState' <<< "$r844_source"
  rg -q 'realtimeGrowthObservationDecisionCountForTesting' \
    <<< "$r844_source"
  rg -q 'restartR843Route' <<< "$r844_source"
  rg -q 'testR832ConfirmedInterruptionProductionChain' <<< "$r844_source"
  rg -q 'firstTranscript: "嗯"' <<< "$r844_source"
  rg -q 'secondTranscript: "我还有一个问题"' <<< "$r844_source"
  rg -q 'secondTranscript: "嗯嗯"' <<< "$r844_source"

  provider_audio_frame="$build_dir/provider-audio-frame.txt"
  awk \
    '/struct RealtimeBrainAudioFrame/ { active = 1 }
     active { print }
     active && /^}/ { exit }' \
    "$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift" \
    > "$provider_audio_frame"
  if rg -q \
      'sourceGate|userActivity|nearEnd|playback|turn|completion|[Aa]coustic|[Ee]ligibility|backchannel|semantic|disposition' \
      "$provider_audio_frame"; then
    echo "r844_provider_pcm_contract=FAIL" >&2
    exit 1
  fi
  echo "r844_production_chain_fixture=PASS"
  echo "r844_runtime_single_response_owner=PASS"
  echo "r844_provider_pcm_contract=PASS"
  echo "r844_passive_persistence=PASS"
elif [ "$test_mode" = "r843-semantic-fusion-only" ]; then
  rg -qx 'realtime_semantic_turn_taking_cases=13' "$output"
  r843_checks="$({
    awk -F= '/^realtime_semantic_turn_taking_checks=/ { print $2 }' \
      "$output"
  })"
  [ -n "$r843_checks" ]
  [ "$r843_checks" -gt 0 ]
  rg -qx 'r843_final_before_completion_cases=1' "$output"
  rg -qx 'r843_completion_before_final_cases=1' "$output"
  rg -qx 'r843_cross_source_turn_cases=1' "$output"
  rg -qx 'r843_valid_completed_semantic_turns=6' "$output"
  rg -qx 'r843_valid_turn_response_creates=6' "$output"
  rg -qx 'r843_completion_only_response_creates=0' "$output"
  rg -qx 'r843_semantic_only_response_creates=0' "$output"
  rg -qx 'r843_provider_only_response_creates=0' "$output"
  rg -qx 'r843_empty_final_response_creates=0' "$output"
  rg -qx 'r843_wrong_identity_response_creates=0' "$output"
  rg -qx 'r843_stale_generation_response_creates=0' "$output"
  rg -qx 'r843_duplicate_response_creates=0' "$output"
  rg -qx 'r843_extra_interrupts=0' "$output"
  rg -qx 'r843_extra_playback_clears=0' "$output"
  rg -qx 'r843_extra_generation_advances=0' "$output"
  rg -qx 'r843_real_qwen_and_devices=NOT_RUN_HUMAN_GATE' "$output"

  r843_source="$({
    awk '/private static func testR843SemanticTurnTakingFusion/ { active = 1 }
         /private static func testR842PauseVsUtteranceCompletion/ { active = 0 }
         active' "$test_source"
    awk '/private static func emitR842ListeningSamples/ { active = 1 }
         /private static func assertR842ListeningHasNoDecisionSideEffects/ { active = 0 }
         active' "$test_source"
  })"
  capture_activity_source="$({
    awk '/private final class R823AudioCapture/ { active = 1 }
         /private struct R823ControllerStack/ { active = 0 }
         active' "$test_source"
  })"
  if rg -q \
      'provider\.createResponse\(|RealtimeBrainCreateResponseCommand\(|createRealtimeResidentBrainResponseIfEligible|beginResponseCreate|finishResponseCreate|finishRealtimeUtteranceCompletionWindow|submitRealtimeResidentBrain(Acoustic|EligibleAcoustic)Evidence|RealtimeAcousticObservation\(|MacSpeechResidentAcousticSnapshot\(|cancelRealtimeResidentBrainGenerationForTesting|interruptRealtimeResidentBrainForTesting|beginRealtimeBrainGenerationTransition|finishRealtimeBrainGenerationInterruption|frameBuffer\.append\(' \
      <<< "$r843_source"; then
    echo "r843_test_seam_bypass=FAIL" >&2
    exit 1
  fi
  rg -q 'MacSpeechAudioActivityEvidenceKind\.classify' \
    <<< "$capture_activity_source"
  rg -q 'emitR842ListeningSamples' <<< "$r843_source"
  rg -q 'processCapture\(' <<< "$r843_source"
  rg -q 'processedSamples: processed' <<< "$r843_source"
  rg -q 'kind: \.userSpeechStarted' <<< "$r843_source"
  rg -q 'kind: \.userSpeechStopped' <<< "$r843_source"
  rg -q 'kind: \.userTranscriptPartial' <<< "$r843_source"
  rg -q 'kind: \.userTranscriptFinal' <<< "$r843_source"
  rg -q 'testR832ConfirmedInterruptionProductionChain' <<< "$r843_source"
  rg -q 'stack\.provider\.createCount' <<< "$r843_source"
  rg -q 'stack\.provider\.lastCreateCommand' <<< "$r843_source"

  provider_audio_frame="$build_dir/provider-audio-frame.txt"
  awk \
    '/struct RealtimeBrainAudioFrame/ { active = 1 }
     active { print }
     active && /^}/ { exit }' \
    "$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift" \
    > "$provider_audio_frame"
  if rg -q \
      'sourceGate|userActivity|nearEnd|playback|turn|completion|[Aa]coustic|[Ee]ligibility' \
      "$provider_audio_frame"; then
    echo "r843_provider_pcm_contract=FAIL" >&2
    exit 1
  fi
  echo "r843_production_chain_fixture=PASS"
  echo "r843_runtime_single_response_owner=PASS"
  echo "r843_provider_pcm_contract=PASS"
elif [ "$test_mode" = "r842-listening-only" ]; then
  rg -qx 'realtime_turn_completion_listening_cases=1' "$output"
  rg -qx 'realtime_turn_completion_listening_checks=139' "$output"
  rg -qx 'r842_listening_continuous_cases=1' "$output"
  rg -qx 'r842_listening_short_pause_cases=1' "$output"
  rg -qx 'r842_listening_speaking_admissions=4' "$output"
  rg -qx 'r842_listening_true_end_candidates=3' "$output"
  rg -qx 'r842_listening_false_completions=0' "$output"
  rg -qx 'r842_provider_only_false_admissions=0' "$output"
  rg -qx 'r842_provider_only_false_completions=0' "$output"
  rg -qx 'r842_listening_negative_false_admissions=0' "$output"
  rg -qx 'r842_listening_negative_false_completions=0' "$output"
  rg -qx 'r842_stale_pcm_admissions=0' "$output"
  rg -qx 'r842_old_generation_completions=0' "$output"

  listening_source="$({
    awk '/private static func testR842NormalListeningAdmission/ { active = 1 }
         /private static func printR842ListeningMetrics/ { active = 0 }
         active' "$test_source"
  })"
  capture_activity_source="$({
    awk '/private final class R823AudioCapture/ { active = 1 }
         /private struct R823ControllerStack/ { active = 0 }
         active' "$test_source"
  })"
  if rg -q \
      'establishR842AcousticAuthorization|submitR841DoubleTalkThroughProductionChain|submitRealtimeResidentBrain(Acoustic|EligibleAcoustic)Evidence|RealtimeAcousticObservation\(|classification: \.nearEndCandidate|residentPlaybackActive: true' \
      <<< "$listening_source"; then
    echo "r842_listening_test_seam_bypass=FAIL" >&2
    exit 1
  fi
  rg -q 'MacSpeechAudioActivityEvidenceKind\.classify' \
    <<< "$capture_activity_source"
  rg -q 'processCapture\(' <<< "$listening_source"
  rg -q 'processedSamples: processed' <<< "$listening_source"
  rg -q 'kind: \.userSpeechStarted' <<< "$listening_source"
  rg -q 'kind: \.userSpeechStopped' <<< "$listening_source"
  rg -q 'kind: \.userTranscriptFinal' <<< "$listening_source"
  rg -q 'activity: activity\.localActivity' \
    "$repo_root/apps/macos/Aftelle/AppController.swift"
  rg -q 'confirmAcceptedLocalActivity' \
    "$repo_root/apps/macos/Aftelle/AppController.swift" \
    "$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
  rg -q 'confirmRealtimeResidentBrainAcceptedLocalAudioActivity' \
    "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
  rg -q 'lastAudioInputFrame == frame' \
    "$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
  provider_audio_frame="$build_dir/provider-audio-frame.txt"
  awk \
    '/struct RealtimeBrainAudioFrame/ { active = 1 }
     active { print }
     active && /^}/ { exit }' \
    "$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift" \
    > "$provider_audio_frame"
  if rg -q \
      'sourceGate|userActivity|nearEnd|playback|turn|completion|[Aa]coustic|[Ee]ligibility' \
      "$provider_audio_frame"; then
    echo "r842_provider_pcm_contract=FAIL" >&2
    exit 1
  fi
  echo "r842_listening_production_chain_fixture=PASS"
  echo "r842_provider_pcm_contract=PASS"
elif [ "$test_mode" = "r842-turn-completion-only" ]; then
  rg -qx 'realtime_turn_completion_cases=1' "$output"
  rg -qx 'realtime_turn_completion_checks=390' "$output"
  rg -qx 'r842_completion_window_ns=800000000' "$output"
  rg -qx 'r842_clock_source=monotonic_uptime' "$output"
  rg -qx 'r842_short_pause_cases=5' "$output"
  rg -qx 'r842_short_pause_false_completions=0' "$output"
  rg -qx 'r842_true_end_cases=11' "$output"
  rg -qx 'r842_utterance_completion_candidates=11' "$output"
  max_true_end_latency="$({
    awk -F= '/^r842_max_true_end_latency_ns=/ { print $2 }' "$output"
  })"
  [ "$max_true_end_latency" -ge 800000000 ]
  [ "$max_true_end_latency" -le 1600000000 ]
  rg -qx 'r842_duplicate_completions=0' "$output"
  rg -qx 'r842_resident_only_false_completions=0' "$output"
  rg -qx 'r842_stale_generation_completions=0' "$output"
  rg -qx 'r842_old_timer_resurrections=0' "$output"
  rg -qx 'r842_double_talk_cases=2' "$output"
  rg -qx 'r842_response_creates=0' "$output"
  rg -qx 'r842_provider_interrupts=0' "$output"
  rg -qx 'r842_provider_cancels=0' "$output"
  rg -qx 'r842_host_playback_clears=0' "$output"
  rg -qx 'r842_extra_generation_advances=0' "$output"
  rg -qx 'r842_listening_continuous_cases=1' "$output"
  rg -qx 'r842_listening_short_pause_cases=1' "$output"
  rg -qx 'r842_listening_speaking_admissions=4' "$output"
  rg -qx 'r842_listening_true_end_candidates=3' "$output"
  rg -qx 'r842_listening_false_completions=0' "$output"
  rg -qx 'r842_provider_only_false_admissions=0' "$output"
  rg -qx 'r842_provider_only_false_completions=0' "$output"
  rg -qx 'r842_listening_negative_false_admissions=0' "$output"
  rg -qx 'r842_listening_negative_false_completions=0' "$output"
  rg -qx 'r842_stale_pcm_admissions=0' "$output"
  rg -qx 'r842_old_generation_completions=0' "$output"
  rg -qx 'r842_real_qwen_and_devices=NOT_RUN_HUMAN_GATE' "$output"

  r842_source="$({
    awk '/private static func testR842PauseVsUtteranceCompletion/ { active = 1 }
         /private enum R841DoubleTalkTransition/ { active = 0 }
         active' "$test_source"
  })"
  if rg -q \
      'interruptionProposed|submitSemanticProposal|createRealtimeResidentBrainResponseIfEligible|beginResponseCreate|finishResponseCreate|cancelRealtimeResidentBrainGenerationForTesting|interruptRealtimeResidentBrainForTesting|submitRealtimeResidentBrain(Acoustic|EligibleAcoustic)Evidence|RealtimeAcousticObservation\(|MacSpeechResidentAcousticSnapshot\(' \
      <<< "$r842_source"; then
    echo "r842_test_seam_bypass=FAIL" >&2
    exit 1
  fi
  rg -q 'submitR841DoubleTalkThroughProductionChain' <<< "$r842_source"
  rg -q 'submitR841ResidentOnlyThroughProductionChain' <<< "$r842_source"
  rg -q 'submitR841PlaybackTailThroughProductionChain' <<< "$r842_source"
  rg -q 'kind: \.userSpeechStarted' <<< "$r842_source"
  rg -q 'kind: \.userSpeechStopped' <<< "$r842_source"
  rg -q 'kind: \.userTranscriptPartial' <<< "$r842_source"
  rg -q 'kind: \.userTranscriptFinal' <<< "$r842_source"
  rg -q 'DispatchTime\.now\(\)\.uptimeNanoseconds' \
    "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
  rg -q 'realtimeUtteranceCompletionWindowNanoseconds' \
    "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
  rg -q 'UInt64 = 800_000_000' \
    "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
  rg -q 'static let minimumNearEndRMS = 0.012' \
    "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
  echo "r842_formal_activity_fixture=PASS"
  echo "r842_runtime_single_owner=PASS"
elif [ "$test_mode" = "r841-double-talk-only" ]; then
  rg -qx 'realtime_double_talk_acoustic_cases=1' "$output"
  rg -qx 'realtime_double_talk_acoustic_checks=163' "$output"
  rg -qx 'r841_positive_scenarios=11' "$output"
  rg -qx 'r841_double_talk_detected_scenarios=11' "$output"
  rg -qx 'r841_source_gate_open_scenarios=11' "$output"
  rg -qx 'r841_acoustic_eligibility=11' "$output"
  double_talk_frames="$(
    awk -F= '/^r841_double_talk_frames=/ { print $2 }' "$output"
  )"
  active_pcm_packets="$(
    awk -F= '/^r841_active_pcm_packets=/ { print $2 }' "$output"
  )"
  [ "$double_talk_frames" -ge 52 ]
  [ "$active_pcm_packets" -gt 0 ]
  rg -qx 'r841_adaptive_scenarios=1' "$output"
  rg -qx 'r841_transition_to_near_end=1' "$output"
  rg -qx 'r841_transition_to_far_end=1' "$output"
  rg -qx 'r841_negative_scenarios=6' "$output"
  rg -qx 'r841_negative_observations=176' "$output"
  rg -qx 'r841_negative_frames=3896' "$output"
  rg -qx 'r841_stress_frames=3840' "$output"
  rg -qx 'r841_false_double_talk=0' "$output"
  rg -qx 'r841_far_end_false_double_talk=0' "$output"
  rg -qx 'r841_residual_echo_false_double_talk=0' "$output"
  rg -qx 'r841_playback_tail_false_double_talk=0' "$output"
  rg -qx 'r841_timing_jitter_false_double_talk=0' "$output"
  rg -qx 'r841_stress_false_double_talk=0' "$output"
  rg -qx 'r841_resident_only_eligibility=0' "$output"
  rg -qx 'r841_confirmed_interruptions=0' "$output"
  rg -qx 'r841_provider_interrupts=0' "$output"
  rg -qx 'r841_provider_cancels=0' "$output"
  rg -qx 'r841_host_playback_clears=0' "$output"
  rg -qx 'r841_generation_changes=0' "$output"
  rg -qx 'r841_lease_changes=0' "$output"
  rg -qx 'r841_semantic_proposals=0' "$output"
  rg -qx 'r841_acoustic_threshold_changes=0' "$output"
  rg -qx 'r841_real_room_and_devices=NOT_RUN_HUMAN_GATE' "$output"

  r841_source="$({
    awk '/private static func testR841DoubleTalkAcousticDetermination/ { active = 1 }
         /private static func testR852FormalRealtimeSubtitleAndDiagnostics/ { active = 0 }
         active' "$test_source"
    awk '/private static func submitR841DoubleTalkThroughProductionChain/ { active = 1 }
         /private static func testR852FormalRealtimeSubtitleAndDiagnostics/ { active = 0 }
         active' "$test_source"
  })"
  if rg -q \
      'RealtimeAcousticObservation\(|MacSpeechResidentAcousticSnapshot\(|classification: \.(doubleTalk|nearEndCandidate)|submitSemanticProposal|kind: \.interruptionProposed|submitRealtimeResidentBrain(Acoustic|EligibleAcoustic)Evidence|consumeRealtimeResidentBrainInterruptionEvidence|claimRealtimeResidentBrainInterruptionDecision|completeRealtimeResidentBrainInterruption|beginRealtimeBrainGenerationTransition|speechAudioOutputHost\.clear\(|clearScheduledPlayback\(|provider\.(interrupt|cancelGeneration)\(|frameBuffer\.append\(' \
      <<< "$r841_source"; then
    echo "r841_test_seam_bypass=FAIL" >&2
    exit 1
  fi
  rg -q 'playbackStarted\(' <<< "$r841_source"
  rg -q 'playbackCompleted\(' <<< "$r841_source"
  rg -q 'processRender\(' <<< "$r841_source"
  rg -q 'processCapture\(' <<< "$r841_source"
  rg -q 'zip\(render, nearEnd\)' <<< "$r841_source"
  rg -q 'processedSamples: processed' <<< "$r841_source"
  rg -q 'sourceAssessment == \.doubleTalk' <<< "$r841_source"
  rg -q 'outputConverter\.convert\(cleanedBuffer\)' "$test_source"
  rg -q 'pendingEligibleAcousticObservation == nil' \
    "$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
  echo "r841_production_chain_fixture=PASS"
elif [ "$test_mode" = "r831-positive-only" ]; then
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
elif [ "$test_mode" = "r841-double-talk-only" ]; then
  echo "realtime_double_talk_acoustic=PASS"
elif [ "$test_mode" = "r842-listening-only" ]; then
  echo "realtime_turn_completion_listening_admission=PASS"
elif [ "$test_mode" = "r842-turn-completion-only" ]; then
  echo "realtime_turn_completion=PASS"
elif [ "$test_mode" = "r844-classifier-only" ]; then
  echo "realtime_backchannel_classifier=PASS"
elif [ "$test_mode" = "r844-response-policy-only" ]; then
  echo "realtime_backchannel_response_policy=PASS"
elif [ "$test_mode" = "r852-subtitle-diagnostics-only" ]; then
  echo "realtime_formal_subtitle_diagnostics=PASS"
elif [ "$test_mode" = "r843-semantic-fusion-only" ]; then
  echo "realtime_semantic_turn_taking=PASS"
elif [ "$test_mode" = "r851-cross-node-only" ]; then
  echo "realtime_total_cross_node=PASS"
elif [ "$test_mode" = "r851-randomized-only" ]; then
  echo "realtime_total_randomized=PASS"
elif [ "$test_mode" = "r851-key-repeat" ]; then
  echo "realtime_total_key_repeat=PASS"
else
  echo "realtime_resident_only_zero_self_interrupt_freeze=PASS"
fi
