#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="${1:-normal}"
dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-voice-p2.XXXXXX")"
trap 'rm -rf "$dir"' EXIT
src="$root/apps/macos/NativeVoiceTransport"
tests="$root/tools/native_voice_transport_p2_tests"
c=(-O0)
swift=(-Onone)
case "$mode" in
  normal) ;;
  release) c=(-O2); swift=(-O) ;;
  tsan) c=(-g -O1 -fsanitize=thread); swift=(-g -sanitize=thread) ;;
  asan) c=(-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all); swift=(-g -sanitize=address) ;;
  *) exit 64 ;;
esac
clang -std=c11 -Wall -Wextra -Werror -pthread -DNVT_TESTING -DNVT_IO_TESTING "${c[@]}" -I "$src" \
  "$src/NativeVoiceRing.c" "$src/NativeVoiceRealtime.c" "$tests/RealtimeTests.c" -o "$dir/realtime"
"$dir/realtime"
for file in NativeVoiceRing NativeVoiceRealtime; do
  clang -std=c11 -Wall -Wextra -Werror "${c[@]}" -c "$src/$file.c" -o "$dir/$file.o"
done
clang++ -std=c++20 -fobjc-arc -Wall -Wextra -Werror "${c[@]}" -c "$src/NativeVoiceRealtimeLease.mm" -o "$dir/lease.o"
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -warn-concurrency -strict-concurrency=complete \
  "${swift[@]}" -import-objc-header "$src/NativeVoiceRealtime.h" -framework AVFoundation -framework CoreAudio \
  -framework AudioToolbox -lc++ "$src/"*.swift \
  "$tests/"*.swift "$dir/"*.o -o "$dir/session"
"$dir/session"
python3 "$root/tools/native_voice_transport_tests/guard.py"
echo "native_voice_p2_mode=$mode"
