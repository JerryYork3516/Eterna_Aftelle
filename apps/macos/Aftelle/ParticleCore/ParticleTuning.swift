import Foundation
import simd

struct ParticleVisualProfile {
    let focus: Float
    let pulse: Float
    let circulation: Float
    let disruption: Float
    let dissolution: Float
}

struct ParticleTuning: Codable, Equatable {
    var sphereRadius: Double
    var globalScale: Double
    var shapeStrength: Double
    var shapeFeatureScale: Double
    var shapeSmoothness: Double
    var shapeSeed: Double
    var surfaceRatio: Double
    var surfaceLightStrength: Double
    var ridgeStrength: Double
    var ridgeWidth: Double
    var ridgeBreakup: Double
    var ridgeSeed: Double
    var ridgeFlowBinding: Double
    var breathingAmount: Double
    var breathingSpeed: Double
    var flowStrength: Double
    var flowShapeStrength: Double
    var flowSpeed: Double
    var flowDirection: Double
    var flowEffect: Double
    var flowBrightnessStrength: Double
    var rotationSpeed: Double
    var rotationDirection: Double
    var disturbanceStrength: Double
    var aggregationStrength: Double
    var damping: Double
    var edgeDustAmount: Double
    var edgeFrayAmount: Double
    var scatterStrength: Double
    var scatterClusterStrength: Double
    var scatterClusterScale: Double
    var scatterSeed: Double
    var pointSizeScale: Double
    var brightness: Double
    var alphaScale: Double

    init(
        sphereRadius: Double,
        globalScale: Double,
        shapeStrength: Double,
        shapeFeatureScale: Double,
        shapeSmoothness: Double,
        shapeSeed: Double,
        surfaceRatio: Double,
        surfaceLightStrength: Double,
        ridgeStrength: Double,
        ridgeWidth: Double,
        ridgeBreakup: Double,
        ridgeSeed: Double,
        ridgeFlowBinding: Double,
        breathingAmount: Double,
        breathingSpeed: Double,
        flowStrength: Double,
        flowShapeStrength: Double,
        flowSpeed: Double,
        flowDirection: Double,
        flowEffect: Double,
        flowBrightnessStrength: Double,
        rotationSpeed: Double,
        rotationDirection: Double,
        disturbanceStrength: Double,
        aggregationStrength: Double,
        damping: Double,
        edgeDustAmount: Double,
        edgeFrayAmount: Double,
        scatterStrength: Double,
        scatterClusterStrength: Double,
        scatterClusterScale: Double,
        scatterSeed: Double,
        pointSizeScale: Double,
        brightness: Double,
        alphaScale: Double
    ) {
        self.sphereRadius = sphereRadius
        self.globalScale = globalScale
        self.shapeStrength = shapeStrength
        self.shapeFeatureScale = shapeFeatureScale
        self.shapeSmoothness = shapeSmoothness
        self.shapeSeed = shapeSeed
        self.surfaceRatio = surfaceRatio
        self.surfaceLightStrength = surfaceLightStrength
        self.ridgeStrength = ridgeStrength
        self.ridgeWidth = ridgeWidth
        self.ridgeBreakup = ridgeBreakup
        self.ridgeSeed = ridgeSeed
        self.ridgeFlowBinding = ridgeFlowBinding
        self.breathingAmount = breathingAmount
        self.breathingSpeed = breathingSpeed
        self.flowStrength = flowStrength
        self.flowShapeStrength = flowShapeStrength
        self.flowSpeed = flowSpeed
        self.flowDirection = flowDirection
        self.flowEffect = flowEffect
        self.flowBrightnessStrength = flowBrightnessStrength
        self.rotationSpeed = rotationSpeed
        self.rotationDirection = rotationDirection
        self.disturbanceStrength = disturbanceStrength
        self.aggregationStrength = aggregationStrength
        self.damping = damping
        self.edgeDustAmount = edgeDustAmount
        self.edgeFrayAmount = edgeFrayAmount
        self.scatterStrength = scatterStrength
        self.scatterClusterStrength = scatterClusterStrength
        self.scatterClusterScale = scatterClusterScale
        self.scatterSeed = scatterSeed
        self.pointSizeScale = pointSizeScale
        self.brightness = brightness
        self.alphaScale = alphaScale
    }

    static let systemDefault = ParticleTuning(
        sphereRadius: 0.5,
        globalScale: 0.5,
        shapeStrength: 0,
        shapeFeatureScale: 0,
        shapeSmoothness: 0,
        shapeSeed: 0.5,
        surfaceRatio: 0.62,
        surfaceLightStrength: 0.5,
        ridgeStrength: 0,
        ridgeWidth: 0.5,
        ridgeBreakup: 0.5,
        ridgeSeed: 0.5,
        ridgeFlowBinding: 0.5,
        breathingAmount: 0.34,
        breathingSpeed: 0.34,
        flowStrength: 0.38,
        flowShapeStrength: 0.38,
        flowSpeed: 0.32,
        flowDirection: 1,
        flowEffect: 0,
        flowBrightnessStrength: 0,
        rotationSpeed: 0,
        rotationDirection: 1,
        disturbanceStrength: 0.24,
        aggregationStrength: 0.58,
        damping: 0.58,
        edgeDustAmount: 0,
        edgeFrayAmount: 0,
        scatterStrength: 0,
        scatterClusterStrength: 0.5,
        scatterClusterScale: 0.5,
        scatterSeed: 0.5,
        pointSizeScale: 0.42,
        brightness: 0.46,
        alphaScale: 0.5
    )

