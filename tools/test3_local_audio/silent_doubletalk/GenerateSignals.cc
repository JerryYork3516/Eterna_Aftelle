#define main original_offline_validation_main
#include "offline_aec_validation.cc"
#undef main
#include <fstream>

void WriteSamples(const std::string& filename, const std::vector<float>& samples) {
  std::ofstream output;
  output.exceptions(std::ios::failbit | std::ios::badbit);
  output.open(filename, std::ios::binary);
  output.write(reinterpret_cast<const char*>(samples.data()),
               samples.size() * sizeof(float));
}

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  for (int mode : {0, 1, 2, 3}) {
    const bool double_talk = mode != 0;
    for (bool loud : {false, true}) {
      if (mode == 3 && loud) continue;
      Signals signals = MakeSignals(Scenario::kDoubleTalk, 120);
      const std::vector<float> near_source = mode >= 2 ? signals.near_end : std::vector<float>();
      const float gain = loud ? 2.f : 1.f;
      for (size_t i = 0; i < signals.capture.size(); ++i) {
        signals.render[i] *= gain;
        signals.echo[i] *= gain;
        if (mode == 3) signals.echo[i] = 0.f;
        if (mode >= 2) {
          // Start at a syllable boundary and retain ten complete 580 ms syllable periods.
          signals.near_end[i] = i >= 12 * kSampleRate && i < 178 * kSampleRate / 10
                                   ? near_source[i - 12 * kSampleRate] : 0.f;
        } else if (!double_talk || i < 12 * kSampleRate) {
          signals.near_end[i] = 0.f;
        }
        signals.capture[i] = signals.echo[i] + signals.near_end[i];
      }
      const std::string name = mode == 3 ? "double-talk-ending-isolated" :
          std::string(mode == 2 ? "double-talk-ending" : double_talk ? "double-talk" : "echo-only") +
          (loud ? "-loud" : "-normal");
      const std::string stem = std::string(argv[1]) + "/" + name;
      WriteSamples(stem + ".render48", signals.render);
      WriteSamples(stem + ".raw48", signals.capture);
      WriteSamples(stem + ".near48", signals.near_end);
    }
  }
}
