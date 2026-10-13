#include "VPRecorder.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define VP_FILE_MAGIC UINT64_C(0x3152434552505656)
#define VP_RECORD_MAGIC UINT32_C(0x31524356)
#define VP_FOOTER_MAGIC UINT64_C(0x314c414553505656)
#define VP_RECEIPT_MAGIC UINT64_C(0x3154494543505656)
#define VP_WRITER_STACK (256u * 1024u)
#define VP_WRITER_GUARD 4096u
#define VP_FNV_OFFSET UINT64_C(14695981039346656037)
#define VP_FNV_PRIME UINT64_C(1099511628211)

enum {
    VP_ADMISSION_UNARMED = 0,
    VP_ADMISSION_OPEN = 1,
    VP_ADMISSION_CLOSED = 2
};

typedef struct {
    uint64_t magic;
    uint32_t schema_version;
    uint32_t header_bytes;
    uint32_t record_header_bytes;
    uint32_t footer_bytes;
    uint32_t maximum_seconds;
    uint32_t native_byte_order;
    uint64_t maximum_pcm_bytes;
    uint64_t resident_bytes;
    uint64_t start_tick;
} VPFileHeader;

typedef struct {
    uint32_t channels;
    uint32_t bytes;
} VPBufferLayout;

typedef struct {
    uint32_t magic;
    uint32_t schema_version;
    uint32_t header_bytes;
    uint32_t stream_kind;
    uint64_t sequence;
    uint32_t frame_count;
    uint32_t payload_bytes;
    AudioStreamBasicDescription format;
    uint32_t sample_time_valid;
    uint32_t host_time_valid;
    int64_t sample_time;
    uint64_t host_time;
    uint64_t callback_enter_tick;
    uint32_t source_range_valid;
    uint32_t continuity_known;
    int64_t source_start_frame;
    uint64_t source_frame_count;
    uint32_t buffer_count;
    uint32_t reserved;
    VPBufferLayout buffers[VP_MAX_BUFFERS];
} VPRecordHeader;

typedef struct {
    uint64_t magic;
    uint32_t schema_version;
    uint32_t footer_bytes;
    uint64_t checksum;
    VPRecorderSnapshot snapshot;
} VPFileFooter;

typedef struct {
    uint64_t magic;
    uint32_t schema_version;
    uint32_t receipt_bytes;
    uint64_t checksum;
    uint64_t file_bytes;
    uint64_t record_count;
    uint64_t pcm_bytes;
} VPSealReceipt;

typedef struct {
    VPRecordHeader header;
    unsigned char payload[VP_SLOT_BYTES];
} VPSlot;

typedef struct {
    bool seen;
    bool sample_valid;
    int64_t next_sample;
    AudioStreamBasicDescription format;
    uint32_t buffer_count;
    uint32_t channels[VP_MAX_BUFFERS];
} VPStreamState;

struct VPRecorder {
    VPRecorderConfig config;
    int descriptor;
    int directory_descriptor;
    pthread_t writer;
    bool writer_started;
    bool writer_joined;
    atomic_flag admission;
    _Atomic bool armed;
    _Atomic uint32_t admission_state;
    _Atomic bool finish_requested;
    _Atomic bool seal_started;
    _Atomic bool sealed;
    _Atomic bool writer_failure;
    _Atomic bool pause_writer;
    _Atomic uint32_t invalid_reasons;
    _Atomic uint32_t active_callbacks;
    _Atomic uint64_t write_index;
    _Atomic uint64_t read_index;
    _Atomic uint64_t written_records;
    _Atomic uint64_t lost_records;
    _Atomic uint64_t overflow_records;
    _Atomic uint64_t suppressed_records;
    _Atomic uint64_t discarded_records;
    _Atomic uint64_t reserved_pcm_bytes;
    _Atomic uint64_t written_pcm_bytes;
    _Atomic uint64_t stream_written_records[2];
    _Atomic uint64_t stream_written_frames[2];
    _Atomic uint64_t missing_sample_time_records;
    _Atomic uint64_t missing_host_time_records;
    _Atomic uint64_t continuity_unknown_records;
    _Atomic uint64_t first_callback_tick;
    _Atomic uint64_t last_callback_tick;
    uint64_t start_tick;
    uint64_t maximum_ticks;
    uint64_t checksum;
    uint64_t disk_bytes;
    VPStreamState streams[2];
    VPSlot slots[VP_SLOT_COUNT];
};

_Static_assert(sizeof(VPRecorder) + VP_WRITER_STACK + VP_WRITER_GUARD
               <= VP_MAX_RESIDENT_BYTES, "diagnostic resident budget exceeded");
_Static_assert(ATOMIC_BOOL_LOCK_FREE == 2 && ATOMIC_INT_LOCK_FREE == 2
               && ATOMIC_LONG_LOCK_FREE == 2 && ATOMIC_LLONG_LOCK_FREE == 2,
               "callback atomic types must always be lock free");

static void brief_wait(void) {
    const struct timespec delay = { .tv_sec = 0, .tv_nsec = 1000000 };
    nanosleep(&delay, NULL);
}

uint64_t vp_recorder_resident_bytes(void) {
    return sizeof(VPRecorder) + VP_WRITER_STACK + VP_WRITER_GUARD;
}

