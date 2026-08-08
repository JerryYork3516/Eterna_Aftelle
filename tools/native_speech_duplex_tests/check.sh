#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-native-duplex.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
host_sources=(
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleTuning.swift"
  "$repo_root/apps/macos/Aftelle/ParticleCore/ResidentVisualIntent.swift"
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleStateController.swift"
  "$repo_root/apps/macos/Aftelle/AppModels.swift"
  "$repo_root/apps/macos/Aftelle/ProviderKeychainStore.swift"
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
  "$repo_root/tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift"
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
  "$repo_root/tools/native_speech_duplex_tests/NativeSpeechDuplexTests.swift" \
  -o "$build_dir/native_speech_duplex_tests"

fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
test -f "$fixture"
runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/native_speech_duplex_tests" "$fixture"

output_bridge="$repo_root/apps/macos/Aftelle/MacSpeechNativeOutputBridge.swift"
input_bridge="$repo_root/apps/macos/Aftelle/MacSpeechNativeInputBridge.swift"
codec="$repo_root/apps/macos/RuntimeCore/StepFunRealtimeCodec.swift"
adapter="$repo_root/apps/macos/RuntimeCore/StepFunRealtimeAdapter.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
orchestration="$repo_root/apps/macos/Aftelle/AppModels.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
engine="$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift"
router="$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"
content_view="$repo_root/apps/macos/Aftelle/ContentView.swift"
localizations=(
  "$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings"
  "$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"
)

test "$(rg -c 'receiveTask = Task \{' "$output_bridge")" -eq 1
test "$(rg -c 'pumpTask = Task \{' "$input_bridge")" -eq 1
test "$(rg -c 'mediaDeliveryTask = Task \{' "$output_bridge")" -eq 1
rg -q 'static let mediaEventCapacity = 64' "$output_bridge"
rg -q 'pendingMediaEvents.count >= Self.mediaEventCapacity' "$output_bridge"
rg -q 'mediaCapacityWaiter = continuation' "$output_bridge"
test "$(rg -c 'withCheckedContinuation' "$output_bridge")" -eq 1
rg -q 'case \.outputAudio, \.outputText, \.responseCompleted:' "$output_bridge"
rg -q 'case \.inputSpeechStarted, \.turnFailed,' "$output_bridge"
rg -q 'clearOutputForSpeechStart' "$output_bridge" "$controller"
if rg -q 'AsyncStream' "$output_bridge"; then
  echo "native_speech_duplex_bounded_output=FAIL"
  exit 1
fi
echo "native_speech_duplex_single_loops=PASS"
echo "native_speech_duplex_bounded_output=PASS"
echo "native_speech_control_media_lanes=PASS"

rg -q 'orchestrationKernel.receiveNativeSpeechEvent' "$controller"
rg -q 'runtimeCore.receiveNativeSpeechEvent' "$orchestration"
rg -q 'executionEngine.receiveNativeSpeechEvent' "$runtime"
rg -q 'providerRouter.receiveNativeSpeechEvent' "$engine"
rg -q 'nativeSpeechProvider.receive' "$router"
rg -q 'nextRecognizedEvent' "$adapter"
echo "native_speech_duplex_return_chain=PASS"

rg -q 'speechAudioOutputHost.enqueue' "$controller"
rg -q 'speechAudioOutputHost.start' "$controller"
rg -q 'handleNativeSpeechPlaybackEvent' "$controller"
rg -q 'runtimeCore.handleNativeSpeechPlaybackEvent' "$orchestration"
rg -q 'func handleNativeSpeechPlaybackEvent' "$runtime"
rg -q 'case playbackStarted' "$repo_root/apps/macos/RuntimeCore/RealtimeSpeechStateMachine.swift"
echo "native_speech_playback_forward_chain=PASS"
echo "native_speech_playback_lifecycle_return_chain=PASS"

rg -q 'case "response.audio.done"' "$codec"
rg -q 'case "response.done"' "$codec"
rg -q 'responseDoneKind' "$codec"
rg -q 'return .responseCompleted' "$codec"
rg -q 'response.function_call_arguments.done' "$codec"
rg -q 'response.thinking.delta' "$codec"
echo "native_speech_duplex_codec=PASS"

if rg -q 'AVAudioPlayer|AVAudioPlayerNode|response\.create|input_audio_buffer\.commit' \
  "$output_bridge" "$controller" "$orchestration" "$runtime"; then
  echo "native_speech_duplex_scope=FAIL"
  exit 1
fi
if rg -q 'StepFunRealtimeAdapter|ProviderRouter' "$controller"; then
  echo "native_speech_duplex_controller_boundary=FAIL"
  exit 1
fi
if rg -q 'AVFoundation|CoreAudio|AVAudio' "$runtime" "$engine" "$router"; then
  echo "native_speech_duplex_runtime_platform_boundary=FAIL"
  exit 1
fi
test -z "$(git diff b0e79a56b6ab7a36b1192417b50fbafd79c6f97f -- apps/macos/RuntimeCore/NativeSpeechProvider.swift)"
if git diff -U0 b0e79a56b6ab7a36b1192417b50fbafd79c6f97f -- \
  "$runtime" | rg -q '^\+public '; then
  echo "native_speech_duplex_runtime_public_api=FAIL"
  exit 1
fi
echo "native_speech_duplex_scope=PASS"
echo "native_speech_duplex_runtime_public_api=PASS"

test "$(rg -c '/\* MacSpeechNativeOutputBridge\.swift( in Sources)? \*/' "$project")" -eq 4
echo "native_speech_duplex_target_membership=PASS"

rg -q 'speechOutputBridgeSnapshot' "$content_view"
for localization in "${localizations[@]}"; do
  rg -q 'particleDebug\.audioHost\.outputBridge\.streaming' "$localization"
  rg -q 'particleDebug\.audioHost\.outputChunks' "$localization"
  rg -q 'particleDebug\.audioHost\.completedResponses' "$localization"
  rg -q 'particleDebug\.audioHost\.outputTerminal' "$localization"
  rg -q 'particleDebug\.realtimeDiagnostics\.export' "$localization"
done
rg -q 'completedResponseCount' "$output_bridge" "$content_view"
rg -q 'RealtimeSpeechDiagnosticTimeline' "$controller" "$orchestration"
rg -q 'NSSavePanel' "$controller"
rg -q 'schemaVersion: 3' "$controller"
rg -q 'static let capacity = 30_000' "$repo_root/apps/macos/Aftelle/AppModels.swift"
if sed -n '/struct RealtimeSpeechDiagnosticTimeline/,/struct RealtimeSpeechDiagnosticViewState/p' \
  "$repo_root/apps/macos/Aftelle/AppModels.swift" | rg -q 'removeFirst'; then
  echo "native_speech_diagnostic_ring=FAIL"
  exit 1
fi
echo "native_speech_diagnostic_ring=PASS"
runtime_diagnostic="$repo_root/apps/macos/RuntimeCore/RealtimeWebSocketTransport.swift"
rg -q 'defaultCapacity = 30_000' "$runtime_diagnostic"
if sed -n '/final class NativeSpeechDiagnosticBuffer/,/^}/p' \
  "$runtime_diagnostic" | rg -q 'removeFirst'; then
  echo "native_speech_runtime_diagnostic_ring=FAIL"
  exit 1
fi
echo "native_speech_runtime_diagnostic_ring=PASS"
diagnostic_model="$build_dir/realtime-speech-diagnostic-model.txt"
sed -n '/enum RealtimeSpeechDiagnosticSource/,/^#endif/p' \
  "$repo_root/apps/macos/Aftelle/AppModels.swift" > "$diagnostic_model"
if rg -qi 'Authorization|instructions|transcript|base64|resident_identity' \
  "$diagnostic_model"; then
  echo "native_speech_diagnostic_redaction=FAIL"
  exit 1
fi
echo "native_speech_duplex_debug_localization=PASS"
echo "native_speech_diagnostic_redaction=PASS"

transport="$repo_root/apps/macos/RuntimeCore/URLSessionRealtimeWebSocketTransport.swift"
rg -q 'timeoutIntervalForRequest = 15' "$transport"
if rg -q 'timeoutIntervalForResource|consumeTimeout|consumeWithinLimit' \
  "$transport" "$output_bridge" "$controller"; then
  echo "native_speech_persistent_session=FAIL"
  exit 1
fi
echo "native_speech_persistent_session=PASS"

rg -q 'commitNativeSpeechInterrupt' "$controller" "$orchestration" "$runtime"
rg -q 'claimPendingInterrupt' "$runtime"
rg -q 'executionEngine.cancelNativeSpeech' "$runtime"
rg -q 'decodeEnvelope' "$codec" "$adapter"
rg -q 'didEmitCancellationAcknowledgement' "$adapter"
if rg -q 'public func commitNativeSpeechInterrupt' "$runtime" "$orchestration"; then
  echo "native_speech_interrupt_boundary=FAIL"
  exit 1
fi
echo "native_speech_interrupt_boundary=PASS"

rg -q 'residentTranscriptAccumulator' "$adapter"
rg -q 'userTranscriptAccumulator' "$adapter"
rg -q 'residentAudioTranscriptDelta' "$codec" "$adapter"
rg -q 'residentTextDelta' "$codec" "$adapter"
rg -q 'case \.residentTextDelta, \.residentTextDone:' "$adapter"
rg -q 'case chunkPlayed' \
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputHost.swift"
rg -q 'RealtimeSpeechPlaybackSubtitleSynchronizer' "$controller"
rg -q 'RealtimeSpeechPlaybackSubtitleIdentity' "$controller"
rg -q 'pendingFrameCapacity = 128' "$controller"
rg -q 'requiredAudioSequence' "$controller"
rg -Fq 'mutating func advance(' "$controller"
rg -Fq 'observeEnqueuedAudio(' "$controller"
rg -Fq 'completePlayback(' "$controller"
if rg -q 'requiredPlayedChunkCount|lastAssignedPlayedChunkCount|forceLatest' \
  "$controller"; then
  echo "native_speech_subtitle_audio_watermark=FAIL"
  exit 1
fi
rg -q 'conversation.item.created' "$codec"
rg -q 'provider_user_partial_unavailable' "$adapter"
echo "native_speech_subtitle_audio_watermark=PASS"
if rg -q 'scheduleRealtimeSpeechPartialRefresh|subtitleSnapshot\.userPartial' \
  "$controller"; then
  echo "native_speech_user_partial_ui=FAIL"
  exit 1
fi
echo "native_speech_user_partial_ui=PASS"
echo "native_speech_streaming_subtitle=PASS"
