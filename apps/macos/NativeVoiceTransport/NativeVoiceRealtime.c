#include "NativeVoiceRealtime.h"
#include <math.h>
#include <stdatomic.h>
#include <stddef.h>
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

#ifdef NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
enum { SAME_FRAME_SLOTS = 16, SAME_FRAME_SAMPLE_BUDGET = 524288 };
typedef struct {
    uint32_t frames_per_slot;
    size_t samples_per_slot;
    float *samples;
    Counter read, written, dropped, dropped_frames;
    NVTSameFrameBlock blocks[SAME_FRAME_SLOTS];
} SameFrameQueue;
#endif

struct NVTRTIO {
    NVTRTConfig config;
    NVTRing *capture, *playback;
    float *capture_scratch;
    uint64_t lost_before;  // Sink producer only; committed with its next accepted block.
    uint64_t lost_token;
    atomic_uint state;
    Counter playing, primed, cancelling, rendered_end, idle, cancelled, underrun, rejected_input, rejected_output;
    Counter rendered_clear, render_read, render_written, render_dropped;
    Counter capture_minimum_host, capture_callbacks, accepted_input;
    Counter capture_fence_missing, capture_fence_old, capture_stale;
    NVTRenderFact render_facts[NVT_RENDER_FACT_CAPACITY];
#ifdef NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
    SameFrameQueue *same_frame;
#endif
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
                         &io->underrun, &io->rejected_input, &io->rejected_output,
                         &io->rendered_clear, &io->render_read, &io->render_written, &io->render_dropped,
                         &io->capture_minimum_host, &io->capture_callbacks, &io->accepted_input,
                         &io->capture_fence_missing, &io->capture_fence_old, &io->capture_stale};
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

#ifdef NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
bool nvt_rt_enable_same_frame(NVTRTIO *io) {
    if (io->same_frame || atomic_load_explicit(&io->state, memory_order_acquire) != PREPARED) return false;
    size_t max_frames = SAME_FRAME_SAMPLE_BUDGET / SAME_FRAME_SLOTS / io->config.capture_channels;
    if (!max_frames) return false;
    SameFrameQueue *queue = calloc(1, sizeof(*queue));
    if (!queue) return false;
    queue->frames_per_slot = max_frames < io->config.max_callback_frames
        ? (uint32_t)max_frames : io->config.max_callback_frames;
    queue->samples_per_slot = (size_t)queue->frames_per_slot * io->config.capture_channels;
    queue->samples = calloc(SAME_FRAME_SLOTS * queue->samples_per_slot, sizeof(float));
    atomic_init(&queue->read, 0);
    atomic_init(&queue->written, 0);
    atomic_init(&queue->dropped, 0);
    atomic_init(&queue->dropped_frames, 0);
    if (!queue->samples) { free(queue); return false; }
    // Touch the arena on the control side before a hardware callback can write it.
    volatile float *memory = queue->samples;
    for (size_t i = 0; i < SAME_FRAME_SLOTS * queue->samples_per_slot; i += 1024) memory[i] = 0;
    io->same_frame = queue;
    return true;
}

bool nvt_rt_peek_same_frame(const NVTRTIO *io, NVTSameFrameBlock *block) {
    const SameFrameQueue *queue = io->same_frame;
    if (!queue || !nvt_rt_active(io)) return false;
    uint64_t read = value(&queue->read);
    if (read == value(&queue->written)) return false;
    *block = queue->blocks[read % SAME_FRAME_SLOTS];
    return true;
}

void nvt_rt_release_same_frame(NVTRTIO *io) {
    SameFrameQueue *queue = io->same_frame;
    if (!queue) return;
    uint64_t read = value(&queue->read);
    if (read == value(&queue->written)) return;
    size_t slot = read % SAME_FRAME_SLOTS;
    size_t samples = (size_t)queue->blocks[slot].frames * io->config.capture_channels;
    __builtin_memset(queue->samples + slot * queue->samples_per_slot, 0, samples * sizeof(float));
    publish(&queue->read, read + 1);
}

NVTSameFrameStats nvt_rt_same_frame_stats(const NVTRTIO *io) {
    const SameFrameQueue *queue = io->same_frame;
    if (!queue) return (NVTSameFrameStats){0};
    return (NVTSameFrameStats){ value(&queue->dropped), value(&queue->dropped_frames),
                                value(&queue->written) - value(&queue->read) };
}

