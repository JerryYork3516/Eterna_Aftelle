> Published historical report. Source: `.build/test3-webrtc-optimized-freeze-20261003/replay-isolated/adaptive-ablation/fresh-aec-metrics-review.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Fresh AEC3 metrics on the exact physical replay

**Result:** Fable's proposed recent-reliable-ERLE guard cannot act on either physical false-Gate epoch. The existing Host metrics cache is delayed by callback batching in general, but it was not stale at these false frames.

An isolated derivative of `aec_internal_event_witness.py` queried `AftelleAECBridgeGetStats` immediately after every 480-sample capture frame while replaying the original audio/control ordinals. All 1120 clean and linear frames reproduced the physical capsule **bit-for-bit** before metrics were interpreted. Full fresh ERLE/ERL/delay arrays are in `fresh-aec-metrics.json`.

| Capture frames | Fresh ERLE | Recorded Host-cached ERLE | Fresh estimated delay |
| --- | ---: | ---: | ---: |
| 650–652, first false confirmation | 0.175512 dB | 0.175512 dB | 8 ms |
| 692–694, second false confirmation | 0.175512 dB | 0.175512 dB | 8 ms |
| 713–715, later false run | 0.175512 dB | 0.175512 dB | 0 ms |

No fresh ERLE reached 3 dB before capture frame 735; the maximum before then was 2.741465 dB. The proposed requirement for an ERLE ≥3 dB within the preceding 30 frames is therefore false at every studied false confirmation. The physical recording did reach ≥3 dB later (frames 952–999 in the fresh per-frame series), so “this route never had reliable ERLE” would also be inaccurate. An occasional later cache difference, such as frame 1000, confirms that the Host cache can lag; it does not explain the two earlier false onsets.

ERLE and estimated delay are AEC3 metrics, not independent human-source labels. This audit does not validate an ERLE Gate rule, change the product Bridge, or justify a physical positive recording. Stage 7 forbidden checklist: **PASS** for isolated diagnostic work; Test3/03 remains **BLOCKED**.
