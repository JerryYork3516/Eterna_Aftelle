#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-subtitle-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  "$repo_root/apps/macos/RuntimeCore/NativeSpeechInteraction.swift" \
  "$repo_root/apps/macos/RuntimeCore/RealtimeSpeechSubtitle.swift" \
  "$repo_root/tools/realtime_speech_subtitle_tests/RealtimeSpeechSubtitleTests.swift" \
  -o "$build_dir/subtitle-tests"

"$build_dir/subtitle-tests"

swiftc \
  -parse-as-library \
  -warn-concurrency \
  -strict-concurrency=complete \
  "$repo_root/apps/macos/Aftelle/RealtimeSpeechPresentationMapper.swift" \
  "$repo_root/tools/realtime_speech_subtitle_tests/RealtimeSpeechPresentationMapperTests.swift" \
  -o "$build_dir/particle-mapping-tests"

"$build_dir/particle-mapping-tests"

subtitle="$repo_root/apps/macos/RuntimeCore/RealtimeSpeechSubtitle.swift"
mapper="$repo_root/apps/macos/Aftelle/RealtimeSpeechPresentationMapper.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
orchestration="$repo_root/apps/macos/Aftelle/AppModels.swift"
particle_core="$repo_root/apps/macos/Aftelle/ParticleCore"

if rg -n 'StepFun|AVFoundation|SwiftUI|SessionStore|MemoryController|Trace' \
  "$subtitle"; then
  echo "realtime_speech_subtitle_vendor_neutrality=FAIL"
  exit 1
fi
echo "realtime_speech_subtitle_vendor_neutrality=PASS"

rg -q 'realtimeSpeechSubtitleStateMachine' "$runtime"
rg -q 'realtimeSpeechSubtitleSnapshot' "$orchestration" "$controller"
rg -q 'RealtimeSpeechPresentationMapper\.map' "$controller"
echo "realtime_speech_subtitle_chain=PASS"

if rg -n 'StepFunRealtimeAdapter|QwenRealtimeAdapter|ProviderRouter' \
  "$controller" "$mapper"; then
  echo "realtime_speech_presentation_boundary=FAIL"
  exit 1
fi
echo "realtime_speech_presentation_boundary=PASS"

if rg -n 'asyncAfter|Task\.sleep|Timer' "$mapper"; then
  echo "realtime_speech_particle_timer_simulation=FAIL"
  exit 1
fi
echo "realtime_speech_particle_timer_simulation=PASS"

if rg -n \
  'NativeSpeechEvent|NativeSpeechProvider|StepFun|RealtimeSpeechSubtitle|RealtimeSpeechPlaybackEvent' \
  "$particle_core" -g '*.swift'; then
  echo "realtime_speech_particle_consumer_boundary=FAIL"
  exit 1
fi
echo "realtime_speech_particle_consumer_boundary=PASS"

if git -C "$repo_root" diff -U0 \
  004ac4945c65bef41994201447813f94280b9d0e -- \
  apps/macos/RuntimeCore/RuntimeCore.swift \
  apps/macos/RuntimeCore/RealtimeSpeechSubtitle.swift \
  | rg -q '^\+public '; then
  echo "realtime_speech_subtitle_public_api=FAIL"
  exit 1
fi
echo "realtime_speech_subtitle_public_api=PASS"

for source in RealtimeSpeechSubtitle.swift RealtimeSpeechPresentationMapper.swift; do
  file_ref_count="$(rg -c "path = .*${source}" \
    "$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj")"
  source_count="$(rg -c "${source} in Sources" \
    "$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj")"
  if [ "$file_ref_count" -ne 1 ] || [ "$source_count" -ne 2 ]; then
    echo "realtime_speech_subtitle_target_membership=FAIL:$source"
    exit 1
  fi
done
echo "realtime_speech_subtitle_target_membership=PASS"
