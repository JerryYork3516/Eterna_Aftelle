#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
import CoreAudio
import Foundation

nonisolated struct NativeVoiceOnsetHistory {
    enum Arm: String, CaseIterable, Encodable, Sendable {
        case firstVoiced = "A", shortGap = "B", longGap = "C"

        func voices(_ position: Position) -> Bool {
            position == .target || (self == .shortGap && position == .near) || (self == .longGap && position == .far)
        }
    }

    enum Position: String, CaseIterable, Encodable, Sendable { case far, near, target }
    enum Cue: Equatable { case waiting, speak, quiet, ending }

    struct Plan: Encodable, Sendable {
        let farNanoseconds: UInt64 = 1_000_000_000
        let nearNanoseconds: UInt64 = 9_000_000_000
        let targetNanoseconds: UInt64 = 15_000_000_000
        let scoreNanoseconds: UInt64 = 15_000_000_000
        let quietAfterNanoseconds: UInt64 = 11_000_000_000
        let slotFrames: Int = 114_032
        let serviceAllowanceNanoseconds: UInt64 = 250_000_000
        let clearBudgetNanoseconds: UInt64 = 50_000_000

        var slotNanoseconds: UInt64 { UInt64(slotFrames) * 1_000_000_000 / 24000 }

        func age(of position: Position) -> UInt64 {
            switch position {
            case .far: farNanoseconds
            case .near: nearNanoseconds
            case .target: targetNanoseconds
            }
        }
    }

    struct Clock: Sendable {
        let now: @Sendable () -> UInt64
        let pause: @Sendable () async throws -> Void

        static let live = Self(now: { AudioConvertHostTimeToNanos(AudioGetCurrentHostTime()) },
                               pause: { try await Task.sleep(for: .milliseconds(5)) })
    }

    struct Slot: Encodable, Sendable {
        let position: Position
        let voiced: Bool
        let pcmBytes: Int
        let playback: NativeVoiceIdentity.Playback
        var plannedHostNanoseconds: UInt64?
        var firstEnqueueRequestHostNanoseconds: UInt64?
        var firstConsumption: NativeVoiceRenderFact?
        var consumptionOffsetNanoseconds: Int64?
        var firstNonzero: NativeVoiceRenderFact?
        var firstNonzeroHostNanoseconds: UInt64?
        var digitalEOS: NativeVoiceRenderFact?
        var submittedFrames: UInt64 = 0
    }

    enum Outcome: String, Encodable, Sendable {
        case pending, finished, stopped, invalid, failed
        case cleanupFailed = "cleanup_failed"
    }

    enum Issue: String, Error, Encodable, Sendable {
        case captureNotReady, captureDiscontinuity, transportLoss, missedSlot, invalidRenderTime
        case firstConsumptionOutOfBudget, missingEOS, unexpectedContent, incompleteScore, incompleteDiagnostics
        case graphStartFailed, transportFailed, cancelled, cleanupFailed
    }

    struct Evidence: Encodable, Sendable {
        let experimentID: UUID
        let arm: Arm
        let capture: NativeVoiceIdentity.Capture
        let plan: Plan
        let physicalWitness = "PENDING"
        var slots: [Slot]
        var graphReadyHostNanoseconds: UInt64?
        var scoreFirstPacketHostNanoseconds: UInt64?
        var speakCueHostNanoseconds: UInt64?
        var quietCueHostNanoseconds: UInt64?
        var stoppedHostNanoseconds: UInt64?
        var outcome: Outcome = .pending
        var issue: Issue?
        var cancelPlayback: NativeVoiceIdentity.Playback?
        var clearRequestedHostNanoseconds: UInt64?
        var clearObservedHostNanoseconds: UInt64?
        var clearResult: String?
    }

    static let residentSHA256 = "774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea"
    @MainActor private static var nextIdentity: UInt64 = 2

    let identity: NativeVoiceIdentity
    private let resident: Data
    private let silence: Data
    private(set) var evidence: Evidence
    private(set) var recording: NativeVoiceSameFrameCapture?
    private var nextSlot = 0
    private var activeSlot: Int?
    private var sentBytes = 0
    private var queuedEOS = false
    private var captureSegment: UInt64?
    private var captureSampleCount: UInt64 = 0
    private var captureReady = false

    static func acceptsResident(_ pcm: Data, sha256: String) -> Bool {
        sha256 == residentSHA256 && pcm.count == Plan().slotFrames * 2
    }

    @MainActor
    init(experimentID: UUID, arm: Arm, resident: Data) {
        let base = Self.nextIdentity
        Self.nextIdentity += 4 // Three playback identities and one reserved cancellation successor.
        let authority = NativeVoiceIdentity.Authority(runtimeGeneration: 0, routeEpoch: 0, configurationID: base)
        identity = .init(authority: authority, captureGeneration: base, captureToken: base,
                         playbackEpoch: base, playbackToken: base)
        self.resident = resident
        silence = Data(count: resident.count)
        let slots = Position.allCases.enumerated().map { index, position in
            let token = base + UInt64(index)
            return Slot(position: position, voiced: arm.voices(position), pcmBytes: resident.count,
                        playback: .init(authority: authority, epoch: token, token: token))
        }
        evidence = .init(experimentID: experimentID, arm: arm, capture: identity.capture, plan: Plan(), slots: slots)
    }

    @MainActor
    mutating func run(
        using graph: AppleNativeVoiceTransport, clock: Clock = .live, cue: (Cue) -> Void
    ) async -> (any Error)? {
        var failure: (any Error)?
        do {
            try Task.checkCancellation()
            try await graph.start(identity: identity)
            let ready = clock.now()
            evidence.graphReadyHostNanoseconds = ready
            for index in evidence.slots.indices {
                let position = evidence.slots[index].position
                evidence.slots[index].plannedHostNanoseconds = ready + evidence.plan.age(of: position)
            }
            let outputRate = try await graph.configuredGraph().plan.render.sampleRate
            cue(.waiting)
            try await measure(using: graph, clock: clock, outputRate: outputRate, cue: cue)
            try Task.checkCancellation()
            evidence.outcome = .finished
        } catch is CancellationError {
            evidence.outcome = .stopped
            evidence.issue = .cancelled
            await cancel(using: graph, clock: clock)
        } catch let issue as Issue {
            evidence.outcome = .invalid
            evidence.issue = issue
        } catch {
            evidence.outcome = .failed
            evidence.issue = evidence.graphReadyHostNanoseconds == nil ? .graphStartFailed : .transportFailed
            failure = error
        }
        cue(.ending)
        await graph.close()
        evidence.stoppedHostNanoseconds = clock.now()
        if evidence.outcome == .finished {
            let result = await graph.readback()
            if !hasCoverage(result) {
                evidence.outcome = .invalid
                evidence.issue = .incompleteDiagnostics
            }
        }
        return failure
    }

    mutating func cleanupFailed() {
        evidence.outcome = .cleanupFailed
        evidence.issue = .cleanupFailed
    }
}

