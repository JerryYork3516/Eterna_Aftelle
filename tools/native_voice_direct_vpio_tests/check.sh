#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/apps/macos/NativeVoiceTransport"
tests="$root/tools/native_voice_direct_vpio_tests"
work="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-direct-vpio-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT
defines=(-DNATIVE_VOICE_SAME_FRAME_DIAGNOSTICS=1 -DNATIVE_VOICE_DIRECT_VPIO=1)
mode="${1:-normal}"
case "$mode" in
  normal) c=(-O0); swift=(-Onone) ;;
  tsan) c=(-g -O1 -fsanitize=thread); swift=(-g -sanitize=thread) ;;
  asan) c=(-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all); swift=(-g -sanitize=address) ;;
  *) exit 64 ;;
esac
clang -std=c11 -Wall -Wextra -Werror "${defines[@]}" "${c[@]}" -I "$src" \
  "$src/NativeVoiceRing.c" "$src/NativeVoiceRealtime.c" "$tests/CallbackTests.c" -o "$work/callbacks"
"$work/callbacks"
for file in NativeVoiceRing NativeVoiceRealtime; do
  clang -std=c11 -Wall -Wextra -Werror "${defines[@]}" "${c[@]}" -c "$src/$file.c" -o "$work/$file.o"
done
clang++ -std=c++20 -fobjc-arc -Wall -Wextra -Werror "${defines[@]}" "${c[@]}" \
  -c "$src/NativeVoiceRealtimeLease.mm" -o "$work/lease.o"
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -warn-concurrency -strict-concurrency=complete \
  -warnings-as-errors -D DEBUG -D NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS -D NATIVE_VOICE_DIRECT_VPIO \
  -Xcc "${defines[0]}" -Xcc "${defines[1]}" -import-objc-header "$src/NativeVoiceRealtime.h" \
  -module-cache-path "$work/modules" -framework AVFoundation -framework CoreAudio -framework AudioToolbox \
  -lc++ "${swift[@]}" "$src/"*.swift "$tests/"*.swift "$work/"*.o -o "$work/contract"
"$work/contract"
for fault in stop removeListener uninitialize dispose dispose-before-install stop-after-start-failure split-output-stop split-voice-stop; do
  echo "native_voice_direct_vpio_cleanup_case=$fault"
  "$work/contract" "$fault"
done
if [[ "$mode" == normal ]]; then
  python3 "$root/tools/native_voice_transport_p2_tests/audit_callbacks.py" --direct-vpio
  clang -std=c11 -Wall -Wextra -Werror -O2 -c "$src/NativeVoiceRealtime.c" -o "$work/release.o"
  nm "$work/release.o" >"$work/release-symbols"
  if grep -Eq 'nvt_direct_vpio|nvt_split_vpio_silence|AudioUnitRender' "$work/release-symbols"; then
    echo "direct VoiceProcessingIO callbacks present in Release C object" >&2
    exit 1
  fi
  echo "native_voice_direct_vpio_release_c_symbols=ABSENT"
fi
echo "native_voice_direct_vpio_mode=$mode"
