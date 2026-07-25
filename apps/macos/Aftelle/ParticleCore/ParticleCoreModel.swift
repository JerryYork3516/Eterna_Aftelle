import Foundation
import simd

struct ParticleCoreSeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next()) / Double(UInt64.max)
    }
}

struct ParticleCoreModel {
    static let defaultSeed: UInt64 = 0xA7F7E11E

    struct Particle: Hashable {
        var position: SIMD2<Float>
        var seed: Float
        var ridge: Float
        var depth: Float
        var edgeWeight: Float
    }

    let particles: [Particle]
    let seed: UInt64

    init(
        count: Int = 12_000,
        seed: UInt64 = Self.defaultSeed,
        shapeStrength: Float = 1,
        shapeFeatureScale: Float = 0.5,
        shapeSeed: Float = 0.5,
        scatterStrength: Float = 1,
        scatterClusterStrength: Float = 0.5,
        scatterClusterScale: Float = 0.5,
        scatterSeed: Float = 0.5
    ) {
        self.seed = seed
        var generator = ParticleCoreSeededGenerator(seed: seed)
        var values: [Particle] = []
        values.reserveCapacity(count)
        let tunedShapeStrength = min(2, max(0, shapeStrength))
        let tunedScatterStrength = min(2, max(0, scatterStrength))
        let tunedScatterClusterStrength = min(1, max(0, scatterClusterStrength))
        let tunedScatterClusterScale = min(1, max(0, scatterClusterScale))
        let tunedFeatureScale = min(1, max(0, shapeFeatureScale))
        let featureFrequency = pow(Float(1.8), 1 - tunedFeatureScale * 2)
        let shapePhase = (min(1, max(0, shapeSeed)) - 0.5) * Float.pi * 2
        let scatterOffset = Double(min(1, max(0, scatterSeed)) - 0.5)
        let scatterPhase = Float(scatterOffset) * Float.pi * 2
        let scatterClusterFrequency = 3.4 - tunedScatterClusterScale * 2.0

        let candidateCount = Int(Double(count) * 1.8)
        let overflowVerticalStride = 0.7548776662466927
        var candidateIndex = 0

        while values.count < count {
            let index = candidateIndex
            candidateIndex += 1
            let golden = 0.6180339887498949
            let u = (Double(index) * golden + generator.nextUnit() * 0.022).truncatingRemainder(dividingBy: 1)
            let v = index < candidateCount
                ? (Double(index) + 0.5) / Double(candidateCount)
                : (Double(index - candidateCount) * overflowVerticalStride + 0.5)
                    .truncatingRemainder(dividingBy: 1)
            let theta = Float(u * .pi * 2)
            let z = Float(1 - 2 * v)
            let shell = sqrt(max(0, 1 - z * z))
            let baseX = shell * cos(theta)
            let baseDepth = shell * sin(theta)
            let foldOffset =
                0.14 * sin((baseX * 3.0 + z * 4.7 + baseDepth * 2.0) * featureFrequency + shapePhase)
                + 0.09 * sin((baseDepth * 6.0 - z * 2.6 - baseX * 2.0) * featureFrequency - shapePhase * 0.72)
                + 0.05 * sin((baseX * 11.0 + baseDepth * 5.1 + z * 3.0) * featureFrequency + shapePhase * 1.31)
            let fold = 1 + foldOffset * tunedShapeStrength
            let verticalDetail =
                sin((baseX * 2.0 + baseDepth * 3.0 + z * 1.7) * featureFrequency + shapePhase * 0.61)
            var x = (baseX * 0.58 + baseDepth * 0.075 * tunedShapeStrength) * fold
            var y = (z * 0.44 + 0.035 * tunedShapeStrength * verticalDetail) * fold
            var depth = baseDepth * fold
            let depthScale: Float = 0.58
            var bodyPosition = SIMD3<Float>(x, y, depth * depthScale)
            let shellNormal = simd_normalize(bodyPosition)
            let tangentReference = abs(shellNormal.z) < 0.92
                ? SIMD3<Float>(0, 0, 1)
                : SIMD3<Float>(0, 1, 0)
            let shellTangent = simd_normalize(simd_cross(tangentReference, shellNormal))
            let shellBitangent = simd_normalize(simd_cross(shellNormal, shellTangent))
            let strongScatterSample = Self.wrappedUnit(generator.nextUnit() + scatterOffset)
            let radialScatterSample = Self.wrappedUnit(generator.nextUnit() + scatterOffset * 1.73)
            let tangentialScatterSample = Self.wrappedUnit(generator.nextUnit() + scatterOffset * 2.37)
            let scatterClusterA = 0.5 + 0.5 * sin(
                (baseX * 2.4 + z * 1.6 - baseDepth * 1.2) * scatterClusterFrequency
                    + scatterPhase
            )
            let scatterClusterB = 0.5 + 0.5 * cos(
                (baseDepth * 2.2 - z * 1.8 + baseX * 0.9) * (scatterClusterFrequency * 0.63)
                    - scatterPhase * 0.71
            )
            let rawScatterCluster = min(1, max(0, scatterClusterA * 0.64 + scatterClusterB * 0.36))
            let scatterCluster = rawScatterCluster * rawScatterCluster * (3 - 2 * rawScatterCluster)
            let clusteredStrongProbability = 0.12 + Double(scatterCluster) * 0.66
            let strongScatterProbability = 0.46
                + (clusteredStrongProbability - 0.46) * Double(tunedScatterClusterStrength)
            let scatterClusterAmplitude = 1
                + (0.60 + scatterCluster * 0.80 - 1) * tunedScatterClusterStrength
            let tangentialClusterAmplitude = 1
                + (0.80 + scatterCluster * 0.40 - 1) * tunedScatterClusterStrength
            let strongScatter = strongScatterSample < strongScatterProbability
            let radialScatter = (strongScatter ? 0.105 : 0.034)
                * pow(Float(radialScatterSample), 1.45)
                * tunedScatterStrength
                * scatterClusterAmplitude
            let tangentialScatter = (Float(tangentialScatterSample) - 0.5)
                * 0.048
                * tunedScatterStrength
                * tangentialClusterAmplitude
            let tangentialAngleSeed = Self.wrappedUnit(
                tangentialScatterSample * 1.6180339887498949
                    + strongScatterSample * 0.3819660112501051
            )
            let tangentialAngle = Float(tangentialAngleSeed) * Float.pi * 2
            let tangentialDirection =
                shellTangent * cos(tangentialAngle) + shellBitangent * sin(tangentialAngle)
            bodyPosition += shellNormal * radialScatter + tangentialDirection * tangentialScatter
            x = bodyPosition.x
            y = bodyPosition.y
            depth = bodyPosition.z / depthScale
            let threadA = pow(
                max(0, 0.5 + 0.5 * sin(baseX * 3.0 + z * 4.4 + baseDepth * 2.6 + shapePhase)),
                4
            )
            let threadB = pow(
                max(0, 0.5 + 0.5 * sin(baseDepth * 5.0 - z * 3.1 - baseX * 2.2 - shapePhase * 0.73)),
                5
            )
            let grain = 0.5 + 0.5 * sin(
                baseX * 13.0 + z * 8.7 + baseDepth * 3.1 + shapePhase * 1.17
            )
            let thread = max(threadA, threadB)
            let shapeProminence = max(
                0,
                min(1, 0.5 + foldOffset * tunedShapeStrength / 0.56)
            )
            let ridge = min(1, shapeProminence * 0.30 + thread * 0.14 + grain * 0.10)
            let edgeWeight = max(0, min(1, 0.22 + shapeProminence * 0.46 + thread * 0.22))
            let ridgeKeep = 0.48 + Double(shapeProminence) * 0.08 + Double(thread) * 0.06
            if generator.nextUnit() > ridgeKeep && candidateIndex < candidateCount * 3 {
                continue
            }

            values.append(Particle(
                position: SIMD2<Float>(x, y),
                seed: Float(generator.nextUnit()),
                ridge: ridge,
                depth: depth,
                edgeWeight: edgeWeight
            ))
        }

        self.particles = values
    }

    private static func wrappedUnit(_ value: Double) -> Double {
        value - floor(value)
    }

    var vertexPayloads: [SIMD4<Float>] {
        particles.map { particle in
            SIMD4<Float>(particle.position.x, particle.position.y, particle.ridge, particle.depth)
        }
    }

    func clipBounds(aspect: Float, breathing: Float) -> (minX: Float, minY: Float, maxX: Float, maxY: Float) {
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude

        for particle in particles {
            let clipX = particle.position.x * breathing / max(aspect, 1)
            let clipY = particle.position.y * breathing
            minX = min(minX, clipX)
            minY = min(minY, clipY)
            maxX = max(maxX, clipX)
            maxY = max(maxY, clipY)
        }

        return (minX, minY, maxX, maxY)
    }
}
