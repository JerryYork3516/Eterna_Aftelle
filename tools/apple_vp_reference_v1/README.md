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

## VP-A pure echo preparation — device execution is not authorized

`vp-a` is a separate single-mode experiment entry. Its proposed protocol is
`VPA_PURE_ECHO_V1`: 2 seconds of running silence, one fixed 8-second Float32
linear PCM buffer, and a 3-second planned tail, within a 16-second recorder
admission limit including startup. These parameters require controller approval.
No automatic ON/OFF switching, retry, near-end injection, or Runtime action exists.

Future use requires `--authorize-vp-a`, both live flags, a single explicit mode,
`--duration 16`, study alias, new private output directory, `--material`,
`--material-sha256`, `--material-pcm-sha256`, and `--target-registration`.
The two expected material digests must be approved offline before either arm;
the existing material loader checks file and native buffer identities at runtime.
The target registration is the approved private P3/P4 JSON, used only as a device
allowlist. Its `QUIET_TWO_PHRASES_V1` stimulus is not reused for playback, and no
device is automatically registered. The new private manifest records a separate
VP-A protocol, control ticks, volume snapshots and bounded observation statistics.

Consent flags record operator intent; they cannot replace separate controller
approval and the user's explicit site recording/playback consent. This preparation
ran only builds, static checks and synthetic tests. `VP-A_DEVICE_NOT_RUN`.

Ordinary `record` retains its structural binding guard. `source-probe` retains
its 8-second no-material/no-play contract. Only the explicit VP-A diagnostic
path can use the already reviewed VP_ON Built-in-node presentation with stable
registered USB/Built-in defaults; it still emits `SOURCE_UNVERIFIED` and never
grants source qualification. VP_OFF requires the ordinary verified binding.

Configuration observation is installed before start. Control checks run at up
to 20 Hz; full route/state/format observations run about once per second and at
window boundaries. A returned observation exceeding the proposed 250 ms control
budget invalidates the run. This does not preempt a blocked Apple getter or prove
that engine teardown always finishes within 16 seconds. Device timing and load
remain unmeasured. Known failures stop playback/capture and seal invalid evidence;
the recorder, tap and Apple engine driver are unchanged.

Playback ticks and the planned tail are control evidence, not measured acoustic
arrival or completion. `isPlaying`, positive frame counts and a sealed container
do not prove speaker audibility, full window coverage or echo suppression. Review
every native Input/Render channel offline and preserve unknown channel roles.
The full proposed physical protocol and remaining limits are in the VP-A report.

## Future device recording — not authorized by this implementation delivery

After separate controller approval, microphone authorization and a fixed physical
protocol, a single invocation may use `record --enable-audio --arm-diagnostics`
with explicit `--mode VP_OFF` or `VP_ON`, `--duration`, `--study-id`, and a new
`--output-dir` outside every Git worktree. `--material` selects registered local
linear PCM; omit it for resident-silent near-end tests. These flags do not grant
Runtime interruption authority. Each invocation creates and tears down one engine.

The required default input is USB and output is built-in. Actual node-device
binding must be direct or supported by ordered aggregate members, active membership,
unique physical directions, complete physical/aggregate stream ranges, and zero
process taps. Missing or ambiguous evidence is BLOCKED. This is HAL structural
qualification, not physical source attribution or an AEC result. Recording checks existing
microphone permission; it never requests access. The tool does not change defaults,
volume, hardware gain or microphone mode.

## Explicit microphone permission — not exercised in this delivery

`request-microphone` is a separate, exact command. It requests access once only
when the state is NOT_DETERMINED, then checks the observed authorization result.
AUTHORIZED does not prompt; DENIED/RESTRICTED/UNAVAILABLE fail. This command never
constructs an engine or starts recording. It does not reset TCC or click a prompt.
Actual first-use prompts, permission persistence, signing and Terminal/Codex TCC
responsibility remain NOT_MEASURED despite the embedded usage description/identity.

`permission-status` only reads the current authorization enum; it neither requests
permission nor constructs an engine. `inspect-route` uses the same explicit flags
as `record`, forbids material, and writes private `prepared.json` while its engine
is alive. It does not prepare/start the engine, install taps, play, or create a PCM
recorder. Exit 0 means the snapshot was written; inspect its binding status.

