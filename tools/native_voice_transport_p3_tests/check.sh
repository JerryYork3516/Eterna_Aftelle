#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
export GIT_OPTIONAL_LOCKS=0
mode="${1:-normal}"
work="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-voice-p3.XXXXXX")"
trap 'rm -rf "$work"' EXIT
src=apps/macos/NativeVoiceTransport
tests=tools/native_voice_transport_p3_tests
c=(-O0)
swift=(-Onone)
case "$mode" in
  normal) ;;
  release) c=(-O2); swift=(-O) ;;
  tsan) c=(-g -O1 -fsanitize=thread); swift=(-g -sanitize=thread) ;;
  asan) c=(-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all); swift=(-g -sanitize=address) ;;
  *) exit 64 ;;
esac

clang -std=c11 -Wall -Wextra -Werror -pthread -DNVT_IO_TESTING "${c[@]}" -I "$src" \
  "$src/NativeVoiceRing.c" "$src/NativeVoiceRealtime.c" "$tests/RenderFactsTests.c" -o "$work/facts"
"$work/facts"
for file in NativeVoiceRing NativeVoiceRealtime; do
  clang -std=c11 -Wall -Wextra -Werror "${c[@]}" -c "$src/$file.c" -o "$work/$file.o"
done
clang++ -std=c++20 -fobjc-arc -Wall -Wextra -Werror "${c[@]}" -c "$src/NativeVoiceRealtimeLease.mm" -o "$work/lease.o"

app=apps/macos/Aftelle
hosts=(
  ParticleCore/ParticleTuning.swift ParticleCore/ResidentVisualIntent.swift ParticleCore/ParticleStateController.swift
  AppModels.swift ProviderKeychainStore.swift MacSpeechAcousticEchoHost.swift MacSpeechAudioCapture.swift
  MacSpeechDeviceMonitor.swift MacSpeechAudioHost.swift MacSpeechPCMPlaybackBuffer.swift MacSpeechAudioOutputPlayer.swift
  MacSpeechAudioOutputHost.swift MacSpeechRealtimeBrainInputBridge.swift MacSpeechRealtimeBrainOutputBridge.swift
  MacSpeechNativeInputBridge.swift MacSpeechNativeOutputBridge.swift RealtimeSpeechPresentationMapper.swift
  AppController.swift MacSpeechNativeRealtimeSession.swift MacSpeechNativeRealtimeFacts.swift
)
for i in "${!hosts[@]}"; do hosts[i]="$app/${hosts[i]}"; done
# Keep the existing Fake Provider and fixture private to the combined offline harness.
cat tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift \
  "$tests/ControllerCases.swift" >"$work/ControllerTests.swift"
swiftc -D DEBUG -D NATIVE_VOICE_P3_OFFLINE_TEST -parse-as-library -module-cache-path "$work/modules" \
  -warn-concurrency -strict-concurrency=complete -import-objc-header "$src/NativeVoiceRealtime.h" \
  -framework AVFoundation -framework CoreAudio -framework AppKit -framework Security -framework UniformTypeIdentifiers \
  -lc++ "${swift[@]}" "$src/"*.swift apps/macos/RuntimeCore/*.swift "${hosts[@]}" \
  tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift \
  tools/native_voice_transport_p2_tests/FakeVoiceEngine.swift "$work/ControllerTests.swift" "$work/"*.o -o "$work/controller"
mkdir "$work/runtime-home"
CFFIXED_USER_HOME="$work/runtime-home" "$work/controller" --native-voice-p3
python3 tools/native_voice_transport_tests/guard.py
echo "native_voice_p3_mode=$mode"
