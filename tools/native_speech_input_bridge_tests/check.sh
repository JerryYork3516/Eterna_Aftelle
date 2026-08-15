#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-native-input-bridge.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
host_sources=(
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleTuning.swift"
  "$repo_root/apps/macos/Aftelle/ParticleCore/ResidentVisualIntent.swift"
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleStateController.swift"
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleSimulation.swift"
  "$repo_root/apps/macos/Aftelle/AppModels.swift"
  "$repo_root/apps/macos/Aftelle/ProviderKeychainStore.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechNativeInputBridge.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechNativeOutputBridge.swift"
  "$repo_root/apps/macos/Aftelle/RealtimeSpeechPresentationMapper.swift"
  "$repo_root/apps/macos/Aftelle/AppController.swift"
)

swiftc \
  -D DEBUG \
  -parse-as-library \
  -default-isolation MainActor \
  -warn-concurrency \
  -strict-concurrency=complete \
  -framework AVFoundation \
  -framework CoreAudio \
  -framework AppKit \
  -framework Security \
  -framework UniformTypeIdentifiers \
  "${runtime_sources[@]}" \
  "${host_sources[@]}" \
  "$repo_root/tools/native_speech_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/native_speech_input_bridge_tests/NativeSpeechInputBridgeTests.swift" \
  -o "$build_dir/native_speech_input_bridge_tests"

fixture="${1:-$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident}"
test -f "$fixture"
runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/native_speech_input_bridge_tests" "$fixture"

bridge="$repo_root/apps/macos/Aftelle/MacSpeechNativeInputBridge.swift"
host="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
content_view="$repo_root/apps/macos/Aftelle/ContentView.swift"
localization_en="$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings"
localization_zh="$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"
orchestration="$repo_root/apps/macos/Aftelle/AppModels.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
engine="$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift"
router="$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"
adapter="$repo_root/apps/macos/RuntimeCore/QwenRealtimeAdapter.swift"
transport="$repo_root/apps/macos/RuntimeCore/URLSessionRealtimeWebSocketTransport.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

test "$(rg -c 'Task \{' "$bridge")" -eq 1
if rg -q 'typealias SendFrame = @MainActor' "$bridge"; then
  echo "native_speech_input_bridge_main_actor_path=FAIL"
  exit 1
fi
rg -q 'maxCount: MacSpeechAudioInputFormat.frameCapacity' "$bridge"
rg -q 'static let frameCapacity = 25' "$host"
rg -q 'static let packetSampleCount = 480' "$host"
rg -q 'static let packetByteCount = 960' "$host"
rg -q 'frames.removeFirst\(\)' "$host"
echo "native_speech_input_bridge_bounded_task=PASS"
echo "native_speech_input_bridge_main_actor_path=PASS"

rg -q 'orchestrationKernel.startNativeSpeechInput' "$controller"
rg -q 'orchestrationKernel.sendNativeSpeechInput' "$controller"
rg -q 'runtimeCore.startNativeSpeechInput' "$orchestration"
rg -q 'runtimeCore.sendNativeSpeechInput' "$orchestration"
rg -q 'nonisolated func sendNativeSpeechInput' "$runtime"
rg -q 'executionEngine.sendNativeSpeechAudio' "$runtime"
rg -q 'nonisolated func sendNativeSpeechAudio' "$engine"
rg -q 'providerRouter.sendNativeSpeechAudio' "$engine"
rg -q 'nonisolated func sendNativeSpeechAudio' "$router"
rg -q 'nativeSpeechProvider.send' "$router"
rg -q 'codec.audioAppend' "$adapter"
echo "native_speech_input_bridge_execution_chain=PASS"

rg -q 'controller.startNativeSpeechInputBridge' "$content_view"
rg -q 'startNativeSpeechBridge:' "$content_view"
rg -q 'await startNativeSpeechBridge()' "$content_view"
rg -q 'particleDebug.audioHost.startBridge' "$localization_en" "$localization_zh"
echo "native_speech_input_bridge_debug_entry=PASS"

if rg -q 'Qwen|ProviderRouter|ExecutionEngine|RuntimeCore' "$bridge"; then
  echo "native_speech_input_bridge_host_ownership=FAIL"
  exit 1
fi
if rg -q 'QwenRealtimeAdapter|ProviderRouter' \
  "$controller"; then
  echo "native_speech_input_bridge_controller_boundary=FAIL"
  exit 1
fi
if rg -q 'AVFoundation|CoreAudio|AVAudio' "$runtime" "$engine" "$router"; then
  echo "native_speech_input_bridge_runtime_platform_boundary=FAIL"
  exit 1
fi
echo "native_speech_input_bridge_architecture=PASS"

if rg -q 'input_audio_buffer.commit|response.create|response.audio.delta|AVAudioPlayer|AVAudioPlayerNode' \
  "$bridge" "$controller" "$orchestration" "$runtime"; then
  echo "native_speech_input_bridge_scope=FAIL"
  exit 1
fi
echo "native_speech_input_bridge_scope=PASS"

test "$(rg -c '/\* NativeSpeechInputFrame\.swift( in Sources)? \*/' "$project")" -eq 4
test "$(rg -c '/\* MacSpeechNativeInputBridge\.swift( in Sources)? \*/' "$project")" -eq 4
echo "native_speech_input_bridge_target_membership=PASS"

rg -q 'maximumPendingWrites = 8' "$transport"
rg -q 'BoundedRealtimeWebSocketWriteWindow' "$transport"
rg -q 'beginCloseAndDrain' "$transport"
rg -Fq 'task.send(message) {' "$transport"
if rg -q 'try await task.send' "$transport"; then
  echo "native_speech_input_bridge_write_window=FAIL"
  exit 1
fi
echo "native_speech_input_bridge_write_window=PASS"