    static let storageKey = "ParticleCoreTuning.debug.v2"

    private enum CodingKeys: String, CodingKey {
        case sphereRadius
        case globalScale
        case shapeStrength
        case shapeFeatureScale
        case shapeSmoothness
        case shapeSeed
        case surfaceRatio
        case surfaceLightStrength
        case ridgeStrength
        case ridgeWidth
        case ridgeBreakup
        case ridgeSeed
        case ridgeFlowBinding
        case breathingAmount
        case breathingSpeed
        case flowStrength
        case flowShapeStrength
        case flowSpeed
        case flowDirection
        case flowEffect
        case flowBrightnessStrength
        case rotationSpeed
        case rotationDirection
        case disturbanceStrength
        case aggregationStrength
        case damping
        case edgeDustAmount
        case edgeFrayAmount
        case scatterStrength
        case scatterClusterStrength
        case scatterClusterScale
        case scatterSeed
        case pointSizeScale
        case brightness
        case alphaScale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.systemDefault
        self.init(
            sphereRadius: try container.decodeIfPresent(Double.self, forKey: .sphereRadius)
                ?? defaults.sphereRadius,
            globalScale: try container.decodeIfPresent(Double.self, forKey: .globalScale)
                ?? defaults.globalScale,
            shapeStrength: try container.decodeIfPresent(Double.self, forKey: .shapeStrength)
                ?? defaults.shapeStrength,
            shapeFeatureScale: try container.decodeIfPresent(Double.self, forKey: .shapeFeatureScale)
                ?? defaults.shapeFeatureScale,
            shapeSmoothness: try container.decodeIfPresent(Double.self, forKey: .shapeSmoothness)
                ?? defaults.shapeSmoothness,
            shapeSeed: try container.decodeIfPresent(Double.self, forKey: .shapeSeed)
                ?? defaults.shapeSeed,
            surfaceRatio: try container.decodeIfPresent(Double.self, forKey: .surfaceRatio)
                ?? defaults.surfaceRatio,
            surfaceLightStrength: try container.decodeIfPresent(
                Double.self,
                forKey: .surfaceLightStrength
            ) ?? defaults.surfaceLightStrength,
            ridgeStrength: try container.decodeIfPresent(Double.self, forKey: .ridgeStrength)
                ?? defaults.ridgeStrength,
            ridgeWidth: try container.decodeIfPresent(Double.self, forKey: .ridgeWidth)
                ?? defaults.ridgeWidth,
            ridgeBreakup: try container.decodeIfPresent(Double.self, forKey: .ridgeBreakup)
                ?? defaults.ridgeBreakup,
            ridgeSeed: try container.decodeIfPresent(Double.self, forKey: .ridgeSeed)
                ?? defaults.ridgeSeed,
            ridgeFlowBinding: try container.decodeIfPresent(
                Double.self,
                forKey: .ridgeFlowBinding
            ) ?? defaults.ridgeFlowBinding,
            breathingAmount: try container.decodeIfPresent(
                Double.self,
                forKey: .breathingAmount
            ) ?? defaults.breathingAmount,
            breathingSpeed: try container.decodeIfPresent(Double.self, forKey: .breathingSpeed)
                ?? defaults.breathingSpeed,
            flowStrength: try container.decodeIfPresent(Double.self, forKey: .flowStrength)
                ?? defaults.flowStrength,
            flowShapeStrength: try container.decodeIfPresent(
                Double.self,
                forKey: .flowShapeStrength
            ) ?? defaults.flowShapeStrength,
            flowSpeed: try container.decodeIfPresent(Double.self, forKey: .flowSpeed)
                ?? defaults.flowSpeed,
            flowDirection: try container.decodeIfPresent(Double.self, forKey: .flowDirection)
                ?? defaults.flowDirection,
            flowEffect: try container.decodeIfPresent(Double.self, forKey: .flowEffect)
                ?? defaults.flowEffect,
            flowBrightnessStrength: try container.decodeIfPresent(
                Double.self,
                forKey: .flowBrightnessStrength
            ) ?? defaults.flowBrightnessStrength,
            rotationSpeed: try container.decodeIfPresent(Double.self, forKey: .rotationSpeed)
                ?? defaults.rotationSpeed,
            rotationDirection: try container.decodeIfPresent(
                Double.self,
                forKey: .rotationDirection
            ) ?? defaults.rotationDirection,
            disturbanceStrength: try container.decodeIfPresent(
                Double.self,
                forKey: .disturbanceStrength
            ) ?? defaults.disturbanceStrength,
            aggregationStrength: try container.decodeIfPresent(
                Double.self,
                forKey: .aggregationStrength
            ) ?? defaults.aggregationStrength,
            damping: try container.decodeIfPresent(Double.self, forKey: .damping)
                ?? defaults.damping,
            edgeDustAmount: try container.decodeIfPresent(Double.self, forKey: .edgeDustAmount)
                ?? defaults.edgeDustAmount,
            edgeFrayAmount: try container.decodeIfPresent(Double.self, forKey: .edgeFrayAmount)
                ?? defaults.edgeFrayAmount,
            scatterStrength: try container.decodeIfPresent(Double.self, forKey: .scatterStrength)
                ?? defaults.scatterStrength,
            scatterClusterStrength: try container.decodeIfPresent(
                Double.self,
                forKey: .scatterClusterStrength
            ) ?? defaults.scatterClusterStrength,
            scatterClusterScale: try container.decodeIfPresent(
                Double.self,
                forKey: .scatterClusterScale
            ) ?? defaults.scatterClusterScale,
            scatterSeed: try container.decodeIfPresent(Double.self, forKey: .scatterSeed)
                ?? defaults.scatterSeed,
            pointSizeScale: try container.decodeIfPresent(Double.self, forKey: .pointSizeScale)
                ?? defaults.pointSizeScale,
            brightness: try container.decodeIfPresent(Double.self, forKey: .brightness)
                ?? defaults.brightness,
            alphaScale: try container.decodeIfPresent(Double.self, forKey: .alphaScale)
                ?? defaults.alphaScale
        )
    }

