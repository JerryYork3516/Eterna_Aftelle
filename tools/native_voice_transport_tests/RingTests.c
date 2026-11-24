#include "NativeVoiceRing.h"
#include <assert.h>
#include <limits.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdio.h>

static atomic_uint hook_point, hook_entered, hook_release;
void nvt_test_hook(unsigned point) {
    if (atomic_load(&hook_point) != point) return;
    atomic_store(&hook_entered, 1);
    while (!atomic_load(&hook_release)) sched_yield();
}
static void wait_hook(void) { while (!atomic_load(&hook_entered)) sched_yield(); }
static void arm(unsigned point) {
    atomic_store(&hook_entered, 0); atomic_store(&hook_release, 0); atomic_store(&hook_point, point);
}
static void release_hook(void) { atomic_store(&hook_point, 0); atomic_store(&hook_release, 1); }

static void boundaries(void) {
    assert(!nvt_ring_create(0, 1)); assert(!nvt_ring_create(8, 0));
    NVTRing *r = nvt_ring_create(7, 1); assert(r && nvt_ring_atomics_lock_free(r));
    float input[8] = {1,2,3,4,5,6,7,8}, out[8]; NVTFrame frames[8];
    NVTStamp stamp = {.sample_time = 123, .host_time_ns = 456, .flags = 3};
    assert(nvt_ring_read(r, out, frames, 8, false, false).copied == 0);
    assert(nvt_ring_write(r, input, 8, stamp, 1) == NVT_WRITE_FULL);
    for (unsigned iteration = 0; iteration < 1000; ++iteration) {
        assert(nvt_ring_write(r, input, 7, stamp, 1) == NVT_WRITE_OK);
        assert(nvt_ring_write(r, input, 1, stamp, 1) == NVT_WRITE_FULL);
        for (unsigned offset = 0; offset < 7;) {
            unsigned count = offset < 6 ? 3 : 1;
            NVTReadResult result = nvt_ring_read(r, out, frames, count, false, false);
            assert(result.copied == count);
            for (unsigned j = 0; j < count; ++j) {
                assert(out[j] == input[offset + j]);
                assert(frames[j].offset == offset + j && frames[j].origin.sample_time == 123);
            }
            offset += count;
        }
    }
    NVTReadResult idle = nvt_ring_read(r, out, NULL, 8, true, false);
    assert(idle.copied == 0 && idle.silence == 8);
    for (unsigned j = 0; j < 8; ++j) assert(out[j] == 0);
    assert(nvt_ring_read(r, out, NULL, 3, true, true).silence == 3);
    assert(nvt_ring_write(r, input, 0, stamp, 1) == NVT_WRITE_INVALID);
    stamp.sample_time = INT64_MAX;
    assert(nvt_ring_write(r, input, 1, stamp, 1) == NVT_WRITE_INVALID);
    NVTRingStats stats = nvt_ring_stats(r);
    assert(stats.high_water_frames == 7 && stats.water_frames == 0);
    assert(stats.overflow_events == 1001 && stats.underrun_frames == 3 && stats.idle_silence_frames == 8);
    assert(nvt_ring_invalidate(r, 2)); assert(!nvt_ring_invalidate(r, 2)); assert(!nvt_ring_invalidate(r, 1));
    assert(nvt_ring_write(r, input, 1, (NVTStamp){0}, 1) == NVT_WRITE_STALE);
    assert(nvt_ring_write(r, input, 1, (NVTStamp){0}, 2) == NVT_WRITE_AWAITING_CLEAR);
    assert(nvt_ring_stats(r).acknowledged_token == 1);
    assert(nvt_ring_consumer_sync(r) == 2);
    assert(nvt_ring_write(r, input, 1, (NVTStamp){0}, 2) == NVT_WRITE_OK);
    assert(nvt_ring_read(r, out, NULL, 1, false, false).copied == 1);
    nvt_ring_destroy(r);
}

typedef struct { NVTRing *ring; size_t total; } Context;
static void *sequence_writer(void *value) {
    Context *c = value;
    for (size_t i = 0; i < c->total;) {
        float samples[61]; size_t count = 1 + i % 61;
        if (count > c->total - i) count = c->total - i;
        for (size_t j = 0; j < count; ++j) samples[j] = (float)(i + j);
        NVTWriteStatus status = nvt_ring_write(c->ring, samples, count, (NVTStamp){.sample_time=(int64_t)i,.flags=1}, 1);
        if (status == NVT_WRITE_OK) i += count; else { assert(status == NVT_WRITE_FULL); sched_yield(); }
    }
    return NULL;
}
static void *sequence_reader(void *value) {
    Context *c = value;
    for (size_t i = 0; i < c->total;) {
        float samples[79]; NVTFrame frames[79];
        NVTReadResult result = nvt_ring_read(c->ring, samples, frames, 1 + i % 79, false, false);
        for (size_t j = 0; j < result.copied; ++j) {
            assert(samples[j] == (float)(i+j));
            assert(frames[j].origin.sample_time + frames[j].offset == (int64_t)(i+j));
        }
        i += result.copied;
        if (!result.copied) sched_yield();
    }
    return NULL;
}
static void spsc(void) {
    Context c = {.ring=nvt_ring_create(257,1), .total=1000000}; assert(c.ring);
    pthread_t producer, consumer;
    assert(!pthread_create(&producer,NULL,sequence_writer,&c));
    assert(!pthread_create(&consumer,NULL,sequence_reader,&c));
    assert(!pthread_join(producer,NULL)); assert(!pthread_join(consumer,NULL));
    assert(nvt_ring_stats(c.ring).water_frames == 0); nvt_ring_destroy(c.ring);
}

