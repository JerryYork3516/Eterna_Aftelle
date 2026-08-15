#include <algorithm>
#include <memory>

#include "api/audio/echo_canceller3_factory.h"
#include "api/environment/environment_factory.h"
#include "modules/audio_processing/audio_buffer.h"

int main() {
  webrtc::Environment environment = webrtc::CreateEnvironment();
  webrtc::EchoCanceller3Factory factory;
  std::unique_ptr<webrtc::EchoControl> echo =
      factory.Create(environment, 48000, 1, 1);
  webrtc::AudioBuffer render(48000, 1, 48000, 1, 48000, 1);
  webrtc::AudioBuffer capture(48000, 1, 48000, 1, 48000, 1);
  std::fill_n(render.channels()[0], render.num_frames(), 0.0f);
  std::fill_n(capture.channels()[0], capture.num_frames(), 0.0f);
  echo->SetAudioBufferDelay(0);
  echo->AnalyzeRender(&render);
  echo->AnalyzeCapture(&capture);
  echo->ProcessCapture(&capture, false);
  return echo->GetMetrics().delay_ms < 0 ? 1 : 0;
}
