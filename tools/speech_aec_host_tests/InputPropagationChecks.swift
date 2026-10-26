import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

@main
@MainActor
private enum InputPropagationChecks {
    private static let anchor: UInt64 = 10_000_000_000

    static func main() throws {
        try NativeInputChannelMappingTests.run()
        let fresh = try recyclingNativeBuffer(false)
        let reused = try recyclingNativeBuffer(true)
        precondition(fresh == reused && fresh.allSatisfy(\.isFinite),
                     "converter retained mutable Native buffer contents after convert returned")
        print("native_buffer_reuse_and_post_return_poison=PASS samples=\(fresh.count)")
        let baseline = try stream(residentEvents: false)
        let resident = try stream(residentEvents: true)
        precondition(baseline.bytes == resident.bytes && baseline.times == resident.times,
                     "resident state changed post-VP software audio")
        precondition(!baseline.bytes.isEmpty && baseline.bytes.contains { $0 != 0 })
        print("resident_event_pcm_invariance=PASS packets=\(baseline.times.count) bytes=\(baseline.bytes.count)")
        let host = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)
        precondition(host.configure() == .appleVoiceProcessing)
        let samples: [Float] = [0.1, -0.2, 0.3, -0.4]
        host.routeWillRebuild()
        precondition(host.processCaptureSpans(samples, hostTimeNanoseconds: anchor).isEmpty)
        precondition(host.routeDidRebuild() == .appleVoiceProcessing)
        precondition(host.processCaptureSpans(samples, hostTimeNanoseconds: anchor).flatMap(\.samples) == samples)
        print("real_route_guard_and_restore=PASS")
        let queue = MacSpeechAudioFrameBuffer(capacity: 2)
        queue.begin(generation: 2)
        precondition(!queue.append(pcm16Bytes: baseline.bytes.prefix(960), activity: 1, generation: 1))
        for index in 0 ..< 3 {
            precondition(queue.append(pcm16Bytes: baseline.bytes.prefix(960), activity: 0, generation: 2,
                                      timestamp: anchor + UInt64(index) * 20_000_000))
        }
        precondition(queue.stats().rejectedStaleCount == 1 && queue.stats().droppedCount == 1)
        let frames = queue.drain(maxCount: 25)
        precondition(frames.map(\.sequenceNumber) == [2, 3])
        precondition(frames.allSatisfy { $0.pcm16Bytes == baseline.bytes.prefix(960) })
        print("queue_stale_overflow_order_and_no_activity_gate=PASS device_access=ZERO")
    }

    private static func recyclingNativeBuffer(_ recycle: Bool) throws -> [Float] {
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3)!
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   interleaved: false, channelLayout: layout)
        let converter = try MacSpeechFloatMono48kConverter(inputFormat: format)
        let recycled = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
        var retained: [AVAudioPCMBuffer] = []
        var samples: [Float] = []
        var offset = 0
        for count in [1600, 1600, 137, 1, 1600, 1600, 320, 1600] {
            let buffer = recycle ? recycled : AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
            buffer.frameLength = UInt32(count)
            for frame in 0 ..< count {
                let value = Float(0.3 * sin(Double(offset + frame) * 2 * .pi * 557 / 16000))
                for channel in 0 ..< 3 {
                    buffer.floatChannelData![channel][frame] = value
                }
            }
            samples += try converter.convert(buffer, hostTimeNanoseconds: anchor + UInt64(offset) * 62500,
                                             sampleTime: Int64(offset)).samples
            if recycle {
                for channel in 0 ..< 3 {
                    buffer.floatChannelData![channel].update(repeating: .nan, count: 1600)
                }
            } else {
                retained.append(buffer)
            }
            offset += count
        }
        return withExtendedLifetime(retained) { samples }
    }

    private static func advanceResident(_ host: MacSpeechAcousticEchoHost, index: Int) {
        if index == 30 {
            host.playbackStarted()
        }
        if (30 ..< 80).contains(index) {
            host.processRender([0.25, -0.25], hostTimeNanoseconds: anchor + UInt64(index) * 100_000_000)
        }
        if index == 40 {
            host.renderConversionFailed()
            host.updateDelay(outputPresentationLatencySeconds: .nan, capturePresentationLatencySeconds: 999)
        }
        if index == 80 {
            host.playbackCompleted()
        }
        if index == 81 {
            host.playbackStopped()
        }
    }

    private static func stream(residentEvents: Bool) throws -> (bytes: Data, times: [UInt64]) {
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3)!
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   interleaved: false, channelLayout: layout)
        let input = try MacSpeechFloatMono48kConverter(inputFormat: format)
        let mono = try MacSpeechFloatMono48kConverter.makeBuffer(samples: [0]).format
        let output = try MacSpeechAudioConverter(inputFormat: mono)
        let host = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing)
        precondition(host.configure() == .appleVoiceProcessing)
        let queue = MacSpeechAudioFrameBuffer()
        queue.begin(generation: 1)
        var bytes = Data()
        var times: [UInt64] = []
        for index in 0 ..< 100 {
            if residentEvents {
                advanceResident(host, index: index)
            }
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
            buffer.frameLength = 1600
            for frame in 0 ..< 1600 {
                let sample = Float(0.2 * sin(Double(index * 1600 + frame) * 2 * .pi * 317 / 16000))
                for channel in 0 ..< 3 {
                    buffer.floatChannelData![channel][frame] = sample
                }
            }
            let converted = try input.convert(buffer, hostTimeNanoseconds: anchor + UInt64(index) * 100_000_000,
                                              sampleTime: Int64(index * 1600))
            let spans = host.processCaptureSpans(converted.samples, hostTimeNanoseconds: converted.hostTimeNanoseconds)
            precondition(spans.flatMap(\.samples) == converted.samples)
            for packet in try output.convert(captureSpans: spans, requiresContinuousContentTime: true) {
                precondition(queue.append(pcm16Bytes: packet.bytes, activity: packet.activity, generation: 1,
                                          timestamp: packet.contentTimestampNanoseconds!))
            }
            for frame in queue.drain(maxCount: 25) {
                bytes.append(frame.pcm16Bytes)
                times.append(frame.monotonicTimestampNanoseconds)
            }
        }
        precondition(queue.stats().droppedCount == 0 && queue.stats().rejectedStaleCount == 0)
        for index in 1 ..< times.count {
            precondition(times[index] - times[index - 1] == 20_000_000)
        }
        return (bytes, times)
    }
}
