> Published historical report. Source: `.build/test3-webrtc-optimized-freeze-20261003/optimized-software-suite-review.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Optimized WebRTC software suite — environment regression only

Frozen App SHA-256 `f4577deb09095ae4c567e617f2d22e73d4647d55930679e732416e21ddb3c24e`, branch `7.5.11`, HEAD `fbe7b77ec663832954d428bac90694447cecfba7`.
Fresh preflight and all cases used Timesintelli USB microphone
`<TIMESINTELLI_USB_UID>` and Mac built-in
speaker `BuiltInSpeakerDevice`; WebRTC AEC3 was active, fallback/input
drops/output underruns were zero, and render/capture content gaps were 10 ms.
No 28U1, iPhone recording, user speech instruction, Qwen call or formal
interrupt/cancel/clear was involved. This is not a labelled physical negative
or a real-user positive.

Run: `.build/test3-local-automation/runs/20261003T085819Z-2a5bfce3`.
The optimized 100 ms feed pump had **zero overdue chunks** in all four cases;
maximum lateness was 33.2–37.5 ms. The older software-positive capsule used
for initial Host regression had 73 overdue chunks and 1084.8 ms maximum
lateness. Therefore this new run closes that specific test-environment gap,
while it does not repair source attribution.

| Case | Runner status | Pre-injection / echo Gate frames | Pre-injection / echo forwarded spans | Post-injection forwarded spans in exact Host replay |
| --- | --- | ---: | ---: | ---: |
| normal echo only | CANDIDATE_ONLY | 0 | 0 | — |
| normal software near | FAIL | 20 | 22 | 341 |
| higher echo only | FAIL | 58 | 66 | — |
| higher software near | FAIL | 18 | 20 | 352 |

The two positive capsules replayed deterministically against the current Host
with zero recorded classifier/Gate mismatch. Their injected near signal is a
software regression input, not a physical person. The surrounding real room
audio was not independently labelled by the user, so the software-suite echo
rows cannot be promoted to physical source-attribution evidence. The separate
user-labelled pure-echo recording in `negative-review.md` already fails with
64 Gate frames and 68 forwarded spans.

**Decision:** test pump timing is now valid for mechanical regression; the
source Gate remains unsafe. Test3/03 stays BLOCKED. The Runner's `FAIL` is
retained, and formal Runtime interruption stays locked.
