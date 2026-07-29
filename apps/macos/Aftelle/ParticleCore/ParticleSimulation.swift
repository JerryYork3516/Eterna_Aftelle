import Foundation
import simd

enum ParticleShapeMorphTuning {
    static let defaultDuration = 1.0
    static let minimumDuration = 0.8
    static let maximumDuration = 1.2
    static let minimumLifeMotionScale: Float = 0.34
    static let minimumBreathingScale: Float = 0.78
    static let completionTolerance: Float = 0.000_001
    static let retargetStartTolerance: Float = 0.000_001
    static let maximumAnchorRadius: Float = 1.9
    static let maximumPositionRadius: Float = 2.5
}

enum ParticleShapeTarget: String, CaseIterable, Equatable, Identifiable {
    case sphere
    case customShape
    case abstractBust
    case text
    case guidePath
    case abstractResident
    case realisticResident

    var id: String {
        rawValue
    }

    var isImplemented: Bool {
        self == .sphere || self == .customShape || self == .abstractBust
    }

    var supportsMorph: Bool {
        self == .sphere || self == .customShape || self == .abstractBust
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
    let retargetStartError: Float
    let sphereToBustCompletionError: Float
    let bustToSphereCompletionError: Float
    let maximumAnchorRadius: Float
    let maximumPositionRadius: Float
    let duplicateRequestIgnored: Bool
    let monotonicProgressPreserved: Bool
    let stressSwitchCount: Int
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

private struct SphereFormSample {
    let value: Float
    let tangentGradient: SIMD3<Float>
}

private struct SimulatedParticle {
    let sphereAnchor: SIMD3<Float>
    let customShapeAnchor: SIMD3<Float>
    let abstractBustAnchor: SIMD3<Float>
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
    private var abstractBustAnchorCenter = SIMD3<Float>(repeating: 0)
    private var currentShapeRadius: Float = 1
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
            duration: ParticleShapeMorphTuning.defaultDuration,
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
        let abstractBustAnchors = AbstractBustAnchorGenerator.generate(
            count: count,
            seed: ParticleTuning.Engine.modelSeed
        )
        var rebuilt: [SimulatedParticle] = []
        rebuilt.reserveCapacity(count)
        var sphereCenter = SIMD3<Float>(repeating: 0)
        var customShapeCenter = SIMD3<Float>(repeating: 0)
        var abstractBustCenter = SIMD3<Float>(repeating: 0)

        let activeRadius = sphereRadius
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
            let abstractBustAnchor = abstractBustAnchors[index]
            let activeAnchor: SIMD3<Float>
            switch rebuildShapeTarget {
            case .sphere:
                activeAnchor = sphereFormAnchor
            case .customShape:
                activeAnchor = customShapeAnchor
            case .abstractBust:
                activeAnchor = abstractBustAnchor
            case .text, .guidePath, .abstractResident, .realisticResident:
                activeAnchor = sphereFormAnchor
            }
            let flowPhase = generator.nextUnit() * 2 * .pi
            let disturbancePhase = generator.nextUnit() * 2 * .pi
            let disturbancePhaseY = disturbancePhase
                * ParticleTuning.Engine.disturbanceYPhaseRatio
            let disturbancePhaseZ = disturbancePhase
                * ParticleTuning.Engine.disturbanceZPhaseRatio
            let particle = SimulatedParticle(
                sphereAnchor: sphereAnchor,
                customShapeAnchor: customShapeAnchor,
                abstractBustAnchor: abstractBustAnchor,
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
                position: activeAnchor * activeRadius,
                velocity: .zero
            )
            rebuilt.append(particle)
            sphereCenter += sphereFormAnchor
            customShapeCenter += customShapeAnchor
            abstractBustCenter += abstractBustAnchor
        }

        particles = rebuilt
        let divisor = Float(max(count, 1))
        sphereAnchorCenter = sphereCenter / divisor
        customShapeAnchorCenter = customShapeCenter / divisor
        abstractBustAnchorCenter = abstractBustCenter / divisor
        currentShapeRadius = activeRadius
        let activeCenter = shapeCenter(for: rebuildShapeTarget)
        morphTransition = ParticleMorphTransition(
            currentTarget: rebuildShapeTarget,
            targetTarget: rebuildShapeTarget,
            startCenter: activeCenter,
            targetCenter: activeCenter,
            startTime: previousMorphTime,
            duration: ParticleShapeMorphTuning.defaultDuration,
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
        time: TimeInterval,
        duration: TimeInterval = ParticleShapeMorphTuning.defaultDuration
    ) -> Bool {
        guard target.supportsMorph,
              morphTransition.targetTarget != target else {
            return false
        }

        let monotonicTime = updateMorphClock(time: time)
        _ = resolveMorphProgress(time: monotonicTime)
        settleCompletedMorph()
        let radius = max(
            currentShapeRadius,
            ParticleTuning.Engine.normalizationEpsilon
        )
        var currentCenter = SIMD3<Float>(repeating: 0)
        for index in particles.indices {
            let currentAnchor = particles[index].position / radius
            particles[index].morphStartAnchor = currentAnchor
            particles[index].morphTargetAnchor = shapeAnchor(
                for: target,
                particle: particles[index]
            )
            currentCenter += currentAnchor
        }
        currentCenter /= Float(max(particles.count, 1))
        morphTransition = ParticleMorphTransition(
            currentTarget: morphTransition.targetTarget,
            targetTarget: target,
            startCenter: currentCenter,
            targetCenter: shapeCenter(for: target),
            startTime: monotonicTime,
            duration: Self.clampedMorphDuration(duration),
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
        let duration = ParticleShapeMorphTuning.defaultDuration
        let visualController = ParticleStateController(
            intent: .idle,
            time: time
        )

        if simulation.targetShape != .sphere {
            _ = simulation.setShapeTarget(
                .sphere,
                reason: "debugMorph.prepareSphere",
                time: time,
                duration: duration
            )
            time += duration
            _ = simulation.resolvedAnchors(time: time)
        }

        _ = simulation.setShapeTarget(
            .abstractBust,
            reason: "debugMorph.sphereToBust",
            time: time,
            duration: duration
        )
        let transitionStartTime = simulation.morphTransition.startTime
        let duplicateRequestIgnored = !simulation.setShapeTarget(
            .abstractBust,
            reason: "debugMorph.duplicate",
            time: time + 0.01,
            duration: duration
        ) && simulation.morphTransition.startTime == transitionStartTime
        let forwardTime = simulation.updateMorphClock(time: time + 0.02)
        let forwardProgress = simulation.resolveMorphProgress(
            time: forwardTime
        )
        let backwardTime = simulation.updateMorphClock(time: time + 0.01)
        let backwardProgress = simulation.resolveMorphProgress(
            time: backwardTime
        )
        let monotonicProgressPreserved =
            backwardProgress >= forwardProgress

        time += duration
        let bustResolved = simulation.resolvedAnchors(time: time)
        let bustTargets = simulation.shapeAnchors(for: .abstractBust)
        let sphereToBustCompletionError = Self.maximumAnchorDifference(
            bustResolved,
            bustTargets
        )

        _ = simulation.setShapeTarget(
            .sphere,
            reason: "debugMorph.bustToSphere",
            time: time,
            duration: duration
        )
        time += duration
        let sphereResolved = simulation.resolvedAnchors(time: time)
        let sphereTargets = simulation.shapeAnchors(for: .sphere)
        let bustToSphereCompletionError = Self.maximumAnchorDifference(
            sphereResolved,
            sphereTargets
        )

        _ = simulation.setShapeTarget(
            .abstractBust,
            reason: "debugMorph.interruptPrepare",
            time: time,
            duration: duration
        )
        for _ in 0..<24 {
            time += 1.0 / 60.0
            let visualState = visualController.advance(time: time)
            _ = simulation.advance(
                time: time,
                drawableSize: CGSize(width: 800, height: 800),
                visualState: visualState
            )
        }
        let beforeRetarget = simulation.vertexPayloads
        _ = simulation.setShapeTarget(
            .sphere,
            reason: "debugMorph.retarget",
            time: time,
            duration: duration
        )
        let afterRetarget = simulation.vertexPayloads
        let continuityError = Self.maximumPayloadPositionDifference(
            beforeRetarget,
            afterRetarget
        )
        let retargetStartError = Self.maximumAnchorDifference(
            simulation.resolvedAnchors(time: time),
            simulation.currentPositionAnchors()
        )

        for index in 0..<ParticleTuning.Engine.debugStressSwitchCount {
            time += ParticleTuning.Engine.debugMorphSwitchInterval
            let target: ParticleShapeTarget = index.isMultiple(of: 2)
                ? .abstractBust
                : .sphere
            _ = simulation.setShapeTarget(
                target,
                reason: "debugMorph.stress",
                time: time,
                duration: duration
            )
            let visualState = visualController.advance(time: time)
            _ = simulation.advance(
                time: time,
                drawableSize: CGSize(width: 800, height: 800),
                visualState: visualState
            )
        }

        let progressBeforePause = simulation.resolveMorphProgress(time: time)
        let resumeTime = time + ParticleTuning.Engine.debugResumeInterval
        let monotonicResumeTime = simulation.updateMorphClock(time: resumeTime)
        let progressAfterPause = simulation.resolveMorphProgress(
            time: monotonicResumeTime
        )
        let resumeProgressStep = progressAfterPause - progressBeforePause
        let finiteAnchors = simulation.resolvedAnchors(
            time: resumeTime
        ).allSatisfy { anchor in
            anchor.x.isFinite && anchor.y.isFinite && anchor.z.isFinite
        }
        let maximumAnchorRadius = simulation.resolvedAnchors(
            time: resumeTime
        ).reduce(Float.zero) {
            max($0, simd_length($1))
        }
        let finitePayloads = simulation.vertexPayloads.allSatisfy {
            $0.x.isFinite
                && $0.y.isFinite
                && $0.z.isFinite
                && $0.w.isFinite
        }
        let maximumPositionRadius = simulation.vertexPayloads.reduce(
            Float.zero
        ) {
            max(
                $0,
                simd_length(SIMD3<Float>($1.x, $1.y, $1.z))
            )
        }
        let particleCountAfter = simulation.particleCount
        let rebuildCountAfter = simulation.rebuildCount
        let passed = finiteAnchors
            && finitePayloads
            && continuityError
                <= ParticleTuning.Engine.debugContinuityTolerance
            && retargetStartError
                <= ParticleShapeMorphTuning.retargetStartTolerance
            && sphereToBustCompletionError
                <= ParticleShapeMorphTuning.completionTolerance
            && bustToSphereCompletionError
                <= ParticleShapeMorphTuning.completionTolerance
            && maximumAnchorRadius
                <= ParticleShapeMorphTuning.maximumAnchorRadius
            && maximumPositionRadius
                <= ParticleShapeMorphTuning.maximumPositionRadius
            && duplicateRequestIgnored
            && monotonicProgressPreserved
            && resumeProgressStep
                <= ParticleTuning.Engine.debugMaximumPauseProgressStep
            && particleCountBefore == particleCountAfter
            && rebuildCountBefore == rebuildCountAfter

        return ParticleMorphDebugResult(
            passed: passed,
            continuityError: continuityError,
            retargetStartError: retargetStartError,
            sphereToBustCompletionError: sphereToBustCompletionError,
            bustToSphereCompletionError: bustToSphereCompletionError,
            maximumAnchorRadius: maximumAnchorRadius,
            maximumPositionRadius: maximumPositionRadius,
            duplicateRequestIgnored: duplicateRequestIgnored,
            monotonicProgressPreserved: monotonicProgressPreserved,
            stressSwitchCount:
                ParticleTuning.Engine.debugStressSwitchCount,
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
        let morphTime = updateMorphClock(time: time)
        let shapeState = resolveShapeState(time: morphTime)
        let timeStep = min(
            max(Float(time - previousTime), 0),
            ParticleTuning.Engine.maximumSimulationStep
        )
        previousTime = time
        if timeStep > 0 {
            motionElapsedTime += timeStep
            let expression = visualState.expression.appliedMultipliers
            let flowFrequency = ParticleTuning.Engine.amplifiedValue(
                tuning.flowSpeed,
                minimum: ParticleTuning.Engine.minimumFlowFrequency,
                maximum: ParticleTuning.Engine.maximumFlowFrequency
            )
            flowElapsedTime += expression.applyingMotionSpeed(
                to: timeStep
                    * flowFrequency
                    * visualState.flowSpeedMultiplier
            )
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
        let morphConstraint = sin(
            .pi * min(1, max(0, morphProgress))
        )
        let morphBreathingScale = 1
            - morphConstraint
            * (1 - ParticleShapeMorphTuning.minimumBreathingScale)
        let breathingAmplitude = ParticleTuning.Engine.amplifiedStrength(
            tuning.breathingAmount
        )
            * ParticleTuning.Engine.maximumBreathingScale
            * morphBreathingScale
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
        let stateRadiusScale = 1
            - visualState.focusStrength
            * ParticleTuning.Engine.stateFocusRadiusReduction
            - visualState.dissolutionStrength
            * ParticleTuning.Engine.stateDissolutionRadiusReduction
        let targetRadius = baseRadius
            * breathingScale
            * pulseScale
            * stateRadiusScale
        currentShapeRadius = targetRadius
        let morphLifeMotionScale = 1
            - morphConstraint
            * (1 - ParticleShapeMorphTuning.minimumLifeMotionScale)
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
        let flowMotionStrength = visualState.expression.appliedMultipliers
            .applyingEnergy(
                to: ParticleTuning.Engine.amplifiedStrength(
                    tuning.flowStrength
                ) * visualState.flowSpeedMultiplier,
                maximum: ParticleTuning.Engine.maximumFlowMotionStrength
            )
        let flowAcceleration = flowMotionStrength
            * ParticleTuning.Engine.maximumFlowAcceleration
            * morphLifeMotionScale
        let disturbanceAcceleration = ParticleTuning.Engine.amplifiedStrength(
            tuning.disturbanceStrength
        )
            * ParticleTuning.Engine.maximumDisturbanceAcceleration
            * morphLifeMotionScale
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
            let disruptionWave = disturbanceXTimeSine
                * particle.disturbancePhaseXCosine
                + disturbanceXTimeCosine
                * particle.disturbancePhaseXSine
            let disruptionRadiusScale = 1
                + visualState.disruptionStrength
                * ParticleTuning.Engine.stateDisruptionRadiusScale
                * disruptionWave
            let target = shapeAnchor
                * targetRadius
                * disruptionRadiusScale
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

    @discardableResult
    private mutating func updateMorphClock(
        time: TimeInterval
    ) -> TimeInterval {
        let monotonicTime = max(time, previousMorphTime)
        let rawDelta = monotonicTime - previousMorphTime
        let maximumDelta = TimeInterval(
            ParticleTuning.Engine.maximumSimulationStep
        )
        let discardedDelta = rawDelta - min(rawDelta, maximumDelta)
        if discardedDelta > 0, morphTransition.progress < 1 {
            morphTransition.startTime += discardedDelta
        }
        previousMorphTime = monotonicTime
        return monotonicTime
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
        case .abstractBust:
            return particle.abstractBustAnchor
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
        case .abstractBust:
            return abstractBustAnchorCenter
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

    private func currentPositionAnchors() -> [SIMD3<Float>] {
        let radius = max(
            currentShapeRadius,
            ParticleTuning.Engine.normalizationEpsilon
        )
        return particles.map { $0.position / radius }
    }

    private func shapeAnchors(
        for target: ParticleShapeTarget
    ) -> [SIMD3<Float>] {
        particles.map { shapeAnchor(for: target, particle: $0) }
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

    private static func maximumPayloadPositionDifference(
        _ lhs: [SIMD4<Float>],
        _ rhs: [SIMD4<Float>]
    ) -> Float {
        guard lhs.count == rhs.count else { return .infinity }
        var maximumDifference: Float = 0
        for index in lhs.indices {
            let difference = SIMD3<Float>(
                lhs[index].x - rhs[index].x,
                lhs[index].y - rhs[index].y,
                lhs[index].z - rhs[index].z
            )
            maximumDifference = max(
                maximumDifference,
                simd_length(difference)
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
        var shapedNormal = normal
        if strength > ParticleTuning.Engine.normalizationEpsilon {
            let formSample = Self.organicSphereFormSample(
                normal: normal,
                phase: shapePhase,
                lowLobeWeight: lowLobeWeight,
                mediumLobeWeight: mediumLobeWeight,
                upperMediumLobeWeight: upperMediumLobeWeight,
                highLobeWeight: highLobeWeight
            )
            let densityWarp = Self.densityWarpedSphereDirection(
                normal: normal,
                gradient: formSample.tangentGradient,
                strength: strength
            )
            shapedNormal = densityWarp.normal
            let field = min(
                1,
                max(
                    -1,
                    formSample.value
                        + simd_dot(
                            densityWarp.gradient,
                            shapedNormal - normal
                        )
                        * ParticleTuning.Engine.sphereFormDensityFieldFollow
                )
            )
            let radiusScale = max(
                ParticleTuning.Engine.minimumSphereFormRadiusScale,
                1
                    + field
                    * strength
                    * ParticleTuning.Engine.maximumSphereFormDisplacement
            )
            shapedAnchor = shapedNormal * radius * radiusScale
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
                shapedNormal,
                ParticleTuning.Engine.scatterPrimaryAxis
            ) * clusterFrequency
                + scatterPhase
        )
        let clusterB = 0.5 + 0.5 * cos(
            simd_dot(
                shapedNormal,
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
        let tangentReference = abs(shapedNormal.y)
            < ParticleTuning.Engine.polarReferenceThreshold
            ? SIMD3<Float>(0, 1, 0)
            : SIMD3<Float>(1, 0, 0)
        let tangent = simd_normalize(
            simd_cross(tangentReference, shapedNormal)
        )
        let bitangent = simd_cross(shapedNormal, tangent)
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
            + shapedNormal * radialDistance
            + tangentDirection * tangentialDistance
    }

    private static func densityWarpedSphereDirection(
        normal: SIMD3<Float>,
        gradient: SIMD3<Float>,
        strength: Float
    ) -> (normal: SIMD3<Float>, gradient: SIMD3<Float>) {
        let warpStrength = min(
            ParticleTuning.Engine.sphereFormMaximumDensityWarp,
            strength * ParticleTuning.Engine.sphereFormDensityWarpStrength
        )
        guard warpStrength > ParticleTuning.Engine.normalizationEpsilon else {
            return (normal, .zero)
        }

        var limitedGradient = gradient
        let gradientLength = simd_length(limitedGradient)
        if gradientLength > ParticleTuning.Engine.sphereFormDensityGradientLimit {
            limitedGradient *= ParticleTuning.Engine.sphereFormDensityGradientLimit
                / gradientLength
        }
        return (
            safeNormalize(
                normal + limitedGradient * warpStrength,
                fallback: normal
            ),
            limitedGradient
        )
    }

    private static func organicSphereFormSample(
        normal: SIMD3<Float>,
        phase: Float,
        lowLobeWeight: Float,
        mediumLobeWeight: Float,
        upperMediumLobeWeight: Float,
        highLobeWeight: Float
    ) -> SphereFormSample {
        let xyField = sphereFormAngularField(
            first: normal.x,
            second: normal.y,
            phase: phase,
            offset: 0,
            lowLobeWeight: lowLobeWeight,
            mediumLobeWeight: mediumLobeWeight,
            upperMediumLobeWeight: upperMediumLobeWeight,
            highLobeWeight: highLobeWeight
        )
        let yzField = sphereFormAngularField(
            first: normal.y,
            second: normal.z,
            phase: phase,
            offset: ParticleTuning.Engine.sphereFormYZPhaseOffset,
            lowLobeWeight: lowLobeWeight,
            mediumLobeWeight: mediumLobeWeight,
            upperMediumLobeWeight: upperMediumLobeWeight,
            highLobeWeight: highLobeWeight
        )
        let zxField = sphereFormAngularField(
            first: normal.z,
            second: normal.x,
            phase: phase,
            offset: ParticleTuning.Engine.sphereFormZXPhaseOffset,
            lowLobeWeight: lowLobeWeight,
            mediumLobeWeight: mediumLobeWeight,
            upperMediumLobeWeight: upperMediumLobeWeight,
            highLobeWeight: highLobeWeight
        )
        let broadPhaseA = simd_dot(
            normal,
            ParticleTuning.Engine.sphereFormBroadAxisA
        )
            * ParticleTuning.Engine.sphereFormBroadFrequencyA
            + phase
        let broadPhaseB = simd_dot(
            normal,
            ParticleTuning.Engine.sphereFormBroadAxisB
        )
            * ParticleTuning.Engine.sphereFormBroadFrequencyB
            + phase * ParticleTuning.Engine.sphereFormBroadPhaseRatioB
        let combinedField =
            xyField * ParticleTuning.Engine.sphereFormXYWeight
            + yzField * ParticleTuning.Engine.sphereFormYZWeight
            + zxField * ParticleTuning.Engine.sphereFormZXWeight
            + cos(broadPhaseA) * ParticleTuning.Engine.sphereFormBroadWeightA
            + cos(broadPhaseB) * ParticleTuning.Engine.sphereFormBroadWeightB
        let xyDensityGradient = sphereFormDensityAngularGradient(
            first: normal.x,
            second: normal.y,
            phase: phase,
            offset: 0,
            lowLobeWeight: lowLobeWeight
        )
        let yzDensityGradient = sphereFormDensityAngularGradient(
            first: normal.y,
            second: normal.z,
            phase: phase,
            offset: ParticleTuning.Engine.sphereFormYZPhaseOffset,
            lowLobeWeight: lowLobeWeight
        )
        let zxDensityGradient = sphereFormDensityAngularGradient(
            first: normal.z,
            second: normal.x,
            phase: phase,
            offset: ParticleTuning.Engine.sphereFormZXPhaseOffset,
            lowLobeWeight: lowLobeWeight
        )
        let angularDensityGradient = SIMD3<Float>(
            xyDensityGradient.x * ParticleTuning.Engine.sphereFormXYWeight
                + zxDensityGradient.y * ParticleTuning.Engine.sphereFormZXWeight,
            xyDensityGradient.y * ParticleTuning.Engine.sphereFormXYWeight
                + yzDensityGradient.x * ParticleTuning.Engine.sphereFormYZWeight,
            yzDensityGradient.y * ParticleTuning.Engine.sphereFormYZWeight
                + zxDensityGradient.x * ParticleTuning.Engine.sphereFormZXWeight
        ) * ParticleTuning.Engine.sphereFormDensityAngularWeight
        let broadGradientA = ParticleTuning.Engine.sphereFormBroadAxisA
            * (
                -sin(broadPhaseA)
                    * ParticleTuning.Engine.sphereFormBroadFrequencyA
                    * ParticleTuning.Engine.sphereFormBroadWeightA
            )
        let broadGradientB = ParticleTuning.Engine.sphereFormBroadAxisB
            * (
                -sin(broadPhaseB)
                    * ParticleTuning.Engine.sphereFormBroadFrequencyB
                    * ParticleTuning.Engine.sphereFormBroadWeightB
            )
        let combinedGradient =
            angularDensityGradient + broadGradientA + broadGradientB
        let fieldScale = ParticleTuning.Engine.sphereFormFieldGain
            / ParticleTuning.Engine.sphereFormFieldNormalization
        let value = tanh(combinedField * fieldScale)
        let gradient = combinedGradient
            * fieldScale
            * (1 - value * value)
        return SphereFormSample(
            value: value,
            tangentGradient: gradient
                - normal * simd_dot(gradient, normal)
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

    private static func sphereFormDensityAngularGradient(
        first: Float,
        second: Float,
        phase: Float,
        offset: Float,
        lowLobeWeight: Float
    ) -> SIMD2<Float> {
        let radiusSquared = first * first + second * second
        guard radiusSquared > ParticleTuning.Engine.normalizationEpsilon else {
            return .zero
        }

        let radialWeight = pow(
            sqrt(radiusSquared),
            ParticleTuning.Engine.sphereFormAngularFalloff
        )
        let angle = atan2(second, first)
        let basePhase =
            angle * ParticleTuning.Engine.sphereFormBaseLobeCount
                + phase
                * ParticleTuning.Engine.sphereFormBasePhaseRatio
                + offset
                * ParticleTuning.Engine.sphereFormBaseOffsetRatio
        let lowPhase =
            angle * ParticleTuning.Engine.sphereFormLowLobeCount
                + phase
                + offset
        let angularValue =
            sin(basePhase) * ParticleTuning.Engine.sphereFormBaseLobeWeight
            + sin(lowPhase) * lowLobeWeight
        let angularDerivative =
            cos(basePhase)
            * ParticleTuning.Engine.sphereFormBaseLobeCount
            * ParticleTuning.Engine.sphereFormBaseLobeWeight
            + cos(lowPhase)
            * ParticleTuning.Engine.sphereFormLowLobeCount
            * lowLobeWeight
        let radialDerivativeScale =
            ParticleTuning.Engine.sphereFormAngularFalloff
            * radialWeight
            / radiusSquared
        let angularDerivativeScale = radialWeight / radiusSquared
        return SIMD2<Float>(
            radialDerivativeScale * first * angularValue
                - angularDerivativeScale * second * angularDerivative,
            radialDerivativeScale * second * angularValue
                + angularDerivativeScale * first * angularDerivative
        )
    }

    private static func easedMorphProgress(_ progress: Float) -> Float {
        progress * progress * progress
            * (progress * (progress * 6 - 15) + 10)
    }

    private static func clampedMorphDuration(
        _ duration: TimeInterval
    ) -> TimeInterval {
        min(
            ParticleShapeMorphTuning.maximumDuration,
            max(
                ParticleShapeMorphTuning.minimumDuration,
                duration
            )
        )
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
