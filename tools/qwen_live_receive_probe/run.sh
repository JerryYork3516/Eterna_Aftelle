#!/usr/bin/env bash
set -euo pipefail
umask 077

if [ "$#" -eq 0 ]; then set -- --self-test; fi
watchdog_seconds=300
read_seconds=false
for argument in "$@"; do
  if [ "$read_seconds" = true ]; then
    if [[ ! "$argument" =~ ^[0-9]{1,3}$ ]] || (( 10#$argument < 1 || 10#$argument > 300 )); then
      printf 'probe_error=arguments\n' >&2
      exit 1
    fi
    watchdog_seconds=$((10#$argument))
    read_seconds=false
  elif [ "$argument" = --seconds ]; then
    read_seconds=true
  fi
done
if [ "$read_seconds" = true ]; then printf 'probe_error=arguments\n' >&2; exit 1; fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-qwen-live-probe.XXXXXX")"
printf 'probe_artifacts=%s\n' "$probe_dir"
git -C "$repo_root" rev-parse HEAD > "$probe_dir/revision.txt"
git -C "$repo_root" diff --name-only > "$probe_dir/modified-files.txt"
mkdir -p "$probe_dir/runtime-home" "$probe_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$probe_dir/module-cache"
export SWIFT_MODULECACHE_PATH="$probe_dir/module-cache"

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
source "$repo_root/tools/qwen_live_receive_probe/probe-build.sh"
probe_build receive "$probe_dir/build.log" -D DEBUG -parse-as-library -default-isolation MainActor \
  -warn-concurrency "${runtime_sources[@]}" \
  "$repo_root/apps/macos/Aftelle/ProviderKeychainStore.swift" \
  "$repo_root/tools/qwen_realtime_resident_brain_tests/FakeRealtimeWebSocketTransport.swift" \
  "$repo_root/tools/qwen_live_receive_probe/ProbeEvidence.swift" \
  "$repo_root/tools/qwen_live_receive_probe/RealQwenReceiveProbe.swift"
ln -s "$PROBE_BINARY" "$probe_dir/probe"

export CFFIXED_USER_HOME="$probe_dir/runtime-home"
run_started="$(/usr/bin/perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'print clock_gettime(CLOCK_MONOTONIC)')"
set +e
/usr/bin/perl "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" \
  "$watchdog_seconds" "$PROBE_BINARY" \
  --output "$probe_dir" \
  --fixture "$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident" \
  "$@" > "$probe_dir/run.log" 2>&1
probe_status=$?
set -e
cat "$probe_dir/run.log"
if [ "$probe_status" -eq 124 ]; then
  printf 'probe_result=WATCHDOG_TIMEOUT\n' | tee "$probe_dir/watchdog.txt"
  # The child may be stuck inside Security.framework before it can drain diagnostics.
  /usr/bin/perl -MJSON::PP -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e '
    use strict; use warnings;
    my ($root, $seconds, $started) = @ARGV;
    my @attempts;
    for my $directory (sort glob("$root/attempt-*")) {
      my %attempt = (last_milestone => "unknown", credential_phase => "unknown",
                     first_report_preserved => -f "$directory/report.json" ? JSON::PP::true : JSON::PP::false);
      for my $source (["progress.json", "last_milestone", "last_milestone"],
                      ["credential.json", "phase", "credential_phase"]) {
        if (open my $file, "<", "$directory/$source->[0]") {
          local $/; my $record = eval { decode_json(<$file>) }; close $file;
          $attempt{$source->[2]} = $record->{$source->[1]} if ref($record) eq "HASH" && defined $record->{$source->[1]};
        }
      }
      push @attempts, \%attempt;
    }
    print JSON::PP->new->canonical->pretty->encode({schema_version => 1,
      outcome => "WATCHDOG_TIMEOUT", deadline_seconds => 0 + $seconds,
      elapsed_ms => 1000 * (clock_gettime(CLOCK_MONOTONIC) - $started),
      human_gate => "NOT_RUN", attempts => \@attempts});
  ' "$probe_dir" "$watchdog_seconds" "$run_started" > "$probe_dir/watchdog.json"
fi
printf 'probe_exit=%s\nprobe_artifacts=%s\n' "$probe_status" "$probe_dir"
exit "$probe_status"