// Only the Sink writes. Publish before the PCM block so the Worker can join by ID.
static void offer_same_frame(NVTRTIO *io, const AudioBufferList *input, uint64_t id,
                             uint64_t capture, uint64_t playback, uint32_t frames) {
    SameFrameQueue *queue = io->same_frame;
    uint64_t written = value(&queue->written);
    if (frames > queue->frames_per_slot || written - value(&queue->read) == SAME_FRAME_SLOTS) {
        count(&queue->dropped, 1);
        count(&queue->dropped_frames, frames);
        return;
    }
    size_t slot = written % SAME_FRAME_SLOTS;
    float *dest = queue->samples + slot * queue->samples_per_slot;
    uint32_t channels = io->config.capture_channels;
    if (io->config.capture_interleaved) {
        __builtin_memcpy(dest, input->mBuffers[0].mData, (size_t)frames * channels * sizeof(float));
    } else {
        for (uint32_t channel = 0; channel < channels; ++channel) {
            __builtin_memcpy(dest + (size_t)channel * frames, input->mBuffers[channel].mData,
                             (size_t)frames * sizeof(float));
        }
    }
    queue->blocks[slot] = (NVTSameFrameBlock){
        .id = id, .configuration_id = io->config.configuration_id,
        .capture_token = capture, .playback_token = playback,
        .frames = frames, .channels = channels, .selected_channel = io->config.capture_channel,
        .interleaved = io->config.capture_interleaved, .samples = dest
    };
    publish(&queue->written, written + 1);
}
#endif

void nvt_rt_destroy(NVTRTIO *io) {
    if (!io) return;
    nvt_ring_destroy(io->capture);
    nvt_ring_destroy(io->playback);
    free(io->capture_scratch);
#ifdef NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
    if (io->same_frame) {
        free(io->same_frame->samples);
        free(io->same_frame);
    }
#endif
    free(io);
}
bool nvt_rt_activate(NVTRTIO *io) {
    unsigned expected = PREPARED;
    return atomic_compare_exchange_strong_explicit(&io->state, &expected, ACTIVE,
                                                   memory_order_acq_rel, memory_order_acquire);
}
void nvt_rt_close(NVTRTIO *io) {
    atomic_store_explicit(&io->state, CLOSED, memory_order_release);
    // UINT64_MAX is reserved for retirement.
    nvt_ring_invalidate(io->capture, UINT64_MAX);
}
bool nvt_rt_active(const NVTRTIO *io) {
    return atomic_load_explicit(&io->state, memory_order_acquire) == ACTIVE;
}
NVTRing *nvt_rt_capture_ring(NVTRTIO *io) { return io->capture; }
NVTRingStats nvt_rt_capture_stats(const NVTRTIO *io) { return nvt_ring_stats(io->capture); }

bool nvt_rt_set_capture(NVTRTIO *io, uint64_t token, uint64_t minimum_host_ns) {
    if (!nvt_rt_active(io) || token >= UINT64_MAX || token <= nvt_ring_active_token(io->capture) ||
        !minimum_host_ns || minimum_host_ns < value(&io->capture_minimum_host)) return false;
    // Acquiring the successor ring token also acquires its content-time lower bound.
    publish(&io->capture_minimum_host, minimum_host_ns);
    return nvt_ring_invalidate(io->capture, token);
}

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
        .rendered_clear_token = value(&io->rendered_clear),
        .dropped_render_facts = value(&io->render_dropped),
        .idle_frames = value(&io->idle), .cancelled_frames = value(&io->cancelled),
        .underrun_frames = value(&io->underrun), .rejected_input_frames = value(&io->rejected_input),
        .rejected_output_frames = value(&io->rejected_output),
        .capture_minimum_host_ns = value(&io->capture_minimum_host),
        .capture_callbacks = value(&io->capture_callbacks), .accepted_input_frames = value(&io->accepted_input),
        .capture_fence_missing_frames = value(&io->capture_fence_missing),
        .capture_fence_old_frames = value(&io->capture_fence_old),
        .capture_stale_frames = value(&io->capture_stale)
    };
}

