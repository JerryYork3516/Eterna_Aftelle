import Foundation
import simd

struct ParticleTuning: Codable, Equatable {
    var globalScale: Double
    var pointSizeScale: Double
    var brightness: Double
    var alphaScale: Double
    var ridgeBrightness: Double
    var ridgeWidth: Double
    var ridgeBreakup: Double
    var ridgeSeed: Double
    var ridgeFlowBinding: Double
    var breathingAmount: Double
    var breathingSpeed: Double
    var flowStrength: Double
    var flowSpeed: Double
    var flowDirection: Double
    var flowSeed: Double
    var flowBrightnessStrength: Double
    var rotationSpeed: Double
    var rotationDirection: Double
    var edgeDustAmount: Double
    var edgeFrayAmount: Double
    var surfaceLightStrength: Double
    var shapeStrength: Double
    var shapeFeatureScale: Double
    var shapeSeed: Double
    var scatterStrength: Double
    var scatterClusterStrength: Double
    var scatterClusterScale: Double
    var scatterSeed: Double

    init(
        globalScale: Double,
        pointSizeScale: Double,
        brightness: Double,
        alphaScale: Double,
        ridgeBrightness: Double,
        ridgeWidth: Double,
        ridgeBreakup: Double,
        ridgeSeed: Double,
        ridgeFlowBinding: Double,
        breathingAmount: Double,
        breathingSpeed: Double,
        flowStrength: Double,
        flowSpeed: Double,
        flowDirection: Double,
        flowSeed: Double,
        flowBrightnessStrength: Double,
        rotationSpeed: Double,
        rotationDirection: Double,
        edgeDustAmount: Double,
        edgeFrayAmount: Double,
        surfaceLightStrength: Double,
        shapeStrength: Double,
        shapeFeatureScale: Double,
        shapeSeed: Double,
        scatterStrength: Double,
        scatterClusterStrength: Double,
        scatterClusterScale: Double,
        scatterSeed: Double
    ) {
        self.globalScale = globalScale
        self.pointSizeScale = pointSizeScale
        self.brightness = brightness
        self.alphaScale = alphaScale
        self.ridgeBrightness = ridgeBrightness
        self.ridgeWidth = ridgeWidth
        self.ridgeBreakup = ridgeBreakup
        self.ridgeSeed = ridgeSeed
        self.ridgeFlowBinding = ridgeFlowBinding
        self.breathingAmount = breathingAmount
        self.breathingSpeed = breathingSpeed
        self.flowStrength = flowStrength
        self.flowSpeed = flowSpeed
        self.flowDirection = flowDirection
        self.flowSeed = flowSeed
        self.flowBrightnessStrength = flowBrightnessStrength
        self.rotationSpeed = rotationSpeed
        self.rotationDirection = rotationDirection
        self.edgeDustAmount = edgeDustAmount
        self.edgeFrayAmount = edgeFrayAmount
        self.surfaceLightStrength = surfaceLightStrength
        self.shapeStrength = shapeStrength
        self.shapeFeatureScale = shapeFeatureScale
        self.shapeSeed = shapeSeed
        self.scatterStrength = scatterStrength
        self.scatterClusterStrength = scatterClusterStrength
        self.scatterClusterScale = scatterClusterScale
        self.scatterSeed = scatterSeed
    }

    static let systemDefault = ParticleTuning(
        globalScale: 0.5,
        pointSizeScale: 0.5,
        brightness: 0.5,
        alphaScale: 0.5,
        ridgeBrightness: 0.5,
        ridgeWidth: 0.5,
        ridgeBreakup: 0.5,
        ridgeSeed: 0.5,
        ridgeFlowBinding: 0.35,
        breathingAmount: 0.5,
        breathingSpeed: 0.5,
        flowStrength: 0.5,
        flowSpeed: 0.5,
        flowDirection: 1.0,
        flowSeed: 0.5,
        flowBrightnessStrength: 0.5,
        rotationSpeed: 0.5,
        rotationDirection: 1.0,
        edgeDustAmount: 0.5,
        edgeFrayAmount: 0.5,
        surfaceLightStrength: 0.5,
        shapeStrength: 0.5,
        shapeFeatureScale: 0.5,
        shapeSeed: 0.5,
        scatterStrength: 0.5,
        scatterClusterStrength: 0.5,
        scatterClusterScale: 0.5,
        scatterSeed: 0.5
    )

