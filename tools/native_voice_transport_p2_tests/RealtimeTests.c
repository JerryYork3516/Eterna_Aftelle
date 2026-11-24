#include "NativeVoiceRealtime.h"
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static atomic_uint armed, entered, resume;
void nvt_io_test_hook(unsigned point) {
    if (atomic_load(&armed) != point) return;
    atomic_store(&entered, 1);
    while (!atomic_load(&resume)) sched_yield();
}
void nvt_test_hook(unsigned point) { nvt_io_test_hook(10 + point); }
static void arm(unsigned point) {
    atomic_store(&entered, 0);
    atomic_store(&resume, 0);
    atomic_store(&armed, point);
}
static void wait_hook(void) { while (!atomic_load(&entered)) sched_yield(); }
static void release_hook(void) {
    atomic_store(&armed, 0);
    atomic_store(&resume, 1);
}

static NVTRTConfig config(bool interleaved) {
    return (NVTRTConfig) {
        .capture_channels = 2, .capture_channel = 1, .max_callback_frames = 16,
        .capture_interleaved = interleaved, .timebase_numerator = 125, .timebase_denominator = 3,
        .capture_capacity = 16, .playback_capacity = 16,
        .configuration_id = 721, .capture_token = 11, .playback_token = 21
    };
}
static AudioBufferList *input_abl(float *left, float *right, uint32_t frames, bool interleaved) {
    uint32_t count = interleaved ? 1 : 2;
    AudioBufferList *list = malloc(offsetof(AudioBufferList, mBuffers) + count * sizeof(AudioBuffer));
    assert(list);
    list->mNumberBuffers = count;
    list->mBuffers[0] = (AudioBuffer) {.mNumberChannels = interleaved ? 2 : 1,
        .mDataByteSize = frames * sizeof(float) * (interleaved ? 2 : 1), .mData = left};
    if (right) list->mBuffers[1] = (AudioBuffer) {.mNumberChannels = 1,
        .mDataByteSize = frames * sizeof(float), .mData = right};
    return list;
}

static void capture_layouts(void) {
    for (unsigned layout = 0; layout < 2; ++layout) {
        NVTRTIO *io = nvt_rt_create(config(layout));
        assert(io);
        float planar[7] = {1,2,3,4,5,6,7}, right[7] = {11,12,13,14,15,16,17}, mixed[14];
        for (size_t i = 0; i < 7; ++i) { mixed[i*2] = planar[i]; mixed[i*2+1] = right[i]; }
        AudioBufferList *list = input_abl(layout ? mixed : planar, layout ? NULL : right, 7, layout);
        AudioTimeStamp stamp = {.mSampleTime = -11, .mHostTime = 120, .mFlags = kAudioTimeStampSampleHostTimeValid};
        assert(nvt_rt_capture(io, &stamp, 7, list) == noErr);
        assert(nvt_rt_capture_stats(io).water_frames == 0);
        assert(nvt_rt_activate(io) && !nvt_rt_activate(io));
        assert(nvt_rt_capture(io, &stamp, 7, list) == noErr);
        float samples[16];
        NVTFrame frames[16];
        NVTRing *ring = nvt_rt_capture_ring(io);
        assert(nvt_ring_read(ring, samples, frames, 3, false, false).copied == 3);
        for (size_t i = 0; i < 3; ++i) {
            assert(samples[i] == right[i] && frames[i].offset == i);
            assert(frames[i].origin.sample_time == -11 && frames[i].origin.host_time_ns == 5000);
            assert(frames[i].origin.flags == 3 && frames[i].ingress.raw_flags == kAudioTimeStampSampleHostTimeValid);
            assert(frames[i].ingress.raw_sample_time == -11 && frames[i].ingress.raw_host_time == 120);
            assert(frames[i].ingress.configuration_id == 721 && frames[i].ingress.dropped_before == 0);
        }
        assert(nvt_ring_read(ring, samples, frames, 16, false, false).copied == 4);
        assert(frames[0].offset == 3 && samples[0] == right[3]);
        nvt_rt_capture(io, &stamp, 7, list);
        nvt_rt_capture(io, &stamp, 7, list);
        nvt_rt_capture(io, &stamp, 7, list); // full: the next accepted block gets the discontinuity
        nvt_rt_capture(io, &stamp, 17, list); // variable callback outside the allocation bound
        list->mBuffers[0].mDataByteSize = 1;
        nvt_rt_capture(io, &stamp, 5, list);
        assert(nvt_rt_capture_stats(io).overflow_events == 1);
        assert(nvt_rt_stats(io).rejected_input_frames == 29);
        assert(nvt_ring_read(ring, samples, frames, 16, false, false).copied == 14);
        assert(frames[13].ingress.dropped_before == 0);
        list->mBuffers[0].mDataByteSize = sizeof(float) * (layout ? 14 : 7);
        stamp.mSampleTime = 3.5;
        stamp.mHostTime = UINT64_MAX;
        nvt_rt_capture(io, &stamp, 5, list);
        assert(nvt_ring_read(ring, samples, frames, 16, false, false).copied == 5);
        assert(frames[0].ingress.dropped_before == 29 && frames[0].origin.flags == 0);
        assert(frames[0].ingress.raw_sample_time == 3.5 && frames[0].ingress.raw_host_time == UINT64_MAX);
        nvt_rt_capture(io, NULL, 1, list);
        assert(nvt_ring_read(ring, samples, frames, 16, false, false).copied == 1);
        assert(frames[0].ingress.dropped_before == 0 && frames[0].origin.flags == 0);
        nvt_rt_close(io);
        assert(!nvt_rt_activate(io));
        nvt_rt_capture(io, &stamp, 7, list);
        assert(nvt_rt_capture_stats(io).water_frames == 0);
        free(list);
        nvt_rt_destroy(io);
    }
}

