import Foundation
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPATimingEvidenceTests: XCTestCase {
    func testFinalPairCanBeLocallyValidButGlobalAdmissionFails() throws {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        evidence.armTick = 0
        for (index, phase) in VPAClockPair.Phase.allCases.prefix(5).enumerated() {
            let origin = UInt64(index) * 3_000_000_000
            try evidence.recordClockPair(
                VPAClockPair(
                    phase: phase, absoluteBeforeTick: origin, continuousTick: origin + 100,
                    absoluteAfterTick: origin + 200, timebaseNumerator: 1, timebaseDenominator: 1))
        }
        let pair = VPAClockPair(
            phase: .beforeStop, absoluteBeforeTick: 15_900_000_000, continuousTick: 16_000_000_000,
            absoluteAfterTick: 16_100_000_000, timebaseNumerator: 1, timebaseDenominator: 1)
        try evidence.recordClockPair(pair)
        XCTAssertEqual(pair.bracketSeconds, 0.2)
        XCTAssertThrowsError(
            try VPAWindow.requireAdmission(
                armTick: evidence.armTick, currentTick: 16_100_000_000, maximumTicks: 16_000_000_000)
        ) { XCTAssertEqual(($0 as? EngineeringFailure)?.diagnostic.code, "EXPERIMENT_WINDOW_INVALID") }
        XCTAssertEqual(evidence.clockPairs.count, 6)
        XCTAssertFalse(evidence.postRollCompleted)
        XCTAssertFalse(evidence.isTimingComplete)
    }

    func testSixEventPairsNeedPrewarmAndPostRoll() throws {
        var evidence = VPAEvidence(registrationSHA256: String(repeating: "a", count: 64))
        for (index, phase) in VPAClockPair.Phase.allCases.enumerated() {
            try evidence.recordClockPair(pair(phase, origin: UInt64(index + 1) * 1_000))
        }
        evidence.windowsCompleted = true
        XCTAssertFalse(evidence.isTimingComplete)
        evidence.prewarmStartTick = 1_200
        evidence.prewarmEndTick = 1_500
        evidence.prewarmInputRecords = 1
        evidence.prewarmRenderRecords = 1
        evidence.prewarmCompleted = true
        evidence.postRollCompleted = true
        XCTAssertTrue(evidence.isTimingComplete)
        XCTAssertEqual(evidence.clockEvidenceStatus, "EVENT_LOCAL_BRACKETS_GLOBAL_MAPPING_NOT_USED")
        XCTAssertEqual(evidence.postRollSeconds, 0.5)
        XCTAssertFalse(evidence.sourceQualificationGranted)
    }

    func testWrongPhaseRetainsRawPairAndFailsClosed() {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        XCTAssertThrowsError(try evidence.recordClockPair(pair(.playRequest, origin: 1_000)))
        XCTAssertEqual(evidence.clockPairs.count, 1)
        XCTAssertEqual(evidence.clockPairs.first?.phase, .playRequest)
        XCTAssertEqual(evidence.clockEvidenceStatus, "INVALID_PAIR")
        XCTAssertFalse(evidence.isTimingComplete)
    }

    func testInvalidClockEvidenceCannotBeClearedByLaterPairs() {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        XCTAssertThrowsError(try evidence.recordClockPair(pair(.playRequest, origin: 1_000)))
        XCTAssertThrowsError(try evidence.recordClockPair(pair(.playRequest, origin: 2_000)))
        XCTAssertEqual(evidence.clockPairs.count, 1)
        XCTAssertEqual(evidence.clockEvidenceStatus, "INVALID_PAIR")
        XCTAssertTrue(evidence.clockInvalid)
    }

    func testRepeatedPhaseTimeCannotClaimProgress() throws {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        try evidence.recordClockPair(pair(.beforeStart, origin: 1_000))
        XCTAssertThrowsError(try evidence.recordClockPair(pair(.quietStart, origin: 1_000)))
        XCTAssertEqual(evidence.clockEvidenceStatus, "CLOCK_ORDER_OR_UNITS_CHANGED")
    }

    func testBackwardClockOrChangedUnitsAreNotSmoothed() throws {
        for numerator: UInt32 in [125, 1] {
            var evidence = VPAEvidence(registrationSHA256: "synthetic")
            try evidence.recordClockPair(pair(.beforeStart, origin: 1_000))
            let next = VPAClockPair(
                phase: .quietStart, absoluteBeforeTick: numerator == 125 ? 900 : 2_000,
                continuousTick: 2_100, absoluteAfterTick: 2_002,
                timebaseNumerator: numerator, timebaseDenominator: 3)
            XCTAssertThrowsError(try evidence.recordClockPair(next))
            XCTAssertEqual(evidence.clockPairs.count, 2)
            XCTAssertEqual(evidence.clockEvidenceStatus, "CLOCK_ORDER_OR_UNITS_CHANGED")
        }
    }

    func testDisjointOffsetsAreRetainedWithoutGlobalMappingAssumption() throws {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        try evidence.recordClockPair(pair(.beforeStart, origin: 1_000))
        let changed = VPAClockPair(
            phase: .quietStart, absoluteBeforeTick: 2_000, continuousTick: 2_200, absoluteAfterTick: 2_002,
            timebaseNumerator: 125, timebaseDenominator: 3)
        try evidence.recordClockPair(changed)
        XCTAssertEqual(evidence.clockPairs.count, 2)
        XCTAssertEqual(evidence.quietStartTick, changed.continuousTick)
        XCTAssertFalse(evidence.clockInvalid)
    }

    func testAllLocalEventBracketsRetainedEvenWhenOffsetsChangeBetweenEvents() throws {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        for (index, phase) in VPAClockPair.Phase.allCases.enumerated() {
            let origin = UInt64(index + 1) * 1_000
            try evidence.recordClockPair(
                VPAClockPair(
                    phase: phase, absoluteBeforeTick: origin, continuousTick: origin * 2,
                    absoluteAfterTick: origin + 4, timebaseNumerator: 1, timebaseDenominator: 1))
        }
        XCTAssertEqual(evidence.clockEvidenceStatus, "EVENT_LOCAL_BRACKETS_GLOBAL_MAPPING_NOT_USED")
        XCTAssertFalse(evidence.clockInvalid)
        XCTAssertEqual(evidence.postRollStartTick, evidence.clockPairs[4].continuousTick)
    }

    func testClockCollectionCannotExceedSixPairs() throws {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        for (index, phase) in VPAClockPair.Phase.allCases.enumerated() {
            try evidence.recordClockPair(pair(phase, origin: UInt64(index + 1) * 1_000))
        }
        XCTAssertThrowsError(try evidence.recordClockPair(pair(.beforeStop, origin: 7_000)))
        XCTAssertEqual(evidence.clockPairs.count, 6)
        XCTAssertEqual(evidence.clockEvidenceStatus, "PAIR_LIMIT_EXCEEDED")
    }

    func testSlowOrInvalidPairRetainsRawEvidence() {
        for numerator: UInt32 in [0, 1] {
            var evidence = VPAEvidence(registrationSHA256: "synthetic")
            let next = VPAClockPair(
                phase: .beforeStart, absoluteBeforeTick: 100, continuousTick: 101,
                absoluteAfterTick: 300_000_100, timebaseNumerator: numerator, timebaseDenominator: 1)
            XCTAssertThrowsError(try evidence.recordClockPair(next))
            XCTAssertEqual(evidence.clockPairs.count, 1)
            XCTAssertEqual(evidence.clockPairs[0].absoluteAfterTick, 300_000_100)
            XCTAssertEqual(evidence.clockEvidenceStatus, "INVALID_PAIR")
        }
    }

    func testThrowingOptionalMutationPreservesPairInActualManifest() throws {
        let fixture = try SourceProbeFixture()
        fixture.manifest.prepareVPA(registrationSHA256: "synthetic")
        XCTAssertThrowsError(
            try fixture.manifest.vpaExperiment?.recordClockPair(pair(.playRequest, origin: 1_000)))
        XCTAssertEqual(fixture.manifest.vpaExperiment?.clockPairs.count, 1)
        XCTAssertEqual(fixture.manifest.vpaExperiment?.clockEvidenceStatus, "INVALID_PAIR")
    }

    func testOrdinaryAndSourceProbeManifestsKeepTimingFieldsAbsent() throws {
        let fixture = try SourceProbeFixture()
        for sourceProbe in [true, false] {
            if !sourceProbe { fixture.manifest.sourceProbe = nil }
            let data = try JSONEncoder().encode(fixture.manifest)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertNil(json["vpa_experiment"])
            XCTAssertFalse(encoded.contains("clockPairs"))
            XCTAssertFalse(encoded.contains("postRoll"))
        }
    }

    func testEveryEventFieldUsesItsOwnPairedContinuousTick() throws {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        for (index, phase) in VPAClockPair.Phase.allCases.enumerated() {
            try evidence.recordClockPair(pair(phase, origin: UInt64(index + 1) * 1_000))
        }
        XCTAssertEqual(evidence.quietStartTick, evidence.clockPairs[1].continuousTick)
        XCTAssertEqual(evidence.playRequestTick, evidence.clockPairs[2].continuousTick)
        XCTAssertEqual(evidence.plannedTailStartTick, evidence.clockPairs[3].continuousTick)
        XCTAssertEqual(evidence.postRollStartTick, evidence.clockPairs[4].continuousTick)
        XCTAssertEqual(evidence.postRollEndTick, evidence.clockPairs[5].continuousTick)
        XCTAssertEqual(evidence.normalStopBoundaryTick, evidence.clockPairs[5].continuousTick)
    }

    func testMissingQuietOrPostRollBoundaryCannotClaimTimingComplete() throws {
        for omitted in [VPAClockPair.Phase.quietStart, .postRollStart] {
            var evidence = VPAEvidence(registrationSHA256: "synthetic")
            for (index, phase) in VPAClockPair.Phase.allCases.enumerated() {
                if phase == omitted { break }
                try evidence.recordClockPair(pair(phase, origin: UInt64(index + 1) * 1_000))
            }
            evidence.windowsCompleted = true
            evidence.postRollCompleted = true
            XCTAssertFalse(evidence.isTimingComplete)
        }
    }

    func testBoundaryFieldCannotBeReplacedWithAnUnpairedLaterRead() throws {
        var evidence = VPAEvidence(registrationSHA256: "synthetic")
        for (index, phase) in VPAClockPair.Phase.allCases.enumerated() {
            try evidence.recordClockPair(pair(phase, origin: UInt64(index + 1) * 1_000))
        }
        evidence.prewarmStartTick = 1_200
        evidence.prewarmEndTick = 1_500
        evidence.prewarmInputRecords = 1
        evidence.prewarmRenderRecords = 1
        evidence.prewarmCompleted = true
        evidence.windowsCompleted = true
        evidence.postRollCompleted = true
        XCTAssertTrue(evidence.isTimingComplete)
        evidence.quietStartTick = (evidence.quietStartTick ?? 0) + 1
        XCTAssertFalse(evidence.isTimingComplete)
    }

    private func pair(_ phase: VPAClockPair.Phase, origin: UInt64) -> VPAClockPair {
        VPAClockPair(
            phase: phase, absoluteBeforeTick: origin, continuousTick: origin + 100,
            absoluteAfterTick: origin + 2, timebaseNumerator: 125, timebaseDenominator: 3)
    }
}
