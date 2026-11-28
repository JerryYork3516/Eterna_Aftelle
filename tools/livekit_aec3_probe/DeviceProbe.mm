#import <AVFoundation/AVFoundation.h>

#include "DeviceRoute.h"
#include "ProbeSupport.h"
#include "WaveFile.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <thread>
#include <unistd.h>

namespace {
using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;
constexpr int scoreSeconds = 15;
constexpr size_t maxCaptureRate = 48000;
constexpr std::array<size_t, 4> renderRates{8000, 16000, 32000, 48000};
constexpr NSInteger rejectGraph = -7702;
constexpr std::array<AudioObjectPropertyAddress, 2> defaultRouteProperties{{
    {kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
    {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
}};

class CallbackGate {
 public:
  bool Arm() {
    uint32_t current = ready;
    return state.compare_exchange_strong(current, 0);
  }
  void Close() { state.fetch_or(closed); }
  bool Enter() {
    uint32_t current = state.load();
    while (current < closed) {
      if (state.compare_exchange_weak(current, current + 1)) return true;
    }
    return false;
  }
  void Leave() { state.fetch_sub(1); }
  bool Drained() const { return (state.load() & (closed - 1)) == 0; }

 private:
  static constexpr uint32_t closed = 1u << 30;
  static constexpr uint32_t ready = 1u << 31;
  std::atomic<uint32_t> state{ready};
};

class CallbackLease {
 public:
  explicit CallbackLease(CallbackGate &gate) : gate(gate), admitted(gate.Enter()) {}
  ~CallbackLease() { if (admitted) gate.Leave(); }
  CallbackLease(const CallbackLease &) = delete;
  explicit operator bool() const { return admitted; }

 private:
  CallbackGate &gate;
  const bool admitted;
};

struct DevicePcm {
  explicit DevicePcm(const std::vector<int16_t> &resident) {
    for (size_t i = 0; i < renderRates.size(); ++i) {
      render[i] = probe::ResampleFixture(resident, renderRates[i]);
    }
  }

  void Fail(const char *error) {
    gate.Close();
    const char *expected = nullptr;
    fault.compare_exchange_strong(expected, error);
  }

  CallbackGate gate;
  std::array<std::vector<int16_t>, renderRates.size()> render;
  std::vector<int16_t> capture = std::vector<int16_t>(scoreSeconds * maxCaptureRate);
  std::atomic<const char *> fault{nullptr};
  std::atomic<bool> play{false};
  std::atomic<bool> endOfFixture{false};
  std::atomic<size_t> captureRate{0};
  std::atomic<size_t> captured{0};
  size_t renderRate = 0;
  size_t rendered = 0;
  size_t renderBlocks = 0;
  size_t captureClipped = 0;
  size_t tapFrames = 0;
  size_t tapNonzeroFrames = 0;
  double tapRate = 0;
  unsigned tapChannels = 0;
  AVAudioCommonFormat tapSampleFormat = AVAudioOtherFormat;
  bool tapInterleaved = false;
  uint64_t firstTapHostTime = 0;
  uint64_t lastTapHostTime = 0;
  size_t firstTapOffset = 0;
  size_t lastTapOffset = 0;
};

void FeedRender(DevicePcm &pcm, float *samples, size_t frames, size_t rate) {
  std::fill_n(samples, frames, 0.0f);
  CallbackLease lease(pcm.gate);
  if (!lease || !pcm.play) return;

  const auto found = std::find(renderRates.begin(), renderRates.end(), rate);
  if (found == renderRates.end() || (pcm.renderRate && pcm.renderRate != rate)) {
    return pcm.Fail("render-pre rate changed or is unsupported");
  }
  pcm.renderRate = rate;
  const auto &render = pcm.render[found - renderRates.begin()];
  const size_t framesToCopy = std::min(frames, render.size() - pcm.rendered);
  if (!framesToCopy) return;
  ++pcm.renderBlocks;
  std::copy_n(render.data() + pcm.rendered, framesToCopy, samples);
  pcm.rendered += framesToCopy;
  if (pcm.rendered == render.size()) pcm.endOfFixture = true;
}

void SaveCapture(DevicePcm &pcm, const float *samples, size_t frames, size_t rate) {
  CallbackLease lease(pcm.gate);
  if (!lease) return;

  if (!rate || rate > maxCaptureRate || (pcm.captureRate && pcm.captureRate != rate)) {
    return pcm.Fail("capture-post rate changed or is unsupported");
  }
  pcm.captureRate = rate;
  const size_t offset = pcm.captured.load(std::memory_order_relaxed);
  const size_t framesToCopy = std::min(frames, scoreSeconds * rate - offset);
  for (size_t frame = 0; frame < framesToCopy; ++frame) {
    const float sample = samples[frame];
    if (!std::isfinite(sample)) return pcm.Fail("capture-post contains nonfinite PCM");
    const float bounded = std::clamp(sample, -32768.0f, 32767.0f);
    if (bounded != sample) ++pcm.captureClipped;
    pcm.capture[offset + frame] = static_cast<int16_t>(std::lround(bounded));
  }
  pcm.captured.store(offset + framesToCopy, std::memory_order_release);
}

template <typename Sample>
void ObserveSamples(DevicePcm &pcm, const AudioBufferList *list, size_t frames,
                    unsigned channels, bool interleaved, uint64_t hostTime, Sample threshold) {
  const size_t buffers = interleaved ? 1 : channels;
  const size_t stride = interleaved ? channels : 1;
  if (list->mNumberBuffers != buffers) return pcm.Fail("mixer tap channel layout changed");
  for (size_t index = 0; index < buffers; ++index) {
    const auto &buffer = list->mBuffers[index];
    if (!buffer.mData || buffer.mNumberChannels != stride ||
        buffer.mDataByteSize < frames * stride * sizeof(Sample)) {
      return pcm.Fail("mixer tap buffer too short");
    }
  }

  for (size_t frame = 0; frame < frames; ++frame) {
    bool nonzero = false;
    for (size_t buffer = 0; buffer < buffers; ++buffer) {
      const auto *samples = static_cast<const Sample *>(list->mBuffers[buffer].mData);
      for (size_t channel = 0; channel < stride; ++channel) {
        const Sample sample = samples[frame * stride + channel];
        if (!std::isfinite(sample)) return pcm.Fail("mixer tap contains nonfinite PCM");
        nonzero |= sample >= threshold || sample <= -threshold;
      }
    }
    if (!nonzero) continue;
    if (!pcm.play) return pcm.Fail("nonzero mixer output before scheduled resident playback");
    if (!hostTime) return pcm.Fail("nonzero mixer tap has no host time");
    if (!pcm.tapNonzeroFrames) {
      pcm.firstTapHostTime = hostTime;
      pcm.firstTapOffset = frame;
    }
    pcm.lastTapHostTime = hostTime;
    pcm.lastTapOffset = frame;
    ++pcm.tapNonzeroFrames;
  }
  pcm.tapFrames += frames;
}

void ObserveTap(DevicePcm &pcm, AVAudioPCMBuffer *buffer, AVAudioTime *time) {
  CallbackLease lease(pcm.gate);
  if (!lease) return;

  AVAudioFormat *format = buffer.format;
  const size_t frames = buffer.frameLength;
  const unsigned channels = format.channelCount;
  if (!frames || frames > 65536 || !channels || channels > 8 ||
      !std::isfinite(format.sampleRate) || format.sampleRate <= 0 ||
      (pcm.tapRate && (pcm.tapRate != format.sampleRate || pcm.tapChannels != channels ||
                       pcm.tapSampleFormat != format.commonFormat || pcm.tapInterleaved != format.isInterleaved))) {
    return pcm.Fail("mixer tap format changed or is unsupported");
  }
  pcm.tapRate = format.sampleRate;
  pcm.tapChannels = channels;
  pcm.tapSampleFormat = format.commonFormat;
  pcm.tapInterleaved = format.isInterleaved;
  const auto *list = buffer.audioBufferList;
  const auto hostTime = time.isHostTimeValid ? time.hostTime : 0;
  switch (format.commonFormat) {
    case AVAudioPCMFormatFloat32:
      return ObserveSamples(pcm, list, frames, channels, format.isInterleaved, hostTime, 1.0f / 32768.0f);
    case AVAudioPCMFormatInt16:
      return ObserveSamples(pcm, list, frames, channels, format.isInterleaved, hostTime, int16_t{1});
    case AVAudioPCMFormatInt32:
      return ObserveSamples(pcm, list, frames, channels, format.isInterleaved, hostTime, int32_t{65536});
    default:
      return pcm.Fail("unsupported mixer tap sample representation");
  }
}

bool StandardMicMode() {
  return AVCaptureDevice.preferredMicrophoneMode == AVCaptureMicrophoneModeStandard &&
      AVCaptureDevice.activeMicrophoneMode == AVCaptureMicrophoneModeStandard;
}
}  // namespace

@interface DeviceHook : NSObject <LKRTCAudioCustomProcessingDelegate>
- (instancetype)initWithPcm:(std::shared_ptr<DevicePcm>)pcm output:(BOOL)output;
@end

@implementation DeviceHook {
  std::shared_ptr<DevicePcm> _pcm;
  BOOL _output;
  size_t _rate;
  size_t _channels;
}

- (instancetype)initWithPcm:(std::shared_ptr<DevicePcm>)pcm output:(BOOL)output {
  self = [super init];
  if (self) {
    _pcm = std::move(pcm);
    _output = output;
  }
  return self;
}

- (void)audioProcessingInitializeWithSampleRate:(size_t)rate channels:(size_t)channels {
  _rate = rate;
  _channels = channels;
}

- (void)audioProcessingProcess:(LKRTCAudioBuffer *)buffer {
  if (_channels != 1 || buffer.channels != 1 || !_rate || _rate % 100 ||
      buffer.frames != _rate / 100 || buffer.frames > maxCaptureRate / 100) {
    if (_output && buffer.frames <= maxCaptureRate / 100) {
      for (size_t channel = 0; channel < std::min<size_t>(buffer.channels, 8); ++channel) {
        std::fill_n([buffer rawBufferForChannel:channel], buffer.frames, 0.0f);
      }
    }
    return _pcm->Fail("expected mono 10 ms blocks from the native APM");
  }
  float *samples = [buffer rawBufferForChannel:0];
  if (_output) FeedRender(*_pcm, samples, buffer.frames, _rate);
  else SaveCapture(*_pcm, samples, buffer.frames, _rate);
}

- (void)audioProcessingRelease {}
@end

@interface DeviceObserver : NSObject <LKRTCAudioDeviceModuleDelegate>
- (instancetype)initWithPcm:(std::shared_ptr<DevicePcm>)pcm target:(probe_route::Target)target;
- (BOOL)validateLive;
- (void)printHardwareWitness;
- (void)beginStop;
- (BOOL)finishStop:(BOOL)started;
@end

@implementation DeviceObserver {
  std::shared_ptr<DevicePcm> _pcm;
  probe_route::Target _target;
  probe_route::Format _format;
  AVAudioEngine *_engine;
  AVAudioNode *_mixer;
  id _changeObserver;
  dispatch_queue_t _routeQueue;
  AudioObjectPropertyListenerBlock _routeListener;
  size_t _routeListeners;
  std::atomic<bool> _attempted;
  std::atomic<bool> _stopping;
  unsigned _created;
  unsigned _stopped;
  unsigned _released;
  BOOL _tapped;
}

- (instancetype)initWithPcm:(std::shared_ptr<DevicePcm>)pcm target:(probe_route::Target)target {
  self = [super init];
  if (self) {
    _pcm = std::move(pcm);
    _target = target;
    std::atomic_init(&_attempted, false);
    std::atomic_init(&_stopping, false);
  }
  return self;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm didCreateEngine:(AVAudioEngine *)engine {
  if (!engine || _created || engine.isInManualRenderingMode || _pcm->fault) {
    _pcm->Fail("device graph recreation or unexpected graph mode");
    return rejectGraph;
  }
  ++_created;
  _engine = engine;
  return 0;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
              willEnableEngine:(AVAudioEngine *)engine isPlayoutEnabled:(BOOL)playout
            isRecordingEnabled:(BOOL)recording isVoiceProcessingEnabled:(BOOL)voiceProcessing {
  if (engine == _engine && playout && recording && !voiceProcessing && !_pcm->fault &&
      !probe::interrupted) return 0;
  _pcm->Fail("ADM did not resolve a duplex graph with Apple VP off");
  return rejectGraph;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
                        engine:(AVAudioEngine *)engine configureInputFromSource:(AVAudioNode *)source
                 toDestination:(AVAudioNode *)destination withFormat:(AVAudioFormat *)format
                       context:(NSDictionary *)context {
  if (engine == _engine && [source isKindOfClass:[AVAudioInputNode class]] &&
      !((AVAudioInputNode *)source).isVoiceProcessingEnabled && destination &&
      format.channelCount == 1 && format.sampleRate > 0) return 0;
  _pcm->Fail("unexpected or VP-enabled ADM capture graph");
  return rejectGraph;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
                        engine:(AVAudioEngine *)engine configureOutputFromSource:(AVAudioNode *)source
                 toDestination:(AVAudioNode *)destination withFormat:(AVAudioFormat *)format
                       context:(NSDictionary *)context {
  if (engine == _engine && source == engine.mainMixerNode && destination == engine.outputNode &&
      format.channelCount == 1 && format.sampleRate > 0 && !_mixer) {
    _mixer = source;
    return 0;
  }
  _pcm->Fail("unexpected ADM output path");
  return rejectGraph;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
               willStartEngine:(AVAudioEngine *)engine isPlayoutEnabled:(BOOL)playout
            isRecordingEnabled:(BOOL)recording {
  if (_attempted.exchange(true) || engine != _engine || !_mixer || !playout || !recording ||
      _pcm->fault || probe::interrupted) {
    _pcm->Fail("ADM restart or missing duplex path");
    return rejectGraph;
  }
  const char *error = nullptr;
  if (!probe_route::CheckEngine(engine, _target, _format, error)) {
    _pcm->Fail(error);
    return rejectGraph;
  }
  auto pcm = _pcm;
  @try {
    // The SDK has already connected this bus to its output node.
    const auto tapFrames = static_cast<AVAudioFrameCount>(std::ceil(_format.outputRate * 0.12));
    [_mixer installTapOnBus:0 bufferSize:tapFrames format:nil
                    block:^(AVAudioPCMBuffer *buffer, AVAudioTime *time) { ObserveTap(*pcm, buffer, time); }];
    _tapped = YES;
  } @catch (NSException *exception) {
    _pcm->Fail("could not install passive ADM mixer tap");
    return rejectGraph;
  }
  _changeObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:AVAudioEngineConfigurationChangeNotification object:engine queue:nil
      usingBlock:^(NSNotification *notification) { pcm->Fail("AVAudioEngine configuration changed"); }];
  if (![self watchDefaults:pcm] || !probe_route::CheckEngine(engine, _target, _format, error) ||
      _pcm->fault || probe::interrupted) {
    _pcm->Fail(error ?: "cannot watch default Core Audio routes");
    return rejectGraph;
  }
  return 0;
}

- (BOOL)watchDefaults:(const std::shared_ptr<DevicePcm> &)pcm {
  _routeQueue = dispatch_queue_create("com.eterna.aftelle.probe-route", DISPATCH_QUEUE_SERIAL);
  auto owner = pcm;
  _routeListener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
    owner->Fail("system default audio route notification");
  };
  for (const auto &property : defaultRouteProperties) {
    if (AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject,
                                           &property, _routeQueue, _routeListener)) return NO;
    ++_routeListeners;
  }
  return YES;
}

- (void)printHardwareWitness {
  std::printf("input=TinyUSB device_id=%u rate=%.0f channels=%u "
              "output=Mac_mini_speaker device_id=%u rate=%.0f channels=%u "
              "platform_vp=off mic_mode=Standard\n",
              _target.input, _format.inputRate, _format.inputChannels,
              _target.output, _format.outputRate, _format.outputChannels);
}

- (BOOL)validateLive {
  const char *error = nullptr;
  probe_route::Format actual;
  if (_pcm->fault) return NO;
  if (!_engine.isRunning || !probe_route::CheckEngine(_engine, _target, actual, error) ||
      !(actual == _format) || !StandardMicMode()) {
    _pcm->Fail(error ?: "running graph, hardware format or Standard Mic Mode changed");
    return NO;
  }
  return YES;
}

- (void)releaseObservation {
  while (_routeListeners) {
    const auto &property = defaultRouteProperties[--_routeListeners];
    if (AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject,
                                              &property, _routeQueue, _routeListener)) {
      _pcm->Fail("could not remove default route listener");
    }
  }
  if (_routeQueue) dispatch_sync(_routeQueue, ^{});
  _routeListener = nil;
  _routeQueue = nil;
  if (_changeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_changeObserver];
    _changeObserver = nil;
  }
  if (_tapped) {
    @try {
      [_mixer removeTapOnBus:0];
      _tapped = NO;
    } @catch (NSException *exception) {
      _pcm->Fail("could not remove passive mixer tap");
      return;
    }
  }
  _mixer = nil;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
                 didStopEngine:(AVAudioEngine *)engine isPlayoutEnabled:(BOOL)playout
            isRecordingEnabled:(BOOL)recording {
  ++_stopped;
  if (!_stopping || engine.isRunning) _pcm->Fail("device graph stopped unexpectedly");
  [self releaseObservation];
  return 0;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
              didDisableEngine:(AVAudioEngine *)engine isPlayoutEnabled:(BOOL)playout
            isRecordingEnabled:(BOOL)recording {
  if (_attempted && !_stopping) _pcm->Fail("ADM disabled the running graph");
  [self releaseObservation];
  return 0;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm willReleaseEngine:(AVAudioEngine *)engine {
  ++_released;
  if (engine.isRunning) _pcm->Fail("released graph reports it is running");
  [self releaseObservation];
  return 0;
}

- (void)audioDeviceModuleDidUpdateDevices:(LKRTCAudioDeviceModule *)adm {
  if (_attempted && !_stopping) _pcm->Fail("SDK audio device list changed during the trial");
}

- (void)audioDeviceModule:(LKRTCAudioDeviceModule *)adm didReceiveSpeechActivityEvent:(LKRTCSpeechActivityEvent)event {}

- (void)beginStop {
  _stopping = true;
  _pcm->gate.Close();
}

- (BOOL)finishStop:(BOOL)started {
  const bool clear = !_engine.isRunning && !_tapped && !_changeObserver && !_routeListeners &&
                     _created == _released && (!started || _stopped == 1);
  if (!_engine.isRunning) {
    [self releaseObservation];
    _engine = nil;
  }
  return clear;
}
@end

namespace {
bool FailMessage(const char *message) {
  std::fprintf(stderr, "FAIL %s\n", message);
  return false;
}

bool HasDeviceAuthorization(int argc, const char *argv[]) {
  return argc == 5 && std::strcmp(argv[0], "--device") == 0 &&
      std::strcmp(argv[1], "--authorize-device") == 0 &&
      std::strcmp(argv[2], "--standard-mic-mode") == 0 && argv[3][0] == '/' && argv[4][0] == '/';
}

bool WaitForMicAuthorization() {
  const auto status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
  if (status == AVAuthorizationStatusAuthorized) return true;
  if (status != AVAuthorizationStatusNotDetermined) {
    return FailMessage("macOS denied microphone access for this launch context");
  }

  std::puts("请在 macOS 授权面板确认麦克风权限。等待期间不会打开设备流。");
  auto response = std::make_shared<std::atomic<int>>(0);
  [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
    response->store(granted ? 1 : -1);
  }];
  const auto deadline = Clock::now() + 60s;
  while (!probe::interrupted && !response->load() && Clock::now() < deadline) {
    std::this_thread::sleep_for(50ms);
  }
  return (!probe::interrupted && response->load() == 1 &&
          [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized) ||
      FailMessage("microphone authorization was not granted or timed out");
}

bool WaitForDrain(DevicePcm &pcm) {
  const auto deadline = Clock::now() + 1s;
  while (!pcm.gate.Drained() && Clock::now() < deadline) std::this_thread::sleep_for(2ms);
  return pcm.gate.Drained();
}

template <typename Start, typename Score, typename Stop>
bool RunTrial(DevicePcm &pcm, Start start, Score score, Stop stop) {
  if (probe::interrupted) return false;
  const bool started = start();
  const bool accepted = started && !pcm.fault && !probe::interrupted && score();
  pcm.gate.Close();
  const bool stopped = stop(started);
  const bool drained = WaitForDrain(pcm);
  std::printf("adm_stop_release=%d admitted_probe_callbacks_drained=%d\n", stopped, drained);
  return accepted && stopped && drained && !pcm.fault && !probe::interrupted;
}

bool RunScore(DevicePcm &pcm, DeviceObserver *observer, LKRTCAudioDeviceModule *adm,
              LKRTCDefaultAudioProcessingModule *apm, LKRTCPeerConnectionFactory *factory) {
  if (!adm.isRecording || adm.isManualRenderingMode || !probe::PlatformPolicyOff(adm) ||
      !probe::ConfigMatches(apm, factory, true) || ![observer validateLive]) {
    return FailMessage("active device route, mode or native APM configuration did not qualify");
  }

  [observer printHardwareWitness];
  const auto start = Clock::now();
  auto nextRouteCheck = start + 100ms;
  if (!pcm.gate.Arm()) return false;
  std::puts("开始。现在请独自持续朗读。");
  bool recovering = false;
  bool quiet = false;
  while (!pcm.fault && !probe::interrupted) {
    const auto now = Clock::now();
    const auto elapsed = now - start;
    if (now >= nextRouteCheck) {
      if (![observer validateLive]) return false;
      nextRouteCheck = now + 100ms;
    }
    if (elapsed >= 3s && !pcm.play.exchange(true)) {
      std::puts("居民开始播放。请继续朗读，保持双讲。");
    }
    if (pcm.endOfFixture && !recovering && !quiet) {
      recovering = true;
      std::puts("居民播放即将结束。请继续朗读，观察声音恢复。");
    }
    if (elapsed >= 11s && !quiet) {
      if (!pcm.endOfFixture) return FailMessage("resident render-pre did not finish before quiet phase");
      quiet = true;
      std::puts("请停止讲话，保持安静。");
    }
    const size_t rate = pcm.captureRate;
    if (elapsed >= 15s && rate && pcm.captured == scoreSeconds * rate) return [observer validateLive];
    if (elapsed >= 15500ms) return FailMessage("did not collect a full 15 seconds of capture-post");
    std::this_thread::sleep_for(5ms);
  }
  return false;
}

bool StopDevice(LKRTCAudioDeviceModule *adm, DeviceObserver *observer, bool started) {
  [observer beginStop];
  const NSInteger status = [adm stopRecording];
  if (status) [adm setEngineAvailability:LKRTCAudioEngineAvailability{NO, NO}];
  const bool released = [observer finishStop:started];
  return !status && !adm.isRecording && !adm.isPlaying && released;
}

bool RunHardware(const probe_route::Target &target, const std::shared_ptr<DevicePcm> &owner) {
  auto &pcm = *owner;
  @autoreleasepool {
    __attribute__((objc_precise_lifetime)) DeviceHook *render = [[DeviceHook alloc] initWithPcm:owner output:YES];
    __attribute__((objc_precise_lifetime)) DeviceHook *capture = [[DeviceHook alloc] initWithPcm:owner output:NO];
    __attribute__((objc_precise_lifetime)) DeviceObserver *observer =
        [[DeviceObserver alloc] initWithPcm:owner target:target];
    LKRTCDefaultAudioProcessingModule *apm = [[LKRTCDefaultAudioProcessingModule alloc]
        initWithConfig:nil capturePostProcessingDelegate:nil renderPreProcessingDelegate:nil];
    apm.renderPreProcessingDelegate = render;
    apm.capturePostProcessingDelegate = capture;
    __attribute__((objc_precise_lifetime)) LKRTCPeerConnectionFactory *factory = [[LKRTCPeerConnectionFactory alloc]
        initWithAudioDeviceModuleType:LKRTCAudioDeviceModuleTypeAudioEngine bypassVoiceProcessing:YES
        encoderFactory:nil decoderFactory:nil audioProcessingModule:apm];
    LKRTCAudioDeviceModule *adm = factory.audioDeviceModule;
    probe::ConfigureApm(apm, true);
    if (!adm || adm.isManualRenderingMode || adm.isRecording || adm.isPlaying ||
        [adm setPlatformVoiceProcessingAllowed:NO] != 0 || !probe::PlatformPolicyOff(adm) ||
        !probe::ConfigMatches(apm, factory, true) || apm.renderPreProcessingDelegate != render ||
        apm.capturePostProcessingDelegate != capture) {
      return FailMessage("device ADM policy or native APM configuration did not qualify before start");
    }

    adm.observer = observer;
    const bool passed = RunTrial(pcm, [&] {
      if ([adm initAndStartRecording] == 0) return true;
      return FailMessage("native ADM start failed");
    }, [&] { return RunScore(pcm, observer, adm, apm, factory); },
       [&](bool started) { return StopDevice(adm, observer, started); });
    adm.observer = nil;
    apm.renderPreProcessingDelegate = nil;
    apm.capturePostProcessingDelegate = nil;
    return passed;
  }
}

bool FinishEvidence(const DevicePcm &pcm) {
  const auto rate = std::find(renderRates.begin(), renderRates.end(), pcm.renderRate);
  if (rate == renderRates.end() || pcm.rendered != pcm.render[rate - renderRates.begin()].size() ||
      !pcm.captureRate || pcm.captured != scoreSeconds * pcm.captureRate ||
      pcm.tapNonzeroFrames < pcm.tapRate / 10 || !pcm.firstTapHostTime ||
      pcm.lastTapHostTime <= pcm.firstTapHostTime) {
    return FailMessage("missing render-pre, capture-post or time-qualified same-graph playback witness");
  }
  std::printf("render_pre_rate=%zu blocks_during_playback=%zu resident_frames=%zu "
              "capture_post_rate=%zu mono_frames=%zu pcm16_clipped=%zu\n",
              pcm.renderRate, pcm.renderBlocks, pcm.rendered, pcm.captureRate.load(),
              pcm.captured.load(), pcm.captureClipped);
  std::printf("mixer_tap_rate=%.0f channels=%u frames=%zu nonzero_frames=%zu "
              "first_host_ticks=%llu first_frame_offset=%zu last_host_ticks=%llu last_frame_offset=%zu\n",
              pcm.tapRate, pcm.tapChannels, pcm.tapFrames, pcm.tapNonzeroFrames,
              static_cast<unsigned long long>(pcm.firstTapHostTime), pcm.firstTapOffset,
              static_cast<unsigned long long>(pcm.lastTapHostTime), pcm.lastTapOffset);
  return true;
}

bool TestPcm() {
  DevicePcm pcm({0, 1200, -600, 0});
  std::array<float, 8> samples{};
  if (!pcm.gate.Arm()) return false;
  FeedRender(pcm, samples.data(), samples.size(), 48000);
  if (pcm.rendered) return false;
  pcm.play = true;
  FeedRender(pcm, samples.data(), samples.size(), 48000);
  if (!pcm.endOfFixture || samples != std::array<float, 8>{0, 600, 1200, 300, -600, -300, 0, 0}) {
    return false;
  }
  SaveCapture(pcm, samples.data(), samples.size(), 48000);
  AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
  AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:8];
  buffer.frameLength = 8;
  std::copy(samples.begin(), samples.end(), buffer.floatChannelData[0]);
  ObserveTap(pcm, buffer, [AVAudioTime timeWithHostTime:321]);
  pcm.gate.Close();
  SaveCapture(pcm, samples.data(), samples.size(), 48000);
  return pcm.gate.Drained() && !pcm.fault && pcm.captured == 8 && pcm.capture[2] == 1200 &&
      pcm.tapFrames == 8 && pcm.tapNonzeroFrames == 5 && pcm.firstTapHostTime == 321 &&
      pcm.firstTapOffset == 1 && pcm.lastTapOffset == 5;
}

bool TestRollback() {
  DevicePcm pcm({0});
  bool continued = false;
  bool rolledBack = false;
  const bool accepted = RunTrial(pcm, [] { return false; }, [&] {
    continued = true;
    return true;
  }, [&](bool started) {
    rolledBack = !started && !pcm.gate.Arm();
    return rolledBack;
  });
  DevicePcm mismatch({0});
  bool stoppedAfterStart = false;
  const bool activated = RunTrial(mismatch, [] { return true; }, [&] {
    mismatch.Fail("simulated active route mismatch");
    return false;
  }, [&](bool started) {
    stoppedAfterStart = started && !mismatch.gate.Arm();
    return stoppedAfterStart;
  });

  CallbackGate gate;
  if (!gate.Arm() || !gate.Enter()) return false;
  gate.Close();
  const bool refused = !gate.Enter() && !gate.Drained();
  gate.Leave();
  return !accepted && !continued && rolledBack && !activated && stoppedAfterStart &&
      refused && gate.Drained();
}

int SelfTest() {
  const char *missing[] = {"--device", "--standard-mic-mode", "/tmp/in", "/tmp/out"};
  const char *approved[] = {"--device", "--authorize-device", "--standard-mic-mode", "/tmp/in", "/tmp/out"};
  if (HasDeviceAuthorization(4, missing) || !HasDeviceAuthorization(5, approved) ||
      !TestRollback() || !TestPcm() || !probe_wave::SelfTest()) {
    FailMessage("device harness self-test");
    return 1;
  }
  std::puts("device_harness_self_test=PASS device_io_attempted=0");
  return 0;
}

int RunDevice(int argc, const char *argv[]) {
  using probe::interrupted;
  if (argc == 1 && std::strcmp(argv[0], "--device-self-test") == 0) return SelfTest();
  if (!HasDeviceAuthorization(argc, argv) || !isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) {
    FailMessage("device mode requires both authorization flags, absolute paths and an interactive Terminal");
    return 64;
  }

  const char *error = nullptr;
  std::vector<int16_t> resident;
  probe_route::Target target;
  if (!probe_wave::LoadResident(argv[3], resident, error) ||
      !probe_wave::CheckCapturePath(argv[4], error) ||
      !probe_route::SelectDefaults(target, error)) {
    FailMessage(error);
    return 1;
  }
  if (!WaitForMicAuthorization()) return interrupted ? 130 : 1;
  if (!probe_route::SelectDefaults(target, error) || !StandardMicMode()) {
    FailMessage(error ?: "confirm Standard Mic Mode in Control Center");
    return 1;
  }

  auto pcm = std::make_shared<DevicePcm>(resident);
  std::puts("15 秒试验即将开始。看到提示再讲话，Ctrl-C 取消。");
  if (!RunHardware(target, pcm) || !FinishEvidence(*pcm)) {
    if (const char *fault = pcm->fault) FailMessage(fault);
    return interrupted ? 130 : 1;
  }
  if (interrupted) return 130;
  if (!probe_wave::WriteCapture(argv[4], pcm->capture.data(), pcm->captured, pcm->captureRate, error)) {
    FailMessage(error);
    return 1;
  }
  std::puts("试验结束。本机录音已保存，可回听。");
  return 0;
}
}  // namespace

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 3) return 64;
    if (!probe::InitializeProcess(argv[1])) return 1;
    return RunDevice(argc - 2, argv + 2);
  }
}
