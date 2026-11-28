#include "NativeVoiceRealtime.h"
#include <assert.h>
#include <stdio.h>

enum Pull { PCM, SILENT, ADVANCE, ERROR, BAD_ABL };
static enum Pull mode;
static NVTRTIO *io;
static unsigned checks, pulls;
static uint32_t expected_buffers, expected_channels;
static const AudioTimeStamp *expected_time;
static char fake_unit;

#define CHECK(test) do { assert(test); ++checks; } while (0)

OSStatus AudioUnitRender(AudioUnit unit, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                         UInt32 bus, UInt32 frames, AudioBufferList *data) {
    CHECK(unit == (AudioUnit)&fake_unit && bus == 1 && time == expected_time);
    ++pulls;
    if (mode == ERROR) return kAudioUnitErr_NoConnection;
    if (mode == BAD_ABL) {
        data->mBuffers[0].mDataByteSize = 0;
        return noErr;
    }
    CHECK(data->mNumberBuffers == expected_buffers);
    for (uint32_t b = 0; b < expected_buffers; ++b) {
        AudioBuffer buffer = data->mBuffers[b];
        CHECK(buffer.mNumberChannels == expected_channels && buffer.mData);
        CHECK(buffer.mDataByteSize == frames * expected_channels * sizeof(float));
        float *samples = buffer.mData;
        for (uint32_t i = 0; i < frames * expected_channels; ++i)
            samples[i] = (float)(b * expected_channels + i % expected_channels + 1) / 8.0f;
    }
    if (mode == SILENT) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    if (mode == ADVANCE) CHECK(nvt_rt_set_capture(io, 12, 500));
    return noErr;
}

static NVTDirectVPIO *make_context(uint32_t channels, bool interleaved) {
    io = nvt_rt_create((NVTRTConfig){
        .capture_channels = channels, .capture_channel = channels - 1, .max_callback_frames = 16,
        .capture_interleaved = interleaved, .timebase_numerator = 1, .timebase_denominator = 1,
        .capture_capacity = 32, .playback_capacity = 32, .configuration_id = 17, .capture_token = 11,
        .playback_token = 21
    });
    CHECK(io);
    NVTDirectVPIO *context = nvt_direct_vpio_create(io, (AudioUnit)&fake_unit);
    CHECK(context);
    mode = PCM;
    expected_buffers = interleaved ? 1 : channels;
    expected_channels = interleaved ? channels : 1;
    return context;
}

static void release_context(NVTDirectVPIO *context) {
    nvt_rt_close(io);
    nvt_direct_vpio_destroy(context);
    nvt_rt_destroy(io);
}

