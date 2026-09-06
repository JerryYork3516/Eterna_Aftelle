#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"
app=apps/macos/Aftelle/AppController.swift
probe=tools/qwen_live_receive_probe/RealQwenReceiveProbe.swift
for source in "$app" "$probe"; do
  rg -q 'wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime\?model=qwen3.5-omni-plus-realtime' "$source"
  rg -q 'defaultProviderVoiceID: "Tina"' "$source"
  rg -q 'ProviderKeychainStore.qwenKeyRef' "$source"
done
if rg -n 'submitRealtimeResidentBrainAcousticEvidenceForTesting|interruptRealtimeResidentBrainForTesting|cancelRealtimeResidentBrainGenerationForTesting|\.interrupt\(|\.clear\(' tools/qwen_live_receive_probe/*.swift; then
  printf 'probe_forbidden_seams=FAIL\n'
  exit 1
fi
for budget in 0 301 invalid; do
  if output="$(bash tools/qwen_live_receive_probe/run.sh --self-test --seconds "$budget" 2>&1)"; then exit 1; fi
  test "$output" = 'probe_error=arguments'
done
if output="$(bash tools/qwen_live_receive_probe/run.sh --self-test --seconds 2>&1)"; then exit 1; fi
test "$output" = 'probe_error=arguments'
printf 'probe_runner_budget_rejections=4 PASS\n'
bash tools/qwen_live_receive_probe/run.sh --self-test

set +e
blocked_output="$(bash tools/qwen_live_receive_probe/run.sh --self-test-blocked-credential --seconds 2)"
blocked_status=$?
set -e
printf '%s\n' "$blocked_output"
test "$blocked_status" -eq 124
blocked_dir="$(printf '%s\n' "$blocked_output" | sed -n 's/^probe_artifacts=//p' | head -n 1)"
/usr/bin/perl -MJSON::PP -e '
  use strict; use warnings;
  my ($directory) = @ARGV;
  open my $file, "<", "$directory/watchdog.json" or die "missing watchdog evidence\n";
  local $/; my $report = decode_json(<$file>); close $file;
  die "wrong hard deadline\n" unless $report->{deadline_seconds} == 2;
  die "hard watchdog did not respect budget\n" unless $report->{elapsed_ms} >= 2000 && $report->{elapsed_ms} < 6000;
  die "missing credential phase\n" unless @{$report->{attempts}} == 1
    && $report->{attempts}[0]{credential_phase} eq "keychain_lookup_begin";
  die "unexpected wire activity\n" unless -f "$directory/attempt-1/wire.ndjson"
    && -z "$directory/attempt-1/wire.ndjson";
  print "probe_blocked_credential_watchdog=PASS\n";
' "$blocked_dir"
printf 'probe_configuration_parity=PASS\nprobe_forbidden_seams=PASS\n'
