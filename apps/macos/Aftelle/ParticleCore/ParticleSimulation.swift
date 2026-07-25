import Foundation
import simd

private struct ParticleSeededGenerator {
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

private struct ParticleModel {
    struct Particle: Hashable {
        var position: SIMD2<Float>
        var ridge: Float
        var depth: Float
    }

    let particles: [Particle]
    let seed: UInt64

    init(
        count: Int = ParticleTuning.Engine.particleCount,
        seed: UInt64 = ParticleTuning.Engine.modelSeed,
        shapeStrength: Float = 1,
        shapeFeatureScale: Float = 0.5,
        shapeSeed: Float = 0.5,
        scatterStrength: Float = 1,
        scatterClusterStrength: Float = 0.5,
        scatterClusterScale: Float = 0.5,
        scatterSeed: Float = 0.5
    ) {
        self.seed = seed
        var generator = ParticleSeededGenerator(seed: seed)
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
            let prominenceRetention = Double(shapeProminence) * 0.08
            let threadRetention = Double(thread) * 0.06
            let ridgeKeep = 0.48 + prominenceRetention + threadRetention
            if generator.nextUnit() > ridgeKeep && candidateIndex < candidateCount * 3 {
                continue
            }

            _ = generator.nextUnit()
            values.append(Particle(
                position: SIMD2<Float>(x, y),
                ridge: ridge,
                depth: depth
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

}

struct ParticleSimulationFrame {
    let motionElapsedTime: Float
    let breathing: Float
    let edgeBreathing: Float
    let coreStability: Float
    let breathingAmount: Float
    let breathingTime: Float
    let resolution: SIMD2<Float>
    let mousePosition: SIMD2<Float>
    let mouseVelocity: SIMD2<Float>
    let mouseInfluence: Float
    let visualState: ParticleVisualState
    let tuning: ParticleTuning
    let colorProfile: ParticleColorProfile
    let flowTime: Float
    let flowStep: Float
}

struct ParticleSimulation {
    private let startTime: TimeInterval
    private var previousMotionElapsed: Float = 0
    private(set) var flowTime: Float = 0
    private var model: ParticleModel
    private(set) var tuning: ParticleTuning
    private(set) var colorProfile: ParticleColorProfile
    private var targetMousePosition = SIMD2<Float>(repeating: 0)
    private var targetMouseVelocity = SIMD2<Float>(repeating: 0)
    private var targetMouseInfluence: Float = 0
    private var smoothMousePosition = SIMD2<Float>(repeating: 0)
    private var smoothMouseVelocity = SIMD2<Float>(repeating: 0)
    private var smoothMouseInfluence: Float = 0
    private var lastMouseEventTime: TimeInterval

    init(
        time: TimeInterval,
        tuning: ParticleTuning = .systemDefault,
        colorProfile: ParticleColorProfile = .systemDefault
    ) {
        startTime = time
        lastMouseEventTime = time
        self.tuning = tuning.clamped()
        self.colorProfile = colorProfile.clamped()
        model = ParticleModel(
            shapeStrength: Float(tuning.shapeStrength) * ParticleTuning.Engine.modelShapeStrengthScale,
            shapeFeatureScale: Float(tuning.shapeFeatureScale),
            shapeSeed: Float(tuning.shapeSeed),
            scatterStrength: Float(tuning.scatterStrength) * ParticleTuning.Engine.modelScatterStrengthScale,
            scatterClusterStrength: Float(tuning.scatterClusterStrength),
            scatterClusterScale: Float(tuning.scatterClusterScale),
            scatterSeed: Float(tuning.scatterSeed)
        )
    }

    var particleCount: Int {
        model.particles.count
    }

    var vertexPayloads: [SIMD4<Float>] {
        model.vertexPayloads
    }

    mutating func setTuning(_ tuning: ParticleTuning) -> Bool {
        let value = tuning.clamped()
        let requiresModelRebuild = self.tuning.shapeStrength != value.shapeStrength
            || self.tuning.shapeFeatureScale != value.shapeFeatureScale
            || self.tuning.shapeSeed != value.shapeSeed
            || self.tuning.scatterStrength != value.scatterStrength
            || self.tuning.scatterClusterStrength != value.scatterClusterStrength
            || self.tuning.scatterClusterScale != value.scatterClusterScale
            || self.tuning.scatterSeed != value.scatterSeed
        self.tuning = value
        return requiresModelRebuild
    }

    mutating func setColorProfile(_ colorProfile: ParticleColorProfile) {
        self.colorProfile = colorProfile.clamped()
    }

    mutating func rebuildParticles() {
        model = ParticleModel(
            shapeStrength: Float(tuning.shapeStrength) * ParticleTuning.Engine.modelShapeStrengthScale,
            shapeFeatureScale: Float(tuning.shapeFeatureScale),
            shapeSeed: Float(tuning.shapeSeed),
            scatterStrength: Float(tuning.scatterStrength) * ParticleTuning.Engine.modelScatterStrengthScale,
            scatterClusterStrength: Float(tuning.scatterClusterStrength),
            scatterClusterScale: Float(tuning.scatterClusterScale),
            scatterSeed: Float(tuning.scatterSeed)
        )
    }

    mutating func updateInteraction(
        position: SIMD2<Float>,
        velocity: SIMD2<Float>,
        active: Bool,
        time: TimeInterval
    ) {
        targetMousePosition = position
        targetMouseVelocity = velocity
        targetMouseInfluence = active ? 1 : 0
        lastMouseEventTime = time
    }

    mutating func advance(
        time: TimeInterval,
        drawableSize: CGSize,
        visualState: ParticleVisualState
    ) -> ParticleSimulationFrame {
        updateSmoothedInteraction(time: time)
        let elapsed = Float(time - startTime)
        let speedPhaseRate = ParticleTuning.Engine.speedPhaseRate
        let motionElapsed = ParticleTuning.Engine.motionBaseRate * elapsed
            + (ParticleTuning.Engine.motionDriftAmplitude / speedPhaseRate)
            * (1 - cos(elapsed * speedPhaseRate))
        let motionStep = min(
            max(motionElapsed - previousMotionElapsed, 0),
            ParticleTuning.Engine.maximumMotionStep
        )
        previousMotionElapsed = motionElapsed
        let flowStep = motionStep
            * ParticleTuning.Engine.flowTimeScale
            * visualState.flowSpeedMultiplier
            * Self.centeredControl(
                tuning.flowSpeed,
                maximum: ParticleTuning.Engine.maximumFlowSpeed
            )
        flowTime += flowStep

        let tunedBreathTime = motionElapsed
            * Float(tuning.breathingSpeed)
            * ParticleTuning.Engine.breathingSpeedScale
        let breathingAmount = Self.centeredControl(
            tuning.breathingAmount,
            maximum: ParticleTuning.Engine.maximumBreathingAmount
        )
        let breathing = (
            ParticleTuning.Engine.breathingPrimaryAmplitude
                * sin(tunedBreathTime * ParticleTuning.Engine.breathingPrimaryFrequency)
                + ParticleTuning.Engine.breathingSecondaryAmplitude
                * sin(
                    tunedBreathTime * ParticleTuning.Engine.breathingSecondaryFrequency
                        + ParticleTuning.Engine.breathingSecondaryPhase
                )
        ) * breathingAmount
        let edgeBreathing = (
            ParticleTuning.Engine.breathingEdgePrimaryAmplitude
                * sin(
                    tunedBreathTime * ParticleTuning.Engine.breathingEdgePrimaryFrequency
                        + ParticleTuning.Engine.breathingEdgePrimaryPhase
                )
                + ParticleTuning.Engine.breathingEdgeSecondaryAmplitude
                * sin(
                    tunedBreathTime * ParticleTuning.Engine.breathingEdgeSecondaryFrequency
                        + ParticleTuning.Engine.breathingEdgeSecondaryPhase
                )
        ) * breathingAmount
        let coreStability = 1 - min(
            ParticleTuning.Engine.breathingCoreVariationLimit,
            abs(breathing) * ParticleTuning.Engine.breathingCoreVariationScale
        )

        return ParticleSimulationFrame(
            motionElapsedTime: motionElapsed,
            breathing: breathing,
            edgeBreathing: edgeBreathing,
            coreStability: coreStability,
            breathingAmount: breathingAmount,
            breathingTime: tunedBreathTime,
            resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            mousePosition: smoothMousePosition,
            mouseVelocity: smoothMouseVelocity,
            mouseInfluence: smoothMouseInfluence,
            visualState: visualState,
            tuning: tuning,
            colorProfile: colorProfile,
            flowTime: flowTime,
            flowStep: flowStep
        )
    }

    private mutating func updateSmoothedInteraction(time: TimeInterval) {
        if time - lastMouseEventTime > ParticleTuning.Engine.interactionTimeout {
            targetMouseInfluence = 0
            targetMouseVelocity = .zero
        }

        smoothMousePosition += (
            targetMousePosition - smoothMousePosition
        ) * ParticleTuning.Engine.positionResponse
        smoothMouseVelocity += (
            targetMouseVelocity - smoothMouseVelocity
        ) * ParticleTuning.Engine.velocityResponse
        let response = targetMouseInfluence > smoothMouseInfluence
            ? ParticleTuning.Engine.interactionRiseResponse
            : ParticleTuning.Engine.interactionFallResponse
        smoothMouseInfluence += (targetMouseInfluence - smoothMouseInfluence) * response
    }

    private static func centeredControl(_ value: Double, maximum: Float) -> Float {
        let control = Float(min(1, max(0, value)))
        if control <= 0.5 {
            return control * 2
        }
        return 1 + (control - 0.5) * 2 * (maximum - 1)
    }
}
