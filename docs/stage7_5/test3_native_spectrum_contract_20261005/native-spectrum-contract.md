# Test3 · Native spectral evidence production contract

## Disposition and scope

**INPUT_CONTRACT_READY for isolated design**, at the specified source revisions. This is a source-derived production and proposed observation contract. The observer is **not implemented** and the spectra are **not currently exported by the Bridge**. No qualification algorithm, new acoustic result, source posterior, performance PASS or Test3 PASS is supplied.

Project: `0d4191fc224c4e6f5049ad329650a8161bfe9a0f`. WebRTC: `9f30e83c018647b05804571699cf22b1f0f3409e`. Every upstream file in `manifest.json` came from `git show PIN:path`, with Git blob and SHA-256. Pre-existing upstream working-tree build changes were excluded. Supplied whole function bodies and headers are reference material, not a new runtime dependency.

This resolves the missing production/call-order/source-domain information requested by GPT Pro. Actual field values, physical alignment, observational non-interference and cost require a future isolated native replay. Unknowns below remain explicit; they do not become invented waveform evidence.

## 1. Entry and units

Current `AftelleAECBridge.mm:16-24,121-142` passes one mono480 normalized Float32 frame at48k to `AudioBuffer::CopyFrom`, calls `AnalyzeCapture`, splits into three160-sample bands, then `EchoControl::ProcessCapture` with linear output. The factory overload supplies a **null neural residual estimator** (`echo_canceller3_factory.cc:34-42`); this current factory path does not acquire a neural model. A different future factory call must be identified separately.

`audio_buffer.cc:138-165` and `audio_util.h:39-72` establish FloatS16 internal amplitude: normalized input is multiplied by32768. This is not a cast to Int16. Three-band analysis filters it. Internal band0 is not every third original sample and is not an independently measured near-end voice.

`aec3_common.h:35-49`: band rate16k, block64 (4ms), FFT128, bins65. `Aec3Fft::Fft` invokes the Ooura forward transform; `FftData::Spectrum` computes `re²+im²`, without division by FFT length, window power or Hz (`aec3_fft.h:35-40`, `fft_data.h:45-75`). Thus power fields below have **FloatS16-amplitude FFT magnitude-squared per stored bin** units, not RMS, dB, a density/Hz, calibrated microphone SPL or a source probability. DC/Nyquist are retained; no implicit one-sided integration factor is applied.

Y/E use a128-point square-root Hann window, whereas render-buffer X2 uses rectangular previous+current blocks (`render_delay_buffer.cc:422-427`, `aec3_fft.h:55-59`). Same bin count/FFT scale does not mean identical window energy or calibration. The residual estimator itself applies its native gain/ERLE/reverb/audibility models; no exact physical echo upper bound follows from its output. Any proposed comparison must respect these conventions rather than transplant a Host RMS/correlation threshold.

## 2. Fields and producers

Paths in this table are under `upstream/modules/audio_processing/aec3/`.

| Field proposed for observation | Producer / definition | Support and semantic limits |
| --- | --- | --- |
| `Y2` | `echo_remover.cc:443-449`, `WindowedPaddedFft` at100-108: `abs(FFT(sqrtHann * [y_previous,y_current]))²` | Current and preceding **executed EchoRemover** band0 capture blocks; zero previous64 at fresh construction. No temporal smoothing in this field. |
| `E2_ree_input` | Same function, selected `e` from `FormLinearFilterOutput:132-146`, FFT at446 and power at449 | Selected refined/coarse residual, with possible30-sample transition. Same local capture-window coordinates asY2, plus render/adaptive-filter/model history dependencies. This is the value before suppressor clipping. |
| `S2_linear` | `LinearEchoPower:67-74,447`: `abs(Y_complex-E_complex)²` | Uses those same windowed complex spectra. It is not `Y2-E2`, not a true echo recording, and not automatically the refined subtractor's other power field. |
| `R2`, `R2_unbounded` | `ResidualEchoEstimator::Estimate`, `residual_echo_estimator.cc:193-318`; read its returned arrays at `echo_remover.cc:492`, before495 | Updated native residual estimates for this execution. Branch/state/history dependent, not independent source truth. See section4. |
| `N2_background_estimate` | `ComfortNoiseGenerator::Compute` at `echo_remover.cc:482`; getter `comfort_noise_generator.h:58-60` returns `N2_` | Persistent background estimate with current-block update or saturation hold; recursive history since its generator construction. Not an8ms sample window and not the generated noise realization. |
| `E2_suppressor_input` | `echo_remover.cc:495-501`: if post-update usable, `min(E2_ree_input,Y2)` per bin | Separate stage identity. Can be represented by rawE2 plus explicit clamp flag; never relabel a final debug dump as the REE input. |
| `nearend_spectrum_kind` | `echo_remover.cc:452`: E2 if **pre-update** usable, otherwiseY2 | Its reference aliases the original array; it observes the later E2 clipping when E2 was selected. Same selector is passed to CNG and later GetGain, at different stages. |
| `native_nearend_state_pre/post` | `suppression_gain_.IsDominantNearend()` beforeEstimate and afterGetGain | Stateful suppressor choice; not a new user's presence probability or a sufficient weak-short-speech criterion. May select a different detector implementation from config. |

