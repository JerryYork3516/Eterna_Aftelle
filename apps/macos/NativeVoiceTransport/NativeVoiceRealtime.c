#include "NativeVoiceRealtime.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>

#ifdef NVT_IO_TESTING
void nvt_io_test_hook(unsigned point);
#define IO_HOOK(point) nvt_io_test_hook(point)
#else
#define IO_HOOK(point) ((void)0)
#endif

_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_LLONG_LOCK_FREE == 2, "RT atomics must be lock-free");
typedef _Atomic unsigned long long Counter;
enum { PREPARED, ACTIVE, CLOSED };

struct NVTRTIO {
    NVTRTConfig config;
    NVTRing *capture, *playback;
    float *capture_scratch;
    uint64_t lost_before;  // Sink producer only; committed with its next accepted block.
    atomic_uint state;
    Counter playing, primed, cancelling, rendered_end, idle, cancelled, underrun, rejected_input, rejected_output;
};

static uint64_t value(const Counter *counter) {
    return atomic_load_explicit(counter, memory_order_acquire);
}
static void publish(Counter *counter, uint64_t number) {
    atomic_store_explicit(counter, number, memory_order_release);
}
static void count(Counter *counter, uint64_t frames) {
    atomic_fetch_add_explicit(counter, frames, memory_order_relaxed);
}

NVTRTIO *nvt_rt_create(NVTRTConfig config) {
    if (!config.capture_channels || config.capture_channel >= config.capture_channels ||
        config.capture_token == UINT64_MAX ||
        !config.max_callback_frames || config.capture_channels > UINT32_MAX / sizeof(float) ||
        config.max_callback_frames > UINT32_MAX / sizeof(float) / config.capture_channels ||
        !config.timebase_numerator || !config.timebase_denominator) return NULL;

    NVTRTIO *io = calloc(1, sizeof(*io));
    if (!io) return NULL;
    io->config = config;
    atomic_init(&io->state, PREPARED);
    Counter *fields[] = {&io->playing, &io->primed, &io->cancelling, &io->rendered_end, &io->idle, &io->cancelled,
                         &io->underrun, &io->rejected_input, &io->rejected_output};
    for (size_t i = 0; i < sizeof(fields) / sizeof(*fields); ++i) {
        atomic_init(fields[i], 0);
        if (!atomic_is_lock_free(fields[i])) { nvt_rt_destroy(io); return NULL; }
    }
    io->capture = nvt_ring_create(config.capture_capacity, config.capture_token);
    io->playback = nvt_ring_create(config.playback_capacity, config.playback_token);
    io->capture_scratch = calloc(config.max_callback_frames, sizeof(float));
    if (!atomic_is_lock_free(&io->state) || !io->capture || !io->playback || !io->capture_scratch) {
        nvt_rt_destroy(io);
        return NULL;
    }
    return io;
}

void nvt_rt_destroy(NVTRTIO *io) {
    if (!io) return;
    nvt_ring_destroy(io->capture);
    nvt_ring_destroy(io->playback);
    free(io->capture_scratch);
    free(io);
}
bool nvt_rt_activate(NVTRTIO *io) {
    unsigned expected = PREPARED;
    return atomic_compare_exchange_strong_explicit(&io->state, &expected, ACTIVE,
                                                   memory_order_acq_rel, memory_order_acquire);
}
void nvt_rt_close(NVTRTIO *io) {
    atomic_store_explicit(&io->state, CLOSED, memory_order_release);
    // A graph never advances its capture token while active. Reserve its final token for close.
    nvt_ring_invalidate(io->capture, UINT64_MAX);
}
bool nvt_rt_active(const NVTRTIO *io) {
    return atomic_load_explicit(&io->state, memory_order_acquire) == ACTIVE;
}
NVTRing *nvt_rt_capture_ring(NVTRTIO *io) { return io->capture; }
NVTRingStats nvt_rt_capture_stats(const NVTRTIO *io) { return nvt_ring_stats(io->capture); }

bool nvt_rt_set_playback(NVTRTIO *io, uint64_t token, bool cancelled) {
    uint64_t active = nvt_ring_active_token(io->playback);
    if (!nvt_rt_active(io) || token < active || (cancelled && token == active)) return false;
    publish(cancelled ? &io->cancelling : &io->playing, token);
    return token == active || nvt_ring_invalidate(io->playback, token);
}
size_t nvt_rt_playback_space(const NVTRTIO *io, uint64_t token) {
    return nvt_rt_active(io) ? nvt_ring_write_space(io->playback, token) : 0;
}
NVTWriteStatus nvt_rt_enqueue(NVTRTIO *io, const float *samples, size_t frames, uint64_t token, bool end) {
    if (!nvt_rt_active(io) || value(&io->playing) != token ||
        nvt_ring_active_token(io->playback) != token) return NVT_WRITE_STALE;
    NVTWriteStatus result = end ? nvt_ring_write_end(io->playback, samples, frames, token)
        : nvt_ring_write(io->playback, samples, frames, (NVTStamp){0}, token);
    if (result == NVT_WRITE_OK && frames) publish(&io->primed, token);
    return result;
}

NVTRTStats nvt_rt_stats(const NVTRTIO *io) {
    return (NVTRTStats){
        .active_token = nvt_ring_active_token(io->playback),
        .acknowledged_token = nvt_ring_acknowledged_token(io->playback),
        .rendered_end_token = value(&io->rendered_end),
        .idle_frames = value(&io->idle), .cancelled_frames = value(&io->cancelled),
        .underrun_frames = value(&io->underrun), .rejected_input_frames = value(&io->rejected_input),
        .rejected_output_frames = value(&io->rejected_output)
    };
}

