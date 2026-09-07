#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="${1:---self-test}"
if [ "$#" -gt 0 ]; then shift; fi
if [ "$mode" != --live ] && [ "$mode" != --self-test ] && [ "$mode" != --build-only ] && [ "$mode" != --authorize-keychain ] && [ "$mode" != --check-keychain ]; then
  echo 'continuous_error=mode' >&2; exit 2
fi
rounds=10
seconds=300
pcm=""
upload=false
interaction=false
inject_error=false
terminal_responses=false
reassociate_round=""
omit_preview=false
require_active_cancel=false
pcm_start=""
pcm_end=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --allow-audio-upload) upload=true; shift ;;
    --allow-keychain-interaction) interaction=true; shift ;;
    --inject-response-error) inject_error=true; shift ;;
    --terminal-responses) terminal_responses=true; shift ;;
    --omit-provisional-preview) omit_preview=true; shift ;;
    --require-active-cancel) require_active_cancel=true; shift ;;
    --rounds|--seconds|--pcm|--reassociate-at-round|--pcm-start-ms|--pcm-end-ms)
      if [ "$#" -lt 2 ]; then echo 'continuous_error=arguments' >&2; exit 2; fi
      case "$1" in
        --rounds) rounds="$2" ;;
        --seconds) seconds="$2" ;;
        --pcm) pcm="$2" ;;
        --reassociate-at-round) reassociate_round="$2" ;;
        --pcm-start-ms) pcm_start="$2" ;;
        --pcm-end-ms) pcm_end="$2" ;;
      esac
      shift 2 ;;
    *) echo 'continuous_error=arguments' >&2; exit 2 ;;
  esac
done
if [[ ! "$rounds" =~ ^([1-9]|1[0-5])$ ]] || [[ ! "$seconds" =~ ^[1-9][0-9]{0,2}$ ]] || (( seconds > 600 )); then
  echo 'continuous_error=budget' >&2; exit 2
fi
for boundary in "$pcm_start" "$pcm_end"; do
  if [ -n "$boundary" ] && [[ ! "$boundary" =~ ^(0|[1-9][0-9]{0,4})$ ]]; then
    echo 'continuous_error=invalid_pcm_range' >&2; exit 2
  fi
done
if [ -n "$reassociate_round" ] && { [[ ! "$reassociate_round" =~ ^([1-9]|1[0-5])$ ]] || (( reassociate_round > rounds )); }; then
  echo 'continuous_error=invalid_reassociation_round' >&2; exit 2
fi
if [ "$omit_preview" = true ] && [ -z "$reassociate_round" ]; then
  echo 'continuous_error=missing_reassociation_round' >&2; exit 2
fi
if [ "$mode" = --live ] && { [ "$upload" != true ] || [ ! -f "$pcm" ]; }; then
  echo 'continuous_error=audio_upload_not_authorized_or_missing_pcm' >&2; exit 2
fi
if [ "$mode" = --self-test ] && { [ "$upload" = true ] || [ "$interaction" = true ] || [ -n "$pcm" ]; }; then
  echo 'continuous_error=self_test_external_access' >&2; exit 2
fi
if [ "$mode" = --build-only ] && { [ "$upload" = true ] || [ "$interaction" = true ] || [ -n "$pcm" ]; }; then
  echo 'continuous_error=build_only_external_access' >&2; exit 2
fi
if [ "$mode" = --authorize-keychain ] && { [ "$interaction" != true ] || [ "$upload" = true ] || [ -n "$pcm" ] || [ -z "${AFTELLE_PROBE_SIGNING_IDENTITY:-}" ]; }; then
  echo 'continuous_error=authorization_requires_signed_probe_and_local_consent' >&2; exit 2
fi
if [ "$mode" = --check-keychain ] && { [ "$interaction" = true ] || [ "$upload" = true ] || [ -n "$pcm" ] || [ -z "${AFTELLE_PROBE_SIGNING_IDENTITY:-}" ]; }; then
  echo 'continuous_error=credential_check_requires_signed_probe_without_interaction_or_upload' >&2; exit 2
fi
if [ "$mode" = --live ] && { [ "$inject_error" = true ] || [ "$terminal_responses" = true ] || [ -n "$reassociate_round" ] || [ "$omit_preview" = true ]; }; then
  echo 'continuous_error=live_fault_injection_forbidden' >&2; exit 2
