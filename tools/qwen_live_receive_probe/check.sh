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
bash tools/qwen_live_receive_probe/run.sh --self-test
printf 'probe_configuration_parity=PASS\nprobe_forbidden_seams=PASS\n'
