#include "ProbeSupport.h"

#import <objc/runtime.h>

#include <algorithm>
#include <cstdio>
#include <csignal>
#include <dlfcn.h>

namespace probe {
static_assert(std::atomic<bool>::is_always_lock_free);
std::atomic<bool> interrupted{false};

namespace {
void Interrupt(int) { interrupted.store(true, std::memory_order_relaxed); }

bool CheckLinkedImage(const char *expected) {
  Method method = class_getInstanceMethod(LKRTCDefaultAudioProcessingModule.class, @selector(config));
  Dl_info info{};
  if (!method || !dladdr(reinterpret_cast<const void *>(method_getImplementation(method)), &info)) return false;
  NSString *expectedPath = [[NSString stringWithUTF8String:expected] stringByResolvingSymlinksInPath];
  NSString *loadedPath = [[NSString stringWithUTF8String:info.dli_fname] stringByResolvingSymlinksInPath];
  return [expectedPath isEqualToString:loadedPath];
}

}  // namespace

bool InitializeProcess(const char *expectedImage) {
  if (!CheckLinkedImage(expectedImage)) {
    std::fputs("FAIL loaded APM image does not match verified framework\n", stderr);
    return false;
  }
  std::setvbuf(stdout, nullptr, _IOLBF, 0);
  if (std::signal(SIGINT, Interrupt) == SIG_ERR || std::signal(SIGTERM, Interrupt) == SIG_ERR) {
    std::fputs("FAIL could not install interrupt handlers\n", stderr);
    return false;
  }
  return true;
}

std::vector<int16_t> ResampleFixture(const std::vector<int16_t> &fixture, size_t rate) {
  const size_t step = fixtureTicksPerSecond / rate;
  const size_t end = fixture.size() * fixtureTicksPerFrame;
  std::vector<int16_t> output;
  output.reserve((end + step - 1) / step);
  for (size_t tick = 0; tick < end; tick += step) {
    const size_t frame = tick / fixtureTicksPerFrame;
    const int fraction = tick % fixtureTicksPerFrame;
    const int current = fixture[frame];
    const int next = fixture[std::min(frame + 1, fixture.size() - 1)];
    const int weight = static_cast<int>(fixtureTicksPerFrame);
    output.push_back((current * (weight - fraction) + next * fraction) / weight);
  }
  return output;
}

void ConfigureApm(LKRTCDefaultAudioProcessingModule *apm, bool echo) {
  LKRTCAudioProcessingConfig *config = [LKRTCAudioProcessingConfig new];
  config.isEchoCancellationEnabled = echo;
  config.isNoiseSuppressionEnabled = NO;
  config.isAutoGainControl1Enabled = NO;
  config.isAutoGainControl2Enabled = NO;
  config.isHighpassFilterEnabled = NO;
  apm.config = config;
}

bool ConfigMatches(LKRTCDefaultAudioProcessingModule *apm,
                   LKRTCPeerConnectionFactory *factory, bool echo) {
  LKRTCAudioProcessingConfig *actual = apm.config;
  LKRTCAudioProcessingState *state = factory.audioProcessingState;
  return actual && state.hasAudioProcessingModule &&
      actual.isEchoCancellationEnabled == echo && state.echoCancellation.isSoftwareActive == echo &&
      !actual.isNoiseSuppressionEnabled && !state.noiseSuppression.isSoftwareActive &&
      !actual.isAutoGainControl1Enabled && !actual.isAutoGainControl2Enabled &&
      !state.autoGainControl.isSoftwareActive &&
      !actual.isHighpassFilterEnabled && !state.highPassFilter.isSoftwareActive;
}

bool PlatformPolicyOff(LKRTCAudioDeviceModule *adm) {
  LKRTCPlatformAudioProcessingState *state = adm.platformAudioProcessingState;
  return !adm.isPlatformVoiceProcessingAllowed && state &&
      !state.isVoiceProcessingEnabledRequested && !state.isVoiceProcessingEnabledActive &&
      !state.echoCancellation.isActive && !state.noiseSuppression.isActive &&
      !state.autoGainControl.isActive;
}

}  // namespace probe
