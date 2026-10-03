> Published historical report. Source: `.build/test3-webrtc-optimized-freeze-20261003/replay-isolated/aec3-internal-divergence/result.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Test3/03 AEC3 internal divergence witness

**Diagnostic completed for the rejected main-lag candidate; no candidate accepted. Test3/03 remains BLOCKED.**

The existing optimized labelled physical pure-echo capsule and optimized normal/higher software-injection capsules were replayed through pinned WebRTC `9f30e83c018647b05804571699cf22b1f0f3409e`. Both unchanged baseline and rejected main-lag libraries were rebuilt as logging-only copies under this ignored directory. All six replays reproduced their corresponding original clean and linear PCM **bit for bit**: physical 537,600/179,200 samples per variant, software 523,200/174,400 per case and variant, with zero mismatches. The frozen raw/render streams, control order, Host classifier and numeric thresholds were unchanged. Per-run hashes and guards are in `*/{baseline,main}/guard.json`.

## First internal divergence

The matched-filter logs are byte-identical between baseline and candidate in each case (physical and normal: 8,935 rows each; higher: 8,810). Aggregator raw main/pre-echo lag, historical histogram candidate/count and quality also match on every logged call. The first different value is solely the **reported delay**, while the histogram quality gate is still applied to its historical winner:

| Capsule | First capture frame/call | Baseline reported delay | Candidate reported delay | First applied controller change |
| --- | ---: | ---: | ---: | --- |
| Physical pure echo | 92 / 230 | 64 downsampled samples | 26 | 4 → 1 blocks |
| Normal software | 90 / 223 | 0 | 2 | frame 91: 0 → 122 blocks |
| Higher software | 89 / 196 | 0 | 36 | 0 → 2 blocks |

This confirms the narrow code change and locates the first state divergence before the Host failures. The unchanged histogram gate does **not** validate that the currently reported main lag is temporally consistent with its historical winner.

## Why the physical negative improves

At physical frames 650–652 and 692–694, baseline holds two AEC render-buffer blocks while candidate holds 26. Exact split-band sample matching identifies all 16 selected blocks in each variant as unique, previously arrived samples; adjacent blocks advance by 64 samples. The median render-to-capture content-index gap changes from 24 ms to 120 ms. In the first window, AEC refined echo-estimate/capture power rises from 0.0003 to 0.346, dominant-near-end blocks fall 8/8 → 0/8, and post-suppression/capture power falls 0.3982 → 0.000022. In the second, post-suppression power falls 0.9592 → 0.000060. This accounts for the candidate's isolated physical-negative Host replay reaching Gate/forwarded 0/0. It is not a new device run or physical-human acceptance.

Physical frames 713–715 have no controller delay in either variant (`applied_blocks=-1`). Only 3/7 baseline and 5/7 candidate aligned blocks have unique exact render and capture identities; no unique-reference conclusion is made for the remaining blocks.

## Why higher volume still fails

Before injection, both variants select the same unique, causal, continuous 124 ms render content throughout higher-volume frames 220–232 (33/33 blocks). Earlier AEC state differs from frame 89. At Host frame 231, candidate `processedLinearCorrelation` is 0.706520 versus baseline 0.644496, crossing the unchanged 0.65 predicate; candidate consequently accumulates three consecutive `low_correlation_near_end` labels and opens at frame 232. This explains the first false confirmation without a missing/future reference at that window. The trace does not isolate one filter coefficient responsible for the changed correlation.

At the software near onset, the same historical histogram winner remains 55 with count 22, while the current reliable matched-filter main lag jumps: at frame 444/call 1084 it is 798 downsampled samples and candidate reports 790; at frame 445/call 1087 it is 1,594 and candidate reports 1,586. Baseline continues to report 48. Controller applied delay jumps from baseline three blocks to candidate 49 then 99 blocks. Exact selected-render matching in frames 444–450 is 18/18 unique and causal; the median content-index gap is 124 ms baseline versus **508 ms candidate**. Candidate continuity breaks at the two jumps (15/17 adjacent pairs), then resumes. Thus the failure is a selection of different real past content, not fabricated silence or future data; the 508 ms match is not established as the physical echo path.

The AEC output then loses near coverage. In higher frames 444–450, post-suppression/capture power falls 0.9545 → 0.2988 and median suppressor gain 0.9945 → 0.0377. By frames 580–600, dominant-near-end is 53/53 baseline versus 0/53 candidate, and post-suppression/capture power is 0.4559 versus 0.0001. The earlier Host review records delayed echo-baseline seeding, then `uncertain` classifications and 0 near forwarded for the full candidate injection period. Both the early false opening and later positive loss must be solved; the candidate is **REJECTED**.

## Why the normal software pass is a limited regression

In normal software frames 444–543, Host marks playback active on 100/100 capture frames, but the AEC controller has **no applied delay** (`-1`) on all 250 internal blocks in both variants. The candidate still forwards 351 software-near spans. This confirms an existing mechanical regression, but does not establish successful double-talk discrimination with an active aligned AEC delay. It cannot override the higher-volume failure or substitute for a physical person's short utterance.

## Boundary and next work

The rejected field substitution is fully explained as an unsafe instantaneous-delay report under a historical histogram gate, with distinct downstream Host false-confirmation and AEC positive-loss chains. This is a diagnosis of **this candidate**, not proof the original WebRTC route is impossible or fixed. No third delay-field change or threshold fit is justified by these samples. Existing live-route pure-echo failure remains, and formal Runtime interruption is still locked.

Evidence: `replay.py`, `identity_audit.py`, `identity-summary.json`, `*/{baseline,main}/{matched,aggregate,controller,block}.csv`, all six `guard.json`, and the prior Host decision-chain review (local-only artifact: `../fresh-main-lag-candidate/divergence-review.md`). No device playback/recording, reset/clean, commit or push.

Stage 7 forbidden checklist: **PASS**. Touched red lines: none. Modified files: ignored copies and diagnostics under this directory only; tracked files: none. Code changed: yes, logging-only ignored copies and replay/audit scripts; product code: no. Runtime API: no. DR schema: no. New platform target: no. Stage 8: no. Stop for user confirmation now: no.