    private enum CodingKeys: String, CodingKey {
        case globalScale
        case pointSizeScale
        case brightness
        case alphaScale
        case ridgeBrightness
        case ridgeWidth
        case ridgeBreakup
        case ridgeSeed
        case ridgeFlowBinding
        case breathingAmount
        case breathingSpeed
        case flowStrength
        case flowSpeed
        case flowDirection
        case flowSeed
        case flowBrightnessStrength
        case rotationSpeed
        case rotationDirection
        case edgeDustAmount
        case edgeFrayAmount
        case surfaceLightStrength
        case shapeStrength
        case shapeFeatureScale
        case shapeSeed
        case scatterStrength
        case scatterClusterStrength
        case scatterClusterScale
        case scatterSeed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.systemDefault
        self.init(
            globalScale: try container.decodeIfPresent(Double.self, forKey: .globalScale) ?? defaults.globalScale,
            pointSizeScale: try container.decodeIfPresent(Double.self, forKey: .pointSizeScale) ?? defaults.pointSizeScale,
            brightness: try container.decodeIfPresent(Double.self, forKey: .brightness) ?? defaults.brightness,
            alphaScale: try container.decodeIfPresent(Double.self, forKey: .alphaScale) ?? defaults.alphaScale,
            ridgeBrightness: try container.decodeIfPresent(Double.self, forKey: .ridgeBrightness) ?? defaults.ridgeBrightness,
            ridgeWidth: try container.decodeIfPresent(Double.self, forKey: .ridgeWidth) ?? defaults.ridgeWidth,
            ridgeBreakup: try container.decodeIfPresent(Double.self, forKey: .ridgeBreakup) ?? defaults.ridgeBreakup,
            ridgeSeed: try container.decodeIfPresent(Double.self, forKey: .ridgeSeed) ?? defaults.ridgeSeed,
            ridgeFlowBinding: try container.decodeIfPresent(Double.self, forKey: .ridgeFlowBinding) ?? defaults.ridgeFlowBinding,
            breathingAmount: try container.decodeIfPresent(Double.self, forKey: .breathingAmount) ?? defaults.breathingAmount,
            breathingSpeed: try container.decodeIfPresent(Double.self, forKey: .breathingSpeed) ?? defaults.breathingSpeed,
            flowStrength: try container.decodeIfPresent(Double.self, forKey: .flowStrength) ?? defaults.flowStrength,
            flowSpeed: try container.decodeIfPresent(Double.self, forKey: .flowSpeed) ?? defaults.flowSpeed,
            flowDirection: try container.decodeIfPresent(Double.self, forKey: .flowDirection) ?? defaults.flowDirection,
            flowSeed: try container.decodeIfPresent(Double.self, forKey: .flowSeed) ?? defaults.flowSeed,
            flowBrightnessStrength: try container.decodeIfPresent(Double.self, forKey: .flowBrightnessStrength) ?? defaults.flowBrightnessStrength,
            rotationSpeed: try container.decodeIfPresent(Double.self, forKey: .rotationSpeed) ?? defaults.rotationSpeed,
            rotationDirection: try container.decodeIfPresent(Double.self, forKey: .rotationDirection) ?? defaults.rotationDirection,
            edgeDustAmount: try container.decodeIfPresent(Double.self, forKey: .edgeDustAmount) ?? defaults.edgeDustAmount,
            edgeFrayAmount: try container.decodeIfPresent(Double.self, forKey: .edgeFrayAmount) ?? defaults.edgeFrayAmount,
            surfaceLightStrength: try container.decodeIfPresent(Double.self, forKey: .surfaceLightStrength) ?? defaults.surfaceLightStrength,
            shapeStrength: try container.decodeIfPresent(Double.self, forKey: .shapeStrength) ?? defaults.shapeStrength,
            shapeFeatureScale: try container.decodeIfPresent(Double.self, forKey: .shapeFeatureScale) ?? defaults.shapeFeatureScale,
            shapeSeed: try container.decodeIfPresent(Double.self, forKey: .shapeSeed) ?? defaults.shapeSeed,
            scatterStrength: try container.decodeIfPresent(Double.self, forKey: .scatterStrength) ?? defaults.scatterStrength,
            scatterClusterStrength: try container.decodeIfPresent(Double.self, forKey: .scatterClusterStrength) ?? defaults.scatterClusterStrength,
            scatterClusterScale: try container.decodeIfPresent(Double.self, forKey: .scatterClusterScale) ?? defaults.scatterClusterScale,
            scatterSeed: try container.decodeIfPresent(Double.self, forKey: .scatterSeed) ?? defaults.scatterSeed
        )
    }

