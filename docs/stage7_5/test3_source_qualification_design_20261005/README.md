# Test3/03 · Source qualification design brief · 2026-10-05

## Assignment

Design **one implementable, falsifiable source-qualification candidate** after reading the code and evidence below. The deliverable is a design and an isolated prototype specification, not a production patch or a claim that Test3 passes.

The current fixed DTLN512 + old Host hybrid is rejected. Its two fixed LiteRT resolver comparison is closed. We need an explicit rule that distinguishes **echo-model mismatch / residual echo** from **additional near-end speech**, rather than another enhanced waveform fed into the same failed Host rules.

A proposed candidate may be unvalidated. Explain what additional evidence it uses and how the first frozen experiment can refute it. Do not answer only that no already-passing candidate exists.

## Code identity and reading order

The product-source checkpoint is `8a2373298b84247af0cb64a4dc9ce94e3fdcb545`. The final delivery commit, supplied in the review prompt, also contains this design packet. `manifest.json` pins every product file and published artifact. The Runner checkpoint preserves evidence against overwrite and verifies atomic writes; it does not change qualification, Gate, or Runtime authority.

Read these actual repository files at the **exact delivery commit**, reporting which functions were inspected:

1. [Host](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift): `processCaptureSpans`, timing/reference association, resident-only baseline, immediate/adaptive/low-correlation qualification, alternative-reference rejection, confirmation and emitted spans.
2. [Processor](../../../apps/macos/Aftelle/MacSpeechWebRTCAECProcessor.swift) and [C++ Bridge](../../../tools/webrtc_aec3/bridge/AftelleAECBridge.mm), [header](../../../tools/webrtc_aec3/bridge/AftelleAECBridge.h): actual outputs, dimensions, content delays, getters and state ownership.
3. [Capture](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift), [Brain input Bridge](../../../apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift) and [AppController](../../../apps/macos/Aftelle/AppController.swift): route lifetime, capture/render arrival and formal-interruption authority guard.
4. [Recorded replay](../../../tools/speech_aec_host_tests/RecordedAcousticReplay.swift) and [Runner](../../../apps/macos/Aftelle/Test3LocalAudioRunner.swift): labels, source/span identity, physical-versus-software evidence and asset retention.
5. [AEC sync](../../../tools/webrtc_aec3/sync.sh), [AGENTS.md](../../../AGENTS.md), [Stage7 checklist](../../stage7_forbidden_checklist.md).

The `pinned-webrtc/` directory contains **exact reference-only Git objects** from `9f30e83c018647b05804571699cf22b1f0f3409e`: residual echo estimator and dominant near-end detector headers/implementations, with LICENSE, PATENTS and AUTHORS. Their hashes and official provenance are in the manifest. These files are not a new vendored runtime or an upgrade. If a design needs other upstream functions, obtain and identify them at the same pin; do not assume current mainline behavior.

## Current failure, with the correct baselines

All physical counts below refer to the same retained, labeled pure-echo capsule, not to the older missing originals. Source classification is scored independently of formal authority guards.

| Frozen route / input | Wrong source qualifications | Confirmation chains | Gate frames | Unique forwarded source spans |
| --- | ---: | ---: | ---: | ---: |
| Original AEC3 + Host, physical pure echo | 42 | 4 | 48 | 56 |
| Rejected DTLN hybrid, physical pure echo | 14 | 1 | 10 | 12 |
| Original AEC3 + Host, software protected activity | 49 qualifications | — | — | 165 |
| Rejected DTLN hybrid, software protected activity | 19 qualifications | — | — | 23 |

The hybrid loses 142 protected original source frames and gains none. Its 14 wrong qualifications are all DTLN-final frames; fallback contributes no wrong qualification. Formal cancellation/clear/generation authority remains ungranted. That guard cannot convert false source qualification into a safe source result.