static bool has_float_frames(const AudioBuffer *buffer, uint32_t channels, uint32_t frames) {
    return buffer->mNumberChannels == channels && buffer->mData &&
        (uintptr_t)buffer->mData % _Alignof(float) == 0 &&
        (uint64_t)frames * channels * sizeof(float) <= buffer->mDataByteSize;
}

static const float *capture_mono(NVTRTIO *io, const AudioBufferList *input, uint32_t frames) {
    const NVTRTConfig *config = &io->config;
    if (!input || frames > config->max_callback_frames) return NULL;
    uint32_t buffers = config->capture_interleaved ? 1 : config->capture_channels;
    uint32_t channels = config->capture_interleaved ? config->capture_channels : 1;
    if (input->mNumberBuffers != buffers) return NULL;
    for (uint32_t i = 0; i < buffers; ++i) {
        if (!has_float_frames(&input->mBuffers[i], channels, frames)) return NULL;
    }
    if (channels == 1) return input->mBuffers[config->capture_channel].mData;
    const float *samples = input->mBuffers[0].mData;
    for (uint32_t i = 0; i < frames; ++i) {
        io->capture_scratch[i] = samples[(size_t)i * channels + config->capture_channel];
    }
    return io->capture_scratch;
}

static bool host_nanos(const NVTRTConfig *config, uint64_t ticks, uint64_t *nanos) {
    uint64_t numerator = config->timebase_numerator, denominator = config->timebase_denominator;
    uint64_t whole = ticks / denominator, rest = (ticks % denominator) * numerator / denominator;
    if (whole > (UINT64_MAX - rest) / numerator) return false;
    *nanos = whole * numerator + rest;
    return true;
}

static NVTStamp stamp_for(const NVTRTConfig *config, const AudioTimeStamp *time, uint32_t frames) {
    NVTStamp stamp = {0};
    if (!time) return stamp;
    double sample = time->mSampleTime;
    if ((time->mFlags & kAudioTimeStampSampleTimeValid) && isfinite(sample) && sample >= -0x1p63 && sample < 0x1p63) {
        int64_t position = (int64_t)sample;
        if ((double)position == sample && position <= INT64_MAX - frames) {
            stamp.sample_time = position;
            stamp.flags |= NVT_SAMPLE_TIME_VALID;
        }
    }
    if ((time->mFlags & kAudioTimeStampHostTimeValid) && host_nanos(config, time->mHostTime, &stamp.host_time_ns)) {
        stamp.flags |= NVT_HOST_TIME_VALID;
    }
    return stamp;
}

static void lost_input(NVTRTIO *io, uint32_t frames) {
    uint64_t previous = io->lost_before;
    io->lost_before = previous > UINT64_MAX - frames ? UINT64_MAX : previous + frames;
    count(&io->rejected_input, frames);
}

OSStatus nvt_rt_capture(NVTRTIO *io, const AudioTimeStamp *time, uint32_t frames, const AudioBufferList *input) {
    if (!frames || !nvt_rt_active(io)) return noErr;
    const uint64_t token = io->config.capture_token;
    const float *mono = capture_mono(io, input, frames);
    if (!mono) { lost_input(io, frames); return noErr; }

    NVTStamp stamp = stamp_for(&io->config, time, frames);
    NVTIngress ingress = {
        .configuration_id = io->config.configuration_id, .dropped_before = io->lost_before,
        .raw_sample_time = time ? time->mSampleTime : 0, .raw_host_time = time ? time->mHostTime : 0,
        .raw_flags = time ? time->mFlags : 0
    };
    IO_HOOK(1);
    if (!nvt_rt_active(io) || token != nvt_ring_active_token(io->capture)) return noErr;
    NVTWriteStatus status = nvt_ring_write_capture(io->capture, mono, frames, stamp, ingress, token);
    if (status == NVT_WRITE_OK) io->lost_before = 0;
    else lost_input(io, frames);
    return noErr;
}

OSStatus nvt_rt_render(NVTRTIO *io, bool *silence, uint32_t frames, AudioBufferList *output) {
    const uint64_t token = nvt_ring_active_token(io->playback);
    const bool enabled = nvt_rt_active(io);
    const bool expected = value(&io->primed) == token;
    *silence = true;
    if (!frames) return noErr;
    if (!output || output->mNumberBuffers != 1 || !has_float_frames(&output->mBuffers[0], 1, frames)) {
        count(&io->rejected_output, frames);
        return kAudio_ParamError;
    }
    float *samples = output->mBuffers[0].mData;
    if (frames > io->config.max_callback_frames) {
        __builtin_memset(samples, 0, (size_t)frames * sizeof(float));
        count(&io->rejected_output, frames);
        return noErr;
    }

    NVTReadResult read = {0};
    IO_HOOK(3);
    if (enabled) read = nvt_ring_read_for_token(io->playback, samples, frames, token);
    if (read.copied < frames) __builtin_memset(samples + read.copied, 0, (frames - read.copied) * sizeof(float));
    IO_HOOK(2);
    bool invalid = enabled && (read.invalidated || token != nvt_ring_active_token(io->playback) || !nvt_rt_active(io));
    size_t copied = invalid ? 0 : read.copied;
    size_t missing = frames - copied;
    if (invalid && read.copied) __builtin_memset(samples, 0, read.copied * sizeof(float));
    if (invalid || value(&io->cancelling) == token) count(&io->cancelled, missing);
    else if (enabled && expected && !read.reached_end) count(&io->underrun, missing);
    else count(&io->idle, missing);
    if (!invalid && read.reached_end) publish(&io->rendered_end, token);
    *silence = copied == 0;
    return noErr;
}
