#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

"$repo_root/tools/realtime_resident_only_zero_self_interrupt_tests/check.sh" \
  r832-confirmed-only
