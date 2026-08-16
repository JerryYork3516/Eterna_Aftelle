#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-qwen-tts.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/qwen_asr_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/qwen_tts_tests/QwenRealtimeTTSAdapterTests.swift" \
  -o "$build_dir/qwen_realtime_tts_tests"

"$build_dir/qwen_realtime_tts_tests"

adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeTTSAdapter.swift"
if rg -n 'MacSpeechAudioOutput|Particle|DialogueHistory|startSpeechRouteTTS|LanguageModelProvider' \
  "$adapter"; then
  echo "qwen_tts_a5_boundary=FAIL"
  exit 1
fi

rg -q 'ProviderCredentialReading' "$adapter"
rg -q 'RealtimeWebSocketTransport' "$adapter"
rg -q 'canonicalResponseText' "$adapter"
rg -q 'ttsProvider: ttsProvider' \
  "$repo_root/apps/macos/RuntimeCore/QwenRealtimeRuntimeComposition.swift"

echo "qwen_tts_transport_reuse=PASS"
echo "qwen_tts_credential_reuse=PASS"
echo "qwen_tts_canonical_text_boundary=PASS"
echo "qwen_tts_a5_boundary=PASS"
