#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'The audio probe requires macOS and Xcode command-line tools.' >&2
  exit 1
fi

usage() {
  echo 'Usage: run.sh [--offline | --device-self-test | --device --authorize-device --standard-mic-mode RESIDENT.wav RECORDING.wav]' >&2
}

mode="${1:---offline}"
case "$mode" in
  --offline|--device-self-test) [[ "$#" -le 1 ]] || { usage; exit 64; } ;;
  --device)
    [[ "$#" == 5 && "$2" == --authorize-device && "$3" == --standard-mic-mode ]] ||
      { usage; exit 64; }
    ;;
  *) usage; exit 64 ;;
esac

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

sources=("$probe_dir/ProbeSupport.mm")
link_flags=(-framework LiveKitWebRTC -framework AVFoundation -framework Foundation)
if [[ "$mode" == --offline ]]; then
  sources+=("$probe_dir/Probe.mm")
else
  sources+=("$probe_dir/DeviceProbe.mm" "$probe_dir/DeviceRoute.mm" "$probe_dir/WaveFile.cpp")
  link_flags+=(-framework CoreAudio -framework AudioToolbox
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$probe_dir/Info.plist")
fi

xcrun --sdk macosx clang++ -std=c++17 -mmacosx-version-min=13.0 -O2 -Wall -Wextra -Werror -Wno-unused-parameter -fobjc-arc \
  -F "$framework_dir" -Wl,-rpath,"$framework_dir" "${link_flags[@]}" "${sources[@]}" -o "$scratch/probe"

if [[ "$mode" != --offline ]]; then
  "$scratch/probe" "$library" "$@"
  exit
fi

capture_path="$scratch/capture.pcm"
"$scratch/probe" "$library" "$capture_path"
if [[ -n "${PROBE_CAPTURE_FILE:-}" ]]; then
  # Export only a completed synthetic run and refuse to overwrite a destination.
  (set -o noclobber; cat "$capture_path" > "$PROBE_CAPTURE_FILE")
fi
