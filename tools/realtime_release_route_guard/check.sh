#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aftelle-release-route.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

app_controller="$repo_root/apps/macos/Aftelle/AppController.swift"
app_models="$repo_root/apps/macos/Aftelle/AppModels.swift"
content_view="$repo_root/apps/macos/Aftelle/ContentView.swift"
app_entry="$repo_root/apps/macos/Aftelle/AftelleApp.swift"
composition="$repo_root/apps/macos/RuntimeCore/QwenRealtimeRuntimeComposition.swift"
project="$repo_root/apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj"
english_strings="$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings"
chinese_strings="$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"

project_release_source() {
  local source="$1"
  local output="$2"
  awk '
    function fail(message) {
      print "realtime_release_route_guard_projection_error=" message \
        > "/dev/stderr"
      exit 1
    }
    BEGIN {
      depth = 0
      emitting = 1
    }
    /^[[:space:]]*#if[[:space:]]+DEBUG[[:space:]]*$/ {
      depth += 1
      kind[depth] = "debug"
      parent[depth] = emitting
      matched[depth] = 0
      emitting = 0
      next
    }
    /^[[:space:]]*#if[[:space:]]+!DEBUG[[:space:]]*$/ {
      depth += 1
      kind[depth] = "debug"
      parent[depth] = emitting
      matched[depth] = 1
      emitting = parent[depth]
      next
    }
    /^[[:space:]]*#if([[:space:]]|$)/ {
      depth += 1
      kind[depth] = "other"
      parent[depth] = emitting
      if (emitting) print
      next
    }
    /^[[:space:]]*#elseif([[:space:]]|$)/ {
      if (depth == 0) fail("unexpected_elseif")
      if (kind[depth] == "debug") {
        if (matched[depth]) {
          emitting = 0
        } else if ($0 ~ /^[[:space:]]*#elseif[[:space:]]+!DEBUG[[:space:]]*$/) {
          matched[depth] = 1
          emitting = parent[depth]
        } else if ($0 ~ /^[[:space:]]*#elseif[[:space:]]+DEBUG[[:space:]]*$/) {
          emitting = 0
        } else {
          fail("unsupported_debug_elseif")
        }
      } else if (parent[depth]) {
        print
      }
      next
    }
    /^[[:space:]]*#else[[:space:]]*$/ {
      if (depth == 0) fail("unexpected_else")
      if (kind[depth] == "debug") {
        emitting = matched[depth] ? 0 : parent[depth]
        matched[depth] = 1
      } else if (parent[depth]) {
        print
      }
      next
    }
    /^[[:space:]]*#endif[[:space:]]*$/ {
      if (depth == 0) fail("unexpected_endif")
      if (kind[depth] == "other" && parent[depth]) print
      emitting = parent[depth]
      delete kind[depth]
      delete parent[depth]
      delete matched[depth]
      depth -= 1
      next
    }
    {
      if (emitting) print
    }
    END {
      if (depth != 0) fail("unterminated_conditional")
    }
  ' "$source" > "$output"
}

dump_ast() {
  local source="$1"
  local output="$2"
  shift 2
  xcrun swiftc -frontend -dump-parse "$@" "$source" > "$output"
}

assert_has() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  if ! rg -Fq -- "$pattern" "$file"; then
    printf 'realtime_release_route_guard_missing=%s\n' "$label" >&2
    exit 1
  fi
}

assert_lacks() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  if rg -q -- "$pattern" "$file"; then
    printf 'realtime_release_route_guard_forbidden=%s\n' "$label" >&2
    exit 1
  fi
}

release_conditions=(-D AFTELLE_WEBRTC_AEC3)
project_release_source \
  "$app_controller" "$work_dir/AppController.release.swift"
project_release_source "$app_models" "$work_dir/AppModels.release.swift"
project_release_source "$content_view" "$work_dir/ContentView.release.swift"
project_release_source "$app_entry" "$work_dir/AftelleApp.release.swift"
project_release_source \
  "$composition" "$work_dir/QwenRealtimeRuntimeComposition.release.swift"

dump_ast \
  "$work_dir/AppController.release.swift" \
  "$work_dir/app-controller-release.ast" \
  "${release_conditions[@]}"
