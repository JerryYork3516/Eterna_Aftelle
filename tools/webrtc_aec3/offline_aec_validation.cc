#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "api/audio/echo_canceller3_factory.h"
#include "api/environment/environment_factory.h"
#include "modules/audio_processing/audio_buffer.h"

namespace {

constexpr int kSampleRate = 48000;
constexpr int kFrameMs = 10;
constexpr int kFrameSamples = kSampleRate * kFrameMs / 1000;
constexpr int kDurationSeconds = 20;
constexpr int kEvaluationStartSeconds = 12;
constexpr float kEpsilon = 1e-12f;

enum class Scenario { kResidentOnly, kUserOnly, kDoubleTalk };

struct Signals {
  std::vector<float> render;
  std::vector<float> echo;
  std::vector<float> near_end;
  std::vector<float> capture;
};

struct Result {
  std::string scenario;
  int path_delay_ms;
  int reported_buffer_delay_ms;
  double input_rms;
  double output_rms;
  double attenuation_db;
  double near_gain_db;
  double near_correlation;
  double echo_gain_db;
  double erl_db;
  double erle_db;
  int estimated_delay_ms;
  int delay_error_ms;
  int alignment_lag_samples;
  bool passed;
};

class DeterministicNoise {
 public:
  explicit DeterministicNoise(uint32_t seed) : state_(seed) {}

  float Next() {
    state_ ^= state_ << 13;
    state_ ^= state_ >> 17;
    state_ ^= state_ << 5;
    return static_cast<float>(state_) / static_cast<float>(UINT32_MAX) * 2.0f -
           1.0f;
  }

