#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-native-speech.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

sources=(
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechInteraction.swift"
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechAudioPayload.swift"
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechProviderProfile.swift"
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechEvent.swift"
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechProvider.swift"
)

swiftc \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  "${sources[@]}" \
  "$repo_root/tools/native_speech_tests/NativeSpeechContractTests.swift" \
  -o "$build_dir/native_speech_contract_tests"

"$build_dir/native_speech_contract_tests"

adapter_sources=(
  "${sources[@]}"
  "$repo_root/apps/macos/RuntimeCore/RealtimeSpeechContextProjection.swift"
  "$repo_root/apps/macos/RuntimeCore/RealtimeWebSocketTransport.swift"
  "$repo_root/apps/macos/RuntimeCore/StepFunRealtimeCodec.swift"
  "$repo_root/apps/macos/RuntimeCore/StepFunRealtimeAdapter.swift"
)

swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  "${adapter_sources[@]}" \
  "$repo_root/tools/native_speech_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/native_speech_tests/StepFunRealtimeAdapterTests.swift" \
  -o "$build_dir/stepfun_realtime_adapter_tests"

"$build_dir/stepfun_realtime_adapter_tests"

qwen_adapter_sources=(
  "${sources[@]}"
  "$repo_root/apps/macos/RuntimeCore/RealtimeSpeechContextProjection.swift"
  "$repo_root/apps/macos/RuntimeCore/RealtimeWebSocketTransport.swift"
  "$repo_root/apps/macos/RuntimeCore/QwenRealtimeCodec.swift"
  "$repo_root/apps/macos/RuntimeCore/QwenRealtimeAdapter.swift"
)

swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  "${qwen_adapter_sources[@]}" \
  "$repo_root/tools/native_speech_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/native_speech_tests/QwenRealtimeAdapterTests.swift" \
  -o "$build_dir/qwen_realtime_adapter_tests"

"$build_dir/qwen_realtime_adapter_tests"

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
swiftc \
  -D DEBUG \
  -parse-as-library \
  "${runtime_sources[@]}" \
  "$repo_root/tools/native_speech_tests/NativeSpeechRuntimeIntegrationTests.swift" \
  -o "$build_dir/native_speech_runtime_integration_tests"

fixture_path="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
if [ ! -f "$fixture_path" ]; then
  echo "native_speech_fixed_fixture=BLOCKED"
  exit 1
fi

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/native_speech_runtime_integration_tests" "$fixture_path"

if rg -n 'StepFun|URLSessionWebSocket|AVFoundation|AVAudioEngine' "${sources[@]}"; then
  echo "native_speech_vendor_neutrality=FAIL"
  exit 1
fi

if ! rg -q '^nonisolated protocol ProviderCredentialReading: Sendable' \
  "$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"; then
  echo "native_speech_credential_sendable=FAIL"
  exit 1
fi

unexpected_stepfun=$(rg -l 'StepFun|stepfun' \
  "$repo_root/apps/macos/RuntimeCore" \
  -g '*.swift' \
  | rg -v '/StepFunRealtime(Adapter|Codec|RuntimeComposition)\.swift$' || true)
if [ -n "$unexpected_stepfun" ]; then
  echo "native_speech_provider_leakage=FAIL"
  printf '%s\n' "$unexpected_stepfun"
  exit 1
fi

unexpected_qwen=$(rg -l 'Qwen|qwen' \
  "$repo_root/apps/macos/RuntimeCore" \
  -g '*.swift' \
  | rg -v '/QwenRealtime(Adapter|Codec|RuntimeComposition)\.swift$' || true)
if [ -n "$unexpected_qwen" ]; then
  echo "native_speech_qwen_provider_leakage=FAIL"
  printf '%s\n' "$unexpected_qwen"
  exit 1
fi

echo "native_speech_vendor_neutrality=PASS"
echo "native_speech_provider_leakage=PASS"
echo "native_speech_qwen_provider_leakage=PASS"

for operation in start send receive cancel close; do
  if ! rg -q "executionEngine\.${operation}NativeSpeech" \
    "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"; then
    echo "native_speech_execution_gate=FAIL:$operation"
    exit 1
  fi
done

rg -q 'executionEngine\.updateNativeSpeechContext' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
rg -q 'providerRouter\.updateNativeSpeechContext' \
  "$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift"
rg -q 'contextProvider\.updateContext' \
  "$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"

echo "native_speech_execution_gate=PASS"

"$repo_root/tools/native_speech_tests/check_a4_1.sh"