static OSStatus render(NVTRTIO *io, float *samples, uint32_t frames, bool *silent) {
    AudioBufferList list = {.mNumberBuffers = 1, .mBuffers = {{1, frames * sizeof(float), samples}}};
    return nvt_rt_render(io, silent, frames, &list);
}

static void playback_boundaries(void) {
    NVTRTIO *io = nvt_rt_create(config(false));
    assert(io && nvt_rt_activate(io));
    float output[20], pcm[16] = {1,2,3,4,5,6,7};
    bool silent = false;
    assert(render(io, output, 7, &silent) == noErr && silent);
    assert(nvt_rt_stats(io).idle_frames == 7 && nvt_rt_stats(io).underrun_frames == 0);
    assert(nvt_rt_set_playback(io, 21, false));
    assert(nvt_rt_enqueue(io, pcm, 16, 21, false) == NVT_WRITE_OK);
    assert(nvt_rt_enqueue(io, pcm, 1, 21, false) == NVT_WRITE_FULL);
    assert(render(io, output, 13, &silent) == noErr && !silent && output[0] == 1);
    assert(render(io, output, 4, &silent) == noErr && !silent);
    assert(nvt_rt_stats(io).underrun_frames == 1);
    assert(nvt_rt_enqueue(io, pcm, 3, 21, true) == NVT_WRITE_OK);
    assert(nvt_rt_enqueue(io, pcm, 1, 21, false) == NVT_WRITE_INVALID);
    assert(render(io, output, 2, &silent) == noErr && !silent && output[1] == 2);
    assert(nvt_rt_stats(io).rendered_end_token == 0);
    assert(render(io, output, 6, &silent) == noErr && !silent && output[0] == 3 && output[1] == 0);
    assert(nvt_rt_stats(io).rendered_end_token == 21 && nvt_rt_stats(io).underrun_frames == 1);
    assert(nvt_rt_set_playback(io, 22, true));
    assert(nvt_rt_stats(io).acknowledged_token == 21);
    assert(nvt_rt_enqueue(io, pcm, 1, 21, true) == NVT_WRITE_STALE);
    assert(render(io, output, 5, &silent) == noErr && silent);
    assert(nvt_rt_stats(io).acknowledged_token == 22 && nvt_rt_stats(io).cancelled_frames == 5);
    assert(nvt_rt_set_playback(io, 23, false));
    assert(nvt_rt_enqueue(io, NULL, 0, 23, true) == NVT_WRITE_AWAITING_CLEAR);
    assert(render(io, output, 1, &silent) == noErr);
    assert(nvt_rt_enqueue(io, NULL, 0, 23, true) == NVT_WRITE_OK);
    assert(render(io, output, 3, &silent) == noErr && silent);
    assert(nvt_rt_stats(io).rendered_end_token == 23);
    output[0] = 991;
    AudioBufferList small = {.mNumberBuffers = 1, .mBuffers = {{1, sizeof(float), output}}};
    assert(nvt_rt_render(io, &silent, 4, &small) == kAudio_ParamError && silent && output[0] == 991);
    assert(render(io, output, 17, &silent) == noErr && silent && output[16] == 0);
    assert(nvt_rt_stats(io).rejected_output_frames == 21);
    nvt_rt_destroy(io);
}

