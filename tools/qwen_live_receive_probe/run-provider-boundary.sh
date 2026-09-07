#!/bin/bash
# Provider-boundary probe runner (isolated, no set -e interference).
# Build: only probe + its dependencies. No RuntimeCore sources.
set -u
work_dir="${1:?}"
pcm="${2:-}"
interaction="${3:-}"
timeout_sec="${4:-60}"
fixture="/Users/jerryyork/Eterna_Aftelle/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
probe_source="$repo_root/tools/qwen_live_receive_probe/ProviderBoundaryDirectProbe.swift"

compiler="$(xcrun --find swiftc)"
sdk="$(xcrun --show-sdk-path)"
identity="${AFTELLE_PROBE_SIGNING_IDENTITY:-}"
digest="$({
  printf '%s\n' "provider-boundary" "$identity" "$compiler" "$sdk" "$probe_source"
  "$compiler" --version
  shasum -a 256 "$sdk/SDKSettings.json" "$probe_source"
} | shasum -a 256 | cut -d ' ' -f 1)"

cache="$repo_root/.build/qwen-live-probes/provider-boundary/$digest"
mkdir -p "$cache"
probe_binary="$cache/probe"

if [ ! -f "$probe_binary" ]; then
  echo "probe_build_cache=MISS" >&2
  if ! "$compiler" -parse-as-library -sdk "$sdk" \
      "$probe_source" \
      -o "$probe_binary" 2>"$work_dir/provider-boundary-build.log"; then
    echo 'provider_boundary_build_error=compile_failed' >&2
    tail -n 40 "$work_dir/provider-boundary-build.log" >&2
    exit 1
  fi
else
  echo "probe_build_cache=HIT" >&2
fi

if [ "$interaction" = "yes" ] && [ -n "$pcm" ]; then
  args=(--live --output "$work_dir" --pcm "$pcm" --allow-audio-upload --fixture "$fixture" --allow-keychain-interaction --timeout-sec "$timeout_sec")
  "$probe_binary" "${args[@]}"
else
  if [ -n "$pcm" ]; then
    args=(--live --output "$work_dir" --pcm "$pcm" --allow-audio-upload --fixture "$fixture" --timeout-sec "$timeout_sec")
    "$probe_binary" "${args[@]}"
  else
    # Self-test mode — caller already set up env (MOCK_SERVER_URL etc.)
    "$probe_binary" "${EXTRA_ARGS[@]}"
  fi
fi
exit $?
