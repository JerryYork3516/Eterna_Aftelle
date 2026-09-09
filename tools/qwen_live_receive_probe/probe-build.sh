#!/usr/bin/env bash
# Sourced by the two runners; only binaries/build metadata enter this ignored cache.
probe_build() {
  local variant="$1" log="$2"
  shift 2
  local identity="${AFTELLE_PROBE_SIGNING_IDENTITY:-}" compiler sdk digest cache staging requirement argument
  local identity_file="$repo_root/.build/qwen-live-probes/signing-identity"
  if [ -z "$identity" ] && [ -f "$identity_file" ]; then
    identity="$(cat "$identity_file")" || return
    if [ -z "$identity" ]; then
      echo 'probe_build_error=invalid_signing_identity' >&2; return 2
    fi
  fi
  if [ -n "$identity" ] && [[ ! "$identity" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    echo 'probe_build_error=invalid_signing_identity' >&2; return 2
  fi
  compiler="$(xcrun --find swiftc)" || return
  sdk="$(xcrun --show-sdk-path)" || return
  digest="$({
    printf '%s\n' "$variant" "$identity" "$compiler" "$sdk" "$@"
    "$compiler" --version
    shasum -a 256 "$sdk/SDKSettings.json" "${BASH_SOURCE[0]}"
    for argument in "$@"; do
      if [[ "$argument" == *.swift ]]; then shasum -a 256 "$argument"; fi
    done
  } | shasum -a 256 | cut -d ' ' -f 1)" || return
  cache="$repo_root/.build/qwen-live-probes/$variant/$digest"
  PROBE_BINARY="$cache/probe"
  requirement='=identifier "probe"'
  if [ -n "$identity" ]; then
    requirement="=identifier \"com.eterna.aftelle.tests.qwen.$variant\" and certificate leaf = H\"$identity\""
  fi
  if [ -f "$PROBE_BINARY" ]; then
    /usr/bin/codesign --verify --strict -R "$requirement" "$PROBE_BINARY" > "$log" 2>&1 || {
      echo 'probe_build_error=cached_signature_invalid' >&2; return 1;
    }
    echo 'probe_build_cache=HIT'
  else
    mkdir -p "$cache"
    # A concurrent build must not replace a binary that has already been authorized.
    if ! mkdir "$cache/build-lock" 2>/dev/null; then echo 'probe_build_error=busy' >&2; return 1; fi
    staging="$(mktemp -d "$cache/build.XXXXXX")" || { rmdir "$cache/build-lock"; return 1; }
    if ! "$compiler" -sdk "$sdk" "$@" -o "$staging/probe" > "$log" 2>&1; then
      rmdir "$cache/build-lock"; tail -n 35 "$log"; return 1
    fi
    if [ -n "$identity" ]; then
      if ! /usr/bin/perl "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" 30 \
        /usr/bin/codesign --sign "$identity" --identifier "com.eterna.aftelle.tests.qwen.$variant" \
        --timestamp=none "$staging/probe" >> "$log" 2>&1; then
        rmdir "$cache/build-lock"
        echo 'probe_build_error=signing_failed_or_requires_local_authorization' >&2; return 1
      fi
    fi
    if ! /usr/bin/codesign --verify --strict -R "$requirement" "$staging/probe" >> "$log" 2>&1; then
      rmdir "$cache/build-lock"; echo 'probe_build_error=signature_invalid' >&2; return 1
    fi
    mv "$staging/probe" "$PROBE_BINARY"
    rmdir "$staging" "$cache/build-lock"
    echo 'probe_build_cache=MISS'
  fi
  /usr/bin/codesign -d -r- "$PROBE_BINARY" > "${log%.log}-signature.txt" 2>&1
  printf 'probe_binary=%s\nprobe_source_digest=%s\n' "$PROBE_BINARY" "$digest"
  if [ -n "$identity" ]; then echo 'probe_signed=true'; else echo 'probe_signed=false'; fi
}