bool nvt_rt_take_render_fact(NVTRTIO *io, NVTRenderFact *fact) {
    uint64_t read = value(&io->render_read);
    if (read == value(&io->render_written)) return false;
    *fact = io->render_facts[read % NVT_RENDER_FACT_CAPACITY];
    publish(&io->render_read, read + 1);
    return true;
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
    if ((time->mFlags & kAudioTimeStampHostTimeValid) && time->mHostTime &&
        host_nanos(config, time->mHostTime, &stamp.host_time_ns) && stamp.host_time_ns) {
        stamp.flags |= NVT_HOST_TIME_VALID;
    }
    return stamp;
}

static void lost_input(NVTRTIO *io, uint32_t frames) {
    uint64_t previous = io->lost_before;
    io->lost_before = previous > UINT64_MAX - frames ? UINT64_MAX : previous + frames;
    count(&io->rejected_input, frames);
}

static OSStatus nvt_rt_capture_for_token(NVTRTIO *io, uint64_t token, const AudioTimeStamp *time,
                                         uint32_t frames, const AudioBufferList *input) {
    if (!frames || !nvt_rt_active(io)) return noErr;
#ifdef NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
    const uint64_t diagnostic_playback = io->same_frame ? nvt_ring_active_token(io->playback) : 0;
#endif
    const uint64_t minimum_host = value(&io->capture_minimum_host);
    count(&io->capture_callbacks, 1);
    if (token != io->lost_token) {
        io->lost_token = token;
        io->lost_before = 0;
    }
    NVTStamp stamp = stamp_for(&io->config, time, frames);
    if (minimum_host) {
        if (stamp.flags != (NVT_SAMPLE_TIME_VALID | NVT_HOST_TIME_VALID)) {
            count(&io->capture_fence_missing, frames);
            lost_input(io, frames);
            return noErr;
        }
        if (stamp.host_time_ns < minimum_host) {
            count(&io->capture_fence_old, frames);
            lost_input(io, frames);
            return noErr;
        }
    }
    const float *mono = capture_mono(io, input, frames);
    if (!mono) { lost_input(io, frames); return noErr; }

    NVTIngress ingress = {
        .configuration_id = io->config.configuration_id, .dropped_before = io->lost_before,
        .raw_sample_time = time ? time->mSampleTime : 0, .raw_host_time = time ? time->mHostTime : 0,
        .raw_flags = time ? time->mFlags : 0, .callback_frames = frames
    };
#ifdef NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
    if (io->same_frame) {
        ingress.diagnostic_block = value(&io->capture_callbacks);
        offer_same_frame(io, input, ingress.diagnostic_block, token, diagnostic_playback, frames);
    }
#endif
    IO_HOOK(1);
    if (!nvt_rt_active(io) || token != nvt_ring_active_token(io->capture)) {
        count(&io->capture_stale, frames);
        count(&io->rejected_input, frames);
        return noErr;
    }
    NVTWriteStatus status = nvt_ring_write_capture(io->capture, mono, frames, stamp, ingress, token);
    if (status == NVT_WRITE_OK) {
        io->lost_before = 0;
        count(&io->accepted_input, frames);
    } else {
        if (status == NVT_WRITE_STALE) count(&io->capture_stale, frames);
        lost_input(io, frames);
    }
    return noErr;
}

OSStatus nvt_rt_capture(NVTRTIO *io, const AudioTimeStamp *time, uint32_t frames, const AudioBufferList *input) {
    return nvt_rt_capture_for_token(io, nvt_ring_active_token(io->capture), time, frames, input);
}

// Only Source writes records. A full queue drops facts, never PCM or the clear fence.
static void publish_render(NVTRTIO *io, const AudioTimeStamp *time, NVTRenderFact fact) {
    uint64_t write = value(&io->render_written);
    if (write - value(&io->render_read) >= NVT_RENDER_FACT_CAPACITY) {
        count(&io->render_dropped, 1);
        return;
    }
    if (time) {
        fact.time_flags = time->mFlags;
        fact.sample_time = time->mSampleTime;
        fact.host_time = time->mHostTime;
        if ((time->mFlags & kAudioTimeStampHostTimeValid) && time->mHostTime)
            host_nanos(&io->config, time->mHostTime, &fact.host_time_ns);
    }
    io->render_facts[write % NVT_RENDER_FACT_CAPACITY] = fact;
    publish(&io->render_written, write + 1);
}

