import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

struct ParticleFrameUniforms {
    var time: Float
    var breathing: Float
    var edgeBreathing: Float
    var coreStability: Float
    var resolution: SIMD2<Float>
    var seed: UInt32
    var particleCount: UInt32
    var mousePosition: SIMD2<Float>
    var mouseVelocity: SIMD2<Float>
    var mouseInfluence: Float
    var visualChannelsVersion: UInt32
    var focusStrength: Float
    var pulseStrength: Float
    var circulationStrength: Float
    var disruptionStrength: Float
    var dissolutionStrength: Float
    var transitionElapsedTime: Float
    var globalScale: Float
    var pointSizeScale: Float
    var brightness: Float
    var alphaScale: Float
    var ridgeStrength: Float
    var ridgeWidth: Float
    var ridgeBreakup: Float
    var ridgeSeed: Float
    var ridgeFlowBinding: Float
    var breathingAmount: Float
    var breathingTime: Float
    var flowStrength: Float
    var flowTime: Float
    var flowDirection: Float
    var flowSeed: Float
    var flowBrightnessStrength: Float
    var rotationSpeed: Float
    var rotationDirection: Float
    var edgeDustAmount: Float
    var edgeFrayAmount: Float
    var surfaceLightStrength: Float
    var baseColor: SIMD4<Float>
    var ridgeColor: SIMD4<Float>
    var dimColor: SIMD4<Float>
    var highlightColor: SIMD4<Float>
    var colorAlphaScale: Float
}

