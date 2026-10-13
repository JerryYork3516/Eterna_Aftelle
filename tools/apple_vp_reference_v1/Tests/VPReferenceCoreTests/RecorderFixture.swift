import AudioToolbox
import Foundation
import VPRecorder

final class RecorderFixture {
    enum FixtureError: Error {
        case creation(Int32)
        case arm
        case writerTimeout
    }

    let directory: URL
    let recorder: OpaquePointer
    let startTick: UInt64 = 1_024

    var evidence: URL { directory.appendingPathComponent("evidence.vp0") }

    static var nativeMonoFormat: AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
        )
    }

    init(configure: (inout VPRecorderConfig) -> Void = { _ in }) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vp0-synthetic-\(UUID().uuidString)")
        var config = vp_recorder_default_config()
        config.fixture_mode = true
        configure(&config)
        var errorCode: Int32 = 0
        guard
            let created = directory.path.withCString({
                vp_recorder_create($0, &config, &errorCode)
            })
        else {
            throw FixtureError.creation(errorCode)
        }
        recorder = created
    }

    deinit {
        vp_recorder_destroy(recorder)
        try? FileManager.default.removeItem(at: directory)
    }

    func arm() throws {
        guard vp_recorder_arm(recorder, startTick) else { throw FixtureError.arm }
    }

    func identity(
        frames: UInt32 = 4, sample: Int64 = 0, tick: UInt64? = nil,
        stream: UInt32 = UInt32(VP_STREAM_INPUT)
    ) -> VPFrameIdentity {
        var identity = VPFrameIdentity()
        identity.stream_kind = stream
        identity.frame_count = frames
        identity.format = Self.nativeMonoFormat
        identity.sample_time_valid = true
        identity.host_time_valid = true
        identity.sample_time = sample
        identity.host_time = 987_654
        identity.callback_enter_tick = tick ?? startTick + 1
        return identity
    }

    func submit(_ identity: VPFrameIdentity, bytes: [UInt8] = Array(repeating: 7, count: 16)) -> Bool {
        var identity = identity
        return bytes.withUnsafeBytes { buffer in
            vp_recorder_submit_synthetic(recorder, &identity, buffer.baseAddress, UInt32(buffer.count))
        }
    }

    func waitForWritten(_ count: UInt64) throws {
        let deadline = Date().addingTimeInterval(10)
        while vp_recorder_snapshot(recorder).written_records < count {
            if Date() >= deadline || vp_recorder_snapshot(recorder).writer_failure {
                throw FixtureError.writerTimeout
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func validate() -> VPFileValidation {
        evidence.path.withCString { vp_recorder_validate_file($0) }
    }
}
