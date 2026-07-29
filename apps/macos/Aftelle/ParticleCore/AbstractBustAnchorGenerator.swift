import Foundation
import simd

struct AbstractBustTuning: Equatable {
    var headWidth: Float
    var headHeight: Float
    var headPosition: SIMD3<Float>
    var neckWidth: Float
    var neckLength: Float
    var shoulderWidth: Float
    var shoulderSlope: Float
    var torsoLength: Float
    var torsoTaper: Float
    var frontBackThickness: Float
    var asymmetryStrength: Float
    var contourSoftening: Float

    static let systemDefault = AbstractBustTuning(
        headWidth: 0.30,
        headHeight: 0.40,
        headPosition: SIMD3<Float>(0, 0.62, 0),
        neckWidth: 0.16,
        neckLength: 0.24,
        shoulderWidth: 0.60,
        shoulderSlope: 0.10,
        torsoLength: 0.76,
        torsoTaper: 0.22,
        frontBackThickness: 0.28,
        asymmetryStrength: 0.018,
        contourSoftening: 0.82
    )
}

enum AbstractBustAnchorRegion: CaseIterable {
    case head
    case neck
    case shouldersAndChest
    case torso
}

struct AbstractBustAnchorGenerator {
    static func generate(
        count: Int,
        seed: UInt64,
        tuning: AbstractBustTuning = .systemDefault
    ) -> [SIMD3<Float>] {
        guard count > 0 else { return [] }

        let ranges = regionRanges(count: count)
        var anchors = Array(repeating: SIMD3<Float>.zero, count: count)
        for index in anchors.indices {
            let region = region(at: index, ranges: ranges)
            let range = ranges[region] ?? (0..<count)
            anchors[index] = anchor(
                region: region,
                localIndex: index - range.lowerBound,
                localCount: range.count,
                seed: seed,
                tuning: tuning
            )
        }
        return anchors
    }

    static func regionRanges(
        count: Int
    ) -> [AbstractBustAnchorRegion: Range<Int>] {
        let headEnd = Int(Float(count) * 0.26)
        let neckEnd = headEnd + Int(Float(count) * 0.06)
        let shouldersEnd = neckEnd + Int(Float(count) * 0.26)
        return [
            .head: 0..<headEnd,
            .neck: headEnd..<neckEnd,
            .shouldersAndChest: neckEnd..<shouldersEnd,
            .torso: shouldersEnd..<count
        ]
    }

    private static func region(
        at index: Int,
        ranges: [AbstractBustAnchorRegion: Range<Int>]
    ) -> AbstractBustAnchorRegion {
        for region in AbstractBustAnchorRegion.allCases
            where ranges[region]?.contains(index) == true {
            return region
        }
        return .torso
    }

    private static func anchor(
        region: AbstractBustAnchorRegion,
        localIndex: Int,
        localCount: Int,
        seed: UInt64,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        switch region {
        case .head:
            return headAnchor(
                index: localIndex,
                count: localCount,
                phase: seededPhase(seed: seed, salt: 0x11),
                tuning: tuning
            )
        case .neck:
            return neckAnchor(
                index: localIndex,
                count: localCount,
                phase: seededPhase(seed: seed, salt: 0x22),
                tuning: tuning
            )
        case .shouldersAndChest:
            return shouldersAndChestAnchor(
                index: localIndex,
                count: localCount,
                phase: seededPhase(seed: seed, salt: 0x33),
                tuning: tuning
            )
        case .torso:
            return torsoAnchor(
                index: localIndex,
                count: localCount,
                phase: seededPhase(seed: seed, salt: 0x44),
                tuning: tuning
            )
        }
    }

    private static func headAnchor(
        index: Int,
        count: Int,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let sample = fibonacciSphere(index: index, count: count, phase: phase)
        let headDepth = tuning.frontBackThickness * 0.82
        var anchor = SIMD3<Float>(
            sample.x * tuning.headWidth,
            sample.y * tuning.headHeight,
            sample.z * headDepth
        ) + tuning.headPosition
        anchor.x += tuning.asymmetryStrength
            * (0.22 + 0.18 * sample.y)
        return anchor
    }

