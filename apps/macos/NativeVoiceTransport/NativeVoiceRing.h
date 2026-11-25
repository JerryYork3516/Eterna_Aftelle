#ifndef NATIVE_VOICE_RING_H
#define NATIVE_VOICE_RING_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct NVTRing NVTRing;
enum { NVT_SAMPLE_TIME_VALID = 1, NVT_HOST_TIME_VALID = 2 };
typedef struct {
    int64_t sample_time;
    uint64_t host_time_ns;
    uint32_t flags;
} NVTStamp;
typedef struct {
    double raw_sample_time;
    uint64_t raw_host_time;
    uint64_t configuration_id;
    uint64_t dropped_before;
    uint32_t raw_flags, callback_frames;
} NVTIngress;
typedef struct {
    float sample;
    uint32_t offset;
    NVTStamp origin;
    NVTIngress ingress;
} NVTFrame;
typedef enum {
    NVT_WRITE_OK, NVT_WRITE_STALE, NVT_WRITE_AWAITING_CLEAR,
    NVT_WRITE_FULL, NVT_WRITE_INVALID
} NVTWriteStatus;
typedef struct {
    size_t copied;
    size_t silence;
    uint64_t token;
    bool invalidated;
    bool reached_end;
} NVTReadResult;
typedef struct {
    uint64_t overflow_events, dropped_frames, stale_frames;
    uint64_t underrun_frames, idle_silence_frames, invalidated_silence_frames, clear_discarded_frames;
    uint64_t water_frames, high_water_frames, active_token, acknowledged_token;
} NVTRingStats;

// Create/destroy only while both endpoints are stopped. Storage is preallocated.
NVTRing *nvt_ring_create(size_t capacity_frames, uint64_t initial_token);
void nvt_ring_destroy(NVTRing *ring);
bool nvt_ring_atomics_lock_free(const NVTRing *ring);
// One serialized control owner; strictly increasing tokens, never reuse/wrap.
// Bind each token to the full external generation/route/configuration identity.
bool nvt_ring_invalidate(NVTRing *ring, uint64_t next_token);
uint64_t nvt_ring_active_token(const NVTRing *ring);
uint64_t nvt_ring_acknowledged_token(const NVTRing *ring);
size_t nvt_ring_write_space(const NVTRing *ring, uint64_t token);
// Sole producer. All-or-nothing; new-token writes wait for consumer acknowledgement.
NVTWriteStatus nvt_ring_write(NVTRing *ring, const float *samples, size_t count,
                             NVTStamp stamp, uint64_t token);
NVTWriteStatus nvt_ring_write_capture(NVTRing *ring, const float *samples, size_t count,
                                     NVTStamp stamp, NVTIngress ingress, uint64_t token);
// Commit the last samples and EOS together. An empty tail is legal.
NVTWriteStatus nvt_ring_write_end(NVTRing *ring, const float *samples, size_t count, uint64_t token);
// Sole consumer. O(1) logical flush; control never writes either cursor.
uint64_t nvt_ring_consumer_sync(NVTRing *ring);
// Work bounded by capacity + count; no allocation, locks, waiting, or SRC.
// Capture: fill_silence=false. Playback: true; expected_audio distinguishes idle.
// frames may be NULL for playback; samples must hold count floats.
NVTReadResult nvt_ring_read(NVTRing *ring, float *samples, NVTFrame *frames,
                            size_t count, bool fill_silence, bool expected_audio);
// A callback that began before a clear can acknowledge it, but cannot read its successor.
NVTReadResult nvt_ring_read_for_token(NVTRing *ring, float *samples, size_t count, uint64_t token);
// Approximate concurrent telemetry, never a correctness/clear-completion fence.
NVTRingStats nvt_ring_stats(const NVTRing *ring);

#endif
