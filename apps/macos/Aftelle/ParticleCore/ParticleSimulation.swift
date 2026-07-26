import Foundation
import simd

private struct ParticleSeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func nextUnit() -> Float {
        Float(Double(next()) / Double(UInt64.max))
    }

    mutating func nextSignedUnit() -> Float {
        nextUnit() * 2 - 1
    }
}

private struct SimulatedParticle {
    let anchor: SIMD3<Float>
    let flowPhase: Float
    let disturbancePhase: Float
    let surfaceWeight: Float
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
}

struct ParticleStabilitySnapshot {
    let centerDrift: Float
    let maximumRadius: Float
    let maximumSpeed: Float
}

struct ParticleSimulationFrame {
    let motionElapsedTime: Float
    let resolution: SIMD2<Float>
    let mousePosition: SIMD2<Float>
    let mouseVelocity: SIMD2<Float>
    let mouseInfluence: Float
    let visualState: ParticleVisualState
    let tuning: ParticleTuning
    let colorProfile: ParticleColorProfile
    let stability: ParticleStabilitySnapshot
}

struct ParticleSimulation {
    private var previousTime: TimeInterval
    private var motionElapsedTime: Float = 0
    private var particles: [SimulatedParticle] = []
    private var payloads: [SIMD4<Float>] = []
    private var anchorCenter = SIMD3<Float>(repeating: 0)
    private(set) var tuning: ParticleTuning
    private(set) var colorProfile: ParticleColorProfile
    private var targetMousePosition = SIMD2<Float>(repeating: 0)
    private var targetMouseVelocity = SIMD2<Float>(repeating: 0)
    private var targetMouseInfluence: Float = 0
    private var smoothMousePosition = SIMD2<Float>(repeating: 0)
    private var smoothMouseVelocity = SIMD2<Float>(repeating: 0)
    private var smoothMouseInfluence: Float = 0
    private var lastMouseEventTime: TimeInterval
    private var stability = ParticleStabilitySnapshot(
        centerDrift: 0,
        maximumRadius: 0,
        maximumSpeed: 0
    )
    private(set) var rebuildCount = 0

    init(
        time: TimeInterval,
        tuning: ParticleTuning = .systemDefault,
        colorProfile: ParticleColorProfile = .systemDefault
    ) {
        previousTime = time
        lastMouseEventTime = time
        self.tuning = tuning.clamped()
        self.colorProfile = colorProfile.clamped()
        rebuildParticles()
    }

    var particleCount: Int {
        particles.count
    }

    var vertexPayloads: [SIMD4<Float>] {
        payloads
    }

    mutating func setTuning(_ tuning: ParticleTuning) -> Bool {
        let value = tuning.clamped()
        let requiresModelRebuild = self.tuning.surfaceRatio != value.surfaceRatio
        self.tuning = value
        return requiresModelRebuild
    }

    mutating func setColorProfile(_ colorProfile: ParticleColorProfile) {
        self.colorProfile = colorProfile.clamped()
    }

