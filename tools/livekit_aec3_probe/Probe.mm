#import <AVFoundation/AVFoundation.h>

#include "ProbeSupport.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <thread>
#include <vector>

namespace {
using namespace probe;
constexpr size_t sampleRate = 48000;
constexpr size_t blockFrames = sampleRate / 100;
constexpr size_t maxManualFrames = 3072;
constexpr size_t fixtureFrames = 599 * (blockFrames / 2) + 173;
constexpr size_t warmupBlocks = 15;
constexpr std::array<size_t, 3> renderRates{16000, 32000, 48000};
constexpr size_t captureFrames = 630 * blockFrames;
constexpr NSInteger graphRejected = -7701;
constexpr auto settleTime = std::chrono::milliseconds(35);
bool Require(bool condition, const char *message) {
  if (!condition) std::fprintf(stderr, "FAIL %s\n", message);
  return condition;
}

struct ProbePcm {
  std::array<std::vector<int16_t>, renderRates.size()> render;
  std::vector<int16_t> input = std::vector<int16_t>(captureFrames);
  std::vector<int16_t> capture = std::vector<int16_t>(captureFrames);
  std::atomic<bool> invalid{false};
  std::atomic<size_t> captured{0};
  std::atomic<size_t> renderBlocks{0};
  size_t renderOffset = 0;
  size_t inputOffset = 0;
  size_t paddedFrames = 0;
  size_t renderRate = 0;
  size_t firstPadding = 0;
};

bool CheckFixtureResampling() {
  const std::vector<int16_t> input{0, 1200, -600, 0};
  return Require(ResampleFixture(input, 16000) == std::vector<int16_t>{0, 300, 0} &&
      ResampleFixture(input, 32000) == std::vector<int16_t>{0, 900, 300, -450, 0, 0} &&
      ResampleFixture(input, 48000) == std::vector<int16_t>{0, 600, 1200, 300, -600, -300, 0, 0},
      "24 kHz fixture resampling and continuity");
}

void FillRender(ProbePcm &pcm) {
  std::vector<int16_t> fixture(fixtureFrames);
  uint32_t random = 0xe9934e21;
  int32_t smoothed = 0;
  for (auto &sample : fixture) {
    random = random * 1664525u + 1013904223u;
    smoothed = (3 * smoothed + static_cast<int32_t>(random >> 17) - 16384) / 4;
    sample = static_cast<int16_t>(smoothed);
  }
  for (size_t index = 0; index < renderRates.size(); ++index) {
    pcm.render[index] = ResampleFixture(fixture, renderRates[index]);
  }
}

void FillEcho(ProbePcm &pcm) {
  constexpr size_t firstDelay = (warmupBlocks + 7) * blockFrames;
  constexpr size_t secondDelay = (warmupBlocks + 9) * blockFrames + 137;
  const auto &render = pcm.render.back();
  for (size_t frame = 0; frame < pcm.input.size(); ++frame) {
    const auto delayed = [&render, frame](size_t delay) {
      return frame >= delay && frame - delay < render.size()
          ? render[frame - delay] : 0;
    };
    pcm.input[frame] = delayed(firstDelay) / 2 + delayed(secondDelay) / 5;
  }
}

bool IsSample(float sample) {
  return std::isfinite(sample) && sample >= -32768.0f && sample <= 32767.0f;
}

enum class RunMode { matched, silentReference, aecOff, cancel, rejectConfig, rejectGraph };
}  // namespace

@interface ProbeHook : NSObject <LKRTCAudioCustomProcessingDelegate>
- (instancetype)initWithPcm:(ProbePcm *)pcm render:(BOOL)render silent:(BOOL)silent;
@end

@implementation ProbeHook {
  ProbePcm *_pcm;
  BOOL _render;
  BOOL _silent;
  size_t _rate;
  size_t _channels;
}

- (instancetype)initWithPcm:(ProbePcm *)pcm render:(BOOL)render silent:(BOOL)silent {
  self = [super init];
  if (self) {
    _pcm = pcm;
    _render = render;
    _silent = silent;
  }
  return self;
}

