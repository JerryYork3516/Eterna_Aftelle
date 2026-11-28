#import "DeviceRoute.h"

#import <AudioToolbox/AudioHardwareService.h>
#import <AudioToolbox/AudioToolbox.h>

#include <array>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <sys/sysctl.h>

namespace probe_route {
namespace {

constexpr auto global = kAudioObjectPropertyScopeGlobal;
constexpr auto inputScope = kAudioObjectPropertyScopeInput;
constexpr auto outputScope = kAudioObjectPropertyScopeOutput;
constexpr auto main = kAudioObjectPropertyElementMain;

bool Fail(const char *&error, const char *reason) {
  error = reason;
  return false;
}

template <typename Value>
bool Read(AudioObjectID object, AudioObjectPropertyAddress address, Value &value) {
  UInt32 size = sizeof(value);
  return AudioObjectGetPropertyData(object, &address, 0, nullptr, &size, &value) == noErr &&
      size == sizeof(value);
}

NSString *ReadName(AudioObjectID object) {
  CFStringRef name = nullptr;
  const bool read = Read(object, {kAudioObjectPropertyName, global, main}, name);
  NSString *result = CFBridgingRelease(name);
  return read ? result : nil;
}

bool Contains(NSString *label, NSString *token) {
  return label && [label rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound;
}

bool IsMacMini() {
  char model[64]{};
  size_t size = sizeof(model);
  if (sysctlbyname("hw.model", model, &size, nullptr, 0) != 0 || size == 0 ||
      size > sizeof(model) || model[size - 1] != '\0') {
    return false;
  }
  // Apple's Mac mini model identifiers. Older models use the Macmini prefix.
  return std::strncmp(model, "Macmini", 7) == 0 || std::strcmp(model, "Mac14,3") == 0 ||
      std::strcmp(model, "Mac14,12") == 0 || std::strcmp(model, "Mac16,10") == 0 ||
      std::strcmp(model, "Mac16,11") == 0 || std::strcmp(model, "Mac17,16") == 0 ||
      std::strcmp(model, "Mac18,5") == 0;
}

bool IsSpeakerStream(AudioDeviceID device) {
  constexpr AudioObjectPropertyAddress streams{kAudioDevicePropertyStreams, outputScope, main};
  std::array<AudioStreamID, 32> ids{};
  UInt32 size = sizeof(ids);
  if (AudioObjectGetPropertyData(device, &streams, 0, nullptr, &size, ids.data()) != noErr ||
      size == 0 || size > sizeof(ids) || size % sizeof(ids[0]) != 0) {
    return false;
  }
  for (size_t i = 0; i < size / sizeof(ids[0]); ++i) {
    UInt32 type = 0;
    if (!Read(ids[i], {kAudioStreamPropertyTerminalType, global, main}, type) ||
        type != kAudioStreamTerminalTypeSpeaker) {
      return false;
    }
  }
  return true;
}

bool IsActiveDevice(AudioDeviceID device, UInt32 expectedTransport) {
  UInt32 transport = 0;
  UInt32 alive = 0;
  return device != kAudioObjectUnknown &&
      Read(device, {kAudioDevicePropertyTransportType, global, main}, transport) &&
      transport == expectedTransport &&
      Read(device, {kAudioDevicePropertyDeviceIsAlive, global, main}, alive) && alive == 1;
}

bool IsInternalSpeaker(AudioDeviceID device) {
  if (!IsMacMini() || !IsActiveDevice(device, kAudioDeviceTransportTypeBuiltIn)) return false;
  UInt32 jackConnected = 0;
  if (Read(device, {kAudioDevicePropertyJackIsConnected, outputScope, main}, jackConnected) &&
      jackConnected != 0) {
    return false;
  }
  NSString *name = ReadName(device);
  const bool namedSpeaker = Contains(name, @"Mac mini") &&
      (Contains(name, @"speaker") || Contains(name, @"扬声器") || Contains(name, @"揚聲器"));
  return namedSpeaker || IsSpeakerStream(device);
}

bool MatchesLevel(Float32 value, long expected) {
  return std::isfinite(value) && value >= 0.0f && value <= 1.0f &&
      std::lround(static_cast<double>(value) * 10000.0) == expected;
}

unsigned ChannelCount(AudioDeviceID device, AudioObjectPropertyScope scope) {
  constexpr unsigned maxBuffers = 32;
  constexpr size_t header = offsetof(AudioBufferList, mBuffers);
  alignas(AudioBufferList) std::array<std::byte, header + maxBuffers * sizeof(AudioBuffer)> bytes{};
  AudioObjectPropertyAddress address{kAudioDevicePropertyStreamConfiguration, scope, main};
  UInt32 size = bytes.size();
  if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, bytes.data()) != noErr ||
      size < header || size > bytes.size()) {
    return 0;
  }
  UInt32 buffers = 0;
  std::memcpy(&buffers, bytes.data() + offsetof(AudioBufferList, mNumberBuffers), sizeof(buffers));
  if (buffers > (size - header) / sizeof(AudioBuffer)) return 0;
  unsigned channels = 0;
  for (UInt32 i = 0; i < buffers; ++i) {
    AudioBuffer buffer;
    std::memcpy(&buffer, bytes.data() + header + i * sizeof(buffer), sizeof(buffer));
    if (buffer.mNumberChannels > 64 - channels) return 0;
    channels += buffer.mNumberChannels;
  }
  return channels;
}

bool CheckLevel(AudioDeviceID device, AudioObjectPropertyScope scope, long expected) {
  Float32 value = 0;
  const AudioObjectPropertyAddress volume{kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope, main};
  if (AudioObjectHasProperty(device, &volume)) {
    return Read(device, volume, value) && MatchesLevel(value, expected);
  }
  // Devices can expose this selector exclusively via Audio Hardware Services.
  UInt32 size = sizeof(value);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  const OSStatus virtualResult = AudioHardwareServiceGetPropertyData(device, &volume, 0, nullptr, &size, &value);
#pragma clang diagnostic pop
  if (virtualResult == noErr) return size == sizeof(value) && MatchesLevel(value, expected);

  AudioObjectPropertyAddress scalar{kAudioDevicePropertyVolumeScalar, scope, main};
  if (AudioObjectHasProperty(device, &scalar)) {
    return Read(device, scalar, value) && MatchesLevel(value, expected);
  }

  const unsigned channels = ChannelCount(device, scope);
  if (channels == 0) return false;
  for (unsigned channel = 1; channel <= channels; ++channel) {
    scalar.mElement = channel;
    if (!Read(device, scalar, value) || !MatchesLevel(value, expected)) return false;
  }
  return true;
}

bool CheckUnmuted(AudioDeviceID device, AudioObjectPropertyScope scope) {
  AudioObjectPropertyAddress mute{kAudioDevicePropertyMute, scope, main};
  const unsigned channels = ChannelCount(device, scope);
  for (unsigned channel = 0; channel <= channels; ++channel) {
    mute.mElement = channel;
    UInt32 value = 0;
    if (AudioObjectHasProperty(device, &mute) && (!Read(device, mute, value) || value != 0)) {
      return false;
    }
  }
  return true;
}

bool ReadDefault(AudioObjectPropertySelector selector, AudioDeviceID &device) {
  return Read(kAudioObjectSystemObject, {selector, global, main}, device) &&
      device != kAudioObjectUnknown;
}

bool ReadUnitDevice(AudioUnit unit, AudioUnitElement element, AudioDeviceID &device) {
  UInt32 size = sizeof(device);
  return unit && AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                      kAudioUnitScope_Global, element, &device, &size) == noErr &&
      size == sizeof(device) && device != kAudioObjectUnknown;
}

}  // namespace

