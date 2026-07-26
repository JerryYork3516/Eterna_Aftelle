import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

struct ParticleFrameUniforms {
    var viewportAndRender: SIMD4<Float>
    var interaction: SIMD4<Float>
    var visualChannelsA: SIMD4<Float>
    var visualChannelsB: SIMD4<Float>
    var baseColor: SIMD4<Float>
    var ridgeColor: SIMD4<Float>
    var dimColor: SIMD4<Float>
    var highlightColor: SIMD4<Float>
    var renderGeometry: SIMD4<Float>
    var renderChannels: SIMD4<Float>
    var renderAlpha: SIMD4<Float>
    var renderPoint: SIMD4<Float>
    var renderLight: SIMD4<Float>
    var renderColor: SIMD4<Float>
    var viewOrientation: SIMD4<Float>
}

final class ParticleRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var particleBuffer: MTLBuffer
    private let uniformsBuffer: MTLBuffer
    private let startTime: TimeInterval
    private let stateController: ParticleStateController
    private var simulation: ParticleSimulation
    private var pendingModelRebuild: DispatchWorkItem?
    private var metricsStartTime: TimeInterval
    private var metricsFrameCount = 0
    private var viewOrientation: ParticleViewOrientation = .identity
    private var isManualRotationEnabled = false
    #if DEBUG
    private var isDebugAutoCycleEnabled = false
    private var debugAutoCycleIndex = 0
    private var debugAutoCycleNextTime: TimeInterval?
    #endif
    var debugMetricsHandler: ((ParticleRenderMetrics) -> Void)?

    init?(device: MTLDevice, visualIntent: ResidentVisualIntent = .idle) {
        let now = CACurrentMediaTime()
        let simulation = ParticleSimulation(time: now)
        let stateController = ParticleStateController(intent: visualIntent, time: now)

        self.device = device
        startTime = now
        metricsStartTime = now
        self.simulation = simulation
        self.stateController = stateController

        guard let commandQueue = device.makeCommandQueue() else {
            print("[ParticleCore] commandQueue failed")
            return nil
        }
        guard let library = device.makeDefaultLibrary() else {
            print("[ParticleCore] defaultLibrary failed")
            return nil
        }
        guard let vertexFunction = library.makeFunction(name: "particleVertex"),
              let fragmentFunction = library.makeFunction(name: "particleFragment") else {
            print("[ParticleCore] shader functions missing")
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("[ParticleCore] pipeline failed \(error)")
            return nil
        }

        guard let particleBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD4<Float>>.stride * simulation.particleCount,
            options: .storageModeShared
        ) else {
            print("[ParticleCore] vertexBuffer failed")
            return nil
        }
        guard let uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<ParticleFrameUniforms>.stride,
            options: .storageModeShared
        ) else {
            print("[ParticleCore] uniformsBuffer failed")
            return nil
        }

        self.commandQueue = commandQueue
        self.particleBuffer = particleBuffer
        self.uniformsBuffer = uniformsBuffer

        super.init()
        uploadParticles()
    }

    func draw(in view: MTKView) {
        metricsFrameCount += 1
        let now = CACurrentMediaTime()
        #if DEBUG
        advanceDebugAutoCycle(time: now)
        #endif
        let visualState = stateController.advance(time: now)
        let frame = simulation.advance(
            time: now,
            drawableSize: view.drawableSize,
            visualState: visualState
        )
        uploadParticles()

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                  descriptor: renderPassDescriptor
              ) else { return }

        var uniforms = makeUniforms(from: frame)
        memcpy(
            uniformsBuffer.contents(),
            &uniforms,
            MemoryLayout<ParticleFrameUniforms>.stride
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(
            type: .point,
            vertexStart: 0,
            vertexCount: simulation.particleCount
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        publishDebugMetricsIfNeeded(
            view: view,
            renderElapsedTime: Float(now - startTime),
            frame: frame,
            time: now
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func updateInteraction(
        position: SIMD2<Float>,
        velocity: SIMD2<Float>,
        active: Bool
    ) {
        simulation.updateInteraction(
            position: position,
            velocity: velocity,
            active: active,
            time: CACurrentMediaTime()
        )
    }

    func setVisualIntent(
        _ visualIntent: ResidentVisualIntent,
        reason: String = "appMapping"
    ) {
        let previousIntent = stateController.targetIntent
        stateController.setIntent(
            visualIntent,
            reason: reason,
            time: CACurrentMediaTime()
        )
        guard previousIntent != visualIntent else { return }
        print(
            "[ParticleCore] visualIntent changed \(visualIntent) "
                + "previous=\(previousIntent) reason=\(reason)"
        )
    }

    func setTuning(_ tuning: ParticleTuning) {
        guard simulation.setTuning(tuning) else { return }
        pendingModelRebuild?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.rebuildParticles()
        }
        pendingModelRebuild = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ParticleTuning.Engine.modelRebuildDelay,
            execute: workItem
        )
    }

    func setColorProfile(_ colorProfile: ParticleColorProfile) {
        simulation.setColorProfile(colorProfile)
    }

    func setManualRotationEnabled(_ enabled: Bool) {
        guard isManualRotationEnabled != enabled else { return }
        isManualRotationEnabled = enabled
        print("[ParticleCore] manualRotation enabled=\(enabled)")
    }

    func setViewOrientation(_ orientation: ParticleViewOrientation) {
        viewOrientation = orientation
    }

    func rotateView(
        fromArcballPoint start: SIMD2<Float>,
        to end: SIMD2<Float>
    ) -> ParticleViewOrientation? {
        guard simd_length_squared(end - start)
            > ParticleTuning.Engine.quaternionNormalizationEpsilon else {
            return nil
        }

        let delta = simd_quatf(
            from: Self.arcballVector(start),
            to: Self.arcballVector(end)
        )
        let current = simd_quatf(vector: viewOrientation.quaternion)
        let orientation = ParticleViewOrientation(
            quaternion: (delta * current).vector
        )
        viewOrientation = orientation
        return orientation
    }

    func rebuildParticles() {
        simulation.rebuildParticles()
        let requiredLength = MemoryLayout<SIMD4<Float>>.stride * simulation.particleCount
        if particleBuffer.length != requiredLength {
            guard let rebuiltBuffer = device.makeBuffer(
                length: requiredLength,
                options: .storageModeShared
            ) else {
                print("[ParticleCore] model rebuild buffer failed")
                return
            }
            particleBuffer = rebuiltBuffer
        }
        uploadParticles()
        print(
            "[ParticleCore] simulation rebuilt "
                + "seed=\(ParticleTuning.Engine.modelSeed) "
                + "particleCount=\(simulation.particleCount)"
        )
    }

    #if DEBUG
    func setDebugAutoCycleEnabled(_ enabled: Bool) {
        guard isDebugAutoCycleEnabled != enabled else { return }
        isDebugAutoCycleEnabled = enabled
        debugAutoCycleNextTime = enabled ? CACurrentMediaTime() : nil
        if let index = ResidentVisualIntent.allCases.firstIndex(
            of: stateController.targetIntent
        ) {
            debugAutoCycleIndex = index
        }
        print("[ParticleCore] debugAutoCycle enabled=\(enabled)")
    }

    func runDebugTransitionStressTest() {
        let rebuildCountBefore = simulation.rebuildCount
        var finiteChannels = true
        for index in 0..<ParticleTuning.Engine.debugStressSwitchCount {
            let time = CACurrentMediaTime()
            let intent = ResidentVisualIntent.allCases[
                (index + 1) % ResidentVisualIntent.allCases.count
            ]
            stateController.setIntent(intent, reason: "debugStress", time: time)
            let state = stateController.advance(time: time)
            finiteChannels = finiteChannels && Self.channelsAreFinite(state.channels)
        }
        let rebuildCountAfter = simulation.rebuildCount

        let startTime: TimeInterval = 1_000
        let controller = ParticleStateController(intent: .idle, time: startTime)
        var time = startTime
        controller.setIntent(.thinking, reason: "debugStress.prepare", time: time)
        time += 0.09
        let beforeRetarget = controller.advance(time: time)
        controller.setIntent(.error, reason: "debugStress.retarget", time: time)
        let afterRetarget = controller.advance(time: time)
        let continuityError = Self.maximumChannelDifference(
            beforeRetarget.channels,
            afterRetarget.channels
        )
        let progressBeforePause = afterRetarget.transitionProgress
        let afterPause = controller.advance(time: time + 1_800)
        let pauseProgressStep = afterPause.transitionProgress - progressBeforePause
        let passed = finiteChannels
            && rebuildCountBefore == rebuildCountAfter
            && continuityError <= ParticleTuning.Engine.debugContinuityTolerance
            && afterPause.deltaTime <= ParticleTuning.Engine.maximumSimulationStep
            && pauseProgressStep <= ParticleTuning.Engine.debugMaximumPauseProgressStep

        print(
            "[ParticleCore][V2.3Test] passed=\(passed) "
                + "switches=\(ParticleTuning.Engine.debugStressSwitchCount) "
                + "continuityError=\(String(format: "%.6f", continuityError)) "
                + "resumeDelta=\(String(format: "%.6f", afterPause.deltaTime)) "
                + "resumeProgressStep=\(String(format: "%.6f", pauseProgressStep)) "
                + "particleRebuildCount=\(rebuildCountBefore)->\(rebuildCountAfter)"
        )
    }

    private func advanceDebugAutoCycle(time: TimeInterval) {
        guard isDebugAutoCycleEnabled,
              time >= (debugAutoCycleNextTime ?? time) else {
            return
        }
        debugAutoCycleIndex = (debugAutoCycleIndex + 1)
            % ResidentVisualIntent.allCases.count
        setVisualIntent(
            ResidentVisualIntent.allCases[debugAutoCycleIndex],
            reason: "debugAutoCycle"
        )
        debugAutoCycleNextTime = time + ParticleTuning.Engine.debugAutoCycleInterval
    }

    private static func channelsAreFinite(_ channels: ParticleVisualChannels) -> Bool {
        channels.focus.isFinite
            && channels.pulse.isFinite
            && channels.circulation.isFinite
            && channels.disruption.isFinite
            && channels.dissolution.isFinite
    }

    private static func maximumChannelDifference(
        _ lhs: ParticleVisualChannels,
        _ rhs: ParticleVisualChannels
    ) -> Float {
        max(
            abs(lhs.focus - rhs.focus),
            abs(lhs.pulse - rhs.pulse),
            abs(lhs.circulation - rhs.circulation),
            abs(lhs.disruption - rhs.disruption),
            abs(lhs.dissolution - rhs.dissolution)
        )
    }
    #endif

    private func makeUniforms(
        from frame: ParticleSimulationFrame
    ) -> ParticleFrameUniforms {
        let tuning = frame.tuning
        let visualState = frame.visualState
        let colorProfile = frame.colorProfile
        let pointSize = ParticleTuning.Engine.amplifiedValue(
            tuning.pointSizeScale,
            minimum: ParticleTuning.Engine.minimumPointSize,
            maximum: ParticleTuning.Engine.maximumPointSize
        )
        let brightness = ParticleTuning.Engine.amplifiedValue(
            tuning.brightness,
            minimum: ParticleTuning.Engine.minimumBrightness,
            maximum: ParticleTuning.Engine.maximumBrightness
        )
        return ParticleFrameUniforms(
            viewportAndRender: SIMD4(
                frame.resolution.x,
                frame.resolution.y,
                pointSize,
                brightness
            ),
            interaction: SIMD4(
                frame.mousePosition.x,
                frame.mousePosition.y,
                frame.mouseInfluence,
                ParticleTuning.Engine.projectionScale
            ),
            visualChannelsA: SIMD4(
                visualState.focusStrength,
                visualState.pulseStrength,
                visualState.circulationStrength,
                visualState.disruptionStrength
            ),
            visualChannelsB: SIMD4(
                visualState.dissolutionStrength,
                visualState.transitionElapsedTime,
                Float(simulation.particleCount),
                Float(ParticleTuning.Engine.visualChannelsVersion)
            ),
            baseColor: colorProfile.baseVector,
            ridgeColor: colorProfile.ridgeVector,
            dimColor: colorProfile.dimVector,
            highlightColor: SIMD4(
                colorProfile.highlightVector.x,
                colorProfile.highlightVector.y,
                colorProfile.highlightVector.z,
                Float(colorProfile.alphaScale)
            ),
            renderGeometry: SIMD4(
                ParticleTuning.Engine.depthPointSizeMinimum,
                ParticleTuning.Engine.depthPointSizeMaximum,
                ParticleTuning.Engine.volumePointSizeScale,
                ParticleTuning.Engine.surfacePointSizeScale
            ),
            renderChannels: SIMD4(
                ParticleTuning.Engine.focusPointSizeReduction,
                ParticleTuning.Engine.pulsePointSizeIncrease,
                ParticleTuning.Engine.channelBrightnessRange,
                ParticleTuning.Engine.disruptionBrightnessReduction
            ),
            renderAlpha: SIMD4(
                ParticleTuning.Engine.minimumDissolutionAlpha,
                ParticleTuning.Engine.volumeAlpha,
                ParticleTuning.Engine.surfaceAlpha,
                ParticleTuning.Engine.coreAlphaWeight
            ),
            renderPoint: SIMD4(
                ParticleTuning.Engine.pointCoreStart,
                ParticleTuning.Engine.pointCoreEnd,
                ParticleTuning.Engine.pointHaloStart,
                ParticleTuning.Engine.pointHaloEnd
            ),
            renderLight: SIMD4(
                ParticleTuning.Engine.keyLightDirection.x,
                ParticleTuning.Engine.keyLightDirection.y,
                ParticleTuning.Engine.keyLightDirection.z,
                ParticleTuning.Engine.haloAlphaWeight
            ),
            renderColor: SIMD4(
                ParticleTuning.Engine.frontDepthScale,
                ParticleTuning.Engine.surfaceColorBaseMix,
                ParticleTuning.Engine.surfaceColorLightMix,
                ParticleTuning.Engine.highlightColorMix
            ),
            viewOrientation: viewOrientation.quaternion
        )
    }

    private func uploadParticles() {
        let payloads = simulation.vertexPayloads
        let byteCount = MemoryLayout<SIMD4<Float>>.stride * payloads.count
        guard byteCount <= particleBuffer.length else {
            print(
                "[ParticleCore] particle upload skipped "
                    + "bytes=\(byteCount) capacity=\(particleBuffer.length)"
            )
            return
        }
        payloads.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(particleBuffer.contents(), baseAddress, byteCount)
        }
    }

    private func publishDebugMetricsIfNeeded(
        view: MTKView,
        renderElapsedTime: Float,
        frame: ParticleSimulationFrame,
        time: TimeInterval
    ) {
        let interval = time - metricsStartTime
        guard interval >= ParticleTuning.Engine.metricsInterval else { return }

        let fps = Double(metricsFrameCount) / max(interval, 0.001)
        metricsFrameCount = 0
        metricsStartTime = time

        let visualState = frame.visualState
        let drawableSize = "\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height))"
        let interactionActive = frame.mouseInfluence > 0.01
        let metrics = ParticleRenderMetrics(
            fps: fps,
            particleCount: simulation.particleCount,
            drawableSize: drawableSize,
            preferredFramesPerSecond: view.preferredFramesPerSecond,
            currentVisualState: visualState.currentIntent.rawValue,
            targetVisualState: visualState.targetIntent.rawValue,
            renderElapsedTime: Double(renderElapsedTime),
            motionElapsedTime: Double(frame.motionElapsedTime),
            frameDeltaTime: Double(visualState.deltaTime),
            stateElapsedTime: Double(visualState.transitionElapsedTime),
            transitionDuration: Double(visualState.transitionDuration),
            transitionProgress: Double(visualState.transitionProgress),
            lastTransitionReason: visualState.transitionReason,
            mouseInfluenceEnabled: true,
            mouseInsideParticleArea: interactionActive,
            interactionStrength: Double(frame.mouseInfluence)
        )
        debugMetricsHandler?(metrics)
        print(
            "[ParticleCore] snapshot "
                + "fps=\(String(format: "%.1f", fps)) "
                + "particleCount=\(simulation.particleCount) "
                + "drawableSize=\(drawableSize) "
                + "currentIntent=\(visualState.currentIntent.rawValue) "
                + "targetIntent=\(visualState.targetIntent.rawValue) "
                + "deltaTime=\(String(format: "%.4f", visualState.deltaTime)) "
                + "transitionProgress=\(String(format: "%.3f", visualState.transitionProgress)) "
                + "transitionElapsedTime=\(String(format: "%.2f", visualState.transitionElapsedTime)) "
                + "reason=\(visualState.transitionReason) "
                + "interactionStrength=\(String(format: "%.2f", frame.mouseInfluence)) "
                + "manualRotation=\(isManualRotationEnabled) "
                + "orientation=\(Self.orientationDescription(viewOrientation)) "
                + "centerDrift=\(String(format: "%.6f", frame.stability.centerDrift)) "
                + "maximumRadius=\(String(format: "%.4f", frame.stability.maximumRadius)) "
                + "maximumSpeed=\(String(format: "%.4f", frame.stability.maximumSpeed))"
        )
    }

    private static func orientationDescription(
        _ orientation: ParticleViewOrientation
    ) -> String {
        let value = orientation.quaternion
        return String(
            format: "[%.3f,%.3f,%.3f,%.3f]",
            value.x,
            value.y,
            value.z,
            value.w
        )
    }

    private static func arcballVector(_ point: SIMD2<Float>) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(point)
        if lengthSquared <= 1 {
            return SIMD3<Float>(
                point.x,
                point.y,
                sqrt(max(0, 1 - lengthSquared))
            )
        }

        let normalized = simd_normalize(point)
        return SIMD3<Float>(normalized.x, normalized.y, 0)
    }
}