    mutating func rebuildParticles() {
        rebuildCount += 1
        let count = ParticleTuning.Engine.particleCount
        let baseSurfaceRatio = ParticleTuning.Engine.value(
            tuning.surfaceRatio,
            minimum: ParticleTuning.Engine.minimumSurfaceRatio,
            maximum: ParticleTuning.Engine.maximumSurfaceRatio
        )
        let surfaceRatio = min(
            1,
            max(
                0,
                ParticleTuning.Engine.amplifiedAround(
                    baseSurfaceRatio,
                    center: 0.5
                )
            )
        )
        var generator = ParticleSeededGenerator(seed: ParticleTuning.Engine.modelSeed)
        var rebuilt: [SimulatedParticle] = []
        rebuilt.reserveCapacity(count)
        var center = SIMD3<Float>(repeating: 0)

        for index in 0..<count {
            let direction = Self.stratifiedDirection(
                index: index,
                count: count,
                generator: &generator
            )
            let isSurface = generator.nextUnit() < surfaceRatio
            let radialSample = generator.nextUnit()
            let unitRadius: Float
            let surfaceWeight: Float
            if isSurface {
                unitRadius = 1 - ParticleTuning.Engine.surfaceThickness * radialSample * radialSample
                surfaceWeight = 1
            } else {
                unitRadius = pow(radialSample, 1.0 / 3.0)
                surfaceWeight = 0
            }

            let anchor = direction * unitRadius
            let particle = SimulatedParticle(
                anchor: anchor,
                flowPhase: generator.nextUnit() * 2 * .pi,
                disturbancePhase: generator.nextUnit() * 2 * .pi,
                surfaceWeight: surfaceWeight,
                position: anchor * sphereRadius,
                velocity: .zero
            )
            rebuilt.append(particle)
            center += anchor
        }

        particles = rebuilt
        anchorCenter = center / Float(max(count, 1))
        payloads = Array(repeating: .zero, count: count)
        updatePayloads()
        stability = measureStability(expectedCenter: anchorCenter * sphereRadius)
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
        let timeStep = min(
            max(Float(time - previousTime), 0),
            ParticleTuning.Engine.maximumSimulationStep
        )
        previousTime = time
        if timeStep > 0 {
            motionElapsedTime += timeStep
            integrate(
                time: motionElapsedTime,
                timeStep: timeStep,
                visualState: visualState
            )
        }

        return ParticleSimulationFrame(
            motionElapsedTime: motionElapsedTime,
            resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            mousePosition: smoothMousePosition,
            mouseVelocity: smoothMouseVelocity,
            mouseInfluence: smoothMouseInfluence,
            visualState: visualState,
            tuning: tuning,
            colorProfile: colorProfile,
            stability: stability
        )
    }

    private var sphereRadius: Float {
        let minimum = ParticleTuning.Engine.minimumSphereRadius
        let maximum = ParticleTuning.Engine.maximumSphereRadius
        let radius = ParticleTuning.Engine.value(
            tuning.sphereRadius,
            minimum: minimum,
            maximum: maximum
        )
        return ParticleTuning.Engine.amplifiedAround(
            radius,
            center: (minimum + maximum) * 0.5
        )
    }

