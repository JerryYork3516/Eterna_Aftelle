#ifndef AFTELLE_AEC_BRIDGE_H_
#define AFTELLE_AEC_BRIDGE_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AftelleAECBridge AftelleAECBridge;

typedef enum AftelleAECBridgeError {
  AFTELLE_AEC_BRIDGE_OK = 0,
  AFTELLE_AEC_BRIDGE_NULL_ARGUMENT = 1,
  AFTELLE_AEC_BRIDGE_INVALID_STATE = 2,
  AFTELLE_AEC_BRIDGE_UNSUPPORTED_FORMAT = 3,
  AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE = 4,
  AFTELLE_AEC_BRIDGE_INVALID_DELAY = 5,
  AFTELLE_AEC_BRIDGE_INTERNAL_ERROR = 6,
} AftelleAECBridgeError;

typedef struct AftelleAECBridgeStats {
  int32_t enabled;
  int32_t active;
  int32_t estimated_delay_ms;
  double erl_db;
  double erle_db;
} AftelleAECBridgeStats;

AftelleAECBridgeError AftelleAECBridgeCreate(AftelleAECBridge** out_bridge);
void AftelleAECBridgeDestroy(AftelleAECBridge* bridge);

AftelleAECBridgeError AftelleAECBridgeConfigure(AftelleAECBridge* bridge,
                                                int32_t sample_rate_hz,
                                                int32_t channel_count,
                                                size_t frame_samples);

AftelleAECBridgeError AftelleAECBridgeProcessRender(AftelleAECBridge* bridge,
                                                    const float* mono_pcm,
                                                    size_t frame_samples);

AftelleAECBridgeError AftelleAECBridgeProcessCapture(
    AftelleAECBridge* bridge, const float* input_mono_pcm,
    float* output_mono_pcm, size_t frame_samples);

AftelleAECBridgeError AftelleAECBridgeSetDelayMs(AftelleAECBridge* bridge,
                                                 int32_t delay_ms);

AftelleAECBridgeError AftelleAECBridgeReset(AftelleAECBridge* bridge);

AftelleAECBridgeError AftelleAECBridgeGetStats(
    AftelleAECBridge* bridge, AftelleAECBridgeStats* out_stats);

const char* AftelleAECBridgeErrorMessage(AftelleAECBridgeError error);

#ifdef __cplusplus
}
#endif

#endif  // AFTELLE_AEC_BRIDGE_H_
