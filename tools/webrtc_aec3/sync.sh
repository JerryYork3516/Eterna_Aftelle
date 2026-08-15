#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
CACHE_ROOT=${WEBRTC_AEC3_CACHE_ROOT:-${REPO_ROOT}/.build/webrtc-aec3}
DEPOT_TOOLS=${CACHE_ROOT}/depot_tools
CHECKOUT_ROOT=${CACHE_ROOT}/checkout
SOURCE_ROOT=${CHECKOUT_ROOT}/src
WEBRTC_SHA=9f30e83c018647b05804571699cf22b1f0f3409e
DEPOT_TOOLS_SHA=13febbee9ece9e03df923f69d540afc63c6db93e

mkdir -p "${CACHE_ROOT}" "${CHECKOUT_ROOT}"

if [[ ! -d "${DEPOT_TOOLS}/.git" ]]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "${DEPOT_TOOLS}"
fi

if [[ "$(git -C "${DEPOT_TOOLS}" rev-parse HEAD)" != "${DEPOT_TOOLS_SHA}" ]]; then
  git -C "${DEPOT_TOOLS}" fetch origin "${DEPOT_TOOLS_SHA}"
  git -C "${DEPOT_TOOLS}" checkout --detach "${DEPOT_TOOLS_SHA}"
fi

if [[ ! -f "${CHECKOUT_ROOT}/.gclient" ]]; then
  cp "${SCRIPT_DIR}/gclient.template" "${CHECKOUT_ROOT}/.gclient"
fi

export PATH="${DEPOT_TOOLS}:${PATH}"
(
  cd "${CHECKOUT_ROOT}"
  gclient sync --nohooks --revision "src@${WEBRTC_SHA}"
)

actual_sha=$(git -C "${SOURCE_ROOT}" rev-parse HEAD)
if [[ "${actual_sha}" != "${WEBRTC_SHA}" ]]; then
  print -u2 "WebRTC revision mismatch: ${actual_sha}"
  exit 1
fi

print "WebRTC ${WEBRTC_SHA} synchronized without running broad source hooks."