N2 details (`comfort_noise_generator.cc:143-206`): `N2_` starts at1e6; non-saturated input is smoothed by `a+0.1*(b-a)`; counter>50 enables background tracking; floor is imposed. The native counter stops at1000 when the initial object is released, while background tracking continues; it is a startup counter, not total update count. Comfort-noise generation chooses `N2_initial_` until1000 non-saturated increments, but **NoiseSpectrum always returns N2_**. Saturation holds the update. There is no native calibrated noise-confidence flag; `noise_confidence=UNKNOWN`. Do not mistake this initial estimate/hold for missing computation.

## 3. Exact call order, including feedback

Within one `EchoRemoverImpl::ProcessCapture`:

1. `echo_remover.cc:383-408`: update input saturation; apply effective echo-path change/reset handling. Preserve both original/effective event and saturation fields.
2. `413-425`: render analysis; initial-state transition; subtractor processing.
3. `443-452`: form selected residual, computeY2/E2/S2, and choose nearend array using **pre-AecState::Update** usable-linear state.
4. `470-472`: `AecState::Update` changes delay/filter/ERLE/saturation/initial/transparent/quality/reverb state. Its analysis uses this block's spectra and persistent history.
5. `482-483`: CNG consumes the previously selected nearend array and updates N2, beforeE2 clipping.
6. If `capture_output_used_`, `490-492`: REE consumes **post-AecState::Update** state, rawE2 and **most recent completed GetGain suppressor nearend state**. Save raw spectra/returnedR2 now.
7. `495-506`: possibly clipE2, then select echo_spectrum using post-update usable state.
8. `524-527` / `suppression_gain.cc:409-417`: choose R2 orR2_unbounded from active config and call detectorUpdate; that produces the new nearend state used by gains and the nextREE invocation (even if other EchoRemover blocks bypassedGetGain). `529-530` then apply suppression.

Consequences: `usable_linear_pre_state_update` and `usable_linear_post_state_update` can differ in one block. REE and nearend detector are coupled estimates, not independent corroboration. The input state comes from the most recent GetGain invocation, not necessarily the preceding executed EchoRemover block when output was unused. The current-block nearend result must never be retrospectively used as the state consumed by the same block's REE. Default `use_subband_nearend_detection=false` is defined in configuration, but snapshot must identify the actual active detector (`suppression_gain.cc:373-378`) and bounded/unbounded selection, rather than assume defaults.

## 4. Residual and model validity

For the current null-neural factory path, REE has these native branches (`residual_echo_estimator.cc:245-318`):

- usable linear + non-saturated echo: `S2_linear / Erle(onset_compensated)` and unboundedERLE version, then reverb;
- saturated echo: copyY2, then the branch's applicable reverb and final scaling (not necessarily finalR2==Y2);
- non-usable, non-saturated: bin-wise maximum over the render-spectrum delay neighborhood, noise gate/stationary subtraction, echo-path power gain; optional nonlinear reverb;
- final stationarity/audibility scaling may affect **both** returned arrays.

The nonlinear render neighborhood is defined by `GetRenderIndexesToAnalyze:70-86`: inclusive offsets from `max(0,filter_delay-pre_window)` to `filter_delay+post_window`, traversed by the actual ring indices at131-165. Reverb reads a further partition at367-402 and has recursive state. Render FFTs have previous+current render-block support. A passive provenance sidecar must carry those ring entries' source identities, including original insertion and availability; an offline resident source file cannot substitute. Recursive ERLE/reverb/noise support is the retained model epoch history, not a fabricated single finite capture/render lag.

AecState initial-state activity and `SuppressionGain::initial_state_` are separate owners/read times (`aec_state.h:173-194`, `suppression_gain.h:146`, `echo_remover.cc:417-421`). Record both rather than merge them into one startup boolean.

Native flags do not imply source correctness:

