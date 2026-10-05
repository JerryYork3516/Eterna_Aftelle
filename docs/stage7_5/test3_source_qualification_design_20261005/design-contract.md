# GPT Pro design deliverable

## 1. One testable source rule

Provide one candidate, not a menu of models or a general literature review. State the physical/statistical hypothesis: which observable differentiates echo-model error from additional near-end speech, and under which conditions it is invalid or ambiguous. Explain the difference from each of the three failed Host qualification arms. Finding echo energy does not prove the absence of a user; finding residual energy does not prove a user.

State all parameters and their sources before the screening run. Do not fit a threshold, window, lag, confirmation count or gain to the supplied failure frames. Existing qualification thresholds remain frozen; a genuinely new statistic must have its own justified definition and preset protocol, not inherit a threshold from a different signal domain. If the candidate cannot be specified from available evidence, identify the exact missing quantity or contract; do not merely say "need another model/head/sensor".

## 2. Actual, causal inputs

For every consumed quantity, name the producer/file/function, rate, units, sample/content coordinate, arrival guarantee and route epoch. The available external inputs are raw48, processed48, real linear16 and already-arrived render history. Labels, original `u`, future windows, iPhone recordings and offline oracle lags are evaluation-only.

If additional AEC3 internals are required, specify their producer and read point at fixed upstream `9f30e83c018647b05804571699cf22b1f0f3409e`, frequency domain/units, valid conditions, state ownership and cost of passive exposure. Identify missing upstream files honestly. Current Bridge outputs must not be described as already exposing an unavailable residual PSD or posterior. `dominant_nearend` is a suppression state, not by itself proof of every weak short utterance.

## 3. Validity, lifetime and actual ready time

Specify initialization, warmup, resident-only baseline admissibility, route changes, playback start/stop/tail, history gaps, lost or duplicate frames, reset and recovery. Separate `QUALIFIED`, `UNQUALIFIED` and `INVALID`; invalid evidence cannot count as a successful negative control.

Define support intervals and the first instant all supporting samples/state are actually available. Then add computation completion and queue delay. Content-delay compensation (432/216 raw48 samples) is separate from wall-clock decision latency. No retrospective backfill into an earlier decision. Include per-frame/batch scheduling and a preset budget for the actual target Mac; measure P99, max and backlog after isolated implementation, not just average time.

## 4. Complete implementation specification

Give full initialization/per-frame/state-update/reset pseudocode or a minimal isolated prototype diff, including exact inputs, numerical guards, output state and first-failure reason. A prose description such as "use a residual echo estimator" is insufficient. Keep production PCM, Gate, Runtime cancellation/clear/generation and the current formal backend unchanged during the prototype. Root will implement after review; this assignment does not authorize direct repository modification.

## 5. Frozen initial experiment

Use the retained physical pure-echo negative and software mixed/background pair with complete original prehistory/arrival order locally. Do not rerun closed DTLN/kernel/filter variants. Freeze input/file/build hashes, parameter values, event schedule, activity labels, source/sample mapping, numerical tolerances and timing budget before execution.

Score independently:

- source qualifications and first-failure conditions, including invalid coverage;
- consecutive confirmation chains and Gate recommendations, separately from authority guards;
- unique emitted spans attributed to their own original source IDs, including pre-roll released later;
- retained source activity, unchanged PCM and fixed onset response where the source evaluation permits it;
- evidence-ready time, compute completion and queue backlog.

Do not equate total forwarded counts with speech fidelity. Do not let HAL=false or disabled formal authority conceal an incorrect source rule. Do not use the software pair as physical真人 acceptance. Real long double-talk and ~400 ms short-utterance acceptance remains a later labeled entity test, after screening passes and the user confirms readiness.

## 6. Preset decisions

Any wrong source qualification or confirmation in a valid labeled physical pure-echo window rejects the candidate. Any added loss of protected source activity/PCM, failure of the frozen onset condition, unaccounted identity/support gap, or actual timing-budget failure blocks advancement. Report invalid coverage explicitly; invalidation is not a way to manufacture zero false positives.

If rejected, report which preset condition failed without trying another threshold/window/lag/gain on the same data. If screening succeeds, call it an isolated candidate result and identify the remaining real short/long physical acceptance requirements. It is not Test3 PASS or permission to connect formal Runtime interruption.

Conclude with: `DESIGN_CANDIDATE` and a runnable specification, or `DESIGN_BLOCKED` with an exact missing input/contract and the smallest way to obtain it. Neither label is `Test3 PASS`.