private extension NativeVoiceOnsetHistory {
    @MainActor
    mutating func measure(
        using graph: AppleNativeVoiceTransport, clock: Clock, outputRate: Double, cue: (Cue) -> Void
    ) async throws {
        let target = evidence.slots[2].plannedHostNanoseconds!
        let scoreEnd = target + evidence.plan.scoreNanoseconds
        let quietAt = target + evidence.plan.quietAfterNanoseconds
        while true {
            try Task.checkCancellation()
            let batch = try await graph.bridgeService(maxCaptureFrames: 8192)
            try Task.checkCancellation()
            try observe(batch.packets, target: target)
            try observe(batch, outputRate: outputRate)
            let now = clock.now()
            try await feed(using: graph, clock: clock, now: now, cue: cue)
            if now >= quietAt, evidence.quietCueHostNanoseconds == nil {
                evidence.quietCueHostNanoseconds = now
                cue(.quiet)
            }
            if now >= scoreEnd {
                if now > scoreEnd + evidence.plan.serviceAllowanceNanoseconds { throw Issue.incompleteScore }
                if nextSlot == evidence.slots.count, activeSlot == nil,
                   recording?.needsPackets == false { return }
            }
            try await clock.pause()
        }
    }

    @MainActor
    mutating func feed(
        using graph: AppleNativeVoiceTransport, clock: Clock, now: UInt64, cue: (Cue) -> Void
    ) async throws {
        try await beginDueSlot(using: graph, clock: clock, now: now, cue: cue)
        guard let index = activeSlot else { return }
        let slot = evidence.slots[index]
        let deadline = slot.plannedHostNanoseconds! + evidence.plan.slotNanoseconds
            + evidence.plan.serviceAllowanceNanoseconds
        guard now <= deadline else { throw Issue.missingEOS }
        let pcm = slot.voiced ? resident : silence
        if sentBytes < pcm.count {
            let end = min(pcm.count, sentBytes + 4800)
            let submittedAt = clock.now()
            if try await graph.enqueuePlayback(pcm.subdata(in: sentBytes ..< end), identity: slot.playback) {
                if sentBytes == 0 { evidence.slots[index].firstEnqueueRequestHostNanoseconds = submittedAt }
                sentBytes = end
            }
        } else if !queuedEOS {
            queuedEOS = try await graph.finishPlayback(identity: slot.playback)
        }
    }