- `UsableLinearEstimate` (`aec_state.h:54-56`, `.cc:396-437`) is configuration plus filter-quality usability. Its counters/convergence/external-delay/transparent conditions do not establish current-block source attribution or guaranteed convergence.
- `ActiveRender()` is accumulated activity>200 blocks (`.h:65-66`), not a current playback boolean. Current local activity at `.cc:212-227` must be distinguished.
- Capture saturation originates from a whole frame (`echo_canceller3.cc:48-54,862-873`). A delay reset may clear the state boolean after the input flag was written. Preserve both; neither identifies a speaker.
- `ExternalDelayBlocks` is latched (`aec_state.cc:366-368`); preserve the current optional input and latched value separately. Model delay is not a physical reference ground truth.
- `capture_output_used=false` bypassesREE. When EchoRemover is skipped orREE does not run, arrays are unavailable for this block. No reuse of the prior snapshot.

## 5. Blocks, capture source coordinates and readiness

The direct input identity below is scoped to actual `fixed_capture_delay_samples==0`, the current factory default. A future observer must record and assert the effective value. Nonzero fixed delay invokes `DelaySignal` after band split (`echo_canceller3.cc:901-905`); then this mapping is unsupported until its delayed-stream support is separately contracted, and must be markedINVALID rather than silently reused.

Let `h` be a1-based **backend480-sample capture call**, not a possibly batched hardware callback. Fresh frame blocker receives two80-sample low-band subframes; generated block ordinals are

`Q_h = [floor(160*(h-1)/64), floor(160*h/64))`.

| h | Direct input band interval | Produced block ordinals q | Remaining input samples |
| ---: | --- | --- | ---: |
| 1 | [0,160) | 0,1 | 32 |
| 2 | [160,320) | 2,3,4 | 0 |
| 3 | [320,480) | 5,6 | 32 |
| 4 | [480,640) | 7,8,9 | 0 |

These are FrameBlocker-local coordinates. Record an actual sidecar base `B16` for eachAEC/blocker epoch in the persistent analysis-filter band coordinate system. Blockq therefore has actual band interval `[B16+64q,B16+64(q+1))`; the table starts fromB16=0 at fresh configuration. AnAEC-only reset startsq again at0 whileB16 advances; do not reset the analysis coordinate or invent fresh filter padding. `ProcessRemainingCaptureFrameContent` produces the third block in calls2/4; record it even though some of its audio is framed later. See `echo_canceller3.cc`, `frame_blocker.cc`, `block_framer.cc`, and section8 index. Ordinary steady operation therefore produces2/3 records per call, not one10ms statistic.

`block_processor.cc:126-129` can return beforeEchoRemover when render has not started. Generatedq and executed-remover ordinal must therefore be separate. Y/E FFT support is **previous executed block + current block**; q−1 is valid only when execution was uninterrupted. Initialization zeros or held old blocks must be explicitly marked. A complete observation batch needs a status record for every generatedq, including skipped/invalid q; silence or a missing spectrum is not proof of echo-only.

Exact analysis-filter causal support is derivable from `three_band_filter_bank.cc:110-150,187-221`: output band samplep sums raw inputs `3*(p-shift-4*i)+(2-downsampling_index)`. With the nonzero filters, the envelope is `[3p-45,3p+3)`, hence analysis-epoch band interval `[A,B)` has raw48 dependency envelope `[3A-45,3B)` relative to that filter epoch. Map this through its actual raw48 origin/source-ID sidecar; never apply local resetq directly to a global raw index. This is a support envelope, not a one-to-one sample equality. Clip negative dependencies only as marked startup padding when the **AudioBuffer filter epoch is fresh**; afterAEC-only reset earlier filter memory is real prior-epoch history.

The native FFT carries128 band samples; they span a continuous8ms only when the previous/current executed blocks are adjacent. After skips, retain two distinct support intervals, not a fabricated contiguous8ms window. First evidence readiness occurs only when all supports have actually arrived and the native computation returns. For existing Bridge480 batching, record capture-call entry/exit and spectral-snapshot completion separately. Completion afterGetGain is not Host consumability: subsequentApplyGain/metrics, framing, BridgeMerge/CopyTo and actual publication remain. In the proposed caller-drained batch, consumer-ready is measured at/after the completedBridge call and publication; an internal block cannot be backdated to its mathematical sample end. Readiness also depends on already inserted render/model history. Snapshot transport and candidate computation add real time and queue delay, presently **UNMEASURED**.

Current Processor content offsets72/144 low samples correspond nominally to framing/filter/OLA compensation; they are not this internal support formula or wall-clock latency. Raw mic to band0 causal support and physical echo alignment are different questions. The best physical alignment on a future run remains **UNVERIFIED**.

## 6. Lifecycle / epochs

