#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-realtime-brain-contract.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
swiftc \
  -D DEBUG \
  -parse-as-library \
  -default-isolation MainActor \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/realtime_resident_brain_contract_tests/RealtimeResidentBrainContractTests.swift" \
  -o "$build_dir/realtime_resident_brain_contract_tests"

fixture_path="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
if [ ! -f "$fixture_path" ]; then
  echo "realtime_resident_brain_contract_fixture=BLOCKED"
  exit 1
fi

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/realtime_resident_brain_contract_tests" "$fixture_path"

contract="$repo_root/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift"
for symbol in \
  RealtimeResidentBrainProvider \
  openSession \
  updateRuntimeContext \
  appendAudio \
  submitToolResult \
  cancelGeneration \
  interrupt \
  closeSession \
  residentSemanticFinal \
  toolCall \
  interruptionProposed \
  brainLeaseID \
  routeEpoch \
  generation \
  contextRevision \
  sequence; do
  rg -q "$symbol" "$contract"
done

if rg -ni \
  'qwen|openai|gemini|session\.update|websocket|urlsession|keychain|voice_id|bearer|https?://' \
  "$contract"; then
  echo "realtime_resident_brain_contract_provider_neutral=FAIL"
  exit 1
fi

if rg -n '^public ' "$contract"; then
  echo "realtime_resident_brain_contract_runtime_api_scope=FAIL"
  exit 1
fi

rg -q 'providerRouter\.openRealtimeResidentBrainSession' \
  "$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift"
rg -q 'realtimeResidentBrainProvider\.openSession' \
  "$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"
rg -q 'activeBrainLeaseGate\.acquire' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"

echo "realtime_resident_brain_contract_fixture=PASS"
echo "realtime_resident_brain_contract_provider_neutral=PASS"
echo "realtime_resident_brain_contract_runtime_api_scope=PASS"
echo "realtime_resident_brain_contract_router_seam=PASS"
echo "realtime_resident_brain_contract_r1_admission=PASS"
echo "realtime_resident_brain_contract_network_dependency=ZERO"