    private mutating func integrate(
        time: Float,
        timeStep: Float,
        visualState: ParticleVisualState
    ) {
        let baseRadius = sphereRadius
        let breathingAmplitude = ParticleTuning.Engine.amplifiedStrength(
            tuning.breathingAmount
        )
            * ParticleTuning.Engine.maximumBreathingScale
        let breathingFrequency = ParticleTuning.Engine.amplifiedValue(
            tuning.breathingSpeed,
            minimum: ParticleTuning.Engine.minimumBreathingFrequency,
            maximum: ParticleTuning.Engine.maximumBreathingFrequency
        )
        let primaryBreath = sin(time * breathingFrequency)
        let secondaryBreath = sin(
            time * breathingFrequency * ParticleTuning.Engine.secondaryBreathingFrequencyRatio
                + ParticleTuning.Engine.secondaryBreathingPhase
        ) * ParticleTuning.Engine.secondaryBreathingAmplitude
        let breathingScale = 1 + breathingAmplitude * (primaryBreath + secondaryBreath)
        let pulseWave = sin(
            time * ParticleTuning.Engine.statePulseFrequency * 2 * .pi
        )
        let pulseScale = 1
            + visualState.pulseStrength
            * ParticleTuning.Engine.statePulseRadiusScale
            * (pulseWave * 0.5 + 0.5)
        let targetRadius = baseRadius * breathingScale * pulseScale
        let aggregation = ParticleTuning.Engine.amplifiedValue(
            tuning.aggregationStrength,
            minimum: ParticleTuning.Engine.minimumAggregation,
            maximum: ParticleTuning.Engine.maximumAggregation
        )
        let damping = ParticleTuning.Engine.amplifiedValue(
            tuning.damping,
            minimum: ParticleTuning.Engine.minimumDamping,
            maximum: ParticleTuning.Engine.maximumDamping
        )
        let dampingFactor = exp(-damping * timeStep)
        let flowAcceleration = ParticleTuning.Engine.amplifiedStrength(
            tuning.flowStrength
        )
            * ParticleTuning.Engine.maximumFlowAcceleration
            * visualState.flowSpeedMultiplier
        let flowFrequency = ParticleTuning.Engine.amplifiedValue(
            tuning.flowSpeed,
            minimum: ParticleTuning.Engine.minimumFlowFrequency,
            maximum: ParticleTuning.Engine.maximumFlowFrequency
        )
        let disturbanceAcceleration = ParticleTuning.Engine.amplifiedStrength(
            tuning.disturbanceStrength
        )
            * ParticleTuning.Engine.maximumDisturbanceAcceleration
            * (
                1
                    + visualState.disruptionStrength
                    * ParticleTuning.Engine.disruptionAccelerationIncrease
            )
        let axisPhase = time * flowFrequency * ParticleTuning.Engine.flowAxisPrecession
        let flowAxis = simd_normalize(SIMD3<Float>(
            sin(axisPhase) * ParticleTuning.Engine.flowAxisTilt,
            1,
            cos(axisPhase * ParticleTuning.Engine.flowAxisSecondaryRateRatio)
                * ParticleTuning.Engine.flowAxisTilt
        ))
        let secondaryAxis = simd_normalize(ParticleTuning.Engine.secondaryFlowAxis)
        let boundaryRadius = targetRadius * (1 + ParticleTuning.Engine.boundaryMargin)
        var positionCenter = SIMD3<Float>(repeating: 0)
        var velocityCenter = SIMD3<Float>(repeating: 0)

        for index in particles.indices {
            var particle = particles[index]
            let target = particle.anchor * targetRadius
            let radial = Self.safeNormalize(particle.position, fallback: particle.anchor)
            let primaryFlow = simd_cross(flowAxis, radial)
            let secondaryFlow = simd_cross(secondaryAxis, radial)
                * sin(
                    time * flowFrequency * ParticleTuning.Engine.secondaryFlowFrequencyRatio
                        + particle.flowPhase
                )
                * ParticleTuning.Engine.secondaryFlowStrength
            let flowWeight = ParticleTuning.Engine.minimumFlowWeight
                + simd_length(particle.anchor) * ParticleTuning.Engine.anchorFlowWeight
            let flowForce = (primaryFlow + secondaryFlow)
                * flowAcceleration
                * flowWeight

            var disturbance = SIMD3<Float>(
                sin(time * ParticleTuning.Engine.disturbanceFrequency + particle.disturbancePhase),
                sin(
                    time * ParticleTuning.Engine.disturbanceFrequency
                        * ParticleTuning.Engine.disturbanceYFrequencyRatio
                        + particle.disturbancePhase
                        * ParticleTuning.Engine.disturbanceYPhaseRatio
                ),
                cos(
                    time * ParticleTuning.Engine.disturbanceFrequency
                        * ParticleTuning.Engine.disturbanceZFrequencyRatio
                        + particle.disturbancePhase
                        * ParticleTuning.Engine.disturbanceZPhaseRatio
                )
            )
            disturbance -= radial
                * simd_dot(disturbance, radial)
                * ParticleTuning.Engine.disturbanceRadialRetention
            disturbance = Self.safeNormalize(
                disturbance,
                fallback: simd_cross(radial, secondaryAxis)
            )
            let disturbanceForce = disturbance
                * disturbanceAcceleration
                * (
                    ParticleTuning.Engine.minimumDisturbanceWeight
                        + particle.surfaceWeight
                        * ParticleTuning.Engine.surfaceDisturbanceWeight
                )
            let aggregationForce = (target - particle.position) * aggregation

            particle.velocity += (
                aggregationForce + flowForce + disturbanceForce
            ) * timeStep
            particle.velocity *= dampingFactor
            let speed = simd_length(particle.velocity)
            if speed > ParticleTuning.Engine.maximumParticleSpeed {
                particle.velocity *= ParticleTuning.Engine.maximumParticleSpeed / speed
            }
            particle.position += particle.velocity * timeStep

            let radius = simd_length(particle.position)
            if radius > boundaryRadius {
                let boundaryNormal = particle.position / radius
                particle.position = boundaryNormal * boundaryRadius
                let outwardVelocity = max(0, simd_dot(particle.velocity, boundaryNormal))
                particle.velocity -= boundaryNormal
                    * outwardVelocity
                    * (1 - ParticleTuning.Engine.boundaryVelocityRetention)
            }

            particles[index] = particle
            positionCenter += particle.position
            velocityCenter += particle.velocity
        }

        let count = Float(max(particles.count, 1))
        positionCenter /= count
        velocityCenter /= count
        let expectedCenter = anchorCenter * targetRadius
        let centerOffset = (positionCenter - expectedCenter)
            * ParticleTuning.Engine.centerCorrection

        var maximumRadius: Float = 0
        var maximumSpeed: Float = 0
        for index in particles.indices {
            particles[index].position -= centerOffset
            particles[index].velocity -= velocityCenter
            maximumRadius = max(maximumRadius, simd_length(particles[index].position))
            maximumSpeed = max(maximumSpeed, simd_length(particles[index].velocity))
            payloads[index] = SIMD4<Float>(
                particles[index].position,
                particles[index].surfaceWeight
            )
        }

        stability = ParticleStabilitySnapshot(
            centerDrift: simd_length(centerOffset),
            maximumRadius: maximumRadius,
            maximumSpeed: maximumSpeed
        )
    }

