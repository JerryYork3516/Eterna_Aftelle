#pragma once

#import <AVFAudio/AVFAudio.h>
#import <CoreAudio/CoreAudio.h>

namespace probe_route {

struct Target {
  AudioDeviceID input;
  AudioDeviceID output;
};

struct Format {
  double inputRate;
  double outputRate;
  unsigned inputChannels;
  unsigned outputChannels;

  bool operator==(const Format &other) const {
    return inputRate == other.inputRate && outputRate == other.outputRate &&
        inputChannels == other.inputChannels && outputChannels == other.outputChannels;
  }
};

bool SelectDefaults(Target &target, const char *&error);
bool CheckEngine(AVAudioEngine *engine, const Target &target, Format &format, const char *&error);

}  // namespace probe_route
