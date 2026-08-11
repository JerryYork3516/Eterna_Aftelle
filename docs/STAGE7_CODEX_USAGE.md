# Stage 7 Codex Usage

Use this file to record each Codex task before closing the loop.

## Record Template

- Stage:
- Date:
- Task:
- Read scope:
- Changed files:
- Verification:
- Token note:
- Follow-up:

## Apple Official Reference Rule

When a task touches SwiftUI, Metal, FileManager, Keychain, HIG, or Accessibility, read only the current-node minimum Apple official reference listed in `docs/apple_official_reference_stage7.md`. Do not system-learn iOS / visionOS / ARKit / RealityKit, do not add platform targets, and do not treat Apple docs as a new Aftelle architecture source.

## 7.5-realtime-speech-documentation-reconciliation

- Stage: 7.5 documentation authority reconciliation
- Date: 2026-08-11
- Task: Align Stage 7 documentation with the authoritative `03_dev_plan.md` Stage 7.5.1–7.5.28 realtime speech / Studio Next / real-asset plan.
- Read scope: Stage 7 planning, architecture, boundary, forbidden checklist, product, entry gate, execution and documentation-control files containing the superseded Voice Input MVP wording.
- Changed files: documentation only; no Swift, Xcode, Runtime API, DR schema or Store schema changes.
- Verification: keyword rescan; `git diff --check`; docs-only diff review; Stage 7 forbidden checklist.
- Follow-up: resume the separately authorized Stage 7.5 node only after this documentation commit; do not implement A2/A3 in this task.

## 7.5-voice-input-v8-doc-plan (historical, superseded)

> This 2026-07-04 record is retained as history. Its Voice Input MVP scope and follow-up were superseded by the authoritative `03_dev_plan.md` Stage 7.5.1–7.5.28 plan and must not be used as current execution guidance.

- Stage: 7.5 / 7.11 / 7.12 documentation plan
- Date: 2026-07-04
- Task: Upgrade Stage 7 planning docs to v8: add Voice Input MVP, move Demo Readiness Polish to 7.11, and move Demo Lock + recording freeze to 7.12.
- Read scope: `AGENTS.md`, `docs/03_dev_plan.md`, `docs/06_product_design.md`, `docs/02_architecture.md`, `docs/aftelle_runtime_boundary.md`, `docs/stage7_forbidden_checklist.md`, `DEVLOG.md`, this usage log.
- Changed files: `docs/03_dev_plan.md`, `docs/06_product_design.md`, `docs/02_architecture.md`, `docs/aftelle_runtime_boundary.md`, `docs/stage7_forbidden_checklist.md`, `DEVLOG.md`, this usage log.
- Verification: `git diff --check`; `tools/architecture_guard/check.sh`; `tools/secret_guard/check.sh`.
- Token note: documentation-only change; do not modify Swift, Xcode, `runtime_api_contract.md`, `dr_contract_v0_3.md`, `provider_profile_contract.md`, `feature_livestate.md`, `07_dr_blueprint.md`, or `09_skills_plugins.md`.
- Historical follow-up (superseded): implement Voice Input MVP only when Stage 7.5 starts; keep it as record-to-text entering the existing Runtime step path.

## 7.3-apple-official-reference-doc

- Stage: 7.3
- Date: 2026-07-03
- Task: Add document-only Stage 7 Apple official reference rule.
- Read scope: `AGENTS.md`, `CLAUDE.md`, `docs/STAGE7_CODEX_USAGE.md`, targeted search for existing Apple reference mentions.
- Changed files: `docs/apple_official_reference_stage7.md`, `AGENTS.md`, `CLAUDE.md`, this usage log.
- Verification: `git diff --check`; `tools/architecture_guard/check.sh`; `tools/secret_guard/check.sh`.
- Token note: only use Apple docs as minimum implementation references; do not expand Stage 7 or copy Apple documentation text.
- Follow-up: use this rule when Stage 7 tasks touch SwiftUI / Metal / FileManager / Keychain / HIG / Accessibility.

## 7.3-abstract-bust-doc-plan

