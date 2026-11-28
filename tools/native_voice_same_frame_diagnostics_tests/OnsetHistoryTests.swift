@preconcurrency import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

private typealias History = NativeVoiceOnsetHistory

extension SameFrameTests {
    static func onsetHistory() async throws {
        let experiment = UUID()
        let frames = History.Plan().slotFrames
        let signal = Array(repeating: Float(0), count: 24000)
            + Array(repeating: Float(0.25), count: frames - 24000)
        let pcm = NativeVoicePCM16.encode(signal)
        check(History.acceptsResident(pcm, sha256: History.residentSHA256)
            && !History.acceptsResident(pcm.dropLast(2), sha256: History.residentSHA256)
            && !History.acceptsResident(pcm, sha256: "different file"), "fixed SHA and PCM length admission")
        var identities = Set<UInt64>()
        var retired: FakeVoiceEngine?
        for arm in History.Arm.allCases {
            retired = await checkHistoryArm(arm, experiment: experiment, pcm: pcm, retired: retired,
                                            identities: &identities)
        }

        for fault in HistoryTestDriver.Fault.allCases where fault != .none {
            try await historyFault(fault, experiment: experiment, pcm: pcm)
        }
        let (failedGraph, failedHardware) = graph(channelCount: 1, interleaved: false, rate: 24000, diagnostics: true)
        failedHardware.update { $0.failure = .start }
        var failed = History(experimentID: experiment, arm: .firstVoiced, resident: pcm)
        let returned = await failed.run(using: failedGraph, clock: HistoryTestDriver(failedHardware).clock) { _ in }
        check(returned as? FakeVoiceFailure == .start && failed.evidence.issue == .graphStartFailed,
              "start failure returned and classified")
        let failedEngine = failedHardware.update { $0.graphs[0] }
        let terminal = await failedGraph.state
        check(failedEngine.read().stops == 1 && terminal == .closed,
              "startup rollback closes the partially started graph")
        check(failedEngine.render(480).allSatisfy { $0 == 0 }, "late callback after startup rollback rejected")
    }

    private static func checkHistoryArm(
        _ arm: History.Arm, experiment: UUID, pcm: Data, retired: FakeVoiceEngine?,
        identities: inout Set<UInt64>
    ) async -> FakeVoiceEngine {
        let (graph, hardware) = graph(channelCount: 1, interleaved: false, rate: 24000, diagnostics: true)
        let driver = HistoryTestDriver(hardware, retired: retired)
        var history = History(experimentID: experiment, arm: arm, resident: pcm)
        var cues: [History.Cue] = []
        let error = await history.run(using: graph, clock: driver.clock) { cues.append($0) }
        let evidence = history.evidence
        check(error == nil && evidence.outcome == .finished,
              "arm \(arm.rawValue) finished with \(String(describing: evidence.issue))")
        check(evidence.experimentID == experiment && evidence.arm == arm, "paired experiment and arm identity")
        let ages = evidence.slots.map { $0.plannedHostNanoseconds! - evidence.graphReadyHostNanoseconds! }
        check(ages == [1, 9, 15].map { UInt64($0) * 1_000_000_000 }, "all arms use the same graph ages")
        let expectedVoicing: [Bool] = [arm == .longGap, arm == .shortGap, true]
        check(evidence.slots.map(\.voiced) == expectedVoicing, "far and near voicing chosen by arm")
        checkHistorySlots(evidence, identity: history.identity, driver: driver, identities: &identities)
        check(cues == [.waiting, .speak, .quiet, .ending], "bounded participant cue order")
        check(evidence.speakCueHostNanoseconds == evidence.slots[2].plannedHostNanoseconds
            && evidence.quietCueHostNanoseconds! - evidence.speakCueHostNanoseconds! == 11_000_000_000,
            "target and stop-speaking cues share one clock")
        let capture = history.recording!.finish(endedNormally: true)
        let score = NativeVoicePCM16.encode(Array(repeating: 0.5, count: 360_000))
        check(capture.summary.firstSampleCount == 360_000 && capture.pcm == score,
              "target 15 seconds only, original capture sample indices")
        check(evidence.scoreFirstPacketHostNanoseconds == evidence.speakCueHostNanoseconds,
              "score anchors to actual qualified Worker PCM")
        let readback = await graph.readback()
        check(readback?.identity.capture == history.identity.capture && readback?.route.active == false,
              "one capture identity until close")
        let engine = hardware.update { $0.graphs[0] }
        check(hardware.update { $0.graphs.count } == 1 && engine.read().starts == 1 && engine.read().stops == 1,
              "one graph start and stop per arm")
        if retired != nil {
            check(driver.retiredCallbacksRejected, "previous arm's late capture and playback callbacks rejected")
        }
        return engine
    }

