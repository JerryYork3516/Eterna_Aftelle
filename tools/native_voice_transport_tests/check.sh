#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="${1:-normal}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-native-voice.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
src="$root/apps/macos/NativeVoiceTransport"
flags=(-O0)
swift_flags=(-Onone)
case "$mode" in
  normal) ;;
  release) flags=(-O2); swift_flags=(-O) ;;
  tsan) flags=(-g -O1 -fsanitize=thread); swift_flags=(-g -sanitize=thread) ;;
  asan) flags=(-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all); swift_flags=(-g -sanitize=address) ;;
  *) exit 64 ;;
esac
clang -std=c11 -Wall -Wextra -Werror -pthread -DNVT_TESTING "${flags[@]}" -I "$src" \
  "$src/NativeVoiceRing.c" "$root/tools/native_voice_transport_tests/RingTests.c" -o "$build_dir/ring"
"$build_dir/ring"
clang -std=c11 -Wall -Wextra -Werror "${flags[@]}" -c "$src/NativeVoiceRing.c" -o "$build_dir/ring.o"
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -warn-concurrency -strict-concurrency=complete \
  "${swift_flags[@]}" -import-objc-header "$src/NativeVoiceRing.h" -framework AVFoundation \
  "$src/NativeVoiceClock.swift" "$src/NativeVoiceStreamingSRC.swift" \
  "$src/AppleNativeVoiceTransportWorker.swift" "$root/tools/native_voice_transport_tests/TransportTests.swift" \
  "$build_dir/ring.o" -o "$build_dir/transport"
"$build_dir/transport"
python3 "$root/tools/native_voice_transport_tests/guard.py"
echo "native_voice_mode=$mode"
