#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r4-context.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
if [ ! -f "$fixture" ]; then
  printf 'realtime_resident_brain_context_fixture=BLOCKED\n' >&2
  exit 1
fi

protected_sources=(
  apps/macos/RuntimeCore/DRLoader.swift
  apps/macos/RuntimeCore/SessionStore.swift
  apps/macos/RuntimeCore/MemoryController.swift
  apps/macos/RuntimeCore/NarrativeMemoryStore.swift
  apps/macos/RuntimeCore/RelationshipStateStore.swift
)
if ! git -C "$repo_root" diff --quiet -- "${protected_sources[@]}"; then
  printf 'realtime_resident_brain_context_schema_scope=FAIL\n' >&2
  exit 1
fi

provider_sources=(
  "$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
  "$repo_root/apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift"
)
if rg -n \
  '\b(DRLoader|LoadedDR|SessionStore|MemoryController|NarrativeMemoryStore|RelationshipStateStore)\b|payload\.|schema_version|\.digital_resident' \
  "${provider_sources[@]}"; then
  printf 'realtime_resident_brain_context_provider_store_access=FAIL\n' >&2
  exit 1
fi

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
xcrun --sdk macosx swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/realtime_resident_brain_context_tests/RealtimeResidentBrainContextTests.swift" \
  -o "$build_dir/realtime_resident_brain_context_tests"

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/realtime_resident_brain_context_tests" "$fixture"

printf 'realtime_resident_brain_context_schema_scope=PASS\n'
printf 'realtime_resident_brain_context_provider_store_access=PASS\n'
