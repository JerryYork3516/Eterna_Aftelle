import Foundation
import simd

enum ParticleShapeTarget: String, CaseIterable, Equatable, Identifiable {
    case sphere
    case customShape
    case text
    case guidePath
    case abstractResident
    case realisticResident

    var id: String {
        rawValue
    }

    var isImplemented: Bool {
        self == .sphere || self == .customShape
    }

    var debugLocalizedKey: String {
        "particleDebug.shape.\(rawValue)"
    }
}

struct ParticleShapeState {
    let currentTarget: ParticleShapeTarget
    let targetTarget: ParticleShapeTarget
    let elapsedTime: Float
    let duration: Float
    let progress: Float
    let reason: String
}

#if DEBUG
struct ParticleMorphDebugResult {
    let passed: Bool
    let continuityError: Float
    let resumeProgressStep: Float
    let particleCountBefore: Int
    let particleCountAfter: Int
    let rebuildCountBefore: Int
    let rebuildCountAfter: Int
}
#endif

private struct ParticleMorphTransition {
    var currentTarget: ParticleShapeTarget
    var targetTarget: ParticleShapeTarget
    var startCenter: SIMD3<Float>
    var targetCenter: SIMD3<Float>
    var startTime: TimeInterval
    var duration: TimeInterval
    var progress: Float
    var reason: String
}

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
    let sphereAnchor: SIMD3<Float>
    let customShapeAnchor: SIMD3<Float>
    let flowPhase: Float
    let disturbancePhase: Float
    let surfaceWeight: Float
    var morphStartAnchor: SIMD3<Float>
    var morphTargetAnchor: SIMD3<Float>
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
    let shapeState: ParticleShapeState
    let tuning: ParticleTuning
    let colorProfile: ParticleColorProfile
    let stability: ParticleStabilitySnapshot
}

struct ParticleSimulation {
    private var previousTime: TimeInterval
    private var previousMorphTime: TimeInterval
    private var motionElapsedTime: Float = 0
    private var particles: [SimulatedParticle] = []
    private var payloads: [SIMD4<Float>] = []
    private var morphTransition: ParticleMorphTransition
    private var sphereAnchorCenter = SIMD3<Float>(repeating: 0)
    private var customShapeAnchorCenter = SIMD3<Float>(repeating: 0)
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
        previousMorphTime = time
        lastMouseEventTime = time
        morphTransition = ParticleMorphTransition(
            currentTarget: .sphere,
            targetTarget: .sphere,
            startCenter: .zero,
            targetCenter: .zero,
            startTime: time,
            duration: ParticleTuning.Engine.shapeMorphDuration,
            progress: 1,
            reason: "startup"
        )
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

    var targetShape: ParticleShapeTarget {
        morphTransition.targetTarget
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
        let rebuildShapeTarget = morphTransition.targetTarget.isImplemented
            ? morphTransition.targetTarget
            : .sphere
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
        var sphereCenter = SIMD3<Float>(repeating: 0)
        var customShapeCenter = SIMD3<Float>(repeating: 0)

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

            let sphereAnchor = direction * unitRadius
            let customShapeAnchor = Self.customShapeAnchor(from: sphereAnchor)
            let activeAnchor = rebuildShapeTarget == .customShape
                ? customShapeAnchor
                : sphereAnchor
            let particle = SimulatedParticle(
                sphereAnchor: sphereAnchor,
                customShapeAnchor: customShapeAnchor,
                flowPhase: generator.nextUnit() * 2 * .pi,
                disturbancePhase: generator.nextUnit() * 2 * .pi,
                surfaceWeight: surfaceWeight,
                morphStartAnchor: activeAnchor,
                morphTargetAnchor: activeAnchor,
                position: activeAnchor * sphereRadius,
                velocity: .zero
            )
            rebuilt.append(particle)
            sphereCenter += sphereAnchor
            customShapeCenter += customShapeAnchor
        }

