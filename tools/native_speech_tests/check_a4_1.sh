#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-native-speech-a41.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc \
  -parse-as-library \
  "$repo_root/apps/macos/Aftelle/ProviderKeychainStore.swift" \
  "$repo_root/tools/native_speech_tests/ProviderKeychainStoreTests.swift" \
  -o "$build_dir/provider_keychain_store_tests"

"$build_dir/provider_keychain_store_tests"

manifest="$repo_root/apps/macos/Aftelle/Fixtures/Stage7_5/stage7_5_test_assets.json"
controller="$repo_root/apps/macos/Aftelle/AppController.swift"
profile_source="$repo_root/apps/macos/RuntimeCore/NativeSpeechProviderProfile.swift"
keychain_store="$repo_root/apps/macos/Aftelle/ProviderKeychainStore.swift"
for value in \
  "$(jq -r '.primary_native_speech.provider_profile_id' "$manifest")" \
  "$(jq -r '.primary_native_speech.provider' "$manifest")" \
  "$(jq -r '.primary_native_speech.model' "$manifest")" \
  "$(jq -r '.primary_native_speech.voice' "$manifest")" \
  "$(jq -r '.primary_native_speech.input_audio_format' "$manifest")" \
  "$(jq -r '.primary_native_speech.output_audio_format' "$manifest")" \
  "$(jq -r '.primary_native_speech.turn_detection.type' "$manifest")" \
  "$(jq -r '.primary_native_speech.turn_detection.prefix_padding_ms' "$manifest")" \
  "$(jq -r '.primary_native_speech.key_ref' "$manifest")"; do
  if ! rg -Fq "$value" "$controller" "$profile_source" "$keychain_store"; then
    printf 'native_speech_manifest_parity=FAIL:%s\n' "$value"
    exit 1
  fi
done
endpoint_prefix="$(jq -r \
  '.primary_native_speech.endpoint | sub("qwen3\\.5-omni-flash-realtime$"; "")' \
  "$manifest")"
rg -Fq "$endpoint_prefix" "$controller"
echo "native_speech_manifest_parity=PASS"

content_view="$repo_root/apps/macos/Aftelle/ContentView.swift"
app_models="$repo_root/apps/macos/Aftelle/AppModels.swift"
runtime="$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift"

rg -q 'SecureField\(' "$content_view"
rg -q 'controller\.testNativeSpeechProviderConnectivity' "$content_view"
rg -q 'orchestrationKernel\.testNativeSpeechConnectivity' "$controller"
rg -q 'runtimeCore\.testNativeSpeechConnectivity' "$app_models"
rg -q 'startNativeSpeechInteraction\(\)' "$runtime"
rg -q 'receiveNativeSpeechEvent\(' "$runtime"
rg -q 'closeActiveNativeSpeechInteraction\(\)' "$runtime"

if rg -q 'QwenRealtimeAdapter|URLSessionRealtimeWebSocketTransport' \
  "$content_view" "$controller"; then
  echo "native_speech_debug_ui_boundary=FAIL"
  exit 1
fi
echo "native_speech_debug_ui_boundary=PASS"

for strings_file in \
  "$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings" \
  "$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"; do
  plutil -lint "$strings_file" >/dev/null
  for key in \
    particleDebug.qwen.title \
    particleDebug.qwen.credential.present \
    particleDebug.qwen.credential.missing \
    particleDebug.qwen.testConnection; do
    rg -Fq "\"$key\"" "$strings_file"
  done
done
echo "native_speech_debug_localization=PASS"