fi
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-qwen-continuous.XXXXXX")"
echo "continuous_artifacts=$work_dir"
fingerprint() {
  {
    git -C "$repo_root" rev-parse HEAD
    git -C "$repo_root" status --porcelain=v1
    git -C "$repo_root" diff --binary HEAD
    while IFS= read -r -d '' source; do
      shasum -a 256 "$repo_root/$source"
    done < <(git -C "$repo_root" ls-files --others --exclude-standard -z)
  } | shasum -a 256
}
git -C "$repo_root" rev-parse HEAD > "$work_dir/revision.txt"
fingerprint > "$work_dir/worktree-before.sha256"
mkdir -p "$work_dir/runtime-home" "$work_dir/module-cache"
export CFFIXED_USER_HOME="$work_dir/runtime-home"
export CLANG_MODULE_CACHE_PATH="$work_dir/module-cache"
export SWIFT_MODULECACHE_PATH="$work_dir/module-cache"
runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
host_sources=(
  ParticleCore/ParticleTuning.swift ParticleCore/ResidentVisualIntent.swift
  ParticleCore/ParticleStateController.swift AppModels.swift ProviderKeychainStore.swift
  MacSpeechAcousticEchoHost.swift MacSpeechAudioCapture.swift MacSpeechDeviceMonitor.swift
  MacSpeechAudioHost.swift MacSpeechPCMPlaybackBuffer.swift MacSpeechAudioOutputPlayer.swift
  MacSpeechAudioOutputHost.swift MacSpeechRealtimeBrainInputBridge.swift MacSpeechRealtimeBrainOutputBridge.swift
  MacSpeechNativeInputBridge.swift MacSpeechNativeOutputBridge.swift RealtimeSpeechPresentationMapper.swift AppController.swift
)
for index in "${!host_sources[@]}"; do host_sources[$index]="$repo_root/apps/macos/Aftelle/${host_sources[$index]}"; done
source "$repo_root/tools/qwen_live_receive_probe/probe-build.sh"
probe_build continuous "$work_dir/build.log" -D DEBUG -D AFTELLE_CONTINUOUS_PROBE -parse-as-library -warn-concurrency -strict-concurrency=complete \
  -framework AVFoundation -framework CoreAudio -framework AppKit -framework Security -framework UniformTypeIdentifiers \
  "${runtime_sources[@]}" "${host_sources[@]}" \
  "$repo_root/tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift" \
  "$repo_root/tools/qwen_realtime_resident_brain_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift" \
  "$repo_root/tools/qwen_live_receive_probe/ProbeEvidence.swift" \
  "$repo_root/tools/qwen_live_receive_probe/RealQwenReceiveProbe.swift" \
  "$repo_root/tools/qwen_live_receive_probe/ContinuousQwenProbe.swift"
ln -s "$PROBE_BINARY" "$work_dir/probe"
if [ "$mode" = --build-only ]; then
  fingerprint > "$work_dir/worktree-after.sha256"
  cmp "$work_dir/worktree-before.sha256" "$work_dir/worktree-after.sha256"
  echo 'continuous_build_only=PASS online=NOT_RUN keychain_read=NOT_RUN'
  exit 0
fi
arguments=("$mode" --rounds "$rounds" --seconds "$seconds" --output "$work_dir"
  --fixture "$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident")
if [ "$upload" = true ]; then arguments+=(--allow-audio-upload --pcm "$pcm"); fi
if [ "$interaction" = true ]; then arguments+=(--allow-keychain-interaction); fi
if [ "$inject_error" = true ]; then arguments+=(--inject-response-error); fi
if [ "$terminal_responses" = true ]; then arguments+=(--terminal-responses); fi
if [ -n "$reassociate_round" ]; then arguments+=(--reassociate-at-round "$reassociate_round"); fi
if [ "$omit_preview" = true ]; then arguments+=(--omit-provisional-preview); fi
if [ "$require_active_cancel" = true ]; then arguments+=(--require-active-cancel); fi
if [ -n "$pcm_start" ]; then arguments+=(--pcm-start-ms "$pcm_start"); fi
if [ -n "$pcm_end" ]; then arguments+=(--pcm-end-ms "$pcm_end"); fi
set +e
/usr/bin/perl "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" "$seconds" \
  "$PROBE_BINARY" "${arguments[@]}" > "$work_dir/run.log" 2>&1
status=$?
set -e
cat "$work_dir/run.log"
if [ "$status" -eq 124 ]; then echo 'continuous_watchdog=TIMEOUT first_report_preserved=true' | tee "$work_dir/watchdog.txt"; fi
fingerprint > "$work_dir/worktree-after.sha256"
cmp "$work_dir/worktree-before.sha256" "$work_dir/worktree-after.sha256"
echo 'continuous_repository_mutation=PASS'
echo "continuous_exit=$status"
exit "$status"
