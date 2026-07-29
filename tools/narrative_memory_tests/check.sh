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

expected_sha=84098dd0d6d116572b5282ec2d07417e43d1c6cc161f07cff3beb306f9e60cf2
before_sha=$(shasum -a 256 "$dr_path" | awk '{print $1}')
before_size=$(stat -f '%z' "$dr_path")
before_mtime=$(stat -f '%m' "$dr_path")

if [ "$before_sha" != "$expected_sha" ]; then
  printf 'narrative-memory-tests: unexpected DR SHA-256\n' >&2
  exit 1
fi

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
xcrun --sdk macosx swiftc \
  -D DEBUG \
  -parse-as-library \
  -module-cache-path "$build_dir/module-cache" \
  -target arm64-apple-macos14.0 \
  "${runtime_sources[@]}" \
  "$script_dir/NarrativeMemoryTests.swift" \
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
  "$repo_root/apps/macos/RuntimeCore/TraceRecorder.swift" \
  "$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"; then
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
  "$repo_root/apps/macos/RuntimeCore/DRLoader.swift" \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"; then
  printf 'narrative-memory-tests: automatic store integration found\n' >&2
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

if git -C "$repo_root" diff --name-only \
  | rg -q 'apps/macos/Aftelle/(AppModels|AppController|ContentView|ParticleCore)|ProviderRouter|ExecutionEngine|SessionStore|MemoryController|RelationshipStateStore|TraceRecorder'; then
  printf 'narrative-memory-tests: forbidden A1 file changed\n' >&2
  exit 1
fi

printf 'narrative-memory-tests: DR fingerprint unchanged\n'
printf 'narrative-memory-tests: source boundary checks ok\n'