bool SelectDefaults(Target &target, const char *&error) {
  error = nullptr;
  Target selected{kAudioObjectUnknown, kAudioObjectUnknown};
  if (!ReadDefault(kAudioHardwarePropertyDefaultInputDevice, selected.input) ||
      !IsActiveDevice(selected.input, kAudioDeviceTransportTypeUSB) ||
      !Contains(ReadName(selected.input), @"TinyUSB")) {
    return Fail(error, "default input is not a live TinyUSB device");
  }
  if (!ReadDefault(kAudioHardwarePropertyDefaultOutputDevice, selected.output) ||
      !IsInternalSpeaker(selected.output)) {
    return Fail(error, "default output is not the Mac mini internal speaker");
  }
  if (!CheckLevel(selected.input, inputScope, 6049)) {
    return Fail(error, "TinyUSB input level is unreadable or differs from 60.49%");
  }
  if (!CheckLevel(selected.output, outputScope, 5986)) {
    return Fail(error, "Mac mini speaker level is unreadable or differs from 59.86%");
  }
  if (!CheckUnmuted(selected.input, inputScope) || !CheckUnmuted(selected.output, outputScope)) {
    return Fail(error, "device is muted or has an unreadable mute control");
  }
  target = selected;
  return true;
}

bool CheckEngine(AVAudioEngine *engine, const Target &target, Format &format, const char *&error) {
  error = nullptr;
  if (!engine || engine.isInManualRenderingMode) return Fail(error, "expected a device audio engine");

  AudioDeviceID input = kAudioObjectUnknown;
  AudioDeviceID output = kAudioObjectUnknown;
  AVAudioInputNode *inNode = engine.inputNode;
  AVAudioOutputNode *outNode = engine.outputNode;
  if (!ReadUnitDevice(inNode.audioUnit, 1, input) || input != target.input) {
    return Fail(error, "actual audio unit input does not match TinyUSB");
  }
  if (!ReadUnitDevice(outNode.audioUnit, 0, output) || output != target.output) {
    return Fail(error, "actual audio unit output does not match the Mac mini speaker");
  }
  if (inNode.isVoiceProcessingEnabled || outNode.isVoiceProcessingEnabled) {
    return Fail(error, "Apple voice processing is enabled in the device audio graph");
  }

  Target current{};
  if (!SelectDefaults(current, error)) return false;
  if (current.input != input || current.output != output) {
    return Fail(error, "system default audio routes changed");
  }
  AVAudioFormat *inputFormat = [inNode inputFormatForBus:0];
  AVAudioFormat *outputFormat = [outNode outputFormatForBus:0];
  if (!std::isfinite(inputFormat.sampleRate) || inputFormat.sampleRate <= 0 ||
      !std::isfinite(outputFormat.sampleRate) || outputFormat.sampleRate <= 0 ||
      inputFormat.channelCount == 0 || outputFormat.channelCount == 0) {
    return Fail(error, "actual hardware format is unavailable");
  }
  format = {inputFormat.sampleRate, outputFormat.sampleRate,
            inputFormat.channelCount, outputFormat.channelCount};
  return true;
}

}  // namespace probe_route
