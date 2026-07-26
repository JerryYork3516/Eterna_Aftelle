import Foundation

private enum ParticleExpressionTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct ParticleExpressionTests {
    private static var checkCount = 0
    private static let tolerance: Float = 0.000_01

    static func main() throws {
        try testNeutralPreservesBaseline()
        try testFiveStateMappings()
        try testIntensityMappings()
        try testPerceptualStateSeparation()
        try testRelativeColorMapping()
        try testSameInputDoesNotRestart()
        try testMinimumHoldDuration()
        try testPendingTargetSupersededAtHoldBoundary()
        try testTransitionDuration()
        try testRetargetContinuesFromLiveValue()
        try testChangedMappingRetargets()
        try testLongIdleDoesNotDriveProgress()
        try testLifecycleStateSeparation()
        try testLifecycleTransitionCurve()
        try testLifecycleCompositionAndOverrides()
        try testLifecycleOverrideResumeTransition()
        try testInvalidAndCompatibilityFallbacks()
        try testTraceCorrelation()
        try testD1ProjectionBridge()
        try testSixRendererChannels()
        try testSimulationRegression()
        print("particle-expression-tests: \(checkCount) checks passed")
    }

    private static func testNeutralPreservesBaseline() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        let baseline = controller.advance(time: 0)
        try expect(
            baseline.expression.currentMultipliers == .unit,
            "neutral current multipliers"
        )
        try expect(
            baseline.expression.targetMultipliers == .unit,
            "neutral target multipliers"
        )
        try expect(
            baseline.expression.appliedMultipliers == .unit,
            "neutral applied multipliers"
        )

        let color = SIMD4<Float>(0.23, 0.61, 0.88, 0.74)
        try expect(
            ParticleExpressionMultipliers.unit.applyingColor(to: color) == color,
            "neutral color must be bitwise unchanged"
        )
        try expectNear(
            ParticleExpressionMultipliers.unit.applyingBrightness(to: 0.72),
            0.72,
            "neutral brightness"
        )
        try expectNear(
            ParticleExpressionMultipliers.unit.applyingEnergy(
                to: 0.83,
                maximum: 2
            ),
            0.83,
            "neutral energy"
        )
        try expectNear(
            ParticleExpressionMultipliers.unit.applyingMotionSpeed(to: 0.17),
            0.17,
            "neutral motion speed"
        )
        try expectNear(
            ParticleExpressionMultipliers.unit.applyingDiffusion(
                to: 0.64,
                maximum: 2
            ),
            0.64,
            "neutral diffusion"
        )