- (void)audioProcessingInitializeWithSampleRate:(size_t)rate channels:(size_t)channels {
  _rate = rate;
  _channels = channels;
}

- (void)audioProcessingProcess:(LKRTCAudioBuffer *)buffer {
  const size_t frames = _rate / 100;
  if (_channels != 1 || buffer.channels != 1 || buffer.frames != frames) {
    _pcm->invalid = true;
    return;
  }
  float *samples = [buffer rawBufferForChannel:0];
  if (_render) {
    const auto rate = std::find(renderRates.begin(), renderRates.end(), _rate);
    if (rate == renderRates.end()) {
      _pcm->invalid = true;
      return;
    }
    std::fill_n(samples, frames, 0.0f);
    if (++_pcm->renderBlocks <= warmupBlocks) return;
    if (_pcm->renderRate && _pcm->renderRate != _rate) {
      _pcm->invalid = true;
      return;
    }
    _pcm->renderRate = _rate;
    const auto &render = _pcm->render[rate - renderRates.begin()];
    const size_t provided = std::min(frames, render.size() - _pcm->renderOffset);
    if (!_silent) std::copy_n(render.data() + _pcm->renderOffset, provided, samples);
    _pcm->renderOffset += provided;
    if (provided < frames && !_pcm->paddedFrames) _pcm->firstPadding = frames - provided;
    _pcm->paddedFrames += frames - provided;
    return;
  }
  if (_rate != sampleRate) {
    _pcm->invalid = true;
    return;
  }
  const size_t offset = _pcm->captured.load(std::memory_order_relaxed);
  if (offset == _pcm->capture.size()) return;
  for (size_t frame = 0; frame < blockFrames; ++frame) {
    if (!IsSample(samples[frame])) {
      _pcm->invalid = true;
      return;
    }
    _pcm->capture[offset + frame] = static_cast<int16_t>(std::lround(samples[frame]));
  }
  _pcm->captured.store(offset + blockFrames, std::memory_order_release);
}

- (void)audioProcessingRelease {}
@end

@interface ProbeInput : NSObject <LKRTCAudioDeviceModuleDelegate>
- (instancetype)initWithPcm:(ProbePcm *)pcm reject:(BOOL)reject;
@property(nonatomic, readonly) unsigned created;
@property(nonatomic, readonly) unsigned released;
@property(nonatomic, readonly) unsigned stopped;
@end

@implementation ProbeInput {
  ProbePcm *_pcm;
  AVAudioSourceNode *_node;
  BOOL _reject;
}