dump_ast "$work_dir/AppModels.release.swift" "$work_dir/app-models-release.ast" \
  "${release_conditions[@]}"
dump_ast "$work_dir/ContentView.release.swift" "$work_dir/content-view-release.ast" \
  "${release_conditions[@]}"
dump_ast "$work_dir/AftelleApp.release.swift" "$work_dir/app-entry-release.ast" \
  "${release_conditions[@]}"
dump_ast \
  "$work_dir/QwenRealtimeRuntimeComposition.release.swift" \
  "$work_dir/composition-release.ast" \
  "${release_conditions[@]}"

assert_has '"RealtimeFullDuplexSpeechPhase"' \
  "$work_dir/app-models-release.ast" lifecycle_phase
assert_has '"RealtimeFullDuplexSpeechStatus"' \
  "$work_dir/app-models-release.ast" lifecycle_status_model

assert_has '"startRealtimeFullDuplexSpeech()"' \
  "$work_dir/app-controller-release.ast" start_action
assert_has '"startRealtimeResidentBrainRoute()"' \
  "$work_dir/app-controller-release.ast" formal_route_start
assert_has 'name="startRealtimeResidentBrainRoute"' \
  "$work_dir/app-controller-release.ast" start_call_edge
assert_has '"stopRealtimeFullDuplexSpeech()"' \
  "$work_dir/app-controller-release.ast" stop_action
assert_has 'name="stopRealtimeResidentBrainRoute"' \
  "$work_dir/app-controller-release.ast" stop_call_edge
assert_has '"shutdownSpeechAudioHost()"' \
  "$work_dir/app-controller-release.ast" host_shutdown
assert_has '"realtimeFullDuplexSpeechStatus"' \
  "$work_dir/app-controller-release.ast" lifecycle_status
assert_has '"ProductionQwenRealtimeBrainConfiguration"' \
  "$work_dir/app-controller-release.ast" qwen_configuration
assert_has 'name="QwenRealtimeRuntimeComposition"' \
  "$work_dir/app-controller-release.ast" composition_owner
assert_has 'field="makeRuntimeCore"' \
  "$work_dir/app-controller-release.ast" composition_factory
assert_has 'labels="credentialReader:realtimeBrainConfiguration:"' \
  "$work_dir/app-controller-release.ast" composition_arguments
assert_has 'qwen3.5-omni-plus-realtime' \
  "$work_dir/app-controller-release.ast" qwen_model
assert_has 'field="qwenKeyRef"' \
  "$work_dir/app-controller-release.ast" qwen_keychain_ref
assert_has 'value="Tina"' \
  "$work_dir/app-controller-release.ast" qwen_voice
assert_has 'name="SystemMacSpeechVoiceProcessingEngine"' \
  "$work_dir/app-controller-release.ast" shared_audio_engine
assert_has 'name="SystemMacSpeechAudioCapture"' \
  "$work_dir/app-controller-release.ast" production_capture
assert_has 'name="SystemMacSpeechAudioOutputPlayer"' \
  "$work_dir/app-controller-release.ast" production_playback
assert_has 'name="MacSpeechRealtimeBrainInputBridge"' \
  "$work_dir/app-controller-release.ast" production_input_bridge
assert_has 'name="MacSpeechRealtimeBrainOutputBridge"' \
  "$work_dir/app-controller-release.ast" production_output_bridge

assert_has '"makeRuntimeCore(credentialReader:realtimeBrainConfiguration:)"' \
  "$work_dir/composition-release.ast" production_composition
assert_has 'name="QwenRealtimeResidentBrainAdapter"' \
  "$work_dir/composition-release.ast" realtime_brain_provider
assert_has 'name="URLSessionRealtimeWebSocketTransport"' \
  "$work_dir/composition-release.ast" production_transport
assert_has 'name="ProviderRouter"' \
  "$work_dir/composition-release.ast" provider_router
assert_has 'labels="credentialReader:realtimeResidentBrainProvider:"' \
  "$work_dir/composition-release.ast" realtime_provider_argument
assert_has 'name="RuntimeCore"' \
  "$work_dir/composition-release.ast" runtime_core
assert_lacks 'QwenRealtimeAdapter|QwenRealtimeASRAdapter|QwenRealtimeTTSAdapter' \
  "$work_dir/composition-release.ast" legacy_qwen_provider