- Stage: 7.3
- Date: 2026-07-03
- Task: Add document-only Abstract Bust Avatar planning without expanding Stage 7.3 implementation scope.
- Read scope: `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/*`, `DEVLOG.md`, `docs/stage7_forbidden_checklist.md`, `docs/03_dev_plan.md`, `docs/06_product_design.md`, `docs/08_product_designer.md`, `docs/02_architecture.md`, this usage log, `docs/aftelle_runtime_boundary.md`.
- Changed files: `docs/03_dev_plan.md`, `docs/06_product_design.md`, `docs/08_product_designer.md`, `docs/02_architecture.md`, `docs/aftelle_runtime_boundary.md`, `docs/stage7_forbidden_checklist.md`, `DEVLOG.md`, this usage log.
- Verification: `git diff --check`; `tools/architecture_guard/check.sh`; `tools/secret_guard/check.sh`.
- Token note: keep Abstract Bust as design planning; do not touch Swift, Xcode, DR schema, Runtime API, Provider Profile, or `feature_livestate.md`.
- Follow-up: Stage 7.3 implementation may only build particle_core, local `avatar_mode` reserve, render switching interface, and subtitle basics.

## 7.1-livestate-doc-gate

- Stage: 7.1
- Date: 2026-07-02
- Task: Add Stage 7 live-state feature gate and align planning/boundary docs.
- Read scope: `AGENTS.md`, `CLAUDE.md`, `docs/03_dev_plan.md`, `docs/aftelle_runtime_boundary.md`, `docs/STAGE7_CODEX_USAGE.md`.
- Changed files: `docs/feature_livestate.md`, `AGENTS.md`, `CLAUDE.md`, `docs/03_dev_plan.md`, `docs/aftelle_runtime_boundary.md`, this usage log.
- Verification: documentation-only change; checked git diff and searched for `feature_livestate` references.
- Token note: do not duplicate the full 12-card table across plan/boundary docs.
- Follow-up: update Runtime API / DR contract only when implementing the specific feature card.

## 7.0-CAL-002

- Stage: 7.0-CAL-002
- Date: 2026-07-02
- Task: Empty Xcode App bootstrap.
- Read scope: `AGENTS.md`, `docs/04_code_standards.md`, `docs/05_dev_guide.md`, `DEVLOG.md`, current `apps/macos` file list.
- Changed files: new `apps/macos/Aftelle/` SwiftUI app project, `DEVLOG.md`, this usage log.
- Verification: `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -destination 'platform=macOS' -derivedDataPath /tmp/aftelle-cal-002-derived build` passed; built `Aftelle.app` launched and quit successfully; architecture guard and secret guard passed.
- Token note: keep Xcode output scoped; prefer one final build after file creation.
- Follow-up: none yet.

## 7.0-CAL-003

- Stage: 7.0-CAL-003
- Date: 2026-07-02
- Task: RuntimeCore skeleton.
- Read scope: `README.md`, `DEVLOG.md`, `docs/stage7_entry_gate.md`, `docs/runtime_api_contract.md`, `docs/aftelle_runtime_boundary.md`, `docs/dr_contract_v0_3.md`, `docs/provider_profile_contract.md`, `docs/02_architecture.md`, `docs/04_code_standards.md`, `docs/05_dev_guide.md`.
- Changed files: `apps/macos/RuntimeCore/*.swift`, `DEVLOG.md`, this usage log.
- Verification: xcodebuild -list passed; architecture_guard passed; secret_guard passed; xcodebuild build passed with custom -derivedDataPath.
- Token note: keep RuntimeCore stub minimal; do not wire UI or provider paths.
- Follow-up: Ready for CAL-004 load-dr minimal path.

## 7.0-CAL-004

- Stage: 7.0-CAL-004
- Date: 2026-07-02
- Task: load-dr minimal path
- Changed files: apps/macos/RuntimeCore/RuntimeCore.swift, apps/macos/RuntimeCore/DRLoader.swift, apps/macos/Aftelle/ContentView.swift
- Verification: xcodebuild -list passed; architecture_guard passed; secret_guard passed; build passed with custom -derivedDataPath.
- Token note: keep DR load minimal; no provider, no mock step, no trace display.
- Follow-up: 7.0-CAL-005 mock step path.

## 7.0.5

