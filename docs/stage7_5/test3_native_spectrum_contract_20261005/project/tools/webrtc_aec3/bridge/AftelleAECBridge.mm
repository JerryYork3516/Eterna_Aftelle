#include "AftelleAECBridge.h"

#include <memory>
#include <new>

#include "api/audio/echo_canceller3_factory.h"
#include "api/environment/environment_factory.h"
#include "modules/audio_processing/audio_buffer.h"

namespace {

constexpr int kSampleRateHz = 48000;
constexpr int kLinearOutputSampleRateHz = 16000;
constexpr int kChannelCount = 1;
constexpr size_t kFrameSamples = 480;
constexpr size_t kLinearOutputFrameSamples = 160;
constexpr int kMaximumDelayMs = 500;

std::unique_ptr<webrtc::EchoControl> CreateAEC() {
  webrtc::Environment environment = webrtc::CreateEnvironment();
  webrtc::EchoCanceller3Config config;
  config.filter.export_linear_aec_output = true;
  webrtc::EchoCanceller3Factory factory(config);
  return factory.Create(environment, kSampleRateHz, kChannelCount, kChannelCount);
}

}  // namespace

struct AftelleAECBridge {
  bool configured = false;
  int delay_ms = 0;
  webrtc::StreamConfig stream_config{kSampleRateHz, kChannelCount};
  webrtc::StreamConfig linear_output_stream_config{kLinearOutputSampleRateHz,
                                                     kChannelCount};
  std::unique_ptr<webrtc::EchoControl> aec;
  std::unique_ptr<webrtc::AudioBuffer> render;
  std::unique_ptr<webrtc::AudioBuffer> capture;
  std::unique_ptr<webrtc::AudioBuffer> linear_output;
};

