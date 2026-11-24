#ifndef NATIVE_VOICE_REALTIME_H
#define NATIVE_VOICE_REALTIME_H

#include "NativeVoiceRing.h"
#include <AudioToolbox/AudioToolbox.h>

typedef struct NVTRTIO NVTRTIO;
typedef struct {
    uint32_t capture_channels, capture_channel, max_callback_frames;
    bool capture_interleaved;
    uint32_t timebase_numerator, timebase_denominator;
    size_t capture_capacity, playback_capacity;
    uint64_t configuration_id, capture_token, playback_token;
} NVTRTConfig;

typedef struct {
    uint64_t active_token, acknowledged_token, rendered_end_token;
    uint64_t idle_frames, cancelled_frames, underrun_frames;
    uint64_t rejected_input_frames, rejected_output_frames;
} NVTRTStats;

#ifdef __cplusplus
extern "C" {
#endif
CF_ASSUME_NONNULL_BEGIN
// The owner creates one context per graph. An old graph can only close, never reopen.
NVTRTIO * _Nullable nvt_rt_create(NVTRTConfig config);
void nvt_rt_destroy(NVTRTIO * _Nullable io);
bool nvt_rt_activate(NVTRTIO *io);
void nvt_rt_close(NVTRTIO *io);
bool nvt_rt_active(const NVTRTIO *io);
NVTRing *nvt_rt_capture_ring(NVTRTIO *io);
NVTRTStats nvt_rt_stats(const NVTRTIO *io);

// Serial non-realtime control and playback producer. Only the sink publishes capture.
bool nvt_rt_set_playback(NVTRTIO *io, uint64_t token, bool cancelled);
size_t nvt_rt_playback_space(const NVTRTIO *io, uint64_t token);
NVTWriteStatus nvt_rt_enqueue(NVTRTIO *io, const float * _Nullable samples, size_t count, uint64_t token, bool end);
NVTRingStats nvt_rt_capture_stats(const NVTRTIO *io);

// One sink producer and one source consumer. The caller owns the ABL for this invocation.
OSStatus nvt_rt_capture(NVTRTIO *io, const AudioTimeStamp * _Nullable time, uint32_t frames,
                        const AudioBufferList * _Nullable input);
OSStatus nvt_rt_render(NVTRTIO *io, bool *silence, uint32_t frames, AudioBufferList * _Nullable output);
CF_ASSUME_NONNULL_END
#ifdef __cplusplus
}
#endif

#ifdef __OBJC__
#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NVTRTLease : NSObject
- (nullable instancetype)initWithConfig:(NVTRTConfig)config NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) NVTRTIO *io;
- (AVAudioSinkNode *)makeSink;
- (AVAudioSourceNode *)makeSourceWithFormat:(AVAudioFormat *)format;
@end
FOUNDATION_EXPORT BOOL nvt_negotiate_voice_output(AVAudioEngine *engine, AVAudioFormat *capture);
FOUNDATION_EXPORT BOOL nvt_connect_voice_graph(AVAudioEngine *engine, AVAudioSinkNode *sink, AVAudioSourceNode *source,
                                               AVAudioFormat *capture, AVAudioFormat *sourceFormat);
NS_ASSUME_NONNULL_END
#endif
#endif