    @MainActor
    mutating func beginDueSlot(
        using graph: AppleNativeVoiceTransport, clock: Clock, now: UInt64, cue: (Cue) -> Void
    ) async throws {
        guard evidence.slots.indices.contains(nextSlot),
              let planned = evidence.slots[nextSlot].plannedHostNanoseconds, now >= planned
        else { return }
        guard activeSlot == nil else { throw Issue.missingEOS }
        guard now <= planned + evidence.plan.serviceAllowanceNanoseconds else { throw Issue.missedSlot }
        guard captureReady else { throw Issue.captureNotReady }
        let slot = evidence.slots[nextSlot]
        try await graph.beginPlayback(slot.playback)
        activeSlot = nextSlot
        nextSlot += 1
        sentBytes = 0
        queuedEOS = false
        if slot.position == .target {
            evidence.speakCueHostNanoseconds = clock.now()
            cue(.speak)
        }
    }

    mutating func observe(_ packets: [NativeVoiceCapturePacket], target: UInt64) throws {
        for packet in packets {
            guard packet.identity == identity.capture, captureSegment == nil || packet.segment == captureSegment,
                  packet.sampleCount == captureSampleCount, packet.bytes.count == 960
            else { throw Issue.captureDiscontinuity }
            captureSegment = packet.segment
            captureSampleCount += 480
            if packet.timingStatus == .valid, let host = packet.hostTimeNanoseconds {
                captureReady = true
                if recording == nil, host >= target {
                    guard host - target <= evidence.plan.serviceAllowanceNanoseconds
                    else { throw Issue.incompleteScore }
                    evidence.scoreFirstPacketHostNanoseconds = host
                    recording = .init(identity: identity.capture, firstSampleCount: packet.sampleCount)
                }
            }
            recording?.append([packet])
        }
    }

    mutating func observe(_ batch: AppleNativeVoiceTransport.ServiceBatch, outputRate: Double) throws {
        let progress = batch.progress
        guard progress.underrunFrames == 0, progress.captureDroppedFrames == 0,
              progress.captureOverflowEvents == 0, progress.droppedRenderFacts == 0, progress.rejectedOutputFrames == 0
        else { throw Issue.transportLoss }
        guard let index = activeSlot else { return }
        var slot = evidence.slots[index]
        defer { evidence.slots[index] = slot }
        for fact in batch.render where fact.playback == slot.playback {
            try observe(fact, in: &slot, outputRate: outputRate)
        }
        let deadline = slot.plannedHostNanoseconds! + evidence.plan.slotNanoseconds
            + evidence.plan.serviceAllowanceNanoseconds
        if let eosHost = slot.digitalEOS?.hostTimeNanoseconds, eosHost > deadline { throw Issue.missingEOS }
        if slot.digitalEOS != nil, progress.token == slot.playback.token, progress.renderHandoff {
            guard queuedEOS, sentBytes == slot.pcmBytes, slot.firstConsumption != nil,
                  slot.voiced == (slot.firstNonzero != nil)
            else { throw Issue.unexpectedContent }
            activeSlot = nil
        }
    }

