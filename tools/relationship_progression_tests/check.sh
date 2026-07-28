#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s /path/to/resident.digital_resident\n' "$0" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
dr_path=$1
build_dir=$(mktemp -d /private/tmp/aftelle-relationship-tests.XXXXXX)
runtime_home="$build_dir/runtime-home"
trap 'rm -rf "$build_dir"' EXIT

mkdir -p "$runtime_home"

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
xcrun --sdk macosx swiftc \
  -D DEBUG \
  -parse-as-library \
  -module-cache-path "$build_dir/module-cache" \
  -target arm64-apple-macos14.0 \
  "${runtime_sources[@]}" \
  "$script_dir/RelationshipProgressionTests.swift" \
  -o "$build_dir/relationship-progression-tests"

CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/relationship-progression-tests" "$dr_path"

required_d1_fields=(
  relationshipStageID
  relationshipEvidenceIDs
  relationshipDecision
  relationshipReason
)

for field in "${required_d1_fields[@]}"; do
  if ! rg -q "$field" \
    "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift" \
    "$repo_root/apps/macos/Aftelle/AppModels.swift" \
    "$repo_root/apps/macos/Aftelle/AppController.swift" \
    "$repo_root/apps/macos/Aftelle/ContentView.swift"; then
    printf 'relationship-progression-tests: missing D1 field %s\n' \
      "$field" >&2
    exit 1
  fi
done

if sed -n '/struct RuntimeOrchestrationInteraction:/,/^}/p' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift" \
  | rg -q '(inputText|replyText|systemPrompt|apiKey|rawResponse|memoryValue)'; then
  printf 'relationship-progression-tests: D1 contains body fields\n' >&2
  exit 1
fi

if rg -q '(RuntimeRelationship|relationship_progression|relationshipStage)' \
  "$repo_root/apps/macos/RuntimeCore/SessionStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/MemoryController.swift" \
  "$repo_root/apps/macos/RuntimeCore/TraceRecorder.swift"; then
  printf 'relationship-progression-tests: relationship state leaked into existing store, memory, or trace\n' >&2
  exit 1
fi

if rg -q 'relationshipProgression.*Picker|Picker.*relationshipProgression' \
  "$repo_root/apps/macos/Aftelle/ContentView.swift"; then
  printf 'relationship-progression-tests: manual stage selector found\n' >&2
  exit 1
fi

for strings_file in \
  "$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings" \
  "$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"; do
  if ! rg -q '"relationshipProgression.debug.reset"' "$strings_file"; then
    printf 'relationship-progression-tests: missing debug localization\n' >&2
    exit 1
  fi
done

printf 'relationship-progression-tests: source boundary checks ok\n'