        particles = rebuilt
        let divisor = Float(max(count, 1))
        sphereAnchorCenter = sphereCenter / divisor
        customShapeAnchorCenter = customShapeCenter / divisor
        let activeCenter = shapeCenter(for: rebuildShapeTarget)
        morphTransition = ParticleMorphTransition(
            currentTarget: rebuildShapeTarget,
            targetTarget: rebuildShapeTarget,
            startCenter: activeCenter,
            targetCenter: activeCenter,
            startTime: previousMorphTime,
            duration: ParticleTuning.Engine.shapeMorphDuration,
            progress: 1,
            reason: "modelRebuild"
        )
        payloads = Array(repeating: .zero, count: count)
        updatePayloads()
        let expectedCenter = activeCenter * sphereRadius
        stability = measureStability(expectedCenter: expectedCenter)
    }

    @discardableResult
    mutating func setShapeTarget(
        _ target: ParticleShapeTarget,
        reason: String,
        time: TimeInterval
    ) -> Bool {
        guard target.isImplemented,
              morphTransition.targetTarget != target else {
            return false
        }

        updateMorphClock(time: time)
        let easedProgress = Self.easedMorphProgress(
            resolveMorphProgress(time: time)
        )
        let currentCenter = resolvedMorphCenter(
            easedProgress: easedProgress
        )
        settleCompletedMorph()
        for index in particles.indices {
            let currentAnchor = resolvedAnchor(
                for: particles[index],
                easedProgress: easedProgress
            )
            particles[index].morphStartAnchor = currentAnchor
            particles[index].morphTargetAnchor = shapeAnchor(
                for: target,
                particle: particles[index]
            )
        }
        morphTransition = ParticleMorphTransition(
            currentTarget: morphTransition.targetTarget,
            targetTarget: target,
            startCenter: currentCenter,
            targetCenter: shapeCenter(for: target),
            startTime: time,
            duration: ParticleTuning.Engine.shapeMorphDuration,
            progress: 0,
            reason: reason
        )
        return true
    }

    #if DEBUG
    func debugMorphStressResult() -> ParticleMorphDebugResult {
        var simulation = self
        let particleCountBefore = simulation.particleCount
        let rebuildCountBefore = simulation.rebuildCount
        var time = simulation.previousMorphTime + 1

        _ = simulation.setShapeTarget(
            .customShape,
            reason: "debugMorph.prepare",
            time: time
        )
        time += ParticleTuning.Engine.shapeMorphDuration * 0.37
        simulation.updateMorphClock(time: time)
        let beforeRetarget = simulation.resolvedAnchors(time: time)
        _ = simulation.setShapeTarget(
            .sphere,
            reason: "debugMorph.retarget",
            time: time
        )
        let afterRetarget = simulation.resolvedAnchors(time: time)
        let continuityError = Self.maximumAnchorDifference(
            beforeRetarget,
            afterRetarget
        )

        for index in 0..<ParticleTuning.Engine.debugStressSwitchCount {
            time += ParticleTuning.Engine.debugMorphSwitchInterval
            let target: ParticleShapeTarget = index.isMultiple(of: 2)
                ? .customShape
                : .sphere
            _ = simulation.setShapeTarget(
                target,
                reason: "debugMorph.stress",
                time: time
            )
        }

        let progressBeforePause = simulation.resolveMorphProgress(time: time)
        let resumeTime = time + ParticleTuning.Engine.debugResumeInterval
        simulation.updateMorphClock(time: resumeTime)
        let progressAfterPause = simulation.resolveMorphProgress(
            time: resumeTime
        )
        let resumeProgressStep = progressAfterPause - progressBeforePause
        let finiteAnchors = simulation.resolvedAnchors(
            time: resumeTime
        ).allSatisfy { anchor in
            anchor.x.isFinite && anchor.y.isFinite && anchor.z.isFinite
        }
        let particleCountAfter = simulation.particleCount
        let rebuildCountAfter = simulation.rebuildCount
        let passed = finiteAnchors
            && continuityError
                <= ParticleTuning.Engine.debugContinuityTolerance
            && resumeProgressStep
                <= ParticleTuning.Engine.debugMaximumPauseProgressStep
            && particleCountBefore == particleCountAfter
            && rebuildCountBefore == rebuildCountAfter

        return ParticleMorphDebugResult(
            passed: passed,
            continuityError: continuityError,
            resumeProgressStep: resumeProgressStep,
            particleCountBefore: particleCountBefore,
            particleCountAfter: particleCountAfter,
            rebuildCountBefore: rebuildCountBefore,
            rebuildCountAfter: rebuildCountAfter
        )
    }
    #endif

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
        updateMorphClock(time: time)
        let shapeState = resolveShapeState(time: time)
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
                visualState: visualState,
                morphProgress: Self.easedMorphProgress(shapeState.progress)
            )
        }

        return ParticleSimulationFrame(
            motionElapsedTime: motionElapsedTime,
            resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            mousePosition: smoothMousePosition,
            mouseVelocity: smoothMouseVelocity,
            mouseInfluence: smoothMouseInfluence,
            visualState: visualState,
            shapeState: shapeState,
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
        visualState: ParticleVisualState,
        morphProgress: Float
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
            let shapeAnchor = morphProgress >= 1
                ? particle.morphTargetAnchor
                : resolvedAnchor(
                    for: particle,
                    easedProgress: morphProgress
                )
            let target = shapeAnchor * targetRadius
            let radial = Self.safeNormalize(
                particle.position,
                fallback: shapeAnchor
            )
            let primaryFlow = simd_cross(flowAxis, radial)
            let secondaryFlow = simd_cross(secondaryAxis, radial)
                * sin(
                    time * flowFrequency * ParticleTuning.Engine.secondaryFlowFrequencyRatio
                        + particle.flowPhase
                )
                * ParticleTuning.Engine.secondaryFlowStrength
            let flowWeight = ParticleTuning.Engine.minimumFlowWeight
                + simd_length(shapeAnchor) * ParticleTuning.Engine.anchorFlowWeight
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
        let expectedCenter = resolvedMorphCenter(
            easedProgress: morphProgress
        ) * targetRadius
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

    private mutating func updateMorphClock(time: TimeInterval) {
        let rawDelta = max(0, time - previousMorphTime)
        let maximumDelta = TimeInterval(
            ParticleTuning.Engine.maximumSimulationStep
        )
        let discardedDelta = rawDelta - min(rawDelta, maximumDelta)
        if discardedDelta > 0, morphTransition.progress < 1 {
            morphTransition.startTime += discardedDelta
        }
        previousMorphTime = time
    }

    private mutating func resolveShapeState(
        time: TimeInterval
    ) -> ParticleShapeState {
        let progress = resolveMorphProgress(time: time)
        settleCompletedMorph()
        return ParticleShapeState(
            currentTarget: morphTransition.currentTarget,
            targetTarget: morphTransition.targetTarget,
            elapsedTime: Float(
                morphTransition.duration * Double(progress)
            ),
            duration: Float(morphTransition.duration),
            progress: progress,
            reason: morphTransition.reason
        )
    }

    private mutating func resolveMorphProgress(time: TimeInterval) -> Float {
        let duration = max(
            morphTransition.duration,
            ParticleTuning.Engine.minimumTransitionDuration
        )
        let rawProgress = (time - morphTransition.startTime) / duration
        let progress = Float(min(1, max(0, rawProgress)))
        morphTransition.progress = progress
        return progress
    }

    private mutating func settleCompletedMorph() {
        guard morphTransition.progress >= 1,
              morphTransition.currentTarget
                != morphTransition.targetTarget else {
            return
        }
        morphTransition.currentTarget = morphTransition.targetTarget
        morphTransition.startCenter = morphTransition.targetCenter
        for index in particles.indices {
            particles[index].morphStartAnchor =
                particles[index].morphTargetAnchor
        }
    }

    private func resolvedAnchor(
        for particle: SimulatedParticle,
        easedProgress: Float
    ) -> SIMD3<Float> {
        particle.morphStartAnchor
            + (particle.morphTargetAnchor - particle.morphStartAnchor)
            * easedProgress
    }

    private func resolvedMorphCenter(
        easedProgress: Float
    ) -> SIMD3<Float> {
        morphTransition.startCenter
            + (morphTransition.targetCenter - morphTransition.startCenter)
            * easedProgress
    }

    private func shapeAnchor(
        for target: ParticleShapeTarget,
        particle: SimulatedParticle
    ) -> SIMD3<Float> {
        switch target {
        case .sphere:
            return particle.sphereAnchor
        case .customShape:
            return particle.customShapeAnchor
        case .text, .guidePath, .abstractResident, .realisticResident:
            return particle.sphereAnchor
        }
    }

    private func shapeCenter(
        for target: ParticleShapeTarget
    ) -> SIMD3<Float> {
        switch target {
        case .sphere:
            return sphereAnchorCenter
        case .customShape:
            return customShapeAnchorCenter
        case .text, .guidePath, .abstractResident, .realisticResident:
            return sphereAnchorCenter
        }
    }

    #if DEBUG
    private mutating func resolvedAnchors(
        time: TimeInterval
    ) -> [SIMD3<Float>] {
        let progress = Self.easedMorphProgress(
            resolveMorphProgress(time: time)
        )
        return particles.map {
            resolvedAnchor(for: $0, easedProgress: progress)
        }
    }

    private static func maximumAnchorDifference(
        _ lhs: [SIMD3<Float>],
        _ rhs: [SIMD3<Float>]
    ) -> Float {
        guard lhs.count == rhs.count else { return .infinity }
        var maximumDifference: Float = 0
        for index in lhs.indices {
            maximumDifference = max(
                maximumDifference,
                simd_length(lhs[index] - rhs[index])
            )
        }
        return maximumDifference
    }
    #endif

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

    private static func customShapeAnchor(
        from sphereAnchor: SIMD3<Float>
    ) -> SIMD3<Float> {
        let radius = simd_length(sphereAnchor)
        guard radius > ParticleTuning.Engine.normalizationEpsilon else {
            return sphereAnchor
        }
        let direction = sphereAnchor / radius
        let maximumAxis = max(
            abs(direction.x),
            max(abs(direction.y), abs(direction.z))
        )
        return direction
            / max(maximumAxis, ParticleTuning.Engine.normalizationEpsilon)
            * radius
            * ParticleTuning.Engine.customShapeCubeScale
    }

    private static func easedMorphProgress(_ progress: Float) -> Float {
        progress * progress * (3 - 2 * progress)
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
