> Published historical report. Source: `.build/test3-webrtc-optimized-freeze-20261003/replay-isolated/fresh-main-lag-candidate/divergence-review.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Fresh main-lag candidate: read-only higher-volume divergence review

Status: **REJECTED / STOP**. Test3/03 remains **BLOCKED**. This compares the unchanged baseline Host replay with the rejected candidate replay using the same frozen higher-volume software-injection capsule. It does not change AEC3, Host rules, thresholds, PCM, or the product binary. The surrounding room recording has no physical-human label; the injected signal is a software regression, not a Test3 physical positive.

## Pre-injection false opening

The candidate first opens at capture frame 232 and stays open through 269: 38 Gate-open frames and 40 forwarded spans before software injection. Baseline first opens at 326 and has 18 Gate-open frames in the 303-frame pre-injection segment. At frames 230–232 the candidate produces three consecutive `low_correlation_near_end` classifications. Baseline frame 231 is `uncertain`, resetting confirmation. For that frame, the already existing `processedLinearCorrelation >= 0.65` condition is false in baseline (0.644496) and true in candidate (0.706520); the remaining reported low-correlation conditions are satisfied in both. This is a concrete decision-chain difference, not a reason to change 0.65.

## Near injection loses classification, then output

The candidate changes the pre-injection calibration history. Baseline first records `resident_only` at frame 220, initially setting `residualEchoGainBaseline` to 0.058693; the candidate calls frames 220–223 `uncertain` and first records `resident_only` at 226, initially setting the gain to 3.4504. At the injected signal's first strong frame 444, baseline has seven baseline frames and candidate has three. The existing adaptive double-talk guard requires at least five. Baseline frame 444 is `immediate_double_talk` with clean RMS 0.051538; candidate frame 444 is `uncertain` with clean RMS 0.005892, below the unchanged 0.012 level floor. At frame 450, candidate clean RMS is 0.101404, but the three-frame baseline count still blocks the adaptive branch; its immediate branch also fails the current residual-correlation condition (0.465250 > 0.25).

The later interval adds a separate signal-loss mechanism. At frame 580, baseline clean RMS is 0.160305 and classifies `adaptive_double_talk`; candidate clean RMS is 0.000190, classifies `uncertain`, and its adaptive raw/residual/linear excess powers are all negative. In the first 325 injection frames (344–668), candidate has 95 frames at or above the 0.012 clean floor versus 186 baseline, but only 4 `double_talk` and 2 `near_end_speech` classifications versus 58 and 0 baseline. Neither the early classification loss nor later output suppression alone explains all 325 frames; both are visible in the trace. Candidate near forwarded is 0 versus baseline 352 across the full post-injection period.

The same candidate does not universally suppress software injection: in the frozen normal-volume case, it forwards 351 near spans versus the fixed minimum 341 and has 0 pre-injection Gate/forwarded. Thus the higher-volume failure cannot be reduced to a universal no-speech state or repaired by choosing a different fixed cutoff from these three cases.

## Interpretation and stop boundary

The data establish a causal **Host decision chain**: changing AEC3 output changes the correlation witness at frame 231, the timing of `resident_only` baseline seeding, and clean/linear evidence consumed by existing Gate conditions. They do not establish why AEC3's internal filter responds differently in this volume case, nor do they prove how a live person's voice would behave. A frame-by-frame equality check over all 1,090 capture records found no difference in capture frame index, call ordinal, raw capture RMS, external AEC buffer-delay input, or reported backend delay/active/enabled state. The learned raw-echo gain differs downstream, as expected from the changed classification history. Thus a changed raw input or external delay-control schedule does not explain the replay divergence; an internal AEC3 state witness is still missing.

This is the second rejected isolated lag-field change. Stop implementation on this delay-rule path. A future proposal must explain the early false classification and the positive signal loss together, pre-register safety and coverage against all frozen cases, and preserve current physical negative plus genuine short/long human evidence before any Runtime connection. Do not infer a Test3 Decision from replay. Stage 7 forbidden checklist: **PASS** for this read-only diagnostic; no DR, Provider, Runtime API, Store, particle, platform target, or Intent change.

Evidence: `../positive-optimized-higher/capture-frames.json`, `higher/host-replay/capture-frames.json`, both `result.json` files, `../positive-optimized-normal/capture-frames.json`, `normal/host-replay/capture-frames.json`, and the current Host classifier in `apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift` (`gatedCaptureSpans`, `classifyCapture`, `hasImmediateDoubleTalkEvidence`, `hasAdaptiveDoubleTalkEvidence`).