OSStatus nvt_rt_render_at_time(NVTRTIO *io, bool *silence, const AudioTimeStamp *time,
                              uint32_t frames, AudioBufferList *output) {
    const uint64_t token = nvt_ring_active_token(io->playback);
    const bool enabled = nvt_rt_active(io);
    const bool expected = value(&io->primed) == token;
    *silence = true;
    if (!frames) return noErr;
    NVTRenderFact fact = {
        .configuration_id = io->config.configuration_id, .playback_token = token, .frame_count = frames
    };
    if (!output || output->mNumberBuffers != 1 || !has_float_frames(&output->mBuffers[0], 1, frames)) {
        count(&io->rejected_output, frames);
        fact.flags = NVT_RENDER_REJECTED;
        if (enabled) publish_render(io, time, fact);
        return kAudio_ParamError;
    }
    float *samples = output->mBuffers[0].mData;
    if (frames > io->config.max_callback_frames) {
        __builtin_memset(samples, 0, (size_t)frames * sizeof(float));
        count(&io->rejected_output, frames);
        fact.flags = NVT_RENDER_REJECTED;
        if (enabled) publish_render(io, time, fact);
        return noErr;
    }

    NVTReadResult read = {0};
    IO_HOOK(3);
    if (enabled) read = nvt_ring_read_for_token(io->playback, samples, frames, token);
    if (read.copied < frames) __builtin_memset(samples + read.copied, 0, (frames - read.copied) * sizeof(float));
    for (uint32_t i = 0; i < read.copied; ++i) {
        if (samples[i] == 0.0f) continue;
        if (!fact.nonzero_frames) fact.first_nonzero = i;
        fact.nonzero_end = i + 1;
        ++fact.nonzero_frames;
    }
    IO_HOOK(2);
    bool invalid = enabled && (read.invalidated || token != nvt_ring_active_token(io->playback) || !nvt_rt_active(io));
    size_t copied = invalid ? 0 : read.copied;
    size_t missing = frames - copied;
    if (invalid) {
        if (read.copied) __builtin_memset(samples, 0, read.copied * sizeof(float));
        fact.first_nonzero = fact.nonzero_end = fact.nonzero_frames = 0;
    }
    bool cancelling = value(&io->cancelling) == token;
    if (invalid || cancelling) {
        fact.flags |= NVT_RENDER_CANCELLED;
        count(&io->cancelled, missing);
    } else if (enabled && expected && !read.reached_end) {
        if (missing) fact.flags |= NVT_RENDER_UNDERRUN;
        count(&io->underrun, missing);
    } else {
        if (missing) fact.flags |= NVT_RENDER_IDLE;
        count(&io->idle, missing);
    }
    if (enabled && !invalid) {
        fact.acknowledged_token = nvt_ring_acknowledged_token(io->playback);
        if (read.reached_end && value(&io->rendered_end) != token) fact.flags |= NVT_RENDER_END;
        if (cancelling && !copied && fact.acknowledged_token == token) {
            fact.flags |= NVT_RENDER_CLEAR;
            publish(&io->rendered_clear, token);
        }
    }
    fact.submitted_frames = (uint32_t)copied;
    if (enabled) publish_render(io, time, fact);
    // Following idle callbacks must not overwrite the originating EOS time.
    if (fact.flags & NVT_RENDER_END) publish(&io->rendered_end, token);
    *silence = copied == 0;
    return noErr;
}

OSStatus nvt_rt_render(NVTRTIO *io, bool *silence, uint32_t frames, AudioBufferList *output) {
    return nvt_rt_render_at_time(io, silence, NULL, frames, output);
}

#if defined(NATIVE_VOICE_DIRECT_VPIO) && defined(NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS)
struct NVTDirectVPIO {
    NVTRTIO *io;
    AudioUnit unit;
    AudioBufferList *input;
    float *samples;
};