uint64_t vp_recorder_now_tick(void) {
    return mach_continuous_time();
}

uint64_t vp_recorder_ticks_for_seconds(uint32_t seconds) {
    mach_timebase_info_data_t timebase = {0};
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.numer == 0) {
        return 0;
    }
    return (uint64_t)seconds * UINT64_C(1000000000) * timebase.denom / timebase.numer;
}

VPRecorderConfig vp_recorder_default_config(void) {
    VPRecorderConfig config = {0};
    config.schema_version = VP_SCHEMA_VERSION;
    config.maximum_seconds = VP_MAX_SECONDS;
    config.maximum_pcm_bytes = VP_MAX_PCM_BYTES;
    return config;
}

static uint64_t hash_bytes(uint64_t hash, const void *bytes, size_t count) {
    const unsigned char *source = bytes;
    for (size_t index = 0; index < count; ++index) {
        hash = (hash ^ source[index]) * VP_FNV_PRIME;
    }
    return hash;
}

static void fail(VPRecorder *recorder, uint32_t reason) {
    atomic_store_explicit(&recorder->admission_state, VP_ADMISSION_CLOSED, memory_order_release);
    atomic_fetch_or_explicit(&recorder->invalid_reasons, reason, memory_order_relaxed);
}

void vp_recorder_invalidate(VPRecorder *recorder, uint32_t reason) {
    if (recorder == NULL) {
        return;
    }
    atomic_fetch_add_explicit(&recorder->active_callbacks, 1, memory_order_seq_cst);
    if (!atomic_load_explicit(&recorder->seal_started, memory_order_seq_cst)) {
        fail(recorder, reason);
    }
    atomic_fetch_sub_explicit(&recorder->active_callbacks, 1, memory_order_seq_cst);
}

VPRecorderSnapshot vp_recorder_snapshot(const VPRecorder *recorder) {
    VPRecorderSnapshot snapshot = {0};
    snapshot.schema_version = VP_SCHEMA_VERSION;
    snapshot.resident_bytes = vp_recorder_resident_bytes();
    if (recorder == NULL) {
        snapshot.invalid_reasons = VP_INVALID_ABORT;
        return snapshot;
    }
    snapshot.invalid_reasons = atomic_load(&recorder->invalid_reasons);
    snapshot.armed = atomic_load(&recorder->armed);
    snapshot.accepting = atomic_load(&recorder->admission_state) == VP_ADMISSION_OPEN;
    snapshot.sealed = atomic_load(&recorder->sealed);
    snapshot.writer_failure = atomic_load(&recorder->writer_failure);
    snapshot.discarded_records = atomic_load(&recorder->discarded_records);
    snapshot.written_records = atomic_load(&recorder->written_records);
    snapshot.reserved_records = atomic_load(&recorder->write_index);
    snapshot.lost_records = atomic_load(&recorder->lost_records);
    snapshot.overflow_records = atomic_load(&recorder->overflow_records);
    snapshot.suppressed_records = atomic_load(&recorder->suppressed_records);
    snapshot.pending_records = snapshot.reserved_records - snapshot.written_records
        - snapshot.discarded_records;
    snapshot.reserved_pcm_bytes = atomic_load(&recorder->reserved_pcm_bytes);
    snapshot.written_pcm_bytes = atomic_load(&recorder->written_pcm_bytes);
    snapshot.input_written_records = atomic_load(&recorder->stream_written_records[0]);
    snapshot.input_written_frames = atomic_load(&recorder->stream_written_frames[0]);
    snapshot.render_written_records = atomic_load(&recorder->stream_written_records[1]);
    snapshot.render_written_frames = atomic_load(&recorder->stream_written_frames[1]);
    snapshot.missing_sample_time_records = atomic_load(&recorder->missing_sample_time_records);
    snapshot.missing_host_time_records = atomic_load(&recorder->missing_host_time_records);
    snapshot.continuity_unknown_records = atomic_load(&recorder->continuity_unknown_records);
    snapshot.first_callback_tick = atomic_load(&recorder->first_callback_tick);
    snapshot.last_callback_tick = atomic_load(&recorder->last_callback_tick);
    return snapshot;
}

static bool write_all(VPRecorder *recorder, const void *bytes, size_t count, bool checksum) {
    if (recorder->config.fixture_mode
        && recorder->config.fixture_write_failure_after_bytes != 0
        && (recorder->disk_bytes > recorder->config.fixture_write_failure_after_bytes
            || count > recorder->config.fixture_write_failure_after_bytes - recorder->disk_bytes)) {
        errno = EIO;
        return false;
    }
    const unsigned char *source = bytes;
    size_t offset = 0;
    while (offset < count) {
        ssize_t result = write(recorder->descriptor, source + offset, count - offset);
        if (result < 0 && errno == EINTR) {
            continue;
        }
        if (result <= 0) {
            return false;
        }
        offset += (size_t)result;
    }
    if (checksum) {
        recorder->checksum = hash_bytes(recorder->checksum, bytes, count);
    }
    recorder->disk_bytes += count;
    return true;
}

static void writer_failed(VPRecorder *recorder) {
    atomic_store(&recorder->writer_failure, true);
    fail(recorder, VP_INVALID_WRITE);
}

