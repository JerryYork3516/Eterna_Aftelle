#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/apps/macos/NativeVoiceTransport"
tests="$root/tools/native_voice_same_frame_diagnostics_tests"
mode="${1:-normal}"
work="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-same-frame-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT
c=(-O0)
swift=(-Onone)
case "$mode" in
  normal) ;;
  tsan) c=(-g -O1 -fsanitize=thread); swift=(-g -sanitize=thread) ;;
  asan) c=(-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all); swift=(-g -sanitize=address) ;;
  *) exit 64 ;;
esac
define=-DNATIVE_VOICE_SAME_FRAME_DIAGNOSTICS=1
clang -std=c11 -Wall -Wextra -Werror -pthread "$define" "${c[@]}" -I "$src" \
  "$src/NativeVoiceRing.c" "$src/NativeVoiceRealtime.c" "$tests/SameFrameRealtimeTests.c" -o "$work/spsc"
"$work/spsc"
for file in NativeVoiceRing NativeVoiceRealtime; do
  clang -std=c11 -Wall -Wextra -Werror "$define" "${c[@]}" -c "$src/$file.c" -o "$work/$file.o"
done
clang++ -std=c++20 -fobjc-arc -Wall -Wextra -Werror "$define" "${c[@]}" -c "$src/NativeVoiceRealtimeLease.mm" -o "$work/lease.o"
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -warn-concurrency -strict-concurrency=complete \
  -warnings-as-errors -D DEBUG -D NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS -Xcc "$define" \
  -import-objc-header "$src/NativeVoiceRealtime.h" -module-cache-path "$work/modules" \
  -framework AVFoundation -framework CoreAudio -framework AudioToolbox -lc++ "${swift[@]}" \
  "$src/"*.swift "$root/tools/native_voice_transport_p2_tests/FakeVoiceEngine.swift" \
  "$tests/SameFrameTests.swift" "$tests/SameFrameWAVTests.swift" "$work/"*.o -o "$work/session"
"$work/session"
if [[ "$mode" == normal ]]; then
  python3 "$root/tools/native_voice_transport_p2_tests/audit_callbacks.py"
  python3 "$root/tools/native_voice_transport_p2_tests/audit_callbacks.py" --same-frame
  clang -std=c11 -Wall -Wextra -Werror -O2 -c "$src/NativeVoiceRealtime.c" -o "$work/release.o"
  nm "$work/release.o" >"$work/release-symbols"
  if grep -q same_frame "$work/release-symbols"; then
    echo "same-frame recorder present in Release C object" >&2
    exit 1
  fi
  echo "native_voice_same_frame_release_c_symbols=ABSENT"
fi
echo "native_voice_same_frame_mode=$mode"
