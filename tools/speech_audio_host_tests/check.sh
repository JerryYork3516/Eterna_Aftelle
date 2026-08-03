#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-speech-audio-host.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

host="$repo_root/apps/macos/Aftelle/MacSpeechAudioHost.swift"
tests="$repo_root/tools/speech_audio_host_tests/MacSpeechAudioHostTests.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"
entitlements="$repo_root/apps/macos/Aftelle/Aftelle.entitlements"
content_view="$repo_root/apps/macos/Aftelle/ContentView.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"

swiftc \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  -framework AVFoundation \
  "$host" \
  "$tests" \
  -o "$build_dir/speech_audio_host_tests"

"$build_dir/speech_audio_host_tests"

if rg -q 'import AVFoundation' "$repo_root/apps/macos/RuntimeCore" -g '*.swift'; then
  echo "speech_audio_host_runtime_boundary=FAIL"
  exit 1
fi
echo "speech_audio_host_runtime_boundary=PASS"

unexpected_avfoundation="$(rg -l 'AVCaptureDevice|AVAuthorizationStatus|import AVFoundation' \
  "$repo_root/apps/macos/Aftelle" -g '*.swift' | rg -v '/MacSpeechAudioHost\.swift$' || true)"
if [ -n "$unexpected_avfoundation" ]; then
  echo "speech_audio_host_avfoundation_boundary=FAIL"
  printf '%s\n' "$unexpected_avfoundation"
  exit 1
fi
echo "speech_audio_host_avfoundation_boundary=PASS"

if rg -q 'AVAudioEngine|AVCaptureSession|installTap|inputNode|requestRecordPermission' \
  "$host" "$controller" "$content_view"; then
  echo "speech_audio_host_scope=FAIL"
  exit 1
fi
echo "speech_audio_host_scope=PASS"

if rg -q 'RuntimeCore|ExecutionEngine|ProviderRouter|NativeSpeechProvider|StepFun|Keychain|DRLoader|MemoryController|SessionStore' \
  "$host"; then
  echo "speech_audio_host_ownership=FAIL"
  exit 1
fi
echo "speech_audio_host_ownership=PASS"

rg -q 'controller\.requestMicrophoneAuthorization' "$content_view"
rg -q 'speechAudioHost\.requestMicrophoneAuthorization' "$controller"
if rg -q 'AVCaptureDevice|requestAccess|AVFoundation' "$content_view" "$controller"; then
  echo "speech_audio_host_debug_ui_boundary=FAIL"
  exit 1
fi
echo "speech_audio_host_debug_ui_boundary=PASS"

plutil -lint "$entitlements" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' \
  "$entitlements" | rg -q '^true$'
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' \
  "$entitlements" | rg -q '^true$'
test "$(rg -c 'INFOPLIST_KEY_NSMicrophoneUsageDescription = ' "$project")" -eq 2
echo "speech_audio_host_project_permission=PASS"

test "$(rg -c '/\* MacSpeechAudioHost\.swift( in Sources)? \*/' "$project")" -eq 4
echo "speech_audio_host_target_membership=PASS"

for strings_file in \
  "$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings" \
  "$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"; do
  plutil -lint "$strings_file" >/dev/null
  for key in \
    particleDebug.audioHost.title \
    particleDebug.audioHost.authorization \
    particleDebug.audioHost.state \
    particleDebug.audioHost.requestPermission; do
    rg -Fq "\"$key\"" "$strings_file"
  done
done
echo "speech_audio_host_localization=PASS"