- Stage: 7.0.5
- Date: 2026-07-02
- Task: mock step path
- Changed files: apps/macos/RuntimeCore/RuntimeCore.swift, apps/macos/RuntimeCore/ExecutionEngine.swift, apps/macos/RuntimeCore/ProviderRouter.swift, apps/macos/RuntimeCore/TraceRecorder.swift, apps/macos/RuntimeCore/VisualStateMapper.swift, apps/macos/Aftelle/ContentView.swift
- Verification: xcodebuild -list passed; architecture_guard passed; secret_guard passed; build passed with custom -derivedDataPath.
- Token note: keep mock step local; no real provider, no trace UI.
- Follow-up: Stage 7.0.6 trace display.

## 7.0.6

- Stage: 7.0.6
- Date: 2026-07-02
- Task: trace + visual_state display
- Changed files: apps/macos/RuntimeCore/RuntimeCore.swift, apps/macos/RuntimeCore/ExecutionEngine.swift, apps/macos/RuntimeCore/TraceRecorder.swift, apps/macos/RuntimeCore/VisualStateMapper.swift, apps/macos/Aftelle/ContentView.swift
- Verification: xcodebuild -list passed; architecture_guard passed; secret_guard passed; build passed with custom -derivedDataPath.
- Token note: keep trace display minimal; no real provider, no DR writes.
- Follow-up: Stage 7.0.7 polish.

## 7.0.6-fix

- Stage: 7.0.6-fix
- Date: 2026-07-02
- Task: pre-review fixes
- Changed files: apps/macos/Aftelle/ContentView.swift, apps/macos/RuntimeCore/RuntimeCore.swift, apps/macos/RuntimeCore/DRLoader.swift, apps/macos/RuntimeCore/ExecutionEngine.swift, apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj, docs/STAGE7_CODEX_USAGE.md, DEVLOG.md, apps/macos/Aftelle/Fixtures/Freezev03.calibration_fixture.json
- Verification: build passed with custom -derivedDataPath; architecture_guard passed; secret_guard passed.
- Token note: keep calibration fixture minimal and safe; no real .digital_resident.
- Follow-up: none.

## 7.0.6-fix-log-cleanup

- Stage: 7.0.6-fix
- Date: 2026-07-02
- Task: log cleanup
- Changed files: DEVLOG.md, docs/STAGE7_CODEX_USAGE.md
- Verification: not rerun per request.
- Token note: keep logs aligned with current 7.0 calibration state.
- Follow-up: none.

## 7.0-final-review-fix

- Stage: 7.0 final review fix
- Date: 2026-07-02
- Task: align calibration fixture and DRLoader with DR v0.3 key fields.
- Changed files: apps/macos/Aftelle/Fixtures/Freezev03.calibration_fixture.json, apps/macos/RuntimeCore/DRLoader.swift, apps/macos/Eterna_aftelleTests/Eterna_aftelleTests.swift, DEVLOG.md, this usage log.
- Verification: JSON lint passed; Aftelle build passed; architecture_guard passed; secret_guard passed; calibration unit test passed during full Eterna_aftelle test run, while old UI test runner failed to initialize automation mode.
- Token note: keep final review fix narrow; avoid old UI test scheme for routine calibration checks.
- Follow-up: use Aftelle scheme for manual Stage 7.0 verification.

## 7.0-app-cleanup

- Stage: 7.0 app cleanup
- Date: 2026-07-02
- Task: fix bundled fixture lookup and remove old Eterna template project files.
- Changed files: apps/macos/Aftelle/ContentView.swift, deleted old apps/macos/Eterna_aftelle* files, deleted top-level apps/macos/Aftelle.xcodeproj shell, DEVLOG.md, this usage log.
- Verification: JSON lint passed; Aftelle build passed; architecture_guard passed; secret_guard passed; no Eterna references remain under apps/macos.
- Token note: keep cleanup scoped to macOS app tree only.
- Follow-up: none.

## 7.1.1

- Stage: 7.1.1
- Date: 2026-07-02
- Task: Add Platform Adapter boundary.
- Read scope: `AGENTS.md`, `README.md`, `DEVLOG.md`, `docs/03_dev_plan.md`, `docs/04_code_standards.md`, `docs/STAGE7_CODEX_USAGE.md`, `apps/macos/RuntimeCore/*`, `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`.
- Changed files: `apps/macos/RuntimeCore/PlatformAdapter.swift`, `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`, `DEVLOG.md`, this usage log.
- Verification: `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -destination 'platform=macOS' -derivedDataPath /tmp/aftelle-7-1-1-derived build` passed; `tools/architecture_guard/check.sh` ok; `tools/secret_guard/check.sh` ok.
- Token note: keep platform boundary no-op and platform-independent.
- Follow-up: proceed to 7.1.2 desktop shell only.

