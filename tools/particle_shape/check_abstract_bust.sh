#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

xcrun swiftc \
  -D DEBUG \
  -parse-as-library \
  "$repo_root/apps/macos/Aftelle/ParticleCore/AbstractBustAnchorGenerator.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleTuning.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ResidentVisualIntent.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleStateController.swift" \
  "$repo_root/apps/macos/Aftelle/ParticleCore/ParticleSimulation.swift" \
  "$repo_root/tools/particle_shape/check_abstract_bust.swift" \
  -o "$temporary_directory/abstract_bust_check"

"$temporary_directory/abstract_bust_check"