assert_lacks 'NativeSpeechDiagnosticBuffer' \
  "$work_dir/composition-release.ast" debug_diagnostic_buffer
assert_lacks 'makeDebugRuntimeCore' \
  "$work_dir/composition-release.ast" debug_composition
assert_lacks 'Fake|TestHook' \
  "$work_dir/composition-release.ast" fake_provider

assert_has '"RealtimeFullDuplexSpeechControlBar"' \
  "$work_dir/content-view-release.ast" release_control
assert_has 'field="startRealtimeFullDuplexSpeech"' \
  "$work_dir/content-view-release.ast" release_start_wiring
assert_has 'field="stopRealtimeFullDuplexSpeech"' \
  "$work_dir/content-view-release.ast" release_stop_wiring
assert_has '"applicationShouldTerminate(_:)"' \
  "$work_dir/app-entry-release.ast" termination_fence
assert_has 'field="shutdownSpeechAudioHost"' \
  "$work_dir/app-entry-release.ast" termination_shutdown
assert_has 'name="terminateLater"' \
  "$work_dir/app-entry-release.ast" awaited_termination

assert_lacks '"startFormalSpeechRoute()"|"startNativeSpeechInputBridge()"' \
  "$work_dir/app-controller-release.ast" alternate_route_start
assert_lacks 'MacSpeechNativeInputBridge|MacSpeechNativeOutputBridge|cancelFormalSpeechRoute' \
  "$work_dir/app-controller-release.ast" alternate_route_lifecycle
assert_lacks 'FormalSpeechRouteDebugSnapshot|RealtimeSpeechDiagnosticViewState' \
  "$work_dir/app-controller-release.ast" debug_observability
assert_lacks 'FormalSpeechRouteDebugSnapshot|RealtimeSpeechDiagnosticViewState' \
  "$work_dir/app-models-release.ast" debug_observability_models
assert_lacks 'NativeSpeechDiagnosticBuffer' \
  "$work_dir/app-controller-release.ast" debug_diagnostic_buffer
assert_lacks '"ParticleDebugWindow"|"ParticleDebugPanel"' \
  "$work_dir/content-view-release.ast" debug_panel
assert_lacks '"ParticleDebugWindow"' \
  "$work_dir/app-entry-release.ast" debug_window

for release_ast in \
  "$work_dir/app-controller-release.ast" \
  "$work_dir/app-models-release.ast" \
  "$work_dir/content-view-release.ast" \
  "$work_dir/app-entry-release.ast" \
  "$work_dir/composition-release.ast"
do
  assert_lacks 'Fake|TestHook|Fixtures/' "$release_ast" test_seam
done

assert_has 'func startFormalSpeechRoute()' \
  "$app_controller" debug_formal_route
assert_has 'struct ParticleDebugWindow' \
  "$content_view" debug_window_preserved
assert_has 'makeDebugRuntimeCore(' \
  "$composition" debug_composition_preserved

assert_has 'QwenRealtimeRuntimeComposition.swift in Sources' \
  "$project" composition_target_membership

plutil -lint "$english_strings" "$chinese_strings" > /dev/null
for localization_key in \
  realtimeSpeech.title \
  realtimeSpeech.start \
  realtimeSpeech.stop \
  realtimeSpeech.status.idle \
  realtimeSpeech.status.starting \
  realtimeSpeech.status.listening \
  realtimeSpeech.status.processing \
  realtimeSpeech.status.speaking \
  realtimeSpeech.status.stopping \
  realtimeSpeech.status.failed \
  realtimeSpeech.status.unavailable
do
  assert_has "\"$localization_key\" =" \
    "$english_strings" "english_$localization_key"
  assert_has "\"$localization_key\" =" \
    "$chinese_strings" "chinese_$localization_key"
done

printf 'realtime_release_route_declarations=PASS\n'
printf 'realtime_release_call_edges=PASS\n'
printf 'realtime_release_ui_entrypoints=PASS\n'
printf 'realtime_release_termination_fences=PASS\n'
printf 'realtime_release_legacy_provider_symbols=0\n'
printf 'realtime_release_alternate_route_start_symbols=0\n'
printf 'realtime_release_debug_panel_symbols=0\n'
printf 'realtime_release_route_guard=PASS\n'
