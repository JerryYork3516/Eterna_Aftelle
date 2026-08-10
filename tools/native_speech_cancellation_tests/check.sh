#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

"$repo_root/tools/realtime_speech_state_tests/check.sh"
"$repo_root/tools/native_speech_tests/check.sh"
"$repo_root/tools/native_speech_duplex_tests/check.sh"

runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
state_machine="$repo_root/apps/macos/RuntimeCore/RealtimeSpeechStateMachine.swift"
adapter="$repo_root/apps/macos/RuntimeCore/StepFunRealtimeAdapter.swift"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
orchestration="$repo_root/apps/macos/Aftelle/AppModels.swift"
output_bridge="$repo_root/apps/macos/Aftelle/MacSpeechNativeOutputBridge.swift"

rg -q 'case interruptProvider' "$state_machine"
rg -q 'effect == \.interruptProvider' "$runtime"
rg -q 'executionEngine\.cancelNativeSpeech' "$runtime"
rg -q 'providerRouter\.cancelNativeSpeech' \
  "$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift"
rg -q 'nativeSpeechProvider\.cancel' \
  "$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"
rg -q 'codec\.responseCancel' "$adapter"
echo "native_speech_interrupt_execution_chain=PASS"

rg -q 'case rejectedLate' "$state_machine" "$runtime"
rg -q 'case \.success\(\.rejectedLate\)' "$output_bridge"
rg -q 'interactionTerminalOutcome' "$state_machine"
echo "native_speech_canonical_outcome_gate=PASS"

if rg -q 'StepFunRealtimeAdapter|ProviderRouter|"response\.cancel"' \
  "$controller" "$orchestration"; then
  echo "native_speech_cancellation_ui_boundary=FAIL"
  exit 1
fi
echo "native_speech_cancellation_ui_boundary=PASS"

if git -C "$repo_root" diff -U0 \
  33cb8d1de9cbf68c3c0de609661b82152c128a5b -- \
  apps/macos/RuntimeCore/NativeSpeechProvider.swift | rg -q '^\+public '; then
  echo "native_speech_cancellation_provider_public_api=FAIL"
  exit 1
fi
if git -C "$repo_root" diff -U0 \
  33cb8d1de9cbf68c3c0de609661b82152c128a5b -- \
  apps/macos/RuntimeCore/RuntimeCore.swift | rg -q '^\+public '; then
  echo "native_speech_cancellation_public_api=FAIL"
  exit 1
fi
echo "native_speech_cancellation_public_api=PASS"
echo "native_speech_cancellation_provider_public_api=PASS"
