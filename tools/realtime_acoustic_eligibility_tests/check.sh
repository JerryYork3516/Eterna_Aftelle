#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-r822-gate.XXXXXX")"
fixture="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
status_before="$(git -C "$repo_root" status --porcelain=v1)"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
host_sources=(
  "$repo_root/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioCapture.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechAudioHost.swift"
  "$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"
)

swiftc \
  -D DEBUG \
  -parse-as-library \
  -default-isolation MainActor \
  -warn-concurrency \
  -strict-concurrency=complete \
  -framework AVFoundation \
  -framework CoreAudio \
  "${runtime_sources[@]}" \
  "${host_sources[@]}" \
  "$repo_root/tools/realtime_acoustic_eligibility_tests/RealtimeAcousticEligibilityTests.swift" \
  -o "$build_dir/realtime_acoustic_eligibility_tests"

output="$build_dir/output.log"
runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  /usr/bin/perl -e '$seconds = shift; alarm $seconds; exec @ARGV' \
  60 "$build_dir/realtime_acoustic_eligibility_tests" "$fixture" \
  | tee "$output"

rg -qx 'realtime_acoustic_eligibility_cases=9' "$output"
rg -qx 'realtime_acoustic_eligibility_checks=76' "$output"
rg -qx 'r822_resident_stress_observations=320' "$output"
rg -qx 'r822_resident_stress_eligible_acoustic_evidence=0' "$output"
rg -qx 'r822_resident_stress_confirmed_interruptions=0' "$output"
rg -qx 'r822_resident_stress_provider_interrupts=0' "$output"
rg -qx 'r822_resident_stress_provider_cancels=0' "$output"
rg -qx 'r822_resident_stress_runtime_clear_playback_decisions=0' "$output"
rg -qx 'r822_resident_stress_generation_changes=0' "$output"

contract="$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
provider_router="$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"
models="$repo_root/apps/macos/Aftelle/AppModels.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
bridge="$repo_root/apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift"

gate_block="$build_dir/gate.txt"
awk \
  '/struct RealtimeAcousticInterruptionEligibilityGate/ { active = 1 } /struct RealtimeInterruptionEvidenceIdentity/ { active = 0 } active' \
  "$contract" > "$gate_block"
for classification in \
  silenceOrNoise farEndDominant residualEchoLikely nearEndCandidate indeterminate; do
  rg -q "case \.$classification" "$gate_block"
done
rg -q 'observationFreshnessNanoseconds: UInt64 = 500_000_000' "$gate_block"
rg -q 'residualTailWindowNanoseconds: UInt64 = 500_000_000' "$gate_block"
if rg -q \
  'beginRealtimeBrainGenerationTransition|executionEngine|Provider|interruptRealtimeResidentBrain|cancelRealtimeResidentBrain|clearPlayback|confirmed' \
  "$gate_block"; then
  echo "r822_gate_authority=FAIL" >&2
  exit 1
fi
echo "r822_gate_authority=PASS"

atomic_block="$build_dir/atomic.txt"
awk \
  '/func submitRealtimeResidentBrainEligibleAcousticEvidence/ { active = 1 } /#if DEBUG/ { if (active) active = 0 } active' \
  "$runtime" > "$atomic_block"
rg -q 'acceptRealtimeAcousticObservation' "$atomic_block"
rg -q 'consumeRealtimeResidentBrainInterruptionEvidence' "$atomic_block"
rg -q 'nearEndCandidate' "$atomic_block"
if rg -q 'func submitRealtimeResidentBrainAcousticEvidence\(' "$runtime"; then
  echo "r822_raw_acoustic_bypass=FAIL" >&2
  exit 1
fi
rg -q 'submitRealtimeResidentBrainAcousticEvidenceForTesting' "$runtime"
if rg -q 'submitRealtimeResidentBrainAcousticEvidenceForTesting' \
  "$models" "$controller"; then
  echo "r822_host_raw_acoustic_bypass=FAIL" >&2
  exit 1
fi
rg -q 'submitRealtimeResidentBrainEligibleAcousticEvidence' \
  "$runtime" "$models" "$controller"
rg -q 'matchesCurrentPlayback' "$bridge" "$controller"
echo "r822_atomic_runtime_fusion=PASS"

