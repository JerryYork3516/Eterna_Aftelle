#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
import AudioToolbox
import Foundation

nonisolated enum NativeVoiceSameFrameLaunch {
    static let argument = "--apple-native-voice-same-frame-diagnostics"

    static func isRequested(_ arguments: [String]) -> Bool {
        #if NATIVE_VOICE_DIRECT_VPIO
        if NativeVoiceDirectVPIOLaunch.isRequested(arguments) {
            return true
        }
        #endif
        return arguments.dropFirst().contains { $0 == argument || $0.hasPrefix(argument + "=") }
    }

    static func isAllowed(_ arguments: [String], authorized: Bool) -> Bool {
        authorized && (arguments.dropFirst().elementsEqual([argument]) || usesDirectVPIO(arguments))
    }

    private static func usesDirectVPIO(_ arguments: [String]) -> Bool {
        #if NATIVE_VOICE_DIRECT_VPIO
        NativeVoiceDirectVPIOLaunch.isAllowed(arguments, authorized: true)
        #else
        false
        #endif
    }

    static func backendTag(_ arguments: [String]) -> String? {
        #if NATIVE_VOICE_DIRECT_VPIO
        usesDirectVPIO(arguments) ? "direct_voice_processing_io" : nil
        #else
        nil
        #endif
    }

    @MainActor
    static func makeTransport(_ arguments: [String]) -> AppleNativeVoiceTransport {
        let limits = AppleNativeVoiceTransport.Limits(sameFrameDiagnostics: true)
        #if NATIVE_VOICE_DIRECT_VPIO
        if usesDirectVPIO(arguments) {
            return .directVPIO(limits: limits)
        }
        #endif
        return .macOS(limits: limits)
    }
}

nonisolated protocol NativeVoiceSameFrameSystemReading {
    func sameFrameSystemState() -> NativeVoiceSameFrameDiagnostics.SystemState
}

extension NativeVoiceSystemEngine: NativeVoiceSameFrameSystemReading {}

