#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-qwen-live-probe.XXXXXX")"
printf 'probe_artifacts=%s\n' "$probe_dir"
git -C "$repo_root" rev-parse HEAD > "$probe_dir/revision.txt"
git -C "$repo_root" diff --name-only > "$probe_dir/modified-files.txt"
mkdir -p "$probe_dir/runtime-home" "$probe_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$probe_dir/module-cache"
export SWIFT_MODULECACHE_PATH="$probe_dir/module-cache"

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
if ! swiftc -D DEBUG -parse-as-library -default-isolation MainActor \
  -warn-concurrency "${runtime_sources[@]}" \
  "$repo_root/apps/macos/Aftelle/ProviderKeychainStore.swift" \
  "$repo_root/tools/qwen_realtime_resident_brain_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/qwen_live_receive_probe/ProbeEvidence.swift" \
  "$repo_root/tools/qwen_live_receive_probe/RealQwenReceiveProbe.swift" \
  -o "$probe_dir/probe" > "$probe_dir/build.log" 2>&1; then
  tail -30 "$probe_dir/build.log"
  exit 1
fi

if [ "$#" -eq 0 ]; then set -- --self-test; fi
export CFFIXED_USER_HOME="$probe_dir/runtime-home"
set +e
/usr/bin/perl "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" \
  315 "$probe_dir/probe" \
  --output "$probe_dir" \
  --fixture "$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident" \
  "$@" > "$probe_dir/run.log" 2>&1
probe_status=$?
set -e
cat "$probe_dir/run.log"
if [ "$probe_status" -eq 124 ]; then
  printf 'probe_result=WATCHDOG_TIMEOUT\n' | tee "$probe_dir/watchdog.txt"
fi
printf 'probe_exit=%s\nprobe_artifacts=%s\n' "$probe_status" "$probe_dir"
exit "$probe_status"
