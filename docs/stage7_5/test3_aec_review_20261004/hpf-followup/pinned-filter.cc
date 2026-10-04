#include <algorithm>
#include <cstddef>
#include <vector>
#include "modules/audio_processing/high_pass_filter.h"

extern "C" int AftelleDiagnosticHighPass(const float* input, float* output,
                                        size_t count) {
  if (!input || !output || count == 0 || count % 480 != 0) return -1;
  webrtc::HighPassFilter filter(48000, 1);
  std::vector<std::vector<float>> frame(1, std::vector<float>(480));
  for (size_t offset = 0; offset < count; offset += 480) {
    std::copy(input + offset, input + offset + 480, frame[0].begin());
    filter.Process(&frame);
    std::copy(frame[0].begin(), frame[0].end(), output + offset);
  }
  return 0;
}