extern "C" {

AftelleAECBridgeError AftelleAECBridgeCreate(AftelleAECBridge** out_bridge) {
  if (!out_bridge) {
    return AFTELLE_AEC_BRIDGE_NULL_ARGUMENT;
  }
  *out_bridge = new (std::nothrow) AftelleAECBridge();
  return *out_bridge ? AFTELLE_AEC_BRIDGE_OK : AFTELLE_AEC_BRIDGE_INTERNAL_ERROR;
}

void AftelleAECBridgeDestroy(AftelleAECBridge* bridge) { delete bridge; }

AftelleAECBridgeError AftelleAECBridgeConfigure(AftelleAECBridge* bridge, int32_t sample_rate_hz,
                                                int32_t channel_count, size_t frame_samples) {
  if (!bridge) {
    return AFTELLE_AEC_BRIDGE_NULL_ARGUMENT;
  }
  if (sample_rate_hz != kSampleRateHz || channel_count != kChannelCount) {
    return AFTELLE_AEC_BRIDGE_UNSUPPORTED_FORMAT;
  }
  if (frame_samples != kFrameSamples) {
    return AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE;
  }

  try {
    auto aec = CreateAEC();
    auto render = std::make_unique<webrtc::AudioBuffer>(
        kSampleRateHz, kChannelCount, kSampleRateHz, kChannelCount, kSampleRateHz, kChannelCount);
    auto capture = std::make_unique<webrtc::AudioBuffer>(
        kSampleRateHz, kChannelCount, kSampleRateHz, kChannelCount, kSampleRateHz, kChannelCount);
    auto linear_output = std::make_unique<webrtc::AudioBuffer>(
        kLinearOutputSampleRateHz, kChannelCount,
        kLinearOutputSampleRateHz, kChannelCount,
        kLinearOutputSampleRateHz, kChannelCount);
    aec->SetAudioBufferDelay(bridge->delay_ms);
    bridge->aec = std::move(aec);
    bridge->render = std::move(render);
    bridge->capture = std::move(capture);
    bridge->linear_output = std::move(linear_output);
    bridge->configured = true;
    return AFTELLE_AEC_BRIDGE_OK;
  } catch (...) {
    return AFTELLE_AEC_BRIDGE_INTERNAL_ERROR;
  }
}

AftelleAECBridgeError AftelleAECBridgeProcessRender(AftelleAECBridge* bridge, const float* mono_pcm,
                                                    size_t frame_samples) {
  if (!bridge || !mono_pcm) {
    return AFTELLE_AEC_BRIDGE_NULL_ARGUMENT;
  }
  if (!bridge->configured) {
    return AFTELLE_AEC_BRIDGE_INVALID_STATE;
  }
  if (frame_samples != kFrameSamples) {
    return AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE;
  }

  try {
    const float* channels[] = {mono_pcm};
    bridge->render->CopyFrom(channels, bridge->stream_config);
    bridge->render->SplitIntoFrequencyBands();
    bridge->aec->AnalyzeRender(bridge->render.get());
    return AFTELLE_AEC_BRIDGE_OK;
  } catch (...) {
    return AFTELLE_AEC_BRIDGE_INTERNAL_ERROR;
  }
}

static AftelleAECBridgeError ProcessCapture(
    AftelleAECBridge* bridge, const float* input_mono_pcm,
    float* output_mono_pcm, size_t frame_samples,
    float* linear_output_mono_pcm, size_t linear_output_frame_samples) {
  if (!bridge || !input_mono_pcm || !output_mono_pcm) {
    return AFTELLE_AEC_BRIDGE_NULL_ARGUMENT;
  }
  if (!bridge->configured) {
    return AFTELLE_AEC_BRIDGE_INVALID_STATE;
  }
  if (frame_samples != kFrameSamples) {
    return AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE;
  }
  if (linear_output_mono_pcm &&
      linear_output_frame_samples != kLinearOutputFrameSamples) {
    return AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE;
  }

  try {
    const float* input_channels[] = {input_mono_pcm};
    bridge->capture->CopyFrom(input_channels, bridge->stream_config);
    bridge->aec->AnalyzeCapture(bridge->capture.get());
    bridge->capture->SplitIntoFrequencyBands();
    bridge->aec->ProcessCapture(bridge->capture.get(),
                                bridge->linear_output.get(), false);
    bridge->capture->MergeFrequencyBands();
    float* output_channels[] = {output_mono_pcm};
    bridge->capture->CopyTo(bridge->stream_config, output_channels);
    if (linear_output_mono_pcm) {
      float* linear_output_channels[] = {linear_output_mono_pcm};
      bridge->linear_output->CopyTo(bridge->linear_output_stream_config,
                                    linear_output_channels);
    }
    return AFTELLE_AEC_BRIDGE_OK;
  } catch (...) {
    return AFTELLE_AEC_BRIDGE_INTERNAL_ERROR;
  }
}

AftelleAECBridgeError AftelleAECBridgeProcessCapture(AftelleAECBridge* bridge,
                                                     const float* input_mono_pcm,
                                                     float* output_mono_pcm,
                                                     size_t frame_samples) {
  return ProcessCapture(bridge, input_mono_pcm, output_mono_pcm, frame_samples,
                        nullptr, 0);
}

AftelleAECBridgeError AftelleAECBridgeProcessCaptureWithLinearOutput(
    AftelleAECBridge* bridge, const float* input_mono_pcm,
    float* output_mono_pcm, size_t frame_samples,
    float* linear_output_mono_pcm, size_t linear_output_frame_samples) {
  if (!linear_output_mono_pcm) {
    return AFTELLE_AEC_BRIDGE_NULL_ARGUMENT;
  }
  return ProcessCapture(bridge, input_mono_pcm, output_mono_pcm, frame_samples,
                        linear_output_mono_pcm,
                        linear_output_frame_samples);
}

AftelleAECBridgeError AftelleAECBridgeSetDelayMs(AftelleAECBridge* bridge, int32_t delay_ms) {
  if (!bridge) {
    return AFTELLE_AEC_BRIDGE_NULL_ARGUMENT;
  }
  if (!bridge->configured) {
    return AFTELLE_AEC_BRIDGE_INVALID_STATE;
  }
  if (delay_ms < 0 || delay_ms > kMaximumDelayMs) {
    return AFTELLE_AEC_BRIDGE_INVALID_DELAY;
  }
  bridge->delay_ms = delay_ms;
  bridge->aec->SetAudioBufferDelay(delay_ms);
  return AFTELLE_AEC_BRIDGE_OK;
}

AftelleAECBridgeError AftelleAECBridgeReset(AftelleAECBridge* bridge) {
  if (!bridge) {
    return AFTELLE_AEC_BRIDGE_NULL_ARGUMENT;
  }
  if (!bridge->configured) {
    return AFTELLE_AEC_BRIDGE_INVALID_STATE;
  }

  try {
    auto aec = CreateAEC();
    aec->SetAudioBufferDelay(bridge->delay_ms);
    bridge->aec = std::move(aec);
    return AFTELLE_AEC_BRIDGE_OK;
  } catch (...) {
    return AFTELLE_AEC_BRIDGE_INTERNAL_ERROR;
  }
}

AftelleAECBridgeError AftelleAECBridgeGetStats(AftelleAECBridge* bridge,
                                               AftelleAECBridgeStats* out_stats) {
  if (!bridge || !out_stats) {
    return AFTELLE_AEC_BRIDGE_NULL_ARGUMENT;
  }
  if (!bridge->configured) {
    return AFTELLE_AEC_BRIDGE_INVALID_STATE;
  }

  const webrtc::EchoControl::Metrics metrics = bridge->aec->GetMetrics();
  out_stats->enabled = 1;
  out_stats->active = bridge->aec->ActiveProcessing() ? 1 : 0;
  out_stats->estimated_delay_ms = metrics.delay_ms;
  out_stats->erl_db = metrics.echo_return_loss;
  out_stats->erle_db = metrics.echo_return_loss_enhancement;
  return AFTELLE_AEC_BRIDGE_OK;
}

const char* AftelleAECBridgeErrorMessage(AftelleAECBridgeError error) {
  switch (error) {
    case AFTELLE_AEC_BRIDGE_OK:
      return "ok";
    case AFTELLE_AEC_BRIDGE_NULL_ARGUMENT:
      return "null argument";
    case AFTELLE_AEC_BRIDGE_INVALID_STATE:
      return "bridge is not configured";
    case AFTELLE_AEC_BRIDGE_UNSUPPORTED_FORMAT:
      return "only 48 kHz mono is supported";
    case AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE:
      return "frame must contain 480 samples";
    case AFTELLE_AEC_BRIDGE_INVALID_DELAY:
      return "delay must be between 0 and 500 ms";
    case AFTELLE_AEC_BRIDGE_INTERNAL_ERROR:
      return "internal error";
  }
  return "unknown error";
}

}  // extern "C"