static bool write_receipt(VPRecorder *recorder) {
    VPSealReceipt receipt = {0};
    receipt.magic = VP_RECEIPT_MAGIC;
    receipt.schema_version = VP_SCHEMA_VERSION;
    receipt.receipt_bytes = sizeof(receipt);
    receipt.checksum = recorder->checksum;
    receipt.file_bytes = recorder->disk_bytes;
    receipt.record_count = atomic_load(&recorder->written_records);
    receipt.pcm_bytes = atomic_load(&recorder->written_pcm_bytes);
    int descriptor = openat(recorder->directory_descriptor, "evidence.vp0.seal.tmp",
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR);
    if (descriptor < 0) {
        return false;
    }
    ssize_t count;
    do {
        count = write(descriptor, &receipt, sizeof(receipt));
    } while (count < 0 && errno == EINTR);
    bool success = count == sizeof(receipt) && fsync(descriptor) == 0;
    bool published = false;
    close(descriptor);
    if (success) {
        success = renameatx_np(recorder->directory_descriptor, "evidence.vp0.seal.tmp",
                              recorder->directory_descriptor, "evidence.vp0.seal", RENAME_EXCL) == 0;
        published = success;
    }
    if (success) {
        success = fsync(recorder->directory_descriptor) == 0;
    }
    if (!success) {
        unlinkat(recorder->directory_descriptor, "evidence.vp0.seal.tmp", 0);
        if (published) {
            unlinkat(recorder->directory_descriptor, "evidence.vp0.seal", 0);
        }
    }
    return success;
}

static void *writer_main(void *context) {
    VPRecorder *recorder = context;
    VPFileHeader header = {0};
    header.magic = VP_FILE_MAGIC;
    header.schema_version = VP_SCHEMA_VERSION;
    header.header_bytes = sizeof(header);
    header.record_header_bytes = sizeof(VPRecordHeader);
    header.footer_bytes = sizeof(VPFileFooter);
    header.maximum_seconds = recorder->config.maximum_seconds;
    header.native_byte_order = UINT32_C(0x01020304);
    header.maximum_pcm_bytes = recorder->config.maximum_pcm_bytes;
    header.resident_bytes = vp_recorder_resident_bytes();
    header.start_tick = recorder->start_tick;
    if (!write_all(recorder, &header, sizeof(header), true)) {
        writer_failed(recorder);
    }
    for (;;) {
        uint64_t read_index = atomic_load_explicit(&recorder->read_index, memory_order_relaxed);
        uint64_t write_index = atomic_load_explicit(&recorder->write_index, memory_order_acquire);
        if (read_index < write_index && !atomic_load(&recorder->pause_writer)) {
            VPSlot *slot = &recorder->slots[read_index % VP_SLOT_COUNT];
            if (!atomic_load(&recorder->writer_failure)) {
                bool success = write_all(recorder, &slot->header, sizeof(slot->header), true)
                    && write_all(recorder, slot->payload, slot->header.payload_bytes, true);
                if (success) {
                    atomic_fetch_add(&recorder->written_records, 1);
                    atomic_fetch_add(&recorder->written_pcm_bytes, slot->header.payload_bytes);
                    uint32_t stream_index = slot->header.stream_kind - 1;
                    atomic_fetch_add(&recorder->stream_written_records[stream_index], 1);
                    atomic_fetch_add(&recorder->stream_written_frames[stream_index], slot->header.frame_count);
                } else {
                    writer_failed(recorder);
                    atomic_fetch_add(&recorder->discarded_records, 1);
                }
            } else {
                atomic_fetch_add(&recorder->discarded_records, 1);
            }
            atomic_store_explicit(&recorder->read_index, read_index + 1, memory_order_release);
            continue;
        }
        if (atomic_load_explicit(&recorder->finish_requested, memory_order_acquire)
            && read_index == write_index) {
            break;
        }
        brief_wait();
    }
    if (!atomic_load(&recorder->writer_failure)) {
        VPFileFooter footer = {0};
        footer.magic = VP_FOOTER_MAGIC;
        footer.schema_version = VP_SCHEMA_VERSION;
        footer.footer_bytes = sizeof(footer);
        footer.checksum = recorder->checksum;
        footer.snapshot = vp_recorder_snapshot(recorder);
        footer.snapshot.sealed = true;
        footer.snapshot.accepting = false;
        bool footer_written = write_all(recorder, &footer, sizeof(footer), false);
        if (footer_written) {
            recorder->checksum = hash_bytes(recorder->checksum, &footer, sizeof(footer));
        }
        if (!footer_written
            || (recorder->config.fixture_mode && recorder->config.fixture_evidence_sync_failure)
            || fsync(recorder->descriptor) != 0 || !write_receipt(recorder)) {
            writer_failed(recorder);
        }
    }
    close(recorder->descriptor);
    recorder->descriptor = -1;
    close(recorder->directory_descriptor);
    recorder->directory_descriptor = -1;
    return NULL;
}

