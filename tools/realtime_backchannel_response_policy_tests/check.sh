#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_mode="${1:-all}"

case "$test_mode" in
  classifier-focused)
    "$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/check.sh" \
      r844-classifier-only
    ;;
  production-targeted)
    "$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/check.sh" \
      r844-response-policy-only
    ;;
  all)
    "$0" classifier-focused
    "$0" production-targeted
    echo "realtime_backchannel_response_policy_all=PASS"
    ;;
  *)
    echo "unsupported R8.4.4 test mode: $test_mode" >&2
    exit 2
    ;;
esac
