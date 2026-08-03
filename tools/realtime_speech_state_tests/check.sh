#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-realtime-speech-state.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechInteraction.swift" \
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechAudioPayload.swift" \
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechProviderProfile.swift" \
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechEvent.swift" \
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechProvider.swift" \
  "$repo_root/apps/macos/RuntimeCore/RealtimeSpeechStateMachine.swift" \
  "$repo_root/tools/realtime_speech_state_tests/RealtimeSpeechStateMachineTests.swift" \
  -o "$build_dir/realtime_speech_state_tests"

"$build_dir/realtime_speech_state_tests"

if rg -n 'StepFun|stepfun|AVFoundation|SwiftUI' \
  "$repo_root/apps/macos/RuntimeCore/RealtimeSpeechStateMachine.swift"; then
  echo "realtime_speech_vendor_neutrality=FAIL"
  exit 1
fi

if rg -n 'RealtimeSpeechStateMachine\(' \
  "$repo_root/apps/macos/Aftelle/AppController.swift" \
  "$repo_root/apps/macos/RuntimeCore/StepFunRealtimeAdapter.swift"; then
  echo "realtime_speech_runtime_owner=FAIL"
  exit 1
fi

if [ "$(rg -c 'RealtimeSpeechStateMachine\(' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift")" -ne 1 ]; then
  echo "realtime_speech_runtime_owner=FAIL"
  exit 1
fi

if ! diff -u \
  <(git -C "$repo_root" show f9db8c794b6a9a73bbc9aa1ad925303a5016e26f:apps/macos/RuntimeCore/RuntimeCore.swift | rg '^\s*public') \
  <(rg '^\s*public' "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"); then
  echo "realtime_speech_public_api=FAIL"
  exit 1
fi

if [ "$(rg -c 'RealtimeSpeechStateMachine.swift in Sources' \
  "$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj")" -ne 2 ]; then
  echo "realtime_speech_target_membership=FAIL"
  exit 1
fi

for field in state turn reason completedTurns turnDetection guardTimeout lastError path; do
  rg -q "particleDebug.realtimeSpeech.${field}" \
    "$repo_root/apps/macos/Aftelle/ContentView.swift"
  rg -q "particleDebug.realtimeSpeech.${field}" \
    "$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings"
  rg -q "particleDebug.realtimeSpeech.${field}" \
    "$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"
done

echo "realtime_speech_vendor_neutrality=PASS"
echo "realtime_speech_runtime_owner=PASS"
echo "realtime_speech_public_api=PASS"
echo "realtime_speech_target_membership=PASS"
echo "realtime_speech_debug_diagnostics=PASS"
