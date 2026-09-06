#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
runner="$repo_root/tools/qwen_live_receive_probe/run-continuous.sh"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-continuous-check.XXXXXX")"
echo "continuous_check_artifacts=$work_dir"
for value in 0 11 invalid; do
  if bash "$runner" --self-test --rounds "$value" > "$work_dir/rejection-rounds-$value.log" 2>&1; then exit 1; fi
  rg -qx 'continuous_error=budget' "$work_dir/rejection-rounds-$value.log"
done
for value in 0 301 invalid; do
  if bash "$runner" --self-test --seconds "$value" > "$work_dir/rejection-seconds-$value.log" 2>&1; then exit 1; fi
  rg -qx 'continuous_error=budget' "$work_dir/rejection-seconds-$value.log"
done
if bash "$runner" --live > "$work_dir/rejection-upload.log" 2>&1; then exit 1; fi
rg -qx 'continuous_error=audio_upload_not_authorized_or_missing_pcm' "$work_dir/rejection-upload.log"
if bash "$runner" --self-test --allow-keychain-interaction > "$work_dir/rejection-keychain.log" 2>&1; then exit 1; fi
rg -qx 'continuous_error=self_test_external_access' "$work_dir/rejection-keychain.log"
if bash "$runner" --self-test --unknown > "$work_dir/rejection-unknown.log" 2>&1; then exit 1; fi
rg -qx 'continuous_error=arguments' "$work_dir/rejection-unknown.log"
echo 'continuous_runner_rejections=9 PASS'
for mode in --build-only --authorize-keychain; do
  if bash "$runner" "$mode" --allow-audio-upload --pcm "$0" > "$work_dir/rejection-$mode.log" 2>&1; then exit 1; fi
done
if bash "$runner" --authorize-keychain > "$work_dir/rejection-authorization.log" 2>&1; then exit 1; fi
rg -qx 'continuous_error=authorization_requires_signed_probe_and_local_consent' "$work_dir/rejection-authorization.log"
if AFTELLE_PROBE_SIGNING_IDENTITY=invalid bash "$runner" --build-only > "$work_dir/rejection-signing.log" 2>&1; then exit 1; fi
rg -qx 'probe_build_error=invalid_signing_identity' "$work_dir/rejection-signing.log"
echo 'continuous_authorization_rejections=4 PASS'
if bash "$runner" --check-keychain --allow-keychain-interaction > "$work_dir/rejection-credential-check.log" 2>&1; then exit 1; fi
rg -qx 'continuous_error=credential_check_requires_signed_probe_without_interaction_or_upload' "$work_dir/rejection-credential-check.log"
echo 'continuous_unattended_interaction_rejection=PASS'
for value in 0 11 invalid; do
  if bash "$runner" --self-test --reassociate-at-round "$value" > "$work_dir/rejection-item-$value.log" 2>&1; then exit 1; fi
  rg -qx 'continuous_error=invalid_reassociation_round' "$work_dir/rejection-item-$value.log"
done
if bash "$runner" --self-test --omit-provisional-preview > "$work_dir/rejection-preview.log" 2>&1; then exit 1; fi
rg -qx 'continuous_error=missing_reassociation_round' "$work_dir/rejection-preview.log"
if bash "$runner" --live --allow-audio-upload --pcm "$0" --reassociate-at-round 1 > "$work_dir/rejection-live-item.log" 2>&1; then exit 1; fi
rg -qx 'continuous_error=live_fault_injection_forbidden' "$work_dir/rejection-live-item.log"
echo 'continuous_item_rejections=5 PASS'
if rg -n 'submitRealtimeResidentBrainAcousticEvidenceForTesting|interruptRealtimeResidentBrainForTesting|cancelRealtimeResidentBrainGenerationForTesting|\.interrupt\(|\.clear\(' \
  "$repo_root/tools/qwen_live_receive_probe/ContinuousQwenProbe.swift"; then exit 1; fi