## 7.1.2

- Stage: 7.1.2
- Date: 2026-07-02
- Task: Organize macOS desktop shell.
- Read scope: `AGENTS.md`, `README.md`, `DEVLOG.md`, `.cursor/rules/*`, `docs/03_dev_plan.md`, `docs/02_architecture.md`, `docs/aftelle_runtime_boundary.md`, `docs/04_code_standards.md`, `apps/macos/Aftelle/*`, `apps/macos/RuntimeCore/*`.
- Changed files: `apps/macos/Aftelle/AftelleApp.swift`, `apps/macos/Aftelle/ContentView.swift`, `DEVLOG.md`, this usage log.
- Verification: `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -destination 'platform=macOS' -derivedDataPath /tmp/aftelle-7-1-2-derived build` passed; `tools/architecture_guard/check.sh` ok; `tools/secret_guard/check.sh` ok.
- Token note: keep shell thin; do not add startup flow or provider wiring.
- Follow-up: 7.1.3 startup flow only when explicitly started.

## 7.1-DOC-APPLE-HOST-RESERVE

- Stage: 7.1-DOC-APPLE-HOST-RESERVE
- Date: 2026-07-03
- Task: Add document-only Apple ecosystem Host reserve boundary.
- Read scope: `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/*`, `README.md`, `DEVLOG.md`, `docs/02_architecture.md`, `docs/03_dev_plan.md`, `docs/04_code_standards.md`, `docs/aftelle_runtime_boundary.md`, `docs/stage7_entry_gate.md`, `docs/runtime_strategy.md`, this usage log.
- Changed files: documentation only; no Swift, project, DR schema, Runtime API, provider, token, or fixture files.
- Verification: `git diff --check`; architecture guard; secret guard; documentation grep for sensitive terms.
- Token note: keep this as Stage 7.1 doc reserve, not Stage 8 or multiplatform feature work.
- Follow-up: 7.1.18 checklist should include these Host reserve prohibitions.

## 7.1.18

- Stage: 7.1.18
- Date: 2026-07-03
- Task: Add Stage 7 forbidden checklist.
- Read scope: `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/*`, `README.md`, `DEVLOG.md`, `docs/03_dev_plan.md`, `docs/stage7_entry_gate.md`, `docs/feature_livestate.md`, `docs/STAGE7_CODEX_USAGE.md`, and referenced boundary/contract docs for verification only.
- Changed files: `docs/stage7_forbidden_checklist.md`, `AGENTS.md`, `CLAUDE.md`, `DEVLOG.md`, `docs/03_dev_plan.md`, `docs/stage7_entry_gate.md`, this usage log.
- Verification: `git diff --check`; architecture guard; secret guard; documentation grep for sensitive terms.
- Token note: keep this as document / PR checklist only; do not turn it into a script, lint, or code system.
- Follow-up: use checklist before Stage 7.1 Final Review and later Stage 7 tasks.

## 7.3-final-review

- Stage: 7.3 Final Review
- Date: 2026-07-05
- Task: Final code review for Stage 7.3 particle_core visual foundation and branch handoff.
- Read scope: `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/*`, `DEVLOG.md`, Stage 7 architecture / code / product docs, Runtime / DR contracts, `apps/macos/Aftelle/*`, `apps/macos/Aftelle/ParticleCore/*`, and `apps/macos/RuntimeCore/*` read-only.
- Changed files during review: `apps/macos/Aftelle/AftelleApp.swift`, `apps/macos/Aftelle/en.lproj/Localizable.strings`, `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`, `DEVLOG.md`, this usage log.
- Verification: `git diff --check` passed; `tools/architecture_guard/check.sh` ok; `tools/secret_guard/check.sh` ok; `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug build` passed.
- Token note: final review only; no new visual tuning, no new UI, no RuntimeCore / Runtime API / DR schema changes.
- Follow-up: merge `7.3` to `main`, then branch `7.4` from updated `main`.