static void capture(uint32_t channels, bool interleaved) {
    NVTDirectVPIO *context = make_context(channels, interleaved);
    AudioTimeStamp stamp = {.mSampleTime = -9, .mHostTime = 1000,
                           .mFlags = kAudioTimeStampSampleHostTimeValid | kAudioTimeStampRateScalarValid};
    AudioUnitRenderActionFlags flags = 0;
    expected_time = &stamp;
    unsigned before = pulls;
    CHECK(nvt_rt_enable_same_frame(io));
    CHECK(nvt_direct_vpio_capture(context, &flags, &stamp, 1, 7, NULL) == noErr);
    CHECK(pulls == before && nvt_rt_capture_stats(io).water_frames == 0);
    CHECK(nvt_rt_activate(io));
    CHECK(nvt_direct_vpio_capture(context, &flags, &stamp, 1, 7, NULL) == noErr);
    float samples[16];
    NVTFrame frames[16];
    NVTRing *ring = nvt_rt_capture_ring(io);
    CHECK(nvt_ring_read(ring, samples, frames, 16, false, false).copied == 7);
    for (unsigned i = 0; i < 7; ++i) {
        CHECK(samples[i] == (float)channels / 8.0f && frames[i].offset == i);
        CHECK(frames[i].origin.sample_time == -9 && frames[i].origin.host_time_ns == 1000);
        CHECK(frames[i].ingress.raw_flags == stamp.mFlags && frames[i].ingress.configuration_id == 17);
    }
    NVTSameFrameBlock block;
    CHECK(nvt_rt_peek_same_frame(io, &block) && block.channels == channels && block.frames == 7 && block.capture_token == 11);
    nvt_rt_release_same_frame(io);

    mode = SILENT;
    stamp.mSampleTime += 7;
    stamp.mFlags = kAudioTimeStampSampleTimeValid;
    CHECK(nvt_direct_vpio_capture(context, &flags, &stamp, 1, 2, NULL) == noErr);
    CHECK(nvt_ring_read(ring, samples, frames, 16, false, false).copied == 2);
    CHECK(samples[0] == 0 && samples[1] == 0 && frames[0].origin.flags == NVT_SAMPLE_TIME_VALID);
    CHECK(frames[0].ingress.raw_flags == kAudioTimeStampSampleTimeValid);

    mode = ADVANCE;
    stamp.mFlags = kAudioTimeStampSampleHostTimeValid;
    CHECK(nvt_direct_vpio_capture(context, &flags, &stamp, 1, 3, NULL) == noErr);
    CHECK(nvt_rt_stats(io).capture_stale_frames == 3 && nvt_rt_capture_stats(io).water_frames == 0);
    CHECK(nvt_ring_consumer_sync(ring) == 12);
    mode = PCM;
    stamp.mHostTime += 100;
    CHECK(nvt_direct_vpio_capture(context, &flags, &stamp, 1, 1, NULL) == noErr);
    CHECK(nvt_ring_read(ring, samples, frames, 16, false, false).copied == 1);
    CHECK(frames[0].ingress.raw_host_time == stamp.mHostTime);
    release_context(context);
}

static void render(void) {
    NVTDirectVPIO *context = make_context(1, false);
    const AudioTimeStamp stamp = {.mSampleTime = 26, .mHostTime = 2000, .mFlags = kAudioTimeStampSampleHostTimeValid};
    AudioUnitRenderActionFlags flags = 0;
    float samples[] = {99, 99, 99, 99};
    AudioBufferList output = {1, {{1, sizeof(samples), samples}}};
    CHECK(nvt_direct_vpio_render(context, &flags, &stamp, 0, 4, &output) == noErr);
    CHECK((flags & kAudioUnitRenderAction_OutputIsSilence) && samples[0] == 0);
    CHECK(nvt_rt_activate(io) && nvt_rt_set_playback(io, 21, false));
    const float content[] = {0.25f, 0, -0.5f};
    CHECK(nvt_rt_enqueue(io, content, 3, 21, true) == NVT_WRITE_OK);
    CHECK(nvt_direct_vpio_render(context, &flags, &stamp, 0, 4, &output) == noErr);
    CHECK(!(flags & kAudioUnitRenderAction_OutputIsSilence) && samples[0] == 0.25f && samples[2] == -0.5f && samples[3] == 0);
    NVTRenderFact fact;
    CHECK(nvt_rt_take_render_fact(io, &fact) && fact.playback_token == 21 && fact.configuration_id == 17);
    CHECK(fact.sample_time == 26 && fact.host_time == 2000 && fact.time_flags == stamp.mFlags);
    CHECK(fact.submitted_frames == 3 && fact.nonzero_frames == 2 && fact.nonzero_end == 3 && (fact.flags & NVT_RENDER_END));

    CHECK(nvt_rt_set_playback(io, 22, true));
    CHECK(nvt_direct_vpio_render(context, &flags, &stamp, 0, 4, &output) == noErr);
    CHECK((flags & kAudioUnitRenderAction_OutputIsSilence) && nvt_rt_stats(io).rendered_clear_token == 22);
    nvt_direct_vpio_changed(context, (AudioUnit)&fake_unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 1);
    CHECK(!nvt_rt_active(io));
    unsigned before = pulls;
    CHECK(nvt_direct_vpio_capture(context, &flags, &stamp, 1, 4, NULL) == noErr && pulls == before);
    CHECK(nvt_direct_vpio_render(context, &flags, &stamp, 0, 4, &output) == noErr);
    CHECK((flags & kAudioUnitRenderAction_OutputIsSilence) && samples[0] == 0);
    release_context(context);
}