final class ParticleRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var particleBuffer: MTLBuffer
    private let uniformsBuffer: MTLBuffer
    private let startTime: TimeInterval
    private let frameSeed: UInt32
    private let stateController: ParticleStateController
    private var simulation: ParticleSimulation
    private var pendingModelRebuild: DispatchWorkItem?
    private var metricsStartTime: TimeInterval
    private var metricsFrameCount = 0
    private var metricsFlowStepMin = Float.greatestFiniteMagnitude
    private var metricsFlowStepMax: Float = 0
    private var metricsFlowStepNegativeCount = 0
    var debugMetricsHandler: ((ParticleRenderMetrics) -> Void)?

    init?(device: MTLDevice, visualIntent: ResidentVisualIntent = .idle) {
        let now = CACurrentMediaTime()
        let flowSeed = UInt64.random(in: 1...UInt64.max)
        let simulation = ParticleSimulation(time: now)
        let stateController = ParticleStateController(intent: visualIntent, time: now)

        self.device = device
        self.startTime = now
        self.metricsStartTime = now
        self.frameSeed = UInt32(truncatingIfNeeded: flowSeed ^ (flowSeed >> 32))
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
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                  descriptor: renderPassDescriptor
              ) else { return }

        let now = CACurrentMediaTime()
        let visualState = stateController.advance(time: now)
        let frame = simulation.advance(
            time: now,
            drawableSize: view.drawableSize,
            visualState: visualState
        )
        trackFlowStep(frame.flowStep)
        var uniforms = makeUniforms(from: frame)
        memcpy(
            uniformsBuffer.contents(),
            &uniforms,
            MemoryLayout<ParticleFrameUniforms>.stride
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(
            type: .point,
            vertexStart: 0,
            vertexCount: simulation.particleCount
        )
        publishDebugMetricsIfNeeded(
            view: view,
            renderElapsedTime: Float(now - startTime),
            frame: frame,
            time: now
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
        let previousIntent = stateController.currentIntent
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

    private func makeUniforms(
        from frame: ParticleSimulationFrame
    ) -> ParticleFrameUniforms {
        let tuning = frame.tuning
        let colorProfile = frame.colorProfile
        return ParticleFrameUniforms(
            time: frame.motionElapsedTime,
            breathing: frame.breathing,
            edgeBreathing: frame.edgeBreathing,
            coreStability: frame.coreStability,
            resolution: frame.resolution,
            seed: frameSeed,
            particleCount: UInt32(simulation.particleCount),
            mousePosition: frame.mousePosition,
            mouseVelocity: frame.mouseVelocity,
            mouseInfluence: frame.mouseInfluence,
            visualChannelsVersion: ParticleTuning.Engine.visualChannelsVersion,
            focusStrength: frame.visualState.focusStrength,
            pulseStrength: frame.visualState.pulseStrength,
            circulationStrength: frame.visualState.circulationStrength,
            disruptionStrength: frame.visualState.disruptionStrength,
            dissolutionStrength: frame.visualState.dissolutionStrength,
            transitionElapsedTime: frame.visualState.transitionElapsedTime,
            globalScale: Float(tuning.globalScale),
            pointSizeScale: Float(tuning.pointSizeScale),
            brightness: Float(tuning.brightness),
            alphaScale: Float(tuning.alphaScale),
            ridgeStrength: Float(tuning.ridgeBrightness),
            ridgeWidth: Float(tuning.ridgeWidth),
            ridgeBreakup: Float(tuning.ridgeBreakup),
            ridgeSeed: Float(tuning.ridgeSeed),
            ridgeFlowBinding: Float(tuning.ridgeFlowBinding),
            breathingAmount: frame.breathingAmount,
            breathingTime: frame.breathingTime,
            flowStrength: Float(tuning.flowStrength),
            flowTime: frame.flowTime,
            flowDirection: Float(tuning.flowDirection),
            flowSeed: Float(tuning.flowSeed),
            flowBrightnessStrength: Float(tuning.flowBrightnessStrength),
            rotationSpeed: Float(tuning.rotationSpeed),
            rotationDirection: Float(tuning.rotationDirection),
            edgeDustAmount: Float(tuning.edgeDustAmount),
            edgeFrayAmount: Float(tuning.edgeFrayAmount),
            surfaceLightStrength: Float(tuning.surfaceLightStrength),
            baseColor: colorProfile.baseVector,
            ridgeColor: colorProfile.ridgeVector,
            dimColor: colorProfile.dimVector,
            highlightColor: colorProfile.highlightVector,
            colorAlphaScale: Float(colorProfile.alphaScale)
        )
    }

    private func uploadParticles() {
        let payloads = simulation.vertexPayloads
        let pointer = particleBuffer.contents().bindMemory(
            to: SIMD4<Float>.self,
            capacity: payloads.count
        )
        for (index, payload) in payloads.enumerated() {
            pointer[index] = payload
        }
    }

    private func rebuildParticles() {
        simulation.rebuildParticles()
        let payloads = simulation.vertexPayloads
        guard let rebuiltBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD4<Float>>.stride * payloads.count,
            options: .storageModeShared
        ) else {
            print("[ParticleCore] model rebuild buffer failed")
            return
        }

        particleBuffer = rebuiltBuffer
        uploadParticles()
        let tuning = simulation.tuning
        print(
            "[ParticleCore] simulation rebuilt "
                + "shapeStrength=\(String(format: "%.2f", tuning.shapeStrength)) "
                + "scatterStrength=\(String(format: "%.2f", tuning.scatterStrength))"
        )
    }

    private func trackFlowStep(_ flowStep: Float) {
        metricsFlowStepMin = min(metricsFlowStepMin, flowStep)
        metricsFlowStepMax = max(metricsFlowStepMax, flowStep)
        if flowStep < 0 {
            metricsFlowStepNegativeCount += 1
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
        let flowStepMin = metricsFlowStepMin == Float.greatestFiniteMagnitude
            ? 0
            : metricsFlowStepMin
        let flowStepMax = metricsFlowStepMax
        let flowStepNegativeCount = metricsFlowStepNegativeCount
        metricsFlowStepMin = Float.greatestFiniteMagnitude
        metricsFlowStepMax = 0
        metricsFlowStepNegativeCount = 0

        let visualState = frame.visualState
        let drawableSize = "\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height))"
        let interactionActive = frame.mouseInfluence > 0.01
        let metrics = ParticleRenderMetrics(
            fps: fps,
            particleCount: simulation.particleCount,
            drawableSize: drawableSize,
            preferredFramesPerSecond: view.preferredFramesPerSecond,
            currentVisualState: visualState.currentIntent.rawValue,
            previousVisualState: visualState.previousIntent.rawValue,
            renderElapsedTime: Double(renderElapsedTime),
            motionElapsedTime: Double(frame.motionElapsedTime),
            stateElapsedTime: Double(visualState.transitionElapsedTime),
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
                + "visualIntent=\(visualState.currentIntent.rawValue) "
                + "previous=\(visualState.previousIntent.rawValue) "
                + "transitionElapsedTime=\(String(format: "%.2f", visualState.transitionElapsedTime)) "
                + "reason=\(visualState.transitionReason) "
                + "interactionStrength=\(String(format: "%.2f", frame.mouseInfluence)) "
                + "flowTime=\(String(format: "%.3f", frame.flowTime)) "
                + "flowStepMin=\(String(format: "%.5f", flowStepMin)) "
                + "flowStepMax=\(String(format: "%.5f", flowStepMax)) "
                + "flowStepNegativeCount=\(flowStepNegativeCount)"
        )
    }
}
