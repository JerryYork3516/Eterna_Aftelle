> Published historical report. Source: `.build/test3-webrtc-optimized-freeze-20261003/negative-review.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Stage 7.5 / Test3 / 03 — optimized WebRTC physical echo negative

## Decision

**VALID PHYSICAL NEGATIVE, FAIL. Test3/03 remains BLOCKED.** The pre-registered
stop condition fired: while the user and iPhone were silent, the automatic
source Gate opened for 64 ten-millisecond frames, 68 spans were forwarded, and
Runtime recorded two acoustic-evidence events. No real-user positive was run.
Formal generation/cancel/clear remained locked at zero; that lock cannot make
the false source qualification a pass.

## Frozen identity and environment

- Repository `<LOCAL_WORKSPACE>`, branch `7.5.11`, HEAD
  `fbe7b77ec663832954d428bac90694447cecfba7`; the working tree was already
  modified, and no tracked file was changed in this attempt.
- Frozen Debug App executable SHA-256
  `f4577deb09095ae4c567e617f2d22e73d4647d55930679e732416e21ddb3c24e`;
  Swift `-O`, Debug and WebRTC macros on, signed, no separate Debug dylib.
  The four fixture hashes and device preflight are in `manifest.json`.
- Input UID `<TIMESINTELLI_USB_UID>`;
  output UID `BuiltInSpeakerDevice`; no 28U1. Route stayed exact. AEC3 was
  active with zero fallback. The near fixture was loaded but never injected;
  no phone playback, Qwen call, or formal Runtime interruption occurred.
- User confirmed silence/no knocks/no other device playback and hearing the
  Mac resident. Unedited phone memo was AirDropped, copied locally as
  `phone-negative-original.m4a` (mode 0600, SHA-256
  `6bbd08d7ad50de47ddef580a499270bfa51cc8da5ad0ee7fb3eccf30d3e423e4`).
  Memo duration was 22.357 s; its resident playback aligns with the Mac render
  track at about 8.555 s, absolute 8 s correlation 0.549. The phone track is
  a label/cross-check, not a detector input.

## Run result

The frozen App ran only `--test3-webrtc-physical-echo` in the new stage
`<LOCAL_HOME>/Library/Containers/com.eterna.aftelle.Aftelle/Data/tmp/test3-local-audio/webrtc-opt-20261003-f4577deb-echo`.
The runner returned `FAIL` and aggregate `test3_acceptance=BLOCKED`.

| Measure | Observed |
| --- | ---: |
| Capture / playback frames | 1120 / 1060 |
| Resident chunks played / scheduled | 105 / 105 |
| Render/capture maximum content gap | 10 / 10 ms |
| Input drops, output underruns, AEC fallback | 0 / 0 / 0 |
| Echo-only Gate open | **64 frames**, epochs 652–673 and 694–735 |
| Echo-only forwarded spans / Runtime acoustic evidence | **68 / 2** |
| Provisional pause / resume | 1 / 1 |
| Formal interrupt / clear / cancel | 0 / 0 / 0, deliberately locked |

The optimized native capture callback received about 100 ms of audio each
time. Host processing p50/p99/max was 14.256/20.088/20.261 ms per callback;
render callback arrival interval max was 123.443 ms, with none over 150 ms.
The old `-Onone` physical run had about 79.7 ms p50 Host processing and a
464 ms maximum render age. The current callback backlog is substantially
lower, but the two physical runs differ acoustically, so their Gate counts
must not be treated as a controlled A/B of classification quality.

## Denial witness, diagnostic only

The current production `timingMatch` prefers the expected/locked reference
near its target lag. The independent read-only all-integer-lag search in
`raw-max-witness.csv` used only causally arrived Host render samples and the
existing 0–500 ms legal domain. It found these raw capture/render matches:

| Capture frame | Production chosen lag / raw correlation | Independent raw maximum lag / correlation | Production branch |
| ---: | ---: | ---: | --- |
| 650 | 21.010 ms / 0.047 | 114.7 ms / 0.989 | adaptive double talk |
| 651 | 21.010 ms / 0.025 | 110.2 ms / 0.962 | adaptive double talk |
| 652 | 21.010 ms / 0.009 | 118.9 ms / 0.976 | adaptive double talk, Gate opens |
| 692 | 104.426 ms / 0.162 | 345.2 ms / 0.891 | adaptive double talk |
| 693 | 104.426 ms / 0.076 | 144.2 ms / 0.833 | low-correlation near end |
| 694 | 104.426 ms / 0.194 | 144.7 ms / 0.409 | adaptive double talk, Gate opens |

At frame 649, a historical raw match at 112.218 ms / 0.977 was found but did
not establish the expected/locked association: its processed residual
correlation was 0.398, below the existing 0.55 resident-only requirement,
while the linear correlation was 0.981. Frames 650–652 therefore returned to
the approximately 21 ms expected reference. The adaptive power comparison
then used a much quieter reference than the matched physical echo. This
explains one route to the first false classification, not a proven complete
fix. The second epoch has a different, less decisive lag pattern.

The Bridge reported about 8 ms internal render-buffer delay and 0.176 dB ERLE
during these frames, while raw acoustic correlation peaked around 110 ms in
the first epoch. The WebRTC delay metric is not a total speaker-to-microphone
acoustic lag, so subtracting these numbers cannot diagnose an alignment error.
Raw/clean/linear samples had no values at or above absolute 0.99, so
simple clipping was not observed. A strong raw echo match cannot by itself
deny a true double talk, and the earlier score-priority isolated candidate
already failed against a recorded physical negative and synthetic positive.
No Gate rule was changed here.

## Offline replay validity limit

`aec-delay-witness-plan.md` froze one exploratory `SetAudioBufferDelay(110)`
comparison and required byte-exact reproduction of the recorded clean and
linear AEC outputs first. The first replay **failed** because it omitted the
Host's `playbackStarted()` FIFO clear: 120 unprocessed render samples were
discarded in the entity run but kept offline, shifting the replay by 2.5 ms.
After reproducing that lifecycle event, **all 1120 clean and linear frames
matched the entity recording bit-for-bit**. The independent raw-match scan was
also rebuilt from the actual framed timing PCM; its pre-correction CSV was
retained as `raw-max-witness-before-fifo-correction.csv` and is invalid for
reference identity.

With the exact baseline fixed, the single pre-registered fixed 110 ms AEC
buffer-delay variant was run. Its clean and linear RMS and reported delay were
**identical to baseline** in both false epochs and over all playback; it did
not repair the physical echo. See `aec-delay-witness.json`.

Callback content time was checked separately in `callback-pacing-witness.json`:
100 of 106 analyzed capture callbacks had the latest already-fed render
frame 108.157 ms ahead of the first capture frame and 18.157 ms ahead of the
last. A distinct, pre-registered synthetic AEC3 experiment checked whether
100 ms batch feeding alone was sufficient to cause suppression failure.
The saved 10 ms interleaved outputs were reproduced byte-for-byte. On the
same 120 ms synthetic echo path, interleaved/batched echo-only attenuation
was -62.12694/-62.12694 dB; the estimated delay was 116 ms in both. In the
synthetic double talk, near gain was -1.237/-1.244 dB. Therefore batching
alone did not reproduce the physical failure in this control. This does not
validate the physical batch schedule; details are in
`synthetic-pacing-witness.json`.

The now-exact physical capsule was also used for one pre-registered
content-time pacing counterfactual: give AEC3 only render frames with content
time no later than each capture frame. It worsened the first false-epoch clean
RMS from 0.1232 to 0.1474 and all-playback clean RMS from 0.0409 to 0.0536;
the second false-epoch RMS changed only from 0.1240 to 0.1229. This pacing
candidate was rejected without Host Gate replay or product modification.

Finally, the exact Host replay reproduced the entity Gate decision with zero
classifier/Gate mismatch: 64 Gate frames and 68 forwarded spans. A single
isolated ambiguity veto using only the existing 0.35 and 0.7 constants cut
the negative to 21 Gate frames and 23 forwarded spans but still failed. It
was rejected before running the software positive; see
`replay-isolated/conflicting-echo-candidate-result.md`. No source-rule or
threshold change entered the working tree.

## Follow-up no-device checks

A read-only code review confirmed a reference-authority gap: `timingMatch`
selects the nearest expected or locked render window before requiring a
strong raw correlation, while the adaptive double-talk power calculation uses
that selected window's RMS. This explains the first false epoch's quiet 21 ms
reference. It is not a complete fix. Recomputing the existing raw-excess term
against a continuous approximately 112 ms reference makes frames 650 and 651
negative, but frame 652 remains approximately +0.0190 versus the unchanged
0.000144 minimum power. Frames 713–715 remain positive; frame 693 enters a
separate low-correlation near-end branch. Do not implement a lag-only fix or
turn a high raw echo correlation into a blanket double-talk veto: 110 of 189
software-positive double-talk frames also had all-domain raw correlation at
least 0.7.

The causal fixed-lag projection audit in `projection-witness.md` reconstructed
the actual render FIFO and kept one lag per 400 ms window. Pure-echo false Gate
window 690–729 had unexplained RMS 0.1321; existing software-near windows
400–439 and 600–639 had 0.0853 and 0.1965. Normalized residuals overlapped
near 0.8. Thus scalar residual energy provides no defensible separating rule
here. This software-positive run also had 73 overdue feed chunks (max late
1084.779 ms), so it is a mechanical Gate regression, not an acoustically
matched real-user acceptance control.

The original Bridge call order and 48 kHz mono format were reviewed without
finding a definite wiring defect. An isolated bridge with only an existing
WebRTC log sink enabled reproduced all 1120 clean and linear frames bit-for-bit
(`aec-internal-event-witness.json`). Its log contains no render-overrun or
render-underrun/reset event. Delay-alignment changes occurred at AEC blocks
227, 236, 500, 699, 802, 1500, 1835 and 2500. The first false Gate opened
at capture frame 652 (approximately block 1630), and the second at frame 694
(approximately block 1735); no buffer event or delay change coincided with
either onset. The change at block 1835 is near the end of the second open
epoch and cannot explain its start. This stops the specific buffer-event
hypothesis for the two onsets. The log hook and replay are ignored artifacts;
the frozen App and tracked Bridge were untouched.

An optimized software suite was then run on the same frozen binary, exact
device route and zero-overdue 100 ms feed pump. It still produced echo-period
Gate openings in three of four cases, including 20 and 18 frames before
software-near injection, while exact Host replay retained 341 and 352
post-injection forwarded spans. See `optimized-software-suite-review.md`.
These are environment/regression checks; the only user-labelled physical
negative remains the 64-frame FAIL above, and no physical WebRTC positive has
been run. Older Apple-route physical positives lack raw 48 kHz Host mic PCM,
so they cannot be exactly rerun through this frozen WebRTC AEC3 binary.

## Stop and next step

This run met the validity checks and failed the pure-echo zero-qualification
criterion. Do not run a WebRTC real-user positive or connect formal Runtime
interruption yet. The reference-selection review, causal projection audit,
bit-exact AEC event witness and optimized software regression above found no
isolated candidate that reaches zero false Gate without an unsupported
source-veto rule. The single next engineering step is to specify and
pre-register a causal source-evidence rule using the existing WebRTC inputs,
then demand zero Gate/forwarded spans on this immutable physical negative and
no loss of the optimized software-near coverage before any product change or
new physical round. A scoped read-only peer-review prompt is saved as
`read-only-external-review-prompt.md`; no external model has been invoked on
this updated evidence yet. Do not tune the rule to this recording or treat the
software regression as human acceptance. Stage 7 forbidden checklist:
**PASS** for this diagnostic-only attempt; no Runtime API, DR schema, other
platform, or tracked source changed.
