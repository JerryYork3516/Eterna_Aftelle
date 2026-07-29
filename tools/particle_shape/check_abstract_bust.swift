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
        require(
            ParticleShapeMorphTuning.defaultDuration >= 0.8
                && ParticleShapeMorphTuning.defaultDuration <= 1.2,
            "default morph duration range"
        )
        require(
            tuning.headWidth >= 0.255 && tuning.headWidth <= 0.27,
            "frozen head width"
        )
        require(
            tuning.headHeight >= 0.33 && tuning.headHeight <= 0.35,
            "frozen head height"
        )
        require(
            tuning.neckLength >= 0.19 && tuning.neckLength <= 0.216,
            "frozen neck length"
        )
        require(
            tuning.neckRootWidthScale >= 1.15
                && tuning.neckRootWidthScale <= 1.25,
            "frozen neck root width"
        )
        require(
            tuning.asymmetryStrength >= 0.007
                && tuning.asymmetryStrength <= 0.011,
            "frozen asymmetry"
        )
        require(
            tuning.torsoTaper >= 0.28 && tuning.torsoTaper <= 0.32,
            "frozen torso taper"
        )
        require(
            tuning.verticalSampleJitter > 0
                && tuning.angularJitter > 0
                && tuning.radialJitter > 0,
            "deterministic distribution jitter enabled"
        )
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
        let density = densityStats(
            first,
            bounds: bounds,
            bins: SIMD3<Int>(18, 24, 12)
        )
        let shoulderAnchors = Array(
            first[ranges[.shouldersAndChest] ?? (0..<0)]
        )
        let leftShoulderAnchors = shoulderAnchors.filter { $0.x < 0 }
        let rightShoulderAnchors = shoulderAnchors.filter { $0.x >= 0 }
        let leftShoulderDensity = densityStats(
            leftShoulderAnchors,
            bounds: bounds,
            bins: SIMD3<Int>(18, 24, 12)
        )
        let rightShoulderDensity = densityStats(
            rightShoulderAnchors,
            bounds: bounds,
            bins: SIMD3<Int>(18, 24, 12)
        )
        let shoulderSideImbalance = Float(
            abs(leftShoulderAnchors.count - rightShoulderAnchors.count)
        ) / Float(max(shoulderAnchors.count, 1))
        let transitionGap = maximumTransitionGap(
            anchors: first,
            ranges: ranges
        )
        require(abs(centroid.x) < 0.04, "centroid x")
        require(centroid.y > -0.30 && centroid.y < 0.12, "centroid y")
        require(abs(centroid.z) < 0.03, "centroid z")
        require(bounds.minimum.x < -0.58 && bounds.maximum.x > 0.58, "shoulder width")
        require(bounds.minimum.y < -1.06 && bounds.maximum.y > 0.91, "vertical bounds")
        require(bounds.minimum.z < -0.25 && bounds.maximum.z > 0.25, "front/back thickness")
        require(bounds.maximum.x - bounds.minimum.x < 1.45, "maximum width")
        require(bounds.maximum.y - bounds.minimum.y < 2.08, "maximum height")
        require(density.occupied > 1_000, "spatial density coverage")
        require(
            density.maximumToPercentile95 <= 1.55,
            "no local density spike"
        )
        require(
            shoulderSideImbalance < 0.02,
            "shoulder side density balance"
        )
        require(
            max(
                leftShoulderDensity.maximum,
                rightShoulderDensity.maximum
            ) <= 32,
            "shoulder local density bound"
        )
        require(
            abs(
                leftShoulderDensity.maximum
                    - rightShoulderDensity.maximum
            ) <= 3,
            "shoulder local density symmetry"
        )
        require(
            transitionGap < 0.015,
            "head neck shoulder torso transition coverage"
        )

        var simulation = ParticleSimulation(time: 1_000)
        let particleCountBefore = simulation.particleCount
        let rebuildCountBefore = simulation.rebuildCount
        let initialSpherePayloads = simulation.vertexPayloads
        let visualController = ParticleStateController(
            intent: .idle,
            time: 1_000
        )
        var time: TimeInterval = 1_001
        require(
            simulation.setShapeTarget(
                .abstractBust,
                reason: "sphereToAbstractBustCheck",
                time: time
            ),
            "start sphere to abstract bust morph"
        )
        require(
            !simulation.setShapeTarget(
                .abstractBust,
                reason: "duplicateAbstractBustCheck",
                time: time + 0.01
            ),
            "duplicate target does not restart"
        )
        var frame = advance(
            simulation: &simulation,
            controller: visualController,
            time: &time,
            frames: 72
        )
        let bustPayloads = simulation.vertexPayloads
        require(frame.shapeState.progress == 1, "sphere to bust completes")
        require(frame.shapeState.targetTarget == .abstractBust, "bust target state")
        require(bustPayloads.count == 12_000, "bust payload count")
        require(bustPayloads.allSatisfy(isFinite), "finite bust payloads")
        require(bustPayloads != initialSpherePayloads, "sphere/bust distinction")
        let motionTimeAfterBust = frame.motionElapsedTime
        let flowTimeAfterBust = frame.flowElapsedTime

        require(
            simulation.setShapeTarget(
                .sphere,
                reason: "abstractBustToSphereCheck",
                time: time
            ),
            "start abstract bust to sphere morph"
        )
        let reverseStartPayloads = simulation.vertexPayloads
        require(
            reverseStartPayloads == bustPayloads,
            "reverse switch has no position jump"
        )
        frame = advance(
            simulation: &simulation,
            controller: visualController,
            time: &time,
            frames: 72
        )
        let spherePayloads = simulation.vertexPayloads
        require(frame.shapeState.progress == 1, "bust to sphere completes")
        require(spherePayloads.allSatisfy(isFinite), "finite sphere payloads")
        require(
            frame.motionElapsedTime > motionTimeAfterBust,
            "lifecycle motion continues during morph"
        )
        require(
            frame.flowElapsedTime > flowTimeAfterBust,
            "flow life continues during morph"
        )

        require(
            simulation.setShapeTarget(
                .customShape,
                reason: "customShapeRegression",
                time: time
            ),
            "custom shape regression selection"
        )
        frame = advance(
            simulation: &simulation,
            controller: visualController,
            time: &time,
            frames: 72
        )
        let customPayloads = simulation.vertexPayloads
        require(customPayloads.allSatisfy(isFinite), "finite custom payloads")
        require(spherePayloads != customPayloads, "sphere/custom shape distinction")

        require(
            simulation.setShapeTarget(
                .abstractBust,
                reason: "interruptPrepare",
                time: time
            ),
            "start interrupt preparation"
        )
        _ = advance(
            simulation: &simulation,
            controller: visualController,
            time: &time,
            frames: 24
        )
        let interruptPosition = simulation.vertexPayloads
        require(
            simulation.setShapeTarget(
                .sphere,
                reason: "interruptReverse",
                time: time
            ),
            "reverse during transition"
        )
        require(
            interruptPosition == simulation.vertexPayloads,
            "interrupted reverse has no position jump"
        )

        let morphResult = simulation.debugMorphStressResult()
        if !morphResult.passed {
            fputs(
                "morph diagnostics continuity="
                    + "\(format(morphResult.continuityError)) "
                    + "retarget=\(format(morphResult.retargetStartError)) "
                    + "sphereToBust="
                    + "\(format(morphResult.sphereToBustCompletionError)) "
                    + "bustToSphere="
                    + "\(format(morphResult.bustToSphereCompletionError)) "
                    + "maxAnchor="
                    + "\(format(morphResult.maximumAnchorRadius)) "
                    + "maxPosition="
                    + "\(format(morphResult.maximumPositionRadius)) "
                    + "duplicate="
                    + "\(morphResult.duplicateRequestIgnored) "
                    + "monotonic="
                    + "\(morphResult.monotonicProgressPreserved) "
                    + "resume="
                    + "\(format(morphResult.resumeProgressStep))\n",
                stderr
            )
        }
        require(morphResult.passed, "morph stress result")
        require(
            morphResult.stressSwitchCount == 100,
            "100 shape switch stress count"
        )
        require(
            morphResult.continuityError
                <= ParticleTuning.Engine.debugContinuityTolerance,
            "retarget position continuity"
        )
        require(
            morphResult.retargetStartError
                <= ParticleShapeMorphTuning.retargetStartTolerance,
            "retarget starts from current positions"
        )
        require(
            morphResult.sphereToBustCompletionError
                <= ParticleShapeMorphTuning.completionTolerance,
            "sphere to bust completion error"
        )
        require(
            morphResult.bustToSphereCompletionError
                <= ParticleShapeMorphTuning.completionTolerance,
            "bust to sphere completion error"
        )
        require(
            morphResult.maximumAnchorRadius
                <= ParticleShapeMorphTuning.maximumAnchorRadius,
            "rapid switching does not explode"
        )
        require(
            morphResult.maximumPositionRadius
                <= ParticleShapeMorphTuning.maximumPositionRadius,
            "rapid switching positions remain bounded"
        )
        require(
            morphResult.duplicateRequestIgnored,
            "stress duplicate target ignored"
        )
        require(
            morphResult.monotonicProgressPreserved,
            "morph progress remains monotonic"
        )
        require(particleCountBefore == simulation.particleCount, "particle count preserved")
        require(rebuildCountBefore == simulation.rebuildCount, "shape switch does not rebuild")

        print(
            "abstract_bust_morph_check PASS "
                + "count=\(first.count) "
                + "centroid=(\(format(centroid.x)),\(format(centroid.y)),\(format(centroid.z))) "
                + "boundsX=(\(format(bounds.minimum.x)),\(format(bounds.maximum.x))) "
                + "boundsY=(\(format(bounds.minimum.y)),\(format(bounds.maximum.y))) "
                + "boundsZ=(\(format(bounds.minimum.z)),\(format(bounds.maximum.z))) "
                + "sphereToBustError="
                + "\(format(morphResult.sphereToBustCompletionError)) "
                + "bustToSphereError="
                + "\(format(morphResult.bustToSphereCompletionError)) "
                + "retargetError="
                + "\(format(morphResult.retargetStartError)) "
                + "maxAnchorRadius="
                + "\(format(morphResult.maximumAnchorRadius)) "
                + "maxPositionRadius="
                + "\(format(morphResult.maximumPositionRadius)) "
                + "densityMaxToP95="
                + "\(format(density.maximumToPercentile95)) "
                + "densityOccupied=\(density.occupied) "
                + "shoulderSideImbalance="
                + "\(format(shoulderSideImbalance)) "
                + "shoulderVoxelMax="
                + "\(leftShoulderDensity.maximum)"
                + "/\(rightShoulderDensity.maximum) "
                + "transitionGap=\(format(transitionGap)) "
                + "switches=\(morphResult.stressSwitchCount) "
                + "rebuildCount=\(rebuildCountBefore)->\(simulation.rebuildCount)"
        )
    }

    @discardableResult
    private static func advance(
        simulation: inout ParticleSimulation,
        controller: ParticleStateController,
        time: inout TimeInterval,
        frames: Int
    ) -> ParticleSimulationFrame {
        var frame: ParticleSimulationFrame?
        for _ in 0..<frames {
            time += 1.0 / 60.0
            frame = simulation.advance(
                time: time,
                drawableSize: CGSize(width: 800, height: 800),
                visualState: controller.advance(time: time)
            )
        }
        guard let frame else {
            fail("advance requires at least one frame")
        }
        return frame
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

    private struct DensityStats {
        let occupied: Int
        let maximum: Int
        let percentile95: Int

        var maximumToPercentile95: Float {
            Float(maximum) / Float(max(percentile95, 1))
        }
    }

    private static func densityStats(
        _ anchors: [SIMD3<Float>],
        bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>),
        bins: SIMD3<Int>
    ) -> DensityStats {
        guard !anchors.isEmpty else {
            return DensityStats(occupied: 0, maximum: 0, percentile95: 0)
        }
        let extent = simd_max(
            bounds.maximum - bounds.minimum,
            SIMD3<Float>(repeating: 0.000_01)
        )
        let binCount = bins.x * bins.y * bins.z
        var occupancy = Array(repeating: 0, count: binCount)
        for anchor in anchors {
            let unit = simd_clamp(
                (anchor - bounds.minimum) / extent,
                SIMD3<Float>(repeating: 0),
                SIMD3<Float>(repeating: 0.999_999)
            )
            let x = Int(unit.x * Float(bins.x))
            let y = Int(unit.y * Float(bins.y))
            let z = Int(unit.z * Float(bins.z))
            occupancy[(y * bins.z + z) * bins.x + x] += 1
        }
        let occupiedValues = occupancy.filter { $0 > 0 }.sorted()
        let percentileIndex = min(
            occupiedValues.count - 1,
            Int(Float(occupiedValues.count) * 0.95)
        )
        return DensityStats(
            occupied: occupiedValues.count,
            maximum: occupiedValues.last ?? 0,
            percentile95: occupiedValues[percentileIndex]
        )
    }

    private static func maximumTransitionGap(
        anchors: [SIMD3<Float>],
        ranges: [AbstractBustAnchorRegion: Range<Int>]
    ) -> Float {
        let transitions: [
            (AbstractBustAnchorRegion, AbstractBustAnchorRegion)
        ] = [
            (.head, .neck),
            (.neck, .shouldersAndChest),
            (.shouldersAndChest, .torso)
        ]
        var maximumGap: Float = 0
        for (upperRegion, lowerRegion) in transitions {
            guard let upperRange = ranges[upperRegion],
                  let lowerRange = ranges[lowerRegion] else {
                return .infinity
            }
            let upperBounds = bounds(of: Array(anchors[upperRange]))
            let lowerBounds = bounds(of: Array(anchors[lowerRange]))
            maximumGap = max(
                maximumGap,
                max(0, upperBounds.minimum.y - lowerBounds.maximum.y)
            )
        }
        return maximumGap
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
