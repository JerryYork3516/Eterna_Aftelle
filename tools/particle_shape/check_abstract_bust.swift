import Foundation
import simd

@main
struct AbstractBustCheck {
    static func main() {
        let count = ParticleTuning.Engine.particleCount
        let seed = ParticleTuning.Engine.modelSeed
        let tuning = AbstractBustTuning.systemDefault
        let first = AbstractBustAnchorGenerator.generate(
            count: count,
            seed: seed,
            tuning: tuning
        )
        let second = AbstractBustAnchorGenerator.generate(
            count: count,
            seed: seed,
            tuning: tuning
        )

        require(count == 12_000, "engine particle count changed")
        require(first.count == 12_000, "abstract bust anchor count")
        require(first == second, "deterministic generation")
        require(first.allSatisfy(isFinite), "finite anchors")

        let ranges = AbstractBustAnchorGenerator.regionRanges(count: count)
        for region in AbstractBustAnchorRegion.allCases {
            guard let range = ranges[region], !range.isEmpty else {
                fail("missing \(region) coverage")
            }
            require(
                hasHealthyAngularCoverage(Array(first[range])),
                "\(region) distribution coverage"
            )
        }

        let bounds = bounds(of: first)
        let centroid = first.reduce(SIMD3<Float>.zero, +) / Float(first.count)
        require(abs(centroid.x) < 0.04, "centroid x")
        require(centroid.y > -0.30 && centroid.y < 0.12, "centroid y")
        require(abs(centroid.z) < 0.03, "centroid z")
        require(bounds.minimum.x < -0.58 && bounds.maximum.x > 0.58, "shoulder width")
        require(bounds.minimum.y < -1.10 && bounds.maximum.y > 0.98, "vertical bounds")
        require(bounds.minimum.z < -0.25 && bounds.maximum.z > 0.25, "front/back thickness")
        require(bounds.maximum.x - bounds.minimum.x < 1.45, "maximum width")
        require(bounds.maximum.y - bounds.minimum.y < 2.25, "maximum height")

        var simulation = ParticleSimulation(time: 1_000)
        let particleCountBefore = simulation.particleCount
        let rebuildCountBefore = simulation.rebuildCount
        require(
            simulation.setDebugStaticShapeTarget(
                .abstractBust,
                reason: "abstractBustCheck",
                time: 1_001
            ),
            "select abstract bust"
        )
        let bustPayloads = simulation.vertexPayloads
        require(bustPayloads.count == 12_000, "bust payload count")
        require(bustPayloads.allSatisfy(isFinite), "finite bust payloads")
        require(simulation.targetShape == .abstractBust, "bust target state")
        require(
            !simulation.setShapeTarget(
                .abstractBust,
                reason: "abstractBustMustNotMorph",
                time: 1_002
            ),
            "abstract bust morph disabled"
        )
        require(
            simulation.setDebugStaticShapeTarget(
                .sphere,
                reason: "sphereRegression",
                time: 1_003
            ),
            "sphere regression selection"
        )
        let spherePayloads = simulation.vertexPayloads
        require(spherePayloads.allSatisfy(isFinite), "finite sphere payloads")
        require(
            simulation.setDebugStaticShapeTarget(
                .customShape,
                reason: "customShapeRegression",
                time: 1_004
            ),
            "custom shape regression selection"
        )
        let customPayloads = simulation.vertexPayloads
        require(customPayloads.allSatisfy(isFinite), "finite custom payloads")
        require(spherePayloads != customPayloads, "sphere/custom shape distinction")
        require(particleCountBefore == simulation.particleCount, "particle count preserved")
        require(rebuildCountBefore == simulation.rebuildCount, "shape switch does not rebuild")

        print(
            "abstract_bust_check PASS "
                + "count=\(first.count) "
                + "centroid=(\(format(centroid.x)),\(format(centroid.y)),\(format(centroid.z))) "
                + "boundsX=(\(format(bounds.minimum.x)),\(format(bounds.maximum.x))) "
                + "boundsY=(\(format(bounds.minimum.y)),\(format(bounds.maximum.y))) "
                + "boundsZ=(\(format(bounds.minimum.z)),\(format(bounds.maximum.z))) "
                + "rebuildCount=\(rebuildCountBefore)->\(simulation.rebuildCount)"
        )
    }

    private static func hasHealthyAngularCoverage(
        _ anchors: [SIMD3<Float>]
    ) -> Bool {
        guard !anchors.isEmpty else { return false }
        let verticalBins = 8
        let angularBins = 12
        var occupancy = Array(
            repeating: 0,
            count: verticalBins * angularBins
        )
        for (index, anchor) in anchors.enumerated() {
            let vertical = min(
                verticalBins - 1,
                Int(Float(index) / Float(anchors.count) * Float(verticalBins))
            )
            let angle = atan2(anchor.z, anchor.x)
            let angularUnit = (angle + .pi) / (2 * .pi)
            let angular = min(
                angularBins - 1,
                max(0, Int(angularUnit * Float(angularBins)))
            )
            occupancy[vertical * angularBins + angular] += 1
        }
        let average = Float(anchors.count) / Float(occupancy.count)
        let healthy = occupancy.allSatisfy { value in
            value > 0 && Float(value) < average * 2.2
        }
        if !healthy {
            fputs(
                "coverage bins min=\(occupancy.min() ?? 0) "
                    + "max=\(occupancy.max() ?? 0) "
                    + "average=\(format(average))\n",
                stderr
            )
        }
        return healthy
    }

    private static func bounds(
        of anchors: [SIMD3<Float>]
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        anchors.reduce(
            (
                SIMD3<Float>(repeating: .greatestFiniteMagnitude),
                SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            )
        ) { partial, anchor in
            (
                simd_min(partial.0, anchor),
                simd_max(partial.1, anchor)
            )
        }
    }

    private static func isFinite(_ anchor: SIMD3<Float>) -> Bool {
        anchor.x.isFinite && anchor.y.isFinite && anchor.z.isFinite
    }

    private static func isFinite(_ payload: SIMD4<Float>) -> Bool {
        payload.x.isFinite
            && payload.y.isFinite
            && payload.z.isFinite
            && payload.w.isFinite
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ name: String
    ) {
        guard condition() else { fail(name) }
    }

    private static func fail(_ name: String) -> Never {
        fputs("abstract_bust_check FAIL \(name)\n", stderr)
        exit(1)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.4f", value)
    }
}