VPRecorder *vp_recorder_create(const char *new_directory,
                              const VPRecorderConfig *config, int *error_code) {
    if (error_code != NULL) {
        *error_code = 0;
    }
    if (new_directory == NULL || config == NULL || new_directory[0] != '/'
        || config->schema_version != VP_SCHEMA_VERSION || config->maximum_seconds == 0
        || config->maximum_seconds > VP_MAX_SECONDS || config->maximum_pcm_bytes == 0
        || config->maximum_pcm_bytes > VP_MAX_PCM_BYTES
        || (!config->fixture_mode && (config->fixture_pause_writer
            || config->fixture_write_failure_after_bytes != 0
            || config->fixture_evidence_sync_failure))) {
        if (error_code != NULL) {
            *error_code = EINVAL;
        }
        return NULL;
    }
    VPRecorder *recorder = calloc(1, sizeof(*recorder));
    if (recorder == NULL) {
        if (error_code != NULL) {
            *error_code = ENOMEM;
        }
        return NULL;
    }
    recorder->config = *config;
    recorder->descriptor = -1;
    recorder->directory_descriptor = -1;
    recorder->checksum = VP_FNV_OFFSET;
    atomic_flag_clear(&recorder->admission);
    atomic_init(&recorder->armed, false);
    atomic_init(&recorder->admission_state, VP_ADMISSION_UNARMED);
    atomic_init(&recorder->finish_requested, false);
    atomic_init(&recorder->seal_started, false);
    atomic_init(&recorder->sealed, false);
    atomic_init(&recorder->writer_failure, false);
    atomic_init(&recorder->pause_writer, config->fixture_pause_writer);
    atomic_init(&recorder->invalid_reasons, 0);
    atomic_init(&recorder->active_callbacks, 0);
    atomic_init(&recorder->write_index, 0);
    atomic_init(&recorder->read_index, 0);
    atomic_init(&recorder->written_records, 0);
    atomic_init(&recorder->lost_records, 0);
    atomic_init(&recorder->overflow_records, 0);
    atomic_init(&recorder->suppressed_records, 0);
    atomic_init(&recorder->discarded_records, 0);
    atomic_init(&recorder->reserved_pcm_bytes, 0);
    atomic_init(&recorder->written_pcm_bytes, 0);
    for (uint32_t index = 0; index < 2; ++index) {
        atomic_init(&recorder->stream_written_records[index], 0);
        atomic_init(&recorder->stream_written_frames[index], 0);
    }
    atomic_init(&recorder->missing_sample_time_records, 0);
    atomic_init(&recorder->missing_host_time_records, 0);
    atomic_init(&recorder->continuity_unknown_records, 0);
    atomic_init(&recorder->first_callback_tick, 0);
    atomic_init(&recorder->last_callback_tick, 0);
    if (!atomic_is_lock_free(&recorder->write_index)
        || !atomic_is_lock_free(&recorder->invalid_reasons)
        || !atomic_is_lock_free(&recorder->admission_state)) {
        if (error_code != NULL) {
            *error_code = ENOTSUP;
        }
        free(recorder);
        return NULL;
    }
    if (mkdir(new_directory, S_IRWXU) != 0) {
        if (error_code != NULL) {
            *error_code = errno;
        }
        free(recorder);
        return NULL;
    }
    int directory = open(new_directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory < 0) {
        if (error_code != NULL) {
            *error_code = errno;
        }
        free(recorder);
        return NULL;
    }
    recorder->descriptor = openat(directory, "evidence.vp0",
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR);
    int creation_error = errno;
    if (recorder->descriptor < 0) {
        if (error_code != NULL) {
            *error_code = creation_error;
        }
        free(recorder);
        close(directory);
        return NULL;
    }
    recorder->directory_descriptor = directory;
    return recorder;
}

bool vp_recorder_arm(VPRecorder *recorder, uint64_t start_tick) {
    if (recorder == NULL || atomic_load(&recorder->armed)
        || atomic_load(&recorder->sealed) || atomic_load(&recorder->seal_started)
        || atomic_load(&recorder->invalid_reasons) != 0
        || atomic_load(&recorder->admission_state) != VP_ADMISSION_UNARMED) {
        return false;
    }
    if (start_tick == 0) {
        fail(recorder, VP_INVALID_CLOCK);
        return false;
    }
    recorder->maximum_ticks = vp_recorder_ticks_for_seconds(recorder->config.maximum_seconds);
    if (recorder->maximum_ticks == 0) {
        fail(recorder, VP_INVALID_CLOCK);
        return false;
    }
    recorder->start_tick = start_tick;
    pthread_attr_t attributes;
    int result = pthread_attr_init(&attributes);
    if (result == 0) {
        result = pthread_attr_setstacksize(&attributes, VP_WRITER_STACK);
        if (result == 0) {
            result = pthread_attr_setguardsize(&attributes, VP_WRITER_GUARD);
        }
        if (result == 0) {
            uint32_t expected = VP_ADMISSION_UNARMED;
            if (!atomic_compare_exchange_strong(&recorder->admission_state,
                                                &expected, VP_ADMISSION_OPEN)) {
                pthread_attr_destroy(&attributes);
                return false;
            }
            atomic_store(&recorder->armed, true);
            result = pthread_create(&recorder->writer, &attributes, writer_main, recorder);
        }
        pthread_attr_destroy(&attributes);
    }
    if (result != 0) {
        fail(recorder, VP_INVALID_WRITE);
        atomic_store(&recorder->writer_failure, true);
        return false;
    }
    recorder->writer_started = true;
    return atomic_load(&recorder->admission_state) == VP_ADMISSION_OPEN;
}

