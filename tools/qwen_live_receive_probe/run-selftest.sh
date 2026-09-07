#!/bin/bash
# Run probe self-test against a mock server.
# Usage: run-selftest.sh <scenario> [timeout_sec]
set -u
scenario="${1:?}"
timeout_sec="${2:-15}"
repo_root="/Users/jerryyork/Eterna_Aftelle"

# Pick free port
port=$(python3 -c "import socket;s=socket.socket();s.bind(('',0));print(s.getsockname()[1]);s.close()")
work_dir=$(mktemp -d -t "aftelle-pbselftest-$scenario")
echo "selftest_workdir=$work_dir port=$port scenario=$scenario"

# Build (probe only, no RuntimeCore)
cd "$repo_root"
compiler="$(xcrun --find swiftc)"
sdk="$(xcrun --show-sdk-path)"
identity=""
probe_source="$repo_root/tools/qwen_live_receive_probe/ProviderBoundaryDirectProbe.swift"
digest="$({
  printf '%s\n' "provider-boundary" "$identity" "$compiler" "$sdk" "$probe_source"
  "$compiler" --version
  shasum -a 256 "$sdk/SDKSettings.json" "$probe_source"
} | shasum -a 256 | cut -d ' ' -f 1)"
cache="$repo_root/.build/qwen-live-probes/provider-boundary/$digest"
mkdir -p "$cache"
probe_binary="$cache/probe"
if [ ! -f "$probe_binary" ]; then
  echo "probe_build_cache=MISS"
  "$compiler" -parse-as-library -sdk "$sdk" \
    "$probe_source" -o "$probe_binary" 2>"$work_dir/build.log"
fi

# Start mock server
mock_log="$work_dir/mock_server.ndjson"
SCENARIO="$scenario" PORT="$port" MOCK_LOG="$mock_log" \
  python3 /tmp/mock_qwen_server.py >"$work_dir/mock_stdout.log" 2>"$work_dir/mock_stderr.log" &
mock_pid=$!
echo "mock_pid=$mock_pid"

# Wait for server ready
for i in $(seq 1 50); do
  if grep -q '"phase": "server_ready"' "$mock_log" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if ! grep -q '"phase": "server_ready"' "$mock_log" 2>/dev/null; then
  echo "FAIL: mock server did not start"
  kill $mock_pid 2>/dev/null
  exit 1
fi

# Run probe
mock_url="ws://127.0.0.1:$port"
"$probe_binary" --self-test "$scenario" \
  --output "$work_dir" --mock-server "$mock_url" \
  --timeout-sec "$timeout_sec" \
  >"$work_dir/probe_stdout.log" 2>"$work_dir/probe_stderr.log"
rc=$?

# Stop mock
kill $mock_pid 2>/dev/null
wait $mock_pid 2>/dev/null

echo "probe_exit=$rc"
echo "workdir=$work_dir"
echo "---probe_stderr---"
tail -n 40 "$work_dir/probe_stderr.log"
echo "---wire.ndjson tail---"
tail -n 20 "$work_dir/wire.ndjson" 2>/dev/null
echo "---selftest_report.json---"
cat "$work_dir/selftest_report.json" 2>/dev/null
echo "---mock_server.ndjson tail---"
tail -n 20 "$mock_log"
exit $rc