static void split_auhal_callbacks(void) {
    NVTDirectVPIO *context = make_context(1, false);
    const AudioTimeStamp silent_time = {
        .mSampleTime = 2, .mHostTime = 100, .mFlags = kAudioTimeStampSampleHostTimeValid
    };
    const AudioTimeStamp speaker_time = {
        .mSampleTime = 300, .mHostTime = 9000, .mFlags = kAudioTimeStampSampleTimeValid
    };
    AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PreRender;
    float samples[] = {99, 99, 99, 99};
    AudioBufferList output = {1, {{1, sizeof(samples), samples}}};
    CHECK(nvt_rt_activate(io) && nvt_rt_set_playback(io, 21, false));
    const float content[] = {0.25f, -0.5f};
    CHECK(nvt_rt_enqueue(io, content, 2, 21, true) == NVT_WRITE_OK);
    CHECK(nvt_split_vpio_silence(context, &flags, &silent_time, 0, 4, &output) == noErr);
    for (unsigned i = 0; i < 4; ++i) CHECK(samples[i] == 0);
    CHECK((flags & kAudioUnitRenderAction_OutputIsSilence) && (flags & kAudioUnitRenderAction_PreRender));
    NVTRenderFact fact;
    CHECK(!nvt_rt_take_render_fact(io, &fact) && nvt_rt_stats(io).rendered_end_token == 0);
    CHECK(nvt_direct_vpio_render(context, &flags, &speaker_time, 0, 4, &output) == noErr);
    CHECK(samples[0] == 0.25f && samples[1] == -0.5f && samples[3] == 0);
    CHECK(nvt_rt_take_render_fact(io, &fact) && fact.playback_token == 21 && fact.configuration_id == 17);
    CHECK(fact.sample_time == 300 && fact.host_time == 9000 && fact.host_time_ns == 0);
    CHECK(fact.time_flags == kAudioTimeStampSampleTimeValid && (fact.flags & NVT_RENDER_END));
    CHECK(nvt_rt_set_playback(io, 22, true));
    CHECK(nvt_split_vpio_silence(context, &flags, &silent_time, 0, 4, &output) == noErr);
    CHECK(nvt_rt_stats(io).rendered_clear_token == 0);
    CHECK(!nvt_rt_take_render_fact(io, &fact));
    CHECK(nvt_direct_vpio_render(context, &flags, &speaker_time, 0, 4, &output) == noErr);
    CHECK(nvt_rt_stats(io).rendered_clear_token == 22);

    output.mBuffers[0].mDataByteSize = sizeof(float);
    samples[1] = 9;
    CHECK(nvt_split_vpio_silence(context, &flags, &silent_time, 0, 4, &output) == kAudio_ParamError);
    CHECK(samples[1] == 9 && !nvt_rt_active(io));
    release_context(context);
}

static void capture_failure(enum Pull failure, uint32_t frames, OSStatus error) {
    NVTDirectVPIO *context = make_context(2, true);
    const AudioTimeStamp stamp = {.mFlags = kAudioTimeStampSampleTimeValid};
    AudioUnitRenderActionFlags flags = 0;
    expected_time = &stamp;
    mode = failure;
    CHECK(nvt_rt_activate(io));
    CHECK(nvt_direct_vpio_capture(context, &flags, &stamp, 1, frames, NULL) == error);
    CHECK(nvt_rt_stats(io).rejected_input_frames == frames && !nvt_rt_active(io));
    CHECK(nvt_rt_capture_stats(io).water_frames == 0);
    release_context(context);
}

int main(void) {
    capture(1, false);
    capture(3, true);
    capture(5, false);
    render();
    split_auhal_callbacks();
    capture_failure(PCM, 17, kAudioUnitErr_TooManyFramesToProcess);
    capture_failure(BAD_ABL, 4, kAudio_ParamError);
    capture_failure(ERROR, 4, kAudioUnitErr_NoConnection);
    printf("native_voice_direct_vpio_callback_checks=%u\n", checks);
}