static bool same_format(const AudioStreamBasicDescription *left,
                        const AudioStreamBasicDescription *right) {
    return left->mSampleRate == right->mSampleRate && left->mFormatID == right->mFormatID
        && left->mFormatFlags == right->mFormatFlags
        && left->mBytesPerPacket == right->mBytesPerPacket
        && left->mFramesPerPacket == right->mFramesPerPacket
        && left->mBytesPerFrame == right->mBytesPerFrame
        && left->mChannelsPerFrame == right->mChannelsPerFrame
        && left->mBitsPerChannel == right->mBitsPerChannel;
}

static bool submit_locked(VPRecorder *recorder, const VPFrameIdentity *identity,
                          const AudioBufferList *buffers) {
    if (identity == NULL || buffers == NULL || identity->stream_kind < VP_STREAM_INPUT
        || identity->stream_kind > VP_STREAM_RENDER || identity->frame_count == 0
        || buffers->mNumberBuffers == 0 || buffers->mNumberBuffers > VP_MAX_BUFFERS) {
        fail(recorder, VP_INVALID_LAYOUT);
        return false;
    }
    uint64_t entered = identity->callback_enter_tick;
    if (entered < recorder->start_tick || entered - recorder->start_tick > recorder->maximum_ticks) {
        fail(recorder, entered < recorder->start_tick ? VP_INVALID_CLOCK : VP_INVALID_TIME);
        return false;
    }
    const AudioStreamBasicDescription *format = &identity->format;
    if (!isfinite(format->mSampleRate) || format->mSampleRate <= 0
        || format->mFormatID != kAudioFormatLinearPCM || format->mBytesPerFrame == 0
        || format->mChannelsPerFrame == 0 || format->mFramesPerPacket != 1
        || format->mBitsPerChannel == 0 || format->mBitsPerChannel > 64
        || format->mBytesPerPacket != format->mBytesPerFrame) {
        fail(recorder, VP_INVALID_FORMAT);
        return false;
    }
    uint64_t payload_bytes = 0;
    uint64_t channels = 0;
    bool planar = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if ((!planar && buffers->mNumberBuffers != 1)
        || (planar && buffers->mNumberBuffers != format->mChannelsPerFrame)) {
        fail(recorder, VP_INVALID_LAYOUT);
        return false;
    }
    for (uint32_t index = 0; index < buffers->mNumberBuffers; ++index) {
        const AudioBuffer *buffer = &buffers->mBuffers[index];
        uint64_t expected = (uint64_t)identity->frame_count * format->mBytesPerFrame;
        if (buffer->mData == NULL || buffer->mNumberChannels == 0
            || (planar && buffer->mNumberChannels != 1)
            || buffer->mDataByteSize != expected) {
            fail(recorder, VP_INVALID_LAYOUT);
            return false;
        }
        payload_bytes += buffer->mDataByteSize;
        channels += buffer->mNumberChannels;
    }
    if (channels != format->mChannelsPerFrame) {
        fail(recorder, VP_INVALID_LAYOUT);
        return false;
    }
    if (payload_bytes > VP_SLOT_BYTES) {
        atomic_fetch_add(&recorder->overflow_records, 1);
        fail(recorder, VP_INVALID_OVERFLOW);
        return false;
    }
    uint64_t reserved_bytes = atomic_load_explicit(&recorder->reserved_pcm_bytes, memory_order_relaxed);
    if (payload_bytes > recorder->config.maximum_pcm_bytes - reserved_bytes) {
        fail(recorder, VP_INVALID_BYTE_LIMIT);
        return false;
    }
    uint64_t write_index = atomic_load_explicit(&recorder->write_index, memory_order_relaxed);
    uint64_t read_index = atomic_load_explicit(&recorder->read_index, memory_order_acquire);
    if (write_index - read_index >= VP_SLOT_COUNT) {
        atomic_fetch_add(&recorder->overflow_records, 1);
        fail(recorder, VP_INVALID_OVERFLOW);
        return false;
    }
    VPStreamState *stream = &recorder->streams[identity->stream_kind - 1];
    if (stream->seen) {
        bool layout_matches = stream->buffer_count == buffers->mNumberBuffers;
        for (uint32_t index = 0; layout_matches && index < buffers->mNumberBuffers; ++index) {
            layout_matches = stream->channels[index] == buffers->mBuffers[index].mNumberChannels;
        }
        if (!same_format(&stream->format, format) || !layout_matches) {
            fail(recorder, VP_INVALID_FORMAT);
            return false;
        }
        if (stream->sample_valid && identity->sample_time_valid
            && identity->sample_time != stream->next_sample) {
            fail(recorder, VP_INVALID_DISCONTINUITY);
            return false;
        }
    }
    if (identity->sample_time_valid && identity->sample_time > INT64_MAX - identity->frame_count) {
        fail(recorder, VP_INVALID_DISCONTINUITY);
        return false;
    }
    VPSlot *slot = &recorder->slots[write_index % VP_SLOT_COUNT];
    VPRecordHeader *header = &slot->header;
    memset(header, 0, sizeof(*header));
    header->magic = VP_RECORD_MAGIC;
    header->schema_version = VP_SCHEMA_VERSION;
    header->header_bytes = sizeof(*header);
    header->stream_kind = identity->stream_kind;
    header->sequence = write_index;
    header->frame_count = identity->frame_count;
    header->payload_bytes = (uint32_t)payload_bytes;
    header->format = *format;
    header->format.mReserved = 0;
    header->sample_time_valid = identity->sample_time_valid;
    header->host_time_valid = identity->host_time_valid;
    header->sample_time = identity->sample_time;
    header->host_time = identity->host_time;
    header->callback_enter_tick = entered;
    header->source_range_valid = identity->source_range_valid;
    header->source_start_frame = identity->source_start_frame;
    header->source_frame_count = identity->source_frame_count;
    header->continuity_known = stream->seen && stream->sample_valid && identity->sample_time_valid;
    header->buffer_count = buffers->mNumberBuffers;
    size_t offset = 0;
    for (uint32_t index = 0; index < buffers->mNumberBuffers; ++index) {
        const AudioBuffer *buffer = &buffers->mBuffers[index];
        header->buffers[index].channels = buffer->mNumberChannels;
        header->buffers[index].bytes = buffer->mDataByteSize;
        memcpy(slot->payload + offset, buffer->mData, buffer->mDataByteSize);
        offset += buffer->mDataByteSize;
        stream->channels[index] = buffer->mNumberChannels;
    }
    if (!identity->sample_time_valid) {
        atomic_fetch_add(&recorder->missing_sample_time_records, 1);
    }
    if (!identity->host_time_valid) {
        atomic_fetch_add(&recorder->missing_host_time_records, 1);
    }
    if (!header->continuity_known) {
        atomic_fetch_add(&recorder->continuity_unknown_records, 1);
    }
    stream->seen = true;
    stream->format = *format;
    stream->buffer_count = buffers->mNumberBuffers;
    stream->sample_valid = identity->sample_time_valid;
    stream->next_sample = identity->sample_time_valid
        ? identity->sample_time + identity->frame_count : 0;
    if (write_index == 0) {
        atomic_store(&recorder->first_callback_tick, entered);
    }
    atomic_store(&recorder->last_callback_tick, entered);
    atomic_store(&recorder->reserved_pcm_bytes, reserved_bytes + payload_bytes);
    atomic_store_explicit(&recorder->write_index, write_index + 1, memory_order_release);
    return true;
}

