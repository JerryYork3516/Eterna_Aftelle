#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s /path/to/resident.digital_resident\n' "$0" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
dr_path=$1
build_dir=$(mktemp -d /private/tmp/aftelle-narrative-tests.XXXXXX)
runtime_home="$build_dir/runtime-home"
trap 'rm -rf "$build_dir"' EXIT

mkdir -p "$runtime_home"

expected_sha=f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881
before_sha=$(shasum -a 256 "$dr_path" | awk '{print $1}')
before_size=$(stat -f '%z' "$dr_path")
before_mtime=$(stat -f '%m' "$dr_path")

if [ "$before_sha" != "$expected_sha" ]; then
  printf 'narrative-memory-tests: unexpected DR SHA-256\n' >&2
  exit 1
fi

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
test_sources=("$script_dir"/*.swift)
xcrun --sdk macosx swiftc \
  -D DEBUG \
  -parse-as-library \
  -module-cache-path "$build_dir/module-cache" \
  -target arm64-apple-macos14.0 \
  "${runtime_sources[@]}" \
  "${test_sources[@]}" \
  -o "$build_dir/narrative-memory-tests"

CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/narrative-memory-tests" "$dr_path"

after_sha=$(shasum -a 256 "$dr_path" | awk '{print $1}')
after_size=$(stat -f '%z' "$dr_path")
after_mtime=$(stat -f '%m' "$dr_path")

if [ "$before_sha" != "$after_sha" ] \
  || [ "$before_size" != "$after_size" ] \
  || [ "$before_mtime" != "$after_mtime" ]; then
  printf 'narrative-memory-tests: DR fingerprint changed\n' >&2
  exit 1
fi

if ! rg -U -q \
  'data\.write\([[:space:]]+to: storeURL\(residentID: snapshot\.residentID\),[[:space:]]+options: \[\.atomic\]' \
  "$repo_root/apps/macos/RuntimeCore/NarrativeMemoryStore.swift"; then
  printf 'narrative-memory-tests: atomic write missing\n' >&2
  exit 1
fi

if rg -q '(NarrativeMemory|narrative_memory)' \
  "$repo_root/apps/macos/RuntimeCore/SessionStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/MemoryController.swift" \
  "$repo_root/apps/macos/RuntimeCore/RelationshipStateStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/TraceRecorder.swift"; then
  printf 'narrative-memory-tests: feature leaked into existing subsystem\n' >&2
  exit 1
fi

if rg -q '^public .*NarrativeMemory' \
  "$repo_root/apps/macos/RuntimeCore/DRLoader.swift" \
  "$repo_root/apps/macos/RuntimeCore/NarrativeMemoryStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"; then
  printf 'narrative-memory-tests: public Runtime API changed\n' >&2
  exit 1
fi

if rg -q 'NarrativeMemoryStore' \
  "$repo_root/apps/macos/RuntimeCore/DRLoader.swift"; then
  printf 'narrative-memory-tests: loader/store coupling found\n' >&2
  exit 1
fi

if rg -q '(full_dialogue|provider_request|raw_response|api_key|internal_reasoning|trace)' \
  <(
    sed -n \
      '/struct RuntimeNarrativeMemoryRecord:/,/^}/p' \
      "$repo_root/apps/macos/RuntimeCore/NarrativeMemoryStore.swift"
  ); then
  printf 'narrative-memory-tests: forbidden record field found\n' >&2
  exit 1
fi

if rg -q '(summary|userInput|replyText|systemPrompt|apiKey|rawResponse|memoryValue)' \
  <(
    sed -n \
      '/struct RuntimeNarrativeMemoryDecision:/,/^}/p' \
      "$repo_root/apps/macos/RuntimeCore/NarrativeMemoryStore.swift"
    sed -n \
      '/struct RuntimeOrchestrationInteraction:/,/^}/p' \
      "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
    sed -n \
      '/struct RuntimeNarrativeMemoryOrchestrationMetadata:/,/^}/p' \
      "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
  ); then
  printf 'narrative-memory-tests: D1 decision metadata contains sensitive field\n' >&2
  exit 1
fi

for field in \
  retrievalCount \
  retrievedMemoryIDs \
  affectedMemoryIDs \
  userOperation \
  decision \
  reason; do
  if ! sed -n \
    '/struct RuntimeNarrativeMemoryOrchestrationMetadata:/,/^}/p' \
    "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift" \
    | rg -q "$field"; then
    printf 'narrative-memory-tests: missing A3 D1 field %s\n' \
      "$field" >&2
    exit 1
  fi
done

if git -C "$repo_root" diff --unified=0 -- \
  'apps/macos/Aftelle/AppModels.swift' \
  'apps/macos/Aftelle/AppController.swift' \
  'apps/macos/Aftelle/ContentView.swift' \
  'apps/macos/Aftelle/ParticleCore*' \
  'apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj' \
  'apps/macos/RuntimeCore/SessionStore.swift' \
  'apps/macos/RuntimeCore/MemoryController.swift' \
  'apps/macos/RuntimeCore/RelationshipStateStore.swift' \
  'apps/macos/RuntimeCore/TraceRecorder.swift' \
  | rg -q '^[+-][^+-].*(NarrativeMemory|narrative_memory)'; then
  printf 'narrative-memory-tests: forbidden A2 file changed\n' >&2
  exit 1
fi

printf 'narrative-memory-tests: DR fingerprint unchanged\n'
printf 'narrative-memory-tests: source boundary checks ok\n'
