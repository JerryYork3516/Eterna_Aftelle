import Foundation

nonisolated enum NativeVoiceTimingStatus: String {
    case unknown = "UNKNOWN"
    case invalid = "INVALID"
    case valid = "VALID"
}

/// Sample continuity and observed host mapping are independent. Worker-owned.
nonisolated struct NativeVoiceClock {
    struct Observation {
        let discontinuity: Bool
        let status: NativeVoiceTimingStatus
    }

    let sampleRate: Double
    private var expectedSample: Int64?
    private var anchorSample: Int64?
    private var anchorHost: UInt64?
    private var previousHost: UInt64?
    private var confirmations = 0
    private(set) var status: NativeVoiceTimingStatus = .unknown
    static let freshnessNanoseconds: UInt64 = 500_000_000
    /// One native sample plus integer-nanosecond rounding; no empirical tolerance tuning.
    var mappingErrorNanoseconds: Double {
        1_000_000_000 / sampleRate + 1
    }

    mutating func observe(
        sampleTime: Int64?,
        frames: Int,
        hostTime: UInt64?,
        droppedFrames: UInt64 = 0,
        independentHostObservation: Bool = true
    ) -> Observation {
        let end = sampleTime?.addingReportingOverflow(Int64(frames))
        let discontinuity = droppedFrames > 0 || sampleTime == nil || end?.overflow == true
            || (expectedSample != nil && expectedSample != sampleTime)
        expectedSample = end?.overflow == false ? end?.partialValue : nil
        if discontinuity {
            clearMapping()
        }
        guard let sampleTime, let hostTime, end?.overflow == false, frames > 0 else {
            clearMapping()
            return Observation(discontinuity: discontinuity, status: status)
        }
        let predicted = mappedHost(sampleTime: sampleTime)
        let consistent = predicted.map { abs(Double(hostTime) - Double($0)) <= mappingErrorNanoseconds } ?? false
        if let previousHost, hostTime <= previousHost || !consistent {
            anchorSample = sampleTime
            anchorHost = hostTime
            confirmations = independentHostObservation ? 1 : 0
            status = .invalid
        } else if anchorSample == nil {
            anchorSample = sampleTime
            anchorHost = hostTime
            confirmations = independentHostObservation ? 1 : 0
            status = .unknown
        } else {
            if independentHostObservation {
                confirmations = min(3, confirmations + 1)
            }
            status = confirmations == 3 ? .valid : .unknown
        }
        previousHost = hostTime
        return Observation(discontinuity: discontinuity, status: status)
    }

    func qualifiedHost(sampleTime: Int64, offsetFrames: Double = 0) -> UInt64? {
        status == .valid ? mappedHost(sampleTime: sampleTime, offsetFrames: offsetFrames) : nil
    }

    static func isFresh(hostTime: UInt64?, now: UInt64) -> Bool {
        guard let hostTime, hostTime <= now else { return false }
        return now - hostTime <= freshnessNanoseconds
    }

    private func mappedHost(sampleTime: Int64, offsetFrames: Double = 0) -> UInt64? {
        guard let anchorSample, let anchorHost, sampleRate.isFinite, sampleRate > 0 else { return nil }
        let delta = sampleTime.subtractingReportingOverflow(anchorSample)
        guard !delta.overflow else { return nil }
        let offset = (Double(delta.partialValue) + offsetFrames) * 1_000_000_000 / sampleRate
        guard offset.isFinite, abs(offset) < Double(UInt64.max) else { return nil }
        let magnitude = UInt64(abs(offset).rounded())
        let time = offset >= 0 ? anchorHost.addingReportingOverflow(magnitude)
            : anchorHost.subtractingReportingOverflow(magnitude)
        return time.overflow ? nil : time.partialValue
    }

    private mutating func clearMapping() {
        anchorSample = nil
        anchorHost = nil
        previousHost = nil
        confirmations = 0
        status = .unknown
    }
}
