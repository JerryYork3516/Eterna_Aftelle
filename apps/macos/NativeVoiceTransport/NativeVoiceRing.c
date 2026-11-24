#include "NativeVoiceRing.h"
#include <limits.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#ifdef NVT_TESTING
void nvt_test_hook(unsigned point);
#define NVT_HOOK(point) nvt_test_hook(point)
#else
#define NVT_HOOK(point) ((void)0)
#endif

_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "64-bit atomics must always be lock-free");
_Static_assert(sizeof(unsigned long long) == sizeof(uint64_t), "64-bit counters required");
typedef _Atomic unsigned long long NVTCounter;
typedef struct { NVTFrame frame; uint64_t token; } NVTSlot;
struct NVTRing {
    size_t capacity;
    NVTSlot *slots;
    NVTCounter read_index, write_index, active, acknowledged;
    NVTCounter overflow, dropped, stale, underrun, idle, invalid_silence, cleared, high_water;
};

static uint64_t load(const NVTCounter *value) {
    return atomic_load_explicit(value, memory_order_acquire);
}
static void add(NVTCounter *value, uint64_t count) {
    atomic_fetch_add_explicit(value, count, memory_order_relaxed);
}

bool nvt_ring_atomics_lock_free(const NVTRing *r) {
    return r && atomic_is_lock_free(&r->read_index) && atomic_is_lock_free(&r->write_index)
        && atomic_is_lock_free(&r->active) && atomic_is_lock_free(&r->acknowledged)
        && atomic_is_lock_free(&r->overflow) && atomic_is_lock_free(&r->dropped)
        && atomic_is_lock_free(&r->stale) && atomic_is_lock_free(&r->underrun)
        && atomic_is_lock_free(&r->idle) && atomic_is_lock_free(&r->invalid_silence)
        && atomic_is_lock_free(&r->cleared)
        && atomic_is_lock_free(&r->high_water);
}

NVTRing *nvt_ring_create(size_t capacity, uint64_t token) {
    if (!capacity || capacity > UINT32_MAX || capacity > SIZE_MAX / sizeof(NVTSlot) || !token)
        return NULL;
    NVTRing *r = calloc(1, sizeof(*r));
    if (!r) return NULL;
    r->capacity = capacity;
    r->slots = calloc(capacity, sizeof(*r->slots));
    atomic_init(&r->read_index, 0); atomic_init(&r->write_index, 0);
    atomic_init(&r->active, token); atomic_init(&r->acknowledged, token);
    atomic_init(&r->overflow, 0); atomic_init(&r->dropped, 0);
    atomic_init(&r->stale, 0); atomic_init(&r->underrun, 0);
    atomic_init(&r->idle, 0); atomic_init(&r->invalid_silence, 0); atomic_init(&r->cleared, 0);
    atomic_init(&r->high_water, 0);
    if (!r->slots || !nvt_ring_atomics_lock_free(r)) {
        nvt_ring_destroy(r); return NULL;
    }
    return r;
}
void nvt_ring_destroy(NVTRing *r) {
    if (r) { free(r->slots); free(r); }
}
uint64_t nvt_ring_active_token(const NVTRing *r) { return load(&r->active); }
bool nvt_ring_invalidate(NVTRing *r, uint64_t token) {
    if (token <= load(&r->active)) return false;
    atomic_store_explicit(&r->active, token, memory_order_release);
    return true;
}

NVTWriteStatus nvt_ring_write(NVTRing *r, const float *samples, size_t count,
                             NVTStamp stamp, uint64_t token) {
    if (!samples || !count || count > UINT32_MAX
        || ((stamp.flags & NVT_SAMPLE_TIME_VALID) && stamp.sample_time > INT64_MAX - (int64_t)count))
        return NVT_WRITE_INVALID;
    if (token != load(&r->active)) {
        add(&r->stale, count); add(&r->dropped, count); return NVT_WRITE_STALE;
    }
    if (token != load(&r->acknowledged)) {
        add(&r->dropped, count); return NVT_WRITE_AWAITING_CLEAR;
    }
    uint64_t write = load(&r->write_index), read = load(&r->read_index);
    // Refuse cursor exhaustion rather than silently wrapping absolute positions.
    if (count > r->capacity || write > UINT64_MAX - count || write - read > r->capacity - count) {
        add(&r->overflow, 1); add(&r->dropped, count); return NVT_WRITE_FULL;
    }
    for (size_t i = 0; i < count; ++i) {
        r->slots[(write + i) % r->capacity] = (NVTSlot) {
            .frame = { .sample = samples[i], .offset = (uint32_t)i, .origin = stamp },
            .token = token
        };
    }
    // Publication still occurs if clear raced the copy. Tags make it unconsumable.
    NVT_HOOK(1);
    atomic_store_explicit(&r->write_index, write + count, memory_order_release);
    uint64_t water = write + count - read;
    if (water > load(&r->high_water))
        atomic_store_explicit(&r->high_water, water, memory_order_relaxed);
    if (token != load(&r->active)) {
        add(&r->dropped, count); return NVT_WRITE_STALE;
    }
    return NVT_WRITE_OK;
}

uint64_t nvt_ring_consumer_sync(NVTRing *r) {
    uint64_t token = load(&r->active);
    if (token != load(&r->acknowledged)) {
        uint64_t read = load(&r->read_index), write = load(&r->write_index);
        add(&r->cleared, write - read);
        atomic_store_explicit(&r->read_index, write, memory_order_release);
        atomic_store_explicit(&r->acknowledged, token, memory_order_release);
    }
    return token;
}

NVTReadResult nvt_ring_read(NVTRing *r, float *samples, NVTFrame *frames,
                            size_t count, bool fill_silence, bool expected_audio) {
    NVTReadResult result = { .token = nvt_ring_consumer_sync(r) };
    uint64_t read = load(&r->read_index), write = load(&r->write_index);
    while (read < write && result.copied < count) {
        NVTSlot slot = r->slots[read % r->capacity];
        ++read;
        if (slot.token != result.token) { add(&r->stale, 1); continue; }
        samples[result.copied] = slot.frame.sample;
        if (frames) frames[result.copied] = slot.frame;
        ++result.copied;
    }
    atomic_store_explicit(&r->read_index, read, memory_order_release);
    NVT_HOOK(2);
    if (result.token != load(&r->active)) {
        result.invalidated = true;
        add(&r->cleared, result.copied);
        result.copied = 0;
    }
    if (fill_silence) {
        result.silence = count - result.copied;
        if (result.silence) memset(samples + result.copied, 0, result.silence * sizeof(float));
        NVTCounter *silence = result.invalidated ? &r->invalid_silence
            : (expected_audio ? &r->underrun : &r->idle);
        add(silence, result.silence);
    }
    return result;
}

NVTRingStats nvt_ring_stats(const NVTRing *r) {
    uint64_t read = load(&r->read_index), write = load(&r->write_index);
    uint64_t water = write >= read ? write - read : 0;
    return (NVTRingStats) {
        .overflow_events = load(&r->overflow), .dropped_frames = load(&r->dropped),
        .stale_frames = load(&r->stale), .underrun_frames = load(&r->underrun),
        .idle_silence_frames = load(&r->idle), .invalidated_silence_frames = load(&r->invalid_silence),
        .clear_discarded_frames = load(&r->cleared),
        .water_frames = water > r->capacity ? r->capacity : water,
        .high_water_frames = load(&r->high_water),
        .active_token = load(&r->active), .acknowledged_token = load(&r->acknowledged)
    };
}
