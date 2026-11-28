#pragma once

#import <LiveKitWebRTC/LiveKitWebRTC.h>

#include <atomic>
#include <vector>

namespace probe {
extern std::atomic<bool> interrupted;
inline constexpr size_t fixtureTicksPerSecond = 96000;
inline constexpr size_t fixtureTicksPerFrame = 4;

bool InitializeProcess(const char *expectedImage);

std::vector<int16_t> ResampleFixture(const std::vector<int16_t> &fixture, size_t rate);
void ConfigureApm(LKRTCDefaultAudioProcessingModule *apm, bool echo);
bool ConfigMatches(LKRTCDefaultAudioProcessingModule *apm, LKRTCPeerConnectionFactory *factory, bool echo);
bool PlatformPolicyOff(LKRTCAudioDeviceModule *adm);
}  // namespace probe
