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
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechNativeInputBridge.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechNativeOutputBridge.swift"
  "$repo_root/apps/macos/Aftelle/AppController.swift"
)

swiftc \
  -D DEBUG \
  -parse-as-library \
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

fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
test -f "$fixture"
runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/native_speech_input_bridge_tests" "$fixture"

bridge="$repo_root/apps/macos/Aftelle/MacSpeechNativeInputBridge.swift"
host="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
orchestration="$repo_root/apps/macos/Aftelle/AppModels.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
engine="$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift"
router="$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"
adapter="$repo_root/apps/macos/RuntimeCore/StepFunRealtimeAdapter.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

test "$(rg -c 'Task \{' "$bridge")" -eq 1
if rg -q 'typealias SendFrame = @MainActor' "$bridge"; then
  echo "native_speech_input_bridge_main_actor_path=FAIL"
  exit 1
fi
rg -q 'maxCount: MacSpeechAudioInputFormat.frameCapacity' "$bridge"
rg -q 'static let frameCapacity = 8' "$host"
rg -q 'frames.removeFirst\(\)' "$host"
echo "native_speech_input_bridge_bounded_task=PASS"
echo "native_speech_input_bridge_main_actor_path=PASS"

rg -q 'orchestrationKernel.startNativeSpeechInput' "$controller"
rg -q 'orchestrationKernel.sendNativeSpeechInput' "$controller"
rg -q 'runtimeCore.startNativeSpeechInput' "$orchestration"
rg -q 'runtimeCore.sendNativeSpeechInput' "$orchestration"
rg -q 'executionEngine.sendNativeSpeechAudio' "$runtime"
rg -q 'providerRouter.sendNativeSpeechAudio' "$engine"
rg -q 'nativeSpeechProvider.send' "$router"
rg -q 'codec.audioAppend' "$adapter"
echo "native_speech_input_bridge_execution_chain=PASS"

if rg -q 'StepFun|ProviderRouter|ExecutionEngine|RuntimeCore' "$bridge"; then
  echo "native_speech_input_bridge_host_ownership=FAIL"
  exit 1
fi
if rg -q 'StepFunRealtimeAdapter|ProviderRouter' "$controller"; then
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
