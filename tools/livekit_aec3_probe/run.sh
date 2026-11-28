#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'The offline probe requires macOS and Xcode command-line tools.' >&2
  exit 1
fi

probe_dir="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-livekit-aec3.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
version=150.7871.08
checksum=008dbf8187843ab708afa44b65b8041d8ce8da99e530608cd85aa6ea3551529a
archive="${LIVEKIT_WEBRTC_ARCHIVE:-$scratch/LiveKitWebRTC.xcframework.zip}"
if [[ -z "${LIVEKIT_WEBRTC_ARCHIVE:-}" ]]; then
  curl --fail --location --proto '=https' --retry 2 --output "$archive" \
    "https://github.com/livekit/webrtc-xcframework/releases/download/$version/LiveKitWebRTC.xcframework.zip"
fi

observed="$(shasum -a 256 < "$archive" | awk '{print $1}')"
if [[ "$observed" != "$checksum" ]]; then
  echo "LiveKitWebRTC archive SHA-256 mismatch: $observed" >&2
  exit 1
fi

slice=LiveKitWebRTC.xcframework/macos-arm64_x86_64
unzip -q "$archive" "$slice/LiveKitWebRTC.framework/*" -d "$scratch"
framework_dir="$scratch/$slice"
library="$framework_dir/LiveKitWebRTC.framework/LiveKitWebRTC"
printf 'package=%s archive_sha256=%s framework_sha256=%s\n' \
  "$version" "$observed" "$(shasum -a 256 < "$library" | awk '{print $1}')"

xcrun --sdk macosx clang++ -std=c++17 -mmacosx-version-min=13.0 -O2 -Wall -Wextra -Werror -Wno-unused-parameter -fobjc-arc \
  -F "$framework_dir" -Wl,-rpath,"$framework_dir" \
  -framework LiveKitWebRTC -framework AVFoundation -framework Foundation \
  "$probe_dir/Probe.mm" -o "$scratch/probe"

capture_path="$scratch/capture.pcm"
"$scratch/probe" "$library" "$capture_path"
if [[ -n "${PROBE_CAPTURE_FILE:-}" ]]; then
  # Export only a completed synthetic run and refuse to overwrite a destination.
  (set -o noclobber; cat "$capture_path" > "$PROBE_CAPTURE_FILE")
fi