        let drNeutral = makeInput(
            state: .neutral,
            intensity: 0,
            multipliers: .unit
        )
        try expect(
            !controller.setExpressionInput(drNeutral, time: 0),
            "neutral metadata update must not restart"
        )
        try expect(
            controller.advance(time: 0).expression.targetInput.mappingSource
                == "dr",
            "neutral metadata source must still update"
        )
    }

    private static func testFiveStateMappings() throws {
        for state in ParticleExpressionState.allCases {
            let controller = ParticleStateController(intent: .idle, time: 0)
            var time: TimeInterval = 0
            _ = advance(controller, time: &time, by: 0.4)
            let target = mapping(for: state)
            let input = makeInput(
                state: state,
                intensity: 1,
                multipliers: target
            )
            _ = controller.setExpressionInput(input, time: time)
            let visual = advance(controller, time: &time, by: 0.6)
            try expect(
                visual.expression.targetInput.state == state,
                "\(state.rawValue) state"
            )
            try expectMultipliers(
                visual.expression.currentMultipliers,
                target,
                "\(state.rawValue) current"
            )
            try expectMultipliers(
                visual.expression.appliedMultipliers,
                target,
                "\(state.rawValue) applied"
            )
        }
    }

    private static func testIntensityMappings() throws {
        let fullTarget = mapping(for: .caring)
        for intensity in [0.0, 0.5, 1.0] {
            let expected = scaled(fullTarget, by: Float(intensity))
            let input = makeInput(
                state: .caring,
                intensity: intensity,
                multipliers: expected
            )
            try expectNear(
                input.intensity,
                Float(intensity),
                "intensity \(intensity)"
            )
            try expectMultipliers(
                input.multipliers,
                expected,
                "intensity target \(intensity)"
            )
        }
    }

    private static func testPerceptualStateSeparation() throws {
        let responses = ParticleExpressionState.allCases.map { state in
            (
                state,
                scaled(mapping(for: state), by: 0.5).visualResponse
            )
        }
        for (_, response) in responses {
            try expect(
                ParticleTuning.Engine.expressionBrightnessRange
                    .contains(response.brightnessMultiplier)
                    && ParticleTuning.Engine.expressionSaturationRange
                    .contains(response.saturationMultiplier)
                    && ParticleTuning.Engine.expressionTemperatureRange
                    .contains(response.temperatureShift)
                    && ParticleTuning.Engine.expressionEnergyRange
                    .contains(response.energyMultiplier)
                    && ParticleTuning.Engine.expressionMotionRange
                    .contains(response.motionSpeedMultiplier)
                    && ParticleTuning.Engine.expressionDiffusionRange
                    .contains(response.diffusionMultiplier),
                "perceptual expression response remains in safe ranges"
            )
        }
        for firstIndex in responses.indices {
            for secondIndex in responses.indices
                where secondIndex > firstIndex {
                let first = responses[firstIndex]
                let second = responses[secondIndex]
                try expect(
                    maximumMultiplierDifference(
                        first.1,
                        second.1
                    ) >= 0.05,
                    "\(first.0.rawValue) and \(second.0.rawValue) remain visually distinct"
                )
            }
        }
    }

    private static func testRelativeColorMapping() throws {
        let modifier = mapping(for: .caring)
        let userColor = SIMD4<Float>(0.18, 0.54, 0.91, 1)
        let residentColor = SIMD4<Float>(0.68, 0.24, 0.36, 1)
        let modifiedUserColor = modifier.applyingColor(to: userColor)
        let modifiedResidentColor = modifier.applyingColor(to: residentColor)

        try expect(
            modifiedUserColor != modifiedResidentColor,
            "expression color must remain relative to the selected base color"
        )
        try expect(
            modifiedUserColor != modifier.applyingColor(
                to: ParticleColorProfile.systemDefault.baseVector
            ),
            "user override must not collapse to a fixed state color"
        )
        try expect(
            [modifiedUserColor, modifiedResidentColor].allSatisfy {
                (0...1).contains($0.x)
                    && (0...1).contains($0.y)
                    && (0...1).contains($0.z)
            },
            "relative colors must remain clamped"
        )
    }

    private static func testSameInputDoesNotRestart() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        let input = makeInput(
            state: .joyful,
            intensity: 0.8,
            multipliers: scaled(mapping(for: .joyful), by: 0.8)
        )
        try expect(
            controller.setExpressionInput(input, time: time),
            "first expression input must start a transition"
        )
        let before = advance(controller, time: &time, by: 0.2)
        try expect(
            !controller.setExpressionInput(input, time: time),
            "same state and intensity must not restart"
        )
        let after = advance(controller, time: &time, by: 0.05)
        try expect(
            after.expression.transitionProgress
                > before.expression.transitionProgress,
            "same input must preserve transition progress"
        )
    }

    private static func testMinimumHoldDuration() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        let caring = makeInput(
            state: .caring,
            intensity: 1,
            multipliers: mapping(for: .caring)
        )
        let joyful = makeInput(
            state: .joyful,
            intensity: 1,
            multipliers: mapping(for: .joyful)
        )
        try expect(
            controller.setExpressionInput(caring, time: time),
            "caring transition start"
        )
        _ = advance(controller, time: &time, by: 0.1)
        try expect(
            !controller.setExpressionInput(joyful, time: time),
            "new target inside hold must queue"
        )
        let held = advance(controller, time: &time, by: 0.24)
        try expect(
            held.expression.targetInput.state == .joyful,
            "queued target must be visible"
        )
        try expectNear(
            held.expression.transitionProgress,
            0,
            "minimum hold progress"
        )
        let released = advance(controller, time: &time, by: 0.08)
        try expect(
            released.expression.transitionProgress > 0,
            "queued target must begin after minimum hold"
        )
    }

    private static func testTransitionDuration() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        let input = makeInput(
            state: .joyful,
            intensity: 1,
            multipliers: mapping(for: .joyful)
        )
        _ = controller.setExpressionInput(input, time: time)
        let quarter = advance(controller, time: &time, by: 0.15)
        try expectNear(
            quarter.expression.transitionProgress,
            0.25,
            "0.6 second transition quarter",
            tolerance: 0.002
        )
        try expectMultipliers(
            quarter.expression.currentMultipliers,
            ParticleExpressionMultipliers.unit.interpolated(
                to: input.multipliers,
                progress: 0.156_25
            ),
            "cubic expression transition quarter"
        )
        let halfway = advance(controller, time: &time, by: 0.15)
        try expectNear(
            halfway.expression.transitionProgress,
            0.5,
            "0.6 second transition halfway",
            tolerance: 0.002
        )
        let complete = advance(controller, time: &time, by: 0.3)
        try expectNear(
            complete.expression.transitionProgress,
            1,
            "0.6 second transition complete"
        )
    }

    private static func testPendingTargetSupersededAtHoldBoundary() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        let caring = makeInput(
            state: .caring,
            intensity: 1,
            multipliers: mapping(for: .caring)
        )
        let joyful = makeInput(
            state: .joyful,
            intensity: 1,
            multipliers: mapping(for: .joyful)
        )
        let calm = makeInput(
            state: .calm,
            intensity: 1,
            multipliers: mapping(for: .calm)
        )
        _ = controller.setExpressionInput(caring, time: time)
        _ = advance(controller, time: &time, by: 0.1)
        try expect(
            !controller.setExpressionInput(joyful, time: time),
            "joyful must queue inside caring hold"
        )

        _ = advance(controller, time: &time, by: 0.24)
        time += 0.02
        try expect(
            controller.setExpressionInput(calm, time: time),
            "latest input must be accepted after hold"
        )
        let retargeted = controller.advance(time: time)
        try expect(
            retargeted.expression.targetInput.state == .calm,
            "expired pending target must not flash before latest input"
        )

        let returnController = ParticleStateController(intent: .idle, time: 0)
        var returnTime: TimeInterval = 0
        _ = advance(returnController, time: &returnTime, by: 0.4)
        _ = returnController.setExpressionInput(caring, time: returnTime)
        _ = advance(returnController, time: &returnTime, by: 0.1)
        _ = returnController.setExpressionInput(joyful, time: returnTime)
        _ = advance(returnController, time: &returnTime, by: 0.24)
        returnTime += 0.02
        try expect(
            !returnController.setExpressionInput(caring, time: returnTime),
            "latest input matching accepted state must cancel pending"
        )
        try expect(
            returnController.advance(time: returnTime)
                .expression.targetInput.state == .caring,
            "return to accepted state must not flash pending target"
        )
    }

    private static func testRetargetContinuesFromLiveValue() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        let joyful = makeInput(
            state: .joyful,
            intensity: 1,
            multipliers: mapping(for: .joyful)
        )
        let calm = makeInput(
            state: .calm,
            intensity: 1,
            multipliers: mapping(for: .calm)
        )
        _ = controller.setExpressionInput(joyful, time: time)
        let beforeRetarget = advance(controller, time: &time, by: 0.4)
        try expect(
            controller.setExpressionInput(calm, time: time),
            "retarget after hold"
        )
        let afterRetarget = controller.advance(time: time)
        try expectMultipliers(
            afterRetarget.expression.currentMultipliers,
            beforeRetarget.expression.currentMultipliers,
            "retarget continuity"
        )
    }

    private static func testChangedMappingRetargets() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        let original = makeInput(
            state: .caring,
            intensity: 1,
            multipliers: mapping(for: .caring)
        )
        _ = controller.setExpressionInput(original, time: time)
        let before = advance(controller, time: &time, by: 0.4)
        let changedMultipliers = ParticleExpressionMultipliers(
            brightnessMultiplier: 1.03,
            saturationMultiplier: 1.02,
            temperatureShift: 0.02,
            energyMultiplier: 1.01,
            motionSpeedMultiplier: 0.97,
            diffusionMultiplier: 1.01
        )
        let changed = makeInput(
            state: .caring,
            intensity: 1,
            multipliers: changedMultipliers
        )
        try expect(
            controller.setExpressionInput(changed, time: time),
            "same state and intensity with changed mapping must retarget"
        )
        let after = controller.advance(time: time)
        try expectMultipliers(
            after.expression.currentMultipliers,
            before.expression.currentMultipliers,
            "changed mapping continuity"
        )
        try expectMultipliers(
            after.expression.targetMultipliers,
            changedMultipliers,
            "changed mapping target"
        )
    }

    private static func testLongIdleDoesNotDriveProgress() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        time = 3_600
        _ = controller.advance(time: time)
        let joyful = makeInput(
            state: .joyful,
            intensity: 1,
            multipliers: mapping(for: .joyful)
        )
        _ = controller.setExpressionInput(joyful, time: time)
        let started = controller.advance(time: time)
        try expectNear(
            started.expression.transitionProgress,
            0,
            "idle history must not start transition progress"
        )
        time = 7_200
        let resumed = controller.advance(time: time)
        try expect(
            resumed.expression.transitionProgress < 0.06,
            "long pause must contribute at most one clamped frame"
        )
    }

    private static func testLifecycleStateSeparation() throws {
        let states = ResidentVisualIntent.allCases.map {
            ($0, ParticleVisualChannels.target(for: $0))
        }
        for firstIndex in states.indices {
            for secondIndex in states.indices
                where secondIndex > firstIndex {
                let first = states[firstIndex]
                let second = states[secondIndex]
                try expect(
                    maximumChannelDifference(
                        first.1,
                        second.1
                    ) >= 0.30,
                    "\(first.0.rawValue) and \(second.0.rawValue) lifecycle profiles remain distinct"
                )
            }
        }
    }

    private static func testLifecycleTransitionCurve() throws {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        controller.setIntent(
            .thinking,
            reason: "test.lifecycle.cubic",
            time: time
        )
        let quarter = advance(
            controller,
            time: &time,
            by: ParticleTuning.Engine.thinkingTransitionDuration * 0.25
        )
        try expectNear(
            quarter.transitionProgress,
            0.25,
            "lifecycle transition quarter",
            tolerance: 0.002
        )
        try expectChannels(
            quarter.channels,
            ParticleVisualChannels.target(for: .idle).interpolated(
                to: ParticleVisualChannels.target(for: .thinking),
                progress: 0.156_25
            ),
            "cubic lifecycle transition quarter"
        )
    }

    private static func testLifecycleCompositionAndOverrides() throws {
        let composable: [ResidentVisualIntent] = [.idle, .thinking, .speaking]
        for intent in composable {
            let (controller, time, target) = settledJoyfulController()
            controller.setIntent(intent, reason: "test.compose", time: time)
            let state = controller.advance(time: time)
            try expect(
                !state.expression.lifecycleOverrideActive,
                "\(intent.rawValue) must compose expression"
            )
            try expectMultipliers(
                state.expression.appliedMultipliers,
                target,
                "\(intent.rawValue) applied expression"
            )
        }

        let overrides: [ResidentVisualIntent] = [
            .error, .loading, .exit, .listening, .sleeping
        ]
        for intent in overrides {
            let (controller, time, _) = settledJoyfulController()
            controller.setIntent(intent, reason: "test.override", time: time)
            let state = controller.advance(time: time)
            try expect(
                state.expression.lifecycleOverrideActive,
                "\(intent.rawValue) must override expression"
            )
            try expectMultipliers(
                state.expression.appliedMultipliers,
                .unit,
                "\(intent.rawValue) override unit"
            )
        }

        let (errorController, startTime, _) = settledJoyfulController()
        var time = startTime
        errorController.setIntent(.error, reason: "test.error.first", time: time)
        _ = advance(errorController, time: &time, by: 0.1)
        let repeatedInput = makeInput(
            state: .joyful,
            intensity: 1,
            multipliers: mapping(for: .joyful)
        )
        try expect(
            !errorController.setExpressionInput(repeatedInput, time: time),
            "expression dedup remains independent"
        )
        errorController.setIntent(.error, reason: "test.error.repeat", time: time)
        let repeatedError = errorController.advance(time: time)
        try expectNear(
            repeatedError.transitionProgress,
            0,
            "repeated error must restart lifecycle behavior"
        )
        try expect(
            repeatedError.expression.lifecycleOverrideActive,
            "repeated error keeps expression overridden"
        )
    }

    private static func testLifecycleOverrideResumeTransition() throws {
        let (controller, startTime, target) = settledJoyfulController()
        var time = startTime
        controller.setIntent(
            .error,
            reason: "test.override.resume.error",
            time: time
        )
        var state = controller.advance(time: time)
        try expect(
            state.expression.appliedMultipliers == .unit,
            "override entry must apply unit"
        )
        _ = advance(controller, time: &time, by: 0.2)
        controller.setIntent(
            .idle,
            reason: "test.override.resume.idle",
            time: time
        )

        var firstComposable: ParticleVisualState?
        for _ in 0..<240 {
            time += 1.0 / 120.0
            state = controller.advance(time: time)
            if !state.expression.lifecycleOverrideActive {
                firstComposable = state
                break
            }
        }
        guard let firstComposable else {
            throw ParticleExpressionTestError.failed(
                "lifecycle must return to composable state"
            )
        }
        try expectMultipliers(
            firstComposable.expression.appliedMultipliers,
            .unit,
            "override exit starts from current visible unit"
        )
        try expectNear(
            firstComposable.expression.transitionProgress,
            0,
            "override exit transition restarts"
        )
        let halfway = advance(controller, time: &time, by: 0.3)
        try expect(
            halfway.expression.appliedMultipliers != .unit
                && halfway.expression.appliedMultipliers != target,
            "override resume must interpolate"
        )
        let complete = advance(controller, time: &time, by: 0.3)
        try expectMultipliers(
            complete.expression.appliedMultipliers,
            target,
            "override resume completes in 0.6 seconds"
        )
    }

    private static func testInvalidAndCompatibilityFallbacks() throws {
        let interactionID = UUID()
        let invalid = ParticleExpressionInput(
            interactionID: interactionID,
            state: "excited",
            intensity: 0.8,
            fallbackOccurred: false,
            mappingSource: "dr",
            brightnessMultiplier: 1.2,
            saturationMultiplier: 1.1,
            temperatureShift: 0.1,
            energyMultiplier: 1.2,
            motionSpeedMultiplier: 1.1,
            diffusionMultiplier: 1.1
        )
        try expect(
            invalid.state == .neutral
                && invalid.fallbackOccurred
                && invalid.multipliers == .unit
                && invalid.interactionID == interactionID,
            "invalid state fallback"
        )

        let missing = ParticleExpressionInput(
            state: nil,
            intensity: nil,
            fallbackOccurred: false,
            mappingSource: nil,
            brightnessMultiplier: nil,
            saturationMultiplier: nil,
            temperatureShift: nil,
            energyMultiplier: nil,
            motionSpeedMultiplier: nil,
            diffusionMultiplier: nil
        )
        try expect(
            missing == .neutral,
            "missing expression fallback"
        )
        try expect(
            ParticleExpressionInput.neutral.state == .neutral
                && ParticleExpressionInput.neutral.mappingSource
                == "compatibility_fallback"
                && ParticleExpressionInput.neutral.fallbackOccurred,
            "old DR compatibility fallback"
        )

        let (controller, time, _) = settledJoyfulController()
        try expect(
            controller.setExpressionInput(.neutral, time: time),
            "compatibility reset must replace active expression"
        )
        let reset = controller.advance(time: time)
        try expect(
            reset.expression.currentMultipliers == .unit
                && reset.expression.targetMultipliers == .unit
                && reset.expression.transitionProgress == 1,
            "compatibility reset must prevent cross-resident bleed"
        )
    }

    private static func testTraceCorrelation() throws {
        let interactionID = UUID()
        let otherInteractionID = UUID()
        let input = makeInput(
            interactionID: interactionID,
            state: .caring,
            intensity: 0.5,
            multipliers: scaled(mapping(for: .caring), by: 0.5)
        )
        let visual = ParticleExpressionVisualState(
            targetInput: input,
            currentMultipliers: .unit,
            targetMultipliers: input.multipliers,
            appliedMultipliers: .unit,
            transitionProgress: 0,
            lifecycleOverrideActive: false
        )
        try expect(
            visual.matches(
                interactionID: interactionID,
                state: "caring",
                intensity: 0.5,
                fallbackOccurred: false,
                mappingSource: "dr",
                targetMultipliers: input.multipliers
            ),
            "D1 expression snapshot exact interaction match"
        )
        try expect(
            !visual.matches(
                interactionID: otherInteractionID,
                state: "caring",
                intensity: 0.5,
                fallbackOccurred: false,
                mappingSource: "dr",
                targetMultipliers: input.multipliers
            ),
            "D1 repeated expression must not cross interactions"
        )
        try expect(
            !visual.matches(
                interactionID: interactionID,
                state: "caring",
                intensity: 0.5,
                fallbackOccurred: true,
                mappingSource: "dr",
                targetMultipliers: input.multipliers
            ),
            "D1 fallback metadata must match"
        )
    }

    private static func testD1ProjectionBridge() throws {
        let interactionID = UUID()
        let otherInteractionID = UUID()
        let target = scaled(mapping(for: .caring), by: 0.5)
        let current = ParticleExpressionMultipliers.unit.interpolated(
            to: target,
            progress: 0.4
        )
        let input = makeInput(
            interactionID: interactionID,
            state: .caring,
            intensity: 0.5,
            multipliers: target
        )
        let visual = ParticleExpressionVisualState(
            targetInput: input,
            currentMultipliers: current,
            targetMultipliers: target,
            appliedMultipliers: current,
            transitionProgress: 0.4,
            lifecycleOverrideActive: false
        )

        var view = RuntimeOrchestrationInteractionViewState(
            makeInteraction(
                id: interactionID,
                mapping: target
            )
        )
        try expectNear(
            Float(view.expressionTransitionProgress),
            0,
            "D1 unmatched transition starts pending"
        )
        try expectNear(
            Float(view.currentBrightnessMultiplier),
            1,
            "D1 unmatched current starts at neutral evidence"
        )
        view.apply(particleExpression: visual)
        try expectNear(
            Float(view.expressionTransitionProgress),
            0.4,
            "D1 exact snapshot progress"
        )
        try expectNear(
            Float(view.currentBrightnessMultiplier),
            current.brightnessMultiplier,
            "D1 exact snapshot current brightness"
        )

        var repeatedView = RuntimeOrchestrationInteractionViewState(
            makeInteraction(
                id: otherInteractionID,
                mapping: target
            )
        )
        repeatedView.apply(particleExpression: visual)
        try expectNear(
            Float(repeatedView.expressionTransitionProgress),
            0,
            "D1 repeated expression remains interaction isolated"
        )
        repeatedView.applyPendingCurrent(particleExpression: visual)
        try expectNear(
            Float(repeatedView.currentBrightnessMultiplier),
            current.brightnessMultiplier,
            "D1 pending interaction uses last rendered current"
        )
        try expectNear(
            Float(repeatedView.expressionTransitionProgress),
            0,
            "D1 pending interaction does not claim completion"
        )

        var fallbackView = RuntimeOrchestrationInteractionViewState(
            makeInteraction(
                id: interactionID,
                mapping: target,
                fallbackOccurred: true
            )
        )
        fallbackView.apply(particleExpression: visual)
        try expectNear(
            Float(fallbackView.expressionTransitionProgress),
            0,
            "D1 fallback metadata mismatch is rejected"
        )

        var overrideView = RuntimeOrchestrationInteractionViewState(
            makeInteraction(
                id: interactionID,
                mapping: target,
                lifecycleState: .error
            )
        )
        overrideView.apply(particleExpression: visual)
        try expect(
            overrideView.expressionLifecycleOverrideActive,
            "D1 lifecycle override remains visible"
        )

        var previousState = RuntimeOrchestrationViewState(
            interactions: [view],
            statusKey: nil
        )
        previousState.interactions[0].expressionTransitionProgress = 1
        previousState.interactions[0].currentBrightnessMultiplier =
            Double(target.brightnessMultiplier)
        var refreshedState = RuntimeOrchestrationViewState(
            interactions: [
                RuntimeOrchestrationInteractionViewState(
                    makeInteraction(
                        id: interactionID,
                        mapping: target
                    )
                ),
                RuntimeOrchestrationInteractionViewState(
                    makeInteraction(
                        id: otherInteractionID,
                        mapping: target
                    )
                )
            ],
            statusKey: nil
        )
        refreshedState.preserveParticleExpressionProjections(
            from: previousState
        )
        try expectNear(
            Float(
                refreshedState.interactions[0]
                    .expressionTransitionProgress
            ),
            1,
            "D1 prior interaction keeps sampled progress"
        )
        try expectNear(
            Float(
                refreshedState.interactions[0]
                    .currentBrightnessMultiplier
            ),
            target.brightnessMultiplier,
            "D1 prior interaction keeps sampled current"
        )
        try expectNear(
            Float(
                refreshedState.interactions[1]
                    .expressionTransitionProgress
            ),
            0,
            "D1 new interaction remains pending"
        )

        var reusedIDState = RuntimeOrchestrationViewState(
            interactions: [
                RuntimeOrchestrationInteractionViewState(
                    makeInteraction(
                        id: interactionID,
                        mapping: target,
                        sessionID: "other-session"
                    )
                )
            ],
            statusKey: nil
        )
        reusedIDState.preserveParticleExpressionProjections(
            from: previousState
        )
        try expectNear(
            Float(
                reusedIDState.interactions[0]
                    .expressionTransitionProgress
            ),
            0,
            "D1 projection preservation must not cross sessions"
        )

        let pendingInput = makeInput(
            interactionID: otherInteractionID,
            state: .caring,
            intensity: 0.5,
            multipliers: target
        )
        refreshedState.applyParticleExpression(
            rendered: visual,
            pendingInput: pendingInput,
            sessionID: "session-test"
        )
        try expectNear(
            Float(
                refreshedState.interactions[1]
                    .currentBrightnessMultiplier
            ),
            current.brightnessMultiplier,
            "D1 pending round seeds last rendered current"
        )
        try expectNear(
            Float(
                refreshedState.interactions[1]
                    .expressionTransitionProgress
            ),
            0,
            "D1 pending round stays at zero progress"
        )

        var wrongSessionState = RuntimeOrchestrationViewState(
            interactions: [
                RuntimeOrchestrationInteractionViewState(
                    makeInteraction(
                        id: interactionID,
                        mapping: target
                    )
                )
            ],
            statusKey: nil
        )
        wrongSessionState.applyParticleExpression(
            rendered: visual,
            pendingInput: .neutral,
            sessionID: "other-session"
        )
        try expectNear(
            Float(
                wrongSessionState.interactions[0]
                    .expressionTransitionProgress
            ),
            0,
            "D1 expression snapshot must not cross sessions"
        )
    }

    private static func makeInteraction(
        id: UUID,
        mapping: ParticleExpressionMultipliers,
        fallbackOccurred: Bool = false,
        lifecycleState: RuntimeLifecycleState = .speaking,
        sessionID: String = "session-test"
    ) -> RuntimeOrchestrationInteraction {
        RuntimeOrchestrationInteraction(
            id: id,
            residentID: "resident-test",
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            dailyRulesEnabled: true,
            emotionalRulesEnabled: true,
            recentMessageCount: 0,
            fewShotReferences: [],
            approvedPreferenceCount: 0,
            provider: nil,
            result: .success,
            errorCategory: nil,
            sessionWriteStatus: .saved,
            subtitleState: "showing",
            particleState: "speaking",
            lifecycleState: lifecycleState,
            expressionState: "caring",
            expressionIntensity: 0.5,
            expressionFallbackOccurred: fallbackOccurred,
            expressionMapping: RuntimeExpressionMultipliers(
                brightnessMultiplier: Double(
                    mapping.brightnessMultiplier
                ),
                saturationMultiplier: Double(
                    mapping.saturationMultiplier
                ),
                temperatureShift: Double(mapping.temperatureShift),
                energyMultiplier: Double(mapping.energyMultiplier),
                motionSpeedMultiplier: Double(
                    mapping.motionSpeedMultiplier
                ),
                diffusionMultiplier: Double(mapping.diffusionMultiplier)
            ),
            expressionMappingSource: "dr",
            steps: []
        )
    }

    private static func testSixRendererChannels() throws {
        let values = ParticleExpressionMultipliers(
            brightnessMultiplier: 1.15,
            saturationMultiplier: 1.12,
            temperatureShift: 0.08,
            energyMultiplier: 1.18,
            motionSpeedMultiplier: 1.12,
            diffusionMultiplier: 1.14
        )
        let response = values.visualResponse
        try expectNear(
            response.brightnessMultiplier,
            1.206_896_5,
            "brightness perceptual response"
        )
        try expectNear(
            response.energyMultiplier,
            1.245_454_5,
            "energy perceptual response"
        )
        try expectNear(
            values.applyingBrightness(to: 0.5),
            0.5 * response.brightnessMultiplier,
            "brightness channel"
        )
        try expect(
            values.applyingColor(
                to: SIMD4<Float>(0.4, 0.6, 0.8, 1)
            ) != SIMD4<Float>(0.4, 0.6, 0.8, 1),
            "saturation and temperature channels"
        )
        try expectNear(
            values.applyingEnergy(to: 0.5, maximum: 2),
            0.5 * response.energyMultiplier,
            "energy channel"
        )
        try expectNear(
            values.applyingMotionSpeed(to: 0.5),
            0.5 * response.motionSpeedMultiplier,
            "motion speed channel"
        )
        try expectNear(
            values.applyingDiffusion(to: 0.5, maximum: 2),
            0.5 * response.diffusionMultiplier,
            "diffusion channel"
        )
    }

    private static func testSimulationRegression() throws {
        let neutralController = ParticleStateController(intent: .idle, time: 0)
        let neutralState = neutralController.advance(time: 1.0 / 60.0)
        var neutralSimulation = ParticleSimulation(time: 0)
        let particleCount = neutralSimulation.particleCount
        let rebuildCount = neutralSimulation.rebuildCount
        let shape = neutralSimulation.targetShape
        let neutralFrame = neutralSimulation.advance(
            time: 1.0 / 60.0,
            drawableSize: CGSize(width: 800, height: 800),
            visualState: neutralState
        )
        try expect(
            neutralSimulation.particleCount == particleCount
                && neutralSimulation.rebuildCount == rebuildCount
                && neutralSimulation.targetShape == shape,
            "neutral expression must not rebuild or reshape particles"
        )

        let motionValues = ParticleExpressionMultipliers(
            brightnessMultiplier: 1,
            saturationMultiplier: 1,
            temperatureShift: 0,
            energyMultiplier: 1,
            motionSpeedMultiplier: 1.2,
            diffusionMultiplier: 1
        )
        let motionState = settledVisualState(multipliers: motionValues)
        var motionSimulation = ParticleSimulation(time: 0)
        let motionFrame = motionSimulation.advance(
            time: 1.0 / 60.0,
            drawableSize: CGSize(width: 800, height: 800),
            visualState: motionState
        )
        try expectNear(
            motionFrame.flowElapsedTime,
            neutralFrame.flowElapsedTime * 1.2,
            "motion speed affects only future flow increment",
            tolerance: 0.000_001
        )
        try expect(
            motionSimulation.particleCount == particleCount
                && motionSimulation.rebuildCount == rebuildCount
                && motionSimulation.targetShape == shape,
            "expression must preserve V2 topology and shape target"
        )
    }

    private static func settledJoyfulController()
        -> (ParticleStateController, TimeInterval, ParticleExpressionMultipliers) {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        let target = mapping(for: .joyful)
        _ = controller.setExpressionInput(
            makeInput(
                state: .joyful,
                intensity: 1,
                multipliers: target
            ),
            time: time
        )
        _ = advance(controller, time: &time, by: 0.6)
        return (controller, time, target)
    }

    private static func settledVisualState(
        multipliers: ParticleExpressionMultipliers
    ) -> ParticleVisualState {
        let controller = ParticleStateController(intent: .idle, time: 0)
        var time: TimeInterval = 0
        _ = advance(controller, time: &time, by: 0.4)
        _ = controller.setExpressionInput(
            makeInput(
                state: .joyful,
                intensity: 1,
                multipliers: multipliers
            ),
            time: time
        )
        return advance(controller, time: &time, by: 0.6)
    }

    private static func mapping(
        for state: ParticleExpressionState
    ) -> ParticleExpressionMultipliers {
        switch state {
        case .neutral:
            return .unit
        case .calm:
            return ParticleExpressionMultipliers(
                brightnessMultiplier: 0.96,
                saturationMultiplier: 0.9,
                temperatureShift: -0.03,
                energyMultiplier: 0.88,
                motionSpeedMultiplier: 0.86,
                diffusionMultiplier: 0.92
            )
        case .caring:
            return ParticleExpressionMultipliers(
                brightnessMultiplier: 1.06,
                saturationMultiplier: 1.04,
                temperatureShift: 0.05,
                energyMultiplier: 1.02,
                motionSpeedMultiplier: 0.94,
                diffusionMultiplier: 1.02
            )
        case .subdued:
            return ParticleExpressionMultipliers(
                brightnessMultiplier: 0.82,
                saturationMultiplier: 0.75,
                temperatureShift: -0.08,
                energyMultiplier: 0.78,
                motionSpeedMultiplier: 0.8,
                diffusionMultiplier: 0.86
            )
        case .joyful:
            return ParticleExpressionMultipliers(
                brightnessMultiplier: 1.15,
                saturationMultiplier: 1.12,
                temperatureShift: 0.08,
                energyMultiplier: 1.18,
                motionSpeedMultiplier: 1.12,
                diffusionMultiplier: 1.14
            )
        }
    }

    private static func scaled(
        _ target: ParticleExpressionMultipliers,
        by intensity: Float
    ) -> ParticleExpressionMultipliers {
        ParticleExpressionMultipliers.unit.interpolated(
            to: target,
            progress: intensity
        )
    }

    private static func makeInput(
        interactionID: UUID? = nil,
        state: ParticleExpressionState,
        intensity: Double,
        multipliers: ParticleExpressionMultipliers
    ) -> ParticleExpressionInput {
        ParticleExpressionInput(
            interactionID: interactionID,
            state: state.rawValue,
            intensity: intensity,
            fallbackOccurred: false,
            mappingSource: "dr",
            brightnessMultiplier: Double(multipliers.brightnessMultiplier),
            saturationMultiplier: Double(multipliers.saturationMultiplier),
            temperatureShift: Double(multipliers.temperatureShift),
            energyMultiplier: Double(multipliers.energyMultiplier),
            motionSpeedMultiplier: Double(multipliers.motionSpeedMultiplier),
            diffusionMultiplier: Double(multipliers.diffusionMultiplier)
        )
    }

    @discardableResult
    private static func advance(
        _ controller: ParticleStateController,
        time: inout TimeInterval,
        by duration: TimeInterval
    ) -> ParticleVisualState {
        let endTime = time + duration
        let step = 1.0 / 120.0
        _ = controller.advance(time: time)
        while time + step < endTime {
            time += step
            _ = controller.advance(time: time)
        }
        time = endTime
        return controller.advance(time: time)
    }

    private static func maximumMultiplierDifference(
        _ lhs: ParticleExpressionMultipliers,
        _ rhs: ParticleExpressionMultipliers
    ) -> Float {
        [
            abs(lhs.brightnessMultiplier - rhs.brightnessMultiplier),
            abs(lhs.saturationMultiplier - rhs.saturationMultiplier),
            abs(lhs.temperatureShift - rhs.temperatureShift),
            abs(lhs.energyMultiplier - rhs.energyMultiplier),
            abs(lhs.motionSpeedMultiplier - rhs.motionSpeedMultiplier),
            abs(lhs.diffusionMultiplier - rhs.diffusionMultiplier)
        ].max() ?? 0
    }

    private static func maximumChannelDifference(
        _ lhs: ParticleVisualChannels,
        _ rhs: ParticleVisualChannels
    ) -> Float {
        [
            abs(lhs.focus - rhs.focus),
            abs(lhs.pulse - rhs.pulse),
            abs(lhs.circulation - rhs.circulation),
            abs(lhs.disruption - rhs.disruption),
            abs(lhs.dissolution - rhs.dissolution)
        ].max() ?? 0
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        checkCount += 1
        guard condition() else {
            throw ParticleExpressionTestError.failed(message)
        }
    }

    private static func expectNear(
        _ actual: Float,
        _ expected: Float,
        _ message: String,
        tolerance: Float = tolerance
    ) throws {
        try expect(
            abs(actual - expected) <= tolerance,
            "\(message): expected \(expected), got \(actual)"
        )
    }

    private static func expectMultipliers(
        _ actual: ParticleExpressionMultipliers,
        _ expected: ParticleExpressionMultipliers,
        _ message: String
    ) throws {
        try expectNear(
            actual.brightnessMultiplier,
            expected.brightnessMultiplier,
            "\(message) brightness"
        )
        try expectNear(
            actual.saturationMultiplier,
            expected.saturationMultiplier,
            "\(message) saturation"
        )
        try expectNear(
            actual.temperatureShift,
            expected.temperatureShift,
            "\(message) temperature"
        )
        try expectNear(
            actual.energyMultiplier,
            expected.energyMultiplier,
            "\(message) energy"
        )
        try expectNear(
            actual.motionSpeedMultiplier,
            expected.motionSpeedMultiplier,
            "\(message) motion"
        )
        try expectNear(
            actual.diffusionMultiplier,
            expected.diffusionMultiplier,
            "\(message) diffusion"
        )
    }

    private static func expectChannels(
        _ actual: ParticleVisualChannels,
        _ expected: ParticleVisualChannels,
        _ message: String
    ) throws {
        try expectNear(
            actual.focus,
            expected.focus,
            "\(message) focus"
        )
        try expectNear(
            actual.pulse,
            expected.pulse,
            "\(message) pulse"
        )
        try expectNear(
            actual.circulation,
            expected.circulation,
            "\(message) circulation"
        )
        try expectNear(
            actual.disruption,
            expected.disruption,
            "\(message) disruption"
        )
        try expectNear(
            actual.dissolution,
            expected.dissolution,
            "\(message) dissolution"
        )
    }
}