VP ON connects the mixer to output with the actual input client AVAudioFormat,
then re-reads and strictly validates matching VP client formats. Initial formats
may differ before this connection; input must remain unchanged. OFF retains its
existing output client format. Configuration never changes hardware sample rate.
If inspection configuration fails, a private `configuration_failure.json` retains
the original stage/code and available state/formats from the same stopped engine;
write failure is secondary. No retry, prepare, or start is performed. Associate
this snapshot with the separately fixed executable identity; channel count does
not establish microphone or reference-channel roles.

Aggregate descriptor channel counts and actual physical channel counts are saved
separately. A discrepancy is not silently normalized. Qualification uses the
independent complete stream/direction chain; descriptor semantics and asynchronous
HAL changes may remain UNVERIFIED. Running and post-stop routes are also observed,
but multiple property reads are not atomic and do not lock the system route.

Control-path failures emit bounded PRIMARY/SECONDARY stage and stable code values,
without underlying SDK error text, device UID, paths or credentials. A failed
post-start state/format check prevents playback and scoring, then stops/removes
taps and seals admitted evidence. The first failure survives seal/write failures;
at most four secondary diagnostics are retained. A manifest is published exclusively
only after its pending file synchronizes successfully. This is not a whole-bundle
power-loss durability guarantee. Native crashes/Objective-C exceptions are outside
the tested Swift-error recovery contract.

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

## Source verification probe — separate site authorization required

`source-probe` is a separate research command, never selected by `record`.
It requires `--authorize-source-probe`, both live flags, `--mode VP_ON`,
`--duration 8`, a study alias, a new output directory outside Git, and
`--probe-registration <private-json>`. It only checks existing microphone
permission. These parameters record explicit intent; they cannot substitute for
the user's separate site recording authorization.

Registration is an owned 0600 JSON file inside an owned 0700 directory outside
Git, limited to 4096 bytes and opened without following the final symlink. Its
fields are `schemaVersion: 1`, `inputDeviceID`, `outputDeviceID` (the target
devices' existing private SHA-256 anonymous identifiers), and
`stimulusProtocol: "QUIET_TWO_PHRASES_V1"`. Prepare these privately after site
authorization; do not paste identifiers into CLI arguments or public reports.
The probe compares registered targets with USB/Built-in defaults before VP
configuration and checks them again afterward. It does not change routing.

Ordinary `record` keeps its existing guard. Probe routing admits that same
structural qualification, or only the observed case where both nodes identify
the registered Built-in output with no aggregate metadata. Other unknown node
presentations, extra devices, virtual nodes and unqualified aggregates fail.
The exception permits diagnostics only: `source_probe.sourceStatus` always
remains `SOURCE_UNVERIFIED`, and `sourceQualificationGranted` is always false.

All native input channels and digital mixer Render remain in the original
recorder format. There is no playback material, player play call, channel
selection, downmix, source classifier or network/Runtime integration. The C
admission limit is 8 seconds from arm including startup, while ordinary record
keeps 60 seconds; 64 MiB/8 MiB limits are unchanged. R2 observes real configuration
notifications; a control poll checks route/state/format and recorder invalidity
every planned 50 ms, stopping at the first observed failure. This is not an
atomic hardware guarantee or a guarantee of exactly 8 seconds of PCM.

Silent visual cues follow the arm-relative registered sequence: initial quiet
0–2 seconds; phrase one 2–3.3; quiet 3.3–4; phrase two 4–5.5; final quiet to 8.
Suggested phrases are documented in report 05. At most five control cue times
are saved. If a phase was skipped, the probe stops INVALID rather than emitting
catch-up cues. Control cue snapshots are not acoustic arrival timestamps or
proof that the user spoke. Actual stdout display and speaking delays remain
unmeasured. Every failure retains its original code and admitted evidence,
removes the listener, stops/removes taps and seals without retries.

Successful sealed PCM only establishes `INPUT_PCM_PRESENT`. Stimulus response,
USB support and USB confirmation require separate offline evidence review.
Responding to speech or matching defaults cannot automatically confirm USB.
This implementation delivery has not executed a device probe.

## Comparison boundary

Only independent VP_OFF and VP_ON are implemented. Aftelle Apple is a future,
separately approved research arm using frozen components and independent evidence;
this package does not implement that arm or alter shared production audio code.
ON/OFF changes describe the voice-processing bundle/path, not isolated AEC effect.
Physical HIL remains a proxy and cannot replace final human acceptance.
