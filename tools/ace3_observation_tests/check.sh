#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$repo_root/.build/ace3-step2a"
mkdir -p "$build_dir"
sources=(
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioObservation.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioObservationTypes.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
  "$repo_root/tools/ace3_observation_tests/AudioObservationTests.swift"
  "$repo_root/tools/ace3_observation_tests/AudioObservationFixtures.swift"
)
swiftc -D DEBUG -D AFTELLE_AUDIO_OBSERVATION -D AUDIO_OBSERVATION_TESTING \
  -parse-as-library -warn-concurrency -strict-concurrency=complete \
  -framework AVFoundation -framework CoreAudio "${sources[@]}" \
  -o "$build_dir/step2a-tests"
"$build_dir/step2a-tests" "$build_dir"

if [[ "${1:-}" == "--production-aec" ]]; then
  bridge="$build_dir/DerivedData/Build/Intermediates.noindex/Aftelle.build/Debug/Aftelle.build/Objects-normal/arm64/AftelleAECBridge.o"
  test -f "$bridge"
  swiftc -target arm64-apple-macosx26.5 -D DEBUG -D AFTELLE_AUDIO_OBSERVATION -D AUDIO_OBSERVATION_TESTING \
    -D AFTELLE_WEBRTC_AEC3 -parse-as-library -framework AVFoundation -framework CoreAudio \
    -import-objc-header "$repo_root/apps/macos/Aftelle/Aftelle-Bridging-Header.h" \
    "${sources[@]}" "$repo_root/apps/macos/Aftelle/MacSpeechWebRTCAECProcessor.swift" \
    "$bridge" "$repo_root/third_party/webrtc_aec3/WebRTCAEC3.xcframework/macos-arm64_x86_64/libWebRTCAEC3.a" \
    -lc++ -o "$build_dir/step2a-production-aec-tests"
  "$build_dir/step2a-production-aec-tests" "$build_dir"
fi
