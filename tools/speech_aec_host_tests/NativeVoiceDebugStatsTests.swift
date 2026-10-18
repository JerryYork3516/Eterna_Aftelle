@preconcurrency import AVFoundation
import Foundation

#if DEBUG
    @MainActor
    enum NativeVoiceDebugStatsTests {
        private static var cases = 0
        private static var checks = 0
        private static let anchor: UInt64 = 10_000_000_000

        private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            if !condition() {
                fatalError(message)
            }
        }

        static func run() {
            nativeDebugLevels()
            nativeDebugNonFinite()
            nativeDebugCapacity()
            nativeDebugClockFailures()
            nativeDebugPacketFailures()
            nativeDebugIdentityAndSeal()
            nativeDebugUnknownProcessing()
            nativeDebugIntegerFormats()
            nativeDebugInterleavedChannels()
            nativeDebugZeroIdentity()
            cases += 6
            nativeTimingEvents()
            nativeTimingFirstWitness()
            nativeTimingClockFailures()
            nativeTimingIdentity()
            nativeTimingStopAndRoute()
            nativeTimingCapacityAndPrivacy()
            AppleVPDebugProfileTests.run()
            print("d1_native_stats_cases=\(cases)")
            print("d1_native_stats_checks=\(checks)")
            print("d1_native_stats_device_access=ZERO")
        }

        private static func nativeDebugStats(
            channels: UInt32 = 1, configurationID: UInt64 = 3,
            generation: UInt64 = 7, validatedAt: UInt64 = 10_000_000_000
        ) -> MacSpeechNativeVoiceDebugStats {
            var stats = MacSpeechNativeVoiceDebugStats(runID: UUID(), generation: generation)
            let native = MacSpeechNativeInputFormat(sampleRate: 48000, channelCount: channels)
            stats.bind(configurationID: configurationID, voiceProcessing: MacSpeechVoiceProcessingSnapshot(
                mode: .appleVoiceProcessing, configurationID: configurationID,
                inputEnabled: true, outputEnabled: true, bypassed: false, inputMuted: false,
                automaticGainControlEnabled: true, inputFormat: native, outputFormat: native,
                validatedAtNanoseconds: validatedAt
            ))
            return stats
        }

        private static func nativeDebugBuffer(_ channels: [[Float]], interleaved: Bool = false) -> AVAudioPCMBuffer {
            let layout = AVAudioChannelLayout(
                layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels.count)
            )!
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                interleaved: interleaved, channelLayout: layout
            )
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(channels[0].count))!
            buffer.frameLength = buffer.frameCapacity
            for channel in channels.indices {
                for frame in channels[channel].indices {
                    let pointer = buffer.floatChannelData![interleaved ? 0 : channel]
                    pointer[interleaved ? frame * channels.count + channel : frame] = channels[channel][frame]
                }
            }
            return buffer
        }

        private static func nativeDebugLevels() {
            cases += 1
            var stats = nativeDebugStats(channels: 2)
            let planar = nativeDebugBuffer([[0, 1, -1], [0.25, 0.5, 1.5]])
            let second = nativeDebugBuffer([[0, 0.5, -0.5], [0.25, -1, 0]])
            stats.recordNative(planar, hostTimeNanoseconds: anchor, sampleTime: 0, configurationID: 3, generation: 7)
            stats.recordNative(second, hostTimeNanoseconds: anchor + 62500, sampleTime: 3,
                               configurationID: 3, generation: 7)
            stats.recordPacket(timestamp: anchor, byteCount: 960, accepted: true, configurationID: 3, generation: 7)
            let snapshot = stats.snapshot
            expect(snapshot.coverageValid, "matching observed metadata is valid coverage, not acoustic acceptance")
            expect(snapshot.nativeBufferCount == 2 && snapshot.nativeFrameCount == 6,
                   "native counters include both buffers")
            expect(snapshot.channels.map(\.sampleCount) == [6, 6], "each native channel retains its own sample count")
            expect(snapshot.channels.map(\.peakMagnitude) == [1, 1.5], "native peaks do not use mono conversion")
            expect(snapshot.channels.map(\.fullScaleCount) == [2, 2], "full scale includes both signs and overrange")
            expect(snapshot.channels.map(\.overScaleCount) == [0, 1], "overrange is separate from exact full scale")
            expect(snapshot.channels.map(\.nonFiniteCount) == [0, 0], "finite channels are distinguished from unknown")
            expect(planar.floatChannelData![0][1] == 1 && planar.floatChannelData![1][2] == 1.5,
                   "observation does not clamp or mutate native PCM")
            expect(snapshot.firstNativeHostTime == anchor && snapshot.lastNativeSampleTime == 3,
                   "native content anchors retain the original buffer start")
        }

        private static func nativeDebugNonFinite() {
            cases += 1
            var stats = nativeDebugStats()
            stats.recordNative(nativeDebugBuffer([[.nan, .infinity, -.infinity, 0.5]]),
                               hostTimeNanoseconds: anchor, sampleTime: 0, configurationID: 3, generation: 7)
            stats.recordNative(nativeDebugBuffer([[0.25, -0.5]]), hostTimeNanoseconds: anchor + 83333,
                               sampleTime: 4, configurationID: 3, generation: 7)
            let snapshot = stats.snapshot
            expect(snapshot.channels[0].sampleCount == 6, "nonfinite input remains part of the observed sample count")
            expect(snapshot.channels[0].nonFiniteCount == 3, "all nonfinite values are counted")
            expect(snapshot.channels[0].peakMagnitude == nil, "later finite data cannot disguise an unknown run peak")
            expect(snapshot.issues.contains("non_finite") && !snapshot.coverageValid,
                   "nonfinite native evidence cannot receive valid coverage")
        }

        private static func nativeDebugCapacity() {
            cases += 1
            var channels = nativeDebugStats(channels: 9)
            channels.recordNative(nativeDebugBuffer(Array(repeating: [0.25], count: 9)),
                                  hostTimeNanoseconds: anchor, sampleTime: 0, configurationID: 3, generation: 7)
            expect(channels.snapshot.issues.contains("native_capacity"), "too many channels are explicitly rejected")
            expect(channels.snapshot.nativeFrameCount == 1 && channels.snapshot.channels.isEmpty,
                   "overcapacity callback size is recorded without silently truncating channels")
            var frames = nativeDebugStats()
            let samples = Array(repeating: Float(0.25), count: MacSpeechNativeVoiceDebugStats.maxNativeFrames + 1)
            let oversized = nativeDebugBuffer([samples])
            frames.recordNative(oversized, hostTimeNanoseconds: anchor, sampleTime: 0,
                                configurationID: 3, generation: 7)
            expect(frames.snapshot.issues.contains("native_capacity") && frames.snapshot.channels.isEmpty
                && frames.snapshot.nativeFrameCount == UInt64(MacSpeechNativeVoiceDebugStats.maxNativeFrames + 1),
                "oversized callback size remains visible without partial channel statistics")
        }

        private static func nativeDebugClockFailures() {
            cases += 1
            for scenario in ["missing-host", "missing-sample", "sample-gap", "host-gap", "backward"] {
                var stats = nativeDebugStats()
                let sample = nativeDebugBuffer([[0.25]])
                if scenario != "missing-host" && scenario != "missing-sample" {
                    stats.recordNative(sample, hostTimeNanoseconds: anchor, sampleTime: 0,
                                       configurationID: 3, generation: 7)
                }
                let host: UInt64? = scenario == "missing-host" ? nil
                    : scenario == "backward" ? anchor - 1
                    : anchor + (scenario == "host-gap" ? 1_000_000 : 20833)
                let cursor: Int64? = scenario == "missing-sample" ? nil : scenario == "sample-gap" ? 2 : 1
                stats.recordNative(sample, hostTimeNanoseconds: host, sampleTime: cursor,
                                   configurationID: 3, generation: 7)
                expect(stats.snapshot.issues.contains("native_clock") && !stats.snapshot.coverageValid,
                       "native clock failure remains visible: \(scenario)")
            }
        }

        private static func nativeDebugPacketFailures() {
            cases += 1
            var stats = nativeDebugStats()
            stats.recordPacket(timestamp: anchor, byteCount: 960, accepted: true, configurationID: 3, generation: 7)
            stats.recordPacket(timestamp: anchor + 20_000_000, byteCount: 960, accepted: true,
                               configurationID: 3, generation: 7)
            expect(stats.snapshot.packetCount == 2 && stats.snapshot.packetByteCount == 1920,
                   "packet counters retain complete actual packet lengths")
            expect(stats.snapshot.firstPacketTime == anchor && stats.snapshot.lastPacketTime == anchor + 20_000_000,
                   "packet timestamps are original pre-clamp values")
            stats.recordPacket(timestamp: anchor + 20_000_000, byteCount: 960, accepted: true,
                               configurationID: 3, generation: 7)
            expect(stats.snapshot.issues.contains("packet_clock"), "repeated content time is not repaired for evidence")
            stats.recordPacket(timestamp: anchor + 40_000_000, byteCount: 958, accepted: true,
                               configurationID: 3, generation: 7)
            expect(stats.snapshot.issues.contains("packet_length"), "short packets remain invalid rather than padded")
            stats.recordPacket(timestamp: anchor + 60_000_000, byteCount: 960, accepted: false,
                               configurationID: 3, generation: 7)
            expect(stats.snapshot.issues.contains("buffer_rejected"),
                   "buffer rejection is retained before queue counters")
        }

        private static func nativeDebugIdentityAndSeal() {
            cases += 1
            var stats = nativeDebugStats()
            let sample = nativeDebugBuffer([[0.25]])
            stats.recordNative(sample, hostTimeNanoseconds: anchor, sampleTime: 0, configurationID: 2, generation: 7)
            stats.recordNative(sample, hostTimeNanoseconds: anchor, sampleTime: 0, configurationID: 3, generation: 8)
            expect(stats.snapshot.rejections["stale_context"] == 2 && stats.snapshot.nativeFrameCount == 0,
                   "old configuration and generation cannot populate the current run")
            stats.seal()
            let sealed = stats.snapshot
            stats.bind(configurationID: 4, voiceProcessing: nil)
            stats.recordNative(sample, hostTimeNanoseconds: anchor, sampleTime: 0, configurationID: 3, generation: 7)
            stats.recordPacket(timestamp: anchor, byteCount: 960, accepted: true, configurationID: 3, generation: 7)
            stats.reject("unrecognized-test-reason")
            stats.seal(reason: "capture_stopped")
            expect(stats.snapshot.isSealed && stats.snapshot.configurationID == sealed.configurationID,
                   "sealed configuration identity cannot be rebound")
            expect(stats.snapshot.nativeFrameCount == sealed.nativeFrameCount
                && stats.snapshot.packetCount == sealed.packetCount
                && stats.snapshot.rejections == sealed.rejections
                && stats.snapshot.sealReason == sealed.sealReason, "late callbacks cannot modify sealed evidence")
            let next = nativeDebugStats()
            expect(next.snapshot.runID != sealed.runID && next.snapshot.channels.isEmpty
                && next.snapshot.issues.isEmpty,
                "a new run starts without old samples or failures")
        }

        private static func nativeDebugUnknownProcessing() {
            cases += 1
            var stats = MacSpeechNativeVoiceDebugStats(runID: UUID(), generation: 7)
            stats.bind(configurationID: 3, voiceProcessing: nil)
            stats.recordNative(nativeDebugBuffer([[0.25]]), hostTimeNanoseconds: anchor, sampleTime: 0,
                               configurationID: 3, generation: 7)
            expect(stats.snapshot.nativeFrameCount == 1, "unknown processing does not fabricate or hide native samples")
            expect(stats.snapshot.issues.contains("voice_processing") && !stats.snapshot.coverageValid,
                   "actual samples alone cannot prove valid voice processing")
            stats.reject("unrecognized-test-reason")
            expect(stats.snapshot.rejections["other"] == 1, "unrecognized reasons remain in a bounded category")
        }

        private static func nativeDebugIntegerFormats() {
            cases += 1
            for commonFormat in [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatInt32] {
                let format = AVAudioFormat(
                    commonFormat: commonFormat, sampleRate: 48000, channels: 1, interleaved: true
                )!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3)!
                buffer.frameLength = 3
                if commonFormat == .pcmFormatInt16 {
                    buffer.int16ChannelData![0].update(from: [Int16.min, 0, Int16.max], count: 3)
                } else {
                    buffer.int32ChannelData![0].update(from: [Int32.min, 0, Int32.max], count: 3)
                }
                var stats = nativeDebugStats()
                stats.recordNative(buffer, hostTimeNanoseconds: anchor, sampleTime: 0,
                                   configurationID: 3, generation: 7)
                expect(stats.snapshot.channels[0].fullScaleCount == 2, "both native integer limits are full scale")
                expect(stats.snapshot.channels[0].overScaleCount == 0, "native integer endpoints are not overrange")
                expect(stats.snapshot.channels[0].peakMagnitude == 1,
                       "integer observation uses its original native scale")
                expect(stats.snapshot.nativeFormat?.isInterleaved == true, "original native interleaving is recorded")
            }
        }

        private static func nativeDebugInterleavedChannels() {
            cases += 1
            var stats = nativeDebugStats(channels: 2)
            let buffer = nativeDebugBuffer([[0.25, -1.5], [0.5, 1.25]], interleaved: true)
            stats.recordNative(buffer, hostTimeNanoseconds: anchor, sampleTime: 0, configurationID: 3, generation: 7)
            expect(stats.snapshot.channels.map(\.peakMagnitude) == [1.5, 1.25],
                   "interleaved channel strides retain independent native peaks")
            expect(stats.snapshot.channels.map(\.fullScaleCount) == [1, 1],
                   "interleaved full scale is counted per native channel")
            expect(stats.snapshot.channels.map(\.overScaleCount) == [1, 1],
                   "both signs of float overrange remain distinct")
            expect(buffer.floatChannelData![0][2] == -1.5 && buffer.floatChannelData![0][3] == 1.25,
                   "overrange observation does not clamp original samples")
            expect(stats.snapshot.nativeFormat?.isInterleaved == true, "native format records Float32 interleaving")
        }

        private static func nativeDebugZeroIdentity() {
            cases += 1
            let invalid = [nativeDebugStats(configurationID: 0), nativeDebugStats(generation: 0)]
            for stats in invalid {
                expect(stats.snapshot.configurationID == nil && stats.snapshot.issues.contains("stale_context")
                    && !stats.snapshot.coverageValid, "zero configuration or generation cannot bind valid evidence")
            }
            let missingReadback = nativeDebugStats(validatedAt: 0)
            expect(missingReadback.snapshot.issues.contains("voice_processing")
                && !missingReadback.snapshot.coverageValid,
                "zero readback time remains processing-unknown")
        }
    }

    private extension NativeVoiceDebugStatsTests {
        static func timingStats() -> MacSpeechNativeVoiceTiming {
            let value = MacSpeechNativeVoiceTiming(runID: UUID(), generation: 7)
            value.bind(configurationID: 3, playbackGeneration: 1)
            return value
        }

        static func nativeTimingEvents() {
            let value = timingStats()
            for (index, event) in MacSpeechTimingEvent.allCases.enumerated() {
                value.event(event, at: anchor + UInt64(index))
            }
            value.event(.captureStopped, at: anchor + 20)
            let view = value.snapshot()
            expect(view?.events.count == 10, "events have fixed capacity")
            expect(view?.events.first?.firstCallTimeNs == anchor, "engine call timestamp retained")
            expect(view?.events[7].count == 2 && view?.events[7].lastCallTimeNs == anchor + 20, "duplicates aggregate")
            expect(view?.callbacksClosed == true, "stop closes only observation callbacks")
            let origin = anchor
            DispatchQueue.concurrentPerform(iterations: 1000) { index in
                value.event(.playbackPrepared, at: origin + UInt64(index))
            }
            let concurrent = value.snapshot()
            expect(
                (concurrent?.events[4].count ?? 0) + (concurrent?.skippedUpdates ?? 0) == 1001,
                "contention is counted without retry"
            )
            expect(concurrent?.events.count == 10, "concurrency never grows the event buffer")
        }

        static func nativeTimingFirstWitness() {
            let value = timingStats()
            value.input(content: (anchor, 100), arrival: anchor + 1000, frames: 4, rate: 48000,
                        identity: (3, 7))
            let buffer = nativeDebugBuffer([[0, 0.1, 0, 0.2]])
            value.render(buffer, content: (anchor, 0), arrival: anchor + 2000,
                         identity: (3, 7))
            let view = value.snapshot()
            expect(view?.input.firstContentHostNs == anchor && view?.input.firstArrivalNs == anchor + 1000,
                   "content and callback arrival are distinct")
            expect(view?.playerRender.firstNonzeroContentNs == anchor + 20833, "sample offset uses content time")
            expect(view?.playerRender.firstArrivalNs == anchor + 2000, "first Player callback witnessed")
            value.render(buffer, content: (anchor + 83333, 4), arrival: anchor + 100_000, identity: (3, 7))
            let stream = value.snapshot()?.playerRender
            expect(stream?.frames == 8 && stream?.sampleDiscontinuities == 0, "contiguous samples")
            expect(stream?.hostDiscontinuities == 0 && stream?.maximumStartIntervalNs == 83333, "bounded rounding")
            expect(stream?.firstNonzeroContentNs == anchor + 20833, "first nonzero is never overwritten")
        }

        static func nativeTimingClockFailures() {
            let value = timingStats()
            for (host, sample) in [(anchor, Int64(0)), (anchor + 166_667, 8), (anchor + 166_667, 8), (anchor - 1, -1)] {
                value.input(content: (host, sample), arrival: anchor + 1_000_000, frames: 4, rate: 48000,
                            identity: (3, 7))
            }
            value.input(content: (nil, nil), arrival: anchor, frames: 4, rate: 48000, identity: (3, 7))
            let stream = value.snapshot()?.input
            expect(
                stream?.missingTime == 1 && stream?.duplicate == 1 && stream?.backwards == 1,
                "clock negative controls"
            )
            expect(
                (stream?.sampleDiscontinuities ?? 0) > 0 && (stream?.hostDiscontinuities ?? 0) > 0,
                "gaps stay visible"
            )
        }

        static func nativeTimingIdentity() {
            let value = timingStats()
            value.input(content: (anchor, 0), arrival: anchor, frames: 4, rate: 48000, identity: (4, 7))
            value.render(nativeDebugBuffer([[1]]), content: (anchor, 0), arrival: anchor, identity: (3, 8))
            value.bind(configurationID: 3, playbackGeneration: 2)
            expect(
                value.snapshot()?.staleCallbacks == 2 && value.snapshot()?.identityChanges == 1,
                "old identities rejected"
            )
            expect(
                value.snapshot()?.input.buffers == 0 && value.snapshot()?.playerRender.buffers == 0,
                "no stale merge"
            )
        }

        static func nativeTimingStopAndRoute() {
            for event in [MacSpeechTimingEvent.captureStopped, .routeChanged] {
                let value = timingStats()
                value.event(event, at: anchor)
                value.render(nativeDebugBuffer([[1]]), content: (anchor, 0), arrival: anchor,
                             identity: (3, 7))
                expect(
                    value.snapshot()?.staleCallbacks == 1,
                    "late callbacks after stop/route are observation-only rejects"
                )
            }
            let value = timingStats()
            value.bind(configurationID: 4)
            expect(value.snapshot()?.callbacksClosed == true, "configuration reset invalidates the old run")
        }

        static func nativeTimingCapacityAndPrivacy() {
            let value = timingStats()
            value.render(nativeDebugBuffer([Array(repeating: 0, count: 16385)]), content: (anchor, 0),
                         arrival: anchor, identity: (3, 7))
            let buffer = nativeDebugBuffer([[0, 1, 0, 0.5], [0, 1, 0, 0.5], [0, 1, 0, 0.5]])
            value.format(buffer.format)
            value.scheduled(buffer)
            let view = value.snapshot()
            expect(view?.playbackFormat?.asbd.count == 9 && view?.playbackFormat?.channelCount == 3, "complete ASBD")
            expect(
                view?.playbackFormat?.layoutTag == kAudioChannelLayoutTag_DiscreteInOrder | 3,
                "explicit synthetic layout"
            )
            expect(
                view?.scheduledFrames == 4 && view?.scheduledNonzeroFrames == 2,
                "frames are not tripled by channel count"
            )
            expect(view?.nonzeroCoverage.hasPrefix("UNKNOWN") == true, "counts alone never prove interval coverage")
            expect(buffer.floatChannelData?[0][1] == 1, "observation leaves PCM unchanged")
            value.render(buffer, content: (nil, 0), arrival: anchor, identity: (3, 7))
            value.render(buffer, content: (anchor + 83333, 4), arrival: anchor + 100_000, identity: (3, 7))
            expect(value.snapshot()?.playerRender.firstNonzeroContentNs == nil,
                   "missing first-nonzero time stays unknown rather than being backfilled")
            let data = try? JSONEncoder().encode(value.snapshot())
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            expect(value.snapshot()?.invalidBuffers == 1, "oversized buffers do not expand observation capacity")
            expect(
                text.contains("UNKNOWN") && !text.contains("pcm16") && !text.contains("device"),
                "no PCM or device identifiers"
            )
            expect((data?.count ?? Int.max) < 16000, "serialized metadata is bounded")
        }
    }
#endif
