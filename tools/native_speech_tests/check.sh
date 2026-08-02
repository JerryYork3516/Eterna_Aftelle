#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-native-speech.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

sources=(
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechInteraction.swift"
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechAudioPayload.swift"
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechProviderProfile.swift"
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechEvent.swift"
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechProvider.swift"
)

swiftc \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  "${sources[@]}" \
  "$repo_root/tools/native_speech_tests/NativeSpeechContractTests.swift" \
  -o "$build_dir/native_speech_contract_tests"

"$build_dir/native_speech_contract_tests"

if rg -n 'StepFun|URLSessionWebSocket|AVFoundation|AVAudioEngine' "${sources[@]}"; then
  echo "native_speech_vendor_neutrality=FAIL"
  exit 1
fi

echo "native_speech_vendor_neutrality=PASS"