    static func loadSaved() -> ParticleTuning {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ParticleTuning.self, from: data) else {
            return systemDefault
        }
        return decoded.clamped()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(clamped()) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func clamped() -> ParticleTuning {
        var value = self
        for parameter in ParticleTuningParameter.allCases {
            value[keyPath: parameter.keyPath] = Self.clamp(value[keyPath: parameter.keyPath])
        }
        value.flowEffect = ParticleFlowEffect.nearest(
            to: value.flowEffect
        ).tuningValue
        return value
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    enum Engine {
        static let particleCount = 12_000
        static let modelSeed: UInt64 = 0xA7F7E11E
        static let preferredFramesPerSecond = 60
        static let visualChannelsVersion: UInt32 = 1
        static let modelRebuildDelay = 0.12
        static let controlEffectMultiplier: Float = 2
        static let maximumSimulationStep: Float = 1.0 / 30.0
        static let visualTransitionDuration = 0.68
        static let thinkingTransitionDuration = 0.72
        static let speakingTransitionDuration = 0.48
        static let loadingTransitionDuration = 0.64
        static let errorTransitionDuration = 0.30
        static let exitTransitionDuration = 0.95
        static let shapeMorphDuration = 0.85
        static let minimumTransitionDuration = 0.001
        static let debugAutoCycleInterval = 0.45
        static let debugStressSwitchCount = 100
        static let debugMorphSwitchInterval = 0.006
        static let debugResumeInterval = 1_800.0
        static let debugContinuityTolerance: Float = 0.000_001
        static let debugMaximumPauseProgressStep: Float = 0.06
        static let idleProfile = ParticleVisualProfile(
            focus: 0,
            pulse: 0,
            circulation: 0,
            disruption: 0,
            dissolution: 0
        )
        static let listeningProfile = ParticleVisualProfile(
            focus: 0.92,
            pulse: 0,
            circulation: 0.02,
            disruption: 0,
            dissolution: 0
        )
        static let thinkingProfile = ParticleVisualProfile(
            focus: 0.82,
            pulse: 0.04,
            circulation: 0.42,
            disruption: 0.03,
            dissolution: 0
        )
        static let speakingProfile = ParticleVisualProfile(
            focus: 0.02,
            pulse: 0.90,
            circulation: 0.38,
            disruption: 0.01,
            dissolution: 0
        )
        static let sleepingProfile = ParticleVisualProfile(
            focus: 0.60,
            pulse: 0,
            circulation: 0,
            disruption: 0,
            dissolution: 0.55
        )
        static let errorProfile = ParticleVisualProfile(
            focus: 0.04,
            pulse: 0.05,
            circulation: 0.06,
            disruption: 0.36,
            dissolution: 0.08
        )
        static let loadingProfile = ParticleVisualProfile(
            focus: 0.24,
            pulse: 0.08,
            circulation: 1,
            disruption: 0,
            dissolution: 0
        )
        static let exitProfile = ParticleVisualProfile(
            focus: 0.18,
            pulse: 0,
            circulation: 0,
            disruption: 0.06,
            dissolution: 1
        )
        static let speechStartPulseBase: Float = 0.42
        static let speechStartPulseIntensityScale: Float = 0.34
        static let speechSustainPulseBase: Float = 0.20
        static let speechSustainPulseIntensityScale: Float = 0.48
        static let speechCirculationBase: Float = 0.24
        static let speechCirculationIntensityScale: Float = 0.22
        static let defaultSpeechIntensity: Float = 0.68
        static let speechStartDuration = 0.12
        static let speechSustainDuration = 0.52
        static let speechPauseDuration = 0.18
        static let speechEndDuration = 0.18
        static let transientStatePresentationDuration = 0.90
        static let errorImpulseStrength: Float = 1
        static let errorImpulseHoldDuration = 0.50
        static let errorRecoveryDuration = 0.75
        static let stateFocusRadiusReduction: Float = 0.085
        static let statePulseRadiusScale: Float = 0.075
        static let statePulseFrequency: Float = 0.78
        static let stateDisruptionRadiusScale: Float = 0.11
        static let stateDissolutionRadiusReduction: Float = 0.14
        static let circulationFlowIncrease: Float = 0.80
        static let disruptionAccelerationIncrease: Float = 5
        static let dissolutionFlowReduction: Float = 0.80
        static let minimumStateFlowScale: Float = 0.18
        static let maximumStateFlowScale: Float = 1.95
        static let goldenAngle: Float = 2.399_963_1
        static let customShapeCubeScale: Float = 0.577_350_26
        static let minimumGlobalScale: Float = 0.64
        static let maximumGlobalScale: Float = 1.36
        static let maximumSphereFormDisplacement: Float = 0.22
        static let minimumSphereFormRadiusScale: Float = 0.56
        static let fullRotation: Float = 2 * .pi
        static let sphereFormBaseLobeCount: Float = 2
        static let sphereFormLowLobeCount: Float = 3
        static let sphereFormMediumLobeCount: Float = 5
        static let sphereFormUpperMediumLobeCount: Float = 6
        static let sphereFormHighLobeCount: Float = 7
        static let sphereFormBaseLobeWeight: Float = 0.20
        static let sphereFormLowLobeWeight: Float = 0.34
        static let sphereFormLowLobeFeatureReduction: Float = 0.22
        static let sphereFormMediumLobeMinimumWeight: Float = 0.16
        static let sphereFormMediumLobeWeightRange: Float = 0.20
        static let sphereFormUpperMediumLobeMinimumWeight: Float = 0.04
        static let sphereFormUpperMediumLobeWeightRange: Float = 0.16
        static let sphereFormHighLobeMinimumWeight: Float = 0.08
        static let sphereFormHighLobeWeightRange: Float = 0.19
        static let sphereFormMediumSmoothnessReduction: Float = 0.58
        static let sphereFormUpperMediumSmoothnessReduction: Float = 0.72
        static let sphereFormHighSmoothnessReduction: Float = 0.82
        static let sphereFormAngularFalloff: Float = 1.35
        static let sphereFormXYWeight: Float = 0.42
        static let sphereFormYZWeight: Float = 0.42
        static let sphereFormZXWeight: Float = 0.42
        static let sphereFormYZPhaseOffset: Float = 1.5 * .pi
        static let sphereFormZXPhaseOffset: Float = .pi / 6
        static let sphereFormBasePhaseRatio: Float = 0.43
        static let sphereFormMediumPhaseRatio: Float = -0.63
        static let sphereFormUpperMediumPhaseRatio: Float = 0.79
        static let sphereFormHighPhaseRatio: Float = 1.21
        static let sphereFormBaseOffsetRatio: Float = 0.51
        static let sphereFormMediumOffsetRatio: Float = 1.31
        static let sphereFormUpperMediumOffsetRatio: Float = -0.37
        static let sphereFormHighOffsetRatio: Float = -0.73
        static let sphereFormBroadAxisA = SIMD3<Float>(0.85, 0.27, -0.45)
        static let sphereFormBroadAxisB = SIMD3<Float>(-0.32, 0.91, 0.26)
        static let sphereFormBroadFrequencyA: Float = 2.25
        static let sphereFormBroadFrequencyB: Float = 2.75
        static let sphereFormBroadPhaseRatioB: Float = -0.61
        static let sphereFormBroadWeightA: Float = 0.20
        static let sphereFormBroadWeightB: Float = 0.15
        static let sphereFormFieldNormalization: Float = 1.25
        static let sphereFormFieldGain: Float = 1.60
        static let sphereFormDensityAngularWeight: Float = 0.40
        static let sphereFormDensityWarpStrength: Float = 0.16
        static let sphereFormMaximumDensityWarp: Float = 0.30
        static let sphereFormDensityGradientLimit: Float = 1
        static let sphereFormDensityFieldFollow: Float = 0.75
        static let scatterMinimumClusterFrequency: Float = 1.4
        static let scatterMaximumClusterFrequency: Float = 3.4
        static let scatterStrongProbability: Float = 0.46
        static let scatterClusterProbabilityMinimum: Float = 0.12
        static let scatterClusterProbabilityRange: Float = 0.66
        static let scatterStrongRadialDistance: Float = 0.105
        static let scatterSoftRadialDistance: Float = 0.034
        static let scatterRadialExponent: Float = 1.45
        static let scatterTangentialDistance: Float = 0.048
        static let scatterPrimaryWeight: Float = 0.64
        static let scatterSecondaryWeight: Float = 0.36
        static let scatterPrimaryAxis = SIMD3<Float>(0.74, -0.31, 0.59)
        static let scatterSecondaryAxis = SIMD3<Float>(-0.22, 0.91, 0.35)
        static let scatterSecondaryFrequencyRatio: Float = 0.63
        static let scatterRadialClusterMinimum: Float = 0.60
        static let scatterRadialClusterRange: Float = 0.80
        static let scatterTangentialClusterMinimum: Float = 0.80
        static let scatterTangentialClusterRange: Float = 0.40
        static let angularJitterScale: Float = 0.34
        static let surfaceThickness: Float = 0.075
        static let minimumShellConcentration: Float = 1
        static let maximumShellConcentration: Float = 4
        static let minimumSurfaceRatio: Float = 0.10
        static let maximumSurfaceRatio: Float = 0.90
        static let minimumSphereRadius: Float = 0.46
        static let maximumSphereRadius: Float = 0.64
        static let maximumBreathingScale: Float = 0.045
        static let minimumBreathingFrequency: Float = 0.16
        static let maximumBreathingFrequency: Float = 0.52
        static let secondaryBreathingAmplitude: Float = 0.28
        static let secondaryBreathingFrequencyRatio: Float = 0.57
        static let secondaryBreathingPhase: Float = 0.84
        static let maximumFlowAcceleration: Float = 0.22
        static let minimumFlowFrequency: Float = 0.10
        static let maximumFlowFrequency: Float = 0.42
        static let flowWaveFrequencyScale: Float = 2 * .pi
        static let maximumFlowMotionStrength: Float = 1.6
        static let maximumFlowShapeStrength: Float = 2
        static let flowShapeMaterialDisplacement: Float = 0.030
        static let flowShapeCloudDisplacement: Float = 0.040
        static let flowShapeReliefDisplacement: Float = 0.055
        static let flowShapeTimeScale: Float = 0.55
        static let flowShapePrimarySpatialFrequency: Float = 2.6
        static let flowShapeSecondarySpatialFrequency: Float = 3.8
        static let flowShapePrimaryDepthFrequency: Float = 4.8
        static let flowShapeSecondaryDepthFrequency: Float = 4.4
        static let flowShapePrimaryTimeRatio: Float = 0.82
        static let flowShapeSecondaryTimeRatio: Float = 0.68
        static let flowShapePocketTimeRatio: Float = 0.52
        static let directionalFlowWeight: Float = 0.82
        static let circulationFlowWeight: Float = 0.34
        static let minimumFlowPulse: Float = 0.38
        static let flowPulseRange: Float = 0.62
        static let maximumAutomaticRotationSpeed: Float = 1.2
        static let flowAxisTilt: Float = 0.24
        static let flowAxisPrecession: Float = 0.17
        static let flowAxisSecondaryRateRatio: Float = 0.83
        static let secondaryFlowAxis = SIMD3<Float>(0.74, -0.18, 0.65)
        static let secondaryFlowStrength: Float = 0.34
        static let secondaryFlowFrequencyRatio: Float = 0.71
        static let flowPrimarySpatialFrequency: Float = 8.4
        static let flowSecondarySpatialFrequency: Float = 6.2
        static let flowSecondaryVisualTimeRatio: Float = 0.74
        static let flowEffectAxisInfluence: Float = 0.48
        static let flowPrimaryAxisPhaseRatio: Float = 1.37
        static let flowSecondaryAxisPhaseRatio: Float = 0.83
        static let flowDepthAxisInfluence: Float = 0.56
        static let flowSecondaryPatternPhaseRatio: Float = 0.67
        static let flowPointSizeIncrease: Float = 0.52
        static let flowBrightnessIncrease: Float = 0.82
        static let flowAlphaIncrease: Float = 0.20
        static let minimumFlowWeight: Float = 0.42
        static let anchorFlowWeight: Float = 0.58
        static let maximumDisturbanceAcceleration: Float = 0.052
        static let disturbanceFrequency: Float = 0.23
        static let disturbanceYFrequencyRatio: Float = 0.73
        static let disturbanceYPhaseRatio: Float = 1.37
        static let disturbanceZFrequencyRatio: Float = 0.61
        static let disturbanceZPhaseRatio: Float = 0.79
        static let disturbanceRadialRetention: Float = 0.62
        static let minimumDisturbanceWeight: Float = 0.38
        static let surfaceDisturbanceWeight: Float = 0.62
        static let minimumAggregation: Float = 1.6
        static let maximumAggregation: Float = 7.2
        static let minimumDamping: Float = 0.9
        static let maximumDamping: Float = 4.6
        static let boundaryMargin: Float = 0.075
        static let boundaryVelocityRetention: Float = 0.18
        static let maximumParticleSpeed: Float = 0.22
        static let centerCorrection: Float = 1
        static let projectionScale: Float = 1
        static let manualRotationArcballRadiusScale: CGFloat = 0.82
        static let quaternionNormalizationEpsilon: Float = 0.000_01
        static let orientationGuideLabelOpacity = 0.52
        static let minimumPointSize: Float = 2.2
        static let maximumPointSize: Float = 6.4
        static let minimumParticleSizeVariation: Float = 0.62
        static let maximumParticleSizeVariation: Float = 1.55
        static let particleSizeVariationExponent: Float = 1.75
        static let minimumBrightness: Float = 0.58
        static let maximumBrightness: Float = 1.52
        static let depthPointSizeMinimum: Float = 0.72
        static let depthPointSizeMaximum: Float = 1.24
        static let volumePointSizeScale: Float = 0.74
        static let surfacePointSizeScale: Float = 1.08
        static let focusPointSizeReduction: Float = 0.24
        static let pulsePointSizeIncrease: Float = 0.22
        static let channelBrightnessRange: Float = 0.26
        static let disruptionBrightnessReduction: Float = 0.34
        static let minimumDissolutionAlpha: Float = 0.04
        static let minimumAlphaScale: Float = 0.10
        static let maximumAlphaScale: Float = 1.90
        static let pointCoreStart: Float = 0.06
        static let pointCoreEnd: Float = 0.27
        static let pointHaloStart: Float = 0.15
        static let pointHaloEnd: Float = 0.50
        static let volumeAlpha: Float = 0.28
        static let surfaceAlpha: Float = 0.72
        static let coreAlphaWeight: Float = 0.82
        static let haloAlphaWeight: Float = 0.24
        static let keyLightDirection = SIMD3<Float>(-0.42, 0.48, 0.77)
        static let frontDepthScale: Float = 0.92
        static let minimumVisibleBrightnessScale: Float = 1
        static let frontBrightnessScale: Float = 1.34
        static let frontVisibilityFadeStart: Float = 0.46
        static let frontVisibilityFadeEnd: Float = 0.58
        static let surfaceColorBaseMix: Float = 0.16
        static let surfaceColorLightMix: Float = 0.34
        static let highlightColorMix: Float = 0.18
        static let polarReferenceThreshold: Float = 0.92
        static let normalizationEpsilon: Float = 0.000_01
        static let interactionTimeout = 0.35
        static let positionResponse: Float = 0.16
        static let velocityResponse: Float = 0.12
        static let interactionRiseResponse: Float = 0.18
        static let interactionFallResponse: Float = 0.06
        static let orientationOverlayRefreshInterval = 1.0 / 30.0
        static let metricsInterval = 1.0
        static let focusFlowReduction: Float = 0.58
        static let pulseFlowIncrease: Float = 0.26
        static let instabilityFlowReduction: Float = 0.42
        static let focusFlowShapeReduction: Float = 0.30
        static let pulseFlowShapeIncrease: Float = 0.12
        static let circulationFlowShapeIncrease: Float = 0.85
        static let disruptionFlowShapeReduction: Float = 0.25
        static let dissolutionFlowShapeReduction: Float = 0.75
        static let minimumStateFlowShapeScale: Float = 0.18

        static func value(_ control: Double, minimum: Float, maximum: Float) -> Float {
            minimum + Float(min(1, max(0, control))) * (maximum - minimum)
        }

        static func amplifiedStrength(_ control: Double) -> Float {
            Float(min(1, max(0, control))) * controlEffectMultiplier
        }

        static func amplifiedValue(
            _ control: Double,
            minimum: Float,
            maximum: Float
        ) -> Float {
            minimum + amplifiedStrength(control) * (maximum - minimum)
        }

        static func amplifiedAround(_ value: Float, center: Float) -> Float {
            center + (value - center) * controlEffectMultiplier
        }
    }
}

enum ParticleTuningParameter: String, CaseIterable, Identifiable {
    case sphereRadius
    case globalScale
    case shapeStrength
    case shapeFeatureScale
    case shapeSmoothness
    case shapeSeed
    case surfaceRatio
    case surfaceLightStrength
    case ridgeStrength
    case ridgeWidth
    case ridgeBreakup
    case ridgeSeed
    case ridgeFlowBinding
    case breathingAmount
    case breathingSpeed
    case flowStrength
    case flowShapeStrength
    case flowSpeed
    case flowDirection
    case flowEffect
    case flowBrightnessStrength
    case rotationSpeed
    case rotationDirection
    case disturbanceStrength
    case aggregationStrength
    case damping
    case edgeDustAmount
    case edgeFrayAmount
    case scatterStrength
    case scatterClusterStrength
    case scatterClusterScale
    case scatterSeed
    case pointSizeScale
    case brightness
    case alphaScale

