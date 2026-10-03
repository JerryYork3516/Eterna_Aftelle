> Published historical report. Source: `.build/test3-webrtc-optimized-freeze-20261003/replay-isolated/fresh-main-lag-candidate/result.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Fresh main-lag AEC3 candidate — isolated replay result

**REJECTED at the preregistered software regression. Test3/03 remains BLOCKED.**

The pinned WebRTC revision, exact input/order and unchanged Bridge were retained. Only an ignored copy of `matched_filter_lag_aggregator.cc` reported this call's already reliable **main** matched-filter lag instead of the historical histogram/pre-echo lag, at the same unchanged quality and threshold gate and with the same headroom. The fixed plan is `../fresh-main-lag-plan.md`; tracked source and formal Runtime were untouched.

The unchanged Bridge reproduced every frozen clean/linear sample bit for bit in the optimized labelled physical negative and both zero-overdue software cases. The candidate produced complete finite PCM for each. Its fixed physical clean-RMS screen passed all four windows:

| Capture frames | Baseline RMS | Candidate RMS | Candidate / baseline |
| --- | ---: | ---: | ---: |
| 580–639, pre-event | 0.017502 | 0.012222 | 0.698 |
| 650–652, first false window | 0.139735 | 0.001655 | 0.0118 |
| 692–694, second false window | 0.088140 | 0.000652 | 0.00739 |
| 713–715, third false window | 0.164515 | 0.077816 | 0.473 |

Exact current-Host replay then gave:

| Frozen capsule | Pre-injection Gate / forwarded | Post-injection near forwarded | Fixed requirement | Result |
| --- | ---: | ---: | --- | --- |
| Labelled optimized physical pure echo | **0 / 0** | — | 0 / 0 | Pass for this one negative |
| Optimized normal software near | **0 / 0** | **351** | 0 / 0 and ≥341 | Pass as mechanical regression |
| Optimized higher software near | **38 / 40** | **0** | 0 / 0 and ≥352 | **FAIL / stop** |

The higher case is a software injection with an unlabelled surrounding room recording, so it cannot prove physical person performance; it is still a required regression and disproves this candidate's coverage/safety across the frozen suite. The first physical row is an isolated replay of recorded microphone/render audio through a modified AEC3 library and the original Host, **not** a new physical live run or a Test3 Decision. The current App binary and real device route were not changed. No 400 ms short-positive or new human recording was run after the registered failure.

The higher case's frame trace localizes both failures without changing the Gate. In its first 303 active, pre-injection frames (41–343), the candidate opens 38 frames versus baseline 18, first opening at frame 232 versus 326. In the first 325 injection frames (344–668), the candidate opens 0 frames versus baseline 156; its median clean RMS falls from 0.049200 to 0.000281, and 230/325 frames are below the existing 0.012 level floor versus baseline 139/325. This is evidence that the candidate suppresses the injected near signal in this software case, not merely that Host classification changed. It does not identify how a physical person's voice would behave.

The read-only decision-chain review in `divergence-review.md` also shows an earlier classification loss while candidate clean audio is still present; the later suppression does not explain the whole failure by itself.

Evidence: `screen.json`, `physical-host-replay/result.json`, `normal/host-replay/result.json`, `higher/host-replay/result.json`, and each case's `aec-replay-guard.json`. The first field-choice candidate's failure and bit-exact internal witness are preserved in `../fresh-delay-candidate/`.

**Stop boundary:** this was the second surgical isolated delay-field candidate. Do not tune a cutoff or switch lag fields again against these frozen samples. Return to a design review that explains both higher-volume false echo and lost near coverage before any more implementation. No product source, threshold, Runtime API, DR schema or platform target was changed; no device playback/recording, reset/clean, commit or push. Stage 7 forbidden checklist: **PASS** for isolated diagnostic scope.
