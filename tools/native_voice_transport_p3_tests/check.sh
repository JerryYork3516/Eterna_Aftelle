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
  "$tests/ControllerCases.swift" tools/native_voice_transport_p4_tests/CloseoutCases.swift >"$work/ControllerTests.swift"
swiftc -D DEBUG -D NATIVE_VOICE_P3_OFFLINE_TEST -parse-as-library -module-cache-path "$work/modules" \
  -warn-concurrency -strict-concurrency=complete -import-objc-header "$src/NativeVoiceRealtime.h" \
  -framework AVFoundation -framework CoreAudio -framework AppKit -framework Security -framework UniformTypeIdentifiers \
  -lc++ "${swift[@]}" "$src/"*.swift apps/macos/RuntimeCore/*.swift "${hosts[@]}" \
  tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift \
  tools/native_voice_transport_p2_tests/FakeVoiceEngine.swift "$work/ControllerTests.swift" "$work/"*.o -o "$work/controller"
mkdir "$work/runtime-home"
CFFIXED_USER_HOME="$work/runtime-home" "$work/controller" --native-voice-p3
mkdir "$work/p4-runtime-home"
CFFIXED_USER_HOME="$work/p4-runtime-home" "$work/controller" --native-voice-p4
if [[ "$mode" == normal ]]; then
  # These builds are type-checked only. The production factory is never invoked here.
  preflight=(
    -typecheck -parse-as-library -module-cache-path "$work/modules" -swift-version 5 -default-isolation MainActor
    -import-objc-header "$src/NativeVoiceRealtime.h" -D APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED
    "$src/"*.swift apps/macos/RuntimeCore/*.swift "${hosts[@]}"
  )
  swiftc "${preflight[@]}" -D DEBUG
  reject_incompatible() {
    local incompatible="$1"
    shift
    if swiftc "${preflight[@]}" "$@" >"$work/$incompatible.log" 2>&1 ||
       ! grep -q 'error: Device execution and offline Shadow cannot share a build' "$work/$incompatible.log"; then
      cat "$work/$incompatible.log"
      exit 1
    fi
  }
  reject_incompatible release
  reject_incompatible shadow -D DEBUG -D NATIVE_VOICE_P3_OFFLINE_TEST
  echo "native_voice_p4_device_build_preflight=TYPECHECKED_DEBUG_RELEASE_AND_SHADOW_REJECTED"
fi
python3 tools/native_voice_transport_tests/guard.py
echo "native_voice_p3_mode=$mode"
echo "native_voice_p4_mode=$mode"
