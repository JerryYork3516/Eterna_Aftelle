import Darwin
import VPReferenceCore

enum VPAClockSampling {
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