    var id: String { rawValue }

    var localizedKey: String {
        "particleDebug.parameter.\(rawValue)"
    }

    var keyPath: WritableKeyPath<ParticleTuning, Double> {
        switch self {
        case .sphereRadius:
            return \.sphereRadius
        case .globalScale:
            return \.globalScale
        case .shapeStrength:
            return \.shapeStrength
        case .shapeFeatureScale:
            return \.shapeFeatureScale
        case .shapeSmoothness:
            return \.shapeSmoothness
        case .shapeSeed:
            return \.shapeSeed
        case .surfaceRatio:
            return \.surfaceRatio
        case .surfaceLightStrength:
            return \.surfaceLightStrength
        case .ridgeStrength:
            return \.ridgeStrength
        case .ridgeWidth:
            return \.ridgeWidth
        case .ridgeBreakup:
            return \.ridgeBreakup
        case .ridgeSeed:
            return \.ridgeSeed
        case .ridgeFlowBinding:
            return \.ridgeFlowBinding
        case .breathingAmount:
            return \.breathingAmount
        case .breathingSpeed:
            return \.breathingSpeed
        case .flowStrength:
            return \.flowStrength
        case .flowShapeStrength:
            return \.flowShapeStrength
        case .flowSpeed:
            return \.flowSpeed
        case .flowDirection:
            return \.flowDirection
        case .flowEffect:
            return \.flowEffect
        case .flowBrightnessStrength:
            return \.flowBrightnessStrength
        case .rotationSpeed:
            return \.rotationSpeed
        case .rotationDirection:
            return \.rotationDirection
        case .disturbanceStrength:
            return \.disturbanceStrength
        case .aggregationStrength:
            return \.aggregationStrength
        case .damping:
            return \.damping
        case .edgeDustAmount:
            return \.edgeDustAmount
        case .edgeFrayAmount:
            return \.edgeFrayAmount
        case .scatterStrength:
            return \.scatterStrength
        case .scatterClusterStrength:
            return \.scatterClusterStrength
        case .scatterClusterScale:
            return \.scatterClusterScale
        case .scatterSeed:
            return \.scatterSeed
        case .pointSizeScale:
            return \.pointSizeScale
        case .brightness:
            return \.brightness
        case .alphaScale:
            return \.alphaScale
        }
    }
}

enum ParticleFlowEffect: CaseIterable, Identifiable, Hashable {
    case cloudSurge
    case vortex
    case tidal
    case crossCurrent
    case pulse
    case laminar

