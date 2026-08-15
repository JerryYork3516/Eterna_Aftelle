#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
SLICE=${REPO_ROOT}/third_party/webrtc_aec3/WebRTCAEC3.xcframework/macos-arm64_x86_64
HEADERS=${SLICE}/Headers
LIBRARY=${SLICE}/libWebRTCAEC3.a
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aftelle-aec3-acoustic.XXXXXX")
trap 'rm -rf "${WORK_DIR}"' EXIT

[[ -f "${LIBRARY}" ]] || { print -u2 "Missing WebRTCAEC3 XCFramework"; exit 1; }

xcrun clang++ \
  -std=c++20 \
  -O2 \
  -Werror \
  -Wno-nullability-completeness \
  -arch arm64 \
  -mmacosx-version-min=14.0 \
  -DWEBRTC_ENABLE_PROTOBUF=0 \
  -DWEBRTC_STRICT_FIELD_TRIALS=0 \
  -DRTC_DISABLE_TRACE_EVENTS \
  -DWEBRTC_POSIX \
  -DWEBRTC_MAC \
  -DABSL_ALLOCATOR_NOTHROW=1 \
  -I "${HEADERS}" \
  "${SCRIPT_DIR}/offline_aec_validation.cc" \
  "${LIBRARY}" \
  -framework Foundation \
  -o "${WORK_DIR}/offline_aec_validation"

"${WORK_DIR}/offline_aec_validation"