 private:
  uint32_t state_;
};

std::vector<float> MakeSpeechLikeSignal(uint32_t seed, float level,
                                        double modulation_hz) {
  const size_t sample_count = kDurationSeconds * kSampleRate;
  std::vector<float> signal(sample_count);
  DeterministicNoise noise(seed);
  float low = 0.0f;
  float mid = 0.0f;
  float previous_low = 0.0f;

  for (size_t i = 0; i < sample_count; ++i) {
    const double time = static_cast<double>(i) / kSampleRate;
    const float white = noise.Next();
    low = 0.93f * low + 0.07f * white;
    mid = 0.72f * mid + 0.28f * (white - previous_low);
    previous_low = low;
    const float envelope = static_cast<float>(
        0.64 + 0.24 * std::sin(2.0 * M_PI * modulation_hz * time) +
        0.12 * std::sin(2.0 * M_PI * 0.37 * time));
    signal[i] = level * envelope * (0.72f * low + 0.28f * mid);
  }
  return signal;
}

std::vector<float> MakeNearEndSignal() {
  const size_t sample_count = kDurationSeconds * kSampleRate;
  std::vector<float> signal(sample_count);
  DeterministicNoise noise(0xc41f29u);
  double phase = 0.0;
  float breath = 0.0f;

  for (size_t i = 0; i < sample_count; ++i) {
    const double time = static_cast<double>(i) / kSampleRate;
    const double syllable_phase = std::fmod(time, 0.58);
    const double active_phase = std::min(syllable_phase / 0.43, 1.0);
    const float envelope = syllable_phase < 0.43
                               ? static_cast<float>(0.2 + 0.8 *
                                     std::sin(M_PI * active_phase) *
                                     std::sin(M_PI * active_phase))
                               : 0.0f;
    const double fundamental_hz =
        175.0 + 28.0 * std::sin(2.0 * M_PI * 0.31 * time);
    phase += 2.0 * M_PI * fundamental_hz / kSampleRate;
    breath = 0.82f * breath + 0.18f * noise.Next();
    const float voiced = static_cast<float>(
        (std::sin(phase) + 0.42 * std::sin(2.0 * phase) +
         0.18 * std::sin(3.0 * phase)) /
        1.6);
    signal[i] = 0.22f * envelope * (0.9f * voiced + 0.1f * breath);
  }
  return signal;
}

Signals MakeSignals(Scenario scenario, int path_delay_ms) {
  Signals signals;
  signals.render = MakeSpeechLikeSignal(0x71a3c5u, 0.62f, 2.3);
  signals.near_end = MakeNearEndSignal();
  signals.echo.assign(signals.render.size(), 0.0f);
  signals.capture.assign(signals.render.size(), 0.0f);

  const size_t direct_delay = path_delay_ms * kSampleRate / 1000;
  const size_t early_reflection = direct_delay + 3 * kSampleRate / 1000;
  const size_t late_reflection = direct_delay + 11 * kSampleRate / 1000;

  for (size_t i = 0; i < signals.render.size(); ++i) {
    float echo = 0.0f;
    if (i >= direct_delay) {
      echo += 0.48f * signals.render[i - direct_delay];
    }
    if (i >= early_reflection) {
      echo += 0.20f * signals.render[i - early_reflection];
    }
    if (i >= late_reflection) {
      echo += 0.11f * signals.render[i - late_reflection];
    }
    signals.echo[i] = echo;

    switch (scenario) {
      case Scenario::kResidentOnly:
        signals.capture[i] = echo;
        break;
      case Scenario::kUserOnly:
        signals.capture[i] = signals.near_end[i];
        break;
      case Scenario::kDoubleTalk:
        signals.capture[i] = echo + signals.near_end[i];
        break;
    }
  }
  return signals;
}

double Dot(const std::vector<float>& left, const std::vector<float>& right,
           size_t start) {
  double sum = 0.0;
  for (size_t i = start; i < left.size(); ++i) {
    sum += static_cast<double>(left[i]) * right[i];
  }
  return sum;
}

double Rms(const std::vector<float>& signal, size_t start) {
  return std::sqrt(Dot(signal, signal, start) / (signal.size() - start));
}

double DbRatio(double numerator, double denominator) {
  return 20.0 * std::log10(std::max(numerator, static_cast<double>(kEpsilon)) /
                           std::max(denominator, static_cast<double>(kEpsilon)));
}

double DotAligned(const std::vector<float>& output,
                  const std::vector<float>& reference, size_t start,
                  size_t lag_samples) {
  double sum = 0.0;
  for (size_t i = start + lag_samples; i < output.size(); ++i) {
    sum += static_cast<double>(output[i]) * reference[i - lag_samples];
  }
  return sum;
}

double CorrelationAtLag(const std::vector<float>& output,
                        const std::vector<float>& reference, size_t start,
                        size_t lag_samples) {
  double output_energy = 0.0;
  double reference_energy = 0.0;
  for (size_t i = start + lag_samples; i < output.size(); ++i) {
    output_energy += static_cast<double>(output[i]) * output[i];
    reference_energy +=
        static_cast<double>(reference[i - lag_samples]) *
        reference[i - lag_samples];
  }
  return DotAligned(output, reference, start, lag_samples) /
         std::sqrt(std::max(output_energy * reference_energy,
                            static_cast<double>(kEpsilon)));
}

size_t FindAlignmentLag(const std::vector<float>& output,
                        const std::vector<float>& reference, size_t start) {
  size_t best_lag = 0;
  double best_correlation = -1.0;
  for (size_t lag = 0; lag <= 2 * kFrameSamples; ++lag) {
    const double correlation =
        CorrelationAtLag(output, reference, start, lag);
    if (correlation > best_correlation) {
      best_correlation = correlation;
      best_lag = lag;
    }
  }
  return best_lag;
}

std::array<double, 2> Decompose(const std::vector<float>& output,
                                const std::vector<float>& near_end,
                                const std::vector<float>& echo, size_t start,
                                size_t lag_samples) {
  double nn = 0.0;
  double ee = 0.0;
  double ne = 0.0;
  for (size_t i = start + lag_samples; i < output.size(); ++i) {
    const float near_sample = near_end[i - lag_samples];
    const float echo_sample = echo[i - lag_samples];
    nn += static_cast<double>(near_sample) * near_sample;
    ee += static_cast<double>(echo_sample) * echo_sample;
    ne += static_cast<double>(near_sample) * echo_sample;
  }
  const double yn = DotAligned(output, near_end, start, lag_samples);
  const double ye = DotAligned(output, echo, start, lag_samples);
  const double determinant = nn * ee - ne * ne;
  return {(yn * ee - ye * ne) / determinant,
          (ye * nn - yn * ne) / determinant};
}

std::string ScenarioName(Scenario scenario) {
  switch (scenario) {
    case Scenario::kResidentOnly:
      return "resident-only";
    case Scenario::kUserOnly:
      return "user-only";
    case Scenario::kDoubleTalk:
      return "double-talk";
  }
}

Result RunScenario(Scenario scenario, int path_delay_ms,
                   int reported_buffer_delay_ms) {
  Signals signals = MakeSignals(scenario, path_delay_ms);
  std::vector<float> output(signals.capture.size());
  webrtc::Environment environment = webrtc::CreateEnvironment();
  webrtc::EchoCanceller3Factory factory;
  std::unique_ptr<webrtc::EchoControl> aec =
      factory.Create(environment, kSampleRate, 1, 1);
  aec->SetAudioBufferDelay(reported_buffer_delay_ms);
  webrtc::AudioBuffer render(kSampleRate, 1, kSampleRate, 1, kSampleRate, 1);
  webrtc::AudioBuffer capture(kSampleRate, 1, kSampleRate, 1, kSampleRate, 1);
  webrtc::StreamConfig stream_config(kSampleRate, 1);

  for (size_t frame_start = 0; frame_start < signals.capture.size();
       frame_start += kFrameSamples) {
    const float* render_channels[] = {signals.render.data() + frame_start};
    render.CopyFrom(render_channels, stream_config);
    render.SplitIntoFrequencyBands();
    aec->AnalyzeRender(&render);

    const float* capture_channels[] = {signals.capture.data() + frame_start};
    capture.CopyFrom(capture_channels, stream_config);
    aec->AnalyzeCapture(&capture);
    capture.SplitIntoFrequencyBands();
    aec->ProcessCapture(&capture, false);
    capture.MergeFrequencyBands();
    float* output_channels[] = {output.data() + frame_start};
    capture.CopyTo(stream_config, output_channels);
  }

  const size_t evaluation_start = kEvaluationStartSeconds * kSampleRate;
  const auto metrics = aec->GetMetrics();
  Result result{
      .scenario = ScenarioName(scenario),
      .path_delay_ms = path_delay_ms,
      .reported_buffer_delay_ms = reported_buffer_delay_ms,
      .input_rms = Rms(signals.capture, evaluation_start),
      .output_rms = Rms(output, evaluation_start),
      .attenuation_db = DbRatio(Rms(output, evaluation_start),
                                Rms(signals.capture, evaluation_start)),
      .near_gain_db = 0.0,
      .near_correlation = 0.0,
      .echo_gain_db = 0.0,
      .erl_db = metrics.echo_return_loss,
      .erle_db = metrics.echo_return_loss_enhancement,
      .estimated_delay_ms = metrics.delay_ms,
      .delay_error_ms = std::abs(metrics.delay_ms - path_delay_ms),
      .alignment_lag_samples = 0,
      .passed = false,
  };

  if (scenario == Scenario::kResidentOnly) {
    result.echo_gain_db = result.attenuation_db;
    result.passed =
        result.attenuation_db <= -15.0 && result.delay_error_ms <= 8;
  } else if (scenario == Scenario::kUserOnly) {
    result.alignment_lag_samples = static_cast<int>(
        FindAlignmentLag(output, signals.near_end, evaluation_start));
    result.near_gain_db = result.attenuation_db;
    result.near_correlation = CorrelationAtLag(
        output, signals.near_end, evaluation_start,
        result.alignment_lag_samples);
    result.passed = result.near_gain_db >= -1.5 &&
                    result.near_gain_db <= 1.5 &&
                    result.near_correlation >= 0.98;
  } else {
    result.alignment_lag_samples = static_cast<int>(
        FindAlignmentLag(output, signals.near_end, evaluation_start));
    const auto components =
        Decompose(output, signals.near_end, signals.echo, evaluation_start,
                  result.alignment_lag_samples);
    result.near_gain_db = DbRatio(std::abs(components[0]), 1.0);
    result.echo_gain_db = DbRatio(std::abs(components[1]), 1.0);
    result.near_correlation = CorrelationAtLag(
        output, signals.near_end, evaluation_start,
        result.alignment_lag_samples);
    result.passed = result.echo_gain_db <= -12.0 &&
                    result.near_gain_db >= -3.0 &&
                    result.near_correlation >= 0.80 &&
                    result.delay_error_ms <= 8;
  }
  return result;
}

void PrintResult(const Result& result) {
  std::cout << std::fixed << std::setprecision(3)
            << "{\"scenario\":\"" << result.scenario
            << "\",\"path_delay_ms\":" << result.path_delay_ms
            << ",\"reported_buffer_delay_ms\":"
            << result.reported_buffer_delay_ms
            << ",\"input_rms\":" << result.input_rms
            << ",\"output_rms\":" << result.output_rms
            << ",\"attenuation_db\":" << result.attenuation_db
            << ",\"near_gain_db\":" << result.near_gain_db
            << ",\"near_correlation\":" << result.near_correlation
            << ",\"echo_gain_db\":" << result.echo_gain_db
            << ",\"erl_db\":" << result.erl_db
            << ",\"erle_db\":" << result.erle_db
            << ",\"estimated_delay_ms\":" << result.estimated_delay_ms
            << ",\"delay_error_ms\":" << result.delay_error_ms
            << ",\"alignment_lag_samples\":"
            << result.alignment_lag_samples
            << ",\"passed\":" << (result.passed ? "true" : "false")
            << "}\n";
}

}  // namespace

int main() {
  const std::array<int, 3> delays_ms = {20, 60, 120};
  bool all_passed = true;

  for (int delay_ms : delays_ms) {
    Result resident = RunScenario(Scenario::kResidentOnly, delay_ms, 0);
    Result double_talk = RunScenario(Scenario::kDoubleTalk, delay_ms, 0);
    PrintResult(resident);
    PrintResult(double_talk);
    all_passed &= resident.passed && double_talk.passed;
  }

  Result user = RunScenario(Scenario::kUserOnly, 0, 0);
  PrintResult(user);
  all_passed &= user.passed;
  std::cout << "{\"status\":\"" << (all_passed ? "PASS" : "FAIL")
            << "\"}\n";
  return all_passed ? 0 : 1;
}
