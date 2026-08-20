#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-a7-regression.XXXXXX")"
suite_log="$work_dir/suites.log"
status_before="$(git -C "$repo_root" status --porcelain=v1)"
suite_count=0

trap 'rm -rf "$work_dir"' EXIT

run_suite() {
  local name="$1"
  shift
  printf 'a7_suite_start=%s\n' "$name"
  "$@" 2>&1 | tee -a "$suite_log"
  suite_count=$((suite_count + 1))
  printf 'a7_suite_pass=%s\n' "$name"
}

run_suite speech_route \
  "$repo_root/tools/speech_route_tests/check.sh"
run_suite active_brain_lease \
  "$repo_root/tools/active_brain_lease_tests/check.sh"
run_suite realtime_brain_contract \
  "$repo_root/tools/realtime_resident_brain_contract_tests/check.sh"
run_suite qwen_realtime_brain \
  "$repo_root/tools/qwen_realtime_resident_brain_tests/check.sh"
run_suite realtime_brain_context \
  "$repo_root/tools/realtime_resident_brain_context_tests/check.sh"
run_suite qwen_asr \
  "$repo_root/tools/qwen_asr_tests/check.sh"
run_suite qwen_tts \
  "$repo_root/tools/qwen_tts_tests/check.sh"
run_suite realtime_context \
  "$repo_root/tools/realtime_speech_context_tests/check.sh"
run_suite native_input_bridge \
  "$repo_root/tools/native_speech_input_bridge_tests/check.sh"
run_suite realtime_subtitle \
  "$repo_root/tools/realtime_speech_subtitle_tests/check.sh"
run_suite speech_audio_output \
  "$repo_root/tools/speech_audio_output_tests/check.sh"
run_suite speech_audio_host \
  "$repo_root/tools/speech_audio_host_tests/check.sh"
run_suite speech_aec_host \
  "$repo_root/tools/speech_aec_host_tests/check.sh"
run_suite native_cancellation \
  "$repo_root/tools/native_speech_cancellation_tests/check.sh"
run_suite narrative_memory \
  "$repo_root/tools/narrative_memory_tests/check.sh" "$fixture"
run_suite relationship_progression \
  "$repo_root/tools/relationship_progression_tests/check.sh" "$fixture"
run_suite runtime_expression \
  "$repo_root/tools/runtime_expression_tests/check.sh" "$fixture"
run_suite particle_expression \
  env AFTELLE_ALLOW_RUNTIME_CORE_CHANGES=1 \
  "$repo_root/tools/particle_expression_tests/check.sh" "$fixture"

if rg -n 'LanguageModelProvider' \
  "$repo_root/apps/macos/RuntimeCore" -g '*.swift'; then
  printf 'a7_duplicate_language_model_provider=FAIL\n' >&2
  exit 1
fi
if rg -n \
  '\b(class|struct|actor|protocol|enum) Speech(Runtime|Memory|History)\b' \
  "$repo_root/apps/macos" -g '*.swift'; then
  printf 'a7_parallel_speech_subsystem=FAIL\n' >&2
  exit 1
fi
printf 'a7_runtime_ownership_audit=PASS\n'

git -C "$repo_root" diff --check
"$repo_root/tools/architecture_guard/check.sh"
"$repo_root/tools/secret_guard/check.sh"

xcodebuild \
  -project "$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj" \
  -scheme Aftelle \
  -configuration Debug \
  -derivedDataPath "$work_dir/derived-data" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

status_after="$(git -C "$repo_root" status --porcelain=v1)"
if [ "$status_before" != "$status_after" ]; then
  printf 'a7_repository_mutation=FAIL\n' >&2
  exit 1
fi

assertion_count="$({
  awk -F= '/_checks=[0-9]+$/ { total += $2 } END { print total + 0 }' \
    "$suite_log"
  awk '/checks passed$/ { total += $(NF - 2) } END { print total + 0 }' \
    "$suite_log"
} | awk '{ total += $1 } END { print total + 0 }')"

printf 'a7_regression_top_level_suites=%d\n' "$suite_count"
printf 'a7_regression_test_entrypoints=21\n'
printf 'a7_regression_assertions=%s\n' "$assertion_count"
printf 'a7_repository_mutation=PASS\n'
printf 'a7_clean_build=PASS\n'
printf 'stage7_5_11_a7_regression=PASS\n'