bool vp_recorder_submit(VPRecorder *recorder, const VPFrameIdentity *identity,
                        const AudioBufferList *buffers) {
    if (recorder == NULL) {
        return false;
    }
    atomic_fetch_add_explicit(&recorder->active_callbacks, 1, memory_order_seq_cst);
    if (atomic_load_explicit(&recorder->seal_started, memory_order_seq_cst)
        || atomic_load_explicit(&recorder->admission_state, memory_order_acquire) != VP_ADMISSION_OPEN) {
        if (atomic_load(&recorder->armed) && !atomic_load(&recorder->seal_started)
            && !atomic_load(&recorder->sealed)) {
            atomic_fetch_add(&recorder->suppressed_records, 1);
            atomic_fetch_add(&recorder->lost_records, 1);
        }
        atomic_fetch_sub_explicit(&recorder->active_callbacks, 1, memory_order_seq_cst);
        return false;
    }
    if (atomic_flag_test_and_set_explicit(&recorder->admission, memory_order_acquire)) {
        atomic_fetch_add(&recorder->lost_records, 1);
        fail(recorder, VP_INVALID_CONTENTION);
        atomic_fetch_sub_explicit(&recorder->active_callbacks, 1, memory_order_seq_cst);
        return false;
    }
    bool accepted = false;
    if (atomic_load_explicit(&recorder->admission_state, memory_order_acquire) == VP_ADMISSION_OPEN) {
        accepted = submit_locked(recorder, identity, buffers);
        if (!accepted) {
            atomic_fetch_add(&recorder->lost_records, 1);
        }
    } else if (!atomic_load(&recorder->seal_started)) {
        atomic_fetch_add(&recorder->suppressed_records, 1);
        atomic_fetch_add(&recorder->lost_records, 1);
    }
    atomic_flag_clear_explicit(&recorder->admission, memory_order_release);
    atomic_fetch_sub_explicit(&recorder->active_callbacks, 1, memory_order_seq_cst);
    return accepted;
}

bool vp_recorder_submit_synthetic(VPRecorder *recorder,
                                  const VPFrameIdentity *identity,
                                  const void *bytes, uint32_t byte_count) {
    if (recorder == NULL || !recorder->config.fixture_mode || identity == NULL) {
        return false;
    }
    AudioBufferList buffers = {0};
    buffers.mNumberBuffers = 1;
    buffers.mBuffers[0].mNumberChannels = identity->format.mChannelsPerFrame;
    buffers.mBuffers[0].mDataByteSize = byte_count;
    buffers.mBuffers[0].mData = (void *)bytes;
    return vp_recorder_submit(recorder, identity, &buffers);
}

bool vp_recorder_fixture_pause_writer(VPRecorder *recorder, bool pause) {
    if (recorder == NULL || !recorder->config.fixture_mode || atomic_load(&recorder->sealed)) {
        return false;
    }
    atomic_store(&recorder->pause_writer, pause);
    return true;
}

