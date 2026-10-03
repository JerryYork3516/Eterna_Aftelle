> Published historical report. Source: `.build/test3-webrtc-optimized-freeze-20261003/replay-isolated/erle-preclass-candidate-screen.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# ERLE preclassification proposal: frozen-data screen

This is a read-only screen of the peer-proposed ERLE guard, before any code
change. It uses recorded per-frame `backendStats.erleDecibels` from the two
user-labelled WebRTC physical pure-echo negatives and the optimized software
near controls. It does not treat software near as a physical person.

The proposed guard requires a reliable ERLE observation (at least 3 dB) in
the prior 30 frames before using an ERLE below 1 dB to veto a new source
qualification. In the optimized physical negative, the first `>=3 dB`
observation is frame 961. At all six false-Gate lead frames 650–652 and
692–694, and at 713–715, ERLE is 0.1755 dB and there is **no earlier**
`>=3 dB` frame. Therefore the proposed guard cannot run where the physical
Gate first opens. The older physical negative's ERLE is 0.1755 dB throughout
all 1130 frames, so its reliable-history precondition never becomes true.

The proposal also assumes ERLE will rise during software near speech. That
is false for the optimized higher software-near capsule: all 325 frames
within its injection interval remain at 0.1755 dB, while the exact Host
replay forwards 352 post-injection spans. In the normal software-near
capsule, 306/325 injection frames have ERLE below 1 dB and none reaches
3 dB; its exact Host replay forwards 341 post-injection spans. These values
are a mechanical regression check, not a real-human source label.

The proposal is rejected **at its stated precondition**, without
implementing or tuning it. Removing the reliable-history condition would be
a different source rule and could deny real doubletalk; the existing data
do not authorize that change. Test3/03 remains BLOCKED. No device, tracked
code, Gate, threshold, or Runtime path was changed. Stage 7 forbidden
checklist: PASS for an ignored, diagnostic-only artifact.