decision_block="$build_dir/decision.txt"
awk \
  '/private func consumeRealtimeResidentBrainInterruptionDecision/ { active = 1 } /private func applyConfirmedRealtimeResidentBrainInterruption/ { active = 0 } active' \
  "$controller" > "$decision_block"
rg -q 'case \.success\(\.confirmed' "$decision_block"
rg -q 'applyConfirmedRealtimeResidentBrainInterruption' "$decision_block"
if rg -q 'speechAudioOutputHost\.clear' "$decision_block"; then
  echo "r822_host_playback_clear_authority=FAIL" >&2
  exit 1
fi
apply_block="$build_dir/apply-confirmed.txt"
awk \
  '/private func applyConfirmedRealtimeResidentBrainInterruption/ { active = 1 } /private func stopRealtimeResidentBrainRoute/ { active = 0 } active' \
  "$controller" > "$apply_block"
rg -q 'decision\.hostCommand == \.clearPlayback' "$apply_block"
rg -q 'speechAudioOutputHost\.clear' "$apply_block"
echo "r822_host_playback_clear_authority=PASS"

provider_protocol="$build_dir/provider-protocol.txt"
awk \
  '/protocol RealtimeResidentBrainProvider/ { active = 1 } /extension RealtimeResidentBrainProvider/ { active = 0 } active' \
  "$contract" > "$provider_protocol"
if rg -q 'Acoustic|Eligibility|clearPlayback' "$provider_protocol"; then
  echo "r822_provider_neutrality=FAIL" >&2
  exit 1
fi
provider_audio_frame="$build_dir/provider-audio-frame.txt"
awk \
  '/struct RealtimeBrainAudioFrame/ { active = 1 } /struct RealtimeBrainAudioDelta/ { active = 0 } active' \
  "$contract" > "$provider_audio_frame"
if rg -q 'sourceGate|userActivity|Acoustic|Eligibility' \
  "$provider_audio_frame"; then
  echo "r822_provider_audio_frame_neutrality=FAIL" >&2
  exit 1
fi
echo "r822_provider_audio_frame_neutrality=PASS"
if ! rg -q 'sendFrameWithActivity:' "$controller"; then
  echo "r822_production_activity_sidecar=FAIL" >&2
  exit 1
fi
echo "r822_production_activity_sidecar=PASS"
if rg -q 'interruptionAcousticSnapshot|lastSourceGateSequence' "$bridge"; then
  echo "r822_legacy_source_gate_bypass=FAIL" >&2
  exit 1
fi
post_send_block="$build_dir/post-send.txt"
awk \
  '/let result = await sendFrame/ { active = 1 } /case \.failure\(\.invalidIdentity\)/ { active = 0 } active' \
  "$bridge" > "$post_send_block"
awk '
  /activeBinding == binding/ { binding_guard = 1 }
  /activePumpID == pumpID/ { pump_guard = 1 }
  /forwardEligibleAcousticEvidence/ {
    if (!binding_guard || !pump_guard) exit 1
    forwarded = 1
    exit
  }
  END { if (!forwarded) exit 1 }
' "$post_send_block"
rg -q 'currentSnapshot = await source\.residentAcousticSnapshot' "$bridge"
rg -q 'currentSnapshot\.sourceGateOpen' "$bridge"
rg -q 'currentSnapshot\.sourceGateEpoch == eligibilityEpoch' "$bridge"
rg -q 'facts\.sourceGateEpoch == observation\.metrics\.sourceGateEpoch' "$runtime"
echo "r822_post_send_identity_guard=PASS"
echo "r822_source_gate_epoch_fence=PASS"
if rg -q 'RealtimeAcoustic|Eligibility' "$provider_router"; then
  echo "r822_provider_specific_acoustics=FAIL" >&2
  exit 1
fi
echo "r822_provider_neutrality=PASS"

git -C "$repo_root" diff --check
status_after="$(git -C "$repo_root" status --porcelain=v1)"
if [ "$status_before" != "$status_after" ]; then
  echo "r822_repository_mutation=FAIL" >&2
  exit 1
fi
echo "r822_repository_mutation=PASS"
echo "realtime_acoustic_eligibility_gate=PASS"
