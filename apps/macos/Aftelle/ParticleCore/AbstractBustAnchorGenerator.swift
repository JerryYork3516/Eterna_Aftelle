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
    var neckRootWidthScale: Float
    var chestCurvature: Float
    var headNeckBlend: Float
    var verticalSampleJitter: Float
    var angularJitter: Float
    var radialJitter: Float
    var shoulderDistributionExponent: Float
    var torsoDistributionExponent: Float
    var headParticleRatio: Float
    var neckParticleRatio: Float
    var shoulderParticleRatio: Float

    static let systemDefault = AbstractBustTuning(
        headWidth: 0.265,
        headHeight: 0.34,
        headPosition: SIMD3<Float>(0, 0.59, 0),
        neckWidth: 0.16,
        neckLength: 0.20,
        shoulderWidth: 0.60,
        shoulderSlope: 0.085,
        torsoLength: 0.76,
        torsoTaper: 0.30,
        frontBackThickness: 0.28,
        asymmetryStrength: 0.009,
        contourSoftening: 0.90,
        neckRootWidthScale: 1.20,
        chestCurvature: 0.075,
        headNeckBlend: 0.22,
        verticalSampleJitter: 0.42,
        angularJitter: 0.075,
        radialJitter: 0.012,
        shoulderDistributionExponent: 0.82,
        torsoDistributionExponent: 1.10,
        headParticleRatio: 0.22,
        neckParticleRatio: 0.055,
        shoulderParticleRatio: 0.27
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

        let ranges = regionRanges(count: count, tuning: tuning)
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
        count: Int,
        tuning: AbstractBustTuning = .systemDefault
    ) -> [AbstractBustAnchorRegion: Range<Int>] {
        let headEnd = Int(Float(count) * tuning.headParticleRatio)
        let neckEnd = headEnd
            + Int(Float(count) * tuning.neckParticleRatio)
        let shouldersEnd = neckEnd
            + Int(Float(count) * tuning.shoulderParticleRatio)
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
                seed: seed,
                phase: seededPhase(seed: seed, salt: 0x11),
                tuning: tuning
            )
        case .neck:
            return neckAnchor(
                index: localIndex,
                count: localCount,
                seed: seed,
                phase: seededPhase(seed: seed, salt: 0x22),
                tuning: tuning
            )
        case .shouldersAndChest:
            return shouldersAndChestAnchor(
                index: localIndex,
                count: localCount,
                seed: seed,
                phase: seededPhase(seed: seed, salt: 0x33),
                tuning: tuning
            )
        case .torso:
            return torsoAnchor(
                index: localIndex,
                count: localCount,
                seed: seed,
                phase: seededPhase(seed: seed, salt: 0x44),
                tuning: tuning
            )
        }
    }

    private static func headAnchor(
        index: Int,
        count: Int,
        seed: UInt64,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let sample = fibonacciSphere(
            index: index,
            count: count,
            seed: seed,
            phase: phase,
            tuning: tuning
        )
        let headDepth = tuning.frontBackThickness * 0.82
        var anchor = SIMD3<Float>(
            sample.x * tuning.headWidth,
            sample.y * tuning.headHeight,
            sample.z * headDepth
        ) + tuning.headPosition
        let lowerHead = (1 - sample.y) * 0.5
        let neckBlend = smoothstep(
            1 - tuning.headNeckBlend,
            1,
            lowerHead
        )
        let planarLength = max(
            sqrt(sample.x * sample.x + sample.z * sample.z),
            0.000_01
        )
        let planarDirection = SIMD2<Float>(
            sample.x / planarLength,
            sample.z / planarLength
        )
        anchor.x = mix(
            anchor.x,
            planarDirection.x * tuning.neckWidth * 0.90,
            neckBlend
        )
        anchor.z = mix(
            anchor.z,
            planarDirection.y
                * tuning.frontBackThickness
                * 0.46,
            neckBlend
        )
        anchor.x += tuning.asymmetryStrength
            * (0.22 + 0.18 * sample.y)
        return anchor
    }

    private static func neckAnchor(
        index: Int,
        count: Int,
        seed: UInt64,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let u = stratifiedUnitSample(
            index: index,
            count: count,
            seed: seed,
            salt: 0x221,
            jitter: tuning.verticalSampleJitter
        )
        let softened = softenedUnit(u, amount: tuning.contourSoftening)
        let angle = jitteredAngle(
            index: index,
            seed: seed,
            salt: 0x222,
            phase: phase,
            jitter: tuning.angularJitter
        )
        let radialScale = jitteredRadialScale(
            index: index,
            seed: seed,
            salt: 0x223,
            amount: tuning.radialJitter
        )
        let width = tuning.neckWidth
            * mix(0.90, tuning.neckRootWidthScale, softened)
            * radialScale
        let depth = tuning.frontBackThickness
            * mix(0.46, 0.65, softened)
            * radialScale
        let top = tuning.headPosition.y - tuning.headHeight + 0.02
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
        seed: UInt64,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let u = pow(
            stratifiedUnitSample(
                index: index,
                count: count,
                seed: seed,
                salt: 0x331,
                jitter: tuning.verticalSampleJitter
            ),
            tuning.shoulderDistributionExponent
        )
        let softened = softenedUnit(u, amount: tuning.contourSoftening)
        let angle = jitteredAngle(
            index: index,
            seed: seed,
            salt: 0x332,
            phase: phase,
            jitter: tuning.angularJitter
        )
        let radialScale = jitteredRadialScale(
            index: index,
            seed: seed,
            salt: 0x333,
            amount: tuning.radialJitter
        )
        let shoulderRise = smoothstep(0, 0.42, softened)
        let chestSettle = smoothstep(0.38, 1, softened)
        let chestArc = sin(.pi * softened) * tuning.chestCurvature
        var width = mix(
            tuning.neckWidth * tuning.neckRootWidthScale * 0.96,
            tuning.shoulderWidth,
            shoulderRise
        ) * mix(1, 0.90, chestSettle)
        width *= (1 + chestArc * 0.35) * radialScale
        let depth = tuning.frontBackThickness
            * mix(0.62, 1.02, shoulderRise)
            * mix(1, 0.96, chestSettle)
            * (1 + chestArc)
            * radialScale
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
        seed: UInt64,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let u = pow(
            stratifiedUnitSample(
                index: index,
                count: count,
                seed: seed,
                salt: 0x441,
                jitter: tuning.verticalSampleJitter
            ),
            tuning.torsoDistributionExponent
        )
        let softened = softenedUnit(u, amount: tuning.contourSoftening)
        let angle = jitteredAngle(
            index: index,
            seed: seed,
            salt: 0x442,
            phase: phase,
            jitter: tuning.angularJitter
        )
        let radialScale = jitteredRadialScale(
            index: index,
            seed: seed,
            salt: 0x443,
            amount: tuning.radialJitter
        )
        let chestArc = sin(.pi * softened)
            * tuning.chestCurvature
        let width = tuning.shoulderWidth
            * 0.90
            * mix(1, 1 - tuning.torsoTaper, softened)
            * (1 + chestArc * 0.45)
            * radialScale
        let depth = tuning.frontBackThickness
            * mix(0.96, 0.72, softened)
            * (1 + chestArc * 0.55)
            * radialScale
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
        seed: UInt64,
        phase: Float,
        tuning: AbstractBustTuning
    ) -> SIMD3<Float> {
        let u = stratifiedUnitSample(
            index: index,
            count: count,
            seed: seed,
            salt: 0x111,
            jitter: tuning.verticalSampleJitter
        )
        let y = 1 - 2 * u
        let radius = sqrt(max(0, 1 - y * y))
            * jitteredRadialScale(
                index: index,
                seed: seed,
                salt: 0x113,
                amount: tuning.radialJitter
            )
        let angle = jitteredAngle(
            index: index,
            seed: seed,
            salt: 0x112,
            phase: phase,
            jitter: tuning.angularJitter
        )
        return SIMD3<Float>(
            cos(angle) * radius,
            y,
            sin(angle) * radius
        )
    }

    private static func stratifiedUnitSample(
        index: Int,
        count: Int,
        seed: UInt64,
        salt: UInt64,
        jitter: Float
    ) -> Float {
        let offset = deterministicSignedUnit(
            index: index,
            seed: seed,
            salt: salt
        ) * clamped(jitter) * 0.5
        return min(
            0.999_999,
            max(
                0.000_001,
                (Float(index) + 0.5 + offset)
                    / Float(max(count, 1))
            )
        )
    }

    private static func jitteredAngle(
        index: Int,
        seed: UInt64,
        salt: UInt64,
        phase: Float,
        jitter: Float
    ) -> Float {
        goldenAngle * Float(index)
            + phase
            + deterministicSignedUnit(
                index: index,
                seed: seed,
                salt: salt
            ) * max(0, jitter)
    }

    private static func jitteredRadialScale(
        index: Int,
        seed: UInt64,
        salt: UInt64,
        amount: Float
    ) -> Float {
        1 + deterministicSignedUnit(
            index: index,
            seed: seed,
            salt: salt
        ) * max(0, amount)
    }

    private static func deterministicSignedUnit(
        index: Int,
        seed: UInt64,
        salt: UInt64
    ) -> Float {
        var value = seed
            &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
            &+ salt
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Float(Double(value) / Double(UInt64.max)) * 2 - 1
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