    private mutating func updatePayloads() {
        for index in particles.indices {
            payloads[index] = SIMD4<Float>(
                particles[index].position,
                particles[index].surfaceWeight
            )
        }
    }

    private func measureStability(expectedCenter: SIMD3<Float>) -> ParticleStabilitySnapshot {
        guard !particles.isEmpty else {
            return ParticleStabilitySnapshot(centerDrift: 0, maximumRadius: 0, maximumSpeed: 0)
        }

        var center = SIMD3<Float>(repeating: 0)
        var maximumRadius: Float = 0
        var maximumSpeed: Float = 0
        for particle in particles {
            center += particle.position
            maximumRadius = max(maximumRadius, simd_length(particle.position))
            maximumSpeed = max(maximumSpeed, simd_length(particle.velocity))
        }
        center /= Float(particles.count)
        return ParticleStabilitySnapshot(
            centerDrift: simd_length(center - expectedCenter),
            maximumRadius: maximumRadius,
            maximumSpeed: maximumSpeed
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

    private static func stratifiedDirection(
        index: Int,
        count: Int,
        generator: inout ParticleSeededGenerator
    ) -> SIMD3<Float> {
        let normalizedIndex = (Float(index) + 0.5) / Float(max(count, 1))
        let y = 1 - normalizedIndex * 2
        let radial = sqrt(max(0, 1 - y * y))
        let azimuth = Float(index) * ParticleTuning.Engine.goldenAngle
        let base = SIMD3<Float>(
            cos(azimuth) * radial,
            y,
            sin(azimuth) * radial
        )
        let reference = abs(base.y) < ParticleTuning.Engine.polarReferenceThreshold
            ? SIMD3<Float>(0, 1, 0)
            : SIMD3<Float>(1, 0, 0)
        let tangent = simd_normalize(simd_cross(reference, base))
        let bitangent = simd_cross(base, tangent)
        let cellAngle = sqrt(4 * Float.pi / Float(max(count, 1)))
            * ParticleTuning.Engine.angularJitterScale
        let jittered = base
            + tangent * generator.nextSignedUnit() * cellAngle
            + bitangent * generator.nextSignedUnit() * cellAngle
        return simd_normalize(jittered)
    }

    private static func safeNormalize(
        _ value: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let length = simd_length(value)
        if length > ParticleTuning.Engine.normalizationEpsilon {
            return value / length
        }
        let fallbackLength = simd_length(fallback)
        return fallbackLength > ParticleTuning.Engine.normalizationEpsilon
            ? fallback / fallbackLength
            : SIMD3<Float>(0, 1, 0)
    }
}
