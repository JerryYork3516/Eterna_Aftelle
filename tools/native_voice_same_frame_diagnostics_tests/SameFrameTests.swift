@preconcurrency import AudioToolbox
import CoreAudio
import Foundation

@main
@MainActor
struct SameFrameTests {
    private static var checks = 0

    static func main() async throws {
        try await layout(interleaved: false, channelCount: 1, rate: 24000)
        try await layout(interleaved: true, channelCount: 5, rate: 16000)
        try await layout(interleaved: false, channelCount: 5, rate: 44100)
        try await overflowDoesNotChangePCM()
        try await configurationAndRetiredCallback()
        try oldTokenAndTail()
        try await unusableTimestamps()
        try impulseContentAlignment()
        try quantizationAndAdmission()
        try await captureFromExistingWorker()
        captureRejectsGaps()
        try localEvidencePublication()
        try await onsetHistory()
        print("native_voice_same_frame_swift_checks=\(checks)")
    }

    static func check(_ condition: Bool, _ label: String) {
        precondition(condition, label)
        checks += 1
    }

    static let captureIdentity = NativeVoiceIdentity(
        authority: .init(runtimeGeneration: 1, routeEpoch: 1, configurationID: 9),
        captureGeneration: 1, captureToken: 1, playbackEpoch: 1, playbackToken: 1
    )

    static func graph(
        channelCount: UInt32, interleaved: Bool, rate: Double, diagnostics: Bool
    ) -> (AppleNativeVoiceTransport, FakeVoiceHardware) {
        let hardware = FakeVoiceHardware()
        hardware.update {
            let old = $0.snapshot
            let plan = NativeVoiceGraphPlan(
                capture: .init(sampleRate: rate, channels: channelCount, interleaved: interleaved, float32: true),
                render: .init(sampleRate: rate, channels: 2, interleaved: false, float32: true)
            )
            $0.snapshot = .init(plan: plan, defaults: old.defaults, inputUnitDevice: old.inputUnitDevice,
                                outputUnitDevice: old.outputUnitDevice, bindings: old.bindings, streams: old.streams,
                                voiceProcessing: nil)
        }
        let transport = AppleNativeVoiceTransport(
            makeEngine: {
                let engine = FakeVoiceEngine(hardware: hardware)
                hardware.update { $0.graphs.append(engine) }
                return engine
            },
            authorized: { true },
            limits: .init(ringFrames: 32768, callbackFrames: 2048, captureChannel: 0,
                          sameFrameDiagnostics: diagnostics)
        )
        return (transport, hardware)
    }

