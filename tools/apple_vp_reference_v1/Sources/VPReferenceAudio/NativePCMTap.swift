import AVFoundation
import VPRecorder

enum NativePCMTap {
    static func install(node: AVAudioNode, stream: UInt32, recorder: RecorderOwner) {
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, time in
            let entered = vp_recorder_now_tick()
            var identity = VPFrameIdentity()
            identity.stream_kind = stream
            identity.frame_count = buffer.frameLength
            identity.format = buffer.format.streamDescription.pointee
            identity.sample_time_valid = time.isSampleTimeValid
            identity.host_time_valid = time.isHostTimeValid
            identity.sample_time = time.sampleTime
            identity.host_time = time.hostTime
            identity.callback_enter_tick = entered
            identity.source_range_valid = false
            _ = vp_recorder_submit(recorder.handle, &identity, buffer.audioBufferList)
        }
    }
}
