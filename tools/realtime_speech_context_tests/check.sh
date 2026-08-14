#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-realtime-context.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
xcrun --sdk macosx swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  -module-cache-path "$build_dir/module-cache" \
  -target arm64-apple-macos14.0 \
  "${runtime_sources[@]}" \
  "$repo_root/tools/realtime_speech_context_tests/RealtimeSpeechContextProjectionTests.swift" \
  -o "$build_dir/realtime-speech-context-tests"

fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
test -f "$fixture"
runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/realtime-speech-context-tests" "$fixture"

projection="$repo_root/apps/macos/RuntimeCore/RealtimeSpeechContextProjection.swift"
compiler="$repo_root/apps/macos/RuntimeCore/RealtimeSpeechContextCompiler.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
engine="$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift"
router="$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"
adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeAdapter.swift"
codec="$repo_root/apps/macos/RuntimeCore/QwenRealtimeCodec.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

if rg -q 'Qwen|AVFoundation|AVAudio|SwiftUI|URLSession|Store|DRLoader|keyRef|secret' \
  "$projection" "$compiler"; then
  echo "realtime_speech_context_vendor_neutrality=FAIL"
  exit 1
fi
echo "realtime_speech_context_vendor_neutrality=PASS"

rg -q 'compiledResidentDialogueContext' "$runtime"
rg -q 'executionEngine.updateNativeSpeechContext' "$runtime"
rg -q 'providerRouter.updateNativeSpeechContext' "$engine"
rg -q 'contextProvider.updateContext' "$router"
rg -q 'codec.contextUpdate' "$adapter"
rg -q '"instructions": instructions' "$codec"
echo "realtime_speech_context_execution_chain=PASS"

if rg -q 'DRLoader|SessionStore|MemoryStore|NarrativeMemoryStore|RelationshipStateStore' \
  "$adapter" "$codec"; then
  echo "realtime_speech_context_adapter_boundary=FAIL"
  exit 1
fi
echo "realtime_speech_context_adapter_boundary=PASS"

if rg -q 'instructions|RealtimeSpeechContextProjection' \
  "$repo_root/apps/macos/RuntimeCore/SessionStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/MemoryController.swift" \
  "$repo_root/apps/macos/RuntimeCore/TraceRecorder.swift"; then
  echo "realtime_speech_context_persistence_leak=FAIL"
  exit 1
fi
echo "realtime_speech_context_persistence_leak=PASS"

if rg -q 'session\.update|prefix_padding_ms|semantic_vad|qwen3\.5|Maia' \
  "$projection" "$compiler"; then
  echo "realtime_speech_context_provider_field_leak=FAIL"
  exit 1
fi
echo "realtime_speech_context_provider_field_leak=PASS"

test "$(rg -c '/\* RealtimeSpeechContextProjection\.swift( in Sources)? \*/' "$project")" -eq 4
test "$(rg -c '/\* RealtimeSpeechContextCompiler\.swift( in Sources)? \*/' "$project")" -eq 4
echo "realtime_speech_context_target_membership=PASS"