- (instancetype)initWithPcm:(ProbePcm *)pcm reject:(BOOL)reject {
  self = [super init];
  if (self) {
    _pcm = pcm;
    _reject = reject;
  }
  return self;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm didCreateEngine:(AVAudioEngine *)engine {
  if (!engine.isInManualRenderingMode || engine.manualRenderingMode != AVAudioEngineManualRenderingModeRealtime) {
    return graphRejected;
  }
  ++_created;
  return 0;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
              willEnableEngine:(AVAudioEngine *)engine isPlayoutEnabled:(BOOL)playout
            isRecordingEnabled:(BOOL)recording isVoiceProcessingEnabled:(BOOL)voiceProcessing {
  return engine.isInManualRenderingMode && playout && recording && !voiceProcessing ? 0 : graphRejected;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
                        engine:(AVAudioEngine *)engine configureInputFromSource:(AVAudioNode *)source
                 toDestination:(AVAudioNode *)destination withFormat:(AVAudioFormat *)format
                       context:(NSDictionary *)context {
  if (_reject || !engine.isInManualRenderingMode || source || _node ||
      format.sampleRate != sampleRate || format.channelCount != 1 ||
      format.commonFormat != AVAudioPCMFormatInt16 || !format.isInterleaved) {
    return graphRejected;
  }

  ProbePcm *pcm = _pcm;
  AVAudioSourceNodeRenderBlock render = ^OSStatus(BOOL *silence, const AudioTimeStamp *,
      AVAudioFrameCount frames, AudioBufferList *buffers) {
    if (!frames || frames > maxManualFrames || buffers->mNumberBuffers != 1) {
      pcm->invalid = true;
      return kAudio_ParamError;
    }
    AudioBuffer &buffer = buffers->mBuffers[0];
    if (buffer.mNumberChannels != 1 || !buffer.mData ||
        buffer.mDataByteSize != frames * sizeof(int16_t)) {
      pcm->invalid = true;
      return kAudio_ParamError;
    }
    auto *out = static_cast<int16_t *>(buffer.mData);
    const size_t count = std::min<size_t>(frames, pcm->input.size() - pcm->inputOffset);
    std::copy_n(pcm->input.data() + pcm->inputOffset, count, out);
    std::fill(out + count, out + frames, 0);
    pcm->inputOffset += count;
    *silence = count == 0;
    return noErr;
  };

  @try {
    _node = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:render];
    [engine attachNode:_node];
    [engine connect:_node to:destination format:format];
  } @catch (NSException *exception) {
    return graphRejected;
  }
  return 0;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm willReleaseEngine:(AVAudioEngine *)engine {
  if (_node && [engine.attachedNodes containsObject:_node]) [engine detachNode:_node];
  _node = nil;
  ++_released;
  return 0;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
               willStartEngine:(AVAudioEngine *)engine isPlayoutEnabled:(BOOL)playout
            isRecordingEnabled:(BOOL)recording {
  return engine.isInManualRenderingMode ? 0 : graphRejected;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
                 didStopEngine:(AVAudioEngine *)engine isPlayoutEnabled:(BOOL)playout
            isRecordingEnabled:(BOOL)recording {
  if (engine.isRunning) _pcm->invalid = true;
  ++_stopped;
  return 0;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
              didDisableEngine:(AVAudioEngine *)engine isPlayoutEnabled:(BOOL)playout
            isRecordingEnabled:(BOOL)recording {
  return 0;
}

- (NSInteger)audioDeviceModule:(LKRTCAudioDeviceModule *)adm
                        engine:(AVAudioEngine *)engine configureOutputFromSource:(AVAudioNode *)source
                 toDestination:(AVAudioNode *)destination withFormat:(AVAudioFormat *)format
                       context:(NSDictionary *)context {
  return graphRejected;
}

- (void)audioDeviceModuleDidUpdateDevices:(LKRTCAudioDeviceModule *)adm {}
- (void)audioDeviceModule:(LKRTCAudioDeviceModule *)adm didReceiveSpeechActivityEvent:(LKRTCSpeechActivityEvent)event {}
@end

namespace {
bool PrepareAdm(LKRTCAudioDeviceModule *adm) {
  return adm && !adm.isRecording && !adm.isPlaying &&
      [adm setManualRenderingMode:YES] == 0 && adm.isManualRenderingMode &&
      [adm setPlatformVoiceProcessingAllowed:NO] == 0 && !adm.isPlatformVoiceProcessingAllowed;
}

bool WaitForCapture(ProbePcm &pcm, size_t frames) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(12);
  while (pcm.captured.load(std::memory_order_acquire) < frames &&
         !pcm.invalid && !interrupted.load(std::memory_order_relaxed) &&
         std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
  }
  return pcm.captured >= frames;
}

bool CheckStopped(LKRTCAudioDeviceModule *adm, ProbeInput *observer, const ProbePcm &pcm) {
  if ([adm stopRecording] != 0) {
    [adm setEngineAvailability:LKRTCAudioEngineAvailability{NO, NO}];
    return Require(false, "ADM stop recording");
  }
  const size_t renderBlocks = pcm.renderBlocks;
  const size_t captured = pcm.captured;
  std::this_thread::sleep_for(settleTime);
  return Require(adm.isManualRenderingMode && !adm.isRecording && !adm.isPlaying &&
                 observer.created == 1 && observer.stopped == 1 && observer.released == 1 &&
                 pcm.renderBlocks == renderBlocks && pcm.captured == captured && !pcm.invalid,
                 "manual stop, joined callbacks, and observer release");
}

bool CheckCounts(const ProbePcm &pcm, RunMode mode) {
  if (mode == RunMode::cancel) {
    return Require(pcm.captured >= 30 * blockFrames && pcm.captured < captureFrames &&
                   pcm.renderOffset > 0 && pcm.paddedFrames == 0, "cancel before end of fixture");
  }

  const size_t step = pcm.renderRate ? probe::fixtureTicksPerSecond / pcm.renderRate : 0;
  if (!step) return Require(false, "render-pre did not consume a fixture");
  const size_t expected = (fixtureFrames * probe::fixtureTicksPerFrame + step - 1) / step;
  const size_t hookFrames = pcm.renderRate / 100;
  const size_t expectedPadding = (hookFrames - expected % hookFrames) % hookFrames;
  return Require(pcm.captured == captureFrames && pcm.inputOffset == captureFrames &&
                 pcm.renderOffset == expected && expectedPadding > 0 &&
                 pcm.firstPadding == expectedPadding && pcm.paddedFrames >= expectedPadding + hookFrames,
                 "frame accounting, partial EOS and a full silent tail block");
}

bool RunCase(ProbePcm &pcm, RunMode mode, const char *label) {
  if (interrupted.load(std::memory_order_relaxed)) return false;
  FillRender(pcm);
  FillEcho(pcm);
  const bool echo = mode != RunMode::aecOff;
  @autoreleasepool {
    __attribute__((objc_precise_lifetime)) ProbeHook *render =
        [[ProbeHook alloc] initWithPcm:&pcm render:YES silent:mode == RunMode::silentReference];
    __attribute__((objc_precise_lifetime)) ProbeHook *capture =
        [[ProbeHook alloc] initWithPcm:&pcm render:NO silent:NO];
    LKRTCDefaultAudioProcessingModule *apm = [[LKRTCDefaultAudioProcessingModule alloc]
        initWithConfig:nil capturePostProcessingDelegate:nil renderPreProcessingDelegate:nil];
    // This release's ObjC adapter installs delegates through the setters only.
    apm.renderPreProcessingDelegate = render;
    apm.capturePostProcessingDelegate = capture;
    __attribute__((objc_precise_lifetime)) ProbeInput *observer =
        [[ProbeInput alloc] initWithPcm:&pcm reject:mode == RunMode::rejectGraph];
    // The ADM wrapper borrows the factory's worker thread.
    __attribute__((objc_precise_lifetime)) LKRTCPeerConnectionFactory *factory = [[LKRTCPeerConnectionFactory alloc]
        initWithAudioDeviceModuleType:LKRTCAudioDeviceModuleTypeAudioEngine bypassVoiceProcessing:YES
        encoderFactory:nil decoderFactory:nil audioProcessingModule:apm];
    LKRTCAudioDeviceModule *adm = factory.audioDeviceModule;
    if (!Require(PrepareAdm(adm) && apm.renderPreProcessingDelegate == render &&
                 apm.capturePostProcessingDelegate == capture, "manual ADM and APM hook setup")) return false;

    ConfigureApm(apm, echo && mode != RunMode::rejectConfig);
    if (mode == RunMode::rejectConfig) {
      const bool rejected = !ConfigMatches(apm, factory, true) && ConfigMatches(apm, factory, false);
      if (!Require(rejected && !adm.isRecording && !pcm.renderBlocks && !pcm.captured,
                   "configuration mismatch rejected before start")) return false;
      std::puts("case=reject_config mismatch_rejected=1 adm_started=0");
      return true;
    }
    if (!Require(ConfigMatches(apm, factory, echo), "native APM config after Factory init")) return false;
    adm.observer = observer;
    if (interrupted.load(std::memory_order_relaxed)) return false;
    const NSInteger start = [adm initAndStartRecording];
    if (start != 0) {
      std::printf("case=%s adm_start=%ld graph_create=%u graph_release=%u\n",
                  label, static_cast<long>(start), observer.created, observer.released);
      return Require(mode == RunMode::rejectGraph && start == graphRejected &&
                     !adm.isRecording && !pcm.renderBlocks && !pcm.captured &&
                     observer.created == 1 && observer.released == 1 && observer.stopped == 0,
                     "ADM setup rejection and rollback");
    }

    bool valid = Require(mode != RunMode::rejectGraph && ConfigMatches(apm, factory, echo) &&
                         adm.isRecording && adm.isManualRenderingMode && PlatformPolicyOff(adm),
                         "native APM config after manual ADM start");
    if (valid) valid = WaitForCapture(pcm, mode == RunMode::cancel ? 30 * blockFrames : captureFrames);
    const bool stopped = CheckStopped(adm, observer, pcm);
    if (stopped) {
      adm.observer = nil;
      apm.renderPreProcessingDelegate = nil;
      apm.capturePostProcessingDelegate = nil;
    }
    if (interrupted.load(std::memory_order_relaxed)) {
      std::printf("case=%s interrupted=1 stopped=%d\n", label, stopped);
      return false;
    }
    if (!stopped) return false;
    std::printf("case=%s apm_aec=%d render_rate=%zu render_blocks=%zu render_fixture_frames=%zu "
                "first_padding=%zu total_padding=%zu capture_frames=%zu stopped=%d\n",
                label, echo, pcm.renderRate, pcm.renderBlocks.load(), pcm.renderOffset,
                pcm.firstPadding, pcm.paddedFrames, pcm.captured.load(), stopped);
    return Require(valid && stopped, "manual run and shutdown") && CheckCounts(pcm, mode);
  }
}

double TailRms(const std::vector<int16_t> &samples) {
  double energy = 0;
  for (size_t frame = 5 * sampleRate; frame < 6 * sampleRate; ++frame) {
    const double sample = samples[frame];
    energy += sample * sample;
  }
  return std::sqrt(energy / sampleRate);
}

bool CheckSignals(const ProbePcm &matched, const ProbePcm &silent, const ProbePcm &off) {
  int maxError = 0;
  for (size_t frame = 0; frame < captureFrames; ++frame) {
    maxError = std::max(maxError, std::abs(off.input[frame] - off.capture[frame]));
  }
  const double matchedRms = TailRms(matched.capture);
  const double silentRms = TailRms(silent.capture);
  const double offRms = TailRms(off.capture);
  std::printf("capture_tail_rms_s16 matched=%.3f silent_reference=%.3f aec_off=%.3f "
              "aec_off_max_error_s16=%d\n", matchedRms, silentRms, offRms, maxError);
  return Require(maxError <= 2 && offRms > 100.0, "AEC-off sample-by-sample capture continuity") &&
      Require(silentRms > 100.0 && matchedRms < 0.75 * silentRms,
              "AEC3 capture responds to matched render reference");
}

bool Export(const std::vector<int16_t> &capture, const char *path) {
  FILE *file = std::fopen(path, "wb");
  if (!file) return false;
  const size_t written = std::fwrite(capture.data(), sizeof(capture[0]), capture.size(), file);
  const int closed = std::fclose(file);
  return written == capture.size() && closed == 0;
}
}  // namespace

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (!Require(argc == 3, "manual arguments") || !probe::InitializeProcess(argv[1]) ||
        !CheckFixtureResampling()) return 1;
    ProbePcm negative, rejected, canceled, matched, silent, disabled;
    if (!RunCase(negative, RunMode::rejectConfig, "reject_config") ||
        !RunCase(rejected, RunMode::rejectGraph, "reject_graph") ||
        !RunCase(canceled, RunMode::cancel, "cancel") ||
        !RunCase(matched, RunMode::matched, "matched") ||
        !RunCase(silent, RunMode::silentReference, "silent_reference") ||
        !RunCase(disabled, RunMode::aecOff, "aec_off") ||
        !CheckSignals(matched, silent, disabled)) return interrupted.load(std::memory_order_relaxed) ? 130 : 1;
    if (interrupted.load(std::memory_order_relaxed)) return 130;
    if (!Require(Export(matched.capture, argv[2]), "capture-post PCM16LE export")) return 1;
    std::puts("offline_checks=PASS manual_playout_pcm=NOT_EXPOSED");
    return 0;
  }
}