    var id: String { localizedKey }

    var localizedKey: String {
        switch self {
        case .cloudSurge:
            return "particleDebug.flowEffect.cloudSurge"
        case .vortex:
            return "particleDebug.flowEffect.vortex"
        case .tidal:
            return "particleDebug.flowEffect.tidal"
        case .crossCurrent:
            return "particleDebug.flowEffect.crossCurrent"
        case .pulse:
            return "particleDebug.flowEffect.pulse"
        case .laminar:
            return "particleDebug.flowEffect.laminar"
        }
    }

    var tuningValue: Double {
        guard let index = Self.allCases.firstIndex(of: self) else { return 0 }
        return Double(index) / Double(Self.allCases.count - 1)
    }

    var phaseOffset: Float {
        switch self {
        case .cloudSurge:
            return 0.08
        case .vortex:
            return 0.24
        case .tidal:
            return 0.40
        case .crossCurrent:
            return 0.56
        case .pulse:
            return 0.72
        case .laminar:
            return 0.88
        }
    }

    var geometryWeights: SIMD4<Float> {
        switch self {
        case .cloudSurge:
            return SIMD4(0.95, 1.15, 1.00, 0.28)
        case .vortex:
            return SIMD4(1.25, 0.55, 0.48, 0.12)
        case .tidal:
            return SIMD4(0.50, 0.72, 1.35, 0.08)
        case .crossCurrent:
            return SIMD4(1.05, 1.00, 0.72, 0.24)
        case .pulse:
            return SIMD4(0.62, 0.78, 1.50, 0.15)
        case .laminar:
            return SIMD4(0.82, 0.28, 0.25, 0.04)
        }
    }