    func observe(_ fact: NativeVoiceRenderFact, in slot: inout Slot, outputRate: Double) throws {
        guard fact.submittedFrames > 0 || fact.isDigitalHandoff else { return }
        let first = fact.submittedFrames > 0 && slot.firstConsumption == nil
        if first { slot.firstConsumption = fact }
        if fact.isDigitalHandoff { slot.digitalEOS = fact }
        guard let host = fact.hostTimeNanoseconds, fact.hostTime != nil, fact.sampleTime != nil
        else { throw Issue.invalidRenderTime }
        if first {
            let skew = Int64(clamping: host) - Int64(clamping: slot.plannedHostNanoseconds!)
            slot.consumptionOffsetNanoseconds = skew
            guard skew.magnitude <= evidence.plan.serviceAllowanceNanoseconds
            else { throw Issue.firstConsumptionOutOfBudget }
        }
        slot.submittedFrames += UInt64(fact.submittedFrames)
        if let span = fact.nonzeroSpan, slot.firstNonzero == nil {
            slot.firstNonzero = fact
            let offset = (Double(span.lowerBound) * 1e9 / outputRate).rounded()
            slot.firstNonzeroHostNanoseconds = host + UInt64(offset)
            guard slot.voiced else { throw Issue.unexpectedContent }
        }
    }

    @MainActor
    mutating func cancel(using graph: AppleNativeVoiceTransport, clock: Clock) async {
        guard let index = activeSlot else {
            evidence.clearResult = "not_required"
            return
        }
        let current = evidence.slots[index].playback
        let successor = NativeVoiceIdentity.Playback(
            authority: current.authority, epoch: current.epoch + 1, token: current.token + 1
        )
        let requestTime = clock.now()
        evidence.clearRequestedHostNanoseconds = requestTime
        let deadline = requestTime + evidence.plan.clearBudgetNanoseconds
        do {
            try await graph.cancelPlayback(current, replacingWith: successor)
            evidence.cancelPlayback = successor
        } catch {
            evidence.clearResult = "request_failed"
            return
        }
        // The caller's cancelled task cannot sleep while the real consumer clears the ring.
        evidence.clearObservedHostNanoseconds = await Task.detached {
            while clock.now() <= deadline {
                guard let progress = try? await graph.progress() else { return nil as UInt64? }
                let observed = clock.now()
                if progress.token == successor.token, progress.renderClearAcknowledged, observed <= deadline {
                    return observed
                }
                guard observed < deadline else { return nil }
                do { try await clock.pause() } catch { return nil }
            }
            return nil
        }.value
        evidence.clearResult = evidence.clearObservedHostNanoseconds == nil ? "unobserved" : "acknowledged"
    }

    func hasCoverage(_ result: NativeVoiceTransportReadback?) -> Bool {
        guard let result, result.state == "closed", result.identity.capture == identity.capture,
              let trace = result.sameFrameDiagnostics, trace.allocated else { return false }
        return trace.droppedSinkBlocks == 0 && trace.droppedSinkFrames == 0 && trace.droppedSourceFacts == 0
            && trace.rejectedCaptureFrames == 0 && trace.underrunFrames == 0 && trace.rejectedSourceFrames == 0
            && trace.missingInputs == 0 && trace.unjoinedBlocks == 0 && trace.missingMappings == 0
            && trace.droppedEntries == 0 && trace.conversionFailures == 0
    }
}
#endif