static void *one_write(void *value) {
    float samples[4] = {9,9,9,9};
    assert(nvt_ring_write(value,samples,4,(NVTStamp){0},1) == NVT_WRITE_STALE);
    return NULL;
}
static void *one_read(void *value) {
    float samples[4];
    NVTReadResult result = nvt_ring_read(value,samples,NULL,4,true,true);
    assert(result.invalidated && result.copied == 0 && result.silence == 4);
    for (unsigned j=0;j<4;++j) assert(samples[j]==0);
    return NULL;
}
static void forced_races(void) {
    NVTRing *r = nvt_ring_create(8,1); pthread_t thread; float samples[4]={2,2,2,2}, out[8];
    arm(1); assert(!pthread_create(&thread,NULL,one_write,r)); wait_hook();
    assert(nvt_ring_invalidate(r,2)); assert(nvt_ring_consumer_sync(r)==2);
    release_hook(); assert(!pthread_join(thread,NULL));
    assert(nvt_ring_write(r,samples,4,(NVTStamp){0},2)==NVT_WRITE_OK);
    NVTReadResult result=nvt_ring_read(r,out,NULL,8,false,false);
    assert(result.copied==4); for(unsigned j=0;j<4;++j)assert(out[j]==2);
    nvt_ring_destroy(r);
    r=nvt_ring_create(8,1); assert(nvt_ring_write(r,samples,4,(NVTStamp){0},1)==NVT_WRITE_OK);
    arm(2); assert(!pthread_create(&thread,NULL,one_read,r)); wait_hook();
    assert(nvt_ring_invalidate(r,2)); release_hook(); assert(!pthread_join(thread,NULL));
    assert(nvt_ring_consumer_sync(r)==2); assert(nvt_ring_stats(r).water_frames==0);
    assert(nvt_ring_stats(r).invalidated_silence_frames==4 && nvt_ring_stats(r).underrun_frames==0);
    nvt_ring_destroy(r);
}

static atomic_bool finished;
static atomic_uint accepted, consumed;
static void *clear_writer(void *value) {
    NVTRing *r=value;
    while(!atomic_load(&finished)) {
        uint64_t token=nvt_ring_active_token(r); float samples[13];
        for(unsigned j=0;j<13;++j)samples[j]=(float)token;
        if(nvt_ring_write(r,samples,13,(NVTStamp){0},token)==NVT_WRITE_OK)atomic_fetch_add(&accepted,1);
        sched_yield();
    }
    return NULL;
}
static void *clear_reader(void *value) {
    NVTRing *r=value;
    while(!atomic_load(&finished)) {
        float samples[17]; NVTReadResult result=nvt_ring_read(r,samples,NULL,17,false,false);
        for(size_t j=0;j<result.copied;++j)assert(samples[j]==(float)result.token);
        if(result.copied)atomic_fetch_add(&consumed,1);
        sched_yield();
    }
    return NULL;
}
static void clear_stress(void) {
    NVTRing *r=nvt_ring_create(113,1); pthread_t producer,consumer;
    assert(!pthread_create(&producer,NULL,clear_writer,r)); assert(!pthread_create(&consumer,NULL,clear_reader,r));
    while(atomic_load(&consumed)<100)sched_yield();
    for(uint64_t token=2;token<=30000;++token) {
        assert(nvt_ring_invalidate(r,token));
        if(token%7==0)sched_yield();
        NVTRingStats stats=nvt_ring_stats(r); assert(stats.water_frames<=113 && stats.high_water_frames<=113);
    }
    atomic_store(&finished,true); assert(!pthread_join(producer,NULL)); assert(!pthread_join(consumer,NULL));
    assert(atomic_load(&accepted)>0 && atomic_load(&consumed)>0);
    assert(nvt_ring_invalidate(r,30001));
    assert(nvt_ring_consumer_sync(r)==30001);
    float sample=1,out[113]; assert(nvt_ring_write(r,&sample,1,(NVTStamp){0},30000)==NVT_WRITE_STALE);
    assert(nvt_ring_read(r,out,NULL,113,false,false).copied==0);
    nvt_ring_destroy(r);
}

int main(void) {
    boundaries(); spsc(); forced_races(); clear_stress();
    puts("native_voice_ring_suites=4\nnative_voice_spsc_frames=1000000\nnative_voice_clear_transitions=30000\nnative_voice_forced_races=2\nnative_voice_device_access=ZERO");
}