echo 'continuous_forbidden_seams=PASS'
bash "$runner" --self-test --rounds 10 --seconds 120 | tee "$work_dir/positive.log"
probe_dir="$(sed -n 's/^continuous_artifacts=//p' "$work_dir/positive.log" | head -n 1)"
bash "$runner" --build-only | tee "$work_dir/cache-reuse.log"
rg -qx 'probe_build_cache=HIT' "$work_dir/cache-reuse.log"
rg -qx 'continuous_build_only=PASS online=NOT_RUN keychain_read=NOT_RUN' "$work_dir/cache-reuse.log"
test "$(sed -n 's/^probe_binary=//p' "$work_dir/positive.log")" = "$(sed -n 's/^probe_binary=//p' "$work_dir/cache-reuse.log")"
echo 'continuous_same_binary_reuse=PASS'
/usr/bin/perl -MJSON::PP -e '
  local $/; my $r=decode_json(<>);
  die "incomplete continuous coverage\n" unless $r->{outcome} eq "PASS" && $r->{connections}==1
    && $r->{completed_rounds}==10 && $r->{final_reply_drained} && @{$r->{records}}==10;
  my $n=0;
  for my $round (@{$r->{records}}) {
    ++$n;
    die "handoff invariant\n" unless $round->{round}==$n && $round->{generation}==$n+1
      && $round->{clears}==$n && $round->{cancels}==$n && $round->{creates}==$n+1
      && $round->{session_unchanged} && $round->{canonical_matches_provider_final}
      && $round->{unique_confirmed_decisions}==$n && $round->{confirmed_to_clear_ms}<=50
      && $round->{post_clear_played_samples}>0 && $round->{late_callbacks_delivered}>0;
  }
  print "continuous_same_session_rounds=10 PASS\n";
' "$probe_dir/report.json"
mkdir -p "$work_dir/terminal/runtime-home"
CFFIXED_USER_HOME="$work_dir/terminal/runtime-home" /usr/bin/perl \
  "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" 60 "$probe_dir/probe" \
  --self-test --rounds 2 --seconds 60 --terminal-responses --output "$work_dir/terminal" \
  --fixture "$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident" \
  > "$work_dir/terminal.log" 2>&1
/usr/bin/perl -MJSON::PP -e '
  local $/; my $r=decode_json(<>);
  die "terminal playback handoff coverage\n" unless $r->{outcome} eq "PASS" && $r->{connections}==1
    && $r->{completed_rounds}==2 && $r->{final_reply_drained};
  my $n=0;
  for my $round (@{$r->{records}}) {
    ++$n;
    die "terminal response must not require wire cancel\n" unless $round->{cancels}==0
      && $round->{unique_confirmed_decisions}==$n && $round->{clears}==$n && $round->{generation}==$n+1
      && $round->{post_clear_played_samples}>0 && $round->{canonical_matches_provider_final};
  }
  print "continuous_terminal_playback_rounds=2 PASS\n";
' "$work_dir/terminal/report.json"
for scenario in first-a:1:1:omit first-b:1:1:omit ninth:10:9:omit preview-first:1:1:keep preview-ninth:10:9:keep; do
  IFS=: read -r name rounds changed_round preview <<< "$scenario"
  case_dir="$work_dir/$name"
  mkdir -p "$case_dir/runtime-home"
  arguments=(--self-test --rounds "$rounds" --seconds 120 --reassociate-at-round "$changed_round"
    --output "$case_dir" --fixture "$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident")
  if [ "$preview" = omit ]; then arguments+=(--omit-provisional-preview); fi
  CFFIXED_USER_HOME="$case_dir/runtime-home" /usr/bin/perl \
    "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" 120 \
    "$probe_dir/probe" "${arguments[@]}" > "$case_dir/run.log" 2>&1
  /usr/bin/perl -MJSON::PP -e '
    my ($file,$rounds)=@ARGV; open my $fh,"<",$file or die $!; local $/;
    my $r=decode_json(<$fh>);
    die "item handoff did not recover\n" unless $r->{outcome} eq "PASS" && $r->{connections}==1
      && $r->{completed_rounds}==$rounds && $r->{final_reply_drained} && @{$r->{records}}==$rounds;
    my $n=0;
    for my $round (@{$r->{records}}) {
      ++$n;
      die "item handoff invariant\n" unless $round->{round}==$n && $round->{generation}==$n+1
        && $round->{clears}==$n && $round->{creates}==$n+1 && $round->{cancels}==$n
        && $round->{unique_confirmed_decisions}==$n && $round->{session_unchanged}
        && $round->{canonical_matches_provider_final} && $round->{post_clear_played_samples}>0
        && $round->{confirmed_to_clear_ms}<=50;
    }
  ' "$case_dir/report.json" "$rounds"
  echo "continuous_item_handoff=$name rounds=$rounds PASS"