    var motionStyle: SIMD4<Float> {
        switch self {
        case .cloudSurge:
            return SIMD4(0.90, 0.86, 0.82, 0.35)
        case .vortex:
            return SIMD4(1.22, 1.30, 1.10, 1.00)
        case .tidal:
            return SIMD4(0.55, 0.62, 0.58, 0.12)
        case .crossCurrent:
            return SIMD4(1.34, 1.18, 0.92, 0.68)
        case .pulse:
            return SIMD4(0.96, 0.76, 1.28, 0.32)
        case .laminar:
            return SIMD4(0.74, 0.48, 0.68, 0.05)
        }
    }

    var highlightStyle: SIMD4<Float> {
        switch self {
        case .cloudSurge:
            return SIMD4(0.28, 0.78, 0.38, 1.05)
        case .vortex:
            return SIMD4(0.46, 0.84, 0.68, 1.15)
        case .tidal:
            return SIMD4(0.20, 0.66, 0.78, 0.88)
        case .crossCurrent:
            return SIMD4(0.38, 0.76, 0.50, 1.08)
        case .pulse:
            return SIMD4(0.52, 0.88, 0.62, 1.28)
        case .laminar:
            return SIMD4(0.30, 0.60, 0.86, 0.78)
        }
    }

    static func nearest(to value: Double) -> ParticleFlowEffect {
        allCases.min {
            abs($0.tuningValue - value) < abs($1.tuningValue - value)
        } ?? .cloudSurge
    }
}

enum ParticleFlowDirection: CaseIterable, Identifiable {
    case up
    case down
    case left
    case right