Read [the frozen comparison](evidence/dtln-source-gate-shadow-01/result.json), its source metrics, and [42 original AEC3 qualification witnesses](evidence/original-aec3-42-qualification-witnesses.json). The latter is a scalar excerpt selected by explicit `sourceFrame`, not an array index or a complete stateful replay. The original branches are 10 immediate-double-talk, 24 adaptive-double-talk and 8 low-correlation-near-end qualifications. Candidate witnesses and source-loss witnesses are separate files.

## Closed directions and limits

- Source mapping, input/cache initialization, independent recurrent state, outer FFT/IFFT and overlap-add checks did not produce a repair explaining the fixed DTLN failure. The first observable additional response decrease is Stage1 in this fixed software pair; that does not identify a unique model-internal cause.
- Original optimized execution reproduces all 337 records. Reference execution completes but preserves the fixed onset failure. See [conformance result](evidence/dtln-fixed-model-conformance-01/fixed-model-execution-conformance.json) and [closeout](evidence/dtln-candidate-closeout-01/closeout.json).
- Frozen onset `J=[54926,55056)` at 16 kHz is 130 samples / 8.125 ms. `E_AEC3=0.004203665508248569`; optimized DTLN `E=0.7519141892191115`, reference DTLN `E=0.7519151278840992`. This rejects this candidate's preset software onset condition; it does not prove physical syllable damage or reject all model families.
- Prior DTLN core-hop maximum 20.120208 ms exceeds its 8 ms hop budget. Complete online evidence-ready time and backlog remain unverified. Reference-kernel timing is not a production-performance result.
- D2, watermark, AudioSeal, simple HPF and the fixed DTLN/old-Host hybrid are rejected directions in this scope. Do not rerun or retune them. Do not reopen mask/OLA decomposition, gain repair or resolver combinations.

## Available inputs and acceptance assets

The current formal route stays **WebRTC AEC3**, using Timesintelli USB microphone + Mac built-in speaker. No 28U1. At decision time, only already-arrived raw48, processed48, genuine linear16, render history and valid route/state metadata can be consumed. A pre-Apple input candidate is mixed microphone input, not pure near-end voice. Current Bridge metrics are not a calibrated source posterior.

Processed 144 low-rate samples maps to 432 raw48 samples; linear 72 maps to 216. These are content-coordinate compensations, not computation latency or proof of the best physical alignment. The current processed/linear correlation uses an 88-sample low-rate overlap (~5.5 ms). A different signal domain cannot silently inherit the old thresholds.

| Asset | Local availability / use |
| --- | --- |
| Current retained physical negative | 1120 capture / 1119 render frames; 1060 playback-active frames; user confirmed silence and no other playback; injection off. Full local raw/render retained. |
| Software mixed/background pair | 1090 capture / 1089 render frames; raw48 source activity `[164779,320779)`; protected source frames 345–670. Initial controlled screening only. |
| Software differential source `u` | Evaluation identity from the frozen pair, not an isolated physical human waveform and never a detector input. |
| Current physical ~400 ms positive | Not established. Human recording is requested only after an isolated candidate passes initial screening. |
| Two older complete physical negative originals | Reported missing. Do not promise to replay them from summary reports or processed snippets. |

Private signals, complete tensors, weights and recordings are not in this public packet. Remote review cannot independently execute their waveform replay. Metadata hashes describe omitted local artifacts; they do not make those artifacts available. Historical protocols and `.py.txt` scripts are read-only review material, not authorization to run devices or revive a rejected experiment.

## Required design

Deliver the six items in [design-contract.md](design-contract.md): one rule, actual input contract, explicit time/lifetime validity, full pseudocode or an isolated minimal diff, frozen evaluation, and preset stops. Existing software/physical assets are sufficient to specify the initial screening without asking the user to speak now. A design is not a PASS claim.

**Status:** Stage7 scope PASS; Test3/03 BLOCKED; source Decision unpassed; Runtime interruption authority unchanged and ungranted.
