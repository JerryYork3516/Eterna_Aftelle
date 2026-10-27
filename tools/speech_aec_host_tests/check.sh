#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="${1:-full}"
if [[ "$mode" != "full" && "$mode" != "d1-stats-only" && "$mode" != "m08-clock-only" && "$mode" != "m09-clock-only" && "$mode" != "m19-only" ]]; then
  echo "unsupported speech AEC test mode: $mode" >&2
  exit 2
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-speech-aec-host.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

aec_host="$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
capture="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
device_monitor="$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
tests="$repo_root/tools/speech_aec_host_tests/MacSpeechAcousticEchoHostTests.swift"
replay="$repo_root/tools/speech_aec_host_tests/RecordedAcousticReplay.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"

if [[ "$mode" == "m19-only" ]]; then
  swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete \
    -framework AVFoundation -framework CoreAudio "$aec_host" "$capture" "$device_monitor" \
    "$repo_root/tools/speech_aec_host_tests/NativePCMShortWindowTests.swift" \
    -o "$build_dir/native_pcm_short_window_tests"
  "$build_dir/native_pcm_short_window_tests"
  exit 0
fi

if [[ "$mode" == "m09-clock-only" || "$mode" == "full" ]]; then
  swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete \
    -framework AVFoundation "$aec_host" "$capture" "$device_monitor" \
    "$repo_root/tools/speech_aec_host_tests/RawTimestampDiagnosticsTests.swift" \
    -o "$build_dir/raw_timestamp_tests"
  "$build_dir/raw_timestamp_tests"
  if [[ "$mode" == "m09-clock-only" ]]; then
    exit 0
  fi
fi

if [[ "$mode" == "d1-stats-only" || "$mode" == "m08-clock-only" ]]; then
  swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete \
    -framework AVFoundation "$aec_host" "$capture" "$device_monitor" \
    "$repo_root/tools/speech_aec_host_tests/ConverterTimelineTests.swift" \
    "$repo_root/tools/speech_aec_host_tests/CaptureContentClockReproduction.swift" \
    "$repo_root/tools/speech_aec_host_tests/NativeInputChannelMappingTests.swift" \
    "$repo_root/tools/speech_aec_host_tests/NativeVoiceDebugStatsTests.swift" \
    "$repo_root/tools/speech_aec_host_tests/AppleVPDebugProfileTests.swift" \
    -o "$build_dir/native_voice_debug_tests"
  "$build_dir/native_voice_debug_tests" "--$mode"
  if [[ "$mode" == "m08-clock-only" ]]; then
    exit 0
  fi
  swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete \
    -framework AVFoundation "$aec_host" "$capture" "$device_monitor" \
    "$repo_root/tools/speech_aec_host_tests/WarmupWindowStatsTests.swift" \
    -o "$build_dir/warmup_window_tests"
  "$build_dir/warmup_window_tests"
  exit 0
fi

swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  -module-cache-path "$build_dir/module-cache" \
  -framework AVFoundation \
  "$aec_host" \
  "$capture" \
  "$device_monitor" \
  "$tests" \
  -o "$build_dir/speech_aec_host_tests"

swiftc \
  -parse-as-library -warn-concurrency -strict-concurrency=complete \
  -framework AVFoundation \
  "$aec_host" "$capture" \
  "$repo_root/tools/speech_aec_host_tests/ConverterTimelineTests.swift" \
  "$repo_root/tools/speech_aec_host_tests/NativeInputChannelMappingTests.swift" \
  -o "$build_dir/converter_timeline_tests"
"$build_dir/converter_timeline_tests"
nm "$build_dir/converter_timeline_tests" | xcrun swift-demangle > "$build_dir/release-symbols.txt"
if rg -q 'MacSpeechNativeVoiceTiming|MacSpeechTimingSnapshot|MacSpeechPlaybackFormatWitness|MacSpeechAppleVPDebugProfile|MacSpeechWarmupProfile|MacSpeechAcousticWindowStats|MacSpeechRawTimestamp' "$build_dir/release-symbols.txt"; then
  echo "speech_timing_release_isolation=FAIL"
  exit 1
fi
test "$(rg -c 'installTap\(' "$capture")" -eq 2
test "$(rg -c 'AVAudioEngine\(\)' "$capture")" -eq 1
echo "speech_timing_release_isolation=PASS"
echo "speech_timing_original_graph=PASS"

"$build_dir/speech_aec_host_tests"

swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  -module-cache-path "$build_dir/module-cache" \
  "$aec_host" \
  "$replay" \
  -o "$build_dir/recorded_acoustic_replay"

"$build_dir/recorded_acoustic_replay" --self-check

