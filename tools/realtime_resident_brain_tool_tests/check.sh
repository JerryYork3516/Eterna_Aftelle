#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r5-tool.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
if [ ! -f "$fixture" ]; then
  printf 'realtime_resident_brain_tool_fixture=BLOCKED\n' >&2
  exit 1
fi

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
swiftc \
  -D DEBUG \
  -parse-as-library \
  -default-isolation MainActor \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/realtime_resident_brain_tool_tests/RealtimeResidentBrainToolTests.swift" \
  -o "$build_dir/realtime_resident_brain_tool_tests"

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/realtime_resident_brain_tool_tests" "$fixture"

provider_sources=(
  "$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
  "$repo_root/apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift"
)
if rg -n \
  '\bRuntimeTool(Executing|PermissionResolving)\b|configureRuntimeTools|handleRuntimeToolCall' \
  "${provider_sources[@]}"; then
  printf 'realtime_resident_brain_tool_provider_execution_bypass=FAIL\n' >&2
  exit 1
fi

if rg -n \
  '\b(class|struct|actor|protocol|enum)[[:space:]]+(RealtimeResidentBrain|NativeSpeech|Speech|Voice)Tool(Registry|PermissionResolver|Executor)\b' \
  "$repo_root/apps/macos/RuntimeCore" -g '*.swift'; then
  printf 'realtime_resident_brain_tool_parallel_system=FAIL\n' >&2
  exit 1
fi

if rg -ni \
  'urlsession|websocket|https?://' \
  "$repo_root/tools/realtime_resident_brain_tool_tests/RealtimeResidentBrainToolTests.swift"; then
  printf 'realtime_resident_brain_tool_network_dependency=FAIL\n' >&2
  exit 1
fi

printf 'realtime_resident_brain_tool_fixture=PASS\n'
printf 'realtime_resident_brain_tool_runtime_ownership=PASS\n'
printf 'realtime_resident_brain_tool_provider_execution_bypass=PASS\n'
printf 'realtime_resident_brain_tool_parallel_system=PASS\n'
printf 'realtime_resident_brain_tool_network_dependency=ZERO\n'