    private static func neckAnchor(
        index: Int,
        count: Int,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let u = unitSample(index: index, count: count)
        let softened = softenedUnit(u, amount: tuning.contourSoftening)
        let angle = goldenAngle * Float(index) + phase
        let width = tuning.neckWidth * mix(0.86, 1.08, softened)
        let depth = tuning.frontBackThickness * mix(0.48, 0.58, softened)
        let top = tuning.headPosition.y - tuning.headHeight + 0.025
        var anchor = SIMD3<Float>(
            cos(angle) * width,
            top - u * tuning.neckLength,
            sin(angle) * depth
        )
        anchor.x += tuning.asymmetryStrength * 0.18
        return anchor
    }

    private static func shouldersAndChestAnchor(
        index: Int,
        count: Int,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let u = unitSample(index: index, count: count)
        let softened = softenedUnit(u, amount: tuning.contourSoftening)
        let angle = goldenAngle * Float(index) + phase
        let shoulderRise = smoothstep(0, 0.34, softened)
        let chestSettle = smoothstep(0.34, 1, softened)
        let width = mix(
            tuning.neckWidth * 1.02,
            tuning.shoulderWidth,
            shoulderRise
        ) * mix(1, 0.88, chestSettle)
        let depth = tuning.frontBackThickness
            * mix(0.62, 1.02, shoulderRise)
            * mix(1, 0.94, chestSettle)
        let normalizedX = cos(angle)
        let outerShoulderDrop = tuning.shoulderSlope
            * pow(abs(normalizedX), 1.7)
            * (1 - chestSettle)
        let top = tuning.headPosition.y
            - tuning.headHeight
            - tuning.neckLength
            + 0.08
        var anchor = SIMD3<Float>(
            normalizedX * width,
            top - u * 0.47 - outerShoulderDrop,
            sin(angle) * depth
        )
        anchor.z += max(0, sin(angle))
            * sin(.pi * softened)
            * tuning.frontBackThickness
            * 0.08
        applyAsymmetry(to: &anchor, phase: phase, tuning: tuning)
        return anchor
    }

    private static func torsoAnchor(
        index: Int,
        count: Int,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let u = unitSample(index: index, count: count)
        let softened = softenedUnit(u, amount: tuning.contourSoftening)
        let angle = goldenAngle * Float(index) + phase
        let width = tuning.shoulderWidth
            * 0.88
            * mix(1, 1 - tuning.torsoTaper, softened)
        let depth = tuning.frontBackThickness * mix(0.94, 0.76, softened)
        let top = tuning.headPosition.y
            - tuning.headHeight
            - tuning.neckLength
            - 0.39
        var anchor = SIMD3<Float>(
            cos(angle) * width,
            top - u * tuning.torsoLength,
            sin(angle) * depth
        )
        applyAsymmetry(to: &anchor, phase: phase, tuning: tuning)
        return anchor
    }

    private static func applyAsymmetry(
        to anchor: inout SIMD3<Float>,
        phase: Float,
        tuning: AbstractBustTuning
    ) {
        let sideScale: Float = anchor.x >= 0
            ? 1 + tuning.asymmetryStrength
            : 1 - tuning.asymmetryStrength
        anchor.x *= sideScale
        anchor.x += tuning.asymmetryStrength
            * 0.24
            * sin(anchor.y * 3.7 + phase)
    }

    private static func fibonacciSphere(
        index: Int,
        count: Int,
        phase: Float
    ) -> SIMD3<Float> {
        let u = unitSample(index: index, count: count)
        let y = 1 - 2 * u
        let radius = sqrt(max(0, 1 - y * y))
        let angle = goldenAngle * Float(index) + phase
        return SIMD3<Float>(
            cos(angle) * radius,
            y,
            sin(angle) * radius
        )
    }

    private static func unitSample(index: Int, count: Int) -> Float {
        (Float(index) + 0.5) / Float(max(count, 1))
    }

    private static func softenedUnit(_ value: Float, amount: Float) -> Float {
        mix(value, value * value * (3 - 2 * value), clamped(amount))
    }

    private static func smoothstep(
        _ edge0: Float,
        _ edge1: Float,
        _ value: Float
    ) -> Float {
        let unit = clamped((value - edge0) / max(edge1 - edge0, 0.000_01))
        return unit * unit * (3 - 2 * unit)
    }

    private static func mix(
        _ lhs: Float,
        _ rhs: Float,
        _ amount: Float
    ) -> Float {
        lhs + (rhs - lhs) * amount
    }

    private static func clamped(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    private static func seededPhase(seed: UInt64, salt: UInt64) -> Float {
        var value = seed &+ salt &* 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        let unit = Float(Double(value) / Double(UInt64.max))
        return unit * 2 * .pi
    }

    private static let goldenAngle: Float = 2.399_963_1
}