    private static func checkHistorySlots(
        _ evidence: History.Evidence, identity: NativeVoiceIdentity,
        driver: HistoryTestDriver, identities: inout Set<UInt64>
    ) {
        let arm = evidence.arm
        let frames = evidence.plan.slotFrames
        for (index, slot) in evidence.slots.enumerated() {
            check(identities.insert(slot.playback.token).inserted
                && slot.playback.epoch == slot.playback.token
                && slot.playback.authority == evidence.capture.authority, "distinct legal slot identity")
            check(slot.playback.token == identity.playback.token + UInt64(index), "ordered slot token")
            check(slot.pcmBytes == frames * 2 && slot.submittedFrames == UInt64(frames), "equal real PCM consumed")
            let expectedOffset: Int64 = index == 0 ? 2_000_000 : 22_000_000
            let observedOffset = slot.consumptionOffsetNanoseconds!
            check(slot.firstEnqueueRequestHostNanoseconds == slot.plannedHostNanoseconds
                && abs(observedOffset - expectedOffset) < 100,
                "arm \(arm.rawValue) \(slot.position) consumer offset \(observedOffset) ns")
            check(observedOffset == Int64(slot.firstConsumption!.hostTimeNanoseconds!)
                - Int64(slot.plannedHostNanoseconds!), "actual timing evidence is not copied from the plan")
            check(slot.digitalEOS?.isDigitalHandoff == true, "real EOS receipt for every slot")
            check((slot.firstNonzeroHostNanoseconds != nil) == slot.voiced, "actual nonzero output matches slot")
            check(driver.nonzeroFrames[slot.playback.token, default: 0] == (slot.voiced ? frames - 24000 : 0),
                  "slot waveform passes Ring and Worker without skipping silence")
            if slot.voiced {
                let before = Int64(slot.firstConsumption!.hostTimeNanoseconds!)
                let leading = Int64(slot.firstNonzeroHostNanoseconds!) - before
                check(abs(leading - 1_000_000_000) < 100, "original one-second leading silence preserved")
            }
        }
    }

    private static func historyFault(_ fault: HistoryTestDriver.Fault, experiment: UUID, pcm: Data) async throws {
        let (graph, hardware) = graph(channelCount: 1, interleaved: false, rate: 24000, diagnostics: true)
        let driver = HistoryTestDriver(hardware, fault: fault)
        var history = History(experimentID: experiment, arm: .shortGap, resident: pcm)
        _ = await history.run(using: graph, clock: driver.clock) { _ in }
        let evidence = history.evidence
        switch fault {
        case .none: preconditionFailure()
        case .cancel, .unobservedClear:
            let acknowledged = fault == .cancel
            check(evidence.outcome == .stopped && evidence.issue == .cancelled, "cancelled arm receipt")
            check(evidence.cancelPlayback?.token == evidence.slots[1].playback.token + 1,
                  "clear uses a successor identity")
            check(evidence.clearResult == (acknowledged ? "acknowledged" : "unobserved")
                && (evidence.clearObservedHostNanoseconds != nil) == acknowledged,
                "only a real callback can confirm clear")
            if let observed = evidence.clearObservedHostNanoseconds {
                check(observed - evidence.clearRequestedHostNanoseconds! <= 50_000_000, "bounded clear observation")
            }
            let replacement = evidence.cancelPlayback!.token
            check(driver.nonzeroFrames[replacement, default: 0] == 0, "cancelled queue does not leak")
        case .invalidTime:
            check(evidence.outcome == .invalid && evidence.issue == .invalidRenderTime,
                  "invalid consumer clock fails")
        case .captureGap:
            check(evidence.outcome == .invalid && evidence.issue == .captureDiscontinuity,
                  "capture gap invalidates arm")
        case .lostEOS:
            check(evidence.outcome == .invalid && evidence.issue == .missingEOS
                && evidence.slots[1].firstEnqueueRequestHostNanoseconds == nil, "no transition based on an ACK alone")
        case .late:
            check(evidence.outcome == .invalid && evidence.issue == .missedSlot
                && evidence.slots[0].firstEnqueueRequestHostNanoseconds == nil, "late slot cannot move the plan")
        case .route:
            check(evidence.outcome == .failed && evidence.issue == .transportFailed,
                  "route invalidation aborts the arm")
        case .loss:
            check(evidence.outcome == .invalid && evidence.issue == .transportLoss,
                  "rejected output invalidates arm")
        }
        check(evidence.slots[2].firstEnqueueRequestHostNanoseconds == nil,
              "failed or cancelled arm stops before target")
        let engine = hardware.update { $0.graphs[0] }
        check(engine.read().stops == 1 && engine.render(480).allSatisfy { $0 == 0 },
              "one rollback and no output from retired callbacks")
    }
}

