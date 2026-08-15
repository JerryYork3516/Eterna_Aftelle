#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
CACHE_ROOT=${WEBRTC_AEC3_CACHE_ROOT:-${REPO_ROOT}/.build/webrtc-aec3}
SOURCE_ROOT=${WEBRTC_AEC3_SOURCE_ROOT:-${CACHE_ROOT}/checkout/src}
ARTIFACT_ROOT=${CACHE_ROOT}/artifacts
PACKAGE_ROOT=${REPO_ROOT}/third_party/webrtc_aec3
XCFRAMEWORK=${PACKAGE_ROOT}/WebRTCAEC3.xcframework
WEBRTC_SHA=9f30e83c018647b05804571699cf22b1f0f3409e
GN_TARGET=//aftelle_apm:aftelle_webrtc_apm
DEPLOYMENT_TARGET=14.0

GN=${SOURCE_ROOT}/buildtools/mac/gn
NINJA=${SOURCE_ROOT}/third_party/ninja/ninja
LLVM_AR=${SOURCE_ROOT}/third_party/llvm-build/Release+Asserts/bin/llvm-ar
PATCH=${SCRIPT_DIR}/minimal_aec3.patch

for tool in "${GN}" "${NINJA}" "${LLVM_AR}"; do
  [[ -x "${tool}" ]] || { print -u2 "Missing build tool: ${tool}"; exit 1; }
done

actual_sha=$(git -C "${SOURCE_ROOT}" rev-parse HEAD)
[[ "${actual_sha}" == "${WEBRTC_SHA}" ]] || {
  print -u2 "Expected WebRTC ${WEBRTC_SHA}, found ${actual_sha}"
  exit 1
}

mkdir -p "${SOURCE_ROOT}/aftelle_apm" "${ARTIFACT_ROOT}"
cp "${SCRIPT_DIR}/overlay/BUILD.gn" "${SOURCE_ROOT}/aftelle_apm/BUILD.gn"
cp "${SCRIPT_DIR}/overlay/anchor.cc" "${SOURCE_ROOT}/aftelle_apm/anchor.cc"
cp "${SCRIPT_DIR}/overlay/smoke.cc" "${SOURCE_ROOT}/aftelle_apm/smoke.cc"

if git -C "${SOURCE_ROOT}" apply --unidiff-zero --check "${PATCH}" 2>/dev/null; then
  git -C "${SOURCE_ROOT}" apply --unidiff-zero "${PATCH}"
elif ! git -C "${SOURCE_ROOT}" apply --unidiff-zero --reverse --check "${PATCH}" 2>/dev/null; then
  print -u2 "Pinned source does not match the recorded minimal AEC3 patch."
  exit 1
fi

common_args='is_debug=false is_component_build=false target_os="mac" mac_deployment_target="14.0" rtc_include_tests=false rtc_build_examples=false rtc_build_tools=false rtc_enable_protobuf=false rtc_include_builtin_audio_codecs=false rtc_include_internal_audio_device=false rtc_enable_objc_symbol_export=false rtc_disable_trace_events=true use_custom_libcxx=false symbol_level=0 treat_warnings_as_errors=false'

cd "${SOURCE_ROOT}"

build_arch() {
  local arch=$1
  local gn_cpu=$2
  local out_dir=${SOURCE_ROOT}/out/aftelle_aec3_${arch}
  local archive_dir=${ARTIFACT_ROOT}/${arch}
  local thin_archive=${out_dir}/obj/aftelle_apm/libaftelle_webrtc_apm.a
  local archive=${archive_dir}/libWebRTCAEC3.a
  local deps_file=${ARTIFACT_ROOT}/deps-${arch}.txt
  local mri_file

  "${GN}" gen "${out_dir}" --args="${common_args} target_cpu=\"${gn_cpu}\""
  "${GN}" desc "${out_dir}" "${GN_TARGET}" deps --all > "${deps_file}"

  if rg -i 'peer[_-]?connection|(^|[/:])p2p([/:]|$)|(^|[/:])video([/:]|$)|(^|[/:])rtp([_/:]|$)|modules/rtp_rtcp|(^|[/:])sip([/:]|$)|third_party/(perfetto|protobuf)' "${deps_file}"; then
    print -u2 "Forbidden full-stack WebRTC dependency detected for ${arch}."
    exit 1
  fi

  "${NINJA}" -C "${out_dir}" "${GN_TARGET#//}"
  mkdir -p "${archive_dir}"
  mri_file=$(mktemp "${CACHE_ROOT}/llvm-ar.XXXXXX")
  {
    print "create ${archive}"
    print "addlib ${thin_archive}"
    print "save"
    print "end"
  } > "${mri_file}"
  "${LLVM_AR}" -M < "${mri_file}"
  rm "${mri_file}"
  lipo "${archive}" -verify_arch "${arch}"
}

build_arch arm64 arm64
build_arch x86_64 x64

mkdir -p "${ARTIFACT_ROOT}/universal"
lipo -create \
  "${ARTIFACT_ROOT}/arm64/libWebRTCAEC3.a" \
  "${ARTIFACT_ROOT}/x86_64/libWebRTCAEC3.a" \
  -output "${ARTIFACT_ROOT}/universal/libWebRTCAEC3.a"

HEADERS=${ARTIFACT_ROOT}/Headers
rm -rf "${HEADERS}"
mkdir -p "${HEADERS}"
while IFS= read -r header; do
  [[ -n "${header}" ]] || continue
  source_header=${SOURCE_ROOT}/${header}
  if [[ "${header}" == third_party/abseil-cpp/* ]]; then
    destination=${HEADERS}/${header#third_party/abseil-cpp/}
  else
    destination=${HEADERS}/${header}
  fi
  [[ -f "${source_header}" ]] || { print -u2 "Missing public header: ${header}"; exit 1; }
  mkdir -p "${destination:h}"
  cp "${source_header}" "${destination}"
done < "${SCRIPT_DIR}/public_headers.txt"

cp "${SCRIPT_DIR}/WebRTCAEC3.hpp" "${HEADERS}/WebRTCAEC3.hpp"

candidate=${CACHE_ROOT}/WebRTCAEC3.candidate.xcframework
rm -rf "${candidate}"
xcodebuild -create-xcframework \
  -library "${ARTIFACT_ROOT}/universal/libWebRTCAEC3.a" \
  -headers "${HEADERS}" \
  -output "${candidate}"

backup=${CACHE_ROOT}/WebRTCAEC3.xcframework.previous
rm -rf "${backup}"
if [[ -e "${XCFRAMEWORK}" ]]; then
  mv "${XCFRAMEWORK}" "${backup}"
fi
mv "${candidate}" "${XCFRAMEWORK}"
rm -rf "${backup}"

print "Built ${XCFRAMEWORK} for macOS arm64 and x86_64."
