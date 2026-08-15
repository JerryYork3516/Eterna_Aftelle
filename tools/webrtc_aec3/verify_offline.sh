#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
XCFRAMEWORK=${REPO_ROOT}/third_party/webrtc_aec3/WebRTCAEC3.xcframework
SLICE=${XCFRAMEWORK}/macos-arm64_x86_64
HEADERS=${SLICE}/Headers
LIBRARY=${SLICE}/libWebRTCAEC3.a
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aftelle-aec3-verify.XXXXXX")
trap 'rm -rf "${WORK_DIR}"' EXIT

[[ -f "${LIBRARY}" ]] || { print -u2 "Missing XCFramework library"; exit 1; }
lipo "${LIBRARY}" -verify_arch arm64 x86_64

compile_smoke() {
  local arch=$1
  local output=${WORK_DIR}/smoke-${arch}
  xcrun clang++ \
    -std=c++20 \
    -Wno-nullability-completeness \
    -arch "${arch}" \
    -mmacosx-version-min=14.0 \
    -DWEBRTC_ENABLE_PROTOBUF=0 \
    -DWEBRTC_STRICT_FIELD_TRIALS=0 \
    -DRTC_DISABLE_TRACE_EVENTS \
    -DWEBRTC_POSIX \
    -DWEBRTC_MAC \
    -DABSL_ALLOCATOR_NOTHROW=1 \
    -I "${HEADERS}" \
    "${SCRIPT_DIR}/overlay/smoke.cc" \
    "${LIBRARY}" \
    -framework Foundation \
    -o "${output}"
  lipo "${output}" -verify_arch "${arch}"
}

compile_smoke arm64
compile_smoke x86_64
"${WORK_DIR}/smoke-arm64"

print "Offline link/load verification passed for arm64; x86_64 link passed."