@MainActor
private final class HistoryTestDriver {
    enum Fault: CaseIterable {
        case none, cancel, unobservedClear, invalidTime, captureGap, lostEOS, late, route, loss
    }

    private let hardware: FakeVoiceHardware
    private let fault: Fault
    private let retired: FakeVoiceEngine?

    private nonisolated let time = Mutex<UInt64>(1_000_000_000)
    private var tick = 0
    private var cancelled = false
    private(set) var nonzeroFrames: [UInt64: Int] = [:]
    private(set) var retiredCallbacksRejected = false

    init(_ hardware: FakeVoiceHardware, fault: Fault = .none, retired: FakeVoiceEngine? = nil) {
        self.hardware = hardware
        self.fault = fault
        self.retired = retired
    }

    var clock: History.Clock {
        .init(now: { self.time.withLock { $0 } }, pause: { try await self.step() })
    }

    private func step() throws {
        let engine = hardware.update { $0.graphs[0] }
        if tick == 0, let retired {
            let oldContext = retired.read().lease!.context
            let count = nvt_rt_stats(oldContext).accepted_input_frames
            SameFrameTests.inject([Array(repeating: 0.25, count: 480)], into: oldContext,
                                  at: 0, rate: 24000, interleaved: false)
            retiredCallbacksRejected = retired.render(480).allSatisfy { $0 == 0 }
                && nvt_rt_stats(oldContext).accepted_input_frames == count
        }
        if tick >= 455, !cancelled, fault == .cancel || fault == .unobservedClear {
            cancelled = true
            throw CancellationError()
        }
        if tick == 100, fault == .route { engine.read().configurationChanged?() }

        let sample = tick * 480
        let host = UInt64(tick) * 20_000_000 + 1_000_000_000
        let context = engine.read().lease!.context
        if tick != 75 || fault != .captureGap {
            let input = [Float](repeating: tick < 750 ? 0.125 : 0.5, count: 480)
            SameFrameTests.inject([input], into: context, at: sample, rate: 24000, interleaved: false)
        }
        if !cancelled || fault != .unobservedClear {
            let before = nvt_rt_stats(context)
            let output = engine.render(
                tick == 75 && fault == .loss ? 8192 : 480,
                sampleTime: Double(sample), hostTime: AudioConvertNanosToHostTime(host + 2_000_000),
                flags: fault == .invalidTime ? 1 : 3
            )
            nonzeroFrames[before.active_token, default: 0] += output.filter { $0 != 0 }.count
            if fault == .lostEOS, nvt_rt_stats(context).rendered_end_token != before.rendered_end_token {
                var fact = NVTRenderFact()
                while nvt_rt_take_render_fact(context, &fact) {}
            }
        }
        tick += 1
        time.withLock { $0 = host + (fault == .late && tick == 50 ? 320_000_000 : 20_000_000) }
    }
}
