# Apple VP reference v1

Independent macOS research executable for Test3. It does not link Aftelle, Qwen,
Runtime, Host/Gate, HAL VAD or WebRTC. Audio and diagnostics are OFF by default.

## Non-device checks

Run `zsh check.sh` from this directory. It builds Debug and Release, executes only
synthetic/offline tests, checks the SDK-only source boundary, runs strict SwiftLint
and the toolchain formatter, and checks the default/help and missing-flag branches.
It never invokes the live recording branch. SwiftLint 0.65.1 must be available at
`.build/support/swiftlint/swiftlint`, or supplied with `VP_SWIFTLINT_BIN`.
No lint rules are disabled or baselined. No third-party runtime package is used.

## Future device recording — not authorized by this implementation delivery

After separate controller approval, microphone authorization and a fixed physical
protocol, a single invocation may use `record --enable-audio --arm-diagnostics`
with explicit `--mode VP_OFF` or `VP_ON`, `--duration`, `--study-id`, and a new
`--output-dir` outside every Git worktree. `--material` selects registered local
linear PCM; omit it for resident-silent near-end tests. These flags do not grant
Runtime interruption authority. Each invocation creates and tears down one engine.

The required default input is USB and output is built-in. Actual node-device
binding must also be established by the available public state; unknown or
aggregate-only binding is BLOCKED rather than inferred from defaults. TCC behavior
and this binding on real devices are NOT_MEASURED. The tool does not request
microphone permission, change defaults, volume, hardware gain or microphone mode.

Native input and digital mixer Render samples are stored unchanged in a private
binary recorder, with native ASBD and per-buffer layout. Render is not measured
speaker sound pressure; VP_OFF is not ADC raw truth. The manifest identifies the
scheduled material range. Exact source-frame mapping through the mixer is
UNVERIFIED. No production converter or software near-end injection is present.

Hard recorder limits: 60 seconds from arm, 64 MiB combined native input/Render PCM,
and 8 MiB diagnostic resident buffers. The fixed playback-material allocation has
its own 8 MiB cap and is not a diagnostic copy; framework/process RSS is NOT_MEASURED.
Rejection stops diagnostic admission and marks INVALID; planned audio teardown is
independent. The planned deadline uses the same continuous Mach arm clock and
includes startup and system sleep. Raw AVAudioTime hostTime retains its distinct
domain.

`verify <private-directory>` validates the recorder container and receipt only.
It does not establish microphone truth, complete acoustic coverage, a valid
experiment, Apple AEC effectiveness or Test3 PASS. Final run interpretation also
requires the control seal outcome, manifest, source labels and physical protocol.

## Comparison boundary

Only independent VP_OFF and VP_ON are implemented. Aftelle Apple is a future,
separately approved research arm using frozen components and independent evidence;
this package does not implement that arm or alter shared production audio code.
ON/OFF changes describe the voice-processing bundle/path, not isolated AEC effect.
Physical HIL remains a proxy and cannot replace final human acceptance.
