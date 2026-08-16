#include <array>
#include <cmath>
#include <iostream>

#include "AftelleAECBridge.h"

namespace {

constexpr size_t kFrameSamples = 480;
constexpr size_t kLinearOutputFrameSamples = 160;

bool Expect(AftelleAECBridgeError actual, AftelleAECBridgeError expected,
            const char* operation) {
  if (actual == expected) {
    return true;
  }
  std::cerr << operation << ": expected "
            << AftelleAECBridgeErrorMessage(expected) << ", got "
            << AftelleAECBridgeErrorMessage(actual) << '\n';
  return false;
}

bool RunLifecycleAndErrorChecks() {
  bool passed = true;
  std::array<float, kFrameSamples> input{};
  std::array<float, kFrameSamples> output{};
  std::array<float, kLinearOutputFrameSamples> linear_output{};
  AftelleAECBridgeStats stats{};

  passed &= Expect(AftelleAECBridgeCreate(nullptr),
                   AFTELLE_AEC_BRIDGE_NULL_ARGUMENT, "create null output");
  AftelleAECBridgeDestroy(nullptr);

  AftelleAECBridge* bridge = nullptr;
  passed &=
      Expect(AftelleAECBridgeCreate(&bridge), AFTELLE_AEC_BRIDGE_OK, "create");
  passed &=
      Expect(AftelleAECBridgeProcessRender(bridge, input.data(), kFrameSamples),
             AFTELLE_AEC_BRIDGE_INVALID_STATE, "render before configure");
  passed &=
      Expect(AftelleAECBridgeProcessCapture(bridge, input.data(), output.data(),
                                            kFrameSamples),
             AFTELLE_AEC_BRIDGE_INVALID_STATE, "capture before configure");
  passed &= Expect(AftelleAECBridgeProcessCaptureWithLinearOutput(
                       bridge, input.data(), output.data(), kFrameSamples,
                       linear_output.data(), kLinearOutputFrameSamples),
                   AFTELLE_AEC_BRIDGE_INVALID_STATE,
                   "linear capture before configure");
  passed &= Expect(AftelleAECBridgeSetDelayMs(bridge, 0),
                   AFTELLE_AEC_BRIDGE_INVALID_STATE, "delay before configure");
  passed &= Expect(AftelleAECBridgeReset(bridge),
                   AFTELLE_AEC_BRIDGE_INVALID_STATE, "reset before configure");
  passed &= Expect(AftelleAECBridgeGetStats(bridge, &stats),
                   AFTELLE_AEC_BRIDGE_INVALID_STATE, "stats before configure");

  passed &= Expect(AftelleAECBridgeConfigure(nullptr, 48000, 1, 480),
                   AFTELLE_AEC_BRIDGE_NULL_ARGUMENT, "configure null handle");
  passed &=
      Expect(AftelleAECBridgeConfigure(bridge, 24000, 1, 480),
             AFTELLE_AEC_BRIDGE_UNSUPPORTED_FORMAT, "unsupported sample rate");
  passed &= Expect(AftelleAECBridgeConfigure(bridge, 48000, 2, 480),
                   AFTELLE_AEC_BRIDGE_UNSUPPORTED_FORMAT,
                   "unsupported channel count");
  passed &= Expect(AftelleAECBridgeConfigure(bridge, 48000, 1, 240),
                   AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE,
                   "invalid configured frame size");
  passed &= Expect(AftelleAECBridgeConfigure(bridge, 48000, 1, 480),
                   AFTELLE_AEC_BRIDGE_OK, "configure");

  passed &= Expect(AftelleAECBridgeGetStats(bridge, &stats),
                   AFTELLE_AEC_BRIDGE_OK, "stats");
  passed &= stats.enabled == 1 && stats.active == 1;
  passed &= Expect(AftelleAECBridgeProcessRender(nullptr, input.data(), 480),
                   AFTELLE_AEC_BRIDGE_NULL_ARGUMENT, "render null handle");
  passed &= Expect(AftelleAECBridgeProcessRender(bridge, nullptr, 480),
                   AFTELLE_AEC_BRIDGE_NULL_ARGUMENT, "render null input");
  passed &=
      Expect(AftelleAECBridgeProcessRender(bridge, input.data(), 479),
             AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE, "render invalid frame");
  passed &= Expect(
      AftelleAECBridgeProcessCapture(bridge, nullptr, output.data(), 480),
      AFTELLE_AEC_BRIDGE_NULL_ARGUMENT, "capture null input");
  passed &=
      Expect(AftelleAECBridgeProcessCapture(bridge, input.data(), nullptr, 480),
             AFTELLE_AEC_BRIDGE_NULL_ARGUMENT, "capture null output");
  passed &= Expect(
      AftelleAECBridgeProcessCapture(bridge, input.data(), output.data(), 481),
      AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE, "capture invalid frame");
  passed &= Expect(AftelleAECBridgeProcessCaptureWithLinearOutput(
                       bridge, input.data(), output.data(), kFrameSamples,
                       nullptr, kLinearOutputFrameSamples),
                   AFTELLE_AEC_BRIDGE_NULL_ARGUMENT,
                   "linear capture null output");
  passed &= Expect(AftelleAECBridgeProcessCaptureWithLinearOutput(
                       bridge, input.data(), output.data(), kFrameSamples,
                       linear_output.data(), kLinearOutputFrameSamples - 1),
                   AFTELLE_AEC_BRIDGE_INVALID_FRAME_SIZE,
                   "linear capture invalid frame");
  passed &= Expect(AftelleAECBridgeSetDelayMs(bridge, -1),
                   AFTELLE_AEC_BRIDGE_INVALID_DELAY, "negative delay");
  passed &= Expect(AftelleAECBridgeSetDelayMs(bridge, 501),
                   AFTELLE_AEC_BRIDGE_INVALID_DELAY, "excessive delay");
  passed &= Expect(AftelleAECBridgeSetDelayMs(bridge, 40),
                   AFTELLE_AEC_BRIDGE_OK, "valid delay");

  for (int frame = 0; frame < 100; ++frame) {
    passed &= Expect(
        AftelleAECBridgeProcessRender(bridge, input.data(), kFrameSamples),
        AFTELLE_AEC_BRIDGE_OK, "render frame");
    passed &= Expect(AftelleAECBridgeProcessCaptureWithLinearOutput(
                         bridge, input.data(), output.data(), kFrameSamples,
                         linear_output.data(), kLinearOutputFrameSamples),
                     AFTELLE_AEC_BRIDGE_OK, "linear capture frame");
  }
  for (float sample : linear_output) {
    passed &= std::isfinite(sample);
  }

  passed &= Expect(AftelleAECBridgeProcessCapture(bridge, input.data(),
                                                  input.data(), kFrameSamples),
                   AFTELLE_AEC_BRIDGE_OK, "in-place capture frame");
  passed &=
      Expect(AftelleAECBridgeReset(bridge), AFTELLE_AEC_BRIDGE_OK, "reset");
  passed &= Expect(AftelleAECBridgeGetStats(bridge, &stats),
                   AFTELLE_AEC_BRIDGE_OK, "stats after reset");
  passed &= stats.enabled == 1 && stats.active == 1;
  AftelleAECBridgeDestroy(bridge);
  return passed;
}

bool RunRepeatedLifecycleChecks() {
  for (int iteration = 0; iteration < 100; ++iteration) {
    AftelleAECBridge* bridge = nullptr;
    if (AftelleAECBridgeCreate(&bridge) != AFTELLE_AEC_BRIDGE_OK ||
        AftelleAECBridgeConfigure(bridge, 48000, 1, 480) !=
            AFTELLE_AEC_BRIDGE_OK ||
        AftelleAECBridgeReset(bridge) != AFTELLE_AEC_BRIDGE_OK) {
      AftelleAECBridgeDestroy(bridge);
      return false;
    }
    AftelleAECBridgeDestroy(bridge);
  }
  return true;
}

}  // namespace

int main() {
  const bool passed =
      RunLifecycleAndErrorChecks() && RunRepeatedLifecycleChecks();
  std::cout << "{\"bridge_lifecycle_and_errors\":\""
            << (passed ? "PASS" : "FAIL") << "\"}\n";
  return passed ? 0 : 1;
}
