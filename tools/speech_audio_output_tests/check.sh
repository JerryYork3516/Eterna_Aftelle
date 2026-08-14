#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-speech-audio-output.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

buffer="$repo_root/apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift"
capture="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
player="$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift"
host="$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputHost.swift"
device_monitor="$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
fake="$repo_root/tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift"
tests="$repo_root/tools/speech_audio_output_tests/MacSpeechAudioOutputHostTests.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

swiftc \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  -framework AVFoundation \
  -framework CoreAudio \
  "$capture" \
  "$buffer" \
  "$device_monitor" \
  "$player" \
  "$host" \
  "$fake" \
  "$tests" \
  -o "$build_dir/speech_audio_output_tests"

"$build_dir/speech_audio_output_tests"

test "$(rg -c '/\* MacSpeechPCMPlaybackBuffer\.swift( in Sources)? \*/' "$project")" -eq 4
test "$(rg -c '/\* MacSpeechAudioOutputPlayer\.swift( in Sources)? \*/' "$project")" -eq 4
test "$(rg -c '/\* MacSpeechAudioOutputHost\.swift( in Sources)? \*/' "$project")" -eq 4
echo "speech_audio_output_target_membership=PASS"

if rg -q 'Qwen|ProviderRouter|ExecutionEngine|RuntimeCore|NativeSpeechEvent|SessionStore|MemoryController|ParticleCore' \
  "$buffer" "$player" "$host"; then
  echo "speech_audio_output_ownership=FAIL"
  exit 1
fi
echo "speech_audio_output_ownership=PASS"

if rg -q 'AVFoundation|AVAudioEngine|AVAudioPlayerNode|AVAudioConverter' \
  "$repo_root/apps/macos/RuntimeCore" -g '*.swift'; then
  echo "speech_audio_output_runtime_boundary=FAIL"
  exit 1
fi
echo "speech_audio_output_runtime_boundary=PASS"

test "$(rg -n 'AVAudioEngine\(\)' "$capture" "$player" | wc -l)" -eq 1
rg -q 'SystemMacSpeechVoiceProcessingEngine' "$capture" "$player"
if rg -q 'private var engine: AVAudioEngine|let engine = AVAudioEngine\(\)' "$player"; then
  echo "speech_audio_output_shared_voice_processing_graph=FAIL"
  exit 1
fi
echo "speech_audio_output_shared_voice_processing_graph=PASS"

rg -q 'func finishPlayback\(\)' "$player"
rg -q 'player\.finishPlayback\(\)' "$host"
rg -q 'formal playback completion releases the input echo gate once' "$tests"
rg -q 'temporary queue gap keeps the input echo gate active' "$tests"
echo "speech_audio_output_echo_gate_lifecycle=PASS"

if rg -q 'base64EncodedString|Bearer |print\(.*payload|String\(data:.*bytes' \
  "$repo_root/apps/macos/Aftelle/AppController.swift" \
  "$repo_root/apps/macos/Aftelle/ContentView.swift"; then
  echo "speech_audio_output_debug_privacy=FAIL"
  exit 1
fi
echo "speech_audio_output_debug_privacy=PASS"

if rg -q 'outputAudio|receiveNativeSpeechEvent|QwenRealtimeAdapter' \
  "$host" "$player" "$buffer"; then
  echo "speech_audio_output_a2_boundary=FAIL"
  exit 1
fi
echo "speech_audio_output_a2_boundary=PASS"

rg -q 'startupBufferCount: 2' "$buffer"
rg -q 'startupBufferDurationNanoseconds: 500_000_000' "$buffer"
rg -q 'scheduleAheadCount: 4' "$buffer"
rg -q 'applyingResumeFadeIn' "$player"
rg -q 'resetForPlaybackGeneration' "$player" "$host"
if rg -q 'applyingPlaybackSafety|maximumPlaybackPeak|maximumPlaybackRMS' "$player"; then
  echo "speech_audio_output_bit_exact=FAIL"
  exit 1
fi
rg -q 'clearForAcceptedSpeechStart' "$host"
rg -q 'clearScheduledPlayback' "$player"
rg -q 'scheduleAvailableChunks' "$host"
rg -q 'withCheckedContinuation' "$host"
if rg -q 'return fail\(\.queueFull\)' "$host"; then
  echo "speech_audio_output_pressure=FAIL"
  exit 1
fi
rg -q 'func finishProviderResponse\(' "$host"
rg -q 'generation expectedGeneration: UInt64' "$host"
rg -q 'providerResponseFinished' "$host"
rg -q 'case playbackStalled' "$host"
rg -q 'case playbackResumed' "$host"
rg -q 'consumerWatchdogNanoseconds' "$host"
echo "speech_audio_output_continuous_playback=PASS"
echo "speech_audio_output_pressure=PASS"
echo "speech_audio_output_bit_exact=PASS"
