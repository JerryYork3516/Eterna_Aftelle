#!/bin/zsh
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p .build
vp_lint_bin="${VP_SWIFTLINT_BIN:-.build/support/swiftlint/swiftlint}"
test -x "$vp_lint_bin"
swift build -c debug -Xswiftc -warnings-as-errors > .build/check-debug.log 2>&1
swift build -c release -Xswiftc -warnings-as-errors > .build/check-release.log 2>&1
swift test -Xswiftc -warnings-as-errors > .build/check-tests.log 2>&1
swift format lint --strict --configuration .swift-format --recursive Package.swift Sources Tests \
  > .build/check-format.log 2>&1
"$vp_lint_bin" lint --config .swiftlint.yml --strict --no-cache --quiet Package.swift Sources Tests \
  > .build/check-lint.log 2>&1
xcrun clang -std=c11 -Wall -Wextra -Werror -fsyntax-only \
  -I Sources/VPRecorder/include Sources/VPRecorder/VPRecorder.c
python3 check_sources.py
.build/debug/apple-vp-reference > .build/check-default.log
rg -q 'OFF by default' .build/check-default.log
if .build/debug/apple-vp-reference record --mode VP_ON --duration 1 \
  --study-id nondevice --output-dir .build/never-created > .build/check-guard.log 2>&1; then
  print -u2 'FAIL: missing live flags were accepted'
  exit 1
fi
test ! -e .build/never-created
if .build/debug/apple-vp-reference inspect-route --mode VP_OFF --duration 1 \
  --study-id nondevice --output-dir .build/never-inspected > .build/check-inspection-guard.log 2>&1; then
  print -u2 'FAIL: missing inspection flags were accepted'
  exit 1
fi
test ! -e .build/never-inspected
if .build/debug/apple-vp-reference request-microphone unexpected > .build/check-permission-guard.log 2>&1; then
  print -u2 'FAIL: malformed permission command was accepted'
  exit 1
fi
rg -q 'stage=COMMAND code=INVALID_ARGUMENTS' .build/check-permission-guard.log
vp_probe_guard_dir="${TMPDIR%/}/vp0-missing-consent-$$"
if .build/debug/apple-vp-reference source-probe --enable-audio --arm-diagnostics \
  --mode VP_ON --duration 8 --study-id nondevice --output-dir "$vp_probe_guard_dir" \
  --probe-registration "${TMPDIR%/}/vp0-missing-registration.json" > .build/check-probe-guard.log 2>&1; then
  print -u2 'FAIL: unapproved source-probe was accepted'
  exit 1
fi
test ! -e "$vp_probe_guard_dir"
rg -q 'stage=COMMAND code=INVALID_ARGUMENTS' .build/check-probe-guard.log
print 'PASS: build, release, fixtures, formatting, SwiftLint and non-device CLI guards'
