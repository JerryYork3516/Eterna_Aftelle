#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-qwen-asr.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/qwen_asr_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/qwen_asr_tests/QwenRealtimeASRAdapterTests.swift" \
  -o "$build_dir/qwen_realtime_asr_tests"

"$build_dir/qwen_realtime_asr_tests"

adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeASRAdapter.swift"
if rg -n 'requestResidentReply|routeResidentReply|startTTS|TTSProvider|LanguageModelProvider' \
  "$adapter"; then
  echo "qwen_asr_formal_turn_boundary=FAIL"
  exit 1
fi

rg -q 'ProviderCredentialReading' "$adapter"
rg -q 'RealtimeWebSocketTransport' "$adapter"
rg -q 'convert48kMonoTo16k' "$adapter"
rg -q 'asrProvider: asrProvider' \
  "$repo_root/apps/macos/RuntimeCore/QwenRealtimeRuntimeComposition.swift"

echo "qwen_asr_transport_reuse=PASS"
echo "qwen_asr_credential_reuse=PASS"
echo "qwen_asr_audio_boundary=PASS"
echo "qwen_asr_formal_turn_boundary=PASS"
