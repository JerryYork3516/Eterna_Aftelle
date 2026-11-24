#include "NativeVoiceRealtime.h"
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdio.h>

static atomic_uint blocked_point, entered, resume_callback;

void nvt_io_test_hook(unsigned point) {
    if (point != atomic_load(&blocked_point)) return;
    atomic_store(&entered, 1);
    while (!atomic_load(&resume_callback)) sched_yield();
}

static NVTRTIO *context(void) {
    NVTRTConfig config = {
        .capture_channels = 1, .max_callback_frames = 128,
        .timebase_numerator = 125, .timebase_denominator = 3,
        .capture_capacity = 128, .playback_capacity = 128,
        .configuration_id = 8, .capture_token = 4, .playback_token = 2
    };
    NVTRTIO *io = nvt_rt_create(config);
    assert(io && nvt_rt_activate(io));
    return io;
}

static void render(NVTRTIO *io, float *frames, uint32_t count, const AudioTimeStamp *stamp) {
    bool silent;
    AudioBufferList list = {1, {{1, count * sizeof(float), frames}}};
    assert(nvt_rt_render_at_time(io, &silent, stamp, count, &list) == noErr);
}

static void sample_facts(void) {
    NVTRTIO *io = context();
    float output[7];
    NVTRenderFact fact;
    render(io, output, 7, NULL);
    assert(nvt_rt_take_render_fact(io, &fact));
    assert(fact.flags == NVT_RENDER_IDLE && fact.time_flags == 0 && fact.submitted_frames == 0);

    assert(nvt_rt_set_playback(io, 2, false));
    const float pcm[] = {0, 0.25f, 0, -0.25f, 0};
    assert(nvt_rt_enqueue(io, pcm, 5, 2, true) == NVT_WRITE_OK);
    AudioTimeStamp time = {
        .mSampleTime = 19.5, .mHostTime = 1000,
        .mFlags = kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid
    };
    render(io, output, 7, &time);
    assert(output[1] == 0.25f && output[3] == -0.25f && !output[6]);
    assert(nvt_rt_take_render_fact(io, &fact));
    assert(fact.configuration_id == 8 && fact.playback_token == 2 && fact.acknowledged_token == 2);
    assert(fact.time_flags == time.mFlags && fact.sample_time == 19.5);
    assert(fact.host_time == 1000 && fact.host_time_ns == 41666 && fact.frame_count == 7);
    assert(fact.submitted_frames == 5 && fact.nonzero_frames == 2 && fact.first_nonzero == 1 && fact.nonzero_end == 4);
    assert(fact.flags & NVT_RENDER_END);
    assert(!(fact.flags & NVT_RENDER_UNDERRUN));

    for (unsigned j = 0; j < NVT_RENDER_FACT_CAPACITY + 1; ++j) render(io, output, 7, NULL);
    assert(nvt_rt_stats(io).dropped_render_facts == 1);
    assert(nvt_rt_set_playback(io, 3, true));
    assert(nvt_rt_stats(io).rendered_clear_token != 3);
    render(io, output, 7, NULL);
    assert(nvt_rt_stats(io).rendered_clear_token == 3);
    assert(nvt_rt_stats(io).dropped_render_facts == 2);
    for (unsigned j = 0; j < NVT_RENDER_FACT_CAPACITY; ++j) assert(nvt_rt_take_render_fact(io, &fact));
    assert(!nvt_rt_take_render_fact(io, &fact));
    render(io, output, 7, &time);
    assert(nvt_rt_take_render_fact(io, &fact));
    assert(fact.playback_token == 3 && fact.submitted_frames == 0 && fact.nonzero_frames == 0);
    assert(fact.flags == (NVT_RENDER_CLEAR | NVT_RENDER_CANCELLED));
    nvt_rt_destroy(io);
}

static void *late_capture(void *context) {
    float input[4] = {1, 2, 3, 4};
    AudioBufferList list = {1, {{1, sizeof input, input}}};
    assert(nvt_rt_capture(context, NULL, 4, &list) == noErr);
    return NULL;
}

static void shared_generation_fence(void) {
    NVTRTIO *io = context();
    pthread_t thread;
    atomic_store(&blocked_point, 1);
    assert(pthread_create(&thread, NULL, late_capture, io) == 0);
    while (!atomic_load(&entered)) sched_yield();
    assert(nvt_rt_set_capture(io, 5));
    assert(nvt_ring_consumer_sync(nvt_rt_capture_ring(io)) == 5);
    atomic_store(&resume_callback, 1);
    assert(pthread_join(thread, NULL) == 0);
    float samples[4];
    NVTFrame metadata[4];
    assert(nvt_ring_read(nvt_rt_capture_ring(io), samples, metadata, 4, false, false).copied == 0);
    atomic_store(&blocked_point, 0);
    late_capture(io);
    assert(nvt_ring_read(nvt_rt_capture_ring(io), samples, metadata, 4, false, false).copied == 4);
    assert(samples[0] == 1 && samples[3] == 4);
    assert(nvt_ring_stats(nvt_rt_capture_ring(io)).active_token == 5);
    nvt_rt_destroy(io);
}

static void *render_stream(void *context) {
    float output[7];
    for (uint64_t i = 1; i <= 10000; ++i) {
        AudioTimeStamp stamp = {.mSampleTime = (double)i, .mHostTime = i, .mFlags = kAudioTimeStampSampleTimeValid};
        render(context, output, 7, &stamp);
    }
    return NULL;
}

static void concurrent_fact_reader(void) {
    NVTRTIO *io = context();
    pthread_t thread;
    assert(pthread_create(&thread, NULL, render_stream, io) == 0);
    uint64_t seen = 0, last = 0;
    while (seen + nvt_rt_stats(io).dropped_render_facts < 10000) {
        NVTRenderFact fact;
        if (!nvt_rt_take_render_fact(io, &fact)) { sched_yield(); continue; }
        assert(fact.host_time > last && fact.sample_time == (double)fact.host_time);
        assert(fact.frame_count == 7 && fact.flags == NVT_RENDER_IDLE && !fact.host_time_ns);
        last = fact.host_time;
        ++seen;
    }
    assert(pthread_join(thread, NULL) == 0);
    assert(seen > 0);
    nvt_rt_destroy(io);
}

int main(void) {
    sample_facts();
    shared_generation_fence();
    concurrent_fact_reader();
    puts("native_voice_p3_realtime_fact_suites=3");
    puts("native_voice_p3_realtime_device_access=ZERO");
}