/// One serial Worker owns the statistics. Raw copies are consumed in memory and never encoded.
final nonisolated class NativeVoiceSameFrameDiagnostics {
    struct Level: Encodable, Sendable {
        let frames, zeros, fullScale, overScale, nonFinite: Int
        let rms, peak: Double?

        init(_ samples: some Collection<Float>) {
            var zeros = 0, full = 0, over = 0, invalid = 0
            var energy = 0.0, peak = 0.0
            for sample in samples {
                guard sample.isFinite else { invalid += 1; continue }
                let value = abs(Double(sample))
                if value == 0 { zeros += 1 }
                if value >= 1 { full += 1 }
                if value > 1 { over += 1 }
                energy += value * value
                peak = max(peak, value)
            }
            frames = samples.count
            self.zeros = zeros
            fullScale = full
            overScale = over
            nonFinite = invalid
            let finite = frames - invalid
            rms = finite > 0 ? sqrt(energy / Double(finite)) : nil
            self.peak = finite > 0 ? peak : nil
        }
    }

    struct Difference: Encodable, Sendable {
        let bitIdenticalFrames, finitePairs: Int
        let peak, rms, correlation: Double?

        init(_ samples: some Collection<Float>, _ reference: [Float]) {
            var identical = 0, pairs = 0
            var sumA = 0.0, sumB = 0.0, sumAA = 0.0, sumBB = 0.0, sumAB = 0.0
            var errorEnergy = 0.0, maxError = 0.0
            for (sample, other) in zip(samples, reference) {
                if sample.bitPattern == other.bitPattern { identical += 1 }
                guard sample.isFinite, other.isFinite else { continue }
                let a = Double(sample), b = Double(other), error = abs(a - b)
                pairs += 1
                sumA += a
                sumB += b
                sumAA += a * a
                sumBB += b * b
                sumAB += a * b
                errorEnergy += error * error
                maxError = max(maxError, error)
            }
            bitIdenticalFrames = identical
            finitePairs = pairs
            peak = pairs > 0 ? maxError : nil
            rms = pairs > 0 ? sqrt(errorEnergy / Double(pairs)) : nil
            let n = Double(pairs)
            let varianceA = n * sumAA - sumA * sumA
            let varianceB = n * sumBB - sumB * sumB
            correlation = pairs > 1 && varianceA > 0 && varianceB > 0
                ? max(-1, min(1, (n * sumAB - sumA * sumB) / sqrt(varianceA * varianceB))) : nil
        }
    }

    struct Channel: Encodable, Sendable {
        let level: Level
        let versusSelected: Difference
    }

    struct Input: Encodable, Sendable {
        let sink: NativeVoiceSinkFact?
        let blockID, playbackToken: UInt64?
        let segment: UInt64
        let nativeFrames: Range<Int>
        let selectedChannel: UInt32?
        let selected: Level
        let channels: [Channel]?
    }

    struct Release: Encodable, Sendable {
        let capture: NativeVoiceIdentity.Capture
        let segment: UInt64
        let frames24k: Range<Int>
        let nativeContentFrames: Range<Int>
        let acceptedNativeFrames, unreleased24kFrames, discardedFilterTail24kFrames: Int
        let nativeRate: Double
        let leadingPrimeFrames, trailingPrimeFrames: UInt32?
        let selectedForContent: Level?
        let afterSRC: Level
        let finishing: Bool
    }

    struct Packet: Encodable, Sendable {
        let capture: NativeVoiceIdentity.Capture
        let segment, sampleCount: UInt64
        let hostTimeNanoseconds: UInt64?
        let timingStatus: String
        let beforeQuantization, pcm16: Level
        let positiveEndpointFrames, negativeEndpointFrames: Int
        let quantizationDifference: Difference
    }

    struct Render: Encodable, Sendable {
        let configurationID, playbackToken: UInt64
        let sampleTime: Double?
        let hostTime, hostTimeNanoseconds: UInt64?
        let frameCount, submittedFrames, nonzeroFrames, timeFlags, flags: UInt32
        let nonzeroSpan: Range<UInt32>?
        let digitalEOS: Bool

        init(_ fact: NVTRenderFact) {
            configurationID = fact.configuration_id
            playbackToken = fact.playback_token
            timeFlags = fact.time_flags
            let time = AudioTimeStampFlags(rawValue: timeFlags)
            sampleTime = time.contains(.sampleTimeValid) && fact.sample_time.isFinite ? fact.sample_time : nil
            hostTime = time.contains(.hostTimeValid) && fact.host_time != 0 ? fact.host_time : nil
            hostTimeNanoseconds = fact.host_time_ns != 0 ? fact.host_time_ns : nil
            frameCount = fact.frame_count
            submittedFrames = fact.submitted_frames
            nonzeroFrames = fact.nonzero_frames
            flags = fact.flags
            digitalEOS = fact.flags & UInt32(NVT_RENDER_END) != 0
            nonzeroSpan = nonzeroFrames > 0 ? fact.first_nonzero ..< fact.nonzero_end : nil
        }
    }

    struct DeviceControls: Encodable, Sendable {
        let device: UInt32
        let direction: String
        let elements: [Element]
        let channelControlsTruncated: Bool

        struct Element: Encodable, Sendable {
            let number: UInt32
            let volumeScalar: Float?
            let volumeDecibels: Float?
            let muted: Bool?
        }
    }

    struct SystemState: Encodable, Sendable {
        let uptimeNanoseconds: UInt64
        let activeMicMode, preferredMicMode: Int?
        let defaults: NativeVoiceGraphSnapshot.Defaults?
        let inputUnitDevice, outputUnitDevice: UInt32?
        let inputActiveMembers, outputActiveMembers: [UInt32]?
        let voiceProcessingRequested, voiceProcessingReadback: NativeVoiceProcessingReadback?
        let ducking: Ducking?
        let deviceControls: [DeviceControls]

        struct Ducking: Encodable, Sendable {
            let advanced: Bool
            let level: Int
        }
    }

    struct Report: Encodable, Sendable {
        let schemaVersion = 1
        let complete: Bool
        let allocated: Bool
        let observedNativeFrames: Int
        let acceptedNativeFrames: UInt64
        let droppedSinkBlocks, droppedSinkFrames, pendingSinkBlocks, droppedSourceFacts: UInt64
        let rejectedCaptureFrames, underrunFrames, rejectedSourceFrames: UInt64
        let missingInputs, unjoinedBlocks, missingMappings, droppedEntries, conversionFailures: Int
        let sinkSpansWithoutTime, sourceFactsWithoutTime: Int
        let pendingCaptureTail24kFrames, discardedCaptureTail24kFrames: Int
        let initialSystemState, finalSystemState: SystemState?
        let inputs: [Input]
        let releases: [Release]
        let packets: [Packet]
        let renders: [Render]
    }

    private let context: OpaquePointer
    private let allocated: Bool
    private var inputs: [Input] = []
    private var releases: [Release] = []
    private var packets: [Packet] = []
    private var renders: [Render] = []
    private var budget = 16_384
    private var missingInputs = 0
    private var unjoinedBlocks = 0
    private var missingMappings = 0
    private var droppedEntries = 0
    private(set) var conversionFailures = 0
    private var observedNativeFrames = 0
    private var sinkSpansWithoutTime = 0
    private var sourceFactsWithoutTime = 0
    private var selectedContent: [Float] = []
    private var contentStart = 0
    private var contentSegment: UInt64?
    private let contentCapacity = 32_768
    var initialSystemState: SystemState?
    var finalSystemState: SystemState?

    init(context: OpaquePointer) {
        self.context = context
        allocated = nvt_rt_enable_same_frame(context)
        selectedContent.reserveCapacity(contentCapacity)
    }

    func recordInput(_ frame: NVTFrame?, selected: [Float], capture: NativeVoiceIdentity.Capture,
                     segment: UInt64, nativeStart: Int) {
        observedNativeFrames += selected.count
        if contentSegment != segment || contentStart + selectedContent.count != nativeStart
            || selectedContent.count + selected.count > contentCapacity {
            selectedContent.removeAll(keepingCapacity: true)
            contentStart = nativeStart
            contentSegment = segment
        }
        if selected.count <= contentCapacity { selectedContent.append(contentsOf: selected) }

        var channels: [Channel]?
        var selectedChannel: UInt32?
        var playback: UInt64?
        if let frame, frame.ingress.diagnostic_block != 0 {
            var block = NVTSameFrameBlock()
            while nvt_rt_peek_same_frame(context, &block), block.id < frame.ingress.diagnostic_block {
                nvt_rt_release_same_frame(context)
                unjoinedBlocks += 1
            }
            let end = Int(frame.offset) + selected.count
            if block.id == frame.ingress.diagnostic_block, block.capture_token == capture.token,
               block.configuration_id == capture.authority.configurationID, end <= Int(block.frames),
               let raw = block.samples {
                defer { if end == Int(block.frames) { nvt_rt_release_same_frame(context) } }
                guard reserve(1 + Int(block.channels)) else { return }
                selectedChannel = block.selected_channel
                playback = block.playback_token
                channels = (0 ..< Int(block.channels)).map { channel in
                    let offset = Int(frame.offset)
                    let samples = selected.indices.map { index in
                        block.interleaved ? raw[(offset + index) * Int(block.channels) + channel]
                            : raw[channel * Int(block.frames) + offset + index]
                    }
                    return Channel(level: Level(samples), versusSelected: Difference(samples, selected))
                }
            }
        }
        if channels == nil {
            missingInputs += 1
            guard reserve(1) else { return }
        }
        let sink = frame.map { NativeVoiceSinkFact(frame: $0, identity: capture) }
        if sink?.sampleTime == nil || sink?.hostTimeNanoseconds == nil { sinkSpansWithoutTime += 1 }
        inputs.append(Input(
            sink: sink,
            blockID: frame?.ingress.diagnostic_block, playbackToken: playback, segment: segment,
            nativeFrames: nativeStart ..< nativeStart + selected.count, selectedChannel: selectedChannel,
            selected: Level(selected), channels: channels
        ))
    }

    // Attribute the actual released output to its content interval, never to the latest input callback.
    // The span is in the input content clock. An SRC filter can use samples on either side of its boundaries.
    func recordRelease(_ samples: [Float], start: Int, converter: NativeVoiceStreamingSRC,
                       capture: NativeVoiceIdentity.Capture, segment: UInt64, finishing: Bool = false) {
        let end = start + samples.count
        let first = min(converter.inputFrames,
                        Int((Double(start) * converter.inputRate / converter.outputRate).rounded(.down)))
        let last = min(converter.inputFrames,
                       Int((Double(end) * converter.inputRate / converter.outputRate).rounded(.down)))
        let lo = first - contentStart, hi = last - contentStart
        let exists = contentSegment == segment && lo >= 0 && hi <= selectedContent.count
        let selected = exists && hi > lo ? Level(selectedContent[lo ..< hi]) : nil
        if !samples.isEmpty && !exists { missingMappings += 1 }
        if contentSegment == segment, hi > 0 {
            let remove = min(hi, selectedContent.count)
            selectedContent.removeFirst(remove)
            contentStart += remove
        }
        guard reserve(1) else { return }
        let prime = converter.sameFramePrimeInfo
        releases.append(Release(
            capture: capture, segment: segment, frames24k: start ..< end,
            nativeContentFrames: first ..< last, acceptedNativeFrames: converter.inputFrames,
            unreleased24kFrames: converter.unreleasedContentFrames,
            discardedFilterTail24kFrames: converter.discardedFilterTailFrames, nativeRate: converter.inputRate,
            leadingPrimeFrames: prime?.leadingFrames, trailingPrimeFrames: prime?.trailingFrames,
            selectedForContent: selected, afterSRC: Level(samples), finishing: finishing
        ))
    }

    func recordPacket(_ packet: NativeVoiceCapturePacket, samples: [Float]) {
        guard reserve(1) else { return }
        guard let pcm = try? NativeVoicePCM16.decode(packet.bytes), pcm.count == samples.count else {
            droppedEntries += 1
            return
        }
        packets.append(Packet(
            capture: packet.identity, segment: packet.segment, sampleCount: packet.sampleCount,
            hostTimeNanoseconds: packet.hostTimeNanoseconds, timingStatus: packet.timingStatus.rawValue,
            beforeQuantization: Level(samples), pcm16: Level(pcm),
            positiveEndpointFrames: pcm.count(where: { $0 == Float(32767) / 32768 }),
            negativeEndpointFrames: pcm.count(where: { $0 == -1 }),
            quantizationDifference: Difference(pcm, samples)
        ))
    }

    func recordRender(_ fact: NVTRenderFact, configuration: UInt64) {
        guard fact.configuration_id == configuration,
              fact.nonzero_frames != 0 || fact.flags & UInt32(NVT_RENDER_END | NVT_RENDER_CLEAR | NVT_RENDER_UNDERRUN) != 0,
              reserve(1) else { return }
        let render = Render(fact)
        if render.sampleTime == nil || render.hostTimeNanoseconds == nil { sourceFactsWithoutTime += 1 }
        renders.append(render)
    }

    func conversionFailed() { conversionFailures += 1 }

    func report(terminal: String, pendingTail: Int, discardedTail: Int) -> Report {
        let sink = nvt_rt_same_frame_stats(context)
        let transport = nvt_rt_stats(context)
        let complete = terminal == "closed" && allocated && observedNativeFrames > 0
            && sink.dropped_blocks == 0 && sink.pending_blocks == 0 && transport.dropped_render_facts == 0
            && transport.rejected_input_frames == 0 && transport.underrun_frames == 0
            && transport.rejected_output_frames == 0 && UInt64(observedNativeFrames) == transport.accepted_input_frames
            && missingInputs == 0 && unjoinedBlocks == 0 && missingMappings == 0
            && droppedEntries == 0 && conversionFailures == 0
            && sinkSpansWithoutTime == 0 && sourceFactsWithoutTime == 0
        return Report(
            complete: complete, allocated: allocated, observedNativeFrames: observedNativeFrames,
            acceptedNativeFrames: transport.accepted_input_frames,
            droppedSinkBlocks: sink.dropped_blocks, droppedSinkFrames: sink.dropped_frames,
            pendingSinkBlocks: sink.pending_blocks, droppedSourceFacts: transport.dropped_render_facts,
            rejectedCaptureFrames: transport.rejected_input_frames, underrunFrames: transport.underrun_frames,
            rejectedSourceFrames: transport.rejected_output_frames, missingInputs: missingInputs,
            unjoinedBlocks: unjoinedBlocks, missingMappings: missingMappings, droppedEntries: droppedEntries,
            conversionFailures: conversionFailures, sinkSpansWithoutTime: sinkSpansWithoutTime,
            sourceFactsWithoutTime: sourceFactsWithoutTime, pendingCaptureTail24kFrames: pendingTail,
            discardedCaptureTail24kFrames: discardedTail, initialSystemState: initialSystemState,
            finalSystemState: finalSystemState, inputs: inputs, releases: releases, packets: packets, renders: renders
        )
    }

    private func reserve(_ entries: Int) -> Bool {
        guard entries <= budget else { droppedEntries += 1; return false }
        budget -= entries
        return true
    }
}
#endif