    static let storageKey = "ParticleCoreTuning.debug.v1"

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
        static let maximumMotionStep: Float = 0.05
        static let speedPhaseRate: Float = 0.025
        static let motionBaseRate: Float = 0.42
        static let motionDriftAmplitude: Float = 0.08
        static let flowTimeScale: Float = 0.92
        static let stateResponse: Float = 0.036
        static let dissolutionRiseResponse: Float = 0.080
        static let dissolutionFallResponse: Float = 0.050
        static let interactionTimeout = 0.35
        static let positionResponse: Float = 0.16
        static let velocityResponse: Float = 0.12
        static let interactionRiseResponse: Float = 0.18
        static let interactionFallResponse: Float = 0.06
        static let metricsInterval = 1.0
        static let maximumFlowSpeed: Float = 2.75
        static let maximumBreathingAmount: Float = 2.2
        static let breathingSpeedScale: Float = 2
        static let breathingPrimaryAmplitude: Float = 0.010
        static let breathingPrimaryFrequency: Float = 0.23
        static let breathingSecondaryAmplitude: Float = 0.006
        static let breathingSecondaryFrequency: Float = 0.13
        static let breathingSecondaryPhase: Float = 0.9
        static let breathingEdgePrimaryAmplitude: Float = 0.012
        static let breathingEdgePrimaryFrequency: Float = 0.19
        static let breathingEdgePrimaryPhase: Float = 1.4
        static let breathingEdgeSecondaryAmplitude: Float = 0.005
        static let breathingEdgeSecondaryFrequency: Float = 0.37
        static let breathingEdgeSecondaryPhase: Float = 0.3
        static let breathingCoreVariationLimit: Float = 0.025
        static let breathingCoreVariationScale: Float = 0.16
        static let modelShapeStrengthScale: Float = 2
        static let modelScatterStrengthScale: Float = 2
        static let focusFlowReduction: Float = 0.40
        static let pulseFlowIncrease: Float = 0.16
        static let instabilityFlowReduction: Float = 0.04
    }
}

enum ParticleTuningParameter: String, CaseIterable, Identifiable {
    case globalScale
    case pointSizeScale
    case brightness
    case alphaScale
    case ridgeStrength
    case ridgeWidth
    case ridgeBreakup
    case ridgeSeed
    case ridgeFlowBinding
    case breathingAmount
    case breathingSpeed
    case flowSpeed
    case flowDirection
    case flowSeed
    case flowBrightnessStrength
    case flowStructureInfluence
    case rotationSpeed
    case rotationDirection
    case edgeDustAmount
    case edgeFrayAmount
    case surfaceLightStrength
    case shapeStrength
    case shapeFeatureScale
    case shapeSeed
    case scatterStrength
    case scatterClusterStrength
    case scatterClusterScale
    case scatterSeed

    var id: String { rawValue }

    var localizedKey: String {
        "particleDebug.parameter.\(rawValue)"
    }

    var keyPath: WritableKeyPath<ParticleTuning, Double> {
        switch self {
        case .globalScale:
            return \.globalScale
        case .pointSizeScale:
            return \.pointSizeScale
        case .brightness:
            return \.brightness
        case .alphaScale:
            return \.alphaScale
        case .ridgeStrength:
            return \.ridgeBrightness
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
        case .flowSpeed:
            return \.flowSpeed
        case .flowDirection:
            return \.flowDirection
        case .flowSeed:
            return \.flowSeed
        case .flowBrightnessStrength:
            return \.flowBrightnessStrength
        case .flowStructureInfluence:
            return \.flowStrength
        case .rotationSpeed:
            return \.rotationSpeed
        case .rotationDirection:
            return \.rotationDirection
        case .edgeDustAmount:
            return \.edgeDustAmount
        case .edgeFrayAmount:
            return \.edgeFrayAmount
        case .surfaceLightStrength:
            return \.surfaceLightStrength
        case .shapeStrength:
            return \.shapeStrength
        case .shapeFeatureScale:
            return \.shapeFeatureScale
        case .shapeSeed:
            return \.shapeSeed
        case .scatterStrength:
            return \.scatterStrength
        case .scatterClusterStrength:
            return \.scatterClusterStrength
        case .scatterClusterScale:
            return \.scatterClusterScale
        case .scatterSeed:
            return \.scatterSeed
        }
    }
}

enum ParticleRotationDirection: CaseIterable, Identifiable {
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
            return 0.0
        case .down:
            return 1.0 / 3.0
        case .left:
            return 2.0 / 3.0
        case .right:
            return 1.0
        }
    }

    static func nearest(to value: Double) -> ParticleRotationDirection {
        allCases.min { abs($0.tuningValue - value) < abs($1.tuningValue - value) } ?? .right
    }
}

enum ParticleSpinDirection: CaseIterable, Identifiable {
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
            return 1.0 / 3.0
        case .down:
            return 2.0 / 3.0
        case .left:
            return 0
        case .right:
            return 1
        }
    }

    var spinSign: Double {
        switch self {
        case .up, .left:
            return -1
        case .down, .right:
            return 1
        }
    }

    var rotatesVertically: Bool {
        self == .up || self == .down
    }

    static func nearest(to value: Double) -> ParticleSpinDirection {
        allCases.min { abs($0.tuningValue - value) < abs($1.tuningValue - value) } ?? .right
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