bool vp_recorder_fixture_hold_admission(VPRecorder *recorder, bool hold) {
    if (recorder == NULL || !recorder->config.fixture_mode || atomic_load(&recorder->seal_started)) {
        return false;
    }
    if (hold) {
        return !atomic_flag_test_and_set_explicit(&recorder->admission, memory_order_acquire);
    }
    atomic_flag_clear_explicit(&recorder->admission, memory_order_release);
    return true;
}

bool vp_recorder_seal(VPRecorder *recorder) {
    if (recorder == NULL) {
        return false;
    }
    if (atomic_load(&recorder->sealed)) {
        return !atomic_load(&recorder->writer_failure);
    }
    atomic_store_explicit(&recorder->seal_started, true, memory_order_seq_cst);
    atomic_store_explicit(&recorder->admission_state, VP_ADMISSION_CLOSED, memory_order_release);
    /* The SC entry increment/closed check and close/active check share one total
     * order: an entry that observed open must finish before this sees zero;
     * an entry ordered later sees closed and cannot mutate sealed evidence. */
    while (atomic_load_explicit(&recorder->active_callbacks, memory_order_seq_cst) != 0) {
        brief_wait();
    }
    while (atomic_flag_test_and_set_explicit(&recorder->admission, memory_order_acquire)) {
        brief_wait();
    }
    atomic_flag_clear_explicit(&recorder->admission, memory_order_release);
    atomic_store(&recorder->pause_writer, false);
    atomic_store_explicit(&recorder->finish_requested, true, memory_order_release);
    if (recorder->writer_started && !recorder->writer_joined) {
        if (pthread_join(recorder->writer, NULL) != 0) {
            writer_failed(recorder);
            return false;
        }
        recorder->writer_joined = true;
    } else if (recorder->descriptor >= 0) {
        close(recorder->descriptor);
        recorder->descriptor = -1;
        close(recorder->directory_descriptor);
        recorder->directory_descriptor = -1;
        fail(recorder, VP_INVALID_ABORT);
    }
    atomic_store_explicit(&recorder->sealed, true, memory_order_release);
    return !atomic_load(&recorder->writer_failure);
}

static bool read_exact(int descriptor, void *bytes, size_t count) {
    unsigned char *destination = bytes;
    size_t offset = 0;
    while (offset < count) {
        ssize_t result = read(descriptor, destination + offset, count - offset);
        if (result < 0 && errno == EINTR) {
            continue;
        }
        if (result <= 0) {
            return false;
        }
        offset += (size_t)result;
    }
    return true;
}

