import Foundation
import simd

struct ParticleTuning: Codable, Equatable {
    var sphereRadius: Double
    var surfaceRatio: Double
    var breathingAmount: Double
    var breathingSpeed: Double
    var flowStrength: Double
    var flowSpeed: Double
    var disturbanceStrength: Double
    var aggregationStrength: Double
    var damping: Double
    var pointSizeScale: Double
    var brightness: Double

    init(
        sphereRadius: Double,
        surfaceRatio: Double,
        breathingAmount: Double,
        breathingSpeed: Double,
        flowStrength: Double,
        flowSpeed: Double,
        disturbanceStrength: Double,
        aggregationStrength: Double,
        damping: Double,
        pointSizeScale: Double,
        brightness: Double
    ) {
        self.sphereRadius = sphereRadius
        self.surfaceRatio = surfaceRatio
        self.breathingAmount = breathingAmount
        self.breathingSpeed = breathingSpeed
        self.flowStrength = flowStrength
        self.flowSpeed = flowSpeed
        self.disturbanceStrength = disturbanceStrength
        self.aggregationStrength = aggregationStrength
        self.damping = damping
        self.pointSizeScale = pointSizeScale
        self.brightness = brightness
    }

    static let systemDefault = ParticleTuning(
        sphereRadius: 0.5,
        surfaceRatio: 0.62,
        breathingAmount: 0.34,
        breathingSpeed: 0.34,
        flowStrength: 0.38,
        flowSpeed: 0.32,
        disturbanceStrength: 0.24,
        aggregationStrength: 0.58,
        damping: 0.58,
        pointSizeScale: 0.42,
        brightness: 0.46
    )

    static let storageKey = "ParticleCoreTuning.debug.v2"

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
        static let visualTransitionDuration = 0.60
        static let minimumTransitionDuration = 0.001
        static let debugAutoCycleInterval = 0.45
        static let debugStressSwitchCount = 100
        static let debugContinuityTolerance: Float = 0.000_001
        static let debugMaximumPauseProgressStep: Float = 0.06
        static let goldenAngle: Float = 2.399_963_1
        static let angularJitterScale: Float = 0.34
        static let surfaceThickness: Float = 0.075
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
        static let maximumFlowAcceleration: Float = 0.095
        static let minimumFlowFrequency: Float = 0.10
        static let maximumFlowFrequency: Float = 0.42
        static let flowAxisTilt: Float = 0.24
        static let flowAxisPrecession: Float = 0.17
        static let flowAxisSecondaryRateRatio: Float = 0.83
        static let secondaryFlowAxis = SIMD3<Float>(0.74, -0.18, 0.65)
        static let secondaryFlowStrength: Float = 0.34
        static let secondaryFlowFrequencyRatio: Float = 0.71
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
        static let minimumBrightness: Float = 0.58
        static let maximumBrightness: Float = 1.52
        static let depthPointSizeMinimum: Float = 0.72
        static let depthPointSizeMaximum: Float = 1.24
        static let volumePointSizeScale: Float = 0.74
        static let surfacePointSizeScale: Float = 1.08
        static let focusPointSizeReduction: Float = 0.08
        static let pulsePointSizeIncrease: Float = 0.06
        static let channelBrightnessRange: Float = 0.10
        static let disruptionBrightnessReduction: Float = 0.08
        static let minimumDissolutionAlpha: Float = 0.08
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
        static let metricsInterval = 1.0
        static let focusFlowReduction: Float = 0.40
        static let pulseFlowIncrease: Float = 0.16
        static let instabilityFlowReduction: Float = 0.04

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
    case surfaceRatio
    case breathingAmount
    case breathingSpeed
    case flowStrength
    case flowSpeed
    case disturbanceStrength
    case aggregationStrength
    case damping
    case pointSizeScale
    case brightness

    var id: String { rawValue }

    var localizedKey: String {
        "particleDebug.parameter.\(rawValue)"
    }

    var keyPath: WritableKeyPath<ParticleTuning, Double> {
        switch self {
        case .sphereRadius:
            return \.sphereRadius
        case .surfaceRatio:
            return \.surfaceRatio
        case .breathingAmount:
            return \.breathingAmount
        case .breathingSpeed:
            return \.breathingSpeed
        case .flowStrength:
            return \.flowStrength
        case .flowSpeed:
            return \.flowSpeed
        case .disturbanceStrength:
            return \.disturbanceStrength
        case .aggregationStrength:
            return \.aggregationStrength
        case .damping:
            return \.damping
        case .pointSizeScale:
            return \.pointSizeScale
        case .brightness:
            return \.brightness
        }
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