NVTDirectVPIO *nvt_direct_vpio_create(NVTRTIO *io, AudioUnit unit) {
    uint32_t channels = io->config.capture_channels;
    uint32_t frames = io->config.max_callback_frames;
    if (!unit || channels > 32) return NULL;
    uint32_t buffers = io->config.capture_interleaved ? 1 : channels;
    NVTDirectVPIO *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    context->io = io;
    context->unit = unit;
    context->input = calloc(1, offsetof(AudioBufferList, mBuffers) + buffers * sizeof(AudioBuffer));
    context->samples = calloc((size_t)frames * channels, sizeof(float));
    if (!context->input || !context->samples) {
        nvt_direct_vpio_destroy(context);
        return NULL;
    }
    volatile float *memory = context->samples;
    for (size_t i = 0; i < (size_t)frames * channels; i += 1024) memory[i] = 0;
    return context;
}

void nvt_direct_vpio_destroy(NVTDirectVPIO *context) {
    if (!context) return;
    free(context->input);
    free(context->samples);
    free(context);
}

OSStatus nvt_direct_vpio_capture(void *reference, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                                 UInt32 bus, UInt32 frames, AudioBufferList *ignored) {
    (void)bus;
    (void)ignored;
    NVTDirectVPIO *context = reference;
    NVTRTIO *io = context->io;
    const uint64_t token = nvt_ring_active_token(io->capture);
    if (!frames || !nvt_rt_active(io)) return noErr;
    const NVTRTConfig *format = &io->config;
    if (!time || frames > format->max_callback_frames) {
        nvt_rt_capture_for_token(io, token, time, frames, NULL);
        nvt_rt_close(io);
        return frames > format->max_callback_frames ? kAudioUnitErr_TooManyFramesToProcess : kAudio_ParamError;
    }

    const uint32_t buffers = format->capture_interleaved ? 1 : format->capture_channels;
    const uint32_t channels = format->capture_interleaved ? format->capture_channels : 1;
    const uint32_t bytes = frames * channels * sizeof(float);
    const size_t stride = (size_t)format->max_callback_frames * channels;
    AudioBufferList *input = context->input;
    AudioBuffer *planes = input->mBuffers;
    input->mNumberBuffers = buffers;
    for (uint32_t i = 0; i < buffers; ++i) {
        planes[i] = (AudioBuffer){channels, bytes, context->samples + i * stride};
    }

    AudioUnitRenderActionFlags action = flags ? *flags & ~kAudioUnitRenderAction_OutputIsSilence : 0;
    OSStatus status = AudioUnitRender(context->unit, &action, time, 1, frames, input);
    if (status == noErr && input->mNumberBuffers != buffers) status = kAudio_ParamError;
    for (uint32_t i = 0; status == noErr && i < buffers; ++i) {
        if (planes[i].mData != context->samples + i * stride || planes[i].mNumberChannels != channels ||
            planes[i].mDataByteSize != bytes) {
            status = kAudio_ParamError;
        } else if (action & kAudioUnitRenderAction_OutputIsSilence) {
            __builtin_memset(planes[i].mData, 0, bytes);
        }
    }
    // AudioUnitRender may overlap a capture-generation advance. Never relabel that callback.
    if (token != nvt_ring_active_token(io->capture)) {
        count(&io->capture_stale, frames);
        count(&io->rejected_input, frames);
    } else {
        nvt_rt_capture_for_token(io, token, time, frames, status == noErr ? input : NULL);
    }
    if (status != noErr) nvt_rt_close(io);
    return status;
}

OSStatus nvt_direct_vpio_render(void *reference, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                                UInt32 bus, UInt32 frames, AudioBufferList *output) {
    NVTDirectVPIO *context = reference;
    NVTRTIO *io = context->io;
    bool silence = true;
    OSStatus status = bus != 0 ? kAudio_ParamError :
        frames > io->config.max_callback_frames ? kAudioUnitErr_TooManyFramesToProcess :
        nvt_rt_render_at_time(io, &silence, time, frames, output);
    if (flags) {
        *flags = silence ? *flags | kAudioUnitRenderAction_OutputIsSilence
                         : *flags & ~kAudioUnitRenderAction_OutputIsSilence;
    }
    if (status != noErr) nvt_rt_close(io);
    return status;
}

void nvt_direct_vpio_changed(void *reference, AudioUnit unit, AudioUnitPropertyID property,
                             AudioUnitScope scope, AudioUnitElement bus) {
    (void)unit;
    (void)property;
    (void)scope;
    (void)bus;
    NVTDirectVPIO *context = reference;
    nvt_rt_close(context->io);
}
#endif
