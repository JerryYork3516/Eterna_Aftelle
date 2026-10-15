import AudioToolbox
import VPRecorder
import VPReferenceCore
import XCTest

final class VPAWindowCoverageTests: XCTestCase {
    func testBothContinuousStreamsBracketAllFormalWindows() {
        let proof = makeProof()
        XCTAssertTrue(proof.formalWindowsCovered)
        XCTAssertTrue(proof.windows.allSatisfy(\.covered))
        XCTAssertEqual(proof.windows.map(\.name), ["quiet", "play", "tail", "postRoll"])
        XCTAssertEqual(proof.windows.map(\.required), [true, true, true, false])
    }

    func testMissingWarmupStartCannotBeReplacedByLaterQuietSamples() {
        XCTAssertFalse(makeProof(first: 1_100).formalWindowsCovered)
    }

    func testNominalLastBlockEndIsNotAnEndAnchor() {
        let proof = makeProof(last: 14_000)
        XCTAssertFalse(proof.formalWindowsCovered)
        XCTAssertNil(proof.windows[2].inputEnd)
        // The last 100-frame/1kHz block would nominally extend to 14_100; it cannot grant coverage.
    }

    func testDiagnosticPostRollCanBePartialWithoutChangingFormalTail() {
        let proof = makeProof(last: 14_100)
        XCTAssertTrue(proof.formalWindowsCovered)
        XCTAssertFalse(proof.windows[3].covered)
    }

    func testOutermostEventUncertaintyMustBeCovered() {
        let proof = makeProof(first: 1_001, last: 14_601)
        XCTAssertEqual(proof.windows[0].startAbsoluteEarliest, 1_000)
        XCTAssertNil(proof.windows[0].inputStart)
        XCTAssertFalse(proof.windows[0].covered)
    }

    func testNoGlobalOffsetIsUsedToCoverEvents() {
        XCTAssertTrue(makeProof(changingOffsets: true).formalWindowsCovered)
    }

    func testMissingStreamOrExpectedRecordIsUnverified() {
        XCTAssertFalse(makeProof(omitRender: true).formalWindowsCovered)
        var proof = makeProof()
        proof.finish(expectedRecords: proof.recordCount + 1)
        XCTAssertFalse(proof.formalWindowsCovered)
    }

    func testTimeValidityFormatAndSequenceFailuresCannotBeCleared() {
        for kind in 0..<7 {
            var proof = VPAWindowCoverage(clockPairs: pairs())
            var first = identity(host: 900, sample: 0, stream: UInt32(VP_STREAM_INPUT))
            if kind == 0 { first.host_time_valid = false }
            if kind == 1 { first.sample_time_valid = false }
            if kind == 2 { first.format.mSampleRate = .nan }
            if kind == 6 { first.format.mBytesPerFrame = 2 }
            proof.include(first)
            var next = identity(
                host: kind == 3 ? 900 : 1_000, sample: kind == 4 ? 101 : 100, stream: UInt32(VP_STREAM_INPUT))
            if kind == 5 { next.format.mSampleRate = 2_000 }
            proof.include(next)
            proof.finish(expectedRecords: 2)
            XCTAssertFalse(proof.formalWindowsCovered)
        }
    }

    func testSampleTimeOverflowFailsClosed() {
        var proof = VPAWindowCoverage(clockPairs: pairs())
        proof.include(identity(host: 900, sample: Int64.max, stream: UInt32(VP_STREAM_INPUT)))
        proof.include(identity(host: 1_000, sample: 0, stream: UInt32(VP_STREAM_INPUT)))
        proof.finish(expectedRecords: 2)
        XCTAssertEqual(proof.reason, "STREAM_SEQUENCE_UNVERIFIED")
    }

    func testMissingBoundaryIsUnverified() {
        var proof = VPAWindowCoverage(clockPairs: Array(pairs().dropLast()))
        proof.finish(expectedRecords: 0)
        XCTAssertFalse(proof.formalWindowsCovered)
        XCTAssertEqual(proof.reason, "LOCAL_BOUNDARIES_UNVERIFIED")
    }

