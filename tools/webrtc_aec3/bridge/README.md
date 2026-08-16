# A2.3 AEC Bridge

## Boundary

`AftelleAECBridge.h` is a pure C header. Callers see an opaque handle, error
codes, scalar PCM buffers, and a POD stats structure. WebRTC C++ types remain
inside `AftelleAECBridge.mm`.

The Bridge owns only one AEC3 instance and its two frame buffers. It does not
own a Runtime, Provider, Session, audio device, queue, or resampler. It is not
connected to an Aftelle product target in A2.3.

The API is intentionally not internally synchronized. Create, configure,
render, capture, delay, reset, stats, and destroy must be serialized by the
future Host audio-processing queue. Destroy must occur only after that queue has
stopped using the handle.

## API

| Function | Contract |
|---|---|
| `AftelleAECBridgeCreate` | Allocates an unconfigured opaque handle |
| `AftelleAECBridgeDestroy` | Releases the handle; `NULL` is a no-op |
| `AftelleAECBridgeConfigure` | Accepts only 48 kHz, mono, 480 samples |
| `AftelleAECBridgeProcessRender` | Consumes one normalized float PCM render frame |
| `AftelleAECBridgeProcessCapture` | Processes one capture frame; in-place output is supported |
| `AftelleAECBridgeProcessCaptureWithLinearOutput` | Also returns AEC3's 16 kHz mono, 160-sample linear residual for Host-only source evidence |
| `AftelleAECBridgeSetDelayMs` | Accepts 0–500 ms after configure |
| `AftelleAECBridgeReset` | Recreates AEC3 while retaining the configured delay |
| `AftelleAECBridgeGetStats` | Returns enabled, active, estimated delay, ERL, and ERLE |
| `AftelleAECBridgeErrorMessage` | Returns a stable diagnostic string for an error code |

Processing uses normalized float PCM at the C boundary. `AudioBuffer::CopyFrom`
and `CopyTo` perform the expected conversion to and from AEC3's internal
float-S16 processing scale.

## Error model

Every operation except destroy returns an explicit `AftelleAECBridgeError`.
The Bridge rejects null arguments, calls before configure, formats other than
48 kHz mono, frame sizes other than 480 samples, and delay values outside
0–500 ms. C++ exceptions are caught before crossing the C ABI and reported as
`AFTELLE_AEC_BRIDGE_INTERNAL_ERROR`.

## Verification

```sh
tools/webrtc_aec3/run_bridge_validation.sh
AFTELLE_AEC_SANITIZE=1 tools/webrtc_aec3/run_bridge_validation.sh
```

The test performs:

- pure-C header compilation;
- create/configure/reset/destroy and 100 repeated lifecycles;
- null, invalid-state, unsupported-format, invalid-frame, and invalid-delay
  checks;
- 100 continuous render/capture frames and one in-place capture frame;
- the A2.2 resident-only, user-only, and double-talk fixtures through the
  Bridge;
- byte-for-byte comparison of direct AEC3 and Bridge JSON results;
- optional AddressSanitizer and UndefinedBehaviorSanitizer execution.

Recorded result: all lifecycle/error checks PASS, all A2.2 acoustic thresholds
PASS, direct/Bridge output is identical, and ASan/UBSan reports no error.