    var id: String { localizedKey }

    var localizedKey: String {
        switch self {
        case .up:
            return "particleDebug.direction.up"
        case .down:
            return "particleDebug.direction.down"
        case .left:
            return "particleDebug.direction.left"
        case .right:
            return "particleDebug.direction.right"
        }
    }

    var tuningValue: Double {
        switch self {
        case .up:
            return 0
        case .down:
            return 1.0 / 3.0
        case .left:
            return 2.0 / 3.0
        case .right:
            return 1
        }
    }

    var axis: SIMD3<Float> {
        switch self {
        case .up:
            return SIMD3(0, 1, 0)
        case .down:
            return SIMD3(0, -1, 0)
        case .left:
            return SIMD3(-1, 0, 0)
        case .right:
            return SIMD3(1, 0, 0)
        }
    }

    static func nearest(to value: Double) -> ParticleFlowDirection {
        allCases.min {
            abs($0.tuningValue - value) < abs($1.tuningValue - value)
        } ?? .right
    }
}

enum ParticleSpinDirection: CaseIterable, Identifiable {
    case left
    case right

    var id: String { localizedKey }

    var localizedKey: String {
        switch self {
        case .left:
            return "particleDebug.direction.left"
        case .right:
            return "particleDebug.direction.right"
        }
    }

    var tuningValue: Double {
        switch self {
        case .left:
            return 0
        case .right:
            return 1
        }
    }

    var sign: Float {
        switch self {
        case .left:
            return -1
        case .right:
            return 1
        }
    }

    static func nearest(to value: Double) -> ParticleSpinDirection {
        value < 0.5 ? .left : .right
    }
}

struct ParticleColorProfile: Codable, Equatable {
    var baseRed: Double
    var baseGreen: Double
    var baseBlue: Double
    var ridgeRed: Double
    var ridgeGreen: Double
    var ridgeBlue: Double
    var dimRed: Double
    var dimGreen: Double
    var dimBlue: Double
    var highlightRed: Double
    var highlightGreen: Double
    var highlightBlue: Double
    var alphaScale: Double

    static let systemDefault = ParticleColorProfile(
        baseRed: 0.82,
        baseGreen: 0.84,
        baseBlue: 0.88,
        ridgeRed: 0.95,
        ridgeGreen: 0.96,
        ridgeBlue: 0.98,
        dimRed: 0.40,
        dimGreen: 0.42,
        dimBlue: 0.46,
        highlightRed: 0.98,
        highlightGreen: 0.985,
        highlightBlue: 1.0,
        alphaScale: 1.0
    )

