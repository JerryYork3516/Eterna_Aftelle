#import "NativeVoiceRealtime.h"
#include <memory>

// Copies of the lease are made by the block runtime at installation and teardown.
// Invocation borrows its immutable pointer; it cannot retain or free the graph.
@implementation NVTRTLease {
    std::shared_ptr<NVTRTIO> _context;
}
- (nullable instancetype)initWithConfig:(NVTRTConfig)config {
    self = [super init];
    if (!self) return nil;
    NVTRTIO *io = nvt_rt_create(config);
    if (!io) return nil;
    try {
        _context = std::shared_ptr<NVTRTIO>(io, nvt_rt_destroy);
    } catch (const std::bad_alloc &) {
        return nil;
    }
    return self;
}
- (NVTRTIO *)io { return _context.get(); }

- (AVAudioSinkNode *)makeSink {
    const auto lease = _context;
    return [[AVAudioSinkNode alloc] initWithReceiverBlock:^OSStatus(
        const AudioTimeStamp *time, AVAudioFrameCount frames, const AudioBufferList *input) {
        return nvt_rt_capture(lease.get(), time, frames, input);
    }];
}
- (AVAudioSourceNode *)makeSourceWithFormat:(AVAudioFormat *)format {
    const auto lease = _context;
    return [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(
        BOOL *isSilent, const AudioTimeStamp *time, AVAudioFrameCount frames, AudioBufferList *output) {
        bool silent = true;
        OSStatus status = nvt_rt_render_at_time(lease.get(), &silent, time, frames, output);
        *isSilent = silent;
        return status;
    }];
}
@end

BOOL nvt_connect_voice_graph(AVAudioEngine *engine, AVAudioSinkNode *sink, AVAudioSourceNode *source,
                             AVAudioFormat *capture, AVAudioFormat *sourceFormat) {
    @try {
        [engine attachNode:sink];
        [engine attachNode:source];
        [engine connect:engine.inputNode to:sink format:capture];
        [engine connect:source to:engine.mainMixerNode format:sourceFormat];
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}

BOOL nvt_negotiate_voice_output(AVAudioEngine *engine, AVAudioFormat *capture) {
    if (engine.isRunning) return NO;
    @try {
        [engine connect:engine.mainMixerNode to:engine.outputNode format:capture];
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}
