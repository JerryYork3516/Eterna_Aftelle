# A2.2 offline AEC3 validation

## Scope

This validation links directly against the pinned
`third_party/webrtc_aec3/WebRTCAEC3.xcframework`. It does not use Aftelle's
Capture, Playback, RuntimeCore, Qwen, an Objective-C++ bridge, or an Xcode
product target.

## Audio contract

- 48 kHz, mono, normalized float PCM
- 480 samples per frame (10 ms)
- `render -> SplitIntoFrequencyBands -> AnalyzeRender`
- `capture -> AnalyzeCapture -> SplitIntoFrequencyBands -> ProcessCapture -> MergeFrequencyBands`
- 20 seconds per case; scoring uses seconds 12–20 after convergence
- `SetAudioBufferDelay(0)`: the offline render/capture calls are synchronous
  and have no hardware buffer latency. Acoustic-path delay remains in the
  synthesized capture and is estimated by AEC3.
- Output/reference comparison compensates only the measured 434-sample
  analysis/synthesis filter-bank group delay, searched deterministically within
  a maximum 20 ms window.

## Deterministic fixtures

All fixtures are generated in memory from fixed seeds. No product recording or
user audio is read.

- **resident-only:** fixed-seed broadband, amplitude-modulated resident signal;
  capture is a 0.48 direct echo plus 0.20 and 0.11 reflections at +3 ms and
  +11 ms.
- **user-only:** independent voiced signal with changing fundamental,
  harmonics, breath component, 430 ms syllables, and 150 ms pauses.
- **double-talk:** the exact resident echo path plus the independent user
  signal.
- Echo-path delays: 20, 60, and 120 ms.

## Acceptance thresholds

The thresholds are evaluated only after the 12-second convergence point.

| Case | Required |
|---|---|
| resident-only | output/capture attenuation <= -15 dB and estimated delay error <= 8 ms |
| user-only | near-end gain between -1.5 and +1.5 dB; aligned correlation >= 0.98 |
| double-talk | echo coefficient <= -12 dB; near-end gain >= -3 dB; aligned correlation >= 0.80; estimated delay error <= 8 ms |

Double-talk coefficients are obtained by a two-variable least-squares fit of
the processed output against the known near-end and echo fixture components.
This prevents total RMS reduction from being mistaken for successful echo
cancellation.

## Recorded result

| Case | Path delay | Echo/total attenuation | Near gain | Near correlation | Estimated delay | ERL | ERLE | Result |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| resident-only | 20 ms | -62.072 dB | — | — | 16 ms | 10.574 dB | 132.717 dB | PASS |
| resident-only | 60 ms | -62.084 dB | — | — | 56 ms | 10.573 dB | 132.716 dB | PASS |
| resident-only | 120 ms | -62.127 dB | — | — | 116 ms | 10.574 dB | 132.766 dB | PASS |
| user-only | n/a | -0.520 dB total | -0.520 dB | 0.999 | no echo estimate | -30.000 dB | 0.176 dB | PASS |
| double-talk | 20 ms | -47.721 dB echo | -1.018 dB | 0.980 | 16 ms | 10.098 dB | 10.868 dB | PASS |
| double-talk | 60 ms | -45.910 dB echo | -1.010 dB | 0.980 | 56 ms | 10.151 dB | 14.202 dB | PASS |
| double-talk | 120 ms | -54.105 dB echo | -1.062 dB | 0.977 | 116 ms | 10.175 dB | 11.353 dB | PASS |

## Commands

Normal local run:

```sh
tools/webrtc_aec3/run_offline_aec_validation.sh
```

Explicit no-network run on macOS:

```sh
/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' \
  tools/webrtc_aec3/run_offline_aec_validation.sh
```
