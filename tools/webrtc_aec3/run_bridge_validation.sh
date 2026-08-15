#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
BRIDGE_DIR=${SCRIPT_DIR}/bridge
SLICE=${REPO_ROOT}/third_party/webrtc_aec3/WebRTCAEC3.xcframework/macos-arm64_x86_64
HEADERS=${SLICE}/Headers
LIBRARY=${SLICE}/libWebRTCAEC3.a
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aftelle-aec3-bridge.XXXXXX")
trap 'rm -rf "${WORK_DIR}"' EXIT

[[ -f "${LIBRARY}" ]] || { print -u2 "Missing WebRTCAEC3 XCFramework"; exit 1; }

sanitize_flags=()
if [[ ${AFTELLE_AEC_SANITIZE:-0} == 1 ]]; then
  sanitize_flags=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi

common_flags=(
  -std=c++20
  -O2
  -Werror
  -Wno-nullability-completeness
  -arch arm64
  -mmacosx-version-min=14.0
  -DWEBRTC_ENABLE_PROTOBUF=0
  -DWEBRTC_STRICT_FIELD_TRIALS=0
  -DRTC_DISABLE_TRACE_EVENTS
  -DWEBRTC_POSIX
  -DWEBRTC_MAC
  -DABSL_ALLOCATOR_NOTHROW=1
  -I "${HEADERS}"
  -I "${BRIDGE_DIR}"
)

xcrun clang \
  -std=c11 \
  -Werror \
  -I "${BRIDGE_DIR}" \
  -fsyntax-only \
  "${BRIDGE_DIR}/c_header_smoke.c"

xcrun clang++ \
  "${common_flags[@]}" \
  "${sanitize_flags[@]}" \
  "${SCRIPT_DIR}/offline_aec_validation.cc" \
  "${LIBRARY}" \
  -framework Foundation \
  -o "${WORK_DIR}/direct_validation"

xcrun clang++ \
  "${common_flags[@]}" \
  "${sanitize_flags[@]}" \
  -DAFTELLE_AEC_USE_BRIDGE \
  "${SCRIPT_DIR}/offline_aec_validation.cc" \
  "${BRIDGE_DIR}/AftelleAECBridge.mm" \
  "${LIBRARY}" \
  -framework Foundation \
  -o "${WORK_DIR}/bridge_validation"

xcrun clang++ \
  "${common_flags[@]}" \
  "${sanitize_flags[@]}" \
  "${BRIDGE_DIR}/bridge_lifecycle_test.cc" \
  "${BRIDGE_DIR}/AftelleAECBridge.mm" \
  "${LIBRARY}" \
  -framework Foundation \
  -o "${WORK_DIR}/bridge_lifecycle_test"

"${WORK_DIR}/bridge_lifecycle_test"
diff <("${WORK_DIR}/direct_validation") <("${WORK_DIR}/bridge_validation")
"${WORK_DIR}/bridge_validation"
