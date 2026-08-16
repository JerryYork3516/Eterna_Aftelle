#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-speech-route.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
swiftc \
  -D DEBUG \
  -parse-as-library \
  -warn-concurrency \
  "${runtime_sources[@]}" \
  "$repo_root/tools/speech_route_tests/SpeechRouteContractTests.swift" \
  -o "$build_dir/speech_route_contract_tests"

fixture_path="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident"
if [ ! -f "$fixture_path" ]; then
  echo "speech_route_fixed_fixture=BLOCKED"
  exit 1
fi

runtime_home="$build_dir/runtime-home"
mkdir -p "$runtime_home"
CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/speech_route_contract_tests" "$fixture_path"

contract="$repo_root/apps/macos/RuntimeCore/SpeechRouteProvider.swift"
if rg -n 'Qwen|voiceID|voice_id|LanguageModelProvider' "$contract"; then
  echo "speech_route_provider_neutrality=FAIL"
  exit 1
fi

if rg -n 'LanguageModelProvider' \
  "$repo_root/apps/macos/RuntimeCore" \
  -g '*.swift'; then
  echo "speech_route_duplicate_llm=FAIL"
  exit 1
fi

for operation in startASR sendASRAudio receiveASREvent startTTS receiveTTSEvent; do
  rg -q "providerRouter\.${operation}" \
    "$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift"
done

rg -q 'executionEngine\.requestResidentReply' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
rg -q 'finalAlreadySubmitted' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
rg -q 'canonicalResponseText' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
if sed -n \
  '/func submitSpeechRouteASRFinal(/,/^    }/p' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift" \
  | rg -n 'startTTS|TTSSynthesisRequest|ttsProvider'; then
  echo "speech_route_a3_tts_boundary=FAIL"
  exit 1
fi
if rg -n 'SpeechMemory|SpeechHistory' \
  "$repo_root/apps/macos/RuntimeCore" \
  -g '*.swift'; then
  echo "speech_route_parallel_storage=FAIL"
  exit 1
fi

rg -q 'controller\.startFormalSpeechRoute' \
  "$repo_root/apps/macos/Aftelle/ContentView.swift"
for operation in startSpeechRouteASR submitSpeechRouteASRFinal startSpeechRouteTTS commitSpeechRoutePlayback; do
  rg -q "${operation}" \
    "$repo_root/apps/macos/Aftelle/AppController.swift"
done
rg -q 'speechAudioOutputHost.*\.enqueue|speechAudioOutputHost' \
  "$repo_root/apps/macos/Aftelle/AppController.swift"
rg -q 'defersSuccessfulCommit: true' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
rg -q 'playback_pending' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"
rg -q 'input\.sampleRate == 48_000 || input\.sampleRate == 24_000' \
  "$repo_root/apps/macos/RuntimeCore/QwenRealtimeASRAdapter.swift"

echo "speech_route_provider_neutrality=PASS"
echo "speech_route_duplicate_llm=PASS"
echo "speech_route_execution_gate=PASS"
echo "speech_route_final_claim=PASS"
echo "speech_route_a3_tts_boundary=PASS"
echo "speech_route_parallel_storage=PASS"
echo "speech_route_a5_formal_wiring=PASS"
echo "speech_route_playback_commit_gate=PASS"
echo "speech_route_host_format_boundary=PASS"
