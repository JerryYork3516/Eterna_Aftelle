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
    let flowPhaseSine: Float
    let flowPhaseCosine: Float
    let disturbancePhaseXSine: Float
    let disturbancePhaseXCosine: Float
    let disturbancePhaseYSine: Float
    let disturbancePhaseYCosine: Float
    let disturbancePhaseZSine: Float
    let disturbancePhaseZCosine: Float
    let scatterSelector: Float
    let scatterRadialSample: Float
    let scatterTangentialSample: Float
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
    let flowElapsedTime: Float
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
    private var flowElapsedTime: Float = 0
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
        let sphereFormChanged =
            self.tuning.shapeStrength != value.shapeStrength
            || self.tuning.shapeFeatureScale != value.shapeFeatureScale
            || self.tuning.shapeSmoothness != value.shapeSmoothness
            || self.tuning.shapeSeed != value.shapeSeed
            || self.tuning.scatterStrength != value.scatterStrength
            || self.tuning.scatterClusterStrength != value.scatterClusterStrength
            || self.tuning.scatterClusterScale != value.scatterClusterScale
            || self.tuning.scatterSeed != value.scatterSeed
        self.tuning = value
        if sphereFormChanged {
            updateSphereFormTargets()
        }
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
        let surfaceConcentrationControl = min(
            1,
            max(
                0,
                ParticleTuning.Engine.amplifiedAround(
                    baseSurfaceRatio,
                    center: 0.5
                )
            )
        )
        let shellConcentration =
            ParticleTuning.Engine.minimumShellConcentration
            + surfaceConcentrationControl
            * (
                ParticleTuning.Engine.maximumShellConcentration
                    - ParticleTuning.Engine.minimumShellConcentration
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
            // Preserve the seeded sequence used by each particle's later phases.
            _ = generator.nextUnit()
            let radialSample = generator.nextUnit()
            let unitRadius = 1
                - ParticleTuning.Engine.surfaceThickness
                * pow(radialSample, shellConcentration)
            let surfaceWeight: Float = 1

            let sphereAnchor = direction * unitRadius
            let scatterSelector = generator.nextUnit()
            let scatterRadialSample = generator.nextUnit()
            let scatterTangentialSample = generator.nextUnit()
            let sphereFormAnchor = sphereFormAnchor(
                from: sphereAnchor,
                scatterSelector: scatterSelector,
                scatterRadialSample: scatterRadialSample,
                scatterTangentialSample: scatterTangentialSample,
                surfaceWeight: surfaceWeight
            )
            let customShapeAnchor = Self.customShapeAnchor(from: sphereAnchor)
            let activeAnchor = rebuildShapeTarget == .customShape
                ? customShapeAnchor
                : sphereFormAnchor
            let flowPhase = generator.nextUnit() * 2 * .pi
            let disturbancePhase = generator.nextUnit() * 2 * .pi
            let disturbancePhaseY = disturbancePhase
                * ParticleTuning.Engine.disturbanceYPhaseRatio
            let disturbancePhaseZ = disturbancePhase
                * ParticleTuning.Engine.disturbanceZPhaseRatio
            let particle = SimulatedParticle(
                sphereAnchor: sphereAnchor,
                customShapeAnchor: customShapeAnchor,
                flowPhaseSine: sin(flowPhase),
                flowPhaseCosine: cos(flowPhase),
                disturbancePhaseXSine: sin(disturbancePhase),
                disturbancePhaseXCosine: cos(disturbancePhase),
                disturbancePhaseYSine: sin(disturbancePhaseY),
                disturbancePhaseYCosine: cos(disturbancePhaseY),
                disturbancePhaseZSine: sin(disturbancePhaseZ),
                disturbancePhaseZCosine: cos(disturbancePhaseZ),
                scatterSelector: scatterSelector,
                scatterRadialSample: scatterRadialSample,
                scatterTangentialSample: scatterTangentialSample,
                surfaceWeight: surfaceWeight,
                morphStartAnchor: activeAnchor,
                morphTargetAnchor: activeAnchor,
                position: activeAnchor * sphereRadius,
                velocity: .zero
            )
            rebuilt.append(particle)
            sphereCenter += sphereFormAnchor
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
            let flowFrequency = ParticleTuning.Engine.amplifiedValue(
                tuning.flowSpeed,
                minimum: ParticleTuning.Engine.minimumFlowFrequency,
                maximum: ParticleTuning.Engine.maximumFlowFrequency
            )
            flowElapsedTime += timeStep * flowFrequency
            integrate(
                time: motionElapsedTime,
                flowTime: flowElapsedTime,
                timeStep: timeStep,
                visualState: visualState,
                morphProgress: Self.easedMorphProgress(shapeState.progress)
            )
        }

        return ParticleSimulationFrame(
            motionElapsedTime: motionElapsedTime,
            flowElapsedTime: flowElapsedTime,
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
        flowTime: Float,
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
        let flowMotionStrength = min(
            ParticleTuning.Engine.maximumFlowMotionStrength,
            ParticleTuning.Engine.amplifiedStrength(
                tuning.flowStrength
            ) * visualState.flowSpeedMultiplier
        )
        let flowAcceleration = flowMotionStrength
            * ParticleTuning.Engine.maximumFlowAcceleration
        let disturbanceAcceleration = ParticleTuning.Engine.amplifiedStrength(
            tuning.disturbanceStrength
        )
            * ParticleTuning.Engine.maximumDisturbanceAcceleration
            * (
                1
                    + visualState.disruptionStrength
                    * ParticleTuning.Engine.disruptionAccelerationIncrease
            )
        let baseFlowAxis = ParticleFlowDirection.nearest(
            to: tuning.flowDirection
        ).axis
        let flowEffect = ParticleFlowEffect.nearest(
            to: tuning.flowEffect
        )
        let flowEffectMotion = flowEffect.motionStyle
        let flowReference = abs(baseFlowAxis.y)
            < ParticleTuning.Engine.polarReferenceThreshold
            ? SIMD3<Float>(0, 1, 0)
            : SIMD3<Float>(1, 0, 0)
        let flowTangent = simd_normalize(simd_cross(flowReference, baseFlowAxis))
        let flowBitangent = simd_cross(baseFlowAxis, flowTangent)
        let flowEffectPhase = flowEffect.phaseOffset
            * ParticleTuning.Engine.fullRotation
        let axisPhase = flowTime
            * ParticleTuning.Engine.flowAxisPrecession
            * flowEffectMotion.x
            + flowEffectPhase
        let flowAxis = simd_normalize(
            baseFlowAxis
                + flowTangent
                * sin(axisPhase)
                * ParticleTuning.Engine.flowAxisTilt
                + flowBitangent
                * cos(
                    axisPhase
                        * ParticleTuning.Engine.flowAxisSecondaryRateRatio
                )
                * ParticleTuning.Engine.flowAxisTilt
        )
        let secondaryAxis = simd_normalize(ParticleTuning.Engine.secondaryFlowAxis)
        let particleFlowTime = flowTime
            * ParticleTuning.Engine.flowWaveFrequencyScale
            * flowEffectMotion.z
            + flowEffectPhase
        let primaryFlowSine = sin(particleFlowTime)
        let primaryFlowCosine = cos(particleFlowTime)
        let secondaryFlowTime = particleFlowTime
            * ParticleTuning.Engine.secondaryFlowFrequencyRatio
            * flowEffectMotion.y
        let secondaryFlowSine = sin(secondaryFlowTime)
        let secondaryFlowCosine = cos(secondaryFlowTime)
        let disturbanceXTime = time
            * ParticleTuning.Engine.disturbanceFrequency
        let disturbanceYTime = disturbanceXTime
            * ParticleTuning.Engine.disturbanceYFrequencyRatio
        let disturbanceZTime = disturbanceXTime
            * ParticleTuning.Engine.disturbanceZFrequencyRatio
        let disturbanceXTimeSine = sin(disturbanceXTime)
        let disturbanceXTimeCosine = cos(disturbanceXTime)
        let disturbanceYTimeSine = sin(disturbanceYTime)
        let disturbanceYTimeCosine = cos(disturbanceYTime)
        let disturbanceZTimeSine = sin(disturbanceZTime)
        let disturbanceZTimeCosine = cos(disturbanceZTime)
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
            let directionalFlow = baseFlowAxis
                - radial * simd_dot(baseFlowAxis, radial)
            let circulationFlow = simd_cross(flowAxis, radial)
            let particleFlowSine = primaryFlowSine * particle.flowPhaseCosine
                + primaryFlowCosine * particle.flowPhaseSine
            let flowPulse = ParticleTuning.Engine.minimumFlowPulse
                + (0.5 + 0.5 * particleFlowSine)
                * ParticleTuning.Engine.flowPulseRange
            let primaryFlow = directionalFlow
                * flowPulse
                * ParticleTuning.Engine.directionalFlowWeight
                * (1 - flowEffectMotion.w * 0.40)
                + circulationFlow
                * ParticleTuning.Engine.circulationFlowWeight
                * (0.60 + flowEffectMotion.w * 0.80)
            let secondaryFlow = simd_cross(secondaryAxis, radial)
                * (
                    secondaryFlowSine * particle.flowPhaseCosine
                        + secondaryFlowCosine * particle.flowPhaseSine
                )
                * ParticleTuning.Engine.secondaryFlowStrength
            let flowWeight = ParticleTuning.Engine.minimumFlowWeight
                + simd_length(shapeAnchor) * ParticleTuning.Engine.anchorFlowWeight
            let flowForce = (primaryFlow + secondaryFlow)
                * flowAcceleration
                * flowWeight

            var disturbance = SIMD3<Float>(
                disturbanceXTimeSine * particle.disturbancePhaseXCosine
                    + disturbanceXTimeCosine * particle.disturbancePhaseXSine,
                disturbanceYTimeSine * particle.disturbancePhaseYCosine
                    + disturbanceYTimeCosine * particle.disturbancePhaseYSine,
                disturbanceZTimeCosine * particle.disturbancePhaseZCosine
                    - disturbanceZTimeSine * particle.disturbancePhaseZSine
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

            let boundaryRadius = targetRadius
                * (
                    max(1, simd_length(shapeAnchor))
                        + ParticleTuning.Engine.boundaryMargin
                )
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
            return sphereFormAnchor(for: particle)
        case .customShape:
            return particle.customShapeAnchor
        case .text, .guidePath, .abstractResident, .realisticResident:
            return sphereFormAnchor(for: particle)
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

    private mutating func updateSphereFormTargets() {
        guard !particles.isEmpty else { return }
        let updatesSphereTarget = morphTransition.targetTarget == .sphere
        let updatesSettledSphere = updatesSphereTarget
            && morphTransition.currentTarget == .sphere
            && morphTransition.progress >= 1
        var center = SIMD3<Float>(repeating: 0)

        for index in particles.indices {
            let anchor = sphereFormAnchor(for: particles[index])
            center += anchor
            if updatesSphereTarget {
                particles[index].morphTargetAnchor = anchor
                if updatesSettledSphere {
                    particles[index].morphStartAnchor = anchor
                }
            }
        }

        sphereAnchorCenter = center / Float(particles.count)
        if updatesSphereTarget {
            morphTransition.targetCenter = sphereAnchorCenter
            if updatesSettledSphere {
                morphTransition.startCenter = sphereAnchorCenter
            }
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

    private func sphereFormAnchor(
        for particle: SimulatedParticle
    ) -> SIMD3<Float> {
        sphereFormAnchor(
            from: particle.sphereAnchor,
            scatterSelector: particle.scatterSelector,
            scatterRadialSample: particle.scatterRadialSample,
            scatterTangentialSample: particle.scatterTangentialSample,
            surfaceWeight: particle.surfaceWeight
        )
    }

    private func sphereFormAnchor(
        from sphereAnchor: SIMD3<Float>,
        scatterSelector: Float,
        scatterRadialSample: Float,
        scatterTangentialSample: Float,
        surfaceWeight: Float
    ) -> SIMD3<Float> {
        let strength = ParticleTuning.Engine.amplifiedStrength(
            tuning.shapeStrength
        )
        let scatterStrength = ParticleTuning.Engine.amplifiedStrength(
            tuning.scatterStrength
        )
        guard strength > ParticleTuning.Engine.normalizationEpsilon
                || scatterStrength > ParticleTuning.Engine.normalizationEpsilon else {
            return sphereAnchor
        }

        let radius = simd_length(sphereAnchor)
        guard radius > ParticleTuning.Engine.normalizationEpsilon else {
            return sphereAnchor
        }

        let normal = sphereAnchor / radius
        var shapedAnchor = sphereAnchor
        let shapePhase = (
            Float(tuning.shapeSeed) - 0.5
        ) * ParticleTuning.Engine.fullRotation
        let smoothness = Self.easedMorphProgress(
            Float(tuning.shapeSmoothness)
        )
        let featureScale = Self.easedMorphProgress(
            Float(tuning.shapeFeatureScale)
        )
        let lowLobeWeight =
            ParticleTuning.Engine.sphereFormLowLobeWeight
            * (
                1
                    - featureScale
                    * ParticleTuning.Engine.sphereFormLowLobeFeatureReduction
            )
        let mediumLobeWeight = (
            ParticleTuning.Engine.sphereFormMediumLobeMinimumWeight
                + featureScale
                * ParticleTuning.Engine.sphereFormMediumLobeWeightRange
        ) * (
            1
                - smoothness
                * ParticleTuning.Engine.sphereFormMediumSmoothnessReduction
        )
        let highLobeWeight = (
            ParticleTuning.Engine.sphereFormHighLobeMinimumWeight
                + featureScale
                * ParticleTuning.Engine.sphereFormHighLobeWeightRange
        ) * (
            1
                - smoothness
                * ParticleTuning.Engine.sphereFormHighSmoothnessReduction
        )
        let upperMediumLobeWeight = (
            ParticleTuning.Engine.sphereFormUpperMediumLobeMinimumWeight
                + featureScale
                * ParticleTuning.Engine.sphereFormUpperMediumLobeWeightRange
        ) * (
            1
                - smoothness
                * ParticleTuning.Engine.sphereFormUpperMediumSmoothnessReduction
        )
        let field = Self.organicSphereFormField(
            normal: normal,
            phase: shapePhase,
            lowLobeWeight: lowLobeWeight,
            mediumLobeWeight: mediumLobeWeight,
            upperMediumLobeWeight: upperMediumLobeWeight,
            highLobeWeight: highLobeWeight
        )
        let radiusScale = max(
            ParticleTuning.Engine.minimumSphereFormRadiusScale,
            1
                + field
                * strength
                * ParticleTuning.Engine.maximumSphereFormDisplacement
        )
        if strength > ParticleTuning.Engine.normalizationEpsilon {
            shapedAnchor = normal * radius * radiusScale
        }

        guard scatterStrength > ParticleTuning.Engine.normalizationEpsilon else {
            return shapedAnchor
        }

        let scatterPhase = (
            Float(tuning.scatterSeed) - 0.5
        ) * ParticleTuning.Engine.fullRotation
        let clusterFrequency = ParticleTuning.Engine.scatterMaximumClusterFrequency
            - Float(tuning.scatterClusterScale)
            * (
                ParticleTuning.Engine.scatterMaximumClusterFrequency
                    - ParticleTuning.Engine.scatterMinimumClusterFrequency
            )
        let clusterA = 0.5 + 0.5 * sin(
            simd_dot(
                normal,
                ParticleTuning.Engine.scatterPrimaryAxis
            ) * clusterFrequency
                + scatterPhase
        )
        let clusterB = 0.5 + 0.5 * cos(
            simd_dot(
                normal,
                ParticleTuning.Engine.scatterSecondaryAxis
            ) * clusterFrequency
                * ParticleTuning.Engine.scatterSecondaryFrequencyRatio
                - scatterPhase * 0.71
        )
        let rawCluster = min(
            1,
            max(
                0,
                clusterA * ParticleTuning.Engine.scatterPrimaryWeight
                    + clusterB * ParticleTuning.Engine.scatterSecondaryWeight
            )
        )
        let cluster = Self.easedMorphProgress(rawCluster)
        let clusterStrength = Float(tuning.scatterClusterStrength)
        let clusteredProbability =
            ParticleTuning.Engine.scatterClusterProbabilityMinimum
            + cluster * ParticleTuning.Engine.scatterClusterProbabilityRange
        let strongProbability = ParticleTuning.Engine.scatterStrongProbability
            + (
                clusteredProbability
                    - ParticleTuning.Engine.scatterStrongProbability
            ) * clusterStrength
        let radialBase = scatterSelector < strongProbability
            ? ParticleTuning.Engine.scatterStrongRadialDistance
            : ParticleTuning.Engine.scatterSoftRadialDistance
        let radialClusterScale = 1
            + (
                ParticleTuning.Engine.scatterRadialClusterMinimum
                    + cluster
                    * ParticleTuning.Engine.scatterRadialClusterRange
                    - 1
            ) * clusterStrength
        let tangentialClusterScale = 1
            + (
                ParticleTuning.Engine.scatterTangentialClusterMinimum
                    + cluster
                    * ParticleTuning.Engine.scatterTangentialClusterRange
                    - 1
            ) * clusterStrength
        let layerWeight = 0.35 + surfaceWeight * 0.65
        let radialDistance = radialBase
            * pow(
                scatterRadialSample,
                ParticleTuning.Engine.scatterRadialExponent
            )
            * scatterStrength
            * radialClusterScale
            * layerWeight
        let tangentReference = abs(normal.y)
            < ParticleTuning.Engine.polarReferenceThreshold
            ? SIMD3<Float>(0, 1, 0)
            : SIMD3<Float>(1, 0, 0)
        let tangent = simd_normalize(simd_cross(tangentReference, normal))
        let bitangent = simd_cross(normal, tangent)
        let tangentAngle = scatterTangentialSample
            * ParticleTuning.Engine.fullRotation
            + scatterPhase
        let tangentDirection = tangent * cos(tangentAngle)
            + bitangent * sin(tangentAngle)
        let tangentialDistance = (scatterTangentialSample - 0.5)
            * ParticleTuning.Engine.scatterTangentialDistance
            * scatterStrength
            * tangentialClusterScale
            * layerWeight
        return shapedAnchor
            + normal * radialDistance
            + tangentDirection * tangentialDistance
    }

    private static func organicSphereFormField(
        normal: SIMD3<Float>,
        phase: Float,
        lowLobeWeight: Float,
        mediumLobeWeight: Float,
        upperMediumLobeWeight: Float,
        highLobeWeight: Float
    ) -> Float {
        let xyField = sphereFormAngularField(
            first: normal.x,
            second: normal.y,
            phase: phase,
            offset: 0,
            lowLobeWeight: lowLobeWeight,
            mediumLobeWeight: mediumLobeWeight,
            upperMediumLobeWeight: upperMediumLobeWeight,
            highLobeWeight: highLobeWeight
        ) * ParticleTuning.Engine.sphereFormXYWeight
        let yzField = sphereFormAngularField(
            first: normal.y,
            second: normal.z,
            phase: phase,
            offset: ParticleTuning.Engine.sphereFormYZPhaseOffset,
            lowLobeWeight: lowLobeWeight,
            mediumLobeWeight: mediumLobeWeight,
            upperMediumLobeWeight: upperMediumLobeWeight,
            highLobeWeight: highLobeWeight
        ) * ParticleTuning.Engine.sphereFormYZWeight
        let zxField = sphereFormAngularField(
            first: normal.z,
            second: normal.x,
            phase: phase,
            offset: ParticleTuning.Engine.sphereFormZXPhaseOffset,
            lowLobeWeight: lowLobeWeight,
            mediumLobeWeight: mediumLobeWeight,
            upperMediumLobeWeight: upperMediumLobeWeight,
            highLobeWeight: highLobeWeight
        ) * ParticleTuning.Engine.sphereFormZXWeight
        let broadField =
            cos(
                simd_dot(
                    normal,
                    ParticleTuning.Engine.sphereFormBroadAxisA
                ) * ParticleTuning.Engine.sphereFormBroadFrequencyA
                    + phase
            ) * ParticleTuning.Engine.sphereFormBroadWeightA
            + cos(
                simd_dot(
                    normal,
                    ParticleTuning.Engine.sphereFormBroadAxisB
                ) * ParticleTuning.Engine.sphereFormBroadFrequencyB
                    + phase
                    * ParticleTuning.Engine.sphereFormBroadPhaseRatioB
            ) * ParticleTuning.Engine.sphereFormBroadWeightB
        return tanh(
            (
                xyField + yzField + zxField + broadField
            ) / ParticleTuning.Engine.sphereFormFieldNormalization
                * ParticleTuning.Engine.sphereFormFieldGain
        )
    }

    private static func sphereFormAngularField(
        first: Float,
        second: Float,
        phase: Float,
        offset: Float,
        lowLobeWeight: Float,
        mediumLobeWeight: Float,
        upperMediumLobeWeight: Float,
        highLobeWeight: Float
    ) -> Float {
        let radialWeight = pow(
            sqrt(first * first + second * second),
            ParticleTuning.Engine.sphereFormAngularFalloff
        )
        let angle = atan2(second, first)
        let baseField = sin(
            angle * ParticleTuning.Engine.sphereFormBaseLobeCount
                + phase
                * ParticleTuning.Engine.sphereFormBasePhaseRatio
                + offset
                * ParticleTuning.Engine.sphereFormBaseOffsetRatio
        ) * ParticleTuning.Engine.sphereFormBaseLobeWeight
        let lowField = sin(
            angle * ParticleTuning.Engine.sphereFormLowLobeCount
                + phase
                + offset
        ) * lowLobeWeight
        let mediumField = sin(
            angle * ParticleTuning.Engine.sphereFormMediumLobeCount
                + phase
                * ParticleTuning.Engine.sphereFormMediumPhaseRatio
                + offset
                * ParticleTuning.Engine.sphereFormMediumOffsetRatio
        ) * mediumLobeWeight
        let upperMediumField = sin(
            angle * ParticleTuning.Engine.sphereFormUpperMediumLobeCount
                + phase
                * ParticleTuning.Engine.sphereFormUpperMediumPhaseRatio
                + offset
                * ParticleTuning.Engine.sphereFormUpperMediumOffsetRatio
        ) * upperMediumLobeWeight
        let highField = sin(
            angle * ParticleTuning.Engine.sphereFormHighLobeCount
                + phase
                * ParticleTuning.Engine.sphereFormHighPhaseRatio
                + offset
                * ParticleTuning.Engine.sphereFormHighOffsetRatio
        ) * highLobeWeight
        return (
            baseField
                + lowField
                + mediumField
                + upperMediumField
                + highField
        ) * radialWeight
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
