#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$repo_root/.build/test3-converter-timeline"
run_dir="$(mktemp -d "$repo_root/.build/test3-converter-timeline/run.XXXXXX")"
echo "Evidence: $run_dir"
capture="$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
host="$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
shasum -a 256 "$capture" "$host" > "$run_dir/source-before.sha256"
# Expose only fixture injection points in a temporary compilation copy. Method bodies stay unchanged.
/usr/bin/python3 - "$capture" "$run_dir/CaptureForTests.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
for declaration in ["var captureAECConverter:", "var captureOutputConverter:", "var renderAECConverter:",
                    "func processCapture(", "func processRenderedOutput("]:
    old = "private " + declaration
    if source.count(old) != 1:
        raise SystemExit("Test access declaration changed: " + declaration)
    source = source.replace(old, declaration, 1)
Path(sys.argv[2]).write_text(source)
PY
xcrun swiftc -D DEBUG -parse-as-library -O -warn-concurrency -strict-concurrency=complete \
  -module-cache-path "$run_dir/module-cache" "$host" "$run_dir/CaptureForTests.swift" \
  "$repo_root/tools/speech_aec_host_tests/ConverterTimelineTests.swift" -o "$run_dir/timeline-tests"
result=0
"$run_dir/timeline-tests" > "$run_dir/result.json" || result=$?
shasum -a 256 "$capture" "$host" > "$run_dir/source-after.sha256"
cmp "$run_dir/source-before.sha256" "$run_dir/source-after.sha256" || result=1
echo "timeline_exit=$result"
exit "$result"
