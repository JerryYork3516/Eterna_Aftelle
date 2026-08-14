#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-speech-audio-host.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

host="$repo_root/apps/macos/Aftelle/MacSpeechAudioHost.swift"
capture="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
player="$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift"
device_monitor="$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
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
  -framework CoreAudio \
  "$capture" \
  "$device_monitor" \
  "$host" \
  "$tests" \
  -o "$build_dir/speech_audio_host_tests"

"$build_dir/speech_audio_host_tests"

if rg -q 'import AVFoundation' "$repo_root/apps/macos/RuntimeCore" -g '*.swift'; then
  echo "speech_audio_host_runtime_boundary=FAIL"
  exit 1
fi
echo "speech_audio_host_runtime_boundary=PASS"

unexpected_audio_api="$(rg -l 'AVCaptureDevice|AVAuthorizationStatus|AVAudioEngine|AVAudioConverter|import AVFoundation|import CoreAudio|AudioObjectGetPropertyData' \
  "$repo_root/apps/macos/Aftelle" -g '*.swift' \
  | rg -v '/MacSpeechAudio(Host|Capture)\.swift$' \
  | rg -v '/MacSpeechAudioOutputPlayer\.swift$' \
  | rg -v '/MacSpeechDeviceMonitor\.swift$' || true)"
if [ -n "$unexpected_audio_api" ]; then
  echo "speech_audio_host_avfoundation_boundary=FAIL"
  printf '%s\n' "$unexpected_audio_api"
  exit 1
fi
echo "speech_audio_host_avfoundation_boundary=PASS"

if ! rg -q 'AVAudioEngine' "$capture" \
  || ! rg -q 'AVAudioConverter' "$capture" \
  || ! rg -q 'installTap' "$capture" \
  || ! rg -q 'AudioObjectAddPropertyListenerBlock' "$device_monitor"; then
  echo "speech_audio_host_scope=FAIL"
  exit 1
fi
echo "speech_audio_host_scope=PASS"

voice_processing_line="$(rg -n -m 1 'try configureIfNeeded\(\)' "$capture" | cut -d: -f1)"
input_tap_line="$(rg -n -m 1 'inputNode\.installTap' "$capture" | cut -d: -f1)"
if [ "$voice_processing_line" -ge "$input_tap_line" ] \
  || ! rg -q 'setVoiceProcessingEnabled\(true\)' "$capture" \
  || ! rg -q 'inputNode\.isVoiceProcessingEnabled' "$capture" \
  || ! rg -q 'engine\.outputNode\.isVoiceProcessingEnabled' "$capture" \
  || ! rg -q 'voiceProcessingUnavailable = "voice_processing_unavailable"' "$capture"; then
  echo "speech_audio_host_voice_processing=FAIL"
  exit 1
fi
echo "speech_audio_host_voice_processing=PASS"

test "$(rg -n 'AVAudioEngine\(\)' "$capture" "$player" | wc -l)" -eq 1
test "$(rg -c 'let speechAudioEngine = SystemMacSpeechVoiceProcessingEngine\(\)' "$controller")" -eq 2
test "$(rg -c 'SystemMacSpeechAudioCapture\(' "$controller")" -eq 2
test "$(rg -c 'SystemMacSpeechAudioOutputPlayer\(' "$controller")" -eq 2
rg -q 'engine\.attach\(playerNode\)' "$capture"
rg -q 'engine\.connect\(' "$capture"
player_attach_line="$(rg -n -m 1 'engine\.attach\(playerNode\)' "$capture" | cut -d: -f1)"
voice_processing_enable_line="$(rg -n -m 1 'setVoiceProcessingEnabled\(true\)' "$capture" | cut -d: -f1)"
test "$player_attach_line" -lt "$voice_processing_enable_line"
rg -q 'audioEngine\.scheduleOutput' "$player"
echo "speech_audio_host_shared_voice_processing_graph=PASS"

rg -q 'setMutedSpeechActivityEventListener' "$capture"
rg -q 'isVoiceProcessingInputMuted = true' "$capture"
rg -q 'event == \.started' "$capture"
rg -q 'func finishOutputPlayback\(\)' "$capture"
rg -q 'unmuteInput\(\)' "$capture"
echo "speech_audio_host_playback_echo_gate=PASS"

rg -q 'packetDurationMilliseconds = 20' "$capture"
rg -q 'packetSampleCount = 480' "$capture"
rg -q 'packetByteCount = 960' "$capture"
rg -q 'frameCapacity = 25' "$capture"
rg -q 'MacSpeechPCM16Packetizer' "$capture" "$tests"
echo "speech_audio_host_packetization=PASS"

if rg -q 'RuntimeCore|ExecutionEngine|ProviderRouter|NativeSpeechProvider|Qwen|Keychain|DRLoader|MemoryController|SessionStore' \
  "$host" "$capture" "$device_monitor"; then
  echo "speech_audio_host_ownership=FAIL"
  exit 1
fi
echo "speech_audio_host_ownership=PASS"

rg -q 'controller\.requestMicrophoneAuthorization' "$content_view"
rg -q 'speechAudioHost\.requestMicrophoneAuthorization' "$controller"
rg -q 'controller\.startSpeechAudioCapture' "$content_view"
rg -q 'speechAudioHost\.startCapture' "$controller"
rg -q 'controller\.stopSpeechAudioCapture' "$content_view"
rg -q 'speechAudioHost\.stopCapture' "$controller"
if rg -q 'AVCaptureDevice|requestAccess|AVFoundation|AVAudioEngine|CoreAudio|AudioObject' "$content_view" "$controller"; then
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
test "$(rg -c '/\* MacSpeechAudioCapture\.swift( in Sources)? \*/' "$project")" -eq 4
test "$(rg -c '/\* MacSpeechDeviceMonitor\.swift( in Sources)? \*/' "$project")" -eq 4
echo "speech_audio_host_target_membership=PASS"

for strings_file in \
  "$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings" \
  "$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"; do
  plutil -lint "$strings_file" >/dev/null
  for key in \
    particleDebug.audioHost.title \
    particleDebug.audioHost.authorization \
    particleDebug.audioHost.state \
    particleDebug.audioHost.requestPermission \
    particleDebug.audioHost.startCapture \
    particleDebug.audioHost.stopCapture \
    particleDebug.audioHost.inputDevice \
    particleDebug.audioHost.outputDevice \
    particleDebug.audioHost.outputFormat \
    particleDebug.audioHost.generatedFrames \
    particleDebug.audioHost.droppedFrames; do
    rg -Fq "\"$key\"" "$strings_file"
  done
done
echo "speech_audio_host_localization=PASS"

if rg -q 'sendNativeSpeechAudio|send\(audio:|input_audio_buffer\.append' \
  "$host" "$capture" "$device_monitor" "$controller" "$content_view"; then
  echo "speech_audio_host_provider_isolation=FAIL"
  exit 1
fi
echo "speech_audio_host_provider_isolation=PASS"
