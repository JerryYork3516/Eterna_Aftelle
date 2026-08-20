#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r6-voice.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
if [ ! -f "$fixture" ]; then
  printf 'realtime_voice_binding_fixture=BLOCKED\n' >&2
  exit 1
fi

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
module_cache="$build_dir/module-cache"
mkdir -p "$module_cache"
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULECACHE_PATH="$module_cache" \
swiftc \
  -D DEBUG \
  -parse-as-library \
  -default-isolation MainActor \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/realtime_voice_binding_tests/RealtimeVoiceBindingTests.swift" \
  -o "$build_dir/realtime_voice_binding_tests"

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/realtime_voice_binding_tests" "$fixture"

contract="$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift"
test_source="$repo_root/tools/realtime_voice_binding_tests/RealtimeVoiceBindingTests.swift"

for symbol in \
  RuntimeVoiceProviderIdentity \
  RuntimeVoiceBindingMode \
  RuntimeVoiceBindingFallback \
  RuntimeVoiceBinding \
  activeRealtimeProvider \
  providerDefault \
  providerPrivateVoiceReference \
  voiceBinding; do
  rg -q "$symbol" "$contract"
done

if rg -n \
  'Tina|Cherry|Maia|R6PrivateDefaultVoice|defaultProviderVoiceID|voice_id|tts_profile' \
  "$contract"; then
  printf 'realtime_voice_binding_provider_neutral_contract=FAIL\n' >&2
  exit 1
fi

if ! rg -q 'defaultProviderVoiceID' "$adapter" \
  || ! rg -q 'resolveVoiceBinding' "$adapter"; then
  printf 'realtime_voice_binding_adapter_private_resolution=FAIL\n' >&2
  exit 1
fi

if rg -n \
  'RuntimeVoiceBinding|providerPrivateVoiceReference|defaultProviderVoiceID' \
  "$repo_root/docs/dr_contract_v0_3.md" \
  "$repo_root/apps/macos/RuntimeCore" -g '*Store*.swift'; then
  printf 'realtime_voice_binding_dr_store_boundary=FAIL\n' >&2
  exit 1
fi

if git -C "$repo_root" diff --name-only HEAD -- \
  docs/dr_contract_v0_3.md \
  ':(glob)apps/macos/RuntimeCore/*Store*.swift' \
  | rg -q .; then
  printf 'realtime_voice_binding_dr_store_mutation=FAIL\n' >&2
  exit 1
fi

if rg -ni \
  'URLSession|URLSessionWebSocketTask|SystemRealtimeWebSocketTransport|NWConnection' \
  "$test_source"; then
  printf 'realtime_voice_binding_network_dependency=FAIL\n' >&2
  exit 1
fi

binding_owners="$(rg -l \
  'nonisolated struct RuntimeVoiceBinding:' \
  "$repo_root/apps/macos/RuntimeCore" -g '*.swift')"
if [ "$binding_owners" != "$contract" ]; then
  printf 'realtime_voice_binding_runtime_ownership=FAIL\n' >&2
  printf '%s\n' "$binding_owners" >&2
  exit 1
fi

if rg -n \
  '\b(class|struct|actor|protocol|enum)[[:space:]]+Voice(Runtime|Brain|Session|Memory|History)\b' \
  "$repo_root/apps/macos" -g '*.swift'; then
  printf 'realtime_voice_binding_parallel_voice_system=FAIL\n' >&2
  exit 1
fi

printf 'realtime_voice_binding_fixture=PASS\n'
printf 'realtime_voice_binding_provider_neutral_contract=PASS\n'
printf 'realtime_voice_binding_adapter_private_resolution=PASS\n'
printf 'realtime_voice_binding_dr_store_boundary=PASS\n'
printf 'realtime_voice_binding_dr_store_mutation=PASS\n'
printf 'realtime_voice_binding_runtime_ownership=PASS\n'
printf 'realtime_voice_binding_parallel_voice_system=PASS\n'
printf 'realtime_voice_binding_network_dependency=ZERO\n'
