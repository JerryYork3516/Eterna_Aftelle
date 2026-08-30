#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r851-total.XXXXXX")"
manifest="$repo_root/tools/realtime_total_regression_tests/total_invariant_manifest.tsv"
shared_runner="$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/check.sh"
production_contract="$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
qwen_adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift"
timeout_runner="$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl"
expected_production_digest="c60986c398fd7616c85e5f70a5d5d4b74f21e0b171c420fc4e4d3fcca30fe6cc"
expected_manifest_digest="6de2ef316f6bf03b393e14549e4cd3dd6f1b0c958ad1a75e1dcec6731ddb7780"
trap 'rm -rf "$work_dir"' EXIT

production_digest() {
  git -C "$repo_root" ls-files -z \
    | while IFS= read -r -d '' tracked_file; do
        case "$tracked_file" in
          tools/*|docs/*|DEVLOG.md) continue ;;
        esac
        file_digest="$(shasum -a 256 "$repo_root/$tracked_file" \
          | awk '{print $1}')"
        printf '%s\t%s\n' "$file_digest" "$tracked_file"
      done \
    | shasum -a 256 \
    | awk '{print $1}'
}

worktree_fingerprint() {
  {
    git -C "$repo_root" diff --binary --no-ext-diff HEAD
    while IFS= read -r -d '' untracked; do
      printf '%s\0' "$untracked"
      shasum -a 256 "$repo_root/$untracked"
    done < <(git -C "$repo_root" ls-files --others --exclude-standard -z)
  } | shasum -a 256 | awk '{print $1}'
}

run_named_suite() {
  local name="$1"
  local timeout_seconds="$2"
  local log_file="$3"
  shift 3
  printf 'r851_suite_start=%s\n' "$name"
  set +e
  /usr/bin/perl "$timeout_runner" \
    "$timeout_seconds" "$@" 2>&1 | tee "$log_file"
  local pipeline_status=("${PIPESTATUS[@]}")
  local command_status="${pipeline_status[0]}"
  local tee_status="${pipeline_status[1]}"
  set -e
  if [ "$command_status" -eq 124 ]; then
    printf 'r851_suite_timeout=%s\n' "$name" >&2
    return 124
  fi
  if [ "$command_status" -ne 0 ]; then
    printf 'r851_suite_fail=%s exit=%s\n' \
      "$name" "$command_status" >&2
    return "$command_status"
  fi
  if [ "$tee_status" -ne 0 ]; then
    printf 'r851_suite_log_fail=%s exit=%s\n' \
      "$name" "$tee_status" >&2
    return "$tee_status"
  fi
  printf 'r851_suite_pass=%s\n' "$name"
}

status_before="$(git -C "$repo_root" status --porcelain=v1)"
fingerprint_before="$(worktree_fingerprint)"
head_before="$(git -C "$repo_root" rev-parse HEAD)"
branch_before="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || true)"
production_before="$(production_digest)"

expected_manifest_header=$'ID\tInvariant\tExecutable evidence'
[ "$(head -n 1 "$manifest")" = "$expected_manifest_header" ]
expected_manifest_ids=$'A1\nA2\nA3\nB1\nC1\nD1\nE1\nF1\nG1\nH1\nI1'
actual_manifest_ids="$(awk -F '\t' 'NR > 1 { print $1 }' "$manifest" \
  | LC_ALL=C sort)"
[ "$actual_manifest_ids" = "$expected_manifest_ids" ]
manifest_rows="$(awk 'END { print NR - 1 }' "$manifest")"
[ "$manifest_rows" -eq 11 ]
manifest_digest="$(shasum -a 256 "$manifest" | awk '{print $1}')"
[ "$manifest_digest" = "$expected_manifest_digest" ]
printf 'r851_total_invariant_manifest_rows=%s\n' "$manifest_rows"
printf 'r851_total_invariant_manifest=PASS\n'

cross_log="$work_dir/cross-node.log"
random_log="$work_dir/randomized.log"
repeat_log="$work_dir/key-repeat.log"
tool_log="$work_dir/tool.log"

run_named_suite cross-node 180 "$cross_log" \
  "$shared_runner" r851-cross-node-only
run_named_suite randomized-ordering 180 "$random_log" \
  "$shared_runner" r851-randomized-only
run_named_suite key-suite-repeat 900 "$repeat_log" \
  "$shared_runner" r851-key-repeat
run_named_suite tool-boundary 180 "$tool_log" \
  "$repo_root/tools/realtime_resident_brain_tool_tests/check.sh"

rg -qx 'realtime_total_cross_node=PASS' "$cross_log"
rg -qx 'realtime_total_randomized=PASS' "$random_log"
rg -qx 'realtime_total_key_repeat=PASS' "$repeat_log"
rg -qx 'realtime_resident_brain_tool_cases=7' "$tool_log"
rg -qx 'realtime_resident_brain_tool_checks=143' "$tool_log"
rg -qx 'realtime_resident_brain_tool_fixture=PASS' "$tool_log"
rg -qx 'realtime_resident_brain_tool_runtime_ownership=PASS' "$tool_log"
rg -qx 'realtime_resident_brain_tool_provider_execution_bypass=PASS' \
  "$tool_log"
rg -qx 'realtime_resident_brain_tool_parallel_system=PASS' "$tool_log"
rg -qx 'realtime_resident_brain_tool_network_dependency=ZERO' "$tool_log"

swift_scenarios="$(awk -F= \
  '/^r851_cross_node_executable_scenarios=/ { print $2 }' "$cross_log")"
tool_scenarios="$(rg -c \
  '^realtime_resident_brain_tool_runtime_ownership=PASS$' "$tool_log")"
cross_node_scenarios="$((swift_scenarios + tool_scenarios))"
[ "$tool_scenarios" -eq 1 ]
[ "$cross_node_scenarios" -eq 13 ]

random_iterations="$(awk -F= \
  '/^r851_randomized_race_iterations=/ { print $2 }' "$random_log")"
repeat_runs="$(awk -F= \
  '/^r851_key_suite_repeat_runs=/ { print $2 }' "$repeat_log")"
[ "$random_iterations" -ge 100 ]
[ "$repeat_runs" -ge 15 ]

cross_failures="$(awk -F= \
  '/^r851_cross_node_failures=/ { print $2 }' "$cross_log")"
random_failures="$(awk -F= \
  '/^r851_randomized_race_failures=/ { print $2 }' "$random_log")"
duplicate_response_creates="$((
  $(awk -F= '/^r851_duplicate_response_creates=/ { print $2 }' "$cross_log")
  + $(awk -F= '/^r851_randomized_duplicate_response_creates=/ { print $2 }' "$random_log")
))"
duplicate_interrupts="$(awk -F= \
  '/^r851_duplicate_interrupts=/ { print $2 }' "$cross_log")"
duplicate_clears="$(awk -F= \
  '/^r851_duplicate_clears=/ { print $2 }' "$cross_log")"
stale_side_effects="$(awk -F= \
  '/^r851_stale_generation_side_effects=/ { print $2 }' "$cross_log")"
false_self_interrupts="$((
  $(awk -F= '/^r851_false_self_interrupts=/ { print $2 }' "$cross_log")
  + $(awk -F= '/^r851_randomized_false_self_interrupts=/ { print $2 }' "$random_log")
))"
false_persistence_writes="$((
  $(awk -F= '/^r851_false_persistence_writes=/ { print $2 }' "$cross_log")
  + $(awk -F= '/^r851_randomized_false_persistence_writes=/ { print $2 }' "$random_log")
))"
false_history_writes="$(awk -F= \
  '/^r851_false_history_writes=/ { print $2 }' "$cross_log")"
false_memory_writes="$(awk -F= \
  '/^r851_false_memory_writes=/ { print $2 }' "$cross_log")"
false_relationship_changes="$(awk -F= \
  '/^r851_false_relationship_changes=/ { print $2 }' "$cross_log")"
false_growth_writes="$(awk -F= \
  '/^r851_false_growth_writes=/ { print $2 }' "$cross_log")"
generation_drift="$((
  $(awk -F= '/^r851_generation_drift=/ { print $2 }' "$cross_log")
  + $(awk -F= '/^r851_randomized_generation_drift=/ { print $2 }' "$random_log")
))"
lease_drift="$((
  $(awk -F= '/^r851_lease_drift=/ { print $2 }' "$cross_log")
  + $(awk -F= '/^r851_randomized_lease_drift=/ { print $2 }' "$random_log")
))"
[ "$cross_failures" -eq 0 ]
[ "$random_failures" -eq 0 ]
[ "$duplicate_response_creates" -eq 0 ]
[ "$duplicate_interrupts" -eq 0 ]
[ "$duplicate_clears" -eq 0 ]
[ "$stale_side_effects" -eq 0 ]
[ "$false_self_interrupts" -eq 0 ]
[ "$false_persistence_writes" -eq 0 ]
[ "$false_history_writes" -eq 0 ]
[ "$false_memory_writes" -eq 0 ]
[ "$false_relationship_changes" -eq 0 ]
[ "$false_growth_writes" -eq 0 ]
[ "$generation_drift" -eq 0 ]
[ "$lease_drift" -eq 0 ]

provider_audio_frame="$work_dir/provider-audio-frame.txt"
awk '
  /struct RealtimeBrainAudioFrame/ { active = 1 }
  active { print }
  active && /^}/ { exit }
' "$production_contract" > "$provider_audio_frame"
[ -s "$provider_audio_frame" ]
[ "$(rg -c '^[[:space:]]+let ' "$provider_audio_frame")" -eq 6 ]
rg -Fqx 'nonisolated struct RealtimeBrainAudioFrame: Sendable, Equatable {' \
  "$provider_audio_frame"
rg -Fqx '    let identity: RealtimeBrainSessionIdentity' \
  "$provider_audio_frame"
rg -Fqx '    let sequence: UInt64' "$provider_audio_frame"
rg -Fqx '    let timestampNanoseconds: UInt64' "$provider_audio_frame"
rg -Fqx '    let format: RealtimeBrainAudioFormat' "$provider_audio_frame"
rg -Fqx '    let provenance: RealtimeBrainAudioProvenance' \
  "$provider_audio_frame"
rg -Fqx '    let bytes: Data' "$provider_audio_frame"
if rg -qi \
    'sourceGate|userActivity|nearEnd|playback|turn[ P]olicy|completion|backchannel|semantic|response[ A]uthority|[Aa]coustic|[Ee]ligibility' \
    "$provider_audio_frame"; then
  printf 'r851_provider_pcm_contract=FAIL\n' >&2
  exit 1
fi
printf 'r851_provider_pcm_contract=PASS\n'

if rg -q \
    'beginRealtimeBrainGenerationTransition|finishRealtimeBrainGenerationInterruption|SessionStore|NarrativeMemory|passiveBackchannel|realtimeUserTurnDisposition|claimRealtimeResidentBrainInterruptionDecision' \
    "$qwen_adapter"; then
  printf 'r851_qwen_authority_neutrality=FAIL\n' >&2
  exit 1
fi
printf 'r851_qwen_authority_neutrality=PASS\n'

rg -q 'static let minimumNearEndRMS = 0.012' \
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
rg -q 'maximumSourceGateNonUserHangoverFrames = 20' \
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
rg -U -q \
  'private static let realtimeUtteranceCompletionWindowNanoseconds:\n[[:space:]]*UInt64 = 800_000_000' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
rg -q 'residualTailWindowNanoseconds: UInt64 = 500_000_000' \
  "$production_contract"
rg -q 'expect\(confirmedToClear <= 50_000_000,' \
  "$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift"
rg -q 'expect\(firstToClear <= 200_000_000,' \
  "$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift"
printf 'r851_frozen_thresholds=PASS\n'

production_after="$(production_digest)"
status_after="$(git -C "$repo_root" status --porcelain=v1)"
fingerprint_after="$(worktree_fingerprint)"
head_after="$(git -C "$repo_root" rev-parse HEAD)"
branch_after="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || true)"
if [ "$production_before" != "$expected_production_digest" ] \
    || [ "$production_after" != "$expected_production_digest" ]; then
  printf 'r851_production_digest_expected=%s\n' \
    "$expected_production_digest" >&2
  printf 'r851_production_digest_observed_before=%s\n' \
    "$production_before" >&2
  printf 'r851_production_digest_observed_after=%s\n' \
    "$production_after" >&2
  printf 'r851_production_mutations=1\n' >&2
  exit 1
fi
if [ "$status_before" != "$status_after" ] \
    || [ "$fingerprint_before" != "$fingerprint_after" ] \
    || [ "$head_before" != "$head_after" ] \
    || [ "$branch_before" != "$branch_after" ]; then
  printf 'r851_repository_mutation=FAIL\n' >&2
  exit 1
fi

printf 'r851_cross_node_scenarios=%s\n' "$cross_node_scenarios"
printf 'r851_cross_node_failures=%s\n' "$cross_failures"
printf 'r851_randomized_race_iterations=%s\n' "$random_iterations"
printf 'r851_randomized_race_failures=%s\n' "$random_failures"
printf 'r851_key_suite_repeat_runs=%s\n' "$repeat_runs"
printf 'r851_key_suite_repeat_failures=0\n'
printf 'r851_duplicate_response_creates=%s\n' \
  "$duplicate_response_creates"
printf 'r851_duplicate_interrupts=%s\n' "$duplicate_interrupts"
printf 'r851_duplicate_clears=%s\n' "$duplicate_clears"
printf 'r851_stale_generation_side_effects=%s\n' "$stale_side_effects"
printf 'r851_false_self_interrupts=%s\n' "$false_self_interrupts"
printf 'r851_false_persistence_writes=%s\n' "$false_persistence_writes"
printf 'r851_false_history_writes=%s\n' "$false_history_writes"
printf 'r851_false_memory_writes=%s\n' "$false_memory_writes"
printf 'r851_false_relationship_changes=%s\n' \
  "$false_relationship_changes"
printf 'r851_false_growth_writes=%s\n' "$false_growth_writes"
printf 'r851_generation_drift=%s\n' "$generation_drift"
printf 'r851_lease_drift=%s\n' "$lease_drift"
printf 'r851_harness_timeouts=0\n'
printf 'r851_production_mutations=0\n'
printf 'r851_production_digest_before=%s\n' "$production_before"
printf 'r851_production_digest_after=%s\n' "$production_after"
printf 'r851_repository_mutation=PASS\n'
printf 'realtime_total_regression=PASS\n'
