#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
build_dir=$(mktemp -d /private/tmp/aftelle-particle-expression-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT

xcrun --sdk macosx swiftc \
  -D DEBUG \
  -parse-as-library \
  -module-cache-path "$build_dir/module-cache" \
  -target arm64-apple-macos14.0 \
  "$repo_root/apps/macos/RuntimeCore/DRLoader.swift" \
  "$repo_root/apps/macos/RuntimeCore/ExecutionEngine.swift" \
  "$repo_root/apps/macos/RuntimeCore/MemoryController.swift" \
  "$repo_root/apps/macos/RuntimeCore/NarrativeMemoryStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/RelationshipStateStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/PlatformAdapter.swift" \
  "$repo_root/apps/macos/RuntimeCore/ProviderRouter.swift" \
  "$repo_root/apps/macos/RuntimeCore/RuntimeConfig.swift" \
  "$repo_root/apps/macos/RuntimeCore/RuntimeCore.swift" \
  "$repo_root/apps/macos/RuntimeCore/SessionStore.swift" \
  "$repo_root/apps/macos/RuntimeCore/TraceRecorder.swift" \
  "$repo_root/apps/macos/RuntimeCore/VisualStateMapper.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleTuning.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ResidentVisualIntent.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleStateController.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/AbstractBustAnchorGenerator.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleSimulation.swift" \
  "$repo_root/apps/macos/Aftelle/AppModels.swift" \
  "$script_dir/ParticleExpressionTests.swift" \
  -o "$build_dir/particle-expression-tests"

"$build_dir/particle-expression-tests"

required_d1_fields=(
  expressionTransitionProgress
  expressionLifecycleOverrideActive
  currentBrightnessMultiplier
  currentSaturationMultiplier
  currentTemperatureShift
  currentEnergyMultiplier
  currentMotionSpeedMultiplier
  currentDiffusionMultiplier
)

for field in "${required_d1_fields[@]}"; do
  for source_file in \
    "$repo_root/apps/macos/Aftelle/AppModels.swift" \
    "$repo_root/apps/macos/Aftelle/AppController.swift" \
    "$repo_root/apps/macos/Aftelle/ContentView.swift"; do
    if ! rg -q "$field" "$source_file"; then
      printf 'particle-expression-tests: missing D1 field %s in %s\n' \
        "$field" "$source_file" >&2
      exit 1
    fi
  done
done

for symbol in \
  ParticleDRColorView \
  particleDRColorPalette \
  setParticleColorSource \
  effectiveParticleColorProfile; do
  if ! rg -q "$symbol" \
    "$repo_root/apps/macos/Aftelle/ContentView.swift" \
    "$repo_root/apps/macos/Aftelle/AppController.swift"; then
    printf 'particle-expression-tests: missing read-only DR color symbol %s\n' \
      "$symbol" >&2
    exit 1
  fi
done

if rg -q \
  'ParticleColorParameterRow|ParticleColorProfile\.(loadSaved|hasSavedProfile|clearSaved)|colorProfile\.save\(' \
  "$repo_root/apps/macos/Aftelle/ContentView.swift" \
  "$repo_root/apps/macos/Aftelle/AppController.swift"; then
  printf 'particle-expression-tests: manual color override remains connected\n' >&2
  exit 1
fi

if sed -n '/private struct ParticleDRColorView:/,/#endif/p' \
  "$repo_root/apps/macos/Aftelle/ContentView.swift" \
  | rg -q 'Slider\(|TextField\('; then
  printf 'particle-expression-tests: DR color view must remain read-only\n' >&2
  exit 1
fi

for localization_file in \
  "$repo_root/apps/macos/Aftelle/en.lproj/Localizable.strings" \
  "$repo_root/apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings"; do
  for key in \
    particleDebug.color.source \
    particleDebug.color.useDR \
    particleDebug.color.useDefault \
    particleDebug.color.drPalette; do
    if ! rg -q "\"$key\"" "$localization_file"; then
      printf 'particle-expression-tests: missing color localization %s in %s\n' \
        "$key" "$localization_file" >&2
      exit 1
    fi
  done
  if rg -q 'particleDebug\.color\.(base|ridge|dim|highlight|alphaScale)' \
    "$localization_file"; then
    printf 'particle-expression-tests: manual color parameter localization remains in %s\n' \
      "$localization_file" >&2
    exit 1
  fi
done

allow_dr_color_changes=${AFTELLE_ALLOW_DR_COLOR_RENDERING_CHANGES:-0}

if [[ "$allow_dr_color_changes" != "1" ]] \
  && git -C "$repo_root" diff --name-only \
  | rg -q 'apps/macos/Aftelle/ParticleCore/ParticleCoreShaders\.metal$'; then
  printf 'particle-expression-tests: Metal Shader changed without authorization\n' >&2
  exit 1
fi

if [[ "$allow_dr_color_changes" != "1" ]] \
  && git -C "$repo_root" diff --name-only \
  | rg -q 'apps/macos/Aftelle/ParticleCore/(ParticleTuning|ResidentVisualIntent)\.swift$'; then
  printf 'particle-expression-tests: V2 lifecycle or tuning baseline changed\n' >&2
  exit 1
fi

if [[ "$allow_dr_color_changes" == "1" ]]; then
  particle_tuning_path="apps/macos/Aftelle/ParticleCore/ParticleTuning.swift"
  if ! diff -q \
    <(
      git -C "$repo_root" show "HEAD:$particle_tuning_path" \
        | sed '/^struct ParticleColorProfile:/,/^enum ParticleColorParameter:/d'
    ) \
    <(
      sed '/^struct ParticleColorProfile:/,/^enum ParticleColorParameter:/d' \
        "$repo_root/$particle_tuning_path"
    ) >/dev/null; then
    printf 'particle-expression-tests: non-color V2 tuning baseline changed\n' >&2
    exit 1
  fi
  if rg -q 'dominantResidentColor|subtleColor' \
    "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleTuning.swift"; then
    printf 'particle-expression-tests: DR colors are still being whitened\n' >&2
    exit 1
  fi
  if ! rg -U -q \
    'sourceRGBBlendFactor = \.sourceAlpha[[:space:]]+pipelineDescriptor\.colorAttachments\[0\]\.sourceAlphaBlendFactor = \.one[[:space:]]+pipelineDescriptor\.colorAttachments\[0\]\.destinationRGBBlendFactor =[[:space:]]+\.oneMinusSourceAlpha[[:space:]]+pipelineDescriptor\.colorAttachments\[0\]\.destinationAlphaBlendFactor =[[:space:]]+\.oneMinusSourceAlpha' \
    "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleRenderer.swift"; then
    printf 'particle-expression-tests: color-preserving blend mode missing\n' >&2
    exit 1
  fi
  if ! rg -q 'out\.dimColor = uniforms\.dimColor' \
    "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal" \
    || ! rg -q 'const half3 dimColor' \
      "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal" \
    || ! rg -U -q \
      'half3 color = mix\([[:space:]]+dimColor,[[:space:]]+bodyColor,' \
      "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal"; then
    printf 'particle-expression-tests: dim color is not used by the Shader\n' >&2
    exit 1
  fi
  if rg -q 'sqrt\(saturate\(in\.flowLight\)\)' \
    "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal" \
    || ! rg -U -q \
      'const float flowTransitionPadding = 0\.12;[[:space:]]+const float flowTransitionStart = max\(' \
      "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal" \
    || ! rg -U -q \
      'const float flowPattern = flowProgress[[:space:]]+\* flowProgress[[:space:]]+\* flowProgress[[:space:]]+\* \(flowProgress \* \(flowProgress \* 6 - 15\) \+ 10\);' \
      "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal" \
    || ! rg -U -q \
      'const float flowColorWeight = saturate\(in\.flowLight\)[[:space:]]+\* surfaceWeight[[:space:]]+\* 0\.62;' \
    "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal" \
    || ! rg -U -q \
      'const float palettePosition = saturate\([[:space:]]+max\(surfaceColorWeight, highlightColorWeight\) \* 0\.5[[:space:]]+\+ highlightColorWeight \* 0\.5[[:space:]]+\);' \
      "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal" \
    || ! rg -U -q \
      'const half peakLimit = mix\(colorPeak, half\(1\), half\(0\.32\)\);[[:space:]]+color \*= min\(' \
      "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreShaders.metal"; then
    printf 'particle-expression-tests: flow highlight color preservation missing\n' >&2
    exit 1
  fi
fi

if git -C "$repo_root" diff --name-only \
  | rg -q 'apps/macos/RuntimeCore/(DRLoader|ProviderRouter|ExecutionEngine|RuntimeCore|VisualStateMapper)\.swift$'; then
  printf 'particle-expression-tests: forbidden Runtime/A1 file changed\n' >&2
  exit 1
fi

for method in \
  applyingBrightness \
  applyingColor \
  applyingDiffusion; do
  if ! rg -q "$method" \
    "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleRenderer.swift"; then
    printf 'particle-expression-tests: Renderer missing %s\n' "$method" >&2
    exit 1
  fi
done

if ! rg -q 'applyingMotionSpeed' \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleSimulation.swift"; then
  printf 'particle-expression-tests: motion speed is not applied to future flow time\n' >&2
  exit 1
fi

if ! rg -q 'applyingEnergy' \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleSimulation.swift"; then
  printf 'particle-expression-tests: energy is not applied to flow activity\n' >&2
  exit 1
fi

if rg -q 'flowElapsedTime\\s*\\*=' \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleSimulation.swift"; then
  printf 'particle-expression-tests: historical flow time is being rescaled\n' >&2
  exit 1
fi

if rg -q '(setTuning|rebuildParticles|setShapeTarget).*expression' \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleRenderer.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleCoreMetalView.swift"; then
  printf 'particle-expression-tests: expression entered rebuild or shape path\n' >&2
  exit 1
fi

if sed -n '/struct RuntimeOrchestrationInteractionViewState:/,/^}/p' \
  "$repo_root/apps/macos/Aftelle/AppModels.swift" \
  | rg -qi '(userInput|replyText|systemPrompt|apiKey|authorization|rawHTTP|rawResponse|memoryValue|secret)'; then
  printf 'particle-expression-tests: D1 view state contains sensitive body fields\n' >&2
  exit 1
fi

printf 'particle-expression-tests: source boundary checks ok\n'
