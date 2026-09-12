#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
artifact_root="$repo_root/.build/test3-local-automation/silent-doubletalk"
mkdir -p "$artifact_root"
run_dir="$(mktemp -d "$artifact_root/run.XXXXXX")"
echo "Evidence: $run_dir"
slice="$repo_root/third_party/webrtc_aec3/WebRTCAEC3.xcframework/macos-arm64_x86_64"
bridge="$repo_root/tools/webrtc_aec3/bridge"
host="$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
processor="$repo_root/apps/macos/Aftelle/MacSpeechWebRTCAECProcessor.swift"
sources=("$host" "$processor" "$bridge/AftelleAECBridge.mm" "$bridge/AftelleAECBridge.h"
  "$repo_root/tools/webrtc_aec3/offline_aec_validation.cc" "$slice/libWebRTCAEC3.a"
  "$script_dir/GenerateSignals.cc" "$script_dir/SilentDoubleTalkTests.swift" "$script_dir/run.sh")
shasum -a 256 "${sources[@]}" > "$run_dir/source-sha-before.txt"
flags=(-std=c++20 -O2 -Werror -Wno-nullability-completeness -arch arm64 -mmacosx-version-min=14.0
  -DWEBRTC_ENABLE_PROTOBUF=0 -DWEBRTC_STRICT_FIELD_TRIALS=0 -DRTC_DISABLE_TRACE_EVENTS
  -DWEBRTC_POSIX -DWEBRTC_MAC -DABSL_ALLOCATOR_NOTHROW=1 -I "$slice/Headers")
xcrun clang++ "${flags[@]}" -I "$repo_root/tools/webrtc_aec3" "$script_dir/GenerateSignals.cc" \
  "$slice/libWebRTCAEC3.a" -framework Foundation -o "$run_dir/generate-signals"
"$run_dir/generate-signals" "$run_dir"
xcrun clang++ "${flags[@]}" -c "$bridge/AftelleAECBridge.mm" -o "$run_dir/bridge.o"
xcrun swiftc -D DEBUG -parse-as-library -O -warn-concurrency -strict-concurrency=complete \
  -target arm64-apple-macos14.0 -module-cache-path "$artifact_root/module-cache" \
  -import-objc-header "$bridge/AftelleAECBridge.h" "$host" "$processor" \
  "$script_dir/SilentDoubleTalkTests.swift" "$run_dir/bridge.o" "$slice/libWebRTCAEC3.a" \
  -Xlinker -lc++ -o "$run_dir/silent-doubletalk-tests"
result=0
"$run_dir/silent-doubletalk-tests" "$run_dir" > "$run_dir/stdout.json" || result=$?
cat "$run_dir/stdout.json"
shasum -a 256 "${sources[@]}" > "$run_dir/source-sha-after.txt"
cmp "$run_dir/source-sha-before.txt" "$run_dir/source-sha-after.txt" || result=1
exit "$result"