| Event | Current code behavior | Required observation identity |
| --- | --- | --- |
| Configure | Fresh AEC and AudioBuffers, with current bridge delay (`bridge.mm:65-80`) | IncrementAEC instance and analysis-filter epochs; fresh padding and model history. |
| BridgeReset | FreshAEC only (`bridge.mm:192-196`); existing capture/render AudioBuffers and split/merge filter states persist | IncrementAEC/model/blocker epoch, retain analysis-filter epoch. Do not call all buffers zero-initialized. |
| SetDelayMs | Store delay and forward toAEC (`bridge.mm:179-180`), not reconstruct buffers | Preserve instance, record requested delay/event; native effective buffer changes tracked separately. |
| Native delay/path change | Subtractor/AecState partial resets, suppression initial state may change | Record event generation and effective flags. It is not fresh instance or full reset of all recurrent spectra. |
| Render overrun/underrun/not-started | Native buffer/controller handling; possibly noEchoRemover | Record buffer event and source identity validity; never reuse old valid arrays. |
| Device route change/discontinuity | Not a native source identity feature | Caller must provide route epoch/gap metadata; native indices alone cannot prove physical continuity. |

`AecState` reset does not uniformly clear every state: filter quality retains previous convergence/start counters; external delay may remain latched; residual reverb/render noise state is not reset by the EchoRemover path-change handling (`aec_state.cc:143-170,366-401`, `residual_echo_estimator.cc:321-327`). Distinct epochs and local reset events must remain visible.

## 7. Proposed passive snapshot, not an implementation

See `proposed-passive-snapshot.json`. It specifies a **mono capacity3 batch per backend call**, copied into owned preallocated storage at the existing processing points. Source provenance uses metadata sidecars at capture block generation and render-ring insertion/overwrite/reset. These sidecars must follow the actual ring operations; index reuse alone is not source identity.

The six65-bin Float32 power arrays consume1560 bytes/valid block, at most4680 bytes/call for currentmono3-block maximum, plus bounded metadata. Pre-update selector flags and rawE2 must be saved before they are overwritten; returnedR2 and N2 before clamping; post-nearend after existingGetGain. Record internal spectral completion then, but expose the caller-drained complete batch only after theBridge call succeeds/returns; record actual publication time separately. E2 clamping can be represented by rawE2/Y2 plus explicit stage flag, avoiding an additional array. Copy cost is bounded but real time **NOT_MEASURED**. Reject overflow/count/order/support mismatch as invalid, do not silently drop oldest records or read only the final block.

Never retain spans into stack/scratch memory across calls. Never call `Update`, `Compute`, `Estimate`, `GetGain` or a reset a second time to obtain diagnostics. Observer reads/copies only; no detector label, oracle or source activity changes state. Publication/printing of actual spectral arrays is outside this task; future local replay must keep private derived data local.

## 8. Source index and remaining unknowns

`manifest.json` identifies all exact Git objects. Important reading anchors:

- `echo_remover.cc:67-108,132-146,383-530`: spectrum definitions, selectors, read points and call order.
- `aec_state.cc:143-170,210-291,332-437`: quality/state update, latch and reset.
- `residual_echo_estimator.cc:70-165,193-327,367-434`: render neighborhoods, branch outputs, recursive support and scaling.
- `suppression_gain.cc:373-378,385-439`: detector selection and state feedback.
- `comfort_noise_generator.cc:143-206`, `.h:57-60`: background/noise-generation distinction.
- `aec3_fft.h:35-65`, `.cc:117-146`, `fft_data.h:45-75`: window, forwardFFT and power convention.
- `echo_canceller3.cc`, `frame_blocker.cc`, `block_processor.cc`, `block_framer.cc`: complete2/3 block processing and skip semantics.
- `audio_buffer.cc:138-165`, `splitting_filter.cc`, `three_band_filter_bank.cc:110-225`: FloatS16 and source support.

UNKNOWN/NOT_ESTABLISHED: actual active configuration/field-trial values on a future run; actual per-block source-sidecar values and availability timestamps; private NoiseSpectrum confidence (no calibrated native contract exists); physical optimum alignment; observer bit-exact non-interference; full compute/queue budget; ability of these estimates to distinguish residual echo from weak真人. These are not populated by this source-only audit.

**No candidate or acoustic experiment was run.** OriginalAEC3 physical42/4/48/56 and rejectedhybrid14/1/10/12 remain historical frozen results. Software49 qualifications/165unique spans remains a source-ID/PCM protection baseline, not an entity acceptance. Stage7 scopePASS; Test3/03BLOCKED; sourceDecision unpassed; Runtime authority unchanged and ungranted.

Unique next step: GPT Pro uses this production contract and fixed function bodies to finish one implementable spectral qualification hypothesis, with its parameter origins, complete pseudocode and preset screening/stops. Source inspection completion is not permission to attach it to formal interruption.