    static let storageKey = "ParticleCoreColorProfile.debug.v1"

    static func loadSaved() -> ParticleColorProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ParticleColorProfile.self, from: data) else {
            return nil
        }
        return decoded.clamped()
    }

    static func hasSavedProfile() -> Bool {
        UserDefaults.standard.data(forKey: storageKey) != nil
    }

    func save() {
        guard let data = try? JSONEncoder().encode(clamped()) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static func make(fromDRData data: Data) -> ParticleColorProfile {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lattice = object["lattice_config"] as? [String: Any],
              let palette = lattice["color_palette"] as? [String],
              let color = dominantResidentColor(from: palette) else {
            return systemDefault
        }

        let base = subtleColor(from: color, target: 0.82, chroma: 0.34)
        let ridge = subtleColor(from: color, target: 0.92, chroma: 0.28)
        let dim = subtleColor(from: color, target: 0.39, chroma: 0.30)
        let highlight = subtleColor(from: color, target: 0.965, chroma: 0.14)

        return ParticleColorProfile(
            baseRed: Double(base.x),
            baseGreen: Double(base.y),
            baseBlue: Double(base.z),
            ridgeRed: Double(ridge.x),
            ridgeGreen: Double(ridge.y),
            ridgeBlue: Double(ridge.z),
            dimRed: Double(dim.x),
            dimGreen: Double(dim.y),
            dimBlue: Double(dim.z),
            highlightRed: Double(highlight.x),
            highlightGreen: Double(highlight.y),
            highlightBlue: Double(highlight.z),
            alphaScale: 1.0
        ).clamped()
    }

    var baseVector: SIMD4<Float> {
        SIMD4(Float(baseRed), Float(baseGreen), Float(baseBlue), 1)
    }

    var ridgeVector: SIMD4<Float> {
        SIMD4(Float(ridgeRed), Float(ridgeGreen), Float(ridgeBlue), 1)
    }

    var dimVector: SIMD4<Float> {
        SIMD4(Float(dimRed), Float(dimGreen), Float(dimBlue), 1)
    }

    var highlightVector: SIMD4<Float> {
        SIMD4(Float(highlightRed), Float(highlightGreen), Float(highlightBlue), 1)
    }

    func clamped() -> ParticleColorProfile {
        var value = self
        for parameter in ParticleColorParameter.allCases {
            value[keyPath: parameter.keyPath] = Self.clamp(value[keyPath: parameter.keyPath])
        }
        return value
    }

    nonisolated private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    nonisolated private static func dominantResidentColor(from palette: [String]) -> SIMD3<Float>? {
        let colors = palette.compactMap(parseHexColor)
        guard !colors.isEmpty else { return nil }

        var weighted = SIMD3<Float>(repeating: 0)
        var totalWeight: Float = 0
        let weights: [Float] = [1.0, 0.24, 0.12, 0.10]
        for (index, color) in colors.prefix(4).enumerated() {
            let weight = weights[index]
            weighted += color * weight
            totalWeight += weight
        }
        return weighted / max(totalWeight, 0.001)
    }

    nonisolated private static func parseHexColor(_ value: String) -> SIMD3<Float>? {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let hex = Int(raw, radix: 16) else { return nil }
        return SIMD3(
            Float((hex >> 16) & 0xFF) / 255,
            Float((hex >> 8) & 0xFF) / 255,
            Float(hex & 0xFF) / 255
        )
    }

    nonisolated private static func subtleColor(from color: SIMD3<Float>, target: Float, chroma: Float) -> SIMD3<Float> {
        let sourceLuma = max(0.001, dot(color, SIMD3<Float>(0.2126, 0.7152, 0.0722)))
        let normalized = color * (target / sourceLuma)
        let neutral = SIMD3<Float>(repeating: target)
        return clampVector(neutral + (normalized - neutral) * chroma, lower: 0.24, upper: 1.0)
    }

    nonisolated private static func clampVector(_ value: SIMD3<Float>, lower: Float, upper: Float) -> SIMD3<Float> {
        SIMD3(
            max(lower, min(upper, value.x)),
            max(lower, min(upper, value.y)),
            max(lower, min(upper, value.z))
        )
    }
}

enum ParticleColorParameter: String, CaseIterable, Identifiable {
    case baseRed
    case baseGreen
    case baseBlue
    case ridgeRed
    case ridgeGreen
    case ridgeBlue
    case dimRed
    case dimGreen
    case dimBlue
    case highlightRed
    case highlightGreen
    case highlightBlue
    case alphaScale

    var id: String { rawValue }

    var localizedKey: String {
        "particleDebug.color.\(rawValue)"
    }

    var keyPath: WritableKeyPath<ParticleColorProfile, Double> {
        switch self {
        case .baseRed:
            return \.baseRed
        case .baseGreen:
            return \.baseGreen
        case .baseBlue:
            return \.baseBlue
        case .ridgeRed:
            return \.ridgeRed
        case .ridgeGreen:
            return \.ridgeGreen
        case .ridgeBlue:
            return \.ridgeBlue
        case .dimRed:
            return \.dimRed
        case .dimGreen:
            return \.dimGreen
        case .dimBlue:
            return \.dimBlue
        case .highlightRed:
            return \.highlightRed
        case .highlightGreen:
            return \.highlightGreen
        case .highlightBlue:
            return \.highlightBlue
        case .alphaScale:
            return \.alphaScale
        }
    }
}
