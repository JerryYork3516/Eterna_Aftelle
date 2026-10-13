#ifndef VP_RECORDER_H
#define VP_RECORDER_H

#include <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VP_SCHEMA_VERSION 1u
#define VP_MAX_SECONDS 60u
#define VP_MAX_PCM_BYTES (64ull * 1024ull * 1024ull)
#define VP_MAX_RESIDENT_BYTES (8ull * 1024ull * 1024ull)
#define VP_SLOT_BYTES (128u * 1024u)
#define VP_SLOT_COUNT 32u
#define VP_MAX_BUFFERS 32u

enum {
    VP_STREAM_INPUT = 1,
    VP_STREAM_RENDER = 2
};

enum {
    VP_INVALID_NONE = 0,
    VP_INVALID_TIME = 1u << 0,
    VP_INVALID_BYTE_LIMIT = 1u << 1,
    VP_INVALID_OVERFLOW = 1u << 2,
    VP_INVALID_CONTENTION = 1u << 3,
    VP_INVALID_FORMAT = 1u << 4,
    VP_INVALID_DISCONTINUITY = 1u << 5,
    VP_INVALID_LAYOUT = 1u << 6,
    VP_INVALID_WRITE = 1u << 7,
    VP_INVALID_ABORT = 1u << 8,
    VP_INVALID_CLOCK = 1u << 9
};

typedef struct VPRecorder VPRecorder;

typedef struct {
    uint32_t schema_version;
    uint32_t maximum_seconds;
    uint64_t maximum_pcm_bytes;
    bool fixture_mode;
    bool fixture_pause_writer;
    uint64_t fixture_write_failure_after_bytes;
    bool fixture_evidence_sync_failure;
} VPRecorderConfig;

typedef struct {
    uint32_t stream_kind;
    uint32_t frame_count;
    AudioStreamBasicDescription format;
    bool sample_time_valid;
    bool host_time_valid;
    int64_t sample_time;
    /* Raw AVAudioTime hostTime; its clock domain is separate from continuous ticks. */
    uint64_t host_time;
    /* mach_continuous_time at callback entry, including elapsed system sleep. */
    uint64_t callback_enter_tick;
    bool source_range_valid;
    int64_t source_start_frame;
    uint64_t source_frame_count;
} VPFrameIdentity;

typedef struct {
    uint32_t schema_version;
    uint32_t invalid_reasons;
    bool armed;
    bool accepting;
    bool sealed;
    bool writer_failure;
    uint64_t reserved_records;
    uint64_t written_records;
    uint64_t lost_records;
    uint64_t overflow_records;
    uint64_t suppressed_records;
    uint64_t discarded_records;
    uint64_t pending_records;
    uint64_t reserved_pcm_bytes;
    uint64_t written_pcm_bytes;
    uint64_t input_written_records;
    uint64_t input_written_frames;
    uint64_t render_written_records;
    uint64_t render_written_frames;
    uint64_t missing_sample_time_records;
    uint64_t missing_host_time_records;
    uint64_t continuity_unknown_records;
    uint64_t resident_bytes;
    uint64_t first_callback_tick;
    uint64_t last_callback_tick;
} VPRecorderSnapshot;

typedef struct {
    uint32_t schema_version;
    bool complete;
    bool checksum_matches;
    uint32_t invalid_reasons;
    uint64_t record_count;
    uint64_t pcm_bytes;
    uint64_t resident_bytes;
} VPFileValidation;

VPRecorderConfig vp_recorder_default_config(void);
uint64_t vp_recorder_resident_bytes(void);
/* mach_continuous_time domain for arm, deadline and callback-entry budgets.
 * Uses mach_timebase_info units and includes sleep; never rewrites raw hostTime. */
uint64_t vp_recorder_now_tick(void);
uint64_t vp_recorder_ticks_for_seconds(uint32_t seconds);

/* Control thread only. Creates a NEW 0700 directory and a 0600 evidence.vp0 file.
 * Existing paths and final symlinks are rejected; audio remains unarmed. */
VPRecorder *vp_recorder_create(const char *new_directory,
                              const VPRecorderConfig *config, int *error_code);
bool vp_recorder_arm(VPRecorder *recorder, uint64_t start_tick);

/* Callback safe: bounded copy, lock-free atomics and one non-waiting admission token.
 * No allocation, file IO, encoding or worker creation. Rejection never changes
 * an AVAudioEngine lifecycle. Identity and AudioBufferList remain caller-owned. */
bool vp_recorder_submit(VPRecorder *recorder, const VPFrameIdentity *identity,
                        const AudioBufferList *buffers);

/* Offline fixtures only, rejected unless fixture_mode was set at creation. */
bool vp_recorder_submit_synthetic(VPRecorder *recorder,
                                  const VPFrameIdentity *identity,
                                  const void *bytes, uint32_t byte_count);
bool vp_recorder_fixture_pause_writer(VPRecorder *recorder, bool pause);
/* Fixture control only. A successful hold must be released before seal/destroy. */
bool vp_recorder_fixture_hold_admission(VPRecorder *recorder, bool hold);

VPRecorderSnapshot vp_recorder_snapshot(const VPRecorder *recorder);
void vp_recorder_invalidate(VPRecorder *recorder, uint32_t reason);

/* Control thread only. Stops admission, waits for any admitted callback, drains
 * and joins the writer, writes/fyncs a footer and private seal receipt, then
 * forbids further writing. Missing/failed receipts cannot validate complete.
 * Call after taps are removed; concurrent rejection is safe while owner lives. */
bool vp_recorder_seal(VPRecorder *recorder);

/* Offline control thread only; validates fixed records, footer, counts and hash.
 * A missing footer, truncation or post-footer bytes can never be complete. */
VPFileValidation vp_recorder_validate_file(const char *file_path);
bool vp_recorder_read_identity(const char *file_path, uint64_t record_index,
                              VPFrameIdentity *identity, uint32_t *buffer_count,
                              uint64_t *pcm_bytes);

/* Owner must first remove taps/stop audio, prevent new calls and join the writer.
 * Destroy itself does not free memory still held by an audio callback. */
void vp_recorder_destroy(VPRecorder *recorder);

#ifdef __cplusplus
}
#endif
#endif