done
mkdir -p "$work_dir/fault/runtime-home"
set +e
CFFIXED_USER_HOME="$work_dir/fault/runtime-home" /usr/bin/perl \
  "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" 60 "$probe_dir/probe" \
  --self-test --rounds 10 --seconds 60 --inject-response-error --output "$work_dir/fault" \
  --fixture "$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident" \
  > "$work_dir/fault.log" 2>&1
status=$?
set -e
test "$status" -eq 1
/usr/bin/perl -MJSON::PP -e '
  local $/; my $r=decode_json(<>);
  die "first fault not preserved\n" unless $r->{outcome} eq "FAIL" && $r->{error} eq "provider_failure"
    && $r->{phase} eq "await_rebound" && $r->{round}==1 && $r->{completed_rounds}==0;
  print "continuous_first_failure_stop=PASS\n";
' "$work_dir/fault/report.json"
mkdir -p "$work_dir/active/runtime-home" "$work_dir/missing-active/runtime-home"
CFFIXED_USER_HOME="$work_dir/active/runtime-home" /usr/bin/perl \
  "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" 60 "$probe_dir/probe" \
  --self-test --rounds 2 --seconds 60 --require-active-cancel --pcm-start-ms 10 --pcm-end-ms 1510 \
  --output "$work_dir/active" --fixture "$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident" \
  > "$work_dir/active/run.log" 2>&1
/usr/bin/perl -MJSON::PP -e '
  my ($file,$selection)=@ARGV; open my $f,"<",$file or die $!; local $/; my $r=decode_json(<$f>);
  die "active cancellation coverage\n" unless $r->{outcome} eq "PASS" && $r->{require_active_cancel}
    && $r->{completed_rounds}==2 && $r->{connections}==1 && $r->{final_reply_drained};
  my $n=0; for my $row (@{$r->{records}}) {
    ++$n; die "active generation proof\n" unless $row->{provider_active_at_speech_start}
      && $row->{provider_active_at_cancel_submission} && $row->{cancels}==$n && $row->{clears}==$n;
  }
  open my $s,"<",$selection or die $!; my $v=decode_json(<$s>);
  die "PCM selection metadata\n" unless $v->{start_ms}==10 && $v->{end_ms}==1510 && $v->{byte_count}==48000
    && $v->{selected_sha256} ne $v->{source_sha256};
  print "continuous_active_generation_rounds=2 PASS\n";
' "$work_dir/active/report.json" "$work_dir/active/input-selection.json"
set +e
CFFIXED_USER_HOME="$work_dir/missing-active/runtime-home" /usr/bin/perl \
  "$repo_root/tools/realtime_total_regression_tests/run_with_timeout.pl" 60 "$probe_dir/probe" \
  --self-test --rounds 1 --seconds 60 --require-active-cancel --terminal-responses \
  --output "$work_dir/missing-active" --fixture "$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident" \
  > "$work_dir/missing-active/run.log" 2>&1
status=$?
set -e
test "$status" -eq 1
/usr/bin/perl -MJSON::PP -e '
  local $/; my $r=decode_json(<>);
  die "terminal playback must not pass active cancellation coverage\n" unless $r->{outcome} eq "COVERAGE_NOT_MET"
    && $r->{error} eq "coverage_missing_active_generation_cancel" && $r->{completed_rounds}==0;
  print "continuous_active_coverage_fail_closed=PASS\n";
' "$work_dir/missing-active/report.json"
for boundary in -1 invalid 1.5; do
  if bash "$runner" --self-test --pcm-start-ms "$boundary" > "$work_dir/range-$boundary.log" 2>&1; then exit 1; fi
  rg -qx 'continuous_error=invalid_pcm_range' "$work_dir/range-$boundary.log"
done
echo 'continuous_check=PASS'
