import Darwin
import VPRecorder
import VPReferenceCore

enum VPAClockSampling {
    static func record(_ phase: VPAClockPair.Phase, into evidence: inout VPAEvidence?) throws {
        try evidence?.recordClockPair(VPAClockSampling.read(phase: phase))
        let maximum = vp_recorder_ticks_for_seconds(VPARequest.maximumSeconds)
        let tick = vp_recorder_now_tick()
        try VPAWindow.requireAdmission(
            armTick: evidence?.armTick, currentTick: tick, maximumTicks: maximum)
        if phase == .quietStart, let arm = evidence?.armTick {
            let elapsed = Double(tick - arm) / Double(vp_recorder_ticks_for_seconds(1))
            guard elapsed <= VPARequest.prewarmDeadlineSeconds else {
                throw EngineeringFailure(stage: .recorder, code: .experimentPrewarmInvalid)
            }
        }
    }

    static func read(phase: VPAClockPair.Phase) -> VPAClockPair {
        var timebase = mach_timebase_info_data_t()
        if mach_timebase_info(&timebase) != KERN_SUCCESS {
            timebase.numer = 0
            timebase.denom = 0
        }
        let before = mach_absolute_time()
        let continuous = mach_continuous_time()
        let after = mach_absolute_time()
        return VPAClockPair(
            phase: phase, absoluteBeforeTick: before, continuousTick: continuous, absoluteAfterTick: after,
            timebaseNumerator: timebase.numer, timebaseDenominator: timebase.denom)
    }
}
