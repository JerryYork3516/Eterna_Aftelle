#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s /path/to/resident.digital_resident\n' "$0" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
dr_path=$1
build_dir=$(mktemp -d /private/tmp/aftelle-runtime-expression-tests.XXXXXX)
runtime_home="$build_dir/runtime-home"
trap 'rm -rf "$build_dir"' EXIT

mkdir -p "$runtime_home"

runtime_sources=("$repo_root"/apps/macos/RuntimeCore/*.swift)
xcrun --sdk macosx swiftc \
  -D DEBUG \
  -parse-as-library \
  -module-cache-path "$build_dir/module-cache" \
  -target arm64-apple-macos14.0 \
  "${runtime_sources[@]}" \
  "$script_dir/RuntimeExpressionTests.swift" \
  -o "$build_dir/runtime-expression-tests"

CFFIXED_USER_HOME="$runtime_home" \
  "$build_dir/runtime-expression-tests" "$dr_path"

required_d1_fields=(
  lifecycleState
  expressionState
  expressionIntensity
  expressionFallbackOccurred
  expressionMappingSource
  expressionTransitionProgress
  expressionLifecycleOverrideActive
  currentBrightnessMultiplier
  currentSaturationMultiplier
  currentTemperatureShift
  currentEnergyMultiplier
  currentMotionSpeedMultiplier
  currentDiffusionMultiplier
  brightnessMultiplier
  saturationMultiplier
  temperatureShift
  energyMultiplier
  motionSpeedMultiplier
  diffusionMultiplier
)

for field in "${required_d1_fields[@]}"; do
  if ! rg -q "$field" \
    "$repo_root/apps/macos/Aftelle/AppModels.swift" \
    "$repo_root/apps/macos/Aftelle/AppController.swift" \
    "$repo_root/apps/macos/Aftelle/ContentView.swift"; then
    printf 'runtime-expression-tests: missing D1 field %s\n' "$field" >&2
    exit 1
  fi
done

for strings_file in \
  "$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings" \
  "$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"; do
  if ! rg -q '"runtimeOrchestration.error.stale_request"' "$strings_file"; then
    printf 'runtime-expression-tests: missing stale_request localization\n' >&2
    exit 1
  fi
done

if sed -n '/struct RuntimeOrchestrationInteraction:/,/^}/p' \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift" \
  | rg -q '(inputText|replyText|systemPrompt|apiKey|rawResponse|memoryValue)'; then
  printf 'runtime-expression-tests: D1 orchestration record contains sensitive body fields\n' >&2
  exit 1
fi

if rg -q 'response_format' \
  "$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift"; then
  printf 'runtime-expression-tests: provider depends on response_format\n' >&2
  exit 1
fi

if rg -q '(expressionState|expressionIntensity|expressionMapping|expression_state|expression_intensity)' \
  "$repo_root/apps/macos/RuntimeCore/SessionStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/MemoryController.swift" \
  "$repo_root/apps/macos/RuntimeCore/TraceRecorder.swift"; then
  printf 'runtime-expression-tests: expression state leaked into Store, Memory, or Trace\n' >&2
  exit 1
fi

if [ "${AFTELLE_ALLOW_PARTICLE_EXPRESSION_CHANGES:-0}" != "1" ]; then
  if git -C "$repo_root" diff --name-only \
    | rg -q '(ParticleStateController|ParticleRenderer|ParticleCoreShaders\\.metal)$'; then
    printf 'runtime-expression-tests: forbidden Particle V2 file changed\n' >&2
    exit 1
  fi
fi

printf 'runtime-expression-tests: source boundary checks ok\n'