static void *old_render(void *context) {
    float output[5] = {9,9,9,9,9};
    bool silent = false;
    assert(render(context, output, 5, &silent) == noErr && silent);
    for (size_t i = 0; i < 5; ++i) assert(output[i] == 0);
    return NULL;
}
static void render_cancel_races(void) {
    for (unsigned point = 2; point <= 3; ++point) {
        NVTRTIO *io = nvt_rt_create(config(false));
        assert(io && nvt_rt_activate(io) && nvt_rt_set_playback(io, 21, false));
        float pcm[7] = {11,12,13,14,15,16,17}, output[7];
        assert(nvt_rt_enqueue(io, pcm, 7, 21, true) == NVT_WRITE_OK);
        pthread_t thread;
        arm(point);
        assert(!pthread_create(&thread, NULL, old_render, io));
        wait_hook();
        assert(nvt_rt_set_playback(io, 22, true));
        assert(nvt_rt_set_playback(io, 23, false));
        assert(nvt_rt_enqueue(io, pcm, 7, 23, true) == NVT_WRITE_AWAITING_CLEAR);
        release_hook();
        assert(!pthread_join(thread, NULL));
        bool silent = true;
        if (point == 2) assert(render(io, output, 1, &silent) == noErr && silent);
        assert(nvt_rt_stats(io).acknowledged_token == 23 && nvt_rt_stats(io).rendered_end_token == 0);
        assert(nvt_rt_enqueue(io, pcm, 7, 23, true) == NVT_WRITE_OK);
        assert(render(io, output, 7, &silent) == noErr && !silent && output[0] == 11 && output[6] == 17);
        assert(nvt_rt_stats(io).rendered_end_token == 23 && nvt_rt_stats(io).cancelled_frames == 5);
        nvt_rt_destroy(io);
    }
}

static void *old_capture(void *context) {
    float mixed[8] = {1,2,1,2,1,2,1,2};
    AudioBufferList *list = input_abl(mixed, NULL, 4, true);
    AudioTimeStamp stamp = {.mSampleTime = 9, .mHostTime = 12, .mFlags = kAudioTimeStampSampleHostTimeValid};
    assert(nvt_rt_capture(context, &stamp, 4, list) == noErr);
    free(list);
    return NULL;
}
static void retired_capture_races(void) {
    unsigned points[] = {1, 11};
    for (size_t i = 0; i < sizeof(points) / sizeof(*points); ++i) {
        NVTRTIO *old = nvt_rt_create(config(true));
        assert(old && nvt_rt_activate(old));
        pthread_t thread;
        arm(points[i]);
        assert(!pthread_create(&thread, NULL, old_capture, old));
        wait_hook();
        nvt_rt_close(old);
        NVTRTConfig next = config(true);
        next.capture_token++;
        next.configuration_id++;
        NVTRTIO *fresh = nvt_rt_create(next);
        assert(fresh && nvt_rt_activate(fresh));
        release_hook();
        assert(!pthread_join(thread, NULL));
        assert(nvt_rt_capture_stats(old).water_frames == 0 && nvt_rt_capture_stats(fresh).water_frames == 0);
        assert(!nvt_rt_active(old) && nvt_rt_active(fresh));
        old_capture(fresh);
        float samples[4];
        NVTFrame frames[4];
        assert(nvt_ring_read(nvt_rt_capture_ring(fresh), samples, frames, 4, false, false).copied == 4);
        assert(samples[0] == 2 && frames[0].ingress.configuration_id == 722);
        nvt_rt_destroy(old);
        nvt_rt_destroy(fresh);
    }
}

int main(void) {
    capture_layouts();
    playback_boundaries();
    render_cancel_races();
    retired_capture_races();
    puts("native_voice_p2_realtime_suites=4\nnative_voice_p2_forced_boundary_races=4\nnative_voice_p2_device_access=ZERO");
}
