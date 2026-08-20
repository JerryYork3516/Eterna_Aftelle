#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-active-brain-lease.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
swiftc \
  -D DEBUG \
  -parse-as-library \
  -default-isolation MainActor \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/active_brain_lease_tests/ActiveBrainLeaseTests.swift" \
  -o "$build_dir/active_brain_lease_tests"

fixture_path="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
if [ ! -f "$fixture_path" ]; then
  echo "active_brain_lease_fixed_fixture=BLOCKED"
  exit 1
fi

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/active_brain_lease_tests" "$fixture_path"

lease_owners="$(rg -l 'ActiveBrainLease|RuntimeActiveBrainLeaseGate' \
  "$repo_root/apps/macos" -g '*.swift')"
if [ "$lease_owners" != "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift" ]; then
  echo "active_brain_lease_runtime_ownership=FAIL"
  printf '%s\n' "$lease_owners"
  exit 1
fi

for symbol in ActiveBrainLease RuntimeBrainRoute RuntimeBrainGeneration routeEpoch; do
  rg -q "$symbol" "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
done

if sed -n '/func startFormalSpeechRoute()/,/^    }/p' \
  "$repo_root/apps/macos/Aftelle/AppController.swift" \
  | rg -q 'legacy_bridge_active'; then
  echo "active_brain_lease_appcontroller_authority=FAIL"
  exit 1
fi
if ! sed -n '/func startFormalSpeechRoute()/,/^    }/p' \
  "$repo_root/apps/macos/Aftelle/AppController.swift" \
  | rg -q 'orchestrationKernel.startSpeechRouteASR'; then
  echo "active_brain_lease_runtime_admission=FAIL"
  exit 1
fi
if [ "$(rg -c 'guard speechHostAllowsSessionReplacement else' \
  "$repo_root/apps/macos/Aftelle/AppController.swift")" -ne 2 ]; then
  echo "active_brain_lease_session_host_fence=FAIL"
  exit 1
fi
session_host_fence="$(sed -n '/private var speechHostAllowsSessionReplacement/,/^    }/p' \
  "$repo_root/apps/macos/Aftelle/AppController.swift")"
if ! printf '%s\n' "$session_host_fence" \
  | rg -q 'speechHostLifecycleOperationCount == 0' \
  || ! printf '%s\n' "$session_host_fence" \
  | rg -q '!speechAudioHostSnapshot\.isCapturing'; then
  echo "active_brain_lease_session_host_readiness=FAIL"
  exit 1
fi
for start_function in startFormalSpeechRoute startNativeSpeechInputBridge; do
  start_body="$(sed -n "/func $start_function()/,/^    }/p" \
    "$repo_root/apps/macos/Aftelle/AppController.swift")"
  if ! printf '%s\n' "$start_body" \
    | rg -q 'speechHostLifecycleOperationCount \+= 1' \
    || ! printf '%s\n' "$start_body" \
    | rg -q 'speechHostLifecycleOperationCount -= 1'; then
    echo "active_brain_lease_session_host_start_window=FAIL"
    exit 1
  fi
done

echo "active_brain_lease_runtime_ownership=PASS"
echo "active_brain_lease_route_epoch=PASS"
echo "active_brain_lease_single_brain=PASS"
echo "active_brain_lease_stale_gate=PASS"
echo "active_brain_lease_appcontroller_authority=PASS"
echo "active_brain_lease_runtime_admission=PASS"
echo "active_brain_lease_session_host_fence=PASS"
echo "active_brain_lease_session_host_readiness=PASS"
echo "active_brain_lease_session_host_start_window=PASS"
