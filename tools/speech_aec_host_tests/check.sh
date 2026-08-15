#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-speech-aec-host.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

aec_host="$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
capture="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
tests="$repo_root/tools/speech_aec_host_tests/MacSpeechAcousticEchoHostTests.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

swiftc \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  -framework AVFoundation \
  "$aec_host" \
  "$capture" \
  "$tests" \
  -o "$build_dir/speech_aec_host_tests"

"$build_dir/speech_aec_host_tests"

rg -q 'case webRTCAEC3' "$aec_host"
rg -q 'case appleVoiceProcessing' "$aec_host"
rg -q 'case halfDuplexFallback' "$aec_host"
rg -q 'speech-aec-processing' "$aec_host"
rg -q 'fifoSampleCapacity' "$aec_host"
rg -q 'outputNode\.presentationLatency' "$capture"
if rg -q 'playerNode\.outputPresentationLatency' "$capture"; then
  echo "speech_aec_hardware_delay=FAIL"
  exit 1
fi
echo "speech_aec_hardware_delay=PASS"
rg -q 'presentationLatency' "$capture"
rg -q 'playbackCompleted\(\)' "$aec_host" "$capture"
rg -q 'playerNode\.installTap' "$capture"
rg -q 'processRenderedOutput' "$capture"
rg -q 'renderConversionFailed' "$aec_host" "$capture"
if rg -q 'mainMixerNode\.installTap' "$capture"; then
  echo "speech_aec_render_source=FAIL"
  exit 1
fi
echo "speech_aec_render_source=PASS"
test "$(rg -c 'acousticEchoHost\.processRender' "$capture")" -eq 1
if rg -q 'scheduledOutputFrameCount|queuedOutputFrameCount' "$aec_host" "$capture"; then
  echo "speech_aec_render_timing=FAIL"
  exit 1
fi
echo "speech_aec_render_timing=PASS"
capture_aec_line="$(rg -n -m 1 'acousticEchoHost\.processCapture' "$capture" | cut -d: -f1)"
capture_packet_line="$(rg -n -m 1 'outputConverter\.convert' "$capture" | cut -d: -f1)"
test "$capture_aec_line" -lt "$capture_packet_line"
if rg -q 'Task\.sleep|usleep|Thread\.sleep' "$aec_host" "$capture"; then
  echo "speech_aec_timer_fallback=FAIL"
  exit 1
fi
echo "speech_aec_host_contract=PASS"

test "$(rg -c '/\* MacSpeechAcousticEchoHost\.swift( in Sources)? \*/' "$project")" -eq 4
test "$(rg -c '/\* MacSpeechWebRTCAECProcessor\.swift( in Sources)? \*/' "$project")" -eq 4
test "$(rg -c '/\* AftelleAECBridge\.mm( in Sources)? \*/' "$project")" -eq 4
test "$(rg -c '/\* WebRTCAEC3\.xcframework( in Frameworks)? \*/' "$project")" -eq 4
rg -q 'SWIFT_OBJC_BRIDGING_HEADER = "Aftelle-Bridging-Header.h"' "$project"
echo "speech_aec_target_membership=PASS"

if rg -q 'RuntimeCore|ProviderRouter|Qwen|SessionStore|MemoryController|Keychain|transcript|pcm16Bytes' "$aec_host"; then
  echo "speech_aec_host_ownership_privacy=FAIL"
  exit 1
fi
echo "speech_aec_host_ownership_privacy=PASS"