VPFileValidation vp_recorder_validate_file(const char *file_path) {
    VPFileValidation validation = {0};
    validation.schema_version = VP_SCHEMA_VERSION;
    if (file_path == NULL) {
        return validation;
    }
    int descriptor = open(file_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) {
        return validation;
    }
    VPFileHeader header = {0};
    if (!read_exact(descriptor, &header, sizeof(header)) || header.magic != VP_FILE_MAGIC
        || header.schema_version != VP_SCHEMA_VERSION || header.header_bytes != sizeof(header)
        || header.record_header_bytes != sizeof(VPRecordHeader)
        || header.footer_bytes != sizeof(VPFileFooter)
        || header.maximum_seconds > VP_MAX_SECONDS || header.maximum_seconds == 0
        || header.maximum_pcm_bytes > VP_MAX_PCM_BYTES || header.maximum_pcm_bytes == 0
        || header.resident_bytes > VP_MAX_RESIDENT_BYTES
        || header.native_byte_order != UINT32_C(0x01020304)) {
        close(descriptor);
        return validation;
    }
    validation.resident_bytes = header.resident_bytes;
    struct stat file_status = {0};
    bool regular_file = fstat(descriptor, &file_status) == 0 && S_ISREG(file_status.st_mode);
    uint64_t checksum = hash_bytes(VP_FNV_OFFSET, &header, sizeof(header));
    for (;;) {
        uint64_t prefix = 0;
        if (!read_exact(descriptor, &prefix, sizeof(prefix))) {
            break;
        }
        if (prefix == VP_FOOTER_MAGIC) {
            VPFileFooter footer = {0};
            footer.magic = prefix;
            if (!read_exact(descriptor, (unsigned char *)&footer + sizeof(prefix),
                            sizeof(footer) - sizeof(prefix))) {
                break;
            }
            unsigned char extra = 0;
            bool end_of_file = read(descriptor, &extra, 1) == 0;
            validation.checksum_matches = footer.checksum == checksum;
            validation.invalid_reasons = footer.snapshot.invalid_reasons;
            char receipt_path[PATH_MAX];
            bool receipt_matches = false;
            size_t path_length = strlen(file_path);
            if (path_length + sizeof(".seal") <= sizeof(receipt_path)) {
                memcpy(receipt_path, file_path, path_length);
                memcpy(receipt_path + path_length, ".seal", sizeof(".seal"));
                int receipt_descriptor = open(receipt_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
                if (receipt_descriptor >= 0) {
                    VPSealReceipt receipt = {0};
                    bool receipt_read = read_exact(receipt_descriptor, &receipt, sizeof(receipt));
                    bool receipt_end = read(receipt_descriptor, &extra, 1) == 0;
                    receipt_matches = receipt_read && receipt_end
                        && receipt.magic == VP_RECEIPT_MAGIC
                        && receipt.schema_version == VP_SCHEMA_VERSION
                        && receipt.receipt_bytes == sizeof(receipt)
                        && receipt.checksum == hash_bytes(checksum, &footer, sizeof(footer)) && regular_file
                        && receipt.file_bytes == (uint64_t)file_status.st_size
                        && receipt.record_count == validation.record_count
                        && receipt.pcm_bytes == validation.pcm_bytes;
                    close(receipt_descriptor);
                }
            }
            validation.checksum_matches = validation.checksum_matches && receipt_matches;
            validation.complete = footer.schema_version == VP_SCHEMA_VERSION
                && footer.footer_bytes == sizeof(footer) && end_of_file
                && receipt_matches && validation.checksum_matches
                && footer.snapshot.schema_version == VP_SCHEMA_VERSION
                && footer.snapshot.sealed && !footer.snapshot.accepting
                && !footer.snapshot.writer_failure && footer.snapshot.pending_records == 0
                && footer.snapshot.reserved_records == validation.record_count
                && footer.snapshot.written_records == validation.record_count
                && footer.snapshot.reserved_pcm_bytes == validation.pcm_bytes
                && footer.snapshot.written_pcm_bytes == validation.pcm_bytes
                && footer.snapshot.resident_bytes == header.resident_bytes;
            break;
        }
        VPRecordHeader record = {0};
        memcpy(&record, &prefix, sizeof(prefix));
        if (!read_exact(descriptor, (unsigned char *)&record + sizeof(prefix),
                        sizeof(record) - sizeof(prefix)) || record.magic != VP_RECORD_MAGIC
            || record.schema_version != VP_SCHEMA_VERSION || record.header_bytes != sizeof(record)
            || record.sequence != validation.record_count || record.payload_bytes > VP_SLOT_BYTES
            || record.buffer_count == 0 || record.buffer_count > VP_MAX_BUFFERS) {
            break;
        }
        uint64_t layout_bytes = 0;
        for (uint32_t index = 0; index < record.buffer_count; ++index) {
            layout_bytes += record.buffers[index].bytes;
        }
        if (layout_bytes != record.payload_bytes || record.payload_bytes
            > header.maximum_pcm_bytes - validation.pcm_bytes) {
            break;
        }
        checksum = hash_bytes(checksum, &record, sizeof(record));
        unsigned char buffer[16384];
        uint32_t remaining = record.payload_bytes;
        bool payload_complete = true;
        while (remaining != 0) {
            size_t count = remaining < sizeof(buffer) ? remaining : sizeof(buffer);
            if (!read_exact(descriptor, buffer, count)) {
                payload_complete = false;
                break;
            }
            checksum = hash_bytes(checksum, buffer, count);
            remaining -= (uint32_t)count;
        }
        if (!payload_complete) {
            break;
        }
        validation.record_count += 1;
        validation.pcm_bytes += record.payload_bytes;
    }
    close(descriptor);
    return validation;
}

bool vp_recorder_read_identity(const char *file_path, uint64_t record_index,
                              VPFrameIdentity *identity, uint32_t *buffer_count,
                              uint64_t *pcm_bytes) {
    if (file_path == NULL || identity == NULL || buffer_count == NULL || pcm_bytes == NULL) {
        return false;
    }
    int descriptor = open(file_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) {
        return false;
    }
    VPFileHeader file_header = {0};
    bool found = false;
    if (read_exact(descriptor, &file_header, sizeof(file_header))
        && file_header.magic == VP_FILE_MAGIC && file_header.schema_version == VP_SCHEMA_VERSION) {
        for (uint64_t index = 0; index <= record_index; ++index) {
            VPRecordHeader record = {0};
            if (!read_exact(descriptor, &record, sizeof(record)) || record.magic != VP_RECORD_MAGIC
                || record.header_bytes != sizeof(record) || record.payload_bytes > VP_SLOT_BYTES
                || record.buffer_count > VP_MAX_BUFFERS || record.sequence != index) {
                break;
            }
            if (index == record_index) {
                memset(identity, 0, sizeof(*identity));
                identity->stream_kind = record.stream_kind;
                identity->frame_count = record.frame_count;
                identity->format = record.format;
                identity->sample_time_valid = record.sample_time_valid;
                identity->host_time_valid = record.host_time_valid;
                identity->sample_time = record.sample_time;
                identity->host_time = record.host_time;
                identity->callback_enter_tick = record.callback_enter_tick;
                identity->source_range_valid = record.source_range_valid;
                identity->source_start_frame = record.source_start_frame;
                identity->source_frame_count = record.source_frame_count;
                *buffer_count = record.buffer_count;
                *pcm_bytes = record.payload_bytes;
                found = true;
                break;
            }
            if (lseek(descriptor, record.payload_bytes, SEEK_CUR) < 0) {
                break;
            }
        }
    }
    close(descriptor);
    return found;
}

void vp_recorder_destroy(VPRecorder *recorder) {
    if (recorder == NULL) {
        return;
    }
    if (!atomic_load(&recorder->sealed)) {
        vp_recorder_invalidate(recorder, VP_INVALID_ABORT);
        vp_recorder_seal(recorder);
    }
    if (recorder->writer_started && !recorder->writer_joined) {
        return;
    }
    free(recorder);
}
