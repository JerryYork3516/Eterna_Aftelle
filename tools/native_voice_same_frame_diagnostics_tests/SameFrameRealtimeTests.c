#include "NativeVoiceRealtime.h"
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdio.h>

enum { BLOCKS = 2048, FRAMES = 8 };
typedef struct {
    NVTRTIO *io;
    atomic_bool finished;
    uint64_t verified;
} Fixture;

static void *sink(void *argument) {
    Fixture *fixture = argument;
    float samples[FRAMES * 2];
    AudioBufferList list = {
        .mNumberBuffers = 1,
        .mBuffers = {{ .mNumberChannels = 2, .mDataByteSize = sizeof(samples), .mData = samples }}
    };
    for (uint64_t block = 1; block <= BLOCKS; ++block) {
        for (size_t i = 0; i < FRAMES; ++i) {
            samples[i * 2] = (float)block;
            samples[i * 2 + 1] = -(float)block;
        }
        assert(nvt_rt_capture(fixture->io, NULL, FRAMES, &list) == noErr);
    }
    atomic_store_explicit(&fixture->finished, true, memory_order_release);
    return NULL;
}

static void *worker(void *argument) {
    Fixture *fixture = argument;
    uint64_t previous = 0;
    while (true) {
        NVTSameFrameBlock block;
        if (!nvt_rt_peek_same_frame(fixture->io, &block)) {
            if (atomic_load_explicit(&fixture->finished, memory_order_acquire)
                && !nvt_rt_peek_same_frame(fixture->io, &block)) break;
            if (!nvt_rt_peek_same_frame(fixture->io, &block)) { sched_yield(); continue; }
        }
        assert(block.id > previous && block.capture_token == 1 && block.configuration_id == 3);
        assert(block.frames == FRAMES && block.channels == 2 && block.interleaved);
        for (size_t i = 0; i < FRAMES; ++i) {
            assert(block.samples[i * 2] == (float)block.id);
            assert(block.samples[i * 2 + 1] == -(float)block.id);
        }
        previous = block.id;
        fixture->verified++;
        nvt_rt_release_same_frame(fixture->io);
    }
    return NULL;
}

int main(void) {
    Fixture fixture = {
        .io = nvt_rt_create((NVTRTConfig){
            .capture_channels = 2, .capture_channel = 0, .max_callback_frames = 32, .capture_interleaved = true,
            .timebase_numerator = 1, .timebase_denominator = 1, .capture_capacity = 32768,
            .playback_capacity = 16, .configuration_id = 3, .capture_token = 1, .playback_token = 1
        })
    };
    atomic_init(&fixture.finished, false);
    assert(fixture.io && nvt_rt_enable_same_frame(fixture.io) && nvt_rt_activate(fixture.io));
    assert(!nvt_rt_enable_same_frame(fixture.io));
    pthread_t producer, consumer;
    assert(pthread_create(&producer, NULL, sink, &fixture) == 0);
    assert(pthread_create(&consumer, NULL, worker, &fixture) == 0);
    assert(pthread_join(producer, NULL) == 0 && pthread_join(consumer, NULL) == 0);
    NVTSameFrameStats facts = nvt_rt_same_frame_stats(fixture.io);
    assert(facts.pending_blocks == 0 && fixture.verified > 0 && fixture.verified + facts.dropped_blocks == BLOCKS);
    assert(facts.dropped_frames == facts.dropped_blocks * FRAMES);
    assert(nvt_rt_stats(fixture.io).accepted_input_frames == BLOCKS * FRAMES);
    nvt_rt_close(fixture.io);
    NVTSameFrameBlock retired;
    assert(!nvt_rt_peek_same_frame(fixture.io, &retired));
    nvt_rt_destroy(fixture.io);
    printf("native_voice_same_frame_c_cases=1 submitted_blocks=%d validated_blocks=%llu dropped_blocks=%llu\n",
           BLOCKS, (unsigned long long)fixture.verified, (unsigned long long)facts.dropped_blocks);
}