    func testHugeHostJumpWithOnlyTwoSmallBuffersCannotPass() {
        var proof = VPAWindowCoverage(clockPairs: pairs())
        for stream in [UInt32(VP_STREAM_INPUT), UInt32(VP_STREAM_RENDER)] {
            proof.include(identity(host: 900, sample: 0, stream: stream))
            proof.include(identity(host: 14_600, sample: 100, stream: stream))
        }
        proof.finish(expectedRecords: 4)
        XCTAssertFalse(proof.formalWindowsCovered)
        XCTAssertTrue(proof.windows.allSatisfy { !$0.covered })
    }

    func testShortLocalAbsoluteDurationCannotPassWithSufficientPCM() {
        let proof = makeProof(shortQuiet: true)
        XCTAssertFalse(proof.formalWindowsCovered)
        XCTAssertFalse(proof.windows[0].minimumDurationVerified)
    }

    func testFractionalNativeRateIsNotRoundedIntoAnExactProof() {
        XCTAssertFalse(makeProof(rate: 1_000.5).formalWindowsCovered)
    }

    func testDurationProductOverflowCannotProduceCoverage() {
        let large = pairs().map {
            VPAClockPair(
                phase: $0.phase, absoluteBeforeTick: $0.absoluteBeforeTick * 1_000_000_000,
                continuousTick: $0.absoluteBeforeTick * 1_000_000_000,
                absoluteAfterTick: $0.absoluteBeforeTick * 1_000_000_000,
                timebaseNumerator: UInt32.max, timebaseDenominator: 1)
        }
        var proof = VPAWindowCoverage(clockPairs: large)
        XCTAssertEqual(proof.windows.count, 4)
        XCTAssertFalse(proof.windows[0].minimumDurationVerified)
        proof.finish(expectedRecords: 0)
        XCTAssertFalse(proof.formalWindowsCovered)
    }

    private func makeProof(
        first: UInt64 = 900, last: UInt64 = 14_600, omitRender: Bool = false, changingOffsets: Bool = false,
        shortQuiet: Bool = false, rate: Double = 1_000
    ) -> VPAWindowCoverage {
        var proof = VPAWindowCoverage(clockPairs: pairs(changingOffsets: changingOffsets, shortQuiet: shortQuiet))
        var sample: Int64 = 0
        for host in stride(from: first, through: last, by: 100) {
            var input = identity(host: host, sample: sample, stream: UInt32(VP_STREAM_INPUT))
            input.format.mSampleRate = rate
            proof.include(input)
            if !omitRender {
                var render = identity(host: host, sample: sample, stream: UInt32(VP_STREAM_RENDER))
                render.format.mSampleRate = rate
                proof.include(render)
            }
            sample += 100
        }
        proof.finish(expectedRecords: proof.recordCount)
        return proof
    }

    private func pairs(changingOffsets: Bool = false, shortQuiet: Bool = false) -> [VPAClockPair] {
        zip(VPAClockPair.Phase.allCases, [0, 1_000, shortQuiet ? 2_000 : 3_002, 11_004, 14_006, 14_508]).enumerated()
            .map { index, value in
                VPAClockPair(
                    phase: value.0, absoluteBeforeTick: UInt64(value.1),
                    continuousTick: UInt64(value.1) + UInt64(changingOffsets ? index * 10 : 0),
                    absoluteAfterTick: UInt64(value.1 + 1), timebaseNumerator: 1_000_000, timebaseDenominator: 1)
            }
    }

    private func identity(host: UInt64, sample: Int64, stream: UInt32) -> VPFrameIdentity {
        var value = VPFrameIdentity()
        value.stream_kind = stream
        value.frame_count = 100
        value.sample_time_valid = true
        value.host_time_valid = true
        value.host_time = host
        value.sample_time = sample
        value.format = RecorderFixture.nativeMonoFormat
        value.format.mSampleRate = 1_000
        return value
    }
}
