#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-qwen-realtime-brain.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
swiftc \
  -D DEBUG \
  -parse-as-library \
  -default-isolation MainActor \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/qwen_realtime_resident_brain_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/qwen_realtime_resident_brain_tests/QwenRealtimeResidentBrainAdapterTests.swift" \
  -o "$build_dir/qwen_realtime_resident_brain_tests"

fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
if [ ! -f "$fixture" ]; then
  echo "qwen_realtime_resident_brain_fixture=BLOCKED"
  exit 1
fi

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/qwen_realtime_resident_brain_tests" "$fixture"

adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift"
for symbol in \
  QwenRealtimeResidentBrainAdapter \
  qwen3.5-omni-plus-realtime \
  session.created \
  session.update \
  session.updated \
  response.done \
  residentSemanticFinal \
  input_audio_buffer.append \
  conversation.item.create \
  response.cancel; do
  rg -q "$symbol" "$adapter"
done

if rg -n \
  'input_audio_buffer\.commit|session\.finish|OpenAI-Beta|X-DashScope-WorkSpace' \
  "$adapter"; then
  echo "qwen_realtime_resident_brain_wire_scope=FAIL"
  exit 1
fi

rg -q 'realtimeResidentBrainProvider:' \
  "$repo_root/apps/macos/RuntimeCore/QwenRealtimeRuntimeComposition.swift"
rg -q 'ProviderKeychainStore.qwenKeyRef' \
  "$repo_root/apps/macos/Aftelle/AppController.swift"
rg -q 'QwenRealtimeResidentBrainAdapter.swift in Sources' \
  "$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

echo "qwen_realtime_resident_brain_fixture=PASS"
echo "qwen_realtime_resident_brain_wire_scope=PASS"
echo "qwen_realtime_resident_brain_runtime_seam=PASS"
echo "qwen_realtime_resident_brain_credential_scope=PASS"
echo "qwen_realtime_resident_brain_real_websocket_test=NOT_RUN_HUMAN_GATE"