    static func inject(
        _ lanes: [[Float]], into context: OpaquePointer, at sample: Int, rate: Double, interleaved: Bool,
        timeFlags: AudioTimeStampFlags = [.sampleTimeValid, .hostTimeValid]
    ) {
        let frames = lanes[0].count
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: frames * lanes.count)
        defer { storage.deallocate() }
        let abl = AudioBufferList.allocate(maximumBuffers: interleaved ? 1 : lanes.count)
        defer { free(abl.unsafeMutablePointer) }
        abl.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(interleaved ? 1 : lanes.count)
        for channel in lanes.indices {
            precondition(lanes[channel].count == frames)
            for frame in 0 ..< frames {
                storage[interleaved ? frame * lanes.count + channel : channel * frames + frame] = lanes[channel][frame]
            }
        }
        if interleaved {
            abl[0] = .init(mNumberChannels: UInt32(lanes.count), mDataByteSize: UInt32(frames * lanes.count * 4),
                           mData: storage)
        } else {
            for channel in lanes.indices {
                abl[channel] = .init(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4),
                                     mData: storage + channel * frames)
            }
        }
        var time = AudioTimeStamp()
        time.mFlags = timeFlags
        time.mSampleTime = Double(sample)
        time.mHostTime = AudioConvertNanosToHostTime(1_000_000_000 + UInt64((Double(sample) / rate * 1e9).rounded()))
        precondition(nvt_rt_capture(context, &time, UInt32(frames), abl.unsafeMutablePointer) == noErr)
    }

    private static func layout(interleaved: Bool, channelCount: UInt32, rate: Double) async throws {
        let (transport, hardware) = graph(channelCount: channelCount, interleaved: interleaved, rate: rate, diagnostics: true)
        try await transport.start(identity: captureIdentity)
        let engine = hardware.update { $0.graphs[0] }
        let context = engine.read().lease!.context
        let signal: [Float] = (0 ..< 320).map { [0, 0.25, -0.5, 0.125][$0 % 4] }
        let lanes = channelCount == 1 ? [signal] : [
            signal, signal, signal.map { $0 * 0.5 }, Array(repeating: 0, count: signal.count),
            signal.enumerated().map { $0.offset == 0 ? 1.25 : $0.offset == 1 ? .nan : -$0.element }
        ]
        for block in 0 ..< 5 {
            inject(lanes, into: context, at: signal.count * block, rate: rate, interleaved: interleaved)
            // Joining is through the real callback ID, even when the consumer splits one ABL.
            _ = try await transport.bridgeService(maxCaptureFrames: 120)
            _ = try await transport.bridgeService(maxCaptureFrames: 2048)
        }
        try await transport.beginPlayback(captureIdentity.playback)
        _ = try await transport.enqueuePlayback(
            NativeVoicePCM16.encode(Array(repeating: 0.25, count: 960)), identity: captureIdentity.playback
        )
        check(try await transport.finishPlayback(identity: captureIdentity.playback), "EOS accepted by Fake graph")
        _ = engine.render(2048, sampleTime: 9, hostTime: AudioConvertNanosToHostTime(1_080_000_000), flags: 3)
        _ = try await transport.bridgeService(maxCaptureFrames: 2048)
        await transport.close()
        let result = await transport.readback()!.sameFrameDiagnostics!
        check(result.complete, "lossless same-frame coverage")
        check(result.initialSystemState == nil, "Fake Engine has no physical system readback")
        check(result.inputs.count == 10, "each split consumption has a trace")
        check(result.inputs[0].blockID == result.inputs[1].blockID, "split input uses same callback ID")
        check(result.inputs[1].sink?.workerFrameOffset == 120, "callback-relative offset")
        check(result.inputs[0].sink?.sampleTime == 0 && result.inputs[0].sink?.hostTimeNanoseconds == 1_000_000_000,
              "raw callback sample and host anchors")
        check(result.inputs[0].playbackToken == 1 && result.inputs[0].sink?.identity.token == 1,
              "capture and playback identity")
        let input = result.inputs[0]
        let channels = input.channels!
        check(channels.count == Int(channelCount) && input.selectedChannel == 0, "configuration channel count")
        check(input.selected.zeros == 30 && input.selected.peak == 0.5, "actual selected levels")
        check(channels[0].versusSelected.bitIdenticalFrames == 120, "raw selected equals Worker input")
        if channelCount > 1 {
            check(channels[1].versusSelected.bitIdenticalFrames == 120, "identical other channel")
            check(channels[2].versusSelected.peak == 0.25, "attenuated channel difference")
            check(channels[2].level.rms == input.selected.rms.map { $0 * 0.5 }, "attenuation RMS")
            check((channels[2].versusSelected.correlation ?? 0) > 0.999, "attenuation correlation")
            check(channels[3].level.zeros == 120 && channels[3].versusSelected.correlation == nil, "silent channel")
            check(channels[4].level.overScale == 1 && channels[4].level.nonFinite == 1, "full scale and NaN")
            check(channels[4].versusSelected.finitePairs == 119 && (channels[4].versusSelected.correlation ?? 0) < -0.8,
                  "different waveform finite-pair correlation")
        }
        check(result.releases.contains { $0.acceptedNativeFrames > 0 }, "actual converter timeline")
        check(result.releases.allSatisfy { $0.frames24k.isEmpty || $0.selectedForContent != nil }, "SRC content join")
        check(result.releases.allSatisfy {
            $0.nativeContentFrames.upperBound <= $0.acceptedNativeFrames && $0.nativeRate == rate
        }, "native content bounds through delay")
        check(!result.packets.isEmpty && result.packets.allSatisfy {
            $0.beforeQuantization.frames == 480 && $0.pcm16.frames == 480
        }, "exact emitted packet")
        check(result.packets.allSatisfy { ($0.quantizationDifference.peak ?? .infinity) <= 1.0 / 32768 },
              "only expected PCM16 quantization error")
        check(result.renders.contains { $0.nonzeroFrames > 0 && $0.nonzeroSpan != nil && $0.playbackToken == 1 },
              "Source nonzero span stored")
        check(result.renders.contains { $0.digitalEOS && $0.sampleTime == 9 && $0.hostTimeNanoseconds != nil },
              "digital EOS and timestamp stored")
        let encoded = try JSONEncoder().encode(result)
        check(!String(decoding: encoded, as: UTF8.self).contains("\"samples\""), "no raw sample arrays in export")
    }

    private static func overflowDoesNotChangePCM() async throws {
        func run(_ diagnostics: Bool) async throws -> ([Data], NativeVoiceTransportReadback) {
            let (transport, hardware) = graph(channelCount: 1, interleaved: true, rate: 24000, diagnostics: diagnostics)
            try await transport.start(identity: captureIdentity)
            let context = hardware.update { $0.graphs[0].read().lease!.context }
            for index in 0 ..< 20 {
                inject([Array(repeating: Float(index) * 0.025, count: 96)],
                       into: context, at: index * 96, rate: 24000, interleaved: true)
            }
            let batch = try await transport.bridgeService(maxCaptureFrames: 2048)
            await transport.close()
            return (batch.packets.map(\.bytes), await transport.readback()!)
        }
        let (off, baseline) = try await run(false)
        let (on, enabled) = try await run(true)
        let observation = enabled.sameFrameDiagnostics!
        check(off == on && !off.isEmpty, "PCM unchanged even if observation overflows")
        check(baseline.sameFrameDiagnostics == nil, "diagnostics default off")
        check(observation.droppedSinkBlocks == 4 && observation.droppedSinkFrames == 384, "bounded capture copy loss")
        check(observation.missingInputs == 4 && !observation.complete, "dropped evidence always incomplete")
        check(observation.acceptedNativeFrames == 1920 && observation.observedNativeFrames == 1920,
              "observation overflow does not reject capture"
        )
    }

    private static func configurationAndRetiredCallback() async throws {
        let (transport, hardware) = graph(channelCount: 1, interleaved: false, rate: 16000, diagnostics: true)
        try await transport.start(identity: captureIdentity)
        let lease = hardware.update { $0.graphs[0].read().lease! }
        inject([[0.2, 0.3]], into: lease.context, at: 0, rate: 16000, interleaved: false)
        _ = try await transport.bridgeService(maxCaptureFrames: 2048)
        try await transport.invalidateConfiguration(captureIdentity.capture)
        let before = nvt_rt_stats(lease.context)
        inject([[0.9, 0.9]], into: lease.context, at: 2, rate: 16000, interleaved: false)
        check(nvt_rt_stats(lease.context).accepted_input_frames == before.accepted_input_frames,
              "closed callback cannot feed PCM")
        var block = NVTSameFrameBlock()
        check(!nvt_rt_peek_same_frame(lease.context, &block), "closed callback cannot expose evidence")
        let retired = await transport.readback()!.sameFrameDiagnostics!
        check(!retired.complete && retired.inputs.count == 1, "configuration-invalid report sealed incomplete")
        let next = NativeVoiceIdentity(
            authority: .init(runtimeGeneration: 1, routeEpoch: 2, configurationID: 10),
            captureGeneration: 2, captureToken: 2, playbackEpoch: 2, playbackToken: 2
        )
        try await transport.rebuild(identity: next)
        let current = hardware.update { $0.graphs[1].read().lease! }
        inject([[0.15, 0.25]], into: current.context, at: 0, rate: 16000, interleaved: false)
        _ = try await transport.bridgeService(maxCaptureFrames: 2048)
        await transport.close()
        let successor = await transport.readback()!.sameFrameDiagnostics!
        check(successor.inputs.count == 1 && successor.inputs[0].sink?.identity == next.capture,
              "rebuild uses independently allocated configuration evidence")
    }

    private static func oldTokenAndTail() throws {
        let config = NVTRTConfig(capture_channels: 1, capture_channel: 0, max_callback_frames: 2048,
                                 capture_interleaved: false, timebase_numerator: 1, timebase_denominator: 1,
                                 capture_capacity: 2048, playback_capacity: 2048,
                                 configuration_id: 9, capture_token: 1, playback_token: 1)
        let context = nvt_rt_create(config)!
        defer { nvt_rt_destroy(context) }
        let worker = try AppleNativeVoiceTransportWorker(identity: captureIdentity, nativeRate: 16000)
        worker.sameFrame = NativeVoiceSameFrameDiagnostics(context: context)
        check(nvt_rt_activate(context), "activate synthetic context")
        inject([Array(repeating: 0.95, count: 40)], into: context, at: 0, rate: 16000, interleaved: false)
        check(nvt_rt_set_capture(context, 2, 1), "move capture fence")
        let next = NativeVoiceIdentity(
            authority: captureIdentity.capture.authority, captureGeneration: 2, captureToken: 2,
            playbackEpoch: 1, playbackToken: 1
        )
        try worker.reset(identity: next, nativeRate: 16000)
        _ = try worker.drainCapture(nvt_rt_capture_ring(context), maxFrames: 512, requiresConfiguration: true)
        let input: [Float] = (0 ..< 633).map { $0 == 321 ? 0.5 : 0.2 }
        inject([input], into: context, at: 40, rate: 16000, interleaved: false)
        let first = try worker.drainCapture(nvt_rt_capture_ring(context), maxFrames: 320, requiresConfiguration: true)
        let second = try worker.drainCapture(nvt_rt_capture_ring(context), maxFrames: 1024, requiresConfiguration: true)
        let last = try worker.finishCapture(identity: next.capture)
        let facts = worker.sameFrame!.report(terminal: "closed", pendingTail: worker.pendingCaptureTailSamples,
                                             discardedTail: worker.discardedCaptureTailSamples)
        check(facts.unjoinedBlocks == 1 && !facts.complete, "discarded old raw identity leaves incomplete evidence")
        check(facts.inputs.allSatisfy { $0.sink?.identity == next.capture && $0.selected.peak != Double(Float(0.95)) },
              "old raw samples never join new capture token")
        check(facts.releases.last?.finishing == true && facts.releases.last?.frames24k.upperBound == 949, "flush retains floor duration")
        check(facts.releases.last?.unreleased24kFrames == 0 && facts.pendingCaptureTail24kFrames == 0, "finish closes SRC and packet tail")
        check(facts.discardedCaptureTail24kFrames == 469, "incomplete packet tail quantified")
        check(facts.releases.compactMap(\.selectedForContent).reduce(0) { $0 + $1.frames } == 632,
              "non-integer ratio native edge mapped without inventing a sample")
        let standalone = try NativeVoiceStreamingSRC(inputRate: 16000, outputRate: 24000)
        let all = try standalone.append(input) + standalone.finish()
        check((first + second + last).map(\.bytes) == [NativeVoicePCM16.encode(Array(all.prefix(480)))],
              "real primed converter and streaming chunks produce the same packet")
    }

    private static func unusableTimestamps() async throws {
        let (transport, hardware) = graph(channelCount: 1, interleaved: false, rate: 24000, diagnostics: true)
        try await transport.start(identity: captureIdentity)
        let engine = hardware.update { $0.graphs[0] }
        inject([Array(repeating: 0.25, count: 480)], into: engine.read().lease!.context,
               at: 0, rate: 24000, interleaved: false, timeFlags: [.sampleTimeValid])
        try await transport.beginPlayback(captureIdentity.playback)
        _ = try await transport.enqueuePlayback(
            NativeVoicePCM16.encode(Array(repeating: 0.25, count: 960)), identity: captureIdentity.playback
        )
        _ = try await transport.finishPlayback(identity: captureIdentity.playback)
        _ = engine.render(2048, sampleTime: 0, hostTime: 0, flags: 1)
        _ = try await transport.bridgeService(maxCaptureFrames: 2048)
        await transport.close()
        let result = await transport.readback()!.sameFrameDiagnostics!
        check(result.sinkSpansWithoutTime == 1 && result.sourceFactsWithoutTime == 1,
              "missing host timestamps remain unknown in both directions")
        check(result.inputs[0].sink?.hostTimeNanoseconds == nil && result.renders[0].hostTimeNanoseconds == nil,
              "no fabricated HostTime in evidence")
        check(!result.complete && result.missingInputs == 0, "time comparability is independent of PCM coverage")
    }

    private static func impulseContentAlignment() throws {
        for rate in [16_000.0, 24_000.0, 44_100.0, 48_000.0] {
            let converter = try NativeVoiceStreamingSRC(inputRate: rate, outputRate: 24_000)
            // Markers bracket varying chunk boundaries and a late marker arrives in the flush at non-unity rates.
            let markers = [37, 311, 743, 1195]
            var input = Array(repeating: Float(0), count: 1200)
            for marker in markers { input[marker] = 0.9 }
            var result: [Float] = []
            var offset = 0
            for count in [100, 183, 115, 219, 267, 316] {
                result += try converter.append(Array(input[offset ..< offset + count]))
                offset += count
            }
            let beforeFlush = result.count
            result += try converter.finish()
            check(beforeFlush + (rate == 24_000 ? 0 : 1) <= result.count
                      && result.count == Int(Double(input.count) * 24_000 / rate),
                  "actual release and flush preserve duration at \(rate)")
            for marker in markers {
                let expected = Double(marker) * 24_000 / rate
                let center = Int(expected.rounded())
                let window = max(0, center - 8) ..< min(result.count, center + 9)
                let peak = window.max { abs(result[$0]) < abs(result[$1]) }!
                check(abs(Double(peak) - expected) <= 1 && abs(result[peak]) > 0.2,
                      "actual impulse landmark follows the content coordinate at \(rate)")
                if marker == markers.last, rate != 24_000 {
                    check(peak >= beforeFlush, "tail marker is attributed to content received before the flush")
                }
            }
            if rate == 24_000 {
                check(converter.sameFramePrimeInfo == nil, "unity-rate copy has no applicable SRC prime metadata")
            }
        }
    }

    private static func quantizationAndAdmission() throws {
        let config = NVTRTConfig(capture_channels: 1, capture_channel: 0, max_callback_frames: 32,
                                 capture_interleaved: true, timebase_numerator: 1, timebase_denominator: 1,
                                 capture_capacity: 32, playback_capacity: 32,
                                 configuration_id: 9, capture_token: 1, playback_token: 1)
        let context = nvt_rt_create(config)!
        defer { nvt_rt_destroy(context) }
        let diagnostic = NativeVoiceSameFrameDiagnostics(context: context)
        let samples: [Float] = [1.25, -1.5, Float(1) / 32768, 0]
        diagnostic.recordPacket(.init(bytes: NativeVoicePCM16.encode(samples), identity: captureIdentity.capture,
                                       segment: 7, sampleCount: 0, hostTimeNanoseconds: nil, timingStatus: .unknown),
                                samples: samples)
        let packet = diagnostic.report(terminal: "closed", pendingTail: 0, discardedTail: 0).packets[0]
        check(packet.positiveEndpointFrames == 1 && packet.negativeEndpointFrames == 1, "PCM16 clipping endpoints")
        check(packet.beforeQuantization.overScale == 2 && packet.pcm16.overScale == 0, "pre-quantization Float32 preserved")
        check(packet.quantizationDifference.peak == 0.5, "measured clipping difference")
        let flag = NativeVoiceSameFrameLaunch.argument
        check(NativeVoiceSameFrameLaunch.isAllowed(["Aftelle", flag], authorized: true), "explicit allowed launch")
        for args in [["Aftelle"], ["Aftelle", flag, "--apple-native-voice-acoustic-lab"],
                     ["Aftelle", flag + "=yes"], ["Aftelle", flag, flag]] {
            check(!NativeVoiceSameFrameLaunch.isAllowed(args, authorized: true), "reject non-canonical launch")
        }
        check(NativeVoiceSameFrameLaunch.isRequested(["Aftelle", flag + "=yes"]), "malformed launch fails closed in router")
        check(!NativeVoiceSameFrameLaunch.isAllowed(["Aftelle", flag], authorized: false), "device gate still applies")
    }
}