rg -q 'case webRTCAEC3' "$aec_host"
rg -q 'case appleVoiceProcessing' "$aec_host"
rg -q 'case halfDuplexFallback' "$aec_host"
rg -q 'speech-aec-processing' "$aec_host"
rg -q 'fifoSampleCapacity' "$aec_host"
rg -q 'outputNode\.presentationLatency' "$capture"
if sed -n '/private func processCapture(/,/private func rebuildAudioFormatsLocked(/p' \
  "$capture" | rg -q 'presentationLatency'; then
  echo "speech_aec_capture_callback_latency_read=FAIL"
  exit 1
fi
rg -q 'refreshAcousticEchoPresentationLatencyLocked' "$capture"
rg -q 'nativeSampleTime: when.isSampleTimeValid' "$capture"
rg -q 'timestamp: timestamp' "$capture"
if sed -n '/private func processCapture(/,/private func rebuildAudioFormatsLocked(/p' \
  "$capture" | rg -q 'timestamp:.*DispatchTime|timestamp:.*uptimeNanoseconds'; then
  echo "speech_aec_content_time=FAIL"
  exit 1
fi
echo "speech_aec_content_time=PASS"
echo "speech_aec_capture_callback_latency_read=PASS"
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
test "$(rg -c 'Self\.hostTimeNanoseconds\((when|time)\)' "$capture")" -eq 2
rg -Fq 'at: when' "$capture"
rg -Fq 'let nativeSampleTime = time.isSampleTimeValid ? time.sampleTime : nil' "$capture"
rg -q 'AVAudioTime\.seconds\(forHostTime:' "$capture"
rg -q 'renderTimingHistory' "$aec_host"
rg -q 'causalLastAudibleRenderHostTimeNanoseconds' "$aec_host"
rg -q 'renderCaptureCorrelation' "$aec_host"
rg -q 'residualRenderCorrelation' "$aec_host"
rg -q 'case echoOnly = "echo_only"' "$aec_host"
rg -q 'case nearEndSpeech = "near_end_speech"' "$aec_host"
rg -q 'case doubleTalk = "double_talk"' "$aec_host"
rg -q 'sourceGatePreRollFrameCapacity = 15' "$aec_host"
rg -q 'sourceGateResetFrameCount = 20' "$aec_host"
rg -q 'maximumSourceGateNonUserHangoverFrames = 20' "$aec_host"
rg -q 'maximumContinuousSourceForwardedFrameCount' "$aec_host"
rg -q 'maximumSourceGateOpenFrameCount' "$aec_host"
rg -q 'rawEchoGainBaseline' "$aec_host"
rg -q 'residualEchoGainBaseline' "$aec_host"
rg -q 'adaptiveEvidenceCandidateFrameCount' "$aec_host"
rg -q 'adaptiveDoubleTalkFrameCount' "$aec_host"
rg -q 'renderCaptureIsolationEstablished' "$aec_host"
rg -q 'renderCaptureIsolationWarmupFrameCount' "$aec_host"
rg -q 'maximumAdaptiveRawExcessRMS' "$aec_host"
rg -q 'maximumAdaptiveResidualExcessRMS' "$aec_host"
rg -q 'lastSourceGateCloseReason' "$aec_host"
rg -q 'classifyCapture' "$aec_host"
rg -q 'case sourceAlignmentUnavailable' "$aec_host"
rg -q 'case sourceClassificationUncertain' "$aec_host"
rg -q 'sourceForwardedFrameCount' "$aec_host"
rg -q 'sourceSuppressedFrameCount' "$aec_host"
rg -q 'sourceTimingCandidateFrameCount' "$aec_host"
rg -q 'func resetDiagnostics' "$aec_host"
if rg -q 'mainMixerNode\.installTap' "$capture"; then
  echo "speech_aec_render_source=FAIL"
  exit 1
fi
echo "speech_aec_render_source=PASS"
test "$(rg -c 'host\.processRender' "$capture")" -eq 1
if rg -q 'scheduledOutputFrameCount|queuedOutputFrameCount' "$aec_host" "$capture"; then
  echo "speech_aec_render_timing=FAIL"
  exit 1
fi
echo "speech_aec_render_timing=PASS"
capture_aec_line="$(rg -n -m 1 'host\.processCaptureSpans' "$capture" | cut -d: -f1)"
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

if rg -q 'RuntimeCore|ProviderRouter|Qwen|SessionStore|MemoryController|Keychain|transcript|pcm16Bytes|response\.cancel|Interrupt' "$aec_host"; then
  echo "speech_aec_host_ownership_privacy=FAIL"
  exit 1
fi
echo "speech_aec_host_ownership_privacy=PASS"
